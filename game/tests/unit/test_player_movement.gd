extends GutTest
## Player: zero-delay cursor lock, zone confinement, cursor warps (zone edge and
## resume), and the hurtbox scene shape.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")
const DT: float = 1.0 / 60.0
const LAYER_PLAYER: int = 1
const MASK_ENEMIES_ASTEROIDS_PICKUPS: int = (1 << 2) | (1 << 4) | (1 << 5)
const HIDDEN: Input.MouseMode = Input.MOUSE_MODE_CONFINED_HIDDEN
const VISIBLE: Input.MouseMode = Input.MOUSE_MODE_VISIBLE

var _player: Player
## Every warp_mouse call the Player made (recorder injected in before_each).
var _warps: Array[Vector2] = []


func before_each() -> void:
	_warps.clear()
	_player = PLAYER_SCENE.instantiate() as Player
	_player.warp_mouse = _record_warp
	add_child_autofree(_player)
	# Tests drive the ship explicitly; the real mouse must not move it.
	_player.set_physics_process(false)


func after_each() -> void:
	PauseArbiter.set_gameplay_mouse_mode(VISIBLE)
	PauseArbiter.clear()
	_player = null


func _record_warp(p: Vector2) -> void:
	_warps.append(p)


# --- Pure confine -------------------------------------------------------------

func test_confine_pure_cases() -> void:
	var lo: Vector2 = Vector2(0, 432)
	var hi: Vector2 = Vector2(1920, 1080)
	assert_eq(Player.confine(Vector2(700, 600), lo, hi), Vector2(700, 600), "inside")
	assert_eq(Player.confine(Vector2(700, 100), lo, hi), Vector2(700, 432), "above")
	assert_eq(Player.confine(Vector2(-50, 1200), lo, hi), Vector2(0, 1080), "left and below")
	assert_eq(Player.confine(Vector2(2000, 1200), lo, hi), Vector2(1920, 1080), "right and below")
	assert_eq(Player.confine(Vector2(700, 432), lo, hi), Vector2(700, 432), "on the edge")
	assert_eq(Player.confine(Vector2(5, 5), Vector2(10, 20), Vector2(30, 40)), Vector2(10, 20), "other bounds")


func test_clamp_to_bounds_uses_tuning() -> void:
	assert_eq(_player.clamp_to_bounds(Vector2(-1, 0)), Vector2(0, 432))
	assert_eq(_player.clamp_to_bounds(Vector2(5000, 5000)), Vector2(1920, 1080))
	assert_eq(_player.clamp_to_bounds(Vector2(700, 600)), Vector2(700, 600))


# --- step_lock: the I/O matrix ------------------------------------------------

func test_inside_zone_locks_same_tick_no_warp() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	_player.global_position = Vector2(960, 900)
	_player.step_lock(Vector2(700, 600))
	assert_eq(_player.global_position, Vector2(700, 600), "exactly on the cursor, no residual offset")
	assert_eq(_warps, [] as Array[Vector2], "no warp inside the zone")


func test_above_zone_clamps_and_warps_to_edge() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	_player.step_lock(Vector2(700, 100))
	assert_eq(_player.global_position, Vector2(700, 432))
	assert_eq(_warps, [Vector2(700, 432)] as Array[Vector2])


func test_outside_x_and_below_clamp_and_warp() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	_player.step_lock(Vector2(-50, 1200))
	assert_eq(_player.global_position, Vector2(0, 1080))
	_player.step_lock(Vector2(2000, 1200))
	assert_eq(_player.global_position, Vector2(1920, 1080))
	assert_eq(_warps, [Vector2(0, 1080), Vector2(1920, 1080)] as Array[Vector2])


func test_on_the_edge_no_repeated_warps() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	for i: int in 5:
		_player.step_lock(Vector2(700, 432))
	assert_eq(_player.global_position, Vector2(700, 432))
	assert_eq(_warps, [] as Array[Vector2], "the edge itself never warps")


func test_sub_pixel_past_the_edge_does_not_warp() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	_player.step_lock(Vector2(700, 431.6))
	assert_eq(_player.global_position, Vector2(700, 432), "still clamped")
	assert_eq(_warps, [] as Array[Vector2], "within WARP_EPS_PX: no warp")


func test_beyond_warp_eps_warps_once() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	_player.step_lock(Vector2(700, 430))
	assert_eq(_player.global_position, Vector2(700, 432))
	assert_eq(_warps, [Vector2(700, 432)] as Array[Vector2])


func test_visible_mode_clamps_without_warp() -> void:
	PauseArbiter.set_gameplay_mouse_mode(VISIBLE)
	_player.step_lock(Vector2(700, 100))
	assert_eq(_player.global_position, Vector2(700, 432))
	assert_eq(_warps, [] as Array[Vector2], "VISIBLE mode never moves the OS cursor")


func test_paused_mode_clamps_without_warp() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	PauseArbiter.push(&"menu")
	_player.step_lock(Vector2(700, 100))
	assert_eq(_warps, [] as Array[Vector2], "mode is VISIBLE while paused")


func test_lock_follows_every_tick_without_lag() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	for target: Vector2 in [Vector2(100, 900), Vector2(1800, 500), Vector2(960, 1080), Vector2(0, 432)]:
		_player.step_lock(target)
		assert_eq(_player.global_position, target, "one tick to %s" % target)


func test_never_rotates() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	for target: Vector2 in [Vector2(0, 432), Vector2(1920, 1080), Vector2(100, 900), Vector2(1500, 100)]:
		_player.step_lock(target)
		assert_eq(_player.rotation, 0.0)


func test_physics_process_locks_to_viewport_mouse() -> void:
	_player.global_position = Vector2(-300, 100)
	var expected: Vector2 = _player.clamp_to_bounds(_player.get_viewport().get_mouse_position())
	_player._physics_process(DT)
	assert_eq(_player.global_position, expected)


func test_lock_reads_viewport_not_global_mouse() -> void:
	var camera: Camera2D = Camera2D.new()
	camera.position = Vector2(960, 540)
	camera.offset = Vector2(40, 0)
	add_child_autofree(camera)
	camera.make_current()
	await wait_process_frames(2)
	var viewport_target: Vector2 = _player.clamp_to_bounds(_player.get_viewport().get_mouse_position())
	var global_target: Vector2 = _player.clamp_to_bounds(_player.get_global_mouse_position())
	assert_ne(viewport_target, global_target, "the camera offset separates the two spaces")
	_player._physics_process(DT)
	assert_eq(_player.global_position, viewport_target, "locks in viewport coordinates")


func test_default_warp_is_the_viewport() -> void:
	var fresh: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(fresh)
	fresh.set_physics_process(false)
	assert_true(fresh.warp_mouse.is_valid(), "defaulted in _ready")
	assert_eq(fresh.warp_mouse.get_method(), &"warp_mouse")
	assert_eq(fresh.warp_mouse.get_object(), fresh.get_viewport())


# --- Resume ---------------------------------------------------------------------

func test_resume_warps_cursor_to_ship_once() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	_player.global_position = Vector2(800, 900)
	PauseArbiter.push(&"menu")
	assert_eq(_warps, [] as Array[Vector2], "no warp on push")
	PauseArbiter.pop(&"menu")
	assert_eq(_warps, [Vector2(800, 900)] as Array[Vector2], "one warp to the ship")
	# The cursor now reads the warped point: the ship does not jump.
	_player.step_lock(Vector2(800, 900))
	assert_eq(_player.global_position, Vector2(800, 900))
	assert_eq(_warps.size(), 1, "no further warp")


func test_pop_while_still_paused_no_warp() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	_player.global_position = Vector2(800, 900)
	PauseArbiter.push(&"story")
	PauseArbiter.push(&"menu")
	PauseArbiter.pop(&"menu")
	assert_eq(_warps, [] as Array[Vector2], "story still pauses")
	PauseArbiter.pop(&"story")
	assert_eq(_warps, [Vector2(800, 900)] as Array[Vector2])


func test_resume_in_visible_mode_no_warp() -> void:
	PauseArbiter.set_gameplay_mouse_mode(VISIBLE)
	PauseArbiter.push(&"menu")
	PauseArbiter.pop(&"menu")
	assert_eq(_warps, [] as Array[Vector2])


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
