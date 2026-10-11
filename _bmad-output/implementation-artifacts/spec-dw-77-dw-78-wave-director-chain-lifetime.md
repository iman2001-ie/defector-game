---
title: 'DW-77, DW-78: WaveDirector gap timer dies with the director; a death stops running chains'
type: 'bugfix'
created: '2026-10-10'
status: 'done'
baseline_revision: 529e52de64d34bfff53ef41eebb82255da560d83
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** (DW-77) `WaveDirector._try_clear` waits out the wave-clear gap on a `SceneTreeTimer` (wave_director.gd:562), which outlives the director, so a death reload during the gap resumes the coroutine on a freed instance (Godot logs "Resumed function ... after await, but class instance is gone"). (DW-78) After `Events.level_failed`, running action chains keep going (decision #39), so a chain whose `wait` ends during the death beat can still request comms, story events, music, hints or groups, e.g. open a story pause over the death.

**Approach:** DW-77: wait out the gap on the same pausable one-shot child `Timer` the `wait` action uses, so it is freed with the director. DW-78 (operator decision 2026-10-10, "Stop the whole chain after a fail"): once `_failed` is set, a running chain runs no further action of any kind (spawn_group included); `_failed` is checked after every await in `_run_chain` (and before each action). Amend decision #39 and the architecture notes that quote it.

## Boundaries & Constraints

**Always:** Statically typed GDScript, logging through `Log`. The gap stays pausable and keeps its `waves.gap_s` length from `Config`. A chain stopped by a failure still decrements `_running_chains` (emitting `chains_finished` at 0) so `running_chains()` reads 0, but never clears or stalls anything (those already return while `_failed`). A chain of an older wave (serial changed) still returns without touching the counters, exactly as today. Progress freeze rules from DW-54 are unchanged. A group spawn already requested (deferred) before the failure still spawns uncounted, as today: the decision covers the chain's own later actions.

**Never:** Don't change the intro/outro (they already stop on `_failed`), `_spawn_group`, counting, `start_level` / `debug_skip_to_boss` resets, or `CommsChannel` / `PauseArbiter`. Don't edit `deferred-work.md`, `sprint-status.yaml`, `.bmad-loop/` or level/tuning data. No new tuning values.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Reload during gap | 2 waves, wave 1 cleared, director freed (death reload) before `gap_s` ends | no "class instance is gone" error, no second `wave_started` | none |
| Gap timer shape | wave cleared, gap running | exactly one `PROCESS_MODE_PAUSABLE` `Timer` child; freed after the gap; next wave starts after `gap_s` | none |
| Gap <= 0 | `waves.gap_s` = 0 | next wave still starts on a later frame, never synchronously inside `_try_clear`; no Timer error | none |
| Death during wait | chain `[wait, music, comms, story_event, hint, spawn_group]`, `level_failed` during the wait | none of the later actions run; `running_chains()` 0 after the wait; one INFO `beat` line saying the chain stopped | none |
| Death while a story holds the chain | chain `[comms story_a, story_event e]`, `level_failed`, then `story_a` finishes | `e` not emitted; `running_chains()` 0 | none |
| Group requested before death | chain `[spawn_group r, wait, story_event e]` with a bogus entry in `r`, death right after start | `r` spawns uncounted (bogus not subtracted, no stall net); `e` not emitted | bogus type ERROR as today |
| Retry after stop | stopped chain, then `start_level` | new attempt's chains run normally | none |

</intent-contract>

## Code Map

- `game/systems/waves/wave_director.gd:551-572` -- `_try_clear`: line 562 is the `SceneTreeTimer` gap; replace with a child Timer from `_start_wait_timer` (generalize its doc at :518-527; it runs `wait_time` > 0 only, so floor the gap at a tiny technical minimum such as a `const MIN_TIMER_S: float = 0.001` documented as "fires on the next frame like the old zero-length timer"; not a design number). `queue_free` the timer after it fires, as `_run_chain` does at :471.
- `game/systems/waves/wave_director.gd:456-499` -- `_run_chain`: add the `_failed` stop. Wait branch :466-473 and comms loop :478-481 are the awaits; the comms `while` must also exit on `_failed` (otherwise it keeps waiting for the story). The end block :494-499 stays the single exit for a stopped chain.
- `game/systems/waves/wave_director.gd:1-48` -- class doc: lines 17-22 ("Running chains and pending group spawns still run") and 36-41 (await rule: "Every await ... is on this node's own signal or a child Timer") must describe the new rules, and line 14-15 the gap.
- `game/systems/waves/wave_director.gd:115-119` -- `_on_events_level_failed` sets `_failed` (first outcome wins); read-only.
- `game/tests/unit/test_wave_director.gd` -- helpers `_start`, `_start_chain`, `_load_dialogue` (:780, fixture story_a/combat_a), `_finish`, `_events_named`, `_lines_containing`, `_wait_real`, `_silent_wav`; `Audio.current_music()`. Rewrite `test_chains_and_groups_still_run_after_death_without_counting` (:608-630) to the "group requested before death" row. Models: `test_death_reload_drops_a_chain_in_a_wait` (:1052), `test_wait_uses_a_pausable_child_timer` (:1082), `test_gap_is_pausable` (:508). GUT 9.7 fails a test on engine errors and offers `assert_engine_error_count`; the freed-director error only shows if the test waits past the gap.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md:43` -- decision #39 row: replace "running chains and group spawns still run" with the new rule and add "amended 2026-10-10 (DW-78)" in the source/status columns.
- `_bmad-output/game-architecture.md` -- :808 (chain lifetime: gap Timer too), :811 (gap is a pausable child Timer), :813 and :1664 (the decision #39 quotes).

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_wave_director.gd` -- write failing tests first for every matrix row (red before green), rewrite the :608 test -- regression net.
- `game/systems/waves/wave_director.gd` -- child-Timer gap in `_try_clear`; `_failed` stop in `_run_chain`; class doc -- DW-77, DW-78.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- amend decision #39 -- operator decision record.
- `_bmad-output/game-architecture.md` -- update the four notes above -- keep the contract in sync.

**Acceptance Criteria:**
- Given the full GUT suite, when it runs headless, then every test passes with no new engine errors or warnings.
- Given `grep create_timer game/systems/waves/wave_director.gd`, when run, then nothing matches.
- Given decision #39 and the architecture notes, when read, then none says chains still run after `level_failed`, and each says a death stops running chains (a group requested earlier still spawns uncounted).

## Spec Change Log

## Review Triage Log

### 2026-10-10 — Review pass
- verdicts: 23 findings — high 0, medium 0, low 13, false 7, maybe-false 3
- findings:
  - `[low]` `[patch]` (blind) Stop log skipped when the death lands during the chain's last action — fixed: the loop top records the skipped count and breaks; one INFO `chain stopped` line is logged after the loop whenever `_failed` is set (0 skipped for a death during the last await).
  - `[low]` `[patch]` (blind) No test covers the last-action case — added `test_death_during_the_last_wait_logs_the_stop`; the story-held test now asserts one stop line.
  - `[low]` `[patch]` (blind) Architecture "As built (Story 5.3)" paragraph (~:842) and "Death mid-chain" edge case (~:880) omit DW-78/DW-77 — both now mention the failed-attempt stop and the child-Timer gap.
  - `[false]` `[reject]` (blind) Deferred-work ledger not updated — the intent forbids editing the ledger; the orchestrator records resolution.
  - `[false]` `[reject]` (blind) Spec missing from the reviewed patch — excluded on purpose (claims file goes to the edge-case layer only); it is committed with the change.
  - `[maybe-false]` `[reject]` (blind) Reload-during-gap test may not fail on the old code — the engine never emitted "class instance is gone" in this setup (DW-77 was "not reproduced"), so the test is a regression guard only; settling it needs an engine build that reports the resume error. If true it is low (the fix itself removes the SceneTreeTimer), so rejected with this note.
  - `[low]` `[reject]` (blind) Comms already requested in the same frame as the death still reach the channel — pre-existing, needs a frame-exact coincidence (story sequences pause the tree, so the player cannot die during one), and the fix would add guards in CommsChannel/PauseArbiter outside this change.
  - `[low]` `[reject]` (blind) Negative `waves.gap_s` silently clamped to 1 ms — pre-existing (the old timer accepted it too), tuning is a single shipped value of 2.0; fix would add a new validation rule.
  - `[low]` `[reject]` (blind) F6 path not covered for chains — debug-only; F6 resets `_failed` before `start_wave`, the same reset `start_level` uses, which the retry test covers; extra test not worth it.
  - `[maybe-false]` `[reject]` (blind) New tests depend on wall-clock margins — they follow the file's existing 2x-margin pattern and passed in two full runs; would only be low if flaky.
  - `[low]` `[patch]` (edge) Stop line not logged when the failure lands in the last await — same root as the first row; same fix.
  - `[false]` `[reject]` (edge) `_try_clear` while the director is detached never starts the next wave — unreachable: resolves and clears only happen with the director in the tree, and the old code called `get_tree()` there (null outside the tree), so this is no regression.
  - `[low]` `[patch]` (edge) Claim "logs one INFO beat line" untrue for last-action stops — same root; now true.
  - `[low]` `[patch]` (edge) Claim "`_failed` checked after every await" not literal for the wait branch — same root; behaviour already stopped the chain, and the post-loop check now logs it.
  - `[low]` `[patch]` (edge) Rewritten group test dropped `_kill(1)`, making `resolved_count() == 0` vacuous — re-added the kill of the group's wasp.
  - `[low]` `[patch]` (verification-gap) A failed story-held chain woken by another sequence's finished is untested (removing the comms-loop `break` passes every test) — added `test_failed_story_chain_stops_on_another_finished`.
  - `[low]` `[patch]` (verification-gap, other) Stop line missing when the failure lands in the last await — same root as the first row; same fix.
  - `[false]` `[reject]` (intent) Pending group spawn surviving the death is an unstated rule — the operator decision scopes "running chains"; a group already requested is not an action of a running chain and its deferred spawn lands in the same frame; documented as-is, not a new behaviour.
  - `[low]` `[patch]` (intent) No stop line and no test for a death during a final `wait` — same root as the first row; fixed and covered by `test_death_during_the_last_wait_logs_the_stop`.
  - `[maybe-false]` `[reject]` (intent) DW-77 test doesn't isolate the timer swap / last-wave gap→outro untested — the outro path uses the same gap code; same evidence limit as the blind-hunter row; if true low.
  - `[false]` `[reject]` (intent) DW-78 tests check the director, not PauseArbiter — the director's `comms_sequence_requested` is the only route to that story pause; no request means no pause.
  - `[false]` `[reject]` (intent) `MIN_TIMER_S` is an extra change — required because a Timer cannot run 0 s; documented as technical, not a design number.
  - `[false]` `[reject]` (intent) The spec planned the pending-group rule — informational, no defect.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` then `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` (real path in `LOCAL.md`) -- expected: all tests pass, 0 failures.

## Auto Run Result

Status: done

**Summary:** DW-77: `WaveDirector._try_clear` now waits out the wave-clear gap on a pausable one-shot child `Timer` (`_start_wait_timer`, floored at `MIN_TIMER_S` = 0.001 s because a Timer can't run 0 s), so it is freed with the director on a death reload. DW-78 (operator decision 2026-10-10): once `Events.level_failed` fires, a running chain runs no further action of any kind; `_failed` is checked before each action and the story-comms wait exits on it; a stopped chain logs one INFO `beat` line and still leaves the chain count. A group requested before the death still spawns, uncounted. Decision #39 and the architecture notes are amended.

**Files changed:**
- `game/systems/waves/wave_director.gd` -- child-Timer gap, `_failed` chain stop, class doc.
- `game/tests/unit/test_wave_director.gd` -- 9 new tests (gap timer shape, zero gap, reload during the gap, death during a wait / last wait, story-held chain stops on its own or another finished, retry after a stop) and the rewritten group-before-death test.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- decision #39 amended (DW-78).
- `_bmad-output/game-architecture.md` -- chain lifetime, gap, decision #39 quotes, as-built and edge-case notes.

**Review:** 23 findings; 10 low rows patched (4 entries: stop-log placement, story-wake test gap, vacuous group-kill check, stale architecture notes), 0 deferred, 13 rejected (reasons in the triage log). Patched by verdict: high 0, medium 0, low 4 entries. Follow-up review recommended: false.

**Verification:** headless `--import` then the full GUT suite: 85 scripts, 1610/1610 passing (after patches; 1608/1608 before). Every I/O matrix row has a passing test.

**Residual risks:** the reload-during-gap test never failed on the old code — Godot 4.7 didn't emit the "class instance is gone" error in this setup — so it guards regressions but didn't reproduce DW-77. The new timing-based tests use the file's existing 2x wall-clock margins.
