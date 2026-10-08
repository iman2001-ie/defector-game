extends GutTest
## Pins the committed Windows Desktop export preset (relative paths only).

const PRESETS_PATH: String = "res://export_presets.cfg"

var _cfg: ConfigFile


func before_each() -> void:
	_cfg = ConfigFile.new()
	assert_eq(_cfg.load(PRESETS_PATH), OK, "export_presets.cfg parses")


func test_preset_header() -> void:
	assert_eq(_cfg.get_value("preset.0", "name", ""), "Windows Desktop")
	assert_eq(_cfg.get_value("preset.0", "platform", ""), "Windows Desktop")
	assert_eq(_cfg.get_value("preset.0", "runnable", false), true)
	assert_eq(_cfg.get_value("preset.0", "export_filter", ""), "all_resources")
	assert_eq(_cfg.get_value("preset.0", "include_filter", ""), "data/*.json")
	assert_eq(_cfg.get_value("preset.0", "exclude_filter", ""), "addons/gut/*, tests/*")
	assert_eq(_cfg.get_value("preset.0", "export_path", ""), "export/windows/DEFECTOR.exe")


func test_preset_options() -> void:
	assert_eq(_cfg.get_value("preset.0.options", "binary_format/embed_pck", false), true)
	assert_eq(_cfg.get_value("preset.0.options", "binary_format/architecture", ""), "x86_64")
	assert_eq(_cfg.get_value("preset.0.options", "application/product_name", ""), "DEFECTOR")
	assert_eq(_cfg.get_value("preset.0.options", "codesign/enable", true), false)
	assert_eq(_cfg.get_value("preset.0.options", "application/icon", ""), "", "no icon until Epic 8")


func test_no_absolute_paths() -> void:
	var text: String = FileAccess.get_file_as_string(PRESETS_PATH)
	var regex: RegEx = RegEx.create_from_string("(?i)(?<![a-z])[a-z]:[\\\\/]|users[\\\\/]")
	assert_null(regex.search(text), "no drive letters or user folders")


func test_level_files_match_the_include_filter() -> void:
	var filters: PackedStringArray = str(_cfg.get_value("preset.0", "include_filter", "")).split(",", false)
	var files: PackedStringArray = DirAccess.get_files_at("res://data/levels/")
	assert_gt(files.size(), 0, "level files exist")
	for file: String in files:
		if not file.ends_with(".json"):
			continue
		var path: String = "data/levels/" + file
		var matched: bool = false
		for filter: String in filters:
			if path.matchn(filter.strip_edges()):
				matched = true
		assert_true(matched, "%s is exported by the include filter" % path)
