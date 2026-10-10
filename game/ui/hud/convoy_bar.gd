class_name ConvoyBar
extends Control
## The convoy's shared HP in the top-right HUD band (UX `convoyBar`, FR62,
## Story 6.1): a `hud.convoy_bar.width` x `height` bar right-aligned to
## `right_x` at `y`, under the energy bar and thinner than it. A `coalition` fill
## on a `heartEmpty` track, with a `CONVOY` label in `muted` (`label_px`)
## right-aligned `label_gap_px` to the left of the bar.
##
## Driven only by Events.convoy_hp_changed, and hidden until the first one, so
## a level without a convoy never shows it. An HP drop flashes a full-rect
## `danger` overlay once for `flash_s`; while HP / max is below `low_ratio` the
## label's alpha pulses at `pulse_hz` (down to `pulse_min_alpha`). _process runs
## only while flashing or pulsing, and the node is PAUSABLE, so both freeze under
## pause. Colours and styles come from the shared Theme (type `ConvoyBar`);
## layout from Config.

const THEME_TYPE: StringName = &"ConvoyBar"
const STYLE_TRACK: StringName = &"track"
const STYLE_FILL: StringName = &"fill"
const COLOR_LABEL: StringName = &"label"
const COLOR_DANGER: StringName = &"danger"
const TEXT_LABEL: String = "CONVOY"

var right_x: float = 0.0
var top_y: float = 0.0
var bar_width: float = 0.0
var bar_height: float = 0.0
var label_px: int = 0
var label_gap_px: float = 0.0
var flash_s: float = 0.0
var low_ratio: float = 0.0
var pulse_hz: float = 0.0
var pulse_min_alpha: float = 0.0

var _current: int = 0
var _max: int = 0
var _has_value: bool = false
var _flashing: bool = false
var _flash_elapsed: float = 0.0
var _pulse_elapsed: float = 0.0
var _label: Label


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	right_x = Config.num("hud.convoy_bar.right_x")
	top_y = Config.num("hud.convoy_bar.y")
	bar_width = maxf(Config.num("hud.convoy_bar.width"), 0.0)
	bar_height = maxf(Config.num("hud.convoy_bar.height"), 0.0)
	label_px = maxi(Config.int_("hud.convoy_bar.label_px"), 1)
	label_gap_px = maxf(Config.num("hud.convoy_bar.label_gap_px"), 0.0)
	flash_s = maxf(Config.num("hud.convoy_bar.flash_s"), 0.0)
	low_ratio = clampf(Config.num("hud.convoy_bar.low_ratio"), 0.0, 1.0)
	pulse_hz = maxf(Config.num("hud.convoy_bar.pulse_hz"), 0.0)
	pulse_min_alpha = clampf(Config.num("hud.convoy_bar.pulse_min_alpha"), 0.0, 1.0)
	position = Vector2(right_x - bar_width, top_y)
	size = Vector2(bar_width, bar_height)
	_build_label()
	visible = false
	set_process(false)
	Events.convoy_hp_changed.connect(_on_events_convoy_hp_changed)


# --- Read accessors (tests) ------------------------------------------------------

func current() -> int:
	return _current


func max_hp() -> int:
	return _max


## True while the damage flash runs (the danger overlay is drawn).
func is_flashing() -> bool:
	return _flashing


## True while HP / max is below low_ratio (the label pulses).
func is_low() -> bool:
	return is_low_ratio(_current, _max, low_ratio)


## The CONVOY label (a child Label, built in _ready).
func label() -> Label:
	return _label


## Width of the fill for `hp` of `max_value` on a `width` px bar (clamped to
## 0..width; 0 when max_value <= 0).
static func fill_width(hp: int, max_value: int, width: float) -> float:
	if max_value <= 0 or width <= 0.0:
		return 0.0
	return width * clampf(float(hp) / float(max_value), 0.0, 1.0)


## True when `hp` / `max_value` is below `ratio` (false with no max).
static func is_low_ratio(hp: int, max_value: int, ratio: float) -> bool:
	if max_value <= 0:
		return false
	return float(hp) / float(max_value) < ratio


## The label alpha `elapsed` s into a pulse of `hz`: 1 at the start of each
## cycle, `min_alpha` half-way (a cosine). 1 with no frequency.
static func pulse_alpha(elapsed: float, hz: float, min_alpha: float) -> float:
	if hz <= 0.0:
		return 1.0
	var wave: float = 0.5 + 0.5 * cos(TAU * hz * elapsed)
	return lerpf(min_alpha, 1.0, wave)


# --- Drawing -------------------------------------------------------------------

func _draw() -> void:
	if bar_width <= 0.0 or bar_height <= 0.0:
		return
	draw_style_box(get_theme_stylebox(STYLE_TRACK, THEME_TYPE), Rect2(Vector2.ZERO, size))
	var filled: float = fill_width(_current, _max, size.x)
	if filled > 0.0:
		draw_style_box(get_theme_stylebox(STYLE_FILL, THEME_TYPE), Rect2(Vector2.ZERO, Vector2(filled, size.y)))
	if _flashing:
		draw_rect(Rect2(Vector2.ZERO, size), get_theme_color(COLOR_DANGER, THEME_TYPE))


## Advances the flash and the pulse; runs only while either is active.
func _process(delta: float) -> void:
	if _flashing:
		_flash_elapsed += delta
		if _flash_elapsed >= flash_s:
			_flashing = false
			queue_redraw()
	_update_pulse(delta)
	set_process(_flashing or is_low())


# --- Events ----------------------------------------------------------------------

func _on_events_convoy_hp_changed(current_hp: int, max_value: int) -> void:
	var previous: int = _current
	var had_value: bool = _has_value
	_max = maxi(max_value, 0)
	_current = clampi(current_hp, 0, _max)
	_has_value = true
	visible = true
	if had_value and _current < previous and flash_s > 0.0:
		_flashing = true
		_flash_elapsed = 0.0
	_update_pulse(0.0)
	set_process(_flashing or is_low())
	queue_redraw()


## Pulses the label while low; otherwise holds it fully opaque.
func _update_pulse(delta: float) -> void:
	if is_low():
		_pulse_elapsed += delta
		_label.modulate.a = pulse_alpha(_pulse_elapsed, pulse_hz, pulse_min_alpha)
	else:
		_pulse_elapsed = 0.0
		_label.modulate.a = 1.0


# --- Label -----------------------------------------------------------------------

## The CONVOY label: `muted` at label_px, right-aligned label_gap_px left of the
## bar and vertically centred on it.
func _build_label() -> void:
	_label = Label.new()
	_label.name = "Label"
	_label.text = TEXT_LABEL
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override(&"font_color", get_theme_color(COLOR_LABEL, THEME_TYPE))
	_label.add_theme_font_size_override(&"font_size", label_px)
	add_child(_label)
	var font: Font = _label.get_theme_font(&"font")
	var text_size: Vector2 = Vector2(float(label_px) * TEXT_LABEL.length(), float(label_px))
	if font != null:
		text_size = font.get_string_size(TEXT_LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label_px)
	var w: float = ceilf(text_size.x)
	var h: float = ceilf(maxf(text_size.y, float(label_px)))
	_label.size = Vector2(w, h)
	_label.position = Vector2(-label_gap_px - w, (bar_height - h) / 2.0)
