class_name RetryPrompt
extends Control
## The retry prompt on the Overlay layer (UX "Retry prompt", Story 3.2): no
## panel, just a dim, the loss reason in `danger` and RETRY · QUIT TO TITLE.
##
## Events in, SceneRouter out: it never reads gameplay nodes. On the first
## Events.level_failed it starts a pausable feedback.player_death_pause_s timer
## (the death beat: it freezes under any pause and stretches with hit-stop);
## when that fires, show_prompt() pushes the `death` pause reason and shows the
## prompt with RETRY focused (focus ring hidden). Later failures are ignored,
## and so is any failure after Events.level_cleared (the first outcome wins,
## DW-75: a convoy loss can't fail a cleared level). RETRY calls
## SceneRouter.retry_level() (energy 0), QUIT TO TITLE SceneRouter.goto_title(); a
## second press does nothing.
##
## Runs while paused (PROCESS_MODE_ALWAYS). It captures the mouse only while
## shown. Colours and button styles come from the shared Theme (type
## `RetryPrompt`); layout numbers and the beat come from Config.

const THEME_TYPE: StringName = &"RetryPrompt"
const COLOR_DIM: StringName = &"dim"
const COLOR_REASON: StringName = &"reason"
const COLOR_TEXT: StringName = &"text"
const STYLE_BUTTON_NORMAL: StringName = &"button_normal"
const STYLE_BUTTON_HOVER: StringName = &"button_hover"
const STYLE_BUTTON_FOCUS: StringName = &"button_focus"
const FONT_SIZE_BUTTON: StringName = &"button"
const PAUSE_REASON: StringName = &"death"
const TEXT_HULL: String = "HULL DESTROYED"
const TEXT_CONVOY: String = "CONVOY LOST"
const TEXT_RETRY: String = "RETRY"
const TEXT_QUIT: String = "QUIT TO TITLE"

## Seconds of unpaused time between level_failed and the prompt.
var beat_s: float = 0.0
var headline_y: float = 0.0
var headline_px: int = 0
var button_size: Vector2 = Vector2.ZERO
var button_gap_px: float = 0.0
var buttons_top_y: float = 0.0

var _pending: bool = false
var _shown: bool = false
var _leaving: bool = false
## Set by Events.level_cleared: later failures are ignored (DW-75).
var _cleared: bool = false
var _reason: StringName = &""

@onready var _dim: ColorRect = $Dim
@onready var _reason_label: Label = $Reason
@onready var _retry: Button = $Retry
@onready var _quit: Button = $Quit


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	beat_s = maxf(Config.num("feedback.player_death_pause_s"), 0.0)
	headline_y = Config.num("ui.retry_prompt.headline_y")
	headline_px = maxi(Config.int_("ui.retry_prompt.headline_px"), 1)
	button_size = Vector2(Config.num("ui.retry_prompt.button_w"), Config.num("ui.retry_prompt.button_h"))
	button_gap_px = maxf(Config.num("ui.retry_prompt.button_gap_px"), 0.0)
	buttons_top_y = Config.num("ui.retry_prompt.buttons_top_y")
	_apply_theme()
	_layout()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_retry.text = TEXT_RETRY
	_quit.text = TEXT_QUIT
	_retry.pressed.connect(_on_retry_pressed)
	_quit.pressed.connect(_on_quit_pressed)
	Events.level_failed.connect(_on_events_level_failed)
	Events.level_cleared.connect(_on_events_level_cleared)


# --- Read accessors (tests) ------------------------------------------------------

func is_shown() -> bool:
	return _shown


## True during the death beat (level_failed received, prompt not shown yet).
func is_pending() -> bool:
	return _pending


func reason_text() -> String:
	return _reason_label.text


## The RETRY and QUIT rects: a centred pair of `button` boxes, `gap` px apart,
## top at `top_y`, on a canvas `canvas_w` px wide.
static func button_rects(canvas_w: float, button: Vector2, gap: float, top_y: float) -> Array[Rect2]:
	var left: float = (canvas_w - (button.x * 2.0 + gap)) / 2.0
	return [
		Rect2(Vector2(left, top_y), button),
		Rect2(Vector2(left + button.x + gap, top_y), button),
	]


## The headline for a level_failed reason; unknown reasons fall back to HULL DESTROYED.
static func text_for(reason: StringName) -> String:
	if reason == &"convoy":
		return TEXT_CONVOY
	return TEXT_HULL


# --- Showing ---------------------------------------------------------------------

## Ends the beat: pauses with the `death` reason and shows the prompt for `reason`.
func show_prompt(reason: StringName) -> void:
	if _shown:
		return
	_pending = false
	_shown = true
	_reason = reason
	if reason != &"hearts" and reason != &"convoy":
		Log.warn("scene", "Retry prompt: unknown loss reason '%s', showing %s" % [reason, TEXT_HULL])
	_reason_label.text = text_for(reason)
	PauseArbiter.push(PAUSE_REASON)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Mouse-only UI: keep RETRY focused but hide the focus ring, so only hover highlights.
	_retry.grab_focus(true)


func _on_events_level_failed(reason: StringName) -> void:
	if _pending or _shown or _cleared:
		return
	_pending = true
	_reason = reason
	get_tree().create_timer(beat_s, false).timeout.connect(_on_beat_timeout)


func _on_events_level_cleared(_level_id: int) -> void:
	_cleared = true


func _on_beat_timeout() -> void:
	if not _pending or not is_inside_tree():
		return
	show_prompt(_reason)


func _on_retry_pressed() -> void:
	if not _shown or _leaving:
		return
	_leaving = true
	SceneRouter.retry_level()


func _on_quit_pressed() -> void:
	if not _shown or _leaving:
		return
	_leaving = true
	SceneRouter.goto_title()


# --- Layout and theme ------------------------------------------------------------

func _layout() -> void:
	_reason_label.position = Vector2(0.0, headline_y)
	_reason_label.size = Vector2(Playfield.SIZE.x, float(headline_px))
	var rects: Array[Rect2] = button_rects(Playfield.SIZE.x, button_size, button_gap_px, buttons_top_y)
	_retry.position = rects[0].position
	_retry.size = rects[0].size
	_quit.position = rects[1].position
	_quit.size = rects[1].size


## Copies the RetryPrompt theme items onto the children (their own theme types
## are Label / Button / ColorRect).
func _apply_theme() -> void:
	_dim.color = get_theme_color(COLOR_DIM, THEME_TYPE)
	_reason_label.add_theme_color_override(&"font_color", get_theme_color(COLOR_REASON, THEME_TYPE))
	_reason_label.add_theme_font_size_override(&"font_size", headline_px)
	var normal: StyleBox = get_theme_stylebox(STYLE_BUTTON_NORMAL, THEME_TYPE)
	var hover: StyleBox = get_theme_stylebox(STYLE_BUTTON_HOVER, THEME_TYPE)
	var focus: StyleBox = get_theme_stylebox(STYLE_BUTTON_FOCUS, THEME_TYPE)
	var text_color: Color = get_theme_color(COLOR_TEXT, THEME_TYPE)
	var font_px: int = get_theme_font_size(FONT_SIZE_BUTTON, THEME_TYPE)
	for button: Button in [_retry, _quit]:
		button.add_theme_stylebox_override(&"normal", normal)
		button.add_theme_stylebox_override(&"hover", hover)
		button.add_theme_stylebox_override(&"pressed", hover)
		button.add_theme_stylebox_override(&"hover_pressed", hover)
		button.add_theme_stylebox_override(&"focus", focus)
		for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
			button.add_theme_color_override(color_name, text_color)
		if font_px > 0:
			button.add_theme_font_size_override(&"font_size", font_px)
