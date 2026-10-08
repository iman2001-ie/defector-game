extends GutTest
## SaveManager (Story 4.2): the [progress] ConfigFile round trip, the defaults
## for a missing file (INFO) and for a corrupt file, a missing or unknown
## save_version or bad values (WARN), and no file I/O at construction. Every
## test uses its own user://test_*.cfg path, never the real save.

const SAVE_MANAGER_SCRIPT: GDScript = preload("res://autoloads/save_manager.gd")
const TEST_SAVE: String = "user://test_save_manager.cfg"
## A path whose folder doesn't exist, so the write fails.
const UNWRITABLE_SAVE: String = "user://test_save_manager_missing_dir/save.cfg"

var _lines: Array[String] = []


func before_each() -> void:
	_lines.clear()
	SaveManager.save_path = TEST_SAVE
	_delete(TEST_SAVE)
	GameState.highest_unlocked_level = 1
	GameState.all_levels_unlocked = false
	Log.sink = _capture


func after_each() -> void:
	Log.sink = Callable()
	_delete(TEST_SAVE)
	SaveManager.save_path = SaveManager.DEFAULT_SAVE_PATH
	GameState.energy = 0
	GameState.highest_unlocked_level = 1
	GameState.all_levels_unlocked = false


func _delete(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _lines_starting(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.begins_with(prefix):
			out.append(line)
	return out


func _write_raw(text: String) -> void:
	var file: FileAccess = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## Writes [progress] with the given values; a null value leaves the key out.
func _write_progress(version: Variant, highest: Variant, energy: Variant) -> void:
	var file: ConfigFile = ConfigFile.new()
	if version != null:
		file.set_value("progress", "save_version", version)
	if highest != null:
		file.set_value("progress", "highest_unlocked_level", highest)
	if energy != null:
		file.set_value("progress", "energy", energy)
	assert_eq(file.save(TEST_SAVE), OK, "fixture written")


func _assert_defaults(progress: Dictionary, what: String) -> void:
	assert_eq(progress, {"highest_unlocked_level": 1, "energy": 0}, what)


func _assert_one_warn(what: String) -> void:
	assert_eq(_lines_starting("[WARN][save]").size(), 1, what + ": one WARN save line")


# --- Constants and construction -------------------------------------------------

func test_constants() -> void:
	assert_eq(SaveManager.SAVE_VERSION, 1)
	assert_eq(SaveManager.DEFAULT_SAVE_PATH, "user://save.cfg")


func test_construction_does_no_file_io() -> void:
	var manager: Node = SAVE_MANAGER_SCRIPT.new() as Node
	assert_eq(manager.get(&"save_path"), "user://save.cfg", "default path")
	manager.set(&"save_path", TEST_SAVE)
	add_child_autofree(manager)
	assert_false(FileAccess.file_exists(TEST_SAVE), "nothing written by _ready")
	assert_eq(_lines_starting("[INFO][save]").size() + _lines_starting("[WARN][save]").size(), 0, "nothing read by _ready")


# --- Load -------------------------------------------------------------------------

func test_missing_file_gives_defaults_with_info() -> void:
	var progress: Dictionary = SaveManager.load_progress()
	_assert_defaults(progress, "defaults")
	assert_eq(_lines_starting("[INFO][save]").size(), 1, "INFO line")
	assert_eq(_lines_starting("[WARN][save]").size(), 0, "no WARN")
	assert_false(FileAccess.file_exists(TEST_SAVE), "loading creates no file")


func test_round_trip() -> void:
	GameState.highest_unlocked_level = 2
	GameState.energy = 40
	assert_true(SaveManager.save(), "save() returns true")
	assert_eq(_lines_starting("[INFO][save] Saved").size(), 1, "INFO save line")
	var raw: ConfigFile = ConfigFile.new()
	assert_eq(raw.load(TEST_SAVE), OK, "raw ConfigFile reads it")
	assert_eq(raw.get_value("progress", "save_version"), 1)
	assert_eq(raw.get_value("progress", "highest_unlocked_level"), 2)
	assert_eq(raw.get_value("progress", "energy"), 40)
	assert_typeof(raw.get_value("progress", "energy"), TYPE_INT)
	GameState.highest_unlocked_level = 1
	GameState.energy = 0
	assert_eq(SaveManager.load_progress(), {"highest_unlocked_level": 2, "energy": 40})
	assert_eq(_lines_starting("[WARN][save]").size(), 0, "no WARN")


func test_corrupt_file_gives_defaults_with_warn() -> void:
	_write_raw("this is not a config file\n[progress\nenergy = = =\n{{{")
	_assert_defaults(SaveManager.load_progress(), "corrupt")
	_assert_one_warn("corrupt")
	assert_engine_error("ConfigFile parse error")


func test_unknown_version_gives_defaults_with_warn() -> void:
	_write_progress(2, 2, 40)
	_assert_defaults(SaveManager.load_progress(), "save_version 2")
	_assert_one_warn("save_version 2")


func test_missing_version_gives_defaults_with_warn() -> void:
	_write_progress(null, 2, 40)
	_assert_defaults(SaveManager.load_progress(), "no save_version")
	_assert_one_warn("no save_version")


func test_non_int_version_gives_defaults_with_warn() -> void:
	_write_progress("1", 2, 40)
	_assert_defaults(SaveManager.load_progress(), "string save_version")
	_assert_one_warn("string save_version")


func test_bad_values_give_defaults_with_warn() -> void:
	var cases: Array[Array] = [
		[0, 40, "highest 0"],
		[2, -5, "energy -5"],
		["2", 40, "string highest"],
		[2, "forty", "string energy"],
		[2.0, 40, "float highest"],
		[null, 40, "missing highest"],
		[2, null, "missing energy"],
	]
	for row: Array in cases:
		_lines.clear()
		_delete(TEST_SAVE)
		_write_progress(1, row[0], row[1])
		_assert_defaults(SaveManager.load_progress(), str(row[2]))
		_assert_one_warn(str(row[2]))


# --- Save -------------------------------------------------------------------------

func test_save_failure_logs_an_error_and_returns_false() -> void:
	SaveManager.save_path = UNWRITABLE_SAVE
	assert_false(SaveManager.save(), "save() returns false")
	assert_eq(_lines_starting("[ERROR][save]").size(), 1, "ERROR save line")
	assert_push_error("[ERROR][save]")
	assert_false(FileAccess.file_exists(UNWRITABLE_SAVE))
