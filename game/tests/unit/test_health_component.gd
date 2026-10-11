extends GutTest
## HealthComponent (DW-55): hearts floored at 0, i-frames counted from step(delta)
## with the flicker target toggled at flicker_hz, and the damaged / died /
## iframes_ended signals in order, and the max clamped to at least 1 (DW-72).
## Driven on a bare node with a Sprite2D target.

const IFRAMES_S: float = 1.0
const FLICKER_HZ: float = 10.0

var _health: HealthComponent
var _sprite: Sprite2D
var _order: Array[String] = []


func before_each() -> void:
	_order.clear()
	_sprite = Sprite2D.new()
	add_child_autofree(_sprite)
	_health = HealthComponent.new()
	add_child_autofree(_health)
	_health.setup(5, IFRAMES_S, FLICKER_HZ, _sprite)
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	_health.iframes_ended.connect(_on_iframes_ended)
	watch_signals(_health)


func _on_damaged(current: int, max_value: int) -> void:
	_order.append("damaged %d/%d iframing=%s" % [current, max_value, _health.is_iframing()])


func _on_died() -> void:
	_order.append("died")


func _on_iframes_ended() -> void:
	_order.append("iframes_ended")


func test_setup_fills_hearts() -> void:
	assert_eq(_health.max_value, 5)
	assert_eq(_health.current, 5)
	assert_false(_health.is_iframing())
	assert_true(_health.can_take(1))


func test_non_lethal_hit_starts_iframes_after_damaged() -> void:
	_health.take(1)
	assert_eq(_health.current, 4)
	assert_true(_health.is_iframing(), "i-frames running")
	assert_eq(_order, ["damaged 4/5 iframing=false"] as Array[String], "damaged fires before the i-frames start")
	assert_signal_not_emitted(_health, "died")
	assert_true(_sprite.visible, "visible at the hit")


func test_lethal_hit_floors_and_dies_without_iframes() -> void:
	_health.current = 1
	_health.take(3)
	assert_eq(_health.current, 0, "floored at 0")
	assert_false(_health.is_iframing(), "no i-frames on death")
	assert_eq(_order, ["damaged 0/5 iframing=false", "died"] as Array[String])
	assert_signal_emit_count(_health, "died", 1)


func test_ignored_hits() -> void:
	assert_false(_health.can_take(0))
	assert_false(_health.can_take(-2))
	_health.take(0)
	_health.take(-2)
	assert_eq(_health.current, 5)
	_health.current = 0
	assert_false(_health.can_take(1), "nothing to take at 0")
	_health.take(1)
	assert_eq(_health.current, 0)
	assert_signal_not_emitted(_health, "damaged")
	assert_signal_not_emitted(_health, "died")


func test_hit_during_iframes_is_ignored() -> void:
	_health.take(1)
	assert_false(_health.can_take(1))
	_health.take(1)
	assert_eq(_health.current, 4)
	assert_signal_emit_count(_health, "damaged", 1)


func test_flicker_phase() -> void:
	_health.take(1)
	_health.step(0.03)
	assert_true(_sprite.visible, "first half of the 0.1 s cycle: on")
	_health.step(0.04)
	assert_false(_sprite.visible, "second half: off")
	_health.step(0.05)
	assert_true(_sprite.visible, "next cycle: on")
	_health.step(0.04)
	assert_false(_sprite.visible, "off again")


func test_iframes_end_once_and_restore_the_target() -> void:
	_health.take(1)
	_health.step(0.07)
	assert_false(_sprite.visible)
	_health.step(IFRAMES_S)
	assert_false(_health.is_iframing())
	assert_true(_sprite.visible, "target restored")
	assert_signal_emit_count(_health, "iframes_ended", 1)
	_health.step(IFRAMES_S)
	assert_signal_emit_count(_health, "iframes_ended", 1, "only once")
	assert_true(_health.can_take(1), "hittable again")


func test_step_without_iframes_does_nothing() -> void:
	_health.step(0.07)
	assert_true(_sprite.visible)
	assert_signal_not_emitted(_health, "iframes_ended")


func test_zero_iframes_leaves_none() -> void:
	_health.setup(5, 0.0, FLICKER_HZ, _sprite)
	_health.take(1)
	assert_eq(_health.current, 4)
	assert_false(_health.is_iframing())
	assert_true(_health.can_take(1))


func test_stop_iframes() -> void:
	_health.take(1)
	_health.step(0.07)
	_health.stop_iframes()
	assert_false(_health.is_iframing())
	assert_true(_sprite.visible, "target restored")
	assert_signal_not_emitted(_health, "iframes_ended", "stopping is not an expiry")


## DW-72: a max below 1 would leave the owner silently unhittable; it logs a data
## error naming the value and counts as 1.
func test_zero_max_clamps_to_one_and_logs() -> void:
	_health.setup(0, IFRAMES_S, FLICKER_HZ, _sprite)
	assert_push_error("got max hearts 0")
	assert_eq(_health.max_value, 1)
	assert_eq(_health.current, 1)
	assert_true(_health.can_take(1), "hittable")


func test_negative_max_clamps_to_one_and_logs() -> void:
	_health.setup(-3, IFRAMES_S, FLICKER_HZ, _sprite)
	assert_push_error("got max hearts -3")
	assert_eq(_health.max_value, 1)
	assert_eq(_health.current, 1)
	assert_true(_health.can_take(1), "hittable")


func test_positive_max_logs_nothing() -> void:
	_health.setup(1, IFRAMES_S, FLICKER_HZ, _sprite)
	assert_push_error_count(0, "a max of 1 is valid")
	assert_eq(_health.max_value, 1)
