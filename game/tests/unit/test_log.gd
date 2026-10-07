extends GutTest
## Log autoload: line format, level side effects, DEBUG dropping and the test sink.

var _saved_debug_enabled: bool
var _captured: Array[Array] = []


func before_each() -> void:
	_saved_debug_enabled = Log.debug_enabled
	_captured.clear()


func after_each() -> void:
	Log.debug_enabled = _saved_debug_enabled
	Log.sink = Callable()


func _capture(level: String, category: String, msg: String) -> void:
	_captured.append([level, category, msg])


func test_format() -> void:
	assert_eq(Log.format("INFO", "boot", "msg"), "[INFO][boot] msg")


func test_info_is_written() -> void:
	assert_true(Log.emit_line(Log.LEVEL_INFO, "boot", "hello"))


func test_debug_dropped_when_not_debug_build() -> void:
	Log.debug_enabled = false
	assert_false(Log.emit_line(Log.LEVEL_DEBUG, "debug", "dropped"))


func test_debug_wrapper_dropped_when_not_debug_build() -> void:
	Log.debug_enabled = false
	assert_false(Log.debug("debug", "dropped"))


func test_debug_written_in_debug_build() -> void:
	Log.debug_enabled = true
	assert_true(Log.emit_line(Log.LEVEL_DEBUG, "debug", "kept"))


func test_non_debug_levels_ignore_debug_flag() -> void:
	Log.debug_enabled = false
	assert_true(Log.emit_line(Log.LEVEL_INFO, "boot", "still written"))


func test_error_also_pushes_error() -> void:
	Log.error("data", "boom")
	assert_push_error("[ERROR][data] boom")


func test_warn_also_pushes_warning() -> void:
	Log.warn("save", "careful")
	assert_push_warning("[WARN][save] careful")


func test_unknown_category_still_logs_and_warns() -> void:
	assert_true(Log.emit_line(Log.LEVEL_INFO, "not_a_category", "x"))
	assert_push_warning("not_a_category")


# --- Test sink --------------------------------------------------------------

func test_sink_receives_info_line() -> void:
	Log.sink = _capture
	assert_true(Log.info("boot", "x"))
	assert_eq(_captured, [["INFO", "boot", "x"]] as Array[Array])


func test_sink_receives_warn_line() -> void:
	Log.sink = _capture
	assert_true(Log.warn("save", "careful"))
	assert_eq(_captured, [["WARN", "save", "careful"]] as Array[Array])
	assert_push_warning("[WARN][save] careful")


func test_sink_receives_error_line() -> void:
	Log.sink = _capture
	assert_true(Log.error("data", "boom"))
	assert_eq(_captured, [["ERROR", "data", "boom"]] as Array[Array])
	assert_push_error("[ERROR][data] boom")


func test_sink_not_called_for_dropped_debug() -> void:
	Log.sink = _capture
	Log.debug_enabled = false
	assert_false(Log.debug("debug", "dropped"))
	assert_eq(_captured.size(), 0)


func test_no_sink_still_writes() -> void:
	Log.sink = _capture
	Log.sink = Callable()
	assert_true(Log.emit_line(Log.LEVEL_INFO, "boot", "no sink"))
	assert_eq(_captured.size(), 0)
