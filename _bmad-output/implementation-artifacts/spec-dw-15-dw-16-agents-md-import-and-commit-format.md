---
title: 'DW-15/DW-16: AGENTS.md commit-subject format and --import re-run guidance'
type: 'chore'
created: '2026-10-07'
status: 'done'
baseline_revision: '2034298b2a2c3db8cd70ea4bb1cbe9b7aa6c5ffd'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
warnings: []
deferred:
  - summary: >-
      AGENTS.md section 5 still requires a story id or key, so bmad-loop's other commit subjects (`sweep <bundle>: DW-n via bmad-loop`, `chore(sweep|operator|decisions|retro): ...`) and manual non-story commits still do not fit the rule.
    evidence: |-
      git log shows `sweep dw-stress-bench-nfr-peak: DW-9, DW-21 via bmad-loop`, `chore(operator): confirm ...`, `chore(decisions): pre-answer DW-15`, `Epic 1 retro: revision 2`. The DW-15 decision only covers the `story <key>: ...` form, and the fix edits AGENTS.md (agent-context file), so it is deferred.
    location: >-
      AGENTS.md:60
    severity: medium
  - summary: >-
      The --import re-run triggers name only adding class_name scripts or imported assets; renaming, moving or deleting class_name scripts, changing imported assets, and pulling or switching branches that do so are covered only by the generic "stale game/.godot/" clause, and no symptom of a stale cache is given.
    evidence: |-
      Headless -s runs never rescan the class cache, whatever the cause of the change. A typical symptom is a parse error naming a class_name that exists. The fix edits AGENTS.md (agent-context file), so it is deferred.
    location: >-
      AGENTS.md:30; _bmad-output/game-architecture.md:1335-1337
    severity: low
  - summary: >-
      The DW-15 decision (amend AGENTS.md section 5) is recorded only in the deferred-work ledger, not in a decision log as AGENTS.md section 4 asks.
    evidence: |-
      Commit `chore(decisions): pre-answer DW-15` recorded it in the ledger before this run. No process decision log exists, and the GDD decision log covers game design. This is pre-existing and not caused by this change.
    location: >-
      _bmad-output/implementation-artifacts/deferred-work.md (DW-15)
    severity: low
  - summary: >-
      The --import re-run reason ("headless -s runs don't rescan the class cache") explains only the class_name trigger; it does not say why new imported assets also need a re-run (headless -s runs don't import them either).
    evidence: |-
      AGENTS.md:30 and game-architecture.md:1335-1337 list "new imported assets" as a trigger, but the stated cause is only the class cache. A new WAV that Audio preloads has no .import artefact until --import runs. The instruction itself is still correct, so following it gives the right result. The fix edits AGENTS.md (agent-context file), so it is deferred.
    location: >-
      AGENTS.md:30; _bmad-output/game-architecture.md:1335-1337
    severity: low
---

<intent-contract>

## Intent

**Problem:** AGENTS.md section 5 only allows the manual `Story X.Y: summary` commit subject, but bmad-loop commits as `story <key>: ...` (DW-15, decision recorded 2026-10-07: amend section 5). AGENTS.md section 3 and the architecture's headless CLI loop call the `--import` step "one-time, on a fresh clone", but headless `-s` runs never rescan the `class_name` cache, so an existing checkout also needs `--import` after adding `class_name` scripts or new imported assets, or whenever `game/.godot/` is stale (DW-16).

**Approach:** Reword the one bullet in AGENTS.md section 5 to accept both subject forms, and reword the `--import` note in AGENTS.md section 3 and the matching `# One-time, on a fresh clone` comment in `game-architecture.md` to say when to re-run it.

## Boundaries & Constraints

**Always:** Keep `<GODOT_DIR>` placeholders and exact command lines unchanged. Keep the existing explanation of what `--import` does (builds the `class_name` cache, imports the WAVs `Audio` preloads). Keep the "references the story id" requirement and the manual example. Match the surrounding terse doc style.

**Never:** Edit `sprint-status.yaml` (the epic-1 status fix is the operator's job) or the deferred-work ledger. Add machine-specific paths, emails or other sensitive values. Touch game code, the CLI export section at ~line 1237 (already correct for fresh clones), or `godot-testing.md` knowledge files. Change any design decision.

</intent-contract>

## Code Map

- `AGENTS.md:29-31` -- section 3 Tests bullet; line 30 is the parenthetical `(one-time, on a fresh clone with no game/.godot/: builds the class_name cache and imports the WAVs that Audio preloads)`. Target of DW-16.
- `AGENTS.md:60` -- section 5 commit bullet: `Keep commits small, with a clear message that references the story id (e.g. Story 1.2: ship chases cursor).` Target of DW-15.
- `_bmad-output/game-architecture.md:1335` -- comment `# One-time, on a fresh clone: import the project (builds the class_name cache and imports the WAVs Audio preloads)` in the AI Tooling headless CLI loop block. Target of DW-16 (ledger's `:1232` anchor is stale).
- `git log --format=%s` -- evidence of the bmad-loop form: `story 1-3-fire-the-laser: implemented and reviewed via bmad-loop`. Read-only.
- `CLAUDE.md` -- imports AGENTS.md; no change needed (does not restate either rule).

## Tasks & Acceptance

**Execution:**
- `AGENTS.md` -- section 3: replace the "one-time, on a fresh clone" parenthetical so it says to run `--import` on a fresh clone with no `game/.godot/`, and re-run it after adding `class_name` scripts or new imported assets or whenever `game/.godot/` is stale, because headless `-s` runs do not rescan the class cache; keep what it does. Section 5: amend the commit bullet to accept either the manual `Story X.Y: summary` form or the bmad-loop `story <key>: ...` form (key is the story file slug, e.g. `story 1-3-fire-the-laser: ...`). -- DW-15, DW-16.
- `_bmad-output/game-architecture.md` -- reword the line-1335 comment the same way (fresh clone, plus re-run after new `class_name` scripts/imported assets or a stale `game/.godot/`). -- DW-16.

**Acceptance Criteria:**
- Given AGENTS.md section 5, when an agent reads the commit rule, then it accepts both `Story X.Y: summary` and `story <key>: ...` subjects and still requires the story id/key.
- Given AGENTS.md section 3, when an agent reads the import note, then it no longer says "one-time" and states the re-run triggers (new `class_name` scripts, new imported assets, stale `game/.godot/`) and the reason (headless `-s` runs don't rescan the class cache).
- Given `game-architecture.md` AI Tooling CLI block, when read, then the import comment states the same triggers and no longer says "One-time".
- Given the full diff, when scanned, then it contains no machine-specific paths, emails or secrets, and every command line is byte-identical to the baseline.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 19 findings — high 1, medium 4, low 10, false 4, maybe-false 0
- findings:
  - `high` `patch` Blind: the spec's leak-scan grep contains a literal employer email domain, so committing it would publish employer details in a public repo. — Patched: the subagent replaced it with a generic whole-diff scan (`git diff HEAD`, drive-path and email regexes). A history and tracked-file search found no earlier occurrence.
  - `medium` `patch` Blind: the leak scan covered only the two doc files, not the new spec. — Same root cause as the row above, fixed by the same patch: the scan now covers `git diff HEAD`, and the spec is staged.
  - `false` `reject` Blind: plain `git diff --stat` would not list the spec. — The spec was registered with `git add -N`, so `git diff` and `git diff HEAD --stat` both list it (checked).
  - `medium` `defer` Blind: §5 still excludes sweep, chore, retro and other non-story commits. — Real (see git log). The DW-15 decision only covers `story <key>:`, and the fix edits AGENTS.md, so it is deferred.
  - `low` `reject` Blind: the bmad-loop form doesn't spell out its fixed suffix. — `...` deliberately leaves the summary free; the slug example removes the ambiguity. Readers are unlikely to be confused, and the fix only adds wording.
  - `low` `defer` Blind: re-run triggers miss rename/delete, modified assets, pulls/branch switches and GUT updates. — Real, partly covered by the "stale" clause. AGENTS.md is an agent-context file, so it is deferred.
  - `low` `defer` Blind: no symptom is given for a stale `game/.godot/`. — Grouped into the re-run-triggers deferral above.
  - `false` `reject` Blind: the CLI export block (~1237) is inconsistent. — That block always runs `--import` immediately before `--export-release`, so following it never exports from a stale cache.
  - `low` `defer` Blind: the DW-15 decision is not in a decision log. — Pre-existing (recorded in the ledger by `chore(decisions): pre-answer DW-15`), not caused by this change.
  - `low` `reject` Blind: the AGENTS.md wording is long and dense. — Cosmetic. Restructuring into sub-bullets is more than a direct correction.
  - `medium` `defer` Edge: the `sweep <slug>: DW-n via bmad-loop` form is not covered. — Same root cause as the non-story-commit deferral.
  - `medium` `defer` Edge: `chore(...)` housekeeping commits carry no story id. — Same root cause as the non-story-commit deferral.
  - `low` `defer` Edge: rename/move/delete of a `class_name` script is not listed. — Grouped into the re-run-triggers deferral.
  - `low` `defer` Edge: a pull or branch switch bringing in new scripts is not listed. — Grouped into the re-run-triggers deferral.
  - `low` `defer` Edge: the architecture comment misses the same triggers. — Grouped into the re-run-triggers deferral.
  - `low` `defer` Edge (claim): the spec calls `story <key>:` "the" bmad-loop form. — Grouped into the non-story-commit deferral. Since that group's highest verdict is medium, this row shares the defer route.
  - `low` `defer` Intent: §5 doesn't cover every bmad-loop subject (reading B). — Grouped into the non-story-commit deferral.
  - `false` `reject` Intent: the ledger anchor `:1232` points at the export block, which was not edited. — The bundle intent explicitly names ~1332 `# One-time, on a fresh clone`, and the export block already runs import first (see above).
  - `false` `reject` Intent: the checks are string-level only. — The change is docs-only, and text checks plus the diff read are the right verification. No defect is claimed.

### 2026-10-07 — Review pass
- verdicts: 23 findings — high 0, medium 3, low 13, false 7, maybe-false 0 (follow-up pass; carried rows keep their logged verdicts)
- findings:
  - `medium` `defer` Blind: this change's own commit (`9345d06`, `DW-15, DW-16: ...`) fits neither allowed subject form. — carried: same claim as the logged non-story-commit row (AGENTS.md:60 still reads as described); already deferred, not deferred again.
  - `medium` `defer` Blind: the non-story-subject and re-run-trigger gaps could have been fixed here instead of deferred. — carried: same claims as the logged non-story-commit and re-run-triggers rows; AGENTS.md fixes route to defer by rule.
  - `false` `reject` Blind: `game-architecture.md` has a per-section change log with no DW-16 entry. — The list at ~1407-1430 is the dated "As-built reconciliation 2026-10-07" record of Story 1.10; its DW-17 bullet was written by Story 1.10 itself (`1a40a12`). It is not a running change log, so no entry is missing.
  - `low` `defer` Blind: the stated reason (class cache not rescanned) does not explain the "new imported assets" trigger. — Real: new WAVs lack `.import` artefacts until `--import` runs, which is a separate cause. The instruction is still correct. The fix edits AGENTS.md, so it is deferred (new frontmatter item).
  - `low` `reject` Blind: DW-15 is marked done in the ledger although the sprint-status half is still open. — The intent assigns the epic-1 status fix to the operator and forbids ledger edits; ledger status is orchestrator bookkeeping.
  - `false` `reject` Blind: the spec's status fields contradict its content and the Auto Run Result is missing. — `in-review` is this follow-up pass's normal transition, and the Auto Run Result is rewritten at finalize. The fix would also edit this build's spec.
  - `low` `reject` Blind: the Spec Change Log is empty although the spec was patched. — The Change Log records bad_spec loopbacks, and none happened; the patch is logged in the triage row. The fix edits this build's spec.
  - `low` `reject` Blind: AC4 (command lines byte-identical) has no verification command. — The fix edits this build's spec. Checked by hand: `git diff <baseline> -- AGENTS.md _bmad-output/game-architecture.md | grep '^[-+].*Godot_v4'` prints nothing.
  - `low` `reject` Blind: the verification commands diff the working tree, so they cannot be reproduced after commit. — The fix edits this build's spec. Run against the baseline here instead (see Auto Run Result).
  - `low` `reject` Blind: the leak-scan regex misses `/c/Users/`, `/home/`, other drive paths and machine names. — The fix edits this build's spec. A broader scan of added lines since the baseline (drive paths, `/x/Users/`, `/home/`, emails, employer and user names) found nothing.
  - `false` `reject` Blind: the ledger's stale DW-16 anchor (`:1232`) is left in place. — The intent forbids ledger edits; the ledger belongs to the orchestrator.
  - `medium` `defer` Edge: this change's own commit subject breaks the amended rule. — carried: same as the logged non-story-commit row.
  - `low` `reject` Edge: agents may mix the forms (`Story 1-3-...:` or `story 1.3:`) and break tooling matching one form. — No tooling in the repo parses commit subjects (searched); each form comes with its own example. Unlikely in practice, and the fix only adds wording.
  - `low` `defer` Edge: rename/move/delete of `class_name` scripts or changed assets not listed. — carried: logged re-run-triggers row.
  - `low` `defer` Edge: pull or branch switch not listed. — carried: logged re-run-triggers row.
  - `low` `defer` Edge: no symptom of a stale `game/.godot/` is named. — carried: logged stale-symptom row.
  - `low` `defer` Edge: the architecture comment misses the same triggers. — carried: logged architecture-comment row.
  - `false` `reject` Edge: the leak-scan regex is too narrow. — Same claim as the Blind leak-scan row: the fix edits this build's spec, and a broader scan found nothing.
  - `false` `reject` Edge: `git diff --stat` cannot verify scope after commit. — Same claim as the Blind reproducibility row: the fix edits this build's spec; scope was checked with `git diff <baseline> --stat`.
  - `low` `defer` Intent: reading R1b (all bmad-loop subjects) is not implemented. — carried: logged reading-B row.
  - `low` `defer` Intent: reading R2b (every cache-changing event) is covered only by the "stale" catch-all. — carried: logged re-run-triggers row.
  - `false` `reject` Intent: R1c treats the change as a rule change rather than a clarification. — The auditor calls it cosmetic either way; no defect is claimed.
  - `false` `reject` Intent: the checks are string-level and the behavioural surface is unverified. — carried: logged string-level-checks row.

## Verification

**Commands:**
- `grep -n "one-time, on a fresh clone\|One-time, on a fresh clone" AGENTS.md _bmad-output/game-architecture.md` -- expected: no matches (the unrelated "one-time entry effects" at `game-architecture.md:1107` is out of scope).
- `git diff --stat` -- expected: only `AGENTS.md` and `_bmad-output/game-architecture.md` (plus this spec) changed.
- `git diff HEAD | grep -nE "[A-Za-z]:[\\/]Users[\\/]|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"` -- expected: no matches other than `noreply` addresses.


## Auto Run Result

Status: done (follow-up review pass)

**Summary:** Resolved DW-15 and DW-16 in documentation. AGENTS.md section 5 now accepts the bmad-loop `story <key>: ...` commit subject (key = story file slug) alongside the manual `Story X.Y: summary` form. The `--import` notes in AGENTS.md section 3 and the architecture's headless CLI loop no longer say "one-time": they say to run it on a fresh clone and re-run it after adding `class_name` scripts or new imported assets, or whenever `game/.godot/` is stale, because headless `-s` runs don't rescan the class cache.

**Files changed (since baseline `2034298b2a2c3db8cd70ea4bb1cbe9b7aa6c5ffd`):**
- `AGENTS.md` -- section 3 import note reworded (DW-16); section 5 commit rule accepts both subject forms (DW-15).
- `_bmad-output/game-architecture.md` -- AI Tooling CLI block import comment reworded to match (DW-16).
- `_bmad-output/implementation-artifacts/spec-dw-15-dw-16-agents-md-import-and-commit-format.md` -- this spec.

**Review findings (follow-up pass):** 23 findings (high 0, medium 3, low 13, false 7). No patches. 13 rows carried from the first pass, keeping their routes and not deferred again. 1 new deferral (low): the stated `--import` reason explains only the class-cache trigger, not the new-assets trigger. 9 non-carried rows rejected: the architecture "change log" (it is Story 1.10's dated reconciliation record); DW-15 ledger status and the stale ledger anchor (orchestrator- and operator-owned, excluded by the intent); spec status, Change Log, AC4 command, reproducibility and leak-regex findings (each fix edits this build's spec; the checks were run by hand instead, see below); form-mixing (no tooling parses subjects); R1c (cosmetic). Reasons are in the triage log.

**Follow-up review:** false. Follow-up pass with no `high` patched. Patched counts by verdict: none.

**Verification:**
- `grep -n "one-time, on a fresh clone\|One-time, on a fresh clone" AGENTS.md _bmad-output/game-architecture.md`: no matches.
- `git diff 2034298b2a2c3db8cd70ea4bb1cbe9b7aa6c5ffd --stat` (committed range): only `AGENTS.md`, `_bmad-output/game-architecture.md` and this spec.
- `git diff <baseline> -- AGENTS.md _bmad-output/game-architecture.md | grep '^[-+].*Godot_v4'`: no output, so the command lines are byte-identical.
- A broader leak scan of added lines since the baseline (drive-letter paths, `/x/Users/`, `/home/`, email addresses, employer and user names): no matches.
- Docs-only change, so GUT was not run.

**Residual risks:** the deferred items in frontmatter. `deferred-work.md` has uncommitted orchestrator edits (DW-15/DW-16 closed, DW-28 to DW-30 added) that were there before this run. This run left them alone and did not commit them, because the orchestrator owns the ledger.
