class_name LevelIntroCard
extends Control
## The "LEVEL N" title card (Epic 7 playtest L, 2026-10-14): a big centred
## "LEVEL N" with the level's name under it, shown at the start of a campaign
## level before its briefing or wave 1.
##
## Driven only by Events (the HUD rule): Events.level_intro_started(number,
## name, hold_s) shows it. It fades in over ui.level_intro.fade_in_s, holds for
## hold_s, fades out over fade_out_s, then hides. The level itself waits
## total_s(...) of game time before it starts (level.gd), so the card never
## blocks anything on its own.
##
## PAUSABLE: the fade runs on _process, so it freezes under any pause, like the
## level's start timer. Mouse-transparent. Built in code: the Number and Name
## Labels span the full width; Number's vertical centre sits on
## ui.level_intro.center_y at number_px, Name sits gap_px below it at name_px.
## Colours and the glow come from the Theme type `LevelIntro` (colors/number,
## colors/number_glow, colors/name, constants/glow_px). On a failed config it
## shows nothing (the level shows no card then either).

const THEME_TYPE: StringName = &"LevelIntro"
const COLOR_NUMBER: StringName = &"number"
const COLOR_NUMBER_GLOW: StringName = &"number_glow"
const COLOR_NAME: StringName = &"name"
const CONSTANT_GLOW_PX: StringName = &"glow_px"
const TEXT_FORMAT: String = "LEVEL %d"
## A text label is this many times its font size tall, so the glyphs fit inside
## it (as TitleScreen.LOGO_BOX_SCALE did for the old text logo).
const TEXT_BOX_SCALE: float = 2.0

var _number: Label
var _name: Label
var _fade_in_s: float = 0.0
var _hold_s: float = 0.0
var _fade_out_s: float = 0.0
var _t: float = 0.0
var _active: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_number = _make_label("Number")
	_name = _make_label("Name")
	visible = false
	Events.level_intro_started.connect(_on_events_level_intro_started)


## The card's alpha `t` seconds after it starts: 0 -> 1 over fade_in, 1 for
## hold, 1 -> 0 over fade_out, 0 after.
static func alpha_at(t: float, fade_in: float, hold: float, fade_out: float) -> float:
	if t < 0.0:
		return 0.0
	if t < fade_in:
		return t / fade_in
	if t < fade_in + hold:
		return 1.0
	if t < fade_in + hold + fade_out:
		return 1.0 - (t - fade_in - hold) / fade_out
	return 0.0


## The card's whole time on screen.
static func total_s(fade_in: float, hold: float, fade_out: float) -> float:
	return maxf(fade_in, 0.0) + maxf(hold, 0.0) + maxf(fade_out, 0.0)


## True while the card is showing (fading in, holding or fading out).
func is_showing() -> bool:
	return _active


## The "LEVEL N" label (tests).
func number_label() -> Label:
	return _number


## The level-name label (tests).
func name_label() -> Label:
	return _name


func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	modulate.a = alpha_at(_t, _fade_in_s, _hold_s, _fade_out_s)
	if _t >= total_s(_fade_in_s, _hold_s, _fade_out_s):
		_active = false
		visible = false


func _on_events_level_intro_started(level_number: int, level_name: String, hold_s: float) -> void:
	if not Config.load_error.is_empty():
		return
	_fade_in_s = maxf(Config.num("ui.level_intro.fade_in_s"), 0.0)
	_fade_out_s = maxf(Config.num("ui.level_intro.fade_out_s"), 0.0)
	_hold_s = maxf(hold_s, 0.0)
	_number.text = TEXT_FORMAT % level_number
	_name.text = level_name.to_upper()
	_layout()
	_apply_theme()
	_t = 0.0
	_active = true
	modulate.a = alpha_at(0.0, _fade_in_s, _hold_s, _fade_out_s)
	visible = true


func _make_label(label_name: String) -> Label:
	var label: Label = Label.new()
	label.name = label_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)
	return label


func _layout() -> void:
	var number_px: float = Config.num("ui.level_intro.number_px")
	var name_px: float = Config.num("ui.level_intro.name_px")
	var center_y: float = Config.num("ui.level_intro.center_y")
	var gap_px: float = Config.num("ui.level_intro.gap_px")
	var number_h: float = number_px * TEXT_BOX_SCALE
	_number.position = Vector2(0.0, center_y - number_h / 2.0)
	_number.size = Vector2(Playfield.SIZE.x, number_h)
	_number.add_theme_font_size_override(&"font_size", int(number_px))
	# The name's glyph top sits gap_px below the number's glyph bottom.
	var name_h: float = name_px * TEXT_BOX_SCALE
	var name_center: float = center_y + number_px / 2.0 + gap_px + name_px / 2.0
	_name.position = Vector2(0.0, name_center - name_h / 2.0)
	_name.size = Vector2(Playfield.SIZE.x, name_h)
	_name.add_theme_font_size_override(&"font_size", int(name_px))


func _apply_theme() -> void:
	_number.add_theme_color_override(&"font_color", get_theme_color(COLOR_NUMBER, THEME_TYPE))
	_number.add_theme_color_override(&"font_shadow_color", get_theme_color(COLOR_NUMBER_GLOW, THEME_TYPE))
	_number.add_theme_constant_override(&"shadow_offset_x", 0)
	_number.add_theme_constant_override(&"shadow_offset_y", 0)
	_number.add_theme_constant_override(&"shadow_outline_size", get_theme_constant(CONSTANT_GLOW_PX, THEME_TYPE))
	_name.add_theme_color_override(&"font_color", get_theme_color(COLOR_NAME, THEME_TYPE))
