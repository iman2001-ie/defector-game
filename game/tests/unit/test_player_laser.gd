extends GutTest
## Player laser: fire timing via step_fire, bolt params, muzzle flash, pause gating.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")
const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const DT: float = 1.0 / 60.0

var _player: Player
var _spawner: Spawner
var _projectiles: Node2D


func before_each() -> void:
	var world: Node2D = Node2D.new()
	_projectiles = Node2D.new()
	_projectiles.name = "Projectiles"
	world.add_child(_projectiles)
	for container: String in ["Enemies", "Asteroids"]:
		var node: Node2D = Node2D.new()
		node.name = container
		world.add_child(node)
	add_child_autofree(world)
	_spawner = Spawner.new()
	_spawner.world = world
	add_child_autofree(_spawner)
	_player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(_player)
	# Tests drive the ship explicitly; real input and mouse must not.
	_player.set_physics_process(false)
	_player.global_position = Vector2(960, 900)
	_player.set_spawner(_spawner)


func after_each() -> void:
	Feedback.reset()
	Input.action_release(&"fire_laser")
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_player = null
	_spawner = null
	_projectiles = null


func _ticks(held: bool, n: int) -> void:
	for i: int in n:
		_player.step_fire(held, DT)


func _flash() -> Node2D:
	return _player.get_node("Muzzle/MuzzleFlash") as Node2D


func test_rate_ten_per_second() -> void:
	_player.step_fire(true, DT)
	assert_eq(_projectiles.get_child_count(), 1, "first bolt on tick 1")
	_ticks(true, 59)
	assert_eq(_projectiles.get_child_count(), 10, "60 ticks -> 10 bolts")


func test_rate_holds_without_drift() -> void:
	_ticks(true, 600)
	assert_eq(_projectiles.get_child_count(), 100, "600 ticks -> 100 bolts")


func test_tap_respects_cooldown() -> void:
	_ticks(true, 1)
	_ticks(false, 2)
	_ticks(true, 1)
	assert_eq(_projectiles.get_child_count(), 1)


func test_repress_after_interval_fires_at_once() -> void:
	_ticks(true, 1)
	_ticks(false, 6)
	_ticks(true, 1)
	assert_eq(_projectiles.get_child_count(), 2)


func test_long_release_does_not_bank_shots() -> void:
	_ticks(false, 60)
	_ticks(true, 6)
	assert_eq(_projectiles.get_child_count(), 1, "no burst after a long release")


func test_not_held_fires_nothing() -> void:
	_ticks(false, 60)
	assert_eq(_projectiles.get_child_count(), 0)
	assert_false(_flash().visible, "flash hidden")


func test_no_spawner_no_bolt_no_error() -> void:
	var lone: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(lone)
	lone.set_physics_process(false)
	for i: int in 60:
		lone.step_fire(true, DT)
	assert_eq(_projectiles.get_child_count(), 0)
	assert_false((lone.get_node("Muzzle/MuzzleFlash") as Node2D).visible)


func test_non_positive_rate_warns_and_disables_laser() -> void:
	var laser_tuning: Dictionary = Config.tuning["weapons"]["laser"]
	var original: Variant = laser_tuning["rate_per_s"]
	laser_tuning["rate_per_s"] = 0
	var fresh: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(fresh)
	laser_tuning["rate_per_s"] = original
	fresh.set_physics_process(false)
	fresh.set_spawner(_spawner)
	assert_push_warning("rate_per_s")
	for i: int in 60:
		fresh.step_fire(true, DT)
	assert_eq(_projectiles.get_child_count(), 0, "laser disabled")


func test_flash_sits_on_muzzle() -> void:
	assert_eq(_flash().get_parent(), _player.get_node("Muzzle"))
	assert_eq(_flash().position, Vector2.ZERO)


func test_bolt_params_from_muzzle_and_tuning() -> void:
	_player.step_fire(true, DT)
	assert_eq(_projectiles.get_child_count(), 1)
	if _projectiles.get_child_count() != 1:
		return
	var bolt: Projectile = _projectiles.get_child(0) as Projectile
	var muzzle: Marker2D = _player.get_node("Muzzle") as Marker2D
	assert_eq(bolt.global_position, muzzle.global_position)
	assert_eq(bolt.velocity, Vector2(0, -Config.num("weapons.laser.speed_px_s")))
	assert_eq(bolt.velocity, Vector2(0, -1800))
	assert_eq(bolt.damage, Config.int_("weapons.laser.damage"))
	assert_true(bolt is LaserBolt)


func test_muzzle_flash_every_shot_hidden_after_half_interval() -> void:
	assert_false(_flash().visible, "hidden at start")
	_player.step_fire(true, DT)
	assert_true(_flash().visible, "shown on shot")
	_ticks(false, 2)
	assert_true(_flash().visible, "still shown before half the interval")
	_ticks(false, 1)
	assert_false(_flash().visible, "hidden after half the 0.1 s interval")
	_ticks(false, 3)
	_player.step_fire(true, DT)
	assert_true(_flash().visible, "shown again on the next shot")


func test_flash_cycles_while_held() -> void:
	_ticks(true, 1)
	assert_true(_flash().visible, "tick 1: shot")
	_ticks(true, 3)
	assert_false(_flash().visible, "tick 4: hidden after half the interval")
	_ticks(true, 3)
	assert_eq(_projectiles.get_child_count(), 2)
	assert_true(_flash().visible, "tick 7: next shot shows the flash again")


func test_bolt_plays_laser_zap_with_jitter() -> void:
	var jitter: float = Config.num("weapons.laser.sfx_pitch_jitter")
	var pitches: Dictionary[float, bool] = {}
	for shot: int in 10:
		_player.step_fire(true, DT)
		var sfx: AudioStreamPlayer = Audio.newest_player()
		assert_not_null(sfx)
		if sfx == null:
			return
		assert_eq(sfx.stream, Audio.SFX[&"laser_zap"])
		assert_between(sfx.pitch_scale, 1.0 - jitter, 1.0 + jitter, "pitch within jitter")
		pitches[sfx.pitch_scale] = true
		# Let the cooldown elapse (6 ticks per bolt at 10/s) before the next shot.
		_ticks(true, 5)
	assert_eq(_projectiles.get_child_count(), 10, "one bolt per shot")
	assert_gt(pitches.size(), 1, "pitch is jittered")


func test_laser_zap_jitter_follows_tuning() -> void:
	var laser_tuning: Dictionary = Config.tuning["weapons"]["laser"]
	var original: Variant = laser_tuning["sfx_pitch_jitter"]
	laser_tuning["sfx_pitch_jitter"] = 0.0
	var fresh: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(fresh)
	laser_tuning["sfx_pitch_jitter"] = original
	fresh.set_physics_process(false)
	fresh.set_spawner(_spawner)
	for shot: int in 5:
		fresh.step_fire(true, DT)
		var sfx: AudioStreamPlayer = Audio.newest_player()
		assert_not_null(sfx)
		if sfx == null:
			return
		assert_eq(sfx.pitch_scale, 1.0, "zero tuning jitter gives an unjittered zap")
		for tick: int in 5:
			fresh.step_fire(true, DT)


func test_no_bolt_no_zap() -> void:
	Audio.play_sfx(&"explosion_small")
	var before: AudioStreamPlayer = Audio.newest_player()
	var lone: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(lone)
	lone.set_physics_process(false)
	lone.step_fire(true, DT)
	assert_eq(Audio.newest_player(), before, "no sound without a spawned bolt")


func test_paused_tree_does_not_fire() -> void:
	var sandbox: Node2D = SANDBOX_SCENE.instantiate() as Node2D
	add_child_autofree(sandbox)
	var projectiles: Node = sandbox.get_node("World/Projectiles")
	PauseArbiter.push(&"menu")
	Input.action_press(&"fire_laser")
	await wait_physics_frames(10)
	assert_eq(projectiles.get_child_count(), 0, "no bolts while paused")
	PauseArbiter.pop(&"menu")
	await wait_physics_frames(10)
	assert_gt(projectiles.get_child_count(), 0, "fires once unpaused")


# --- Story 5.8: player_action ----------------------------------------------------

func test_a_bolt_emits_player_action_laser() -> void:
	watch_signals(Events)
	_ticks(false, 3)
	assert_signal_not_emitted(Events, "player_action", "not held: no bolt, no action")
	_ticks(true, 1)
	assert_eq(_projectiles.get_child_count(), 1)
	assert_signal_emit_count(Events, "player_action", 1)
	assert_signal_emitted_with_parameters(Events, "player_action", [&"laser"])


func test_no_spawner_no_player_action() -> void:
	_player.set_spawner(null)
	watch_signals(Events)
	_ticks(true, 10)
	assert_signal_not_emitted(Events, "player_action")
