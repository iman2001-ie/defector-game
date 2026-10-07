extends Node2D
## Debug sandbox (temporary main scene): fly the ship and fire the laser; later shoot targets.

@onready var _player: Player = $World/Player
@onready var _spawner: Spawner = $Spawner


func _ready() -> void:
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	_player.set_spawner(_spawner)
	Log.info("scene", "Sandbox ready")
