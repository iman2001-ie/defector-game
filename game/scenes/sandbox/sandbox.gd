extends Node2D
## Debug sandbox (temporary main scene): fly the ship, later shoot targets.


func _ready() -> void:
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	Log.info("scene", "Sandbox ready")
