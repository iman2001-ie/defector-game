extends GutTest
## Player: cursor-chase model (pure helpers + instanced scene) and the hurtbox scene shape.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")
const DT: float = 1.0 / 60.0
const LAYER_PLAYER: int = 1
const MASK_ENEMIES_ASTEROIDS_PICKUPS: int = (1 << 2) | (1 << 4) | (1 << 5)

var _max_speed: float
var _gain: float
var _player: Player


func before_each() -> void:
	_max_speed = Config.num("player.max_speed")
	_gain = Player.solve_chase_gain(
		_max_speed, Config.num("player.chase_ref_distance_px"), Config.num("player.chase_ref_time_s"))
	_player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(_player)
	# Tests drive the ship explicitly; the real mouse must not move it.
	_player.set_physics_process(false)


func _settle(target: Vector2, steps: int = 240) -> void:
	for i: int in steps:
		_player.step_toward(target, DT)


# --- Pure helpers -----------------------------------------------------------

func test_solved_gain_matches_reference() -> void:
	assert_almost_eq(_gain, 116.0, 1.0, "1400 / 150 / 0.12 -> ~116 /s")


func test_reference_move_arrives_in_time_without_overshoot() -> void:
	var target: Vector2 = Vector2(1110, 800)
	var pos: Vector2 = Vector2(960, 800)
	var arrived_at: float = -1.0
	for i: int in 30:
		pos = Player.chase_step(pos, target, DT, _max_speed, _gain)
		assert_true(pos.x <= target.x, "never overshoots (step %d)" % i)
		if arrived_at < 0.0 and pos.distance_to(target) <= 1.0:
			arrived_at = (i + 1) * DT
	assert_between(arrived_at, 0.10, 0.14, "within 1 px after 0.10-0.14 s")


func test_speed_cap_on_far_target() -> void:
	var from: Vector2 = Vector2(960, 800)
	var to: Vector2 = Player.chase_step(from, from + Vector2(1000, 0), DT, _max_speed, _gain)
	assert_almost_eq(from.distance_to(to), _max_speed * DT, 0.001, "moves exactly max_speed/60")


func test_no_snap_on_first_step() -> void:
	for offset: Vector2 in [Vector2(2, 0), Vector2(0, -5), Vector2(150, 0), Vector2(-400, 300)]:
		var from: Vector2 = Vector2(960, 800)
		var target: Vector2 = from + offset
		var to: Vector2 = Player.chase_step(from, target, DT, _max_speed, _gain)
		var remaining: float = to.distance_to(target)
		assert_lt(remaining, offset.length(), "distance shrinks for %s" % offset)
		assert_gt(remaining, 0.0, "does not snap for %s" % offset)


func test_small_offset_is_smoothed() -> void:
	var from: Vector2 = Vector2(960, 800)
	var to: Vector2 = Player.chase_step(from, from + Vector2(5, 0), DT, _max_speed, _gain)
	assert_gt(from.distance_to(to), 0.0)
	assert_lt(from.distance_to(to), _max_speed * DT, "moves less than the cap")


func test_infeasible_ref_time_falls_back_to_upper_bound() -> void:
	# 150 px at 1400 px/s needs at least ~0.107 s; 0.05 s cannot be met.
	assert_eq(Player.solve_chase_gain(1400.0, 150.0, 0.05), Player.GAIN_MAX)
	assert_eq(Player.solve_chase_gain(1400.0, 150.0, 150.0 / 1400.0), Player.GAIN_MAX)
	assert_false(Player.is_ref_time_feasible(1400.0, 150.0, 0.05))
	assert_true(Player.is_ref_time_feasible(1400.0, 150.0, 0.12))


# --- Instanced scene driven by step_toward ----------------------------------

func test_scene_reference_move() -> void:
	_player.global_position = Vector2(960, 800)
	var target: Vector2 = Vector2(1110, 800)
	for i: int in 7:
		_player.step_toward(target, DT)
		assert_gt(_player.global_position.distance_to(target), 1.0, "not yet arrived at step %d" % i)
	_player.step_toward(target, DT)
	assert_lt(_player.global_position.distance_to(target), 1.0, "arrived by 8 steps (0.133 s)")
	assert_true(_player.global_position.x <= target.x, "no overshoot")


func test_scene_speed_cap() -> void:
	_player.global_position = Vector2(960, 800)
	_player.step_toward(Vector2(960, 800) + Vector2(-1000, 0), DT)
	assert_almost_eq(_player.global_position.x, 960.0 - _max_speed * DT, 0.001)


func test_clamp_low() -> void:
	_player.global_position = Vector2(960, 800)
	_settle(Vector2(960, 100))
	assert_almost_eq(_player.global_position, Vector2(960, 432), Vector2(0.01, 0.01))


func test_clamp_bottom_left() -> void:
	_player.global_position = Vector2(960, 800)
	_settle(Vector2(-50, 1200))
	assert_almost_eq(_player.global_position, Vector2(0, 1080), Vector2(0.01, 0.01))


func test_clamp_bottom_right() -> void:
	_player.global_position = Vector2(960, 800)
	_settle(Vector2(2000, 1200))
	assert_almost_eq(_player.global_position, Vector2(1920, 1080), Vector2(0.01, 0.01))


func test_position_clamped_even_when_starting_outside() -> void:
	_player.global_position = Vector2(-300, 100)
	_player.step_toward(Vector2(-300, 100), DT)
	assert_eq(_player.global_position, Vector2(0, 432))


func test_clamp_to_bounds() -> void:
	assert_eq(_player.clamp_to_bounds(Vector2(-1, 0)), Vector2(0, 432))
	assert_eq(_player.clamp_to_bounds(Vector2(5000, 5000)), Vector2(1920, 1080))
	assert_eq(_player.clamp_to_bounds(Vector2(700, 600)), Vector2(700, 600))


func test_never_rotates() -> void:
	_player.global_position = Vector2(960, 800)
	for target: Vector2 in [Vector2(0, 432), Vector2(1920, 1080), Vector2(100, 900), Vector2(1500, 500)]:
		_settle(target, 20)
		assert_eq(_player.rotation, 0.0)


func test_physics_process_chases_global_mouse() -> void:
	_player.global_position = Vector2(960, 800)
	var expected: Vector2 = _player.clamp_to_bounds(Player.chase_step(
		Vector2(960, 800), _player.clamp_to_bounds(_player.get_global_mouse_position()), DT, _max_speed, _gain))
	_player._physics_process(DT)
	assert_eq(_player.global_position, expected)


func test_infeasible_ref_time_warns_and_uses_capped_chase() -> void:
	var player_tuning: Dictionary = Config.tuning["player"]
	var original: Variant = player_tuning["chase_ref_time_s"]
	player_tuning["chase_ref_time_s"] = 0.05
	var fresh: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(fresh)
	player_tuning["chase_ref_time_s"] = original
	fresh.set_physics_process(false)
	assert_push_warning("chase_ref_time_s")
	fresh.global_position = Vector2(960, 800)
	fresh.step_toward(Vector2(1960, 800), DT)
	assert_almost_eq(fresh.global_position.distance_to(Vector2(960, 800)), _max_speed * DT, 0.001)


# --- Scene shape --------------------------------------------------------------

func test_root_is_area2d_on_player_layer() -> void:
	assert_true(_player is Area2D)
	assert_eq(_player.collision_layer, LAYER_PLAYER, "layer player only")
	assert_eq(_player.collision_mask, MASK_ENEMIES_ASTEROIDS_PICKUPS, "masks enemies, asteroids, pickups")
	assert_true(_player.monitorable)


func test_hurtbox_is_centred_circle() -> void:
	var shapes: Array[CollisionShape2D] = []
	for child: Node in _player.get_children():
		if child is CollisionShape2D:
			shapes.append(child as CollisionShape2D)
	assert_eq(shapes.size(), 1, "one collision shape")
	if shapes.is_empty():
		return
	var circle: CircleShape2D = shapes[0].shape as CircleShape2D
	assert_not_null(circle, "shape is a CircleShape2D")
	if circle != null:
		assert_eq(circle.radius, Config.num("player.hurtbox_diameter_px") / 2.0)
	assert_eq(shapes[0].position, Vector2.ZERO)


func test_sprite_matches_sprite_px() -> void:
	var sprite: Sprite2D = null
	for child: Node in _player.get_children():
		if child is Sprite2D:
			sprite = child as Sprite2D
	assert_not_null(sprite, "has a Sprite2D")
	if sprite == null:
		return
	assert_not_null(sprite.texture)
	var px: float = Config.num("player.sprite_px")
	assert_eq(sprite.texture.get_size(), Vector2(px, px))


func test_hurtbox_and_sprite_sizes_follow_config() -> void:
	# Values differ from the literals baked into player.tscn, so only _ready() can set them.
	var player_tuning: Dictionary = Config.tuning["player"]
	var original_diameter: Variant = player_tuning["hurtbox_diameter_px"]
	var original_sprite_px: Variant = player_tuning["sprite_px"]
	player_tuning["hurtbox_diameter_px"] = 40
	player_tuning["sprite_px"] = 64
	var fresh: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(fresh)
	player_tuning["hurtbox_diameter_px"] = original_diameter
	player_tuning["sprite_px"] = original_sprite_px
	fresh.set_physics_process(false)
	var circle: CircleShape2D = (fresh.get_node("Hurtbox") as CollisionShape2D).shape as CircleShape2D
	assert_eq(circle.radius, 20.0)
	assert_eq((fresh.get_node("Sprite") as Sprite2D).texture.get_size(), Vector2(64, 64))
