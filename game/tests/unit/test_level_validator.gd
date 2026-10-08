extends GutTest
## LevelValidator: every problem names the source file and the key path;
## field types, action keys, grid width and group/progress reachability.

const SRC: String = "res://data/levels/level_test.json"
const MAX_COLUMNS: int = 12

var _known: Array[StringName] = [&"wasp", &"hunter_wasp"]
var _flags: Dictionary = {"on": true, "off": false, "hunter_wasp": false}
var _type_flags: Dictionary = {&"hunter_wasp": "hunter_wasp"}


func _valid() -> Dictionary:
	return {
		"id": 7,
		"waves": [
			{
				"spawns": [{"type": "wasp", "count": 8.0, "formation": "grid_4x2"}],
				"asteroids": [{"size": "small", "count": 2.0}],
				"groups": {"r": [{"type": "wasp", "count": 4.0, "formation": "grid_4x1"}]},
				"triggers": [
					{"when": "wave_start", "actions": [{"wait": 0.5}]},
					{"when": "progress", "at": 0.5, "actions": [{"wait": 1.0}, {"spawn_group": "r"}]},
				],
			},
			{"boss": "flagship", "triggers": [{"when": "boss_phase", "phase": 2.0, "actions": []}]},
		],
	}


func _validate(data: Dictionary) -> Array[String]:
	return LevelValidator.validate(data, SRC, _known, _flags, _type_flags, MAX_COLUMNS)


## Asserts exactly one problem, naming the source and `path`.
func _assert_one(data: Dictionary, path: String) -> void:
	var problems: Array[String] = _validate(data)
	assert_eq(problems.size(), 1, "one problem: %s" % [problems])
	if problems.size() == 1:
		assert_string_contains(problems[0], SRC)
		assert_string_contains(problems[0], path)


func test_valid_level_has_no_problems() -> void:
	assert_eq(_validate(_valid()), [] as Array[String])


func test_id_must_be_numeric() -> void:
	var data: Dictionary = _valid()
	data["id"] = "seven"
	_assert_one(data, "id")
	data.erase("id")
	_assert_one(data, "id")


func test_waves_must_be_a_non_empty_array_of_objects() -> void:
	var data: Dictionary = _valid()
	data["waves"] = {}
	_assert_one(data, "waves")
	data["waves"] = []
	_assert_one(data, "waves")
	data["waves"] = [3]
	_assert_one(data, "waves[0]")


func test_wave_needs_spawns_or_boss() -> void:
	var data: Dictionary = _valid()
	data["waves"] = [{"triggers": []}]
	_assert_one(data, "waves[0]")
	data["waves"] = [{"spawns": "wasp"}]
	_assert_one(data, "waves[0].spawns")


func test_unknown_spawn_type() -> void:
	var data: Dictionary = _valid()
	data["waves"][0]["spawns"].append({"type": "bogus", "count": 1})
	_assert_one(data, "waves[0].spawns[1].type")


func test_count_must_be_a_positive_integer() -> void:
	for bad: Variant in [0, -2, 1.5, "3", null]:
		var data: Dictionary = _valid()
		data["waves"][0]["spawns"][0]["count"] = bad
		_assert_one(data, "waves[0].spawns[0].count")


func test_invalid_formation() -> void:
	var data: Dictionary = _valid()
	data["waves"][0]["spawns"][0]["formation"] = "grid_4"
	_assert_one(data, "waves[0].spawns[0].formation")


func test_group_entries_are_checked() -> void:
	var data: Dictionary = _valid()
	data["waves"][0]["groups"]["r"][0]["type"] = "bogus"
	_assert_one(data, "waves[0].groups.r[0].type")


func test_asteroid_size_and_count() -> void:
	var data: Dictionary = _valid()
	data["waves"][0]["asteroids"][0]["size"] = "huge"
	_assert_one(data, "waves[0].asteroids[0].size")
	data = _valid()
	data["waves"][0]["asteroids"][0]["count"] = 0
	_assert_one(data, "waves[0].asteroids[0].count")


func test_trigger_when_must_be_known() -> void:
	var data: Dictionary = _valid()
	data["waves"][0]["triggers"][0]["when"] = "sometimes"
	_assert_one(data, "waves[0].triggers[0].when")


## _valid() plus `trigger` as waves[0].triggers[2]. Name no group in it, so a
## bad field is its only problem.
func _with_trigger(trigger: Dictionary) -> Dictionary:
	var data: Dictionary = _valid()
	data["waves"][0]["triggers"].append(trigger)
	return data


func test_progress_needs_at_in_range() -> void:
	for bad: Variant in [1.5, -0.1, "half", null]:
		_assert_one(_with_trigger({"when": "progress", "at": bad, "actions": []}), "waves[0].triggers[2].at")
	_assert_one(_with_trigger({"when": "progress", "actions": []}), "waves[0].triggers[2].at")


func test_actions_must_be_objects() -> void:
	var data: Dictionary = _valid()
	data["waves"][0]["triggers"][0]["actions"] = ["wait"]
	_assert_one(data, "waves[0].triggers[0].actions[0]")


func test_spawn_group_must_name_a_group_in_the_wave() -> void:
	var data: Dictionary = _valid()
	data["waves"][0]["triggers"][0]["actions"].append({"spawn_group": "missing"})
	_assert_one(data, "waves[0].triggers[0].actions[1].spawn_group")


func test_every_group_must_be_spawned_by_some_trigger() -> void:
	var data: Dictionary = _valid()
	data["waves"][0]["groups"]["orphan"] = [{"type": "wasp", "count": 1}]
	_assert_one(data, "waves[0].groups.orphan")


func _count_containing(problems: Array[String], needle: String) -> int:
	var n: int = 0
	for p: String in problems:
		if p.contains(needle):
			n += 1
	return n


# --- Reachability (R1, R2) ----------------------------------------------------

## One wave: `spawn_count` Wasps, groups name -> Wasp count, `triggers`.
func _wave(spawn_count: int, groups: Dictionary, triggers: Array) -> Dictionary:
	var group_dict: Dictionary = {}
	for group_name: String in groups:
		group_dict[group_name] = [{"type": "wasp", "count": float(groups[group_name])}]
	return {"id": 1.0, "waves": [{
		"spawns": [{"type": "wasp", "count": float(spawn_count)}],
		"groups": group_dict,
		"triggers": triggers,
	}]}


func test_reachable_chain_has_no_problems() -> void:
	# 2 spawns + a 4 + b 4 = 10 counted; once a spawns, 6/10 = 0.6 can resolve.
	var data: Dictionary = _wave(2, {"a": 4, "b": 4}, [
		{"when": "wave_start", "actions": [{"spawn_group": "a"}]},
		{"when": "progress", "at": 0.6, "actions": [{"spawn_group": "b"}]},
	])
	assert_eq(_validate(data), [] as Array[String])


func test_wave_clear_group_is_unreachable() -> void:
	var data: Dictionary = _wave(2, {"g": 2}, [{"when": "wave_clear", "actions": [{"spawn_group": "g"}]}])
	_assert_one(data, "waves[0].groups.g")


func test_flag_off_group_is_unreachable() -> void:
	var data: Dictionary = _wave(4, {"g": 2}, [
		{"when": "progress", "at": 0.5, "flag": "off", "actions": [{"spawn_group": "g"}]},
	])
	_assert_one(data, "waves[0].groups.g")


func test_negated_flag_pair_reaches_the_group() -> void:
	for flag: String in ["on", "off"]:
		var data: Dictionary = _wave(4, {"g": 2}, [
			{"when": "progress", "at": 0.5, "flag": flag, "actions": [{"spawn_group": "g"}]},
			{"when": "progress", "at": 0.5, "flag": "!" + flag, "actions": [{"spawn_group": "g"}]},
		])
		assert_eq(_validate(data), [] as Array[String], flag)


func test_unknown_flag_is_a_problem() -> void:
	# Its only route to the group, so the group is unreachable too.
	var data: Dictionary = _wave(4, {"g": 2}, [
		{"when": "progress", "at": 0.5, "flag": "nope", "actions": [{"spawn_group": "g"}]},
	])
	var problems: Array[String] = _validate(data)
	assert_eq(problems.size(), 2, "%s" % [problems])
	assert_eq(_count_containing(problems, "waves[0].triggers[0].flag"), 1, "flag problem")
	assert_eq(_count_containing(problems, "waves[0].groups.g"), 1, "group problem")
	for bad: Variant in ["nope", "!nope", 3.0, null]:
		_assert_one(_with_trigger({"when": "wave_start", "flag": bad, "actions": []}), "waves[0].triggers[2].flag")


func test_boss_trigger_group_is_unreachable() -> void:
	for trigger: Dictionary in [
		{"when": "boss_phase", "phase": 2.0, "actions": [{"spawn_group": "g"}]},
		{"when": "boss_hp_le", "hp": 50.0, "actions": [{"spawn_group": "g"}]},
	]:
		_assert_one(_wave(2, {"g": 2}, [trigger]), "waves[0].groups.g")


func test_unreachable_at_is_a_problem() -> void:
	# 6 spawns + 4 = 10 counted; only 6/10 = 0.6 can resolve before the group spawns.
	var data: Dictionary = _wave(6, {"g": 4}, [
		{"when": "progress", "at": 0.7, "actions": [{"spawn_group": "g"}]},
	])
	var problems: Array[String] = _validate(data)
	assert_eq(problems.size(), 2, "%s" % [problems])
	assert_eq(_count_containing(problems, "waves[0].triggers[0].at"), 1, "at problem")
	assert_eq(_count_containing(problems, "6/10"), 1, "names available/total")
	assert_eq(_count_containing(problems, "waves[0].groups.g"), 1, "group problem")


func test_flag_gated_type_counts_zero() -> void:
	# Hunter Wasps off: the group counts 0, so 4/4 resolve and at 1.0 fires.
	var data: Dictionary = _wave(4, {"g": 2}, [{"when": "progress", "at": 1.0, "actions": [{"spawn_group": "g"}]}])
	data["waves"][0]["groups"]["g"] = [{"type": "hunter_wasp", "count": 2.0}]
	assert_eq(_validate(data), [] as Array[String], "flag off")
	_flags["hunter_wasp"] = true
	var problems: Array[String] = _validate(data)
	_flags["hunter_wasp"] = false
	assert_eq(problems.size(), 2, "flag on: the hunters count, so at 1.0 is unreachable: %s" % [problems])


# --- Field types (R4, R9) -----------------------------------------------------

func test_trigger_field_types() -> void:
	var cases: Array = [
		[{"when": "wave_start", "at": "x", "actions": []}, "at"],
		[{"when": "boss_phase", "phase": 1.5, "actions": []}, "phase"],
		[{"when": "boss_phase", "phase": 0.0, "actions": []}, "phase"],
		[{"when": "boss_phase", "phase": "2", "actions": []}, "phase"],
		[{"when": "boss_phase", "actions": []}, "phase"],
		[{"when": "boss_hp_le", "hp": "50", "actions": []}, "hp"],
		[{"when": "boss_hp_le", "hp": -1.0, "actions": []}, "hp"],
		[{"when": "boss_hp_le", "actions": []}, "hp"],
		[{"when": "wave_start", "hp": null, "actions": []}, "hp"],
	]
	for c: Array in cases:
		_assert_one(_with_trigger(c[0] as Dictionary), "waves[0].triggers[2].%s" % c[1])
	assert_eq(_validate(_with_trigger({"when": "boss_hp_le", "hp": 0.0, "actions": []})), [] as Array[String], "hp 0 is fine")


func test_action_value_types() -> void:
	var cases: Array = [
		[{"wait": "1"}, "wait"],
		[{"wait": -0.5}, "wait"],
		[{"comms": 3.0}, "comms"],
		[{"comms": ""}, "comms"],
		[{"story_event": null}, "story_event"],
		[{"music": []}, "music"],
		[{"spawn_group": 5.0}, "spawn_group"],
	]
	for c: Array in cases:
		var data: Dictionary = _valid()
		data["waves"][0]["triggers"][0]["actions"].append(c[0])
		_assert_one(data, "waves[0].triggers[0].actions[1].%s" % c[1])
	var ok: Dictionary = _valid()
	ok["waves"][0]["triggers"][0]["actions"].append_array([{"comms": "a"}, {"story_event": "b"}, {"music": "c"}, {"wait": 0.0}])
	assert_eq(_validate(ok), [] as Array[String], "valid action values")


func test_action_needs_exactly_one_known_key() -> void:
	for bad: Dictionary in [{"dance": 1.0}, {}, {"wait": 1.0, "comms": "x"}]:
		var data: Dictionary = _valid()
		data["waves"][0]["triggers"][0]["actions"].append(bad)
		var problems: Array[String] = _validate(data)
		assert_eq(problems.size(), 1, "%s: %s" % [bad, problems])
		if problems.size() == 1:
			assert_string_contains(problems[0], "waves[0].triggers[0].actions[1]:")


func test_entry_must_be_top_or_sides() -> void:
	for bad: Variant in ["left", 1.0, null]:
		var data: Dictionary = _valid()
		data["waves"][0]["spawns"][0]["entry"] = bad
		_assert_one(data, "waves[0].spawns[0].entry")
	for good: String in ["top", "sides"]:
		var data: Dictionary = _valid()
		data["waves"][0]["groups"]["r"][0]["entry"] = good
		assert_eq(_validate(data), [] as Array[String], good)


# --- Grid width (R7) ----------------------------------------------------------

func test_grid_wider_than_the_playfield_is_a_problem() -> void:
	var data: Dictionary = _valid()
	data["waves"][0]["spawns"][0]["formation"] = "grid_13x1"
	_assert_one(data, "waves[0].spawns[0].formation")
	data["waves"][0]["spawns"][0]["formation"] = "grid_12x1"
	assert_eq(_validate(data), [] as Array[String], "12 columns fit")


## A wave whose progress `at` 0.7 can't be reached (4/8 without a bad entry).
func _unreachable_wave(spawns: Array, group: Array) -> Dictionary:
	return {"id": 7, "waves": [{
		"spawns": spawns,
		"groups": {"g": group},
		"triggers": [{"when": "progress", "at": 0.7, "actions": [{"spawn_group": "g"}]}],
	}]}


## A non-object spawn or group entry leaves the wave's counts unknown, so the
## reachability pass is skipped: the `at` 0.7 and group g aren't reported on
## top of the entry problem.
func test_non_object_entry_skips_reachability() -> void:
	var wasps: Dictionary = {"type": "wasp", "count": 4.0}
	_assert_one(_unreachable_wave([3, wasps], [wasps.duplicate()]), "waves[0].spawns[0]")
	_assert_one(_unreachable_wave([wasps], [3, wasps.duplicate()]), "waves[0].groups.g[0]")
