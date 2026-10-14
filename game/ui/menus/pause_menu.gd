class_name PauseMenu
extends Control
## The pause menu on the level's Overlay layer (Story 4.4, FR57 / FR8; UX
## "Pause menu"): a dim, a centred panel with the PAUSED heading and
## RESUME · RESTART LEVEL · QUIT TO TITLE.
##
## Esc (the `pause` action, echoes ignored) toggles it. open() pushes the `menu`
## pause reason; it does nothing while the `death` or `final_choice` reason is
## active (a `story` pause doesn't block it). resume() (RESUME or Esc again) pops
## only `menu`, so an underlying story pause stays. Over a story pause the menu
## hides its own Dim (the comms panel's dim is already up: one dim, never
## stacked). RESTART LEVEL calls
## SceneRouter.restart_level() (back to the attempt's starting energy), QUIT TO
## TITLE SceneRouter.goto_title(); the menu
## stays visible until the scene changes and a `_leaving` guard ignores every
## later press and Esc.
##
## Recent comms (Epic 7 playtest C): a RECENT COMMS block below the panel
## lists the last `ui.pause_menu.recent_comms` combat lines (from
## Events.comms_line_shown with mode &"combat"; story lines are ignored), newest
## first, as "NAME: text" in the speaker's accent (the CommsPanel colours,
## names from comms.speakers). The block is hidden while there are none. It is
## `comms_w` wide, centred, `comms_gap_px` below the panel.
##
## Runs while paused (PROCESS_MODE_ALWAYS). It captures the mouse only while
## shown. Mouse-only: no button takes focus. Colours, sizes and styles come from
## the shared Theme (type `PauseMenu`); layout numbers from `ui.pause_menu`.

const THEME_TYPE: StringName = &"PauseMenu"
const COLOR_DIM: StringName = &"dim"
const COLOR_TEXT: StringName = &"text"
const STYLE_PANEL: StringName = &"panel"
const STYLE_BUTTON_NORMAL: StringName = &"button_normal"
const STYLE_BUTTON_HOVER: StringName = &"button_hover"
const STYLE_BUTTON_FOCUS: StringName = &"button_focus"
const FONT_SIZE_HEADING: StringName = &"heading"
const FONT_SIZE_BUTTON: StringName = &"button"
const FONT_SIZE_COMMS: StringName = &"comms"
## The recent-comms rows' font (Story 8.2): a base-less FontVariation, so the
## dialogue keeps the engine font like the comms UIs; the heading keeps the
## Theme default (Kenney Future).
const FONT_COMMS: StringName = &"comms"
## Speaker accents and the muted heading colour, shared with the comms views.
const COMMS_COLOR_THEME_TYPE: StringName = &"CommsPanel"
const COLOR_MUTED: StringName = &"muted"
## Only these Events.comms_line_shown lines are listed.
const COMBAT_MODE: StringName = &"combat"
const TEXT_RECENT_COMMS: String = "RECENT COMMS"
const PAUSE_REASON: StringName = &"menu"
## While this reason is active the comms panel's dim is showing (Story 5.1).
const STORY_REASON: StringName = &"story"
## Reasons under which Esc does not open the menu.
const BLOCKING_REASONS: Array[StringName] = [&"death", &"final_choice"]
const TEXT_HEADING: String = "PAUSED"
const TEXT_RESUME: String = "RESUME"
const TEXT_RESTART: String = "RESTART LEVEL"
const TEXT_QUIT: String = "QUIT TO TITLE"
const BUTTON_COUNT: int = 3

var panel_w: float = 0.0
var panel_padding_px: float = 0.0
var heading_px: float = 0.0
var heading_gap_px: float = 0.0
var button_size: Vector2 = Vector2.ZERO
var button_gap_px: float = 0.0
## `ui.pause_menu` recent-comms numbers.
var recent_comms_max: int = 0
var comms_gap_px: float = 0.0
var comms_w: float = 0.0
var comms_padding_px: float = 0.0
var comms_line_gap_px: float = 0.0

var _shown: bool = false
var _leaving: bool = false
## The recent combat lines, newest first: [speaker (StringName), text (String)] pairs.
var _recent: Array[Array] = []
## One label per listed line (recent_comms_max of them).
var _comms_labels: Array[Label] = []
## `comms.speakers`: speaker id (String) -> {"name", "portrait"}.
var _speakers: Dictionary = {}
var _text_color: Color = Color.WHITE

@onready var _dim: ColorRect = $Dim
@onready var _panel: Panel = $Panel
@onready var _heading: Label = $Panel/Heading
@onready var _resume: Button = $Resume
@onready var _restart: Button = $Restart
@onready var _quit: Button = $Quit
@onready var _comms: PanelContainer = $RecentComms
@onready var _comms_margin: MarginContainer = $RecentComms/Margin
@onready var _comms_list: VBoxContainer = $RecentComms/Margin/List
@onready var _comms_heading: Label = $RecentComms/Margin/List/Heading


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	panel_w = maxf(Config.num("ui.pause_menu.panel_w"), 0.0)
	panel_padding_px = maxf(Config.num("ui.pause_menu.panel_padding_px"), 0.0)
	heading_px = maxf(Config.num("ui.pause_menu.heading_px"), 1.0)
	heading_gap_px = maxf(Config.num("ui.pause_menu.heading_gap_px"), 0.0)
	button_size = Vector2(maxf(Config.num("ui.pause_menu.button_w"), 1.0), maxf(Config.num("ui.pause_menu.button_h"), 1.0))
	button_gap_px = maxf(Config.num("ui.pause_menu.button_gap_px"), 0.0)
	recent_comms_max = maxi(Config.int_("ui.pause_menu.recent_comms"), 0)
	comms_gap_px = maxf(Config.num("ui.pause_menu.comms_gap_px"), 0.0)
	comms_w = maxf(Config.num("ui.pause_menu.comms_w"), 1.0)
	comms_padding_px = maxf(Config.num("ui.pause_menu.comms_padding_px"), 0.0)
	comms_line_gap_px = maxf(Config.num("ui.pause_menu.comms_line_gap_px"), 0.0)
	_speakers = Config.section("comms.speakers")
	_heading.text = TEXT_HEADING
	_comms_heading.text = TEXT_RECENT_COMMS
	for i: int in recent_comms_max:
		var label: Label = Label.new()
		label.name = "Line%d" % i
		# One row per line (a combat line is at most 50 characters); an
		# overlong one ends in an ellipsis instead of widening the block.
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.visible = false
		_comms_list.add_child(label)
		_comms_labels.append(label)
	_resume.text = TEXT_RESUME
	_restart.text = TEXT_RESTART
	_quit.text = TEXT_QUIT
	_apply_theme()
	_layout()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resume.pressed.connect(_on_resume_pressed)
	_restart.pressed.connect(_on_restart_pressed)
	_quit.pressed.connect(_on_quit_pressed)
	_refresh_comms()
	Events.comms_line_shown.connect(_on_events_comms_line_shown)


func _exit_tree() -> void:
	if Events.comms_line_shown.is_connected(_on_events_comms_line_shown):
		Events.comms_line_shown.disconnect(_on_events_comms_line_shown)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	get_viewport().set_input_as_handled()
	if _shown:
		resume()
	else:
		open()


# --- Read accessors (tests) ------------------------------------------------------

func is_shown() -> bool:
	return _shown


## The listed recent comms lines as shown ("NAME: text"), newest first.
func recent_comms() -> Array[String]:
	var out: Array[String] = []
	for label: Label in _comms_labels:
		if label.visible:
			out.append(label.text)
	return out


## "NAME: text" for a recent comms line (the name uppercase).
static func comms_line_text(display_name: String, text: String) -> String:
	return "%s: %s" % [display_name.to_upper(), text]


## The panel rect: `panel_w` wide, padding + heading + heading gap + `count`
## buttons with `gap` between them + padding tall, centred on `canvas`.
static func panel_rect(canvas: Vector2, width: float, padding: float, heading: float, heading_gap: float, button: Vector2, gap: float, count: int) -> Rect2:
	var height: float = padding * 2.0 + heading + heading_gap + button.y * count + gap * maxi(count - 1, 0)
	return Rect2(Vector2((canvas.x - width) / 2.0, (canvas.y - height) / 2.0), Vector2(width, height))


## The button rects inside `panel`: centred horizontally, stacked `gap` px
## apart, the first top at panel top + padding + heading + heading gap.
static func button_rects(panel: Rect2, padding: float, heading: float, heading_gap: float, button: Vector2, gap: float, count: int) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var left: float = panel.position.x + (panel.size.x - button.x) / 2.0
	var top: float = panel.position.y + padding + heading + heading_gap
	for i: int in count:
		rects.append(Rect2(Vector2(left, top + (button.y + gap) * i), button))
	return rects


# --- Opening and closing ---------------------------------------------------------

## Pushes the `menu` reason and shows the menu. Does nothing while shown, while
## leaving, or while `death` / `final_choice` is active.
func open() -> void:
	if _shown or _leaving:
		return
	for reason: StringName in BLOCKING_REASONS:
		if PauseArbiter.has_reason(reason):
			return
	_shown = true
	_dim.visible = not PauseArbiter.has_reason(STORY_REASON)
	PauseArbiter.push(PAUSE_REASON)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Log.info("scene", "Pause menu opened")


## Pops only the `menu` reason and hides the menu. Does nothing when hidden or
## while leaving.
func resume() -> void:
	if not _shown or _leaving:
		return
	_shown = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	PauseArbiter.pop(PAUSE_REASON)
	Log.info("scene", "Pause menu closed")


func _on_resume_pressed() -> void:
	resume()


func _on_restart_pressed() -> void:
	if not _shown or _leaving:
		return
	_leaving = true
	SceneRouter.restart_level()


func _on_quit_pressed() -> void:
	if not _shown or _leaving:
		return
	_leaving = true
	SceneRouter.goto_title()


# --- Recent comms ------------------------------------------------------------------

## Keeps the newest combat lines (at most recent_comms_max); story lines are ignored.
func _on_events_comms_line_shown(speaker: StringName, text: String, mode: StringName) -> void:
	if mode != COMBAT_MODE or recent_comms_max <= 0:
		return
	_recent.push_front([speaker, text])
	if _recent.size() > recent_comms_max:
		_recent.resize(recent_comms_max)
	_refresh_comms()


## Fills one label per recent line ("NAME: text" in the speaker's accent),
## hides the rest, hides the block when there are none and re-lays it out.
func _refresh_comms() -> void:
	for i: int in _comms_labels.size():
		var label: Label = _comms_labels[i]
		if i >= _recent.size():
			label.visible = false
			continue
		var speaker: StringName = _recent[i][0] as StringName
		var raw: Variant = _speakers.get(String(speaker))
		var display_name: String = str((raw as Dictionary).get("name", String(speaker))) if raw is Dictionary else String(speaker)
		label.text = comms_line_text(display_name, _recent[i][1] as String)
		label.add_theme_color_override(&"font_color", _accent(speaker))
		label.visible = true
	_comms.visible = not _recent.is_empty()
	_layout_comms()


## The speaker's accent (CommsPanel colours), the menu text colour without one.
func _accent(speaker: StringName) -> Color:
	if has_theme_color(speaker, COMMS_COLOR_THEME_TYPE):
		return get_theme_color(speaker, COMMS_COLOR_THEME_TYPE)
	return _text_color


# --- Layout and theme ------------------------------------------------------------

func _layout() -> void:
	var panel: Rect2 = panel_rect(Playfield.SIZE, panel_w, panel_padding_px, heading_px, heading_gap_px, button_size, button_gap_px, BUTTON_COUNT)
	_panel.position = panel.position
	_panel.size = panel.size
	_heading.position = Vector2(0.0, panel_padding_px)
	_heading.size = Vector2(panel.size.x, heading_px)
	var rects: Array[Rect2] = button_rects(panel, panel_padding_px, heading_px, heading_gap_px, button_size, button_gap_px, BUTTON_COUNT)
	var buttons: Array[Button] = [_resume, _restart, _quit]
	for i: int in buttons.size():
		buttons[i].position = rects[i].position
		buttons[i].size = rects[i].size
	_layout_comms()


## The recent comms block: comms_w wide, centred, comms_gap_px below the panel,
## as tall as its content.
func _layout_comms() -> void:
	_comms.custom_minimum_size = Vector2(comms_w, 0.0)
	_comms.position = Vector2((Playfield.SIZE.x - comms_w) / 2.0, _panel.position.y + _panel.size.y + comms_gap_px)
	_comms.size = Vector2(comms_w, 0.0)
	for side: String in ["left", "top", "right", "bottom"]:
		_comms_margin.add_theme_constant_override("margin_" + side, int(comms_padding_px))
	_comms_list.add_theme_constant_override(&"separation", int(comms_line_gap_px))
	_comms.size = Vector2(comms_w, 0.0)


## Copies the PauseMenu theme items onto the children (their own theme types
## are ColorRect / Panel / Label / Button).
func _apply_theme() -> void:
	_dim.color = get_theme_color(COLOR_DIM, THEME_TYPE)
	_panel.add_theme_stylebox_override(&"panel", get_theme_stylebox(STYLE_PANEL, THEME_TYPE))
	_comms.add_theme_stylebox_override(&"panel", get_theme_stylebox(STYLE_PANEL, THEME_TYPE))
	var text_color: Color = get_theme_color(COLOR_TEXT, THEME_TYPE)
	_text_color = text_color
	var comms_px: int = get_theme_font_size(FONT_SIZE_COMMS, THEME_TYPE)
	_comms_heading.add_theme_color_override(&"font_color", get_theme_color(COLOR_MUTED, COMMS_COLOR_THEME_TYPE))
	for label: Label in [_comms_heading] + _comms_labels:
		if comms_px > 0:
			label.add_theme_font_size_override(&"font_size", comms_px)
	if has_theme_font(FONT_COMMS, THEME_TYPE):
		for label: Label in _comms_labels:
			label.add_theme_font_override(&"font", get_theme_font(FONT_COMMS, THEME_TYPE))
	_heading.add_theme_color_override(&"font_color", text_color)
	var heading_font_px: int = get_theme_font_size(FONT_SIZE_HEADING, THEME_TYPE)
	if heading_font_px > 0:
		_heading.add_theme_font_size_override(&"font_size", heading_font_px)
	var normal: StyleBox = get_theme_stylebox(STYLE_BUTTON_NORMAL, THEME_TYPE)
	var hover: StyleBox = get_theme_stylebox(STYLE_BUTTON_HOVER, THEME_TYPE)
	var focus: StyleBox = get_theme_stylebox(STYLE_BUTTON_FOCUS, THEME_TYPE)
	var font_px: int = get_theme_font_size(FONT_SIZE_BUTTON, THEME_TYPE)
	for button: Button in [_resume, _restart, _quit]:
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
