extends GutTest
## Projectile contract via laser_bolt.tscn: motion, off-screen free, one damage instance, scene shape.

const BOLT_SCENE: PackedScene = preload("res://entities/projectiles/laser_bolt.tscn")
const DamageTarget: GDScript = preload("res://tests/fixtures/damage_target.gd")
const DT: float = 1.0 / 60.0
const LAYER_PLAYER_SHOTS: int = 1 << 1


func after_each() -> void:
	Feedback.reset()


func _make_bolt(pos: Vector2, velocity: Vector2 = Vector2(0, -1800), damage: int = 1) -> Projectile:
	var bolt: Projectile = BOLT_SCENE.instantiate() as Projectile
	bolt.setup({"position": pos, "velocity": velocity, "damage": damage})
	add_child_autofree(bolt)
	bolt.set_physics_process(false)
	return bolt


func _make_target(with_damage: bool = true) -> Area2D:
	var target: Area2D = (DamageTarget.new() as Area2D) if with_damage else Area2D.new()
	add_child_autofree(target)
	return target


func _calls(target: Area2D) -> Array:
	return target.get("calls") as Array


func test_setup_stores_and_ready_applies() -> void:
	var bolt: Projectile = BOLT_SCENE.instantiate() as Projectile
	bolt.setup({"position": Vector2(300, 400), "velocity": Vector2(0, -50), "damage": 3})
	assert_eq(bolt.position, Vector2.ZERO, "setup does not apply the position")
	add_child_autofree(bolt)
	bolt.set_physics_process(false)
	assert_eq(bolt.global_position, Vector2(300, 400))
	assert_eq(bolt.velocity, Vector2(0, -50))
	assert_eq(bolt.damage, 3)
	assert_true(bolt.is_in_group(&"projectiles"))


func test_bolt_moves_straight_by_velocity() -> void:
	var bolt: Projectile = _make_bolt(Vector2(960, 500))
	bolt._physics_process(DT)
	assert_almost_eq(bolt.global_position, Vector2(960, 470), Vector2(0.0001, 0.0001), "moves (0, -30)")
	assert_eq(bolt.global_position.x, 960.0, "never sideways")


func test_bolt_freed_off_screen() -> void:
	var bolt: Projectile = _make_bolt(Vector2(960, -40))
	bolt._physics_process(DT)
	assert_true(bolt.is_queued_for_deletion(), "y -70 is past the 64 px margin")


func test_bolt_within_margin_survives() -> void:
	var bolt: Projectile = _make_bolt(Vector2(960, -20), Vector2.ZERO)
	bolt._physics_process(DT)
	assert_false(bolt.is_queued_for_deletion(), "y -20 is inside the 64 px margin")


func test_bolt_on_screen_survives() -> void:
	var bolt: Projectile = _make_bolt(Vector2(960, 500))
	bolt._physics_process(DT)
	assert_false(bolt.is_queued_for_deletion())


func test_hit_applies_damage_once_then_frees() -> void:
	var bolt: Projectile = _make_bolt(Vector2(960, 500))
	var target: Area2D = _make_target()
	bolt._on_area_entered(target)
	var calls: Array = _calls(target)
	assert_eq(calls.size(), 1)
	if calls.size() == 1:
		assert_eq(calls[0].amount, 1)
		assert_eq(calls[0].source, bolt)
	assert_true(bolt.is_queued_for_deletion())


func test_double_overlap_damages_only_first() -> void:
	var bolt: Projectile = _make_bolt(Vector2(960, 500))
	var first: Area2D = _make_target()
	var second: Area2D = _make_target()
	bolt._on_area_entered(first)
	bolt._on_area_entered(second)
	assert_eq(_calls(first).size(), 1, "first damaged")
	assert_eq(_calls(second).size(), 0, "second untouched")


func test_area_without_apply_damage_still_frees() -> void:
	var bolt: Projectile = _make_bolt(Vector2(960, 500))
	var target: Area2D = _make_target(false)
	bolt._on_area_entered(target)
	assert_true(bolt.is_queued_for_deletion())


func test_real_overlap_through_physics_damages_once() -> void:
	var target: Area2D = DamageTarget.new() as Area2D
	target.collision_layer = 1 << 2  # enemies
	target.collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 20.0
	shape.shape = circle
	target.add_child(shape)
	target.position = Vector2(960, 500)
	add_child_autofree(target)
	var bolt: Projectile = BOLT_SCENE.instantiate() as Projectile
	bolt.setup({"position": Vector2(960, 500), "velocity": Vector2.ZERO, "damage": 1})
	add_child_autofree(bolt)
	await wait_physics_frames(5)
	var calls: Array = _calls(target)
	assert_eq(calls.size(), 1, "one apply_damage through area_entered")
	if calls.size() == 1:
		assert_eq(calls[0].amount, 1)
		assert_eq(calls[0].source, bolt)
	assert_true(not is_instance_valid(bolt) or bolt.is_queued_for_deletion(), "bolt freed")


# --- Scene shape --------------------------------------------------------------

func test_scene_root_layers() -> void:
	var bolt: Projectile = _make_bolt(Vector2(960, 500))
	assert_true(bolt is LaserBolt, "root is a LaserBolt (Projectile)")
	assert_eq(bolt.collision_layer, LAYER_PLAYER_SHOTS, "player_shots")
	assert_eq(bolt.collision_mask, CollisionLayers.MASK_PLAYER_SHOTS, "enemies + asteroids + convoy")
	assert_false(bolt.monitorable)
	assert_true(bolt.monitoring)


func test_capsule_prevents_tunnelling() -> void:
	var bolt: Projectile = _make_bolt(Vector2(960, 500))
	var shapes: Array[CollisionShape2D] = []
	for child: Node in bolt.get_children():
		if child is CollisionShape2D:
			shapes.append(child as CollisionShape2D)
	assert_eq(shapes.size(), 1, "one collision shape")
	if shapes.is_empty():
		return
	var capsule: CapsuleShape2D = shapes[0].shape as CapsuleShape2D
	assert_not_null(capsule, "CapsuleShape2D")
	if capsule != null:
		assert_gte(capsule.height, Config.num("weapons.laser.speed_px_s") / float(Engine.physics_ticks_per_second), "height >= distance per physics tick")
	assert_eq(shapes[0].rotation, 0.0, "vertical, aligned with travel")


func test_twin_visual_sprites() -> void:
	var bolt: Projectile = _make_bolt(Vector2(960, 500))
	var xs: Array = []
	for child: Node in bolt.get_children():
		if child is Sprite2D:
			xs.append((child as Sprite2D).position.x)
	xs.sort()
	assert_eq(xs, [-8.0, 8.0], "two sprites at x -8 and 8")


# --- Convoy block (Story 6.1, DW-32) ----------------------------------------------

const CONVOY_SCENE: PackedScene = preload("res://entities/allies/convoy.tscn")


## A world with Effects (so Feedback spawns explosions) and its Spawner.
func _effects_world() -> Node2D:
	var world: Node2D = Node2D.new()
	for container: String in ["Projectiles", "Enemies", "Asteroids", "Effects"]:
		var node: Node2D = Node2D.new()
		node.name = container
		world.add_child(node)
	add_child_autofree(world)
	var spawner: Spawner = Spawner.new()
	spawner.world = world
	add_child_autofree(spawner)
	return world


func _explosion_scales(world: Node2D) -> Array[float]:
	var out: Array[float] = []
	for child: Node in world.get_node("Effects").get_children():
		if child is Explosion:
			out.append((child as Explosion).explosion_scale)
	return out


func test_is_convoy_tests_the_layer_bit() -> void:
	var convoy_area: Area2D = _make_target()
	convoy_area.collision_layer = CollisionLayers.CONVOY
	var both: Area2D = _make_target()
	both.collision_layer = CollisionLayers.CONVOY | CollisionLayers.ENEMIES
	var enemy: Area2D = _make_target()
	enemy.collision_layer = CollisionLayers.ENEMIES
	assert_true(Projectile.is_convoy(convoy_area))
	assert_true(Projectile.is_convoy(both))
	assert_false(Projectile.is_convoy(enemy))
	assert_false(Projectile.is_convoy(null))


func test_bolt_blocked_by_a_convoy_area_without_damage() -> void:
	var world: Node2D = _effects_world()
	var bolt: Projectile = _make_bolt(Vector2(960, 500))
	var convoy_area: Area2D = _make_target()
	convoy_area.collision_layer = CollisionLayers.CONVOY
	bolt._on_area_entered(convoy_area)
	assert_eq(_calls(convoy_area).size(), 0, "no apply_damage on the convoy")
	assert_true(bolt.is_queued_for_deletion(), "the shot is stopped and freed")
	assert_eq(_explosion_scales(world), [Config.num("feedback.tiers.small.explosion_scale")] as Array[float], "SMALL blocked-shot effect")


func test_bolt_still_damages_an_enemy_area() -> void:
	var bolt: Projectile = _make_bolt(Vector2(960, 500))
	var enemy: Area2D = _make_target()
	enemy.collision_layer = CollisionLayers.ENEMIES
	bolt._on_area_entered(enemy)
	assert_eq(_calls(enemy).size(), 1)


func test_real_bolt_into_a_real_convoy_ship_leaves_hp_unchanged() -> void:
	var convoy: Convoy = CONVOY_SCENE.instantiate() as Convoy
	add_child_autofree(convoy)
	convoy.set_physics_process(false)
	var ship: ConvoyShip = convoy.ships()[Convoy.FLANK_TOP]
	var bolt: Projectile = BOLT_SCENE.instantiate() as Projectile
	bolt.setup({"position": ship.global_position + Vector2(0, 120), "velocity": Vector2(0, -1800), "damage": 1})
	add_child_autofree(bolt)
	await wait_physics_frames(10)
	assert_eq(convoy.hp(), convoy.max_hp(), "convoy HP unchanged")
	assert_true(not is_instance_valid(bolt) or bolt.is_queued_for_deletion(), "bolt stopped by the hull")


## Story 6.3: the base damage-amount hook returns the projectile's own damage
## for any area (EnemyBullet overrides it for the convoy).
func test_base_damage_for_returns_damage() -> void:
	var bolt: Projectile = _make_bolt(Vector2(960, 500), Vector2(0, -1800), 3)
	var enemy: Area2D = _make_target()
	enemy.collision_layer = CollisionLayers.ENEMIES
	var convoy_area: Area2D = _make_target()
	convoy_area.collision_layer = CollisionLayers.CONVOY
	assert_eq(bolt._damage_for(enemy), 3)
	assert_eq(bolt._damage_for(convoy_area), 3)
	bolt._on_area_entered(enemy)
	var calls: Array = _calls(enemy)
	assert_eq(calls.size(), 1)
	if calls.size() == 1:
		assert_eq(calls[0].amount, 3, "_on_area_entered applies _damage_for")


## Story 6.4: setup's optional from_ally key (ally shots); missing keeps false.
func test_setup_from_ally_key() -> void:
	var bolt: Projectile = BOLT_SCENE.instantiate() as Projectile
	assert_false(bolt.from_ally, "default false")
	bolt.setup({"position": Vector2(300, 400), "from_ally": true})
	assert_true(bolt.from_ally)
	bolt.setup({"damage": 2})
	assert_true(bolt.from_ally, "a missing key keeps the current value")
	bolt.free()
