class_name Player
extends Area2D
## Player ship: chases the cursor with a speed-capped exponential approach.
##
## Per physics tick: step = min(dist * (1 - exp(-gain * delta)), max_speed * delta)
## along the offset to the clamped target. gain is solved once in _ready() so the
## continuous model covers chase_ref_distance_px (to within ARRIVE_EPS_PX) in
## chase_ref_time_s. The ship never rotates.
##
## Laser: while fire_laser is held, one bolt per 1 / weapons.laser.rate_per_s is
## spawned at the Muzzle through the injected Spawner, with a muzzle flash.
##
## Missile: a fire_missile press launches one missile at the Muzzle along the
## ship->cursor vector (straight up when the cursor is within
## straight_up_within_px), then a cooldown_s cooldown broadcast as a ratio
## through Events.missile_cooldown_changed (1 = just fired, 0 = ready).

## The chase counts as arrived within this many pixels when solving the gain.
const ARRIVE_EPS_PX: float = 1.0
const GAIN_MIN: float = 1.0
const GAIN_MAX: float = 10000.0
const GAIN_SOLVE_ITERATIONS: int = 40
## Absorbs float drift so whole multiples of the physics delta add up to one interval.
const FIRE_EPS: float = 1e-6
const LASER_TYPE: StringName = &"laser_bolt"
const MISSILE_TYPE: StringName = &"missile"

var _max_speed: float
var _gain: float
var _bounds_min: Vector2
var _bounds_max: Vector2

var _laser_damage: int
var _laser_speed: float
var _fire_interval: float = INF
## Seconds until the next bolt may fire; may dip below 0 while held (carried, no drift).
var _fire_cooldown: float = 0.0
var _flash_left: float = 0.0

var _missile_damage: int
var _missile_speed: float
var _missile_cooldown_s: float
var _missile_straight_up_px: float
## Seconds until the missile is ready; 0 when ready.
var _missile_cooldown: float = 0.0
var _spawner: Spawner

@onready var _hurtbox: CollisionShape2D = $Hurtbox
@onready var _sprite: Sprite2D = $Sprite
@onready var _muzzle: Marker2D = $Muzzle
@onready var _muzzle_flash: Node2D = $Muzzle/MuzzleFlash


func _ready() -> void:
	_max_speed = Config.num("player.max_speed")
	var ref_distance: float = Config.num("player.chase_ref_distance_px")
	var ref_time: float = Config.num("player.chase_ref_time_s")
	if not is_ref_time_feasible(_max_speed, ref_distance, ref_time):
		Log.warn("data", "player.chase_ref_time_s %.3f is unreachable at max_speed %.0f for %.0f px; using pure capped chase" % [ref_time, _max_speed, ref_distance])
	_gain = solve_chase_gain(_max_speed, ref_distance, ref_time)

	var width: float = float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	_bounds_min = Vector2(0.0, Config.num("player.bounds_y.min"))
	_bounds_max = Vector2(width, Config.num("player.bounds_y.max"))

	var hurtbox_circle: CircleShape2D = _hurtbox.shape as CircleShape2D
	if hurtbox_circle != null:
		hurtbox_circle.radius = Config.num("player.hurtbox_diameter_px") / 2.0
	var placeholder: GradientTexture2D = _sprite.texture as GradientTexture2D
	if placeholder != null:
		var px: int = Config.int_("player.sprite_px")
		placeholder.width = px
		placeholder.height = px

	_laser_damage = Config.int_("weapons.laser.damage")
	_laser_speed = Config.num("weapons.laser.speed_px_s")
	var rate: float = Config.num("weapons.laser.rate_per_s")
	if rate > 0.0:
		_fire_interval = 1.0 / rate
	else:
		Log.warn("data", "weapons.laser.rate_per_s %.3f is not positive; laser disabled" % rate)
	_muzzle_flash.visible = false

	_missile_damage = Config.int_("weapons.missile.damage")
	_missile_speed = Config.num("weapons.missile.speed_px_s")
	_missile_cooldown_s = Config.num("weapons.missile.cooldown_s")
	_missile_straight_up_px = Config.num("weapons.missile.straight_up_within_px")
	if _missile_cooldown_s <= 0.0:
		Log.warn("data", "weapons.missile.cooldown_s %.3f is not positive; missile has no cooldown" % _missile_cooldown_s)


func _physics_process(delta: float) -> void:
	step_toward(get_global_mouse_position(), delta)
	step_fire(Input.is_action_pressed(&"fire_laser"), delta)
	step_missile(Input.is_action_just_pressed(&"fire_missile"), get_global_mouse_position(), delta)


## Injected by the scene root. Without a spawner the ship does not fire.
func set_spawner(spawner: Spawner) -> void:
	_spawner = spawner


## One fire tick. The cooldown is checked, then counted down, so a held trigger
## fires on ticks 1, 7, 13, ... at 10/s and 1/60 s. At most one bolt per tick.
## Released (or without a spawner) the cooldown floors at 0: the next press fires at once.
func step_fire(held: bool, delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= FIRE_EPS:
			_flash_left = 0.0
			_muzzle_flash.visible = false
	var can_fire: bool = held and is_finite(_fire_interval) and is_instance_valid(_spawner)
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
	_muzzle_flash.visible = true
	_flash_left = _fire_interval * 0.5


## One missile tick. The cooldown is counted down first (emitting its ratio, the
## last emit exactly 0), then a press fires if the missile is ready, so the 90th
## tick after a launch at 1.5 s and 1/60 s is the first that can fire again.
## Presses during the cooldown are dropped, not buffered.
func step_missile(pressed: bool, target: Vector2, delta: float) -> void:
	if _missile_cooldown > 0.0:
		_missile_cooldown -= delta
		if _missile_cooldown <= FIRE_EPS:
			_missile_cooldown = 0.0
		Events.missile_cooldown_changed.emit(_missile_cooldown / _missile_cooldown_s)
	if not pressed or _missile_cooldown > 0.0 or not is_instance_valid(_spawner):
		return
	var missile: Projectile = _spawner.spawn_projectile(MISSILE_TYPE, {
		"position": _muzzle.global_position,
		"velocity": missile_direction(global_position, target, _missile_straight_up_px) * _missile_speed,
		"damage": _missile_damage,
	})
	if missile == null or _missile_cooldown_s <= 0.0:
		return
	_missile_cooldown = _missile_cooldown_s
	Events.missile_cooldown_changed.emit(1.0)


## Unit direction from the ship toward the cursor; straight up within straight_up_within px.
static func missile_direction(from: Vector2, target: Vector2, straight_up_within: float) -> Vector2:
	if from.distance_to(target) <= straight_up_within:
		return Vector2.UP
	return (target - from).normalized()


## One chase tick toward target. Both the target and the result are clamped.
func step_toward(target: Vector2, delta: float) -> void:
	var clamped_target: Vector2 = clamp_to_bounds(target)
	var start: Vector2 = clamp_to_bounds(global_position)
	global_position = clamp_to_bounds(chase_step(start, clamped_target, delta, _max_speed, _gain))


## Clamps the ship centre to x 0..viewport width, y bounds_y.min..max.
func clamp_to_bounds(p: Vector2) -> Vector2:
	return p.clamp(_bounds_min, _bounds_max)


static func chase_step(from: Vector2, target: Vector2, delta: float, max_speed: float, gain: float) -> Vector2:
	var offset: Vector2 = target - from
	var dist: float = offset.length()
	if dist <= 0.0:
		return target
	var step: float = minf(dist * (1.0 - exp(-gain * delta)), max_speed * delta)
	return from + offset / dist * step


## True when some gain can cover ref_distance in ref_time at max_speed.
static func is_ref_time_feasible(max_speed: float, ref_distance: float, ref_time: float) -> bool:
	return ref_time > ref_distance / max_speed


## Bisects the gain so the continuous chase covers ref_distance in ref_time.
## Returns GAIN_MAX (pure capped chase) when no gain fits.
static func solve_chase_gain(max_speed: float, ref_distance: float, ref_time: float) -> float:
	if not is_ref_time_feasible(max_speed, ref_distance, ref_time):
		return GAIN_MAX
	var lo: float = GAIN_MIN
	var hi: float = GAIN_MAX
	for i: int in GAIN_SOLVE_ITERATIONS:
		var mid: float = (lo + hi) * 0.5
		if _cover_time(max_speed, ref_distance, mid) > ref_time:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## Time for the continuous model to get within ARRIVE_EPS_PX of a target d px away:
## capped phase until dist == v / g, then exponential down to the epsilon.
static func _cover_time(v: float, d: float, g: float) -> float:
	var d_cap: float = v / g
	if d_cap >= d:
		return log(d / ARRIVE_EPS_PX) / g
	return (d - d_cap) / v + log(d_cap / ARRIVE_EPS_PX) / g
