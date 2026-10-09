extends GutTest
## level.tscn: the architecture tree, process modes, level_started with the
## JSON id, the gameplay mouse mode, wave 1 from level_dev.json and the
## LEVEL CLEAR banner, the hearts display, energy bar and hit vignette in the HUD, the
## retry prompt and pause menu in the Overlay, the level id resolution and the death -> retry
## reload (Story 3.2), and the level_cleared -> SceneRouter.complete_level
## wiring (Story 4.2; the save is a test file). Long wave runs make the player
## debug_invincible so a death can't pause the tree mid-test.

const LEVEL_SCENE: PackedScene = preload("res://scenes/level/level.tscn")
const CONTAINERS: Array[String] = ["Asteroids", "Enemies", "Allies", "Pickups", "Projectiles", "Effects"]
const ROOT_CHILDREN: Array[String] = [
	"Background", "World", "Spawner", "WaveDirector", "ShakeCamera", "WorldEnvironment", "HUD", "Comms", "Overlay",
]
const TEST_SAVE: String = "user://test_level_save.cfg"

var _level: Node2D
var _started: Array[int] = []
var _cleared: Array[int] = []
var _lines: Array[String] = []
var _scene_calls: Array[String] = []


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
	_scene_calls.clear()
	SaveManager.save_path = TEST_SAVE
	_delete_save()
	_reset_game_state()
	Events.level_started.connect(_on_level_started)
	Events.level_cleared.connect(_on_level_cleared)


func after_each() -> void:
	Events.level_started.disconnect(_on_level_started)
	Events.level_cleared.disconnect(_on_level_cleared)
	Log.sink = Callable()
	_level = null
	SceneRouter.change_scene = SceneRouter.default_change_scene()
	_delete_save()
	SaveManager.save_path = SaveManager.DEFAULT_SAVE_PATH
	_reset_game_state()
	Config.load_data()
	Feedback.reset()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	PauseArbiter.clear()


func _reset_game_state() -> void:
	GameState.energy = 0
	GameState.current_level_id = ""
	GameState.is_retry = false
	GameState.highest_unlocked_level = 1
	GameState.all_levels_unlocked = false


func _delete_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)


func _record_scene(path: String) -> Error:
	_scene_calls.append(path)
	return OK


## Long wave runs: enemies may reach the static ship; a death would pause the tree.
func _make_player_invincible() -> void:
	(_level.get_node("World/Player") as Player).debug_invincible = true


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
	var prompt: RetryPrompt = _level.get_node_or_null("Overlay/RetryPrompt") as RetryPrompt
	assert_not_null(prompt, "Overlay/RetryPrompt is a RetryPrompt")
	if prompt != null:
		assert_lt(prompt.get_index(), _level.get_node("Overlay/DebugTools").get_index(), "the debug overlay draws on top")
		assert_false(prompt.visible, "hidden at start")
	var menu: PauseMenu = _level.get_node_or_null("Overlay/PauseMenu") as PauseMenu
	assert_not_null(menu, "Overlay/PauseMenu is a PauseMenu")
	if menu != null:
		assert_gt(menu.get_index(), _level.get_node("Overlay/RetryPrompt").get_index(), "after the retry prompt")
		assert_lt(menu.get_index(), _level.get_node("Overlay/DebugTools").get_index(), "the debug overlay draws on top")
		assert_false(menu.visible, "hidden at start")
	var env: Environment = (_level.get_node("WorldEnvironment") as WorldEnvironment).environment
	assert_true(env.glow_enabled, "glow on")
	assert_almost_eq(env.glow_intensity, Config.num("render.glow.intensity"), 0.0001, "glow from data")


func test_wasp_dive_clock_under_the_wave_director() -> void:
	_make_level()
	var clock: WaspDiveClock = _level.get_node_or_null("WaveDirector/WaspDiveClock") as WaspDiveClock
	assert_not_null(clock, "WaveDirector/WaspDiveClock is a WaspDiveClock")
	if clock != null:
		assert_eq(clock.process_mode, Node.PROCESS_MODE_INHERIT, "freezes with the game")


func test_player_is_in_group_player() -> void:
	_make_level()
	var player: Node = _level.get_node("World/Player")
	assert_true(player.is_in_group(&"player"))
	assert_eq(get_tree().get_first_node_in_group(&"player"), player)


func test_dev_wasps_enter_from_above_to_slots_in_the_top_zone() -> void:
	_make_level()
	var zone_y: float = Config.num("enemies.wasp.zone_height_ratio") * Playfield.SIZE.y
	var wasps: int = 0
	for child: Node in _level.get_node("World/Enemies").get_children():
		var wasp: Wasp = child as Wasp
		if wasp == null or not wasp.is_in_group(&"counted"):
			continue
		wasps += 1
		assert_lt(wasp.global_position.y, 0.0, "starts above the top edge")
		assert_eq(wasp.state(), Wasp.State.ENTER)
		assert_lte(wasp.formation_slot().y, zone_y, "slot inside the top 40%")
		assert_eq(wasp.global_position.x, wasp.formation_slot().x, "top entry above its slot")
	assert_eq(wasps, 8, "level_dev wave 1 Wasps")


func test_process_modes() -> void:
	_make_level()
	assert_eq(_level.get_node("World").process_mode, Node.PROCESS_MODE_INHERIT, "World pausable")
	assert_eq(_level.get_node("WaveDirector").process_mode, Node.PROCESS_MODE_INHERIT, "WaveDirector pausable")
	assert_eq(_level.get_node("HUD").process_mode, Node.PROCESS_MODE_INHERIT, "HUD pausable")
	assert_eq(_level.get_node("ShakeCamera").process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(_level.get_node("Overlay/DebugTools").process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(_level.get_node("Overlay/RetryPrompt").process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(_level.get_node("Overlay/PauseMenu").process_mode, Node.PROCESS_MODE_ALWAYS)


func test_level_started_with_the_json_id_and_wave_1() -> void:
	Log.sink = _capture
	_make_level()
	Log.sink = Callable()
	assert_eq(_started, [0] as Array[int], "level_started(0) from level_dev.json")
	var director: WaveDirector = _level.get_node("WaveDirector") as WaveDirector
	assert_eq(director.wave_number(), 1, "wave 1 started")
	assert_eq(director.wave_count(), 6)
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


## Story 4.2: a cleared campaign level reaches SceneRouter.complete_level from
## the level scene: unlock, save, then level 2 starts.
func test_level_cleared_reaches_the_router() -> void:
	SceneRouter.change_scene = _record_scene
	_make_level()
	GameState.energy = 35
	Events.level_cleared.emit(1)
	assert_eq(_scene_calls, [SceneRouter.LEVEL_SCENE_PATH] as Array[String], "level scene loaded")
	assert_eq(GameState.current_level_id, "2", "level 2 starts")
	assert_eq(GameState.highest_unlocked_level, 2, "level 2 unlocked")
	assert_eq(GameState.energy, 35, "energy carried")
	assert_true(FileAccess.file_exists(TEST_SAVE), "save written")


func test_dev_level_cleared_changes_nothing() -> void:
	SceneRouter.change_scene = _record_scene
	_make_level()
	Events.level_cleared.emit(0)
	assert_eq(_scene_calls, [] as Array[String], "no scene change")
	assert_eq(GameState.current_level_id, "dev", "same level")
	assert_eq(GameState.highest_unlocked_level, 1, "no unlock")
	assert_false(FileAccess.file_exists(TEST_SAVE), "no save")


func test_wave_bar_in_the_hud() -> void:
	_make_level()
	var hud: Node = _level.get_node("HUD")
	var bar: WaveBar = hud.get_node_or_null("WaveBar") as WaveBar
	assert_not_null(bar, "HUD/WaveBar is a WaveBar")
	if bar == null:
		return
	assert_lt(bar.get_index(), hud.get_node("LevelClearBanner").get_index(), "banner draws on top")
	assert_eq(bar.process_mode, Node.PROCESS_MODE_PAUSABLE, "freezes with the game")
	assert_eq(bar.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_not_null(bar.theme, "has the shared theme")
	if bar.theme != null:
		assert_eq(bar.theme.resource_path, "res://ui/theme/defector_theme.tres")
	assert_eq(bar.position, Vector2(680, 40))
	assert_eq(bar.size, Vector2(560, 20))
	assert_true(bar.get_rect().end.y <= 120.0, "inside the top 120 px HUD band")
	var waves: Array = Config.level("dev").get("waves", []) as Array
	assert_gt(waves.size(), 1, "level_dev has several waves")
	assert_eq(bar.segment_count(), waves.size(), "one segment per level_dev wave")
	assert_eq(bar.current_index(), 0)


func test_hearts_and_vignette_in_the_hud() -> void:
	_make_level()
	var hud: Node = _level.get_node("HUD")
	var hearts: HeartsDisplay = hud.get_node_or_null("HeartsDisplay") as HeartsDisplay
	var vignette: HitVignette = hud.get_node_or_null("HitVignette") as HitVignette
	assert_not_null(hearts, "HUD/HeartsDisplay is a HeartsDisplay")
	assert_not_null(vignette, "HUD/HitVignette is a HitVignette")
	if hearts == null or vignette == null:
		return
	for node: Control in [hearts, vignette]:
		assert_eq(node.process_mode, Node.PROCESS_MODE_PAUSABLE, "%s freezes with the game" % node.name)
		assert_eq(node.mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s ignores the mouse" % node.name)
		assert_not_null(node.theme, "%s has the shared theme" % node.name)
		if node.theme != null:
			assert_eq(node.theme.resource_path, "res://ui/theme/defector_theme.tres")
	assert_lt(vignette.get_index(), hearts.get_index(), "the vignette draws under the meters")
	assert_false(vignette.visible, "vignette hidden at start")


func test_energy_bar_in_the_hud() -> void:
	_make_level()
	var hud: Node = _level.get_node("HUD")
	var bar: EnergyBar = hud.get_node_or_null("EnergyBar") as EnergyBar
	assert_not_null(bar, "HUD/EnergyBar is an EnergyBar")
	if bar == null:
		return
	assert_eq(bar.get_index(), hud.get_node("HeartsDisplay").get_index() + 1, "right after HeartsDisplay")
	assert_eq(bar.process_mode, Node.PROCESS_MODE_PAUSABLE, "freezes with the game")
	assert_eq(bar.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_not_null(bar.theme, "has the shared theme")
	if bar.theme != null:
		assert_eq(bar.theme.resource_path, "res://ui/theme/defector_theme.tres")
	assert_eq(bar.get_rect(), Rect2(1568, 76, 320, 16))
	assert_true(bar.get_rect().end.y <= 120.0, "inside the top 120 px HUD band")
	assert_eq(bar.tick_positions(), [160.0, 318.0] as Array[float], "ticks at 50 and 100")


func test_level_start_announces_zero_energy_to_the_bar() -> void:
	watch_signals(Events)
	_make_level()
	assert_signal_emitted_with_parameters(Events, "energy_changed", [0, 100])
	var bar: EnergyBar = _level.get_node("HUD/EnergyBar") as EnergyBar
	assert_eq(bar.current(), 0)
	assert_eq(bar.max_energy(), 100)


func test_level_start_shows_the_carried_energy() -> void:
	GameState.energy = 30
	_make_level()
	assert_eq((_level.get_node("HUD/EnergyBar") as EnergyBar).current(), 30)


func test_energy_pickup_reaches_the_bar() -> void:
	_make_level()
	GameState.add_energy(10)
	assert_eq((_level.get_node("HUD/EnergyBar") as EnergyBar).current(), 10)


func test_hearts_display_shows_five_after_one_frame() -> void:
	_make_level()
	var hearts: HeartsDisplay = _level.get_node("HUD/HeartsDisplay") as HeartsDisplay
	await wait_process_frames(1)
	assert_eq(hearts.max_hearts(), 5)
	assert_eq(hearts.current(), 5, "5 filled hearts")
	assert_almost_eq(hearts.get_rect().end.x, Config.num("hud.hearts.right_x"), 0.001, "right-aligned")
	assert_true(hearts.get_rect().end.y <= 120.0, "inside the top 120 px HUD band")


func test_player_hit_reaches_the_hud() -> void:
	_make_level()
	await wait_process_frames(1)
	var player: Player = _level.get_node("World/Player") as Player
	player.apply_damage(1, null)
	Feedback.reset()
	var hearts: HeartsDisplay = _level.get_node("HUD/HeartsDisplay") as HeartsDisplay
	var vignette: HitVignette = _level.get_node("HUD/HitVignette") as HitVignette
	assert_eq(hearts.current(), 4)
	assert_eq(hearts.popping_index(), 4)
	assert_almost_eq(vignette.current_alpha(), 0.5, 0.0001)
	assert_true(vignette.visible)


func test_wave_bar_follows_the_director() -> void:
	_make_level()
	var bar: WaveBar = _level.get_node("HUD/WaveBar") as WaveBar
	var director: WaveDirector = _level.get_node("WaveDirector") as WaveDirector
	director.debug_resolve_wave()
	# level_dev wave 1 has a 0.5 s wait chain; the clear follows it.
	var waited: float = 0.0
	while bar.highlighted_index() != 1 and waited < 2.0:
		await wait_seconds(0.1)
		waited += 0.1
	assert_eq(bar.target_fill(0), 1.0, "wave 1 segment full")
	assert_eq(bar.highlighted_index(), 1, "wave 2 segment highlighted in the gap")


func test_missing_level_file_starts_nothing() -> void:
	_make_level("does_not_exist")
	assert_push_error("not found")
	assert_push_error("could not be loaded")
	assert_eq(_started.size(), 0, "no level_started")
	assert_eq(_counted(), 0, "nothing spawned")


## Acceptance: clearing all six waves of level_dev (via F3) clears the level.
func test_clearing_every_dev_wave_clears_the_level() -> void:
	(Config.tuning["waves"] as Dictionary)["gap_s"] = 0.05
	Log.sink = _capture
	_make_level()
	_make_player_invincible()
	var director: WaveDirector = _level.get_node("WaveDirector") as WaveDirector
	var banner: Label = _level.get_node("HUD/LevelClearBanner") as Label
	for wave: int in 6:
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


## R3 / DW-38: shipped level_dev cleared by real kills (no F3), so the kill ->
## progress trigger -> reinforcements -> clear path runs against shipped data.
func test_dev_level_clears_with_real_kills_and_no_stall() -> void:
	const DEADLINE_S: float = 15.0
	(Config.tuning["waves"] as Dictionary)["gap_s"] = 0.05
	Log.sink = _capture
	_make_level()
	_make_player_invincible()
	var director: WaveDirector = _level.get_node("WaveDirector") as WaveDirector
	var banner: Label = _level.get_node("HUD/LevelClearBanner") as Label
	var enemies: Node = _level.get_node("World/Enemies")
	var end_ms: int = Time.get_ticks_msec() + int(DEADLINE_S * 1000.0)
	while not director.is_level_cleared() and Time.get_ticks_msec() < end_ms:
		for child: Node in enemies.get_children():
			var enemy: Enemy = child as Enemy
			if enemy == null or not enemy.is_in_group(&"counted") or enemy.is_dead() or enemy.is_queued_for_deletion():
				continue
			enemy.apply_damage(maxi(enemy.hp, 1), null)
		await wait_seconds(0.1)
	Log.sink = Callable()
	assert_true(director.is_level_cleared(), "level cleared by real kills within %.0f s (stuck on wave %d, %d/%d resolved)" % [
		DEADLINE_S, director.wave_number(), director.resolved_count(), director.total_count()])
	assert_eq(_cleared, [0] as Array[int], "level_cleared(0) once")
	assert_true(banner.visible, "LEVEL CLEAR shown")
	for wave: int in 6:
		var started: int = 0
		for line: String in _lines:
			if line.begins_with("[INFO][wave] Level 0 wave %d/6 started" % (wave + 1)):
				started += 1
		assert_eq(started, 1, "wave %d started once" % (wave + 1))
	var reinforcements: int = 0
	var stalled: int = 0
	var wave_errors: int = 0
	var f3: int = 0
	for line: String in _lines:
		if line.contains("group 'reinforcements' spawned"):
			reinforcements += 1
		if line.contains("stalled"):
			stalled += 1
		if line.begins_with("[ERROR][wave]"):
			wave_errors += 1
		if line.begins_with("[INFO][debug] F3:"):
			f3 += 1
	assert_eq(reinforcements, 1, "wave 2 reinforcements spawned once")
	assert_eq(stalled, 0, "no stall ERROR")
	assert_eq(wave_errors, 0, "no [ERROR][wave] line")
	assert_eq(f3, 0, "never resolved with F3")


## Story 2.5: level_dev wave 3 brings two counted Lancers into World/Enemies.
func test_dev_wave_3_has_lancers() -> void:
	(Config.tuning["waves"] as Dictionary)["gap_s"] = 0.05
	_make_level()
	_make_player_invincible()
	var director: WaveDirector = _level.get_node("WaveDirector") as WaveDirector
	for wave: int in 2:
		director.debug_resolve_wave()
		var waited: float = 0.0
		while director.wave_number() == wave + 1 and waited < 3.0:
			await wait_seconds(0.1)
			waited += 0.1
	assert_eq(director.wave_number(), 3, "on wave 3")
	var lancers: int = 0
	var spawner: Spawner = _level.get_node("Spawner") as Spawner
	for child: Node in _level.get_node("World/Enemies").get_children():
		var lancer: Lancer = child as Lancer
		if lancer == null or lancer.is_queued_for_deletion() or not lancer.is_in_group(&"counted"):
			continue
		lancers += 1
		assert_eq(lancer.state(), Lancer.State.ENTER, "still entering")
		# A side entry flies level at the slot's y; a top entry would still be above it.
		assert_almost_eq(lancer.global_position.y, lancer.formation_slot().y, 0.5,
			"side entry: level with its slot at y %.1f" % lancer.global_position.y)
		assert_eq(lancer.spawner, spawner, "the level Spawner is injected")
	assert_eq(lancers, 2, "two Lancers in wave 3")


## Story 2.6: level_dev wave 4 brings two counted Needles and two medium asteroids.
func test_dev_wave_4_has_needles_and_cover() -> void:
	(Config.tuning["waves"] as Dictionary)["gap_s"] = 0.05
	_make_level()
	_make_player_invincible()
	var director: WaveDirector = _level.get_node("WaveDirector") as WaveDirector
	for wave: int in 3:
		director.debug_resolve_wave()
		var waited: float = 0.0
		while director.wave_number() == wave + 1 and waited < 3.0:
			await wait_seconds(0.1)
			waited += 0.1
	assert_eq(director.wave_number(), 4, "on wave 4")
	var needles: int = 0
	var spawner: Spawner = _level.get_node("Spawner") as Spawner
	for child: Node in _level.get_node("World/Enemies").get_children():
		var needle: Needle = child as Needle
		if needle == null or needle.is_queued_for_deletion() or not needle.is_in_group(&"counted"):
			continue
		needles += 1
		assert_eq(needle.anchor().y, Config.num("enemies.needle.anchor_y_px"), "anchors on the top edge")
		assert_eq(needle.spawner, spawner, "the level Spawner is injected")
	assert_eq(needles, 2, "two Needles in wave 4")
	var medium: int = 0
	for child: Node in _level.get_node("World/Asteroids").get_children():
		var rock: Asteroid = child as Asteroid
		if rock != null and not rock.is_queued_for_deletion() and rock.size == &"medium":
			medium += 1
	assert_eq(medium, 2, "two medium asteroids for cover")


## Story 2.7: level_dev wave 5 brings one counted Bastion, on formation row 0.
func test_dev_wave_5_has_a_bastion() -> void:
	(Config.tuning["waves"] as Dictionary)["gap_s"] = 0.05
	Log.sink = _capture
	_make_level()
	_make_player_invincible()
	var director: WaveDirector = _level.get_node("WaveDirector") as WaveDirector
	for wave: int in 4:
		director.debug_resolve_wave()
		var waited: float = 0.0
		while director.wave_number() == wave + 1 and waited < 3.0:
			await wait_seconds(0.1)
			waited += 0.1
	Log.sink = Callable()
	assert_eq(director.wave_number(), 5, "on wave 5")
	var bastions: int = 0
	var spawner: Spawner = _level.get_node("Spawner") as Spawner
	for child: Node in _level.get_node("World/Enemies").get_children():
		var bastion: Bastion = child as Bastion
		if bastion == null or bastion.is_queued_for_deletion() or not bastion.is_in_group(&"counted"):
			continue
		bastions += 1
		assert_eq(bastion.formation_slot(), Vector2(960, 160), "row 0, the drift box top")
		assert_eq(bastion.spawner, spawner, "the level Spawner is injected")
	assert_eq(bastions, 1, "one Bastion in wave 5")
	for line: String in _lines:
		assert_false(line.begins_with("[WARN][spawn] bastion"), "no clamp WARN: " + line)


## Story 2.8: level_dev wave 6 lists Hunter Wasps; with the default flag (off)
## only its six Wasps spawn and count, and the skip is logged at DEBUG.
func test_dev_wave_6_skips_hunters_with_the_default_flag() -> void:
	(Config.tuning["waves"] as Dictionary)["gap_s"] = 0.05
	Log.sink = _capture
	_make_level()
	_make_player_invincible()
	var director: WaveDirector = _level.get_node("WaveDirector") as WaveDirector
	for wave: int in 5:
		director.debug_resolve_wave()
		var waited: float = 0.0
		while director.wave_number() == wave + 1 and waited < 3.0:
			await wait_seconds(0.1)
			waited += 0.1
		assert_eq(director.wave_number(), wave + 2, "wave %d advanced within 3 s" % (wave + 1))
	Log.sink = Callable()
	assert_false(Config.flag("hunter_wasp"), "flag default stays off")
	assert_eq(director.wave_number(), 6, "on wave 6")
	assert_eq(director.total_count(), 6, "six counted Wasps")
	var wasps: int = 0
	for child: Node in _level.get_node("World/Enemies").get_children():
		if child.is_queued_for_deletion():
			continue
		assert_false(child is HunterWasp, "no Hunter Wasp spawned")
		if child is Wasp and child.is_in_group(&"counted"):
			wasps += 1
	assert_eq(wasps, 6)
	var skips: int = 0
	for line: String in _lines:
		if line.begins_with("[DEBUG][spawn]") and line.contains("waves[5].spawns[0]: 4 x hunter_wasp skipped"):
			skips += 1
	assert_eq(skips, 1, "one DEBUG skip line")


# --- Level id and retry (Story 3.2) ---------------------------------------------

func test_resolve_level_id_prefers_the_game_state_id() -> void:
	assert_eq(LEVEL_SCRIPT.resolve_level_id("dev", ""), "dev", "no state id: the export")
	assert_eq(LEVEL_SCRIPT.resolve_level_id("dev", "2"), "2", "state id wins")
	assert_eq(LEVEL_SCRIPT.resolve_level_id("", "dev"), "dev")


func test_level_writes_its_id_back_to_game_state() -> void:
	Log.sink = _capture
	_make_level()
	Log.sink = Callable()
	assert_eq(GameState.current_level_id, "dev")
	assert_eq(_level.get("level_id"), "dev")
	for line: String in _lines:
		assert_false(line.contains("(retry)"), "a fresh start is not tagged: " + line)


func test_level_uses_the_game_state_id_and_tags_a_retry() -> void:
	GameState.current_level_id = "dev"
	GameState.is_retry = true
	Log.sink = _capture
	_make_level("does_not_exist")
	Log.sink = Callable()
	assert_eq(_level.get("level_id"), "dev", "GameState id wins over the export")
	assert_eq(_started, [0] as Array[int], "level_dev started")
	assert_eq(_retry_start_lines(), 1, "start line tagged (retry)")


func _retry_start_lines() -> int:
	var tagged: int = 0
	for line: String in _lines:
		if line.begins_with("[INFO][scene] Level 0") and line.ends_with(" (retry)"):
			tagged += 1
	return tagged


## Acceptance: death in a real level -> beat -> prompt + `death` pause -> RETRY
## -> SceneRouter reloads level.tscn; the reloaded level is clean.
func test_death_and_retry_reload_a_clean_level() -> void:
	(Config.tuning["feedback"] as Dictionary)["player_death_pause_s"] = 0.2
	SceneRouter.change_scene = _record_scene
	_make_level()
	await wait_process_frames(1)
	var player: Player = _level.get_node("World/Player") as Player
	var prompt: RetryPrompt = _level.get_node("Overlay/RetryPrompt") as RetryPrompt
	player.hearts = 1
	player.apply_damage(1, null)
	assert_true(player.is_dead())
	assert_true(prompt.is_pending(), "death beat running")
	assert_false(PauseArbiter.is_paused())
	# The beat is pausable and stretched by the 100 ms death hit-stop; wait in real time.
	await get_tree().create_timer(0.6, true, false, true).timeout
	assert_true(prompt.is_shown(), "prompt after the beat")
	assert_eq(PauseArbiter.reasons(), [&"death"] as Array[StringName])
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "cursor visible")
	assert_eq(prompt.reason_text(), "HULL DESTROYED")
	(prompt.get_node("Retry") as Button).pressed.emit()
	assert_eq(_scene_calls, [SceneRouter.LEVEL_SCENE_PATH] as Array[String], "level.tscn reloaded once")
	assert_false(PauseArbiter.is_paused(), "not paused")
	assert_eq(Engine.time_scale, 1.0)
	assert_true(GameState.is_retry)
	assert_eq(GameState.energy, 0)
	assert_eq(GameState.current_level_id, "dev")
	# Stand in for the scene change: free the old level, instantiate the recorded path.
	_level.queue_free()
	await wait_process_frames(1)
	var scene: PackedScene = load(_scene_calls[0]) as PackedScene
	_lines.clear()
	Log.sink = _capture
	_level = scene.instantiate() as Node2D
	_level.set("level_id", "does_not_exist")
	add_child_autofree(_level)
	Log.sink = Callable()
	assert_eq(_level.get("level_id"), "dev", "same level id")
	var fresh: Player = _level.get_node("World/Player") as Player
	assert_eq(fresh.hearts, 5, "5 hearts")
	assert_false(fresh.is_dead())
	assert_true(fresh.visible)
	var director: WaveDirector = _level.get_node("WaveDirector") as WaveDirector
	assert_eq(director.wave_number(), 1, "wave 1")
	assert_eq(_counted(), 8, "only wave 1's spawns")
	assert_eq(_level.get_node("World/Enemies").get_child_count(), 8, "no leftover enemies")
	assert_eq(_level.get_node("World/Projectiles").get_child_count(), 0, "no projectiles")
	assert_false(PauseArbiter.is_paused())
	assert_true(GameState.is_retry)
	var fresh_prompt: RetryPrompt = _level.get_node("Overlay/RetryPrompt") as RetryPrompt
	assert_false(fresh_prompt.visible, "retry prompt hidden")
	assert_false(fresh_prompt.is_pending())
	assert_eq(_retry_start_lines(), 1, "retry start logged")

## Story 4.4 acceptance: Esc in a running level pauses the tree with the HUD
## frozen and the menu shown; RESUME unpauses and the Player warps the cursor
## back onto the unmoved ship once.
func test_esc_pauses_and_resume_warps_onto_the_ship() -> void:
	_make_level()
	_make_player_invincible()
	var player: Player = _level.get_node("World/Player") as Player
	var warps: Array[Vector2] = []
	player.warp_mouse = func(at: Vector2) -> void: warps.append(at)
	var menu: PauseMenu = _level.get_node("Overlay/PauseMenu") as PauseMenu
	var ship_at: Vector2 = player.global_position
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_CONFINED_HIDDEN, "gameplay mode")
	var esc: InputEventAction = InputEventAction.new()
	esc.action = &"pause"
	esc.pressed = true
	menu._unhandled_input(esc)
	assert_true(menu.is_shown(), "menu shown")
	assert_true(menu.visible)
	assert_eq(PauseArbiter.reasons(), [&"menu"] as Array[StringName])
	assert_true(get_tree().paused, "tree paused")
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "cursor visible")
	for hud_node: String in ["HitVignette", "WaveBar", "HeartsDisplay", "EnergyBar"]:
		var node: Node = _level.get_node("HUD/" + hud_node)
		assert_eq(node.process_mode, Node.PROCESS_MODE_PAUSABLE, "%s freezes" % hud_node)
		assert_false(node.can_process(), "%s frozen under the menu" % hud_node)
	assert_eq(warps, [] as Array[Vector2], "no warp on open")
	(menu.get_node("Resume") as Button).pressed.emit()
	assert_false(menu.is_shown(), "menu hidden")
	assert_false(get_tree().paused, "tree unpaused")
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_CONFINED_HIDDEN, "gameplay mode back")
	assert_eq(warps, [ship_at] as Array[Vector2], "cursor warped onto the ship once")
	assert_eq(player.global_position, ship_at, "the ship didn't move")

func _esc_key_event() -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	return event


## Story 4.4: a real Esc key through the viewport reaches the PauseMenu, which
## marks it handled; a second Esc closes the menu.
func test_real_esc_key_toggles_the_menu() -> void:
	_make_level()
	_make_player_invincible()
	var menu: PauseMenu = _level.get_node("Overlay/PauseMenu") as PauseMenu
	get_viewport().push_input(_esc_key_event())
	assert_true(get_viewport().is_input_handled(), "Esc marked handled")
	assert_true(menu.is_shown(), "menu shown")
	assert_true(get_tree().paused, "tree paused")
	get_viewport().push_input(_esc_key_event())
	assert_true(get_viewport().is_input_handled(), "second Esc marked handled")
	assert_false(menu.is_shown(), "menu hidden")
	assert_false(get_tree().paused, "tree unpaused")

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


# --- Injected user args and change_scene (DW-46) -------------------------------

## A level whose _ready parses `args`; `record` injects _record_scene as its
## change_scene. Logs are captured during _ready.
func _level_with_args(args: PackedStringArray, record: bool = true) -> Node2D:
	_lines.clear()
	_level = LEVEL_SCENE.instantiate() as Node2D
	_level.user_args = args
	if record:
		_level.change_scene = _record_scene
	Log.sink = _capture
	add_child_autofree(_level)
	Log.sink = Callable()
	return _level


## Explosions in this level's World/Effects at the off-screen pre-warm spot.
func _prewarm_explosions() -> Array[Explosion]:
	var out: Array[Explosion] = []
	for child: Node in _level.get_node("World/Effects").get_children():
		if child is Explosion and (child as Explosion).global_position == Feedback.PREWARM_POSITION:
			out.append(child as Explosion)
	return out


func _lines_containing(text: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.contains(text):
			out.append(line)
	return out


func test_stress_arg_redirects_to_the_sandbox() -> void:
	_level_with_args(PackedStringArray(["--stress"]))
	assert_eq(_lines_containing("switching to the sandbox stress scene").size(), 1, "redirect logged")
	assert_eq(_started.size(), 0, "no level_started")
	assert_eq(GameState.current_level_id, "", "returns before the level setup")
	assert_eq(_prewarm_explosions().size(), 0, "no pre-warm explosion")
	assert_eq(_scene_calls.size(), 0, "redirect is deferred")
	await wait_process_frames(1)
	assert_eq(_scene_calls, [LEVEL_SCRIPT.SANDBOX_SCENE_PATH] as Array[String], "deferred redirect to the sandbox once")


func test_bench_arg_redirects_to_the_sandbox() -> void:
	_level_with_args(PackedStringArray(["--bench=1"]))
	assert_eq(_lines_containing("switching to the sandbox stress scene").size(), 1, "redirect logged")
	assert_eq(_started.size(), 0, "no level_started")
	assert_eq(GameState.current_level_id, "", "returns before the level setup")
	assert_eq(_prewarm_explosions().size(), 0, "no pre-warm explosion")
	assert_eq(_scene_calls.size(), 0, "redirect is deferred")
	await wait_process_frames(1)
	assert_eq(_scene_calls, [LEVEL_SCRIPT.SANDBOX_SCENE_PATH] as Array[String], "deferred redirect to the sandbox once")


func test_no_args_start_the_level_and_prewarm() -> void:
	_level_with_args(PackedStringArray())
	assert_eq(_started, [0] as Array[int], "level_started once")
	assert_eq(_prewarm_explosions().size(), ImpactTier.NAMES.size(), "one pre-warm explosion per tier")
	assert_eq(_lines_containing("Feedback pre-warm skipped").size(), 0, "no skip line")
	await wait_process_frames(1)
	assert_eq(_scene_calls.size(), 0, "no scene change")


func test_no_prewarm_arg_skips_the_prewarm() -> void:
	_level_with_args(PackedStringArray(["--no-prewarm"]))
	assert_eq(_started, [0] as Array[int], "level_started once")
	assert_eq(_prewarm_explosions().size(), 0, "no pre-warm explosion")
	assert_eq(_lines_containing("Feedback pre-warm skipped").size(), 1, "skip logged")
	await wait_process_frames(1)
	assert_eq(_scene_calls.size(), 0, "no scene change")


func test_ready_wires_the_real_change_scene() -> void:
	_level_with_args(PackedStringArray(), false)
	var wired: Callable = _level.get("change_scene")
	assert_true(wired.is_valid(), "change_scene wired")
	assert_eq(wired.get_method(), &"change_scene_to_file", "the tree's change_scene_to_file")
	assert_eq(wired.get_object(), get_tree(), "bound to the scene tree")


# --- Comms (Story 5.1) ---------------------------------------------------------

func test_comms_channel_and_panel_in_the_comms_layer() -> void:
	_make_level()
	var channel: CommsChannel = _level.get_node_or_null("Comms/CommsChannel") as CommsChannel
	assert_not_null(channel, "Comms/CommsChannel is a CommsChannel")
	if channel == null:
		return
	var panel: CommsPanel = _level.get_node_or_null("Comms/CommsPanel") as CommsPanel
	assert_not_null(panel, "Comms/CommsPanel is a CommsPanel")
	assert_true(is_instance_valid(channel.panel), "the channel's panel is wired")
	assert_eq(channel.panel, panel, "wired to Comms/CommsPanel")
	assert_eq(channel.process_mode, Node.PROCESS_MODE_ALWAYS)
	if panel != null:
		assert_eq(panel.process_mode, Node.PROCESS_MODE_ALWAYS)
		assert_false(panel.visible, "hidden at start")
	assert_false(channel.is_showing())


func test_debug_comms_id_only_in_debug_builds() -> void:
	var args: Dictionary = DebugArgs.parse(PackedStringArray(["--comms=dev_comms_check"]))
	var none: Dictionary = DebugArgs.parse(PackedStringArray())
	assert_eq(LEVEL_SCRIPT.debug_comms_id(true, args), &"dev_comms_check", "debug build")
	assert_eq(LEVEL_SCRIPT.debug_comms_id(false, args), &"", "release build ignores it")
	assert_eq(LEVEL_SCRIPT.debug_comms_id(true, none), &"", "no arg")


func test_comms_arg_requests_the_sequence_after_the_start() -> void:
	var requested: Array[StringName] = []
	var record: Callable = func(id: StringName) -> void: requested.append(id)
	Events.comms_sequence_requested.connect(record)
	_level_with_args(PackedStringArray(["--comms=dev_comms_check"]))
	assert_eq(_started, [0] as Array[int], "the level started")
	assert_eq(requested, [] as Array[StringName], "requested deferred")
	await get_tree().process_frame
	await get_tree().process_frame
	Events.comms_sequence_requested.disconnect(record)
	assert_eq(requested, [&"dev_comms_check"] as Array[StringName], "requested once")
	var channel: CommsChannel = _level.get_node("Comms/CommsChannel") as CommsChannel
	assert_eq(channel.current_sequence(), &"dev_comms_check", "the panel shows it")
	assert_true(get_tree().paused, "story pause")


func _laser_bolts() -> int:
	var n: int = 0
	for child: Node in _level.get_node("World/Projectiles").get_children():
		if child is LaserBolt:
			n += 1
	return n


## One LMB press or release through the real input path: Input parses it
## (so `fire_laser` / `comms_advance` are held or not, as for a real click)
## and dispatches it to the viewport. `at` is in viewport coordinates.
func _real_click(pressed: bool, at: Vector2) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	_parse_at(event, at)


## Parses a mouse event placed at viewport position `at` (window coordinates
## through the viewport's screen transform) and flushes it.
func _parse_at(event: InputEventMouse, at: Vector2) -> void:
	var window_at: Vector2 = get_viewport().get_screen_transform() * at
	event.position = window_at
	event.global_position = window_at
	Input.parse_input_event(event)
	Input.flush_buffered_events()


## Story 5.1 acceptance: the story panel opens over the running level (paused,
## dimmed, HUD frozen, comms-open SFX, name and typing text, no buttons), and
## clicking through every line never fires a laser bolt: the channel consumes
## press and release and lifts the pause on the release.
func test_clicking_through_a_story_never_fires_the_laser() -> void:
	_make_level()
	_make_player_invincible()
	var player: Player = _level.get_node("World/Player") as Player
	player.warp_mouse = func(_at: Vector2) -> void: pass
	var ship_at: Vector2 = player.global_position
	var mouse_before: Vector2 = get_viewport().get_mouse_position()
	var channel: CommsChannel = _level.get_node("Comms/CommsChannel") as CommsChannel
	var panel: CommsPanel = _level.get_node("Comms/CommsPanel") as CommsPanel
	assert_false(Input.is_action_pressed(&"fire_laser"), "no fire held before")
	await get_tree().physics_frame
	assert_eq(_laser_bolts(), 0, "no bolt before")
	# Another sfx first, so the comms_open check below can only pass if the channel played it.
	Audio.play_sfx(&"laser_zap")
	Events.comms_sequence_requested.emit(&"dev_comms_check")
	assert_true(get_tree().paused, "paused")
	assert_true(PauseArbiter.has_reason(&"story"))
	assert_true(panel.visible, "panel and dim shown")
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"comms_open"], "comms-open SFX")
	assert_eq((panel.get_node("Panel/Name") as Label).text, "TAREK")
	assert_true(panel.is_typing(), "text typing")
	assert_eq(panel.find_children("*", "BaseButton", true, false).size(), 0, "no buttons")
	for hud_node: String in ["WaveBar", "HeartsDisplay", "EnergyBar"]:
		assert_true(_level.get_node("HUD/" + hud_node).is_visible_in_tree(), "%s visible" % hud_node)
		assert_false(_level.get_node("HUD/" + hud_node).can_process(), "%s frozen" % hud_node)
	var clicks: int = 0
	while channel.is_showing() and clicks < 20:
		_real_click(true, ship_at)
		assert_true(Input.is_action_pressed(&"fire_laser"), "LMB held after the press")
		await get_tree().physics_frame
		await get_tree().physics_frame
		_real_click(false, ship_at)
		assert_false(Input.is_action_pressed(&"fire_laser"), "LMB up after the release")
		await get_tree().physics_frame
		await get_tree().physics_frame
		assert_eq(_laser_bolts(), 0, "no bolt after click %d" % (clicks + 1))
		clicks += 1
	assert_false(channel.is_showing(), "clicked through to the end")
	assert_between(clicks, 4, 8, "4 lines: complete (if still typing) + advance each")
	assert_false(get_tree().paused, "unpaused")
	for i: int in 5:
		await get_tree().physics_frame
	assert_eq(_laser_bolts(), 0, "no laser bolt from any click")
	var weapons: PlayerWeapons = player.get_node("Weapons") as PlayerWeapons
	assert_eq(weapons._fire_cooldown, 0.0, "fire state idle")
	Input.action_release(&"fire_laser")
	Input.action_release(&"comms_advance")
	# Other suites read the viewport mouse: put it back.
	_parse_at(InputEventMouseMotion.new(), mouse_before)
	assert_almost_eq(get_viewport().get_mouse_position(), mouse_before, Vector2.ONE, "mouse restored")


# --- Combat comms (Story 5.2) ----------------------------------------------------

func test_comms_box_in_the_comms_layer() -> void:
	_make_level()
	var channel: CommsChannel = _level.get_node("Comms/CommsChannel") as CommsChannel
	var box: CommsBox = _level.get_node_or_null("Comms/CommsBox") as CommsBox
	assert_not_null(box, "Comms/CommsBox is a CommsBox")
	if box == null:
		return
	assert_true(is_instance_valid(channel.box), "the channel's box is wired")
	assert_eq(channel.box, box, "wired to Comms/CommsBox")
	assert_lt(box.get_index(), _level.get_node("Comms/CommsPanel").get_index(), "the story panel draws on top")
	assert_false(box.visible, "hidden at start")
	assert_eq(box.process_mode, Node.PROCESS_MODE_INHERIT, "inherits")
	PauseArbiter.push(&"menu")
	assert_false(box.can_process(), "freezes with the game")
	PauseArbiter.pop(&"menu")


## Story 5.2 acceptance: with the fire button held, a combat line shows in the
## top-left box without pausing, laser bolts keep spawning, and after the line
## time the box fades and `finished` is emitted once.
func test_combat_line_keeps_the_fight_running() -> void:
	_make_level()
	_make_player_invincible()
	var player: Player = _level.get_node("World/Player") as Player
	player.warp_mouse = func(_at: Vector2) -> void: pass
	var channel: CommsChannel = _level.get_node("Comms/CommsChannel") as CommsChannel
	var box: CommsBox = _level.get_node("Comms/CommsBox") as CommsBox
	var finished: Array[StringName] = []
	var record: Callable = func(id: StringName) -> void: finished.append(id)
	Events.comms_sequence_finished.connect(record)
	var bolts: Array[int] = [0]
	var count_bolt: Callable = func(node: Node) -> void:
		if node is LaserBolt:
			bolts[0] += 1
	_level.get_node("World/Projectiles").child_entered_tree.connect(count_bolt)
	await get_tree().physics_frame
	Input.action_press(&"fire_laser")
	Events.comms_sequence_requested.emit(&"dev_combat_check")
	assert_false(get_tree().paused, "the game stays unpaused")
	assert_false(PauseArbiter.has_reason(&"story"), "no story pause")
	assert_true(box.visible, "the box shows")
	assert_false((_level.get_node("Comms/CommsPanel") as CommsPanel).visible, "no story panel")
	assert_eq((box.get_node("Box/Name") as Label).text, "ISOLDE", "uppercase name")
	assert_true(box.is_typing(), "typing text")
	var at_request: int = bolts[0]
	var left_at_start: float = channel._combat_left_s
	for i: int in 30:
		await get_tree().physics_frame
	assert_eq(channel.current_combat(), &"dev_combat_check", "still on the line")
	assert_lt(channel._combat_left_s, left_at_start, "real frames drive the line timer")
	assert_gt(bolts[0], at_request, "laser bolts keep spawning")
	assert_eq((box.get_node("Box") as Control).get_rect(), Rect2(32, 24, 560, 96), "top-left at the UX rect")
	assert_eq(finished, [] as Array[StringName], "not finished before the line time")
	channel.step_combat(channel._combat_left_s + 0.01)
	assert_eq(finished, [&"dev_combat_check"] as Array[StringName], "finished once after the line time")
	assert_false(box.is_open(), "the box fades")
	for i: int in 2000:
		await get_tree().process_frame
		if not box.visible:
			break
	assert_false(box.visible, "hidden after the fade")
	assert_eq(finished, [&"dev_combat_check"] as Array[StringName], "finished exactly once")
	Input.action_release(&"fire_laser")
	Events.comms_sequence_finished.disconnect(record)


# --- Wave-triggered dialogue (Story 5.3) ----------------------------------------

## Story 5.3 acceptance: the level's WaveDirector, restarted with an inline level
## whose wave-1 wave_start chain is [comms dev_comms_check, story_event dev_evt],
## pauses the tree with the story reason through the real CommsChannel and holds
## dev_evt; clicking through the story fires dev_evt after the pause lifts.
func test_wave_start_story_comms_holds_the_story_event() -> void:
	_make_level()
	_make_player_invincible()
	var player: Player = _level.get_node("World/Player") as Player
	player.warp_mouse = func(_at: Vector2) -> void: pass
	var ship_at: Vector2 = player.global_position
	var mouse_before: Vector2 = get_viewport().get_mouse_position()
	var channel: CommsChannel = _level.get_node("Comms/CommsChannel") as CommsChannel
	var director: WaveDirector = _level.get_node("WaveDirector") as WaveDirector
	## [event name, tree paused when it fired] per story_event_requested.
	var fired: Array[Array] = []
	var record: Callable = func(event_name: StringName) -> void: fired.append([event_name, get_tree().paused])
	Events.story_event_requested.connect(record)
	await get_tree().physics_frame
	director.start_level({"id": 0.0, "waves": [{
		"spawns": [{"type": "wasp", "count": 1.0}],
		"triggers": [{"when": "wave_start", "actions": [{"comms": "dev_comms_check"}, {"story_event": "dev_evt"}]}],
	}]}, "res://tests/inline_level_5_3.json")
	assert_true(get_tree().paused, "the tree pauses")
	assert_true(PauseArbiter.has_reason(&"story"), "with the story reason")
	assert_eq(channel.current_sequence(), &"dev_comms_check", "the story shows")
	assert_eq(fired, [] as Array[Array], "dev_evt held by the story")
	assert_eq(director.running_chains(), 1, "the chain waits")
	var clicks: int = 0
	while channel.is_showing() and clicks < 20:
		assert_eq(fired, [] as Array[Array], "dev_evt not fired mid-story")
		_real_click(true, ship_at)
		await get_tree().physics_frame
		_real_click(false, ship_at)
		await get_tree().physics_frame
		clicks += 1
	assert_false(channel.is_showing(), "clicked through to the end")
	assert_false(get_tree().paused, "the pause lifted")
	assert_eq(fired, [[&"dev_evt", false]] as Array[Array], "dev_evt fired once, after the pause lifted")
	assert_eq(director.running_chains(), 0, "the chain finished")
	Events.story_event_requested.disconnect(record)
	Input.action_release(&"fire_laser")
	Input.action_release(&"comms_advance")
	_parse_at(InputEventMouseMotion.new(), mouse_before)
