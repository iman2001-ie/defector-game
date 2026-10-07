---
title: 'DW-6/DW-12: document the one-time --import step before the GUT command'
type: 'chore'
created: '2026-10-07'
status: 'done'
baseline_revision: '9197010c69e540184157a65ce8c7540a268c3faa'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
warnings: []
deferred:
  - summary: >-
      The new docs call the --import step "one-time", but an existing checkout also needs it re-run after adding class_name scripts or new imported assets (or when game/.godot/ is stale).
    evidence: |-
      Stories 1.2-1.5 each re-ran --import to refresh the class cache for new class_name types (Player, Projectile, Enemy, Missile). Headless -s runs do not rescan the class cache. The fix rewords AGENTS.md (agent-context file), so it is deferred.
    location: >-
      AGENTS.md:29-30; _bmad-output/game-architecture.md:1232
    severity: medium
  - summary: >-
      The architecture's CLI export command has the same fresh-clone gap: it runs --export-release without a prior --import.
    evidence: |-
      Story 1.7 had to run --import before --export-release. Pre-existing; the bundle intent covers only the test command.
    location: >-
      _bmad-output/game-architecture.md:1141
    severity: low
  - summary: >-
      The godot-testing.md knowledge files show GUT commands with no --path and no import step, so agents reading them still get the failing fresh-clone procedure.
    evidence: |-
      .claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md (and its .agents/skills copy) are untouched by this change; pre-existing agent-context files outside the intent's two named locations.
    location: >-
      .claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md
    severity: low
---

<intent-contract>

## Intent

**Problem:** A fresh clone (no `game/.godot/`) cannot run the GUT suite: `Audio`'s WAV preloads fail and no `class_name` types are registered until the project has been imported once. Neither AGENTS.md nor the architecture's test command mentions this (DW-6, DW-12).

**Approach:** In AGENTS.md section 3 and in the architecture's "Run all GUT tests headless" block, add the one-time `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` command before the existing GUT command, with a one-line note explaining why (builds the `class_name` cache and imports the WAVs that `Audio` preloads).

## Boundaries & Constraints

**Always:** Use only the `<GODOT_DIR>` placeholder. Keep the existing GUT command text byte-identical. Keep the note to one line. Match each file's existing formatting (inline-code bullet in AGENTS.md, bash comment + command in the architecture fenced block).

**Never:** Real local paths, usernames or machine details. No edits to `deferred-work.md`, `sprint-status.yaml`, CLAUDE.md, game code or tests. No other architecture or AGENTS.md content changes.

</intent-contract>

## Code Map

- `AGENTS.md:28-29` -- section 3 "Tests:" bullet; GUT command is the inline-code line 29. Insert the import step before it.
- `_bmad-output/game-architecture.md:1231-1233` -- "AI Tooling" headless CLI loop fenced `bash` block; `# Run all GUT tests headless` comment + command at 1232-1233. Insert a `# One-time import ...` comment + command above it.
- `game/autoloads/audio.gd` -- read-only evidence: preloads the five WAVs that need import.
- `_bmad-output/game-architecture.md:1141` -- read-only: existing `--headless --path game` command style to mirror.

## Tasks & Acceptance

**Execution:**
- `AGENTS.md` -- in the section 3 Tests bullet, add the `--import` command (inline code) before the GUT command with a one-line why-note -- so agents on a fresh clone import first.
- `_bmad-output/game-architecture.md` -- add `# One-time, on a fresh clone: import the project (builds the class_name cache and imports the WAVs Audio preloads)` plus the `--import` command before `# Run all GUT tests headless` -- keeps the architecture's CLI loop consistent with AGENTS.md.

**Acceptance Criteria:**
- Given AGENTS.md section 3, when read top to bottom, then the `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` command appears before the unchanged GUT command, with a one-line note naming the `class_name` cache and the `Audio` preloads.
- Given the architecture's headless CLI loop block, when read, then the same `--import` command with a one-line comment appears before `# Run all GUT tests headless`, and the GUT command is unchanged.
- Given the full diff, when scanned, then it touches only those two files and contains no absolute path, username or machine detail.
- Given a clean `git archive HEAD` copy with no `game/.godot/`, when the import command then the GUT command are run, then the suite passes.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 16 findings — high 0, medium 4, low 7, false 4, maybe-false 1
- findings:
  - `medium` `reject` (blind) The spec's Verification scan pattern spelled out an employer-identifying token in a tracked file — fix edits this build's spec, so rejected as a review route; the token was nonetheless removed before commit for AGENTS.md section 1 compliance.
  - `low` `reject` (blind) The scan used plain `git diff`, which skips the untracked spec — fix edits this build's spec; the pre-commit scan ran on the staged diff instead.
  - `medium` `defer` (blind) "One-time" is wrong: re-import is needed after adding class_name scripts or assets — confirmed by Stories 1.2-1.5 re-running --import; fix edits AGENTS.md (agent-context), deferred.
  - `low` `reject` (blind) Naming the Audio WAVs will go stale as more imported assets arrive — the intent mandates naming the class_name cache and Audio preloads; wording change adds no everyday value.
  - `low` `defer` (blind) The architecture export command (line 1141) has the same fresh-clone gap — pre-existing, outside the intent's test-command scope.
  - `low` `reject` (blind) No expected result stated for the import command — cosmetic; a non-zero exit is already self-evident and the fix adds content for little gain.
  - `low` `reject` (blind) Spec AC "touches only those two files" vs Verification "plus this spec" — fix edits this build's spec.
  - `false` `reject` (blind) No evidence the fresh-clone check ran — the check ran twice (implementer and orchestrator): clean git-archive copy, import exit 0, GUT 274/274 passed; recorded under Auto Run Result.
  - `low` `defer` (blind) godot-testing.md knowledge file still shows GUT commands without --path or the import step — pre-existing agent-context file, deferred.
  - `false` `reject` (blind) Nothing closes DW-6/DW-12 — the intent states the orchestrator records resolution; not editing the ledger is required.
  - `medium` `defer` (edge) AGENTS.md note says import is one-time; a new class_name or WAV then breaks GUT — same root cause as the "one-time" entry, deferred with it.
  - `medium` `defer` (edge) Architecture comment says one-time; headless -s runs do not rescan the class cache — same root cause, deferred with it.
  - `maybe-false` `defer` (edge) Gating on a missing game/.godot/ skips a needed re-import when the cache is partial or stale — would be settled by interrupting an import and running GUT; grouped with the medium "one-time" entry.
  - `false` `reject` (intent) R2 runtime evidence not recorded in the diff — the fresh-clone run was performed and passed (274/274); evidence lives in this spec's Auto Run Result.
  - `low` `defer` (intent) Other copies of the GUT command (godot-testing.md in .claude and .agents skills) not updated — same root cause as the godot-testing.md entry, deferred with it.
  - `false` `reject` (intent) Artifact-only receipt does not apply — an observation, not a defect; no receipt is asserted.

### 2026-10-07 — Review pass
- verdicts: 20 findings — high 0, medium 4, low 11, false 3, maybe-false 2
- findings:
  - `medium` `defer` (blind) "One-time" wording is wrong; re-import is needed after new class_name scripts or assets — carried: same claim as the logged medium defer, AGENTS.md:29-30 and architecture:1232 still say "one-time"; already deferred (DW-16), not re-deferred.
  - `low` `reject` (blind) Triage-log rejections cite an Auto Run Result section that the working copy no longer has — the fix edits this build's spec; this pass re-ran the fresh-clone check (import exit 0, GUT 274/274, exit 0) and records it under a new Auto Run Result.
  - `low` `reject` (blind) AC "touches only those two files" contradicts Verification "plus this spec" — carried: same row as the logged reject; fix edits this build's spec.
  - `low` `reject` (blind) The Verification secrets-scan regex misses emails, hostnames and tokens — the fix edits this build's spec; the pre-commit scan of the staged diff for this pass covered emails and LOCAL.md values directly.
  - `low` `defer` (blind) The architecture export command (line 1141) has the same fresh-clone gap — carried: same row as the logged defer (DW-17); not re-deferred.
  - `false` `reject` (blind) The three deferred items have no ledger entries, so the next sweep will miss them — the working-tree deferred-work.md already holds them as DW-16, DW-17 and DW-18 (orchestrator bookkeeping).
  - `low` `reject` (blind) Spec line references mix pre-change and post-change numbers — the fix edits this build's spec.
  - `low` `reject` (blind) No expected result stated for the import command — carried: same row as the logged cosmetic reject.
  - `maybe-false` `defer` (blind) Gating on a missing game/.godot/ skips a needed re-import when the cache is stale or partial — carried: same row as the logged maybe-false, grouped with the "one-time" entry (DW-16).
  - `low` `reject` (blind) Naming only the Audio WAVs will go stale — carried: same row as the logged reject; the intent mandates naming them.
  - `medium` `defer` (edge) AGENTS.md note says one-time; a new class_name or asset then breaks GUT — carried: same row as the logged defer (DW-16).
  - `medium` `defer` (edge) Architecture comment limits import to fresh clones; headless -s does not rescan the class cache — carried: same row as the logged defer (DW-16).
  - `maybe-false` `defer` (edge) A partial or interrupted game/.godot/ cache is not covered by the trigger — carried: same row as the logged maybe-false (DW-16).
  - `low` `defer` (edge) The CLI export block has no prior --import — carried: same row as the logged defer (DW-17).
  - `low` `reject` (edge) Claim check: the AC says two files but the diff touches three (the spec) — carried: same as the logged AC-vs-Verification reject; fix edits this build's spec.
  - `false` `reject` (intent) R2 runtime evidence is not shown — this pass re-ran it in a clean git-archive HEAD copy with no game/.godot/: import exit 0, GUT 24 scripts, 274/274 passing, exit 0.
  - `medium` `defer` (intent) "One-time" matches the intent's words but not the real re-import conditions — carried: same root cause as the logged defer (DW-16).
  - `low` `defer` (intent) godot-testing.md copies still show the GUT command without --path or the import step — carried: same row as the logged defer (DW-18).
  - `low` `reject` (intent) Spec's AC and Verification disagree on file scope — carried: same as the logged reject; fix edits this build's spec.
  - `false` `reject` (intent) deferred-work.md has an uncommitted change despite the "no edits" rule — that change is the orchestrator's ledger bookkeeping (DW-6/DW-12 resolution, DW-16..18), not part of this build's diff; the build did not touch it.

## Verification

**Commands:**
- `git diff --stat` -- expected: only `AGENTS.md` and `_bmad-output/game-architecture.md` (plus this spec) changed.
- `git diff --cached | grep -iE '[A-Z]:[\/]|/Users/'` (and a scan for the values in the gitignored `LOCAL.md`) -- expected: no output.
- In a scratch `git archive` copy: run the `--import` command, then the GUT command -- expected: all tests pass.

## Auto Run Result

Status: done (follow-up review pass)

**Summary:** Documented the `--import` step a fresh clone needs before the GUT suite can run (DW-6, DW-12). The `--headless --path game --import` command now comes before the unchanged GUT command in AGENTS.md section 3 and in the architecture's headless CLI loop, with a one-line note naming the `class_name` cache and the `Audio` WAV preloads. Only the `<GODOT_DIR>` placeholder is used. This follow-up pass changed no code or docs.

**Files changed (since baseline):**
- `AGENTS.md` -- section 3 Tests bullet: the import command and a one-line why-note, placed before the GUT command.
- `_bmad-output/game-architecture.md` -- headless CLI loop block: a comment and the import command, placed before `# Run all GUT tests headless`.
- `_bmad-output/implementation-artifacts/spec-dw-6-dw-12-gut-import-step-docs.md` -- this spec (follow-up triage log and this result).

**Review findings (follow-up pass):** 20 total. Patches applied: 0. New deferred items: 0 (the 9 defer rows are all carried from the first pass and already in the ledger as DW-16, DW-17 and DW-18). Rejected: 11, each with its reason in the Review Triage Log: 6 low findings whose fix would edit this build's spec, 2 carried cosmetic rejects, and 3 false findings (missing ledger entries, missing runtime evidence, the ledger diff).

**Follow-up review recommended:** false (patched entries: high 0, medium 0, low 0).

**Verification:**
- `git diff 9197010 --stat`: only `AGENTS.md`, `game-architecture.md` and this spec, plus the orchestrator's `deferred-work.md` change (not part of this build).
- Fresh clone: in a `git archive HEAD` copy with no `game/.godot/`, `--import` exited 0. GUT then reported 24 scripts, 274/274 tests passing, exit 0.
- Sensitive-content scan of the staged diff (absolute paths, usernames, `LOCAL.md` values, email addresses, employer details): no matches.

**Residual risks:** The docs still call the import "one-time", but adding a new `class_name` script or asset also needs a re-import (DW-16). The working copy still holds the orchestrator's uncommitted `deferred-work.md` edits. This run left them alone on purpose, as the invocation requires.

