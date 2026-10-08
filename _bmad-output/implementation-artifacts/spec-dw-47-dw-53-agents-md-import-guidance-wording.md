---
title: 'DW-47..DW-53: tighten the --import re-run guidance and link its two copies'
type: 'chore'
created: '2026-10-08'
status: 'done'
baseline_revision: '7290d1eb8a8cfb6ecc05a98732c32ed718ae6be5'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
warnings: []
deferred:
  - summary: >-
      A third copy of the import description, in the CLI export block at `_bmad-output/game-architecture.md:1247`, still says "imports the WAVs Audio preloads", and AGENTS.md's "source for the copy" pointer names only the headless CLI block.
    evidence: |-
      Line 1247 reads `# 1. Import (builds the class_name cache and imports the WAVs Audio preloads)`. The bundle intent names only two copies, so this one predates the change and was left untouched. It can drift from AGENTS.md just like DW-51 described. A fix rewords line 1247 and widens the AGENTS.md pointer, which edits an agent-context file.
    location: >-
      _bmad-output/game-architecture.md:1247; AGENTS.md:30
    severity: low
  - summary: >-
      The class_name trigger covers adding, changing or removing the `class_name` declaration, but not changing the `extends` line or `@icon` of a script that keeps its `class_name`, though the global class cache stores the base type and icon too.
    evidence: |-
      Godot's `global_script_class_cache.cfg` records each class's base and icon alongside its name, so such an edit leaves the cache stale for headless `-s` runs. The "any pull" and "stale game/.godot/" clauses cover incoming changes but not a local edit read literally. The fix edits AGENTS.md (agent-context file).
    location: >-
      AGENTS.md:30; _bmad-output/game-architecture.md:1344-1345
    severity: low
  - summary: >-
      "(only the `.import` sidecars are tracked)" does not say what it contrasts with, so it can read as if the source assets were untracked.
    evidence: |-
      The intended contrast is tracked assets plus sidecars versus the ignored imported copies; wording such as "the assets and their `.import` sidecars are tracked; the imported copies are not" removes the ambiguity. The fix edits AGENTS.md (agent-context file).
    location: >-
      AGENTS.md:30; _bmad-output/game-architecture.md:1348
    severity: low
  - summary: >-
      The asset cause says an asset "has no imported copy" until `--import` runs, but for a changed (not new or moved) asset the imported copy exists and is out of date.
    evidence: |-
      Imported copies in `game/.godot/imported/` are keyed by source path, so a changed asset keeps its old copy. Wording such as "no up-to-date imported copy" covers both cases. The simplification comes from the bundle intent. The fix edits AGENTS.md (agent-context file).
    location: >-
      AGENTS.md:30; _bmad-output/game-architecture.md:1347
    severity: low
---

<intent-contract>

## Intent

**Problem:** The `--import` note in AGENTS.md section 3 and its copy in the architecture's headless CLI block misstate the asset cause (the `.import` sidecars are tracked; what is missing is the imported copy under the gitignored `game/.godot/imported/`), narrow `--import` to "the WAVs `Audio` preloads", miss in-place `class_name` edits and asset rename/move/delete as triggers, make the pull trigger conditional on inspecting the incoming changes, name only the class_name symptom, and carry no cross-reference so the copies drift (DW-47..DW-53).

**Approach:** Reword both copies with the same meaning: `--import` builds the class cache and imports the project's assets; triggers are adding, changing or removing a `class_name` declaration (including adding, renaming, moving or deleting a script that has one), adding, changing, renaming, moving or deleting an imported asset, any pull or branch switch, and a stale `game/.godot/`; causes are the unrescanned class cache and the missing imported copy in `game/.godot/imported/`; symptoms are a parse error naming an existing `class_name` or a preload/resource-load failure for an existing asset. AGENTS.md is marked as the source; the architecture comment points at it.

## Boundaries & Constraints

**Always:** Keep the AGENTS.md entry a parenthetical between the two commands so the "then:" flow still reads. Keep the architecture text as `#` comment lines above the `--import` command. Use `<GODOT_DIR>` placeholders only.

**Never:** Change either command line (byte-identical). Edit the deferred-work ledger or the sprint board. Touch any other AGENTS.md section or other architecture text. Add machine-specific paths, emails or employer details.

</intent-contract>

## Code Map

- `AGENTS.md:30` -- the parenthetical after the `--import` command in section 3 "Tests"; the text to reword. Lines 29 and 31 are the commands (read-only).
- `_bmad-output/game-architecture.md:1342-1346` -- `#` comment lines above the `--import` command in the "AI Tooling (MCP Servers)" bash block; reword to match and add the pointer to AGENTS.md. Line 1347 (the command) is read-only.
- Evidence: `git ls-files '*.import'` lists 36 tracked sidecars (10 wav, 12 ttf, 9 png, 4 svg, 1 fnt); `game/.gitignore` ignores `.godot/`.
- `_bmad-output/implementation-artifacts/spec-dw-29-dw-31-agents-md-import-rerun-wording.md` -- the prior build that wrote the current wording and deferred these items; read-only background.

## Tasks & Acceptance

**Execution:**
- `AGENTS.md` -- rewrite the line-30 parenthetical per the Design Notes golden example -- resolves DW-47..DW-53 in the source copy.
- `_bmad-output/game-architecture.md` -- rewrite the comment lines above the `--import` command per the golden example, including a line naming AGENTS.md section 3 as the source -- keeps the copy consistent and resolves DW-51.

**Acceptance Criteria:**
- Given either copy, when read, then `--import` is described as importing the project's assets (no "WAVs that `Audio` preloads" wording remains).
- Given either copy, when read, then the triggers include adding, changing or removing a `class_name` declaration; adding, changing, renaming, moving or deleting an imported asset; any pull or branch switch (unconditional); a stale `game/.godot/`; and a fresh clone.
- Given either copy, when read, then the asset cause names the missing imported copy in `game/.godot/imported/` (not a missing `.import` artefact), and both symptoms are named: a parse error naming an existing `class_name`, and a preload or resource-load failure for an existing asset.
- Given AGENTS.md, when read, then it states it is the source for the architecture copy; given the architecture comment, when read, then it points to AGENTS.md section 3.
- Given the diff against the baseline, when compared, then every `Godot_v4` line is unchanged and only `AGENTS.md`, `game-architecture.md` and this spec changed.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 20 findings — high 0, medium 0, low 16, false 4, maybe-false 0
- findings:
  - `low` `reject` Blind: the note doesn't say new `.import` sidecars written by `--import` must be committed. — Pre-existing and not met in practice: every tracked asset has a tracked sidecar. The fix adds a clause.
  - `low` `defer` Blind: changing `extends` or `@icon` of a `class_name` script is not a named trigger. — Real: the class cache stores base and icon. Grouped with Edge row 4. The fix edits AGENTS.md: deferred.
  - `low` `reject` Blind: the "change both together" clause is buried mid-parenthetical. — The pointer is present in both copies and leads the architecture comment; moving it is restructuring, not a direct correction.
  - `low` `reject` Blind: the AGENTS.md parenthetical is one long sentence with nested parentheses. — It still reads in order and the spec keeps the parenthetical form; restructuring into bullets is more than a direct correction.
  - `false` `reject` Blind: the unconditional pull trigger makes the other triggers redundant. — Local edits involve no pull, so the class_name and asset triggers are still needed for them.
  - `false` `reject` Blind: the spec has no step that closes DW-47..DW-53. — The intent says the orchestrator records resolution and forbids editing the ledger.
  - `low` `reject` Blind: the spec's verification relies on fixed line numbers. — The fix edits this build's spec.
  - `low` `reject` Blind: the spec's sidecar counts (36) differ from the ledger's (31) with no snapshot note. — The fix edits this build's spec; 36 is the current count.
  - `false` `reject` Blind: empty Spec Change Log / Review Triage Log conflict with `in-review`. — The review pass fills the triage log (this entry); the change log stays empty without a bad_spec loopback.
  - `low` `patch` Blind: the architecture pointer says "AGENTS.md section 3 (Tests)" but section 3 is "Project facts". — Fixed: the pointer now reads "AGENTS.md section 3 (Project facts), Tests bullet".
  - `low` `defer` Edge: a third copy at `game-architecture.md:1247` still says "imports the WAVs Audio preloads". — Real, pre-existing, outside the two copies the intent names. Grouped with Edge row 2 and Intent row 1: deferred.
  - `low` `defer` Edge: "source for the copy" implies one copy; the export-block copy is unlinked. — Same root cause as the third-copy row: deferred.
  - `low` `reject` Edge: editing a `.import` sidecar locally is not a trigger. — Import settings are changed in the editor, which reimports itself; rare in everyday use, and the fix adds a clause.
  - `low` `defer` Edge: an `extends`/`@icon` change on a `class_name` script is not a trigger. — Grouped with Blind row 2: deferred.
  - `low` `reject` Edge: a deleted `game/.godot/` in an existing clone may not read as covered. — A missing cache reads plainly as stale, and "with no `game/.godot/`" names the state; unlikely to mislead.
  - `low` `defer` Edge: "(only the `.import` sidecars are tracked)" lacks its contrast and can read as assets untracked. — Real wording ambiguity; the fix edits AGENTS.md: deferred.
  - `low` `defer` Intent: a third copy of the old clause remains at `game-architecture.md:1247`. — Grouped with Edge row 1: deferred.
  - `false` `reject` Intent: the drift guard is prose only, with no mechanical check. — The intent asks for a cross-reference, which both copies now carry.
  - `low` `defer` Intent: for a changed asset the imported copy is outdated, not missing. — Real simplification shared with the intent; the fix edits AGENTS.md: deferred.
  - `low` `reject` Intent: the spec's evidence counts differ from the ledger's. — The fix edits this build's spec; the spec's count is the current one.

### 2026-10-08 — Review pass
- verdicts: 23 findings — high 0, medium 0, low 18, false 5, maybe-false 0
- findings:
  - `low` `defer` Blind: a third copy at `game-architecture.md:1247` still says "imports the WAVs Audio preloads", and the AGENTS.md pointer names only one copy. — carried: line 1247 is unchanged; already in `deferred`.
  - `low` `defer` Blind: "no imported copy" is wrong for a changed asset, whose copy is outdated. — carried: the wording is unchanged; already in `deferred`.
  - `low` `defer` Blind: "(only the `.import` sidecars are tracked)" can read as if the source assets were untracked. — carried: the wording is unchanged; already in `deferred`.
  - `low` `reject` Blind: nothing says to commit new `.import` sidecars. — carried: not met in practice, since every tracked asset has a tracked sidecar; the fix adds a clause.
  - `low` `reject` Blind: merge, rebase, reset, stash pop and cherry-pick are not named triggers. — Rare in this repo's linear workflow; the "whenever `game/.godot/` is stale" catch-all covers them; the fix adds a clause to an agent-context file.
  - `low` `defer` Blind: an `extends`/`@icon` change on a `class_name` script is not a trigger. — carried: the wording is unchanged; already in `deferred`.
  - `low` `reject` Blind: the symptoms don't cover a stale cache entry (an old name or path that still resolves). — The list says "Typical symptoms", not all symptoms, and the trigger list already requires the re-run after a rename, move or delete; the fix adds a clause.
  - `low` `reject` Blind: the note doesn't say `--import` is safe to run every time. — Not a defect: the triggers are already broad, and the loop's verify command imports unconditionally; the fix adds new guidance.
  - `false` `reject` Blind: the AGENTS.md pointer omits `_bmad-output/`, so the file is hard to find. — `git ls-files` lists exactly one `game-architecture.md`, and AGENTS.md section 4 (line 41) maps it under `_bmad-output/`.
  - `low` `reject` Blind: the "section 3" pointer breaks if AGENTS.md is renumbered. — Hypothetical; the pointer also names the section title "Project facts" and the Tests bullet. Fixing it means restructuring, not a direct correction.
  - `low` `reject` Blind: the AGENTS.md parenthetical is one long sentence with nested parentheses. — carried: it still reads in order, and the spec keeps the parenthetical form.
  - `low` `reject` Blind: the spec's `--stat` check fails on the working tree because `deferred-work.md` is modified. — The fix edits this build's spec; the ledger edit is the orchestrator's uncommitted bookkeeping, and HEAD `1a520b4` touches only the three spec files.
  - `low` `reject` Blind: the spec's verification relies on fixed line numbers. — carried: the fix edits this build's spec.
  - `low` `reject` Blind: the spec's `context` list includes `godot-testing.md` and omits AGENTS.md. — The fix edits this build's spec; the testing file is required by project facts.
  - `false` `reject` Blind: `followup_review_recommended: false` is inconsistent with open deferred items. — The recommendation counts patched entries only (1 low on the first pass), so `false` is the correct result by rule.
  - `low` `reject` Edge: merge, rebase, cherry-pick, stash pop and reset are not named triggers. — Same claim as the Blind merge/rebase row: rare here, covered by the stale catch-all, and the fix adds a clause.
  - `low` `reject` Edge: a new worktree with no `game/.godot/` is not a clone. — carried (same claim as the earlier "deleted `game/.godot/`" row): a missing cache reads plainly as stale, and "with no `game/.godot/`" names the state.
  - `low` `reject` Edge: the spec's file-scope claim conflicts with the modified `deferred-work.md`. — The fix edits this build's spec; the ledger edit is the orchestrator's, and the committed change set is the three files.
  - `low` `defer` Intent: a third copy at `game-architecture.md:1247` keeps the WAVs wording. — carried: line 1247 is unchanged; already in `deferred`.
  - `low` `defer` Intent: the changed asset is outdated, not missing, and `extends`/`@icon` edits are not covered. — carried: both items are unchanged and already in `deferred`.
  - `false` `reject` Intent: the drift guard is prose only, with no mechanical check. — carried: the intent asks for a cross-reference, and both copies carry one.
  - `false` `reject` Intent: the grep checks test phrases, not whether the two copies mean the same. — Read side by side in the diff, the two copies state the same description, triggers, causes and symptoms clause for clause.
  - `false` `reject` Intent: uncommitted working-tree ledger edits may belong to this change. — `git show --stat 1a520b4` lists only AGENTS.md, `game-architecture.md` and the spec; the ledger edits are the orchestrator's `resolution:` bookkeeping.

## Design Notes

Golden wording (meaning must match; minor phrasing may differ):

AGENTS.md: `(builds the class_name cache and imports the project's assets; this note is the source for the copy in game-architecture.md's headless CLI block, so change both together. Run it on a fresh clone with no game/.godot/, and re-run it after adding, changing or removing a class_name declaration (including adding, renaming, moving or deleting a script that has one), after adding, changing, renaming, moving or deleting an imported asset, after any pull or branch switch, or whenever game/.godot/ is stale, because headless -s runs don't rescan the class cache, and an asset has no imported copy in the gitignored game/.godot/imported/ until --import runs (only the .import sidecars are tracked). Typical symptoms: a parse error naming a class_name that exists, or a preload or resource-load failure for an asset that exists), then:` -- with backticks around code terms as in the current text.

## Verification

**Commands:**
- `git diff 7290d1eb8a8cfb6ecc05a98732c32ed718ae6be5 -- AGENTS.md _bmad-output/game-architecture.md | grep '^[-+].*Godot_v4'` -- expected: no output.
- `sed -n 30p AGENTS.md | grep -c WAVs; sed -n 1340,1352p _bmad-output/game-architecture.md | grep -c WAVs` -- expected: 0 and 0 (the import note only; other architecture text is out of scope).
- `grep -n "godot/imported" AGENTS.md _bmad-output/game-architecture.md` -- expected: one hit in each file, in the import note.
- `grep -n "resource-load" AGENTS.md _bmad-output/game-architecture.md` -- expected: one hit in each file.
- `grep -n "any pull or branch switch" AGENTS.md _bmad-output/game-architecture.md` -- expected: one hit in each file.
- `git diff 7290d1eb8a8cfb6ecc05a98732c32ed718ae6be5 --stat` -- expected: only `AGENTS.md`, `_bmad-output/game-architecture.md` and this spec.
- `git diff 7290d1eb8a8cfb6ecc05a98732c32ed718ae6be5 | grep -nE "[A-Za-z]:[\\/]Users[\\/]|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"` -- expected: no matches.

## Auto Run Result

Status: done

**Summary:** Follow-up review pass on the committed DW-47..DW-53 change (`1a520b4f6f7075adacb1c5645522d212509487cc`). The change rewords the `--import` note in AGENTS.md section 3 and its copy in the architecture's headless CLI block: `--import` imports the project's assets; the triggers include in-place `class_name` declaration edits, asset rename/move/delete and any pull or branch switch; the asset cause is the missing imported copy in `game/.godot/imported/`; both symptoms are named; and the copies cross-reference each other. No code changes were needed in this pass.

**Files changed (since baseline `7290d1eb8a8cfb6ecc05a98732c32ed718ae6be5`):**
- `AGENTS.md`: section 3 `--import` parenthetical reworded, with the source marker.
- `_bmad-output/game-architecture.md`: the headless CLI import comment reworded to match, with the pointer to AGENTS.md.
- `_bmad-output/implementation-artifacts/spec-dw-47-dw-53-agents-md-import-guidance-wording.md`: this spec (this pass adds a triage-log entry and this result).

**Review findings (follow-up pass):** 23 (high 0, medium 0, low 18, false 5, maybe-false 0). The verification-gap layer found nothing.
- **Patched:** none.
- **Deferred:** no new items. 6 rows carried onto the 4 existing `deferred` items: the third copy at line 1247, the `extends`/`@icon` trigger, the sidecar-contrast wording, and outdated vs missing imported copy.
- **Rejected:**
  - git operations other than pull or switch, from both the blind and edge layers (low; rare here, covered by the stale catch-all, adds a clause)
  - stale-cache symptoms (low; the list says "typical")
  - "safe to always run" note (low; new guidance, not a defect)
  - pointer missing the `_bmad-output/` path (false; the filename is unique and section 4 maps it)
  - section-number fragility (low; hypothetical)
  - worktree with no `game/.godot/` (low; carried)
  - sidecar-commit note and long sentence (low; carried)
  - spec-only fixes: the `--stat` check with the ledger in the working tree, fixed line numbers, the `context` list, and the file-scope claim (low; each fix edits this spec)
  - recommendation flag (false; correct by rule)
  - prose-only drift guard (false; carried)
  - copies may differ in meaning (false; they match clause for clause)
  - ledger edits belong to this change (false; HEAD touches only the three files)

**Follow-up review:** false. This is a follow-up pass, and it patched high 0, medium 0, low 0, so the work has converged.

**Verification:**
- No `Godot_v4` line differs from the baseline.
- No "WAVs" in either import note.
- `godot/imported`, `resource-load` and `any pull or branch switch` each appear once in each file.
- The committed change set is the three files above.
- Leak scan (drive-letter user paths, emails): no matches.
- Docs-only change, so GUT was not run.

**Residual risks:**
- The 4 existing deferred low wording items, now DW-63..DW-66 in the ledger.
- The working tree still holds the orchestrator's uncommitted `deferred-work.md` edits (DW-47..DW-53 `resolution:` lines, new DW-63+ entries). Per the run instructions, this pass did not touch, commit or revert them.

