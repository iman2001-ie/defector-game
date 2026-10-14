class_name Ram
extends Node2D
## The Ram (Tarek's fall, playtest 2026-10-13): a bigger, spikier Maul that
## dives from the top edge straight at Vale, too fast to dodge, and strikes
## Tarek, who has put his ship in the way. A visual-only story prop: no
## collision, never in Groups.ENEMIES, never counted, never a target. Spawned
## only by TarekFallScene through Spawner.spawn_ram.
##
## setup({"from": Vector2, "to": Vector2, "travel_s": float, "scale": float})
## before add_child. It flies from `from` to `to` in a straight line at a
## constant speed, taking exactly travel_s seconds of game time (so it slows
## with Feedback's slow motion and freezes under a pause or a hit-stop), with its
## nose (local +y, like the Maul's) along the line. On arrival it emits
## `arrived` once and frees itself; the director plays the impact.
## step(delta) is the test seam (_physics_process calls it).
##
## Story 8.2: the `Hull` is the Maul's recoloured Kenney sprite, fitted in
## _ready so its longer side is sprite_px (before the root's size_scale).

signal arrived

## The Hull sprite's longer side in px, before the root scale (`scale` param).
@export var sprite_px: float = 120.0

var from: Vector2 = Vector2.ZERO
var to: Vector2 = Vector2.ZERO
var travel_s: float = 0.0
var size_scale: float = 1.0

var _t: float = 0.0
var _done: bool = false


func setup(params: Dictionary) -> void:
	if params.get("from") is Vector2:
		from = params["from"] as Vector2
	if params.get("to") is Vector2:
		to = params["to"] as Vector2
	var travel: Variant = params.get("travel_s", 0.0)
	travel_s = maxf(float(travel), 0.0) if (travel is float or travel is int) else 0.0
	var size: Variant = params.get("scale", 1.0)
	size_scale = maxf(float(size), 0.01) if (size is float or size is int) else 1.0


func _ready() -> void:
	var hull: Sprite2D = get_node_or_null(^"Hull") as Sprite2D
	if hull != null:
		SpriteFit.fit_longest(hull, sprite_px, "ram")
	global_position = from
	scale = Vector2.ONE * size_scale
	if to != from:
		rotation = (to - from).angle() - PI / 2.0


func _physics_process(delta: float) -> void:
	step(delta)


## Advances the dive by `delta` seconds; on reaching `to` emits `arrived` once
## and frees the Ram.
func step(delta: float) -> void:
	if _done:
		return
	_t += maxf(delta, 0.0)
	var k: float = 1.0 if travel_s <= 0.0 else clampf(_t / travel_s, 0.0, 1.0)
	global_position = from.lerp(to, k)
	if k >= 1.0:
		_done = true
		arrived.emit()
		queue_free()


func has_arrived() -> bool:
	return _done
