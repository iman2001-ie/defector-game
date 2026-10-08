class_name ShieldBubble
extends Node2D
## The Shield bubble on the ship (UX `shieldBubble`, Story 3.4). A Player child
## drawn in-world: a `coalition` ring of player.shield_bubble.diameter_px /
## stroke_px at `alpha`, centred on the ship.
##
## Driven by the Player only: show_remaining(remaining_s) every shield tick
## (<= 0 hides it) and hide_bubble() when the shield ends or the ship dies. In
## the last blink_last_s it blinks at blink_hz (see is_lit). Hidden by default.

## UX `shieldBubble` ring: token `coalition`.
const RING_COLOR: Color = Color("#22E6FF")
const ARC_POINTS: int = 64

var diameter_px: float = 0.0
var stroke_px: float = 0.0
var alpha: float = 0.0
var blink_hz: float = 0.0
var blink_last_s: float = 0.0


func _ready() -> void:
	diameter_px = maxf(Config.num("player.shield_bubble.diameter_px"), 0.0)
	stroke_px = maxf(Config.num("player.shield_bubble.stroke_px"), 0.0)
	alpha = clampf(Config.num("player.shield_bubble.alpha"), 0.0, 1.0)
	blink_hz = maxf(Config.num("player.shield_bubble.blink_hz"), 0.0)
	blink_last_s = maxf(Config.num("player.shield_bubble.blink_last_s"), 0.0)
	visible = false
	queue_redraw()


## Ring radius in px (half the tuned diameter).
func radius_px() -> float:
	return diameter_px / 2.0


## The ring colour: `coalition` at the tuned alpha.
func ring_color() -> Color:
	return Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, alpha)


## Shows the bubble for `remaining_s` of shield left (blinking near the end);
## remaining_s <= 0 hides it.
func show_remaining(remaining_s: float) -> void:
	visible = remaining_s > 0.0 and is_lit(remaining_s, blink_last_s, blink_hz)


func hide_bubble() -> void:
	visible = false


## True when the bubble is drawn with `remaining` s left: always above
## `last_s`; inside that window it blinks at `hz`, lit for the first half of
## each cycle, with the phase starting at the window's start.
static func is_lit(remaining: float, last_s: float, hz: float) -> bool:
	if remaining > last_s:
		return true
	var t: float = last_s - remaining
	return fmod(t * hz, 1.0) < 0.5


func _draw() -> void:
	if diameter_px <= 0.0 or stroke_px <= 0.0:
		return
	draw_arc(Vector2.ZERO, radius_px(), 0.0, TAU, ARC_POINTS, ring_color(), stroke_px, true)
