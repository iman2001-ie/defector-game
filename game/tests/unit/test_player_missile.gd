extends GutTest
## Player missile: aim direction, cooldown gating, cooldown ratio broadcast.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")
const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const DT: float = 1.0 / 60.0
const SHIP: Vector2 = Vector2(960, 900)
const FAR_TARGET: Vector2 = Vector2(960, 100)

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
	_player.global_position = SHIP
	_player.set_spawner(_spawner)
	watch_signals(Events)


func after_each() -> void:
	Feedback.reset()
	Input.action_release(&"fire_missile")
	Input.action_release(&"fire_laser")
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_player = null
	_spawner = null
	_projectiles = null


func _ticks(pressed: bool, n: int, target: Vector2 = FAR_TARGET) -> void:
	for i: int in n:
		_player.step_missile(pressed, target, DT)


func _missiles() -> Array[Missile]:
	var out: Array[Missile] = []
	for child: Node in _projectiles.get_children():
		if child is Missile:
			out.append(child as Missile)
	return out


func _fire_once_at(target: Vector2) -> Missile:
	_player.step_missile(true, target, DT)
	var missiles: Array[Missile] = _missiles()
	assert_eq(missiles.size(), 1, "one missile")
	return missiles[0] if missiles.size() == 1 else null


func test_aimed_shot() -> void:
	var missile: Missile = _fire_once_at(Vector2(1260, 500))
	if missile == null:
		return
	var muzzle: Marker2D = _player.get_node("Muzzle") as Marker2D
	assert_eq(missile.global_position, muzzle.global_position, "spawned at the Muzzle")
	assert_almost_eq(missile.velocity, Vector2(0.6, -0.8) * 900.0, Vector2(0.001, 0.001))
	assert_eq(missile.damage, 8)
	assert_almost_eq(missile.rotation, missile.velocity.angle() + PI / 2.0, 0.0001)


func test_close_cursor_flies_straight_up() -> void:
	for offset: Vector2 in [Vector2(32, 0), Vector2(-32, 0), Vector2(0, 32), Vector2(0, -32), Vector2.ZERO]:
		assert_eq(Player.missile_direction(SHIP, SHIP + offset, 32.0), Vector2.UP, "offset %s" % offset)
	var missile: Missile = _fire_once_at(SHIP + Vector2(32, 0))
	if missile != null:
		assert_eq(missile.velocity, Vector2(0, -900))


func test_just_outside_aims_at_cursor() -> void:
	assert_eq(Player.missile_direction(SHIP, SHIP + Vector2(33, 0), 32.0), Vector2.RIGHT)
	var missile: Missile = _fire_once_at(SHIP + Vector2(33, 0))
	if missile != null:
		assert_almost_eq(missile.velocity, Vector2(900, 0), Vector2(0.001, 0.001))


func test_cooldown_drops_presses_then_fires() -> void:
	_ticks(true, 1)
	_ticks(true, 89)
	assert_eq(_missiles().size(), 1, "presses on ticks 1-89 dropped")
	_ticks(true, 1)
	assert_eq(_missiles().size(), 2, "tick 90 fires again")


func test_presses_during_cooldown_not_buffered() -> void:
	_ticks(true, 1)
	_ticks(true, 10)
	_ticks(false, 100)
	assert_eq(_missiles().size(), 1, "no buffered shot after the cooldown")


func test_ring_signal() -> void:
	_ticks(true, 1)
	_ticks(false, 90)
	_ticks(false, 30)
	var count: int = get_signal_emit_count(Events, "missile_cooldown_changed")
	assert_eq(count, 91, "1.0 on fire, then one per cooldown tick")
	if count != 91:
		return
	var ratios: Array[float] = []
	for i: int in count:
		ratios.append(float(get_signal_parameters(Events, "missile_cooldown_changed", i)[0]))
	assert_eq(ratios[0], 1.0, "just fired")
	for i: int in range(1, count):
		assert_lt(ratios[i], ratios[i - 1], "strictly decreasing at %d" % i)
	assert_eq(ratios[count - 1], 0.0, "last emit exactly 0")


func test_not_pressed_no_missile_no_emit() -> void:
	_ticks(false, 120)
	assert_eq(_missiles().size(), 0)
	assert_signal_not_emitted(Events, "missile_cooldown_changed")


func test_no_spawner_no_missile_no_emit() -> void:
	var lone: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(lone)
	lone.set_physics_process(false)
	lone.step_missile(true, FAR_TARGET, DT)
	lone.step_missile(true, FAR_TARGET, DT)
	assert_eq(_projectiles.get_child_count(), 0)
	assert_signal_not_emitted(Events, "missile_cooldown_changed")
	# Cooldown stayed 0: once a spawner arrives the first press fires.
	lone.set_spawner(_spawner)
	lone.step_missile(true, FAR_TARGET, DT)
	assert_eq(_projectiles.get_child_count(), 1)


func test_failed_spawn_does_not_start_cooldown() -> void:
	# A World without a Projectiles container: spawn_projectile returns null.
	var bare: Node2D = Node2D.new()
	for container: String in ["Enemies", "Asteroids"]:
		var node: Node2D = Node2D.new()
		node.name = container
		bare.add_child(node)
	add_child_autofree(bare)
	var broken: Spawner = Spawner.new()
	broken.world = bare
	add_child_autofree(broken)
	assert_push_error("Projectiles")
	_player.set_spawner(broken)
	_player.step_missile(true, FAR_TARGET, DT)
	assert_signal_not_emitted(Events, "missile_cooldown_changed")
	# Cooldown stayed 0: the next press with a working spawner fires at once.
	_player.set_spawner(_spawner)
	_player.step_missile(true, FAR_TARGET, DT)
	assert_eq(_missiles().size(), 1)


func test_laser_and_missile_fire_in_same_tick() -> void:
	_player.step_fire(true, DT)
	_player.step_missile(true, FAR_TARGET, DT)
	assert_eq(_projectiles.get_child_count(), 2)
	var bolts: int = 0
	for child: Node in _projectiles.get_children():
		if child is LaserBolt:
			bolts += 1
	assert_eq(bolts, 1, "one laser bolt")
	assert_eq(_missiles().size(), 1, "one missile")


func test_non_positive_cooldown_warns_fires_every_press_no_emit() -> void:
	var missile_tuning: Dictionary = Config.tuning["weapons"]["missile"]
	var original: Variant = missile_tuning["cooldown_s"]
	missile_tuning["cooldown_s"] = 0
	var fresh: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(fresh)
	missile_tuning["cooldown_s"] = original
	fresh.set_physics_process(false)
	fresh.set_spawner(_spawner)
	assert_push_warning("cooldown_s")
	for i: int in 3:
		fresh.step_missile(true, FAR_TARGET, DT)
		var sfx: AudioStreamPlayer = Audio.newest_player()
		assert_not_null(sfx)
		if sfx != null:
			assert_eq(sfx.stream, Audio.SFX[&"missile_launch"], "thump on every launch")
		assert_true((fresh.get_node("Muzzle/MuzzleFlash") as Node2D).visible, "flash on every launch")
	assert_eq(_missiles().size(), 3, "fires on every press")
	assert_signal_not_emitted(Events, "missile_cooldown_changed")


func test_launch_plays_thump_and_flashes() -> void:
	var flash: Node2D = _player.get_node("Muzzle/MuzzleFlash") as Node2D
	assert_false(flash.visible, "hidden at start")
	_player.step_fire(true, DT)
	_player.step_missile(true, FAR_TARGET, DT)
	var sfx: AudioStreamPlayer = Audio.newest_player()
	assert_not_null(sfx)
	if sfx != null:
		assert_eq(sfx.stream, Audio.SFX[&"missile_launch"])
	assert_true(flash.visible, "muzzle flash on launch")


func test_missile_flash_hides_after_flash_time() -> void:
	var flash: Node2D = _player.get_node("Muzzle/MuzzleFlash") as Node2D
	_player.step_missile(true, FAR_TARGET, DT)
	assert_true(flash.visible, "shown on launch")
	# step_fire decays the flash every tick: MISSILE_FLASH_S is 3 ticks at 1/60 s.
	_player.step_fire(false, DT)
	_player.step_fire(false, DT)
	assert_true(flash.visible, "still shown after 2 ticks")
	_player.step_fire(false, DT)
	assert_false(flash.visible, "hidden after MISSILE_FLASH_S")


func test_press_on_cooldown_no_thump() -> void:
	_player.step_missile(true, FAR_TARGET, DT)
	_player.step_missile(true, FAR_TARGET, DT)
	assert_eq(_missiles().size(), 1, "second press on cooldown")
	Audio.play_sfx(&"explosion_small")
	var before: AudioStreamPlayer = Audio.newest_player()
	_player.step_missile(true, FAR_TARGET, DT)
	assert_eq(Audio.newest_player(), before, "no thump without a launch")


func test_failed_spawn_no_thump_no_flash() -> void:
	# A World without a Projectiles container: spawn_projectile returns null.
	var bare: Node2D = Node2D.new()
	for container: String in ["Enemies", "Asteroids"]:
		var node: Node2D = Node2D.new()
		node.name = container
		bare.add_child(node)
	add_child_autofree(bare)
	var broken: Spawner = Spawner.new()
	broken.world = bare
	add_child_autofree(broken)
	assert_push_error("Projectiles")
	_player.set_spawner(broken)
	Audio.play_sfx(&"explosion_small")
	var before: AudioStreamPlayer = Audio.newest_player()
	_player.step_missile(true, FAR_TARGET, DT)
	assert_eq(Audio.newest_player(), before, "no missile_launch sound")
	assert_false((_player.get_node("Muzzle/MuzzleFlash") as Node2D).visible, "muzzle flash stays hidden")


## Counts missiles added to the sandbox's Projectiles container (they may leave the screen).
func _count_missile_spawns(sandbox: Node2D) -> Array[int]:
	var count: Array[int] = [0]
	sandbox.get_node("World/Projectiles").child_entered_tree.connect(
			func(node: Node) -> void:
				if node is Missile:
					count[0] += 1)
	return count


func test_held_rmb_fires_once_through_physics_process() -> void:
	var sandbox: Node2D = SANDBOX_SCENE.instantiate() as Node2D
	add_child_autofree(sandbox)
	var spawned: Array[int] = _count_missile_spawns(sandbox)
	Input.action_press(&"fire_missile")
	await wait_physics_frames(120)
	assert_eq(spawned[0], 1, "held RMB is one press: one missile, even after the cooldown")


func test_rmb_while_paused_fires_nothing() -> void:
	var sandbox: Node2D = SANDBOX_SCENE.instantiate() as Node2D
	add_child_autofree(sandbox)
	var spawned: Array[int] = _count_missile_spawns(sandbox)
	PauseArbiter.push(&"menu")
	Input.action_press(&"fire_missile")
	await wait_physics_frames(10)
	assert_eq(spawned[0], 0, "no missile while paused")
