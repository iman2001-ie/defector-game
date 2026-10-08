---
title: 'DW-35/36/38/39: reliable F3 wave test and a real-kill level_dev clear test'
type: 'chore'
created: '2026-10-07'
status: 'done'
baseline_revision: '7f2cb06b8b350611057c20077f2e824b9d3a7492'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** `test_f3_resolves_the_wave_and_fires_pending_triggers_in_order` (`game/tests/unit/test_wave_director.gd:473-507`) asserts `_counted().size() == 0` after `wait_process_frames(2)` with `gap_s` 0.05. When those two headless frames take longer than 0.05 s, wave 2's single Wasp has already spawned and is counted, so the test fails in isolation (DW-35; DW-36 is its duplicate; retro item DW-39). Separately, every test against the shipped `level_dev.json` advances waves with F3, which marks unspawned groups as skipped, so the real kill → progress trigger → reinforcements → clear path never runs against shipped data (retro R3, DW-38).

**Approach:** Make the F3 test assert only what the skipped group could cause, independent of when the gap ends. Add a test that plays `level.tscn` with `level_dev` to LEVEL CLEAR by killing spawned enemies with `apply_damage`, and asserts no stall ERROR was logged.

## Boundaries & Constraints

**Always:** Tests only: no production code or data changes. Statically typed GDScript. Use the existing fixtures and helpers (`_counted`, `_lines_containing`, `_events_named`, `_capture`, `_make_level`). Every wait in the new test is bounded by a deadline so a regression fails, never hangs. Restore `Log.sink` and Config in teardown (existing `after_each` already does).

**Never:** Call `debug_resolve_wave()`/F3 or `debug_skip_to_boss()` in the new test. Do not weaken the other assertions of the F3 test (resolved == total == 8, three progress triggers, 0.25 before 0.75, one wave_cleared, next wave starts). Do not edit `deferred-work.md` or `sprint-status.yaml`. Do not add a new `tests/` subfolder (the architecture lists only `unit/` and `data/`).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| F3 test, fast frames | gap not yet elapsed after F3 | Passes: group `r` never spawned | No error expected |
| F3 test, slow frames | gap elapses within the post-F3 wait, wave 2 Wasp spawned | Still passes: assertions ignore wave 2's Wasp | No error expected |
| Skipped group regression | group `r` spawns after F3 | Fails: a `group 'r' spawned` INFO line exists, or more than 1 counted enemy alive after wave 2 starts | Assertion failure |
| Real-kill clear | level_dev, kill every live counted enemy repeatedly | `level_cleared(0)` once, banner visible, `reinforcements` spawned once, 6 wave starts, no `stalled` line, no `[ERROR][wave]` line, no F3 line | Bounded loop fails with a clear message on timeout |

</intent-contract>

## Code Map

- `game/tests/unit/test_wave_director.gd:473-507` -- the flaky F3 test. `:487` is `_director.debug_resolve_wave()`; `:504-507` are the timing-dependent `wait_process_frames(2)` / `_counted().size() == 0` and the next-wave check. Helpers: `_counted()` `:96`, `_lines_containing()` `:69`, `_events_named()` `:77`, `GAP_S` 0.05 `:6`.
- `game/systems/waves/wave_director.gd` -- read-only. `_spawn_group()` `:316-331` logs `Level %d wave %d: group '%s' spawned` (INFO, category `wave`) only when a group really spawns; F3 cancels pending groups (`:174-180`). `_check_stall()` `:400-416` logs `[ERROR][wave] ... stalled with ...`. `_try_clear()` waits `gap_s` (`create_timer(_gap_s, false)`) then `start_wave(index + 1)` or `_finish_level()` (`Level %d cleared`).
- `game/core/enemy.gd:49-80` -- `apply_damage(amount, source)`; `source` may be null; `_die()` emits `resolved` once and `queue_free()`s. `is_dead()` `:69`.
- `game/data/levels/level_dev.json` -- read-only. 6 waves; wave 2 has 6 Wasps + group `reinforcements` (4 Wasps) fired at progress 0.5 after a 1.0 s wait; wave 6's Hunter Wasps are flag-gated off by default (only 6 Wasps count). Longest chain 1.0 s.
- `game/tests/unit/test_level.gd` -- home of level_dev scene tests. Reuse `_make_level()` `:47`, `_capture` `:26`, `_cleared` / `_on_level_cleared`, `after_each` (restores Log.sink, Config, PauseArbiter). Pattern to mirror (but without F3): `test_clearing_every_dev_wave_clears_the_level` `:207-231`.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_wave_director.gd` -- In the F3 test replace the `await wait_process_frames(2)` + `_counted().size() == 0` pair: after the existing `wave_cleared` assert, `await wait_seconds(GAP_S + 0.1)`, assert 2 `wave_started` events, assert `_lines_containing("group 'r' spawned").size() == 0` ("the skipped group never spawns"), and assert `_counted().size() == 1` ("only wave 2's Wasp is alive"). Keep every other assertion. -- Asserts on the skipped group, so the outcome no longer depends on whether the gap elapsed during a frame wait.
- `game/tests/unit/test_level.gd` -- Add `test_dev_level_clears_with_real_kills_and_no_stall` after `test_clearing_every_dev_wave_clears_the_level`: set `waves.gap_s` 0.05, `Log.sink = _capture`, `_make_level()`; loop while not `director.is_level_cleared()` and elapsed < 15 s: call `apply_damage(maxi(enemy.hp, 1), null)` on every `Enemy` in `World/Enemies` that is counted, not dead and not queued for deletion, then `await wait_seconds(0.1)`. Then reset `Log.sink` and assert: cleared within 15 s; `_cleared == [0]`; banner visible; 6 `[INFO][wave] Level 0 wave N/6 started` lines; exactly 1 line containing `group 'reinforcements' spawned`; zero lines containing `stalled`; zero lines beginning `[ERROR][wave]`; zero lines containing `F3`. -- Covers the shipped-data kill → trigger → reinforcements → clear path (R3).

**Acceptance Criteria:**
- Given `test_wave_director.gd` run alone, when it is run 5 times in a row, then every run reports 0 failures.
- Given the full suite, when it runs headless, then it reports 0 failures and the new test is counted as passing.
- Given the new level test, when the stall net would fire (for example a group that never spawns), then the test fails on the `stalled` / `[ERROR][wave]` assertion rather than timing out silently.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 16 findings — high 0, medium 0, low 11, false 5, maybe-false 0
- findings:
  - `[low]` `[patch]` F3 test: "skipped group never spawns" rests only on a missing INFO line and would pass vacuously if the log text changed — added an assertion that the `[DEBUG][beat] Group 'r' was skipped` line appears once, proving the skip path ran.
  - `[low]` `[reject]` F3 test: `_counted().size() == 1` couples to wave 2's content — wave 2 is the literal fixture in the same test; any change there is made alongside the assertion. No named harm.
  - `[low]` `[patch]` Real-kill test: timeout message gives no clue where it stuck — message now includes wave number and resolved/total.
  - `[false]` `[reject]` Real-kill test does not check the "was skipped" line or the level-cleared line — the stall net always logs the `stalled` ERROR when it skips a group (`wave_director.gd` `_check_stall`), which is asserted absent; `_cleared == [0]` asserts the single clear.
  - `[low]` `[reject]` `F3` substring check adds little — harmless guard; replacing it adds nothing.
  - `[low]` `[reject]` Wave count 6 and group name hard-coded — the test intentionally pins shipped data, as the sibling level_dev tests do; a data change must revisit them anyway.
  - `[false]` `[reject]` Hit-stop not isolated / no `Feedback.reset()` in teardown — `Feedback.hit_stop` ends itself via a time-scale-ignoring timer and stops never stack beyond the latest end time; the deadline is wall-clock; a failure mid-stop still self-restores.
  - `[low]` `[reject]` Spec matrix "fast frames" row is no longer distinct — fix edits this build's spec.
  - `[low]` `[reject]` Spec lacks recorded verification evidence and DW-close owner — fix edits this build's spec; evidence is recorded under Auto Run Result, the orchestrator closes the ledger.
  - `[low]` `[reject]` Spec Code Map line numbers go stale — fix edits this build's spec; lines are from `baseline_revision`.
  - `[false]` `[reject]` Edge: paused tree would hang the loop — nothing in the level pauses the tree without input (PauseArbiter is cleared in teardown, no focus-loss pause exists), so the bounded loop always rechecks the deadline.
  - `[false]` `[reject]` Edge: hit-stop slows game timers so the deadline may fail spuriously — hit-stops are milliseconds per kill batch; the run finishes in a few seconds against a 15 s budget (5/5 + full-suite passes).
  - `[low]` `[reject]` Edge: wave count hard-coded — duplicate of the hard-coded-data row; same reason.
  - `[low]` `[reject]` Edge: F3 check is only a substring heuristic — the test never calls F3; the check is a cheap guard, not the proof.
  - `[false]` `[reject]` Intent: F3 fix is a hybrid of the two named options — the assertions now target only the skipped group (skip line, no spawn line, nothing beyond wave 2's one Wasp), which is the first named option; not a defect.
  - `[low]` `[reject]` Intent: the real-kill test overrides `waves.gap_s` to 0.05 instead of shipped tuning — the gap length does not affect the kill → trigger → reinforcements → stall path under test; shipped level data is used unchanged.

### 2026-10-07 — Review pass
- verdicts: 18 findings — high 0, medium 0, low 11, false 7, maybe-false 0
- findings:
  - `[low]` `[reject]` Real-kill test hard-codes the wave count 6 instead of `director.wave_count()` — carried: the test intentionally pins shipped data, as the sibling level_dev tests do.
  - `[low]` `[patch]` `line.contains("F3")` also matches the stall-net line `Group '...' was skipped (F3 or stall net)` (`wave_director.gd:311`), so a stall would also report a misleading "resolved with F3" failure — now matches the real F3 log prefix `[INFO][debug] F3:` (same prefix `test_debug_tools.gd:441` uses).
  - `[low]` `[reject]` `stalled` and `[ERROR][wave]` checks overlap; bare `stalled` could match an unrelated line — redundancy is harmless, and a stray match fails loudly rather than passing; no such line exists today.
  - `[false]` `[reject]` Wall-clock deadline vs engine-time waits may fail on a loaded CI host — carried: the run finishes in a few seconds against a 15 s budget; the deadline only bounds a hang.
  - `[low]` `[reject]` Reinforcements count does not check it fired in wave 2 — `reinforcements` is a wave-2-only group in `level_dev.json`, so the line can come from no other wave; tightening the string adds nothing in everyday use.
  - `[false]` `[reject]` Nothing proves every counted enemy died by a kill — the only non-kill resolution paths are F3 (`[INFO][debug] F3:` asserted absent) and the stall net (`stalled` / `[ERROR][wave]` asserted absent); the level only clears when resolved == total.
  - `[low]` `[reject]` Batch kills jump wave-2 progress past 0.5 instead of crossing it one kill at a time — the intent's matrix specifies "kill every live counted enemy repeatedly"; single-kill crossing is covered by the WaveDirector unit tests on progress triggers.
  - `[false]` `[reject]` Real-kill test does not check the `Level 0 cleared` log line — carried: `_cleared == [0]` asserts the single clear.
  - `[low]` `[reject]` F3 test `_counted().size() == 1` is coupled to wave 2's `_wasps(1)` literal — carried: same-test fixture, changed together.
  - `[false]` `[reject]` F3 test lost its in-gap no-spawn check — every real group spawn logs `group '<name>' spawned` (`wave_director.gd:329`), so a spawn of `r` at any time up to the post-gap assert is caught by the zero-line assertion, and the skip line proves the request was refused.
  - `[low]` `[reject]` Edge: Level id 0 and 6 waves hard-coded — carried: duplicate of the hard-coded-data row.
  - `[low]` `[patch]` Edge: stall-net skip counted as F3 — same root cause as the F3 substring row; fixed by the same prefix match.
  - `[low]` `[reject]` Edge: `reinforcements` group name hard-coded — carried: intentional pinning of shipped data.
  - `[false]` `[reject]` Intent: the in-gap state ("fast frames" row) is no longer exercised — the assertions hold in both rows; the spawn-line check covers the in-gap window (see the in-gap row above).
  - `[low]` `[reject]` Intent: the live count is exact (`== 1`) rather than ignored/capped — carried: same as the `_counted` coupling row; after `GAP_S + 0.1` wave 2's Wasp has spawned and wave 1's dead Wasps are freed, 5/5 isolated runs green.
  - `[low]` `[reject]` Intent: a group-`r` spawn later than `GAP_S + 0.1` would not be caught — once wave 2 starts, wave 1's groups no longer apply; waiting longer only adds runtime for a path the code does not have.
  - `[false]` `[reject]` Intent: the real-kill test loops `_lines` inline instead of `_lines_containing` / `_events_named` — those helpers do not exist in `test_level.gd`; the inline loops are equivalent, no bad outcome.
  - `[false]` `[reject]` Intent: the 15 s deadline is unproven on a slow runner — carried: duplicate of the wall-clock deadline row.

## Design Notes

Why not just raise `gap_s` for the F3 test: it would still be a timing race, only a wider one. Asserting after the gap (when the state is settled) and checking the group's own INFO line removes the race entirely. Wave 2's lone Wasp is the only counted enemy that may exist once wave 2 has started, so `_counted().size() == 1` also catches a stray group spawn of up to 4 Wasps.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_wave_director.gd -gexit` (5 times) -- expected: 0 failures each run
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass

## Auto Run Result

Status: done

**Summary:** Made the F3 wave test independent of frame timing (it now asserts on the skipped group after the gap has settled) and added a level test that plays the shipped `level_dev.json` to LEVEL CLEAR with real `apply_damage` kills and asserts no stall ERROR. Resolves DW-35, DW-36 (duplicate), DW-39 and DW-38. Tests only; no production code or data changed. A follow-up review pass (2026-10-07) tightened the real-kill test's F3 check.

**Files changed:**
- `game/tests/unit/test_wave_director.gd` -- F3 test: removed the 2-frame wait / zero-count race; after the gap asserts wave 2 started, the group 'r' skip line logged once, no 'r' spawn line, and only wave 2's one Wasp alive.
- `game/tests/unit/test_level.gd` -- new `test_dev_level_clears_with_real_kills_and_no_stall` (wall-clock-bounded kill loop, no F3); follow-up pass: F3 check matches the `[INFO][debug] F3:` prefix, not any line containing `F3`.
- `_bmad-output/implementation-artifacts/spec-dw-35-dw-38-wave-test-reliability.md` -- this spec.

**Review findings:**
- First pass: 16 findings. Patches 2 (low: skip-line assertion, diagnostic timeout message), deferred 0, rejected 14 (reasons in the first Review Triage Log entry).
- Follow-up pass: 18 findings. Patches 1 entry (2 low rows, one root cause: `contains("F3")` also matched the stall-net "(F3 or stall net)" line), deferred 0, rejected 16. Each rejection's reason is in the second Review Triage Log entry: 7 false; 9 low covering carried data pinning, harmless redundancy, intent-specified batch kills, and unreachable late spawns.

**Follow-up review recommendation:** false. This is a follow-up pass and patched high 0, medium 0, low 1 entry, so the work has converged.

**Verification:**
- `test_wave_director.gd` alone, 5 runs after the follow-up patch: 26/26 passing each run, exit 0.
- Full suite headless after the follow-up patch: 614/614 passing, exit 0; `test_dev_level_clears_with_real_kills_and_no_stall` runs and passes.

**Residual risks:** The real-kill test relies on the player taking no damage; once Epic 3 adds player damage, it may need an invulnerable player. The stall-catching assertion was reasoned from code, not proven with a deliberately broken level.
