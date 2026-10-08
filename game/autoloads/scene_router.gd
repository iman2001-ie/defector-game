extends Node
## The only place that changes scenes (architecture boundary 4; the debug F5
## reload and the --stress redirect are the debug-only exceptions).
##
## Retry is a scene reload (ADR-004): restart_level() wipes energy, marks the
## attempt as a retry, drops every pause reason, ends any hit-stop and reloads
## level.tscn, which reads GameState.current_level_id, so the same level runs
## again from wave 1. There is no retry counter and no limit.

const LEVEL_SCENE_PATH: String = "res://scenes/level/level.tscn"
const MAIN_SCENE_SETTING: String = "application/run/main_scene"

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


## Placeholder until the title screen exists: Story 4.1/4.2 replace this body
## (its callers stay). Today it loads the configured main scene (the level) as
## a fresh, non-retry attempt with 0 energy (there is no save to restore yet)
## and no level id, so the main scene runs its own exported level.
func goto_title() -> void:
	GameState.energy = 0
	GameState.is_retry = false
	GameState.current_level_id = ""
	var path: String = str(ProjectSettings.get_setting(MAIN_SCENE_SETTING, LEVEL_SCENE_PATH))
	_change_to(path, "Quit to title (placeholder): loading %s" % path)


func _change_to(path: String, message: String) -> void:
	PauseArbiter.clear()
	Feedback.reset()
	Log.info("scene", message)
	change_scene.call(path)
