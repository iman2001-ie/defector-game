extends GutTest
## BossBar (Story 7.3, FR53, UX `bossBar`): hidden until Events.boss_started,
## then cross-fades in over the WaveBar's slot while the WaveBar fades out; the
## enemy fill shows current / max from the left; two text markers at
## boss.core.hp / max and boss.final_choice_hp / max; a muted FLAGSHIP label
## centred below the bar at y 68; level_started hides it and brings the
## WaveBar back. Driven by Events only.

const THEME_PATH: String = "res://ui/theme/defector_theme.tres"


func after_each() -> void:
	PauseArbiter.clear()
	Config.load_data()


func _make() -> BossBar:
	var bar: BossBar = BossBar.new()
	bar.theme = load(THEME_PATH) as Theme
	add_child_autofree(bar)
	return bar


func _make_wave_bar() -> WaveBar:
	var bar: WaveBar = WaveBar.new()
	bar.theme = load(THEME_PATH) as Theme
	add_child_autofree(bar)
	return bar


func _assert_color(actual: Color, expected: Color, what: String) -> void:
	assert_almost_eq(actual.r, expected.r, 0.002, what + " r")
	assert_almost_eq(actual.g, expected.g, 0.002, what + " g")
	assert_almost_eq(actual.b, expected.b, 0.002, what + " b")
	assert_almost_eq(actual.a, expected.a, 0.002, what + " a")


func test_tuning() -> void:
	var expected: Dictionary = {"x": 680.0, "y": 40.0, "width": 560.0, "height": 20.0, "fade_s": 0.3,
		"label_y": 68.0, "label_px": 20.0, "marker_w_px": 2.0}
	for key: String in expected:
		assert_almost_eq(Config.num("hud.boss_bar.%s" % key), float(expected[key]), 0.0001, "hud.boss_bar.%s" % key)


func test_init_modes_and_rect() -> void:
	var bar: BossBar = _make()
	assert_eq(bar.process_mode, Node.PROCESS_MODE_PAUSABLE)
	assert_eq(bar.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(bar.label().mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(bar.get_rect(), Rect2(680, 40, 560, 20), "the wave bar's slot")


func test_hidden_until_boss_started() -> void:
	var bar: BossBar = _make()
	assert_false(bar.visible, "hidden outside the boss fight")
	assert_eq(bar.modulate.a, 0.0)
	Events.wave_started.emit(0, 3)
	Events.boss_hp_changed.emit(300, 300, 0)
	assert_false(bar.visible, "other events don't show it")
	Events.boss_started.emit()
	assert_true(bar.visible)


func test_boss_started_cross_fades_both_bars() -> void:
	var wave_bar: WaveBar = _make_wave_bar()
	var bar: BossBar = _make()
	var fade_s: float = Config.num("hud.boss_bar.fade_s")
	assert_eq(wave_bar.modulate.a, 1.0, "the wave bar shows before the boss")
	Events.boss_started.emit()
	await wait_seconds(fade_s / 2.0)
	assert_between(bar.modulate.a, 0.05, 0.95, "the boss bar is fading in")
	assert_between(wave_bar.modulate.a, 0.05, 0.95, "the wave bar is fading out")
	await wait_seconds(fade_s / 2.0 + 0.15)
	assert_almost_eq(bar.modulate.a, 1.0, 0.001, "the boss bar faded in")
	assert_almost_eq(wave_bar.modulate.a, 0.0, 0.001, "the wave bar faded out")


func test_fill_is_current_over_max_from_the_left() -> void:
	var bar: BossBar = _make()
	Events.boss_started.emit()
	Events.boss_hp_changed.emit(300, 300, 0)
	assert_eq(bar.current(), 300)
	assert_eq(bar.max_hp(), 300)
	assert_almost_eq(bar.fill_width(), 560.0, 0.001, "full")
	Events.boss_hp_changed.emit(290, 300, 1)
	assert_almost_eq(bar.fill_width(), 560.0 * 290.0 / 300.0, 0.001, "drains right to left")
	Events.boss_hp_changed.emit(200, 300, 1)
	assert_almost_eq(bar.fill_width(), 560.0 * 2.0 / 3.0, 0.001, "turrets gone")
	Events.boss_hp_changed.emit(-5, 300, 1)
	assert_eq(bar.fill_width(), 0.0, "clamped at empty")


func test_markers_at_the_core_and_final_choice_hp() -> void:
	var bar: BossBar = _make()
	assert_eq(bar.marker_xs(), [] as Array[float], "no markers before any HP")
	Events.boss_hp_changed.emit(300, 300, 0)
	var xs: Array[float] = bar.marker_xs()
	assert_eq(xs.size(), 2, "two markers")
	if xs.size() == 2:
		assert_almost_eq(xs[0], 560.0 * 200.0 / 300.0, 0.001, "66.7 %: the turrets gone")
		assert_almost_eq(xs[1], 560.0 * 50.0 / 300.0, 0.001, "16.7 %: the Final Choice")
	assert_eq(bar.marker_hps, [Config.int_("boss.core.hp"), Config.int_("boss.final_choice_hp")] as Array[int], "read from tuning")


func test_zero_max_draws_an_empty_bar_without_markers() -> void:
	var bar: BossBar = _make()
	Events.boss_started.emit()
	Events.boss_hp_changed.emit(10, 0, 0)
	assert_eq(bar.fill_width(), 0.0, "empty fill")
	assert_eq(bar.marker_xs(), [] as Array[float], "no markers")
	assert_eq(BossBar.marker_x(50, 0, 560.0), 0.0)


func test_label() -> void:
	var bar: BossBar = _make()
	var label: Label = bar.label()
	assert_eq(label.text, "FLAGSHIP")
	assert_eq(label.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER, "centred")
	assert_eq(label.get_theme_font_size(&"font_size"), 20)
	_assert_color(label.get_theme_color(&"font_color"), Color("#93A7C2"), "muted label")
	assert_almost_eq(label.get_global_rect().position.y, 68.0, 0.01, "top at y 68")
	assert_almost_eq(label.get_global_rect().position.x, 680.0, 0.01, "as wide as the bar")
	assert_almost_eq(label.size.x, 560.0, 0.01)
	assert_true(label.get_global_rect().position.y + 20.0 <= 120.0, "inside the top HUD band")


func test_theme_items() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	assert_true(theme.has_stylebox(&"track", &"BossBar"))
	assert_true(theme.has_stylebox(&"fill", &"BossBar"))
	assert_eq(theme.get_stylebox(&"track", &"BossBar"), theme.get_stylebox(&"track", &"WaveBar"), "the wave bar's track")
	var fill: StyleBoxFlat = theme.get_stylebox(&"fill", &"BossBar") as StyleBoxFlat
	assert_not_null(fill)
	if fill != null:
		_assert_color(fill.bg_color, Color("#FF2BD6"), "enemy fill")
		assert_eq(fill.corner_radius_top_left, 2, "2 px corners")
		assert_eq(fill.corner_radius_bottom_right, 2)
	_assert_color(theme.get_color(&"marker", &"BossBar"), Color("#E8F4FF"), "text markers")
	_assert_color(theme.get_color(&"label", &"BossBar"), Color("#93A7C2"), "muted label")


func test_level_started_hides_it_and_restores_the_wave_bar() -> void:
	var wave_bar: WaveBar = _make_wave_bar()
	var bar: BossBar = _make()
	Events.boss_started.emit()
	Events.boss_hp_changed.emit(250, 300, 1)
	await wait_seconds(Config.num("hud.boss_bar.fade_s") + 0.15)
	Events.level_started.emit(3)
	assert_false(bar.visible, "hidden")
	assert_eq(bar.modulate.a, 0.0)
	assert_eq(bar.max_hp(), 0, "values reset")
	assert_eq(wave_bar.modulate.a, 1.0, "the wave bar is back")


func test_fade_freezes_under_pause() -> void:
	var bar: BossBar = _make()
	Events.boss_started.emit()
	PauseArbiter.push(&"menu")
	var frozen: float = bar.modulate.a
	# A SceneTreeTimer runs while paused by default.
	await get_tree().create_timer(Config.num("hud.boss_bar.fade_s") + 0.15).timeout
	assert_eq(bar.modulate.a, frozen, "the fade holds while paused")
	assert_lt(bar.modulate.a, 1.0)
	PauseArbiter.pop(&"menu")
	await wait_seconds(Config.num("hud.boss_bar.fade_s") + 0.15)
	assert_almost_eq(bar.modulate.a, 1.0, 0.001)
