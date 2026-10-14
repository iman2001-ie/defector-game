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


## Every tier row matches its raw feedback.tiers.<name> row in tuning (so a
## retune flows straight through) and every number is a sane, non-negative one.
func test_tier_rows_from_tuning() -> void:
	var raw_tiers: Dictionary = (Config.tuning["feedback"] as Dictionary)["tiers"] as Dictionary
	for tier: int in ImpactTier.NAMES.size():
		var row: Dictionary = Feedback.tier_row(tier)
		var label: String = ImpactTier.NAMES[tier]
		assert_true(raw_tiers.has(label), "tuning has feedback.tiers.%s" % label)
		var raw: Dictionary = raw_tiers.get(label, {}) as Dictionary
		for key: String in ["explosion_scale", "shake_px", "shake_s", "hit_stop_ms"]:
			var tuned: float = float(raw.get(key, -2.0))
			assert_gte(tuned, 0.0, "%s %s >= 0" % [label, key])
			assert_almost_eq(row.get(key, -1.0) as float, tuned, 0.0001, "%s %s from tuning" % [label, key])
		assert_gt(row.get("explosion_scale", -1.0) as float, 0.0, label + " scale > 0")
	assert_eq(Feedback.tier_row(ImpactTier.SMALL).get("extras"), [&"sparks"] as Array[StringName])
	assert_eq(Feedback.tier_row(ImpactTier.MEDIUM).get("extras"), [&"debris"] as Array[StringName])
	assert_eq(Feedback.tier_row(ImpactTier.LARGE).get("extras"), [&"debris", &"shockwave"] as Array[StringName])
	assert_almost_eq(Feedback.tier_row(ImpactTier.LARGE).get("sfx_pitch", -1.0) as float, 0.8, 0.0001)
	assert_almost_eq(Feedback.tier_row(ImpactTier.MEDIUM).get("sfx_pitch", -1.0) as float, 1.0, 0.0001)
	assert_almost_eq(Feedback.tier_row(ImpactTier.SMALL).get("sfx_pitch", -1.0) as float, 1.2, 0.0001, "Story 8.1")
	assert_eq(Feedback.tier_row(ImpactTier.LARGE).get("sfx"), &"explosion_large")
	assert_eq(Feedback.tier_row(99), {}, "out of range")


## Story 8.1: the pitch falls with the size tier (small 1.2 > medium 1.0 > large 0.8).
func test_explosion_pitch_falls_with_size() -> void:
	var small: float = Feedback.tier_row(ImpactTier.SMALL).get("sfx_pitch", -1.0) as float
	var medium: float = Feedback.tier_row(ImpactTier.MEDIUM).get("sfx_pitch", -1.0) as float
	var large: float = Feedback.tier_row(ImpactTier.LARGE).get("sfx_pitch", -1.0) as float
	assert_gt(small, medium, "small above medium")
	assert_gt(medium, large, "medium above large")


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
		assert_between(player.pitch_scale, 1.14, 1.26, "pitch 1.2 +-5% (Story 8.1)")


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


## Story 8.1: every tier's sound, pitch and volume are its tuning.feedback row
## (data only): the registered stream named by `sfx`, `sfx_volume_db`, and
## `sfx_pitch` within the default jitter.
func test_every_tier_plays_its_tuned_sfx() -> void:
	var raw_tiers: Dictionary = Config.section("feedback.tiers")
	for tier: int in ImpactTier.NAMES.size():
		var label: String = ImpactTier.NAMES[tier]
		var raw: Dictionary = raw_tiers.get(label, {}) as Dictionary
		var id: StringName = StringName(str(raw.get("sfx", "")))
		assert_true(Audio.SFX.has(id), "%s: sfx '%s' registered" % [label, id])
		Feedback.impact(tier, Vector2(300, 300))
		Feedback.reset()
		var player: AudioStreamPlayer = Audio.newest_player()
		assert_not_null(player, label)
		if player == null or not Audio.SFX.has(id):
			continue
		assert_eq(player.stream, Audio.SFX[id], "%s plays %s" % [label, id])
		assert_almost_eq(player.volume_db, float(raw.get("sfx_volume_db", 99.0)), 0.0001, "%s volume from tuning" % label)
		var pitch: float = float(raw.get("sfx_pitch", -1.0))
		var jitter: float = Audio.DEFAULT_PITCH_JITTER
		assert_between(player.pitch_scale, pitch * (1.0 - jitter) - 0.0001, pitch * (1.0 + jitter) + 0.0001, "%s pitch from tuning" % label)


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


## The stream chain explosion k plays (its boss_death_chain_sfx row).
func _chain_stream(k: int) -> AudioStream:
	var rows: Array = Config.section("feedback").get("boss_death_chain_sfx", []) as Array
	return Audio.SFX[StringName(str((rows[k] as Dictionary)["sfx"]))]


## The pitch chain explosion k plays at (its boss_death_chain_sfx row).
func _chain_pitch(k: int) -> float:
	var rows: Array = Config.section("feedback").get("boss_death_chain_sfx", []) as Array
	return float((rows[k] as Dictionary)["sfx_pitch"])


## The Boss-death tier's explosion scale, as a node scale.
func _boss_death_scale() -> Vector2:
	return Vector2.ONE * Config.num("feedback.tiers.boss_death.explosion_scale")


func test_chain_tuning() -> void:
	assert_gt(Config.num("feedback.boss_death_chain_s"), 0.0, "the chain has a duration")
	assert_gte(_chain_offsets().size(), 2, "a chain of at least two explosions")


func test_boss_death_plays_the_full_impact_first() -> void:
	_setup_listeners()
	Feedback.boss_death(CHAIN_POS)
	var explosions: Array[Explosion] = _explosions()
	assert_eq(explosions.size(), 1, "explosion 0 inside the call")
	if explosions.size() == 1:
		var e: Explosion = explosions[0]
		assert_eq(e.global_position, CHAIN_POS + _chain_offsets()[0], "at pos + offset 0")
		assert_eq(e.scale, _boss_death_scale(), "Boss-death scale")
		assert_eq(e.extras, [&"white_flash"] as Array[StringName], "with the tier's extras")
		assert_true(e.is_flashing(), "the white flash")
		assert_almost_eq(e.speed, Config.num("feedback.boss_death_chain_anim_speed"), 0.0001, "at the chain's playback speed")
	assert_almost_eq(_camera.current_amplitude(), Config.num("feedback.tiers.boss_death.shake_px"), 0.0001, "the tier's shake")
	assert_true(Feedback.is_hit_stopped(), "the tier's hit-stop")
	assert_eq(Engine.time_scale, 0.0)
	assert_eq(Audio.newest_player().stream, _chain_stream(0), "chain sfx row 0, not the tier sfx")
	assert_eq(Feedback.chain_pending(), _chain_offsets().size() - 1, "the rest of the chain to come")


func test_chain_spreads_the_explosions_evenly_over_chain_s() -> void:
	_setup_listeners()
	var offsets: Array[Vector2] = _chain_offsets()
	var count: int = offsets.size()
	var chain_s: float = Config.num("feedback.boss_death_chain_s")
	Feedback.boss_death(CHAIN_POS)
	var seen: int = 1
	var times: Array[float] = [0.0]
	var flashes: int = 1
	var sfx_after: Array[bool] = []
	var t: float = 0.0
	for i: int in ceili(chain_s / CHAIN_DT) + 2:
		var before: AudioStreamPlayer = Audio.newest_player()
		Feedback.step_chain(CHAIN_DT)
		t += CHAIN_DT
		var explosions: Array[Explosion] = _explosions()
		if explosions.size() > seen:
			assert_eq(explosions.size(), seen + 1, "one explosion at a time")
			var e: Explosion = explosions.back()
			assert_eq(e.global_position, CHAIN_POS + offsets[seen], "explosion %d at pos + its offset" % seen)
			assert_eq(e.scale, _boss_death_scale(), "explosion %d at the Boss-death scale" % seen)
			assert_eq(e.extras, [] as Array[StringName], "explosion %d has no extras" % seen)
			assert_almost_eq(e.speed, Config.num("feedback.boss_death_chain_anim_speed"), 0.0001, "explosion %d at the chain speed" % seen)
			if e.is_flashing():
				flashes += 1
			sfx_after.append(Audio.newest_player() != before and Audio.newest_player().stream == _chain_stream(seen))
			var row_pitch: float = _chain_pitch(seen)
			assert_almost_eq(Audio.newest_player().pitch_scale, row_pitch, 0.0001, "explosion %d at exactly its row's pitch (no jitter)" % seen)
			times.append(t)
			seen = explosions.size()
	assert_eq(seen, count, "one explosion per offset")
	assert_eq(times.size(), count)
	for k: int in mini(times.size(), count):
		assert_almost_eq(times[k], float(k) * chain_s / float(count - 1), CHAIN_DT + 0.0001, "explosion %d at k * chain_s / (N - 1)" % k)
	assert_eq(flashes, 1, "the flash only on the first")
	var all_sfx: Array[bool] = []
	all_sfx.resize(count - 1)
	all_sfx.fill(true)
	assert_eq(sfx_after, all_sfx, "each later explosion plays its own chain sfx row")
	assert_eq(Feedback.chain_pending(), 0, "nothing left")
	Feedback.step_chain(1.0)
	assert_eq(_explosions().size(), count, "a finished chain plays nothing more")


func test_chain_freezes_while_the_tree_is_paused() -> void:
	_setup_listeners()
	Feedback.boss_death(CHAIN_POS)
	PauseArbiter.push(&"menu")
	Feedback._process(1.0)
	assert_eq(_explosions().size(), 1, "paused: frozen")
	assert_eq(Feedback.chain_pending(), _chain_offsets().size() - 1)
	PauseArbiter.pop(&"menu")
	Feedback._process(Config.num("feedback.boss_death_chain_s") / float(_chain_offsets().size() - 1) + 0.05)
	assert_eq(_explosions().size(), 2, "unpaused: the chain goes on")


func test_reset_drops_the_pending_chain() -> void:
	_setup_listeners()
	Feedback.boss_death(CHAIN_POS)
	Feedback.reset()
	assert_eq(Feedback.chain_pending(), 0, "dropped")
	Feedback.step_chain(Config.num("feedback.boss_death_chain_s") + 1.0)
	assert_eq(_explosions().size(), 1, "only the first played")


func test_chain_without_a_spawner_plays_no_explosion_and_no_error() -> void:
	var lines: Array[String] = []
	Log.sink = func(level: String, category: String, msg: String) -> void: lines.append(Log.format(level, category, msg))
	Feedback.boss_death(CHAIN_POS)
	for i: int in ceili(Config.num("feedback.boss_death_chain_s") / CHAIN_DT) + 10:
		Feedback.step_chain(CHAIN_DT)
	assert_eq(Feedback.chain_pending(), 0, "the chain ran out")
	assert_eq(Audio.newest_player().stream, _chain_stream(_chain_offsets().size() - 1), "the sfx still plays")
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
		assert_eq(explosions[0].scale, _boss_death_scale(), "the Boss-death impact")
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


# --- Slow motion and the fair resume (Epic 7 playtest C) ---------------------------

## A stand-in Player: the resume hook and the slow-motion clock only look for
## a node in Groups.PLAYER.
func _add_player() -> Node2D:
	var player: Node2D = Node2D.new()
	player.add_to_group(Groups.PLAYER)
	add_child_autofree(player)
	return player


func test_resume_slowmo_tuning() -> void:
	assert_almost_eq(Config.num("feedback.resume_slowmo.scale"), 0.25, 0.0001)
	assert_almost_eq(Config.num("feedback.resume_slowmo.hold_s"), 0.15, 0.0001)
	assert_almost_eq(Config.num("feedback.resume_slowmo.ramp_s"), 0.9, 0.0001)


func test_slow_motion_is_idle_at_start() -> void:
	assert_false(Feedback.is_slow_motion())
	assert_eq(Feedback.slow_motion_scale(), 1.0, "1.0 when idle")
	Feedback.step_slow_motion(1.0)
	assert_eq(Engine.time_scale, 1.0, "a step while idle does nothing")


func test_slow_motion_holds_then_ramps_back_to_one() -> void:
	Feedback.slow_motion(0.25, 0.15, 0.9)
	assert_true(Feedback.is_slow_motion())
	assert_eq(Engine.time_scale, 0.25, "slowed at once")
	assert_eq(Feedback.slow_motion_scale(), 0.25)
	Feedback.step_slow_motion(0.1)
	assert_eq(Engine.time_scale, 0.25, "still held at 0.1 s")
	Feedback.step_slow_motion(0.05)
	assert_almost_eq(Engine.time_scale, 0.25, 0.0001, "the hold ends at 0.15 s")
	Feedback.step_slow_motion(0.45)
	assert_almost_eq(Engine.time_scale, 0.625, 0.0001, "half way up the 0.9 s ramp")
	assert_almost_eq(Feedback.slow_motion_scale(), 0.625, 0.0001)
	Feedback.step_slow_motion(0.44)
	assert_lt(Engine.time_scale, 1.0, "not quite back")
	assert_true(Feedback.is_slow_motion())
	Feedback.step_slow_motion(0.02)
	assert_eq(Engine.time_scale, 1.0, "back to normal at hold + ramp")
	assert_false(Feedback.is_slow_motion(), "done")
	assert_eq(Feedback.slow_motion_scale(), 1.0)


func test_a_step_past_the_hold_carries_into_the_ramp() -> void:
	Feedback.slow_motion(0.2, 0.5, 1.0)
	Feedback.step_slow_motion(1.0)
	assert_almost_eq(Engine.time_scale, 0.6, 0.0001, "0.5 s of hold, then 0.5 s into the 1 s ramp")


func test_slow_motion_without_hold_or_ramp_does_nothing() -> void:
	Feedback.slow_motion(0.25, 0.0, 0.0)
	assert_false(Feedback.is_slow_motion())
	assert_eq(Engine.time_scale, 1.0)


func test_the_slow_motion_clock_is_frozen_while_paused() -> void:
	_add_player()
	Feedback.slow_motion(0.25, 0.15, 0.9)
	PauseArbiter.push(&"menu")
	# Pretend 10 s of real time passed while paused: _process must not count it.
	Feedback._slow_last_usec = Time.get_ticks_usec() - 10000000
	Feedback._process(0.0)
	assert_true(Feedback.is_slow_motion(), "still running")
	assert_eq(Feedback.slow_motion_scale(), 0.25, "the paused time didn't count")
	PauseArbiter.clear()
	Feedback._process(0.0)
	assert_true(Feedback.is_slow_motion(), "only the microseconds since the last frame count")
	assert_eq(Feedback.slow_motion_scale(), 0.25)


func test_slow_motion_ends_when_the_player_leaves_the_tree() -> void:
	var player: Node2D = _add_player()
	Feedback.slow_motion(0.25, 0.15, 0.9)
	Feedback._process(0.0)
	assert_true(Feedback.is_slow_motion(), "a Player is in the tree")
	remove_child(player)
	player.free()
	Feedback._process(0.0)
	assert_false(Feedback.is_slow_motion(), "the level ended: no slow motion left behind")
	assert_eq(Engine.time_scale, 1.0)


func test_hit_stop_composes_with_slow_motion() -> void:
	Feedback.slow_motion(0.5, 1.0, 1.0)
	Feedback.hit_stop(5000.0)
	assert_eq(Engine.time_scale, 0.0, "the hit-stop freezes time")
	Feedback.step_slow_motion(1.5)
	assert_eq(Engine.time_scale, 0.0, "the ramp doesn't lift the stop")
	assert_almost_eq(Feedback.slow_motion_scale(), 0.75, 0.0001, "the ramp moved on in real time")
	Feedback._end_hit_stop(Feedback._hit_stop_serial)
	assert_almost_eq(Engine.time_scale, 0.75, 0.0001, "back to the ramp value, not 1.0")
	assert_false(Feedback.is_hit_stopped())


func test_slow_motion_started_during_a_hit_stop_waits_for_it() -> void:
	Feedback.hit_stop(5000.0)
	Feedback.slow_motion(0.25, 0.15, 0.9)
	assert_eq(Engine.time_scale, 0.0, "still stopped")
	Feedback._end_hit_stop(Feedback._hit_stop_serial)
	assert_eq(Engine.time_scale, 0.25, "then slow")


func test_a_hit_stop_after_the_ramp_returns_to_one() -> void:
	Feedback.slow_motion(0.5, 0.1, 0.1)
	Feedback.hit_stop(5000.0)
	Feedback.step_slow_motion(1.0)
	assert_false(Feedback.is_slow_motion())
	assert_eq(Engine.time_scale, 0.0, "the stop still holds")
	Feedback._end_hit_stop(Feedback._hit_stop_serial)
	assert_eq(Engine.time_scale, 1.0)


func test_reset_cancels_slow_motion() -> void:
	Feedback.slow_motion(0.25, 0.15, 0.9)
	Feedback.reset()
	assert_false(Feedback.is_slow_motion())
	assert_eq(Feedback.slow_motion_scale(), 1.0)
	assert_eq(Engine.time_scale, 1.0)
	Feedback.step_slow_motion(0.1)
	assert_eq(Engine.time_scale, 1.0, "nothing left to step")


func test_resume_with_a_player_starts_the_resume_slow_motion() -> void:
	_add_player()
	PauseArbiter.push(&"story")
	assert_false(Feedback.is_slow_motion(), "nothing while paused")
	PauseArbiter.pop(&"story")
	assert_true(Feedback.is_slow_motion(), "resumed in a level")
	assert_almost_eq(Engine.time_scale, Config.num("feedback.resume_slowmo.scale"), 0.0001)
	Feedback.step_slow_motion(Config.num("feedback.resume_slowmo.hold_s") + Config.num("feedback.resume_slowmo.ramp_s") + 0.01)
	assert_eq(Engine.time_scale, 1.0, "back to normal within hold + ramp")


func test_menu_and_final_choice_resumes_slow_down_too() -> void:
	_add_player()
	for reason: StringName in [&"menu", &"final_choice"]:
		Feedback.reset()
		PauseArbiter.push(reason)
		PauseArbiter.pop(reason)
		assert_true(Feedback.is_slow_motion(), "%s resume" % reason)


func test_a_pop_that_leaves_a_pause_does_not_slow_down() -> void:
	_add_player()
	PauseArbiter.push(&"story")
	PauseArbiter.push(&"menu")
	PauseArbiter.pop(&"menu")
	assert_false(Feedback.is_slow_motion(), "still paused by the story")


func test_resume_without_a_player_does_not_slow_down() -> void:
	PauseArbiter.push(&"menu")
	PauseArbiter.pop(&"menu")
	assert_false(Feedback.is_slow_motion(), "no Player: the title, a menu scene")
	assert_eq(Engine.time_scale, 1.0)


func test_a_scene_change_clear_does_not_slow_down() -> void:
	_add_player()
	PauseArbiter.push(&"story")
	PauseArbiter.clear()
	assert_false(Feedback.is_slow_motion(), "PauseArbiter.clear() is a scene change")
	assert_eq(Engine.time_scale, 1.0)
	assert_false(PauseArbiter.is_clearing(), "only true during clear()")


# --- Playtest pt7-e: chain sounds and speed --------------------------------------

## Fewer sfx rows than offsets: the rest play the Boss-death tier sfx.
func test_missing_chain_sfx_rows_use_the_tier_sfx() -> void:
	(Config.tuning["feedback"] as Dictionary)["boss_death_chain_offsets_px"] = [[0, 0], [100, 0]]
	(Config.tuning["feedback"] as Dictionary)["boss_death_chain_s"] = 1.0
	(Config.tuning["feedback"] as Dictionary)["boss_death_chain_sfx"] = [{"sfx": "explosion_small", "sfx_pitch": 1.0, "sfx_volume_db": -2}]
	Feedback.load_tiers()
	_setup_listeners()
	Feedback.boss_death(CHAIN_POS)
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"explosion_small"], "row 0")
	assert_almost_eq(Audio.newest_player().volume_db, -2.0, 0.0001, "row 0's volume")
	Feedback.step_chain(1.0)
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"explosion_boss_death"], "no row 1: the tier sfx")


## A malformed row logs one data error at load and falls back to the tier sfx.
func test_malformed_chain_sfx_row_falls_back() -> void:
	(Config.tuning["feedback"] as Dictionary)["boss_death_chain_offsets_px"] = [[0, 0]]
	(Config.tuning["feedback"] as Dictionary)["boss_death_chain_sfx"] = [{"sfx": 3}]
	Feedback.load_tiers()
	assert_push_error("feedback.boss_death_chain_sfx entry { \"sfx\": 3 } is not a {sfx, sfx_pitch, sfx_volume_db} row; the tier sfx plays instead")
	_setup_listeners()
	Feedback.boss_death(CHAIN_POS)
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"explosion_boss_death"], "the tier sfx")


## A row with a pitch of 0 or less is malformed too (pitch_scale must be > 0).
func test_chain_sfx_row_with_no_pitch_falls_back() -> void:
	(Config.tuning["feedback"] as Dictionary)["boss_death_chain_offsets_px"] = [[0, 0]]
	(Config.tuning["feedback"] as Dictionary)["boss_death_chain_sfx"] = [{"sfx": "explosion_small", "sfx_pitch": 0, "sfx_volume_db": 0}]
	Feedback.load_tiers()
	assert_push_error("is not a {sfx, sfx_pitch, sfx_volume_db} row; the tier sfx plays instead")
	_setup_listeners()
	Feedback.boss_death(CHAIN_POS)
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"explosion_boss_death"], "the tier sfx")


## Ordinary impacts keep the authored playback speed.
func test_ordinary_impacts_play_at_speed_one() -> void:
	_setup_listeners()
	Feedback.impact(ImpactTier.LARGE, Vector2(300, 300))
	var explosions: Array[Explosion] = _explosions()
	assert_eq(explosions.size(), 1)
	if explosions.size() == 1:
		assert_almost_eq(explosions[0].speed, 1.0, 0.0001)


# --- Playtest pt7-g: the convoy death chain ------------------------------------------

const CONVOY_POSITIONS: Array[Vector2] = [Vector2(400, 820), Vector2(220, 840), Vector2(580, 840)]


func test_convoy_chain_tuning() -> void:
	assert_gt(Config.num("feedback.convoy_death_chain_s"), 0.0)
	assert_gt(Config.num("feedback.convoy_death_explosion_scale"), Config.num("feedback.tiers.large.explosion_scale"), "bigger than a Large kill")
	var rows: Array = Config.section("feedback").get("convoy_death_chain_sfx", []) as Array
	assert_eq(rows.size(), 3, "one sound per ship")
	for row: Variant in rows:
		assert_true(Audio.SFX.has(StringName(str((row as Dictionary)["sfx"]))), "a registered sound")
		assert_gte(float((row as Dictionary)["sfx_pitch"]), 0.9, "never pitched down into mud")


func test_convoy_death_plays_a_full_impact_then_queues_the_rest() -> void:
	_setup_listeners()
	var steps: Array[int] = []
	Feedback.convoy_death(CONVOY_POSITIONS, func(k: int) -> void: steps.append(k))
	assert_eq(steps, [0] as Array[int], "explosion 0 inside the call")
	var explosions: Array[Explosion] = _explosions()
	assert_eq(explosions.size(), 1)
	if explosions.size() == 1:
		var e: Explosion = explosions[0]
		assert_eq(e.global_position, CONVOY_POSITIONS[0])
		assert_eq(e.scale, Vector2.ONE * Config.num("feedback.convoy_death_explosion_scale"), "the convoy scale")
		assert_eq(e.extras, [&"debris", &"shockwave"] as Array[StringName], "the Large extras")
		assert_almost_eq(e.speed, Config.num("feedback.boss_death_chain_anim_speed"), 0.0001, "the slow chain speed")
	assert_almost_eq(_camera.current_amplitude(), Config.num("feedback.tiers.large.shake_px"), 0.0001, "a full impact shakes")
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"explosion_mid"], "the medium explosion")
	assert_eq(Feedback.chain_pending(), 2)
	Feedback.reset()


func test_convoy_chain_spreads_over_chain_s_with_its_rows() -> void:
	_setup_listeners()
	var steps: Array[int] = []
	var chain_s: float = Config.num("feedback.convoy_death_chain_s")
	Feedback.convoy_death(CONVOY_POSITIONS, func(k: int) -> void: steps.append(k))
	var t: float = 0.0
	var times: Array[float] = []
	var rows: Array = Config.section("feedback").get("convoy_death_chain_sfx", []) as Array
	for i: int in ceili(chain_s / CHAIN_DT) + 2:
		var before: int = steps.size()
		Feedback.step_chain(CHAIN_DT)
		t += CHAIN_DT
		if steps.size() > before:
			times.append(t)
			var k: int = steps.back()
			var row: Dictionary = rows[k] as Dictionary
			assert_eq(Audio.newest_player().stream, Audio.SFX[StringName(str(row["sfx"]))], "explosion %d plays its row" % k)
			var pitch: float = float(row["sfx_pitch"])
			assert_almost_eq(Audio.newest_player().pitch_scale, pitch, pitch * Audio.DEFAULT_PITCH_JITTER + 0.0001)
			var e: Explosion = _explosions().back()
			assert_eq(e.global_position, CONVOY_POSITIONS[k])
			assert_eq(e.extras, [&"debris", &"shockwave"] as Array[StringName], "every convoy blast keeps the extras")
	assert_eq(steps, [0, 1, 2] as Array[int])
	assert_eq(times.size(), 2)
	for j: int in times.size():
		assert_almost_eq(times[j], float(j + 1) * chain_s / 2.0, CHAIN_DT + 0.0001)


func test_reset_drops_the_convoy_chain_without_calling_back() -> void:
	var steps: Array[int] = []
	Feedback.convoy_death(CONVOY_POSITIONS, func(k: int) -> void: steps.append(k))
	Feedback.reset()
	Feedback.step_chain(10.0)
	assert_eq(steps, [0] as Array[int], "nothing after the reset")
	assert_eq(Feedback.chain_pending(), 0)


func test_convoy_death_with_no_positions_does_nothing() -> void:
	var steps: Array[int] = []
	Feedback.convoy_death([] as Array[Vector2], func(k: int) -> void: steps.append(k))
	assert_eq(steps, [] as Array[int])
	assert_eq(Feedback.chain_pending(), 0)


func test_boss_chain_after_a_convoy_chain_uses_the_boss_settings() -> void:
	_setup_listeners()
	var steps: Array[int] = []
	Feedback.convoy_death(CONVOY_POSITIONS, func(k: int) -> void: steps.append(k))
	Feedback.boss_death(CHAIN_POS)
	Feedback.step_chain(Config.num("feedback.boss_death_chain_s") + 1.0)
	assert_eq(steps, [0] as Array[int], "the boss chain replaced the convoy's callback")
	assert_eq(_explosions().back().scale, _boss_death_scale(), "boss-death scale")
	assert_eq(_explosions().back().extras, [] as Array[StringName], "later boss blasts have no extras")


func test_convoy_sfx_row_falls_back_to_the_large_tier() -> void:
	(Config.tuning["feedback"] as Dictionary)["convoy_death_chain_sfx"] = [{"sfx": "", "sfx_pitch": 1.0, "sfx_volume_db": 0}]
	Feedback.load_tiers()
	assert_push_error("feedback.convoy_death_chain_sfx entry")
	assert_eq(Feedback.convoy_sfx_row(0)["sfx"], &"explosion_large", "a malformed row uses the Large tier")
	assert_eq(Feedback.convoy_sfx_row(5)["sfx"], &"explosion_large", "a missing row too")
