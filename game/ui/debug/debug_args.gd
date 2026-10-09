class_name DebugArgs
extends RefCounted
## Parses the debug command-line user args (the ones after `--`):
##   --stress          40-Wasp stress sandbox with ~200 live projectiles
##   --bench=<seconds> stress sandbox that holds fire, logs frame stats and quits
##   --no-prewarm      the sandbox skips Feedback.prewarm() (compare first-explosion cost)
##   --comms=<id>      the level requests that comms sequence once it starts (Story 5.1)
## Unknown args are ignored. Callers pass OS.get_cmdline_user_args() or an
## injectable user_args field that defaults to it.

const STRESS_ARG: String = "--stress"
const BENCH_PREFIX: String = "--bench="
const NO_PREWARM_ARG: String = "--no-prewarm"
const COMMS_PREFIX: String = "--comms="


## Returns {"stress": bool, "bench_s": float, "prewarm": bool, "comms": StringName}.
## A positive bench implies stress; a malformed or non-positive bench value logs
## a warning and is ignored. prewarm is true unless --no-prewarm is present.
## comms is the --comms=<id> sequence id (the last one wins), &"" when absent;
## an empty id logs a warning and is ignored.
static func parse(args: PackedStringArray) -> Dictionary:
	var stress: bool = false
	var bench_s: float = 0.0
	var prewarm: bool = true
	var comms: StringName = &""
	for arg: String in args:
		if arg == STRESS_ARG:
			stress = true
		elif arg == NO_PREWARM_ARG:
			prewarm = false
		elif arg.begins_with(COMMS_PREFIX):
			var id: String = arg.substr(COMMS_PREFIX.length()).strip_edges()
			if id.is_empty():
				Log.warn("debug", "Ignoring --comms with no sequence id")
			else:
				comms = StringName(id)
		elif arg.begins_with(BENCH_PREFIX):
			var raw: String = arg.substr(BENCH_PREFIX.length())
			if raw.is_valid_float() and raw.to_float() > 0.0:
				bench_s = raw.to_float()
				stress = true
			else:
				Log.warn("debug", "Ignoring --bench value '%s' (expected a positive number of seconds)" % raw)
	return {"stress": stress, "bench_s": bench_s, "prewarm": prewarm, "comms": comms}
