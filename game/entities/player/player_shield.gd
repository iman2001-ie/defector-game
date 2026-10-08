class_name PlayerShield
extends Node
## The Player's shield state (DW-55; the `Shield` child, Story 3.4 behaviour).
##
## raise() puts the shield up for abilities.shield.duration_s (not at all when
## that is 0) and shows the ShieldBubble. step(delta) counts it down from physics
## delta, so it freezes under pause and hit-stop, updating the bubble; on the
## tick it runs out the bubble hides and `ended` fires once. drop() clears it at
## once without `ended`. The Player owns the energy spend, denial, death and the
## contact re-check; this node has no global events.

## The shield ran out (not emitted by drop).
signal ended

## The ShieldBubble drawn while the shield is up (resolved once in _ready).
@export var bubble: NodePath

## Energy cost (abilities.shield.cost, at least 0).
var cost: int = 0
## Seconds the shield lasts (abilities.shield.duration_s, at least 0).
var duration_s: float = 0.0

var _active: bool = false
var _remaining: float = 0.0
var _bubble: ShieldBubble


func _ready() -> void:
	_bubble = get_node_or_null(bubble) as ShieldBubble
	if _bubble == null:
		Log.error("combat", "PlayerShield '%s' is missing its bubble; the shield is not drawn" % name)
	cost = maxi(Config.int_("abilities.shield.cost"), 0)
	duration_s = maxf(Config.num("abilities.shield.duration_s"), 0.0)


## True while the shield is up.
func is_active() -> bool:
	return _active


## Seconds of shield left (0 when down).
func remaining() -> float:
	return _remaining if _active else 0.0


## Puts the shield up for duration_s and shows the bubble. The caller decides
## whether it may (an active shield is never stacked or refreshed by the Player).
func raise() -> void:
	_active = duration_s > 0.0
	_remaining = duration_s
	if _bubble != null:
		_bubble.show_remaining(remaining())


## One shield tick: counts down by `delta`; on the tick it runs out, drops the
## shield and emits `ended`.
func step(delta: float) -> void:
	if not _active:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		drop()
		ended.emit()
		return
	if _bubble != null:
		_bubble.show_remaining(_remaining)


## Drops the shield at once and hides the bubble, without `ended`.
func drop() -> void:
	_active = false
	_remaining = 0.0
	if _bubble != null:
		_bubble.hide_bubble()
