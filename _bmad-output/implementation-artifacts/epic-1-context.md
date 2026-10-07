# Epic 1 Context: Core Feel Prototype

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Prove the core hypothesis before any story work: the player flies a neon ship locked to the mouse cursor, fires lasers and straight-up splash missiles, and blasts Wasps and asteroids in a sandbox where every impact scales with size. The epic also lays the data-driven Godot foundation (autoloads, Config, collision layers, input actions, GUT) that every later epic builds on. It is the go/no-go fun gate: done when the developer says "yes" to "Was the shooting fun on its own?" (amended 2026-10-07 per GDD decision #34: the colleague requirement is waived for Epic 1). The gate has passed. A playtest redesign then added Stories 1.8-1.10, which lock the ship to the cursor, fire the missile straight up, brighten the glow, and bring the architecture doc in line with the code. All three run before Epic 2.

## Stories

- Story 1.1: Set Up the Godot Project and Data-Driven Foundation
- Story 1.2: Fly the Ship with the Mouse (chase and reticle superseded by 1.8)
- Story 1.3: Fire the Laser
- Story 1.4: Shoot Wasps and Asteroids in the Sandbox
- Story 1.5: Fire Aimed Missiles with Splash Damage (aiming and reticle ring superseded by 1.8)
- Story 1.6: Feel Every Impact Scale with Size
- Story 1.7: Validate the Core Feel in a Stress-Tested Sandbox
- Story 1.8: Lock the Ship to the Cursor and Fire Missiles Straight Up
- Story 1.9: Make Laser Bolts and the Neon Glow Brighter
- Story 1.10: Reconcile the Architecture with the As-Built

## Requirements & Constraints

- **Movement (current model):** the ship sits exactly on the cursor in the same physics tick. There is no chase, smoothing or speed cap, and the ship never rotates. The cursor itself is confined to the player zone: full width, y 432-1080 (bottom 60%). If the mouse goes above the zone, the cursor is warped back to the edge so there is no dead travel. On resume from any pause, the cursor is warped to the ship so the ship never jumps. There is no reticle, because the ship is the cursor.
- **Hurtbox:** a 24 px circle centred on a ~96 px cyan/teal ship.
- **Laser:** hold LMB. Twin bolts (the twin is visual only) at 10 bolts/s, 1 damage each, 1800 px/s, straight up, unlimited. Muzzle flash on every shot. No firing while paused.
- **Missile:** RMB fires from the ship's nose straight up at 900 px/s. It deals 8 damage to the target it hits and 3 splash damage to every other enemy or asteroid within 120 px (the hit target takes no splash). 1.5 s cooldown, unlimited ammo, smoke trail.
- **Missile cooldown ring:** drawn on top of the ship and no bigger than it. High-contrast `text` (#E8F4FF) stroke with a dark `background` outline. It sweeps clockwise from 12 o'clock, is hidden when ready, and is driven only by `Events.missile_cooldown_changed(ratio)` (1 = just fired, 0 = ready). Radius and stroke are tunable data.
- **Wasp (sandbox target):** 3 HP, hitbox about 80% of the sprite, magenta/red.
- **Asteroids:** S/M/L are 64/128/224 px, 4/12/30 HP, and drift down at 140/100/60 px/s. They rotate at a random 10-40°/s, never split, and free themselves after exiting the bottom. They block every projectile from both sides, and player shots damage them.
- **Impact tiers:** Small (0.5×, no shake, no hit-stop, spark burst), Medium (1×, 4 px/0.15 s, debris), Large (2×, 8 px/0.25 s, 40 ms hit-stop, shockwave). Explosion SFX volume and pitch scale with the tier. The laser zap has ±5% pitch jitter, and missile launch plays a thump.
- **Performance:** 60 FPS at 1920×1080 on the dev laptop's iGPU with 40 Wasps and the fire button held (frame time under 16.6 ms). Forward+ was kept, and the bench passed with a p99 of about 7 ms. Any visual change must re-run the `--bench=20` check.
- **Glow:** laser bolts must read as bullets, and the overall neon should be slightly brighter but not washed out. The final judgement is made by the operator on an exported build.
- **Tunability:** every GDD number lives in `data/*.json` and is read through `Config`, never hard-coded. Tuning changes are recorded in the GDD decision log.
- **Export:** a Windows export smoke check (run from a folder outside the repo) belongs to this epic, so export problems surface early.

## Technical Decisions

- Godot 4.7.2-stable, statically typed GDScript, Forward+ with `hdr_2d` and `WorldEnvironment` glow. The project lives in `game/`. No runtime plugins; GUT is dev-only and excluded from export.
- **Autoload order:** `Log, Events, Config, GameState, SaveManager, PauseArbiter, Audio, Feedback, EntityRegistry, SceneRouter`. Each autoload is created by the first story that needs it.
- **Collision layers 1-8:** `player, player_shots, enemies, enemy_shots, asteroids, pickups, convoy, allies`. `asteroids` is in the mask of both `player_shots` and `enemy_shots`. Every entity is an `Area2D` with no physics bodies. Projectiles apply damage to what they overlap, then free themselves. Player shots have `monitorable = false`.
- **Anti-tunnelling:** every projectile uses a `CapsuleShape2D` aligned with travel, with height ≥ speed/60 (laser ≥ 30 px, missile ≥ 15 px).
- **Creation:** only `Spawner.spawn_*()` instantiates gameplay entities. It uses scenes preloaded in `EntityRegistry`, and calls `setup(params)` before `add_child` into `World/<Container>`. No pooling.
- **Enemy contract:** `resolved` is emitted exactly once, plus `type_id`, `tier`, `setup`, `apply_damage(amount, source)` and `destroy_by_contact()`. HP comes from `Config.int_("enemies.<id>.hp")`. A death calls `Feedback.impact(tier, pos)`, emits `Events.enemy_killed`, emits `resolved`, then calls `queue_free()`.
- **Pause and time:** only `PauseArbiter` sets `tree.paused` and `mouse_mode`. Gameplay uses `CONFINED_HIDDEN`; any pause reason switches to `VISIBLE`. The Player owns every `warp_mouse` call (zone confinement, resume, and the planned Epic 6 convoy push) and reacts to a resume signal from PauseArbiter. Only `Feedback` sets `Engine.time_scale` (overlapping hit-stops keep the longest remaining) and drives the camera shake. `ShakeCamera` keeps the strongest active shake with linear decay. Spawner and ShakeCamera register with Feedback; this is the accepted design.
- **Config:** typed getters `num`, `int_`, `flag`, `section`. JSON numbers are floats, so counts and HP must go through `int_()`. A missing key logs `Log.error`, asserts, and returns `0`/`false`/`{}`. A `tuning.json` parse failure sets `Config.load_error`. Values are cached in `setup()`/`_ready()` and never read per frame. `Config.reload()` backs the F5 hot-reload. The fixed `tuning.json` sections are listed in the architecture. The glow values live in `render.glow` (intensity, bloom, hdr_threshold) and the scene root applies them on start and on F5. Laser brightness lives in `weapons.laser.glow_energy` / `halo_energy`.
- **ADR-003 fallback:** glow sprites also use an additive `CanvasItemMaterial`, so the neon still reads with the WorldEnvironment glow off or under the Compatibility renderer. Laser bolts use an HDR-bright core (modulate above 1.0) plus a wider additive halo.
- **Audio:** buses Master → Music, SFX, UI. A pool of 12 `AudioStreamPlayer`s that steals the oldest when full. `play_sfx(id, pitch_jitter = DEFAULT_PITCH_JITTER, volume_db = 0.0, pitch = 1.0)`. Each tier row carries `sfx`, `sfx_pitch` and `sfx_volume_db`. `Feedback.prewarm()` spawns one explosion of each tier off-screen at (-1000, 540); the scene root calls it at the end of its `_ready`.
- **Logging:** all logging goes through `Log` with the format `[LEVEL][category] message` and the fixed categories. Never use bare `print()`, and never log in per-frame paths.
- **Debug tools (debug builds only):** F1 overlay (FPS, frame ms, node count, enemies alive) and F5, which runs the validating `Config.reload()` on `tuning.json` and `flags.json`, then restarts the scene (on failure it keeps the previous data and doesn't restart). The `-- --stress` and `--bench=N` command-line modes are used for the perf gate.
- **Input:** code uses action names only (`fire_laser`, `fire_missile`, `ability_shield`, `ability_barrage`, `comms_advance`, `pause`, `toggle_fullscreen`, `debug_*`), never raw keys.
- **Testing:** GUT 9.7.1 runs headless; run `--import` once on a fresh clone. Tests cover pure logic only (config, pause arbiter, the clamp and warp decision as a pure function of the mouse position and bounds, resume-warp, missile direction, ring ratio). Feel is validated by playtest.
- **Export:** Windows Desktop preset with an embedded PCK, the non-resource filter `data/*.json`, and the exclude filter `addons/gut/*, tests/*`. Output goes to `game/export/` (gitignored). Run the `--import` step before the export command.

## UX & Interaction Patterns

- Theme A "Cold Neon": coalition cyan #22E6FF for the player, enemy magenta #FF2BD6 for enemies and their shots, hazard grey-brown with a rim light for asteroids. Depth comes from glow, not shadows. The look is clean neon/vector on a dark space background.
- The persistent HUD stays in the top 120 px band. The player zone (below y 432) stays clear apart from in-world elements such as the cooldown ring.
- Laser bolts are elongated with a bright core and an additive glow. The cooldown ring must read clearly over the ship while lasers fire over explosions.

## Cross-Story Dependencies

- Story 1.1 provides the foundation every other story uses: Config, Log, Events, layers, input actions and GUT.
- `PauseArbiter` arrives in 1.2. `Spawner`/`EntityRegistry` and the projectile contract arrive in 1.3, and the Enemy base in 1.4. `Feedback`/`Audio`/`ShakeCamera` arrive in 1.6, and debug tools and the export preset in 1.7.
- Story 1.8 supersedes the chase movement and reticle from 1.2 and the cursor-aimed missile and reticle ring from 1.5. It removes `player.max_speed`, `chase_ref_*`, `missile_direction`, `weapons.missile.straight_up_within_px` and the reticle files.
- Story 1.9 depends on the ADR-003 additive fallback and re-runs the 1.7 bench. Story 1.10 runs after 1.8 and 1.9 and updates the architecture doc, so that `reticle`, `max_speed`, `chase` and `toward the cursor` only appear in historical notes.
- Later epics build on this: the convoy push-out in Epic 6 must sweep the ship's move against `convoy` and then warp the cursor to the ship. HUD elements must read `Events` only. All of Epic 1 must be finished before Epic 2.
