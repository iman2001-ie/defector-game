class_name CollisionLayers
## Physics layer bits, matching layer_names/2d_physics in project.godot and the
## architecture's layer table. Scenes keep numeric values in .tscn; tests check
## them against these constants.

const PLAYER: int = 1
const PLAYER_SHOTS: int = 2
const ENEMIES: int = 4
const ENEMY_SHOTS: int = 8
const ASTEROIDS: int = 16
const PICKUPS: int = 32
const CONVOY: int = 64
const ALLIES: int = 128

## What player (and ally) shots detect.
const MASK_PLAYER_SHOTS: int = ENEMIES | ASTEROIDS | CONVOY
## What enemy shots detect.
const MASK_ENEMY_SHOTS: int = PLAYER | ASTEROIDS | CONVOY
