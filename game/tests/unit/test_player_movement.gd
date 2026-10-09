extends GutTest
## Player: zero-delay cursor lock, zone confinement, cursor warps (zone edge and
## resume), the hurtbox scene shape and the hull sprite (Story 4.0).

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")
const DT: float = 1.0 / 60.0
const LAYER_PLAYER: int = 1
const MASK_ENEMIES_ASTEROIDS_PICKUPS: int = (1 << 2) | (1 << 4) | (1 << 5)
const HIDDEN: Input.MouseMode = Input.MOUSE_MODE_CONFINED_HIDDEN
const VISIBLE: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
const HULL_DIR: String = "res://assets/sprites/player/"
const HULL_PATH: String = HULL_DIR + "playerShip1_coalition.png"

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


## Story 4.5: under a non-16:9 window the mouse can sit in a letterbox bar,
## which arrives as a viewport coordinate outside the playfield. It is confined
## and warped back in viewport coordinates like any other outside point.
func test_mouse_in_a_letterbox_bar_clamps_and_warps_in_viewport_coords() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	_player.step_lock(Vector2(-150, 1200))
	assert_eq(_player.global_position, Vector2(0, 1080), "left pillarbox, below the field")
	assert_eq(_warps, [Vector2(0, 1080)] as Array[Vector2], "one warp, viewport coordinates")
	_player.step_lock(Vector2(2100, 300))
	assert_eq(_player.global_position, Vector2(1920, 432), "right pillarbox, above the zone")
	assert_eq(_warps, [Vector2(0, 1080), Vector2(1920, 432)] as Array[Vector2])


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


## DW-61: the outgoing Player of a scene change is out of the tree (not yet
## freed, still connected) when SceneRouter clears the pauses after the swap.
func test_out_of_tree_player_does_not_warp_on_resume() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	_player.global_position = Vector2(800, 900)
	PauseArbiter.push(&"death")
	remove_child(_player)
	assert_false(_player.is_inside_tree(), "fixture: removed from the tree")
	PauseArbiter.clear()
	assert_eq(_warps, [] as Array[Vector2], "no warp from a Player outside the tree")


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


# --- Hull sprite (Story 4.0) -------------------------------------------------

## Drawn hull size: the texture size times the Sprite scale.
func _drawn(sprite: Sprite2D) -> Vector2:
	return sprite.texture.get_size() * sprite.scale


func test_sprite_is_the_real_hull() -> void:
	var sprite: Sprite2D = _player.get_node("Sprite") as Sprite2D
	assert_not_null(sprite.texture, "has a texture")
	if sprite.texture == null:
		return
	assert_false(sprite.texture is GradientTexture2D, "not the placeholder gradient")
	assert_eq(sprite.texture.resource_path, HULL_PATH)
	assert_eq(sprite.position, Vector2.ZERO, "centred on the ship")
	assert_eq(sprite.rotation, 0.0, "never rotated")
	assert_true(sprite.modulate.r <= 1.0 and sprite.modulate.g <= 1.0 and sprite.modulate.b <= 1.0,
			"modulate not HDR")
	assert_true(sprite.self_modulate.r <= 1.0 and sprite.self_modulate.g <= 1.0
			and sprite.self_modulate.b <= 1.0, "self_modulate not HDR")


func test_hull_asset_is_the_coalition_recolour() -> void:
	var tex: Texture2D = load(HULL_PATH) as Texture2D
	assert_not_null(tex, "hull PNG loads (run --import first)")
	if tex == null:
		return
	var image: Image = tex.get_image()
	assert_eq(Vector2i(image.get_width(), image.get_height()), Vector2i(99, 75))
	if image.is_compressed():
		image.decompress()
	var counts: Dictionary = {}
	for y: int in image.get_height():
		for x: int in image.get_width():
			var c: Color = image.get_pixel(x, y)
			if c.a8 == 255:
				var key: int = (c.r8 << 16) | (c.g8 << 8) | c.b8
				counts[key] = int(counts.get(key, 0)) + 1
	var best: int = -1
	var best_count: int = 0
	for key: int in counts:
		if int(counts[key]) > best_count:
			best = key
			best_count = int(counts[key])
	var coalition: Color = Color("#22E6FF")
	assert_almost_eq((best >> 16) & 0xFF, coalition.r8, 1, "body red")
	assert_almost_eq((best >> 8) & 0xFF, coalition.g8, 1, "body green")
	assert_almost_eq(best & 0xFF, coalition.b8, 1, "body blue")


func test_sprite_longer_side_matches_sprite_px() -> void:
	var sprite: Sprite2D = _player.get_node("Sprite") as Sprite2D
	var px: float = Config.num("player.sprite_px")
	var drawn: Vector2 = _drawn(sprite)
	assert_almost_eq(maxf(drawn.x, drawn.y), px, 1.0, "longer side = sprite_px")
	assert_almost_eq(sprite.scale.x, sprite.scale.y, 0.0001, "uniform scale")
	assert_almost_eq(drawn.x / drawn.y, sprite.texture.get_size().x / sprite.texture.get_size().y,
			0.0001, "aspect kept")


func test_muzzle_on_the_nose() -> void:
	var sprite: Sprite2D = _player.get_node("Sprite") as Sprite2D
	var muzzle: Marker2D = _player.get_node("Muzzle") as Marker2D
	assert_almost_eq(muzzle.position.x, 0.0, 0.01)
	assert_almost_eq(muzzle.position.y, -_drawn(sprite).y / 2.0, 0.01)


func test_hurtbox_and_sprite_sizes_follow_config() -> void:
	# Values differ from the defaults, so only _ready() can set them.
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
	var hurtbox: CollisionShape2D = fresh.get_node("Hurtbox") as CollisionShape2D
	var circle: CircleShape2D = hurtbox.shape as CircleShape2D
	assert_eq(circle.radius, 20.0)
	assert_eq(hurtbox.position, Vector2.ZERO)
	var sprite: Sprite2D = fresh.get_node("Sprite") as Sprite2D
	var drawn: Vector2 = _drawn(sprite)
	assert_almost_eq(maxf(drawn.x, drawn.y), 64.0, 1.0, "longer side = 64")
	assert_almost_eq(sprite.scale.x, sprite.scale.y, 0.0001, "uniform scale")
	var muzzle: Marker2D = fresh.get_node("Muzzle") as Marker2D
	assert_almost_eq(muzzle.position.y, -drawn.y / 2.0, 0.01, "Muzzle follows the nose")
	assert_almost_eq(muzzle.position.x, 0.0, 0.01)


func test_bad_sprite_px_warns_and_keeps_scale() -> void:
	var lines: Array[String] = []
	var capture: Callable = func(level: String, category: String, msg: String) -> void:
		lines.append(Log.format(level, category, msg))
	var player_tuning: Dictionary = Config.tuning["player"]
	var original_sprite_px: Variant = player_tuning["sprite_px"]
	player_tuning["sprite_px"] = 0
	Log.sink = capture
	var fresh: Player = PLAYER_SCENE.instantiate() as Player
	var scene_muzzle: Vector2 = (fresh.get_node("Muzzle") as Marker2D).position
	add_child_autofree(fresh)
	Log.sink = Callable()
	player_tuning["sprite_px"] = original_sprite_px
	fresh.set_physics_process(false)
	assert_eq((fresh.get_node("Sprite") as Sprite2D).scale, Vector2.ONE, "scale unchanged")
	assert_eq((fresh.get_node("Muzzle") as Marker2D).position, scene_muzzle, "Muzzle unchanged")
	var warns: Array[String] = []
	for line: String in lines:
		# The MissileRing also warns about its radius clamp here (sprite_px / 2 = 0).
		if line.begins_with("[WARN][data] Player hull"):
			warns.append(line)
	assert_eq(warns.size(), 1, "one hull data WARN")


# --- Story 5.8: player_moved ------------------------------------------------------

func test_player_moved_fires_on_movement_and_not_when_still() -> void:
	watch_signals(Events)
	_player.step_lock(Vector2(700, 600))
	assert_signal_not_emitted(Events, "player_moved", "the first lock tick only snaps the spawned ship")
	_player.step_lock(Vector2(800, 600))
	assert_signal_emit_count(Events, "player_moved", 1, "moved 100 px")
	assert_almost_eq(float(get_signal_parameters(Events, "player_moved", 0)[0]), 100.0, 0.001, "distance")
	_player.step_lock(Vector2(800, 600))
	assert_signal_emit_count(Events, "player_moved", 1, "still: no emit")
	_player.step_lock(Vector2(800, 100))
	assert_signal_emit_count(Events, "player_moved", 2, "confined distance")
	assert_almost_eq(float(get_signal_parameters(Events, "player_moved", 1)[0]), 600.0 - Config.num("player.bounds_y.min"), 0.001, "600 -> the zone top")
	_player.step_lock(Vector2(800, 50))
	assert_signal_emit_count(Events, "player_moved", 2, "pushing against the edge is not movement")
