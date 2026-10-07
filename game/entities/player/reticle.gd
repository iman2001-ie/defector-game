extends Sprite2D
## Marks the cursor in world space. Visual only, so it updates in _process.


func _process(_delta: float) -> void:
	global_position = get_global_mouse_position()
