extends GutTest
## NeedleBolt (Story 2.6): an EnemyBullet with layers 8/81, an elongated
## magenta streak with a white core, a capsule long enough for 1600 px/s that
## follows velocity, asteroid cover (a Needle firing through a real Spawner at
## a stand-in behind a real medium asteroid) and no tunnelling through physics.

const BOLT_SCENE: PackedScene = preload("res://entities/projectiles/needle_bolt.tscn")
const DamageTarget: GDScript = preload("res://tests/fixtures/damage_target.gd")
const CONVOY_SCENE: PackedScene = preload("res://entities/allies/convoy.tscn")
const ENEMY_COLOR: Color = Color("#FF2BD6")
const DT: float = 1.0 / 60.0

var _world: Node2D = null
var _projectiles: Node2D = null
var _spawner: Spawner = null


func after_each() -> void:
	Feedback.reset()
	_world = null
	_projectiles = null
	_spawner = null


func _make(pos: Vector2, velocity: Vector2 = Vector2(0, 1600)) -> NeedleBolt:
	var bolt: NeedleBolt = BOLT_SCENE.instantiate() as NeedleBolt
	bolt.setup({"position": pos, "velocity": velocity, "damage": 1})
	add_child_autofree(bolt)
	bolt.set_physics_process(false)
	return bolt


func _hitbox(bolt: NeedleBolt) -> CollisionShape2D:
	return bolt.get_node("Hitbox") as CollisionShape2D


func _streak(bolt: NeedleBolt) -> Sprite2D:
	return bolt.get_node_or_null("Streak") as Sprite2D


func _make_world() -> void:
	_world = Node2D.new()
	for container: String in ["Projectiles", "Enemies", "Asteroids"]:
		var node: Node2D = Node2D.new()
		node.name = container
		_world.add_child(node)
	add_child_autofree(_world)
	_projectiles = _world.get_node("Projectiles") as Node2D
	_spawner = Spawner.new()
	_spawner.world = _world
	add_child_autofree(_spawner)


## A player stand-in: a 24 px circle on the player layer, in group `player`
## (so the Needle aims at it), recording apply_damage calls.
func _make_stand_in(pos: Vector2) -> Area2D:
	var target: Area2D = DamageTarget.new() as Area2D
	target.collision_layer = CollisionLayers.PLAYER
	target.collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	target.add_child(shape)
	target.position = pos
	target.add_to_group(&"player")
	add_child_autofree(target)
	return target


## Spawns a Needle at (960, 160) through the Spawner and steps it (physics
## off) until its first bolt is fired; returns that bolt.
func _fire_needle() -> Projectile:
	var needle: Needle = _spawner.spawn_enemy(&"needle", {"position": Vector2(960, 160)}) as Needle
	assert_not_null(needle)
	if needle == null:
		return null
	needle.set_physics_process(false)
	var t: float = 0.0
	while _projectiles.get_child_count() == 0 and t < 3.0:
		needle.step(DT)
		t += DT
	assert_eq(_projectiles.get_child_count(), 1, "the Needle fired one bolt")
	if _projectiles.get_child_count() != 1:
		return null
	return _projectiles.get_child(0) as Projectile


# --- Scene shape --------------------------------------------------------------

func test_is_registered_and_layered() -> void:
	assert_true(EntityRegistry.PROJECTILES.has(&"needle_bolt"))
	var bolt: NeedleBolt = _make(Vector2(960, 540))
	assert_true(bolt is EnemyBullet, "extends EnemyBullet")
	assert_eq(bolt.collision_layer, CollisionLayers.ENEMY_SHOTS, "enemy_shots")
	assert_eq(bolt.collision_mask, CollisionLayers.MASK_ENEMY_SHOTS, "player + asteroids + convoy")
	assert_true(bolt.monitoring)
	assert_false(bolt.monitorable)


func test_capsule_is_long_enough_for_the_bolt_speed() -> void:
	var bolt: NeedleBolt = _make(Vector2(960, 540))
	var capsule: CapsuleShape2D = _hitbox(bolt).shape as CapsuleShape2D
	assert_not_null(capsule, "CapsuleShape2D")
	if capsule == null:
		return
	assert_gte(capsule.radius, 8.0, "radius >= 8")
	var per_tick: float = Config.num("enemies.needle.bolt_speed_px_s") / float(Engine.physics_ticks_per_second)
	assert_gte(capsule.height, per_tick, "height >= bolt_speed_px_s / 60")
	assert_gte(capsule.height, 27.0, "GDD: >= 27 px")


func test_capsule_and_streak_follow_velocity() -> void:
	for velocity: Vector2 in [Vector2(0, 1600), Vector2(1600, 0), Vector2(-900, 900), Vector2(300, -1500)]:
		var bolt: NeedleBolt = _make(Vector2(960, 540), velocity)
		var dir: Vector2 = velocity.normalized()
		var axis: Vector2 = Vector2.DOWN.rotated(_hitbox(bolt).rotation)
		assert_almost_eq(axis.dot(dir), 1.0, 0.0001, "capsule along %s" % velocity)
		var streak: Sprite2D = _streak(bolt)
		assert_not_null(streak, "Streak")
		if streak != null:
			var streak_axis: Vector2 = Vector2.DOWN.rotated(streak.rotation)
			assert_almost_eq(streak_axis.dot(dir), 1.0, 0.0001, "streak along %s" % velocity)


func test_streak_is_an_elongated_magenta_bolt_with_a_white_core() -> void:
	var bolt: NeedleBolt = _make(Vector2(960, 540))
	var streak: Sprite2D = _streak(bolt)
	assert_not_null(streak, "Streak sprite")
	if streak == null:
		return
	var tex: GradientTexture2D = streak.texture as GradientTexture2D
	assert_not_null(tex, "gradient texture")
	if tex == null:
		return
	var width: float = float(tex.width) * streak.scale.x
	var length: float = float(tex.height) * streak.scale.y
	assert_gte(width, 16.0, "streak >= 16 px wide")
	assert_gte(width * 0.85, 16.0, "opaque body >= 16 px wide")
	assert_gt(length, width * 2.0, "elongated")
	var gradient: Gradient = tex.gradient
	assert_eq(gradient.sample(0.0), Color.WHITE, "white core")
	var body: Color = gradient.sample(0.45)
	assert_almost_eq(body.r, ENEMY_COLOR.r, 0.01, "enemy colour r")
	assert_almost_eq(body.g, ENEMY_COLOR.g, 0.01, "enemy colour g")
	assert_almost_eq(body.b, ENEMY_COLOR.b, 0.01, "enemy colour b")
	assert_eq(body.a, 1.0, "opaque body")


# --- Cover and hits (real physics) ----------------------------------------------

func test_asteroid_on_the_locked_line_stops_the_bolt() -> void:
	_make_world()
	var stand_in: Area2D = _make_stand_in(Vector2(960, 900))
	var rock: Asteroid = _spawner.spawn_asteroid({"size": &"medium", "position": Vector2(960, 520)})
	assert_not_null(rock)
	if rock == null:
		return
	rock.set_physics_process(false)
	var hp_before: int = rock.hp
	await wait_physics_frames(2)
	var bolt: Projectile = _fire_needle()
	if bolt == null:
		return
	assert_true(bolt is NeedleBolt)
	assert_almost_eq(bolt.velocity.normalized(), Vector2.DOWN, Vector2(0.0001, 0.0001), "aimed through the asteroid")
	await wait_physics_frames(60)
	assert_eq(rock.hp, hp_before, "asteroid HP unchanged")
	assert_false(rock.is_queued_for_deletion())
	assert_eq((stand_in.get("calls") as Array).size(), 0, "the stand-in behind cover takes no damage")
	assert_eq(_projectiles.get_child_count(), 0, "bolt stopped and freed")


func test_bolt_does_not_tunnel_through_the_player() -> void:
	_make_world()
	var stand_in: Area2D = _make_stand_in(Vector2(960, 700))
	await wait_physics_frames(2)
	var bolt: Projectile = _fire_needle()
	if bolt == null:
		return
	await wait_physics_frames(60)
	var calls: Array = stand_in.get("calls") as Array
	assert_eq(calls.size(), 1, "exactly one apply_damage")
	if calls.size() == 1:
		assert_eq(calls[0].amount, 1)
		assert_true(is_same(calls[0].source, bolt), "the bolt is the source")
	assert_eq(_projectiles.get_child_count(), 0, "bolt freed")


# --- Convoy (Story 6.3) -------------------------------------------------------------

## A Needle bolt is a stray: it never carries targets_convoy, and one that
## reaches a convoy ship stops, frees itself and costs damage.convoy_stray.
func test_needle_bolt_is_a_stray_on_the_convoy() -> void:
	_make_world()
	var convoy: Convoy = CONVOY_SCENE.instantiate() as Convoy
	add_child_autofree(convoy)
	convoy.set_physics_process(false)
	var bolt: Projectile = _fire_needle()
	if bolt == null:
		return
	bolt.set_physics_process(false)
	assert_true(bolt is NeedleBolt)
	assert_false((bolt as EnemyBullet).targets_convoy, "never convoy-aimed")
	bolt._on_area_entered(convoy.ships()[Convoy.FLANK_BOTTOM])
	assert_eq(convoy.hp(), convoy.max_hp() - Config.int_("damage.convoy_stray"), "stray: 2")
	assert_eq(convoy.hp(), 98)
	assert_true(bolt.is_queued_for_deletion(), "the bolt stops and frees")
