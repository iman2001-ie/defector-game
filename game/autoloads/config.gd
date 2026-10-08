extends Node
## Loads data/tuning.json and data/flags.json and serves typed, dot-path lookups.
##
## Gameplay code never indexes `tuning` directly: use num / int_ / flag / section.
## A missing key or wrong type logs an error naming the full key path, asserts
## (when assert_on_missing is true) and returns a neutral fallback.

const DEFAULT_TUNING_PATH: String = "res://data/tuning.json"
const DEFAULT_FLAGS_PATH: String = "res://data/flags.json"
## Level files are keyed by a string id: level_dev.json, later level_1.json.
const LEVEL_PATH_FORMAT: String = "res://data/levels/level_%s.json"

var tuning: Dictionary = {}
var flags: Dictionary = {}
## Empty when tuning loaded fine; otherwise a human-readable reason for display.
var load_error: String = ""
## Tests set this to false: a failed assert would abort the test before the fallback returns.
var assert_on_missing: bool = true

var _tuning_path: String = DEFAULT_TUNING_PATH
var _flags_path: String = DEFAULT_FLAGS_PATH


func _ready() -> void:
	load_data()
	_log_summary()


## Loads both files. A tuning failure sets load_error and empties tuning; a flags
## failure empties flags and is logged, but does not touch load_error.
func load_data(tuning_path: String = DEFAULT_TUNING_PATH, flags_path: String = DEFAULT_FLAGS_PATH) -> void:
	_tuning_path = tuning_path
	_flags_path = flags_path
	load_error = ""

	var tuning_result: Dictionary = _read_json_dict(tuning_path)
	tuning = tuning_result.data
	if not (tuning_result.error as String).is_empty():
		load_error = tuning_result.error

	var flags_result: Dictionary = _read_json_dict(flags_path)
	flags = flags_result.data


## Re-reads the files most recently passed to load_data() and validates them
## against the shape of the data loaded now: every current key path must still
## exist with the same kind (extra keys are fine). On success commits both,
## clears load_error and returns true. On any failure logs every problem, leaves
## tuning, flags and load_error untouched and returns false.
func reload() -> bool:
	var problems: Array[String] = []
	var tuning_result: Dictionary = _read_json_dict(_tuning_path)
	var flags_result: Dictionary = _read_json_dict(_flags_path)
	var new_tuning: Dictionary = tuning_result.data
	var new_flags: Dictionary = flags_result.data
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
	for problem: String in LevelValidator.validate(data, path, _known_enemy_types()):
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
