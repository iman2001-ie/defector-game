class_name Projectile
extends Area2D
## Base for every projectile: flies by velocity, frees itself off-screen and
## applies its damage to the first area it overlaps (one damage instance).
##
## The convoy is solid to every projectile (Story 6.1, GDD #23, #46): a shot that
## reaches a convoy-layer area stops and frees itself like any other hit. Player
## and ally shots (this base, laser, missile, micro-missile) never damage it
## (_can_damage, DW-32) and show the laser's SMALL blocked-shot effect whatever
## their own impact_tier (_on_impact); the Missile also skips its splash (DW-33).
## EnemyBullet overrides both hooks, so enemy shots do damage the convoy.
##
## Created only by Spawner: setup(params) stores values before add_child, and
## _ready() applies them.

## How far past the playfield edge a projectile may travel before it is freed.
const OFFSCREEN_MARGIN_PX: float = 64.0

var damage: int = 1
var velocity: Vector2 = Vector2.ZERO
## Set by ally shooters (later epics); enemies read it from the damage source.
var from_ally: bool = false
## Feedback tier played where this projectile hits (missile: MEDIUM).
var impact_tier: int = ImpactTier.SMALL

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
	_bounds = Playfield.RECT.grow(OFFSCREEN_MARGIN_PX)
	add_to_group(Groups.PROJECTILES)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	position += velocity * delta
	if not _bounds.has_point(global_position):
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	if _spent:
		return
	_spent = true
	if area.has_method(&"apply_damage") and _can_damage(area):
		area.call(&"apply_damage", damage, self)
	_on_impact(area)
	queue_free()


## True when `area` sits on the convoy collision layer (a ConvoyShip).
static func is_convoy(area: Area2D) -> bool:
	return area != null and (area.collision_layer & CollisionLayers.CONVOY) != 0


## Damage hook: false stops this projectile from damaging `area` (it still
## stops and frees). The base refuses convoy areas, so player and ally shots are
## blocked with no friendly fire (DW-32). EnemyBullet overrides it so enemy shots
## never chip asteroids but do damage the convoy.
func _can_damage(area: Area2D) -> bool:
	return not is_convoy(area)


## Impact hook: plays the impact feedback, SMALL (the laser's blocked-shot effect)
## on a convoy area, else impact_tier. Missile overrides it for splash and then
## calls this base version.
func _on_impact(area: Area2D) -> void:
	Feedback.impact(ImpactTier.SMALL if is_convoy(area) else impact_tier, global_position)
