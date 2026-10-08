---
title: 'DW-28: AGENTS.md commit-subject forms for non-story commits'
type: 'chore'
created: '2026-10-08'
status: 'done'
baseline_revision: '3c3bec6ace728a56512d559ed6ab0b1c14a68a3d'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
warnings: []
deferred:
  - summary: >-
      Retro commits now fit two forms, `chore(retro): ...` and a clear summary such as `Epic 1 retro: revision 2`. AGENTS.md section 5 doesn't say which to use when, for example only bmad-loop or orchestrator commits use `chore(<scope>)`.
    evidence: |-
      AGENTS.md:62 gives `chore(retro): epic 3 retrospective` as a bookkeeping example, and AGENTS.md:63 lists retros as manual non-story work with `Epic 1 retro: revision 2`. Both are real subjects in git log. An agent writing a retro commit can't tell from the text which form applies. The fix is a short clarifying clause in AGENTS.md (agent-context file), so it is deferred.
    location: >-
      AGENTS.md:62-63
    severity: low
---

<intent-contract>

## Intent

**Problem:** AGENTS.md section 5 (line 60) says every commit message references a story id or key, but bmad-loop also writes `sweep <bundle>: DW-n via bmad-loop` and `chore(<scope>): ...` commits, and manual non-story work (e.g. `Epic 1 retro: revision 2`) has no story either, so most of the log breaks the written rule (DW-28). On 2026-10-07 the user decided to amend section 5 to list these forms while keeping story references required for story work.

**Approach:** Reword the section 5 commit bullet so story work keeps its two existing forms, and add the three non-story forms (sweep, chore, clear summary for manual non-story work) with real examples from `git log`. Record the decision as GDD decision-log row #36, since no row covers it.

## Boundaries & Constraints

**Always:** Docs only. Keep the existing text from "either the manual form `Story X.Y: summary`" through "(e.g. `story 1-3-fire-the-laser: ...`)" byte-identical. Story work must still be required to reference the story id or key. Examples are real subjects taken from `git log`. Match the terse AGENTS.md style. Append the decision-log row after #35 in the existing table format; never edit or renumber existing rows.

**Never:** Edit the deferred-work ledger or `sprint-status.yaml`. Touch game code or any other AGENTS.md bullet. Add machine-specific paths, emails, employer or user names. Rewrite git history or invent new subject forms beyond the three the decision names.

</intent-contract>

## Code Map

- `AGENTS.md:60` -- section 5 commit bullet: "Keep commits small, with a clear message that references the story id or key: either the manual form ... or the bmad-loop form `story <key>: ...`, where the key is the story file slug (e.g. `story 1-3-fire-the-laser: ...`)." The only place the rule is stated (grep of tracked docs found no other copy; `CLAUDE.md` imports AGENTS.md and does not restate it).
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- table `| # | Date | Decision / Change | Source | Status |`, last row #35 (line 39). No row mentions commit subjects. Row #34/#35 show the style for process decisions recorded via DW ids (`Applied 2026-10-07 (DW-22)`).
- `git log --format=%s` -- read-only evidence: `sweep dw-wave-test-reliability: DW-35, DW-36, DW-39, DW-38 via bmad-loop`, `chore(retro): epic 3 retrospective`, `chore(decisions): pre-answer DW-24`, `chore(sweep): ingest retro action items`, `Epic 1 retro: revision 2`.

## Tasks & Acceptance

**Execution:**
- `AGENTS.md` -- turn line 60 into: "Keep commits small, with a clear message. Story work must reference the story id or key: either the manual form ... (unchanged) ...`story 1-3-fire-the-laser: ...`). Other commits use:" followed by three indented sub-bullets: (1) bmad-loop deferred-work bundles `sweep <bundle>: DW-n ...` with a real sweep example; (2) orchestration and bookkeeping `chore(<scope>): ...` with real `chore(retro)`/`chore(decisions)` examples; (3) manual non-story work such as retros and correct-course: a clear summary of the change, e.g. `Epic 1 retro: revision 2`. -- DW-28.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- append row `| 36 | 2026-10-07 | ... | User (bmad-loop decision, DW-28) | Applied 2026-10-08 (DW-28) |` stating the commit-subject rule: story work keeps `Story X.Y: summary` / `story <key>: ...`; `sweep <bundle>: DW-n ...` and `chore(<scope>): ...` for orchestration/bookkeeping; a clear summary for manual non-story work; amended passage AGENTS.md section 5. -- AGENTS.md section 4 asks for decisions in the relevant log.

**Acceptance Criteria:**
- Given AGENTS.md section 5, when an agent reads the commit rule, then it requires story work to reference the story id or key with the two unchanged story forms and examples, and also accepts `sweep <bundle>: DW-n ...`, `chore(<scope>): ...`, and a clear summary for manual non-story work (retros, correct-course).
- Given the subjects in `git log` since the DW-15 change, when each is checked against the new rule, then every one fits one of the five forms.
- Given the decision log, when read, then the last row is #36 recording this rule and rows #1-#35 are byte-identical to the baseline.
- Given the full diff against the baseline, when scanned, then it contains no machine-specific paths, emails, employer or user names, and touches only `AGENTS.md`, the decision log and this spec.

## Verification

**Commands:**
- `git diff 3c3bec6ace728a56512d559ed6ab0b1c14a68a3d --stat` -- expected: only AGENTS.md, decision-log.md and this spec (spec added via `git add -N`).
- `git diff 3c3bec6ace728a56512d559ed6ab0b1c14a68a3d -- _bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md | grep -c '^-[^-]'` -- expected: 0.
- `grep -c 'either the manual form `Story X.Y: summary` (e.g. `Story 1.2: ship chases cursor`) or the bmad-loop form `story <key>: ...`, where the key is the story file slug (e.g. `story 1-3-fire-the-laser: ...`)' AGENTS.md` -- expected: 1.
- `git diff 3c3bec6ace728a56512d559ed6ab0b1c14a68a3d | grep -E -i '^\+.*([A-Za-z]:[\\/]|/(c|home)/|Users[\\/]|@[a-z0-9-]+\.[a-z]{2,})'` -- expected: no output.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 19 findings — high 0, medium 0, low 12, false 7, maybe-false 0
- findings:
  - `low` `reject` Blind: the "clear summary" form accepts any subject, so the AC that history fits the five forms can't fail. — The free-form summary is the user's DW-28 decision wording. Narrowing it would change that decision, and the AC half of the fix edits this spec.
  - `low` `defer` Blind: retros fit both `chore(retro)` and the clear-summary form, and the text doesn't say which to use. — Real: AGENTS.md:62 and :63 both have retro examples. The fix edits AGENTS.md (agent-context file), so it is deferred (frontmatter item).
  - `low` `reject` Blind: `chore(<scope>)` doesn't list the allowed scopes. — The decision text says `chore(<scope>)` with an open scope. A closed list would narrow the user's decision, and the existing examples already show real scopes.
  - `low` `reject` Blind: the sweep template leaves out the `via bmad-loop` suffix and the comma separator. — `...` deliberately leaves the tail free, and the example shows both. Only the orchestrator writes these subjects, so readers are unlikely to be confused.
  - `low` `patch` Blind: row #36 clashes with old commit `2b7524f` ("decision 36 (story 1.9)"), which actually edited row #32. — Checked with `git show 2b7524f`: its only row change is #32. Patched: row #36 now records the clash, the same way row #34 records its numbering clash.
  - `false` `reject` Blind: the AC's "since the DW-15 change" names no commit. — The fix edits this build's spec. The check was run anyway: every subject after `07f5ab5` fits a structured form.
  - `false` `reject` Blind: the grep verification command breaks its own Markdown, and `...` is a regex wildcard. — The fix edits this build's spec. The command was run and returned 1, and `...` matching itself is a superset check that still pins every other byte.
  - `false` `reject` Blind: the spec's context list includes unrelated files. — The fix edits this build's spec. Project rules require those two context entries in every spec.
  - `low` `patch` Blind: row #36 doesn't record that it extends DW-15. — Patched: row #36 now says it extends DW-15, which added the `story <key>: ...` form.
  - `low` `reject` Blind: nothing covers commits that mix story and non-story work. — Rare, because commits are kept small. A tie-break rule adds complexity, and story references stay required for any story work.
  - `low` `reject` Edge: unclear whether a hotfix to a done story counts as story work. — Same root cause as the mixed-commit row (where "story work" ends). The plain reading is that it is story work and references the story. Defining it would add rule complexity for a rare case.
  - `low` `reject` Edge: `chore(operator): confirm <story>` is story-scoped but uses the chore form. — It is bookkeeping that bullet 2 explicitly covers, and the subject still names the story key. Only the orchestrator writes these subjects.
  - `low` `reject` Edge: a manual DW fix outside bmad-loop has no defined form. — It is manual non-story work, so the clear-summary form covers it. Requiring DW ids would add a rule the decision didn't make.
  - `low` `defer` Edge: two forms exist for retro commits. — Same root cause as the Blind retro row, so it shares that deferral.
  - `false` `reject` Intent: "Other commits use:" reads as more closed than "also accepts", and the opening clause was rewritten. — The decision says story references stay required for story work, so non-story commits need the listed forms. The story forms and examples are byte-identical (grep returned 1).
  - `false` `reject` Intent: the open `<scope>` is looser than the four scopes in the ledger. — Same claim as the Blind scope row. The decision itself uses `chore(<scope>)`.
  - `false` `reject` Intent: the free-form summary is unbounded. — It matches the decision text, and the auditor says so itself. Same claim as the first Blind row.
  - `false` `reject` Intent: the diff doesn't constrain the orchestrator's commit writer. — The intent asks only for a documentation amendment, and the documented forms are taken from the loop's actual output.
  - `low` `reject` Intent: subjects before `07f5ab5`, such as `2b7524f`, mention a story without a story form. — They predate the rule, and history is not rewritten. The `2b7524f` confusion is now noted in row #36.


### 2026-10-08 — Review pass
- verdicts: 18 findings — high 0, medium 0, low 11, false 7, maybe-false 0
- findings:
  - `low` `defer` Blind: retro commits fit both `chore(retro)` and the clear-summary form, with no tie-break. — carried: same claim as the earlier Blind retro row. AGENTS.md:62-63 still read the same, and the item is already in the frontmatter `deferred` list, so it isn't deferred again.
  - `low` `reject` Blind: AGENTS.md doesn't say which forms the tools write and which people write, so a manual DW fix outside the loop has no clear form. — carried: same claim as the earlier "manual DW fix outside bmad-loop" row. The clear-summary form covers it, and the text is unchanged.
  - `false` `reject` Blind: commit `53d37c4` breaks its own example (no `dw-` bundle prefix, no `via bmad-loop`). — Its subject `sweep agents-md-commit-subject-forms: DW-28 ...` fits the template `sweep <bundle>: DW-n ...`. The example illustrates the form and doesn't set the rule, and the orchestrator wrote that subject, not this diff.
  - `low` `reject` Blind: the `chore(<scope>)` examples leave out the `sweep` and `operator` scopes. — carried: same claim as the earlier open-scope and `chore(operator)` rows. The scope is open by the decision, and the bullet still reads the same.
  - `false` `reject` Blind: the spec's status in the working tree went from `done` back to `in-review`, and its result section was removed. — This is a temporary state during the follow-up review: this pass sets `in-review`, and finalization writes `done` and a new `## Auto Run Result` before committing.
  - `false` `reject` Blind: the ledger changes (DW-28 closed, DW-62 filed) aren't committed with the bundle, and no one owns them. — The orchestrator owns and writes the ledger. The intent forbids this work from editing it, and the reviewed diff doesn't touch it.
  - `low` `reject` Blind: "manual" means two things: the "manual form" for stories and "manual non-story work". — Real but minor. The intent requires the "either the manual form ..." passage to stay byte-identical, so it can't be reworded here.
  - `false` `reject` Blind: the `2b7524f` note in row #36 is git history housekeeping, not a design decision. — Row #34 sets the precedent of recording numbering clashes. The note stops a reader from tying "decision 36" in an old subject to this row. No harm is named.
  - `low` `reject` Blind: the AC "every subject fits one of the five forms" can't fail, because the clear summary accepts anything. — carried: same claim as the earlier free-form-summary and AC rows. The fix would edit this build's spec, and the summary form is the user's decision wording.
  - `low` `reject` Blind: AGENTS.md doesn't link to the `commit_message_template` setting in `.bmad-loop/policy.toml`. — Drift would need someone to set that template first, which is unlikely. Linking loop config from AGENTS.md also adds surface the decision didn't ask for.
  - `low` `defer` Edge: retro commits match both `chore(retro)` and the clear-summary form. — carried: same claim as the Blind retro row. It shares that existing deferral and isn't deferred again.
  - `low` `reject` Edge: the default `Revert "story <key>: ..."` subject doesn't start with a story form. — It still names the story key. Reverts are rare in this repo's linear history, and adding a revert rule would add complexity the decision didn't make.
  - `low` `reject` Edge: git's default merge subjects (`Merge branch ...`) match none of the listed forms. — Work lands linearly on `main` and git log has no merge commits, so this is rare. A merge exemption adds a rule the decision didn't make.
  - `false` `reject` Intent: "Other commits use:" reads as a closed list, but the AC says "also accepts". — carried: same claim as the earlier Intent row. Story forms are byte-identical (grep returned 1).
  - `low` `defer` Intent: the reading where each form belongs to a particular author is only partly implemented; retros appear under two forms. — carried: same root cause as the Blind retro row. It shares that existing deferral and isn't deferred again.
  - `low` `reject` Intent: the sweep template leaves out the `via bmad-loop` suffix from the problem statement. — carried: same claim as the earlier Blind sweep-template row. `...` leaves the tail free, and the example shows the suffix.
  - `false` `reject` Intent: the checks are text-only and the history AC can't fail. — carried: same as the earlier free-form-summary and AC rows. The fix would edit this build's spec, and docs-only work has no behaviour to test.
  - `false` `reject` Intent: the uncommitted working-tree changes touch the ledger, which this work must never edit. — The ledger change is the orchestrator's (DW-28 marked done, DW-62 filed from this spec's `deferred` list). It is outside the reviewed diff, and this run doesn't write the ledger.

## Auto Run Result

Status: done

**Summary:** This was a follow-up review pass on the already-applied DW-28 change, with no code changes. AGENTS.md section 5 still requires story work to reference the story id or key, using the two story forms, which are byte-identical to before. It lists `sweep <bundle>: DW-n ...`, `chore(<scope>): ...` and a clear summary for other commits. GDD decision-log row #36 records the rule.

**Files changed:**
- `AGENTS.md` -- section 5 commit bullet split into story work plus the three other-commit forms (in commit `53d37c4`, unchanged by this pass).
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- row #36 (in commit `53d37c4`, unchanged by this pass).
- `_bmad-output/implementation-artifacts/spec-dw-28-agents-md-commit-subject-forms.md` -- this spec, with this pass's triage log and result.

**Review findings:** 18 findings (the verification-gap layer found none, since this is docs only):
- **Patched:** 0.
- **Deferred:** 0 new. Three findings are carried rows of the existing retro-form deferral.
- **Rejected:** 15, each with its reason in the Review Triage Log above:
  - 7 `false`: the template fit of `53d37c4`, the temporary spec status, ledger ownership (two findings), the row #36 note, the closed-list wording, and the AC/checks.
  - 8 `low`: the "manual" wording (passage pinned byte-identical), the policy.toml link, revert and merge subjects, and carried rows for authorship, scopes, the AC, and the sweep suffix.

**Follow-up review recommended:** false. This was a follow-up pass with no `high` patched (patched counts: high 0, medium 0, low 0), so the work has converged.

**Verification:**
- `git diff <baseline> --stat` lists AGENTS.md, decision-log.md and this spec. The only other entry is `deferred-work.md`, the orchestrator's uncommitted ledger bookkeeping, which this run didn't touch.
- The decision-log diff removes 0 lines.
- The story-form passage appears exactly once in AGENTS.md.
- The leak scan of added lines in the reviewed files found nothing.

**Residual risks:** "A clear summary" is still a judgement call. The two forms for retro commits are still open as a deferred item. `deferred-work.md` is left uncommitted on purpose, because the orchestrator owns it.
