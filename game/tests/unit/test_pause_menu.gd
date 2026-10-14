extends GutTest
## PauseMenu (Story 4.4): Esc (the `pause` action) toggles it. Opening pushes the
## `menu` reason (blocked by `death` / `final_choice`, allowed over `story`);
## RESUME or Esc pops only `menu`. RESTART LEVEL -> SceneRouter.restart_level()
## (back to the energy the attempt started with, GameState.level_start_energy;
## playtest 2026-10-13), QUIT TO TITLE -> SceneRouter.goto_title() (energy 0);
## the scene change is a recorder and the save is a test file.

const MENU_SCENE: PackedScene = preload("res://ui/menus/pause_menu.tscn")
const THEME_PATH: String = "res://ui/theme/defector_theme.tres"
const TEST_SAVE: String = "user://test_pause_menu_save.cfg"
const TEXT_COLOR: Color = Color(0.909804, 0.956863, 1, 1)

var _calls: Array[String] = []
var _lines: Array[String] = []


func before_each() -> void:
	_calls.clear()
	_lines.clear()
	SaveManager.save_path = TEST_SAVE
	_delete_save()
	GameState.highest_unlocked_level = 1
	GameState.all_levels_unlocked = false
	SceneRouter.change_scene = _record
	Log.sink = _capture


func after_each() -> void:
	Log.sink = Callable()
	SceneRouter.change_scene = SceneRouter.default_change_scene()
	_delete_save()
	SaveManager.save_path = SaveManager.DEFAULT_SAVE_PATH
	GameState.highest_unlocked_level = 1
	GameState.all_levels_unlocked = false
	GameState.energy = 0
	GameState.level_start_energy = 0
	GameState.current_level_id = ""
	GameState.is_retry = false
	Config.load_data()
	Feedback.reset()
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _delete_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)


func _record(path: String) -> Error:
	_calls.append(path)
	return OK


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _make() -> PauseMenu:
	var menu: PauseMenu = MENU_SCENE.instantiate() as PauseMenu
	add_child_autofree(menu)
	return menu


func _esc(menu: PauseMenu) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = &"pause"
	event.pressed = true
	menu._unhandled_input(event)


func _button(menu: PauseMenu, name: String) -> Button:
	return menu.get_node(name) as Button


func _count_lines(text: String) -> int:
	var n: int = 0
	for line: String in _lines:
		if line == text:
			n += 1
	return n


func _assert_color(actual: Color, expected: Color, what: String) -> void:
	assert_almost_eq(actual.r, expected.r, 0.002, what + " r")
	assert_almost_eq(actual.g, expected.g, 0.002, what + " g")
	assert_almost_eq(actual.b, expected.b, 0.002, what + " b")
	assert_almost_eq(actual.a, expected.a, 0.002, what + " a")


# --- Setup, layout and theme --------------------------------------------------------

func test_tuning() -> void:
	assert_eq(Config.num("ui.pause_menu.panel_w"), 520.0)
	assert_eq(Config.num("ui.pause_menu.panel_padding_px"), 40.0)
	assert_eq(Config.num("ui.pause_menu.heading_px"), 48.0)
	assert_eq(Config.num("ui.pause_menu.heading_gap_px"), 40.0)
	assert_eq(Config.num("ui.pause_menu.button_w"), 400.0)
	assert_eq(Config.num("ui.pause_menu.button_h"), 72.0)
	assert_eq(Config.num("ui.pause_menu.button_gap_px"), 24.0)


func test_hidden_at_start() -> void:
	var menu: PauseMenu = _make()
	assert_eq(menu.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_false(menu.visible)
	assert_false(menu.is_shown())
	assert_eq(menu.mouse_filter, Control.MOUSE_FILTER_IGNORE, "no mouse capture while hidden")
	assert_false(PauseArbiter.is_paused())
	assert_not_null(menu.theme)
	if menu.theme != null:
		assert_eq(menu.theme.resource_path, THEME_PATH)


func test_layout() -> void:
	var menu: PauseMenu = _make()
	var panel: Panel = menu.get_node("Panel") as Panel
	assert_eq(panel.get_rect(), Rect2(700, 324, 520, 432), "panel rect")
	var heading: Label = menu.get_node("Panel/Heading") as Label
	assert_eq(heading.global_position.y, 364.0, "heading top")
	assert_eq(heading.position.x, 0.0)
	assert_eq(heading.size.x, 520.0, "full panel width")
	assert_eq(heading.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER)
	assert_eq(_button(menu, "Resume").get_rect(), Rect2(760, 452, 400, 72), "RESUME rect")
	assert_eq(_button(menu, "Restart").get_rect(), Rect2(760, 548, 400, 72), "RESTART rect")
	assert_eq(_button(menu, "Quit").get_rect(), Rect2(760, 644, 400, 72), "QUIT rect")
	var dim: ColorRect = menu.get_node("Dim") as ColorRect
	assert_eq(dim.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(dim.get_rect(), Rect2(Vector2.ZERO, Playfield.SIZE), "full-rect dim")


func test_layout_follows_tuning() -> void:
	var tuning: Dictionary = (Config.tuning["ui"] as Dictionary)["pause_menu"] as Dictionary
	tuning["panel_w"] = 600
	tuning["panel_padding_px"] = 20
	tuning["heading_px"] = 60
	tuning["heading_gap_px"] = 10
	tuning["button_w"] = 300
	tuning["button_h"] = 50
	tuning["button_gap_px"] = 10
	var menu: PauseMenu = _make()
	# height = 20 + 60 + 10 + 3 * 50 + 2 * 10 + 20 = 280
	assert_eq((menu.get_node("Panel") as Panel).get_rect(), Rect2(660, 400, 600, 280))
	assert_eq((menu.get_node("Panel/Heading") as Label).global_position.y, 420.0)
	assert_eq(_button(menu, "Resume").get_rect(), Rect2(810, 490, 300, 50))
	assert_eq(_button(menu, "Restart").get_rect(), Rect2(810, 550, 300, 50))
	assert_eq(_button(menu, "Quit").get_rect(), Rect2(810, 610, 300, 50))


func test_rect_math() -> void:
	var panel: Rect2 = PauseMenu.panel_rect(Vector2(1920, 1080), 520.0, 40.0, 48.0, 40.0, Vector2(400, 72), 24.0, 3)
	assert_eq(panel, Rect2(700, 324, 520, 432))
	var rects: Array[Rect2] = PauseMenu.button_rects(panel, 40.0, 48.0, 40.0, Vector2(400, 72), 24.0, 3)
	assert_eq(rects, [Rect2(760, 452, 400, 72), Rect2(760, 548, 400, 72), Rect2(760, 644, 400, 72)] as Array[Rect2])


func test_texts_are_uppercase() -> void:
	var menu: PauseMenu = _make()
	assert_eq((menu.get_node("Panel/Heading") as Label).text, "PAUSED")
	assert_eq(_button(menu, "Resume").text, "RESUME")
	assert_eq(_button(menu, "Restart").text, "RESTART LEVEL")
	assert_eq(_button(menu, "Quit").text, "QUIT TO TITLE")
	for name: String in ["Resume", "Restart", "Quit"]:
		var text: String = _button(menu, name).text
		assert_eq(text, text.to_upper(), "%s uppercase" % name)
		assert_eq(_button(menu, name).focus_mode, Control.FOCUS_NONE, "%s mouse-only" % name)


func test_theme_items() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	_assert_color(theme.get_color(&"dim", &"PauseMenu"), Color(0, 0, 0, 0.6), "dim token")
	_assert_color(theme.get_color(&"text", &"PauseMenu"), Color("#E8F4FF"), "text token")
	assert_eq(theme.get_font_size(&"heading", &"PauseMenu"), 48)
	assert_eq(theme.get_font_size(&"button", &"PauseMenu"), 28)
	var panel_box: StyleBoxFlat = theme.get_stylebox(&"panel", &"PauseMenu") as StyleBoxFlat
	assert_not_null(panel_box, "panel StyleBoxFlat")
	if panel_box != null:
		_assert_color(panel_box.bg_color, Color(10.0 / 255.0, 18.0 / 255.0, 34.0 / 255.0, 0.85), "surfaceAlt fill")
		_assert_color(panel_box.border_color, Color("#2A3B5C"), "border")
		assert_eq(panel_box.border_width_top, 1)
		assert_eq(panel_box.corner_radius_top_left, 4)
	for style: StringName in [&"button_normal", &"button_hover", &"button_focus"]:
		assert_eq(theme.get_stylebox(style, &"PauseMenu"), theme.get_stylebox(style, &"RetryPrompt"), "%s reuses the retry box" % style)


func test_theme_applied_to_children() -> void:
	var menu: PauseMenu = _make()
	_assert_color((menu.get_node("Dim") as ColorRect).color, Color(0, 0, 0, 0.6), "dim colour")
	var panel: Panel = menu.get_node("Panel") as Panel
	var panel_box: StyleBoxFlat = panel.get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_not_null(panel_box, "panel style applied")
	if panel_box != null:
		_assert_color(panel_box.border_color, Color("#2A3B5C"), "panel border")
	var heading: Label = menu.get_node("Panel/Heading") as Label
	assert_eq(heading.get_theme_font_size(&"font_size"), 48)
	_assert_color(heading.get_theme_color(&"font_color"), TEXT_COLOR, "heading colour")
	for name: String in ["Resume", "Restart", "Quit"]:
		var button: Button = _button(menu, name)
		var expected: Dictionary = {&"normal": Color("#2A3B5C"), &"hover": Color("#22E6FF"), &"focus": Color("#22E6FF")}
		for style: StringName in expected:
			var box: StyleBoxFlat = button.get_theme_stylebox(style) as StyleBoxFlat
			assert_not_null(box, "%s %s StyleBoxFlat" % [name, style])
			if box != null:
				_assert_color(box.border_color, expected[style] as Color, "%s %s border" % [name, style])
		var font_px: int = button.get_theme_font_size(&"font_size")
		assert_eq(font_px, 28, "%s font size" % name)
		assert_gte(font_px, 20, "%s text never below 20px" % name)
		_assert_color(button.get_theme_color(&"font_color"), TEXT_COLOR, "%s text colour" % name)
	assert_gte(heading.get_theme_font_size(&"font_size"), 20)


# --- Opening and closing ----------------------------------------------------------

func test_esc_opens() -> void:
	var menu: PauseMenu = _make()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	_esc(menu)
	assert_true(menu.is_shown())
	assert_true(menu.visible)
	assert_eq(PauseArbiter.reasons(), [&"menu"] as Array[StringName])
	assert_true(get_tree().paused)
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "cursor visible")
	assert_eq(menu.mouse_filter, Control.MOUSE_FILTER_STOP, "captures the mouse while shown")
	assert_eq(_count_lines("[INFO][scene] Pause menu opened"), 1, "one INFO line")


func test_esc_again_resumes() -> void:
	var menu: PauseMenu = _make()
	_esc(menu)
	watch_signals(PauseArbiter)
	_esc(menu)
	assert_false(menu.is_shown())
	assert_false(menu.visible)
	assert_eq(PauseArbiter.reasons(), [] as Array[StringName])
	assert_false(get_tree().paused)
	assert_signal_emit_count(PauseArbiter, "resumed", 1)
	assert_eq(menu.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(_count_lines("[INFO][scene] Pause menu closed"), 1)


func test_resume_button() -> void:
	var menu: PauseMenu = _make()
	_esc(menu)
	watch_signals(PauseArbiter)
	_button(menu, "Resume").pressed.emit()
	assert_false(menu.is_shown())
	assert_false(menu.visible)
	assert_false(get_tree().paused)
	assert_signal_emit_count(PauseArbiter, "resumed", 1)
	assert_eq(menu.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(_count_lines("[INFO][scene] Pause menu closed"), 1)


func test_resume_under_story_keeps_the_story_pause() -> void:
	var menu: PauseMenu = _make()
	PauseArbiter.push(&"story")
	_esc(menu)
	assert_true(menu.is_shown(), "a story pause doesn't block the menu")
	var reasons: Array[StringName] = PauseArbiter.reasons()
	assert_true(reasons.has(&"story") and reasons.has(&"menu"))
	watch_signals(PauseArbiter)
	_button(menu, "Resume").pressed.emit()
	assert_false(menu.is_shown())
	assert_false(menu.visible)
	assert_eq(PauseArbiter.reasons(), [&"story"] as Array[StringName], "only menu popped")
	assert_true(get_tree().paused, "still paused by the story")
	assert_signal_not_emitted(PauseArbiter, "resumed")


func test_death_blocks_the_menu() -> void:
	var menu: PauseMenu = _make()
	PauseArbiter.push(RetryPrompt.PAUSE_REASON)
	_esc(menu)
	assert_false(menu.is_shown())
	assert_false(menu.visible)
	assert_eq(PauseArbiter.reasons(), [RetryPrompt.PAUSE_REASON] as Array[StringName])
	assert_eq(_count_lines("[INFO][scene] Pause menu opened"), 0)


func test_final_choice_blocks_the_menu() -> void:
	var menu: PauseMenu = _make()
	PauseArbiter.push(&"final_choice")
	_esc(menu)
	assert_false(menu.is_shown())
	assert_false(menu.visible)
	assert_eq(PauseArbiter.reasons(), [&"final_choice"] as Array[StringName])


func test_echo_is_ignored() -> void:
	var menu: PauseMenu = _make()
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	key.echo = true
	menu._unhandled_input(key)
	assert_false(menu.is_shown(), "echo doesn't open")
	assert_false(PauseArbiter.is_paused())
	key.echo = false
	menu._unhandled_input(key)
	assert_true(menu.is_shown(), "the same key without echo opens")
	key.echo = true
	menu._unhandled_input(key)
	assert_true(menu.is_shown(), "echo doesn't close")
	assert_eq(PauseArbiter.reasons(), [&"menu"] as Array[StringName])


func test_other_actions_are_ignored() -> void:
	var menu: PauseMenu = _make()
	var event: InputEventAction = InputEventAction.new()
	event.action = &"fire"
	event.pressed = true
	menu._unhandled_input(event)
	assert_false(menu.is_shown())
	var release: InputEventAction = InputEventAction.new()
	release.action = &"pause"
	release.pressed = false
	menu._unhandled_input(release)
	assert_false(menu.is_shown(), "a release doesn't open")


func test_resume_press_while_hidden_does_nothing() -> void:
	var menu: PauseMenu = _make()
	watch_signals(PauseArbiter)
	_button(menu, "Resume").pressed.emit()
	_button(menu, "Restart").pressed.emit()
	_button(menu, "Quit").pressed.emit()
	assert_false(menu.is_shown())
	assert_false(PauseArbiter.is_paused())
	assert_signal_not_emitted(PauseArbiter, "resumed")
	assert_eq(_calls, [] as Array[String])
	assert_eq(_lines.size(), 0, "nothing logged")


# --- Leaving ----------------------------------------------------------------------

func test_restart_reloads_the_level_with_the_start_energy() -> void:
	var menu: PauseMenu = _make()
	GameState.level_start_energy = 40
	GameState.energy = 80
	GameState.current_level_id = "2"
	_esc(menu)
	_button(menu, "Restart").pressed.emit()
	assert_eq(_calls, [SceneRouter.LEVEL_SCENE_PATH] as Array[String], "level.tscn once")
	assert_eq(GameState.energy, 40, "back to the 40 the attempt started with, not 80")
	assert_eq(GameState.level_start_energy, 40, "the new attempt starts with it too")
	assert_has(_lines, "[INFO][scene] Restart: reloading level '2'", "the router's restart, not a death retry")
	assert_true(GameState.is_retry)
	assert_eq(GameState.current_level_id, "2")
	assert_false(FileAccess.file_exists(TEST_SAVE), "no save written")
	assert_true(menu.visible, "stays visible until the scene changes")
	_button(menu, "Restart").pressed.emit()
	_button(menu, "Quit").pressed.emit()
	_button(menu, "Resume").pressed.emit()
	_esc(menu)
	assert_eq(_calls.size(), 1, "later presses and Esc ignored")
	assert_true(GameState.is_retry, "the quit was ignored")
	assert_false(PauseArbiter.is_paused(), "Esc didn't reopen")


func test_quit_goes_to_the_title() -> void:
	var menu: PauseMenu = _make()
	GameState.energy = 40
	GameState.current_level_id = "2"
	_esc(menu)
	_button(menu, "Quit").pressed.emit()
	assert_eq(_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String], "title.tscn once")
	assert_eq(GameState.current_level_id, "", "goto_title ran")
	assert_eq(GameState.energy, 0, "goto_title zeroes the energy")
	assert_false(FileAccess.file_exists(TEST_SAVE), "no save written")
	assert_true(menu.visible, "stays visible until the scene changes")
	_button(menu, "Quit").pressed.emit()
	_button(menu, "Restart").pressed.emit()
	_esc(menu)
	assert_eq(_calls.size(), 1, "later presses and Esc ignored")
	assert_false(GameState.is_retry)
	assert_false(PauseArbiter.is_paused())


# --- One dim (Story 5.1) -------------------------------------------------------------

func test_dim_shown_without_a_story() -> void:
	var menu: PauseMenu = _make()
	_esc(menu)
	assert_true((menu.get_node("Dim") as Control).visible, "own dim over gameplay")


func test_dim_hidden_over_a_story_pause() -> void:
	var menu: PauseMenu = _make()
	PauseArbiter.push(&"story")
	_esc(menu)
	assert_true(menu.is_shown())
	assert_false((menu.get_node("Dim") as Control).visible, "the comms dim is already up: one dim")
	_esc(menu)
	PauseArbiter.pop(&"story")
	_esc(menu)
	assert_true((menu.get_node("Dim") as Control).visible, "dim back once the story is over")


# --- Recent comms (Epic 7 playtest C) -----------------------------------------------

func _comms_block(menu: PauseMenu) -> PanelContainer:
	return menu.get_node("RecentComms") as PanelContainer


func _line(speaker: StringName, text: String, mode: StringName = &"combat") -> void:
	Events.comms_line_shown.emit(speaker, text, mode)


func test_recent_comms_tuning_and_theme() -> void:
	assert_eq(Config.int_("ui.pause_menu.recent_comms"), 3)
	var theme: Theme = load(THEME_PATH) as Theme
	assert_gte(theme.get_font_size(&"comms", &"PauseMenu"), 22, "readable: at least 22 px")


func test_recent_comms_hidden_when_empty() -> void:
	var menu: PauseMenu = _make()
	menu.open()
	assert_false(_comms_block(menu).visible, "no combat lines yet: no block")
	assert_eq(menu.recent_comms(), [] as Array[String])


func test_recent_comms_lists_combat_lines_newest_first() -> void:
	var menu: PauseMenu = _make()
	_line(&"tarek", "Ambush on the left.")
	_line(&"isolde", "Still flying, General?")
	menu.open()
	assert_true(_comms_block(menu).visible, "block shown")
	assert_eq((menu.get_node("RecentComms/Margin/List/Heading") as Label).text, "RECENT COMMS")
	assert_eq(menu.recent_comms(), ["ISOLDE: Still flying, General?", "TAREK: Ambush on the left."] as Array[String], "newest first")


func test_recent_comms_keeps_only_the_last_n() -> void:
	var menu: PauseMenu = _make()
	for i: int in 5:
		_line(&"ryn", "Line %d." % i)
	assert_eq(menu.recent_comms(), ["RYN: Line 4.", "RYN: Line 3.", "RYN: Line 2."] as Array[String], "capped at recent_comms")


func test_recent_comms_ignores_story_lines() -> void:
	var menu: PauseMenu = _make()
	_line(&"tarek", "A story line.", &"story")
	assert_false(_comms_block(menu).visible, "story lines aren't listed")
	_line(&"tarek", "A combat line.")
	_line(&"vale", "Another story line.", &"story")
	assert_eq(menu.recent_comms(), ["TAREK: A combat line."] as Array[String])


func test_recent_comms_lines_use_the_speaker_accent_at_a_readable_size() -> void:
	var menu: PauseMenu = _make()
	_line(&"isolde", "Pink.")
	_line(&"tarek", "Cyan.")
	var labels: Array[Label] = []
	for child: Node in menu.get_node("RecentComms/Margin/List").get_children():
		if child is Label and child.name != &"Heading" and (child as Label).visible:
			labels.append(child as Label)
	assert_eq(labels.size(), 2)
	_assert_color(labels[0].get_theme_color(&"font_color"), Color("#3DF2FF"), "tarek accent")
	_assert_color(labels[1].get_theme_color(&"font_color"), Color("#FF6AE3"), "isolde accent")
	for label: Label in labels:
		assert_gte(label.get_theme_font_size(&"font_size"), 22, "at least 22 px")
		assert_eq(label.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	# Story 8.2: dialogue keeps the engine font (a base-less FontVariation);
	# the heading keeps the Theme default (Kenney Future).
	var theme: Theme = load(THEME_PATH) as Theme
	var row_font: FontVariation = labels[0].get_theme_font(&"font") as FontVariation
	assert_not_null(row_font, "the row font is a FontVariation")
	if row_font != null:
		assert_eq(row_font, theme.get_font(&"comms", &"PauseMenu"), "PauseMenu/fonts/comms")
		assert_null(row_font.base_font, "no base: the engine font")
	assert_eq((menu.get_node("RecentComms/Margin/List/Heading") as Label).get_theme_font(&"font"), theme.default_font, "the heading in Kenney Future")


func test_recent_comms_block_sits_below_the_panel() -> void:
	var menu: PauseMenu = _make()
	_line(&"tarek", "Placed.")
	var block: Rect2 = _comms_block(menu).get_rect()
	var panel: Rect2 = (menu.get_node("Panel") as Panel).get_rect()
	assert_eq(block.position.y, panel.end.y + Config.num("ui.pause_menu.comms_gap_px"), "comms_gap_px below the panel")
	assert_eq(block.size.x, Config.num("ui.pause_menu.comms_w"))
	assert_eq(block.get_center().x, Playfield.SIZE.x / 2.0, "centred")
	assert_lte(block.end.y, Playfield.SIZE.y, "on screen")
	assert_eq(_comms_block(menu).mouse_filter, Control.MOUSE_FILTER_IGNORE)


## Through the real CommsChannel: a combat sequence's line reaches the menu.
func test_a_channel_combat_line_reaches_the_menu() -> void:
	var menu: PauseMenu = _make()
	var box: CommsBox = (load("res://systems/comms/comms_box.tscn") as PackedScene).instantiate() as CommsBox
	add_child_autofree(box)
	var channel: CommsChannel = CommsChannel.new()
	channel.box = box
	channel.panel = (load("res://systems/comms/comms_panel.tscn") as PackedScene).instantiate() as CommsPanel
	add_child_autofree(channel.panel)
	add_child_autofree(channel)
	Config.load_data(Config.DEFAULT_TUNING_PATH, Config.DEFAULT_FLAGS_PATH, "res://tests/fixtures/dialogue/channel/")
	Events.comms_sequence_requested.emit(&"combat_a")
	assert_eq(menu.recent_comms(), ["ISOLDE: Combat chatter."] as Array[String])
