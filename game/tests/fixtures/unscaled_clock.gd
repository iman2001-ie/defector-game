extends RefCounted
## Test helper for real-time checks of a time-scale-ignoring tween (the music
## fade). Just after engine start the unscaled clock jumps (over a second in
## one frame), which ends a 0.5 s fade in a single frame when the test runs
## first or alone. Not a test script (GUT only collects `test_`-prefixed files)
## and has no class_name: preload it by path.

static var _settled: bool = false


## Waits (once per run) until a time-scale-ignoring tween on `node` steps in
## line with the frame delta for 3 frames in a row. Returns false if it never
## does within 300 frames, so the caller can fail loudly.
static func settle(node: Node) -> bool:
	if _settled:
		return true
	var probe: Tween = node.create_tween()
	probe.set_ignore_time_scale(true)
	probe.tween_interval(3600.0)
	var steady: int = 0
	var last: float = probe.get_total_elapsed_time()
	for i: int in 300:
		await node.get_tree().process_frame
		var step: float = probe.get_total_elapsed_time() - last
		last = probe.get_total_elapsed_time()
		steady = steady + 1 if step <= node.get_process_delta_time() * 2.0 + 0.005 else 0
		if steady >= 3:
			_settled = true
			break
	probe.kill()
	return _settled
