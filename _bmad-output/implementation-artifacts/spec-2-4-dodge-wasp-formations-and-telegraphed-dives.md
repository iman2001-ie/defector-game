---
title: 'Story 2.4: Dodge Wasp Formations and Telegraphed Dives'
type: 'feature'
created: '2026-10-07'
baseline_revision: '4b9bb4dc83891fadf502655ce3f9ad2d30249e0a'
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

**Problem:** Wave Wasps appear at their formation slot and sit still forever (`wasp.gd` is a bare `Enemy`). The GDD Wasp (FR19, FR25, NFR6) must fly in at 350 px/s to a slot in the top 40%, hold it, and every 3–5 s one holding Wasp flashes its wings, pauses 0.4 s and dives at the player at 600 px/s; a Wasp leaving the screen re-enters from the top, returns to its slot and never resolves. Nothing enforces the ≥ 0.3 s telegraph rule over tuning yet.

**Approach:** Give `Wasp` (new `class_name`) an `enum State { ENTER, HOLD, TELEGRAPH, DIVE }` state machine driven by the director's existing `slot`/`entry` spawn params, with every number from `tuning.enemies.wasp`. Add a formation-wide `WaspDiveClock` node (child of `WaveDirector` in `level.tscn`) that every random 3–5 s tells one random holding Wasp to start its dive. Put the Player in group `player` so a diving Wasp can aim at it. Extend `test_data_files.gd` with the telegraph rule and a "Wasp formations fit the top 40%" check.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript. `_state` is assigned only inside `_enter_state()`, which also does the entry effects (flash on/off, entry start position, dive direction). `_physics_process(delta)` only calls a public `step(delta)` containing the `match`, so tests drive it deterministically.
- Numbers from `Config` only, read once in `_ready`: `enemies.wasp.entry_speed_px_s`, `dive_speed_px_s`, `telegraph_s`, `dive_interval_s.min/max`, plus new keys `zone_height_ratio` 0.4, `wing_flash_hz` 10, `wing_flash_energy` 2.0. No per-frame allocation, group lookup or logging; the player lookup (`get_first_node_in_group(&"player")`) happens once per dive, the clock's group scan once per dive tick.
- Entry: `"top"` starts at `(slot.x, -sprite_px/2)`; `"sides"` starts at `(-sprite_px/2 or width + sprite_px/2, slot.y)` from the nearer side; any other entry → `Log.warn("spawn", …)` and top. A slot below the zone (`slot.y > zone_height_ratio × Playfield.SIZE.y`) is clamped to it with one `Log.warn("spawn", …)`.
- No `slot` param (the sandbox) → the Wasp starts in HOLD at its `position` and never moves on its own; the sandbox has no dive clock, so its formation and the stress bench behave exactly as before.
- Dive direction is snapshotted when DIVE starts: toward the player's `global_position`, or `Vector2.DOWN` with no player or a zero vector. A Wasp in DIVE whose position leaves `Playfield.RECT` grown by `sprite_px/2` re-enters ENTER at `(slot.x, -sprite_px/2)` and flies back to its slot at the entry speed. It never emits `resolved` for leaving.
- The clock is a plain `Node` (`process_mode` inherit, so it freezes with the game), uses its own seedable `rng`, and on each deadline picks one Wasp in group `enemies` that `is_holding()` and is not dead, calls `start_dive()`, then draws the next interval in `[min, max]`. With no holding Wasp it just draws the next interval.

**Never:**
- No player contact damage, hearts or `destroy_by_contact` wiring (Epic 3). No changes to `Formation`, `WaveDirector` logic, `Events` signals, the sandbox, the bench or `sprint-status.yaml`. No new art; the flash is a `Hull.self_modulate` blink. No Hunter Wasp.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Top entry | slot (720,160), entry top | spawns at (720,-32) in ENTER, moves 350 px/s toward slot, HOLD on arrival, stays put | — |
| Side entry | slot (400,280), entry sides | starts at (-32,280); slot x > 960 starts at (1952, y) | — |
| Unknown entry | entry "spiral" | top entry | WARN, no crash |
| Slot too low | slot y 520, zone 432 | holds at y 432 | WARN |
| Sandbox | only `position` | HOLD at position, never moves | — |
| Telegraph | `start_dive()` while HOLD | TELEGRAPH: no movement, hull flashes, for `telegraph_s`; then DIVE | `start_dive()` outside HOLD ignored |
| Dive | player at (960,900) | moves 600 px/s along the snapshotted direction | no player → straight down |
| Exit | diving Wasp leaves the grown rect (bottom or side) | ENTER from (slot.x,-32), back to slot, HOLD; `resolved` not emitted | — |
| Clock | 3 holding, 1 entering; deadline reached | exactly one holding Wasp starts its telegraph; next deadline in [min,max] | none holding → no dive, reschedule |
| Pause | tree paused | Wasps and clock frozen | — |

</intent-contract>

## Code Map

- `game/entities/enemies/wasp/wasp.gd` -- today only `_init` sets `type_id`. Becomes `class_name Wasp extends Enemy`; override `setup()` (call `super`, read `slot`/`entry`) and `_ready()` (call `super` first — it applies `_spawn_position`, HP, hitbox — then read tuning and `_enter_state`). Add read accessors `state()`, `formation_slot()`, `is_holding()`, `is_flashing()`.
- `game/entities/enemies/wasp/wasp.tscn` -- `Hull` Polygon2D (enemy magenta) is the flash target; sprite_px 64. No structural change needed.
- `game/core/enemy.gd` -- read-only base: `setup` stores `position` into `_spawn_position`/`_has_spawn_position` (protected, Wasp may overwrite them in its `setup`); `_ready` applies them; `is_dead()`.
- `game/systems/waves/wave_director.gd` L230-245 -- read-only: each counted enemy gets `{"position": slot, "slot": slot, "formation": formation, "entry": entry_kind}` (`entry` is a StringName, default `"top"`).
- `game/scenes/level/level.tscn` -- add `WaspDiveClock` (Node, script `res://entities/enemies/wasp/wasp_dive_clock.gd`) as a child of `WaveDirector`; bump `load_steps`. Root children stay unchanged (`test_level.test_tree`).
- `game/entities/player/player.gd` `_ready` L38 -- add `add_to_group(&"player")`.
- `game/scenes/sandbox/sandbox.gd` L107, L131 -- read-only: spawns Wasps with `{"position": slot}` only.
- `game/data/tuning.json` `enemies.wasp` -- add `zone_height_ratio`, `wing_flash_hz`, `wing_flash_energy`. `weapons.enemy_bullet.min_telegraph_s` (0.3) is the rule's threshold. Telegraph-like keys today: `telegraph_s` (wasp, lancer, bastion, boss.turrets), `lock_s` (needle), `charge_s` (boss.core), `radial_charge_s`, `aimed_telegraph_s` (boss.desperate).
- `game/tests/unit/test_wave_director.gd` L142, L149 -- assert `global_position` equals the slot; change them to `(enemy as Wasp).formation_slot()` (the spawn point is now the entry point).
- `game/tests/unit/test_enemy.gd` L153 `test_wasp_holds_position` -- stays valid (no slot → HOLD).
- `game/tests/data/test_data_files.gd` -- add the two data checks; `Formation.rows_used(formation, count, spacing, width)` and `waves.formation` tuning give the row math.
- `game/tests/unit/test_level.gd` -- style for level tests (preload scene, `add_child_autofree`, restore `Config.load_data()`).
- New `class_name`s (`Wasp`, `WaspDiveClock`) need `--import`; commit the new `.gd.uid` files.

## Tasks & Acceptance

**Execution (write each test first, red, then the code):**
- `game/data/tuning.json` -- add `"zone_height_ratio": 0.4, "wing_flash_hz": 10, "wing_flash_energy": 2.0` to `enemies.wasp` -- the zone and flash are tunable.
- `game/entities/enemies/wasp/wasp.gd` -- the state machine per the Always rules and matrix. TELEGRAPH blinks `Hull.self_modulate` between white and `Color(e, e, e)` at `wing_flash_hz` and restores white on leaving it.
- `game/entities/enemies/wasp/wasp_dive_clock.gd` -- `class_name WaspDiveClock extends Node`; `rng`, `step(delta)`, `time_left()`; `_ready` reads the interval and draws the first deadline.
- `game/scenes/level/level.tscn` -- add `WaveDirector/WaspDiveClock`.
- `game/entities/player/player.gd` -- join group `player`.
- `game/tests/unit/test_wasp.gd` -- every matrix row except Clock, plus: speeds and telegraph read from tuning (change a value via `Config.tuning`, restore with `Config.load_data()`), a source scan that `_state =` occurs exactly once, and `start_dive()` ignored outside HOLD.
- `game/tests/unit/test_wasp_dive_clock.gd` -- the Clock and Pause rows with a seeded rng; deadlines within [min, max]; dead/entering/diving Wasps never picked.
- `game/tests/unit/test_wave_director.gd` -- the two slot assertions above.
- `game/tests/unit/test_level.gd` -- `WaveDirector/WaspDiveClock` is a `WaspDiveClock`; the Player is in group `player`; level_dev's counted Wasps start above y 0 with slots inside the top 40%.
- `game/tests/data/test_data_files.gd` -- (1) recursively over `tuning.enemies` and `tuning.boss`, every key named `telegraph_s`, `lock_s`, `charge_s` or ending in `_telegraph_s`/`_charge_s` is ≥ `weapons.enemy_bullet.min_telegraph_s`, and the walk finds the wasp, lancer, needle, bastion and boss entries (not vacuous); (2) in every level file, a wave containing a Wasp entry stacks its spawn and group rows so the last row's y ≤ `zone_height_ratio × 1080`.
- `_bmad-output/game-architecture.md` -- a short "As-built 2026-10-07 (Story 2.4)" note: Wasp states, `WaspDiveClock` under `WaveDirector`, the Player's `player` group, the three new tuning keys.
- Run `--import`, then the full GUT suite.

**Acceptance Criteria:**
- Given level_dev started normally, when wave 1 spawns, then each Wasp starts off-screen per its `entry` and flies at `entry_speed_px_s` to its slot (y ≤ 40% of 1080), then holds.
- Given Wasps holding formation in a level, when the clock's random 3–5 s deadline passes, then exactly one holding Wasp flashes and stays still for `telegraph_s`, then dives toward the player's position at `dive_speed_px_s`.
- Given a diving Wasp leaving the screen, when it crosses the edge, then it re-enters from the top, returns to its slot, and the wave's resolved count is unchanged.
- Given `tests/data/test_data_files.gd`, when it runs, then every telegraph duration in `tuning.enemies` and `tuning.boss` is ≥ 0.3 s.
- Given the headless GUT suite, when it runs, then the new tests pass and no previously passing test fails.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 28 findings — high 0, medium 1, low 24, false 3, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind: AC3 "resolved count unchanged" tested only as the Wasp's own `resolved` signal — added `test_wasp_leaving_the_screen_does_not_resolve` in `test_wave_director.gd` (dive out, return to HOLD under a real director; `resolved_count` 0, `total_count` 1, no `wave_cleared`).
  - `[low]` `[reject]` Blind: the clock is never exercised inside a real level — the unit tests cover the pick/cadence logic and `test_level` covers the wiring (node present, inherits pause, Wasps in `enemies`); a real-level run needs 3–5 s waits or new stepping infrastructure for little extra coverage.
  - `[low]` `[reject]` Blind: `entry` values aren't validated in level data — a typo logs a runtime WARN and falls back to top (tested); a validator branch adds code for an unlikely authoring slip.
  - `[medium]` `[patch]` Blind: the zone data test checks the wave's total rows whenever a Wasp is present, so Lancer/Bastion rows stacked below the Wasps (Stories 2.5/2.7 data) would fail it falsely — rewritten to mirror the director's row stacking and check only each Wasp entry's own slots.
  - `[low]` `[reject]` Blind: the telegraph check relies on key names — the test pins all 8 current telegraph paths, so today's tuning is fully covered; an explicit key classifier is more machinery than the risk.
  - `[low]` `[patch]` Blind: the new Wasp tuning keys have no range checks — added `test_wasp_tuning_ranges` (speeds > 0, 0 < min ≤ max, 0 < zone ≤ 1, flash hz > 0, energy > 1).
  - `[low]` `[patch]` Blind: the blink rate isn't tested — the telegraph test now counts flash toggles ≈ `telegraph_s × wing_flash_hz × 2` (±1).
  - `[low]` `[reject]` Blind: tests hard-code tuning-derived numbers (-32, 35, 60, 432, 8 Wasps) — deliberate pins tying behaviour to the GDD numbers, the same choice accepted in Story 2.3; tuning changes update one assertion set.
  - `[low]` `[reject]` Blind: the level test assumes every level_dev Wasp enters from the top — it documents the current dev data; sides entry through the director is now covered in `test_wave_director.gd`.
  - `[low]` `[reject]` Blind: slot clamping warns per Wasp and stacks clamped Wasps on one row — only reachable with bad level data, which the zone data test now rejects; the WARN is the backstop.
  - `[low]` `[reject]` Blind: Wasps can be hit while partly off-screen during entry — the hitbox (r 25.6) at y −32 barely reaches the screen and entry lasts under a second; no player-visible harm.
  - `[false]` `[reject]` Blind: the clock keeps running between waves / after level clear and dives Wasps — a wave clears only when every counted enemy resolved, so no holding Wasp exists in the gap or after `level_cleared`; comms beats arrive in Epic 5.
  - `[low]` `[reject]` Blind: the `_state =` source scan is fragile — it passes on the real source and a comment match would fail loudly, not silently; hardening it is not worth the code.
  - `[false]` `[reject]` Blind: slotless Wasps can be picked by the clock — slotless Wasps exist only in the sandbox, which has no clock; every WaveDirector spawn passes `slot`.
  - `[low]` `[patch]` Edge: a slot x outside the playfield (e.g. grid_14x1) would leave a Wasp holding off-screen, unkillable — same root as the zone-test row: the rewritten data test asserts every Wasp slot x is in [sprite_px/2, 1920 − sprite_px/2].
  - `[low]` `[patch]` Edge: `entry_speed_px_s` ≤ 0 keeps a Wasp in ENTER forever — covered by `test_wasp_tuning_ranges`.
  - `[low]` `[patch]` Edge: `dive_speed_px_s` ≤ 0 keeps a Wasp in DIVE forever — covered by `test_wasp_tuning_ranges`.
  - `[low]` `[patch]` Edge: `dive_interval_s` min ≤ 0 or min > max dives every frame — covered by `test_wasp_tuning_ranges`.
  - `[low]` `[reject]` Edge: the overshoot below 0 is dropped when the next interval is drawn — drift is at most one physics tick per 3–5 s, imperceptible, and the spec defines each interval as drawn from the dive moment.
  - `[low]` `[patch]` Edge: the side-exit DIVE loop in `test_wasp.gd` has no cap and would hang the suite on a regression — capped at 10 s, then asserts ENTER.
  - `[low]` `[patch]` Edge: the wait-for-DIVE loop in `test_wasp_dive_clock.gd` has no cap — capped at 3 s, then asserts DIVE.
  - `[low]` `[patch]` Edge: the zone data test counts rows for unknown-type entries, which the director skips — same root as the zone-test row; the rewrite skips them without advancing the row.
  - `[low]` `[patch]` Verification gap: no test sends `"entry": "sides"` from wave data through WaveDirector → Spawner → Wasp — added `test_sides_entry_reaches_the_wasp`.
  - `[low]` `[reject]` Intent: no assembled-level test runs the full enter → pick → dive → return loop — same as the Blind clock-in-level row; each link is tested, and the director-level return is now tested.
  - `[false]` `[reject]` Intent: "exits the bottom" was widened to any edge — a superset: a bottom exit behaves exactly per the AC, and side exits (possible when aiming at a far-side player) re-enter instead of leaving a Wasp stranded; recorded in Design Notes.
  - `[low]` `[patch]` Intent: "does not resolve" not tested through the director — same root as the first Blind row; fixed there.
  - `[low]` `[reject]` Intent: two `test_wave_director` assertions now check the stored slot rather than the position — Wasps now spawn at their entry point by design; arrival at the slot is tested in `test_wasp.gd`.
  - `[low]` `[reject]` Intent: the telegraph rule depends on a naming heuristic — same as the Blind naming row.

### 2026-10-07 — Review pass
- verdicts: 27 findings — high 0, medium 0, low 21, false 6, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind: `test_dead_and_busy_wasps_are_never_picked` runs 10 deadlines, so it passes even without the clock's own filter, because `start_dive()` ignores busy or dead Wasps and `target` gets picked eventually — now one deadline, and the first pick must be `target`. Mutation check: with the filter removed, the test fails.
  - `[low]` `[reject]` Blind: `entry` values aren't validated in level data — carried: a typo logs a runtime WARN and falls back to top (tested); a validator branch adds code for an unlikely authoring slip.
  - `[low]` `[reject]` Blind: clamping slots below the zone stacks Wasps on one row — carried: only reachable with bad level data, which the zone data test rejects; the WARN is the backstop.
  - `[low]` `[reject]` Blind: the zone check uses the slot centre, so a Wasp at y 432 reaches down to y 464, overlapping `player.bounds_y.min` 432 — the intent defines the zone by slot (`slot.y > zone_height_ratio × SIZE.y`); current data's lowest row is y 400; there's no player contact until Epic 3, and a margin rule would need a design decision.
  - `[low]` `[reject]` Blind: the clock ignores wave state, so a deadline during entry is used up and the first dive of a wave can wait up to about max + entry time — the intent explicitly says "with no holding Wasp it just draws the next interval"; at most one cadence slot is lost, at wave start.
  - `[false]` `[reject]` Blind: the as-built note says "no design decision changed" despite new values — `wing_flash_hz` and `wing_flash_energy` are tuning, not design decisions; the any-edge exit is a superset of the AC (already judged false in the first pass); no GDD decision is contradicted.
  - `[low]` `[reject]` Blind: the zone data test copies the director's row stacking rather than calling it — same root as the Edge and Verification-gap group-order rows: latent until waves have several groups (every level today has one group per wave), and a shared helper adds public surface to `Formation`/`WaveDirector`, which the intent's Never list rules out.
  - `[low]` `[reject]` Blind: the telegraph rule relies on key names — carried: all 8 current telegraph paths are pinned.
  - `[low]` `[reject]` Blind: no real-level run of the clock — carried: the logic and the wiring are tested separately.
  - `[low]` `[reject]` Blind: no test kills a Wasp mid-telegraph or mid-dive — Wasp does not override `Enemy._die()`, which emits `resolved` once and frees at once (`core/enemy.gd:67-75`, tested in `test_enemy.gd`); there is no Wasp-specific death path to break.
  - `[low]` `[reject]` Blind: the `_state =` source regex is brittle, and the initial `var _state = HOLD` bypasses `_enter_state` — carried for the regex; every Wasp runs `_enter_state` in `_ready()` before it is stepped, so the field initializer is never seen.
  - `[false]` `[reject]` Blind: the `formation` param is passed but unused — the director sends it to every enemy type; ignoring it does no harm, and none was named.
  - `[low]` `[patch]` Edge: `entry_speed_px_s` <= 0 — carried: already covered by `test_wasp_tuning_ranges` in the first pass; nothing new to do.
  - `[low]` `[patch]` Edge: `dive_speed_px_s` <= 0 — carried: covered by `test_wasp_tuning_ranges`; nothing new to do.
  - `[low]` `[patch]` Edge: a slot x outside the playfield — carried: the zone data test asserts every Wasp slot x is in [sprite_px/2, 1920 − sprite_px/2]; nothing new to do.
  - `[low]` `[reject]` Edge: rows below the zone clamp onto one row — carried (as the Blind clamp row).
  - `[false]` `[reject]` Edge: an exact `global_position == _slot` check fails under a non-identity parent transform — Wasps are parented by `Spawner` to `World/Enemies`, a plain Node2D with identity transform (`level.tscn`), and `move_toward` lands exactly on the target.
  - `[low]` `[reject]` Edge: the data test stacks groups in dictionary key order, but at runtime they stack in trigger order — real but latent (one group per wave in every level today); fixing it needs trigger-order parsing in the test, more than a direct correction, for a case developers won't hit yet.
  - `[false]` `[reject]` Edge: non-Wasp rows in a Wasp wave are not checked — the intent's check is "Wasp formations fit the top 40%"; Lancer and Bastion rows aren't Wasp formations, and the first pass deliberately narrowed the test for this reason (medium patch).
  - `[low]` `[reject]` Edge: clock overshoot drift — carried: at most one physics tick per 3–5 s.
  - `[low]` `[reject]` Verification gap: the zone data test's group order can diverge from trigger order (filed `defer`) — same root and reason as the Edge group-order row; caused by this story's new test, so it is not a pre-existing defer; latent, and the fix is more than a direct correction.
  - `[low]` `[reject]` Verification gap (other): the `_state` assignment test is a source scan — carried: the transitions are also covered by the behavioural tests.
  - `[low]` `[reject]` Intent: no test runs the clock, director Wasps and the real Player together in a running level — carried (as the Blind real-level row).
  - `[false]` `[reject]` Intent: pause is covered only by combining two tests — the clock and Wasp freeze tests plus `test_process_modes` (WaveDirector is INHERIT) cover it; nothing goes wrong.
  - `[false]` `[reject]` Intent: the telegraph data test covers more than the Wasp — consistent with the intent's "over tuning" and the GDD-wide NFR6 rule; not a defect.
  - `[low]` `[reject]` Intent: the zone test mirrors the director's algorithm instead of asking it — same root and reason as the Blind copied-stacking row; the extra x check came from the first pass's patch.
  - `[low]` `[reject]` Intent: the no-per-frame-allocation rule and sandbox/bench equivalence are not asserted by any test — code inspection confirms both: one group scan per deadline, a reused `_candidates`, one player lookup per dive, and a sandbox HOLD tick that only adds to `_t`.

## Design Notes

**Why a clock node.** The GDD says "every 3–5 s *one* Wasp dives", a formation-wide cadence that per-Wasp timers can't give (8 Wasps would dive about twice a second). The clock is behaviour, not spawning, so the WaveDirector's "decides what spawns" rule is untouched; it sits under `WaveDirector` so the level's fixed root tree stays as the architecture lists it. A sandbox has no clock, so Epic 1's respawning formation and the `--bench` load stay the same.

**Side exits.** A dive aimed at a player far to the side can leave through a side edge before the bottom; the off-screen rule treats any exit the same, so a Wasp can never be stuck off-screen.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0; class cache has `Wasp`, `WaspDiveClock`.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all pass except the known pre-existing `test_wave_director.gd` F3 timing failure, if it still reproduces.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --quit-after 600` -- expected: no ERROR or WARN lines.

## Auto Run Result

Status: done

**Summary:** This was a follow-up review pass on the finished Story 2.4 (the Wasp state machine ENTER/HOLD/TELEGRAPH/DIVE, `WaspDiveClock` under `WaveDirector`, the Player's `player` group, the three new Wasp tuning keys, and the telegraph and zone data tests). It found one small test weakness and fixed it. No game code changed in this pass.

**Files changed (this pass):**
- `game/tests/unit/test_wasp_dive_clock.gd`: `test_dead_and_busy_wasps_are_never_picked` now gives the clock a single deadline, so it actually tests the clock's holding, living and not-freed filter.
- This spec: the triage log and this result.

**Review findings:** 27 findings: high 0, medium 0, low 21, false 6.
- **Patched (1 new):**
  - The clock filter test. A mutation check with the filter removed makes it fail.
  - 3 more `patch` rows are carried from the first pass, with no new action.
- **Deferred:** none.
- **Rejected:** 23 rows. Each reason is in the triage log. In short:
  - 9 carried rejects: entry validation, clamp stacking (×2), the telegraph key-name heuristic, the real-level clock run (×2), the `_state` source scan (×2) and overshoot drift.
  - The group-order mismatch in the zone data test (×4: Blind, Edge, Verification gap, Intent). It is latent while every level has one group per wave. The fix needs trigger-order parsing or a new shared public helper.
  - The slot-centre zone vs the player's `bounds_y`. The intent defines the zone by slot, and there's no contact until Epic 3.
  - The clock redrawing during entry. This behaviour is defined by the intent.
  - No mid-dive kill test. Wasp uses the base death path, which is already tested.
  - The no-allocation rule and sandbox equivalence are not covered by tests. Code inspection confirms both.
  - False (6):
    - The as-built note wording.
    - The unused `formation` param.
    - Float equality under the parent transform.
    - Non-Wasp rows not checked.
    - Pause covered by combining tests.
    - The telegraph test's wider scope.
- **Follow-up review recommended: false.** This is a follow-up pass and no `high` was patched. Patched by verdict: high 0, medium 0, low 1.

**Verification:**
- `--import` exited 0.
- Full GUT suite: 38 scripts, 492 tests, all 492 passed (2908 asserts).
- `--headless --quit-after 600` exited 0 with no WARN or ERROR lines.
- Mutation check: with the clock filter reduced to `wasp != null`, `test_dead_and_busy_wasps_are_never_picked` fails (0/1). The source was restored afterwards.

**Residual risks:**
- All runs were headless. Nobody has watched a dive on screen, so the readability of the 2.0× flash at 10 Hz and the dive feel need a playtest. No feel or fun claim is made.
- Waves with several groups (Stories 2.5/2.7) need the zone data test to stack groups in trigger order. Today it uses dictionary key order, which is equivalent only while a wave has one group.
- Contact damage isn't wired until Epic 3, so diving Wasps pass through the player.
- The `test_wave_director.gd` F3 timing test is still fragile when run alone (see Story 2.3's deferred item).

