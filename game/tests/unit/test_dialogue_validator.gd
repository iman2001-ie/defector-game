extends GutTest
## DialogueValidator (Story 5.1): one problem per defect, each naming the file
## and the sequence id; story text is capped, combat limits are Story 5.2's.

const SRC: String = "res://data/dialogue/test.json"
const MAX: int = 200


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
	assert_eq(DialogueValidator.validate(data, SRC, MAX), [] as Array[String])


func test_every_speaker_is_known() -> void:
	for speaker: StringName in DialogueValidator.SPEAKERS:
		var problems: Array[String] = DialogueValidator.validate_sequence("s", _seq("story", [_line(String(speaker), "Hi.")]), SRC, MAX)
		assert_eq(problems, [] as Array[String], "speaker %s" % speaker)


func test_sequences_missing() -> void:
	_only_problem(DialogueValidator.validate({}, SRC, MAX), "sequences: missing or not an object")


func test_sequences_not_an_object() -> void:
	_only_problem(DialogueValidator.validate({"sequences": []}, SRC, MAX), "sequences: missing or not an object")


func test_sequence_not_an_object() -> void:
	_only_problem(DialogueValidator.validate({"sequences": {"odd": 5}}, SRC, MAX), "sequences.odd: is not an object")


func test_empty_or_blank_id() -> void:
	var good: Dictionary = _seq("story", [_line("ryn", "Hi.")])
	_only_problem(DialogueValidator.validate_sequence("", good, SRC, MAX), "sequence id is empty")
	_only_problem(DialogueValidator.validate_sequence("  ", good, SRC, MAX), "sequence id is empty")
	_only_problem(DialogueValidator.validate({"sequences": {"": good}}, SRC, MAX), "sequence id is empty")


func test_unknown_mode() -> void:
	_only_problem(DialogueValidator.validate_sequence("m", _seq("chatter", [_line("ryn", "Hi.")]), SRC, MAX), "sequences.m.mode: unknown mode 'chatter'")


func test_missing_mode() -> void:
	var seq: Dictionary = {"lines": [_line("ryn", "Hi.")]}
	_only_problem(DialogueValidator.validate_sequence("m", seq, SRC, MAX), "sequences.m.mode")


func test_lines_missing() -> void:
	_only_problem(DialogueValidator.validate_sequence("l", {"mode": "story"}, SRC, MAX), "sequences.l.lines: missing or not an array")


func test_lines_not_an_array() -> void:
	_only_problem(DialogueValidator.validate_sequence("l", _seq("story", {}), SRC, MAX), "sequences.l.lines: missing or not an array")


func test_lines_empty() -> void:
	_only_problem(DialogueValidator.validate_sequence("l", _seq("story", []), SRC, MAX), "sequences.l.lines: is empty")


func test_line_not_an_object() -> void:
	_only_problem(DialogueValidator.validate_sequence("l", _seq("story", ["text"]), SRC, MAX), "sequences.l.lines[0]: is not an object")


func test_unknown_speaker() -> void:
	_only_problem(DialogueValidator.validate_sequence("s", _seq("story", [_line("bob", "Hi.")]), SRC, MAX), "sequences.s.lines[0].speaker: unknown speaker 'bob'")


func test_missing_speaker() -> void:
	_only_problem(DialogueValidator.validate_sequence("s", _seq("story", [{"text": "Hi."}]), SRC, MAX), "sequences.s.lines[0].speaker")


func test_text_missing_or_not_a_string() -> void:
	_only_problem(DialogueValidator.validate_sequence("t", _seq("story", [{"speaker": "ryn"}]), SRC, MAX), "sequences.t.lines[0].text: missing or not a string")
	_only_problem(DialogueValidator.validate_sequence("t", _seq("story", [_line("ryn", 4)]), SRC, MAX), "sequences.t.lines[0].text: missing or not a string")


func test_text_empty_after_strip() -> void:
	_only_problem(DialogueValidator.validate_sequence("t", _seq("story", [_line("ryn", "  \t ")]), SRC, MAX), "sequences.t.lines[0].text: is empty")
	_only_problem(DialogueValidator.validate_sequence("t", _seq("story", [_line("ryn", "")]), SRC, MAX), "sequences.t.lines[0].text: is empty")


func test_story_text_limit() -> void:
	var at_max: String = "a".repeat(MAX)
	assert_eq(DialogueValidator.validate_sequence("t", _seq("story", [_line("ryn", at_max)]), SRC, MAX), [] as Array[String], "200 chars ok")
	_only_problem(DialogueValidator.validate_sequence("t", _seq("story", [_line("ryn", at_max + "b")]), SRC, MAX), "sequences.t.lines[0].text: story line has 201 characters, more than 200")


func test_combat_text_has_no_story_limit() -> void:
	var long_text: String = "a".repeat(MAX + 1)
	assert_eq(DialogueValidator.validate_sequence("c", _seq("combat", [_line("isolde", long_text)]), SRC, MAX), [] as Array[String], "combat limits are Story 5.2's")


func test_negative_limit_skips_the_length_check() -> void:
	var long_text: String = "a".repeat(MAX + 1)
	assert_eq(DialogueValidator.validate_sequence("t", _seq("story", [_line("ryn", long_text)]), SRC, -1), [] as Array[String])


func test_every_problem_is_reported() -> void:
	var seq: Dictionary = _seq("chatter", [_line("bob", ""), 3, _line("ryn", "ok")])
	var problems: Array[String] = DialogueValidator.validate_sequence("x", seq, SRC, MAX)
	assert_eq(problems.size(), 4, "mode, speaker, text, non-object line: %s" % [problems])
	for problem: String in problems:
		assert_string_contains(problem, "%s sequences.x" % SRC)


func test_validate_collects_every_sequence() -> void:
	var data: Dictionary = {"sequences": {
		"a": _seq("story", []),
		"b": _seq("bad", [_line("ryn", "Hi.")]),
		"c": _seq("story", [_line("ryn", "Fine.")]),
	}}
	var problems: Array[String] = DialogueValidator.validate(data, SRC, MAX)
	assert_eq(problems.size(), 2, "%s" % [problems])
