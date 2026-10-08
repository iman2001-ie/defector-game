extends Node2D
## The one generic level scene (architecture Scene Structure, ADR-006). Reads
## data/levels/level_<level_id>.json through Config.level() and hands it to the
## WaveDirector. Until the title flow exists (Epic 4) it is the main scene and
## runs level_dev.json.
##
## The level id is GameState.current_level_id when set (a retry reloads this
## scene with the same id, ADR-004), else the exported level_id; the resolved
## id is written back to GameState. A retry adds " (retry)" to the start line.
##
## Debug builds given `-- --stress` or `-- --bench=<s>` switch to the sandbox
## stress scene instead (the stress bench lives there). `-- --no-prewarm`
## (debug builds) skips Feedback.prewarm(), as in the sandbox.

const SANDBOX_SCENE_PATH: String = "res://scenes/sandbox/sandbox.tscn"

## Level file key: data/levels/level_<level_id>.json. Used when
## GameState.current_level_id is empty; replaced by the resolved id in _ready.
@export var level_id: String = "dev"

@onready var _player: Player = $World/Player
@onready var _spawner: Spawner = $Spawner
@onready var _director: WaveDirector = $WaveDirector


func _ready() -> void:
	var args: Dictionary = DebugArgs.parse(OS.get_cmdline_user_args())
	if should_redirect_to_stress(OS.is_debug_build(), args):
		Log.info("scene", "Stress/bench args: switching to the sandbox stress scene")
		get_tree().change_scene_to_file.call_deferred(SANDBOX_SCENE_PATH)
		return
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


## The level file key to run: the GameState id when non-empty, else the exported one.
static func resolve_level_id(exported: String, state_id: String) -> String:
	return state_id if not state_id.is_empty() else exported


## Debug builds given `--stress` or `--bench=<s>` (which implies stress) run the sandbox instead.
static func should_redirect_to_stress(debug_build: bool, args: Dictionary) -> bool:
	return debug_build and args.stress


## Pre-warm unless a debug build was given `--no-prewarm` (release builds always pre-warm).
static func should_prewarm(debug_build: bool, args: Dictionary) -> bool:
	return not debug_build or args.prewarm
