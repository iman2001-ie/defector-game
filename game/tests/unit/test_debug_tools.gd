extends GutTest
## DebugTools: F1 overlay toggle, F2 invincibility, F4 energy, F5 data reload +
## restart, F7 unlock all (in memory, never saved), release no-op.

const DEBUG_TOOLS_SCENE: PackedScene = preload("res://ui/debug/debug_tools.tscn")
const TEMP_TUNING: String = "user://test_debug_tools_tuning.json"
const TEMP_FLAGS: String = "user://test_debug_tools_flags.json"
## F7 must never write the save; SaveManager points here during the tests.
const TEST_SAVE: String = "user://test_debug_tools_save.cfg"

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")

var _tools: DebugTools
var _restarts: int = 0
var _overlay_initialised_before: bool = false
var _vsync_before: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED
## The sandbox instantiated by _restart_sandbox (the F5 consumer re-read test).
var _restarted_sandbox: Node2D = null


func before_each() -> void:
	DebugTools.overlay_visible = false
	_overlay_initialised_before = DebugTools._overlay_initialised
	_vsync_before = DisplayServer.window_get_vsync_mode()
	_restarts = 0
	_restarted_sandbox = null
	Config.assert_on_missing = false
	SaveManager.save_path = TEST_SAVE
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)
	GameState.highest_unlocked_level = 1
	GameState.all_levels_unlocked = false


func after_each() -> void:
	GameState.energy = 0
	_tools = null
	_restarted_sandbox = null
	DebugTools.overlay_visible = false
	DebugTools._overlay_initialised = _overlay_initialised_before
	DisplayServer.window_set_vsync_mode(_vsync_before)
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Config.assert_on_missing = true
	Config.load_data()
	Feedback.load_tiers()
	Feedback.reset()
	PauseArbiter.clear()
	Input.action_release(&"fire_laser")
	Log.sink = Callable()
	SaveManager.save_path = SaveManager.DEFAULT_SAVE_PATH
	GameState.highest_unlocked_level = 1
	GameState.all_levels_unlocked = false
	for path: String in [TEMP_TUNING, TEMP_FLAGS, TEST_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _count_restart() -> void:
	_restarts += 1


## A DebugTools with an injected restart callable and user args (none by
## default), added to the tree.
func _make_tools(enabled: bool = true, args: PackedStringArray = PackedStringArray()) -> DebugTools:
	var tools: DebugTools = DEBUG_TOOLS_SCENE.instantiate() as DebugTools
	tools.debug_enabled = enabled
	tools.user_args = args
	tools.restart_scene = _count_restart
	add_child_autofree(tools)
	return tools


func _action_event(action: StringName) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _overlay_label(tools: DebugTools) -> Label:
	return tools.get_node("OverlayLabel") as Label


## Writes the real tuning with feedback.tiers.large.shake_px replaced (or raw text).
func _write_tuning(shake_px: float, raw_text: String = "") -> void:
	var text: String = raw_text
	if text.is_empty():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Config.DEFAULT_TUNING_PATH))
		data["feedback"]["tiers"]["large"]["shake_px"] = shake_px
		text = JSON.stringify(data)
	var file: FileAccess = FileAccess.open(TEMP_TUNING, FileAccess.WRITE)
	file.store_string(text)
	file.close()


# --- Structure ----------------------------------------------------------------

func test_process_mode_always_and_label() -> void:
	_tools = _make_tools()
	assert_eq(_tools.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_not_null(_overlay_label(_tools), "OverlayLabel child")


func test_overlay_starts_hidden_outside_stress() -> void:
	_tools = _make_tools()
	assert_false(_overlay_label(_tools).visible)


# --- F1 -----------------------------------------------------------------------

func test_f1_toggles_overlay() -> void:
	_tools = _make_tools()
	var label: Label = _overlay_label(_tools)
	_tools._unhandled_input(_action_event(&"debug_overlay"))
	assert_true(label.visible, "first press shows")
	assert_true(DebugTools.overlay_visible, "static state follows")
	_tools._unhandled_input(_action_event(&"debug_overlay"))
	assert_false(label.visible, "second press hides")
	assert_false(DebugTools.overlay_visible, "static state follows")


func test_overlay_visibility_survives_a_new_instance() -> void:
	_tools = _make_tools()
	_tools.toggle_overlay()
	var second: DebugTools = _make_tools()
	assert_true(_overlay_label(second).visible, "restart keeps the overlay shown")


func test_refresh_overlay_text() -> void:
	_tools = _make_tools()
	_tools.toggle_overlay()
	_tools.refresh_overlay()
	var text: String = _overlay_label(_tools).text
	assert_string_contains(text, "FPS")
	assert_string_contains(text, "frame ms")
	assert_string_contains(text, "nodes")
	assert_string_contains(text, "enemies")


# --- F2 -----------------------------------------------------------------------

func _ignore_warp(_p: Vector2) -> void:
	pass


## A Player in group `player` with physics off (the real mouse must not move it).
func _make_player() -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.warp_mouse = _ignore_warp
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


func test_f2_toggles_player_invincibility() -> void:
	var player: Player = _make_player()
	_tools = _make_tools()
	_tools._unhandled_input(_action_event(&"debug_invincible"))
	assert_true(player.debug_invincible, "first press: on")
	assert_true(player.is_invulnerable())
	_tools._unhandled_input(_action_event(&"debug_invincible"))
	assert_false(player.debug_invincible, "second press: off")


func test_overlay_shows_invincible_state() -> void:
	var player: Player = _make_player()
	_tools = _make_tools()
	_tools.toggle_overlay()
	var label: Label = _overlay_label(_tools)
	assert_string_contains(label.text, "invincible off")
	_tools.toggle_invincible()
	assert_string_contains(label.text, "invincible on", "F2 refreshes the visible overlay")
	assert_true(player.debug_invincible)


func test_overlay_without_player_shows_dash() -> void:
	_tools = _make_tools()
	_tools.toggle_overlay()
	assert_string_contains(_overlay_label(_tools).text, "invincible -")
	_tools.toggle_invincible()
	assert_string_contains(_overlay_label(_tools).text, "invincible -", "no player: nothing to toggle")


func test_f2_does_nothing_in_release() -> void:
	var player: Player = _make_player()
	_tools = _make_tools(false)
	_tools._unhandled_input(_action_event(&"debug_invincible"))
	_tools.toggle_invincible()
	assert_false(player.debug_invincible, "release build: F2 ignored")


# --- F4 -----------------------------------------------------------------------

var _debug_lines: Array[String] = []


func _capture_debug(level: String, category: String, msg: String) -> void:
	_debug_lines.append(Log.format(level, category, msg))


func test_f4_adds_energy_capped() -> void:
	GameState.energy = 30
	watch_signals(Events)
	_debug_lines.clear()
	Log.sink = _capture_debug
	_tools = _make_tools()
	_tools._unhandled_input(_action_event(&"debug_add_energy"))
	Log.sink = Callable()
	assert_eq(GameState.energy, 100, "30 + 100, capped at 100")
	assert_signal_emit_count(Events, "energy_changed", 1)
	assert_signal_emitted_with_parameters(Events, "energy_changed", [100, 100])
	assert_has(_debug_lines, "[INFO][debug] F4: energy 100/100")


func test_f4_from_empty_adds_debug_energy_add() -> void:
	(Config.tuning["debug"] as Dictionary)["energy_add"] = 20
	_tools = _make_tools()
	_tools.add_energy()
	assert_eq(GameState.energy, 20)


func test_f4_does_nothing_in_release() -> void:
	GameState.energy = 30
	watch_signals(Events)
	_tools = _make_tools(false)
	_tools._unhandled_input(_action_event(&"debug_add_energy"))
	_tools.add_energy()
	assert_eq(GameState.energy, 30, "release build: F4 ignored")
	assert_signal_not_emitted(Events, "energy_changed")


# --- F7 -----------------------------------------------------------------------

func test_f7_unlocks_every_level_in_memory_only() -> void:
	_debug_lines.clear()
	Log.sink = _capture_debug
	_tools = _make_tools()
	_tools._unhandled_input(_action_event(&"debug_unlock_all"))
	Log.sink = Callable()
	assert_true(GameState.all_levels_unlocked, "flag set")
	assert_true(GameState.is_level_unlocked(3), "level 3 reports unlocked")
	assert_eq(GameState.highest_unlocked_level, 1, "real progress untouched")
	assert_has(_debug_lines, "[INFO][debug] F7: all levels unlocked (in memory, not saved)")
	assert_false(FileAccess.file_exists(TEST_SAVE), "no save written")
	for line: String in _debug_lines:
		assert_false(line.contains("[save]"), "SaveManager not used: " + line)


func test_f7_does_nothing_in_release() -> void:
	_tools = _make_tools(false)
	_tools._unhandled_input(_action_event(&"debug_unlock_all"))
	_tools.unlock_all()
	assert_false(GameState.all_levels_unlocked, "release build: F7 ignored")
	assert_false(GameState.is_level_unlocked(3))
	assert_false(FileAccess.file_exists(TEST_SAVE))


# --- Release ------------------------------------------------------------------

func test_release_build_is_a_no_op() -> void:
	DebugTools.overlay_visible = true
	_tools = _make_tools(false)
	var label: Label = _overlay_label(_tools)
	assert_false(label.visible, "overlay hidden")
	assert_false(_tools.is_processing(), "process off")
	assert_false(_tools.is_processing_unhandled_input(), "input off")
	_tools._unhandled_input(_action_event(&"debug_overlay"))
	assert_false(label.visible, "F1 ignored")
	_tools._unhandled_input(_action_event(&"debug_reload_data"))
	assert_false(_tools.reload_data(), "reload refused")
	assert_eq(_restarts, 0, "restart never called")
	_tools.refresh_overlay()
	assert_eq(label.text, "", "no overlay text")


# --- F5 -----------------------------------------------------------------------

func test_f5_reloads_tuning_feedback_and_restarts() -> void:
	_write_tuning(8.0)
	Config.load_data(TEMP_TUNING, Config.DEFAULT_FLAGS_PATH)
	Feedback.load_tiers()
	assert_eq(Config.num("feedback.tiers.large.shake_px"), 8.0, "baseline")
	_tools = _make_tools()
	_write_tuning(12.0)
	_tools._unhandled_input(_action_event(&"debug_reload_data"))
	assert_eq(Config.num("feedback.tiers.large.shake_px"), 12.0, "Config reloaded")
	assert_eq(Feedback.tier_row(ImpactTier.LARGE).get("shake_px"), 12.0, "Feedback tiers reloaded")
	assert_eq(_restarts, 1, "restart called once")


func test_reload_data_returns_true_and_clears_pause() -> void:
	_write_tuning(8.0)
	Config.load_data(TEMP_TUNING, Config.DEFAULT_FLAGS_PATH)
	_tools = _make_tools()
	PauseArbiter.push(&"menu")
	assert_true(_tools.reload_data(), "reload succeeded")
	assert_false(PauseArbiter.is_paused(), "pause reasons cleared")
	assert_eq(_restarts, 1)


func test_f5_bad_json_refuses_restart() -> void:
	_write_tuning(8.0)
	Config.load_data(TEMP_TUNING, Config.DEFAULT_FLAGS_PATH)
	_tools = _make_tools()
	_write_tuning(0.0, "{ not json")
	assert_false(_tools.reload_data(), "reload refused")
	assert_eq(_restarts, 0, "restart not called")
	assert_eq(Config.num("feedback.tiers.large.shake_px"), 8.0, "old tuning kept")
	assert_eq(Config.load_error, "", "load_error cleared")
	assert_eq(Feedback.tier_row(ImpactTier.LARGE).get("shake_px"), 8.0, "Feedback tiers untouched")
	assert_push_error("Reload rejected")
	assert_push_error("parse error")
	assert_push_error("[ERROR][debug]")


func test_f5_bad_flags_refuses_restart() -> void:
	var file: FileAccess = FileAccess.open(TEMP_FLAGS, FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string(Config.DEFAULT_FLAGS_PATH))
	file.close()
	Config.load_data(Config.DEFAULT_TUNING_PATH, TEMP_FLAGS)
	var old_flags: Dictionary = Config.flags.duplicate(true)
	assert_false(old_flags.is_empty(), "baseline flags")
	_tools = _make_tools()
	file = FileAccess.open(TEMP_FLAGS, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	assert_false(_tools.reload_data(), "reload refused")
	assert_eq(_restarts, 0, "restart not called")
	assert_eq(Config.flags, old_flags, "old flags kept")
	assert_eq(Config.load_error, "", "load_error clear")
	assert_push_error("Reload rejected")
	assert_push_error("parse error")
	assert_push_error("[ERROR][debug]")


func test_f5_missing_key_refuses_restart() -> void:
	_write_tuning(8.0)
	Config.load_data(TEMP_TUNING, Config.DEFAULT_FLAGS_PATH)
	Feedback.load_tiers()
	_tools = _make_tools()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEMP_TUNING))
	(data["player"] as Dictionary).erase("hearts")
	data["feedback"]["tiers"]["large"]["shake_px"] = 12.0
	_write_tuning(0.0, JSON.stringify(data))
	assert_false(_tools.reload_data(), "reload refused")
	assert_eq(_restarts, 0, "restart not called")
	assert_eq(Config.int_("player.hearts"), 5, "old value served")
	assert_eq(Config.num("feedback.tiers.large.shake_px"), 8.0, "old tuning kept")
	assert_eq(Feedback.tier_row(ImpactTier.LARGE).get("shake_px"), 8.0, "Feedback tiers untouched")
	assert_push_error("tuning.player.hearts missing")
	assert_push_error("[ERROR][debug]")


# --- Bench --------------------------------------------------------------------

const USEC: float = 1000000.0

var _quits: Array[int] = []
var _lines: Array[String] = []


func _record_quit(code: int) -> void:
	_quits.append(code)


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _lines_containing(text: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.contains(text):
			out.append(line)
	return out


## A DebugTools with a started 1 s bench; _process off so real frames never finish
## it, and an injected quit callable that only records the exit code.
func _bench_tools() -> DebugTools:
	_quits.clear()
	_lines.clear()
	var tools: DebugTools = _make_tools()
	tools.set_process(false)
	tools.quit_game = _record_quit
	tools._bench_s = 1.0
	tools._start_bench()
	return tools


func _at(tools: DebugTools, seconds: float) -> int:
	return tools._bench_start_usec + int(seconds * USEC)


func test_bench_start_holds_fire() -> void:
	_tools = _bench_tools()
	assert_true(Input.is_action_pressed(&"fire_laser"), "fire_laser held")


func test_bench_skips_warm_up_then_samples() -> void:
	_tools = _bench_tools()
	var warmup: float = Config.num("debug.bench.warmup_s")
	assert_gt(warmup, 0.0, "warm-up from Config")
	_tools._step_bench(_at(_tools, warmup) - 1000, 5.0)
	assert_eq(_tools._bench_stats.count(), 0, "warm-up not sampled")
	_tools._step_bench(_at(_tools, warmup + 0.5), 5.0)
	_tools._step_bench(_at(_tools, warmup + 0.6), 7.0)
	assert_eq(_tools._bench_stats.count(), 2, "window sampled")
	assert_false(_tools._bench_done, "still running")


func test_bench_exit_code_pass_and_fail() -> void:
	_tools = _bench_tools()
	_tools._bench_stats = FrameStats.new(4)
	_tools._bench_stats.add(10.0)
	_tools._bench_stats.add(16.0)
	assert_eq(_tools._bench_exit_code(), 0, "under budget passes")
	_tools._bench_stats.clear()
	_tools._bench_stats.add(16.6)
	assert_eq(_tools._bench_exit_code(), 2, "at budget fails")
	_tools._bench_stats.clear()
	_tools._bench_stats.add(30.0)
	assert_eq(_tools._bench_exit_code(), 2, "over budget fails")


func test_bench_fails_on_a_max_spike_with_a_passing_average() -> void:
	_tools = _bench_tools()
	_tools._bench_stats = FrameStats.new(1000)
	for i: int in 999:
		_tools._bench_stats.add(4.0)
	_tools._bench_stats.add(Config.num("debug.bench.max_ms_max"))
	assert_lt(_tools._bench_stats.average_ms(), Config.num("debug.bench.avg_ms_max"), "average passes")
	assert_lt(_tools._bench_stats.percentile_ms(99.0), Config.num("debug.bench.p99_ms_max"), "p99 passes")
	assert_eq(_tools._bench_exit_code(), 2, "max at its limit fails")


func test_bench_fails_on_p99_with_a_passing_average() -> void:
	_tools = _bench_tools()
	(Config.tuning["debug"]["bench"] as Dictionary)["max_ms_max"] = 1000.0
	_tools._bench_stats = FrameStats.new(100)
	for i: int in 97:
		_tools._bench_stats.add(4.0)
	for i: int in 3:
		_tools._bench_stats.add(20.0)
	assert_lt(_tools._bench_stats.average_ms(), Config.num("debug.bench.avg_ms_max"), "average passes")
	assert_gte(_tools._bench_stats.percentile_ms(99.0), Config.num("debug.bench.p99_ms_max"), "p99 over")
	assert_eq(_tools._bench_exit_code(), 2, "p99 over its limit fails")


func test_bench_fails_with_no_samples() -> void:
	_tools = _bench_tools()
	_tools._bench_stats = FrameStats.new(4)
	assert_eq(_tools._bench_exit_code(), 2, "empty bench is not a PASS")


func test_bench_limits_come_from_config() -> void:
	_tools = _bench_tools()
	_tools._bench_stats = FrameStats.new(4)
	_tools._bench_stats.add(20.0)
	assert_eq(_tools._bench_exit_code(), 2, "fails at the default limits")
	var bench: Dictionary = Config.tuning["debug"]["bench"]
	bench["avg_ms_max"] = 25.0
	bench["p99_ms_max"] = 25.0
	bench["max_ms_max"] = 25.0
	assert_eq(_tools._bench_exit_code(), 0, "passes once the limits are raised")


func test_finish_logs_then_quits_after_the_delay() -> void:
	# A generous delay so a slow headless frame can't fire the quit before the
	# next-frame check (the same-frame check below needs no margin).
	(Config.tuning["debug"]["bench"] as Dictionary)["quit_delay_s"] = 1.0
	_tools = _bench_tools()
	Log.sink = _capture
	_tools._bench_stats = FrameStats.new(4)
	_tools._bench_stats.add(5.0)
	_tools._bench_stats.add(6.0)
	_tools._finish_bench()
	Log.sink = Callable()
	var finals: Array[String] = _lines_containing("Stress bench: frames=")
	assert_eq(finals.size(), 1, "one final line")
	if finals.size() == 1:
		var line: String = finals[0]
		assert_true(line.begins_with("[INFO][debug] Stress bench:"), line)
		for part: String in ["frames=2", "avg=5.50 ms", "p99=6.00 ms", "max=6.00 ms", "enemies=", "projectiles=", "result=PASS"]:
			assert_string_contains(line, part)
	assert_true(_tools._bench_done, "bench done")
	assert_false(Input.is_action_pressed(&"fire_laser"), "fire released")
	assert_eq(_quits.size(), 0, "no quit in the same frame as the log")
	await wait_process_frames(1)
	assert_eq(_quits.size(), 0, "no quit on the next frame either")
	await wait_seconds(Config.num("debug.bench.quit_delay_s") + 0.2)
	assert_eq(_quits, [0] as Array[int], "quit once with the PASS exit code")


func test_finish_quits_with_fail_code() -> void:
	_tools = _bench_tools()
	Log.sink = _capture
	_tools._bench_stats = FrameStats.new(4)
	_tools._finish_bench()
	Log.sink = Callable()
	var finals: Array[String] = _lines_containing("Stress bench: frames=")
	assert_eq(finals.size(), 1, "final line still written for an empty bench")
	if finals.size() == 1:
		assert_string_contains(finals[0], "frames=0")
		assert_string_contains(finals[0], "result=FAIL")
	assert_eq(_quits.size(), 0, "not yet")
	await wait_seconds(Config.num("debug.bench.quit_delay_s") + 0.2)
	assert_eq(_quits, [2] as Array[int], "empty bench quits with 2")


func test_step_past_the_window_finishes_once() -> void:
	_tools = _bench_tools()
	var end_s: float = Config.num("debug.bench.warmup_s") + _tools._bench_s
	_tools._step_bench(_at(_tools, end_s + 0.1), 5.0)
	assert_true(_tools._bench_done, "finished")
	await wait_seconds(Config.num("debug.bench.quit_delay_s") + 0.2)
	assert_eq(_quits.size(), 1, "quit called once")


## One bench step inside warm-up, after the first-large time.
func _step_first_large(tools: DebugTools, ms: float) -> void:
	tools._step_bench(_at(tools, Config.num("debug.bench.first_large_at_s") + 0.01), ms)


func test_first_large_impact_fires_once_and_logs_its_frames() -> void:
	_tools = _bench_tools()
	Log.sink = _capture
	var at_s: float = Config.num("debug.bench.first_large_at_s")
	assert_lt(at_s, Config.num("debug.bench.warmup_s"), "inside warm-up")
	_tools._step_bench(_at(_tools, at_s) - 1000, 3.0)
	assert_false(Feedback.is_hit_stopped(), "nothing before its time")
	_step_first_large(_tools, 3.0)
	assert_true(Feedback.is_hit_stopped(), "LARGE impact fired (hit-stop running)")
	Feedback.reset()
	var frames: int = Config.int_("debug.bench.first_large_frames")
	assert_gt(frames, 0, "frames from Config")
	for i: int in frames - 1:
		_step_first_large(_tools, 10.0 + i)
	assert_eq(_lines_containing("first LARGE impact").size(), 0, "not logged before every frame is measured")
	_step_first_large(_tools, 30.0)
	_step_first_large(_tools, 3.0)
	Log.sink = Callable()
	assert_false(Feedback.is_hit_stopped(), "fired once only")
	var logged: Array[String] = _lines_containing("Stress bench: first LARGE impact")
	assert_eq(logged.size(), 1, "one first-large line")
	if logged.size() == 1:
		assert_true(logged[0].begins_with("[INFO][debug]"), logged[0])
		assert_string_contains(logged[0], "max=30.00 ms")
		assert_string_contains(logged[0], "prewarm=on")
	assert_eq(_tools._bench_stats.count(), 0, "warm-up frames are not sampled")


func test_first_large_logs_prewarm_off() -> void:
	_tools = _bench_tools()
	_tools._prewarm = false
	Log.sink = _capture
	_step_first_large(_tools, 3.0)
	Feedback.reset()
	for i: int in Config.int_("debug.bench.first_large_frames"):
		_step_first_large(_tools, 8.0)
	Log.sink = Callable()
	var logged: Array[String] = _lines_containing("Stress bench: first LARGE impact")
	assert_eq(logged.size(), 1, "one first-large line")
	if logged.size() == 1:
		assert_string_contains(logged[0], "prewarm=off")


# --- F3 / F6 and the wave overlay lines (Story 2.2) ----------------------------

## A WaveDirector (no spawner) in the tree, running two empty waves.
func _make_director() -> WaveDirector:
	var director: WaveDirector = WaveDirector.new()
	add_child_autofree(director)
	director.start_level({"id": 1.0, "waves": [{"spawns": []}, {"spawns": []}]}, "test")
	assert_push_error("no spawner")
	return director


func test_f3_dispatches_to_the_wave_director() -> void:
	_lines.clear()
	_make_director()
	_tools = _make_tools()
	Log.sink = _capture
	_tools._unhandled_input(_action_event(&"debug_resolve_wave"))
	Log.sink = Callable()
	assert_eq(_lines_containing("[INFO][debug] F3:").size(), 1, "F3 reached the director")
	assert_eq(_lines_containing("no wave director").size(), 0)


func test_f3_without_a_director_logs() -> void:
	_lines.clear()
	_tools = _make_tools()
	Log.sink = _capture
	_tools._unhandled_input(_action_event(&"debug_resolve_wave"))
	Log.sink = Callable()
	assert_eq(_lines_containing("[INFO][debug] F3: no wave director in this scene").size(), 1)


func test_f6_dispatches_to_the_wave_director() -> void:
	_lines.clear()
	_make_director()
	_tools = _make_tools()
	Log.sink = _capture
	_tools._unhandled_input(_action_event(&"debug_skip_to_boss"))
	Log.sink = Callable()
	assert_eq(_lines_containing("[INFO][debug] F6: no boss wave in level 1").size(), 1, "F6 reached the director")


func test_f6_without_a_director_logs() -> void:
	_lines.clear()
	_tools = _make_tools()
	Log.sink = _capture
	_tools._unhandled_input(_action_event(&"debug_skip_to_boss"))
	Log.sink = Callable()
	assert_eq(_lines_containing("[INFO][debug] F6: no wave director in this scene").size(), 1)


func test_release_ignores_f3_and_f6() -> void:
	_lines.clear()
	_tools = _make_tools(false)
	Log.sink = _capture
	_tools.resolve_wave()
	_tools.skip_to_boss()
	Log.sink = Callable()
	assert_eq(_lines.size(), 0, "nothing logged")


func test_overlay_wave_and_pause_lines() -> void:
	_tools = _make_tools()
	_tools.refresh_overlay()
	var text: String = _overlay_label(_tools).text
	assert_string_contains(text, "wave -")
	assert_string_contains(text, "pause none")
	_make_director()
	PauseArbiter.push(&"menu")
	_tools.refresh_overlay()
	text = _overlay_label(_tools).text
	assert_string_contains(text, "wave 1/2")
	assert_string_contains(text, "resolved 0/0")
	assert_string_contains(text, "pause menu")


# --- User args wiring (DW-27) ---------------------------------------------------

## A DebugTools whose _ready parses args, with logs captured from before _ready
## and an injected quit; _process stops right after so real frames never step a bench.
func _args_tools(args: PackedStringArray) -> DebugTools:
	_quits.clear()
	_lines.clear()
	var tools: DebugTools = DEBUG_TOOLS_SCENE.instantiate() as DebugTools
	tools.debug_enabled = true
	tools.user_args = args
	tools.restart_scene = _count_restart
	tools.quit_game = _record_quit
	DebugTools._overlay_initialised = false
	Log.sink = _capture
	add_child_autofree(tools)
	Log.sink = Callable()
	tools.set_process(false)
	return tools


func test_bench_arg_with_no_prewarm_starts_the_bench_prewarm_off() -> void:
	_tools = _args_tools(PackedStringArray(["--bench=1", "--no-prewarm"]))
	var starts: Array[String] = _lines_containing("Stress bench: ")
	starts = starts.filter(func(line: String) -> bool: return line.contains("warm-up"))
	assert_eq(starts.size(), 1, "one bench start line")
	if starts.size() == 1:
		assert_string_contains(starts[0], "prewarm=off")
	assert_true(Input.is_action_pressed(&"fire_laser"), "fire_laser held by the bench")
	assert_true(_overlay_label(_tools).visible, "bench implies stress: overlay shown")
	assert_eq(_quits.size(), 0, "no quit at start")


func test_bench_arg_defaults_to_prewarm_on() -> void:
	_tools = _args_tools(PackedStringArray(["--bench=1"]))
	var starts: Array[String] = _lines_containing("Stress bench: ")
	starts = starts.filter(func(line: String) -> bool: return line.contains("warm-up"))
	assert_eq(starts.size(), 1, "one bench start line")
	if starts.size() == 1:
		assert_string_contains(starts[0], "prewarm=on")
	assert_true(Input.is_action_pressed(&"fire_laser"), "fire_laser held by the bench")


func test_stress_arg_shows_the_overlay_without_a_bench() -> void:
	_tools = _args_tools(PackedStringArray(["--stress"]))
	assert_true(_overlay_label(_tools).visible, "stress shows the overlay")
	assert_true(DebugTools.overlay_visible, "static state follows")
	assert_false(Input.is_action_pressed(&"fire_laser"), "no bench: fire not held")
	assert_eq(_lines_containing("Stress bench").size(), 0, "no bench line")


func test_no_args_keeps_the_overlay_hidden_and_no_bench() -> void:
	_tools = _args_tools(PackedStringArray())
	assert_false(_overlay_label(_tools).visible, "overlay hidden")
	assert_false(DebugTools.overlay_visible, "static state follows")
	assert_false(Input.is_action_pressed(&"fire_laser"), "no bench: fire not held")
	assert_eq(_lines_containing("Stress bench").size(), 0, "no bench line")


# --- Real F5 path (DW-19) --------------------------------------------------------

func _f5_key_event() -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_F5
	event.pressed = true
	return event


func test_real_f5_key_reloads_and_restarts() -> void:
	_write_tuning(8.0)
	Config.load_data(TEMP_TUNING, Config.DEFAULT_FLAGS_PATH)
	Feedback.load_tiers()
	_tools = _make_tools()
	_write_tuning(12.0)
	get_viewport().push_input(_f5_key_event())
	assert_eq(Config.num("feedback.tiers.large.shake_px"), 12.0, "Config reloaded from the changed file")
	assert_eq(Feedback.tier_row(ImpactTier.LARGE).get("shake_px"), 12.0, "Feedback tiers reloaded")
	assert_eq(_restarts, 1, "restart called once")


func test_default_callables_target_the_scene_tree() -> void:
	var tools: DebugTools = DEBUG_TOOLS_SCENE.instantiate() as DebugTools
	tools.debug_enabled = true
	tools.user_args = PackedStringArray()
	add_child_autofree(tools)
	_tools = tools
	assert_true(tools.restart_scene.is_valid(), "restart bound")
	assert_eq(tools.restart_scene.get_object(), get_tree(), "restart on the scene tree")
	assert_eq(tools.restart_scene.get_method(), &"reload_current_scene", "restart reloads the scene")
	assert_true(tools.quit_game.is_valid(), "quit bound")
	assert_eq(tools.quit_game.get_object(), get_tree(), "quit on the scene tree")
	assert_eq(tools.quit_game.get_method(), &"quit", "quit is SceneTree.quit")


## Stands in for reload_current_scene: instantiates the sandbox fresh.
func _restart_sandbox() -> void:
	_restarts += 1
	_restarted_sandbox = SANDBOX_SCENE.instantiate() as Node2D
	add_child_autofree(_restarted_sandbox)


func test_real_f5_restart_re_reads_config_in_the_new_scene() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Config.DEFAULT_TUNING_PATH))
	var new_intensity: float = (data["render"]["glow"]["intensity"] as float) + 0.25
	_write_tuning(8.0)
	Config.load_data(TEMP_TUNING, Config.DEFAULT_FLAGS_PATH)
	_tools = _make_tools()
	_tools.restart_scene = _restart_sandbox
	data["render"]["glow"]["intensity"] = new_intensity
	_write_tuning(0.0, JSON.stringify(data))
	get_viewport().push_input(_f5_key_event())
	assert_eq(_restarts, 1, "restart called once")
	assert_not_null(_restarted_sandbox, "sandbox re-instantiated")
	if _restarted_sandbox == null:
		return
	var env: Environment = (_restarted_sandbox.get_node("WorldEnvironment") as WorldEnvironment).environment
	assert_almost_eq(env.glow_intensity, new_intensity, 0.0001, "new scene reads the reloaded glow")
