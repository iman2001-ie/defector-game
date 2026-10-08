---
title: 'DW-37: harden wave-data validation and counting (retro R1, R2, R4-R7, R9)'
type: 'bugfix'
created: '2026-10-08'
status: done
baseline_revision: e71820b0f097a97fe1e2273d1c2c1ec33f0ca31d
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-2-retro-2026-10-07.md'
warnings: ['oversized']
deferred:
  - summary: >-
      LevelValidator doesn't detect a group named by more than one spawn_group action that can fire in the same wave.
    evidence: |-
      WaveDirector._request_group logs a WARN and ignores a second request for an already-spawned group (wave_director.gd:319); the validator's reachability pass accepts duplicate naming. Pre-existing, not introduced by DW-37.
    location: >-
      game/systems/waves/level_validator.gd
    severity: low
---

<intent-contract>

## Intent

**Problem:** Valid-looking wave data can stall or stack enemies (epic-2 retro R1-R7, R9). Every group counts toward the wave total even when no trigger that names it can fire before the wave clears. A progress `at` can sit above what can resolve before its group spawns. `at`/`phase`/`hp`/`flag`/`wait`/`entry` and action keys are never type-checked. Grid columns are unbounded. The data test leaves the Bastion out of the zoned types. `WaveDirector._next_row` advances for Needles and Hunter Wasps, which use only the slot's x.

**Approach:** Apply the 2026-10-07 DW-37 decision. `LevelValidator` rejects unreachable groups and unreachable progress `at` values (a fixed-point simulation of the wave), type-checks the trigger, action and entry fields, and bounds grid columns. `Formation` caps grid columns to what fits the playfield width. `WaveDirector` doesn't advance `_next_row` for rowless types. The data test zones the Bastion. Each rule gets a test.

## Boundaries & Constraints

**Always:** Statically typed GDScript. `LevelValidator` and `Formation` stay pure (no autoload reads inside them). The validator gets flags, type gates and the column bound as arguments. Reachability mirrors runtime counting: a type whose `EntityRegistry.ENEMY_FLAGS` flag isn't `true` counts 0, the boss counts 1, and progress triggers fire only on a resolve (k/total for k = 1..available, the same float division as `WaveProgress.ratio()`). Problems keep the `<source> <key path>: <message>` shape. Tuning comes from `Config` (`waves.formation.spacing_px.x`) and `Playfield.SIZE.x`. Don't hard-code 12.

**Never:** Don't change runtime counting or stall-net behaviour in `WaveDirector` (the decision makes unreachable groups a validation error, not uncounted). Don't fix R8 (`at: 0` fires after the first kill; deferred). Don't edit `deferred-work.md`, `sprint-status.yaml`, `level_dev.json` or `flags.json`. Don't hard-code a boss phase maximum.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Reachable chain | 2 spawns; group `a` of 4, group `b` of 4; wave_start spawns `a`; progress `at` 0.6 spawns `b` | no problem (after `a` spawns, 6 of the 10 counted can resolve: 6/10 = 0.6 >= `at`). A group's own count is in `total` before it spawns, so `at` 1.0 here would be unreachable (see "Unreachable at") | none |
| wave_clear group | only a `wave_clear` trigger names group `g` | problem at `groups.g` | validator problem |
| Flag off / negated pair | `flag: "off"` names `g` / `flag` + `!flag` both name `g` | problem at `groups.g` / no problem | validator problem |
| Unknown flag | `flag: "nope"` or non-string | problem at `triggers[i].flag` (and `groups.g` if that was its only route) | validator problem |
| boss_* group | only `boss_phase`/`boss_hp_le` names `g` | problem at `groups.g` | validator problem |
| Unreachable at | 6 spawns, group of 4, `at` 0.7 | problems at `triggers[i].at` and `groups.g` | validator problem |
| Field types | `at`/`hp` non-number; `phase` non-integer or < 1 on boss_phase; `hp` < 0 on boss_hp_le; `wait` non-number or < 0; `entry` not `top`/`sides`; comms/story_event/music/spawn_group not a non-empty string | one problem at that key path | validator problem |
| Action keys | `{ "dance": 1 }`, `{}`, `{ "wait": 1, "comms": "x" }` | one problem at `actions[i]` | validator problem |
| Wide grid | `grid_13x1` with max_columns 12 | problem at `.formation`; `Formation.slots` wraps it to rows of 12, all x within [spacing.x/2, width - spacing.x/2] | validator problem; runtime bounded |
| Rowless types | needle/hunter_wasp entry then a wasp entry | wasp starts on row 0 (y = top_y) | none |

</intent-contract>

## Code Map

- `game/systems/waves/level_validator.gd` -- `validate()` :13, `_check_wave` :33 (groups :52-66, triggers :68-84), `_check_entries` :88 (add `entry` and column checks), `_check_trigger` :122 (type checks and action keys). Add the reachability pass after triggers are parsed in `_check_wave`.
- `game/systems/waves/formation.gd` -- `_columns` :41: grid columns uncapped. Add `static func max_columns(spacing: Vector2, width: float) -> int` (floori(width / spacing.x), 0 when spacing.x <= 0 means unbounded) and cap with `maxi(..., 1)`. Reuse it in the default-formation branch.
- `game/systems/waves/wave_director.gd:257-258` -- `_spawn_entry` advances `_next_row` for every type. Skip the advance when `EntityRegistry.ROWLESS_TYPES.has(type_id)`.
- `game/systems/waves/beat_trigger.gd` -- read-only. Its `should_fire` semantics (flag `!` negation, missing/non-bool flag = false) are what the reachability pass mirrors.
- `game/autoloads/entity_registry.gd` -- add `const ROWLESS_TYPES: Array[StringName] = [&"needle", &"hunter_wasp"]` and `func enemy_flags() -> Dictionary` (returns `ENEMY_FLAGS`, for Config's runtime lookup).
- `game/autoloads/config.gd:111-135` -- `level_at` calls `LevelValidator.validate`. Pass `flags`, the registry's `enemy_flags()` via `registry.call` (same pattern as `_known_enemy_types` :127; no static EntityRegistry reference), and `Formation.max_columns(...)`.
- `game/core/enemy.gd:14-15` -- `Enemy.ENTRY_TOP`/`ENTRY_SIDES`, the valid `entry` values.
- `game/entities/enemies/bastion/bastion.gd:66-80` -- the drift box y range is [band_y.min + half, band_y.max - half]; slots outside it are clamped with a WARN.
- `game/tests/unit/test_level_validator.gd` -- `_validate` :27 and `_assert_one` :32 helpers. The `_valid()` fixture must keep validating.
- `game/tests/unit/test_formation.gd`, `game/tests/unit/test_wave_director.gd` (`test_flag_on_spawns_counted_hunters` :257 asserts the wasps at y 280; after this change they're at 160; validator call :335), `game/tests/data/test_data_files.gd` (validate call :32; `ZONED_TYPES` :138 and the row-mirror loop :146-194), `game/tests/unit/test_level.gd:456-480` (Bastion row 0).

## Tasks & Acceptance

**Execution:**
- `game/autoloads/entity_registry.gd` -- add `ROWLESS_TYPES` and `enemy_flags()` -- one source for rowless types and the gate map.
- `game/systems/waves/formation.gd` -- add `max_columns`, cap grid columns, update the class doc -- R7 at runtime.
- `game/systems/waves/level_validator.gd` -- new signature `validate(data, source, known_types, flags: Dictionary, type_flags: Dictionary, max_columns: int)`; checks from the matrix; reachability pass; doc comment lists the rules -- R1, R2, R4, R7, R9.
- `game/systems/waves/wave_director.gd` -- rowless types don't advance `_next_row`; update the header doc -- R5.
- `game/autoloads/config.gd` -- pass the new arguments -- runtime logging keeps working.
- `game/tests/unit/test_level_validator.gd` -- update `_validate`; add one test per matrix row -- coverage.
- `game/tests/unit/test_formation.gd` -- a wide-grid cap test plus `max_columns` -- R7.
- `game/tests/unit/test_wave_director.gd` -- a Needle/Hunter rowless test; fix the :257 expectation; update the :335 call -- R5.
- `game/tests/data/test_data_files.gd` -- pass the new args; add `&"bastion"` to `ZONED_TYPES` with its drift-box y range; the mirror skips rows for `ROWLESS_TYPES`; update the header doc -- R6.

**Acceptance Criteria:**
- Given the shipped `level_dev.json`, when the GUT suite runs headless, then `test_every_level_file_is_valid` and `test_zoned_formations_fit_their_top_zone` pass and at least one Bastion entry is checked.
- Given the full GUT suite, when run with the AGENTS.md command, then every test passes with 0 failures.

## Spec Change Log

- 2026-10-08 (bmad-loop-resolve): the "Reachable chain" matrix row used `at` 1.0, which can't be reached because group `b` counts toward `total` before it spawns. That contradicted the DW-37 decision, the Design Notes and the "Unreachable at" row. The row now uses 2 spawns, `a` = 4, `b` = 4, `at` 0.6 (exactly 6/10). The reachability rules are unchanged.

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 26 findings — high 0, medium 2, low 20, false 4, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind: reachability still ran when `spawns` or a group wasn't an array, adding misleading `.at`/group problems — patched: those branches now clear `counts_known`.
  - `[low]` `[reject]` Blind: `flag: ""` / `"!"` pass in BeatTrigger but the validator reports them as unknown — the data is still rejected with an explicit problem; the authoring case is unlikely and mirroring it would add a branch.
  - `[low]` `[defer]` Blind: a group named by two triggers that can both fire isn't detected (the runtime WARNs and ignores the second request) — a pre-existing gap DW-37 didn't introduce; deferred.
  - `[low]` `[reject]` Blind: the validator counts the boss as 1 resolvable, but today's runtime subtracts it at once (Epic 7 stub) — the spec's Design Notes fix the boss at 1; no level has a boss wave yet and the stall net prevents soft-locks.
  - `[false]` `[reject]` Blind: `test_hunter_wasps_do_not_advance_the_row` leaks `Config.flags` — `after_each` calls `Config.load_data()`, which reloads flags.json.
  - `[low]` `[reject]` Blind: validity depends on the current flags.json values — this is the decision's "flag that is off" reading; flipping a flag in flags.json re-runs the data test against the new value; checking every combination adds complexity.
  - `[low]` `[patch]` Blind: dead `total == 0` branch in `_can_fire` — patched: branch removed.
  - `[low]` `[reject]` Blind: no tests for the skip path, `max_columns == 0`, `grid_columns()`, the non-boss `phase` message, or `_enemy_flags()` without a registry — the skip path is already exercised by `test_count_must_be_positive_integer`; the rest are minor and unlikely to regress.
  - `[low]` `[patch]` Blind: test_data_files.gd header was badly wrapped and the "flag-gated types take their rows" doc was stale — patched: header reflowed, stale sentence removed.
  - `[low]` `[patch]` Blind: rowless entries share row 0 with the next entry (Hunter Wasp sides entry starts at the slot's y), against a doc that said "only x" — the behaviour is what the intent asks for; patched the docs in entity_registry.gd and the wave_director.gd header.
  - `[low]` `[patch]` Edge: `max_columns` returned 0 (unbounded) when spacing.x > width — patched: returns at least 1 when spacing.x > 0; assertion added.
  - `[low]` `[reject]` Edge: empty or bare-`!` flag mismatch — same as the Blind flag row; rejected for the same reason.
  - `[low]` `[reject]` Edge: when every counted entry is flag-gated off (0/0), the `at` is reported as unreachable — same root cause as the flag-dependence row; it follows the spec's `available >= 1` rule.
  - `[low]` `[reject]` Edge: the boss-count claim — same as the Blind boss row.
  - `[low]` `[reject]` Edge: the stall net can fire an "unreachable" progress trigger late, at ratio 1.0 — the decision makes such data a validation error whatever happens late at runtime; only the wording of the message is affected.
  - `[low]` `[patch]` Edge: the "only the slot's x" claim is wrong for a sides-entry Hunter Wasp — grouped with the rowless doc row; patched there.
  - `[low]` `[reject]` Edge: numeric `spawn_group` adds an extra "never named" problem — already reported as a non-string problem; unlikely to occur.
  - `[medium]` `[patch]` Verification gap: the new validator inputs `Config.level_at` passes were untested at the load boundary — patched: added `test_level_at_passes_flags_and_column_bound` in test_config.gd (grid_13x1 plus an unknown flag; both errors asserted).
  - `[false]` `[reject]` Verification gap (other): Config.flags leak — refuted the same way as the Blind row (`after_each` reloads flags).
  - `[low]` `[reject]` Verification gap (other): flag-dependent validity — same as the Blind flag-dependence row.
  - `[false]` `[reject]` Intent: only the validator changes, not the BeatTrigger runtime — the decision chooses "validation error" in so many words; Config logging and then returning data is existing behaviour.
  - `[low]` `[reject]` Intent: no test cross-checks the validator against the director, and the boss counting differs — same as the Blind boss row.
  - `[medium]` `[patch]` Intent: the Config wiring isn't exercised — same as the verification-gap row; patched by the same test.
  - `[low]` `[reject]` Intent: validity depends on the flags — same as the Blind flag-dependence row.
  - `[false]` `[reject]` Intent: checks go beyond the literal intent (action values, phase/hp on any trigger) — the spec matrix calls for them; not a defect.
  - `[low]` `[reject]` Intent: no negative test for a misplaced Bastion — the rule is itself a test change, and the shipped-data test now requires at least one Bastion entry to be checked; a negative test would mean refactoring the helper.

## Design Notes

Reachability (per wave): `total` = gated counts of spawns + every group + 1 for a boss. `available` = gated spawns + boss. Iterate to a fixed point. A trigger can fire when its flag passes and its `when` is `wave_start`, or `progress` with `available >= 1` and `float(available) / float(total) >= at` (`total == 0`: ratio 1.0). `wave_clear` and `boss_*` never count, because the wave has already cleared or isn't evaluated yet. When a trigger fires, each of its `spawn_group` groups is marked spawned and its count added to `available`. Afterwards: a group named by some trigger but never marked spawned is a problem, and the existing "never named" problem stays as-is for unnamed groups. A `progress` trigger whose flag passes, whose `at` is valid, and which never fired gets a problem at `.at` naming `available/total`.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: completes (no class_name changes, but cheap)
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass

## Auto Run Result

Status: done

**Summary:** Implemented the 2026-10-07 DW-37 decision. LevelValidator now runs a fixed-point reachability pass (it rejects groups whose triggers can never fire, and progress `at` values that can't be reached). It type-checks `at`/`phase`/`hp`/`flag` (against flags.json)/`entry`/action values, rejects unknown or multiple action keys, and bounds grid columns. Formation caps grid columns to the playfield width. WaveDirector no longer advances `_next_row` for Needles and Hunter Wasps. The data test zones the Bastion by its drift box.

**Files changed:**
- `game/systems/waves/level_validator.gd`: new signature `(data, source, known_types, flags, type_flags, max_columns)`; field, action, entry and column checks; reachability pass.
- `game/systems/waves/formation.gd`: `max_columns()` (at least 1 when spacing > 0) and `grid_columns()`; grid columns capped.
- `game/systems/waves/wave_director.gd`: rowless types don't advance the row; header doc.
- `game/autoloads/entity_registry.gd`: `ROWLESS_TYPES` and `enemy_flags()`.
- `game/autoloads/config.gd`: `level_at` passes flags, the type gates and the column bound.
- `game/tests/unit/test_level_validator.gd`: one or more tests per matrix row.
- `game/tests/unit/test_formation.gd`: `max_columns` and wide-grid wrap tests.
- `game/tests/unit/test_wave_director.gd`: Needle and Hunter Wasp rowless tests; the hunters test now expects y 160.
- `game/tests/unit/test_config.gd`: a test for the `level_at` wiring.
- `game/tests/data/test_data_files.gd`: new validator arguments; Bastion added to `ZONED_TYPES` (drift box); rowless types skipped in the row mirror.

**Review findings:** 26 in total. 7 entries patched: 1 medium (the Config wiring test) and 6 low (the non-array skip, the dead branch, the data-test docs, the rowless docs, the `max_columns` floor). 1 deferred: duplicate group requests are not detected. 18 rejected, each with its reason in the Review Triage Log above.

**Follow-up review recommendation:** false. A first pass patched 0 high entries and 1 medium entry.

**Verification:** `--import` exited 0. The full GUT suite (AGENTS.md command) gave 889 of 889 passing, 0 failures, before and after the patches (888, plus the new Config test). Every matrix row has a covering test that ran and passed.

**Residual risks:**
- Validity depends on the current flags.json values.
- The boss counts 1 in the validator, while the Epic 7 stub subtracts it at runtime.
- level_dev waves 4 and 6 now place their Wasps on row 0 (y 160). Nobody has checked this on screen.
