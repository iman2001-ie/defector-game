---
title: 'DW-107: make the ally-kill level test reliable'
type: 'chore'
created: '2026-10-14'
status: 'done'
baseline_revision: 47c0ee1e8ccd1b3c863eb59052b9df46ad5090b9
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `test_level.gd` `test_dev_ally_level_spawns_tarek_who_fires_and_scores` (Story 6.4) fails about 1 run in 12: headless, 25 single-test runs gave 2 failures, both "the ally scored a kill (by_ally)" after the full 15 s budget, while passing runs took 3.8 to 9.9 s in total. The failure logs show wave 1 resolving all 8 wasps (and wave 2 starting) with zero ally kills. The timing assumption is that Tarek (1 damage, 1 shot/s, no lead, aimed at the nearest enemy) lands 3 hits on one 3 HP wasp within 15 s. Meanwhile the `debug_invincible` player, left at its spawn point, destroys every diving wasp on contact, without crediting the ally, and absorbs the ally's partial hits. This is how the game is meant to play (the ally's 10-15% kill share is a playtest-tuned design target), not a game bug.

**Approach:** Fix only the test. Park the player (`PROCESS_MODE_DISABLED`, as the player-aim Lancer test already does) so nothing but the ally can resolve a wasp, and set `enemies.wasp.hp` to 1 in `Config.tuning` before the level is made, so the first bolt that lands is a credited kill. Keep every other assertion. Make the kill failure message report the ticks waited.

## Boundaries & Constraints

**Always:** Test-only change in `game/tests/unit/test_level.gd`. Statically typed GDScript. The test still runs on the real `level.tscn` with `dev_ally`, through `Spawner`, `AllyShip` firing and `Events.enemy_killed(..., by_ally)`, so it still fails if the ally never fires, its bolt isn't `from_ally`, or a kill isn't reported `by_ally`. Change tuning by mutating `Config.tuning` (the file's existing pattern; `after_each` restores it with `Config.load_data()`). The bolt `damage == 1` assertion stays (it reads the ally's damage, not wasp HP).

**Never:** No production code, scene or data/JSON edits. Don't delete the kill assertion or merely raise the 15 s budget. Don't edit `deferred-work.md`, `sprint-status.yaml` or `.bmad-loop/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Wasp dives toward the parked player | player disabled, so its Area2D is out of physics | the wasp leaves the screen, re-enters and holds its slot again; it is not destroyed | none |
| Ally targets a diving or entering wasp | the bolt misses | the next shot comes 1 s later; holding wasps stay as targets | none |
| First bolt lands | wasp HP is 1 | `enemy_killed(&"wasp", pos, true)`; the loop exits | none |
| Ally never kills (regression) | e.g. `from_ally` lost | the assertion fails after 15 s, printing the ticks waited | failure |

</intent-contract>

## Code Map

- `game/tests/unit/test_level.gd:1641-1680` -- the target test. Spawn and placement asserts, then `wait_physics_frames(30)` patrol check (2.5 px per tick, 2.0 px tolerance; deterministic, since physics delta is fixed; 25/25 runs passed it), then a frame-counted loop `15 * Engine.physics_ticks_per_second` that waits for `_ally_kills > 0`, then `assert_gt(_ally_kills, 0, ...)` at :1680 (the failing line).
- `game/tests/unit/test_level.gd:86-94` -- `_make_player_invincible()` and `_make_level(level_id)`. The tuning mutation must happen before `_make_level` (enemies read HP in `_ready`).
- `game/tests/unit/test_level.gd:1523-1530` -- the pattern to reuse: `player.debug_invincible = true; player.process_mode = Node.PROCESS_MODE_DISABLED`, and `((Config.tuning["enemies"] as Dictionary)["lancer"] as Dictionary)[...] = ...`.
- `game/tests/unit/test_level.gd:48-62` -- `after_each` calls `Config.load_data()` (restores the tuning).
- `game/core/enemy.gd:71,87-89,129,215-216` (read-only) -- `hp = _max_hp()` in `_ready` from `Config.int_("enemies.<type>.hp")`; `apply_damage` records `_last_hit_by_ally` from `source.from_ally`; `enemy_killed` emits it.
- `game/entities/player/player.gd:68-72` (read-only) -- small enemies are destroyed by player contact even while invulnerable: the competing resolver.
- `game/entities/enemies/wasp/wasp.gd:1-17` (read-only) -- a diving wasp that leaves the screen re-enters and holds its slot; it never resolves by leaving.
- `game/entities/allies/ally_ship.gd` (read-only) -- `_tick_fire` (1 shot per `fire_interval_s`), `nearest_target`, `aim` (no lead).
- `game/data/tuning.json` (read-only) -- `enemies.wasp.hp` 3; `allies.damage` 1, `fire_interval_s` 1.0.
- `game/data/levels/level_dev_ally.json` (read-only) -- wave 1 is 8 wasps (grid_4x2, top).

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_level.gd` -- in `test_dev_ally_level_spawns_tarek_who_fires_and_scores`: before `_make_level("dev_ally")` set `((Config.tuning["enemies"] as Dictionary)["wasp"] as Dictionary)["hp"] = 1`; after `_make_player_invincible()` set the player's `process_mode = Node.PROCESS_MODE_DISABLED`; add a short comment saying why (the player's contact kills are not the ally's, and one landed bolt must be the kill); include the ticks waited in the kill assertion message; update the doc comment above the test to mention the parked player and 1 HP wasps.

**Acceptance Criteria:**
- Given the edited test, when it is run alone headless 25 times in a row, then all 25 runs pass.
- Given the full GUT suite, when run headless after `--import`, then all tests pass.
- Given a regression where ally kills are not reported `by_ally`, when the test runs, then it still fails on the kill assertion.

## Design Notes

Parking the player removes the competing resolver, so wasps stay on screen until the ally kills one. 1 HP removes the "3 hits on one moving target" chance. Together they turn a probabilistic wait into "the first landed bolt", and holding wasps are stationary targets, so that comes within a few shots. Lowering HP doesn't weaken the check: crediting (`_last_hit_by_ally` from the last hit) works the same at any HP.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: completes.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gselect=test_level.gd -gunit_test_name=test_dev_ally_level_spawns_tarek_who_fires_and_scores -gexit` in a 25-run loop -- expected: 25/25 pass.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all pass.

## Spec Change Log

## Review Triage Log

### 2026-10-14 — Review pass
- verdicts: 14 findings — high 0, medium 0, low 9, false 5, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) The "(waited %d)" figure in the kill message always equals the budget, since the assertion can only fail once frames_left is 0 — removed it; the message now reads "... within %d physics ticks" % frame_budget.
  - `[low]` `[reject]` (blind) The test doesn't assert that no non-ally kill happened (the fix's premise) — needs a new counter and handler for a diagnostic only; 50 post-fix runs all finished in about 2 s, and a broken premise still fails the kill assertion.
  - `[false]` `[reject]` (blind) nearest_target favours fast divers, so 15 s may still run out — 50 post-fix single-test runs (25 implementer, 25 orchestrator) each finished in about 2.0 s of GUT time (two at about 3 s, one at 4.1 s), against a 15 s budget; a timeout needs 15 misses in a row.
  - `[low]` `[reject]` (blind) The spec records no run results — the fix is a spec edit; the results are recorded in Auto Run Result.
  - `[low]` `[reject]` (blind) The regression AC's method isn't given — the fix is a spec edit; the method (from_ally forced false, test failed after 900 ticks, file restored) is recorded in Auto Run Result.
  - `[low]` `[reject]` (blind) Code Map cites :1523-1530 for the parking pattern; it is at :1547-1549 (and :1430-1432, :1597-1598) — the fix is a spec edit.
  - `[low]` `[reject]` (blind) Fourth copy of the parking code, written as an inline cast instead of a typed local — style only; a shared helper adds surface across four tests for no behaviour change.
  - `[false]` `[reject]` (blind) "Crediting works the same at any HP" loses last-hit vs first-hit coverage — test_enemy.gd covers it: test_ally_source_flags_kill, test_player_kill_after_ally_hit_is_not_ally, test_contact_after_ally_hit_is_not_ally.
  - `[low]` `[reject]` (blind) _make_player_invincible() is redundant once the player is disabled — harmless, and matches the other parked-player tests (:1430-1432, :1547-1549), which also set debug_invincible.
  - `[false]` `[reject]` (intent) The fix edits the setup, not the wait — the intent asks to find the timing assumption and fix the test; the assumption (3 ally hits on one wasp before the player's contact kills resolve the wave) lives in the setup, and the wait is now reliable.
  - `[false]` `[reject]` (intent) Mixed-source kills under real tuning are no longer exercised here — covered by the test_enemy.gd ally-credit tests listed above.
  - `[low]` `[reject]` (intent) The ledger saw the flake in a full run, but the fix was checked single-test — the single-test failures match the ledger symptom exactly (the kill assertion after the full budget), and two full-suite runs after the fix passed 2183/2183.
  - `[low]` `[reject]` (intent) No run evidence in the diff — recorded in Auto Run Result.
  - `[false]` `[reject]` (intent) The artifact-only receipt does not apply — correct, and it is not asserted: the change edits a tracked test file.

## Auto Run Result

Status: done

**Summary:** Reproduced DW-107: before the fix, 25 single-test headless runs gave 2 failures, both "the ally scored a kill (by_ally)" after the full 15 s budget, while passing runs took 3.8 to 9.9 s. Cause: each wasp has 3 HP and Tarek fires 1 unled 1-damage shot per second. The `debug_invincible` player, left at its spawn point, destroys every diving wasp on contact (not credited to the ally), so in the failing runs wave 1 resolved all 8 wasps with no ally kill. This is intended gameplay, not a game bug. Fixed the test only: the player is parked (`PROCESS_MODE_DISABLED`, the file's existing pattern) and `enemies.wasp.hp` is set to 1 in `Config.tuning` (restored by `after_each`), so the first bolt that lands is a credited kill. The kill assertion message now names the tick budget.

**Files changed:**
- `game/tests/unit/test_level.gd` -- `test_dev_ally_level_spawns_tarek_who_fires_and_scores`: 1 HP wasps, parked player, comments, and the tick budget in the kill message.
- `_bmad-output/implementation-artifacts/spec-dw-107-ally-kill-test-flake.md` -- this spec.

**Review:** 14 findings (blind hunter 9, edge-case 0, verification-gap 0, intent alignment 5): 1 low patched (the always-equal "waited" figure was removed from the message), 0 deferred, 13 rejected. Each rejection and its reason is in the Review Triage Log above: 5 false; 4 whose only fix was a spec edit (the evidence is recorded here instead); a non-ally-kill counter; the parking helper's style; the redundant invincible call; and full-run vs single-run checking. Patched by verdict: high 0, medium 0, low 1. Follow-up review recommended: false.

**Verification:**
- `--import` ok.
- Target test alone, 25 runs after the fix: implementer 25/25, orchestrator 25/25 before the patch and 25/25 after it, each about 2.0 s of GUT time.
- Regression check (implementer): `from_ally` temporarily forced false in `ally_ship.gd`; the test failed on the kill assertion after 900 ticks; the file was restored with git.
- Full GUT suite: 2183/2183 passing, 100 scripts. Run by the implementer and by the orchestrator, before and after the patch.

**Residual risks:** This test no longer exercises ally kills under real wasp HP with the player in play. That mixed-source crediting is covered by the `test_enemy.gd` ally-credit tests. The ledger's original sighting was in a full-suite run; the single-test failures reproduced the same symptom.
