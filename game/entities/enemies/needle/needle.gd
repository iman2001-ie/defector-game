class_name Needle
extends Enemy
## Needle: medium sniper that teaches cover (GDD FR21, FR25, FR6).
##
## A Needle flies (ANCHORING, at enemies.needle.reposition_speed_px_s) to an
## anchor on the top edge (y anchor_y_px plus the spawn's `row_shift_y`, which
## a level that moves its formation rows sets, x from its formation slot) and then
## runs its attack cycle, one start every fire_interval_s:
##   TRACKING  track_s: the targeting line follows the player (enemy colour).
##   LOCKED    lock_s: the line freezes and turns red (the >= 0.3 s telegraph,
##             silent since playtest pt7-e), then one needle_bolt fires along
##             it at bolt_speed_px_s with the needle_fire laser cue.
##   COOLDOWN  fire_interval_s - track_s - lock_s, line hidden.
## After reposition_interval_s anchored it moves, only from COOLDOWN, to a new
## anchor x at least reposition_min_distance_px away along the top edge.
##
## Bolts are requested through `spawner` (injected by Spawner). Without one the
## Needle runs its cycle but never fires. Without a `slot` (the sandbox) the
## anchor is its spawn position.

enum State { ANCHORING, TRACKING, LOCKED, COOLDOWN }

const BOLT_ID: StringName = &"needle_bolt"
## The laser cue played as each bolt fires (playtest pt7-e).
const FIRE_SFX: StringName = &"needle_fire"
## Slack on the reposition check, so float step accumulation can't push the
## move one full cycle later.
const REPOSITION_EPS_S: float = 0.0001
const TRACK_WIDTH_PX: float = 2.0
const LOCK_WIDTH_PX: float = 4.0

## Targeting line while tracking: UX `enemy` #FF2BD6 at half alpha.
@export var track_color: Color = Color("#FF2BD6", 0.5)
## Targeting line once locked: UX `danger` #FF1F4B, opaque.
@export var lock_color: Color = Color("#FF1F4B")

## Picks reposition anchors; tests seed it.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _state: State = State.ANCHORING
## Seconds spent in the current state.
var _t: float = 0.0
## Seconds since the Needle last arrived on an anchor.
var _anchored_t: float = 0.0
var _anchor: Vector2 = Vector2.ZERO
var _line_dir: Vector2 = Vector2.DOWN
var _line_length: float = 0.0
var _min_x: float = 0.0
var _max_x: float = 0.0

var _reposition_interval_s: float = 0.0
var _track_s: float = 0.0
var _lock_s: float = 0.0
var _cooldown_s: float = 0.0
var _bolt_speed: float = 0.0
var _anchor_y: float = 0.0
var _row_shift_y: float = 0.0
var _reposition_speed: float = 0.0
var _min_distance: float = 0.0
var _bolt_damage: int = 1

var _muzzle: Node2D = null
var _line: Line2D = null


func _init() -> void:
	type_id = &"needle"
	rng.randomize()


## Enemy's params (position, slot, entry) plus an optional `row_shift_y`
## (float): only the slot's x is used, and the anchor row moves by row_shift_y.
func setup(params: Dictionary) -> void:
	super(params)
	var shift: Variant = params.get("row_shift_y", 0.0)
	_row_shift_y = float(shift) if (shift is float or shift is int) else 0.0


func _ready() -> void:
	super()
	_reposition_interval_s = Config.num(_tuning_key("reposition_interval_s"))
	var fire_interval_s: float = Config.num(_tuning_key("fire_interval_s"))
	_track_s = Config.num(_tuning_key("track_s"))
	_lock_s = Config.num(_tuning_key("lock_s"))
	_cooldown_s = maxf(fire_interval_s - _track_s - _lock_s, 0.0)
	_bolt_speed = Config.num(_tuning_key("bolt_speed_px_s"))
	_anchor_y = Config.num(_tuning_key("anchor_y_px")) + _row_shift_y
	_reposition_speed = Config.num(_tuning_key("reposition_speed_px_s"))
	_min_distance = Config.num(_tuning_key("reposition_min_distance_px"))
	_bolt_damage = Config.int_("damage.bullet_hearts")
	_line_length = Playfield.SIZE.length()
	_muzzle = get_node_or_null(^"Muzzle") as Node2D
	_line = get_node_or_null(^"TelegraphLine") as Line2D
	var half: float = sprite_px / 2.0
	_min_x = half
	_max_x = Playfield.SIZE.x - half
	if not _has_slot:
		_anchor = global_position
		_enter_state(State.ANCHORING)
		return
	var x: float = clampf(_slot.x, _min_x, _max_x)
	if x != _slot.x:
		Log.warn("spawn", "needle slot x %.0f is off screen (%.0f..%.0f); clamped" % [_slot.x, _min_x, _max_x])
	_anchor = Vector2(x, _anchor_y)
	global_position = _entry_start_for(_anchor)
	_enter_state(State.ANCHORING)


func _physics_process(delta: float) -> void:
	step(delta)


## Advances the state machine by `delta` seconds.
func step(delta: float) -> void:
	_t += delta
	if _state != State.ANCHORING:
		_anchored_t += delta
	match _state:
		State.ANCHORING:
			global_position = global_position.move_toward(_anchor, _reposition_speed * delta)
			if global_position == _anchor:
				_anchored_t = 0.0
				_enter_state(State.TRACKING)
		State.TRACKING:
			_aim_line()
			if _t >= _track_s:
				_enter_state(State.LOCKED)
		State.LOCKED:
			if _t >= _lock_s:
				_fire()
				_enter_state(State.COOLDOWN)
		State.COOLDOWN:
			if _anchored_t >= _reposition_interval_s - REPOSITION_EPS_S:
				_anchor = Vector2(_pick_anchor_x(global_position.x), _anchor_y)
				_enter_state(State.ANCHORING)
			elif _t >= _cooldown_s:
				_enter_state(State.TRACKING)


func state() -> State:
	return _state


## The anchor the Needle is flying to, or sitting on.
func anchor() -> Vector2:
	return _anchor


func line_visible() -> bool:
	return _line != null and _line.visible


func line_color() -> Color:
	return _line.default_color if _line != null else Color.TRANSPARENT


## Unit direction of the targeting line (frozen while LOCKED).
func line_direction() -> Vector2:
	return _line_dir


func _enter_state(new_state: State) -> void:
	_state = new_state
	_t = 0.0
	if _line != null:
		_line.visible = new_state == State.TRACKING or new_state == State.LOCKED
		if new_state == State.LOCKED:
			_line.default_color = lock_color
			_line.width = LOCK_WIDTH_PX
		else:
			_line.default_color = track_color
			_line.width = TRACK_WIDTH_PX
	if new_state == State.TRACKING:
		# Aim at once so the line never shows a stale direction.
		_aim_line()


func _muzzle_position() -> Vector2:
	return _muzzle.global_position if _muzzle != null else global_position


## Points the line from the muzzle toward the player (straight down with no
## player or a zero vector), reaching across the whole playfield.
func _aim_line() -> void:
	_line_dir = _aim_from(_muzzle_position())
	if _line != null:
		var start: Vector2 = _muzzle.position if _muzzle != null else Vector2.ZERO
		_line.set_point_position(0, start)
		_line.set_point_position(1, start + _line_dir * _line_length)


func _fire() -> void:
	if not _can_fire():
		return
	var bolt: Projectile = spawner.spawn_projectile(BOLT_ID, {
		"position": _muzzle_position(),
		"velocity": _line_dir * _bolt_speed,
		"damage": _bolt_damage,
	})
	# The shot is heard only when a bolt really leaves (playtest pt7-e), so a
	# held fire (Tarek's fall) stays silent.
	if bolt != null:
		Audio.play_sfx(FIRE_SFX, Audio.DEFAULT_PITCH_JITTER, Config.num("enemies.needle.fire_sfx_volume_db"))


## A new anchor x: uniform over the parts of [_min_x, _max_x] at least
## _min_distance from `current_x`; uniform over the whole range if none exist.
func _pick_anchor_x(current_x: float) -> float:
	var left_end: float = minf(current_x - _min_distance, _max_x)
	var left_len: float = maxf(left_end - _min_x, 0.0)
	var right_start: float = maxf(current_x + _min_distance, _min_x)
	var right_len: float = maxf(_max_x - right_start, 0.0)
	var total: float = left_len + right_len
	if total <= 0.0:
		return rng.randf_range(_min_x, _max_x)
	var r: float = rng.randf() * total
	if r < left_len:
		return _min_x + r
	return right_start + (r - left_len)
