class_name FinalChoice
extends Control
## The Final Choice control (Story 7.5, UX "Final Choice"): two large buttons
## below the story panel, shown after Isolde's lead-in. A view, like
## CommsPanel: it never reads dialogue data, and only CommsChannel calls it
## (show_options, hide_options). A click on an option emits `chosen(id)` once
## per showing; the channel does the rest (the event, GameState, the pause
## reason, the response).
##
## Two Buttons (`First`, `Second`) laid out as a centred pair from
## `ui.final_choice` (480 x 120, 48 px apart, top at y 680, so centred on
## x 960), FOCUS_NONE (mouse only, no focus ring), with the option `label` as
## their text, taken as-is from the data. Their styles follow the retry
## prompt's buttons: theme type `FinalChoice` (`styles/button_normal`: a
## surfaceAlt fill with a 1 px border; `styles/button_hover`: a coalition
## border and glow; `colors/text`), the font size from `ui.final_choice.font_px`.
## The root ignores the mouse, so a click outside the buttons (the gap
## included) goes on to CommsChannel, which consumes it. There is no timer.
## Runs while paused (PROCESS_MODE_ALWAYS); hidden at start.

## An option was clicked: its `id` (&"surrender" | &"destroy").
signal chosen(id: StringName)

const THEME_TYPE: StringName = &"FinalChoice"
const COLOR_TEXT: StringName = &"text"
const STYLE_BUTTON_NORMAL: StringName = &"button_normal"
const STYLE_BUTTON_HOVER: StringName = &"button_hover"
## Option keys (DialogueValidator's).
const OPTION_ID: String = DialogueValidator.OPTION_ID
const OPTION_LABEL: String = DialogueValidator.OPTION_LABEL

var button_size: Vector2 = Vector2.ZERO
var button_gap_px: float = 0.0
var buttons_top_y: float = 0.0
var font_px: int = 0

var _ids: Array[StringName] = []
var _shown: bool = false

@onready var _first: Button = $First
@onready var _second: Button = $Second


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	button_size = Vector2(maxf(Config.num("ui.final_choice.button_w"), 1.0), maxf(Config.num("ui.final_choice.button_h"), 1.0))
	button_gap_px = maxf(Config.num("ui.final_choice.button_gap_px"), 0.0)
	buttons_top_y = Config.num("ui.final_choice.buttons_top_y")
	font_px = Config.int_("ui.final_choice.font_px")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for button: Button in buttons():
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_STOP
	_first.pressed.connect(_on_pressed.bind(0))
	_second.pressed.connect(_on_pressed.bind(1))
	_apply_theme()
	_layout()
	visible = false


# --- Channel API ----------------------------------------------------------------

## Shows the buttons for `options` (each a Dictionary with `id` and `label`;
## the first two are used).
func show_options(options: Array) -> void:
	_ids.clear()
	var buttons_list: Array[Button] = buttons()
	for i: int in buttons_list.size():
		var option: Dictionary = options[i] if i < options.size() and options[i] is Dictionary else {}
		_ids.append(StringName(str(option.get(OPTION_ID, ""))))
		buttons_list[i].text = str(option.get(OPTION_LABEL, ""))
	_shown = true
	visible = true


## Hides the buttons; later clicks do nothing.
func hide_options() -> void:
	_shown = false
	visible = false


# --- Read accessors (tests) -----------------------------------------------------

func is_shown() -> bool:
	return _shown


func buttons() -> Array[Button]:
	return [_first, _second]


## The option ids in button order.
func option_ids() -> Array[StringName]:
	return _ids.duplicate()


## The two button rects: a centred pair of `button` boxes `gap` px apart, top at
## `top_y`, on a canvas `canvas_w` px wide.
static func button_rects(canvas_w: float, button: Vector2, gap: float, top_y: float) -> Array[Rect2]:
	var left: float = (canvas_w - (button.x * 2.0 + gap)) / 2.0
	return [
		Rect2(Vector2(left, top_y), button),
		Rect2(Vector2(left + button.x + gap, top_y), button),
	]


# --- Internals ------------------------------------------------------------------

func _on_pressed(index: int) -> void:
	if not _shown or index >= _ids.size():
		return
	_shown = false
	chosen.emit(_ids[index])


func _layout() -> void:
	var rects: Array[Rect2] = button_rects(Playfield.SIZE.x, button_size, button_gap_px, buttons_top_y)
	var buttons_list: Array[Button] = buttons()
	for i: int in buttons_list.size():
		buttons_list[i].position = rects[i].position
		buttons_list[i].size = rects[i].size


## Copies the FinalChoice theme items onto the buttons (their own theme type is
## Button), as the retry prompt does.
func _apply_theme() -> void:
	var normal: StyleBox = get_theme_stylebox(STYLE_BUTTON_NORMAL, THEME_TYPE)
	var hover: StyleBox = get_theme_stylebox(STYLE_BUTTON_HOVER, THEME_TYPE)
	var text_color: Color = get_theme_color(COLOR_TEXT, THEME_TYPE)
	for button: Button in buttons():
		button.add_theme_stylebox_override(&"normal", normal)
		button.add_theme_stylebox_override(&"hover", hover)
		button.add_theme_stylebox_override(&"pressed", hover)
		button.add_theme_stylebox_override(&"hover_pressed", hover)
		for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
			button.add_theme_color_override(color_name, text_color)
		if font_px > 0:
			button.add_theme_font_size_override(&"font_size", font_px)
