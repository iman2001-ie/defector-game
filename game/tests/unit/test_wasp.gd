extends GutTest
## Wasp state machine (Story 2.4): entry, hold, telegraph, dive, off-screen
## re-entry, sandbox hold, tuning reads, pause. Driven through step(delta)
## with physics processing off, so every move is deterministic.

const WASP_SCENE: PackedScene = preload("res://entities/enemies/wasp/wasp.tscn")
const WASP_SCRIPT_PATH: String = "res://entities/enemies/wasp/wasp.gd"
const DT: float = 1.0 / 60.0

var _lines: Array[String] = []
var _player: Node2D = null


func before_each() -> void:
	_lines.clear()
	Log.sink = _capture


func after_each() -> void:
	Log.sink = Callable()
	Config.load_data()
	PauseArbiter.clear()
	Feedback.reset()
	_player = null


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _warns() -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.begins_with("[WARN][spawn]"):
			out.append(line)
	return out


func _make(params: Dictionary, manual: bool = true) -> Wasp:
	var wasp: Wasp = WASP_SCENE.instantiate() as Wasp
	wasp.setup(params)
	add_child_autofree(wasp)
	if manual:
		wasp.set_physics_process(false)
	watch_signals(wasp)
	return wasp


func _make_player(pos: Vector2) -> Node2D:
	_player = Node2D.new()
	_player.add_to_group(&"player")
	add_child_autofree(_player)
	_player.global_position = pos
	return _player


## Steps until the Wasp reaches `target_state` or `max_s` elapses; returns seconds stepped.
func _step_until(wasp: Wasp, target_state: Wasp.State, max_s: float) -> float:
	var t: float = 0.0
	while wasp.state() != target_state and t < max_s:
		wasp.step(DT)
		t += DT
	return t


func _hull(wasp: Wasp) -> CanvasItem:
	return wasp.get_node("Hull") as CanvasItem


# --- Entry --------------------------------------------------------------------

func test_top_entry_flies_to_the_slot_and_holds() -> void:
	var wasp: Wasp = _make({"position": Vector2(720, 160), "slot": Vector2(720, 160), "entry": &"top"})
	assert_eq(wasp.global_position, Vector2(720, -32), "starts above the top edge")
	assert_eq(wasp.state(), Wasp.State.ENTER)
	assert_eq(wasp.formation_slot(), Vector2(720, 160))
	wasp.step(0.1)
	assert_almost_eq(wasp.global_position.y, -32.0 + 35.0, 0.001, "350 px/s")
	assert_eq(wasp.global_position.x, 720.0)
	var t: float = _step_until(wasp, Wasp.State.HOLD, 2.0)
	assert_eq(wasp.state(), Wasp.State.HOLD)
	assert_almost_eq(t + 0.1, 192.0 / 350.0, DT * 1.5, "arrives after distance / entry speed")
	assert_eq(wasp.global_position, Vector2(720, 160))
	assert_true(wasp.is_holding())
	for i: int in 60:
		wasp.step(DT)
	assert_eq(wasp.global_position, Vector2(720, 160), "stays put")
	assert_eq(_warns().size(), 0)


func test_side_entry_starts_on_the_nearer_side() -> void:
	var left: Wasp = _make({"position": Vector2(400, 280), "slot": Vector2(400, 280), "entry": &"sides"})
	assert_eq(left.global_position, Vector2(-32, 280))
	var right: Wasp = _make({"position": Vector2(1200, 160), "slot": Vector2(1200, 160), "entry": &"sides"})
	assert_eq(right.global_position, Vector2(1952, 160))
	_step_until(left, Wasp.State.HOLD, 3.0)
	assert_eq(left.global_position, Vector2(400, 280), "left Wasp holds its slot")
	assert_eq(_warns().size(), 0)


## Story 7.4: a boss-launched Wasp's first ENTER starts at `launch_from` (the
## core centre); its re-entry after a dive still comes from the top.
func test_launch_from_starts_the_first_entry_there_and_reaches_the_slot() -> void:
	var from: Vector2 = Vector2(960, 294)
	var wasp: Wasp = _make({"slot": Vector2(640, 370), "launch_from": from})
	assert_eq(wasp.state(), Wasp.State.ENTER)
	assert_eq(wasp.global_position, from, "starts at launch_from")
	assert_eq(wasp.formation_slot(), Vector2(640, 370))
	wasp.step(0.1)
	var expected: Vector2 = from.move_toward(Vector2(640, 370), 35.0)
	assert_almost_eq(wasp.global_position.x, expected.x, 0.001, "flies toward the slot at entry speed")
	assert_almost_eq(wasp.global_position.y, expected.y, 0.001)
	_step_until(wasp, Wasp.State.HOLD, 3.0)
	assert_eq(wasp.state(), Wasp.State.HOLD)
	assert_eq(wasp.global_position, Vector2(640, 370), "holds its slot")
	wasp.start_dive()
	_step_until(wasp, Wasp.State.DIVE, 1.0)
	_step_until(wasp, Wasp.State.ENTER, 5.0)
	assert_eq(wasp.state(), Wasp.State.ENTER, "re-entering after the dive")
	assert_eq(wasp.global_position, Vector2(640, -32), "the re-entry comes from the top, not launch_from")
	assert_eq(_warns().size(), 0)


func test_without_launch_from_the_entry_start_is_unchanged() -> void:
	var top: Wasp = _make({"position": Vector2(640, 370), "slot": Vector2(640, 370), "entry": &"top"})
	assert_eq(top.global_position, Vector2(640, -32), "top entry as before")
	var sides: Wasp = _make({"position": Vector2(400, 280), "slot": Vector2(400, 280), "entry": &"sides"})
	assert_eq(sides.global_position, Vector2(-32, 280), "side entry as before")


func test_launch_from_without_a_slot_is_ignored() -> void:
	var wasp: Wasp = _make({"position": Vector2(500, 300), "launch_from": Vector2(960, 294)})
	assert_eq(wasp.state(), Wasp.State.HOLD, "a slotless Wasp still holds")
	assert_eq(wasp.global_position, Vector2(500, 300))


func test_unknown_entry_warns_and_uses_top() -> void:
	var wasp: Wasp = _make({"position": Vector2(720, 160), "slot": Vector2(720, 160), "entry": &"spiral"})
	assert_eq(wasp.global_position, Vector2(720, -32))
	assert_eq(wasp.state(), Wasp.State.ENTER)
	assert_eq(_warns().size(), 1, "one WARN")
	assert_string_contains(_warns()[0], "spiral")


func test_slot_below_the_zone_is_clamped() -> void:
	var wasp: Wasp = _make({"position": Vector2(720, 520), "slot": Vector2(720, 520), "entry": &"top"})
	assert_eq(wasp.formation_slot(), Vector2(720, 432))
	assert_eq(_warns().size(), 1, "one WARN")
	_step_until(wasp, Wasp.State.HOLD, 3.0)
	assert_eq(wasp.global_position, Vector2(720, 432), "holds at the zone edge")


func test_sandbox_wasp_holds_its_position() -> void:
	var wasp: Wasp = _make({"position": Vector2(500, 300)}, false)
	assert_eq(wasp.state(), Wasp.State.HOLD)
	assert_eq(wasp.global_position, Vector2(500, 300))
	await wait_physics_frames(5)
	assert_eq(wasp.global_position, Vector2(500, 300), "never moves on its own")
	assert_eq(wasp.state(), Wasp.State.HOLD)


# --- Telegraph and dive -------------------------------------------------------

func _holding(slot: Vector2 = Vector2(720, 160)) -> Wasp:
	var wasp: Wasp = _make({"position": slot, "slot": slot, "entry": &"top"})
	_step_until(wasp, Wasp.State.HOLD, 3.0)
	return wasp


func test_telegraph_flashes_without_moving_then_dives() -> void:
	_make_player(Vector2(960, 900))
	var wasp: Wasp = _holding()
	var hull: CanvasItem = _hull(wasp)
	assert_eq(hull.self_modulate, Color.WHITE)
	wasp.start_dive()
	assert_eq(wasp.state(), Wasp.State.TELEGRAPH)
	assert_true(wasp.is_flashing(), "wings flash on entry")
	var e: float = Config.num("enemies.wasp.wing_flash_energy")
	assert_eq(hull.self_modulate, Color(e, e, e))
	var saw_off: bool = false
	var toggles: int = 0
	var was_flashing: bool = true
	var t: float = 0.0
	while wasp.state() == Wasp.State.TELEGRAPH and t < 1.0:
		wasp.step(DT)
		t += DT
		if wasp.state() == Wasp.State.TELEGRAPH:
			assert_eq(wasp.global_position, Vector2(720, 160), "no movement while telegraphing")
			if wasp.is_flashing() != was_flashing:
				toggles += 1
				was_flashing = wasp.is_flashing()
			if not wasp.is_flashing():
				saw_off = true
				assert_eq(hull.self_modulate, Color.WHITE)
	assert_true(saw_off, "the flash blinks")
	var expected_toggles: float = Config.num("enemies.wasp.telegraph_s") * Config.num("enemies.wasp.wing_flash_hz") * 2.0
	assert_between(float(toggles), expected_toggles - 1.0, expected_toggles + 1.0, "blinks at wing_flash_hz")
	assert_almost_eq(t, Config.num("enemies.wasp.telegraph_s"), DT * 1.5, "telegraph lasts telegraph_s")
	assert_eq(wasp.state(), Wasp.State.DIVE)
	assert_false(wasp.is_flashing())
	assert_eq(hull.self_modulate, Color.WHITE, "flash restored on leaving")


func test_dive_heads_for_the_player_at_dive_speed() -> void:
	var player: Node2D = _make_player(Vector2(960, 900))
	var wasp: Wasp = _holding()
	wasp.start_dive()
	_step_until(wasp, Wasp.State.DIVE, 1.0)
	var start: Vector2 = wasp.global_position
	var expected_dir: Vector2 = (Vector2(960, 900) - start).normalized()
	player.global_position = Vector2(100, 900)
	wasp.step(0.1)
	var moved: Vector2 = wasp.global_position - start
	assert_almost_eq(moved.length(), Config.num("enemies.wasp.dive_speed_px_s") * 0.1, 0.01, "dive_speed_px_s")
	assert_almost_eq(moved.normalized().dot(expected_dir), 1.0, 0.0001, "snapshotted direction")


func test_dive_without_a_player_goes_straight_down() -> void:
	var wasp: Wasp = _holding()
	wasp.start_dive()
	_step_until(wasp, Wasp.State.DIVE, 1.0)
	var start: Vector2 = wasp.global_position
	wasp.step(0.1)
	assert_almost_eq(wasp.global_position.x, start.x, 0.0001)
	assert_almost_eq(wasp.global_position.y, start.y + Config.num("enemies.wasp.dive_speed_px_s") * 0.1, 0.01, "dive_speed_px_s, straight down")


func test_start_dive_ignored_outside_hold() -> void:
	var wasp: Wasp = _make({"position": Vector2(720, 160), "slot": Vector2(720, 160), "entry": &"top"})
	wasp.start_dive()
	assert_eq(wasp.state(), Wasp.State.ENTER, "ignored while entering")
	_step_until(wasp, Wasp.State.HOLD, 3.0)
	wasp.start_dive()
	wasp.step(DT)
	wasp.start_dive()
	assert_eq(wasp.state(), Wasp.State.TELEGRAPH, "ignored while telegraphing")
	_step_until(wasp, Wasp.State.DIVE, 1.0)
	wasp.start_dive()
	assert_eq(wasp.state(), Wasp.State.DIVE, "ignored while diving")


func test_dead_wasp_ignores_start_dive() -> void:
	var wasp: Wasp = _holding()
	wasp.apply_damage(wasp.hp, null)
	wasp.start_dive()
	assert_eq(wasp.state(), Wasp.State.HOLD)


# --- Off-screen re-entry ------------------------------------------------------

func test_bottom_exit_reenters_from_the_top_without_resolving() -> void:
	var wasp: Wasp = _holding(Vector2(720, 160))
	wasp.start_dive()
	_step_until(wasp, Wasp.State.DIVE, 1.0)
	_step_until(wasp, Wasp.State.ENTER, 5.0)
	assert_eq(wasp.state(), Wasp.State.ENTER, "re-entering")
	assert_eq(wasp.global_position, Vector2(720, -32), "from above the slot")
	_step_until(wasp, Wasp.State.HOLD, 3.0)
	assert_eq(wasp.global_position, Vector2(720, 160), "back on its slot")
	assert_signal_not_emitted(wasp, "resolved")
	assert_false(wasp.is_dead())


func test_side_exit_reenters_from_the_top() -> void:
	_make_player(Vector2(1900, 600))
	var wasp: Wasp = _holding(Vector2(1680, 400))
	wasp.start_dive()
	_step_until(wasp, Wasp.State.DIVE, 1.0)
	var last: Vector2 = wasp.global_position
	var t: float = 0.0
	while wasp.state() == Wasp.State.DIVE and t < 10.0:
		last = wasp.global_position
		wasp.step(DT)
		t += DT
	assert_eq(wasp.state(), Wasp.State.ENTER, "left the screen")
	assert_gt(last.x, 1900.0, "left through the right edge")
	assert_lt(last.y, 1000.0, "well before the bottom")
	assert_eq(wasp.global_position, Vector2(1680, -32))
	assert_signal_not_emitted(wasp, "resolved")


func test_sides_wasp_reenters_from_the_top() -> void:
	var wasp: Wasp = _make({"position": Vector2(400, 280), "slot": Vector2(400, 280), "entry": &"sides"})
	_step_until(wasp, Wasp.State.HOLD, 3.0)
	wasp.start_dive()
	_step_until(wasp, Wasp.State.DIVE, 1.0)
	_step_until(wasp, Wasp.State.ENTER, 5.0)
	assert_eq(wasp.global_position, Vector2(400, -32), "re-entry is always from the top")


# --- Tuning -------------------------------------------------------------------

func test_speeds_and_telegraph_come_from_tuning() -> void:
	var wasp_tuning: Dictionary = (Config.tuning["enemies"] as Dictionary)["wasp"] as Dictionary
	wasp_tuning["entry_speed_px_s"] = 100.0
	wasp_tuning["dive_speed_px_s"] = 200.0
	wasp_tuning["telegraph_s"] = 1.0
	wasp_tuning["zone_height_ratio"] = 0.2
	var wasp: Wasp = _make({"position": Vector2(720, 160), "slot": Vector2(720, 160), "entry": &"top"})
	wasp.step(0.1)
	assert_almost_eq(wasp.global_position.y, -32.0 + 10.0, 0.001, "entry_speed_px_s")
	_step_until(wasp, Wasp.State.HOLD, 5.0)
	wasp.start_dive()
	var t: float = _step_until(wasp, Wasp.State.DIVE, 3.0)
	assert_almost_eq(t, 1.0, DT * 1.5, "telegraph_s")
	var start: Vector2 = wasp.global_position
	wasp.step(0.1)
	assert_almost_eq((wasp.global_position - start).length(), 20.0, 0.01, "dive_speed_px_s")
	var low: Wasp = _make({"position": Vector2(720, 280), "slot": Vector2(720, 280), "entry": &"top"})
	assert_eq(low.formation_slot().y, 216.0, "zone_height_ratio")


func test_state_is_assigned_only_in_enter_state() -> void:
	var source: String = FileAccess.get_file_as_string(WASP_SCRIPT_PATH)
	var assignments: RegEx = RegEx.create_from_string("(?<!\\w)_state\\s*=(?!=)")
	assert_eq(assignments.search_all(source).size(), 1, "exactly one `_state =`")
	var enter: int = source.find("func _enter_state(")
	var hit: RegExMatch = assignments.search(source)
	assert_true(enter >= 0 and hit != null and hit.get_start() > enter, "inside _enter_state")


# --- Pause --------------------------------------------------------------------

func test_paused_tree_freezes_the_wasp() -> void:
	var wasp: Wasp = _make({"position": Vector2(720, 160), "slot": Vector2(720, 160), "entry": &"top"}, false)
	assert_eq(wasp.process_mode, Node.PROCESS_MODE_INHERIT)
	PauseArbiter.push(&"menu")
	var before: Vector2 = wasp.global_position
	assert_false(wasp.can_process(), "paused with the tree")
	await get_tree().create_timer(0.2, true, true).timeout
	assert_eq(wasp.global_position, before, "no movement while paused")
	PauseArbiter.pop(&"menu")
	await wait_physics_frames(3)
	assert_gt(wasp.global_position.y, before.y, "moves again after resume")
