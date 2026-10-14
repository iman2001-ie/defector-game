class_name StoryScene
extends Control
## The comms-only story scene (Story 5.5, FR41; UX "Opening story scene"): the
## sequence SceneRouter.story_sequence() plays on the centred story panel over
## the project clear colour (no dim, no HUD), with a visible arrow cursor. There
## is no PauseMenu, so Esc does nothing, and no skip.
##
## _ready declares the VISIBLE mouse mode, connects
## Events.comms_sequence_finished and requests the sequence; the Comms/
## CommsChannel child is already listening (child _ready runs first) and owns
## the `story` pause. When that id finishes (also the deferred finish of an
## unknown id, so nothing soft-locks) it calls SceneRouter.finish_story()
## once, which loads the pending level or the end screen (the council epilogue,
## Story 7.8). Run directly with nothing pending it warns and calls
## finish_story(), which goes to the title.
##
## Story 8.4: a pending sequence logs one `[INFO][beat] Story '<id>'` line
## (the opening and the epilogue are playthrough beats for tools/beat_audit.py).
##
## Story 8.2: the `Background` child (first, so it draws behind the comms) is
## a LevelBackground showing LevelBackground.MENU_BACKGROUND; the council
## epilogue (SceneRouter.ENDING_SEQUENCE) shows the throne world instead, so
## the planet of Level 3 and the end screen stays on screen (playtest
## 2026-10-14). backdrop_for(sequence) picks it.
##
## Playtest pt7-e: the council epilogue also starts the gentle `epilogue` track
## audio.epilogue_music_delay_s after the scene loads (so the boss track's
## fade-out finishes first), fading in over audio.music_fade_in_s. The end
## screen keeps it playing.

const EPILOGUE_MUSIC: StringName = &"epilogue"

var _sequence: StringName = &""
var _finished: bool = false


func _ready() -> void:
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_sequence = SceneRouter.story_sequence()
	var background: LevelBackground = get_node_or_null(^"Background") as LevelBackground
	if background != null:
		background.apply(backdrop_for(_sequence))
	if _sequence == &"":
		Log.warn("scene", "Story scene has no pending sequence; finishing at once")
		_finish()
		return
	Log.info("beat", "Story '%s'" % _sequence)
	if _sequence == SceneRouter.ENDING_SEQUENCE:
		_start_epilogue_music()
	Events.comms_sequence_finished.connect(_on_events_comms_sequence_finished)
	if _sequence != SceneRouter.ENDING_SEQUENCE and Audio.is_fading_out() and Config.load_error.is_empty():
		# The menu track is still fading (PLAY from the title): the opening
		# briefing starts once it is silent (playtest pt7-k review). The
		# epilogue keeps its own timing (the boss fade runs under its first
		# line, as before). Real time, so the story pause can't hold it; the
		# connection dies with the scene.
		get_tree().create_timer(Config.num("audio.music_fade_out_s"), true, false, true).timeout.connect(_request_sequence)
		return
	_request_sequence()


func _request_sequence() -> void:
	Events.comms_sequence_requested.emit(_sequence)


func _exit_tree() -> void:
	if Events.comms_sequence_finished.is_connected(_on_events_comms_sequence_finished):
		Events.comms_sequence_finished.disconnect(_on_events_comms_sequence_finished)


## The background id for story `sequence`: the throne world for the council
## epilogue, LevelBackground.MENU_BACKGROUND for anything else.
static func backdrop_for(sequence_id: StringName) -> String:
	if sequence_id == SceneRouter.ENDING_SEQUENCE:
		return LevelBackground.THRONE_WORLD
	return LevelBackground.MENU_BACKGROUND


## The sequence this scene plays (&"" when none was pending).
func sequence() -> StringName:
	return _sequence


func _on_events_comms_sequence_finished(sequence_id: StringName) -> void:
	if sequence_id != _sequence:
		return
	_finish()


## Starts the epilogue track after audio.epilogue_music_delay_s (at once for 0).
## The timer runs in real time, so the paused story panel never holds it back,
## and its connection dies with the scene, so a scene freed first plays nothing.
func _start_epilogue_music() -> void:
	var delay: float = Config.num("audio.epilogue_music_delay_s")
	if delay <= 0.0:
		_play_epilogue_music()
		return
	get_tree().create_timer(delay, true, false, true).timeout.connect(_play_epilogue_music)


func _play_epilogue_music() -> void:
	Audio.play_music(EPILOGUE_MUSIC, Config.num("audio.music_fade_in_s"))


func _finish() -> void:
	if _finished:
		return
	_finished = true
	SceneRouter.finish_story()
