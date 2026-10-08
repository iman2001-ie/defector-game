class_name Groups
## Scene-tree group names (DW-61). Production code adds to and queries groups
## only through these constants; .tscn files store no groups (every group is
## joined from code), and tests may spell the literals as independent checks.

## The Player (one per gameplay scene).
const PLAYER: StringName = &"player"
## Every Enemy (joined in Enemy._ready).
const ENEMIES: StringName = &"enemies"
## Every Asteroid.
const ASTEROIDS: StringName = &"asteroids"
## Every Projectile (player and enemy shots).
const PROJECTILES: StringName = &"projectiles"
## Every EnergyOrb pickup.
const PICKUPS: StringName = &"pickups"
## Enemies the WaveDirector counts towards the current wave.
const COUNTED: StringName = &"counted"
## The scene's WaveDirector (found by DebugTools).
const WAVE_DIRECTOR: StringName = &"wave_director"
