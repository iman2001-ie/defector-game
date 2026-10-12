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
## The level's Convoy (joined in Convoy._ready, Story 6.1).
const CONVOY: StringName = &"convoy"
## The level's ally ship (joined in AllyShip._ready, Story 6.4).
const ALLIES: StringName = &"allies"
## The live boss (the Flagship; joined in Flagship._ready, Story 7.3). Never counted.
const BOSS: StringName = &"boss"
## Wasps the Flagship launched in CORE (joined by Flagship, Story 7.4). Never
## counted: the WaveDirector never connects their `resolved`; F6 frees them.
const BOSS_WASPS: StringName = &"boss_wasps"
