---
title: 'DW-46: injectable user args and change-scene seam in Level'
type: 'chore'
created: '2026-10-08'
status: 'done'
baseline_revision: '585053ccc2284f5f2bf9ff4004f8e2cfa36a6e76'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** `Level._ready` (`game/scenes/level/level.gd:27`) parses `OS.get_cmdline_user_args()` directly and redirects with `get_tree().change_scene_to_file.call_deferred(...)`, so the `--stress`/`--bench` redirect to the sandbox and the `--no-prewarm` skip are untested: `test_level.gd` only checks the static helpers with hand-built dictionaries, so breaking the args wiring in `_ready` leaves the suite green (DW-46, the DW-27 gap in a third script).

**Approach:** Follow the DW-27 seam used by `DebugTools`/`Sandbox`: add a `user_args: PackedStringArray` field defaulting to `OS.get_cmdline_user_args()`, and a `change_scene: Callable` that `_ready` defaults to `get_tree().change_scene_to_file` when not injected (as `DebugTools.restart_scene` does). `_ready` parses `user_args` and redirects through `change_scene` (still deferred). Add GUT tests that drive `_ready` through these seams and observe outer surfaces.

## Boundaries & Constraints

**Always:** statically typed GDScript; logging via `Log`; real runs behave exactly as before (default args are the OS args, default callable is the tree's `change_scene_to_file`, the redirect stays deferred and returns before any level setup); tests set the seams before `add_child` and restore global state they touch (`Log.sink`, `GameState`, `Feedback`, `PauseArbiter`).

**Never:** call the real `change_scene_to_file` from a test (it would replace the GUT runner's scene); change `DebugArgs` parsing or the static helpers `should_redirect_to_stress`/`should_prewarm`; route the redirect through `SceneRouter` (its doc names the `--stress` redirect as a debug-only exception, and `SceneRouter._change_to` clears pause/feedback state); edit the deferred-work ledger.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Stress redirect | `user_args = ["--stress"]`, recorder injected as `change_scene` | after one frame the recorder got exactly `[Level.SANDBOX_SCENE_PATH]`; no `level_started`; log line `switching to the sandbox stress scene` | none |
| Bench redirect | `user_args = ["--bench=1"]` | same as stress redirect | none |
| No args | `user_args = []`, recorder injected | recorder never called (after a frame); `level_started` emitted once; one prewarm explosion per tier at `Feedback.PREWARM_POSITION` in `World/Effects`; no skip line | none |
| No prewarm | `user_args = ["--no-prewarm"]`, recorder injected | level starts (`level_started` once), no prewarm explosion, one `Feedback pre-warm skipped` log line, recorder not called | none |
| Default callable | nothing injected, `user_args = []` | after `_ready`, `change_scene` targets the scene tree's `change_scene_to_file` (checked by object and method, never called) | none |

</intent-contract>

## Code Map

- `game/scenes/level/level.gd` -- `_ready` line 27 parses OS args; lines 28-31 redirect via `get_tree().change_scene_to_file.call_deferred(SANDBOX_SCENE_PATH)`; lines 49-52 gate `Feedback.prewarm()` with `should_prewarm(OS.is_debug_build(), args)` and log the skip. Exported `level_id` at line 19 -- add the two seam fields after it with "tests set before add_child" doc comments, and update the header comment (lines 11-13) if it mentions the OS args.
- `game/ui/debug/debug_tools.gd:25-35,70-74` -- reference seam: `restart_scene: Callable` defaulted in `_ready` when `not is_valid()`, `user_args` field defaulting to the OS args.
- `game/scenes/sandbox/sandbox.gd:32-34` -- same `user_args` doc wording to mirror.
- `game/autoloads/scene_router.gd:16-27` -- `change_scene` Callable + `default_change_scene()` pattern; `test_scene_router.gd:50-64` shows how to assert the default callable by method name without calling it.
- `game/tests/unit/test_level.gd` -- `_make_level` (line 73) instantiates and `add_child_autofree`s; `_record_scene` (line 63) is a ready recorder into `_scene_calls` (cleared in `before_each`); `_started` collects `level_started`; `_capture`/`_lines` capture logs (set `Log.sink = _capture` before add_child, `after_each` clears it); `LEVEL_SCRIPT` const is used by the static-helper tests at lines 615-632.
- `game/tests/unit/test_sandbox.gd:384-418` -- `_prewarm_explosions()` / `_lines_containing()` helpers and the no-prewarm/default tests to mirror for the level.
- `game/autoloads/feedback.gd:10,110` -- `PREWARM_POSITION`; `prewarm()` spawns one explosion per tier (`ImpactTier.NAMES.size()`) through the registered spawner into `World/Effects`.

## Tasks & Acceptance

**Execution:**
- `game/scenes/level/level.gd` -- add `var user_args: PackedStringArray = OS.get_cmdline_user_args()` and `var change_scene: Callable`; in `_ready` default `change_scene` to `get_tree().change_scene_to_file` when invalid, parse `user_args`, and redirect with `change_scene.call_deferred(SANDBOX_SCENE_PATH)` -- the DW-46 seam.
- `game/tests/unit/test_level.gd` -- add a helper that instantiates the level, sets `user_args` and (optionally) `change_scene = _record_scene`, captures logs during `add_child_autofree`; add one test per I/O matrix row (await `get_tree().process_frame` before asserting recorder calls, since the redirect is deferred). Add `_prewarm_explosions`/`_lines_containing` helpers like `test_sandbox.gd`'s. Make the no-args and no-prewarm tests' player `debug_invincible` only if needed for stability.

**Acceptance Criteria:**
- Given the redirect in `_ready` ignores `user_args` (e.g. parses an empty array), when the suite runs, then the stress and bench redirect tests fail.
- Given the `should_prewarm(..., args)` call in `level.gd` ignores the args, when the suite runs, then the level no-prewarm test fails.
- Given the redirect calls `get_tree().change_scene_to_file` instead of `change_scene`, when the suite runs, then the redirect tests fail (recorder empty).
- Given the full GUT suite runs headless, then it passes with no new failures and the GUT runner scene is never replaced.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 20 findings — high 0, medium 0, low 13, false 7, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) redirect tests don't pin that the redirect is deferred — fixed: both redirect tests assert `_scene_calls` is empty before the frame await.
  - `[low]` `[patch]` (blind) redirect tests don't pin the early return before level setup — fixed: both assert `GameState.current_level_id == ""` and no pre-warm explosion before the await.
  - `[low]` `[reject]` (blind) `OS.is_debug_build()` in `_ready` is not injectable, so the release branch is only covered by the static-helper tests — pre-existing and outside the intent (args + change-scene seams); GUT only runs the debug console build (AGENTS.md), and the fix adds a new field; same call as DW-27's release-build row.
  - `[low]` `[patch]` (blind) seams set with `Object.set` by string silently no-op on a rename, so `_ready` would fall back to the real scene change inside GUT — fixed: `_level_with_args` assigns `_level.user_args` / `_level.change_scene` as properties, as `test_sandbox.gd` does, so a missing field errors.
  - `[low]` `[patch]` (blind) `test_ready_wires_the_real_change_scene` has no assertion messages — fixed: messages added to all three assertions.
  - `[low]` `[reject]` (blind) test helpers copied from `test_sandbox.gd` / existing hand-written log loops not refactored — per-file helpers are the suite's established style; refactoring unrelated tests is outside the change, no named harm.
  - `[false]` `[reject]` (blind) inline default instead of a SceneRouter-style `default_change_scene()` helper — the intent says to follow the DebugTools seam, which defaults inline in `_ready` (`debug_tools.gd:70-73`); no caller needs the helper.
  - `[false]` `[reject]` (blind) header comment cites a DW id — DW ids in comments are the project convention (`bastion.gd:9`, `lancer.gd:9`, `test_debug_tools.gd:608`).
  - `[low]` `[reject]` (blind) no combined-flags test (`--stress --no-prewarm`) — the redirect tests now assert no pre-warm happens on redirect, which pins the ordering; extra combinations are `DebugArgs` parsing, tested in `test_debug_args.gd`.
  - `[low]` `[reject]` (edge) `call_deferred` drops the `change_scene_to_file` Error — pre-existing (the old line deferred the same call), debug-only path, and Godot itself logs a failed scene load; a guard adds a new method for a case never shown reachable.
  - `[false]` `[reject]` (edge) an injected callable whose target was freed falls back silently — the only injected callable is `_record_scene` on the live test object; no shown path frees it before `_ready`.
  - `[low]` `[reject]` (edge) redirect tests fail on a non-debug build — GUT only runs on the debug console build per AGENTS.md; same as DW-27's sandbox row.
  - `[low]` `[reject]` (verification-gap) default `user_args = OS.get_cmdline_user_args()` is not pinned by any test — under the documented GUT command the OS args are empty, so no in-suite test can tell the default from an empty literal; shared by Sandbox/DebugTools and rejected the same way in DW-27; a real `-- --stress` run is the check.
  - `[low]` `[patch]` (verification-gap, other) `test_ready_wires_the_real_change_scene` lacks messages — same as the blind row; same fix.
  - `[low]` `[patch]` (verification-gap, other) `Object.set` seam injection silently no-ops — same as the blind row; same fix.
  - `[false]` `[reject]` (intent) Level gets its own change-scene seam instead of SceneRouter's — the intent allows either; SceneRouter's doc names the `--stress` redirect as the exception and `_change_to` clears pause/feedback state, so routing through it would change behaviour.
  - `[low]` `[reject]` (intent) build type still read from `OS.is_debug_build()` — same as the blind row.
  - `[low]` `[patch]` (intent) redirect tests don't assert pre-warm is skipped — same as the blind early-return row; same fix.
  - `[false]` `[reject]` (intent) default user_args source never exercised — duplicate of the verification-gap row (graded there); no separate defect.
  - `[false]` `[reject]` (intent) real scene change only identity-checked — running it would replace the GUT runner's scene; the identity check plus the recorder is the intended surface.

### 2026-10-08 — Review pass
- verdicts: 14 findings — high 0, medium 0, low 6, false 8, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) `_make_level` sets neither seam, so a GUT run started with `-- --stress` would redirect through the real `change_scene_to_file` — pre-existing (the baseline `_ready` read the OS args and called the real change the same way) and only reachable with a GUT command line other than the documented one, which passes no user args; the fix changes setup for every existing level test, not a direct correction.
  - `[low]` `[reject]` (blind) redirect/no-prewarm tests depend on `OS.is_debug_build()` without a seam or guard — carried: same as the logged `OS.is_debug_build()` / non-debug-build rows; `level.gd:40` still reads it directly, GUT only runs the debug console build.
  - `[false]` `[reject]` (blind) the `change_scene` seam duplicates `SceneRouter.change_scene` — carried: same as the logged SceneRouter rows; the intent forbids routing the redirect through SceneRouter and names the DebugTools inline default.
  - `[false]` `[reject]` (blind) stress and bench tests are copies; no combined-flags or unknown-arg case — the two tests are the matrix's two separate rows, and the duplication names no harm; the combined-flags case is carried from the logged row (redirect tests pin no pre-warm on redirect) and unknown-arg handling is `DebugArgs` parsing, tested in `test_debug_args.gd`.
  - `[false]` `[reject]` (blind) `_level_with_args` clears `Log.sink` instead of restoring it, losing a caller's sink and lines from the deferred frame — `after_each` (`test_level.gd:47`) already resets the sink to `Callable()`, so no prior sink exists to lose; the redirect line is logged synchronously in `_ready` (`level.gd:41`) inside the capture window, and the deferred recorder logs nothing.
  - `[low]` `[reject]` (blind) the default `user_args = OS.get_cmdline_user_args()` is never tested — carried: same as the logged verification-gap row; under the documented GUT command both sides are empty, so the suggested assert cannot tell the initializer from an empty literal.
  - `[false]` `[reject]` (blind) "(DW-46 seams)" in the header comment will go stale — carried: same as the logged DW-id comment row (project convention).
  - `[false]` `[reject]` (blind) ledger and spec updates are uncommitted and the spec lost 19 lines — not a defect in the change: the ledger status and the spec reset for this follow-up pass are the orchestrator's bookkeeping, and the fix would edit the ledger/spec, which this run must not do.
  - `[low]` `[reject]` (edge) redirect/no-prewarm tests fail on a non-debug build — carried: same as the logged edge row.
  - `[false]` `[reject]` (edge) a freed injected callable falls back silently to the real scene change — carried: same as the logged edge row.
  - `[false]` `[reject]` (edge) after the redirect returns early the Player runs a frame without `set_spawner` — `PlayerWeapons` guards a missing spawner (`player_weapons.gd:100,106`: without a spawner the weapons do not fire); the ordering is unchanged from the baseline, and the redirect tests keep the level alive past that frame with the suite green.
  - `[low]` `[reject]` (intent) default `user_args` from the OS args is not exercised — carried: same as the logged verification-gap row.
  - `[false]` `[reject]` (intent) the real tree scene change is only identity-checked — carried: same as the logged intent row; running it would replace the GUT runner's scene.
  - `[low]` `[reject]` (intent) the `OS.is_debug_build()` release branch is reached only by the static-helper tests — carried: same as the logged intent row.

## Design Notes

The redirect stays `call_deferred` because changing scene inside `_ready` of the scene being entered is unsafe; tests therefore await one process frame before checking the recorder. The level's embedded `Overlay/DebugTools` keeps its own `user_args` seam (empty under GUT); the two are independent, as in the sandbox.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass
- Mutation check: temporarily make `level.gd` parse `PackedStringArray()` instead of `user_args` and rerun `-gtest=res://tests/unit/test_level.gd` -- expected: the new redirect and no-prewarm tests fail; restore.

## Auto Run Result

Status: done (follow-up review pass)

**Summary:** `Level` parses an injectable `user_args: PackedStringArray` (default `OS.get_cmdline_user_args()`) and redirects through an injectable `change_scene: Callable` (defaulted in `_ready` to the tree's `change_scene_to_file`, still `call_deferred`). Real runs behave as before. Five GUT tests drive the real `_ready` for `--stress`, `--bench`, no args, `--no-prewarm` and the default callable. Resolves DW-46. This follow-up pass changed no code.

**Files changed (commit `0d3a3891f71252c0685a695025a23425070d67b6`):**
- `game/scenes/level/level.gd` -- `user_args` and `change_scene` fields; `_ready` uses them; header comment updated.
- `game/tests/unit/test_level.gd` -- `_level_with_args`, `_prewarm_explosions`, `_lines_containing` helpers and five args/redirect tests.

**Review findings (follow-up pass):** 14 findings (low 6, false 8). Patches: none. Deferred: none. Rejected: all 14. Ten were carried from the first pass's rows (debug-build gate, SceneRouter reuse, default OS args, DW-id comment, freed callable, real-change identity check). The four new ones were rejected because:
- `_make_level` not using the seams: pre-existing, and only reachable with a non-documented GUT command line.
- Duplicated stress/bench tests: these are separate matrix rows, and the duplication causes no harm.
- `Log.sink` cleared rather than restored: `after_each` already clears it, and the redirect line is captured synchronously.
- Uncommitted ledger/spec: this is orchestrator bookkeeping.

Separately, the claim that the Player ticks a frame without a spawner was disproved: `PlayerWeapons` guards a missing spawner. Every reason is in the Review Triage Log.

**Follow-up review recommended:** false (follow-up pass; patched: high 0, medium 0, low 0).

**Verification:** `--import` exited 0. Full headless GUT suite: 897 tests, 896 passing, 1 pending (the `test_feedback.gd` hit-stop timing guard, unrelated), exit 0.

**Residual risks:** unchanged from the first pass. The default `user_args` initializer and the `OS.is_debug_build()` gate in `_ready` are exercised only by real command-line runs. The real `change_scene_to_file` is checked by identity only. `game-architecture.md` describes the redirect as `change_scene_to_file` without mentioning the seam. The uncommitted DW-46 status change in `deferred-work.md` is the orchestrator's and was left untouched.
