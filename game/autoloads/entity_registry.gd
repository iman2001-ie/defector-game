extends Node
## Preloaded entity scenes, looked up by type id. Only Spawner instantiates them.

const PROJECTILES: Dictionary[StringName, PackedScene] = {
	&"laser_bolt": preload("res://entities/projectiles/laser_bolt.tscn"),
}
