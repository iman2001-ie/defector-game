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
## Debug builds given `-- --level-bench=<scenario>` (Story 8.3) start level
## debug.level_bench.level through SceneRouter.start_level instead of the title,
## so the same command runs the level bench on the editor binary and on a debug
## export. Release builds ignore the arg and show the title.
##
## Every scene change is deferred: the main scene's _ready runs while the root
## is still adding it, so it can't be removed from the tree yet.
##
## Story 8.4: the first line the boot scene logs (after the autoloads' load
## lines) is `[INFO][boot] Build: release` or `Build: debug`
## (OS.is_debug_build()), before any redirect, so
## tools/beat_audit.py can tell a release playthrough from a debug one.

const SANDBOX_SCENE_PATH: String = "res://scenes/sandbox/sandbox.tscn"

## The user args _ready parses (`--stress`, `--bench=<s>`, `--level-bench=<scenario>`). Tests override this
## before add_child.
var user_args: PackedStringArray = OS.get_cmdline_user_args()
## Changes the scene to a file path (the debug `--stress` redirect, deferred).
## Defaults to get_tree().change_scene_to_file in _ready; tests inject a
## recorder before add_child.
var change_scene: Callable


func _ready() -> void:
	# Story 8.4: the boot scene's first line (after the autoloads' load lines), so
	# every launch's log says which build it is (beat_audit.py).
	Log.info("boot", "Build: %s" % build_type(OS.is_debug_build()))
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
	# A failed config can't start a level; the title shows the error instead.
	if should_start_level_bench(OS.is_debug_build(), args) and Config.load_error.is_empty():
		var level: String = str(Config.int_("debug.level_bench.level"))
		Log.info("boot", "Level bench '%s': starting level %s" % [args.level_bench, level])
		SceneRouter.start_level.call_deferred(level)
		return
	SceneRouter.goto_title.call_deferred()


## The build type named in the `[INFO][boot] Build: <type>` line: "debug" or "release".
static func build_type(debug_build: bool) -> String:
	return "debug" if debug_build else "release"


## Debug builds given `--stress` or `--bench=<s>` (which implies stress) run the sandbox instead.
static func should_redirect_to_stress(debug_build: bool, args: Dictionary) -> bool:
	return debug_build and args.stress


## Debug builds given a valid `--level-bench=<scenario>` start the bench level instead of the title.
static func should_start_level_bench(debug_build: bool, args: Dictionary) -> bool:
	return debug_build and not String(args.get("level_bench", "")).is_empty()
