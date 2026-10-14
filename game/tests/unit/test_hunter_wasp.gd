extends GutTest
## Hunter Wasp (Story 2.8): stats, capped-turn chase at constant speed, player
## caching and fallback, entries, death and contact, tuning reads, pause.
## Driven through step(delta) with physics processing off.

const SpriteProbe: GDScript = preload("res://tests/fixtures/sprite_probe.gd")
const HUNTER_SCENE: PackedScene = preload("res://entities/enemies/hunter_wasp/hunter_wasp.tscn")
const DT: float = 1.0 / 60.0
const ORANGE: Color = Color("#FF8A1F")

var _lines: Array[String] = []


func before_each() -> void:
	_lines.clear()
	Log.sink = _capture


func after_each() -> void:
	Log.sink = Callable()
	Config.load_data()
	PauseArbiter.clear()
	Feedback.reset()


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _warns() -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.begins_with("[WARN][spawn]"):
			out.append(line)
	return out


func _make(params: Dictionary, manual: bool = true) -> HunterWasp:
	var hunter: HunterWasp = HUNTER_SCENE.instantiate() as HunterWasp
	hunter.setup(params)
	add_child_autofree(hunter)
	if manual:
		hunter.set_physics_process(false)
	watch_signals(hunter)
	return hunter


func _make_player(pos: Vector2) -> Node2D:
	var player: Node2D = Node2D.new()
	player.add_to_group(&"player")
	add_child_autofree(player)
	player.global_position = pos
	return player


func _angle_deg(a: Vector2, b: Vector2) -> float:
	return rad_to_deg(absf(a.angle_to(b)))


# --- Stats --------------------------------------------------------------------

func test_stats_tier_hitbox_and_orange_hull() -> void:
	var hunter: HunterWasp = _make({"position": Vector2(960, 300)})
	assert_eq(hunter.type_id, &"hunter_wasp")
	assert_eq(hunter.hp, 3)
	assert_eq(hunter.tier, ImpactTier.SMALL)
	var node: Node = hunter
	assert_false(node is Wasp, "not a Wasp: the dive clock never picks it")
	var hitbox: CollisionShape2D = hunter.get_node_or_null("Hitbox") as CollisionShape2D
	assert_not_null(hitbox)
	if hitbox != null:
		var circle: CircleShape2D = hitbox.shape as CircleShape2D
		assert_not_null(circle)
		if circle != null:
			assert_almost_eq(circle.radius, 32.0 * Config.num("enemies.hunter_wasp.hitbox_ratio"), 0.0001)
	var hull: Sprite2D = hunter.get_node_or_null("Hull") as Sprite2D
	assert_not_null(hull, "Hull sprite")
	if hull != null:
		assert_eq(hull.texture.resource_path, "res://assets/sprites/enemies/enemy_hunter_wasp.png", "the Wasp hull in orange #FF8A1F")
		assert_almost_eq(SpriteProbe.longest_side(hull), hunter.sprite_px, 1.0, "longer side = sprite_px")
		assert_lt(SpriteProbe.hue_distance_deg(SpriteProbe.dominant_hue(hull.texture), ORANGE.h), 8.0, "in the Hunter orange hue")
		assert_eq(hull.self_modulate, Color.WHITE, "modulate stays white")
	assert_eq(hunter.collision_layer, 4, "enemies layer")
	assert_eq(hunter.collision_mask, 0)
	assert_false(hunter.monitoring)


# --- Chase --------------------------------------------------------------------

func test_straight_chase_moves_300_px_per_second_toward_the_player() -> void:
	_make_player(Vector2(960, 900))
	var hunter: HunterWasp = _make({"position": Vector2(960, 100)})
	assert_eq(hunter.heading(), Vector2.DOWN)
	for i: int in 30:
		var before: Vector2 = hunter.global_position
		hunter.step(DT)
		assert_almost_eq(hunter.global_position.y - before.y, 300.0 * DT, 0.0001)
		assert_almost_eq(hunter.global_position.x, 960.0, 0.0001)
	assert_almost_eq(hunter.rotation, 0.0, 0.0001, "nose (down) follows the heading")


func test_turn_rate_caps_the_heading_change() -> void:
	_make_player(Vector2(960, 100))
	var hunter: HunterWasp = _make({"position": Vector2(960, 900)})
	var prev: Vector2 = hunter.heading()
	for i: int in 60:
		hunter.step(DT)
		assert_lte(_angle_deg(prev, hunter.heading()), 1.5 + 0.001, "<= 1.5 deg per 1/60 s")
		prev = hunter.heading()
	assert_almost_eq(_angle_deg(Vector2.DOWN, hunter.heading()), 90.0, 0.5, "90 deg after 1.0 s")
	assert_almost_eq(hunter.rotation, hunter.heading().angle() - PI / 2.0, 0.0001, "hull follows the heading")


func test_catches_up_with_a_static_player_at_constant_speed() -> void:
	var player: Node2D = _make_player(Vector2(1400, 700))
	var hunter: HunterWasp = _make({"position": Vector2(960, 100)})
	var closest: float = INF
	for i: int in 600:
		var before: Vector2 = hunter.global_position
		hunter.step(DT)
		assert_almost_eq(before.distance_to(hunter.global_position), 300.0 * DT, 0.0001, "constant speed")
		closest = minf(closest, hunter.global_position.distance_to(player.global_position))
	assert_lt(closest, 40.0, "comes within 40 px within 10 s")


func test_steers_toward_the_moved_player() -> void:
	var player: Node2D = _make_player(Vector2(1600, 500))
	var hunter: HunterWasp = _make({"position": Vector2(960, 500)})
	hunter.step(DT)
	assert_gt(hunter.heading().x, 0.0, "turning right toward the player")
	player.global_position = Vector2(300, 500)
	assert_eq(hunter.chase_target(), Vector2(300, 500), "cached node, not a snapshot")
	for i: int in 10:
		hunter.step(DT)
	assert_lt(hunter.heading().x, 0.0, "now turning left toward the new position")


func test_no_player_steers_toward_the_playfield_centre() -> void:
	var hunter: HunterWasp = _make({"position": Vector2(200, 540)})
	assert_eq(hunter.chase_target(), Playfield.SIZE / 2.0)
	hunter.step(DT)
	assert_gt(hunter.heading().x, 0.0, "turning toward the centre")
	assert_eq(_lines.size(), 0, "no log lines")


func test_freed_player_falls_back_and_a_new_one_is_found() -> void:
	var player: Node2D = _make_player(Vector2(1400, 700))
	var hunter: HunterWasp = _make({"position": Vector2(960, 100)})
	hunter.step(DT)
	assert_eq(hunter.chase_target(), Vector2(1400, 700))
	player.free()
	hunter.step(DT)
	assert_eq(hunter.chase_target(), Playfield.SIZE / 2.0, "falls back to the centre")
	var fresh: Node2D = _make_player(Vector2(300, 800))
	var t: float = 0.0
	while hunter.chase_target() != fresh.global_position and t < 1.0:
		hunter.step(DT)
		t += DT
	assert_eq(hunter.chase_target(), Vector2(300, 800), "found the new player")
	assert_lte(t, 0.5 + DT * 1.5, "within 0.5 s")


func test_no_log_lines_while_chasing() -> void:
	_make_player(Vector2(1400, 700))
	var hunter: HunterWasp = _make({"position": Vector2(960, 100)})
	_lines.clear()
	for i: int in 300:
		hunter.step(DT)
	assert_eq(_lines, [] as Array[String])


# --- Entries ------------------------------------------------------------------

func test_sides_entry_starts_off_screen_on_the_nearer_side() -> void:
	var left: HunterWasp = _make({"position": Vector2(400, 200), "slot": Vector2(400, 200), "entry": &"sides"})
	assert_eq(left.global_position, Vector2(-32, 200))
	assert_eq(left.heading(), Vector2.RIGHT)
	assert_almost_eq(left.rotation, -PI / 2.0, 0.0001, "nose points right")
	var right: HunterWasp = _make({"position": Vector2(1500, 200), "slot": Vector2(1500, 200), "entry": &"sides"})
	assert_eq(right.global_position, Vector2(1952, 200))
	assert_eq(right.heading(), Vector2.LEFT)
	assert_eq(_warns().size(), 0)


func test_top_entry_starts_above_the_slot_heading_down() -> void:
	var hunter: HunterWasp = _make({"position": Vector2(960, 160), "slot": Vector2(960, 160), "entry": &"top"})
	assert_eq(hunter.global_position, Vector2(960, -32))
	assert_eq(hunter.heading(), Vector2.DOWN)
	assert_eq(_warns().size(), 0)


func test_unknown_entry_warns_and_uses_top() -> void:
	var hunter: HunterWasp = _make({"position": Vector2(960, 160), "slot": Vector2(960, 160), "entry": &"spiral"})
	assert_eq(hunter.global_position, Vector2(960, -32))
	assert_eq(hunter.heading(), Vector2.DOWN)
	assert_eq(_warns(), ["[WARN][spawn] hunter_wasp entry 'spiral' is unknown; using top"] as Array[String])


func test_without_a_slot_it_starts_at_its_spawn_position_heading_down() -> void:
	var hunter: HunterWasp = _make({"position": Vector2(700, 300)})
	assert_eq(hunter.global_position, Vector2(700, 300))
	assert_eq(hunter.heading(), Vector2.DOWN)


# --- Death and contact --------------------------------------------------------

func test_three_damage_kills_once() -> void:
	watch_signals(Events)
	var hunter: HunterWasp = _make({"position": Vector2(960, 300)})
	hunter.apply_damage(2, null)
	assert_false(hunter.is_dead(), "alive at 1 HP")
	hunter.apply_damage(1, null)
	assert_true(hunter.is_dead())
	assert_signal_emit_count(hunter, "resolved", 1)
	assert_signal_emit_count(Events, "enemy_killed", 1)
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"hunter_wasp", Vector2(960, 300), false])
	hunter.apply_damage(3, null)
	assert_signal_emit_count(hunter, "resolved", 1, "resolves once")


func test_contact_destroys_it_once() -> void:
	watch_signals(Events)
	var hunter: HunterWasp = _make({"position": Vector2(960, 300)})
	hunter.destroy_by_contact()
	assert_true(hunter.is_dead(), "small tier dies by contact")
	hunter.destroy_by_contact()
	assert_signal_emit_count(hunter, "resolved", 1)
	assert_signal_emit_count(Events, "enemy_killed", 1)


# --- Tuning reads -------------------------------------------------------------

func test_speed_and_turn_rate_come_from_tuning() -> void:
	var section: Dictionary = (Config.tuning["enemies"] as Dictionary)["hunter_wasp"]
	section["chase_speed_px_s"] = 120.0
	section["turn_rate_deg_s"] = 180.0
	_make_player(Vector2(960, 100))
	var hunter: HunterWasp = _make({"position": Vector2(960, 900)})
	var before: Vector2 = hunter.global_position
	hunter.step(DT)
	assert_almost_eq(before.distance_to(hunter.global_position), 2.0, 0.0001, "120 px/s")
	assert_almost_eq(_angle_deg(Vector2.DOWN, hunter.heading()), 3.0, 0.001, "180 deg/s")


# --- Pause --------------------------------------------------------------------

func test_paused_tree_freezes_the_hunter() -> void:
	var hunter: HunterWasp = _make({"position": Vector2(960, 300)}, false)
	assert_eq(hunter.process_mode, Node.PROCESS_MODE_INHERIT)
	PauseArbiter.push(&"menu")
	var before: Vector2 = hunter.global_position
	assert_false(hunter.can_process(), "paused with the tree")
	await get_tree().create_timer(0.2, true, true).timeout
	assert_eq(hunter.global_position, before, "no movement while paused")
	PauseArbiter.pop(&"menu")
	await wait_physics_frames(3)
	assert_ne(hunter.global_position, before, "moves again after resume")
