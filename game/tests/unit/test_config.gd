extends GutTest
## Config autoload: typed getters, fallbacks, parse failures and reload.

const BAD_TUNING: String = "res://tests/fixtures/bad_tuning.json"
const BAD_FLAGS: String = "res://tests/fixtures/bad_flags.json"
const MISSING_FILE: String = "res://tests/fixtures/does_not_exist.json"
const ARRAY_ROOT: String = "res://tests/fixtures/array_root.json"
const NON_BOOL_FLAGS: String = "res://tests/fixtures/non_bool_flags.json"
const TEMP_TUNING: String = "user://test_config_tuning.json"
const TEMP_FLAGS: String = "user://test_config_flags.json"

const SECTIONS: Array[String] = [
	"player", "weapons", "abilities", "energy", "drops", "enemies", "boss",
	"asteroids", "convoy", "allies", "waves", "progression", "comms", "feedback", "damage",
	"hud", "ui", "audio", "render", "debug",
]
const FLAG_DEFAULTS: Dictionary = {
	"surrender_prompts": true,
	"isolde_interruptions": true,
	"tarek_fall": true,
	"hunter_wasp": false,
}
const TIER_KEYS: Array[String] = [
	"explosion_scale", "shake_px", "shake_s", "hit_stop_ms", "extras", "sfx", "sfx_pitch",
]
const TIERS: Array[String] = [
	"small", "medium", "large", "boss_part", "boss_death", "player_hit", "player_death",
]

var _captured: Array[Array] = []


func before_each() -> void:
	Config.assert_on_missing = false
	_captured.clear()


func after_each() -> void:
	Log.sink = Callable()
	Config.assert_on_missing = true
	Config.load_data()
	for path: String in [TEMP_TUNING, TEMP_FLAGS]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _capture(level: String, category: String, msg: String) -> void:
	_captured.append([level, category, msg])


## True when an INFO/data line starting "Loaded " was captured.
func _captured_load_summary() -> bool:
	for entry: Array in _captured:
		if entry[0] == "INFO" and entry[1] == "data" and (entry[2] as String).begins_with("Loaded "):
			return true
	return false


## Parsed copy of a real data file, for tests to edit and write back.
func _real(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## Asserts the single "Reload rejected" line contains every fragment (in any
## order), then claims it. GUT lets each push_error be asserted only once.
func _assert_rejection_names(fragments: Array[String]) -> void:
	var line: Variant = null
	for err: Variant in get_errors():
		if not err.handled and err.contains_text("Reload rejected"):
			line = err
			break
	assert_not_null(line, "a Reload rejected line was pushed")
	if line != null:
		for fragment: String in fragments:
			assert_true(line.contains_text(fragment), "rejection names '%s'" % fragment)
	assert_push_error("Reload rejected")


## Loads temp copies of the real tuning and flags, so reload() re-reads the temp paths.
func _load_temp_copies() -> void:
	_write(TEMP_TUNING, JSON.stringify(_real(Config.DEFAULT_TUNING_PATH)))
	_write(TEMP_FLAGS, JSON.stringify(_real(Config.DEFAULT_FLAGS_PATH)))
	Config.load_data(TEMP_TUNING, TEMP_FLAGS)


# --- Shape of the real data files -------------------------------------------

func test_real_data_loads_without_error() -> void:
	assert_eq(Config.load_error, "")


func test_tuning_has_exactly_the_fixed_sections() -> void:
	var keys: Array = Config.tuning.keys()
	keys.sort()
	var expected: Array = SECTIONS.duplicate()
	expected.sort()
	assert_eq(keys, expected)


func test_flags_have_the_four_defaults() -> void:
	assert_eq(Config.flags, FLAG_DEFAULTS)


func test_feedback_tiers_have_full_shape() -> void:
	var tiers: Dictionary = Config.section("feedback.tiers")
	for tier: String in TIERS:
		assert_true(tiers.has(tier), "feedback.tiers.%s exists" % tier)
		var row: Dictionary = tiers.get(tier, {})
		for key: String in TIER_KEYS:
			assert_true(row.has(key), "feedback.tiers.%s.%s exists" % [tier, key])


func test_mandatory_key_paths() -> void:
	assert_eq(Config.num("waves.gap_s"), 2.0)
	assert_eq(Config.int_("comms.chars_per_s"), 45)
	assert_eq(Config.int_("damage.convoy_aimed"), 5)
	assert_eq(Config.int_("damage.convoy_stray"), 2)
	assert_eq(Config.int_("boss.final_choice_hp"), 50)
	assert_gt(Config.num("player.missile_ring.radius_px"), 0.0, "player.missile_ring.radius_px")
	assert_gt(Config.num("player.missile_ring.stroke_px"), 0.0, "player.missile_ring.stroke_px")
	assert_gt(Config.num("render.glow.intensity"), 0.0, "render.glow.intensity")
	assert_gt(Config.num("render.glow.bloom"), 0.0, "render.glow.bloom")
	assert_gt(Config.num("render.glow.hdr_threshold"), 0.0, "render.glow.hdr_threshold")
	assert_gt(Config.num("weapons.laser.glow_energy"), 1.0, "weapons.laser.glow_energy (HDR)")
	assert_gt(Config.num("weapons.laser.halo_energy"), 0.0, "weapons.laser.halo_energy")
	for type_id: String in ["wasp", "lancer", "needle", "bastion", "maul", "hunter_wasp"]:
		assert_gt(Config.int_("enemies.%s.hp" % type_id), 0, "enemies.%s.hp" % type_id)
		assert_false(Config.section("drops.%s" % type_id).is_empty(), "drops.%s" % type_id)
	for size: String in ["small", "medium", "large"]:
		assert_false(Config.section("asteroids.%s" % size).is_empty(), "asteroids.%s" % size)


# --- Typed getters ----------------------------------------------------------

func test_num_returns_float() -> void:
	var v: Variant = Config.num("weapons.laser.speed_px_s")
	assert_eq(typeof(v), TYPE_FLOAT)
	assert_eq(v, 1800.0)


func test_int_converts_json_float_to_int() -> void:
	var v: Variant = Config.int_("player.hearts")
	assert_eq(typeof(v), TYPE_INT)
	assert_eq(v, 5)


func test_flag_values() -> void:
	assert_true(Config.flag("tarek_fall"))
	assert_false(Config.flag("hunter_wasp"))


func test_section_returns_non_empty_dictionary() -> void:
	var tiers: Dictionary = Config.section("feedback.tiers")
	assert_false(tiers.is_empty())


# --- Missing keys -----------------------------------------------------------

func test_num_missing_key_returns_zero_and_logs_path() -> void:
	assert_eq(Config.num("player.nope"), 0.0)
	assert_push_error("tuning.player.nope")


func test_int_missing_key_returns_zero_and_logs_path() -> void:
	var v: Variant = Config.int_("player.nope")
	assert_eq(typeof(v), TYPE_INT)
	assert_eq(v, 0)
	assert_push_error("tuning.player.nope")


func test_flag_missing_returns_false_and_logs_path() -> void:
	assert_false(Config.flag("nope"))
	assert_push_error("flags.nope")


func test_section_missing_returns_empty_and_logs_path() -> void:
	assert_eq(Config.section("nope"), {})
	assert_push_error("tuning.nope")


# --- Wrong types ------------------------------------------------------------

func test_num_on_dictionary_returns_fallback() -> void:
	assert_eq(Config.num("feedback.tiers"), 0.0)
	assert_push_error("tuning.feedback.tiers")


func test_section_on_number_returns_fallback() -> void:
	assert_eq(Config.section("weapons.laser.speed_px_s"), {})
	assert_push_error("tuning.weapons.laser.speed_px_s")


# --- Bad files --------------------------------------------------------------

func test_bad_tuning_sets_load_error_without_crash() -> void:
	Config.load_data(BAD_TUNING, Config.DEFAULT_FLAGS_PATH)
	assert_ne(Config.load_error, "")
	assert_eq(Config.tuning, {})
	assert_eq(Config.flags, FLAG_DEFAULTS, "flags still load")
	assert_push_error("bad_tuning.json")


func test_bad_flags_empties_flags_but_not_load_error() -> void:
	Config.load_data(Config.DEFAULT_TUNING_PATH, BAD_FLAGS)
	assert_eq(Config.flags, {})
	assert_eq(Config.load_error, "")
	assert_false(Config.tuning.is_empty(), "tuning still loads")
	assert_push_error("bad_flags.json")


func test_missing_flags_file_empties_flags_but_not_load_error() -> void:
	Config.load_data(Config.DEFAULT_TUNING_PATH, MISSING_FILE)
	assert_eq(Config.flags, {})
	assert_eq(Config.load_error, "")
	assert_push_error("does_not_exist.json")


func test_missing_tuning_file_sets_load_error() -> void:
	Config.load_data(MISSING_FILE, Config.DEFAULT_FLAGS_PATH)
	assert_ne(Config.load_error, "")
	assert_eq(Config.tuning, {})
	assert_push_error("does_not_exist.json")


func test_non_object_root_sets_load_error() -> void:
	Config.load_data(ARRAY_ROOT, Config.DEFAULT_FLAGS_PATH)
	assert_ne(Config.load_error, "")
	assert_eq(Config.tuning, {})
	assert_push_error("array_root.json")


func test_flag_non_bool_returns_false_and_logs_path() -> void:
	Config.load_data(Config.DEFAULT_TUNING_PATH, NON_BOOL_FLAGS)
	assert_false(Config.flag("surrender_prompts"))
	assert_push_error("flags.surrender_prompts")


# --- Reload -----------------------------------------------------------------

func test_reload_rereads_custom_paths() -> void:
	Config.load_data(BAD_TUNING, Config.DEFAULT_FLAGS_PATH)
	assert_false(Config.reload(), "still broken")
	assert_ne(Config.load_error, "")
	assert_eq(Config.tuning, {})
	# Boot read error, reload read error, "Reload rejected" line.
	assert_push_error("previous data kept")
	assert_push_error_count(3)


func test_reload_keeps_values() -> void:
	Config.load_data()
	var before: Dictionary = Config.tuning.duplicate(true)
	assert_true(Config.reload())
	assert_eq(Config.load_error, "")
	assert_eq(Config.tuning, before)
	assert_eq(Config.num("weapons.laser.speed_px_s"), 1800.0)
	assert_eq(Config.flags, FLAG_DEFAULTS)


func test_reload_serves_changed_value() -> void:
	_load_temp_copies()
	var data: Dictionary = _real(Config.DEFAULT_TUNING_PATH)
	data["weapons"]["laser"]["speed_px_s"] = 900.0
	_write(TEMP_TUNING, JSON.stringify(data))
	assert_true(Config.reload(), "reload accepted")
	assert_eq(Config.num("weapons.laser.speed_px_s"), 900.0, "new value served")
	assert_eq(Config.load_error, "")
	assert_push_error_count(0)


func test_reload_accepts_extra_key() -> void:
	_load_temp_copies()
	var data: Dictionary = _real(Config.DEFAULT_TUNING_PATH)
	data["player"]["brand_new"] = 3.0
	data["new_section"] = {"a": true}
	_write(TEMP_TUNING, JSON.stringify(data))
	assert_true(Config.reload(), "extra keys allowed")
	assert_eq(Config.num("player.brand_new"), 3.0)


func test_reload_serves_changed_flag() -> void:
	_load_temp_copies()
	var data: Dictionary = _real(Config.DEFAULT_FLAGS_PATH)
	data["tarek_fall"] = false
	_write(TEMP_FLAGS, JSON.stringify(data))
	assert_true(Config.reload(), "reload accepted")
	assert_false(Config.flag("tarek_fall"), "new flag value served")
	assert_push_error_count(0)


func test_reload_parse_failure_keeps_state() -> void:
	_load_temp_copies()
	var old_tuning: Dictionary = Config.tuning.duplicate(true)
	var old_flags: Dictionary = Config.flags.duplicate(true)
	_write(TEMP_TUNING, "{ not json")
	assert_false(Config.reload(), "reload refused")
	assert_eq(Config.tuning, old_tuning, "old tuning kept")
	assert_eq(Config.flags, old_flags, "old flags kept")
	assert_eq(Config.load_error, "", "load_error unchanged")
	assert_push_error("parse error")
	assert_push_error("previous data kept")


func test_reload_flags_parse_failure_keeps_flags() -> void:
	_load_temp_copies()
	_write(TEMP_FLAGS, "{ not json")
	assert_false(Config.reload(), "reload refused")
	assert_eq(Config.flags, FLAG_DEFAULTS, "old flags kept")
	assert_eq(Config.load_error, "")
	assert_push_error("Reload rejected")
	assert_push_error("parse error")


func test_reload_missing_key_keeps_state() -> void:
	_load_temp_copies()
	var old_tuning: Dictionary = Config.tuning.duplicate(true)
	var data: Dictionary = _real(Config.DEFAULT_TUNING_PATH)
	(data["player"] as Dictionary).erase("hearts")
	_write(TEMP_TUNING, JSON.stringify(data))
	assert_false(Config.reload(), "reload refused")
	assert_eq(Config.tuning, old_tuning, "old tuning kept")
	assert_eq(Config.int_("player.hearts"), 5, "old value served")
	assert_eq(Config.load_error, "")
	assert_push_error("tuning.player.hearts missing")


func test_reload_wrong_type_keeps_state() -> void:
	_load_temp_copies()
	var old_tuning: Dictionary = Config.tuning.duplicate(true)
	var data: Dictionary = _real(Config.DEFAULT_TUNING_PATH)
	data["weapons"]["laser"]["speed_px_s"] = "fast"
	_write(TEMP_TUNING, JSON.stringify(data))
	assert_false(Config.reload(), "reload refused")
	assert_eq(Config.tuning, old_tuning, "old tuning kept")
	assert_eq(Config.num("weapons.laser.speed_px_s"), 1800.0, "old value served")
	assert_push_error("tuning.weapons.laser.speed_px_s: expected number, got String")


func test_reload_missing_flag_fails() -> void:
	_load_temp_copies()
	var data: Dictionary = _real(Config.DEFAULT_FLAGS_PATH)
	data.erase("tarek_fall")
	data["hunter_wasp"] = 1
	_write(TEMP_FLAGS, JSON.stringify(data))
	assert_false(Config.reload(), "reload refused")
	assert_eq(Config.flags, FLAG_DEFAULTS, "old flags kept")
	_assert_rejection_names(["flags.hunter_wasp: expected bool, got number", "flags.tarek_fall missing"])


func test_reload_without_reference_after_failed_boot() -> void:
	_write(TEMP_TUNING, "{ not json")
	Config.load_data(TEMP_TUNING, Config.DEFAULT_FLAGS_PATH)
	assert_ne(Config.load_error, "", "boot failed")
	_write(TEMP_TUNING, JSON.stringify(_real(Config.DEFAULT_TUNING_PATH)))
	assert_true(Config.reload(), "fixed file accepted")
	assert_eq(Config.load_error, "", "load_error cleared")
	assert_eq(Config.num("weapons.laser.speed_px_s"), 1800.0)
	assert_push_error("parse error")


func test_reload_still_broken_keeps_load_error() -> void:
	_write(TEMP_TUNING, "{ not json")
	Config.load_data(TEMP_TUNING, Config.DEFAULT_FLAGS_PATH)
	var boot_error: String = Config.load_error
	assert_ne(boot_error, "", "boot failed")
	assert_false(Config.reload(), "still broken")
	assert_eq(Config.load_error, boot_error, "load_error unchanged")
	assert_eq(Config.tuning, {})
	assert_push_error_count(3)


func test_reload_reports_problems_in_both_files() -> void:
	_load_temp_copies()
	var data: Dictionary = _real(Config.DEFAULT_TUNING_PATH)
	(data["player"] as Dictionary).erase("hearts")
	_write(TEMP_TUNING, JSON.stringify(data))
	_write(TEMP_FLAGS, "{ not json")
	assert_false(Config.reload(), "reload refused")
	assert_eq(Config.int_("player.hearts"), 5, "old tuning kept")
	assert_eq(Config.flags, FLAG_DEFAULTS, "old flags kept")
	_assert_rejection_names(["test_config_flags.json parse error", "tuning.player.hearts missing"])
	assert_push_error("parse error")


func test_reload_missing_file_keeps_state() -> void:
	_load_temp_copies()
	var old_tuning: Dictionary = Config.tuning.duplicate(true)
	DirAccess.remove_absolute(TEMP_TUNING)
	assert_false(Config.reload(), "reload refused")
	assert_eq(Config.tuning, old_tuning, "old tuning kept")
	assert_eq(Config.load_error, "")
	assert_push_error("Reload rejected")
	assert_push_error("not found")


func test_reload_nested_wrong_type_names_full_path() -> void:
	_load_temp_copies()
	var old_tuning: Dictionary = Config.tuning.duplicate(true)
	var data: Dictionary = _real(Config.DEFAULT_TUNING_PATH)
	data["feedback"]["tiers"]["large"]["shake_px"] = "big"
	_write(TEMP_TUNING, JSON.stringify(data))
	assert_false(Config.reload(), "reload refused")
	assert_eq(Config.tuning, old_tuning, "old tuning kept")
	assert_push_error("tuning.feedback.tiers.large.shake_px: expected number, got String")


# --- Load summary log -------------------------------------------------------

func test_ready_logs_load_summary() -> void:
	Log.sink = _capture
	Config._ready()
	assert_true(_captured_load_summary(), "boot logs an [INFO][data] Loaded ... summary")


func test_reload_logs_load_summary() -> void:
	Config.load_data()
	Log.sink = _capture
	assert_true(Config.reload(), "reload accepted")
	assert_true(_captured_load_summary(), "reload logs an [INFO][data] Loaded ... summary")


# --- Level data (Story 2.2) ---------------------------------------------------

const TEMP_LEVEL: String = "user://test_config_level.json"


func test_level_dev_loads() -> void:
	var data: Dictionary = Config.level("dev")
	assert_false(data.is_empty(), "level_dev.json loads")
	assert_eq(int(data.get("id", -1)), 0, "id 0")
	assert_eq((data.get("waves", []) as Array).size(), 6, "six waves")


func test_level_missing_id_returns_empty() -> void:
	assert_eq(Config.level("does_not_exist"), {})
	assert_push_error("level_does_not_exist.json not found")


func test_level_parse_error_returns_empty() -> void:
	assert_eq(Config.level_at("res://tests/fixtures/level_parse_error.json"), {})
	assert_push_error("parse error")


func test_level_without_waves_returns_empty() -> void:
	assert_eq(Config.level_at("res://tests/fixtures/level_no_waves.json"), {})
	assert_push_error("level_no_waves.json has no waves array")


func test_level_with_an_empty_waves_array_returns_empty() -> void:
	assert_eq(Config.level_at("res://tests/fixtures/level_empty_waves.json"), {})
	assert_push_error("level_empty_waves.json has no waves array")


func test_level_problems_are_logged_and_data_returned() -> void:
	_write(TEMP_LEVEL, JSON.stringify({"id": 4, "waves": [{"spawns": [{"type": "bogus", "count": 1}]}]}))
	var data: Dictionary = Config.level_at(TEMP_LEVEL)
	DirAccess.remove_absolute(TEMP_LEVEL)
	assert_eq(int(data.get("id", -1)), 4, "data still returned")
	assert_push_error("%s waves[0].spawns[0].type" % TEMP_LEVEL)


## DW-37: level_at passes the flags, type gates and column bound to the
## validator. The test sets surrender_prompts true and hunter_wasp false
## (after_each reloads the shipped flags). With Config's flags, triggers[0]'s
## flag is known; with the real type gates, group h's Hunter Wasps count 0, so
## its progress `at` 1.0 is reachable (13/13). Passing {} for either would add a
## triggers[0].flag, a .at or a groups.h problem.
func test_level_at_passes_flags_and_column_bound() -> void:
	Config.flags["surrender_prompts"] = true
	Config.flags["hunter_wasp"] = false
	_write(TEMP_LEVEL, JSON.stringify({"id": 4, "waves": [{
		"spawns": [{"type": "wasp", "count": 13, "formation": "grid_13x1"}],
		"groups": {"h": [{"type": "hunter_wasp", "count": 4}]},
		"triggers": [
			{"when": "progress", "at": 1.0, "flag": "surrender_prompts", "actions": [{"spawn_group": "h"}]},
			{"when": "wave_start", "flag": "nope", "actions": []},
		],
	}]}))
	Log.sink = _capture
	Config.level_at(TEMP_LEVEL)
	DirAccess.remove_absolute(TEMP_LEVEL)
	var errors: Array[String] = []
	for entry: Array in _captured:
		if entry[0] == "ERROR" and entry[1] == "data":
			errors.append(entry[2] as String)
	assert_eq(errors.size(), 2, "only the column and unknown-flag problems: %s" % [errors])
	assert_push_error("%s waves[0].spawns[0].formation" % TEMP_LEVEL)
	assert_push_error("%s waves[0].triggers[1].flag" % TEMP_LEVEL)


## DW-68: level_at passes EntityRegistry's rowless types to the validator, so a
## Maul before a Needle is fine and a Wasp before one is a problem.
func test_level_at_passes_rowless_types() -> void:
	Log.sink = _capture
	for first: String in ["maul", "wasp"]:
		_captured.clear()
		_write(TEMP_LEVEL, JSON.stringify({"id": 4, "waves": [{
			"spawns": [{"type": first, "count": 1}, {"type": "needle", "count": 1}],
		}]}))
		Config.level_at(TEMP_LEVEL)
		DirAccess.remove_absolute(TEMP_LEVEL)
		var errors: Array[String] = []
		for entry: Array in _captured:
			if entry[0] == "ERROR" and entry[1] == "data":
				errors.append(entry[2] as String)
		if first == "maul":
			assert_eq(errors, [] as Array[String], "a rowless Maul may precede the Needle")
		else:
			assert_eq(errors.size(), 1, "the Needle follows a Wasp: %s" % [errors])
			assert_push_error("%s waves[0].spawns[1].type" % TEMP_LEVEL)


# --- Dialogue data (Story 5.1) ------------------------------------------------

const BAD_DIALOGUE_DIR: String = "res://tests/fixtures/dialogue/bad/"
const MISSING_DIALOGUE_DIR: String = "res://tests/fixtures/dialogue/does_not_exist/"
const TEMP_DIALOGUE_DIR: String = "user://test_config_dialogue/"


func _clear_temp_dialogue() -> void:
	if not DirAccess.dir_exists_absolute(TEMP_DIALOGUE_DIR):
		return
	for file: String in DirAccess.get_files_at(TEMP_DIALOGUE_DIR):
		DirAccess.remove_absolute(TEMP_DIALOGUE_DIR + file)
	DirAccess.remove_absolute(TEMP_DIALOGUE_DIR)


func _write_dialogue(file: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TEMP_DIALOGUE_DIR)
	_write(TEMP_DIALOGUE_DIR + file, text)


func _story(id: String, text: String) -> String:
	return JSON.stringify({"sequences": {id: {"mode": "story", "lines": [{"speaker": "tarek", "text": text}]}}})


func test_dev_comms_check_is_a_story_sequence() -> void:
	assert_true(Config.has_sequence(&"dev_comms_check"))
	assert_true(Config.dialogue_is_story(&"dev_comms_check"))
	var seq: Dictionary = Config.sequence(&"dev_comms_check")
	assert_eq(seq.get("mode"), "story")
	assert_between((seq.get("lines", []) as Array).size(), 3, 5, "3-5 placeholder lines")


func test_sequence_returns_a_deep_copy() -> void:
	var seq: Dictionary = Config.sequence(&"dev_comms_check")
	((seq.lines as Array)[0] as Dictionary)["text"] = "changed"
	(seq.lines as Array).clear()
	var again: Dictionary = Config.sequence(&"dev_comms_check")
	assert_gt((again.lines as Array).size(), 0, "lines untouched")
	assert_ne(((again.lines as Array)[0] as Dictionary).get("text"), "changed", "line untouched")


func test_unknown_sequence_is_empty_without_logging() -> void:
	Log.sink = _capture
	assert_eq(Config.sequence(&"nope"), {})
	assert_false(Config.has_sequence(&"nope"))
	assert_false(Config.dialogue_is_story(&"nope"))
	assert_eq(_captured.size(), 0, "nothing logged")
	assert_push_error_count(0)


func test_bad_dialogue_files_are_logged_and_skipped() -> void:
	Config.load_data(Config.DEFAULT_TUNING_PATH, Config.DEFAULT_FLAGS_PATH, BAD_DIALOGUE_DIR)
	var a: String = BAD_DIALOGUE_DIR + "a_bad.json"
	for fragment: String in [
		"%s sequences.unknown_speaker.lines[0].speaker" % a,
		"%s sequences.bad_mode.mode" % a,
		"%s sequences.empty_lines.lines" % a,
		"%s sequences.empty_text.lines[0].text" % a,
		"%s sequences.too_long.lines[0].text: story line has 201 characters" % a,
		"%s sequences.non_object_line.lines[0]" % a,
		"%s sequences.not_an_object" % a,
		"%sb_dup.json sequences.good_one: duplicate sequence id" % BAD_DIALOGUE_DIR,
		"%sc_parse.json parse error" % BAD_DIALOGUE_DIR,
		"%sd_no_sequences.json sequences: missing or not an object" % BAD_DIALOGUE_DIR,
		"%s sequences.\" \": sequence id is empty" % a,
		"%se_combat.json sequences.combat_two_lines.lines: combat sequence has 2 lines, exactly 1 allowed" % BAD_DIALOGUE_DIR,
		"%se_combat.json sequences.combat_too_long.lines[0].text: combat line has 51 characters, more than 50" % BAD_DIALOGUE_DIR,
	]:
		assert_push_error(fragment)
	assert_push_error_count(13)
	assert_false(Config.has_sequence(&""), "no empty id")
	assert_false(Config.has_sequence(&" "), "no blank id")
	for id: StringName in [&"unknown_speaker", &"bad_mode", &"empty_lines", &"empty_text", &"too_long", &"non_object_line", &"not_an_object", &"combat_two_lines", &"combat_too_long"]:
		assert_false(Config.has_sequence(id), "%s left out" % id)
	assert_true(Config.dialogue_is_story(&"good_one"), "the good sequence loads")
	assert_eq(((Config.sequence(&"good_one").lines as Array)[0] as Dictionary).get("text"), "First definition wins.", "first duplicate wins")
	assert_true(Config.has_sequence(&"good_two"), "the other file's sequence loads")
	assert_false(Config.dialogue_is_story(&"good_two"), "combat is not story")
	assert_eq(Config.load_error, "", "dialogue never sets load_error")


func test_missing_dialogue_dir_leaves_dialogue_empty() -> void:
	Config.load_data(Config.DEFAULT_TUNING_PATH, Config.DEFAULT_FLAGS_PATH, MISSING_DIALOGUE_DIR)
	assert_false(Config.has_sequence(&"dev_comms_check"))
	assert_eq(Config.load_error, "")
	assert_push_error("dialogue dir not found")


func test_load_logs_the_dialogue_summary() -> void:
	Log.sink = _capture
	Config._ready()
	var found: bool = false
	for entry: Array in _captured:
		if entry[0] == "INFO" and entry[1] == "data" and (entry[2] as String).begins_with("Loaded ") and (entry[2] as String).contains("dialogue sequences from %s" % Config.DEFAULT_DIALOGUE_DIR):
			found = true
	assert_true(found, "boot logs the dialogue summary")


func test_reload_rereads_dialogue() -> void:
	_clear_temp_dialogue()
	_write_dialogue("a.json", _story("first", "One."))
	Config.load_data(Config.DEFAULT_TUNING_PATH, Config.DEFAULT_FLAGS_PATH, TEMP_DIALOGUE_DIR)
	assert_true(Config.has_sequence(&"first"))
	_write_dialogue("a.json", _story("second", "Two."))
	assert_true(Config.reload(), "reload accepted")
	assert_false(Config.has_sequence(&"first"), "old sequence gone")
	assert_true(Config.dialogue_is_story(&"second"), "new sequence served")
	_clear_temp_dialogue()


func test_reload_rejects_a_dialogue_parse_error() -> void:
	_clear_temp_dialogue()
	_write_dialogue("a.json", _story("first", "One."))
	Config.load_data(Config.DEFAULT_TUNING_PATH, Config.DEFAULT_FLAGS_PATH, TEMP_DIALOGUE_DIR)
	_write_dialogue("a.json", _story("second", "Two."))
	_write_dialogue("b.json", "{ not json")
	assert_false(Config.reload(), "reload refused")
	assert_true(Config.has_sequence(&"first"), "previous dialogue kept")
	assert_false(Config.has_sequence(&"second"))
	_assert_rejection_names(["b.json parse error"])
	assert_push_error("parse error")
	_clear_temp_dialogue()


func test_reload_only_logs_validator_problems() -> void:
	_clear_temp_dialogue()
	_write_dialogue("a.json", _story("first", "One."))
	Config.load_data(Config.DEFAULT_TUNING_PATH, Config.DEFAULT_FLAGS_PATH, TEMP_DIALOGUE_DIR)
	_write_dialogue("a.json", JSON.stringify({"sequences": {
		"first": {"mode": "story", "lines": [{"speaker": "tarek", "text": "One."}]},
		"broken": {"mode": "story", "lines": [{"speaker": "bob", "text": "Who?"}]},
	}}))
	assert_true(Config.reload(), "validator problems don't reject the reload")
	assert_true(Config.has_sequence(&"first"))
	assert_false(Config.has_sequence(&"broken"), "bad sequence left out")
	assert_push_error("sequences.broken.lines[0].speaker")
	assert_push_error_count(1)
	_clear_temp_dialogue()


## Real tuning with both comms line-max keys erased: non-empty, so a missing
## key is logged (DW-76).
func _tuning_without_line_max() -> Dictionary:
	var data: Dictionary = _real(Config.DEFAULT_TUNING_PATH)
	var comms: Dictionary = data["comms"]
	comms.erase("story_line_max_chars")
	comms.erase("combat_line_max_chars")
	return data


func _line_max_error(key: String, kind: String) -> String:
	return "[ERROR][data] tuning.%s missing or not a number; %s line length not checked" % [key, kind]


## DW-76: with both line-max keys missing, _load_dialogue logs one error per key
## and checks no line length (-1), so over-long story and combat lines load.
func test_load_dialogue_without_line_max_keys_skips_length_checks() -> void:
	var comms: Dictionary = _real(Config.DEFAULT_TUNING_PATH)["comms"]
	var story_len: int = int(comms[Config.STORY_MAX_CHARS_KEY.get_slice(".", 1)]) + 1
	var combat_len: int = int(comms[Config.COMBAT_MAX_CHARS_KEY.get_slice(".", 1)]) + 1
	_clear_temp_dialogue()
	_write_dialogue("a.json", _story("long_story", "s".repeat(story_len)))
	_write_dialogue("b.json", JSON.stringify({"sequences": {"long_combat": {
		"mode": "combat", "lines": [{"speaker": "isolde", "text": "c".repeat(combat_len)}],
	}}}))
	var read_problems: Array[String] = []
	var out: Dictionary = Config._load_dialogue(TEMP_DIALOGUE_DIR, _tuning_without_line_max(), read_problems)
	_clear_temp_dialogue()
	assert_eq(out.size(), 2, "both sequences returned: %s" % [out.keys()])
	assert_true(out.has(&"long_story"), "%d-char story line accepted" % story_len)
	assert_true(out.has(&"long_combat"), "%d-char combat line accepted" % combat_len)
	assert_eq(read_problems, [] as Array[String], "no read problems")
	assert_push_error(_line_max_error(Config.STORY_MAX_CHARS_KEY, "story"))
	assert_push_error(_line_max_error(Config.COMBAT_MAX_CHARS_KEY, "combat"))
	assert_push_error_count(2)


## DW-76: _line_max_chars returns -1 for a missing or non-number key (one error
## each).
func test_line_max_chars_falls_back_to_no_limit() -> void:
	var tuning: Dictionary = _tuning_without_line_max()
	assert_eq(Config._line_max_chars(tuning, Config.STORY_MAX_CHARS_KEY, "story"), -1, "missing story key")
	assert_eq(Config._line_max_chars(tuning, Config.COMBAT_MAX_CHARS_KEY, "combat"), -1, "missing combat key")
	(tuning["comms"] as Dictionary)["story_line_max_chars"] = "200"
	assert_eq(Config._line_max_chars(tuning, Config.STORY_MAX_CHARS_KEY, "story"), -1, "string value")
	assert_push_error(_line_max_error(Config.STORY_MAX_CHARS_KEY, "story"))
	assert_push_error(_line_max_error(Config.COMBAT_MAX_CHARS_KEY, "combat"))
	assert_push_error(_line_max_error(Config.STORY_MAX_CHARS_KEY, "story"))
	assert_push_error_count(3)


## DW-76: _line_max_chars returns -1 for empty tuning (a failed tuning load, no error).
func test_line_max_chars_on_empty_tuning_returns_minus_one_silently() -> void:
	assert_eq(Config._line_max_chars({}, Config.STORY_MAX_CHARS_KEY, "story"), -1, "story")
	assert_eq(Config._line_max_chars({}, Config.COMBAT_MAX_CHARS_KEY, "combat"), -1, "combat")
	assert_push_error_count(0)
