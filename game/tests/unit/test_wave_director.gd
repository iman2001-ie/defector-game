extends GutTest
## WaveDirector: every row of the Story 2.2 I/O matrix, against a minimal
## World + Spawner fixture and inline level dictionaries.

const SRC: String = "res://data/levels/level_test.json"
const GAP_S: float = 0.05

var _root: Node
var _world: Node2D
var _director: WaveDirector
## Every wave/level Events emission: [signal name, args...].
var _events: Array[Array] = []
var _lines: Array[String] = []
var _recorders: Dictionary = {}


func before_each() -> void:
	(Config.tuning["waves"] as Dictionary)["gap_s"] = GAP_S
	_events.clear()
	_lines.clear()
	_recorders = {
		"wave_started": func(i: int, n: int) -> void: _events.append(["wave_started", i, n]),
		"wave_progress_changed": func(i: int, r: float) -> void: _events.append(["wave_progress_changed", i, r]),
		"wave_cleared": func(i: int) -> void: _events.append(["wave_cleared", i]),
		"level_cleared": func(id: int) -> void: _events.append(["level_cleared", id]),
	}
	for signal_name: String in _recorders:
		Events.connect(signal_name, _recorders[signal_name])
	Log.sink = _capture
	_root = Node.new()
	_world = Node2D.new()
	_world.name = "World"
	for container: String in ["Asteroids", "Enemies", "Projectiles"]:
		var node: Node2D = Node2D.new()
		node.name = container
		_world.add_child(node)
	var spawner: Spawner = Spawner.new()
	spawner.world = _world
	_director = WaveDirector.new()
	_director.spawner = spawner
	_director.rng.seed = 7
	_root.add_child(_world)
	_root.add_child(spawner)
	_root.add_child(_director)
	add_child_autofree(_root)


func after_each() -> void:
	for signal_name: String in _recorders:
		Events.disconnect(signal_name, _recorders[signal_name])
	_recorders = {}
	Log.sink = Callable()
	Config.load_data()
	PauseArbiter.clear()
	_director = null


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


## Real-time wait that also works while the tree is paused (GUT's
## wait_seconds timer pauses with the tree; process frames keep coming).
func _wait_real(seconds: float) -> void:
	var end_ms: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end_ms:
		await wait_process_frames(1)


func _lines_containing(text: String) -> Array[String]:
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


## Live (not dying) enemies in the fixture's Enemies container.
func _enemies() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for child: Node in _world.get_node("Enemies").get_children():
		var enemy: Enemy = child as Enemy
		if enemy != null and not enemy.is_dead() and not enemy.is_queued_for_deletion():
			out.append(enemy)
	return out


func _counted() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for enemy: Enemy in _enemies():
		if enemy.is_in_group(&"counted"):
			out.append(enemy)
	return out


func _kill(count: int) -> void:
	var live: Array[Enemy] = _enemies()
	for i: int in mini(count, live.size()):
		live[i].apply_damage(live[i].hp, null)


func _wasps(count: int, formation: String = "") -> Dictionary:
	var entry: Dictionary = {"type": "wasp", "count": float(count)}
	if not formation.is_empty():
		entry["formation"] = formation
	return entry


func _start(waves: Array, id: int = 3) -> void:
	_director.start_level({"id": float(id), "waves": waves}, SRC)


# --- Wave start ---------------------------------------------------------------

func test_wave_start_counts_spawns_and_groups() -> void:
	_start([{
		"spawns": [_wasps(8, "grid_4x2")],
		"groups": {"r": [_wasps(4)]},
		"triggers": [
			{"when": "wave_start", "actions": [{"wait": 0.05}]},
			{"when": "progress", "at": 1.0, "actions": [{"spawn_group": "r"}]},
		],
	}])
	assert_eq(_events_named("wave_started"), [["wave_started", 0, 1]] as Array[Array], "wave_started(0, 1)")
	assert_eq(_director.total_count(), 12, "spawns + group entries counted up front")
	assert_eq(_director.resolved_count(), 0)
	assert_eq(_counted().size(), 8, "8 Wasps in counted")
	assert_eq(_director.running_chains(), 1, "wave_start trigger running")
	assert_eq(_director.wave_number(), 1)
	assert_eq(_director.wave_count(), 1)
	assert_eq(_lines_containing("[INFO][wave] Level 3 wave 1/1 started").size(), 1, "INFO wave start")
	assert_eq(_lines_containing("[INFO][beat]").size(), 1, "INFO beat fired")
	var first: Enemy = _counted()[0]
	assert_eq((first as Wasp).formation_slot(), Vector2(720, 160), "grid_4x2 slot from waves.formation tuning")


func test_entries_stack_on_the_next_free_rows() -> void:
	_start([{"spawns": [_wasps(4, "grid_4x1"), _wasps(2, "grid_2x1")]}])
	var ys: Dictionary = {}
	for enemy: Enemy in _counted():
		ys[(enemy as Wasp).formation_slot().y] = true
	assert_eq(ys.keys().size(), 2, "two rows")
	assert_true(ys.has(160.0) and ys.has(280.0), "second entry starts on row 1")


## DW-37 (R5): Hunter Wasps never hold their slot, so they don't advance the
## formation row; the next entry starts on the same row.
func _assert_rowless(rowless: String) -> void:
	_start([{"spawns": [{"type": rowless, "count": 2.0, "formation": "grid_2x2"}, _wasps(2, "grid_2x1")]}])
	var wasps: int = 0
	var rowless_count: int = 0
	for enemy: Enemy in _counted():
		if enemy is Wasp:
			wasps += 1
			assert_eq((enemy as Wasp).formation_slot().y, 160.0, "after %s, Wasps start on row 0 (top_y)" % rowless)
		else:
			rowless_count += 1
	assert_eq(wasps, 2, "two Wasps after %s" % rowless)
	assert_eq(rowless_count, 2, "two %s spawned" % rowless)


## DW-37 (R5): the Needle anchors on row 0 (enemies.needle.anchor_y_px = top_y)
## and roams it, so it takes a row: the shipped level_dev.json wave 4's Wasps
## after its Needles start on row 1, off the Needle anchors.
func test_needles_take_a_row() -> void:
	var level: Dictionary = Config.level("dev")
	_start([(level.waves as Array)[3]])
	var row_1: float = Config.num("waves.formation.top_y") + Config.num("waves.formation.spacing_px.y")
	var anchor_y: float = Config.num("enemies.needle.anchor_y_px")
	var wasps: int = 0
	var needles: int = 0
	for enemy: Enemy in _counted():
		if enemy is Wasp:
			wasps += 1
			var slot: Vector2 = (enemy as Wasp).formation_slot()
			assert_eq(slot.y, row_1, "after Needles, Wasps start on row 1")
			assert_ne(slot.y, anchor_y, "no Wasp slot on the Needle anchor row")
		elif enemy is Needle:
			needles += 1
	assert_eq(row_1, 280.0, "row 1 is y 280 with the shipped tuning")
	assert_eq(wasps, 4, "four Wasps after the Needles")
	assert_eq(needles, 2, "two Needles spawned")


func test_hunter_wasps_do_not_advance_the_row() -> void:
	Config.flags["hunter_wasp"] = true
	_assert_rowless("hunter_wasp")


func test_sides_entry_reaches_the_wasp() -> void:
	_start([{"spawns": [{"type": "wasp", "count": 2.0, "formation": "grid_2x1", "entry": "sides"}]}])
	var counted: Array[Enemy] = _counted()
	assert_eq(counted.size(), 2)
	for enemy: Enemy in counted:
		var wasp: Wasp = enemy as Wasp
		var slot: Vector2 = wasp.formation_slot()
		var half: float = wasp.sprite_px / 2.0
		var side_x: float = -half if slot.x <= Playfield.SIZE.x / 2.0 else Playfield.SIZE.x + half
		assert_eq(wasp.state(), Wasp.State.ENTER, "entering")
		assert_eq(wasp.global_position.y, slot.y, "at its slot's height")
		assert_eq(wasp.global_position.x, side_x, "off-screen on the nearer side")


## AC3: a diving Wasp that leaves and returns leaves the wave's counts untouched.
func test_wasp_leaving_the_screen_does_not_resolve() -> void:
	_start([{"spawns": [_wasps(1)]}])
	var wasp: Wasp = _counted()[0] as Wasp
	wasp.set_physics_process(false)
	var dt: float = 1.0 / 60.0
	var t: float = 0.0
	while not wasp.is_holding() and t < 5.0:
		wasp.step(dt)
		t += dt
	assert_true(wasp.is_holding(), "reached its slot")
	wasp.start_dive()
	var left: bool = false
	t = 0.0
	while t < 10.0 and not (left and wasp.is_holding()):
		wasp.step(dt)
		t += dt
		if wasp.state() == Wasp.State.ENTER:
			left = true
	assert_true(left, "left the screen and re-entered")
	assert_true(wasp.is_holding(), "back on its slot")
	assert_eq(_director.resolved_count(), 0, "nothing resolved")
	assert_eq(_director.total_count(), 1)
	assert_eq(_events_named("wave_cleared").size(), 0, "no wave_cleared")


# --- Asteroids ----------------------------------------------------------------

func test_asteroids_spawn_at_the_top_and_never_count() -> void:
	_start([{"spawns": [_wasps(1)], "asteroids": [{"size": "small", "count": 3.0}, {"size": "huge", "count": 1.0}]}])
	assert_push_error("asteroids[1].size")
	var rocks: Array[Node] = _world.get_node("Asteroids").get_children()
	assert_eq(rocks.size(), 3, "3 small asteroids, the unknown size skipped")
	for node: Node in rocks:
		var rock: Asteroid = node as Asteroid
		rock.set_physics_process(false)
		assert_eq(rock.size, &"small")
		assert_eq(rock.global_position.y, -rock.radius, "just above the top edge")
		assert_false(rock.is_in_group(&"counted"), "never counted")
	assert_eq(_director.total_count(), 1, "asteroids not in the total")


# --- Unknown type -------------------------------------------------------------

func test_unknown_type_is_logged_subtracted_and_the_wave_still_clears() -> void:
	_start([{"spawns": [{"type": "bogus", "count": 2.0}, _wasps(1)]}])
	assert_push_error("%s waves[0].spawns[0].type" % SRC)
	assert_eq(_director.total_count(), 1, "the bogus entry subtracted")
	var changes: Array[Array] = _events_named("wave_progress_changed")
	assert_eq(changes.size(), 1, "the subtraction emits wave_progress_changed")
	if changes.size() == 1:
		assert_almost_eq(changes[0][2] as float, 0.0, 0.0001, "ratio 0 of 1 after the subtraction")
	assert_eq(_counted().size(), 1)
	assert_eq(_events_named("wave_cleared").size(), 0, "not clear yet")
	_kill(1)
	assert_eq(_events_named("wave_cleared"), [["wave_cleared", 0]] as Array[Array], "clears after the Wasp dies")


# --- Feature-flag gate (Story 2.8) --------------------------------------------

func _hunters(count: int, formation: String = "") -> Dictionary:
	var entry: Dictionary = {"type": "hunter_wasp", "count": float(count)}
	if not formation.is_empty():
		entry["formation"] = formation
	return entry


func _skip_lines() -> Array[String]:
	return _lines_containing("hunter_wasp skipped (flag 'hunter_wasp' off); not counted")


func test_flag_off_skips_hunters_uncounted_and_the_wave_clears() -> void:
	Config.flags["hunter_wasp"] = false
	_start([{"spawns": [_hunters(4, "grid_4x1"), _wasps(2, "grid_2x1")]}])
	assert_eq(_director.total_count(), 2, "hunters not counted")
	assert_eq(_enemies().size(), 2, "only the Wasps spawned")
	for enemy: Enemy in _enemies():
		assert_true(enemy is Wasp)
		assert_eq((enemy as Wasp).formation_slot().y, 160.0, "Wasps take formation row 0")
	assert_eq(_skip_lines(), [
		"[DEBUG][spawn] %s waves[0].spawns[0]: 4 x hunter_wasp skipped (flag 'hunter_wasp' off); not counted" % SRC,
	] as Array[String], "one DEBUG skip line")
	assert_eq(_events_named("wave_progress_changed").size(), 0, "not a subtraction")
	_kill(1)
	assert_eq(_events_named("wave_cleared").size(), 0, "not clear yet")
	_kill(1)
	assert_eq(_events_named("wave_cleared").size(), 1, "clears after 2 resolves")


func test_flag_on_spawns_counted_hunters() -> void:
	Config.flags["hunter_wasp"] = true
	_start([{"spawns": [_hunters(4, "grid_4x1"), _wasps(2, "grid_2x1")]}])
	assert_eq(_director.total_count(), 6)
	var hunters: int = 0
	var wasps: int = 0
	for enemy: Enemy in _counted():
		if enemy is HunterWasp:
			hunters += 1
		elif enemy is Wasp:
			wasps += 1
			assert_eq((enemy as Wasp).formation_slot().y, 160.0, "hunters are rowless: Wasps on row 0")
	assert_eq(hunters, 4, "4 counted Hunter Wasps")
	assert_eq(wasps, 2, "2 counted Wasps")
	assert_eq(_skip_lines().size(), 0, "nothing skipped")
	_kill(6)
	assert_eq(_events_named("wave_cleared").size(), 1)


func test_flag_off_group_entry_is_not_counted_or_spawned() -> void:
	Config.flags["hunter_wasp"] = false
	_start([{
		"spawns": [_wasps(1)],
		"groups": {"r": [_hunters(2), _wasps(1)]},
		"triggers": [{"when": "progress", "at": 0.5, "actions": [{"spawn_group": "r"}]}],
	}])
	assert_eq(_director.total_count(), 2, "the group's hunters are not in the total")
	_kill(1)
	await wait_process_frames(2)
	assert_eq(_counted().size(), 1, "the group spawned only its Wasp")
	for enemy: Enemy in _enemies():
		assert_false(enemy is HunterWasp, "no Hunter spawned")
	assert_eq(_skip_lines(), [
		"[DEBUG][spawn] %s waves[0].groups.r[0]: 2 x hunter_wasp skipped (flag 'hunter_wasp' off); not counted" % SRC,
	] as Array[String])
	_kill(1)
	assert_eq(_director.total_count(), 2, "nothing subtracted")
	assert_eq(_events_named("wave_cleared").size(), 1, "wave clears")


func test_flag_gate_is_read_once_per_wave() -> void:
	Config.flags["hunter_wasp"] = false
	_start([{
		"spawns": [_wasps(1)],
		"groups": {"r": [_hunters(2), _wasps(1)]},
		"triggers": [{"when": "progress", "at": 0.5, "actions": [{"spawn_group": "r"}]}],
	}])
	assert_eq(_director.total_count(), 2)
	Config.flags["hunter_wasp"] = true
	_kill(1)
	await wait_process_frames(2)
	for enemy: Enemy in _enemies():
		assert_false(enemy is HunterWasp, "the gate cached at wave start still holds")
	assert_eq(_counted().size(), 1, "only the group's Wasp spawned")
	assert_eq(_director.total_count(), 2, "total unchanged")
	assert_eq(_skip_lines().size(), 1, "the group entry was skipped")


func test_wave_of_only_disabled_entries_clears_without_a_stall() -> void:
	Config.flags["hunter_wasp"] = false
	_start([{"spawns": [_hunters(3, "grid_3x1")]}])
	assert_eq(_director.total_count(), 0, "nothing counted")
	assert_eq(_enemies().size(), 0, "nothing spawned")
	assert_eq(_lines_containing("stalled").size(), 0, "no stall ERROR")
	assert_eq(_events_named("wave_cleared").size(), 1, "the wave clears")


## GDD Level 3 wave 2 shape (decision F14): Hunters stay a known id with the flag off.
func test_cut_story_level_3_wave_2_shape_validates_and_clears() -> void:
	Config.flags["hunter_wasp"] = false
	var data: Dictionary = {"id": 3.0, "waves": [{
		"spawns": [
			{"type": "bastion", "count": 2.0, "formation": "grid_2x1", "entry": "top"},
			{"type": "needle", "count": 2.0, "formation": "grid_2x1", "entry": "top"},
			_hunters(4, "grid_4x1"),
		],
		"asteroids": [{"size": "medium", "count": 3.0}],
	}]}
	var max_columns: int = Formation.max_columns(Vector2(Config.num("waves.formation.spacing_px.x"), 0.0), Playfield.SIZE.x)
	assert_eq(LevelValidator.validate(data, SRC, EntityRegistry.enemy_types(), Config.flags, EntityRegistry.enemy_flags(), max_columns), [] as Array[String], "validates")
	_director.start_level(data, SRC)
	assert_eq(_director.total_count(), 4, "2 Bastions + 2 Needles")
	assert_eq(_counted().size(), 4)
	assert_eq(_skip_lines().size(), 1, "DEBUG skip line")
	_kill(4)
	assert_eq(_events_named("wave_cleared").size(), 1, "clears after 4 resolves")


# --- Progress trigger ---------------------------------------------------------

func test_progress_trigger_fires_once_and_spawns_after_a_pausable_wait() -> void:
	_start([{
		"spawns": [_wasps(2)],
		"groups": {"r": [_wasps(2)]},
		"triggers": [{"when": "progress", "at": 0.5, "actions": [{"wait": 0.2}, {"spawn_group": "r"}]}],
	}])
	_kill(1)
	assert_eq(_director.running_chains(), 0, "0.25 < 0.5: not fired")
	_kill(1)
	assert_eq(_director.running_chains(), 1, "0.5: fired")
	assert_eq(_lines_containing("[INFO][beat]").size(), 1, "fired once")
	PauseArbiter.push(&"menu")
	await _wait_real(0.4)
	assert_eq(_enemies().size(), 0, "the wait holds while paused")
	PauseArbiter.pop(&"menu")
	await wait_seconds(0.3)
	await wait_process_frames(2)
	assert_eq(_counted().size(), 2, "group spawned after the wait")
	assert_eq(_director.running_chains(), 0, "chain finished")
	_kill(2)
	assert_eq(_lines_containing("[INFO][beat]").size(), 1, "never fires twice")
	assert_eq(_events_named("wave_cleared").size(), 1, "wave clears")


func test_progress_changed_after_every_resolve() -> void:
	_start([{"spawns": [_wasps(4)]}])
	_kill(2)
	var changes: Array[Array] = _events_named("wave_progress_changed")
	assert_eq(changes.size(), 2)
	if changes.size() == 2:
		assert_almost_eq(changes[1][2] as float, 0.5, 0.0001, "ratio after 2 of 4")


# --- Group spawned twice ------------------------------------------------------

func test_second_spawn_group_request_is_warned_and_ignored() -> void:
	_start([{
		"spawns": [_wasps(1)],
		"groups": {"r": [_wasps(2)]},
		"triggers": [
			{"when": "wave_start", "actions": [{"spawn_group": "r"}]},
			{"when": "wave_start", "actions": [{"spawn_group": "r"}]},
		],
	}])
	assert_eq(_lines_containing("[WARN][beat]").size(), 1, "second request warned")
	await wait_process_frames(2)
	assert_eq(_counted().size(), 3, "group spawned once")
	assert_eq(_director.total_count(), 3)


# --- Stall net ----------------------------------------------------------------

func test_stall_subtracts_never_spawned_groups() -> void:
	_start([{
		"spawns": [_wasps(1)],
		"groups": {"lost": [_wasps(2)]},
		"triggers": [{"when": "progress", "at": 1.0, "actions": [{"spawn_group": "lost"}]}],
	}])
	assert_eq(_director.total_count(), 3)
	_kill(1)
	assert_push_error("lost")
	assert_eq(_lines_containing("[WARN][beat]").size(), 0, "a given-up group is not re-requested with a false warning")
	assert_eq(_director.total_count(), 1, "group count subtracted")
	assert_eq(_events_named("wave_cleared").size(), 1, "no soft-lock")


# --- Wave clear and the gap ---------------------------------------------------

func test_running_chain_blocks_clear() -> void:
	_start([{"spawns": [_wasps(1)], "triggers": [{"when": "wave_start", "actions": [{"wait": 0.2}]}]}])
	_kill(1)
	assert_eq(_events_named("wave_cleared").size(), 0, "chain still running")
	await wait_seconds(0.3)
	assert_eq(_events_named("wave_cleared").size(), 1, "clears when the chain ends")


func test_wave_clear_runs_triggers_then_gap_then_next_wave() -> void:
	_start([
		{"spawns": [_wasps(1)], "triggers": [{"when": "wave_clear", "actions": [{"wait": 0.25}]}]},
		{"spawns": [_wasps(2)]},
	])
	_kill(1)
	assert_eq(_events_named("wave_cleared"), [["wave_cleared", 0]] as Array[Array])
	assert_eq(_director.running_chains(), 1, "wave_clear trigger running")
	await wait_seconds(GAP_S + 0.05)
	assert_eq(_events_named("wave_started").size(), 1, "gap over, but the chain still holds the next wave")
	await wait_seconds(0.3)
	assert_eq(_events_named("wave_started"), [["wave_started", 0, 2], ["wave_started", 1, 2]] as Array[Array], "next wave")
	assert_eq(_director.total_count(), 2)
	assert_eq(_counted().size(), 2)


func test_gap_is_pausable() -> void:
	(Config.tuning["waves"] as Dictionary)["gap_s"] = 0.2
	_start([{"spawns": [_wasps(1)]}, {"spawns": [_wasps(1)]}])
	_kill(1)
	PauseArbiter.push(&"menu")
	await _wait_real(0.4)
	assert_eq(_events_named("wave_started").size(), 1, "no next wave while paused")
	PauseArbiter.pop(&"menu")
	await wait_seconds(0.4)
	assert_eq(_events_named("wave_started").size(), 2, "next wave once unpaused")


# --- Last wave ----------------------------------------------------------------

func test_last_wave_clears_the_level() -> void:
	_start([{"spawns": [_wasps(1)]}], 5)
	_kill(1)
	assert_eq(_events_named("level_cleared").size(), 0, "after the gap")
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_events_named("level_cleared"), [["level_cleared", 5]] as Array[Array])
	assert_eq(_lines_containing("[INFO][wave] Level 5 cleared").size(), 1, "INFO level clear")
	assert_true(_director.is_level_cleared())


# --- Boss wave ----------------------------------------------------------------

func test_boss_wave_without_a_flagship_is_subtracted_and_clears() -> void:
	_start([{"boss": "flagship", "triggers": []}])
	assert_push_error("boss 'flagship'")
	assert_eq(_director.total_count(), 0)
	assert_eq(_events_named("wave_cleared"), [["wave_cleared", 0]] as Array[Array])


# --- F3 -----------------------------------------------------------------------

func test_f3_resolves_the_wave_and_fires_pending_triggers_in_order() -> void:
	_start([
		{
			"spawns": [_wasps(4)],
			"groups": {"r": [_wasps(4)]},
			"triggers": [
				{"when": "progress", "at": 0.25, "actions": [{"comms": "first"}]},
				{"when": "progress", "at": 0.75, "actions": [{"comms": "third"}]},
				{"when": "progress", "at": 0.5, "actions": [{"spawn_group": "r"}]},
			],
		},
		{"spawns": [_wasps(1)]},
	])
	var live: Array[Enemy] = _counted()
	_director.debug_resolve_wave()
	for enemy: Enemy in live:
		assert_true(enemy.is_dead(), "killed through the death path")
	assert_eq(_director.resolved_count(), _director.total_count(), "fully resolved")
	assert_eq(_director.total_count(), 8, "skipped group resolved, not subtracted")
	var fired: Array[String] = _lines_containing("[INFO][beat]")
	assert_eq(fired.size(), 3, "every progress trigger fired")
	var first_at: int = -1
	var third_at: int = -1
	for i: int in _lines.size():
		if _lines[i].begins_with("[DEBUG][beat] Action") and _lines[i].contains("first"):
			first_at = i
		elif _lines[i].begins_with("[DEBUG][beat] Action") and _lines[i].contains("third"):
			third_at = i
	assert_gt(first_at, -1, "the at 0.25 trigger ran its action")
	assert_gt(third_at, first_at, "the at 0.25 trigger ran before the at 0.75 one")
	assert_eq(_events_named("wave_cleared").size(), 1, "wave cleared")
	# Assert after the gap, once the state is settled, so the outcome never
	# depends on whether the gap ended during a frame wait (DW-35).
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_events_named("wave_started").size(), 2, "next wave starts")
	assert_eq(_lines_containing("[DEBUG][beat] Group 'r' was skipped").size(), 1, "the group's spawn request was refused")
	assert_eq(_lines_containing("group 'r' spawned").size(), 0, "the skipped group never spawns")
	assert_eq(_counted().size(), 1, "only wave 2's Wasp is alive")


func test_f3_cancels_a_pending_group_spawn() -> void:
	_start([{
		"spawns": [_wasps(2)],
		"groups": {"r": [_wasps(2)]},
		"triggers": [{"when": "wave_start", "actions": [{"spawn_group": "r"}]}],
	}])
	_director.debug_resolve_wave()
	await wait_process_frames(2)
	assert_eq(_counted().size(), 0, "pending group cancelled")
	assert_eq(_events_named("wave_cleared").size(), 1)


# --- F6 -----------------------------------------------------------------------

func test_f6_jumps_to_the_boss_wave_and_abandons_chains() -> void:
	_start([
		{
			"spawns": [_wasps(3)],
			"groups": {"r": [_wasps(2)]},
			"triggers": [{"when": "wave_start", "actions": [{"wait": 0.1}, {"spawn_group": "r"}]}],
		},
		{"spawns": [_wasps(1)]},
		{"boss": "flagship"},
	])
	var old: Array[Enemy] = _counted()
	_director.debug_skip_to_boss()
	assert_push_error("boss 'flagship'")
	for enemy: Enemy in old:
		assert_true(enemy.is_queued_for_deletion(), "freed")
		assert_false(enemy.is_dead(), "without resolving")
	assert_eq(_events_named("wave_started").back(), ["wave_started", 2, 3], "boss wave started")
	assert_eq(_director.wave_number(), 3)
	await wait_seconds(0.2)
	assert_eq(_counted().size(), 0, "the abandoned chain spawned nothing")
	assert_eq(_director.running_chains(), 0, "the abandoned chain left the counters alone")
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_events_named("level_cleared").size(), 1, "boss wave subtracted, level cleared")


func test_f6_without_a_boss_wave_logs() -> void:
	_start([{"spawns": [_wasps(1)]}])
	_director.debug_skip_to_boss()
	assert_eq(_lines_containing("[INFO][debug] F6: no boss wave").size(), 1)
	assert_eq(_director.wave_number(), 1, "stays on the wave")
	assert_eq(_counted().size(), 1)


# --- Bad level data -----------------------------------------------------------

func test_level_without_waves_starts_nothing() -> void:
	_director.start_level({"id": 1.0}, SRC)
	assert_push_error("has no waves")
	assert_eq(_events_named("wave_started").size(), 0)
	assert_eq(_director.wave_number(), 0)
