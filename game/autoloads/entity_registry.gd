extends Node
## Preloaded entity scenes, looked up by type id. Only Spawner instantiates them.

const ENEMIES: Dictionary[StringName, PackedScene] = {
	&"wasp": preload("res://entities/enemies/wasp/wasp.tscn"),
	&"lancer": preload("res://entities/enemies/lancer/lancer.tscn"),
	&"needle": preload("res://entities/enemies/needle/needle.tscn"),
	&"bastion": preload("res://entities/enemies/bastion/bastion.tscn"),
	&"hunter_wasp": preload("res://entities/enemies/hunter_wasp/hunter_wasp.tscn"),
}
## Enemy type id -> the flags.json flag that gates its wave spawns. A type is
## always a known id (levels validate with it); the WaveDirector skips its
## spawn entries, uncounted, while the flag is false.
const ENEMY_FLAGS: Dictionary[StringName, String] = {
	&"hunter_wasp": "hunter_wasp",
}
const PROJECTILES: Dictionary[StringName, PackedScene] = {
	&"laser_bolt": preload("res://entities/projectiles/laser_bolt.tscn"),
	&"missile": preload("res://entities/projectiles/missile.tscn"),
	&"enemy_bullet": preload("res://entities/projectiles/enemy_bullet.tscn"),
	&"needle_bolt": preload("res://entities/projectiles/needle_bolt.tscn"),
}
## One scene for every asteroid size; the size is set through setup().
const ASTEROID: PackedScene = preload("res://entities/asteroids/asteroid.tscn")
## One explosion scene for every impact tier; scale and extras come through setup().
const EXPLOSION: PackedScene = preload("res://entities/effects/explosion.tscn")
## The gold energy orb dropped by Loot (Story 3.3).
const ENERGY_ORB: PackedScene = preload("res://entities/pickups/energy_orb.tscn")


## The known enemy type ids (Config validates level files against them).
func enemy_types() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(ENEMIES.keys())
	return out
