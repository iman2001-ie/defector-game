extends Node
## Levelled, categorised logging. The only script in the project that calls print().
##
## Format: [LEVEL][category] message. ERROR also calls push_error, WARN also calls
## push_warning. DEBUG lines are dropped when debug_enabled is false (release builds).

const LEVEL_DEBUG: String = "DEBUG"
const LEVEL_INFO: String = "INFO"
const LEVEL_WARN: String = "WARN"
const LEVEL_ERROR: String = "ERROR"

const CATEGORIES: Array[String] = [
	"boot", "scene", "wave", "beat", "comms", "spawn",
	"combat", "save", "audio", "data", "debug",
]

## Injectable so tests can simulate a release build.
var debug_enabled: bool = OS.is_debug_build()
## Test hook only: production code never sets this. When valid, it is called with
## (level: String, category: String, msg: String) once per line actually written,
## after the line is printed. Tests reset it to Callable() when done.
var sink: Callable = Callable()


func debug(category: String, msg: String) -> bool:
	return emit_line(LEVEL_DEBUG, category, msg)


func info(category: String, msg: String) -> bool:
	return emit_line(LEVEL_INFO, category, msg)


func warn(category: String, msg: String) -> bool:
	return emit_line(LEVEL_WARN, category, msg)


func error(category: String, msg: String) -> bool:
	return emit_line(LEVEL_ERROR, category, msg)


## Pure formatter: "[LEVEL][category] message".
func format(level: String, category: String, msg: String) -> String:
	return "[%s][%s] %s" % [level, category, msg]


## Writes one line. Returns false when the line was dropped (DEBUG in release).
func emit_line(level: String, category: String, msg: String) -> bool:
	if level == LEVEL_DEBUG and not debug_enabled:
		return false
	if not CATEGORIES.has(category):
		push_warning("Log: unknown category '%s'" % category)
	var line: String = format(level, category, msg)
	print(line)
	if sink.is_valid():
		sink.call(level, category, msg)
	if level == LEVEL_ERROR:
		push_error(line)
	elif level == LEVEL_WARN:
		push_warning(line)
	return true
