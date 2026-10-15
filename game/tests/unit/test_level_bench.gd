extends GutTest
## Story 8.3: the level bench (LevelBench, `-- --level-bench=<scenario>`) on the
## real level.tscn with Level 3. Real frames drive it to its target state
## (the briefing clicked through, the jump, the Flagship driven through the
## Final Choice); then its processing is stopped and step() gets fake times, so
## the settle, the sampling window, the PASS / FAIL rule and the early ends are
## deterministic. The bench numbers are shrunk through Config, the quit is a
## recorder, the cursor warp is a recorder, the save is a test file and the
## router's scene change is a recorder. Real frame times and the 60 FPS target
## are measured on a debug export (decision #67), not here.

const LEVEL_SCENE: PackedScene = preload("res://scenes/level/level.tscn")
const TEST_SAVE: String = "user://test_level_bench_save.cfg"
const USEC: int = 1000000
const SETTLE_S: float = 0.5
const SAMPLE_S: float = 1.0
const QUIT_DELAY_S: float = 0.2

var _level: Node2D
var _lines: Array[String] = []
var _quits: Array[int] = []
var _warps: Array[Vector2] = []
var _choices: Array[StringName] = []
var _scene_calls: Array[String] = []


func before_each() -> void:
	_lines.clear()
	_quits.clear()
	_warps.clear()
	_choices.clear()
	_scene_calls.clear()
	_level = null
	SaveManager.save_path = TEST_SAVE
	_delete_save()
	_reset_game_state()
	SceneRouter.change_scene = _record_scene
	Events.final_choice_made.connect(_on_final_choice_made)
	Log.sink = _capture


func after_each() -> void:
	Events.final_choice_made.disconnect(_on_final_choice_made)
	Log.sink = Callable()
	_level = null
	Input.action_release(&"fire_laser")
	SceneRouter.change_scene = SceneRouter.default_change_scene()
	_delete_save()
	SaveManager.save_path = SaveManager.DEFAULT_SAVE_PATH
	_reset_game_state()
	Config.load_data()
	Feedback.reset()
	Audio.stop_music(0.0)
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	PauseArbiter.clear()


func _reset_game_state() -> void:
	GameState.energy = 0
	GameState.current_level_id = ""
	GameState.is_retry = false
	GameState.shown_hints.clear()
	GameState.final_choice = &""


func _delete_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _record_scene(path: String) -> Error:
	_scene_calls.append(path)
	return OK


func _record_quit(code: int) -> void:
	_quits.append(code)


func _on_final_choice_made(id: StringName) -> void:
	_choices.append(id)


func _lines_containing(text: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.contains(text):
			out.append(line)
	return out


## The real level scene on `level_id` with `-- --level-bench=<scenario>`, a
## short wave gap, small bench numbers and recorders for the quit and the warp.
func _make_level(scenario: String, level_id: String = "3") -> Node2D:
	(Config.tuning["waves"] as Dictionary)["gap_s"] = 0.05
	var bench_cfg: Dictionary = Config.tuning["debug"]["level_bench"]
	bench_cfg["settle_s"] = SETTLE_S
	bench_cfg["sample_s"] = SAMPLE_S
	(Config.tuning["debug"]["bench"] as Dictionary)["quit_delay_s"] = QUIT_DELAY_S
	_level = LEVEL_SCENE.instantiate() as Node2D
	_level.set("level_id", level_id)
	_level.user_args = PackedStringArray(["--level-bench=" + scenario])
	_level.set("level_bench_quit", _record_quit)
	var player: Player = _level.get_node("World/Player") as Player
	player.warp_mouse = func(at: Vector2) -> void: _warps.append(at)
	add_child_autofree(_level)
	return _level


func _bench() -> LevelBench:
	return _level.get_node_or_null("Overlay/LevelBench") as LevelBench


func _director() -> WaveDirector:
	return _level.get_node("WaveDirector") as WaveDirector


func _channel() -> CommsChannel:
	return _level.get_node("Comms/CommsChannel") as CommsChannel


func _player() -> Player:
	return _level.get_node("World/Player") as Player


func _flagship() -> Flagship:
	for child: Node in _level.get_node("World/Enemies").get_children():
		var boss: Flagship = child as Flagship
		if boss != null and not boss.is_queued_for_deletion():
			return boss
	return null


## Real frames (the tree may be paused) until the bench reaches `stage` or
## `timeout_s` passes. Physics speeds the Flagship's arrival up once.
func _run_until(stage: LevelBench.Stage, timeout_s: float = 8.0) -> void:
	var end_ms: int = Time.get_ticks_msec() + int(timeout_s * 1000.0)
	var hurried: bool = false
	while _bench().stage() < stage and Time.get_ticks_msec() < end_ms:
		var boss: Flagship = _flagship()
		if not hurried and boss != null and boss.phase() == Flagship.Phase.ARRIVING:
			hurried = true
			boss.step(Config.num("boss.hull.arrival_s"))
		await wait_process_frames(1)
	assert_eq(_bench().stage(), stage, "the bench reached stage %s" % LevelBench.Stage.keys()[stage])


## The bench's processing stopped, so only the fake times below step it.
func _freeze(bench: LevelBench) -> int:
	bench.set_process(false)
	return bench._stage_start_usec


func _final_lines() -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines_containing("Level bench: scenario="):
		if line.contains("frames="):
			out.append(line)
	return out


# --- busiest_wave -----------------------------------------------------------------

func test_busiest_wave_jumps_to_wave_3_with_fire_held_then_settles_and_samples() -> void:
	_make_level("busiest_wave")
	var bench: LevelBench = _bench()
	assert_not_null(bench, "Overlay/LevelBench")
	if bench == null:
		return
	assert_eq(bench.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(bench.stage(), LevelBench.Stage.WAITING, "waits for wave 1")
	assert_true(_channel().is_showing(), "the briefing shows")
	assert_eq(_lines_containing("[INFO][debug] Level bench: scenario=busiest_wave starting").size(), 1, "one start line")
	await _run_until(LevelBench.Stage.SETTLING)
	assert_false(_channel().is_showing(), "the briefing was clicked through")
	assert_eq(_director().wave_number(), 3, "jumped to wave 3")
	assert_eq(_director().total_count(), 24, "wave 3's 24 counted")
	assert_true(_player().debug_invincible, "the player is invincible")
	assert_true(_warps.has(DebugTools.BENCH_AIM), "the cursor went to BENCH_AIM")
	assert_true(Input.is_action_pressed(&"fire_laser"), "fire held")
	assert_true(bench.is_fire_held())
	assert_eq(_lines_containing("[INFO][debug] Level bench: wave 3 reached (fire held)").size(), 1, "one phase-reached line")
	var t0: int = _freeze(bench)
	bench.step(t0 + int(SETTLE_S * USEC) - 1000, 5.0)
	assert_eq(bench.stage(), LevelBench.Stage.SETTLING, "still settling")
	assert_eq(bench.stats().count(), 0, "settle frames are not sampled")
	bench.step(t0 + int(SETTLE_S * USEC), 5.0)
	assert_eq(bench.stage(), LevelBench.Stage.SAMPLING, "sampling after settle_s")
	var s0: int = bench._stage_start_usec
	bench.step(s0 + 100000, 5.0)
	bench.step(s0 + 200000, 7.0)
	assert_eq(bench.stats().count(), 2, "two frames sampled")
	bench.step(s0 + int(SAMPLE_S * USEC), 6.0)
	assert_eq(bench.stage(), LevelBench.Stage.DONE, "done after sample_s")
	assert_eq(bench.ended(), "time")
	assert_eq(bench.exit_code(), 0, "PASS under every limit")
	assert_false(Input.is_action_pressed(&"fire_laser"), "fire released")
	var finals: Array[String] = _final_lines()
	assert_eq(finals.size(), 1, "one final line")
	if finals.size() == 1:
		assert_true(finals[0].begins_with("[INFO][debug] Level bench: scenario=busiest_wave frames=3 "), finals[0])
		for part: String in ["avg=6.00 ms", "p99=7.00 ms", "max=7.00 ms", "enemies=", "projectiles=", "ended=time", "renderer=", "window=", "vsync=", "result=PASS"]:
			assert_string_contains(finals[0], part)
		var enemies: RegExMatch = RegEx.create_from_string("enemies=([0-9]+)").search(finals[0])
		assert_not_null(enemies, "an enemies count")
		if enemies != null:
			assert_gt(enemies.get_string(1).to_int(), 0, "the peak enemy count while sampling")
	bench.step(s0 + int(SAMPLE_S * USEC) * 2, 50.0)
	assert_eq(bench.stats().count(), 3, "nothing sampled after the end")
	assert_eq(_quits, [] as Array[int], "no quit in the frame that logs")
	await wait_seconds(QUIT_DELAY_S + 0.3)
	assert_eq(_quits, [0] as Array[int], "quit once with 0 after the delay")
	assert_eq(_lines_containing("[ERROR]"), [] as Array[String], "no errors")


func test_busiest_wave_fails_on_a_slow_frame() -> void:
	_make_level("busiest_wave")
	await _run_until(LevelBench.Stage.SETTLING)
	var bench: LevelBench = _bench()
	var t0: int = _freeze(bench)
	bench.step(t0 + int(SETTLE_S * USEC), 5.0)
	var s0: int = bench._stage_start_usec
	bench.step(s0 + 100000, Config.num("debug.bench.max_ms_max"))
	bench.step(s0 + int(SAMPLE_S * USEC), 5.0)
	assert_eq(bench.exit_code(), 2, "a frame at the limit fails")
	var finals: Array[String] = _final_lines()
	assert_eq(finals.size(), 1)
	if finals.size() == 1:
		assert_string_contains(finals[0], "result=FAIL")
	await wait_seconds(QUIT_DELAY_S + 0.3)
	assert_eq(_quits, [2] as Array[int], "quit with 2")


func test_busiest_wave_cleared_early_stops_sampling() -> void:
	_make_level("busiest_wave")
	await _run_until(LevelBench.Stage.SETTLING)
	var bench: LevelBench = _bench()
	var t0: int = _freeze(bench)
	bench.step(t0 + int(SETTLE_S * USEC), 5.0)
	var s0: int = bench._stage_start_usec
	bench.step(s0 + 100000, 5.0)
	_director().debug_resolve_wave()
	await wait_process_frames(2)
	bench.step(s0 + 200000, 5.0)
	assert_eq(bench.stage(), LevelBench.Stage.DONE, "finished early")
	assert_eq(bench.ended(), "wave_cleared")
	assert_eq(bench.stats().count(), 1, "the frame after the clear is not sampled")
	assert_eq(bench.exit_code(), 0)
	assert_string_contains(_final_lines()[0], "ended=wave_cleared")
	await wait_seconds(QUIT_DELAY_S + 0.3)
	assert_eq(_quits, [0] as Array[int])


func test_wave_cleared_while_settling_is_a_zero_sample_fail() -> void:
	_make_level("busiest_wave")
	await _run_until(LevelBench.Stage.SETTLING)
	var bench: LevelBench = _bench()
	var t0: int = _freeze(bench)
	_director().debug_resolve_wave()
	await wait_process_frames(2)
	bench.step(t0 + 1000, 5.0)
	assert_eq(bench.ended(), "wave_cleared")
	assert_eq(bench.stats().count(), 0)
	assert_eq(bench.exit_code(), 2, "0 samples fail")
	assert_string_contains(_final_lines()[0], "frames=0")
	assert_string_contains(_final_lines()[0], "result=FAIL")
	await wait_seconds(QUIT_DELAY_S + 0.3)
	assert_eq(_quits, [2] as Array[int])


func test_missing_wave_fails_without_hanging() -> void:
	(Config.tuning["debug"]["level_bench"] as Dictionary)["wave"] = 9
	_make_level("busiest_wave")
	var end_ms: int = Time.get_ticks_msec() + 8000
	while _bench().stage() != LevelBench.Stage.DONE and Time.get_ticks_msec() < end_ms:
		await wait_process_frames(1)
	assert_eq(_bench().stage(), LevelBench.Stage.DONE)
	assert_eq(_bench().ended(), "no_target")
	assert_eq(_lines_containing("[ERROR][debug] Level bench: level 3 has no wave 9").size(), 1)
	assert_push_error("Level bench")
	assert_push_warning("Wave jump")
	assert_false(Input.is_action_pressed(&"fire_laser"), "fire never held")
	await wait_seconds(QUIT_DELAY_S + 0.3)
	assert_eq(_quits, [2] as Array[int], "quit with 2")


func test_level_that_fails_to_load_aborts_the_bench() -> void:
	_make_level("busiest_wave", "no_such_level")
	var bench: LevelBench = _bench()
	assert_not_null(bench, "the bench was added before the load")
	if bench == null:
		return
	assert_eq(bench.stage(), LevelBench.Stage.DONE)
	assert_eq(bench.ended(), "no_target")
	assert_eq(bench.exit_code(), 2)
	assert_eq(_lines_containing("[ERROR][debug] Level bench: level 'no_such_level' could not be loaded").size(), 1)
	assert_push_error("Level bench")
	assert_push_error("level_no_such_level.json not found")
	assert_push_error("Level 'no_such_level' could not be loaded; nothing started")
	var finals: Array[String] = _final_lines()
	assert_eq(finals.size(), 1, "one final line")
	if finals.size() == 1:
		assert_string_contains(finals[0], "frames=0 ")
		assert_string_contains(finals[0], "ended=no_target")
		assert_string_contains(finals[0], "result=FAIL")
	assert_eq(_quits, [] as Array[int], "not in the same frame")
	await wait_seconds(QUIT_DELAY_S + 0.3)
	assert_eq(_quits, [2] as Array[int], "quit with 2 after the delay")


# --- desperate --------------------------------------------------------------------

func test_desperate_drives_the_flagship_through_the_final_choice_without_fire() -> void:
	_make_level("desperate")
	var bench: LevelBench = _bench()
	await _run_until(LevelBench.Stage.SETTLING)
	var boss: Flagship = _flagship()
	assert_not_null(boss, "the Flagship")
	if boss == null:
		return
	assert_eq(_director().wave_number(), _director().wave_count(), "the boss wave (the last)")
	assert_eq(boss.phase(), Flagship.Phase.DESPERATE, "DESPERATE")
	assert_eq(boss.live_turret_count(), 0, "the turrets were killed")
	assert_eq(boss.core().hp, Config.int_("boss.final_choice_hp"), "the core at its floor")
	assert_eq(_choices, [&"surrender"] as Array[StringName], "the first option picked once")
	assert_false(_channel().is_showing(), "the response clicked through")
	assert_eq(PauseArbiter.reasons(), [] as Array[StringName], "no pause left")
	assert_false(Input.is_action_pressed(&"fire_laser"), "fire not held")
	assert_false(bench.is_fire_held())
	assert_true(_player().debug_invincible, "the player is invincible")
	assert_true(_warps.has(DebugTools.BENCH_AIM), "the cursor went to BENCH_AIM")
	assert_eq(_lines_containing("[INFO][debug] Level bench: Flagship DESPERATE reached (fire off)").size(), 1)
	var t0: int = _freeze(bench)
	bench.step(t0 + int(SETTLE_S * USEC), 5.0)
	var s0: int = bench._stage_start_usec
	bench.step(s0 + 100000, 8.0)
	bench.step(s0 + int(SAMPLE_S * USEC), 8.0)
	assert_eq(bench.ended(), "time")
	assert_eq(bench.exit_code(), 0)
	assert_string_contains(_final_lines()[0], "scenario=desperate frames=2 ")
	assert_eq(_lines_containing("[ERROR]"), [] as Array[String], "no errors")
	await wait_seconds(QUIT_DELAY_S + 0.3)
	assert_eq(_quits, [0] as Array[int])


func test_desperate_phase_left_early_stops_sampling() -> void:
	_make_level("desperate")
	await _run_until(LevelBench.Stage.SETTLING)
	var bench: LevelBench = _bench()
	var t0: int = _freeze(bench)
	bench.step(t0 + int(SETTLE_S * USEC), 5.0)
	var s0: int = bench._stage_start_usec
	bench.step(s0 + 100000, 5.0)
	var core: FlagshipCore = _flagship().core()
	core.apply_damage(core.hp, null)
	assert_eq(_flagship().phase(), Flagship.Phase.DYING, "Ryn's kill, in effect")
	bench.step(s0 + 200000, 5.0)
	assert_eq(bench.ended(), "phase_left")
	assert_eq(bench.stats().count(), 1)
	assert_string_contains(_final_lines()[0], "ended=phase_left")
	await wait_seconds(QUIT_DELAY_S + 0.3)
	assert_eq(_quits, [0] as Array[int])


func test_desperate_without_a_boss_wave_fails() -> void:
	_make_level("desperate", "dev")
	var end_ms: int = Time.get_ticks_msec() + 5000
	while _bench().stage() != LevelBench.Stage.DONE and Time.get_ticks_msec() < end_ms:
		await wait_process_frames(1)
	assert_eq(_bench().ended(), "no_target")
	assert_eq(_lines_containing("[ERROR][debug] Level bench: no Flagship in level 0").size(), 1)
	assert_push_error("Level bench")
	await wait_seconds(QUIT_DELAY_S + 0.3)
	assert_eq(_quits, [2] as Array[int])


# --- Without a director -----------------------------------------------------------

func test_no_director_fails_at_once() -> void:
	var bench: LevelBench = LevelBench.new()
	bench.debug_enabled = true
	bench.scenario = "busiest_wave"
	bench.target_wave = 3
	bench.sample_s = SAMPLE_S
	bench.quit_delay_s = QUIT_DELAY_S
	bench.quit_game = _record_quit
	add_child_autofree(bench)
	assert_eq(bench.stage(), LevelBench.Stage.DONE)
	assert_eq(bench.exit_code(), 2)
	assert_eq(_lines_containing("[ERROR][debug] Level bench: no WaveDirector in this scene").size(), 1)
	assert_push_error("Level bench")
	assert_eq(_quits, [] as Array[int], "not in the same frame")
	await wait_seconds(QUIT_DELAY_S + 0.3)
	assert_eq(_quits, [2] as Array[int])


func test_release_bench_does_nothing() -> void:
	var bench: LevelBench = LevelBench.new()
	bench.debug_enabled = false
	bench.scenario = "busiest_wave"
	bench.quit_game = _record_quit
	add_child_autofree(bench)
	assert_false(bench.is_processing(), "no processing")
	assert_eq(bench.stage(), LevelBench.Stage.WAITING)
	assert_eq(_lines, [] as Array[String], "nothing logged")
	await wait_seconds(QUIT_DELAY_S + 0.1)
	assert_eq(_quits, [] as Array[int], "never quits")
