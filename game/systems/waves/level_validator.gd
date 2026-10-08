class_name LevelValidator
extends RefCounted
## Checks a level JSON dictionary (data/levels/level_<id>.json). Pure logic,
## no nodes, no autoload reads: the caller passes the known enemy types, the
## flags, the type gates and the column bound. Config.level() logs every
## problem; the GUT data test fails on any.
##
## Each problem names the source file and the key path, for example
## `res://data/levels/level_dev.json waves[1].spawns[0].type: unknown enemy type 'bogus'`.
##
## Rules:
## - `id` is a number; `waves` is a non-empty array of objects; a wave has a
##   `spawns` array or a `boss` (a non-empty string).
## - Spawn and group entries: a known `type`, an integer `count` > 0, an optional
##   valid `formation` with at most `max_columns` grid columns (when > 0), an
##   optional `entry` of `top` or `sides`.
## - Asteroid entries: a known `size` and an integer `count` > 0.
## - Triggers: a known `when`. `at` is a number in 0-1 (required on progress);
##   `phase` is an integer (required and >= 1 on boss_phase); `hp` is a number
##   (required and >= 0 on boss_hp_le); `flag` is a string naming a flag in
##   `flags`, optionally negated with "!".
## - Actions: objects with exactly one of comms, spawn_group, story_event,
##   music, wait. `wait` is a number >= 0, the rest non-empty strings; a
##   spawn_group names a group in the same wave.
## - Every group is named by some spawn_group action.
## - Reachability (mirrors WaveDirector counting): a type gated by `type_flags`
##   whose flag isn't `true` counts 0, a boss counts 1, and every group counts
##   toward the total up front. Starting from the spawns (and the boss) as what
##   can resolve, triggers fire to a fixed point: wave_start always (if its flag
##   passes), progress when `available / total >= at` with available >= 1;
##   wave_clear and boss_* never (the wave has cleared, or isn't evaluated
##   yet). A fired trigger's groups join `available`. A group named only by
##   triggers that never fire is a problem, and so is the `at` of a progress
##   trigger whose flag passes but which never fires. The pass is skipped for
##   a wave whose spawns, groups or their entries have a shape, type or count
##   problem (its counts are not known).

const WHENS: Array[String] = ["wave_start", "progress", "wave_clear", "boss_phase", "boss_hp_le"]
const ACTION_KEYS: Array[String] = ["comms", "spawn_group", "story_event", "music", "wait"]
const NEGATE_PREFIX: String = "!"


## Returns every problem found (empty when the level is valid). `flags` is the
## flags.json dictionary, `type_flags` maps an enemy type id to the flag that
## gates it (EntityRegistry.ENEMY_FLAGS) and `max_columns` bounds grid columns
## (Formation.max_columns(); 0 means unbounded).
static func validate(data: Dictionary, source: String, known_types: Array[StringName], flags: Dictionary, type_flags: Dictionary, max_columns: int) -> Array[String]:
	var problems: Array[String] = []
	if not _is_number(data.get("id")):
		problems.append(_problem(source, "id", "missing or not a number"))
	var waves: Variant = data.get("waves")
	if not (waves is Array):
		problems.append(_problem(source, "waves", "missing or not an array"))
		return problems
	if (waves as Array).is_empty():
		problems.append(_problem(source, "waves", "is empty"))
	var ctx: Dictionary = {
		"source": source,
		"known_types": known_types,
		"flags": flags,
		"type_flags": type_flags,
		"max_columns": max_columns,
	}
	for i: int in (waves as Array).size():
		var wave: Variant = (waves as Array)[i]
		var path: String = "waves[%d]" % i
		if wave is Dictionary:
			_check_wave(wave as Dictionary, ctx, path, problems)
		else:
			problems.append(_problem(source, path, "is not an object"))
	return problems


static func _check_wave(wave: Dictionary, ctx: Dictionary, path: String, problems: Array[String]) -> void:
	var source: String = ctx.source
	## False once a spawn or group entry has a type or count problem.
	var counts_known: Array[bool] = [true]
	var spawns: Array = []
	if wave.has("spawns"):
		if wave["spawns"] is Array:
			spawns = wave["spawns"]
			_check_entries(spawns, ctx, path + ".spawns", problems, counts_known)
		else:
			problems.append(_problem(source, path + ".spawns", "is not an array"))
			counts_known[0] = false
	elif not wave.has("boss"):
		problems.append(_problem(source, path, "needs a spawns array or a boss"))
	if wave.has("boss") and not (wave["boss"] is String and not (wave["boss"] as String).is_empty()):
		problems.append(_problem(source, path + ".boss", "is not a non-empty string"))

	if wave.has("asteroids"):
		var asteroids: Variant = wave["asteroids"]
		if asteroids is Array:
			_check_asteroids(asteroids as Array, source, path + ".asteroids", problems)
		else:
			problems.append(_problem(source, path + ".asteroids", "is not an array"))

	## Group name -> its entries (an empty array when the group isn't an array).
	var groups: Dictionary = {}
	if wave.has("groups"):
		var raw_groups: Variant = wave["groups"]
		if raw_groups is Dictionary:
			for key: Variant in raw_groups:
				var group_name: String = str(key)
				var group_path: String = "%s.groups.%s" % [path, group_name]
				var entries: Variant = (raw_groups as Dictionary)[key]
				if entries is Array:
					groups[group_name] = entries
					_check_entries(entries as Array, ctx, group_path, problems, counts_known)
				else:
					groups[group_name] = []
					problems.append(_problem(source, group_path, "is not an array"))
					counts_known[0] = false
		else:
			problems.append(_problem(source, path + ".groups", "is not an object"))

	## One parsed record per trigger object, for the reachability pass.
	var parsed: Array[Dictionary] = []
	var named_groups: Array[String] = []
	if wave.has("triggers"):
		var triggers: Variant = wave["triggers"]
		if triggers is Array:
			for t: int in (triggers as Array).size():
				var trigger_path: String = "%s.triggers[%d]" % [path, t]
				var trigger: Variant = (triggers as Array)[t]
				if trigger is Dictionary:
					parsed.append(_check_trigger(trigger as Dictionary, ctx, trigger_path, groups, named_groups, problems))
				else:
					problems.append(_problem(source, trigger_path, "is not an object"))
		else:
			problems.append(_problem(source, path + ".triggers", "is not an array"))

	for group_name: String in groups:
		if not named_groups.has(group_name):
			problems.append(_problem(source, "%s.groups.%s" % [path, group_name], "is never named by a spawn_group action in this wave"))

	if counts_known[0]:
		_check_reachability(wave, spawns, groups, parsed, named_groups, ctx, path, problems)


## Fixed-point simulation of the wave's counting (see the class doc).
static func _check_reachability(wave: Dictionary, spawns: Array, groups: Dictionary, parsed: Array[Dictionary], named_groups: Array[String], ctx: Dictionary, path: String, problems: Array[String]) -> void:
	var source: String = ctx.source
	var available: int = _gated_total(spawns, ctx)
	if wave.has("boss"):
		available += 1
	var total: int = available
	for group_name: String in groups:
		total += _gated_total(groups[group_name] as Array, ctx)
	var spawned: Dictionary = {}
	var fired: Array[bool] = []
	fired.resize(parsed.size())
	fired.fill(false)
	var changed: bool = true
	while changed:
		changed = false
		for t: int in parsed.size():
			if fired[t] or not _can_fire(parsed[t], available, total):
				continue
			fired[t] = true
			changed = true
			for group_name: String in parsed[t].groups:
				if not spawned.has(group_name):
					spawned[group_name] = true
					available += _gated_total(groups[group_name] as Array, ctx)
	for group_name: String in groups:
		if named_groups.has(group_name) and not spawned.has(group_name):
			problems.append(_problem(source, "%s.groups.%s" % [path, group_name], "no trigger that names it can fire before the wave clears"))
	for t: int in parsed.size():
		var record: Dictionary = parsed[t]
		if record.when == "progress" and record.flag_passes and record.at_valid and not fired[t]:
			problems.append(_problem(source, "%s.at" % record.path, "at %s can't be reached: at most %d/%d can resolve before it fires" % [str(record.at), available, total]))


static func _can_fire(record: Dictionary, available: int, total: int) -> bool:
	if not record.flag_passes:
		return false
	match record.when:
		"wave_start":
			return true
		"progress":
			if not record.at_valid or available < 1:
				return false
			return float(available) / float(total) >= float(record.at)
	return false


## What `entries` add to the wave total: each entry's count, 0 for a type whose
## gating flag isn't `true`.
static func _gated_total(entries: Array, ctx: Dictionary) -> int:
	var type_flags: Dictionary = ctx.type_flags
	var flags: Dictionary = ctx.flags
	var out: int = 0
	for entry: Variant in entries:
		if not (entry is Dictionary):
			continue
		var dict: Dictionary = entry
		var type_id: StringName = StringName(str(dict.get("type", "")))
		if type_flags.has(type_id) and not (flags.get(str(type_flags[type_id])) is bool and flags.get(str(type_flags[type_id]))):
			continue
		if _is_positive_int(dict.get("count")):
			out += int(dict["count"])
	return out


## Spawn and group entries: a known type and an integer count > 0; an optional
## valid formation within the column bound; an optional valid entry. Sets
## counts_known[0] false on a type or count problem.
static func _check_entries(entries: Array, ctx: Dictionary, path: String, problems: Array[String], counts_known: Array[bool]) -> void:
	var source: String = ctx.source
	var known_types: Array[StringName] = ctx.known_types
	var max_columns: int = ctx.max_columns
	for e: int in entries.size():
		var entry_path: String = "%s[%d]" % [path, e]
		var entry: Variant = entries[e]
		if not (entry is Dictionary):
			problems.append(_problem(source, entry_path, "is not an object"))
			continue
		var dict: Dictionary = entry
		var type_id: StringName = StringName(str(dict.get("type", "")))
		if not known_types.has(type_id):
			problems.append(_problem(source, entry_path + ".type", "unknown enemy type '%s'" % type_id))
			counts_known[0] = false
		if not _is_positive_int(dict.get("count")):
			problems.append(_problem(source, entry_path + ".count", "must be an integer > 0"))
			counts_known[0] = false
		if dict.has("formation"):
			var formation: Variant = dict["formation"]
			if not (formation is String and Formation.is_valid(formation as String)):
				problems.append(_problem(source, entry_path + ".formation", "invalid formation '%s'" % str(formation)))
			elif max_columns > 0 and Formation.grid_columns(formation as String) > max_columns:
				problems.append(_problem(source, entry_path + ".formation", "'%s' has more than the %d columns that fit the playfield width" % [formation, max_columns]))
		if dict.has("entry"):
			var entry_kind: Variant = dict["entry"]
			if not (entry_kind is String and (StringName(entry_kind as String) == Enemy.ENTRY_TOP or StringName(entry_kind as String) == Enemy.ENTRY_SIDES)):
				problems.append(_problem(source, entry_path + ".entry", "must be '%s' or '%s', not '%s'" % [Enemy.ENTRY_TOP, Enemy.ENTRY_SIDES, str(entry_kind)]))


static func _check_asteroids(entries: Array, source: String, path: String, problems: Array[String]) -> void:
	for a: int in entries.size():
		var entry_path: String = "%s[%d]" % [path, a]
		var entry: Variant = entries[a]
		if not (entry is Dictionary):
			problems.append(_problem(source, entry_path, "is not an object"))
			continue
		var dict: Dictionary = entry
		var size: StringName = StringName(str(dict.get("size", "")))
		if not Asteroid.SIZES.has(size):
			problems.append(_problem(source, entry_path + ".size", "unknown asteroid size '%s'" % size))
		if not _is_positive_int(dict.get("count")):
			problems.append(_problem(source, entry_path + ".count", "must be an integer > 0"))


## Checks one trigger and returns its record for the reachability pass:
## path, when, at, at_valid, flag_passes, groups (the valid spawn_group names).
static func _check_trigger(trigger: Dictionary, ctx: Dictionary, path: String, groups: Dictionary, named_groups: Array[String], problems: Array[String]) -> Dictionary:
	var source: String = ctx.source
	var when: String = str(trigger.get("when", "")) if trigger.get("when") is String else ""
	if not WHENS.has(when):
		problems.append(_problem(source, path + ".when", "unknown when '%s'" % str(trigger.get("when", ""))))
	var record: Dictionary = {
		"path": path,
		"when": when,
		"at": trigger.get("at"),
		"at_valid": false,
		"flag_passes": true,
		"groups": [] as Array[String],
	}

	if when == "progress" or trigger.has("at"):
		var at: Variant = trigger.get("at")
		if _is_number(at) and float(at) >= 0.0 and float(at) <= 1.0:
			record.at_valid = true
		else:
			problems.append(_problem(source, path + ".at", "progress needs at in 0-1" if when == "progress" else "must be a number in 0-1"))
	if when == "boss_phase" or trigger.has("phase"):
		var phase: Variant = trigger.get("phase")
		if not (_is_int(phase) and (when != "boss_phase" or float(phase) >= 1.0)):
			problems.append(_problem(source, path + ".phase", "boss_phase needs an integer phase >= 1" if when == "boss_phase" else "must be an integer"))
	if when == "boss_hp_le" or trigger.has("hp"):
		var hp: Variant = trigger.get("hp")
		if not (_is_number(hp) and (when != "boss_hp_le" or float(hp) >= 0.0)):
			problems.append(_problem(source, path + ".hp", "boss_hp_le needs a number hp >= 0" if when == "boss_hp_le" else "must be a number"))
	if trigger.has("flag"):
		record.flag_passes = _check_flag(trigger["flag"], ctx, path + ".flag", problems)

	if not trigger.has("actions"):
		return record
	var actions: Variant = trigger["actions"]
	if not (actions is Array):
		problems.append(_problem(source, path + ".actions", "is not an array"))
		return record
	for i: int in (actions as Array).size():
		var action_path: String = "%s.actions[%d]" % [path, i]
		var action: Variant = (actions as Array)[i]
		if not (action is Dictionary):
			problems.append(_problem(source, action_path, "is not an object"))
			continue
		var dict: Dictionary = action
		if dict.size() != 1 or not ACTION_KEYS.has(str(dict.keys()[0])):
			problems.append(_problem(source, action_path, "needs exactly one key of %s, has %s" % [", ".join(ACTION_KEYS), str(dict.keys())]))
			continue
		var key: String = str(dict.keys()[0])
		var value: Variant = dict[key]
		if key == "wait":
			if not (_is_number(value) and float(value) >= 0.0):
				problems.append(_problem(source, action_path + ".wait", "must be a number >= 0"))
			continue
		if not (value is String and not (value as String).is_empty()):
			problems.append(_problem(source, "%s.%s" % [action_path, key], "is not a non-empty string"))
			continue
		if key == "spawn_group":
			var group_name: String = value
			if not named_groups.has(group_name):
				named_groups.append(group_name)
			if groups.has(group_name):
				(record.groups as Array[String]).append(group_name)
			else:
				problems.append(_problem(source, action_path + ".spawn_group", "names no group '%s' in this wave" % group_name))
	return record


## Checks a trigger flag against `flags` and returns whether it passes (as
## BeatTrigger would: "!" negates, a flag that isn't `true` is off). An unknown
## or malformed flag is a problem and never passes.
static func _check_flag(raw: Variant, ctx: Dictionary, path: String, problems: Array[String]) -> bool:
	var flags: Dictionary = ctx.flags
	if not (raw is String):
		problems.append(_problem(ctx.source, path, "is not a string"))
		return false
	var flag: String = raw
	var negated: bool = flag.begins_with(NEGATE_PREFIX)
	var flag_name: String = flag.substr(NEGATE_PREFIX.length()) if negated else flag
	if not flags.has(flag_name):
		problems.append(_problem(ctx.source, path, "unknown flag '%s'" % flag_name))
		return false
	var is_set: bool = flags[flag_name] is bool and flags[flag_name]
	return not is_set if negated else is_set


static func _is_number(v: Variant) -> bool:
	return v is int or v is float


## JSON numbers arrive as floats: 2.0 counts as the integer 2.
static func _is_int(v: Variant) -> bool:
	return _is_number(v) and float(v) == floorf(float(v))


## JSON numbers arrive as floats: 8.0 counts as the integer 8.
static func _is_positive_int(v: Variant) -> bool:
	return _is_int(v) and float(v) > 0.0


static func _problem(source: String, path: String, message: String) -> String:
	return "%s %s: %s" % [source, path, message]
