extends GutTest
## Loot (Story 3.3): the drop roll (orb_count) and Loot.drop, which asks a
## Spawner for the orbs (deferred), spread energy.orb_spread_px apart and centred
## on the death point. Drop outcomes are forced through Config.tuning.drops.

var _world: Node2D
var _pickups: Node2D


func before_each() -> void:
	_world = Node2D.new()
	for container: String in ["Projectiles", "Enemies", "Asteroids"]:
		var node: Node2D = Node2D.new()
		node.name = container
		_world.add_child(node)
	_pickups = Node2D.new()
	_pickups.name = "Pickups"
	_world.add_child(_pickups)
	add_child_autofree(_world)


func after_each() -> void:
	Config.assert_on_missing = true
	Config.load_data()
	_world = null
	_pickups = null


func _make_spawner() -> Spawner:
	var spawner: Spawner = Spawner.new()
	spawner.world = _world
	add_child_autofree(spawner)
	return spawner


func _set_drop(key: String, chance: float, orbs: int) -> void:
	(Config.tuning["drops"] as Dictionary)[key] = {"chance": chance, "orbs": orbs}


func _orbs() -> Array[EnergyOrb]:
	var out: Array[EnergyOrb] = []
	for child: Node in _pickups.get_children():
		if child is EnergyOrb and not child.is_queued_for_deletion():
			var orb: EnergyOrb = child as EnergyOrb
			orb.set_physics_process(false)
			out.append(orb)
	return out


## The orb started at `at`: x exact; y at most a frame's physics drift below it.
func _assert_dropped_at(orb: EnergyOrb, at: Vector2) -> void:
	assert_eq(orb.global_position.x, at.x)
	assert_between(orb.global_position.y, at.y, at.y + 40.0, "spawned at the point, then drifted down")


# --- orb_count ------------------------------------------------------------------

func test_roll_hit() -> void:
	assert_eq(Loot.orb_count({"chance": 0.15, "orbs": 1}, 0.1), 1)


func test_roll_miss_at_the_chance() -> void:
	assert_eq(Loot.orb_count({"chance": 0.15, "orbs": 1}, 0.15), 0, "roll == chance misses")
	assert_eq(Loot.orb_count({"chance": 0.15, "orbs": 1}, 0.9), 0)


func test_bastion_row_always_gives_two() -> void:
	for roll: float in [0.0, 0.5, 0.999]:
		assert_eq(Loot.orb_count({"chance": 1.0, "orbs": 2}, roll), 2, "roll %s" % roll)


func test_bad_rows_give_zero() -> void:
	assert_eq(Loot.orb_count({}, 0.0), 0, "empty row")
	assert_eq(Loot.orb_count({"orbs": 1}, 0.0), 0, "no chance")
	assert_eq(Loot.orb_count({"chance": "high", "orbs": 1}, 0.0), 0, "chance not a number")
	assert_eq(Loot.orb_count({"chance": 1.0}, 0.0), 0, "no orbs")
	assert_eq(Loot.orb_count({"chance": 1.0, "orbs": "two"}, 0.0), 0, "orbs not a number")


func test_real_rows_match_the_gdd() -> void:
	assert_eq(Loot.orb_count(Config.section("drops.wasp"), 0.149), 1)
	assert_eq(Loot.orb_count(Config.section("drops.wasp"), 0.15), 0)
	assert_eq(Loot.orb_count(Config.section("drops.bastion"), 0.999), 2)


# --- drop -----------------------------------------------------------------------

func test_drop_spawns_one_orb_deferred_at_the_point() -> void:
	var spawner: Spawner = _make_spawner()
	_set_drop("wasp", 1.0, 1)
	assert_eq(Loot.drop(spawner, "wasp", Vector2(500, 300)), 1)
	assert_eq(_orbs().size(), 0, "deferred: nothing yet")
	await wait_process_frames(1)
	var orbs: Array[EnergyOrb] = _orbs()
	assert_eq(orbs.size(), 1)
	if orbs.size() == 1:
		_assert_dropped_at(orbs[0], Vector2(500, 300))


func test_drop_miss_spawns_nothing() -> void:
	var spawner: Spawner = _make_spawner()
	_set_drop("wasp", 0.0, 1)
	assert_eq(Loot.drop(spawner, "wasp", Vector2(500, 300)), 0)
	await wait_process_frames(1)
	assert_eq(_orbs().size(), 0)


func test_bastion_drop_two_orbs_spread_around_the_point() -> void:
	var spawner: Spawner = _make_spawner()
	assert_eq(Loot.drop(spawner, "bastion", Vector2(800, 200), 0.7), 2)
	await wait_process_frames(1)
	var xs: Array[float] = []
	for orb: EnergyOrb in _orbs():
		xs.append(orb.global_position.x)
		_assert_dropped_at(orb, Vector2(orb.global_position.x, 200))
	xs.sort()
	assert_eq(xs, [784.0, 816.0] as Array[float], "32 px apart, centred on the death point")


func test_three_orbs_are_centred() -> void:
	var spawner: Spawner = _make_spawner()
	_set_drop("wasp", 1.0, 3)
	assert_eq(Loot.drop(spawner, "wasp", Vector2(100, 100)), 3)
	await wait_process_frames(1)
	var xs: Array[float] = []
	for orb: EnergyOrb in _orbs():
		xs.append(orb.global_position.x)
	xs.sort()
	assert_eq(xs, [68.0, 100.0, 132.0] as Array[float])


func test_missing_row_drops_nothing() -> void:
	Config.assert_on_missing = false
	var spawner: Spawner = _make_spawner()
	assert_eq(Loot.drop(spawner, "foo", Vector2(100, 100), 0.0), 0)
	assert_push_error("tuning.drops.foo")
	await wait_process_frames(1)
	assert_eq(_orbs().size(), 0)


func test_null_spawner_drops_nothing() -> void:
	_set_drop("wasp", 1.0, 1)
	assert_eq(Loot.drop(null, "wasp", Vector2(100, 100)), 0)


func test_freed_spawner_drops_nothing() -> void:
	_set_drop("wasp", 1.0, 1)
	var spawner: Spawner = Spawner.new()
	spawner.world = _world
	add_child(spawner)
	spawner.free()
	assert_eq(Loot.drop(spawner, "wasp", Vector2(100, 100)), 0)


func test_spawner_freed_before_the_deferred_call() -> void:
	_set_drop("wasp", 1.0, 1)
	var spawner: Spawner = Spawner.new()
	spawner.world = _world
	add_child(spawner)
	assert_eq(Loot.drop(spawner, "wasp", Vector2(100, 100)), 1)
	spawner.free()
	await wait_process_frames(1)
	assert_eq(_orbs().size(), 0, "the deferred spawn is dropped")
