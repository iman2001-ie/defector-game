class_name PlayerWeapons
extends Node
## The Player's laser and missile. A child of the Player scene; the Player
## drives it each physics tick and keeps the public weapon API as delegators.
##
## Laser: while held, one bolt per 1 / weapons.laser.rate_per_s is spawned at the
## muzzle through the injected Spawner, with a muzzle flash.
##
## Missile: a press launches one missile at the muzzle, always straight up
## (Vector2.UP * weapons.missile.speed_px_s), then a cooldown_s cooldown broadcast
## as a ratio through Events.missile_cooldown_changed (1 = just fired, 0 = ready).
##
## Barrage volley (Story 3.5): start_barrage() launches abilities.barrage.missiles
## micro-missiles, the first at once and then one every duration_s / missiles,
## counted down from physics delta in step_barrage (frozen under pause and
## hit-stop). Each launch spawns a MicroMissile at the muzzle flying straight up
## (it homes by itself), plays the whoosh and flashes the muzzle. The tick of the
## last launch also plays the LARGE impact feedback at the muzzle, once. The
## Player owns the energy, denial and death rules; it calls stop_barrage on death.
##
## Control hints (Story 5.8): a spawned laser bolt emits
## Events.player_action(&"laser") and a spawned missile &"missile"; the barrage
## volley's micro-missiles never emit.

## Absorbs float drift so whole multiples of the physics delta add up to one interval.
const FIRE_EPS: float = 1e-6
const LASER_TYPE: StringName = &"laser_bolt"
const MISSILE_TYPE: StringName = &"missile"
## Seconds the muzzle flash shows after a missile launch (art constant).
const MISSILE_FLASH_S: float = 0.05
const LASER_SFX: StringName = &"laser_zap"
const MISSILE_SFX: StringName = &"missile_launch"
const MICRO_TYPE: StringName = &"micro_missile"
## Playtest pt7-h: each left/right launch pair's share of launch_fan_deg, in turn.
const FAN_SPREAD: Array[float] = [1.0, 0.55, 0.8]
const WHOOSH_SFX: StringName = &"barrage_whoosh"
## Events.player_action ids (Story 5.8).
const ACTION_LASER: StringName = &"laser"
const ACTION_MISSILE: StringName = &"missile"

## Where projectiles spawn (resolved once in _ready).
@export var muzzle: NodePath
## Shown briefly on each shot (resolved once in _ready).
@export var muzzle_flash: NodePath

var _laser_damage: int
var _laser_speed: float
var _fire_interval: float = INF
## Seconds until the next bolt may fire; may dip below 0 while held (carried, no drift).
var _fire_cooldown: float = 0.0
var _flash_left: float = 0.0
var _laser_pitch_jitter: float = 0.0

var _missile_damage: int
var _missile_speed: float
var _missile_cooldown_s: float
## Seconds until the missile is ready; 0 when ready.
var _missile_cooldown: float = 0.0
var _spawner: Spawner

var _barrage_missiles: int = 0
var _barrage_interval: float = 0.0
var _barrage_damage: int = 0
var _barrage_speed: float = 0.0
var _barrage_valid: bool = false
## Micro-missiles still to launch in the running volley; 0 when idle.
var _barrage_left: int = 0
## Seconds until the next launch; carried (no drift) like the laser cooldown.
var _barrage_cooldown: float = 0.0
## Playtest pt7-h: the launch fan's half-angle and the volley's launch count.
var _barrage_fan_deg: float = 0.0
var _barrage_launched: int = 0

var _muzzle: Node2D
var _muzzle_flash: Node2D


func _ready() -> void:
	_muzzle = get_node_or_null(muzzle) as Node2D
	_muzzle_flash = get_node_or_null(muzzle_flash) as Node2D
	if _muzzle == null or _muzzle_flash == null:
		Log.error("combat", "PlayerWeapons '%s' is missing its muzzle or muzzle flash; weapons disabled" % name)

	_laser_damage = Config.int_("weapons.laser.damage")
	_laser_speed = Config.num("weapons.laser.speed_px_s")
	var rate: float = Config.num("weapons.laser.rate_per_s")
	if rate > 0.0:
		_fire_interval = 1.0 / rate
	else:
		Log.warn("data", "weapons.laser.rate_per_s %.3f is not positive; laser disabled" % rate)
	_laser_pitch_jitter = Config.num("weapons.laser.sfx_pitch_jitter")
	if _muzzle_flash != null:
		_muzzle_flash.visible = false

	_missile_damage = Config.int_("weapons.missile.damage")
	_missile_speed = Config.num("weapons.missile.speed_px_s")
	_missile_cooldown_s = Config.num("weapons.missile.cooldown_s")
	if _missile_cooldown_s <= 0.0:
		Log.warn("data", "weapons.missile.cooldown_s %.3f is not positive; missile has no cooldown" % _missile_cooldown_s)

	_barrage_missiles = Config.int_("abilities.barrage.missiles")
	var barrage_duration: float = Config.num("abilities.barrage.duration_s")
	_barrage_damage = Config.int_("abilities.barrage.damage")
	_barrage_speed = Config.num("abilities.barrage.speed_px_s")
	_barrage_fan_deg = maxf(Config.num("abilities.barrage.launch_fan_deg"), 0.0)
	_barrage_valid = _barrage_missiles > 0 and barrage_duration > 0.0
	if _barrage_valid:
		_barrage_interval = barrage_duration / float(_barrage_missiles)
	else:
		Log.warn("data", "abilities.barrage missiles %d / duration_s %.3f must be positive; barrage fires nothing" % [_barrage_missiles, barrage_duration])


## Without a spawner (or without a muzzle) the weapons do not fire.
func set_spawner(spawner: Spawner) -> void:
	_spawner = spawner


func _can_spawn() -> bool:
	return is_instance_valid(_spawner) and _muzzle != null and _muzzle_flash != null


## One fire tick. The cooldown is checked, then counted down, so a held trigger
## fires on ticks 1, 7, 13, ... at 10/s and 1/60 s. At most one bolt per tick.
## Released (or without a spawner) the cooldown floors at 0: the next press fires at once.
func step_fire(held: bool, delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= FIRE_EPS:
			_flash_left = 0.0
			_muzzle_flash.visible = false
	var can_fire: bool = held and is_finite(_fire_interval) and _can_spawn()
	if can_fire and _fire_cooldown <= FIRE_EPS:
		_fire_cooldown += _fire_interval
		_fire_bolt()
	_fire_cooldown -= delta
	if not can_fire:
		_fire_cooldown = maxf(_fire_cooldown, 0.0)


func _fire_bolt() -> void:
	var bolt: Projectile = _spawner.spawn_projectile(LASER_TYPE, {
		"position": _muzzle.global_position,
		"velocity": Vector2(0.0, -_laser_speed),
		"damage": _laser_damage,
	})
	if bolt == null:
		return
	Audio.play_sfx(LASER_SFX, _laser_pitch_jitter)
	_muzzle_flash.visible = true
	_flash_left = _fire_interval * 0.5
	Events.player_action.emit(ACTION_LASER)


## One missile tick. The cooldown is counted down first (emitting its ratio, the
## last emit exactly 0), then a press fires if the missile is ready, so the 90th
## tick after a launch at 1.5 s and 1/60 s is the first that can fire again.
## Presses during the cooldown are dropped, not buffered. The missile spawns at
## the muzzle and flies straight up.
func step_missile(pressed: bool, delta: float) -> void:
	if _missile_cooldown > 0.0:
		_missile_cooldown -= delta
		if _missile_cooldown <= FIRE_EPS:
			_missile_cooldown = 0.0
		Events.missile_cooldown_changed.emit(_missile_cooldown / _missile_cooldown_s)
	if not pressed or _missile_cooldown > 0.0 or not _can_spawn():
		return
	var missile: Projectile = _spawner.spawn_projectile(MISSILE_TYPE, {
		"position": _muzzle.global_position,
		"velocity": Vector2.UP * _missile_speed,
		"damage": _missile_damage,
	})
	if missile == null:
		return
	Audio.play_sfx(MISSILE_SFX)
	_muzzle_flash.visible = true
	_flash_left = maxf(_flash_left, MISSILE_FLASH_S)
	Events.player_action.emit(ACTION_MISSILE)
	if _missile_cooldown_s <= 0.0:
		return
	_missile_cooldown = _missile_cooldown_s
	Events.missile_cooldown_changed.emit(1.0)


# --- Barrage volley ---------------------------------------------------------------

## True while a volley still has micro-missiles to launch.
func is_barraging() -> bool:
	return _barrage_left > 0


## Micro-missiles still to launch in the running volley (0 when idle).
func barrage_left() -> int:
	return _barrage_left


## Starts a volley and launches the first micro-missile at once. Does nothing
## while a volley runs or when the barrage data is mistuned.
func start_barrage() -> void:
	if not _barrage_valid or _barrage_left > 0:
		return
	_barrage_left = _barrage_missiles
	_barrage_cooldown = 0.0
	_barrage_launched = 0
	_step_launch()


## One volley tick: counts the launch timer down by `delta` and launches when it
## reaches 0, so at 2.0 s / 12 and 1/60 s the launches land on ticks 0, 10, ... 110.
func step_barrage(delta: float) -> void:
	if _barrage_left <= 0:
		return
	_barrage_cooldown -= delta
	_step_launch()


## Ends a running volley at once: no more launches and no finish.
func stop_barrage() -> void:
	_barrage_left = 0
	_barrage_cooldown = 0.0


func _step_launch() -> void:
	if _barrage_left <= 0 or _barrage_cooldown > FIRE_EPS:
		return
	_barrage_cooldown += _barrage_interval
	_barrage_left -= 1
	_launch_micro()
	if _barrage_left == 0 and _muzzle != null:
		Feedback.impact(ImpactTier.LARGE, _muzzle.global_position)


## The launch angle (degrees from straight up, negative to the left) of
## micro-missile `index` in a volley (playtest pt7-h): it alternates left and
## right, cycling through FAN_SPREAD, so a volley fans out evenly and
## predictably within +-fan_deg.
static func fan_angle_deg(index: int, fan_deg: float) -> float:
	var side: float = -1.0 if index % 2 == 0 else 1.0
	return side * fan_deg * FAN_SPREAD[floori(index / 2.0) % FAN_SPREAD.size()]


## One launch. Without a spawner (or on a failed spawn) it still counts but
## plays nothing.
func _launch_micro() -> void:
	if not _can_spawn():
		return
	var angle: float = PlayerWeapons.fan_angle_deg(_barrage_launched, _barrage_fan_deg)
	_barrage_launched += 1
	var micro: Projectile = _spawner.spawn_projectile(MICRO_TYPE, {
		"position": _muzzle.global_position,
		"velocity": Vector2.UP.rotated(deg_to_rad(angle)) * _barrage_speed,
		"damage": _barrage_damage,
	})
	if micro == null:
		return
	Audio.play_sfx(WHOOSH_SFX)
	_muzzle_flash.visible = true
	_flash_left = maxf(_flash_left, MISSILE_FLASH_S)
