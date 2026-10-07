class_name MissileRing
extends Node2D
## The missile cooldown ring on the ship (UX token `missileRing`, GDD decisions
## #29/#31). A Player child drawn above the hull sprite.
##
## Driven only by Events.missile_cooldown_changed (1 = just fired, 0 = ready): it
## sweeps clockwise from 12 o'clock over the fraction of the cooldown left and
## draws nothing when the missile is ready. A `text` stroke over a `background`
## outline, so it reads over the cyan hull and over explosions.

## UX `missileRing` stroke: token `text`.
const STROKE_COLOR: Color = Color("#E8F4FF")
## UX `missileRing` outline: token `background`.
const OUTLINE_COLOR: Color = Color("#05070F")
## UX `missileRing`: the outline shows this many px on each side of the stroke.
const OUTLINE_PX: float = 2.0
## 12 o'clock; angles grow clockwise on screen (y points down).
const START_ANGLE: float = -PI / 2.0
const ARC_POINTS: int = 48

## 0..1 fraction of the cooldown left; 0 = ready (nothing drawn).
var cooldown_ratio: float = 0.0
var radius_px: float
var stroke_px: float


func _ready() -> void:
	radius_px = Config.num("player.missile_ring.radius_px")
	stroke_px = Config.num("player.missile_ring.stroke_px")
	var max_radius: float = Config.num("player.sprite_px") / 2.0
	if radius_px > max_radius:
		Log.warn("data", "player.missile_ring.radius_px %.1f is larger than half of player.sprite_px; clamped to %.1f" % [radius_px, max_radius])
		radius_px = max_radius
	Events.missile_cooldown_changed.connect(_on_missile_cooldown_changed)


func should_draw() -> bool:
	return cooldown_ratio > 0.0


## End angle of the arc for a cooldown ratio: a clockwise sweep from 12 o'clock.
static func end_angle(ratio: float) -> float:
	return START_ANGLE + TAU * ratio


func _draw() -> void:
	if not should_draw():
		return
	var end: float = end_angle(cooldown_ratio)
	draw_arc(Vector2.ZERO, radius_px, START_ANGLE, end, ARC_POINTS, OUTLINE_COLOR,
			stroke_px + 2.0 * OUTLINE_PX, true)
	draw_arc(Vector2.ZERO, radius_px, START_ANGLE, end, ARC_POINTS, STROKE_COLOR, stroke_px, true)


func _on_missile_cooldown_changed(ratio: float) -> void:
	cooldown_ratio = clampf(ratio, 0.0, 1.0)
	queue_redraw()
