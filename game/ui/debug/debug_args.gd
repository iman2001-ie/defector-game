class_name DebugArgs
extends RefCounted
## Parses the debug command-line user args (the ones after `--`):
##   --stress          40-Wasp stress sandbox with ~200 live projectiles
##   --bench=<seconds> stress sandbox that holds fire, logs frame stats and quits
##   --no-prewarm      the sandbox skips Feedback.prewarm() (compare first-explosion cost)
##   --comms=<id>[,<id>...]  the level requests those comms sequences, in order, once it
##                     starts (Story 5.1; a list since the Story 5.2 follow-up, so queued
##                     combat lines can be checked back-to-back)
##   --level=<id>      the level scene runs data/levels/level_<id>.json (Story 5.6); only
##                     when level.tscn is the launched scene (boot routes in via SceneRouter)
##   --level-bench=<scenario>  self-timing bench inside the real level (Story 8.3):
##                     busiest_wave or desperate (LEVEL_BENCH_SCENARIOS); boot starts
##                     level debug.level_bench.level and the level runs a LevelBench.
##                     Never implies stress (it is not --bench=)
## Unknown args are ignored. Callers pass OS.get_cmdline_user_args() or an
## injectable user_args field that defaults to it.

const STRESS_ARG: String = "--stress"
const BENCH_PREFIX: String = "--bench="
const NO_PREWARM_ARG: String = "--no-prewarm"
const COMMS_PREFIX: String = "--comms="
const LEVEL_PREFIX: String = "--level="
const LEVEL_BENCH_PREFIX: String = "--level-bench="
## The --level-bench scenarios LevelBench can drive.
const LEVEL_BENCH_SCENARIOS: PackedStringArray = ["busiest_wave", "desperate"]


## Returns {"stress": bool, "bench_s": float, "prewarm": bool,
## "comms": Array[StringName], "level": String, "level_bench": String}.
## A positive bench implies stress; a malformed or non-positive bench value logs
## a warning and is ignored. prewarm is true unless --no-prewarm is present.
## comms is the --comms= list of sequence ids in order (the last --comms wins),
## empty when absent; empty items are skipped, and a list with no ids logs a
## warning and is ignored. level is the --level=<id> level
## file key (the last one wins), "" when absent; an empty id logs a warning and
## is ignored. level_bench is the --level-bench=<scenario> name (the last valid
## one wins), "" when absent; an empty or unknown scenario logs a warning naming
## the valid ones and is ignored. It never sets stress.
static func parse(args: PackedStringArray) -> Dictionary:
	var stress: bool = false
	var bench_s: float = 0.0
	var prewarm: bool = true
	var comms: Array[StringName] = []
	var level: String = ""
	var level_bench: String = ""
	for arg: String in args:
		if arg == STRESS_ARG:
			stress = true
		elif arg == NO_PREWARM_ARG:
			prewarm = false
		elif arg.begins_with(COMMS_PREFIX):
			var ids: Array[StringName] = []
			for item: String in arg.substr(COMMS_PREFIX.length()).split(","):
				if not item.strip_edges().is_empty():
					ids.append(StringName(item.strip_edges()))
			if ids.is_empty():
				Log.warn("debug", "Ignoring --comms with no sequence id")
			else:
				comms = ids
		elif arg.begins_with(LEVEL_BENCH_PREFIX):
			var scenario: String = arg.substr(LEVEL_BENCH_PREFIX.length()).strip_edges()
			if LEVEL_BENCH_SCENARIOS.has(scenario):
				level_bench = scenario
			else:
				Log.warn("debug", "Ignoring --level-bench value '%s' (expected one of: %s)" % [scenario, ", ".join(LEVEL_BENCH_SCENARIOS)])
		elif arg.begins_with(LEVEL_PREFIX):
			var level_arg: String = arg.substr(LEVEL_PREFIX.length()).strip_edges()
			if level_arg.is_empty():
				Log.warn("debug", "Ignoring --level with no level id")
			else:
				level = level_arg
		elif arg.begins_with(BENCH_PREFIX):
			var raw: String = arg.substr(BENCH_PREFIX.length())
			if raw.is_valid_float() and raw.to_float() > 0.0:
				bench_s = raw.to_float()
				stress = true
			else:
				Log.warn("debug", "Ignoring --bench value '%s' (expected a positive number of seconds)" % raw)
	return {"stress": stress, "bench_s": bench_s, "prewarm": prewarm, "comms": comms, "level": level, "level_bench": level_bench}
