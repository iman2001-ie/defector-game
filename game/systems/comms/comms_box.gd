class_name CommsBox
extends Control
## The combat comms box (Story 5.2, UX "Interruption box"): a small top-left
## box with a speaker-accent left edge, a placeholder portrait, the speaker's
## uppercase name and one short typed line. No dim, no cue, never pauses.
##
## A view only: it never reads dialogue data, and only CommsChannel calls it
## (show_line, cut_off, dismiss, hide_now, is_typing, is_open). A cut-off line
## (Story 5.4) types only to its `cut_off_at` characters and stays there. Mouse-transparent
## (MOUSE_FILTER_IGNORE on it and every child), so clicks reach the game.
## The process mode is inherited (pausable in the level), and every tween is
## created on the box with the default pause mode, so the slide, the typewriter
## and the fade freeze while the tree is paused and resume where they were.
##
## The text font, font sizes, the line spacing and the box style come from the shared Theme
## (type `CommsBox`); the text colour and the speaker accents are the
## `CommsPanel` colours, shared with the story panel. The portrait frame is the
## only per-node style override; the `Edge` colour is set on the ColorRect.
## Layout numbers come from `ui.comms_box`, speaker names and the portrait flag
## from `comms.speakers`, the typing speed and the slide / fade times from
## `comms`. All are cached in _ready.

const THEME_TYPE: StringName = &"CommsBox"
## Colours shared with the story panel.
const COLOR_THEME_TYPE: StringName = &"CommsPanel"
const COLOR_TEXT: StringName = &"text"
const STYLE_PANEL: StringName = &"panel"
const FONT_SIZE_TEXT: StringName = &"text"
const FONT_SIZE_NAME: StringName = &"name"
const CONSTANT_LINE_SPACING: StringName = &"line_spacing"
## The text font: a FontVariation of the default font whose spacing_top /
## spacing_bottom trim the 24 px line box to the UX 28 px line height, so two
## lines fill the 56 px text rect exactly.
const FONT_TEXT: StringName = &"text"
## Keys of the layout() result.
const RECT_BOX: StringName = &"box"
const RECT_EDGE: StringName = &"edge"
const RECT_PORTRAIT: StringName = &"portrait"
const RECT_NAME: StringName = &"name"
const RECT_TEXT: StringName = &"text"

var chars_per_s: float = 0.0

## `ui.comms_box` numbers.
var _box_rect: Rect2 = Rect2()
var _edge: float = 0.0
var _padding: float = 0.0
var _portrait_px: float = 0.0
var _portrait_gap: float = 0.0
var _name_h: float = 0.0
var _line_h: float = 0.0
var _lines: int = 0
## `comms.box_slide_in_s` / `comms.box_fade_out_s`.
var _slide_s: float = 0.0
var _fade_s: float = 0.0
## `comms.speakers`: speaker id (String) -> {"name", "portrait"}.
var _speakers: Dictionary = {}
var _text_color: Color = Color.WHITE
var _frame_style: StyleBox = null
var _type_tween: Tween = null
var _slide_tween: Tween = null
var _fade_tween: Tween = null
var _speaker: StringName = &""

@onready var _box: Panel = $Box
@onready var _edge_rect: ColorRect = $Box/Edge
@onready var _portrait: Panel = $Box/Portrait
@onready var _initial: Label = $Box/Portrait/Initial
@onready var _name: Label = $Box/Name
@onready var _text: Label = $Box/Text


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	chars_per_s = Config.num("comms.chars_per_s")
	_slide_s = maxf(Config.num("comms.box_slide_in_s"), 0.0)
	_fade_s = maxf(Config.num("comms.box_fade_out_s"), 0.0)
	_box_rect = Rect2(
		Config.num("ui.comms_box.x"), Config.num("ui.comms_box.y"),
		maxf(Config.num("ui.comms_box.w"), 1.0), maxf(Config.num("ui.comms_box.h"), 1.0))
	_edge = maxf(Config.num("ui.comms_box.edge_px"), 0.0)
	_padding = maxf(Config.num("ui.comms_box.padding_px"), 0.0)
	_portrait_px = maxf(Config.num("ui.comms_box.portrait_px"), 0.0)
	_portrait_gap = maxf(Config.num("ui.comms_box.portrait_gap_px"), 0.0)
	_name_h = maxf(Config.num("ui.comms_box.name_h_px"), 0.0)
	_line_h = maxf(Config.num("ui.comms_box.text_line_h_px"), 0.0)
	_lines = maxi(Config.int_("ui.comms_box.text_lines"), 0)
	_speakers = Config.section("comms.speakers")
	for child: Control in [_box, _edge_rect, _portrait, _initial, _name, _text]:
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.clip_text = true
	_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_theme()
	_apply_layout(true)
	visible = false


# --- Channel API ------------------------------------------------------------------

## Shows one line: the uppercase name from comms.speakers in the speaker's
## accent, the accent edge, the portrait only when the speaker has one (the
## text block re-laid out for either variant). The box slides in from the left
## edge of the screen and the text types from the first character. With
## `cut_off_at >= 0` (a cut-off line, Story 5.4) it types only to `cut_off_at`
## characters over cut_off_at / chars_per_s and stays there (never -1).
func show_line(speaker: StringName, text: String, cut_off_at: int = -1) -> void:
	_kill_tweens()
	_speaker = speaker
	var raw: Variant = _speakers.get(String(speaker))
	var info: Dictionary = raw if raw is Dictionary else {}
	var display_name: String = str(info.get("name", String(speaker))).to_upper()
	var with_portrait: bool = info.get("portrait") is bool and bool(info.get("portrait"))
	var accent: Color = accent_color(speaker)
	_name.text = display_name
	_name.add_theme_color_override(&"font_color", accent)
	_edge_rect.color = accent
	_portrait.visible = with_portrait
	if with_portrait:
		_initial.text = display_name.left(1)
		_initial.add_theme_color_override(&"font_color", accent)
		_apply_frame(accent)
	_apply_layout(with_portrait)
	_text.text = text
	modulate.a = 1.0
	visible = true
	_slide_in()
	_type(cut_off_at)


## Fades the box out over box_fade_out_s, then hides it.
func dismiss() -> void:
	if not visible:
		return
	_kill_tween(_fade_tween)
	_fade_tween = null
	if _fade_s <= 0.0:
		_hide()
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, ^"modulate:a", 0.0, _fade_s)
	_fade_tween.finished.connect(_hide)


## The cut-off moment (Story 5.4): stops the typewriter and shows exactly
## `chars` characters.
func cut_off(chars: int) -> void:
	_kill_tween(_type_tween)
	_type_tween = null
	_text.visible_characters = maxi(chars, 0)


## Stops every tween and hides the box at once (a story line preempts it).
func hide_now() -> void:
	_kill_tweens()
	_hide()


func is_typing() -> bool:
	return _type_tween != null and _type_tween.is_valid() and _type_tween.is_running()


## Visible and not fading out.
func is_open() -> bool:
	return visible and not (_fade_tween != null and _fade_tween.is_valid())


# --- Read accessors (tests) --------------------------------------------------------

## The speaker's accent from the Theme (`CommsPanel/colors/<speaker>`, shared
## with the story panel); the text colour for a speaker without one.
func accent_color(speaker: StringName) -> Color:
	if has_theme_color(speaker, COLOR_THEME_TYPE):
		return get_theme_color(speaker, COLOR_THEME_TYPE)
	return _text_color


func current_speaker() -> StringName:
	return _speaker


## The box, edge, portrait, name and text rects (keys RECT_*). The box rect is
## in canvas coordinates (x, y, w, h); the others are local to the box. The
## portrait is centred vertically (inset = (h - portrait_px) / 2) after the
## edge; the name and the text block start after the portrait and its gap (or
## after the inset without a portrait) and span to the right inset; the name
## sits at the top padding and the text (line_h × lines tall) right below it.
static func layout(x: float, y: float, w: float, h: float, edge: float, padding: float, portrait_px: float, portrait_gap: float, name_h: float, line_h: float, lines: int, with_portrait: bool) -> Dictionary:
	var inset: float = maxf((h - portrait_px) / 2.0, 0.0)
	var left: float = edge + inset + (portrait_px + portrait_gap if with_portrait else 0.0)
	var block_w: float = maxf(w - left - inset, 0.0)
	return {
		RECT_BOX: Rect2(x, y, w, h),
		RECT_EDGE: Rect2(0.0, 0.0, edge, h),
		RECT_PORTRAIT: Rect2(edge + inset, inset, portrait_px, portrait_px),
		RECT_NAME: Rect2(left, padding, block_w, name_h),
		RECT_TEXT: Rect2(left, padding + name_h, block_w, line_h * float(lines)),
	}


# --- Internals ---------------------------------------------------------------------

## Slides Box from x = -w to its x over box_slide_in_s.
func _slide_in() -> void:
	var to_x: float = _box_rect.position.x
	if _slide_s <= 0.0:
		_box.position.x = to_x
		return
	_box.position.x = -_box_rect.size.x
	_slide_tween = create_tween()
	_slide_tween.tween_property(_box, ^"position:x", to_x, _slide_s).from(-_box_rect.size.x)


## Tweens visible_characters from 0 to the character count over
## count / chars_per_s seconds (default pause mode: freezes while paused).
## With `cut_off_at >= 0` it types only to that count and keeps it at the end
## (a cut-off line never shows the whole text).
func _type(cut_off_at: int = -1) -> void:
	var cut: bool = cut_off_at >= 0
	var count: int = mini(cut_off_at, _text.text.length()) if cut else _text.text.length()
	if chars_per_s <= 0.0 or count == 0:
		_text.visible_characters = count if cut else -1
		return
	_text.visible_characters = 0
	_type_tween = create_tween()
	_type_tween.tween_property(_text, ^"visible_characters", count, count / chars_per_s).from(0)
	if cut:
		_type_tween.finished.connect(_on_cut_typed)
	else:
		_type_tween.finished.connect(_on_typed)


func _on_typed() -> void:
	_text.visible_characters = -1
	_type_tween = null


func _on_cut_typed() -> void:
	_type_tween = null


func _hide() -> void:
	_fade_tween = null
	visible = false
	modulate.a = 1.0
	_speaker = &""


func _kill_tweens() -> void:
	for tween: Tween in [_type_tween, _slide_tween, _fade_tween]:
		_kill_tween(tween)
	_type_tween = null
	_slide_tween = null
	_fade_tween = null


func _kill_tween(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()


func _apply_layout(with_portrait: bool) -> void:
	var rects: Dictionary = layout(_box_rect.position.x, _box_rect.position.y, _box_rect.size.x, _box_rect.size.y,
		_edge, _padding, _portrait_px, _portrait_gap, _name_h, _line_h, _lines, with_portrait)
	_set_rect(_box, rects[RECT_BOX] as Rect2)
	_set_rect(_edge_rect, rects[RECT_EDGE] as Rect2)
	_set_rect(_portrait, rects[RECT_PORTRAIT] as Rect2)
	_set_rect(_initial, Rect2(Vector2.ZERO, (rects[RECT_PORTRAIT] as Rect2).size))
	_set_rect(_name, rects[RECT_NAME] as Rect2)
	_set_rect(_text, rects[RECT_TEXT] as Rect2)


func _set_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


## The portrait frame: a copy of the box style with its border in `accent`
## (the one allowed per-node style override).
func _apply_frame(accent: Color) -> void:
	var frame: StyleBox = _frame_style.duplicate() if _frame_style != null else null
	if frame is StyleBoxFlat:
		(frame as StyleBoxFlat).border_color = accent
	if frame != null:
		_portrait.add_theme_stylebox_override(&"panel", frame)


## Copies the CommsBox theme items (and the shared CommsPanel text colour)
## onto the children (their own theme types are Panel / ColorRect / Label).
func _apply_theme() -> void:
	_text_color = get_theme_color(COLOR_TEXT, COLOR_THEME_TYPE)
	var box_style: StyleBox = get_theme_stylebox(STYLE_PANEL, THEME_TYPE)
	_box.add_theme_stylebox_override(&"panel", box_style)
	_frame_style = box_style
	_text.add_theme_color_override(&"font_color", _text_color)
	if has_theme_font(FONT_TEXT, THEME_TYPE):
		_text.add_theme_font_override(&"font", get_theme_font(FONT_TEXT, THEME_TYPE))
	if has_theme_constant(CONSTANT_LINE_SPACING, THEME_TYPE):
		_text.add_theme_constant_override(&"line_spacing", get_theme_constant(CONSTANT_LINE_SPACING, THEME_TYPE))
	var sizes: Dictionary = {_text: FONT_SIZE_TEXT, _name: FONT_SIZE_NAME, _initial: FONT_SIZE_NAME}
	for label: Label in sizes:
		var font_px: int = get_theme_font_size(sizes[label] as StringName, THEME_TYPE)
		if font_px > 0:
			label.add_theme_font_size_override(&"font_size", font_px)
