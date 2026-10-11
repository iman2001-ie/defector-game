---
title: 'DW-74, DW-79, DW-84: harden wall-clock and frame-timing sensitive GUT tests'
type: 'chore'
created: '2026-10-11'
status: 'done'
baseline_revision: 02353b97c6057c0de6feb55dc9f4c2d34ef85806
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

**Problem:** Three GUT tests fail intermittently on slow headless frames. (DW-74) `test_feedback.test_hit_stop_overlap_keeps_longest` asserts the resume is seen < 250 ms after start; one stalled frame made it 356 ms. (DW-79) `test_shake_camera.test_process_drives_shake` shakes for 0.25 s and checks after 3 process frames; three large deltas decay the shake to 0, so the offset is `Vector2.ZERO`. (DW-84) an unidentified test in `test_level.gd` failed once; the audit found two real-time checks there that depend on wall-clock pacing: the convoy Lancer test's fixed 2 px aim tolerance (the convoy drifts ~0.67 px per physics tick, so a catch-up burst of 3+ ticks between shot and poll breaks it) and the Maul test's wall-clock `>= 300 ms` telegraph check (a catch-up burst advances game time without wall time).

**Approach:** Keep every test's intent but measure in the clock the game actually uses: track the largest frame gap while polling a hit-stop resume and turn a late resume caused by a frame stall into `pending` (same pattern as the existing "second hit_stop came too late"); drive the shake-camera `_process` test with a long shake and a bounded frame loop; measure the convoy/Maul checks in physics ticks (`Engine.get_physics_frames()`) instead of milliseconds or a fixed pixel bound. Failure messages carry the measured values.

## Boundaries & Constraints

**Always:** Test-only changes in the three test files. Statically typed GDScript. Each hardened assertion still fails for the bug it guards (a hit-stop that never ends or runs far too long; `_process` not driving `step()`; a Lancer shot not aimed at a ship centre; a Maul reaching the band before the telegraph minimum). Read tuning numbers (`convoy.speed_px_s`, `weapons.enemy_bullet.min_telegraph_s`) through `Config`; tick rate via `Engine.physics_ticks_per_second`. Every new or changed assertion message includes the measured value(s) (ms, ticks, px) so a failing run identifies itself.

**Never:** No production code changes (`feedback.gd`, `shake_camera.gd`, `lancer.gd`, `convoy.gd`, `maul.gd` untouched). No data/tuning edits. No blanket bound widening without the stall evidence; no deleting the checks. Don't edit `deferred-work.md`, `sprint-status.yaml` or `.bmad-loop/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Hit-stop, smooth frames | all poll gaps <= 60 ms | resume < 250 ms asserted as today | No error expected |
| Hit-stop, one stalled frame | resume >= 250 ms and largest gap (incl. time before polling) > 60 ms | `pending` naming the gap and resume ms | not a failure |
| Hit-stop stuck / overlong | resume >= 250 ms with smooth frames, or never resumes | assertion fails with ms values | failure |
| Shake `_process`, any deltas | `shake(8, long duration)`, process enabled | within a bounded frame budget amplitude drops below 8 and offset is non-zero and inside the square | fail after budget with message |
| Convoy aim, catch-up burst | N physics ticks since previous poll | miss px < speed * (N + 1) / tps + margin | fail prints miss px and N |
| Maul telegraph | hit tick recorded in the HP handler | (hit tick - detection tick + 1) / tps >= min_telegraph_s | fail prints ticks |

</intent-contract>

## Code Map

- `game/tests/unit/test_feedback.gd:57-62` -- `_await_resume(start_usec, limit_ms)`; extend it to record the largest gap between observations into a member (initial gap = time already elapsed before polling). Used by `test_hit_stop_overlap_keeps_longest` (:315, bound :331) and `test_hit_stop_extend` (:334, bound `second_ms + 250` :348) -- apply the same stall guard to both.
- `game/tests/unit/test_shake_camera.gd:86-91` -- `test_process_drives_shake`. `ShakeCamera` (`game/systems/camera/shake_camera.gd`, read-only): `step(delta)` decays `_remaining` linearly, offset random in +-amp; `_process` calls `step`.
- `game/tests/unit/test_level.gd:1356` -- `_on_convoy_hp` handler (append a tick record alongside `_hp_values`); `:1374` `_wait_for_wave`.
- `game/tests/unit/test_level.gd:1385-1456` -- `test_dev_convoy_maul_wave_hits_the_convoy`; `spawn_ms` (:1411) and wall-clock assert (:1445) -> physics ticks.
- `game/tests/unit/test_level.gd:1482-1520` -- `test_dev_convoy_lancer_shots_hit_the_convoy_for_five`; `assert_lt(best, 2.0)` (:1515) -> tick-scaled tolerance.
- `game/tests/unit/test_level.gd:1523-1548` -- player-aim Lancer test: player parked (`PROCESS_MODE_DISABLED`), so its 0.01 px bound is not timing-dependent; only add measured values to messages.
- `game/entities/allies/convoy.gd:87-93` -- convoy moves in `_physics_process` at `convoy.speed_px_s` (40). Lancer aims at `ship.global_position` with no lead (`lancer.gd:_fire`).

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_feedback.gd` -- add gap tracking to `_await_resume` with a doc comment explaining the 60 ms threshold (deadline + two gaps of <= 60 ms stays under the 250 ms margin); in both hit-stop timing tests, when the resume bound is exceeded and the largest gap > 60 ms, call `pending(...)` with the values, else assert as before.
- `game/tests/unit/test_shake_camera.gd` -- shake with a long duration (e.g. 1000 s), await process frames until amplitude < 8 or a budget (e.g. 60 frames) runs out; assert amplitude decayed, offset non-zero and within +-amplitude, messages include frame count and values.
- `game/tests/unit/test_level.gd` -- Lancer convoy test: record `Engine.get_physics_frames()` each poll; tolerance `speed_px_s * (ticks_since_last_poll + 1) / tps + 0.5`. Maul test: record the detection tick and the tick of the first convoy HP change (in the handler); assert tick-based duration with one tick of slack. Add measured values to messages in both Lancer tests.

**Acceptance Criteria:**
- Given the full GUT suite, when run headless, then it passes with no new failures.
- Given each of `test_feedback.gd` and `test_shake_camera.gd`, when run 15 times in a row headless, then no failure occurs (pending allowed).
- Given `test_level.gd`, when run 8 times in a row headless, then no failure occurs.

## Spec Change Log

## Review Triage Log

### 2026-10-11 — Review pass
- verdicts: 23 findings — high 0, medium 0, low 15, false 8, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) Stall guard counts any gap, incl. pre-poll and pre-deadline, so an overlong hit-stop in a run that also stalled becomes pending — only in runs with a >60 ms stall; smooth runs still fail an overlong stop; the fix needs a deadline parameter, not worth it.
  - `[low]` `[reject]` (blind) Maul tick count overstates game time under time_scale < 1 — same weakness as the old wall-clock check; the geometric to_band assertion is the primary guard and the real flight (~1.5 s) is far above 0.3 s.
  - `[false]` `[reject]` (blind) One tick of slack unjustified for other spawn paths — Mauls start at top_y 160 and dive 600 px to band 760 at 400 px/s (>= 1.5 s); a false failure needs >70 ticks of detection lag, and the existing "at its slot's y" check already bounds lag to 2 ticks.
  - `[low]` `[reject]` (blind) `_hp_ticks` cleared but unused in the Lancer test — clearing keeps the same-index invariant with `_hp_values`; harmless.
  - `[low]` `[patch]` (blind) `+ 0.5` px margin unexplained — comment added (float error in _ray_miss_px and ship placement).
  - `[false]` `[reject]` (blind) Shake test no longer shows a shake running out — test_keep_strongest covers decay to 0 and offset cleared via step().
  - `[low]` `[patch]` (blind) Zero-delta cause hidden in the shake failure message — message now prints Engine.time_scale and PauseArbiter.is_paused().
  - `[low]` `[reject]` (blind) `_max_gap_ms` is shared state between helpers — always called back to back within one test; no caller diverges.
  - `[low]` `[reject]` (blind) Spec lacks repeat-run evidence — fix edits the spec; runs are recorded in Auto Run Result.
  - `[low]` `[reject]` (blind) Code Map line numbers stale / DW-84 culprit unconfirmed — fix edits the spec; residual risk recorded below.
  - `[low]` `[reject]` (edge) Pre-deadline stalls trigger pending — same as the first row.
  - `[low]` `[reject]` (edge) Pre-poll time seeds the gap — same as the first row.
  - `[false]` `[reject]` (edge) Mauls spawned several ticks before detection give a false failure — see the slack row: >1.2 s of margin.
  - `[low]` `[reject]` (edge) time_scale != 1 during Maul flight — same as the second row.
  - `[false]` `[reject]` (edge) Bullets alive before the poll loop have untracked age — Lancers go ENTER -> STRAFE -> TELEGRAPH before the first `_fire`, and the loop starts on the frame wave 2 begins.
  - `[low]` `[patch]` (edge) Comment claims catch-up bursts run several ticks between polls, but awaiting physics_frame resumes every tick — comment rewritten (ticks_since normally 1); behaviour matches the old 2.0 px bound for whole-tick ages.
  - `[low]` `[reject]` (edge) Stall-to-pending claim breaks the still-fails guarantee — same as the first row.
  - `[low]` `[reject]` (intent) DW-84 culprit not identified — not reproducible (all ledger re-runs passed); audit, hardening, richer messages and repeat runs done as the intent asks; recorded as residual risk.
  - `[low]` `[reject]` (intent) Audit touched only three test_level tests — the other wall-clock uses are timeout budgets (3–12 s) on events that take far less, not timing assertions.
  - `[false]` `[reject]` (intent) No repeat-run evidence — implementer ran feedback/shake 15x and test_level 8x, orchestrator 5x more plus two full suites, all passing.
  - `[false]` `[reject]` (intent) Pending trigger broader than intended — duplicate of the first row's claim, graded there.
  - `[false]` `[reject]` (intent) DW-79 surface changed — the test still runs through `_process`; the intent offered both remedies.
  - `[false]` `[reject]` (intent) Changes beyond named items — the Maul test is part of the DW-84 audit; implementation-artifact specs are tracked in this repo.

## Design Notes

Godot emits `process_frame`/`physics_frame` before running that frame's timers/physics, so a poll sees state one frame late; tolerances are built from "deadline + gaps", never from a fixed wall-clock number.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: completes.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all pass.
- Same with `-gtest=res://tests/unit/test_feedback.gd` (and the other two files) in a loop -- expected: no failures.

## Auto Run Result

Status: done

**Summary:** Hardened three timing-sensitive GUT areas without touching production code. DW-74: hit-stop timing tests track the largest frame gap while waiting for the resume; a late resume after a >60 ms stall is now `pending` (with values), otherwise the 250 ms bound still fails. DW-79: `test_process_drives_shake` uses a 1000 s shake and a 60-frame budget so slow frames can't decay it to 0, and checks the offset is non-zero and inside the square. DW-84: Maul telegraph check now counts physics ticks (hit tick recorded in the HP handler) instead of wall time; the Lancer convoy aim tolerance is expressed in ticks with an accurate comment; both Lancer tests print measured values on failure.

**Files changed:**
- `game/tests/unit/test_feedback.gd` -- gap tracking in `_await_resume`, `_assert_resumed_promptly` stall-to-pending guard used by both hit-stop timing tests.
- `game/tests/unit/test_shake_camera.gd` -- deterministic `_process` shake test with diagnostic messages.
- `game/tests/unit/test_level.gd` -- tick-based Maul telegraph check, tick-scaled Lancer aim tolerance, richer failure messages.

**Review:** 23 findings; 3 low patched (Lancer comment and margin rationale, shake message diagnostics); 0 deferred; 20 rejected (reasons in the triage log). Patched by verdict: high 0, medium 0, low 3. Follow-up review recommended: false.

**Verification:** `--import` ok; full GUT suite 1619/1619 passing (before and after patches). Implementer: test_feedback.gd and test_shake_camera.gd 15x each, test_level.gd 8x, no failures (some runs show the pre-existing "second hit_stop came too late" pending). Orchestrator: 5 more runs each of test_feedback.gd and test_shake_camera.gd, all passing.

**Residual risks:** The original DW-84 failure was never captured, so it is unconfirmed that either hardened check was the culprit; review showed the Lancer aim check already polls every physics tick, so it was not wall-clock dependent. The new stall-to-pending path has not triggered in any run.
