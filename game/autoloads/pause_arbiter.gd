extends Node
## The only owner of get_tree().paused and Input.mouse_mode.
##
## Holds a set of pause reasons (&"menu", &"story", &"final_choice", &"death").
## The tree is paused while any reason is active. The mouse is VISIBLE while
## paused, otherwise the gameplay mode the current scene declared.

var _reasons: Dictionary = {}  # StringName -> true
var _gameplay_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


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


## SceneRouter calls this on every scene change (later epics).
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
	get_tree().paused = is_paused()
	Input.mouse_mode = current_mouse_mode()
