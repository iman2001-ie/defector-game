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
## Enemy types that don't hold a formation row: the Needle anchors at its own y,
## and the Hunter Wasp never holds its slot (a sides entry only starts at the
## slot's y, so it may share a row with the next entry). The WaveDirector
## doesn't advance its formation row for them.
const ROWLESS_TYPES: Array[StringName] = [&"needle", &"hunter_wasp"]
const PROJECTILES: Dictionary[StringName, PackedScene] = {
	&"laser_bolt": preload("res://entities/projectiles/laser_bolt.tscn"),
	&"missile": preload("res://entities/projectiles/missile.tscn"),
	&"micro_missile": preload("res://entities/projectiles/micro_missile.tscn"),
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


## The ENEMY_FLAGS gate map (type id -> flags.json flag), for Config's runtime
## lookup (LevelValidator counts a gated type 0 while its flag is off).
func enemy_flags() -> Dictionary:
	return ENEMY_FLAGS
