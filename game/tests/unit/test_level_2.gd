extends GutTest
## Story 7.2: Level 2 (The Blockade) played on the real level.tscn with
## level_id "2", by killing counted enemies through all five waves: Tarek
## flying and no convoy, Tarek's paused briefing holding wave 1, the Needle,
## Bastion and Lancer waves with their asteroids, Isolde's interruption in the
## calm after wave 2 clears (Epic 7 playtest C), Tarek's fall and his cut-off line at 0.5 of wave 5 (no pause,
## comms silenced until the wave clears, Tarek leaving the fight), Ryn's report
## as the paused outro, then exactly one level_cleared(2) and the router loading
## level 3. The flag-off row loads a temp flags file the way F5 re-reads it
## (Config.load_data(tuning, flags)); after_each restores the shipped data. The
## player is debug_invincible, the save is a test file and the router's scene
## change is a recorder. Ally kills shift the ratios, so no test asserts an
## exact kill count; the trigger thresholds are checked from the resolved /
## total recorded when each sequence was requested. Feel, pacing, the 3-4
## minute length, cover usefulness and the emotional beat are operator
## playtests and are not claimed here.

const LEVEL_SCENE: PackedScene = preload("res://scenes/level/level.tscn")
const TEMP_FLAGS: String = "user://test_level_2_flags.json"
const TEST_SAVE: String = "user://test_level_2_save.cfg"
const LEVEL_ID: String = "2"
const BRIEFING: StringName = &"l2_briefing"
const INTERRUPT: StringName = &"l2_w3_isolde_interrupt"
const CUTOFF: StringName = &"l2_w5_tarek_cutoff"
const REPORT: StringName = &"l2_ryn_report"
const MUSIC_ID: StringName = &"combat"
const FALL_EVENT_LINE: String = "[INFO][beat] Level 2 wave 5: story event 'tarek_fall'"

var _level: Node2D
var _cleared: Array[int] = []
var _requested: Array[StringName] = []
## One entry per comms request: {id, wave, resolved, total}.
var _request_info: Array[Dictionary] = []
var _lines: Array[String] = []
var _scene_calls: Array[String] = []
## Wave number (int) -> {type id (StringName) -> how many entered World/Enemies}.
var _spawned: Dictionary = {}
## Wave number (int) -> {size (StringName) -> how many entered World/Asteroids}.
var _rocks: Dictionary = {}
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


func _on_asteroid_entered(node: Node) -> void:
	var rock: Asteroid = node as Asteroid
	if rock == null or _level == null:
		return
	var wave: int = _director().wave_number()
	if not _rocks.has(wave):
		_rocks[wave] = {}
	var tally: Dictionary = _rocks[wave]
	tally[rock.size] = int(tally.get(rock.size, 0)) + 1


func before_each() -> void:
	_cleared.clear()
	_requested.clear()
	_request_info.clear()
	_lines.clear()
	_scene_calls.clear()
	_spawned.clear()
	_rocks.clear()
	_level = null
	SaveManager.save_path = TEST_SAVE
	_delete_files()
	_reset_game_state()
	SceneRouter.change_scene = _record_scene
	Events.level_cleared.connect(_on_level_cleared)
	Events.comms_sequence_requested.connect(_on_comms_requested)
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


## The real level scene on level_2 with a short wave gap, an invincible player
## (a death would pause the tree) and no cursor warps. Every enemy entering
## World/Enemies and every asteroid entering World/Asteroids is tallied under
## its wave.
func _make_level() -> Node2D:
	(Config.tuning["waves"] as Dictionary)["gap_s"] = 0.05
	_level = LEVEL_SCENE.instantiate() as Node2D
	_level.set("level_id", LEVEL_ID)
	_level.user_args = PackedStringArray()
	_level.get_node("World/Enemies").child_entered_tree.connect(_on_enemy_entered)
	_level.get_node("World/Asteroids").child_entered_tree.connect(_on_asteroid_entered)
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


## The type tally of wave `wave` (type id -> count).
func _tally(wave: int) -> Dictionary:
	return _spawned.get(wave, {}) as Dictionary


## The asteroids spawned in wave `wave` (size -> count).
func _rocks_in(wave: int) -> Dictionary:
	return _rocks.get(wave, {}) as Dictionary


## Live nodes of `cls_name` directly under World/Allies.
func _allies_of(cls_name: String) -> int:
	var n: int = 0
	for child: Node in _level.get_node("World/Allies").get_children():
		if child.is_queued_for_deletion():
			continue
		if (cls_name == "Convoy" and child is Convoy) or (cls_name == "AllyShip" and child is AllyShip):
			n += 1
	return n


## The live Tarek AllyShip, or null once he has left.
func _tarek() -> AllyShip:
	for child: Node in _level.get_node("World/Allies").get_children():
		var ally: AllyShip = child as AllyShip
		if ally != null and not ally.is_queued_for_deletion():
			return ally
	return null


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


## Kills one counted enemy at a time (a frame between kills) until resolved /
## total reaches `ratio`.
func _kill_to_ratio(ratio: float) -> void:
	var director: WaveDirector = _director()
	var guard: int = 0
	while float(director.resolved_count()) / float(maxi(director.total_count(), 1)) < ratio and guard < 40:
		assert_true(_kill_one_counted(), "a counted enemy to kill")
		guard += 1
		await get_tree().process_frame


## Kills the last wave until the outro story shows (or the level clears).
func _kill_until_outro() -> void:
	var end_ms: int = Time.get_ticks_msec() + 10000
	while _channel().current_sequence() != REPORT and not _director().is_level_cleared() and Time.get_ticks_msec() < end_ms:
		_kill_one_counted()
		await _wait(0.05)
	assert_true(_channel().current_sequence() == REPORT or _director().is_level_cleared(),
		"wave %d reached the outro (stuck at %d/%d)" % [_director().wave_number(), _director().resolved_count(), _director().total_count()])


## Clicks through the story on the channel's advance path (as a click release does).
func _click_through() -> void:
	var channel: CommsChannel = _channel()
	var clicks: int = 0
	while channel.is_showing() and clicks < 10:
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


## Level start: Tarek and no convoy, the paused briefing holding wave 1; then
## the click-through starts wave 1 with its 8 counted and the combat music.
func _start_through_briefing() -> void:
	var director: WaveDirector = _director()
	assert_eq(_allies_of("Convoy"), 0, "no Convoy")
	assert_eq(_allies_of("AllyShip"), 1, "one AllyShip in World/Allies")
	var tarek: AllyShip = _tarek()
	assert_not_null(tarek, "Tarek flies")
	if tarek != null:
		assert_eq(tarek.ally_id, "tarek", "the ally is Tarek")
	assert_eq(director.level_id(), 2, "level 2")
	assert_eq(director.wave_count(), 5, "5 waves")
	assert_eq(_requested, [BRIEFING] as Array[StringName], "the briefing is requested at the start")
	assert_eq(_channel().current_sequence(), BRIEFING, "the briefing shows")
	assert_true(get_tree().paused, "the briefing is a paused story")
	assert_true(PauseArbiter.has_reason(&"story"), "with the story reason")
	assert_true(_panel().visible, "in the centred panel")
	assert_eq((_panel().get_node("Panel/Name") as Label).text, "TAREK")
	assert_eq(director.wave_number(), 0, "wave 1 waits for the briefing")
	assert_eq(_spawned, {}, "nothing spawned before the click-through")
	_click_through()
	assert_false(get_tree().paused, "the pause lifted")
	assert_eq(director.wave_number(), 1, "wave 1 starts after the briefing")
	assert_eq(director.total_count(), 8, "wave 1: 8 counted")
	assert_eq(Audio.current_music(), MUSIC_ID, "wave 1 starts the combat music")


## Waves 1-4: the counts by type, the asteroids, Isolde's interruption (when
## `interrupt_on`) on wave 2's clear with no pause.
func _play_waves_1_to_4(interrupt_on: bool) -> void:
	var director: WaveDirector = _director()
	assert_eq(_tally(1), {&"needle": 2, &"wasp": 6}, "wave 1: 2 Needles, 6 Wasps")
	assert_eq(_rocks_in(1), {&"medium": 2, &"large": 1}, "wave 1: 2 medium and 1 large asteroid")
	await _kill_through_wave(1)
	# Wave 2.
	assert_eq(director.wave_number(), 2, "on wave 2")
	assert_eq(director.total_count(), 9, "wave 2: 9 counted")
	assert_eq(_tally(2), {&"bastion": 1, &"wasp": 8}, "wave 2: 1 Bastion, 8 Wasps")
	assert_eq(_rocks_in(2), {}, "wave 2: no asteroids")
	await _kill_through_wave(2)
	var interrupt: Dictionary = _info(INTERRUPT)
	if interrupt_on:
		assert_false(interrupt.is_empty(), "Isolde's interruption requested")
		assert_eq(interrupt.get("wave"), 2, "on wave 2's clear")
		assert_eq(interrupt.get("total"), 9, "wave 2's count")
		assert_eq(interrupt.get("resolved"), interrupt.get("total"), "with wave 2 fully resolved (the calm gap)")
		assert_true(_channel().current_combat() == INTERRUPT or _channel().combat_queued().has(INTERRUPT), "the interruption reached the channel")
	else:
		assert_true(interrupt.is_empty(), "the interruption was never requested")
	# Wave 3.
	assert_eq(director.wave_number(), 3, "on wave 3")
	assert_eq(director.total_count(), 6, "wave 3: 6 counted")
	assert_eq(_tally(3), {&"needle": 3, &"lancer": 3}, "wave 3: 3 Needles, 3 Lancers")
	assert_eq(_rocks_in(3), {&"medium": 2}, "wave 3: 2 medium asteroids")
	await _kill_through_wave(3)
	assert_false(get_tree().paused, "wave 3 ends unpaused")
	assert_false(PauseArbiter.has_reason(&"story"), "no story pause in wave 3")
	if not interrupt_on:
		assert_false(_requested.has(INTERRUPT), "the interruption was never requested")
	# Wave 4.
	assert_eq(director.wave_number(), 4, "on wave 4")
	assert_eq(director.total_count(), 12, "wave 4: 12 counted")
	assert_eq(_tally(4), {&"bastion": 2, &"wasp": 10}, "wave 4: 2 Bastions, 10 Wasps")
	assert_eq(_rocks_in(4), {&"large": 1}, "wave 4: 1 large asteroid")
	assert_false(get_tree().paused, "no pause in wave 4")
	await _kill_through_wave(4)
	# Wave 5 starts.
	assert_eq(director.wave_number(), 5, "on wave 5")
	assert_eq(director.total_count(), 8, "wave 5: 8 counted")
	assert_eq(_tally(5), {&"needle": 2, &"bastion": 2, &"lancer": 4}, "wave 5: 2 Needles, 2 Bastions, 4 Lancers")
	assert_eq(_rocks_in(5), {&"medium": 2}, "wave 5: 2 medium asteroids")


## Kills wave 5 to the outro, checks Ryn's report pauses before the clear,
## clicks it through and checks the single clear and the router call.
func _finish_level() -> void:
	await _kill_until_outro()
	assert_eq(_channel().current_sequence(), REPORT, "Ryn's report shows")
	assert_true(get_tree().paused, "the outro is a paused story")
	assert_true(_panel().visible, "in the centred panel")
	assert_eq((_panel().get_node("Panel/Name") as Label).text, "RYN")
	assert_eq(_cleared, [] as Array[int], "not cleared before the outro")
	assert_eq(_info(REPORT).get("wave"), 5, "requested after wave 5")
	assert_eq(_info(REPORT).get("resolved"), _info(REPORT).get("total"), "with wave 5 fully resolved")
	_click_through()
	assert_eq(_cleared, [2] as Array[int], "level_cleared(2) once")
	assert_true(_director().is_level_cleared(), "the director cleared the level")
	assert_eq(_scene_calls, [SceneRouter.LEVEL_SCENE_PATH] as Array[String], "the router loaded the level scene once")
	assert_eq(GameState.current_level_id, "3", "level 3 is next")
	assert_eq(GameState.highest_unlocked_level, 3, "level 3 unlocked")
	await get_tree().process_frame
	assert_eq(_cleared, [2] as Array[int], "still cleared exactly once")
	assert_eq(_scene_calls.size(), 1, "still one scene change")


## No spawn clamp or entry warnings, no stall net and no wave errors.
func _assert_clean_log() -> void:
	assert_eq(_lines_matching("[WARN][spawn]"), [] as Array[String], "no spawn warnings")
	assert_eq(_lines_matching("stalled"), [] as Array[String], "no stalled wave")
	assert_eq(_lines_matching("[ERROR][wave]"), [] as Array[String], "no wave errors")
	assert_eq(_lines_matching("[INFO][wave] Level 2 cleared").size(), 1, "one level clear line")


# --- Acceptance 1: the shipped flags ---------------------------------------------

## The whole level with the shipped flags: the briefing, waves 1-4 and the
## interruption, then (once Isolde's line is done, as in play) the fall and the
## cut-off playing at once on the 0.5 crossing of wave 5 with no pause, the cut
## landing (comms silenced, the music stopped), Tarek leaving, Ryn's report
## before the clear, one clear and the router loading level 3.
func test_shipped_flags_play_level_2_to_the_clear() -> void:
	assert_true(Config.flag("isolde_interruptions"), "shipped: interruptions on")
	assert_true(Config.flag("tarek_fall"), "shipped: Tarek's fall on")
	_make_level()
	_start_through_briefing()
	await _play_waves_1_to_4(true)
	# Wave 5: let Isolde's line finish first (in play waves 3 and 4 outlast
	# it), so the cut-off plays at once on the crossing instead of queueing.
	var director: WaveDirector = _director()
	var idle_ms: int = Time.get_ticks_msec() + 10000
	while (_channel().current_combat() != &"" or not _channel().combat_queued().is_empty()) and Time.get_ticks_msec() < idle_ms:
		await _wait(0.05)
	assert_eq(_channel().current_combat(), &"", "no combat line playing before wave 5's kills")
	assert_eq(_channel().combat_queued(), [] as Array[StringName], "no combat line queued before wave 5's kills")
	# The fall and the cut-off on the resolve that crosses 0.5.
	await _kill_to_ratio(0.5)
	assert_eq(_lines_matching(FALL_EVENT_LINE).size(), 1, "the tarek_fall story event fired once")
	var cutoff: Dictionary = _info(CUTOFF)
	assert_false(cutoff.is_empty(), "the cut-off line requested")
	assert_eq(cutoff.get("wave"), 5, "in wave 5")
	assert_true(_crossed(cutoff, 0.5), "at 0.5 of wave 5 (%s/%s)" % [cutoff.get("resolved"), cutoff.get("total")])
	assert_eq(_channel().current_combat(), CUTOFF, "the cut-off plays at once")
	assert_false(get_tree().paused, "the fall doesn't pause")
	assert_false(PauseArbiter.is_paused(), "no pause reason")
	var tarek: AllyShip = _tarek()
	assert_not_null(tarek, "Tarek still here at the event")
	if tarek != null:
		assert_ne(tarek.state(), AllyShip.State.PATROL, "Tarek left his patrol for Vale")
	# Let the cut land before killing the rest (a clear right after 0.5 is the
	# accepted outro/cut-off edge, decision #53 reading 5).
	var end_ms: int = Time.get_ticks_msec() + 12000
	while _channel().cut_phase() != CommsChannel.CutPhase.HOLD and not _channel().is_silenced() and Time.get_ticks_msec() < end_ms:
		await get_tree().physics_frame
	assert_true(_channel().cut_phase() == CommsChannel.CutPhase.HOLD or _channel().is_silenced(), "the cut-off landed")
	assert_true(_channel().is_silenced(), "comms silenced until the wave clears")
	assert_eq(Audio.current_music(), &"", "the cut-off stopped the music")
	assert_eq(director.wave_number(), 5, "still wave 5")
	# Tarek leaves the fight.
	end_ms = Time.get_ticks_msec() + 10000
	while _tarek() != null and Time.get_ticks_msec() < end_ms:
		await get_tree().physics_frame
	assert_null(_tarek(), "Tarek has left the fight")
	assert_eq(_lines_matching("Tarek's fall: Tarek has left the level").size(), 1, "left once")
	assert_eq(director.wave_number(), 5, "still wave 5 after he left")
	await _finish_level()
	assert_eq(_requested, [BRIEFING, INTERRUPT, CUTOFF, REPORT] as Array[StringName], "comms request order")
	assert_eq(_lines_matching("Ally 'tarek' spawned").size(), 1, "Tarek never re-created")
	_assert_clean_log()


# --- Acceptance 2: tarek_fall off ------------------------------------------------

## tarek_fall off (isolde_interruptions as shipped): wave 5 passing 0.5 fires
## no story event and no cut-off line; Tarek is still patrolling and undamaged
## at the clear; Ryn's report still plays before the clear and the level clears
## to level 3.
func test_tarek_fall_off_keeps_tarek_flying_and_clears() -> void:
	_load_flags({"tarek_fall": false})
	_make_level()
	_start_through_briefing()
	await _play_waves_1_to_4(true)
	var director: WaveDirector = _director()
	await _kill_to_ratio(0.5)
	assert_gte(float(director.resolved_count()) / float(director.total_count()), 0.5, "past 50 %")
	await get_tree().process_frame
	assert_eq(_lines_matching("story event").size(), 0, "no story event")
	assert_false(_requested.has(CUTOFF), "the cut-off line was never requested")
	assert_false(_channel().is_silenced(), "comms not silenced")
	assert_false(get_tree().paused, "no pause at 0.5")
	await _kill_until_outro()
	var tarek: AllyShip = _tarek()
	assert_not_null(tarek, "Tarek still flies at the clear")
	if tarek != null:
		assert_eq(tarek.state(), AllyShip.State.PATROL, "still patrolling")
		assert_false(tarek.is_damaged(), "not damaged")
	await _finish_level()
	assert_eq(_requested, [BRIEFING, INTERRUPT, REPORT] as Array[StringName], "no cut-off in the requests")
	assert_eq(_lines_matching("Tarek's fall").size(), 0, "no fall at all")
	_assert_clean_log()


# --- Isolde's interruption off -----------------------------------------------------

## isolde_interruptions off: waves 2 and 3 clear without Isolde's line ever
## being requested, and with no pause.
func test_isolde_interruptions_off_never_requests_the_wave_3_line() -> void:
	_load_flags({"isolde_interruptions": false})
	_make_level()
	_start_through_briefing()
	await _kill_through_wave(1)
	await _kill_through_wave(2)
	assert_eq(_director().wave_number(), 3, "on wave 3")
	await _kill_through_wave(3)
	assert_eq(_director().wave_number(), 4, "wave 3 cleared")
	assert_false(_requested.has(INTERRUPT), "the interruption was never requested")
	assert_eq(_requested, [BRIEFING] as Array[StringName], "only the briefing was requested")
	assert_false(get_tree().paused, "no pause")
