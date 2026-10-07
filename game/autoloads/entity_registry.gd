extends Node
## Preloaded entity scenes, looked up by type id. Only Spawner instantiates them.

const ENEMIES: Dictionary[StringName, PackedScene] = {
	&"wasp": preload("res://entities/enemies/wasp/wasp.tscn"),
}
const PROJECTILES: Dictionary[StringName, PackedScene] = {
	&"laser_bolt": preload("res://entities/projectiles/laser_bolt.tscn"),
	&"missile": preload("res://entities/projectiles/missile.tscn"),
}
## One scene for every asteroid size; the size is set through setup().
const ASTEROID: PackedScene = preload("res://entities/asteroids/asteroid.tscn")
