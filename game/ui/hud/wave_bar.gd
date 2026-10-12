class_name WaveBar
extends Control
## The segmented wave progress bar at the top centre of the HUD (UX `waveBar`,
## UX-DR1/DR2). One segment per wave of the level.
##
## Driven only by Events: level_started resets it, wave_started sets the
## segment count and the current wave (earlier segments are full),
## wave_progress_changed fills the current segment and wave_cleared fills it
## completely and highlights the next segment during the gap between waves.
## Fills tween over `hud.wave_bar.fill_tween_s` and never go down within an
## attempt. The tween is bound to this pausable node, so it freezes with the game.
##
## Boss fight (Story 7.3): Events.boss_started fades the whole bar out over
## `hud.boss_bar.fade_s` while the BossBar fades in over the same slot;
## level_started brings it back at once.
##
## Colours, outline, corners and the gap come from the shared Theme
## (`ui/theme/defector_theme.tres`, type `WaveBar`); position, size and the
## tween time come from Config.

const THEME_TYPE: StringName = &"WaveBar"
const STYLE_TRACK: StringName = &"track"
const STYLE_FILL: StringName = &"fill"
const STYLE_HIGHLIGHT: StringName = &"highlight"
const CONST_SEPARATION: StringName = &"separation"

var fill_tween_s: float = 0.0
## The boss-bar cross-fade time (hud.boss_bar.fade_s).
var boss_fade_s: float = 0.0

## Fill each segment is heading for (0..1).
var _target: Array[float] = []
## Fill each segment shows right now (0..1); trails _target while a tween runs.
var _displayed: Array[float] = []
var _current: int = -1
var _highlight: int = -1
var _tween: Tween
## Segment the running tween animates; -1 when none.
var _tween_index: int = -1
var _fade_tween: Tween


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	position = Vector2(Config.num("hud.wave_bar.x"), Config.num("hud.wave_bar.y"))
	size = Vector2(Config.num("hud.wave_bar.width"), Config.num("hud.wave_bar.height"))
	fill_tween_s = maxf(Config.num("hud.wave_bar.fill_tween_s"), 0.0)
	boss_fade_s = maxf(Config.num("hud.boss_bar.fade_s"), 0.0)
	Events.level_started.connect(_on_events_level_started)
	Events.wave_started.connect(_on_events_wave_started)
	Events.wave_progress_changed.connect(_on_events_wave_progress_changed)
	Events.wave_cleared.connect(_on_events_wave_cleared)
	Events.boss_started.connect(_on_events_boss_started)


# --- Read accessors (tests) ------------------------------------------------------

func segment_count() -> int:
	return _target.size()


## The wave being fought (0-based); -1 before the first wave_started.
func current_index() -> int:
	return _current


## The segment highlighted between waves; -1 when none.
func highlighted_index() -> int:
	return _highlight


func target_fill(index: int) -> float:
	return _target[index] if index >= 0 and index < _target.size() else 0.0


func displayed_fill(index: int) -> float:
	return _displayed[index] if index >= 0 and index < _displayed.size() else 0.0


## `count` equal-width segments with `gap` px between them, filling `bar_size`.
static func segment_rects(count: int, bar_size: Vector2, gap: float) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if count <= 0:
		return rects
	var width: float = (bar_size.x - gap * float(count - 1)) / float(count)
	for i: int in count:
		rects.append(Rect2(float(i) * (width + gap), 0.0, width, bar_size.y))
	return rects


# --- Drawing -------------------------------------------------------------------

func _draw() -> void:
	var count: int = segment_count()
	if count == 0:
		return
	var fill: StyleBox = get_theme_stylebox(STYLE_FILL, THEME_TYPE)
	var gap: float = float(get_theme_constant(CONST_SEPARATION, THEME_TYPE))
	var rects: Array[Rect2] = segment_rects(count, size, gap)
	for i: int in count:
		var rect: Rect2 = rects[i]
		draw_style_box(get_theme_stylebox(style_for(i), THEME_TYPE), rect)
		var filled: Rect2 = fill_rect(rect, _displayed[i])
		if filled.has_area():
			draw_style_box(fill, filled)


## Background style of segment `index`: the highlight between waves, else the track.
func style_for(index: int) -> StringName:
	return STYLE_HIGHLIGHT if index == _highlight else STYLE_TRACK


## The filled part of a segment `rect` showing `shown` (0..1); zero-size when empty.
static func fill_rect(rect: Rect2, shown: float) -> Rect2:
	if shown <= 0.0:
		return Rect2(rect.position, Vector2.ZERO)
	return Rect2(rect.position, Vector2(rect.size.x * minf(shown, 1.0), rect.size.y))


# --- Events ----------------------------------------------------------------------

func _on_events_level_started(_level_id: int) -> void:
	_stop_tween()
	_stop_fade()
	modulate.a = 1.0
	for i: int in segment_count():
		_target[i] = 0.0
		_displayed[i] = 0.0
	_current = -1
	_highlight = -1
	queue_redraw()


func _on_events_wave_started(wave_index: int, wave_count: int) -> void:
	if wave_count <= 0 or wave_index < 0 or wave_index >= wave_count:
		return
	_finish_tween()
	var old_count: int = segment_count()
	if wave_count != old_count:
		_target.resize(wave_count)
		_displayed.resize(wave_count)
		for i: int in range(old_count, wave_count):
			_target[i] = 0.0
			_displayed[i] = 0.0
	# Earlier waves are done (also covers skipped waves).
	for i: int in wave_index:
		_target[i] = 1.0
		_displayed[i] = 1.0
	_current = wave_index
	_highlight = -1
	queue_redraw()


func _on_events_wave_progress_changed(wave_index: int, ratio: float) -> void:
	if wave_index != _current or wave_index < 0 or wave_index >= segment_count():
		return
	_raise_target(wave_index, ratio)


func _on_events_wave_cleared(wave_index: int) -> void:
	if wave_index != _current or wave_index < 0 or wave_index >= segment_count():
		return
	_raise_target(wave_index, 1.0)
	var next: int = wave_index + 1 if wave_index + 1 < segment_count() else -1
	if next != _highlight:
		_highlight = next
		queue_redraw()


## The boss arrived: fade the bar out (the BossBar fades in over it).
func _on_events_boss_started() -> void:
	_stop_fade()
	if boss_fade_s <= 0.0:
		modulate.a = 0.0
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, ^"modulate:a", 0.0, boss_fade_s)


func _stop_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


# --- Fill animation ------------------------------------------------------------

## Raises segment `index`'s target to `ratio` (clamped) and tweens its fill
## there. A lower ratio is ignored, so the bar never goes back.
func _raise_target(index: int, ratio: float) -> void:
	var value: float = clampf(ratio, 0.0, 1.0)
	if value <= _target[index]:
		return
	_target[index] = value
	if _tween_index != index:
		_finish_tween()
	else:
		_stop_tween()
	if fill_tween_s <= 0.0:
		_set_displayed(value, index)
		return
	_tween_index = index
	_tween = create_tween()
	_tween.tween_method(_set_displayed.bind(index), _displayed[index], value, fill_tween_s)
	_tween.finished.connect(_on_tween_finished)


func _set_displayed(value: float, index: int) -> void:
	if index < 0 or index >= _displayed.size():
		return
	var shown: float = maxf(value, _displayed[index])
	if shown != _displayed[index]:
		_displayed[index] = shown
		queue_redraw()


func _on_tween_finished() -> void:
	_tween = null
	_tween_index = -1


## Ends the running tween with its segment at the target.
func _finish_tween() -> void:
	var index: int = _tween_index
	_stop_tween()
	if index >= 0 and index < _target.size():
		_set_displayed(_target[index], index)


## Kills the running tween where it is.
func _stop_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_tween_index = -1
