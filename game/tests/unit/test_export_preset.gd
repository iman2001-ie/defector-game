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
