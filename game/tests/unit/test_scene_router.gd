extends GutTest
## SceneRouter (Story 3.2): restart_level() and the placeholder goto_title()
## reset GameState, clear every pause reason, end hit-stop and change the scene
## through the injectable change_scene (a recorder here: the real one would
## replace the test runner's scene).

var _calls: Array[String] = []
var _lines: Array[String] = []


func before_each() -> void:
	_calls.clear()
	_lines.clear()
	SceneRouter.change_scene = _record
	Log.sink = _capture


func after_each() -> void:
	Log.sink = Callable()
	SceneRouter.change_scene = SceneRouter.default_change_scene()
	GameState.energy = 0
	GameState.current_level_id = ""
	GameState.is_retry = false
	Feedback.reset()
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _record(path: String) -> Error:
	_calls.append(path)
	return OK


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _scene_lines() -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.begins_with("[INFO][scene]"):
			out.append(line)
	return out


func test_process_mode_always() -> void:
	assert_eq(SceneRouter.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_default_change_scene_is_the_tree_method() -> void:
	var real: Callable = SceneRouter.default_change_scene()
	assert_true(real.is_valid())
	assert_eq(real.get_method(), &"change_scene_to_file")
	assert_eq(real.get_object(), get_tree())


## A fresh router (the autoload's field is reset by every after_each, so only a
## new instance proves _ready wires the real scene change when nothing is injected).
func test_ready_wires_the_real_change_scene() -> void:
	var router: Node = (load("res://autoloads/scene_router.gd") as GDScript).new() as Node
	add_child_autofree(router)
	var wired: Callable = router.get(&"change_scene")
	assert_true(wired.is_valid())
	assert_eq(wired.get_method(), &"change_scene_to_file")
	assert_eq(wired.get_object(), get_tree())


func test_level_scene_path() -> void:
	assert_eq(SceneRouter.LEVEL_SCENE_PATH, "res://scenes/level/level.tscn")
	assert_true(ResourceLoader.exists(SceneRouter.LEVEL_SCENE_PATH))


func test_restart_level_resets_and_reloads() -> void:
	GameState.energy = 70
	GameState.current_level_id = "dev"
	GameState.is_retry = false
	PauseArbiter.push(&"death")
	Feedback.hit_stop(500.0)
	SceneRouter.restart_level()
	assert_eq(GameState.energy, 0, "energy wiped")
	assert_true(GameState.is_retry, "marked as a retry")
	assert_eq(GameState.current_level_id, "dev", "same level id")
	assert_false(PauseArbiter.is_paused(), "pause reasons cleared")
	assert_eq(PauseArbiter.reasons(), [] as Array[StringName])
	assert_eq(Engine.time_scale, 1.0, "hit-stop ended")
	assert_false(Feedback.is_hit_stopped())
	assert_eq(_calls, ["res://scenes/level/level.tscn"] as Array[String], "one scene change")
	assert_eq(_scene_lines().size(), 1, "one INFO scene line")


func test_many_restarts_have_no_limit() -> void:
	for i: int in 25:
		SceneRouter.restart_level()
	assert_eq(_calls.size(), 25, "every retry reloads")
	for path: String in _calls:
		assert_eq(path, SceneRouter.LEVEL_SCENE_PATH)
	assert_true(GameState.is_retry)


func test_goto_title_is_a_fresh_attempt_of_the_main_scene() -> void:
	GameState.energy = 30
	GameState.is_retry = true
	GameState.current_level_id = "dev"
	PauseArbiter.push(&"death")
	SceneRouter.goto_title()
	assert_eq(GameState.energy, 0)
	assert_false(GameState.is_retry, "not a retry")
	assert_eq(GameState.current_level_id, "", "level id cleared: the main scene uses its own")
	assert_false(PauseArbiter.is_paused())
	assert_eq(Engine.time_scale, 1.0)
	var main_scene: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	assert_eq(_calls, [main_scene] as Array[String])
	assert_eq(_scene_lines().size(), 1, "one INFO scene line")
