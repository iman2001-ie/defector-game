class_name BossBar
extends Control
## The Flagship's HP bar (UX `bossBar`, FR53, Story 7.3). It takes the wave
## bar's slot (`hud.boss_bar`: x, y, width x height) and cross-fades in over
## `fade_s` when the boss arrives, while the WaveBar fades out over the same
## time (WaveBar listens to boss_started itself).
##
## An `enemy` fill shows the combined remaining HP from the left, so it drains
## right to left. Two `marker_w_px` markers in `text` sit at boss.core.hp / max
## (the turrets gone, 66.7 % with shipped data) and boss.final_choice_hp / max
## (the Final Choice, 16.7 %), measured from the left. A `FLAGSHIP` label in
## `muted` (`label_px`) is centred below the bar with its top at `label_y`.
## With max <= 0 the fill is empty and no marker is drawn.
##
## Driven only by Events: hidden until boss_started; boss_hp_changed sets the
## fill; level_started hides it again (the WaveBar comes back). Config gives
## the layout and the marker HP values, the Theme (type `BossBar`) the styles
## and colours. The fade tween is bound to this pausable node, so it freezes
## with the game.

const THEME_TYPE: StringName = &"BossBar"
const STYLE_TRACK: StringName = &"track"
const STYLE_FILL: StringName = &"fill"
const COLOR_MARKER: StringName = &"marker"
const COLOR_LABEL: StringName = &"label"
const TEXT_LABEL: String = "FLAGSHIP"

var fade_s: float = 0.0
var label_y: float = 0.0
var label_px: int = 0
var marker_w_px: float = 0.0
## The HP values the two markers stand for (boss.core.hp, boss.final_choice_hp).
var marker_hps: Array[int] = []

var _current: int = 0
var _max: int = 0
var _tween: Tween
var _label: Label


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	position = Vector2(Config.num("hud.boss_bar.x"), Config.num("hud.boss_bar.y"))
	size = Vector2(maxf(Config.num("hud.boss_bar.width"), 0.0), maxf(Config.num("hud.boss_bar.height"), 0.0))
	fade_s = maxf(Config.num("hud.boss_bar.fade_s"), 0.0)
	label_y = Config.num("hud.boss_bar.label_y")
	label_px = maxi(Config.int_("hud.boss_bar.label_px"), 1)
	marker_w_px = maxf(Config.num("hud.boss_bar.marker_w_px"), 0.0)
	marker_hps = [Config.int_("boss.core.hp"), Config.int_("boss.final_choice_hp")]
	_build_label()
	visible = false
	modulate.a = 0.0
	Events.boss_started.connect(_on_events_boss_started)
	Events.boss_hp_changed.connect(_on_events_boss_hp_changed)
	Events.level_started.connect(_on_events_level_started)


# --- Read accessors (tests) ------------------------------------------------------

func current() -> int:
	return _current


func max_hp() -> int:
	return _max


## The FLAGSHIP label (a child Label, built in _ready).
func label() -> Label:
	return _label


## Width of the fill now (0 when max <= 0).
func fill_width() -> float:
	return ConvoyBar.fill_width(_current, _max, size.x)


## Local x of each marker now (empty when max <= 0).
func marker_xs() -> Array[float]:
	var out: Array[float] = []
	if _max <= 0:
		return out
	for marker_hp: int in marker_hps:
		out.append(marker_x(marker_hp, _max, size.x))
	return out


## Local x of the marker for `marker_hp` of `max_value` on a `width` px bar,
## measured from the left and clamped to the bar.
static func marker_x(marker_hp: int, max_value: int, width: float) -> float:
	if max_value <= 0:
		return 0.0
	return width * clampf(float(marker_hp) / float(max_value), 0.0, 1.0)


# --- Drawing -------------------------------------------------------------------

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	draw_style_box(get_theme_stylebox(STYLE_TRACK, THEME_TYPE), Rect2(Vector2.ZERO, size))
	var filled: float = fill_width()
	if filled > 0.0:
		draw_style_box(get_theme_stylebox(STYLE_FILL, THEME_TYPE), Rect2(Vector2.ZERO, Vector2(filled, size.y)))
	if marker_w_px <= 0.0:
		return
	var color: Color = get_theme_color(COLOR_MARKER, THEME_TYPE)
	for x: float in marker_xs():
		draw_rect(Rect2(x - marker_w_px / 2.0, 0.0, marker_w_px, size.y), color)


# --- Events ----------------------------------------------------------------------

func _on_events_boss_started() -> void:
	visible = true
	_fade_to(1.0)


func _on_events_boss_hp_changed(current_hp: int, max_value: int, _phase: int) -> void:
	_max = maxi(max_value, 0)
	_current = clampi(current_hp, 0, _max)
	queue_redraw()


func _on_events_level_started(_level_id: int) -> void:
	_stop_tween()
	visible = false
	modulate.a = 0.0
	_current = 0
	_max = 0
	queue_redraw()


func _fade_to(alpha: float) -> void:
	_stop_tween()
	if fade_s <= 0.0:
		modulate.a = alpha
		return
	_tween = create_tween()
	_tween.tween_property(self, ^"modulate:a", alpha, fade_s)


func _stop_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


# --- Label -----------------------------------------------------------------------

## The FLAGSHIP label: `muted` at label_px, as wide as the bar and centred on
## it, its top at label_y (screen y; the bar's own y is subtracted).
func _build_label() -> void:
	_label = Label.new()
	_label.name = "Label"
	_label.text = TEXT_LABEL
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label.add_theme_color_override(&"font_color", get_theme_color(COLOR_LABEL, THEME_TYPE))
	_label.add_theme_font_size_override(&"font_size", label_px)
	add_child(_label)
	_label.position = Vector2(0.0, label_y - position.y)
	_label.size = Vector2(size.x, float(label_px))
