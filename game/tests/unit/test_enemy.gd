extends GutTest
## Enemy contract via wasp.tscn: HP, damage intake, ally attribution, one-shot death,
## hitbox from tuning, scene layers, the shared subclass helpers (slot/entry
## params, entry start, aim, fire guard, tuning keys); ImpactTier name mapping;
## death drops through Loot (Story 3.3).

const WASP_SCENE: PackedScene = preload("res://entities/enemies/wasp/wasp.tscn")
const DamageTarget: GDScript = preload("res://tests/fixtures/damage_target.gd")

var _lines: Array[String] = []
var _debug_was: bool = true


func before_each() -> void:
	watch_signals(Events)
	_lines.clear()
	_debug_was = Log.debug_enabled
	Log.sink = _capture


func after_each() -> void:
	Config.load_data()
	Log.sink = Callable()
	Log.debug_enabled = _debug_was
	Feedback.reset()


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _logged(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.begins_with(prefix):
			out.append(line)
	return out


func _make_wasp(pos: Vector2 = Vector2(960, 300)) -> Enemy:
	var wasp: Enemy = WASP_SCENE.instantiate() as Enemy
	wasp.setup({"position": pos})
	add_child_autofree(wasp)
	watch_signals(wasp)
	return wasp


## An out-of-tree Projectile standing in for a bolt, with the given from_ally flag.
func _source(from_ally: bool) -> Projectile:
	var projectile: Projectile = Projectile.new()
	projectile.from_ally = from_ally
	autofree(projectile)
	return projectile


func test_setup_stores_and_ready_applies() -> void:
	var wasp: Enemy = WASP_SCENE.instantiate() as Enemy
	wasp.setup({"position": Vector2(300, 200)})
	assert_eq(wasp.position, Vector2.ZERO, "setup does not apply the position")
	add_child_autofree(wasp)
	assert_eq(wasp.global_position, Vector2(300, 200))
	assert_eq(wasp.hp, Config.int_("enemies.wasp.hp"))
	assert_eq(wasp.hp, 3)


func test_wasp_kill_after_three_hits() -> void:
	var wasp: Enemy = _make_wasp()
	var bolt: Projectile = _source(false)
	wasp.apply_damage(1, bolt)
	wasp.apply_damage(1, bolt)
	assert_eq(wasp.hp, 1)
	assert_signal_not_emitted(Events, "enemy_killed", "alive after 2 hits")
	assert_false(wasp.is_queued_for_deletion())
	wasp.apply_damage(1, bolt)
	assert_eq(wasp.hp, 0)
	assert_signal_emit_count(Events, "enemy_killed", 1)
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"wasp", Vector2(960, 300), false])
	assert_signal_emit_count(wasp, "resolved", 1)
	assert_true(wasp.is_queued_for_deletion())


func test_overkill_does_not_die_twice() -> void:
	var wasp: Enemy = _make_wasp()
	for i: int in 4:
		wasp.apply_damage(1, null)
	assert_signal_emit_count(Events, "enemy_killed", 1)
	assert_signal_emit_count(wasp, "resolved", 1)
	wasp.destroy_by_contact()
	assert_signal_emit_count(Events, "enemy_killed", 1, "contact after death is ignored")
	assert_signal_emit_count(wasp, "resolved", 1)


func test_ally_source_flags_kill() -> void:
	var wasp: Enemy = _make_wasp()
	wasp.apply_damage(2, _source(false))
	wasp.apply_damage(1, _source(true))
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"wasp", Vector2(960, 300), true])


func test_player_kill_after_ally_hit_is_not_ally() -> void:
	var wasp: Enemy = _make_wasp()
	wasp.apply_damage(2, _source(true))
	wasp.apply_damage(1, _source(false))
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"wasp", Vector2(960, 300), false])


func test_null_source_kill() -> void:
	var wasp: Enemy = _make_wasp()
	wasp.apply_damage(3, null)
	assert_signal_emit_count(Events, "enemy_killed", 1)
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"wasp", Vector2(960, 300), false])
	assert_signal_emit_count(wasp, "resolved", 1)


func test_plain_source_without_from_ally() -> void:
	var wasp: Enemy = _make_wasp()
	var plain: Area2D = DamageTarget.new() as Area2D
	autofree(plain)
	wasp.apply_damage(3, plain)
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"wasp", Vector2(960, 300), false])


func test_destroy_by_contact() -> void:
	var wasp: Enemy = _make_wasp()
	wasp.destroy_by_contact()
	assert_signal_emit_count(Events, "enemy_killed", 1)
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"wasp", Vector2(960, 300), false])
	assert_signal_emit_count(wasp, "resolved", 1)
	assert_true(wasp.is_queued_for_deletion())


func test_medium_enemy_is_destroyed_by_contact() -> void:
	var lancer: Enemy = (preload("res://entities/enemies/lancer/lancer.tscn") as PackedScene).instantiate() as Enemy
	lancer.setup({"position": Vector2(700, 200)})
	add_child_autofree(lancer)
	lancer.set_physics_process(false)
	watch_signals(lancer)
	assert_eq(lancer.tier, ImpactTier.MEDIUM)
	lancer.destroy_by_contact()
	assert_true(lancer.is_dead(), "a medium enemy dies by contact")
	assert_signal_emit_count(lancer, "resolved", 1)
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"lancer", Vector2(700, 200), false])


func test_contact_after_ally_hit_is_not_ally() -> void:
	var wasp: Enemy = _make_wasp()
	wasp.apply_damage(1, _source(true))
	wasp.destroy_by_contact()
	assert_signal_emit_count(Events, "enemy_killed", 1)
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"wasp", Vector2(960, 300), false])


func test_tier_read_from_tuning() -> void:
	var lancer: Enemy = Enemy.new()
	lancer.type_id = &"lancer"
	var hitbox: CollisionShape2D = CollisionShape2D.new()
	hitbox.name = "Hitbox"
	lancer.add_child(hitbox)
	add_child_autofree(lancer)
	assert_eq(lancer.tier, ImpactTier.MEDIUM, "lancer tier 'medium' from tuning")


func test_wasp_hitbox_radius_from_tuning() -> void:
	var wasp: Enemy = _make_wasp()
	var hitbox: CollisionShape2D = wasp.get_node_or_null("Hitbox") as CollisionShape2D
	assert_not_null(hitbox)
	if hitbox == null:
		return
	var circle: CircleShape2D = hitbox.shape as CircleShape2D
	assert_not_null(circle, "CircleShape2D")
	if circle != null:
		assert_almost_eq(circle.radius, 25.6, 0.0001, "64 / 2 * 0.8")
		assert_almost_eq(circle.radius, wasp.sprite_px / 2.0 * Config.num("enemies.wasp.hitbox_ratio"), 0.0001)


func test_wasp_scene_contract() -> void:
	var wasp: Enemy = _make_wasp()
	assert_true(wasp is Enemy, "root is an Enemy")
	assert_eq(wasp.type_id, &"wasp")
	assert_eq(wasp.collision_layer, CollisionLayers.ENEMIES, "enemies layer")
	assert_eq(wasp.collision_mask, 0, "masks nothing")
	assert_false(wasp.monitoring)
	assert_true(wasp.monitorable)
	assert_eq(wasp.tier, ImpactTier.SMALL)
	assert_true(wasp.is_in_group(&"enemies"))
	assert_eq(wasp.sprite_px, 64.0)


func test_wasp_holds_position() -> void:
	var wasp: Enemy = _make_wasp(Vector2(720, 160))
	await wait_physics_frames(5)
	assert_eq(wasp.global_position, Vector2(720, 160))


# --- Shared subclass helpers --------------------------------------------------

## A slotless wasp (it holds its spawn position, so _ready computes no entry)
## with the given params merged in, physics off.
func _make_helper_wasp(extra: Dictionary = {}) -> Enemy:
	var params: Dictionary = {"position": Vector2(960, 300)}
	params.merge(extra, true)
	var wasp: Enemy = WASP_SCENE.instantiate() as Enemy
	wasp.setup(params)
	add_child_autofree(wasp)
	wasp.set_physics_process(false)
	return wasp


func _make_player(pos: Vector2) -> Node2D:
	var player: Node2D = Node2D.new()
	player.add_to_group(&"player")
	add_child_autofree(player)
	player.global_position = pos
	return player


func test_setup_stores_slot_and_entry() -> void:
	var wasp: Enemy = WASP_SCENE.instantiate() as Enemy
	assert_false(wasp._has_slot, "no slot before setup")
	assert_eq(wasp._entry, Enemy.ENTRY_TOP, "entry defaults to top")
	wasp.setup({"position": Vector2(720, 400), "slot": Vector2(720, 160), "entry": "sides"})
	assert_true(wasp._has_slot)
	assert_eq(wasp._slot, Vector2(720, 160))
	assert_eq(wasp._entry, Enemy.ENTRY_SIDES, "a String entry becomes a StringName")
	autofree(wasp)


func test_entry_start_top() -> void:
	var wasp: Enemy = _make_helper_wasp({"entry": &"top"})
	assert_eq(wasp._entry_start_for(Vector2(500, 150)), Vector2(500, -32))
	var default_entry: Enemy = _make_helper_wasp()
	assert_eq(default_entry._entry_start_for(Vector2(500, 150)), Vector2(500, -32), "absent entry is top")
	assert_eq(_logged("[WARN]").size(), 0)


func test_entry_start_sides_left_half() -> void:
	var wasp: Enemy = _make_helper_wasp({"entry": &"sides"})
	assert_eq(wasp._entry_start_for(Vector2(300, 150)), Vector2(-32, 150))
	assert_eq(wasp._entry_start_for(Vector2(960, 200)), Vector2(-32, 200), "the centre counts as left")
	assert_eq(_logged("[WARN]").size(), 0)


func test_entry_start_sides_right_half() -> void:
	var wasp: Enemy = _make_helper_wasp({"entry": &"sides"})
	assert_eq(wasp._entry_start_for(Vector2(961, 150)), Vector2(1952, 150))
	assert_eq(_logged("[WARN]").size(), 0)


func test_entry_start_unknown_warns_and_uses_top() -> void:
	var wasp: Enemy = _make_helper_wasp({"entry": &"spiral"})
	assert_eq(_logged("[WARN]").size(), 0, "a slotless wasp computes no entry in _ready")
	assert_eq(wasp._entry_start_for(Vector2(500, 150)), Vector2(500, -32))
	assert_eq(_logged("[WARN]"), ["[WARN][spawn] wasp entry 'spiral' is unknown; using top"] as Array[String])


func test_aim_from_without_player_is_down() -> void:
	var wasp: Enemy = _make_helper_wasp()
	assert_eq(wasp._aim_from(Vector2(500, 500)), Vector2.DOWN)


func test_aim_from_player_on_origin_is_down() -> void:
	var wasp: Enemy = _make_helper_wasp()
	_make_player(Vector2(500, 500))
	assert_eq(wasp._aim_from(Vector2(500, 500)), Vector2.DOWN)


func test_aim_from_points_at_the_player() -> void:
	var wasp: Enemy = _make_helper_wasp()
	_make_player(Vector2(800, 900))
	var dir: Vector2 = wasp._aim_from(Vector2(500, 500))
	assert_almost_eq(dir.x, 0.6, 0.0001)
	assert_almost_eq(dir.y, 0.8, 0.0001)
	assert_almost_eq(dir.length(), 1.0, 0.0001, "unit vector")


func test_can_fire_without_spawner_logs_one_debug() -> void:
	Log.debug_enabled = true
	var wasp: Enemy = _make_helper_wasp()
	assert_null(wasp.spawner)
	assert_false(wasp._can_fire())
	assert_false(wasp._can_fire(), "still false")
	assert_eq(_logged("[DEBUG][spawn]"), ["[DEBUG][spawn] wasp has no spawner; shot skipped"] as Array[String], "once per enemy")


func test_can_fire_with_live_then_freed_spawner() -> void:
	Log.debug_enabled = true
	var wasp: Enemy = _make_helper_wasp()
	var spawner: Spawner = Spawner.new()
	wasp.spawner = spawner
	assert_true(wasp._can_fire(), "a live spawner can take shots")
	spawner.free()
	assert_false(wasp._can_fire(), "a freed spawner counts as missing")
	assert_eq(_logged("[DEBUG][spawn]"), ["[DEBUG][spawn] wasp has no spawner; shot skipped"] as Array[String])


func test_tuning_key() -> void:
	var lancer: Enemy = (preload("res://entities/enemies/lancer/lancer.tscn") as PackedScene).instantiate() as Enemy
	assert_eq(lancer._tuning_key("telegraph_s"), "enemies.lancer.telegraph_s")
	autofree(lancer)
	var wasp: Enemy = _make_helper_wasp()
	assert_eq(wasp._tuning_key("hp"), "enemies.wasp.hp")


# --- ImpactTier ---------------------------------------------------------------

func test_impact_tier_from_name() -> void:
	var expected: Dictionary = {
		"small": ImpactTier.SMALL,
		"medium": ImpactTier.MEDIUM,
		"large": ImpactTier.LARGE,
		"boss_part": ImpactTier.BOSS_PART,
		"boss_death": ImpactTier.BOSS_DEATH,
		"player_hit": ImpactTier.PLAYER_HIT,
		"player_death": ImpactTier.PLAYER_DEATH,
	}
	for tier_name: String in expected:
		assert_eq(ImpactTier.from_name(tier_name), expected[tier_name], tier_name)


func test_impact_tier_unknown_name_logs_and_returns_small() -> void:
	assert_eq(ImpactTier.from_name("gigantic"), ImpactTier.SMALL)
	assert_push_error("gigantic")


# --- Death drops (Story 3.3) -------------------------------------------------------


## A World with the entity containers and Pickups, plus its Spawner.
func _drop_world() -> Spawner:
	var world: Node2D = Node2D.new()
	for container: String in ["Projectiles", "Enemies", "Asteroids", "Pickups"]:
		var node: Node2D = Node2D.new()
		node.name = container
		world.add_child(node)
	add_child_autofree(world)
	var spawner: Spawner = Spawner.new()
	spawner.world = world
	add_child_autofree(spawner)
	return spawner


## The orb started at `at`: x exact; y at most a frame's physics drift below it.
func _assert_dropped_at(orb: EnergyOrb, at: Vector2) -> void:
	assert_eq(orb.global_position.x, at.x)
	assert_between(orb.global_position.y, at.y, at.y + 40.0, "spawned at the point, then drifted down")


func _orbs(spawner: Spawner) -> Array[EnergyOrb]:
	var out: Array[EnergyOrb] = []
	for child: Node in spawner.world.get_node("Pickups").get_children():
		if child is EnergyOrb:
			(child as EnergyOrb).set_physics_process(false)
			out.append(child as EnergyOrb)
	return out


var _order: Array[String] = []


func _set_chance(type_id: String, chance: float) -> void:
	((Config.tuning["drops"] as Dictionary)[type_id] as Dictionary)["chance"] = chance


func _spawn(spawner: Spawner, type_id: StringName, pos: Vector2) -> Enemy:
	var enemy: Enemy = spawner.spawn_enemy(type_id, {"position": pos})
	enemy.set_physics_process(false)
	return enemy


func _on_order_killed(_t: StringName, _p: Vector2, _a: bool) -> void:
	_order.append("killed")


func test_kill_drops_an_orb_at_the_death_point() -> void:
	var spawner: Spawner = _drop_world()
	_set_chance("wasp", 1.0)
	_spawn(spawner, &"wasp", Vector2(640, 200)).apply_damage(99, null)
	await wait_process_frames(1)
	var orbs: Array[EnergyOrb] = _orbs(spawner)
	assert_eq(orbs.size(), 1)
	if orbs.size() == 1:
		_assert_dropped_at(orbs[0], Vector2(640, 200))


func test_missed_roll_drops_nothing() -> void:
	var spawner: Spawner = _drop_world()
	_set_chance("wasp", 0.0)
	_spawn(spawner, &"wasp", Vector2(640, 200)).apply_damage(99, null)
	await wait_process_frames(1)
	assert_eq(_orbs(spawner).size(), 0)


func test_bastion_drops_two_orbs_32_px_apart() -> void:
	var spawner: Spawner = _drop_world()
	_spawn(spawner, &"bastion", Vector2(800, 200)).apply_damage(999, null)
	Feedback.reset()
	await wait_process_frames(1)
	var xs: Array[float] = []
	for orb: EnergyOrb in _orbs(spawner):
		xs.append(orb.global_position.x)
		_assert_dropped_at(orb, Vector2(orb.global_position.x, 200))
	xs.sort()
	assert_eq(xs, [784.0, 816.0] as Array[float])


func test_contact_kill_drops_too() -> void:
	var spawner: Spawner = _drop_world()
	_set_chance("wasp", 1.0)
	_spawn(spawner, &"wasp", Vector2(640, 200)).destroy_by_contact()
	await wait_process_frames(1)
	assert_eq(_orbs(spawner).size(), 1)


func test_kill_signals_keep_their_order_and_orbs_arrive_deferred() -> void:
	var spawner: Spawner = _drop_world()
	_set_chance("wasp", 1.0)
	_order.clear()
	var wasp: Enemy = _spawn(spawner, &"wasp", Vector2(640, 200))
	Events.enemy_killed.connect(_on_order_killed)
	wasp.resolved.connect(func() -> void: _order.append("resolved"))
	wasp.apply_damage(99, null)
	Events.enemy_killed.disconnect(_on_order_killed)
	assert_eq(_order, ["killed", "resolved"] as Array[String])
	assert_eq(_orbs(spawner).size(), 0, "orbs arrive deferred")
	await wait_process_frames(1)
	assert_eq(_orbs(spawner).size(), 1)


func test_enemy_without_spawner_drops_nothing_silently() -> void:
	_set_chance("wasp", 1.0)
	var wasp: Enemy = _make_wasp()
	wasp.set_physics_process(false)
	wasp.apply_damage(99, null)
	await wait_process_frames(1)
	assert_eq(get_tree().get_nodes_in_group(&"pickups").size(), 0, "no orb anywhere")
	assert_eq(_logged("[ERROR]").size(), 0)
	assert_eq(_logged("[WARN]").size(), 0)
