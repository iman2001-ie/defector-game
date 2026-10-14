extends GutTest
## Needle state machine (Story 2.6): anchoring entry, tracking line, red lock,
## sniper bolt through a real Spawner, cycle cadence, reposition, no-spawner
## path, tuning reads, pause. Driven through step(delta) with physics
## processing off, so every move is deterministic. Playtest pt7-e: each bolt
## that leaves plays the needle_fire cue (the lock is silent).

const SpriteProbe: GDScript = preload("res://tests/fixtures/sprite_probe.gd")
const NEEDLE_SCENE: PackedScene = preload("res://entities/enemies/needle/needle.tscn")
const NEEDLE_SCRIPT_PATH: String = "res://entities/enemies/needle/needle.gd"
const DT: float = 1.0 / 60.0
const ENEMY_COLOR: Color = Color("#FF2BD6")
const DANGER_COLOR: Color = Color("#FF1F4B")

var _lines: Array[String] = []
var _player: Node2D = null
var _world: Node2D = null
var _projectiles: Node2D = null
var _spawner: Spawner = null
var _debug_was: bool = true


func before_each() -> void:
	_lines.clear()
	_debug_was = Log.debug_enabled
	Log.sink = _capture


func after_each() -> void:
	Log.sink = Callable()
	Log.debug_enabled = _debug_was
	Config.load_data()
	PauseArbiter.clear()
	Feedback.reset()
	_player = null
	_world = null
	_projectiles = null
	_spawner = null


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _logged(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.begins_with(prefix):
			out.append(line)
	return out


func _warns() -> Array[String]:
	return _logged("[WARN][spawn]")


## A Needle created without a Spawner (spawner stays null).
func _make(params: Dictionary, manual: bool = true) -> Needle:
	var needle: Needle = NEEDLE_SCENE.instantiate() as Needle
	needle.setup(params)
	add_child_autofree(needle)
	if manual:
		needle.set_physics_process(false)
	return needle


## A test world (Projectiles + Enemies + Asteroids) with a real Spawner.
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


func _spawn(params: Dictionary) -> Needle:
	var needle: Needle = _spawner.spawn_enemy(&"needle", params) as Needle
	assert_not_null(needle, "spawned a Needle")
	if needle != null:
		needle.set_physics_process(false)
	return needle


func _make_player(pos: Vector2) -> Node2D:
	_player = Node2D.new()
	_player.add_to_group(&"player")
	add_child_autofree(_player)
	_player.global_position = pos
	return _player


## Steps until the Needle reaches `target_state` or `max_s` elapses; returns seconds stepped.
func _step_until(needle: Needle, target_state: Needle.State, max_s: float) -> float:
	var t: float = 0.0
	while needle.state() != target_state and t < max_s:
		needle.step(DT)
		t += DT
	return t


func _bolts() -> Array[Projectile]:
	var out: Array[Projectile] = []
	for child: Node in _projectiles.get_children():
		var p: Projectile = child as Projectile
		if p != null and not p.is_queued_for_deletion():
			p.set_physics_process(false)
			out.append(p)
	return out


func _line(needle: Needle) -> Line2D:
	return needle.get_node("TelegraphLine") as Line2D


func _muzzle(needle: Needle) -> Node2D:
	return needle.get_node("Muzzle") as Node2D


## The line starts at the muzzle and reaches across the playfield along `dir`.
func _assert_line_along(needle: Needle, dir: Vector2, label: String) -> void:
	var line: Line2D = _line(needle)
	var start: Vector2 = _muzzle(needle).position
	assert_almost_eq(line.get_point_position(0), start, Vector2(0.001, 0.001), label + ": starts at the muzzle")
	var end: Vector2 = start + dir * Playfield.SIZE.length()
	assert_almost_eq(line.get_point_position(1), end, Vector2(0.01, 0.01), label + ": reaches across the playfield")


func _assert_color_near(got: Color, want: Color, label: String) -> void:
	var near: bool = absf(got.r - want.r) < 0.002 and absf(got.g - want.g) < 0.002 \
		and absf(got.b - want.b) < 0.002 and absf(got.a - want.a) < 0.002
	assert_true(near, "%s: %s ~ %s" % [label, got, want])


# --- Base stats ---------------------------------------------------------------

func test_hp_tier_and_scene() -> void:
	var needle: Needle = _make({"position": Vector2(960, 160)})
	assert_eq(needle.type_id, &"needle")
	assert_eq(needle.hp, Config.int_("enemies.needle.hp"))
	assert_eq(needle.tier, ImpactTier.MEDIUM)
	assert_eq(needle.sprite_px, 80.0)
	assert_eq(needle.collision_layer, CollisionLayers.ENEMIES)
	assert_eq(needle.collision_mask, 0)
	assert_false(needle.monitoring)
	var hull: Sprite2D = needle.get_node_or_null("Hull") as Sprite2D
	assert_not_null(hull, "Hull sprite")
	if hull != null:
		assert_eq(hull.texture.resource_path, "res://assets/sprites/enemies/enemy_needle.png", "the Needle hull")
		assert_almost_eq(SpriteProbe.longest_side(hull), needle.sprite_px, 1.0, "longer side = sprite_px")
		assert_lt(SpriteProbe.hue_distance_deg(SpriteProbe.dominant_hue(hull.texture), ENEMY_COLOR.h), 8.0, "in the enemy hue")
		assert_eq(hull.self_modulate, Color.WHITE, "modulate stays white")
		var drawn: Vector2 = SpriteFit.drawn_size(hull)
		assert_gt(drawn.y, drawn.x, "long and thin")
	var muzzle: Marker2D = needle.get_node_or_null("Muzzle") as Marker2D
	assert_not_null(muzzle, "Muzzle marker")
	if muzzle != null:
		assert_eq(muzzle.position, Vector2(0, 40), "at the nose")
		assert_almost_eq(Vector2.RIGHT.rotated(muzzle.rotation).dot(Vector2.DOWN), 1.0, 0.001, "points down")
	var line: Line2D = needle.get_node_or_null("TelegraphLine") as Line2D
	assert_not_null(line, "TelegraphLine")
	if line != null:
		assert_eq(line.get_point_count(), 2)
	assert_false(needle.line_visible(), "line hidden at rest")
	_assert_color_near(needle.track_color, Color(ENEMY_COLOR, 0.5), "track_color")
	_assert_color_near(needle.lock_color, DANGER_COLOR, "lock_color")


func test_needle_hitbox_radius_from_tuning() -> void:
	var needle: Needle = _make({"position": Vector2(960, 160)})
	var hitbox: CollisionShape2D = needle.get_node_or_null("Hitbox") as CollisionShape2D
	assert_not_null(hitbox)
	if hitbox == null:
		return
	var circle: CircleShape2D = hitbox.shape as CircleShape2D
	assert_not_null(circle, "CircleShape2D")
	if circle != null:
		assert_almost_eq(circle.radius, 80.0 / 2.0 * Config.num("enemies.needle.hitbox_ratio"), 0.0001, "80 / 2 * hitbox_ratio")


# --- Entry and anchor -----------------------------------------------------------

func test_top_entry_anchors_at_the_top_edge() -> void:
	var needle: Needle = _make({"position": Vector2(960, 280), "slot": Vector2(960, 280), "entry": &"top"})
	assert_eq(needle.global_position, Vector2(960, -40), "starts above the top edge")
	assert_eq(needle.state(), Needle.State.ANCHORING)
	assert_eq(needle.anchor(), Vector2(960, 160), "slot y ignored: anchor_y_px")
	assert_false(needle.line_visible())
	needle.step(0.1)
	assert_almost_eq(needle.global_position.y, -40.0 + 40.0, 0.001, "400 px/s")
	assert_eq(needle.global_position.x, 960.0)
	assert_false(needle.line_visible(), "line hidden while anchoring")
	var t: float = _step_until(needle, Needle.State.TRACKING, 3.0)
	assert_eq(needle.state(), Needle.State.TRACKING)
	assert_almost_eq(t + 0.1, 200.0 / 400.0, DT * 1.5, "arrives after distance / reposition speed")
	assert_eq(needle.global_position, Vector2(960, 160))
	assert_eq(_warns().size(), 0)


func test_side_entry_starts_on_the_nearer_side() -> void:
	var left: Needle = _make({"position": Vector2(400, 280), "slot": Vector2(400, 280), "entry": &"sides"})
	assert_eq(left.global_position, Vector2(-40, 160), "level with anchor_y_px, not the slot y")
	assert_eq(left.anchor(), Vector2(400, 160))
	assert_eq(left.state(), Needle.State.ANCHORING)
	var right: Needle = _make({"position": Vector2(1500, 280), "slot": Vector2(1500, 280), "entry": &"sides"})
	assert_eq(right.global_position, Vector2(1960, 160), "level with anchor_y_px, not the slot y")
	assert_eq(right.anchor(), Vector2(1500, 160))
	_step_until(left, Needle.State.TRACKING, 4.0)
	assert_eq(left.global_position, Vector2(400, 160), "arrives on its anchor")
	_step_until(right, Needle.State.TRACKING, 4.0)
	assert_eq(right.global_position, Vector2(1500, 160))
	assert_eq(_warns().size(), 0)


func test_unknown_entry_and_off_screen_slot_warn() -> void:
	var needle: Needle = _make({"position": Vector2(5, 160), "slot": Vector2(5, 160), "entry": &"spiral"})
	assert_eq(needle.anchor(), Vector2(40, 160), "x clamped to sprite_px / 2")
	assert_eq(needle.global_position, Vector2(40, -40), "top entry")
	assert_eq(needle.state(), Needle.State.ANCHORING)
	var warns: Array[String] = _warns()
	assert_eq(warns.size(), 2, "one WARN each")
	if warns.size() == 2:
		assert_string_contains(warns[0] + warns[1], "spiral")
		assert_string_contains(warns[0] + warns[1], "clamped")


func test_slot_past_the_right_edge_is_clamped() -> void:
	var needle: Needle = _make({"position": Vector2(1915, 160), "slot": Vector2(1915, 160), "entry": &"top"})
	assert_eq(needle.anchor(), Vector2(1880, 160))
	assert_eq(_warns().size(), 1)


func test_without_a_slot_the_spawn_position_is_the_anchor() -> void:
	var needle: Needle = _make({"position": Vector2(500, 300)})
	assert_eq(needle.global_position, Vector2(500, 300), "no teleport")
	assert_eq(needle.anchor(), Vector2(500, 300))
	assert_eq(needle.state(), Needle.State.ANCHORING)
	needle.step(DT)
	assert_eq(needle.state(), Needle.State.TRACKING, "already on its anchor")
	assert_eq(needle.global_position, Vector2(500, 300))


# --- Track and lock -----------------------------------------------------------

func test_tracking_line_follows_the_player() -> void:
	var player: Node2D = _make_player(Vector2(300, 900))
	var needle: Needle = _make({"position": Vector2(960, 160)})
	needle.step(DT)
	assert_eq(needle.state(), Needle.State.TRACKING)
	assert_true(needle.line_visible(), "line visible")
	_assert_color_near(needle.line_color(), Color(ENEMY_COLOR, 0.5), "enemy colour at half alpha")
	assert_eq(_line(needle).width, 2.0)
	var origin: Vector2 = _muzzle(needle).global_position
	var dir: Vector2 = (player.global_position - origin).normalized()
	assert_almost_eq(needle.line_direction(), dir, Vector2(0.0001, 0.0001), "aimed on entry")
	_assert_line_along(needle, dir, "on entry")
	for pos: Vector2 in [Vector2(400, 880), Vector2(1500, 700), Vector2(960, 1000)]:
		player.global_position = pos
		needle.step(DT)
		assert_eq(needle.state(), Needle.State.TRACKING)
		dir = (pos - origin).normalized()
		assert_almost_eq(needle.line_direction(), dir, Vector2(0.0001, 0.0001), "follows the player to %s" % pos)
		_assert_line_along(needle, dir, "player at %s" % pos)


func test_no_player_points_the_line_straight_down() -> void:
	var needle: Needle = _make({"position": Vector2(960, 160)})
	needle.step(DT)
	needle.step(DT)
	assert_eq(needle.state(), Needle.State.TRACKING)
	assert_eq(needle.line_direction(), Vector2.DOWN)
	_assert_line_along(needle, Vector2.DOWN, "no player")


func test_player_on_the_muzzle_points_the_line_straight_down() -> void:
	var needle: Needle = _make({"position": Vector2(960, 160)})
	_make_player(_muzzle(needle).global_position)
	needle.step(DT)
	needle.step(DT)
	assert_eq(needle.line_direction(), Vector2.DOWN)


func test_lock_freezes_the_line_red_then_fires_along_it() -> void:
	_make_world()
	var player: Node2D = _make_player(Vector2(300, 900))
	var needle: Needle = _spawn({"position": Vector2(960, 160)})
	if needle == null:
		return
	assert_eq(needle.spawner, _spawner, "Spawner injected itself")
	needle.step(DT)
	var track: float = _step_until(needle, Needle.State.LOCKED, 3.0)
	assert_almost_eq(track, Config.num("enemies.needle.track_s"), DT * 1.5, "track_s")
	assert_true(needle.line_visible(), "line visible while locked")
	_assert_color_near(needle.line_color(), DANGER_COLOR, "danger red, opaque")
	assert_eq(_line(needle).width, 4.0)
	var origin: Vector2 = _muzzle(needle).global_position
	var locked: Vector2 = needle.line_direction()
	assert_almost_eq(locked, (Vector2(300, 900) - origin).normalized(), Vector2(0.0001, 0.0001))
	var end_before: Vector2 = _line(needle).get_point_position(1)
	player.global_position = Vector2(1800, 600)
	var lock: float = 0.0
	while needle.state() == Needle.State.LOCKED and lock < 1.0:
		assert_eq(_bolts().size(), 0, "no shot before lock_s")
		needle.step(DT)
		lock += DT
		if needle.state() == Needle.State.LOCKED:
			assert_eq(needle.line_direction(), locked, "frozen")
			assert_eq(_line(needle).get_point_position(1), end_before, "line not re-aimed")
	assert_almost_eq(lock, Config.num("enemies.needle.lock_s"), DT * 1.5, "lock_s")
	assert_eq(needle.state(), Needle.State.COOLDOWN)
	assert_false(needle.line_visible(), "line hidden in cooldown")
	var bolts: Array[Projectile] = _bolts()
	assert_eq(bolts.size(), 1, "one needle_bolt")
	if bolts.size() != 1:
		return
	var bolt: Projectile = bolts[0]
	assert_true(bolt is NeedleBolt, "a NeedleBolt")
	assert_almost_eq(bolt.global_position, origin, Vector2(0.001, 0.001), "spawned at Muzzle")
	assert_almost_eq(bolt.velocity.length(), Config.num("enemies.needle.bolt_speed_px_s"), 0.05, "bolt_speed_px_s")
	assert_almost_eq(bolt.velocity.normalized().dot(locked), 1.0, 0.000001, "along the locked line")
	assert_eq(bolt.damage, Config.int_("damage.bullet_hearts"), "damage.bullet_hearts")


func test_cycle_cadence_and_reposition() -> void:
	_make_world()
	_make_player(Vector2(300, 900))
	var needle: Needle = _spawn({"position": Vector2(960, 160)})
	if needle == null:
		return
	needle.rng.seed = 7
	var period: float = Config.num("enemies.needle.fire_interval_s")
	var fire_at: float = Config.num("enemies.needle.track_s") + Config.num("enemies.needle.lock_s")
	var anchored_for: float = Config.num("enemies.needle.reposition_interval_s")
	needle.step(DT)
	assert_eq(needle.state(), Needle.State.TRACKING, "anchored")
	var shots: Array[float] = []
	var t: float = 0.0
	var seen: int = 0
	while needle.state() != Needle.State.ANCHORING and t < anchored_for + period + 1.0:
		needle.step(DT)
		t += DT
		var n: int = _bolts().size()
		if n > seen:
			shots.append(t)
			seen = n
	# Each state change can run up to one step over, so cycle k may drift by
	# up to 3 * k steps from the ideal k * fire_interval_s.
	assert_gte(shots.size(), 1, "at least one shot per anchor")
	if shots.size() >= 1:
		assert_almost_eq(shots[0], fire_at, DT * 2.5, "first shot at track + lock")
	for k: int in range(1, shots.size()):
		assert_almost_eq(shots[k] - shots[k - 1], period, DT * 3.5, "next cycle starts fire_interval_s later")
	assert_eq(needle.state(), Needle.State.ANCHORING, "repositions")
	assert_gte(t, anchored_for - DT, "not before reposition_interval_s anchored")
	if shots.size() >= 1:
		# It moves only from COOLDOWN: after the last shot, before another track.
		assert_between(t - shots.back(), 0.0, period - fire_at + DT * 1.5, "repositions in the cooldown after the last shot")
		assert_lt(anchored_for - shots.back(), period, "no cycle was skipped before the reposition")
	assert_eq(needle.anchor().y, Config.num("enemies.needle.anchor_y_px"), "stays on the top edge")
	assert_gte(absf(needle.anchor().x - 960.0), Config.num("enemies.needle.reposition_min_distance_px"), "at least reposition_min_distance_px away")
	assert_between(needle.anchor().x, 40.0, 1880.0, "on screen")
	assert_false(needle.line_visible())
	var travel: float = _step_until(needle, Needle.State.TRACKING, 5.0)
	assert_almost_eq(travel, absf(needle.anchor().x - 960.0) / Config.num("enemies.needle.reposition_speed_px_s"), DT * 1.5, "flies at reposition_speed_px_s")
	assert_eq(needle.global_position, needle.anchor())


func test_seeded_reposition_stays_in_bounds_and_far_enough() -> void:
	(Config.tuning["enemies"] as Dictionary)["needle"]["reposition_interval_s"] = 0.0
	for x: float in [40.0, 300.0, 960.0, 1700.0, 1880.0]:
		for seed_value: int in 12:
			var needle: Needle = _make({"position": Vector2(x, 160)})
			needle.rng.seed = seed_value
			needle.step(DT)
			_step_until(needle, Needle.State.COOLDOWN, 3.0)
			needle.step(DT)
			assert_eq(needle.state(), Needle.State.ANCHORING, "reposition due on the first cooldown")
			var a: Vector2 = needle.anchor()
			assert_between(a.x, 40.0, 1880.0, "x %.0f seed %d in bounds" % [x, seed_value])
			assert_gte(absf(a.x - x), 320.0, "x %.0f seed %d far enough" % [x, seed_value])
			assert_eq(a.y, 160.0)


func test_reposition_without_a_far_enough_x_uses_the_full_range() -> void:
	var needle_tuning: Dictionary = (Config.tuning["enemies"] as Dictionary)["needle"] as Dictionary
	needle_tuning["reposition_interval_s"] = 0.0
	needle_tuning["reposition_min_distance_px"] = 5000.0
	var needle: Needle = _make({"position": Vector2(960, 160)})
	needle.rng.seed = 3
	needle.step(DT)
	_step_until(needle, Needle.State.COOLDOWN, 3.0)
	needle.step(DT)
	assert_eq(needle.state(), Needle.State.ANCHORING)
	assert_between(needle.anchor().x, 40.0, 1880.0)


func test_reposition_never_interrupts_a_track_or_lock() -> void:
	(Config.tuning["enemies"] as Dictionary)["needle"]["reposition_interval_s"] = 0.5
	var needle: Needle = _make({"position": Vector2(960, 160)})
	needle.step(DT)
	var t: float = 0.0
	while needle.state() != Needle.State.ANCHORING and t < 3.0:
		assert_ne(needle.state(), Needle.State.ANCHORING)
		needle.step(DT)
		t += DT
	var fire_at: float = Config.num("enemies.needle.track_s") + Config.num("enemies.needle.lock_s")
	assert_almost_eq(t, fire_at, DT * 2.5, "waits for the cycle to reach COOLDOWN")


func test_no_spawner_runs_the_cycle_without_firing() -> void:
	Log.debug_enabled = true
	_make_player(Vector2(960, 900))
	var needle: Needle = _make({"position": Vector2(700, 160)})
	assert_null(needle.spawner)
	needle.step(DT)
	for cycle: int in 2:
		_step_until(needle, Needle.State.LOCKED, 3.0)
		assert_eq(needle.state(), Needle.State.LOCKED, "cycle %d locks" % cycle)
		_step_until(needle, Needle.State.COOLDOWN, 1.0)
		assert_eq(needle.state(), Needle.State.COOLDOWN, "cycle %d continues" % cycle)
		_step_until(needle, Needle.State.TRACKING, 3.0)
	assert_eq(get_tree().get_nodes_in_group(&"projectiles").size(), 0, "no bolt")
	assert_eq(_logged("[DEBUG][spawn]").size(), 1, "DEBUG once per Needle")
	assert_eq(_warns().size(), 0)


# --- Tuning -------------------------------------------------------------------

func test_numbers_come_from_tuning() -> void:
	_make_world()
	var needle_tuning: Dictionary = (Config.tuning["enemies"] as Dictionary)["needle"] as Dictionary
	needle_tuning["anchor_y_px"] = 200.0
	needle_tuning["reposition_speed_px_s"] = 200.0
	needle_tuning["track_s"] = 0.6
	needle_tuning["lock_s"] = 0.4
	needle_tuning["fire_interval_s"] = 2.0
	needle_tuning["reposition_interval_s"] = 3.0
	needle_tuning["reposition_min_distance_px"] = 900.0
	needle_tuning["bolt_speed_px_s"] = 1000.0
	(Config.tuning["damage"] as Dictionary)["bullet_hearts"] = 2
	var needle: Needle = _spawn({"position": Vector2(400, 280), "slot": Vector2(400, 280), "entry": &"top"})
	if needle == null:
		return
	needle.rng.seed = 11
	assert_eq(needle.anchor(), Vector2(400, 200), "anchor_y_px")
	needle.step(0.1)
	assert_almost_eq(needle.global_position.y, -40.0 + 20.0, 0.001, "reposition_speed_px_s drives the entry")
	_step_until(needle, Needle.State.TRACKING, 3.0)
	var track: float = _step_until(needle, Needle.State.LOCKED, 3.0)
	assert_almost_eq(track, 0.6, DT * 1.5, "track_s")
	var lock: float = _step_until(needle, Needle.State.COOLDOWN, 3.0)
	assert_almost_eq(lock, 0.4, DT * 1.5, "lock_s")
	var bolts: Array[Projectile] = _bolts()
	assert_eq(bolts.size(), 1)
	if bolts.size() == 1:
		assert_almost_eq(bolts[0].velocity.length(), 1000.0, 0.001, "bolt_speed_px_s")
		assert_eq(bolts[0].damage, 2, "damage.bullet_hearts")
	var cool: float = _step_until(needle, Needle.State.TRACKING, 3.0)
	assert_almost_eq(cool, 1.0, DT * 1.5, "cooldown = fire_interval_s - track_s - lock_s")
	var t: float = _step_until(needle, Needle.State.ANCHORING, 5.0)
	assert_almost_eq(t, 1.0, DT * 3.5, "reposition_interval_s (3 s anchored, second cooldown)")
	assert_gte(absf(needle.anchor().x - 400.0), 900.0, "reposition_min_distance_px")
	assert_eq(needle.anchor().y, 200.0)


func test_cooldown_is_never_negative() -> void:
	(Config.tuning["enemies"] as Dictionary)["needle"]["fire_interval_s"] = 1.0
	var needle: Needle = _make({"position": Vector2(960, 160)})
	needle.step(DT)
	_step_until(needle, Needle.State.COOLDOWN, 3.0)
	needle.step(DT)
	assert_eq(needle.state(), Needle.State.TRACKING, "zero cooldown")


func test_state_is_assigned_only_in_enter_state() -> void:
	var source: String = FileAccess.get_file_as_string(NEEDLE_SCRIPT_PATH)
	var assignments: RegEx = RegEx.create_from_string("(?<!\\w)_state\\s*=(?!=)")
	assert_eq(assignments.search_all(source).size(), 1, "exactly one `_state =`")
	var enter: int = source.find("func _enter_state(")
	var hit: RegExMatch = assignments.search(source)
	assert_true(enter >= 0 and hit != null and hit.get_start() > enter, "inside _enter_state")


# --- Pause --------------------------------------------------------------------

func test_paused_tree_freezes_the_needle_and_its_bolts() -> void:
	_make_world()
	var needle: Needle = _spawner.spawn_enemy(&"needle",
		{"position": Vector2(960, 160), "slot": Vector2(960, 160), "entry": &"top"}) as Needle
	var bolt: Projectile = _spawner.spawn_projectile(&"needle_bolt",
		{"position": Vector2(960, 300), "velocity": Vector2(0, 1600), "damage": 1})
	assert_not_null(needle)
	assert_not_null(bolt)
	if needle == null or bolt == null:
		return
	assert_eq(needle.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_eq(bolt.process_mode, Node.PROCESS_MODE_INHERIT)
	PauseArbiter.push(&"menu")
	var needle_before: Vector2 = needle.global_position
	var bolt_before: Vector2 = bolt.global_position
	assert_false(needle.can_process(), "Needle paused with the tree")
	assert_false(bolt.can_process(), "bolt paused with the tree")
	await get_tree().create_timer(0.2, true, true).timeout
	assert_eq(needle.global_position, needle_before, "Needle frozen")
	assert_eq(bolt.global_position, bolt_before, "bolt frozen")
	PauseArbiter.pop(&"menu")
	await wait_physics_frames(3)
	assert_gt(needle.global_position.y, needle_before.y, "Needle moves again")
	assert_gt(bolt.global_position.y, bolt_before.y, "bolt moves again")


## Playtest 2026-10-13: a level that moves its formation rows passes
## row_shift_y, and the Needle's anchor row moves with them.
func test_row_shift_moves_the_anchor_row() -> void:
	var needle: Needle = _make({"position": Vector2(960, 200), "slot": Vector2(960, 200), "entry": &"top", "row_shift_y": 40.0})
	assert_eq(needle.anchor(), Vector2(960, Config.num("enemies.needle.anchor_y_px") + 40.0), "anchor_y_px + row_shift_y")
	var plain: Needle = _make({"position": Vector2(960, 200), "slot": Vector2(960, 200), "entry": &"top", "row_shift_y": "bad"})
	assert_eq(plain.anchor().y, Config.num("enemies.needle.anchor_y_px"), "a non-number shift is ignored")


# --- Playtest pt7-e: fire cue ---------------------------------------------------

## The lock is silent; every bolt that leaves plays needle_fire once, on that
## step, at enemies.needle.fire_sfx_volume_db. No spawner or a held fire spawns
## no bolt, so it plays nothing.
func test_each_fired_bolt_plays_needle_fire_once() -> void:
	for mode: String in ["no_spawner", "spawner", "held"]:
		if mode != "no_spawner":
			_make_world()
			_spawner.hold_enemy_fire = mode == "held"
		_make_player(Vector2(500, 900))
		var needle: Needle = _make({"position": Vector2(700, 160)}) if mode == "no_spawner" else _spawn({"position": Vector2(960, 160)})
		assert_not_null(needle, "a Needle (%s)" % mode)
		if needle == null:
			continue
		var fires: int = 0
		var cues: int = 0
		var t: float = 0.0
		var cycle_s: float = Config.num("enemies.needle.fire_interval_s")
		while t < cycle_s * 3.0:
			var before_state: Needle.State = needle.state()
			var before_serial: int = Audio._next_serial
			needle.step(DT)
			t += DT
			var fired: bool = before_state == Needle.State.LOCKED and needle.state() != Needle.State.LOCKED
			var newest: AudioStreamPlayer = Audio.newest_player()
			var played: bool = Audio._next_serial > before_serial and newest != null and newest.stream == Audio.SFX[&"needle_fire"]
			if fired:
				fires += 1
			if played:
				cues += 1
				assert_true(fired, "needle_fire only on the fire step (%s)" % mode)
				assert_almost_eq(newest.volume_db, Config.num("enemies.needle.fire_sfx_volume_db"), 0.0001, "fire_sfx_volume_db")
		assert_gte(fires, 2, "at least two shots (%s)" % mode)
		assert_eq(cues, fires if mode == "spawner" else 0, "one needle_fire per bolt that leaves (%s)" % mode)
	assert_eq(_logged("[WARN][audio]"), [] as Array[String], "needle_fire is registered")
