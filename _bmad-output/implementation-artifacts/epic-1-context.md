# Epic 1 Context: Core Feel Prototype

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Prove the core hypothesis of DEFECTOR before any story or campaign work: flying the ship with the mouse, streaming lasers and landing aimed missiles on Wasps and asteroids feels good on its own, with every impact scaled by the size of what was hit. The epic also lays the data-driven foundation (Godot project, logging, event bus, tuning config, tests) that every later epic builds on. It ends with a go/no-go fun gate: the developer and at least one colleague must answer "yes" to "Was the shooting fun on its own?" and a 40-Wasp stress test must hold 60 FPS.

## Stories

- Story 1.1: Set Up the Godot Project and Data-Driven Foundation
- Story 1.2: Fly the Ship with the Mouse
- Story 1.3: Fire the Laser
- Story 1.4: Shoot Wasps and Asteroids in the Sandbox
- Story 1.5: Fire Aimed Missiles with Splash Damage
- Story 1.6: Feel Every Impact Scale with Size
- Story 1.7: Validate the Core Feel in a Stress-Tested Sandbox

## Requirements & Constraints

- **Ship:** chases the cursor without snapping (capped at `player.max_speed`, 1400 px/s; a 150 px move takes about 0.12 s), never rotates, clamped to full width and y 432–1080. Hurtbox is a 24 px circle on a ~96 px sprite. During gameplay the OS cursor is hidden and confined, and a reticle marks it.
- **Laser (LMB held):** 10 bolts/s, twin visual but one damage instance per bolt, 1 damage, 1800 px/s straight up, unlimited. No fire while paused.
- **Missile (RMB):** flies along the ship-to-cursor vector at 900 px/s (straight up if the cursor is within 32 px). 8 damage to the hit target and 3 splash to every *other* enemy or asteroid within 120 px. 1.5 s cooldown, unlimited ammo, radial cooldown ring on the reticle.
- **Asteroids:** S/M/L = 64/128/224 px, 4/12/30 HP, 140/100/60 px/s downward, random 10–40°/s spin. They never split, free themselves after exiting the bottom, and block projectiles from both sides (player shots damage them).
- **Wasp (sandbox target):** 3 HP, hitbox about 80% of the sprite, magenta/red. The sandbox respawns the formation when it is cleared and spawns random-size asteroids at intervals.
- **Impact feel:** Small = 0.5x explosion, no shake or hit-stop, spark burst. Medium = 1x, 4 px / 0.15 s shake, debris. Large = 2x, 8 px / 0.25 s, 40 ms hit-stop, debris and shockwave ring. Weapons get a muzzle flash on every shot, a laser zap with ±5% pitch jitter, a missile launch thump, a smoke trail and a medium-tier explosion on impact.
- **Friendly fire must be impossible** by layer and mask design.
- **Performance:** 60 FPS at 1920x1080 on the dev laptop's integrated GPU. Stress test is 40 Wasps plus held fire with frame time under 16.6 ms.
- **Every GDD number is first-pass tuning.** It lives in data, never in code, and tuning changes are recorded in the GDD decision log.
- **Statically typed GDScript** with no runtime plugins (GUT is dev-only).

## Technical Decisions

- **Project:** Godot 4.7.2-stable in `game/`, Forward+. Settings: 1920x1080, fullscreen, stretch `canvas_items` / aspect `keep`, `hdr_2d = true`, custom user dir `DEFECTOR`, file logging on (release too), `untyped_declaration` = Warn. Use the folder skeleton from the architecture (`autoloads/ core/ entities/ systems/ scenes/ ui/ data/ assets/ tests/`), with each feature's `.tscn` and `.gd` kept together.
- **Autoload order:** `Log, Events, Config, GameState, SaveManager, PauseArbiter, Audio, Feedback, EntityRegistry, SceneRouter`. Each one is created by the first story that needs it: Log/Events/Config in 1.1, PauseArbiter in 1.2, EntityRegistry in 1.3, Feedback/Audio in 1.6.
- **Collision layers (exact):** 1 player, 2 player_shots, 3 enemies, 4 enemy_shots, 5 asteroids, 6 pickups, 7 convoy, 8 allies.
  - player masks enemies, asteroids, pickups, convoy.
  - player_shots masks enemies, asteroids, convoy, and has `monitorable = false`.
  - enemy_shots masks player, asteroids, convoy.
- **Damage rule:** all entities are `Area2D`. Projectiles apply damage to what they overlap (`apply_damage(amount, source)` if the method exists), call the `_on_impact` hook, then `queue_free()`. The Player applies its own contact damage.
- **Anti-tunnelling:** each projectile uses a `CapsuleShape2D` aligned with travel, with height >= speed / 60 (laser >= 30 px, missile >= 15 px). Projectiles free themselves outside a bounds rect slightly larger than the playfield.
- **Entity creation:** only `Spawner.spawn_*()` instantiates gameplay entities. It takes scenes preloaded in `EntityRegistry`, calls `setup(params)` before `add_child` into the right `World/<Container>`, and does no pooling. `setup()` stores values and `_ready()` applies them.
- **Enemy contract** (`core/enemy.gd`):
  - `signal resolved`, emitted exactly once.
  - `type_id`, `tier`, `setup()`, `apply_damage()` (records `source.from_ally`), `destroy_by_contact()`.
  - HP via `Config.int_("enemies.<type_id>.hp")`.
  - On death: `Feedback.impact(tier, pos)`, then `Events.enemy_killed`, then `resolved`, then `queue_free()`.
- **Config:**
  - JSON in `res://data/`. `tuning.json` has the fixed sections `player, weapons, abilities, energy, drops, enemies, boss, asteroids, convoy, allies, waves, comms, feedback, damage`. `flags.json` has `surrender_prompts, isolde_interruptions, tarek_fall` (true) and `hunter_wasp` (false).
  - Read values only through the typed getters `num/int_/flag/section`, never `Config.tuning[...]`. A missing key logs an error with the key path, asserts in debug, and returns 0/false/{}.
  - JSON numbers are floats, so counts and HP go through `int_()`.
  - Cache values in `setup()`/`_ready()` and never read them per frame.
  - A `tuning.json` parse failure sets `Config.load_error` for a boot or title scene to display.
- **Pause and time:** only `PauseArbiter` sets `tree.paused` (from a reason set with `push/pop/is_paused/clear`) and the mouse mode: `CONFINED_HIDDEN` in gameplay, `VISIBLE` when any reason is active. Only `Feedback` sets `Engine.time_scale` (overlapping hit-stops keep the longest remaining; restore uses a process-always, time-scale-ignoring timer) and the camera shake.
- **Feedback:**
  - `core/impact_tier.gd` defines the enum `SMALL, MEDIUM, LARGE, BOSS_PART, BOSS_DEATH, PLAYER_HIT, PLAYER_DEATH`. The tier table lives in `tuning.json` under `feedback.tiers`.
  - `ShakeCamera` registers with `Feedback` on `_ready` and unregisters on `_exit_tree`. It keeps the strongest active shake with linear decay and runs process-always, but it respects `PauseArbiter`.
  - Each level-type scene pre-warms one explosion of each tier off-screen (x = -1000) at load.
- **Audio:** `Master` bus feeding `Music`, `SFX` and `UI` buses. `Audio.play_sfx(id, pitch_jitter, volume_db)` uses a pool of 12 non-positional `AudioStreamPlayer`s and steals the oldest when full. Each tier maps to an SFX id plus pitch and volume offsets from tuning.
- **Events:** `events.gd` holds the full typed signal catalogue from the architecture, with no logic. New global signals go there first. Epic 1 uses `enemy_killed`, `asteroid_destroyed` and `missile_cooldown_changed(ratio)` (1 = just fired, 0 = ready).
- **Logging:** `Log.info/warn/error/debug(category, msg)` prints `[LEVEL][category] message`. ERROR and WARN also call `push_error`/`push_warning`, and DEBUG is dropped in release. Categories are fixed (`boot, scene, wave, beat, comms, spawn, combat, save, audio, data, debug`). No per-frame logging and no bare `print()`.
- **Input:** code uses action names only: `fire_laser` LMB, `fire_missile` RMB, `ability_shield` E, `ability_barrage` Q, `comms_advance` LMB, `pause` Esc, `toggle_fullscreen` F11, and `debug_overlay` through `debug_unlock_all` on F1–F7.
- **Conventions:**
  - Everything is statically typed and indented with tabs.
  - Anything with a collision shape moves in `_physics_process`.
  - Positions are in 1920x1080 playfield coordinates; use `get_global_mouse_position()`.
  - Free nodes with `queue_free()` only.
  - Gameplay timers are pausable (`create_timer(t, false)`).
  - Groups: `enemies, counted, asteroids, allies, pickups, projectiles`.
- **Debug tools:** active only when `OS.is_debug_build()`. One `DebugTools` node: F1 toggles an overlay (FPS, frame ms, node count, enemies alive) and F5 reloads all JSON and restarts the sandbox.
- **Renderer fallback:** neon comes from `hdr_2d` plus `WorldEnvironment` glow, but glow sprites also use additive `CanvasItemMaterial` so the look survives a switch to the Compatibility renderer. If the stress test fails, switch to Compatibility and record the decision in the GDD decision log.
- **Tests:** GUT 9.7.1 (`godot_4_7` branch) in `addons/gut/`, run headless. Tests cover pure logic and data only (`test_config`, `test_pause_arbiter` in this epic); feel is verified by playtest.
- **Export smoke check (end of epic):** Windows Desktop preset with the `data/*.json` non-resource filter, excluding `addons/gut/*` and `tests/*`, exporting to the gitignored `game/export/`. The exe must launch from a folder outside the repo, load tuning and render the glow.
- **Assets:** free or CC0 only, Kenney packs first, and every one credited in `game/assets/CREDITS.md`.

## UX & Interaction Patterns

- **Palette:**
  - Player and Coalition: cyan `#22E6FF`.
  - Enemies and all enemy projectiles: magenta `#FF2BD6`.
  - Asteroids: jagged, cratered grey-brown `#7A6E62` with a `#C9D8E8` rim light. Never smooth or round.
  - Background: `#05070F`.
- **Reticle:** drawn exactly at the cursor, so the ship trails it while moving. It is a 32 px cyan ring. The missile cooldown arc (4 px stroke, radius 22 px, muted `#93A7C2`, drawn with `draw_arc`) sweeps clockwise from 12 o'clock while reloading.
- **Ship sprites** must read as spaceships: Kenney Space Shooter Redux hulls, recoloured.
- **Layout zones:** the top 120 px band is reserved for the persistent HUD; the enemy zone is y 120–432 and the player zone y 432–1080. Nothing persistent is drawn in the player zone.

## Cross-Story Dependencies

- Story 1.1 must come first: every story relies on its project settings, layers, input actions, `Log`/`Events`/`Config` and GUT.
- Story 1.2 creates the sandbox scene (temporarily the main scene) with a `World` node mirroring the level tree's containers, plus `PauseArbiter`.
- Story 1.3 introduces `Projectile`, `Spawner` and `EntityRegistry`. Stories 1.4 and 1.5 spawn through them.
- Story 1.4 introduces the `Enemy` base and asteroids. Story 1.5's splash and Story 1.6's tiers act on them.
- Story 1.6 adds `Feedback`/`Audio`/`ShakeCamera`. Earlier entities and projectiles should route impacts only through `Feedback.impact(tier, pos)`.
- Story 1.7 depends on everything above. Epic 5 may not start until its fun gate passes.
- Later epics build directly on this: the Wave Director (Epic 2) uses `Spawner` and the `resolved` contract, and hearts and energy (Epic 3) extend the Player and the `Events` catalogue.
