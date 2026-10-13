extends GutTest
## Story 5.6: Isolde's flag-gated interruption and surrender prompt on the real
## level.tscn running level_dev_isolde.json, and the debug-only `--level=<id>`
## arg. Epic 7 playtest D: the surrender offer ends in a SURRENDER / REFUSE
## choice; REFUSE plays Isolde's answer and the reinforcements come as before,
## SURRENDER plays the accept lines and loses the level (&"surrender").
## The flag-off rows load a temp flags file the way F5 re-reads it
## (Config.load_data(tuning, flags)); after_each restores the shipped data.

const LEVEL_SCENE: PackedScene = preload("res://scenes/level/level.tscn")
const LEVEL_SCRIPT: GDScript = preload("res://scenes/level/level.gd")
const TEMP_FLAGS: String = "user://test_isolde_beats_flags.json"
const TEST_SAVE: String = "user://test_isolde_beats_save.cfg"
const LEVEL_ID: String = "dev_isolde"
const INTERRUPT: StringName = &"l1_w3_isolde_interrupt"
const SURRENDER: StringName = &"l1_w5_surrender"
const SURRENDER_TEXT: String = "You're outnumbered, General. Come home."
const ACCEPT: StringName = &"l1_surrender_accept"
const REFUSE: StringName = &"l1_surrender_refuse"

var _level: Node2D
var _cleared: Array[int] = []
var _requested: Array[StringName] = []
var _lines: Array[String] = []
var _failed: Array[StringName] = []
## Every comms_sequence_finished and level_failed in order ("finished:<id>" / "failed:<reason>").
var _order: Array[String] = []


func _on_level_cleared(id: int) -> void:
	_cleared.append(id)


func _on_level_failed(reason: StringName) -> void:
	_failed.append(reason)
	_order.append("failed:%s" % reason)


func _on_comms_finished(id: StringName) -> void:
	_order.append("finished:%s" % id)


func _on_comms_requested(id: StringName) -> void:
	_requested.append(id)


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func before_each() -> void:
	_cleared.clear()
	_requested.clear()
	_lines.clear()
	_failed.clear()
	_order.clear()
	SaveManager.save_path = TEST_SAVE
	_reset_game_state()
	Events.level_cleared.connect(_on_level_cleared)
	Events.level_failed.connect(_on_level_failed)
	Events.comms_sequence_finished.connect(_on_comms_finished)
	Events.comms_sequence_requested.connect(_on_comms_requested)


func after_each() -> void:
	Events.level_cleared.disconnect(_on_level_cleared)
	Events.level_failed.disconnect(_on_level_failed)
	Events.comms_sequence_finished.disconnect(_on_comms_finished)
	Events.comms_sequence_requested.disconnect(_on_comms_requested)
	Log.sink = Callable()
	_level = null
	for path: String in [TEMP_FLAGS, TEST_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
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
	GameState.final_choice = &""


## Loads the shipped flags with `flag` set to `value` from a temp flags file,
## as F5 does after an edit of flags.json.
func _load_flags_with(flag: String, value: bool) -> void:
	var flags: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Config.DEFAULT_FLAGS_PATH))
	flags[flag] = value
	var file: FileAccess = FileAccess.open(TEMP_FLAGS, FileAccess.WRITE)
	file.store_string(JSON.stringify(flags))
	file.close()
	Config.load_data(Config.DEFAULT_TUNING_PATH, TEMP_FLAGS)
	assert_eq(Config.flag(flag), value, "%s loaded as %s" % [flag, value])


## The real level scene on level_dev_isolde, with a short wave gap, an
## invincible player (a death would pause the tree) and no cursor warps.
func _make_level() -> Node2D:
	(Config.tuning["waves"] as Dictionary)["gap_s"] = 0.05
	_level = LEVEL_SCENE.instantiate() as Node2D
	_level.set("level_id", LEVEL_ID)
	_level.user_args = PackedStringArray()
	add_child_autofree(_level)
	var player: Player = _level.get_node("World/Player") as Player
	player.debug_invincible = true
	player.warp_mouse = func(_at: Vector2) -> void: pass
	return _level


func _director() -> WaveDirector:
	return _level.get_node("WaveDirector") as WaveDirector


func _channel() -> CommsChannel:
	return _level.get_node("Comms/CommsChannel") as CommsChannel


## Counted enemies still alive in World/Enemies.
func _counted() -> int:
	var n: int = 0
	for child: Node in _level.get_node("World/Enemies").get_children():
		var enemy: Enemy = child as Enemy
		if enemy != null and enemy.is_in_group(&"counted") and not enemy.is_dead() and not enemy.is_queued_for_deletion():
			n += 1
	return n


## Kills one counted enemy that is still alive; returns false when none is left.
func _kill_one_counted() -> bool:
	for child: Node in _level.get_node("World/Enemies").get_children():
		var enemy: Enemy = child as Enemy
		if enemy == null or not enemy.is_in_group(&"counted") or enemy.is_dead() or enemy.is_queued_for_deletion():
			continue
		enemy.apply_damage(maxi(enemy.hp, 1), null)
		return true
	return false


## Kills counted enemies until the director leaves wave `wave` (or the level clears).
func _kill_through_wave(wave: int) -> void:
	var end_ms: int = Time.get_ticks_msec() + 10000
	while _director().wave_number() == wave and not _director().is_level_cleared() and Time.get_ticks_msec() < end_ms:
		_kill_one_counted()
		await wait_seconds(0.05)


## Kills on the current wave until resolved / total reaches `ratio`; returns the kills.
func _kill_to_ratio(ratio: float) -> int:
	var kills: int = 0
	var director: WaveDirector = _director()
	while float(director.resolved_count()) / float(director.total_count()) < ratio and kills < 20:
		assert_true(_kill_one_counted(), "a counted enemy to kill")
		kills += 1
	return kills


func _final_choice() -> FinalChoice:
	return _level.get_node("Comms/FinalChoice") as FinalChoice


## Presses the FinalChoice button for option `id` (as a click on it does).
func _choose(id: StringName) -> void:
	var view: FinalChoice = _final_choice()
	var index: int = view.option_ids().find(id)
	assert_true(index >= 0, "the choice offers '%s'" % id)
	if index >= 0:
		view.buttons()[index].pressed.emit()


## Clicks through the story on the channel's advance path (as a click release
## does), answering the surrender offer with `choice` (REFUSE keeps the level
## going).
func _click_through(choice: StringName = &"refuse") -> void:
	var channel: CommsChannel = _channel()
	var clicks: int = 0
	while channel.is_showing() and clicks < 20:
		if channel.is_choosing():
			_choose(choice)
		else:
			channel.advance()
		clicks += 1
	assert_false(channel.is_showing(), "clicked through")


# --- Interruption -----------------------------------------------------------------

## Interrupt on: 2 of wave 1's 8 kills (0.25) show Isolde's combat line in the
## box while the tree stays unpaused.
func test_interrupt_shows_in_the_box_without_pausing() -> void:
	_make_level()
	var box: CommsBox = _level.get_node("Comms/CommsBox") as CommsBox
	assert_eq(_director().wave_number(), 1, "on wave 1")
	assert_eq(_director().total_count(), 8, "8 counted")
	assert_true(_kill_one_counted())
	assert_eq(_channel().current_combat(), &"", "nothing at 1/8")
	assert_true(_kill_one_counted())
	assert_eq(_channel().current_combat(), INTERRUPT, "the interruption plays at 0.25")
	assert_true(box.visible, "the box shows it")
	assert_eq((box.get_node("Box/Name") as Label).text, "ISOLDE")
	assert_false(get_tree().paused, "the tree stays unpaused")
	assert_false(PauseArbiter.has_reason(&"story"), "no story pause")
	assert_false((_level.get_node("Comms/CommsPanel") as CommsPanel).visible, "no story panel")


## Interrupt off (flags file reloaded): no combat line at 0.25 or later in wave
## 1, the wave still clears, and wave 2's surrender (still on) and its 4
## reinforcements still arrive and the level clears.
func test_interrupt_off_never_fires_and_the_wave_clears() -> void:
	_load_flags_with("isolde_interruptions", false)
	_make_level()
	assert_eq(_kill_to_ratio(0.25), 2, "2 kills reach 0.25")
	assert_eq(_channel().current_combat(), &"", "no combat line at 0.25")
	await _kill_through_wave(1)
	assert_eq(_director().wave_number(), 2, "wave 1 cleared, wave 2 started")
	assert_false(_requested.has(INTERRUPT), "the interruption was never requested")
	assert_eq(_kill_to_ratio(0.30), 5, "5 of 14 reach 0.30")
	assert_eq(_channel().current_sequence(), SURRENDER, "the surrender still shows")
	_click_through()
	await get_tree().process_frame
	assert_eq(_counted(), 9, "4 reinforcements spawned after the click-through")
	await _kill_through_wave(2)
	assert_true(_director().is_level_cleared(), "the level clears")
	assert_false(_requested.has(INTERRUPT), "the interruption never played")


# --- Surrender --------------------------------------------------------------------

## Acceptance 1 with the shipped flags: the interruption shows unpaused in wave
## 1; at 0.30 of wave 2 the surrender line pauses the game in the centred panel
## before any reinforcement; after the click-through the pause lifts, 4 more
## counted wasps spawn and the level clears.
func test_shipped_flags_interrupt_then_surrender_then_reinforcements() -> void:
	assert_true(Config.flag("isolde_interruptions"), "shipped: interruptions on")
	assert_true(Config.flag("surrender_prompts"), "shipped: surrender prompts on")
	_make_level()
	var panel: CommsPanel = _level.get_node("Comms/CommsPanel") as CommsPanel
	_kill_to_ratio(0.25)
	assert_eq(_channel().current_combat(), INTERRUPT, "interruption in wave 1")
	assert_false(get_tree().paused, "unpaused during the interruption")
	await _kill_through_wave(1)
	assert_eq(_director().wave_number(), 2, "on wave 2")
	assert_eq(_director().total_count(), 14, "10 + 4 reinforcements counted up front")
	assert_eq(_counted(), 10, "10 wasps, no reinforcements yet")
	var kills: int = _kill_to_ratio(0.30)
	assert_eq(kills, 5, "5 of 14 reach 0.30")
	assert_true(get_tree().paused, "the surrender pauses the game")
	assert_true(PauseArbiter.has_reason(&"story"), "with the story reason")
	assert_eq(_channel().current_sequence(), SURRENDER, "the surrender sequence shows")
	assert_true(panel.visible, "in the centred panel")
	assert_eq((panel.get_node("Panel/Name") as Label).text, "ISOLDE")
	assert_eq((panel.get_node("Panel/Text") as Label).text, SURRENDER_TEXT)
	assert_eq(panel.find_children("*", "BaseButton", true, false).size(), 0, "no buttons in the panel itself")
	await get_tree().process_frame
	assert_eq(_counted(), 5, "no reinforcements while the prompt is up")
	# The two offer lines (complete + advance each), then SURRENDER / REFUSE.
	var channel: CommsChannel = _channel()
	for i: int in 4:
		channel.advance()
	assert_true(channel.is_choosing(), "the choice is up after Isolde's offer")
	assert_true(_final_choice().visible, "in the Final Choice view")
	assert_eq(_final_choice().option_ids(), [&"surrender", &"refuse"] as Array[StringName])
	assert_eq(_final_choice().buttons()[0].text, "SURRENDER")
	assert_eq(_final_choice().buttons()[1].text, "REFUSE")
	assert_true(get_tree().paused, "still paused while choosing")
	await get_tree().process_frame
	assert_eq(_counted(), 5, "no reinforcements while choosing")
	_choose(&"refuse")
	assert_eq(GameState.final_choice, &"refuse", "the pick is stored")
	assert_eq(channel.current_sequence(), REFUSE, "Isolde answers the refusal")
	assert_eq((panel.get_node("Panel/Name") as Label).text, "ISOLDE")
	_click_through()
	assert_false(get_tree().paused, "the pause lifted")
	assert_eq(_failed, [] as Array[StringName], "refusing loses nothing")
	await get_tree().process_frame
	assert_eq(_counted(), 9, "4 reinforcements spawned after the click-through")
	await _kill_through_wave(2)
	assert_true(_director().is_level_cleared(), "the level clears")
	assert_eq(_cleared, [0] as Array[int], "level_cleared(0) once")


## SURRENDER: the accept lines play, then (just before the surrender
## sequence's comms_sequence_finished) the level is lost with &"surrender", so
## the wave chain waiting on that sequence stops and the reinforcements never
## come; Vale's ship powers down (scripted lock), nothing clears, and the retry
## prompt shows "EXECUTED AT DAWN" after the death beat.
func test_surrender_loses_the_level_after_the_accept_lines() -> void:
	_make_level()
	await _kill_through_wave(1)
	assert_eq(_kill_to_ratio(0.30), 5, "5 of 14 reach 0.30")
	var channel: CommsChannel = _channel()
	var panel: CommsPanel = _level.get_node("Comms/CommsPanel") as CommsPanel
	for i: int in 4:
		channel.advance()
	assert_true(channel.is_choosing(), "the choice is up")
	_choose(&"surrender")
	assert_eq(GameState.final_choice, &"surrender", "the pick is stored")
	assert_eq(channel.current_sequence(), ACCEPT, "the accept lines play")
	assert_eq(_failed, [] as Array[StringName], "not lost before the accept lines end")
	var texts: Array[String] = []
	var clicks: int = 0
	while channel.is_showing() and clicks < 20:
		var text: String = (panel.get_node("Panel/Text") as Label).text
		if texts.is_empty() or texts[-1] != text:
			texts.append(text)
		channel.advance()
		clicks += 1
	assert_false(channel.is_showing(), "clicked through")
	assert_eq(texts.size(), 3, "three accept lines")
	if texts.size() == 3:
		assert_eq(texts[2], "Guards, take the General. The execution is at dawn.", "Isolde orders the execution")
	assert_eq(_failed, [&"surrender"] as Array[StringName], "level_failed(surrender) once")
	assert_eq(_order, ["failed:surrender", "finished:%s" % SURRENDER] as Array[String], "before the surrender's finished")
	assert_false(get_tree().paused, "the story pause lifted for the death beat")
	var counted_at_fail: int = _counted()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_counted(), counted_at_fail, "no reinforcements after a surrender")
	var player: Player = _level.get_node("World/Player") as Player
	assert_true(player.is_scripted_locked(), "Vale's ship powered down")
	var resolved: int = _director().resolved_count()
	assert_true(_kill_one_counted())
	assert_eq(_director().resolved_count(), resolved, "a dead attempt's kills don't count")
	var prompt: RetryPrompt = _level.get_node("Overlay/RetryPrompt") as RetryPrompt
	var end_ms: int = Time.get_ticks_msec() + int((Config.num("feedback.player_death_pause_s") + 3.0) * 1000.0)
	while not prompt.visible and Time.get_ticks_msec() < end_ms:
		await get_tree().process_frame
	assert_true(prompt.visible, "the retry prompt follows")
	assert_eq(prompt.reason_text(), "EXECUTED AT DAWN", "the surrender headline")
	assert_false(_director().is_level_cleared(), "the level never clears")
	assert_eq(_cleared, [] as Array[int], "no level_cleared")


## Surrender off (flags file reloaded): no pause and no surrender request at
## 0.30, and the 4 reinforcements still spawn.
func test_surrender_off_still_sends_the_reinforcements() -> void:
	_load_flags_with("surrender_prompts", false)
	_make_level()
	await _kill_through_wave(1)
	assert_eq(_director().wave_number(), 2, "on wave 2")
	assert_eq(_kill_to_ratio(0.30), 5, "5 of 14 reach 0.30")
	assert_false(get_tree().paused, "no pause")
	assert_false(PauseArbiter.has_reason(&"story"), "no story pause reason")
	assert_false((_level.get_node("Comms/CommsPanel") as CommsPanel).visible, "no story panel")
	assert_false(_requested.has(SURRENDER), "the surrender was never requested")
	await get_tree().process_frame
	assert_eq(_counted(), 9, "4 reinforcements spawned")
	await _kill_through_wave(2)
	assert_true(_director().is_level_cleared(), "the level clears")


## F3 with the prompt on: the surrender still pauses mid-resolve; after the
## click-through the chain finishes and the wave clears (no soft-lock). F3
## resolves the whole wave, groups included, so the existing F3 rule skips the
## chain's spawn_group (unchanged WaveDirector behaviour): nothing extra spawns.
func test_f3_with_the_prompt_on_does_not_soft_lock() -> void:
	Log.sink = _capture
	_make_level()
	_director().debug_resolve_wave()
	var end_ms: int = Time.get_ticks_msec() + 3000
	while _director().wave_number() == 1 and Time.get_ticks_msec() < end_ms:
		await wait_seconds(0.05)
	assert_eq(_director().wave_number(), 2, "on wave 2")
	_director().debug_resolve_wave()
	assert_true(get_tree().paused, "the surrender pauses")
	assert_eq(_channel().current_sequence(), SURRENDER, "the surrender shows")
	assert_eq(_director().running_chains(), 1, "the chain waits for the click-through")
	assert_false(_director().is_level_cleared(), "the wave waits for the chain")
	_click_through()
	assert_false(get_tree().paused, "the pause lifted")
	end_ms = Time.get_ticks_msec() + 3000
	while not _director().is_level_cleared() and Time.get_ticks_msec() < end_ms:
		await wait_seconds(0.05)
	assert_true(_director().is_level_cleared(), "the level clears")
	assert_eq(_director().running_chains(), 0, "the chain finished")
	assert_eq(_cleared, [0] as Array[int], "level_cleared(0) once")
	assert_eq(_lines.count("[DEBUG][beat] Group 'reinforcements' was skipped (F3 or stall net); not spawned"), 1, "F3 skipped the group")
	Log.sink = Callable()


# --- --level=<id> -----------------------------------------------------------------

func test_debug_level_id_only_in_debug_builds() -> void:
	var args: Dictionary = DebugArgs.parse(PackedStringArray(["--level=dev_isolde"]))
	var none: Dictionary = DebugArgs.parse(PackedStringArray())
	var empty: Dictionary = DebugArgs.parse(PackedStringArray(["--level="]))
	assert_push_warning("--level")
	assert_eq(LEVEL_SCRIPT.debug_level_id(true, args), "dev_isolde", "debug build")
	assert_eq(LEVEL_SCRIPT.debug_level_id(false, args), "", "release build ignores it")
	assert_eq(LEVEL_SCRIPT.debug_level_id(true, none), "", "no arg")
	assert_eq(LEVEL_SCRIPT.debug_level_id(true, empty), "", "empty arg")
	assert_eq(LEVEL_SCRIPT.debug_level_id(true, {}), "", "no level key")


## A retry keeps its GameState id even with the arg: the arg only replaces the
## exported id, before resolve_level_id.
func test_retry_keeps_its_id_over_the_arg() -> void:
	var exported: String = LEVEL_SCRIPT.debug_level_id(true, DebugArgs.parse(PackedStringArray(["--level=dev_isolde"])))
	assert_eq(LEVEL_SCRIPT.resolve_level_id(exported, "dev"), "dev", "GameState id wins")
	assert_eq(LEVEL_SCRIPT.resolve_level_id(exported, ""), "dev_isolde", "fresh run uses the arg")


func _level_with_args(args: PackedStringArray) -> void:
	_level = LEVEL_SCENE.instantiate() as Node2D
	_level.user_args = args
	Log.sink = _capture
	add_child_autofree(_level)
	Log.sink = Callable()


func test_level_arg_runs_that_level() -> void:
	_level_with_args(PackedStringArray(["--level=dev_isolde"]))
	assert_eq(_level.get("level_id"), "dev_isolde", "the arg replaced the exported id")
	assert_eq(GameState.current_level_id, "dev_isolde", "written back, so a retry keeps it")
	assert_eq(_director().total_count(), 8, "dev_isolde wave 1 runs")
	assert_eq(_lines.count("[INFO][debug] --level: running level 'dev_isolde'"), 1, "one debug line")


func test_level_arg_does_not_override_a_retry() -> void:
	GameState.current_level_id = "dev"
	_level_with_args(PackedStringArray(["--level=dev_isolde"]))
	assert_eq(_level.get("level_id"), "dev", "the retry id stays")
	assert_eq(GameState.current_level_id, "dev")
	assert_eq(_lines_containing("--level").size(), 1, "one debug line")
	assert_eq(_lines.count("[INFO][debug] --level 'dev_isolde' ignored: GameState level 'dev' wins"), 1, "says the arg was ignored")


func test_no_level_arg_keeps_the_exported_id() -> void:
	_level_with_args(PackedStringArray())
	assert_eq(_level.get("level_id"), "dev", "the exported dev level")
	assert_eq(_lines_containing("--level").size(), 0, "no --level line")


func _lines_containing(text: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.contains(text):
			out.append(line)
	return out
