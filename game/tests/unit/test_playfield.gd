extends GutTest
## Playfield: the single source of the logical playfield size.

const FORBIDDEN: String = "display/window/size/viewport_"
const SCANNED_DIRS: Array[String] = [
	"res://autoloads", "res://core", "res://entities", "res://scenes", "res://systems", "res://ui",
]


func test_size_matches_project_viewport() -> void:
	var expected: Vector2 = Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	assert_eq(Playfield.SIZE, expected)
	assert_eq(Playfield.SIZE, Vector2(1920, 1080))


func test_rect_is_size_at_origin() -> void:
	assert_eq(Playfield.RECT, Rect2(Vector2.ZERO, Playfield.SIZE))


func test_no_gameplay_script_reads_viewport_size() -> void:
	var offenders: Array[String] = []
	for dir: String in SCANNED_DIRS:
		_scan(dir, offenders)
	assert_eq(offenders, [] as Array[String], "read Playfield instead of the viewport settings")


func _scan(dir_path: String, offenders: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	assert_not_null(dir, "can open %s" % dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_scan(dir_path.path_join(sub), offenders)
	for file: String in dir.get_files():
		if file.get_extension() != "gd":
			continue
		var path: String = dir_path.path_join(file)
		if FileAccess.get_file_as_string(path).contains(FORBIDDEN):
			offenders.append(path)
