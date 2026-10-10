extends GutTest
## Missile: scene shape, orientation along travel, splash damage, registry entry.

const MISSILE_SCENE: PackedScene = preload("res://entities/projectiles/missile.tscn")
const DamageTarget: GDScript = preload("res://tests/fixtures/damage_target.gd")
const IMPACT: Vector2 = Vector2(500, 500)


func after_each() -> void:
	Feedback.reset()


func _make_missile(pos: Vector2, velocity: Vector2 = Vector2.ZERO, damage: int = 8) -> Missile:
	var missile: Missile = MISSILE_SCENE.instantiate() as Missile
	missile.setup({"position": pos, "velocity": velocity, "damage": damage})
	add_child_autofree(missile)
	missile.set_physics_process(false)
	return missile


## A shapeless recording target, optionally in a group.
func _make_target(pos: Vector2, group: StringName = &"") -> Area2D:
	var target: Area2D = DamageTarget.new() as Area2D
	target.position = pos
	if group != &"":
		target.add_to_group(group)
	add_child_autofree(target)
	return target


func _amounts(target: Area2D) -> Array:
	var out: Array = []
	for call: Dictionary in target.get("calls") as Array:
		out.append(call.amount)
	return out


# --- Scene shape --------------------------------------------------------------

func test_scene_root_and_layers() -> void:
	var missile: Missile = _make_missile(IMPACT)
	assert_true(missile is Projectile, "root is a Missile (Projectile)")
	assert_eq(missile.collision_layer, CollisionLayers.PLAYER_SHOTS)
	assert_eq(missile.collision_mask, CollisionLayers.MASK_PLAYER_SHOTS)
	assert_false(missile.monitorable)
	assert_true(missile.monitoring)


func test_capsule_prevents_tunnelling() -> void:
	var missile: Missile = _make_missile(IMPACT)
	var shapes: Array[CollisionShape2D] = []
	for child: Node in missile.get_children():
		if child is CollisionShape2D:
			shapes.append(child as CollisionShape2D)
	assert_eq(shapes.size(), 1, "one collision shape")
	if shapes.is_empty():
		return
	var capsule: CapsuleShape2D = shapes[0].shape as CapsuleShape2D
	assert_not_null(capsule, "CapsuleShape2D")
	if capsule != null:
		assert_gte(capsule.height, 15.0)
		assert_gte(capsule.height, Config.num("weapons.missile.speed_px_s") / float(Engine.physics_ticks_per_second), "height >= distance per physics tick")
	assert_eq(shapes[0].rotation, 0.0, "capsule along local Y")


func test_smoke_trail() -> void:
	var missile: Missile = _make_missile(IMPACT)
	var trail: GPUParticles2D = missile.get_node_or_null(^"SmokeTrail") as GPUParticles2D
	assert_not_null(trail, "SmokeTrail is a GPUParticles2D")
	if trail == null:
		return
	assert_true(trail.emitting)
	assert_false(trail.local_coords)
	assert_lte(trail.amount, 32)


func test_reads_splash_tuning() -> void:
	var missile: Missile = _make_missile(IMPACT)
	assert_eq(missile.splash_damage, 3)
	assert_eq(missile.splash_radius, 120.0)


# --- Orientation --------------------------------------------------------------

func test_capsule_axis_points_along_velocity() -> void:
	var velocity: Vector2 = Vector2(0.6, -0.8) * 900.0
	var missile: Missile = _make_missile(IMPACT, velocity)
	assert_almost_eq(missile.rotation, velocity.angle() + PI / 2.0, 0.0001)
	var axis: Vector2 = missile.global_transform.y.normalized()
	assert_almost_eq(axis.cross(velocity.normalized()), 0.0, 0.0001, "capsule axis parallel to travel")
	assert_almost_eq(-axis.dot(velocity.normalized()), 1.0, 0.0001, "nose (local -Y) leads")


func test_straight_up_keeps_zero_rotation() -> void:
	var missile: Missile = _make_missile(IMPACT, Vector2(0, -900))
	assert_almost_eq(missile.rotation, 0.0, 0.0001)


# --- Splash -------------------------------------------------------------------

func test_splash_row() -> void:
	var missile: Missile = _make_missile(IMPACT)
	var a: Area2D = _make_target(IMPACT + Vector2(10, 0), &"enemies")
	var b: Area2D = _make_target(IMPACT + Vector2(0, -100), &"enemies")
	var c: Area2D = _make_target(IMPACT + Vector2(120, 0), &"enemies")
	var d: Area2D = _make_target(IMPACT + Vector2(121, 0), &"enemies")
	var e: Area2D = _make_target(IMPACT + Vector2(-60, 0), &"asteroids")
	var f: Area2D = _make_target(IMPACT + Vector2(0, 50))
	missile._on_area_entered(a)
	assert_eq(_amounts(a), [8], "A: direct hit only")
	assert_eq(_amounts(b), [3], "B at 100 px")
	assert_eq(_amounts(c), [3], "C at exactly 120 px")
	assert_eq(_amounts(d), [], "D at 121 px")
	assert_eq(_amounts(e), [3], "E asteroid at 60 px")
	assert_eq(_amounts(f), [], "F in no group")
	assert_eq((b.get("calls") as Array)[0].source, missile, "splash source is the missile")
	assert_true(missile.is_queued_for_deletion())


func test_node_in_both_groups_splashed_once() -> void:
	var missile: Missile = _make_missile(IMPACT)
	var a: Area2D = _make_target(IMPACT, &"enemies")
	var both: Area2D = _make_target(IMPACT + Vector2(30, 0), &"enemies")
	both.add_to_group(&"asteroids")
	missile._on_area_entered(a)
	assert_eq(_amounts(both), [3])


func test_queued_target_skipped() -> void:
	var missile: Missile = _make_missile(IMPACT)
	var a: Area2D = _make_target(IMPACT, &"enemies")
	var dying: Area2D = _make_target(IMPACT + Vector2(20, 0), &"enemies")
	dying.queue_free()
	missile._on_area_entered(a)
	assert_eq(_amounts(dying), [], "already queued for deletion")


func test_second_overlap_does_not_splash_again() -> void:
	var missile: Missile = _make_missile(IMPACT)
	var a: Area2D = _make_target(IMPACT, &"enemies")
	var b: Area2D = _make_target(IMPACT + Vector2(50, 0), &"enemies")
	missile._on_area_entered(a)
	missile._on_area_entered(b)
	assert_eq(_amounts(a), [8])
	assert_eq(_amounts(b), [3], "spent missile: no second hit or splash")


func test_real_physics_hit_splashes() -> void:
	var a: Area2D = DamageTarget.new() as Area2D
	a.collision_layer = CollisionLayers.ENEMIES
	a.collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 20.0
	shape.shape = circle
	a.add_child(shape)
	a.position = IMPACT
	a.add_to_group(&"enemies")
	add_child_autofree(a)
	var b: Area2D = _make_target(IMPACT + Vector2(0, -100), &"enemies")
	var missile: Missile = MISSILE_SCENE.instantiate() as Missile
	missile.setup({"position": IMPACT, "velocity": Vector2.ZERO, "damage": 8})
	add_child_autofree(missile)
	await wait_physics_frames(5)
	assert_eq(_amounts(a), [8], "one direct hit through area_entered")
	assert_eq(_amounts(b), [3], "splash")
	assert_true(not is_instance_valid(missile) or missile.is_queued_for_deletion(), "missile freed")


func test_registry_has_missile() -> void:
	assert_true(EntityRegistry.PROJECTILES.has(&"missile"))
	var missile: Node = (EntityRegistry.PROJECTILES[&"missile"] as PackedScene).instantiate()
	assert_true(missile is Missile)
	missile.free()


# --- Convoy fizzle (Story 6.1, DW-33, GDD #46) -------------------------------------

const CONVOY_SCENE: PackedScene = preload("res://entities/allies/convoy.tscn")


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


func test_missile_into_a_convoy_area_fizzles() -> void:
	var world: Node2D = _effects_world()
	var missile: Missile = _make_missile(IMPACT)
	var hull: Area2D = _make_target(IMPACT)
	hull.collision_layer = CollisionLayers.CONVOY
	var enemy: Area2D = _make_target(IMPACT + Vector2(30, 0), &"enemies")
	var rock: Area2D = _make_target(IMPACT + Vector2(0, -60), &"asteroids")
	missile._on_area_entered(hull)
	assert_eq(_amounts(hull), [], "no convoy damage")
	assert_eq(_amounts(enemy), [], "no splash on a nearby enemy")
	assert_eq(_amounts(rock), [], "no splash on a nearby asteroid")
	assert_true(missile.is_queued_for_deletion(), "freed")
	assert_eq(_explosion_scales(world), [Config.num("feedback.tiers.small.explosion_scale")] as Array[float], "SMALL, not MEDIUM")


func test_missile_hit_on_an_enemy_still_plays_medium() -> void:
	var world: Node2D = _effects_world()
	var missile: Missile = _make_missile(IMPACT)
	var a: Area2D = _make_target(IMPACT, &"enemies")
	missile._on_area_entered(a)
	assert_eq(_explosion_scales(world), [Config.num("feedback.tiers.medium.explosion_scale")] as Array[float])


func test_real_missile_into_a_real_convoy_ship_fizzles() -> void:
	var convoy: Convoy = CONVOY_SCENE.instantiate() as Convoy
	add_child_autofree(convoy)
	convoy.set_physics_process(false)
	var ship: ConvoyShip = convoy.ships()[Convoy.FLANK_TOP]
	var near: Area2D = _make_target(ship.global_position + Vector2(0, -60), &"enemies")
	var missile: Missile = MISSILE_SCENE.instantiate() as Missile
	missile.setup({"position": ship.global_position + Vector2(0, 120), "velocity": Vector2(0, -900), "damage": 8})
	add_child_autofree(missile)
	await wait_physics_frames(15)
	assert_eq(convoy.hp(), convoy.max_hp(), "convoy HP unchanged")
	assert_eq(_amounts(near), [], "no splash")
	assert_true(not is_instance_valid(missile) or missile.is_queued_for_deletion(), "stopped by the hull")
