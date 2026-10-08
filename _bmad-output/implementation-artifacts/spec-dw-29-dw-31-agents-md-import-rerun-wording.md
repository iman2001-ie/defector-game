---
title: 'DW-29/DW-31: complete the --import re-run triggers and causes'
type: 'chore'
created: '2026-10-07'
status: 'done'
baseline_revision: 'e6dc781db5a48a7b5c1ee64e8c8c927f671bbade'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
warnings: []
deferred:
  - summary: >-
      The asset cause says new or changed assets have "no up-to-date `.import` artefact", but the `.import` sidecars are tracked in git; after a pull or branch switch, what is actually missing is the imported copy under the ignored `game/.godot/imported/`.
    evidence: |-
      `git ls-files '*.import'` lists 31 tracked sidecars, including every `game/assets/audio/sfx/*.wav.import`, and `game/.gitignore` ignores `.godot/`. The instruction (re-run `--import`) is still correct; only the stated cause is imprecise. The wording came from the bundle intent. The fix edits AGENTS.md (agent-context file), so it is deferred.
    location: >-
      AGENTS.md:30; _bmad-output/game-architecture.md:1339-1340
    severity: low
  - summary: >-
      Only the class_name symptom is named; a stale or missing asset import shows up as a preload or resource-load failure for an asset that exists, and nothing links that to the `--import` re-run.
    evidence: |-
      Both places list asset triggers and the asset cause, but the only symptom given is "a parse error naming a `class_name` that exists". `Audio` preloads WAVs, so a missing import fails at load, not parse. Raised by the blind and edge-case layers. The fix edits AGENTS.md (agent-context file), so it is deferred.
    location: >-
      AGENTS.md:30; _bmad-output/game-architecture.md:1341
    severity: low
  - summary: >-
      The trigger list names adding or changing imported assets but not renaming, moving or deleting them, although a moved asset's new path has no imported copy until `--import` runs.
    evidence: |-
      Imported copies in `game/.godot/imported/` are keyed by source path, so a moved WAV with its tracked sidecar has no imported copy at the new path. Only the generic "stale game/.godot/" clause covers it. The fix edits AGENTS.md (agent-context file), so it is deferred.
    location: >-
      AGENTS.md:30; _bmad-output/game-architecture.md:1338-1339
    severity: low
  - summary: >-
      The class_name triggers name adding, renaming, moving or deleting class_name *scripts*, but not adding, changing or removing a `class_name` declaration inside an existing script.
    evidence: |-
      Editing the `class_name` line in place changes the global class cache just like adding a new script, and headless `-s` runs don't rescan it. "Renaming class_name scripts" reads as a file rename. Raised by the intent-alignment layer. The fix edits AGENTS.md (agent-context file), so it is deferred.
    location: >-
      AGENTS.md:30; _bmad-output/game-architecture.md:1338
    severity: low
  - summary: >-
      The `--import` guidance is kept by hand in two places (AGENTS.md section 3 and the architecture's headless CLI block) with no cross-reference, so the copies can drift.
    evidence: |-
      DW-6/DW-12, DW-15/DW-16 and now DW-29/DW-31 each had to edit both copies in step. Neither marks the other as the source. This is pre-existing, not caused by this change.
    location: >-
      AGENTS.md:30; _bmad-output/game-architecture.md:1337-1341
    severity: low
  - summary: >-
      The opening clause says `--import` "imports the WAVs that `Audio` preloads", but the new triggers cover imported assets in general, and most tracked imports are not WAVs.
    evidence: |-
      `git ls-files '*.import'` lists 31 sidecars: 5 wav, 12 ttf, 9 png, 4 svg, 1 fnt. The clause predates this change (the diff kept it), and following the note still gives the right result. The fix edits AGENTS.md (agent-context file), so it is deferred.
    location: >-
      AGENTS.md:30; _bmad-output/game-architecture.md:1337
    severity: low
  - summary: >-
      The trigger "after pulling or switching to a branch that does either" asks the agent to inspect the incoming changes for class_name or asset edits before deciding whether to re-import.
    evidence: |-
      This clause was added by this change. Agents rarely inspect a pull's contents, so they may skip a needed re-import. "After any pull or branch switch" would be simpler, and re-importing costs little. The "stale game/.godot/" catch-all only partly covers it. The fix edits AGENTS.md (agent-context file), so it is deferred.
    location: >-
      AGENTS.md:30; _bmad-output/game-architecture.md:1339
    severity: low
---

<intent-contract>

## Intent

**Problem:** The `--import` note in AGENTS.md section 3 and the matching comment in the architecture's headless CLI loop name only *adding* `class_name` scripts or *new* imported assets as re-run triggers (DW-29). They give only one cause, the class cache, which does not explain the asset trigger (DW-31). Neither says what a stale cache looks like.

**Approach:** Reword both places so they list the full trigger set: adding, renaming, moving or deleting `class_name` scripts; adding or changing imported assets; pulling or switching to a branch that does either; a stale `game/.godot/`. Give both causes: headless `-s` runs don't rescan the class cache, and new or changed assets have no up-to-date `.import` artefact until `--import` runs. Name the typical symptom: a parse error naming a `class_name` that exists.

## Boundaries & Constraints

**Always:** Keep the two places consistent in meaning. Keep the AGENTS.md entry a parenthetical between the two commands, so the "then:" flow still reads. Use `<GODOT_DIR>` placeholders only.

**Never:** Change either command line (byte-identical). Edit the deferred-work ledger or the sprint board. Touch any other AGENTS.md section or other architecture text. Add machine-specific paths, emails or employer details.

</intent-contract>

## Code Map

- `AGENTS.md:30` -- the parenthetical after the `--import` command in section 3 "Tests"; the text to reword. Lines 29 and 31 are the commands (read-only).
- `_bmad-output/game-architecture.md:1336-1339` -- `#` comment lines above the `--import` command in the "AI Tooling (MCP Servers)" bash block; reword to match. Line 1340 (the command) is read-only.
- `_bmad-output/implementation-artifacts/spec-dw-15-dw-16-agents-md-import-and-commit-format.md` -- the prior build that wrote the current wording; read-only background.

## Tasks & Acceptance

**Execution:**
- `AGENTS.md` -- rewrite the line-30 parenthetical: what `--import` does; run on a fresh clone; re-run after the full trigger set; both causes; the symptom -- resolves DW-29 and DW-31 in the agent-context file.
- `_bmad-output/game-architecture.md` -- rewrite the comment lines above the `--import` command with the same triggers, causes and symptom, as `#` comments -- keeps the architecture consistent with AGENTS.md.

**Acceptance Criteria:**
- Given AGENTS.md section 3, when an agent reads the `--import` note, then it names renaming, moving and deleting `class_name` scripts, changing imported assets, and pulling or switching branches, as well as adding scripts/assets and a stale `game/.godot/`.
- Given either location, when read, then it gives both causes (class cache not rescanned by headless `-s` runs; no up-to-date `.import` artefact for new or changed assets until `--import` runs) and the symptom (parse error naming an existing `class_name`).
- Given the diff against the baseline, when command lines are compared, then every `Godot_v4` line is unchanged and only `AGENTS.md`, `game-architecture.md` and this spec changed.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 18 findings — high 0, medium 0, low 12, false 5, maybe-false 1
- findings:
  - `low` `defer` Blind: the asset cause names the `.import` sidecar, but sidecars are tracked; after a pull, the missing piece is `game/.godot/imported/`. — Verified with `git ls-files '*.import'` (31 tracked). The fix edits AGENTS.md (agent-context file): deferred.
  - `low` `defer` Blind: no asset-side symptom is given. — Real: a missing import fails at preload, not parse. Grouped with Edge rows 3 and 4. The fix edits AGENTS.md: deferred.
  - `false` `reject` Blind: the symptom doesn't fit renames or moves. — After a rename or move the class still exists at its new path and the stale cache points at the old one, so the error does name a `class_name` that exists. The symptom is labelled "typical", not exhaustive.
  - `low` `reject` Blind: quote the exact Godot error text. — Agents meet the generic phrase fine in practice, and the fix means adding version-specific strings that can only be checked by reproducing the errors. That is more than a direct correction.
  - `maybe-false` `reject` Blind: no fallback (delete `game/.godot/`) when a re-import leaves a stale entry. — Settling it needs a headless repro to show whether `--import` fully rebuilds `global_script_class_cache.cfg` after a delete. If true it would only be low, so it is rejected.
  - `low` `reject` Blind: the AGENTS.md parenthetical is one long sentence. — It still reads in order, and the spec keeps the parenthetical form. Restructuring it into bullets is more than a direct correction.
  - `low` `defer` Blind: the guidance is duplicated in two files with no cross-reference. — Real drift risk, but the duplication is pre-existing and not caused by this change: deferred.
  - `false` `reject` Blind: the colon in the architecture comment reads as a cut-off list. — A colon introducing the explanation is standard usage; the sentence that follows reads as the causes.
  - `low` `reject` Blind: the spec's greps don't check the pull trigger or the symptom. — The fix edits this build's spec. The diff was checked by hand: both files carry "pulling or switching" and the symptom.
  - `false` `reject` Blind: the spec's `context` lists an unrelated testing file. — The project's persistent facts require every spec to list `godot-testing.md`.
  - `false` `reject` Blind: the spec doesn't say how DW-29 and DW-31 get closed. — The intent says the orchestrator records resolution and forbids editing the ledger.
  - `low` `defer` Edge: AGENTS.md doesn't list renaming, moving or deleting imported assets. — Real: imported copies are keyed by path. Grouped with the next row. The fix edits AGENTS.md: deferred.
  - `low` `defer` Edge: the architecture comment has the same asset rename/move/delete gap. — Grouped with the row above: deferred.
  - `low` `defer` Edge: AGENTS.md doesn't name the asset-side (preload) symptom. — Grouped with Blind row 2: deferred.
  - `low` `defer` Edge: the architecture comment doesn't name the asset-side symptom. — Grouped with Blind row 2: deferred.
  - `low` `reject` Edge: rebase, merge, stash pop and file checkout aren't listed. — A pull includes merge or rebase, and the "whenever `game/.godot/` is stale" clause catches the rest. Rarely hit, and the fix adds clauses.
  - `false` `reject` Intent: the checks are string-level and no behaviour is verified. — This is a wording-only change with the commands byte-identical, so no runtime behaviour changed that could be tested.
  - `low` `defer` Intent: in-place `class_name` declaration edits aren't a named trigger. — Real: they change the class cache just like a new script. The fix edits AGENTS.md: deferred.

### 2026-10-07 — Review pass (follow-up)
- verdicts: 17 findings — high 0, medium 0, low 15, false 1, maybe-false 1
- findings:
  - `low` `defer` Blind: the asset cause names the `.import` sidecar, but sidecars are tracked; the missing piece is `game/.godot/imported/`. — carried: text unchanged since the first pass; already deferred.
  - `low` `defer` Blind: no asset-side symptom is given. — carried: still only the class_name symptom; already deferred.
  - `low` `defer` Blind: asset rename, move and delete are not triggers. — carried: the asset triggers still read "adding or changing"; already deferred.
  - `low` `defer` Blind: in-place `class_name` declaration edits are not a named trigger. — carried: already deferred.
  - `maybe-false` `reject` Blind: no fallback (delete `game/.godot/`) when `--import` does not fix it. — carried: settling it needs a headless repro of the cache rebuild after a delete; it would only be low.
  - `low` `reject` Blind: no note that `--import` creates `*.gd.uid` files that must be committed. — Pre-existing, not caused by this change, and not hit in practice: 175 tracked `.uid` files for 174 tracked `.gd` scripts, so agents already commit them. The fix adds a clause.
  - `low` `defer` Blind: the "imports the WAVs that `Audio` preloads" clause is narrower than the new general asset triggers. — Real: 26 of 31 tracked `.import` files are not WAVs. The clause predates this change. The fix edits AGENTS.md: deferred.
  - `low` `defer` Blind: the pull/branch trigger makes the agent inspect incoming changes before deciding to re-import. — Real and introduced by this change; "any pull or branch switch" is simpler. The fix edits AGENTS.md: deferred.
  - `low` `defer` Blind: the guidance is duplicated in two files with no cross-reference, and the phrasing differs. — carried: the duplication is pre-existing; already deferred.
  - `low` `reject` Blind: the AGENTS.md parenthetical is one long sentence. — carried: it still reads in order; restructuring is more than a direct correction.
  - `low` `reject` Blind: the exact Godot error text is not quoted. — carried: it needs repro-verified, version-specific strings.
  - `low` `defer` Edge: AGENTS.md does not list renaming, moving or deleting imported assets. — carried: already deferred.
  - `low` `defer` Edge: in-file `class_name` (or `extends`) edits are not a trigger. — carried: same claim as the in-place declaration row (the cache holds name and base together); already deferred.
  - `low` `defer` Edge: the architecture comment has the same trigger gaps. — carried: already deferred.
  - `low` `defer` Edge: only the class_name symptom is named; asset staleness fails differently. — carried: already deferred.
  - `false` `reject` Intent: the two copies differ in phrasing ("whenever"/"when", parenthetical/colon, backticks dropped in the bash comment). — The intent asks for consistency in meaning, and the auditor itself finds that the triggers, causes and symptom match in both.
  - `low` `defer` Intent: what a failed asset import looks like is left open. — carried: same as the asset-side symptom row; already deferred.

## Verification

**Commands:**
- `git diff e6dc781db5a48a7b5c1ee64e8c8c927f671bbade -- AGENTS.md _bmad-output/game-architecture.md | grep '^[-+].*Godot_v4'` -- expected: no output.
- `grep -n "renam" AGENTS.md _bmad-output/game-architecture.md` -- expected: one hit in each file, in the import note.
- `grep -n "\.import" AGENTS.md _bmad-output/game-architecture.md` -- expected: the `.import` artefact cause appears in each file.
- `git diff e6dc781db5a48a7b5c1ee64e8c8c927f671bbade --stat` -- expected: only `AGENTS.md`, `_bmad-output/game-architecture.md` and this spec.
- `git diff e6dc781db5a48a7b5c1ee64e8c8c927f671bbade | grep -nE "[A-Za-z]:[\\/]Users[\\/]|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"` -- expected: no matches.

## Auto Run Result

Status: done

**Summary:** Follow-up review pass on the DW-29/DW-31 wording change; no code changes. The `--import` note in AGENTS.md section 3 and the matching comment in the architecture's headless CLI block still read as the first pass left them:
- the full re-run trigger set (adding, renaming, moving or deleting `class_name` scripts; adding or changing imported assets; pulling or switching branches; a stale `game/.godot/`)
- both causes
- the class_name parse-error symptom

Both command lines are byte-identical to the baseline.

**Files changed (since baseline `e6dc781db5a48a7b5c1ee64e8c8c927f671bbade`):**
- `AGENTS.md`: section 3 `--import` parenthetical reworded (first pass).
- `_bmad-output/game-architecture.md`: the headless CLI import comment reworded to match (first pass).
- `_bmad-output/implementation-artifacts/spec-dw-29-dw-31-agents-md-import-rerun-wording.md`: this spec; this pass adds a triage log entry, 2 deferred items and this result.

**Review findings (this pass):** 17 findings (high 0, medium 0, low 15, false 1, maybe-false 1).
- **Patches:** none.
- **Newly deferred:** 2, both low:
  - the "imports the WAVs" clause is narrower than the asset triggers (pre-existing)
  - the pull/branch trigger asks agents to inspect incoming changes

  Both fixes edit AGENTS.md.
- **Carried:** 12 rows from the first pass, with their verdicts and routes unchanged (9 deferred, 3 rejected). They were not deferred a second time.
- **Rejected:**
  - the `.uid` follow-up note (low; pre-existing and not hit in practice: every tracked `.gd` has a tracked `.uid`)
  - the phrasing differences between the two copies (false; the intent asks for consistency in meaning)
  - carried: delete-`.godot` fallback (maybe-false), long sentence (low), exact error text (low)

**Follow-up review:** false. Follow-up pass, no `high` patched (patched: high 0, medium 0, low 0).

**Verification:**
- `git diff <baseline> -- AGENTS.md _bmad-output/game-architecture.md | grep '^[-+].*Godot_v4'`: no output, so the command lines are unchanged.
- `grep -n "renam"`: one hit in each file, in the import note.
- `.import` artefact cause: present in each file.
- `git diff <baseline> --stat`: the change set covers `AGENTS.md`, `game-architecture.md` and this spec. The uncommitted change to `deferred-work.md` is the orchestrator's own bookkeeping and was left untouched.
- Leak scan (drive-letter user paths, emails): no matches.
- Docs-only change, so GUT was not run.

**Residual risks:** the deferred items (5 from the first pass, 2 from this one), all low and all wording in AGENTS.md and the architecture. The deferred-work ledger was not edited.
