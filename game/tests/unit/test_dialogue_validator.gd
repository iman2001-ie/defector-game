extends GutTest
## DialogueValidator (Stories 5.1-5.4): one problem per defect, each naming the
## file and the sequence id; story text is capped at 200 characters, a combat
## sequence has exactly one line of at most 50; is_interruption() leaves out
## the cut-off line. Story 5.4: the cut_off_at / after rules.

const SRC: String = "res://data/dialogue/test.json"
const MAX: int = 200
const CMAX: int = 50


func _seq(mode: Variant, lines: Variant) -> Dictionary:
	return {"mode": mode, "lines": lines}


func _line(speaker: Variant, text: Variant) -> Dictionary:
	return {"speaker": speaker, "text": text}


func _only_problem(problems: Array[String], fragment: String) -> void:
	assert_eq(problems.size(), 1, "one problem: %s" % [problems])
	if problems.size() == 1:
		assert_string_contains(problems[0], fragment)
		assert_string_contains(problems[0], SRC)


func test_constants() -> void:
	assert_eq(DialogueValidator.SPEAKERS, [&"vale", &"isolde", &"tarek", &"ryn", &"system"] as Array[StringName])
	assert_eq(DialogueValidator.MODES, [&"story", &"combat"] as Array[StringName])


func test_valid_file_has_no_problems() -> void:
	var data: Dictionary = {"sequences": {
		"a": _seq("story", [_line("tarek", "Hello, General."), _line("vale", "Hello.")]),
		"b": _seq("combat", [_line("isolde", "Still alive?")]),
	}}
	assert_eq(DialogueValidator.validate(data, SRC, MAX, CMAX), [] as Array[String])


func test_every_speaker_is_known() -> void:
	for speaker: StringName in DialogueValidator.SPEAKERS:
		var problems: Array[String] = DialogueValidator.validate_sequence("s", _seq("story", [_line(String(speaker), "Hi.")]), SRC, MAX, CMAX)
		assert_eq(problems, [] as Array[String], "speaker %s" % speaker)


func test_sequences_missing() -> void:
	_only_problem(DialogueValidator.validate({}, SRC, MAX, CMAX), "sequences: missing or not an object")


func test_sequences_not_an_object() -> void:
	_only_problem(DialogueValidator.validate({"sequences": []}, SRC, MAX, CMAX), "sequences: missing or not an object")


func test_sequence_not_an_object() -> void:
	_only_problem(DialogueValidator.validate({"sequences": {"odd": 5}}, SRC, MAX, CMAX), "sequences.odd: is not an object")


func test_empty_or_blank_id() -> void:
	var good: Dictionary = _seq("story", [_line("ryn", "Hi.")])
	_only_problem(DialogueValidator.validate_sequence("", good, SRC, MAX, CMAX), "sequence id is empty")
	_only_problem(DialogueValidator.validate_sequence("  ", good, SRC, MAX, CMAX), "sequence id is empty")
	_only_problem(DialogueValidator.validate({"sequences": {"": good}}, SRC, MAX, CMAX), "sequence id is empty")


func test_unknown_mode() -> void:
	_only_problem(DialogueValidator.validate_sequence("m", _seq("chatter", [_line("ryn", "Hi.")]), SRC, MAX, CMAX), "sequences.m.mode: unknown mode 'chatter'")


func test_missing_mode() -> void:
	var seq: Dictionary = {"lines": [_line("ryn", "Hi.")]}
	_only_problem(DialogueValidator.validate_sequence("m", seq, SRC, MAX, CMAX), "sequences.m.mode")


func test_lines_missing() -> void:
	_only_problem(DialogueValidator.validate_sequence("l", {"mode": "story"}, SRC, MAX, CMAX), "sequences.l.lines: missing or not an array")


func test_lines_not_an_array() -> void:
	_only_problem(DialogueValidator.validate_sequence("l", _seq("story", {}), SRC, MAX, CMAX), "sequences.l.lines: missing or not an array")


func test_lines_empty() -> void:
	_only_problem(DialogueValidator.validate_sequence("l", _seq("story", []), SRC, MAX, CMAX), "sequences.l.lines: is empty")


func test_line_not_an_object() -> void:
	_only_problem(DialogueValidator.validate_sequence("l", _seq("story", ["text"]), SRC, MAX, CMAX), "sequences.l.lines[0]: is not an object")


func test_unknown_speaker() -> void:
	_only_problem(DialogueValidator.validate_sequence("s", _seq("story", [_line("bob", "Hi.")]), SRC, MAX, CMAX), "sequences.s.lines[0].speaker: unknown speaker 'bob'")


func test_missing_speaker() -> void:
	_only_problem(DialogueValidator.validate_sequence("s", _seq("story", [{"text": "Hi."}]), SRC, MAX, CMAX), "sequences.s.lines[0].speaker")


func test_text_missing_or_not_a_string() -> void:
	_only_problem(DialogueValidator.validate_sequence("t", _seq("story", [{"speaker": "ryn"}]), SRC, MAX, CMAX), "sequences.t.lines[0].text: missing or not a string")
	_only_problem(DialogueValidator.validate_sequence("t", _seq("story", [_line("ryn", 4)]), SRC, MAX, CMAX), "sequences.t.lines[0].text: missing or not a string")


func test_text_empty_after_strip() -> void:
	_only_problem(DialogueValidator.validate_sequence("t", _seq("story", [_line("ryn", "  \t ")]), SRC, MAX, CMAX), "sequences.t.lines[0].text: is empty")
	_only_problem(DialogueValidator.validate_sequence("t", _seq("story", [_line("ryn", "")]), SRC, MAX, CMAX), "sequences.t.lines[0].text: is empty")


func test_story_text_limit() -> void:
	var at_max: String = "a".repeat(MAX)
	assert_eq(DialogueValidator.validate_sequence("t", _seq("story", [_line("ryn", at_max)]), SRC, MAX, CMAX), [] as Array[String], "200 chars ok")
	_only_problem(DialogueValidator.validate_sequence("t", _seq("story", [_line("ryn", at_max + "b")]), SRC, MAX, CMAX), "sequences.t.lines[0].text: story line has 201 characters, more than 200")


func test_combat_text_limit() -> void:
	var at_max: String = "a".repeat(CMAX)
	assert_eq(DialogueValidator.validate_sequence("c", _seq("combat", [_line("isolde", at_max)]), SRC, MAX, CMAX), [] as Array[String], "50 chars ok")
	_only_problem(DialogueValidator.validate_sequence("c", _seq("combat", [_line("isolde", at_max + "b")]), SRC, MAX, CMAX), "sequences.c.lines[0].text: combat line has 51 characters, more than 50")


func test_story_and_combat_limits_apply_to_their_own_mode() -> void:
	var mid: String = "a".repeat(CMAX + 10)
	assert_eq(DialogueValidator.validate_sequence("s", _seq("story", [_line("ryn", mid)]), SRC, MAX, CMAX), [] as Array[String], "60-char story line ok")
	_only_problem(DialogueValidator.validate_sequence("c", _seq("combat", [_line("ryn", mid)]), SRC, MAX, CMAX), "combat line has 60 characters, more than 50")


func test_negative_combat_limit_skips_the_check() -> void:
	var long_text: String = "a".repeat(MAX + 1)
	assert_eq(DialogueValidator.validate_sequence("c", _seq("combat", [_line("isolde", long_text)]), SRC, MAX, -1), [] as Array[String])


func test_combat_has_exactly_one_line() -> void:
	var two: Dictionary = _seq("combat", [_line("isolde", "One."), _line("tarek", "Two.")])
	_only_problem(DialogueValidator.validate_sequence("c", two, SRC, MAX, CMAX), "sequences.c.lines: combat sequence has 2 lines, exactly 1 allowed")
	var three_story: Dictionary = _seq("story", [_line("isolde", "One."), _line("tarek", "Two."), _line("ryn", "Three.")])
	assert_eq(DialogueValidator.validate_sequence("s", three_story, SRC, MAX, CMAX), [] as Array[String], "story sequences may have many lines")


func test_is_interruption() -> void:
	assert_true(DialogueValidator.is_interruption(_seq("combat", [_line("isolde", "Still alive?")])), "a combat line")
	assert_false(DialogueValidator.is_interruption(_seq("story", [_line("isolde", "Story.")])), "story is not")
	var cut: Dictionary = _seq("combat", [{"speaker": "tarek", "text": "General, get behind me, I've got you cov-", "cut_off_at": 39}])
	assert_false(DialogueValidator.is_interruption(cut), "the cut-off line doesn't count")
	assert_false(DialogueValidator.is_interruption({}), "empty dict")
	assert_false(DialogueValidator.is_interruption({"mode": 3, "lines": []}), "non-string mode")


func test_negative_limit_skips_the_length_check() -> void:
	var long_text: String = "a".repeat(MAX + 1)
	assert_eq(DialogueValidator.validate_sequence("t", _seq("story", [_line("ryn", long_text)]), SRC, -1, CMAX), [] as Array[String])


func test_every_problem_is_reported() -> void:
	var seq: Dictionary = _seq("chatter", [_line("bob", ""), 3, _line("ryn", "ok")])
	var problems: Array[String] = DialogueValidator.validate_sequence("x", seq, SRC, MAX, CMAX)
	assert_eq(problems.size(), 4, "mode, speaker, text, non-object line: %s" % [problems])
	for problem: String in problems:
		assert_string_contains(problem, "%s sequences.x" % SRC)


func test_validate_collects_every_sequence() -> void:
	var data: Dictionary = {"sequences": {
		"a": _seq("story", []),
		"b": _seq("bad", [_line("ryn", "Hi.")]),
		"c": _seq("story", [_line("ryn", "Fine.")]),
	}}
	var problems: Array[String] = DialogueValidator.validate(data, SRC, MAX, CMAX)
	assert_eq(problems.size(), 2, "%s" % [problems])


# --- Cut-off lines (Story 5.4) -------------------------------------------------

const CUT_TEXT: String = "General, get behind me, I've got you cov—"


func _cut_line(extra: Dictionary) -> Dictionary:
	var line: Dictionary = _line("tarek", CUT_TEXT)
	line.merge(extra, true)
	return line


func _cut_problems(mode: String, extra: Dictionary) -> Array[String]:
	return DialogueValidator.validate_sequence("cut", _seq(mode, [_cut_line(extra)]), SRC, MAX, CMAX)


func test_valid_cut_off_lines() -> void:
	var full: Dictionary = {"cut_off_at": 39.0, "after": {"silence": "until_wave_clear", "shake": "large", "sfx": "comms_static", "music": "stop"}}
	assert_eq(_cut_problems("combat", full), [] as Array[String], "full after (JSON float 39.0 is whole)")
	assert_eq(_cut_problems("combat", {"cut_off_at": 39}), [] as Array[String], "no after")
	assert_eq(_cut_problems("combat", {"cut_off_at": 1, "after": {}}), [] as Array[String], "empty after, lowest cut")
	assert_eq(_cut_problems("combat", {"cut_off_at": CUT_TEXT.length() - 1}), [] as Array[String], "highest cut")
	for music: String in LevelValidator.MUSIC_ACTIONS:
		assert_eq(_cut_problems("combat", {"cut_off_at": 39, "after": {"music": music}}), [] as Array[String], music)
	for tier: String in ImpactTier.NAMES:
		assert_eq(_cut_problems("combat", {"cut_off_at": 39, "after": {"shake": tier}}), [] as Array[String], tier)


func test_cut_off_in_a_story_sequence() -> void:
	_only_problem(_cut_problems("story", {"cut_off_at": 39}), "sequences.cut.lines[0].cut_off_at: cut_off_at is only allowed in combat sequences")


func test_cut_off_at_must_be_a_whole_number_in_range() -> void:
	_only_problem(_cut_problems("combat", {"cut_off_at": 0}), "lines[0].cut_off_at: must be from 1 to 40")
	_only_problem(_cut_problems("combat", {"cut_off_at": 1.5}), "lines[0].cut_off_at: must be a whole number")
	_only_problem(_cut_problems("combat", {"cut_off_at": CUT_TEXT.length()}), "lines[0].cut_off_at: must be from 1 to 40")
	_only_problem(_cut_problems("combat", {"cut_off_at": 99.0}), "lines[0].cut_off_at: must be from 1 to 40")
	_only_problem(_cut_problems("combat", {"cut_off_at": -3}), "lines[0].cut_off_at")
	_only_problem(_cut_problems("combat", {"cut_off_at": "39"}), "lines[0].cut_off_at: must be a whole number")
	_only_problem(_cut_problems("combat", {"cut_off_at": true}), "lines[0].cut_off_at: must be a whole number")


func test_after_without_cut_off_at() -> void:
	_only_problem(_cut_problems("combat", {"after": {"sfx": "comms_static"}}), "lines[0].after: after needs cut_off_at")


func test_after_not_an_object() -> void:
	_only_problem(_cut_problems("combat", {"cut_off_at": 39, "after": "static"}), "lines[0].after: is not an object")


func test_after_unknown_key() -> void:
	_only_problem(_cut_problems("combat", {"cut_off_at": 39, "after": {"bogus": 1}}), "lines[0].after.bogus: unknown after key 'bogus'")


func test_after_bad_values() -> void:
	_only_problem(_cut_problems("combat", {"cut_off_at": 39, "after": {"silence": "forever"}}), "lines[0].after.silence: must be 'until_wave_clear'")
	_only_problem(_cut_problems("combat", {"cut_off_at": 39, "after": {"shake": "huge"}}), "lines[0].after.shake: must be one of small")
	_only_problem(_cut_problems("combat", {"cut_off_at": 39, "after": {"sfx": ""}}), "lines[0].after.sfx: must be a non-empty sfx id")
	_only_problem(_cut_problems("combat", {"cut_off_at": 39, "after": {"sfx": 5}}), "lines[0].after.sfx")
	_only_problem(_cut_problems("combat", {"cut_off_at": 39, "after": {"music": "loud"}}), "lines[0].after.music: must be one of stop, combat, boss")


func test_cut_off_line_is_not_an_interruption() -> void:
	assert_false(DialogueValidator.is_interruption(_seq("combat", [_cut_line({"cut_off_at": 39})])))
