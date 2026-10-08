extends Node
## The only owner of get_tree().paused and Input.mouse_mode.
##
## Holds a set of pause reasons (&"menu", &"story", &"final_choice", &"death").
## The tree is paused while any reason is active. The mouse is VISIBLE while
## paused, otherwise the gameplay mode the current scene declared.
##
## resumed fires on every paused -> unpaused transition (the last pop, or clear()
## while paused), after the mouse mode is written. The Player answers it by warping
## the cursor onto the ship, so the ship never jumps after a pause.

## Emitted once per paused -> unpaused transition, after mouse_mode is written.
signal resumed

var _reasons: Dictionary = {}  # StringName -> true
var _gameplay_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
## The paused state _apply() last wrote, to detect the resume transition.
var _was_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func push(reason: StringName) -> void:
	_reasons[reason] = true
	_apply()


func pop(reason: StringName) -> void:
	_reasons.erase(reason)
	_apply()


func is_paused() -> bool:
	return not _reasons.is_empty()


## A copy of the active pause reasons (for the debug overlay).
func reasons() -> Array[StringName]:
	var out: Array[StringName] = []
	for reason: StringName in _reasons:
		out.append(reason)
	return out


## SceneRouter calls this on every scene change.
func clear() -> void:
	_reasons.clear()
	_apply()


## Scenes declare their gameplay mode: gameplay scenes CONFINED_HIDDEN, menus VISIBLE.
func set_gameplay_mouse_mode(mode: Input.MouseMode) -> void:
	_gameplay_mode = mode
	_apply()


## The mode _apply() writes: VISIBLE while paused, else the gameplay mode.
func current_mouse_mode() -> Input.MouseMode:
	return Input.MOUSE_MODE_VISIBLE if is_paused() else _gameplay_mode


func _apply() -> void:
	var paused: bool = is_paused()
	get_tree().paused = paused
	Input.mouse_mode = current_mouse_mode()
	var resuming: bool = _was_paused and not paused
	_was_paused = paused
	if resuming:
		resumed.emit()
