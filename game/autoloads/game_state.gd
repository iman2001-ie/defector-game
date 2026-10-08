extends Node
## Run state that outlives a level scene (architecture State Management, D6).
## Fields only, no logic: SceneRouter writes them on scene changes and the
## level scene writes current_level_id once it has resolved its id. Energy
## logic (clamp, energy_changed, orbs) arrives with Story 3.3, saving with Epic 4.

## Energy carried by the player (0..100). Reset to 0 only by
## SceneRouter.restart_level() and goto_title(); death itself leaves it alone.
var energy: int = 0
## Level file key of the level being played (data/levels/level_<id>.json, e.g.
## "dev"); "" until a level scene has started.
var current_level_id: String = ""
## True when the current level was entered through a retry (briefings are skipped).
var is_retry: bool = false
