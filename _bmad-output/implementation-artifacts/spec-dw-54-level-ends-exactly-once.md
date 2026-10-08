---
title: 'DW-54: a level ends exactly once (first outcome wins; a clear makes the ship safe)'
type: 'bugfix'
created: '2026-10-08'
status: 'done'
baseline_revision: 'b90bae85ace2506f8def79b6c7cc1b166c0e0330'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
warnings: []
deferred:
  - summary: >-
      "First outcome wins" is enforced at the only current emitter (Player); RetryPrompt still reacts to any level_failed, so a future emitter (convoy, Epic 6) must not fail a cleared level.
    evidence: |-
      ui/menus/retry_prompt.gd opens on the first Events.level_failed with no level_cleared check; events.gd documents a &"convoy" reason with no emitter yet. Today Player is the only emitter and is gated by _safe, so nothing is reachable now.
    location: >-
      game/ui/menus/retry_prompt.gd:125
    severity: low
---

<intent-contract>

## Intent

**Problem:** Epic 3 retro F1 / DW-54. After `Events.level_failed` the WaveDirector already never emits `wave_cleared` / `level_cleared`, but kills still count: `_on_enemy_resolved` resolves progress, emits `wave_progress_changed` and fires progress triggers, so in-flight missiles keep scoring a dead attempt. After `Events.level_cleared` nothing protects the ship: a lethal hit still emits `player_died` + `level_failed` (opening the retry prompt on a cleared level).

**Approach:** Human decision (2026-10-08, option 1): first outcome wins and a clear makes the ship safe. WaveDirector freezes progress once failed (no resolve, no subtraction, no `wave_progress_changed`, no progress triggers, no stall net, F3 refuses). Player listens to `Events.level_cleared` and from then on ignores damage and hazard contact, so it can never die or emit `level_failed`. Record decision-log row #39 and add tests combining a death and a clear in both orders.

## Boundaries & Constraints

**Always:** Statically typed GDScript; logging through `Log`. The safe flag is set only by `Events.level_cleared` and never reset (retry/next level reload the scene, ADR-004). After the clear, energy orbs are still collected on contact; the ship stays visible, alive and able to fire. `start_level` / `debug_skip_to_boss` keep resetting `_failed` (a fresh attempt counts again). Update `game-architecture.md` lines ~801, ~1539 and ~1617 to state the new rules. Decision-log row #39 cites DW-54 and the user decision.

**Never:** Don't touch `deferred-work.md` or `sprint-status.yaml`. Don't change `Events` signal signatures, RetryPrompt, SceneRouter, level.gd or any `.tscn`. Don't stop chains or group spawns of a dead attempt (only counting stops). Don't route the safe state through `is_invulnerable()` (contact must not destroy small/medium enemies after the clear).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Kill after death | `level_failed` emitted, then a counted enemy dies | `resolved_count()` unchanged; no `wave_progress_changed`; no progress trigger fires; no `wave_cleared`/`level_cleared` | No error |
| Death then clear (integrated) | Player + WaveDirector; lethal hit, then the last enemy dies, wait past the gap | `level_failed` once, `level_cleared` never, `is_level_cleared()` false | No error |
| Clear then death (integrated) | Last enemy dies, gap passes (`level_cleared`), then a lethal `apply_damage` | Player alive, hearts unchanged, no `player_hit`/`player_died`/`level_failed`; `level_cleared` once | No error |
| Contact after clear | Wasp / asteroid contact after `level_cleared` | No heart cost, wasp not destroyed, nothing remembered | No error |
| Orb after clear | EnergyOrb contact after `level_cleared` | Collected as before | No error |
| F3 after death | `debug_resolve_wave()` after `level_failed` | INFO `F3: attempt failed; nothing to resolve`, progress unchanged | No error |
| Fresh attempt | `start_level` after a failure | Kills count and clear again (existing test) | No error |

</intent-contract>

## Code Map

- `game/systems/waves/wave_director.gd` -- `_failed` (L73) set in `_on_events_level_failed` (L89), reset in `start_level` (L103) and `debug_skip_to_boss` (L219). Gate: `_on_enemy_resolved` (L356, after the serial check), `_subtract` (L364), `_check_stall` (L417), `debug_resolve_wave` (L178). `_try_clear` / `_finish_level` already gated. Header doc L17-18.
- `game/entities/player/player.gd` -- `_ready` (L117) connect `Events.level_cleared`; `apply_damage` (L194) and `on_contact` (L313, after the orb branch) return when safe; `_recheck_contacts` (L363) clears contacts when safe. Add public `is_level_cleared_safe()` style query (name: `is_safe()`). Header doc L36-42.
- `game/tests/unit/test_wave_director.gd` -- fixture with `_start`, `_kill`, `_events_named`, recorders (L16-50); existing dead-attempt tests L506-540 to extend next to.
- `game/tests/fixtures/player_test_base.gd` -- `_begin`, `_make_player`, hazard factories for Player tests.
- `game/tests/unit/test_player_death.gd` -- pattern for Player death assertions.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- append row #39.
- `_bmad-output/game-architecture.md` -- L801, L1539, L1617.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_wave_director.gd` -- add failing tests: kill after death freezes progress (no `wave_progress_changed`, `resolved_count` unchanged, progress-triggered group not requested), F3 after death refuses, `level_failed` after `level_cleared` leaves `is_level_cleared()` true and `level_cleared` once.
- `game/tests/unit/test_player_level_clear.gd` (new, extends player_test_base) -- after `Events.level_cleared`: lethal damage ignored (no events), wasp/asteroid contact costs nothing and wasp survives, orb still collected, `is_safe()` true; before it false.
- `game/tests/unit/test_level_outcome.gd` (new) -- WaveDirector fixture (as in test_wave_director) plus a real Player scene: death-then-clear and clear-then-death per the matrix.
- `game/systems/waves/wave_director.gd` -- implement the gates; update header doc.
- `game/entities/player/player.gd` -- implement the safe state; update header doc.
- `decision-log.md` -- row #39; `game-architecture.md` -- the three lines.

**Acceptance Criteria:**
- Given the full GUT suite, when it runs headless, then all tests pass with no new orphan or error output.
- Given the decision log, when read, then row #39 records "first outcome wins; a clear makes the ship safe" (DW-54, user, 2026-10-08).

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all pass

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 23 findings — high 0, medium 5, low 12, false 6, maybe-false 0
- findings:
  - `[medium]` `[patch]` (blind) `_check_stall` `_failed` gate never exercised by a test — added `test_chains_and_groups_still_run_after_death_without_counting` (chain ends after death with nothing live, so the stall net would fire without the gate).
  - `[medium]` `[patch]` (blind) "chains and group spawns still run" and the `_subtract` after-death path untested — same new test: the group's wasp spawns, the bogus entry is not subtracted, total stays 4.
  - `[low]` `[patch]` (blind) F6 contradicts "a level ends exactly once" and the docs don't say so — added a debug-only exception sentence to decision-log row #39 and the architecture WaveDirector bullet.
  - `[low]` `[defer]` (blind) RetryPrompt still reacts to any `level_failed`; a future convoy emitter could fail a cleared level — pre-existing listener; the only emitter today is gated; recorded in `deferred`.
  - `[low]` `[reject]` (blind) DW-54 text added inside architecture sections headed "no design decision changed" — each added sentence opens with "Since DW-54 (decision #39)", so the source is explicit; restructuring the doc is beyond a direct correction.
  - `[low]` `[reject]` (blind) orb test hard-codes energy 10 — matches the existing test convention (`test_player_pickup.gd:26,40,65`); the no-hard-coding rule is for game code and data.
  - `[low]` `[reject]` (blind) integration tests skip progress-freeze, contact and bullet paths — progress freeze and contact are covered in unit tests; bullets reach the Player through `apply_damage` (`core/projectile.gd:54`), which is gated.
  - `[low]` `[reject]` (blind) ACs don't restate the matrix as Given/When/Then — the fix edits this build's spec.
  - `[low]` `[reject]` (blind) no level.gd / RetryPrompt end-to-end test — those files are unchanged and the only emitter is gated; a full-scene test is more than a direct fix.
  - `[medium]` `[patch]` (edge) `_try_clear`: a death while awaiting `chains_finished` after the gap still started the next wave — the loop now returns on `serial != _serial or _failed`; added `test_death_while_waiting_for_chains_never_starts_the_next_wave`.
  - `[low]` `[patch]` (edge) F6 after a clear leaves the Player safe through the boss wave — debug-only; documented as the F6 exception (row #39, architecture).
  - `[false]` `[reject]` (edge) `start_level` again in the same scene leaves the Player safe — level.gd calls `start_level` once per scene load; retry and next level reload the scene (SceneRouter).
  - `[medium]` `[patch]` (edge) claim "no wave clears / progress frozen" contradicted by the post-gap loop — same root cause and fix as the `_try_clear` row.
  - `[low]` `[patch]` (edge) claim "safe never reset" vs F6 restarting a wave — same F6 doc exception.
  - `[medium]` `[patch]` (verification-gap) after-death `_check_stall` / `_subtract` gates unpinned — same new test as the first two rows.
  - `[false]` `[reject]` (verification-gap) `_level_done` guard in `_on_events_level_failed` has no observable effect — defensive only, no bad outcome.
  - `[false]` `[reject]` (verification-gap) `_safe` term in `_recheck_contacts` has no observable effect — defensive only, no bad outcome.
  - `[false]` `[reject]` (intent) in-flight missiles path not exercised — the gate is on `Enemy.resolved`, which every kill source goes through.
  - `[low]` `[defer]` (intent) one-outcome rule not enforced level-wide (RetryPrompt) — grouped with the RetryPrompt defer row.
  - `[low]` `[reject]` (intent) projectiles after the clear untested — same as the blind integration row.
  - `[false]` `[reject]` (intent) freezing subtraction, stall net and F3 goes beyond the text — it is what "stops counting kill progress" means for this director; recorded in decision #39.
  - `[false]` `[reject]` (intent) orbs still collected, ship still fires, not via `is_invulnerable()` — these keep existing behaviour and are documented; no harm.
  - `[low]` `[reject]` (intent) level scene surface not exercised — same as the blind end-to-end row.


### 2026-10-08 — Review pass
- verdicts: 20 findings — high 0, medium 0, low 14, false 6, maybe-false 0
- findings:
  - `[false]` `[reject]` (blind) a death during the outro makes both outcomes fire, because `_level_done` is set before `level_cleared` — `_finish_level` sets `_level_done` and emits `level_cleared` in the same synchronous call; the outro is only a log line, and there is no `await` between the two, so the window doesn't exist.
  - `[low]` `[defer]` (blind) RetryPrompt still reacts to any `level_failed` (convoy) after the clear — carried: same as the logged RetryPrompt / future-convoy-emitter defer row; `retry_prompt.gd` is unchanged and already in `deferred`.
  - `[low]` `[patch]` (blind) the architecture says a `level_failed` after `level_cleared` "changes nothing", but RetryPrompt still reacts — reworded `game-architecture.md` L801 to "changes nothing in the WaveDirector".
  - `[low]` `[reject]` (blind) after a death, F6 can clear the level and save progress from a dead attempt — this F6 reset of `_failed` existed before this change, and it is debug-only; refusing it in the router would add guards for a key that never ships to players.
  - `[false]` `[reject]` (blind) `test_death_then_clear_never_clears` passes because of the freeze, not the clear guards — the test follows the matrix row exactly (lethal hit, then the last kill, then wait past the gap); `test_death_while_waiting_for_chains_never_starts_the_next_wave` and the existing gap test cover a death after the wave resolved.
  - `[false]` `[reject]` (blind) no test for a failure between `_level_done = true` and the `level_cleared` emit — no such window exists (see the outro row).
  - `[low]` `[reject]` (blind) no test that counting resumes after F6 reopens a failed attempt — debug-only path; the player-facing fresh attempt (`start_level`) is covered by an existing test; adding an F6 test isn't worth it.
  - `[low]` `[reject]` (blind) the orb test hard-codes energy 10 — carried: same as the logged row (matches the `test_player_pickup.gd` convention).
  - `[low]` `[reject]` (blind) contact is driven through `on_contact` directly, and tests read the private `_contacts` — matches the existing player-test fixture (`player_test_base.gd`, physics off); rewriting it for real `area_entered` overlap goes beyond a direct fix.
  - `[low]` `[reject]` (blind) projectiles hitting a safe Player aren't covered — carried: same as the logged bullet-path row (`core/projectile.gd:54` goes through the gated `apply_damage`).
  - `[false]` `[reject]` (blind) `test_level_outcome.gd` overlaps the unit tests — the spec asks for that integrated file on purpose (real Player plus WaveDirector), and no harm is named.
  - `[low]` `[defer]` (edge) RetryPrompt opens on a convoy or non-player `level_failed` after the clear — carried: same RetryPrompt defer row.
  - `[low]` `[reject]` (edge) the orb test hard-codes 10 instead of `Config.int_("energy.orb_value")` — carried: same as the logged row.
  - `[false]` `[reject]` (verification-gap) the `_level_done` guard in `_on_events_level_failed` has no observable effect — carried: same as the logged row (defensive only).
  - `[low]` `[reject]` (intent) the visible symptom (RetryPrompt over a cleared level / `level.tscn`) isn't exercised — carried: same as the logged level-scene row.
  - `[low]` `[defer]` (intent) "first outcome wins" holds for Player deaths only, not scene-wide — carried: same RetryPrompt defer row.
  - `[low]` `[reject]` (intent) contact is tested by calling the method, not through physics — grouped with the blind `on_contact` row; same reason.
  - `[low]` `[reject]` (intent) "able to fire" after the clear isn't asserted — the diff doesn't touch the firing code (`_safe` gates only `apply_damage`, `on_contact` and the contact re-check), so the existing firing tests still apply.
  - `[false]` `[reject]` (intent) the ship is still vulnerable during the gap before `level_cleared` — the intent sets the safe flag only on `Events.level_cleared`, and a death in the gap is a valid first outcome.
  - `[low]` `[patch]` (intent) decision-log row #39 is credited to the user, but its F6 note came from the review — the Source column now reads "User (Epic 3 retro F1, DW-54); F6 note added from the implementation review".

## Auto Run Result

Status: done (follow-up review pass)

**Summary:** This pass was a follow-up review of the DW-54 change (decision #39: first outcome wins, and a clear makes the ship safe). No code defects were found. Two doc-wording patches were applied.

**Files changed in this pass:**
- `_bmad-output/game-architecture.md` -- L801 now says a late `level_failed` changes nothing *in the WaveDirector*.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- row #39 Source column now notes the F6 note came from the implementation review.

**Files in the reviewed change (already committed in aea77f6):** `game/systems/waves/wave_director.gd`, `game/entities/player/player.gd`, `game/tests/unit/test_wave_director.gd`, `game/tests/unit/test_player_level_clear.gd` (+ `.uid`), `game/tests/unit/test_level_outcome.gd` (+ `.uid`), decision-log row #39, `game-architecture.md`.

**Review:**
- 20 findings: 0 high, 0 medium, 14 low, 6 false.
- Patched: 2 low (both doc wording).
- Deferred: the RetryPrompt / future emitter item (3 rows, carried). It is already in `deferred`, so nothing new was added.
- Rejected, each with its reason in the triage log:
  - 6 false: the outro window, the death-then-clear test, the outro-window test, the test overlap, the `_level_done` guard, the gap window.
  - 9 low: F6 saving from a dead attempt, an F6 counting-resume test, the orb ×2, the `on_contact`/private `_contacts` style ×2, projectiles, the level-scene surface, the "able to fire" assertion.

**Follow-up review:** not recommended (`false`). This was a follow-up pass, and no `high` finding was patched (patched by verdict: high 0, medium 0, low 2).

**Verification:**
- `--import` exits 0.
- Full GUT suite: 71 scripts, 1067 tests, 1066 passing and 1 pending. The pending test is `test_feedback.gd::test_hit_stop_overlap_keeps_longest`, the known slow-frame timing guard, unrelated to this change.

**Residual risks:**
- RetryPrompt still trusts every `level_failed` emitter (deferred).
- F6 is a debug-only exception to "first outcome wins".
- The doc patches change wording only.
- Feel isn't verified.
- `deferred-work.md` has the orchestrator's uncommitted ledger update; it was left untouched and uncommitted as instructed.
