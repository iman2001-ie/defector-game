extends Node
## The only place that changes scenes (architecture boundary 4; the debug F5
## reload and the --stress redirect in boot.gd / level.gd are the debug-only
## exceptions).
##
## Every change goes through _change_to(), which drops every pause reason
## (PauseArbiter.clear()), ends any hit-stop and logs one INFO scene line first.
##
## - goto_title(): the title screen (scenes/title/title.tscn). Restores energy
##   and highest_unlocked_level from the save (F13: in-memory mid-level energy
##   never leaks across menus), clears the retry flag and the level id.
## - goto_level_select(): the Level Select screen
##   (scenes/title/level_select.tscn, Story 4.3). Leaves GameState alone (the
##   title's goto_title() already restored energy and unlocks) and writes no save.
## - start_level(id): a fresh (non-retry) attempt of level `id` in level.tscn,
##   carrying the current energy. Refused (logged) while Config.load_error is set.
## - restart_level(): retry is a scene reload (ADR-004). It wipes energy, marks
##   the attempt as a retry and reloads level.tscn, which reads
##   GameState.current_level_id, so the same level runs again from wave 1. There
##   is no retry counter and no limit.
## - complete_level(n): a cleared campaign level (1..progression.level_count)
##   raises the unlock, saves (the only save in the game) and starts level n+1
##   with the carried energy, or goes to the title after the last level. The
##   level scene calls it on Events.level_cleared; the router itself doesn't
##   listen to Events (bare WaveDirector tests clear levels too).

const LEVEL_SCENE_PATH: String = "res://scenes/level/level.tscn"
const TITLE_SCENE_PATH: String = "res://scenes/title/title.tscn"
const LEVEL_SELECT_SCENE_PATH: String = "res://scenes/title/level_select.tscn"

## Changes the scene to a file path. Defaults to get_tree().change_scene_to_file
## in _ready; tests inject a recorder (calling the real one in GUT would replace
## the test runner's scene).
var change_scene: Callable


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not change_scene.is_valid():
		change_scene = default_change_scene()


## The real scene change (get_tree().change_scene_to_file); tests restore it.
func default_change_scene() -> Callable:
	return get_tree().change_scene_to_file


## Retry: reloads level.tscn with the same GameState.current_level_id, with 0
## energy and is_retry set.
func restart_level() -> void:
	GameState.energy = 0
	GameState.is_retry = true
	_change_to(LEVEL_SCENE_PATH, "Retry: reloading level '%s'" % GameState.current_level_id)


## Starts level `id` (data/levels/level_<id>.json) as a fresh attempt: sets
## GameState.current_level_id, clears is_retry and keeps the current energy.
## While Config.load_error is set no level can start: logs an ERROR and changes
## nothing.
func start_level(id: String) -> void:
	if not Config.load_error.is_empty():
		Log.error("scene", "Cannot start level '%s': config failed to load (%s)" % [id, Config.load_error])
		return
	GameState.current_level_id = id
	GameState.is_retry = false
	_change_to(LEVEL_SCENE_PATH, "Starting level '%s'" % id)


## The title screen: energy and highest_unlocked_level restored from the save
## (clamped into 1..progression.level_count and 0..max energy while the config
## is healthy), not a retry, no level id. Writes no save.
func goto_title() -> void:
	var progress: Dictionary = SaveManager.load_progress()
	var highest: int = int(progress.get(SaveManager.KEY_HIGHEST, SaveManager.DEFAULT_HIGHEST))
	var energy: int = int(progress.get(SaveManager.KEY_ENERGY, SaveManager.DEFAULT_ENERGY))
	if Config.load_error.is_empty():
		highest = clampi(highest, 1, maxi(Config.int_("progression.level_count"), 1))
		energy = clampi(energy, 0, maxi(GameState.max_energy(), 0))
	GameState.highest_unlocked_level = highest
	GameState.energy = energy
	GameState.is_retry = false
	GameState.current_level_id = ""
	_change_to(TITLE_SCENE_PATH, "Going to the title screen")


## The Level Select screen. Touches no GameState field (energy and unlocks are
## the values goto_title() restored from the save) and writes no save.
func goto_level_select() -> void:
	_change_to(LEVEL_SELECT_SCENE_PATH, "Going to level select")


## Level `n` was cleared. A campaign level (1..progression.level_count) raises
## highest_unlocked_level to max(current, min(n + 1, level_count)), saves, then
## starts level n + 1 with the current energy, or goes to the title after the
## last level (Epic 7 replaces that with the end screen). The transition happens
## even if the save fails. Any other id (the dev level is 0) is only logged.
func complete_level(n: int) -> void:
	var level_count: int = Config.int_("progression.level_count")
	if n < 1 or n > level_count:
		Log.info("scene", "Level %d cleared: not a campaign level; no save, no scene change" % n)
		return
	GameState.highest_unlocked_level = maxi(GameState.highest_unlocked_level, mini(n + 1, level_count))
	SaveManager.save()
	if n < level_count:
		start_level(str(n + 1))
	else:
		goto_title()


func _change_to(path: String, message: String) -> void:
	PauseArbiter.clear()
	Feedback.reset()
	Log.info("scene", message)
	change_scene.call(path)
