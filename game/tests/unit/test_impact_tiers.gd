extends GutTest
## Impact tiers in the sandbox: every death and projectile impact drives Feedback
## with the right tier; pre-warm on load.

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")

var _sandbox: Node2D
var _effects: Node2D
var _spawner: Spawner
var _camera: ShakeCamera


func before_each() -> void:
	_sandbox = SANDBOX_SCENE.instantiate() as Node2D
	add_child_autofree(_sandbox)
	_effects = _sandbox.get_node("World/Effects") as Node2D
	_spawner = _sandbox.get_node("Spawner") as Spawner
	_camera = _sandbox.get_node("ShakeCamera") as ShakeCamera
	# Tests read the amplitude after awaiting frames; it must not decay meanwhile.
	_camera.set_process(false)
	_sandbox.set_physics_process(false)


func after_each() -> void:
	Feedback.reset()
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_sandbox = null
	_effects = null
	_spawner = null
	_camera = null


func _newest_explosion() -> Explosion:
	for i: int in range(_effects.get_child_count() - 1, -1, -1):
		var e: Explosion = _effects.get_child(i) as Explosion
		if e != null:
			return e
	return null


func _assert_newest(expected_scale: float, expected_amp: float, hit_stopped: bool) -> void:
	var e: Explosion = _newest_explosion()
	assert_not_null(e, "an explosion")
	if e != null:
		assert_eq(e.scale, Vector2(expected_scale, expected_scale), "explosion scale")
		assert_ne(e.global_position.x, Feedback.PREWARM_POSITION.x, "not a pre-warm explosion")
	assert_almost_eq(_camera.current_amplitude(), expected_amp, 0.0001, "camera amplitude")
	assert_eq(Feedback.is_hit_stopped(), hit_stopped, "hit-stop")


func _kill_asteroid(size: StringName) -> void:
	var rock: Asteroid = _spawner.spawn_asteroid({"size": size, "position": Vector2(400, 600)})
	rock.set_physics_process(false)
	rock.apply_damage(rock.hp, null)


func test_prewarm_on_load() -> void:
	var count: int = 0
	for child: Node in _effects.get_children():
		var e: Explosion = child as Explosion
		if e == null:
			continue
		count += 1
		assert_eq(e.global_position.x, -1000.0, "off-screen")
	assert_eq(count, 7, "one per tier")
	assert_eq(_camera.current_amplitude(), 0.0)
	assert_eq(Engine.time_scale, 1.0)


func test_wasp_death_small() -> void:
	var wasp: Enemy = _sandbox.get_node("World/Enemies").get_child(0) as Enemy
	wasp.apply_damage(wasp.hp, null)
	_assert_newest(0.5, 0.0, false)
	assert_true((_newest_explosion().get_node("Sparks") as GPUParticles2D).emitting, "spark burst")


func test_small_asteroid() -> void:
	_kill_asteroid(&"small")
	_assert_newest(0.5, 0.0, false)


func test_medium_asteroid() -> void:
	_kill_asteroid(&"medium")
	_assert_newest(1.0, 4.0, false)


func test_large_asteroid() -> void:
	_kill_asteroid(&"large")
	_assert_newest(2.0, 8.0, true)
	assert_eq(Engine.time_scale, 0.0)
	assert_true((_newest_explosion().get_node("Shockwave") as Node2D).visible, "shockwave ring")


func test_missile_impact_medium() -> void:
	# A lower-row Wasp; the missile flies straight up into it.
	var target: Enemy = null
	for child: Node in _sandbox.get_node("World/Enemies").get_children():
		var wasp: Enemy = child as Enemy
		if wasp != null and wasp.global_position == Vector2(720, 280):
			target = wasp
	assert_not_null(target)
	if target == null:
		return
	_spawner.spawn_projectile(&"missile", {"position": Vector2(720, 600), "velocity": Vector2(0, -900), "damage": 8})
	await wait_physics_frames(30)
	# The Wasp's Small death comes first; the missile's Medium impact is the newest.
	_assert_newest(1.0, 4.0, false)
	assert_true((_newest_explosion().get_node("Debris") as GPUParticles2D).emitting, "debris")


func test_laser_impact_small() -> void:
	var rock: Asteroid = _spawner.spawn_asteroid({"size": &"large", "position": Vector2(400, 500)})
	rock.set_physics_process(false)
	_spawner.spawn_projectile(&"laser_bolt", {"position": Vector2(400, 900), "velocity": Vector2(0, -1800), "damage": 1})
	await wait_physics_frames(20)
	assert_eq(rock.hp, 29, "bolt hit the asteroid")
	_assert_newest(0.5, 0.0, false)
