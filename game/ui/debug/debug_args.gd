class_name DebugArgs
extends RefCounted
## Parses the debug command-line user args (the ones after `--`):
##   --stress          40-Wasp stress sandbox
##   --bench=<seconds> stress sandbox that holds fire, logs frame stats and quits
## Unknown args are ignored. Callers pass OS.get_cmdline_user_args().

const STRESS_ARG: String = "--stress"
const BENCH_PREFIX: String = "--bench="


## Returns {"stress": bool, "bench_s": float}. A positive bench implies stress;
## a malformed or non-positive bench value logs a warning and is ignored.
static func parse(args: PackedStringArray) -> Dictionary:
	var stress: bool = false
	var bench_s: float = 0.0
	for arg: String in args:
		if arg == STRESS_ARG:
			stress = true
		elif arg.begins_with(BENCH_PREFIX):
			var raw: String = arg.substr(BENCH_PREFIX.length())
			if raw.is_valid_float() and raw.to_float() > 0.0:
				bench_s = raw.to_float()
				stress = true
			else:
				Log.warn("debug", "Ignoring --bench value '%s' (expected a positive number of seconds)" % raw)
	return {"stress": stress, "bench_s": bench_s}
