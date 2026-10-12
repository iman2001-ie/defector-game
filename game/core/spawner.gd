class_name Spawner
extends Node
## The only creator of gameplay entities. Looks the scene up in EntityRegistry,
## instantiates it, calls setup(params), then adds it to the matching World container.

## The level/sandbox World node that holds the entity containers.
@export var world: Node2D

var _projectiles: Node2D
var _enemies: Node2D
var _asteroids: Node2D
var _effects: Node2D
var _pickups: Node2D
var _allies: Node2D


func _ready() -> void:
	if world == null:
		Log.error("spawn", "Spawner '%s' has no world set" % name)
		return
	_projectiles = _container(^"Projectiles")
	_enemies = _container(^"Enemies")
	_asteroids = _container(^"Asteroids")
	# Effects is optional (test worlds omit it); only a Spawner with one feeds Feedback.
	_effects = world.get_node_or_null(^"Effects") as Node2D
	if _effects != null:
		Feedback.register_spawner(self)
	else:
		Log.debug("spawn", "World '%s' has no Effects container; explosions disabled" % world.name)
	# Pickups is optional too (test worlds omit it); without it no orbs drop.
	_pickups = world.get_node_or_null(^"Pickups") as Node2D
	if _pickups == null:
		Log.debug("spawn", "World '%s' has no Pickups container; energy orbs disabled" % world.name)
	# Allies is optional too (test worlds and the sandbox omit it); without it no convoy or ally spawns.
	_allies = world.get_node_or_null(^"Allies") as Node2D
	if _allies == null:
		Log.debug("spawn", "World '%s' has no Allies container; convoy and ally disabled" % world.name)


func _exit_tree() -> void:
	Feedback.unregister_spawner(self)


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


## Returns the spawned enemy, or null for an unknown id or a missing container.
## Callers must treat null as "not counted".
func spawn_enemy(type_id: StringName, params: Dictionary) -> Enemy:
	var scene: PackedScene = EntityRegistry.ENEMIES.get(type_id) as PackedScene
	if scene == null:
		Log.error("spawn", "unknown enemy type '%s'" % type_id)
		return null
	if _enemies == null:
		return null
	var node: Node = scene.instantiate()
	var enemy: Enemy = node as Enemy
	if enemy == null:
		Log.error("spawn", "enemy type '%s' is not an Enemy" % type_id)
		node.queue_free()
		return null
	enemy.spawner = self
	enemy.setup(params)
	_enemies.add_child(enemy)
	return enemy


## Returns the spawned boss (Story 7.3), or null for an unknown id or a missing
## Enemies container. Like spawn_enemy it hands the boss this Spawner (the
## Flagship passes it on to its parts) and parents it to World/Enemies.
## Callers must treat null as "not counted".
func spawn_boss(type_id: StringName, params: Dictionary) -> Flagship:
	var scene: PackedScene = EntityRegistry.BOSSES.get(type_id) as PackedScene
	if scene == null:
		Log.error("spawn", "unknown boss type '%s'" % type_id)
		return null
	if _enemies == null:
		return null
	var node: Node = scene.instantiate()
	var boss: Flagship = node as Flagship
	if boss == null:
		Log.error("spawn", "boss type '%s' is not a Flagship" % type_id)
		node.queue_free()
		return null
	boss.spawner = self
	boss.setup(params)
	_enemies.add_child(boss)
	return boss


## Returns the spawned asteroid, or null for an unknown size or a missing container.
## params.size must be one of Asteroid.SIZES.
func spawn_asteroid(params: Dictionary) -> Asteroid:
	var size: StringName = StringName(str(params.get("size", "")))
	if not Asteroid.SIZES.has(size):
		Log.error("spawn", "unknown asteroid size '%s'" % size)
		return null
	if _asteroids == null:
		return null
	var node: Node = EntityRegistry.ASTEROID.instantiate()
	var asteroid: Asteroid = node as Asteroid
	if asteroid == null:
		Log.error("spawn", "asteroid scene is not an Asteroid")
		node.queue_free()
		return null
	asteroid.spawner = self
	asteroid.setup(params)
	_asteroids.add_child(asteroid)
	return asteroid


## Returns the spawned explosion, or null without an Effects container.
## params: position, scale, extras (see Explosion.setup).
func spawn_explosion(params: Dictionary) -> Explosion:
	if _effects == null:
		return null
	var node: Node = EntityRegistry.EXPLOSION.instantiate()
	var explosion: Explosion = node as Explosion
	if explosion == null:
		Log.error("spawn", "explosion scene is not an Explosion")
		node.queue_free()
		return null
	explosion.setup(params)
	_effects.add_child(explosion)
	return explosion


## Returns the spawned energy orb, or null without a Pickups container.
## params: position (see EnergyOrb.setup). Loot calls this deferred.
func spawn_orb(params: Dictionary) -> EnergyOrb:
	if _pickups == null:
		return null
	var node: Node = EntityRegistry.ENERGY_ORB.instantiate()
	var orb: EnergyOrb = node as EnergyOrb
	if orb == null:
		Log.error("spawn", "energy orb scene is not an EnergyOrb")
		node.queue_free()
		return null
	orb.setup(params)
	_pickups.add_child(orb)
	return orb


## Returns the spawned convoy (Story 6.1), or null without an Allies container.
## params: none yet (see Convoy.setup).
func spawn_convoy(params: Dictionary) -> Convoy:
	if _allies == null:
		Log.debug("spawn", "No Allies container; convoy not spawned")
		return null
	var node: Node = EntityRegistry.CONVOY.instantiate()
	var convoy: Convoy = node as Convoy
	if convoy == null:
		Log.error("spawn", "convoy scene is not a Convoy")
		node.queue_free()
		return null
	convoy.setup(params)
	_allies.add_child(convoy)
	return convoy


## Returns the spawned ally ship (Story 6.4), or null without an Allies container.
## params: ally ("tarek" | "ryn", see AllyShip.setup). The ally gets this
## Spawner, which creates its shots.
func spawn_ally(params: Dictionary) -> AllyShip:
	if _allies == null:
		Log.debug("spawn", "No Allies container; ally not spawned")
		return null
	var node: Node = EntityRegistry.ALLY_SHIP.instantiate()
	var ally: AllyShip = node as AllyShip
	if ally == null:
		Log.error("spawn", "ally scene is not an AllyShip")
		node.queue_free()
		return null
	ally.spawner = self
	ally.setup(params)
	_allies.add_child(ally)
	return ally


func _container(path: NodePath) -> Node2D:
	var node: Node2D = world.get_node_or_null(path) as Node2D
	if node == null:
		Log.error("spawn", "World '%s' has no %s container" % [world.name, path])
	return node
