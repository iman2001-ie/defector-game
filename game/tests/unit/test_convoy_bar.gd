extends GutTest
## ConvoyBar (Story 6.1, FR62): the top-right convoy meter, driven only by
## Events.convoy_hp_changed and hidden until the first one; layout from
## hud.convoy_bar, colours and styles from the theme; a danger flash on each
## HP drop and a pulsing label below low_ratio.

const THEME_PATH: String = "res://ui/theme/defector_theme.tres"


func after_each() -> void:
	PauseArbiter.clear()
	Config.load_data()


func _make() -> ConvoyBar:
	var bar: ConvoyBar = ConvoyBar.new()
	bar.theme = load(THEME_PATH) as Theme
	add_child_autofree(bar)
	return bar


func _assert_color(actual: Color, expected: Color, what: String) -> void:
	assert_almost_eq(actual.r, expected.r, 0.002, what + " r")
	assert_almost_eq(actual.g, expected.g, 0.002, what + " g")
	assert_almost_eq(actual.b, expected.b, 0.002, what + " b")
	assert_almost_eq(actual.a, expected.a, 0.002, what + " a")


func test_tuning() -> void:
	var expected: Dictionary = {"right_x": 1888.0, "y": 104.0, "width": 320.0, "height": 12.0, "label_px": 20.0,
		"label_gap_px": 8.0, "flash_s": 0.3, "low_ratio": 0.3, "pulse_hz": 2.0, "pulse_min_alpha": 0.35}
	for key: String in expected:
		assert_almost_eq(Config.num("hud.convoy_bar.%s" % key), float(expected[key]), 0.0001, "hud.convoy_bar.%s" % key)
	assert_lt(Config.num("hud.convoy_bar.height"), Config.num("hud.energy_bar.height"), "thinner than the energy bar")


func test_init_modes() -> void:
	var bar: ConvoyBar = _make()
	assert_eq(bar.process_mode, Node.PROCESS_MODE_PAUSABLE)
	assert_eq(bar.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(bar.label().mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_hidden_until_the_first_hp_event() -> void:
	var bar: ConvoyBar = _make()
	assert_false(bar.visible, "hidden in a level without a convoy")
	Events.energy_changed.emit(50, 100)
	assert_false(bar.visible, "other events don't show it")
	Events.convoy_hp_changed.emit(100, 100)
	assert_true(bar.visible)
	assert_eq(bar.current(), 100)
	assert_eq(bar.max_hp(), 100)
	assert_false(bar.is_flashing(), "the first value is not a hit")


func test_rect_from_tuning() -> void:
	var bar: ConvoyBar = _make()
	assert_eq(bar.get_rect(), Rect2(1568, 104, 320, 12))
	assert_eq(bar.get_rect().end.x, 1888.0, "right-aligned at x 1888")
	assert_true(bar.get_rect().end.y <= 120.0, "inside the top HUD band")


func test_label() -> void:
	var bar: ConvoyBar = _make()
	var label: Label = bar.label()
	assert_eq(label.text, "CONVOY")
	assert_eq(label.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT)
	assert_eq(label.get_theme_font_size(&"font_size"), 20)
	_assert_color(label.get_theme_color(&"font_color"), Color("#93A7C2"), "muted label")
	assert_almost_eq(label.position.x + label.size.x, -8.0, 0.01, "right edge 8 px left of the bar")
	assert_almost_eq(label.position.y + label.size.y / 2.0, 6.0, 0.5, "vertically centred on the bar")
	assert_eq(label.modulate.a, 1.0)


func test_theme_items() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	assert_true(theme.has_color(&"label", &"ConvoyBar"))
	assert_true(theme.has_color(&"danger", &"ConvoyBar"))
	_assert_color(theme.get_color(&"label", &"ConvoyBar"), Color("#93A7C2"), "muted")
	_assert_color(theme.get_color(&"danger", &"ConvoyBar"), Color("#FF1F4B"), "danger")
	var fill: StyleBoxFlat = theme.get_stylebox(&"fill", &"ConvoyBar") as StyleBoxFlat
	var track: StyleBoxFlat = theme.get_stylebox(&"track", &"ConvoyBar") as StyleBoxFlat
	assert_not_null(fill, "fill StyleBoxFlat")
	assert_not_null(track, "track StyleBoxFlat")
	if fill != null:
		_assert_color(fill.bg_color, Color("#22E6FF"), "coalition fill")
		assert_eq(fill.corner_radius_top_left, 2, "2 px bar corners")
	if track != null:
		_assert_color(track.bg_color, Color("#2B3348"), "heartEmpty track")


func test_fill_width() -> void:
	assert_eq(ConvoyBar.fill_width(100, 100, 320.0), 320.0)
	assert_eq(ConvoyBar.fill_width(60, 100, 320.0), 192.0, "60 %")
	assert_eq(ConvoyBar.fill_width(0, 100, 320.0), 0.0)
	assert_eq(ConvoyBar.fill_width(150, 100, 320.0), 320.0, "capped")
	assert_eq(ConvoyBar.fill_width(50, 0, 320.0), 0.0, "no max")


func test_hp_drop_fills_60_percent_and_flashes_once() -> void:
	var bar: ConvoyBar = _make()
	Events.convoy_hp_changed.emit(100, 100)
	Events.convoy_hp_changed.emit(60, 100)
	assert_eq(bar.current(), 60)
	assert_eq(ConvoyBar.fill_width(bar.current(), bar.max_hp(), bar.size.x), 192.0, "fill 60 %")
	assert_true(bar.is_flashing(), "danger flash on the drop")
	assert_true(bar.is_processing())
	bar._process(0.2)
	assert_true(bar.is_flashing(), "still within flash_s")
	bar._process(0.11)
	assert_false(bar.is_flashing(), "one flash of 0.3 s")
	assert_false(bar.is_processing(), "idle again above low_ratio")


func test_no_flash_on_a_rise_or_equal_value() -> void:
	var bar: ConvoyBar = _make()
	Events.convoy_hp_changed.emit(50, 100)
	Events.convoy_hp_changed.emit(50, 100)
	assert_false(bar.is_flashing())
	Events.convoy_hp_changed.emit(100, 100)
	assert_false(bar.is_flashing())


func test_flash_freezes_under_pause() -> void:
	var bar: ConvoyBar = _make()
	Events.convoy_hp_changed.emit(100, 100)
	Events.convoy_hp_changed.emit(90, 100)
	PauseArbiter.push(&"menu")
	assert_false(bar.can_process(), "PAUSABLE: frozen while paused")
	PauseArbiter.pop(&"menu")
	assert_true(bar.can_process())


func test_label_pulses_below_low_ratio() -> void:
	var bar: ConvoyBar = _make()
	Events.convoy_hp_changed.emit(100, 100)
	assert_false(bar.is_low())
	Events.convoy_hp_changed.emit(30, 100)
	assert_false(bar.is_low(), "exactly 30 % is not below")
	Events.convoy_hp_changed.emit(29, 100)
	assert_true(bar.is_low(), "below 30 %")
	assert_true(bar.is_processing(), "pulsing")
	bar._process(0.31)
	bar._process(0.1)
	# 0.41 s into the pulse.
	var label: Label = bar.label()
	assert_almost_eq(label.modulate.a, ConvoyBar.pulse_alpha(0.41, 2.0, bar.pulse_min_alpha), 0.0001)
	assert_lt(label.modulate.a, 1.0, "dimmed in the pulse")
	Events.convoy_hp_changed.emit(80, 100)
	assert_eq(label.modulate.a, 1.0, "solid again above low_ratio")


func test_pulse_alpha() -> void:
	assert_almost_eq(ConvoyBar.pulse_alpha(0.0, 2.0, 0.35), 1.0, 0.0001, "starts lit")
	assert_almost_eq(ConvoyBar.pulse_alpha(0.25, 2.0, 0.35), 0.35, 0.0001, "trough half a cycle in")
	assert_almost_eq(ConvoyBar.pulse_alpha(0.5, 2.0, 0.35), 1.0, 0.0001, "one cycle at 2 Hz")
	assert_eq(ConvoyBar.pulse_alpha(0.25, 0.0, 0.35), 1.0, "no frequency: solid")


func test_is_low_ratio() -> void:
	assert_true(ConvoyBar.is_low_ratio(29, 100, 0.3))
	assert_false(ConvoyBar.is_low_ratio(30, 100, 0.3))
	assert_false(ConvoyBar.is_low_ratio(0, 0, 0.3), "no max")
