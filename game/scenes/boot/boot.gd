extends Node
## The main scene (Story 4.1). Declares the menu mouse mode (VISIBLE), confirms
## Config loaded (it logs either way) and goes to the title screen through
## SceneRouter.goto_title(). A failed config still reaches the title, which then
## shows the error instead of its buttons.
##
## Debug builds given `-- --stress` or `-- --bench=<s>` switch to the sandbox
## stress scene instead, because the CLI bench launches the main scene. Like
## level.gd's redirect this is a debug-only exception to "only SceneRouter
## changes scenes". The args come from user_args and the redirect goes through
## change_scene (the same seams as level.gd).
##
## Both scene changes are deferred: the main scene's _ready runs while the root
## is still adding it, so it can't be removed from the tree yet.

const SANDBOX_SCENE_PATH: String = "res://scenes/sandbox/sandbox.tscn"

## The user args _ready parses (`--stress`, `--bench=<s>`). Tests override this
## before add_child.
var user_args: PackedStringArray = OS.get_cmdline_user_args()
## Changes the scene to a file path (the debug `--stress` redirect, deferred).
## Defaults to get_tree().change_scene_to_file in _ready; tests inject a
## recorder before add_child.
var change_scene: Callable


func _ready() -> void:
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if not change_scene.is_valid():
		change_scene = get_tree().change_scene_to_file
	var args: Dictionary = DebugArgs.parse(user_args)
	if should_redirect_to_stress(OS.is_debug_build(), args):
		Log.info("boot", "Stress/bench args: switching to the sandbox stress scene")
		change_scene.call_deferred(SANDBOX_SCENE_PATH)
		return
	if Config.load_error.is_empty():
		Log.info("boot", "Config loaded (%d tuning sections, %d flags)" % [Config.tuning.size(), Config.flags.size()])
	else:
		Log.error("boot", "Config failed to load: %s" % Config.load_error)
	SceneRouter.goto_title.call_deferred()


## Debug builds given `--stress` or `--bench=<s>` (which implies stress) run the sandbox instead.
static func should_redirect_to_stress(debug_build: bool, args: Dictionary) -> bool:
	return debug_build and args.stress
