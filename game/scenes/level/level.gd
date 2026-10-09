extends Node2D
## The one generic level scene (architecture Scene Structure, ADR-006). Reads
## data/levels/level_<level_id>.json through Config.level() and hands it to the
## WaveDirector. The title's PLAY and Level Select reach it through
## SceneRouter.start_level(); level 1 first plays the opening story scene, which
## loads it through SceneRouter.finish_story() (Story 5.5). Run directly (no
## GameState id) it falls back to its exported "dev" level.
##
## The level id is GameState.current_level_id when set (a retry reloads this
## scene with the same id, ADR-004), else the exported level_id; the resolved
## id is written back to GameState. A retry adds " (retry)" to the start line.
##
## Events.level_cleared(id) -> SceneRouter.complete_level(id) (Story 4.2): a
## campaign level unlocks and saves, then the next level or the title loads.
##
## Debug builds given `-- --stress` or `-- --bench=<s>` switch to the sandbox
## stress scene instead (the stress bench lives there). `-- --no-prewarm`
## (debug builds) skips Feedback.prewarm(), as in the sandbox. The args come
## from user_args and the redirect goes through change_scene (DW-46 seams).
## `-- --comms=<id>[,<id>...]` (debug builds, Story 5.1) requests those comms
## sequences in order (deferred) once the level has started, so the comms panel can be checked
## before the wave triggers exist. `-- --level=<id>` (debug builds, Story 5.6)
## replaces the exported level_id before resolve_level_id, so a human can play
## a level the title doesn't reach (e.g. dev_isolde); a non-empty GameState id
## (a retry or any SceneRouter entry) still wins. It only takes effect when
## level.tscn is the launched scene (boot.tscn is the main scene and routes in
## through SceneRouter, which sets the GameState id):
##   "<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game res://scenes/level/level.tscn -- --level=dev_isolde

const SANDBOX_SCENE_PATH: String = "res://scenes/sandbox/sandbox.tscn"

## Level file key: data/levels/level_<level_id>.json. Used when
## GameState.current_level_id is empty; replaced by the resolved id in _ready.
@export var level_id: String = "dev"

## The user args _ready parses (`--stress`, `--bench=<s>`, `--no-prewarm`,
## `--comms=<id>[,<id>...]`, `--level=<id>`).
## Tests override this before add_child.
var user_args: PackedStringArray = OS.get_cmdline_user_args()
## Changes the scene to a file path (the debug `--stress` redirect, deferred).
## Defaults to get_tree().change_scene_to_file in _ready; tests inject a
## recorder before add_child (calling the real one in GUT would replace the
## test runner's scene).
var change_scene: Callable

@onready var _player: Player = $World/Player
@onready var _spawner: Spawner = $Spawner
@onready var _director: WaveDirector = $WaveDirector


func _ready() -> void:
	if not change_scene.is_valid():
		change_scene = get_tree().change_scene_to_file
	var args: Dictionary = DebugArgs.parse(user_args)
	if should_redirect_to_stress(OS.is_debug_build(), args):
		Log.info("scene", "Stress/bench args: switching to the sandbox stress scene")
		change_scene.call_deferred(SANDBOX_SCENE_PATH)
		return
	# Progression (Story 4.2): a cleared level goes through the router, which
	# saves and moves on for campaign levels only (the dev level is a no-op).
	Events.level_cleared.connect(_on_events_level_cleared)
	var arg_level: String = debug_level_id(OS.is_debug_build(), args)
	if not arg_level.is_empty():
		if GameState.current_level_id.is_empty():
			Log.info("debug", "--level: running level '%s'" % arg_level)
		else:
			Log.info("debug", "--level '%s' ignored: GameState level '%s' wins" % [arg_level, GameState.current_level_id])
		level_id = arg_level
	level_id = resolve_level_id(level_id, GameState.current_level_id)
	GameState.current_level_id = level_id
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	_player.set_spawner(_spawner)
	RenderGlow.apply(($WorldEnvironment as WorldEnvironment).environment)
	var data: Dictionary = Config.level(level_id)
	if data.is_empty():
		Log.error("scene", "Level '%s' could not be loaded; nothing started" % level_id)
		return
	var id: int = int(data.get("id", 0)) if (data.get("id") is float or data.get("id") is int) else 0
	Events.level_started.emit(id)
	# The HUD energy bar shows the attempt's starting energy (0 on a retry).
	GameState.emit_energy()
	var retry_tag: String = " (retry)" if GameState.is_retry else ""
	Log.info("scene", "Level %d '%s' started (%s)%s" % [id, str(data.get("name", "")), Config.LEVEL_PATH_FORMAT % level_id, retry_tag])
	_director.start_level(data, Config.LEVEL_PATH_FORMAT % level_id)
	# One explosion per tier off-screen, so the first real impact doesn't hitch.
	if should_prewarm(OS.is_debug_build(), args):
		Feedback.prewarm()
	else:
		Log.info("scene", "Feedback pre-warm skipped (--no-prewarm)")
	for comms_id: StringName in debug_comms_ids(OS.is_debug_build(), args):
		Log.info("debug", "--comms: requesting comms sequence '%s'" % comms_id)
		_request_comms.call_deferred(comms_id)


func _request_comms(sequence_id: StringName) -> void:
	Events.comms_sequence_requested.emit(sequence_id)


func _on_events_level_cleared(cleared_id: int) -> void:
	SceneRouter.complete_level(cleared_id)


## The level file key to run: the GameState id when non-empty, else the exported one.
static func resolve_level_id(exported: String, state_id: String) -> String:
	return state_id if not state_id.is_empty() else exported


## Debug builds given `--stress` or `--bench=<s>` (which implies stress) run the sandbox instead.
static func should_redirect_to_stress(debug_build: bool, args: Dictionary) -> bool:
	return debug_build and args.stress


## The --comms= sequences to request, in order, after the level starts: debug
## builds only (empty in release builds or without the arg).
static func debug_comms_ids(debug_build: bool, args: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	if not debug_build:
		return ids
	var raw: Variant = args.get("comms", [])
	if raw is Array:
		for id: Variant in raw as Array:
			if id is StringName or id is String:
				ids.append(StringName(id))
	return ids


## The --level=<id> level file key that replaces the exported level_id: debug
## builds only ("" in release builds or without the arg).
static func debug_level_id(debug_build: bool, args: Dictionary) -> String:
	if not debug_build:
		return ""
	var id: Variant = args.get("level", "")
	return String(id) if (id is String or id is StringName) else ""


## Pre-warm unless a debug build was given `--no-prewarm` (release builds always pre-warm).
static func should_prewarm(debug_build: bool, args: Dictionary) -> bool:
	return not debug_build or args.prewarm
