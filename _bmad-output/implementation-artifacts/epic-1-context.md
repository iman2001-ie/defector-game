# Epic 1 Context: Core Feel Prototype

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Prove the core hypothesis of DEFECTOR before any story or campaign work: flying the ship with the mouse, streaming lasers and firing missiles at Wasps and asteroids feels good on its own, with every impact scaled by the size of what was hit. The epic also lays the data-driven foundation (Godot project, logging, event bus, tuning config, tests) that every later epic builds on. The fun gate (Story 1.7) passed and Forward+ held the 40-Wasp stress test. The playtest then changed the design: the ship now sits exactly on the cursor, the missile fires straight up, the reticle is removed and the glow is brighter. Stories 1.8–1.10 apply these changes and bring the architecture doc in line with the code, so that Epic 2 is built against the final movement and patterns.

## Stories

- Story 1.1: Set Up the Godot Project and Data-Driven Foundation
- Story 1.2: Fly the Ship with the Mouse (partly superseded by 1.8)
- Story 1.3: Fire the Laser
- Story 1.4: Shoot Wasps and Asteroids in the Sandbox
- Story 1.5: Fire Aimed Missiles with Splash Damage (partly superseded by 1.8)
- Story 1.6: Feel Every Impact Scale with Size
- Story 1.7: Validate the Core Feel in a Stress-Tested Sandbox
- Story 1.8: Lock the Ship to the Cursor and Fire Missiles Straight Up
- Story 1.9: Make Laser Bolts and the Neon Glow Brighter
- Story 1.10: Reconcile the Architecture with the As-Built

## Requirements & Constraints

- **Movement:**
  - The ship sits exactly on the cursor in the same physics tick. There is no chase, smoothing, speed cap or lag.
  - It never rotates. It is clamped to x 0–1920 and y `player.bounds_y` (432–1080).
  - The 24 px hurtbox circle is unchanged.
- **Cursor:**
  - During gameplay the cursor is hidden and confined to the player zone.
  - Godot can only confine to the window, so when the cursor goes above the zone it is warped back to the zone edge. Moving back down responds immediately, with no dead travel.
  - On resume from any pause, the cursor is warped to the ship, so the ship never jumps.
- **Laser (LMB held):** 10 bolts/s. Each bolt is a twin visual but deals one damage instance of 1 damage. Bolts travel straight up at 1800 px/s, ammo is unlimited, and nothing fires while paused.
- **Missile (RMB):**
  - Fires from the ship's nose, always straight up (`Vector2.UP`), at 900 px/s.
  - Deals 8 damage to the target it hits and 3 splash damage to every other enemy or asteroid within 120 px.
  - 1.5 s cooldown, unlimited ammo.
- **Asteroids:**
  - Sizes S/M/L are 64/128/224 px, with 4/12/30 HP, falling at 140/100/60 px/s and spinning at a random 10–40°/s.
  - They never split.
  - They block projectiles from both sides.
- **Wasp (sandbox target):** 3 HP, with a hitbox about 80% of the sprite.
- **Impact tiers:**
  - Small: 0.5x scale, no shake.
  - Medium: 1x scale, 4 px / 0.15 s shake.
  - Large: 2x scale, 8 px / 0.25 s shake, 40 ms hit-stop, shockwave.
  - Explosion volume scales with the tier through `sfx_volume_db`.
- **Glow (Story 1.9):**
  - Bolts must read as bullets: an HDR core above 1.0 plus a wider additive halo.
  - The whole scene should be slightly brighter than the baseline (intensity 0.8, bloom 0.05, threshold 0.6) without washing out. This is judged on an exported build.
- **Performance:** 60 FPS at 1080p on the dev laptop iGPU. `--bench=20` p99 must stay under 16.6 ms (it was 7.01 ms before the glow change).
- **No hard-coded GDD numbers.** Every GDD number is first-pass tuning in data. Tuning changes go in the GDD decision log.
- **Friendly fire** must be impossible by layer and mask design.

## Technical Decisions

- **Engine:** Godot 4.7.2, Forward+ (kept; the ADR-003 Compatibility fallback was not needed). `hdr_2d` plus WorldEnvironment glow, with additive `CanvasItemMaterial` so the look survives without the glow.
  - Glow values now live in `tuning.json` under `render.glow` and are applied by the scene root, so F5 can reload them.
  - Laser brightness is data too, for example `weapons.laser.glow_energy`.
- **Removed tuning keys:**
  - `player.max_speed`
  - `player.chase_ref_distance_px`
  - `player.chase_ref_time_s`
  - `weapons.missile.straight_up_within_px`
- **Removed code:**
  - the chase solver code and its tests
  - `missile_direction`
  - `reticle.tscn` / `reticle.gd`
- **Ownership rules:**
  - Only `PauseArbiter` sets `tree.paused` and `mouse_mode`.
  - The Player owns every `warp_mouse` call (zone confinement, resume, and later the convoy push), reacting to a PauseArbiter resume signal.
  - Only `Feedback` touches `Engine.time_scale`.
  - Only `Spawner.spawn_*()` creates entities, using `setup()` before `add_child`.
  - Logging goes through `Log`.
- **Cooldown ring:**
  - It is a Player child drawn above the ship sprite with `draw_arc`.
  - It is driven only by `Events.missile_cooldown_changed(ratio)`, where 1 means just fired and 0 means ready.
- **Config:**
  - Read values only through the typed getters `num/int_/flag/section`, and cache them in `setup()`/`_ready()`. Counts and HP go through `int_()`.
  - `Config.reload()` backs the F5 reload.
- **Collision layers:** 1 player, 2 player_shots, 3 enemies, 4 enemy_shots, 5 asteroids, 6 pickups, 7 convoy, 8 allies.
  - Both shot layers mask asteroids.
  - player_shots has `monitorable = false`.
- **Projectiles and enemies:**
  - Projectiles use a `CapsuleShape2D` with height at least speed / 60 and free themselves outside the playfield bounds.
  - Enemies follow the `Enemy` contract (`resolved` emitted once, `apply_damage`, `destroy_by_contact`).
  - Every impact goes through `Feedback.impact(tier, pos)`.
- **Architecture doc (Story 1.10):** `game-architecture.md` must document what was actually built:
  - the `play_sfx` pitch parameter and the tier `sfx_volume_db`
  - the single explosion scene
  - Spawner and ShakeCamera registering with Feedback
  - the `-- --stress` and `--bench=N` modes
  - the `Playfield` class and the `PlayerWeapons` split
  - `Config.reload()`
  - the cursor lock, zone confinement and resume-warp owner
  - the ring on the ship
  - `render.glow`
  - the export command, with the `--import` step first

  Also add an "As-built reconciliation" note at the end. Afterwards, `reticle`, `max_speed`, `chase` and `toward the cursor` may appear only in historical notes.
- **Tests:** GUT runs headless and covers pure logic only. For 1.8, the tests cover:
  - the one-tick clamped lock
  - the zone clamp and the cursor-warp decision, as a pure function of the mouse position and bounds
  - the resume warp
  - the straight-up missile direction
  - the ring ratio handling

## UX & Interaction Patterns

- **Palette:** player cyan `#22E6FF`, enemies and enemy shots magenta `#FF2BD6`, asteroids `#7A6E62` with a `#C9D8E8` rim, background `#05070F`.
- **No reticle.** The ship is the cursor.
- **Missile cooldown ring (`missileRing` token):**
  - Drawn over the ship, with a radius no larger than half the ship's size (first pass 36 px).
  - A 5 px stroke in `text` `#E8F4FF` with a 2 px `background` outline. The radius and stroke are tunable data.
  - Sweeps clockwise from 12 o'clock over the remaining fraction, hides when ready, and freezes while paused.
  - Must read clearly over the hull and over explosions.
- **Layout zones:** the top 120 px are the HUD band, the enemy zone is y 120–432 and the player zone is y 432–1080.

## Cross-Story Dependencies

- Stories 1.1–1.7 are done. Run 1.8, then 1.9, then 1.10, all before Epic 2.
- Story 1.10 depends on 1.8 and 1.9 so that it documents the final code. When it is done, it closes the deferred-work items DW-11 and DW-17.
- The Epic 1 retrospective is re-run after Story 1.10.
- Later stories build on the 1.8 rules:
  - Story 4.4: on resume, the cursor is back on the ship.
  - Story 4.5: the lock and zone confinement hold under letterbox, because warps use viewport coordinates.
  - Story 6.1: the convoy push sweeps the ship's move and then warps the cursor to the ship.
- With the missile fixed straight up, the risk of splash vs `grid_4x2` spacing (DW-3) is watched in Epic 2 playtests.
