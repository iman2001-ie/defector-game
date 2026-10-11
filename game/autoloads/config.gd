extends Node
## Loads data/tuning.json, data/flags.json and every data/dialogue/*.json and
## serves typed, dot-path lookups plus the dialogue sequences.
##
## Gameplay code never indexes `tuning` directly: use num / int_ / flag / section.
## A missing key or wrong type logs an error naming the full key path, asserts
## (when assert_on_missing is true) and returns a neutral fallback.

const DEFAULT_TUNING_PATH: String = "res://data/tuning.json"
const DEFAULT_FLAGS_PATH: String = "res://data/flags.json"
## Level files are keyed by a string id: level_dev.json, later level_1.json.
const LEVEL_PATH_FORMAT: String = "res://data/levels/level_%s.json"
## Every *.json in this dir is a dialogue file (Story 5.1), loaded in name order.
const DEFAULT_DIALOGUE_DIR: String = "res://data/dialogue/"
const DIALOGUE_EXTENSION: String = ".json"
const STORY_MAX_CHARS_KEY: String = "comms.story_line_max_chars"
const COMBAT_MAX_CHARS_KEY: String = "comms.combat_line_max_chars"

var tuning: Dictionary = {}
var flags: Dictionary = {}
## Empty when tuning loaded fine; otherwise a human-readable reason for display.
var load_error: String = ""
## Tests set this to false: a failed assert would abort the test before the fallback returns.
var assert_on_missing: bool = true

var _tuning_path: String = DEFAULT_TUNING_PATH
var _flags_path: String = DEFAULT_FLAGS_PATH
var _dialogue_dir: String = DEFAULT_DIALOGUE_DIR
## Valid dialogue sequences: StringName id -> sequence Dictionary.
var _dialogue: Dictionary = {}


func _ready() -> void:
	load_data()
	_log_summary()


## Loads both files, then the dialogue dir. A tuning failure sets load_error and
## empties tuning; a flags failure empties flags and is logged, but does not
## touch load_error. Dialogue problems are logged and the bad files or
## sequences are left out (see _load_dialogue); they never touch load_error.
func load_data(tuning_path: String = DEFAULT_TUNING_PATH, flags_path: String = DEFAULT_FLAGS_PATH, dialogue_dir: String = DEFAULT_DIALOGUE_DIR) -> void:
	_tuning_path = tuning_path
	_flags_path = flags_path
	_dialogue_dir = dialogue_dir
	load_error = ""

	var tuning_result: Dictionary = _read_json_dict(tuning_path)
	tuning = tuning_result.data
	if not (tuning_result.error as String).is_empty():
		load_error = tuning_result.error

	var flags_result: Dictionary = _read_json_dict(flags_path)
	flags = flags_result.data

	var ignored: Array[String] = []
	_dialogue = _load_dialogue(dialogue_dir, tuning, ignored)


## Re-reads the files most recently passed to load_data() and validates them
## against the shape of the data loaded now: every current key path must still
## exist with the same kind (extra keys are fine). It re-reads the dialogue dir
## too: a dialogue file that fails to parse (or a missing dir) is a reload
## problem; validator problems are only logged and the bad sequences left out.
## On success commits tuning, flags and dialogue, clears load_error and returns
## true. On any failure logs every problem, leaves tuning, flags, dialogue and
## load_error untouched and returns false.
func reload() -> bool:
	var problems: Array[String] = []
	var tuning_result: Dictionary = _read_json_dict(_tuning_path)
	var flags_result: Dictionary = _read_json_dict(_flags_path)
	var new_tuning: Dictionary = tuning_result.data
	var new_flags: Dictionary = flags_result.data
	var new_dialogue: Dictionary = _load_dialogue(_dialogue_dir, new_tuning, problems)
	if (tuning_result.error as String).is_empty():
		_check_shape(tuning, new_tuning, "tuning", problems)
	else:
		problems.append(tuning_result.error)
	if (flags_result.error as String).is_empty():
		_check_shape(flags, new_flags, "flags", problems)
	else:
		problems.append(flags_result.error)
	if not problems.is_empty():
		Log.error("data", "Reload rejected (%s); previous data kept" % "; ".join(problems))
		return false
	tuning = new_tuning
	flags = new_flags
	_dialogue = new_dialogue
	load_error = ""
	_log_summary()
	return true


func num(path: String) -> float:
	var v: Variant = _lookup(tuning, path)
	if not (v is float or v is int):
		_report_missing("tuning." + path, "a number")
		return 0.0
	return float(v)


func int_(path: String) -> int:
	return int(num(path))


func flag(flag_name: String) -> bool:
	var v: Variant = flags.get(flag_name)
	if not (v is bool):
		_report_missing("flags." + flag_name, "a bool")
		return false
	return v


func section(path: String) -> Dictionary:
	var v: Variant = _lookup(tuning, path)
	if not (v is Dictionary):
		_report_missing("tuning." + path, "a section")
		return {}
	return (v as Dictionary).duplicate(true)


# --- Dialogue (Story 5.1) -------------------------------------------------------

## A deep copy of sequence `id` ({"mode", "lines"}), or {} for an unknown id.
## Logs nothing: CommsChannel reports an unknown id.
func sequence(id: StringName) -> Dictionary:
	var seq: Variant = _dialogue.get(id)
	return (seq as Dictionary).duplicate(true) if seq is Dictionary else {}


func has_sequence(id: StringName) -> bool:
	return _dialogue.has(id)


## True only for a known sequence whose mode is story.
func dialogue_is_story(id: StringName) -> bool:
	var seq: Variant = _dialogue.get(id)
	return seq is Dictionary and (seq as Dictionary).get("mode") == String(DialogueValidator.MODE_STORY)


## Level data for `id` (res://data/levels/level_<id>.json). See level_at().
func level(id: String) -> Dictionary:
	return level_at(LEVEL_PATH_FORMAT % id)


## Reads a level file. Returns {} (logged with the path) when the file is
## missing, does not parse, or has no (or an empty) `waves` array. Otherwise logs every
## LevelValidator problem and returns the data anyway: the WaveDirector skips
## the bad items at runtime.
func level_at(path: String) -> Dictionary:
	var result: Dictionary = _read_json_dict(path)
	if not (result.error as String).is_empty():
		return {}
	var data: Dictionary = result.data
	if not (data.get("waves") is Array) or (data.waves as Array).is_empty():
		Log.error("data", "%s has no waves array; level not loaded" % path)
		return {}
	var spacing: Vector2 = Vector2(num("waves.formation.spacing_px.x"), 0.0)
	var max_columns: int = Formation.max_columns(spacing, Playfield.SIZE.x)
	for problem: String in LevelValidator.validate(data, path, _known_enemy_types(), flags, _enemy_flags(), _rowless_types(), max_columns):
		Log.error("data", problem)
	return data


## EntityRegistry's enemy type ids, looked up at runtime: a static reference to
## EntityRegistry.ENEMIES would make Config -> EntityRegistry -> enemy scenes ->
## Config a cyclic compile dependency.
func _known_enemy_types() -> Array[StringName]:
	var out: Array[StringName] = []
	var registry: Node = get_node_or_null(^"/root/EntityRegistry")
	if registry != null:
		out.assign(registry.call(&"enemy_types"))
	else:
		Log.error("data", "EntityRegistry autoload not found; every enemy type is unknown")
	return out


## EntityRegistry's type -> gating flag map, looked up at runtime for the same
## reason as _known_enemy_types().
func _enemy_flags() -> Dictionary:
	var registry: Node = get_node_or_null(^"/root/EntityRegistry")
	if registry == null:
		Log.error("data", "EntityRegistry autoload not found; no enemy type is flag-gated")
		return {}
	var out: Variant = registry.call(&"enemy_flags")
	return out if out is Dictionary else {}


## EntityRegistry's rowless enemy types, looked up at runtime for the same
## reason as _known_enemy_types() (LevelValidator's Needle rule, DW-68).
func _rowless_types() -> Array[StringName]:
	var out: Array[StringName] = []
	var registry: Node = get_node_or_null(^"/root/EntityRegistry")
	if registry == null:
		Log.error("data", "EntityRegistry autoload not found; every enemy type takes a row")
		return out
	var raw: Variant = registry.call(&"rowless_types")
	if raw is Array:
		out.assign(raw as Array)
	return out


## Reads every *.json in `dir` (sorted by name) and returns the valid sequences
## (StringName id -> Dictionary). The story and combat line limits come from
## `tuning_data` (comms.story_line_max_chars, comms.combat_line_max_chars). A
## missing dir, or a file that is missing, fails to parse or isn't an object,
## is Log.error'ed, skipped and appended to `read_problems` (reload() rejects
## on those). Every validator problem is Log.error'ed and a sequence with any
## problem is left out. A duplicate id across files is Log.error'ed and the first one wins.
func _load_dialogue(dir: String, tuning_data: Dictionary, read_problems: Array[String]) -> Dictionary:
	var out: Dictionary = {}
	if not DirAccess.dir_exists_absolute(dir):
		var missing: String = "%s dialogue dir not found" % dir
		Log.error("data", missing)
		read_problems.append(missing)
		return out
	var max_chars: int = _story_max_chars(tuning_data)
	var combat_max_chars: int = _combat_max_chars(tuning_data)
	var files: Array[String] = []
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(DIALOGUE_EXTENSION):
			files.append(file)
	files.sort()
	## Sequence id -> the file that defined it first.
	var sources: Dictionary = {}
	for file: String in files:
		var path: String = dir.path_join(file)
		var result: Dictionary = _read_json_dict(path)
		if not (result.error as String).is_empty():
			read_problems.append(result.error)
			continue
		var data: Dictionary = result.data
		var sequences: Variant = data.get("sequences")
		if not (sequences is Dictionary):
			for problem: String in DialogueValidator.validate(data, path, max_chars, combat_max_chars):
				Log.error("data", problem)
			continue
		for key: Variant in sequences:
			var id: StringName = StringName(str(key))
			var seq: Variant = (sequences as Dictionary)[key]
			var problems: Array[String] = DialogueValidator.validate_sequence(str(key), seq, path, max_chars, combat_max_chars)
			for problem: String in problems:
				Log.error("data", problem)
			if not problems.is_empty():
				continue
			if out.has(id):
				Log.error("data", "%s sequences.%s: duplicate sequence id (first in %s); ignored" % [path, id, sources[id]])
				continue
			out[id] = seq
			sources[id] = path
	return out


## comms.story_line_max_chars from `tuning_data`, or -1 (no limit) when it is
## missing. That is an error only when tuning itself loaded (a failed tuning
## load is already reported and blocks every level).
func _story_max_chars(tuning_data: Dictionary) -> int:
	return _line_max_chars(tuning_data, STORY_MAX_CHARS_KEY, "story")


## comms.combat_line_max_chars from `tuning_data` (Story 5.2), or -1 (no
## limit) when it is missing; logged like the story key.
func _combat_max_chars(tuning_data: Dictionary) -> int:
	return _line_max_chars(tuning_data, COMBAT_MAX_CHARS_KEY, "combat")


func _line_max_chars(tuning_data: Dictionary, key: String, kind: String) -> int:
	var v: Variant = _lookup(tuning_data, key)
	if v is int or v is float:
		return int(v)
	if not tuning_data.is_empty():
		Log.error("data", "tuning.%s missing or not a number; %s line length not checked" % [key, kind])
	return -1


func _lookup(root: Dictionary, path: String) -> Variant:
	var node: Variant = root
	for part: String in path.split("."):
		if not (node is Dictionary and (node as Dictionary).has(part)):
			return null
		node = (node as Dictionary)[part]
	return node


func _report_missing(full_path: String, expected: String) -> void:
	var msg: String = "%s missing or not %s" % [full_path, expected]
	Log.error("data", msg)
	if assert_on_missing:
		assert(false, msg)


## Appends a problem for every key path in `reference` that is missing from
## `candidate` or holds a different kind of value. Recurses into Dictionaries;
## Array elements are not checked. An empty reference accepts anything.
func _check_shape(reference: Dictionary, candidate: Dictionary, prefix: String, problems: Array[String]) -> void:
	for key: Variant in reference:
		var path: String = "%s.%s" % [prefix, key]
		if not candidate.has(key):
			problems.append("%s missing" % path)
			continue
		var want: String = _kind(reference[key])
		var got: String = _kind(candidate[key])
		if want != got:
			problems.append("%s: expected %s, got %s" % [path, want, got])
		elif want == "Dictionary":
			_check_shape(reference[key], candidate[key], path, problems)


## Shape kind of a JSON value; int and float are both "number".
func _kind(v: Variant) -> String:
	if v is int or v is float:
		return "number"
	return type_string(typeof(v))


## Returns {"data": Dictionary, "error": String}; error is empty on success.
func _read_json_dict(path: String) -> Dictionary:
	var err: String = ""
	var data: Dictionary = {}
	if not FileAccess.file_exists(path):
		err = "%s not found" % path
	else:
		var text: String = FileAccess.get_file_as_string(path)
		var json: JSON = JSON.new()
		if json.parse(text) != OK:
			err = "%s parse error at line %d: %s" % [path, json.get_error_line(), json.get_error_message()]
		elif not (json.data is Dictionary):
			err = "%s root is not a JSON object" % path
		else:
			data = json.data
	if not err.is_empty():
		Log.error("data", err)
	return {"data": data, "error": err}


func _log_summary() -> void:
	if load_error.is_empty():
		Log.info("data", "Loaded %s (%d sections) and %s (%d flags)" % [_tuning_path, tuning.size(), _flags_path, flags.size()])
	else:
		Log.info("data", "Data loaded with errors: %s" % load_error)
	Log.info("data", "Loaded %d dialogue sequences from %s" % [_dialogue.size(), _dialogue_dir])
