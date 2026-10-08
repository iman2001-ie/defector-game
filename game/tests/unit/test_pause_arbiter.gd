extends GutTest
## PauseArbiter: reason set -> tree.paused, the derived mouse mode and the resumed signal.


func after_each() -> void:
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _assert_paused(expected: bool, msg: String) -> void:
	assert_eq(PauseArbiter.is_paused(), expected, "is_paused: " + msg)
	assert_eq(get_tree().paused, expected, "tree.paused: " + msg)


func test_starts_unpaused() -> void:
	_assert_paused(false, "no reasons")


func test_process_mode_always() -> void:
	assert_eq(PauseArbiter.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_pause_stack_two_reasons() -> void:
	PauseArbiter.push(&"menu")
	PauseArbiter.push(&"story")
	PauseArbiter.pop(&"menu")
	_assert_paused(true, "story still active after popping menu")
	PauseArbiter.pop(&"story")
	_assert_paused(false, "all reasons popped")


func test_duplicate_push_needs_single_pop() -> void:
	PauseArbiter.push(&"menu")
	PauseArbiter.push(&"menu")
	_assert_paused(true, "pushed twice")
	PauseArbiter.pop(&"menu")
	_assert_paused(false, "single pop clears a duplicated reason")


func test_pop_unknown_reason_is_noop() -> void:
	PauseArbiter.pop(&"death")
	_assert_paused(false, "popping a never-pushed reason while unpaused")
	PauseArbiter.push(&"menu")
	PauseArbiter.pop(&"death")
	_assert_paused(true, "popping a never-pushed reason keeps others")


func test_clear_removes_all() -> void:
	PauseArbiter.push(&"menu")
	PauseArbiter.push(&"story")
	PauseArbiter.clear()
	_assert_paused(false, "after clear")


func test_default_gameplay_mouse_mode_is_visible() -> void:
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE)


func test_mouse_mode_follows_pause_state() -> void:
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_CONFINED_HIDDEN, "no reasons")
	PauseArbiter.push(&"story")
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "any reason")
	PauseArbiter.pop(&"story")
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_CONFINED_HIDDEN, "reason popped")


func test_gameplay_mode_set_while_paused_stays_visible() -> void:
	PauseArbiter.push(&"death")
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "reason active")
	PauseArbiter.pop(&"death")
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_CONFINED_HIDDEN, "reason popped")


# --- resumed --------------------------------------------------------------------

func test_resumed_once_on_last_pop() -> void:
	watch_signals(PauseArbiter)
	PauseArbiter.push(&"menu")
	assert_signal_not_emitted(PauseArbiter, "resumed", "not on push")
	PauseArbiter.pop(&"menu")
	assert_signal_emit_count(PauseArbiter, "resumed", 1)


func test_resumed_not_on_pop_while_another_reason_remains() -> void:
	PauseArbiter.push(&"story")
	PauseArbiter.push(&"menu")
	watch_signals(PauseArbiter)
	PauseArbiter.pop(&"menu")
	assert_signal_not_emitted(PauseArbiter, "resumed", "story still active")
	PauseArbiter.pop(&"story")
	assert_signal_emit_count(PauseArbiter, "resumed", 1)


func test_resumed_not_on_pop_while_unpaused() -> void:
	watch_signals(PauseArbiter)
	PauseArbiter.pop(&"menu")
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	assert_signal_not_emitted(PauseArbiter, "resumed")


func test_resumed_once_on_clear_while_paused() -> void:
	PauseArbiter.push(&"menu")
	PauseArbiter.push(&"story")
	watch_signals(PauseArbiter)
	PauseArbiter.clear()
	assert_signal_emit_count(PauseArbiter, "resumed", 1)


func test_resumed_not_on_clear_while_unpaused() -> void:
	watch_signals(PauseArbiter)
	PauseArbiter.clear()
	assert_signal_not_emitted(PauseArbiter, "resumed")


func test_resumed_after_mouse_mode_written() -> void:
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	PauseArbiter.push(&"menu")
	var seen: Array = []
	var probe: Callable = func() -> void:
		seen.append(PauseArbiter.current_mouse_mode())
		seen.append(get_tree().paused)
	PauseArbiter.resumed.connect(probe)
	PauseArbiter.pop(&"menu")
	PauseArbiter.resumed.disconnect(probe)
	assert_eq(seen, [Input.MOUSE_MODE_CONFINED_HIDDEN, false] as Array, "listeners see the gameplay state")


func test_reasons_returns_a_copy() -> void:
	assert_eq(PauseArbiter.reasons(), [] as Array[StringName], "none")
	PauseArbiter.push(&"menu")
	PauseArbiter.push(&"story")
	var reasons: Array[StringName] = PauseArbiter.reasons()
	assert_eq(reasons.size(), 2)
	assert_true(reasons.has(&"menu") and reasons.has(&"story"))
	reasons.clear()
	assert_eq(PauseArbiter.reasons().size(), 2, "editing the copy changes nothing")
