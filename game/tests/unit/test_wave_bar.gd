extends GutTest
## WaveBar: the segmented top-centre wave progress bar, driven only by Events
## (level_started / wave_started / wave_progress_changed / wave_cleared).

const THEME_PATH: String = "res://ui/theme/defector_theme.tres"
const SCRIPT_PATH: String = "res://ui/hud/wave_bar.gd"
## Short tween for the timing tests (restored by Config.load_data()).
const FAST_TWEEN_S: float = 0.05


func after_each() -> void:
	get_tree().paused = false
	Config.load_data()
	PauseArbiter.clear()


func _make_bar(tween_s: float = -1.0) -> WaveBar:
	if tween_s >= 0.0:
		((Config.tuning["hud"] as Dictionary)["wave_bar"] as Dictionary)["fill_tween_s"] = tween_s
	var bar: WaveBar = WaveBar.new()
	bar.theme = load(THEME_PATH) as Theme
	add_child_autofree(bar)
	return bar


## level_started then wave_started(0, count), as the level does.
func _start(bar: WaveBar, count: int = 3) -> void:
	Events.level_started.emit(0)
	Events.wave_started.emit(0, count)
	assert_eq(bar.segment_count(), count)


func _settle() -> void:
	await wait_seconds(FAST_TWEEN_S + 0.1)


# --- I/O matrix ----------------------------------------------------------------

func test_level_start_shows_empty_segments() -> void:
	var bar: WaveBar = _make_bar()
	assert_eq(bar.segment_count(), 0, "nothing before the first wave")
	_start(bar)
	assert_eq(bar.current_index(), 0)
	assert_eq(bar.highlighted_index(), -1, "no highlight")
	for i: int in 3:
		assert_eq(bar.target_fill(i), 0.0, "target %d empty" % i)
		assert_eq(bar.displayed_fill(i), 0.0, "segment %d empty" % i)


func test_progress_tweens_to_the_ratio() -> void:
	var bar: WaveBar = _make_bar(FAST_TWEEN_S)
	_start(bar)
	Events.wave_progress_changed.emit(0, 0.5)
	assert_eq(bar.target_fill(0), 0.5, "target set at once")
	assert_lt(bar.displayed_fill(0), 0.5, "fill animates, not instant")
	await _settle()
	assert_almost_eq(bar.displayed_fill(0), 0.5, 0.0001, "reached after fill_tween_s")


func test_fill_takes_fill_tween_s() -> void:
	var bar: WaveBar = _make_bar(0.4)
	_start(bar)
	Events.wave_progress_changed.emit(0, 1.0)
	await wait_seconds(0.15)
	var mid: float = bar.displayed_fill(0)
	assert_gt(mid, 0.0, "moving")
	assert_lt(mid, 1.0, "not done before fill_tween_s")
	await wait_seconds(0.4)
	assert_almost_eq(bar.displayed_fill(0), 1.0, 0.0001, "done after fill_tween_s")


func test_zero_tween_fills_instantly() -> void:
	var bar: WaveBar = _make_bar(0.0)
	_start(bar)
	Events.wave_progress_changed.emit(0, 0.5)
	assert_eq(bar.displayed_fill(0), 0.5, "no tween: shown at once")


func test_style_for_highlights_only_the_next_segment() -> void:
	var bar: WaveBar = _make_bar(FAST_TWEEN_S)
	_start(bar)
	assert_eq(bar.style_for(0), &"track")
	assert_eq(bar.style_for(1), &"track")
	Events.wave_cleared.emit(0)
	assert_eq(bar.style_for(1), &"highlight", "next segment highlighted")
	assert_eq(bar.style_for(0), &"track")
	assert_eq(bar.style_for(2), &"track")


func test_fill_rect() -> void:
	var rect: Rect2 = Rect2(0, 0, 184, 20)
	var half: Rect2 = WaveBar.fill_rect(rect, 0.5)
	assert_eq(half.size.x, 92.0, "half width")
	assert_eq(half.size.y, 20.0)
	assert_eq(half.position, rect.position)
	assert_false(WaveBar.fill_rect(rect, 0.0).has_area(), "no fill at 0")
	assert_eq(WaveBar.fill_rect(Rect2(188, 0, 184, 20), 1.0), Rect2(188, 0, 184, 20), "full")


func test_lower_ratio_is_ignored() -> void:
	var bar: WaveBar = _make_bar(FAST_TWEEN_S)
	_start(bar)
	Events.wave_progress_changed.emit(0, 0.5)
	await _settle()
	Events.wave_progress_changed.emit(0, 0.25)
	assert_eq(bar.target_fill(0), 0.5, "target stays")
	await _settle()
	assert_almost_eq(bar.displayed_fill(0), 0.5, 0.0001, "fill stays")


func test_displayed_fill_never_decreases_mid_tween() -> void:
	var bar: WaveBar = _make_bar(0.3)
	_start(bar)
	Events.wave_progress_changed.emit(0, 0.4)
	var last: float = 0.0
	for step: int in 12:
		if step == 3:
			Events.wave_progress_changed.emit(0, 0.8)
		if step == 6:
			Events.wave_progress_changed.emit(0, 0.1)
		await wait_seconds(0.05)
		var now: float = bar.displayed_fill(0)
		assert_true(now >= last, "step %d: %.3f >= %.3f" % [step, now, last])
		last = now
	assert_almost_eq(last, 0.8, 0.0001)


func test_wave_clear_fills_and_highlights_next() -> void:
	var bar: WaveBar = _make_bar(FAST_TWEEN_S)
	_start(bar)
	Events.wave_progress_changed.emit(0, 0.5)
	Events.wave_cleared.emit(0)
	assert_eq(bar.target_fill(0), 1.0)
	assert_eq(bar.highlighted_index(), 1, "next segment highlighted in the gap")
	await _settle()
	assert_almost_eq(bar.displayed_fill(0), 1.0, 0.0001, "segment 0 full")


func test_next_wave_snaps_previous_and_clears_highlight() -> void:
	var bar: WaveBar = _make_bar(5.0)
	_start(bar)
	Events.wave_cleared.emit(0)
	assert_lt(bar.displayed_fill(0), 1.0, "still tweening")
	Events.wave_started.emit(1, 3)
	assert_eq(bar.displayed_fill(0), 1.0, "snapped full")
	assert_eq(bar.highlighted_index(), -1, "highlight off")
	assert_eq(bar.current_index(), 1)
	assert_eq(bar.displayed_fill(1), 0.0)


func test_progress_on_another_segment_snaps_the_old_tween() -> void:
	var bar: WaveBar = _make_bar(5.0)
	_start(bar)
	Events.wave_progress_changed.emit(0, 0.6)
	Events.wave_cleared.emit(0)
	Events.wave_started.emit(1, 3)
	Events.wave_progress_changed.emit(1, 0.5)
	assert_eq(bar.displayed_fill(0), 1.0, "old segment at its target")
	assert_eq(bar.target_fill(1), 0.5)


func test_skipped_waves_are_full() -> void:
	var bar: WaveBar = _make_bar(FAST_TWEEN_S)
	_start(bar)
	Events.wave_started.emit(2, 3)
	assert_eq(bar.current_index(), 2)
	for i: int in 2:
		assert_eq(bar.target_fill(i), 1.0, "target %d full" % i)
		assert_eq(bar.displayed_fill(i), 1.0, "segment %d full" % i)
	assert_eq(bar.displayed_fill(2), 0.0)


func test_last_wave_clear_highlights_nothing() -> void:
	var bar: WaveBar = _make_bar(FAST_TWEEN_S)
	_start(bar)
	Events.wave_started.emit(2, 3)
	Events.wave_cleared.emit(2)
	assert_eq(bar.highlighted_index(), -1, "nothing after the last wave")
	await _settle()
	for i: int in 3:
		assert_almost_eq(bar.displayed_fill(i), 1.0, 0.0001, "segment %d full" % i)


func test_stale_and_bad_indices_are_ignored() -> void:
	var bar: WaveBar = _make_bar(FAST_TWEEN_S)
	_start(bar)
	Events.wave_started.emit(1, 3)
	Events.wave_progress_changed.emit(0, 0.5)
	Events.wave_progress_changed.emit(3, 0.5)
	Events.wave_progress_changed.emit(-1, 0.5)
	Events.wave_cleared.emit(5)
	Events.wave_cleared.emit(-1)
	Events.wave_started.emit(4, 3)
	Events.wave_started.emit(-1, 3)
	assert_eq(bar.current_index(), 1, "bad wave_started ignored")
	assert_eq(bar.target_fill(1), 0.0, "current untouched")
	assert_eq(bar.highlighted_index(), -1)
	assert_eq(bar.target_fill(3), 0.0, "out-of-range accessor is safe")
	assert_eq(bar.displayed_fill(-1), 0.0, "out-of-range accessor is safe")
	await _settle()
	assert_eq(bar.displayed_fill(1), 0.0)
	assert_eq(bar.displayed_fill(2), 0.0)


func test_ratio_is_clamped() -> void:
	var bar: WaveBar = _make_bar(FAST_TWEEN_S)
	_start(bar)
	Events.wave_progress_changed.emit(0, -0.2)
	assert_eq(bar.target_fill(0), 0.0, "negative clamped to 0")
	Events.wave_progress_changed.emit(0, 1.7)
	assert_eq(bar.target_fill(0), 1.0, "over 1 clamped to 1")
	await _settle()
	assert_almost_eq(bar.displayed_fill(0), 1.0, 0.0001)


func test_level_started_resets_everything() -> void:
	var bar: WaveBar = _make_bar(5.0)
	_start(bar)
	Events.wave_progress_changed.emit(0, 0.7)
	Events.wave_cleared.emit(0)
	Events.level_started.emit(0)
	assert_eq(bar.highlighted_index(), -1, "no highlight")
	assert_eq(bar.current_index(), -1, "no current wave")
	for i: int in bar.segment_count():
		assert_eq(bar.target_fill(i), 0.0, "target %d reset" % i)
		assert_eq(bar.displayed_fill(i), 0.0, "segment %d reset" % i)
	Events.wave_started.emit(0, 5)
	assert_eq(bar.segment_count(), 5, "count from the next wave_started")
	await wait_seconds(0.1)
	assert_eq(bar.displayed_fill(0), 0.0, "the old tween is gone")


func test_paused_tree_freezes_the_fill() -> void:
	var bar: WaveBar = _make_bar(0.3)
	assert_eq(bar.process_mode, Node.PROCESS_MODE_PAUSABLE)
	_start(bar)
	Events.wave_progress_changed.emit(0, 1.0)
	await wait_seconds(0.1)
	get_tree().paused = true
	var frozen: float = bar.displayed_fill(0)
	assert_gt(frozen, 0.0, "moving before the pause")
	assert_lt(frozen, 1.0, "not finished before the pause")
	# A SceneTreeTimer runs while paused by default.
	await get_tree().create_timer(0.4).timeout
	assert_eq(bar.displayed_fill(0), frozen, "frozen while paused")
	get_tree().paused = false
	await wait_seconds(0.4)
	assert_almost_eq(bar.displayed_fill(0), 1.0, 0.0001, "resumes on unpause")


# --- Geometry, data and theme --------------------------------------------------

func test_segment_rects_geometry() -> void:
	var rects: Array[Rect2] = WaveBar.segment_rects(3, Vector2(560, 20), 4.0)
	assert_eq(rects.size(), 3)
	var xs: Array[float] = [0.0, 188.0, 376.0]
	for i: int in 3:
		assert_almost_eq(rects[i].position.x, xs[i], 0.0001, "x %d" % i)
		assert_almost_eq(rects[i].size.x, 184.0, 0.0001, "width %d" % i)
		assert_eq(rects[i].position.y, 0.0)
		assert_eq(rects[i].size.y, 20.0)
	assert_almost_eq(rects[2].end.x, 560.0, 0.0001, "fills the width")
	assert_eq(WaveBar.segment_rects(0, Vector2(560, 20), 4.0).size(), 0, "no segments")
	assert_eq(WaveBar.segment_rects(1, Vector2(560, 20), 4.0)[0], Rect2(0, 0, 560, 20), "one segment")


func test_rect_from_data() -> void:
	var bar: WaveBar = _make_bar()
	assert_eq(bar.position, Vector2(Config.num("hud.wave_bar.x"), Config.num("hud.wave_bar.y")))
	assert_eq(bar.size, Vector2(Config.num("hud.wave_bar.width"), Config.num("hud.wave_bar.height")))
	assert_eq(bar.mouse_filter, Control.MOUSE_FILTER_IGNORE, "click-through")


func test_tuning_matches_ux_layout() -> void:
	assert_eq(Config.num("hud.wave_bar.x"), 680.0)
	assert_eq(Config.num("hud.wave_bar.y"), 40.0)
	assert_eq(Config.num("hud.wave_bar.width"), 560.0)
	assert_eq(Config.num("hud.wave_bar.height"), 20.0)
	assert_eq(Config.num("hud.wave_bar.fill_tween_s"), 0.2)


func test_theme_items_and_colours() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	assert_not_null(theme, "theme loads")
	if theme == null:
		return
	assert_eq(theme.get_constant(&"separation", &"WaveBar"), 4, "4 px gaps")
	var track: StyleBoxFlat = theme.get_stylebox(&"track", &"WaveBar") as StyleBoxFlat
	var fill: StyleBoxFlat = theme.get_stylebox(&"fill", &"WaveBar") as StyleBoxFlat
	var highlight: StyleBoxFlat = theme.get_stylebox(&"highlight", &"WaveBar") as StyleBoxFlat
	assert_not_null(track, "track is a StyleBoxFlat")
	assert_not_null(fill, "fill is a StyleBoxFlat")
	assert_not_null(highlight, "highlight is a StyleBoxFlat")
	if track == null or fill == null or highlight == null:
		return
	assert_eq(track.bg_color.to_html(false), "2b3348", "track heartEmpty")
	assert_eq(track.border_color.to_html(false), "2a3b5c", "track border")
	assert_eq(fill.bg_color.to_html(false), "22e6ff", "fill coalition")
	assert_eq(highlight.bg_color.to_html(false), "2b3348", "highlight is the track")
	assert_eq(highlight.border_color.to_html(false), "22e6ff", "highlight coalition outline")
	for box: StyleBoxFlat in [track, highlight]:
		for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			assert_eq(box.get_border_width(side), 1, "1 px outline")
	for box: StyleBoxFlat in [track, fill, highlight]:
		for corner: Corner in [CORNER_TOP_LEFT, CORNER_TOP_RIGHT, CORNER_BOTTOM_RIGHT, CORNER_BOTTOM_LEFT]:
			assert_eq(box.get_corner_radius(corner), 2, "2 px bar corners")


func test_bar_reads_styles_from_its_theme() -> void:
	var bar: WaveBar = _make_bar()
	var theme: Theme = load(THEME_PATH) as Theme
	assert_eq(bar.get_theme_stylebox(&"fill", &"WaveBar"), theme.get_stylebox(&"fill", &"WaveBar"))
	assert_eq(bar.get_theme_constant(&"separation", &"WaveBar"), 4)


func test_source_reads_only_events() -> void:
	var source: String = FileAccess.get_file_as_string(SCRIPT_PATH)
	assert_ne(source, "", "source readable")
	for banned: String in ["get_tree", "get_node", "get_parent", "$", "WaveDirector", "_process", "theme_override", "Color(", "Color."]:
		assert_false(source.contains(banned), "wave_bar.gd must not contain '%s'" % banned)
	for sig: String in ["level_started", "wave_started", "wave_progress_changed", "wave_cleared"]:
		assert_true(source.contains("Events.%s.connect" % sig), "connects Events.%s" % sig)
