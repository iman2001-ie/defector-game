extends GutTest
## Convoy + ConvoyShip (Story 6.1, DW-83): the scene shape and layers, the
## nose-up side-by-side layout (lead raised in the middle) centred in the band,
## the ping-pong path (step_span, no mirroring), the shared HP pool and its loss
## (first outcome wins), the cached solid hull polygon and the code-drawn
## nose-up hull. Driven through step() with physics off.

const SpriteProbe: GDScript = preload("res://tests/fixtures/sprite_probe.gd")
const CONVOY_SCENE: PackedScene = preload("res://entities/allies/convoy.tscn")
const SHIP_SCENE: PackedScene = preload("res://entities/allies/convoy_ship.tscn")
const DT: float = 1.0 / 60.0
const PLAYER_SPAWN: Vector2 = Vector2(960, 900)

var _lines: Array[String] = []


func before_each() -> void:
	_lines.clear()
	Log.sink = _capture
	watch_signals(Events)


func after_each() -> void:
	Log.sink = Callable()
	Config.load_data()
	Feedback.reset()  # Drop a pending death chain (and its hit-stop).
	Feedback.load_tiers()


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _logged(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.begins_with(prefix):
			out.append(line)
	return out


func _make() -> Convoy:
	var convoy: Convoy = CONVOY_SCENE.instantiate() as Convoy
	convoy.setup({})
	add_child_autofree(convoy)
	convoy.set_physics_process(false)
	return convoy


## The drawn (sprite-extent) rect of a ship.
func _sprite_rect(ship: ConvoyShip) -> Rect2:
	return Rect2(ship.global_position - ship.hull_size() / 2.0, ship.hull_size())


func _group_rect(convoy: Convoy) -> Rect2:
	var out: Rect2 = _sprite_rect(convoy.ships()[0])
	for ship: ConvoyShip in convoy.ships():
		out = out.merge(_sprite_rect(ship))
	return out


# --- Tuning and scene shape -------------------------------------------------------

func test_tuning() -> void:
	assert_eq(Config.int_("convoy.hp"), 100)
	assert_eq(Config.int_("convoy.ships"), 3)
	assert_eq(Config.num("convoy.ship_width_px"), 160.0)
	assert_eq(Config.num("convoy.ship_height_px"), 80.0)
	assert_eq(Config.num("convoy.hitbox_ratio"), 0.8)
	assert_eq(Config.num("convoy.speed_px_s"), 40.0)
	assert_eq(Config.num("convoy.band_y.min"), 760.0)
	assert_eq(Config.num("convoy.band_y.max"), 920.0)
	assert_eq(Config.num("convoy.gap_px"), 8.0)
	assert_eq(Config.num("convoy.lead_raise_px"), 20.0)
	assert_false((Config.tuning["convoy"] as Dictionary).has("lead_offset_px"), "the old lead offset is gone")


func test_scene_shape() -> void:
	var convoy: Convoy = _make()
	assert_true(convoy.is_in_group(&"convoy"), "joins the convoy group")
	var names: Array[String] = []
	for child: Node in convoy.get_children():
		names.append(String(child.name))
	assert_eq(names, ["Lead", "FlankLeft", "FlankRight"] as Array[String])
	assert_eq(convoy.ships().size(), 3)
	for ship: ConvoyShip in convoy.ships():
		assert_true(ship is Area2D)
		assert_eq(ship.collision_layer, CollisionLayers.CONVOY, "%s on the convoy layer" % ship.name)
		assert_eq(ship.collision_mask, 0, "%s detects nothing" % ship.name)
		assert_false(ship.monitoring, "%s monitoring off" % ship.name)
		assert_true(ship.monitorable, "%s found by shots" % ship.name)
		assert_eq(ship.convoy, convoy)
		var hitbox: CollisionShape2D = ship.get_node("Hitbox") as CollisionShape2D
		var rect: RectangleShape2D = hitbox.shape as RectangleShape2D
		assert_not_null(rect, "Hitbox is a RectangleShape2D")
		if rect != null:
			assert_eq(rect.size, Vector2(128, 64), "160 x 80 at hitbox_ratio 0.8")
		assert_eq(ship.hull_size(), Vector2(160, 80))
		assert_eq(ship.rotation, 0.0)


func test_hitbox_follows_tuning() -> void:
	var convoy_tuning: Dictionary = Config.tuning["convoy"]
	convoy_tuning["ship_width_px"] = 200
	convoy_tuning["hitbox_ratio"] = 0.5
	var ship: ConvoyShip = SHIP_SCENE.instantiate() as ConvoyShip
	add_child_autofree(ship)
	assert_eq(ship.hitbox_size(), Vector2(100, 40))
	assert_eq(((ship.get_node("Hitbox") as CollisionShape2D).shape as RectangleShape2D).size, Vector2(100, 40))


func test_wrong_ship_count_warns() -> void:
	(Config.tuning["convoy"] as Dictionary)["ships"] = 4
	var convoy: Convoy = _make()
	assert_eq(_logged("[WARN][data] convoy.ships").size(), 1, "one data WARN")
	assert_eq(convoy.ships().size(), 3, "still three ships")


# --- Layout --------------------------------------------------------------------------

func test_start_layout_left_edge_heading_right() -> void:
	var convoy: Convoy = _make()
	assert_eq(convoy.left_x(), 0.0)
	assert_eq(convoy.direction(), 1)
	assert_eq(convoy.span(), 496.0, "3 x 160 + 2 x 8")
	var ships: Array[ConvoyShip] = convoy.ships()
	assert_eq(ships[Convoy.FLANK_LEFT].global_position, Vector2(80, 850))
	assert_eq(ships[Convoy.LEAD].global_position, Vector2(248, 830), "lead in the middle, raised")
	assert_eq(ships[Convoy.FLANK_RIGHT].global_position, Vector2(416, 850))
	var group: Rect2 = _group_rect(convoy)
	assert_eq(group, Rect2(0, 790, 496, 100), "the group from x 0, centred in the band")
	for ship: ConvoyShip in ships:
		var r: Rect2 = _sprite_rect(ship)
		assert_true(Playfield.RECT.encloses(r), "%s fully on-screen" % ship.name)
		assert_true(r.position.y >= 760.0 and r.end.y <= 920.0, "%s inside y 760-920" % ship.name)
		assert_false(r.has_point(PLAYER_SPAWN), "%s clear of the player spawn" % ship.name)


func test_lead_is_raised_between_the_flankers() -> void:
	var convoy: Convoy = _make()
	var ships: Array[ConvoyShip] = convoy.ships()
	var lead: Vector2 = ships[Convoy.LEAD].global_position
	var left: Vector2 = ships[Convoy.FLANK_LEFT].global_position
	var right: Vector2 = ships[Convoy.FLANK_RIGHT].global_position
	assert_eq(left.y - lead.y, 20.0, "the lead sits lead_raise_px higher")
	assert_eq(left.y, right.y, "flankers on one row")
	assert_true(left.x < lead.x and lead.x < right.x, "lead between the flankers")
	assert_eq(lead.x - left.x, right.x - lead.x, "symmetric about the lead")


func test_hulls_are_gap_px_apart() -> void:
	var convoy: Convoy = _make()
	var left: Rect2 = _sprite_rect(convoy.ships()[Convoy.FLANK_LEFT])
	var lead: Rect2 = _sprite_rect(convoy.ships()[Convoy.LEAD])
	var right: Rect2 = _sprite_rect(convoy.ships()[Convoy.FLANK_RIGHT])
	assert_eq(lead.position.x - left.end.x, 8.0, "8 px between flank-left and the lead")
	assert_eq(right.position.x - lead.end.x, 8.0, "8 px between the lead and flank-right")


func test_layout_tuning_is_clamped_at_zero() -> void:
	var convoy_tuning: Dictionary = Config.tuning["convoy"]
	convoy_tuning["gap_px"] = -10
	convoy_tuning["lead_raise_px"] = -5
	var convoy: Convoy = _make()
	assert_eq(convoy.span(), 480.0, "a negative gap counts as 0")
	var ships: Array[ConvoyShip] = convoy.ships()
	assert_eq(ships[Convoy.LEAD].global_position.y, ships[Convoy.FLANK_LEFT].global_position.y, "a negative raise counts as 0")


func test_hulls_never_overlap() -> void:
	var convoy: Convoy = _make()
	for dir_run: int in 2:
		var rects: Array[Rect2] = []
		for ship: ConvoyShip in convoy.ships():
			rects.append(_sprite_rect(ship))
		for i: int in rects.size():
			for j: int in range(i + 1, rects.size()):
				var overlap: Rect2 = rects[i].intersection(rects[j])
				assert_true(overlap.size.x <= 0.0 or overlap.size.y <= 0.0, "hulls %d and %d don't overlap" % [i, j])
		convoy.step(60.0)


func test_ship_centres_pure() -> void:
	var at_100: Array[Vector2] = Convoy.ship_centres(100.0, 160.0, 80.0, 8.0, 20.0, 760.0, 920.0)
	assert_eq(at_100, [Vector2(348, 830), Vector2(180, 850), Vector2(516, 850)] as Array[Vector2])
	assert_eq(Convoy.ship_centre(Convoy.LEAD, 0.0, 160.0, 80.0, 8.0, 20.0, 760.0, 920.0), Vector2(248, 830))
	assert_eq(Convoy.ship_centre(Convoy.FLANK_LEFT, 0.0, 160.0, 80.0, 8.0, 20.0, 760.0, 920.0), Vector2(80, 850))
	assert_eq(Convoy.ship_centre(Convoy.FLANK_RIGHT, 0.0, 160.0, 80.0, 8.0, 20.0, 760.0, 920.0), Vector2(416, 850))
	assert_eq(Convoy.group_span(160.0, 8.0), 496.0)


func test_moves_right_as_one_group_at_speed() -> void:
	var convoy: Convoy = _make()
	var before: Array[Vector2] = []
	for ship: ConvoyShip in convoy.ships():
		before.append(ship.global_position)
	for i: int in 60:
		convoy.step(DT)
	assert_almost_eq(convoy.left_x(), 40.0, 0.001, "40 px in 1 s")
	for i: int in convoy.ships().size():
		var moved: Vector2 = convoy.ships()[i].global_position - before[i]
		assert_almost_eq(moved.x, 40.0, 0.001, "ship %d moved 40 px right" % i)
		assert_almost_eq(moved.y, 0.0, 0.0001, "ship %d stays in its row" % i)


func test_physics_process_steps() -> void:
	var convoy: Convoy = _make()
	convoy._physics_process(0.5)
	assert_almost_eq(convoy.left_x(), 20.0, 0.001)


func test_step_span_pure() -> void:
	assert_eq(Convoy.step_span(0.0, 1, 10.0, 496.0, 1920.0), Vector2(10, 1), "moving right")
	assert_eq(Convoy.step_span(1414.0, 1, 20.0, 496.0, 1920.0), Vector2(1424, -1), "clamped at the right edge and flipped")
	assert_eq(Convoy.step_span(1424.0, -1, 10.0, 496.0, 1920.0), Vector2(1414, -1), "heading back left")
	assert_eq(Convoy.step_span(5.0, -1, 20.0, 496.0, 1920.0), Vector2(0, 1), "clamped at the left edge and flipped")
	assert_eq(Convoy.step_span(0.0, 1, 0.0, 496.0, 1920.0), Vector2(0, 1), "starting at 0 heading right doesn't flip")
	assert_eq(Convoy.step_span(0.0, 1, 5000.0, 496.0, 1920.0), Vector2(1424, -1), "a huge step still clamps")


## Each ship's offset from the lead (the layout's shape, whatever left_x is).
func _offsets(convoy: Convoy) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var lead: Vector2 = convoy.ships()[Convoy.LEAD].global_position
	for ship: ConvoyShip in convoy.ships():
		out.append(ship.global_position - lead)
	return out


func test_right_edge_turns_without_mirroring() -> void:
	var convoy: Convoy = _make()
	var shape: Array[Vector2] = _offsets(convoy)
	convoy.step(1424.0 / 40.0)
	assert_eq(convoy.left_x(), 1424.0)
	assert_eq(convoy.direction(), -1, "flipped at the right edge")
	assert_eq(_group_rect(convoy).end.x, 1920.0, "right edge exactly on the screen edge")
	assert_eq(_offsets(convoy), shape, "the same layout heading left (no mirroring)")
	var ships: Array[ConvoyShip] = convoy.ships()
	assert_lt(ships[Convoy.FLANK_LEFT].global_position.x, ships[Convoy.LEAD].global_position.x, "flank-left still on the left")


func test_two_crossings_stay_on_screen_with_one_layout() -> void:
	var convoy: Convoy = _make()
	var shape: Array[Vector2] = _offsets(convoy)
	var flips: int = 0
	var last_dir: int = convoy.direction()
	# 1424 px each way at 40 px/s is 35.6 s; run 90 s (two full crossings and more).
	for i: int in 90 * 60:
		convoy.step(DT)
		for ship: ConvoyShip in convoy.ships():
			var r: Rect2 = _sprite_rect(ship)
			if r.position.x < -0.001 or r.end.x > 1920.001:
				fail_test("%s left x 0-1920 at tick %d: %s" % [ship.name, i, r])
				return
		if convoy.direction() != last_dir:
			flips += 1
			last_dir = convoy.direction()
			var now: Array[Vector2] = _offsets(convoy)
			for j: int in now.size():
				if not now[j].is_equal_approx(shape[j]):
					fail_test("layout changed at tick %d: %s" % [i, now])
					return
	assert_gte(flips, 2, "reversed at both edges")


# --- Solid hull polygon (DW-83) -----------------------------------------------------------

func test_hull_polygon_at_the_start() -> void:
	var convoy: Convoy = _make()
	var poly: PackedVector2Array = convoy.hull_polygon()
	assert_eq(poly, PackedVector2Array([Vector2(16, 882), Vector2(16, 818), Vector2(184, 798),
		Vector2(312, 798), Vector2(480, 818), Vector2(480, 882)]), "the convex outline of the three hitboxes")


func test_hull_polygon_is_built_from_the_hitboxes() -> void:
	var convoy: Convoy = _make()
	var poly: PackedVector2Array = convoy.hull_polygon()
	var left: Rect2 = convoy.ships()[Convoy.FLANK_LEFT].hull_rect()
	var lead: Rect2 = convoy.ships()[Convoy.LEAD].hull_rect()
	var right: Rect2 = convoy.ships()[Convoy.FLANK_RIGHT].hull_rect()
	assert_eq(poly[0], Vector2(left.position.x, left.end.y), "flank-left bottom-left")
	assert_eq(poly[1], left.position, "flank-left top-left")
	assert_eq(poly[2], lead.position, "lead top-left")
	assert_eq(poly[3], Vector2(lead.end.x, lead.position.y), "lead top-right")
	assert_eq(poly[4], Vector2(right.end.x, right.position.y), "flank-right top-right")
	assert_eq(poly[5], right.end, "flank-right bottom-right")
	for r: Rect2 in [left, lead, right]:
		for corner: Vector2 in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]:
			assert_true(Geometry2D.is_point_in_polygon(corner, poly) or _on_polygon(corner, poly), "%s inside the polygon" % corner)


func _on_polygon(p: Vector2, poly: PackedVector2Array) -> bool:
	for i: int in poly.size():
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		if q.distance_to(p) < 0.001:
			return true
	return false


func test_hull_polygon_is_cached_and_refreshed_in_place() -> void:
	var convoy: Convoy = _make()
	var poly: PackedVector2Array = convoy.hull_polygon()
	assert_eq(poly.size(), 6)
	convoy.step(1.0)
	var moved: PackedVector2Array = convoy.hull_polygon()
	assert_eq(moved.size(), 6, "still 6 points")
	assert_eq(moved[1], Vector2(56, 818), "refreshed after a step")
	assert_eq(moved[5], Vector2(520, 882))


# --- HP --------------------------------------------------------------------------------

func test_ready_emits_full_hp() -> void:
	var convoy: Convoy = _make()
	assert_eq(convoy.hp(), 100)
	assert_eq(convoy.max_hp(), 100)
	assert_signal_emitted_with_parameters(Events, "convoy_hp_changed", [100, 100])
	assert_false(convoy.is_lost())


func test_damage_lowers_hp_and_broadcasts() -> void:
	var convoy: Convoy = _make()
	convoy.apply_damage(5, null)
	assert_eq(convoy.hp(), 95)
	assert_signal_emitted_with_parameters(Events, "convoy_hp_changed", [95, 100])
	convoy.apply_damage(2, null)
	assert_eq(convoy.hp(), 93)
	assert_signal_emit_count(Events, "convoy_hp_changed", 3, "ready + 2 hits")


func test_non_positive_damage_is_ignored() -> void:
	var convoy: Convoy = _make()
	convoy.apply_damage(0, null)
	convoy.apply_damage(-5, null)
	assert_eq(convoy.hp(), 100)
	assert_signal_emit_count(Events, "convoy_hp_changed", 1, "only the ready broadcast")


func test_ship_forwards_damage_to_the_pool() -> void:
	var convoy: Convoy = _make()
	convoy.ships()[Convoy.FLANK_RIGHT].apply_damage(10, null)
	convoy.ships()[Convoy.LEAD].apply_damage(5, null)
	assert_eq(convoy.hp(), 85, "one shared pool")


func test_hp_persists_across_waves() -> void:
	var convoy: Convoy = _make()
	convoy.apply_damage(30, null)
	Events.wave_started.emit(1, 2)
	Events.wave_cleared.emit(1)
	Events.wave_started.emit(2, 2)
	assert_eq(convoy.hp(), 70, "not reset by a wave change")


func test_loss_fails_the_level_once() -> void:
	var convoy: Convoy = _make()
	convoy.apply_damage(95, null)
	assert_signal_not_emitted(Events, "level_failed")
	convoy.apply_damage(10, null)
	assert_eq(convoy.hp(), 0, "floored at 0")
	assert_true(convoy.is_lost())
	assert_signal_emit_count(Events, "level_failed", 1)
	assert_signal_emitted_with_parameters(Events, "level_failed", [&"convoy"])
	assert_signal_emitted_with_parameters(Events, "convoy_hp_changed", [0, 100])
	assert_eq(_logged("[INFO][combat] Convoy lost").size(), 1, "loss logged")
	var hp_events: int = get_signal_emit_count(Events, "convoy_hp_changed")
	convoy.apply_damage(5, null)
	assert_eq(convoy.hp(), 0)
	assert_signal_emit_count(Events, "level_failed", 1, "never again")
	assert_signal_emit_count(Events, "convoy_hp_changed", hp_events, "no events after the loss")


func test_damage_after_clear_is_ignored() -> void:
	var convoy: Convoy = _make()
	Events.level_cleared.emit(0)
	convoy.apply_damage(100, null)
	assert_eq(convoy.hp(), 100, "no HP change")
	assert_false(convoy.is_lost())
	assert_signal_emit_count(Events, "convoy_hp_changed", 1, "no events")
	assert_signal_not_emitted(Events, "level_failed")


func test_no_failure_after_a_death() -> void:
	var convoy: Convoy = _make()
	Events.level_failed.emit(&"hearts")
	convoy.apply_damage(100, null)
	assert_signal_emit_count(Events, "level_failed", 1, "only the hearts failure")
	assert_signal_emitted_with_parameters(Events, "level_failed", [&"hearts"])
	assert_false(convoy.is_lost())


# --- Hull drawing ----------------------------------------------------------------------

func test_hull_outline_points_nose_up() -> void:
	var ship: ConvoyShip = SHIP_SCENE.instantiate() as ConvoyShip
	add_child_autofree(ship)
	assert_false("facing" in ship, "no facing property any more")
	var outline: PackedVector2Array = ship.outline()
	assert_eq(outline.size(), 5)
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	var bottom: int = 0
	for p: Vector2 in outline:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
		if is_equal_approx(p.y, 40.0):
			bottom += 1
	assert_eq(max_x - min_x, 160.0, "ship_width_px wide")
	assert_eq(max_y - min_y, 80.0, "ship_height_px tall")
	assert_eq(bottom, 2, "flat bottom")
	assert_true(outline.has(Vector2(0, -40)), "nose at the top centre")
	assert_true(outline.has(Vector2(-80, -20)) and outline.has(Vector2(80, -20)), "taper over the top quarter")


## Story 8.2: the hull is a Kenney cargo sprite turned nose-up, recoloured a
## dimmed coalition (dimmer than the ally fighter, so it reads as civilian),
## fitted uniformly inside ship_width_px x ship_height_px. Playtest 2026-10-14:
## only slightly dimmed (value 0.9), so its brightest parts still reach the
## glow threshold (in linear light; the project renders 2D in HDR) and bloom.
func test_hull_sprite_is_dim_coalition_cargo_fitted_inside_the_hull() -> void:
	var ship: ConvoyShip = SHIP_SCENE.instantiate() as ConvoyShip
	add_child_autofree(ship)
	var sprite: Sprite2D = ship.hull_sprite()
	assert_not_null(sprite, "the Sprite child")
	if sprite == null:
		return
	assert_eq(sprite.texture.resource_path, "res://assets/sprites/allies/convoy_cargo.png")
	var box: Vector2 = Vector2(Config.num("convoy.ship_width_px"), Config.num("convoy.ship_height_px"))
	var drawn: Vector2 = SpriteFit.drawn_size(sprite)
	assert_lte(drawn.x, box.x + 0.001, "inside the hull width")
	assert_lte(drawn.y, box.y + 0.001, "inside the hull height")
	assert_true(absf(drawn.x - box.x) < 1.0 or absf(drawn.y - box.y) < 1.0, "touches the box on one side (%s in %s)" % [drawn, box])
	assert_almost_eq(sprite.scale.x, sprite.scale.y, 0.0001, "uniform")
	assert_eq(sprite.rotation, 0.0, "the texture is already nose-up")
	assert_eq(sprite.self_modulate, Color.WHITE)
	assert_lt(SpriteProbe.hue_distance_deg(SpriteProbe.dominant_hue(sprite.texture), Color("#22E6FF").h), 8.0, "coalition hue")
	var fighter: Texture2D = load("res://assets/sprites/allies/ally_coalition.png") as Texture2D
	assert_lt(SpriteProbe.max_channel(sprite.texture), SpriteProbe.max_channel(fighter), "dimmer than the ally fighter")
	var top: float = SpriteProbe.max_channel(sprite.texture)
	var linear_top: float = Color(top, top, top).srgb_to_linear().r
	assert_gt(linear_top, Config.num("render.glow.hdr_threshold"), "bright enough to glow (linear %.3f)" % linear_top)


func test_ship_without_convoy_ignores_damage() -> void:
	var ship: ConvoyShip = SHIP_SCENE.instantiate() as ConvoyShip
	add_child_autofree(ship)
	ship.apply_damage(5, null)
	assert_signal_not_emitted(Events, "convoy_hp_changed")


# --- Enemy shots (Story 6.3, GDD #23) ----------------------------------------------------

func _fire_bullet_at(ship: ConvoyShip, params: Dictionary) -> EnemyBullet:
	var bullet: EnemyBullet = (load("res://entities/projectiles/enemy_bullet.tscn") as PackedScene).instantiate() as EnemyBullet
	var all: Dictionary = {"position": ship.global_position + Vector2(0, -150), "velocity": Vector2(0, 450), "damage": 3}
	all.merge(params, true)
	bullet.setup(all)
	add_child_autofree(bullet)
	return bullet


func test_aimed_enemy_bullet_costs_the_convoy_aimed_amount() -> void:
	var convoy: Convoy = _make()
	var bullet: EnemyBullet = _fire_bullet_at(convoy.ships()[Convoy.LEAD], {"targets_convoy": true})
	await wait_physics_frames(40)
	assert_eq(convoy.hp(), 100 - Config.int_("damage.convoy_aimed"), "aimed: 5, not the bullet's own damage")
	assert_eq(convoy.hp(), 95)
	assert_signal_emit_count(Events, "convoy_hp_changed", 2, "the start value and one hit")
	assert_true(not is_instance_valid(bullet) or bullet.is_queued_for_deletion(), "the bullet is spent")


func test_aimed_bullet_hitting_any_ship_costs_the_aimed_amount() -> void:
	var convoy: Convoy = _make()
	var ship: ConvoyShip = convoy.ships()[Convoy.FLANK_RIGHT]
	# From below, so FlankRight is the ship hit.
	var bullet: EnemyBullet = _fire_bullet_at(ship, {"targets_convoy": true,
		"position": ship.global_position + Vector2(0, 150), "velocity": Vector2(0, -450)})
	await wait_physics_frames(40)
	assert_eq(convoy.hp(), 95, "the flag alone decides the amount")
	assert_true(not is_instance_valid(bullet) or bullet.is_queued_for_deletion())


func test_stray_enemy_bullet_costs_the_convoy_stray_amount() -> void:
	var convoy: Convoy = _make()
	var bullet: EnemyBullet = _fire_bullet_at(convoy.ships()[Convoy.LEAD], {})
	await wait_physics_frames(40)
	assert_eq(convoy.hp(), 100 - Config.int_("damage.convoy_stray"), "stray: 2, not the bullet's own damage")
	assert_eq(convoy.hp(), 98)
	assert_signal_emit_count(Events, "convoy_hp_changed", 2, "the start value and one hit")
	assert_true(not is_instance_valid(bullet) or bullet.is_queued_for_deletion(), "the bullet is spent")


# --- Playtest pt7-g: the convoy blows up --------------------------------------------

## Steps the pending Feedback chain until it has run out (bounded).
func _run_chain() -> void:
	for i: int in ceili(Config.num("feedback.convoy_death_chain_s") / DT) + 10:
		Feedback.step_chain(DT)


func test_loss_blows_the_ships_up_in_order() -> void:
	var convoy: Convoy = _make()
	var lead: ConvoyShip = convoy.ships()[Convoy.LEAD]
	var left: ConvoyShip = convoy.ships()[Convoy.FLANK_LEFT]
	var right: ConvoyShip = convoy.ships()[Convoy.FLANK_RIGHT]
	convoy.apply_damage(100, null)
	assert_true(lead.is_destroyed(), "the lead blows up at once")
	assert_false(lead.visible, "and vanishes")
	assert_false(left.is_destroyed(), "the flanks follow")
	assert_eq(Feedback.chain_pending(), 2, "two more explosions queued")
	Feedback.step_chain(Config.num("feedback.convoy_death_chain_s") / 2.0 + 0.01)
	assert_true(left.is_destroyed(), "then the left flank")
	assert_false(right.is_destroyed())
	_run_chain()
	assert_true(right.is_destroyed(), "then the right flank")
	assert_eq(Feedback.chain_pending(), 0)


func test_death_positions_follow_the_death_order() -> void:
	var convoy: Convoy = _make()
	var positions: Array[Vector2] = convoy.death_positions()
	assert_eq(positions.size(), 3)
	for k: int in Convoy.DEATH_ORDER.size():
		assert_eq(positions[k], convoy.ships()[Convoy.DEATH_ORDER[k]].global_position)


func test_a_lost_convoy_stops_moving() -> void:
	var convoy: Convoy = _make()
	convoy.apply_damage(100, null)
	var left: float = convoy.left_x()
	var lead_pos: Vector2 = convoy.ships()[Convoy.LEAD].global_position
	convoy.step(1.0)
	assert_eq(convoy.left_x(), left, "it stays where it died")
	assert_eq(convoy.ships()[Convoy.LEAD].global_position, lead_pos)


func test_destroyed_ship_is_off_every_layer() -> void:
	var convoy: Convoy = _make()
	var ship: ConvoyShip = convoy.ships()[Convoy.LEAD]
	assert_ne(ship.collision_layer, 0, "hittable while alive")
	ship.destroy()
	ship.destroy()
	await wait_physics_frames(1)
	assert_eq(ship.collision_layer, 0, "shots pass through the wreck")
	assert_false(ship.monitorable)
	assert_false(ship.visible)


func test_no_chain_when_the_level_already_ended() -> void:
	var convoy: Convoy = _make()
	Events.level_failed.emit(&"hearts")
	convoy.apply_damage(100, null)
	assert_eq(Feedback.chain_pending(), 0, "no explosions for a convoy that never died")
	for ship: ConvoyShip in convoy.ships():
		assert_false(ship.is_destroyed())


## Review fix (pt7-g): the wreck stays solid until its last ship has blown up.
func test_is_wrecked_only_after_every_ship_is_destroyed() -> void:
	var convoy: Convoy = _make()
	assert_false(convoy.is_wrecked(), "intact")
	var ships: Array = convoy.ships()
	for i: int in ships.size():
		(ships[i] as ConvoyShip).destroy()
		assert_eq(convoy.is_wrecked(), i == ships.size() - 1, "wrecked only once all %d ships are gone" % ships.size())
