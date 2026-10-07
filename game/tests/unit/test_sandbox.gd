extends GutTest
## Sandbox scene: World containers, Player and Reticle, gameplay mouse mode,
## Wasp formation respawn and the asteroid timer.

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const CONTAINERS: Array[String] = ["Asteroids", "Enemies", "Allies", "Pickups", "Projectiles", "Effects"]

var _sandbox: Node2D


func before_each() -> void:
	_sandbox = SANDBOX_SCENE.instantiate() as Node2D
	add_child_autofree(_sandbox)


func after_each() -> void:
	_sandbox = null
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func test_world_containers() -> void:
	var world: Node2D = _sandbox.get_node_or_null("World") as Node2D
	assert_not_null(world, "World is a Node2D")
	if world == null:
		return
	assert_eq(world.process_mode, Node.PROCESS_MODE_INHERIT, "World is pausable")
	for container: String in CONTAINERS:
		var node: Node = world.get_node_or_null(container)
		assert_true(node is Node2D, "World/%s is a Node2D" % container)
	assert_true(world.get_node_or_null("Player") is Player, "World/Player is a Player")
	assert_true(world.get_node_or_null("Reticle") is Sprite2D, "World/Reticle is a Sprite2D")
	assert_eq(world.get_child(world.get_child_count() - 1).name, &"Reticle", "Reticle draws last")


func test_player_starts_at_spawn_point() -> void:
	var player: Player = _sandbox.get_node("World/Player") as Player
	assert_eq(player.position, Vector2(960, 900))


func test_gameplay_mouse_mode_confined_hidden() -> void:
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_CONFINED_HIDDEN, "no reasons")
	PauseArbiter.push(&"menu")
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "with a reason")


func test_reticle_follows_mouse() -> void:
	var reticle: Sprite2D = _sandbox.get_node("World/Reticle") as Sprite2D
	reticle.global_position = Vector2(-500, -500)
	reticle._process(0.0)
	assert_eq(reticle.global_position, reticle.get_global_mouse_position())


func test_spawner_wired_to_world_and_player() -> void:
	var spawner: Spawner = _sandbox.get_node_or_null("Spawner") as Spawner
	assert_not_null(spawner, "Sandbox/Spawner is a Spawner")
	if spawner == null:
		return
	assert_eq(spawner.world, _sandbox.get_node("World"), "Spawner.world is World")
	var player: Player = _sandbox.get_node("World/Player") as Player
	player.step_fire(true, 1.0 / 60.0)
	assert_eq(_sandbox.get_node("World/Projectiles").get_child_count(), 1, "player fires through the sandbox Spawner")


# --- Wasp formation and asteroids (Story 1.4) ---------------------------------

func _wasps() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for child: Node in _sandbox.get_node("World/Enemies").get_children():
		if child is Enemy:
			out.append(child as Enemy)
	return out


func _expected_slots() -> Array[Vector2]:
	var slots: Array[Vector2] = []
	for y: float in [160.0, 280.0]:
		for x: float in [720.0, 880.0, 1040.0, 1200.0]:
			slots.append(Vector2(x, y))
	return slots


func _positions(wasps: Array[Enemy]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for wasp: Enemy in wasps:
		out.append(wasp.global_position)
	return out


func test_formation_grid_4x2_on_ready() -> void:
	var wasps: Array[Enemy] = _wasps()
	assert_eq(wasps.size(), 8, "8 Wasps")
	assert_eq(_positions(wasps), _expected_slots(), "grid_4x2 slots centred on x 960")
	for wasp: Enemy in wasps:
		assert_eq(wasp.type_id, &"wasp")
		assert_lt(wasp.global_position.y, 1080.0 * 0.4, "inside the top 40%")


func test_formation_respawns_when_all_dead() -> void:
	var first: Array[Enemy] = _wasps()
	for wasp: Enemy in first:
		wasp.apply_damage(3, null)
	await wait_process_frames(2)
	var fresh: Array[Enemy] = _wasps()
	assert_eq(fresh.size(), 8, "8 alive again")
	for wasp: Enemy in fresh:
		assert_false(wasp.is_queued_for_deletion(), "new Wasp")
		assert_false(first.has(wasp), "not an old Wasp")
	assert_eq(_positions(fresh), _expected_slots(), "same slots")


func test_respawn_after_kill_inside_physics_callback() -> void:
	var wasps: Array[Enemy] = _wasps()
	for i: int in 7:
		wasps[i].apply_damage(3, null)
	var last: Enemy = wasps[7]
	var spawner: Spawner = _sandbox.get_node("Spawner") as Spawner
	for i: int in 3:
		spawner.spawn_projectile(&"laser_bolt",
			{"position": last.global_position + Vector2(0, 300), "velocity": Vector2(0, -1800), "damage": 1})
	await wait_physics_frames(30)
	var fresh: Array[Enemy] = _wasps()
	assert_eq(fresh.size(), 8, "8 alive again")
	for wasp: Enemy in fresh:
		assert_false(wasp.is_queued_for_deletion(), "new Wasp")
		assert_false(wasps.has(wasp), "not an old Wasp")
	assert_eq(_positions(fresh), _expected_slots(), "same slots")


func test_no_respawn_while_some_alive() -> void:
	var wasps: Array[Enemy] = _wasps()
	for i: int in 7:
		wasps[i].apply_damage(3, null)
	await wait_process_frames(2)
	assert_eq(_wasps().size(), 1, "only the survivor")


func test_asteroid_timer_spawns_every_interval() -> void:
	_sandbox.set_physics_process(false)
	_sandbox.rng.seed = 1234
	_sandbox.set("_asteroid_elapsed", 0.0)
	var asteroids: Node = _sandbox.get_node("World/Asteroids")
	for i: int in 179:
		_sandbox.step_asteroids(1.0 / 60.0)
	assert_eq(asteroids.get_child_count(), 0, "none before the first interval")
	_sandbox.step_asteroids(1.0 / 60.0)
	assert_eq(asteroids.get_child_count(), 1, "one after 3.0 s")
	for i: int in 180:
		_sandbox.step_asteroids(1.0 / 60.0)
	assert_eq(asteroids.get_child_count(), 2, "two after 6.0 s")
	for child: Node in asteroids.get_children():
		var rock: Asteroid = child as Asteroid
		rock.set_physics_process(false)
		assert_true(Asteroid.SIZES.has(rock.size))
		assert_gte(rock.global_position.x - rock.radius, 0.0, "fully inside the left edge")
		assert_lte(rock.global_position.x + rock.radius, 1920.0, "fully inside the right edge")
		assert_eq(rock.global_position.y, -rock.radius, "just above the top edge")


func test_asteroid_sizes_vary() -> void:
	_sandbox.set_physics_process(false)
	_sandbox.rng.seed = 42
	for i: int in 30:
		_sandbox.step_asteroids(3.0)
	var sizes: Dictionary = {}
	for child: Node in _sandbox.get_node("World/Asteroids").get_children():
		var rock: Asteroid = child as Asteroid
		rock.set_physics_process(false)
		sizes[rock.size] = true
		assert_gte(rock.global_position.x - rock.radius, 0.0, "fully inside the left edge")
		assert_lte(rock.global_position.x + rock.radius, 1920.0, "fully inside the right edge")
		assert_eq(rock.global_position.y, -rock.radius, "just above the top edge")
	assert_eq(sizes.size(), 3, "every size appears")


func test_paused_sandbox_spawns_no_asteroid() -> void:
	var asteroids: Node = _sandbox.get_node("World/Asteroids")
	_sandbox.set("_asteroid_elapsed", 2.99)
	PauseArbiter.push(&"menu")
	await wait_physics_frames(10)
	assert_eq(asteroids.get_child_count(), 0, "no asteroid while paused")
	PauseArbiter.pop(&"menu")
	await wait_physics_frames(10)
	assert_eq(asteroids.get_child_count(), 1, "timer resumes once unpaused")
