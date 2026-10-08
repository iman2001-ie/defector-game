extends GutTest
## PlayerShield (DW-55): the shield state and countdown on a bare node with a
## ShieldBubble. raise() shows the bubble for duration_s, step(delta) counts it
## down and emits `ended` once on expiry, drop() clears it silently.

const DT: float = 1.0 / 60.0
## Fixed duration for the countdown tests (above 1 s and the bubble blink window).
const DURATION_S: float = 4.0

var _shield: PlayerShield
var _bubble: ShieldBubble
## duration_s as read from Config in _ready, before the override.
var _tuned_duration_s: float = 0.0


func before_each() -> void:
	var root: Node = Node.new()
	_bubble = ShieldBubble.new()
	_bubble.name = "ShieldBubble"
	root.add_child(_bubble)
	_shield = PlayerShield.new()
	_shield.bubble = NodePath("../ShieldBubble")
	root.add_child(_shield)
	add_child_autofree(root)
	_tuned_duration_s = _shield.duration_s
	_shield.duration_s = DURATION_S
	watch_signals(_shield)


func test_reads_tuning() -> void:
	assert_eq(_shield.cost, Config.int_("abilities.shield.cost"))
	assert_eq(_tuned_duration_s, maxf(Config.num("abilities.shield.duration_s"), 0.0))
	assert_false(_shield.is_active())
	assert_eq(_shield.remaining(), 0.0)
	assert_false(_bubble.visible)


func test_raise_shows_the_bubble() -> void:
	_shield.raise()
	assert_true(_shield.is_active())
	assert_eq(_shield.remaining(), _shield.duration_s)
	assert_true(_bubble.visible)


func test_step_counts_down_and_expires_once() -> void:
	_shield.raise()
	_shield.step(1.0)
	assert_true(_shield.is_active())
	assert_almost_eq(_shield.remaining(), _shield.duration_s - 1.0, 0.0001)
	var t: float = 1.0
	while t < _shield.duration_s + DT:
		_shield.step(DT)
		t += DT
	assert_false(_shield.is_active())
	assert_eq(_shield.remaining(), 0.0)
	assert_false(_bubble.visible, "bubble hidden")
	assert_signal_emit_count(_shield, "ended", 1)
	_shield.step(DT)
	assert_signal_emit_count(_shield, "ended", 1, "only once")


func test_step_while_down_does_nothing() -> void:
	_shield.step(DT)
	assert_false(_shield.is_active())
	assert_signal_not_emitted(_shield, "ended")


func test_zero_duration_is_not_active() -> void:
	_shield.duration_s = 0.0
	_shield.raise()
	assert_false(_shield.is_active())
	assert_eq(_shield.remaining(), 0.0)
	assert_false(_bubble.visible)


func test_drop_clears_silently() -> void:
	_shield.raise()
	_shield.drop()
	assert_false(_shield.is_active())
	assert_eq(_shield.remaining(), 0.0)
	assert_false(_bubble.visible, "bubble hidden")
	assert_signal_not_emitted(_shield, "ended", "dropping is not an expiry")
