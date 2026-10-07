class_name Spawner
extends Node
## The only creator of gameplay entities. Looks the scene up in EntityRegistry,
## instantiates it, calls setup(params), then adds it to the matching World container.

## The level/sandbox World node that holds the entity containers.
@export var world: Node2D

var _projectiles: Node2D


func _ready() -> void:
	if world == null:
		Log.error("spawn", "Spawner '%s' has no world set" % name)
		return
	_projectiles = world.get_node_or_null(^"Projectiles") as Node2D
	if _projectiles == null:
		Log.error("spawn", "World '%s' has no Projectiles container" % world.name)


## Returns the spawned projectile, or null for an unknown id or a missing container.
func spawn_projectile(type_id: StringName, params: Dictionary) -> Projectile:
	var scene: PackedScene = EntityRegistry.PROJECTILES.get(type_id) as PackedScene
	if scene == null:
		Log.error("spawn", "unknown projectile type '%s'" % type_id)
		return null
	if _projectiles == null:
		return null
	var node: Node = scene.instantiate()
	var projectile: Projectile = node as Projectile
	if projectile == null:
		Log.error("spawn", "projectile type '%s' is not a Projectile" % type_id)
		node.queue_free()
		return null
	projectile.setup(params)
	_projectiles.add_child(projectile)
	return projectile
