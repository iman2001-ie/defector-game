class_name EnergyOrb
extends Area2D
## A gold energy orb dropped from wreckage (Story 3.3, GDD Energy). It drifts
## down at energy.orb_drift_px_s; while the living ship is within
## energy.orb_magnet_radius_px (inclusive) it flies at the ship at
## energy.orb_magnet_speed_px_s instead, never overshooting. It frees itself
## after energy.orb_despawn_s of physics time or once fully below the playfield.
##
## Layer `pickups`, mask 0: the Player's hurtbox detects the orb and calls
## collect(), which adds energy.orb_value through GameState once.
##
## Playtest pt7-e: the pickup chime plays at energy.orb_sfx.volume_db through
## Audio.play_sfx_solo, so a burst of pickups never stacks. A pickup within
## streak_window_s (real time) of the previous one is one streak step higher in
## pitch (streak_pitch_step per step, at most streak_max_steps); a longer gap
## starts again at the base pitch. The streak is shared by every orb.
##
## Created only by Spawner: setup(params) stores values before add_child, and
## _ready() applies them.

## The lowest pitch a pickup plays at, whatever streak_pitch_step is tuned to.
const MIN_PICKUP_PITCH: float = 0.1

## The pickup streak (shared): when the last pickup played (real-time msec,
## -1 before any) and how many steps the next one is above the base pitch.
static var _last_pickup_msec: int = -1
static var _streak_step: int = 0

var value: int = 0
var drift_speed: float = 0.0
var magnet_radius: float = 0.0
var magnet_speed: float = 0.0
var despawn_s: float = 0.0
var diameter: float = 0.0
## Physics time since _ready.
var age: float = 0.0

var _spawn_position: Vector2 = Vector2.ZERO
var _has_spawn_position: bool = false
var _collected: bool = false
## The ship, looked up once in _ready (no per-frame group lookups).
var _player: Player = null


## Stores params; nothing is applied until _ready(). Keys: position (global).
func setup(params: Dictionary) -> void:
	if params.has("position"):
		_spawn_position = params["position"] as Vector2
		_has_spawn_position = true


func _ready() -> void:
	if _has_spawn_position:
		global_position = _spawn_position
	value = Config.int_("energy.orb_value")
	drift_speed = Config.num("energy.orb_drift_px_s")
	magnet_radius = maxf(Config.num("energy.orb_magnet_radius_px"), 0.0)
	magnet_speed = Config.num("energy.orb_magnet_speed_px_s")
	despawn_s = Config.num("energy.orb_despawn_s")
	diameter = maxf(Config.num("energy.orb_diameter_px"), 0.0)
	var hitbox: CollisionShape2D = get_node_or_null(^"Hitbox") as CollisionShape2D
	if hitbox != null:
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = diameter / 2.0
		hitbox.shape = circle
	var sprite: Sprite2D = get_node_or_null(^"Sprite") as Sprite2D
	if sprite != null:
		var texture: GradientTexture2D = sprite.texture as GradientTexture2D
		# The texture is shared by every orb: only resize it when tuning changed.
		if texture != null and diameter >= 1.0 and (texture.width != int(diameter) or texture.height != int(diameter)):
			texture.width = int(diameter)
			texture.height = int(diameter)
	add_to_group(Groups.PICKUPS)
	_player = get_tree().get_first_node_in_group(Groups.PLAYER) as Player


func _physics_process(delta: float) -> void:
	step(delta)


## One tick: ages the orb (freed at despawn_s), then magnet or drift, then
## frees it once it is fully below the playfield.
func step(delta: float) -> void:
	if _collected or is_queued_for_deletion():
		return
	age += delta
	if age >= despawn_s:
		queue_free()
		return
	if is_magnet_target_in_range():
		global_position = global_position.move_toward(_player.global_position, magnet_speed * delta)
	else:
		global_position.y += drift_speed * delta
	if global_position.y - diameter / 2.0 > Playfield.SIZE.y:
		queue_free()


## True when the cached ship is valid, alive and within magnet_radius (inclusive).
func is_magnet_target_in_range() -> bool:
	if not is_instance_valid(_player) or _player.is_dead():
		return false
	return global_position.distance_squared_to(_player.global_position) <= magnet_radius * magnet_radius


## Adds the orb's energy, plays the pickup sound and frees the orb. Works once:
## returns true the first time, false after.
func collect() -> bool:
	if _collected:
		return false
	_collected = true
	GameState.add_energy(value)
	_play_pickup_sfx()
	queue_free()
	return true


## Clears the pickup streak (tests).
static func reset_pickup_streak() -> void:
	_last_pickup_msec = -1
	_streak_step = 0


## The pitch multiplier of the next pickup at real time `now_msec`, which also
## advances the streak: 1.0 after a gap of more than streak_window_s, else one
## more streak_pitch_step (capped at streak_max_steps).
static func next_pickup_pitch(now_msec: int) -> float:
	var window_ms: float = Config.num("energy.orb_sfx.streak_window_s") * 1000.0
	if _last_pickup_msec >= 0 and float(now_msec - _last_pickup_msec) <= window_ms:
		_streak_step = mini(_streak_step + 1, maxi(Config.int_("energy.orb_sfx.streak_max_steps"), 0))
	else:
		_streak_step = 0
	_last_pickup_msec = now_msec
	return maxf(1.0 + float(_streak_step) * Config.num("energy.orb_sfx.streak_pitch_step"), MIN_PICKUP_PITCH)


func _play_pickup_sfx() -> void:
	var pitch: float = next_pickup_pitch(Time.get_ticks_msec())
	Audio.play_sfx_solo(&"energy_pickup", 0.0, Config.num("energy.orb_sfx.volume_db"), pitch)
