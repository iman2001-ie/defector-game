extends Node
## Impact feedback (Pillar 2): one call per hit or death scales the explosion,
## camera shake, hit-stop and SFX with the impact tier. Tier rows come from
## tuning.feedback.tiers (read once in load_tiers()).
##
## The only owner of Engine.time_scale (hit-stop and slow motion). Scene nodes
## register themselves: the level's ShakeCamera and Spawner.
##
## Slow motion (Epic 7 playtest C): slow_motion(scale, hold_s, ramp_s) holds
## time_scale at `scale` for hold_s, then ramps it linearly back to 1.0 over
## ramp_s. Its clock is real time (Time.get_ticks_usec deltas in _process, since
## the frame delta is itself scaled) and doesn't advance while the tree is
## paused; step_slow_motion(real_delta) is the same step for tests. A hit-stop
## composes with it: time_scale stays 0 during the stop and returns to
## slow_motion_scale() (not 1.0) when the stop ends. reset() cancels it, and so
## does the Player leaving the tree (the level ended). The fair resume: every
## PauseArbiter.resumed while a Player (Groups.PLAYER) is in the tree, except
## one caused by PauseArbiter.clear() (a scene change), starts
## slow_motion(feedback.resume_slowmo.scale / hold_s / ramp_s), so a story
## pause's Continue, the Final Choice and the Esc menu all resume gently.
##
## Boss death (Story 7.5): boss_death(pos) plays the Flagship's chain, one
## Boss-death explosion per feedback.boss_death_chain_offsets_px entry at
## pos + offset, spread evenly over feedback.boss_death_chain_s (explosion k at
## k * chain_s / (N - 1); a single entry plays at once). Explosion 0 is a full
## impact (its extras, shake, hit-stop and sfx) inside the call; each later one
## is only its explosion (no extras) plus the tier sfx. The pending ones advance
## in step_chain(delta), which _process calls with game-time delta only while
## the tree isn't paused; reset() drops them. No per-frame allocation.
##
## Playtest pt7-e: each chain explosion k plays its own sound, row k of
## feedback.boss_death_chain_sfx ({sfx, sfx_pitch, sfx_volume_db}; explosion 0's
## row replaces the tier sfx of its impact), so the chain reads as separate
## blasts. A missing row (fewer rows than offsets) uses the tier sfx; a
## malformed one logs an error at load and does the same. Every chain explosion
## plays at feedback.boss_death_chain_anim_speed (Explosion `speed`).
##
## Convoy death (playtest pt7-g): convoy_death(positions, on_step) runs the same
## pending-chain machinery over the convoy's ships: explosion k at positions[k]
## at k * feedback.convoy_death_chain_s / (N - 1), each a Large-tier explosion
## scaled to feedback.convoy_death_explosion_scale with the Large extras, at the
## chain playback speed, playing row k of feedback.convoy_death_chain_sfx (else
## the Large tier sfx). Explosion 0 is a full impact (shake and hit-stop). The
## optional on_step(k) is called as explosion k plays, so the convoy can hide
## that ship. Only one chain is pending at a time; a new one replaces it.

## Where prewarm() spawns its explosions: off-screen left, vertically centred.
const PREWARM_POSITION: Vector2 = Vector2(-1000, 540)
## The screen-space extra prewarm() leaves out (it has nothing to warm up and
## would flash the whole screen).
const PREWARM_SKIPPED_EXTRA: StringName = &"white_flash"
## Slack for the chain's float steps (120 steps of 1/60 s reach 2.0 s).
const CHAIN_EPSILON_S: float = 0.0001

## One cached row per tier, indexed by ImpactTier.
var _tiers: Array[Dictionary] = []
var _camera: ShakeCamera = null
var _spawner: Spawner = null
var _hit_stop_end_usec: int = 0
var _hit_stop_serial: int = 0
## feedback.boss_death_chain_s and feedback.boss_death_chain_offsets_px, cached
## in load_tiers().
var _chain_s: float = 0.0
var _chain_offsets: PackedVector2Array = PackedVector2Array()
## The pending chain: one position and start time per explosion; _chain_next
## is the next one to play (== size when none is pending).
var _chain_positions: PackedVector2Array = PackedVector2Array()
var _chain_times: PackedFloat32Array = PackedFloat32Array()
var _chain_next: int = 0
var _chain_t: float = 0.0
## feedback.boss_death_chain_sfx: one sfx row per chain explosion ({} = the tier
## sfx), and feedback.boss_death_chain_anim_speed, cached in load_tiers().
var _chain_sfx: Array[Dictionary] = []
var _chain_anim_speed: float = 1.0
## feedback.convoy_death_chain_s, convoy_death_explosion_scale and
## convoy_death_chain_sfx, cached in load_tiers().
var _convoy_chain_s: float = 0.0
var _convoy_scale: float = 1.0
var _convoy_sfx: Array[Dictionary] = []
## The pending chain's settings (the boss's or the convoy's): the tier row its
## explosions use, its sound rows and their fallback, whether every explosion
## keeps the row's extras (else only explosion 0 does), and the step callback.
var _active_row: Dictionary = {}
var _active_sfx: Array[Dictionary] = []
var _active_fallback_sfx: Dictionary = {}
var _active_step_extras: bool = false
var _active_on_step: Callable = Callable()
## Slow motion: the current target scale (1.0 when idle), the scale it started
## at, the real seconds of hold left, the ramp length and the real seconds into
## the ramp. _slow_last_usec is the real clock at the last _process.
var _slow_active: bool = false
var _slow_scale: float = 1.0
var _slow_base: float = 1.0
var _slow_hold_left: float = 0.0
var _slow_ramp_s: float = 0.0
var _slow_ramp_t: float = 0.0
var _slow_last_usec: int = 0
## feedback.resume_slowmo.scale / hold_s / ramp_s, cached in load_tiers().
var _resume_scale: float = 1.0
var _resume_hold_s: float = 0.0
var _resume_ramp_s: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_tiers()
	# PauseArbiter is an earlier autoload, so it is ready here.
	PauseArbiter.resumed.connect(_on_pause_arbiter_resumed)


func _process(delta: float) -> void:
	var paused: bool = get_tree().paused
	if _chain_next < _chain_positions.size() and not paused:
		step_chain(delta)
	if _slow_active:
		var now: int = Time.get_ticks_usec()
		var real_delta: float = (now - _slow_last_usec) / 1000000.0
		_slow_last_usec = now
		if paused:
			# The slow-motion clock doesn't advance while the tree is paused.
			return
		if get_tree().get_first_node_in_group(Groups.PLAYER) == null:
			_end_slow_motion()
			return
		step_slow_motion(real_delta)


## Reads every tier row from tuning (missing keys log through Config), and the
## boss-death chain's duration and offsets.
func load_tiers() -> void:
	_load_chain()
	_resume_scale = Config.num("feedback.resume_slowmo.scale")
	_resume_hold_s = Config.num("feedback.resume_slowmo.hold_s")
	_resume_ramp_s = Config.num("feedback.resume_slowmo.ramp_s")
	_tiers.clear()
	for tier_name: String in ImpactTier.NAMES:
		var key: String = "feedback.tiers.%s" % tier_name
		var raw: Dictionary = Config.section(key)
		var extras: Array[StringName] = []
		var raw_extras: Variant = raw.get("extras", [])
		if raw_extras is Array:
			for extra: Variant in raw_extras as Array:
				extras.append(StringName(str(extra)))
		_tiers.append({
			"explosion_scale": Config.num(key + ".explosion_scale"),
			"shake_px": Config.num(key + ".shake_px"),
			"shake_s": Config.num(key + ".shake_s"),
			"hit_stop_ms": Config.num(key + ".hit_stop_ms"),
			"sfx_pitch": Config.num(key + ".sfx_pitch"),
			"sfx_volume_db": Config.num(key + ".sfx_volume_db"),
			"sfx": StringName(str(raw.get("sfx", ""))),
			"extras": extras,
		})


## The cached row for a tier (a copy), or {} when out of range.
func tier_row(tier: int) -> Dictionary:
	if tier < 0 or tier >= _tiers.size():
		return {}
	return _tiers[tier].duplicate(true)


func register_camera(c: ShakeCamera) -> void:
	_camera = c


func unregister_camera(c: ShakeCamera) -> void:
	if _camera == c:
		_camera = null


func register_spawner(s: Spawner) -> void:
	_spawner = s


func unregister_spawner(s: Spawner) -> void:
	if _spawner == s:
		_spawner = null


## Explosion + shake + hit-stop + SFX for one impact of the given tier.
func impact(tier: int, position: Vector2) -> void:
	if tier < 0 or tier >= _tiers.size():
		Log.error("combat", "Feedback.impact: unknown tier %d" % tier)
		return
	var row: Dictionary = _tiers[tier]
	_impact_row(row, position, row, 1.0)


## A full impact of `row` at `position` whose sound comes from `sfx_row` (at
## `pitch_jitter`) and whose explosion plays at `speed`.
func _impact_row(row: Dictionary, position: Vector2, sfx_row: Dictionary, speed: float, pitch_jitter: float = Audio.DEFAULT_PITCH_JITTER) -> void:
	_spawn_explosion_with(row, position, row["extras"] as Array, speed)
	_shake(row)
	var stop_ms: float = row["hit_stop_ms"]
	if stop_ms > 0.0:
		hit_stop(stop_ms)
	_play_sfx(sfx_row, pitch_jitter)


## Shakes the registered camera with the tier's shake_px / shake_s only: no
## explosion, hit-stop or SFX (Story 5.4, a comms cut-off). An unknown tier logs
## an error and does nothing; with no camera it does nothing.
func shake_tier(tier: int) -> void:
	if tier < 0 or tier >= _tiers.size():
		Log.error("combat", "Feedback.shake_tier: unknown tier %d" % tier)
		return
	_shake(_tiers[tier])


## Shakes the registered camera by `px` pixels for `s` seconds only: no
## explosion, hit-stop or SFX (the comms cut-off's own shake, GDD decision #43).
## A no-op when either value isn't above 0 or no camera is registered.
func shake(px: float, s: float) -> void:
	if _camera != null and is_instance_valid(_camera) and px > 0.0 and s > 0.0:
		_camera.shake(px, s)


## Freezes time for ms milliseconds. Overlapping stops keep the longest remaining
## one; they never stack. Stale timers are ignored through the serial.
func hit_stop(ms: float) -> void:
	if ms <= 0.0:
		return
	var end_usec: int = Time.get_ticks_usec() + int(ms * 1000.0)
	if end_usec <= _hit_stop_end_usec:
		return
	_hit_stop_end_usec = end_usec
	_hit_stop_serial += 1
	Engine.time_scale = 0.0
	get_tree().create_timer(ms / 1000.0, true, false, true).timeout.connect(_end_hit_stop.bind(_hit_stop_serial))


func is_hit_stopped() -> bool:
	return _hit_stop_end_usec != 0


## Slows time to `scale` (clamped to 0-1) for `hold_s` real seconds, then ramps
## it linearly back to 1.0 over `ramp_s` real seconds. A new call replaces a
## slow motion in progress. Under a hit-stop time_scale stays 0 until the stop
## ends. With hold_s and ramp_s both 0 or less it does nothing.
func slow_motion(scale: float, hold_s: float, ramp_s: float) -> void:
	if hold_s <= 0.0 and ramp_s <= 0.0:
		return
	_slow_active = true
	_slow_base = clampf(scale, 0.0, 1.0)
	_slow_scale = _slow_base
	_slow_hold_left = maxf(hold_s, 0.0)
	_slow_ramp_s = maxf(ramp_s, 0.0)
	_slow_ramp_t = 0.0
	_slow_last_usec = Time.get_ticks_usec()
	_apply_time_scale()


## The slow motion's current target scale; 1.0 when none is running.
func slow_motion_scale() -> float:
	return _slow_scale if _slow_active else 1.0


func is_slow_motion() -> bool:
	return _slow_active


## Advances the slow motion by `real_delta` real seconds: the hold first, then
## the ramp; at the end of the ramp the scale is 1.0 and it stops. _process
## calls it with the real-time delta only while the tree isn't paused.
func step_slow_motion(real_delta: float) -> void:
	if not _slow_active:
		return
	var left: float = maxf(real_delta, 0.0)
	if _slow_hold_left > 0.0:
		var used: float = minf(left, _slow_hold_left)
		_slow_hold_left -= used
		left -= used
		if _slow_hold_left > 0.0:
			return
	_slow_ramp_t += left
	if _slow_ramp_t >= _slow_ramp_s:
		_end_slow_motion()
		return
	_slow_scale = lerpf(_slow_base, 1.0, _slow_ramp_t / _slow_ramp_s)
	_apply_time_scale()


## Spawns one explosion per tier off-screen (shader and particle warm-up) with
## no shake, hit-stop or sound, and without the screen-space white flash.
func prewarm() -> void:
	for row: Dictionary in _tiers:
		var extras: Array[StringName] = (row["extras"] as Array[StringName]).duplicate()
		extras.erase(PREWARM_SKIPPED_EXTRA)
		_spawn_explosion_with(row, PREWARM_POSITION, extras)


## The Flagship's death (Story 7.5): explosion 0 of the chain plays now as a full
## Boss-death impact at pos + offsets[0]; the rest are queued for step_chain at
## k * chain_s / (N - 1). A new call replaces a chain still pending. Without
## offsets it logs an error and plays the single impact at pos.
func boss_death(pos: Vector2) -> void:
	var count: int = _chain_offsets.size()
	if count == 0:
		Log.error("combat", "feedback.boss_death_chain_offsets_px is empty; one boss_death impact instead")
		impact(ImpactTier.BOSS_DEATH, pos)
		return
	_chain_positions.resize(count)
	_chain_times.resize(count)
	for k: int in count:
		_chain_positions[k] = pos + _chain_offsets[k]
		_chain_times[k] = 0.0 if count == 1 else float(k) * _chain_s / float(count - 1)
	_chain_t = 0.0
	_chain_next = 1
	_active_row = _tiers[ImpactTier.BOSS_DEATH]
	_active_sfx = _chain_sfx
	_active_fallback_sfx = _active_row
	_active_step_extras = false
	_active_on_step = Callable()
	_impact_row(_active_row, _chain_positions[0], chain_sfx_row(0), _chain_anim_speed, 0.0)


## The convoy's death (playtest pt7-g): one explosion per entry of `positions`
## (the ships' centres), spread evenly over feedback.convoy_death_chain_s.
## Explosion 0 plays now as a full impact; the rest are queued for step_chain.
## on_step(k), when valid, is called as explosion k plays. A new call replaces
## a chain still pending. An empty `positions` does nothing.
func convoy_death(positions: Array[Vector2], on_step: Callable = Callable()) -> void:
	var count: int = positions.size()
	if count == 0:
		return
	if ImpactTier.LARGE >= _tiers.size():
		Log.error("combat", "convoy_death: no Large tier row; the ships are cleared without explosions")
		if on_step.is_valid():
			for k: int in count:
				on_step.call(k)
		return
	_chain_positions.resize(count)
	_chain_times.resize(count)
	for k: int in count:
		_chain_positions[k] = positions[k]
		_chain_times[k] = 0.0 if count == 1 else float(k) * _convoy_chain_s / float(count - 1)
	_chain_t = 0.0
	_chain_next = 1
	_active_row = _tiers[ImpactTier.LARGE].duplicate()
	_active_row["explosion_scale"] = _convoy_scale
	_active_sfx = _convoy_sfx
	_active_fallback_sfx = _tiers[ImpactTier.LARGE]
	_active_step_extras = true
	_active_on_step = on_step
	_impact_row(_active_row, _chain_positions[0], _active_sfx_row(0), _chain_anim_speed, 0.0)
	_call_on_step(0)


## Advances the pending chain (the boss's or the convoy's) by `delta` seconds of
## game time: each explosion whose time has come plays (the chain row's scale;
## the boss chain without extras, the convoy chain with them) with its sound
## row, then calls the chain's on_step. Does nothing when no chain is pending.
func step_chain(delta: float) -> void:
	if _chain_next >= _chain_positions.size():
		return
	_chain_t += delta
	while _chain_next < _chain_positions.size() and _chain_t + CHAIN_EPSILON_S >= _chain_times[_chain_next]:
		var k: int = _chain_next
		var extras: Array = _active_row.get("extras", []) as Array if _active_step_extras else []
		_spawn_explosion_with(_active_row, _chain_positions[k], extras, _chain_anim_speed)
		_play_sfx(_active_sfx_row(k), 0.0)
		_chain_next += 1
		_call_on_step(k)


## The sound row of chain explosion `k`: its feedback.boss_death_chain_sfx row,
## else the Boss-death tier's own sfx, pitch and volume.
func chain_sfx_row(k: int) -> Dictionary:
	if k >= 0 and k < _chain_sfx.size() and not _chain_sfx[k].is_empty():
		return _chain_sfx[k]
	return _tiers[ImpactTier.BOSS_DEATH] if ImpactTier.BOSS_DEATH < _tiers.size() else {}


## The convoy chain's sound row `k`: its feedback.convoy_death_chain_sfx row,
## else the Large tier's own sfx, pitch and volume.
func convoy_sfx_row(k: int) -> Dictionary:
	if k >= 0 and k < _convoy_sfx.size() and not _convoy_sfx[k].is_empty():
		return _convoy_sfx[k]
	return _tiers[ImpactTier.LARGE] if ImpactTier.LARGE < _tiers.size() else {}


## The pending chain's sound row `k` (its own row, else its fallback).
func _active_sfx_row(k: int) -> Dictionary:
	if k >= 0 and k < _active_sfx.size() and not _active_sfx[k].is_empty():
		return _active_sfx[k]
	return _active_fallback_sfx


func _call_on_step(k: int) -> void:
	if _active_on_step.is_valid():
		_active_on_step.call(k)


## Explosions of the pending chain (boss or convoy) still to play (tests, F1).
func chain_pending() -> int:
	return maxi(_chain_positions.size() - _chain_next, 0)


## Ends any hit-stop at once; pending timers become stale. Cancels slow motion
## and drops a pending chain (boss or convoy) without calling its on_step.
func reset() -> void:
	_hit_stop_serial += 1
	_hit_stop_end_usec = 0
	_slow_active = false
	_slow_scale = 1.0
	Engine.time_scale = 1.0
	_chain_next = _chain_positions.size()
	_active_on_step = Callable()


## Shakes the registered camera with the row's shake_px / shake_s (see shake).
func _shake(row: Dictionary) -> void:
	shake(row["shake_px"] as float, row["shake_s"] as float)


## Plays the row's sfx. Chain rows pass a jitter of 0: each row already sets
## its own pitch, and jitter could push one below the 0.9 floor.
func _play_sfx(row: Dictionary, pitch_jitter: float = Audio.DEFAULT_PITCH_JITTER) -> void:
	if row.is_empty():
		return
	Audio.play_sfx(row["sfx"] as StringName, pitch_jitter, row["sfx_volume_db"] as float, row["sfx_pitch"] as float)


## Spawns one explosion at the row's scale with the given extras and playback
## speed; nothing without a registered spawner.
func _spawn_explosion_with(row: Dictionary, position: Vector2, extras: Array, speed: float = 1.0) -> void:
	if _spawner == null or not is_instance_valid(_spawner):
		return
	_spawner.spawn_explosion({
		"position": position,
		"scale": row["explosion_scale"],
		"extras": extras,
		"speed": speed,
	})


## Caches feedback.boss_death_chain_s and the chain offsets (each a [x, y]
## pair; a malformed entry logs an error and is skipped) and drops a pending
## chain.
func _load_chain() -> void:
	_chain_s = maxf(Config.num("feedback.boss_death_chain_s"), 0.0)
	_chain_offsets.clear()
	var raw: Variant = Config.section("feedback").get("boss_death_chain_offsets_px")
	if not (raw is Array):
		Log.error("data", "feedback.boss_death_chain_offsets_px missing or not an array")
	else:
		for entry: Variant in raw as Array:
			var pair: Array = entry as Array if entry is Array else []
			if pair.size() != 2 or not ((pair[0] is float or pair[0] is int) and (pair[1] is float or pair[1] is int)):
				Log.error("data", "feedback.boss_death_chain_offsets_px entry %s is not an [x, y] pair; skipped" % str(entry))
				continue
			_chain_offsets.append(Vector2(float(pair[0]), float(pair[1])))
	_chain_anim_speed = Config.num("feedback.boss_death_chain_anim_speed")
	if _chain_anim_speed <= 0.0:
		Log.error("data", "feedback.boss_death_chain_anim_speed must be > 0; using 1.0")
		_chain_anim_speed = 1.0
	_chain_anim_speed = maxf(_chain_anim_speed, Explosion.MIN_SPEED)
	_load_chain_sfx()
	_convoy_chain_s = maxf(Config.num("feedback.convoy_death_chain_s"), 0.0)
	_convoy_scale = maxf(Config.num("feedback.convoy_death_explosion_scale"), 0.0)
	_convoy_sfx = _load_sfx_rows("convoy_death_chain_sfx")
	_chain_positions.clear()
	_chain_times.clear()
	_chain_next = 0
	_active_on_step = Callable()


## Caches feedback.boss_death_chain_sfx (see _load_sfx_rows).
func _load_chain_sfx() -> void:
	_chain_sfx = _load_sfx_rows("boss_death_chain_sfx")


## The rows of feedback.<key>: each entry a {sfx (non-empty string), sfx_pitch
## (> 0), sfx_volume_db (numbers)} row; a malformed entry logs an error and
## becomes {} (the tier sfx). A missing key means every explosion uses the tier
## sfx; a non-array logs an error and does the same.
func _load_sfx_rows(key: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var raw: Variant = Config.section("feedback").get(key, [])
	if not (raw is Array):
		Log.error("data", "feedback.%s is not an array; the chain uses the tier sfx" % key)
		return rows
	for entry: Variant in raw as Array:
		var row: Dictionary = entry as Dictionary if entry is Dictionary else {}
		var pitch: Variant = row.get("sfx_pitch")
		var volume: Variant = row.get("sfx_volume_db")
		var sfx: Variant = row.get("sfx")
		if not (sfx is String) or (sfx as String).is_empty() or not (pitch is float or pitch is int) or float(pitch) <= 0.0 or not (volume is float or volume is int):
			Log.error("data", "feedback.%s entry %s is not a {sfx, sfx_pitch, sfx_volume_db} row; the tier sfx plays instead" % [key, str(entry)])
			rows.append({})
			continue
		rows.append({
			"sfx": StringName(sfx as String),
			"sfx_pitch": float(pitch),
			"sfx_volume_db": float(volume),
		})
	return rows


func _end_hit_stop(serial: int) -> void:
	if serial != _hit_stop_serial:
		return
	_hit_stop_end_usec = 0
	Engine.time_scale = slow_motion_scale()


## Writes the slow-motion scale unless a hit-stop holds time at 0.
func _apply_time_scale() -> void:
	if not is_hit_stopped():
		Engine.time_scale = slow_motion_scale()


func _end_slow_motion() -> void:
	_slow_active = false
	_slow_scale = 1.0
	_apply_time_scale()


## The fair resume: slow motion from feedback.resume_slowmo, only in a level
## (a Player in the tree) and never for PauseArbiter.clear() (a scene change).
func _on_pause_arbiter_resumed() -> void:
	if PauseArbiter.is_clearing():
		return
	if get_tree().get_first_node_in_group(Groups.PLAYER) == null:
		return
	slow_motion(_resume_scale, _resume_hold_s, _resume_ramp_s)
