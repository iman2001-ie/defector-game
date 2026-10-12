extends GutTest
## Feedback: tier rows from tuning, impact (explosion + shake + hit-stop + SFX),
## hit-stop overlap rules, reset, prewarm, registration. Story 7.5: the
## boss-death chain (boss_death, step_chain, the pause freeze, reset).

const CONTAINERS: Array[String] = ["Projectiles", "Enemies", "Asteroids", "Effects"]

var _world: Node2D
var _effects: Node2D
var _spawner: Spawner
var _camera: ShakeCamera


func after_each() -> void:
	Feedback.reset()
	PauseArbiter.clear()
	Log.sink = Callable()
	Config.load_data()
	Feedback.load_tiers()
	_world = null
	_effects = null
	_spawner = null
	_camera = null


## A test World with every container, its Spawner and a ShakeCamera (both register).
func _setup_listeners() -> void:
	_world = Node2D.new()
	for container: String in CONTAINERS:
		var node: Node2D = Node2D.new()
		node.name = container
		_world.add_child(node)
	add_child_autofree(_world)
	_effects = _world.get_node("Effects") as Node2D
	_spawner = Spawner.new()
	_spawner.world = _world
	add_child_autofree(_spawner)
	_camera = ShakeCamera.new()
	add_child_autofree(_camera)
	# Tests read the amplitude; frames must not decay it.
	_camera.set_process(false)


func _explosions() -> Array[Explosion]:
	var out: Array[Explosion] = []
	for child: Node in _effects.get_children():
		if child is Explosion:
			out.append(child as Explosion)
	return out


## Awaits t seconds of real time (scaled timers freeze while time_scale is 0).
func _real_wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


## Milliseconds since start_usec.
func _ms_since(start_usec: int) -> float:
	return (Time.get_ticks_usec() - start_usec) / 1000.0


## A frame gap above this counts as a stall. The hit-stop timer is seen at most
## one gap after its deadline (it ticks whole frame deltas, and process_frame is
## emitted before that frame's timers run), so deadline + two gaps of <= 60 ms
## (100 + 120 = 220 ms) stays under the 250 ms "resumed promptly" margin; a late
## resume with a larger gap is a slow headless frame, not a stuck hit-stop.
const STALL_GAP_MS: float = 60.0

## Largest gap (ms) between observations in the last _await_resume, counting the
## time already elapsed since start_usec before polling began.
var _max_gap_ms: float = 0.0


## Awaits process frames until time_scale is back to 1 (or limit_ms passes);
## returns the elapsed ms since start_usec at that moment. Records the largest
## gap between observations in _max_gap_ms.
func _await_resume(start_usec: int, limit_ms: float) -> float:
	var last_ms: float = _ms_since(start_usec)
	_max_gap_ms = last_ms
	while Engine.time_scale < 0.5 and last_ms < limit_ms:
		await get_tree().process_frame
		var now_ms: float = _ms_since(start_usec)
		_max_gap_ms = maxf(_max_gap_ms, now_ms - last_ms)
		last_ms = now_ms
	return _ms_since(start_usec)


## Asserts resumed_ms < bound_ms, unless it was missed while a frame stalled
## (largest gap > STALL_GAP_MS), which is reported as pending instead.
func _assert_resumed_promptly(resumed_ms: float, bound_ms: float) -> void:
	if resumed_ms >= bound_ms and _max_gap_ms > STALL_GAP_MS:
		pending("resume seen at %.1f ms (bound %.1f ms) after a %.1f ms frame stall" % [resumed_ms, bound_ms, _max_gap_ms])
		return
	assert_lt(resumed_ms, bound_ms, "resumed promptly (at %.1f ms, largest frame gap %.1f ms)" % [resumed_ms, _max_gap_ms])


# --- Tier data ---------------------------------------------------------------

func test_tier_names_in_enum_order() -> void:
	assert_eq(ImpactTier.NAMES.size(), 7)
	for i: int in ImpactTier.NAMES.size():
		assert_eq(ImpactTier.from_name(ImpactTier.NAMES[i]), i, ImpactTier.NAMES[i])


func test_tier_rows_from_tuning() -> void:
	# name: [scale, shake_px, shake_s, hit_stop_ms]
	var expected: Dictionary = {
		ImpactTier.SMALL: [0.5, 0.0, 0.0, 0.0],
		ImpactTier.MEDIUM: [1.0, 4.0, 0.15, 0.0],
		ImpactTier.LARGE: [2.0, 8.0, 0.25, 40.0],
		ImpactTier.BOSS_PART: [1.5, 6.0, 0.2, 30.0],
		ImpactTier.BOSS_DEATH: [4.0, 20.0, 1.0, 150.0],
		ImpactTier.PLAYER_HIT: [0.5, 6.0, 0.2, 50.0],
		ImpactTier.PLAYER_DEATH: [2.0, 12.0, 0.5, 100.0],
	}
	for tier: int in expected:
		var row: Dictionary = Feedback.tier_row(tier)
		var values: Array = expected[tier]
		var label: String = ImpactTier.NAMES[tier]
		assert_almost_eq(row.get("explosion_scale", -1.0) as float, values[0] as float, 0.0001, label + " scale")
		assert_almost_eq(row.get("shake_px", -1.0) as float, values[1] as float, 0.0001, label + " shake_px")
		assert_almost_eq(row.get("shake_s", -1.0) as float, values[2] as float, 0.0001, label + " shake_s")
		assert_almost_eq(row.get("hit_stop_ms", -1.0) as float, values[3] as float, 0.0001, label + " hit_stop_ms")
	assert_eq(Feedback.tier_row(ImpactTier.SMALL).get("extras"), [&"sparks"] as Array[StringName])
	assert_eq(Feedback.tier_row(ImpactTier.MEDIUM).get("extras"), [&"debris"] as Array[StringName])
	assert_eq(Feedback.tier_row(ImpactTier.LARGE).get("extras"), [&"debris", &"shockwave"] as Array[StringName])
	assert_almost_eq(Feedback.tier_row(ImpactTier.LARGE).get("sfx_pitch", -1.0) as float, 0.8, 0.0001)
	assert_eq(Feedback.tier_row(ImpactTier.LARGE).get("sfx"), &"explosion_large")
	assert_eq(Feedback.tier_row(99), {}, "out of range")


func test_tier_volumes() -> void:
	var expected: Array[float] = [-6.0, -3.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for tier: int in expected.size():
		assert_almost_eq(Feedback.tier_row(tier).get("sfx_volume_db", 99.0) as float, expected[tier], 0.0001, ImpactTier.NAMES[tier])


func test_process_mode_always() -> void:
	assert_eq(Feedback.process_mode, Node.PROCESS_MODE_ALWAYS)


# --- impact() ----------------------------------------------------------------

func test_large_impact() -> void:
	_setup_listeners()
	Feedback.impact(ImpactTier.LARGE, Vector2(500, 400))
	var explosions: Array[Explosion] = _explosions()
	assert_eq(explosions.size(), 1, "one explosion")
	if explosions.size() == 1:
		var e: Explosion = explosions[0]
		assert_eq(e.global_position, Vector2(500, 400))
		assert_eq(e.scale, Vector2(2, 2))
		assert_true((e.get_node("Debris") as GPUParticles2D).emitting, "debris")
		assert_true((e.get_node("Shockwave") as Node2D).visible, "shockwave")
		assert_false((e.get_node("Sparks") as GPUParticles2D).emitting, "no sparks")
	assert_almost_eq(_camera.current_amplitude(), 8.0, 0.0001, "shake 8 px")
	assert_eq(Engine.time_scale, 0.0, "hit-stop")
	assert_true(Feedback.is_hit_stopped())
	var player: AudioStreamPlayer = Audio.newest_player()
	assert_not_null(player)
	if player != null:
		assert_eq(player.stream, Audio.SFX[&"explosion_large"])
		assert_between(player.pitch_scale, 0.76, 0.84, "pitch 0.8 +-5%")
		assert_almost_eq(player.volume_db, 0.0, 0.0001)


func test_small_impact() -> void:
	_setup_listeners()
	Feedback.impact(ImpactTier.SMALL, Vector2(300, 300))
	var explosions: Array[Explosion] = _explosions()
	assert_eq(explosions.size(), 1, "one explosion")
	if explosions.size() == 1:
		var e: Explosion = explosions[0]
		assert_eq(e.scale, Vector2(0.5, 0.5))
		assert_true((e.get_node("Sparks") as GPUParticles2D).emitting, "sparks")
		assert_false((e.get_node("Debris") as GPUParticles2D).emitting, "no debris")
	assert_eq(_camera.current_amplitude(), 0.0, "no shake")
	assert_eq(Engine.time_scale, 1.0, "no hit-stop")
	assert_false(Feedback.is_hit_stopped())
	var player: AudioStreamPlayer = Audio.newest_player()
	assert_not_null(player)
	if player != null:
		assert_eq(player.stream, Audio.SFX[&"explosion_small"])
		assert_almost_eq(player.volume_db, -6.0, 0.0001)


func test_medium_impact_shakes_without_hit_stop() -> void:
	_setup_listeners()
	Feedback.impact(ImpactTier.MEDIUM, Vector2(300, 300))
	assert_almost_eq(_camera.current_amplitude(), 4.0, 0.0001)
	assert_eq(Engine.time_scale, 1.0)
	assert_eq(_explosions()[0].scale, Vector2(1, 1))


func test_no_listeners_still_plays_sfx() -> void:
	Feedback.impact(ImpactTier.MEDIUM, Vector2(300, 300))
	var player: AudioStreamPlayer = Audio.newest_player()
	assert_not_null(player)
	if player != null:
		assert_eq(player.stream, Audio.SFX[&"explosion_medium"])
		assert_almost_eq(player.volume_db, -3.0, 0.0001)


func test_bad_tier_logs_and_does_nothing() -> void:
	_setup_listeners()
	Audio.play_sfx(&"laser_zap")
	var before: AudioStreamPlayer = Audio.newest_player()
	Feedback.impact(99, Vector2(300, 300))
	assert_push_error("tier")
	assert_eq(_explosions().size(), 0, "no explosion")
	assert_eq(_camera.current_amplitude(), 0.0, "no shake")
	assert_eq(Engine.time_scale, 1.0, "no hit-stop")
	assert_eq(Audio.newest_player(), before, "no sound")
	Feedback.impact(-1, Vector2(300, 300))
	assert_push_error("tier")


func test_unregistered_camera_not_shaken() -> void:
	_setup_listeners()
	remove_child(_camera)
	Feedback.impact(ImpactTier.LARGE, Vector2(300, 300))
	assert_eq(_camera.current_amplitude(), 0.0, "camera left the tree")
	_camera.free()
	_camera = null


func test_unregister_spawner_only_if_current() -> void:
	_setup_listeners()
	var other: Spawner = Spawner.new()
	Feedback.unregister_spawner(other)
	other.free()
	Feedback.impact(ImpactTier.SMALL, Vector2(300, 300))
	assert_eq(_explosions().size(), 1, "the registered spawner is kept")


func test_spawner_without_effects_does_not_register() -> void:
	_setup_listeners()
	var bare: Node2D = Node2D.new()
	for container: String in ["Projectiles", "Enemies", "Asteroids"]:
		var node: Node2D = Node2D.new()
		node.name = container
		bare.add_child(node)
	add_child_autofree(bare)
	var no_fx: Spawner = Spawner.new()
	no_fx.world = bare
	add_child_autofree(no_fx)
	assert_null(no_fx.spawn_explosion({"position": Vector2.ZERO}), "no Effects, no explosion")
	Feedback.impact(ImpactTier.SMALL, Vector2(300, 300))
	assert_eq(_explosions().size(), 1, "the spawner with Effects is still registered")


func test_spawner_unregisters_on_exit() -> void:
	_setup_listeners()
	remove_child(_spawner)
	Feedback.impact(ImpactTier.SMALL, Vector2(300, 300))
	assert_eq(_explosions().size(), 0, "no spawner registered")
	_spawner.free()
	_spawner = null


# --- shake_tier() (Story 5.4) ------------------------------------------------

func test_shake_tier_shakes_only() -> void:
	_setup_listeners()
	Audio.play_sfx(&"laser_zap")
	var before: AudioStreamPlayer = Audio.newest_player()
	Feedback.shake_tier(ImpactTier.LARGE)
	assert_almost_eq(_camera.current_amplitude(), 8.0, 0.0001, "large shake_px")
	assert_eq(_explosions().size(), 0, "no explosion")
	assert_eq(Engine.time_scale, 1.0, "no hit-stop")
	assert_false(Feedback.is_hit_stopped())
	assert_eq(Audio.newest_player(), before, "no sound")


func test_shake_tier_small_has_no_shake() -> void:
	_setup_listeners()
	Feedback.shake_tier(ImpactTier.SMALL)
	assert_eq(_camera.current_amplitude(), 0.0, "small has shake_px 0")


func test_shake_tier_bad_tier_logs_and_does_nothing() -> void:
	_setup_listeners()
	Feedback.shake_tier(99)
	assert_push_error("Feedback.shake_tier: unknown tier 99")
	assert_eq(_camera.current_amplitude(), 0.0, "nothing shakes")
	Feedback.shake_tier(-1)
	assert_push_error("Feedback.shake_tier: unknown tier -1")


func test_shake_tier_without_camera_is_a_no_op() -> void:
	Feedback.shake_tier(ImpactTier.LARGE)
	assert_eq(Engine.time_scale, 1.0)
	assert_false(Feedback.is_hit_stopped())


# --- shake() (GDD decision #43) ----------------------------------------------

func test_shake_shakes_only() -> void:
	_setup_listeners()
	Audio.play_sfx(&"laser_zap")
	var before: AudioStreamPlayer = Audio.newest_player()
	Feedback.shake(18.0, 0.9)
	assert_almost_eq(_camera.current_amplitude(), 18.0, 0.0001, "18 px")
	assert_eq(_explosions().size(), 0, "no explosion")
	assert_eq(Engine.time_scale, 1.0, "no hit-stop")
	assert_false(Feedback.is_hit_stopped())
	assert_eq(Audio.newest_player(), before, "no sound")


func test_shake_non_positive_values_are_a_no_op() -> void:
	_setup_listeners()
	for args: Array in [[0.0, 1.0], [18.0, 0.0], [-5.0, 1.0], [18.0, -1.0]]:
		Feedback.shake(args[0] as float, args[1] as float)
		assert_eq(_camera.current_amplitude(), 0.0, "no shake for %s" % [args])


func test_shake_without_camera_is_a_no_op() -> void:
	Feedback.shake(18.0, 0.9)
	assert_eq(Engine.time_scale, 1.0)
	assert_false(Feedback.is_hit_stopped())


func test_tier_shake_goes_through_shake() -> void:
	_setup_listeners()
	Feedback.shake_tier(ImpactTier.MEDIUM)
	var row: Dictionary = Feedback.tier_row(ImpactTier.MEDIUM)
	assert_almost_eq(_camera.current_amplitude(), row.get("shake_px", -1.0) as float, 0.0001, "the medium row's shake_px")


# --- Hit-stop ----------------------------------------------------------------

func test_hit_stop_zero_or_negative_ignored() -> void:
	Feedback.hit_stop(0.0)
	Feedback.hit_stop(-5.0)
	assert_eq(Engine.time_scale, 1.0)
	assert_false(Feedback.is_hit_stopped())


## Timers count down whole frame deltas, and the first delta after a timer is
## created also covers the time before it. Starting right after a frame boundary
## keeps that error small; the thresholds sit between the two candidate end times.
func _sync_to_frame() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func test_hit_stop_overlap_keeps_longest() -> void:
	await _sync_to_frame()
	var start: int = Time.get_ticks_usec()
	Feedback.hit_stop(100.0)
	assert_eq(Engine.time_scale, 0.0)
	await _real_wait(0.02)
	var second_ms: float = _ms_since(start)
	Feedback.hit_stop(40.0)
	var resumed_ms: float = await _await_resume(start, 400.0)
	assert_eq(Engine.time_scale, 1.0, "resumed (at %.1f ms)" % resumed_ms)
	assert_false(Feedback.is_hit_stopped())
	# Ending with the shorter second stop would resume near second_ms + 40 (~60 ms).
	if second_ms + 40.0 < 70.0:
		assert_gte(resumed_ms, 80.0, "held for the longest stop (second at %.1f ms)" % second_ms)
	else:
		pending("second hit_stop came too late (%.1f ms) to tell the stops apart" % second_ms)
	_assert_resumed_promptly(resumed_ms, 250.0)


func test_hit_stop_extend() -> void:
	await _sync_to_frame()
	var start: int = Time.get_ticks_usec()
	Feedback.hit_stop(40.0)
	await _real_wait(0.02)
	var second_ms: float = _ms_since(start)
	Feedback.hit_stop(100.0)
	var resumed_ms: float = await _await_resume(start, 500.0)
	assert_eq(Engine.time_scale, 1.0, "resumed (at %.1f ms)" % resumed_ms)
	# The first (stale) 40 ms timer must not end the extended freeze (~second_ms + 100).
	if second_ms > 50.0:
		pending("second hit_stop came too late (%.1f ms) to tell the stops apart" % second_ms)
		return
	assert_gte(resumed_ms, maxf(80.0, second_ms + 70.0), "extended (second at %.1f ms)" % second_ms)
	_assert_resumed_promptly(resumed_ms, second_ms + 250.0)


func test_reset_ends_hit_stop_and_ignores_stale_timer() -> void:
	await _sync_to_frame()
	Feedback.hit_stop(40.0)
	Feedback.reset()
	assert_eq(Engine.time_scale, 1.0)
	assert_false(Feedback.is_hit_stopped())
	var start: int = Time.get_ticks_usec()
	Feedback.hit_stop(300.0)
	await _real_wait(0.1)
	# The 40 ms timer from before the reset has fired by now and was ignored.
	if _ms_since(start) < 250.0:
		assert_eq(Engine.time_scale, 0.0, "the new stop still holds")
		assert_true(Feedback.is_hit_stopped())
	else:
		pending("frame took too long to check the stale timer")
	Feedback.reset()
	assert_eq(Engine.time_scale, 1.0)


# --- Prewarm -----------------------------------------------------------------

func test_prewarm_spawns_one_per_tier_off_screen_silently() -> void:
	_setup_listeners()
	Audio.play_sfx(&"laser_zap")
	var before: AudioStreamPlayer = Audio.newest_player()
	Feedback.prewarm()
	var explosions: Array[Explosion] = _explosions()
	assert_eq(explosions.size(), 7, "one per tier")
	for i: int in explosions.size():
		var e: Explosion = explosions[i]
		assert_eq(e.global_position, Feedback.PREWARM_POSITION, "off-screen")
		var row_scale: float = Feedback.tier_row(i).get("explosion_scale", -1.0) as float
		assert_eq(e.scale, Vector2(row_scale, row_scale), "%s scale" % ImpactTier.NAMES[i])
	assert_eq(explosions[2].extras, [&"debris", &"shockwave"] as Array[StringName], "large extras")
	assert_false(explosions[ImpactTier.BOSS_DEATH].extras.has(&"white_flash"), "no screen flash at prewarm")
	assert_false(explosions[ImpactTier.BOSS_DEATH].is_flashing())
	assert_eq(Feedback.tier_row(ImpactTier.BOSS_DEATH).get("extras"), [&"white_flash"] as Array[StringName], "the tier row keeps its flash")
	assert_eq(_camera.current_amplitude(), 0.0, "no shake")
	assert_eq(Engine.time_scale, 1.0, "no hit-stop")
	assert_eq(Audio.newest_player(), before, "no sound")


func test_prewarm_without_spawner_is_harmless() -> void:
	Feedback.prewarm()
	assert_eq(Engine.time_scale, 1.0)


# --- Boss-death chain (Story 7.5) ------------------------------------------------

const CHAIN_DT: float = 1.0 / 60.0
const CHAIN_POS: Vector2 = Vector2(960, 170)


func _chain_offsets() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for pair: Variant in Config.section("feedback").get("boss_death_chain_offsets_px", []) as Array:
		out.append(Vector2(float((pair as Array)[0]), float((pair as Array)[1])))
	return out


func test_chain_tuning() -> void:
	assert_eq(Config.num("feedback.boss_death_chain_s"), 2.0, "2 s chain")
	assert_eq(_chain_offsets(), [Vector2(0, 124), Vector2(-270, 40), Vector2(270, 40), Vector2(0, 0)] as Array[Vector2], "the core, the hull ends, the hull centre")


func test_boss_death_plays_the_full_impact_first() -> void:
	_setup_listeners()
	Feedback.boss_death(CHAIN_POS)
	var explosions: Array[Explosion] = _explosions()
	assert_eq(explosions.size(), 1, "explosion 0 inside the call")
	if explosions.size() == 1:
		var e: Explosion = explosions[0]
		assert_eq(e.global_position, CHAIN_POS + Vector2(0, 124), "at pos + offset 0")
		assert_eq(e.scale, Vector2(4, 4), "Boss-death scale")
		assert_eq(e.extras, [&"white_flash"] as Array[StringName], "with the tier's extras")
		assert_true(e.is_flashing(), "the white flash")
	assert_almost_eq(_camera.current_amplitude(), 20.0, 0.0001, "20 px shake")
	assert_true(Feedback.is_hit_stopped(), "150 ms hit-stop")
	assert_eq(Engine.time_scale, 0.0)
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"explosion_boss_death"], "the tier sfx")
	assert_eq(Feedback.chain_pending(), 3, "3 more to come")


func test_chain_spreads_the_explosions_evenly_over_chain_s() -> void:
	_setup_listeners()
	var offsets: Array[Vector2] = _chain_offsets()
	Feedback.boss_death(CHAIN_POS)
	var seen: int = 1
	var times: Array[float] = [0.0]
	var flashes: int = 1
	var sfx_after: Array[bool] = []
	var t: float = 0.0
	for i: int in 120:
		var before: AudioStreamPlayer = Audio.newest_player()
		Feedback.step_chain(CHAIN_DT)
		t += CHAIN_DT
		var explosions: Array[Explosion] = _explosions()
		if explosions.size() > seen:
			assert_eq(explosions.size(), seen + 1, "one explosion at a time")
			var e: Explosion = explosions.back()
			assert_eq(e.global_position, CHAIN_POS + offsets[seen], "explosion %d at pos + its offset" % seen)
			assert_eq(e.scale, Vector2(4, 4), "explosion %d at the Boss-death scale" % seen)
			assert_eq(e.extras, [] as Array[StringName], "explosion %d has no extras" % seen)
			if e.is_flashing():
				flashes += 1
			sfx_after.append(Audio.newest_player() != before and Audio.newest_player().stream == Audio.SFX[&"explosion_boss_death"])
			times.append(t)
			seen = explosions.size()
	assert_eq(seen, 4, "4 explosions in total")
	assert_eq(times.size(), 4)
	for k: int in mini(times.size(), 4):
		assert_almost_eq(times[k], float(k) * 2.0 / 3.0, CHAIN_DT + 0.0001, "explosion %d at k * chain_s / (N - 1)" % k)
	assert_eq(flashes, 1, "the flash only on the first")
	assert_eq(sfx_after, [true, true, true] as Array[bool], "each later explosion plays the tier sfx")
	assert_eq(Feedback.chain_pending(), 0, "nothing left")
	Feedback.step_chain(1.0)
	assert_eq(_explosions().size(), 4, "a finished chain plays nothing more")


func test_chain_freezes_while_the_tree_is_paused() -> void:
	_setup_listeners()
	Feedback.boss_death(CHAIN_POS)
	PauseArbiter.push(&"menu")
	Feedback._process(1.0)
	assert_eq(_explosions().size(), 1, "paused: frozen")
	assert_eq(Feedback.chain_pending(), 3)
	PauseArbiter.pop(&"menu")
	Feedback._process(0.7)
	assert_eq(_explosions().size(), 2, "unpaused: the chain goes on")


func test_reset_drops_the_pending_chain() -> void:
	_setup_listeners()
	Feedback.boss_death(CHAIN_POS)
	Feedback.reset()
	assert_eq(Feedback.chain_pending(), 0, "dropped")
	Feedback.step_chain(3.0)
	assert_eq(_explosions().size(), 1, "only the first played")


func test_chain_without_a_spawner_plays_no_explosion_and_no_error() -> void:
	var lines: Array[String] = []
	Log.sink = func(level: String, category: String, msg: String) -> void: lines.append(Log.format(level, category, msg))
	Feedback.boss_death(CHAIN_POS)
	for i: int in 130:
		Feedback.step_chain(CHAIN_DT)
	assert_eq(Feedback.chain_pending(), 0, "the chain ran out")
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"explosion_boss_death"], "the sfx still plays")
	for line: String in lines:
		assert_false(line.begins_with("[ERROR]"), "no error: %s" % line)


func test_a_single_offset_plays_at_once() -> void:
	(Config.tuning["feedback"] as Dictionary)["boss_death_chain_offsets_px"] = [[5, -5]]
	Feedback.load_tiers()
	_setup_listeners()
	Feedback.boss_death(CHAIN_POS)
	assert_eq(_explosions().size(), 1)
	assert_eq(_explosions()[0].global_position, CHAIN_POS + Vector2(5, -5))
	assert_eq(Feedback.chain_pending(), 0, "nothing queued")


func test_load_tiers_rereads_the_chain() -> void:
	(Config.tuning["feedback"] as Dictionary)["boss_death_chain_offsets_px"] = [[0, 0], [100, 0]]
	(Config.tuning["feedback"] as Dictionary)["boss_death_chain_s"] = 1.0
	Feedback.load_tiers()
	_setup_listeners()
	Feedback.boss_death(CHAIN_POS)
	assert_eq(Feedback.chain_pending(), 1)
	Feedback.step_chain(0.9)
	assert_eq(_explosions().size(), 1, "not before 1.0 s")
	Feedback.step_chain(0.1)
	assert_eq(_explosions().size(), 2, "at chain_s")
	assert_eq(_explosions()[1].global_position, CHAIN_POS + Vector2(100, 0))


func test_no_chain_offsets_plays_one_impact_at_pos() -> void:
	(Config.tuning["feedback"] as Dictionary)["boss_death_chain_offsets_px"] = []
	Feedback.load_tiers()
	_setup_listeners()
	Feedback.boss_death(CHAIN_POS)
	assert_push_error("feedback.boss_death_chain_offsets_px is empty; one boss_death impact instead")
	var explosions: Array[Explosion] = _explosions()
	assert_eq(explosions.size(), 1, "exactly one explosion")
	if explosions.size() == 1:
		assert_eq(explosions[0].global_position, CHAIN_POS, "at pos")
		assert_eq(explosions[0].scale, Vector2(4, 4), "the Boss-death impact")
	assert_eq(Feedback.chain_pending(), 0, "nothing queued")


func test_malformed_chain_offsets_are_skipped() -> void:
	var lines: Array[String] = []
	Log.sink = func(level: String, category: String, msg: String) -> void: lines.append(Log.format(level, category, msg))
	(Config.tuning["feedback"] as Dictionary)["boss_death_chain_offsets_px"] = [[0, 0], "x", [1]]
	Feedback.load_tiers()
	assert_push_error("feedback.boss_death_chain_offsets_px entry x is not an [x, y] pair; skipped")
	assert_push_error("feedback.boss_death_chain_offsets_px entry [1] is not an [x, y] pair; skipped")
	var errors: Array[String] = []
	for line: String in lines:
		if line.begins_with("[ERROR][data]"):
			errors.append(line)
	assert_eq(errors.size(), 2, "one data error per malformed entry: %s" % [errors])
	_setup_listeners()
	Feedback.boss_death(CHAIN_POS)
	assert_eq(_explosions().size(), 1, "only the valid offset plays")
	assert_eq(_explosions()[0].global_position, CHAIN_POS)
	assert_eq(Feedback.chain_pending(), 0, "nothing queued")
