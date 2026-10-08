---
title: 'Story 3.3: Collect Energy from Wreckage'
type: 'feature'
created: '2026-10-07'
baseline_revision: '80bbbaf32980242ccb69dc6f12f119db3f8e66c0'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-3-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/EXPERIENCE.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Kills and broken asteroids give nothing back. There are no energy orbs, no energy logic (clamp, `energy_changed`), no energy bar and no F4. Shield and Barrage (3.4/3.5) need all of this. Covers FR13, FR14 and FR62 (energy bar). SHOULD tier.

**Approach:** Enemies and asteroids roll `tuning.drops.<key>` in their death path and ask their `Spawner` (deferred) for gold `EnergyOrb`s in `World/Pickups`. Orbs drift down, are pulled to a living ship within the magnet radius and despawn after 6 s. The Player collects them on contact, and `GameState.add_energy` clamps the value and emits `Events.energy_changed`. A new HUD `EnergyBar` shows it, and F4 adds energy.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript. Every number comes from `Config`. Existing keys: `energy.{max, orb_value, orb_drift_px_s, orb_magnet_radius_px, orb_despawn_s}`, `drops.*`, `abilities.shield.cost` and `abilities.barrage.cost`. New keys: `energy.orb_magnet_speed_px_s` 600, `energy.orb_diameter_px` 24, `energy.orb_spread_px` 32, `hud.energy_bar` {`right_x` 1888, `y` 76, `width` 320, `height` 16, `tick_px` 2} and `debug.energy_add` 100.
- **GameState** gets its first logic: `max_energy() -> int` (`Config.int_("energy.max")`), `add_energy(amount: int) -> int` (clamps `energy + amount` into 0..max, always emits `Events.energy_changed(energy, max)` and returns the new value) and `emit_energy()` (emits the current value). `restart_level()`/`goto_title()` keep writing `energy = 0` directly, because the reloaded level announces it.
- **Loot** (`core/loot.gd`, `class_name Loot`, static only): `orb_count(row: Dictionary, roll: float) -> int` returns `row.orbs` when `roll < row.chance`, else 0, and returns 0 for a missing or non-number field. `drop(spawner: Spawner, table_key: String, at: Vector2, roll: float = randf()) -> int` reads `Config.section("drops." + table_key)` and, with a valid spawner and count n > 0, calls `spawner.spawn_orb.call_deferred({position})` n times, spread horizontally `orb_spread_px` apart and centred on `at`. It returns n. A null or freed spawner returns 0 with no error.
- **Death paths:** `Enemy._die()` calls `_drop_loot()` → `Loot.drop(spawner, String(type_id), global_position)` after `enemy_killed` and before `resolved`. The Asteroid gets `var spawner: Spawner = null` (set by `Spawner.spawn_asteroid` before `add_child`) and drops with key `"asteroid_%s" % size` after `asteroid_destroyed`. Contact kills, ally kills and the F3 resolve all go through these paths. Replace the stale "Drops arrive in Epic 4" comments.
- **EnergyOrb** (`entities/pickups/energy_orb.tscn` + `.gd`, `class_name EnergyOrb extends Area2D`): layer `PICKUPS` (32), mask 0, group `pickups`, a `Hitbox` circle of `orb_diameter_px`, and a gold (`#FFD23F`) additive gradient `Sprite` sized to the diameter. `setup({position})` works as on other entities. `step(delta)` is called from `_physics_process`: age += delta, and at `age >= orb_despawn_s` the orb frees itself. When the cached Player (found once in `_ready` by group `player`) is valid, not dead and within `orb_magnet_radius_px` (inclusive), the orb moves toward it at `orb_magnet_speed_px_s`, without overshooting. Otherwise it moves down at `orb_drift_px_s`. It also frees itself once fully below `Playfield.SIZE.y`. `collect() -> bool` works once: `GameState.add_energy(orb_value)`, `Audio.play_sfx(&"energy_pickup")`, `queue_free()`, returns true. After that it returns false.
- **Spawner:** `spawn_orb(params) -> EnergyOrb` parents to `World/Pickups`, which is optional the same way as `Effects` (a missing container gives one `Log.debug` in `_ready`, and the method returns null). `EntityRegistry.ENERGY_ORB` is the preloaded scene.
- **Player:** `on_contact` collects an `EnergyOrb` (even while invulnerable or `debug_invincible`) at no heart cost and never remembers it. The dead ship already has monitoring off.
- **EnergyBar** (`ui/hud/energy_bar.gd`, `class_name EnergyBar extends Control`, `HUD/EnergyBar` after `HeartsDisplay`, `PROCESS_MODE_PAUSABLE`, `MOUSE_FILTER_IGNORE`) is driven only by `Events.energy_changed`. Its rect is `right_x - width`, `y`, `width × height` (x 1568, y 76, 320×16). `_max` starts at `Config.int_("energy.max")`. It draws the theme `EnergyBar` styles `track` (`#2B3348`, 2 px corners) and `fill` (`#FFD23F`, width = width × current/max, nothing at 0), plus vertical `tick` lines (`#E8F4FF`, `tick_px` wide, full height) at `shield.cost` and `barrage.cost` of max, clamped inside the bar. Static helpers `fill_width(current, max, width)` and `tick_x(value, max, width, tick_px)`. Accessors `current()`, `max_energy()`, `tick_positions()`.
- `level.gd` calls `GameState.emit_energy()` in `_ready` right after `level_started`, so the bar shows the attempt's starting energy.
- **F4:** `DebugTools.add_energy()` (debug builds only) handles `debug_add_energy`. It runs `GameState.add_energy(Config.int_("debug.energy_add"))` and logs one `Log.info("debug", "F4: energy n/max")`.
- **SFX:** append an `energy_pickup` sound (a short, bright ~0.15 s rising chime with its own seed) to `tools/gen_placeholder_sfx.py` so the existing WAVs stay byte-identical. Then register it in `Audio.SFX` and add a CREDITS row.

**Never:**
- No Shield, Barrage, `ability_denied` or denied flash (Stories 3.4/3.5). No saving or carry-over (Epic 4). No Maul or Flagship turret (Epics 6/7). Their drop rows stay in data, unused.
- No `instantiate` outside Spawner. No per-frame group lookups or allocations in `_physics_process`. No HUD polling of `GameState`. No bare `print()`. No per-orb INFO logs.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Roll hit | `{chance 0.15, orbs 1}`, roll 0.1 | 1 | n/a |
| Roll miss | same, roll 0.15 | 0 | n/a |
| Bastion | `{1.0, 2}`, any roll in [0,1) | 2 orbs, 32 px apart, centred on the death point | n/a |
| Bad row | `drops.foo` missing or chance not a number | 0 orbs | Config logs the missing path |
| No spawner | enemy built without Spawner dies | no orb | silent |
| Drift | orb at (100,100), no player, 0.5 s | (100,160) | n/a |
| Magnet | ship 160 px away | moves toward ship at 600 px/s, never overshooting | n/a |
| Outside magnet | ship 161 px away, or dead | drifts down | n/a |
| Despawn | 6.0 s of physics time | freed, no energy | n/a |
| Collect | energy 0, ship touches orb | energy 10, `energy_changed(10,100)`, `energy_pickup` played, orb freed, hearts unchanged | n/a |
| Cap | energy 95, collect | energy 100, `energy_changed(100,100)` | n/a |
| Double collect | `collect()` twice | second returns false, energy +10 once | n/a |
| F4 | energy 30 | 100, one `energy_changed` | release build: nothing |
| HUD | `energy_changed(50,100)` | fill 160 px; ticks at x 160 and 318 | n/a |

</intent-contract>

## Code Map

- `game/core/enemy.gd:94-102` -- `_die()`. Add `_drop_loot()` after `enemy_killed` (the architecture snippet at `game-architecture.md:~970` shows this order). `spawner` (line 24) is already set by Spawner.
- `game/entities/asteroids/asteroid.gd:68-77` -- `apply_damage` death branch. Add the `spawner` field and the drop.
- `game/core/spawner.gd` -- `_ready` container lookup (the `Effects` optional pattern, lines 22-27), `spawn_asteroid` (set `asteroid.spawner = self`), and the new `spawn_orb`, modelled on `spawn_explosion`.
- `game/autoloads/entity_registry.gd` -- add `ENERGY_ORB` next to `EXPLOSION`.
- `game/autoloads/game_state.gd` -- fields only today. Its doc says energy logic arrives with 3.3; update the doc.
- `game/autoloads/events.gd:8` -- `energy_changed(current, max_energy)` already exists. No change.
- `game/entities/player/player.gd:198-218` -- `on_contact`. Put the orb branch first after the `_dead` guard. The player mask is already 52 (enemies|asteroids|pickups). Update the class doc's contact paragraph.
- `game/entities/player/player.tscn` -- the gradient Sprite and additive material pattern for the orb visual.
- `game/core/collision_layers.gd` -- `PICKUPS` = 32.
- `game/ui/hud/hearts_display.gd`, `wave_bar.gd` -- patterns for an Events-only HUD control, Config reads in `_ready`, theme lookup by type, static layout helpers and read accessors.
- `game/ui/theme/defector_theme.tres` -- add the `EnergyBar` styles and colour (the WaveBar StyleBoxFlat pattern, lines 3-30 and 84-87). Remember to bump `load_steps`.
- `game/scenes/level/level.tscn` -- add `HUD/EnergyBar` after `HeartsDisplay` (offsets 1568,76 to 1888,92; theme set) and a new ext_resource. `World/Pickups` exists. `level.gd` `_ready` emits `level_started`; add `emit_energy()` after it.
- `game/scenes/sandbox/sandbox.tscn` -- has `World/Pickups`, so the sandbox gets drops too. No change.
- `game/ui/debug/debug_tools.gd:107-124` -- `_unhandled_input` chain. Add `debug_add_energy` (F4, already in `project.godot`) and `add_energy()` like `toggle_invincible`. Update the class doc.
- `game/systems/waves/wave_director.gd:179` -- F3 kills through `apply_damage`, so it drops orbs. No change.
- `game/autoloads/audio.gd:9-17`, `tools/gen_placeholder_sfx.py` (`main()` at line 137; seed consts at lines 19-22), `game/assets/CREDITS.md` -- add the SFX.
- `game/tests/unit/test_config.gd:134` -- the drop rows exist. `test_data_files.gd` -- add a GDD-conformance test for the drop chances/orbs and the new keys.
- `game/tests/unit/test_level.gd` -- `after_each` already resets GameState and clears PauseArbiter. The long wave tests may now spawn orbs; that's harmless.
- `_bmad-output/game-architecture.md` -- the built-parts line ~562, F4 row ~535 (Built), `_die` snippet ~970, the Pickups/energy rows, and an as-built bullet for Loot, EnergyOrb, EnergyBar and GameState energy.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_loot.gd`, `test_energy_orb.gd`, `test_energy_bar.gd`, `test_game_state.gd` (extend), `test_player_hearts.gd` or a new `test_player_pickup.gd`, `test_enemy.gd`/`test_asteroid.gd`/`test_spawner.gd` (drop + `spawn_orb`), `test_debug_tools.gd` (F4 and release no-op), `test_audio.gd` (`energy_pickup` registered), `test_level.gd` (EnergyBar present at the expected rect; a start `energy_changed(0,100)` reaches it) -- write these FIRST and cover every I/O row. Force drop outcomes by setting `Config.tuning.drops.<key>.chance` to 1.0/0.0, and call `Config.load_data()` in `after_each`. Wait one frame for deferred orbs. Reset `GameState.energy` in `after_each`.
- `game/autoloads/game_state.gd` -- the energy API.
- `game/core/loot.gd` -- NEW.
- `game/entities/pickups/energy_orb.gd`, `energy_orb.tscn`, `game/autoloads/entity_registry.gd`, `game/core/spawner.gd` -- the orb and its creation.
- `game/core/enemy.gd`, `game/entities/asteroids/asteroid.gd` -- the drops.
- `game/entities/player/player.gd` -- orb collection.
- `game/ui/hud/energy_bar.gd`, `game/ui/theme/defector_theme.tres`, `game/scenes/level/level.tscn`, `game/scenes/level/level.gd` -- the HUD bar and the start emit.
- `game/ui/debug/debug_tools.gd` -- F4.
- `game/data/tuning.json` -- the new keys.
- `tools/gen_placeholder_sfx.py`, `game/assets/audio/sfx/sfx_energy_pickup.wav`, `game/autoloads/audio.gd`, `game/assets/CREDITS.md` -- the SFX. Regenerate, confirm that only the new WAV is added, then run `--import` (new class_names and WAV).
- `_bmad-output/game-architecture.md` -- the as-built notes per the Code Map.

**Acceptance Criteria:**
- Given a level is running, when the player kills a Bastion, then two gold orbs appear in `World/Pickups` at its death point, drift down, are pulled onto the ship when it comes within 160 px, and touching them raises `GameState.energy` by 10 each, with `HUD/EnergyBar` filling and the `energy_pickup` SFX playing without an "unknown sfx" warning.
- Given the HUD at level start, then `HUD/EnergyBar` shows the starting energy (0 on a fresh attempt or retry) with tick marks at 50 and 100.
- Given a debug build, when F4 is pressed, then energy rises by 100, capped at 100, and the bar shows full. In a release build F4 does nothing.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 27 findings — high 0, medium 1, low 18, false 8, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: `EnergyOrb._ready` resizes the shared `GradientTexture2D`, and a fractional or tiny diameter makes the sprite and hitbox sizes differ. Every orb uses the same diameter, so resizing the shared texture is the same pattern as `player.gd`. A mismatch needs non-integer tuning, and making the texture local to the scene would allocate one texture per orb.
  - `[false]` `[reject]` Blind: multi-orb drops near the side edges land where the player can't reach them. The ship is confined to x 0..1920, and the magnet radius is 160 px. The furthest off-screen drop is a Bastion at half-sprite 80 plus a 16 px spread, so 96 px, which is still inside the magnet's reach.
  - `[low]` `[reject]` Blind: a missing drop row asserts at kill time, and drop values aren't checked when data loads. Every current type has a row (`test_config.gd:134`, and the new `test_data_files` GDD check). Asserting on a missing key is Config's project-wide convention. Load-time validation of the drop table is new machinery.
  - `[low]` `[reject]` Blind: `Config.section` deep-copies the drop row on every death. That's one small Dictionary per death, not per frame. The same death also instances a whole explosion scene, so the copy causes no measurable harm.
  - `[low]` `[reject]` Blind: the orb looks up the Player only once, so a ship that appears later never gets the magnet. In `level.tscn` and the sandbox, the Player exists before any enemy can die, and a retry reloads the whole scene. No game path can reach this state.
  - `[false]` `[reject]` Blind: the spawner check is written three times (Enemy, Asteroid, Loot). The repeated check is harmless and changes no behaviour, and the reviewer named no harm it causes.
  - `[low]` `[reject]` Blind: the spec doesn't record that `Loot.drop` takes an untyped `spawner_ref`. The fix would edit this build's spec. The reason is in the code and the architecture as-built notes, and the Auto Run Result reports the deviation.
  - `[low]` `[reject]` Blind: no test covers drops from ally kills or the F3 resolve. Both go through `Enemy._die()`, and `_last_hit_by_ally` doesn't affect `_drop_loot`. F3 calls `apply_damage` (`wave_director.gd:179`). The shared path is tested, including contact kills and the drop's position in the death order.
  - `[low]` `[reject]` Blind: no end-to-end test of acceptance criterion 1 in `level.tscn`. Each link is tested where it connects: Enemy → Loot → real Spawner → `Pickups` (`test_enemy`), orb drift and magnet (`test_energy_orb`), real-physics pickup (`test_player_pickup`), and GameState → bar in the level (`test_level`).
  - `[low]` `[reject]` Blind: the despawn test accepts 361 frames instead of 360. Floating-point drift costs at most one 16 ms frame, and the test allows for it on purpose.
  - `[low]` `[reject]` Blind: the ticks sit to the right of their thresholds. The spec's I/O matrix fixes the tick positions at x 160 and 318, and at 50 energy the fill meets the tick's left edge. Moving the tick means editing the spec.
  - `[false]` `[reject]` Blind: the bar has no "ready" cue and no fill tween. The epic context gives the E/Q hints at 50 and 100 to Epic 5. A tween isn't required, and UX says only "fills on pickup".
  - `[false]` `[reject]` Blind: orbs from kills above the screen fall in late. Enemies above the screen are at most about 80 px up, so their orbs drift in within about 0.7 s of the 6 s lifetime. That isn't a meaningful loss.
  - `[low]` `[reject]` Blind: the generated WAV isn't pinned to its generator. Every placeholder WAV follows this project pattern, and the WAV is regenerated and committed together with the generator.
  - `[false]` `[reject]` Edge: orbs can spawn off-screen horizontally. Same refutation as the Blind row: the magnet's reach covers every off-screen death position.
  - `[low]` `[reject]` Edge: a future enemy type without a drop row reports the missing key on every death. Same reason as the Blind missing-row row: Config's convention, and current types are covered.
  - `[low]` `[reject]` Edge: lowering `energy.max` with an F5 reload while energy is above it makes `emit_energy` report energy above the max. Only the debug F5 can cause this. The bar clamps the value, and the next `add_energy` clamps the state.
  - `[low]` `[reject]` Edge: an orb never magnets to a Player added after it. Same as the Blind row: no game path reaches this state.
  - `[low]` `[patch]` Edge: a negative `orb_magnet_radius_px` squares to a positive value and turns the magnet on. Fixed: `energy_orb.gd` now clamps it with `maxf(..., 0.0)` when it reads tuning, and `test_a_negative_magnet_radius_never_pulls` covers it.
  - `[false]` `[reject]` Edge: the Bastion's orbs sit ±16 px from its death point. The spec centres the spread on the death point, which is what "at its death point" means for two orbs.
  - `[medium]` `[patch]` Verification gap: no test checks that the EnergyBar repaints after `energy_changed`, so a dropped `queue_redraw()` would freeze the HUD while every test stays green. Added `test_energy_changed_repaints_the_bar`, which watches the `draw` signal after the change. Removing `queue_redraw()` makes it fail, which confirms it catches the problem.
  - `[low]` `[reject]` Intent: the tests check pieces one at a time and never the whole running chain. Same as the Blind end-to-end row: each link is tested where it connects.
  - `[false]` `[reject]` Intent: the R4 reading (feel and visuals as owed operator actions). The intent's examples are infrastructure actions outside the repo. A feel playtest is this project's standard leftover manual check (the 3.1/3.2 triage), not an `awaiting-operator` action.
  - `[false]` `[reject]` Intent: F4 and the new tuning keys go beyond the story. F4 is the fifth acceptance criterion of Story 3.3 in `epics.md`. The keys are data defaults for feel numbers the GDD doesn't specify (Design Notes).
  - `[low]` `[reject]` Intent: the drop rate is never checked statistically. The roll is a single `roll < chance` comparison, tested with fixed rolls on both sides of the threshold. The chances are checked against the GDD in data tests. A statistical test would be flaky.
  - `[low]` `[reject]` Intent: the SFX is checked as the stream assigned to the player, not as heard audio. Playback is engine behaviour. The test confirms that `energy_pickup` is the stream the pool played and that it is registered (so there's no unknown-sfx warning).
  - `[low]` `[reject]` Intent: nothing checks the orb's gold glow or the bar's look on screen. Automation can't judge visuals. Layer, group, size and theme colours are asserted, and the look is left for the human playtest.

### 2026-10-08 — Review pass (follow-up)
- verdicts: 25 findings — high 0, medium 1, low 18, false 6, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: a missing drop row raises a config error on every death of a future type. carried: same as the earlier missing-row row (Config's convention; every current type has a row).
  - `[false]` `[reject]` Blind: orbs aren't clamped inside the playfield horizontally, so side-entry or edge kills waste them. carried: the 160 px magnet reaches every off-screen death position (at most 96 px out).
  - `[low]` `[patch]` Blind: `test_drop_comes_after_enemy_killed_and_before_resolved` can't see where `_drop_loot()` runs, because the spawn is deferred either way, so its name claims more than it checks. Renamed it to `test_kill_signals_keep_their_order_and_orbs_arrive_deferred`, which is what it asserts.
  - `[low]` `[reject]` Blind: no end-to-end kill → orb → pickup → bar test in `level.tscn`. carried: each link is tested where it connects.
  - `[false]` `[reject]` Blind: the spawner guard is checked in the callers and again in `Loot.drop`. carried: harmless repetition with no named harm.
  - `[low]` `[reject]` Blind: `energy_orb.tscn` (radius 12, 24×24 texture) and `level.tscn` (EnergyBar offsets) repeat tuning values. `_ready` overwrites them from Config, so they only serve as the editor preview. `test_level` asserts the bar rect from tuning. The HUD controls from earlier stories use the same pattern, and a stale preview never reaches the player.
  - `[false]` `[reject]` Blind: every orb allocates its own `CircleShape2D` while the texture is shared. One small allocation per spawn is not per frame, and sharing the shape would let one orb's resize change every orb. A tuning change reaching every orb's texture is intended. The shared-texture part matches the earlier carried row.
  - `[low]` `[reject]` Blind: `_drop_world()`, `_orbs()` and `_assert_dropped_at()` are copied across three test files. Dev-only duplication with no wrong result. Moving them into a fixture is a refactor, not a direct correction.
  - `[low]` `[reject]` Blind: no RNG seam for the drop roll below `Loot`, so tests force outcomes through `Config.tuning`. `Loot.drop` already takes a `roll`. Adding a seam to the entities adds public surface, and the forced-chance pattern is restored in `after_each`.
  - `[low]` `[patch]` Blind: `test_data_files` checks `hud.energy_bar.right_x` against a literal `1920.0`. It now uses `Playfield.SIZE.x`. The `120.0` HUD-band literal stays, because no named constant exists for it.
  - `[low]` `[patch]` Blind: the architecture Directory Structure tree under `core/` doesn't list `loot.gd`. Added the `loot.gd` line. The other half of the claim is false: the State Management row "Energy carry-over, wipe on death, save on clear" is the target rule set. A retry calls `restart_level()`, which zeroes energy, so it doesn't contradict the as-built notes.
  - `[false]` `[reject]` Blind: orbs vanish at despawn with no blink or fade. Neither the intent, the GDD nor the UX spec asks for a despawn warning on orbs. The only blink in DESIGN.md is the shield's.
  - `[low]` `[reject]` Edge: a zero or negative `energy.orb_magnet_speed_px_s` makes the magnet push orbs away. Only a mistuned data file can reach this, and the fix adds a guard.
  - `[false]` `[reject]` Edge: orbs can spawn off-screen sideways. carried: the magnet's reach covers every off-screen death position.
  - `[low]` `[reject]` Edge: an F5 reload that lowers `energy.max` makes `emit_energy` report energy above the max. carried: debug F5 only; the bar clamps it and the next `add_energy` clamps the state.
  - `[medium]` `[patch]` Verification gap: the asteroid drop test couldn't tell the per-size drop rows apart. `asteroid_small` stayed at 1.0 across loop passes, and the missed-roll test zeroed only `large`. New helper `_only_size_drops(size)` sets the tested size's row to 1.0 and the other two to 0.0, and the missed-roll test now zeroes all three rows. Mutation check: hard-coding `"asteroid_small"` in `asteroid.gd` now fails `test_asteroid` (1 failure). Restored afterwards.
  - `[low]` `[patch]` Verification gap (other): the ordering test's name overclaims. It is grouped with the Blind ordering row and fixed by the same rename.
  - `[low]` `[reject]` Intent: the tests show the player-facing loop piece by piece, never as one chain in a level. carried: each link is tested where it connects.
  - `[low]` `[reject]` Intent: ally kills and the F3 resolve have no drop assertions. carried: both go through the tested `_die` path.
  - `[false]` `[reject]` Intent: the F4 test synthesises the action, so the key isn't covered. `test_project_settings.gd` asserts the `debug_add_energy` → F4 binding.
  - `[low]` `[reject]` Intent: the despawn test never checks the exact 360th step. carried: the one-frame float tolerance is deliberate.
  - `[low]` `[reject]` Intent: "centred on the death point" is checked exactly in x but loosely in y (+40 px). `Loot.drop` passes `at.y` unchanged, as the code shows. The tolerance only absorbs drift in the physics frame before the test reads the orb, and tightening it would make the test flaky.
  - `[low]` `[reject]` Intent: `Loot.drop` has an untyped spawner parameter instead of `Spawner`. carried: the deviation is disclosed and the fix would edit the spec.
  - `[low]` `[reject]` Intent: rendered pixels of the orb and bar are never checked. carried: visuals are left for the human playtest.
  - `[low]` `[reject]` Intent: no test runs the orb under the real physics loop (`_physics_process` → `step`). The delegation is one line, every behaviour in `step` is tested, and breaking it would show at once in any playtest.

## Design Notes

- **New tuning keys:** the GDD gives no magnet speed, orb size or multi-orb spread. They are first-pass feel tuning, not design decisions, so they get data defaults (600 px/s, 24 px, 32 px) that a designer can change without touching code. `debug.energy_add` keeps the F4 "+100" out of code.
- **Deferred spawn:** orbs are Area2Ds, and deaths happen inside `area_entered` callbacks. Adding a collision object during a physics query flush triggers Godot's "flushing queries" error, so `Loot.drop` defers `spawn_orb`. A deferred call on a freed spawner is dropped safely.
- **Always emit on collect:** emitting even at the cap keeps the AC literal ("energy_changed fires"), and the bar is idempotent.
- **Collection lives in Player.on_contact:** the architecture puts the `pickups` mask on the Player hurtbox and gives the orb mask 0, so the Player detects the orb and the orb owns `collect()`.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0, with the new class_names (`Loot`, `EnergyOrb`, `EnergyBar`) and the WAV imported (`<GODOT_DIR>` from `LOCAL.md`).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failures, no new SCRIPT ERRORs.
- `git status --short game/assets/audio/sfx` -- expected: only `sfx_energy_pickup.wav` (+ `.import`) is new.

**Manual checks (if no CLI):**
- Orb look, the magnet feel and the bar's look need a human playtest.

## Auto Run Result

Status: done

**Summary:** This was a follow-up review pass on Story 3.3 (energy orbs from wreckage, the energy bar and F4). The implementation from commit 6bce725 stands. Four review layers reported 25 findings. Four were patched (one medium, three low), and all four are in tests or documentation. No production code changed.

**Files changed in this pass:**
- `game/tests/unit/test_asteroid.gd`: new `_only_size_drops()` helper. The per-size drop test isolates each size's row, and the missed-roll test zeroes all three rows.
- `game/tests/unit/test_enemy.gd`: the ordering test is renamed to `test_kill_signals_keep_their_order_and_orbs_arrive_deferred`, which is what it checks.
- `game/tests/data/test_data_files.gd`: the EnergyBar bound uses `Playfield.SIZE.x` instead of `1920.0`.
- `_bmad-output/game-architecture.md`: the `core/` tree now lists `loot.gd`.

The files changed in the first pass are unchanged and listed in commit 6bce725: GameState energy API, `Loot`, `EnergyOrb`, `Spawner.spawn_orb`, Enemy and Asteroid drops, Player pickup, `EnergyBar` + theme, level wiring, F4, tuning keys, the `energy_pickup` SFX and tests.

**Review findings:** 25 findings (high 0, medium 1, low 18, false 6, maybe-false 0).
- **Patched (4):**
  - medium: the asteroid size-row verification gap
  - low: the ordering test's overclaiming name (Blind and VG rows, grouped)
  - low: the `1920.0` literal
  - low: `loot.gd` missing from the architecture tree
- **Deferred:** none.
- **Rejected (21):** each row's reason is in the follow-up Review Triage Log entry. Ten rows were carried from the first pass.
  - Lows rejected:
    - the missing-row error
    - no end-to-end test (×2)
    - scene preview values that copy tuning
    - duplicated test helpers
    - no RNG seam
    - a negative magnet speed
    - the F5 `energy.max` over-cap
    - ally/F3 drops untested
    - the despawn frame tolerance
    - the y tolerance
    - the untyped spawner parameter
    - visuals untested
    - the physics-loop delegation untested
  - Falses:
    - off-screen orbs (×2)
    - the triple spawner guard
    - the per-orb shape
    - no despawn blink
    - F4 key coverage

**Follow-up review recommended:** false. This is a follow-up pass, and it patched no high (patched by verdict: high 0, medium 1, low 3).

**Verification:**
- `--headless --path game --import` exits 0.
- The full GUT suite passes 801/801 (7389 asserts) with 0 SCRIPT ERRORs.
- Mutation check: replacing the asteroid's size-keyed row with `"asteroid_small"` makes `test_asteroid` fail (10/11 passing). The source was restored from git afterwards.

**Residual risks:**
- The orb's gold glow, the magnet feel (600 px/s), the pickup chime and the bar's look still need a human playtest.
- The F4 amount, magnet speed, orb size and spread are new data defaults that the GDD doesn't set.
