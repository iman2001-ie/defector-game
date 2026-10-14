class_name LevelBench
extends Node
## Self-timing level bench (Story 8.3, NFR1): `-- --level-bench=<scenario>` on a
## debug build. Boot starts level debug.level_bench.level and level.gd adds one
## LevelBench under Overlay, handing it its refs and its numbers before
## add_child. It drives the real level to the scenario's target state with no
## input, samples real frame times there and quits PASS (0) or FAIL (2), like
## the sandbox stress bench (DebugTools `--bench=`), whose PASS rule
## (DebugTools.bench_passed) it shares.
##
## Scenarios (DebugArgs.LEVEL_BENCH_SCENARIOS):
## - busiest_wave: once wave 1 starts (the intro clicked through), it jumps
##   (deferred) to wave `target_wave` (1-based) through
##   WaveDirector.debug_jump_to_wave, makes the Player debug_invincible, warps
##   the cursor to DebugTools.BENCH_AIM through the Player's warp_mouse and
##   holds fire_laser. Sampling starts settle_s after that wave starts and
##   stops after sample_s, or early when the wave clears (ended=wave_cleared).
## - desperate: once wave 1 starts it jumps to the boss wave
##   (WaveDirector.debug_skip_to_boss), with the same invincibility and aim but
##   fire NOT held (the laser would kill the 50 HP core in about 5 s). When the
##   Flagship reaches TURRETS it kills the turrets, drops the core to its Final
##   Choice floor, clicks through l3_final_choice, picks the first option and
##   clicks through the response. Sampling starts settle_s after DESPERATE
##   begins and stops after sample_s, or early when the phase ends (Ryn kills
##   the core: ended=phase_left).
## Story comms are clicked through with the public CommsChannel.advance() and
## FinalChoice button APIs; the bench never pushes or pops a pause, so it runs
## PROCESS_MODE_ALWAYS. A missing WaveDirector, wave or Flagship logs an
## ERROR and finishes at once (frames=0, ended=no_target, FAIL).
##
## Frame ms is real wall time (Time.get_ticks_usec()), so hit-stop can't hide a
## frame's cost; vsync is off for the run. The sample buffer is preallocated
## (FrameStats) and nothing is logged per frame: one start line, one
## phase-reached line and the final line
##   `Level bench: scenario=… frames=… avg=… ms p99=… ms max=… ms enemies=…
##   projectiles=… ended=time|wave_cleared|phase_left renderer=… window=…
##   vsync=… result=PASS|FAIL`
## (enemies and projectiles are the peak live counts while sampling). The quit
## runs through quit_game after a real-time quit_delay_s timer, never in the
## frame that logs. Does nothing when debug_enabled is false (release builds).

enum Stage { WAITING, DRIVING, SETTLING, SAMPLING, DONE }

const BUSIEST_WAVE: String = "busiest_wave"
const DESPERATE: String = "desperate"
const ENDED_TIME: String = "time"
const ENDED_WAVE_CLEARED: String = "wave_cleared"
const ENDED_PHASE_LEFT: String = "phase_left"
const ENDED_NO_TARGET: String = "no_target"
const _USEC_PER_S: float = 1000000.0

## Tests override this before add_child to simulate a release build.
var debug_enabled: bool = OS.is_debug_build()
## One of DebugArgs.LEVEL_BENCH_SCENARIOS.
var scenario: String = ""
var director: WaveDirector = null
var player: Player = null
var channel: CommsChannel = null
var final_choice: FinalChoice = null
## busiest_wave's target wave, 1-based (debug.level_bench.wave).
var target_wave: int = 0
## Seconds sampled (debug.level_bench.sample_s).
var sample_s: float = 0.0
## Seconds between reaching the target state and the first sample
## (debug.level_bench.settle_s): Feedback's resume slow-mo has to wear off.
var settle_s: float = 0.0
## Real-time delay between the final line and the quit (debug.bench.quit_delay_s).
var quit_delay_s: float = 0.0
## Called with the exit code once the bench is over. Defaults to get_tree().quit.
var quit_game: Callable

var _stage: Stage = Stage.WAITING
var _stats: FrameStats = null
var _last_usec: int = 0
var _stage_start_usec: int = 0
var _jump_requested: bool = false
var _target_started: bool = false
var _target_cleared: bool = false
var _fire_held: bool = false
var _boss: Flagship = null
var _choice_picked: bool = false
var _peak_enemies: int = 0
var _peak_projectiles: int = 0
var _ended: String = ""
var _exit_code: int = -1


func _init() -> void:
	name = "LevelBench"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	if not debug_enabled:
		set_process(false)
		return
	if not quit_game.is_valid():
		quit_game = get_tree().quit
	_stats = FrameStats.new(ceili(maxf(sample_s, 0.0) * DebugTools.BENCH_MAX_FPS))
	# Frame ms must measure work, not the display wait.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Events.wave_started.connect(_on_events_wave_started)
	Events.wave_cleared.connect(_on_events_wave_cleared)
	Log.info("debug", "Level bench: scenario=%s starting (%s, settle %.1f s, sample %.1f s)" % [
		scenario, _target_label(), settle_s, sample_s,
	])
	if not DebugArgs.LEVEL_BENCH_SCENARIOS.has(scenario):
		abort("unknown scenario '%s'" % scenario)
		return
	if director == null or not is_instance_valid(director):
		abort("no WaveDirector in this scene")
		return
	if director.wave_number() >= 1:
		_request_jump()


func _exit_tree() -> void:
	if Events.wave_started.is_connected(_on_events_wave_started):
		Events.wave_started.disconnect(_on_events_wave_started)
	if Events.wave_cleared.is_connected(_on_events_wave_cleared):
		Events.wave_cleared.disconnect(_on_events_wave_cleared)
	if _fire_held:
		_release_fire()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var ms: float = (now - _last_usec) / 1000.0 if _last_usec != 0 else 0.0
	_last_usec = now
	step(now, ms)


## One bench frame at `now_usec` that took `frame_ms` (tests pass fake times).
func step(now_usec: int, frame_ms: float) -> void:
	if _stage == Stage.DONE:
		return
	_click_comms()
	match _stage:
		Stage.DRIVING:
			if scenario == BUSIEST_WAVE:
				if _target_started:
					_enter_settling(now_usec)
			else:
				_drive_flagship(now_usec)
		Stage.SETTLING:
			var settle_lost: String = _target_lost()
			if not settle_lost.is_empty():
				_finish(settle_lost)
			elif now_usec - _stage_start_usec >= int(settle_s * _USEC_PER_S):
				_stage = Stage.SAMPLING
				_stage_start_usec = now_usec
		Stage.SAMPLING:
			var sample_lost: String = _target_lost()
			if not sample_lost.is_empty():
				_finish(sample_lost)
				return
			_stats.add(frame_ms)
			_peak_enemies = maxi(_peak_enemies, get_tree().get_node_count_in_group(Groups.ENEMIES))
			_peak_projectiles = maxi(_peak_projectiles, get_tree().get_node_count_in_group(Groups.PROJECTILES))
			if now_usec - _stage_start_usec >= int(sample_s * _USEC_PER_S):
				_finish(ENDED_TIME)


## Logs `reason` as an ERROR and finishes at once with FAIL (ended=no_target).
func abort(reason: String) -> void:
	if _stage == Stage.DONE:
		return
	Log.error("debug", "Level bench: %s; result=FAIL" % reason)
	_finish(ENDED_NO_TARGET)


# --- Read accessors (tests) -------------------------------------------------------

func stage() -> Stage:
	return _stage


func stats() -> FrameStats:
	return _stats


func ended() -> String:
	return _ended


## 0 (PASS) or 2 (FAIL) once finished, -1 before.
func exit_code() -> int:
	return _exit_code


func is_fire_held() -> bool:
	return _fire_held


# --- Internals --------------------------------------------------------------------

func _target_label() -> String:
	return "wave %d" % target_wave if scenario == BUSIEST_WAVE else "Flagship DESPERATE"


func _on_events_wave_started(index: int, _count: int) -> void:
	if _stage == Stage.WAITING:
		_request_jump()
	elif _stage == Stage.DRIVING and scenario == BUSIEST_WAVE and index == target_wave - 1:
		_target_started = true


func _on_events_wave_cleared(index: int) -> void:
	# Any stage after the jump: a target wave with nothing counted clears inside
	# start_wave, before DRIVING sees it start; SETTLING then ends wave_cleared.
	if scenario == BUSIEST_WAVE and index == target_wave - 1 and _stage != Stage.WAITING and _stage != Stage.DONE:
		_target_cleared = true


## The jump runs deferred: wave_started goes out from inside WaveDirector.start_wave.
func _request_jump() -> void:
	if _jump_requested:
		return
	_jump_requested = true
	_jump.call_deferred()


func _jump() -> void:
	if _stage != Stage.WAITING:
		return
	if director == null or not is_instance_valid(director):
		abort("no WaveDirector in this scene")
		return
	_stage = Stage.DRIVING
	if player != null and is_instance_valid(player):
		player.debug_invincible = true
		if player.warp_mouse.is_valid():
			player.warp_mouse.call(DebugTools.BENCH_AIM)
	if scenario == BUSIEST_WAVE:
		if not director.debug_jump_to_wave(target_wave - 1):
			abort("level %d has no wave %d" % [director.level_id(), target_wave])
			return
		Input.action_press(&"fire_laser")
		_fire_held = true
	else:
		director.debug_skip_to_boss()
		_boss = get_tree().get_first_node_in_group(Groups.BOSS) as Flagship
		if _boss == null:
			abort("no Flagship in level %d" % director.level_id())


## desperate: TURRETS -> kill the turrets (CORE) -> the core dropped to its floor
## (FINAL_CHOICE, whose comms _click_comms answers) -> DESPERATE.
func _drive_flagship(now_usec: int) -> void:
	if _boss == null or not is_instance_valid(_boss) or _boss.is_queued_for_deletion():
		abort("the Flagship is gone before DESPERATE")
		return
	match _boss.phase():
		Flagship.Phase.TURRETS:
			for turret: FlagshipTurret in _boss.turrets():
				if is_instance_valid(turret) and not turret.is_dead():
					turret.apply_damage(maxi(turret.hp, 1), null)
		Flagship.Phase.CORE:
			var core: FlagshipCore = _boss.core()
			if core == null or not is_instance_valid(core) or core.hp_floor() <= 0:
				abort("the Flagship core has no Final Choice floor")
				return
			if not core.invulnerable:
				core.apply_damage(maxi(core.hp - core.hp_floor(), 1), null)
		Flagship.Phase.DESPERATE:
			_enter_settling(now_usec)
		Flagship.Phase.DYING:
			_finish(ENDED_PHASE_LEFT)


## Clicks story comms through; on a Final Choice it picks the first option once.
func _click_comms() -> void:
	if channel == null or not is_instance_valid(channel):
		return
	if channel.is_choosing():
		if not _choice_picked and final_choice != null and is_instance_valid(final_choice) and final_choice.is_shown():
			_choice_picked = true
			final_choice.buttons()[0].pressed.emit()
		return
	if channel.is_showing():
		channel.advance()


func _enter_settling(now_usec: int) -> void:
	_stage = Stage.SETTLING
	_stage_start_usec = now_usec
	Log.info("debug", "Level bench: %s reached (fire %s); settling %.1f s, then sampling %.1f s" % [
		_target_label(), "held" if _fire_held else "off", settle_s, sample_s,
	])


## "" while the target state holds, else the `ended` reason.
func _target_lost() -> String:
	if scenario == BUSIEST_WAVE:
		return ENDED_WAVE_CLEARED if _target_cleared else ""
	if _boss == null or not is_instance_valid(_boss) or _boss.phase() != Flagship.Phase.DESPERATE:
		return ENDED_PHASE_LEFT
	return ""


func _release_fire() -> void:
	Input.action_release(&"fire_laser")
	_fire_held = false


## Releases fire, logs the final line, then quits on a later frame: the real-time
## quit delay gives stdout and the file logger time to drain.
func _finish(ended_reason: String) -> void:
	_stage = Stage.DONE
	_ended = ended_reason
	_exit_code = 0 if DebugTools.bench_passed(_stats) else 2
	if _fire_held:
		_release_fire()
	var count: int = _stats.count() if _stats != null else 0
	Log.info("debug", "Level bench: scenario=%s frames=%d avg=%.2f ms p99=%.2f ms max=%.2f ms enemies=%d projectiles=%d ended=%s renderer=%s window=%s vsync=%d result=%s" % [
		scenario,
		count,
		_stats.average_ms() if _stats != null else 0.0,
		_stats.percentile_ms(99.0) if _stats != null else 0.0,
		_stats.max_ms() if _stats != null else 0.0,
		_peak_enemies,
		_peak_projectiles,
		_ended,
		RenderingServer.get_current_rendering_method(),
		DisplayServer.window_get_size(),
		DisplayServer.window_get_vsync_mode(),
		"PASS" if _exit_code == 0 else "FAIL",
	])
	# Real time, process_always, ignoring time_scale: hit-stop cannot hold the quit.
	# Bound to quit_game itself, so the quit survives this node being freed meanwhile.
	get_tree().create_timer(quit_delay_s, true, false, true).timeout.connect(quit_game.bind(_exit_code))
