extends GutTest
## level.tscn: the architecture tree, process modes, level_started with the
## JSON id, the gameplay mouse mode, wave 1 from level_dev.json and the
## LEVEL CLEAR banner, the hearts display and hit vignette in the HUD, the
## retry prompt in the Overlay, the level id resolution and the death -> retry
## reload (Story 3.2). Long wave runs make the player debug_invincible so a
## death can't pause the tree mid-test.

const LEVEL_SCENE: PackedScene = preload("res://scenes/level/level.tscn")
const CONTAINERS: Array[String] = ["Asteroids", "Enemies", "Allies", "Pickups", "Projectiles", "Effects"]
const ROOT_CHILDREN: Array[String] = [
	"Background", "World", "Spawner", "WaveDirector", "ShakeCamera", "WorldEnvironment", "HUD", "Comms", "Overlay",
]

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
	_reset_game_state()
	Events.level_started.connect(_on_level_started)
	Events.level_cleared.connect(_on_level_cleared)


func after_each() -> void:
	Events.level_started.disconnect(_on_level_started)
	Events.level_cleared.disconnect(_on_level_cleared)
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
