extends GutTest
## Spawner: registry lookup, setup before add_child into World/Projectiles, error paths.

var _world: Node2D
var _projectiles: Node2D


func before_each() -> void:
	_world = Node2D.new()
	_projectiles = Node2D.new()
	_projectiles.name = "Projectiles"
	_world.add_child(_projectiles)
	add_child_autofree(_world)


func after_each() -> void:
	_world = null
	_projectiles = null


func _make_spawner(world: Node2D) -> Spawner:
	var spawner: Spawner = Spawner.new()
	spawner.world = world
	add_child_autofree(spawner)
	return spawner


func test_registry_has_laser_bolt() -> void:
	assert_true(EntityRegistry.PROJECTILES.has(&"laser_bolt"))


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


func test_unknown_id_returns_null() -> void:
	var spawner: Spawner = _make_spawner(_world)
	assert_null(spawner.spawn_projectile(&"nope", {}))
	assert_push_error("nope")
	assert_eq(_projectiles.get_child_count(), 0, "nothing added")


func test_missing_container_logs_and_returns_null() -> void:
	var bare: Node2D = Node2D.new()
	add_child_autofree(bare)
	var spawner: Spawner = _make_spawner(bare)
	assert_push_error("Projectiles")
	assert_null(spawner.spawn_projectile(&"laser_bolt", {}))


func test_missing_world_logs_and_returns_null() -> void:
	var spawner: Spawner = _make_spawner(null)
	assert_push_error("no world")
	assert_null(spawner.spawn_projectile(&"laser_bolt", {}))
