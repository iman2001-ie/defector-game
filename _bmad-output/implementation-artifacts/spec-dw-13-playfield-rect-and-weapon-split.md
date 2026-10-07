---
title: 'DW-13: shared playfield rect and player weapon split'
type: 'refactor'
created: '2026-10-07'
status: 'done'
baseline_revision: 'bfbe6150603691fee7a5381c20347398279697e4'
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

**Problem:** Four scripts read the 1920×1080 playfield size straight from `ProjectSettings`, and `player.gd` mixes movement with all laser and missile firing logic. Epic 2 adds more entities that need the playfield bounds, and Epic 3 adds hearts and abilities to the player (epic-1 retro item 7, DW-13).

**Approach:** Add one `Playfield` constants class in `game/core/` (the architecture's "game constant" pattern, `const PLAYFIELD := Vector2(1920, 1080)`) and use it at the four read sites. Move laser and missile firing into a `PlayerWeapons` node script that the Player scene owns as a child node. Player keeps its public weapon API as thin delegators.

## Boundaries & Constraints

**Always:** Behaviour stays exactly the same: fire timing, cooldown, flash timing, SFX, spawn params, `Events.missile_cooldown_changed` emits, Config keys and warnings. Use statically typed GDScript. Only `Spawner` creates projectiles. Existing tests pass unmodified. Write the new tests first.

**Never:** Don't change tuning data, `Events`, the Spawner or the projectile scenes. Don't change movement/chase logic. Don't add per-frame allocations or node lookups in the fire paths. Don't edit the deferred-work ledger. Don't change project settings.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Playfield matches project | `Playfield.SIZE`, `Playfield.RECT` | equal the viewport size in project settings (1920×1080), RECT at origin | n/a |
| Weapons standalone | `PlayerWeapons` with muzzle + flash and a spawner, `step_fire(true)` held 60 ticks at 1/60 | 10 bolts at the muzzle, flash shown | n/a |
| Weapons missile | `step_missile(true, origin, target, dt)` | one missile toward target from origin, cooldown 1.0 emit | presses on cooldown dropped |
| No spawner | component without spawner | fires nothing, no emit | no error |

</intent-contract>

## Code Map

- `game/core/collision_layers.gd`, `game/core/impact_tier.gd` -- pattern for a `class_name` constants-only script (no `extends`).
- `game/core/projectile.gd:38-41` -- builds `_bounds` from two ProjectSettings reads; becomes `Playfield.RECT.grow(OFFSCREEN_MARGIN_PX)`.
- `game/entities/asteroids/asteroid.gd:22,46,66` -- `_viewport_height` from ProjectSettings; use `Playfield.SIZE.y` (drop the var or assign from the constant).
- `game/entities/player/player.gd:67` -- bounds width from ProjectSettings; use `Playfield.SIZE.x`.
- `game/scenes/sandbox/sandbox.gd:28,37` -- `_playfield_width` from ProjectSettings; use `Playfield.SIZE.x`.
- `game/entities/player/player.gd` -- weapon consts (`FIRE_EPS`, `LASER_TYPE`, `MISSILE_TYPE`, `MISSILE_FLASH_S`, `LASER_SFX`, `MISSILE_SFX`), laser/missile vars, the weapon half of `_ready()`, `set_spawner`, `step_fire`, `_fire_bolt`, `step_missile`, static `missile_direction`. All of these move to the component. `_physics_process` calls stay in the same order (move, laser, missile).
- `game/entities/player/player.tscn` -- add a `Weapons` child node (script `player_weapons.gd`) after `Muzzle`, with `muzzle` and `muzzle_flash` exported NodePaths set to `../Muzzle` and `../Muzzle/MuzzleFlash`. Bump `load_steps`.
- `game/tests/unit/test_player_laser.gd`, `test_player_missile.gd`, `test_sandbox.gd:61` -- read-only. They call `player.set_spawner`, `step_fire(held, dt)`, `step_missile(pressed, target, dt)`, `Player.missile_direction(...)` and read `Muzzle/MuzzleFlash`. These must keep working.
- `game/tests/unit/test_project_settings.gd:61-62` -- the asserted viewport size.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_playfield.gd` -- new: `Playfield.SIZE` equals the two ProjectSettings viewport values; `RECT` is `Rect2(Vector2.ZERO, SIZE)`; no script in `res://core`, `res://entities` or `res://scenes` reads `display/window/size/viewport_` (static source scan) -- guards the single source.
- `game/tests/unit/test_player_weapons.gd` -- new: build a `PlayerWeapons` without the player scene (Node2D parent with Marker2D muzzle + Node2D flash; set the exports before add_child), plus a Spawner world like test_player_laser. Cover: laser rate 10/s over 60 ticks, bolt at the muzzle with tuning velocity/damage, missile from the origin toward the target with the cooldown 1.0 emit then drop, `missile_direction` straight-up rule, no-spawner no-fire, and that `player.tscn` has a `Weapons` child that is a `PlayerWeapons`.
- `game/core/playfield.gd` -- new `class_name Playfield` with `SIZE: Vector2 = Vector2(1920, 1080)` and `RECT: Rect2`, plus a doc comment that ties it to the project viewport.
- `game/entities/player/player_weapons.gd` -- new `class_name PlayerWeapons extends Node`. Move the weapon code in verbatim. `step_missile(pressed, origin, target, delta)` takes the ship position as `origin`. Resolve `muzzle`/`muzzle_flash` once in `_ready`.
- `game/entities/player/player.gd` -- remove the weapon code. Add `@onready var _weapons: PlayerWeapons = $Weapons`. Keep `set_spawner`, `step_fire`, `step_missile(pressed, target, delta)` (passes `global_position`) and static `missile_direction` as one-line delegators. Update the class doc.
- `game/entities/player/player.tscn` -- add the `Weapons` node.
- `game/core/projectile.gd`, `game/entities/asteroids/asteroid.gd`, `game/scenes/sandbox/sandbox.gd` -- swap the reads for `Playfield`.

**Acceptance Criteria:**
- Given the full GUT suite, when run headless, then every pre-existing test passes with no test file changed except the two new ones.
- Given the sandbox scene, when the player holds LMB / presses RMB, then bolts and missiles spawn exactly as before (covered by the existing sandbox-driven tests in test_player_laser/test_player_missile).
- Given a grep of `game/` excluding `tests/` and `addons/`, when searching `display/window/size/viewport_`, then there are no matches.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 31 findings — high 0, medium 3, low 9, false 19, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) test_playfield scans only core/entities/scenes, not autoloads/systems/ui — added the three dirs to SCANNED_DIRS.
  - `[low]` `[reject]` (blind) guard misses get_viewport_rect / DisplayServer reads — intent targets ProjectSettings reads only; widening means extra patterns for reads that are legitimate elsewhere (camera), not worth it.
  - `[medium]` `[patch]` (blind) new missing-muzzle Log.error/disable path untested — added test_missing_muzzle_logs_and_fires_nothing (grouped with the verification-gap finding).
  - `[false]` `[reject]` (blind) inconsistent null guard on _muzzle_flash in step_fire — _flash_left only goes positive after a successful spawn, which requires _can_spawn() (non-null flash), so the unguarded write cannot hit null.
  - `[false]` `[reject]` (blind) scene test only checks NodePath strings — test_player_laser.test_bolt_params_from_muzzle_and_tuning and test_player_missile.test_aimed_shot fire through player.tscn and assert spawn at the real Muzzle.
  - `[low]` `[reject]` (blind) no-spawner test's flash assertion is vacuous — the projectile assertion still fails loudly (null spawner deref) if gating breaks, and no-spawner + later-spawner behaviour is covered by test_player_laser/test_player_missile; negligible.
  - `[low]` `[patch]` (blind) Player delegators crash before ready; set_spawner used to work pre-tree — set_spawner now resolves `get_node(^"Weapons")` directly.
  - `[low]` `[reject]` (blind) sandbox keeps redundant _playfield_width — spec allowed either; no divergence possible since it is assigned from the constant.
  - `[false]` `[reject]` (blind) test hard-codes 1920x1080 a third time — playfield is fixed by architecture and test_project_settings already pins it; no divergence results.
  - `[false]` `[reject]` (blind) spec records no verification — recorded at finalize below.
  - `[false]` `[reject]` (blind) typed node exports instead of NodePaths — preference; no named harm.
  - `[false]` `[reject]` (blind) player.tscn ext_resource lacks uid — no .tscn in the project carries uids; consistent with convention, path resolution works.
  - `[low]` `[patch]` (edge) set_spawner before tree entry hits null _weapons — same root cause as blind B7; patched.
  - `[low]` `[reject]` (edge) step_fire/step_missile before _ready crash on null _weapons — no caller does this, and old code also crashed (null _muzzle) on pre-ready firing with a spawner; a guard adds a hot-path branch.
  - `[false]` `[reject]` (edge) muzzle freed after _ready — Muzzle and Weapons are siblings under Player and are freed together.
  - `[false]` `[reject]` (edge) flash freed while _flash_left > 0 — same lifetime as above.
  - `[medium]` `[patch]` (edge) missing-muzzle disable path never exercised — grouped with the blind/VG finding; test added.
  - `[low]` `[patch]` (edge) SCANNED_DIRS misses autoloads/systems/ui — grouped with blind B1; patched.
  - `[false]` `[reject]` (edge) scripts embedded in .tscn/.tres escape the scan — no embedded GDScript sub-resources exist in game/.
  - `[false]` `[reject]` (edge) projectile counted in shared container makes no-spawner gate weakly tested — a broken gate derefs a null spawner and errors the test.
  - `[low]` `[reject]` (edge) warning log order changes (Weapons warnings before Player's) — no test or user-visible consumer depends on log order; fixing requires restructuring the ready order.
  - `[medium]` `[patch]` (verification-gap) missing-muzzle guard untested, disposition patch — test_missing_muzzle_logs_and_fires_nothing added and passing.
  - `[false]` `[reject]` (intent) value written twice (project.godot + Playfield) vs a settings-reading helper — architecture's config table prescribes `const PLAYFIELD := Vector2(1920, 1080)`; intent explicitly allows a constant; test pins agreement.
  - `[false]` `[reject]` (intent) guard scope narrower than AC — duplicate of blind B1, patched (counted here as reported).
  - `[false]` `[reject]` (intent) Player→Weapons path covered only by existing tests — those tests ran and passed (299/299).
  - `[false]` `[reject]` (intent) new missing-muzzle behaviour vs strict "unchanged" — normal-path behaviour unchanged; the branch is now tested (patched under the VG entry).
  - `[false]` `[reject]` (intent) three sites use SIZE components rather than RECT — all four reads come from the one Playfield source as the intent asks.
  - `[false]` `[reject]` (intent) shared core/ class vs "const in owning script" — the intent explicitly requests a shared source.
  - `[false]` `[reject]` (intent) spec file is outside the intent — workflow process artifact, not a deliverable.
  - `[false]` `[reject]` (intent) facade (R2a) chosen over a direct handoff — both readings satisfy "a component the player owns"; facade keeps existing tests unmodified as required.
  - `[false]` `[reject]` (intent) ledger stages two deadlines merged into one change — both deadlines are met.

### 2026-10-07 — Review pass
- verdicts: 20 findings — high 0, medium 0, low 8, false 12, maybe-false 0
- findings:
  - `[false]` `[reject]` (blind) architecture doc not updated for the shared Playfield constant — the architecture row is "`const` in the owning script"; `Playfield` is the owning script of `const SIZE`, so the pattern holds. The 1920×1080 statements at lines 56/1093 are still true, and no design decision changed.
  - `[low]` `[reject]` (blind) `set_spawner` uses `get_node(^"Weapons")` while the other delegators use `@onready _weapons` (two path literals, generic null crash) — renaming the node would only need two edits in one file. The pre-ready `step_fire`/`step_missile` part is carried from the prior row (reject). A shared getter adds surface for a negligible risk.
  - `[low]` `[reject]` (blind) no test calls `set_spawner` before the Player enters the tree — no caller in game/ or tests/ does this today (sandbox and all tests call it after `add_child`), so nobody would hit a regression in everyday use. Not worth a dedicated test.
  - `[low]` `[reject]` (blind) the missing-flash half of the disable path is untested and the error doesn't name which node is missing — it is the same `or` branch as the tested missing-muzzle case, and only a broken scene reaches it. Diagnostic wording is cosmetic.
  - `[false]` `[reject]` (blind) component tests skip flash timing, the cooldown ratio sequence and the no-cooldown/no-rate warnings — test_player_laser/test_player_missile cover all of these today by running the same PlayerWeapons code through the delegators. Losing the delegators is speculative future work.
  - `[false]` `[reject]` (blind) `_make_weapons()` silently rebinds `_flash` in test_no_spawner_fires_nothing — the final assertion is meant to check the lone instance's flash, and that is what it checks. No wrong outcome.
  - `[low]` `[reject]` (blind) the playfield guard misses new top-level dirs and fails if a listed dir is missing — carried scope note from the prior SCANNED_DIRS patch. All six dirs exist and the grep AC has 0 matches. Reworking the scan for directories that don't exist yet is not worth it.
  - `[false]` `[reject]` (blind) spec record incomplete (status in-review, no verification result, empty change log) — in-review is this pass's transient state, results are recorded under Auto Run Result at finalize, and the change log only records bad_spec loopbacks (none occurred). Any fix would also edit this build's spec.
  - `[low]` `[reject]` (blind) prior triage rows label patched duplicates as `[false]` — counting is cosmetic, and the fix would edit this build's spec.
  - `[false]` `[reject]` (blind) stale docs: Code Map line numbers, `missile_direction` comment, projectile class doc — Code Map is pre-change planning (spec edit). In context, "from the ship toward the cursor" is exactly what from/target mean. projectile.gd's class doc says "off-screen", which is still accurate.
  - `[false]` `[reject]` (blind) the missing-muzzle Log.error/disable path contradicts "behaviour stays exactly the same" — carried from the prior intent row: the normal path is unchanged, and the branch is tested. `_can_spawn()` is a field check with no allocation or lookup.
  - `[low]` `[reject]` (edge) `missile_direction` returns a zero vector when `straight_up_within_px` is negative and the target is exactly on the origin — pre-existing: identical code at baseline `player.gd:169`. It needs invalid tuning (shipped value 32) plus exact pixel coincidence, and the fix adds a guard.
  - `[false]` `[reject]` (intent) Player-level equivalence is backed only by the existing tests — carried. Those tests run unmodified and pass in this pass's verification.
  - `[false]` `[reject]` (intent) the standalone matrix row is split across a 60-tick count test and a 1-tick position/flash test — every bolt goes through the same `_fire_bolt` at `_muzzle.global_position`, so both halves of the row are asserted.
  - `[low]` `[patch]` (intent) missile test origin equals the rig's ship position, so a bug that aimed from the parent instead of `origin` would pass — moved the test origin to (560, 900) and the target to (860, 500). The direction stays (0.6, −0.8), and the origin now differs from SHIP (960, 900).
  - `[false]` `[reject]` (intent) "no error" is not asserted in the no-spawner test — GUT 9.7 fails a test on an unexpected push_error (test_missing_muzzle has to use `assert_push_error` for that reason), so an error would fail it.
  - `[false]` `[reject]` (intent) the source-scan guard is stronger than "the four read sites" — the spec's AC asks for that grep property, and a stronger guard has no named harm.
  - `[low]` `[reject]` (intent) the change in warning order is not tested — carried from the prior row: no consumer depends on log order.
  - `[false]` `[reject]` (intent) the working tree has a ledger edit despite "don't edit the ledger" — that is the orchestrator's DW-13 bookkeeping, not part of this change, and this build did not touch it.
  - `[false]` `[reject]` (intent) test-first and the pass count can't be checked from the diff — this pass reran the full suite (see Auto Run Result).

## Design Notes

The delegators keep the existing tests and `sandbox.gd` untouched. That proves the behaviour is unchanged, and it keeps Player as the single entry point for the scene root. The component is a plain `Node` (not Node2D) because it has no transform of its own. It reads positions from the muzzle and from the origin it is passed. A Godot child's `_ready` runs before its parent's, so Config warnings still fire during the player's `add_child`, and the existing `assert_push_warning` tests still hold.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` then `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failures.


## Auto Run Result

Status: done (follow-up review pass)

**Summary:** This pass reviewed the committed DW-13 change. It adds `Playfield` (`game/core/playfield.gd`, `SIZE` 1920x1080 + `RECT`) as the one source of the playfield size, used at the four former ProjectSettings read sites. It also adds `PlayerWeapons` (`game/entities/player/player_weapons.gd`), a `Weapons` child of `player.tscn` that holds the laser and missile logic. Player keeps its weapon API as delegators. The review found nothing wrong in the game code. One weakness in the test was fixed.

**Files changed (this pass):**
- `game/tests/unit/test_player_weapons.gd` -- the missile test's aim origin now differs from the rig's ship position, so the test proves the explicit `origin` is used.

**Files changed (the DW-13 change as a whole):** `game/core/playfield.gd`, `game/core/projectile.gd`, `game/entities/asteroids/asteroid.gd`, `game/scenes/sandbox/sandbox.gd`, `game/entities/player/player_weapons.gd`, `game/entities/player/player.gd`, `game/entities/player/player.tscn`, `game/tests/unit/test_playfield.gd`, `game/tests/unit/test_player_weapons.gd` (+ `.uid` files).

**Review:** 20 findings (high 0, medium 0, low 8, false 12).
- **Patched (1, low):** the missile origin in the test.
- **Deferred:** none.
- **Rejected (19):** each one has its reason in the Review Triage Log above, in short:
  - architecture doc already consistent
  - duplicate `Weapons` lookup is negligible
  - nobody calls `set_spawner` before the Player enters the tree
  - missing-flash branch is the same as the tested missing-muzzle branch
  - component behaviour is covered through the delegators
  - the test helper rebinding is intended
  - the guard covers all existing dirs
  - spec-record findings would edit the spec
  - the `missile_direction` zero-vector case is pre-existing and needs invalid tuning
  - the remaining intent items are already true or carried

**Follow-up review recommendation:** false. This was a follow-up pass and it patched no high findings (patched: 0 high, 0 medium, 1 low).

**Verification:** Ran `--import` (exit 0), then the full headless GUT run: 299 tests, 298 passing, 0 failing, 1 pending, 1774 asserts.
- The pending test is `test_feedback.gd::test_hit_stop_overlap_keeps_longest`, which reported pending because a second hit-stop came too late (34.5 ms) to tell the two stops apart. It is outside this change.
- No pre-existing test file changed.

**Residual risks:**
- Tests don't verify game feel; a quick play in the sandbox is still recommended.
- Weapon Config warnings now log before the Player's chase warning (ready order).
