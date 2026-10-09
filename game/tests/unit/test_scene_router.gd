extends GutTest
## SceneRouter (Stories 3.2, 4.1): restart_level(), goto_title() and
## start_level(id) set GameState, clear every pause reason, end hit-stop and
## change the scene through the injectable change_scene (a recorder here: the
## real one would replace the test runner's scene). start_level refuses while
## Config.load_error is set. Story 4.2: goto_title() restores energy and the
## unlock from the save (clamped), complete_level(n) unlocks, saves and moves
## on, and nothing else writes the save. Story 4.3: goto_level_select() changes
## to the Level Select screen and leaves GameState and the save alone. The save
## is a test file here. Story 5.5: start_level("1") goes through the opening
## story scene (goto_story), finish_story() starts the pending level without the
## opening check, and a retry never plays it.

const TEST_SAVE: String = "user://test_scene_router_save.cfg"

var _calls: Array[String] = []
var _lines: Array[String] = []
## DW-61 ordering: "change paused=<bool>" at each change_scene call and
## "resumed" for each PauseArbiter.resumed, in the order they happened.
var _order: Array[String] = []


func before_each() -> void:
	_calls.clear()
	_lines.clear()
	_order.clear()
	PauseArbiter.resumed.connect(_on_resumed)
	SaveManager.save_path = TEST_SAVE
	_delete_save()
	GameState.highest_unlocked_level = 1
	GameState.all_levels_unlocked = false
	SceneRouter.change_scene = _record
	Log.sink = _capture


func after_each() -> void:
	if PauseArbiter.resumed.is_connected(_on_resumed):
		PauseArbiter.resumed.disconnect(_on_resumed)
	Log.sink = Callable()
	SceneRouter._story_id = &""
	SceneRouter._story_next_level = 0
	SceneRouter.change_scene = SceneRouter.default_change_scene()
	_delete_save()
	SaveManager.save_path = SaveManager.DEFAULT_SAVE_PATH
	GameState.energy = 0
	GameState.current_level_id = ""
	GameState.is_retry = false
	GameState.highest_unlocked_level = 1
	GameState.all_levels_unlocked = false
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


## [save_version, highest_unlocked_level, energy] read straight from the test file.
func _read_save() -> Array:
	var file: ConfigFile = ConfigFile.new()
	if file.load(TEST_SAVE) != OK:
		return []
	return [
		file.get_value("progress", "save_version"),
		file.get_value("progress", "highest_unlocked_level"),
		file.get_value("progress", "energy"),
	]


func _record(path: String) -> Error:
	_calls.append(path)
	_order.append("change paused=%s" % PauseArbiter.is_paused())
	return OK


func _on_resumed() -> void:
	_order.append("resumed")


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


## DW-61: the pauses are still held at the swap call and dropped right after it,
## so `resumed` fires once, after the outgoing scene left the tree.
func test_restart_level_clears_the_pauses_after_the_swap() -> void:
	GameState.current_level_id = "dev"
	PauseArbiter.push(&"death")
	SceneRouter.restart_level()
	assert_eq(_order, ["change paused=true", "resumed"] as Array[String], "paused at the call, resumed once after it")
	assert_false(PauseArbiter.is_paused(), "unpaused afterwards")
	assert_false(get_tree().paused)


func test_goto_title_clears_the_pauses_after_the_swap() -> void:
	PauseArbiter.push(&"menu")
	PauseArbiter.push(&"story")
	SceneRouter.goto_title()
	assert_eq(_order, ["change paused=true", "resumed"] as Array[String], "paused at the call, resumed once after it")
	assert_false(PauseArbiter.is_paused(), "unpaused afterwards")


func test_title_scene_path() -> void:
	assert_eq(SceneRouter.TITLE_SCENE_PATH, "res://scenes/title/title.tscn")
	assert_true(ResourceLoader.exists(SceneRouter.TITLE_SCENE_PATH))


func test_goto_title_resets_state_and_goes_to_the_title() -> void:
	_write_save(1, 20)
	GameState.energy = 30
	GameState.is_retry = true
	GameState.current_level_id = "dev"
	PauseArbiter.push(&"death")
	Feedback.hit_stop(500.0)
	SceneRouter.goto_title()
	assert_eq(GameState.energy, 20, "the saved energy")
	assert_false(GameState.is_retry, "not a retry")
	assert_eq(GameState.current_level_id, "", "level id cleared")
	assert_false(PauseArbiter.is_paused(), "pause reasons cleared")
	assert_eq(Engine.time_scale, 1.0, "hit-stop ended")
	assert_eq(_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String], "one change to the title")
	assert_eq(_scene_lines().size(), 1, "one INFO scene line")


func test_level_select_scene_path() -> void:
	assert_eq(SceneRouter.LEVEL_SELECT_SCENE_PATH, "res://scenes/title/level_select.tscn")
	assert_true(ResourceLoader.exists(SceneRouter.LEVEL_SELECT_SCENE_PATH))


func test_goto_level_select_leaves_game_state_alone() -> void:
	_write_save(1, 5)
	GameState.energy = 45
	GameState.highest_unlocked_level = 2
	GameState.current_level_id = "3"
	GameState.is_retry = true
	PauseArbiter.push(&"menu")
	Feedback.hit_stop(500.0)
	SceneRouter.goto_level_select()
	assert_eq(GameState.energy, 45, "energy unchanged")
	assert_eq(GameState.highest_unlocked_level, 2, "unlock unchanged")
	assert_eq(GameState.current_level_id, "3", "level id unchanged")
	assert_true(GameState.is_retry, "retry flag unchanged")
	assert_false(PauseArbiter.is_paused(), "pause reasons cleared")
	assert_eq(Engine.time_scale, 1.0, "hit-stop ended")
	assert_eq(_calls, [SceneRouter.LEVEL_SELECT_SCENE_PATH] as Array[String], "one change to level select")
	assert_eq(_scene_lines().size(), 1, "one INFO scene line")
	assert_eq(_read_save(), [1, 1, 5], "save untouched")


func test_goto_level_select_writes_no_save() -> void:
	SceneRouter.goto_level_select()
	assert_false(FileAccess.file_exists(TEST_SAVE), "no save written")


func test_start_level_sets_the_id_and_keeps_the_energy() -> void:
	GameState.energy = 40
	GameState.is_retry = true
	GameState.current_level_id = ""
	PauseArbiter.push(&"menu")
	PauseArbiter.push(&"story")
	Feedback.hit_stop(500.0)
	SceneRouter.start_level("2")
	assert_eq(GameState.current_level_id, "2")
	assert_false(GameState.is_retry, "a fresh attempt")
	assert_eq(GameState.energy, 40, "energy carried")
	assert_false(PauseArbiter.is_paused(), "pause reasons cleared")
	assert_eq(PauseArbiter.reasons(), [] as Array[StringName])
	assert_eq(Engine.time_scale, 1.0, "hit-stop ended")
	assert_eq(_calls, [SceneRouter.LEVEL_SCENE_PATH] as Array[String], "one change to the level")
	assert_eq(_scene_lines().size(), 1, "one INFO scene line")


func test_start_level_with_a_config_error_changes_nothing() -> void:
	var saved_error: String = Config.load_error
	Config.load_error = "res://data/tuning.json parse error at line 1: test"
	GameState.energy = 10
	GameState.is_retry = true
	GameState.current_level_id = "dev"
	PauseArbiter.push(&"death")
	SceneRouter.start_level("1")
	Config.load_error = saved_error
	assert_eq(_calls, [] as Array[String], "no scene change")
	assert_eq(GameState.current_level_id, "dev", "level id untouched")
	assert_true(GameState.is_retry, "is_retry untouched")
	assert_eq(GameState.energy, 10, "energy untouched")
	assert_true(PauseArbiter.is_paused(), "pause reasons untouched")
	var errors: int = 0
	for line: String in _lines:
		if line.begins_with("[ERROR][scene]") and line.contains("Cannot start level '1'"):
			errors += 1
	assert_eq(errors, 1, "one ERROR scene line")
	assert_push_error("Cannot start level '1'")
	assert_eq(_scene_lines().size(), 0, "no INFO scene line")


# --- Story 4.2: save restore and progression ---------------------------------------

func test_goto_title_restores_the_saved_energy_and_unlock() -> void:
	_write_save(2, 20)
	GameState.energy = 70
	GameState.highest_unlocked_level = 3
	GameState.all_levels_unlocked = true
	SceneRouter.goto_title()
	assert_eq(GameState.energy, 20, "saved energy, not the in-memory 70 (F13)")
	assert_eq(GameState.highest_unlocked_level, 2, "saved unlock")
	assert_true(GameState.all_levels_unlocked, "the F7 flag survives goto_title")
	assert_eq(_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String])
	assert_eq(_read_save(), [1, 2, 20], "the save is unchanged")


func test_goto_title_clamps_the_saved_values() -> void:
	_write_save(9, 500)
	SceneRouter.goto_title()
	assert_eq(GameState.highest_unlocked_level, 3, "clamped to progression.level_count")
	assert_eq(GameState.energy, 100, "clamped to energy.max")


func test_goto_title_without_a_save_gives_the_defaults() -> void:
	GameState.energy = 70
	GameState.highest_unlocked_level = 3
	SceneRouter.goto_title()
	assert_eq(GameState.energy, 0)
	assert_eq(GameState.highest_unlocked_level, 1)
	assert_false(FileAccess.file_exists(TEST_SAVE), "no save written")


func test_goto_title_with_a_config_error_still_restores() -> void:
	var saved_error: String = Config.load_error
	Config.load_error = "res://data/tuning.json parse error at line 1: test"
	_write_save(2, 20)
	SceneRouter.goto_title()
	Config.load_error = saved_error
	assert_eq(GameState.highest_unlocked_level, 2)
	assert_eq(GameState.energy, 20)
	assert_eq(_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String])


## DW-61: the restore goto_title() does, on its own (F5 calls it): no scene
## change, no level-id change, no save written.
func test_restore_saved_progress_restores_and_clears_the_retry() -> void:
	_write_save(2, 40)
	GameState.energy = 0
	GameState.highest_unlocked_level = 1
	GameState.is_retry = true
	GameState.current_level_id = "2"
	SceneRouter.restore_saved_progress()
	assert_eq(GameState.energy, 40, "saved energy")
	assert_eq(GameState.highest_unlocked_level, 2, "saved unlock")
	assert_false(GameState.is_retry, "retry flag cleared")
	assert_eq(GameState.current_level_id, "2", "level id untouched")
	assert_eq(_calls, [] as Array[String], "no scene change")
	assert_eq(_read_save(), [1, 2, 40], "the save is unchanged")


func test_restore_saved_progress_clamps() -> void:
	_write_save(9, 500)
	SceneRouter.restore_saved_progress()
	assert_eq(GameState.highest_unlocked_level, 3, "clamped to progression.level_count")
	assert_eq(GameState.energy, 100, "clamped to energy.max")


func test_restore_saved_progress_without_a_save_gives_the_defaults() -> void:
	GameState.energy = 70
	GameState.highest_unlocked_level = 3
	GameState.is_retry = true
	SceneRouter.restore_saved_progress()
	assert_eq(GameState.energy, 0)
	assert_eq(GameState.highest_unlocked_level, 1)
	assert_false(GameState.is_retry)
	assert_false(FileAccess.file_exists(TEST_SAVE), "no save written")


func test_complete_level_1_unlocks_saves_and_starts_level_2() -> void:
	GameState.highest_unlocked_level = 1
	GameState.energy = 35
	GameState.current_level_id = "1"
	SceneRouter.complete_level(1)
	assert_eq(GameState.highest_unlocked_level, 2, "level 2 unlocked")
	assert_eq(_read_save(), [1, 2, 35], "save written with the unlock and the energy")
	assert_eq(_calls, [SceneRouter.LEVEL_SCENE_PATH] as Array[String], "one change to the level")
	assert_eq(GameState.current_level_id, "2", "level 2 starts")
	assert_eq(GameState.energy, 35, "energy carried")
	assert_false(GameState.is_retry)


func test_complete_level_1_again_keeps_the_higher_unlock() -> void:
	GameState.highest_unlocked_level = 3
	GameState.energy = 50
	SceneRouter.complete_level(1)
	assert_eq(GameState.highest_unlocked_level, 3, "never lowered")
	assert_eq(_read_save(), [1, 3, 50])
	assert_eq(_calls, [SceneRouter.LEVEL_SCENE_PATH] as Array[String])
	assert_eq(GameState.current_level_id, "2")


func test_complete_last_level_saves_and_goes_to_the_title() -> void:
	GameState.highest_unlocked_level = 3
	GameState.energy = 80
	GameState.current_level_id = "3"
	SceneRouter.complete_level(3)
	assert_eq(_read_save(), [1, 3, 80], "save written")
	assert_eq(_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String], "the title opens")
	assert_eq(GameState.highest_unlocked_level, 3, "restored from the save")
	assert_eq(GameState.energy, 80, "restored from the save")
	assert_eq(GameState.current_level_id, "", "no level id")


func test_f7_flag_never_leaks_into_the_save() -> void:
	GameState.all_levels_unlocked = true
	GameState.highest_unlocked_level = 1
	GameState.energy = 10
	SceneRouter.complete_level(1)
	assert_eq(_read_save(), [1, 2, 10], "the save holds the real unlock (2), not the debug one")
	assert_true(GameState.all_levels_unlocked, "the flag is still on")


func test_complete_level_unlock_never_passes_the_level_count() -> void:
	GameState.highest_unlocked_level = 2
	SceneRouter.complete_level(3)
	assert_eq(GameState.highest_unlocked_level, 3, "min(n + 1, level_count)")


func test_complete_non_campaign_level_does_nothing() -> void:
	for id: int in [0, 5, -1]:
		_lines.clear()
		GameState.highest_unlocked_level = 1
		GameState.energy = 30
		GameState.current_level_id = "dev"
		SceneRouter.complete_level(id)
		assert_eq(_calls, [] as Array[String], "id %d: no scene change" % id)
		assert_false(FileAccess.file_exists(TEST_SAVE), "id %d: no save" % id)
		assert_eq(GameState.highest_unlocked_level, 1, "id %d: no unlock" % id)
		assert_eq(GameState.current_level_id, "dev", "id %d: level id untouched" % id)
		assert_eq(GameState.energy, 30, "id %d: energy untouched" % id)
		assert_has(_lines, "[INFO][scene] Level %d cleared: not a campaign level; no save, no scene change" % id)


func test_complete_level_moves_on_even_if_the_save_fails() -> void:
	SaveManager.save_path = "user://test_scene_router_missing_dir/save.cfg"
	GameState.energy = 10
	SceneRouter.complete_level(1)
	assert_push_error("[ERROR][save]")
	assert_eq(GameState.highest_unlocked_level, 2)
	assert_eq(_calls, [SceneRouter.LEVEL_SCENE_PATH] as Array[String], "level 2 still starts")
	assert_eq(GameState.current_level_id, "2")


func test_title_start_and_restart_write_no_save() -> void:
	GameState.highest_unlocked_level = 2
	GameState.energy = 40
	SceneRouter.start_level("2")
	SceneRouter.restart_level()
	SceneRouter.goto_title()
	assert_eq(_calls.size(), 3, "three scene changes")
	assert_false(FileAccess.file_exists(TEST_SAVE), "no save file written")


# --- Story 5.5: the opening story ------------------------------------------------------

func _count_starting(prefix: String) -> int:
	var n: int = 0
	for line: String in _lines:
		if line.begins_with(prefix):
			n += 1
	return n


func test_story_scene_path_and_opening_constants() -> void:
	assert_eq(SceneRouter.STORY_SCENE_PATH, "res://scenes/story/story.tscn")
	assert_true(ResourceLoader.exists(SceneRouter.STORY_SCENE_PATH))
	assert_eq(SceneRouter.OPENING_SEQUENCE, &"opening_main")
	assert_eq(SceneRouter.OPENING_LEVEL_ID, "1")


func test_nothing_pending_at_start() -> void:
	assert_eq(SceneRouter.story_sequence(), &"")
	assert_eq(SceneRouter.story_next_level(), 0)


func test_start_level_1_plays_the_opening_first() -> void:
	GameState.energy = 40
	GameState.is_retry = true
	GameState.current_level_id = ""
	PauseArbiter.push(&"menu")
	Feedback.hit_stop(500.0)
	SceneRouter.start_level("1")
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH] as Array[String], "one change to the story scene")
	assert_eq(SceneRouter.story_sequence(), &"opening_main", "pending opening")
	assert_eq(SceneRouter.story_next_level(), 1, "then level 1")
	assert_false(GameState.is_retry, "a fresh attempt")
	assert_eq(GameState.energy, 40, "energy kept")
	assert_false(PauseArbiter.is_paused(), "pause reasons cleared")
	assert_eq(Engine.time_scale, 1.0, "hit-stop ended")
	assert_eq(_scene_lines(), ["[INFO][scene] Story 'opening_main' before level 1"] as Array[String], "one INFO scene line")


func test_start_other_levels_skip_the_opening() -> void:
	for id: String in ["2", "3", "dev"]:
		_calls.clear()
		SceneRouter.start_level(id)
		assert_eq(_calls, [SceneRouter.LEVEL_SCENE_PATH] as Array[String], "level '%s' loads at once" % id)
		assert_eq(GameState.current_level_id, id)
		assert_eq(SceneRouter.story_sequence(), &"", "no story pending for '%s'" % id)


func test_goto_story_stores_the_pending_story() -> void:
	GameState.is_retry = true
	GameState.energy = 15
	GameState.current_level_id = "x"
	SceneRouter.goto_story(&"some_story", 3)
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH] as Array[String])
	assert_eq(SceneRouter.story_sequence(), &"some_story")
	assert_eq(SceneRouter.story_next_level(), 3)
	assert_false(GameState.is_retry, "retry flag cleared")
	assert_eq(GameState.energy, 15, "energy kept")
	assert_eq(GameState.current_level_id, "x", "level id untouched until the level loads")
	assert_has(_lines, "[INFO][scene] Story 'some_story' before level 3")


func test_goto_story_clears_the_pauses_after_the_swap() -> void:
	PauseArbiter.push(&"menu")
	SceneRouter.goto_story(&"opening_main", 1)
	assert_eq(_order, ["change paused=true", "resumed"] as Array[String], "paused at the call, resumed once after it")
	assert_false(PauseArbiter.is_paused())


func test_finish_story_starts_the_pending_level_once() -> void:
	GameState.energy = 25
	SceneRouter.start_level("1")
	GameState.is_retry = true
	SceneRouter.finish_story()
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH, SceneRouter.LEVEL_SCENE_PATH] as Array[String], "story, then the level, no second story")
	assert_eq(GameState.current_level_id, "1")
	assert_false(GameState.is_retry, "a fresh attempt")
	assert_eq(GameState.energy, 25, "energy kept")
	assert_eq(SceneRouter.story_sequence(), &"", "pending story cleared")
	assert_eq(SceneRouter.story_next_level(), 0)
	assert_eq(_scene_lines().back(), "[INFO][scene] Starting level '1'")


func test_finish_story_with_nothing_pending_goes_to_the_title() -> void:
	SceneRouter.finish_story()
	assert_eq(_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String], "the title")
	assert_eq(_count_starting("[WARN][scene] No pending story"), 1, "one WARN")
	assert_push_warning("No pending story")


func test_second_finish_story_goes_to_the_title() -> void:
	SceneRouter.goto_story(&"opening_main", 1)
	SceneRouter.finish_story()
	SceneRouter.finish_story()
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH, SceneRouter.LEVEL_SCENE_PATH, SceneRouter.TITLE_SCENE_PATH] as Array[String])
	assert_push_warning("No pending story")


func test_restart_level_1_never_plays_the_opening() -> void:
	GameState.current_level_id = "1"
	SceneRouter.restart_level()
	assert_eq(_calls, [SceneRouter.LEVEL_SCENE_PATH] as Array[String], "level.tscn, never the story")
	assert_eq(SceneRouter.story_sequence(), &"")
	assert_true(GameState.is_retry)


func test_goto_story_with_a_config_error_changes_nothing() -> void:
	var saved_error: String = Config.load_error
	Config.load_error = "res://data/tuning.json parse error at line 1: test"
	GameState.is_retry = true
	SceneRouter.goto_story(&"opening_main", 1)
	Config.load_error = saved_error
	assert_eq(_calls, [] as Array[String], "no scene change")
	assert_eq(SceneRouter.story_sequence(), &"", "nothing pending")
	assert_true(GameState.is_retry, "is_retry untouched")
	assert_eq(_count_starting("[ERROR][scene] Cannot play story 'opening_main'"), 1, "one ERROR scene line")
	assert_push_error("Cannot play story 'opening_main'")


func test_start_level_1_with_a_config_error_plays_no_story() -> void:
	var saved_error: String = Config.load_error
	Config.load_error = "res://data/tuning.json parse error at line 1: test"
	SceneRouter.start_level("1")
	Config.load_error = saved_error
	assert_eq(_calls, [] as Array[String], "no scene change")
	assert_eq(SceneRouter.story_sequence(), &"", "nothing pending")
	assert_push_error("Cannot start level '1'")
