extends GutTest
## Maul (Story 6.2, FR23): stats and scene contract, off-screen starts with the
## alarm ping and the trail, the straight dive at the nearest convoy ship locked
## at spawn, the convoy hit (10 HP, MEDIUM feedback, no kill, no loot), the miss,
## the no-convoy resolve, kills by shots, and the pause freeze.
## Driven through step(delta) with physics processing off, plus real overlaps.

const MAUL_SCENE: PackedScene = preload("res://entities/enemies/maul/maul.tscn")
const CONVOY_SCENE: PackedScene = preload("res://entities/allies/convoy.tscn")
const DT: float = 1.0 / 60.0
const ENEMY_COLOR: Color = Color("#FF2BD6")
const DANGER_COLOR: Color = Color("#FF1F4B")

var _lines: Array[String] = []
var _debug_was: bool = true


func before_each() -> void:
	_lines.clear()
	_debug_was = Log.debug_enabled
	Log.debug_enabled = true
	Log.sink = _capture
	watch_signals(Events)


func after_each() -> void:
	Log.sink = Callable()
	Log.debug_enabled = _debug_was
	Config.load_data()
	PauseArbiter.clear()
	Feedback.reset()


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _logged(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.begins_with(prefix):
			out.append(line)
	return out


## A still convoy (physics off) at its start layout: flank-left (80, 850), lead
## (248, 830), flank-right (416, 850).
func _make_convoy() -> Convoy:
	var convoy: Convoy = CONVOY_SCENE.instantiate() as Convoy
	add_child_autofree(convoy)
	convoy.set_physics_process(false)
	return convoy


func _make(params: Dictionary, manual: bool = true, spawner: Spawner = null) -> Maul:
	var maul: Maul
	if spawner != null:
		maul = spawner.spawn_enemy(&"maul", params) as Maul
	else:
		maul = MAUL_SCENE.instantiate() as Maul
		maul.setup(params)
		add_child_autofree(maul)
	if manual:
		maul.set_physics_process(false)
	watch_signals(maul)
	return maul


func _make_player(pos: Vector2) -> Node2D:
	var player: Node2D = Node2D.new()
	player.add_to_group(&"player")
	add_child_autofree(player)
	player.global_position = pos
	return player


## The ship whose centre is nearest `from`, computed independently of the Maul.
func _nearest_ship(convoy: Convoy, from: Vector2) -> ConvoyShip:
	var best: ConvoyShip = null
	var best_d: float = INF
	for ship: ConvoyShip in convoy.ships():
		var d: float = from.distance_to(ship.global_position)
		if d < best_d:
			best_d = d
			best = ship
	return best


## A World with the entity containers and Pickups, plus its Spawner.
func _drop_world() -> Spawner:
	var world: Node2D = Node2D.new()
	for container: String in ["Projectiles", "Enemies", "Asteroids", "Pickups", "Effects"]:
		var node: Node2D = Node2D.new()
		node.name = container
		world.add_child(node)
	add_child_autofree(world)
	var spawner: Spawner = Spawner.new()
	spawner.world = world
	add_child_autofree(spawner)
	return spawner


func _orbs(spawner: Spawner) -> int:
	var n: int = 0
	for child: Node in spawner.world.get_node("Pickups").get_children():
		if child is EnergyOrb:
			n += 1
	return n


func _force_drop() -> void:
	((Config.tuning["drops"] as Dictionary)["maul"] as Dictionary)["chance"] = 1.0


## True while any SFX pool player holds `id`'s stream.
func _sfx_played(id: StringName) -> bool:
	for child: Node in Audio.get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		if player != null and player.bus == &"SFX" and player.stream == Audio.SFX.get(id):
			return true
	return false


# --- Stats and scene ----------------------------------------------------------

func test_stats_layers_hull_and_trail() -> void:
	var maul: Maul = _make({"position": Vector2(960, 300)})
	assert_eq(maul.type_id, &"maul")
	assert_eq(maul.hp, Config.int_("enemies.maul.hp"))
	assert_eq(maul.hp, 6)
	assert_eq(maul.tier, ImpactTier.MEDIUM)
	assert_eq(maul.sprite_px, 96.0, "medium-tier sprite size")
	var node: Node = maul
	assert_false(node is Wasp, "not a Wasp")
	assert_false(node is HunterWasp, "not a Hunter")
	var hitbox: CollisionShape2D = maul.get_node_or_null("Hitbox") as CollisionShape2D
	assert_not_null(hitbox)
	if hitbox != null:
		var circle: CircleShape2D = hitbox.shape as CircleShape2D
		assert_not_null(circle)
		if circle != null:
			assert_almost_eq(circle.radius, 48.0 * Config.num("enemies.maul.hitbox_ratio"), 0.0001)
	assert_eq(maul.collision_layer, CollisionLayers.ENEMIES, "enemies layer")
	assert_eq(maul.collision_mask, CollisionLayers.CONVOY, "only the Maul masks the convoy")
	assert_true(maul.monitoring, "detects convoy ships")
	var hull: Polygon2D = maul.get_node_or_null("Hull") as Polygon2D
	assert_not_null(hull)
	if hull != null:
		assert_true(hull.color.is_equal_approx(ENEMY_COLOR), "enemy #FF2BD6 hull")
		assert_gte(hull.polygon.size(), 3)
	var trail: Polygon2D = maul.get_node_or_null("Trail") as Polygon2D
	assert_not_null(trail)
	if trail != null:
		assert_true(trail.color.is_equal_approx(DANGER_COLOR), "danger #FF1F4B trail")
		var mat: CanvasItemMaterial = trail.material as CanvasItemMaterial
		assert_not_null(mat, "trail has a CanvasItemMaterial")
		if mat != null:
			assert_eq(mat.blend_mode, CanvasItemMaterial.BLEND_MODE_ADD, "additive glow")
		assert_true(trail.visible, "trail shows while diving")
		var behind: bool = true
		for p: Vector2 in trail.polygon:
			behind = behind and p.y < 0.0
		assert_true(behind, "the trail is behind the nose (local -y)")
		assert_lt(trail.get_index(), hull.get_index(), "the hull draws over the trail")


func test_scene_layer_and_mask_match_the_constants() -> void:
	var probe: Maul = MAUL_SCENE.instantiate() as Maul
	assert_eq(probe.collision_layer, CollisionLayers.ENEMIES)
	assert_eq(probe.collision_mask, CollisionLayers.CONVOY)
	assert_true(probe.monitoring, "monitoring on in the scene (never toggled in a physics flush)")
	probe.free()


# --- Spawn and targeting ------------------------------------------------------

func test_left_side_spawn_aims_at_the_nearest_ship_and_pings() -> void:
	var convoy: Convoy = _make_convoy()
	var maul: Maul = _make({"position": Vector2(400, 200), "slot": Vector2(400, 200), "entry": &"sides"})
	var start: Vector2 = Vector2(-48, 200)
	assert_eq(maul.global_position, start, "just off-screen left at the slot's y")
	var ship: ConvoyShip = _nearest_ship(convoy, start)
	assert_eq(maul.target_ship(), ship, "nearest ship centre at spawn")
	var expected: Vector2 = (ship.global_position - start).normalized()
	assert_almost_eq(maul.heading().distance_to(expected), 0.0, 0.0001, "unit vector at the target's centre")
	assert_almost_eq(maul.heading().length(), 1.0, 0.0001)
	assert_almost_eq(maul.rotation, expected.angle() - PI / 2.0, 0.0001, "nose follows the heading")
	assert_eq(maul.state(), Maul.State.DIVE)
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"maul_alarm"], "alarm ping")
	assert_eq(_logged("[WARN]"), [] as Array[String])


func test_right_side_spawn_starts_past_the_right_edge() -> void:
	var convoy: Convoy = _make_convoy()
	var maul: Maul = _make({"position": Vector2(1500, 300), "slot": Vector2(1500, 300), "entry": &"sides"})
	var start: Vector2 = Vector2(1968, 300)
	assert_eq(maul.global_position, start)
	var ship: ConvoyShip = _nearest_ship(convoy, start)
	assert_eq(maul.target_ship(), ship)
	assert_almost_eq(maul.heading().distance_to((ship.global_position - start).normalized()), 0.0, 0.0001)


func test_nearest_ship_depends_on_the_start() -> void:
	var convoy: Convoy = _make_convoy()
	# Flank-right (416, 850) is nearest from the right; flank-left (80, 850) from the far left low.
	var right: Maul = _make({"position": Vector2(1500, 840), "slot": Vector2(1500, 840), "entry": &"sides"})
	assert_eq(right.target_ship(), convoy.ships()[Convoy.FLANK_RIGHT])
	var low_left: Maul = _make({"position": Vector2(100, 900)})
	assert_eq(low_left.target_ship(), convoy.ships()[Convoy.FLANK_LEFT])


func test_top_entry_starts_above_the_slot() -> void:
	var convoy: Convoy = _make_convoy()
	var maul: Maul = _make({"position": Vector2(960, 160), "slot": Vector2(960, 160), "entry": &"top"})
	var start: Vector2 = Vector2(960, -48)
	assert_eq(maul.global_position, start)
	assert_eq(maul.target_ship(), _nearest_ship(convoy, start))


func test_without_a_slot_it_starts_at_its_position() -> void:
	var convoy: Convoy = _make_convoy()
	var maul: Maul = _make({"position": Vector2(700, 300)})
	assert_eq(maul.global_position, Vector2(700, 300))
	assert_eq(maul.target_ship(), _nearest_ship(convoy, Vector2(700, 300)))


func test_unknown_entry_warns_and_uses_top() -> void:
	_make_convoy()
	var maul: Maul = _make({"position": Vector2(960, 160), "slot": Vector2(960, 160), "entry": &"spiral"})
	assert_eq(maul.global_position, Vector2(960, -48))
	assert_eq(_logged("[WARN][spawn]"), ["[WARN][spawn] maul entry 'spiral' is unknown; using top"] as Array[String])


# --- Dive -----------------------------------------------------------------------

func test_dives_at_400_px_s_along_the_fixed_heading() -> void:
	_make_convoy()
	var maul: Maul = _make({"position": Vector2(400, 200), "slot": Vector2(400, 200), "entry": &"sides"})
	var heading: Vector2 = maul.heading()
	for i: int in 30:
		var before: Vector2 = maul.global_position
		maul.step(DT)
		assert_almost_eq(before.distance_to(maul.global_position), 400.0 * DT, 0.0001, "400 px/s")
		assert_almost_eq((maul.global_position - before).normalized().distance_to(heading), 0.0, 0.0001, "straight")
	assert_eq(maul.heading(), heading)


func test_the_player_never_changes_the_heading() -> void:
	_make_convoy()
	var player: Node2D = _make_player(Vector2(960, 900))
	var maul: Maul = _make({"position": Vector2(1500, 200), "slot": Vector2(1500, 200), "entry": &"sides"})
	var heading: Vector2 = maul.heading()
	var rot: float = maul.rotation
	for pos: Vector2 in [Vector2(1900, 440), Vector2(0, 1080), Vector2(1700, 300), Vector2(maul.global_position.x, 600)]:
		player.global_position = pos
		for i: int in 10:
			maul.step(DT)
		assert_eq(maul.heading(), heading, "heading unchanged with the player at %s" % pos)
		assert_eq(maul.rotation, rot)


func test_dive_speed_comes_from_tuning() -> void:
	((Config.tuning["enemies"] as Dictionary)["maul"] as Dictionary)["dive_speed_px_s"] = 120.0
	_make_convoy()
	var maul: Maul = _make({"position": Vector2(700, 300)})
	var before: Vector2 = maul.global_position
	maul.step(DT)
	assert_almost_eq(before.distance_to(maul.global_position), 2.0, 0.0001, "120 px/s")


## The telegraph rule: even from the lowest enemy-zone y the dive takes longer
## than weapons.enemy_bullet.min_telegraph_s to reach the convoy band.
func test_reaching_the_band_takes_at_least_the_telegraph_minimum() -> void:
	var lowest_start: float = Config.num("player.bounds_y.min")
	var band_top: float = Config.num("convoy.band_y.min")
	var seconds: float = (band_top - lowest_start) / Config.num("enemies.maul.dive_speed_px_s")
	assert_gte(seconds, Config.num("weapons.enemy_bullet.min_telegraph_s"))


func test_no_log_lines_while_diving() -> void:
	_make_convoy()
	var maul: Maul = _make({"position": Vector2(700, 300)})
	_lines.clear()
	for i: int in 30:
		maul.step(DT)
	assert_eq(_lines, [] as Array[String])


# --- Convoy hit -----------------------------------------------------------------

func test_convoy_hit_deals_10_and_resolves_without_a_kill() -> void:
	var spawner: Spawner = _drop_world()
	_force_drop()
	var convoy: Convoy = _make_convoy()
	var maul: Maul = _make({"position": Vector2(700, 300)}, true, spawner)
	var ship: ConvoyShip = maul.target_ship()
	maul.area_entered.emit(ship)
	assert_eq(convoy.hp(), 90, "convoy HP drops by damage.convoy_maul")
	assert_eq(Config.int_("damage.convoy_maul"), 10)
	assert_signal_emitted_with_parameters(Events, "convoy_hp_changed", [90, 100])
	assert_signal_emit_count(maul, "resolved", 1)
	assert_signal_not_emitted(Events, "enemy_killed", "not a kill")
	assert_true(maul.is_dead())
	assert_true(maul.is_queued_for_deletion(), "freed")
	assert_eq(maul.state(), Maul.State.DONE)
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"explosion_medium"], "MEDIUM death feedback")
	maul.area_entered.emit(ship)
	assert_eq(convoy.hp(), 90, "a second overlap is ignored")
	assert_signal_emit_count(maul, "resolved", 1, "resolves once")
	await wait_process_frames(2)
	assert_eq(_orbs(spawner), 0, "no loot")


func test_real_overlap_with_a_convoy_ship_hits_it() -> void:
	var convoy: Convoy = _make_convoy()
	var ship: ConvoyShip = convoy.ships()[Convoy.LEAD]
	var maul: Maul = _make({"position": ship.global_position})
	var count: Array[int] = [0]
	maul.resolved.connect(func() -> void: count[0] += 1)
	await wait_physics_frames(3)
	assert_eq(convoy.hp(), 90, "one hit through the physics overlap")
	assert_eq(count[0], 1, "resolved once")
	assert_false(is_instance_valid(maul), "freed")
	assert_signal_not_emitted(Events, "enemy_killed")


func test_other_areas_are_ignored() -> void:
	_make_convoy()
	var maul: Maul = _make({"position": Vector2(700, 300)})
	var other: Area2D = Area2D.new()
	add_child_autofree(other)
	maul.area_entered.emit(other)
	assert_false(maul.is_dead())
	assert_signal_not_emitted(maul, "resolved")


func test_hit_on_an_ended_convoy_still_self_destructs() -> void:
	var convoy: Convoy = _make_convoy()
	var maul: Maul = _make({"position": Vector2(700, 300)})
	Events.level_cleared.emit(0)
	maul.area_entered.emit(maul.target_ship())
	assert_eq(convoy.hp(), 100, "the convoy ignores hits after the outcome")
	assert_signal_emit_count(maul, "resolved", 1)
	assert_true(maul.is_queued_for_deletion())


# --- Miss -----------------------------------------------------------------------

func test_miss_resolves_once_outside_the_playfield() -> void:
	var spawner: Spawner = _drop_world()
	_force_drop()
	var convoy: Convoy = _make_convoy()
	var maul: Maul = _make({"position": Vector2(400, 200), "slot": Vector2(400, 200), "entry": &"sides"}, true, spawner)
	# Take the cargo out of the way after the Maul aimed: its line now hits nothing.
	convoy.queue_free()
	await wait_process_frames(1)
	maul.step(DT)
	assert_signal_not_emitted(maul, "resolved", "starting on the edge is not a miss")
	var steps: int = 0
	while not maul.is_dead() and steps < 600:
		maul.step(DT)
		steps += 1
	assert_true(maul.is_dead(), "resolved after leaving the playfield")
	var half: float = maul.sprite_px / 2.0
	var p: Vector2 = maul.global_position
	assert_false(p.x > -half and p.x < 1920.0 + half and p.y > -half and p.y < 1080.0 + half, "fully outside")
	assert_signal_emit_count(maul, "resolved", 1)
	assert_signal_not_emitted(Events, "enemy_killed")
	assert_true(maul.is_queued_for_deletion())
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"maul_alarm"], "no feedback on a miss")
	maul.step(DT)
	assert_signal_emit_count(maul, "resolved", 1, "once")
	await wait_process_frames(2)
	assert_eq(_orbs(spawner), 0, "no loot")


# --- No convoy ------------------------------------------------------------------

func test_no_convoy_resolves_on_the_first_step_not_in_ready() -> void:
	var maul: Maul = _make({"position": Vector2(400, 200), "slot": Vector2(400, 200), "entry": &"sides"})
	assert_null(maul.target_ship())
	assert_false(maul.is_dead(), "not resolved inside _ready")
	assert_signal_not_emitted(maul, "resolved")
	assert_eq(_logged("[DEBUG][combat]"), ["[DEBUG][combat] maul: no live convoy at spawn; resolves without a kill"] as Array[String])
	var start: Vector2 = maul.global_position
	maul.step(DT)
	assert_signal_emit_count(maul, "resolved", 1)
	assert_signal_not_emitted(Events, "enemy_killed")
	assert_true(maul.is_queued_for_deletion())
	assert_eq(maul.global_position, start, "never flew")
	maul.step(DT)
	assert_signal_emit_count(maul, "resolved", 1)
	assert_eq(_logged("[DEBUG][combat]").size(), 1, "logged once")


func test_lost_convoy_counts_as_no_convoy() -> void:
	var convoy: Convoy = _make_convoy()
	convoy.apply_damage(convoy.max_hp(), null)
	assert_true(convoy.is_lost())
	var maul: Maul = _make({"position": Vector2(700, 300)})
	assert_null(maul.target_ship())
	maul.step(DT)
	assert_signal_emit_count(maul, "resolved", 1)
	assert_signal_not_emitted(Events, "enemy_killed")


func test_physics_process_drives_the_no_convoy_resolve() -> void:
	var maul: Maul = _make({"position": Vector2(700, 300)}, false)
	var count: Array[int] = [0]
	maul.resolved.connect(func() -> void: count[0] += 1)
	await wait_physics_frames(2)
	assert_eq(count[0], 1, "resolved once")


# --- Shot down ------------------------------------------------------------------

func test_shot_down_by_an_ally_is_a_kill_with_loot() -> void:
	var spawner: Spawner = _drop_world()
	_force_drop()
	_make_convoy()
	var maul: Maul = _make({"position": Vector2(700, 300)}, true, spawner)
	var bolt: Projectile = Projectile.new()
	bolt.from_ally = true
	autofree(bolt)
	maul.apply_damage(5, bolt)
	assert_false(maul.is_dead(), "alive at 1 HP")
	maul.apply_damage(1, bolt)
	assert_true(maul.is_dead())
	assert_signal_emit_count(Events, "enemy_killed", 1)
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"maul", Vector2(700, 300), true])
	assert_signal_emit_count(maul, "resolved", 1)
	await wait_process_frames(1)
	assert_eq(_orbs(spawner), 1, "drops.maul rolled")


func test_contact_destroys_it_as_a_kill() -> void:
	_make_convoy()
	var maul: Maul = _make({"position": Vector2(700, 300)})
	maul.destroy_by_contact()
	assert_true(maul.is_dead(), "medium tier dies by contact")
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"maul", Vector2(700, 300), false])
	assert_signal_emit_count(maul, "resolved", 1)


# --- Pause ----------------------------------------------------------------------

func test_paused_tree_freezes_the_maul() -> void:
	_make_convoy()
	var maul: Maul = _make({"position": Vector2(1500, 200)}, false)
	PauseArbiter.push(&"menu")
	var before: Vector2 = maul.global_position
	await get_tree().create_timer(0.2, true, true).timeout
	assert_eq(maul.global_position, before, "no movement while paused")
	PauseArbiter.pop(&"menu")
	await wait_physics_frames(3)
	assert_ne(maul.global_position, before, "moves again after resume")
