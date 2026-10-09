extends GutTest
## CommsPanel (Story 5.1): the story panel view. Layout from ui.comms_panel
## (UX: panel 410,300 1100x300; text block 812 px with a portrait, 1036 px
## without), theme items, mouse transparency, the speaker name / accent /
## portrait, and the typewriter (visible_characters tween, runs while paused).

const PANEL_SCENE: PackedScene = preload("res://systems/comms/comms_panel.tscn")
const THEME_PATH: String = "res://ui/theme/defector_theme.tres"
const ACCENTS: Dictionary = {
	&"isolde": "#FF6AE3",
	&"tarek": "#3DF2FF",
	&"ryn": "#7CFFB2",
	&"vale": "#E8F4FF",
	&"system": "#93A7C2",
}


func after_each() -> void:
	Log.sink = Callable()
	Config.load_data()
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _make() -> CommsPanel:
	var panel: CommsPanel = PANEL_SCENE.instantiate() as CommsPanel
	add_child_autofree(panel)
	return panel


func _label(panel: CommsPanel, path: String) -> Label:
	return panel.get_node(path) as Label


func _assert_color(actual: Color, expected: Color, what: String) -> void:
	assert_almost_eq(actual.r, expected.r, 0.002, what + " r")
	assert_almost_eq(actual.g, expected.g, 0.002, what + " g")
	assert_almost_eq(actual.b, expected.b, 0.002, what + " b")
	assert_almost_eq(actual.a, expected.a, 0.002, what + " a")


func _layout(with_portrait: bool) -> Dictionary:
	return CommsPanel.layout(410.0, 300.0, 1100.0, 300.0, 32.0, 200.0, 24.0, 36.0, 8.0, 24.0, with_portrait)


# --- Data, layout and theme ---------------------------------------------------------

func test_tuning() -> void:
	var expected: Dictionary = {
		"x": 410.0, "y": 300.0, "w": 1100.0, "h": 300.0, "padding_px": 32.0, "portrait_px": 200.0,
		"portrait_gap_px": 24.0, "name_h_px": 36.0, "name_gap_px": 8.0, "cue_h_px": 24.0,
	}
	for key: String in expected:
		assert_eq(Config.num("ui.comms_panel.%s" % key), expected[key], "ui.comms_panel.%s" % key)
	assert_eq(Config.int_("comms.story_line_max_chars"), 200)
	assert_eq(Config.num("comms.chars_per_s"), 45.0)


func test_layout_math_with_portrait() -> void:
	var rects: Dictionary = _layout(true)
	assert_eq(rects[CommsPanel.RECT_PANEL], Rect2(410, 300, 1100, 300), "UX panel rect")
	assert_eq(rects[CommsPanel.RECT_PORTRAIT], Rect2(32, 32, 200, 200), "200 px portrait inside the padding")
	assert_eq((rects[CommsPanel.RECT_TEXT] as Rect2).size.x, 812.0, "812 px text block")
	assert_eq((rects[CommsPanel.RECT_TEXT] as Rect2).position.x, 256.0, "after portrait + gap")
	assert_eq(rects[CommsPanel.RECT_NAME], Rect2(256, 32, 812, 36))
	assert_eq(rects[CommsPanel.RECT_TEXT], Rect2(256, 76, 812, 168))
	assert_eq(rects[CommsPanel.RECT_CUE], Rect2(256, 244, 812, 24), "cue at the bottom padding")


func test_layout_math_without_portrait() -> void:
	var rects: Dictionary = _layout(false)
	assert_eq(rects[CommsPanel.RECT_PANEL], Rect2(410, 300, 1100, 300))
	assert_eq(rects[CommsPanel.RECT_TEXT], Rect2(32, 76, 1036, 168), "1036 px text block")
	assert_eq(rects[CommsPanel.RECT_NAME], Rect2(32, 32, 1036, 36))
	assert_eq(rects[CommsPanel.RECT_CUE], Rect2(32, 244, 1036, 24))


func test_hidden_at_start_and_mouse_transparent() -> void:
	var panel: CommsPanel = _make()
	assert_false(panel.visible, "hidden at start")
	assert_eq(panel.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	for path: String in ["Dim", "Panel", "Panel/Portrait", "Panel/Portrait/Initial", "Panel/Name", "Panel/Text", "Panel/Cue"]:
		assert_eq((panel.get_node(path) as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s ignores the mouse" % path)
	assert_eq(panel.theme.resource_path, THEME_PATH)
	var dim: ColorRect = panel.get_node("Dim") as ColorRect
	assert_eq(dim.get_rect(), Rect2(Vector2.ZERO, Playfield.SIZE), "full-rect dim")
	assert_eq((panel.get_node("Panel") as Control).get_rect(), Rect2(410, 300, 1100, 300), "panel at the UX rect")
	var buttons: Array[Node] = panel.find_children("*", "BaseButton", true, false)
	assert_eq(buttons.size(), 0, "no buttons")


func test_text_label_settings() -> void:
	var panel: CommsPanel = _make()
	var text: Label = _label(panel, "Panel/Text")
	assert_eq(text.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	assert_true(text.clip_text)
	assert_eq(text.visible_characters_behavior, TextServer.VC_CHARS_AFTER_SHAPING)
	var cue: Label = _label(panel, "Panel/Cue")
	assert_eq(cue.text, "click to continue ▸")
	assert_eq(cue.text, cue.text.to_lower(), "cue stays lowercase")
	assert_eq(cue.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT)


func test_theme_items() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	_assert_color(theme.get_color(&"dim", &"CommsPanel"), Color(0, 0, 0, 0.6), "dim")
	_assert_color(theme.get_color(&"text", &"CommsPanel"), Color("#E8F4FF"), "text")
	_assert_color(theme.get_color(&"muted", &"CommsPanel"), Color("#93A7C2"), "muted")
	for speaker: StringName in ACCENTS:
		_assert_color(theme.get_color(speaker, &"CommsPanel"), Color(ACCENTS[speaker] as String), "%s accent" % speaker)
	assert_eq(theme.get_font_size(&"text", &"CommsPanel"), 30)
	assert_eq(theme.get_font_size(&"name", &"CommsPanel"), 28)
	assert_eq(theme.get_font_size(&"cue", &"CommsPanel"), 20)
	var box: StyleBoxFlat = theme.get_stylebox(&"panel", &"CommsPanel") as StyleBoxFlat
	assert_not_null(box, "panel StyleBoxFlat")
	if box != null:
		_assert_color(box.bg_color, Color(10.0 / 255.0, 18.0 / 255.0, 34.0 / 255.0, 0.85), "surfaceAlt fill")
		_assert_color(box.border_color, Color("#2A3B5C"), "border")
		assert_eq(box.border_width_left, 1)
		assert_eq(box.corner_radius_top_left, 4)


func test_theme_applied_to_children() -> void:
	var panel: CommsPanel = _make()
	_assert_color((panel.get_node("Dim") as ColorRect).color, Color(0, 0, 0, 0.6), "dim colour")
	assert_eq(_label(panel, "Panel/Text").get_theme_font_size(&"font_size"), 30)
	assert_eq(_label(panel, "Panel/Name").get_theme_font_size(&"font_size"), 28)
	assert_eq(_label(panel, "Panel/Cue").get_theme_font_size(&"font_size"), 20)
	_assert_color(_label(panel, "Panel/Text").get_theme_color(&"font_color"), Color("#E8F4FF"), "text colour")
	_assert_color(_label(panel, "Panel/Cue").get_theme_color(&"font_color"), Color("#93A7C2"), "cue in muted")
	var box: StyleBoxFlat = (panel.get_node("Panel") as Panel).get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_not_null(box)
	if box != null:
		_assert_color(box.border_color, Color("#2A3B5C"), "panel border")


# --- Lines ----------------------------------------------------------------------------

func test_open_and_close() -> void:
	var panel: CommsPanel = _make()
	panel.open()
	assert_true(panel.visible)
	assert_true((panel.get_node("Dim") as Control).is_visible_in_tree(), "dim shown")
	assert_true((panel.get_node("Panel") as Control).is_visible_in_tree(), "panel shown")
	panel.show_line(&"tarek", "Typing.")
	assert_true(panel.is_typing())
	panel.close()
	assert_false(panel.visible)
	assert_false(panel.is_typing(), "close kills the tween")


## Story 5.5: the opening story scene turns the dim off; the default keeps it.
func test_dim_on_by_default() -> void:
	var panel: CommsPanel = _make()
	assert_true(panel.dim, "dim on by default")
	panel.open()
	assert_true((panel.get_node("Dim") as Control).is_visible_in_tree(), "dim shown")


func test_dim_off_keeps_the_dim_hidden() -> void:
	var panel: CommsPanel = PANEL_SCENE.instantiate() as CommsPanel
	panel.dim = false
	add_child_autofree(panel)
	panel.open()
	assert_true(panel.visible, "panel open")
	assert_false((panel.get_node("Dim") as Control).visible, "dim hidden")
	assert_true((panel.get_node("Panel") as Control).is_visible_in_tree(), "panel shown")
	panel.close()
	panel.open()
	assert_false((panel.get_node("Dim") as Control).visible, "still hidden on a second open")


func test_portrait_speaker_line() -> void:
	var panel: CommsPanel = _make()
	panel.open()
	panel.show_line(&"tarek", "Comms check, General.")
	var name_label: Label = _label(panel, "Panel/Name")
	assert_eq(name_label.text, "TAREK", "uppercase name from comms.speakers")
	_assert_color(name_label.get_theme_color(&"font_color"), Color("#3DF2FF"), "name in the accent")
	var portrait: Panel = panel.get_node("Panel/Portrait") as Panel
	assert_true(portrait.visible, "portrait shown")
	var frame: StyleBoxFlat = portrait.get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_not_null(frame, "portrait frame override")
	if frame != null:
		_assert_color(frame.border_color, Color("#3DF2FF"), "frame in the accent")
	var initial: Label = _label(panel, "Panel/Portrait/Initial")
	assert_eq(initial.text, "T", "placeholder initial")
	_assert_color(initial.get_theme_color(&"font_color"), Color("#3DF2FF"), "initial in the accent")
	assert_eq(_label(panel, "Panel/Text").get_rect(), Rect2(256, 76, 812, 168), "812 px text block")
	assert_eq(_label(panel, "Panel/Text").text, "Comms check, General.")
	assert_eq(panel.current_speaker(), &"tarek")


func test_no_portrait_speaker_line() -> void:
	var panel: CommsPanel = _make()
	panel.open()
	panel.show_line(&"isolde", "Portrait first.")
	panel.show_line(&"vale", "No portrait.")
	assert_false((panel.get_node("Panel/Portrait") as Control).visible, "portrait hidden")
	assert_eq(_label(panel, "Panel/Name").text, "VALE")
	_assert_color(_label(panel, "Panel/Name").get_theme_color(&"font_color"), Color("#E8F4FF"), "vale accent")
	assert_eq(_label(panel, "Panel/Text").get_rect(), Rect2(32, 76, 1036, 168), "1036 px text block")
	assert_eq(_label(panel, "Panel/Name").get_rect().size.x, 1036.0)
	panel.show_line(&"ryn", "Back to a portrait.")
	assert_true((panel.get_node("Panel/Portrait") as Control).visible)
	assert_eq(_label(panel, "Panel/Text").get_rect().size.x, 812.0, "re-laid out for the portrait")


func test_typewriter_speed() -> void:
	var panel: CommsPanel = _make()
	panel.open()
	var line: String = "a".repeat(45)
	panel.show_line(&"tarek", line)
	var text: Label = _label(panel, "Panel/Text")
	assert_eq(text.visible_characters, 0, "starts at 0")
	assert_true(panel.is_typing())
	panel._tween.custom_step(0.5)
	assert_between(text.visible_characters, 20, 25, "about half after 0.5 s")
	panel._tween.custom_step(0.39)
	assert_true(panel.is_typing(), "still typing at 0.89 s")
	assert_lt(text.visible_characters, 45)
	panel._tween.custom_step(0.12)
	assert_false(panel.is_typing(), "done by 1.01 s")
	assert_eq(text.visible_characters, -1, "fully visible")


func test_complete_line() -> void:
	var panel: CommsPanel = _make()
	panel.open()
	panel.show_line(&"tarek", "A line that takes a while to type out.")
	panel.complete_line()
	assert_false(panel.is_typing())
	assert_eq(_label(panel, "Panel/Text").visible_characters, -1)


func test_typewriter_runs_while_paused() -> void:
	var panel: CommsPanel = _make()
	panel.open()
	PauseArbiter.push(&"story")
	panel.show_line(&"tarek", "a".repeat(45))
	var text: Label = _label(panel, "Panel/Text")
	for i: int in 2000:
		await get_tree().process_frame
		if text.visible_characters != 0:
			break
	assert_true(text.visible_characters > 0 or text.visible_characters == -1, "typing advanced under the pause")


# --- Line fit (no clipped story text) ---------------------------------------------------

## 200 characters of ordinary prose (the story line limit).
const PROSE_200: String = "We hold the line at the relay until our convoy clears the gates, General. After that, each pilot falls back to the carrier and we regroup for the jump. Nobody stays behind. Not this time. Never again."


func test_line_spacing_constant_applied() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	assert_true(theme.has_constant(&"line_spacing", &"CommsPanel"))
	assert_eq(theme.get_constant(&"line_spacing", &"CommsPanel"), 0)
	var panel: CommsPanel = _make()
	assert_eq(_label(panel, "Panel/Text").get_theme_constant(&"line_spacing"), 0, "applied to the Text label")


func test_long_lines_fit_both_variants() -> void:
	assert_eq(PROSE_200.length(), 200, "fixture is 200 characters")
	var dev_long: String = ""
	for line: Variant in Config.sequence(&"dev_comms_check").get("lines", []) as Array:
		var text: String = str((line as Dictionary).get("text", ""))
		if text.length() > dev_long.length():
			dev_long = text
	assert_gt(dev_long.length(), 180, "dev.json long line found")
	var panel: CommsPanel = _make()
	panel.open()
	var label: Label = _label(panel, "Panel/Text")
	for speaker: StringName in [&"tarek", &"vale"]:
		for text: String in [dev_long, PROSE_200]:
			panel.show_line(speaker, text)
			panel.complete_line()
			await get_tree().process_frame
			await get_tree().process_frame
			assert_lte(label.get_line_count(), label.get_visible_line_count(),
				"%s, %d chars: %d lines, %d visible" % [speaker, text.length(), label.get_line_count(), label.get_visible_line_count()])
