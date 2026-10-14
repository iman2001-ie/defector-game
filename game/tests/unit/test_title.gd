extends GutTest
## Title screen (Story 4.1, FR56): the DEFECTOR logo and PLAY · LEVEL SELECT ·
## QUIT (Story 4.3) at the ui.title layout; with Config.load_error set, the
## Error label replaces the buttons and no Config getter is called. PLAY ->
## SceneRouter.start_new("1"): always a new run at level 1 with 0 energy,
## whatever the unlock or the debug F7 flag (playtest 2026-10-13; a recorder
## here; level 1 goes through the opening story, Story 5.5), LEVEL
## SELECT -> SceneRouter.goto_level_select() (GameState untouched), QUIT ->
## the injected quit_game; a second press does nothing. The title declares the
## VISIBLE mouse mode and logs its ready time.

const TITLE_SCENE: PackedScene = preload("res://scenes/title/title.tscn")
const BAD_CONFIG: String = "res://data/tuning.json parse error at line 3: Expected '}'"
const TEST_SAVE: String = "user://test_title_save.cfg"

var _calls: Array[String] = []
var _quits: int = 0
var _lines: Array[String] = []


func before_each() -> void:
	_calls.clear()
	_quits = 0
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
	GameState.level_start_energy = 0
	GameState.current_level_id = ""
	GameState.is_retry = false
	Feedback.reset()
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _delete_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)


func _record(path: String) -> Error:
	_calls.append(path)
	return OK


func _record_quit() -> void:
	_quits += 1


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _make() -> TitleScreen:
	var title: TitleScreen = TITLE_SCENE.instantiate() as TitleScreen
	title.quit_game = _record_quit
	Log.sink = _capture
	add_child_autofree(title)
	return title


## Makes the title with a failed config: empty tuning, load_error set, asserts off.
func _make_bad() -> TitleScreen:
	Config.assert_on_missing = false
	Config.tuning = {}
	Config.load_error = BAD_CONFIG
	return _make()


func _logo(title: TitleScreen) -> TextureRect:
	return title.get_node("Logo") as TextureRect


func _buttons(title: TitleScreen) -> VBoxContainer:
	return title.get_node("Buttons") as VBoxContainer


func _play(title: TitleScreen) -> Button:
	return title.get_node("Buttons/Play") as Button


func _level_select(title: TitleScreen) -> Button:
	return title.get_node("Buttons/LevelSelect") as Button


func _quit(title: TitleScreen) -> Button:
	return title.get_node("Buttons/Quit") as Button


func _error(title: TitleScreen) -> Label:
	return title.get_node("Error") as Label


## A button's rect in the title's coordinates.
func _button_rect(title: TitleScreen, button: Button) -> Rect2:
	return Rect2(_buttons(title).position + button.position, button.size)


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


# --- Data and theme ---------------------------------------------------------------

func test_tuning() -> void:
	assert_eq(Config.num("ui.title.logo_y"), 300.0)
	assert_eq(Config.num("ui.title.logo_width_px"), 1100.0)
	assert_eq(Config.num("ui.title.button_w"), 400.0)
	assert_eq(Config.num("ui.title.button_h"), 72.0)
	assert_eq(Config.num("ui.title.button_gap_px"), 24.0)
	assert_eq(Config.num("ui.title.buttons_top_y"), 560.0)


func test_theme_items() -> void:
	var theme: Theme = load("res://ui/theme/defector_theme.tres") as Theme
	_assert_color(theme.get_color(&"error", &"Title"), Color("#FF1F4B"), "error")
	_assert_color(theme.get_color(&"text", &"Title"), Color("#E8F4FF"), "text")
	assert_false(theme.has_color(&"logo", &"Title"), "the wordmark PNG carries its own colour (pt7-h)")
	assert_eq(theme.get_font_size(&"button", &"Title"), 28)
	assert_eq(theme.get_font_size(&"error", &"Title"), 28)
	for style: StringName in [&"button_normal", &"button_hover", &"button_focus"]:
		assert_true(theme.has_stylebox(style, &"Title"), "Title/styles/%s" % style)
		assert_eq(theme.get_stylebox(style, &"Title"), theme.get_stylebox(style, &"RetryPrompt"), "%s reuses the retry button style" % style)


# --- Healthy config ---------------------------------------------------------------

func test_healthy_layout() -> void:
	var title: TitleScreen = _make()
	await wait_process_frames(1)
	var logo: TextureRect = _logo(title)
	assert_almost_eq(logo.position.y + logo.size.y / 2.0, 300.0, 0.5, "logo centred at y 300")
	assert_almost_eq(logo.size.x, 1100.0, 0.5, "logo 1100 px wide")
	assert_almost_eq(logo.size.y, 1100.0 * TitleScreen.logo_aspect(), 0.5, "as tall as the wordmark's aspect")
	assert_almost_eq(logo.position.x + logo.size.x / 2.0, 960.0, 0.5, "logo centred horizontally")
	assert_lt(logo.position.y + logo.size.y, 560.0, "above the buttons")
	var play: Rect2 = _button_rect(title, _play(title))
	var level_select: Rect2 = _button_rect(title, _level_select(title))
	var quit: Rect2 = _button_rect(title, _quit(title))
	assert_eq(play, Rect2(760, 560, 400, 72), "PLAY rect")
	assert_eq(level_select, Rect2(760, 656, 400, 72), "LEVEL SELECT rect: 24 px below PLAY")
	assert_eq(quit, Rect2(760, 752, 400, 72), "QUIT rect: 24 px below LEVEL SELECT")
	assert_eq(_buttons(title).get_child(1), _level_select(title), "LEVEL SELECT between PLAY and QUIT")
	assert_true(_buttons(title).visible, "buttons shown")
	assert_false(_error(title).visible, "error hidden")
	assert_false(title.is_config_error())


func test_layout_follows_ui_title_tuning() -> void:
	var ui_title: Dictionary = (Config.tuning["ui"] as Dictionary)["title"]
	ui_title["logo_y"] = 400
	ui_title["logo_width_px"] = 800
	ui_title["button_w"] = 300
	ui_title["button_h"] = 60
	ui_title["button_gap_px"] = 10
	ui_title["buttons_top_y"] = 600
	var title: TitleScreen = _make()
	await wait_process_frames(1)
	var logo: TextureRect = _logo(title)
	assert_almost_eq(logo.position.y + logo.size.y / 2.0, 400.0, 0.5, "logo centred at logo_y")
	assert_almost_eq(logo.size.x, 800.0, 0.5, "logo width is logo_width_px")
	assert_eq(_button_rect(title, _play(title)), Rect2(810, 600, 300, 60), "PLAY rect")
	assert_eq(_button_rect(title, _level_select(title)), Rect2(810, 670, 300, 60), "LEVEL SELECT rect")
	assert_eq(_button_rect(title, _quit(title)), Rect2(810, 740, 300, 60), "QUIT rect")


func test_texts_and_font_sizes() -> void:
	var title: TitleScreen = _make()
	_assert_wordmark(_logo(title))
	assert_eq(_play(title).text, "PLAY")
	assert_eq(_level_select(title).text, "LEVEL SELECT")
	assert_eq(_quit(title).text, "QUIT")
	for button: Button in [_play(title), _level_select(title), _quit(title)]:
		assert_eq(button.get_theme_font_size(&"font_size"), 28, "%s font" % button.name)
		assert_false(button.disabled, "%s enabled" % button.name)
		assert_eq(button.focus_mode, Control.FOCUS_NONE, "%s takes no focus (mouse-only)" % button.name)
		_assert_button_styles(button)
	assert_false(_play(title).has_focus(), "nothing focused")


## Story 8.2: the title has the space_1 backdrop as its first child, so it
## draws behind the logo and the buttons (also on a config error).
func test_space_backdrop_is_the_first_child() -> void:
	var title: TitleScreen = _make()
	var bg: LevelBackground = title.get_node_or_null("Background") as LevelBackground
	assert_not_null(bg, "a LevelBackground")
	if bg == null:
		return
	assert_eq(bg.get_index(), 0, "the first child")
	assert_eq(bg.background_id(), LevelBackground.MENU_BACKGROUND, "space_1")
	assert_eq(bg.tile_texture().resource_path, "res://assets/backgrounds/space_1.png")
	assert_false(bg.shows_throne_world())


func test_space_backdrop_shows_on_a_config_error() -> void:
	var title: TitleScreen = _make_bad()
	var bg: LevelBackground = title.get_node("Background") as LevelBackground
	assert_eq(bg.background_id(), "space_1", "the backdrop needs no Config")


func test_mouse_mode_visible_and_ready_line() -> void:
	_make()
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE)
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE)
	var ready: Array[String] = _lines_starting("[INFO][scene] Title ready ")
	assert_eq(ready.size(), 1, "one Title ready line")
	if ready.size() == 1:
		assert_true(ready[0].ends_with(" ms after launch"), ready[0])


## Story 5.5: level 1 starts through the opening story (the level loads when
## the story finishes; see test_story_scene.gd).
func test_play_starts_level_1_through_the_opening() -> void:
	var title: TitleScreen = _make()
	GameState.energy = 25
	GameState.is_retry = true
	_play(title).pressed.emit()
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH] as Array[String], "one change to the story scene")
	assert_eq(SceneRouter.story_sequence(), &"opening_main")
	assert_eq(SceneRouter.story_next_level(), 1)
	assert_false(GameState.is_retry)
	assert_eq(GameState.energy, 0, "a new run starts at 0")


## Playtest 2026-10-13: PLAY no longer continues at the highest unlocked level.
func test_play_starts_level_1_with_0_energy_even_when_further_unlocked() -> void:
	GameState.highest_unlocked_level = 3
	GameState.energy = 60
	var title: TitleScreen = _make()
	_play(title).pressed.emit()
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH] as Array[String], "the opening, not level 3")
	assert_eq(SceneRouter.story_next_level(), 1, "then level 1")
	assert_eq(GameState.energy, 0, "0 energy, not 60")
	assert_eq(GameState.highest_unlocked_level, 3, "the unlock is kept")
	assert_false(FileAccess.file_exists(TEST_SAVE), "PLAY writes no save")
	SceneRouter.finish_story()
	assert_eq(GameState.current_level_id, "1", "level 1 loads after the opening")
	assert_eq(GameState.energy, 0)
	assert_eq(GameState.level_start_energy, 0, "the attempt starts at 0")


func test_f7_flag_does_not_change_play() -> void:
	GameState.highest_unlocked_level = 2
	GameState.all_levels_unlocked = true
	var title: TitleScreen = _make()
	_play(title).pressed.emit()
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH] as Array[String], "still the opening")
	assert_eq(SceneRouter.story_next_level(), 1, "still level 1")


func test_second_press_is_ignored() -> void:
	var title: TitleScreen = _make()
	_play(title).pressed.emit()
	_play(title).pressed.emit()
	_quit(title).pressed.emit()
	assert_eq(_calls.size(), 1, "one scene change")
	assert_eq(_quits, 0, "the quit was ignored")


func test_level_select_goes_to_level_select() -> void:
	GameState.highest_unlocked_level = 2
	GameState.energy = 35
	GameState.current_level_id = "x"
	GameState.is_retry = true
	var title: TitleScreen = _make()
	_level_select(title).pressed.emit()
	_level_select(title).pressed.emit()
	_play(title).pressed.emit()
	_quit(title).pressed.emit()
	assert_eq(_calls, [SceneRouter.LEVEL_SELECT_SCENE_PATH] as Array[String], "one change to level select")
	assert_eq(_quits, 0, "the quit was ignored")
	assert_eq(GameState.highest_unlocked_level, 2, "unlock untouched")
	assert_eq(GameState.energy, 35, "energy untouched")
	assert_eq(GameState.current_level_id, "x", "level id untouched")
	assert_true(GameState.is_retry, "retry flag untouched")
	assert_false(FileAccess.file_exists(TEST_SAVE), "LEVEL SELECT writes no save")


func test_quit_calls_quit_game_once() -> void:
	var title: TitleScreen = _make()
	_quit(title).pressed.emit()
	_quit(title).pressed.emit()
	_play(title).pressed.emit()
	assert_eq(_quits, 1, "quit once")
	assert_eq(_calls, [] as Array[String], "no scene change")
	assert_eq(_lines_starting("[INFO][scene] Quit").size(), 1, "quit logged")


# --- Bad config -------------------------------------------------------------------

func test_bad_config_shows_the_error_instead_of_the_buttons() -> void:
	var title: TitleScreen = _make_bad()
	assert_true(title.is_config_error())
	assert_false(_buttons(title).visible, "buttons hidden")
	assert_true(_play(title).disabled, "PLAY disabled")
	assert_true(_level_select(title).disabled, "LEVEL SELECT disabled")
	assert_true(_quit(title).disabled, "QUIT disabled")
	var error: Label = _error(title)
	assert_true(error.visible, "error shown")
	assert_eq(error.text, "CONFIG ERROR\n" + BAD_CONFIG)
	assert_eq(error.position.y, 560.0, "in the place of the buttons")
	_assert_color(error.get_theme_color(&"font_color"), Color("#FF1F4B"), "error colour")
	assert_eq(error.get_theme_font_size(&"font_size"), 28, "error font")
	var logo: TextureRect = _logo(title)
	assert_almost_eq(logo.position.y + logo.size.y / 2.0, 300.0, 0.5, "authored logo centre")
	assert_almost_eq(logo.position.x + logo.size.x / 2.0, 960.0, 0.5, "authored logo centred horizontally")
	_assert_wordmark(logo)
	assert_eq(_lines_starting("[ERROR][data]"), [] as Array[String], "no Config getter called")
	assert_eq(_lines_starting("[INFO][scene] Title ready ").size(), 1, "ready line still logged")
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE)


func test_bad_config_buttons_start_nothing() -> void:
	var title: TitleScreen = _make_bad()
	_play(title).pressed.emit()
	_level_select(title).pressed.emit()
	_quit(title).pressed.emit()
	assert_eq(_calls, [] as Array[String], "no scene change")
	assert_eq(_quits, 0, "no quit")
	assert_eq(GameState.current_level_id, "", "no level id")


## The Logo shows the DEFECTOR wordmark (playtest pt7-h), aspect kept, mipmapped.
func _assert_wordmark(logo: TextureRect) -> void:
	assert_eq(logo.texture, TitleScreen.LOGO_TEXTURE, "the wordmark texture")
	assert_eq(logo.texture.resource_path, "res://assets/logo/defector_logo.png")
	assert_eq(logo.expand_mode, TextureRect.EXPAND_IGNORE_SIZE)
	assert_eq(logo.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "aspect kept")
	assert_eq(logo.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "sampled through its mipmaps")
	assert_true(logo.texture.get_image().has_mipmaps(), "imported with mipmaps")


func test_logo_rect_keeps_the_wordmark_aspect() -> void:
	var aspect: float = TitleScreen.logo_aspect()
	assert_almost_eq(aspect, 284.0 / 1536.0, 0.0001, "the 1536 x 284 wordmark")
	assert_eq(TitleScreen.logo_rect(1920.0, 300.0, 1000.0), Rect2(Vector2(460.0, 300.0 - 500.0 * aspect), Vector2(1000.0, 1000.0 * aspect)))
	assert_eq(TitleScreen.logo_rect(1920.0, 300.0, 0.0).size.x, 1.0, "at least 1 px wide")
