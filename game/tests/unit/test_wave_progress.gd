extends GutTest
## WaveProgress: counted-enemy totals, ratio and the no-soft-lock clear rule.


func _resolve_n(progress: WaveProgress, n: int) -> void:
	for i: int in n:
		progress.resolve()


func test_progress_ratio() -> void:
	var progress: WaveProgress = WaveProgress.new()
	progress.reset(8)
	_resolve_n(progress, 2)
	assert_almost_eq(progress.ratio(), 0.25, 0.0001, "2 of 8 is 0.25")
	assert_false(progress.is_complete(), "not complete at 2 of 8")


func test_wave_completes() -> void:
	var progress: WaveProgress = WaveProgress.new()
	progress.reset(3)
	_resolve_n(progress, 3)
	assert_eq(progress.ratio(), 1.0, "ratio 1.0 when all resolved")
	assert_true(progress.is_complete(), "complete at 3 of 3")


func test_failed_spawn_is_subtracted() -> void:
	var progress: WaveProgress = WaveProgress.new()
	progress.reset(5)
	progress.remove_from_total(2)
	_resolve_n(progress, 3)
	assert_eq(progress.total_counted, 3, "total lowered by the failed spawns")
	assert_true(progress.is_complete(), "complete after the remaining 3 resolve")
	assert_eq(progress.ratio(), 1.0, "ratio 1.0")


func test_remove_from_total_defaults_to_one() -> void:
	var progress: WaveProgress = WaveProgress.new()
	progress.reset(4)
	progress.remove_from_total()
	assert_eq(progress.total_counted, 3, "default removes one")


func test_remove_from_total_clamps_resolved() -> void:
	var progress: WaveProgress = WaveProgress.new()
	progress.reset(4)
	_resolve_n(progress, 3)
	progress.remove_from_total(2)
	assert_eq(progress.total_counted, 2, "total lowered to 2")
	assert_eq(progress.resolved, 2, "resolved clamped to the new total")
	assert_true(progress.is_complete(), "complete after the clamp")


func test_over_resolve_is_clamped() -> void:
	var progress: WaveProgress = WaveProgress.new()
	progress.reset(2)
	_resolve_n(progress, 3)
	assert_eq(progress.resolved, 2, "resolved never passes the total")
	assert_true(progress.is_complete(), "still complete (no soft-lock)")
	assert_eq(progress.ratio(), 1.0, "ratio stays 1.0")


func test_empty_wave_is_complete() -> void:
	var progress: WaveProgress = WaveProgress.new()
	progress.reset(0)
	assert_eq(progress.ratio(), 1.0, "empty wave ratio is 1.0")
	assert_true(progress.is_complete(), "empty wave is complete")


func test_every_spawn_removed_is_complete() -> void:
	var progress: WaveProgress = WaveProgress.new()
	progress.reset(2)
	progress.remove_from_total(5)
	assert_eq(progress.total_counted, 0, "total never below 0")
	assert_eq(progress.ratio(), 1.0, "ratio 1.0 with nothing left")
	assert_true(progress.is_complete(), "complete with nothing left")


func test_negative_reset_clamps_to_zero() -> void:
	var progress: WaveProgress = WaveProgress.new()
	progress.reset(-3)
	assert_eq(progress.total_counted, 0, "negative total clamps to 0")
	assert_true(progress.is_complete(), "complete")


func test_reset_clears() -> void:
	var progress: WaveProgress = WaveProgress.new()
	progress.reset(3)
	_resolve_n(progress, 2)
	progress.reset(4)
	assert_eq(progress.resolved, 0, "resolved cleared")
	assert_eq(progress.total_counted, 4, "new total")
	assert_false(progress.is_complete(), "not complete after reset")
