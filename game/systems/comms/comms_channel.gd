class_name CommsChannel
extends Node
## The single dialogue delivery path (Story 5.1, architecture "Comms Channel").
## Listens to Events.comms_sequence_requested, owns the story queue and the
## `story` pause reason, drives the CommsPanel view and emits
## Events.comms_sequence_finished.
##
## - Unknown id: Log.error, then a deferred `finished(id)` (never inside the
##   request, so a caller that emits and then awaits `finished` can't hang).
## - Combat mode (Story 5.2 builds it): Log.warn and a deferred `finished`;
##   no pause, nothing shown.
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

const PAUSE_REASON: StringName = &"story"
const MENU_REASON: StringName = &"menu"
const ADVANCE_ACTION: StringName = &"comms_advance"
const OPEN_SFX: StringName = &"comms_open"

@export var panel: CommsPanel

## Id of the story sequence on the panel; &"" while idle.
var _current: StringName = &""
var _lines: Array = []
var _index: int = 0
var _armed: bool = false
var _queue: Array[StringName] = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	if panel == null:
		Log.error("comms", "CommsChannel has no panel; story lines are not shown")
	Events.comms_sequence_requested.connect(_on_events_comms_sequence_requested)


func _exit_tree() -> void:
	if Events.comms_sequence_requested.is_connected(_on_events_comms_sequence_requested):
		Events.comms_sequence_requested.disconnect(_on_events_comms_sequence_requested)


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


# --- Requests ----------------------------------------------------------------------

func _on_events_comms_sequence_requested(sequence_id: StringName) -> void:
	if not Config.has_sequence(sequence_id):
		Log.error("comms", "Unknown comms sequence '%s'" % sequence_id)
		_emit_finished.call_deferred(sequence_id)
		return
	if not Config.dialogue_is_story(sequence_id):
		Log.warn("comms", "Combat sequence '%s' not shown: combat comms arrive in Story 5.2" % sequence_id)
		_emit_finished.call_deferred(sequence_id)
		return
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
