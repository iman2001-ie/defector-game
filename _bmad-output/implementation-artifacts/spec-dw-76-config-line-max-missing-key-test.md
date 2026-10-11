---
title: 'DW-76: Config test for missing comms line-max tuning keys'
type: 'chore'
created: '2026-10-11'
baseline_revision: 'c7727a68d2b3c7896f822ae14d74fe575b9831f7'
status: 'done'
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

**Problem:** No test covers `Config` loading dialogue with a tuning dictionary that lacks `comms.story_line_max_chars` or `comms.combat_line_max_chars`. The single `Log.error` per key ("... line length not checked") and the `-1` (no limit) fallback from `_line_max_chars` (`game/autoloads/config.gd:267`; the ledger cites line 253 from an older revision) are untested, because every test loads the real tuning where both keys exist (DW-76).

**Approach:** Add GUT tests to `game/tests/unit/test_config.gd` that call `Config._load_dialogue` with a temp dialogue dir and an in-memory copy of the real tuning with both keys erased, asserting exactly one error per key and that over-long story and combat lines are accepted (the `-1` fallback means no length check). Add a direct `_line_max_chars` test for the `-1` return, including the empty-tuning (no log) and wrong-type branches.

## Boundaries & Constraints

**Always:**
- Test-only: no change to `game/autoloads/config.gd` or any production file.
- Reuse the existing helpers in `test_config.gd` (`_real`, `_write_dialogue`, `_clear_temp_dialogue`, `TEMP_DIALOGUE_DIR`); clean the temp dialogue dir up at the end of each test that writes it.
- Statically typed GDScript; every pushed error is claimed with `assert_push_error` and counted with `assert_push_error_count`, so no unexpected error slips through.
- The tuning copy must be non-empty (real tuning minus the two keys), so the logging branch runs.

**Never:** Edit shipped data (`game/data/*`), add fixture files to `res://`, edit the deferred-work ledger, or touch `Config`'s global loaded state beyond what `after_each` already restores.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Both keys missing, via `_load_dialogue` | Real tuning minus `comms.story_line_max_chars` and `comms.combat_line_max_chars`; temp dir with a 201+ char story line and a 51+ char combat line | Both sequences returned; `read_problems` empty | Exactly 2 pushed errors: one `[ERROR][data] tuning.comms.story_line_max_chars missing or not a number; story line length not checked`, one for `combat_line_max_chars` / `combat` |
| Key missing, direct helper | Same tuning copy; `_line_max_chars(tuning, key, kind)` for each key | Returns `-1` for each | One error per call naming the key and kind |
| Key not a number | Tuning copy with `comms.story_line_max_chars` = `"200"` (string) | Returns `-1` | One "missing or not a number" error |
| Empty tuning (failed tuning load) | `{}` | Returns `-1` for both keys | No error logged (`assert_push_error_count(0)`) |

</intent-contract>

## Code Map

- `game/autoloads/config.gd:210` -- `_load_dialogue(dir, tuning_data, read_problems)`: reads `max_chars`/`combat_max_chars` once each via `_story_max_chars`/`_combat_max_chars`, then validates every sequence. Callable from tests on the `Config` autoload.
- `game/autoloads/config.gd:257-273` -- `_story_max_chars`, `_combat_max_chars`, `_line_max_chars`: returns the int, else logs `"tuning.%s missing or not a number; %s line length not checked" % [key, kind]` when `tuning_data` is non-empty, and returns `-1`. Constants `STORY_MAX_CHARS_KEY`, `COMBAT_MAX_CHARS_KEY` at lines 16-17.
- `game/systems/comms/dialogue_validator.gd:103-106` -- a negative limit skips the length check (why over-long lines pass with `-1`).
- `game/autoloads/log.gd` -- `Log.error` prints and `push_error`s `"[ERROR][data] <msg>"`, so GUT's `assert_push_error` sees it.
- `game/tests/unit/test_config.gd:521-545` -- dialogue test section: `TEMP_DIALOGUE_DIR`, `_clear_temp_dialogue`, `_write_dialogue`, `_story`; `_real` at line 60. `after_each` reloads real data. Add new tests at the end of this section (end of file).
- `game/tests/fixtures/dialogue/bad/e_combat.json` -- example combat sequence shape (`mode: combat`, one line, speaker `isolde`).

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_config.gd` -- add (1) a `_load_dialogue` test with both keys erased from a copy of the real tuning, writing a temp story sequence with a >200 char line and a temp combat sequence with a >50 char line; (2) a direct `_line_max_chars` test for missing key, non-number value and empty tuning -- covers DW-76 without production changes.

**Acceptance Criteria:**
- Given a tuning copy lacking both line-max keys, when `Config._load_dialogue` runs on a temp dir with over-long story and combat lines, then it returns both sequences, appends nothing to `read_problems`, and exactly one "line length not checked" error is pushed per key (2 total).
- Given a tuning copy lacking a key or holding a non-number, when `_line_max_chars` runs for it, then it returns `-1` and pushes one error; given `{}`, it returns `-1` and pushes none.
- Given the full GUT suite runs headless, then all tests pass.

## Spec Change Log

## Review Triage Log

### 2026-10-11 — Review pass
- verdicts: 17 findings — high 0, medium 0, low 2, false 8, maybe-false 0 (7 rejected as out of scope or not worth fixing, counted under their own verdict rows below)
- findings:
  - `[low]` `[patch]` (blind) Over-long lengths 201/51 hard-coded to current tuning; a raised limit would silently stop proving the -1 fallback — patched: lengths now derived from the real tuning's limits plus one.
  - `[false]` `[reject]` (blind) No control case shows the same lines are rejected with the keys present — `test_bad_dialogue_files_are_logged_and_skipped` already asserts 201-char story and 51-char combat lines are rejected under real tuning.
  - `[false]` `[reject]` (blind) Only both-keys-missing tested, so a swapped key goes unnoticed — the per-key error texts are claimed individually (a wrapper reading the wrong key fails `assert_push_error`), and swapped limit order in `_load_dialogue` is caught by the existing bad-dialogue test.
  - `[low]` `[patch]` (blind) Doc comment on `test_line_max_chars_falls_back_to_no_limit` describes the empty-tuning case that lives in another, uncommented test — patched: sentence moved onto the empty-tuning test with a DW-76 tag.
  - `[false]` `[reject]` (blind) Success branch of `_line_max_chars` never tested — the existing bad-dialogue test's "201 characters, more than 200" / "51 characters, more than 50" messages prove the real limits are read.
  - `[low]` `[reject]` (blind) Other wrong types (null, bool, Array, missing `comms`) untested — all reach the same `_lookup` branch already covered by the missing and string cases; extra tests add bulk for no new path.
  - `[false]` `[reject]` (blind) Two identical story errors not tied to their calls — only three direct calls run; a silent missing-key call would make `assert_push_error_count(3)` fail.
  - `[false]` `[reject]` (blind) Helper crashes if `comms` is renamed / literal key strings — a crash or unerased key fails the test loudly, which is correct behaviour for a test fixture.
  - `[low]` `[reject]` (blind) Public `reload()` path not exercised — the intent explicitly scopes the test to `_load_dialogue` with a tuning dictionary.
  - `[low]` `[reject]` (blind) Spec gaps (line numbers, empty logs, no `--import` note) — fix would edit this build's spec.
  - `[low]` `[patch]` (edge) Shipped limits raised to 201+/51+ makes the test vacuous — same root cause as the first blind finding; covered by that patch.
  - `[low]` `[reject]` (edge) Negative tuning value disables length checks without an error — pre-existing production behaviour; the intent is test-only, and shipped tuning is positive.
  - `[low]` `[reject]` (edge) Fractional float limit truncates silently — negligible; a guard would add production branches the test-only intent excludes.
  - `[false]` `[reject]` (edge) Real tuning without `comms` crashes the helper — a loud failure in a test fixture is the desired outcome.
  - `[false]` `[reject]` (intent) Literal -1 asserted only at the helper, not through `_load_dialogue` — `_load_dialogue` exposes the limit only by behaviour; the diff asserts both the behaviour and the literal value, matching the intent.
  - `[low]` `[patch]` (intent) Indirect check one-sided at the shipped limits — same root cause as the first blind finding; covered by that patch.
  - `[false]` `[reject]` (intent) Real tuning-load path not exercised — the intent names `_load_dialogue` with a tuning dictionary as the surface; no divergence from it.
  - (verification-gap layer: no gaps found)

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, including the new ones in `test_config.gd`.

## Auto Run Result

Status: done

**Summary:** Added three GUT tests to `game/tests/unit/test_config.gd` covering DW-76: `_load_dialogue` with a real-tuning copy lacking both `comms.*_line_max_chars` keys logs exactly one "line length not checked" error per key and accepts story/combat lines one character over the shipped limits; `_line_max_chars` returns `-1` for a missing or non-number key (one error each) and for empty tuning (no error). Test-only; no production change.

**Files changed:**
- `game/tests/unit/test_config.gd` -- two helpers (`_tuning_without_line_max`, `_line_max_error`) and three DW-76 tests.
- `_bmad-output/implementation-artifacts/spec-dw-76-config-line-max-missing-key-test.md` -- this spec.

**Review findings:** 17 findings. Patches applied: 2 entries (both `low`): lengths derived from real tuning plus one (grouped with the matching edge and intent findings), and a misplaced doc comment moved. Deferred: none. Rejected: every other finding, with reasons in the Review Triage Log (existing coverage, loud fixture failures, out of scope by the test-only intent, or spec-only edits).

**Follow-up review recommendation:** false — first pass patched 0 high and 0 medium entries (2 low).

**Verification:** full headless GUT suite run twice (after implementation and after patches): 1622/1622 tests passing, exit 0.

**Residual risks:** none notable; the tests call private `Config` methods, as other tests in this file already do.
