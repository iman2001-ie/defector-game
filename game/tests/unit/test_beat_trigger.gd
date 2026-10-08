extends GutTest
## BeatTrigger: data-authored beat conditions (when, at, phase, hp, flag, has_fired).


func test_progress_threshold() -> void:
	var trigger: BeatTrigger = BeatTrigger.new({"when": "progress", "at": 0.3})
	assert_false(trigger.should_fire(&"progress", 0.29, {}), "below at")
	assert_true(trigger.should_fire(&"progress", 0.3, {}), "exactly at")
	assert_true(trigger.should_fire(&"progress", 0.5, {}), "above at")


func test_wrong_event_does_not_fire() -> void:
	var trigger: BeatTrigger = BeatTrigger.new({"when": "wave_start"})
	assert_false(trigger.should_fire(&"progress", 1.0, {}), "progress event vs wave_start")


func test_wave_start_fires() -> void:
	var trigger: BeatTrigger = BeatTrigger.new({"when": "wave_start"})
	assert_true(trigger.should_fire(&"wave_start", 0.0, {}), "wave_start")


func test_wave_clear_fires() -> void:
	var trigger: BeatTrigger = BeatTrigger.new({"when": "wave_clear"})
	assert_true(trigger.should_fire(&"wave_clear", 0.0, {}), "wave_clear")
	assert_false(trigger.should_fire(&"wave_start", 0.0, {}), "not on wave_start")


func test_flag_passes_and_fails() -> void:
	var trigger: BeatTrigger = BeatTrigger.new({"when": "wave_start", "flag": "x"})
	assert_true(trigger.should_fire(&"wave_start", 0.0, {"x": true}), "flag true")
	assert_false(trigger.should_fire(&"wave_start", 0.0, {"x": false}), "flag false")


func test_negated_flag() -> void:
	var trigger: BeatTrigger = BeatTrigger.new({"when": "wave_start", "flag": "!x"})
	assert_false(trigger.should_fire(&"wave_start", 0.0, {"x": true}), "!x with x true")
	assert_true(trigger.should_fire(&"wave_start", 0.0, {"x": false}), "!x with x false")


func test_missing_flag_key_counts_as_false() -> void:
	var plain: BeatTrigger = BeatTrigger.new({"when": "wave_start", "flag": "x"})
	var negated: BeatTrigger = BeatTrigger.new({"when": "wave_start", "flag": "!x"})
	assert_false(plain.should_fire(&"wave_start", 0.0, {}), "missing x is false")
	assert_true(negated.should_fire(&"wave_start", 0.0, {}), "missing !x is true")


func test_non_bool_flag_counts_as_false() -> void:
	var trigger: BeatTrigger = BeatTrigger.new({"when": "wave_start", "flag": "x"})
	assert_false(trigger.should_fire(&"wave_start", 0.0, {"x": 1}), "non-bool flag is false")


func test_has_fired_blocks() -> void:
	var trigger: BeatTrigger = BeatTrigger.new({"when": "progress", "at": 0.0})
	trigger.has_fired = true
	assert_false(trigger.should_fire(&"progress", 1.0, {}), "fired trigger never fires again")


func test_should_fire_does_not_set_has_fired() -> void:
	var trigger: BeatTrigger = BeatTrigger.new({"when": "wave_start"})
	assert_true(trigger.should_fire(&"wave_start", 0.0, {}), "fires")
	assert_false(trigger.has_fired, "should_fire is a pure query")
	assert_true(trigger.should_fire(&"wave_start", 0.0, {}), "still fires until the Director marks it")


func test_boss_phase() -> void:
	var trigger: BeatTrigger = BeatTrigger.new({"when": "boss_phase", "phase": 2})
	assert_true(trigger.should_fire(&"boss_phase", 2.0, {}), "phase 2")
	assert_false(trigger.should_fire(&"boss_phase", 1.0, {}), "phase 1")


func test_boss_hp_le() -> void:
	var trigger: BeatTrigger = BeatTrigger.new({"when": "boss_hp_le", "hp": 50})
	assert_true(trigger.should_fire(&"boss_hp_le", 50.0, {}), "hp equal")
	assert_true(trigger.should_fire(&"boss_hp_le", 30.0, {}), "hp below")
	assert_false(trigger.should_fire(&"boss_hp_le", 51.0, {}), "hp above")


func test_unknown_when_never_fires() -> void:
	var trigger: BeatTrigger = BeatTrigger.new({"when": "bogus"})
	for event: StringName in [&"wave_start", &"progress", &"wave_clear", &"boss_phase", &"boss_hp_le", &"bogus"]:
		assert_false(trigger.should_fire(event, 1.0, {}), "unknown when vs %s" % event)


func test_construct_from_json_shape() -> void:
	var data: Variant = JSON.parse_string(
		'{"when": "boss_phase", "phase": 2, "hp": 40, "at": 0.5, "flag": "!tarek_fall",'
		+ ' "actions": [{"comms": "a"}, "junk", {"spawn_group": "b"}, {"wait": 1.5}]}'
	)
	assert_typeof(data, TYPE_DICTIONARY, "fixture JSON parses to a Dictionary")
	var trigger: BeatTrigger = BeatTrigger.new(data as Dictionary)
	assert_eq(trigger.when, &"boss_phase", "when is a StringName")
	assert_eq(trigger.phase, 2, "float phase converted to int")
	assert_eq(trigger.hp, 40.0, "hp")
	assert_eq(trigger.at, 0.5, "at")
	assert_eq(trigger.flag, "!tarek_fall", "flag")
	assert_false(trigger.has_fired, "not fired")
	assert_eq(trigger.actions.size(), 3, "only Dictionary actions kept")
	assert_eq(trigger.actions[0], {"comms": "a"}, "first action in order")
	assert_eq(trigger.actions[1], {"spawn_group": "b"}, "second action in order")
	assert_eq(trigger.actions[2], {"wait": 1.5}, "third action in order")


func test_missing_optional_keys_default() -> void:
	var trigger: BeatTrigger = BeatTrigger.new({"when": "wave_clear"})
	assert_eq(trigger.at, 0.0, "at defaults to 0.0")
	assert_eq(trigger.phase, 0, "phase defaults to 0")
	assert_eq(trigger.hp, 0.0, "hp defaults to 0.0")
	assert_eq(trigger.flag, "", "flag defaults to empty")
	assert_eq(trigger.actions.size(), 0, "actions default to empty")
	assert_false(trigger.has_fired, "not fired")


func test_empty_data_never_fires() -> void:
	var trigger: BeatTrigger = BeatTrigger.new({})
	assert_eq(trigger.when, &"", "when defaults to empty")
	assert_false(trigger.should_fire(&"", 0.0, {}), "empty when never fires")
