class_name AllyBolt
extends Projectile
## An ally's shot (Story 6.4, FR34): one coalition bolt on `player_shots` with
## `from_ally` true, fired by an AllyShip through Spawner.spawn_projectile
## (&"ally_bolt", {position, velocity, damage, from_ally}).
##
## The ally aims at an enemy in any direction, so _ready rotates the bolt to its
## velocity (the scene's bolt and capsule point up at rotation 0); the capsule
## then lies along the travel path (anti-tunnelling: its height must be at least
## allies.shot_speed_px_s / 60). The look is the laser's single bolt: an HDR core
## (weapons.laser.glow_energy) over an additive Halo (weapons.laser.halo_energy).
## The base Projectile handles the rest: one damage instance, blocked with no
## damage by the convoy (_can_damage), freed off-screen.


func _ready() -> void:
	if velocity.length_squared() > 0.0:
		rotation = velocity.angle() + PI / 2.0
	var e: float = Config.num("weapons.laser.glow_energy")
	var h: float = Config.num("weapons.laser.halo_energy")
	var bolt: Sprite2D = get_node_or_null(^"Bolt") as Sprite2D
	if bolt != null:
		bolt.self_modulate = Color(e, e, e, 1.0)
		var halo: Sprite2D = bolt.get_node_or_null(^"Halo") as Sprite2D
		if halo != null:
			halo.self_modulate = Color(h, h, h, 1.0)
	super._ready()
