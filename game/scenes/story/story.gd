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
##
## Playtest pt7-m: a story that leads into a campaign level (the opening before
## Level 1) is that level's true beginning, so its "LEVEL N" title card
## (Events.level_intro_started, drawn by the LevelIntroCard child) shows first,
## for the full ui.level_intro time, and the sequence is requested only after
## it (or after a fading menu track, whichever ends later). The router remembers
## the card (SceneRouter.mark_intro_shown), so the level doesn't show it again.
## The epilogue shows no card.

const EPILOGUE_MUSIC: StringName = &"epilogue"

## False skips the title card (test seam; set before the scene enters the tree).
var intro_card: bool = true

## Waits still holding the opening sequence back (the title card, a music fade).
var _waits: int = 0
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
	# The opening waits for two things: its title card (its own `finished`, plus
	# ui.level_intro.after_s) and a menu track still fading out (PLAY from the
	# title, playtest pt7-k review). The epilogue keeps its own timing (the boss
	# fade runs under its first line, as before).
	if _sequence != SceneRouter.ENDING_SEQUENCE and Config.load_error.is_empty():
		if intro_card and _show_level_card(SceneRouter.story_next_level()):
			_waits += 1
			var card: LevelIntroCard = get_node_or_null(^"LevelIntroCard") as LevelIntroCard
			var after_s: float = maxf(Config.num("ui.level_intro.after_s"), 0.0)
			if card != null:
				card.finished.connect(_wait_then_release.bind(after_s), CONNECT_ONE_SHOT)
			else:
				_wait_then_release(_card_total_s() + after_s)
		if Audio.is_fading_out():
			_waits += 1
			_wait_then_release(Config.num("audio.music_fade_out_s"))
	if _waits == 0:
		_request_sequence()


## Shows level `level`'s title card when it is a campaign level (1..level_count)
## and ui.level_intro.hold_s is above 0, and marks it shown for the router.
## Returns true when a card shows.
func _show_level_card(level: int) -> bool:
	if level < 1 or level > Config.int_("progression.level_count"):
		return false
	var hold: float = Config.num("ui.level_intro.hold_s")
	if hold <= 0.0:
		return false
	Log.info("scene", "Level %d title card before story '%s' (%.2f s + %.2f s)" % [level, _sequence, _card_total_s(), maxf(Config.num("ui.level_intro.after_s"), 0.0)])
	Events.level_intro_started.emit(level, str(Config.level(str(level)).get("name", "")), hold)
	SceneRouter.mark_intro_shown(level)
	return true


## The title card's whole time on screen at the full hold.
func _card_total_s() -> float:
	return LevelIntroCard.total_s(Config.num("ui.level_intro.fade_in_s"), Config.num("ui.level_intro.hold_s"), Config.num("ui.level_intro.fade_out_s"))


## Releases one wait after `seconds` of real time (at once for 0). Nothing pauses
## the story scene before its sequence starts; the connection dies with the scene,
## so a scene freed first requests nothing.
func _wait_then_release(seconds: float) -> void:
	if seconds <= 0.0:
		_release_wait()
		return
	get_tree().create_timer(seconds, true, false, true).timeout.connect(_release_wait)


## One of the opening's waits is over; the sequence starts when none is left.
func _release_wait() -> void:
	_waits -= 1
	if _waits == 0:
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
