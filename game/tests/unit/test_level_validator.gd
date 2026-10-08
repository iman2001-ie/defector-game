extends GutTest
## LevelValidator: every problem names the source file and the key path.

const SRC: String = "res://data/levels/level_test.json"

var _known: Array[StringName] = [&"wasp"]


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
	return LevelValidator.validate(data, SRC, _known)


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


func test_progress_needs_at_in_range() -> void:
	for bad: Variant in [1.5, -0.1, "half"]:
		var data: Dictionary = _valid()
		data["waves"][0]["triggers"][1]["at"] = bad
		_assert_one(data, "waves[0].triggers[1].at")
	var missing: Dictionary = _valid()
	(missing["waves"][0]["triggers"][1] as Dictionary).erase("at")
	_assert_one(missing, "waves[0].triggers[1].at")


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
