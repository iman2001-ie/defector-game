class_name DialogueValidator
extends RefCounted
## Checks a dialogue JSON dictionary (data/dialogue/<scene>.json, Story 5.1).
## Pure logic, no nodes, no autoload reads: the caller passes the story and
## combat line limits. Config logs every problem and leaves out any sequence that has one;
## the GUT data test fails on any.
##
## Shape: { "sequences": { "<id>": { "mode": "story"|"combat",
##   "lines": [ { "speaker": "...", "text": "..." } ] } } }
##
## Each problem names the source file and the sequence id, for example
## `res://data/dialogue/dev.json sequences.dev_comms_check.lines[1].speaker: unknown speaker 'bob'`.
## Combat sequences (Story 5.2) have exactly one line of at most
## `combat_max_chars` characters. is_interruption() tells the per-level
## interruption cap which combat sequences count (not the Tarek cut-off).

const SPEAKERS: Array[StringName] = [&"vale", &"isolde", &"tarek", &"ryn", &"system"]
const MODES: Array[StringName] = [&"story", &"combat"]
const MODE_STORY: StringName = &"story"
const MODE_COMBAT: StringName = &"combat"
## Line key of a cut-off line (Story 5.4); such a sequence isn't an interruption.
const CUT_OFF_KEY: String = "cut_off_at"


## Returns every problem in the file (empty when it is valid).
static func validate(data: Dictionary, path: String, story_max_chars: int, combat_max_chars: int) -> Array[String]:
	var problems: Array[String] = []
	var sequences: Variant = data.get("sequences")
	if not (sequences is Dictionary):
		problems.append(_problem(path, "sequences", "missing or not an object"))
		return problems
	for key: Variant in sequences:
		problems.append_array(validate_sequence(str(key), (sequences as Dictionary)[key], path, story_max_chars, combat_max_chars))
	return problems


## Returns every problem in one sequence `seq` with id `id` from `path`. A
## negative `story_max_chars` / `combat_max_chars` skips that length check
## (Config passes -1 when the tuning key is missing).
static func validate_sequence(id: String, seq: Variant, path: String, story_max_chars: int, combat_max_chars: int) -> Array[String]:
	var problems: Array[String] = []
	var seq_path: String = "sequences.%s" % id
	if id.strip_edges().is_empty():
		problems.append(_problem(path, "sequences.\"%s\"" % id, "sequence id is empty"))
		return problems
	if not (seq is Dictionary):
		problems.append(_problem(path, seq_path, "is not an object"))
		return problems
	var dict: Dictionary = seq
	var mode_raw: Variant = dict.get("mode")
	var mode: StringName = StringName(mode_raw as String) if mode_raw is String else &""
	if not MODES.has(mode):
		problems.append(_problem(path, seq_path + ".mode", "unknown mode '%s'" % str(mode_raw)))
	var lines: Variant = dict.get("lines")
	if not (lines is Array):
		problems.append(_problem(path, seq_path + ".lines", "missing or not an array"))
		return problems
	if (lines as Array).is_empty():
		problems.append(_problem(path, seq_path + ".lines", "is empty"))
		return problems
	if mode == MODE_COMBAT and (lines as Array).size() != 1:
		problems.append(_problem(path, seq_path + ".lines", "combat sequence has %d lines, exactly 1 allowed" % (lines as Array).size()))
	for i: int in (lines as Array).size():
		var line_path: String = "%s.lines[%d]" % [seq_path, i]
		var line: Variant = (lines as Array)[i]
		if not (line is Dictionary):
			problems.append(_problem(path, line_path, "is not an object"))
			continue
		var line_dict: Dictionary = line
		var speaker_raw: Variant = line_dict.get("speaker")
		if not (speaker_raw is String and SPEAKERS.has(StringName(speaker_raw as String))):
			problems.append(_problem(path, line_path + ".speaker", "unknown speaker '%s'" % str(speaker_raw)))
		var text_raw: Variant = line_dict.get("text")
		if not (text_raw is String):
			problems.append(_problem(path, line_path + ".text", "missing or not a string"))
			continue
		var text: String = text_raw
		if text.strip_edges().is_empty():
			problems.append(_problem(path, line_path + ".text", "is empty"))
		elif mode == MODE_STORY and story_max_chars >= 0 and text.length() > story_max_chars:
			problems.append(_problem(path, line_path + ".text", "story line has %d characters, more than %d" % [text.length(), story_max_chars]))
		elif mode == MODE_COMBAT and combat_max_chars >= 0 and text.length() > combat_max_chars:
			problems.append(_problem(path, line_path + ".text", "combat line has %d characters, more than %d" % [text.length(), combat_max_chars]))
	return problems


## True for a combat-mode sequence none of whose lines carries `cut_off_at`:
## the interruptions the per-level cap counts (the Tarek cut-off, Story 5.4,
## doesn't count).
static func is_interruption(seq: Dictionary) -> bool:
	var mode: Variant = seq.get("mode")
	if not (mode is String and StringName(mode as String) == MODE_COMBAT):
		return false
	var lines: Variant = seq.get("lines")
	if lines is Array:
		for line: Variant in lines as Array:
			if line is Dictionary and (line as Dictionary).has(CUT_OFF_KEY):
				return false
	return true


static func _problem(source: String, key_path: String, message: String) -> String:
	return "%s %s: %s" % [source, key_path, message]
