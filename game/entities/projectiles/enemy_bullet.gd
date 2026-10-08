class_name EnemyBullet
extends Projectile
## Shared enemy bullet (Lancer now; Bastion and the Flagship later). A round
## `enemy` magenta orb with a white core, on layer enemy_shots, masking player,
## asteroids and convoy (GDD NFR6).
##
## Its capsule hitbox is turned in _ready so the long axis follows `velocity`
## (anti-tunnelling: height >= max speed / 60). Velocity is fixed at spawn;
## changing it later leaves the capsule misaligned. It damages only targets with
## apply_damage that are not asteroids (only player shots chip asteroids), then
## frees itself. It plays no impact feedback of its own; the player-hit
## feedback comes from Player.apply_damage.


func _ready() -> void:
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


func _on_impact(_area: Area2D) -> void:
	pass
