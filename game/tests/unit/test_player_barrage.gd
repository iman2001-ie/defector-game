extends GutTest
## Player barrage (Story 3.5): try_barrage spends abilities.barrage.cost through
## GameState and starts the PlayerWeapons volley (12 micro-missiles over 2.0 s,
## one every duration_s / missiles, whoosh each, LARGE finish at the muzzle on
## the last launch); too little energy is denied; a running volley is never
## restarted; death stops it; pause freezes it. Driven through try_barrage /
## step_barrage with physics off, plus one test through the real
## `ability_barrage` input action.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")
const DT: float = 1.0 / 60.0
const SHIP: Vector2 = Vector2(960, 900)

var _player: Player
var _spawner: Spawner
var _world: Node2D
var _projectiles: Node2D
var _effects: Node2D
var _lines: Array[String] = []
## Micro-missiles added to Projectiles (they may leave or be freed later).
var _launched: int = 0


func before_each() -> void:
	_lines.clear()
	_launched = 0
	Log.sink = _capture
	GameState.energy = 0
	_world = Node2D.new()
	for container: String in ["Projectiles", "Enemies", "Asteroids", "Effects"]:
		var node: Node2D = Node2D.new()
		node.name = container
		_world.add_child(node)
	add_child_autofree(_world)
	_projectiles = _world.get_node("Projectiles") as Node2D
	_effects = _world.get_node("Effects") as Node2D
	_projectiles.child_entered_tree.connect(_on_projectile_added)
	_spawner = Spawner.new()
	_spawner.world = _world
	add_child_autofree(_spawner)
	_player = PLAYER_SCENE.instantiate() as Player
	_player.warp_mouse = _ignore_warp
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.global_position = SHIP
	_player.set_spawner(_spawner)
	watch_signals(Events)


func after_each() -> void:
	Input.action_release(&"ability_barrage")
	Log.sink = Callable()
	GameState.energy = 0
	Feedback.reset()
	PauseArbiter.clear()
	_player = null
	_spawner = null
	_world = null
	_projectiles = null
	_effects = null


func _ignore_warp(_p: Vector2) -> void:
	pass


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _logged(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.begins_with(prefix):
			out.append(line)
	return out


func _on_projectile_added(node: Node) -> void:
	if node is MicroMissile:
		_launched += 1


func _muzzle() -> Vector2:
	return (_player.get_node("Muzzle") as Marker2D).global_position


func _explosions() -> Array[Explosion]:
	var out: Array[Explosion] = []
	for child: Node in _effects.get_children():
		if child is Explosion:
			out.append(child as Explosion)
	return out


func _start(energy: int = 100) -> void:
	GameState.energy = energy
	assert_true(_player.try_barrage(), "barrage started")


func _ticks(n: int) -> void:
	for i: int in n:
		_player.step_barrage(DT)


# --- Activate / deny --------------------------------------------------------------

func test_activate_spends_cost_and_launches_one_at_once() -> void:
	GameState.energy = 100
	assert_true(_player.try_barrage())
	assert_eq(GameState.energy, 0)
	assert_signal_emitted_with_parameters(Events, "energy_changed", [0, 100])
	assert_eq(_launched, 1, "one micro-missile on the press tick")
	var micros: Array[Node] = _projectiles.get_children()
	assert_eq(micros.size(), 1)
	if micros.size() == 1:
		var micro: MicroMissile = micros[0] as MicroMissile
		assert_not_null(micro, "a MicroMissile")
		if micro != null:
			assert_eq(micro.global_position, _muzzle(), "at the muzzle")
			assert_eq(micro.velocity, Vector2.UP * Config.num("abilities.barrage.speed_px_s"), "launched straight up")
			assert_eq(micro.damage, 6)
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"barrage_whoosh"], "whoosh played")
	assert_true((_player.get_node("Muzzle/MuzzleFlash") as Node2D).visible, "muzzle flash")
	assert_true(_player.is_barraging())
	assert_signal_not_emitted(Events, "ability_denied")
	assert_eq(_logged("[INFO][combat]").size(), 1, "one INFO line")


func test_too_little_energy_is_denied() -> void:
	GameState.energy = 99
	assert_false(_player.try_barrage())
	assert_eq(GameState.energy, 99, "nothing spent")
	assert_signal_emit_count(Events, "ability_denied", 1)
	assert_signal_emitted_with_parameters(Events, "ability_denied", [&"barrage"])
	assert_signal_not_emitted(Events, "energy_changed")
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"ability_denied"], "denied SFX played")
	assert_false(_player.is_barraging())
	_ticks(130)
	assert_eq(_launched, 0, "no missiles")
	assert_eq(_explosions().size(), 0, "no finish")


func test_running_volley_is_not_restarted() -> void:
	_start()
	_ticks(25)
	var left: int = (_player.get_node("Weapons") as PlayerWeapons).barrage_left()
	var launched: int = _launched
	GameState.energy = 100
	var energy_emits: int = get_signal_emit_count(Events, "energy_changed")
	assert_false(_player.try_barrage(), "already running")
	assert_eq(GameState.energy, 100, "nothing spent")
	assert_eq((_player.get_node("Weapons") as PlayerWeapons).barrage_left(), left, "not extended")
	assert_eq(_launched, launched, "no extra launch")
	assert_signal_not_emitted(Events, "ability_denied")
	assert_eq(get_signal_emit_count(Events, "energy_changed"), energy_emits, "no energy_changed")


func test_dead_ship_does_nothing() -> void:
	_player.hearts = 1
	_player.apply_damage(1, null)
	assert_true(_player.is_dead())
	GameState.energy = 100
	watch_signals(Events)
	assert_false(_player.try_barrage())
	assert_eq(GameState.energy, 100)
	assert_signal_not_emitted(Events, "ability_denied")
	assert_signal_not_emitted(Events, "energy_changed")
	assert_eq(_launched, 0)


# --- Cadence and finish -----------------------------------------------------------

func test_cadence_twelve_launches_on_ticks_0_to_110() -> void:
	_start()
	var launch_ticks: Array[int] = [0]
	var last: int = _launched
	for tick: int in range(1, 200):
		_player.step_barrage(DT)
		if _launched != last:
			assert_eq(_launched, last + 1, "one launch per tick")
			# The last launch also plays the LARGE finish, which is the newest sound then.
			var expected: StringName = &"explosion_large" if _launched == 12 else &"barrage_whoosh"
			assert_eq(Audio.newest_player().stream, Audio.SFX[expected], "%s on tick %d" % [expected, tick])
			launch_ticks.append(tick)
			last = _launched
	assert_eq(launch_ticks, [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110] as Array[int])
	assert_eq(_launched, 12, "12 total")
	assert_false(_player.is_barraging(), "volley over")


## step_barrage runs before the Q read, so the press tick launches once and the
## next launch lands 10 ticks later (a swap would give ticks 0, 9, 19, ...).
func test_physics_process_steps_before_reading_q() -> void:
	GameState.energy = 100
	Input.action_press(&"ability_barrage")
	_player._physics_process(DT)
	Input.action_release(&"ability_barrage")
	for i: int in 9:
		_player._physics_process(DT)
	assert_eq(_launched, 1, "only the press-tick launch after 10 ticks")
	_player._physics_process(DT)
	assert_eq(_launched, 2, "second launch on tick 10")


func test_finish_plays_one_large_impact_at_the_muzzle_on_the_last_launch() -> void:
	_start()
	_ticks(109)
	assert_eq(_launched, 11)
	assert_eq(_explosions().size(), 0, "no finish before the last launch")
	_ticks(1)
	assert_eq(_launched, 12)
	var booms: Array[Explosion] = _explosions()
	assert_eq(booms.size(), 1, "exactly one finish")
	if booms.size() == 1:
		assert_eq(booms[0].explosion_scale, 2.0, "LARGE tier")
		assert_eq(booms[0].global_position, _muzzle(), "at the muzzle")
	assert_true(Feedback.is_hit_stopped(), "hit-stop started")
	Feedback.reset()
	_ticks(120)
	assert_eq(_explosions().size(), 1, "only once")


func test_death_mid_volley_stops_launches_and_finish() -> void:
	_start()
	_ticks(40)
	assert_eq(_launched, 5)
	_player._die()
	assert_false(_player.is_barraging())
	var booms: int = _explosions().size()
	Feedback.reset()
	_ticks(120)
	assert_eq(_launched, 5, "no more launches")
	assert_eq(_explosions().size(), booms, "no finish")


func test_mistuned_data_warns_and_spends_without_firing() -> void:
	var barrage: Dictionary = Config.tuning["abilities"]["barrage"]
	var original: Variant = barrage["missiles"]
	barrage["missiles"] = 0
	var fresh: Player = PLAYER_SCENE.instantiate() as Player
	fresh.warp_mouse = _ignore_warp
	add_child_autofree(fresh)
	barrage["missiles"] = original
	fresh.set_physics_process(false)
	fresh.set_spawner(_spawner)
	assert_push_warning("abilities.barrage")
	assert_eq(_logged("[WARN][data]").size(), 1, "one data warning")
	GameState.energy = 100
	assert_true(fresh.try_barrage())
	assert_eq(GameState.energy, 0, "energy still spent")
	assert_false(fresh.is_barraging())
	for i: int in 130:
		fresh.step_barrage(DT)
	assert_eq(_launched, 0, "nothing fires")


func test_no_spawner_still_counts_and_plays_nothing() -> void:
	var lone: Player = PLAYER_SCENE.instantiate() as Player
	lone.warp_mouse = _ignore_warp
	add_child_autofree(lone)
	lone.set_physics_process(false)
	Audio.play_sfx(&"explosion_small")
	var before: AudioStreamPlayer = Audio.newest_player()
	GameState.energy = 100
	assert_true(lone.try_barrage())
	assert_eq((lone.get_node("Weapons") as PlayerWeapons).barrage_left(), 11, "the first launch counted")
	assert_eq(Audio.newest_player(), before, "no whoosh")
	for i: int in 110:
		lone.step_barrage(DT)
	assert_false(lone.is_barraging(), "volley ran out")
	assert_eq(_projectiles.get_child_count(), 0)


# --- Pause and physics ------------------------------------------------------------

func test_physics_process_runs_the_volley() -> void:
	_start()
	for i: int in 110:
		_player._physics_process(DT)
	assert_eq(_launched, 12)


func test_volley_freezes_under_pause() -> void:
	_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	_player.set_physics_process(true)
	_start()
	var weapons: PlayerWeapons = _player.get_node("Weapons") as PlayerWeapons
	PauseArbiter.push(&"menu")
	await wait_physics_frames(30)
	assert_eq(weapons.barrage_left(), 11, "no launches while paused")
	assert_eq(_launched, 1)
	PauseArbiter.clear()
	await wait_physics_frames(30)
	assert_lt(weapons.barrage_left(), 11, "resumes after unpause")


# --- Real input path --------------------------------------------------------------

func test_ability_barrage_action_starts_the_volley() -> void:
	GameState.energy = 100
	_player.set_physics_process(true)
	Input.action_press(&"ability_barrage")
	await wait_physics_frames(1)
	Input.action_release(&"ability_barrage")
	_player.set_physics_process(false)
	assert_eq(GameState.energy, 0, "energy spent")
	assert_eq(_launched, 1, "one micro-missile")
