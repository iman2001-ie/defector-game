class_name Enemy
extends Area2D
## Base for every enemy: HP and tier from tuning, damage intake, one-shot death.
##
## Created only by Spawner: setup(params) stores values before add_child, and
## _ready() applies them. `resolved` is emitted exactly once.
##
## Shared subclass helpers: `_slot`/`_has_slot`/`_entry` from setup params,
## _entry_start_for() (off-screen entry start), _aim_from() (aim at the player),
## _can_fire() (missing-spawner guard) and _tuning_key() ("enemies.<type_id>.<field>").

signal resolved

const ENTRY_TOP: StringName = &"top"
const ENTRY_SIDES: StringName = &"sides"
const PLAYER_GROUP: StringName = &"player"

## Size of the enemy's sprite in px; the hitbox circle is hitbox_ratio of it.
@export var sprite_px: float = 64.0

var type_id: StringName
## Set by Spawner before add_child; shooters request projectiles through it.
## Null for enemies created outside a Spawner (some tests).
var spawner: Spawner = null
var tier: int = ImpactTier.SMALL
var hp: int = 0

var _spawn_position: Vector2 = Vector2.ZERO
var _has_spawn_position: bool = false
var _last_hit_by_ally: bool = false
var _dead: bool = false
## Formation slot (global) from the `slot` param; how each subclass uses it is
## its own (and _has_slot false means the sandbox: no entry flight).
var _slot: Vector2 = Vector2.ZERO
var _has_slot: bool = false
## Entry side from the `entry` param: ENTRY_TOP or ENTRY_SIDES.
var _entry: StringName = ENTRY_TOP
## Set once _can_fire() has logged the missing spawner.
var _warned_no_spawner: bool = false


## Stores params; nothing is applied until _ready(). Keys: position (global),
## slot (formation slot, global), entry (&"top" | &"sides").
func setup(params: Dictionary) -> void:
	if params.has("position"):
		_spawn_position = params["position"] as Vector2
		_has_spawn_position = true
	if params.has("slot"):
		_slot = params["slot"] as Vector2
		_has_slot = true
	if params.has("entry"):
		_entry = StringName(str(params["entry"]))


func _ready() -> void:
	if _has_spawn_position:
		global_position = _spawn_position
	hp = Config.int_(_tuning_key("hp"))
	tier = ImpactTier.from_name(str(Config.section("enemies.%s" % type_id).get("tier", "")))
	var hitbox: CollisionShape2D = get_node_or_null(^"Hitbox") as CollisionShape2D
	if hitbox != null:
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = sprite_px / 2.0 * Config.num(_tuning_key("hitbox_ratio"))
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


## Contact with the player destroys a small or medium enemy outright (GDD
## contact table). Large enemies (Bastion, Flagship parts) ignore contact.
func destroy_by_contact() -> void:
	if _dead:
		return
	if tier != ImpactTier.SMALL and tier != ImpactTier.MEDIUM:
		return
	_last_hit_by_ally = false
	_die()


func is_dead() -> bool:
	return _dead


func _die() -> void:
	if _dead:
		return
	_dead = true
	Feedback.impact(tier, global_position)
	# Drops arrive in Epic 4.
	Events.enemy_killed.emit(type_id, global_position, _last_hit_by_ally)
	resolved.emit()
	queue_free()


## Where an entry flight toward `target` starts, just off screen on the `_entry`
## side: above `target` for ENTRY_TOP; level with it past the nearer side edge
## for ENTRY_SIDES (x <= the playfield centre counts as left). Any other entry
## logs a WARN and uses top.
func _entry_start_for(target: Vector2) -> Vector2:
	var half: float = sprite_px / 2.0
	if _entry == ENTRY_SIDES:
		var x: float = -half if target.x <= Playfield.SIZE.x / 2.0 else Playfield.SIZE.x + half
		return Vector2(x, target.y)
	if _entry != ENTRY_TOP:
		Log.warn("spawn", "%s entry '%s' is unknown; using top" % [type_id, _entry])
	return Vector2(target.x, -half)


## Unit direction from `origin` toward the player's current position; straight
## down with no player or a zero vector.
func _aim_from(origin: Vector2) -> Vector2:
	var player: Node2D = get_tree().get_first_node_in_group(PLAYER_GROUP) as Node2D
	if player == null:
		return Vector2.DOWN
	var to_player: Vector2 = player.global_position - origin
	if to_player.is_zero_approx():
		return Vector2.DOWN
	return to_player.normalized()


## True when `spawner` can take a projectile request. Without one, logs a DEBUG
## line once per enemy and returns false (the shot is skipped).
func _can_fire() -> bool:
	if spawner != null and is_instance_valid(spawner):
		return true
	if not _warned_no_spawner:
		_warned_no_spawner = true
		Log.debug("spawn", "%s has no spawner; shot skipped" % type_id)
	return false


## Config key for this enemy's tuning `field`: "enemies.<type_id>.<field>".
func _tuning_key(field: String) -> String:
	return "enemies.%s.%s" % [type_id, field]
