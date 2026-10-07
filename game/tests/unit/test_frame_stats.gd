extends GutTest
## FrameStats: fixed-capacity frame-time samples with average, max and percentiles.


func test_empty_reads_zero() -> void:
	var stats: FrameStats = FrameStats.new(4)
	assert_eq(stats.count(), 0)
	assert_eq(stats.average_ms(), 0.0)
	assert_eq(stats.max_ms(), 0.0)
	assert_eq(stats.percentile_ms(99.0), 0.0)


func test_capacity_caps_samples() -> void:
	var stats: FrameStats = FrameStats.new(4)
	for ms: float in [10.0, 20.0, 30.0, 40.0, 50.0]:
		stats.add(ms)
	assert_eq(stats.count(), 4, "fifth sample ignored")
	assert_almost_eq(stats.average_ms(), 25.0, 0.0001, "avg")
	assert_almost_eq(stats.max_ms(), 40.0, 0.0001, "max")
	assert_almost_eq(stats.percentile_ms(99.0), 40.0, 0.0001, "p99")
	assert_almost_eq(stats.percentile_ms(50.0), 20.0, 0.0001, "p50 nearest rank")


func test_percentile_sorts_unordered_samples() -> void:
	var stats: FrameStats = FrameStats.new(4)
	for ms: float in [40.0, 10.0, 30.0, 20.0]:
		stats.add(ms)
	assert_almost_eq(stats.percentile_ms(50.0), 20.0, 0.0001, "p50")
	assert_almost_eq(stats.percentile_ms(0.0), 10.0, 0.0001, "p0 is the minimum")
	assert_almost_eq(stats.percentile_ms(100.0), 40.0, 0.0001, "p100 is the maximum")


func test_clear_resets() -> void:
	var stats: FrameStats = FrameStats.new(4)
	stats.add(5.0)
	stats.clear()
	assert_eq(stats.count(), 0)
	assert_eq(stats.average_ms(), 0.0)
	assert_eq(stats.max_ms(), 0.0)
	stats.add(7.0)
	assert_eq(stats.count(), 1, "usable after clear")
	assert_almost_eq(stats.max_ms(), 7.0, 0.0001)
