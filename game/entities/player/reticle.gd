extends Sprite2D
## Marks the cursor in world space. Visual only, so it updates in _process.
## Draws the missile cooldown arc, driven only by Events.missile_cooldown_changed:
## it sweeps clockwise from 12 o'clock over the fraction of the cooldown left.

const COOLDOWN_RADIUS_PX: float = 22.0
const COOLDOWN_WIDTH_PX: float = 4.0
## UX spec `muted`.
const COOLDOWN_COLOR: Color = Color("#93A7C2")
const COOLDOWN_ARC_POINTS: int = 48

## 1 = missile just fired, 0 = ready (no arc).
var cooldown_ratio: float = 0.0


func _ready() -> void:
	Events.missile_cooldown_changed.connect(_on_missile_cooldown_changed)


func _process(_delta: float) -> void:
	global_position = get_global_mouse_position()


func _draw() -> void:
	if cooldown_ratio <= 0.0:
		return
	var start: float = -PI / 2.0
	draw_arc(Vector2.ZERO, COOLDOWN_RADIUS_PX, start, start + TAU * cooldown_ratio,
			COOLDOWN_ARC_POINTS, COOLDOWN_COLOR, COOLDOWN_WIDTH_PX, true)


func _on_missile_cooldown_changed(ratio: float) -> void:
	cooldown_ratio = clampf(ratio, 0.0, 1.0)
	queue_redraw()
