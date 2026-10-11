---
title: 'DW-67, DW-68: LevelValidator rejects duplicate group requests and a Needle that is not the first row-taker'
type: 'bugfix'
created: '2026-10-10'
status: 'done'
baseline_revision: b3952769bc6cc6de0003594e6d1637b06e057adc
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
warnings: ['oversized']
deferred:
  - summary: >-
      A single needle entry that spans more than one formation row (count above max_columns, or a grid_CxR with R > 1) reserves rows 1..n that stay empty, and Needles in the same column overlap on row 0.
    evidence: |-
      Formation.slots wraps or stacks the entry over several rows and WaveDirector advances _next_row by Formation.rows_used, but needle.gd anchors every Needle at enemies.needle.anchor_y_px whatever its slot y. DW-68's rule only checks the entries before a Needle, not how many rows the Needle entry itself takes. No shipped wave does this (both Needle entries are grid_2x1).
    location: >-
      game/systems/waves/level_validator.gd:_check_anchored_list
    severity: low
  - summary: >-
      Nothing enforces enemies.needle.anchor_y_px == waves.formation.top_y, which the "Needle is the first row-taker" rule (DW-68) takes for granted.
    evidence: |-
      test_needle_tuning_ranges only checks that anchor_y_px is inside the enemy zone. If either tuning value changes, even a first-in-wave Needle stops lining up with row 0. Pre-existing tuning coupling; not introduced by this change.
    location: >-
      game/tests/data/test_data_files.gd:test_needle_tuning_ranges
    severity: low
---

<intent-contract>

## Intent

**Problem:** Two kinds of valid-looking wave data misbehave at runtime and `LevelValidator` accepts both. (DW-67) A group named by more than one `spawn_group` action that can fire in the same wave: `WaveDirector._request_group` (wave_director.gd:387-395) spawns it once and only WARNs on the second request. (DW-68) A Needle entry after another row-taking entry: `needle.gd` always anchors at `enemies.needle.anchor_y_px` (= `waves.formation.top_y`, row 0), while `WaveDirector._spawn_entry` reserved the next free row for it, so it sits over the earlier entry's row and its own row stays empty.

**Approach:** Add two rules to `LevelValidator`, each with GUT tests. DW-67: a second `spawn_group` action naming the same group, in a trigger whose flag passes, is a problem (mutually exclusive `flag` / `!flag` pairs stay valid, as in the architecture's own example). DW-68 (operator decision 2026-10-10, "Validator: Needle must be first row-taker"): a `needle` entry that follows, or may follow, another row-taking entry in the same wave is a problem. The validator learns which types are rowless through a new `rowless_types` argument (it stays pure). Document both rules in the architecture's wave-data notes. Shipped level data must still validate cleanly.

## Boundaries & Constraints

**Always:** Statically typed GDScript. `LevelValidator` stays pure: no autoload reads inside it, so `Config` passes the rowless types it reads at runtime from `EntityRegistry` (through `registry.call`, the same pattern as `_enemy_flags()`; no static `EntityRegistry` reference from `Config`). Problems keep the `<source> <key path>: <message>` shape. Every existing `test_level_validator.gd` test keeps passing, including `test_negated_flag_pair_reaches_the_group`.

**Never:** Don't change `WaveDirector`, `needle.gd`, `Formation` or any runtime spawning or counting. Don't edit `deferred-work.md`, `sprint-status.yaml`, `.bmad-loop/` or any `game/data/levels/*.json` file. Don't make the GDD, UX or epics documents say anything new (wave composition in the GDD is an unordered list; order is authoring data).

## I/O & Edge-Case Matrix

Row-taking entry: an object entry with a known `type` not in `rowless_types` and a positive integer `count` (flags are ignored: a gated type still takes a row when its flag is on). Unknown types and bad counts are already problems and don't count as row-takers.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Duplicate request | two `wave_start` triggers (or two actions in one trigger) both `spawn_group: "g"` | one problem at the second action's `.spawn_group` path, naming the first action's path | validator problem |
| Exclusive pair | `flag: "on"` and `flag: "!on"` both name `g` | no problem | none |
| One flag off | `flag: "off"` names `g`, an unflagged `wave_start` names `g` | no duplicate problem (the off trigger can't fire) | none |
| Both pass, any `when` | `wave_start` and `wave_clear` (no flags) both name `g` | duplicate problem at the `wave_clear` action | validator problem |
| Needle first | spawns `[needle, wasp]` | no problem | none |
| Needle after row-taker | spawns `[wasp, needle]`, or `[needle, needle]` (two entries) | one problem at `spawns[1].type` | validator problem |
| Rowless before Needle | spawns `[hunter_wasp, needle]` with `hunter_wasp` in `rowless_types` | no problem | none |
| Needle in group after spawns | spawns `[wasp]`, group `g: [needle]` | problem at `groups.g[0].type` | validator problem |
| Needle in group after group entry | group `g: [wasp, needle]` | problem at `groups.g[1].type` | validator problem |
| Needle in group, other group row-taking | spawns `[]` or rowless only, `g: [needle]`, `h: [wasp]` (both named) | problem at `groups.g[0].type` (group `h` may spawn first) | validator problem |
| Needle-only group, rowless spawns | spawns `[hunter_wasp]`, `g: [needle]` | no problem | none |

</intent-contract>

## Code Map

- `game/systems/waves/level_validator.gd` -- `validate()` signature (add `rowless_types: Array[StringName]` after `type_flags`, store it in `ctx`); class doc "Rules:" list (add both rules); `_check_wave` (after triggers are parsed, run the duplicate check over `parsed` records; run the Needle check over `spawns` and `groups`); `_check_trigger` builds the record (add the action path of each valid `spawn_group` so the duplicate message can name it -- e.g. a `group_paths: Array[String]` parallel to `groups`). `record.flag_passes` is the "can fire" test. Add a `const` for the anchored type id `&"needle"` with a doc line.
- `game/autoloads/entity_registry.gd:18-24` -- `ROWLESS_TYPES` (`hunter_wasp`, `maul`). Add `func rowless_types() -> Array[StringName]` next to `enemy_flags()`.
- `game/autoloads/config.gd:160` -- the only runtime `validate` call. Add `_rowless_types()` modelled on `_enemy_flags()` :180-186 (ERROR log and empty array without the registry) and pass it.
- `game/systems/waves/wave_director.gd:332-339` -- read-only: rows advance per entry unless the type is rowless; spawns first, then each group when requested (`_spawn_group`), `_next_row` reset per wave. `_request_group` :387-395 -- read-only: second request WARNs and is ignored.
- `game/tests/unit/test_level_validator.gd` -- `_validate` :31 (pass a rowless list, e.g. `[&"hunter_wasp"]`; add `&"needle"` to `_known`); `_wave()` helper and `_assert_one` :35 to reuse. New tests for every matrix row.
- `game/tests/data/test_data_files.gd:98` -- validate call: pass `EntityRegistry.rowless_types()`. Shipped levels must stay `[]` (only `level_dev.json` and `level_dev_ally.json` wave 4 have Needles, both first).
- `game/tests/unit/test_wave_director.gd:393-410` -- `test_cut_story_level_3_wave_2_shape_validates_and_clears` lists bastion before needle and asserts it validates: put the needle entry first (the GDD Level 3 table is unordered composition), keep every other assertion, and pass `EntityRegistry.rowless_types()` at :404.
- `_bmad-output/game-architecture.md:1504` -- the `waves.formation` wave-data note: add the Needle rule. Near :806 (wave data "Rules (unambiguous)" list): add the one-request-per-group rule.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_level_validator.gd` -- write failing tests first for every I/O matrix row -- red before green.
- `game/autoloads/entity_registry.gd` -- add `rowless_types()` -- runtime lookup source.
- `game/systems/waves/level_validator.gd` -- add the `rowless_types` argument, the duplicate-request rule and the first-row-taker Needle rule; update the class doc -- DW-67, DW-68.
- `game/autoloads/config.gd` -- add `_rowless_types()` and pass it -- runtime validation uses the rule.
- `game/tests/data/test_data_files.gd`, `game/tests/unit/test_wave_director.gd` -- update the validate calls; reorder the Level 3 fixture -- callers compile and the fixture follows the rule.
- `_bmad-output/game-architecture.md` -- document both rules (cite DW-67, DW-68 and the 2026-10-10 operator decision) -- wave-data notes.

**Acceptance Criteria:**
- Given every shipped `game/data/levels/*.json`, when `test_every_level_file_is_valid` runs, then it reports no problems.
- Given a level with a Needle after a Wasp entry, when `Config.level_at` loads it, then the problem is logged through `Log.error("data", ...)` (the runtime call passes the registry's rowless types).
- Given the full GUT suite, when run headless, then all tests pass.

## Design Notes

Groups spawn at runtime in trigger order, which the validator can't fix statically, so a Needle in group `g` must have no row-taker before it in its own group, none in `spawns`, and none in any other group of the wave (conservative "may follow"). Message examples:
`... waves[0].spawns[1].type: needle must be the first row-taking entry in its wave (it anchors on row 0 at enemies.needle.anchor_y_px) but follows waves[0].spawns[0]`
`... waves[0].triggers[1].actions[0].spawn_group: group 'g' is already requested by waves[0].triggers[0].actions[0]; WaveDirector spawns a group once and ignores a second request`

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: completes (refreshes the class cache)
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failing (`<GODOT_DIR>` from `LOCAL.md`)

## Spec Change Log

## Review Triage Log

### 2026-10-10 — Review pass
- verdicts: 19 findings — high 0, medium 0, low 14, false 5, maybe-false 0
- findings:
  - `[false]` `[reject]` (blind) DW-67 judges duplicates under the current flags, not real exclusivity — Config.level_at re-validates against the live flags on every load and the data test uses the shipped flags, so any duplicate that can fire with the flags in force is reported; same semantics as the DW-37 reachability pass.
  - `[low]` `[reject]` (blind) the group "may follow" rule rejects orders that are fixed by the data (same chain, later `when`) — deliberate conservative rule (Design Notes, class doc, architecture note); only Needles placed in groups are affected and none ship; ordering analysis would add real complexity.
  - `[low]` `[patch]` (blind) groups requested only by flag-failing triggers still count as rivals — `_check_anchored_entries` now builds the set of groups requested by flag-passing triggers and uses it for the rival filter; test added.
  - `[low]` `[defer]` (blind) a single Needle entry spanning several rows isn't caught — not part of DW-68's "follows another entry" rule and no shipped wave does it; deferred.
  - `[low]` `[patch]` (blind) a Needle entry with count 0 / invalid gets an extra anchor problem — the Needle check now requires `_is_row_taker`; test added (one `.count` problem only).
  - `[low]` `[patch]` (blind) missing tests (Config wiring, gated row-taker, flag-off rival group, two Needle-only groups, maul in fixture) — added Config.level_at rowless test, gated-row-taker test and flag-gated rival-group test; two Needle-only groups follow the already-tested may-follow path and the unit fixture is synthetic (the data test uses the real ROWLESS_TYPES), so those two parts were not added.
  - `[false]` `[reject]` (blind) Level 3 wave 2 fixture reorder silently changes a design artifact — gdd.md:399 lists composition only ("2 Bastions, 2 Needles, ..."), no authoring order; the change is test data with a comment citing DW-68.
  - `[false]` `[reject]` (blind) ledger and decision log not touched — the intent forbids editing the ledger (the orchestrator closes it); the operator decision lives in the orchestrator's decisions store and is cited in the architecture note.
  - `[low]` `[defer]` (blind) architecture placement / unenforced anchor_y_px == top_y assumption — placement follows the intent ("wave-data notes", the waves.formation note); the tuning-coupling part is pre-existing and deferred.
  - `[false]` `[reject]` (blind) hard-coded ANCHORED_TYPE breaks the "caller passes the types" contract — the contract is "no autoload reads", which still holds; the message names the Needle's own tuning key, so a generic passed-in list would not make it more correct.
  - `[low]` `[patch]` (edge) exclusive flag/!flag groups give a false "may follow" — same fix as the flag-passing request set above.
  - `[low]` `[patch]` (edge) a Needle group that is never requested (or only by flag-failing triggers) is still checked — such groups are now skipped; the unreachable/unnamed rules already report them.
  - `[low]` `[patch]` (edge) Needle with count 0 / non-integer reported — same fix as the `_is_row_taker` gate above.
  - `[low]` `[patch]` (verification-gap) Config.level_at's rowless-types wiring untested — added `test_level_at_passes_rowless_types` in test_config.gd (maul before needle: no error; wasp before needle: one `.type` error).
  - `[low]` `[patch]` (verification-gap, other) count asymmetry between the Needle check and `_is_row_taker` — resolved by the same gate.
  - `[low]` `[reject]` (intent) DW-67 is stricter than "can fire": a flag-passing trigger that never fires still counts — only boss_* triggers in a non-boss wave never fire at runtime (wave_clear does fire and would WARN); unlikely, and modelling it adds complexity.
  - `[low]` `[reject]` (intent) flag-disabled types counted as row-takers — documented conservative choice; the only gated type (hunter_wasp) is rowless, so it has no effect today.
  - `[low]` `[reject]` (intent) no test ties the validator rule to a running WaveDirector — the runtime row behaviour is already pinned by test_needles_take_a_row and test_dev_wave_4_has_needles_and_cover; the change is validator-only.
  - `[false]` `[reject]` (intent) stale line references in the ledger — informational; the diff does not depend on them.

## Auto Run Result

Status: done

**Summary:** `LevelValidator` now enforces two wave-data rules. DW-67: a second `spawn_group` action naming the same group, in a trigger whose flag passes, is a problem at that action (exclusive `flag` / `!flag` pairs stay valid). DW-68 (operator decision 2026-10-10): a `needle` entry that follows, or may follow, another row-taking entry of its wave is a problem at its `.type`. Groups only count when a flag-passing trigger requests them. The validator stays pure: it gets the rowless types through a new `rowless_types` argument, which `Config` reads from `EntityRegistry.rowless_types()` at runtime. All shipped levels still validate cleanly.

**Files changed:**
- `game/systems/waves/level_validator.gd` -- the `rowless_types` argument, the duplicate-request and first-row-taker Needle rules, class doc.
- `game/autoloads/entity_registry.gd` -- `rowless_types()`.
- `game/autoloads/config.gd` -- `_rowless_types()` passed to the runtime validate call.
- `game/tests/unit/test_level_validator.gd` -- 15 new tests (every I/O matrix row plus the review cases).
- `game/tests/unit/test_config.gd` -- `test_level_at_passes_rowless_types`.
- `game/tests/data/test_data_files.gd`, `game/tests/unit/test_wave_director.gd` -- new argument; the Level 3 wave 2 fixture lists the Needle first.
- `_bmad-output/game-architecture.md` -- the one-request-per-group rule (wave-data rules list) and the Needle rule (waves.formation note).

**Review findings:** 19 findings: 9 patched (all low), 2 deferred (low: a multi-row Needle entry; the unenforced anchor_y_px == top_y coupling), 8 rejected (5 false, 3 low). The reasons are in the Review Triage Log.

**Follow-up review recommendation:** false (patched by verdict: high 0, medium 0, low 9).

**Verification:** `--import` exit 0; the full headless GUT suite gives 85 scripts, 1602/1602 tests passing and no script or parse errors. That includes `test_every_level_file_is_valid` and every new test.

**Residual risks:** Needles in groups are judged conservatively ("may follow" any other requested row-taking group), and gated row-takers are treated as taking a row, so some layouts that would line up at runtime are rejected. Both are documented. No shipped wave has a Needle in a group.
