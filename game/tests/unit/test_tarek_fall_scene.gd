extends GutTest
## TarekFallScene (Story 6.5, reworked in Epic 7 playtest D): the director of
## Tarek's fall, driven through step(delta) with every physics tick off (the
## scene, the Player, Tarek and the Ram). On the tarek_fall story event it
## locks Vale and holds enemy fire, sends Tarek to intercept_offset_px above
## Vale and shows the lock-on line; it requests the cut-off line once at
## impact_s minus the line's typing time (cut_off_at / comms.cutoff_chars_per_s),
## launches the Ram at impact_s - ram_travel_s from (Vale.x, ram_start_y) to
## the intercept point, starts the slow motion at impact_s - slowmo.lead_s,
## plays the impact (Tarek FALLING) when the Ram arrives and releases Vale and
## the enemy fire release_after_s later, or at once on a level outcome. No
## patrolling Tarek: nothing happens. No Vale: Tarek falls at once and the line
## is requested. Feedback.reset() in after_each so no slow motion or hit-stop
## leaks into other suites.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")
const EVENT: StringName = &"tarek_fall"
const VALE_AT: Vector2 = Vector2(900, 900)
const DT: float = 1.0 / 60.0
## A hair, for "just before" / "just after" a timeline mark.
const EPS: float = 0.001

var _world: Node2D
var _effects: Node2D
var _enemies: Node2D
var _spawner: Spawner
var _scene: TarekFallScene
var _player: Player
var _tarek: AllyShip
var _requested: Array[StringName] = []
var _lines: Array[String] = []
## Test time since the event: the director's clock stops once it is DONE.
var _clock: float = 0.0

var impact_s: float
var travel_s: float
var lead_s: float
var release_s: float
var offset_px: float
var line_at: float


func before_each() -> void:
	_requested.clear()
	_lines.clear()
	_clock = 0.0
	Log.sink = _capture
	Events.comms_sequence_requested.connect(_on_comms_requested)
	impact_s = Config.num("story.tarek_fall.impact_s")
	travel_s = Config.num("story.tarek_fall.ram_travel_s")
	lead_s = Config.num("story.tarek_fall.slowmo.lead_s")
	release_s = Config.num("story.tarek_fall.release_after_s")
	offset_px = Config.num("story.tarek_fall.intercept_offset_px")
	line_at = impact_s - 41.0 / Config.num("comms.cutoff_chars_per_s")
	_world = Node2D.new()
	for container: String in ["Projectiles", "Enemies", "Asteroids", "Allies", "Effects"]:
		var node: Node2D = Node2D.new()
		node.name = container
		_world.add_child(node)
	_effects = _world.get_node("Effects") as Node2D
	_enemies = _world.get_node("Enemies") as Node2D
	add_child_autofree(_world)
	_spawner = Spawner.new()
	_spawner.world = _world
	add_child_autofree(_spawner)


func after_each() -> void:
	Events.comms_sequence_requested.disconnect(_on_comms_requested)
	Log.sink = Callable()
	Feedback.reset()
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Config.load_data()
	_world = null
	_effects = null
	_enemies = null
	_spawner = null
	_scene = null
	_player = null
	_tarek = null


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _on_comms_requested(id: StringName) -> void:
	_requested.append(id)


func _count_lines(text: String) -> int:
	var n: int = 0
	for line: String in _lines:
		if line == text:
			n += 1
	return n


## The cast: Vale (unless `with_player` is false), a patrolling Tarek (unless
## `ally` is ""), then the director, every physics tick off.
func _make(with_player: bool = true, ally: String = "tarek") -> TarekFallScene:
	if with_player:
		_player = PLAYER_SCENE.instantiate() as Player
		_player.warp_mouse = func(_at: Vector2) -> void: pass
		add_child_autofree(_player)
		_player.set_physics_process(false)
		_player.global_position = VALE_AT
	if not ally.is_empty():
		_tarek = _spawner.spawn_ally({"ally": ally})
		_tarek.set_physics_process(false)
	_scene = TarekFallScene.new()
	_scene.spawner = _spawner
	add_child_autofree(_scene)
	_scene.set_physics_process(false)
	return _scene


## Advances the director (and Tarek and a live Ram, as their physics ticks
## would) by `delta` in one step. A Ram launched inside this step is first
## caught up to the scene clock (as if launched exactly at impact_s -
## ram_travel_s), so the impact lands on impact_s whatever the step size.
func _step(delta: float) -> void:
	var ram: Ram = _scene.ram()
	_clock += delta
	_scene.step(delta)
	if is_instance_valid(_tarek) and not _tarek.is_queued_for_deletion():
		_tarek.step(delta)
	if ram != null and is_instance_valid(ram) and not ram.is_queued_for_deletion():
		ram.step(delta)
	elif ram == null and _scene.ram() != null:
		var launched: Ram = _scene.ram()
		launched.set_physics_process(false)
		launched.step(maxf(_scene.elapsed() - (_scene.impact_s - _scene.ram_travel_s), 0.0))


## The impact explosions under World/Effects.
func _explosions() -> Array[Explosion]:
	var out: Array[Explosion] = []
	for child: Node in _effects.get_children():
		if child is Explosion and not child.is_queued_for_deletion():
			out.append(child as Explosion)
	return out


## Steps in DT ticks until the test clock reaches `t` exactly.
func _run_to(t: float) -> void:
	while _clock < t - 0.0000001:
		_step(minf(DT, t - _clock))


func _start() -> void:
	Events.story_event_requested.emit(EVENT)


# --- Start ----------------------------------------------------------------------------

func test_tuning_is_cached() -> void:
	_make()
	assert_eq(_scene.impact_s, impact_s)
	assert_eq(_scene.ram_travel_s, travel_s)
	assert_eq(_scene.ram_scale, Config.num("story.tarek_fall.ram_scale"))
	assert_eq(_scene.ram_start_y, Config.num("story.tarek_fall.ram_start_y"))
	assert_eq(_scene.intercept_offset_px, offset_px)
	assert_eq(_scene.release_after_s, release_s)
	assert_eq(_scene.slowmo_lead_s, lead_s)
	assert_eq(_scene.slowmo_scale, Config.num("story.tarek_fall.slowmo.scale"))
	assert_eq(_scene.slowmo_hold_s, Config.num("story.tarek_fall.slowmo.hold_s"))
	assert_eq(_scene.slowmo_ramp_s, Config.num("story.tarek_fall.slowmo.ramp_s"))
	assert_eq(_scene.phase(), TarekFallScene.Phase.IDLE, "idle until the event")


func test_other_events_are_ignored() -> void:
	_make()
	Events.story_event_requested.emit(&"dev_evt")
	assert_eq(_scene.phase(), TarekFallScene.Phase.IDLE)
	assert_false(_player.is_scripted_locked())
	assert_eq(_tarek.state(), AllyShip.State.PATROL)


func test_start_locks_vale_holds_fire_and_sends_tarek() -> void:
	_make()
	_start()
	assert_eq(_scene.phase(), TarekFallScene.Phase.RUNNING)
	assert_true(_player.is_scripted_locked(), "Vale's controls are locked")
	assert_true(_player.is_invulnerable(), "Vale can't be hurt")
	assert_true(_spawner.hold_enemy_fire, "enemies hold their fire")
	assert_true(_scene.line_visible(), "the lock-on line shows")
	var point: Vector2 = VALE_AT + Vector2(0.0, -offset_px)
	assert_eq(_scene.intercept_point(), point, "intercept_offset_px above Vale")
	assert_eq(_tarek.state(), AllyShip.State.APPROACH, "Tarek dashes in")
	assert_eq(_tarek.intercept_point(), point, "to the intercept point")
	assert_eq(_requested, [] as Array[StringName], "the line is not requested at once")
	assert_null(_scene.ram(), "no Ram yet")
	assert_false(Feedback.is_slow_motion(), "no slow motion yet")
	assert_eq(_count_lines("[INFO][scene] Tarek's fall: lock-on, impact in %.2f s" % impact_s), 1)


func test_tarek_reaches_the_point_and_holds() -> void:
	_make()
	_start()
	_run_to(Config.num("allies.fall.approach_s") + DT)
	assert_eq(_tarek.state(), AllyShip.State.HOLD, "holding at the point")
	assert_eq(_tarek.global_position, _scene.intercept_point(), "between Vale and the threat")
	assert_true(_tarek.is_holding())


func test_vale_is_held_against_the_mouse_for_the_whole_scene() -> void:
	_make()
	_start()
	_run_to(impact_s)
	for i: int in 5:
		_player._physics_process(DT)
	assert_eq(_player.global_position, VALE_AT, "held in place")


# --- The cut-off line -------------------------------------------------------------------

func test_cut_off_typing_s() -> void:
	var seq: Dictionary = {"lines": [{"speaker": "tarek", "text": "x", "cut_off_at": 41}]}
	assert_almost_eq(TarekFallScene.cut_off_typing_s(seq, 16.0), 41.0 / 16.0, 0.000001, "cut_off_at / chars per second")
	assert_eq(TarekFallScene.cut_off_typing_s(seq, 0.0), 0.0, "no rate")
	assert_eq(TarekFallScene.cut_off_typing_s(seq, -5.0), 0.0, "negative rate")
	assert_eq(TarekFallScene.cut_off_typing_s({}, 16.0), 0.0, "no lines")
	assert_eq(TarekFallScene.cut_off_typing_s({"lines": []}, 16.0), 0.0, "empty lines")
	assert_eq(TarekFallScene.cut_off_typing_s({"lines": ["text"]}, 16.0), 0.0, "a non-object line")
	assert_eq(TarekFallScene.cut_off_typing_s({"lines": [{"text": "x"}]}, 16.0), 0.0, "no cut_off_at")
	assert_eq(TarekFallScene.cut_off_typing_s({"lines": [{"cut_off_at": "41"}]}, 16.0), 0.0, "a non-number cut_off_at")
	assert_eq(TarekFallScene.cut_off_typing_s({"lines": [{"cut_off_at": -3}]}, 16.0), 0.0, "a negative cut_off_at")
	var shipped: float = TarekFallScene.cut_off_typing_s(Config.sequence(TarekFallScene.CUT_OFF_SEQUENCE), Config.num("comms.cutoff_chars_per_s"))
	assert_almost_eq(shipped, 41.0 / Config.num("comms.cutoff_chars_per_s"), 0.000001, "the shipped line")


func test_line_request_time_puts_the_cut_on_the_impact() -> void:
	_make()
	_start()
	assert_almost_eq(_scene.line_request_time(), line_at, 0.000001, "impact_s - 41 / cutoff_chars_per_s")
	assert_gt(_scene.line_request_time(), 0.0)


func test_the_line_is_requested_once_at_its_time() -> void:
	_make()
	_start()
	_run_to(line_at - EPS)
	assert_eq(_requested, [] as Array[StringName], "not before its time")
	_run_to(line_at + EPS)
	assert_eq(_requested, [TarekFallScene.CUT_OFF_SEQUENCE] as Array[StringName], "requested at its time")
	_run_to(impact_s + release_s + 1.0)
	assert_eq(_requested, [TarekFallScene.CUT_OFF_SEQUENCE] as Array[StringName], "exactly once")


func test_a_line_longer_than_the_impact_is_requested_at_once() -> void:
	var fall: Dictionary = (Config.tuning["story"] as Dictionary)["tarek_fall"] as Dictionary
	fall["impact_s"] = 1.0
	fall["ram_travel_s"] = 0.4
	_make()
	_start()
	assert_eq(_scene.line_request_time(), 0.0, "clamped at 0")
	assert_eq(_requested, [TarekFallScene.CUT_OFF_SEQUENCE] as Array[StringName], "requested at the start")


# --- The Ram, the slow motion and the impact -------------------------------------------

func test_the_ram_launches_at_impact_minus_travel() -> void:
	_make()
	_start()
	_run_to(impact_s - travel_s - EPS)
	assert_null(_scene.ram(), "no Ram before its launch")
	assert_true(_scene.line_visible(), "the lock-on line still shows")
	_run_to(impact_s - travel_s + EPS)
	var ram: Ram = _scene.ram()
	assert_not_null(ram, "launched")
	if ram == null:
		return
	assert_eq(ram.get_parent(), _enemies, "spawned by the Spawner into Enemies")
	assert_false(ram.is_in_group(Groups.ENEMIES), "never an enemy")
	assert_eq(ram.from, Vector2(VALE_AT.x, Config.num("story.tarek_fall.ram_start_y")), "from above Vale")
	assert_eq(ram.to, _scene.intercept_point(), "at the intercept point")
	assert_eq(ram.travel_s, travel_s)
	assert_eq(ram.size_scale, Config.num("story.tarek_fall.ram_scale"))
	assert_false(_scene.line_visible(), "the lock-on line goes")
	assert_eq(_count_lines("[INFO][scene] Tarek's fall: the Ram dives"), 1)


func test_slow_motion_starts_at_the_lead_time() -> void:
	_make()
	_start()
	_run_to(impact_s - lead_s - EPS)
	assert_false(Feedback.is_slow_motion(), "not before the lead time")
	_run_to(impact_s - lead_s + EPS)
	assert_true(Feedback.is_slow_motion(), "slow motion before the impact")
	assert_eq(Feedback.slow_motion_scale(), Config.num("story.tarek_fall.slowmo.scale"))
	assert_ne(_tarek.state(), AllyShip.State.FALLING, "Tarek not hit yet")


func test_impact_when_the_ram_arrives() -> void:
	_make()
	_start()
	_run_to(impact_s - EPS)
	assert_eq(_tarek.state(), AllyShip.State.HOLD, "still holding just before")
	assert_eq(_scene.phase(), TarekFallScene.Phase.RUNNING)
	var ram: Ram = _scene.ram()
	assert_not_null(ram, "the Ram is in flight")
	_run_to(impact_s + EPS)
	assert_eq(_tarek.state(), AllyShip.State.FALLING, "the Ram struck Tarek")
	assert_true(_tarek.is_damaged())
	assert_eq(_scene.phase(), TarekFallScene.Phase.AFTERMATH)
	assert_null(_scene.ram(), "the Ram is gone")
	assert_true(ram == null or not is_instance_valid(ram) or ram.is_queued_for_deletion(), "freed")
	var booms: Array[Explosion] = _explosions()
	assert_eq(booms.size(), 1, "one LARGE impact explosion")
	if booms.size() == 1:
		assert_eq(booms[0].global_position, _scene.intercept_point(), "on Tarek")
	assert_true(Feedback.is_hit_stopped(), "the impact's hit-stop")
	assert_eq(_count_lines("[INFO][scene] Tarek's fall: the Ram struck Tarek"), 1)
	assert_true(_player.is_scripted_locked(), "Vale still locked through the slow motion")
	assert_true(_spawner.hold_enemy_fire)


func test_without_a_spawner_the_clock_decides_the_impact() -> void:
	_make()
	_scene.spawner = null
	_start()
	_run_to(impact_s - EPS)
	assert_null(_scene.ram(), "no Ram without a Spawner")
	assert_eq(_tarek.state(), AllyShip.State.HOLD)
	_run_to(impact_s + EPS)
	assert_eq(_tarek.state(), AllyShip.State.FALLING, "hit at impact_s")
	assert_eq(_scene.phase(), TarekFallScene.Phase.AFTERMATH)


# --- Release -----------------------------------------------------------------------------

func test_release_after_release_after_s() -> void:
	_make()
	_start()
	_run_to(impact_s + EPS)
	assert_eq(_scene.phase(), TarekFallScene.Phase.AFTERMATH)
	_run_to(impact_s + release_s - EPS)
	assert_true(_player.is_scripted_locked(), "still locked just before")
	assert_true(_spawner.hold_enemy_fire)
	_run_to(impact_s + release_s + 2.0 * EPS)
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE)
	assert_false(_player.is_scripted_locked(), "Vale's controls are back")
	assert_false(_player.is_invulnerable(), "and Vale can be hurt again")
	assert_false(_spawner.hold_enemy_fire, "enemy fire is back")
	assert_false(_scene.line_visible())
	assert_eq(_count_lines("[INFO][scene] Tarek's fall: controls released"), 1)
	_run_to(impact_s + release_s + 1.0)
	assert_eq(_requested.size(), 1, "nothing more")
	assert_eq(_explosions().size(), 1, "one impact only")


func test_level_cleared_mid_scene_releases_at_once() -> void:
	_make()
	_start()
	_run_to(line_at + EPS)
	Events.level_cleared.emit(2)
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE)
	assert_false(_player.is_scripted_locked(), "the lock is released")
	assert_false(_spawner.hold_enemy_fire, "the fire hold is released")
	assert_false(_scene.line_visible(), "the lock-on line is gone")
	assert_eq(_count_lines("[INFO][scene] Tarek's fall: controls released (level cleared)"), 1)
	_run_to(impact_s + release_s + 1.0)
	assert_null(_scene.ram(), "no Ram launched afterwards")
	assert_eq(_explosions().size(), 0, "no impact afterwards")
	assert_false(Feedback.is_slow_motion(), "no slow motion afterwards")


func test_level_failed_mid_scene_releases_at_once() -> void:
	_make()
	_start()
	_run_to(impact_s - travel_s + EPS)
	assert_not_null(_scene.ram(), "the Ram is in flight")
	Events.level_failed.emit(&"convoy")
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE)
	assert_false(_player.is_scripted_locked(), "the lock is released")
	assert_false(_spawner.hold_enemy_fire, "the fire hold is released")
	assert_eq(_count_lines("[INFO][scene] Tarek's fall: controls released (level failed)"), 1)
	_run_to(impact_s + 1.0)
	assert_eq(_explosions().size(), 0, "a Ram arriving after the outcome plays no impact")


func test_level_failed_in_the_aftermath_releases_at_once() -> void:
	_make()
	_start()
	_run_to(impact_s + EPS)
	Events.level_failed.emit(&"hearts")
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE)
	assert_false(_player.is_scripted_locked())
	assert_false(_spawner.hold_enemy_fire)


func test_an_outcome_before_the_event_changes_nothing() -> void:
	_make()
	Events.level_cleared.emit(2)
	assert_eq(_scene.phase(), TarekFallScene.Phase.IDLE, "still idle")
	assert_eq(_count_lines("[INFO][scene] Tarek's fall: controls released (level cleared)"), 0)


# --- Edge cases --------------------------------------------------------------------------

func test_a_second_event_is_ignored() -> void:
	_make()
	_start()
	_run_to(1.0)
	var point: Vector2 = _scene.intercept_point()
	var clock: float = _scene.elapsed()
	_start()
	assert_eq(_scene.elapsed(), clock, "the clock was not restarted")
	assert_eq(_scene.intercept_point(), point)
	_run_to(impact_s + release_s + 0.5)
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE)
	_start()
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE, "once per attempt")
	assert_eq(_requested.size(), 1, "one line")
	assert_eq(_explosions().size(), 1, "one impact")
	assert_eq(_count_lines("[INFO][scene] Tarek's fall: lock-on, impact in %.2f s" % impact_s), 1, "one start")


func test_no_tarek_does_nothing() -> void:
	_make(true, "")
	_start()
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE, "skipped")
	assert_false(_player.is_scripted_locked(), "Vale not locked")
	assert_false(_spawner.hold_enemy_fire, "fire not held")
	assert_false(_scene.line_visible())
	_scene.step(impact_s + release_s + 1.0)
	assert_eq(_requested, [] as Array[StringName], "no line")
	assert_eq(_enemies.get_child_count(), 0, "no Ram")
	assert_false(Feedback.is_slow_motion(), "no slow motion")
	assert_eq(_count_lines("[INFO][scene] Tarek's fall: no patrolling Tarek; scene skipped"), 1)


func test_ryn_is_not_tarek() -> void:
	_make(true, "ryn")
	_start()
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE, "skipped")
	assert_eq(_tarek.state(), AllyShip.State.PATROL, "Ryn keeps patrolling")
	assert_false(_player.is_scripted_locked())


func test_a_tarek_already_falling_is_not_used() -> void:
	_make()
	_tarek.take_hit()
	_start()
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE, "no patrolling Tarek")
	assert_false(_player.is_scripted_locked())


func test_no_vale_tarek_falls_at_once_and_the_line_plays() -> void:
	_make(false)
	var at: Vector2 = _tarek.global_position
	_start()
	assert_eq(_tarek.state(), AllyShip.State.FALLING, "Tarek falls at once")
	assert_eq(_tarek.global_position, at, "from where he is")
	assert_eq(_requested, [TarekFallScene.CUT_OFF_SEQUENCE] as Array[StringName], "the line is requested")
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE)
	assert_false(_spawner.hold_enemy_fire, "no fire hold")
	_scene.step(impact_s + 1.0)
	assert_eq(_enemies.get_child_count(), 0, "no Ram")
	assert_eq(_requested.size(), 1, "requested once")
	assert_eq(_count_lines("[INFO][scene] Tarek's fall: no Vale; Tarek falls at once"), 1)


func test_a_dead_vale_counts_as_no_vale() -> void:
	_make()
	_player.debug_invincible = false
	_player.apply_damage(99, null)
	assert_true(_player.is_dead(), "fixture: Vale is dead")
	_start()
	assert_eq(_tarek.state(), AllyShip.State.FALLING, "Tarek falls at once")
	assert_false(_player.is_scripted_locked(), "a dead Vale is not locked")
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE)


func test_physics_process_steps_the_clock() -> void:
	_make()
	_start()
	_scene.set_physics_process(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_gt(_scene.elapsed(), 0.0, "the physics tick advances the clock")
