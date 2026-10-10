class_name ConvoyShip
extends Area2D
## One cargo hull of the escort convoy (Story 6.1, GDD #24). Layer `convoy`,
## mask 0, monitoring off: it detects nothing; projectiles and the Player find it.
##
## The Hitbox RectangleShape2D is convoy.ship_width_px x ship_height_px scaled by
## convoy.hitbox_ratio, set in _ready. The hull is drawn in code (no image asset):
## a dim `coalition` body with a bright `coalition` outline, ship_width_px x
## ship_height_px, its nose toward `facing` (+1 right, -1 left), which the Convoy
## sets. apply_damage forwards to the Convoy, which owns the shared HP pool. The
## ship never rotates, so hull_rect() is an axis-aligned global rect.

## `coalition` (#22E6FF): the convoy's in-world colour (UX DESIGN).
const OUTLINE_COLOR: Color = Color("#22E6FF")
## The body is the coalition colour dimmed, so the hulls read as civilian cargo.
const BODY_COLOR: Color = Color(0.133333, 0.901961, 1.0, 0.22)
const OUTLINE_PX: float = 2.0

## +1: nose to the right; -1: nose to the left. Redraws on change.
var facing: int = 1:
	set(value):
		var next: int = -1 if value < 0 else 1
		if next == facing:
			return
		facing = next
		_build_outline()
		queue_redraw()

## The Convoy this hull belongs to (set by the Convoy in its _ready).
var convoy: Convoy = null

var _size: Vector2 = Vector2.ZERO
var _hitbox_size: Vector2 = Vector2.ZERO
var _outline: PackedVector2Array = PackedVector2Array()

@onready var _hitbox: CollisionShape2D = $Hitbox


func _ready() -> void:
	_size = Vector2(Config.num("convoy.ship_width_px"), Config.num("convoy.ship_height_px"))
	_hitbox_size = _size * Config.num("convoy.hitbox_ratio")
	var rect: RectangleShape2D = _hitbox.shape as RectangleShape2D
	if rect != null:
		rect.size = _hitbox_size
	_build_outline()
	queue_redraw()


## The drawn hull size (ship_width_px x ship_height_px).
func hull_size() -> Vector2:
	return _size


## The hitbox size (the hull size times hitbox_ratio).
func hitbox_size() -> Vector2:
	return _hitbox_size


## The global hitbox rect (centred on the ship; the ship never rotates).
func hull_rect() -> Rect2:
	return Rect2(global_position - _hitbox_size / 2.0, _hitbox_size)


## The drawn hull outline (local points, nose toward `facing`).
func outline() -> PackedVector2Array:
	return _outline


## Forwards a hit to the Convoy's shared HP pool (nothing without a Convoy).
func apply_damage(amount: int, source: Node) -> void:
	if convoy != null and is_instance_valid(convoy):
		convoy.apply_damage(amount, source)


func _draw() -> void:
	if _outline.size() < 3:
		return
	draw_colored_polygon(_outline, BODY_COLOR)
	var closed: PackedVector2Array = _outline.duplicate()
	closed.append(_outline[0])
	draw_polyline(closed, OUTLINE_COLOR, OUTLINE_PX, true)


## A blunt cargo hull: a long box with a tapered nose (the last quarter of the
## height) on the `facing` side.
func _build_outline() -> void:
	var hw: float = _size.x / 2.0
	var hh: float = _size.y / 2.0
	if hw <= 0.0 or hh <= 0.0:
		_outline = PackedVector2Array()
		return
	var nose: float = minf(hh, hw)
	var f: float = float(facing)
	_outline = PackedVector2Array([
		Vector2(-hw * f, -hh),
		Vector2((hw - nose) * f, -hh),
		Vector2(hw * f, 0.0),
		Vector2((hw - nose) * f, hh),
		Vector2(-hw * f, hh),
	])
