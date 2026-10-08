extends GutTest
## Sandbox scene: World containers, Player (no reticle node), gameplay mouse mode,
## Wasp formation respawn and the asteroid timer.

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const CONTAINERS: Array[String] = ["Asteroids", "Enemies", "Allies", "Pickups", "Projectiles", "Effects"]

var _sandbox: Node2D


func before_each() -> void:
	_sandbox = SANDBOX_SCENE.instantiate() as Node2D
	add_child_autofree(_sandbox)


func after_each() -> void:
	_sandbox = null
	Config.load_data()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	PauseArbiter.clear()
	Log.sink = Callable()


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
	# No reticle node (decision #29): the ship is the cursor, so World holds only
	# the containers and the Player.
	var names: Array[String] = []
	for child: Node in world.get_children():
		names.append(String(child.name))
	var expected: Array[String] = CONTAINERS.duplicate()
	expected.append("Player")
	assert_eq(names, expected, "World holds only the containers and the Player")


func test_player_starts_at_spawn_point() -> void:
	var player: Player = _sandbox.get_node("World/Player") as Player
	assert_eq(player.position, Vector2(960, 900))


func test_gameplay_mouse_mode_confined_hidden() -> void:
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_CONFINED_HIDDEN, "no reasons")
	PauseArbiter.push(&"menu")
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "with a reason")


func test_spawner_wired_to_world_and_player() -> void:
	var spawner: Spawner = _sandbox.get_node_or_null("Spawner") as Spawner
	assert_not_null(spawner, "Sandbox/Spawner is a Spawner")
	if spawner == null:
		return
	assert_eq(spawner.world, _sandbox.get_node("World"), "Spawner.world is World")
	var player: Player = _sandbox.get_node("World/Player") as Player
	player.step_fire(true, 1.0 / 60.0)
	assert_eq(_sandbox.get_node("World/Projectiles").get_child_count(), 1, "player fires through the sandbox Spawner")


func test_shake_camera_frames_the_playfield() -> void:
	var camera: ShakeCamera = _sandbox.get_node_or_null("ShakeCamera") as ShakeCamera
	assert_not_null(camera, "Sandbox/ShakeCamera is a ShakeCamera")
	if camera == null:
		return
	camera.set_process(false)
	assert_true(camera.enabled, "enabled")
	assert_eq(camera.position, Vector2(960, 540), "centred on the playfield")
	assert_eq(camera.offset, Vector2.ZERO, "no shake")
	assert_eq(camera.get_screen_center_position(), Vector2(960, 540), "screen centre")


# --- Wasp formation and asteroids (Story 1.4) ---------------------------------

func _wasps() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for child: Node in _sandbox.get_node("World/Enemies").get_children():
		if child is Enemy:
			out.append(child as Enemy)
	return out


func _expected_slots() -> Array[Vector2]:
	var slots: Array[Vector2] = []
	for y: float in [160.0, 280.0]:
		for x: float in [720.0, 880.0, 1040.0, 1200.0]:
			slots.append(Vector2(x, y))
	return slots


func _positions(wasps: Array[Enemy]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for wasp: Enemy in wasps:
		out.append(wasp.global_position)
	return out


func test_formation_grid_4x2_on_ready() -> void:
	var wasps: Array[Enemy] = _wasps()
	assert_eq(wasps.size(), 8, "8 Wasps")
	assert_eq(_positions(wasps), _expected_slots(), "grid_4x2 slots centred on x 960")
	for wasp: Enemy in wasps:
		assert_eq(wasp.type_id, &"wasp")
		assert_lt(wasp.global_position.y, 1080.0 * 0.4, "inside the top 40%")


func test_formation_respawns_when_all_dead() -> void:
	var first: Array[Enemy] = _wasps()
	for wasp: Enemy in first:
		wasp.apply_damage(3, null)
	await wait_process_frames(2)
	var fresh: Array[Enemy] = _wasps()
	assert_eq(fresh.size(), 8, "8 alive again")
	for wasp: Enemy in fresh:
		assert_false(wasp.is_queued_for_deletion(), "new Wasp")
		assert_false(first.has(wasp), "not an old Wasp")
	assert_eq(_positions(fresh), _expected_slots(), "same slots")


func test_respawn_after_kill_inside_physics_callback() -> void:
	var wasps: Array[Enemy] = _wasps()
	for i: int in 7:
		wasps[i].apply_damage(3, null)
	var last: Enemy = wasps[7]
	var spawner: Spawner = _sandbox.get_node("Spawner") as Spawner
	for i: int in 3:
		spawner.spawn_projectile(&"laser_bolt",
			{"position": last.global_position + Vector2(0, 300), "velocity": Vector2(0, -1800), "damage": 1})
	await wait_physics_frames(30)
	var fresh: Array[Enemy] = _wasps()
	assert_eq(fresh.size(), 8, "8 alive again")
	for wasp: Enemy in fresh:
		assert_false(wasp.is_queued_for_deletion(), "new Wasp")
		assert_false(wasps.has(wasp), "not an old Wasp")
	assert_eq(_positions(fresh), _expected_slots(), "same slots")


func test_no_respawn_while_some_alive() -> void:
	var wasps: Array[Enemy] = _wasps()
	for i: int in 7:
		wasps[i].apply_damage(3, null)
	await wait_process_frames(2)
	assert_eq(_wasps().size(), 1, "only the survivor")


func test_asteroid_timer_spawns_every_interval() -> void:
	_sandbox.set_physics_process(false)
	_sandbox.rng.seed = 1234
	_sandbox.set("_asteroid_elapsed", 0.0)
	var asteroids: Node = _sandbox.get_node("World/Asteroids")
	for i: int in 179:
		_sandbox.step_asteroids(1.0 / 60.0)
	assert_eq(asteroids.get_child_count(), 0, "none before the first interval")
	_sandbox.step_asteroids(1.0 / 60.0)
	assert_eq(asteroids.get_child_count(), 1, "one after 3.0 s")
	for i: int in 180:
		_sandbox.step_asteroids(1.0 / 60.0)
	assert_eq(asteroids.get_child_count(), 2, "two after 6.0 s")
	for child: Node in asteroids.get_children():
		var rock: Asteroid = child as Asteroid
		rock.set_physics_process(false)
		assert_true(Asteroid.SIZES.has(rock.size))
		assert_gte(rock.global_position.x - rock.radius, 0.0, "fully inside the left edge")
		assert_lte(rock.global_position.x + rock.radius, 1920.0, "fully inside the right edge")
		assert_eq(rock.global_position.y, -rock.radius, "just above the top edge")


func test_asteroid_sizes_vary() -> void:
	_sandbox.set_physics_process(false)
	_sandbox.rng.seed = 42
	for i: int in 30:
		_sandbox.step_asteroids(3.0)
	var sizes: Dictionary = {}
	for child: Node in _sandbox.get_node("World/Asteroids").get_children():
		var rock: Asteroid = child as Asteroid
		rock.set_physics_process(false)
		sizes[rock.size] = true
		assert_gte(rock.global_position.x - rock.radius, 0.0, "fully inside the left edge")
		assert_lte(rock.global_position.x + rock.radius, 1920.0, "fully inside the right edge")
		assert_eq(rock.global_position.y, -rock.radius, "just above the top edge")
	assert_eq(sizes.size(), 3, "every size appears")


func test_paused_sandbox_spawns_no_asteroid() -> void:
	var asteroids: Node = _sandbox.get_node("World/Asteroids")
	_sandbox.set("_asteroid_elapsed", 2.99)
	PauseArbiter.push(&"menu")
	await wait_physics_frames(10)
	assert_eq(asteroids.get_child_count(), 0, "no asteroid while paused")
	PauseArbiter.pop(&"menu")
	await wait_physics_frames(10)
	assert_eq(asteroids.get_child_count(), 1, "timer resumes once unpaused")


# --- Overlay, glow and stress mode (Story 1.7) ---------------------------------

func test_overlay_layer_holds_debug_tools() -> void:
	var overlay: CanvasLayer = _sandbox.get_node_or_null("Overlay") as CanvasLayer
	assert_not_null(overlay, "Sandbox/Overlay is a CanvasLayer")
	if overlay == null:
		return
	assert_eq(overlay.layer, 30, "Overlay layer 30")
	assert_true(overlay.get_node_or_null("DebugTools") is DebugTools, "Overlay/DebugTools")


func test_overlay_text_counts_enemies() -> void:
	var tools: DebugTools = _sandbox.get_node("Overlay/DebugTools") as DebugTools
	tools.refresh_overlay()
	var text: String = (tools.get_node("OverlayLabel") as Label).text
	assert_string_contains(text, "FPS")
	assert_string_contains(text, "frame ms")
	assert_string_contains(text, "nodes")
	assert_string_contains(text, "enemies 8")


func test_world_environment_glow() -> void:
	var env_node: WorldEnvironment = _sandbox.get_node_or_null("WorldEnvironment") as WorldEnvironment
	assert_not_null(env_node, "Sandbox/WorldEnvironment")
	if env_node == null:
		return
	var env: Environment = env_node.environment
	assert_not_null(env, "has an Environment")
	if env == null:
		return
	assert_eq(env.background_mode, Environment.BG_CANVAS, "canvas background")
	assert_true(env.glow_enabled, "glow on")
	assert_lt(env.glow_hdr_threshold, 1.0, "full-bright neon blooms")
	# Story 1.9: the three values come from tuning.json -> render.glow.
	assert_almost_eq(env.glow_intensity, Config.num("render.glow.intensity"), 0.0001, "intensity from data")
	assert_almost_eq(env.glow_bloom, Config.num("render.glow.bloom"), 0.0001, "bloom from data")
	assert_almost_eq(env.glow_hdr_threshold, Config.num("render.glow.hdr_threshold"), 0.0001, "threshold from data")


## F5 path: Config.reload() then restart_scene re-instantiates the scene root,
## whose _ready() re-applies render.glow.
func test_world_environment_glow_follows_changed_data() -> void:
	(Config.tuning["render"]["glow"] as Dictionary)["intensity"] = 1.3
	_sandbox.queue_free()
	_sandbox = SANDBOX_SCENE.instantiate() as Node2D
	add_child_autofree(_sandbox)
	var env: Environment = (_sandbox.get_node("WorldEnvironment") as WorldEnvironment).environment
	assert_almost_eq(env.glow_intensity, 1.3, 0.0001, "env intensity follows the new data")


func test_normal_sandbox_is_not_stress() -> void:
	assert_false(_sandbox.stress_mode, "no user args in tests")
	assert_eq(_wasps().size(), 8, "8-Wasp formation")


## A fresh sandbox in stress mode (replaces the one from before_each).
func _stress_sandbox() -> Node2D:
	_sandbox.queue_free()
	_sandbox = SANDBOX_SCENE.instantiate() as Node2D
	_sandbox.stress_mode = true
	add_child_autofree(_sandbox)
	return _sandbox


func test_stress_grid_spawns_40_in_the_enemy_zone() -> void:
	_stress_sandbox()
	var wasps: Array[Enemy] = _wasps()
	assert_eq(wasps.size(), 40, "40 Wasps")
	for wasp: Enemy in wasps:
		assert_between(wasp.global_position.x, 0.0, 1920.0, "x on screen")
		assert_between(wasp.global_position.y, 120.0, 432.0, "y in the enemy zone")
	var unique: Dictionary = {}
	for pos: Vector2 in _positions(wasps):
		unique[pos] = true
	assert_eq(unique.size(), 40, "every slot distinct")


func test_stress_refills_a_dead_wasp_at_its_slot() -> void:
	_stress_sandbox()
	var wasps: Array[Enemy] = _wasps()
	var victim: Enemy = wasps[13]
	var slot: Vector2 = victim.global_position
	victim.apply_damage(3, null)
	await wait_process_frames(2)
	var fresh: Array[Enemy] = _wasps()
	assert_eq(fresh.size(), 40, "40 alive again")
	var refilled: Array[Enemy] = []
	for wasp: Enemy in fresh:
		if not wasps.has(wasp):
			refilled.append(wasp)
	assert_eq(refilled.size(), 1, "exactly one new Wasp")
	if refilled.size() == 1:
		assert_eq(refilled[0].global_position, slot, "at the dead Wasp's slot")


# --- Stress projectiles at the NFR peak (DW-9) ---------------------------------

## The stress grid's bottom row y (rows from STRESS_TOP_Y, STRESS_SPACING.y apart).
const STRESS_GRID_BOTTOM_Y: float = 150.0 + 3 * 72.0


func _projectiles() -> Array[Projectile]:
	var out: Array[Projectile] = []
	for child: Node in _sandbox.get_node("World/Projectiles").get_children():
		if child is Projectile and not child.is_queued_for_deletion():
			out.append(child as Projectile)
	return out


func test_stress_tops_up_projectiles_within_the_per_tick_cap() -> void:
	_stress_sandbox()
	_sandbox.set_physics_process(false)
	var target: int = Config.int_("debug.stress.projectiles")
	var cap: int = Config.int_("debug.stress.projectile_spawn_per_tick")
	assert_gt(target, 0, "target from Config")
	assert_gt(cap, 0, "cap from Config")
	var ticks: int = ceili(float(target) / cap)
	var previous: int = 0
	for i: int in ticks:
		_sandbox.step_stress_projectiles()
		var live: int = _projectiles().size()
		assert_lte(live - previous, cap, "tick %d spawns at most the cap" % i)
		previous = live
	assert_eq(_projectiles().size(), target, "at the target after %d ticks" % ticks)
	_sandbox.step_stress_projectiles()
	assert_eq(_projectiles().size(), target, "spawns nothing at the target")


func test_stress_projectiles_spawn_below_the_grid_and_fly_down() -> void:
	_stress_sandbox()
	_sandbox.set_physics_process(false)
	_sandbox.step_stress_projectiles()
	var shots: Array[Projectile] = _projectiles()
	assert_gt(shots.size(), 0, "some spawned")
	for shot: Projectile in shots:
		assert_gt(shot.global_position.y, STRESS_GRID_BOTTOM_Y, "below the Wasp grid")
		assert_between(shot.global_position.x, 0.0, 1920.0, "x on screen")
		assert_gt(shot.velocity.y, 0.0, "flies down")
		assert_almost_eq(shot.velocity.length(), Config.num("weapons.enemy_bullet.max_speed_px_s"), 0.001, "enemy-bullet speed")


func test_stress_reaches_the_target_while_running() -> void:
	_stress_sandbox()
	var target: int = Config.int_("debug.stress.projectiles")
	var cap: int = Config.int_("debug.stress.projectile_spawn_per_tick")
	await wait_physics_frames(ceili(float(target) / cap) + 2)
	var live: int = _projectiles().size()
	assert_between(live, target - cap, target, "about the target live, never above it")
	assert_eq(_wasps().size(), 40, "alongside the 40-Wasp grid")


func test_normal_sandbox_spawns_no_stress_projectiles() -> void:
	await wait_physics_frames(5)
	assert_eq(_projectiles().size(), 0, "no projectiles without stress mode")


func test_prewarm_skipped_only_by_no_prewarm_in_debug_builds() -> void:
	var on: Dictionary = DebugArgs.parse(PackedStringArray())
	var off: Dictionary = DebugArgs.parse(PackedStringArray(["--no-prewarm"]))
	assert_true(_sandbox.should_prewarm(true, on), "debug build, no flag: pre-warm")
	assert_false(_sandbox.should_prewarm(true, off), "debug build, --no-prewarm: skip")
	assert_true(_sandbox.should_prewarm(false, off), "release build ignores --no-prewarm")


# --- User args wiring (DW-27) ---------------------------------------------------

var _lines: Array[String] = []


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


## A fresh sandbox whose _ready parses args (replaces the one from before_each),
## with logs captured during _ready.
func _sandbox_with_args(args: PackedStringArray) -> Node2D:
	_sandbox.queue_free()
	_lines.clear()
	_sandbox = SANDBOX_SCENE.instantiate() as Node2D
	_sandbox.user_args = args
	Log.sink = _capture
	add_child_autofree(_sandbox)
	Log.sink = Callable()
	return _sandbox


## Explosions in this sandbox's World/Effects at the off-screen pre-warm spot.
func _prewarm_explosions() -> Array[Explosion]:
	var out: Array[Explosion] = []
	for child: Node in _sandbox.get_node("World/Effects").get_children():
		if child is Explosion and (child as Explosion).global_position == Feedback.PREWARM_POSITION:
			out.append(child as Explosion)
	return out


func _lines_containing(text: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.contains(text):
			out.append(line)
	return out


func test_no_prewarm_arg_skips_the_prewarm() -> void:
	_sandbox_with_args(PackedStringArray(["--no-prewarm"]))
	assert_eq(_prewarm_explosions().size(), 0, "no pre-warm explosion")
	assert_eq(_lines_containing("Feedback pre-warm skipped").size(), 1, "skip logged")


func test_no_args_prewarms_one_explosion_per_tier() -> void:
	_sandbox_with_args(PackedStringArray())
	assert_eq(_prewarm_explosions().size(), ImpactTier.NAMES.size(), "one pre-warm explosion per tier")
	assert_eq(_lines_containing("Feedback pre-warm skipped").size(), 0, "no skip line")


func test_stress_arg_turns_on_stress_mode() -> void:
	_sandbox_with_args(PackedStringArray(["--stress"]))
	assert_true(_sandbox.stress_mode, "stress_mode from user_args")
	assert_eq(_wasps().size(), 40, "40-Wasp grid")
