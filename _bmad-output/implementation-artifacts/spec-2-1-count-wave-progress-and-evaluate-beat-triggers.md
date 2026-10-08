---
title: 'Story 2.1: Count Wave Progress and Evaluate Beat Triggers'
type: 'feature'
created: '2026-10-07'
status: 'done'
baseline_revision: '1174d59f3c829b0ffcfbd780c8e73b2565f7884d'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-2-context.md'
warnings: ['oversized']
deferred:
  - summary: >-
      The Bastion's y 80–400 drift range may let a large sprite overlap the 0–120 px HUD band and the wave bar.
    evidence: |-
      Pre-existing in the plan, not caused by Story 2.1: GDD gdd.md L269 and epics.md FR22/L829 set "y 80–400", while the UX layout puts the HUD band at 0–120 and the wave bar at y 40. Whether a sprite actually overlaps depends on the Bastion's sprite size and how its y is clamped. To settle it, check the Bastion story (Epic 2) against DESIGN.md's layout bands before building the Bastion.
    location: >-
      _bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md:269
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** Epic 2's Wave Director (Story 2.2) needs two small rule classes it can trust: one that counts wave progress so a wave always clears (even when a spawn fails), and one that decides whether a data-authored beat trigger fires. These don't exist yet, and the clear and trigger rules are the parts most likely to soft-lock a wave or misfire a story beat.

**Approach:** Add two pure `RefCounted` classes, `WaveProgress` and `BeatTrigger`, in `game/systems/waves/`. They follow the architecture's Novel Pattern #1 (game-architecture.md L729-808) exactly, and GUT unit tests cover every rule. Nothing in the running game uses them yet. Story 2.2 wires them in.

## Boundaries & Constraints

**Always:**
- Both classes `extends RefCounted` with a `class_name`, are statically typed, and depend on nothing else: no autoloads (`Config`, `Log`, `Events`), no nodes, no scene tree. Callers pass flags in as a `Dictionary`.
- Keep the architecture's API names: `WaveProgress.total_counted`, `resolved`, `ratio()`, `is_complete()`, `reset(total)`; `BeatTrigger.has_fired`, `actions`, `should_fire(event, ratio, flags) -> bool`.
- `should_fire` is a pure query. It never sets `has_fired`, because the Director sets that when it runs the actions (architecture L821).
- JSON numbers arrive as floats, so convert `phase` with `int()` and read `at` and `hp` as `float`.

**Never:**
- No WaveDirector, level JSON, `Config.level`, Events signals, HUD or data-file test. Those belong to Stories 2.2 and 2.3.
- No action execution (`spawn_group`, `wait`, `comms`...). `BeatTrigger` only stores `actions`.
- Don't hard-code any GDD tuning number (gap, thresholds). These classes contain none.
- Don't edit `sprint-status.yaml`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior |
|----------|--------------|---------------------------|
| Progress ratio | `reset(8)`, 2 resolves | `ratio()` 0.25, `is_complete()` false |
| Wave completes | `reset(3)`, 3 resolves | `ratio()` 1.0, `is_complete()` true |
| Failed spawn | `reset(5)`, `remove_from_total(2)`, 3 resolves | `total_counted` 3, complete, ratio 1.0 |
| Over-resolve guard | `reset(2)`, 3 resolves | `resolved` stays 2, still complete (no soft-lock) |
| Empty wave | `reset(0)` (or every spawn removed) | `ratio()` 1.0, `is_complete()` true, no divide-by-zero |
| Reset clears | resolves, then `reset(4)` | `resolved` 0, `total_counted` 4 |
| Progress threshold | `{when: progress, at: 0.3}` | false at 0.29, true at 0.3 and at 0.5 |
| Wrong event | `{when: wave_start}` called with `&"progress"` | false |
| wave_start / wave_clear | matching event | true |
| Flag passes / fails | `flag: "x"` with `{x: true}` / `{x: false}` | true / false |
| Negated flag | `flag: "!x"` with `{x: true}` / `{x: false}` | false / true |
| Missing flag key | `flag: "x"` / `"!x"` with `{}` | false / true (a missing flag counts as false) |
| Fires once | `has_fired = true` | always false |
| boss_phase | `{when: boss_phase, phase: 2}` | true for value 2.0, false for 1.0 |
| boss_hp_le | `{when: boss_hp_le, hp: 50}` | true for value 50 and 30, false for 51 |
| Unknown `when` | `{when: "bogus"}` | false for every event |

</intent-contract>

## Code Map

- `game/systems/` -- only `camera/shake_camera.gd` exists. Create the new `waves/` folder here (architecture L670 and L1289 place waves in `systems/waves/`).
- `game/ui/debug/debug_args.gd` -- a style reference for a pure class: `class_name` first, then `extends RefCounted`, a `##` doc block, typed consts and statics.
- `game/tests/unit/test_debug_args.gd` -- a style reference for tests: `extends GutTest`, a `##` one-line header, `func test_x() -> void:`, and every assert carries a short message.
- `game/data/flags.json` -- real flag names (`surrender_prompts`, `hunter_wasp`...), all bools. `Config.flags` is the raw `Dictionary` the Director will pass to `should_fire`.
- `_bmad-output/game-architecture.md` L783-808 -- the rules and the Director excerpt that show how 2.2 will call these classes. Read it, but don't edit it.
- `*.gd.uid` files are tracked in git. After `--import`, commit the new `.uid` files next to the scripts.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_wave_progress.gd` -- write first (red): one test per WaveProgress row of the I/O matrix.
- `game/tests/unit/test_beat_trigger.gd` -- write first (red): one test per BeatTrigger row of the matrix, plus construction from a JSON-shaped dict (float `phase`, `actions` kept in order, missing optional keys default safely).
- `game/systems/waves/wave_progress.gd` -- `class_name WaveProgress`. Typed public `total_counted: int` and `resolved: int`. `reset(total: int)` sets resolved to 0 and total to max(total, 0). `resolve()` adds 1 but never goes past the total. `remove_from_total(count: int = 1)` lowers the total, never below 0, and clamps resolved to the new total. `ratio()` returns resolved / total, or 1.0 when the total is 0. `is_complete()` returns `resolved == total_counted`.
- `game/systems/waves/beat_trigger.gd` -- `class_name BeatTrigger`. `_init(data: Dictionary)` stores `when: StringName`, `at: float` (default 0.0), `phase: int` (default 0), `hp: float` (default 0.0), `flag: String` (default ""), `actions: Array[Dictionary]` (only the Dictionary entries, in order) and `has_fired: bool = false`. `should_fire(event: StringName, value: float, flags: Dictionary) -> bool`. The Design Notes describe the rules.
- Run `--import` (new `class_name` scripts), then the full GUT suite.

**Acceptance Criteria:**
- Given the new files, when the headless GUT suite runs, then `test_wave_progress.gd` and `test_beat_trigger.gd` pass, cover every I/O-matrix row, and every test that already existed still passes.
- Given `WaveProgress` and `BeatTrigger`, when their sources are inspected, then neither references an autoload, a Node or the scene tree, and every variable, parameter and return value is typed.
- Given the game is launched normally, when it boots into the sandbox, then nothing has changed in behaviour (the classes are unused until 2.2).

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 26 findings — high 0, medium 0, low 13, false 13, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: WaveProgress fields are public, so the architecture's `_progress.resolved += 1` excerpt skips the clamp and an over-resolve would soft-lock — the Enemy contract emits `resolved` exactly once, so this needs a contract bug plus 2.2 ignoring `resolve()`; making the fields read-only adds surface. Noted for 2.2 under residual risks.
  - `[low]` `[reject]` Blind: `remove_from_total()` with a negative count raises the total — no caller exists and the Director only ever subtracts failed entries (a positive count); the fix would add a guard.
  - `[low]` `[patch]` Blind: the header "The wave can never soft-lock" overclaims beyond counting — fixed: reworded to "Counting can never soft-lock the wave".
  - `[false]` `[reject]` Blind: bad trigger data (unknown `when`, missing `at`/`phase`/`hp`) fails silently with no `is_valid()` — validating level JSON (known `when`, `at` in 0–1, referenced groups) is assigned to Story 2.2's `tests/data/test_data_files.gd` (epic-2-context L51), not to these pure classes, which the spec keeps free of `Log`.
  - `[low]` `[reject]` Blind: JSON `null` values become `"<null>"` or fail in `float()` — designers don't write `null` for these keys and 2.2's data test validates triggers; the fix adds a type guard per field.
  - `[false]` `[reject]` Blind: `at` is not range-checked — the 0–1 range is checked by 2.2's data test (epic-2-context L51), by design.
  - `[false]` `[reject]` Blind: no re-arm, and `actions` share references with the level data — triggers are built per attempt by the Director (2.2), and the architecture's `_run_actions` only reads actions; nothing mutates them.
  - `[false]` `[reject]` Blind: `boss_phase` truncates and uses enum ordinals — the phase arrives from `Events.boss_phase_changed(phase: int)`, so int→float→int is exact; the integer `phase` field is the architecture's own data shape (L785).
  - `[low]` `[reject]` Blind: `"!"`, `"!!x"` and whitespace flag edge cases — authoring typos that are unlikely in practice; the fix adds branches.
  - `[low]` `[patch]` Blind: `boss_hp_le` doesn't say whether `hp` is absolute or a fraction — fixed: the class header and the `should_fire` doc now say absolute hit points.
  - `[low]` `[reject]` Edge: a null, array or dict value for `at`/`phase`/`hp`/`flag` errors on construction — same root as the Blind null finding; rejected for the same reason.
  - `[false]` `[reject]` Edge: `at` > 1 or ≤ 0 misfires — same as the Blind `at` finding; range validation is 2.2's data test.
  - `[low]` `[reject]` Edge: a progress trigger with no `at` defaults to 0.0 and fires on the first kill — the default is spec-mandated, the pure class may not log, and data validation lives in 2.2; the fix adds a warning branch.
  - `[false]` `[reject]` Edge: `actions` hold references to the source dictionaries — nothing mutates actions (architecture L823 only reads them).
  - `[low]` `[reject]` Edge: a bare `"!"` or `"!!x"` flag always passes — same as the Blind flag finding.
  - `[false]` `[reject]` Edge: a fractional `boss_phase` value truncates — the phase source is an int signal, so a fractional value can't occur.
  - `[low]` `[reject]` Edge: a negative `remove_from_total` count leads to a soft-lock — same as the Blind negative-count finding.
  - `[low]` `[reject]` Edge: over-resolve is silently absorbed, hiding accounting bugs — the clamp is the spec's chosen no-soft-lock behaviour; a double resolve needs a broken Enemy contract, and the pure class may not log.
  - `[false]` `[reject]` Edge: `remove_from_total` clamping discards real resolves — a failed spawn never existed, so the resolves can't exceed the live total minus the failed entries; the clamp only triggers on misuse.
  - `[false]` `[reject]` Intent (a): once-only firing depends on the caller setting `has_fired` — that matches the architecture (L821, `_run_actions` sets it), and `test_has_fired_blocks` checks the gate.
  - `[low]` `[reject]` Intent (b): the second parameter is renamed `value` and carries three meanings, which isn't recorded in the architecture — the call shape is unchanged and the meaning is documented on the method; no design decision changed.
  - `[low]` `[reject]` Intent (c): the architecture excerpt's direct `resolved += 1` skips the clamp — same root as the first Blind finding; noted for 2.2.
  - `[false]` `[reject]` Intent (d): a real spawn failure isn't wired to `remove_from_total` — wiring it belongs to Story 2.2 by the epic's own split.
  - `[false]` `[reject]` Intent (e): the tests use synthetic flags, not the real `flags.json` names — the class reads an arbitrary dictionary; the names don't affect behaviour.
  - `[false]` `[reject]` Intent (f): the diff carries no evidence of the runtime ACs — the verification run shows 370/370 passing, and the boot is unchanged by construction (the classes are unreferenced).
  - `[false]` `[reject]` Intent (g): `is_complete()` ignores running action chains — that half of wave clear belongs to the Director (architecture L791), per Story 2.1's AC ("only when resolved == total").

### 2026-10-07 — Review pass
- verdicts: 23 findings — high 0, medium 0, low 11, false 11, maybe-false 1
- findings:
  - `[false]` `[reject]` Blind: Hunter Wasp spawns gated off by the flag may sit in the total and block the clear — epic-2-context L30 says those spawns are "skipped, not counted", so they never enter the total. Building the total is the Director's job (2.2), and `remove_from_total()` exists if they ever need subtracting.
  - `[false]` `[reject]` Blind: `remove_from_total()` raises the ratio without a resolve, so nothing rechecks triggers, the bar or the clear — the class returns the right ratio and completion after the subtraction (test_failed_spawn). When to recheck is the Director's call sequence in 2.2, and no caller exists in this diff. Noted under residual risks.
  - `[false]` `[reject]` Blind: fires-once is tested only by setting `has_fired` by hand — the class's half of the contract is "has_fired blocks it" (test_has_fired_blocks) and "should_fire doesn't set it" (test_should_fire_does_not_set_has_fired). The marking belongs to the Director (architecture L821).
  - `[false]` `[reject]` Blind: no reset for `has_fired` between attempts — carried: same as the earlier "no re-arm" row; the Director builds triggers per attempt.
  - `[false]` `[reject]` Blind: the flag gate is tested only with `wave_start` — `_flag_passes` runs at beat_trigger.gd L90, before the `match`, for every `when`. A flagged progress or boss trigger can't skip the gate.
  - `[low]` `[patch]` Blind: test_construct_from_json_shape casts the parse result without checking it, so a broken fixture fails with confusing messages — fixed: added `assert_typeof(data, TYPE_DICTIONARY, ...)` before the cast.
  - `[low]` `[reject]` Blind: epic-2-context.md says `should_fire(event, ratio, flags)` with no `hp` unit, which disagrees with the class's `value` and its "absolute hit points" — carried: same root as the earlier Intent (b) row. The class doc is authoritative; the context file is a recompiled cache that mirrors the architecture.
  - `[maybe-false]` `[defer]` Blind: the Bastion's y 80–400 drift range may overlap the 0–120 HUD band — pre-existing in the GDD (L269) and epics (FR22), not caused by this story. Overlap depends on sprite size and the y clamp; check against DESIGN.md when the Bastion is built. Deferred as medium (unverified).
  - `[false]` `[reject]` Blind: the WaveProgress header leaves out contact destroys and other resolve paths — `destroy_by_contact()` goes through `_die()` (enemy.gd L56-74), so it is a kill. An exit that doesn't resolve isn't a resolve, so the header doesn't need to list it.
  - `[low]` `[reject]` Blind: over-resolve and `remove_from_total` misuse are absorbed without a trace (suggests bool returns) — carried: same as the earlier "over-resolve silently absorbed" row.
  - `[low]` `[reject]` Edge: a negative `remove_from_total` count can soft-lock — carried: same as the earlier negative-count rows.
  - `[low]` `[reject]` Edge: a fresh instance reports complete (ratio 1.0) before `reset()` — needs a Director that queries before starting the wave (architecture calls `reset` at wave start), and the fix adds a guard field.
  - `[low]` `[reject]` Edge: null, Array or Dictionary values for `at`/`phase`/`hp` error on construction — carried: same as the earlier null/type rows.
  - `[low]` `[reject]` Edge: a bare `"!"` flag always passes — carried: same as the earlier flag-edge rows.
  - `[low]` `[reject]` Edge: `"!!x"` or whitespace in a flag looks up the wrong key — carried: same as the earlier flag-edge rows.
  - `[low]` `[reject]` Edge: a progress trigger with `at` missing, above 1 or NaN — carried: same as the earlier missing-`at` and `at`-range rows (data validation is 2.2's data test).
  - `[false]` `[reject]` Edge: actions are stored by reference to the level data — carried: nothing mutates actions (architecture L823 only reads them).
  - `[false]` `[reject]` Edge: a fractional `boss_phase` value truncates — carried: the phase comes from an int signal.
  - `[low]` `[reject]` Intent 1: the architecture excerpt's `_progress.resolved += 1` skips the clamp, and strict `==` then soft-locks — carried: same as the earlier Blind/Intent (c) rows; noted for 2.2 under residual risks.
  - `[low]` `[reject]` Intent 2: the parameter is named `value`, not `ratio` — carried: same as the earlier Intent (b) row.
  - `[false]` `[reject]` Intent 3: a non-bool flag such as `1` counts as false — every value in game/data/flags.json is a bool, and the class header documents the rule.
  - `[false]` `[reject]` Intent 4: the class decides its own construction surface (a Dictionary in `_init`) — descriptive only; the Tasks section specifies `_init(data: Dictionary)`, so there is no bad outcome.
  - `[false]` `[reject]` Intent 5: `remove_from_total` re-clamps `resolved` beyond the intent — carried: same as the earlier "clamping discards real resolves" row.

## Design Notes

**The `value` parameter.** The architecture's signature is `should_fire(event, ratio, flags)`, but `boss_phase` and `boss_hp_le` also need a number to compare, and that signature has only one numeric slot. So the second parameter is a general-purpose `value`. It is the wave ratio for `progress`, the new phase for `boss_phase` and the boss HP for `boss_hp_le`. The call shape stays as the architecture describes, and the Director passes `0.0` for `wave_start` and `wave_clear`. Document this on the method.

Rule order in `should_fire`:

```gdscript
if has_fired or event != when or not _flag_passes(flags): return false
match when:
	&"wave_start", &"wave_clear": return true
	&"progress": return value >= at
	&"boss_phase": return int(value) == phase
	&"boss_hp_le": return value <= hp
return false
```

`_flag_passes` works like this:
- An empty `flag` passes.
- Otherwise strip a leading `"!"`, read `flags.get(name, false)` and treat any value that isn't a bool as false.
- Invert the result when the flag was negated.

A missing key therefore counts as false, which matches the default-off convention in `flags.json`.

**Over-resolve clamp.** The AC says complete means exactly `resolved == total`. Clamping in `resolve()` and `remove_from_total()` keeps that equality reachable even if a resolve arrives twice, so a wave can't soft-lock past its total.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits cleanly; the `class_name` cache includes WaveProgress and BeatTrigger.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failures, and the new test scripts appear in the run.


## Auto Run Result

Status: done (follow-up review pass)

**Summary:** This pass re-reviewed Story 2.1's two pure `RefCounted` rule classes and their GUT tests:
- `WaveProgress` counts resolves against a clamped total. It handles a failed spawn with `remove_from_total()`, and an empty wave counts as complete.
- `BeatTrigger` decides whether a trigger fires from `when`, `at`, `phase`, `hp`, flags (with `!` negation) and `has_fired`.

The running game still doesn't use either class. Story 2.2 wires them in.

**Files changed (this story, since baseline):**
- `game/systems/waves/wave_progress.gd` (+ `.uid`): `WaveProgress`.
- `game/systems/waves/beat_trigger.gd` (+ `.uid`): `BeatTrigger`, with a pure `should_fire(event, value, flags)`.
- `game/tests/unit/test_wave_progress.gd` (+ `.uid`): 10 tests for the WaveProgress rows of the matrix.
- `game/tests/unit/test_beat_trigger.gd` (+ `.uid`): 16 tests for the BeatTrigger rows. This pass added a parse check to the JSON-shape test.
- `_bmad-output/implementation-artifacts/epic-2-context.md`: compiled Epic 2 planning context.

**Review findings (this pass):** 23 in total. Low 11, false 11, maybe-false 1; no high or medium.
- Patched (1, low): `test_construct_from_json_shape` now asserts the fixture parses to a Dictionary before the cast.
- Deferred (1): the Bastion's y 80–400 drift range may overlap the HUD band. This is pre-existing in the GDD and epics, and graded medium (unverified).
- Rejected: 10 low and 11 false. Fourteen of those repeat rows from the first pass. The new ones were refuted by the code: the flag gate runs before the `match`, contact destroys go through `_die()`, every value in `flags.json` is a bool, and so on. Every reason is in the Review Triage Log.
- Follow-up review recommended: **false**. This is a follow-up pass and no high finding was patched. Patched by verdict: high 0, medium 0, low 1.

**Verification:**
- `--import` exited 0.
- The full headless GUT suite passed: 30 scripts, 370/370 tests, 2088 asserts.
- The verification-gap layer found no gaps.

**Residual risks:**
- Story 2.2 must call `WaveProgress.resolve()`, not the architecture excerpt's `_progress.resolved += 1`. The direct write skips the clamp, and `is_complete()` uses strict equality.
- Story 2.2 must recheck the clear, the bar and the progress triggers after `remove_from_total()`. A subtraction can change the ratio, or finish the wave, with no resolve following it.
- Story 2.2's data test must validate trigger data: a known `when`, an `at` in 0–1, and sane flag strings.
- No feel or playtest claim is made; these are logic-only classes.
