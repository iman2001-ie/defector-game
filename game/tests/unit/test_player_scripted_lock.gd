extends "res://tests/fixtures/player_test_base.gd"
## Player scripted lock (Tarek's fall, Epic 7 playtest D):
## set_scripted_lock(true) holds the ship where it is whatever the mouse does,
## stops the laser and the abilities and makes the ship invulnerable, while the
## i-frame and shield timers keep ticking; set_scripted_lock(false) warps the
## cursor onto the ship (only in the CONFINED_HIDDEN gameplay mode, arming the
## DW-20 one-tick guard) and re-checks remembered hazard contacts. A repeat of
## the current state changes nothing. Driven through _physics_process with the
## physics tick off; the mouse is moved by pushing motion events.

const HIDDEN: Input.MouseMode = Input.MOUSE_MODE_CONFINED_HIDDEN
const VISIBLE: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
const START: Vector2 = Vector2(800, 900)
const AWAY: Vector2 = Vector2(1500, 600)

var _warps: Array[Vector2] = []
var _mouse_before: Vector2 = Vector2.ZERO
var _world: Node2D
var _projectiles: Node2D


func before_each() -> void:
	_begin()
	_warps.clear()
	_mouse_before = get_viewport().get_mouse_position()
	_player = _make_player(START, _record_warp)


func after_each() -> void:
	for action: StringName in [&"fire_laser", &"ability_shield", &"ability_barrage"]:
		Input.action_release(action)
	_move_mouse(_mouse_before)
	PauseArbiter.set_gameplay_mouse_mode(VISIBLE)
	_world = null
	_projectiles = null
	super()


func _record_warp(p: Vector2) -> void:
	_warps.append(p)


func _move_mouse(at: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion, true)


## A Spawner with the containers, handed to the player (so the laser fires).
func _arm() -> void:
	_world = Node2D.new()
	for container: String in ["Projectiles", "Enemies", "Asteroids"]:
		var node: Node2D = Node2D.new()
		node.name = container
		_world.add_child(node)
	_projectiles = _world.get_node("Projectiles") as Node2D
	add_child_autofree(_world)
	var spawner: Spawner = Spawner.new()
	spawner.world = _world
	add_child_autofree(spawner)
	_player.set_spawner(spawner)


func test_starts_unlocked() -> void:
	assert_false(_player.is_scripted_locked())
	assert_false(_player.is_invulnerable())


func test_lock_holds_the_ship_against_the_mouse() -> void:
	_move_mouse(AWAY)
	_player.set_scripted_lock(true)
	assert_true(_player.is_scripted_locked())
	watch_signals(Events)
	for i: int in 10:
		_player._physics_process(DT)
	assert_eq(_player.global_position, START, "held in place")
	assert_signal_not_emitted(Events, "player_moved", "the ship did not move")
	_player.set_scripted_lock(false)
	_player._physics_process(DT)
	# Headless, the viewport may not take the pushed motion: compare with
	# wherever it reads the mouse.
	var target: Vector2 = _player.clamp_to_bounds(get_viewport().get_mouse_position())
	assert_ne(target, START, "fixture: the mouse is away from the ship")
	assert_eq(_player.global_position, target, "follows the mouse again once released")


func test_no_laser_while_locked() -> void:
	_arm()
	Input.action_press(&"fire_laser")
	_player.set_scripted_lock(true)
	for i: int in 30:
		_player._physics_process(DT)
	assert_eq(_projectiles.get_child_count(), 0, "no bolt while locked")
	_player.set_scripted_lock(false)
	_player._physics_process(DT)
	assert_eq(_projectiles.get_child_count(), 1, "fires again once released")


func test_no_shield_while_locked() -> void:
	GameState.energy = 100
	_player.set_scripted_lock(true)
	Input.action_press(&"ability_shield")
	_player._physics_process(DT)
	assert_false(_player.is_shielded(), "no shield while locked")
	assert_eq(GameState.energy, 100, "nothing spent")
	_player.set_scripted_lock(false)
	# Input's "just pressed" depends on the engine frame, which can tick under a
	# loaded full-suite run; once released, the ability itself works again.
	assert_true(_player.try_shield(), "the shield works again once released")
	assert_true(_player.is_shielded())
	assert_eq(GameState.energy, 50)


func test_no_barrage_while_locked() -> void:
	GameState.energy = 100
	_player.set_scripted_lock(true)
	Input.action_press(&"ability_barrage")
	_player._physics_process(DT)
	assert_false(_player.is_barraging(), "no barrage while locked")
	assert_eq(GameState.energy, 100, "nothing spent")


func test_invulnerable_while_locked() -> void:
	var hearts: int = _player.hearts
	_player.set_scripted_lock(true)
	assert_true(_player.is_invulnerable(), "invulnerable")
	_player.apply_damage(1, null)
	_player.apply_damage(99, null)
	assert_eq(_player.hearts, hearts, "no heart lost")
	assert_false(_player.is_dead())
	_player.set_scripted_lock(false)
	assert_false(_player.is_invulnerable(), "vulnerable again once released")
	_player.apply_damage(1, null)
	assert_eq(_player.hearts, hearts - 1, "a hit costs again")


func test_iframes_keep_ticking_while_locked() -> void:
	_player.apply_damage(1, null)
	_player.set_scripted_lock(true)
	var t: float = 0.0
	while t < Config.num("player.iframes_s") + DT:
		_player._physics_process(DT)
		t += DT
	_player.set_scripted_lock(false)
	assert_false(_player.is_invulnerable(), "the i-frames ran out during the lock")


func test_contact_while_locked_hits_on_release() -> void:
	var bastion: Bastion = _bastion()
	var hearts: int = _player.hearts
	_player.set_scripted_lock(true)
	_player.on_contact(bastion)
	assert_eq(_player.hearts, hearts, "no damage while locked")
	_player.set_scripted_lock(false)
	assert_lt(_player.hearts, hearts, "the remembered contact hits once released")


func test_release_warps_the_cursor_and_arms_the_guard() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	_player.set_scripted_lock(true)
	assert_eq(_warps, [] as Array[Vector2], "no warp on lock")
	_player.set_scripted_lock(false)
	assert_eq(_warps, [START] as Array[Vector2], "one warp onto the ship")
	# DW-20: the first tick may still read the pre-warp mouse; the guard holds.
	_player.step_lock(AWAY)
	assert_eq(_player.global_position, START, "the stale mouse is ignored for one tick")
	_player.step_lock(AWAY)
	assert_eq(_player.global_position, _player.clamp_to_bounds(AWAY), "then it moves normally")
	assert_eq(_warps, [START] as Array[Vector2], "no further warp")


func test_release_in_visible_mode_does_not_warp() -> void:
	PauseArbiter.set_gameplay_mouse_mode(VISIBLE)
	_player.set_scripted_lock(true)
	_player.set_scripted_lock(false)
	assert_eq(_warps, [] as Array[Vector2])
	_player.step_lock(AWAY)
	assert_eq(_player.global_position, _player.clamp_to_bounds(AWAY), "no guard without a warp")


func test_repeat_calls_change_nothing() -> void:
	PauseArbiter.set_gameplay_mouse_mode(HIDDEN)
	_player.set_scripted_lock(false)
	assert_eq(_warps, [] as Array[Vector2], "releasing an unlocked ship does nothing")
	_player.set_scripted_lock(true)
	_player.set_scripted_lock(true)
	assert_eq(_logged("[INFO][scene] Player: controls locked").size(), 1, "one lock line")
	_player.set_scripted_lock(false)
	_player.set_scripted_lock(false)
	assert_eq(_warps, [START] as Array[Vector2], "one warp")
	assert_eq(_logged("[INFO][scene] Player: controls released").size(), 1, "one release line")
	assert_false(_player.is_scripted_locked())
