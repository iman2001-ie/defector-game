extends GutTest
## Story 7.3: the Flagship on the real level.tscn with the `dev_boss` level.
## F6 pressed through DebugTools jumps from wave 1 to the boss wave: the
## Flagship spawns through the Spawner with its cover asteroids, the BossBar
## shows (the WaveBar fades out), and nothing logs an error. The player is
## debug_invincible and the router's scene change is a recorder. Story 7.5:
## the turrets killed and the core taken to 50 open the real Final Choice
## (panel, choice, pause; the pause menu refuses), a click picks DESTROY HER,
## the response plays, the Flagship goes DESPERATE, and the core's death ends
## in boss_defeated and the level clear. DW-101: a boss Wasp and an enemy shot
## alive when the core dies are gone by the chain's end, and the ship (with
## debug_invincible off) is safe from the death on: a hit costs nothing and no
## level_failed fires. Feel, readability, fairness,
## difficulty and cover usefulness are operator checks, not claimed here.

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
	GameState.final_choice = &""


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
	var max_hp: int = Config.int_("boss.turrets.count") * Config.int_("boss.turrets.hp") + Config.int_("boss.core.hp")
	assert_eq(boss_bar.max_hp(), max_hp, "turrets.count x turrets.hp + core.hp")
	assert_eq(boss_bar.current(), max_hp)
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


# --- Story 7.5: the Final Choice, DESPERATE and the boss death on the real level ----

const CLICK_AT: Vector2 = Vector2(960, 1000)


## One LMB press or release at `at` through the root viewport (GUI first,
## then _unhandled_input), like a real click.
func _push_click(pressed: bool, at: Vector2 = CLICK_AT) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = at
	event.global_position = at
	get_viewport().push_input(event, true)


func _click_at(at: Vector2 = CLICK_AT) -> void:
	_push_click(true, at)
	_push_click(false, at)


func test_final_choice_desperate_and_boss_death_on_dev_boss() -> void:
	_make_level()
	var finished: Array[StringName] = []
	var choices: Array[StringName] = []
	var defeated: Array[int] = []
	var cleared: Array[int] = []
	var on_finished: Callable = func(id: StringName) -> void: finished.append(id)
	var on_choice: Callable = func(id: StringName) -> void: choices.append(id)
	var on_defeated: Callable = func() -> void: defeated.append(1)
	var on_cleared: Callable = func(id: int) -> void: cleared.append(id)
	Events.comms_sequence_finished.connect(on_finished)
	Events.final_choice_made.connect(on_choice)
	Events.boss_defeated.connect(on_defeated)
	Events.level_cleared.connect(on_cleared)
	_press(&"debug_skip_to_boss")
	var bosses: Array[Flagship] = _flagships()
	assert_eq(bosses.size(), 1, "the Flagship is present")
	if bosses.size() != 1:
		_disconnect_all([on_finished, on_choice, on_defeated, on_cleared])
		return
	var boss: Flagship = bosses[0]
	boss.step(Config.num("boss.hull.arrival_s"))
	assert_eq(boss.phase(), Flagship.Phase.TURRETS)
	for turret: FlagshipTurret in boss.turrets():
		turret.apply_damage(turret.hp, null)
	assert_eq(boss.phase(), Flagship.Phase.CORE)
	var core: FlagshipCore = boss.core()
	core.apply_damage(core.hp - 50, null)
	assert_eq(core.hp, 50, "the core at 50")
	assert_eq(boss.phase(), Flagship.Phase.FINAL_CHOICE)
	var boss_bar: BossBar = _level.get_node("HUD/BossBar") as BossBar
	assert_eq(boss_bar.current(), 50, "the boss bar at the final marker")
	# Isolde's lead-in in the real story panel, paused.
	var channel: CommsChannel = _level.get_node("Comms/CommsChannel") as CommsChannel
	var panel: CommsPanel = _level.get_node("Comms/CommsPanel") as CommsPanel
	var view: FinalChoice = _level.get_node("Comms/FinalChoice") as FinalChoice
	var menu: PauseMenu = _level.get_node("Overlay/PauseMenu") as PauseMenu
	assert_eq(channel.current_sequence(), &"l3_final_choice", "the lead-in plays")
	assert_true(panel.visible, "the story panel")
	assert_eq((panel.get_node("Panel/Name") as Label).text, "ISOLDE")
	assert_true(PauseArbiter.has_reason(&"story"), "combat paused")
	assert_true(get_tree().paused)
	for i: int in 4:
		_click_at()
	assert_true(channel.is_choosing(), "the choice is up after the lead-in")
	assert_true(view.visible, "FinalChoice shown")
	assert_eq(view.buttons()[0].text, "OFFER SURRENDER")
	assert_eq(view.buttons()[1].text, "DESTROY HER")
	assert_false(panel.is_cue_visible(), "no click-to-continue cue")
	assert_true(PauseArbiter.has_reason(&"final_choice"), "final_choice keeps combat paused")
	assert_true(PauseArbiter.has_reason(&"story"))
	menu.open()
	assert_false(menu.is_shown(), "Esc's pause menu refuses during the choice")
	assert_false(PauseArbiter.has_reason(&"menu"))
	_click_at()
	assert_true(channel.is_choosing(), "a click outside the buttons does nothing")
	assert_eq(finished, [] as Array[StringName])
	# Pick DESTROY HER with a real click on the button.
	_click_at(view.buttons()[1].get_global_rect().get_center())
	assert_eq(choices, [&"destroy"] as Array[StringName], "final_choice_made once")
	assert_eq(GameState.final_choice, &"destroy")
	assert_false(PauseArbiter.has_reason(&"final_choice"), "final_choice popped")
	assert_eq(channel.current_sequence(), &"l3_isolde_refuse_destroy", "the destroy response")
	assert_eq((panel.get_node("Panel/Name") as Label).text, "ARDEN", "Vale's line first")
	assert_eq(boss.phase(), Flagship.Phase.FINAL_CHOICE, "still waiting for the response")
	for i: int in 4:
		_click_at()
	assert_false(panel.visible, "the panel closed")
	assert_eq(PauseArbiter.reasons(), [] as Array[StringName], "no pause reason left")
	assert_eq(finished, [&"l3_final_choice"] as Array[StringName], "one finished, for the requested id")
	assert_eq(boss.phase(), Flagship.Phase.DESPERATE, "DESPERATE")
	assert_false(core.invulnerable, "the core is damageable")
	assert_true(core.is_targetable())
	assert_true(core.is_desperate())
	# DW-101: a live boss Wasp and an enemy shot in flight when the core dies.
	var spawner: Spawner = _level.get_node("Spawner") as Spawner
	var wasp: Wasp = spawner.spawn_enemy(&"wasp", {"slot": Vector2(960, 430), "launch_from": core.global_position}) as Wasp
	assert_not_null(wasp, "a boss Wasp")
	if wasp != null:
		wasp.add_to_group(Groups.BOSS_WASPS)
	var shot: Projectile = spawner.spawn_projectile(&"enemy_bullet", {"position": Vector2(960, 600), "velocity": Vector2(0, 10), "damage": 1})
	assert_not_null(shot, "an enemy shot in flight")
	var failed: Array[StringName] = []
	var on_failed: Callable = func(reason: StringName) -> void: failed.append(reason)
	Events.level_failed.connect(on_failed)
	# Kill the core: DYING, the chain, then boss_defeated and the level clear.
	core.apply_damage(core.hp, null)
	assert_eq(boss.phase(), Flagship.Phase.DYING)
	assert_true(Feedback.is_hit_stopped(), "the boss-death hit-stop")
	var player: Player = _level.get_node("World/Player") as Player
	player.debug_invincible = false
	assert_true(player.is_safe(), "the ship is safe from the boss's death on")
	var hearts: int = player.hearts
	player.apply_damage(99, null)
	assert_eq(player.hearts, hearts, "a hit during DYING costs nothing")
	assert_false(player.is_dead())
	await wait_seconds(Config.num("feedback.boss_death_chain_s") + 0.8)
	Events.level_failed.disconnect(on_failed)
	assert_eq(failed, [] as Array[StringName], "no level_failed")
	assert_eq(defeated.size(), 1, "boss_defeated once")
	assert_eq(_flagships().size(), 0, "the Flagship is gone")
	assert_eq(_live_enemies(), 0, "no live enemy left at the chain's end")
	assert_eq(_live_enemy_shots(), 0, "no enemy shot left at the chain's end")
	assert_eq(Feedback.chain_pending(), 0, "the chain played out")
	assert_eq(cleared, [0] as Array[int], "the boss wave resolved and dev_boss cleared")
	assert_eq(_lines_containing("[ERROR]"), [] as Array[String], "no error")
	_disconnect_all([on_finished, on_choice, on_defeated, on_cleared])


## Live (not dead, not queued) Enemy nodes under World/Enemies.
func _live_enemies() -> int:
	var count: int = 0
	for child: Node in _level.get_node("World/Enemies").get_children():
		var enemy: Enemy = child as Enemy
		if enemy != null and not enemy.is_dead() and not enemy.is_queued_for_deletion():
			count += 1
	return count


## Enemy shots under World/Projectiles not queued for deletion.
func _live_enemy_shots() -> int:
	var count: int = 0
	for child: Node in _level.get_node("World/Projectiles").get_children():
		if child is EnemyBullet and not child.is_queued_for_deletion():
			count += 1
	return count


func _disconnect_all(callables: Array) -> void:
	var signals: Array[Signal] = [Events.comms_sequence_finished, Events.final_choice_made, Events.boss_defeated, Events.level_cleared]
	for i: int in signals.size():
		if signals[i].is_connected(callables[i]):
			signals[i].disconnect(callables[i])
