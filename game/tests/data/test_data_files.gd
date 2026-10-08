extends GutTest
## Data files: every level_*.json in res://data/levels/ passes LevelValidator.

const LEVELS_DIR: String = "res://data/levels/"


func _level_files() -> Array[String]:
	var out: Array[String] = []
	for file: String in DirAccess.get_files_at(LEVELS_DIR):
		if file.begins_with("level_") and file.ends_with(".json"):
			out.append(LEVELS_DIR + file)
	return out


func test_level_files_exist() -> void:
	assert_true(_level_files().has(LEVELS_DIR + "level_dev.json"), "level_dev.json present")


func test_every_level_file_is_valid() -> void:
	var known: Array[StringName] = EntityRegistry.enemy_types()
	for path: String in _level_files():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_true(parsed is Dictionary, "%s parses to an object" % path)
		if not (parsed is Dictionary):
			continue
		var problems: Array[String] = LevelValidator.validate(parsed as Dictionary, path, known)
		assert_eq(problems, [] as Array[String], "%s has no problems" % path)
