extends GutTest
## AllyShip (Story 6.4, FR34, FR7): the scene's layers (nothing detects it, no
## apply_damage), the tuning, the start on the band centre, the ping-pong patrol
## (patrol_step, two full crossings), the fire cadence (one shot per interval,
## the remainder kept, none without a target, none after an outcome), the
## nearest-target pick (dead, off-screen and non-Enemy nodes skipped), the zero
## aim vector, a real ally kill reporting by_ally, and real enemy shots and the
## Player passing through it. Driven through step() with physics off unless a
## real overlap is needed.

const ALLY_SCENE: PackedScene = preload("res://entities/allies/ally_ship.tscn")
const WASP_SCENE: PackedScene = preload("res://entities/enemies/wasp/wasp.tscn")
const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")
const BULLET_SCENE: PackedScene = preload("res://entities/projectiles/enemy_bullet.tscn")
const DT: float = 1.0 / 60.0
## An exact binary fraction: four steps make the 0.5 s interval exactly.
const STEP: float = 0.125

var _world: Node2D
var _projectiles: Node2D
var _enemies: Node2D
var _allies: Node2D
var _spawner: Spawner
var _lines: Array[String] = []
var _kills: Array[Array] = []


func before_each() -> void:
	_lines.clear()
	_kills.clear()
	Log.sink = _capture
	_world = Node2D.new()
	_projectiles = _add_container("Projectiles")
	_enemies = _add_container("Enemies")
	_add_container("Asteroids")
	_allies = _add_container("Allies")
	add_child_autofree(_world)
	_spawner = Spawner.new()
	_spawner.world = _world
	add_child_autofree(_spawner)
	Events.enemy_killed.connect(_on_enemy_killed)


func after_each() -> void:
	Events.enemy_killed.disconnect(_on_enemy_killed)
	Log.sink = Callable()
	Config.load_data()
	Feedback.reset()
	_world = null
	_spawner = null


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _on_enemy_killed(enemy_type: StringName, pos: Vector2, by_ally: bool) -> void:
	_kills.append([enemy_type, pos, by_ally])


func _add_container(container_name: String) -> Node2D:
	var node: Node2D = Node2D.new()
	node.name = container_name
	_world.add_child(node)
	return node


## An ally through the Spawner (into Allies, with the Spawner), physics off.
func _make(id: String = "tarek") -> AllyShip:
	var ally: AllyShip = _spawner.spawn_ally({"ally": id})
	assert_not_null(ally, "spawned")
	ally.set_physics_process(false)
	return ally


## A still Wasp (no slot, so no entry flight) at `pos`, physics and process off.
func _wasp(pos: Vector2) -> Wasp:
	var wasp: Wasp = _spawner.spawn_enemy(&"wasp", {"position": pos}) as Wasp
	wasp.set_physics_process(false)
	wasp.set_process(false)
	return wasp


func _bolts() -> Array[AllyBolt]:
	var out: Array[AllyBolt] = []
	for child: Node in _projectiles.get_children():
		if child is AllyBolt and not child.is_queued_for_deletion():
			out.append(child as AllyBolt)
	return out


func _steps(ally: AllyShip, n: int, delta: float = STEP) -> void:
	for i: int in n:
		ally.step(delta)


# --- Tuning and scene shape -------------------------------------------------------

func test_tuning() -> void:
	assert_eq(Config.num("allies.patrol_band_y.min"), 620.0)
	assert_eq(Config.num("allies.patrol_band_y.max"), 760.0)
	assert_eq(Config.num("allies.speed_px_s"), 150.0)
	assert_eq(Config.int_("allies.damage"), 1)
	assert_eq(Config.num("allies.fire_interval_s"), 0.5)
	assert_eq(Config.num("allies.ship_px"), 64.0)
	assert_eq(Config.num("allies.shot_speed_px_s"), 1200.0)
	assert_eq(Config.num("allies.kill_share.min"), 0.10)
	assert_eq(Config.num("allies.kill_share.max"), 0.15)


func test_scene_layers_and_no_damage_intake() -> void:
	var ally: AllyShip = ALLY_SCENE.instantiate() as AllyShip
	assert_eq(ally.collision_layer, CollisionLayers.ALLIES, ".tscn on the allies layer")
	assert_eq(ally.collision_mask, 0, ".tscn detects nothing")
	assert_false(ally.monitoring)
	assert_false(ally.monitorable)
	ally.free()
	var live: AllyShip = _make()
	assert_eq(live.collision_layer, CollisionLayers.ALLIES)
	assert_eq(live.collision_mask, 0)
	assert_false(live.monitoring, "detects nothing")
	assert_false(live.monitorable, "nothing detects it")
	assert_false(live.has_method(&"apply_damage"), "takes no damage")
	assert_true(live.is_in_group(&"allies"))
	assert_eq(live.ally_id, "tarek")
	assert_eq(live.spawner, _spawner)
	assert_eq(live.get_parent(), _allies)
	assert_eq(live.state(), AllyShip.State.PATROL)


func test_setup_sets_the_ally_id() -> void:
	assert_eq(_make("ryn").ally_id, "ryn")


# --- Patrol -----------------------------------------------------------------------

func test_starts_at_the_left_edge_on_the_band_centre_heading_right() -> void:
	var ally: AllyShip = _make()
	assert_eq(ally.global_position, Vector2(32, 690))
	assert_between(ally.global_position.y, 620.0, 760.0)
	assert_eq(ally.direction(), 1)


func test_moves_at_speed_and_keeps_its_y() -> void:
	var ally: AllyShip = _make()
	ally.step(1.0)
	assert_almost_eq(ally.global_position.x, 32.0 + 150.0, 0.001, "150 px/s")
	assert_eq(ally.global_position.y, 690.0)
	ally.step(DT)
	assert_almost_eq(ally.global_position.x, 182.0 + 150.0 * DT, 0.001)


func test_physics_process_steps() -> void:
	var ally: AllyShip = _make()
	ally._physics_process(1.0)
	assert_almost_eq(ally.global_position.x, 182.0, 0.001)


func test_patrol_step_pure() -> void:
	assert_eq(AllyShip.patrol_step(100.0, 1, 50.0, 32.0, 1888.0), Vector2(150, 1))
	assert_eq(AllyShip.patrol_step(100.0, -1, 50.0, 32.0, 1888.0), Vector2(50, -1))
	assert_eq(AllyShip.patrol_step(1880.0, 1, 50.0, 32.0, 1888.0), Vector2(1888, -1), "clamped, flips at the right edge")
	assert_eq(AllyShip.patrol_step(40.0, -1, 50.0, 32.0, 1888.0), Vector2(32, 1), "clamped, flips at the left edge")
	assert_eq(AllyShip.patrol_step(1888.0, -1, 0.0, 32.0, 1888.0), Vector2(1888, -1), "no distance, no flip away from an edge")
	assert_eq(AllyShip.patrol_step(100.0, 1, -5.0, 32.0, 1888.0), Vector2(100, 1), "negative distance is 0")


func test_two_crossings_ping_pong_on_screen() -> void:
	var ally: AllyShip = _make()
	var flips: int = 0
	var last_dir: int = ally.direction()
	var min_x: float = INF
	var max_x: float = -INF
	var off_band: int = 0
	# One crossing is (1920 - 64) / 150 = 12.4 s; 2.2 crossings.
	for i: int in int(27.5 / DT):
		ally.step(DT)
		if ally.global_position.y != 690.0:
			off_band += 1
		min_x = minf(min_x, ally.global_position.x)
		max_x = maxf(max_x, ally.global_position.x)
		if ally.direction() != last_dir:
			flips += 1
			last_dir = ally.direction()
	assert_eq(flips, 2, "turned at the right edge, then at the left edge")
	assert_eq(ally.direction(), 1, "heading right again")
	assert_almost_eq(max_x, 1888.0, 0.001, "reaches the right edge, never past it")
	assert_almost_eq(min_x, 32.0, 0.001, "back at the left edge, never past it")
	assert_eq(off_band, 0, "y never changes")


# --- Fire -------------------------------------------------------------------------

func test_fires_once_per_interval_at_the_target() -> void:
	var ally: AllyShip = _make()
	var wasp: Wasp = _wasp(Vector2(600, 300))
	_steps(ally, 3)
	assert_eq(_bolts().size(), 0, "0.375 s: no shot yet")
	_steps(ally, 1)
	assert_eq(_bolts().size(), 1, "0.5 s: one shot")
	var bolt: AllyBolt = _bolts()[0]
	assert_true(bolt.from_ally, "from_ally")
	assert_eq(bolt.damage, 1, "allies.damage")
	assert_eq(bolt.collision_layer, CollisionLayers.PLAYER_SHOTS)
	assert_almost_eq(bolt.velocity.length(), 1200.0, 0.01, "shot_speed_px_s")
	assert_almost_eq(bolt.global_position, ally.global_position, Vector2(0.001, 0.001), "from the ally")
	var want: Vector2 = (wasp.global_position - ally.global_position).normalized()
	assert_almost_eq(bolt.velocity.normalized(), want, Vector2(0.0001, 0.0001), "aimed at the wasp")
	_steps(ally, 36)
	assert_eq(_bolts().size(), 10, "5 s: ten shots, one per interval")


func test_clock_keeps_the_remainder() -> void:
	var ally: AllyShip = _make()
	_wasp(Vector2(600, 300))
	ally.step(0.375)
	ally.step(0.25)
	assert_eq(_bolts().size(), 1, "0.625 s: one shot")
	assert_almost_eq(ally.fire_clock(), 0.125, 0.0001, "the remainder is kept")
	ally.step(0.375)
	assert_eq(_bolts().size(), 2, "the next shot at 1.0 s")


func test_no_target_no_shot_and_the_clock_keeps_running() -> void:
	var ally: AllyShip = _make()
	_steps(ally, 6)
	assert_eq(_bolts().size(), 0, "no enemies: no shot")
	assert_almost_eq(ally.fire_clock(), 0.25, 0.0001, "the clock ran past the interval")
	_wasp(Vector2(600, 300))
	assert_eq(_bolts().size(), 0, "a target appearing fires nothing at once")
	_steps(ally, 1)
	assert_eq(_bolts().size(), 0, "0.375 s into the interval: still nothing")
	_steps(ally, 1)
	assert_eq(_bolts().size(), 1, "on the next elapsed interval")


func test_dead_or_offscreen_enemies_draw_no_shot() -> void:
	var ally: AllyShip = _make()
	var dead: Wasp = _wasp(Vector2(400, 300))
	dead.set("_dead", true)
	_wasp(Vector2(600, -40))
	_wasp(Vector2(1960, 400))
	_steps(ally, 8)
	assert_eq(_bolts().size(), 0, "dead and off-screen enemies are no targets")


func test_no_shots_after_a_clear_but_still_patrols() -> void:
	var ally: AllyShip = _make()
	_wasp(Vector2(600, 300))
	_steps(ally, 4)
	assert_eq(_bolts().size(), 1)
	Events.level_cleared.emit(0)
	assert_true(ally.has_ended())
	var x: float = ally.global_position.x
	_steps(ally, 16)
	assert_eq(_bolts().size(), 1, "no further shots")
	assert_almost_eq(ally.global_position.x, x + 150.0 * 2.0, 0.001, "still patrols")


func test_no_shots_after_a_failure() -> void:
	var ally: AllyShip = _make()
	_wasp(Vector2(600, 300))
	Events.level_failed.emit(&"hearts")
	_steps(ally, 16)
	assert_eq(_bolts().size(), 0, "no shots once the level failed")


func test_zero_fire_interval_warns_and_never_fires() -> void:
	(Config.tuning["allies"] as Dictionary)["fire_interval_s"] = 0.0
	var ally: AllyShip = _make()
	_wasp(Vector2(600, 300))
	_steps(ally, 16)
	assert_eq(_bolts().size(), 0, "never fires")
	var n: int = 0
	for line: String in _lines:
		if line.begins_with("[WARN][data] allies.fire_interval_s"):
			n += 1
	assert_eq(n, 1, "one data WARN")


func test_without_a_spawner_no_shot_and_one_debug_line() -> void:
	var debug_was: bool = Log.debug_enabled
	Log.debug_enabled = true
	var ally: AllyShip = _make()
	ally.spawner = null
	_wasp(Vector2(600, 300))
	_steps(ally, 16)
	Log.debug_enabled = debug_was
	assert_eq(_bolts().size(), 0)
	var n: int = 0
	for line: String in _lines:
		if line.begins_with("[DEBUG][spawn]") and line.contains("no spawner"):
			n += 1
	assert_eq(n, 1, "logged once")


# --- Target pick ------------------------------------------------------------------

func test_nearest_target_skips_dead_offscreen_and_non_enemies() -> void:
	var near: Wasp = _wasp(Vector2(200, 600))
	var far: Wasp = _wasp(Vector2(1500, 200))
	var dead: Wasp = _wasp(Vector2(100, 680))
	dead.set("_dead", true)
	var offscreen: Wasp = _wasp(Vector2(-20, 690))
	var plain: Node2D = Node2D.new()
	add_child_autofree(plain)
	var from: Vector2 = Vector2(32, 690)
	var nodes: Array[Node] = [far, dead, plain, offscreen, near]
	assert_eq(AllyShip.nearest_target(from, nodes), near, "the nearest live on-screen enemy")
	var only_bad: Array[Node] = [dead, offscreen, plain]
	assert_null(AllyShip.nearest_target(from, only_bad), "none qualifies")
	assert_null(AllyShip.nearest_target(from, [] as Array[Node]))


func test_fire_re_acquires_the_nearest_each_shot() -> void:
	var ally: AllyShip = _make()
	var a: Wasp = _wasp(Vector2(300, 690))
	var b: Wasp = _wasp(Vector2(1800, 690))
	_steps(ally, 4)
	assert_gt(_bolts()[0].velocity.x, 0.0)
	assert_almost_eq(_bolts()[0].velocity.normalized(), (a.global_position - ally.global_position).normalized(), Vector2(0.0001, 0.0001))
	a.set("_dead", true)
	_steps(ally, 4)
	assert_eq(_bolts().size(), 2)
	assert_almost_eq(_bolts()[1].velocity.normalized(), (b.global_position - ally.global_position).normalized(), Vector2(0.0001, 0.0001), "the next nearest")


func test_zero_aim_vector_fires_straight_up() -> void:
	assert_eq(AllyShip.aim(Vector2(5, 5), Vector2(5, 5)), Vector2.UP)
	assert_eq(AllyShip.aim(Vector2(0, 0), Vector2(10, 0)), Vector2.RIGHT)
	var ally: AllyShip = _make()
	_steps(ally, 3)
	_wasp(ally.global_position + Vector2(150.0 * STEP, 0.0))
	_steps(ally, 1)
	assert_eq(_bolts().size(), 1)
	assert_almost_eq(_bolts()[0].velocity, Vector2(0, -1200), Vector2(0.001, 0.001), "straight up")


# --- Real overlaps ----------------------------------------------------------------

func test_ally_bolt_kill_reports_by_ally() -> void:
	var ally: AllyShip = _make()
	var wasp: Wasp = _wasp(Vector2(32, 400))
	wasp.hp = 1
	var pos: Vector2 = wasp.global_position
	_steps(ally, 4)
	# The ally moved 75 px right while the clock ran; the shot still aims at the wasp.
	assert_eq(_bolts().size(), 1)
	await wait_physics_frames(30)
	assert_eq(_kills.size(), 1, "one kill")
	if _kills.size() == 1:
		assert_eq(_kills[0][0], &"wasp")
		assert_eq(_kills[0][1], pos)
		assert_true(_kills[0][2], "by_ally true")


func test_enemy_bullet_passes_through_the_ally() -> void:
	var ally: AllyShip = _make()
	var bullet: EnemyBullet = BULLET_SCENE.instantiate() as EnemyBullet
	bullet.setup({"position": ally.global_position + Vector2(0, -100), "velocity": Vector2(0, 450), "damage": 1})
	add_child_autofree(bullet)
	watch_signals(bullet)
	await wait_physics_frames(30)
	assert_true(is_instance_valid(bullet) and not bullet.is_queued_for_deletion(), "the bullet keeps flying")
	assert_gt(bullet.global_position.y, ally.global_position.y + 50.0, "past the ally")
	assert_signal_not_emitted(bullet, "area_entered", "no overlap with the ally")


func test_player_overlapping_the_ally_does_nothing() -> void:
	var ally: AllyShip = _make()
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.warp_mouse = func(_p: Vector2) -> void: pass
	add_child_autofree(player)
	player.set_physics_process(false)
	player.global_position = ally.global_position
	watch_signals(Events)
	var hearts: int = player.hearts
	await wait_physics_frames(10)
	assert_eq(player.hearts, hearts, "no hearts lost")
	assert_false(player.get_overlapping_areas().has(ally), "the hurtbox doesn't see the ally")
	assert_signal_not_emitted(Events, "player_hit")


# --- Drawing ----------------------------------------------------------------------

func test_fighter_outline_is_ship_px_nose_up_in_coalition() -> void:
	var ally: AllyShip = _make()
	var pts: PackedVector2Array = ally.outline()
	assert_gt(pts.size(), 2)
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	for p: Vector2 in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	assert_almost_eq(hi.y - lo.y, 64.0, 0.001, "ship_px tall")
	assert_almost_eq(hi.x - lo.x, 64.0, 0.001, "ship_px wide")
	assert_eq(pts[0], Vector2(0, -32), "nose up")
	assert_eq(AllyShip.OUTLINE_COLOR, Color("#22E6FF"))
