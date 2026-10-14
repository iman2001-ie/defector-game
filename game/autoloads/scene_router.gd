extends Node
## The only place that changes scenes (architecture boundary 4; the debug F5
## reload and the --stress redirect in boot.gd / level.gd are the debug-only
## exceptions).
##
## Every change goes through _change_to(), which ends any hit-stop and logs one
## INFO scene line before the swap, then drops every pause reason
## (PauseArbiter.clear()) right after it. change_scene_to_file removes the
## outgoing scene from the tree synchronously (the incoming one is added at the
## end of the frame), so `resumed` never reaches the dead level's Player while it
## is still in the tree, and the new scene's _ready pushes are not wiped (DW-61).
##
## - goto_title(): the title screen (scenes/title/title.tscn). Restores
##   highest_unlocked_level from the save, zeroes the energy and clears the
##   retry flag through restore_saved_progress() (which F5 also calls), then
##   clears the level id.
## - goto_level_select(): the Level Select screen
##   (scenes/title/level_select.tscn, Story 4.3). Leaves GameState alone and
##   writes no save.
## - start_new(id): a new run from a menu (PLAY always starts level 1, a Level
##   Select card any unlocked level): energy 0, then start_level(id) (playtest
##   2026-10-13).
## - start_level(id): a fresh (non-retry) attempt of level `id` in level.tscn,
##   carrying the current energy. Refused (logged) while Config.load_error is set.
##   Level OPENING_LEVEL_ID ("1") goes through the opening story first
##   (goto_story(OPENING_SEQUENCE, 1), Story 5.5, R15): PLAY and Level Select
##   both reach start_level, so both get it.
## - goto_story(id, next_level): the comms-only story scene
##   (scenes/story/story.tscn) for sequence `id`, then level `next_level`, or the
##   end screen when `next_level` is STORY_NEXT_END (Story 7.8, the council
##   epilogue). Stores the pending id and target (story_sequence(),
##   story_next_level()), clears is_retry and keeps the energy. Refused (logged)
##   while Config.load_error is set.
## - finish_story(): the story scene calls it when its sequence finished. Clears
##   the pending story, then starts the pending level as a fresh attempt
##   straight into level.tscn (never the opening again), or goes to the end
##   screen (goto_end()) when the target is STORY_NEXT_END; with none pending it
##   warns and goes to the title.
## - retry_level() / restart_level(): both reload level.tscn as a retry
##   (ADR-004), which reads GameState.current_level_id, so the same level runs
##   again from wave 1. A death's Retry wipes the energy to 0; the pause menu's
##   Restart Level puts back the energy the attempt started with
##   (GameState.level_start_energy, playtest 2026-10-13). No counter, no limit.
## - complete_level(n): a cleared campaign level (1..progression.level_count)
##   raises the unlock, saves (the only save in the game) and starts level n+1
##   with the carried energy. After the last level it plays the council epilogue
##   (goto_story(ENDING_SEQUENCE, STORY_NEXT_END), Story 7.8) when the
##   council_epilogue flag is on and the config loaded, else it goes to the end
##   screen at once (goto_end(), Story 7.7). The level scene calls it on
##   Events.level_cleared; the router itself doesn't listen to Events (bare
##   WaveDirector tests clear levels too).
## - goto_end(): the end screen (scenes/end/end_screen.tscn, Story 7.7), straight
##   from complete_level or after the council epilogue through finish_story().
##   Clears the level id and the retry flag, keeps the energy and
##   GameState.final_choice and writes no save.
##
## The router also owns the F11 window toggle (Story 4.5, FR59): it is the
## PROCESS_MODE_ALWAYS autoload present under every scene, so
## _unhandled_input flips toggle_fullscreen between borderless fullscreen and
## windowed in any scene, paused or not, in debug and release. The choice is
## never persisted: a fresh launch is always fullscreen (project.godot mode 3).

const LEVEL_SCENE_PATH: String = "res://scenes/level/level.tscn"
const TITLE_SCENE_PATH: String = "res://scenes/title/title.tscn"
const LEVEL_SELECT_SCENE_PATH: String = "res://scenes/title/level_select.tscn"
const STORY_SCENE_PATH: String = "res://scenes/story/story.tscn"
const END_SCENE_PATH: String = "res://scenes/end/end_screen.tscn"
## The opening comms sequence (data/dialogue/opening.json) and the level it
## opens: scene-flow wiring like the paths above, not tuning (Story 5.5).
const OPENING_SEQUENCE: StringName = &"opening_main"
const OPENING_LEVEL_ID: String = "1"
## The council epilogue (data/dialogue/ending.json, Story 7.8) and the
## goto_story target that means "the end screen, not a level": scene-flow wiring
## like the opening constants, not tuning.
const ENDING_SEQUENCE: StringName = &"ending_council"
const STORY_NEXT_END: int = -1

## Changes the scene to a file path. Defaults to get_tree().change_scene_to_file
## in _ready; tests inject a recorder (calling the real one in GUT would replace
## the test runner's scene).
var change_scene: Callable
## Returns the current DisplayServer.WindowMode. Defaults to
## DisplayServer.window_get_mode in _ready; tests inject a recorder.
var get_window_mode: Callable
## Sets a DisplayServer.WindowMode. Defaults to DisplayServer.window_set_mode in
## _ready; tests inject a recorder so the real window never changes.
var set_window_mode: Callable

## The story the story scene plays (&"" when none is pending) and the level
## finish_story() starts after it (0 when none, STORY_NEXT_END for the end
## screen).
var _story_id: StringName = &""
var _story_next_level: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not change_scene.is_valid():
		change_scene = default_change_scene()
	if not get_window_mode.is_valid():
		get_window_mode = default_get_window_mode()
	if not set_window_mode.is_valid():
		set_window_mode = default_set_window_mode()


## F11 (the toggle_fullscreen action, never a raw key; echoes ignored) toggles
## the window mode and marks the event handled.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		toggle_window_mode()
		get_viewport().set_input_as_handled()


## The real scene change (get_tree().change_scene_to_file); tests restore it.
func default_change_scene() -> Callable:
	return get_tree().change_scene_to_file


## The real window-mode getter (DisplayServer.window_get_mode); tests restore it.
func default_get_window_mode() -> Callable:
	return DisplayServer.window_get_mode


## The real window-mode setter (DisplayServer.window_set_mode); tests restore it.
func default_set_window_mode() -> Callable:
	return DisplayServer.window_set_mode


## The mode F11 switches to: any fullscreen mode (borderless or exclusive) goes
## windowed; every other mode (windowed, maximized, minimized) goes borderless
## fullscreen. Never exclusive fullscreen.
static func toggled_window_mode(mode: DisplayServer.WindowMode) -> DisplayServer.WindowMode:
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		return DisplayServer.WINDOW_MODE_WINDOWED
	return DisplayServer.WINDOW_MODE_FULLSCREEN


## Flips the window between borderless fullscreen and windowed and logs one INFO
## scene line. Writes nothing to disk.
func toggle_window_mode() -> void:
	var current: DisplayServer.WindowMode = get_window_mode.call() as DisplayServer.WindowMode
	var next: DisplayServer.WindowMode = toggled_window_mode(current)
	set_window_mode.call(next)
	var label: String = "windowed" if next == DisplayServer.WINDOW_MODE_WINDOWED else "fullscreen"
	Log.info("scene", "Window mode: %s" % label)


## Retry after a death: reloads level.tscn with the same
## GameState.current_level_id, with 0 energy and is_retry set.
func retry_level() -> void:
	_reload_level(0, "Retry")


## Pause menu Restart Level: reloads level.tscn with the same
## GameState.current_level_id and is_retry set, with the energy the attempt
## started with (GameState.level_start_energy), so a restart neither wipes nor
## banks energy.
func restart_level() -> void:
	_reload_level(GameState.level_start_energy, "Restart")


## A new run from a menu (title PLAY, a Level Select card): 0 energy, then
## start_level(id). Refused like start_level while Config.load_error is set
## (the energy is still zeroed; it is never saved).
func start_new(id: String) -> void:
	GameState.energy = 0
	start_level(id)


## Starts level `id` (data/levels/level_<id>.json) as a fresh attempt: sets
## GameState.current_level_id, clears is_retry and keeps the current energy.
## While Config.load_error is set no level can start: logs an ERROR and changes
## nothing.
## Level OPENING_LEVEL_ID plays the opening story first (goto_story); every
## other id loads level.tscn at once. Leaving the menus fades the menu track
## out (playtest pt7-k), so it never carries into the game.
func start_level(id: String) -> void:
	if not Config.load_error.is_empty():
		Log.error("scene", "Cannot start level '%s': config failed to load (%s)" % [id, Config.load_error])
		return
	if Audio.current_music() == Audio.MENU_MUSIC:
		Audio.stop_music()
	if id == OPENING_LEVEL_ID:
		goto_story(OPENING_SEQUENCE, int(id))
		return
	_load_level(id)


## The comms-only story scene for sequence `id`, followed by level
## `next_level`, or by the end screen when `next_level` is STORY_NEXT_END
## (finish_story()). Clears is_retry and keeps the energy. While
## Config.load_error is set it logs an ERROR and changes nothing.
func goto_story(id: StringName, next_level: int) -> void:
	if not Config.load_error.is_empty():
		Log.error("scene", "Cannot play story '%s': config failed to load (%s)" % [id, Config.load_error])
		return
	_story_id = id
	_story_next_level = next_level
	GameState.is_retry = false
	var target: String = "the end screen" if next_level == STORY_NEXT_END else "level %d" % next_level
	_change_to(STORY_SCENE_PATH, "Story '%s' before %s" % [id, target])


## The pending story sequence id (&"" when none).
func story_sequence() -> StringName:
	return _story_id


## The level the pending story leads to (0 when none, STORY_NEXT_END when it
## leads to the end screen).
func story_next_level() -> int:
	return _story_next_level


## The story scene's sequence finished: clears the pending story, then starts
## the pending level as a fresh attempt (energy kept) straight into level.tscn,
## without the opening check, or goes to the end screen (goto_end()) when the
## target is STORY_NEXT_END. With no pending story it warns and goes to the
## title.
func finish_story() -> void:
	var next_level: int = _story_next_level
	_story_id = &""
	_story_next_level = 0
	if next_level == STORY_NEXT_END:
		goto_end()
		return
	if next_level < 1:
		Log.warn("scene", "No pending story to finish; going to the title")
		goto_title()
		return
	_load_level(str(next_level))


## The title screen: the unlock restored from the save and energy 0
## (restore_saved_progress()), no level id. Writes no save. Fades out any music
## (the end screen's epilogue track, or a level track when quitting to the
## title; playtest pt7-e) except the menu track, which the title keeps playing
## (playtest pt7-k: the title then crossfades into it). A broken config stops
## the music at once (no fade time can be read then).
func goto_title() -> void:
	if not Config.load_error.is_empty():
		Audio.stop_music(0.0)
	elif Audio.current_music() != Audio.MENU_MUSIC:
		Audio.stop_music()
	restore_saved_progress()
	GameState.current_level_id = ""
	_change_to(TITLE_SCENE_PATH, "Going to the title screen")


## Restores highest_unlocked_level from the save (clamped into
## 1..progression.level_count while the config is healthy), zeroes the energy
## (energy is never saved; every menu start begins at 0) and clears is_retry.
## Touches no other field, changes no scene and writes no save. goto_title()
## and the debug F5 reload call it.
func restore_saved_progress() -> void:
	var progress: Dictionary = SaveManager.load_progress()
	var highest: int = int(progress.get(SaveManager.KEY_HIGHEST, SaveManager.DEFAULT_HIGHEST))
	if Config.load_error.is_empty():
		highest = clampi(highest, 1, maxi(Config.int_("progression.level_count"), 1))
	GameState.highest_unlocked_level = highest
	GameState.energy = 0
	GameState.is_retry = false


## The Level Select screen. Touches no GameState field (a card starts its level
## through start_new, at 0 energy) and writes no save.
func goto_level_select() -> void:
	_change_to(LEVEL_SELECT_SCENE_PATH, "Going to level select")


## Level `n` was cleared. A campaign level (1..progression.level_count) raises
## highest_unlocked_level to max(current, min(n + 1, level_count)), saves, then
## starts level n + 1 with the current energy, fading the music out first
## (playtest pt7-k). After the last level it first
## fades the music out (Audio.stop_music(), over audio.music_fade_out_s; Story
## 8.1, DW-100), so the boss track never carries on into the epilogue or the end
## screen, then plays the council epilogue (goto_story(ENDING_SEQUENCE,
## STORY_NEXT_END), Story 7.8)
## when Config.load_error is empty and the council_epilogue flag is on;
## otherwise it goes to the end screen at once (goto_end(), Story 7.7), so a
## broken config (where goto_story refuses) never strands the player on the
## cleared level. The transition happens even if the save fails. Any other id
## (the dev level is 0) is only logged.
func complete_level(n: int) -> void:
	var level_count: int = Config.int_("progression.level_count")
	if n < 1 or n > level_count:
		Log.info("scene", "Level %d cleared: not a campaign level; no save, no scene change" % n)
		return
	GameState.highest_unlocked_level = maxi(GameState.highest_unlocked_level, mini(n + 1, level_count))
	SaveManager.save()
	if n < level_count:
		# Playtest pt7-k: the level's track fades out across the change, so the
		# next level's briefing starts in silence (its own track starts at wave 1).
		Audio.stop_music()
		start_level(str(n + 1))
		return
	Audio.stop_music()
	if Config.load_error.is_empty() and Config.flag("council_epilogue"):
		goto_story(ENDING_SEQUENCE, STORY_NEXT_END)
	else:
		goto_end()


## The end screen after the last level (Story 7.7), straight from
## complete_level or after the council epilogue (finish_story(), Story 7.8): no
## level id, not a retry. Keeps the energy and GameState.final_choice and writes
## no save (the save already happened in complete_level).
func goto_end() -> void:
	GameState.current_level_id = ""
	GameState.is_retry = false
	_change_to(END_SCENE_PATH, "Going to the end screen")


## Sets the level id, clears is_retry, records the attempt's starting energy
## (GameState.level_start_energy) and loads level.tscn (energy kept).
func _load_level(id: String) -> void:
	GameState.current_level_id = id
	GameState.is_retry = false
	GameState.level_start_energy = GameState.energy
	_change_to(LEVEL_SCENE_PATH, "Starting level '%s'" % id)


## Reloads level.tscn as a retry of the current level with `energy`, which is
## also the new attempt's starting energy.
func _reload_level(energy: int, label: String) -> void:
	GameState.energy = energy
	GameState.level_start_energy = energy
	GameState.is_retry = true
	# Restart from the pause menu fades whatever plays (the boss track too); the
	# level's own wave-1 trigger brings its track back (playtest pt7-k review).
	Audio.stop_music()
	_change_to(LEVEL_SCENE_PATH, "%s: reloading level '%s'" % [label, GameState.current_level_id])


func _change_to(path: String, message: String) -> void:
	Feedback.reset()
	Log.info("scene", message)
	change_scene.call(path)
	# After the swap: the outgoing scene is already out of the tree (DW-61).
	PauseArbiter.clear()
