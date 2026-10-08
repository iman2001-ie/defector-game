---
title: 'DW-37: harden wave-data validation and counting (retro R1, R2, R4-R7, R9)'
type: 'bugfix'
created: '2026-10-08'
status: done
baseline_revision: 6d169690e7fa250ba757dbebf281cb9f423c60fb
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
  - summary: >-
      A Needle entry authored after another entry anchors on row 0 over the earlier entry's Wasps, while the row WaveDirector reserves for it stays empty.
    evidence: |-
      needle.gd anchors at enemies.needle.anchor_y_px (160 = waves.formation.top_y) whatever its slot y, but WaveDirector._spawn_entry gives it the next free row. Only a first-in-wave Needle (as in level_dev.json wave 4) lines up. Pre-existing: before DW-37 every type advanced the row. Neither LevelValidator nor test_zoned_formations_fit_their_top_zone detects it, and no shipped wave hits it.
    location: >-
      game/systems/waves/wave_director.gd:264
    severity: low
---

<intent-contract>

## Intent

**Problem:** Valid-looking wave data can stall or stack enemies (epic-2 retro R1-R7, R9). Every group counts toward the wave total even when no trigger that names it can fire before the wave clears. A progress `at` can sit above what can resolve before its group spawns. `at`/`phase`/`hp`/`flag`/`wait`/`entry` and action keys are never type-checked. Grid columns are unbounded. The data test leaves the Bastion out of the zoned types. `WaveDirector._next_row` advances for Hunter Wasps, which hold no slot. (R5 also named Needles, but a Needle anchors at `enemies.needle.anchor_y_px` = `waves.formation.top_y` and roams that row, so it really occupies a row and keeps advancing `_next_row`.)

**Approach:** Apply the 2026-10-07 DW-37 decision. `LevelValidator` rejects unreachable groups and unreachable progress `at` values (a fixed-point simulation of the wave), type-checks the trigger, action and entry fields, and bounds grid columns. `Formation` caps grid columns to what fits the playfield width. `WaveDirector` doesn't advance `_next_row` for rowless types. The only rowless type is `hunter_wasp`; the Needle stays row-taking. The data test zones the Bastion. Each rule gets a test.

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
| Rowless types | hunter_wasp entry then a wasp entry | wasp starts on row 0 (y = top_y) | none |
| Needle takes a row | needle entry then a wasp entry | wasp starts on row 1 (y = top_y + spacing.y); shipped `level_dev.json` wave 4 keeps its Wasps at y 280 | none |

</intent-contract>

## Code Map

- `game/systems/waves/level_validator.gd` -- `validate()` :13, `_check_wave` :33 (groups :52-66, triggers :68-84), `_check_entries` :88 (add `entry` and column checks), `_check_trigger` :122 (type checks and action keys). Add the reachability pass after triggers are parsed in `_check_wave`.
- `game/systems/waves/formation.gd` -- `_columns` :41: grid columns uncapped. Add `static func max_columns(spacing: Vector2, width: float) -> int` (floori(width / spacing.x), 0 when spacing.x <= 0 means unbounded) and cap with `maxi(..., 1)`. Reuse it in the default-formation branch.
- `game/systems/waves/wave_director.gd:257-258` -- `_spawn_entry` advances `_next_row` for every type. Skip the advance when `EntityRegistry.ROWLESS_TYPES.has(type_id)`.
- `game/systems/waves/beat_trigger.gd` -- read-only. Its `should_fire` semantics (flag `!` negation, missing/non-bool flag = false) are what the reachability pass mirrors.
- `game/autoloads/entity_registry.gd` -- add `const ROWLESS_TYPES: Array[StringName] = [&"hunter_wasp"]` (not `needle`: see the Needle row in the matrix) and `func enemy_flags() -> Dictionary` (returns `ENEMY_FLAGS`, for Config's runtime lookup).
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
- `game/tests/unit/test_wave_director.gd` -- a Hunter Wasp rowless test and a Needle row-taking test (Wasps after Needles on row 1); fix the :257 expectation; update the :335 call -- R5.
- `game/tests/data/test_data_files.gd` -- pass the new args; add `&"bastion"` to `ZONED_TYPES` with its drift-box y range; the mirror skips rows for `ROWLESS_TYPES` (Hunter Wasp only); update the header doc -- R6.
- `_bmad-output/game-architecture.md:1453` -- the "every entry starts on the next free row" sentence gains the Hunter Wasp rowless exception and the grid column cap -- doc parity.

**Acceptance Criteria:**
- Given the shipped `level_dev.json`, when the GUT suite runs headless, then `test_every_level_file_is_valid` and `test_zoned_formations_fit_their_top_zone` pass and at least one Bastion entry is checked.
- Given the shipped `level_dev.json` wave 4 (Needle `grid_2x1` then Wasp `grid_4x1`), when it spawns, then the Wasps sit on row 1 (y 280) and no Wasp slot coincides with a Needle anchor.
- Given the full GUT suite, when run with the AGENTS.md command, then every test passes with 0 failures.

## Spec Change Log

- 2026-10-08 (bmad-loop-resolve): the "Reachable chain" matrix row used `at` 1.0, which can't be reached because group `b` counts toward `total` before it spawns. That contradicted the DW-37 decision, the Design Notes and the "Unreachable at" row. The row now uses 2 spawns, `a` = 4, `b` = 4, `at` 0.6 (exactly 6/10). The reachability rules are unchanged.

- 2026-10-08 (bmad-loop-resolve, Needle rows): the review found that Needles anchor on row 0 (`anchor_y_px` 160 = `top_y` 160) and roam it, so R5's premise that Needles "ignore the row" was false. Making them rowless stacked `level_dev.json` wave 4's Wasps on the Needle anchors. Human decision: the Needle keeps taking a row, and only `hunter_wasp` is rowless. The matrix now has separate "Rowless types" (hunter_wasp) and "Needle takes a row" rows, `ROWLESS_TYPES` is `[&"hunter_wasp"]`, and a wave-4 AC was added. Re-drive resumes review on the restored attempt patch (`dw-37-intent-gap-attempt.patch`), which made Needles rowless. The review must patch it to this intent: drop `&"needle"` from `ROWLESS_TYPES`, replace `test_needles_do_not_advance_the_row` with a row-1 assertion, and fix the docs that call the Needle rowless (entity_registry.gd, the wave_director.gd header, the test_data_files.gd header). Also apply the three patches carried from the blocked pass: pin the flags and type gates in `test_level_at_passes_flags_and_column_bound` (a gated `hunter_wasp` group with its flag off, plus a trigger on a known `true` flag); clear `counts_known` for a non-object entry in `_check_entries`; and update game-architecture.md:1453. Out of scope: a Needle group authored *after* a Wasp group still anchors on row 0 over those Wasps. This predates DW-37 and is a candidate deferred item.

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

### 2026-10-08 — Review pass
Follow-up pass on the `done` spec. Attempted change saved as `_bmad-output/implementation-artifacts/dw-37-intent-gap-attempt.patch` (baseline..6d16969, `game/` only). Code reverted to baseline in the working tree.
- verdicts: 22 findings — high 0, medium 2, low 15, false 5, maybe-false 0
- findings:
  - `[medium]` `[intent_gap]` Blind: making the Needle rowless stacks Needles on Wasps. `enemies.needle.anchor_y_px` (160) equals `waves.formation.top_y` (160), so a Needle sits on row 0. In `level_dev.json` wave 4 (`needle grid_2x1`, then `wasp grid_4x1`) the Wasps now take row 0 too. Two Needles anchor at (880,160) and (1040,160), exactly on two Wasp slots that the Wasps hold between dives (wasp.gd:72). Before the change, the Wasps sat on row 1 (y 280). The R5 premise "Needles ignore the row" is false, and the intent's "Rowless types" matrix row requires this outcome, so the spec can't settle the fix. Unresolved questions are under Auto Run Result.
  - `[false]` `[reject]` Blind: `Config.flags` leaks out of `test_hunter_wasps_do_not_advance_the_row` — carried: `after_each` calls `Config.load_data()` (test_wave_director.gd:53).
  - `[low]` `[reject]` Blind: levels are validated only with the shipped flag values — carried: same as the earlier flag-dependence row.
  - `[low]` `[reject]` Blind: `"!nope"` fails in the validator but passes in BeatTrigger — carried: same as the earlier empty or bare-`!` flag row.
  - `[low]` `[reject]` Blind: the "at can't be reached" message is wrong because the stall net fires the trigger late — carried: same as the earlier stall-net row.
  - `[low]` `[reject]` Blind: boss-trigger groups become permanent errors, and the boss counts 1 — carried: same as the earlier boss row.
  - `[false]` `[reject]` Blind: a missing `spacing_px.x` silently turns off the column bound — not silent: `Config.num` calls `_report_missing` (config.gd:77). The key also ships in tuning.json.
  - `[low]` `[patch]` Blind: game-architecture.md:1453 still says every entry starts on the next free row — real, and a direct doc fix. Moot this pass because of the intent_gap above.
  - `[low]` `[reject]` Blind: the column bound uses spacing, not sprite size — the widest enemy (Bastion, 160) equals the spacing today. Making the bound sprite-aware adds parameters for a case no data hits.
  - `[low]` `[reject]` Blind: untested paths (`grid_columns`, `max_columns` 0, non-string `when`, a valid `at` on a non-progress trigger, the rowless enemies' own positions) — partly carried from the earlier untested-paths row. The rest are minor and unlikely to regress.
  - `[low]` `[reject]` Edge: the boss is counted in `available` though the runtime subtracts it — carried: the earlier boss row.
  - `[low]` `[reject]` Edge: run reachability with every type gate forced true — carried: the flag-dependence row.
  - `[low]` `[reject]` Edge: the data test validates only against the current flags — carried: the flag-dependence row.
  - `[low]` `[patch]` Edge: a non-object spawn or group entry doesn't clear `counts_known` (level_validator.gd:215-217), so reachability still runs and can add follow-on problems — real, a one-line fix. Moot this pass because of the intent_gap.
  - `[low]` `[reject]` Edge: the doc claims boss counting matches the runtime — carried: the boss row.
  - `[medium]` `[patch]` Verification gap (pre-verified): `test_level_at_passes_flags_and_column_bound` doesn't pin the flags or the type gates `Config.level_at` passes. `"nope"` is unknown under `{}` too, and no gated type is used. Moot this pass because of the intent_gap; carry it into the re-derivation.
  - `[low]` `[reject]` Intent: boss counting diverges from the runtime — carried: the boss row.
  - `[low]` `[reject]` Intent: reachability is tested only on synthetic data, with no validator/director cross-check — carried: the earlier "no test cross-checks" row.
  - `[low]` `[reject]` Intent: reachability is skipped for a wave with a type or count problem — deliberate: an earlier patch avoids misleading follow-on problems, and the entry problem is still reported.
  - `[false]` `[reject]` Intent: the checks go beyond the matrix — carried: the earlier "checks go beyond the literal intent" row.
  - `[false]` `[reject]` Intent: rowless types are wired into existing tests — describes the expected test updates the spec's Code Map asks for, not a defect. The stacking consequence is the intent_gap row.
  - `[false]` `[reject]` Intent: flags are fixed at load time — `Config.flags` is only written by tests, so load-time and runtime flags agree today.

### 2026-10-08 — Review pass
Re-drive after the Needle-rows resolution (baseline 6d16969). The intent-gap attempt patch was already in HEAD, so it was not re-applied.
- verdicts: 23 findings — high 0, medium 2, low 14, false 7, maybe-false 0
- findings:
  - `[low]` `[defer]` Blind: a Needle entry after another entry anchors on row 0 over the earlier Wasps, and the row it reserves stays empty — real (needle.gd anchors at `anchor_y_px` whatever its slot y), but it predates DW-37 (before it every type advanced the row) and no shipped wave hits it; the Spec Change Log already names it a candidate deferred item. Deferred.
  - `[low]` `[reject]` Blind: a multi-row Needle grid reserves every grid row — pre-existing `rows_used` behaviour from before DW-37; no shipped data has a multi-row Needle grid, and the fix adds a type branch.
  - `[low]` `[reject]` Blind: nothing asserts `enemies.needle.anchor_y_px` = `waves.formation.top_y` — two independent tuning keys; asserting them equal would freeze a designer knob the intent doesn't freeze. Unlikely to bite, and the fix adds a new data rule.
  - `[medium]` `[patch]` Blind: the non-object `counts_known` rule has no test — grouped with the verification-gap row. Fixed: added `test_non_object_entry_skips_reachability` (spawns and group cases); the implementer confirmed it fails with line 218 removed.
  - `[low]` `[patch]` Blind: `test_level_at_passes_flags_and_column_bound` asserts the shipped `flags.json` values, so it breaks when the Hunter Wasp flag ships enabled — fixed: the test sets `surrender_prompts` true and `hunter_wasp` false itself (after_each reloads Config).
  - `[false]` `[reject]` Blind: `errors.size() == 2` doesn't check which errors — refuted: the count of 2 together with the two `assert_push_error` strings pins exactly the column and unknown-flag problems.
  - `[low]` `[reject]` Blind: redundant `assert_ne` and hard-coded 280/160 in tests — the 280 pins the spec AC ("Wasps at y 280") against the shipped tuning; row_1 itself is read from Config. The 160 in `_assert_rowless` is pre-existing. Cosmetic.
  - `[low]` `[reject]` Blind: the `_assert_rowless` helper is now single-use with a generic parameter — cosmetic; its doc names the Hunter Wasp correctly.
  - `[false]` `[reject]` Blind: the architecture line is unclear about whether column wrap is the contract — refuted: the line states both, the runtime wrap and the validator rejection, which is exactly the matrix's "validator problem; runtime bounded".
  - `[false]` `[reject]` Blind: the Needle reversal has no decision record — refuted: the human decision is recorded in this spec's Change Log (2026-10-08 bmad-loop-resolve, Needle rows).
  - `[low]` `[defer]` Edge: a non-first Needle entry overlaps earlier Wasps (entity_registry.gd:22) — same root cause as the first Blind row; deferred with it.
  - `[low]` `[reject]` Edge: a multi-row Needle grid pushes later entries down (wave_director.gd:264) — same as the Blind multi-row row.
  - `[low]` `[reject]` Edge: anchor_y_px may be tuned away from top_y — same as the Blind anchor row.
  - `[low]` `[reject]` Edge: clearing `counts_known` for a non-object entry hides reachability problems in that wave — deliberate per the Spec Change Log patch; the wave already fails validation on the entry problem, so the level is still rejected.
  - `[low]` `[defer]` Edge: the data-test mirror passes while a non-first Needle overlaps Wasps — same root cause as the first Blind row; deferred with it.
  - `[low]` `[defer]` Edge (claim): "the Needle takes a row" holds only when its entry is first — same root cause as the first Blind row; deferred with it.
  - `[medium]` `[patch]` Verification gap (pre-verified): no test proves a non-object spawn or group entry turns off reachability — fixed with `test_non_object_entry_skips_reachability` (see the Blind row).
  - `[low]` `[patch]` Intent: `test_needles_take_a_row` built a synthetic copy of wave 4 rather than the shipped `level_dev.json` wave 4 the AC names — fixed: the test now loads `Config.level("dev")` and starts its wave 4 (index 3).
  - `[low]` `[patch]` Intent: the data test checks only zones, not y 280 for wave 4 — same root cause as the previous row; fixed by the same test change.
  - `[false]` `[reject]` Intent: the Hunter Wasp and Needle cases are tested differently — descriptive, not a defect; both matrix rows have covering tests that pass.
  - `[false]` `[reject]` Intent: the non-object change is untested — duplicate of the verification-gap row, now patched.
  - `[false]` `[reject]` Intent: reachability, field checks, column bound and Bastion zoning aren't in this diff — refuted: they landed in 6d16969 with their tests, which ran and passed in this pass's full suite.
  - `[false]` `[reject]` Intent: `deferred-work.md` is staged and an attempt patch is untracked — refuted: those are the orchestrator's ledger edit and the resolve artifact, not part of this diff.

### 2026-10-08 — Review pass
Follow-up pass on the `done` spec (baseline 6d16969, reviewed through c1fa084).
- verdicts: 19 findings — high 0, medium 0, low 16, false 3, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: `test_non_object_entry_skips_reachability` can't prove the line it covers matters — refuted: without `counts_known[0] = false` the fixture is 4/8 = 0.5 < 0.7, which adds `.at` and `groups.g` problems, so `_assert_one` fails. The previous pass's implementer confirmed this with line 218 removed.
  - `[low]` `[defer]` Blind: a Needle entry after another entry anchors on row 0, while docs say flatly that it takes a row — carried: same root cause as the deferred non-first Needle row; already in the frontmatter `deferred` list.
  - `[low]` `[reject]` Blind: `test_needles_take_a_row` depends on shipped wave 4 and has no synthetic needle-then-wasp case — the AC names the shipped wave 4, which is itself a needle-then-wasp case (the earlier pass moved the test to shipped data on purpose). A shipped-data change that breaks it fails loudly.
  - `[false]` `[reject]` Blind: a non-object `groups` value doesn't clear `counts_known`, so follow-on reachability problems appear — refuted: `groups` stays `{}`, so `total` is gated spawns only and every one of them resolves. The ratio reaches 1.0 (or 1.0 at 0/0), so no valid `at` is reported unreachable. Only the `.groups` and unknown-group problems appear.
  - `[low]` `[reject]` Blind: `_assert_rowless` is single-use — carried: the earlier `_assert_rowless` cosmetic row.
  - `[low]` `[patch]` Blind: the doc for the skipped reachability sits on the `_unreachable_wave` helper, not on the test — fixed: the doc moved onto `test_non_object_entry_skips_reachability`, and the helper got a one-line doc. The suggested rename of `test_level_at_passes_flags_and_column_bound` wasn't done: type gates come from the same `level_at` call, and the test's doc already explains them.
  - `[low]` `[reject]` Blind: the exact count of 2 in test_config.gd can miss problems logged under another category — the validator's problems all go through `Log.error("data", ...)` in `level_at`. The verification-gap layer confirmed each wrong argument adds a counted data error. Cosmetic hardening.
  - `[low]` `[defer]` Edge: a Needle entry on row 1 or later anchors on row 0 (entity_registry.gd:22) — carried: the deferred non-first Needle row.
  - `[low]` `[reject]` Edge: a multi-row Needle grid, or two Needle entries, uses up several rows — carried: the earlier multi-row Needle row.
  - `[low]` `[reject]` Edge: `anchor_y_px` may be tuned away from `top_y` — carried: the earlier anchor row.
  - `[low]` `[reject]` Edge: `test_needles_take_a_row` errors if `level_dev.json` has fewer than 4 waves — an index error is a loud test failure, which is the correct outcome when the shipped data the AC names changes.
  - `[low]` `[reject]` Edge: the size-2 assertion breaks if the logging category changes — same as the Blind exact-count row.
  - `[low]` `[defer]` Edge (claim): Needle row-taking holds only when the Needle comes first — carried: the deferred non-first Needle row.
  - `[low]` `[defer]` Edge (claim): the wave_director.gd doc "the Needle takes a row" misleads authors — carried: the deferred non-first Needle row.
  - `[low]` `[defer]` Verification gap (other): the Needle row rule holds only for a first Needle entry — carried: the deferred non-first Needle row.
  - `[low]` `[reject]` Intent: a non-object entry suppresses truly unreachable `at`/group problems — carried: the earlier "clearing `counts_known` hides reachability problems" row.
  - `[low]` `[reject]` Intent: the Needle row is proven only through shipped data — same as the Blind shipped-wave-4 row.
  - `[low]` `[reject]` Intent: nothing shows the column bound comes from Config and `Playfield.SIZE.x` rather than a literal — config.gd reads `waves.formation.spacing_px.x` and `Playfield.SIZE.x` (visible in 6d16969). A test that pins the source would have to change tuning, and that regression is unlikely.
  - `[false]` `[reject]` Intent: most matrix rows aren't in this diff — carried: they landed in 6d16969 with their tests, which passed in this pass's full suite.

## Design Notes

Reachability (per wave): `total` = gated counts of spawns + every group + 1 for a boss. `available` = gated spawns + boss. Iterate to a fixed point. A trigger can fire when its flag passes and its `when` is `wave_start`, or `progress` with `available >= 1` and `float(available) / float(total) >= at` (`total == 0`: ratio 1.0). `wave_clear` and `boss_*` never count, because the wave has already cleared or isn't evaluated yet. When a trigger fires, each of its `spawn_group` groups is marked spawned and its count added to `available`. Afterwards: a group named by some trigger but never marked spawned is a problem, and the existing "never named" problem stays as-is for unnamed groups. A `progress` trigger whose flag passes, whose `at` is valid, and which never fired gets a problem at `.at` naming `available/total`.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: completes (no class_name changes, but cheap)
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass



## Auto Run Result

Status: done

**Summary:** Follow-up review pass on DW-37 (diff 6d16969..c1fa084). Four review layers found nothing high or medium. One low finding was patched: a doc comment in `test_level_validator.gd` was moved onto the test it describes. No code behaviour changed in this pass. The DW-37 implementation itself (reachability, field and action checks, column cap, Hunter Wasp rowless, Needle takes a row, Bastion zoning) is described in the Spec Change Log and the earlier triage entries.

**Files changed (this pass):**
- `game/tests/unit/test_level_validator.gd`: the doc on skipped reachability moved from the `_unreachable_wave` helper to `test_non_object_entry_skips_reachability`; the helper got a one-line doc.

**Review findings:** 19 in total (low 16, false 3).
- **Patched:** 1 low (the doc placement). 0 high, 0 medium.
- **Deferred:** none new. Five rows were carried into the existing deferred item for a non-first Needle entry.
- **Rejected:** 13, each with its reason in this pass's Review Triage Log entry. Two of them are refuted claims: the non-object test can't fail, and a non-object `groups` cascades.

**Follow-up review recommendation:** false. This was a follow-up pass and it patched no high entry (patched by verdict: high 0, medium 0, low 1).

**Verification:**
- `--import` exited 0.
- Full GUT suite (AGENTS.md command) after the patch: 890 tests, 890 passed, 0 failures, 0 pending.

**Residual risks:**
- A Needle entry that isn't first in its wave still anchors over earlier Wasps (deferred).
- Validity still depends on the current flags.json values, and the boss counts 1 in the validator.
- No one has checked the wave 4 layout on screen.
