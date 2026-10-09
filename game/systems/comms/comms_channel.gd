class_name CommsChannel
extends Node
## The single dialogue delivery path (Stories 5.1-5.4, architecture "Comms
## Channel"). Listens to Events.comms_sequence_requested, owns the story and
## combat queues and the `story` pause reason, drives the CommsPanel (story)
## and CommsBox (combat) views and emits Events.comms_sequence_finished. Every
## requested known sequence finishes exactly once (played, preempted or
## dropped).
##
## - Unknown id: Log.error, then a deferred `finished(id)` (never inside the
##   request, so a caller that emits and then awaits `finished` can't hang).
## - Combat mode (Story 5.2): no pause, no SFX, input untouched. While idle the
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
## - Cut-off (Story 5.4): a combat line with `cut_off_at` (a combat sequence
##   has one line, so it is the whole sequence) types to exactly `cut_off_at`
##   characters over cut_off_at / chars_per_s s of game time. At that moment
##   the box stops there and the `after` effects run in order: the sfx
##   (Audio.play_sfx), the shake tier (Feedback.shake_tier), the music action
##   (Audio.apply_music_action), then silence. comms.cutoff_hide_s later the
##   box hides at once (no fade) and `finished` is emitted. Both phases count
##   game time in step_combat, so a pause freezes them. A story that preempts
##   the line before its cut-off moment drops it with no effects.
## - Silence (`after.silence: until_wave_clear`): drops every queued combat
##   sequence and every later combat request (DEBUG, deferred `finished`);
##   story sequences still play. Events.wave_cleared lifts it. A wave_cleared
##   between the cut-off line's start and its cut-off moment voids the
##   silence, so it never carries into the next wave.

const PAUSE_REASON: StringName = &"story"
const MENU_REASON: StringName = &"menu"
const ADVANCE_ACTION: StringName = &"comms_advance"
const OPEN_SFX: StringName = &"comms_open"
## Slack for the combat line timer, so float steps that add up to the line
## time (1.9 + 0.1 s) end it.
const COMBAT_EPSILON_S: float = 0.000001
## Cut-off line keys (Story 5.4, see DialogueValidator).
const CUT_OFF_KEY: String = DialogueValidator.CUT_OFF_KEY
const AFTER_KEY: String = DialogueValidator.AFTER_KEY

## Phases of the playing combat line: a plain line, a cut-off line typing
## towards its cut-off moment, a cut-off line holding before it hides.
enum CutPhase { NONE, TYPING, HOLD }

@export var panel: CommsPanel
@export var box: CommsBox

## Id of the story sequence on the panel; &"" while idle.
var _current: StringName = &""
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
var _combat_queue_max: int = 0
var _cutoff_hide_s: float = 0.0

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
	_combat_queue_max = maxi(Config.int_("comms.combat_queue_max"), 0)
	_cutoff_hide_s = maxf(Config.num("comms.cutoff_hide_s"), 0.0)
	Events.comms_sequence_requested.connect(_on_events_comms_sequence_requested)
	Events.wave_cleared.connect(_on_events_wave_cleared)


func _exit_tree() -> void:
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
	_lines = seq.get("lines", []) as Array
	_index = 0
	_armed = false
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
	panel.show_line(StringName(str(line.get("speaker", ""))), str(line.get("text", "")))


func _emit_finished(sequence_id: StringName) -> void:
	Events.comms_sequence_finished.emit(sequence_id)


# --- Input and advancing -----------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_showing() or PauseArbiter.has_reason(MENU_REASON):
		return
	if not event.is_action(ADVANCE_ACTION):
		return
	get_viewport().set_input_as_handled()
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
	if not is_showing():
		return
	if panel != null and panel.is_typing():
		panel.complete_line()
		return
	_index += 1
	if _index < _lines.size():
		_show_line()
		return
	_finish()


func _finish() -> void:
	var finished_id: StringName = _current
	Log.info("comms", "Story sequence '%s' finished" % finished_id)
	if not _queue.is_empty():
		# Still showing while `finished` goes out, so a story requested by a
		# listener queues behind the ones already waiting.
		var next_id: StringName = _queue.pop_front()
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
	Events.comms_sequence_finished.emit(finished_id)
	if not is_showing() and not is_playing_combat():
		_start_next_combat()


# --- Combat ------------------------------------------------------------------------

func _process(delta: float) -> void:
	if is_playing_combat() and not get_tree().paused:
		step_combat(delta)


## Counts the current combat line down by `delta` s of game time. At the end it
## shows the next line or, after the last, fades the box, logs, emits
## `finished` and starts the next queued combat if no story is showing and
## nothing (a `finished` listener) started one. A cut-off line first reaches
## its cut-off moment (see _cut_off), then holds for comms.cutoff_hide_s and
## hides the box at once instead of fading it.
func step_combat(delta: float) -> void:
	if not is_playing_combat():
		return
	_combat_left_s -= delta
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
		_combat_left_s = _cut_at / _chars_per_s if _chars_per_s > 0.0 else 0.0
	else:
		_combat_left_s = combat_line_s(text.length(), _chars_per_s, _combat_min_s, _combat_extra_s)
	if box != null:
		box.show_line(speaker, text, _cut_at)


## The cut-off moment: the box stops at `cut_off_at` characters, then the
## `after` effects run in order (sfx, shake, music, silence) and the line holds
## for comms.cutoff_hide_s more seconds of game time.
func _cut_off() -> void:
	_cut_phase = CutPhase.HOLD
	_combat_left_s += _cutoff_hide_s
	if box != null:
		box.cut_off(_cut_at)
	Log.info("comms", "Combat sequence '%s' cut off at %d characters" % [_combat, _cut_at])
	var sfx: Variant = _cut_after.get(DialogueValidator.AFTER_SFX)
	if sfx is String and not (sfx as String).is_empty():
		Audio.play_sfx(StringName(sfx as String), 0.0)
	var shake: Variant = _cut_after.get(DialogueValidator.AFTER_SHAKE)
	if shake is String:
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


func _reset_cut() -> void:
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
