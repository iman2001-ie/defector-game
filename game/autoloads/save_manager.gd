extends Node
## The only code that touches user:// (architecture D9 and boundary 4; Story 4.2).
##
## The save is a ConfigFile at save_path (user://save.cfg, which the custom user
## dir puts in %APPDATA%\DEFECTOR\) with one section:
##
##   [progress]
##   save_version=1
##   highest_unlocked_level=2
##   energy=40
##
## - load_progress(): reads it. A missing file gives the defaults (INFO); a
##   corrupt file, a missing or unknown save_version, or a missing, non-int or
##   out-of-range value gives the defaults with a WARN. Never crashes and never
##   calls a Config getter (it also runs while Config.load_error is set).
## - save(): writes GameState.highest_unlocked_level and GameState.energy. Only
##   SceneRouter.complete_level() calls it (saving happens only on a level clear).
##
## No file I/O happens in _ready. Tests point save_path at their own
## user://test_*.cfg file and restore DEFAULT_SAVE_PATH afterwards.

const SAVE_VERSION: int = 1
const DEFAULT_SAVE_PATH: String = "user://save.cfg"
const SECTION: String = "progress"
const KEY_VERSION: String = "save_version"
const KEY_HIGHEST: String = "highest_unlocked_level"
const KEY_ENERGY: String = "energy"
const DEFAULT_HIGHEST: int = 1
const DEFAULT_ENERGY: int = 0

## Where the save lives. Tests inject a test path.
var save_path: String = DEFAULT_SAVE_PATH


## The defaults: level 1 unlocked, no energy.
func defaults() -> Dictionary:
	return {KEY_HIGHEST: DEFAULT_HIGHEST, KEY_ENERGY: DEFAULT_ENERGY}


## Reads the save: {"highest_unlocked_level": int, "energy": int}. Any problem
## gives the defaults (missing file: INFO; anything else: WARN).
func load_progress() -> Dictionary:
	var file: ConfigFile = ConfigFile.new()
	var err: Error = file.load(save_path)
	if err == ERR_FILE_NOT_FOUND:
		Log.info("save", "No save at %s; using defaults (level %d, energy %d)" % [save_path, DEFAULT_HIGHEST, DEFAULT_ENERGY])
		return defaults()
	if err != OK:
		Log.warn("save", "Save %s could not be read (%s); using defaults" % [save_path, error_string(err)])
		return defaults()
	var version: Variant = _value(file, KEY_VERSION)
	if not (version is int):
		Log.warn("save", "Save %s has no valid save_version; using defaults" % save_path)
		return defaults()
	if int(version) != SAVE_VERSION:
		Log.warn("save", "Unknown save_version %d in %s; using defaults" % [int(version), save_path])
		return defaults()
	var highest: Variant = _value(file, KEY_HIGHEST)
	var energy: Variant = _value(file, KEY_ENERGY)
	if not (highest is int) or not (energy is int) or int(highest) < 1 or int(energy) < 0:
		Log.warn("save", "Save %s has bad values (highest_unlocked_level=%s, energy=%s); using defaults" % [save_path, var_to_str(highest), var_to_str(energy)])
		return defaults()
	Log.info("save", "Save loaded from %s (level %d unlocked, energy %d)" % [save_path, int(highest), int(energy)])
	return {KEY_HIGHEST: int(highest), KEY_ENERGY: int(energy)}


## Writes save_version, GameState.highest_unlocked_level and GameState.energy to
## save_path. Returns false (and logs an ERROR) when the write fails.
func save() -> bool:
	var file: ConfigFile = ConfigFile.new()
	file.set_value(SECTION, KEY_VERSION, SAVE_VERSION)
	file.set_value(SECTION, KEY_HIGHEST, GameState.highest_unlocked_level)
	file.set_value(SECTION, KEY_ENERGY, GameState.energy)
	var err: Error = file.save(save_path)
	if err != OK:
		Log.error("save", "Save to %s failed (%s)" % [save_path, error_string(err)])
		return false
	Log.info("save", "Saved to %s (level %d unlocked, energy %d)" % [save_path, GameState.highest_unlocked_level, GameState.energy])
	return true


## The [progress] value of `key`, or null when it is missing (get_value with a
## null default would raise an engine error).
func _value(file: ConfigFile, key: String) -> Variant:
	return file.get_value(SECTION, key) if file.has_section_key(SECTION, key) else null
