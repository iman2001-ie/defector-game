---
title: 'Story 2.8: Outrun the Hunter Wasp'
type: 'feature'
created: '2026-10-07'
baseline_revision: '32030236e9392205ccfee4d72642457b6624d57e'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-2-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** There is no Hunter Wasp (GDD FR24, gdd.md L271: small, 3 HP, distinct orange tint, chases the player at 300 px/s with a 90°/s turn limit, contact only; COULD). `hunter_wasp` has tuning, a drop row and a flag (`flags.hunter_wasp`, default `false`), but it is not a registered type, so a level listing it fails validation (decision F14 says it is always a known id), and the WaveDirector has no flag gate.

**Approach:** Add `HunterWasp` (`class_name`, extends `Enemy`) that steers toward the player with a capped turn rate, register it, and teach the WaveDirector to skip (not count, DEBUG log) spawn entries whose type's feature flag is off. Add a dev wave that lists Hunter Wasps, and tests.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript. `_physics_process(delta)` only calls a public `step(delta)`. No per-frame allocation or logging; no per-frame group lookup (cache the player node; when it is missing or freed, re-look it up at most every 0.5 s via a script `const`).
- Numbers from `Config`, read once in `_ready`: `enemies.hunter_wasp.chase_speed_px_s` (300), `turn_rate_deg_s` (90); HP/tier/hitbox via the `Enemy` base. No new tuning keys.
- Movement each step: `heading` (unit `Vector2`) turns toward the target by at most `deg_to_rad(turn_rate_deg_s) × delta` (exact `angle_to` when smaller), then `global_position += heading × chase_speed × delta`. Speed is constant. `rotation` follows the heading (hull nose = heading; the polygon nose points down, so `rotation = heading.angle() − PI/2`).
- Target = the cached player's `global_position` (group `player`, Wasp `PLAYER_GROUP` precedent); with no player, `Playfield.SIZE / 2` so it never flies away for good. A zero vector to the target keeps the heading.
- Spawn (Wasp precedent): with a `slot`, entry `"top"` starts at `(slot.x, −half)` heading DOWN; `"sides"` starts at `(−half, slot.y)` heading RIGHT if `slot.x ≤ width/2`, else `(width + half, slot.y)` heading LEFT; another entry → one `Log.warn("spawn", …)` and top. No slot: stays at its spawn position, heading DOWN. `half = sprite_px / 2`, `sprite_px` 64. It never holds a formation slot and never re-enters/wraps.
- Scene `entities/enemies/hunter_wasp/hunter_wasp.tscn`: Wasp scene layout (`Area2D` layer 4 mask 0 `monitoring = false`, `Hitbox`, `Hull` `Polygon2D`) with a distinct swept-back silhouette, nose pointing down, `Hull.color` orange `#FF8A1F` (not the `enemy` magenta).
- `EntityRegistry`: `&"hunter_wasp"` in `ENEMIES` (always, per F14), plus `const ENEMY_FLAGS: Dictionary[StringName, String] = { &"hunter_wasp": "hunter_wasp" }` (type id → gating flag).
- `WaveDirector.start_wave` reads the gates once per wave (`Config.flag(name)` for each `ENEMY_FLAGS` entry) and caches the disabled types. A spawn or group entry whose type is disabled contributes 0 to `total_counted`, takes no formation rows, spawns nothing and logs one `Log.debug("spawn", "<source> <path>: <n> x hunter_wasp skipped (flag 'hunter_wasp' off); not counted")`. It is not an error and is not subtracted. Group entries use the same cached set when the group spawns.
- `flags.json` keeps `"hunter_wasp": false` (architecture default).

**Never:**
- No contact damage to the player (Epic 3), no drops (Epic 4), no shooting, no telegraph state, no Wasp dive-clock participation (`HunterWasp` is not a `Wasp`). No changes to `Enemy`, `Formation`, `Events`, `Spawner`, `LevelValidator`, the sandbox, the bench, `flags.json` or `sprint-status.yaml`. No new art files. No flag flip.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Stats | spawned | HP 3, SMALL tier, hitbox r = 32 × `hitbox_ratio`, `Hull.color` #FF8A1F | — |
| Straight chase | player straight ahead | moves exactly 300 × dt per step toward it | — |
| Turn limit | player behind (180°) | heading turns ≤ 1.5° per 1/60 s step; after 1.0 s turned 90° (±0.5°) | — |
| Catch-up | start (960,100) heading DOWN, player static at (1400,700) (outside the ~190 px turn circle), 10 s of steps | comes within 40 px of the player at some step; every step moves 300 × dt | — |
| Moving player | player moved mid-chase | next steps steer toward the new position (cached node, not a snapshot) | — |
| No player | no `player` group node | steers toward playfield centre | — |
| Player freed | cached player freed | no crash; falls back to centre, re-finds a new player within 0.5 s | — |
| Entries | slot (400,200)/(1500,200) sides; (960,160) top; "spiral" | starts (−32,200)→RIGHT / (1952,200)→LEFT; (960,−32)→DOWN; top | WARN on "spiral" |
| Death / contact | 3 damage; `destroy_by_contact()` | one `resolved`, one `enemy_killed` | — |
| Pause | tree paused | frozen | — |
| Flag off | wave: 4 hunter_wasp + 2 wasp, flag false | total 2, 2 enemies spawned, wasps take formation row 0, clears after 2 resolves | DEBUG skip line |
| Flag on | same wave, flag true | total 6, 4 counted `HunterWasp`s + 2 wasps | — |
| Flag-off group | group with hunter_wasp, flag false | not in total; spawn_group spawns nothing for it; wave clears | DEBUG skip line |
| Cut story (F14) | GDD Level 3 W2 shape (2 bastion, 2 needle, 3 medium asteroids, 4 hunter_wasp), flag false | `LevelValidator` accepts it; total 4; clears after 4 resolves | DEBUG skip line |

</intent-contract>

## Code Map

- `game/entities/enemies/wasp/wasp.gd` + `.tscn` -- pattern to mirror: `_init` sets `type_id`, `setup` (slot/entry, `super(params)` first), `_ready` (`super()` first, Config reads, entry WARN text "wasp entry '%s' is unknown; using top"), `PLAYER_GROUP`, `_top_entry_start`. Scene layout and magenta hull polygon (nose `(0,32)`).
- `game/entities/enemies/wasp/wasp_dive_clock.gd` -- picks only `Wasp` instances; read-only. HunterWasp must not extend `Wasp`.
- `game/core/enemy.gd` -- base: HP/tier/hitbox from `enemies.<type_id>`, `destroy_by_contact()` (small/medium), `_die`. Read-only.
- `game/autoloads/entity_registry.gd` -- add `hunter_wasp` to `ENEMIES` and the new `ENEMY_FLAGS`.
- `game/systems/waves/wave_director.gd` -- `start_wave` total loop (spawns + groups) and `_spawn_entry` (the unknown-type check, then formation slots): add the gate. `_entry_count` stays as is; add a helper that returns 0 for disabled entries in the total loops. Cache: e.g. `_disabled_types: Dictionary`, rebuilt in `start_wave`.
- `game/autoloads/config.gd` -- `flag(name)` (logs a missing flag), `level`/`LevelValidator.validate(data, path, known)` with `EntityRegistry.enemy_types()`.
- `game/data/tuning.json` L123 `enemies.hunter_wasp` -- all keys exist. `game/data/flags.json` -- unchanged.
- `game/data/levels/level_dev.json` -- append wave 6: `spawns` `[{hunter_wasp, 4, grid_4x1, top}, {wasp, 6, grid_3x2, top}]`, `asteroids` `[]`, `triggers` `[{ "when": "wave_clear", "actions": [ { "wait": 0.5 } ] }]`. With the default flag only the 6 Wasps spawn.
- `game/tests/unit/test_wasp.gd`, `test_bastion.gd` -- test style (`_make` without spawner, manual `step`, `Log.sink`, `after_each` resets `Config.load_data()`/`PauseArbiter.clear()`/`Feedback.reset()`). Flags are toggled in tests via `Config.flags["hunter_wasp"] = true` and restored by `Config.load_data()`.
- `game/tests/unit/test_wave_director.gd` -- inline-dictionary fixture with a real `Spawner` and `World`; template for the gate rows (`test_unknown_type_is_logged_subtracted_and_the_wave_still_clears` L212). A player node for hunters is not needed there.
- `game/tests/unit/test_level.gd` -- `wave_count() == 5` L139, `for wave: int in 5` L214 → 6; `test_dev_wave_5_has_a_bastion` L292 is the template for wave 6 (flag off: 6 counted Wasps, no `HunterWasp`).
- `game/tests/unit/test_config.gd` `test_level_dev_loads` L437 -- five → six waves.
- `game/tests/unit/test_spawner.gd` L60 -- template for a registry test; L67 type loop gains `hunter_wasp`.
- `game/tests/data/test_data_files.gd` -- add `test_hunter_wasp_tuning_ranges` (speed > 0, 0 < turn rate ≤ 360, hp ≥ 1) and `test_every_gated_type_has_a_flag` (each `ENEMY_FLAGS` value exists as a bool in `flags.json`, each key is in `ENEMIES`).
- New `class_name` `HunterWasp` needs `--import`; commit the new `.gd.uid`.

## Tasks & Acceptance

**Execution (write each test first, red, then the code):**
- `game/entities/enemies/hunter_wasp/hunter_wasp.gd` + `.tscn` -- `class_name HunterWasp extends Enemy` per the Always rules; accessors `heading() -> Vector2`, `chase_target() -> Vector2`.
- `game/autoloads/entity_registry.gd` -- register `hunter_wasp`; add `ENEMY_FLAGS`.
- `game/systems/waves/wave_director.gd` -- the flag gate; update the header doc comment.
- `game/data/levels/level_dev.json` -- wave 6.
- `game/tests/unit/test_hunter_wasp.gd` -- the HunterWasp matrix rows; Config reads (change `chase_speed_px_s`/`turn_rate_deg_s` in `Config.tuning`, check behaviour); no `Log` lines while chasing.
- `game/tests/unit/test_wave_director.gd` -- the Flag off / Flag on / Flag-off group / Cut story rows.
- `game/tests/unit/test_spawner.gd`, `test_level.gd`, `test_config.gd`, `game/tests/data/test_data_files.gd` -- per the Code Map.
- `_bmad-output/game-architecture.md` -- a short "As-built 2026-10-07 (Story 2.8)" note: HunterWasp steering, `ENEMY_FLAGS` gate in WaveDirector, flag default still false.
- Run `--import`, then the full GUT suite.

**Acceptance Criteria:**
- Given the `hunter_wasp` flag is true and a wave lists `hunter_wasp` spawns, when a Hunter Wasp is active, then it has 3 HP, an orange tint, and chases the player at 300 px/s with a 90°/s turn limit, with no shot of any kind.
- Given the flag is false, when a wave lists Hunter Wasp spawns, then they are skipped, not counted toward the wave total, and logged at DEBUG.
- Given the flag stays false, when the data test and a Level-3-W2-shaped wave run, then `hunter_wasp` is a known type id, the wave validates and clears normally.
- Given the headless GUT suite, when it runs, then the new tests pass and no previously passing test fails.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 19 findings — high 0, medium 0, low 13, false 6, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: when the player is near an edge, the Hunter's ~191 px turn loop takes it off-screen for a moment, where it can't be shot but still counts — this follows from the GDD numbers (300 px/s, 90°/s), and it always steers back. The flag is off by default, so players don't meet it. A fix (clamping or steering early) adds behaviour the spec rules out ("never wraps"). Left for a playtest.
  - `[low]` `[reject]` Blind: Hunters from one `grid_4x1` entry converge into one stack — real once the flag is on, but a fix (separation or a stagger) is new steering behaviour, not a direct correction. The flag is off by default. Left for a playtest.
  - `[low]` `[reject]` Blind: enabled Hunters use formation rows they never hold, which pushes later entries down a row — real (`test_flag_on_spawns_counted_hunters` asserts y 280), but it only matters when Hunter entries are listed before slot-holding entries, and the flag is off. A fix needs a per-type rows rule in `WaveDirector`.
  - `[low]` `[patch]` Blind: no test proves the gate is read once per wave (`Config` can reload flags mid-run) — added `test_flag_gate_is_read_once_per_wave`: the flag flips on before a progress-released group spawns, and the group's Hunters still don't spawn and the total stays 2.
  - `[low]` `[patch]` Blind: no test covers a wave with only disabled entries (total 0) — added `test_wave_of_only_disabled_entries_clears_without_a_stall` (total 0, nothing spawned, no "stalled" line, `wave_cleared` fires).
  - `[low]` `[patch]` Blind: the header comment and the as-built note say every disabled spawn and group entry logs a DEBUG line, but a never-requested group logs nothing — reworded both: the line is logged when the entry would spawn.
  - `[low]` `[reject]` Blind: the Hunter tests hard-code the shipped tuning (300 px/s, 1.5°/step, 32 px) — matches the GDD values the ACs state. `test_speed_and_turn_rate_come_from_tuning` proves the Config reads. Rewriting every test is not a direct correction.
  - `[low]` `[reject]` Blind: no end-to-end test of `level_dev` wave 6 with the flag on — the flag-on path is pinned in `test_wave_director` (counts, rows, `HunterWasp` instances), and chase behaviour in `test_hunter_wasp`. Another real-time level test adds slow coverage for little gain.
  - `[low]` `[reject]` Blind: the entry and player-lookup code is copied from `Wasp` — the same per-enemy pattern as Lancer, Needle and Bastion. A shared helper is a refactor across enemies, not part of this story.
  - `[low]` `[patch]` Blind: the wave-6 level test's F3 loop never asserts that each wave advanced — it now asserts `wave_number() == wave + 2` after each wait.
  - `[false]` `[reject]` Edge: an `ENEMY_FLAGS` key missing from `ENEMIES` would be subtracted as unknown after it was left out of the total — `test_every_gated_type_has_a_flag` asserts every `ENEMY_FLAGS` key is in `ENEMIES`, and both are constants, so this state can't ship.
  - `[low]` `[reject]` Edge: a player that is `queue_free`'d is still valid for the rest of that frame, so the Hunter steers at it one more step — at most one frame of steering; same `is_instance_valid` pattern as Wasp/Needle. Player death arrives in Epic 3.
  - `[false]` `[reject]` Edge: a `player`-group node that is not a `Node2D` makes every look-up null — the only node in the group is `entities/player/player.gd` (L39), a Node2D-derived ship. Same cast as Wasp, Lancer and Needle.
  - `[low]` `[reject]` Edge: a group of only disabled entries still logs INFO "group … spawned" — cosmetic. The DEBUG skip lines next to it explain it, and a fix adds a branch to `_spawn_group`.
  - `[low]` `[reject]` Verification gap (other): a wave whose `spawns` are all disabled, and whose group is released by a `progress` trigger, hits the stall net (ERROR) when the flag is off — real, but no level has that shape. The stall net is the existing behaviour for a wave that can't progress. A fix means a new rule in `_check_stall`.
  - `[false]` `[reject]` Intent: "dealing contact damage only" is not hooked up to the player — no player HP or damage system exists until Epic 3. "Contact only" is the attack type (GDD L271). Contact death is tested through `destroy_by_contact()`.
  - `[low]` `[reject]` Intent: the chase is never tested against the real `Player` scene in a running level with the flag on — `_physics_process` only calls `step`, the target is any `player`-group Node2D, and the spawn path is tested separately. Lancer/Needle precedent.
  - `[false]` `[reject]` Intent: AC3 names a Level 3 file that doesn't exist — `level_3.json` arrives in Story 4.1 and Epic 7. `test_data_files.gd` validates every `level_*.json` on its own, and the Level-3-W2-shaped fixture proves validation and clearing now.
  - `[false]` `[reject]` Intent: the story was built, not cut, so the "cut" AC3 can't be proven on a cut codebase — the invariant (known id, flag false, the wave clears) is proven on the built path with the flag off, which is the state a cut leaves.

### 2026-10-07 — Review pass
- verdicts: 20 findings — high 0, medium 0, low 15, false 5, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: enabled Hunters use formation rows they never hold, so wave-6 Wasps shift down — carried: the code still reads as logged; the flag is off by default, and a fix needs a per-type rows rule in `WaveDirector`.
  - `[low]` `[reject]` Blind: Hunters from one side spawn stacked and stay stacked — carried: the code still reads as logged; a fix is new steering behaviour, left for a playtest.
  - `[low]` `[reject]` Blind: nothing keeps a Hunter on screen (the ~191 px turn loop goes off-screen near edges) — carried: this follows from the GDD numbers; the spec rules out wrapping; left for a playtest.
  - `[low]` `[reject]` Blind: the catch-up test's 40 px threshold is not compared with the summed radii (Hunter 25.6 + player hurtbox 12 = 37.6) — true, but 40 px is the matrix's own number, and contact damage only arrives in Epic 3; tightening the test goes beyond the intent.
  - `[low]` `[reject]` Blind: the player look-up accepts a queued-for-deletion or dying player — carried: at most one frame of steering, same as Wasp/Needle; player death arrives in Epic 3.
  - `[low]` `[reject]` Blind: some gate behaviour has no test (a never-requested group logs nothing, F3 in a wave with disabled entries, an all-disabled group) — `debug_resolve_wave` (wave_director.gd L163) resolves `_progress`, whose total already excludes disabled entries, so F3 behaves the same; the "group spawned" INFO line and the stall net are carried rows. These are coverage gaps with no defect behind them.
  - `[low]` `[reject]` Blind: no end-to-end test of `level_dev` wave 6 with the flag on — carried: the flag-on path is pinned in `test_wave_director`.
  - `[low]` `[reject]` Blind: `test_dev_wave_6_skips_hunters_with_the_default_flag` walks five waves in real time — a few seconds of a 38.8 s suite; a shared helper or a wave-index jump is a test refactor, not a direct correction.
  - `[low]` `[reject]` Blind: `test_hunter_wasp_tuning_ranges` doesn't check `hitbox_ratio` or `tier` — no enemy's data test checks these (`test_data_files.gd` has no hitbox_ratio/tier asserts for any type); a range test for every enemy is a wider change than this story.
  - `[low]` `[reject]` Blind: the type-id expression is duplicated in `_counted_count` (L466) and `_spawn_entry` (L246) — both are the same `StringName(str(dict.get("type", "")))`, so they can't diverge today; a helper is a refactor.
  - `[false]` `[reject]` Blind: the "contact damage" AC has no recorded link to Epic 3 — carried: player hearts and damage don't exist until Epic 3. "Contact only" is the attack type, and the as-built note records it.
  - `[low]` `[reject]` Edge: a wave whose only spawns are disabled, with a group released by a progress trigger, stalls into the ERROR net — carried: no level has that shape; a fix is a new rule in `_check_stall`.
  - `[false]` `[reject]` Edge: progress triggers fire at different kill counts depending on the flag — this is the intended result of "contributes 0 to `total_counted`", which the intent states. It is designed behaviour, not a defect.
  - `[low]` `[reject]` Edge: a cached player that is queued for deletion is chased for one more frame — carried (same as the Blind look-up row).
  - `[false]` `[reject]` Edge: a zero or negative `turn_rate_deg_s`/`chase_speed_px_s` breaks the clamp — tuning is read once in `_ready`, and `test_hunter_wasp_tuning_ranges` requires speed > 0 and 0 < turn rate ≤ 360 for the shipped data, so this state can't ship.
  - `[low]` `[reject]` Intent: chase behaviour is tested only through manual `step()` calls against a bare `Node2D`, never against the real Player in a live level — carried: Lancer/Needle precedent; `_physics_process` only calls `step`.
  - `[low]` `[reject]` Intent: entry geometry is tested by calling `setup()` directly, never through a `WaveDirector` spawn — `_spawn_entry` passes `slot`/`entry` to every enemy the same way, and the Wasp tests already cover that path; the flag-on director test checks `HunterWasp` instances.
  - `[low]` `[reject]` Intent: the dev wave only ever runs with the flag off — carried: `flags.json` must not flip; the flag-on path is pinned at director level.
  - `[false]` `[reject]` Intent: R3a (log every disabled group entry at wave start) vs the diff's R3b (log when the group would spawn) — the intent says "Group entries use the same cached set when the group spawns", which supports R3b, and the header and the as-built note document it. Not a divergence.
  - `[false]` `[reject]` Intent: the freed-player test allows 0.5 s + 1.5 frames rather than exactly 0.5 s — the intent row says "within 0.5 s" of re-look-up cadence, and the test's margin is one-step quantisation at 60 Hz. The code uses the 0.5 s `const`.

## Design Notes

**Flag default.** The architecture and epic context set `hunter_wasp` to `false` by default; building the story does not flip it. Turning Hunters on is a one-line designer change in `flags.json`, then wave 6 of `level_dev` shows them.

**Gate placement.** The gate is a per-type flag map in `EntityRegistry` read by the WaveDirector at wave start, so totals are known up front (bar stays monotonic) and the gate is reusable. Disabled entries are a designer choice, so DEBUG, not ERROR, and they never become a subtraction.

**Steering.** A 90°/s cap at 300 px/s gives a ~190 px turn radius: the Hunter overshoots and loops back, which is the "keep moving" pressure. Contact damage arrives with the player's hearts in Epic 3.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0; class cache has `HunterWasp`.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --quit-after 600` -- expected: no ERROR or WARN lines.

## Auto Run Result

Status: done (follow-up review pass)

**Summary:** Story 2.8 adds the Hunter Wasp and a feature-flag gate for wave spawns. This pass re-reviewed the committed work (`db2da56`); it changed no code.
- `HunterWasp` (extends `Enemy`, not `Wasp`) has 3 HP, the small tier and an orange `#FF8A1F` hull. It flies at a constant 300 px/s, turns toward the cached player at most 90°/s, and heads for the playfield centre when there is no player. It is contact only.
- `hunter_wasp` is always a registered type (F14). `EntityRegistry.ENEMY_FLAGS` maps it to `flags.hunter_wasp`. `WaveDirector` reads the gates once per wave. A disabled entry counts 0, takes no rows, spawns nothing and logs one DEBUG line when it would spawn.
- `flags.hunter_wasp` stays `false`. `level_dev.json` wave 6 lists 4 Hunters and 6 Wasps.

**Files changed (since `32030236e9392205ccfee4d72642457b6624d57e`):**
- `game/entities/enemies/hunter_wasp/hunter_wasp.gd` + `.tscn` (+ `.uid`): the Hunter Wasp.
- `game/autoloads/entity_registry.gd`: registers `hunter_wasp`; adds `ENEMY_FLAGS`.
- `game/systems/waves/wave_director.gd`: the per-wave flag gate and its header doc.
- `game/data/levels/level_dev.json`: wave 6.
- `game/tests/unit/test_hunter_wasp.gd` (+ `.uid`), `test_wave_director.gd`, `test_spawner.gd`, `test_level.gd`, `test_config.gd`, `game/tests/data/test_data_files.gd`: tests for the matrix and the gate.
- `_bmad-output/game-architecture.md`: the "As-built 2026-10-07 (Story 2.8)" note.

**Review findings (follow-up pass):** 20 in total: high 0, medium 0, low 15, false 5, maybe-false 0. The verification-gap layer found no gaps.
- **Patched:** none.
- **Deferred:** none.
- **Rejected lows:**
  - Carried from the first pass: formation rows used by Hunters, stacking, off-screen loops, one frame chasing a queued-free player (logged twice), no flag-on end-to-end test, the all-disabled-spawns stall net, the chase not tested against the real Player, and the dev wave run only with the flag off.
  - New this pass:
    - the catch-up test's 40 px threshold (it is the matrix value; contact is Epic 3);
    - missing tests for a few gate paths (F3 checked by reading the code: it works);
    - the slow wave-6 level test;
    - no `hitbox_ratio`/`tier` range test (no enemy has one);
    - a duplicated type-id expression;
    - entry geometry not checked through a director spawn.
- **Rejected as false:**
  - Contact-damage AC tracking (carried).
  - Progress ratios that depend on the flag (intended).
  - Invalid runtime tuning (the data test forbids it).
  - The R3a/R3b logging-time reading (the intent supports R3b).
  - The freed-player timing margin.
- **Follow-up review recommended: false.** This was a follow-up pass, and it patched 0 high, 0 medium and 0 low.

**Verification:**
- `--import` exited 0.
- Full GUT suite: 44 scripts, 613/613 tests passed (6513 asserts), 38.8 s.

**Residual risks:**
- Nobody has seen a Hunter in play, because the flag is off by default. To see one, set `flags.hunter_wasp` to `true` and reach wave 6 of `level_dev`. Feel, readability against the magenta enemies, edge loops, stacking and the formation-row shift all need a human playtest. This run makes no feel or fun claim.
- Designer calls still open:
  - whether to turn the flag on;
  - the orange `#FF8A1F` (not a DESIGN.md palette token);
  - whether Hunters should skip formation rows.
- `sprint-status.yaml` belongs to the orchestrator. This run neither wrote, reverted nor committed it.

