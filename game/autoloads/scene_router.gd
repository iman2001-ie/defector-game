extends Node
## The only place that changes scenes (architecture boundary 4; the debug F5
## reload and the --stress redirect in boot.gd / level.gd are the debug-only
## exceptions).
##
## Every change goes through _change_to(), which drops every pause reason
## (PauseArbiter.clear()), ends any hit-stop and logs one INFO scene line first.
##
## - goto_title(): the title screen (scenes/title/title.tscn) with 0 energy, no
##   retry and no level id. Story 4.2 swaps the energy reset for the save restore.
## - start_level(id): a fresh (non-retry) attempt of level `id` in level.tscn,
##   carrying the current energy. Refused (logged) while Config.load_error is set.
## - restart_level(): retry is a scene reload (ADR-004). It wipes energy, marks
##   the attempt as a retry and reloads level.tscn, which reads
##   GameState.current_level_id, so the same level runs again from wave 1. There
##   is no retry counter and no limit.

const LEVEL_SCENE_PATH: String = "res://scenes/level/level.tscn"
const TITLE_SCENE_PATH: String = "res://scenes/title/title.tscn"

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


## The title screen: 0 energy (there is no save to restore yet; Story 4.2), not a
## retry, no level id.
func goto_title() -> void:
	GameState.energy = 0
	GameState.is_retry = false
	GameState.current_level_id = ""
	_change_to(TITLE_SCENE_PATH, "Going to the title screen")


func _change_to(path: String, message: String) -> void:
	PauseArbiter.clear()
	Feedback.reset()
	Log.info("scene", message)
	change_scene.call(path)
