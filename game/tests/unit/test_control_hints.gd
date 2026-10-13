extends GutTest
## Story 5.8: the control hints on the real level.tscn running
## level_dev_hints.json (wave 1 `hint: move_fire`, wave 2 `hint: missile`).
## GameState.shown_hints is reset around every test; the Player's physics is
## off so the headless mouse never moves the ship (movement is simulated with
## Events.player_moved).

const LEVEL_SCENE: PackedScene = preload("res://scenes/level/level.tscn")
const THEME_PATH: String = "res://ui/theme/defector_theme.tres"
const LEVEL_ID: String = "dev_hints"

var _level: Node2D
var _hints: Array[StringName] = []


func _on_hint_requested(hint_id: StringName) -> void:
	_hints.append(hint_id)


func before_each() -> void:
	_hints.clear()
	_reset_game_state()
	GameState.shown_hints.clear()
	Events.hint_requested.connect(_on_hint_requested)


func after_each() -> void:
	Events.hint_requested.disconnect(_on_hint_requested)
	_level = null
	_reset_game_state()
	GameState.shown_hints.clear()
	Config.load_data()
	Feedback.reset()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	PauseArbiter.clear()


func _reset_game_state() -> void:
	GameState.energy = 0
	GameState.current_level_id = ""
	GameState.is_retry = false


## The real level scene on level_dev_hints with short hint fades, an invincible
## player with physics off and no cursor warps.
func _make_level() -> Node2D:
	(Config.tuning["waves"] as Dictionary)["gap_s"] = 0.05
	var pill_tuning: Dictionary = (Config.tuning["ui"] as Dictionary)["hint_pill"] as Dictionary
	pill_tuning["fade_in_s"] = 0.05
	pill_tuning["fade_out_s"] = 0.05
	_level = LEVEL_SCENE.instantiate() as Node2D
	_level.set("level_id", LEVEL_ID)
	_level.user_args = PackedStringArray()
	var player: Player = _level.get_node("World/Player") as Player
	player.debug_invincible = true
	player.warp_mouse = func(_at: Vector2) -> void: pass
	add_child_autofree(_level)
	player.set_physics_process(false)
	return _level


func _pill() -> HintPill:
	return _level.get_node("HUD/HintPill") as HintPill


func _wait_faded(pill: HintPill, max_s: float = 1.0) -> void:
	var end_ms: int = Time.get_ticks_msec() + int(max_s * 1000.0)
	while pill.is_fading() and Time.get_ticks_msec() < end_ms:
		await wait_process_frames(1)


func test_hint_pill_in_the_hud() -> void:
	_make_level()
	var hud: Node = _level.get_node("HUD")
	var pill: HintPill = hud.get_node_or_null("HintPill") as HintPill
	assert_not_null(pill, "HUD/HintPill is a HintPill")
	if pill == null:
		return
	assert_eq(pill.get_index(), hud.get_node("EnergyBar").get_index() + 1, "right after EnergyBar")
	assert_eq(pill.process_mode, Node.PROCESS_MODE_PAUSABLE, "freezes with the game")
	assert_eq(pill.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_not_null(pill.theme, "has the shared theme")
	if pill.theme != null:
		assert_eq(pill.theme.resource_path, THEME_PATH)


func test_wave_1_shows_move_then_fire_without_pausing() -> void:
	_make_level()
	var pill: HintPill = _pill()
	assert_eq(_hints, [&"move_fire"] as Array[StringName], "wave 1 asked for move_fire")
	assert_eq(pill.showing_hint(), &"move")
	assert_eq(pill.action_text(), "MOVE THE MOUSE TO FLY")
	assert_true(pill.visible, "the pill shows")
	assert_almost_eq(pill.get_rect().get_center(), Vector2(960, 560), Vector2(0.5, 0.001), "centre-low")
	assert_false(get_tree().paused, "the tree stays unpaused")
	assert_false((_level.get_node("Comms/CommsPanel") as CommsPanel).visible, "the comms panel stays hidden")
	assert_false((_level.get_node("Comms/CommsBox") as CommsBox).visible, "the comms box stays hidden")
	for i: int in 3:
		Events.player_moved.emit(50.0)
	assert_true(pill.is_fading(), "150 px of movement dismisses move")
	await _wait_faded(pill)
	assert_eq(pill.showing_hint(), &"fire", "fire replaces move")
	assert_eq(pill.key_text(), "[HOLD LMB]")
	assert_false(get_tree().paused)


func test_energy_never_changing_means_no_energy_hints() -> void:
	_make_level()
	var pill: HintPill = _pill()
	assert_eq(pill.showing_hint(), &"move", "move on screen, not an energy hint")
	assert_false(pill.queued().has(&"shield"), "energy 0 at the start: no shield hint")
	assert_false(pill.queued().has(&"barrage"))
	assert_false(GameState.shown_hints.has(&"shield"))


func test_a_retry_reload_shows_neither_hint_again() -> void:
	_make_level()
	var pill: HintPill = _pill()
	Events.player_moved.emit(150.0)
	await _wait_faded(pill)
	assert_eq(pill.showing_hint(), &"fire")
	Events.player_action.emit(&"laser")
	await _wait_faded(pill)
	assert_eq(pill.showing_hint(), &"")
	_level.queue_free()
	await wait_process_frames(2)
	_hints.clear()
	GameState.is_retry = true
	_make_level()
	assert_eq(_hints, [&"move_fire"] as Array[StringName], "the trigger fires again on the retry")
	assert_eq(_pill().showing_hint(), &"", "but neither hint shows again")
	assert_eq(_pill().queued(), [] as Array[StringName])
	assert_false(_pill().visible)


func test_a_reload_with_the_same_shown_hints_shows_neither() -> void:
	GameState.shown_hints[&"move"] = true
	GameState.shown_hints[&"fire"] = true
	_make_level()
	assert_eq(_hints, [&"move_fire"] as Array[StringName])
	assert_eq(_pill().showing_hint(), &"")
	assert_false(_pill().visible)


func test_carried_energy_at_level_start_queues_shield_then_barrage() -> void:
	GameState.energy = 100
	_make_level()
	var pill: HintPill = _pill()
	# level.gd announces the energy before the director starts wave 1.
	assert_eq(pill.showing_hint(), &"shield", "the start-of-level energy_changed(100) shows shield first")
	assert_eq(pill.queued(), [&"barrage", &"move", &"fire"] as Array[StringName],
		"barrage queued right after shield, then wave 1's move and fire")


func test_the_real_player_dismisses_move_then_fire() -> void:
	_make_level()
	var pill: HintPill = _pill()
	var player: Player = _level.get_node("World/Player") as Player
	var step: float = Config.num("ui.hint_pill.move_dismiss_px") / 3.0
	player.step_lock(Vector2(600, 800))
	assert_false(pill.is_fading(), "the first snap tick is not movement")
	for i: int in 2:
		player.step_lock(Vector2(600 + step * float(i + 1), 800))
	assert_false(pill.is_fading(), "two thirds of the distance")
	player.step_lock(Vector2(600 + step * 3.0 + 1.0, 800))
	assert_true(pill.is_fading(), "the real ship's movement dismisses move")
	await _wait_faded(pill)
	assert_eq(pill.showing_hint(), &"fire")
	player.step_fire(true, 1.0 / 60.0)
	assert_true(pill.is_fading(), "the real ship's first bolt dismisses fire")
	await _wait_faded(pill)
	assert_eq(pill.showing_hint(), &"")
	assert_false(get_tree().paused)


## Playtest 2026-10-13: only a level with "teach_controls": true (level 1)
## clears the shown hints; level_dev_hints has no such key, so every record
## survives the level start and neither hint shows.
func test_a_level_without_teach_controls_keeps_the_shown_hints() -> void:
	for id: StringName in [&"move", &"fire", &"missile", &"shield"]:
		GameState.shown_hints[id] = true
	GameState.is_retry = true
	_make_level()
	assert_eq(_hints, [&"move_fire"] as Array[StringName], "the trigger still fires")
	for id: StringName in [&"move", &"fire", &"missile", &"shield"]:
		assert_true(GameState.shown_hints.has(id), "%s still recorded" % id)
	assert_eq(_pill().showing_hint(), &"", "move doesn't show again")
	assert_eq(_pill().queued(), [] as Array[StringName])
