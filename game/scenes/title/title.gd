class_name TitleScreen
extends Control
## The title screen (Story 4.1, FR56; UX "Title screen"): the DEFECTOR logo and
## PLAY · QUIT. PLAY continues at the highest unlocked level (Story 4.2);
## Story 4.3 adds LEVEL SELECT.
##
## Healthy config: the layout comes from `ui.title` (logo centre y and size,
## button size, gap and first top; the button stack is centred horizontally).
## Fatal config (Config.load_error set, so the data is empty): the buttons are
## hidden and disabled and the Error label shows the message in their place.
## That branch never calls a Config getter (each would assert on the empty
## data); it keeps the positions authored in title.tscn, which match the UX.
##
## PLAY -> SceneRouter.start_level(GameState.highest_unlocked_level) with the
## energy goto_title() restored from the save (the debug F7 unlock doesn't change
## it); QUIT -> quit_game (logged).
## A second press does nothing. Colours, sizes and button styles come from the
## shared Theme (type `Title`), copied onto the children in code. Mouse-only:
## no button takes focus.

const THEME_TYPE: StringName = &"Title"
const COLOR_LOGO: StringName = &"logo"
const COLOR_LOGO_GLOW: StringName = &"logo_glow"
const COLOR_ERROR: StringName = &"error"
const COLOR_TEXT: StringName = &"text"
const CONSTANT_LOGO_GLOW_PX: StringName = &"logo_glow_px"
const FONT_SIZE_BUTTON: StringName = &"button"
const FONT_SIZE_ERROR: StringName = &"error"
const STYLE_BUTTON_NORMAL: StringName = &"button_normal"
const STYLE_BUTTON_HOVER: StringName = &"button_hover"
const STYLE_BUTTON_FOCUS: StringName = &"button_focus"
const TEXT_LOGO: String = "DEFECTOR"
const TEXT_PLAY: String = "PLAY"
const TEXT_QUIT: String = "QUIT"
const TEXT_ERROR_HEADER: String = "CONFIG ERROR"
## The Logo label is this many times logo_px tall, so the glyphs fit inside it.
const LOGO_BOX_SCALE: float = 2.0

## Quits the application. Defaults to get_tree().quit in _ready; tests inject a
## recorder before add_child.
var quit_game: Callable

var _leaving: bool = false
var _config_failed: bool = false

@onready var _logo: Label = $Logo
@onready var _buttons: VBoxContainer = $Buttons
@onready var _play: Button = $Buttons/Play
@onready var _quit: Button = $Buttons/Quit
@onready var _error: Label = $Error


func _ready() -> void:
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if not quit_game.is_valid():
		quit_game = get_tree().quit
	_config_failed = not Config.load_error.is_empty()
	_logo.text = TEXT_LOGO
	_play.text = TEXT_PLAY
	_quit.text = TEXT_QUIT
	_apply_theme()
	if _config_failed:
		_show_config_error(Config.load_error)
	else:
		_error.visible = false
		_layout()
	_play.pressed.connect(_on_play_pressed)
	_quit.pressed.connect(_on_quit_pressed)
	Log.info("scene", "Title ready %d ms after launch" % Time.get_ticks_msec())


## True when the config failed to load and the error replaces the buttons.
func is_config_error() -> bool:
	return _config_failed


## The logo label's rect: `logo_px` font, centred on y `logo_y`, full canvas width.
static func logo_rect(canvas_w: float, logo_y: float, logo_px: float) -> Rect2:
	var height: float = logo_px * LOGO_BOX_SCALE
	return Rect2(Vector2(0.0, logo_y - height / 2.0), Vector2(canvas_w, height))


## The button stack's rect: `count` buttons of `button` size with `gap` between
## them, centred horizontally, top at `top_y`.
static func buttons_rect(canvas_w: float, button: Vector2, gap: float, top_y: float, count: int) -> Rect2:
	var height: float = button.y * count + gap * maxi(count - 1, 0)
	return Rect2(Vector2((canvas_w - button.x) / 2.0, top_y), Vector2(button.x, height))


func _show_config_error(message: String) -> void:
	_buttons.visible = false
	_play.disabled = true
	_quit.disabled = true
	_error.text = TEXT_ERROR_HEADER + "\n" + message
	_error.visible = true


func _on_play_pressed() -> void:
	if _leaving or _config_failed:
		return
	_leaving = true
	SceneRouter.start_level(str(GameState.highest_unlocked_level))


func _on_quit_pressed() -> void:
	if _leaving or _config_failed:
		return
	_leaving = true
	Log.info("scene", "Quit from the title screen")
	quit_game.call()


# --- Layout and theme ------------------------------------------------------------

## Healthy config only: positions from ui.title.
func _layout() -> void:
	var logo_px: int = maxi(Config.int_("ui.title.logo_px"), 1)
	var logo: Rect2 = logo_rect(Playfield.SIZE.x, Config.num("ui.title.logo_y"), float(logo_px))
	_logo.add_theme_font_size_override(&"font_size", logo_px)
	_logo.position = logo.position
	_logo.size = logo.size
	var button: Vector2 = Vector2(Config.num("ui.title.button_w"), Config.num("ui.title.button_h"))
	var gap: float = maxf(Config.num("ui.title.button_gap_px"), 0.0)
	var top_y: float = Config.num("ui.title.buttons_top_y")
	for child: Node in _buttons.get_children():
		(child as Control).custom_minimum_size = button
	_buttons.add_theme_constant_override(&"separation", int(gap))
	var rect: Rect2 = buttons_rect(Playfield.SIZE.x, button, gap, top_y, _buttons.get_child_count())
	_buttons.position = rect.position
	_buttons.size = rect.size


## Copies the Title theme items onto the children (their own theme types are
## Label / Button). Reads only the Theme, never Config.
func _apply_theme() -> void:
	_logo.add_theme_color_override(&"font_color", get_theme_color(COLOR_LOGO, THEME_TYPE))
	_logo.add_theme_color_override(&"font_shadow_color", get_theme_color(COLOR_LOGO_GLOW, THEME_TYPE))
	_logo.add_theme_constant_override(&"shadow_offset_x", 0)
	_logo.add_theme_constant_override(&"shadow_offset_y", 0)
	_logo.add_theme_constant_override(&"shadow_outline_size", get_theme_constant(CONSTANT_LOGO_GLOW_PX, THEME_TYPE))
	_error.add_theme_color_override(&"font_color", get_theme_color(COLOR_ERROR, THEME_TYPE))
	var error_px: int = get_theme_font_size(FONT_SIZE_ERROR, THEME_TYPE)
	if error_px > 0:
		_error.add_theme_font_size_override(&"font_size", error_px)
	var normal: StyleBox = get_theme_stylebox(STYLE_BUTTON_NORMAL, THEME_TYPE)
	var hover: StyleBox = get_theme_stylebox(STYLE_BUTTON_HOVER, THEME_TYPE)
	var focus: StyleBox = get_theme_stylebox(STYLE_BUTTON_FOCUS, THEME_TYPE)
	var text_color: Color = get_theme_color(COLOR_TEXT, THEME_TYPE)
	var font_px: int = get_theme_font_size(FONT_SIZE_BUTTON, THEME_TYPE)
	for button: Button in [_play, _quit]:
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override(&"normal", normal)
		button.add_theme_stylebox_override(&"hover", hover)
		button.add_theme_stylebox_override(&"pressed", hover)
		button.add_theme_stylebox_override(&"hover_pressed", hover)
		button.add_theme_stylebox_override(&"focus", focus)
		for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
			button.add_theme_color_override(color_name, text_color)
		if font_px > 0:
			button.add_theme_font_size_override(&"font_size", font_px)
