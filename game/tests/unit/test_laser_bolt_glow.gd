extends GutTest
## Laser bolt glow (Story 1.9, decision #30): each twin is an HDR core
## (self_modulate = weapons.laser.glow_energy > 1) with a wider additive Halo
## behind it (self_modulate = weapons.laser.halo_energy).

const TWINS: Array[String] = ["BoltLeft", "BoltRight"]

var _spawner: Spawner
var _projectiles: Node2D


func before_each() -> void:
	var world: Node2D = Node2D.new()
	_projectiles = Node2D.new()
	_projectiles.name = "Projectiles"
	world.add_child(_projectiles)
	add_child_autofree(world)
	_spawner = Spawner.new()
	_spawner.world = world
	add_child_autofree(_spawner)


func after_each() -> void:
	Config.load_data()
	Feedback.reset()
	_spawner = null
	_projectiles = null


func _spawn_bolt() -> Projectile:
	var bolt: Projectile = _spawner.spawn_projectile(&"laser_bolt",
			{"position": Vector2(960, 500), "velocity": Vector2.ZERO, "damage": 1})
	if bolt != null:
		bolt.set_physics_process(false)
	return bolt


func _drawn_size(sprite: Sprite2D) -> Vector2:
	return sprite.texture.get_size() * sprite.scale.abs()


func test_glow_energy_is_hdr() -> void:
	assert_gt(Config.num("weapons.laser.glow_energy"), 1.0, "core above the 1.0 HDR line")
	assert_gt(Config.num("weapons.laser.halo_energy"), 0.0, "halo visible")


func test_twin_cores_use_glow_energy() -> void:
	var bolt: Projectile = _spawn_bolt()
	assert_not_null(bolt, "bolt spawned")
	if bolt == null:
		return
	var e: float = Config.num("weapons.laser.glow_energy")
	for twin_name: String in TWINS:
		var twin: Sprite2D = bolt.get_node_or_null(twin_name) as Sprite2D
		assert_not_null(twin, twin_name)
		if twin == null:
			continue
		assert_eq(twin.self_modulate, Color(e, e, e, 1.0), "%s core self_modulate" % twin_name)
		assert_eq(twin.modulate, Color.WHITE, "%s modulate untouched (halo independent)" % twin_name)


func test_each_twin_has_a_wider_additive_halo_behind_it() -> void:
	var bolt: Projectile = _spawn_bolt()
	if bolt == null:
		fail_test("bolt spawned")
		return
	var h: float = Config.num("weapons.laser.halo_energy")
	for twin_name: String in TWINS:
		var twin: Sprite2D = bolt.get_node(twin_name) as Sprite2D
		var halo: Sprite2D = twin.get_node_or_null("Halo") as Sprite2D
		assert_not_null(halo, "%s/Halo is a Sprite2D" % twin_name)
		if halo == null:
			continue
		var mat: CanvasItemMaterial = halo.material as CanvasItemMaterial
		assert_not_null(mat, "%s/Halo has a CanvasItemMaterial" % twin_name)
		if mat != null:
			assert_eq(mat.blend_mode, CanvasItemMaterial.BLEND_MODE_ADD, "%s/Halo additive" % twin_name)
		assert_true(halo.show_behind_parent, "%s/Halo draws behind the core" % twin_name)
		assert_eq(halo.self_modulate, Color(h, h, h, 1.0), "%s/Halo self_modulate" % twin_name)
		assert_eq(halo.position, Vector2.ZERO, "%s/Halo centred on the core" % twin_name)
		var core_size: Vector2 = _drawn_size(twin)
		var halo_size: Vector2 = _drawn_size(halo)
		assert_gt(halo_size.x, core_size.x, "%s/Halo wider than the core" % twin_name)
		assert_gt(halo_size.y, core_size.y, "%s/Halo longer than the core" % twin_name)


func test_changed_glow_energy_applies_to_new_bolts() -> void:
	Config.tuning["weapons"]["laser"]["glow_energy"] = 3.0
	Config.tuning["weapons"]["laser"]["halo_energy"] = 0.5
	var bolt: Projectile = _spawn_bolt()
	if bolt == null:
		fail_test("bolt spawned")
		return
	for twin_name: String in TWINS:
		var twin: Sprite2D = bolt.get_node(twin_name) as Sprite2D
		assert_eq(twin.self_modulate, Color(3.0, 3.0, 3.0, 1.0), "%s core at 3.0" % twin_name)
		var halo: Sprite2D = twin.get_node_or_null("Halo") as Sprite2D
		assert_not_null(halo, "%s/Halo is a Sprite2D" % twin_name)
		if halo == null:
			continue
		assert_eq(halo.self_modulate, Color(0.5, 0.5, 0.5, 1.0), "%s halo at 0.5" % twin_name)


func test_hitbox_and_layout_unchanged() -> void:
	var bolt: Projectile = _spawn_bolt()
	if bolt == null:
		fail_test("bolt spawned")
		return
	var hitbox: CollisionShape2D = bolt.get_node_or_null("Hitbox") as CollisionShape2D
	assert_not_null(hitbox, "Hitbox")
	if hitbox != null:
		var capsule: CapsuleShape2D = hitbox.shape as CapsuleShape2D
		assert_not_null(capsule, "capsule")
		if capsule != null:
			assert_eq(capsule.radius, 10.0, "radius")
			assert_eq(capsule.height, 40.0, "height")
		assert_eq(hitbox.position, Vector2.ZERO, "centred")
	assert_eq((bolt.get_node("BoltLeft") as Node2D).position, Vector2(-8, 0), "left twin")
	assert_eq((bolt.get_node("BoltRight") as Node2D).position, Vector2(8, 0), "right twin")
	assert_eq(bolt.collision_layer, 1 << 1, "player_shots")
	assert_eq(bolt.collision_mask, (1 << 2) | (1 << 4), "enemies + asteroids")
	assert_eq(bolt.damage, 1, "damage")
