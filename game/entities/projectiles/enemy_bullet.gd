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
## frees itself. No impact feedback yet (player-hit feedback is Epic 3).


func _ready() -> void:
	var hitbox: CollisionShape2D = get_node_or_null(^"Hitbox") as CollisionShape2D
	if hitbox != null and not velocity.is_zero_approx():
		# The capsule's long axis is local +y; turn it onto the travel direction.
		hitbox.rotation = velocity.angle() - PI / 2.0
	super._ready()


func _can_damage(area: Area2D) -> bool:
	return (area.collision_layer & CollisionLayers.ASTEROIDS) == 0


func _on_impact(_area: Area2D) -> void:
	pass
