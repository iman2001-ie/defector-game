extends GutTest
## WaspDiveClock (Story 2.4): one holding Wasp dives per random deadline in
## [dive_interval_s.min, max]; entering, diving, telegraphing and dead Wasps are
## never picked; it freezes with the paused tree.

const WASP_SCENE: PackedScene = preload("res://entities/enemies/wasp/wasp.tscn")
const DT: float = 1.0 / 60.0

var _clock: WaspDiveClock = null
var _min_s: float = 0.0
var _max_s: float = 0.0


func before_each() -> void:
	_min_s = Config.num("enemies.wasp.dive_interval_s.min")
	_max_s = Config.num("enemies.wasp.dive_interval_s.max")


func after_each() -> void:
	PauseArbiter.clear()
	Feedback.reset()
	_clock = null


func _make_clock(seed_value: int = 11, manual: bool = true) -> WaspDiveClock:
	_clock = WaspDiveClock.new()
	_clock.rng.seed = seed_value
	add_child_autofree(_clock)
	if manual:
		_clock.set_physics_process(false)
	return _clock


func _wasp(slot: Vector2) -> Wasp:
	var wasp: Wasp = WASP_SCENE.instantiate() as Wasp
	wasp.setup({"position": slot, "slot": slot, "entry": &"top"})
	add_child_autofree(wasp)
	wasp.set_physics_process(false)
	return wasp


func _holding_wasp(slot: Vector2) -> Wasp:
	var wasp: Wasp = _wasp(slot)
	var t: float = 0.0
	while not wasp.is_holding() and t < 3.0:
		wasp.step(DT)
		t += DT
	return wasp


## Steps the clock just past its current deadline.
func _reach_deadline() -> void:
	_clock.step(_clock.time_left() + 0.001)


func _telegraphing(wasps: Array[Wasp]) -> Array[Wasp]:
	var out: Array[Wasp] = []
	for wasp: Wasp in wasps:
		if wasp.state() == Wasp.State.TELEGRAPH:
			out.append(wasp)
	return out


func test_first_deadline_is_within_the_interval() -> void:
	_make_clock()
	assert_between(_clock.time_left(), _min_s, _max_s)
	assert_eq(_clock.process_mode, Node.PROCESS_MODE_INHERIT, "freezes with the game")


func test_deadline_picks_exactly_one_holding_wasp() -> void:
	var holding: Array[Wasp] = [
		_holding_wasp(Vector2(560, 160)), _holding_wasp(Vector2(720, 160)), _holding_wasp(Vector2(880, 160)),
	]
	var entering: Wasp = _wasp(Vector2(1040, 160))
	_make_clock()
	_clock.step(_clock.time_left() - 0.01)
	assert_eq(_telegraphing(holding).size(), 0, "nothing before the deadline")
	_clock.step(0.02)
	assert_eq(_telegraphing(holding).size(), 1, "exactly one holding Wasp telegraphs")
	assert_eq(entering.state(), Wasp.State.ENTER, "the entering Wasp is never picked")
	assert_between(_clock.time_left(), _min_s, _max_s, "next deadline in [min, max]")


func test_deadlines_stay_within_the_interval() -> void:
	_make_clock(3)
	for i: int in 50:
		assert_between(_clock.time_left(), _min_s, _max_s, "deadline %d" % i)
		_reach_deadline()


func test_no_holding_wasp_just_reschedules() -> void:
	var entering: Wasp = _wasp(Vector2(720, 160))
	_make_clock()
	_reach_deadline()
	assert_eq(entering.state(), Wasp.State.ENTER, "untouched")
	assert_between(_clock.time_left(), _min_s, _max_s, "rescheduled")


func test_dead_and_busy_wasps_are_never_picked() -> void:
	var dead: Wasp = _holding_wasp(Vector2(560, 160))
	var diving: Wasp = _holding_wasp(Vector2(720, 160))
	var target: Wasp = _holding_wasp(Vector2(880, 160))
	var entering: Wasp = _wasp(Vector2(1040, 160))
	diving.start_dive()
	var t: float = 0.0
	while diving.state() != Wasp.State.DIVE and t < 3.0:
		diving.step(DT)
		t += DT
	assert_eq(diving.state(), Wasp.State.DIVE)
	dead.apply_damage(dead.hp, null)
	assert_true(dead.is_dead())
	_make_clock()
	_reach_deadline()
	assert_eq(target.state(), Wasp.State.TELEGRAPH, "the first deadline picks the only holding, living Wasp")
	assert_eq(diving.state(), Wasp.State.DIVE)
	assert_eq(entering.state(), Wasp.State.ENTER)


func test_same_seed_same_picks() -> void:
	var wasps: Array[Wasp] = [
		_holding_wasp(Vector2(560, 160)), _holding_wasp(Vector2(720, 160)), _holding_wasp(Vector2(880, 160)),
	]
	_make_clock(42)
	var first_deadline: float = _clock.time_left()
	_reach_deadline()
	var picked: Wasp = _telegraphing(wasps)[0]
	var check: RandomNumberGenerator = RandomNumberGenerator.new()
	check.seed = 42
	assert_almost_eq(first_deadline, check.randf_range(_min_s, _max_s), 0.000001, "seeded interval")
	assert_eq(picked, wasps[check.randi_range(0, 2)], "seeded pick")


func test_paused_tree_freezes_the_clock() -> void:
	_make_clock(5, false)
	PauseArbiter.push(&"menu")
	var before: float = _clock.time_left()
	assert_false(_clock.can_process(), "paused with the tree")
	await get_tree().create_timer(0.2, true, true).timeout
	assert_eq(_clock.time_left(), before, "no countdown while paused")
	PauseArbiter.pop(&"menu")
	await wait_physics_frames(3)
	assert_lt(_clock.time_left(), before, "counts down after resume")
