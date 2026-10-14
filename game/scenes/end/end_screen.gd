class_name EndScreen
extends Control
## The end screen after Level 3 (Story 7.7, FR60; UX "End screen"): the
## DEFECTOR logo, one closing line, "Thanks for playing" and BACK TO TITLE,
## over the throne-world backdrop. SceneRouter.complete_level(level_count)
## saves and then goes here through SceneRouter.goto_end().
##
## The backdrop is the project clear colour (`background` #05070F) plus the
## throne-world planet arc drawn by the reused LevelBackground (the
## `Background` child, first, so it draws behind the labels and the button).
##
## Healthy config: the layout comes from `ui.end_screen` (each text label spans
## the full canvas width, centred horizontally, with its vertical centre on its
## `*_y` at its `*_px` font size, as the title logo uses `logo_y`; the button is
## centred horizontally with its top at `button_top_y`, as the title's
## `buttons_top_y`). Fatal config (Config.load_error set, so the data is
## empty): no Config getter is called (each would assert on the empty data) and
## the positions authored in end_screen.tscn, which match the UX, are kept.
##
## BACK TO TITLE -> SceneRouter.goto_title() once; a second press does nothing.
## Colours, sizes and button styles come from the shared Theme (type
## `EndScreen`), copied onto the children in code. Mouse-only: the button takes
## no focus. The closing line is microcopy, like the title's TEXT_PLAY: the
## docs leave its wording open (decision #57, provisional).
##
## Story 8.4: after the ready line it logs `[INFO][beat] End screen: campaign
## finished <s> s after launch (final choice '<id>')` (<s> whole seconds of
## Time.get_ticks_msec(), the choice `none` when GameState.final_choice is
## empty), the end-of-run beat tools/beat_audit.py reads.

const THEME_TYPE: StringName = &"EndScreen"
const COLOR_LOGO: StringName = &"logo"
const COLOR_LOGO_GLOW: StringName = &"logo_glow"
const COLOR_TEXT: StringName = &"text"
const COLOR_MUTED: StringName = &"muted"
const CONSTANT_LOGO_GLOW_PX: StringName = &"logo_glow_px"
const FONT_SIZE_BUTTON: StringName = &"button"
const STYLE_BUTTON_NORMAL: StringName = &"button_normal"
const STYLE_BUTTON_HOVER: StringName = &"button_hover"
const STYLE_BUTTON_FOCUS: StringName = &"button_focus"
const TEXT_LOGO: String = "DEFECTOR"
const TEXT_CLOSING: String = "The Sovereignty has fallen. The war is over."
const TEXT_THANKS: String = "Thanks for playing"
const TEXT_BACK: String = "BACK TO TITLE"
## A text label is this many times its font size tall, so the glyphs fit
## inside it (as TitleScreen.LOGO_BOX_SCALE).
const TEXT_BOX_SCALE: float = 2.0

var _leaving: bool = false
var _config_failed: bool = false

@onready var _background: LevelBackground = $Background
@onready var _logo: Label = $Logo
@onready var _closing: Label = $ClosingLine
@onready var _thanks: Label = $Thanks
@onready var _back: Button = $Back


func _ready() -> void:
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_config_failed = not Config.load_error.is_empty()
	_background.apply(LevelBackground.THRONE_WORLD)
	_logo.text = TEXT_LOGO
	_closing.text = TEXT_CLOSING
	_thanks.text = TEXT_THANKS
	_back.text = TEXT_BACK
	_apply_theme()
	if not _config_failed:
		_layout()
	_back.pressed.connect(_on_back_pressed)
	Log.info("scene", "End screen ready")
	# Story 8.4: the last playthrough beat for tools/beat_audit.py (also on a fatal config).
	var choice: String = "none" if GameState.final_choice.is_empty() else String(GameState.final_choice)
	Log.info("beat", "End screen: campaign finished %d s after launch (final choice '%s')" % [floori(Time.get_ticks_msec() / 1000.0), choice])


## True when the config failed to load (the authored layout is kept).
func is_config_error() -> bool:
	return _config_failed


## A text label's rect: `font_px` font, centred on y `centre_y`, full canvas width.
static func text_rect(canvas_w: float, centre_y: float, font_px: float) -> Rect2:
	var height: float = font_px * TEXT_BOX_SCALE
	return Rect2(Vector2(0.0, centre_y - height / 2.0), Vector2(canvas_w, height))


## The button's rect: `button` size, centred horizontally, top at `top_y`.
static func button_rect(canvas_w: float, button: Vector2, top_y: float) -> Rect2:
	return Rect2(Vector2((canvas_w - button.x) / 2.0, top_y), button)


func _on_back_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	SceneRouter.goto_title()


# --- Layout and theme ------------------------------------------------------------

## Healthy config only: positions and text sizes from ui.end_screen.
func _layout() -> void:
	_place_text(_logo, "ui.end_screen.logo_y", "ui.end_screen.logo_px")
	_place_text(_closing, "ui.end_screen.line_y", "ui.end_screen.line_px")
	_place_text(_thanks, "ui.end_screen.thanks_y", "ui.end_screen.thanks_px")
	var button: Vector2 = Vector2(Config.num("ui.end_screen.button_w"), Config.num("ui.end_screen.button_h"))
	var rect: Rect2 = button_rect(Playfield.SIZE.x, button, Config.num("ui.end_screen.button_top_y"))
	_back.custom_minimum_size = rect.size
	_back.position = rect.position
	_back.size = rect.size


func _place_text(label: Label, y_key: String, px_key: String) -> void:
	var font_px: int = maxi(Config.int_(px_key), 1)
	var rect: Rect2 = text_rect(Playfield.SIZE.x, Config.num(y_key), float(font_px))
	label.add_theme_font_size_override(&"font_size", font_px)
	label.position = rect.position
	label.size = rect.size


## Copies the EndScreen theme items onto the children (their own theme types
## are Label / Button). Reads only the Theme, never Config.
func _apply_theme() -> void:
	_logo.add_theme_color_override(&"font_color", get_theme_color(COLOR_LOGO, THEME_TYPE))
	_logo.add_theme_color_override(&"font_shadow_color", get_theme_color(COLOR_LOGO_GLOW, THEME_TYPE))
	_logo.add_theme_constant_override(&"shadow_offset_x", 0)
	_logo.add_theme_constant_override(&"shadow_offset_y", 0)
	_logo.add_theme_constant_override(&"shadow_outline_size", get_theme_constant(CONSTANT_LOGO_GLOW_PX, THEME_TYPE))
	var text_color: Color = get_theme_color(COLOR_TEXT, THEME_TYPE)
	_closing.add_theme_color_override(&"font_color", text_color)
	_thanks.add_theme_color_override(&"font_color", get_theme_color(COLOR_MUTED, THEME_TYPE))
	var normal: StyleBox = get_theme_stylebox(STYLE_BUTTON_NORMAL, THEME_TYPE)
	var hover: StyleBox = get_theme_stylebox(STYLE_BUTTON_HOVER, THEME_TYPE)
	var focus: StyleBox = get_theme_stylebox(STYLE_BUTTON_FOCUS, THEME_TYPE)
	_back.focus_mode = Control.FOCUS_NONE
	_back.add_theme_stylebox_override(&"normal", normal)
	_back.add_theme_stylebox_override(&"hover", hover)
	_back.add_theme_stylebox_override(&"pressed", hover)
	_back.add_theme_stylebox_override(&"hover_pressed", hover)
	_back.add_theme_stylebox_override(&"focus", focus)
	for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		_back.add_theme_color_override(color_name, text_color)
	var font_px: int = get_theme_font_size(FONT_SIZE_BUTTON, THEME_TYPE)
	if font_px > 0:
		_back.add_theme_font_size_override(&"font_size", font_px)
