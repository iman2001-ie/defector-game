extends GutTest
## CommsBox (Story 5.2): the combat interruption box view. Layout from
## ui.comms_box (UX: box 32,24 560x96; text block 448 px with a portrait at
## x 100, 532 px without at x 16, y 34-90), theme items, mouse transparency,
## the speaker name / accent / edge / portrait, the slide-in, the typewriter
## (pausable), the fade-out, hide_now, and a 50-character line fitting two
## lines in both variants.

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
	return CommsBox.layout(32.0, 24.0, 560.0, 96.0, 4.0, 6.0, 72.0, 12.0, 28.0, 28.0, 2, with_portrait)


# --- Data, layout and theme ---------------------------------------------------------

func test_tuning() -> void:
	var expected: Dictionary = {
		"x": 32.0, "y": 24.0, "w": 560.0, "h": 96.0, "edge_px": 4.0, "padding_px": 6.0, "portrait_px": 72.0,
		"portrait_gap_px": 12.0, "name_h_px": 28.0, "text_line_h_px": 28.0, "text_lines": 2.0,
	}
	for key: String in expected:
		assert_eq(Config.num("ui.comms_box.%s" % key), expected[key], "ui.comms_box.%s" % key)
	assert_eq(Config.int_("comms.combat_line_max_chars"), 50)
	assert_eq(Config.num("comms.box_slide_in_s"), 0.15)
	assert_eq(Config.num("comms.box_fade_out_s"), 0.2)


func test_layout_math_with_portrait() -> void:
	var rects: Dictionary = _layout(true)
	assert_eq(rects[CommsBox.RECT_BOX], Rect2(32, 24, 560, 96), "UX box rect")
	assert_eq(rects[CommsBox.RECT_EDGE], Rect2(0, 0, 4, 96), "4 px accent edge")
	assert_eq(rects[CommsBox.RECT_PORTRAIT], Rect2(16, 12, 72, 72), "72 px portrait, centred vertically")
	assert_eq(rects[CommsBox.RECT_NAME], Rect2(100, 6, 448, 28))
	assert_eq(rects[CommsBox.RECT_TEXT], Rect2(100, 34, 448, 56), "448 px text block, y 34-90")
	var box: Rect2 = rects[CommsBox.RECT_BOX] as Rect2
	assert_eq(box.end.x, 592.0, "ends at x 592 (88 px before the wave bar)")


func test_layout_math_without_portrait() -> void:
	var rects: Dictionary = _layout(false)
	assert_eq(rects[CommsBox.RECT_BOX], Rect2(32, 24, 560, 96))
	assert_eq(rects[CommsBox.RECT_NAME], Rect2(16, 6, 532, 28))
	assert_eq(rects[CommsBox.RECT_TEXT], Rect2(16, 34, 532, 56), "532 px text block")


func test_hidden_at_start_and_mouse_transparent() -> void:
	var box: CommsBox = _make()
	assert_false(box.visible, "hidden at start")
	assert_eq(box.process_mode, Node.PROCESS_MODE_INHERIT, "pausable through its parent")
	assert_eq(box.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	for path: String in ["Box", "Box/Edge", "Box/Portrait", "Box/Portrait/Initial", "Box/Name", "Box/Text"]:
		assert_eq(_node(box, path).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s ignores the mouse" % path)
	assert_eq(box.theme.resource_path, THEME_PATH)
	assert_eq(_node(box, "Box").get_rect(), Rect2(32, 24, 560, 96), "box at the UX rect")
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
	assert_eq(theme.get_font_size(&"text", &"CommsBox"), 24)
	assert_eq(theme.get_font_size(&"name", &"CommsBox"), 28)
	assert_true(theme.has_constant(&"line_spacing", &"CommsBox"))
	assert_eq(theme.get_stylebox(&"panel", &"CommsBox"), theme.get_stylebox(&"panel", &"CommsPanel"), "reuses the comms panel box")


func test_theme_applied_to_children() -> void:
	var box: CommsBox = _make()
	var theme: Theme = load(THEME_PATH) as Theme
	assert_eq(_label(box, "Box/Text").get_theme_font_size(&"font_size"), 24)
	assert_eq(_label(box, "Box/Name").get_theme_font_size(&"font_size"), 28)
	assert_eq(_label(box, "Box/Text").get_theme_constant(&"line_spacing"), theme.get_constant(&"line_spacing", &"CommsBox"), "line spacing applied")
	assert_true(theme.has_font(&"text", &"CommsBox"), "CommsBox text font")
	assert_eq(_label(box, "Box/Text").get_theme_font(&"font"), theme.get_font(&"text", &"CommsBox"), "text font applied")
	_assert_color(_label(box, "Box/Text").get_theme_color(&"font_color"), Color("#E8F4FF"), "text colour")
	var style: StyleBoxFlat = (box.get_node("Box") as Panel).get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_not_null(style)
	if style != null:
		_assert_color(style.bg_color, Color(10.0 / 255.0, 18.0 / 255.0, 34.0 / 255.0, 0.85), "surfaceAlt fill")
		_assert_color(style.border_color, Color("#2A3B5C"), "border")


# --- Lines ----------------------------------------------------------------------------

func test_portrait_speaker_line() -> void:
	var box: CommsBox = _make()
	box.show_line(&"tarek", "Ambush on the left.")
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
	assert_eq(_label(box, "Box/Portrait/Initial").text, "T", "placeholder initial")
	assert_eq(_label(box, "Box/Text").get_rect(), Rect2(100, 34, 448, 56), "448 px text block")
	assert_eq(_label(box, "Box/Text").text, "Ambush on the left.")
	assert_eq(box.current_speaker(), &"tarek")


func test_no_portrait_speaker_line() -> void:
	var box: CommsBox = _make()
	box.show_line(&"isolde", "Portrait first.")
	box.show_line(&"vale", "No portrait.")
	assert_false(_node(box, "Box/Portrait").visible, "portrait hidden")
	assert_eq(_label(box, "Box/Name").text, "VALE")
	_assert_color((box.get_node("Box/Edge") as ColorRect).color, Color("#E8F4FF"), "vale edge")
	assert_eq(_label(box, "Box/Text").get_rect(), Rect2(16, 34, 532, 56), "532 px text block")
	box.show_line(&"ryn", "Back to a portrait.")
	assert_true(_node(box, "Box/Portrait").visible)
	assert_eq(_label(box, "Box/Text").get_rect().size.x, 448.0, "re-laid out for the portrait")


func test_slides_in_from_the_left() -> void:
	var box: CommsBox = _make()
	box.show_line(&"isolde", "Sliding in.")
	var panel: Control = _node(box, "Box")
	assert_eq(panel.position.x, -560.0, "starts off screen at x = -w")
	box._slide_tween.custom_step(0.075)
	assert_between(panel.position.x, -560.0, 32.0, "part way")
	assert_ne(panel.position.x, -560.0)
	box._slide_tween.custom_step(0.1)
	assert_eq(panel.position.x, 32.0, "in place after 0.15 s")
	assert_eq(panel.position.y, 24.0)


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
## cut_off_at / chars_per_s and stays there (never -1).
func test_cut_off_line_types_to_cut_off_at_and_stays() -> void:
	var box: CommsBox = _make()
	var line: String = "General, get behind me, I've got you cov—"
	box.show_line(&"tarek", line, 39)
	var text: Label = _label(box, "Box/Text")
	assert_eq(text.text, line, "the whole text is set")
	assert_eq(text.visible_characters, 0, "starts at 0")
	assert_true(box.is_typing())
	box._type_tween.custom_step(39.0 / 45.0 - 0.02)
	assert_true(box.is_typing(), "still typing just before 39 / 45 s")
	assert_lt(text.visible_characters, 39)
	box._type_tween.custom_step(0.03)
	assert_false(box.is_typing(), "done at 39 / 45 s")
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
	assert_eq(_label(box, "Box/Text").visible_characters, 39)
	assert_true(box.visible, "still shown")


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
	var x: float = _node(box, "Box").position.x
	for i: int in 10:
		await get_tree().process_frame
	assert_eq(text.visible_characters, 0, "typewriter frozen")
	assert_eq(_node(box, "Box").position.x, x, "slide frozen")
	PauseArbiter.pop(&"menu")
	for i: int in 2000:
		await get_tree().process_frame
		if text.visible_characters != 0:
			break
	assert_true(text.visible_characters > 0 or text.visible_characters == -1, "typing resumes")


func test_dismiss_fades_then_hides() -> void:
	var box: CommsBox = _make()
	box.show_line(&"isolde", "Going.")
	box.dismiss()
	assert_true(box.visible, "visible while fading")
	assert_false(box.is_open(), "not open while fading")
	box._fade_tween.custom_step(0.1)
	assert_between(box.modulate.a, 0.3, 0.7, "half faded at 0.1 s")
	box._fade_tween.custom_step(0.11)
	assert_false(box.visible, "hidden after 0.2 s")
	assert_false(box.is_open())


func test_show_line_while_fading_reopens() -> void:
	var box: CommsBox = _make()
	box.show_line(&"isolde", "First.")
	box.dismiss()
	box._fade_tween.custom_step(0.1)
	box.show_line(&"tarek", "Second.")
	assert_true(box.is_open(), "open again")
	assert_eq(box.modulate.a, 1.0, "full alpha")
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
	for id: StringName in [&"dev_combat_check", &"dev_combat_vale"]:
		for line: Variant in Config.sequence(id).get("lines", []) as Array:
			dev_lines.append(str((line as Dictionary).get("text", "")))
	assert_eq(dev_lines.size(), 2, "dev combat lines found")
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


## UX: 24 px text at a 28 px line height (line 2 top - line 1 top = font
## height + line spacing), so two full lines fill the 56 px text rect.
func test_text_line_pitch_is_28_px() -> void:
	var box: CommsBox = _make()
	var label: Label = _label(box, "Box/Text")
	var font: Font = label.get_theme_font(&"font")
	var font_px: int = label.get_theme_font_size(&"font_size")
	var pitch: float = font.get_height(font_px) + label.get_theme_constant(&"line_spacing")
	assert_eq(font_px, 24)
	assert_eq(pitch, Config.num("ui.comms_box.text_line_h_px"), "28 px line pitch")
	assert_eq(pitch, 28.0)
	assert_lte(pitch * 2.0, label.size.y, "two lines inside the text rect")
	for speaker: StringName in [&"isolde", &"vale"]:
		box.show_line(speaker, LINES_50[0])
		await get_tree().process_frame
		await get_tree().process_frame
		assert_eq(label.get_line_count(), 2, "%s: wraps to two lines" % speaker)
		assert_eq(label.get_visible_line_count(), 2, "%s: both lines fully visible" % speaker)
		assert_eq(label.get_line_height(0), 28, "%s: line 1 is 28 px" % speaker)
		assert_eq(label.get_line_height(1), 28, "%s: line 2 is 28 px" % speaker)
