extends "res://tests/fixtures/player_test_base.gd"
## Player vs convoy (Story 6.1, GDD #25, #29): the HullArea scene shape, the pure
## resolve_hull sweep and push-out, step_lock against a real Convoy (no
## tunnelling, slide, push-out by a moving hull, the first tick, the cursor warp
## onto the ship), no hearts lost through convoy contact, and the Player
## body-blocking an enemy shot meant for the convoy.

const CONVOY_SCENE: PackedScene = preload("res://entities/allies/convoy.tscn")
const BULLET_SCENE: PackedScene = preload("res://entities/projectiles/enemy_bullet.tscn")
const HIDDEN: Input.MouseMode = Input.MOUSE_MODE_CONFINED_HIDDEN
const LO: Vector2 = Vector2(0, 432)
const HI: Vector2 = Vector2(1920, 1080)
## The start-of-level FlankTop hitbox (centre (80, 800), 128 x 64).
const FLANK_TOP: Rect2 = Rect2(16, 768, 128, 64)

var _warps: Array[Vector2] = []
var _convoy: Convoy


func before_each() -> void:
	_warps.clear()
	_begin()
	_player = _make_player(Vector2(80, 700), _record_warp)


func after_each() -> void:
	_convoy = null
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	super()


func _record_warp(p: Vector2) -> void:
	_warps.append(p)


func _make_convoy() -> Convoy:
	_convoy = CONVOY_SCENE.instantiate() as Convoy
	add_child_autofree(_convoy)
	_convoy.set_physics_process(false)
	_player.set_convoy(_convoy)
	return _convoy


func _rects(list: Array) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r: Variant in list:
		out.append(r as Rect2)
	return out


# --- Scene shape --------------------------------------------------------------------

func test_hull_area_scene_shape() -> void:
	var hull: Area2D = _player.get_node_or_null("HullArea") as Area2D
	assert_not_null(hull, "HullArea is an Area2D child")
	if hull == null:
		return
	assert_eq(hull.collision_layer, 0, "on no layer")
	assert_eq(hull.collision_mask, CollisionLayers.CONVOY, "masks only the convoy")
	var shape: CollisionShape2D = hull.get_node("HullShape") as CollisionShape2D
	var circle: CircleShape2D = shape.shape as CircleShape2D
	assert_not_null(circle, "a CircleShape2D")
	if circle != null:
		assert_eq(circle.radius, Config.num("player.hull_diameter_px") / 2.0, "radius 32")
	assert_eq(shape.position, Vector2.ZERO)
	assert_eq(_player.hull_radius(), 32.0)


func test_hurtbox_and_root_mask_unchanged() -> void:
	assert_eq(_player.collision_mask, CollisionLayers.ENEMIES | CollisionLayers.ASTEROIDS | CollisionLayers.PICKUPS, "still 52, no convoy")
	assert_eq(_player.collision_mask, 52)
	var circle: CircleShape2D = (_player.get_node("Hurtbox") as CollisionShape2D).shape as CircleShape2D
	assert_eq(circle.radius, 12.0, "the 24 px hurtbox")


func test_hull_radius_follows_tuning() -> void:
	var player_tuning: Dictionary = Config.tuning["player"]
	var original: Variant = player_tuning["hull_diameter_px"]
	player_tuning["hull_diameter_px"] = 80
	var fresh: Player = _make_player(Vector2(500, 600))
	player_tuning["hull_diameter_px"] = original
	assert_eq(fresh.hull_radius(), 40.0)
	var shape: CollisionShape2D = fresh.get_node("HullArea/HullShape") as CollisionShape2D
	assert_eq((shape.shape as CircleShape2D).radius, 40.0)


# --- resolve_hull (pure) -------------------------------------------------------------

func test_flick_through_a_hull_stops_on_the_near_side() -> void:
	var rects: Array[Rect2] = _rects([FLANK_TOP, Rect2(16, 848, 128, 64)])
	var p: Vector2 = Player.resolve_hull(Vector2(80, 700), Vector2(80, 1000), 32.0, rects, LO, HI)
	assert_almost_eq(p, Vector2(80, 736), Vector2(0.001, 0.001), "stops above the hull it came from")
	assert_false(Player.overlaps_hull(p, 32.0, rects), "outside every hull")


func test_flick_up_from_below_stops_below() -> void:
	var rects: Array[Rect2] = _rects([FLANK_TOP, Rect2(16, 848, 128, 64)])
	var p: Vector2 = Player.resolve_hull(Vector2(80, 1000), Vector2(80, 600), 32.0, rects, LO, HI)
	assert_almost_eq(p, Vector2(80, 944), Vector2(0.001, 0.001), "stops below the bottom hull")


func test_diagonal_move_slides_along_the_hull() -> void:
	var rects: Array[Rect2] = _rects([FLANK_TOP])
	var p: Vector2 = Player.resolve_hull(Vector2(40, 700), Vector2(120, 790), 32.0, rects, LO, HI)
	assert_false(Player.overlaps_hull(p, 32.0, rects), "outside the hull")
	assert_almost_eq(p.y, 736.0, 0.01, "resting on the top face")
	assert_gt(p.x, 100.0, "slid along the hull toward the target x")


func test_clear_path_reaches_the_target() -> void:
	var rects: Array[Rect2] = _rects([FLANK_TOP])
	assert_eq(Player.resolve_hull(Vector2(600, 700), Vector2(900, 600), 32.0, rects, LO, HI), Vector2(900, 600))


func test_no_rects_is_a_plain_confine() -> void:
	var none: Array[Rect2] = []
	assert_eq(Player.resolve_hull(Vector2(80, 700), Vector2(-50, 1200), 32.0, none, LO, HI), Vector2(0, 1080))


func test_centre_inside_a_hull_leaves_by_the_nearest_side() -> void:
	var rects: Array[Rect2] = _rects([FLANK_TOP])
	var p: Vector2 = Player.resolve_hull(Vector2(80, 775), Vector2(80, 775), 32.0, rects, LO, HI)
	assert_almost_eq(p, Vector2(80, 736), Vector2(0.001, 0.001), "out through the top (nearest)")
	var q: Vector2 = Player.resolve_hull(Vector2(140, 800), Vector2(140, 800), 32.0, rects, LO, HI)
	assert_almost_eq(q, Vector2(176, 800), Vector2(0.001, 0.001), "out through the right side")


func test_squeeze_at_the_screen_edge_pushes_along_y() -> void:
	var rects: Array[Rect2] = _rects([FLANK_TOP, Rect2(16, 848, 128, 64)])
	var p: Vector2 = Player.resolve_hull(Vector2(0, 800), Vector2(0, 800), 32.0, rects, LO, HI)
	assert_eq(p.x, 0.0, "kept on the screen edge")
	assert_false(Player.overlaps_hull(p, 32.0, rects), "never left inside a hull")
	assert_almost_eq(p.y, 736.0, 0.001, "pushed out along y")


# --- step_lock with a real convoy --------------------------------------------------------

func test_cursor_flick_through_a_convoy_ship_is_blocked_and_warped() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	_make_convoy()
	_player.step_lock(Vector2(80, 700))
	assert_eq(_player.global_position, Vector2(80, 700), "first tick snaps")
	_player.step_lock(Vector2(80, 1000))
	assert_almost_eq(_player.global_position, Vector2(80, 736), Vector2(0.001, 0.001), "stopped on the near side")
	assert_false(Player.overlaps_hull(_player.global_position, 32.0, _convoy.hull_rects()))
	assert_eq(_warps.size(), 1, "one warp")
	if _warps.size() == 1:
		assert_almost_eq(_warps[0], _player.global_position, Vector2(0.001, 0.001), "cursor warped onto the ship")


func test_moving_hull_pushes_a_still_ship_and_warps() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	_make_convoy()
	_player.global_position = Vector2(400, 840)
	_player.step_lock(Vector2(400, 840))
	assert_eq(_player.global_position, Vector2(400, 840), "clear of the lead at the start")
	assert_eq(_warps, [] as Array[Vector2])
	_convoy.step(1.0)
	_player.step_lock(Vector2(400, 840))
	var lead: Rect2 = _convoy.hull_rects()[Convoy.LEAD]
	assert_almost_eq(_player.global_position, Vector2(lead.end.x + 32.0, 840), Vector2(0.001, 0.001), "pushed ahead of the lead")
	assert_eq(_warps.size(), 1, "cursor warped once")
	if _warps.size() == 1:
		assert_almost_eq(_warps[0], _player.global_position, Vector2(0.001, 0.001))
	_player.step_lock(_player.global_position)
	assert_eq(_warps.size(), 1, "no warp once the cursor sits on the ship")


func test_first_tick_inside_a_hull_snaps_then_pushes_out() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	var fresh: Player = PLAYER_SCENE.instantiate() as Player
	fresh.warp_mouse = _record_warp
	add_child_autofree(fresh)
	fresh.set_physics_process(false)
	_player = fresh
	_make_convoy()
	fresh.step_lock(Vector2(80, 775))
	assert_almost_eq(fresh.global_position, Vector2(80, 736), Vector2(0.001, 0.001), "out of the hull on the first tick")
	assert_signal_not_emitted(Events, "player_moved", "the first tick is not movement")


func test_no_hearts_lost_through_convoy_contact() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	_make_convoy()
	_player.step_lock(Vector2(80, 700))
	for y: float in [760.0, 800.0, 860.0, 1000.0]:
		_player.step_lock(Vector2(80, y))
	_player.global_position = Vector2(80, 800)
	await wait_physics_frames(5)
	assert_eq(_player.hearts, 5, "no heart lost")
	assert_signal_not_emitted(Events, "player_hit")
	for i: int in get_signal_emit_count(Events, "hearts_changed"):
		assert_eq(get_signal_parameters(Events, "hearts_changed", i)[0], 5, "only the full-hearts broadcast")


func test_visible_mode_never_warps() -> void:
	_make_convoy()
	_player.step_lock(Vector2(80, 700))
	_player.step_lock(Vector2(80, 1000))
	assert_almost_eq(_player.global_position, Vector2(80, 736), Vector2(0.001, 0.001), "still blocked")
	assert_eq(_warps, [] as Array[Vector2], "no warp outside CONFINED_HIDDEN")


func test_freed_convoy_turns_the_hulls_off() -> void:
	_make_convoy()
	_player.step_lock(Vector2(80, 700))
	_convoy.free()
	_player.step_lock(Vector2(80, 1000))
	assert_eq(_player.global_position, Vector2(80, 1000), "no convoy left: plain lock")


func test_null_convoy_is_a_plain_lock() -> void:
	_player.set_convoy(null)
	_player.step_lock(Vector2(80, 700))
	_player.step_lock(Vector2(80, 1000))
	assert_eq(_player.global_position, Vector2(80, 1000))


# --- Body-block (AC) ----------------------------------------------------------------------

func test_player_body_blocks_a_shot_meant_for_the_convoy() -> void:
	var convoy: Convoy = _make_convoy()
	var ship: ConvoyShip = convoy.ships()[Convoy.FLANK_TOP]
	_player.global_position = ship.global_position + Vector2(0, -100)
	var bullet: EnemyBullet = BULLET_SCENE.instantiate() as EnemyBullet
	bullet.setup({"position": ship.global_position + Vector2(0, -250), "velocity": Vector2(0, 450),
		"damage": Config.int_("damage.bullet_hearts")})
	add_child_autofree(bullet)
	await wait_physics_frames(40)
	assert_eq(_player.hearts, 4, "the Player takes the heart")
	assert_eq(convoy.hp(), convoy.max_hp(), "the convoy takes nothing")
	assert_true(not is_instance_valid(bullet) or bullet.is_queued_for_deletion(), "the bullet is spent")


func test_player_moved_uses_the_blocked_position() -> void:
	_make_convoy()
	_player.step_lock(Vector2(80, 700))
	_player.step_lock(Vector2(80, 1000))
	assert_signal_emit_count(Events, "player_moved", 1, "one move up to the hull")
	assert_almost_eq(float(get_signal_parameters(Events, "player_moved", 0)[0]), 36.0, 0.01, "700 -> 736, not to the cursor")
	_player.step_lock(Vector2(80, 1000))
	assert_signal_emit_count(Events, "player_moved", 1, "pushing into the hull is not movement")
