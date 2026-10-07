extends GutTest
## Combat through real physics: laser bolts kill a Wasp; an asteroid blocks bolts
## aimed at a Wasp behind it; missile hits and splash. Layer config checks.

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
	# Kills drive Feedback; a large kill would leave a hit-stop running.
	Feedback.reset()
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


func test_missile_hits_asteroid_and_stops() -> void:
	var wasp: Enemy = _spawner.spawn_enemy(&"wasp", {"position": Vector2(960, 200)})
	var rock: Asteroid = _spawner.spawn_asteroid({"size": &"large", "position": Vector2(960, 500)})
	assert_not_null(wasp)
	assert_not_null(rock)
	if wasp == null or rock == null:
		return
	rock.set_physics_process(false)
	var missile: Projectile = _spawner.spawn_projectile(&"missile", {"position": Vector2(960, 900), "velocity": Vector2(0, -900), "damage": 8})
	assert_not_null(missile)
	await wait_physics_frames(40)
	assert_eq(rock.hp, 22, "8 direct damage")
	assert_eq(wasp.hp, 3, "the wasp behind the asteroid takes none")
	assert_eq(_world.get_node("Projectiles").get_child_count(), 0, "missile stopped")


func test_missile_asteroid_hit_splashes_nearby_wasp() -> void:
	var rock: Asteroid = _spawner.spawn_asteroid({"size": &"large", "position": Vector2(960, 500)})
	# Impact is near (960, 610-625): this Wasp is ~100 px away and off the missile's path.
	var wasp: Enemy = _spawner.spawn_enemy(&"wasp", {"position": Vector2(1060, 620)})
	assert_not_null(rock)
	assert_not_null(wasp)
	if rock == null or wasp == null:
		return
	rock.set_physics_process(false)
	_spawner.spawn_projectile(&"missile", {"position": Vector2(960, 900), "velocity": Vector2(0, -900), "damage": 8})
	await wait_physics_frames(40)
	assert_eq(rock.hp, 22, "8 direct damage to the asteroid")
	# A Wasp has 3 HP, so exactly 3 splash damage kills it.
	assert_signal_emit_count(Events, "enemy_killed", 1)
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"wasp", Vector2(1060, 620), false])
	assert_true(not is_instance_valid(wasp) or wasp.is_queued_for_deletion(), "splashed wasp dies")
	assert_eq(_world.get_node("Projectiles").get_child_count(), 0, "missile stopped")


func test_missile_splash_in_formation() -> void:
	var wasps: Array[Enemy] = []
	for y: float in [160.0, 280.0]:
		for x: float in [720.0, 880.0, 1040.0, 1200.0]:
			var wasp: Enemy = _spawner.spawn_enemy(&"wasp", {"position": Vector2(x, y)})
			assert_not_null(wasp)
			if wasp == null:
				return
			wasps.append(wasp)
	var hit: Enemy = wasps[1]
	var below: Enemy = wasps[5]
	assert_eq(hit.global_position, Vector2(880, 160))
	assert_eq(below.global_position, Vector2(880, 280))
	_spawner.spawn_projectile(&"missile", {"position": Vector2(880, 220), "velocity": Vector2(0, -900), "damage": 8})
	await wait_physics_frames(10)
	assert_true(not is_instance_valid(hit) or hit.is_queued_for_deletion(), "direct hit dies")
	assert_true(not is_instance_valid(below) or below.is_queued_for_deletion(), "splashed wasp below dies")
	assert_signal_emit_count(Events, "enemy_killed", 2)
	for i: int in wasps.size():
		if i == 1 or i == 5:
			continue
		assert_true(is_instance_valid(wasps[i]), "wasp %d alive" % i)
		if is_instance_valid(wasps[i]):
			assert_eq(wasps[i].hp, 3, "wasp %d untouched" % i)
	assert_eq(_world.get_node("Projectiles").get_child_count(), 0, "missile spent")


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
