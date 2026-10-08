extends Node
## Run state that outlives a level scene (architecture State Management, D6).
## SceneRouter writes the fields on scene changes and the level scene writes
## current_level_id once it has resolved its id. Energy logic (Story 3.3):
## add_energy() clamps into 0..max_energy() and emits Events.energy_changed;
## emit_energy() announces the current value (the level does it at start).
## Saving and carry-over arrive with Epic 4.

## Energy carried by the player (0..energy.max). Reset to 0 only by
## SceneRouter.restart_level() and goto_title() (written directly; the reloaded
## level announces it); death itself leaves it alone.
var energy: int = 0
## Level file key of the level being played (data/levels/level_<id>.json, e.g.
## "dev"); "" until a level scene has started.
var current_level_id: String = ""
## True when the current level was entered through a retry (briefings are skipped).
var is_retry: bool = false


## The energy cap (tuning energy.max).
func max_energy() -> int:
	return Config.int_("energy.max")


## Adds `amount` (negative spends), clamps the result into 0..max_energy(),
## always emits Events.energy_changed(energy, max) and returns the new value.
func add_energy(amount: int) -> int:
	var cap: int = maxi(max_energy(), 0)
	energy = clampi(energy + amount, 0, cap)
	Events.energy_changed.emit(energy, cap)
	return energy


## Emits Events.energy_changed with the current value.
func emit_energy() -> void:
	Events.energy_changed.emit(energy, maxi(max_energy(), 0))
