extends GutTest
## HintPill (Story 5.8): the centre-low control-hint pill. Unit tests on a bare
## pill driven only through Events (hint_requested, energy_changed,
## player_moved, player_action). GameState.shown_hints is reset around every
## test, and short fade / show times are set in tuning where a test waits.

const THEME_PATH: String = "res://ui/theme/defector_theme.tres"
const KEY_GOLD: Color = Color(1, 0.823529, 0.247059, 1)
const TEXT_ICE: Color = Color(0.909804, 0.956863, 1, 1)

var _lines: Array[String] = []


func before_each() -> void:
	GameState.shown_hints.clear()
	_lines.clear()
	Log.sink = _capture


func after_each() -> void:
	Log.sink = Callable()
	GameState.shown_hints.clear()
	PauseArbiter.clear()
	Config.load_data()


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _lines_containing(text: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.contains(text):
			out.append(line)
	return out


## Short fades (and optionally a short show time) so the waits stay fast.
func _fast(show_s: float = 5.0) -> void:
	var pill: Dictionary = (Config.tuning["ui"] as Dictionary)["hint_pill"] as Dictionary
	pill["fade_in_s"] = 0.05
	pill["fade_out_s"] = 0.05
	pill["show_s"] = show_s


func _make() -> HintPill:
	var pill: HintPill = HintPill.new()
	pill.theme = load(THEME_PATH) as Theme
	add_child_autofree(pill)
	return pill


## Waits until the pill's current hint has faded out (real frames, unpaused).
func _wait_faded(pill: HintPill, max_s: float = 1.0) -> void:
	var end_ms: int = Time.get_ticks_msec() + int(max_s * 1000.0)
	while pill.is_fading() and Time.get_ticks_msec() < end_ms:
		await wait_process_frames(1)


# --- Shape --------------------------------------------------------------------------

func test_init_modes_and_mouse_transparency() -> void:
	var pill: HintPill = _make()
	assert_eq(pill.process_mode, Node.PROCESS_MODE_PAUSABLE)
	assert_eq(pill.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var controls: int = 0
	for child: Node in pill.find_children("*", "Control", true, false):
		controls += 1
		assert_eq((child as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s ignores the mouse" % child.name)
	assert_eq(controls, 3, "a Panel and two Labels")
	assert_false(pill.visible, "hidden at start")
	assert_eq(pill.showing_hint(), &"")


func test_tuning_is_cached() -> void:
	var pill: HintPill = _make()
	assert_eq(pill.center_y, 560.0)
	assert_eq(pill.pill_h, 52.0)
	assert_eq(pill.padding_px, 24.0)
	assert_eq(pill.gap_px, 12.0)
	assert_almost_eq(pill.fade_in_s, 0.2, 0.0001)
	assert_almost_eq(pill.fade_out_s, 0.2, 0.0001)
	assert_almost_eq(pill.show_s, 5.0, 0.0001)
	assert_eq(pill.move_dismiss_px, 150.0)


func test_exact_copy_and_colours_per_hint() -> void:
	var expected: Dictionary = {
		&"move": ["", "MOVE THE MOUSE TO FLY"],
		&"fire": ["[HOLD LMB]", "FIRE"],
		&"missile": ["[RMB]", "MISSILE"],
		&"shield": ["[E]", "SHIELD"],
		&"barrage": ["[Q]", "BARRAGE"],
	}
	for id: StringName in expected:
		assert_eq(HintPill.COPY[id], expected[id], "copy of %s" % id)
	var pill: HintPill = _make()
	Events.hint_requested.emit(&"missile")
	assert_eq(pill.showing_hint(), &"missile")
	assert_eq(pill.key_text(), "[RMB]")
	assert_eq(pill.action_text(), "MISSILE")
	assert_eq(pill.key_color(), KEY_GOLD, "key in energy gold")
	assert_eq(pill.action_color(), TEXT_ICE, "action in the text colour")
	assert_eq(pill.font_px(), 28, "28 px text")


func test_theme_items() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	assert_eq(theme.get_color(&"key", &"HintPill"), KEY_GOLD)
	assert_eq(theme.get_color(&"text", &"HintPill"), TEXT_ICE)
	assert_eq(theme.get_font_size(&"text", &"HintPill"), 28)
	var box: StyleBoxFlat = theme.get_stylebox(&"panel", &"HintPill") as StyleBoxFlat
	assert_not_null(box, "a StyleBoxFlat pill")
	if box == null:
		return
	assert_eq(box.bg_color, Color(0.0392157, 0.0705882, 0.133333, 0.85), "surfaceAlt")
	assert_eq(box.corner_radius_top_left, 26, "fully rounded at 52 px")
	assert_eq(box.corner_radius_bottom_right, 26)
	assert_eq(box.shadow_color, Color(1, 0.823529, 0.247059, 0.35), "soft energy glow")
	assert_eq(box.shadow_size, 6)


func test_rect_is_centred_low_and_52_tall() -> void:
	var pill: HintPill = _make()
	for id: StringName in [&"move_fire", &"missile"]:
		Events.hint_requested.emit(id)
	var rect: Rect2 = pill.get_rect()
	assert_eq(rect.size.y, 52.0, "52 px tall")
	assert_almost_eq(rect.get_center().y, 560.0, 0.001, "vertical centre at 560")
	assert_almost_eq(rect.get_center().x, 960.0, 0.5, "centred horizontally")
	assert_gt(rect.size.x, 2.0 * 24.0, "padding on both sides")
	assert_eq(pill.key_text(), "", "move has no key part")


func test_rect_width_follows_the_text_and_padding() -> void:
	var pill: HintPill = _make()
	Events.hint_requested.emit(&"missile")
	var key: Label = pill.get_node("Panel/Key") as Label
	var action: Label = pill.get_node("Panel/Action") as Label
	assert_almost_eq(key.position.x, 24.0, 0.001, "left padding")
	assert_almost_eq(action.position.x, key.position.x + key.size.x + 12.0, 0.001, "gap between key and action")
	assert_almost_eq(pill.size.x, action.position.x + action.size.x + 24.0, 0.001, "right padding")
	assert_almost_eq(pill.get_rect().get_center().x, 960.0, 0.5)


# --- Move then fire -------------------------------------------------------------------

func test_move_then_fire() -> void:
	_fast()
	var pill: HintPill = _make()
	Events.hint_requested.emit(&"move_fire")
	assert_eq(pill.showing_hint(), &"move")
	assert_eq(pill.action_text(), "MOVE THE MOUSE TO FLY")
	assert_eq(pill.queued(), [&"fire"] as Array[StringName])
	assert_true(pill.visible)
	assert_true(GameState.shown_hints.has(&"move"), "recorded when it starts showing")
	assert_false(GameState.shown_hints.has(&"fire"), "fire is only queued")
	Events.player_action.emit(&"laser")
	assert_false(pill.is_fading(), "a bolt doesn't dismiss the move hint")
	Events.player_moved.emit(100.0)
	assert_false(pill.is_fading(), "100 px is not enough")
	Events.player_moved.emit(49.0)
	assert_false(pill.is_fading(), "149 px is not enough")
	Events.player_moved.emit(1.0)
	assert_true(pill.is_fading(), "150 px of cumulative movement dismisses it")
	assert_false(get_tree().paused, "never pauses")
	await _wait_faded(pill)
	assert_eq(pill.showing_hint(), &"fire", "fire shows after move faded")
	assert_eq(pill.key_text(), "[HOLD LMB]")
	assert_eq(pill.action_text(), "FIRE")
	Events.player_moved.emit(500.0)
	assert_false(pill.is_fading(), "movement doesn't dismiss fire")
	Events.player_action.emit(&"laser")
	assert_true(pill.is_fading(), "the first bolt dismisses fire")
	await _wait_faded(pill)
	assert_eq(pill.showing_hint(), &"")
	assert_false(pill.visible, "hidden with nothing queued")
	assert_false(get_tree().paused)
	assert_eq(PauseArbiter.reasons().size(), 0, "PauseArbiter gains no reason")


func test_fade_in_runs_from_transparent() -> void:
	var pill: HintPill = _make()
	Events.hint_requested.emit(&"missile")
	assert_eq(pill.modulate.a, 0.0, "fades in from 0")
	await wait_seconds(0.3)
	assert_almost_eq(pill.modulate.a, 1.0, 0.001, "fully in after fade_in_s (0.2)")


func test_each_hint_is_dismissed_by_its_own_action() -> void:
	_fast()
	var cases: Array[Array] = [
		[&"missile", &"missile"],
		[&"shield", &"shield"],
		[&"barrage", &"barrage"],
	]
	for c: Array in cases:
		GameState.shown_hints.clear()
		var pill: HintPill = _make()
		var hint: StringName = c[0]
		if hint == &"missile":
			Events.hint_requested.emit(&"missile")
		elif hint == &"shield":
			Events.energy_changed.emit(50, 100)
		else:
			GameState.shown_hints[&"shield"] = true
			Events.energy_changed.emit(100, 100)
		assert_eq(pill.showing_hint(), hint)
		for other: StringName in [&"laser", &"missile", &"shield", &"barrage"]:
			if other != c[1]:
				Events.player_action.emit(other)
		assert_false(pill.is_fading(), "%s ignores other actions" % hint)
		Events.player_action.emit(c[1] as StringName)
		assert_true(pill.is_fading(), "%s dismissed by its action" % hint)
		pill.queue_free()
		await wait_process_frames(1)


# --- Timeout and pause -------------------------------------------------------------------

func test_timeout_fades_the_hint() -> void:
	_fast(0.3)
	var pill: HintPill = _make()
	Events.hint_requested.emit(&"missile")
	await wait_seconds(0.15)
	assert_false(pill.is_fading(), "still showing before show_s")
	await wait_seconds(0.3)
	assert_true(pill.is_fading() or pill.showing_hint() == &"", "faded out after show_s")
	await _wait_faded(pill)
	assert_eq(pill.showing_hint(), &"")
	assert_false(pill.visible)


func test_a_pause_stops_the_clock() -> void:
	_fast(0.3)
	var pill: HintPill = _make()
	Events.hint_requested.emit(&"missile")
	PauseArbiter.push(&"menu")
	var end_ms: int = Time.get_ticks_msec() + 600
	while Time.get_ticks_msec() < end_ms:
		await wait_process_frames(1)
	assert_eq(pill.showing_hint(), &"missile", "the clock froze under the pause")
	assert_false(pill.is_fading(), "no fade while paused")
	PauseArbiter.pop(&"menu")
	await wait_seconds(0.5)
	await _wait_faded(pill)
	assert_eq(pill.showing_hint(), &"", "the clock resumed after the pause")


func test_a_pause_freezes_the_fades() -> void:
	var pill_tuning: Dictionary = (Config.tuning["ui"] as Dictionary)["hint_pill"] as Dictionary
	pill_tuning["fade_in_s"] = 0.2
	pill_tuning["fade_out_s"] = 0.2
	var pill: HintPill = _make()
	Events.hint_requested.emit(&"move_fire")
	PauseArbiter.push(&"menu")
	var end_ms: int = Time.get_ticks_msec() + 400
	while Time.get_ticks_msec() < end_ms:
		await wait_process_frames(1)
	assert_lt(pill.modulate.a, 1.0, "the fade-in froze under the pause")
	PauseArbiter.pop(&"menu")
	await wait_seconds(0.35)
	assert_almost_eq(pill.modulate.a, 1.0, 0.001, "the fade-in finished after the pause")
	Events.player_moved.emit(150.0)
	assert_true(pill.is_fading())
	PauseArbiter.push(&"menu")
	end_ms = Time.get_ticks_msec() + 400
	while Time.get_ticks_msec() < end_ms:
		await wait_process_frames(1)
	assert_true(pill.is_fading(), "the fade-out froze under the pause")
	assert_eq(pill.showing_hint(), &"move", "the next hint waits while paused")
	PauseArbiter.pop(&"menu")
	await _wait_faded(pill)
	assert_false(pill.is_fading(), "the fade-out finished after the pause")
	assert_eq(pill.showing_hint(), &"fire", "then the next hint shows")


func test_default_show_time_is_five_seconds() -> void:
	var pill: HintPill = _make()
	Events.hint_requested.emit(&"missile")
	assert_almost_eq(pill.time_left(), 5.0, 0.05, "5 s clock from the start of the fade-in")


# --- Queue -----------------------------------------------------------------------------

func test_queue_waits_for_the_fade_out() -> void:
	_fast()
	var pill: HintPill = _make()
	Events.hint_requested.emit(&"move_fire")
	Events.hint_requested.emit(&"missile")
	assert_eq(pill.showing_hint(), &"move")
	assert_eq(pill.queued(), [&"fire", &"missile"] as Array[StringName])
	Events.player_moved.emit(150.0)
	assert_true(pill.is_fading())
	assert_eq(pill.showing_hint(), &"move", "missile waits while move fades")
	await _wait_faded(pill)
	assert_eq(pill.showing_hint(), &"fire")
	Events.player_action.emit(&"laser")
	await _wait_faded(pill)
	assert_eq(pill.showing_hint(), &"missile", "missile only after the earlier ones faded")


func test_actions_count_only_for_the_showing_hint() -> void:
	_fast()
	var pill: HintPill = _make()
	Events.hint_requested.emit(&"move_fire")
	Events.player_action.emit(&"laser")
	Events.player_moved.emit(150.0)
	await _wait_faded(pill)
	assert_eq(pill.showing_hint(), &"fire", "the bolt during move didn't consume fire")
	Events.player_moved.emit(100.0)
	Events.player_action.emit(&"laser")
	await _wait_faded(pill)
	assert_eq(pill.showing_hint(), &"")


func test_move_progress_does_not_carry_into_a_later_move_hint() -> void:
	var pill: HintPill = _make()
	Events.player_moved.emit(400.0)
	Events.hint_requested.emit(&"move_fire")
	assert_eq(pill.showing_hint(), &"move")
	assert_false(pill.is_fading(), "movement before the hint showed doesn't count")


# --- Energy --------------------------------------------------------------------------

func test_energy_thresholds() -> void:
	var pill: HintPill = _make()
	Events.energy_changed.emit(40, 100)
	assert_eq(pill.showing_hint(), &"", "40: nothing")
	assert_eq(pill.queued(), [] as Array[StringName])
	Events.energy_changed.emit(50, 100)
	assert_eq(pill.showing_hint(), &"shield", "50: shield")
	assert_eq(pill.action_text(), "SHIELD")
	assert_eq(pill.key_text(), "[E]")
	Events.energy_changed.emit(100, 100)
	assert_eq(pill.queued(), [&"barrage"] as Array[StringName], "100: barrage queued")
	Events.energy_changed.emit(100, 100)
	Events.energy_changed.emit(60, 100)
	assert_eq(pill.showing_hint(), &"shield", "repeats are ignored")
	assert_eq(pill.queued(), [&"barrage"] as Array[StringName], "repeats are ignored")


func test_energy_100_queues_shield_then_barrage() -> void:
	var pill: HintPill = _make()
	Events.energy_changed.emit(100, 100)
	assert_eq(pill.showing_hint(), &"shield", "shield first")
	assert_eq(pill.queued(), [&"barrage"] as Array[StringName])
	assert_eq(pill.key_text(), "[E]")


func test_thresholds_follow_the_ability_costs() -> void:
	(Config.tuning["abilities"]["shield"] as Dictionary)["cost"] = 30
	var pill: HintPill = _make()
	Events.energy_changed.emit(30, 100)
	assert_eq(pill.showing_hint(), &"shield", "the cost from tuning")


func test_no_energy_events_means_no_energy_hints() -> void:
	var pill: HintPill = _make()
	Events.hint_requested.emit(&"move_fire")
	Events.hint_requested.emit(&"missile")
	assert_false(pill.queued().has(&"shield"))
	assert_false(pill.queued().has(&"barrage"))
	assert_ne(pill.showing_hint(), &"shield")


# --- Once per session -------------------------------------------------------------

func test_a_shown_hint_never_shows_again_after_a_reload() -> void:
	_fast()
	var pill: HintPill = _make()
	Events.hint_requested.emit(&"missile")
	assert_eq(pill.showing_hint(), &"missile")
	pill.queue_free()
	await wait_process_frames(1)
	var fresh: HintPill = _make()
	Events.hint_requested.emit(&"missile")
	assert_eq(fresh.showing_hint(), &"", "a retry doesn't repeat it")
	assert_false(fresh.visible)


func test_a_fresh_pill_with_shown_hints_shows_nothing() -> void:
	for id: StringName in [&"move", &"fire", &"missile", &"shield", &"barrage"]:
		GameState.shown_hints[id] = true
	var pill: HintPill = _make()
	Events.hint_requested.emit(&"move_fire")
	Events.hint_requested.emit(&"missile")
	Events.energy_changed.emit(100, 100)
	assert_eq(pill.showing_hint(), &"")
	assert_eq(pill.queued(), [] as Array[StringName])
	assert_false(pill.visible)


func test_a_queued_hint_that_never_showed_can_show_later() -> void:
	var pill: HintPill = _make()
	Events.hint_requested.emit(&"move_fire")
	assert_eq(pill.queued(), [&"fire"] as Array[StringName])
	pill.queue_free()
	await wait_process_frames(1)
	assert_false(GameState.shown_hints.has(&"fire"))
	var fresh: HintPill = _make()
	Events.hint_requested.emit(&"move_fire")
	assert_eq(fresh.showing_hint(), &"fire", "move was shown; fire never was")


func test_a_showing_or_queued_hint_is_not_queued_twice() -> void:
	var pill: HintPill = _make()
	Events.hint_requested.emit(&"move_fire")
	Events.hint_requested.emit(&"move_fire")
	assert_eq(pill.showing_hint(), &"move")
	assert_eq(pill.queued(), [&"fire"] as Array[StringName])


# --- Bad input and isolation ---------------------------------------------------------

func test_unknown_id_shows_nothing_and_warns() -> void:
	var pill: HintPill = _make()
	Events.hint_requested.emit(&"bogus")
	assert_eq(pill.showing_hint(), &"")
	assert_false(pill.visible)
	assert_eq(_lines_containing("[WARN][hint]").size(), 1, "one hint warning")
	assert_push_warning("bogus")


func test_never_pauses_or_touches_comms() -> void:
	var pill: HintPill = _make()
	watch_signals(Events)
	Events.hint_requested.emit(&"move_fire")
	Events.energy_changed.emit(100, 100)
	assert_false(get_tree().paused)
	assert_eq(PauseArbiter.reasons().size(), 0)
	assert_signal_not_emitted(Events, "comms_sequence_requested")
	assert_eq(pill.showing_hint(), &"move")


func test_logs_the_hint_shown_at_info() -> void:
	var pill: HintPill = _make()
	Events.hint_requested.emit(&"missile")
	assert_eq(pill.showing_hint(), &"missile")
	assert_eq(_lines_containing("[INFO][hint] Hint 'missile' shown").size(), 1)
