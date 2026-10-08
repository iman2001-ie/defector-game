class_name WaspDiveClock
extends Node
## Formation-wide Wasp dive cadence (GDD: "every 3-5 s one Wasp dives").
##
## Every random enemies.wasp.dive_interval_s (min..max) it tells one random
## holding, living Wasp to start its dive (telegraph first). With no holding
## Wasp it just draws the next interval. A child of WaveDirector in level.tscn;
## process_mode inherits, so it freezes with the game. The sandbox has none.

## Interval draws and Wasp picks; tests seed it.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _min_s: float = 0.0
var _max_s: float = 0.0
var _left: float = 0.0
## Reused per tick so a dive tick allocates only the group scan.
var _candidates: Array[Wasp] = []


func _ready() -> void:
	_min_s = Config.num("enemies.wasp.dive_interval_s.min")
	_max_s = Config.num("enemies.wasp.dive_interval_s.max")
	_left = _draw()


func _physics_process(delta: float) -> void:
	step(delta)


## Advances the clock by `delta` seconds; on the deadline, one holding Wasp dives.
func step(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	var wasp: Wasp = _pick()
	if wasp != null:
		wasp.start_dive()
	_left = _draw()


## Seconds until the next dive deadline.
func time_left() -> float:
	return _left


func _draw() -> float:
	return rng.randf_range(_min_s, _max_s)


func _pick() -> Wasp:
	_candidates.clear()
	for node: Node in get_tree().get_nodes_in_group(Groups.ENEMIES):
		var wasp: Wasp = node as Wasp
		if wasp != null and wasp.is_holding() and not wasp.is_dead() and not wasp.is_queued_for_deletion():
			_candidates.append(wasp)
	if _candidates.is_empty():
		return null
	var picked: Wasp = _candidates[rng.randi_range(0, _candidates.size() - 1)]
	_candidates.clear()
	return picked
