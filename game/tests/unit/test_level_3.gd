extends GutTest
## Story 7.6: Level 3 (Siege of the Throne World) played on the real level.tscn
## with level_id "3": Ryn flying and no convoy, the throne world in the
## Background, Ryn's paused briefing holding wave 1, the three defence waves
## (the W2 Hunter Wasps skipped and not counted while `hunter_wasp` is off, as
## shipped), Isolde's taunt at 0.25 of wave 3 with no pause, then the Flagship
## boss wave with the boss music and its cover asteroids, driven through the
## turrets, the 50 HP clamp, the Final Choice (OFFER SURRENDER), the response
## and the core's death to exactly one boss_defeated; then (Story 7.7) Isolde's
## final line l3_isolde_final plays as the paused story outro (ISOLDE in the
## panel) with no clear yet, and only after its click-through come one
## level_cleared(3), the save and the router going to the end screen. An
## all-flags-on run (every flags.json key true, the Hunter Wasps counted,
## DESTROY HER) proves the Final Choice, the refusal and the final line each
## fire exactly once (AC3). The flag rows load a temp flags file the way F5 re-reads it
## (Config.load_data(tuning, flags)); after_each restores the shipped data. The
## player is debug_invincible, the save is a test file and the router's scene
## change is a recorder. Ryn's kills shift the ratios, so no test asserts an
## exact kill count; the taunt's threshold is checked from the resolved / total
## recorded when it was requested. Feel, pacing, the 3-4 minute length,
## difficulty and how the throne-world reveal reads are operator playtests and
## are not claimed here.

const LEVEL_SCENE: PackedScene = preload("res://scenes/level/level.tscn")
const TEMP_FLAGS: String = "user://test_level_3_flags.json"
const TEST_SAVE: String = "user://test_level_3_save.cfg"
const LEVEL_ID: String = "3"
const BRIEFING: StringName = &"l3_briefing"
const TAUNT: StringName = &"l3_w3_isolde_taunt"
const FINAL_CHOICE: StringName = &"l3_final_choice"
const FINAL_LINE: StringName = &"l3_isolde_final"
const COMBAT_MUSIC: StringName = &"combat"
const BOSS_MUSIC: StringName = &"boss"
const MUSIC_IDS: Array[StringName] = [&"combat", &"boss"]
const HUNTER_SKIP_LINE: String = "waves[1].spawns[2]: 4 x hunter_wasp skipped (flag 'hunter_wasp' off); not counted"
## A click below the story panel and clear of the Final Choice buttons.
const CLICK_AT: Vector2 = Vector2(960, 1000)

var _level: Node2D
var _cleared: Array[int] = []
var _defeated: Array[int] = []
var _choices: Array[StringName] = []
var _requested: Array[StringName] = []
## One entry per comms request: {id, wave, resolved, total}.
var _request_info: Array[Dictionary] = []
var _lines: Array[String] = []
var _scene_calls: Array[String] = []
## Wave number (int) -> {type id (StringName) -> how many entered World/Enemies}.
var _spawned: Dictionary = {}
## Wave number (int) -> {size (StringName) -> how many entered World/Asteroids}.
var _rocks: Dictionary = {}
## Music id -> the stream it had before the test (null when none).
var _saved_music: Dictionary = {}


func _on_level_cleared(id: int) -> void:
	_cleared.append(id)


func _on_boss_defeated() -> void:
	_defeated.append(1)


func _on_final_choice_made(id: StringName) -> void:
	_choices.append(id)


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
	_defeated.clear()
	_choices.clear()
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
	Events.boss_defeated.connect(_on_boss_defeated)
	Events.final_choice_made.connect(_on_final_choice_made)
	Events.comms_sequence_requested.connect(_on_comms_requested)
	Log.sink = _capture
	# Silent test tracks under the combat and boss ids, so both music actions
	# are observable (no track ships until Story 8.1).
	_saved_music.clear()
	for id: StringName in MUSIC_IDS:
		_saved_music[id] = Audio.music_streams.get(id) as AudioStream
		Audio.music_streams[id] = _silent_track()


func after_each() -> void:
	Events.level_cleared.disconnect(_on_level_cleared)
	Events.boss_defeated.disconnect(_on_boss_defeated)
	Events.final_choice_made.disconnect(_on_final_choice_made)
	Events.comms_sequence_requested.disconnect(_on_comms_requested)
	Log.sink = Callable()
	_level = null
	Audio.stop_music(0.0)
	for id: StringName in MUSIC_IDS:
		var saved: AudioStream = _saved_music.get(id) as AudioStream
		if saved != null:
			Audio.music_streams[id] = saved
		else:
			Audio.music_streams.erase(id)
	SceneRouter.change_scene = SceneRouter.default_change_scene()
	_delete_files()
	SaveManager.save_path = SaveManager.DEFAULT_SAVE_PATH
	_reset_game_state()
	Config.load_data()
	Feedback.reset()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	PauseArbiter.clear()


func _silent_track() -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var data: PackedByteArray = PackedByteArray()
	data.resize(22050 * 2)
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = 22050
	return wav


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


## The real level scene on level_3 with a short wave gap, an invincible player
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


func _tally(wave: int) -> Dictionary:
	return _spawned.get(wave, {}) as Dictionary


func _rocks_in(wave: int) -> Dictionary:
	return _rocks.get(wave, {}) as Dictionary


## Live nodes of `cls_name` directly under World/Allies.
func _allies_of(cls_name: String) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in _level.get_node("World/Allies").get_children():
		if child.is_queued_for_deletion():
			continue
		if (cls_name == "Convoy" and child is Convoy) or (cls_name == "AllyShip" and child is AllyShip):
			out.append(child)
	return out


func _flagships() -> Array[Flagship]:
	var out: Array[Flagship] = []
	for child: Node in _level.get_node("World/Enemies").get_children():
		var boss: Flagship = child as Flagship
		if boss != null and not boss.is_queued_for_deletion():
			out.append(boss)
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


## Clicks through the story on the channel's advance path (as a click release does).
func _click_through() -> void:
	var channel: CommsChannel = _channel()
	var clicks: int = 0
	while channel.is_showing() and clicks < 10:
		channel.advance()
		clicks += 1
	assert_false(channel.is_showing(), "clicked through")


## One LMB press or release at `at` through the root viewport (GUI first,
## then _unhandled_input), like a real click.
func _push_click(pressed: bool, at: Vector2) -> void:
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


## [save_version, highest_unlocked_level, energy] read straight from the test
## save ([] when there is none).
func _read_save() -> Array:
	var file: ConfigFile = ConfigFile.new()
	if file.load(TEST_SAVE) != OK:
		return []
	return [
		file.get_value("progress", "save_version"),
		file.get_value("progress", "highest_unlocked_level"),
		file.get_value("progress", "energy"),
	]


func _lines_matching(fragment: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.contains(fragment):
			out.append(line)
	return out


## No spawn clamp or entry warnings, no stall net and no errors.
func _assert_clean_log() -> void:
	assert_eq(_lines_matching("[WARN][spawn]"), [] as Array[String], "no spawn warnings")
	assert_eq(_lines_matching("stalled"), [] as Array[String], "no stalled wave")
	assert_eq(_lines_matching("[ERROR]"), [] as Array[String], "no errors")


## Level start: Ryn and no convoy, the throne world in the Background, the
## paused briefing (RYN) holding wave 1; then the click-through starts wave 1
## with its 16 counted and the combat music.
func _start_through_briefing() -> void:
	var director: WaveDirector = _director()
	assert_eq(_allies_of("Convoy").size(), 0, "no Convoy")
	var allies: Array[Node] = _allies_of("AllyShip")
	assert_eq(allies.size(), 1, "one AllyShip in World/Allies")
	if allies.size() == 1:
		assert_eq((allies[0] as AllyShip).ally_id, "ryn", "the ally is Ryn")
	var bg: LevelBackground = _level.get_node("Background") as LevelBackground
	assert_not_null(bg, "Background is a LevelBackground")
	if bg != null:
		assert_true(bg.shows_throne_world(), "the throne world is in the background")
	assert_eq(director.level_id(), 3, "level 3")
	assert_eq(director.wave_count(), 4, "3 defence waves and the boss wave")
	assert_eq(_requested, [BRIEFING] as Array[StringName], "the briefing is requested at the start")
	assert_eq(_channel().current_sequence(), BRIEFING, "the briefing shows")
	assert_true(get_tree().paused, "the briefing is a paused story")
	assert_true(PauseArbiter.has_reason(&"story"), "with the story reason")
	assert_true(_panel().visible, "in the centred panel")
	assert_eq((_panel().get_node("Panel/Name") as Label).text, "RYN")
	assert_eq(director.wave_number(), 0, "wave 1 waits for the briefing")
	assert_eq(_spawned, {}, "nothing spawned before the click-through")
	_click_through()
	assert_false(get_tree().paused, "the pause lifted")
	assert_eq(director.wave_number(), 1, "wave 1 starts after the briefing")
	assert_eq(director.total_count(), 16, "wave 1: 16 counted")
	assert_eq(_tally(1), {&"lancer": 4, &"wasp": 12}, "wave 1: 4 Lancers, 12 Wasps")
	assert_eq(_rocks_in(1), {}, "wave 1: no asteroids")
	assert_eq(Audio.current_music(), COMBAT_MUSIC, "wave 1 starts the combat music")


## Wave 2 with `hunter_on` as the hunter_wasp flag: the counted mix, the 3
## medium asteroids, the Hunter Wasps skipped (one DEBUG line) or counted.
func _check_wave_2(hunter_on: bool) -> void:
	var director: WaveDirector = _director()
	assert_eq(director.wave_number(), 2, "on wave 2")
	if hunter_on:
		assert_eq(director.total_count(), 8, "wave 2: 8 counted with hunter_wasp on")
		assert_eq(_tally(2), {&"needle": 2, &"bastion": 2, &"hunter_wasp": 4}, "wave 2: 2 Needles, 2 Bastions, 4 Hunter Wasps")
		assert_eq(_lines_matching(HUNTER_SKIP_LINE), [] as Array[String], "no skip line")
	else:
		assert_eq(director.total_count(), 4, "wave 2: 4 counted with hunter_wasp off")
		assert_eq(_tally(2), {&"needle": 2, &"bastion": 2}, "wave 2: 2 Needles, 2 Bastions, no Hunter Wasp")
		var skips: int = 0
		for line: String in _lines:
			if line.begins_with("[DEBUG][spawn]") and line.contains(HUNTER_SKIP_LINE):
				skips += 1
		assert_eq(skips, 1, "one DEBUG skip line")
	assert_eq(_rocks_in(2), {&"medium": 3}, "wave 2: 3 medium asteroids")


## Wave 3: the counted mix and, when `taunt_on`, Isolde's taunt requested on
## the resolve that crosses 0.25 with no pause; then the boss wave starts with
## the boss music, total 1, one Flagship and its 2 medium cover asteroids.
func _play_wave_3_into_the_boss(taunt_on: bool) -> void:
	var director: WaveDirector = _director()
	assert_eq(director.wave_number(), 3, "on wave 3")
	assert_eq(director.total_count(), 24, "wave 3: 24 counted")
	assert_eq(_tally(3), {&"bastion": 1, &"lancer": 3, &"wasp": 20}, "wave 3: 1 Bastion, 3 Lancers, 20 Wasps")
	assert_eq(_rocks_in(3), {}, "wave 3: no asteroids")
	await _kill_through_wave(3)
	assert_false(get_tree().paused, "wave 3 ends unpaused")
	assert_false(PauseArbiter.has_reason(&"story"), "no story pause in wave 3")
	var taunt: Dictionary = _info(TAUNT)
	if taunt_on:
		assert_false(taunt.is_empty(), "Isolde's taunt requested")
		assert_eq(taunt.get("wave"), 3, "in wave 3")
		assert_true(_crossed(taunt, 0.25), "at 0.25 of wave 3 (%s/%s)" % [taunt.get("resolved"), taunt.get("total")])
	else:
		assert_true(taunt.is_empty(), "the taunt was never requested")
	# The boss wave.
	assert_eq(director.wave_number(), 4, "on the boss wave")
	assert_eq(director.total_count(), 1, "the boss wave counts 1")
	assert_eq(Audio.current_music(), BOSS_MUSIC, "the boss music")
	assert_eq(_flagships().size(), 1, "one Flagship")
	assert_eq(_tally(4), {&"flagship": 1}, "the boss wave spawns only the Flagship")
	assert_eq(_rocks_in(4), {&"medium": 2}, "its 2 medium cover asteroids")
	assert_false(director.is_level_cleared(), "not cleared while the Flagship lives")


## Drives the live Flagship from its arrival to the end screen: the turrets
## killed, the core taken to the 50 HP clamp, Isolde's lead-in clicked through,
## a real click on option `option` (`choice`, whose response `response` opens
## with Vale's line), the response clicked through, DESPERATE, the core killed;
## then boss_defeated once and Isolde's final line as the paused story outro
## (ISOLDE) with no clear, no save and no scene change yet; after its
## click-through, level_cleared(3) once, the save [1, 3, energy], one change to
## the end screen and still exactly once 0.3 s later.
func _drive_flagship_to_the_end_screen(option: int, choice: StringName, response: StringName) -> void:
	var bosses: Array[Flagship] = _flagships()
	assert_eq(bosses.size(), 1, "one Flagship to drive")
	if bosses.size() != 1:
		return
	var boss: Flagship = bosses[0]
	# Phase 1: the arrival, then the turrets killed.
	boss.step(Config.num("boss.hull.arrival_s"))
	assert_eq(boss.phase(), Flagship.Phase.TURRETS, "the turrets phase")
	for turret: FlagshipTurret in boss.turrets():
		if is_instance_valid(turret) and not turret.is_dead():
			turret.apply_damage(turret.hp, null)
	assert_eq(boss.phase(), Flagship.Phase.CORE, "the exposed core")
	# Phase 2 to the clamp: the Final Choice opens.
	var core: FlagshipCore = boss.core()
	core.apply_damage(core.hp - 50, null)
	assert_eq(core.hp, 50, "the core clamped at 50")
	assert_eq(boss.phase(), Flagship.Phase.FINAL_CHOICE, "FINAL_CHOICE")
	var channel: CommsChannel = _channel()
	var view: FinalChoice = _level.get_node("Comms/FinalChoice") as FinalChoice
	assert_eq(channel.current_sequence(), FINAL_CHOICE, "Isolde's lead-in plays")
	assert_true(get_tree().paused, "the Final Choice pauses")
	assert_eq((_panel().get_node("Panel/Name") as Label).text, "ISOLDE")
	for i: int in 4:
		_click_at()
	assert_true(channel.is_choosing(), "the choice is up after the lead-in")
	assert_true(view.visible, "FinalChoice shown")
	assert_eq(view.buttons()[0].text, "OFFER SURRENDER")
	assert_eq(view.buttons()[1].text, "DESTROY HER")
	# The option with a real click, then the response.
	_click_at(view.buttons()[option].get_global_rect().get_center())
	assert_eq(_choices, [choice] as Array[StringName], "final_choice_made once")
	assert_eq(GameState.final_choice, choice)
	assert_eq(channel.current_sequence(), response, "the %s response" % choice)
	assert_eq((_panel().get_node("Panel/Name") as Label).text, "VALE", "Vale's line first")
	for i: int in 4:
		_click_at()
	assert_false(_panel().visible, "the panel closed")
	assert_eq(PauseArbiter.reasons(), [] as Array[StringName], "no pause reason left")
	assert_eq(boss.phase(), Flagship.Phase.DESPERATE, "DESPERATE")
	assert_eq(_cleared, [] as Array[int], "not cleared before the Flagship dies")
	# The core's death: the chain and boss_defeated, then the outro.
	core.apply_damage(core.hp, null)
	assert_eq(boss.phase(), Flagship.Phase.DYING, "DYING")
	var end_ms: int = Time.get_ticks_msec() + int((Config.num("feedback.boss_death_chain_s") + 5.0) * 1000.0)
	while channel.current_sequence() != FINAL_LINE and _cleared.is_empty() and Time.get_ticks_msec() < end_ms:
		await _wait(0.05)
	assert_eq(_defeated.size(), 1, "boss_defeated once")
	assert_eq(_flagships().size(), 0, "the Flagship is gone")
	# Isolde's final line: a paused story outro before the clear.
	assert_eq(channel.current_sequence(), FINAL_LINE, "Isolde's final line plays as the outro")
	assert_true(get_tree().paused, "the outro is a paused story")
	assert_true(PauseArbiter.has_reason(&"story"), "with the story reason")
	assert_true(_panel().visible, "in the centred panel")
	assert_eq((_panel().get_node("Panel/Name") as Label).text, "ISOLDE")
	assert_eq(_cleared, [] as Array[int], "no level_cleared before the click-through")
	assert_false(_director().is_level_cleared(), "the director hasn't cleared the level yet")
	assert_eq(_scene_calls, [] as Array[String], "no scene change yet")
	assert_eq(_read_save(), [], "no save before the click-through")
	_click_through()
	# The clear, the save and the end screen.
	assert_eq(_cleared, [3] as Array[int], "level_cleared(3) once, after the click-through")
	assert_true(_director().is_level_cleared(), "the director cleared the level")
	assert_eq(_read_save(), [1, 3, GameState.energy], "the save written with level 3 and the energy")
	assert_eq(_scene_calls, [SceneRouter.END_SCENE_PATH] as Array[String], "the router went to the end screen once")
	assert_eq(GameState.highest_unlocked_level, 3, "complete_level(3) records level 3 as the highest")
	assert_eq(GameState.current_level_id, "", "no level id on the end screen")
	assert_eq(GameState.final_choice, choice, "the Final Choice kept")
	await _wait(0.3)
	assert_eq(_defeated.size(), 1, "still one boss_defeated")
	assert_eq(_cleared, [3] as Array[int], "still cleared exactly once")
	assert_eq(_scene_calls.size(), 1, "still one scene change")
	assert_eq(_lines_matching("[INFO][beat] Level 3 outro 'l3_isolde_final'").size(), 1, "one outro line")
	assert_eq(_lines_matching("[INFO][wave] Level 3 cleared").size(), 1, "one level clear line")


# --- Acceptance 1: the shipped flags ---------------------------------------------

## The whole level with the shipped flags: the briefing, the three defence waves
## (Hunter Wasps skipped), the taunt, the boss wave, then the Flagship driven
## through the turrets, the clamp, the Final Choice (OFFER SURRENDER), the
## response and the core's death to one boss_defeated; Isolde's final line
## paused before the clear, then one level_cleared(3), the save and the end
## screen.
func test_shipped_flags_play_level_3_through_the_final_line_to_the_end_screen() -> void:
	assert_false(Config.flag("hunter_wasp"), "shipped: hunter_wasp off")
	assert_true(Config.flag("isolde_interruptions"), "shipped: interruptions on")
	_make_level()
	_start_through_briefing()
	await _kill_through_wave(1)
	_check_wave_2(false)
	await _kill_through_wave(2)
	await _play_wave_3_into_the_boss(true)
	await _drive_flagship_to_the_end_screen(0, &"surrender", &"l3_isolde_refuse_surrender")
	assert_eq(_requested, [BRIEFING, TAUNT, FINAL_CHOICE, FINAL_LINE] as Array[StringName], "comms request order")
	assert_eq(_lines_matching("Ally 'ryn' spawned").size(), 1, "Ryn spawned once")
	_assert_clean_log()


# --- Acceptance 3: every flag on, exactly-once beats -------------------------------

## Every flags.json key on (the Hunter Wasps counted in W2), played from wave 1
## to the end screen choosing DESTROY HER: no stall, spawn clamp or error, and
## the Final Choice, the refusal and the final line each fire exactly once.
func test_all_flags_on_play_to_the_end_screen_with_each_beat_once() -> void:
	var all_on: Dictionary = {}
	var shipped: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Config.DEFAULT_FLAGS_PATH))
	for key: Variant in shipped:
		all_on[key] = true
	assert_gt(all_on.size(), 0, "flags.json has keys")
	_load_flags(all_on)
	_make_level()
	_start_through_briefing()
	await _kill_through_wave(1)
	_check_wave_2(true)
	await _kill_through_wave(2)
	await _play_wave_3_into_the_boss(true)
	await _drive_flagship_to_the_end_screen(1, &"destroy", &"l3_isolde_refuse_destroy")
	assert_eq(_requested, [BRIEFING, TAUNT, FINAL_CHOICE, FINAL_LINE] as Array[StringName], "comms request order")
	assert_eq(_choices, [&"destroy"] as Array[StringName], "final_choice_made exactly once")
	assert_eq(_lines_matching("Story sequence 'l3_final_choice': final choice shown").size(), 1, "the Final Choice shown once")
	assert_eq(_lines_matching("Final choice '").size(), 1, "one response started")
	assert_eq(_lines_matching("Final choice 'destroy': response 'l3_isolde_refuse_destroy' started").size(), 1, "the refusal started once")
	assert_eq(_requested.count(FINAL_LINE), 1, "the final line requested once")
	assert_eq(_lines_matching("Story sequence 'l3_isolde_final' started").size(), 1, "the final line started once")
	assert_eq(_scene_calls, [SceneRouter.END_SCENE_PATH] as Array[String], "one change to the end screen")
	_assert_clean_log()


# --- Acceptance 2: hunter_wasp on --------------------------------------------------

## hunter_wasp on: wave 2 counts 8 including the 4 Hunter Wasps and clears into
## wave 3.
func test_hunter_wasp_on_counts_the_hunters_and_clears_wave_2() -> void:
	_load_flags({"hunter_wasp": true})
	_make_level()
	_start_through_briefing()
	await _kill_through_wave(1)
	_check_wave_2(true)
	await _kill_through_wave(2)
	assert_eq(_director().wave_number(), 3, "wave 2 cleared into wave 3")
	assert_eq(_director().total_count(), 24, "wave 3: 24 counted")
	assert_false(get_tree().paused, "no pause")
	_assert_clean_log()


# --- Acceptance 2: isolde_interruptions off ---------------------------------------

## isolde_interruptions off: wave 3 passes 0.25 and clears into the boss wave
## without the taunt ever being requested; the boss music starts.
func test_isolde_interruptions_off_never_requests_the_taunt() -> void:
	_load_flags({"isolde_interruptions": false})
	_make_level()
	_start_through_briefing()
	await _kill_through_wave(1)
	_check_wave_2(false)
	await _kill_through_wave(2)
	await _play_wave_3_into_the_boss(false)
	assert_false(_requested.has(TAUNT), "the taunt was never requested")
	assert_eq(_requested, [BRIEFING] as Array[StringName], "only the briefing was requested")
	assert_false(get_tree().paused, "no pause")
	_assert_clean_log()
