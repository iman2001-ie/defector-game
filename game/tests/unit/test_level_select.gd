extends GutTest
## Level Select (Story 4.3, FR56): one card per campaign level
## (progression.level_count) with its LEVEL n number and uppercased JSON name,
## locked cards disabled at ui.level_select.locked_alpha with LOCKED shown, and
## BACK. An unlocked card -> SceneRouter.start_level(str(n)) (a recorder here;
## card 1 goes through the opening story, Story 5.5),
## BACK -> SceneRouter.goto_title(); a second press does nothing. With
## Config.load_error set no card is built, no Config getter runs and only BACK
## works. The save is a test file and is never written.

const LEVEL_SELECT_SCENE: PackedScene = preload("res://scenes/title/level_select.tscn")
const BAD_CONFIG: String = "res://data/tuning.json parse error at line 3: Expected '}'"
const TEST_SAVE: String = "user://test_level_select_save.cfg"
const LEVEL_NAMES: Array[String] = ["CARGO AMBUSH", "THE BLOCKADE", "SIEGE OF THE THRONE WORLD"]

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
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)


func after_each() -> void:
	Log.sink = Callable()
	Config.assert_on_missing = true
	Config.load_data()
	SceneRouter._story_id = &""
	SceneRouter._story_next_level = 0
	SceneRouter.change_scene = SceneRouter.default_change_scene()
	_delete_save()
	SaveManager.save_path = SaveManager.DEFAULT_SAVE_PATH
	GameState.highest_unlocked_level = 1
	GameState.all_levels_unlocked = false
	GameState.energy = 0
	GameState.current_level_id = ""
	GameState.is_retry = false
	Feedback.reset()
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _delete_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)


func _write_save(highest: int, energy: int) -> void:
	var file: ConfigFile = ConfigFile.new()
	file.set_value("progress", "save_version", 1)
	file.set_value("progress", "highest_unlocked_level", highest)
	file.set_value("progress", "energy", energy)
	assert_eq(file.save(TEST_SAVE), OK, "fixture save written")


func _record(path: String) -> Error:
	_calls.append(path)
	return OK


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _make() -> LevelSelectScreen:
	var screen: LevelSelectScreen = LEVEL_SELECT_SCENE.instantiate() as LevelSelectScreen
	Log.sink = _capture
	add_child_autofree(screen)
	return screen


## Makes the screen with a failed config: empty tuning, load_error set, asserts off.
func _make_bad() -> LevelSelectScreen:
	Config.assert_on_missing = false
	Config.tuning = {}
	Config.load_error = BAD_CONFIG
	return _make()


func _cards(screen: LevelSelectScreen) -> Control:
	return screen.get_node("Cards") as Control


func _card(screen: LevelSelectScreen, n: int) -> Button:
	return screen.get_node_or_null("Cards/Card%d" % n) as Button


func _back(screen: LevelSelectScreen) -> Button:
	return screen.get_node("Back") as Button


func _label(card: Button, node_name: String) -> Label:
	return card.get_node(node_name) as Label


## A card's rect in the screen's coordinates.
func _card_rect(screen: LevelSelectScreen, card: Button) -> Rect2:
	return Rect2(_cards(screen).position + card.position, card.size)


func _lines_starting(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.begins_with(prefix):
			out.append(line)
	return out


func _assert_color(actual: Color, expected: Color, what: String) -> void:
	assert_almost_eq(actual.r, expected.r, 0.002, what + " r")
	assert_almost_eq(actual.g, expected.g, 0.002, what + " g")
	assert_almost_eq(actual.b, expected.b, 0.002, what + " b")
	assert_almost_eq(actual.a, expected.a, 0.002, what + " a")


## The LevelSelect/Title button styles: normal has a `border` edge, hover and
## focus a `coalition` edge (the shared retry-button StyleBoxes).
func _assert_button_styles(button: Button) -> void:
	var expected: Dictionary = {&"normal": Color("#2A3B5C"), &"hover": Color("#22E6FF"), &"focus": Color("#22E6FF")}
	for style: StringName in expected:
		var box: StyleBoxFlat = button.get_theme_stylebox(style) as StyleBoxFlat
		assert_not_null(box, "%s %s StyleBoxFlat" % [button.name, style])
		if box != null:
			_assert_color(box.border_color, expected[style] as Color, "%s %s border" % [button.name, style])


func _assert_locked(screen: LevelSelectScreen, n: int, locked: bool) -> void:
	var card: Button = _card(screen, n)
	assert_not_null(card, "Card%d exists" % n)
	if card == null:
		return
	assert_eq(card.disabled, locked, "Card%d disabled == locked" % n)
	assert_eq(_label(card, "Locked").visible, locked, "Card%d LOCKED label" % n)
	assert_almost_eq(card.modulate.a, 0.4 if locked else 1.0, 0.001, "Card%d alpha" % n)


# --- Data and theme ---------------------------------------------------------------

func test_tuning() -> void:
	assert_eq(Config.num("ui.level_select.card_w"), 480.0)
	assert_eq(Config.num("ui.level_select.card_h"), 280.0)
	assert_eq(Config.num("ui.level_select.card_gap_px"), 48.0)
	assert_eq(Config.num("ui.level_select.cards_top_y"), 360.0)
	assert_eq(Config.num("ui.level_select.back_x"), 32.0)
	assert_eq(Config.num("ui.level_select.back_y"), 984.0)
	assert_eq(Config.num("ui.level_select.back_w"), 240.0)
	assert_eq(Config.num("ui.level_select.back_h"), 64.0)
	assert_almost_eq(Config.num("ui.level_select.locked_alpha"), 0.4, 0.0001)


func test_theme_items() -> void:
	var theme: Theme = load("res://ui/theme/defector_theme.tres") as Theme
	_assert_color(theme.get_color(&"text", &"LevelSelect"), Color("#E8F4FF"), "text")
	_assert_color(theme.get_color(&"muted", &"LevelSelect"), Color("#93A7C2"), "muted")
	_assert_color(theme.get_color(&"thumbnail", &"LevelSelect"), Color("#2B3348"), "thumbnail")
	assert_eq(theme.get_font_size(&"button", &"LevelSelect"), 28)
	assert_eq(theme.get_font_size(&"name", &"LevelSelect"), 28)
	assert_eq(theme.get_font_size(&"number", &"LevelSelect"), 20)
	for style: StringName in [&"button_normal", &"button_hover", &"button_focus"]:
		assert_true(theme.has_stylebox(style, &"LevelSelect"), "LevelSelect/styles/%s" % style)
		assert_eq(theme.get_stylebox(style, &"LevelSelect"), theme.get_stylebox(style, &"RetryPrompt"), "%s reuses the retry button style" % style)


func test_cards_rect() -> void:
	assert_eq(LevelSelectScreen.cards_rect(1920.0, Vector2(480, 280), 48.0, 360.0, 3), Rect2(192, 360, 1536, 280))
	assert_eq(LevelSelectScreen.cards_rect(1920.0, Vector2(480, 280), 48.0, 360.0, 1), Rect2(720, 360, 480, 280))


# --- Layout -----------------------------------------------------------------------

func test_healthy_layout() -> void:
	var screen: LevelSelectScreen = _make()
	await wait_process_frames(1)
	assert_eq(_cards(screen).get_child_count(), 3, "one card per level")
	assert_eq(_card_rect(screen, _card(screen, 1)), Rect2(192, 360, 480, 280), "Card1 rect")
	assert_eq(_card_rect(screen, _card(screen, 2)), Rect2(720, 360, 480, 280), "Card2 rect")
	assert_eq(_card_rect(screen, _card(screen, 3)), Rect2(1248, 360, 480, 280), "Card3 rect")
	var back: Button = _back(screen)
	assert_eq(Rect2(back.position, back.size), Rect2(32, 984, 240, 64), "BACK rect")
	assert_false(screen.is_config_error())


func test_layout_follows_ui_level_select_tuning() -> void:
	var section: Dictionary = (Config.tuning["ui"] as Dictionary)["level_select"]
	section["card_w"] = 400
	section["card_h"] = 200
	section["card_gap_px"] = 20
	section["cards_top_y"] = 300
	section["back_x"] = 40
	section["back_y"] = 900
	section["back_w"] = 200
	section["back_h"] = 50
	section["locked_alpha"] = 0.25
	var screen: LevelSelectScreen = _make()
	await wait_process_frames(1)
	# 3 × 400 + 2 × 20 = 1240 wide, so x starts at (1920 − 1240) / 2 = 340.
	assert_eq(_card_rect(screen, _card(screen, 1)), Rect2(340, 300, 400, 200), "Card1 rect")
	assert_eq(_card_rect(screen, _card(screen, 2)), Rect2(760, 300, 400, 200), "Card2 rect")
	assert_eq(_card_rect(screen, _card(screen, 3)), Rect2(1180, 300, 400, 200), "Card3 rect")
	var back: Button = _back(screen)
	assert_eq(Rect2(back.position, back.size), Rect2(40, 900, 200, 50), "BACK rect")
	assert_almost_eq(_card(screen, 2).modulate.a, 0.25, 0.001, "locked alpha from tuning")


func test_card_count_follows_progression_level_count() -> void:
	(Config.tuning["progression"] as Dictionary)["level_count"] = 2
	var screen: LevelSelectScreen = _make()
	assert_eq(_cards(screen).get_child_count(), 2, "two cards")
	assert_not_null(_card(screen, 2))
	assert_null(_card(screen, 3), "no Card3")
	assert_eq(_lines_starting("[INFO][scene] Level select ready (2 levels, 1 unlocked)").size(), 1)


func test_texts_and_font_sizes() -> void:
	var screen: LevelSelectScreen = _make()
	for n: int in range(1, 4):
		var card: Button = _card(screen, n)
		assert_eq(_label(card, "Number").text, "LEVEL %d" % n)
		assert_eq(_label(card, "Name").text, LEVEL_NAMES[n - 1])
		assert_eq(_label(card, "Locked").text, "LOCKED")
		assert_true(card.get_node("Thumbnail") is ColorRect, "Card%d thumbnail placeholder" % n)
		_assert_color((card.get_node("Thumbnail") as ColorRect).color, Color("#2B3348"), "thumbnail")
		assert_eq(card.focus_mode, Control.FOCUS_NONE, "Card%d takes no focus" % n)
		_assert_button_styles(card)
		assert_eq(_label(card, "Number").get_theme_font_size(&"font_size"), 20, "number font")
		assert_eq(_label(card, "Name").get_theme_font_size(&"font_size"), 28, "name font")
		_assert_color(_label(card, "Name").get_theme_color(&"font_color"), Color("#E8F4FF"), "name colour")
		_assert_color(_label(card, "Locked").get_theme_color(&"font_color"), Color("#93A7C2"), "LOCKED colour")
		for child: Node in card.get_children():
			assert_eq((child as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s/%s ignores the mouse" % [card.name, child.name])
			if child is Label:
				assert_true((child as Label).text == (child as Label).text.to_upper(), "%s uppercase" % child.name)
				assert_gte((child as Label).get_theme_font_size(&"font_size"), 20, "%s/%s ≥ 20 px" % [card.name, child.name])
	var back: Button = _back(screen)
	assert_eq(back.text, "BACK")
	assert_eq(back.focus_mode, Control.FOCUS_NONE)
	assert_eq(back.get_theme_font_size(&"font_size"), 28, "BACK font")
	_assert_button_styles(back)
	_assert_color(back.get_theme_color(&"font_color"), Color("#E8F4FF"), "BACK colour")


func test_mouse_mode_visible_and_ready_line() -> void:
	_make()
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE)
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE)
	assert_eq(_lines_starting("[INFO][scene] Level select ready (3 levels, 1 unlocked)").size(), 1, "one ready line")


# --- Unlock state -----------------------------------------------------------------

func test_fresh_save_only_level_1_unlocked() -> void:
	var screen: LevelSelectScreen = _make()
	_assert_locked(screen, 1, false)
	_assert_locked(screen, 2, true)
	_assert_locked(screen, 3, true)


func test_locked_card_disabled_style_is_the_normal_style() -> void:
	var screen: LevelSelectScreen = _make()
	var card: Button = _card(screen, 3)
	assert_true(card.disabled, "Card3 locked")
	var box: StyleBoxFlat = card.get_theme_stylebox(&"disabled") as StyleBoxFlat
	assert_not_null(box, "disabled StyleBoxFlat")
	if box != null:
		assert_eq(box, card.get_theme_stylebox(&"normal"), "disabled reuses the normal style")
		_assert_color(box.border_color, Color("#2A3B5C"), "disabled border")


func test_every_name_fits_its_row() -> void:
	var screen: LevelSelectScreen = _make()
	await wait_process_frames(1)
	for n: int in range(1, 4):
		var name_label: Label = _label(_card(screen, n), "Name")
		assert_lte(name_label.get_line_count(), name_label.get_visible_line_count(), "Card%d name '%s' fits its row" % [n, name_label.text])


func test_mid_progress_unlocks_levels_1_and_2() -> void:
	GameState.highest_unlocked_level = 2
	var screen: LevelSelectScreen = _make()
	_assert_locked(screen, 1, false)
	_assert_locked(screen, 2, false)
	_assert_locked(screen, 3, true)


func test_f7_flag_unlocks_every_card() -> void:
	GameState.all_levels_unlocked = true
	var screen: LevelSelectScreen = _make()
	for n: int in range(1, 4):
		_assert_locked(screen, n, false)
	assert_eq(_lines_starting("[INFO][scene] Level select ready (3 levels, 3 unlocked)").size(), 1)


# --- Presses ----------------------------------------------------------------------

func test_pick_unlocked_starts_the_level_with_the_restored_energy() -> void:
	GameState.highest_unlocked_level = 2
	GameState.energy = 40
	GameState.is_retry = true
	var screen: LevelSelectScreen = _make()
	_card(screen, 2).pressed.emit()
	_card(screen, 2).pressed.emit()
	_card(screen, 1).pressed.emit()
	_back(screen).pressed.emit()
	assert_eq(_calls, [SceneRouter.LEVEL_SCENE_PATH] as Array[String], "one change to the level")
	assert_eq(GameState.current_level_id, "2")
	assert_eq(GameState.energy, 40, "energy kept")
	assert_false(GameState.is_retry, "a fresh attempt")
	assert_false(FileAccess.file_exists(TEST_SAVE), "no save written")


func test_energy_restored_by_goto_title_reaches_the_level() -> void:
	_write_save(3, 55)
	GameState.energy = 90
	SceneRouter.goto_title()
	SceneRouter.goto_level_select()
	var screen: LevelSelectScreen = _make()
	_card(screen, 3).pressed.emit()
	assert_eq(_calls, [SceneRouter.TITLE_SCENE_PATH, SceneRouter.LEVEL_SELECT_SCENE_PATH, SceneRouter.LEVEL_SCENE_PATH] as Array[String])
	assert_eq(GameState.current_level_id, "3")
	assert_eq(GameState.energy, 55, "the saved energy")


func test_pick_locked_does_nothing() -> void:
	var screen: LevelSelectScreen = _make()
	_card(screen, 3).pressed.emit()
	_card(screen, 2).pressed.emit()
	assert_eq(_calls, [] as Array[String], "no scene change")
	assert_eq(GameState.current_level_id, "", "no level id")
	_card(screen, 1).pressed.emit()
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH] as Array[String], "a locked press doesn't block an unlocked one (level 1 opens with the story)")
	assert_eq(SceneRouter.story_sequence(), &"opening_main", "Story 5.5: the opening is pending")
	assert_eq(SceneRouter.story_next_level(), 1)


func test_back_goes_to_the_title() -> void:
	_write_save(2, 30)
	var screen: LevelSelectScreen = _make()
	_back(screen).pressed.emit()
	_back(screen).pressed.emit()
	_card(screen, 1).pressed.emit()
	assert_eq(_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String], "one change to the title")
	assert_eq(GameState.highest_unlocked_level, 2, "goto_title restored the save")
	assert_eq(GameState.energy, 30, "goto_title restored the save")
	var file: ConfigFile = ConfigFile.new()
	assert_eq(file.load(TEST_SAVE), OK, "save still there")
	assert_eq(file.get_value("progress", "highest_unlocked_level"), 2, "save untouched")
	assert_eq(file.get_value("progress", "energy"), 30, "save untouched")


func test_no_save_written_on_any_path() -> void:
	GameState.highest_unlocked_level = 3
	var screen: LevelSelectScreen = _make()
	_card(screen, 1).pressed.emit()
	assert_false(FileAccess.file_exists(TEST_SAVE), "a card press writes no save")
	var other: LevelSelectScreen = _make()
	_back(other).pressed.emit()
	assert_false(FileAccess.file_exists(TEST_SAVE), "BACK writes no save")


# --- Broken data ------------------------------------------------------------------

func test_broken_level_file_still_shows_the_number() -> void:
	# There is no level_4.json, so Config.level("4") logs a data error and returns {}.
	(Config.tuning["progression"] as Dictionary)["level_count"] = 4
	var screen: LevelSelectScreen = _make()
	var card: Button = _card(screen, 4)
	assert_not_null(card, "Card4 built")
	if card != null:
		assert_eq(_label(card, "Number").text, "LEVEL 4")
		assert_eq(_label(card, "Name").text, "", "empty name")
	var errors: Array[String] = _lines_starting("[ERROR][data]")
	assert_eq(errors.size(), 1, "the one data error Config logs")
	if errors.size() == 1:
		assert_true(errors[0].contains("level_4.json"), errors[0])
	assert_push_error("level_4.json")


func test_bad_config_builds_no_cards_and_back_works() -> void:
	var screen: LevelSelectScreen = _make_bad()
	assert_true(screen.is_config_error())
	assert_eq(_cards(screen).get_child_count(), 0, "no cards")
	var back: Button = _back(screen)
	assert_eq(Rect2(back.position, back.size), Rect2(32, 984, 240, 64), "authored BACK rect")
	assert_false(back.disabled, "BACK enabled")
	assert_eq(back.text, "BACK")
	assert_eq(_lines_starting("[ERROR][data]"), [] as Array[String], "no Config getter called")
	assert_eq(_lines_starting("[INFO][scene] Level select ready (0 levels, 0 unlocked)").size(), 1)
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE)
	back.pressed.emit()
	back.pressed.emit()
	assert_eq(_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String], "one change to the title")
