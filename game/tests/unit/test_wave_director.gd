extends GutTest
## WaveDirector: every row of the Story 2.2 I/O matrix, against a minimal
## World + Spawner fixture and inline level dictionaries.

const SRC: String = "res://data/levels/level_test.json"
const GAP_S: float = 0.05
const UnscaledClock := preload("res://tests/fixtures/unscaled_clock.gd")

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
		"comms_sequence_requested": func(id: StringName) -> void: _events.append(["comms_sequence_requested", id]),
		"story_event_requested": func(event_name: StringName) -> void: _events.append(["story_event_requested", event_name]),
		"hint_requested": func(hint_id: StringName) -> void: _events.append(["hint_requested", hint_id]),
		"boss_started": func() -> void: _events.append(["boss_started"]),
		"boss_phase_changed": func(p: int) -> void: _events.append(["boss_phase_changed", p]),
		"boss_hp_changed": func(c: int, m: int, p: int) -> void: _events.append(["boss_hp_changed", c, m, p]),
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
	GameState.is_retry = false
	Audio.stop_music(0.0)
	Audio.music_streams.clear()
	Audio._warned_music.clear()
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
	var top_y: float = Config.num("waves.formation.top_y")
	var row_1: float = top_y + Config.num("waves.formation.spacing_px.y")
	assert_true(ys.has(top_y) and ys.has(row_1), "second entry starts on row 1")


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
	assert_eq(row_1, 250.0, "row 1 is y 250 with the shipped tuning (decision #53)")
	assert_eq(wasps, 4, "four Wasps after the Needles")
	assert_eq(needles, 2, "two Needles spawned")


func test_hunter_wasps_do_not_advance_the_row() -> void:
	Config.flags["hunter_wasp"] = true
	_assert_rowless("hunter_wasp")


## Story 6.2: the Maul never holds its slot either.
func test_mauls_do_not_advance_the_row() -> void:
	_assert_rowless("maul")


## Story 6.2 AC: a Maul that resolves without a kill (here: no convoy, on its
## first step) is counted, so a wave of only Mauls clears.
func test_a_wave_of_only_mauls_clears_without_a_convoy() -> void:
	_start([{"spawns": [{"type": "maul", "count": 3.0, "formation": "grid_3x1", "entry": "sides"}]}])
	assert_eq(_director.total_count(), 3)
	await wait_physics_frames(3)
	assert_eq(_director.resolved_count(), 3, "every Maul resolved")
	await wait_seconds(GAP_S * 4.0)
	assert_eq(_events_named("level_cleared").size(), 1, "the wave (and the one-wave level) clears")


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
## The Needle entry comes first: it must be the first row-taker (DW-68).
func test_cut_story_level_3_wave_2_shape_validates_and_clears() -> void:
	Config.flags["hunter_wasp"] = false
	var data: Dictionary = {"id": 3.0, "waves": [{
		"spawns": [
			{"type": "needle", "count": 2.0, "formation": "grid_2x1", "entry": "top"},
			{"type": "bastion", "count": 2.0, "formation": "grid_2x1", "entry": "top"},
			_hunters(4, "grid_4x1"),
		],
		"asteroids": [{"size": "medium", "count": 3.0}],
	}]}
	var max_columns: int = Formation.max_columns(Vector2(Config.num("waves.formation.spacing_px.x"), 0.0), Playfield.SIZE.x)
	assert_eq(LevelValidator.validate(data, SRC, EntityRegistry.enemy_types(), Config.flags, EntityRegistry.enemy_flags(), EntityRegistry.rowless_types(), max_columns), [] as Array[String], "validates")
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


## DW-77: the gap waits on a pausable child Timer, freed after the gap.
func test_gap_uses_a_pausable_child_timer() -> void:
	_start([{"spawns": [_wasps(1)]}, {"spawns": [_wasps(1)]}])
	_kill(1)
	var timers: Array[Node] = _director.find_children("*", "Timer", false, false)
	assert_eq(timers.size(), 1, "one Timer child")
	if timers.size() == 1:
		assert_eq(timers[0].process_mode, Node.PROCESS_MODE_PAUSABLE)
		assert_almost_eq((timers[0] as Timer).wait_time, GAP_S, 0.0001, "waves.gap_s long")
	await wait_seconds(GAP_S + 0.05)
	assert_eq(_events_named("wave_started").size(), 2, "next wave after the gap")
	await wait_process_frames(1)
	assert_eq(_director.find_children("*", "Timer", false, false).size(), 0, "timer freed")


## DW-77: a zero gap still starts the next wave on a later frame.
func test_zero_gap_starts_the_next_wave_later() -> void:
	(Config.tuning["waves"] as Dictionary)["gap_s"] = 0.0
	_start([{"spawns": [_wasps(1)]}, {"spawns": [_wasps(1)]}])
	_kill(1)
	assert_eq(_events_named("wave_cleared").size(), 1)
	assert_eq(_events_named("wave_started").size(), 1, "never synchronously inside the clear")
	await wait_process_frames(3)
	assert_eq(_events_named("wave_started").size(), 2, "next wave on a later frame")
	assert_engine_error_count(0, "no Timer error")


## DW-77: a death reload during the gap never resumes the freed director.
func test_death_reload_during_the_gap_resumes_nothing() -> void:
	_start([{"spawns": [_wasps(1)]}, {"spawns": [_wasps(1)]}])
	_kill(1)
	assert_eq(_events_named("wave_cleared").size(), 1, "wave 1 cleared")
	Events.level_failed.emit(&"hearts")
	_root.queue_free()
	await wait_process_frames(2)
	assert_false(is_instance_valid(_director), "director freed")
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_events_named("wave_started").size(), 1, "no second wave_started")
	assert_engine_error_count(0, "no 'class instance is gone' error")


# --- Last wave ----------------------------------------------------------------

func test_last_wave_clears_the_level() -> void:
	_start([{"spawns": [_wasps(1)]}], 5)
	_kill(1)
	assert_eq(_events_named("level_cleared").size(), 0, "after the gap")
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_events_named("level_cleared"), [["level_cleared", 5]] as Array[Array])
	assert_eq(_lines_containing("[INFO][wave] Level 5 cleared").size(), 1, "INFO level clear")
	assert_true(_director.is_level_cleared())


## Retro F1: once the player died, the last kill clears nothing; a new
## start_level resets the guard.
func test_dead_attempt_never_clears() -> void:
	_start([{"spawns": [_wasps(1)]}], 5)
	Events.level_failed.emit(&"hearts")
	_kill(1)
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_events_named("wave_cleared"), [] as Array[Array], "no wave_cleared")
	assert_eq(_events_named("level_cleared"), [] as Array[Array], "no level_cleared")
	assert_false(_director.is_level_cleared())
	_start([{"spawns": [_wasps(1)]}], 5)
	_kill(1)
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_events_named("wave_cleared"), [["wave_cleared", 0]] as Array[Array], "a new attempt clears")
	assert_eq(_events_named("level_cleared"), [["level_cleared", 5]] as Array[Array])


func test_death_during_a_gap_never_starts_the_next_wave() -> void:
	_start([{"spawns": [_wasps(1)]}, {"spawns": [_wasps(1)]}])
	_kill(1)
	assert_eq(_events_named("wave_cleared").size(), 1, "wave 1 cleared before the death")
	Events.level_failed.emit(&"hearts")
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_events_named("wave_started").size(), 1, "no second wave_started")


func test_death_during_the_last_gap_never_clears_the_level() -> void:
	_start([{"spawns": [_wasps(1)]}], 5)
	_kill(1)
	assert_eq(_events_named("wave_cleared").size(), 1, "wave cleared before the death")
	Events.level_failed.emit(&"hearts")
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_events_named("level_cleared"), [] as Array[Array], "no level_cleared")


## DW-54: after the death, kills don't resolve, emit no progress, fire no
## progress trigger and never trip the stall net.
func test_kill_after_death_freezes_progress() -> void:
	_start([{
		"spawns": [_wasps(4)],
		"groups": {"r": [_wasps(2)]},
		"triggers": [{"when": "progress", "at": 0.1, "actions": [{"spawn_group": "r"}]}],
	}], 5)
	Events.level_failed.emit(&"hearts")
	_kill(1)
	assert_eq(_director.resolved_count(), 0, "kill not resolved")
	assert_eq(_director.total_count(), 6, "nothing subtracted")
	assert_eq(_events_named("wave_progress_changed"), [] as Array[Array], "no wave_progress_changed")
	assert_eq(_lines_containing("[INFO][beat]"), [] as Array[String], "progress trigger not fired")
	assert_eq(_director.running_chains(), 0)
	_kill(3)
	await wait_process_frames(2)
	assert_eq(_counted().size(), 0, "the group was never requested")
	assert_eq(_director.resolved_count(), 0)
	assert_eq(_lines_containing("stalled"), [] as Array[String], "no stall net")
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_events_named("wave_cleared"), [] as Array[Array], "no wave_cleared")
	assert_eq(_events_named("level_cleared"), [] as Array[Array], "no level_cleared")


## DW-54: a death while the gap waits for wave_clear chains never starts the next wave.
func test_death_while_waiting_for_chains_never_starts_the_next_wave() -> void:
	_start([
		{"spawns": [_wasps(1)], "triggers": [{"when": "wave_clear", "actions": [{"wait": GAP_S + 0.25}]}]},
		{"spawns": [_wasps(1)]},
	])
	_kill(1)
	assert_eq(_events_named("wave_cleared").size(), 1, "wave 1 cleared")
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_director.running_chains(), 1, "gap over, still waiting for the chain")
	Events.level_failed.emit(&"hearts")
	await wait_seconds(0.3)
	assert_eq(_director.running_chains(), 0, "chain finished")
	assert_eq(_events_named("wave_started").size(), 1, "no second wave_started")


## DW-54, DW-78: a group requested before the death still spawns uncounted (a
## failed entry is not subtracted, no stall net), but the chain's later actions
## never run.
func test_group_requested_before_death_spawns_uncounted_and_the_chain_stops() -> void:
	_start([{
		"spawns": [_wasps(2)],
		"groups": {"r": [{"type": "bogus", "count": 1.0}, _wasps(1)]},
		"triggers": [{"when": "wave_start", "actions": [{"spawn_group": "r"}, {"wait": GAP_S}, {"story_event": "e"}]}],
	}])
	assert_eq(_director.total_count(), 4)
	Events.level_failed.emit(&"hearts")
	_kill(2)
	await wait_process_frames(2)
	assert_eq(_counted().size(), 1, "the group's wasp spawned")
	assert_push_error("bogus")
	assert_eq(_lines_containing("[ERROR]").size(), 1, "only the bogus type errors")
	_kill(1)
	await wait_seconds(GAP_S + 0.05)
	assert_eq(_story_events(), [] as Array[Array], "e never emitted")
	assert_eq(_director.running_chains(), 0, "chain stopped")
	assert_eq(_director.total_count(), 4, "nothing subtracted")
	assert_eq(_director.resolved_count(), 0)
	assert_eq(_events_named("wave_progress_changed"), [] as Array[Array], "no wave_progress_changed")
	assert_eq(_lines_containing("stalled"), [] as Array[String], "no stall net")


## DW-78: a death during a wait stops the chain: no later action of any kind runs.
func test_death_during_a_wait_stops_the_chain() -> void:
	_load_dialogue()
	Audio.music_streams[&"combat"] = _silent_wav()
	_start([{
		"spawns": [_wasps(1)],
		"groups": {"r": [_wasps(2)]},
		"triggers": [{"when": "wave_start", "actions": [
			{"wait": 0.1}, {"music": "combat"}, {"comms": "story_a"}, {"story_event": "e"},
			{"hint": "move_fire"}, {"spawn_group": "r"},
		]}],
	}])
	assert_eq(_director.running_chains(), 1, "chain in its wait")
	Events.level_failed.emit(&"hearts")
	await wait_seconds(0.2)
	await wait_process_frames(2)
	assert_eq(Audio.current_music(), &"", "no music action")
	assert_eq(_requests(), [] as Array[Array], "no comms request")
	assert_eq(_story_events(), [] as Array[Array], "no story event")
	assert_eq(_events_named("hint_requested"), [] as Array[Array], "no hint")
	assert_eq(_counted().size(), 1, "no group spawned")
	assert_eq(_director.running_chains(), 0, "chain stopped")
	var stops: Array[String] = _lines_containing("chain stopped")
	assert_eq(stops.size(), 1, "one stop line")
	if stops.size() == 1:
		assert_true(stops[0].begins_with("[INFO][beat]"), "INFO beat line")


## DW-78: a death while a story holds the chain: the chain stops once the story ends.
func test_death_while_a_story_holds_the_chain_stops_it() -> void:
	_load_dialogue()
	_start_chain([{"comms": "story_a"}, {"story_event": "e"}])
	Events.level_failed.emit(&"hearts")
	_finish(&"story_a")
	assert_eq(_story_events(), [] as Array[Array], "e never emitted")
	assert_eq(_director.running_chains(), 0, "chain stopped")
	assert_eq(_lines_containing("chain stopped").size(), 1, "one stop line")


## DW-78: a failed chain held by a story stops on another sequence's finished.
func test_failed_story_chain_stops_on_another_finished() -> void:
	_load_dialogue()
	_start_chain([{"comms": "story_a"}, {"story_event": "e"}])
	Events.level_failed.emit(&"hearts")
	_finish(&"combat_a")
	assert_eq(_director.running_chains(), 0, "chain stopped")
	assert_eq(_story_events(), [] as Array[Array], "e never emitted")
	assert_eq(_lines_containing("chain stopped").size(), 1, "one stop line")


## DW-78: a death during the chain's last await still logs the stop line.
func test_death_during_the_last_wait_logs_the_stop() -> void:
	_start_chain([{"wait": 0.1}])
	Events.level_failed.emit(&"hearts")
	await wait_seconds(0.2)
	assert_eq(_director.running_chains(), 0, "chain stopped")
	var stops: Array[String] = _lines_containing("chain stopped")
	assert_eq(stops.size(), 1, "one stop line")
	if stops.size() == 1:
		assert_true(stops[0].begins_with("[INFO][beat]"), "INFO beat line")


## DW-78: after a stopped chain, a new attempt's chains run normally.
func test_retry_after_a_stopped_chain_runs_chains() -> void:
	_start_chain([{"wait": 0.05}, {"story_event": "e"}])
	Events.level_failed.emit(&"hearts")
	await wait_seconds(0.1)
	assert_eq(_director.running_chains(), 0, "stopped")
	_start_chain([{"wait": 0.05}, {"story_event": "e2"}])
	assert_eq(_director.running_chains(), 1, "new chain running")
	await wait_seconds(0.1)
	assert_eq(_story_events(), [["story_event_requested", &"e2"]] as Array[Array], "the new attempt's chain ran")
	assert_eq(_director.running_chains(), 0)


func test_f3_after_death_refuses() -> void:
	_start([{"spawns": [_wasps(2)]}], 5)
	Events.level_failed.emit(&"hearts")
	_director.debug_resolve_wave()
	assert_eq(_lines_containing("[INFO][debug] F3: attempt failed; nothing to resolve").size(), 1, "INFO refusal")
	assert_eq(_director.resolved_count(), 0, "progress unchanged")
	assert_eq(_counted().size(), 2, "no enemy killed")
	assert_eq(_events_named("wave_progress_changed"), [] as Array[Array])
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_events_named("wave_cleared"), [] as Array[Array], "no wave_cleared")


## DW-54: first outcome wins; a failure after the clear changes nothing.
func test_failure_after_clear_keeps_the_clear() -> void:
	_start([{"spawns": [_wasps(1)]}], 5)
	_kill(1)
	await wait_seconds(GAP_S + 0.1)
	assert_true(_director.is_level_cleared())
	Events.level_failed.emit(&"hearts")
	await wait_seconds(GAP_S + 0.1)
	assert_true(_director.is_level_cleared(), "still cleared")
	assert_eq(_events_named("level_cleared"), [["level_cleared", 5]] as Array[Array], "level_cleared once")


# --- Boss wave (Story 7.3) ----------------------------------------------------

## Live Flagships in the fixture's Enemies container.
func _flagships() -> Array[Flagship]:
	var out: Array[Flagship] = []
	for child: Node in _world.get_node("Enemies").get_children():
		var boss: Flagship = child as Flagship
		if boss != null and not boss.is_queued_for_deletion():
			out.append(boss)
	return out


func _medium_asteroids() -> int:
	var count: int = 0
	for child: Node in _world.get_node("Asteroids").get_children():
		var rock: Asteroid = child as Asteroid
		if rock != null and rock.size == &"medium":
			count += 1
	return count


func test_boss_wave_spawns_the_flagship_counted_as_one() -> void:
	_start([{"boss": "flagship", "triggers": []}])
	assert_eq(_director.total_count(), 1, "the boss counts 1")
	assert_eq(_events_named("wave_started"), [["wave_started", 0, 1]] as Array[Array])
	var bosses: Array[Flagship] = _flagships()
	assert_eq(bosses.size(), 1, "one Flagship under World/Enemies")
	if bosses.size() == 1:
		assert_true(bosses[0].is_in_group(&"boss"), "in Groups.BOSS")
		assert_false(bosses[0].is_in_group(&"counted"), "not in Groups.COUNTED")
		assert_eq(bosses[0].spawner, _director.spawner, "spawned through the Spawner")
	assert_eq(_counted().size(), 0)
	assert_eq(_events_named("boss_started").size(), 1)
	assert_eq(_events_named("boss_phase_changed"), [["boss_phase_changed", 0]] as Array[Array])
	assert_eq(_events_named("boss_hp_changed"), [["boss_hp_changed", 300, 300, 0]] as Array[Array])
	assert_eq(_medium_asteroids(), Config.int_("boss.phase1_medium_asteroids"), "the cover asteroids")
	assert_eq(_medium_asteroids(), 2)
	for rock: Node in _world.get_node("Asteroids").get_children():
		assert_false(rock.is_in_group(&"counted"), "cover never counts")
	assert_eq(_lines_containing("[INFO][wave] Level 3 wave 1: boss 'flagship' spawned").size(), 1)


func test_cover_asteroids_add_to_the_waves_own() -> void:
	_start([{"boss": "flagship", "asteroids": [{"size": "medium", "count": 1.0}, {"size": "small", "count": 2.0}]}])
	assert_eq(_medium_asteroids(), 3, "2 cover + 1 listed")
	assert_eq(_world.get_node("Asteroids").get_child_count(), 5, "plus the 2 small")


func test_boss_wave_never_clears_without_boss_defeated() -> void:
	_start([{"boss": "flagship"}])
	await wait_seconds(GAP_S + 0.2)
	assert_eq(_events_named("wave_cleared"), [] as Array[Array], "no clear while the Flagship lives")
	assert_eq(_director.total_count(), 1, "never subtracted")
	assert_eq(_director.resolved_count(), 0)
	assert_eq(_lines_containing("stalled").size(), 0, "no stall net")
	assert_eq(_flagships().size(), 1)


func test_boss_defeated_resolves_the_wave_once() -> void:
	_start([{"boss": "flagship"}], 5)
	Events.boss_defeated.emit()
	assert_eq(_director.resolved_count(), 1, "1/1")
	assert_eq(_events_named("wave_progress_changed"), [["wave_progress_changed", 0, 1.0]] as Array[Array])
	assert_eq(_events_named("wave_cleared"), [["wave_cleared", 0]] as Array[Array])
	Events.boss_defeated.emit()
	assert_eq(_director.resolved_count(), 1, "a second boss_defeated changes nothing")
	assert_eq(_events_named("wave_progress_changed").size(), 1)
	assert_eq(_events_named("wave_cleared").size(), 1)
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_events_named("level_cleared"), [["level_cleared", 5]] as Array[Array])
	Events.boss_defeated.emit()
	assert_eq(_events_named("level_cleared").size(), 1, "still once")


func test_boss_defeated_before_the_boss_wave_is_ignored() -> void:
	_start([{"spawns": [_wasps(1)]}, {"boss": "flagship"}])
	Events.boss_defeated.emit()
	assert_eq(_director.resolved_count(), 0, "wave 1 isn't a boss wave")
	assert_eq(_events_named("wave_cleared"), [] as Array[Array])


## DW-54: a dead attempt's boss_defeated resolves nothing.
func test_boss_defeated_after_level_failed_does_not_resolve() -> void:
	_start([{"boss": "flagship"}], 5)
	Events.level_failed.emit(&"hearts")
	Events.boss_defeated.emit()
	assert_eq(_director.resolved_count(), 0, "not resolved")
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_events_named("wave_cleared"), [] as Array[Array])
	assert_eq(_events_named("level_cleared"), [] as Array[Array])


func test_unknown_boss_is_logged_subtracted_and_the_wave_clears() -> void:
	_start([{"boss": "bogus", "triggers": []}])
	assert_push_error("boss 'bogus'")
	assert_eq(_director.total_count(), 0, "subtracted")
	assert_eq(_flagships().size(), 0)
	assert_eq(_medium_asteroids(), 0, "no cover without a boss")
	assert_eq(_events_named("wave_cleared"), [["wave_cleared", 0]] as Array[Array])


func test_boss_without_a_spawner_is_logged_subtracted_and_the_wave_clears() -> void:
	_director.spawner = null
	_start([{"boss": "flagship"}])
	assert_push_error("WaveDirector has no spawner")
	assert_push_error("boss 'flagship' has no spawner")
	assert_eq(_director.total_count(), 0, "subtracted")
	assert_eq(_events_named("wave_cleared"), [["wave_cleared", 0]] as Array[Array])


func test_f3_on_a_boss_wave_frees_the_flagship_and_clears() -> void:
	var defeats: Array[int] = [0]
	var on_defeat: Callable = func() -> void: defeats[0] += 1
	Events.boss_defeated.connect(on_defeat)
	_start([{"boss": "flagship"}, {"spawns": [_wasps(1)]}])
	var boss: Flagship = _flagships()[0]
	_director.debug_resolve_wave()
	Events.boss_defeated.disconnect(on_defeat)
	assert_true(boss.is_queued_for_deletion(), "Flagship freed")
	assert_eq(defeats[0], 0, "no boss_defeated")
	assert_eq(_director.resolved_count(), 1, "resolved 1/1")
	assert_eq(_events_named("wave_cleared"), [["wave_cleared", 0]] as Array[Array])
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_events_named("wave_started").size(), 2, "the next wave starts")
	Events.boss_defeated.emit()
	assert_eq(_director.resolved_count(), 0, "a late boss_defeated doesn't touch wave 2")


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
	var fired: Array[String] = _lines_containing("trigger fired")
	assert_eq(fired.size(), 3, "every progress trigger fired")
	var first_at: int = -1
	var third_at: int = -1
	for i: int in _lines.size():
		if _lines[i].begins_with("[INFO][beat]") and _lines[i].contains("comms 'first'"):
			first_at = i
		elif _lines[i].begins_with("[INFO][beat]") and _lines[i].contains("comms 'third'"):
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
	for enemy: Enemy in old:
		assert_true(enemy.is_queued_for_deletion(), "freed")
		assert_false(enemy.is_dead(), "without resolving")
	assert_eq(_events_named("wave_started").back(), ["wave_started", 2, 3], "boss wave started")
	assert_eq(_director.wave_number(), 3)
	await wait_seconds(0.2)
	assert_eq(_counted().size(), 0, "the abandoned chain spawned nothing")
	assert_eq(_director.running_chains(), 0, "the abandoned chain left the counters alone")
	assert_eq(_flagships().size(), 1, "the Flagship spawned")
	assert_eq(_director.total_count(), 1)
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_events_named("level_cleared"), [] as Array[Array], "the boss wave waits for boss_defeated")
	Events.boss_defeated.emit()
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_events_named("level_cleared").size(), 1, "level cleared after boss_defeated")


func test_f6_resets_the_dead_attempt_guard() -> void:
	_start([{"spawns": [_wasps(1)]}, {"boss": "flagship"}])
	Events.level_failed.emit(&"hearts")
	_director.debug_skip_to_boss()
	Events.boss_defeated.emit()
	assert_eq(_director.resolved_count(), 1, "the reopened attempt resolves the boss")
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_events_named("level_cleared").size(), 1, "level cleared")


func test_f6_frees_the_live_flagship_and_starts_a_fresh_one() -> void:
	_start([{"spawns": [_wasps(1)]}, {"boss": "flagship"}])
	_director.debug_skip_to_boss()
	var first: Array[Flagship] = _flagships()
	assert_eq(first.size(), 1)
	_director.debug_skip_to_boss()
	assert_true(first[0].is_queued_for_deletion(), "the old Flagship freed")
	var second: Array[Flagship] = _flagships()
	assert_eq(second.size(), 1, "a fresh Flagship")
	if second.size() == 1:
		assert_ne(second[0], first[0])
	assert_eq(_events_named("wave_started").back(), ["wave_started", 1, 2], "the boss wave restarted")
	assert_eq(_events_named("boss_started").size(), 2)
	assert_eq(_director.total_count(), 1)
	assert_eq(_director.resolved_count(), 0)
	Events.boss_defeated.emit()
	assert_eq(_events_named("wave_cleared"), [["wave_cleared", 1]] as Array[Array], "one boss_defeated clears it")


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


# --- Comms, story events, music, intro and outro (Story 5.3) ------------------

const CHANNEL_DIR: String = "res://tests/fixtures/dialogue/channel/"


## Loads the channel fixture dialogue (story_a, story_b, story_c: story; combat_a: combat).
## The fixture has no CommsChannel: tests emit comms_sequence_finished themselves.
func _load_dialogue() -> void:
	Config.load_data(Config.DEFAULT_TUNING_PATH, Config.DEFAULT_FLAGS_PATH, CHANNEL_DIR)
	(Config.tuning["waves"] as Dictionary)["gap_s"] = GAP_S
	assert_true(Config.dialogue_is_story(&"story_a"), "fixture story_a")
	assert_true(Config.dialogue_is_story(&"story_b"), "fixture story_b")
	assert_true(Config.has_sequence(&"combat_a") and not Config.dialogue_is_story(&"combat_a"), "fixture combat_a")


## One wave of `wasps` Wasps whose wave_start chain is `actions`.
func _start_chain(actions: Array, wasps: int = 1) -> void:
	_start([{"spawns": [_wasps(wasps)], "triggers": [{"when": "wave_start", "actions": actions}]}])


func _requests() -> Array[Array]:
	return _events_named("comms_sequence_requested")


func _story_events() -> Array[Array]:
	return _events_named("story_event_requested")


func _finish(id: StringName) -> void:
	Events.comms_sequence_finished.emit(id)


func test_story_comms_blocks_the_chain_until_finished() -> void:
	_load_dialogue()
	_start_chain([{"comms": "story_a"}, {"story_event": "e"}])
	assert_eq(_requests(), [["comms_sequence_requested", &"story_a"]] as Array[Array], "request emitted")
	assert_eq(_story_events(), [] as Array[Array], "e waits for the story")
	assert_eq(_director.running_chains(), 1, "chain running")
	assert_eq(_lines_containing("[INFO][beat] Level 3 wave 1: comms 'story_a'").size(), 1, "INFO beat line")
	_finish(&"story_a")
	assert_eq(_story_events(), [["story_event_requested", &"e"]] as Array[Array], "e after finished")
	assert_eq(_director.running_chains(), 0, "chain finished")


func test_f6_abandons_a_chain_waiting_on_a_story() -> void:
	_load_dialogue()
	_start([
		{"spawns": [_wasps(1)], "triggers": [{"when": "wave_start", "actions": [{"comms": "story_a"}, {"story_event": "e"}]}]},
		{"boss": "flagship"},
	])
	assert_eq(_director.running_chains(), 1, "chain waiting on story_a")
	_director.debug_skip_to_boss()
	assert_eq(_director.running_chains(), 0, "F6 dropped the chain count")
	_finish(&"story_a")
	assert_eq(_story_events(), [] as Array[Array], "the abandoned chain runs nothing")
	assert_eq(_director.running_chains(), 0, "the abandoned chain left the counters alone")


func test_combat_comms_does_not_block() -> void:
	_load_dialogue()
	_start_chain([{"comms": "combat_a"}, {"story_event": "e"}])
	assert_eq(_requests(), [["comms_sequence_requested", &"combat_a"]] as Array[Array])
	assert_eq(_story_events(), [["story_event_requested", &"e"]] as Array[Array], "e in the same call")
	assert_eq(_director.running_chains(), 0)


func test_unknown_comms_id_does_not_block() -> void:
	_load_dialogue()
	_start_chain([{"comms": "nope"}, {"story_event": "e"}])
	assert_eq(_requests(), [["comms_sequence_requested", &"nope"]] as Array[Array], "request emitted")
	assert_eq(_story_events(), [["story_event_requested", &"e"]] as Array[Array], "e follows at once")
	assert_eq(_director.running_chains(), 0)


func test_another_ids_finished_keeps_waiting() -> void:
	_load_dialogue()
	_start_chain([{"comms": "story_a"}, {"story_event": "e"}])
	_finish(&"story_b")
	assert_eq(_story_events(), [] as Array[Array], "still waiting")
	assert_eq(_director.running_chains(), 1)
	_finish(&"story_a")
	assert_eq(_story_events().size(), 1, "released by its own id")


func test_synchronous_finished_during_the_request_continues() -> void:
	_load_dialogue()
	var instant: Callable = func(id: StringName) -> void: Events.comms_sequence_finished.emit(id)
	Events.comms_sequence_requested.connect(instant)
	_start_chain([{"comms": "story_a"}, {"story_event": "e"}])
	Events.comms_sequence_requested.disconnect(instant)
	assert_eq(_story_events(), [["story_event_requested", &"e"]] as Array[Array], "chain continued")
	assert_eq(_director.running_chains(), 0)


func test_story_event_is_emitted_once() -> void:
	_start_chain([{"story_event": "tarek_fall"}])
	assert_eq(_story_events(), [["story_event_requested", &"tarek_fall"]] as Array[Array])
	assert_eq(_lines_containing("[INFO][beat] Level 3 wave 1: story event 'tarek_fall'").size(), 1)


func test_hint_action_emits_hint_requested() -> void:
	_start_chain([{"hint": "move_fire"}])
	assert_eq(_events_named("hint_requested"), [["hint_requested", &"move_fire"]] as Array[Array])
	assert_eq(_lines_containing("[INFO][beat] Level 3 wave 1: hint 'move_fire'").size(), 1, "INFO beat line")
	assert_eq(_lines_containing("unknown action").size(), 0, "hint is a known action")
	assert_eq(_director.running_chains(), 0, "the chain finished at once")


func test_hint_action_never_blocks_the_chain() -> void:
	_start_chain([{"hint": "missile"}, {"story_event": "e"}])
	assert_eq(_events_named("hint_requested"), [["hint_requested", &"missile"]] as Array[Array])
	assert_eq(_story_events(), [["story_event_requested", &"e"]] as Array[Array], "e runs in the same chain step")
	assert_eq(_director.running_chains(), 0, "nothing waits on a hint")
	assert_false(get_tree().paused, "a hint never pauses")


func _silent_wav() -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var data: PackedByteArray = PackedByteArray()
	data.resize(2205 * 2)
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = 2205
	return wav


func test_music_actions_play_switch_and_fade_stop() -> void:
	assert_true(await UnscaledClock.settle(self), "unscaled clock settled")
	Audio.music_streams[&"combat"] = _silent_wav()
	Audio.music_streams[&"boss"] = _silent_wav()
	_start([{
		"spawns": [_wasps(2)],
		"triggers": [
			{"when": "wave_start", "actions": [{"music": "combat"}]},
			{"when": "progress", "at": 0.5, "actions": [{"music": "boss"}]},
			{"when": "progress", "at": 1.0, "actions": [{"music": "stop"}]},
		],
	}])
	var player: AudioStreamPlayer = Audio.music_player()
	assert_eq(Audio.current_music(), &"combat")
	assert_eq(player.stream, Audio.music_streams[&"combat"])
	_kill(1)
	assert_eq(Audio.current_music(), &"boss", "switched")
	assert_eq(player.stream, Audio.music_streams[&"boss"])
	_kill(1)
	assert_eq(Audio.current_music(), &"", "stop")
	await wait_seconds(0.25)
	assert_lt(player.volume_db, -1.0, "fading over 0.5 s")
	assert_gt(player.volume_db, -80.0)
	await wait_seconds(0.4)
	assert_false(player.playing, "stopped")
	assert_almost_eq(player.volume_db, 0.0, 0.0001, "base volume restored")


func test_missing_music_stream_warns_once_and_stays_silent() -> void:
	Audio.music_streams[&"combat"] = _silent_wav()
	_start_chain([{"music": "combat"}, {"music": "boss"}, {"music": "boss"}])
	assert_eq(Audio.current_music(), &"", "silent")
	assert_false(Audio.music_player().playing, "combat stopped")
	assert_eq(_lines_containing("[WARN][audio]").size(), 1, "one warning")
	assert_push_warning_count(1)


func test_clear_waits_for_a_story_chain() -> void:
	_load_dialogue()
	_start_chain([{"comms": "story_a"}, {"story_event": "e"}], 2)
	_kill(2)
	assert_eq(_director.resolved_count(), 2, "every enemy resolved")
	assert_eq(_events_named("wave_cleared"), [] as Array[Array], "no clear while the story chain waits")
	_finish(&"story_a")
	assert_eq(_events_named("wave_cleared"), [["wave_cleared", 0]] as Array[Array], "clears once the chain ends")


func _level(waves: Array, intro: Variant = null, outro: Variant = null) -> Dictionary:
	return {"id": 3.0, "intro_sequence": intro, "outro_sequence": outro, "waves": waves}


func test_story_intro_holds_wave_one() -> void:
	_load_dialogue()
	_director.start_level(_level([{"spawns": [_wasps(1)]}], "story_a"), SRC)
	assert_eq(_requests(), [["comms_sequence_requested", &"story_a"]] as Array[Array], "intro requested")
	assert_eq(_events_named("wave_started"), [] as Array[Array], "no wave yet")
	assert_eq(_director.wave_number(), 0)
	assert_eq(_lines_containing("[INFO][beat] Level 3 intro 'story_a'").size(), 1)
	_finish(&"story_b")
	assert_eq(_events_named("wave_started"), [] as Array[Array], "a finished for another id")
	_finish(&"story_a")
	assert_eq(_events_named("wave_started"), [["wave_started", 0, 1]] as Array[Array], "wave 1 after the intro")
	assert_eq(_counted().size(), 1)


func test_intro_is_skipped_on_retry() -> void:
	_load_dialogue()
	GameState.is_retry = true
	_director.start_level(_level([{"spawns": [_wasps(1)]}], "story_a"), SRC)
	assert_eq(_requests(), [] as Array[Array], "no request")
	assert_eq(_events_named("wave_started"), [["wave_started", 0, 1]] as Array[Array], "wave 1 at once")
	assert_eq(_lines_containing("[INFO][beat] Level 3 intro 'story_a' skipped (retry)").size(), 1, "INFO skip line")


func test_combat_intro_does_not_hold_wave_one() -> void:
	_load_dialogue()
	_director.start_level(_level([{"spawns": [_wasps(1)]}], "combat_a"), SRC)
	assert_eq(_requests(), [["comms_sequence_requested", &"combat_a"]] as Array[Array])
	assert_eq(_events_named("wave_started").size(), 1, "wave 1 at once")


func test_restart_during_the_intro_abandons_it() -> void:
	_load_dialogue()
	_director.start_level(_level([{"spawns": [_wasps(1)]}], "story_a"), SRC)
	_director.start_level(_level([{"spawns": [_wasps(1)]}]), SRC)
	assert_eq(_events_named("wave_started").size(), 1, "the new level started")
	_finish(&"story_a")
	assert_eq(_events_named("wave_started").size(), 1, "the old intro starts nothing")
	assert_eq(_counted().size(), 1)


func test_f6_during_the_intro_abandons_it() -> void:
	_load_dialogue()
	_director.start_level(_level([{"spawns": [_wasps(1)]}, {"boss": "flagship"}], "story_a"), SRC)
	_director.debug_skip_to_boss()
	assert_eq(_events_named("wave_started"), [["wave_started", 1, 2]] as Array[Array], "boss wave")
	_finish(&"story_a")
	assert_eq(_events_named("wave_started").size(), 1, "the intro starts nothing after F6")


func test_story_outro_plays_before_level_cleared() -> void:
	_load_dialogue()
	_director.start_level(_level([{"spawns": [_wasps(1)]}], null, "story_b"), SRC)
	_kill(1)
	assert_eq(_requests(), [] as Array[Array], "not before the gap")
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_requests(), [["comms_sequence_requested", &"story_b"]] as Array[Array], "outro after the gap")
	assert_eq(_lines_containing("[INFO][beat] Level 3 outro 'story_b'").size(), 1)
	assert_eq(_events_named("level_cleared"), [] as Array[Array], "waits for the outro")
	assert_false(_director.is_level_cleared())
	_finish(&"story_b")
	assert_eq(_events_named("level_cleared"), [["level_cleared", 3]] as Array[Array], "cleared after the outro")
	assert_true(_director.is_level_cleared())


func test_outro_plays_on_retry_too() -> void:
	_load_dialogue()
	GameState.is_retry = true
	_director.start_level(_level([{"spawns": [_wasps(1)]}], null, "story_b"), SRC)
	_kill(1)
	await wait_seconds(GAP_S + 0.1)
	assert_eq(_requests(), [["comms_sequence_requested", &"story_b"]] as Array[Array], "outro requested on a retry")
	_finish(&"story_b")
	assert_eq(_events_named("level_cleared").size(), 1)


func test_death_during_the_outro_never_clears() -> void:
	_load_dialogue()
	_director.start_level(_level([{"spawns": [_wasps(1)]}], null, "story_b"), SRC)
	_kill(1)
	await wait_seconds(GAP_S + 0.1)
	Events.level_failed.emit(&"hearts")
	_finish(&"story_b")
	assert_eq(_events_named("level_cleared"), [] as Array[Array], "no level_cleared")
	assert_false(_director.is_level_cleared())


func test_death_reload_drops_a_chain_waiting_on_a_story() -> void:
	_load_dialogue()
	_start_chain([{"comms": "story_a"}, {"story_event": "e"}])
	Events.level_failed.emit(&"hearts")
	_root.queue_free()
	await wait_process_frames(2)
	assert_false(is_instance_valid(_director), "director freed")
	_finish(&"story_a")
	await wait_process_frames(2)
	assert_eq(_story_events(), [] as Array[Array], "the freed chain runs nothing")


func test_death_reload_drops_a_chain_in_a_wait() -> void:
	_start_chain([{"wait": 0.1}, {"story_event": "e"}])
	Events.level_failed.emit(&"hearts")
	_root.queue_free()
	await wait_process_frames(2)
	assert_false(is_instance_valid(_director), "director freed")
	await wait_seconds(0.25)
	assert_eq(_story_events(), [] as Array[Array], "the elapsed wait runs nothing")


func test_death_during_the_intro_starts_nothing() -> void:
	_load_dialogue()
	_director.start_level(_level([{"spawns": [_wasps(1)]}], "story_a"), SRC)
	Events.level_failed.emit(&"hearts")
	_finish(&"story_a")
	assert_eq(_events_named("wave_started"), [] as Array[Array], "no wave_started")
	assert_eq(_counted().size(), 0, "nothing counted")


func test_death_reload_drops_a_waiting_intro() -> void:
	_load_dialogue()
	_director.start_level(_level([{"spawns": [_wasps(1)]}], "story_a"), SRC)
	_root.queue_free()
	await wait_process_frames(2)
	assert_false(is_instance_valid(_director), "director freed")
	_finish(&"story_a")
	await wait_process_frames(2)
	assert_eq(_events_named("wave_started"), [] as Array[Array], "the freed intro starts nothing")


func test_wait_uses_a_pausable_child_timer() -> void:
	_start_chain([{"wait": 0.1}, {"story_event": "e"}])
	var timers: Array[Node] = _director.find_children("*", "Timer", false, false)
	assert_eq(timers.size(), 1, "one Timer child")
	if timers.size() == 1:
		assert_eq(timers[0].process_mode, Node.PROCESS_MODE_PAUSABLE)
	await wait_seconds(0.2)
	assert_eq(_story_events().size(), 1, "the chain continued")
	await wait_process_frames(1)
	assert_eq(_director.find_children("*", "Timer", false, false).size(), 0, "timer freed")
