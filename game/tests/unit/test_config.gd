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
	"asteroids", "convoy", "allies", "waves", "comms", "feedback", "damage",
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
