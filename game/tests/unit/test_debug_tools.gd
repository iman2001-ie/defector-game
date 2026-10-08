extends GutTest
## DebugTools: F1 overlay toggle, F5 data reload + restart, release no-op.

const DEBUG_TOOLS_SCENE: PackedScene = preload("res://ui/debug/debug_tools.tscn")
const TEMP_TUNING: String = "user://test_debug_tools_tuning.json"
const TEMP_FLAGS: String = "user://test_debug_tools_flags.json"

var _tools: DebugTools
var _restarts: int = 0


func before_each() -> void:
	DebugTools.overlay_visible = false
	_restarts = 0
	Config.assert_on_missing = false


func after_each() -> void:
	_tools = null
	DebugTools.overlay_visible = false
	Config.assert_on_missing = true
	Config.load_data()
	Feedback.load_tiers()
	Feedback.reset()
	PauseArbiter.clear()
	Input.action_release(&"fire_laser")
	Log.sink = Callable()
	for path: String in [TEMP_TUNING, TEMP_FLAGS]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _count_restart() -> void:
	_restarts += 1


## A DebugTools with an injected restart callable, added to the tree.
func _make_tools(enabled: bool = true) -> DebugTools:
	var tools: DebugTools = DEBUG_TOOLS_SCENE.instantiate() as DebugTools
	tools.debug_enabled = enabled
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
