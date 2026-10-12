extends GutTest
## Story 7.3: the Flagship on the real level.tscn with the `dev_boss` level.
## F6 pressed through DebugTools jumps from wave 1 to the boss wave: the
## Flagship spawns through the Spawner with its cover asteroids, the BossBar
## shows (the WaveBar fades out), and nothing logs an error. The player is
## debug_invincible and the router's scene change is a recorder. Feel,
## readability, difficulty and cover usefulness are operator checks, not
## claimed here.

const LEVEL_SCENE: PackedScene = preload("res://scenes/level/level.tscn")
const LEVEL_ID: String = "dev_boss"

var _level: Node2D
var _lines: Array[String] = []
var _scene_calls: Array[String] = []


func before_each() -> void:
	_lines.clear()
	_scene_calls.clear()
	_level = null
	_reset_game_state()
	SceneRouter.change_scene = _record_scene
	Log.sink = _capture


func after_each() -> void:
	Log.sink = Callable()
	_level = null
	SceneRouter.change_scene = SceneRouter.default_change_scene()
	_reset_game_state()
	Config.load_data()
	Feedback.reset()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	PauseArbiter.clear()


func _reset_game_state() -> void:
	GameState.energy = 0
	GameState.current_level_id = ""
	GameState.is_retry = false
	GameState.shown_hints.clear()


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _record_scene(path: String) -> Error:
	_scene_calls.append(path)
	return OK


func _lines_containing(text: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.contains(text):
			out.append(line)
	return out


func _make_level() -> Node2D:
	(Config.tuning["waves"] as Dictionary)["gap_s"] = 0.05
	_level = LEVEL_SCENE.instantiate() as Node2D
	_level.set("level_id", LEVEL_ID)
	_level.user_args = PackedStringArray()
	var player: Player = _level.get_node("World/Player") as Player
	player.debug_invincible = true
	player.warp_mouse = func(_at: Vector2) -> void: pass
	add_child_autofree(_level)
	return _level


func _director() -> WaveDirector:
	return _level.get_node("WaveDirector") as WaveDirector


func _flagships() -> Array[Flagship]:
	var out: Array[Flagship] = []
	for child: Node in _level.get_node("World/Enemies").get_children():
		var boss: Flagship = child as Flagship
		if boss != null and not boss.is_queued_for_deletion():
			out.append(boss)
	return out


func _press(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	(_level.get_node("Overlay/DebugTools") as DebugTools)._unhandled_input(event)


func test_hud_has_a_hidden_boss_bar_after_the_wave_bar() -> void:
	_make_level()
	var hud: Node = _level.get_node("HUD")
	var bar: BossBar = hud.get_node_or_null("BossBar") as BossBar
	assert_not_null(bar, "HUD/BossBar is a BossBar")
	if bar == null:
		return
	assert_eq(bar.get_index(), hud.get_node("WaveBar").get_index() + 1, "right after WaveBar")
	assert_eq(bar.process_mode, Node.PROCESS_MODE_PAUSABLE, "freezes with the game")
	assert_eq(bar.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_not_null(bar.theme, "has the shared theme")
	if bar.theme != null:
		assert_eq(bar.theme.resource_path, "res://ui/theme/defector_theme.tres")
	assert_false(bar.visible, "hidden before the boss")
	assert_eq(bar.get_rect(), Rect2(680, 40, 560, 20))


func test_f6_jumps_to_the_flagship_and_shows_the_boss_bar() -> void:
	_make_level()
	var director: WaveDirector = _director()
	assert_eq(director.wave_number(), 1, "wave 1 runs first")
	assert_eq(_flagships().size(), 0, "no Flagship yet")
	var boss_bar: BossBar = _level.get_node("HUD/BossBar") as BossBar
	var wave_bar: WaveBar = _level.get_node("HUD/WaveBar") as WaveBar
	assert_false(boss_bar.visible)
	_press(&"debug_skip_to_boss")
	assert_eq(_lines_containing("[INFO][debug] F6: jumping to boss wave 2").size(), 1, "F6 through DebugTools")
	assert_eq(director.wave_number(), 2, "the boss wave")
	assert_eq(director.total_count(), 1)
	var bosses: Array[Flagship] = _flagships()
	assert_eq(bosses.size(), 1, "the Flagship is present")
	var medium: int = 0
	for child: Node in _level.get_node("World/Asteroids").get_children():
		if child is Asteroid and (child as Asteroid).size == &"medium":
			medium += 1
	assert_eq(medium, 2, "the cover asteroids")
	assert_true(boss_bar.visible, "the boss bar shows")
	assert_eq(boss_bar.max_hp(), 300)
	assert_eq(boss_bar.current(), 300)
	await wait_seconds(Config.num("hud.boss_bar.fade_s") + 0.2)
	assert_almost_eq(boss_bar.modulate.a, 1.0, 0.001, "the boss bar faded in")
	assert_almost_eq(wave_bar.modulate.a, 0.0, 0.001, "the wave bar faded out")
	assert_eq(_flagships().size(), 1, "still one Flagship")
	if bosses.size() == 1:
		assert_eq(bosses[0].phase(), Flagship.Phase.ARRIVING, "arriving")
		assert_lt(bosses[0].global_position.y, Config.num("boss.hull.station_y"), "still flying in")
		assert_gt(bosses[0].global_position.y, Config.num("boss.hull.arrive_from_y"), "flying in under physics")
	assert_eq(_lines_containing("[ERROR]"), [] as Array[String], "no error")
	assert_eq(_scene_calls, [] as Array[String], "no scene change")
