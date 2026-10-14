class_name LevelSelectScreen
extends Control
## The Level Select screen (Story 4.3, FR56; UX "Level Select"): one card per
## campaign level (1..progression.level_count) in a centred row, each with its
## `LEVEL <n>` number, the uppercased level name from data/levels/level_<n>.json
## and a thumbnail of the level's backdrop, plus BACK. The Thumbnail (Story 8.2)
## is a clipped ColorRect in the theme's `thumbnail` colour holding a
## `Background` LevelBackground set to the level's `background` id, scaled
## uniformly so the playfield covers the thumbnail, centred horizontally and
## top-aligned (the throne world hangs from the top); a null or absent id
## draws nothing, so the theme colour shows.
##
## A level is unlocked when GameState.is_level_unlocked(n) (the debug F7 flag
## counts). A locked card is disabled, drawn at ui.level_select.locked_alpha and
## shows LOCKED. An unlocked card -> SceneRouter.start_new(str(n)), a new run
## with 0 energy (playtest 2026-10-13); BACK -> SceneRouter.goto_title(). A
## second press does nothing. Writes no save.
##
## Healthy config: the layout comes from `ui.level_select`. Fatal config
## (Config.load_error set; normally unreachable because the title hides its
## buttons): no cards are built and no Config getter is called; only BACK works,
## at the position authored in level_select.tscn. Colours, sizes and button
## styles come from the shared Theme (type `LevelSelect`), copied onto the
## children in code like TitleScreen._apply_theme. Mouse-only: no focus.

const THEME_TYPE: StringName = &"LevelSelect"
const COLOR_TEXT: StringName = &"text"
const COLOR_MUTED: StringName = &"muted"
const COLOR_THUMBNAIL: StringName = &"thumbnail"
const FONT_SIZE_BUTTON: StringName = &"button"
const FONT_SIZE_NAME: StringName = &"name"
const FONT_SIZE_NUMBER: StringName = &"number"
const STYLE_BUTTON_NORMAL: StringName = &"button_normal"
const STYLE_BUTTON_HOVER: StringName = &"button_hover"
const STYLE_BUTTON_FOCUS: StringName = &"button_focus"
const TEXT_BACK: String = "BACK"
const TEXT_LOCKED: String = "LOCKED"
const TEXT_NUMBER_FORMAT: String = "LEVEL %d"
const CARD_NAME_FORMAT: String = "Card%d"
## Inner card layout (not tuning: it scales with the card size). Padding around
## the thumbnail and the text block, and the heights of the text rows.
const CARD_PAD_PX: float = 16.0
const NUMBER_ROW_PX: float = 28.0
const NAME_ROW_PX: float = 84.0

var _leaving: bool = false
var _config_failed: bool = false
var _level_count: int = 0
var _unlocked_count: int = 0
var _locked_alpha: float = 1.0

@onready var _cards: Control = $Cards
@onready var _back: Button = $Back


func _ready() -> void:
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_config_failed = not Config.load_error.is_empty()
	_back.text = TEXT_BACK
	_style_button(_back)
	if not _config_failed:
		_level_count = maxi(Config.int_("progression.level_count"), 0)
		_locked_alpha = Config.num("ui.level_select.locked_alpha")
		_build_cards()
		_layout()
		# Playtest pt7-k: the menu track keeps playing from the title.
		Audio.play_music(Audio.MENU_MUSIC)
	_back.pressed.connect(_on_back_pressed)
	Log.info("scene", "Level select ready (%d levels, %d unlocked)" % [_level_count, _unlocked_count])


## True when the config failed to load and no cards were built.
func is_config_error() -> bool:
	return _config_failed


## The card row's rect: `count` cards of `card` size with `gap` between them,
## centred horizontally, top at `top_y`.
static func cards_rect(canvas_w: float, card: Vector2, gap: float, top_y: float, count: int) -> Rect2:
	var width: float = card.x * count + gap * maxi(count - 1, 0)
	return Rect2(Vector2((canvas_w - width) / 2.0, top_y), Vector2(width, card.y))


## The background id a card's thumbnail shows: the level data's `background`
## when it is a String, else "" (null or absent: the theme colour shows).
static func thumbnail_background_id(level_data: Dictionary) -> String:
	var id: Variant = level_data.get("background")
	return id as String if id is String else ""


## Where a playfield-sized LevelBackground goes inside a `size` thumbnail:
## a uniform scale so it covers the thumbnail, centred horizontally and
## top-aligned.
static func thumbnail_transform(size: Vector2) -> Transform2D:
	var k: float = maxf(size.x / Playfield.SIZE.x, size.y / Playfield.SIZE.y)
	var origin: Vector2 = Vector2((size.x - Playfield.SIZE.x * k) / 2.0, 0.0)
	return Transform2D(0.0, Vector2(k, k), 0.0, origin)


func _on_card_pressed(n: int) -> void:
	if _leaving or _config_failed or not GameState.is_level_unlocked(n):
		return
	_leaving = true
	SceneRouter.start_new(str(n))


func _on_back_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	SceneRouter.goto_title()


# --- Cards -------------------------------------------------------------------------

## Healthy config only: one card per level id 1.._level_count under Cards.
func _build_cards() -> void:
	var text_color: Color = get_theme_color(COLOR_TEXT, THEME_TYPE)
	var muted: Color = get_theme_color(COLOR_MUTED, THEME_TYPE)
	var thumb_color: Color = get_theme_color(COLOR_THUMBNAIL, THEME_TYPE)
	var number_px: int = get_theme_font_size(FONT_SIZE_NUMBER, THEME_TYPE)
	var name_px: int = get_theme_font_size(FONT_SIZE_NAME, THEME_TYPE)
	var button_px: int = get_theme_font_size(FONT_SIZE_BUTTON, THEME_TYPE)
	for n: int in range(1, _level_count + 1):
		var unlocked: bool = GameState.is_level_unlocked(n)
		if unlocked:
			_unlocked_count += 1
		var card: Button = Button.new()
		card.name = CARD_NAME_FORMAT % n
		_style_button(card)
		var level_data: Dictionary = Config.level(str(n))
		var thumbnail: ColorRect = ColorRect.new()
		thumbnail.name = "Thumbnail"
		thumbnail.color = thumb_color
		thumbnail.clip_contents = true
		thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var background: LevelBackground = LevelBackground.new()
		background.name = "Background"
		background.animate = false  # 1-2 px stars would flicker at thumbnail scale.
		background.apply(thumbnail_background_id(level_data))
		thumbnail.add_child(background)
		card.add_child(thumbnail)
		card.add_child(_make_label("Number", TEXT_NUMBER_FORMAT % n, text_color, number_px))
		var name_label: Label = _make_label("Name", str(level_data.get("name", "")).to_upper(), text_color, name_px)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.clip_text = true
		card.add_child(name_label)
		var locked: Label = _make_label("Locked", TEXT_LOCKED, muted, button_px)
		locked.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		locked.visible = not unlocked
		card.add_child(locked)
		card.disabled = not unlocked
		if not unlocked:
			card.modulate.a = _locked_alpha
		card.pressed.connect(_on_card_pressed.bind(n))
		_cards.add_child(card)


func _make_label(node_name: String, text: String, color: Color, font_px: int) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override(&"font_color", color)
	if font_px > 0:
		label.add_theme_font_size_override(&"font_size", font_px)
	return label


# --- Layout and theme --------------------------------------------------------------

## Healthy config only: positions from ui.level_select.
func _layout() -> void:
	var card: Vector2 = Vector2(Config.num("ui.level_select.card_w"), Config.num("ui.level_select.card_h"))
	var gap: float = maxf(Config.num("ui.level_select.card_gap_px"), 0.0)
	var rect: Rect2 = cards_rect(Playfield.SIZE.x, card, gap, Config.num("ui.level_select.cards_top_y"), _level_count)
	_cards.position = rect.position
	_cards.size = rect.size
	var i: int = 0
	for child: Node in _cards.get_children():
		var button: Button = child as Button
		button.position = Vector2((card.x + gap) * i, 0.0)
		button.size = card
		_layout_card(button, card)
		i += 1
	_back.position = Vector2(Config.num("ui.level_select.back_x"), Config.num("ui.level_select.back_y"))
	_back.size = Vector2(Config.num("ui.level_select.back_w"), Config.num("ui.level_select.back_h"))


## The card's children, relative to the card: the thumbnail on top (LOCKED
## centred over it), then the number and name rows.
func _layout_card(button: Button, card: Vector2) -> void:
	var inner_w: float = maxf(card.x - CARD_PAD_PX * 2.0, 0.0)
	var thumb_h: float = maxf(card.y - CARD_PAD_PX * 3.0 - NUMBER_ROW_PX - NAME_ROW_PX, 0.0)
	var thumb: Rect2 = Rect2(Vector2(CARD_PAD_PX, CARD_PAD_PX), Vector2(inner_w, thumb_h))
	_place(button.get_node("Thumbnail") as Control, thumb)
	var background: LevelBackground = button.get_node("Thumbnail/Background") as LevelBackground
	var fit: Transform2D = thumbnail_transform(thumb.size)
	background.position = fit.origin
	background.scale = fit.get_scale()
	_place(button.get_node("Locked") as Control, thumb)
	var number_y: float = thumb.end.y + CARD_PAD_PX
	_place(button.get_node("Number") as Control, Rect2(CARD_PAD_PX, number_y, inner_w, NUMBER_ROW_PX))
	_place(button.get_node("Name") as Control, Rect2(CARD_PAD_PX, number_y + NUMBER_ROW_PX, inner_w, NAME_ROW_PX))


func _place(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


## Copies the LevelSelect button items onto `button` (its own theme type is
## Button). Reads only the Theme, never Config.
func _style_button(button: Button) -> void:
	var normal: StyleBox = get_theme_stylebox(STYLE_BUTTON_NORMAL, THEME_TYPE)
	var hover: StyleBox = get_theme_stylebox(STYLE_BUTTON_HOVER, THEME_TYPE)
	var focus: StyleBox = get_theme_stylebox(STYLE_BUTTON_FOCUS, THEME_TYPE)
	var text_color: Color = get_theme_color(COLOR_TEXT, THEME_TYPE)
	var font_px: int = get_theme_font_size(FONT_SIZE_BUTTON, THEME_TYPE)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override(&"normal", normal)
	button.add_theme_stylebox_override(&"hover", hover)
	button.add_theme_stylebox_override(&"pressed", hover)
	button.add_theme_stylebox_override(&"hover_pressed", hover)
	button.add_theme_stylebox_override(&"disabled", normal)
	button.add_theme_stylebox_override(&"focus", focus)
	for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color", &"font_disabled_color"]:
		button.add_theme_color_override(color_name, text_color)
	if font_px > 0:
		button.add_theme_font_size_override(&"font_size", font_px)
