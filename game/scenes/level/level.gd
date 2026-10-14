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
## Convoy (Story 6.1): when the level JSON has "convoy": true, the Spawner
## spawns one Convoy into World/Allies and the level injects it into the Player
## (set_convoy, for the solid hulls) before the WaveDirector starts. A missing
## or false key spawns nothing (the HUD convoy bar stays hidden).
##
## Ally (Story 6.4): when the level JSON has "ally": "tarek" or "ryn"
## (ally_id), the Spawner spawns one AllyShip with that id into World/Allies
## before the WaveDirector starts. An absent or null key spawns nothing; any
## other value (LevelValidator also reports it) logs a WARN and spawns nothing.
## Play the ally dev level with:
##   "<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game res://scenes/level/level.tscn -- --level=dev_ally
##
## Background (Story 7.6): before the convoy, the ally and the WaveDirector,
## the level hands the data's "background" id (background_id) to its
## Background node (LevelBackground.apply) and logs one `Background '<id>'`
## INFO line when the id it shows is non-empty (an unknown id warns and shows
## none). Only "throne_world" (Level 3) draws
## anything until Epic 8; an absent or null key is "" and draws nothing.
##
## Control hints (playtest 2026-10-13): when the level JSON has
## "teach_controls": true (level 1), the level clears GameState.shown_hints at
## start, so its hints show on every run, retries included. Any other value
## leaves the session's shown hints alone.
##
## Kill share (Story 6.4, FR34): on a level that spawned an ally, the level
## tallies Events.enemy_killed (all kills, and those with by_ally) and, when the
## attempt's outcome is decided (the first Events.level_cleared or
## level_failed), logs one `[INFO][combat] Kills: N total, ally M (P%); target 10-15%`
## line (kill_share_line, the target from tuning allies.kill_share), once per
## attempt. A level without an ally logs no such line.
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
## `-- --level-bench=<scenario>` (debug builds, Story 8.3; boot starts level
## debug.level_bench.level for it) adds one LevelBench under Overlay before the
## WaveDirector starts, with this scene's WaveDirector, Player, CommsChannel and
## FinalChoice and its numbers from tuning debug.level_bench / debug.bench. A
## level that fails to load aborts it (FAIL), so the run never hangs.

const SANDBOX_SCENE_PATH: String = "res://scenes/sandbox/sandbox.tscn"

## Level file key: data/levels/level_<level_id>.json. Used when
## GameState.current_level_id is empty; replaced by the resolved id in _ready.
@export var level_id: String = "dev"

## The user args _ready parses (`--stress`, `--bench=<s>`, `--no-prewarm`,
## `--comms=<id>[,<id>...]`, `--level=<id>`, `--level-bench=<scenario>`).
## Tests override this before add_child.
var user_args: PackedStringArray = OS.get_cmdline_user_args()
## Changes the scene to a file path (the debug `--stress` redirect, deferred).
## Defaults to get_tree().change_scene_to_file in _ready; tests inject a
## recorder before add_child (calling the real one in GUT would replace the
## test runner's scene).
var change_scene: Callable

## The level bench's quit callable (Story 8.3); empty means get_tree().quit.
## Tests inject a recorder before add_child.
var level_bench_quit: Callable

## True once this level spawned an ally: only then is the kill share logged.
var _has_ally: bool = false
var _kills: int = 0
var _ally_kills: int = 0
## Set once the kill-share line is logged: the attempt's outcome is decided.
var _summary_logged: bool = false

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
	Events.level_failed.connect(_on_events_level_failed)
	Events.enemy_killed.connect(_on_events_enemy_killed)
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
	var bench_scenario: String = debug_level_bench(OS.is_debug_build(), args)
	var bench: LevelBench = _add_level_bench(bench_scenario) if not bench_scenario.is_empty() else null
	var data: Dictionary = Config.level(level_id)
	if data.is_empty():
		Log.error("scene", "Level '%s' could not be loaded; nothing started" % level_id)
		if bench != null:
			bench.abort("level '%s' could not be loaded" % level_id)
		return
	var id: int = int(data.get("id", 0)) if (data.get("id") is float or data.get("id") is int) else 0
	if teaches_controls(data):
		GameState.shown_hints.clear()
	Events.level_started.emit(id)
	# The HUD energy bar shows the attempt's starting energy (0 on a retry).
	GameState.emit_energy()
	var retry_tag: String = " (retry)" if GameState.is_retry else ""
	Log.info("scene", "Level %d '%s' started (%s)%s" % [id, str(data.get("name", "")), Config.LEVEL_PATH_FORMAT % level_id, retry_tag])
	var backdrop: LevelBackground = $Background as LevelBackground
	backdrop.apply(background_id(data))
	if not backdrop.background_id().is_empty():
		Log.info("scene", "Background '%s'" % backdrop.background_id())
	if has_convoy(data):
		_spawn_convoy()
	var ally: String = ally_id(data)
	if not ally.is_empty():
		_spawn_ally(ally)
	_director.start_level(data, Config.LEVEL_PATH_FORMAT % level_id)
	# One explosion per tier off-screen, so the first real impact doesn't hitch.
	if should_prewarm(OS.is_debug_build(), args):
		Feedback.prewarm()
	else:
		Log.info("scene", "Feedback pre-warm skipped (--no-prewarm)")
	for comms_id: StringName in debug_comms_ids(OS.is_debug_build(), args):
		Log.info("debug", "--comms: requesting comms sequence '%s'" % comms_id)
		_request_comms.call_deferred(comms_id)


## Spawns the convoy through the Spawner and hands it to the Player.
func _spawn_convoy() -> void:
	var convoy: Convoy = _spawner.spawn_convoy({})
	if convoy == null:
		Log.warn("scene", "Level asks for a convoy but none could be spawned")
		return
	_player.set_convoy(convoy)
	Log.info("scene", "Convoy spawned: %d ships, %d HP" % [convoy.ships().size(), convoy.max_hp()])


## Spawns the level's ally ship through the Spawner.
func _spawn_ally(id: String) -> void:
	var ally: AllyShip = _spawner.spawn_ally({"ally": id})
	if ally == null:
		Log.warn("scene", "Level asks for ally '%s' but none could be spawned" % id)
		return
	_has_ally = true
	Log.info("scene", "Ally '%s' spawned" % id)


## Adds the Story 8.3 level bench under Overlay (it connects to Events in its
## _ready, so it sees wave 1 start).
func _add_level_bench(scenario: String) -> LevelBench:
	var bench: LevelBench = LevelBench.new()
	bench.scenario = scenario
	bench.director = _director
	bench.player = _player
	bench.channel = $Comms/CommsChannel as CommsChannel
	bench.final_choice = $Comms/FinalChoice as FinalChoice
	bench.target_wave = Config.int_("debug.level_bench.wave")
	bench.sample_s = Config.num("debug.level_bench.sample_s")
	bench.settle_s = Config.num("debug.level_bench.settle_s")
	bench.quit_delay_s = Config.num("debug.bench.quit_delay_s")
	if level_bench_quit.is_valid():
		bench.quit_game = level_bench_quit
	$Overlay.add_child(bench)
	return bench


func _request_comms(sequence_id: StringName) -> void:
	Events.comms_sequence_requested.emit(sequence_id)


func _on_events_level_cleared(cleared_id: int) -> void:
	_log_kill_share()
	SceneRouter.complete_level(cleared_id)


func _on_events_level_failed(_reason: StringName) -> void:
	_log_kill_share()


func _on_events_enemy_killed(_enemy_type: StringName, _position: Vector2, by_ally: bool) -> void:
	if _summary_logged:
		return
	_kills += 1
	if by_ally:
		_ally_kills += 1


## Logs the attempt's kill-share line once (the first outcome wins), only on a
## level that spawned an ally.
func _log_kill_share() -> void:
	if _summary_logged or not _has_ally:
		return
	_summary_logged = true
	Log.info("combat", kill_share_line(_kills, _ally_kills,
		Config.num("allies.kill_share.min"), Config.num("allies.kill_share.max")))


## `Kills: N total, ally M (P%); target LO-HI%`: P is the ally's rounded
## percentage of `total` (0 when total is 0); `lo` and `hi` are fractions.
static func kill_share_line(total: int, ally: int, lo: float, hi: float) -> String:
	var pct: int = roundi(100.0 * float(ally) / float(total)) if total > 0 else 0
	return "Kills: %d total, ally %d (%d%%); target %d-%d%%" % [total, ally, pct, roundi(lo * 100.0), roundi(hi * 100.0)]


## The level's ally id: "tarek" or "ryn" from the data's "ally" key; "" when
## the key is absent or null, and "" with a WARN for any other value.
static func ally_id(data: Dictionary) -> String:
	var value: Variant = data.get("ally")
	if value == null:
		return ""
	if LevelValidator.is_valid_ally(value):
		return value as String
	Log.warn("scene", "Level ally %s is not null, \"tarek\" or \"ryn\"; no ally spawned" % JSON.stringify(value))
	return ""


## The level's background id from the data's "background" key; "" when the key
## is absent or null, and "" with a WARN for any value that isn't a String
## (LevelBackground.apply warns about an unknown String id).
static func background_id(data: Dictionary) -> String:
	var value: Variant = data.get("background")
	if value == null:
		return ""
	if value is String:
		return value as String
	Log.warn("scene", "Level background %s is not null or a string; no background drawn" % JSON.stringify(value))
	return ""


## True only when the level data's "teach_controls" is the boolean true.
static func teaches_controls(data: Dictionary) -> bool:
	var value: Variant = data.get("teach_controls", false)
	return value is bool and value


## True only when the level data's "convoy" is the boolean true.
static func has_convoy(data: Dictionary) -> bool:
	var value: Variant = data.get("convoy", false)
	return value is bool and bool(value)


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


## The --level-bench=<scenario> to run: debug builds only ("" in release
## builds or without the arg).
static func debug_level_bench(debug_build: bool, args: Dictionary) -> String:
	if not debug_build:
		return ""
	var scenario: Variant = args.get("level_bench", "")
	return String(scenario) if (scenario is String or scenario is StringName) else ""


## Pre-warm unless a debug build was given `--no-prewarm` (release builds always pre-warm).
static func should_prewarm(debug_build: bool, args: Dictionary) -> bool:
	return not debug_build or args.prewarm
