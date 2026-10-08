extends GutTest
## Story 4.5 (FR59): SceneRouter owns the F11 window toggle. toggle_fullscreen
## flips borderless fullscreen <-> windowed in any scene, paused or not, and the
## choice is never persisted. The router's get_window_mode / set_window_mode are
## recorders here, so the real window never changes. Also pins the letterbox:
## a non-16:9 root keeps the 1920x1080 canvas and scales it uniformly.

const TEST_SAVE: String = "user://test_window_mode_save.cfg"

## The mode the injected getter reports.
var _mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN
## Every mode the router set through the injected setter.
var _sets: Array[DisplayServer.WindowMode] = []
var _lines: Array[String] = []


func before_each() -> void:
	_mode = DisplayServer.WINDOW_MODE_FULLSCREEN
	_sets.clear()
	_lines.clear()
	SaveManager.save_path = TEST_SAVE
	_delete_save()
	SceneRouter.get_window_mode = _get_mode
	SceneRouter.set_window_mode = _set_mode
	Log.sink = _capture


func after_each() -> void:
	Log.sink = Callable()
	SceneRouter.get_window_mode = SceneRouter.default_get_window_mode()
	SceneRouter.set_window_mode = SceneRouter.default_set_window_mode()
	_delete_save()
	SaveManager.save_path = SaveManager.DEFAULT_SAVE_PATH
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _delete_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)


func _get_mode() -> DisplayServer.WindowMode:
	return _mode


func _set_mode(mode: DisplayServer.WindowMode) -> void:
	_sets.append(mode)
	_mode = mode


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _window_lines() -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.begins_with("[INFO][scene] Window mode:"):
			out.append(line)
	return out


func _key(keycode: Key, echo: bool = false) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	event.echo = echo
	return event


# --- toggled_window_mode ---------------------------------------------------------

func test_toggled_window_mode_for_every_mode() -> void:
	assert_eq(SceneRouter.toggled_window_mode(DisplayServer.WINDOW_MODE_FULLSCREEN),
		DisplayServer.WINDOW_MODE_WINDOWED, "fullscreen -> windowed")
	assert_eq(SceneRouter.toggled_window_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN),
		DisplayServer.WINDOW_MODE_WINDOWED, "exclusive -> windowed")
	assert_eq(SceneRouter.toggled_window_mode(DisplayServer.WINDOW_MODE_WINDOWED),
		DisplayServer.WINDOW_MODE_FULLSCREEN, "windowed -> fullscreen")
	assert_eq(SceneRouter.toggled_window_mode(DisplayServer.WINDOW_MODE_MAXIMIZED),
		DisplayServer.WINDOW_MODE_FULLSCREEN, "maximized -> fullscreen")
	assert_eq(SceneRouter.toggled_window_mode(DisplayServer.WINDOW_MODE_MINIMIZED),
		DisplayServer.WINDOW_MODE_FULLSCREEN, "minimized -> fullscreen")


# --- toggle_window_mode ----------------------------------------------------------

func test_toggle_from_fullscreen_goes_windowed() -> void:
	SceneRouter.toggle_window_mode()
	assert_eq(_sets, [DisplayServer.WINDOW_MODE_WINDOWED] as Array[DisplayServer.WindowMode], "set once")
	assert_eq(_window_lines(), ["[INFO][scene] Window mode: windowed"] as Array[String])


func test_toggle_from_windowed_goes_fullscreen() -> void:
	_mode = DisplayServer.WINDOW_MODE_WINDOWED
	SceneRouter.toggle_window_mode()
	assert_eq(_sets, [DisplayServer.WINDOW_MODE_FULLSCREEN] as Array[DisplayServer.WindowMode], "set once")
	assert_eq(_window_lines(), ["[INFO][scene] Window mode: fullscreen"] as Array[String])


func test_toggle_from_exclusive_goes_windowed() -> void:
	_mode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	SceneRouter.toggle_window_mode()
	assert_eq(_sets, [DisplayServer.WINDOW_MODE_WINDOWED] as Array[DisplayServer.WindowMode])


func test_toggle_from_maximized_or_minimized_goes_fullscreen() -> void:
	for mode: DisplayServer.WindowMode in [DisplayServer.WINDOW_MODE_MAXIMIZED, DisplayServer.WINDOW_MODE_MINIMIZED]:
		_sets.clear()
		_mode = mode
		SceneRouter.toggle_window_mode()
		assert_eq(_sets, [DisplayServer.WINDOW_MODE_FULLSCREEN] as Array[DisplayServer.WindowMode], "mode %d" % mode)


func test_two_toggles_round_trip() -> void:
	SceneRouter.toggle_window_mode()
	SceneRouter.toggle_window_mode()
	assert_eq(_sets, [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN] as Array[DisplayServer.WindowMode])
	assert_eq(_mode, DisplayServer.WINDOW_MODE_FULLSCREEN)


# --- F11 through the viewport ----------------------------------------------------

func test_real_f11_key_toggles_once_and_is_handled() -> void:
	get_viewport().push_input(_key(KEY_F11))
	assert_true(get_viewport().is_input_handled(), "F11 marked handled")
	assert_eq(_sets, [DisplayServer.WINDOW_MODE_WINDOWED] as Array[DisplayServer.WindowMode], "toggled once")
	assert_eq(_window_lines().size(), 1, "one INFO scene line")


func test_f11_action_event_toggles() -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = &"toggle_fullscreen"
	event.pressed = true
	get_viewport().push_input(event)
	assert_true(get_viewport().is_input_handled())
	assert_eq(_sets, [DisplayServer.WINDOW_MODE_WINDOWED] as Array[DisplayServer.WindowMode])


func test_f11_toggles_while_paused() -> void:
	PauseArbiter.push(&"menu")
	assert_true(get_tree().paused, "tree paused")
	get_viewport().push_input(_key(KEY_F11))
	assert_true(get_viewport().is_input_handled(), "handled while paused")
	assert_eq(_sets, [DisplayServer.WINDOW_MODE_WINDOWED] as Array[DisplayServer.WindowMode], "toggled once")
	assert_eq(PauseArbiter.reasons(), [&"menu"] as Array[StringName], "pause untouched")


func test_echo_does_not_toggle() -> void:
	get_viewport().push_input(_key(KEY_F11, true))
	assert_false(get_viewport().is_input_handled(), "echo not handled")
	assert_eq(_sets, [] as Array[DisplayServer.WindowMode], "no call")
	assert_eq(_window_lines(), [] as Array[String])


func test_other_keys_do_not_toggle() -> void:
	SceneRouter._unhandled_input(_key(KEY_ESCAPE))
	SceneRouter._unhandled_input(_key(KEY_F1))
	var release: InputEventKey = _key(KEY_F11)
	release.pressed = false
	SceneRouter._unhandled_input(release)
	assert_eq(_sets, [] as Array[DisplayServer.WindowMode], "no call for Esc, F1 or an F11 release")


func test_toggle_is_not_persisted() -> void:
	get_viewport().push_input(_key(KEY_F11))
	SceneRouter.toggle_window_mode()
	assert_eq(_sets.size(), 2)
	assert_false(FileAccess.file_exists(TEST_SAVE), "no save file written")
	assert_eq(ProjectSettings.get_setting("display/window/size/mode"), 3, "the launch mode setting is unchanged")


# --- Router wiring ---------------------------------------------------------------

func test_router_process_mode_always() -> void:
	assert_eq(SceneRouter.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_defaults_are_the_display_server_methods() -> void:
	var getter: Callable = SceneRouter.default_get_window_mode()
	var setter: Callable = SceneRouter.default_set_window_mode()
	assert_true(getter.is_valid())
	assert_true(setter.is_valid())
	assert_eq(getter.get_method(), &"window_get_mode")
	assert_eq(setter.get_method(), &"window_set_mode")


## A fresh router (the autoload's fields are reset by every after_each, so only a
## new instance proves _ready wires the real window-mode callables).
func test_ready_wires_the_real_window_mode_callables() -> void:
	var router: Node = (load("res://autoloads/scene_router.gd") as GDScript).new() as Node
	add_child_autofree(router)
	router.set_process_unhandled_input(false)
	var getter: Callable = router.get(&"get_window_mode")
	var setter: Callable = router.get(&"set_window_mode")
	assert_true(getter.is_valid())
	assert_true(setter.is_valid())
	assert_eq(getter.get_method(), &"window_get_mode")
	assert_eq(setter.get_method(), &"window_set_mode")


# --- Letterbox -------------------------------------------------------------------

func test_non_16_9_root_letterboxes_uniformly() -> void:
	var root: Window = get_tree().root
	var saved: Vector2i = root.size
	root.size = Vector2i(2560, 1600)
	var resized: Vector2i = root.size
	var visible: Vector2 = root.get_visible_rect().size
	var xform: Transform2D = root.get_final_transform()
	root.size = saved
	assert_eq(resized, Vector2i(2560, 1600), "the headless root accepted the resize")
	assert_eq(visible, Vector2(1920, 1080), "the canvas stays 1920x1080")
	assert_almost_eq(xform.get_scale().x, xform.get_scale().y, 0.0001, "uniform scale")
	assert_almost_eq(xform.get_scale().x, 2560.0 / 1920.0, 0.0001, "fit to the width, bars top and bottom")
	assert_almost_eq(xform.origin, Vector2(0, 80), Vector2(0.0001, 0.0001), "letterbox bar: (1600 - 1440) / 2 = 80 px at the top, none at the sides")
