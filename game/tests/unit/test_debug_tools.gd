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
	assert_push_error("parse error")
	assert_push_error("[ERROR][debug]")


# --- Bench --------------------------------------------------------------------

## A DebugTools with a started 1 s bench; _process off so real frames never finish it.
func _bench_tools() -> DebugTools:
	var tools: DebugTools = _make_tools()
	tools.set_process(false)
	tools._bench_s = 1.0
	tools._start_bench()
	return tools


func test_bench_start_holds_fire() -> void:
	_tools = _bench_tools()
	assert_true(Input.is_action_pressed(&"fire_laser"), "fire_laser held")


func test_bench_skips_warm_up_then_samples() -> void:
	_tools = _bench_tools()
	var start: int = _tools._bench_start_usec
	_tools._step_bench(start + int(DebugTools.BENCH_WARMUP_S * 1000000.0) - 1000, 5.0)
	assert_eq(_tools._bench_stats.count(), 0, "warm-up not sampled")
	_tools._step_bench(start + int((DebugTools.BENCH_WARMUP_S + 0.5) * 1000000.0), 5.0)
	_tools._step_bench(start + int((DebugTools.BENCH_WARMUP_S + 0.6) * 1000000.0), 7.0)
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
