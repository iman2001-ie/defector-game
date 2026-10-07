class_name PlayerWeapons
extends Node
## The Player's laser and missile. A child of the Player scene; the Player
## drives it each physics tick and keeps the public weapon API as delegators.
##
## Laser: while held, one bolt per 1 / weapons.laser.rate_per_s is spawned at the
## muzzle through the injected Spawner, with a muzzle flash.
##
## Missile: a press launches one missile at the muzzle along the origin->target
## vector (straight up when the target is within straight_up_within_px), then a
## cooldown_s cooldown broadcast as a ratio through Events.missile_cooldown_changed
## (1 = just fired, 0 = ready).

## Absorbs float drift so whole multiples of the physics delta add up to one interval.
const FIRE_EPS: float = 1e-6
const LASER_TYPE: StringName = &"laser_bolt"
const MISSILE_TYPE: StringName = &"missile"
## Seconds the muzzle flash shows after a missile launch (art constant).
const MISSILE_FLASH_S: float = 0.05
const LASER_SFX: StringName = &"laser_zap"
const MISSILE_SFX: StringName = &"missile_launch"

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
var _missile_straight_up_px: float
## Seconds until the missile is ready; 0 when ready.
var _missile_cooldown: float = 0.0
var _spawner: Spawner

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
	_missile_straight_up_px = Config.num("weapons.missile.straight_up_within_px")
	if _missile_cooldown_s <= 0.0:
		Log.warn("data", "weapons.missile.cooldown_s %.3f is not positive; missile has no cooldown" % _missile_cooldown_s)


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


## One missile tick. The cooldown is counted down first (emitting its ratio, the
## last emit exactly 0), then a press fires if the missile is ready, so the 90th
## tick after a launch at 1.5 s and 1/60 s is the first that can fire again.
## Presses during the cooldown are dropped, not buffered. origin is the ship
## position the aim is measured from; the missile itself spawns at the muzzle.
func step_missile(pressed: bool, origin: Vector2, target: Vector2, delta: float) -> void:
	if _missile_cooldown > 0.0:
		_missile_cooldown -= delta
		if _missile_cooldown <= FIRE_EPS:
			_missile_cooldown = 0.0
		Events.missile_cooldown_changed.emit(_missile_cooldown / _missile_cooldown_s)
	if not pressed or _missile_cooldown > 0.0 or not _can_spawn():
		return
	var missile: Projectile = _spawner.spawn_projectile(MISSILE_TYPE, {
		"position": _muzzle.global_position,
		"velocity": missile_direction(origin, target, _missile_straight_up_px) * _missile_speed,
		"damage": _missile_damage,
	})
	if missile == null:
		return
	Audio.play_sfx(MISSILE_SFX)
	_muzzle_flash.visible = true
	_flash_left = maxf(_flash_left, MISSILE_FLASH_S)
	if _missile_cooldown_s <= 0.0:
		return
	_missile_cooldown = _missile_cooldown_s
	Events.missile_cooldown_changed.emit(1.0)


## Unit direction from the ship toward the cursor; straight up within straight_up_within px.
static func missile_direction(from: Vector2, target: Vector2, straight_up_within: float) -> Vector2:
	if from.distance_to(target) <= straight_up_within:
		return Vector2.UP
	return (target - from).normalized()
