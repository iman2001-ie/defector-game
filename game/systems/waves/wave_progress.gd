class_name WaveProgress
extends RefCounted
## Counts one wave's progress: how many counted enemies it has and how many
## have resolved (killed, or a Maul that ended its dive). Pure logic, no nodes.
##
## Counting can never soft-lock the wave: resolve() never passes the total, a failed
## spawn is subtracted with remove_from_total(), and an empty wave (total 0)
## is complete with ratio 1.0.

var total_counted: int = 0
var resolved: int = 0


## Starts a new wave with `total` counted enemies (negative clamps to 0).
func reset(total: int) -> void:
	total_counted = maxi(total, 0)
	resolved = 0


## Records one resolved enemy. Extra resolves past the total are ignored.
func resolve() -> void:
	resolved = mini(resolved + 1, total_counted)


## Lowers the total by `count` (a spawn that failed), never below 0, and clamps
## resolved to the new total.
func remove_from_total(count: int = 1) -> void:
	total_counted = maxi(total_counted - count, 0)
	resolved = mini(resolved, total_counted)


## Fraction of the wave resolved, 0.0 to 1.0. An empty wave returns 1.0.
func ratio() -> float:
	if total_counted <= 0:
		return 1.0
	return float(resolved) / float(total_counted)


## True when every counted enemy has resolved.
func is_complete() -> bool:
	return resolved == total_counted
