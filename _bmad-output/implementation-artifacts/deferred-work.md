### DW-1: No automated check that the boot [INFO][data] summary line is emitted at INFO level.
origin: spec-deferred e60b6cd07bb5
location: game/autoloads/config.gd:22
source_spec: `spec-1-1-set-up-the-godot-project-and-data-driven-foundation.md`
severity: low
reason: Verification-gap layer: removing _log_summary() from Config._ready() leaves all tests green; the line is only seen by reading GUT output. Capturing Log output needs a sink or last-line hook, which this story does not add.
status: open

### DW-2: The laser bolt scene masks enemies and asteroids (20) but not convoy, while CollisionLayers.MASK_PLAYER_SHOTS and the architecture layer table include convoy (84).
origin: spec-deferred 23f5fc59453c
location: game/entities/projectiles/laser_bolt.tscn:4
source_spec: `spec-1-4-shoot-wasps-and-asteroids-in-the-sandbox.md`
severity: low
reason: game/entities/projectiles/laser_bolt.tscn has collision_mask = 20 (set in Story 1.3; Story 1.4 may not change the laser). game-architecture.md layer table: player_shots mask = enemies, asteroids, convoy; FR33 says convoy ships block every projectile. No convoy exists until Epic 6, so nothing breaks today, but player bolts would pass through convoy ships. test_laser_bolt_masks_enemies_and_asteroids checks single bits only, so the gap is not flagged.
status: open
