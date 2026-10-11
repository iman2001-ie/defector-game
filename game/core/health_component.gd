class_name HealthComponent
extends Node
## Hearts and i-frames for one owner (DW-55; the Player's `Health` child).
##
## setup() fills `current` to `max_value` (a max below 1 logs an error and counts
## as 1, so the owner is never silently unhittable; DW-72). take(amount) floors
## `current` at 0, emits `damaged`, then either emits `died` (at 0) or starts
## `iframes_s` of i-frames. I-frame time accumulates from step(delta), so it
## freezes whenever the owner stops ticking it; meanwhile only the flicker target
## blinks at `flicker_hz` (visible for the first half of each cycle). On the tick
## they run out the target is restored and `iframes_ended` fires once. The owner
## keeps every other invulnerability rule and all global events; this node has none.

## A hit landed: `current` after the hit (0 on the lethal one), out of max_value.
signal damaged(current: int, max_value: int)
## The hit that brought `current` to 0 (after `damaged`).
signal died
## The i-frames ran out (not emitted by stop_iframes).
signal iframes_ended

## Hearts left (0..max_value).
var current: int = 0
## Hearts after setup().
var max_value: int = 0

var _iframes_s: float = 0.0
var _flicker_hz: float = 0.0
var _flicker_target: CanvasItem
var _iframe_active: bool = false
var _iframe_elapsed: float = 0.0


## Sets the hearts to `p_max_value` and the i-frame tuning; negative times and
## rates count as 0. A `p_max_value` below 1 logs a data error and is used as 1.
## `flicker_target` may be null (no flicker).
func setup(p_max_value: int, iframes_s: float, flicker_hz: float, flicker_target: CanvasItem) -> void:
	var hearts: int = p_max_value
	if hearts < 1:
		Log.error("data", "HealthComponent '%s' got max hearts %d (must be at least 1); using 1" % [name, p_max_value])
		hearts = 1
	max_value = hearts
	current = hearts
	_iframes_s = maxf(iframes_s, 0.0)
	_flicker_hz = maxf(flicker_hz, 0.0)
	_flicker_target = flicker_target
	_iframe_active = false
	_iframe_elapsed = 0.0


## True when a hit of `amount` would land: amount > 0, hearts left, no i-frames.
func can_take(amount: int) -> bool:
	return amount > 0 and current > 0 and not _iframe_active


## Costs `amount` hearts (see the class doc); ignored when can_take is false.
func take(amount: int) -> void:
	if not can_take(amount):
		return
	current = maxi(current - amount, 0)
	damaged.emit(current, max_value)
	if current == 0:
		died.emit()
		return
	_iframe_active = _iframes_s > 0.0
	_iframe_elapsed = 0.0
	_set_target_visible(true)


## One i-frame tick: advances the window by `delta` and flickers the target.
func step(delta: float) -> void:
	if not _iframe_active:
		return
	_iframe_elapsed += delta
	if _iframe_elapsed >= _iframes_s:
		_iframe_active = false
		_set_target_visible(true)
		iframes_ended.emit()
		return
	_set_target_visible(fmod(_iframe_elapsed * _flicker_hz, 1.0) < 0.5)


## True while the i-frames run.
func is_iframing() -> bool:
	return _iframe_active


## Ends the i-frames at once and restores the target, without `iframes_ended`.
func stop_iframes() -> void:
	_iframe_active = false
	_set_target_visible(true)


func _set_target_visible(value: bool) -> void:
	if _flicker_target != null:
		_flicker_target.visible = value
