extends GutTest
## HeartsDisplay: the top-right hearts, driven only by Events.hearts_changed
## (layout from hud.hearts, colours from the theme, the lost-heart pop).

const THEME_PATH: String = "res://ui/theme/defector_theme.tres"


func after_each() -> void:
	get_tree().paused = false
	Config.load_data()
	PauseArbiter.clear()


func _make(pop_s: float = -1.0) -> HeartsDisplay:
	if pop_s >= 0.0:
		((Config.tuning["hud"] as Dictionary)["hearts"] as Dictionary)["pop_s"] = pop_s
	var display: HeartsDisplay = HeartsDisplay.new()
	display.theme = load(THEME_PATH) as Theme
	add_child_autofree(display)
	return display


func test_init_modes() -> void:
	var display: HeartsDisplay = _make()
	assert_eq(display.process_mode, Node.PROCESS_MODE_PAUSABLE)
	assert_eq(display.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_nothing_before_the_first_event() -> void:
	var display: HeartsDisplay = _make()
	assert_eq(display.max_hearts(), 0)
	assert_eq(display.current(), 0)
	assert_eq(display.popping_index(), -1)


func test_first_event_shows_full_hearts_right_aligned() -> void:
	var display: HeartsDisplay = _make()
	Events.hearts_changed.emit(5, 5)
	assert_eq(display.max_hearts(), 5)
	assert_eq(display.current(), 5)
	assert_eq(display.popping_index(), -1, "no pop for the initial value")
	# 5 x 40 px + 4 x 8 px = 232 px, ending at x 1888, y 24.
	assert_eq(display.size, Vector2(232, 40))
	assert_eq(display.position, Vector2(1888 - 232, 24))


func test_row_width() -> void:
	assert_eq(HeartsDisplay.row_width(5, 40.0, 8.0), 232.0)
	assert_eq(HeartsDisplay.row_width(1, 40.0, 8.0), 40.0)
	assert_eq(HeartsDisplay.row_width(0, 40.0, 8.0), 0.0)


func test_heart_polygon_fits_the_unit_box() -> void:
	var points: PackedVector2Array = HeartsDisplay.heart_polygon(32)
	assert_eq(points.size(), 32)
	for p: Vector2 in points:
		assert_between(p.x, -1.0001, 1.0001)
		assert_between(p.y, -1.0001, 1.0001)
	assert_eq(HeartsDisplay.heart_polygon(2).size(), 0, "too few points")


func test_lost_heart_pops_then_settles() -> void:
	var display: HeartsDisplay = _make(0.1)
	Events.hearts_changed.emit(5, 5)
	Events.hearts_changed.emit(4, 5)
	assert_eq(display.current(), 4)
	assert_eq(display.popping_index(), 4, "the heart just lost pops")
	assert_almost_eq(display.pop_scale_now(), Config.num("hud.hearts.pop_scale"), 0.0001, "starts at pop_scale")
	await wait_seconds(0.2)
	assert_eq(display.popping_index(), -1, "pop over after pop_s")
	assert_eq(display.pop_scale_now(), 1.0)


func test_two_heart_loss_pops_from_the_lowest_lost() -> void:
	var display: HeartsDisplay = _make()
	Events.hearts_changed.emit(5, 5)
	Events.hearts_changed.emit(3, 5)
	assert_eq(display.current(), 3)
	assert_eq(display.popping_index(), 3)


func test_icons_fill_and_pop_after_a_two_heart_loss() -> void:
	var display: HeartsDisplay = _make()
	Events.hearts_changed.emit(5, 5)
	Events.hearts_changed.emit(3, 5)
	var pop: float = Config.num("hud.hearts.pop_scale")
	for i: int in 5:
		assert_eq(HeartsDisplay.icon_filled(i, display.current()), i < 3, "icon %d filled" % i)
		var scale_now: float = HeartsDisplay.icon_scale(i, display.popping_index(), display._pop_to, display.pop_scale_now())
		assert_eq(scale_now, pop if i >= 3 else 1.0, "icon %d pop scale" % i)
	assert_eq(HeartsDisplay.icon_scale(3, -1, -1, pop), 1.0, "no pop when none is running")


func test_pop_takes_at_most_the_ui_limit() -> void:
	assert_lte(Config.num("hud.hearts.pop_s"), 0.3, "UI motion never exceeds 0.3 s")


func test_overkill_values_are_clamped() -> void:
	var display: HeartsDisplay = _make()
	Events.hearts_changed.emit(5, 5)
	Events.hearts_changed.emit(-1, 5)
	assert_eq(display.current(), 0)


func test_theme_colours() -> void:
	var display: HeartsDisplay = _make()
	assert_true(display.get_theme_color(&"heart", &"HeartsDisplay").is_equal_approx(Color("#FF4766")), "heart colour")
	assert_true(display.get_theme_color(&"empty", &"HeartsDisplay").is_equal_approx(Color("#2B3348")), "empty colour")
	assert_true(display.get_theme_color(&"outline", &"HeartsDisplay").is_equal_approx(Color("#93A7C2")), "outline colour")


func test_pop_freezes_while_paused() -> void:
	var display: HeartsDisplay = _make(0.1)
	Events.hearts_changed.emit(5, 5)
	Events.hearts_changed.emit(4, 5)
	get_tree().paused = true
	# A SceneTreeTimer runs while paused by default.
	await get_tree().create_timer(0.2).timeout
	assert_eq(display.popping_index(), 4, "tween bound to the pausable node")
	get_tree().paused = false
