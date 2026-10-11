---
title: 'DW-20, DW-71, DW-72: player guard hardening (resume tick, missing bubble, non-positive hearts)'
type: 'bugfix'
created: '2026-10-10'
status: 'done'
baseline_revision: 'f028772d92c1e2e66358c53e49bc6810327507ec'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Three unguarded Player edges: (DW-20) after `Player._on_resumed` warps the cursor onto the ship, the next physics tick may still read the pre-warp viewport mouse position and jump the ship one tick; (DW-71) `PlayerShield`'s missing-bubble path (`Log.error` plus null-safe `raise`/`step`/`drop`) has no test; (DW-72) a non-positive `player.hearts` tuning value makes the ship silently unhittable (`current` 0, `can_take` false, no warning).

**Approach:** (DW-20, operator decision 2026-10-10) remember the resume warp target and, on the first `step_lock` after the warp, use that target instead of the passed mouse position. (DW-71) add a GUT test for a `PlayerShield` with no bubble. (DW-72) in `HealthComponent.setup`, log an error and clamp a `p_max_value` below 1 to 1; tests at the component and at the Player surface.

## Boundaries & Constraints

**Always:** Statically typed GDScript; logging only through `Log` (`Log.error` pushes an error, so tests claim it with `assert_push_error`); the guard is consumed by exactly one `step_lock` call; shipped tuning (`player.hearts` = 5) behaves exactly as before; tests that mutate `Config.tuning` restore it with `Config.load_data()` in `after_each`.

**Never:** No change to `game/data/*.json`; no new `warp_mouse` call sites; no change to PauseArbiter, mouse modes or `_physics_process` input reads beyond what the guard needs; don't arm the guard when `_on_resumed` doesn't warp (VISIBLE mode or out of tree); don't touch the deferred-work ledger.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Stale tick after resume warp | CONFINED_HIDDEN, ship at (800,900), pause popped (warp to (800,900)), then `step_lock((100,500))` | Ship stays at (800,900); no further warp; no `player_moved` | none |
| Tick after the guard tick | as above, then a second `step_lock((100,500))` | Ship moves to (100,500) as normal | none |
| Resume without warp | VISIBLE mode, pause popped, then `step_lock((100,500))` | No warp, no guard: ship moves to (100,500) | none |
| Shield without bubble | `PlayerShield` whose `bubble` path resolves to nothing | `_ready` logs `[ERROR][combat] PlayerShield '<name>' is missing its bubble...`; `raise`/`step`/`drop` work (active, countdown, `ended` once) with no crash | error pushed and asserted |
| Non-positive max hearts | `HealthComponent.setup(0 or -3, ...)` | `max_value` = `current` = 1; `can_take(1)` true; one `[ERROR][data]` line naming the value | error pushed and asserted |
| Player with bad tuning | `Config.tuning.player.hearts` = 0, Player instantiated | `max_hearts` 1; `apply_damage(1)` kills the ship (`player_died`) | error pushed and asserted |
| Shipped tuning | `player.hearts` = 5 | `max_hearts` 5, no error line | none |

</intent-contract>

## Code Map

- `game/entities/player/player.gd` -- `_on_resumed` (l.625-629) warps to `global_position` only in CONFINED_HIDDEN and in tree; `step_lock(mouse)` (l.503-517) confines, resolves hulls, warps when off by > `WARP_EPS_PX`, emits `player_moved` when moved. `_physics_process` (l.198-201) passes `get_viewport().get_mouse_position()`. Class doc l.18-22 describes resume warps.
- `game/entities/player/player_shield.gd` -- `_ready` l.29-31 resolves `bubble` and `Log.error("combat", ...)` when null; `raise`/`step`/`drop` already null-check `_bubble`. Read-only (test only).
- `game/core/health_component.gd` -- `setup` l.34-41 copies `p_max_value` unclamped; class doc l.5.
- `game/tests/unit/test_player_movement.gd` -- `_record_warp` recorder in `before_each`, resume tests l.178-200, `HIDDEN`/`VISIBLE` consts; `after_each` resets mode and `PauseArbiter.clear()`.
- `game/tests/unit/test_player_shield_component.gd` -- bare-node `PlayerShield` + `ShieldBubble` fixture pattern; `DURATION_S` override.
- `game/tests/unit/test_health_component.gd` -- `HealthComponent` on a bare node with a Sprite2D target.
- `game/tests/unit/test_player_hearts.gd` -- extends `res://tests/fixtures/player_test_base.gd` (`_begin()`, `_make_player(pos)`, `Log.sink` capture into `_lines`, `_logged(prefix)`).
- `game/tests/unit/test_config.gd` / `test_boot.gd` -- `assert_push_error(substring)` pattern for claiming `Log.error` pushes.
- `_bmad-output/game-architecture.md` -- l.251 Resume bullet; l.680 HealthComponent API line (`setup(...)`).

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_player_movement.gd` -- add failing tests first: stale tick after resume warp holds the ship (no warp, no `player_moved`); the following tick moves normally; VISIBLE-mode resume arms no guard -- DW-20 red phase.
- `game/entities/player/player.gd` -- add `_resume_pending: bool` and `_resume_target: Vector2`; `_on_resumed` sets both when it warps; `step_lock` replaces `mouse` with `_resume_target` and clears the flag when pending; update the class doc and the `_on_resumed`/`step_lock` doc comments -- DW-20 guard.
- `game/tests/unit/test_player_shield_component.gd` -- add a test building a `PlayerShield` with an unresolvable `bubble` path: asserts the error push, then `raise` (active), `step` countdown, `ended` once on expiry, `drop` all without crash -- DW-71.
- `game/tests/unit/test_health_component.gd` -- add tests for `setup(0, ...)` and `setup(-3, ...)`: `max_value`/`current` 1, `can_take(1)` true, error pushed -- DW-72 red phase.
- `game/core/health_component.gd` -- in `setup`, when `p_max_value < 1`, `Log.error("data", ...)` naming the node and the value, then use 1; update docs -- DW-72.
- `game/tests/unit/test_player_hearts.gd` -- add a Player-surface test: set `Config.tuning.player.hearts` to 0, make a player, assert `max_hearts` 1 and that `apply_damage(1)` kills it; restore with `Config.load_data()` -- DW-72 at the outermost surface.
- `_bmad-output/game-architecture.md` -- append the one-tick guard to the Resume bullet and the clamp to the HealthComponent `setup` description -- doc sync.

**Acceptance Criteria:**
- Given the shipped tuning, when the full GUT suite runs headless, then every test passes with no unclaimed errors.
- Given the Player test suites, when they run, then existing resume, hearts and shield tests pass unchanged.

## Spec Change Log

## Review Triage Log

### 2026-10-10 — Review pass
- verdicts: 17 findings — high 0, medium 0, low 10, false 6, maybe-false 1
- findings:
  - `[low]` `[reject]` (blind) Guard not cleared by a non-warping resume or on death — a HIDDEN resume then a VISIBLE resume with no tick between needs a scene-declared mode change (a scene swap that removes this Player), and the target equals the unmoved ship position anyway; a dead ship never ticks again (ADR-004 reload). Fix would add a branch for an unreachable case.
  - `[false]` `[reject]` (blind) Zone-edge and convoy-push warps lack the same guard — a stale read after those warps is outside the zone or inside a hull and is confined / pushed back to the same point, so the ship cannot jump; the intent names only the resume warp.
  - `[low]` `[patch]` (blind) "The ship holds still for that tick" overclaims with a live convoy (resolve_hull can still push it) — reworded in game-architecture.md Resume bullet and the step_lock doc comment.
  - `[low]` `[reject]` (blind) No test for a guard tick that itself warps or a resume before the first lock — the flag is cleared unconditionally at the top of step_lock and the first-lock path snaps to the same target; extra tests add no failing case.
  - `[low]` `[reject]` (blind) Bad-tuning test doesn't assert hearts_changed [1,1] — _emit_hearts reads the forwarding hearts/max_hearts, already covered by test_initial_hearts_changed_is_deferred and the max_hearts==1 assertion.
  - `[false]` `[reject]` (blind) Contact-cost and i-frame values are also unclamped — 0 contact cost and 0 i-frames are legal documented values (apply_damage ignores amount <= 0); they don't make the ship unhittable, unlike hearts.
  - `[false]` `[reject]` (blind) Validate at Config load instead of the consumer — the intent explicitly allows HealthComponent.setup; no harm beyond one visible error per spawn, which is the requested visibility.
  - `[low]` `[patch]` (blind) DW-71 test doesn't check the `combat` category — assert_push_error now matches `[ERROR][combat] PlayerShield 'BubblelessShield' is missing its bubble`.
  - `[low]` `[patch]` (blind) after_each comment "Some tests change Config.tuning" overstates (one test) — reworded to "A test changes Config.tuning".
  - `[maybe-false]` `[reject]` (edge) Several physics ticks in one frame after resume could read the stale mouse twice — depends on whether Viewport.get_mouse_position updates only on the per-frame input flush; settle with a live pause/resume under a frame spike. If true it is a one-tick cosmetic jump (low, never observed), and the operator decision fixes the guard at exactly one tick.
  - `[low]` `[reject]` (edge) VISIBLE resume with a pending HIDDEN guard — same root and reasoning as the first blind row (unreachable without a scene swap; harmless target).
  - `[false]` `[reject]` (edge) Guard stays armed if the player dies — a dead ship's _physics_process returns early and the scene reloads (ADR-004); the flag is never read.
  - `[low]` `[reject]` (edge) test_resume_without_warp_arms_no_guard covers only a clean state — same root as the first blind row.
  - `[false]` `[reject]` (intent) DW-20 tested via step_lock rather than _physics_process — the intent literally says "use the warp target (the ship's position) in step_lock" with the injected recorder; _physics_process is the sole production caller.
  - `[low]` `[reject]` (intent) Dead ship keeps the guard armed — duplicate of the edge row; no observable effect.
  - `[low]` `[patch]` (intent) DW-71 test checks message text but not the category — same fix as the blind category row.
  - `[false]` `[reject]` (intent) Clamp in the generic component reaches beyond player.hearts — the intent names HealthComponent.setup as an allowed site; Player is its only owner.

## Design Notes

The guard lives in `step_lock` (not `_physics_process`) so tests driving `step_lock` directly exercise it. Using the stored target (rather than the current `global_position`) keeps the guard equal to exactly what was warped. With mouse == target == the ship's position the tick yields `final == previous` (no warp, no `player_moved`); a live convoy cannot move a resting ship that is already pushed out.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failures

## Auto Run Result

Status: done

**Summary:** DW-20: `Player._on_resumed` now stores the warp target and arms a one-tick guard; the next `step_lock` uses that target instead of its mouse argument, then disarms, so a stale pre-warp read can't move the ship. DW-71: a test covers `PlayerShield` with no bubble (error logged, raise/step/drop still work). DW-72: `HealthComponent.setup` logs a `data` error and uses 1 for a max below 1, so a bad `player.hearts` no longer makes the ship unhittable; shipped tuning (5) is unchanged.

**Files changed:**
- `game/entities/player/player.gd` -- `_resume_pending` / `_resume_target`, guard in `step_lock`, armed in `_on_resumed`; docs.
- `game/core/health_component.gd` -- clamp plus `Log.error` in `setup`; docs.
- `game/tests/unit/test_player_movement.gd` -- stale-tick, guard-spent and no-warp-no-guard tests.
- `game/tests/unit/test_player_shield_component.gd` -- missing-bubble test.
- `game/tests/unit/test_health_component.gd` -- 0 / -3 clamp tests, valid-1 no-error test.
- `game/tests/unit/test_player_hearts.gd` -- Player-surface clamp test, shipped-tuning no-error test, `after_each` reloading Config.
- `_bmad-output/game-architecture.md` -- Resume bullet and HealthComponent `setup` description.

**Review findings:** 17 findings (high 0, medium 0, low 10, false 6, maybe-false 1). Patched 3 entries (all low): convoy-aware "ignores the mouse" wording in the architecture doc and the `step_lock` doc; `[ERROR][combat]` prefix in the DW-71 assertion; accurate `after_each` comment. Deferred: none. Rejected (reasons in the Review Triage Log): guard not cleared on non-warping resume / death (unreachable, harmless); other warp sites (no jump possible, out of intent); extra guard/first-lock tests; HUD hearts_changed assertion; contact/i-frame clamps (0 is legal); Config-load validation (intent allows setup); multi-tick-per-frame stale read (maybe-false, low if true, operator fixed one tick); step_lock vs _physics_process surface; generic-component clamp.

**Follow-up review recommended:** false (patched: high 0, medium 0, low 3).

**Verification:** `--import` exit 0; full headless GUT suite: 85 scripts, 1619/1619 passing, 0 failures, every pushed error claimed with `assert_push_error`. The implementation subagent confirmed the new tests fail against the original `player.gd` / `health_component.gd`. A "3 objects leaked" warning the subagent saw in a combined three-file run didn't show up in the full suite or in any single-file run, on either the patched tree or baseline.

**Residual risks:** Whether the viewport really reports a stale mouse after a warp (and whether that can last longer than one physics tick when several ticks run in one frame) is still not checked live; the guard is defensive by operator decision. Not checked by hand in the running game.
