extends GutTest
## EnemyBullet (Story 2.5): layers, round magenta visual with a white core,
## travel-aligned anti-tunnelling capsule, damage only on non-asteroid targets
## with apply_damage, asteroids stop it without damage, no impact feedback;
## the targets_convoy flag and the convoy aimed / stray amounts (Story 6.3).

const BULLET_SCENE: PackedScene = preload("res://entities/projectiles/enemy_bullet.tscn")
const DamageTarget: GDScript = preload("res://tests/fixtures/damage_target.gd")
const ENEMY_COLOR: Color = Color("#FF2BD6")

var _world: Node2D = null
var _spawner: Spawner = null


func after_each() -> void:
	Feedback.reset()
	Config.load_data()
	_world = null
	_spawner = null


func _make(pos: Vector2, velocity: Vector2 = Vector2(0, 450), damage: int = 1, manual: bool = true, targets_convoy: bool = false) -> EnemyBullet:
	var bullet: EnemyBullet = BULLET_SCENE.instantiate() as EnemyBullet
	var params: Dictionary = {"position": pos, "velocity": velocity, "damage": damage}
	if targets_convoy:
		params["targets_convoy"] = true
	bullet.setup(params)
	add_child_autofree(bullet)
	if manual:
		bullet.set_physics_process(false)
	return bullet


func _hitbox(bullet: EnemyBullet) -> CollisionShape2D:
	return bullet.get_node("Hitbox") as CollisionShape2D


func _calls(target: Area2D) -> Array:
	return target.get("calls") as Array


func _make_target(layer: int, pos: Vector2 = Vector2(-500, -500), with_damage: bool = true) -> Area2D:
	var target: Area2D = (DamageTarget.new() as Area2D) if with_damage else Area2D.new()
	target.collision_layer = layer
	target.collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	target.add_child(shape)
	target.position = pos
	add_child_autofree(target)
	return target


## A test world with a real Spawner; `effects` adds an Effects container,
## which registers the Spawner with Feedback.
func _make_world(effects: bool = false) -> void:
	_world = Node2D.new()
	var names: Array[String] = ["Projectiles", "Enemies", "Asteroids"]
	if effects:
		names.append("Effects")
	for container: String in names:
		var node: Node2D = Node2D.new()
		node.name = container
		_world.add_child(node)
	add_child_autofree(_world)
	_spawner = Spawner.new()
	_spawner.world = _world
	add_child_autofree(_spawner)


# --- Scene shape --------------------------------------------------------------

func test_is_registered_and_layered() -> void:
	assert_true(EntityRegistry.PROJECTILES.has(&"enemy_bullet"))
	var bullet: EnemyBullet = _make(Vector2(960, 540))
	assert_true(bullet is Projectile)
	assert_eq(bullet.collision_layer, CollisionLayers.ENEMY_SHOTS, "enemy_shots")
	assert_eq(bullet.collision_mask, CollisionLayers.MASK_ENEMY_SHOTS, "player + asteroids + convoy")
	assert_eq(bullet.collision_mask, 81)
	assert_true(bullet.monitoring)
	assert_false(bullet.monitorable)


func test_visual_is_a_round_magenta_orb_with_a_white_core() -> void:
	var bullet: EnemyBullet = _make(Vector2(960, 540))
	var orb: Sprite2D = bullet.get_node_or_null("Orb") as Sprite2D
	assert_not_null(orb, "Orb sprite")
	if orb == null:
		return
	var tex: GradientTexture2D = orb.texture as GradientTexture2D
	assert_not_null(tex, "gradient texture")
	if tex == null:
		return
	var min_d: float = Config.num("weapons.enemy_bullet.min_diameter_px")
	assert_eq(min_d, 16.0)
	assert_gte(float(tex.width) * orb.scale.x, min_d, "diameter >= min_diameter_px")
	assert_eq(tex.width, tex.height, "round")
	assert_eq(tex.fill, GradientTexture2D.FILL_RADIAL, "radial")
	var gradient: Gradient = tex.gradient
	assert_eq(gradient.sample(0.0), Color.WHITE, "white core")
	var body: Color = gradient.sample(0.45)
	assert_almost_eq(body.r, ENEMY_COLOR.r, 0.01, "enemy colour r")
	assert_almost_eq(body.g, ENEMY_COLOR.g, 0.01, "enemy colour g")
	assert_almost_eq(body.b, ENEMY_COLOR.b, 0.01, "enemy colour b")
	assert_eq(body.a, 1.0, "opaque body")
	# The opaque body (up to the 0.85 stop) still spans >= 16 px.
	assert_gte(float(tex.width) * 0.85, min_d, "opaque diameter >= min_diameter_px")


func test_capsule_is_large_enough() -> void:
	var bullet: EnemyBullet = _make(Vector2(960, 540))
	var capsule: CapsuleShape2D = _hitbox(bullet).shape as CapsuleShape2D
	assert_not_null(capsule, "CapsuleShape2D")
	if capsule == null:
		return
	assert_gte(capsule.radius, 8.0, "radius >= 8")
	assert_gte(capsule.height, Config.num("weapons.enemy_bullet.max_speed_px_s") / float(Engine.physics_ticks_per_second),
		"height >= max speed per physics tick")


func test_capsule_axis_follows_velocity() -> void:
	for velocity: Vector2 in [Vector2(0, 450), Vector2(450, 0), Vector2(-300, 300), Vector2(100, -400)]:
		var bullet: EnemyBullet = _make(Vector2(960, 540), velocity)
		var axis: Vector2 = Vector2.DOWN.rotated(_hitbox(bullet).rotation)
		assert_almost_eq(axis.dot(velocity.normalized()), 1.0, 0.0001, "long axis along %s" % velocity)


func test_zero_velocity_keeps_the_capsule_upright() -> void:
	var bullet: EnemyBullet = _make(Vector2(960, 540), Vector2.ZERO)
	assert_eq(_hitbox(bullet).rotation, 0.0)


func test_moves_by_velocity() -> void:
	var bullet: EnemyBullet = _make(Vector2(960, 540), Vector2(0, 450))
	bullet._physics_process(0.1)
	assert_almost_eq(bullet.global_position, Vector2(960, 585), Vector2(0.001, 0.001))


# --- Hits ---------------------------------------------------------------------

func test_hit_on_a_player_stand_in_damages_once_then_frees() -> void:
	var bullet: EnemyBullet = _make(Vector2(960, 540))
	var target: Area2D = _make_target(CollisionLayers.PLAYER)
	var other: Area2D = _make_target(CollisionLayers.PLAYER)
	bullet._on_area_entered(target)
	bullet._on_area_entered(other)
	var calls: Array = _calls(target)
	assert_eq(calls.size(), 1, "apply_damage once")
	if calls.size() == 1:
		assert_eq(calls[0].amount, 1)
		assert_eq(calls[0].source, bullet)
	assert_eq(_calls(other).size(), 0, "one damage instance")
	assert_true(bullet.is_queued_for_deletion(), "freed")


func test_hit_plays_no_impact_feedback() -> void:
	_make_world(true)
	var effects: Node2D = _world.get_node("Effects") as Node2D
	var bullet: Projectile = _spawner.spawn_projectile(&"enemy_bullet",
		{"position": Vector2(960, 540), "velocity": Vector2.ZERO, "damage": 1})
	bullet.set_physics_process(false)
	var target: Area2D = _make_target(CollisionLayers.PLAYER)
	bullet._on_area_entered(target)
	assert_eq(_calls(target).size(), 1)
	assert_eq(effects.get_child_count(), 0, "no explosion (player-hit feedback is Epic 3)")
	assert_false(Feedback.is_hit_stopped(), "no hit-stop")


func test_target_without_apply_damage_only_frees() -> void:
	var bullet: EnemyBullet = _make(Vector2(960, 540))
	var target: Area2D = _make_target(CollisionLayers.PLAYER, Vector2(-500, -500), false)
	bullet._on_area_entered(target)
	assert_true(bullet.is_queued_for_deletion())


func test_can_damage_rejects_asteroid_layer_only() -> void:
	var bullet: EnemyBullet = _make(Vector2(960, 540))
	var asteroid_layer: Area2D = _make_target(CollisionLayers.ASTEROIDS)
	bullet._on_area_entered(asteroid_layer)
	assert_eq(_calls(asteroid_layer).size(), 0, "no damage to an asteroid-layer target")
	assert_true(bullet.is_queued_for_deletion(), "still stopped")
	var convoy_bullet: EnemyBullet = _make(Vector2(960, 540))
	var convoy: Area2D = _make_target(CollisionLayers.CONVOY)
	convoy_bullet._on_area_entered(convoy)
	assert_eq(_calls(convoy).size(), 1, "other layers are damaged")
	var aimed: EnemyBullet = _make(Vector2(960, 540), Vector2(0, 450), 1, true, true)
	var rock: Area2D = _make_target(CollisionLayers.ASTEROIDS)
	aimed._on_area_entered(rock)
	assert_eq(_calls(rock).size(), 0, "a convoy-aimed bullet still never damages an asteroid")
	assert_true(aimed.is_queued_for_deletion())


func test_real_overlap_with_a_player_stand_in_through_physics() -> void:
	var target: Area2D = _make_target(CollisionLayers.PLAYER, Vector2(960, 540))
	var bullet: EnemyBullet = _make(Vector2(960, 540), Vector2.ZERO, 1, false)
	await wait_physics_frames(5)
	var calls: Array = _calls(target)
	assert_eq(calls.size(), 1, "one apply_damage through area_entered")
	if calls.size() == 1:
		assert_eq(calls[0].amount, 1)
	assert_true(not is_instance_valid(bullet) or bullet.is_queued_for_deletion(), "freed")


func test_real_asteroid_stops_the_bullet_without_damage() -> void:
	_make_world()
	var rock: Asteroid = _spawner.spawn_asteroid({"size": &"large", "position": Vector2(960, 500)})
	assert_not_null(rock)
	if rock == null:
		return
	rock.set_physics_process(false)
	var hp_before: int = rock.hp
	var bullet: Projectile = _spawner.spawn_projectile(&"enemy_bullet",
		{"position": Vector2(960, 200), "velocity": Vector2(0, 450), "damage": 1})
	assert_true(bullet is EnemyBullet)
	await wait_physics_frames(60)
	assert_eq(rock.hp, hp_before, "asteroid HP unchanged")
	assert_false(rock.is_queued_for_deletion())
	assert_eq(_world.get_node("Projectiles").get_child_count(), 0, "bullet stopped and freed")


# --- Convoy amounts (Story 6.3) ----------------------------------------------------

func test_targets_convoy_defaults_false_and_reads_the_setup_key() -> void:
	var plain: EnemyBullet = _make(Vector2(960, 540))
	assert_false(plain.targets_convoy, "default false")
	var aimed: EnemyBullet = _make(Vector2(960, 540), Vector2(0, 450), 1, true, true)
	assert_true(aimed.targets_convoy, "setup key")
	assert_eq(aimed.velocity, Vector2(0, 450), "the base keys still apply")
	assert_eq(aimed.damage, 1)
	var kept: EnemyBullet = BULLET_SCENE.instantiate() as EnemyBullet
	kept.targets_convoy = true
	kept.setup({"damage": 2})
	assert_true(kept.targets_convoy, "a missing key keeps the current value")
	autofree(kept)


func test_aimed_bullet_applies_convoy_aimed_to_a_convoy_area_once() -> void:
	var bullet: EnemyBullet = _make(Vector2(960, 540), Vector2(0, 450), 1, true, true)
	var convoy: Area2D = _make_target(CollisionLayers.CONVOY)
	var other: Area2D = _make_target(CollisionLayers.CONVOY)
	bullet._on_area_entered(convoy)
	bullet._on_area_entered(other)
	var calls: Array = _calls(convoy)
	assert_eq(calls.size(), 1, "one damage instance")
	if calls.size() == 1:
		assert_eq(calls[0].amount, Config.int_("damage.convoy_aimed"), "aimed: damage.convoy_aimed")
		assert_eq(Config.int_("damage.convoy_aimed"), 7, "shipped: 7 (operator retune 2026-10-14)")
		assert_eq(calls[0].source, bullet)
	assert_eq(_calls(other).size(), 0)
	assert_true(bullet.is_queued_for_deletion(), "freed")


func test_stray_bullet_applies_convoy_stray_to_a_convoy_area() -> void:
	var bullet: EnemyBullet = _make(Vector2(960, 540), Vector2(0, 450), 3)
	var convoy: Area2D = _make_target(CollisionLayers.CONVOY)
	bullet._on_area_entered(convoy)
	var calls: Array = _calls(convoy)
	assert_eq(calls.size(), 1)
	if calls.size() == 1:
		assert_eq(calls[0].amount, Config.int_("damage.convoy_stray"), "stray: 2, not its own damage")
		assert_eq(calls[0].amount, 2)
	assert_true(bullet.is_queued_for_deletion(), "freed")


func test_aimed_bullet_still_costs_the_player_its_own_damage() -> void:
	var bullet: EnemyBullet = _make(Vector2(960, 540), Vector2(0, 450), 1, true, true)
	var player: Area2D = _make_target(CollisionLayers.PLAYER)
	bullet._on_area_entered(player)
	var calls: Array = _calls(player)
	assert_eq(calls.size(), 1)
	if calls.size() == 1:
		assert_eq(calls[0].amount, 1, "damage (bullet hearts), not the convoy amount")
	var heavy: EnemyBullet = _make(Vector2(960, 540), Vector2(0, 450), 2)
	var player2: Area2D = _make_target(CollisionLayers.PLAYER)
	heavy._on_area_entered(player2)
	assert_eq((_calls(player2)[0] as Dictionary).amount, 2, "a stray's own damage on the player")


func test_convoy_amounts_come_from_tuning() -> void:
	var damage_tuning: Dictionary = Config.tuning["damage"] as Dictionary
	damage_tuning["convoy_aimed"] = 7
	damage_tuning["convoy_stray"] = 3
	var aimed: EnemyBullet = _make(Vector2(960, 540), Vector2(0, 450), 1, true, true)
	var stray: EnemyBullet = _make(Vector2(960, 540))
	assert_eq(aimed._damage_for(_make_target(CollisionLayers.CONVOY)), 7)
	assert_eq(stray._damage_for(_make_target(CollisionLayers.CONVOY)), 3)
	assert_eq(aimed._damage_for(_make_target(CollisionLayers.PLAYER)), 1)


func test_spawned_bullet_carries_targets_convoy() -> void:
	_make_world()
	var bullet: Projectile = _spawner.spawn_projectile(&"enemy_bullet",
		{"position": Vector2(960, 540), "velocity": Vector2(0, 450), "damage": 1, "targets_convoy": true})
	assert_true(bullet is EnemyBullet)
	if bullet is EnemyBullet:
		bullet.set_physics_process(false)
		assert_true((bullet as EnemyBullet).targets_convoy)
