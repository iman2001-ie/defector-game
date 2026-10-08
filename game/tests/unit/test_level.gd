extends GutTest
## level.tscn: the architecture tree, process modes, level_started with the
## JSON id, the gameplay mouse mode, wave 1 from level_dev.json and the
## LEVEL CLEAR banner.

const LEVEL_SCENE: PackedScene = preload("res://scenes/level/level.tscn")
const CONTAINERS: Array[String] = ["Asteroids", "Enemies", "Allies", "Pickups", "Projectiles", "Effects"]
const ROOT_CHILDREN: Array[String] = [
	"Background", "World", "Spawner", "WaveDirector", "ShakeCamera", "WorldEnvironment", "HUD", "Comms", "Overlay",
]

var _level: Node2D
var _started: Array[int] = []
var _cleared: Array[int] = []
var _lines: Array[String] = []


func _on_level_started(id: int) -> void:
	_started.append(id)


func _on_level_cleared(id: int) -> void:
	_cleared.append(id)


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func before_each() -> void:
	_started.clear()
	_cleared.clear()
	_lines.clear()
	Events.level_started.connect(_on_level_started)
	Events.level_cleared.connect(_on_level_cleared)


func after_each() -> void:
	Events.level_started.disconnect(_on_level_started)
	Events.level_cleared.disconnect(_on_level_cleared)
	Log.sink = Callable()
	_level = null
	Config.load_data()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	PauseArbiter.clear()


func _make_level(level_id: String = "dev") -> Node2D:
	_level = LEVEL_SCENE.instantiate() as Node2D
	_level.set("level_id", level_id)
	add_child_autofree(_level)
	return _level


func _counted() -> int:
	var n: int = 0
	for child: Node in _level.get_node("World/Enemies").get_children():
		if child.is_in_group(&"counted") and not child.is_queued_for_deletion():
			n += 1
	return n


func test_tree() -> void:
	_make_level()
	var names: Array[String] = []
	for child: Node in _level.get_children():
		names.append(String(child.name))
	assert_eq(names, ROOT_CHILDREN, "architecture level tree")
	var world: Node = _level.get_node("World")
	for container: String in CONTAINERS:
		assert_true(world.get_node_or_null(container) is Node2D, "World/%s" % container)
	var player: Player = world.get_node_or_null("Player") as Player
	assert_not_null(player, "World/Player")
	if player != null:
		assert_eq(player.position, Vector2(960, 900))
	var spawner: Spawner = _level.get_node("Spawner") as Spawner
	assert_eq(spawner.world, world, "Spawner.world is World")
	var director: WaveDirector = _level.get_node("WaveDirector") as WaveDirector
	assert_eq(director.spawner, spawner, "WaveDirector uses the Spawner")
	assert_true(director.is_in_group(&"wave_director"))
	assert_eq((_level.get_node("ShakeCamera") as Node2D).position, Vector2(960, 540))
	assert_eq((_level.get_node("HUD") as CanvasLayer).layer, 10)
	assert_eq((_level.get_node("Comms") as CanvasLayer).layer, 20)
	assert_eq((_level.get_node("Overlay") as CanvasLayer).layer, 30)
	assert_true(_level.get_node_or_null("HUD/LevelClearBanner") is LevelClearBanner)
	assert_true(_level.get_node_or_null("Overlay/DebugTools") is DebugTools)
	var env: Environment = (_level.get_node("WorldEnvironment") as WorldEnvironment).environment
	assert_true(env.glow_enabled, "glow on")
	assert_almost_eq(env.glow_intensity, Config.num("render.glow.intensity"), 0.0001, "glow from data")


func test_process_modes() -> void:
	_make_level()
	assert_eq(_level.get_node("World").process_mode, Node.PROCESS_MODE_INHERIT, "World pausable")
	assert_eq(_level.get_node("WaveDirector").process_mode, Node.PROCESS_MODE_INHERIT, "WaveDirector pausable")
	assert_eq(_level.get_node("HUD").process_mode, Node.PROCESS_MODE_INHERIT, "HUD pausable")
	assert_eq(_level.get_node("ShakeCamera").process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(_level.get_node("Overlay/DebugTools").process_mode, Node.PROCESS_MODE_ALWAYS)


func test_level_started_with_the_json_id_and_wave_1() -> void:
	Log.sink = _capture
	_make_level()
	Log.sink = Callable()
	assert_eq(_started, [0] as Array[int], "level_started(0) from level_dev.json")
	var director: WaveDirector = _level.get_node("WaveDirector") as WaveDirector
	assert_eq(director.wave_number(), 1, "wave 1 started")
	assert_eq(director.wave_count(), 3)
	assert_eq(director.level_id(), 0)
	assert_eq(_counted(), 8, "8 Wasps")
	var info: Array[String] = []
	for line: String in _lines:
		if line.begins_with("[INFO][scene] Level 0"):
			info.append(line)
	assert_eq(info.size(), 1, "INFO level start")


func test_gameplay_mouse_mode() -> void:
	_make_level()
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_CONFINED_HIDDEN)


func test_banner_shows_on_level_cleared() -> void:
	_make_level()
	var banner: Label = _level.get_node("HUD/LevelClearBanner") as Label
	assert_false(banner.visible, "hidden at start")
	assert_eq(banner.text, "LEVEL CLEAR")
	Events.level_cleared.emit(0)
	assert_true(banner.visible, "shown on level_cleared")


func test_missing_level_file_starts_nothing() -> void:
	_make_level("does_not_exist")
	assert_push_error("not found")
	assert_push_error("could not be loaded")
	assert_eq(_started.size(), 0, "no level_started")
	assert_eq(_counted(), 0, "nothing spawned")


## Acceptance: clearing all three waves of level_dev (via F3) clears the level.
func test_clearing_every_dev_wave_clears_the_level() -> void:
	(Config.tuning["waves"] as Dictionary)["gap_s"] = 0.05
	Log.sink = _capture
	_make_level()
	var director: WaveDirector = _level.get_node("WaveDirector") as WaveDirector
	var banner: Label = _level.get_node("HUD/LevelClearBanner") as Label
	for wave: int in 3:
		assert_eq(director.wave_number(), wave + 1, "on wave %d" % (wave + 1))
		director.debug_resolve_wave()
		# Longest chain in level_dev is 1.0 s, plus the gap.
		var waited: float = 0.0
		while director.wave_number() == wave + 1 and not director.is_level_cleared() and waited < 3.0:
			await wait_seconds(0.1)
			waited += 0.1
		assert_true(director.wave_number() > wave + 1 or director.is_level_cleared(),
			"wave %d advanced within 3 s" % (wave + 1))
	Log.sink = Callable()
	assert_eq(_cleared, [0] as Array[int], "level_cleared(0)")
	assert_true(banner.visible, "LEVEL CLEAR shown")
	var cleared_lines: int = 0
	for line: String in _lines:
		if line == "[INFO][wave] Level 0 cleared":
			cleared_lines += 1
	assert_eq(cleared_lines, 1, "INFO level clear")


# --- Debug-arg gates ----------------------------------------------------------

const LEVEL_SCRIPT: GDScript = preload("res://scenes/level/level.gd")


func test_stress_redirect_only_in_debug_builds_with_stress_or_bench() -> void:
	var stress: Dictionary = DebugArgs.parse(PackedStringArray(["--stress"]))
	var bench: Dictionary = DebugArgs.parse(PackedStringArray(["--bench=5"]))
	var none: Dictionary = DebugArgs.parse(PackedStringArray())
	assert_true(LEVEL_SCRIPT.should_redirect_to_stress(true, stress), "debug --stress")
	assert_true(LEVEL_SCRIPT.should_redirect_to_stress(true, bench), "debug --bench=5")
	assert_false(LEVEL_SCRIPT.should_redirect_to_stress(true, none), "debug, no args")
	assert_false(LEVEL_SCRIPT.should_redirect_to_stress(false, stress), "release --stress")
	assert_false(LEVEL_SCRIPT.should_redirect_to_stress(false, bench), "release --bench=5")
	assert_false(LEVEL_SCRIPT.should_redirect_to_stress(false, none), "release, no args")


func test_prewarm_skipped_only_by_no_prewarm_in_debug_builds() -> void:
	var on: Dictionary = DebugArgs.parse(PackedStringArray())
	var off: Dictionary = DebugArgs.parse(PackedStringArray(["--no-prewarm"]))
	assert_true(LEVEL_SCRIPT.should_prewarm(true, on), "debug build, no flag: pre-warm")
	assert_false(LEVEL_SCRIPT.should_prewarm(true, off), "debug build, --no-prewarm: skip")
	assert_true(LEVEL_SCRIPT.should_prewarm(false, off), "release build ignores --no-prewarm")
