class_name Enemy
extends Area2D
## Base for every enemy: HP and tier from tuning, damage intake, one-shot death.
##
## Created only by Spawner: setup(params) stores values before add_child, and
## _ready() applies them. `resolved` is emitted exactly once: through _die()
## (a kill) or _resolve_without_kill() (no kill, e.g. a Maul hit or miss).
##
## Shared subclass helpers: `_slot`/`_has_slot`/`_entry` from setup params,
## _entry_start_for() (off-screen entry start), _aim_from() (aim at the player),
## _can_fire() (missing-spawner guard) and _tuning_key() ("<_tuning_section()>.<field>").
##
## Virtual hooks (Story 7.3, the Flagship and its parts): _tuning_section()
## (where the hp, tier and hitbox_ratio live; default "enemies.<type_id>"),
## _max_hp() (the hp set in _ready; default the section's hp), _hitbox_shape()
## (default a circle of sprite_px / 2 * hitbox_ratio) and is_targetable()
## (whether homing shots and allies may pick it; default true). Story 7.5 adds
## _death_feedback() (the impact a kill plays; default the tier's).

signal resolved

const ENTRY_TOP: StringName = &"top"
const ENTRY_SIDES: StringName = &"sides"

## Size of the enemy's sprite in px; the hitbox circle is hitbox_ratio of it.
@export var sprite_px: float = 64.0

var type_id: StringName
## Set by Spawner before add_child; shooters request projectiles and every
## enemy requests its death drops (energy orbs) through it.
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
	hp = _max_hp()
	tier = ImpactTier.from_name(str(Config.section(_tuning_section()).get("tier", "")))
	var hitbox: CollisionShape2D = get_node_or_null(^"Hitbox") as CollisionShape2D
	if hitbox != null:
		hitbox.shape = _hitbox_shape()
	else:
		Log.error("combat", "enemy '%s' has no Hitbox" % type_id)
	add_to_group(Groups.ENEMIES)


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


## Whether homing shots (micro-missiles) and the ally may pick this enemy as a
## target. True for every regular enemy; the Flagship hull and an invulnerable
## core say no.
func is_targetable() -> bool:
	return true


func _die() -> void:
	if _dead:
		return
	_dead = true
	_death_feedback()
	Events.enemy_killed.emit(type_id, global_position, _last_hit_by_ally)
	_drop_loot()
	resolved.emit()
	queue_free()


## The feedback a kill plays (Story 7.5 hook): the tier's impact at the enemy.
## The Flagship core overrides it to play nothing (the Flagship's death chain,
## Feedback.boss_death, is the feedback).
func _death_feedback() -> void:
	Feedback.impact(tier, global_position)


## The no-kill exit (decision F18, Story 6.2): the enemy leaves the wave
## without being killed (a Maul that hit the convoy, missed, or had no convoy).
## It counts as resolved for the WaveDirector but is never a kill: no
## Events.enemy_killed and no loot roll. `play_feedback` plays the tier's impact
## (a Maul self-destructing on the convoy); a miss plays nothing. Once only:
## ignored when already dead, like _die().
func _resolve_without_kill(play_feedback: bool) -> void:
	if _dead:
		return
	_dead = true
	if play_feedback:
		Feedback.impact(tier, global_position)
	resolved.emit()
	queue_free()


## Rolls tuning.drops.<type_id> and asks the spawner for the orbs (deferred).
## Without a spawner nothing drops.
func _drop_loot() -> void:
	if spawner == null or not is_instance_valid(spawner):
		return
	Loot.drop(spawner, String(type_id), global_position)


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
	var player: Node2D = get_tree().get_first_node_in_group(Groups.PLAYER) as Node2D
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


## The tuning section holding this enemy's hp, tier and hitbox_ratio:
## "enemies.<type_id>" (the Flagship and its parts override it).
func _tuning_section() -> String:
	return "enemies.%s" % type_id


## Config key for this enemy's tuning `field`: "<_tuning_section()>.<field>".
func _tuning_key(field: String) -> String:
	return "%s.%s" % [_tuning_section(), field]


## The hp set in _ready: the section's `hp`.
func _max_hp() -> int:
	return Config.int_(_tuning_key("hp"))


## The Hitbox shape built in _ready: a circle of sprite_px / 2 * hitbox_ratio.
func _hitbox_shape() -> Shape2D:
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = sprite_px / 2.0 * Config.num(_tuning_key("hitbox_ratio"))
	return circle
