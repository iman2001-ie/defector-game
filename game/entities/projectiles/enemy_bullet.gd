class_name EnemyBullet
extends Projectile
## Shared enemy bullet (Lancer, Bastion, the Needle via NeedleBolt; the Flagship
## later). A round `enemy` magenta orb with a white core, on layer enemy_shots,
## masking player, asteroids and convoy (GDD NFR6).
##
## Its capsule hitbox is turned in _ready so the long axis follows `velocity`
## (anti-tunnelling: height >= max speed / 60). Velocity is fixed at spawn;
## changing it later leaves the capsule misaligned. It damages only targets with
## apply_damage that are not asteroids (only player shots chip asteroids), then
## frees itself. It plays no impact feedback of its own; the player-hit
## feedback comes from Player.apply_damage.
##
## Convoy damage (Story 6.3, GDD #23): a convoy ship it reaches takes
## damage.convoy_aimed when `targets_convoy` is set (a Lancer aiming at the
## convoy), else damage.convoy_stray (Bastion shots, Needle bolts, player-aimed
## Lancer shots). Every other target still takes `damage`, so a convoy-aimed
## shot that hits the player costs the usual hearts.

## True when the shooter aimed this shot at the convoy (setup key
## `targets_convoy`, default false).
var targets_convoy: bool = false

var _convoy_aimed: int = 0
var _convoy_stray: int = 0


## Projectile.setup plus the optional `targets_convoy` key.
func setup(params: Dictionary) -> void:
	super(params)
	targets_convoy = bool(params.get("targets_convoy", targets_convoy))


func _ready() -> void:
	_convoy_aimed = Config.int_("damage.convoy_aimed")
	_convoy_stray = Config.int_("damage.convoy_stray")
	# The capsule's long axis is local +y; turn it onto the travel direction.
	_align_to_velocity(get_node_or_null(^"Hitbox") as Node2D)
	super._ready()


## Turns `node` so its local +y axis points along `velocity`. Skips a null node
## or a zero velocity.
func _align_to_velocity(node: Node2D) -> void:
	if node == null or velocity.is_zero_approx():
		return
	node.rotation = velocity.angle() - PI / 2.0


func _can_damage(area: Area2D) -> bool:
	return (area.collision_layer & CollisionLayers.ASTEROIDS) == 0


## The convoy amounts on a convoy area (aimed or stray), else `damage`.
func _damage_for(area: Area2D) -> int:
	if is_convoy(area):
		return _convoy_aimed if targets_convoy else _convoy_stray
	return damage


func _on_impact(_area: Area2D) -> void:
	pass
