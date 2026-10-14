extends GutTest
## DebugArgs: command-line stress and bench flags (the args after `--`).


func test_stress_flag() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--stress"]))
	assert_true(parsed.stress, "stress")
	assert_eq(parsed.bench_s, 0.0, "no bench")


func test_bench_implies_stress() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--bench=20"]))
	assert_true(parsed.stress, "bench implies stress")
	assert_eq(parsed.bench_s, 20.0, "bench seconds")


func test_no_args() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray())
	assert_false(parsed.stress, "no stress")
	assert_eq(parsed.bench_s, 0.0, "no bench")


func test_unknown_args_ignored() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--foo", "bar", "--bench"]))
	assert_false(parsed.stress, "no stress")
	assert_eq(parsed.bench_s, 0.0, "no bench")


func test_malformed_bench_warns_and_is_ignored() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--bench=abc"]))
	assert_false(parsed.stress, "no stress")
	assert_eq(parsed.bench_s, 0.0, "no bench")
	assert_push_warning("abc")


func test_non_positive_bench_warns_and_is_ignored() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--bench=-1"]))
	assert_false(parsed.stress, "no stress")
	assert_eq(parsed.bench_s, 0.0, "no bench")
	assert_push_warning("-1")


func test_zero_bench_warns_and_is_ignored() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--bench=0"]))
	assert_false(parsed.stress, "no stress")
	assert_eq(parsed.bench_s, 0.0, "no bench")
	assert_push_warning_count(1)


func test_bad_bench_with_stress_keeps_stress() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--stress", "--bench=x"]))
	assert_true(parsed.stress, "stress from --stress")
	assert_eq(parsed.bench_s, 0.0, "no bench")
	assert_push_warning_count(1)


# --- Pre-warm switch (DW-9) ---------------------------------------------------

func test_prewarm_defaults_to_true() -> void:
	assert_true(DebugArgs.parse(PackedStringArray()).prewarm, "no args: pre-warm on")
	assert_true(DebugArgs.parse(PackedStringArray(["--bench=5"])).prewarm, "bench alone: pre-warm on")


func test_no_prewarm_flag() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--no-prewarm"]))
	assert_false(parsed.prewarm, "pre-warm off")
	assert_false(parsed.stress, "does not imply stress")
	assert_eq(parsed.bench_s, 0.0, "no bench")


func test_no_prewarm_combines_with_bench() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--bench=2", "--no-prewarm"]))
	assert_false(parsed.prewarm, "pre-warm off")
	assert_true(parsed.stress, "bench implies stress")
	assert_eq(parsed.bench_s, 2.0, "bench seconds")


# --- Comms sequence (Story 5.1) -------------------------------------------------

func test_comms_defaults_to_empty() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray())
	assert_eq(parsed.comms, [] as Array[StringName])
	assert_true(parsed.comms is Array[StringName], "a typed StringName array")


func test_comms_id() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--comms=dev_comms_check"]))
	assert_eq(parsed.comms, [&"dev_comms_check"] as Array[StringName])
	assert_true(parsed.comms is Array[StringName], "a typed StringName array")
	assert_false(parsed.stress, "does not imply stress")
	assert_true(parsed.prewarm)


func test_comms_combines_with_other_args() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--no-prewarm", "--comms=abc"]))
	assert_eq(parsed.comms, [&"abc"] as Array[StringName])
	assert_false(parsed.prewarm)


## Story 5.2 follow-up: a comma-separated list keeps its order; blank items
## and surrounding spaces are dropped; the last --comms wins.
func test_comms_list_in_order() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--comms=a, b,,c ,"]))
	assert_eq(parsed.comms, [&"a", &"b", &"c"] as Array[StringName])
	var last: Dictionary = DebugArgs.parse(PackedStringArray(["--comms=a,b", "--comms=c"]))
	assert_eq(last.comms, [&"c"] as Array[StringName], "the last --comms wins")


func test_comms_list_of_blanks_warns_and_is_ignored() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--comms= , ,"]))
	assert_eq(parsed.comms, [] as Array[StringName])
	assert_push_warning("--comms")


func test_empty_comms_warns_and_is_ignored() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--comms="]))
	assert_eq(parsed.comms, [] as Array[StringName])
	assert_push_warning("--comms")


# --- Level id (Story 5.6) -------------------------------------------------------

func test_level_defaults_to_empty() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray())
	assert_eq(parsed.level, "")
	assert_eq(typeof(parsed.level), TYPE_STRING)


func test_level_id() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--level=dev_isolde"]))
	assert_eq(parsed.level, "dev_isolde")
	assert_eq(typeof(parsed.level), TYPE_STRING)
	assert_false(parsed.stress, "does not imply stress")
	assert_true(parsed.prewarm)
	assert_eq(parsed.comms, [] as Array[StringName], "does not set comms")


func test_level_combines_with_other_args() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--comms=abc", "--level=dev", "--no-prewarm"]))
	assert_eq(parsed.level, "dev")
	assert_eq(parsed.comms, [&"abc"] as Array[StringName])
	assert_false(parsed.prewarm)


func test_empty_level_warns_and_is_ignored() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--level="]))
	assert_eq(parsed.level, "")
	assert_push_warning("--level")


func test_parse_returns_every_key() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray())
	assert_eq(parsed, {"stress": false, "bench_s": 0.0, "prewarm": true, "comms": [] as Array[StringName], "level": "", "level_bench": ""})


# --- Level bench (Story 8.3) ------------------------------------------------------

func test_level_bench_defaults_to_empty() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray())
	assert_eq(parsed.level_bench, "")
	assert_eq(typeof(parsed.level_bench), TYPE_STRING)


func test_level_bench_scenarios_parse_without_stress() -> void:
	for scenario: String in ["busiest_wave", "desperate"]:
		var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--level-bench=" + scenario]))
		assert_eq(parsed.level_bench, scenario)
		assert_false(parsed.stress, "%s does not imply stress" % scenario)
		assert_eq(parsed.bench_s, 0.0, "%s is not the stress bench" % scenario)
		assert_eq(parsed.level, "", "%s is not --level=" % scenario)


func test_level_bench_scenarios_const() -> void:
	assert_eq(DebugArgs.LEVEL_BENCH_SCENARIOS, PackedStringArray(["busiest_wave", "desperate"]))


func test_level_bench_last_one_wins() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--level-bench=busiest_wave", "--level-bench=desperate"]))
	assert_eq(parsed.level_bench, "desperate")


func test_empty_level_bench_warns_and_is_ignored() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--level-bench="]))
	assert_eq(parsed.level_bench, "")
	assert_false(parsed.stress)
	assert_push_warning("--level-bench value '' (expected one of: busiest_wave, desperate)")


func test_unknown_level_bench_warns_and_is_ignored() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--level-bench=foo"]))
	assert_eq(parsed.level_bench, "")
	assert_false(parsed.stress)
	assert_push_warning("--level-bench value 'foo' (expected one of: busiest_wave, desperate)")
