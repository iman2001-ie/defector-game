---
title: 'DW-8: validating Config.reload() that keeps its own state on failure'
type: 'refactor'
created: '2026-10-07'
status: 'done'
baseline_revision: '362ec3fb20704935265ef886cbd7eeb3b1f0f9ae'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
warnings: []
deferred:
  - summary: >-
      The real F5 path (input event, then get_tree().reload_current_scene and consumers re-reading Config) is still untested; tests inject restart_scene and call reload_data() directly.
    evidence: |-
      Pre-existing gap (epic 1 retro finding B4, deferred there). This change keeps the injected-restart test seam; the B1 failure it fixes is pinned at the Config and reload_data() level only.
    location: >-
      game/ui/debug/debug_tools.gd:28,51-52
    severity: low
---

<intent-contract>

## Intent

**Problem:** F5 rolls back only on a JSON parse failure or empty flags. A file that parses but drops a key or changes a type is accepted, and the restarted scene then hits Config's missing-key assert. The rollback also writes `Config.tuning`, `Config.flags` and `Config.load_error` from `DebugTools`, which breaks the "access through Config" rule (retro epic 1, B1/B2/C2/D2).

**Approach:** `Config.reload() -> bool` reads both files into locals, validates them against the shape of the data loaded now, and only then commits. On any failure it leaves `tuning`, `flags` and `load_error` exactly as they were, logs why, and returns `false`. `DebugTools.reload_data()` calls it and branches on the result.

## Boundaries & Constraints

**Always:**
- The reference shape is the currently loaded `tuning` / `flags`. Every key path in it must exist in the new data with the same kind: number (int and float are the same kind), Dictionary (recurse), Array (elements not checked), String, bool. Extra keys in the new data are allowed.
- If the current data is empty (e.g. boot failed), there is no reference, so any parseable object root is accepted.
- A parse error, missing file or non-object root in either file fails the reload.
- Failure: one `Log.error("data", ...)` line naming every problem (full key path, e.g. `tuning.player.hearts missing`, `tuning.player.max_speed: expected number, got String`) and saying the previous data is kept.
- Success: commit both dictionaries, set `load_error = ""`, call `_log_summary()`, return `true`.
- `reload()` keeps using the paths last given to `load_data()`.
- Statically typed GDScript; logging only via `Log`.

**Never:**
- No writes to `Config.tuning`, `Config.flags` or `Config.load_error` outside `config.gd` (production code).
- Do not change `load_data()` boot behaviour or the getters.
- No hand-written schema file or key list; no new reload signal (out of scope).
- Do not touch `deferred-work.md` or `sprint-status.yaml`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Value change | Good data loaded; file changes a number | returns true; new value served; `load_error` "" | none |
| Added key | New file has an extra key | returns true | none |
| Parse failure | Tuning file is `{ not json` | returns false; tuning, flags, load_error unchanged | Log.error names parse error |
| Flags failure | Flags file unparseable | returns false; old flags kept | Log.error |
| Missing key | `player.hearts` removed | returns false; old data intact | Log.error contains `tuning.player.hearts` |
| Wrong type | `player.max_speed` is `"fast"` | returns false; old data intact | Log.error contains `tuning.player.max_speed` |
| Missing flag | a flag key removed or made non-bool | returns false | Log.error contains `flags.<name>` |
| No reference | Boot tuning failed (`load_error` set, tuning {}), file now fixed | returns true; load_error "" | none |
| Still broken | Boot tuning failed; reload also fails | returns false; load_error unchanged (still set) | Log.error |

</intent-contract>

## Code Map

- `game/autoloads/config.gd:44-47` -- current `reload()` just re-runs `load_data()`; replace with the validating version.
- `game/autoloads/config.gd:107-124` -- `_read_json_dict()` returns `{data, error}` and logs the read error itself; reuse it for both files.
- `game/autoloads/config.gd:127-131` -- `_log_summary()`; call on success.
- `game/ui/debug/debug_tools.gd:121-143` -- `reload_data()` snapshots and writes Config fields; reduce to `if not Config.reload(): Log.error("debug", "F5 reload failed; previous data kept, scene not restarted"); return false`, then the existing Feedback/PauseArbiter/restart sequence. Update the doc comment.
- `game/tests/unit/test_config.gd:197-212` -- reload tests; `test_reload_rereads_custom_paths` must be updated for the bool return and the extra error line.
- `game/tests/unit/test_debug_tools.gd:56-66,155-184` -- `_write_tuning()` helper and the bad-JSON / bad-flags F5 tests; these must keep passing (they assert `[ERROR][debug]` and `load_error == ""`).
- `game/tests/fixtures/` -- existing bad fixtures; tests may write temp files under `user://` instead of new fixtures, as `test_debug_tools.gd` does.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_config.gd` -- first add failing tests: successful reload returns true and serves the new value; parse failure returns false and keeps old tuning/flags/load_error; missing key and wrong type each return false, keep old data, and push an error naming the key path; extra key accepted; flag removed fails; no-reference reload after a failed boot succeeds. Write temp copies of the real data under `user://` and clean them in `after_each`. Fix `test_reload_rereads_custom_paths` for the new contract.
- `game/autoloads/config.gd` -- implement `reload() -> bool` plus a recursive shape check helper per the Boundaries.
- `game/ui/debug/debug_tools.gd` -- call the new API; delete every direct write of Config fields.
- `game/tests/unit/test_debug_tools.gd` -- add an F5 test: a tuning file missing a key refuses restart, keeps the old value and leaves Feedback tiers untouched.

**Acceptance Criteria:**
- Given a running debug build with good data, when F5 is pressed after a tuning edit removes a key, then the scene does not restart, the old values are still served, and the log names the missing key path.
- Given the repo after the change, when searching `game/` outside `tests/` for assignments to `Config.tuning`, `Config.flags` or `Config.load_error`, then none are found.
- Given the full GUT suite, when run headless, then all tests pass (pre-existing pending tests stay pending).

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 23 findings — high 0, medium 0, low 17, false 6, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) When one file fails to read, the other file's shape check is skipped, so the rejection line misses problems. Fix: `reload()` now shape-checks each file whose own read succeeded. Added `test_reload_reports_problems_in_both_files`.
  - `[low]` `[reject]` (blind) With no reference (boot failed), any parseable object is accepted, and the old `flags.is_empty()` guard is gone. The spec chose this ("No reference" row). It only differs from the old behaviour for a literal `{}` after a failed boot. A partial tuning after a failed boot was accepted before too. Fixing it needs a second schema source, which is more than a direct correction, for a state nobody meets in everyday use.
  - `[low]` `[reject]` (blind) Read errors are logged twice (`_read_json_dict` plus the "Reload rejected" line), and the `[debug]` line no longer carries the reason. Log-only and cosmetic: the reason is on the adjacent `[data]` line. `_read_json_dict`'s own logging is pre-existing and the spec reuses it.
  - `[low]` `[reject]` (blind) Array elements are not checked, and a key added by one reload becomes required for later reloads. Both are by design (Boundaries; Design Notes: removing a key needs a restart). The arrays Config currently serves hold only strings.
  - `[low]` `[patch]` (blind) No tests cover a missing file / non-object root or a nested mismatch path. Added `test_reload_missing_file_keeps_state` and `test_reload_nested_wrong_type_names_full_path`.
  - `[false]` `[reject]` (blind) The verification grep misses indexed or method-call writes. A broader `grep -rnE "Config\.(tuning|flags|load_error)" game --include=*.gd` outside `tests/` finds no references at all, so no such write exists. The fix would also edit the spec.
  - `[low]` `[patch]` (blind) The comment in `test_reload_rereads_custom_paths` calls the third error a "reload summary". Corrected to the "Reload rejected" line. Exact error counts are kept on purpose (they pin the logging contract).
  - `[low]` `[patch]` (blind) `test_reload_missing_flag_fails` depends on key order. Replaced with the `_assert_rejection_names()` helper, which checks each fragment in any order. Two `assert_push_error` calls can't both claim one GUT error.
  - `[low]` `[reject]` (blind) No DebugTools-level "still broken" test, and no assert that Feedback/PauseArbiter are skipped on failure. Covered at Config level, and the tiers-untouched asserts in the F5 failure tests already show Feedback was not reloaded. Adding a test would be redundant.
  - `[false]` `[reject]` (blind) The spec has stale line ranges and empty logs. The logs fill during review, and the fix would edit this build's spec.
  - `[low]` `[patch]` (edge) Shape problems in the file that parsed are not reported when the other file fails. Same root and fix as the first blind finding.
  - `[low]` `[reject]` (edge) An empty `{}` flags file is accepted after a failed boot. Same root as the no-reference finding; rejected for the same reason.
  - `[low]` `[reject]` (edge) A wrong kind already in the loaded data becomes the reference, so a fixed file is rejected. Only reachable after booting with mistyped data, which asserts in debug on first read; a restart clears it. The fix needs type knowledge beyond a direct correction.
  - `[low]` `[reject]` (edge, deletion) The removed `Config.flags.is_empty()` guard lets F5 restart with no flags. Same root as the no-reference finding.
  - `[low]` `[patch]` (edge, claim) Not every problem is named, and there are several error lines. The "not every problem" part is fixed with the first finding; the line-count part is rejected with the duplicate-logging finding.
  - `[low]` `[patch]` (edge, claim) The test comment misdescribes the third error. Same fix as the comment finding above.
  - `[low]` `[patch]` (verification-gap, other) The shape check is skipped for both files on one read error. Same root and fix as the first blind finding. The layer found no verification gaps.
  - `[low]` `[reject]` (intent) The no-reference case accepts anything (the consumer surface vs loaded-data surface). Same root as the no-reference finding.
  - `[false]` `[reject]` (intent) `load_error` is now kept on failure where the old rollback cleared it. The intent explicitly asks to "restore its own previous ... load_error", so this is the requested behaviour.
  - `[false]` `[reject]` (intent) The C2 `Events`-style reload signal is not implemented. intent.md (the contract) does not ask for it. It describes the retro's wider suggestion, not a defect in this change.
  - `[low]` `[defer]` (intent) The real F5 input → `reload_current_scene` path is untested. Pre-existing (retro B4); deferred.
  - `[false]` `[reject]` (intent) The debug log reason moved to the `[data]` line. Described as consistent with the intent; the reason is still logged.
  - `[false]` `[reject]` (intent) Array element types are not validated. Restates the array finding above with no new bad outcome; the arrays Config serves hold only strings.

### 2026-10-07 — Review pass
- verdicts: 23 findings — high 0, medium 0, low 22, false 1, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) A valid `{}` is accepted after a failed boot, and the old `flags.is_empty()` guard is gone. Carried: same as the logged no-reference row, and the code still reads as described (the spec's "No reference" row).
  - `[low]` `[reject]` (blind) After a failed flags boot, non-bool flags are not checked. Same root as the no-reference row and rejected for the same reason. It needs a type rule beyond the loaded-shape schema, for a state reached only after a broken boot.
  - `[low]` `[reject]` (blind) Keys added by one reload become required later. Carried: by design (Design Notes).
  - `[low]` `[reject]` (blind) The F5 `[debug]` line no longer carries the reason. Carried: log-only; the reason is on the adjacent `[data]` line.
  - `[low]` `[reject]` (blind) Read errors are logged twice. Carried: cosmetic; `_read_json_dict` logging is pre-existing.
  - `[low]` `[reject]` (blind) `load_data()` treats a broken flags file differently from `reload()`. The spec's Never list forbids changing `load_data()` boot behaviour. The only harm is the empty-reference state, which is already rejected.
  - `[low]` `[reject]` (blind) No test asserts the success-path `_log_summary()` line. `Log.info` only prints and there is no log-capture seam, so asserting it needs new test plumbing for a log-only line.
  - `[low]` `[reject]` (blind) Some tests prove less than their names say:
    - the `load_error == ""` asserts, and no Dictionary→number or Array→Dictionary case.
    - By reading, `_check_shape` compares kinds before it recurses, so these cases are reported correctly.
    - `test_reload_still_broken_keeps_load_error` covers a non-empty `load_error` surviving.
    - No defective behaviour was found.
  - `[low]` `[reject]` (blind) The test helpers `_real`/`_write` don't check for parse or open failure, and the code is duplicated across test files. Test-only. The real data files parse (every suite run loads them).
  - `[low]` `[reject]` (blind) JSON `null` is its own kind (`Nil`). `grep null game/data/*.json` finds no nulls, so nobody meets this today, and handling it means adding a branch.
  - `[low]` `[reject]` (edge) The reference ratchets on keys that a reload adds. Carried: by design.
  - `[low]` `[reject]` (edge) After a failed tuning boot, any object is accepted. Carried: no-reference row.
  - `[low]` `[reject]` (edge) After a failed flags boot, empty or non-bool flags are accepted. Carried: no-reference row (`{}` flags after a failed boot).
  - `[low]` `[reject]` (edge) A new key's type is ignored, e.g. a new flag set to a number. Only code that reads a key absent at boot can see it, and that code already reports the key missing at boot. A restart re-validates the key. Reaching it needs a code change, which means a restart anyway.
  - `[low]` `[reject]` (edge) Array element shapes are not checked. Carried: by design.
  - `[low]` `[reject]` (edge) A `null` reference value rejects every replacement. Same as the null row above; there are no nulls in the data.
  - `[low]` `[reject]` (edge, deletion) The removed `Config.flags.is_empty()` guard. Carried: no-reference row.
  - `[low]` `[patch]` (verification-gap) No successful-reload test applies a changed flags value, so dropping `flags = new_flags` would pass the suite. Added `test_reload_serves_changed_flag`: it flips `tarek_fall` in the temp flags file and asserts that `reload()` returns true, `Config.flag("tarek_fall")` is false, and no errors were pushed.
  - `[low]` `[reject]` (verification-gap, other) An empty `{}` flags file is accepted after a failed flags boot. Carried: no-reference row.
  - `[low]` `[reject]` (intent) Strict "one `Log.error` line" versus the per-file read lines. Carried: duplicate-logging row.
  - `[low]` `[reject]` (intent) Flags-only empty reference, including accepting `{}`. Carried: no-reference row.
  - `[low]` `[defer]` (intent) Untested real F5 → `reload_current_scene` path, and wrong-type and missing-flag cases tested only at Config level. Carried: already in this spec's `deferred` list (retro B4); not deferred again.
  - `[false]` `[reject]` (intent) `null` is compared as an exact type (R5a). It is described as a reading, not a defect, and no data holds `null`.

## Design Notes

Using the loaded data as the schema keeps validation free of a second hand-maintained key list that could drift from `tuning.json`. Any key the game had a moment ago is one some code may read, so dropping or retyping it is exactly what B1 describes. Designers can still add keys freely. Removing a key on purpose needs a restart instead of F5, which is fine for a debug tool.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failures (`<GODOT_DIR>` from `LOCAL.md`).
- `grep -rnE "Config\.(tuning|flags|load_error)\s*=" game --include=*.gd | grep -v tests/` -- expected: no output.


## Auto Run Result

Status: done (follow-up review pass)

**Summary:** `Config.reload()` returns `bool`. It reads `tuning` and `flags` into locals and checks each file that parsed against the shape of the data loaded now. It commits only when there are no problems; otherwise it logs one `Reload rejected (...)` line and leaves `tuning`, `flags` and `load_error` untouched. `DebugTools.reload_data()` branches on the result and no longer writes any `Config` field. This follow-up pass re-reviewed the whole change since the baseline and added one missing success-path test.

**Files changed (whole change since baseline):**
- `game/autoloads/config.gd`: validating `reload() -> bool` plus the `_check_shape()` and `_kind()` helpers.
- `game/ui/debug/debug_tools.gd`: `reload_data()` calls `Config.reload()`; the direct Config writes are removed.
- `game/tests/unit/test_config.gd`: reload tests for every I/O-matrix row, plus a missing file, a nested path and problems in both files. This pass added `test_reload_serves_changed_flag`.
- `game/tests/unit/test_debug_tools.gd`: `test_f5_missing_key_refuses_restart`, and the existing F5 failure tests claim the `Reload rejected` error.

**Review findings (this pass):** 23 total (22 low, 1 false).
- **Patches applied:** 1 low. Added a test showing that a successful reload serves a changed flag value (verification-gap layer).
- **Deferred:** none new. The real F5 → `reload_current_scene` path was carried from the existing `deferred` entry.
- **Rejected, with reasons (details in the Review Triage Log):**
  - No-reference cases after a failed boot: `{}` or non-bool flags are accepted, and the `flags.is_empty()` guard is gone. This is the spec's chosen behaviour, and it needs a state reached only after a broken boot.
  - The key ratchet and unchecked Array elements: by design.
  - Duplicate read-error logging, and the reason only on the `[data]` line: cosmetic.
  - The `load_data()`/`reload()` difference: the spec forbids changing `load_data()`.
  - No test for the summary log line: no log-capture seam.
  - Weak test names and untested kind swaps: the code handles them correctly by reading.
  - Test-helper robustness: test-only.
  - JSON `null` kind: no nulls in the data.
  - A new key's type is unchecked: needs a code change, so a restart anyway.
  - false: the `null` reading is not a defect.

**Follow-up review recommended:** false. This is a follow-up pass and it patched no `high` finding (patched: high 0, medium 0, low 1).

**Verification:**
- Full headless GUT suite: 288/288 passing, 0 failing, 0 pending.
- `grep -rnE "Config\.(tuning|flags|load_error)\s*=" game --include=*.gd | grep -v tests/`: no output.

**Residual risks:**
- After a failed boot there is no reference shape, so F5 accepts any parseable object, including `{}`.
- Removing a key on purpose needs a game restart instead of F5.
- The real scene-restart path is covered only by the injected `restart_scene` seam (deferred).
- Live F5 in a window was not exercised; that needs a display.
- `_bmad-output/implementation-artifacts/deferred-work.md` holds uncommitted ledger edits made by the orchestrator. Per the invocation, this run did not touch or commit them.
