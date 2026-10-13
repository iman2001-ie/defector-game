extends GutTest
## Lancer state machine (Story 2.5): entry, strafe, muzzle-glow telegraph, aimed
## shot through a real Spawner, no-spawner path, tuning reads, pause, the convoy
## aim roll and ship pick (Story 6.3). Driven through step(delta) with physics
## processing off, so every move is deterministic.

const LANCER_SCENE: PackedScene = preload("res://entities/enemies/lancer/lancer.tscn")
const LANCER_SCRIPT_PATH: String = "res://entities/enemies/lancer/lancer.gd"
const CONVOY_SCENE: PackedScene = preload("res://entities/allies/convoy.tscn")
const DT: float = 1.0 / 60.0

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


## A Lancer created without a Spawner (spawner stays null).
func _make(params: Dictionary, manual: bool = true) -> Lancer:
	var lancer: Lancer = LANCER_SCENE.instantiate() as Lancer
	lancer.setup(params)
	add_child_autofree(lancer)
	if manual:
		lancer.set_physics_process(false)
	return lancer


## A test world (Projectiles + Enemies) with a real Spawner.
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


func _spawn(params: Dictionary) -> Lancer:
	var lancer: Lancer = _spawner.spawn_enemy(&"lancer", params) as Lancer
	assert_not_null(lancer, "spawned a Lancer")
	if lancer != null:
		lancer.set_physics_process(false)
	return lancer


func _make_player(pos: Vector2) -> Node2D:
	_player = Node2D.new()
	_player.add_to_group(&"player")
	add_child_autofree(_player)
	_player.global_position = pos
	return _player


## Steps until the Lancer reaches `target_state` or `max_s` elapses; returns seconds stepped.
func _step_until(lancer: Lancer, target_state: Lancer.State, max_s: float) -> float:
	var t: float = 0.0
	while lancer.state() != target_state and t < max_s:
		lancer.step(DT)
		t += DT
	return t


func _bullets() -> Array[Projectile]:
	var out: Array[Projectile] = []
	for child: Node in _projectiles.get_children():
		var p: Projectile = child as Projectile
		if p != null and not p.is_queued_for_deletion():
			out.append(p)
	return out


# --- Base stats ---------------------------------------------------------------

func test_hp_and_tier() -> void:
	var lancer: Lancer = _make({"position": Vector2(960, 160)})
	assert_eq(lancer.type_id, &"lancer")
	assert_eq(lancer.hp, 8)
	assert_eq(lancer.tier, ImpactTier.MEDIUM)
	assert_eq(lancer.sprite_px, 96.0)
	assert_eq(lancer.collision_layer, CollisionLayers.ENEMIES)
	assert_not_null(lancer.get_node_or_null("Hull") as Polygon2D, "Hull silhouette")
	var muzzle: Marker2D = lancer.get_node_or_null("Muzzle") as Marker2D
	assert_not_null(muzzle, "Muzzle marker")
	if muzzle != null:
		assert_gt(muzzle.position.y, 0.0, "at the nose (below the centre)")
		assert_almost_eq(Vector2.RIGHT.rotated(muzzle.rotation).dot(Vector2.DOWN), 1.0, 0.001, "points down")
	assert_false(lancer.is_glowing(), "glow hidden at rest")


func test_lancer_hitbox_radius_from_tuning() -> void:
	var lancer: Lancer = _make({"position": Vector2(960, 160)})
	var hitbox: CollisionShape2D = lancer.get_node_or_null("Hitbox") as CollisionShape2D
	assert_not_null(hitbox)
	if hitbox == null:
		return
	var circle: CircleShape2D = hitbox.shape as CircleShape2D
	assert_not_null(circle, "CircleShape2D")
	if circle != null:
		assert_almost_eq(circle.radius, 96.0 / 2.0 * Config.num("enemies.lancer.hitbox_ratio"), 0.0001, "96 / 2 * hitbox_ratio")


# --- Entry --------------------------------------------------------------------

func test_top_entry_flies_to_the_slot_then_strafes() -> void:
	var lancer: Lancer = _make({"position": Vector2(960, 160), "slot": Vector2(960, 160), "entry": &"top"})
	assert_eq(lancer.global_position, Vector2(960, -48), "starts above the top edge")
	assert_eq(lancer.state(), Lancer.State.ENTER)
	assert_eq(lancer.formation_slot(), Vector2(960, 160))
	lancer.step(0.1)
	assert_almost_eq(lancer.global_position.y, -48.0 + 20.0, 0.001, "200 px/s")
	assert_eq(lancer.global_position.x, 960.0)
	var t: float = _step_until(lancer, Lancer.State.STRAFE, 3.0)
	assert_eq(lancer.state(), Lancer.State.STRAFE)
	assert_almost_eq(t + 0.1, 208.0 / 200.0, DT * 1.5, "arrives after distance / strafe speed")
	assert_eq(lancer.global_position, Vector2(960, 160))
	assert_eq(lancer.strafe_dir(), 1.0, "slot.x <= width / 2 strafes +x first")
	assert_eq(_warns().size(), 0)


func test_side_entry_starts_on_the_nearer_side() -> void:
	var left: Lancer = _make({"position": Vector2(400, 160), "slot": Vector2(400, 160), "entry": &"sides"})
	assert_eq(left.global_position, Vector2(-48, 160))
	assert_eq(left.state(), Lancer.State.ENTER)
	var right: Lancer = _make({"position": Vector2(1200, 160), "slot": Vector2(1200, 160), "entry": &"sides"})
	assert_eq(right.global_position, Vector2(1968, 160))
	assert_eq(right.strafe_dir(), -1.0, "right of centre strafes -x first")
	_step_until(left, Lancer.State.STRAFE, 4.0)
	assert_eq(left.global_position, Vector2(400, 160), "arrives on its slot")
	assert_eq(_warns().size(), 0)


func test_unknown_entry_warns_and_uses_top() -> void:
	var lancer: Lancer = _make({"position": Vector2(960, 160), "slot": Vector2(960, 160), "entry": &"spiral"})
	assert_eq(lancer.global_position, Vector2(960, -48))
	assert_eq(lancer.state(), Lancer.State.ENTER)
	assert_eq(_warns().size(), 1, "one WARN")
	if _warns().size() == 1:
		assert_string_contains(_warns()[0], "spiral")


func test_slot_below_the_zone_is_clamped() -> void:
	var lancer: Lancer = _make({"position": Vector2(960, 520), "slot": Vector2(960, 520), "entry": &"top"})
	assert_eq(lancer.formation_slot(), Vector2(960, 378))
	assert_eq(_warns().size(), 1, "one WARN")
	_step_until(lancer, Lancer.State.STRAFE, 4.0)
	assert_eq(lancer.global_position, Vector2(960, 378), "holds y 378")
	for i: int in 30:
		lancer.step(DT)
	assert_eq(lancer.global_position.y, 378.0, "y never changes")


func test_without_a_slot_strafes_from_its_position() -> void:
	var lancer: Lancer = _make({"position": Vector2(500, 300)})
	assert_eq(lancer.state(), Lancer.State.STRAFE)
	assert_eq(lancer.global_position, Vector2(500, 300))
	assert_eq(lancer.strafe_dir(), 1.0)
	lancer.step(0.1)
	assert_almost_eq(lancer.global_position.x, 520.0, 0.001)
	assert_eq(lancer.global_position.y, 300.0)


# --- Strafe -------------------------------------------------------------------

func test_strafe_flips_at_the_right_bound() -> void:
	(Config.tuning["enemies"] as Dictionary)["lancer"]["fire_interval_s"] = 100.0
	var lancer: Lancer = _make({"position": Vector2(900, 160)})
	assert_eq(lancer.strafe_dir(), 1.0)
	while lancer.global_position.x < 1860.0:
		lancer.step(DT)
	# Put it exactly at 1860 moving +x.
	lancer.global_position.x = 1860.0
	assert_eq(lancer.strafe_dir(), 1.0)
	var max_x: float = 0.0
	var t: float = 0.0
	while t < 1.0 - DT / 2.0:
		lancer.step(DT)
		t += DT
		max_x = maxf(max_x, lancer.global_position.x)
		assert_eq(lancer.global_position.y, 160.0, "y unchanged")
	assert_almost_eq(max_x, 1872.0, 0.001, "reaches width - sprite_px / 2")
	assert_eq(lancer.strafe_dir(), -1.0, "flipped")
	# The step that hits the bound is clamped onto it, so allow one step of slack.
	assert_almost_eq(lancer.global_position.x, 1872.0 - (200.0 - 12.0), 200.0 * DT, "then moves -x")


func test_strafe_flips_at_the_left_bound() -> void:
	(Config.tuning["enemies"] as Dictionary)["lancer"]["fire_interval_s"] = 100.0
	var lancer: Lancer = _make({"position": Vector2(1100, 160)})
	assert_eq(lancer.strafe_dir(), -1.0)
	var min_x: float = INF
	for i: int in 400:
		lancer.step(DT)
		min_x = minf(min_x, lancer.global_position.x)
		assert_between(lancer.global_position.x, 48.0, 1872.0, "stays on screen")
	assert_almost_eq(min_x, 48.0, 0.001, "clamped onto the left bound")
	assert_eq(lancer.strafe_dir(), 1.0, "flipped to +x")


func test_strafe_large_step_is_clamped_on_screen() -> void:
	var lancer: Lancer = _make({"position": Vector2(900, 160)})
	assert_eq(lancer.strafe_dir(), 1.0)
	lancer.step(5.0)
	assert_eq(lancer.global_position.x, 1872.0, "clamped onto the bound")
	assert_eq(lancer.strafe_dir(), -1.0)


# --- Fire cycle ---------------------------------------------------------------

func test_fire_cycle_through_a_real_spawner() -> void:
	_make_world()
	_make_player(Vector2(960, 900))
	var lancer: Lancer = _spawn({"position": Vector2(700, 160)})
	if lancer == null:
		return
	assert_eq(lancer.spawner, _spawner, "Spawner injected itself")
	assert_eq(lancer.state(), Lancer.State.STRAFE)
	var t: float = _step_until(lancer, Lancer.State.TELEGRAPH, 3.0)
	assert_almost_eq(t, 1.7, DT * 1.5, "fire_interval_s - telegraph_s of strafing")
	assert_true(lancer.is_glowing(), "muzzle glows")
	var glow: CanvasItem = lancer.get_node("Muzzle/MuzzleGlow") as CanvasItem
	var e: float = Config.num("enemies.lancer.muzzle_glow_energy")
	assert_eq(glow.self_modulate, Color(e, e, e), "HDR glow")
	assert_eq(_bullets().size(), 0, "no shot during the telegraph start")
	var x_before: float = lancer.global_position.x
	lancer.step(DT)
	assert_gt(lancer.global_position.x, x_before, "still strafing while telegraphing")
	var tele: float = DT
	var muzzle_at_fire: Vector2 = Vector2.ZERO
	while lancer.state() == Lancer.State.TELEGRAPH and tele < 1.0:
		assert_eq(_bullets().size(), 0, "no shot before telegraph_s")
		var before_step: Vector2 = lancer.global_position
		lancer.step(DT)
		tele += DT
		# The bullet spawns where the muzzle was after this step's strafe move.
		muzzle_at_fire = (lancer.get_node("Muzzle") as Node2D).global_position
		if lancer.state() == Lancer.State.TELEGRAPH:
			assert_ne(lancer.global_position, before_step, "moving")
	assert_almost_eq(tele, Config.num("enemies.lancer.telegraph_s"), DT * 1.5, "telegraph_s")
	assert_eq(lancer.state(), Lancer.State.STRAFE, "back to STRAFE")
	assert_false(lancer.is_glowing(), "glow off")
	var bullets: Array[Projectile] = _bullets()
	assert_eq(bullets.size(), 1, "one enemy_bullet")
	if bullets.size() != 1:
		return
	var bullet: Projectile = bullets[0]
	bullet.set_physics_process(false)
	assert_true(bullet is EnemyBullet, "an EnemyBullet")
	assert_almost_eq(bullet.global_position, muzzle_at_fire, Vector2(0.001, 0.001), "spawned at Muzzle")
	assert_almost_eq(bullet.velocity.length(), Config.num("enemies.lancer.bullet_speed_px_s"), 0.01, "bullet_speed_px_s")
	var expected: Vector2 = (Vector2(960, 900) - muzzle_at_fire).normalized()
	assert_almost_eq(bullet.velocity.normalized().dot(expected), 1.0, 0.0001, "aimed at the player")
	assert_eq(bullet.damage, Config.int_("damage.bullet_hearts"), "damage.bullet_hearts")


func test_shot_direction_is_snapshotted_at_fire_time() -> void:
	_make_world()
	var player: Node2D = _make_player(Vector2(100, 900))
	var lancer: Lancer = _spawn({"position": Vector2(700, 160)})
	if lancer == null:
		return
	_step_until(lancer, Lancer.State.TELEGRAPH, 3.0)
	player.global_position = Vector2(1800, 700)
	_step_until(lancer, Lancer.State.STRAFE, 1.0)
	var bullets: Array[Projectile] = _bullets()
	assert_eq(bullets.size(), 1)
	if bullets.size() != 1:
		return
	bullets[0].set_physics_process(false)
	var expected: Vector2 = (Vector2(1800, 700) - bullets[0].global_position).normalized()
	assert_almost_eq(bullets[0].velocity.normalized().dot(expected), 1.0, 0.0001, "player position at fire time")
	var before: Vector2 = bullets[0].velocity
	player.global_position = Vector2(0, 0)
	lancer.step(DT)
	assert_eq(bullets[0].velocity, before, "never re-aimed after firing")


func test_shot_without_a_player_goes_straight_down() -> void:
	_make_world()
	var lancer: Lancer = _spawn({"position": Vector2(700, 160)})
	if lancer == null:
		return
	_step_until(lancer, Lancer.State.TELEGRAPH, 3.0)
	_step_until(lancer, Lancer.State.STRAFE, 1.0)
	var bullets: Array[Projectile] = _bullets()
	assert_eq(bullets.size(), 1)
	if bullets.size() == 1:
		bullets[0].set_physics_process(false)
		assert_almost_eq(bullets[0].velocity, Vector2(0, Config.num("enemies.lancer.bullet_speed_px_s")), Vector2(0.001, 0.01), "straight down at bullet_speed_px_s")


func test_player_on_the_muzzle_shoots_straight_down() -> void:
	# A stationary Lancer, so the player can sit exactly on its muzzle.
	(Config.tuning["enemies"] as Dictionary)["lancer"]["strafe_speed_px_s"] = 0.0
	_make_world()
	var lancer: Lancer = _spawn({"position": Vector2(700, 160)})
	if lancer == null:
		return
	_make_player((lancer.get_node("Muzzle") as Node2D).global_position)
	_step_until(lancer, Lancer.State.TELEGRAPH, 3.0)
	_step_until(lancer, Lancer.State.STRAFE, 1.0)
	var bullets: Array[Projectile] = _bullets()
	assert_eq(bullets.size(), 1)
	if bullets.size() == 1:
		bullets[0].set_physics_process(false)
		assert_almost_eq(bullets[0].velocity, Vector2(0, Config.num("enemies.lancer.bullet_speed_px_s")), Vector2(0.001, 0.01), "straight down at bullet_speed_px_s")


## DW-40 (decision #38): fire_interval_s is the full shot period and includes
## the telegraph, so shots are fire_interval_s apart, the muzzle glowing for the
## last telegraph_s of each period.
func test_cycle_repeats_every_full_period() -> void:
	_make_world()
	var lancer: Lancer = _spawn({"position": Vector2(700, 160)})
	if lancer == null:
		return
	var interval: float = Config.num("enemies.lancer.fire_interval_s")
	var telegraph: float = Config.num("enemies.lancer.telegraph_s")
	var t: float = 0.0
	var shots: Array[float] = []
	var glow_starts: Array[float] = []
	var was_glowing: bool = false
	# 3 shots by 3.25 periods (at ~1, ~2, ~3 periods); the 4th lands at ~4.
	while t < interval * 3.25:
		var before: int = _bullets().size()
		lancer.step(DT)
		t += DT
		if lancer.is_glowing() and not was_glowing:
			glow_starts.append(t)
		was_glowing = lancer.is_glowing()
		if _bullets().size() > before:
			shots.append(t)
	assert_eq(_bullets().size(), 3, "one shot per fire_interval_s")
	assert_eq(shots.size(), 3, "three separate shots")
	if shots.size() != 3:
		return
	assert_almost_eq(shots[0], interval, DT * 2.5, "first shot fire_interval_s after STRAFE begins")
	assert_almost_eq(shots[1] - shots[0], interval, DT * 2.5, "shot to shot = fire_interval_s")
	assert_almost_eq(shots[2] - shots[1], interval, DT * 2.5, "shot to shot = fire_interval_s")
	assert_eq(glow_starts.size(), 3, "one telegraph per shot")
	if glow_starts.size() == 3:
		for i: int in 3:
			assert_almost_eq(shots[i] - glow_starts[i], telegraph, DT * 1.5, "glows for the last telegraph_s")


## A telegraph at least as long as the interval clamps the strafe time to 0:
## the Lancer leaves STRAFE on the next tick and the period is ~telegraph_s.
func test_telegraph_longer_than_interval_clamps_strafe_to_zero() -> void:
	var lancer_tuning: Dictionary = (Config.tuning["enemies"] as Dictionary)["lancer"] as Dictionary
	lancer_tuning["fire_interval_s"] = 0.2
	lancer_tuning["telegraph_s"] = 0.5
	_make_world()
	var lancer: Lancer = _spawn({"position": Vector2(700, 160)})
	if lancer == null:
		return
	assert_eq(lancer.state(), Lancer.State.STRAFE)
	lancer.step(DT)
	assert_eq(lancer.state(), Lancer.State.TELEGRAPH, "leaves STRAFE on the next tick")
	var t: float = 0.0
	var shots: Array[float] = []
	while t < 2.0:
		var before: int = _bullets().size()
		lancer.step(DT)
		t += DT
		if _bullets().size() > before:
			shots.append(t)
	assert_gte(shots.size(), 3, "keeps firing")
	if shots.size() >= 2:
		assert_almost_eq(shots[1] - shots[0], 0.5, DT * 2.5, "period ~telegraph_s")
	assert_eq(_warns().size(), 0, "no warning")


func test_no_fire_while_entering() -> void:
	_make_world()
	var lancer: Lancer = _spawn({"position": Vector2(960, 160), "slot": Vector2(960, 378), "entry": &"top"})
	if lancer == null:
		return
	var t: float = 0.0
	while lancer.state() == Lancer.State.ENTER and t < 5.0:
		lancer.step(DT)
		t += DT
		assert_false(lancer.is_glowing())
	assert_gt(t, 2.0, "the entry takes longer than fire_interval_s")
	assert_eq(_projectiles.get_child_count(), 0, "never fires while entering")
	var strafe: float = _step_until(lancer, Lancer.State.TELEGRAPH, 3.0)
	assert_almost_eq(strafe, 1.7, DT * 1.5, "timer starts when STRAFE begins")


func test_no_spawner_runs_the_cycle_without_firing() -> void:
	Log.debug_enabled = true
	_make_player(Vector2(960, 900))
	var lancer: Lancer = _make({"position": Vector2(700, 160)})
	assert_null(lancer.spawner)
	for cycle: int in 2:
		_step_until(lancer, Lancer.State.TELEGRAPH, 3.0)
		assert_eq(lancer.state(), Lancer.State.TELEGRAPH, "cycle %d telegraphs" % cycle)
		_step_until(lancer, Lancer.State.STRAFE, 1.0)
		assert_eq(lancer.state(), Lancer.State.STRAFE, "cycle %d continues" % cycle)
	assert_eq(get_tree().get_nodes_in_group(&"projectiles").size(), 0, "no bullet")
	var debugs: Array[String] = _logged("[DEBUG][spawn]")
	assert_eq(debugs.size(), 1, "DEBUG once per Lancer")
	assert_eq(_warns().size(), 0)


# --- Tuning -------------------------------------------------------------------

func test_numbers_come_from_tuning() -> void:
	_make_world()
	var lancer_tuning: Dictionary = (Config.tuning["enemies"] as Dictionary)["lancer"] as Dictionary
	lancer_tuning["strafe_speed_px_s"] = 100.0
	lancer_tuning["zone_height_ratio"] = 0.2
	lancer_tuning["fire_interval_s"] = 1.0
	lancer_tuning["telegraph_s"] = 0.5
	lancer_tuning["bullet_speed_px_s"] = 300.0
	lancer_tuning["muzzle_glow_energy"] = 3.0
	(Config.tuning["damage"] as Dictionary)["bullet_hearts"] = 2
	var low: Lancer = _make({"position": Vector2(960, 300), "slot": Vector2(960, 300), "entry": &"top"})
	assert_eq(low.formation_slot().y, 216.0, "zone_height_ratio")
	low.step(0.1)
	assert_almost_eq(low.global_position.y, -48.0 + 10.0, 0.001, "strafe_speed_px_s drives the entry")
	var lancer: Lancer = _spawn({"position": Vector2(700, 160)})
	if lancer == null:
		return
	lancer.step(0.1)
	assert_almost_eq(lancer.global_position.x, 710.0, 0.001, "strafe_speed_px_s")
	var t: float = 0.1 + _step_until(lancer, Lancer.State.TELEGRAPH, 3.0)
	assert_almost_eq(t, 0.5, DT * 1.5, "fire_interval_s - telegraph_s")
	var glow: CanvasItem = lancer.get_node("Muzzle/MuzzleGlow") as CanvasItem
	assert_eq(glow.self_modulate, Color(3.0, 3.0, 3.0), "muzzle_glow_energy")
	var tele: float = _step_until(lancer, Lancer.State.STRAFE, 2.0)
	assert_almost_eq(tele, 0.5, DT * 1.5, "telegraph_s")
	var bullets: Array[Projectile] = _bullets()
	assert_eq(bullets.size(), 1)
	if bullets.size() == 1:
		bullets[0].set_physics_process(false)
		assert_almost_eq(bullets[0].velocity.length(), 300.0, 0.001, "bullet_speed_px_s")
		assert_eq(bullets[0].damage, 2, "damage.bullet_hearts")


func test_state_is_assigned_only_in_enter_state() -> void:
	var source: String = FileAccess.get_file_as_string(LANCER_SCRIPT_PATH)
	var assignments: RegEx = RegEx.create_from_string("(?<!\\w)_state\\s*=(?!=)")
	assert_eq(assignments.search_all(source).size(), 1, "exactly one `_state =`")
	var enter: int = source.find("func _enter_state(")
	var hit: RegExMatch = assignments.search(source)
	assert_true(enter >= 0 and hit != null and hit.get_start() > enter, "inside _enter_state")


# --- Pause --------------------------------------------------------------------

func test_paused_tree_freezes_the_lancer_and_its_bullets() -> void:
	_make_world()
	var lancer: Lancer = _spawner.spawn_enemy(&"lancer", {"position": Vector2(700, 160)}) as Lancer
	var bullet: Projectile = _spawner.spawn_projectile(&"enemy_bullet",
		{"position": Vector2(960, 540), "velocity": Vector2(0, 450), "damage": 1})
	assert_not_null(lancer)
	assert_not_null(bullet)
	if lancer == null or bullet == null:
		return
	assert_eq(lancer.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_eq(bullet.process_mode, Node.PROCESS_MODE_INHERIT)
	PauseArbiter.push(&"menu")
	var lancer_before: Vector2 = lancer.global_position
	var bullet_before: Vector2 = bullet.global_position
	assert_false(lancer.can_process(), "Lancer paused with the tree")
	assert_false(bullet.can_process(), "bullet paused with the tree")
	await get_tree().create_timer(0.2, true, true).timeout
	assert_eq(lancer.global_position, lancer_before, "Lancer frozen")
	assert_eq(bullet.global_position, bullet_before, "bullet frozen")
	PauseArbiter.pop(&"menu")
	await wait_physics_frames(3)
	assert_gt(lancer.global_position.x, lancer_before.x, "Lancer moves again")
	assert_gt(bullet.global_position.y, bullet_before.y, "bullet moves again")


# --- Convoy targeting (Story 6.3) ------------------------------------------------

func _lancer_tuning() -> Dictionary:
	return (Config.tuning["enemies"] as Dictionary)["lancer"] as Dictionary


## A real Convoy (joins Groups.CONVOY), physics off so its ships stay put.
func _make_convoy() -> Convoy:
	var convoy: Convoy = CONVOY_SCENE.instantiate() as Convoy
	convoy.setup({})
	add_child_autofree(convoy)
	convoy.set_physics_process(false)
	return convoy


## Calls the Lancer's _fire() once and returns the bullet it spawned (physics off).
func _fire_once(lancer: Lancer) -> EnemyBullet:
	var before: int = _bullets().size()
	lancer._fire()
	var bullets: Array[Projectile] = _bullets()
	assert_eq(bullets.size(), before + 1, "one bullet per _fire")
	if bullets.size() != before + 1:
		return null
	var bullet: EnemyBullet = bullets[bullets.size() - 1] as EnemyBullet
	bullet.set_physics_process(false)
	return bullet


## The convoy ship whose centre `bullet` aims at exactly, or null.
func _aimed_ship(bullet: EnemyBullet, convoy: Convoy) -> ConvoyShip:
	for ship: ConvoyShip in convoy.ships():
		var expected: Vector2 = (ship.global_position - bullet.global_position).normalized()
		if bullet.velocity.normalized().dot(expected) > 0.99999:
			return ship
	return null


func _aims_at_player(bullet: EnemyBullet) -> bool:
	var expected: Vector2 = (_player.global_position - bullet.global_position).normalized()
	return bullet.velocity.normalized().dot(expected) > 0.99999


func test_convoy_aim_chance_from_tuning() -> void:
	assert_between(Config.num("enemies.lancer.convoy_aim_chance"), 0.0, 1.0, "convoy_aim_chance is a probability")
	assert_gte(Config.int_("damage.convoy_stray"), 0, "convoy_stray >= 0")
	assert_gte(Config.int_("damage.convoy_aimed"), Config.int_("damage.convoy_stray"), "an aimed shot costs at least a stray")


func test_rng_is_a_seedable_member() -> void:
	var a: Lancer = _make({"position": Vector2(700, 160)})
	assert_true(a.rng is RandomNumberGenerator)
	var b: Lancer = _make({"position": Vector2(900, 160)})
	assert_ne(a.rng.seed, b.rng.seed, "randomized in _ready")


func test_chance_one_always_aims_at_a_convoy_ship() -> void:
	_lancer_tuning()["convoy_aim_chance"] = 1.0
	_make_world()
	_make_player(Vector2(960, 600))
	var convoy: Convoy = _make_convoy()
	var lancer: Lancer = _spawn({"position": Vector2(700, 160)})
	if lancer == null:
		return
	lancer.rng.seed = 42
	var hit: Dictionary = {}
	for i: int in 60:
		var bullet: EnemyBullet = _fire_once(lancer)
		if bullet == null:
			return
		assert_true(bullet.targets_convoy, "shot %d marked targets_convoy" % i)
		var ship: ConvoyShip = _aimed_ship(bullet, convoy)
		assert_not_null(ship, "shot %d points at a ship centre" % i)
		if ship != null:
			hit[ship.name] = true
		assert_almost_eq(bullet.velocity.length(), Config.num("enemies.lancer.bullet_speed_px_s"), 0.01, "bullet_speed_px_s")
		assert_eq(bullet.damage, Config.int_("damage.bullet_hearts"), "its own heart damage is unchanged")
	assert_eq(hit.size(), 3, "every ship can be picked")


func test_chance_zero_never_aims_at_the_convoy() -> void:
	_lancer_tuning()["convoy_aim_chance"] = 0.0
	_make_world()
	_make_player(Vector2(960, 600))
	_make_convoy()
	var lancer: Lancer = _spawn({"position": Vector2(700, 160)})
	if lancer == null:
		return
	for i: int in 50:
		var bullet: EnemyBullet = _fire_once(lancer)
		if bullet == null:
			return
		assert_false(bullet.targets_convoy, "shot %d not convoy-aimed" % i)
		assert_true(_aims_at_player(bullet), "shot %d aims at the player" % i)


func test_roll_and_pick_use_the_lancer_rng() -> void:
	_lancer_tuning()["convoy_aim_chance"] = 0.5
	_make_world()
	_make_player(Vector2(960, 600))
	var convoy: Convoy = _make_convoy()
	var lancer: Lancer = _spawn({"position": Vector2(700, 160)})
	if lancer == null:
		return
	lancer.rng.seed = 1234
	var mirror: RandomNumberGenerator = RandomNumberGenerator.new()
	mirror.seed = 1234
	for i: int in 40:
		var expected: ConvoyShip = null
		if mirror.randf() < 0.5:
			expected = convoy.ships()[mirror.randi_range(0, convoy.ships().size() - 1)]
		var bullet: EnemyBullet = _fire_once(lancer)
		if bullet == null:
			return
		assert_eq(bullet.targets_convoy, expected != null, "shot %d roll" % i)
		if expected != null:
			assert_eq(_aimed_ship(bullet, convoy), expected, "shot %d pick" % i)
		else:
			assert_true(_aims_at_player(bullet), "shot %d aims at the player" % i)


func test_seeded_odds_over_1000_shots() -> void:
	_lancer_tuning()["convoy_aim_chance"] = 0.5
	_make_world()
	_make_convoy()
	var lancer: Lancer = _spawn({"position": Vector2(700, 160)})
	if lancer == null:
		return
	lancer.rng.seed = 6303
	var convoy_shots: int = 0
	for i: int in 1000:
		if lancer._pick_convoy_ship() != null:
			convoy_shots += 1
	assert_between(convoy_shots, 450, 550, "about half the shots aim at the convoy")


func test_no_convoy_always_aims_at_the_player_without_a_roll() -> void:
	_lancer_tuning()["convoy_aim_chance"] = 1.0
	_make_world()
	_make_player(Vector2(960, 600))
	var lancer: Lancer = _spawn({"position": Vector2(700, 160)})
	if lancer == null:
		return
	var state_before: int = lancer.rng.state
	for i: int in 10:
		var bullet: EnemyBullet = _fire_once(lancer)
		if bullet == null:
			return
		assert_false(bullet.targets_convoy)
		assert_true(_aims_at_player(bullet), "aims at the player")
	assert_eq(lancer.rng.state, state_before, "no roll consumed")


func test_lost_convoy_counts_as_no_convoy() -> void:
	_lancer_tuning()["convoy_aim_chance"] = 1.0
	_make_world()
	_make_player(Vector2(960, 600))
	var convoy: Convoy = _make_convoy()
	convoy.apply_damage(convoy.max_hp(), null)
	assert_true(convoy.is_lost())
	var lancer: Lancer = _spawn({"position": Vector2(700, 160)})
	if lancer == null:
		return
	var state_before: int = lancer.rng.state
	var bullet: EnemyBullet = _fire_once(lancer)
	if bullet == null:
		return
	assert_false(bullet.targets_convoy)
	assert_true(_aims_at_player(bullet))
	assert_eq(lancer.rng.state, state_before, "no roll consumed")


func test_convoy_without_ships_counts_as_no_convoy() -> void:
	_lancer_tuning()["convoy_aim_chance"] = 1.0
	_make_world()
	_make_player(Vector2(960, 600))
	var convoy: Convoy = _make_convoy()
	convoy.ships().clear()
	var lancer: Lancer = _spawn({"position": Vector2(700, 160)})
	if lancer == null:
		return
	var state_before: int = lancer.rng.state
	var bullet: EnemyBullet = _fire_once(lancer)
	if bullet == null:
		return
	assert_false(bullet.targets_convoy)
	assert_true(_aims_at_player(bullet))
	assert_eq(lancer.rng.state, state_before, "no roll consumed")


func test_convoy_shot_with_the_muzzle_on_the_ship_centre_goes_straight_down() -> void:
	_lancer_tuning()["convoy_aim_chance"] = 1.0
	_lancer_tuning()["strafe_speed_px_s"] = 0.0
	_make_world()
	var convoy: Convoy = _make_convoy()
	var lancer: Lancer = _spawn({"position": Vector2(700, 160)})
	if lancer == null:
		return
	# Every ship centre on the muzzle, so whichever ship is picked the vector is zero.
	var muzzle: Vector2 = (lancer.get_node("Muzzle") as Node2D).global_position
	for ship: ConvoyShip in convoy.ships():
		ship.global_position = muzzle
	var bullet: EnemyBullet = _fire_once(lancer)
	if bullet == null:
		return
	assert_true(bullet.targets_convoy)
	assert_almost_eq(bullet.velocity, Vector2(0, Config.num("enemies.lancer.bullet_speed_px_s")), Vector2(0.001, 0.01), "straight down at bullet_speed_px_s")
	assert_eq(Lancer._aim_at(Vector2(5, 5), Vector2(5, 5)), Vector2.DOWN)
	assert_almost_eq(Lancer._aim_at(Vector2(0, 0), Vector2(3, 4)), Vector2(0.6, 0.8), Vector2(0.0001, 0.0001))


func test_roll_happens_once_at_fire_time_after_the_telegraph() -> void:
	_lancer_tuning()["convoy_aim_chance"] = 1.0
	_make_world()
	_make_player(Vector2(960, 600))
	var convoy: Convoy = _make_convoy()
	var lancer: Lancer = _spawn({"position": Vector2(700, 160)})
	if lancer == null:
		return
	var state_before: int = lancer.rng.state
	_step_until(lancer, Lancer.State.TELEGRAPH, 3.0)
	assert_eq(lancer.rng.state, state_before, "no roll while strafing")
	while lancer.state() == Lancer.State.TELEGRAPH:
		assert_eq(lancer.rng.state, state_before, "no roll during the telegraph")
		lancer.step(DT)
	var bullets: Array[Projectile] = _bullets()
	assert_eq(bullets.size(), 1, "one shot")
	assert_ne(lancer.rng.state, state_before, "rolled at the shot")
	if bullets.size() != 1:
		return
	var bullet: EnemyBullet = bullets[0] as EnemyBullet
	bullet.set_physics_process(false)
	assert_true(bullet.targets_convoy)
	assert_not_null(_aimed_ship(bullet, convoy), "aimed at a ship centre at fire time")
