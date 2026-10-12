extends GutTest
## Flagship Phases 1 and 2 (Stories 7.3 and 7.4, FR49, FR50, FR52, FR53):
## spawned through a real Spawner into a fixture world (Enemies, Projectiles,
## Effects, Pickups) and driven through step(delta) with physics processing off.
## Phase 1: the arrival, the staggered start-to-start turret cadence (shot
## times, glow window, spread angles and speed), part, hull and core damage,
## turret death (Boss-part tier, enemy_killed, the orb), the combined HP events,
## hitbox layout, contact and targeting. Phase 2: the move to CORE when the 4th
## turret dies, core damage, the core's start-to-start radial cadence and glow,
## the 12-bullet radial burst, the Wasp launches (slots, cap, not counted,
## drops), leaving CORE and targeting. Phase 3 (Story 7.5): the 50 HP clamp
## into FINAL_CHOICE and its comms request, the wait for its own `finished`,
## DESPERATE (the alternating radials, the aimed spread, the shared glow, the
## red pulse, targeting) and the core's death: DYING, Feedback.boss_death and
## boss_defeated after the chain.

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
## Every Events.comms_sequence_requested id.
var _requests: Array[StringName] = []


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
	_requests.clear()
	Events.comms_sequence_requested.connect(_on_requested)


func after_each() -> void:
	for signal_name: String in _recorders:
		Events.disconnect(signal_name, _recorders[signal_name])
	_recorders = {}
	Events.comms_sequence_requested.disconnect(_on_requested)
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


func _on_requested(id: StringName) -> void:
	_requests.append(id)


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


## A Flagship at its station with every turret destroyed (CORE, Story 7.4).
## Clears the recorded events and log lines.
func _spawn_in_core() -> Flagship:
	var boss: Flagship = _spawn_at_station()
	for turret: FlagshipTurret in boss.turrets():
		turret.apply_damage(turret.hp, null)
	assert_eq(boss.phase(), Flagship.Phase.CORE, "in CORE")
	_events.clear()
	_lines.clear()
	return boss


## A Flagship in CORE whose core was clamped to 50 (FINAL_CHOICE, Story 7.5).
## Clears the recorded events, requests and log lines.
func _spawn_in_final_choice() -> Flagship:
	var boss: Flagship = _spawn_in_core()
	boss.core().apply_damage(boss.core().hp, null)
	assert_eq(boss.phase(), Flagship.Phase.FINAL_CHOICE, "in FINAL_CHOICE")
	_events.clear()
	_requests.clear()
	_lines.clear()
	return boss


## A Flagship in DESPERATE (its Final Choice finished). Clears the recorded
## events and log lines.
func _spawn_in_desperate() -> Flagship:
	var boss: Flagship = _spawn_in_final_choice()
	Events.comms_sequence_finished.emit(Flagship.FINAL_CHOICE_SEQUENCE)
	assert_eq(boss.phase(), Flagship.Phase.DESPERATE, "in DESPERATE")
	_events.clear()
	_lines.clear()
	return boss


## A stand-in player at `pos` (in the player group, for _aim_from).
func _add_player(pos: Vector2) -> Node2D:
	var player: Node2D = Node2D.new()
	player.add_to_group(&"player")
	add_child_autofree(player)
	player.global_position = pos
	return player


## Explosions under World/Effects not queued for deletion.
func _live_explosions() -> Array[Explosion]:
	var out: Array[Explosion] = []
	for child: Node in _effects.get_children():
		var e: Explosion = child as Explosion
		if e != null and not e.is_queued_for_deletion():
			out.append(e)
	return out


## Steps the Flagship `seconds` at DT (rounded to whole ticks).
func _step_for(boss: Flagship, seconds: float) -> void:
	for i: int in roundi(seconds / DT):
		boss.step(DT)


## Live boss-launched Wasps (Groups.BOSS_WASPS), physics off on each.
func _launched() -> Array[Wasp]:
	var out: Array[Wasp] = []
	for node: Node in get_tree().get_nodes_in_group(&"boss_wasps"):
		var wasp: Wasp = node as Wasp
		if wasp != null and not wasp.is_dead() and not wasp.is_queued_for_deletion():
			wasp.set_physics_process(false)
			out.append(wasp)
	return out


## The 10 documented boss Wasp slots (decision #55), in fill order.
func _expected_slots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for y: float in [370.0, 430.0]:
		for x: float in [640.0, 800.0, 960.0, 1120.0, 1280.0]:
			out.append(Vector2(x, y))
	return out


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


## Story 7.4: turrets that all die while ARRIVING don't stop the arrival; its
## end enters CORE instead of TURRETS.
func test_turrets_killed_while_arriving_enter_core_at_the_station() -> void:
	var boss: Flagship = _spawn()
	var arrival_s: float = Config.num("boss.hull.arrival_s")
	var station: Vector2 = Vector2(960, Config.num("boss.hull.station_y"))
	_step_for(boss, arrival_s / 2.0)
	assert_eq(boss.phase(), Flagship.Phase.ARRIVING)
	_events.clear()
	for turret: FlagshipTurret in boss.turrets():
		turret.apply_damage(turret.hp, null)
	assert_eq(boss.live_turret_count(), 0)
	assert_eq(boss.phase(), Flagship.Phase.ARRIVING, "still arriving")
	assert_eq(_logged("[INFO][combat] Flagship: all turrets destroyed").size(), 1, "one INFO line")
	var y: float = boss.global_position.y
	boss.step(DT)
	assert_gt(boss.global_position.y, y, "still moving down")
	var t: float = DT
	while boss.phase() == Flagship.Phase.ARRIVING and t < arrival_s:
		boss.step(DT)
		t += DT
	assert_eq(boss.global_position, station, "at its station")
	assert_eq(boss.phase(), Flagship.Phase.CORE, "the arrival ends in CORE")
	assert_eq(_events_named("boss_phase_changed"), [["boss_phase_changed", 2]] as Array[Array], "CORE once, never TURRETS")
	assert_false(boss.core().invulnerable, "the core is exposed")
	assert_true(boss.core().is_attacking(), "and attacking")
	assert_eq(_logged("all turrets destroyed").size(), 1, "still once")


## Story 7.4: the 4th turret's death moves the Flagship to CORE at once.
func test_fourth_turret_death_enters_core() -> void:
	var boss: Flagship = _spawn_at_station()
	var turrets: Array[FlagshipTurret] = boss.turrets()
	for i: int in 3:
		turrets[i].apply_damage(25, null)
	assert_eq(boss.phase(), Flagship.Phase.TURRETS, "3 turrets down: still TURRETS")
	assert_true(boss.core().invulnerable)
	_events.clear()
	turrets[3].apply_damage(25, null)
	assert_eq(boss.live_turret_count(), 0)
	assert_eq(boss.phase(), Flagship.Phase.CORE, "the 4th turret's death enters CORE")
	assert_eq(_events_named("boss_phase_changed"), [["boss_phase_changed", 2]] as Array[Array])
	assert_eq(_events_named("boss_hp_changed").back(), ["boss_hp_changed", 200, 300, 2])
	assert_eq(_logged("[INFO][combat] Flagship: all turrets destroyed").size(), 1, "one INFO line")
	assert_false(boss.core().invulnerable, "the core is exposed")
	assert_true(boss.core().is_targetable(), "and targetable")
	assert_true(boss.core().is_attacking(), "the core cycle started")
	assert_eq(boss.current_hp(), 200)
	await wait_physics_frames(2)
	for i: int in 300:
		boss.step(DT)
	assert_eq(boss.phase(), Flagship.Phase.CORE)
	assert_eq(_logged("all turrets destroyed").size(), 1, "still once")
	assert_eq(_events_named("boss_phase_changed").size(), 1, "CORE entered once")
	assert_eq(_events_named("boss_defeated"), [] as Array[Array], "no boss_defeated")


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

## Story 7.4: in CORE the exposed core is the target; the hull never is.
func test_in_core_the_core_is_the_target() -> void:
	var boss: Flagship = _spawn_in_core()
	await wait_physics_frames(2)
	assert_true(boss.core().is_targetable(), "exposed core")
	assert_false(boss.is_targetable(), "hull")
	var below_core: Vector2 = boss.core().global_position + Vector2(0, 300)
	var far_side: Vector2 = Vector2(100, 900)
	var nodes: Array[Node] = get_tree().get_nodes_in_group(&"enemies")
	for from: Vector2 in [below_core, far_side]:
		assert_eq(MicroMissile.nearest_enemy(from, nodes), boss.core(), "a micro-missile picks the core")
		assert_eq(AllyShip.nearest_target(from, nodes), boss.core(), "the ally picks the core")


# --- Phase 2: the exposed core (Story 7.4) -------------------------------------------

func test_hit_on_the_core_in_core() -> void:
	var boss: Flagship = _spawn_in_core()
	boss.core().apply_damage(10, null)
	assert_eq(boss.core().hp, 190, "core 190")
	assert_eq(_events, [["boss_hp_changed", 190, 300, 2]] as Array[Array])
	assert_eq(boss.current_hp(), 190)


func test_core_start_to_start_cadence_and_glow_window() -> void:
	var boss: Flagship = _spawn_in_core()
	var interval: float = Config.num("boss.core.radial_interval_s")
	var charge: float = Config.num("boss.core.charge_s")
	assert_eq([interval, charge], [3.0, 0.6], "shipped cadence")
	var core: FlagshipCore = boss.core()
	var shots: Array[float] = []
	## [t, glowing] samples, taken after each step.
	var samples: Array[Array] = []
	var seen: int = 0
	var t: float = 0.0
	var duration: float = 9.4
	while t < duration:
		boss.step(DT)
		t += DT
		var bullets: Array[Projectile] = _bullets()
		var fresh: int = bullets.size() - seen
		seen = bullets.size()
		if fresh > 0:
			assert_eq(fresh, 12, "12 bullets per burst")
			shots.append(t)
		samples.append([t, core.is_glowing()])
	assert_eq(shots.size(), 3, "3 bursts by %.1f s" % duration)
	for k: int in shots.size():
		assert_almost_eq(shots[k], interval + float(k) * interval, DT + EPS, "burst %d at interval + k*interval (one full period after CORE)" % k)
	var checked: int = 0
	for sample: Array in samples:
		var st: float = sample[0]
		var next_shot: float = (floorf(st / interval + EPS) + 1.0) * interval
		var lead: float = next_shot - st
		if absf(lead - charge) < 2.0 * DT or lead < 2.0 * DT or absf(lead - interval) < 2.0 * DT:
			continue
		checked += 1
		assert_eq(sample[1], lead < charge, "core glow at %.3f s (next burst in %.3f s)" % [st, lead])
	assert_gt(checked, 400, "the glow was checked across the run")


func test_radial_burst_is_12_bullets_30_degrees_apart_at_300() -> void:
	var boss: Flagship = _spawn_in_core()
	var t: float = 0.0
	while _bullets().is_empty() and t < 4.0:
		boss.step(DT)
		t += DT
	var bullets: Array[Projectile] = _bullets()
	assert_eq(bullets.size(), 12, "one 12-bullet burst")
	var angles: Array[float] = []
	for b: Projectile in bullets:
		assert_eq(b.global_position, boss.core().global_position, "from the core centre")
		assert_almost_eq(b.velocity.length(), 300.0, 0.01, "300 px/s")
		assert_eq(b.damage, Config.int_("damage.bullet_hearts"))
		angles.append(fposmod(_deg_from_down(b.velocity) + 0.001, 360.0) - 0.001)
	angles.sort()
	for i: int in angles.size():
		assert_almost_eq(angles[i], 30.0 * float(i), 0.01, "bullet %d at %d degrees from straight down" % [i, 30 * i])


func test_radial_velocities_helper() -> void:
	var twelve: PackedVector2Array = FlagshipCore.radial_velocities(12, 300.0)
	assert_eq(twelve.size(), 12)
	assert_almost_eq(twelve[0].x, 0.0, EPS, "the first bullet flies straight down")
	assert_almost_eq(twelve[0].y, 300.0, EPS)
	assert_almost_eq(_deg_from_down(twelve[1]), 30.0, 0.001, "the next one 30 degrees on")
	for v: Vector2 in twelve:
		assert_almost_eq(v.length(), 300.0, 0.001)
	var one: PackedVector2Array = FlagshipCore.radial_velocities(1, 100.0)
	assert_eq(one.size(), 1)
	assert_almost_eq(one[0].y, 100.0, EPS)
	assert_eq(FlagshipCore.radial_velocities(0, 100.0).size(), 0)


func test_first_launch_sends_five_wasps_from_the_core_to_slots_0_to_4() -> void:
	var boss: Flagship = _spawn_in_core()
	var interval: float = Config.num("boss.core.wasp_launch_interval_s")
	assert_eq(interval, 10.0, "shipped launch interval")
	var origin: Vector2 = boss.core().global_position
	_step_for(boss, interval - 2.0 * DT)
	assert_eq(_launched().size(), 0, "nothing before 10 s")
	_step_for(boss, 3.0 * DT)
	var wasps: Array[Wasp] = _launched()
	assert_eq(wasps.size(), 5, "5 Wasps at 10 s")
	var slots: Array[Vector2] = _expected_slots()
	assert_eq(slots.size(), 10, "10 boss slots")
	for i: int in wasps.size():
		var wasp: Wasp = wasps[i]
		assert_eq(wasp.type_id, &"wasp")
		assert_eq(wasp.get_parent(), _world.get_node("Enemies"), "spawned through the Spawner")
		assert_eq(wasp.spawner, _spawner)
		assert_true(wasp.is_in_group(&"boss_wasps"), "in Groups.BOSS_WASPS")
		assert_false(wasp.is_in_group(&"counted"), "never counted")
		assert_eq(wasp.formation_slot(), slots[i], "slot %d" % i)
		assert_eq(wasp.state(), Wasp.State.ENTER)
		assert_eq(wasp.global_position, origin, "flies out of the core centre")
	for wasp: Wasp in wasps:
		var t: float = 0.0
		while wasp.state() != Wasp.State.HOLD and t < 3.0:
			wasp.step(DT)
			t += DT
		assert_eq(wasp.state(), Wasp.State.HOLD, "reached its slot")
		assert_eq(wasp.global_position, wasp.formation_slot())
	assert_eq(_logged("[WARN]"), [] as Array[String], "no slot clamp or other warning")


func test_dive_clock_picks_a_launched_wasp_holding_its_slot() -> void:
	var boss: Flagship = _spawn_in_core()
	_step_for(boss, Config.num("boss.core.wasp_launch_interval_s") + DT)
	var wasps: Array[Wasp] = _launched()
	assert_eq(wasps.size(), 5)
	var wasp: Wasp = wasps[0]
	var t: float = 0.0
	while wasp.state() != Wasp.State.HOLD and t < 3.0:
		wasp.step(DT)
		t += DT
	assert_eq(wasp.state(), Wasp.State.HOLD, "reached its slot")
	for other: Wasp in wasps.slice(1):
		assert_eq(other.state(), Wasp.State.ENTER, "the others are still entering")
	var clock: WaspDiveClock = WaspDiveClock.new()
	add_child_autofree(clock)
	clock.set_physics_process(false)
	clock.step(clock.time_left() + DT)
	assert_eq(wasp.state(), Wasp.State.TELEGRAPH, "the dive clock picked the boss-launched Wasp")


func test_launches_never_exceed_the_cap_and_refill_freed_slots() -> void:
	var boss: Flagship = _spawn_in_core()
	assert_eq(Config.int_("boss.core.wasp_launch_count"), 5)
	assert_eq(Config.int_("boss.core.wasp_max_alive"), 10)
	var slots: Array[Vector2] = _expected_slots()
	var t: float = 0.0
	var max_seen: int = 0
	var killed: bool = false
	var at_20: int = -1
	var at_30: Array[Wasp] = []
	while t < 45.0:
		boss.step(DT)
		t += DT
		var alive: int = _launched().size()
		max_seen = maxi(max_seen, alive)
		if at_20 < 0 and t >= 20.5:
			at_20 = alive
		if not killed and t >= 25.0:
			killed = true
			for wasp: Wasp in _launched():
				if wasp.formation_slot() in [slots[1], slots[5], slots[7]]:
					wasp.apply_damage(wasp.hp, null)
			assert_eq(_launched().size(), 7, "3 killed")
		if at_30.is_empty() and t >= 30.5:
			at_30 = _launched()
	assert_eq(at_20, 10, "20 s: 5 more (10 alive)")
	assert_eq(at_30.size(), 10, "30 s: 3 into the freed slots (10 alive)")
	var taken: Array[Vector2] = []
	for wasp: Wasp in at_30:
		assert_false(wasp.formation_slot() in taken, "one Wasp per slot")
		taken.append(wasp.formation_slot())
	for slot: Vector2 in slots:
		assert_true(slot in taken, "slot %s filled" % slot)
	assert_eq(max_seen, 10, "never more than 10 alive")
	assert_eq(_launched().size(), 10, "40 s: the cap holds, nothing launched")


func test_launched_wasp_kill_uses_the_wasp_drop_table() -> void:
	var boss: Flagship = _spawn_in_core()
	await wait_physics_frames(2)
	for child: Node in _pickups.get_children():
		child.queue_free()
	await wait_physics_frames(1)
	((Config.tuning["drops"] as Dictionary)["wasp"] as Dictionary)["chance"] = 1.0
	_step_for(boss, Config.num("boss.core.wasp_launch_interval_s") + DT)
	var wasp: Wasp = _launched()[0]
	var pos: Vector2 = wasp.global_position
	_events.clear()
	wasp.apply_damage(wasp.hp, null)
	assert_eq(_events_named("enemy_killed"), [["enemy_killed", &"wasp", pos, false]] as Array[Array])
	assert_eq(_events_named("boss_hp_changed"), [] as Array[Array], "a Wasp kill is not boss damage")
	await wait_physics_frames(2)
	var orbs: int = 0
	for child: Node in _pickups.get_children():
		if child is EnergyOrb and not child.is_queued_for_deletion():
			orbs += 1
	assert_eq(orbs, Config.int_("drops.wasp.orbs"), "rolled on drops.wasp")


func test_leaving_core_stops_shots_and_launches_and_keeps_the_wasps() -> void:
	var boss: Flagship = _spawn_in_core()
	_step_for(boss, 11.5)
	var wasps: Array[Wasp] = _launched()
	assert_eq(wasps.size(), 5)
	assert_true(boss.core().is_glowing(), "charging before the 12 s burst")
	boss._enter_phase(Flagship.Phase.FINAL_CHOICE)
	assert_false(boss.core().is_glowing(), "the glow is off")
	assert_false(boss.core().is_attacking())
	var bullets: int = _bullets().size()
	_step_for(boss, 30.0)
	assert_eq(_bullets().size(), bullets, "no more core shots")
	assert_eq(_launched().size(), 5, "no more launches; the live Wasps stay")
	for wasp: Wasp in wasps:
		assert_true(is_instance_valid(wasp) and not wasp.is_dead(), "launched Wasp still alive")
	assert_false(boss.core().is_glowing())


# --- Phase 3: the Final Choice, DESPERATE and DYING (Story 7.5) -----------------------

## Story 7.5: the shipped Phase 3 numbers these tests rely on.
func test_phase_3_tuning_used_here() -> void:
	assert_eq(Config.int_("boss.final_choice_hp"), 50)
	assert_eq(Config.num("boss.desperate.radial_interval_s"), 1.5)
	assert_eq(Config.num("boss.desperate.aimed_interval_s"), 2.0)
	assert_eq(Config.int_("boss.desperate.radial_bullets"), 12)
	assert_eq(Config.int_("boss.desperate.radial_bursts"), 2)
	assert_eq(Config.num("feedback.boss_death_chain_s"), 2.0)
	assert_eq(Flagship.FINAL_CHOICE_SEQUENCE, &"l3_final_choice")


func test_clamp_a_999_hit_from_60_to_exactly_50_and_final_choice() -> void:
	var boss: Flagship = _spawn_in_core()
	var core: FlagshipCore = boss.core()
	core.apply_damage(140, null)
	assert_eq(core.hp, 60, "a plain hit above the floor")
	assert_eq(boss.phase(), Flagship.Phase.CORE)
	_events.clear()
	_requests.clear()
	core.apply_damage(999, null)
	_assert_clamped_into_final_choice(boss)


func test_clamp_an_exact_hit_from_55() -> void:
	var boss: Flagship = _spawn_in_core()
	var core: FlagshipCore = boss.core()
	core.apply_damage(145, null)
	assert_eq(core.hp, 55)
	_events.clear()
	_requests.clear()
	core.apply_damage(5, null)
	_assert_clamped_into_final_choice(boss)


func _assert_clamped_into_final_choice(boss: Flagship) -> void:
	var core: FlagshipCore = boss.core()
	assert_eq(core.hp, 50, "clamped to exactly 50")
	assert_false(core.is_dead(), "never a kill")
	assert_true(core.invulnerable, "invulnerable")
	assert_false(core.is_targetable(), "no target")
	assert_eq(core.hp_floor(), 0, "the floor is spent")
	assert_eq(boss.phase(), Flagship.Phase.FINAL_CHOICE, "FINAL_CHOICE")
	assert_eq(_events, [
		["boss_hp_changed", 50, 300, 2],
		["boss_phase_changed", 3],
		["boss_hp_changed", 50, 300, 3],
	] as Array[Array], "the hp change, then the phase entry")
	assert_eq(_requests, [&"l3_final_choice"] as Array[StringName], "l3_final_choice requested once")
	assert_false(core.is_attacking(), "the core attack stopped")
	assert_false(core.is_glowing())
	assert_eq(_events_named("enemy_killed"), [] as Array[Array])
	assert_eq(_events_named("boss_defeated"), [] as Array[Array])


func test_a_hit_above_the_floor_stays_in_core() -> void:
	var boss: Flagship = _spawn_in_core()
	boss.core().apply_damage(149, null)
	assert_eq(boss.core().hp, 51, "core 51")
	assert_false(boss.core().invulnerable)
	assert_eq(boss.phase(), Flagship.Phase.CORE, "still CORE")
	assert_eq(_requests, [] as Array[StringName], "nothing requested")
	assert_eq(boss.core().hp_floor(), 50, "the floor is still armed")


func test_final_choice_waits_for_its_own_finished() -> void:
	var boss: Flagship = _spawn_in_core()
	_step_for(boss, 1.0)
	var core: FlagshipCore = boss.core()
	core.apply_damage(150, null)
	assert_eq(boss.phase(), Flagship.Phase.FINAL_CHOICE)
	var bullets: int = _bullets().size()
	var wasps: int = _launched().size()
	_events.clear()
	Events.comms_sequence_finished.emit(&"other")
	Events.comms_sequence_finished.emit(&"l3_isolde_refuse_destroy")
	for i: int in 600:
		boss.step(DT)
	assert_eq(boss.phase(), Flagship.Phase.FINAL_CHOICE, "still FINAL_CHOICE")
	assert_eq(_bullets().size(), bullets, "no core shots")
	assert_eq(_launched().size(), wasps, "no launches")
	assert_false(core.is_glowing(), "no charge glow")
	core.apply_damage(10, null)
	assert_eq(core.hp, 50, "the core ignores damage")
	assert_eq(_events, [] as Array[Array], "nothing emitted")


func test_finished_outside_final_choice_is_ignored() -> void:
	var boss: Flagship = _spawn_in_core()
	Events.comms_sequence_finished.emit(&"l3_final_choice")
	assert_eq(boss.phase(), Flagship.Phase.CORE, "CORE ignores it")
	assert_eq(_events_named("boss_phase_changed"), [] as Array[Array])


func test_final_choice_finished_enters_desperate_once() -> void:
	var boss: Flagship = _spawn_in_final_choice()
	Events.comms_sequence_finished.emit(&"l3_final_choice")
	assert_eq(boss.phase(), Flagship.Phase.DESPERATE, "DESPERATE")
	assert_eq(_events, [["boss_phase_changed", 4], ["boss_hp_changed", 50, 300, 4]] as Array[Array])
	var core: FlagshipCore = boss.core()
	assert_false(core.invulnerable, "the core is vulnerable again")
	assert_true(core.is_targetable(), "and targetable")
	assert_true(core.is_desperate(), "the desperate cycles run")
	assert_true(core.is_pulsing(), "the red pulse")
	Events.comms_sequence_finished.emit(&"l3_final_choice")
	assert_eq(_events_named("boss_phase_changed").size(), 1, "entered once")
	assert_eq(boss.phase(), Flagship.Phase.DESPERATE)
	core.apply_damage(10, null)
	assert_eq(core.hp, 40, "damage lands")
	assert_eq(_events.back(), ["boss_hp_changed", 40, 300, 4])


func test_desperate_cadence_over_6_1_s() -> void:
	var player: Node2D = _add_player(Vector2(1300, 900))
	var boss: Flagship = _spawn_in_desperate()
	var core: FlagshipCore = boss.core()
	var origin: Vector2 = core.global_position
	var radial_interval: float = Config.num("boss.desperate.radial_interval_s")
	var radial_charge: float = Config.num("boss.desperate.radial_charge_s")
	var aimed_interval: float = Config.num("boss.desperate.aimed_interval_s")
	var aimed_telegraph: float = Config.num("boss.desperate.aimed_telegraph_s")
	assert_eq([radial_interval, radial_charge, aimed_interval, aimed_telegraph], [1.5, 0.4, 2.0, 0.3], "shipped cadence")
	## [t, radial bullets, aimed bullets] per tick that fired.
	var shots: Array[Array] = []
	var radial_angles: Array[Array] = []
	var aimed_angles: Array[Array] = []
	var samples: Array[Array] = []
	var seen: int = _bullets().size()
	var t: float = 0.0
	while t < 6.1:
		boss.step(DT)
		t += DT
		var bullets: Array[Projectile] = _bullets()
		var fresh: Array[Projectile] = bullets.slice(seen)
		seen = bullets.size()
		var radial: Array[float] = []
		var aimed: Array[float] = []
		for b: Projectile in fresh:
			assert_eq(b.global_position, origin, "from the core centre")
			assert_eq(b.damage, Config.int_("damage.bullet_hearts"))
			var speed: float = b.velocity.length()
			if is_equal_approx(speed, 300.0):
				radial.append(fposmod(_deg_from_down(b.velocity) + 0.001, 360.0) - 0.001)
			elif is_equal_approx(speed, 400.0):
				aimed.append(_deg_from_down(b.velocity))
			else:
				fail_test("unexpected bullet speed %.2f" % speed)
		if not radial.is_empty() or not aimed.is_empty():
			shots.append([t, radial.size(), aimed.size()])
		if not radial.is_empty():
			radial.sort()
			radial_angles.append(radial)
		if not aimed.is_empty():
			aimed.sort()
			aimed_angles.append(aimed)
		samples.append([t, core.is_glowing()])
	var radial_times: Array[float] = []
	var aimed_times: Array[float] = []
	for shot: Array in shots:
		if int(shot[1]) > 0:
			assert_eq(shot[1], 12, "12 bullets per radial burst")
			radial_times.append(shot[0])
		if int(shot[2]) > 0:
			assert_eq(shot[2], 3, "3 bullets per aimed spread")
			aimed_times.append(shot[0])
	assert_eq(radial_times.size(), 4, "radials at 1.5, 3.0, 4.5, 6.0")
	for k: int in radial_times.size():
		assert_almost_eq(radial_times[k], radial_interval * float(k + 1), DT + EPS, "radial %d at 1.5 * %d" % [k + 1, k + 1])
	assert_eq(aimed_times.size(), 3, "aimed spreads at 2.0, 4.0, 6.0")
	for k: int in aimed_times.size():
		assert_almost_eq(aimed_times[k], aimed_interval * float(k + 1), DT + EPS, "aimed spread %d at 2.0 * %d" % [k + 1, k + 1])
	# Bursts 1 and 3 fly straight down (0, 30, ...); bursts 2 and 4 sit 15 degrees on, in the gaps.
	for k: int in radial_angles.size():
		var offset: float = 0.0 if k % 2 == 0 else 15.0
		var angles: Array = radial_angles[k]
		for i: int in angles.size():
			assert_almost_eq(float(angles[i]), offset + 30.0 * float(i), 0.01, "burst %d bullet %d" % [k + 1, i])
	var aim_deg: float = _deg_from_down(player.global_position - origin)
	for k: int in aimed_angles.size():
		var angles: Array = aimed_angles[k]
		assert_almost_eq(float(angles[0]), aim_deg - 15.0, 0.01, "spread %d: -15 degrees" % (k + 1))
		assert_almost_eq(float(angles[1]), aim_deg, 0.01, "spread %d: the centre bullet at the player" % (k + 1))
		assert_almost_eq(float(angles[2]), aim_deg + 15.0, 0.01, "spread %d: +15 degrees" % (k + 1))
	# The Glow shows in each radial's last 0.4 s and each aimed spread's last 0.3 s (edges skipped).
	var checked: int = 0
	for sample: Array in samples:
		var st: float = sample[0]
		var radial_lead: float = (floorf(st / radial_interval + EPS) + 1.0) * radial_interval - st
		var aimed_lead: float = (floorf(st / aimed_interval + EPS) + 1.0) * aimed_interval - st
		var near_edge: bool = false
		for edge: float in [radial_lead - radial_charge, aimed_lead - aimed_telegraph, radial_lead, aimed_lead, radial_lead - radial_interval, aimed_lead - aimed_interval]:
			if absf(edge) < 2.0 * DT:
				near_edge = true
		if near_edge:
			continue
		checked += 1
		var expected: bool = radial_lead < radial_charge or aimed_lead < aimed_telegraph
		assert_eq(sample[1], expected, "glow at %.3f s (radial in %.3f, aimed in %.3f)" % [st, radial_lead, aimed_lead])
	assert_gt(checked, 250, "the glow was checked across the run")
	assert_true(core.is_pulsing(), "the pulse is on")


func test_desperate_rotation_helper() -> void:
	assert_eq(FlagshipCore.desperate_rotation_deg(0, 12, 2), 0.0)
	assert_eq(FlagshipCore.desperate_rotation_deg(1, 12, 2), 15.0)
	assert_eq(FlagshipCore.desperate_rotation_deg(2, 12, 2), 0.0)
	assert_eq(FlagshipCore.desperate_rotation_deg(3, 12, 2), 15.0)
	assert_eq(FlagshipCore.desperate_rotation_deg(1, 12, 1), 0.0, "one burst never rotates")
	assert_eq(FlagshipCore.desperate_rotation_deg(2, 12, 3), 20.0, "thirds of the gap with 3 bursts")
	assert_eq(FlagshipCore.desperate_rotation_deg(1, 0, 2), 0.0, "no bullets")


func test_desperate_aimed_spread_without_a_player_flies_down() -> void:
	var boss: Flagship = _spawn_in_desperate()
	_step_for(boss, 2.0 + DT)
	var aimed: Array[float] = []
	for b: Projectile in _bullets():
		if is_equal_approx(b.velocity.length(), 400.0):
			aimed.append(_deg_from_down(b.velocity))
	aimed.sort()
	assert_eq(aimed.size(), 3)
	if aimed.size() == 3:
		assert_almost_eq(aimed[1], 0.0, 0.01, "straight down with no player")


func test_desperate_pulse_is_a_steady_sine_toward_red() -> void:
	var boss: Flagship = _spawn_in_desperate()
	var core: FlagshipCore = boss.core()
	var base: Color = (core.get_node("Eye") as Polygon2D).color
	assert_eq(Config.num("boss.desperate.pulse_hz"), 2.0)
	assert_almost_eq(core.pulse_amount(), 0.0, 0.001, "starts at the Eye's own colour")
	_step_for(boss, 0.25)
	assert_almost_eq(core.pulse_amount(), 1.0, 0.01, "full red half a period in (2 Hz)")
	assert_almost_eq(core.eye_color().r, core.pulse_color.r, 0.02, "the Eye is red")
	assert_almost_eq(core.eye_color().g, core.pulse_color.g, 0.02)
	assert_almost_eq(core.eye_color().b, core.pulse_color.b, 0.02)
	_step_for(boss, 0.25)
	assert_almost_eq(core.pulse_amount(), 0.0, 0.01, "back after a full period")
	assert_almost_eq(core.eye_color().b, base.b, 0.02, "the Eye's own colour again")
	assert_almost_eq(FlagshipCore.pulse_at(0.125, 2.0), 0.5, 0.0001, "a quarter period: half way")


func test_desperate_without_a_spawner_fires_nothing() -> void:
	var boss: Flagship = FLAGSHIP_SCENE.instantiate() as Flagship
	add_child_autofree(boss)
	boss.set_physics_process(false)
	boss.step(Config.num("boss.hull.arrival_s"))
	for turret: FlagshipTurret in boss.turrets():
		turret.apply_damage(turret.hp, null)
	boss.core().apply_damage(150, null)
	assert_eq(boss.phase(), Flagship.Phase.FINAL_CHOICE)
	Events.comms_sequence_finished.emit(&"l3_final_choice")
	assert_eq(boss.phase(), Flagship.Phase.DESPERATE)
	var glowed: bool = false
	var t: float = 0.0
	while t < 6.1:
		boss.step(DT)
		t += DT
		glowed = glowed or boss.core().is_glowing()
	assert_true(glowed, "the cycles run (the glow showed)")
	assert_eq(_logged("[DEBUG][spawn] flagship_core has no spawner").size(), 1, "one DEBUG line")
	assert_eq(_logged("[ERROR]"), [] as Array[String], "no error")


## Story 7.5: the exposed core in DESPERATE is the target again; the hull never is.
func test_in_desperate_the_core_is_the_target() -> void:
	var boss: Flagship = _spawn_in_final_choice()
	await wait_physics_frames(2)
	var nodes: Array[Node] = get_tree().get_nodes_in_group(&"enemies")
	var below_core: Vector2 = boss.core().global_position + Vector2(0, 300)
	assert_false(boss.core().is_targetable(), "no target during the choice")
	assert_null(MicroMissile.nearest_enemy(below_core, nodes), "nothing for a micro-missile")
	Events.comms_sequence_finished.emit(&"l3_final_choice")
	assert_true(boss.core().is_targetable(), "targetable in DESPERATE")
	assert_false(boss.is_targetable(), "hull")
	assert_eq(MicroMissile.nearest_enemy(below_core, nodes), boss.core(), "a micro-missile picks the core")
	assert_eq(AllyShip.nearest_target(below_core, nodes), boss.core(), "the ally picks the core")


func test_core_death_enters_dying_then_boss_defeated_after_the_chain() -> void:
	var boss: Flagship = _spawn_in_core()
	_step_for(boss, Config.num("boss.core.wasp_launch_interval_s") + DT)
	var wasps: Array[Wasp] = _launched()
	assert_eq(wasps.size(), 5, "Wasps launched in CORE")
	boss.core().apply_damage(boss.core().hp, null)
	assert_eq(boss.phase(), Flagship.Phase.FINAL_CHOICE)
	Events.comms_sequence_finished.emit(&"l3_final_choice")
	assert_eq(boss.phase(), Flagship.Phase.DESPERATE)
	await wait_physics_frames(2)
	for child: Node in _effects.get_children():
		child.queue_free()
	await wait_physics_frames(1)
	var orbs_before: int = _pickups.get_child_count()
	var core: FlagshipCore = boss.core()
	var core_pos: Vector2 = core.global_position
	var hull_pos: Vector2 = boss.global_position
	_events.clear()
	_lines.clear()
	assert_eq(core.hp, 50)
	core.apply_damage(50, null)
	assert_true(core.is_dead(), "core destroyed")
	assert_eq(_events_named("enemy_killed"), [["enemy_killed", &"flagship_core", core_pos, false]] as Array[Array])
	assert_eq(boss.phase(), Flagship.Phase.DYING, "DYING")
	assert_eq(_events_named("boss_phase_changed"), [["boss_phase_changed", 5]] as Array[Array])
	assert_eq(_events_named("boss_hp_changed").back(), ["boss_hp_changed", 0, 300, 5], "combined 0")
	assert_eq(boss.collision_layer, 0, "the hull leaves its layer")
	assert_eq(core.collision_layer, 0, "the core leaves its layer")
	for turret: FlagshipTurret in boss.turrets():
		if is_instance_valid(turret):
			assert_eq(turret.collision_layer, 0)
	var explosions: Array[Explosion] = _live_explosions()
	assert_eq(explosions.size(), 1, "one explosion at once: the chain's first, no core impact of its own")
	if explosions.size() == 1:
		assert_eq(explosions[0].global_position, hull_pos + Vector2(0, 124), "at the core (pos + the first offset)")
		assert_eq(explosions[0].scale, Vector2(4, 4), "scale 4")
		assert_true(explosions[0].is_flashing(), "the white flash")
	assert_almost_eq(_camera.current_amplitude(), 20.0, EPS, "20 px shake")
	assert_true(Feedback.is_hit_stopped(), "the 150 ms hit-stop")
	assert_eq(Feedback.chain_pending(), 3)
	var defeated_at: float = -1.0
	var t: float = 0.0
	while t < 2.5:
		boss.step(DT)
		Feedback.step_chain(DT)
		t += DT
		if defeated_at < 0.0 and not _events_named("boss_defeated").is_empty():
			defeated_at = t
	assert_eq(_events_named("boss_defeated").size(), 1, "boss_defeated exactly once")
	assert_almost_eq(defeated_at, Config.num("feedback.boss_death_chain_s"), DT + EPS, "after the 2.0 s chain")
	assert_true(boss.is_queued_for_deletion(), "the Flagship frees itself")
	assert_eq(_live_explosions().size(), 4, "4 explosions in total")
	assert_eq(_logged("[INFO][combat] Flagship destroyed").size(), 1, "one INFO line")
	for wasp: Wasp in wasps:
		assert_true(is_instance_valid(wasp) and not wasp.is_dead() and not wasp.is_queued_for_deletion(), "launched Wasps stay")
	await wait_physics_frames(2)
	assert_eq(_pickups.get_child_count(), orbs_before, "the core drops nothing")
	assert_eq(_logged("[ERROR]"), [] as Array[String], "no error")


## The core's death in any phase enters DYING (without a floor, e.g. bad data).
func test_core_death_in_core_without_a_floor_enters_dying() -> void:
	var boss: Flagship = _spawn_in_core()
	boss.core().set_hp_floor(0)
	boss.core().apply_damage(999, null)
	assert_true(boss.core().is_dead())
	assert_eq(boss.phase(), Flagship.Phase.DYING)
	assert_eq(_requests, [] as Array[StringName], "no Final Choice")
	_step_for(boss, Config.num("feedback.boss_death_chain_s") + DT)
	assert_eq(_events_named("boss_defeated").size(), 1)


func test_without_a_spawner_core_cycles_but_nothing_fires_or_launches() -> void:
	var boss: Flagship = FLAGSHIP_SCENE.instantiate() as Flagship
	add_child_autofree(boss)
	boss.set_physics_process(false)
	boss.step(Config.num("boss.hull.arrival_s"))
	for turret: FlagshipTurret in boss.turrets():
		turret.apply_damage(turret.hp, null)
	assert_eq(boss.phase(), Flagship.Phase.CORE)
	var glowed: bool = false
	var t: float = 0.0
	while t < 21.0:
		boss.step(DT)
		t += DT
		glowed = glowed or boss.core().is_glowing()
	assert_true(glowed, "the core cycle runs (the glow showed)")
	assert_eq(_launched().size(), 0, "nothing launched")
	assert_eq(_logged("[DEBUG][spawn] flagship_core has no spawner").size(), 1, "one DEBUG line for the core")
	assert_eq(_logged("[DEBUG][spawn] flagship has no spawner").size(), 1, "one DEBUG line for the Flagship")
	assert_eq(_logged("[ERROR]"), [] as Array[String], "no error")
