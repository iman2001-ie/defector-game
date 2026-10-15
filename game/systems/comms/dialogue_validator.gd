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
##     "music"?: one of LevelValidator.MUSIC_ACTIONS } }
## One problem each for: `cut_off_at` in a story sequence; `cut_off_at` not a
## whole number from 1 to text length - 1 (a JSON float with no fraction is
## whole); `after` without `cut_off_at` or not an object; an unknown `after`
## key; `silence` other than `until_wave_clear`; `shake` not in
## ImpactTier.NAMES or SHAKE_CUTOFF; `sfx` not a non-empty string; `music` not in
## LevelValidator.MUSIC_ACTIONS.
##
## Choice (Story 7.5, the Final Choice; also Isolde's Level 1 surrender offer
## since the Epic 7 playtest, 2026-10-13), story sequences only:
##   "choice": { "options": [ { "id": "surrender"|"destroy"|"refuse",
##     "label": "...", "next": "<story sequence id>", "fail"?: "surrender" },
##     { ... } ] }
## An option's optional `fail` names the level_failed reason CommsChannel
## raises once that option's `next` response has played (the surrender lose
## ending).
## One problem each for: `choice` in a combat sequence; `choice` not an object;
## `options` missing or not an array; `options` not exactly CHOICE_OPTIONS
## entries; an option that isn't an object; an `id` not in CHOICE_IDS or
## repeating an earlier option's; a `label` or `next` that isn't a non-empty
## string; a `fail` not in FAIL_REASONS. Whether `next` names a known story
## sequence is a cross-file check (the data test; CommsChannel logs an unknown
## one and finishes at once).
##
## Story line sound and silence (Epic 7 playtest J, Tarek's fall as story
## beats), story sequences only:
##   a line's optional "sfx": "<sfx id>" plays when the line shows (and stops
##   when it ends); a sequence's optional "silence_after": "until_wave_clear"
##   silences combat comms once the sequence finishes, as a cut-off line's
##   `after.silence` does.
## One problem each for: `sfx` on a combat line (combat lines use the cut-off
## `after.sfx`); `sfx` not a non-empty string; `silence_after` on a combat
## sequence; `silence_after` other than `until_wave_clear`.
## The `static` speaker (the open channel's noise) has an empty name and no
## portrait in comms.speakers.
##
## Story line portrait override (operator playtest 2026-10-15, Tarek's "..."):
##   a story line's optional "portrait": false shows that line without the
##   speaker's portrait (name and accent kept); absent keeps comms.speakers'
##   setting. One problem each for: `portrait` on a combat line; `portrait`
##   not a bool.

const SPEAKERS: Array[StringName] = [&"vale", &"isolde", &"tarek", &"ryn", &"system", &"static"]
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
## Sequence key of the Final Choice block and its keys (Story 7.5).
const CHOICE_KEY: String = "choice"
const CHOICE_OPTIONS_KEY: String = "options"
const OPTION_ID: String = "id"
const OPTION_LABEL: String = "label"
const OPTION_NEXT: String = "next"
const OPTION_FAIL: String = "fail"
## The option ids a choice may use (each at most once).
const CHOICE_IDS: Array[String] = ["surrender", "destroy", "refuse"]
## The level_failed reasons an option's `fail` may name.
const FAIL_REASONS: Array[String] = ["surrender"]
## A choice has exactly this many options.
const CHOICE_OPTIONS: int = 2
## Story line key: an sfx id played while the line shows (Epic 7 playtest J).
const LINE_SFX_KEY: String = "sfx"
## Story line key: false hides the speaker's portrait on this line only.
const LINE_PORTRAIT_KEY: String = "portrait"
## Story sequence key: silence combat comms once it finishes (Epic 7 playtest J).
const SILENCE_AFTER_KEY: String = "silence_after"


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
	problems.append_array(_choice_problems(dict, mode, path, seq_path))
	if dict.has(SILENCE_AFTER_KEY):
		var silence_path: String = seq_path + "." + SILENCE_AFTER_KEY
		if mode != MODE_STORY:
			problems.append(_problem(path, silence_path, "silence_after is only allowed in story sequences"))
		elif not (dict[SILENCE_AFTER_KEY] is String and (dict[SILENCE_AFTER_KEY] as String) == SILENCE_UNTIL_WAVE_CLEAR):
			problems.append(_problem(path, silence_path, "must be '%s', not '%s'" % [SILENCE_UNTIL_WAVE_CLEAR, str(dict[SILENCE_AFTER_KEY])]))
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
		if line_dict.has(LINE_SFX_KEY):
			var sfx_path: String = line_path + "." + LINE_SFX_KEY
			var sfx: Variant = line_dict[LINE_SFX_KEY]
			if mode != MODE_STORY:
				problems.append(_problem(path, sfx_path, "a line sfx is only allowed in story sequences"))
			elif not (sfx is String and not (sfx as String).strip_edges().is_empty()):
				problems.append(_problem(path, sfx_path, "must be a non-empty sfx id, not '%s'" % str(sfx)))
		if line_dict.has(LINE_PORTRAIT_KEY):
			var portrait_path: String = line_path + "." + LINE_PORTRAIT_KEY
			if mode != MODE_STORY:
				problems.append(_problem(path, portrait_path, "a portrait override is only allowed in story sequences"))
			elif not (line_dict[LINE_PORTRAIT_KEY] is bool):
				problems.append(_problem(path, portrait_path, "must be true or false, not '%s'" % str(line_dict[LINE_PORTRAIT_KEY])))
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


## The choice problems of one sequence (Story 7.5); none without a `choice` key.
static func _choice_problems(seq: Dictionary, mode: StringName, path: String, seq_path: String) -> Array[String]:
	var problems: Array[String] = []
	if not seq.has(CHOICE_KEY):
		return problems
	var choice_path: String = seq_path + "." + CHOICE_KEY
	if mode != MODE_STORY:
		problems.append(_problem(path, choice_path, "choice is only allowed in story sequences"))
		return problems
	var choice: Variant = seq[CHOICE_KEY]
	if not (choice is Dictionary):
		problems.append(_problem(path, choice_path, "is not an object"))
		return problems
	var options_path: String = choice_path + "." + CHOICE_OPTIONS_KEY
	var options: Variant = (choice as Dictionary).get(CHOICE_OPTIONS_KEY)
	if not (options is Array):
		problems.append(_problem(path, options_path, "missing or not an array"))
		return problems
	if (options as Array).size() != CHOICE_OPTIONS:
		problems.append(_problem(path, options_path, "has %d options, exactly %d allowed" % [(options as Array).size(), CHOICE_OPTIONS]))
	var seen: Array[String] = []
	for i: int in (options as Array).size():
		var option_path: String = "%s[%d]" % [options_path, i]
		var option: Variant = (options as Array)[i]
		if not (option is Dictionary):
			problems.append(_problem(path, option_path, "is not an object"))
			continue
		var dict: Dictionary = option
		var id: Variant = dict.get(OPTION_ID)
		if not (id is String and CHOICE_IDS.has(id as String)):
			problems.append(_problem(path, option_path + "." + OPTION_ID, "must be one of %s, not '%s'" % [", ".join(CHOICE_IDS), str(id)]))
		elif seen.has(id as String):
			problems.append(_problem(path, option_path + "." + OPTION_ID, "duplicate option id '%s'" % str(id)))
		else:
			seen.append(id as String)
		for key: String in [OPTION_LABEL, OPTION_NEXT]:
			var value: Variant = dict.get(key)
			if not (value is String and not (value as String).strip_edges().is_empty()):
				problems.append(_problem(path, option_path + "." + key, "must be a non-empty string, not '%s'" % str(value)))
		if dict.has(OPTION_FAIL) and not (dict[OPTION_FAIL] is String and FAIL_REASONS.has(dict[OPTION_FAIL] as String)):
			problems.append(_problem(path, option_path + "." + OPTION_FAIL, "must be one of %s, not '%s'" % [", ".join(FAIL_REASONS), str(dict[OPTION_FAIL])]))
	return problems


static func _problem(source: String, key_path: String, message: String) -> String:
	return "%s %s: %s" % [source, key_path, message]
