class_name Enemy
extends Area2D
## Base for every enemy: HP and tier from tuning, damage intake, one-shot death.
##
## Created only by Spawner: setup(params) stores values before add_child, and
## _ready() applies them. `resolved` is emitted exactly once.

signal resolved

## Size of the enemy's sprite in px; the hitbox circle is hitbox_ratio of it.
@export var sprite_px: float = 64.0

var type_id: StringName
var tier: int = ImpactTier.SMALL
var hp: int = 0

var _spawn_position: Vector2 = Vector2.ZERO
var _has_spawn_position: bool = false
var _last_hit_by_ally: bool = false
var _dead: bool = false


## Stores params; nothing is applied until _ready(). Keys: position (global).
func setup(params: Dictionary) -> void:
	if params.has("position"):
		_spawn_position = params["position"] as Vector2
		_has_spawn_position = true


func _ready() -> void:
	if _has_spawn_position:
		global_position = _spawn_position
	var key: String = "enemies.%s" % type_id
	hp = Config.int_(key + ".hp")
	tier = ImpactTier.from_name(str(Config.section(key).get("tier", "")))
	var hitbox: CollisionShape2D = get_node_or_null(^"Hitbox") as CollisionShape2D
	if hitbox != null:
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = sprite_px / 2.0 * Config.num(key + ".hitbox_ratio")
		hitbox.shape = circle
	else:
		Log.error("combat", "enemy '%s' has no Hitbox" % type_id)
	add_to_group(&"enemies")


func apply_damage(amount: int, source: Node) -> void:
	if _dead:
		return
	_last_hit_by_ally = source != null and source.get(&"from_ally") == true
	hp -= amount
	if hp <= 0:
		_die()


## Contact with the player destroys the enemy outright (GDD contact table).
func destroy_by_contact() -> void:
	if _dead:
		return
	_last_hit_by_ally = false
	_die()


func is_dead() -> bool:
	return _dead


func _die() -> void:
	if _dead:
		return
	_dead = true
	# Feedback.impact(tier, global_position) arrives in Story 1.6; drops in Epic 4.
	Events.enemy_killed.emit(type_id, global_position, _last_hit_by_ally)
	resolved.emit()
	queue_free()
