extends GutTest
## Groups (DW-61): the scene-tree group names as constants, and no production
## script spells a group literal or keeps its own *_GROUP constant. Tests keep
## their literals on purpose (independent checks), so tests/ and addons/ are
## not scanned.

const SKIPPED_DIRS: Array[String] = ["res://addons", "res://tests"]


func test_constant_values() -> void:
	assert_eq(Groups.PLAYER, &"player")
	assert_eq(Groups.ENEMIES, &"enemies")
	assert_eq(Groups.ASTEROIDS, &"asteroids")
	assert_eq(Groups.PROJECTILES, &"projectiles")
	assert_eq(Groups.PICKUPS, &"pickups")
	assert_eq(Groups.COUNTED, &"counted")
	assert_eq(Groups.WAVE_DIRECTOR, &"wave_director")
	assert_eq(Groups.CONVOY, &"convoy")
	assert_eq(Groups.ALLIES, &"allies")
	assert_eq(Groups.BOSS, &"boss")


func test_constants_are_string_names() -> void:
	for value: Variant in [
		Groups.PLAYER, Groups.ENEMIES, Groups.ASTEROIDS, Groups.PROJECTILES,
		Groups.PICKUPS, Groups.COUNTED, Groups.WAVE_DIRECTOR, Groups.CONVOY,
		Groups.ALLIES, Groups.BOSS,
	]:
		assert_eq(typeof(value), TYPE_STRING_NAME)


func test_no_production_script_spells_a_group_literal() -> void:
	var const_group: RegEx = RegEx.create_from_string("const\\s+\\w+_GROUP\\b")
	var offenders: Array[String] = []
	var files: Array[String] = []
	_collect("res://", files)
	assert_gt(files.size(), 0, "found production scripts")
	for path: String in files:
		var text: String = FileAccess.get_file_as_string(path)
		if text.contains("group(&\"") or text.contains("in_group(&\""):
			offenders.append("%s: group literal" % path)
		if const_group.search(text) != null:
			offenders.append("%s: *_GROUP constant" % path)
	assert_eq(offenders, [] as Array[String], "use Groups.* instead")


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	assert_not_null(dir, "can open %s" % dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		if sub.begins_with("."):
			continue
		var sub_path: String = dir_path.path_join(sub)
		if sub_path in SKIPPED_DIRS:
			continue
		_collect(sub_path, out)
	for file: String in dir.get_files():
		if file.get_extension() == "gd":
			out.append(dir_path.path_join(file))
