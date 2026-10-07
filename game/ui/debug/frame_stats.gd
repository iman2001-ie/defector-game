class_name FrameStats
extends RefCounted
## Fixed-capacity frame-time samples (ms). add() never allocates: the buffer is
## preallocated and samples past capacity are ignored. percentile_ms() sorts a
## copy, so call it only at report time.

var _samples: PackedFloat32Array = PackedFloat32Array()
var _count: int = 0
var _sum: float = 0.0
var _max: float = 0.0


func _init(capacity: int) -> void:
	_samples.resize(maxi(capacity, 0))


func add(ms: float) -> void:
	if _count >= _samples.size():
		return
	_samples[_count] = ms
	_count += 1
	_sum += ms
	if ms > _max:
		_max = ms


func clear() -> void:
	_count = 0
	_sum = 0.0
	_max = 0.0


func count() -> int:
	return _count


func average_ms() -> float:
	if _count == 0:
		return 0.0
	return _sum / _count


func max_ms() -> float:
	return _max


## Nearest-rank percentile, p in 0..100. 0 when empty.
func percentile_ms(p: float) -> float:
	if _count == 0:
		return 0.0
	var sorted: PackedFloat32Array = _samples.slice(0, _count)
	sorted.sort()
	var rank: int = clampi(ceili(clampf(p, 0.0, 100.0) / 100.0 * _count), 1, _count)
	return sorted[rank - 1]
