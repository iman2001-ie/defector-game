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
	assert_eq(parsed.comms, &"")
	assert_eq(typeof(parsed.comms), TYPE_STRING_NAME)


func test_comms_id() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--comms=dev_comms_check"]))
	assert_eq(parsed.comms, &"dev_comms_check")
	assert_eq(typeof(parsed.comms), TYPE_STRING_NAME)
	assert_false(parsed.stress, "does not imply stress")
	assert_true(parsed.prewarm)


func test_comms_combines_with_other_args() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--no-prewarm", "--comms=abc"]))
	assert_eq(parsed.comms, &"abc")
	assert_false(parsed.prewarm)


func test_empty_comms_warns_and_is_ignored() -> void:
	var parsed: Dictionary = DebugArgs.parse(PackedStringArray(["--comms="]))
	assert_eq(parsed.comms, &"")
	assert_push_warning("--comms")
