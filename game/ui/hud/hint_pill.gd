class_name HintPill
extends Control
## The centre-low control-hint pill (Story 5.8, FR66, UX "Control hint" /
## "Hint pill"): a fully rounded `surfaceAlt` pill with the key part in `energy`
## gold and the action part in the text colour, e.g. `[RMB] MISSILE`.
##
## Driven only by Events (the HUD rule):
## - hint_requested(&"move_fire" | &"missile") from the WaveDirector `hint`
##   action queues `move` then `fire`, or `missile`; an unknown id logs a
##   warning and shows nothing.
## - energy_changed queues `shield` / `barrage` when a value reaches
##   abilities.shield.cost / abilities.barrage.cost (shield first when both do).
## - player_moved / player_action dismiss the showing hint when they are its
##   action: `move` after ui.hint_pill.move_dismiss_px of cumulative movement,
##   `fire` on a laser bolt, `missile` / `shield` / `barrage` on their action.
##   An action counts only while its hint is the one showing (not fading).
##
## One pill at a time: a hint fades in over fade_in_s; show_s after it started
## showing (or on its action) it fades out over fade_out_s, then the next queued
## hint shows. Once per session: a hint is recorded in GameState.shown_hints
## when it starts showing, and a shown, showing or queued hint is never queued
## again, so retries (scene reloads) never repeat it; a hint that was only
## queued when the scene reloaded can still show later. A level with
## "teach_controls": true (Level 1) clears GameState.shown_hints at its start,
## so its hints show on every run (playtest 2026-10-13).
##
## Never pauses and never touches PauseArbiter or the comms. PAUSABLE: the fade
## tweens (created on the pill, default pause mode) and the show_s Timer child
## freeze under any pause. Mouse-transparent (MOUSE_FILTER_IGNORE on it and every
## child). Built in code: a Panel holding the Key and Action Labels; the pill's
## own rect is the pill (centred on the playfield, vertical centre at center_y).
## Styling comes from the Theme type `HintPill` (styles/panel, colors/key,
## colors/text, font_sizes/text); layout and timing from `ui.hint_pill`, cached
## in _ready.

const THEME_TYPE: StringName = &"HintPill"
const STYLE_PANEL: StringName = &"panel"
const COLOR_KEY: StringName = &"key"
const COLOR_TEXT: StringName = &"text"
const FONT_SIZE_TEXT: StringName = &"text"

const HINT_MOVE: StringName = &"move"
const HINT_FIRE: StringName = &"fire"
const HINT_MISSILE: StringName = &"missile"
const HINT_SHIELD: StringName = &"shield"
const HINT_BARRAGE: StringName = &"barrage"

## The UI copy per hint: [key part, action part] (UX Voice and Tone).
const COPY: Dictionary = {
	&"move": ["", "MOVE THE MOUSE TO FLY"],
	&"fire": ["[HOLD LMB]", "FIRE"],
	&"missile": ["[RMB]", "MISSILE"],
	&"shield": ["[E]", "SHIELD"],
	&"barrage": ["[Q]", "BARRAGE"],
}
## hint_requested id -> the hints it queues, in order.
const REQUESTS: Dictionary = {
	&"move_fire": [&"move", &"fire"],
	&"missile": [&"missile"],
}
## player_action -> the hint it dismisses (the move hint uses player_moved).
const ACTION_HINTS: Dictionary = {
	&"laser": &"fire",
	&"missile": &"missile",
	&"shield": &"shield",
	&"barrage": &"barrage",
}

## `ui.hint_pill` numbers (cached in _ready).
var center_y: float = 0.0
var pill_h: float = 0.0
var padding_px: float = 0.0
var gap_px: float = 0.0
var fade_in_s: float = 0.0
var fade_out_s: float = 0.0
var show_s: float = 0.0
var move_dismiss_px: float = 0.0

var _shield_cost: int = 0
var _barrage_cost: int = 0
var _showing: StringName = &""
var _queue: Array[StringName] = []
var _fading: bool = false
var _moved: float = 0.0
var _fade_tween: Tween = null
var _font_px: int = 0

var _panel: Panel
var _key: Label
var _action: Label
var _timer: Timer


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	center_y = Config.num("ui.hint_pill.center_y")
	pill_h = maxf(Config.num("ui.hint_pill.h"), 1.0)
	padding_px = maxf(Config.num("ui.hint_pill.padding_px"), 0.0)
	gap_px = maxf(Config.num("ui.hint_pill.gap_px"), 0.0)
	fade_in_s = maxf(Config.num("ui.hint_pill.fade_in_s"), 0.0)
	fade_out_s = maxf(Config.num("ui.hint_pill.fade_out_s"), 0.0)
	show_s = maxf(Config.num("ui.hint_pill.show_s"), 0.0)
	move_dismiss_px = maxf(Config.num("ui.hint_pill.move_dismiss_px"), 0.0)
	_shield_cost = Config.int_("abilities.shield.cost")
	_barrage_cost = Config.int_("abilities.barrage.cost")
	_build()
	_apply_theme()
	visible = false
	Events.hint_requested.connect(_on_events_hint_requested)
	Events.energy_changed.connect(_on_events_energy_changed)
	Events.player_moved.connect(_on_events_player_moved)
	Events.player_action.connect(_on_events_player_action)


# --- Read accessors (tests) ------------------------------------------------------

## The hint on screen (also while it fades out); &"" when none.
func showing_hint() -> StringName:
	return _showing


## The hints waiting for the pill (a copy).
func queued() -> Array[StringName]:
	return _queue.duplicate()


## True while the showing hint fades out.
func is_fading() -> bool:
	return _fading


func key_text() -> String:
	return _key.text


func action_text() -> String:
	return _action.text


func key_color() -> Color:
	return _key.get_theme_color(&"font_color")


func action_color() -> Color:
	return _action.get_theme_color(&"font_color")


func font_px() -> int:
	return _font_px


## Seconds left on the show_s clock (0 when it isn't running).
func time_left() -> float:
	return 0.0 if _timer.is_stopped() else _timer.time_left


# --- Events ----------------------------------------------------------------------

func _on_events_hint_requested(hint_id: StringName) -> void:
	if not REQUESTS.has(hint_id):
		Log.warn("hint", "Unknown hint request '%s'; nothing shown" % hint_id)
		return
	for hint: StringName in REQUESTS[hint_id]:
		_enqueue(hint)


func _on_events_energy_changed(current_energy: int, _max_energy: int) -> void:
	if current_energy >= _shield_cost:
		_enqueue(HINT_SHIELD)
	if current_energy >= _barrage_cost:
		_enqueue(HINT_BARRAGE)


func _on_events_player_moved(distance_px: float) -> void:
	if _showing != HINT_MOVE or _fading:
		return
	_moved += distance_px
	if _moved >= move_dismiss_px:
		_dismiss()


func _on_events_player_action(action: StringName) -> void:
	if _showing.is_empty() or _fading:
		return
	if ACTION_HINTS.get(action, &"") == _showing:
		_dismiss()


# --- Internals ---------------------------------------------------------------------

## Queues `hint` unless it was shown this session, is showing or is queued;
## shows it at once when the pill is free.
func _enqueue(hint: StringName) -> void:
	if GameState.shown_hints.has(hint) or hint == _showing or _queue.has(hint):
		return
	_queue.append(hint)
	Log.debug("hint", "Hint '%s' queued" % hint)
	_show_next()


## Shows the next queued hint when no hint is on screen.
func _show_next() -> void:
	if not _showing.is_empty() or _queue.is_empty():
		return
	var hint: StringName = _queue.pop_front()
	_showing = hint
	_moved = 0.0
	GameState.shown_hints[hint] = true
	var copy: Array = COPY[hint]
	_key.text = str(copy[0])
	_action.text = str(copy[1])
	_layout()
	visible = true
	_kill_fade()
	if fade_in_s > 0.0:
		modulate.a = 0.0
		_fade_tween = create_tween()
		_fade_tween.tween_property(self, ^"modulate:a", 1.0, fade_in_s)
	else:
		modulate.a = 1.0
	if show_s > 0.0:
		_timer.start(show_s)
	Log.info("hint", "Hint '%s' shown" % hint)


## Starts the fade-out of the showing hint (its action, or the show_s clock).
func _dismiss() -> void:
	if _showing.is_empty() or _fading:
		return
	_fading = true
	_timer.stop()
	_kill_fade()
	Log.debug("hint", "Hint '%s' dismissed" % _showing)
	if fade_out_s <= 0.0:
		_on_faded_out()
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, ^"modulate:a", 0.0, fade_out_s)
	_fade_tween.finished.connect(_on_faded_out)


func _on_faded_out() -> void:
	_fade_tween = null
	_fading = false
	_showing = &""
	visible = false
	modulate.a = 1.0
	_show_next()


func _on_timer_timeout() -> void:
	_dismiss()


func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


## The Panel (full pill) with the Key and Action Labels, and the show_s Timer.
func _build() -> void:
	_panel = Panel.new()
	_panel.name = "Panel"
	_key = Label.new()
	_key.name = "Key"
	_action = Label.new()
	_action.name = "Action"
	for child: Control in [_panel, _key, _action]:
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for label: Label in [_key, _action]:
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_panel.add_child(label)
	add_child(_panel)
	_timer = Timer.new()
	_timer.name = "ShowTimer"
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)


## Sizes the pill to its text: padding, key, gap (only with a key), action,
## padding; centred horizontally on the playfield with its vertical centre at
## center_y.
func _layout() -> void:
	var key_w: float = _text_width(_key)
	var action_w: float = _text_width(_action)
	var gap: float = gap_px if key_w > 0.0 else 0.0
	var w: float = padding_px * 2.0 + key_w + gap + action_w
	position = Vector2((Playfield.SIZE.x - w) / 2.0, center_y - pill_h / 2.0)
	size = Vector2(w, pill_h)
	_panel.position = Vector2.ZERO
	_panel.size = size
	_key.visible = key_w > 0.0
	_key.position = Vector2(padding_px, 0.0)
	_key.size = Vector2(key_w, pill_h)
	_action.position = Vector2(padding_px + key_w + gap, 0.0)
	_action.size = Vector2(action_w, pill_h)


func _text_width(label: Label) -> float:
	if label.text.is_empty():
		return 0.0
	var font: Font = label.get_theme_font(&"font")
	if font == null:
		return 0.0
	return ceilf(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_px).x)


## Copies the HintPill theme items onto the children (their own theme types
## are Panel / Label).
func _apply_theme() -> void:
	_panel.add_theme_stylebox_override(&"panel", get_theme_stylebox(STYLE_PANEL, THEME_TYPE))
	_key.add_theme_color_override(&"font_color", get_theme_color(COLOR_KEY, THEME_TYPE))
	_action.add_theme_color_override(&"font_color", get_theme_color(COLOR_TEXT, THEME_TYPE))
	_font_px = get_theme_font_size(FONT_SIZE_TEXT, THEME_TYPE)
	if _font_px <= 0:
		_font_px = get_theme_default_font_size()
	for label: Label in [_key, _action]:
		label.add_theme_font_size_override(&"font_size", _font_px)
