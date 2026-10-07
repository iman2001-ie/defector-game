class_name ShockwaveRing
extends Node2D
## Expanding, fading ring drawn with draw_arc. The owning Explosion drives progress.

const START_RADIUS_PX: float = 8.0
const END_RADIUS_PX: float = 96.0
const WIDTH_PX: float = 4.0
const SEGMENTS: int = 48
## hazardRim (#C9D8E8): the ring reads as a pressure wave, not a faction colour.
const COLOR: Color = Color(0.788, 0.847, 0.910, 1.0)

## 0 = just started, 1 = fully expanded and invisible.
var progress: float = 0.0


func set_progress(p: float) -> void:
	progress = clampf(p, 0.0, 1.0)
	queue_redraw()


func current_radius() -> float:
	return lerpf(START_RADIUS_PX, END_RADIUS_PX, progress)


func _draw() -> void:
	if progress >= 1.0:
		return
	var colour: Color = COLOR
	colour.a = 1.0 - progress
	draw_arc(Vector2.ZERO, current_radius(), 0.0, TAU, SEGMENTS, colour, WIDTH_PX, true)
