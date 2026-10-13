extends GutTest
## End screen (Story 7.7, FR60; UX "End screen"): DEFECTOR, one closing line,
## "Thanks for playing" and BACK TO TITLE over the throne-world backdrop (the
## reused LevelBackground, drawn first), at the ui.end_screen layout; with
## Config.load_error set, the authored layout is kept and no Config getter is
## called. BACK TO TITLE -> SceneRouter.goto_title() once (a recorder here),
## even on a double press. The screen declares the VISIBLE mouse mode and logs
## one ready line.

const END_SCENE: PackedScene = preload("res://scenes/end/end_screen.tscn")
const BAD_CONFIG: String = "res://data/tuning.json parse error at line 3: Expected '}'"
const TEST_SAVE: String = "user://test_end_screen_save.cfg"

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
	SceneRouter.change_scene = SceneRouter.default_change_scene()
	_delete_save()
	SaveManager.save_path = SaveManager.DEFAULT_SAVE_PATH
	GameState.highest_unlocked_level = 1
	GameState.all_levels_unlocked = false
	GameState.energy = 0
	GameState.current_level_id = ""
	GameState.is_retry = false
	GameState.final_choice = &""
	Feedback.reset()
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _delete_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)


func _write_save(highest: int) -> void:
	var file: ConfigFile = ConfigFile.new()
	file.set_value("progress", "save_version", 1)
	file.set_value("progress", "highest_unlocked_level", highest)
	assert_eq(file.save(TEST_SAVE), OK, "fixture save written")


func _record(path: String) -> Error:
	_calls.append(path)
	return OK


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _make() -> EndScreen:
	var screen: EndScreen = END_SCENE.instantiate() as EndScreen
	Log.sink = _capture
	add_child_autofree(screen)
	return screen


## Makes the end screen with a failed config: empty tuning, load_error set, asserts off.
func _make_bad() -> EndScreen:
	Config.assert_on_missing = false
	Config.tuning = {}
	Config.load_error = BAD_CONFIG
	return _make()


func _label(screen: EndScreen, name: String) -> Label:
	return screen.get_node(name) as Label


func _back(screen: EndScreen) -> Button:
	return screen.get_node("Back") as Button


func _background(screen: EndScreen) -> LevelBackground:
	return screen.get_node_or_null("Background") as LevelBackground


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


## A label spans the full canvas width with its vertical centre on `centre_y`
## at `font_px`.
func _assert_text_at(label: Label, centre_y: float, font_px: int) -> void:
	assert_almost_eq(label.position.y + label.size.y / 2.0, centre_y, 0.5, "%s centred at y %s" % [label.name, centre_y])
	assert_eq(label.position.x, 0.0, "%s from the left edge" % label.name)
	assert_eq(label.size.x, 1920.0, "%s spans the canvas width" % label.name)
	assert_eq(label.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER, "%s centred horizontally" % label.name)
	assert_eq(label.get_theme_font_size(&"font_size"), font_px, "%s %d px" % [label.name, font_px])


## The shared retry-button styles: normal has a `border` edge, hover and focus a
## `coalition` edge.
func _assert_button_styles(button: Button) -> void:
	var expected: Dictionary = {&"normal": Color("#2A3B5C"), &"hover": Color("#22E6FF"), &"focus": Color("#22E6FF")}
	for style: StringName in expected:
		var box: StyleBoxFlat = button.get_theme_stylebox(style) as StyleBoxFlat
		assert_not_null(box, "%s %s StyleBoxFlat" % [button.name, style])
		if box != null:
			_assert_color(box.border_color, expected[style] as Color, "%s %s border" % [button.name, style])


# --- Data and theme ---------------------------------------------------------------

func test_theme_items() -> void:
	var theme: Theme = load("res://ui/theme/defector_theme.tres") as Theme
	_assert_color(theme.get_color(&"logo", &"EndScreen"), theme.get_color(&"logo", &"Title"), "logo = Title logo")
	_assert_color(theme.get_color(&"logo_glow", &"EndScreen"), theme.get_color(&"logo_glow", &"Title"), "logo_glow = Title logo_glow")
	_assert_color(theme.get_color(&"text", &"EndScreen"), Color("#E8F4FF"), "text")
	_assert_color(theme.get_color(&"muted", &"EndScreen"), Color("#93A7C2"), "muted")
	assert_eq(theme.get_constant(&"logo_glow_px", &"EndScreen"), 16, "logo glow outline")
	assert_eq(theme.get_font_size(&"button", &"EndScreen"), 28)
	for style: StringName in [&"button_normal", &"button_hover", &"button_focus"]:
		assert_true(theme.has_stylebox(style, &"EndScreen"), "EndScreen/styles/%s" % style)
		assert_eq(theme.get_stylebox(style, &"EndScreen"), theme.get_stylebox(style, &"RetryPrompt"), "%s reuses the retry button style" % style)


# --- Scene shape --------------------------------------------------------------------

func test_scene_shape_and_texts() -> void:
	var screen: EndScreen = _make()
	var names: Array[String] = []
	for child: Node in screen.get_children():
		names.append(String(child.name))
	assert_eq(names, ["Background", "Logo", "ClosingLine", "Thanks", "Back"] as Array[String], "children in draw order")
	assert_eq(_label(screen, "Logo").text, "DEFECTOR")
	assert_eq(_label(screen, "ClosingLine").text, EndScreen.TEXT_CLOSING)
	assert_eq(EndScreen.TEXT_CLOSING, "The Sovereignty has fallen. The war is over.")
	assert_eq(_label(screen, "Thanks").text, "Thanks for playing")
	assert_eq(_back(screen).text, "BACK TO TITLE")


## The backdrop: the reused LevelBackground showing the throne world, drawn
## first (behind every label and the button).
func test_background_is_the_throne_world_drawn_first() -> void:
	var screen: EndScreen = _make()
	var bg: LevelBackground = _background(screen)
	assert_not_null(bg, "Background is a LevelBackground")
	if bg == null:
		return
	assert_eq(bg.get_script(), load("res://scenes/level/level_background.gd"), "the level's script, reused")
	assert_true(bg.shows_throne_world(), "the throne world")
	assert_eq(bg.get_index(), 0, "the first child, so it draws first")
	assert_eq(_lines_starting("[WARN]"), [] as Array[String], "no warning")


## The project clear colour is the UX `background` token (the backdrop's base).
func test_clear_colour_is_the_background_token() -> void:
	var clear: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color") as Color
	_assert_color(clear, Color("#05070F"), "clear colour")


# --- Healthy config ---------------------------------------------------------------

func test_healthy_layout() -> void:
	var screen: EndScreen = _make()
	await wait_process_frames(1)
	assert_false(screen.is_config_error())
	_assert_text_at(_label(screen, "Logo"), 320.0, 120)
	_assert_text_at(_label(screen, "ClosingLine"), 480.0, 30)
	_assert_text_at(_label(screen, "Thanks"), 560.0, 28)
	var back: Button = _back(screen)
	assert_eq(Rect2(back.position, back.size), Rect2(760, 700, 400, 72), "BACK TO TITLE rect")


func test_layout_follows_ui_end_screen_tuning() -> void:
	var tuned: Dictionary = (Config.tuning["ui"] as Dictionary)["end_screen"]
	tuned["logo_y"] = 300
	tuned["logo_px"] = 100
	tuned["line_y"] = 500
	tuned["line_px"] = 40
	tuned["thanks_y"] = 600
	tuned["thanks_px"] = 24
	tuned["button_w"] = 300
	tuned["button_h"] = 60
	tuned["button_top_y"] = 800
	var screen: EndScreen = _make()
	await wait_process_frames(1)
	_assert_text_at(_label(screen, "Logo"), 300.0, 100)
	_assert_text_at(_label(screen, "ClosingLine"), 500.0, 40)
	_assert_text_at(_label(screen, "Thanks"), 600.0, 24)
	var back: Button = _back(screen)
	assert_eq(Rect2(back.position, back.size), Rect2(810, 800, 300, 60), "BACK TO TITLE rect")


func test_colours_and_button_style() -> void:
	var screen: EndScreen = _make()
	var logo: Label = _label(screen, "Logo")
	_assert_color(logo.get_theme_color(&"font_color"), Color("#22E6FF"), "logo colour")
	var glow: Color = logo.get_theme_color(&"font_shadow_color")
	_assert_color(Color(glow, 1.0), Color("#22E6FF"), "logo glow hue")
	assert_almost_eq(glow.a, 0.5, 0.05, "logo glow alpha")
	assert_eq(logo.get_theme_constant(&"shadow_outline_size"), 16, "logo glow outline")
	assert_eq(logo.get_theme_constant(&"shadow_offset_x"), 0)
	assert_eq(logo.get_theme_constant(&"shadow_offset_y"), 0)
	_assert_color(_label(screen, "ClosingLine").get_theme_color(&"font_color"), Color("#E8F4FF"), "closing line in text")
	_assert_color(_label(screen, "Thanks").get_theme_color(&"font_color"), Color("#93A7C2"), "thanks in muted")
	var back: Button = _back(screen)
	assert_eq(back.get_theme_font_size(&"font_size"), 28, "button font")
	_assert_color(back.get_theme_color(&"font_color"), Color("#E8F4FF"), "button text")
	assert_eq(back.focus_mode, Control.FOCUS_NONE, "takes no focus (mouse-only)")
	assert_false(back.has_focus(), "nothing focused")
	assert_false(back.disabled, "enabled")
	_assert_button_styles(back)


func test_mouse_mode_visible_and_ready_line() -> void:
	_make()
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE)
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE)
	assert_eq(_lines_starting("[INFO][scene] End screen ready"), ["[INFO][scene] End screen ready"] as Array[String], "one ready line")


# --- BACK TO TITLE ----------------------------------------------------------------

func test_back_goes_to_the_title_once() -> void:
	_write_save(3)
	GameState.energy = 80
	GameState.highest_unlocked_level = 3
	var screen: EndScreen = _make()
	_back(screen).pressed.emit()
	_back(screen).pressed.emit()
	assert_eq(_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String], "one change to the title")
	assert_eq(GameState.energy, 0, "energy zeroed (never saved)")
	assert_eq(GameState.highest_unlocked_level, 3, "unlock restored from the save")
	assert_eq(_lines_starting("[INFO][scene] Going to the title screen").size(), 1, "one title line")


## A real click on the button goes through the GUI.
func test_real_click_goes_to_the_title() -> void:
	var screen: EndScreen = _make()
	await wait_process_frames(1)
	var at: Vector2 = _back(screen).get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = at
		event.global_position = at
		get_viewport().push_input(event, true)
	assert_eq(_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String], "one change to the title")


# --- Bad config -------------------------------------------------------------------

func test_bad_config_keeps_the_authored_layout_and_calls_no_getter() -> void:
	var screen: EndScreen = _make_bad()
	assert_true(screen.is_config_error())
	await wait_process_frames(1)
	_assert_text_at(_label(screen, "Logo"), 320.0, 120)
	_assert_text_at(_label(screen, "ClosingLine"), 480.0, 30)
	_assert_text_at(_label(screen, "Thanks"), 560.0, 28)
	var back: Button = _back(screen)
	assert_eq(Rect2(back.position, back.size), Rect2(760, 700, 400, 72), "authored BACK TO TITLE rect")
	assert_eq(_label(screen, "Logo").text, "DEFECTOR")
	assert_eq(_label(screen, "ClosingLine").text, EndScreen.TEXT_CLOSING)
	assert_eq(_label(screen, "Thanks").text, "Thanks for playing")
	assert_eq(back.text, "BACK TO TITLE")
	assert_true(_background(screen).shows_throne_world(), "the backdrop still shows")
	assert_eq(_lines_starting("[ERROR][data]"), [] as Array[String], "no Config getter called")
	assert_eq(_lines_starting("[INFO][scene] End screen ready").size(), 1, "ready line still logged")
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE)


func test_bad_config_button_still_goes_to_the_title() -> void:
	_write_save(2)
	GameState.energy = 10
	var screen: EndScreen = _make_bad()
	_back(screen).pressed.emit()
	_back(screen).pressed.emit()
	assert_eq(_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String], "one change to the title")
	assert_eq(GameState.highest_unlocked_level, 2, "unlock restored from the save")
	assert_eq(GameState.energy, 0, "energy zeroed")
	assert_eq(_lines_starting("[ERROR][data]"), [] as Array[String], "no Config getter called")
