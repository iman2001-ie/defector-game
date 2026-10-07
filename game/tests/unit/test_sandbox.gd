extends GutTest
## Sandbox scene: World containers, Player and Reticle, gameplay mouse mode.

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const CONTAINERS: Array[String] = ["Asteroids", "Enemies", "Allies", "Pickups", "Projectiles", "Effects"]

var _sandbox: Node2D


func before_each() -> void:
	_sandbox = SANDBOX_SCENE.instantiate() as Node2D
	add_child_autofree(_sandbox)


func after_each() -> void:
	_sandbox = null
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func test_world_containers() -> void:
	var world: Node2D = _sandbox.get_node_or_null("World") as Node2D
	assert_not_null(world, "World is a Node2D")
	if world == null:
		return
	assert_eq(world.process_mode, Node.PROCESS_MODE_INHERIT, "World is pausable")
	for container: String in CONTAINERS:
		var node: Node = world.get_node_or_null(container)
		assert_true(node is Node2D, "World/%s is a Node2D" % container)
	assert_true(world.get_node_or_null("Player") is Player, "World/Player is a Player")
	assert_true(world.get_node_or_null("Reticle") is Sprite2D, "World/Reticle is a Sprite2D")
	assert_eq(world.get_child(world.get_child_count() - 1).name, &"Reticle", "Reticle draws last")


func test_player_starts_at_spawn_point() -> void:
	var player: Player = _sandbox.get_node("World/Player") as Player
	assert_eq(player.position, Vector2(960, 900))


func test_gameplay_mouse_mode_confined_hidden() -> void:
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_CONFINED_HIDDEN, "no reasons")
	PauseArbiter.push(&"menu")
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "with a reason")


func test_reticle_follows_mouse() -> void:
	var reticle: Sprite2D = _sandbox.get_node("World/Reticle") as Sprite2D
	reticle.global_position = Vector2(-500, -500)
	reticle._process(0.0)
	assert_eq(reticle.global_position, reticle.get_global_mouse_position())


func test_spawner_wired_to_world_and_player() -> void:
	var spawner: Spawner = _sandbox.get_node_or_null("Spawner") as Spawner
	assert_not_null(spawner, "Sandbox/Spawner is a Spawner")
	if spawner == null:
		return
	assert_eq(spawner.world, _sandbox.get_node("World"), "Spawner.world is World")
	var player: Player = _sandbox.get_node("World/Player") as Player
	player.step_fire(true, 1.0 / 60.0)
	assert_eq(_sandbox.get_node("World/Projectiles").get_child_count(), 1, "player fires through the sandbox Spawner")
