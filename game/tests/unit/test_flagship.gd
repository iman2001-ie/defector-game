extends GutTest
## Flagship Phase 1 (Story 7.3, FR49, FR52, FR53): spawned through a real
## Spawner into a fixture world (Enemies, Projectiles, Effects, Pickups) and
## driven through step(delta) with physics processing off. Covers the arrival,
## the staggered start-to-start turret cadence (shot times, glow window, spread
## angles and speed), part, hull and core damage, turret death (Boss-part tier,
## enemy_killed, the orb), all turrets dead, the combined HP events, hitbox
## layout, contact and targeting.

const FLAGSHIP_SCENE: PackedScene = preload("res://entities/boss/flagship.tscn")
const DT: float = 1.0 / 60.0
const EPS: float = 0.0001

var _world: Node2D = null
var _projectiles: Node2D = null
var _pickups: Node2D = null
var _effects: Node2D = null
var _spawner: Spawner = null
var _camera: ShakeCamera = null
var _lines: Array[String] = []
## Every boss Events emission: [signal name, args...].
var _events: Array[Array] = []
var _recorders: Dictionary = {}


func before_each() -> void:
	_lines.clear()
	_events.clear()
	Log.sink = _capture
	_recorders = {
		"boss_started": func() -> void: _events.append(["boss_started"]),
		"boss_phase_changed": func(p: int) -> void: _events.append(["boss_phase_changed", p]),
		"boss_hp_changed": func(c: int, m: int, p: int) -> void: _events.append(["boss_hp_changed", c, m, p]),
		"enemy_killed": func(t: StringName, pos: Vector2, by_ally: bool) -> void: _events.append(["enemy_killed", t, pos, by_ally]),
		"boss_defeated": func() -> void: _events.append(["boss_defeated"]),
	}
	for signal_name: String in _recorders:
		Events.connect(signal_name, _recorders[signal_name])


func after_each() -> void:
	for signal_name: String in _recorders:
		Events.disconnect(signal_name, _recorders[signal_name])
	_recorders = {}
	Log.sink = Callable()
	Config.load_data()
	Feedback.reset()
	PauseArbiter.clear()
	_world = null
	_projectiles = null
	_pickups = null
	_effects = null
	_spawner = null
	_camera = null


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _logged(text: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.contains(text):
			out.append(line)
	return out


func _events_named(signal_name: String) -> Array[Array]:
	var out: Array[Array] = []
	for event: Array in _events:
		if event[0] == signal_name:
			out.append(event)
	return out


## A world with Enemies, Projectiles, Effects and Pickups, a real Spawner and a
## ShakeCamera (frozen, so its amplitude can be read).
func _make_world() -> void:
	_world = Node2D.new()
	_world.name = "World"
	for container: String in ["Enemies", "Projectiles", "Effects", "Pickups", "Asteroids"]:
		var node: Node2D = Node2D.new()
		node.name = container
		_world.add_child(node)
	add_child_autofree(_world)
	_projectiles = _world.get_node("Projectiles") as Node2D
	_pickups = _world.get_node("Pickups") as Node2D
	_effects = _world.get_node("Effects") as Node2D
	_spawner = Spawner.new()
	_spawner.world = _world
	add_child_autofree(_spawner)
	_camera = ShakeCamera.new()
	add_child_autofree(_camera)
	_camera.set_process(false)


## A Flagship spawned through the fixture's Spawner, physics off.
func _spawn() -> Flagship:
	if _spawner == null:
		_make_world()
	var boss: Flagship = _spawner.spawn_boss(&"flagship", {})
	assert_not_null(boss, "spawned a Flagship")
	if boss != null:
		boss.set_physics_process(false)
	return boss


## A Flagship spawned and stepped straight to its station (TURRETS).
func _spawn_at_station() -> Flagship:
	var boss: Flagship = _spawn()
	boss.step(Config.num("boss.hull.arrival_s"))
	assert_eq(boss.phase(), Flagship.Phase.TURRETS, "at its station")
	return boss


func _bullets() -> Array[Projectile]:
	var out: Array[Projectile] = []
	for child: Node in _projectiles.get_children():
		var p: Projectile = child as Projectile
		if p != null and not p.is_queued_for_deletion():
			out.append(p)
	return out


func _deg_from_down(v: Vector2) -> float:
	return rad_to_deg(Vector2.DOWN.angle_to(v))


func _newest_explosion() -> Explosion:
	for i: int in range(_effects.get_child_count() - 1, -1, -1):
		var e: Explosion = _effects.get_child(i) as Explosion
		if e != null:
			return e
	return null


# --- Scene, registry and spawn ------------------------------------------------

func test_flagship_is_a_boss_not_a_spawns_type() -> void:
	assert_true(EntityRegistry.BOSSES.has(&"flagship"), "in BOSSES")
	assert_false(EntityRegistry.ENEMIES.has(&"flagship"), "not a valid spawns type")
	assert_false(EntityRegistry.enemy_types().has(&"flagship"))


func test_spawn_builds_the_hull_four_turrets_and_the_core() -> void:
	var boss: Flagship = _spawn()
	assert_eq(boss.get_parent(), _world.get_node("Enemies"), "under World/Enemies")
	assert_eq(boss.type_id, &"flagship")
	assert_eq(boss.tier, ImpactTier.BOSS_DEATH)
	assert_eq(boss.spawner, _spawner)
	assert_true(boss.is_in_group(&"boss"), "in Groups.BOSS")
	assert_true(boss.is_in_group(&"enemies"))
	assert_false(boss.is_in_group(&"counted"), "never counted")
	assert_eq(boss.turrets().size(), Config.int_("boss.turrets.count"), "the scene's turrets match tuning")
	assert_eq(boss.turrets().size(), 4)
	for area: Area2D in [boss, boss.core()] as Array[Area2D]:
		assert_eq(area.collision_layer, CollisionLayers.ENEMIES, "%s on the enemies layer" % area.name)
		assert_eq(area.collision_mask, 0, "%s mask 0" % area.name)
	for turret: FlagshipTurret in boss.turrets():
		assert_eq(turret.type_id, &"flagship_turret")
		assert_eq(turret.hp, 25)
		assert_eq(turret.tier, ImpactTier.BOSS_PART)
		assert_eq(turret.sprite_px, Config.num("boss.turrets.sprite_px"))
		assert_eq(turret.collision_layer, CollisionLayers.ENEMIES)
		assert_eq(turret.collision_mask, 0)
		assert_eq(turret.spawner, _spawner, "the hull hands its spawner to the turret")
		assert_false(turret.invulnerable)
		assert_false(turret.is_firing(), "idle while arriving")
	var core: FlagshipCore = boss.core()
	assert_not_null(core)
	assert_eq(core.type_id, &"flagship_core")
	assert_eq(core.hp, 200)
	assert_eq(core.tier, ImpactTier.BOSS_DEATH)
	assert_true(core.invulnerable, "the core starts invulnerable")
	assert_eq(core.spawner, _spawner)
	assert_eq(boss.max_hp(), 300, "4 x 25 + 200")
	assert_eq(boss.current_hp(), 300)
	assert_eq(_logged("[WARN]"), [] as Array[String], "no warning")


func test_spawn_emits_started_arriving_and_full_hp() -> void:
	var boss: Flagship = _spawn()
	assert_eq(_events, [
		["boss_started"],
		["boss_phase_changed", 0],
		["boss_hp_changed", 300, 300, 0],
	] as Array[Array])
	assert_eq(boss.phase(), Flagship.Phase.ARRIVING)
	assert_eq(boss.global_position, Vector2(960, Config.num("boss.hull.arrive_from_y")))


func test_phase_enum_order() -> void:
	assert_eq(Flagship.Phase.keys(), ["ARRIVING", "TURRETS", "CORE", "FINAL_CHOICE", "DESPERATE", "DYING"])
	assert_eq(int(Flagship.Phase.CORE), 2, "Story 7.4 relies on CORE being 2")


# --- Arrival -------------------------------------------------------------------

func test_arrives_at_its_station_over_arrival_s_then_turrets() -> void:
	var boss: Flagship = _spawn()
	var from_y: float = Config.num("boss.hull.arrive_from_y")
	var station_y: float = Config.num("boss.hull.station_y")
	var arrival_s: float = Config.num("boss.hull.arrival_s")
	_events.clear()
	var t: float = 0.0
	var half_checked: bool = false
	while boss.phase() == Flagship.Phase.ARRIVING and t < arrival_s + 1.0:
		boss.step(DT)
		t += DT
		assert_eq(boss.global_position.x, 960.0, "straight down the centre")
		if not half_checked and t >= arrival_s / 2.0:
			half_checked = true
			assert_almost_eq(boss.global_position.y, lerpf(from_y, station_y, t / arrival_s), 0.01, "linear over arrival_s")
		if boss.phase() == Flagship.Phase.ARRIVING:
			for turret: FlagshipTurret in boss.turrets():
				assert_false(turret.is_firing(), "no turret fires while arriving")
	assert_almost_eq(t, arrival_s, DT + EPS, "arrives after arrival_s")
	assert_eq(boss.global_position, Vector2(960, station_y), "at its station")
	assert_eq(_events, [["boss_phase_changed", 1], ["boss_hp_changed", 300, 300, 1]] as Array[Array])
	for turret: FlagshipTurret in boss.turrets():
		assert_true(turret.is_firing(), "every turret's cycle started")


# --- Turret cadence ----------------------------------------------------------------

func test_staggered_start_to_start_cadence_and_glow_window() -> void:
	var boss: Flagship = _spawn_at_station()
	var interval: float = Config.num("boss.turrets.fire_interval_s")
	var stagger: float = Config.num("boss.turrets.stagger_s")
	var telegraph: float = Config.num("boss.turrets.telegraph_s")
	assert_eq([interval, stagger, telegraph], [3.0, 0.75, 0.5], "shipped cadence")
	var turrets: Array[FlagshipTurret] = boss.turrets()
	var shots: Array = [[], [], [], []]
	## [t, turret index, glowing] samples, taken after each step.
	var samples: Array[Array] = []
	var seen: int = 0
	var t: float = 0.0
	var duration: float = 9.4
	while t < duration:
		boss.step(DT)
		t += DT
		var bullets: Array[Projectile] = _bullets()
		var fresh: Array[Projectile] = bullets.slice(seen)
		seen = bullets.size()
		for i: int in turrets.size():
			var from_turret: int = 0
			for b: Projectile in fresh:
				if is_equal_approx(b.global_position.x, turrets[i].global_position.x):
					from_turret += 1
			if from_turret > 0:
				assert_eq(from_turret, 3, "turret %d fires 3 bullets per shot" % i)
				(shots[i] as Array).append(t)
			samples.append([t, i, turrets[i].is_glowing()])
	for i: int in turrets.size():
		var expected: Array[float] = []
		var k: int = 0
		while float(i) * stagger + interval + float(k) * interval <= duration:
			expected.append(float(i) * stagger + interval + float(k) * interval)
			k += 1
		var got: Array = shots[i]
		assert_eq(got.size(), expected.size(), "turret %d shot count by %.1f s" % [i, duration])
		for n: int in mini(got.size(), expected.size()):
			assert_almost_eq(float(got[n]), expected[n], DT + EPS, "turret %d shot %d at i*stagger + interval + k*interval" % [i, n])
	# The glow shows only in the telegraph_s before each shot (samples near the
	# window edges are skipped: they depend on the tick grid).
	var checked: int = 0
	for sample: Array in samples:
		var st: float = sample[0]
		var i: int = sample[1]
		var first: float = float(i) * stagger + interval
		var next_shot: float = INF
		var k: int = 0
		while first + float(k) * interval <= duration + interval:
			var shot: float = first + float(k) * interval
			if shot > st + EPS:
				next_shot = shot
				break
			k += 1
		var lead: float = next_shot - st
		if absf(lead - telegraph) < 2.0 * DT or lead < 2.0 * DT or absf(lead - interval) < 2.0 * DT:
			continue
		checked += 1
		var in_window: bool = lead < telegraph and st >= float(i) * stagger
		assert_eq(sample[2], in_window, "turret %d glow at %.3f s (next shot in %.3f s)" % [i, st, lead])
	assert_gt(checked, 1000, "the glow was checked across the run")


func test_spread_is_three_unaimed_bullets_at_350() -> void:
	var boss: Flagship = _spawn_at_station()
	var turret: FlagshipTurret = boss.turrets()[0]
	var t: float = 0.0
	while _bullets().is_empty() and t < 4.0:
		boss.step(DT)
		t += DT
	var bullets: Array[Projectile] = _bullets()
	assert_eq(bullets.size(), 3, "turret 0 fires first, alone")
	var angles: Array[float] = []
	for b: Projectile in bullets:
		assert_eq(b.global_position, turret.global_position, "from the turret")
		assert_almost_eq(b.velocity.length(), 350.0, 0.01, "350 px/s")
		assert_eq(b.damage, Config.int_("damage.bullet_hearts"))
		angles.append(_deg_from_down(b.velocity))
	angles.sort()
	assert_almost_eq(angles[0], -15.0, 0.01)
	assert_almost_eq(angles[1], 0.0, 0.01)
	assert_almost_eq(angles[2], 15.0, 0.01)


func test_spread_velocities_helper() -> void:
	var one: PackedVector2Array = FlagshipTurret.spread_velocities(1, 15.0, 100.0)
	assert_eq(one.size(), 1)
	assert_almost_eq(one[0].x, 0.0, EPS, "one bullet flies straight down")
	assert_almost_eq(one[0].y, 100.0, EPS)


func test_without_a_spawner_the_cycle_runs_but_never_fires() -> void:
	var boss: Flagship = FLAGSHIP_SCENE.instantiate() as Flagship
	add_child_autofree(boss)
	boss.set_physics_process(false)
	boss.step(Config.num("boss.hull.arrival_s"))
	var glowed: bool = false
	var t: float = 0.0
	while t < 7.0:
		boss.step(DT)
		t += DT
		glowed = glowed or boss.turrets()[0].is_glowing()
	assert_true(glowed, "the cycle runs (the glow showed)")
	assert_eq(boss.phase(), Flagship.Phase.TURRETS)
	assert_eq(_logged("[ERROR]"), [] as Array[String], "no error")


# --- Damage --------------------------------------------------------------------

func test_hit_on_a_turret_lowers_the_combined_hp() -> void:
	var boss: Flagship = _spawn_at_station()
	_events.clear()
	var turret: FlagshipTurret = boss.turrets()[1]
	turret.apply_damage(10, null)
	assert_eq(turret.hp, 15)
	assert_eq(_events, [["boss_hp_changed", 290, 300, 1]] as Array[Array])
	assert_eq(boss.current_hp(), 290)


func test_hull_and_invulnerable_core_ignore_damage() -> void:
	var boss: Flagship = _spawn_at_station()
	_events.clear()
	boss.apply_damage(10, null)
	boss.core().apply_damage(10, null)
	assert_eq(boss.core().hp, 200, "core hp unchanged")
	assert_eq(boss.current_hp(), 300)
	assert_eq(_events, [] as Array[Array], "no event")
	assert_false(boss.is_dead())
	assert_false(boss.core().is_dead())


func test_shots_on_the_hull_and_core_are_spent() -> void:
	var boss: Flagship = _spawn_at_station()
	_events.clear()
	for target: Area2D in [boss, boss.core()] as Array[Area2D]:
		var bolt: Projectile = _spawner.spawn_projectile(&"laser_bolt", {"position": Vector2(100, 900), "velocity": Vector2(0, -100)})
		bolt.set_physics_process(false)
		bolt._on_area_entered(target)
		assert_true(bolt.is_queued_for_deletion(), "the shot on %s is spent" % target.name)
	assert_eq(boss.current_hp(), 300)
	assert_eq(_events_named("boss_hp_changed"), [] as Array[Array])


func test_turret_death_plays_the_boss_part_tier_and_drops_an_orb() -> void:
	var boss: Flagship = _spawn_at_station()
	_events.clear()
	var turret: FlagshipTurret = boss.turrets()[0]
	var pos: Vector2 = turret.global_position
	turret.apply_damage(30, null)
	assert_true(turret.is_dead(), "turret destroyed")
	var e: Explosion = _newest_explosion()
	assert_not_null(e, "an explosion")
	if e != null:
		assert_eq(e.scale, Vector2(1.5, 1.5), "Boss-part explosion 1.5x")
		assert_eq(e.global_position, pos)
	assert_almost_eq(_camera.current_amplitude(), 6.0, EPS, "6 px shake")
	assert_true(Feedback.is_hit_stopped(), "30 ms hit-stop")
	assert_eq(_events_named("enemy_killed"), [["enemy_killed", &"flagship_turret", pos, false]] as Array[Array])
	assert_eq(_events_named("boss_hp_changed"), [["boss_hp_changed", 275, 300, 1]] as Array[Array], "overkill-free: 300 - 25")
	await wait_physics_frames(2)
	var orbs: int = 0
	for child: Node in _pickups.get_children():
		if child is EnergyOrb:
			orbs += 1
	assert_eq(orbs, 1, "a turret always drops one orb")
	assert_eq(boss.current_hp(), 275, "the freed turret counts 0")


func test_all_turrets_dead_logs_once_and_stays_in_turrets() -> void:
	var boss: Flagship = _spawn_at_station()
	for turret: FlagshipTurret in boss.turrets():
		turret.apply_damage(25, null)
	assert_eq(boss.live_turret_count(), 0)
	assert_eq(_logged("[INFO][combat] Flagship: all turrets destroyed").size(), 1, "one INFO line")
	assert_eq(boss.phase(), Flagship.Phase.TURRETS, "no CORE phase in Story 7.3")
	assert_eq(boss.current_hp(), 200)
	assert_eq(_events_named("boss_hp_changed").back(), ["boss_hp_changed", 200, 300, 1])
	await wait_physics_frames(2)
	for i: int in 300:
		boss.step(DT)
	assert_eq(boss.phase(), Flagship.Phase.TURRETS)
	assert_eq(_logged("all turrets destroyed").size(), 1, "still once")
	assert_eq(_events_named("boss_defeated"), [] as Array[Array], "no boss_defeated")
	assert_true(boss.core().invulnerable, "the core stays invulnerable")


# --- Geometry, contact and targeting --------------------------------------------

func test_no_part_hitbox_overlaps_the_hull() -> void:
	var boss: Flagship = _spawn_at_station()
	var hull: CollisionShape2D = boss.get_node("Hitbox") as CollisionShape2D
	var rect: RectangleShape2D = hull.shape as RectangleShape2D
	assert_not_null(rect, "the hull hitbox is a rect")
	if rect == null:
		return
	assert_eq(rect.size, Vector2(720, 160))
	var parts: Array[FlagshipPart] = []
	parts.assign(boss.turrets())
	parts.append(boss.core())
	for part: FlagshipPart in parts:
		var hitbox: CollisionShape2D = part.get_node("Hitbox") as CollisionShape2D
		var circle: CircleShape2D = hitbox.shape as CircleShape2D
		assert_not_null(circle, "%s hitbox is a circle" % part.name)
		if circle == null:
			continue
		var section: String = "boss.core" if part == boss.core() else "boss.turrets"
		assert_almost_eq(circle.radius, Config.num(section + ".sprite_px") / 2.0 * Config.num(section + ".hitbox_ratio"), EPS)
		assert_false(rect.collide(hull.global_transform, circle, hitbox.global_transform), "%s doesn't overlap the hull" % part.name)
		assert_gt(part.global_position.y - circle.radius, boss.global_position.y + rect.size.y / 2.0, "%s hangs below the hull" % part.name)
		assert_lte(part.global_position.y + circle.radius, 432.0, "%s inside the enemy zone" % part.name)


func test_contact_never_destroys_the_hull_or_a_part() -> void:
	var boss: Flagship = _spawn_at_station()
	boss.destroy_by_contact()
	boss.turrets()[0].destroy_by_contact()
	boss.core().destroy_by_contact()
	assert_false(boss.is_dead())
	assert_false(boss.turrets()[0].is_dead())
	assert_false(boss.core().is_dead())
	assert_eq(_events_named("enemy_killed"), [] as Array[Array])


func test_only_turrets_are_targets() -> void:
	var boss: Flagship = _spawn_at_station()
	assert_false(boss.is_targetable(), "hull")
	assert_false(boss.core().is_targetable(), "invulnerable core")
	for turret: FlagshipTurret in boss.turrets():
		assert_true(turret.is_targetable(), "turret")
	var below_core: Vector2 = boss.core().global_position + Vector2(0, 300)
	var nodes: Array[Node] = get_tree().get_nodes_in_group(&"enemies")
	var missile_pick: Node2D = MicroMissile.nearest_enemy(below_core, nodes)
	var ally_pick: Enemy = AllyShip.nearest_target(below_core, nodes)
	assert_true(missile_pick is FlagshipTurret, "a micro-missile picks a turret, not the core or hull")
	assert_true(ally_pick is FlagshipTurret, "the ally picks a turret, not the core or hull")
	for turret: FlagshipTurret in boss.turrets():
		turret.apply_damage(25, null)
	await wait_physics_frames(2)
	nodes = get_tree().get_nodes_in_group(&"enemies")
	assert_null(MicroMissile.nearest_enemy(below_core, nodes), "no target left: hull and core are skipped")
	assert_null(AllyShip.nearest_target(below_core, nodes))
