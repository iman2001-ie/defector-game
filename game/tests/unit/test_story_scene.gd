extends GutTest
## The comms-only story scene (Story 5.5, FR41, R15): story.tscn plays
## SceneRouter.story_sequence() through its own Comms/CommsChannel on a panel
## with no dim, with a visible cursor, no HUD and no PauseMenu (Esc does
## nothing). When that sequence finishes (also the deferred finish of an
## unknown id) it calls SceneRouter.finish_story() once, which loads the
## pending level. Run with nothing pending it goes to the title. Story 7.8:
## with ending_council pending before the end screen (STORY_NEXT_END) the
## click-through opens the end screen once, with the same lines whatever the
## Final Choice was.
## The scene change is a recorder; input goes through
## get_viewport().push_input like a real click.

const STORY_SCENE: PackedScene = preload("res://scenes/story/story.tscn")
const TITLE_SCENE: PackedScene = preload("res://scenes/title/title.tscn")
const LEVEL_SELECT_SCENE: PackedScene = preload("res://scenes/title/level_select.tscn")
const TEST_SAVE: String = "user://test_story_scene_save.cfg"
const CLICK_AT: Vector2 = Vector2(960, 900)
## More clicks than any 6-10 line story needs (two per line).
const MAX_CLICKS: int = 40

var _calls: Array[String] = []
var _lines: Array[String] = []
var _story: StoryScene
## The viewport mouse before the test, restored after it (other suites read it).
var _mouse_before: Vector2 = Vector2.ZERO


func before_each() -> void:
	_mouse_before = get_viewport().get_mouse_position()
	_calls.clear()
	_lines.clear()
	_story = null
	SaveManager.save_path = TEST_SAVE
	_delete_save()
	GameState.highest_unlocked_level = 1
	GameState.all_levels_unlocked = false
	SceneRouter.change_scene = _record
	Log.sink = _capture
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)


func after_each() -> void:
	Audio.stop_music(0.0)
	Log.sink = Callable()
	_story = null
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = _mouse_before
	motion.global_position = _mouse_before
	get_viewport().push_input(motion, true)
	SceneRouter._story_id = &""
	SceneRouter._story_next_level = 0
	SceneRouter.change_scene = SceneRouter.default_change_scene()
	_delete_save()
	SaveManager.save_path = SaveManager.DEFAULT_SAVE_PATH
	GameState.energy = 0
	GameState.level_start_energy = 0
	GameState.current_level_id = ""
	GameState.is_retry = false
	GameState.highest_unlocked_level = 1
	GameState.all_levels_unlocked = false
	GameState.final_choice = &""
	Feedback.reset()
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _delete_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)


func _record(path: String) -> Error:
	_calls.append(path)
	return OK


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _count_starting(prefix: String) -> int:
	var n: int = 0
	for line: String in _lines:
		if line.begins_with(prefix):
			n += 1
	return n


## Instances story.tscn with whatever the router has pending.
func _make() -> StoryScene:
	_story = STORY_SCENE.instantiate() as StoryScene
	add_child_autofree(_story)
	return _story


## The router's goto_story (recorded), then the scene it would load.
func _make_with(id: StringName, next_level: int) -> StoryScene:
	SceneRouter.goto_story(id, next_level)
	return _make()


func _channel() -> CommsChannel:
	return _story.get_node("Comms/CommsChannel") as CommsChannel


func _panel() -> CommsPanel:
	return _story.get_node("Comms/CommsPanel") as CommsPanel


func _mouse(pressed: bool) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = CLICK_AT
	event.global_position = CLICK_AT
	return event


func _click() -> void:
	get_viewport().push_input(_mouse(true), true)
	get_viewport().push_input(_mouse(false), true)


## Clicks until the channel shows nothing (or MAX_CLICKS); returns the clicks used.
func _click_through() -> int:
	var clicks: int = 0
	while _channel().is_showing() and clicks < MAX_CLICKS:
		_click()
		clicks += 1
	return clicks


func _count(path: String) -> int:
	return _calls.count(path)


# --- Structure -------------------------------------------------------------------

func test_scene_shape() -> void:
	SceneRouter.goto_story(&"opening_main", 1)
	var story: StoryScene = STORY_SCENE.instantiate() as StoryScene
	assert_true(story is Control, "a Control root")
	assert_not_null(story.theme, "the shared theme")
	assert_eq(story.mouse_filter, Control.MOUSE_FILTER_IGNORE, "clicks pass to the channel")
	var comms: CanvasLayer = story.get_node("Comms") as CanvasLayer
	assert_eq(comms.layer, 20, "Comms layer 20")
	var channel: CommsChannel = story.get_node("Comms/CommsChannel") as CommsChannel
	var box: CommsBox = story.get_node("Comms/CommsBox") as CommsBox
	var panel: CommsPanel = story.get_node("Comms/CommsPanel") as CommsPanel
	assert_not_null(channel)
	assert_not_null(box)
	assert_not_null(panel)
	assert_lt(box.get_index(), panel.get_index(), "the box before the panel, so the panel draws on top")
	assert_false(panel.dim, "no dim on the story scene")
	for name: String in ["HUD", "WaveDirector", "Overlay", "PauseMenu", "DebugTools", "World"]:
		assert_null(story.find_child(name, true, false), "no %s" % name)
	add_child_autofree(story)
	_story = story
	assert_eq(channel.panel, panel, "panel wired")
	assert_eq(channel.box, box, "box wired")


## Story 8.2: the story scene has the space_1 backdrop as its first child, so
## it draws behind the comms.
func test_space_backdrop_is_the_first_child() -> void:
	var story: StoryScene = _make_with(&"opening_main", 1)
	var bg: LevelBackground = story.get_node_or_null("Background") as LevelBackground
	assert_not_null(bg, "a LevelBackground")
	if bg == null:
		return
	assert_eq(bg.get_index(), 0, "the first child")
	assert_eq(bg.background_id(), "space_1")
	assert_eq(bg.background_id(), LevelBackground.MENU_BACKGROUND)
	assert_not_null(bg.tile_texture(), "tiles the space texture")
	assert_false(bg.shows_throne_world())


## Playtest 2026-10-14: the council epilogue keeps the throne world of Level 3
## and the end screen behind the comms, instead of cutting to dark space.
func test_epilogue_shows_the_throne_world() -> void:
	var story: StoryScene = _make_with(SceneRouter.ENDING_SEQUENCE, SceneRouter.STORY_NEXT_END)
	var bg: LevelBackground = story.get_node_or_null("Background") as LevelBackground
	assert_not_null(bg, "a LevelBackground")
	if bg == null:
		return
	assert_eq(bg.background_id(), LevelBackground.THRONE_WORLD)
	assert_true(bg.shows_throne_world(), "the planet is drawn")


func test_backdrop_for_picks_the_throne_world_only_for_the_epilogue() -> void:
	assert_eq(StoryScene.backdrop_for(&"ending_council"), LevelBackground.THRONE_WORLD)
	assert_eq(StoryScene.backdrop_for(&"opening_main"), LevelBackground.MENU_BACKGROUND)
	assert_eq(StoryScene.backdrop_for(&""), LevelBackground.MENU_BACKGROUND)


# --- I/O rows ----------------------------------------------------------------------

func test_scene_plays_the_pending_story() -> void:
	_make_with(&"opening_main", 1)
	assert_eq(_story.sequence(), &"opening_main")
	assert_eq(_channel().current_sequence(), &"opening_main", "the channel plays the opening")
	assert_eq(_channel().line_index(), 0, "line 0")
	assert_true(_panel().visible, "panel showing")
	assert_false((_panel().get_node("Dim") as Control).visible, "dim hidden")
	assert_eq(PauseArbiter.reasons(), [&"story"] as Array[StringName], "paused with story")
	assert_true(get_tree().paused, "tree paused")
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "cursor visible")
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH] as Array[String], "no level yet")


## Story 8.4: the scene logs one `[INFO][beat] Story '<id>'` line for the
## sequence it plays (the beat_audit.py contract), the opening and the epilogue alike.
func test_opening_logs_its_story_beat() -> void:
	_make_with(&"opening_main", 1)
	assert_eq(_count_starting("[INFO][beat] Story 'opening_main'"), 1, "one opening beat")
	assert_true(_lines.has("[INFO][beat] Story 'opening_main'"), "the exact text")
	_click_through()
	assert_eq(_count_starting("[INFO][beat] Story "), 1, "logged once, not per line or on finish")


func test_epilogue_logs_its_story_beat() -> void:
	_make_with(SceneRouter.ENDING_SEQUENCE, SceneRouter.STORY_NEXT_END)
	assert_true(_lines.has("[INFO][beat] Story 'ending_council'"), "the exact text")
	assert_eq(_count_starting("[INFO][beat] Story "), 1, "one beat line")


## Playtest pt7-e: the epilogue starts the gentle epilogue track after
## audio.epilogue_music_delay_s (real time, while the story pause holds the
## tree), fading in; the opening plays no music.
func test_epilogue_starts_its_track_after_the_delay() -> void:
	var audio_tuning: Dictionary = Config.tuning["audio"] as Dictionary
	var delay_was: Variant = audio_tuning["epilogue_music_delay_s"]
	audio_tuning["epilogue_music_delay_s"] = 0.2
	Audio.stop_music(0.0)
	_make_with(SceneRouter.ENDING_SEQUENCE, SceneRouter.STORY_NEXT_END)
	assert_eq(Audio.current_music(), &"", "silent at first")
	assert_true(get_tree().paused, "the story pause holds the tree")
	# The story pause holds the tree, so wait on an always-processing timer.
	await get_tree().create_timer(0.4, true, false, true).timeout
	assert_eq(Audio.current_music(), StoryScene.EPILOGUE_MUSIC, "the epilogue track plays")
	assert_eq(_count_starting("[INFO][audio] Music 'epilogue' playing (%.2f s fade-in)" % Config.num("audio.music_fade_in_s")), 1, "fading in")
	audio_tuning["epilogue_music_delay_s"] = delay_was
	Audio.stop_music(0.0)


func test_opening_plays_no_music() -> void:
	var audio_tuning: Dictionary = Config.tuning["audio"] as Dictionary
	var delay_was: Variant = audio_tuning["epilogue_music_delay_s"]
	audio_tuning["epilogue_music_delay_s"] = 0.1
	Audio.stop_music(0.0)
	_make_with(&"opening_main", 1)
	await get_tree().create_timer(0.3, true, false, true).timeout
	assert_eq(Audio.current_music(), &"", "no track for the opening")
	audio_tuning["epilogue_music_delay_s"] = delay_was


func test_no_pending_story_logs_no_beat() -> void:
	_make()
	assert_eq(_count_starting("[INFO][beat]"), 0, "no beat line")
	assert_eq(_count_starting("[WARN][scene] Story scene has no pending sequence"), 1, "the warning stays")
	assert_push_warning("no pending sequence")


func test_click_through_loads_level_1_once() -> void:
	GameState.energy = 30
	_make_with(&"opening_main", 1)
	var clicks: int = _click_through()
	assert_lt(clicks, MAX_CLICKS, "the story ended")
	assert_false(PauseArbiter.has_reason(&"story"), "pause lifted")
	assert_false(get_tree().paused)
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "the scene declared a visible cursor")
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH, SceneRouter.LEVEL_SCENE_PATH] as Array[String], "the level path once")
	assert_eq(GameState.current_level_id, "1")
	assert_false(GameState.is_retry)
	assert_eq(GameState.energy, 30, "energy kept")
	assert_eq(SceneRouter.story_sequence(), &"", "pending story cleared")
	# A late click and a repeated finish change nothing more.
	_click()
	Events.comms_sequence_finished.emit(&"opening_main")
	assert_eq(_count(SceneRouter.LEVEL_SCENE_PATH), 1, "finish_story called once")
	assert_eq(_count_starting("[WARN][scene]"), 0, "no warning")


func test_other_ids_are_ignored() -> void:
	_make_with(&"opening_main", 1)
	Events.comms_sequence_finished.emit(&"dev_comms_check")
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH] as Array[String], "still on the story")
	assert_true(_channel().is_showing())


func test_unknown_id_still_loads_the_level() -> void:
	_make_with(&"no_such_story", 1)
	assert_false(PauseArbiter.is_paused(), "nothing to pause for")
	await wait_process_frames(2)
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH, SceneRouter.LEVEL_SCENE_PATH] as Array[String], "no soft-lock")
	assert_eq(GameState.current_level_id, "1")
	assert_eq(_count_starting("[ERROR][comms] Unknown comms sequence 'no_such_story'"), 1, "the channel logs it")
	assert_push_error("no_such_story")


func test_esc_does_nothing() -> void:
	_make_with(&"opening_main", 1)
	_panel().complete_line()
	var esc: InputEventAction = InputEventAction.new()
	esc.action = &"pause"
	esc.pressed = true
	get_viewport().push_input(esc, true)
	var release: InputEventAction = InputEventAction.new()
	release.action = &"pause"
	release.pressed = false
	get_viewport().push_input(release, true)
	assert_false(PauseArbiter.has_reason(&"menu"), "no menu reason")
	assert_eq(PauseArbiter.reasons(), [&"story"] as Array[StringName], "still the story pause")
	assert_eq(_channel().line_index(), 0, "line unchanged")
	assert_eq(_channel().current_sequence(), &"opening_main")
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH] as Array[String], "no scene change")


func test_no_pending_story_goes_to_the_title() -> void:
	_make()
	assert_eq(_story.sequence(), &"")
	assert_eq(_calls, [SceneRouter.TITLE_SCENE_PATH] as Array[String], "the title")
	assert_false(PauseArbiter.is_paused(), "nothing requested")
	assert_eq(_count_starting("[WARN][scene] Story scene has no pending sequence"), 1)
	assert_push_warning("no pending sequence")


# --- Acceptance -------------------------------------------------------------------

## Playtest 2026-10-13: PLAY is always a new run from level 1 at 0 energy,
## whatever the unlock.
func test_title_play_opens_with_the_story_then_level_1() -> void:
	GameState.energy = 10
	GameState.highest_unlocked_level = 3
	var title: TitleScreen = TITLE_SCENE.instantiate() as TitleScreen
	title.quit_game = func() -> void: pass
	add_child_autofree(title)
	(title.get_node("Buttons/Play") as Button).pressed.emit()
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH] as Array[String], "the story scene")
	assert_eq(SceneRouter.story_sequence(), &"opening_main")
	assert_eq(SceneRouter.story_next_level(), 1)
	title.queue_free()
	await wait_process_frames(1)
	_make()
	_click_through()
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH, SceneRouter.LEVEL_SCENE_PATH] as Array[String], "then the level")
	assert_eq(GameState.current_level_id, "1")
	assert_false(GameState.is_retry)
	assert_eq(GameState.energy, 0, "a new run starts at 0")
	assert_eq(GameState.level_start_energy, 0)


func test_level_select_card_1_opens_with_the_story_then_level_1() -> void:
	GameState.highest_unlocked_level = 2
	var screen: LevelSelectScreen = LEVEL_SELECT_SCENE.instantiate() as LevelSelectScreen
	add_child_autofree(screen)
	(screen.get_node("Cards/Card1") as Button).pressed.emit()
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH] as Array[String], "the story scene")
	assert_eq(SceneRouter.story_sequence(), &"opening_main")
	assert_eq(SceneRouter.story_next_level(), 1)
	screen.queue_free()
	await wait_process_frames(1)
	_make()
	_click_through()
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH, SceneRouter.LEVEL_SCENE_PATH] as Array[String], "then the level")
	assert_eq(GameState.current_level_id, "1")
	assert_false(GameState.is_retry)


func test_retry_and_restart_after_the_opening_never_replay_it() -> void:
	_make_with(&"opening_main", 1)
	_click_through()
	SceneRouter.retry_level()
	SceneRouter.restart_level()
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH, SceneRouter.LEVEL_SCENE_PATH, SceneRouter.LEVEL_SCENE_PATH, SceneRouter.LEVEL_SCENE_PATH] as Array[String])
	assert_true(GameState.is_retry)


# --- Story 7.8: the council epilogue ----------------------------------------------

## Clicks through like _click_through(), recording [speaker, text] of each line
## the panel shows (one entry per line, in order).
func _click_through_recording() -> Array[Array]:
	var shown: Array[Array] = []
	var last_line: int = -1
	var clicks: int = 0
	while _channel().is_showing() and clicks < MAX_CLICKS:
		if _channel().line_index() != last_line:
			last_line = _channel().line_index()
			shown.append([_panel().current_speaker(), (_panel().get_node("Panel/Text") as Label).text])
		_click()
		clicks += 1
	return shown


## [speaker, text] of every ending_council line as the data lists them.
func _ending_lines() -> Array[Array]:
	var out: Array[Array] = []
	for line: Variant in Config.sequence(SceneRouter.ENDING_SEQUENCE).get("lines", []) as Array:
		var entry: Dictionary = line as Dictionary
		out.append([StringName(str(entry.get("speaker"))), str(entry.get("text"))])
	return out


func test_ending_council_plays_then_opens_the_end_screen_once() -> void:
	GameState.energy = 80
	GameState.final_choice = &"destroy"
	_make_with(SceneRouter.ENDING_SEQUENCE, SceneRouter.STORY_NEXT_END)
	assert_eq(_story.sequence(), &"ending_council")
	assert_eq(_channel().current_sequence(), &"ending_council", "the channel plays the epilogue")
	assert_eq(_channel().line_index(), 0, "line 0")
	assert_true(_panel().visible, "panel showing")
	assert_eq(PauseArbiter.reasons(), [&"story"] as Array[StringName], "paused with story")
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH] as Array[String], "no end screen yet")
	var clicks: int = _click_through()
	assert_lt(clicks, MAX_CLICKS, "the epilogue ended")
	assert_false(PauseArbiter.has_reason(&"story"), "pause lifted")
	assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH, SceneRouter.END_SCENE_PATH] as Array[String], "then the end screen once")
	assert_eq(GameState.current_level_id, "", "no level id")
	assert_eq(GameState.energy, 80, "energy kept")
	assert_eq(GameState.final_choice, &"destroy", "the Final Choice kept")
	assert_eq(SceneRouter.story_sequence(), &"", "pending story cleared")
	assert_eq(SceneRouter.story_next_level(), 0)
	# A late click and a repeated finish change nothing more.
	_click()
	Events.comms_sequence_finished.emit(SceneRouter.ENDING_SEQUENCE)
	assert_eq(_count(SceneRouter.END_SCENE_PATH), 1, "finish_story called once")
	assert_eq(_count(SceneRouter.TITLE_SCENE_PATH), 0, "never the title")
	assert_eq(_count_starting("[WARN][scene]"), 0, "no warning")
	assert_false(FileAccess.file_exists(TEST_SAVE), "nothing saves after the epilogue")


## The epilogue is choice-neutral: whatever GameState.final_choice holds, the
## same lines (same count, speakers and texts as the data) play, then the end
## screen.
func test_ending_council_is_the_same_for_every_final_choice() -> void:
	var expected: Array[Array] = _ending_lines()
	assert_eq(expected.size(), 6, "six lines in the data")
	for choice: StringName in [&"surrender", &"destroy", &""]:
		_calls.clear()
		GameState.final_choice = choice
		_make_with(SceneRouter.ENDING_SEQUENCE, SceneRouter.STORY_NEXT_END)
		var shown: Array[Array] = _click_through_recording()
		assert_eq(shown, expected, "choice '%s': the same speakers and texts as the data" % choice)
		assert_eq(_calls, [SceneRouter.STORY_SCENE_PATH, SceneRouter.END_SCENE_PATH] as Array[String], "choice '%s': then the end screen" % choice)
		assert_eq(GameState.final_choice, choice, "choice '%s' untouched" % choice)
		remove_child(_story)
		_story.queue_free()
		_story = null
		await wait_process_frames(1)
