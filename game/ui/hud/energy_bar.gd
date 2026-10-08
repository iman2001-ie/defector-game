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
##
## Denied flash (Story 3.4): Events.ability_denied (any ability) starts, or
## restarts, a flash of hud.energy_bar.denied_flash_s with denied_flashes
## on-phases; each on-phase draws a full-rect `denied` overlay above the fill
## and ticks. _process runs only while flashing, and the node is PAUSABLE, so
## the flash freezes under pause.

const THEME_TYPE: StringName = &"EnergyBar"
const STYLE_TRACK: StringName = &"track"
const STYLE_FILL: StringName = &"fill"
const COLOR_TICK: StringName = &"tick"
const COLOR_DENIED: StringName = &"denied"

var right_x: float = 0.0
var top_y: float = 0.0
var bar_width: float = 0.0
var bar_height: float = 0.0
var tick_px: float = 0.0
var denied_flash_s: float = 0.0
var denied_flashes: int = 0

var _current: int = 0
var _max: int = 0
## Energy values that get a tick mark (the ability costs).
var _tick_values: Array[int] = []
var _flashing: bool = false
var _flash_elapsed: float = 0.0
var _flash_on: bool = false


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
	denied_flash_s = maxf(Config.num("hud.energy_bar.denied_flash_s"), 0.0)
	denied_flashes = maxi(Config.int_("hud.energy_bar.denied_flashes"), 0)
	position = Vector2(right_x - bar_width, top_y)
	size = Vector2(bar_width, bar_height)
	set_process(false)
	Events.energy_changed.connect(_on_events_energy_changed)
	Events.ability_denied.connect(_on_events_ability_denied)


# --- Read accessors (tests) ------------------------------------------------------

func current() -> int:
	return _current


func max_energy() -> int:
	return _max


## True while a denied flash runs.
func is_flashing() -> bool:
	return _flashing


## True during an on-phase of the denied flash (the overlay is drawn).
func flash_on() -> bool:
	return _flash_on


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


## Whether the denied overlay is lit `elapsed` s into a flash of `duration` s
## with `flashes` on-phases: false outside [0, duration) or with no duration or
## flashes; otherwise lit in the first half of each of the `flashes` cycles.
static func flash_lit(elapsed: float, duration: float, flashes: int) -> bool:
	if duration <= 0.0 or flashes <= 0 or elapsed < 0.0 or elapsed >= duration:
		return false
	return fmod(elapsed / duration * float(flashes), 1.0) < 0.5


# --- Drawing -------------------------------------------------------------------

func _draw() -> void:
	if bar_width <= 0.0 or bar_height <= 0.0:
		return
	draw_style_box(get_theme_stylebox(STYLE_TRACK, THEME_TYPE), Rect2(Vector2.ZERO, size))
	var filled: float = fill_width(_current, _max, size.x)
	if filled > 0.0:
		draw_style_box(get_theme_stylebox(STYLE_FILL, THEME_TYPE), Rect2(Vector2.ZERO, Vector2(filled, size.y)))
	if tick_px > 0.0 and _max > 0:
		var tick: Color = get_theme_color(COLOR_TICK, THEME_TYPE)
		for value: int in _tick_values:
			draw_rect(Rect2(tick_x(value, _max, size.x, tick_px), 0.0, tick_px, size.y), tick)
	if _flash_on:
		draw_rect(Rect2(Vector2.ZERO, size), get_theme_color(COLOR_DENIED, THEME_TYPE))


## Advances the denied flash; runs only while flashing.
func _process(delta: float) -> void:
	_flash_elapsed += delta
	_update_flash()


# --- Events ----------------------------------------------------------------------

func _on_events_energy_changed(current_energy: int, max_value: int) -> void:
	_max = maxi(max_value, 0)
	_current = clampi(current_energy, 0, _max)
	queue_redraw()


## Any denied ability starts the flash again from 0.
func _on_events_ability_denied(_ability: StringName) -> void:
	_flashing = true
	_flash_elapsed = 0.0
	_update_flash()


## Sets the on/off phase for the current elapsed time and stops at the end.
func _update_flash() -> void:
	var lit: bool = flash_lit(_flash_elapsed, denied_flash_s, denied_flashes)
	if _flash_elapsed >= denied_flash_s:
		_flashing = false
		lit = false
	set_process(_flashing)
	if lit != _flash_on:
		_flash_on = lit
		queue_redraw()
