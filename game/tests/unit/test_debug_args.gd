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
