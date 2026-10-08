extends GutTest
## Boot (Story 4.1): the main scene declares the VISIBLE mouse mode, logs whether
## Config loaded (INFO) or not (ERROR) and goes to the title either way through
## SceneRouter.goto_title() (deferred). Debug builds given --stress / --bench=N
## redirect to the sandbox instead (deferred, through the injectable
## change_scene). Both scene changes are recorders here.

const BOOT_SCENE: PackedScene = preload("res://scenes/boot/boot.tscn")
const BOOT_SCRIPT: GDScript = preload("res://scenes/boot/boot.gd")
## goto_title() reads the save: a test file, never the real one.
const TEST_SAVE: String = "user://test_boot_save.cfg"

var _router_calls: Array[String] = []
var _boot_calls: Array[String] = []
var _lines: Array[String] = []
var _saved_error: String = ""


func before_each() -> void:
	_router_calls.clear()
	_boot_calls.clear()
	_lines.clear()
	_saved_error = Config.load_error
	SaveManager.save_path = TEST_SAVE
	_delete_save()
	GameState.highest_unlocked_level = 1
	GameState.all_levels_unlocked = false
	SceneRouter.change_scene = _record_router
	# Start from the gameplay mode, so the boot's VISIBLE declaration is observable.
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)


func after_each() -> void:
	Log.sink = Callable()
	Config.load_error = _saved_error
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


func _record_router(path: String) -> Error:
	_router_calls.append(path)
	return OK


func _record_boot(path: String) -> Error:
	_boot_calls.append(path)
	return OK


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


## A boot node whose _ready parses `args`, with the boot change_scene recorded
## and its log lines captured.
func _boot(args: PackedStringArray) -> Node:
	var boot: Node = BOOT_SCENE.instantiate()
	boot.set(&"user_args", args)
	boot.set(&"change_scene", _record_boot)
	Log.sink = _capture
	add_child_autofree(boot)
	return boot


func _lines_starting(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.begins_with(prefix):
			out.append(line)
	return out


func test_main_scene_is_the_boot_scene() -> void:
	assert_eq(str(ProjectSettings.get_setting("application/run/main_scene")), "res://scenes/boot/boot.tscn")
	assert_true(ResourceLoader.exists("res://scenes/boot/boot.tscn"))


func test_boot_ok_logs_and_goes_to_the_title() -> void:
	Config.load_error = ""
	_boot(PackedStringArray())
	assert_eq(_lines_starting("[INFO][boot] Config loaded").size(), 1, "INFO boot line")
	assert_eq(_lines_starting("[ERROR][boot]").size(), 0, "no ERROR boot line")
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "menu mouse mode")
	await wait_process_frames(1)
	assert_eq(_router_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String], "one change to the title")
	assert_eq(_boot_calls, [] as Array[String], "no stress redirect")


func test_boot_with_a_bad_config_logs_an_error_and_still_goes_to_the_title() -> void:
	Config.load_error = "res://data/tuning.json parse error at line 3: Expected '}'"
	_boot(PackedStringArray())
	var errors: Array[String] = _lines_starting("[ERROR][boot] Config failed to load: ")
	assert_eq(errors.size(), 1, "ERROR boot line")
	if errors.size() == 1:
		assert_true(errors[0].contains(Config.load_error), "names the load error")
	assert_eq(_lines_starting("[INFO][boot] Config loaded").size(), 0, "no OK line")
	assert_push_error("[ERROR][boot] Config failed to load")
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE)
	await wait_process_frames(1)
	assert_eq(_router_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String], "still goes to the title")


func test_stress_redirect_only_in_debug_builds_with_stress_or_bench() -> void:
	var stress: Dictionary = DebugArgs.parse(PackedStringArray(["--stress"]))
	var bench: Dictionary = DebugArgs.parse(PackedStringArray(["--bench=5"]))
	var none: Dictionary = DebugArgs.parse(PackedStringArray())
	assert_true(BOOT_SCRIPT.should_redirect_to_stress(true, stress), "debug --stress")
	assert_true(BOOT_SCRIPT.should_redirect_to_stress(true, bench), "debug --bench=5")
	assert_false(BOOT_SCRIPT.should_redirect_to_stress(true, none), "debug, no args")
	assert_false(BOOT_SCRIPT.should_redirect_to_stress(false, stress), "release --stress")
	assert_false(BOOT_SCRIPT.should_redirect_to_stress(false, bench), "release --bench=5")


func test_stress_arg_redirects_to_the_sandbox() -> void:
	if not OS.is_debug_build():
		pass_test("release build: no stress redirect")
		return
	_boot(PackedStringArray(["--stress"]))
	assert_eq(_lines_starting("[INFO][boot] Stress/bench args").size(), 1, "redirect logged")
	assert_eq(_lines_starting("[INFO][boot] Config loaded").size(), 0, "no config line")
	assert_eq(_boot_calls.size(), 0, "redirect is deferred")
	await wait_process_frames(1)
	assert_eq(_boot_calls, [BOOT_SCRIPT.SANDBOX_SCENE_PATH] as Array[String], "deferred redirect once")
	assert_eq(_router_calls, [] as Array[String], "no goto_title")


func test_bench_arg_redirects_to_the_sandbox() -> void:
	if not OS.is_debug_build():
		pass_test("release build: no bench redirect")
		return
	_boot(PackedStringArray(["--bench=5"]))
	await wait_process_frames(1)
	assert_eq(_boot_calls, [BOOT_SCRIPT.SANDBOX_SCENE_PATH] as Array[String], "deferred redirect once")
	assert_eq(_router_calls, [] as Array[String], "no goto_title")


## Story 4.2 acceptance: no save -> level 1 unlocked, 0 energy, INFO save line.
func test_boot_without_a_save_uses_the_defaults() -> void:
	GameState.energy = 50
	GameState.highest_unlocked_level = 3
	_boot(PackedStringArray())
	await wait_process_frames(1)
	assert_eq(GameState.highest_unlocked_level, 1)
	assert_eq(GameState.energy, 0)
	assert_eq(_lines_starting("[INFO][save]").size(), 1, "INFO save line")
	assert_eq(_lines_starting("[WARN][save]").size(), 0, "no WARN")
	assert_false(FileAccess.file_exists(TEST_SAVE), "boot writes no save")


## Story 4.2 acceptance: a corrupt or unknown-version save -> WARN + defaults.
func test_boot_with_a_bad_save_warns_and_uses_the_defaults() -> void:
	var file: FileAccess = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string("[progress]\nsave_version=7\nhighest_unlocked_level=3\nenergy=50\n")
	file.close()
	_boot(PackedStringArray())
	await wait_process_frames(1)
	assert_eq(GameState.highest_unlocked_level, 1)
	assert_eq(GameState.energy, 0)
	assert_eq(_lines_starting("[WARN][save]").size(), 1, "WARN save line")
	assert_eq(_router_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String], "still goes to the title")
