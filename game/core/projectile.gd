class_name Projectile
extends Area2D
## Base for every projectile: flies by velocity, frees itself off-screen and
## applies its damage to the first area it overlaps (one damage instance).
##
## Created only by Spawner: setup(params) stores values before add_child, and
## _ready() applies them.

## How far past the viewport edge a projectile may travel before it is freed.
const OFFSCREEN_MARGIN_PX: float = 64.0

var damage: int = 1
var velocity: Vector2 = Vector2.ZERO
## Set by ally shooters (later epics); enemies read it from the damage source.
var from_ally: bool = false

var _spawn_position: Vector2 = Vector2.ZERO
var _has_spawn_position: bool = false
var _bounds: Rect2
var _spent: bool = false


## Stores params; nothing is applied until _ready(). Keys: position (global),
## velocity, damage. Missing keys keep the current values.
func setup(params: Dictionary) -> void:
	if params.has("position"):
		_spawn_position = params["position"] as Vector2
		_has_spawn_position = true
	velocity = params.get("velocity", velocity) as Vector2
	damage = int(params.get("damage", damage))


func _ready() -> void:
	if _has_spawn_position:
		global_position = _spawn_position
	var size: Vector2 = Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	_bounds = Rect2(Vector2.ZERO, size).grow(OFFSCREEN_MARGIN_PX)
	add_to_group(&"projectiles")
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	position += velocity * delta
	if not _bounds.has_point(global_position):
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	if _spent:
		return
	_spent = true
	if area.has_method(&"apply_damage"):
		area.call(&"apply_damage", damage, self)
	_on_impact(area)
	queue_free()


## Impact hook (missile overrides it for splash). Feedback arrives in Story 1.6.
func _on_impact(_area: Area2D) -> void:
	pass
