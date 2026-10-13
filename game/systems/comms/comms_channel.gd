class_name CommsChannel
extends Node
## The single dialogue delivery path (Stories 5.1-5.4 and 7.5, architecture "Comms
## Channel"). Listens to Events.comms_sequence_requested, owns the story and
## combat queues and the `story` pause reason, drives the CommsPanel (story)
## and CommsBox (combat) views and emits Events.comms_sequence_finished. Every
## requested known sequence finishes exactly once (played, preempted or
## dropped).
##
## - Unknown id: Log.error, then a deferred `finished(id)` (never inside the
##   request, so a caller that emits and then awaits `finished` can't hang).
## - Combat mode (Story 5.2): no pause, input untouched. While idle the
##   box shows line 0 and each line stays combat_line_s(...) seconds of game
##   time (step_combat runs only while the tree isn't paused); after the last
##   line the box fades and `finished` is emitted. A combat request while a
##   combat plays or a story shows is queued FIFO (comms.combat_queue_max; the
##   oldest is dropped with a deferred `finished`). Queued combat plays when
##   neither a story nor a combat is showing.
## - A story request while a combat plays preempts it: the box hides at once,
##   the combat's `finished` is emitted deferred, the combat queue is kept.
## - Story mode while idle: push `story`, play `comms_open`, open the panel and
##   show line 0. Story mode while a story plays: queued FIFO, never dropped.
## - Input: `comms_advance` presses and releases are consumed while a story is
##   showing and the `menu` reason is not active. A press arms the channel; an
##   armed release advances. The pause lifts on the release, so the laser
##   (which polls `fire_laser`, the same button) never sees it held on the
##   first unpaused tick. A release that isn't armed (held from before the
##   panel opened) is consumed and ignored.
## - Advance: complete a typing line, else show the next line. After the last
##   line it logs and emits `finished`; the next queued story starts without
##   unpausing (with `comms_open` again: a new conversation), otherwise the
##   panel closes and `story` is popped before `finished` is emitted.
## - Line cues (GDD decision #40): showing the next line of a story plays
##   `comms_handover` when its speaker differs from the previous line's, else
##   `comms_click`. Completing a typing line and line 0 (it has `comms_open`)
##   play none.
## - Line log (Epic 7 playtest C): every line shown on the panel or in the box
##   emits Events.comms_line_shown(speaker, text, mode) (mode &"story" or
##   &"combat"); a cut-off line carries its shown text (shown_text).
## - Combat cues (GDD decisions #41, #42): every combat line (a cut-off line
##   too) starts with a key-in cue, see combat_cue: `comms_open_nobeep` when the box
##   opens fresh, `comms_handover` / `comms_click` when it follows straight on
##   from another combat line (box still up or fading). All of them play
##   quieter than in a story (comms.combat_open_db / combat_line_cue_db); no
##   cue when the box fades or hides.
## - Cut-off (Story 5.4, GDD decision #43): a combat line with `cut_off_at` (a
##   combat sequence has one line, so it is the whole sequence) types to
##   exactly `cut_off_at` characters over cut_off_at / comms.cutoff_chars_per_s
##   s of game time. At that moment the box stops there and shows
##   comms.cutoff_suffix after the cut, and the `after` effects run in order:
##   the sfx (Audio.play_sfx), the shake (`cutoff`: Feedback.shake with
##   comms.cutoff_shake_px / cutoff_shake_s; a tier name:
##   Feedback.shake_tier), the music action (Audio.apply_music_action), then
##   silence. comms.cutoff_hide_s later the box hides at once (no fade) and
##   `finished` is emitted. The after-sfx (the 2.5 s static) lives with the
##   line: it is stopped whenever the line ends (the hide, a preempt, the
##   channel leaving the tree) and its stream pauses while the tree is paused.
##   The hold counts real time (game delta / Engine.time_scale), so it stays in
##   step with the audio under a hit-stop's slow-down; the typing counts game
##   time. Both phases count
##   game time in step_combat, so a pause freezes them. A story that preempts
##   the line before its cut-off moment drops it with no effects.
## - Silence (`after.silence: until_wave_clear`): drops every queued combat
##   sequence and every later combat request (DEBUG, deferred `finished`);
##   story sequences still play. Events.wave_cleared lifts it. A wave_cleared
##   between the cut-off line's start and its cut-off moment voids the
##   silence, so it never carries into the next wave.
## - Choice (Story 7.5, the Final Choice): a story sequence with a `choice`
##   block plays its lines as usual. On the advance after its last line the
##   panel stays open on that line with its cue hidden, the channel pushes the
##   `final_choice` reason (`story` stays) and shows the FinalChoice view with
##   the options. While the choice is up, `comms_advance` presses and releases
##   are consumed and do nothing (and advance() does nothing). A click on an
##   option emits Events.final_choice_made(id), sets GameState.final_choice,
##   hides the view, pops `final_choice`, plays `comms_handover` and plays the
##   option's `next` story lines in the same panel (current_sequence() is the
##   `next` id meanwhile). When `next` ends, the normal finish runs (queue,
##   panel close, pop `story`) and emits `finished` once, with the requested
##   id; nothing is emitted for `next`, which nobody requested. Without a
##   `final_choice` view the sequence logs an error and finishes as a plain
##   story (no event); an unknown `next` logs an error and finishes at once.

const PAUSE_REASON: StringName = &"story"
## The pause reason held while the Final Choice buttons are up (Story 7.5).
const CHOICE_REASON: StringName = &"final_choice"
const MENU_REASON: StringName = &"menu"
const ADVANCE_ACTION: StringName = &"comms_advance"
const OPEN_SFX: StringName = &"comms_open"
const CLICK_SFX: StringName = &"comms_click"
## comms_open without the talk-permit beep: the combat box keys in, it never "opens a conversation".
const COMBAT_OPEN_SFX: StringName = &"comms_open_nobeep"
const HANDOVER_SFX: StringName = &"comms_handover"
## The `mode` of Events.comms_line_shown.
const MODE_STORY: StringName = &"story"
const MODE_COMBAT: StringName = &"combat"
## Slack for the combat line timer, so float steps that add up to the line
## time (4.9 + 0.1 s) end it.
const COMBAT_EPSILON_S: float = 0.000001
## Cut-off line keys (Story 5.4, see DialogueValidator).
const CUT_OFF_KEY: String = DialogueValidator.CUT_OFF_KEY
const AFTER_KEY: String = DialogueValidator.AFTER_KEY

## Phases of the playing combat line: a plain line, a cut-off line typing
## towards its cut-off moment, a cut-off line holding before it hides.
enum CutPhase { NONE, TYPING, HOLD }

@export var panel: CommsPanel
@export var box: CommsBox
## The Final Choice view (Story 7.5); only needed by a sequence with a `choice`.
@export var final_choice: FinalChoice

## Id of the story sequence on the panel (a choice's `next` while its response
## plays); &"" while idle.
var _current: StringName = &""
## Id of the story sequence that was requested (and is finished); differs from
## _current only while a choice's response plays.
var _requested: StringName = &""
## The `choice.options` of the requested sequence; empty without a choice.
var _choice_options: Array = []
## True while the Final Choice buttons are up.
var _choosing: bool = false
## True while a choice's `next` response plays.
var _in_response: bool = false
## The chosen option's `fail` reason (&"" for none): once its response has
## played, _finish raises Events.level_failed with it (the Level 1 surrender
## lose ending, playtest 2026-10-13).
var _fail_reason: StringName = &""
var _lines: Array = []
var _index: int = 0
var _armed: bool = false
var _queue: Array[StringName] = []

## Id of the combat sequence in the box; &"" while none plays.
var _combat: StringName = &""
var _combat_lines: Array = []
var _combat_index: int = 0
## Game time left on the current combat line.
var _combat_left_s: float = 0.0
var _combat_queue: Array[StringName] = []
## `comms` tuning, cached in _ready.
var _chars_per_s: float = 0.0
var _combat_min_s: float = 0.0
var _combat_extra_s: float = 0.0
## `comms.combat_open_db` / `combat_line_cue_db`: combat cue volumes.
var _combat_open_db: float = 0.0
var _combat_line_cue_db: float = 0.0
var _combat_queue_max: int = 0
var _cutoff_hide_s: float = 0.0
## `comms.cutoff_chars_per_s` / `cutoff_suffix` / `cutoff_shake_px` /
## `cutoff_shake_s`: the cut-off line's typing speed, cut marker and shake.
var _cutoff_chars_per_s: float = 0.0
var _cutoff_suffix: String = ""
var _cutoff_shake_px: float = 0.0
var _cutoff_shake_s: float = 0.0
## The player Audio.play_sfx returned for the cut-off's after-sfx, and its
## stream (the pool may hand the player to another sound).
var _cut_sfx_player: AudioStreamPlayer = null
var _cut_sfx_stream: AudioStream = null

## Cut-off state of the playing combat line (Story 5.4); NONE for a plain line.
var _cut_phase: CutPhase = CutPhase.NONE
var _cut_at: int = -1
var _cut_after: Dictionary = {}
## Events.wave_cleared arrived while the cut-off line typed: no silence.
var _cut_wave_cleared: bool = false
## Combat sequences are dropped until the wave clears.
var _silenced: bool = false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	if panel == null:
		Log.error("comms", "CommsChannel has no panel; story lines are not shown")
	if box == null:
		Log.error("comms", "CommsChannel has no box; combat lines are not shown")
	_chars_per_s = Config.num("comms.chars_per_s")
	_combat_min_s = Config.num("comms.combat_line_min_s")
	_combat_extra_s = Config.num("comms.combat_line_extra_s")
	_combat_open_db = Config.num("comms.combat_open_db")
	_combat_line_cue_db = Config.num("comms.combat_line_cue_db")
	_combat_queue_max = maxi(Config.int_("comms.combat_queue_max"), 0)
	_cutoff_hide_s = maxf(Config.num("comms.cutoff_hide_s"), 0.0)
	_cutoff_chars_per_s = Config.num("comms.cutoff_chars_per_s")
	_cutoff_suffix = cutoff_suffix_from(Config.section("comms"))
	_cutoff_shake_px = Config.num("comms.cutoff_shake_px")
	_cutoff_shake_s = Config.num("comms.cutoff_shake_s")
	Events.comms_sequence_requested.connect(_on_events_comms_sequence_requested)
	Events.wave_cleared.connect(_on_events_wave_cleared)
	if final_choice != null:
		final_choice.chosen.connect(_on_final_choice_chosen)


func _exit_tree() -> void:
	_stop_cut_sfx()
	if final_choice != null and is_instance_valid(final_choice) and final_choice.chosen.is_connected(_on_final_choice_chosen):
		final_choice.chosen.disconnect(_on_final_choice_chosen)
	if Events.comms_sequence_requested.is_connected(_on_events_comms_sequence_requested):
		Events.comms_sequence_requested.disconnect(_on_events_comms_sequence_requested)
	if Events.wave_cleared.is_connected(_on_events_wave_cleared):
		Events.wave_cleared.disconnect(_on_events_wave_cleared)


# --- Read accessors ----------------------------------------------------------------

## The story sequence on the panel, &"" while idle.
func current_sequence() -> StringName:
	return _current


func is_showing() -> bool:
	return _current != &""


## True while the Final Choice buttons are up (Story 7.5).
func is_choosing() -> bool:
	return _choosing


## The story sequence that was requested and will be finished (the choice
## parent while its response plays); &"" while idle.
func requested_sequence() -> StringName:
	return _requested


## Index of the line on the panel (tests).
func line_index() -> int:
	return _index


## Story ids waiting behind the current one, oldest first (tests).
func queued() -> Array[StringName]:
	return _queue.duplicate()


## The combat sequence in the box, &"" while none plays.
func current_combat() -> StringName:
	return _combat


func is_playing_combat() -> bool:
	return _combat != &""


## Combat ids waiting to play, oldest first.
func combat_queued() -> Array[StringName]:
	return _combat_queue.duplicate()


## True while combat sequences are dropped (a cut-off's `until_wave_clear`).
func is_silenced() -> bool:
	return _silenced


## The phase of the playing combat line (CutPhase.NONE for a plain line).
func cut_phase() -> CutPhase:
	return _cut_phase


## How long a combat line of `chars` characters stays up:
## max(min_s, chars / chars_per_s + extra_s), or max(min_s, extra_s) when
## chars_per_s isn't positive.
static func combat_line_s(chars: int, chars_per_s: float, min_s: float, extra_s: float) -> float:
	if chars_per_s <= 0.0:
		return maxf(min_s, extra_s)
	return maxf(min_s, chars / chars_per_s + extra_s)


# --- Requests ----------------------------------------------------------------------

func _on_events_comms_sequence_requested(sequence_id: StringName) -> void:
	if not Config.has_sequence(sequence_id):
		Log.error("comms", "Unknown comms sequence '%s'" % sequence_id)
		_emit_finished.call_deferred(sequence_id)
		return
	if not Config.dialogue_is_story(sequence_id):
		if _silenced:
			Log.debug("comms", "Comms silenced: dropped combat sequence '%s'" % sequence_id)
			_emit_finished.call_deferred(sequence_id)
			return
		_request_combat(sequence_id)
		return
	if is_playing_combat():
		_preempt_combat(sequence_id)
	if is_showing():
		_queue.append(sequence_id)
		Log.debug("comms", "Story sequence '%s' queued behind '%s'" % [sequence_id, _current])
		return
	PauseArbiter.push(PAUSE_REASON)
	_start(sequence_id)


func _start(sequence_id: StringName) -> void:
	var seq: Dictionary = Config.sequence(sequence_id)
	_current = sequence_id
	_requested = sequence_id
	_lines = seq.get("lines", []) as Array
	_index = 0
	_armed = false
	_choosing = false
	_in_response = false
	_fail_reason = &""
	_choice_options = []
	var choice: Variant = seq.get(DialogueValidator.CHOICE_KEY)
	if choice is Dictionary and (choice as Dictionary).get(DialogueValidator.CHOICE_OPTIONS_KEY) is Array:
		_choice_options = (choice as Dictionary)[DialogueValidator.CHOICE_OPTIONS_KEY] as Array
	if box != null:
		# A combat line still fading out doesn't linger under the dim.
		box.hide_now()
	Audio.play_sfx(OPEN_SFX, 0.0)
	if panel != null:
		panel.open()
	_show_line()
	Log.info("comms", "Story sequence '%s' started (%d lines)" % [sequence_id, _lines.size()])


func _show_line() -> void:
	if panel == null or _index >= _lines.size():
		return
	var line: Dictionary = _lines[_index]
	var speaker: StringName = StringName(str(line.get("speaker", "")))
	var text: String = str(line.get("text", ""))
	panel.show_line(speaker, text)
	Events.comms_line_shown.emit(speaker, text, MODE_STORY)


func _emit_finished(sequence_id: StringName) -> void:
	Events.comms_sequence_finished.emit(sequence_id)


# --- Input and advancing -----------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_showing() or PauseArbiter.has_reason(MENU_REASON):
		return
	if not event.is_action(ADVANCE_ACTION):
		return
	get_viewport().set_input_as_handled()
	if _choosing:
		# Only the FinalChoice buttons answer while the choice is up.
		_armed = false
		return
	if event.is_echo():
		return
	if event.is_pressed():
		_armed = true
		return
	if not _armed:
		return
	_armed = false
	advance()


## Completes a typing line, else shows the next one; after the last line the
## sequence finishes. Does nothing while idle.
func advance() -> void:
	if not is_showing() or _choosing:
		return
	if panel != null and panel.is_typing():
		panel.complete_line()
		return
	_index += 1
	if _index < _lines.size():
		Audio.play_sfx(HANDOVER_SFX if _speaker_at(_index) != _speaker_at(_index - 1) else CLICK_SFX, 0.0)
		_show_line()
		return
	_finish()


func _speaker_at(index: int) -> String:
	var line: Variant = _lines[index]
	return str((line as Dictionary).get("speaker", "")) if line is Dictionary else ""


func _finish() -> void:
	if not _in_response and not _choice_options.is_empty() and _show_choice():
		return
	var finished_id: StringName = _requested
	var fail: StringName = _fail_reason
	Log.info("comms", "Story sequence '%s' finished" % finished_id)
	_requested = &""
	_choice_options = []
	_in_response = false
	_fail_reason = &""
	if not _queue.is_empty():
		# Still showing while `finished` goes out, so a story requested by a
		# listener queues behind the ones already waiting.
		var next_id: StringName = _queue.pop_front()
		_raise_fail(fail)
		Events.comms_sequence_finished.emit(finished_id)
		_start(next_id)
		return
	_current = &""
	_lines = []
	_index = 0
	_armed = false
	if panel != null:
		panel.close()
	PauseArbiter.pop(PAUSE_REASON)
	# The loss goes out before `finished`, so the wave chain waiting on this
	# sequence sees the failed level and stops (no reinforcements after a
	# surrender).
	_raise_fail(fail)
	Events.comms_sequence_finished.emit(finished_id)
	if not is_showing() and not is_playing_combat():
		_start_next_combat()


# --- Choice (Story 7.5) ------------------------------------------------------------

## Shows the Final Choice for the requested sequence: the panel stays on its
## last line with the cue hidden, `final_choice` is pushed and the view shows
## the options. Returns false (after a Log.error) without a view, so the
## sequence finishes as a plain story.
func _show_choice() -> bool:
	if final_choice == null or not is_instance_valid(final_choice):
		Log.error("comms", "CommsChannel has no final_choice view; '%s' finishes without its choice" % _requested)
		return false
	_choosing = true
	_armed = false
	if panel != null:
		panel.set_cue_visible(false)
	PauseArbiter.push(CHOICE_REASON)
	final_choice.show_options(_choice_options)
	Log.info("comms", "Story sequence '%s': final choice shown" % _requested)
	return true


## A chosen option's `fail` reason (the Level 1 surrender): the level is lost
## with it once the response has played, just before that sequence's
## comms_sequence_finished. Nothing for &"".
func _raise_fail(reason: StringName) -> void:
	if reason.is_empty():
		return
	Log.info("comms", "Choice outcome: the level is lost ('%s')" % reason)
	Events.level_failed.emit(reason)


## An option was clicked: the event, GameState, the view hidden, the
## `final_choice` reason popped, then the option's `next` response in the same
## panel (an unknown `next` logs an error and finishes at once). An option with
## `fail` loses the level once that response has played (_raise_fail).
func _on_final_choice_chosen(id: StringName) -> void:
	if not _choosing:
		return
	var option: Dictionary = {}
	for raw: Variant in _choice_options:
		if raw is Dictionary and StringName(str((raw as Dictionary).get(DialogueValidator.OPTION_ID, ""))) == id:
			option = raw
			break
	if option.is_empty():
		Log.error("comms", "Final choice '%s' is not an option of '%s'; ignored" % [id, _requested])
		return
	_choosing = false
	var fail: Variant = option.get(DialogueValidator.OPTION_FAIL)
	_fail_reason = StringName(fail as String) if fail is String else &""
	Events.final_choice_made.emit(id)
	GameState.final_choice = id
	if final_choice != null and is_instance_valid(final_choice):
		final_choice.hide_options()
	PauseArbiter.pop(CHOICE_REASON)
	_in_response = true
	var next_id: StringName = StringName(str(option.get(DialogueValidator.OPTION_NEXT, "")))
	var lines: Variant = Config.sequence(next_id).get("lines")
	if not Config.dialogue_is_story(next_id) or not (lines is Array) or (lines as Array).is_empty():
		Log.error("comms", "Final choice '%s': next '%s' is not a known story sequence; '%s' finishes" % [id, next_id, _requested])
		_finish()
		return
	_current = next_id
	_lines = lines as Array
	_index = 0
	_armed = false
	if panel != null:
		panel.set_cue_visible(true)
	Audio.play_sfx(HANDOVER_SFX, 0.0)
	_show_line()
	Log.info("comms", "Final choice '%s': response '%s' started (%d lines)" % [id, next_id, _lines.size()])


# --- Combat ------------------------------------------------------------------------

func _process(delta: float) -> void:
	_sync_cut_sfx_pause(get_tree().paused)
	if is_playing_combat() and not get_tree().paused:
		step_combat(delta)


## Counts the current combat line down by `delta` s of game time. At the end it
## shows the next line or, after the last, fades the box, logs, emits
## `finished` and starts the next queued combat if no story is showing and
## nothing (a `finished` listener) started one. A cut-off line first reaches
## its cut-off moment (see _cut_off), then holds for comms.cutoff_hide_s and
## hides the box at once instead of fading it. The hold counts real time
## (hold_step), the rest game time.
func step_combat(delta: float) -> void:
	if not is_playing_combat():
		return
	_combat_left_s -= hold_step(delta, Engine.time_scale) if _cut_phase == CutPhase.HOLD else delta
	if _combat_left_s > COMBAT_EPSILON_S:
		return
	if _cut_phase == CutPhase.TYPING:
		_cut_off()
		return
	var cut: bool = _cut_phase == CutPhase.HOLD
	_combat_index += 1
	if not cut and _combat_index < _combat_lines.size():
		_show_combat_line()
		return
	var finished_id: StringName = _combat
	_clear_combat()
	if box != null:
		if cut:
			box.hide_now()
		else:
			box.dismiss()
	Log.info("comms", "Combat sequence '%s' finished" % finished_id)
	Events.comms_sequence_finished.emit(finished_id)
	if not is_showing() and not is_playing_combat():
		_start_next_combat()


## Plays a combat sequence at once when nothing is showing; otherwise queues
## it, dropping the oldest queued one (deferred `finished`) past the max.
func _request_combat(sequence_id: StringName) -> void:
	# Only straight to the box when nothing waits: a request from inside a
	# `finished` listener must not jump ahead of queued combat ids.
	if not is_playing_combat() and not is_showing() and _combat_queue.is_empty():
		_start_combat(sequence_id)
		return
	_combat_queue.append(sequence_id)
	Log.debug("comms", "Combat sequence '%s' queued" % sequence_id)
	if _combat_queue.size() > _combat_queue_max:
		var dropped: StringName = _combat_queue.pop_front()
		Log.debug("comms", "Combat queue full (max %d): dropped '%s'" % [_combat_queue_max, dropped])
		_emit_finished.call_deferred(dropped)


func _start_combat(sequence_id: StringName) -> void:
	_combat = sequence_id
	_combat_lines = Config.sequence(sequence_id).get("lines", []) as Array
	_combat_index = 0
	_show_combat_line()
	Log.info("comms", "Combat sequence '%s' started" % sequence_id)


func _show_combat_line() -> void:
	var speaker: StringName = &""
	var text: String = ""
	var line: Dictionary = {}
	if _combat_index < _combat_lines.size() and _combat_lines[_combat_index] is Dictionary:
		line = _combat_lines[_combat_index]
		speaker = StringName(str(line.get("speaker", "")))
		text = str(line.get("text", ""))
	_reset_cut()
	var cut_raw: Variant = line.get(CUT_OFF_KEY)
	if cut_raw is int or cut_raw is float:
		_cut_phase = CutPhase.TYPING
		_cut_at = clampi(int(cut_raw), 0, text.length())
		var after_raw: Variant = line.get(AFTER_KEY)
		_cut_after = after_raw if after_raw is Dictionary else {}
		_combat_left_s = _cut_at / _cutoff_chars_per_s if _cutoff_chars_per_s > 0.0 else 0.0
	else:
		_combat_left_s = combat_line_s(text.length(), _chars_per_s, _combat_min_s, _combat_extra_s)
	if box != null:
		var cue: StringName = combat_cue(box.visible, box.current_speaker(), speaker)
		Audio.play_sfx(cue, 0.0, _combat_open_db if cue == COMBAT_OPEN_SFX else _combat_line_cue_db)
		box.show_line(speaker, text, _cut_at)
	Events.comms_line_shown.emit(speaker, shown_text(text, _cut_at, _cutoff_suffix), MODE_COMBAT)


## The text a line ends up showing: the whole text, or for a cut-off line
## (cut_at >= 0) its first cut_at characters plus the cut-off suffix.
static func shown_text(text: String, cut_at: int, suffix: String) -> String:
	return text if cut_at < 0 else text.left(cut_at) + suffix


## The key-in cue for a combat line (GDD decisions #41, #42): `comms_open_nobeep` when
## the box opens fresh (hidden), else (still up or fading from the previous
## line) `comms_handover` for a new speaker and `comms_click` for the same one.
static func combat_cue(box_visible: bool, previous_speaker: StringName, speaker: StringName) -> StringName:
	if not box_visible:
		return COMBAT_OPEN_SFX
	return HANDOVER_SFX if speaker != previous_speaker else CLICK_SFX


## The cut-off moment: the box stops at `cut_off_at` characters plus
## comms.cutoff_suffix, then the `after` effects run in order (sfx, shake,
## music, silence) and the line holds for comms.cutoff_hide_s more seconds of
## game time.
func _cut_off() -> void:
	_cut_phase = CutPhase.HOLD
	_combat_left_s += _cutoff_hide_s
	if box != null:
		box.cut_off(_cut_at, _cutoff_suffix)
	Log.info("comms", "Combat sequence '%s' cut off at %d characters" % [_combat, _cut_at])
	var sfx: Variant = _cut_after.get(DialogueValidator.AFTER_SFX)
	if sfx is String and not (sfx as String).is_empty():
		_cut_sfx_player = Audio.play_sfx(StringName(sfx as String), 0.0)
		_cut_sfx_stream = _cut_sfx_player.stream if _cut_sfx_player != null else null
	var shake: Variant = _cut_after.get(DialogueValidator.AFTER_SHAKE)
	if shake is String:
		if (shake as String) == DialogueValidator.SHAKE_CUTOFF:
			Feedback.shake(_cutoff_shake_px, _cutoff_shake_s)
		else:
			Feedback.shake_tier(ImpactTier.from_name(shake as String))
	var music: Variant = _cut_after.get(DialogueValidator.AFTER_MUSIC)
	if music is String:
		Audio.apply_music_action(StringName(music as String))
	var silence: Variant = _cut_after.get(DialogueValidator.AFTER_SILENCE)
	if silence is String and (silence as String) == DialogueValidator.SILENCE_UNTIL_WAVE_CLEAR:
		if _cut_wave_cleared:
			Log.debug("comms", "Silence from '%s' skipped: its wave already cleared" % _combat)
		else:
			_silence_on()


## Silences comms until the wave clears and drops every queued combat sequence
## (a deferred `finished` each).
func _silence_on() -> void:
	_silenced = true
	Log.info("comms", "Comms silenced until the wave clears (cut-off '%s')" % _combat)
	for dropped: StringName in _combat_queue:
		Log.debug("comms", "Comms silenced: dropped queued combat sequence '%s'" % dropped)
		_emit_finished.call_deferred(dropped)
	_combat_queue.clear()


func _on_events_wave_cleared(_wave_index: int) -> void:
	if _cut_phase == CutPhase.TYPING:
		_cut_wave_cleared = true
	if _silenced:
		_silenced = false
		Log.info("comms", "Comms silence lifted (wave cleared)")


## The game-time `delta` as real time (delta / time_scale), so the cut-off
## hold keeps step with the static under a slow-down. A time scale of 0 or
## less (a hit-stop freeze, where delta is 0 too) returns `delta`.
static func hold_step(delta: float, time_scale: float) -> float:
	return delta / time_scale if time_scale > 0.0 else delta


## comms.cutoff_suffix, or "" with an error when it isn't a String.
static func cutoff_suffix_from(comms: Dictionary) -> String:
	var raw: Variant = comms.get("cutoff_suffix")
	if raw is String:
		return raw
	Log.error("data", "tuning.comms.cutoff_suffix missing or not a string")
	return ""


## The cut-off's after-sfx player while it still plays that stream, else null.
func cut_sfx_player() -> AudioStreamPlayer:
	if _cut_sfx_player == null or not is_instance_valid(_cut_sfx_player):
		return null
	if _cut_sfx_player.stream != _cut_sfx_stream:
		return null
	return _cut_sfx_player


## Pauses or resumes the cut-off's after-sfx with the tree.
func _sync_cut_sfx_pause(paused: bool) -> void:
	var player: AudioStreamPlayer = cut_sfx_player()
	if player != null and player.stream_paused != paused:
		player.stream_paused = paused


## Stops the cut-off's after-sfx (unpaused, so the pooled player is clean).
func _stop_cut_sfx() -> void:
	var player: AudioStreamPlayer = cut_sfx_player()
	if player != null:
		player.stream_paused = false
		player.stop()
	_cut_sfx_player = null
	_cut_sfx_stream = null


func _reset_cut() -> void:
	_stop_cut_sfx()
	_cut_phase = CutPhase.NONE
	_cut_at = -1
	_cut_after = {}
	_cut_wave_cleared = false


func _start_next_combat() -> void:
	if not _combat_queue.is_empty():
		_start_combat(_combat_queue.pop_front())


## A story request drops the playing combat line: the box hides at once and
## the combat's `finished` goes out deferred. Queued combat lines stay.
func _preempt_combat(story_id: StringName) -> void:
	var dropped: StringName = _combat
	_clear_combat()
	if box != null:
		box.hide_now()
	Log.info("comms", "Combat sequence '%s' preempted by story '%s'" % [dropped, story_id])
	_emit_finished.call_deferred(dropped)


func _clear_combat() -> void:
	_combat = &""
	_combat_lines = []
	_combat_index = 0
	_combat_left_s = 0.0
	_reset_cut()
