class_name Player
extends Area2D
## Player ship: chases the cursor with a speed-capped exponential approach.
##
## Per physics tick: step = min(dist * (1 - exp(-gain * delta)), max_speed * delta)
## along the offset to the clamped target. gain is solved once in _ready() so the
## continuous model covers chase_ref_distance_px (to within ARRIVE_EPS_PX) in
## chase_ref_time_s. The ship never rotates.

## The chase counts as arrived within this many pixels when solving the gain.
const ARRIVE_EPS_PX: float = 1.0
const GAIN_MIN: float = 1.0
const GAIN_MAX: float = 10000.0
const GAIN_SOLVE_ITERATIONS: int = 40

var _max_speed: float
var _gain: float
var _bounds_min: Vector2
var _bounds_max: Vector2

@onready var _hurtbox: CollisionShape2D = $Hurtbox
@onready var _sprite: Sprite2D = $Sprite


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


func _physics_process(delta: float) -> void:
	step_toward(get_global_mouse_position(), delta)


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
