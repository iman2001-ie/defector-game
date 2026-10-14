class_name CommsBox
extends Control
## The combat comms box (Story 5.2, UX "Interruption box"; moved by Epic 7
## playtest C): a bottom-centre box with a speaker-accent left edge, a
## portrait, the speaker's uppercase name and one short typed line.
## No dim, no cue, never pauses. It rises into place (from `ui.comms_box.rise_px`
## lower, fading in) over comms.box_rise_in_s.
##
## See-through: while visible, each frame (step_see_through) it checks whether
## the Player (Groups.PLAYER) or an enemy projectile (Groups.PROJECTILES on the
## CollisionLayers.ENEMY_SHOTS layer; player shots are ignored) is inside the box
## rect grown by `see_through_margin_px`; if so the Box panel's alpha eases
## down to `see_through_alpha`, else back up to 1, at `see_through_fade_per_s`
## alpha per second. The see-through factor lives on the Box panel's modulate,
## the rise-in and the fade-out on the root modulate, so they compose. Enemy
## shots are tracked from SceneTree.node_added / node_removed, so the per-frame
## check allocates nothing.
##
## A view only: it never reads dialogue data, and only CommsChannel calls it
## (show_line, cut_off, dismiss, hide_now, is_typing, is_open). A cut-off line
## (Story 5.4) types only to its `cut_off_at` characters, at the slower
## `comms.cutoff_chars_per_s`, and cut_off shows it with the cut suffix. Mouse-transparent
## (MOUSE_FILTER_IGNORE on it and every child), so clicks reach the game.
## The process mode is inherited (pausable in the level), and every tween is
## created on the box with the default pause mode, so the rise, the typewriter
## and the fade freeze while the tree is paused and resume where they were.
##
## Portrait (Story 8.2): a speaker with comms.speakers.<id>.portrait true shows
## its CommsPortraits texture in `Portrait/Image` (inset by the frame border);
## without a texture it shows the placeholder initial instead.
##
## The text font, font sizes, the line spacing and the box style come from the shared Theme
## (type `CommsBox`); the text colour and the speaker accents are the
## `CommsPanel` colours, shared with the story panel. The portrait frame is the
## only per-node style override; the `Edge` colour is set on the ColorRect.
## Layout numbers come from `ui.comms_box` (the box is `w` x `h`, centred
## horizontally on the Playfield, its bottom `bottom_margin_px` above the
## screen's bottom), speaker names and the portrait flag from `comms.speakers`,
## the typing speeds and the rise / fade times from `comms`. All are cached in
## _ready.

const THEME_TYPE: StringName = &"CommsBox"
## Colours shared with the story panel.
const COLOR_THEME_TYPE: StringName = &"CommsPanel"
const COLOR_TEXT: StringName = &"text"
const STYLE_PANEL: StringName = &"panel"
const FONT_SIZE_TEXT: StringName = &"text"
const FONT_SIZE_NAME: StringName = &"name"
const CONSTANT_LINE_SPACING: StringName = &"line_spacing"
## The text font: a base-less FontVariation (the engine font, not the Theme's
## Kenney Future default; Story 8.2) whose spacing_top /
## spacing_bottom trim the 28 px line box (39 px) to a 33 px line height
## (`ui.comms_box.text_line_h_px`), so two lines fill the 66 px text rect exactly.
const FONT_TEXT: StringName = &"text"
## Keys of the layout() result.
const RECT_BOX: StringName = &"box"
const RECT_EDGE: StringName = &"edge"
const RECT_PORTRAIT: StringName = &"portrait"
const RECT_NAME: StringName = &"name"
const RECT_TEXT: StringName = &"text"

var chars_per_s: float = 0.0
## `comms.cutoff_chars_per_s`: the typing speed of a cut-off line (GDD decision #43).
var cutoff_chars_per_s: float = 0.0

## `ui.comms_box` numbers.
var _box_rect: Rect2 = Rect2()
var _edge: float = 0.0
var _padding: float = 0.0
var _portrait_px: float = 0.0
var _portrait_gap: float = 0.0
var _name_h: float = 0.0
var _line_h: float = 0.0
var _lines: int = 0
## `ui.comms_box.rise_px` and the see-through numbers.
var _rise_px: float = 0.0
var _see_through_alpha: float = 1.0
var _see_through_margin: float = 0.0
var _see_through_fade_per_s: float = 0.0
## The box rect grown by the see-through margin (canvas coordinates).
var _see_through_rect: Rect2 = Rect2()
## The Box panel's current see-through alpha (1 = opaque).
var _see_through: float = 1.0
## Live enemy-shot candidates (Area2D on the enemy-shots layer), tracked from
## node_added / node_removed; the group is checked per frame.
var _enemy_shots: Array[Area2D] = []
## `comms.box_rise_in_s` / `comms.box_fade_out_s`.
var _rise_s: float = 0.0
var _fade_s: float = 0.0
## `comms.speakers`: speaker id (String) -> {"name", "portrait"}.
var _speakers: Dictionary = {}
var _text_color: Color = Color.WHITE
var _frame_style: StyleBox = null
var _type_tween: Tween = null
var _rise_tween: Tween = null
var _fade_tween: Tween = null
var _speaker: StringName = &""
## Speaker id -> portrait texture (a copy of CommsPortraits.TEXTURES; tests
## may change it). A portrait speaker missing here shows the initial.
var portraits: Dictionary[StringName, Texture2D] = CommsPortraits.TEXTURES.duplicate()

@onready var _box: Panel = $Box
@onready var _edge_rect: ColorRect = $Box/Edge
@onready var _portrait: Panel = $Box/Portrait
@onready var _initial: Label = $Box/Portrait/Initial
@onready var _image: TextureRect = $Box/Portrait/Image
@onready var _name: Label = $Box/Name
@onready var _text: Label = $Box/Text


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	chars_per_s = Config.num("comms.chars_per_s")
	cutoff_chars_per_s = Config.num("comms.cutoff_chars_per_s")
	_rise_s = maxf(Config.num("comms.box_rise_in_s"), 0.0)
	_fade_s = maxf(Config.num("comms.box_fade_out_s"), 0.0)
	_box_rect = box_rect(Playfield.SIZE, maxf(Config.num("ui.comms_box.w"), 1.0),
		maxf(Config.num("ui.comms_box.h"), 1.0), maxf(Config.num("ui.comms_box.bottom_margin_px"), 0.0))
	_rise_px = maxf(Config.num("ui.comms_box.rise_px"), 0.0)
	_see_through_alpha = clampf(Config.num("ui.comms_box.see_through_alpha"), 0.0, 1.0)
	_see_through_margin = maxf(Config.num("ui.comms_box.see_through_margin_px"), 0.0)
	_see_through_fade_per_s = maxf(Config.num("ui.comms_box.see_through_fade_per_s"), 0.0)
	_see_through_rect = _box_rect.grow(_see_through_margin)
	_edge = maxf(Config.num("ui.comms_box.edge_px"), 0.0)
	_padding = maxf(Config.num("ui.comms_box.padding_px"), 0.0)
	_portrait_px = maxf(Config.num("ui.comms_box.portrait_px"), 0.0)
	_portrait_gap = maxf(Config.num("ui.comms_box.portrait_gap_px"), 0.0)
	_name_h = maxf(Config.num("ui.comms_box.name_h_px"), 0.0)
	_line_h = maxf(Config.num("ui.comms_box.text_line_h_px"), 0.0)
	_lines = maxi(Config.int_("ui.comms_box.text_lines"), 0)
	_speakers = Config.section("comms.speakers")
	for child: Control in [_box, _edge_rect, _portrait, _initial, _image, _name, _text]:
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.clip_text = true
	_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# The 512 px portraits are drawn far smaller: sample their mipmaps.
	_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_apply_theme()
	_apply_layout(true)
	visible = false


func _enter_tree() -> void:
	_enemy_shots.clear()
	get_tree().node_added.connect(_on_tree_node_added)
	get_tree().node_removed.connect(_on_tree_node_removed)
	# Shots already in the tree (one-off; later ones arrive through node_added).
	for node: Node in get_tree().get_nodes_in_group(Groups.PROJECTILES):
		_on_tree_node_added(node)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.disconnect(_on_tree_node_added)
	if get_tree().node_removed.is_connected(_on_tree_node_removed):
		get_tree().node_removed.disconnect(_on_tree_node_removed)
	_enemy_shots.clear()


func _process(delta: float) -> void:
	if visible:
		step_see_through(delta)


# --- Channel API ------------------------------------------------------------------

## Shows one line: the uppercase name from comms.speakers in the speaker's
## accent, the accent edge, the portrait only when the speaker has one (the
## text block re-laid out for either variant). The box rises into place and
## fades in, and the text types from the first character. With
## `cut_off_at >= 0` (a cut-off line, Story 5.4) it types only to `cut_off_at`
## characters over cut_off_at / cutoff_chars_per_s and stays there (never -1).
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
		var picture: Texture2D = portraits.get(speaker) as Texture2D
		_image.texture = picture
		_image.visible = picture != null
		_initial.visible = picture == null
		_initial.text = display_name.left(1)
		_initial.add_theme_color_override(&"font_color", accent)
		_apply_frame(accent)
	_apply_layout(with_portrait)
	_text.text = text
	visible = true
	_rise_in()
	_type(cut_off_at)


## Fades the box out over box_fade_out_s with a sine ease-out (quick at first,
## then settling softly into nothing), then hides it.
func dismiss() -> void:
	if not visible:
		return
	_kill_tween(_fade_tween)
	_fade_tween = null
	# The fade takes over the root alpha from a rise still running.
	_kill_tween(_rise_tween)
	_rise_tween = null
	_box.position.y = _box_rect.position.y
	if _fade_s <= 0.0:
		_hide()
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, ^"modulate:a", 0.0, _fade_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_fade_tween.finished.connect(_hide)


## The cut-off moment (Story 5.4): stops the typewriter and shows exactly the
## first `chars` characters. With a `suffix` (comms.cutoff_suffix, "...", GDD
## decision #43) the text becomes those characters plus the suffix, all
## visible; with an empty one the text is kept and only `chars` show.
func cut_off(chars: int, suffix: String = "") -> void:
	_kill_tween(_type_tween)
	_type_tween = null
	var shown: int = maxi(chars, 0)
	if suffix.is_empty():
		_text.visible_characters = shown
		return
	_text.text = _text.text.left(shown) + suffix
	_text.visible_characters = -1


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


## The Box panel's see-through alpha (1 = opaque, see_through_alpha at most see-through).
func see_through() -> float:
	return _see_through


## The rect the Player or an enemy shot must be inside to make the box see-through.
func see_through_rect() -> Rect2:
	return _see_through_rect


## The box rect in canvas coordinates: `w` x `h`, centred horizontally on
## `canvas`, its bottom `bottom_margin` above the canvas bottom.
static func box_rect(canvas: Vector2, w: float, h: float, bottom_margin: float) -> Rect2:
	return Rect2((canvas.x - w) / 2.0, canvas.y - bottom_margin - h, w, h)


## One see-through step of `delta` seconds: eases the Box panel's alpha towards
## see_through_alpha while the Player or an enemy shot is under the box (see
## is_covering), else towards 1. Allocates nothing.
func step_see_through(delta: float) -> void:
	var target: float = _see_through_alpha if is_covering() else 1.0
	_see_through = move_toward(_see_through, target, _see_through_fade_per_s * maxf(delta, 0.0))
	_box.modulate.a = _see_through


## True while the Player or a live enemy projectile (Groups.PROJECTILES on the
## enemy-shots layer) is inside see_through_rect() (screen position).
func is_covering() -> bool:
	var player: Node = get_tree().get_first_node_in_group(Groups.PLAYER)
	if player is CanvasItem and _covers(player as CanvasItem):
		return true
	for shot: Area2D in _enemy_shots:
		if _is_enemy_shot(shot) and _covers(shot):
			return true
	return false


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

## Raises Box from rise_px below its y into place while the root alpha fades
## from 0 to 1, both over box_rise_in_s (sine ease-out).
func _rise_in() -> void:
	var to_y: float = _box_rect.position.y
	_box.position.x = _box_rect.position.x
	if _rise_s <= 0.0:
		_box.position.y = to_y
		modulate.a = 1.0
		return
	_box.position.y = to_y + _rise_px
	modulate.a = 0.0
	_rise_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_rise_tween.tween_property(_box, ^"position:y", to_y, _rise_s).from(to_y + _rise_px)
	_rise_tween.tween_property(self, ^"modulate:a", 1.0, _rise_s).from(0.0)


## Whether `item`'s screen position (camera included) is inside the see-through rect.
func _covers(item: CanvasItem) -> bool:
	return _see_through_rect.has_point(item.get_global_transform_with_canvas().origin)


## A live projectile on the enemy-shots layer (player shots never count).
func _is_enemy_shot(shot: Area2D) -> bool:
	return is_instance_valid(shot) and shot.is_inside_tree() and shot.is_in_group(Groups.PROJECTILES) \
		and (shot.collision_layer & CollisionLayers.ENEMY_SHOTS) != 0


## Tracks an enemy-shot candidate: an Area2D on the enemy-shots layer (the
## Projectile joins its group in _ready, after node_added).
func _on_tree_node_added(node: Node) -> void:
	if node is Area2D and ((node as Area2D).collision_layer & CollisionLayers.ENEMY_SHOTS) != 0 and not _enemy_shots.has(node):
		_enemy_shots.append(node as Area2D)


func _on_tree_node_removed(node: Node) -> void:
	if node is Area2D:
		_enemy_shots.erase(node)


## Tweens visible_characters from 0 to the character count over
## count / chars_per_s seconds (default pause mode: freezes while paused).
## With `cut_off_at >= 0` it types only to that count, over
## count / cutoff_chars_per_s, and keeps it at the end (a cut-off line never
## shows the whole text). A speed of 0 or less shows the count at once.
func _type(cut_off_at: int = -1) -> void:
	var cut: bool = cut_off_at >= 0
	var count: int = mini(cut_off_at, _text.text.length()) if cut else _text.text.length()
	var speed: float = cutoff_chars_per_s if cut else chars_per_s
	if speed <= 0.0 or count == 0:
		_text.visible_characters = count if cut else -1
		return
	_text.visible_characters = 0
	_type_tween = create_tween()
	_type_tween.tween_property(_text, ^"visible_characters", count, count / speed).from(0)
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
	_see_through = 1.0
	_box.modulate.a = 1.0
	_box.position = _box_rect.position
	_speaker = &""


func _kill_tweens() -> void:
	for tween: Tween in [_type_tween, _rise_tween, _fade_tween]:
		_kill_tween(tween)
	_type_tween = null
	_rise_tween = null
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
	_set_rect(_image, CommsPortraits.image_rect((rects[RECT_PORTRAIT] as Rect2).size, _frame_style))
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
