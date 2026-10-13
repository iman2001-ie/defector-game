extends GutTest
## Story 7.1: Level 1 (Cargo Ambush) played on the real level.tscn with
## level_id "1", by killing counted enemies through all five waves: the convoy
## and Tarek at the start, the control hints, Tarek's ambush warning in the
## calm after wave 2 clears and Isolde's interruption in the calm after wave 3
## clears (Epic 7 playtest C), the surrender pause (answered REFUSE, Epic 7
## playtest D) and the 4 Maul reinforcements in wave 5, Tarek's closing story as the outro, then exactly
## one level_cleared(1) and the router loading level 2. The flag-off row loads
## a temp flags file the way F5 re-reads it (Config.load_data(tuning, flags));
## after_each restores the shipped data. The convoy's HP is raised before the
## level spawns so stray hits and Maul rams can't fail the run, the player is
## debug_invincible, the save is a test file and the router's scene change is
## a recorder. Ally kills and Maul misses shift the ratios, so no test asserts
## an exact kill count; the trigger thresholds are checked from the resolved /
## total recorded when each sequence was requested. Feel, pacing and the
## 3-4 minute length are operator playtests and are not claimed here.

const LEVEL_SCENE: PackedScene = preload("res://scenes/level/level.tscn")
const TEMP_FLAGS: String = "user://test_level_1_flags.json"
const TEST_SAVE: String = "user://test_level_1_save.cfg"
const LEVEL_ID: String = "1"
const TAREK_WARNING: StringName = &"l1_w3_tarek_warning"
const INTERRUPT: StringName = &"l1_w3_isolde_interrupt"
const SURRENDER: StringName = &"l1_w5_surrender"
const CLOSING: StringName = &"l1_tarek_closing"
const MUSIC_ID: StringName = &"combat"
## Large enough that no stray shot or Maul ram can end the run.
const TEST_CONVOY_HP: int = 100000

var _level: Node2D
var _cleared: Array[int] = []
var _requested: Array[StringName] = []
## One entry per comms request: {id, wave, resolved, total}.
var _request_info: Array[Dictionary] = []
var _hints: Array[StringName] = []
var _lines: Array[String] = []
var _scene_calls: Array[String] = []
## Wave number (int) -> {type id (StringName) -> how many entered World/Enemies}.
var _spawned: Dictionary = {}
var _saved_music: AudioStream = null


func _on_level_cleared(id: int) -> void:
	_cleared.append(id)


func _on_comms_requested(id: StringName) -> void:
	_requested.append(id)
	var info: Dictionary = {"id": id, "wave": 0, "resolved": 0, "total": 0}
	if _level != null and is_instance_valid(_level):
		var director: WaveDirector = _director()
		info["wave"] = director.wave_number()
		info["resolved"] = director.resolved_count()
		info["total"] = director.total_count()
	_request_info.append(info)


func _on_hint_requested(id: StringName) -> void:
	_hints.append(id)


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _record_scene(path: String) -> Error:
	_scene_calls.append(path)
	return OK


func _on_enemy_entered(node: Node) -> void:
	var enemy: Enemy = node as Enemy
	if enemy == null or _level == null:
		return
	var wave: int = _director().wave_number()
	if not _spawned.has(wave):
		_spawned[wave] = {}
	var tally: Dictionary = _spawned[wave]
	tally[enemy.type_id] = int(tally.get(enemy.type_id, 0)) + 1


func before_each() -> void:
	_cleared.clear()
	_requested.clear()
	_request_info.clear()
	_hints.clear()
	_lines.clear()
	_scene_calls.clear()
	_spawned.clear()
	_level = null
	SaveManager.save_path = TEST_SAVE
	_delete_files()
	_reset_game_state()
	SceneRouter.change_scene = _record_scene
	Events.level_cleared.connect(_on_level_cleared)
	Events.comms_sequence_requested.connect(_on_comms_requested)
	Events.hint_requested.connect(_on_hint_requested)
	Log.sink = _capture
	# A silent test track under the level's music id, so the music action is
	# observable (no combat track ships until Story 8.1).
	_saved_music = Audio.music_streams.get(MUSIC_ID) as AudioStream
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var data: PackedByteArray = PackedByteArray()
	data.resize(22050 * 2)
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = 22050
	Audio.music_streams[MUSIC_ID] = wav


func after_each() -> void:
	Events.level_cleared.disconnect(_on_level_cleared)
	Events.comms_sequence_requested.disconnect(_on_comms_requested)
	Events.hint_requested.disconnect(_on_hint_requested)
	Log.sink = Callable()
	_level = null
	Audio.stop_music(0.0)
	if _saved_music != null:
		Audio.music_streams[MUSIC_ID] = _saved_music
	else:
		Audio.music_streams.erase(MUSIC_ID)
	SceneRouter.change_scene = SceneRouter.default_change_scene()
	_delete_files()
	SaveManager.save_path = SaveManager.DEFAULT_SAVE_PATH
	_reset_game_state()
	Config.load_data()
	Feedback.reset()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	PauseArbiter.clear()


func _delete_files() -> void:
	for path: String in [TEMP_FLAGS, TEST_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _reset_game_state() -> void:
	GameState.energy = 0
	GameState.current_level_id = ""
	GameState.is_retry = false
	GameState.highest_unlocked_level = 1
	GameState.all_levels_unlocked = false
	GameState.shown_hints.clear()
	GameState.final_choice = &""


## Loads the shipped flags with `overrides` applied from a temp flags file, as
## F5 does after an edit of flags.json.
func _load_flags(overrides: Dictionary) -> void:
	var flags: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Config.DEFAULT_FLAGS_PATH))
	for key: Variant in overrides:
		flags[key] = overrides[key]
	var file: FileAccess = FileAccess.open(TEMP_FLAGS, FileAccess.WRITE)
	file.store_string(JSON.stringify(flags))
	file.close()
	Config.load_data(Config.DEFAULT_TUNING_PATH, TEMP_FLAGS)
	for key: Variant in overrides:
		assert_eq(Config.flag(str(key)), bool(overrides[key]), "%s loaded as %s" % [key, overrides[key]])


## The real level scene on level_1 with a short wave gap, a convoy that can't
## be lost, an invincible player (a death would pause the tree) and no cursor
## warps. Every enemy entering World/Enemies is tallied under its wave.
func _make_level() -> Node2D:
	(Config.tuning["waves"] as Dictionary)["gap_s"] = 0.05
	(Config.tuning["convoy"] as Dictionary)["hp"] = TEST_CONVOY_HP
	_level = LEVEL_SCENE.instantiate() as Node2D
	_level.set("level_id", LEVEL_ID)
	_level.user_args = PackedStringArray()
	_level.get_node("World/Enemies").child_entered_tree.connect(_on_enemy_entered)
	var player: Player = _level.get_node("World/Player") as Player
	player.debug_invincible = true
	player.warp_mouse = func(_at: Vector2) -> void: pass
	add_child_autofree(_level)
	return _level


func _director() -> WaveDirector:
	return _level.get_node("WaveDirector") as WaveDirector


func _channel() -> CommsChannel:
	return _level.get_node("Comms/CommsChannel") as CommsChannel


func _panel() -> CommsPanel:
	return _level.get_node("Comms/CommsPanel") as CommsPanel


func _pill() -> HintPill:
	return _level.get_node("HUD/HintPill") as HintPill


## How many enemies of `type_id` entered World/Enemies during wave `wave`.
func _spawned_in(wave: int, type_id: StringName) -> int:
	return int((_spawned.get(wave, {}) as Dictionary).get(type_id, 0))


## The type tally of wave `wave` (type id -> count).
func _tally(wave: int) -> Dictionary:
	return _spawned.get(wave, {}) as Dictionary


## Live nodes of `cls_name` directly under World/Allies.
func _allies_of(cls_name: String) -> int:
	var n: int = 0
	for child: Node in _level.get_node("World/Allies").get_children():
		if child.is_queued_for_deletion():
			continue
		if (cls_name == "Convoy" and child is Convoy) or (cls_name == "AllyShip" and child is AllyShip):
			n += 1
	return n


## Asteroids under World/Asteroids by size (size StringName -> count).
func _asteroids_by_size() -> Dictionary:
	var out: Dictionary = {}
	for child: Node in _level.get_node("World/Asteroids").get_children():
		var rock: Asteroid = child as Asteroid
		if rock != null and not rock.is_queued_for_deletion():
			out[rock.size] = int(out.get(rock.size, 0)) + 1
	return out


## Kills one counted enemy that is still alive; returns false when none is left.
func _kill_one_counted() -> bool:
	for child: Node in _level.get_node("World/Enemies").get_children():
		var enemy: Enemy = child as Enemy
		if enemy == null or not enemy.is_in_group(&"counted") or enemy.is_dead() or enemy.is_queued_for_deletion():
			continue
		enemy.apply_damage(maxi(enemy.hp, 1), null)
		return true
	return false


## Waits `seconds` of real time on a process-always timer, so it also returns
## while a story pauses the tree (GUT's wait_seconds would not).
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


## Kills counted enemies until the director leaves wave `wave`.
func _kill_through_wave(wave: int) -> void:
	var end_ms: int = Time.get_ticks_msec() + 10000
	while _director().wave_number() == wave and not _director().is_level_cleared() and Time.get_ticks_msec() < end_ms:
		_kill_one_counted()
		await _wait(0.05)
	assert_true(_director().wave_number() != wave or _director().is_level_cleared(),
		"wave %d ended (stuck at %d/%d)" % [wave, _director().resolved_count(), _director().total_count()])


## Kills the last wave until the outro story shows (or the level clears).
func _kill_until_outro() -> void:
	var end_ms: int = Time.get_ticks_msec() + 10000
	while _channel().current_sequence() != CLOSING and not _director().is_level_cleared() and Time.get_ticks_msec() < end_ms:
		_kill_one_counted()
		await _wait(0.05)
	assert_true(_channel().current_sequence() == CLOSING or _director().is_level_cleared(),
		"wave %d reached the outro (stuck at %d/%d)" % [_director().wave_number(), _director().resolved_count(), _director().total_count()])


## Kills one counted enemy at a time (a frame between kills, so a deferred group
## spawn would show) until resolved / total reaches `ratio`. While the ratio is
## below it, no Maul may have arrived in wave `wave`.
func _kill_to_ratio_without_mauls(wave: int, ratio: float) -> void:
	var director: WaveDirector = _director()
	var guard: int = 0
	while float(director.resolved_count()) / float(director.total_count()) < ratio and guard < 40:
		assert_eq(_spawned_in(wave, &"maul"), 0, "no Maul before %.2f (at %d/%d)" % [ratio, director.resolved_count(), director.total_count()])
		assert_true(_kill_one_counted(), "a counted enemy to kill")
		guard += 1
		await get_tree().process_frame


## Clicks through the story on the channel's advance path (as a click release
## does), answering a choice (Isolde's surrender offer, Epic 7 playtest D) with
## the FinalChoice button for `choice`: REFUSE keeps the level going.
func _click_through(choice: StringName = &"refuse") -> void:
	var channel: CommsChannel = _channel()
	var view: FinalChoice = _level.get_node("Comms/FinalChoice") as FinalChoice
	var clicks: int = 0
	while channel.is_showing() and clicks < 20:
		if channel.is_choosing():
			var index: int = view.option_ids().find(choice)
			assert_true(index >= 0, "the choice offers '%s'" % choice)
			if index < 0:
				return
			view.buttons()[index].pressed.emit()
		else:
			channel.advance()
		clicks += 1
	assert_false(channel.is_showing(), "clicked through")


## The recorded request of `id` (empty when it was never requested).
func _info(id: StringName) -> Dictionary:
	for info: Dictionary in _request_info:
		if info["id"] == id:
			return info
	return {}


## True when the request crossed `at`: resolved / total >= at, and one resolve
## fewer was still below it (the trigger fired on the crossing resolve).
func _crossed(info: Dictionary, at: float) -> bool:
	var total: float = float(info.get("total", 0))
	if total <= 0.0:
		return false
	var resolved: float = float(info.get("resolved", 0))
	return resolved / total >= at and (resolved - 1.0) / total < at


func _lines_matching(fragment: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.contains(fragment):
			out.append(line)
	return out


## Waves 1-4 with the start-of-level rows: convoy, Tarek, hints, music, the
## counts, wave 2's asteroids, Tarek's warning on wave 2's clear and (when
## `interrupt_on`) the interruption on wave 3's clear, wave 4's mix.
func _play_waves_1_to_4(interrupt_on: bool) -> void:
	var director: WaveDirector = _director()
	# Level start.
	assert_eq(_allies_of("Convoy"), 1, "one Convoy in World/Allies")
	assert_eq(_allies_of("AllyShip"), 1, "one AllyShip in World/Allies")
	for child: Node in _level.get_node("World/Allies").get_children():
		if child is AllyShip:
			assert_eq((child as AllyShip).ally_id, "tarek", "the ally is Tarek")
	assert_eq(director.level_id(), 1, "level 1")
	assert_eq(director.wave_count(), 5, "5 waves")
	assert_eq(director.wave_number(), 1, "wave 1 starts at once (no intro)")
	assert_eq(director.total_count(), 8, "wave 1: 8 counted")
	assert_eq(_tally(1), {&"wasp": 8}, "wave 1: 8 Wasps")
	assert_eq(_hints, [&"move_fire"] as Array[StringName], "move_fire requested at level start")
	assert_eq(_pill().showing_hint(), &"move", "the move hint shows")
	assert_true(_pill().queued().has(&"fire"), "the fire hint is queued behind it")
	assert_eq(Audio.current_music(), MUSIC_ID, "wave 1 starts the combat music")
	assert_false(get_tree().paused, "no pause at the start")
	assert_eq(_requested, [] as Array[StringName], "no comms at the start")
	await _kill_through_wave(1)
	# Wave 2.
	assert_eq(director.wave_number(), 2, "on wave 2")
	assert_eq(_hints, [&"move_fire", &"missile"] as Array[StringName], "missile requested at wave 2 start")
	assert_true(_pill().queued().has(&"missile") or _pill().showing_hint() == &"missile", "the missile hint reaches the pill")
	assert_eq(director.total_count(), 10, "wave 2: 10 counted")
	assert_eq(_tally(2), {&"wasp": 10}, "wave 2: 10 Wasps")
	assert_eq(_asteroids_by_size(), {&"small": 3, &"medium": 1}, "wave 2: 3 small and 1 medium asteroid")
	await _kill_through_wave(2)
	# Wave 3.
	assert_eq(director.wave_number(), 3, "on wave 3")
	assert_eq(director.total_count(), 17, "wave 3: 17 counted")
	assert_eq(_tally(3), {&"lancer": 2, &"wasp": 12, &"maul": 3}, "wave 3: 2 Lancers, 12 Wasps, 3 Mauls")
	var warning: Dictionary = _info(TAREK_WARNING)
	assert_false(warning.is_empty(), "Tarek's warning requested")
	assert_eq(warning.get("wave"), 2, "on wave 2's clear")
	assert_eq(warning.get("total"), 10, "wave 2's count")
	assert_eq(warning.get("resolved"), warning.get("total"), "with wave 2 fully resolved (the calm gap)")
	assert_eq(_channel().current_combat(), TAREK_WARNING, "the warning plays in the box")
	assert_false(get_tree().paused, "the warning doesn't pause")
	assert_false(PauseArbiter.has_reason(&"story"), "no story pause")
	await _kill_through_wave(3)
	assert_false(get_tree().paused, "wave 3 ends unpaused")
	assert_false(PauseArbiter.has_reason(&"story"), "no story pause in wave 3")
	var interrupt: Dictionary = _info(INTERRUPT)
	if interrupt_on:
		assert_false(interrupt.is_empty(), "Isolde's interruption requested")
		assert_eq(interrupt.get("wave"), 3, "on wave 3's clear")
		assert_eq(interrupt.get("total"), 17, "wave 3's count")
		assert_eq(interrupt.get("resolved"), interrupt.get("total"), "with wave 3 fully resolved (the calm gap)")
		assert_true(_channel().current_combat() == INTERRUPT or _channel().combat_queued().has(INTERRUPT), "the interruption reached the channel")
	else:
		assert_true(interrupt.is_empty(), "the interruption was never requested")
	# Wave 4.
	assert_eq(director.wave_number(), 4, "on wave 4")
	assert_eq(director.total_count(), 14, "wave 4: 14 counted")
	assert_eq(_tally(4), {&"lancer": 4, &"wasp": 10}, "wave 4: 4 Lancers, 10 Wasps")
	assert_false(get_tree().paused, "no pause in wave 4")
	await _kill_through_wave(4)
	assert_eq(director.wave_number(), 5, "on wave 5")
	assert_eq(director.total_count(), 23, "wave 5: 23 counted (3 + 16 + 4 reinforcements up front)")
	assert_eq(_tally(5), {&"lancer": 3, &"wasp": 16}, "wave 5: 3 Lancers, 16 Wasps, no Maul yet")


## Kills through wave 5 to the outro, checks Tarek's closing pauses before the
## clear, clicks it through and checks the single clear and the router call.
func _finish_level() -> void:
	await _kill_until_outro()
	assert_eq(_channel().current_sequence(), CLOSING, "Tarek's closing shows")
	assert_true(get_tree().paused, "the outro is a paused story")
	assert_true(_panel().visible, "in the centred panel")
	assert_eq((_panel().get_node("Panel/Name") as Label).text, "TAREK")
	assert_eq(_cleared, [] as Array[int], "not cleared before the outro")
	assert_eq(_info(CLOSING).get("wave"), 5, "requested after wave 5")
	assert_eq(_info(CLOSING).get("resolved"), _info(CLOSING).get("total"), "with wave 5 fully resolved")
	_click_through()
	assert_eq(_cleared, [1] as Array[int], "level_cleared(1) once")
	assert_true(_director().is_level_cleared(), "the director cleared the level")
	assert_eq(_scene_calls, [SceneRouter.LEVEL_SCENE_PATH] as Array[String], "the router loaded the level scene once")
	assert_eq(GameState.current_level_id, "2", "level 2 is next")
	assert_eq(GameState.highest_unlocked_level, 2, "level 2 unlocked")
	await get_tree().process_frame
	assert_eq(_cleared, [1] as Array[int], "still cleared exactly once")
	assert_eq(_scene_calls.size(), 1, "still one scene change")


## No spawn clamp or entry warnings, no stall net and no wave errors.
func _assert_clean_log() -> void:
	assert_eq(_lines_matching("[WARN][spawn]"), [] as Array[String], "no spawn warnings")
	assert_eq(_lines_matching("stalled"), [] as Array[String], "no stalled wave")
	assert_eq(_lines_matching("[ERROR][wave]"), [] as Array[String], "no wave errors")
	assert_eq(_lines_matching("group 'reinforcements' spawned").size(), 1, "the reinforcements spawned once")
	assert_eq(_lines_matching("[INFO][wave] Level 1 cleared").size(), 1, "one level clear line")


# --- Acceptance 1: the shipped flags ---------------------------------------------

## The whole level with the shipped flags: every matrix row in order, the
## comms request order, the surrender pause before the Mauls, the outro, one
## clear and the router loading level 2.
func test_shipped_flags_play_level_1_to_the_clear() -> void:
	assert_true(Config.flag("isolde_interruptions"), "shipped: interruptions on")
	assert_true(Config.flag("surrender_prompts"), "shipped: surrender prompts on")
	_make_level()
	await _play_waves_1_to_4(true)
	# Wave 5: the surrender at 0.30 pauses before any Maul.
	await _kill_to_ratio_without_mauls(5, 0.30)
	var surrender: Dictionary = _info(SURRENDER)
	assert_false(surrender.is_empty(), "the surrender requested")
	assert_eq(surrender.get("wave"), 5, "in wave 5")
	assert_true(_crossed(surrender, 0.30), "at 0.30 of wave 5 (%s/%s)" % [surrender.get("resolved"), surrender.get("total")])
	assert_true(get_tree().paused, "the surrender pauses the game")
	assert_true(PauseArbiter.has_reason(&"story"), "with the story reason")
	assert_eq(_channel().current_sequence(), SURRENDER, "the surrender shows")
	assert_true(_panel().visible, "in the centred panel")
	assert_eq((_panel().get_node("Panel/Name") as Label).text, "ISOLDE")
	await get_tree().process_frame
	assert_eq(_spawned_in(5, &"maul"), 0, "no Maul while the prompt is up")
	_click_through()
	assert_eq(GameState.final_choice, &"refuse", "Vale refused (Epic 7 playtest D)")
	assert_false(get_tree().paused, "the pause lifted")
	await get_tree().process_frame
	assert_eq(_spawned_in(5, &"maul"), 4, "4 Mauls after the refusal")
	await _finish_level()
	assert_eq(_requested, [TAREK_WARNING, INTERRUPT, SURRENDER, CLOSING] as Array[StringName], "comms request order")
	assert_eq(_hints, [&"move_fire", &"missile"] as Array[StringName], "only the two data hints were requested")
	_assert_clean_log()


# --- Acceptance 2: both Isolde flags off -------------------------------------------

## surrender_prompts and isolde_interruptions off: neither Isolde line is
## requested, the 4 Mauls still arrive at 0.30 of wave 5 with no pause, and the
## level clears to level 2.
func test_flags_off_still_send_the_mauls_and_clear() -> void:
	_load_flags({"surrender_prompts": false, "isolde_interruptions": false})
	_make_level()
	await _play_waves_1_to_4(false)
	await _kill_to_ratio_without_mauls(5, 0.30)
	assert_false(get_tree().paused, "no pause at 0.30")
	assert_false(PauseArbiter.has_reason(&"story"), "no story pause reason")
	assert_false(_panel().visible, "no story panel")
	assert_false(_requested.has(SURRENDER), "the surrender was never requested")
	await get_tree().process_frame
	assert_eq(_spawned_in(5, &"maul"), 4, "4 Mauls arrive at 0.30")
	assert_false(get_tree().paused, "still unpaused")
	await _finish_level()
	assert_eq(_requested, [TAREK_WARNING, CLOSING] as Array[StringName], "only Tarek's lines")
	_assert_clean_log()


# --- Energy hints ----------------------------------------------------------------

## Energy reaching 50 and then 100 on Level 1 queues the shield and then the
## barrage hint behind the move / fire hints (the pill raises them itself).
func test_energy_hints_show_on_level_1() -> void:
	_make_level()
	var pill: HintPill = _pill()
	assert_eq(pill.showing_hint(), &"move", "move shows first")
	assert_false(pill.queued().has(&"shield"), "no shield hint at 0 energy")
	GameState.add_energy(Config.int_("abilities.shield.cost"))
	assert_true(pill.queued().has(&"shield") or pill.showing_hint() == &"shield", "the shield hint is queued at the shield cost")
	assert_false(pill.queued().has(&"barrage"), "no barrage hint below its cost")
	GameState.add_energy(Config.int_("abilities.barrage.cost") - Config.int_("abilities.shield.cost"))
	assert_eq(GameState.energy, Config.int_("abilities.barrage.cost"), "energy lands exactly on the barrage cost")
	var queue: Array[StringName] = pill.queued()
	assert_true(queue.has(&"shield") or pill.showing_hint() == &"shield", "the shield hint is queued or showing")
	assert_true(queue.has(&"barrage") or pill.showing_hint() == &"barrage", "the barrage hint is queued at the barrage cost")
	var shield_at: int = -1 if pill.showing_hint() == &"shield" else queue.find(&"shield")
	var barrage_at: int = -1 if pill.showing_hint() == &"barrage" else queue.find(&"barrage")
	assert_lt(shield_at, barrage_at, "shield before barrage")
	assert_true(GameState.shown_hints.has(&"move"), "move recorded as shown")


# --- Playtest 2026-10-13: level 1 always teaches the controls --------------------

## level_1.json has "teach_controls": true, so the level clears the session's
## shown hints at start: a retry shows move / fire again, and the earlier
## missile and energy-hint records are gone too.
func test_a_retry_of_level_1_shows_the_control_hints_again() -> void:
	for id: StringName in [&"move", &"fire", &"missile", &"shield", &"barrage"]:
		GameState.shown_hints[id] = true
	GameState.is_retry = true
	_make_level()
	assert_eq(_hints, [&"move_fire"] as Array[StringName], "move_fire requested at level start")
	assert_eq(_pill().showing_hint(), &"move", "move shows again")
	assert_true(_pill().queued().has(&"fire"), "fire is queued again")
	assert_true(GameState.shown_hints.has(&"move"), "move recorded again as it shows")
	for id: StringName in [&"fire", &"missile", &"shield", &"barrage"]:
		assert_false(GameState.shown_hints.has(id), "%s record cleared at level start" % id)


## A real reload of level 1 after its hints showed shows them again.
func test_a_reload_of_level_1_shows_move_and_fire_again() -> void:
	_make_level()
	assert_eq(_pill().showing_hint(), &"move", "first run: move shows")
	assert_true(GameState.shown_hints.has(&"move"))
	_level.queue_free()
	await wait_process_frames(2)
	_hints.clear()
	GameState.is_retry = true
	_make_level()
	assert_eq(_hints, [&"move_fire"] as Array[StringName], "the trigger fires again")
	assert_eq(_pill().showing_hint(), &"move", "move shows again on the reload")
	assert_true(_pill().queued().has(&"fire"), "fire is queued again")
