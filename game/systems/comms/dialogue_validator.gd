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
##
## Cut-off lines (Story 5.4), combat sequences only:
##   { "speaker", "text", "cut_off_at": <int>, "after"?: { "silence"?:
##     "until_wave_clear", "shake"?: "<ImpactTier name>"|"cutoff", "sfx"?: "<sfx id>",
##     "music"?: "stop"|"combat"|"boss" } }
## One problem each for: `cut_off_at` in a story sequence; `cut_off_at` not a
## whole number from 1 to text length - 1 (a JSON float with no fraction is
## whole); `after` without `cut_off_at` or not an object; an unknown `after`
## key; `silence` other than `until_wave_clear`; `shake` not in
## ImpactTier.NAMES or SHAKE_CUTOFF; `sfx` not a non-empty string; `music` not in
## LevelValidator.MUSIC_ACTIONS.

const SPEAKERS: Array[StringName] = [&"vale", &"isolde", &"tarek", &"ryn", &"system"]
const MODES: Array[StringName] = [&"story", &"combat"]
const MODE_STORY: StringName = &"story"
const MODE_COMBAT: StringName = &"combat"
## Line key of a cut-off line (Story 5.4); such a sequence isn't an interruption.
const CUT_OFF_KEY: String = "cut_off_at"
## Line key of the cut-off effects and its keys (Story 5.4).
const AFTER_KEY: String = "after"
const AFTER_SILENCE: String = "silence"
const AFTER_SHAKE: String = "shake"
const AFTER_SFX: String = "sfx"
const AFTER_MUSIC: String = "music"
## The only `after.silence` value.
const SILENCE_UNTIL_WAVE_CLEAR: String = "until_wave_clear"
## The `after.shake` value for the dedicated cut-off shake (comms.cutoff_shake_px
## / cutoff_shake_s, GDD decision #43); every other value names an ImpactTier.
const SHAKE_CUTOFF: String = "cutoff"


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
		problems.append_array(_cut_off_problems(line_dict, mode, path, line_path))
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


## The cut-off problems of one line (Story 5.4): `cut_off_at` only in combat
## sequences, a whole number from 1 to text length - 1; `after` only with
## `cut_off_at`, an object of the AFTER_KEYS with valid values.
static func _cut_off_problems(line: Dictionary, mode: StringName, path: String, line_path: String) -> Array[String]:
	var problems: Array[String] = []
	var has_cut: bool = line.has(CUT_OFF_KEY)
	if has_cut and mode == MODE_STORY:
		problems.append(_problem(path, line_path + "." + CUT_OFF_KEY, "cut_off_at is only allowed in combat sequences"))
		return problems
	if has_cut:
		var cut: Variant = line[CUT_OFF_KEY]
		var text: Variant = line.get("text")
		var whole: bool = cut is int or (cut is float and is_finite(cut as float) and floorf(cut as float) == (cut as float))
		if not whole:
			problems.append(_problem(path, line_path + "." + CUT_OFF_KEY, "must be a whole number, not '%s'" % str(cut)))
		elif text is String:
			var at: int = int(cut)
			var length: int = (text as String).length()
			if at < 1 or at > length - 1:
				problems.append(_problem(path, line_path + "." + CUT_OFF_KEY, "must be from 1 to %d (text length - 1), not %d" % [length - 1, at]))
	if not line.has(AFTER_KEY):
		return problems
	var after_path: String = line_path + "." + AFTER_KEY
	if not has_cut:
		problems.append(_problem(path, after_path, "after needs cut_off_at"))
		return problems
	var after_raw: Variant = line[AFTER_KEY]
	if not (after_raw is Dictionary):
		problems.append(_problem(path, after_path, "is not an object"))
		return problems
	var after: Dictionary = after_raw
	for key: Variant in after:
		var value: Variant = after[key]
		var key_path: String = "%s.%s" % [after_path, str(key)]
		match str(key):
			AFTER_SILENCE:
				if not (value is String and (value as String) == SILENCE_UNTIL_WAVE_CLEAR):
					problems.append(_problem(path, key_path, "must be '%s', not '%s'" % [SILENCE_UNTIL_WAVE_CLEAR, str(value)]))
			AFTER_SHAKE:
				if not (value is String and ((value as String) == SHAKE_CUTOFF or ImpactTier.NAMES.has(value as String))):
					problems.append(_problem(path, key_path, "must be one of %s, %s, not '%s'" % [", ".join(ImpactTier.NAMES), SHAKE_CUTOFF, str(value)]))
			AFTER_SFX:
				if not (value is String and not (value as String).strip_edges().is_empty()):
					problems.append(_problem(path, key_path, "must be a non-empty sfx id, not '%s'" % str(value)))
			AFTER_MUSIC:
				if not (value is String and LevelValidator.MUSIC_ACTIONS.has(value as String)):
					problems.append(_problem(path, key_path, "must be one of %s, not '%s'" % [", ".join(LevelValidator.MUSIC_ACTIONS), str(value)]))
			_:
				problems.append(_problem(path, key_path, "unknown after key '%s'" % str(key)))
	return problems


static func _problem(source: String, key_path: String, message: String) -> String:
	return "%s %s: %s" % [source, key_path, message]
