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

### DW-3: A player's straight shot into the grid_4x2 formation hits a bottom-row Wasp and splashes nothing, so the missile does not "burst a formation" from the ship's firing position.
origin: spec-deferred 4b2e391514c6
location: game/data/tuning.json weapons.missile.splash_radius_px; game/entities/projectiles/missile.gd apply_splash
source_spec: `spec-1-5-fire-aimed-missiles-with-splash-damage.md`
severity: medium
reason: The missile centre at contact with the Wasp at (880, 280) from below sits at about y 305-318 (Wasp hitbox radius ~25.6 px plus the 12 px capsule half-height). From there the top-row Wasp at (880, 160) is about 145-158 px away and the bottom-row neighbours about 164 px away, all beyond splash_radius_px 120. Only a top-row hit (the spec's staged Formation row, fired from inside the grid) splashes a neighbour. The numbers are the GDD's tuning (splash_radius_px 120, grid_4x2 spacing 160 x 120), so fixing it means a tuning or design decision for the Story 1.7 core-feel playtest, not a code change in this story.
status: open

### DW-4: The off-screen pre-warm at x = -1000 may be culled by the renderer, so particle and additive-material shaders might not actually compile before the first real explosion.
origin: spec-deferred 3daa68d1eac9
location: game/autoloads/feedback.gd prewarm(); game/entities/effects/explosion.tscn visibility_rect
source_spec: `spec-1-6-feel-every-impact-scale-with-size.md`
reason: Feedback.prewarm() spawns explosions at (-1000, 540); every GPUParticles2D has visibility_rect Rect2(-200,-200,400,400), scaled at most 4x, so each explosion lies wholly outside the viewport. If culled canvas items are never drawn, no pipeline compiles and the first real impact can still hitch. Headless tests only count nodes and positions, so they cannot settle it. Would settle: a Story 1.7 frame-time check of the first large explosion on the dev laptop (with and without pre-warm). The x = -1000 position is mandated by the architecture and the story's acceptance criteria.
status: open

### DW-5: Nothing caps live explosions; each one builds three GPUParticles2D nodes plus a ring, and double feedback and missile splash multiply them.
origin: spec-deferred ffc60527d303
location: game/autoloads/feedback.gd impact(); game/entities/effects/explosion.tscn
source_spec: `spec-1-6-feel-every-impact-scale-with-size.md`
reason: Every Feedback.impact spawns a full Explosion (Burst, Sparks, Debris, Shockwave) that lives until LIFETIME_S, with no pooling (ruled out by the spec) and no budget. A kill makes two impacts (projectile + death), and splash chains add more. Headless tests cannot measure GPU cost. Would settle: the Story 1.7 stress test, frame time with many simultaneous kills on the dev laptop.
status: open

### DW-6: A fresh clone cannot run the GUT suite until the project has been imported once with --import.
origin: spec-deferred e212d1529e2f
location: AGENTS.md section 3 (test command); game/autoloads/audio.gd preloads
source_spec: `spec-1-6-feel-every-impact-scale-with-size.md`
severity: medium
reason: Verified in a clean git-archive copy with no game/.godot: Audio's preload of the five WAVs fails, then every class_name type is missing, and the suite errors out. The baseline 01325de copy also fails (no class_name cache before --import), so the root cause predates this story. After --headless --path game --import, all 240 tests pass. The fix is to add the --import step before the test command in AGENTS.md (an agent-context file).
status: open
