extends GutTest
## Config autoload: typed getters, fallbacks, parse failures and reload.

const BAD_TUNING: String = "res://tests/fixtures/bad_tuning.json"
const BAD_FLAGS: String = "res://tests/fixtures/bad_flags.json"
const MISSING_FILE: String = "res://tests/fixtures/does_not_exist.json"
const ARRAY_ROOT: String = "res://tests/fixtures/array_root.json"
const NON_BOOL_FLAGS: String = "res://tests/fixtures/non_bool_flags.json"

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


func before_each() -> void:
	Config.assert_on_missing = false


func after_each() -> void:
	Config.assert_on_missing = true
	Config.load_data()


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
	for type_id: String in ["wasp", "lancer", "needle", "bastion", "maul", "hunter_wasp"]:
		assert_gt(Config.int_("enemies.%s.hp" % type_id), 0, "enemies.%s.hp" % type_id)
		assert_false(Config.section("drops.%s" % type_id).is_empty(), "drops.%s" % type_id)
	for size: String in ["small", "medium", "large"]:
		assert_false(Config.section("asteroids.%s" % size).is_empty(), "asteroids.%s" % size)


# --- Typed getters ----------------------------------------------------------

func test_num_returns_float() -> void:
	var v: Variant = Config.num("player.max_speed")
	assert_eq(typeof(v), TYPE_FLOAT)
	assert_eq(v, 1400.0)


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
	assert_eq(Config.section("player.max_speed"), {})
	assert_push_error("tuning.player.max_speed")


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
	Config.reload()
	assert_ne(Config.load_error, "")
	assert_eq(Config.tuning, {})
	assert_push_error_count(2)


func test_reload_keeps_values() -> void:
	Config.load_data()
	var before: Dictionary = Config.tuning.duplicate(true)
	Config.reload()
	assert_eq(Config.load_error, "")
	assert_eq(Config.tuning, before)
	assert_eq(Config.num("player.max_speed"), 1400.0)
	assert_eq(Config.flags, FLAG_DEFAULTS)
