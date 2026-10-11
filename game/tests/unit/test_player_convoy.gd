extends "res://tests/fixtures/player_test_base.gd"
## Player vs convoy (Story 6.1, DW-83, GDD #25, #29, #51): the HullArea scene
## shape, the pure resolve_hull sweep and push-out against the formation's one
## solid convex polygon (no slipping through a gap from above, below or the
## side, the slide along the outline, the edge squeeze, winding independence),
## step_lock against a real Convoy (no tunnelling, push-out by a moving hull,
## the first tick, the cursor warp onto the ship), no hearts lost through convoy
## contact, and the Player body-blocking an enemy shot meant for the convoy.

const CONVOY_SCENE: PackedScene = preload("res://entities/allies/convoy.tscn")
const BULLET_SCENE: PackedScene = preload("res://entities/projectiles/enemy_bullet.tscn")
const HIDDEN: Input.MouseMode = Input.MOUSE_MODE_CONFINED_HIDDEN
const LO: Vector2 = Vector2(0, 432)
const HI: Vector2 = Vector2(1920, 1080)
const R: float = 32.0
## The start-of-level formation polygon (convoy at left_x 0): the convex outline
## of the three 128 x 64 hitboxes.
const POLY: PackedVector2Array = [Vector2(16, 882), Vector2(16, 818), Vector2(184, 798),
	Vector2(312, 798), Vector2(480, 818), Vector2(480, 882)]
## The shoulder edge from flank-left's top-left corner up to the lead's.
const SHOULDER_A: Vector2 = Vector2(16, 818)
const SHOULDER_B: Vector2 = Vector2(184, 798)
const V_EPS: Vector2 = Vector2(0.001, 0.001)

var _warps: Array[Vector2] = []
var _convoy: Convoy


func before_each() -> void:
	_warps.clear()
	_begin()
	_player = _make_player(Vector2(248, 700), _record_warp)


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


func _shifted(poly: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in poly:
		out.append(p + by)
	return out


func _reversed(poly: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = poly.duplicate()
	out.reverse()
	return out


## The distance from `p` to the polygon's boundary.
func _boundary_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var best: float = INF
	for i: int in poly.size():
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_to(q))
	return best


## True when the ship at `p` is clear of the polygon (outside it, at least the
## radius from its boundary, within the overlap tolerance).
func _clear(p: Vector2, poly: PackedVector2Array) -> bool:
	return not Geometry2D.is_point_in_polygon(p, poly) and _boundary_distance(p, poly) >= R - Player.HULL_EPS_PX


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


# --- overlaps_hull (pure) -------------------------------------------------------------

func test_overlaps_hull_rows() -> void:
	assert_false(Player.overlaps_hull(Vector2(248, 766), R, POLY), "resting on the lead's top is not overlapping")
	assert_true(Player.overlaps_hull(Vector2(248, 767), R, POLY), "1 px closer overlaps")
	assert_true(Player.overlaps_hull(Vector2(248, 850), R, POLY), "centre inside")
	assert_true(Player.overlaps_hull(Vector2(164, 840), R, POLY), "centre in the gap between two hitboxes")
	assert_false(Player.overlaps_hull(Vector2(900, 600), R, POLY), "far away")
	assert_false(Player.overlaps_hull(Vector2(248, 850), R, PackedVector2Array()), "no polygon")
	assert_false(Player.overlaps_hull(Vector2(248, 850), R, PackedVector2Array([Vector2(0, 0), Vector2(500, 900)])), "2 points is no polygon")


# --- resolve_hull (pure) -------------------------------------------------------------

func test_flick_across_stops_above_the_lead() -> void:
	var p: Vector2 = Player.resolve_hull(Vector2(248, 700), Vector2(248, 1000), R, POLY, LO, HI)
	assert_almost_eq(p, Vector2(248, 766), V_EPS, "stops above the lead it came from")
	assert_false(Player.overlaps_hull(p, R, POLY))


func test_flick_up_from_below_stops_below() -> void:
	var p: Vector2 = Player.resolve_hull(Vector2(248, 1000), Vector2(248, 600), R, POLY, LO, HI)
	assert_almost_eq(p, Vector2(248, 914), V_EPS, "stops below the formation")


func test_slow_descent_through_a_gap_rests_on_the_polygon() -> void:
	for x: float in [164.0, 332.0]:
		var p: Vector2 = Vector2(x, 700)
		var y: float = 700.0
		while y <= 1000.0:
			p = Player.resolve_hull(p, Vector2(x, y), R, POLY, LO, HI)
			if not _clear(p, POLY):
				fail_test("x %s: overlapping the formation at cursor y %s: %s" % [x, y, p])
				return
			y += 4.0
		assert_lt(p.y, 800.0, "x %s: still above the formation" % x)
		assert_almost_eq(_boundary_distance(p, POLY), R, 0.01, "x %s: resting on the outline" % x)


func test_rise_through_a_gap_from_below_stops_below() -> void:
	for x: float in [164.0, 248.0, 332.0]:
		var p: Vector2 = Vector2(x, 1000)
		var y: float = 1000.0
		while y >= 700.0:
			p = Player.resolve_hull(p, Vector2(x, y), R, POLY, LO, HI)
			if not _clear(p, POLY):
				fail_test("x %s: overlapping the formation at cursor y %s: %s" % [x, y, p])
				return
			y -= 4.0
		assert_almost_eq(p, Vector2(x, 914), V_EPS, "x %s: stopped below the formation" % x)


func test_side_approach_into_the_pocket_under_the_lead() -> void:
	var poly: PackedVector2Array = _shifted(POLY, Vector2(200, 0))
	var p: Vector2 = Vector2(100, 870)
	var x: float = 100.0
	while x <= 900.0:
		p = Player.resolve_hull(p, Vector2(x, 870), R, poly, LO, HI)
		if not _clear(p, poly) or p.x > 184.001:
			fail_test("rightward: inside or past the formation at cursor x %s: %s" % [x, p])
			return
		x += 4.0
	assert_almost_eq(p, Vector2(184, 870), V_EPS, "stopped at the formation's left edge")
	assert_almost_eq(Player.resolve_hull(Vector2(100, 870), Vector2(900, 870), R, poly, LO, HI), Vector2(184, 870), V_EPS, "one flick right")
	p = Vector2(900, 870)
	x = 900.0
	while x >= 100.0:
		p = Player.resolve_hull(p, Vector2(x, 870), R, poly, LO, HI)
		if not _clear(p, poly) or p.x < 711.999:
			fail_test("leftward: inside or past the formation at cursor x %s: %s" % [x, p])
			return
		x -= 4.0
	assert_almost_eq(p, Vector2(712, 870), V_EPS, "stopped at the formation's right edge")
	assert_almost_eq(Player.resolve_hull(Vector2(900, 870), Vector2(100, 870), R, poly, LO, HI), Vector2(712, 870), V_EPS, "one flick left")


func test_diagonal_move_slides_along_the_shoulder() -> void:
	var target: Vector2 = Vector2(150, 830)
	assert_true(Geometry2D.is_point_in_polygon(target, POLY), "the target is inside the formation")
	var p: Vector2 = Player.resolve_hull(Vector2(60, 740), target, R, POLY, LO, HI)
	assert_false(Player.overlaps_hull(p, R, POLY), "outside the formation")
	var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, SHOULDER_A, SHOULDER_B)
	assert_almost_eq(p.distance_to(q), R, 0.01, "resting on the sloped shoulder")
	assert_true(q != SHOULDER_A and q != SHOULDER_B, "on the edge itself, not a corner")
	assert_gt(p.x, 100.0, "slid along the shoulder toward the target x")


func test_clear_path_reaches_the_target() -> void:
	assert_eq(Player.resolve_hull(Vector2(600, 700), Vector2(900, 600), R, POLY, LO, HI), Vector2(900, 600))


func test_degenerate_polygon_is_a_plain_confine() -> void:
	assert_eq(Player.resolve_hull(Vector2(80, 700), Vector2(-50, 1200), R, PackedVector2Array(), LO, HI), Vector2(0, 1080))
	var two: PackedVector2Array = PackedVector2Array([Vector2(0, 850), Vector2(500, 850)])
	assert_eq(Player.resolve_hull(Vector2(248, 700), Vector2(248, 1000), R, two, LO, HI), Vector2(248, 1000), "2 points")
	assert_eq(Player.resolve_hull(Vector2(248, 700), Vector2(248, 1000), 0.0, POLY, LO, HI), Vector2(248, 1000), "radius 0")


func test_centre_inside_leaves_by_the_nearest_edge() -> void:
	var p: Vector2 = Player.resolve_hull(Vector2(300, 860), Vector2(300, 860), R, POLY, LO, HI)
	assert_almost_eq(p, Vector2(300, 914), V_EPS, "out through the bottom (nearest)")
	var q: Vector2 = Player.resolve_hull(Vector2(470, 850), Vector2(470, 850), R, POLY, LO, HI)
	assert_almost_eq(q, Vector2(512, 850), V_EPS, "out through the right edge")


func test_squeeze_at_the_screen_edge_pushes_along_y() -> void:
	var p: Vector2 = Player.resolve_hull(Vector2(0, 840), Vector2(0, 840), R, POLY, LO, HI)
	assert_eq(p.x, 0.0, "kept on the screen edge")
	assert_false(Player.overlaps_hull(p, R, POLY), "never left inside the formation")
	assert_almost_eq(p.y, 818.0 - sqrt(R * R - 16.0 * 16.0), 0.01, "up to 32 px from the corner (16, 818), about 790.29")


func test_squeeze_at_the_screen_edge_pushes_down_when_nearer() -> void:
	var p: Vector2 = Player.resolve_hull(Vector2(0, 890), Vector2(0, 890), R, POLY, LO, HI)
	assert_eq(p.x, 0.0, "kept on the screen edge")
	assert_false(Player.overlaps_hull(p, R, POLY), "never left inside the formation")
	assert_almost_eq(p.y, 882.0 + sqrt(R * R - 16.0 * 16.0), 0.01, "down to 32 px from the corner (16, 882), about 909.71")


func test_squeeze_at_the_right_screen_edge_pushes_along_y() -> void:
	var poly: PackedVector2Array = _shifted(POLY, Vector2(1424, 0))
	var p: Vector2 = Player.resolve_hull(Vector2(1920, 840), Vector2(1920, 840), R, poly, LO, HI)
	assert_eq(p.x, 1920.0, "kept on the right screen edge")
	assert_false(Player.overlaps_hull(p, R, poly), "never left inside the formation")
	assert_almost_eq(p.y, 818.0 - sqrt(R * R - 16.0 * 16.0), 0.01, "up to 32 px from the corner (1904, 818), about 790.29")


func test_result_does_not_depend_on_winding() -> void:
	var rev: PackedVector2Array = _reversed(POLY)
	var cases: Array[Array] = [
		[Vector2(248, 700), Vector2(248, 1000)],
		[Vector2(248, 1000), Vector2(248, 600)],
		[Vector2(60, 740), Vector2(150, 830)],
		[Vector2(300, 860), Vector2(300, 860)],
		[Vector2(470, 850), Vector2(470, 850)],
		[Vector2(0, 840), Vector2(0, 840)],
		[Vector2(100, 850), Vector2(900, 850)],
	]
	for c: Array in cases:
		var a: Vector2 = Player.resolve_hull(c[0], c[1], R, POLY, LO, HI)
		var b: Vector2 = Player.resolve_hull(c[0], c[1], R, rev, LO, HI)
		assert_almost_eq(b, a, V_EPS, "%s -> %s: same result for either winding" % [c[0], c[1]])
		assert_eq(Player.overlaps_hull(c[1], R, rev), Player.overlaps_hull(c[1], R, POLY), "overlaps_hull winding-free at %s" % c[1])


# --- step_lock with a real convoy --------------------------------------------------------

func test_cursor_flick_through_the_formation_is_blocked_and_warped() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	_make_convoy()
	_player.step_lock(Vector2(248, 700))
	assert_eq(_player.global_position, Vector2(248, 700), "first tick snaps")
	_player.step_lock(Vector2(248, 1000))
	assert_almost_eq(_player.global_position, Vector2(248, 766), V_EPS, "stopped on the near side")
	assert_false(Player.overlaps_hull(_player.global_position, R, _convoy.hull_polygon()))
	assert_eq(_warps.size(), 1, "one warp")
	if _warps.size() == 1:
		assert_almost_eq(_warps[0], _player.global_position, V_EPS, "cursor warped onto the ship")


func test_side_approach_against_a_moved_convoy() -> void:
	_make_convoy()
	_convoy.step(5.0)
	assert_eq(_convoy.left_x(), 200.0)
	var poly: PackedVector2Array = _convoy.hull_polygon()
	assert_eq(poly[0].x, 216.0, "polygon from x 216")
	assert_eq(poly[5].x, 680.0, "to x 680")
	_player.step_lock(Vector2(100, 870))
	var x: float = 104.0
	while x <= 900.0:
		_player.step_lock(Vector2(x, 870))
		var p: Vector2 = _player.global_position
		if not _clear(p, poly) or p.x > 184.001:
			fail_test("inside or past the formation at cursor x %s: %s" % [x, p])
			return
		x += 4.0
	assert_almost_eq(_player.global_position, Vector2(184, 870), V_EPS, "stopped left of the pocket")
	_player.global_position = Vector2(100, 870)
	_player.step_lock(Vector2(100, 870))
	_player.step_lock(Vector2(900, 870))
	assert_almost_eq(_player.global_position, Vector2(184, 870), V_EPS, "a flick from the left stops left of it")
	_player.global_position = Vector2(900, 870)
	_player.step_lock(Vector2(900, 870))
	_player.step_lock(Vector2(100, 870))
	assert_almost_eq(_player.global_position, Vector2(712, 870), V_EPS, "a flick from the right stops right of it")


func test_descent_through_a_gap_then_a_moving_shoulder_with_a_real_convoy() -> void:
	_make_convoy()
	_player.global_position = Vector2(164, 700)
	_player.step_lock(Vector2(164, 700))
	var y: float = 704.0
	while y <= 1000.0:
		_player.step_lock(Vector2(164, y))
		if Player.overlaps_hull(_player.global_position, R, _convoy.hull_polygon()):
			fail_test("overlapping the formation at cursor y %s: %s" % [y, _player.global_position])
			return
		y += 4.0
	assert_lt(_player.global_position.y, 800.0, "ended above the formation")
	assert_almost_eq(_boundary_distance(_player.global_position, _convoy.hull_polygon()), R, 0.01, "resting on the outline")
	var q: Vector2 = Geometry2D.get_closest_point_to_segment(_player.global_position, SHOULDER_A, SHOULDER_B)
	assert_almost_eq(_player.global_position.distance_to(q), R, 0.01, "resting on the left shoulder")
	for i: int in 60:
		_convoy.step(1.0 / 60.0)
		_player.step_lock(_player.global_position)
		if Player.overlaps_hull(_player.global_position, R, _convoy.hull_polygon()):
			fail_test("overlapping the moving formation at tick %d: %s" % [i, _player.global_position])
			return
	assert_almost_eq(_convoy.left_x(), 40.0, 0.001, "the convoy moved 40 px under the ship")


func test_moving_hull_pushes_a_still_ship_and_warps() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	_make_convoy()
	_player.global_position = Vector2(520, 850)
	_player.step_lock(Vector2(520, 850))
	assert_eq(_player.global_position, Vector2(520, 850), "clear of the formation at the start")
	assert_eq(_warps, [] as Array[Vector2])
	_convoy.step(1.0)
	_player.step_lock(Vector2(520, 850))
	var right_x: float = _convoy.hull_polygon()[5].x
	assert_eq(right_x, 520.0, "the formation moved 40 px right")
	assert_almost_eq(_player.global_position, Vector2(right_x + R, 850), V_EPS, "pushed 32 px right of the polygon")
	assert_eq(_warps.size(), 1, "cursor warped once")
	if _warps.size() == 1:
		assert_almost_eq(_warps[0], _player.global_position, V_EPS)
	_player.step_lock(_player.global_position)
	assert_eq(_warps.size(), 1, "no warp once the cursor sits on the ship")


func test_first_tick_inside_the_formation_snaps_then_pushes_out() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	var fresh: Player = PLAYER_SCENE.instantiate() as Player
	fresh.warp_mouse = _record_warp
	add_child_autofree(fresh)
	fresh.set_physics_process(false)
	_player = fresh
	_make_convoy()
	fresh.step_lock(Vector2(300, 860))
	assert_almost_eq(fresh.global_position, Vector2(300, 914), V_EPS, "out of the formation on the first tick")
	assert_signal_not_emitted(Events, "player_moved", "the first tick is not movement")


func test_no_hearts_lost_through_convoy_contact() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	_make_convoy()
	_player.step_lock(Vector2(248, 700))
	for y: float in [760.0, 800.0, 860.0, 1000.0]:
		_player.step_lock(Vector2(248, y))
	_player.global_position = Vector2(248, 830)
	await wait_physics_frames(5)
	assert_eq(_player.hearts, 5, "no heart lost")
	assert_signal_not_emitted(Events, "player_hit")
	for i: int in get_signal_emit_count(Events, "hearts_changed"):
		assert_eq(get_signal_parameters(Events, "hearts_changed", i)[0], 5, "only the full-hearts broadcast")


func test_visible_mode_never_warps() -> void:
	_make_convoy()
	_player.step_lock(Vector2(248, 700))
	_player.step_lock(Vector2(248, 1000))
	assert_almost_eq(_player.global_position, Vector2(248, 766), V_EPS, "still blocked")
	assert_eq(_warps, [] as Array[Vector2], "no warp outside CONFINED_HIDDEN")


func test_freed_convoy_turns_the_hulls_off() -> void:
	_make_convoy()
	_player.step_lock(Vector2(248, 700))
	_convoy.free()
	_player.step_lock(Vector2(248, 1000))
	assert_eq(_player.global_position, Vector2(248, 1000), "no convoy left: plain lock")


func test_null_convoy_is_a_plain_lock() -> void:
	_player.set_convoy(null)
	_player.step_lock(Vector2(248, 700))
	_player.step_lock(Vector2(248, 1000))
	assert_eq(_player.global_position, Vector2(248, 1000))


# --- Body-block (AC) ----------------------------------------------------------------------

func test_player_body_blocks_a_shot_meant_for_the_convoy() -> void:
	var convoy: Convoy = _make_convoy()
	var ship: ConvoyShip = convoy.ships()[Convoy.FLANK_LEFT]
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
	_player.step_lock(Vector2(248, 700))
	_player.step_lock(Vector2(248, 1000))
	assert_signal_emit_count(Events, "player_moved", 1, "one move up to the formation")
	assert_almost_eq(float(get_signal_parameters(Events, "player_moved", 0)[0]), 66.0, 0.01, "700 -> 766, not to the cursor")
	_player.step_lock(Vector2(248, 1000))
	assert_signal_emit_count(Events, "player_moved", 1, "pushing into the formation is not movement")
