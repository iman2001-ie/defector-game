extends GutTest
## Bastion state machine (Story 2.7): entry, drift box, turret-glow telegraph,
## unaimed spread through a real Spawner, no-spawner path, death tier, contact
## immunity, tuning reads, pause. Driven through step(delta) with physics
## processing off, so every move is deterministic.

const BASTION_SCENE: PackedScene = preload("res://entities/enemies/bastion/bastion.tscn")
const WASP_SCENE: PackedScene = preload("res://entities/enemies/wasp/wasp.tscn")
const BASTION_SCRIPT_PATH: String = "res://entities/enemies/bastion/bastion.gd"
const DT: float = 1.0 / 60.0
const EPS: float = 0.001

var _lines: Array[String] = []
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


func _bastion_tuning() -> Dictionary:
	return (Config.tuning["enemies"] as Dictionary)["bastion"] as Dictionary


## A Bastion created without a Spawner (spawner stays null). A seed >= 0 seeds
## its rng before _ready, so the first drift target is deterministic too.
func _make(params: Dictionary, seed_value: int = -1) -> Bastion:
	var bastion: Bastion = BASTION_SCENE.instantiate() as Bastion
	if seed_value >= 0:
		bastion.rng.seed = seed_value
	bastion.setup(params)
	add_child_autofree(bastion)
	bastion.set_physics_process(false)
	return bastion


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


func _spawn(params: Dictionary) -> Bastion:
	var bastion: Bastion = _spawner.spawn_enemy(&"bastion", params) as Bastion
	assert_not_null(bastion, "spawned a Bastion")
	if bastion != null:
		bastion.set_physics_process(false)
	return bastion


## Steps until the Bastion reaches `target_state` or `max_s` elapses; returns seconds stepped.
func _step_until(bastion: Bastion, target_state: Bastion.State, max_s: float) -> float:
	var t: float = 0.0
	while bastion.state() != target_state and t < max_s:
		bastion.step(DT)
		t += DT
	return t


func _bullets() -> Array[Projectile]:
	var out: Array[Projectile] = []
	for child: Node in _projectiles.get_children():
		var p: Projectile = child as Projectile
		if p != null and not p.is_queued_for_deletion():
			out.append(p)
	return out


func _in_box(p: Vector2, box: Rect2) -> bool:
	return p.x >= box.position.x - EPS and p.x <= box.end.x + EPS \
		and p.y >= box.position.y - EPS and p.y <= box.end.y + EPS


## Degrees from straight down to `v` (positive = clockwise on screen).
func _deg_from_down(v: Vector2) -> float:
	return rad_to_deg(Vector2.DOWN.angle_to(v))


# --- Base stats ---------------------------------------------------------------

func test_hp_tier_and_scene() -> void:
	var bastion: Bastion = _make({"position": Vector2(960, 240)})
	assert_eq(bastion.type_id, &"bastion")
	assert_eq(bastion.hp, 40)
	assert_eq(bastion.tier, ImpactTier.LARGE)
	assert_eq(bastion.sprite_px, 160.0)
	assert_eq(bastion.collision_layer, CollisionLayers.ENEMIES)
	assert_eq(bastion.collision_mask, 0)
	assert_false(bastion.monitoring)
	var hull: Polygon2D = bastion.get_node_or_null("Hull") as Polygon2D
	assert_not_null(hull, "Hull silhouette")
	if hull != null:
		assert_eq(hull.color.to_html(false), "ff2bd6", "enemy colour")
	assert_eq(bastion.turret_count(), Config.int_("enemies.bastion.turrets"), "scene turrets match tuning")
	var t0: Marker2D = bastion.get_node_or_null("Turrets/Turret0") as Marker2D
	var t1: Marker2D = bastion.get_node_or_null("Turrets/Turret1") as Marker2D
	assert_not_null(t0)
	assert_not_null(t1)
	if t0 != null and t1 != null:
		assert_eq(t0.position, Vector2(-44, 40))
		assert_eq(t1.position, Vector2(44, 40))
		assert_false((t0.get_node("Glow") as CanvasItem).visible, "glow hidden at rest")
		assert_false((t1.get_node("Glow") as CanvasItem).visible, "glow hidden at rest")
	assert_false(bastion.is_glowing())
	assert_eq(_warns().size(), 0)


func test_hitbox_radius_from_tuning() -> void:
	var bastion: Bastion = _make({"position": Vector2(960, 240)})
	var hitbox: CollisionShape2D = bastion.get_node_or_null("Hitbox") as CollisionShape2D
	assert_not_null(hitbox)
	if hitbox == null:
		return
	var circle: CircleShape2D = hitbox.shape as CircleShape2D
	assert_not_null(circle, "CircleShape2D")
	if circle != null:
		assert_almost_eq(circle.radius, 160.0 / 2.0 * Config.num("enemies.bastion.hitbox_ratio"), 0.0001)


func test_drift_box_keeps_the_hull_inside_the_band() -> void:
	var bastion: Bastion = _make({"position": Vector2(960, 240)})
	var box: Rect2 = bastion.drift_box()
	assert_eq(box.position, Vector2(80, 160), "band_y.min + half, half")
	assert_eq(box.end, Vector2(1840, 320), "width - half, band_y.max - half")


# --- Entry --------------------------------------------------------------------

func test_top_entry_flies_to_the_slot_then_drifts() -> void:
	var bastion: Bastion = _make({"position": Vector2(960, 160), "slot": Vector2(960, 160), "entry": &"top"})
	assert_eq(bastion.global_position, Vector2(960, -80), "starts above the top edge")
	assert_eq(bastion.state(), Bastion.State.ENTER)
	assert_eq(bastion.formation_slot(), Vector2(960, 160))
	bastion.step(0.1)
	assert_almost_eq(bastion.global_position.y, -80.0 + 6.0, EPS, "60 px/s")
	assert_eq(bastion.global_position.x, 960.0)
	var t: float = _step_until(bastion, Bastion.State.DRIFT, 6.0)
	assert_eq(bastion.state(), Bastion.State.DRIFT)
	assert_almost_eq(t + 0.1, 240.0 / 60.0, DT * 1.5, "arrives after distance / drift speed")
	assert_eq(bastion.global_position, Vector2(960, 160))
	assert_true(_in_box(bastion.drift_target(), bastion.drift_box()), "first target picked in the box")
	assert_eq(_warns().size(), 0)


func test_side_entry_starts_on_the_nearer_side() -> void:
	var left: Bastion = _make({"position": Vector2(400, 200), "slot": Vector2(400, 200), "entry": &"sides"})
	assert_eq(left.global_position, Vector2(-80, 200))
	assert_eq(left.state(), Bastion.State.ENTER)
	var right: Bastion = _make({"position": Vector2(1500, 200), "slot": Vector2(1500, 200), "entry": &"sides"})
	assert_eq(right.global_position, Vector2(2000, 200))
	assert_eq(right.state(), Bastion.State.ENTER)
	_step_until(left, Bastion.State.DRIFT, 10.0)
	assert_eq(left.global_position, Vector2(400, 200), "arrives on its slot")
	assert_eq(_warns().size(), 0)


func test_slot_outside_the_drift_box_is_clamped() -> void:
	var low: Bastion = _make({"position": Vector2(960, 400), "slot": Vector2(960, 400), "entry": &"top"})
	assert_eq(low.formation_slot(), Vector2(960, 320))
	assert_eq(low.global_position, Vector2(960, -80), "enters above the clamped slot")
	assert_eq(_warns().size(), 1, "one WARN")
	var edge: Bastion = _make({"position": Vector2(10, 200), "slot": Vector2(10, 200), "entry": &"top"})
	assert_eq(edge.formation_slot(), Vector2(80, 200))
	assert_eq(_warns().size(), 2, "one WARN each")


func test_unknown_entry_warns_and_uses_top() -> void:
	var bastion: Bastion = _make({"position": Vector2(960, 200), "slot": Vector2(960, 200), "entry": &"spiral"})
	assert_eq(bastion.global_position, Vector2(960, -80))
	assert_eq(bastion.state(), Bastion.State.ENTER)
	assert_eq(_warns().size(), 1, "one WARN")
	if _warns().size() == 1:
		assert_string_contains(_warns()[0], "spiral")


func test_without_a_slot_drifts_from_its_position() -> void:
	var bastion: Bastion = _make({"position": Vector2(500, 600)})
	assert_eq(bastion.state(), Bastion.State.DRIFT)
	assert_eq(bastion.global_position, Vector2(500, 600), "no clamp")
	assert_true(_in_box(bastion.drift_target(), bastion.drift_box()), "first target picked in _ready")
	assert_eq(_warns().size(), 0, "no WARN")
	var before: Vector2 = bastion.global_position
	bastion.step(0.5)
	assert_almost_eq(bastion.global_position.distance_to(before), 30.0, EPS, "60 px/s toward its target")


# --- Drift --------------------------------------------------------------------

func test_drift_stays_in_the_box_at_drift_speed() -> void:
	var bastion: Bastion = _make({"position": Vector2(960, 160), "slot": Vector2(960, 160), "entry": &"top"}, 7)
	_step_until(bastion, Bastion.State.DRIFT, 6.0)
	assert_eq(bastion.state(), Bastion.State.DRIFT)
	var box: Rect2 = bastion.drift_box()
	var targets: int = 0
	var last_target: Vector2 = bastion.drift_target()
	var max_step: float = 0.0
	var outside: int = 0
	var t: float = 0.0
	while t < 60.0:
		var before: Vector2 = bastion.global_position
		bastion.step(DT)
		t += DT
		max_step = maxf(max_step, bastion.global_position.distance_to(before))
		if not _in_box(bastion.global_position, box):
			outside += 1
		if bastion.drift_target() != last_target:
			assert_true(_in_box(bastion.drift_target(), box), "new target in the box")
			last_target = bastion.drift_target()
			targets += 1
	assert_eq(outside, 0, "always inside the drift box")
	assert_lte(max_step, 60.0 * DT + EPS, "<= 60 px/s per step")
	assert_gte(targets, 3, "reaches several targets in 60 s")


func test_drift_continues_while_telegraphing() -> void:
	var bastion: Bastion = _make({"position": Vector2(960, 240)}, 3)
	_step_until(bastion, Bastion.State.TELEGRAPH, 3.0)
	assert_eq(bastion.state(), Bastion.State.TELEGRAPH)
	var before: Vector2 = bastion.global_position
	bastion.step(DT)
	assert_ne(bastion.global_position, before, "still drifting while telegraphing")


func test_band_shorter_than_the_hull_uses_the_band_centre() -> void:
	var band: Dictionary = _bastion_tuning()["band_y"] as Dictionary
	band["min"] = 100.0
	band["max"] = 200.0
	var bastion: Bastion = _make({"position": Vector2(960, 150), "slot": Vector2(960, 300), "entry": &"top"}, 5)
	var box: Rect2 = bastion.drift_box()
	assert_eq(box.position.y, 150.0, "y min = band centre")
	assert_eq(box.end.y, 150.0, "y max = band centre")
	assert_eq(bastion.formation_slot(), Vector2(960, 150), "slot clamped to the centre")
	_step_until(bastion, Bastion.State.DRIFT, 6.0)
	for i: int in 600:
		bastion.step(DT)
		assert_almost_eq(bastion.global_position.y, 150.0, EPS, "y fixed on the band centre")


# --- Fire cycle ---------------------------------------------------------------

func test_telegraph_then_spread_through_a_real_spawner() -> void:
	_make_world()
	var bastion: Bastion = _spawn({"position": Vector2(960, 240)})
	if bastion == null:
		return
	assert_eq(bastion.spawner, _spawner, "Spawner injected itself")
	assert_eq(bastion.state(), Bastion.State.DRIFT)
	var t: float = _step_until(bastion, Bastion.State.TELEGRAPH, 4.0)
	assert_almost_eq(t, 2.0, DT * 1.5, "fire_interval_s - telegraph_s of drifting")
	assert_true(bastion.is_glowing(), "every turret glows")
	var e: float = Config.num("enemies.bastion.turret_glow_energy")
	for turret: Node in bastion.get_node("Turrets").get_children():
		var glow: CanvasItem = turret.get_node("Glow") as CanvasItem
		assert_true(glow.visible, "%s glows" % turret.name)
		assert_eq(glow.self_modulate, Color(e, e, e), "HDR glow")
	var tele: float = 0.0
	var origins: Array[Vector2] = []
	while bastion.state() == Bastion.State.TELEGRAPH and tele < 2.0:
		assert_eq(_bullets().size(), 0, "no shot before telegraph_s")
		assert_true(bastion.is_glowing(), "glows through the telegraph")
		bastion.step(DT)
		tele += DT
		# Shots spawn from where the turrets were after this step's drift move.
		origins.clear()
		for turret: Node in bastion.get_node("Turrets").get_children():
			origins.append((turret as Node2D).global_position)
	assert_almost_eq(tele, 0.5, DT * 1.5, "telegraph_s")
	assert_eq(bastion.state(), Bastion.State.DRIFT, "back to DRIFT")
	assert_false(bastion.is_glowing(), "glows hidden")
	var bullets: Array[Projectile] = _bullets()
	assert_eq(bullets.size(), 6, "3 bullets per turret")
	if bullets.size() != 6:
		return
	for origin: Vector2 in origins:
		var angles: Array[float] = []
		for bullet: Projectile in bullets:
			bullet.set_physics_process(false)
			if bullet.global_position.distance_to(origin) < EPS:
				assert_true(bullet is EnemyBullet, "an EnemyBullet")
				assert_almost_eq(bullet.velocity.length(), 350.0, EPS, "350 px/s")
				assert_eq(bullet.damage, Config.int_("damage.bullet_hearts"), "damage.bullet_hearts")
				angles.append(_deg_from_down(bullet.velocity))
		angles.sort()
		assert_eq(angles.size(), 3, "3 bullets from turret at %s" % origin)
		if angles.size() == 3:
			assert_almost_eq(angles[0], -15.0, EPS, "-15 deg")
			assert_almost_eq(angles[1], 0.0, EPS, "straight down")
			assert_almost_eq(angles[2], 15.0, EPS, "+15 deg")


func test_spread_is_not_aimed_at_the_player() -> void:
	_make_world()
	var player: Node2D = Node2D.new()
	player.add_to_group(&"player")
	add_child_autofree(player)
	player.global_position = Vector2(100, 900)
	var bastion: Bastion = _spawn({"position": Vector2(960, 240)})
	if bastion == null:
		return
	_step_until(bastion, Bastion.State.TELEGRAPH, 4.0)
	_step_until(bastion, Bastion.State.DRIFT, 2.0)
	var bullets: Array[Projectile] = _bullets()
	assert_eq(bullets.size(), 6)
	var centre: int = 0
	for bullet: Projectile in bullets:
		bullet.set_physics_process(false)
		if absf(_deg_from_down(bullet.velocity)) < EPS:
			centre += 1
	assert_eq(centre, 2, "each spread is centred straight down")


## DW-40 (decision #38): fire_interval_s is the full volley period and includes
## the telegraph, so volleys are fire_interval_s apart, the turrets glowing for
## the last telegraph_s of each period.
func test_cycle_repeats_every_full_period() -> void:
	_make_world()
	var bastion: Bastion = _spawn({"position": Vector2(960, 240)})
	if bastion == null:
		return
	var t: float = 0.0
	var volleys: Array[float] = []
	var glow_starts: Array[float] = []
	var was_glowing: bool = false
	# 3 volleys by ~8.0 s (at ~2.5, ~5.0, ~7.5 s); the 4th lands at ~10.0 s.
	while t < 3.0 * 2.5 + 0.5:
		var before: int = _bullets().size()
		bastion.step(DT)
		t += DT
		if bastion.is_glowing() and not was_glowing:
			glow_starts.append(t)
		was_glowing = bastion.is_glowing()
		if _bullets().size() > before:
			volleys.append(t)
	assert_eq(_bullets().size(), 18, "one 6-bullet volley per 2.5 s, none extra")
	assert_eq(volleys.size(), 3, "three separate volleys")
	if volleys.size() != 3:
		return
	assert_almost_eq(volleys[0], 2.5, DT * 2.5, "first volley fire_interval_s after DRIFT begins")
	assert_almost_eq(volleys[1] - volleys[0], 2.5, DT * 2.5, "volley to volley = fire_interval_s")
	assert_almost_eq(volleys[2] - volleys[1], 2.5, DT * 2.5, "volley to volley = fire_interval_s")
	assert_eq(glow_starts.size(), 3, "one telegraph per volley")
	if glow_starts.size() == 3:
		for i: int in 3:
			assert_almost_eq(volleys[i] - glow_starts[i], 0.5, DT * 1.5, "glows for the last telegraph_s")
	# The drift timer restarts after each volley: DRIFT -> TELEGRAPH takes
	# fire_interval_s - telegraph_s again.
	_step_until(bastion, Bastion.State.TELEGRAPH, 4.0)
	_step_until(bastion, Bastion.State.DRIFT, 2.0)
	assert_eq(bastion.state(), Bastion.State.DRIFT, "back in DRIFT after a volley")
	assert_almost_eq(_step_until(bastion, Bastion.State.TELEGRAPH, 4.0), 2.0, DT * 1.5,
		"fire_interval_s - telegraph_s after the volley")


## A telegraph at least as long as the interval clamps the drift time to 0:
## the Bastion leaves DRIFT on the next tick and the period is ~telegraph_s.
func test_telegraph_longer_than_interval_clamps_drift_to_zero() -> void:
	var tuning: Dictionary = _bastion_tuning()
	tuning["fire_interval_s"] = 0.2
	tuning["telegraph_s"] = 0.5
	_make_world()
	var bastion: Bastion = _spawn({"position": Vector2(960, 240)})
	if bastion == null:
		return
	assert_eq(bastion.state(), Bastion.State.DRIFT)
	bastion.step(DT)
	assert_eq(bastion.state(), Bastion.State.TELEGRAPH, "leaves DRIFT on the next tick")
	var t: float = 0.0
	var volleys: Array[float] = []
	while t < 2.0:
		var before: int = _bullets().size()
		bastion.step(DT)
		t += DT
		if _bullets().size() > before:
			volleys.append(t)
	assert_gte(volleys.size(), 3, "keeps firing")
	if volleys.size() >= 2:
		assert_almost_eq(volleys[1] - volleys[0], 0.5, DT * 2.5, "period ~telegraph_s")
	assert_eq(_warns().size(), 0, "no warning")


func test_no_fire_while_entering() -> void:
	_make_world()
	var bastion: Bastion = _spawn({"position": Vector2(960, 320), "slot": Vector2(960, 320), "entry": &"top"})
	if bastion == null:
		return
	var t: float = 0.0
	while bastion.state() == Bastion.State.ENTER and t < 10.0:
		bastion.step(DT)
		t += DT
		assert_false(bastion.is_glowing())
	assert_gt(t, 2.5, "the entry takes longer than fire_interval_s")
	assert_eq(_projectiles.get_child_count(), 0, "never fires while entering")
	var drift: float = _step_until(bastion, Bastion.State.TELEGRAPH, 4.0)
	assert_almost_eq(drift, 2.0, DT * 1.5, "timer starts when DRIFT begins")


func test_no_spawner_runs_the_cycle_without_firing() -> void:
	Log.debug_enabled = true
	var bastion: Bastion = _make({"position": Vector2(960, 240)})
	assert_null(bastion.spawner)
	for cycle: int in 2:
		_step_until(bastion, Bastion.State.TELEGRAPH, 4.0)
		assert_eq(bastion.state(), Bastion.State.TELEGRAPH, "cycle %d telegraphs" % cycle)
		_step_until(bastion, Bastion.State.DRIFT, 2.0)
		assert_eq(bastion.state(), Bastion.State.DRIFT, "cycle %d continues" % cycle)
	assert_eq(get_tree().get_nodes_in_group(&"projectiles").size(), 0, "no bullet")
	assert_eq(_logged("[DEBUG][spawn]").size(), 1, "DEBUG once per Bastion")
	assert_eq(_warns().size(), 0)


func test_turret_count_mismatch_warns_and_uses_the_scene() -> void:
	_bastion_tuning()["turrets"] = 3
	_make_world()
	var bastion: Bastion = _spawn({"position": Vector2(960, 240)})
	if bastion == null:
		return
	assert_eq(_warns().size(), 1, "one WARN")
	assert_eq(bastion.turret_count(), 2, "the scene's turrets")
	_step_until(bastion, Bastion.State.TELEGRAPH, 4.0)
	_step_until(bastion, Bastion.State.DRIFT, 2.0)
	assert_eq(_bullets().size(), 6, "two spreads")
	assert_eq(_warns().size(), 1, "still one WARN")


# --- Death and contact --------------------------------------------------------

func test_death_resolves_once_with_the_large_tier() -> void:
	watch_signals(Events)
	var bastion: Bastion = _make({"position": Vector2(960, 240)})
	watch_signals(bastion)
	bastion.apply_damage(39, null)
	assert_false(bastion.is_dead(), "alive at 1 HP")
	assert_false(Feedback.is_hit_stopped())
	bastion.apply_damage(1, null)
	assert_true(bastion.is_dead())
	assert_signal_emit_count(bastion, "resolved", 1)
	assert_signal_emit_count(Events, "enemy_killed", 1)
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"bastion", Vector2(960, 240), false])
	assert_true(Feedback.is_hit_stopped(), "Large tier: hit-stop running")
	bastion.apply_damage(5, null)
	assert_signal_emit_count(bastion, "resolved", 1, "resolves once")


func test_contact_does_not_destroy_the_bastion() -> void:
	watch_signals(Events)
	var bastion: Bastion = _make({"position": Vector2(960, 240)})
	watch_signals(bastion)
	bastion.destroy_by_contact()
	assert_false(bastion.is_dead(), "alive")
	assert_eq(bastion.hp, 40, "HP untouched")
	assert_false(bastion.is_queued_for_deletion())
	assert_signal_not_emitted(bastion, "resolved")
	assert_signal_not_emitted(Events, "enemy_killed")
	var wasp: Enemy = WASP_SCENE.instantiate() as Enemy
	wasp.setup({"position": Vector2(400, 300)})
	add_child_autofree(wasp)
	wasp.set_physics_process(false)
	wasp.destroy_by_contact()
	assert_true(wasp.is_dead(), "a Wasp still dies by contact")


# --- Tuning -------------------------------------------------------------------

func test_numbers_come_from_tuning() -> void:
	_make_world()
	var tuning: Dictionary = _bastion_tuning()
	tuning["drift_speed_px_s"] = 120.0
	tuning["fire_interval_s"] = 1.0
	tuning["telegraph_s"] = 0.4
	tuning["bullet_speed_px_s"] = 200.0
	tuning["spread_bullets"] = 5
	tuning["spread_deg"] = 30.0
	tuning["turret_glow_energy"] = 3.0
	tuning["hp"] = 12
	(tuning["band_y"] as Dictionary)["min"] = 60.0
	(tuning["band_y"] as Dictionary)["max"] = 420.0
	(Config.tuning["damage"] as Dictionary)["bullet_hearts"] = 2
	var entering: Bastion = _make({"position": Vector2(960, 140), "slot": Vector2(960, 140), "entry": &"top"})
	assert_eq(entering.hp, 12, "hp")
	assert_eq(entering.drift_box(), Rect2(80, 140, 1760, 200), "band_y")
	entering.step(0.1)
	assert_almost_eq(entering.global_position.y, -80.0 + 12.0, EPS, "drift_speed_px_s drives the entry")
	var bastion: Bastion = _spawn({"position": Vector2(960, 240)})
	if bastion == null:
		return
	var t: float = _step_until(bastion, Bastion.State.TELEGRAPH, 3.0)
	assert_almost_eq(t, 0.6, DT * 1.5, "fire_interval_s - telegraph_s")
	var glow: CanvasItem = bastion.get_node("Turrets/Turret0/Glow") as CanvasItem
	assert_eq(glow.self_modulate, Color(3.0, 3.0, 3.0), "turret_glow_energy")
	var tele: float = _step_until(bastion, Bastion.State.DRIFT, 2.0)
	assert_almost_eq(tele, 0.4, DT * 1.5, "telegraph_s")
	var bullets: Array[Projectile] = _bullets()
	assert_eq(bullets.size(), 10, "spread_bullets per turret")
	var angles: Array[float] = []
	for bullet: Projectile in bullets:
		bullet.set_physics_process(false)
		assert_almost_eq(bullet.velocity.length(), 200.0, EPS, "bullet_speed_px_s")
		assert_eq(bullet.damage, 2, "damage.bullet_hearts")
		angles.append(snappedf(_deg_from_down(bullet.velocity), 0.001))
	angles.sort()
	assert_eq(angles, [-30.0, -30.0, -15.0, -15.0, 0.0, 0.0, 15.0, 15.0, 30.0, 30.0] as Array[float], "spread_deg")


func test_one_bullet_spread_fires_straight_down() -> void:
	_bastion_tuning()["spread_bullets"] = 1
	_make_world()
	var bastion: Bastion = _spawn({"position": Vector2(960, 240)})
	if bastion == null:
		return
	_step_until(bastion, Bastion.State.TELEGRAPH, 4.0)
	_step_until(bastion, Bastion.State.DRIFT, 2.0)
	var bullets: Array[Projectile] = _bullets()
	assert_eq(bullets.size(), 2, "one per turret")
	for bullet: Projectile in bullets:
		bullet.set_physics_process(false)
		assert_almost_eq(bullet.velocity, Vector2(0, 350), Vector2(EPS, EPS), "0 deg")


func test_state_is_assigned_only_in_enter_state() -> void:
	var source: String = FileAccess.get_file_as_string(BASTION_SCRIPT_PATH)
	var assignments: RegEx = RegEx.create_from_string("(?<!\\w)_state\\s*=(?!=)")
	assert_eq(assignments.search_all(source).size(), 1, "exactly one `_state =`")
	var enter: int = source.find("func _enter_state(")
	var hit: RegExMatch = assignments.search(source)
	assert_true(enter >= 0 and hit != null and hit.get_start() > enter, "inside _enter_state")


# --- Pause --------------------------------------------------------------------

func test_paused_tree_freezes_the_bastion() -> void:
	_make_world()
	var bastion: Bastion = _spawner.spawn_enemy(&"bastion", {"position": Vector2(960, 240)}) as Bastion
	assert_not_null(bastion)
	if bastion == null:
		return
	assert_eq(bastion.process_mode, Node.PROCESS_MODE_INHERIT)
	PauseArbiter.push(&"menu")
	var before: Vector2 = bastion.global_position
	assert_false(bastion.can_process(), "Bastion paused with the tree")
	await get_tree().create_timer(0.2, true, true).timeout
	assert_eq(bastion.global_position, before, "Bastion frozen")
	PauseArbiter.pop(&"menu")
	await wait_physics_frames(10)
	assert_ne(bastion.global_position, before, "Bastion moves again")
