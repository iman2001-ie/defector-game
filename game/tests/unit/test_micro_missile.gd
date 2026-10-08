extends GutTest
## MicroMissile (Story 3.5): scene shape, registry entry, nearest-enemy pick once
## at launch, re-pick only on target loss, steering, base-projectile hits
## (asteroids block it) and the lifetime free with no impact.

const MICRO_SCENE: PackedScene = preload("res://entities/projectiles/micro_missile.tscn")
const WASP_SCENE: PackedScene = preload("res://entities/enemies/wasp/wasp.tscn")
const ASTEROID_SCENE: PackedScene = preload("res://entities/asteroids/asteroid.tscn")
const DamageTarget: GDScript = preload("res://tests/fixtures/damage_target.gd")
const DT: float = 1.0 / 60.0
const LAUNCH: Vector2 = Vector2(960, 900)


func after_each() -> void:
	Feedback.reset()


func _speed() -> float:
	return Config.num("abilities.barrage.speed_px_s")


func _make(pos: Vector2 = LAUNCH, velocity: Vector2 = Vector2.ZERO) -> MicroMissile:
	if velocity == Vector2.ZERO:
		velocity = Vector2.UP * _speed()
	var micro: MicroMissile = MICRO_SCENE.instantiate() as MicroMissile
	micro.setup({"position": pos, "velocity": velocity, "damage": Config.int_("abilities.barrage.damage")})
	add_child_autofree(micro)
	micro.set_physics_process(false)
	return micro


func _wasp(pos: Vector2) -> Wasp:
	var wasp: Wasp = WASP_SCENE.instantiate() as Wasp
	wasp.setup({"position": pos})
	add_child_autofree(wasp)
	wasp.set_physics_process(false)
	return wasp


# --- Scene shape --------------------------------------------------------------

func test_registered_and_layered() -> void:
	assert_true(EntityRegistry.PROJECTILES.has(&"micro_missile"), "registered")
	var micro: MicroMissile = _make()
	assert_true(micro is Projectile)
	assert_eq(micro.collision_layer, CollisionLayers.PLAYER_SHOTS, "player_shots")
	assert_eq(micro.collision_mask, CollisionLayers.MASK_PLAYER_SHOTS, "enemies + asteroids + convoy")
	assert_false(micro.monitorable)
	assert_true(micro.monitoring)
	assert_eq(micro.impact_tier, ImpactTier.SMALL)
	assert_eq(micro.damage, 6)


func test_capsule_prevents_tunnelling() -> void:
	var micro: MicroMissile = _make()
	var shapes: Array[CollisionShape2D] = []
	for child: Node in micro.get_children():
		if child is CollisionShape2D:
			shapes.append(child as CollisionShape2D)
	assert_eq(shapes.size(), 1, "one collision shape")
	if shapes.is_empty():
		return
	var capsule: CapsuleShape2D = shapes[0].shape as CapsuleShape2D
	assert_not_null(capsule, "CapsuleShape2D")
	if capsule != null:
		assert_gte(capsule.height, _speed() / float(Engine.physics_ticks_per_second), "height >= distance per physics tick")
	assert_eq(shapes[0].rotation, 0.0, "capsule along local Y")


func test_additive_coalition_body() -> void:
	var micro: MicroMissile = _make()
	var body: Polygon2D = micro.get_node_or_null(^"Body") as Polygon2D
	assert_not_null(body, "Body is a Polygon2D")
	if body == null:
		return
	assert_eq(body.color.to_html(false), "22e6ff", "coalition cyan")
	var mat: CanvasItemMaterial = body.material as CanvasItemMaterial
	assert_not_null(mat)
	if mat != null:
		assert_eq(mat.blend_mode, CanvasItemMaterial.BLEND_MODE_ADD, "additive")


func test_reads_tuning_and_points_along_travel() -> void:
	var micro: MicroMissile = _make()
	assert_eq(micro.turn_rate_deg_s, 540.0)
	assert_eq(micro.lifetime_s, 3.0)
	assert_almost_eq(micro.rotation, 0.0, 0.0001, "nose up")


# --- nearest_enemy ------------------------------------------------------------

func test_nearest_enemy_picks_the_closest() -> void:
	var far: Node2D = autofree(Node2D.new()) as Node2D
	far.position = Vector2(0, 300)
	var near: Node2D = autofree(Node2D.new()) as Node2D
	near.position = Vector2(0, 100)
	var nodes: Array[Node] = [far, near]
	assert_eq(MicroMissile.nearest_enemy(Vector2.ZERO, nodes), near)


func test_nearest_enemy_tie_first_wins_and_empty_is_null() -> void:
	var a: Node2D = autofree(Node2D.new()) as Node2D
	a.position = Vector2(100, 0)
	var b: Node2D = autofree(Node2D.new()) as Node2D
	b.position = Vector2(-100, 0)
	var nodes: Array[Node] = [a, b]
	assert_eq(MicroMissile.nearest_enemy(Vector2.ZERO, nodes), a, "first wins a tie")
	assert_null(MicroMissile.nearest_enemy(Vector2.ZERO, [] as Array[Node]))


func test_nearest_enemy_skips_non_node2d_queued_and_dead() -> void:
	var plain: Node = autofree(Node.new()) as Node
	var dead: Wasp = _wasp(LAUNCH + Vector2(0, -50))
	dead._dead = true
	var queued: Wasp = _wasp(LAUNCH + Vector2(0, -60))
	queued.queue_free()
	var alive: Wasp = _wasp(LAUNCH + Vector2(0, -400))
	var nodes: Array[Node] = [plain, dead, queued, alive]
	assert_eq(MicroMissile.nearest_enemy(LAUNCH, nodes), alive)
	var none: Array[Node] = [plain, dead, queued]
	assert_null(MicroMissile.nearest_enemy(LAUNCH, none))


# --- Targeting ----------------------------------------------------------------

func test_targets_nearest_enemy_at_launch() -> void:
	_wasp(LAUNCH + Vector2(0, -300))
	var near: Wasp = _wasp(LAUNCH + Vector2(100, 0))
	var micro: MicroMissile = _make()
	assert_eq(micro.target(), near, "100 px one")


func test_no_rescan_when_a_nearer_enemy_arrives() -> void:
	var first: Wasp = _wasp(LAUNCH + Vector2(0, -300))
	var micro: MicroMissile = _make()
	assert_eq(micro.target(), first)
	_wasp(LAUNCH + Vector2(0, -20))
	micro._physics_process(DT)
	assert_eq(micro.target(), first, "target unchanged")


func test_repicks_when_target_freed() -> void:
	var first: Wasp = _wasp(LAUNCH + Vector2(0, -100))
	var second: Wasp = _wasp(LAUNCH + Vector2(0, -400))
	var micro: MicroMissile = _make()
	assert_eq(micro.target(), first)
	first.free()
	assert_null(micro.target(), "freed target reads as null")
	micro._physics_process(DT)
	assert_eq(micro.target(), second, "remaining enemy")


func test_repick_skips_queued_target() -> void:
	var first: Wasp = _wasp(LAUNCH + Vector2(0, -100))
	var second: Wasp = _wasp(LAUNCH + Vector2(0, -400))
	var micro: MicroMissile = _make()
	first.queue_free()
	micro._physics_process(DT)
	assert_eq(micro.target(), second)


func test_no_enemies_flies_straight_up() -> void:
	var micro: MicroMissile = _make()
	assert_null(micro.target())
	for i: int in 10:
		micro._physics_process(DT)
	assert_eq(micro.velocity, Vector2.UP * _speed(), "velocity unchanged")
	assert_almost_eq(micro.global_position.y, LAUNCH.y - _speed() * DT * 10.0, 0.01, "moved straight up")


func test_steers_toward_target_at_turn_rate() -> void:
	_wasp(LAUNCH + Vector2(400, 0))
	var micro: MicroMissile = _make()
	micro._physics_process(DT)
	var turned: float = Vector2.UP.angle_to(micro.velocity)
	assert_almost_eq(turned, deg_to_rad(540.0) * DT, 0.0001, "turned by the max rate toward +x")
	assert_almost_eq(micro.velocity.length(), _speed(), 0.001, "speed kept")
	assert_almost_eq(micro.rotation, micro.velocity.angle() + PI / 2.0, 0.0001, "nose along travel")


func test_target_lost_with_none_left_never_scans_again() -> void:
	var only: Wasp = _wasp(LAUNCH + Vector2(0, -300))
	var micro: MicroMissile = _make()
	only.free()
	micro._physics_process(DT)
	assert_null(micro.target())
	_wasp(LAUNCH + Vector2(0, -50))
	micro._physics_process(DT)
	assert_null(micro.target(), "no further scan")


# --- steer --------------------------------------------------------------------

func test_steer_caps_the_turn_and_keeps_length() -> void:
	var v: Vector2 = Vector2.UP * 800.0
	var out: Vector2 = MicroMissile.steer(v, Vector2.RIGHT, 0.1)
	assert_almost_eq(v.angle_to(out), 0.1, 0.00001, "turns 0.1 rad")
	assert_almost_eq(out.length(), 800.0, 0.001, "same length")
	var left: Vector2 = MicroMissile.steer(v, Vector2.LEFT, 0.1)
	assert_almost_eq(v.angle_to(left), -0.1, 0.00001, "turns the short way")


func test_steer_snaps_when_within_the_cap() -> void:
	var v: Vector2 = Vector2.UP * 800.0
	var desired: Vector2 = Vector2.UP.rotated(0.05)
	var out: Vector2 = MicroMissile.steer(v, desired, 0.1)
	assert_almost_eq(out.angle(), desired.angle(), 0.00001)
	assert_almost_eq(out.length(), 800.0, 0.001)


# --- Hits and lifetime --------------------------------------------------------

func test_hit_deals_damage_and_frees() -> void:
	var target: Area2D = DamageTarget.new() as Area2D
	target.position = Vector2(-500, -500)
	add_child_autofree(target)
	var micro: MicroMissile = _make()
	micro._on_area_entered(target)
	var calls: Array = target.get("calls") as Array
	assert_eq(calls.size(), 1)
	if calls.size() == 1:
		assert_eq(calls[0].amount, 6)
	assert_true(micro.is_queued_for_deletion(), "freed")


func test_asteroid_blocks_and_takes_damage() -> void:
	var rock: Asteroid = ASTEROID_SCENE.instantiate() as Asteroid
	rock.setup({"size": &"large", "position": Vector2(1500, 150)})
	add_child_autofree(rock)
	rock.set_physics_process(false)
	var hp: int = rock.hp
	var micro: MicroMissile = _make()
	micro._on_area_entered(rock)
	assert_eq(rock.hp, hp - 6, "asteroid takes 6")
	assert_true(micro.is_queued_for_deletion(), "missile freed")


func test_lifetime_frees_without_impact() -> void:
	var world: Node2D = Node2D.new()
	for container: String in ["Projectiles", "Enemies", "Asteroids", "Effects"]:
		var node: Node2D = Node2D.new()
		node.name = container
		world.add_child(node)
	add_child_autofree(world)
	var spawner: Spawner = Spawner.new()
	spawner.world = world
	add_child_autofree(spawner)
	var micro: MicroMissile = spawner.spawn_projectile(&"micro_missile",
		{"position": Vector2(960, 540), "velocity": Vector2.UP * 1.0, "damage": 6}) as MicroMissile
	micro.set_physics_process(false)
	micro._physics_process(micro.lifetime_s - 0.1)
	assert_false(micro.is_queued_for_deletion(), "alive before lifetime_s")
	micro._physics_process(0.1)
	assert_true(micro.is_queued_for_deletion(), "freed at lifetime_s")
	assert_eq((world.get_node("Effects") as Node2D).get_child_count(), 0, "no impact feedback")
