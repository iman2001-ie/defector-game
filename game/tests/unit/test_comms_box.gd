extends GutTest
## CommsBox (Story 5.2; Epic 7 playtest C): the combat interruption box view.
## Layout from ui.comms_box (UX: box 900x124 at the bottom centre, x 510-1410,
## y 928-1052, 28 px above the bottom; text block 758 px with a portrait at
## x 124, 860 px without at x 22, y 50-116), theme items, mouse transparency,
## the speaker name / accent / edge / portrait, the rise-in, the typewriter
## (pausable), the fade-out, hide_now, a 50-character line fitting two lines
## in both variants, and the see-through while the Player or an enemy shot is
## under the box.

const BOX_SCENE: PackedScene = preload("res://systems/comms/comms_box.tscn")
const THEME_PATH: String = "res://ui/theme/defector_theme.tres"
## Realistic 50-character combat lines (the combat line limit).
const LINES_50: Array[String] = [
	"Still flying, General? Not for long, I promise ya.",
	"Mauls inbound on the convoy! Break left, General!!",
	"MAULS INBOUND ON THE CONVOY. WATCH YOUR SIX, SIR!!",
]


func after_each() -> void:
	Log.sink = Callable()
	Config.load_data()
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _make() -> CommsBox:
	var box: CommsBox = BOX_SCENE.instantiate() as CommsBox
	add_child_autofree(box)
	return box


func _node(box: CommsBox, path: String) -> Control:
	return box.get_node(path) as Control


func _label(box: CommsBox, path: String) -> Label:
	return box.get_node(path) as Label


func _assert_color(actual: Color, expected: Color, what: String) -> void:
	assert_almost_eq(actual.r, expected.r, 0.002, what + " r")
	assert_almost_eq(actual.g, expected.g, 0.002, what + " g")
	assert_almost_eq(actual.b, expected.b, 0.002, what + " b")
	assert_almost_eq(actual.a, expected.a, 0.002, what + " a")


func _layout(with_portrait: bool) -> Dictionary:
	return CommsBox.layout(510.0, 928.0, 900.0, 124.0, 4.0, 8.0, 88.0, 14.0, 42.0, 33.0, 2, with_portrait)


## The box rect from the shipped tuning.
const BOX_RECT: Rect2 = Rect2(510, 928, 900, 124)


## Shows a line and finishes its rise, so the box is in place at full alpha.
func _show_risen(box: CommsBox, speaker: StringName, text: String) -> void:
	box.show_line(speaker, text)
	if box._rise_tween != null:
		box._rise_tween.custom_step(1.0)


## A stand-in Player (only its group and position matter to the box).
func _add_player(pos: Vector2) -> Node2D:
	var player: Node2D = Node2D.new()
	player.add_to_group(Groups.PLAYER)
	player.position = pos
	add_child_autofree(player)
	return player


## A projectile stand-in on `layer` in the projectiles group.
func _add_shot(pos: Vector2, layer: int) -> Area2D:
	var shot: Area2D = Area2D.new()
	shot.collision_layer = layer
	shot.collision_mask = 0
	shot.add_to_group(Groups.PROJECTILES)
	shot.position = pos
	add_child_autofree(shot)
	return shot


# --- Data, layout and theme ---------------------------------------------------------

func test_tuning() -> void:
	var expected: Dictionary = {
		"w": 900.0, "h": 124.0, "bottom_margin_px": 28.0, "rise_px": 24.0, "edge_px": 4.0, "padding_px": 8.0,
		"portrait_px": 88.0, "portrait_gap_px": 14.0, "name_h_px": 42.0, "text_line_h_px": 33.0, "text_lines": 2.0,
		"see_through_alpha": 0.3, "see_through_margin_px": 24.0, "see_through_fade_per_s": 5.0,
	}
	for key: String in expected:
		assert_almost_eq(Config.num("ui.comms_box.%s" % key), expected[key] as float, 0.0001, "ui.comms_box.%s" % key)
	assert_eq(Config.int_("comms.combat_line_max_chars"), 50)
	assert_eq(Config.num("comms.box_rise_in_s"), 0.2)
	assert_eq(Config.num("comms.box_fade_out_s"), 0.6)
	assert_eq(_make().cutoff_chars_per_s, Config.num("comms.cutoff_chars_per_s"), "the cut-off typing speed is cached")


func test_layout_math_with_portrait() -> void:
	var rects: Dictionary = _layout(true)
	assert_eq(rects[CommsBox.RECT_BOX], BOX_RECT, "UX box rect")
	assert_eq(rects[CommsBox.RECT_EDGE], Rect2(0, 0, 4, 124), "4 px accent edge")
	assert_eq(rects[CommsBox.RECT_PORTRAIT], Rect2(22, 18, 88, 88), "88 px portrait, centred vertically")
	assert_eq(rects[CommsBox.RECT_NAME], Rect2(124, 8, 758, 42))
	assert_eq(rects[CommsBox.RECT_TEXT], Rect2(124, 50, 758, 66), "758 px text block, y 50-116")


## Bottom centre: centred on the 1920 px playfield, its bottom 28 px above the
## screen's bottom.
func test_box_rect_math() -> void:
	var rect: Rect2 = CommsBox.box_rect(Playfield.SIZE, 900.0, 124.0, 28.0)
	assert_eq(rect, BOX_RECT)
	assert_eq(rect.get_center().x, Playfield.SIZE.x / 2.0, "centred horizontally")
	assert_eq(rect.end.y, Playfield.SIZE.y - 28.0, "bottom 28 px above the screen's bottom")
	assert_eq(CommsBox.box_rect(Vector2(1000, 500), 200.0, 50.0, 10.0), Rect2(400, 440, 200, 50))


func test_layout_follows_tuning() -> void:
	var tuning: Dictionary = (Config.tuning["ui"] as Dictionary)["comms_box"] as Dictionary
	tuning["w"] = 1000
	tuning["h"] = 140
	tuning["bottom_margin_px"] = 40
	var box: CommsBox = _make()
	assert_eq(_node(box, "Box").get_rect(), Rect2(460, 900, 1000, 140), "w, h and the bottom margin from tuning")


func test_layout_math_without_portrait() -> void:
	var rects: Dictionary = _layout(false)
	assert_eq(rects[CommsBox.RECT_BOX], BOX_RECT)
	assert_eq(rects[CommsBox.RECT_NAME], Rect2(22, 8, 860, 42))
	assert_eq(rects[CommsBox.RECT_TEXT], Rect2(22, 50, 860, 66), "860 px text block")


func test_hidden_at_start_and_mouse_transparent() -> void:
	var box: CommsBox = _make()
	assert_false(box.visible, "hidden at start")
	assert_eq(box.process_mode, Node.PROCESS_MODE_INHERIT, "pausable through its parent")
	assert_eq(box.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	for path: String in ["Box", "Box/Edge", "Box/Portrait", "Box/Portrait/Initial", "Box/Name", "Box/Text"]:
		assert_eq(_node(box, path).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s ignores the mouse" % path)
	assert_eq(box.theme.resource_path, THEME_PATH)
	assert_eq(_node(box, "Box").get_rect(), BOX_RECT, "box at the UX rect")
	assert_eq(box.find_children("*", "BaseButton", true, false).size(), 0, "no buttons")
	assert_null(box.get_node_or_null("Dim"), "no dim")


func test_text_label_settings() -> void:
	var box: CommsBox = _make()
	var text: Label = _label(box, "Box/Text")
	assert_eq(text.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	assert_true(text.clip_text)
	assert_eq(text.visible_characters_behavior, TextServer.VC_CHARS_AFTER_SHAPING)


func test_theme_items() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	assert_eq(theme.get_font_size(&"text", &"CommsBox"), 28)
	assert_eq(theme.get_font_size(&"name", &"CommsBox"), 30)
	assert_true(theme.has_constant(&"line_spacing", &"CommsBox"))
	var box_style: StyleBoxFlat = theme.get_stylebox(&"panel", &"CommsBox") as StyleBoxFlat
	var panel_style: StyleBoxFlat = theme.get_stylebox(&"panel", &"CommsPanel") as StyleBoxFlat
	assert_not_null(box_style)
	if box_style != null and panel_style != null:
		assert_lt(box_style.bg_color.a, panel_style.bg_color.a, "a more see-through fill than the story panel")
		_assert_color(box_style.border_color, panel_style.border_color, "the comms panel border")


func test_theme_applied_to_children() -> void:
	var box: CommsBox = _make()
	var theme: Theme = load(THEME_PATH) as Theme
	assert_eq(_label(box, "Box/Text").get_theme_font_size(&"font_size"), 28)
	assert_eq(_label(box, "Box/Name").get_theme_font_size(&"font_size"), 30)
	assert_eq(_label(box, "Box/Text").get_theme_constant(&"line_spacing"), theme.get_constant(&"line_spacing", &"CommsBox"), "line spacing applied")
	assert_true(theme.has_font(&"text", &"CommsBox"), "CommsBox text font")
	assert_eq(_label(box, "Box/Text").get_theme_font(&"font"), theme.get_font(&"text", &"CommsBox"), "text font applied")
	_assert_color(_label(box, "Box/Text").get_theme_color(&"font_color"), Color("#E8F4FF"), "text colour")
	var style: StyleBoxFlat = (box.get_node("Box") as Panel).get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_not_null(style)
	if style != null:
		_assert_color(style.bg_color, Color(10.0 / 255.0, 18.0 / 255.0, 34.0 / 255.0, 0.7), "semi-transparent surfaceAlt fill")
		_assert_color(style.border_color, Color("#2A3B5C"), "border")


# --- Lines ----------------------------------------------------------------------------

func test_portrait_speaker_line() -> void:
	var box: CommsBox = _make()
	_show_risen(box, &"tarek", "Ambush on the left.")
	assert_true(box.visible)
	assert_true(box.is_open())
	assert_eq(box.modulate.a, 1.0)
	var name_label: Label = _label(box, "Box/Name")
	assert_eq(name_label.text, "TAREK", "uppercase name")
	_assert_color(name_label.get_theme_color(&"font_color"), Color("#3DF2FF"), "name in the accent")
	_assert_color((box.get_node("Box/Edge") as ColorRect).color, Color("#3DF2FF"), "edge in the accent")
	var portrait: Panel = box.get_node("Box/Portrait") as Panel
	assert_true(portrait.visible, "portrait shown")
	var frame: StyleBoxFlat = portrait.get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_not_null(frame, "portrait frame override")
	if frame != null:
		_assert_color(frame.border_color, Color("#3DF2FF"), "frame in the accent")
	var image: TextureRect = box.get_node("Box/Portrait/Image") as TextureRect
	assert_true(image.visible, "the portrait image shows")
	assert_eq(image.texture.resource_path, "res://assets/portraits/portrait_tarek.png", "Tarek's portrait")
	assert_eq(image.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "sampled through its mipmaps")
	assert_false(_label(box, "Box/Portrait/Initial").visible, "the initial is hidden")
	assert_eq(Rect2(image.position, image.size), Rect2(1, 1, 86, 86), "inside the 1 px accent frame")
	assert_eq(image.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(_label(box, "Box/Text").get_rect(), Rect2(124, 50, 758, 66), "758 px text block")
	assert_eq(_label(box, "Box/Text").text, "Ambush on the left.")
	assert_eq(box.current_speaker(), &"tarek")


func test_no_portrait_speaker_line() -> void:
	var box: CommsBox = _make()
	box.show_line(&"isolde", "Portrait first.")
	box.show_line(&"vale", "No portrait.")
	assert_false(_node(box, "Box/Portrait").visible, "portrait hidden")
	assert_eq(_label(box, "Box/Name").text, "ARDEN")
	_assert_color((box.get_node("Box/Edge") as ColorRect).color, Color("#E8F4FF"), "vale edge")
	assert_eq(_label(box, "Box/Text").get_rect(), Rect2(22, 50, 860, 66), "860 px text block")
	box.show_line(&"ryn", "Back to a portrait.")
	assert_true(_node(box, "Box/Portrait").visible)
	assert_eq(_label(box, "Box/Text").get_rect().size.x, 758.0, "re-laid out for the portrait")


## Story 8.2: every portrait speaker has its own portrait (Isolde, Tarek, Ryn);
## Vale and the system keep the no-portrait variant.
func test_each_portrait_speaker_shows_their_portrait() -> void:
	var box: CommsBox = _make()
	for speaker: StringName in [&"isolde", &"tarek", &"ryn"]:
		box.show_line(speaker, "Portrait check.")
		var image: TextureRect = box.get_node("Box/Portrait/Image") as TextureRect
		assert_true(image.visible, "%s image" % speaker)
		assert_eq(image.texture, CommsPortraits.TEXTURES[speaker], "%s portrait" % speaker)
		assert_eq(image.texture.resource_path, "res://assets/portraits/portrait_%s.png" % speaker)
		assert_false(_label(box, "Box/Portrait/Initial").visible, "%s: no initial" % speaker)
	for speaker: StringName in [&"vale", &"system"]:
		box.show_line(speaker, "No portrait.")
		assert_false((box.get_node("Box/Portrait") as Control).visible, "%s: no-portrait variant" % speaker)


## A portrait speaker with no texture keeps the placeholder initial.
func test_portrait_speaker_without_a_texture_shows_the_initial() -> void:
	var box: CommsBox = _make()
	box.portraits.erase(&"tarek")
	box.show_line(&"tarek", "No picture yet.")
	assert_true((box.get_node("Box/Portrait") as Control).visible, "the frame shows")
	assert_false((box.get_node("Box/Portrait/Image") as Control).visible, "no image")
	var initial: Label = _label(box, "Box/Portrait/Initial")
	assert_true(initial.visible, "the initial shows")
	assert_eq(initial.text, "T", "placeholder initial")
	box.show_line(&"ryn", "Back to a picture.")
	assert_true((box.get_node("Box/Portrait/Image") as Control).visible, "Ryn's image")
	assert_false(_label(box, "Box/Portrait/Initial").visible, "no initial")


## Epic 7 playtest C: the box rises rise_px into place and fades in over
## comms.box_rise_in_s (no slide from the left).
func test_rises_into_place() -> void:
	var box: CommsBox = _make()
	box.show_line(&"isolde", "Rising in.")
	var panel: Control = _node(box, "Box")
	assert_eq(panel.position, Vector2(510, 952), "starts 24 px below its place")
	assert_eq(box.modulate.a, 0.0, "starts transparent")
	box._rise_tween.custom_step(0.1)
	assert_between(panel.position.y, 928.0, 952.0, "part way")
	assert_ne(panel.position.y, 952.0)
	assert_between(box.modulate.a, 0.01, 0.99, "fading in")
	assert_eq(panel.position.x, 510.0, "never moves sideways")
	box._rise_tween.custom_step(0.11)
	assert_eq(panel.position, Vector2(510, 928), "in place after 0.2 s")
	assert_eq(box.modulate.a, 1.0, "opaque after 0.2 s")
	assert_true(box.is_open())


## A dismiss during the rise snaps the box into place and fades from the
## alpha it had reached.
func test_dismiss_during_the_rise() -> void:
	var box: CommsBox = _make()
	box.show_line(&"isolde", "Short lived.")
	box._rise_tween.custom_step(0.1)
	var alpha: float = box.modulate.a
	box.dismiss()
	assert_false(box._rise_tween != null and box._rise_tween.is_valid(), "rise stopped")
	assert_eq(_node(box, "Box").position, Vector2(510, 928), "in place")
	assert_lte(box.modulate.a, alpha, "fades from where it was")
	box._fade_tween.custom_step(0.61)
	assert_false(box.visible, "hidden after the fade")


func test_typewriter_speed() -> void:
	var box: CommsBox = _make()
	box.show_line(&"isolde", "a".repeat(45))
	var text: Label = _label(box, "Box/Text")
	assert_eq(text.visible_characters, 0, "starts at 0")
	assert_true(box.is_typing())
	box._type_tween.custom_step(0.5)
	assert_between(text.visible_characters, 20, 25, "about half after 0.5 s")
	box._type_tween.custom_step(0.39)
	assert_true(box.is_typing(), "still typing at 0.89 s")
	box._type_tween.custom_step(0.12)
	assert_false(box.is_typing(), "done by 1.01 s")
	assert_eq(text.visible_characters, -1, "fully visible")


## Story 5.4: a cut-off line types only to cut_off_at characters over
## cut_off_at / comms.cutoff_chars_per_s (GDD decision #43) and stays there
## (never -1).
func test_cut_off_line_types_to_cut_off_at_and_stays() -> void:
	var box: CommsBox = _make()
	var line: String = "General, get behind me, I've got you cov—"
	var cut_s: float = 39.0 / Config.num("comms.cutoff_chars_per_s")
	assert_gt(cut_s, 39.0 / Config.num("comms.chars_per_s"), "slower than a normal line")
	box.show_line(&"tarek", line, 39)
	var text: Label = _label(box, "Box/Text")
	assert_eq(text.text, line, "the whole text is set")
	assert_eq(text.visible_characters, 0, "starts at 0")
	assert_true(box.is_typing())
	box._type_tween.custom_step(39.0 / Config.num("comms.chars_per_s"))
	assert_true(box.is_typing(), "not done at the normal speed")
	# 0.1 s before the end, more than one character is left at 16 chars/s.
	box._type_tween.custom_step(cut_s - 39.0 / Config.num("comms.chars_per_s") - 0.1)
	assert_true(box.is_typing(), "still typing just before 39 / cutoff_chars_per_s s")
	assert_lt(text.visible_characters, 39)
	box._type_tween.custom_step(0.11)
	assert_false(box.is_typing(), "done at 39 / cutoff_chars_per_s s")
	assert_eq(text.visible_characters, 39, "stops at cut_off_at, never -1")
	for i: int in 3:
		await get_tree().process_frame
	assert_eq(text.visible_characters, 39, "stays there")


func test_cut_off_stops_the_typewriter() -> void:
	var box: CommsBox = _make()
	box.show_line(&"tarek", "a".repeat(41), 39)
	box._type_tween.custom_step(0.2)
	box.cut_off(39)
	assert_false(box.is_typing(), "tween killed")
	assert_eq(_label(box, "Box/Text").text, "a".repeat(41), "no suffix: the text is kept")
	assert_eq(_label(box, "Box/Text").visible_characters, 39)
	assert_true(box.visible, "still shown")


## GDD decision #43: with a suffix the text becomes the first `chars`
## characters plus the suffix, all visible, and the typewriter stops.
func test_cut_off_with_a_suffix() -> void:
	var box: CommsBox = _make()
	box.show_line(&"tarek", "General, get behind me, I've got you cov—", 39)
	box._type_tween.custom_step(0.5)
	box.cut_off(39, "...")
	var text: Label = _label(box, "Box/Text")
	assert_false(box.is_typing(), "tween killed")
	assert_eq(text.text, "General, get behind me, I've got you co...")
	assert_eq(text.visible_characters, -1, "all of it visible")
	for i: int in 3:
		await get_tree().process_frame
	assert_eq(text.text, "General, get behind me, I've got you co...", "stays")
	assert_eq(text.visible_characters, -1, "stays visible")
	assert_true(box.visible, "still shown")


## A cut-off line with a non-positive cutoff_chars_per_s shows its cut_off_at
## characters at once.
func test_cut_off_line_with_no_typing_speed_is_instant() -> void:
	var box: CommsBox = _make()
	box.cutoff_chars_per_s = 0.0
	box.show_line(&"tarek", "General, get behind me, I've got you cov—", 39)
	assert_false(box.is_typing(), "no tween")
	assert_eq(_label(box, "Box/Text").visible_characters, 39)


func test_default_show_line_is_unchanged() -> void:
	var box: CommsBox = _make()
	box.show_line(&"isolde", "a".repeat(10), -1)
	box._type_tween.custom_step(1.0)
	assert_eq(_label(box, "Box/Text").visible_characters, -1, "-1 types the whole line")


func test_tweens_freeze_while_paused() -> void:
	var box: CommsBox = _make()
	box.show_line(&"isolde", "a".repeat(45))
	PauseArbiter.push(&"menu")
	var text: Label = _label(box, "Box/Text")
	var y: float = _node(box, "Box").position.y
	var alpha: float = box.modulate.a
	for i: int in 10:
		await get_tree().process_frame
	assert_eq(text.visible_characters, 0, "typewriter frozen")
	assert_eq(_node(box, "Box").position.y, y, "rise frozen")
	assert_eq(box.modulate.a, alpha, "fade-in frozen")
	PauseArbiter.pop(&"menu")
	for i: int in 2000:
		await get_tree().process_frame
		if text.visible_characters != 0:
			break
	assert_true(text.visible_characters > 0 or text.visible_characters == -1, "typing resumes")


func test_dismiss_fades_then_hides() -> void:
	var box: CommsBox = _make()
	_show_risen(box, &"isolde", "Going.")
	box.dismiss()
	assert_true(box.visible, "visible while fading")
	assert_false(box.is_open(), "not open while fading")
	box._fade_tween.custom_step(0.3)
	# Sine ease-out: at half the 0.6 s fade alpha is 1 - sin(pi/4) ~ 0.29, past linear's 0.5.
	assert_between(box.modulate.a, 0.2, 0.4, "eased past half at 0.3 s")
	box._fade_tween.custom_step(0.29)
	assert_gt(box.modulate.a, 0.0, "still settling just before the end")
	assert_true(box.visible, "visible until the fade ends")
	box._fade_tween.custom_step(0.02)
	assert_false(box.visible, "hidden after 0.6 s")
	assert_false(box.is_open())


func test_show_line_while_fading_reopens() -> void:
	var box: CommsBox = _make()
	_show_risen(box, &"isolde", "First.")
	box.dismiss()
	box._fade_tween.custom_step(0.1)
	box.show_line(&"tarek", "Second.")
	assert_true(box.is_open(), "open again")
	box._rise_tween.custom_step(1.0)
	assert_eq(box.modulate.a, 1.0, "full alpha after the rise")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(box.visible, "the old fade doesn't hide it")


func test_hide_now() -> void:
	var box: CommsBox = _make()
	box.show_line(&"isolde", "Typing a while.")
	box.hide_now()
	assert_false(box.visible, "hidden at once")
	assert_false(box.is_typing(), "typewriter stopped")
	assert_false(box.is_open())
	assert_eq(box.modulate.a, 1.0)


# --- Line fit (no clipped combat text) --------------------------------------------------

func test_fifty_char_lines_fit_two_lines_in_both_variants() -> void:
	var box: CommsBox = _make()
	var label: Label = _label(box, "Box/Text")
	var dev_lines: Array[String] = []
	for id: StringName in [&"dev_combat_check", &"dev_combat_isolde_2", &"dev_combat_vale"]:
		for line: Variant in Config.sequence(id).get("lines", []) as Array:
			dev_lines.append(str((line as Dictionary).get("text", "")))
	assert_eq(dev_lines.size(), 3, "dev combat lines found")
	for speaker: StringName in [&"isolde", &"vale"]:
		for text: String in LINES_50 + dev_lines:
			box.show_line(speaker, text)
			box.hide_now()
			box.show_line(speaker, text)
			await get_tree().process_frame
			await get_tree().process_frame
			var what: String = "%s, %d chars: %d lines, %d visible" % [speaker, text.length(), label.get_line_count(), label.get_visible_line_count()]
			assert_lte(label.get_line_count(), 2, "at most 2 lines: " + what)
			assert_lte(label.get_line_count(), label.get_visible_line_count(), "every line visible: " + what)
	for text: String in LINES_50:
		assert_eq(text.length(), 50, "fixture '%s' is 50 characters" % text)


## UX (decisions #24, #27): 28 px text at a 33 px line height (line 2 top -
## line 1 top = font height + line spacing, measured in-engine), so two full
## lines fill the 66 px text rect.
func test_text_line_pitch_is_33_px() -> void:
	var box: CommsBox = _make()
	var label: Label = _label(box, "Box/Text")
	var font: Font = label.get_theme_font(&"font")
	var font_px: int = label.get_theme_font_size(&"font_size")
	var pitch: float = font.get_height(font_px) + label.get_theme_constant(&"line_spacing")
	assert_eq(font_px, 28)
	assert_eq(pitch, Config.num("ui.comms_box.text_line_h_px"), "33 px line pitch")
	assert_eq(pitch, 33.0)
	assert_lte(pitch * 2.0, label.size.y, "two lines inside the text rect")
	# The widest 50-character line (all capitals) wraps to two lines in the
	# 758 px portrait variant (the 860 px no-portrait one may fit it on one).
	box.show_line(&"isolde", LINES_50[2])
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(label.get_line_count(), 2, "wraps to two lines")
	assert_eq(label.get_visible_line_count(), 2, "both lines fully visible")
	assert_eq(label.get_line_height(0), 33, "line 1 is 33 px")
	assert_eq(label.get_line_height(1), 33, "line 2 is 33 px")


## UX decision #24: the name's baseline sits above the text block, so its
## glyphs never crowd the first line of text (30 px name: baseline at y 41,
## text block at y 50).
func test_name_baseline_clears_the_text() -> void:
	var box: CommsBox = _make()
	box.show_line(&"isolde", LINES_50[0])
	var name_label: Label = _label(box, "Box/Name")
	var text: Label = _label(box, "Box/Text")
	var name_px: int = name_label.get_theme_font_size(&"font_size")
	assert_eq(name_px, 30)
	var baseline: float = name_label.position.y + name_label.get_theme_font(&"font").get_ascent(name_px)
	assert_lte(baseline + 6.0, text.position.y, "at least 6 px from the name baseline to the text block")


# --- See-through (Epic 7 playtest C) ---------------------------------------------------

func test_see_through_rect_is_the_box_grown_by_the_margin() -> void:
	var box: CommsBox = _make()
	assert_eq(box.see_through_rect(), BOX_RECT.grow(24.0))
	assert_eq(box.see_through(), 1.0, "opaque at start")


func test_player_under_the_box_makes_it_see_through_then_opaque_again() -> void:
	var box: CommsBox = _make()
	_show_risen(box, &"isolde", "Over the ship.")
	var player: Node2D = _add_player(Vector2(960, 990))
	assert_true(box.is_covering(), "the ship is under the box")
	box.step_see_through(0.1)
	assert_almost_eq(box.see_through(), 0.5, 0.0001, "eases down at 5 alpha/s")
	assert_almost_eq(_node(box, "Box").modulate.a, 0.5, 0.0001, "on the Box panel")
	assert_eq(box.modulate.a, 1.0, "the root alpha is left to the rise / fade")
	box.step_see_through(1.0)
	assert_almost_eq(box.see_through(), 0.3, 0.0001, "settles at see_through_alpha")
	player.position = Vector2(960, 500)
	assert_false(box.is_covering(), "the ship left")
	box.step_see_through(0.1)
	assert_almost_eq(box.see_through(), 0.8, 0.0001, "eases back up")
	box.step_see_through(1.0)
	assert_eq(box.see_through(), 1.0, "opaque again")
	assert_eq(_node(box, "Box").modulate.a, 1.0)


func test_the_margin_counts_as_under_the_box() -> void:
	var box: CommsBox = _make()
	_show_risen(box, &"isolde", "Margin.")
	var player: Node2D = _add_player(Vector2(960, 928 - 20))
	assert_true(box.is_covering(), "20 px above the box: inside the 24 px margin")
	player.position = Vector2(510 - 30, 990)
	assert_false(box.is_covering(), "30 px left of the box: outside the margin")


func test_enemy_shot_under_the_box_makes_it_see_through() -> void:
	var box: CommsBox = _make()
	_show_risen(box, &"isolde", "Incoming.")
	var shot: Area2D = _add_shot(Vector2(700, 1000), CollisionLayers.ENEMY_SHOTS)
	assert_true(box.is_covering(), "an enemy bullet under the box")
	box.step_see_through(1.0)
	assert_almost_eq(box.see_through(), 0.3, 0.0001)
	shot.position = Vector2(700, 300)
	assert_false(box.is_covering(), "the bullet moved on")
	box.step_see_through(1.0)
	assert_eq(box.see_through(), 1.0, "opaque again")


func test_player_shots_never_make_it_see_through() -> void:
	var box: CommsBox = _make()
	_show_risen(box, &"isolde", "Firing.")
	_add_shot(Vector2(700, 1000), CollisionLayers.PLAYER_SHOTS)
	assert_false(box.is_covering(), "a player shot is ignored")
	box.step_see_through(1.0)
	assert_eq(box.see_through(), 1.0, "stays opaque")


## An enemy-shot-layer area outside the projectiles group (not a projectile) is ignored.
func test_an_enemy_layer_area_outside_the_group_is_ignored() -> void:
	var box: CommsBox = _make()
	_show_risen(box, &"isolde", "Not a shot.")
	var shot: Area2D = _add_shot(Vector2(700, 1000), CollisionLayers.ENEMY_SHOTS)
	shot.remove_from_group(Groups.PROJECTILES)
	assert_false(box.is_covering())


func test_a_shot_already_in_the_tree_and_a_freed_shot() -> void:
	var shot: Area2D = _add_shot(Vector2(700, 1000), CollisionLayers.ENEMY_SHOTS)
	var box: CommsBox = _make()
	_show_risen(box, &"isolde", "Already there.")
	assert_true(box.is_covering(), "a shot added before the box counts")
	remove_child(shot)
	assert_false(box.is_covering(), "a shot that left the tree no longer counts")
	shot.free()
	assert_false(box.is_covering(), "nor once freed")


## The see-through (Box modulate) and the fade-out (root modulate) compose.
func test_see_through_composes_with_the_fade_out() -> void:
	var box: CommsBox = _make()
	_show_risen(box, &"isolde", "Fading.")
	_add_player(Vector2(960, 990))
	box.step_see_through(1.0)
	box.dismiss()
	box._fade_tween.custom_step(0.3)
	assert_almost_eq(_node(box, "Box").modulate.a, 0.3, 0.0001, "see-through kept during the fade")
	assert_between(box.modulate.a, 0.2, 0.4, "the root fades")
	box._fade_tween.custom_step(0.31)
	assert_false(box.visible, "hidden after the fade")
	assert_eq(box.see_through(), 1.0, "reset when hidden")
	assert_eq(_node(box, "Box").modulate.a, 1.0)


## Frames step the see-through only while the box is visible.
func test_frames_step_the_see_through_only_while_visible() -> void:
	var box: CommsBox = _make()
	_add_player(Vector2(960, 990))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(box.see_through(), 1.0, "hidden: no see-through")
	_show_risen(box, &"isolde", "Now visible.")
	for i: int in 200:
		await get_tree().process_frame
		if box.see_through() < 1.0:
			break
	assert_lt(box.see_through(), 1.0, "visible: frames ease it down")
	assert_eq(box.mouse_filter, Control.MOUSE_FILTER_IGNORE, "still mouse-transparent")
