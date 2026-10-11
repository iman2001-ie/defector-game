extends GutTest
## Convoy + ConvoyShip (Story 6.1): the scene shape and layers, the triangle
## layout in the band, the ping-pong path (step_span, mirrored triangle), the
## shared HP pool and its loss (first outcome wins), the cached hull rects and
## the code-drawn hull. Driven through step() with physics off.

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
	assert_eq(Config.num("convoy.lead_offset_px"), 40.0)


func test_scene_shape() -> void:
	var convoy: Convoy = _make()
	assert_true(convoy.is_in_group(&"convoy"), "joins the convoy group")
	var names: Array[String] = []
	for child: Node in convoy.get_children():
		names.append(String(child.name))
	assert_eq(names, ["Lead", "FlankTop", "FlankBottom"] as Array[String])
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
	assert_eq(convoy.ships().size(), 3, "still the triangle")


# --- Layout --------------------------------------------------------------------------

func test_start_layout_left_edge_heading_right() -> void:
	var convoy: Convoy = _make()
	assert_eq(convoy.left_x(), 0.0)
	assert_eq(convoy.direction(), 1)
	assert_eq(convoy.span(), 360.0, "2 x 160 + 40")
	var ships: Array[ConvoyShip] = convoy.ships()
	assert_eq(ships[Convoy.LEAD].global_position, Vector2(280, 840), "lead ahead, band centre")
	assert_eq(ships[Convoy.FLANK_TOP].global_position, Vector2(80, 800))
	assert_eq(ships[Convoy.FLANK_BOTTOM].global_position, Vector2(80, 880))
	var group: Rect2 = _group_rect(convoy)
	assert_eq(group, Rect2(0, 760, 360, 160), "the group fills the band from x 0")
	for ship: ConvoyShip in ships:
		var r: Rect2 = _sprite_rect(ship)
		assert_true(Playfield.RECT.encloses(r), "%s fully on-screen" % ship.name)
		assert_true(r.position.y >= 760.0 and r.end.y <= 920.0, "%s inside y 760-920" % ship.name)
		assert_false(r.has_point(PLAYER_SPAWN), "%s clear of the player spawn" % ship.name)
		assert_eq(ship.facing, 1, "%s nose to the right" % ship.name)


func test_lead_gap_is_lead_offset() -> void:
	var convoy: Convoy = _make()
	var lead: Rect2 = _sprite_rect(convoy.ships()[Convoy.LEAD])
	var flank: Rect2 = _sprite_rect(convoy.ships()[Convoy.FLANK_TOP])
	assert_eq(lead.position.x - flank.end.x, 40.0, "40 px between the flank fronts and the lead's rear")


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
	var right: Array[Vector2] = Convoy.ship_centres(100.0, 1, 160.0, 80.0, 40.0, 760.0, 920.0)
	assert_eq(right, [Vector2(380, 840), Vector2(180, 800), Vector2(180, 880)] as Array[Vector2])
	var left: Array[Vector2] = Convoy.ship_centres(100.0, -1, 160.0, 80.0, 40.0, 760.0, 920.0)
	assert_eq(left, [Vector2(180, 840), Vector2(380, 800), Vector2(380, 880)] as Array[Vector2], "mirrored")
	assert_eq(Convoy.ship_centre(Convoy.LEAD, 0.0, 1, 160.0, 80.0, 40.0, 760.0, 920.0), Vector2(280, 840))


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
	assert_eq(Convoy.step_span(0.0, 1, 10.0, 360.0, 1920.0), Vector2(10, 1), "moving right")
	assert_eq(Convoy.step_span(1550.0, 1, 20.0, 360.0, 1920.0), Vector2(1560, -1), "clamped at the right edge and flipped")
	assert_eq(Convoy.step_span(1560.0, -1, 10.0, 360.0, 1920.0), Vector2(1550, -1), "heading back left")
	assert_eq(Convoy.step_span(5.0, -1, 20.0, 360.0, 1920.0), Vector2(0, 1), "clamped at the left edge and flipped")
	assert_eq(Convoy.step_span(0.0, 1, 0.0, 360.0, 1920.0), Vector2(0, 1), "starting at 0 heading right doesn't flip")
	assert_eq(Convoy.step_span(0.0, 1, 5000.0, 360.0, 1920.0), Vector2(1560, -1), "a huge step still clamps")


func test_right_edge_mirrors_the_triangle() -> void:
	var convoy: Convoy = _make()
	convoy.step((1560.0 - 0.0) / 40.0)
	assert_eq(convoy.left_x(), 1560.0)
	assert_eq(convoy.direction(), -1, "flipped at the right edge")
	var ships: Array[ConvoyShip] = convoy.ships()
	assert_eq(_group_rect(convoy).end.x, 1920.0, "right edge exactly on the screen edge")
	assert_lt(ships[Convoy.LEAD].global_position.x, ships[Convoy.FLANK_TOP].global_position.x, "lead now on the left, leading")
	for ship: ConvoyShip in ships:
		assert_eq(ship.facing, -1, "%s nose to the left" % ship.name)


func test_two_crossings_stay_on_screen_and_lead_leads() -> void:
	var convoy: Convoy = _make()
	var flips: int = 0
	var last_dir: int = convoy.direction()
	# 1560 px each way at 40 px/s is 39 s; run 90 s (two full crossings and more).
	for i: int in 90 * 60:
		convoy.step(DT)
		for ship: ConvoyShip in convoy.ships():
			var r: Rect2 = _sprite_rect(ship)
			if r.position.x < -0.001 or r.end.x > 1920.001:
				fail_test("%s left x 0-1920 at tick %d: %s" % [ship.name, i, r])
				return
		var lead_x: float = convoy.ships()[Convoy.LEAD].global_position.x
		var flank_x: float = convoy.ships()[Convoy.FLANK_TOP].global_position.x
		if (lead_x - flank_x) * float(convoy.direction()) <= 0.0:
			fail_test("lead not leading at tick %d" % i)
			return
		if convoy.direction() != last_dir:
			flips += 1
			last_dir = convoy.direction()
	assert_gte(flips, 2, "reversed at both edges")


# --- Hull rects ----------------------------------------------------------------------

func test_hull_rects_are_cached_and_follow_the_ships() -> void:
	var convoy: Convoy = _make()
	var rects: Array[Rect2] = convoy.hull_rects()
	assert_eq(rects.size(), 3)
	assert_eq(rects[Convoy.FLANK_TOP], Rect2(16, 768, 128, 64), "global hitbox rect")
	assert_eq(rects[Convoy.LEAD], convoy.ships()[Convoy.LEAD].hull_rect())
	convoy.step(1.0)
	assert_same(convoy.hull_rects(), rects, "the same cached array every tick")
	assert_eq(rects[Convoy.FLANK_TOP], Rect2(56, 768, 128, 64), "refreshed in place")


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
	convoy.ships()[Convoy.FLANK_BOTTOM].apply_damage(10, null)
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

func test_hull_outline_faces_its_facing() -> void:
	var ship: ConvoyShip = SHIP_SCENE.instantiate() as ConvoyShip
	add_child_autofree(ship)
	var outline: PackedVector2Array = ship.outline()
	assert_eq(outline.size(), 5)
	var min_x: float = INF
	var max_x: float = -INF
	var nose: Vector2 = Vector2.ZERO
	for p: Vector2 in outline:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		if is_zero_approx(p.y):
			nose = p
	assert_eq(max_x - min_x, 160.0, "ship_width_px wide")
	assert_eq(nose, Vector2(80, 0), "nose on the right")
	ship.facing = -1
	for p: Vector2 in ship.outline():
		if is_zero_approx(p.y):
			assert_eq(p, Vector2(-80, 0), "nose on the left")


func test_hull_colours_are_coalition_and_dim() -> void:
	assert_eq(ConvoyShip.OUTLINE_COLOR, Color("#22E6FF"), "bright coalition outline")
	var body: Color = ConvoyShip.BODY_COLOR
	assert_almost_eq(body.r, ConvoyShip.OUTLINE_COLOR.r, 0.002)
	assert_almost_eq(body.g, ConvoyShip.OUTLINE_COLOR.g, 0.002)
	assert_almost_eq(body.b, ConvoyShip.OUTLINE_COLOR.b, 0.002)
	assert_lt(body.a, 0.5, "dim body")


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
	var ship: ConvoyShip = convoy.ships()[Convoy.FLANK_BOTTOM]
	# From below, so FlankBottom (not FlankTop above it) is the ship hit.
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
