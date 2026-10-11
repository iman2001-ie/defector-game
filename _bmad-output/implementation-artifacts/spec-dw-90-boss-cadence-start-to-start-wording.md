---
title: 'DW-90: reword the Flagship cadence lines (FR49-FR51, Epic 7 ACs, GDD Flagship table) to start-to-start'
type: 'chore'
created: '2026-10-11'
status: 'done'
baseline_revision: 'c375161ebd101712f2aa74b30ee4ced1b0952935'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
warnings: []
deferred:
  - summary: >-
      The Flagship turrets are "staggered" (FR49, Story 7.3, GDD phase 1) but no stagger offset is defined in the docs or in `tuning.json` `boss.turrets`.
    evidence: |-
      `boss.turrets` has count, hp, spread_bullets, bullet_speed_px_s, fire_interval_s 3.0 and telegraph_s 0.5, with no stagger key; the architecture doesn't define it either. Under start-to-start the stagger is the only thing that separates the four turrets' clocks, so an Epic 7 implementer must invent a value (and must put it in data, per AGENTS.md). Pre-existing; this rewording didn't cause it.
    location: >-
      _bmad-output/planning-artifacts/epics.md (FR49, Story 7.3); game/data/tuning.json (boss.turrets)
    severity: low
---

<intent-contract>

## Intent

**Problem:** Decision #50 made every boss interval start-to-start (glow/charge inside the period), and DW-70 reworded Stories 2.5/2.7 to say so, but FR49-FR51, the Epic 7 story ACs and the GDD Flagship phase table still read "every N s after a G s glow", so an Epic 7 implementer reading only those lines could build interval + glow (DW-90).

**Approach:** The operator chose (2026-10-11) to reword those lines to the Story 2.5/2.7 start-to-start wording, keeping every number, and to record the change in the GDD decision log referencing decision #50 and DW-70. Docs only.

## Boundaries & Constraints

**Always:** Keep every number (bullet counts, speeds, HP, intervals, glow/charge durations, Wasp launch values) exactly as now. Use the DW-70 phrasing pattern: "fires every N s start-to-start; its/the G s glow runs inside that period, then it fires" (or "glows for G s inside that period, then fires"), citing decision #50 in the ACs. New decision-log row is #52, same 5-column format, Source naming DW-90.

**Never:** No code, data (`game/data/*.json`) or test change. No edit of `deferred-work.md`, `sprint-status.yaml` or cached `epic-*-context.md`. Don't touch FR20/FR22, the Lancer/Bastion GDD rows, or the Wasp launch cadence (`wasp_launch_interval_s` has no telegraph). Don't change the meaning of anything other than the cadence wording.

</intent-contract>

## Code Map

- `_bmad-output/planning-artifacts/epics.md:133` -- FR49: "Each turret fires a 3-bullet spread (350 px/s) every 3.0 s, staggered, after a 0.5 s glow."
- `epics.md:134` -- FR50: "12-bullet radial burst (300 px/s) every 3.0 s after a 0.6 s charge glow".
- `epics.md:135` -- FR51: desperate barrage "every 1.5 s after a 0.4 s glow, plus an aimed 3-bullet spread (400 px/s) every 2.0 s after a 0.3 s glow".
- `epics.md:1652-1654` -- Story 7.3 Phase 1 AC (turrets).
- `epics.md:1686-1688` -- Story 7.4 Phase 2 AC: "When 3.0 s pass / Then the core glows for 0.6 s, then fires..." (reads as interval then glow).
- `epics.md:1722-1724` -- Story 7.5 DESPERATE AC.
- `epics.md:785-787`, `:831-833` -- Story 2.5 / 2.7 DW-70 wording: the golden example. Read-only.
- `gdds/gdd-game-project-2026-10-06/gdd.md:283-285` -- Flagship phase table Attacks column, same three cadences.
- `gdds/gdd-game-project-2026-10-06/decision-log.md` -- table ends at #51 (line 55); #38 line 42, #50 line 54.
- `_bmad-output/game-architecture.md:1192` -- Flagship cadence bullet already start-to-start. Read-only.

## Tasks & Acceptance

**Execution:**
- `_bmad-output/planning-artifacts/epics.md` -- reword FR49, FR50, FR51 cadence clauses and the Story 7.3, 7.4, 7.5 cadence ACs to start-to-start (decision #50) -- remove the interval + glow misreading.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md` -- reword the three Flagship table Attacks cells the same way -- GDD matches the ACs.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- append row #52 (DW-90, 2026-10-11) naming the edited lines, referencing #50 and DW-70, stating no number, code or data changed; add "FR49-FR51, Epic 7 ACs and GDD Flagship table amended (DW-90)" note to #50's Status cell -- traceability.

**Acceptance Criteria:**
- Given `epics.md` FR49-FR51 and Stories 7.3-7.5, when read, then each boss cadence (turrets 3.0/0.5, core 3.0/0.6, desperate radial 1.5/0.4, desperate aimed 2.0/0.3) says start-to-start with the glow/charge inside the period, and no "every N s after a G s glow" phrasing remains for them.
- Given `gdd.md:283-285`, when read, then the same four cadences use the same start-to-start wording.
- Given the old and new text, when every number is compared, then all are unchanged.
- Given `decision-log.md`, when read, then row #52 records the change with references to decision #50 and DW-70.
- Given `git diff --stat`, when inspected, then only the three planning docs and this spec changed.

## Spec Change Log

## Review Triage Log

### 2026-10-11 — Review pass
- verdicts: 22 findings — high 0, medium 0, low 17, false 5, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) Decision #50's body still quotes the old FR49/FR51 wording — it is a historical record of what #50 checked; its Status cell now points to the DW-90 amendment and #52 records the new wording, so readers aren't misled. Rewriting a past decision's body is not a direct correction.
  - `[low]` `[patch]` (blind) Readiness report G-FR60 to G-FR62 keeps the old phrasing with no stated reason — added a clause to #52: the report is a dated 2026-10-06 assessment snapshot, left unchanged on purpose.
  - `[low]` `[patch]` (blind) Desperate radial glow worded differently in epics.md vs GDD, "it fires" unclear for 2 alternating bursts — FR51, Story 7.5 and GDD phase 3 now share "(each burst's 0.4 s charge glow runs inside that period, then that burst fires)".
  - `[low]` `[reject]` (blind) Spec verification grep expected output wrong (FR20 doesn't match) and pattern too weak — fix edits this build's spec. Broader grep `after a [0-9.]+ s [a-z ]*glow` was run anyway: only FR20/FR22 match.
  - `[low]` `[reject]` (blind) Story 7.4 AC lost its "When 3.0 s pass" first-cycle trigger — the old trigger encoded the interval-plus-glow reading DW-90 removes; the new shape is the DW-70 Story 2.5/2.7 golden pattern, and first-cycle timing was never specified for 7.3/7.5 either. Specifying it needs a new design decision, not a direct correction.
  - `[low]` `[defer]` (blind) Turret "staggered" offset is undefined (no tuning key in `boss.turrets`) — pre-existing, not caused by this rewording; deferred for Epic 7 planning.
  - `[low]` `[reject]` (blind) Spec frontmatter context lists godot-testing.md, line-number Code Map anchors — fix edits this build's spec; the context entry is mandated for every spec.
  - `[false]` `[reject]` (blind) Nothing checks #52 for old wording; log has old wording in two places — #52 quotes the old phrase only as the misreading it removes, and #50's Status cell points to the amendment.
  - `[false]` `[reject]` (blind) #52 doesn't record that the GDD-folder epics.md was checked — no bad outcome: that file states no glow durations (lines 135-140), so nothing needed syncing.
  - `[low]` `[reject]` (edge) Story 7.4 first-burst timing unstated — same as the blind Story 7.4 finding; rejected on the same grounds.
  - `[low]` `[defer]` (edge) Stagger offset unstated under start-to-start — same root cause as the blind stagger finding; deferred.
  - `[low]` `[reject]` (edge) Desperate radial and aimed glows coincide every 6 s, unspecified — pre-existing; two separate timers with separate tuning keys (architecture Flagship cadence bullet) are the natural reading; not caused by this change.
  - `[low]` `[patch]` (edge) Readiness report G-FR60 to G-FR62 old wording — same as the blind readiness finding; patched via the #52 clause.
  - `[low]` `[reject]` (edge) #50 quote orphaned — same as the blind #50 finding; rejected on the same grounds.
  - `[low]` `[patch]` (verification-gap) Readiness report old wording — same as above; patched via the #52 clause.
  - `[false]` `[reject]` (verification-gap) GDD-folder epics.md needs no fix — informational; confirms no defect.
  - `[low]` `[patch]` (intent) R2 gap: readiness report — same as above; patched via the #52 clause.
  - `[low]` `[reject]` (intent) R2 gap: #50 body quotes — same as the blind #50 finding.
  - `[low]` `[reject]` (intent) AC shape split (7.4 Given/When/Then, 7.3/7.5 inline) — both forms state start-to-start as the intent asks; 7.3/7.5 carry other clauses in the same AC; cosmetic.
  - `[false]` `[reject]` (intent) FR-level change goes beyond DW-70 precedent — the intent explicitly names FR49-FR51.
  - `[low]` `[reject]` (intent) "2 alternating radial bursts every 1.5 s" ambiguous — pre-existing, carried over unchanged; `boss.desperate.radial_interval_s` defines it.
  - `[false]` `[reject]` (intent) Artifact-only receipt doesn't apply — informational; correct, and no receipt is asserted.

## Verification

**Commands:**
- `grep -nE "after a 0\.[3-6] s (charge )?glow|after a 0\.[3-6] s turret glow|each after a 0\.4 s charge glow" _bmad-output/planning-artifacts/epics.md _bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md` -- expected: only FR20/FR22 (Lancer/Bastion, out of scope) match.
- `git diff --stat` -- expected: epics.md, gdd.md, decision-log.md and this spec only.

## Auto Run Result

Status: done

**Summary:** Reworded the Flagship boss cadence lines to start-to-start, matching decision #50 and the DW-70 wording of Stories 2.5/2.7. Each line now says the boss fires every N s start-to-start, with the glow or charge inside that period. Every number is unchanged. Docs only: no code, data or tests changed.

**Files changed:**
- `_bmad-output/planning-artifacts/epics.md` -- FR49, FR50, FR51 and the Story 7.3 (Phase 1), 7.4 (Phase 2, rebuilt in the DW-70 Given/When/Then shape) and 7.5 (DESPERATE) ACs reworded; the ACs cite decision #50.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md` -- Flagship phase table Attacks cells for phases 1-3 reworded the same way.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- new row #52 (DW-90), referencing #50, #38 and DW-70 and noting the readiness report is a dated snapshot left unchanged on purpose; #50's Status cell notes the DW-90 amendment.
- `_bmad-output/implementation-artifacts/spec-dw-90-boss-cadence-start-to-start-wording.md` -- this spec.

**Review findings:** 22 findings (0 high, 0 medium, 17 low, 5 false).
- Patched (2 entries, both low): readiness-report clause added to #52; identical desperate-radial glow phrase in FR51, Story 7.5 and the GDD.
- Deferred (1 entry, low): turret stagger offset undefined (pre-existing).
- Rejected: #50 body quotes old wording (historical record; Status cell points to the amendment); spec grep/frontmatter nits (fix edits this spec); Story 7.4 first-cycle timing (old trigger encoded the misreading; needs a new decision); coincident desperate timers and alternating-burst ambiguity (pre-existing); AC shape split (cosmetic); 5 false (see triage log).

**Follow-up review recommended:** false. Patched entries: high 0, medium 0, low 2.

**Verification:**
- `grep -nE "after a [0-9.]+ s [a-z ]*glow"` over epics.md and gdd.md -- only FR20/FR22 (Lancer/Bastion, out of scope) match; no Flagship line keeps the old wording.
- `git diff --stat` -- only the three planning docs and this spec.
- Word-level diff check by the implementer: all bullet counts, speeds, HP, intervals, glow/charge times and Wasp launch values unchanged.
- No GUT run: no code, data or test changed.

**Residual risks:** The turret stagger offset and the first-cycle timing after each phase entry are still unspecified for Epic 7 (deferred / rejected above). The readiness report keeps the old phrasing by design.
