extends GutTest
## AllyBolt (Story 6.4): an ally's shot on `player_shots` with from_ally true,
## registered as &"ally_bolt", rotated to its velocity with a capsule long
## enough for its speed, coalition-coloured like the laser, and blocked by a
## real convoy ship with no damage.

const BOLT_SCENE: PackedScene = preload("res://entities/projectiles/ally_bolt.tscn")
const CONVOY_SCENE: PackedScene = preload("res://entities/allies/convoy.tscn")


func after_each() -> void:
	Feedback.reset()


func _make(params: Dictionary) -> AllyBolt:
	var bolt: AllyBolt = BOLT_SCENE.instantiate() as AllyBolt
	bolt.setup(params)
	add_child_autofree(bolt)
	bolt.set_physics_process(false)
	return bolt


func test_registered_as_ally_bolt() -> void:
	assert_true(EntityRegistry.PROJECTILES.has(&"ally_bolt"))
	var node: Node = (EntityRegistry.PROJECTILES[&"ally_bolt"] as PackedScene).instantiate()
	assert_true(node is AllyBolt)
	assert_true(node is Projectile)
	node.free()


func test_layers() -> void:
	var bolt: AllyBolt = _make({"position": Vector2(500, 500), "velocity": Vector2(0, -1200)})
	assert_eq(bolt.collision_layer, CollisionLayers.PLAYER_SHOTS)
	assert_eq(bolt.collision_mask, CollisionLayers.MASK_PLAYER_SHOTS)
	assert_false(bolt.monitorable)
	assert_true(bolt.monitoring)


func test_setup_from_ally_key() -> void:
	var bolt: AllyBolt = _make({"position": Vector2(500, 500), "velocity": Vector2(0, -1200), "damage": 1, "from_ally": true})
	assert_true(bolt.from_ally)
	assert_eq(bolt.damage, 1)
	var plain: AllyBolt = _make({"position": Vector2(500, 500)})
	assert_false(plain.from_ally, "missing key keeps the default")


func test_rotated_to_its_velocity() -> void:
	var up: AllyBolt = _make({"position": Vector2(500, 500), "velocity": Vector2(0, -1200)})
	assert_almost_eq(up.rotation, 0.0, 0.0001, "up: no rotation")
	var right: AllyBolt = _make({"position": Vector2(500, 500), "velocity": Vector2(1200, 0)})
	assert_almost_eq(Vector2.UP.rotated(right.rotation), Vector2.RIGHT, Vector2(0.0001, 0.0001), "the nose follows the velocity")
	var diag: Vector2 = Vector2(-1, -1).normalized()
	var d: AllyBolt = _make({"position": Vector2(500, 500), "velocity": diag * 1200.0})
	assert_almost_eq(Vector2.UP.rotated(d.rotation), diag, Vector2(0.0001, 0.0001))
	var still: AllyBolt = _make({"position": Vector2(500, 500), "velocity": Vector2.ZERO})
	assert_eq(still.rotation, 0.0, "no velocity: no rotation")


func test_capsule_prevents_tunnelling() -> void:
	var bolt: AllyBolt = _make({"position": Vector2(500, 500), "velocity": Vector2(0, -1200)})
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
		assert_gte(capsule.height, Config.num("allies.shot_speed_px_s") / float(Engine.physics_ticks_per_second), "height >= distance per physics tick")
	assert_eq(shapes[0].rotation, 0.0, "aligned with the bolt (which is rotated to travel)")


func test_single_coalition_bolt_with_glow() -> void:
	var bolt: AllyBolt = _make({"position": Vector2(500, 500), "velocity": Vector2(0, -1200)})
	var sprites: Array[Sprite2D] = []
	for child: Node in bolt.get_children():
		if child is Sprite2D:
			sprites.append(child as Sprite2D)
	assert_eq(sprites.size(), 1, "one bolt, not twins")
	if sprites.is_empty():
		return
	var e: float = Config.num("weapons.laser.glow_energy")
	assert_eq(sprites[0].self_modulate, Color(e, e, e, 1.0), "HDR core like the laser")
	var halo: Sprite2D = sprites[0].get_node_or_null("Halo") as Sprite2D
	assert_not_null(halo)
	var tex: GradientTexture2D = sprites[0].texture as GradientTexture2D
	assert_not_null(tex)
	if tex != null:
		assert_eq(tex.gradient.get_color(1), Color(0.133333, 0.901961, 1, 1), "coalition")


func test_real_bolt_into_a_real_convoy_ship_leaves_hp_unchanged() -> void:
	var convoy: Convoy = CONVOY_SCENE.instantiate() as Convoy
	add_child_autofree(convoy)
	convoy.set_physics_process(false)
	var ship: ConvoyShip = convoy.ships()[Convoy.FLANK_LEFT]
	var bolt: AllyBolt = BOLT_SCENE.instantiate() as AllyBolt
	bolt.setup({"position": ship.global_position + Vector2(0, -120), "velocity": Vector2(0, 1200), "damage": 1, "from_ally": true})
	add_child_autofree(bolt)
	await wait_physics_frames(10)
	assert_eq(convoy.hp(), convoy.max_hp(), "convoy HP unchanged")
	assert_true(not is_instance_valid(bolt) or bolt.is_queued_for_deletion(), "bolt stopped by the hull")
