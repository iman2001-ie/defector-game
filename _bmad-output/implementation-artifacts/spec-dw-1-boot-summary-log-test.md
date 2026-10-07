---
title: 'DW-1: automated check that Config emits its boot [INFO][data] summary'
type: 'chore'
created: '2026-10-07'
status: 'done'
baseline_revision: '4491c2d9de30fe5d09ea44dc7c14524b599b6a95'
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

**Problem:** Nothing checks that `Config` logs its `[INFO][data]` load summary. Deleting `_log_summary()` from `Config._ready()` leaves every test green, because `Log` only prints and tests cannot see what it wrote (DW-1).

**Approach:** Give `Log` an optional, test-only sink `Callable` that receives every line `Log` actually writes (level, category, message), without changing normal output. Add GUT tests that install the sink, run `Config._ready()` and a successful `Config.reload()`, and assert an `INFO` / `data` line was captured.

## Boundaries & Constraints

**Always:**
- `Log.sink` defaults to an empty `Callable()`; when it is not valid, `emit_line()` behaves exactly as today (same `print`, `push_error`, `push_warning`, same return values).
- When valid, the sink is called once per written line with `(level: String, category: String, msg: String)`, after the line is printed. Dropped DEBUG lines are not passed to the sink.
- Tests that set `Log.sink` reset it to `Callable()` in `after_each`.
- Statically typed GDScript; all logging still goes through `Log`; `print()` stays only in `log.gd`.

**Never:**
- No change to the log line format, to `Config` behaviour, or to `Config._log_summary()` wording.
- No production code sets `Log.sink`.
- Do not touch `deferred-work.md` or `sprint-status.yaml`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| No sink | `Log.sink` empty | line printed, return true, nothing else called | none |
| Sink set, INFO | `Log.info("boot", "x")` | sink receives `("INFO", "boot", "x")` once | none |
| Sink set, DEBUG dropped | `debug_enabled = false`, `Log.debug(...)` | returns false, sink not called | none |
| Boot summary | sink set, `Config._ready()` | captured entry with level `INFO`, category `data`, msg starting `Loaded ` | none |
| Reload summary | sink set, `Config.reload()` on real data | returns true; captured `INFO`/`data` entry starting `Loaded ` | none |

</intent-contract>

## Code Map

- `game/autoloads/log.gd:43-54` -- `emit_line()`, the single write path; add the `sink` var (near `debug_enabled`, line 18) and invoke it after `print(line)` when `sink.is_valid()`.
- `game/autoloads/config.gd:22-24` -- `_ready()` calls `load_data()` then `_log_summary()`; the line DW-1 protects. Read-only.
- `game/autoloads/config.gd:51-71` -- `reload()` calls `_log_summary()` on success. Read-only.
- `game/autoloads/config.gd:156-160` -- `_log_summary()` emits `Log.info("data", "Loaded ...")` (or `"Data loaded with errors: ..."`). Read-only.
- `game/tests/unit/test_log.gd` -- existing Log tests; `before_each`/`after_each` save and restore `debug_enabled`. Add sink tests and restore `sink` there.
- `game/tests/unit/test_config.gd:31-39` -- `before_each`/`after_each` (after_each re-runs `Config.load_data()`); add the summary tests and reset `Log.sink` in `after_each`.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_log.gd` -- first add failing tests: sink receives `(level, category, msg)` for INFO, WARN (still asserting the push_warning) and ERROR (still asserting the push_error); sink not called for a dropped DEBUG line; with no sink, `emit_line` still returns true. Reset `Log.sink = Callable()` in `after_each`.
- `game/tests/unit/test_config.gd` -- add failing tests: with a capturing sink, `Config._ready()` captures an `INFO`/`data` entry whose msg begins `Loaded `; `Config.reload()` on the real files returns true and captures the same. Reset `Log.sink` in `after_each`.
- `game/autoloads/log.gd` -- add `var sink: Callable = Callable()` with a doc comment marking it a test hook, and call it from `emit_line()` per the Boundaries.

**Acceptance Criteria:**
- Given `_log_summary()` is removed from `Config._ready()`, when the GUT suite runs, then the boot-summary test fails.
- Given the change is applied, when the full GUT suite runs headless, then every test passes and the console log lines look identical to before.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 19 findings — high 0, medium 0, low 12, false 7, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) `test_no_sink_still_writes` never installs a sink, so its zero-capture check cannot fail — fixed: the test now installs `_capture`, clears it with `Callable()`, logs, and asserts nothing was captured.
  - `[low]` `[reject]` (blind) The `"Data loaded with errors:"` branch of `_log_summary()` has no capture test — DW-1 is about the summary being emitted at boot at INFO; the fix is an extra test outside that, and nobody would meet the gap in normal use.
  - `[low]` `[reject]` (blind) The summary check only matches the `Loaded ` prefix, not the paths or counts — pinning the wording would make the test brittle; DW-1 only asks whether the line is emitted at INFO/data.
  - `[low]` `[reject]` (blind) The `log.gd` file header does not mention `sink` — the var has its own doc comment that names it a test hook; cosmetic.
  - `[low]` `[reject]` (blind) A sink that calls `Log` would recurse — only test sinks exist and they only append; the fix would add a guard for a state nothing reaches.
  - `[false]` `[reject]` (blind) A sink with the wrong arity is unguarded — a mismatched Callable fails loudly with an engine call error, which is correct behaviour for a programmer mistake in a test hook.
  - `[low]` `[reject]` (blind) Nothing enforces "production never sets `Log.sink`" — the fix is a new grep-style test; the risk is a convention break nobody is near.
  - `[low]` `[reject]` (blind) The spec's Code Map line ranges are off by a few lines — the fix edits this build's spec.
  - `[false]` `[reject]` (blind) The "console lines identical" AC and the mutation AC are unchecked — the diff leaves `format()` and the `print(line)` call untouched, and the mutation was run in review: removing `_log_summary()` from `_ready()` gave 305/306 with 1 failing.
  - `[false]` `[reject]` (blind) `test_reload_logs_load_summary` relies on hidden ordering — it calls `Config.load_data()` itself, which resets both paths to the defaults before `reload()`.
  - `[low]` `[reject]` (blind) The `_capture` helper is duplicated in two test files — 3 lines each; a shared helper class adds more than it saves.
  - `[low]` `[reject]` (edge) A sink that logs recurses without bound — same as the blind recursion finding; no such sink exists, and the fix is an added guard.
  - `[false]` `[reject]` (edge) `is_valid()` does not check the sink's arity — loud failure on a test-only programmer error is correct behaviour.
  - `[false]` `[reject]` (edge) The sink runs before `push_error`/`push_warning`, so the order differs — the spec requires "after the line is printed", which holds; the test sinks have no side effects that touch the pushes, and the WARN/ERROR sink tests still assert the pushes.
  - `[low]` `[reject]` (intent) The test re-runs `_ready()` instead of watching the engine's real boot — the hook cannot be installed before autoload init; the ledger's failure mode (deleting the call from `_ready()`) is caught, as the mutation run showed.
  - `[low]` `[reject]` (intent) The sink sees the raw level/category/msg, not the printed `[INFO][data]` text — the formatting is unchanged and is pinned by the existing `test_format`; the fix would be a duplicate check.
  - `[low]` `[reject]` (intent) The `Loaded ` prefix is narrower than "any INFO/data line" and leaves the error branch untested — same root as the blind error-branch finding; rejected for the same reason.
  - `[false]` `[reject]` (intent) The hook timing means a throwing sink could skip the pushes — GDScript call errors do not unwind the caller, and production never sets the sink.
  - `[false]` `[reject]` (intent) There is no record of the mutation run — it was run in review with 305/306 passing and 1 failing, and `config.gd` was restored with no diff.

### 2026-10-07 — Review pass
- verdicts: 16 findings — high 0, medium 0, low 14, false 2, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) Moving `_log_summary()` above `load_data()` in `_ready()` would still pass, because the autoload already holds data from earlier loads — a different defect from DW-1, which is the call being deleted; catching it needs temp-file setup and path/count assertions, and nobody is near that reorder.
  - `[low]` `[reject]` (blind) No test checks that a rejected `reload()` logs no summary — today `_log_summary()` sits after the `return false` (config.gd:61-68); the fix is a new test for a mutation nobody is near.
  - `[low]` `[reject]` (blind) The summary tests do not also assert no `ERROR` was captured during the load — validity of the real data files is a separate concern from DW-1; the fix adds an assertion outside this ledger item.
  - `[low]` `[reject]` (blind) No test shows DEBUG lines reach the sink when `debug_enabled` is true — the sink call sits on the one shared write path after the drop check, so INFO/WARN/ERROR coverage already exercises it; the fix is an extra test.
  - `[low]` `[reject]` (blind) No test shows an unknown-category line reaches the sink — same shared write path as above; the fix is an extra test.
  - `[false]` `[reject]` (blind) `test_no_sink_still_writes` does not show WARN/ERROR still push with no sink — the existing `test_warn_also_pushes_warning` and the error-push test run with the default empty sink (reset in `after_each`) and assert the pushes.
  - `[low]` `[reject]` (blind) Re-running `Config._ready()` in a test would be fragile if `_ready()` later connects signals — today `_ready()` is only `load_data()` + `_log_summary()` (config.gd:22-24); the harm is hypothetical, and the fix is a refactor or comment.
  - `[low]` `[reject]` (blind) The `log.gd` header does not mention `sink`, and the sink is not gated off in release builds — carried: same as the prior pass's header row; the var has its own doc comment, and production never sets it.
  - `[low]` `[reject]` (edge) A rejected reload is not tested for the absence of the summary — same as the blind row above; rejected for the same reason.
  - `[low]` `[reject]` (edge) The `"Data loaded with errors"` branch is never captured — carried: same as the prior pass's error-branch row.
  - `[low]` `[reject]` (edge) A sink that calls `Log` recurses without bound — carried: same as the prior pass's recursion rows.
  - `[low]` `[reject]` (intent) The tests re-run `_ready()` instead of watching the engine's real boot — carried: same as the prior pass's intent row.
  - `[low]` `[reject]` (intent) The sink sees raw arguments, not the formatted `[INFO][data]` text — carried: same as the prior pass's intent row; `test_format` pins the format.
  - `[low]` `[reject]` (intent) Only the success branch of `_log_summary()` is observed — carried: same as the prior pass's prefix/error-branch row.
  - `[low]` `[reject]` (intent) `test_no_sink_still_writes` cannot prove `print` ran or that nothing else happened — "behaves exactly as today" is shown by the code (the only addition is the guarded `sink.call`) and by the existing no-sink tests; capturing stdout would need new infrastructure.
  - `[false]` `[reject]` (intent) The working tree has uncommitted changes to `deferred-work.md` and the spec — they are outside the reviewed diff: the ledger change is the orchestrator's own bookkeeping, and the spec change is this follow-up pass resetting its result section.

## Design Notes

A sink beats a "last line" record: `Config._ready()` can log errors before the summary, and a list lets the test search for the specific entry. A method on the test (or a lambda appending to an Array, which is captured by reference) works as the sink:

```gdscript
var _captured: Array[Array] = []
func _capture(level: String, category: String, msg: String) -> void:
	_captured.append([level, category, msg])
# Log.sink = _capture
```

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failures (GODOT_DIR from LOCAL.md).

## Auto Run Result

Status: done

**Summary:** `Log` has a test-only `sink: Callable`. When it is set, every line that is actually written is passed to it as `(level, category, msg)`, after the `print`. It is empty by default, so normal output is unchanged. GUT tests install a capturing sink, run `Config._ready()` and a successful `Config.reload()`, and assert that an `INFO`/`data` line starting `Loaded ` was captured. That resolves DW-1. This was a follow-up review pass on the committed change (695a0e0), and it made no code changes.

**Files changed (by the original pass, re-reviewed here):**
- `game/autoloads/log.gd` -- the `sink` var and the call to it in `emit_line()`.
- `game/tests/unit/test_log.gd` -- 5 sink tests; `after_each` resets the sink.
- `game/tests/unit/test_config.gd` -- 2 tests for the boot and reload summaries; `after_each` resets the sink.

**Review findings (follow-up pass):** 16 total. 0 patches, 0 deferred, 16 rejected (14 low, 2 false). Each one's reason is in the Review Triage Log above. 6 rows were carried unchanged from the first pass. The new low rows all ask for extra tests or guards beyond DW-1: no summary on a rejected reload, DEBUG or unknown-category lines reaching the sink, the summary logged before the data loads, and no ERROR during the load. The verification-gap layer found no gaps.

**Follow-up review recommended:** false. This was a follow-up pass and it patched no `high` (0 high, 0 medium and 0 low patched).

**Verification:** I ran the full GUT suite headless on the committed tree: 306/306 passed, 26 scripts, 1790 asserts.

**Residual risks:** The `"Data loaded with errors:"` branch of the summary, and the absence of a summary on a rejected reload, still have no capture tests. The timing-sensitive hit-stop test that can mark itself Pending predates this change.
