class_name DebugTools
extends Node
## Debug-build tools (architecture "Debug Tools"): F1 toggles a frame-stats
## overlay, F5 reloads every JSON file and restarts the scene. With the
## `-- --bench=<s>` user arg it also runs the self-timing stress bench.
## Does nothing at all when debug_enabled is false (release builds).

## Overlay text refresh period (real time).
const OVERLAY_REFRESH_S: float = 0.25
## Bench: real seconds skipped before sampling (spawn, pre-warm, first kills).
const BENCH_WARMUP_S: float = 2.0
## NFR1 frame budget: 60 FPS.
const FRAME_BUDGET_MS: float = 16.6
## Bench sample buffer size per second of bench (vsync is off, so frames are fast).
const BENCH_MAX_FPS: int = 5000
## Bench cursor: under a stress-grid column, in the player zone.
const BENCH_AIM: Vector2 = Vector2(1040, 900)

const _USEC_PER_S: float = 1000000.0

## Overlay visibility, shared across instances so it survives an F5 restart.
static var overlay_visible: bool = false
static var _overlay_initialised: bool = false

## Tests override this before add_child to simulate a release build.
var debug_enabled: bool = OS.is_debug_build()
## Called after a successful F5 reload. Defaults to get_tree().reload_current_scene.
var restart_scene: Callable

var _last_frame_usec: int = 0
var _window_start_usec: int = 0
var _window_sum_ms: float = 0.0
var _window_max_ms: float = 0.0
var _window_frames: int = 0

var _bench_s: float = 0.0
var _bench_start_usec: int = 0
var _bench_done: bool = false
var _bench_stats: FrameStats = null

@onready var _label: Label = $OverlayLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not debug_enabled:
		_label.visible = false
		set_process(false)
		set_process_unhandled_input(false)
		return
	if not restart_scene.is_valid():
		restart_scene = get_tree().reload_current_scene
	var args: Dictionary = DebugArgs.parse(OS.get_cmdline_user_args())
	var stress: bool = args.stress
	if not _overlay_initialised:
		_overlay_initialised = true
		overlay_visible = stress
	_label.visible = overlay_visible
	if stress:
		# Frame ms must measure work, not the display wait.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_bench_s = args.bench_s
	if _bench_s > 0.0:
		_start_bench()
	_reset_window(Time.get_ticks_usec())
	if overlay_visible:
		refresh_overlay()


func _process(_delta: float) -> void:
	# Real wall time, so hit-stop (time_scale 0) does not hide frame cost.
	var now: int = Time.get_ticks_usec()
	if _last_frame_usec != 0:
		var ms: float = (now - _last_frame_usec) / 1000.0
		_window_sum_ms += ms
		_window_frames += 1
		if ms > _window_max_ms:
			_window_max_ms = ms
		if _bench_stats != null and not _bench_done:
			_step_bench(now, ms)
	_last_frame_usec = now
	if _label.visible and (now - _window_start_usec) / _USEC_PER_S >= OVERLAY_REFRESH_S:
		refresh_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if not debug_enabled:
		return
	if event.is_action_pressed(&"debug_overlay"):
		toggle_overlay()
		_mark_handled()
	elif event.is_action_pressed(&"debug_reload_data"):
		reload_data()
		_mark_handled()


func toggle_overlay() -> void:
	if not debug_enabled:
		return
	overlay_visible = not overlay_visible
	_label.visible = overlay_visible
	if overlay_visible:
		_reset_window(Time.get_ticks_usec())
		refresh_overlay()


## Rebuilds the overlay text from the current refresh window, then starts a new window.
func refresh_overlay() -> void:
	if not debug_enabled:
		return
	var avg_ms: float = _window_sum_ms / _window_frames if _window_frames > 0 else 0.0
	_label.text = "FPS %d\nframe ms %.2f avg / %.2f max\nnodes %d\nenemies %d" % [
		Engine.get_frames_per_second(),
		avg_ms,
		_window_max_ms,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		get_tree().get_node_count_in_group(&"enemies"),
	]
	_reset_window(Time.get_ticks_usec())


## F5: reloads tuning and flags. If either file fails to load, the previous
## tuning and flags are restored, load_error is cleared and nothing restarts.
## Returns true when the scene restarted.
func reload_data() -> bool:
	if not debug_enabled:
		return false
	var old_tuning: Dictionary = Config.tuning
	var old_flags: Dictionary = Config.flags
	Config.reload()
	if not Config.load_error.is_empty() or Config.flags.is_empty():
		var reason: String = Config.load_error if not Config.load_error.is_empty() else "flags file failed to load"
		Config.tuning = old_tuning
		Config.flags = old_flags
		Config.load_error = ""
		Log.error("debug", "F5 reload failed (%s); previous data kept, scene not restarted" % reason)
		return false
	# Feedback is an autoload: a scene restart does not re-read its tier cache.
	Feedback.reset()
	Feedback.load_tiers()
	PauseArbiter.clear()
	Log.info("debug", "F5: data reloaded, restarting scene")
	restart_scene.call()
	return true


func _reset_window(now: int) -> void:
	_window_start_usec = now
	_window_sum_ms = 0.0
	_window_max_ms = 0.0
	_window_frames = 0


func _mark_handled() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _start_bench() -> void:
	_bench_stats = FrameStats.new(ceili(_bench_s * BENCH_MAX_FPS))
	_bench_start_usec = Time.get_ticks_usec()
	get_viewport().warp_mouse(BENCH_AIM)
	Input.action_press(&"fire_laser")
	Log.info("debug", "Stress bench: %.1f s warm-up, then %.1f s sampled with fire held" % [BENCH_WARMUP_S, _bench_s])


func _step_bench(now: int, ms: float) -> void:
	var elapsed_s: float = (now - _bench_start_usec) / _USEC_PER_S
	if elapsed_s < BENCH_WARMUP_S:
		return
	if elapsed_s < BENCH_WARMUP_S + _bench_s:
		_bench_stats.add(ms)
		return
	_finish_bench()


func _finish_bench() -> void:
	_bench_done = true
	var exit_code: int = _bench_exit_code()
	Log.info("debug", "Stress bench: frames=%d avg=%.2f ms p99=%.2f ms max=%.2f ms enemies=%d renderer=%s window=%s vsync=%d result=%s" % [
		_bench_stats.count(),
		_bench_stats.average_ms(),
		_bench_stats.percentile_ms(99.0),
		_bench_stats.max_ms(),
		get_tree().get_node_count_in_group(&"enemies"),
		RenderingServer.get_current_rendering_method(),
		DisplayServer.window_get_size(),
		DisplayServer.window_get_vsync_mode(),
		"PASS" if exit_code == 0 else "FAIL",
	])
	Input.action_release(&"fire_laser")
	get_tree().quit(exit_code)


## 0 (PASS) when the sampled average is under FRAME_BUDGET_MS, else 2 (FAIL).
func _bench_exit_code() -> int:
	return 0 if _bench_stats.average_ms() < FRAME_BUDGET_MS else 2
