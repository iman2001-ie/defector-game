---
title: 'DW-62..DW-66: tighten AGENTS.md retro commit form and --import note wording across all copies'
type: 'chore'
created: '2026-10-10'
status: 'done'
baseline_revision: '272700394d216482599e8ac82f970ed746d7a037'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
warnings: []
deferred:
  - summary: >-
      The class_name trigger list covers `extends` and `@icon` edits but not adding or removing `@abstract` or `@tool` on a script that keeps its `class_name`, though the global class cache records those too.
    evidence: |-
      `game/.godot/global_script_class_cache.cfg` entries carry `base`, `class`, `icon`, `is_abstract`, `is_tool`, `language` and `path`, so toggling `@abstract`/`@tool` leaves the cache stale for headless `-s` runs. No game script uses either today, so it is rare. The fix edits AGENTS.md:30 (agent-context file) and its architecture copy.
    location: >-
      AGENTS.md:30; _bmad-output/game-architecture.md:1393-1395
    severity: low
  - summary: >-
      The CLI export block's import comment is called a "copy" of the AGENTS.md note (and AGENTS.md says to change all copies together), but it repeats only the first clause and points elsewhere for re-run rules, so what must stay in sync is unclear.
    evidence: |-
      game-architecture.md:1293-1295 says "Copy of the note in AGENTS.md ... see it or the headless CLI block ... for when to re-run"; game-architecture.md:1391-1392 calls it "another copy"; AGENTS.md:30 names it among "the copies". Calling it a short form/pointer in all three places removes the ambiguity. The fix edits AGENTS.md (agent-context file).
    location: >-
      AGENTS.md:30; _bmad-output/game-architecture.md:1293-1295, 1391-1392
    severity: low
  - summary: >-
      AGENTS.md section 5 now gives a form for bmad-loop/orchestration retro commits and for hand-written retro revisions, but not for a first retrospective a person writes by hand (previously covered by "retros").
    evidence: |-
      AGENTS.md:62 covers "retro commits made by bmad-loop or orchestration"; AGENTS.md:63 now says "hand-written retro revisions" where it used to say "retros". Wording such as "hand-written retros (first pass or revision)" closes the gap. The fix edits AGENTS.md (agent-context file).
    location: >-
      AGENTS.md:62-63
    severity: low
---

<intent-contract>

## Intent

**Problem:** AGENTS.md section 5 lists two retro commit forms (`chore(retro): ...` and `Epic 1 retro: revision 2`) without saying which applies when (DW-62). The `--import` note in AGENTS.md section 3 names only one architecture copy, while a third copy in the architecture's CLI export block still says "imports the WAVs Audio preloads" (DW-63); the note misses `extends`/`@icon` edits on a script that keeps its `class_name` (DW-64), "(only the `.import` sidecars are tracked)" reads as if the assets were untracked (DW-65), and "has no imported copy" is wrong for a changed asset whose old copy exists (DW-66).

**Approach:** Docs-only rewording. Section 5: bmad-loop/orchestration retro bookkeeping uses `chore(retro): ...`; manual (hand-written) retro revisions use a clear summary such as `Epic 1 retro: revision 2`. Section 3 note and the architecture headless CLI comment: add the `extends`/`@icon` trigger, say "no up-to-date imported copy", replace the sidecar parenthetical with "the assets and their `.import` sidecars are tracked; the imported copies are not", and make the source pointer name both architecture copies. Reword the CLI export block's import comment to match the note and point at the source.

## Boundaries & Constraints

**Always:** Keep all copies identical in substance. Keep the AGENTS.md entry a parenthetical between the two commands so "then:" still reads. Keep architecture text as `#` comment lines above the `--import` command. `<GODOT_DIR>` placeholders only.

**Never:** Change any command line (byte-identical). Edit the deferred-work ledger or sprint board. Touch other AGENTS.md sections/bullets or other architecture text. Change code, tests or data. Add machine-specific paths, emails or employer details.

</intent-contract>

## Code Map

- `AGENTS.md:30` -- the `--import` note (source); holds the "source for the copy in `game-architecture.md`'s headless CLI block, so change both together" pointer, the class_name trigger, "has no imported copy", and "(only the `.import` sidecars are tracked)".
- `AGENTS.md:62-63` -- section 5 bookkeeping (`chore(retro): epic 3 retrospective`) and manual non-story (`Epic 1 retro: revision 2`) bullets. git log confirms both forms: `chore(retro): epic N retrospective` (bmad-loop) and `Epic 1 retro: revision 2` (manual).
- `_bmad-output/game-architecture.md:1293` -- CLI export block step 1 comment: `# 1. Import (builds the class_name cache and imports the WAVs Audio preloads)` (stale third copy).
- `_bmad-output/game-architecture.md:1388-1395` -- headless CLI block comment copy; line 1389 says "change both together"; 1390-1391 class_name trigger; 1393-1394 imported-copy cause and sidecar parenthetical.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md:40` (#36) -- read-only: retros as manual non-story work; the clarification is consistent with it (tool-made retros were already bookkeeping), so no new decision row.

## Tasks & Acceptance

**Execution:**
- `AGENTS.md` -- line 30: pointer names both architecture copies (headless CLI block and CLI export block import step) and says change them together; class_name trigger adds "or changing the `extends` line or `@icon` of a script that keeps its `class_name`"; "no imported copy" -> "no up-to-date imported copy"; parenthetical -> "(the assets and their `.import` sidecars are tracked; the imported copies are not)". Lines 62-63: bookkeeping bullet says it covers retro commits made by bmad-loop or orchestration (e.g. `chore(retro): epic 3 retrospective`); manual bullet says manual retro revisions (hand-written, e.g. `Epic 1 retro: revision 2`) and correct-course -- DW-62..66.
- `_bmad-output/game-architecture.md` -- line 1293: reword to say it builds the class_name cache and imports the project's assets, pointing at AGENTS.md section 3 (the source) / the headless CLI block for re-run rules; lines 1388-1395: mirror the AGENTS.md changes (all copies pointer, extends/@icon trigger, up-to-date, sidecar wording), rewrapping comment lines -- DW-63..66.

**Acceptance Criteria:**
- Given AGENTS.md section 5, when an agent writes a retro commit, then the text states that bmad-loop/orchestration retro bookkeeping uses `chore(retro): ...` and manual retro revisions use a clear summary such as `Epic 1 retro: revision 2`.
- Given the repo, when grepping tracked files (excluding implementation artifacts and `_bmad/`) for `imports the WAVs` or `only the .import sidecars` / ``only the `.import` sidecars``, then there are no matches.
- Given AGENTS.md:30 and the architecture headless CLI comment, when compared, then both contain the extends/@icon trigger, "no up-to-date imported copy", the assets-and-sidecars-tracked wording, and a pointer naming every copy.
- Given the architecture CLI export block, when read, then its import comment says "imports the project's assets" and names AGENTS.md as the source.
- Given `git diff`, when inspected, then only `AGENTS.md`, `_bmad-output/game-architecture.md` and this spec change, and every command line is byte-identical.

## Spec Change Log

## Review Triage Log

### 2026-10-10 — Review pass
- verdicts: 17 findings — high 0, medium 0, low 8, false 9, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: extends/@icon trigger sits inside the "(including ...)" parenthetical that explains the declaration trigger — the parenthetical already lists script-level operations (renaming, moving a script) beyond the declaration itself, and the trigger is stated plainly, so no reader misses it.
  - `[low]` `[defer]` Blind: `@abstract`/`@tool` changes are also cached but not listed — confirmed in `game/.godot/global_script_class_cache.cfg` (`is_abstract`, `is_tool`); fix edits AGENTS.md, deferred.
  - `[low]` `[defer]` Blind: export block called a "copy" but holds only the first clause — real ambiguity for future editors; fix touches AGENTS.md wording, deferred.
  - `[low]` `[patch]` Blind: cross-references name sections inexactly ("under AI Tooling" vs heading `AI Tooling (MCP Servers)`) — patched game-architecture.md:1295 to name the exact heading; "Deployment Architecture" already matches its heading.
  - `[low]` `[defer]` Blind: first-pass hand-written retro fits neither section 5 bullet — real (line 63 narrowed "retros" to "hand-written retro revisions"); fix edits AGENTS.md, deferred.
  - `[low]` `[reject]` Blind: spec's `git diff --stat` check cannot list the untracked spec — fix edits this build's spec; checked with `git status --short` instead.
  - `[false]` `[reject]` Blind: AC grep scope wider than the verification command — repo-wide grep (verification-gap layer) also found no stale wording; fix would edit the spec.
  - `[false]` `[reject]` Blind: irrelevant `godot-testing.md` context entry — required by project persistent facts for every spec; fix edits the spec.
  - `[false]` `[reject]` Blind: nothing says how DW-62..66 get closed — the intent assigns resolution to the orchestrator.
  - `[false]` `[reject]` Blind: ledger line numbers are stale — the ledger is read-only by intent and the Code Map carries the correct lines.
  - `[false]` `[reject]` Blind: "the imported copies are not" repeats "gitignored" — the intent prescribes this exact contrast wording (DW-65); no defect.
  - `[low]` `[defer]` Edge: first-pass human retro not covered — same root cause as the Blind retro row; deferred with it.
  - `[low]` `[defer]` Edge: `@abstract`/`@tool` trigger missing — same root cause as the Blind cache row; deferred with it.
  - `[low]` `[defer]` Edge: export-block copy cannot be kept identical to the full note — same root cause as the Blind "copy" row; deferred with it.
  - `[false]` `[reject]` Intent: DW-62 leaves human-first-retro / loop-revision cases undefined — the human-first-retro case is the deferred row above; a bmad-loop revision is covered by line 62 ("retro commits made by bmad-loop or orchestration"), so no additional gap.
  - `[false]` `[reject]` Intent: export block is a short copy, not a full one — the intent says "reword ... to match", which the short form satisfies; the naming ambiguity is the deferred row.
  - `[false]` `[reject]` Intent: no command compares the copies for drift — the intent is docs-only wording; adding drift tooling is outside it.

## Verification

**Commands:**
- `git grep -n "imports the WAVs\|only the .import sidecars\|only the \`.import\` sidecars" -- AGENTS.md _bmad-output/game-architecture.md` -- expected: no output.
- `git diff --stat` -- expected: only AGENTS.md, _bmad-output/game-architecture.md and the spec.
- `git diff -U0 | grep '^[-+].*Godot_v4'` -- expected: no output (command lines untouched).

## Auto Run Result

Status: done

**Summary:** Docs-only rewording for DW-62..DW-66. AGENTS.md section 5 now says bmad-loop/orchestration retro commits use `chore(<scope>): ...` and hand-written retro revisions use a clear summary. The `--import` note in AGENTS.md section 3 and its headless CLI copy in the architecture now name every copy, add the `extends`/`@icon` trigger, say "no up-to-date imported copy", and state that assets and their `.import` sidecars are tracked while imported copies are not. The stale CLI export-block comment ("imports the WAVs Audio preloads") now says it imports the project's assets and points at the source.

**Files changed:**
- `AGENTS.md` -- section 3 import note (pointer, triggers, wording) and section 5 retro commit-form bullets.
- `_bmad-output/game-architecture.md` -- CLI export block import comment reworded; headless CLI block comment mirrors the AGENTS.md note.
- `_bmad-output/implementation-artifacts/spec-dw-62-dw-66-agents-md-import-and-commit-wording.md` -- this spec.

**Review findings:** 17 findings (0 high, 0 medium, 8 low, 9 false). 1 patch applied (exact heading name in the export-block cross-reference). 3 items deferred (`@abstract`/`@tool` trigger; export block called a "copy"; first-pass hand-written retro form), all because their fix edits AGENTS.md. Rejected: 9 false findings and 1 low spec-only finding, with reasons in the Review Triage Log.

**Follow-up review recommendation:** false (patched by verdict: 0 high, 0 medium, 1 low).

**Verification:** stale-wording grep over AGENTS.md and the architecture returned nothing; `git diff -U0 | grep '^[-+].*Godot_v4'` returned nothing (command lines unchanged); `git status --short` shows only AGENTS.md, the architecture and this spec. No code changed, so the GUT suite was not run.

**Residual risks:** the three deferred low items above.
