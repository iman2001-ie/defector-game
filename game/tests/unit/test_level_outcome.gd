extends GutTest
## A level ends exactly once (DW-54, decision #39): the first outcome wins and a
## clear makes the ship safe. A real Player next to a WaveDirector + Spawner
## fixture (as in test_wave_director), with a death and a clear in both orders.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")
const SRC: String = "res://data/levels/level_test.json"
const GAP_S: float = 0.05
const LEVEL_ID: int = 5

var _world: Node2D
var _director: WaveDirector
var _player: Player


func before_each() -> void:
	(Config.tuning["waves"] as Dictionary)["gap_s"] = GAP_S
	GameState.energy = 0
	watch_signals(Events)
	var root: Node = Node.new()
	_world = Node2D.new()
	_world.name = "World"
	for container: String in ["Asteroids", "Enemies", "Projectiles"]:
		var node: Node2D = Node2D.new()
		node.name = container
		_world.add_child(node)
	var spawner: Spawner = Spawner.new()
	spawner.world = _world
	_director = WaveDirector.new()
	_director.spawner = spawner
	_director.rng.seed = 7
	root.add_child(_world)
	root.add_child(spawner)
	root.add_child(_director)
	add_child_autofree(root)
	_player = PLAYER_SCENE.instantiate() as Player
	_player.warp_mouse = _ignore_warp
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.global_position = Vector2(200, 900)


func after_each() -> void:
	Config.load_data()
	GameState.energy = 0
	Feedback.reset()
	PauseArbiter.clear()
	_director = null
	_player = null


func _ignore_warp(_p: Vector2) -> void:
	pass


## Kills every live (not dying) enemy in the fixture's Enemies container.
func _kill_all() -> void:
	for child: Node in _world.get_node("Enemies").get_children():
		var enemy: Enemy = child as Enemy
		if enemy != null and not enemy.is_dead() and not enemy.is_queued_for_deletion():
			enemy.apply_damage(enemy.hp, null)


func _start() -> void:
	_director.start_level({"id": float(LEVEL_ID), "waves": [{"spawns": [{"type": "wasp", "count": 1.0}]}]}, SRC)


func test_death_then_clear_never_clears() -> void:
	_start()
	_player.hearts = 1
	_player.apply_damage(1, null)
	Feedback.reset()  # Drop the death hit-stop so the gap wait runs in real time.
	assert_true(_player.is_dead())
	_kill_all()
	await wait_seconds(GAP_S + 0.1)
	assert_signal_emit_count(Events, "level_failed", 1, "level_failed once")
	assert_signal_not_emitted(Events, "level_cleared")
	assert_signal_not_emitted(Events, "wave_cleared")
	assert_false(_director.is_level_cleared())
	assert_false(_player.is_safe(), "a dead ship never turns safe")


func test_clear_then_death_never_fails() -> void:
	_start()
	_kill_all()
	await wait_seconds(GAP_S + 0.1)
	assert_signal_emit_count(Events, "level_cleared", 1)
	assert_true(_player.is_safe())
	var hearts: int = _player.hearts
	_player.apply_damage(hearts + 5, null)
	assert_false(_player.is_dead(), "player alive")
	assert_eq(_player.hearts, hearts, "hearts unchanged")
	assert_signal_not_emitted(Events, "player_hit")
	assert_signal_not_emitted(Events, "player_died")
	assert_signal_not_emitted(Events, "level_failed")
	await wait_seconds(GAP_S + 0.1)
	assert_signal_emit_count(Events, "level_cleared", 1, "level_cleared once")
	assert_true(_director.is_level_cleared())
