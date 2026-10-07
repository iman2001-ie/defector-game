extends GutTest
## Feedback: tier rows from tuning, impact (explosion + shake + hit-stop + SFX),
## hit-stop overlap rules, reset, prewarm, registration.

const CONTAINERS: Array[String] = ["Projectiles", "Enemies", "Asteroids", "Effects"]

var _world: Node2D
var _effects: Node2D
var _spawner: Spawner
var _camera: ShakeCamera


func after_each() -> void:
	Feedback.reset()
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


## Awaits process frames until time_scale is back to 1 (or limit_ms passes);
## returns the elapsed ms since start_usec at that moment.
func _await_resume(start_usec: int, limit_ms: float) -> float:
	while Engine.time_scale < 0.5 and _ms_since(start_usec) < limit_ms:
		await get_tree().process_frame
	return _ms_since(start_usec)


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
	assert_eq(Engine.time_scale, 1.0, "resumed")
	assert_false(Feedback.is_hit_stopped())
	# Ending with the shorter second stop would resume near second_ms + 40 (~60 ms).
	if second_ms + 40.0 < 70.0:
		assert_gte(resumed_ms, 80.0, "held for the longest stop (second at %.1f ms)" % second_ms)
	else:
		pending("second hit_stop came too late (%.1f ms) to tell the stops apart" % second_ms)
	assert_lt(resumed_ms, 250.0, "resumed promptly")


func test_hit_stop_extend() -> void:
	await _sync_to_frame()
	var start: int = Time.get_ticks_usec()
	Feedback.hit_stop(40.0)
	await _real_wait(0.02)
	var second_ms: float = _ms_since(start)
	Feedback.hit_stop(100.0)
	var resumed_ms: float = await _await_resume(start, 500.0)
	assert_eq(Engine.time_scale, 1.0, "resumed")
	# The first (stale) 40 ms timer must not end the extended freeze (~second_ms + 100).
	if second_ms > 50.0:
		pending("second hit_stop came too late (%.1f ms) to tell the stops apart" % second_ms)
		return
	assert_gte(resumed_ms, maxf(80.0, second_ms + 70.0), "extended (second at %.1f ms)" % second_ms)
	assert_lt(resumed_ms, second_ms + 250.0, "resumed promptly")


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
	assert_eq(_camera.current_amplitude(), 0.0, "no shake")
	assert_eq(Engine.time_scale, 1.0, "no hit-stop")
	assert_eq(Audio.newest_player(), before, "no sound")


func test_prewarm_without_spawner_is_harmless() -> void:
	Feedback.prewarm()
	assert_eq(Engine.time_scale, 1.0)
