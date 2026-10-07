# Epic 1 Context: Core Feel Prototype

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Stand up the Godot project and its data-driven foundation, then build a debug sandbox where the player flies the ship with the mouse, fires lasers and aimed missiles, and blasts Wasps and asteroids with impact feedback that scales with size. This proves the core hypothesis ("is the shooting fun on its own?") and is the go/no-go gate for the whole project: Epic 5 must not start until the developer and at least one colleague say yes. It also sets every convention (logging, events, Config, spawning, pause/time ownership, collision layers) that later epics build on.

## Stories

- Story 1.1: Set Up the Godot Project and Data-Driven Foundation
- Story 1.2: Fly the Ship with the Mouse
- Story 1.3: Fire the Laser
- Story 1.4: Shoot Wasps and Asteroids in the Sandbox
- Story 1.5: Fire Aimed Missiles with Splash Damage
- Story 1.6: Feel Every Impact Scale with Size
- Story 1.7: Validate the Core Feel in a Stress-Tested Sandbox

## Requirements & Constraints

- **Movement:** ship chases the cursor in `_physics_process` without snapping, capped at `player.max_speed` (1400 px/s, ~0.12 s for a 150 px move). Never rotates; clamped to full width and y 432–1080. Hurtbox is a 24 px circle on a ~96 px sprite. OS cursor hidden and confined during gameplay; a reticle marks the cursor.
- **Laser (hold LMB):** 10 bolts/s, twin visual but one damage instance, 1 damage, 1800 px/s straight up, unlimited. No firing while paused.
- **Missile (RMB):** along the ship-to-cursor vector (straight up if the cursor is within 32 px), 900 px/s, 8 damage to the hit target plus 3 splash to every other enemy/asteroid within 120 px (no double-dip), 1.5 s cooldown, unlimited, smoke trail, radial cooldown ring on the reticle.
- **Asteroids:** small/medium/large = 64/128/224 px, 4/12/30 HP, 140/100/60 px/s, random 10–40 deg/s spin, never split, free after exiting the bottom, never count toward waves. They block every projectile from both sides; player shots damage them.
- **Wasp (sandbox target):** 3 HP, hitbox ~80% of sprite (the convention for all enemies). Sandbox respawns formations and spawns random asteroids continuously.
- **Feedback tiers:** Small (0.5x, no shake/hit-stop, spark burst), Medium (1x, 4 px/0.15 s, debris), Large (2x, 8 px/0.25 s, 40 ms hit-stop, debris + shockwave ring). Boss and player tiers exist in data but are exercised in later epics. Wasp/small asteroid/laser impact = Small; medium asteroid/missile impact = Medium; large asteroid = Large.
- **Weapon feel:** muzzle flash every shot, laser zap with +/-5% pitch jitter, missile launch thump; placeholder Kenney sounds are fine.
- **Performance:** 60 FPS at 1920x1080 on the dev laptop's iGPU; stress test of 40 Wasps + held fire must stay under 16.6 ms per frame.
- **Tunability:** every GDD number lives in data, never hard-coded. Tuning changes and the renderer decision are recorded in the GDD decision log.
- **Assets:** free/CC0 only (Kenney first), each credited in `game/assets/CREDITS.md`. No plugins in the shipped runtime; GUT is dev-only.
- **Export smoke check (end of epic):** Windows Desktop preset with the `data/*.json` non-resource filter; exported exe runs from a folder outside the repo, loads tuning, and renders glow.

## Technical Decisions

- **Project:** Godot 4.7.2-stable, statically typed GDScript, Forward+, project root `game/`. Settings: 1920x1080, fullscreen, stretch `canvas_items`/`keep`, `hdr_2d = true`, custom user dir `DEFECTOR`, file logging on (release too), `untyped_declaration` = Warn. `game/.gitignore` ignores `.godot/`, `export/`, `*.tmp`. Folder skeleton: `autoloads/ core/ entities/ systems/ scenes/ ui/ data/ assets/ tests/`, hybrid by feature (scene + script together, snake_case files).
- **Autoload order (final):** `Log, Events, Config, GameState, SaveManager, PauseArbiter, Audio, Feedback, EntityRegistry, SceneRouter`. Create each only in the story that first needs it: Epic 1 adds `Log`, `Events`, `Config` (1.1), `PauseArbiter` (1.2), `EntityRegistry` (1.3), `Feedback`, `Audio` (1.6), keeping relative order.
- **Collision layers (exact):** 1 `player`, 2 `player_shots`, 3 `enemies`, 4 `enemy_shots`, 5 `asteroids`, 6 `pickups`, 7 `convoy`, 8 `allies`. Player hurtbox masks enemies/asteroids/pickups (convoy later); `player_shots` mask enemies/asteroids/convoy; `enemy_shots` mask player/asteroids/convoy; asteroids mask nothing. Projectiles on `player_shots` use `monitorable = false`.
- **Input actions only, never raw keys:** `fire_laser` (LMB), `fire_missile` (RMB), `ability_shield` (E), `ability_barrage` (Q), `comms_advance` (LMB), `pause` (Esc), `toggle_fullscreen` (F11), `debug_overlay` ... `debug_unlock_all` (F1–F7).
- **Logging:** `Log.info/warn/error/debug(category, msg)` prints `[LEVEL][category] message`; ERROR/WARN also `push_error`/`push_warning`; DEBUG dropped in release. Fixed categories: `boot, scene, wave, beat, comms, spawn, combat, save, audio, data, debug`. No per-frame logging, no bare `print()`.
- **Events:** `events.gd` holds the full typed signal catalogue from the architecture (no logic) from Story 1.1 onward. New global signals are added there first. Past-tense names for facts, `*_requested` for commands. Use direct calls when exactly one known node must act.
- **Config/data:** `data/tuning.json` with fixed sections `player, weapons, abilities, energy, drops, enemies, boss, asteroids, convoy, allies, waves, comms, feedback, damage`, populated with every GDD number; `data/flags.json` with `surrender_prompts`, `isolde_interruptions`, `tarek_fall` (true), `hunter_wasp` (false). Access only through `Config.num/int_/flag/section` (plus `level`/`sequence` later). JSON numbers are floats: counts and HP go through `Config.int_()`. Missing key: `Log.error` with key path, assert in debug, return `0`/`false`/`{}`. A `tuning.json` parse failure sets `Config.load_error` for display, not a crash. Read tuning in `setup()`/`_ready()` and cache; never per frame. F5 reloads all JSON in debug.
- **Pause/time ownership:** only `PauseArbiter` sets `get_tree().paused` and mouse mode (reason set: `menu, story, final_choice, death`; `push/pop/is_paused/clear`; `CONFINED_HIDDEN` in gameplay, `VISIBLE` when any reason is active). Only `Feedback` sets `Engine.time_scale` (hit-stop: longest remaining wins, restored by a process-always, time-scale-ignoring timer) and the camera offset.
- **Spawning:** only `Spawner` (`core/spawner.gd`, a node in the level/sandbox tree) instantiates gameplay entities. It looks up preloaded scenes in `EntityRegistry`, calls `setup(params)` before `add_child` into the matching `World/<Container>`. `setup()` stores values and `_ready()` applies them. No pooling (ADR-002).
- **Projectile contract** (`class_name Projectile extends Area2D`): moves by velocity in `_physics_process`, frees itself outside the playfield bounds rect, calls `apply_damage(damage, self)` on an overlapped area that has it, runs the `_on_impact` hook (missile overrides it for splash), then `queue_free()`. Anti-tunnelling: `CapsuleShape2D` aligned with travel, height >= speed / 60 (laser >= 30 px, missile >= 15 px).
- **Enemy contract** (`class_name Enemy extends Area2D`): `signal resolved` emitted exactly once, `type_id`, `tier`, `setup(params)`, `apply_damage(amount, source)` (records `source.from_ally`), `destroy_by_contact()`, HP from `Config.int_("enemies.<type_id>.hp")`. Death = `Feedback.impact(tier, pos)` then `Events.enemy_killed`, then `resolved`, then `queue_free()`. Behaviour uses `enum State` + `match` with transitions only via `_enter_state()`.
- **Impact feedback:** `core/impact_tier.gd` enum (`SMALL, MEDIUM, LARGE, BOSS_PART, BOSS_DEATH, PLAYER_HIT, PLAYER_DEATH`); tier rows (scale, shake, hit-stop, extras, sfx id and pitch/volume offsets) live in `tuning.feedback.tiers`. Entities call only `Feedback.impact(tier, position)`. `ShakeCamera` registers with `Feedback` in `_ready`, unregisters in `_exit_tree`, keeps the strongest active shake with linear decay, and runs process-always but respects `PauseArbiter.is_paused()`. Pre-warm one explosion per tier off-screen (x = -1000) when a level-type scene loads.
- **Audio:** buses Master -> Music, SFX, UI; pool of 12 `AudioStreamPlayer`s (non-positional) that steals the oldest when full; `Audio.play_sfx(id, pitch_jitter := 0.05, volume_db := 0.0)`.
- **Rendering (ADR-003):** neon via `hdr_2d` + `WorldEnvironment` glow, but glow sprites also use additive `CanvasItemMaterial` so switching to Compatibility is a one-setting fallback if the stress test fails.
- **Boundaries:** autoloads never reference scene nodes by path (nodes register themselves); no absolute node paths or `get_parent()` chains; `queue_free()` only; gameplay timers are pausable (`create_timer(t, false)`); use `get_global_mouse_position()`; `_physics_process` for anything with a collision shape.
- **Tests:** GUT 9.7.1 (`godot_4_7` branch) in `game/addons/gut/`, dev-only and excluded from export. Epic 1 adds `tests/unit/test_config.gd` and `tests/unit/test_pause_arbiter.gd`. Run headless: `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`. Feel is checked by playtest.
- **Debug tools:** a single `DebugTools` node that does nothing in release. Epic 1 needs F1 (overlay: FPS, frame ms, node count, enemies alive) and F5 (reload data and restart the sandbox).

## UX & Interaction Patterns

- Colour language: player/Coalition cyan `#22E6FF`; enemies and all enemy projectiles magenta `#FF2BD6`; asteroids desaturated grey-brown `#7A6E62` with rim light `#C9D8E8`; background `#05070F`. Placeholder art should already follow this.
- Reticle: 32 px coalition-cyan ring drawn exactly at the cursor (the ship trails it while moving). The missile cooldown arc is a 4 px `muted` (`#93A7C2`) stroke at radius 22 px, drawn with `draw_arc`, sweeping clockwise from 12 o'clock. It is driven by `Events.missile_cooldown_changed(ratio)` (1 = just fired, 0 = ready).
- The reticle is a `Sprite2D` inside `World`, not a HUD element. The persistent HUD (later epics) stays in the top 120 px band.

## Cross-Story Dependencies

- 1.1 is the foundation for everything: project settings, layers, input map, `Log`/`Events`/`Config`, `tuning.json`/`flags.json`, GUT.
- 1.2 creates the sandbox scene (`scenes/sandbox/sandbox.tscn`, temporary main scene) with a `World` node mirroring the level tree containers (Asteroids, Enemies, Allies, Pickups, Projectiles, Effects, Player) plus `PauseArbiter`. Later stories add to this sandbox.
- 1.3 introduces `Projectile`, `Spawner` and `EntityRegistry`; 1.4 (Enemy base, Wasp, asteroids) and 1.5 (missile) build on them.
- 1.6 retrofits `Feedback.impact` and `Audio` calls into the deaths and impacts from 1.3–1.5, and adds `ShakeCamera` and pre-warm.
- 1.7 depends on all of the above (overlay, F5 reload, stress test, fun gate, Windows export smoke check).
- Later epics reuse these contracts: the `level.tscn` tree (Epic 2) replaces the sandbox as the gameplay scene; `GameState`/`SceneRouter` arrive in Epic 3, `SaveManager` in Epic 4. Until Epic 4, `level_cleared` only logs and shows a placeholder.
