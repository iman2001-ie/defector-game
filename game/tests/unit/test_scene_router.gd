extends GutTest
## SceneRouter (Stories 3.2, 4.1): retry_level(), restart_level(), goto_title()
## and start_level(id) set GameState, clear every pause reason, end hit-stop and
## change the scene through the injectable change_scene (a recorder here: the
## real one would replace the test runner's scene). start_level refuses while
## Config.load_error is set. Story 4.2: goto_title() restores the unlock from
## the save (clamped) and zeroes the energy, complete_level(n) unlocks, saves
## (the unlock only, never the energy) and moves on with the carried energy,
## and nothing else writes the save; an older save's energy key is ignored.
## Story 4.3: goto_level_select() changes to the Level Select screen and leaves
## GameState and the save alone. The save is a test file here. Playtest
## 2026-10-13: start_new(id) (title PLAY, Level Select) zeroes the energy and
## starts the level; every level load records GameState.level_start_energy; a
## death's retry_level() reloads with 0 energy and the pause menu's
## restart_level() with the attempt's start energy. Story 5.5: start_level("1") goes through the opening
## story scene (goto_story), finish_story() starts the pending level without the
## opening check, and a retry never plays it. Story 7.7: complete_level of the
## last level saves and goes to the end screen through goto_end(), which clears
## the level id and the retry flag and keeps the energy and the Final Choice.
## Story 7.8: with the council_epilogue flag on (and a healthy config) the last
## level's complete_level saves and then plays ending_council through
## goto_story(ENDING_SEQUENCE, STORY_NEXT_END); finish_story() with that target
## goes to the end screen. With the flag off it goes to the end screen at once.
## Every last-level row sets the flag explicitly; after_each restores it.
## Story 8.1 (DW-100): complete_level of the last level stops the music (a fade
## over audio.music_fade_out_s) before either branch, so the boss track never
## reaches the epilogue or the end screen; earlier clears leave it alone.

const TEST_SAVE: String = "user://test_scene_router_save.cfg"

var _calls: Array[String] = []
var _lines: Array[String] = []
## DW-61 ordering: "change paused=<bool>" at each change_scene call and
## "resumed" for each PauseArbiter.resumed, in the order they happened.
var _order: Array[String] = []
## The shipped council_epilogue value, restored by after_each.
var _saved_epilogue: Variant = null


func before_each() -> void:
	_saved_epilogue = Config.flags.get("council_epilogue")
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
	GameState.level_start_energy = 0
	GameState.current_level_id = ""
	GameState.is_retry = false
	GameState.highest_unlocked_level = 1
	GameState.all_levels_unlocked = false
	GameState.final_choice = &""
	Feedback.reset()
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Audio.stop_music(0.0)
	if _saved_epilogue == null:
		Config.flags.erase("council_epilogue")
	else:
		Config.flags["council_epilogue"] = _saved_epilogue


func _delete_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)


## A save fixture. A non-negative `old_energy` adds the `energy` key an older
## save (before playtest 2026-10-13) carried; it must be ignored.
func _write_save(highest: int, old_energy: int = -1) -> void:
	var file: ConfigFile = ConfigFile.new()
	file.set_value("progress", "save_version", 1)
	file.set_value("progress", "highest_unlocked_level", highest)
	if old_energy >= 0:
		file.set_value("progress", "energy", old_energy)
	assert_eq(file.save(TEST_SAVE), OK, "fixture save written")


## [save_version, highest_unlocked_level] read straight from the test file.
func _read_save() -> Array:
	var file: ConfigFile = ConfigFile.new()
	if file.load(TEST_SAVE) != OK:
		return []
	return [
		file.get_value("progress", "save_version"),
		file.get_value("progress", "highest_unlocked_level"),
	]


## The keys in the test file's [progress] section ([] when there is no file).
func _save_keys() -> PackedStringArray:
	var file: ConfigFile = ConfigFile.new()
	if file.load(TEST_SAVE) != OK:
		return PackedStringArray()
	return file.get_section_keys("progress")


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


func test_retry_level_resets_and_reloads() -> void:
	GameState.energy = 70
	GameState.level_start_energy = 40
	GameState.current_level_id = "dev"
	GameState.is_retry = false
	PauseArbiter.push(&"death")
	Feedback.hit_stop(500.0)
	SceneRouter.retry_level()
	assert_eq(GameState.energy, 0, "energy wiped")
	assert_eq(GameState.level_start_energy, 0, "the new attempt starts at 0")
	assert_true(GameState.is_retry, "marked as a retry")
	assert_eq(GameState.current_level_id, "dev", "same level id")
	assert_false(PauseArbiter.is_paused(), "pause reasons cleared")
	assert_eq(PauseArbiter.reasons(), [] as Array[StringName])
	assert_eq(Engine.time_scale, 1.0, "hit-stop ended")
	assert_false(Feedback.is_hit_stopped())
	assert_eq(_calls, ["res://scenes/level/level.tscn"] as Array[String], "one scene change")
	assert_eq(_scene_lines().size(), 1, "one INFO scene line")


func test_many_retries_and_restarts_have_no_limit() -> void:
	for i: int in 25:
		SceneRouter.retry_level()
		SceneRouter.restart_level()
	assert_eq(_calls.size(), 50, "every retry and restart reloads")
	for path: String in _calls:
		assert_eq(path, SceneRouter.LEVEL_SCENE_PATH)
	assert_true(GameState.is_retry)


## DW-61: the pauses are still held at the swap call and dropped right after it,
## so `resumed` fires once, after the outgoing scene left the tree.
func test_retry_level_clears_the_pauses_after_the_swap() -> void:
	GameState.current_level_id = "dev"
	PauseArbiter.push(&"death")
	SceneRouter.retry_level()
	assert_eq(_order, ["change paused=true", "resumed"] as Array[String], "paused at the call, resumed once after it")
	assert_false(PauseArbiter.is_paused(), "unpaused afterwards")
	assert_false(get_tree().paused)


func test_restart_level_clears_the_pauses_after_the_swap() -> void:
	GameState.current_level_id = "dev"
	PauseArbiter.push(&"menu")
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
	_write_save(1)
	GameState.energy = 30
	GameState.is_retry = true
	GameState.current_level_id = "dev"
	PauseArbiter.push(&"death")
	Feedback.hit_stop(500.0)
	SceneRouter.goto_title()
	assert_eq(GameState.energy, 0, "energy zeroed (never saved)")
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
	_write_save(1)
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
	assert_eq(_read_save(), [1, 1], "save untouched")


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

func test_goto_title_restores_the_saved_unlock_and_zeroes_the_energy() -> void:
	_write_save(2)
	GameState.energy = 70
	GameState.highest_unlocked_level = 3
	GameState.all_levels_unlocked = true
	SceneRouter.goto_title()
	assert_eq(GameState.energy, 0, "energy 0, not the in-memory 70 (F13)")
	assert_eq(GameState.highest_unlocked_level, 2, "saved unlock")
	assert_true(GameState.all_levels_unlocked, "the F7 flag survives goto_title")
	assert_eq(_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String])
	assert_eq(_read_save(), [1, 2], "the save is unchanged")


## An older save still holding an `energy` key: the unlock loads, the old
## energy is ignored and the file is not rewritten.
func test_goto_title_ignores_an_old_saved_energy() -> void:
	_write_save(2, 60)
	GameState.energy = 70
	SceneRouter.goto_title()
	assert_eq(GameState.energy, 0, "the old saved energy is ignored")
	assert_eq(GameState.highest_unlocked_level, 2, "saved unlock")
	assert_eq(_save_keys(), PackedStringArray(["save_version", "highest_unlocked_level", "energy"]), "the old file is not rewritten")


func test_goto_title_clamps_the_saved_unlock() -> void:
	_write_save(9)
	GameState.energy = 50
	SceneRouter.goto_title()
	assert_eq(GameState.highest_unlocked_level, 3, "clamped to progression.level_count")
	assert_eq(GameState.energy, 0, "energy 0")


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
	_write_save(2)
	GameState.energy = 20
	SceneRouter.goto_title()
	Config.load_error = saved_error
	assert_eq(GameState.highest_unlocked_level, 2)
	assert_eq(GameState.energy, 0)
	assert_eq(_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String])


## DW-61: the restore goto_title() does, on its own (F5 calls it): no scene
## change, no level-id change, no save written.
func test_restore_saved_progress_restores_and_clears_the_retry() -> void:
	_write_save(2)
	GameState.energy = 40
	GameState.highest_unlocked_level = 1
	GameState.is_retry = true
	GameState.current_level_id = "2"
	SceneRouter.restore_saved_progress()
	assert_eq(GameState.energy, 0, "energy zeroed")
	assert_eq(GameState.highest_unlocked_level, 2, "saved unlock")
	assert_false(GameState.is_retry, "retry flag cleared")
	assert_eq(GameState.current_level_id, "2", "level id untouched")
	assert_eq(_calls, [] as Array[String], "no scene change")
	assert_eq(_read_save(), [1, 2], "the save is unchanged")


func test_restore_saved_progress_clamps() -> void:
	_write_save(9, 500)
	SceneRouter.restore_saved_progress()
	assert_eq(GameState.highest_unlocked_level, 3, "clamped to progression.level_count")
	assert_eq(GameState.energy, 0, "an old saved energy is ignored")


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
	assert_eq(_read_save(), [1, 2], "save written with the unlock")
	assert_eq(_save_keys(), PackedStringArray(["save_version", "highest_unlocked_level"]), "no energy saved")
	assert_eq(_calls, [SceneRouter.LEVEL_SCENE_PATH] as Array[String], "one change to the level")
	assert_eq(GameState.current_level_id, "2", "level 2 starts")
	assert_eq(GameState.energy, 35, "energy carried")
	assert_false(GameState.is_retry)


func test_complete_level_1_again_keeps_the_higher_unlock() -> void:
	GameState.highest_unlocked_level = 3
	GameState.energy = 50
	SceneRouter.complete_level(1)
	assert_eq(GameState.highest_unlocked_level, 3, "never lowered")
	assert_eq(_read_save(), [1, 3])
	assert_eq(_calls, [SceneRouter.LEVEL_SCENE_PATH] as Array[String])
	assert_eq(GameState.current_level_id, "2")


## Story 7.7: with the council epilogue off, the last level saves, then goes
## to the end screen (goto_end()) with no story pending.
func test_complete_last_level_saves_and_goes_to_the_end_screen() -> void:
	Config.flags["council_epilogue"] = false
	GameState.highest_unlocked_level = 3
	GameState.energy = 80
	GameState.current_level_id = "3"
	GameState.final_choice = &"destroy"
	SceneRouter.complete_level(3)
	assert_eq(_read_save(), [1, 3], "save written")
	assert_eq(_calls, [SceneRouter.END_SCENE_PATH] as Array[String], "one change to the end screen")
	assert_eq(GameState.highest_unlocked_level, 3, "level 3 is the highest")
	assert_eq(GameState.energy, 80, "energy kept")
	assert_eq(GameState.current_level_id, "", "no level id")
	assert_false(GameState.is_retry, "not a retry")
	assert_eq(GameState.final_choice, &"destroy", "the Final Choice kept for Story 7.8")
	assert_eq(_scene_lines(), ["[INFO][scene] Going to the end screen"] as Array[String], "one INFO scene line")
	assert_eq(SceneRouter.story_sequence(), &"", "no story pending")
	assert_eq(SceneRouter.story_next_level(), 0)


func test_complete_last_level_goes_to_the_end_screen_even_if_the_save_fails() -> void:
	Config.flags["council_epilogue"] = false
	SaveManager.save_path = "user://test_scene_router_missing_dir/save.cfg"
	GameState.highest_unlocked_level = 3
	GameState.energy = 80
	GameState.current_level_id = "3"
	SceneRouter.complete_level(3)
	assert_push_error("[ERROR][save]")
	assert_eq(_calls, [SceneRouter.END_SCENE_PATH] as Array[String], "the end screen still opens")
	assert_eq(GameState.energy, 80, "energy kept")
	assert_eq(GameState.current_level_id, "")


# --- Story 7.7: the end screen -----------------------------------------------------------

func test_end_scene_path() -> void:
	assert_eq(SceneRouter.END_SCENE_PATH, "res://scenes/end/end_screen.tscn")
	assert_true(ResourceLoader.exists(SceneRouter.END_SCENE_PATH))


func test_goto_end_clears_the_level_and_keeps_energy_and_choice() -> void:
	_write_save(1)
	GameState.energy = 60
	GameState.highest_unlocked_level = 3
	GameState.current_level_id = "3"
	GameState.is_retry = true
	GameState.final_choice = &"surrender"
	PauseArbiter.push(&"story")
	Feedback.hit_stop(500.0)
	SceneRouter.goto_end()
	assert_eq(_calls, [SceneRouter.END_SCENE_PATH] as Array[String], "one change to the end screen")
	assert_eq(GameState.current_level_id, "", "level id cleared")
	assert_false(GameState.is_retry, "retry flag cleared")
	assert_eq(GameState.energy, 60, "energy kept (not restored from the save)")
	assert_eq(GameState.highest_unlocked_level, 3, "unlock untouched")
	assert_eq(GameState.final_choice, &"surrender", "the Final Choice kept")
	assert_false(PauseArbiter.is_paused(), "pause reasons cleared")
	assert_eq(PauseArbiter.reasons(), [] as Array[StringName])
	assert_eq(Engine.time_scale, 1.0, "hit-stop ended")
	assert_eq(_scene_lines(), ["[INFO][scene] Going to the end screen"] as Array[String], "one INFO scene line")
	assert_eq(_read_save(), [1, 1], "goto_end writes no save")


func test_goto_end_clears_the_pauses_after_the_swap() -> void:
	PauseArbiter.push(&"story")
	SceneRouter.goto_end()
	assert_eq(_order, ["change paused=true", "resumed"] as Array[String], "paused at the call, resumed once after it")
	assert_false(PauseArbiter.is_paused(), "unpaused afterwards")


func test_f7_flag_never_leaks_into_the_save() -> void:
	GameState.all_levels_unlocked = true
	GameState.highest_unlocked_level = 1
	GameState.energy = 10
	SceneRouter.complete_level(1)
	assert_eq(_read_save(), [1, 2], "the save holds the real unlock (2), not the debug one")
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


func test_title_start_retry_and_restart_write_no_save() -> void:
	GameState.highest_unlocked_level = 2
	GameState.energy = 40
	SceneRouter.start_level("2")
	SceneRouter.start_new("2")
	SceneRouter.retry_level()
	SceneRouter.restart_level()
	SceneRouter.goto_title()
	assert_eq(_calls.size(), 5, "five scene changes")
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


func test_retry_and_restart_of_level_1_never_play_the_opening() -> void:
	GameState.current_level_id = "1"
	SceneRouter.retry_level()
	SceneRouter.restart_level()
	assert_eq(_calls, [SceneRouter.LEVEL_SCENE_PATH, SceneRouter.LEVEL_SCENE_PATH] as Array[String], "level.tscn, never the story")
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


# --- Story 7.8: the council epilogue ----------------------------------------------------

func test_ending_constants() -> void:
	assert_eq(SceneRouter.ENDING_SEQUENCE, &"ending_council")
	assert_eq(SceneRouter.STORY_NEXT_END, -1)
	assert_true(Config.dialogue_is_story(SceneRouter.ENDING_SEQUENCE), "ending_council is a loaded story sequence")


## Flag on: the save first, then one change to the story scene with
## ending_council pending before the end screen; energy and choice kept.
func test_complete_last_level_with_the_epilogue_plays_ending_council() -> void:
	Config.flags["council_epilogue"] = true
	GameState.highest_unlocked_level = 3
	GameState.energy = 80
	GameState.current_level_id = "3"
	GameState.final_choice = &"destroy"
	SceneRouter.complete_level(3)
	assert_eq(_read_save(), [1, 3], "save written")
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH] as Array[String], "one change to the story scene")
	assert_eq(SceneRouter.story_sequence(), &"ending_council", "the epilogue pending")
	assert_eq(SceneRouter.story_next_level(), SceneRouter.STORY_NEXT_END, "then the end screen")
	assert_eq(GameState.energy, 80, "energy kept")
	assert_eq(GameState.final_choice, &"destroy", "the Final Choice kept")
	assert_false(GameState.is_retry, "not a retry")
	assert_eq(_scene_lines(), ["[INFO][scene] Story 'ending_council' before the end screen"] as Array[String], "one INFO scene line")


## The save is already on disk when the story scene change is requested.
func test_complete_last_level_with_the_epilogue_saves_before_the_change() -> void:
	Config.flags["council_epilogue"] = true
	GameState.energy = 42
	SceneRouter.change_scene = _record_with_save
	SceneRouter.complete_level(3)
	assert_eq(_calls, ["%s saved=%s" % [SceneRouter.STORY_SCENE_PATH, str([1, 3])]] as Array[String], "saved before the story scene")


func _record_with_save(path: String) -> Error:
	_calls.append("%s saved=%s" % [path, str(_read_save())])
	return OK


func test_complete_last_level_with_the_epilogue_moves_on_even_if_the_save_fails() -> void:
	Config.flags["council_epilogue"] = true
	SaveManager.save_path = "user://test_scene_router_missing_dir/save.cfg"
	GameState.energy = 80
	SceneRouter.complete_level(3)
	assert_push_error("[ERROR][save]")
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH] as Array[String], "the story scene still opens")
	assert_eq(SceneRouter.story_sequence(), &"ending_council")
	assert_eq(SceneRouter.story_next_level(), SceneRouter.STORY_NEXT_END)
	assert_eq(GameState.energy, 80, "energy kept")


## A broken config would make goto_story refuse, so the last level goes to the
## end screen directly and never logs a refused story.
func test_complete_last_level_with_a_config_error_goes_to_the_end_screen() -> void:
	Config.flags["council_epilogue"] = true
	GameState.energy = 80
	GameState.highest_unlocked_level = 3
	var saved_error: String = Config.load_error
	Config.load_error = "res://data/tuning.json parse error at line 1: test"
	SceneRouter.complete_level(3)
	Config.load_error = saved_error
	assert_eq(_read_save(), [1, 3], "the save still written")
	assert_has(_scene_lines(), "[INFO][scene] Going to the end screen", "the end-screen INFO line")
	assert_eq(_calls, [SceneRouter.END_SCENE_PATH] as Array[String], "one change to the end screen")
	assert_eq(SceneRouter.story_sequence(), &"", "no story pending")
	assert_eq(_count_starting("[ERROR][scene] Cannot play story"), 0, "never a refused story")


## Levels below the last are unchanged by the flag.
func test_epilogue_flag_does_not_change_levels_below_the_last() -> void:
	Config.flags["council_epilogue"] = true
	SceneRouter.complete_level(2)
	assert_eq(_calls, [SceneRouter.LEVEL_SCENE_PATH] as Array[String], "level 3 starts")
	assert_eq(GameState.current_level_id, "3")
	assert_eq(SceneRouter.story_sequence(), &"")


func test_goto_story_before_the_end_stores_the_target_and_logs() -> void:
	GameState.is_retry = true
	GameState.energy = 15
	GameState.current_level_id = "3"
	SceneRouter.goto_story(&"some_story", SceneRouter.STORY_NEXT_END)
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH] as Array[String])
	assert_eq(SceneRouter.story_sequence(), &"some_story")
	assert_eq(SceneRouter.story_next_level(), SceneRouter.STORY_NEXT_END)
	assert_false(GameState.is_retry, "retry flag cleared")
	assert_eq(GameState.energy, 15, "energy kept")
	assert_eq(_scene_lines(), ["[INFO][scene] Story 'some_story' before the end screen"] as Array[String])


func test_goto_story_before_the_end_with_a_config_error_changes_nothing() -> void:
	var saved_error: String = Config.load_error
	Config.load_error = "res://data/tuning.json parse error at line 1: test"
	SceneRouter.goto_story(SceneRouter.ENDING_SEQUENCE, SceneRouter.STORY_NEXT_END)
	Config.load_error = saved_error
	assert_eq(_calls, [] as Array[String], "no scene change")
	assert_eq(SceneRouter.story_sequence(), &"", "nothing pending")
	assert_push_error("Cannot play story 'ending_council'")


## finish_story() with the end pending clears it and calls goto_end() once,
## writing no save; a second finish has nothing pending and goes to the title
## as before.
func test_finish_story_before_the_end_goes_to_the_end_screen_once() -> void:
	Config.flags["council_epilogue"] = true
	GameState.energy = 80
	GameState.current_level_id = "3"
	GameState.final_choice = &"surrender"
	SceneRouter.complete_level(3)
	_delete_save()
	SceneRouter.finish_story()
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH, SceneRouter.END_SCENE_PATH] as Array[String], "story, then the end screen")
	assert_eq(SceneRouter.story_sequence(), &"", "pending story cleared")
	assert_eq(SceneRouter.story_next_level(), 0)
	assert_eq(GameState.current_level_id, "", "no level id")
	assert_false(GameState.is_retry)
	assert_eq(GameState.energy, 80, "energy kept")
	assert_eq(GameState.final_choice, &"surrender", "the Final Choice kept")
	assert_eq(_scene_lines().back(), "[INFO][scene] Going to the end screen")
	assert_false(FileAccess.file_exists(TEST_SAVE), "nothing saves after the epilogue")
	SceneRouter.finish_story()
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH, SceneRouter.END_SCENE_PATH, SceneRouter.TITLE_SCENE_PATH] as Array[String], "a second finish goes to the title")
	assert_push_warning("No pending story")


# --- Playtest 2026-10-13: menu starts, retry and restart energy ---------------------------

func test_start_new_zeroes_the_energy_and_starts_the_level() -> void:
	GameState.energy = 60
	GameState.level_start_energy = 60
	GameState.is_retry = true
	PauseArbiter.push(&"menu")
	SceneRouter.start_new("2")
	assert_eq(GameState.energy, 0, "a new run starts at 0")
	assert_eq(GameState.level_start_energy, 0, "and records 0 as the start energy")
	assert_eq(GameState.current_level_id, "2")
	assert_false(GameState.is_retry, "a fresh attempt")
	assert_false(PauseArbiter.is_paused(), "pause reasons cleared")
	assert_eq(_calls, [SceneRouter.LEVEL_SCENE_PATH] as Array[String], "one change to the level")
	assert_eq(_scene_lines(), ["[INFO][scene] Starting level '2'"] as Array[String])
	assert_false(FileAccess.file_exists(TEST_SAVE), "no save written")


func test_start_new_level_1_plays_the_opening_with_0_energy() -> void:
	GameState.energy = 60
	GameState.highest_unlocked_level = 3
	SceneRouter.start_new("1")
	assert_eq(GameState.energy, 0)
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH] as Array[String], "the opening first")
	assert_eq(SceneRouter.story_sequence(), &"opening_main")
	assert_eq(SceneRouter.story_next_level(), 1)
	SceneRouter.finish_story()
	assert_eq(GameState.current_level_id, "1")
	assert_eq(GameState.energy, 0, "level 1 starts at 0")
	assert_eq(GameState.level_start_energy, 0)


## start_new refuses like start_level under a config error; the energy is
## still zeroed (it is never saved).
func test_start_new_with_a_config_error_zeroes_the_energy_and_changes_nothing_else() -> void:
	var saved_error: String = Config.load_error
	Config.load_error = "res://data/tuning.json parse error at line 1: test"
	GameState.energy = 30
	GameState.current_level_id = "dev"
	SceneRouter.start_new("2")
	Config.load_error = saved_error
	assert_eq(_calls, [] as Array[String], "no scene change")
	assert_eq(GameState.energy, 0, "energy zeroed")
	assert_eq(GameState.current_level_id, "dev", "level id untouched")
	assert_push_error("Cannot start level '2'")


func test_load_level_records_the_start_energy() -> void:
	GameState.energy = 40
	GameState.level_start_energy = 0
	SceneRouter.start_level("2")
	assert_eq(GameState.level_start_energy, 40, "start_level records the carried energy")
	GameState.energy = 25
	SceneRouter.goto_story(&"opening_main", 1)
	assert_eq(GameState.level_start_energy, 40, "a story alone records nothing")
	SceneRouter.finish_story()
	assert_eq(GameState.level_start_energy, 25, "finish_story's level load records it")


func test_retry_level_gives_0_energy() -> void:
	GameState.energy = 40
	SceneRouter.start_level("2")
	GameState.energy = 80
	SceneRouter.retry_level()
	assert_eq(GameState.energy, 0, "a death's retry starts at 0")
	assert_eq(GameState.level_start_energy, 0)
	assert_true(GameState.is_retry)
	assert_eq(GameState.current_level_id, "2", "same level")
	assert_eq(_scene_lines().back(), "[INFO][scene] Retry: reloading level '2'")


func test_restart_level_gives_back_the_start_energy() -> void:
	GameState.energy = 40
	SceneRouter.start_level("2")
	GameState.energy = 80
	PauseArbiter.push(&"menu")
	Feedback.hit_stop(500.0)
	SceneRouter.restart_level()
	assert_eq(GameState.energy, 40, "back to what the attempt started with, not 80")
	assert_eq(GameState.level_start_energy, 40, "the new attempt starts with it too")
	assert_true(GameState.is_retry, "marked as a retry")
	assert_eq(GameState.current_level_id, "2", "same level")
	assert_false(PauseArbiter.is_paused(), "pause reasons cleared")
	assert_eq(Engine.time_scale, 1.0, "hit-stop ended")
	assert_eq(_calls, [SceneRouter.LEVEL_SCENE_PATH, SceneRouter.LEVEL_SCENE_PATH] as Array[String])
	assert_eq(_scene_lines().back(), "[INFO][scene] Restart: reloading level '2'")


func test_restart_level_twice_keeps_the_start_energy() -> void:
	GameState.energy = 40
	SceneRouter.start_level("2")
	GameState.energy = 80
	SceneRouter.restart_level()
	GameState.energy = 10
	SceneRouter.restart_level()
	assert_eq(GameState.energy, 40, "still the original start energy")


func test_restart_after_a_retry_gives_0() -> void:
	GameState.energy = 40
	SceneRouter.start_level("2")
	GameState.energy = 70
	SceneRouter.retry_level()
	GameState.energy = 30
	SceneRouter.restart_level()
	assert_eq(GameState.energy, 0, "the retried attempt started at 0")
	assert_eq(GameState.level_start_energy, 0)


func test_level_clear_carries_the_energy_and_records_it_as_the_start() -> void:
	GameState.energy = 20
	SceneRouter.start_level("2")
	GameState.energy = 65
	SceneRouter.complete_level(2)
	assert_eq(GameState.current_level_id, "3")
	assert_eq(GameState.energy, 65, "the energy carries into the next level")
	assert_eq(GameState.level_start_energy, 65, "and is the next level's start energy")
	GameState.energy = 90
	SceneRouter.restart_level()
	assert_eq(GameState.energy, 65, "a restart of level 3 gives back the carried energy")


# --- Story 8.1: the music stops on the last clear (DW-100) ---------------------------

## Asserts the music was playing `id`, is now cleared at once and is fading out
## over audio.music_fade_out_s (one stopping line); after_each ends the fade.
func _assert_music_fading_out(id: StringName) -> void:
	assert_eq(Audio.current_music(), &"", "current_music() cleared at once")
	assert_true(Audio.music_player().playing, "the track is still audible while it fades")
	assert_true(Audio._is_fading(), "fading out")
	var fade: float = Config.num("audio.music_fade_out_s")
	assert_eq(_count_starting("[INFO][audio] Music '%s' stopping (%.2f s fade)" % [id, fade]), 1, "one fade over audio.music_fade_out_s")


func test_last_clear_with_the_epilogue_stops_the_music() -> void:
	Config.flags["council_epilogue"] = true
	Audio.play_music(&"boss")
	assert_eq(Audio.current_music(), &"boss", "the shipped boss track plays")
	SceneRouter.complete_level(3)
	_assert_music_fading_out(&"boss")
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH] as Array[String], "then the epilogue")


func test_last_clear_without_the_epilogue_stops_the_music() -> void:
	Config.flags["council_epilogue"] = false
	Audio.play_music(&"level_1")
	SceneRouter.complete_level(3)
	_assert_music_fading_out(&"level_1")
	assert_eq(_calls, [SceneRouter.END_SCENE_PATH] as Array[String], "then the end screen")


func test_last_clear_with_a_config_error_stops_the_music() -> void:
	Config.flags["council_epilogue"] = true
	Audio.play_music(&"boss")
	var saved_error: String = Config.load_error
	Config.load_error = "res://data/tuning.json parse error at line 1: test"
	SceneRouter.complete_level(3)
	Config.load_error = saved_error
	_assert_music_fading_out(&"boss")
	assert_eq(_calls, [SceneRouter.END_SCENE_PATH] as Array[String], "then the end screen")


## The stop comes before the scene change: the change already sees silence.
func test_last_clear_stops_the_music_before_the_scene_change() -> void:
	Config.flags["council_epilogue"] = false
	Audio.play_music(&"boss")
	SceneRouter.change_scene = _record_with_music
	SceneRouter.complete_level(3)
	assert_eq(_calls, ["%s music=''" % SceneRouter.END_SCENE_PATH] as Array[String], "silent at the change")


func _record_with_music(path: String) -> Error:
	_calls.append("%s music='%s'" % [path, Audio.current_music()])
	return OK


func test_earlier_clear_leaves_the_music_alone() -> void:
	Audio.play_music(&"level_1")
	SceneRouter.complete_level(1)
	assert_eq(Audio.current_music(), &"level_1", "the level track keeps playing")
	assert_false(Audio._is_fading(), "no fade")
	assert_eq(_count_starting("[INFO][audio] Music 'level_1' stopping"), 0, "no stopping line")
	assert_eq(_calls, [SceneRouter.LEVEL_SCENE_PATH] as Array[String], "level 2 starts")


func test_last_clear_in_silence_is_quiet() -> void:
	Config.flags["council_epilogue"] = true
	Audio.stop_music(0.0)
	SceneRouter.complete_level(3)
	assert_eq(Audio.current_music(), &"", "still silent")
	assert_false(Audio.music_player().playing, "nothing plays")
	assert_eq(_count_starting("[INFO][audio] Music"), 0, "no music line")
	assert_eq(_count_starting("[ERROR]"), 0, "no error")
	assert_eq(_count_starting("[WARN]"), 0, "no warning")
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH] as Array[String], "the epilogue still plays")


## Playtest pt7-e: going to the title fades out any music (the end screen's
## epilogue track, or a level track after a quit); the title has no track.
func test_goto_title_fades_the_music_out() -> void:
	Audio.play_music(&"epilogue")
	SceneRouter.goto_title()
	_assert_music_fading_out(&"epilogue")
	assert_eq(_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String], "to the title")
