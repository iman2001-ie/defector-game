class_name EnergyBar
extends Control
## The player's energy in the top-right HUD band (UX `energyBar`, FR62): a
## `hud.energy_bar.width` x `height` bar right-aligned to `right_x` at `y`.
## An `energy` fill on a `heartEmpty` track, with `text`-coloured tick marks at
## the Shield and Barrage costs (abilities.shield.cost / barrage.cost of max).
##
## Driven only by Events.energy_changed (the level emits the starting value
## right after level_started). Colours and corners come from the shared Theme
## (`ui/theme/defector_theme.tres`, type `EnergyBar`); layout from Config.

const THEME_TYPE: StringName = &"EnergyBar"
const STYLE_TRACK: StringName = &"track"
const STYLE_FILL: StringName = &"fill"
const COLOR_TICK: StringName = &"tick"

var right_x: float = 0.0
var top_y: float = 0.0
var bar_width: float = 0.0
var bar_height: float = 0.0
var tick_px: float = 0.0

var _current: int = 0
var _max: int = 0
## Energy values that get a tick mark (the ability costs).
var _tick_values: Array[int] = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	right_x = Config.num("hud.energy_bar.right_x")
	top_y = Config.num("hud.energy_bar.y")
	bar_width = maxf(Config.num("hud.energy_bar.width"), 0.0)
	bar_height = maxf(Config.num("hud.energy_bar.height"), 0.0)
	tick_px = maxf(Config.num("hud.energy_bar.tick_px"), 0.0)
	_max = maxi(Config.int_("energy.max"), 0)
	_tick_values = [Config.int_("abilities.shield.cost"), Config.int_("abilities.barrage.cost")]
	position = Vector2(right_x - bar_width, top_y)
	size = Vector2(bar_width, bar_height)
	Events.energy_changed.connect(_on_events_energy_changed)


# --- Read accessors (tests) ------------------------------------------------------

func current() -> int:
	return _current


func max_energy() -> int:
	return _max


## The x (left edge, bar-local) of each tick mark, in _tick_values order.
func tick_positions() -> Array[float]:
	var out: Array[float] = []
	for value: int in _tick_values:
		out.append(tick_x(value, _max, bar_width, tick_px))
	return out


## Width of the fill for `current_energy` of `max_value` on a `width` px bar
## (clamped to 0..width; 0 when max_value <= 0).
static func fill_width(current_energy: int, max_value: int, width: float) -> float:
	if max_value <= 0 or width <= 0.0:
		return 0.0
	return width * clampf(float(current_energy) / float(max_value), 0.0, 1.0)


## Left edge of the `tick` px wide mark for `value` of `max_value` on a `width`
## px bar, clamped so the whole mark stays inside the bar.
static func tick_x(value: int, max_value: int, width: float, tick: float) -> float:
	var hi: float = maxf(width - tick, 0.0)
	if max_value <= 0:
		return 0.0
	return clampf(width * float(value) / float(max_value), 0.0, hi)


# --- Drawing -------------------------------------------------------------------

func _draw() -> void:
	if bar_width <= 0.0 or bar_height <= 0.0:
		return
	draw_style_box(get_theme_stylebox(STYLE_TRACK, THEME_TYPE), Rect2(Vector2.ZERO, size))
	var filled: float = fill_width(_current, _max, size.x)
	if filled > 0.0:
		draw_style_box(get_theme_stylebox(STYLE_FILL, THEME_TYPE), Rect2(Vector2.ZERO, Vector2(filled, size.y)))
	if tick_px <= 0.0 or _max <= 0:
		return
	var tick: Color = get_theme_color(COLOR_TICK, THEME_TYPE)
	for value: int in _tick_values:
		draw_rect(Rect2(tick_x(value, _max, size.x, tick_px), 0.0, tick_px, size.y), tick)


# --- Events ----------------------------------------------------------------------

func _on_events_energy_changed(current_energy: int, max_value: int) -> void:
	_max = maxi(max_value, 0)
	_current = clampi(current_energy, 0, _max)
	queue_redraw()
