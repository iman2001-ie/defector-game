class_name CommsPanel
extends Control
## The story comms panel (Story 5.1, UX "Story panel"): a dim over the
## playfield and a centred conversation panel with a placeholder portrait, the
## speaker's uppercase name in its accent colour, typewriter text and the
## lowercase `click to continue ▸` cue. It has no buttons.
##
## A view only: it never reads dialogue data, and only CommsChannel calls it
## (open, close, show_line, is_typing, complete_line). Mouse-transparent
## (MOUSE_FILTER_IGNORE on it and every child), so the advance click reaches
## CommsChannel._unhandled_input. Runs while paused (PROCESS_MODE_ALWAYS), and
## the typewriter tween keeps running under the story pause.
##
## Colours, font sizes and the panel style come from the shared Theme (type
## `CommsPanel`); the portrait frame is the only per-node style override (the
## panel box with its border in the speaker accent). Layout numbers come from
## `ui.comms_panel`, speaker names and the portrait flag from `comms.speakers`,
## the typing speed from `comms.chars_per_s`. All are cached in _ready.

const THEME_TYPE: StringName = &"CommsPanel"
const COLOR_DIM: StringName = &"dim"
const COLOR_TEXT: StringName = &"text"
const COLOR_MUTED: StringName = &"muted"
const STYLE_PANEL: StringName = &"panel"
const FONT_SIZE_TEXT: StringName = &"text"
const FONT_SIZE_NAME: StringName = &"name"
const FONT_SIZE_CUE: StringName = &"cue"
## Text line spacing: 0 so four 30 px lines fit the 168 px text block.
const CONSTANT_LINE_SPACING: StringName = &"line_spacing"
const TEXT_CUE: String = "click to continue ▸"
## Keys of the layout() result.
const RECT_PANEL: StringName = &"panel"
const RECT_PORTRAIT: StringName = &"portrait"
const RECT_NAME: StringName = &"name"
const RECT_TEXT: StringName = &"text"
const RECT_CUE: StringName = &"cue"

var chars_per_s: float = 0.0

## `ui.comms_panel` numbers.
var _panel_rect: Rect2 = Rect2()
var _padding: float = 0.0
var _portrait_px: float = 0.0
var _portrait_gap: float = 0.0
var _name_h: float = 0.0
var _name_gap: float = 0.0
var _cue_h: float = 0.0
## `comms.speakers`: speaker id (String) -> {"name", "portrait"}.
var _speakers: Dictionary = {}
var _text_color: Color = Color.WHITE
var _frame_style: StyleBox = null
var _tween: Tween = null
var _speaker: StringName = &""

@onready var _dim: ColorRect = $Dim
@onready var _panel: Panel = $Panel
@onready var _portrait: Panel = $Panel/Portrait
@onready var _initial: Label = $Panel/Portrait/Initial
@onready var _name: Label = $Panel/Name
@onready var _text: Label = $Panel/Text
@onready var _cue: Label = $Panel/Cue


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	chars_per_s = Config.num("comms.chars_per_s")
	if chars_per_s <= 0.0:
		Log.warn("data", "comms.chars_per_s %.2f must be positive; lines show at once" % chars_per_s)
	_panel_rect = Rect2(
		Config.num("ui.comms_panel.x"), Config.num("ui.comms_panel.y"),
		maxf(Config.num("ui.comms_panel.w"), 1.0), maxf(Config.num("ui.comms_panel.h"), 1.0))
	_padding = maxf(Config.num("ui.comms_panel.padding_px"), 0.0)
	_portrait_px = maxf(Config.num("ui.comms_panel.portrait_px"), 0.0)
	_portrait_gap = maxf(Config.num("ui.comms_panel.portrait_gap_px"), 0.0)
	_name_h = maxf(Config.num("ui.comms_panel.name_h_px"), 0.0)
	_name_gap = maxf(Config.num("ui.comms_panel.name_gap_px"), 0.0)
	_cue_h = maxf(Config.num("ui.comms_panel.cue_h_px"), 0.0)
	_speakers = Config.section("comms.speakers")
	for child: Control in [_dim, _panel, _portrait, _initial, _name, _text, _cue]:
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.clip_text = true
	_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_cue.text = TEXT_CUE
	_cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cue.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_theme()
	_apply_layout(true)
	visible = false


# --- Channel API ------------------------------------------------------------------

## Shows the dim and the panel.
func open() -> void:
	visible = true


## Hides everything and stops the typewriter.
func close() -> void:
	_kill_tween()
	visible = false
	_speaker = &""


## Shows one line: the uppercase name from comms.speakers in the speaker's
## accent, the portrait only when the speaker has one (the text block re-laid
## out for either variant), and the text typed from the first character.
func show_line(speaker: StringName, text: String) -> void:
	_speaker = speaker
	var raw: Variant = _speakers.get(String(speaker))
	var info: Dictionary = raw if raw is Dictionary else {}
	var display_name: String = str(info.get("name", String(speaker))).to_upper()
	var with_portrait: bool = info.get("portrait") is bool and bool(info.get("portrait"))
	var accent: Color = accent_color(speaker)
	_name.text = display_name
	_name.add_theme_color_override(&"font_color", accent)
	_portrait.visible = with_portrait
	if with_portrait:
		_initial.text = display_name.left(1)
		_initial.add_theme_color_override(&"font_color", accent)
		_apply_frame(accent)
	_apply_layout(with_portrait)
	_text.text = text
	_type()


func is_typing() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


## Shows the whole current line at once.
func complete_line() -> void:
	_kill_tween()
	_text.visible_characters = -1


# --- Read accessors (tests) --------------------------------------------------------

## The speaker's accent from the Theme (`CommsPanel/colors/<speaker>`); the text
## colour for a speaker without one.
func accent_color(speaker: StringName) -> Color:
	if has_theme_color(speaker, THEME_TYPE):
		return get_theme_color(speaker, THEME_TYPE)
	return _text_color


func current_speaker() -> StringName:
	return _speaker


## The panel, portrait, name, text and cue rects (keys RECT_*). The panel rect
## is in canvas coordinates (x, y, w, h); the others are local to the panel.
## The portrait sits at (padding, padding), portrait_px square. The text block
## starts after the portrait and its gap (or at the padding without a
## portrait) and spans to the right padding; the name is on top, the text
## below it after name_gap, and the cue is the bottom cue_h of the block.
static func layout(x: float, y: float, w: float, h: float, padding: float, portrait_px: float, portrait_gap: float, name_h: float, name_gap: float, cue_h: float, with_portrait: bool) -> Dictionary:
	var left: float = padding + (portrait_px + portrait_gap if with_portrait else 0.0)
	var block_w: float = maxf(w - padding - left, 0.0)
	var text_top: float = padding + name_h + name_gap
	var text_h: float = maxf(h - padding - cue_h - text_top, 0.0)
	return {
		RECT_PANEL: Rect2(x, y, w, h),
		RECT_PORTRAIT: Rect2(padding, padding, portrait_px, portrait_px),
		RECT_NAME: Rect2(left, padding, block_w, name_h),
		RECT_TEXT: Rect2(left, text_top, block_w, text_h),
		RECT_CUE: Rect2(left, h - padding - cue_h, block_w, cue_h),
	}


# --- Internals ---------------------------------------------------------------------

## Tweens visible_characters from 0 to the character count over
## count / chars_per_s seconds, on this node, running while paused.
func _type() -> void:
	_kill_tween()
	var count: int = _text.text.length()
	if chars_per_s <= 0.0 or count == 0:
		_text.visible_characters = -1
		return
	_text.visible_characters = 0
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_text, ^"visible_characters", count, count / chars_per_s).from(0)
	_tween.finished.connect(_on_typed)


func _on_typed() -> void:
	_text.visible_characters = -1
	_tween = null


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _apply_layout(with_portrait: bool) -> void:
	var rects: Dictionary = layout(_panel_rect.position.x, _panel_rect.position.y, _panel_rect.size.x, _panel_rect.size.y,
		_padding, _portrait_px, _portrait_gap, _name_h, _name_gap, _cue_h, with_portrait)
	_set_rect(_panel, rects[RECT_PANEL] as Rect2)
	_set_rect(_portrait, rects[RECT_PORTRAIT] as Rect2)
	_set_rect(_initial, Rect2(Vector2.ZERO, (rects[RECT_PORTRAIT] as Rect2).size))
	_set_rect(_name, rects[RECT_NAME] as Rect2)
	_set_rect(_text, rects[RECT_TEXT] as Rect2)
	_set_rect(_cue, rects[RECT_CUE] as Rect2)


func _set_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


## The portrait frame: a copy of the panel box with its border in `accent`
## (the one allowed per-node style override).
func _apply_frame(accent: Color) -> void:
	var frame: StyleBox = _frame_style.duplicate() if _frame_style != null else null
	if frame is StyleBoxFlat:
		(frame as StyleBoxFlat).border_color = accent
	if frame != null:
		_portrait.add_theme_stylebox_override(&"panel", frame)


## Copies the CommsPanel theme items onto the children (their own theme types
## are ColorRect / Panel / Label).
func _apply_theme() -> void:
	_dim.color = get_theme_color(COLOR_DIM, THEME_TYPE)
	_text_color = get_theme_color(COLOR_TEXT, THEME_TYPE)
	var panel_style: StyleBox = get_theme_stylebox(STYLE_PANEL, THEME_TYPE)
	_panel.add_theme_stylebox_override(&"panel", panel_style)
	_frame_style = panel_style
	_text.add_theme_color_override(&"font_color", _text_color)
	if has_theme_constant(CONSTANT_LINE_SPACING, THEME_TYPE):
		_text.add_theme_constant_override(&"line_spacing", get_theme_constant(CONSTANT_LINE_SPACING, THEME_TYPE))
	_cue.add_theme_color_override(&"font_color", get_theme_color(COLOR_MUTED, THEME_TYPE))
	var sizes: Dictionary = {_text: FONT_SIZE_TEXT, _name: FONT_SIZE_NAME, _initial: FONT_SIZE_NAME, _cue: FONT_SIZE_CUE}
	for label: Label in sizes:
		var font_px: int = get_theme_font_size(sizes[label] as StringName, THEME_TYPE)
		if font_px > 0:
			label.add_theme_font_size_override(&"font_size", font_px)
