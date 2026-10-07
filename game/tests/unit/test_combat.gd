extends GutTest
## Combat through real physics: laser bolts kill a Wasp; an asteroid blocks bolts
## aimed at a Wasp behind it. Layer config checks.

const BOLT_SPEED: float = 1800.0

var _world: Node2D
var _spawner: Spawner


func before_each() -> void:
	watch_signals(Events)
	_world = Node2D.new()
	for container: String in ["Projectiles", "Enemies", "Asteroids"]:
		var node: Node2D = Node2D.new()
		node.name = container
		_world.add_child(node)
	add_child_autofree(_world)
	_spawner = Spawner.new()
	_spawner.world = _world
	add_child_autofree(_spawner)


func after_each() -> void:
	_world = null
	_spawner = null


func _fire_bolts(from: Vector2, count: int) -> void:
	for i: int in count:
		_spawner.spawn_projectile(&"laser_bolt", {"position": from, "velocity": Vector2(0, -BOLT_SPEED), "damage": 1})


func test_three_bolts_kill_a_wasp() -> void:
	var wasp: Enemy = _spawner.spawn_enemy(&"wasp", {"position": Vector2(960, 300)})
	assert_not_null(wasp)
	if wasp == null:
		return
	# The Wasp is freed by the time we assert, so count resolved through a closure.
	var resolved_count: Array[int] = [0]
	wasp.resolved.connect(func() -> void: resolved_count[0] += 1)
	_fire_bolts(Vector2(960, 700), 3)
	await wait_physics_frames(30)
	assert_signal_emit_count(Events, "enemy_killed", 1)
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"wasp", Vector2(960, 300), false])
	assert_eq(resolved_count[0], 1, "resolved once")
	assert_true(not is_instance_valid(wasp) or wasp.is_queued_for_deletion(), "wasp freed")
	assert_eq(_world.get_node("Projectiles").get_child_count(), 0, "every bolt spent")


func test_asteroid_blocks_bolts_aimed_at_a_wasp() -> void:
	var wasp: Enemy = _spawner.spawn_enemy(&"wasp", {"position": Vector2(960, 200)})
	var rock: Asteroid = _spawner.spawn_asteroid({"size": &"large", "position": Vector2(960, 500)})
	assert_not_null(wasp)
	assert_not_null(rock)
	if wasp == null or rock == null:
		return
	rock.set_physics_process(false)
	_fire_bolts(Vector2(960, 900), 3)
	await wait_physics_frames(40)
	assert_eq(rock.hp, 27, "1 damage per bolt")
	assert_eq(wasp.hp, 3, "the wasp takes none")
	assert_signal_not_emitted(Events, "enemy_killed")
	assert_eq(_world.get_node("Projectiles").get_child_count(), 0, "every bolt stopped")


func test_layer_constants() -> void:
	assert_eq(CollisionLayers.MASK_PLAYER_SHOTS & CollisionLayers.ASTEROIDS, CollisionLayers.ASTEROIDS, "player_shots mask asteroids")
	assert_eq(CollisionLayers.MASK_ENEMY_SHOTS & CollisionLayers.ASTEROIDS, CollisionLayers.ASTEROIDS, "enemy_shots mask asteroids")
	assert_eq(CollisionLayers.MASK_PLAYER_SHOTS, CollisionLayers.ENEMIES | CollisionLayers.ASTEROIDS | CollisionLayers.CONVOY)
	assert_eq(CollisionLayers.MASK_ENEMY_SHOTS, CollisionLayers.PLAYER | CollisionLayers.ASTEROIDS | CollisionLayers.CONVOY)


func test_laser_bolt_masks_enemies_and_asteroids() -> void:
	var bolt: Projectile = _spawner.spawn_projectile(&"laser_bolt", {"position": Vector2(960, 500), "velocity": Vector2.ZERO})
	assert_not_null(bolt)
	if bolt == null:
		return
	bolt.set_physics_process(false)
	assert_eq(bolt.collision_layer, CollisionLayers.PLAYER_SHOTS)
	assert_eq(bolt.collision_mask & CollisionLayers.ASTEROIDS, CollisionLayers.ASTEROIDS)
	assert_eq(bolt.collision_mask & CollisionLayers.ENEMIES, CollisionLayers.ENEMIES)


func test_project_layer_bits_match_constants() -> void:
	var expected: Dictionary = {
		"player": CollisionLayers.PLAYER,
		"player_shots": CollisionLayers.PLAYER_SHOTS,
		"enemies": CollisionLayers.ENEMIES,
		"enemy_shots": CollisionLayers.ENEMY_SHOTS,
		"asteroids": CollisionLayers.ASTEROIDS,
		"pickups": CollisionLayers.PICKUPS,
		"convoy": CollisionLayers.CONVOY,
		"allies": CollisionLayers.ALLIES,
	}
	for i: int in range(1, 9):
		var layer_name: String = ProjectSettings.get_setting("layer_names/2d_physics/layer_%d" % i, "")
		assert_true(expected.has(layer_name), "layer %d named" % i)
		if expected.has(layer_name):
			assert_eq(1 << (i - 1), expected[layer_name], "layer %d '%s' bit" % [i, layer_name])
	assert_eq(ProjectSettings.get_setting("layer_names/2d_physics/layer_5", ""), "asteroids")
