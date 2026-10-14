class_name ConvoyShip
extends Area2D
## One cargo hull of the escort convoy (Story 6.1, DW-83, GDD #24). Layer
## `convoy`, mask 0, monitoring off: it detects nothing; projectiles and the
## Player find it.
##
## The Hitbox RectangleShape2D is convoy.ship_width_px x ship_height_px scaled by
## convoy.hitbox_ratio, set in _ready. The hull (Story 8.2) is the `Sprite`
## child: a Kenney cargo hull turned nose-up and recoloured a dimmed `coalition`
## (so it reads as civilian cargo, not a fighter), fitted uniformly inside
## ship_width_px x ship_height_px. outline() stays as the hull's shape data:
## ship_width_px x ship_height_px, nose-up, a flat bottom and the top quarter of
## the height tapered to a point at (0, -h/2). apply_damage forwards to the
## Convoy, which owns the shared HP pool. The ship never rotates, so
## hull_rect() is an axis-aligned global rect; the Convoy builds its solid hull
## polygon from the three.

## The Convoy this hull belongs to (set by the Convoy in its _ready).
var convoy: Convoy = null

var _size: Vector2 = Vector2.ZERO
var _hitbox_size: Vector2 = Vector2.ZERO
var _outline: PackedVector2Array = PackedVector2Array()

@onready var _hitbox: CollisionShape2D = $Hitbox
@onready var _sprite: Sprite2D = get_node_or_null(^"Sprite") as Sprite2D


func _ready() -> void:
	_size = Vector2(Config.num("convoy.ship_width_px"), Config.num("convoy.ship_height_px"))
	_hitbox_size = _size * Config.num("convoy.hitbox_ratio")
	var rect: RectangleShape2D = _hitbox.shape as RectangleShape2D
	if rect != null:
		rect.size = _hitbox_size
	_build_outline()
	if _sprite != null:
		SpriteFit.fit_inside(_sprite, _size, "convoy ship")


## The drawn hull size (ship_width_px x ship_height_px).
func hull_size() -> Vector2:
	return _size


## The hitbox size (the hull size times hitbox_ratio).
func hitbox_size() -> Vector2:
	return _hitbox_size


## The global hitbox rect (centred on the ship; the ship never rotates).
func hull_rect() -> Rect2:
	return Rect2(global_position - _hitbox_size / 2.0, _hitbox_size)


## The drawn hull outline (local points, nose-up).
func outline() -> PackedVector2Array:
	return _outline


## Forwards a hit to the Convoy's shared HP pool (nothing without a Convoy).
func apply_damage(amount: int, source: Node) -> void:
	if convoy != null and is_instance_valid(convoy):
		convoy.apply_damage(amount, source)


## The hull Sprite (null if the scene lacks it).
func hull_sprite() -> Sprite2D:
	return _sprite


## A blunt nose-up cargo hull: a flat bottom, straight sides, and the top
## quarter of the height tapered to a point at the top centre.
func _build_outline() -> void:
	var hw: float = _size.x / 2.0
	var hh: float = _size.y / 2.0
	if hw <= 0.0 or hh <= 0.0:
		_outline = PackedVector2Array()
		return
	var taper: float = _size.y / 4.0
	_outline = PackedVector2Array([
		Vector2(-hw, hh),
		Vector2(-hw, -hh + taper),
		Vector2(0.0, -hh),
		Vector2(hw, -hh + taper),
		Vector2(hw, hh),
	])
