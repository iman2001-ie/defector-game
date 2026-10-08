extends GutTest
## EnergyBar (Story 3.3): the top-right energy meter, driven only by
## Events.energy_changed (layout from hud.energy_bar, colours from the theme,
## ticks at the Shield and Barrage costs).

const THEME_PATH: String = "res://ui/theme/defector_theme.tres"


func after_each() -> void:
	PauseArbiter.clear()
	Config.load_data()


func _make() -> EnergyBar:
	var bar: EnergyBar = EnergyBar.new()
	bar.theme = load(THEME_PATH) as Theme
	add_child_autofree(bar)
	return bar


func test_init_modes() -> void:
	var bar: EnergyBar = _make()
	assert_eq(bar.process_mode, Node.PROCESS_MODE_PAUSABLE)
	assert_eq(bar.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_rect_from_tuning() -> void:
	var bar: EnergyBar = _make()
	assert_eq(bar.position, Vector2(1568, 76))
	assert_eq(bar.size, Vector2(320, 16))
	assert_eq(bar.get_rect().end.x, 1888.0, "right-aligned at x 1888")


func test_starts_empty_with_the_tuning_max() -> void:
	var bar: EnergyBar = _make()
	assert_eq(bar.current(), 0)
	assert_eq(bar.max_energy(), 100)


func test_energy_changed_updates_the_bar() -> void:
	var bar: EnergyBar = _make()
	Events.energy_changed.emit(50, 100)
	assert_eq(bar.current(), 50)
	assert_eq(bar.max_energy(), 100)
	assert_eq(EnergyBar.fill_width(bar.current(), bar.max_energy(), bar.size.x), 160.0, "fill 160 px")
	assert_eq(bar.tick_positions(), [160.0, 318.0] as Array[float], "ticks at 50 and 100, clamped inside")


func test_values_are_clamped() -> void:
	var bar: EnergyBar = _make()
	Events.energy_changed.emit(150, 100)
	assert_eq(bar.current(), 100)
	Events.energy_changed.emit(-5, 100)
	assert_eq(bar.current(), 0)


func test_fill_width() -> void:
	assert_eq(EnergyBar.fill_width(0, 100, 320.0), 0.0, "nothing at 0")
	assert_eq(EnergyBar.fill_width(10, 100, 320.0), 32.0)
	assert_eq(EnergyBar.fill_width(100, 100, 320.0), 320.0)
	assert_eq(EnergyBar.fill_width(200, 100, 320.0), 320.0, "capped")
	assert_eq(EnergyBar.fill_width(50, 0, 320.0), 0.0, "no max")


func test_tick_x() -> void:
	assert_eq(EnergyBar.tick_x(50, 100, 320.0, 2.0), 160.0)
	assert_eq(EnergyBar.tick_x(100, 100, 320.0, 2.0), 318.0, "the whole tick stays inside")
	assert_eq(EnergyBar.tick_x(0, 100, 320.0, 2.0), 0.0)
	assert_eq(EnergyBar.tick_x(150, 100, 320.0, 2.0), 318.0)
	assert_eq(EnergyBar.tick_x(50, 0, 320.0, 2.0), 0.0, "no max")


func test_ticks_follow_the_ability_costs() -> void:
	((Config.tuning["abilities"] as Dictionary)["shield"] as Dictionary)["cost"] = 25
	var bar: EnergyBar = _make()
	assert_eq(bar.tick_positions(), [80.0, 318.0] as Array[float])


func test_theme_styles() -> void:
	var bar: EnergyBar = _make()
	var track: StyleBoxFlat = bar.get_theme_stylebox(&"track", &"EnergyBar") as StyleBoxFlat
	var fill: StyleBoxFlat = bar.get_theme_stylebox(&"fill", &"EnergyBar") as StyleBoxFlat
	assert_not_null(track)
	assert_not_null(fill)
	if track != null:
		assert_true(track.bg_color.is_equal_approx(Color("#2B3348")), "heartEmpty track")
		assert_eq(track.corner_radius_top_left, 2)
	if fill != null:
		assert_true(fill.bg_color.is_equal_approx(Color("#FFD23F")), "energy fill")
		assert_eq(fill.corner_radius_top_left, 2)
	assert_true(bar.get_theme_color(&"tick", &"EnergyBar").is_equal_approx(Color("#E8F4FF")), "text ticks")


func test_draws_without_errors() -> void:
	var bar: EnergyBar = _make()
	Events.energy_changed.emit(0, 100)
	await wait_process_frames(1)
	Events.energy_changed.emit(70, 100)
	await wait_process_frames(1)
	assert_eq(bar.current(), 70)


func test_energy_changed_repaints_the_bar() -> void:
	var bar: EnergyBar = _make()
	await wait_process_frames(1)
	watch_signals(bar)
	Events.energy_changed.emit(40, 100)
	await wait_process_frames(1)
	assert_signal_emitted(bar, "draw", "the bar redraws after energy_changed")


# --- Denied flash (Story 3.4) ----------------------------------------------------

func test_denied_flash_tuning() -> void:
	var bar: EnergyBar = _make()
	assert_almost_eq(bar.denied_flash_s, 0.3, 0.0001)
	assert_eq(bar.denied_flashes, 2)


func test_idle_bar_does_not_process() -> void:
	var bar: EnergyBar = _make()
	assert_false(bar.is_processing(), "_process off until a denial")
	assert_false(bar.is_flashing())
	assert_false(bar.flash_on())


func test_flash_lit() -> void:
	assert_true(EnergyBar.flash_lit(0.0, 0.3, 2), "on at 0")
	assert_true(EnergyBar.flash_lit(0.07, 0.3, 2), "on before 0.075")
	assert_false(EnergyBar.flash_lit(0.075, 0.3, 2), "off from 0.075")
	assert_false(EnergyBar.flash_lit(0.14, 0.3, 2), "off before 0.15")
	assert_true(EnergyBar.flash_lit(0.15, 0.3, 2), "on from 0.15")
	assert_true(EnergyBar.flash_lit(0.22, 0.3, 2), "on before 0.225")
	assert_false(EnergyBar.flash_lit(0.225, 0.3, 2), "off from 0.225")
	assert_false(EnergyBar.flash_lit(0.29, 0.3, 2), "still off")
	assert_false(EnergyBar.flash_lit(0.3, 0.3, 2), "over at duration")
	assert_false(EnergyBar.flash_lit(-0.01, 0.3, 2), "before start")
	assert_false(EnergyBar.flash_lit(0.0, 0.0, 2), "no duration")
	assert_false(EnergyBar.flash_lit(0.0, 0.3, 0), "no flashes")


func test_ability_denied_flashes_twice_then_stops() -> void:
	var bar: EnergyBar = _make()
	Events.ability_denied.emit(&"shield")
	assert_true(bar.is_flashing())
	assert_true(bar.flash_on(), "on at once")
	assert_true(bar.is_processing(), "_process runs while flashing")
	bar._process(0.08)
	assert_false(bar.flash_on(), "0.08: off")
	bar._process(0.08)
	assert_true(bar.flash_on(), "0.16: on")
	bar._process(0.08)
	assert_false(bar.flash_on(), "0.24: off")
	assert_true(bar.is_flashing(), "still running")
	bar._process(0.07)
	assert_false(bar.is_flashing(), "stops at 0.3")
	assert_false(bar.flash_on())
	assert_false(bar.is_processing(), "_process off again")


func test_any_ability_flashes() -> void:
	var bar: EnergyBar = _make()
	Events.ability_denied.emit(&"barrage")
	assert_true(bar.is_flashing())
	assert_true(bar.flash_on())


func test_second_denial_restarts_the_flash() -> void:
	var bar: EnergyBar = _make()
	Events.ability_denied.emit(&"shield")
	bar._process(0.2)
	assert_true(bar.flash_on())
	bar._process(0.05)
	assert_false(bar.flash_on(), "0.25: off")
	Events.ability_denied.emit(&"shield")
	assert_true(bar.flash_on(), "restarted from 0")
	bar._process(0.1)
	assert_false(bar.flash_on(), "0.1 into the new flash: off")
	assert_true(bar.is_flashing(), "the new flash still runs past the old end")
	bar._process(0.1)
	assert_true(bar.is_flashing())


func test_flash_freezes_under_pause() -> void:
	var bar: EnergyBar = _make()
	Events.ability_denied.emit(&"shield")
	PauseArbiter.push(&"menu")
	# ~0.4 s of frames, past the whole 0.3 s flash, so an unpaused flash would
	# have ended (GUT's wait_seconds itself freezes under pause; physics_frame
	# still fires).
	await wait_physics_frames(24)
	assert_true(bar.is_flashing(), "frozen")
	assert_true(bar.flash_on(), "still on the first phase")
	PauseArbiter.clear()
	await wait_seconds(0.4)
	assert_false(bar.is_flashing(), "runs out once unpaused")
	assert_false(bar.is_processing(), "_process off again")


func test_flash_runs_out_in_real_frames() -> void:
	var bar: EnergyBar = _make()
	Events.ability_denied.emit(&"shield")
	await wait_seconds(0.45)
	assert_false(bar.is_flashing())
	assert_false(bar.is_processing())


func test_denied_theme_colour() -> void:
	var bar: EnergyBar = _make()
	assert_true(bar.has_theme_color(&"denied", &"EnergyBar"), "EnergyBar/colors/denied")
	assert_true(bar.get_theme_color(&"denied", &"EnergyBar").is_equal_approx(Color("#FF1F4B")), "danger")


func test_flash_repaints_the_bar() -> void:
	var bar: EnergyBar = _make()
	await wait_process_frames(1)
	watch_signals(bar)
	Events.ability_denied.emit(&"shield")
	await wait_process_frames(1)
	assert_signal_emitted(bar, "draw", "the bar redraws when the flash turns on")
