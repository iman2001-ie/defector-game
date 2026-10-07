class_name ShakeCamera
extends Camera2D
## Level camera with screen shake. Registers with Feedback on entering the tree
## (unregisters on exit); Feedback calls shake().
##
## Keeps the strongest active shake: amplitude decays linearly to 0 over its
## duration, and every frame the offset jumps to a random point in the square
## +-current_amplitude(). Runs while the tree is paused (process always) but
## holds still and keeps its remaining time while PauseArbiter reports a pause.
## Under hit-stop delta is 0, so the shake keeps jittering without decaying.

## Remaining time below this counts as finished (absorbs float drift).
const IDLE_EPS_S: float = 1e-6

var _amplitude: float = 0.0
var _duration: float = 0.0
var _remaining: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()


func _enter_tree() -> void:
	Feedback.register_camera(self)


func _exit_tree() -> void:
	Feedback.unregister_camera(self)


func _process(delta: float) -> void:
	step(delta)


## Starts a shake unless either value is not positive or a stronger shake is active.
func shake(amplitude_px: float, duration_s: float) -> void:
	if amplitude_px <= 0.0 or duration_s <= 0.0:
		return
	if amplitude_px < current_amplitude():
		return
	_amplitude = amplitude_px
	_duration = duration_s
	_remaining = duration_s


## Amplitude now: the start amplitude scaled by the remaining fraction (0 when idle).
func current_amplitude() -> float:
	if _remaining <= 0.0 or _duration <= 0.0:
		return 0.0
	return _amplitude * _remaining / _duration


## One frame of shake (public so tests can drive it).
func step(delta: float) -> void:
	if PauseArbiter.is_paused():
		offset = Vector2.ZERO
		return
	if _remaining > 0.0:
		_remaining -= delta
		if _remaining <= IDLE_EPS_S:
			_remaining = 0.0
	var amp: float = current_amplitude()
	if amp > 0.0:
		offset = Vector2(_rng.randf_range(-amp, amp), _rng.randf_range(-amp, amp))
	else:
		offset = Vector2.ZERO
