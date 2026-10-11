extends GutTest
## ShakeCamera: strongest shake wins, linear decay, random offset in the square,
## pause hold, registration with Feedback.

var _camera: ShakeCamera


func before_each() -> void:
	_camera = ShakeCamera.new()
	add_child_autofree(_camera)
	# Tests drive step() explicitly.
	_camera.set_process(false)


func after_each() -> void:
	Feedback.reset()
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_camera = null


func test_process_mode_always() -> void:
	assert_eq(_camera.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_idle_amplitude_zero() -> void:
	assert_eq(_camera.current_amplitude(), 0.0)
	_camera.step(0.1)
	assert_eq(_camera.offset, Vector2.ZERO)


func test_keep_strongest() -> void:
	_camera.shake(8.0, 0.25)
	_camera.step(0.05)
	_camera.shake(4.0, 0.15)
	assert_almost_eq(_camera.current_amplitude(), 6.4, 0.0001, "weaker shake ignored")
	_camera.step(0.1)
	assert_almost_eq(_camera.current_amplitude(), 3.2, 0.0001, "linear decay")
	_camera.step(0.1)
	assert_eq(_camera.current_amplitude(), 0.0, "idle after 0.25 s")
	assert_eq(_camera.offset, Vector2.ZERO, "offset cleared")


func test_replace_when_stronger_than_remaining() -> void:
	_camera.shake(4.0, 0.15)
	_camera.step(0.1)
	_camera.shake(2.0, 0.2)
	assert_almost_eq(_camera.current_amplitude(), 2.0, 0.0001)


func test_non_positive_ignored() -> void:
	_camera.shake(0.0, 0.5)
	_camera.shake(5.0, 0.0)
	_camera.shake(-3.0, 0.5)
	assert_eq(_camera.current_amplitude(), 0.0)


func test_offset_within_square() -> void:
	_camera.shake(8.0, 0.25)
	var moved: bool = false
	for i: int in 30:
		_camera.step(0.0)
		var amp: float = _camera.current_amplitude()
		assert_lte(absf(_camera.offset.x), amp + 0.0001)
		assert_lte(absf(_camera.offset.y), amp + 0.0001)
		if _camera.offset != Vector2.ZERO:
			moved = true
	assert_true(moved, "jitters")
	assert_almost_eq(_camera.current_amplitude(), 8.0, 0.0001, "zero delta (hit-stop) does not decay")


func test_paused_holds_still_and_keeps_remaining() -> void:
	_camera.shake(8.0, 0.25)
	_camera.step(0.05)
	var amp: float = _camera.current_amplitude()
	PauseArbiter.push(&"menu")
	_camera.step(0.1)
	assert_eq(_camera.offset, Vector2.ZERO, "still while paused")
	assert_almost_eq(_camera.current_amplitude(), amp, 0.0001, "remaining kept")
	PauseArbiter.pop(&"menu")
	_camera.step(0.0)
	assert_almost_eq(_camera.current_amplitude(), amp, 0.0001)
	assert_ne(_camera.offset, Vector2.ZERO, "resumes")


## A long shake so a few slow headless frames can't decay it to 0; the loop
## stops as soon as a frame with a non-zero delta has decayed it.
func test_process_drives_shake() -> void:
	const FRAME_BUDGET: int = 60
	_camera.set_process(true)
	_camera.shake(8.0, 1000.0)
	var frames: int = 0
	while _camera.current_amplitude() >= 8.0 and frames < FRAME_BUDGET:
		await get_tree().process_frame
		frames += 1
	var amp: float = _camera.current_amplitude()
	var off: Vector2 = _camera.offset
	assert_lt(amp, 8.0, "_process decays the shake (amplitude %.4f after %d frames, time_scale %.2f, paused %s)" % [amp, frames, Engine.time_scale, PauseArbiter.is_paused()])
	assert_ne(off, Vector2.ZERO, "_process moves the offset (offset %s, amplitude %.4f, %d frames)" % [off, amp, frames])
	assert_lte(absf(off.x), amp + 0.0001, "offset x inside the square (offset %s, amplitude %.4f)" % [off, amp])
	assert_lte(absf(off.y), amp + 0.0001, "offset y inside the square (offset %s, amplitude %.4f)" % [off, amp])


func test_registers_and_unregisters_with_tree() -> void:
	Feedback.impact(ImpactTier.MEDIUM, Vector2(100, 100))
	assert_almost_eq(_camera.current_amplitude(), 4.0, 0.0001, "registered on entering the tree")
	_camera.step(1.0)
	remove_child(_camera)
	Feedback.impact(ImpactTier.MEDIUM, Vector2(100, 100))
	assert_eq(_camera.current_amplitude(), 0.0, "unregistered on exit")
	_camera.free()


func test_freed_other_camera_does_not_unregister_current() -> void:
	var other: ShakeCamera = ShakeCamera.new()
	add_child(other)
	# `other` registered last; re-register ours, then free `other`.
	Feedback.register_camera(_camera)
	other.free()
	Feedback.impact(ImpactTier.MEDIUM, Vector2(100, 100))
	assert_almost_eq(_camera.current_amplitude(), 4.0, 0.0001)


func test_re_added_camera_registers_again() -> void:
	remove_child(_camera)
	add_child(_camera)
	Feedback.impact(ImpactTier.MEDIUM, Vector2(100, 100))
	assert_almost_eq(_camera.current_amplitude(), 4.0, 0.0001, "registered on re-entering the tree")
