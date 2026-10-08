class_name HeartsDisplay
extends Control
## The player's hearts in the top-right HUD band (UX `hearts`): `max` heart
## icons right-aligned to `hud.hearts.right_x` at `hud.hearts.y`. Filled hearts
## use the theme's `heart` colour; empty hearts are a `empty` fill with a
## `muted` (`outline`) stroke, so they never rely on colour alone.
##
## Driven only by Events.hearts_changed. Hearts fill from the left; when hearts
## go down the newly lost hearts pop (scale `pop_scale` -> 1 over `pop_s`) and
## are drawn as outlines. The pop tween is bound to this pausable node, so it
## freezes with the game. Icons are drawn in code (no image files).

const THEME_TYPE: StringName = &"HeartsDisplay"
const COLOR_HEART: StringName = &"heart"
const COLOR_EMPTY: StringName = &"empty"
const COLOR_OUTLINE: StringName = &"outline"
## Outline stroke width on screen, in px (art constant, not tuning).
const OUTLINE_PX: float = 2.0
## Points sampled along the heart curve.
const HEART_POINTS: int = 32

var right_x: float = 0.0
var top_y: float = 0.0
var icon_px: float = 0.0
var gap_px: float = 0.0
var pop_scale: float = 1.0
var pop_s: float = 0.0

var _current: int = 0
var _max: int = 0
## First and one-past-last index of the hearts popping; _pop_from is -1 when none.
var _pop_from: int = -1
var _pop_to: int = -1
var _pop_now: float = 1.0
var _tween: Tween
## Unit heart polygon centred on the origin, fitting a 2x2 box (built once).
var _shape: PackedVector2Array = PackedVector2Array()
## The same points closed (first point repeated) for the outline.
var _outline: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	right_x = Config.num("hud.hearts.right_x")
	top_y = Config.num("hud.hearts.y")
	icon_px = maxf(Config.num("hud.hearts.icon_px"), 0.0)
	gap_px = maxf(Config.num("hud.hearts.gap_px"), 0.0)
	pop_scale = maxf(Config.num("hud.hearts.pop_scale"), 0.0)
	pop_s = maxf(Config.num("hud.hearts.pop_s"), 0.0)
	_shape = heart_polygon(HEART_POINTS)
	_outline = _shape.duplicate()
	if not _shape.is_empty():
		_outline.append(_shape[0])
	_layout()
	Events.hearts_changed.connect(_on_events_hearts_changed)


# --- Read accessors (tests) ------------------------------------------------------

func current() -> int:
	return _current


func max_hearts() -> int:
	return _max


## The lowest index of the hearts popping right now; -1 when none.
func popping_index() -> int:
	return _pop_from


## The scale the popping hearts are drawn at (1 when none).
func pop_scale_now() -> float:
	return _pop_now if _pop_from >= 0 else 1.0


## Total width of `count` icons of `icon` px with `gap` px between them.
static func row_width(count: int, icon: float, gap: float) -> float:
	if count <= 0:
		return 0.0
	return float(count) * icon + float(count - 1) * gap


## A heart outline of `count` points, centred on the origin and scaled to fit a
## 2x2 box (y down, point at the bottom).
static func heart_polygon(count: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	if count < 3:
		return points
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	for i: int in count:
		var t: float = TAU * float(i) / float(count)
		var s: float = sin(t)
		var p: Vector2 = Vector2(16.0 * s * s * s, -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)))
		points.append(p)
		lo = lo.min(p)
		hi = hi.max(p)
	var centre: Vector2 = (lo + hi) / 2.0
	var half: float = maxf(hi.x - lo.x, hi.y - lo.y) / 2.0
	for i: int in count:
		points[i] = (points[i] - centre) / half
	return points


# --- Drawing -------------------------------------------------------------------

## Icon `i` is filled while it is below the `current` heart count (hearts fill from the left).
static func icon_filled(i: int, current_hearts: int) -> bool:
	return i < current_hearts


## Draw scale of icon `i`: `pop_now` inside the popping range [pop_from, pop_to), else 1.
static func icon_scale(i: int, pop_from: int, pop_to: int, pop_now: float) -> float:
	if pop_from >= 0 and i >= pop_from and i < pop_to:
		return pop_now
	return 1.0


func _layout() -> void:
	var width: float = row_width(_max, icon_px, gap_px)
	position = Vector2(right_x - width, top_y)
	size = Vector2(width, icon_px)


func _draw() -> void:
	if _max <= 0 or _shape.is_empty() or icon_px <= 0.0:
		return
	var heart: Color = get_theme_color(COLOR_HEART, THEME_TYPE)
	var empty: Color = get_theme_color(COLOR_EMPTY, THEME_TYPE)
	var outline: Color = get_theme_color(COLOR_OUTLINE, THEME_TYPE)
	for i: int in _max:
		var radius: float = icon_px / 2.0 * icon_scale(i, _pop_from, _pop_to, _pop_now)
		var centre: Vector2 = Vector2(float(i) * (icon_px + gap_px) + icon_px / 2.0, icon_px / 2.0)
		draw_set_transform(centre, 0.0, Vector2(radius, radius))
		if icon_filled(i, _current):
			draw_colored_polygon(_shape, heart)
		else:
			draw_colored_polygon(_shape, empty)
			draw_polyline(_outline, outline, OUTLINE_PX / radius, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Events ----------------------------------------------------------------------

func _on_events_hearts_changed(current_hearts: int, max_value: int) -> void:
	var new_max: int = maxi(max_value, 0)
	var new_current: int = clampi(current_hearts, 0, new_max)
	var lost_from: int = new_current
	var lost_to: int = mini(_current, new_max)
	var lost: bool = new_max == _max and lost_to > lost_from
	if new_max != _max:
		_max = new_max
		_layout()
	_current = new_current
	if lost:
		_start_pop(lost_from, lost_to)
	else:
		_stop_pop()
	queue_redraw()


func _start_pop(from_index: int, to_index: int) -> void:
	_stop_pop()
	if pop_s <= 0.0:
		return
	_pop_from = from_index
	_pop_to = to_index
	_set_pop(pop_scale)
	_tween = create_tween()
	_tween.tween_method(_set_pop, pop_scale, 1.0, pop_s)
	_tween.finished.connect(_stop_pop)


func _set_pop(value: float) -> void:
	_pop_now = value
	queue_redraw()


func _stop_pop() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	var was_popping: bool = _pop_from >= 0
	_pop_from = -1
	_pop_to = -1
	_pop_now = 1.0
	if was_popping:
		queue_redraw()
