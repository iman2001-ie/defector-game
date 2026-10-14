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
## a LevelBackground showing LevelBackground.MENU_BACKGROUND.

var _sequence: StringName = &""
var _finished: bool = false


func _ready() -> void:
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var background: LevelBackground = get_node_or_null(^"Background") as LevelBackground
	if background != null:
		background.apply(LevelBackground.MENU_BACKGROUND)
	_sequence = SceneRouter.story_sequence()
	if _sequence == &"":
		Log.warn("scene", "Story scene has no pending sequence; finishing at once")
		_finish()
		return
	Log.info("beat", "Story '%s'" % _sequence)
	Events.comms_sequence_finished.connect(_on_events_comms_sequence_finished)
	Events.comms_sequence_requested.emit(_sequence)


func _exit_tree() -> void:
	if Events.comms_sequence_finished.is_connected(_on_events_comms_sequence_finished):
		Events.comms_sequence_finished.disconnect(_on_events_comms_sequence_finished)


## The sequence this scene plays (&"" when none was pending).
func sequence() -> StringName:
	return _sequence


func _on_events_comms_sequence_finished(sequence_id: StringName) -> void:
	if sequence_id != _sequence:
		return
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	SceneRouter.finish_story()
