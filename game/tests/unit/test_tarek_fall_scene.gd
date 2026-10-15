extends GutTest
## TarekFallScene (Story 6.5, reworked in Epic 7 playtests D and J): the
## director of Tarek's fall, driven through step(delta) with every physics tick
## off (the scene, the Player, Tarek and the Ram). On the tarek_fall story event
## it locks Vale, holds enemy fire and shows the lock-on line (LOCK); at
## warn_after_s it requests the warning story beat (WARNING) and waits for its
## `finished`; then Tarek dashes to intercept_offset_px above Vale and the
## impact clock starts (RUNNING): the Ram launches at impact_s - ram_travel_s,
## the slow motion starts at impact_s - slowmo.lead_s and the impact (Tarek
## FALLING, the music fading out, the burn sound) plays when the Ram arrives
## (AFTERMATH). aftermath_after_s later it requests the down beat (CALLOUT),
## and release_after_s after that beat's `finished` it releases Vale and the
## enemy fire (SETTLE, then DONE), or at once on a level outcome. No
## patrolling Tarek: nothing happens. No Vale: Tarek falls at once and both
## beats are requested. The test plays the comms channel's part by emitting
## Events.comms_sequence_finished. Feedback.reset() in after_each so no slow
## motion or hit-stop leaks into other suites. DW-110: freeing the director
## stops the burn and nothing else; after_each stops any burn a test leaves.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")
const EVENT: StringName = &"tarek_fall"
const VALE_AT: Vector2 = Vector2(900, 900)
const DT: float = 1.0 / 60.0
## A hair, for "just before" / "just after" a timeline mark.
const EPS: float = 0.001
const WARNING: StringName = TarekFallScene.WARNING_SEQUENCE
const DOWN: StringName = TarekFallScene.DOWN_SEQUENCE

var _world: Node2D
var _effects: Node2D
var _enemies: Node2D
var _spawner: Spawner
var _scene: TarekFallScene
var _player: Player
var _tarek: AllyShip
var _requested: Array[StringName] = []
var _lines: Array[String] = []
## Test time since the current phase clock started: reset with each beat.
var _clock: float = 0.0

var warn_s: float
var impact_s: float
var travel_s: float
var lead_s: float
var aftermath_s: float
var release_s: float
var offset_px: float


func before_each() -> void:
	_requested.clear()
	_lines.clear()
	_clock = 0.0
	Log.sink = _capture
	Events.comms_sequence_requested.connect(_on_comms_requested)
	warn_s = Config.num("story.tarek_fall.warn_after_s")
	impact_s = Config.num("story.tarek_fall.impact_s")
	travel_s = Config.num("story.tarek_fall.ram_travel_s")
	lead_s = Config.num("story.tarek_fall.slowmo.lead_s")
	aftermath_s = Config.num("story.tarek_fall.aftermath_after_s")
	release_s = Config.num("story.tarek_fall.release_after_s")
	offset_px = Config.num("story.tarek_fall.intercept_offset_px")
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
	Audio.stop_music(0.0)
	# No 4.6 s burn may leak into other suites (DW-110).
	Audio.stop_sfx(TarekFallScene.BURN_SFX)
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


## Plays the comms channel's part: the story beat `id` was clicked through.
func _finish(id: StringName) -> void:
	Events.comms_sequence_finished.emit(id)


## Starts the scene and runs it through the warning beat: the dash starts and
## the test clock restarts with the impact clock.
func _to_dash() -> void:
	_start()
	_run_to(warn_s + EPS)
	_finish(WARNING)
	_clock = 0.0


## Runs the scene to just after the impact (the AFTERMATH clock restarts).
func _to_impact() -> void:
	_to_dash()
	_run_to(impact_s + EPS)
	_clock = _scene.elapsed()


## Runs the scene through the down beat (the SETTLE clock restarts).
func _to_settle() -> void:
	_to_impact()
	_run_to(aftermath_s + EPS)
	_finish(DOWN)
	_clock = 0.0


# --- Start ----------------------------------------------------------------------------

func test_tuning_is_cached() -> void:
	_make()
	assert_eq(_scene.warn_after_s, warn_s)
	assert_eq(_scene.impact_s, impact_s)
	assert_eq(_scene.ram_travel_s, travel_s)
	assert_eq(_scene.ram_scale, Config.num("story.tarek_fall.ram_scale"))
	assert_eq(_scene.ram_start_y, Config.num("story.tarek_fall.ram_start_y"))
	assert_eq(_scene.intercept_offset_px, offset_px)
	assert_eq(_scene.aftermath_after_s, aftermath_s)
	assert_eq(_scene.release_after_s, release_s)
	assert_eq(_scene.burn_volume_db, Config.num("story.tarek_fall.burn_volume_db"))
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


func test_start_locks_vale_holds_fire_and_shows_the_lock_on() -> void:
	_make()
	_start()
	assert_eq(_scene.phase(), TarekFallScene.Phase.LOCK)
	assert_true(_player.is_scripted_locked(), "Vale's controls are locked")
	assert_true(_player.is_invulnerable(), "Vale can't be hurt")
	assert_true(_spawner.hold_enemy_fire, "enemies hold their fire")
	assert_true(_scene.line_visible(), "the lock-on line shows")
	var point: Vector2 = VALE_AT + Vector2(0.0, -offset_px)
	assert_eq(_scene.intercept_point(), point, "intercept_offset_px above Vale")
	assert_eq(_tarek.state(), AllyShip.State.PATROL, "Tarek waits for his warning before he dashes")
	assert_true(_tarek.hold_fire, "and stops shooting at the lock-on")
	assert_eq(_requested, [] as Array[StringName], "no beat at once")
	assert_null(_scene.ram(), "no Ram yet")
	assert_false(Feedback.is_slow_motion(), "no slow motion yet")
	assert_eq(_count_lines("[INFO][scene] Tarek's fall: lock-on, warning in %.2f s" % warn_s), 1)


# --- The warning beat --------------------------------------------------------------------

func test_the_warning_is_requested_once_at_warn_after_s() -> void:
	_make()
	_start()
	_run_to(warn_s - EPS)
	assert_eq(_requested, [] as Array[StringName], "not before its time")
	_run_to(warn_s + EPS)
	assert_eq(_requested, [WARNING] as Array[StringName], "the warning beat")
	assert_eq(_scene.phase(), TarekFallScene.Phase.WARNING)
	_run_to(warn_s + 5.0)
	assert_eq(_requested, [WARNING] as Array[StringName], "exactly once, and nothing moves on without its finish")
	assert_eq(_scene.phase(), TarekFallScene.Phase.WARNING, "waiting for the beat")
	assert_eq(_tarek.state(), AllyShip.State.PATROL, "Tarek has not dashed yet")
	assert_null(_scene.ram(), "no Ram while waiting")


func test_the_warning_finishing_sends_tarek_in() -> void:
	_make()
	_to_dash()
	assert_eq(_scene.phase(), TarekFallScene.Phase.RUNNING)
	assert_eq(_scene.elapsed(), 0.0, "the impact clock starts at the dash")
	assert_eq(_tarek.state(), AllyShip.State.APPROACH, "Tarek dashes in")
	assert_eq(_tarek.intercept_point(), _scene.intercept_point(), "to the intercept point")
	assert_true(_scene.line_visible(), "the lock-on line still shows")
	assert_eq(_count_lines("[INFO][scene] Tarek's fall: Tarek dashes in, impact in %.2f s" % impact_s), 1)


func test_other_sequences_finishing_change_nothing() -> void:
	_make()
	_start()
	_finish(WARNING)
	assert_eq(_scene.phase(), TarekFallScene.Phase.LOCK, "a warning finish before its request is ignored")
	_run_to(warn_s + EPS)
	_finish(&"l2_briefing")
	_finish(DOWN)
	assert_eq(_scene.phase(), TarekFallScene.Phase.WARNING, "only the warning's finish moves on")


func test_tarek_reaches_the_point_and_holds() -> void:
	_make()
	_to_dash()
	_run_to(Config.num("allies.fall.approach_s") + DT)
	assert_eq(_tarek.state(), AllyShip.State.HOLD, "holding at the point")
	assert_eq(_tarek.global_position, _scene.intercept_point(), "between Vale and the threat")
	assert_true(_tarek.is_holding())


func test_vale_is_held_against_the_mouse_for_the_whole_scene() -> void:
	_make()
	_to_dash()
	_run_to(impact_s)
	for i: int in 5:
		_player._physics_process(DT)
	assert_eq(_player.global_position, VALE_AT, "held in place")


# --- The Ram, the slow motion and the impact -------------------------------------------

func test_the_ram_launches_at_impact_minus_travel() -> void:
	_make()
	_to_dash()
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
	_to_dash()
	_run_to(impact_s - lead_s - EPS)
	assert_false(Feedback.is_slow_motion(), "not before the lead time")
	_run_to(impact_s - lead_s + EPS)
	assert_true(Feedback.is_slow_motion(), "slow motion before the impact")
	assert_eq(Feedback.slow_motion_scale(), Config.num("story.tarek_fall.slowmo.scale"))
	assert_ne(_tarek.state(), AllyShip.State.FALLING, "Tarek not hit yet")


func test_impact_when_the_ram_arrives() -> void:
	_make()
	Audio.play_music(&"boss")
	_to_dash()
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
	assert_eq(Audio.current_music(), &"", "the music drops out")
	assert_eq(Audio.newest_player().stream, Audio.SFX[TarekFallScene.BURN_SFX], "the burning fall plays")
	assert_eq(_count_lines("[INFO][scene] Tarek's fall: the Ram struck Tarek"), 1)
	assert_true(_player.is_scripted_locked(), "Vale still locked through the slow motion")
	assert_true(_spawner.hold_enemy_fire)
	assert_eq(_requested, [WARNING] as Array[StringName], "the down beat waits for its delay")


func test_without_a_spawner_the_clock_decides_the_impact() -> void:
	_make()
	_scene.spawner = null
	_to_dash()
	_run_to(impact_s - EPS)
	assert_null(_scene.ram(), "no Ram without a Spawner")
	assert_eq(_tarek.state(), AllyShip.State.HOLD)
	_run_to(impact_s + EPS)
	assert_eq(_tarek.state(), AllyShip.State.FALLING, "hit at impact_s")
	assert_eq(_scene.phase(), TarekFallScene.Phase.AFTERMATH)


# --- The down beat and the release -------------------------------------------------------

func test_the_down_beat_is_requested_after_the_aftermath() -> void:
	_make()
	_to_impact()
	_run_to(aftermath_s - EPS)
	assert_eq(_requested, [WARNING] as Array[StringName], "not before its delay")
	_run_to(aftermath_s + EPS)
	assert_eq(_requested, [WARNING, DOWN] as Array[StringName], "the down beat")
	assert_eq(_scene.phase(), TarekFallScene.Phase.CALLOUT)
	_run_to(aftermath_s + 5.0)
	assert_eq(_scene.phase(), TarekFallScene.Phase.CALLOUT, "waiting for the beat")
	assert_true(_player.is_scripted_locked(), "Vale still locked until the beat ends")
	assert_true(_spawner.hold_enemy_fire)


func test_release_after_the_down_beat() -> void:
	_make()
	_to_settle()
	assert_eq(_scene.phase(), TarekFallScene.Phase.SETTLE)
	_run_to(release_s - EPS)
	assert_true(_player.is_scripted_locked(), "still locked just before")
	assert_true(_spawner.hold_enemy_fire)
	_run_to(release_s + 2.0 * EPS)
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE)
	assert_false(_player.is_scripted_locked(), "Vale's controls are back")
	assert_false(_player.is_invulnerable(), "and Vale can be hurt again")
	assert_false(_spawner.hold_enemy_fire, "enemy fire is back")
	assert_false(_scene.line_visible())
	assert_eq(_count_lines("[INFO][scene] Tarek's fall: controls released"), 1)
	_run_to(release_s + 1.0)
	assert_eq(_requested, [WARNING, DOWN] as Array[StringName], "nothing more")
	assert_eq(_explosions().size(), 1, "one impact only")


func test_level_cleared_during_the_warning_releases_at_once() -> void:
	_make()
	_start()
	_run_to(warn_s + EPS)
	Events.level_cleared.emit(2)
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE)
	assert_false(_player.is_scripted_locked(), "the lock is released")
	assert_false(_spawner.hold_enemy_fire, "the fire hold is released")
	assert_false(_scene.line_visible(), "the lock-on line is gone")
	assert_eq(_count_lines("[INFO][scene] Tarek's fall: controls released (level cleared)"), 1)
	_finish(WARNING)
	assert_eq(_tarek.state(), AllyShip.State.PATROL, "no dash after the outcome")
	_run_to(warn_s + impact_s + 1.0)
	assert_null(_scene.ram(), "no Ram launched afterwards")
	assert_eq(_explosions().size(), 0, "no impact afterwards")
	assert_false(Feedback.is_slow_motion(), "no slow motion afterwards")


func test_level_failed_mid_scene_releases_at_once() -> void:
	_make()
	_to_dash()
	_run_to(impact_s - travel_s + EPS)
	assert_not_null(_scene.ram(), "the Ram is in flight")
	Events.level_failed.emit(&"convoy")
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE)
	assert_false(_player.is_scripted_locked(), "the lock is released")
	assert_false(_spawner.hold_enemy_fire, "the fire hold is released")
	assert_eq(_count_lines("[INFO][scene] Tarek's fall: controls released (level failed)"), 1)
	_run_to(impact_s + 1.0)
	assert_eq(_explosions().size(), 0, "a Ram arriving after the outcome plays no impact")


func test_level_failed_in_the_aftermath_releases_and_requests_nothing_more() -> void:
	_make()
	_to_impact()
	Events.level_failed.emit(&"hearts")
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE)
	assert_false(_player.is_scripted_locked())
	assert_false(_spawner.hold_enemy_fire)
	_run_to(aftermath_s + 1.0)
	assert_eq(_requested, [WARNING] as Array[StringName], "no down beat after the outcome")


func test_an_outcome_before_the_event_changes_nothing() -> void:
	_make()
	Events.level_cleared.emit(2)
	assert_eq(_scene.phase(), TarekFallScene.Phase.IDLE, "still idle")
	assert_eq(_count_lines("[INFO][scene] Tarek's fall: controls released (level cleared)"), 0)


# --- Edge cases --------------------------------------------------------------------------

func test_a_second_event_is_ignored() -> void:
	_make()
	_start()
	_run_to(0.5)
	var point: Vector2 = _scene.intercept_point()
	var clock: float = _scene.elapsed()
	_start()
	assert_eq(_scene.elapsed(), clock, "the clock was not restarted")
	assert_eq(_scene.intercept_point(), point)
	_run_to(warn_s + EPS)
	_finish(WARNING)
	_clock = 0.0
	_run_to(impact_s + aftermath_s + 0.5)
	_finish(DOWN)
	_clock = 0.0
	_run_to(release_s + 0.5)
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE)
	_start()
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE, "once per attempt")
	assert_eq(_requested, [WARNING, DOWN] as Array[StringName], "one of each beat")
	assert_eq(_explosions().size(), 1, "one impact")
	assert_eq(_count_lines("[INFO][scene] Tarek's fall: lock-on, warning in %.2f s" % warn_s), 1, "one start")


func test_no_tarek_does_nothing() -> void:
	_make(true, "")
	_start()
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE, "skipped")
	assert_false(_player.is_scripted_locked(), "Vale not locked")
	assert_false(_spawner.hold_enemy_fire, "fire not held")
	assert_false(_scene.line_visible())
	_scene.step(warn_s + impact_s + 1.0)
	assert_eq(_requested, [] as Array[StringName], "no beat")
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


func test_no_vale_tarek_falls_at_once_and_both_beats_play() -> void:
	_make(false)
	Audio.play_music(&"boss")
	var at: Vector2 = _tarek.global_position
	_start()
	assert_eq(_tarek.state(), AllyShip.State.FALLING, "Tarek falls at once")
	assert_eq(_tarek.global_position, at, "from where he is")
	assert_eq(_requested, [WARNING, DOWN] as Array[StringName], "both beats, in order")
	assert_eq(_scene.phase(), TarekFallScene.Phase.DONE)
	assert_false(_spawner.hold_enemy_fire, "no fire hold")
	assert_eq(Audio.current_music(), &"", "the music drops out")
	assert_eq(Audio.newest_player().stream, Audio.SFX[TarekFallScene.BURN_SFX], "the burning fall plays")
	_scene.step(impact_s + 1.0)
	assert_eq(_enemies.get_child_count(), 0, "no Ram")
	assert_eq(_requested.size(), 2, "requested once each")
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


# --- Leaving the tree (DW-110) -------------------------------------------------------------

## Stops and frees every combat-pool player, so the burn's player can't be
## stolen by the pool's oldest-first rule in these tests.
func _free_combat_pool() -> void:
	var skip: Array[AudioStreamPlayer] = Audio.comms_players()
	skip.append_array(Audio.music_players())
	for child: Node in Audio.get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		if player != null and not skip.has(player):
			player.stop()
			player.finished.emit()


## The Audio players still playing Tarek's burn.
func _burns() -> int:
	var n: int = 0
	for child: Node in Audio.get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		if player != null and player.playing and player.stream == Audio.SFX[TarekFallScene.BURN_SFX]:
			n += 1
	return n


## A retry or quit frees the level, and the director with it.
func _free_scene() -> void:
	_scene.free()
	_scene = null


func test_leaving_the_tree_after_the_impact_stops_the_burn() -> void:
	_free_combat_pool()
	_make()
	_to_impact()
	assert_eq(_burns(), 1, "fixture: the burn plays after the impact")
	var zap: AudioStreamPlayer = Audio.play_sfx(&"laser_zap")
	assert_not_null(zap)
	_free_scene()
	assert_eq(_burns(), 0, "the burn stops with the scene")
	if zap != null:
		assert_true(zap.playing, "other combat sounds keep playing")


func test_leaving_the_tree_after_the_no_vale_fall_stops_the_burn() -> void:
	_free_combat_pool()
	_make(false)
	_start()
	assert_eq(_burns(), 1, "fixture: the burn plays at once")
	var zap: AudioStreamPlayer = Audio.play_sfx(&"laser_zap")
	assert_not_null(zap)
	_free_scene()
	assert_eq(_burns(), 0, "the burn stops with the scene")
	if zap != null:
		assert_true(zap.playing, "other combat sounds keep playing")


func test_the_burn_still_plays_through_the_down_beat() -> void:
	_free_combat_pool()
	_make()
	_to_impact()
	_run_to(aftermath_s + EPS)
	assert_eq(_requested, [WARNING, DOWN] as Array[StringName], "the down beat is requested")
	assert_eq(_burns(), 1, "the burn still plays while the scene is in the tree")


func test_physics_process_steps_the_clock() -> void:
	_make()
	_start()
	_scene.set_physics_process(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_gt(_scene.elapsed(), 0.0, "the physics tick advances the clock")
