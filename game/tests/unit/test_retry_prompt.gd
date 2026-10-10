extends GutTest
## RetryPrompt (Story 3.2): hidden until Events.level_failed, then a pausable
## feedback.player_death_pause_s beat, then PauseArbiter.push(&"death") and
## the dim + loss reason + RETRY / QUIT TO TITLE (ui.retry_prompt layout).
## RETRY -> SceneRouter.restart_level(), QUIT -> SceneRouter.goto_title(); the
## scene change is a recorder here.

const PROMPT_SCENE: PackedScene = preload("res://ui/menus/retry_prompt.tscn")
const THEME_PATH: String = "res://ui/theme/defector_theme.tres"
## Short beat for the tests (the shipped value is 1.5 s).
const BEAT_S: float = 0.2
## QUIT reaches goto_title(), which reads the save: a test file, never the real one.
const TEST_SAVE: String = "user://test_retry_prompt_save.cfg"

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


func _make(beat_s: float = BEAT_S) -> RetryPrompt:
	(Config.tuning["feedback"] as Dictionary)["player_death_pause_s"] = beat_s
	var prompt: RetryPrompt = PROMPT_SCENE.instantiate() as RetryPrompt
	add_child_autofree(prompt)
	return prompt


func _retry(prompt: RetryPrompt) -> Button:
	return prompt.get_node("Retry") as Button


func _quit(prompt: RetryPrompt) -> Button:
	return prompt.get_node("Quit") as Button


func _reason(prompt: RetryPrompt) -> Label:
	return prompt.get_node("Reason") as Label


## Real-time wait that also runs while the tree is paused.
func _wait_always(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _assert_color(actual: Color, expected: Color, what: String) -> void:
	assert_almost_eq(actual.r, expected.r, 0.002, what + " r")
	assert_almost_eq(actual.g, expected.g, 0.002, what + " g")
	assert_almost_eq(actual.b, expected.b, 0.002, what + " b")
	assert_almost_eq(actual.a, expected.a, 0.002, what + " a")


# --- Setup and layout -------------------------------------------------------------

func test_tuning() -> void:
	assert_eq(Config.num("feedback.player_death_pause_s"), 1.5)
	assert_eq(Config.num("ui.retry_prompt.headline_y"), 440.0)
	assert_eq(Config.num("ui.retry_prompt.headline_px"), 48.0)
	assert_eq(Config.num("ui.retry_prompt.button_w"), 320.0)
	assert_eq(Config.num("ui.retry_prompt.button_h"), 80.0)
	assert_eq(Config.num("ui.retry_prompt.button_gap_px"), 48.0)
	assert_eq(Config.num("ui.retry_prompt.buttons_top_y"), 560.0)


func test_hidden_at_start() -> void:
	var prompt: RetryPrompt = _make()
	assert_eq(prompt.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_false(prompt.visible)
	assert_false(prompt.is_shown())
	assert_false(prompt.is_pending())
	assert_eq(prompt.mouse_filter, Control.MOUSE_FILTER_IGNORE, "no mouse capture while hidden")
	assert_false(PauseArbiter.is_paused())


func test_uses_the_shared_theme() -> void:
	var prompt: RetryPrompt = _make()
	assert_not_null(prompt.theme)
	if prompt.theme != null:
		assert_eq(prompt.theme.resource_path, THEME_PATH)
	var theme: Theme = load(THEME_PATH) as Theme
	assert_true(theme.has_color(&"dim", &"RetryPrompt"))
	assert_true(theme.has_color(&"reason", &"RetryPrompt"))
	_assert_color(theme.get_color(&"dim", &"RetryPrompt"), Color(0, 0, 0, 0.6), "dim token")
	_assert_color(theme.get_color(&"reason", &"RetryPrompt"), Color("#FF1F4B"), "danger token")
	var normal: StyleBoxFlat = theme.get_stylebox(&"button_normal", &"RetryPrompt") as StyleBoxFlat
	var hover: StyleBoxFlat = theme.get_stylebox(&"button_hover", &"RetryPrompt") as StyleBoxFlat
	assert_not_null(normal, "button_normal StyleBoxFlat")
	assert_not_null(hover, "button_hover StyleBoxFlat")
	if normal != null:
		_assert_color(normal.bg_color, Color(10.0 / 255.0, 18.0 / 255.0, 34.0 / 255.0, 0.85), "surfaceAlt fill")
		_assert_color(normal.border_color, Color("#2A3B5C"), "border")
		assert_eq(normal.border_width_top, 1)
	if hover != null:
		_assert_color(hover.border_color, Color("#22E6FF"), "coalition hover border")
	assert_true(theme.has_stylebox(&"button_focus", &"RetryPrompt"))
	var focus: StyleBoxFlat = theme.get_stylebox(&"button_focus", &"RetryPrompt") as StyleBoxFlat
	assert_not_null(focus, "button_focus StyleBoxFlat")
	if focus != null:
		_assert_color(focus.border_color, Color("#22E6FF"), "coalition focus border")


func test_layout() -> void:
	var prompt: RetryPrompt = _make()
	var dim: ColorRect = prompt.get_node("Dim") as ColorRect
	_assert_color(dim.color, Color(0, 0, 0, 0.6), "dim colour")
	assert_eq(dim.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var reason: Label = _reason(prompt)
	assert_eq(reason.position.y, 440.0, "headline top")
	assert_eq(reason.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER)
	assert_almost_eq(reason.position.x + reason.size.x / 2.0, Playfield.SIZE.x / 2.0, 0.5, "centred")
	assert_eq(reason.get_theme_font_size(&"font_size"), 48)
	_assert_color(reason.get_theme_color(&"font_color"), Color("#FF1F4B"), "danger headline")
	assert_eq(_retry(prompt).get_rect(), Rect2(616, 560, 320, 80), "RETRY rect")
	assert_eq(_quit(prompt).get_rect(), Rect2(984, 560, 320, 80), "QUIT rect")
	assert_eq(_retry(prompt).text, "RETRY")
	assert_eq(_quit(prompt).text, "QUIT TO TITLE")
	var text_color: Color = (load(THEME_PATH) as Theme).get_color(&"text", &"RetryPrompt")
	for button: Button in [_retry(prompt), _quit(prompt)]:
		var expected: Dictionary = {&"normal": Color("#2A3B5C"), &"hover": Color("#22E6FF"), &"focus": Color("#22E6FF")}
		for style: StringName in expected:
			var box: StyleBoxFlat = button.get_theme_stylebox(style) as StyleBoxFlat
			assert_not_null(box, "%s %s StyleBoxFlat" % [button.name, style])
			if box != null:
				_assert_color(box.border_color, expected[style] as Color, "%s %s border" % [button.name, style])
		assert_eq(button.get_theme_font_size(&"font_size"), 28, "%s font size" % button.name)
		_assert_color(button.get_theme_color(&"font_color"), text_color, "%s text colour" % button.name)


func test_button_rects_math() -> void:
	var rects: Array[Rect2] = RetryPrompt.button_rects(1920.0, Vector2(320, 80), 48.0, 560.0)
	assert_eq(rects, [Rect2(616, 560, 320, 80), Rect2(984, 560, 320, 80)] as Array[Rect2])


# --- Death beat -------------------------------------------------------------------

func test_beat_then_prompt() -> void:
	var prompt: RetryPrompt = _make()
	Events.level_failed.emit(&"hearts")
	assert_true(prompt.is_pending(), "beat running")
	assert_false(prompt.is_shown())
	assert_false(prompt.visible)
	assert_false(PauseArbiter.is_paused(), "the world keeps running during the beat")
	await _wait_always(BEAT_S / 2.0)
	assert_false(prompt.is_shown(), "still in the beat")
	await _wait_always(BEAT_S)
	assert_true(prompt.is_shown(), "shown after the beat")
	assert_false(prompt.is_pending())
	assert_true(prompt.visible)
	assert_eq(PauseArbiter.reasons(), [&"death"] as Array[StringName])
	assert_true(get_tree().paused)
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "cursor visible")
	assert_eq(prompt.reason_text(), "HULL DESTROYED")
	assert_eq(_reason(prompt).text, "HULL DESTROYED")
	assert_eq(prompt.mouse_filter, Control.MOUSE_FILTER_STOP, "captures the mouse while shown")
	assert_true(_retry(prompt).has_focus(), "RETRY has focus")


func test_beat_freezes_under_another_pause() -> void:
	var prompt: RetryPrompt = _make()
	Events.level_failed.emit(&"hearts")
	PauseArbiter.push(&"menu")
	await _wait_always(BEAT_S * 2.0)
	assert_false(prompt.is_shown(), "the beat is frozen while paused")
	assert_true(prompt.is_pending())
	PauseArbiter.pop(&"menu")
	await _wait_always(BEAT_S * 2.0)
	assert_true(prompt.is_shown(), "shown once unpaused time reaches the beat")
	assert_eq(PauseArbiter.reasons(), [&"death"] as Array[StringName])


func test_second_failure_is_ignored() -> void:
	var prompt: RetryPrompt = _make()
	Events.level_failed.emit(&"hearts")
	Events.level_failed.emit(&"convoy")
	await _wait_always(BEAT_S * 2.0)
	assert_true(prompt.is_shown())
	assert_eq(prompt.reason_text(), "HULL DESTROYED", "the first reason wins")
	Events.level_failed.emit(&"convoy")
	await _wait_always(BEAT_S * 2.0)
	assert_eq(prompt.reason_text(), "HULL DESTROYED", "ignored while shown")
	assert_false(prompt.is_pending())
	assert_eq(PauseArbiter.reasons(), [&"death"] as Array[StringName])


func test_reason_texts() -> void:
	var prompt: RetryPrompt = _make()
	prompt.show_prompt(&"convoy")
	assert_eq(prompt.reason_text(), "CONVOY LOST")
	var other: RetryPrompt = _make()
	PauseArbiter.clear()
	other.show_prompt(&"something_else")
	assert_eq(other.reason_text(), "HULL DESTROYED", "unknown reason falls back")
	var warns: int = 0
	for line: String in _lines:
		if line.begins_with("[WARN]") and line.contains("something_else"):
			warns += 1
	assert_eq(warns, 1, "unknown reason warned")


# --- Buttons ----------------------------------------------------------------------

func test_retry_restarts_the_level() -> void:
	var prompt: RetryPrompt = _make()
	GameState.energy = 60
	GameState.current_level_id = "dev"
	prompt.show_prompt(&"hearts")
	assert_true(PauseArbiter.is_paused())
	_retry(prompt).pressed.emit()
	assert_eq(GameState.energy, 0)
	assert_true(GameState.is_retry)
	assert_eq(GameState.current_level_id, "dev")
	assert_false(PauseArbiter.is_paused(), "not paused")
	assert_eq(Engine.time_scale, 1.0)
	assert_eq(_calls, [SceneRouter.LEVEL_SCENE_PATH] as Array[String], "level.tscn once")


func test_repeat_press_does_nothing_more() -> void:
	var prompt: RetryPrompt = _make()
	prompt.show_prompt(&"hearts")
	_retry(prompt).pressed.emit()
	_retry(prompt).pressed.emit()
	_quit(prompt).pressed.emit()
	assert_eq(_calls.size(), 1, "one scene change")
	assert_true(GameState.is_retry, "the quit was ignored")


func test_quit_goes_to_the_title() -> void:
	var prompt: RetryPrompt = _make()
	GameState.energy = 60
	GameState.is_retry = true
	prompt.show_prompt(&"hearts")
	_quit(prompt).pressed.emit()
	assert_eq(GameState.energy, 0)
	assert_false(GameState.is_retry)
	assert_false(PauseArbiter.is_paused())
	assert_eq(_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String])


func test_buttons_do_nothing_while_hidden() -> void:
	var prompt: RetryPrompt = _make()
	_retry(prompt).pressed.emit()
	_quit(prompt).pressed.emit()
	assert_eq(_calls, [] as Array[String])


# --- First outcome wins at the consumer (DW-75, Story 6.1) ----------------------------

func test_failure_after_a_clear_is_ignored() -> void:
	var prompt: RetryPrompt = _make()
	Events.level_cleared.emit(0)
	Events.level_failed.emit(&"convoy")
	assert_false(prompt.is_pending(), "no death beat after a clear")
	await _wait_always(BEAT_S * 2.0)
	assert_false(prompt.is_shown(), "no prompt")
	assert_false(prompt.visible)
	assert_false(PauseArbiter.is_paused(), "no death pause")


func test_convoy_loss_shows_convoy_lost() -> void:
	var prompt: RetryPrompt = _make()
	Events.level_failed.emit(&"convoy")
	assert_true(prompt.is_pending())
	await _wait_always(BEAT_S * 2.0)
	assert_true(prompt.is_shown())
	assert_eq(prompt.reason_text(), "CONVOY LOST")
