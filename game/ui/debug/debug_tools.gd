class_name DebugTools
extends Node
## Debug-build tools (architecture "Debug Tools"): F1 toggles a frame-stats
## overlay (plus wave n/N, resolved/total, the pause reasons and the player's
## invincibility), F2 toggles the player's debug_invincible, F3 resolves
## the current wave and F6 jumps to the boss wave (both through the scene's
## WaveDirector, found by group), F4 adds debug.energy_add energy through
## GameState (capped), F5 reloads every JSON file, restores GameState's
## saved progress (as goto_title does) and restarts the scene, F7 unlocks
## every level in memory (GameState.all_levels_unlocked; never saved). With
## the `-- --bench=<s>` user arg it also runs the self-timing stress bench; its
## numbers (limits, warm-up, first-large timing, quit delay) come from
## tuning.debug.bench. Does nothing at all when debug_enabled is false (release builds).

## Overlay text refresh period (real time).
const OVERLAY_REFRESH_S: float = 0.25
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
## Called with the bench exit code once the bench is over. Defaults to get_tree().quit.
var quit_game: Callable
## The user args _ready parses (`--stress`, `--bench=<s>`, `--no-prewarm`).
## Tests override this before add_child.
var user_args: PackedStringArray = OS.get_cmdline_user_args()

var _last_frame_usec: int = 0
var _window_start_usec: int = 0
var _window_sum_ms: float = 0.0
var _window_max_ms: float = 0.0
var _window_frames: int = 0

var _bench_s: float = 0.0
var _bench_start_usec: int = 0
var _bench_done: bool = false
var _bench_stats: FrameStats = null
## False with the `--no-prewarm` user arg (the sandbox then skipped Feedback.prewarm()).
var _prewarm: bool = true
var _warmup_s: float = 0.0
var _quit_delay_s: float = 0.0
var _first_large_at_s: float = 0.0
var _first_large_frames: int = 0
var _first_large_fired: bool = false
## Frames still to measure after the deliberate LARGE impact.
var _first_large_left: int = 0
var _first_large_measured: int = 0
var _first_large_sum_ms: float = 0.0
var _first_large_max_ms: float = 0.0

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
	if not quit_game.is_valid():
		quit_game = get_tree().quit
	var args: Dictionary = DebugArgs.parse(user_args)
	var stress: bool = args.stress
	_prewarm = args.prewarm
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
	elif event.is_action_pressed(&"debug_invincible"):
		toggle_invincible()
		_mark_handled()
	elif event.is_action_pressed(&"debug_add_energy"):
		add_energy()
		_mark_handled()
	elif event.is_action_pressed(&"debug_reload_data"):
		reload_data()
		_mark_handled()
	elif event.is_action_pressed(&"debug_resolve_wave"):
		resolve_wave()
		_mark_handled()
	elif event.is_action_pressed(&"debug_skip_to_boss"):
		skip_to_boss()
		_mark_handled()
	elif event.is_action_pressed(&"debug_unlock_all"):
		unlock_all()
		_mark_handled()


## F2: flips debug_invincible on the scene's Player (found by group).
func toggle_invincible() -> void:
	if not debug_enabled:
		return
	var player: Player = _player()
	if player == null:
		Log.info("debug", "F2: no player in this scene")
		return
	player.debug_invincible = not player.debug_invincible
	Log.info("debug", "F2: invincible %s" % _on_off(player.debug_invincible))
	if _label.visible:
		refresh_overlay()


## F4: adds debug.energy_add energy through GameState (clamped to the max).
func add_energy() -> void:
	if not debug_enabled:
		return
	var energy: int = GameState.add_energy(Config.int_("debug.energy_add"))
	Log.info("debug", "F4: energy %d/%d" % [energy, GameState.max_energy()])


## F7: every level counts as unlocked (GameState.all_levels_unlocked), in
## memory only: SaveManager is never called.
func unlock_all() -> void:
	if not debug_enabled:
		return
	GameState.all_levels_unlocked = true
	Log.info("debug", "F7: all levels unlocked (in memory, not saved)")


func _player() -> Player:
	return get_tree().get_first_node_in_group(Groups.PLAYER) as Player


## F3: resolves the current wave through the scene's WaveDirector.
func resolve_wave() -> void:
	if not debug_enabled:
		return
	var director: WaveDirector = _director()
	if director == null:
		Log.info("debug", "F3: no wave director in this scene")
		return
	director.debug_resolve_wave()


## F6: jumps to the boss wave through the scene's WaveDirector.
func skip_to_boss() -> void:
	if not debug_enabled:
		return
	var director: WaveDirector = _director()
	if director == null:
		Log.info("debug", "F6: no wave director in this scene")
		return
	director.debug_skip_to_boss()


func _director() -> WaveDirector:
	return get_tree().get_first_node_in_group(Groups.WAVE_DIRECTOR) as WaveDirector


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
	_label.text = "FPS %d\nframe ms %.2f avg / %.2f max\nnodes %d\nenemies %d\n%s\npause %s\n%s" % [
		Engine.get_frames_per_second(),
		avg_ms,
		_window_max_ms,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		get_tree().get_node_count_in_group(Groups.ENEMIES),
		_wave_lines(),
		_pause_line(),
		_invincible_line(),
	]
	_reset_window(Time.get_ticks_usec())


## F5: asks Config to reload tuning and flags. Config validates the new files
## and keeps its previous data if either fails to load or drops or retypes a
## key; then nothing restarts and GameState and the pauses stay as they are.
## On success it restores the saved unlock, zeroes the energy and clears
## is_retry (SceneRouter.restore_saved_progress(), with the new clamps), restarts the
## scene, and only then drops the pauses, so `resumed` never reaches the
## outgoing scene's Player in the tree (DW-61). Returns true when the scene
## restarted.
func reload_data() -> bool:
	if not debug_enabled:
		return false
	if not Config.reload():
		Log.error("debug", "F5 reload failed; previous data kept, scene not restarted")
		return false
	# Feedback is an autoload: a scene restart does not re-read its tier cache.
	Feedback.reset()
	Feedback.load_tiers()
	SceneRouter.restore_saved_progress()
	Log.info("debug", "F5: data reloaded, restarting scene")
	restart_scene.call()
	PauseArbiter.clear()
	return true


## "wave n/N" and "resolved r/t", or "wave -" without a WaveDirector.
func _wave_lines() -> String:
	var director: WaveDirector = _director()
	if director == null:
		return "wave -"
	return "wave %d/%d\nresolved %d/%d" % [
		director.wave_number(), director.wave_count(), director.resolved_count(), director.total_count(),
	]


## "invincible on|off", or "invincible -" without a Player.
func _invincible_line() -> String:
	var player: Player = _player()
	if player == null:
		return "invincible -"
	return "invincible %s" % _on_off(player.debug_invincible)


func _on_off(value: bool) -> String:
	return "on" if value else "off"


func _pause_line() -> String:
	var reasons: Array[StringName] = PauseArbiter.reasons()
	if reasons.is_empty():
		return "none"
	var names: PackedStringArray = []
	for reason: StringName in reasons:
		names.append(String(reason))
	return ", ".join(names)


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
	_warmup_s = Config.num("debug.bench.warmup_s")
	_quit_delay_s = Config.num("debug.bench.quit_delay_s")
	_first_large_at_s = Config.num("debug.bench.first_large_at_s")
	_first_large_frames = Config.int_("debug.bench.first_large_frames")
	_first_large_fired = false
	_first_large_left = 0
	_bench_stats = FrameStats.new(ceili(_bench_s * BENCH_MAX_FPS))
	_bench_start_usec = Time.get_ticks_usec()
	get_viewport().warp_mouse(BENCH_AIM)
	Input.action_press(&"fire_laser")
	if _first_large_at_s >= _warmup_s:
		Log.warn("debug", "Stress bench: debug.bench.first_large_at_s (%.2f) is not inside the %.2f s warm-up; no deliberate LARGE impact" % [_first_large_at_s, _warmup_s])
	Log.info("debug", "Stress bench: %.1f s warm-up (LARGE impact at %.1f s), then %.1f s sampled with fire held, prewarm=%s" % [
		_warmup_s, _first_large_at_s, _bench_s, _prewarm_label(),
	])


func _step_bench(now: int, ms: float) -> void:
	if _first_large_left > 0:
		_measure_first_large(ms)
	var elapsed_s: float = (now - _bench_start_usec) / _USEC_PER_S
	if elapsed_s < _warmup_s:
		if not _first_large_fired and elapsed_s >= _first_large_at_s:
			_fire_first_large()
		return
	if elapsed_s < _warmup_s + _bench_s:
		_bench_stats.add(ms)
		return
	_finish_bench()


## The one deliberate LARGE impact of the bench (its debris and shockwave are the
## first ones of the run). Its cost shows in the frames that follow, measured by
## _measure_first_large.
func _fire_first_large() -> void:
	_first_large_fired = true
	_first_large_measured = 0
	_first_large_sum_ms = 0.0
	_first_large_max_ms = 0.0
	_first_large_left = _first_large_frames
	Feedback.impact(ImpactTier.LARGE, Playfield.RECT.get_center())
	if _first_large_left <= 0:
		_log_first_large()


func _measure_first_large(ms: float) -> void:
	_first_large_measured += 1
	_first_large_sum_ms += ms
	if ms > _first_large_max_ms:
		_first_large_max_ms = ms
	_first_large_left -= 1
	if _first_large_left == 0:
		_log_first_large()


func _log_first_large() -> void:
	var avg_ms: float = _first_large_sum_ms / _first_large_measured if _first_large_measured > 0 else 0.0
	Log.info("debug", "Stress bench: first LARGE impact max=%.2f ms avg=%.2f ms over %d frames prewarm=%s" % [
		_first_large_max_ms, avg_ms, _first_large_measured, _prewarm_label(),
	])


func _prewarm_label() -> String:
	return "on" if _prewarm else "off"


## Releases fire, logs the final line, then quits on a later frame: the real-time
## quit delay gives stdout and the file logger time to drain (DW-21).
func _finish_bench() -> void:
	_bench_done = true
	var exit_code: int = _bench_exit_code()
	Input.action_release(&"fire_laser")
	if _first_large_left > 0:
		_first_large_left = 0
		_log_first_large()
	Log.info("debug", "Stress bench: frames=%d avg=%.2f ms p99=%.2f ms max=%.2f ms enemies=%d projectiles=%d renderer=%s window=%s vsync=%d result=%s" % [
		_bench_stats.count(),
		_bench_stats.average_ms(),
		_bench_stats.percentile_ms(99.0),
		_bench_stats.max_ms(),
		get_tree().get_node_count_in_group(Groups.ENEMIES),
		get_tree().get_node_count_in_group(Groups.PROJECTILES),
		RenderingServer.get_current_rendering_method(),
		DisplayServer.window_get_size(),
		DisplayServer.window_get_vsync_mode(),
		"PASS" if exit_code == 0 else "FAIL",
	])
	# Real time, process_always, ignoring time_scale: hit-stop cannot hold the quit.
	# Bound to quit_game itself, so the quit survives this node being freed meanwhile.
	get_tree().create_timer(_quit_delay_s, true, false, true).timeout.connect(quit_game.bind(exit_code))


## 0 (PASS) when the sampled avg, p99 and max are all under their
## tuning.debug.bench limits, else 2 (FAIL). An empty bench fails.
func _bench_exit_code() -> int:
	if _bench_stats == null or _bench_stats.count() == 0:
		return 2
	var passed: bool = (
		_bench_stats.average_ms() < Config.num("debug.bench.avg_ms_max")
		and _bench_stats.percentile_ms(99.0) < Config.num("debug.bench.p99_ms_max")
		and _bench_stats.max_ms() < Config.num("debug.bench.max_ms_max")
	)
	return 0 if passed else 2
