extends GutTest
## Spawner: registry lookup, setup before add_child into the World containers,
## error paths; energy orbs into the optional Pickups container (Story 3.3).

var _world: Node2D
var _projectiles: Node2D
var _enemies: Node2D
var _asteroids: Node2D


func before_each() -> void:
	_world = Node2D.new()
	_projectiles = _add_container("Projectiles")
	_enemies = _add_container("Enemies")
	_asteroids = _add_container("Asteroids")
	add_child_autofree(_world)


func after_each() -> void:
	_world = null
	_projectiles = null
	_enemies = null
	_asteroids = null


func _add_container(container_name: String) -> Node2D:
	var node: Node2D = Node2D.new()
	node.name = container_name
	_world.add_child(node)
	return node


func _make_spawner(world: Node2D) -> Spawner:
	var spawner: Spawner = Spawner.new()
	spawner.world = world
	add_child_autofree(spawner)
	return spawner


func test_registry_has_laser_bolt() -> void:
	assert_true(EntityRegistry.PROJECTILES.has(&"laser_bolt"))


func test_registry_has_wasp_and_asteroid() -> void:
	assert_true(EntityRegistry.ENEMIES.has(&"wasp"))
	assert_not_null(EntityRegistry.ASTEROID)


func test_registry_has_lancer_and_enemy_bullet() -> void:
	assert_true(EntityRegistry.ENEMIES.has(&"lancer"))
	assert_true(EntityRegistry.PROJECTILES.has(&"enemy_bullet"))
	assert_true(EntityRegistry.enemy_types().has(&"lancer"), "a known level type")


func test_registry_has_needle_and_needle_bolt() -> void:
	assert_true(EntityRegistry.ENEMIES.has(&"needle"))
	assert_true(EntityRegistry.PROJECTILES.has(&"needle_bolt"))
	assert_true(EntityRegistry.enemy_types().has(&"needle"), "a known level type")


func test_registry_has_bastion() -> void:
	assert_true(EntityRegistry.ENEMIES.has(&"bastion"))
	assert_true(EntityRegistry.enemy_types().has(&"bastion"), "a known level type")


func test_registry_has_hunter_wasp_and_its_flag() -> void:
	assert_true(EntityRegistry.ENEMIES.has(&"hunter_wasp"))
	assert_true(EntityRegistry.enemy_types().has(&"hunter_wasp"), "always a known level type (F14)")
	assert_eq(EntityRegistry.ENEMY_FLAGS.get(&"hunter_wasp", ""), "hunter_wasp", "gated by flags.hunter_wasp")


func test_registry_has_the_rowless_ungated_maul() -> void:
	assert_true(EntityRegistry.ENEMIES.has(&"maul"))
	assert_true(EntityRegistry.enemy_types().has(&"maul"), "a known level type")
	assert_true(EntityRegistry.ROWLESS_TYPES.has(&"maul"), "never holds its slot")
	assert_false(EntityRegistry.ENEMY_FLAGS.has(&"maul"), "not flag-gated (MUST)")


func test_spawn_enemy_maul() -> void:
	var spawner: Spawner = _make_spawner(_world)
	var enemy: Enemy = spawner.spawn_enemy(&"maul", {"position": Vector2(640, 300)})
	assert_true(enemy is Maul)
	if enemy == null:
		return
	enemy.set_physics_process(false)
	assert_eq(enemy.get_parent(), _enemies)
	assert_eq(enemy.global_position, Vector2(640, 300))
	assert_eq(enemy.spawner, spawner)
	assert_true(enemy.is_in_group(&"enemies"))


func test_spawned_enemy_gets_the_spawner() -> void:
	var spawner: Spawner = _make_spawner(_world)
	for type_id: StringName in [&"wasp", &"lancer", &"needle", &"bastion", &"hunter_wasp", &"maul"]:
		var enemy: Enemy = spawner.spawn_enemy(type_id, {"position": Vector2(640, 160)})
		assert_not_null(enemy)
		if enemy != null:
			enemy.set_physics_process(false)
			assert_eq(enemy.spawner, spawner, "%s.spawner is the Spawner" % type_id)


func test_spawn_enemy_bullet() -> void:
	var spawner: Spawner = _make_spawner(_world)
	var bullet: Projectile = spawner.spawn_projectile(&"enemy_bullet",
		{"position": Vector2(400, 300), "velocity": Vector2(0, 450), "damage": 1})
	assert_true(bullet is EnemyBullet)
	if bullet == null:
		return
	bullet.set_physics_process(false)
	assert_eq(bullet.get_parent(), _projectiles)
	assert_eq(bullet.global_position, Vector2(400, 300))


func test_spawn_parents_into_projectiles_with_params() -> void:
	var spawner: Spawner = _make_spawner(_world)
	var bolt: Projectile = spawner.spawn_projectile(&"laser_bolt",
		{"position": Vector2(400, 700), "velocity": Vector2(0, -1800), "damage": 1})
	assert_not_null(bolt)
	if bolt == null:
		return
	bolt.set_physics_process(false)
	assert_eq(bolt.get_parent(), _projectiles)
	assert_eq(bolt.global_position, Vector2(400, 700))
	assert_eq(bolt.velocity, Vector2(0, -1800))
	assert_eq(bolt.damage, 1)
	assert_true(bolt.is_in_group(&"projectiles"))
	assert_true(bolt is LaserBolt)


func test_spawn_enemy_parents_into_enemies_with_position() -> void:
	var spawner: Spawner = _make_spawner(_world)
	var wasp: Enemy = spawner.spawn_enemy(&"wasp", {"position": Vector2(640, 160)})
	assert_not_null(wasp)
	if wasp == null:
		return
	assert_eq(wasp.get_parent(), _enemies)
	assert_eq(wasp.global_position, Vector2(640, 160))
	assert_eq(wasp.type_id, &"wasp")


func test_spawn_asteroid_parents_into_asteroids_with_position() -> void:
	var spawner: Spawner = _make_spawner(_world)
	var rock: Asteroid = spawner.spawn_asteroid({"size": &"medium", "position": Vector2(500, -64)})
	assert_not_null(rock)
	if rock == null:
		return
	rock.set_physics_process(false)
	assert_eq(rock.get_parent(), _asteroids)
	assert_eq(rock.global_position, Vector2(500, -64))
	assert_eq(rock.size, &"medium")


func test_unknown_id_returns_null() -> void:
	var spawner: Spawner = _make_spawner(_world)
	assert_null(spawner.spawn_projectile(&"nope", {}))
	assert_push_error("nope")
	assert_eq(_projectiles.get_child_count(), 0, "nothing added")


func test_unknown_enemy_returns_null() -> void:
	var spawner: Spawner = _make_spawner(_world)
	assert_null(spawner.spawn_enemy(&"nope", {}))
	assert_push_error("nope")
	assert_eq(_enemies.get_child_count(), 0, "nothing added")


func test_unknown_asteroid_size_returns_null() -> void:
	var spawner: Spawner = _make_spawner(_world)
	assert_null(spawner.spawn_asteroid({"size": &"huge"}))
	assert_push_error("huge")
	assert_eq(_asteroids.get_child_count(), 0, "nothing added")


func test_missing_container_logs_and_returns_null() -> void:
	var bare: Node2D = Node2D.new()
	add_child_autofree(bare)
	var spawner: Spawner = _make_spawner(bare)
	assert_push_error("Projectiles")
	assert_push_error("Enemies")
	assert_push_error("Asteroids")
	assert_null(spawner.spawn_projectile(&"laser_bolt", {}))
	assert_null(spawner.spawn_enemy(&"wasp", {}))
	assert_null(spawner.spawn_asteroid({"size": &"small"}))


func test_missing_world_logs_and_returns_null() -> void:
	var spawner: Spawner = _make_spawner(null)
	assert_push_error("no world")
	assert_null(spawner.spawn_projectile(&"laser_bolt", {}))


# --- Energy orbs (Story 3.3) -------------------------------------------------------

var _spawn_lines: Array[String] = []


func _capture_spawn(level: String, category: String, msg: String) -> void:
	_spawn_lines.append(Log.format(level, category, msg))


func test_registry_has_the_energy_orb() -> void:
	assert_not_null(EntityRegistry.ENERGY_ORB)
	var orb: Node = EntityRegistry.ENERGY_ORB.instantiate()
	assert_true(orb is EnergyOrb)
	orb.free()


func test_spawn_orb_parents_into_pickups() -> void:
	var pickups: Node2D = _add_container("Pickups")
	var spawner: Spawner = _make_spawner(_world)
	var orb: EnergyOrb = spawner.spawn_orb({"position": Vector2(300, 400)})
	assert_not_null(orb)
	if orb == null:
		return
	orb.set_physics_process(false)
	assert_eq(orb.get_parent(), pickups)
	assert_eq(orb.global_position, Vector2(300, 400))
	assert_true(orb.is_in_group(&"pickups"))


func test_spawn_orb_without_pickups_returns_null() -> void:
	_spawn_lines.clear()
	var debug_was: bool = Log.debug_enabled
	Log.debug_enabled = true
	Log.sink = _capture_spawn
	var spawner: Spawner = _make_spawner(_world)
	Log.sink = Callable()
	Log.debug_enabled = debug_was
	var pickup_lines: int = 0
	for line: String in _spawn_lines:
		if line.begins_with("[DEBUG][spawn]") and line.contains("Pickups"):
			pickup_lines += 1
	assert_eq(pickup_lines, 1, "one DEBUG line for the missing container")
	assert_null(spawner.spawn_orb({"position": Vector2(300, 400)}))


func test_spawned_asteroid_gets_the_spawner() -> void:
	var spawner: Spawner = _make_spawner(_world)
	var rock: Asteroid = spawner.spawn_asteroid({"size": &"small", "position": Vector2(500, 300)})
	assert_not_null(rock)
	if rock == null:
		return
	rock.set_physics_process(false)
	assert_eq(rock.spawner, spawner)


# --- Convoy (Story 6.1) --------------------------------------------------------------

func test_registry_has_the_convoy() -> void:
	assert_not_null(EntityRegistry.CONVOY)
	var convoy: Node = EntityRegistry.CONVOY.instantiate()
	assert_true(convoy is Convoy)
	convoy.free()


func test_spawn_convoy_parents_into_allies() -> void:
	var allies: Node2D = _add_container("Allies")
	var spawner: Spawner = _make_spawner(_world)
	watch_signals(Events)
	var convoy: Convoy = spawner.spawn_convoy({})
	assert_not_null(convoy)
	if convoy == null:
		return
	convoy.set_physics_process(false)
	assert_eq(convoy.get_parent(), allies, "under World/Allies")
	assert_true(convoy.is_in_group(&"convoy"))
	assert_eq(convoy.ships().size(), 3)
	assert_signal_emitted_with_parameters(Events, "convoy_hp_changed", [100, 100])


func test_spawn_convoy_without_allies_returns_null() -> void:
	_spawn_lines.clear()
	var debug_was: bool = Log.debug_enabled
	Log.debug_enabled = true
	Log.sink = _capture_spawn
	var spawner: Spawner = _make_spawner(_world)
	var convoy: Convoy = spawner.spawn_convoy({})
	Log.sink = Callable()
	Log.debug_enabled = debug_was
	assert_null(convoy)
	var allies_lines: int = 0
	for line: String in _spawn_lines:
		if line.begins_with("[DEBUG][spawn]") and line.contains("Allies"):
			allies_lines += 1
	assert_eq(allies_lines, 2, "one DEBUG line for the missing container, one for the refused spawn")
