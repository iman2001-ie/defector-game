extends Node
## Loads data/tuning.json and data/flags.json and serves typed, dot-path lookups.
##
## Gameplay code never indexes `tuning` directly: use num / int_ / flag / section.
## A missing key or wrong type logs an error naming the full key path, asserts
## (when assert_on_missing is true) and returns a neutral fallback.

const DEFAULT_TUNING_PATH: String = "res://data/tuning.json"
const DEFAULT_FLAGS_PATH: String = "res://data/flags.json"

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


## Reloads the files most recently passed to load_data().
func reload() -> void:
	load_data(_tuning_path, _flags_path)
	_log_summary()


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
