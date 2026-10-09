extends Node
## Run state that outlives a level scene (architecture State Management, D6).
## SceneRouter writes the fields on scene changes and the level scene writes
## current_level_id once it has resolved its id. Energy logic (Story 3.3):
## add_energy() clamps into 0..max_energy() and emits Events.energy_changed;
## emit_energy() announces the current value (the level does it at start).
## Story 4.2: energy carries into the next level, highest_unlocked_level tracks
## progression, and SaveManager persists both (only on a level clear, through
## SceneRouter.complete_level()); SceneRouter.goto_title() restores them from
## the save.

## Energy carried by the player (0..energy.max). Reset to 0 only by
## SceneRouter.restart_level() (written directly; the reloaded level announces
## it) and restored from the save by goto_title(); death itself leaves it alone.
var energy: int = 0
## Level file key of the level being played (data/levels/level_<id>.json, e.g.
## "dev"); "" until a level scene has started.
var current_level_id: String = ""
## True when the current level was entered through a retry (briefings are skipped).
var is_retry: bool = false
## The highest campaign level the player may start (1..progression.level_count).
## Raised by SceneRouter.complete_level(), restored from the save by goto_title().
var highest_unlocked_level: int = 1
## Debug F7: every level counts as unlocked. In memory only: never saved and
## never reset by goto_title(); PLAY still continues the real progress.
var all_levels_unlocked: bool = false
## Story 5.8: control hints shown this session; never saved or reset. The HUD
## HintPill adds a hint id when the hint starts showing and never queues a
## recorded one again, so retries, restarts and the title don't repeat it.
var shown_hints: Dictionary[StringName, bool] = {}


## True when level `n` may be started (Story 4.3's Level Select): the F7 debug
## flag is on or n <= highest_unlocked_level.
func is_level_unlocked(n: int) -> bool:
	return all_levels_unlocked or n <= highest_unlocked_level


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
