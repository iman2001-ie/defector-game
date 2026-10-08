class_name LevelValidator
extends RefCounted
## Checks a level JSON dictionary (data/levels/level_<id>.json). Pure logic,
## no nodes. Config.level() logs every problem; the GUT data test fails on any.
##
## Each problem names the source file and the key path, for example
## `res://data/levels/level_dev.json waves[1].spawns[0].type: unknown enemy type 'bogus'`.

const WHENS: Array[String] = ["wave_start", "progress", "wave_clear", "boss_phase", "boss_hp_le"]


## Returns every problem found (empty when the level is valid).
static func validate(data: Dictionary, source: String, known_types: Array[StringName]) -> Array[String]:
	var problems: Array[String] = []
	if not _is_number(data.get("id")):
		problems.append(_problem(source, "id", "missing or not a number"))
	var waves: Variant = data.get("waves")
	if not (waves is Array):
		problems.append(_problem(source, "waves", "missing or not an array"))
		return problems
	if (waves as Array).is_empty():
		problems.append(_problem(source, "waves", "is empty"))
	for i: int in (waves as Array).size():
		var wave: Variant = (waves as Array)[i]
		var path: String = "waves[%d]" % i
		if wave is Dictionary:
			_check_wave(wave as Dictionary, source, path, known_types, problems)
		else:
			problems.append(_problem(source, path, "is not an object"))
	return problems


static func _check_wave(wave: Dictionary, source: String, path: String, known_types: Array[StringName], problems: Array[String]) -> void:
	if wave.has("spawns"):
		var spawns: Variant = wave["spawns"]
		if spawns is Array:
			_check_entries(spawns as Array, source, path + ".spawns", known_types, problems)
		else:
			problems.append(_problem(source, path + ".spawns", "is not an array"))
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

	var group_names: Array[String] = []
	if wave.has("groups"):
		var groups: Variant = wave["groups"]
		if groups is Dictionary:
			for key: Variant in groups:
				var group_name: String = str(key)
				group_names.append(group_name)
				var group_path: String = "%s.groups.%s" % [path, group_name]
				var entries: Variant = (groups as Dictionary)[key]
				if entries is Array:
					_check_entries(entries as Array, source, group_path, known_types, problems)
				else:
					problems.append(_problem(source, group_path, "is not an array"))
		else:
			problems.append(_problem(source, path + ".groups", "is not an object"))

	var spawned_groups: Array[String] = []
	if wave.has("triggers"):
		var triggers: Variant = wave["triggers"]
		if triggers is Array:
			for t: int in (triggers as Array).size():
				var trigger_path: String = "%s.triggers[%d]" % [path, t]
				var trigger: Variant = (triggers as Array)[t]
				if trigger is Dictionary:
					_check_trigger(trigger as Dictionary, source, trigger_path, group_names, spawned_groups, problems)
				else:
					problems.append(_problem(source, trigger_path, "is not an object"))
		else:
			problems.append(_problem(source, path + ".triggers", "is not an array"))

	for group_name: String in group_names:
		if not spawned_groups.has(group_name):
			problems.append(_problem(source, "%s.groups.%s" % [path, group_name], "is never named by a spawn_group action in this wave"))


## Spawn and group entries: a known type and an integer count > 0; an optional valid formation.
static func _check_entries(entries: Array, source: String, path: String, known_types: Array[StringName], problems: Array[String]) -> void:
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
		if not _is_positive_int(dict.get("count")):
			problems.append(_problem(source, entry_path + ".count", "must be an integer > 0"))
		if dict.has("formation"):
			var formation: Variant = dict["formation"]
			if not (formation is String and Formation.is_valid(formation as String)):
				problems.append(_problem(source, entry_path + ".formation", "invalid formation '%s'" % str(formation)))


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


static func _check_trigger(trigger: Dictionary, source: String, path: String, group_names: Array[String], spawned_groups: Array[String], problems: Array[String]) -> void:
	var when: String = str(trigger.get("when", ""))
	if not WHENS.has(when):
		problems.append(_problem(source, path + ".when", "unknown when '%s'" % when))
	if when == "progress":
		var at: Variant = trigger.get("at")
		if not (_is_number(at) and float(at) >= 0.0 and float(at) <= 1.0):
			problems.append(_problem(source, path + ".at", "progress needs at in 0-1"))
	if not trigger.has("actions"):
		return
	var actions: Variant = trigger["actions"]
	if not (actions is Array):
		problems.append(_problem(source, path + ".actions", "is not an array"))
		return
	for i: int in (actions as Array).size():
		var action_path: String = "%s.actions[%d]" % [path, i]
		var action: Variant = (actions as Array)[i]
		if not (action is Dictionary):
			problems.append(_problem(source, action_path, "is not an object"))
			continue
		if (action as Dictionary).has("spawn_group"):
			var group_name: String = str((action as Dictionary)["spawn_group"])
			spawned_groups.append(group_name)
			if not group_names.has(group_name):
				problems.append(_problem(source, action_path + ".spawn_group", "names no group '%s' in this wave" % group_name))


static func _is_number(v: Variant) -> bool:
	return v is int or v is float


## JSON numbers arrive as floats: 8.0 counts as the integer 8.
static func _is_positive_int(v: Variant) -> bool:
	return _is_number(v) and float(v) == floorf(float(v)) and float(v) > 0.0


static func _problem(source: String, path: String, message: String) -> String:
	return "%s %s: %s" % [source, path, message]
