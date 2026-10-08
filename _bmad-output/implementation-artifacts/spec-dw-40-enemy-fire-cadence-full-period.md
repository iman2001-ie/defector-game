---
title: 'DW-40: Lancer and Bastion fire on a full period that includes the telegraph'
type: 'bugfix'
created: '2026-10-08'
status: 'done'
baseline_revision: 'e955ce81ed1836e058330c382ccc0bcbeb67073e'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
warnings: []
deferred:
  - summary: >-
      Decision #38 covers only Lancer and Bastion; the boss timers (boss.turrets fire_interval_s/telegraph_s, desperate aimed/radial interval plus glow) still have unstated cadence semantics, and the Wasp dive clock stays clock-then-telegraph.
    evidence: |-
      tuning.json boss.turrets pairs fire_interval_s 3.0 with telegraph_s 0.5, and GDD FR51 says "every 1.5 s after a 0.4 s glow". The boss isn't built yet (Epic 7), so the DW-40 question will come back unless #38 is extended or the boss story states its semantics. Pre-existing ambiguity; the intent scopes DW-40 to Lancer and Bastion.
    location: >-
      game/data/tuning.json (boss.turrets, boss.desperate)
    severity: low
  - summary: >-
      The Story 2.5 AC in epics.md ("Given a Lancer's fire timer reaches 2.0 s ... glows for 0.3 s, then it fires") now describes the old timer literally; as built the timer is 1.7 s and the shot lands at 2.0 s.
    evidence: |-
      epics.md:785-787. FR20 ("every 2.0 s") and decision #38 match the new behaviour, and the architecture note explains it. The DW-40 decision lists only tests, the architecture notes and a decision-log row as the docs to update, and AGENTS.md says to ask the user before changing planning docs, so amending a done story's AC (as #34/#35 did) is left for the user to decide.
    location: >-
      _bmad-output/planning-artifacts/epics.md:785
    severity: low
---

<intent-contract>

## Intent

**Problem:** The GDD says a Lancer fires "every 2.0 s" and a Bastion "every 2.5 s", but as built both wait the full `fire_interval_s` and then the telegraph, so the real shot period is 2.3 s and 3.0 s. The Needle already uses start-to-start semantics. The user decided on 2026-10-07 (DW-40) that the interval includes the telegraph.

**Approach:** The Lancer's STRAFE timer and the Bastion's DRIFT timer run `max(fire_interval_s - telegraph_s, 0)` instead of `fire_interval_s`. The telegraph is unchanged, so the time from one shot to the next equals `fire_interval_s`. Update the cadence tests, the as-built notes in `game-architecture.md`, and add a decision-log row.

## Boundaries & Constraints

**Always:** Read both values from Config (`enemies.lancer.*` and `enemies.bastion.*`), compute the strafe/drift time once in `_ready`, and hard-code no numbers. Keep the state enums, `_enter_state()` as the only writer of `_state`, the telegraph length, the visuals and the never-fire-while-entering rule. Clamp the strafe/drift time at 0. Write the failing tests first.

**Never:** Change `tuning.json` values, the Needle, the Wasp, the GDD or `epics.md` (Story 2.5 and 2.7 are done history). Don't edit the deferred-work ledger. No per-frame allocations.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Lancer default | interval 2.0, telegraph 0.3 | STRAFE 1.7 s, TELEGRAPH 0.3 s, shots 2.0 s apart; first shot 2.0 s after STRAFE begins | No error expected |
| Bastion default | interval 2.5, telegraph 0.5 | DRIFT 2.0 s, TELEGRAPH 0.5 s, volleys 2.5 s apart | No error expected |
| Telegraph >= interval | e.g. interval 0.2, telegraph 0.5 | Strafe/drift time clamps to 0: leaves STRAFE/DRIFT on the next tick, period ≈ telegraph_s | No error, no warning |

</intent-contract>

## Code Map

- `game/entities/enemies/lancer/lancer.gd` -- `_ready` reads `fire_interval_s` / `telegraph_s` (l.51-52); `step()` STRAFE check `_t >= _fire_interval_s` (l.91). The class doc (l.8-11) describes the old cadence.
- `game/entities/enemies/bastion/bastion.gd` -- the same shape: `_ready` l.55-56, DRIFT check l.99, class doc l.8-12.
- `game/entities/enemies/needle/needle.gd:73` -- reference pattern: `_cooldown_s = maxf(fire_interval_s - _track_s - _lock_s, 0.0)`.
- `game/tests/unit/test_lancer.gd` -- the 2.0 s STRAFE assertions in `test_fire_cycle_through_a_real_spawner` (l.256), `test_no_fire_while_entering` (l.371), `test_numbers_come_from_tuning` (l.413, interval 1.0 / telegraph 0.5 → 0.5 s); `test_cycle_repeats_every_interval_plus_telegraph` (l.346) assumes a 2.3 s period. `_step_until` helper l.93.
- `game/tests/unit/test_bastion.gd` -- 2.5 s DRIFT assertions in the spawner test (l.289), `test_no_fire_while_entering` (l.384), `test_cycle_repeats_every_interval_plus_telegraph` (l.352, 3.0 s period, and the post-volley 2.5 s), `test_numbers_come_from_tuning` (l.478, 1.0 / 0.4 → 0.6 s).
- `game/tests/data/test_data_files.gd` -- `test_lancer_tuning_ranges` (l.230), `test_bastion_tuning_ranges` (l.265); the Needle has `track_s + lock_s <= fire_interval_s` (l.253) as the model.
- `_bmad-output/game-architecture.md` -- the Lancer as-built bullet (l.1479, "gives a 2.3 s shot period") and the Bastion cadence bullet (l.1502, "3.0 s period").
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- last row is #37; add #38.
- `game/data/tuning.json` -- read only: lancer 2.0 / 0.3, bastion 2.5 / 0.5.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_lancer.gd` -- first: assert STRAFE→TELEGRAPH takes `fire_interval_s - telegraph_s` (1.7 s default, 0.5 s in the tuning test), rename the repeat test to a full-period test (3 shots by ~6.5 s, shots 2.0 s apart measured shot to shot), and add a telegraph >= interval clamp test -- red phase.
- `game/tests/unit/test_bastion.gd` -- the same for the Bastion: 2.0 s DRIFT, volleys 2.5 s apart (18 bullets by ~7.0 s, none extra), tuning test 0.6 s, clamp test -- red phase.
- `game/tests/data/test_data_files.gd` -- add `telegraph_s <= fire_interval_s` to the lancer and bastion range tests, so data never relies on the clamp silently.
- `game/entities/enemies/lancer/lancer.gd` -- replace `_fire_interval_s` with a strafe time computed once as `maxf(fire_interval - telegraph, 0.0)`; update the class doc.
- `game/entities/enemies/bastion/bastion.gd` -- the same with a drift time; update the class doc.
- `_bmad-output/game-architecture.md` -- update both as-built bullets to the full-period semantics (2.0 s / 2.5 s, matching the Needle), citing DW-40 and decision #38.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- add row #38 (2026-10-08, the DW-40 decision, User, applied).

**Acceptance Criteria:**
- Given default tuning, when a Lancer strafes with a spawner, then consecutive bullets spawn `fire_interval_s` (2.0 s) apart and the muzzle glows for the last `telegraph_s` of each period.
- Given default tuning, when a Bastion drifts with a spawner, then consecutive volleys spawn `fire_interval_s` (2.5 s) apart with the turret glow for the last `telegraph_s`.
- Given the full GUT suite, when it runs headless, then every test passes.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 20 findings — high 0, medium 0, low 14, false 6, maybe-false 0
- findings:
  - `low` `reject` Resetting `_t = 0` on each transition drops the overshoot, so a period runs up to ~2 frames over `fire_interval_s` (blind) — a constant ≤ 33 ms per cycle, not cumulative drift; the same shared pattern as the Needle and Wasp. Players won't notice it, and carrying the remainder over would change a pattern all enemies share.
  - `low` `reject` The period tests (DT*2.5, 3 cycles) can't catch the frame-level overshoot (blind) — follows from the row above; the tolerance matches the existing tests and fixed-step behaviour.
  - `low` `reject` The data test allows `telegraph_s == fire_interval_s`, which gives a near-continuous glow (blind) — the DW-40 decision explicitly allows clamping at 0; tightening it to `<` is a design call it doesn't make, and the shipped data is 0.3/2.0 and 0.5/2.5.
  - `low` `reject` The clamp case logs no WARN, and its period is telegraph_s + DT (blind) — the spec chose no warning, the shipped data can't reach the case (the data test forbids it), and the clamp tests' tolerance covers the extra tick. A WARN would add a branch for an unlikely tuning.
  - `low` `defer` The cadence rule is still split: the boss timers' semantics are unstated and the Wasp is clock-then-telegraph (blind) — a pre-existing ambiguity outside DW-40's Lancer/Bastion scope; recorded in `deferred`.
  - `low` `reject` There is no note on the difficulty impact (+15%/+20% fire rate) (blind) — the user made the decision knowing the periods; tuning stays provisional per decision #11 and fun/feel is a human playtest call.
  - `false` `reject` sprint-status retro item 18 is still open (blind) — the orchestrator owns the sprint board and ledger and records resolution; the intent forbids this run closing them.
  - `false` `reject` Needle alignment isn't shown (blind) — the Needle already runs start-to-start (`needle.gd:73`), and `test_needle.gd` covers its cycle; nothing needed to change.
  - `low` `patch` The Bastion architecture bullet started a sentence with a dangling "So" and left out the first-volley time that the Lancer bullet gives (blind) — fixed: it now reads "The volley period is therefore start-to-start … the first 2.5 s after DRIFT begins".
  - `false` `reject` The clamp tests are inconsistent (inline tuning edit vs helper), with no glow or equality check (blind) — `test_lancer.gd` has no tuning helper and edits the dict inline throughout (e.g. the strafe-bound tests), and the matrix doesn't specify the glow pattern in the clamped state.
  - `low` `reject` The spec's Code Map line numbers are stale after the diff (blind) — the fix edits this build's spec, which is rejected by rule.
  - `low` `defer` The boss.turrets cadence semantics are unspecified (edge) — the same root cause as the deferred boss/Wasp row.
  - `low` `reject` The data test allows equality, so the period becomes fire_interval_s + DT (edge) — the same as the blind equality row; the clamp is allowed by the decision.
  - `low` `reject` The clamped period is telegraph_s + one frame (edge) — the matrix says "≈ telegraph_s"; one frame on an unreachable tuning doesn't matter.
  - `low` `reject` Overshoot from the `_t = 0` reset (edge, low confidence) — the same as the blind overshoot row.
  - `low` `defer` The Story 2.5 AC in epics.md describes the old timer literally (intent auditor) — a real but minor doc staleness; changing planning docs needs the user (AGENTS.md §4) and the DW-40 decision lists the docs to update. Recorded in `deferred`.
  - `false` `reject` The Needle wasn't changed despite "align … Needle" (intent auditor) — the decision says to match the Needle's existing semantics; it was already aligned.
  - `false` `reject` The extra `telegraph_s <= fire_interval_s` data constraint goes beyond the intent (intent auditor) — it isn't silent: it is recorded in row #38 and follows the Needle's `track_s + lock_s <= fire_interval_s` pattern.
  - `false` `reject` The spec file is a tracked deliverable, which matters for an artifact-only claim (intent auditor) — no artifact-only receipt is asserted, because code changed.
  - `low` `reject` No wave-level or playtest test of the cadence (intent auditor) — the unit tests drive the real enemy with a real Spawner, which is the outermost automated surface for cadence; feel is a human check.

### 2026-10-08 — Review pass (follow-up)
- verdicts: 17 findings — high 0, medium 0, low 9, false 8, maybe-false 0
- findings:
  - `low` `patch` The Story 2.5 and 2.7 as-built sections in game-architecture.md still open "Status update only; no design decision changed" while their bullets now record decision #38 (blind) — fixed: both heading lines now add "Amended 2026-10-08: … follows decision #38 (DW-40)".
  - `low` `reject` The DW-69 and DW-70 ledger titles are cut off mid-sentence (blind) — the titles are the orchestrator's bookkeeping in deferred-work.md, and the intent forbids this run editing the ledger. The full text is in this spec's `deferred` frontmatter.
  - `false` `reject` The spec says `in-review` while the ledger says DW-40 is done (blind) — `in-review` is this follow-up pass in progress; finalization sets `status: done`.
  - `low` `reject` Decision #38 doesn't say it excludes the Wasp and boss timers (blind) — the row is titled "Lancer and Bastion fire cadence", so its scope is stated. The open boss/Wasp question is already deferred (DW-69), and adding exclusion text would pre-empt that user decision.
  - `low` `reject` The `telegraph_s == fire_interval_s` boundary that the data test allows has no test (blind) — carried: same claim as the previous pass's equality rows (the decision allows the clamp, shipped data is 0.3/2.0 and 0.5/2.5).
  - `false` `reject` The clamp tests are too loose to catch a wrong period (`>= 3` shots, only the first gap checked) (blind) — the first-gap assertion `0.5 ± DT*2.5` fails for any wrong constant period, and the fixed-step state machine has no way to make later gaps differ from the first.
  - `low` `reject` The docs give exact 2.0 s / 2.5 s periods, but each runs up to ~2 ticks long (blind) — carried: same root cause as the previous pass's `_t = 0` overshoot rows. It is a ≤ 33 ms constant, shared with the Needle and Wasp.
  - `low` `reject` The +15–20% fire rate has no balance follow-up (blind) — carried: same claim as the previous pass's difficulty-impact row. Tuning stays provisional (decision #11), and feel is judged by a human playtest.
  - `low` `reject` Story 2.7's spec text ("After every 2.5 s of drifting…") describes the old timer (blind) — the intent treats Stories 2.5 and 2.7 as done history. A done story spec records what was asked at the time, and the planning-doc staleness is tracked in DW-70.
  - `low` `reject` The data test allows equality; the strafe/drift time becomes exactly 0 (edge) — carried: same as the previous pass's equality rows.
  - `low` `reject` The clamp tests cover only telegraph > interval, not == (edge) — carried: same root cause as the equality rows. The `>` case runs the same `maxf` branch as `==`.
  - `false` `reject` The spec task says "18 bullets by ~7.0 s", but the volleys land at 2.5, 5.0 and 7.5 s (edge, claim) — the fix would edit this build's spec, which is rejected by rule. The previous Auto Run Result already flagged the arithmetic slip, and the test correctly checks at 8.0 s.
  - `false` `reject` The diff edits the deferred-work ledger, though the spec says Never (edge, claim) — the ledger changes (DW-40 closed, DW-69/70 appended) are the orchestrator's bookkeeping, made after commit cc65f7d. This run doesn't edit them; it only commits them unchanged, as the follow-up pass in e955ce8 did.
  - `low` `reject` Cadence is tested only at the unit surface, and a slotted enemy's first shot after entry isn't asserted (intent auditor) — carried: same claim as the previous pass's wave-level row. `test_no_fire_while_entering` checks the 1.7 s / 2.0 s STRAFE/DRIFT after entry, and the telegraph is unchanged.
  - `false` `reject` The `telegraph_s <= fire_interval_s` data constraint goes beyond strict scope (intent auditor) — carried: it is disclosed in row #38 and follows the Needle's pattern.
  - `false` `reject` The ledger edits breach the "Never" fence (intent auditor) — same refutation as the edge-hunter row: orchestrator bookkeeping, not this build's work.
  - `false` `reject` The diff adds a spec artifact that the intent didn't ask for (intent auditor) — carried: the auditor itself notes the intent doesn't forbid it, and the spec is the workflow's record.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failures

## Auto Run Result

Status: done

**Summary:** Applied the DW-40 decision. Lancers and Bastions now fire on a full period that includes the telegraph. STRAFE/DRIFT lasts `max(fire_interval_s - telegraph_s, 0)`, so shots are `fire_interval_s` apart start to start: 2.0 s / 2.5 s with default tuning (was 2.3 s / 3.0 s), matching the Needle. Tuning is unchanged and read from Config. This follow-up review pass found one wording fix in the architecture doc and made no code changes.

**Files changed:**
- `game/entities/enemies/lancer/lancer.gd`: `_strafe_s` replaces `_fire_interval_s`; class doc updated.
- `game/entities/enemies/bastion/bastion.gd`: `_drift_s` replaces `_fire_interval_s`; class doc updated.
- `game/tests/unit/test_lancer.gd`: strafe-time assertions updated; new full-period test and clamp test.
- `game/tests/unit/test_bastion.gd`: drift-time assertions updated; new full-period test and clamp test.
- `game/tests/data/test_data_files.gd`: Lancer and Bastion range tests now require `telegraph_s <= fire_interval_s`.
- `_bmad-output/game-architecture.md`: the Lancer and Bastion as-built bullets describe the full-period cadence. In the follow-up pass, the Story 2.5 / 2.7 headings now note the decision #38 amendment.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md`: row #38.
- `_bmad-output/implementation-artifacts/spec-dw-40-enemy-fire-cadence-full-period.md`: this spec.
- `_bmad-output/implementation-artifacts/deferred-work.md`: orchestrator bookkeeping (DW-40 closed, DW-69 and DW-70 added). This run committed it unchanged and did not edit it.

**Review (follow-up pass):** 17 findings.
- 1 patch applied (low): the architecture headings contradicted the amended bullets.
- 0 deferred.
- 16 rejected, each with its reason in the Review Triage Log. Eight were `false`: the spec status, the clamp-test looseness, the "18 bullets" spec claim, the ledger "Never" breach (×2), the scope of the data constraint, and the spec artifact. Eight were `low`: the ledger title truncation (the run may not edit the ledger), the decision #38 exclusions (DW-69 tracks them), equality boundary (×2, carried), frame overshoot (carried), balance follow-up (carried), Story 2.7 spec text (done history), and the unit-surface-only cadence tests (carried).

**Follow-up review:** not recommended. On a follow-up pass, only a patched `high` would justify another. Patches by verdict: high 0, medium 0, low 1.

**Verification:** `--import` exited 0. Full GUT suite: 892 tests, 891 passing, 0 failing, 1 pending (`test_hit_stop_overlap_keeps_longest`, a timing-dependent test that skips itself, unrelated to this change).

**Residual risks:**
- Enemies fire 15–20% more often, which changes difficulty; only a playtest can judge the feel.
- DW-69 (boss/Wasp cadence semantics) and DW-70 (stale Story 2.5 AC in epics.md) need a user decision.
