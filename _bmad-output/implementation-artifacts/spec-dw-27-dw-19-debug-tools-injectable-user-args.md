---
title: 'DW-27, DW-19: injectable debug user args and the real F5 path'
type: 'chore'
created: '2026-10-07'
status: 'done'
baseline_revision: '4d146d661164617587b08290368ba747073362f4'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
warnings: []
deferred:
  - summary: >-
      Level._ready still parses OS.get_cmdline_user_args() directly, so its --stress/--bench redirect to the sandbox and its --no-prewarm skip are untested (the DW-27 gap, in a third script).
    evidence: |-
      game/scenes/level/level.gd:22 calls DebugArgs.parse(OS.get_cmdline_user_args()); test_level.gd only exercises the static helpers should_redirect_to_stress and should_prewarm with hand-built dictionaries, so breaking the args wiring in _ready leaves the suite green. Pre-existing and outside the bundle intent (which names DebugTools and Sandbox); the redirect also needs an injectable change_scene seam.
    location: >-
      game/scenes/level/level.gd:22
    severity: medium
---

<intent-contract>

## Intent

**Problem:** `DebugTools._ready` and `Sandbox._ready` read `OS.get_cmdline_user_args()` directly, so the `--no-prewarm`, `--stress` and `--bench` wiring is untested (deleting `_prewarm = args.prewarm` leaves the suite green, DW-27). The F5 tests only feed an `InputEventAction` and inject `restart_scene`, so the real key binding, the default restart callable and a consumer re-reading Config after reload are unpinned (DW-19).

**Approach:** Give both scripts a `user_args: PackedStringArray` field that defaults to `OS.get_cmdline_user_args()` and that `_ready` parses instead of the OS call; tests set it before `add_child`. Add GUT tests that observe the wiring through outer surfaces (log lines, overlay, held fire, spawned explosions, stress grid) and a test that drives a real F5 `InputEventKey` through the viewport.

## Boundaries & Constraints

**Always:** statically typed GDScript; logging via `Log`; behaviour of real runs unchanged (the default value is exactly `OS.get_cmdline_user_args()`); tests restore global state they touch (`DebugTools.overlay_visible`, `DebugTools._overlay_initialised`, `Input` fire action, `Log.sink`, Config/Feedback, temp files).

**Never:** call the real `get_tree().reload_current_scene` or `get_tree().quit` from a test (it would reload or quit the GUT runner); change `DebugArgs` parsing; edit the deferred-work ledger; change the `OS.is_debug_build()` gating in `Sandbox`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Bench + no-prewarm | DebugTools `user_args = ["--bench=1", "--no-prewarm"]`, `quit_game` injected | bench start log line contains `prewarm=off`; `fire_laser` held; overlay visible | none |
| Bench, prewarm default | `user_args = ["--bench=1"]` | bench start log line contains `prewarm=on` | none |
| Stress only | `user_args = ["--stress"]`, `_overlay_initialised = false` | overlay label visible, no bench (fire not held) | none |
| No args | `user_args = []` | overlay hidden, no bench | none |
| Sandbox no-prewarm | Sandbox `user_args = ["--no-prewarm"]` | no prewarm explosion in `World/Effects`; log `Feedback pre-warm skipped` | none |
| Sandbox default | `user_args = []` | one prewarm explosion per tier in `World/Effects` | none |
| Sandbox stress | Sandbox `user_args = ["--stress"]` (stress_mode left false) | `stress_mode` true, 40 Wasps | none |
| Real F5 | `InputEventKey` physical F5 pressed via `get_viewport().push_input` | Config reloaded from changed file, `restart_scene` called once | none |

</intent-contract>

## Code Map

- `game/ui/debug/debug_tools.gd` -- `_ready` line 69 parses `OS.get_cmdline_user_args()`; line 71 `_prewarm = args.prewarm`; lines 72-81 stress overlay/vsync and bench start. Injected fields live at lines 25-30 (`debug_enabled`, `restart_scene`, `quit_game`) -- add `user_args` alongside with the same "tests set before add_child" doc style. `_start_bench` logs `prewarm=%s` (line 237) and presses `fire_laser`.
- `game/scenes/sandbox/sandbox.gd` -- `_ready` line 49 parses OS args; line 50 sets `stress_mode`; line 64 `should_prewarm(...)` gates `Feedback.prewarm()` and logs the skip. Add `user_args` near `stress_mode` (line 30).
- `game/autoloads/feedback.gd:110` -- `prewarm()` spawns one explosion per tier at `PREWARM_POSITION` through the registered spawner (observable in `World/Effects`).
- `game/tests/unit/test_debug_tools.gd` -- `_make_tools` (line 38) injects `restart_scene`; `_capture`/`_lines_containing` (lines 221-230) capture logs; `_write_tuning` (line 58) writes a temp tuning file; `after_each` restores state. `_overlay_initialised` is a static that must be reset to test the stress overlay.
- `game/tests/unit/test_sandbox.gd` -- `before_each` adds a default sandbox; `_stress_sandbox` (line 255) shows the replace pattern; `_wasps()` helper; `test_world_environment_glow_follows_changed_data` is the existing consumer-reread example via `Config.tuning` mutation.
- `game/tests/unit/test_feedback.gd:303` -- reference for how prewarm explosions are counted.
- `game/project.godot:104` -- `debug_reload_data` is bound to physical key F5 (4194336).

## Tasks & Acceptance

**Execution:**
- `game/ui/debug/debug_tools.gd` -- add `var user_args: PackedStringArray = OS.get_cmdline_user_args()` (doc: tests override before add_child) and parse it in `_ready` -- the DW-27 seam.
- `game/scenes/sandbox/sandbox.gd` -- same field; parse it in `_ready`; update the `stress_mode` doc comment -- the DW-27 seam for the sandbox.
- `game/tests/unit/test_debug_tools.gd` -- add tests for the DebugTools matrix rows (bench+no-prewarm, bench default, stress only, no args), a real-F5 test (`InputEventKey`, `physical_keycode = KEY_F5`, `pressed = true`, delivered with `get_viewport().push_input`), a default-callables test (`restart_scene` targets the tree's `reload_current_scene`, `quit_game` the tree's `quit`, checked by object and method without calling them), and a consumer re-read test: F5 with a changed temp tuning (`render.glow.intensity`) and a `restart_scene` that instantiates `sandbox.tscn`, asserting the new sandbox's environment glow intensity equals the file's new value. Reset `_overlay_initialised` and release fire in teardown.
- `game/tests/unit/test_sandbox.gd` -- add tests for the Sandbox matrix rows (no-prewarm, default, stress via `user_args`), replacing the before_each sandbox like `_stress_sandbox` does; count prewarm explosions at `Feedback.PREWARM_POSITION` (or the equivalent observable used in `test_feedback.gd`).

**Acceptance Criteria:**
- Given `_prewarm = args.prewarm` is deleted from `debug_tools.gd`, when the suite runs, then at least one new test fails.
- Given the `--stress` wiring in either `_ready` is deleted, when the suite runs, then at least one new test fails.
- Given the `should_prewarm(..., args)` call in `sandbox.gd` ignores the args, when the suite runs, then the sandbox no-prewarm test fails.
- Given a real F5 key event reaches the viewport, when DebugTools handles it, then Config holds the reloaded value and the injected restart ran once.
- Given no injection, when DebugTools is ready, then `restart_scene` is bound to the scene tree's `reload_current_scene`.
- Given the full GUT suite runs headless, then it passes with no new failures or orphans warnings attributable to these tests.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 24 findings — high 0, medium 2, low 13, false 9, maybe-false 0
- findings:
  - `[medium]` `[defer]` (blind) level.gd still reads OS.get_cmdline_user_args() directly — confirmed at level.gd:22; pre-existing, outside the intent's named scripts; recorded in frontmatter `deferred`.
  - `[low]` `[patch]` (blind) bench-args tests depend on the static `_overlay_initialised` via test order — confirmed: after_each restores the script-start value, so a prior script leaving it true hides the overlay; fixed by resetting it in `_args_tools` before add_child.
  - `[low]` `[reject]` (blind) no test pins the default `user_args` to the OS args — GUT runs with empty user args, so no in-suite test can tell the OS default from an empty literal; the real bench run is the check.
  - `[low]` `[reject]` (blind) no test of args reaching a release (`debug_enabled = false`) DebugTools — the early return precedes the parse and `test_release_build_is_a_no_op` pins it; extra tests add little.
  - `[low]` `[reject]` (blind) vsync-off from --stress not asserted — headless DisplayServer vsync is not observable; unlikely regression, not testable here.
  - `[false]` `[reject]` (blind) sandbox test hard-codes 40 Wasps — tests pin literal expectations by design (the existing `test_stress_grid_spawns_40_in_the_enemy_zone` does the same); it is a debug-scene constant, not GDD data read in game code.
  - `[false]` `[reject]` (blind) Log.sink left set if `_ready` errors — a GDScript error in `_ready` does not abort the caller, so the next line restores the sink; after_each also clears it.
  - `[low]` `[reject]` (blind) duplicated log-capture helpers / `_lines` declared mid-file — cosmetic; matches the sectioned style test_debug_tools.gd already uses.
  - `[low]` `[reject]` (blind) real-F5 test doesn't assert handled / sends no release — `is_action_pressed` needs no release event; handled-marking is exercised indirectly (restarted sandbox's tools never fire); low value.
  - `[false]` `[reject]` (blind) re-read test doesn't prove the glow changed — `_write_tuning(8.0)` writes the full default tuning, so its glow is the default and `new_intensity` is default + 0.25 by construction.
  - `[false]` `[reject]` (blind) restarted sandbox's DebugTools also handles the F5 — `_mark_handled` stops propagation; the run shows `_restarts == 1` and the GUT runner was not reloaded.
  - `[low]` `[patch]` (edge) bench test overlay assert order-dependent — same root cause as the blind finding above; same fix.
  - `[low]` `[reject]` (edge) runner launched with `-- --bench/--stress` makes the nested sandbox DebugTools quit GUT — pre-existing for every sandbox test; the documented GUT command passes no user args.
  - `[false]` `[reject]` (edge) restarted sandbox's DebugTools uses real reload/quit — it never handles the already-handled F5 and GUT has no user args; the run confirms no reload or quit.
  - `[low]` `[reject]` (edge) sandbox arg tests fail on a non-debug build — GUT only runs on the debug console editor binary per AGENTS.md.
  - `[false]` `[reject]` (edge, claim) bench+no-prewarm overlay row unpinned without precondition — superseded by the `_args_tools` reset patch; the row is now deterministic.
  - `[false]` `[reject]` (edge, claim) the "never call real reload/quit" guarantee is conditional — under the documented GUT command (no user args) it holds; see the rows above.
  - `[medium]` `[defer]` (verification-gap) level.gd args wiring untested — same root cause as the first row; deferred once.
  - `[low]` `[reject]` (verification-gap, other) default `user_args` unpinned — same as the blind row; the reviewer itself notes no GUT test can catch it.
  - `[false]` `[reject]` (intent) real `reload_current_scene` is never run — the intent explicitly accepts the default-callable check plus a consumer re-read; running it would reload the GUT runner.
  - `[low]` `[patch]` (intent) Feedback not checked after the real F5 — fixed: the real-F5 test now loads Feedback tiers and asserts LARGE shake_px is 12.0 after the key event.
  - `[low]` `[reject]` (intent) no test ties Sandbox and DebugTools to the same args — both default to the same OS call; a cross-check needs extra plumbing for no named harm.
  - `[low]` `[reject]` (intent) default `user_args` untested — duplicate of the rows above.
  - `[false]` `[reject]` (intent) vsync not tested — duplicate of the blind vsync row; not observable headless (graded false as a separate gap since the overlay surface is pinned).

### 2026-10-07 — Review pass (follow-up)
- verdicts: 24 findings — high 0, medium 1, low 20, false 1, maybe-false 2
- findings:
  - `[medium]` `[defer]` (blind) level.gd still reads OS.get_cmdline_user_args() directly — carried: level.gd:22 unchanged; already in frontmatter `deferred`, not re-added.
  - `[low]` `[reject]` (blind) sandbox instances in older tests and `_restart_sandbox` read the real OS args — carried: same as the prior "runner launched with `-- --bench/--stress`" row; the documented GUT command passes no user args.
  - `[low]` `[reject]` (blind) sandbox `--bench` → stress_mode not tested — `DebugArgs.parse` makes a positive bench imply `stress` (debug_args.gd), and Sandbox only reads `args.stress`, which the `--stress` test pins; a bench-only regression would live in DebugArgs, which has its own tests.
  - `[low]` `[reject]` (blind) release gate not tested with args — carried: prior release-build row; the early return precedes the parse.
  - `[false]` `[reject]` (blind) sandbox stress test hard-codes 40 — carried: prior row; literal expectations by design.
  - `[low]` `[reject]` (blind) bench tests warp the mouse and don't restore it — headless runs (the only documented GUT mode) have no real cursor; a restore adds teardown state for no everyday harm.
  - `[low]` `[patch]` (blind) `debug_args.gd:7` doc says callers pass `OS.get_cmdline_user_args()` — fixed: the comment now says callers pass the OS args or an injectable `user_args` field that defaults to them.
  - `[low]` `[reject]` (blind) duplicated log-capture helpers / `_lines` mid-file / sink left set if `_ready` errors — carried: prior two rows (cosmetic; a `_ready` error does not abort the caller).
  - `[low]` `[reject]` (blind) duplicated `user_args` doc comments listing the flags — cosmetic; two short comments, no caller diverges.
  - `[maybe-false]` `[reject]` (blind) F5 glow test's JSON round-trip may turn ints into floats and fail reload — the full suite passes with this test (624/624), and the real-F5 test asserts Config holds the reloaded value; if it ever broke it would fail loudly, only `low`.
  - `[low]` `[reject]` (edge) restarted sandbox's `user_args` not injected — carried: prior runner-args row.
  - `[low]` `[reject]` (edge) restarted sandbox's nested DebugTools has real reload/quit — carried: prior row; it never handles the already-handled F5 and GUT has no user args.
  - `[low]` `[reject]` (edge) `warp_mouse` moves the developer's cursor in windowed runs — same as the blind mouse row; windowed GUT runs are not a documented mode.
  - `[low]` `[reject]` (edge) replacement sandbox's nested DebugTools parses OS args — carried: prior runner-args row.
  - `[low]` `[reject]` (edge) test_sandbox never restores DebugTools overlay statics — pre-existing for every sandbox in `before_each`; with empty args the nested DebugTools sets `overlay_visible = false`, the default, and test_debug_tools resets `_overlay_initialised` in `_args_tools`.
  - `[maybe-false]` `[reject]` (edge) a focused GUT Control may eat the pushed F5 — headless run shows the test passing; only a windowed-run concern, `low` if true.
  - `[low]` `[reject]` (edge, claim) "tests restore the global state they touch" — the only unrestored static is the overlay one above, set to its default value; no named harm.
  - `[medium]` `[defer]` (verification-gap) level.gd args wiring untested — carried: same root cause as the first row; already deferred (DW-46).
  - `[low]` `[reject]` (intent) default restart callable pinned by identity, not behaviour — carried: prior row; the intent forbids running the real reload.
  - `[low]` `[reject]` (intent) consumer re-read uses an injected restart, not a real reload — carried: prior row; the Design Notes accept it.
  - `[low]` `[reject]` (intent) no test ties DebugTools and Sandbox to the same args — carried: prior row.
  - `[low]` `[reject]` (intent) bench via `user_args` is only observed at start-up — stepping and `quit_game` are covered by the existing direct-bench tests; the args seam only affects `_ready`.
  - `[low]` `[reject]` (intent) the real OS default is not exercised — carried: prior row; GUT runs with empty user args.
  - `[low]` `[reject]` (intent) only `physical_keycode` F5 is pushed — it matches the project.godot binding exactly, which is the real path.

## Design Notes

The real `reload_current_scene` cannot run inside GUT, so "consumer re-reads Config" is pinned by an injected restart that does what the real one does (instantiate the scene fresh) after a real F5 reload from disk. The sandbox's embedded DebugTools keeps reading real OS args (empty under GUT); the two seams are independent on purpose.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass
- Mutation check: temporarily delete `_prewarm = args.prewarm` and rerun `test_debug_tools.gd` (`-gtest=res://tests/unit/test_debug_tools.gd`) -- expected: a new test fails; restore.


## Auto Run Result

Status: done (follow-up review pass)

**Summary:** `DebugTools` and `Sandbox` parse an injectable `user_args: PackedStringArray` (default `OS.get_cmdline_user_args()`, so real runs are unchanged). GUT tests pin the `--bench`/`--no-prewarm`/`--stress` wiring through outer surfaces and the real F5 key path. Resolves DW-27 and DW-19. This follow-up pass re-reviewed the full change since the baseline and fixed one stale doc comment.

**Files changed:**
- `game/ui/debug/debug_tools.gd` -- `user_args` field; `_ready` parses it.
- `game/scenes/sandbox/sandbox.gd` -- `user_args` field; `_ready` parses it; `stress_mode` doc updated.
- `game/ui/debug/debug_args.gd` -- (this pass) doc comment now says callers may pass an injectable `user_args` field.
- `game/tests/unit/test_debug_tools.gd` -- args-wiring, real-F5, default-callables and consumer re-read tests.
- `game/tests/unit/test_sandbox.gd` -- `--no-prewarm`, default prewarm and `--stress` args tests.

**Review findings (follow-up pass):** 24 findings (medium 1, low 20, false 1, maybe-false 2). Patched 1 (low): the stale `DebugArgs` doc comment. Deferred: the `level.gd` args gap (carried, already in `deferred`/DW-46, not re-added). Rejected the rest; each reason is in the Review Triage Log (most carried from the first pass; new ones are windowed-run-only or cosmetic).

**Follow-up review recommended:** false (follow-up pass; patched: high 0, medium 0, low 1).

**Verification:** `--import` exited 0. Full headless GUT suite after the patch: 624/624 passing, exit 0.

**Residual risks:** the real `reload_current_scene` is only checked by Callable identity. The sandbox args tests assume a debug build. Tests that build a sandbox without overriding `user_args` would change behaviour if GUT were launched with `-- --stress`/`--bench`. `level.gd` args wiring is still untested (deferred, DW-46).
