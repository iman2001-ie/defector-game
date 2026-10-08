---
title: 'DW-56: shared player test fixture (tests/fixtures/player_test_base.gd)'
type: 'refactor'
created: '2026-10-08'
status: 'done'
baseline_revision: 'a0e67e96e8717cacb5b36382430c34981c282282'
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

**Problem:** Six GUT scripts (`test_player_hearts.gd`, `test_player_shield.gd`, `test_player_death.gd`, `test_player_barrage.gd`, `test_player_pickup.gd`, `test_energy_orb.gd`) each repeat the same player setup (`before_each`/`after_each`), `_ignore_warp`, `_capture`, `_logged` and the hazard factories `_wasp`, `_bastion`, `_asteroid`, `_shoot` (Epic 3 retro A2, DW-56).

**Approach:** Add `game/tests/fixtures/player_test_base.gd` (`extends GutTest`, no `class_name`, like `damage_target.gd`) that holds the shared constants, state, setup/teardown and helpers. Make the six scripts `extends "res://tests/fixtures/player_test_base.gd"`, delete their copies, and keep only their file-specific setup in overrides that call the base.

## Boundaries & Constraints

**Always:** Test-only. Every `func test_*` in the six files keeps its name, body and assertions (current counts: hearts 28, shield 19, death 12, barrage 13, pickup 5, energy_orb 15 = 92). Each file keeps its setup order where it matters: `warp_mouse` is set before `add_child` (Player `_ready` replaces an invalid one with the viewport's warp), death's `ShakeCamera` and `Events` connections exist before the player is added, barrage's world and `Spawner` are built before the player is added and `set_spawner` runs after it, and energy_orb's `before_each` creates no player. Each file keeps its teardown extras (`Input.action_release`, the death `disconnect`s and `set_gameplay_mouse_mode(VISIBLE)` after `PauseArbiter.clear()`, energy_orb's `Config.load_data()`). Statically typed GDScript. Subclasses must not redeclare a base constant, variable or helper (GDScript rejects shadowing).

**Never:** No change to anything outside `game/tests/`. Do not touch other test files (`test_player_lethal_feedback.gd`, laser, missile, movement and weapons tests stay as they are). Do not fix the known order-dependent barrage test (deferred elsewhere). Do not touch `deferred-work.md` or `sprint-status.yaml`. No `class_name` on the fixture.

</intent-contract>

## Code Map

- `game/tests/fixtures/damage_target.gd` -- precedent: a non-test fixture script with no `class_name`, preloaded by path. GUT only collects `test_`-prefixed files, so `tests/fixtures/` is not run as tests.
- `game/autoloads/log.gd:46-59` -- `Log.sink` is called *in addition to* print/push_error/push_warning, so capturing logs in files that did not before (pickup, energy_orb) changes nothing observable.
- `game/entities/player/player.gd:63-64,109-112` -- `warp_mouse` must be set before `_ready`, so the factory takes the warp callable.
- `game/tests/unit/test_player_hearts.gd:8-82,133-138` -- canonical copies: consts (PLAYER/WASP/BASTION/ASTEROID scenes, `DT`, `HAZARD_POS = (1500,150)`), `_player`, `_lines`, `before_each` (player at (200,900)), `after_each`, `_ignore_warp`, `_capture`, `_logged`, `_wasp`, `_bastion`, `_asteroid`, `_shoot`. Keeps LANCER/ENEMY_BULLET/NEEDLE_BOLT consts, `_sprite`, `_step`, `_iframes_s`.
- `game/tests/unit/test_player_shield.gd:10-114` -- same plus `GameState.energy = 0` and `Input.action_release(&"ability_shield")`. Keeps bullet/lancer/orb consts, `_bubble`, `_duration`, `_step`, `_raise`.
- `game/tests/unit/test_player_death.gd:7-103,208-211` -- extra state `_camera`, `_order`, `_failed_reasons`, `_warps`; warp is `_record_warp`. L208-211 is an inline large asteroid identical to `_asteroid(&"large")`.
- `game/tests/unit/test_player_barrage.gd:10-76` -- world/containers/Spawner before the player, player at `SHIP = (960,900)`, `set_spawner` after; `watch_signals` after the player (moving it earlier is harmless: nothing emits synchronously during setup). L241-262 `fresh`/`lone` players are bespoke (no position, tuning patched around `add_child`) and stay inline.
- `game/tests/unit/test_player_pickup.gd:6-30` -- player at (400,900), no log capture.
- `game/tests/unit/test_energy_orb.gd:7-32` -- no default player; `_make_player(pos)` is the base factory; after_each adds `Config.load_data()`.

## Tasks & Acceptance

**Execution:**
- `game/tests/fixtures/player_test_base.gd` -- new. Doc comment saying what it is and how to extend it. Consts `PLAYER_SCENE`, `WASP_SCENE`, `BASTION_SCENE`, `ASTEROID_SCENE`, `DT`, `HAZARD_POS`, `PLAYER_POS = Vector2(200, 900)`; vars `_player: Player`, `_lines: Array[String]`. `before_each()` = `_begin()` then `_player = _make_player(PLAYER_POS)`. `_begin()` clears `_lines`, sets `Log.sink = _capture`, `GameState.energy = 0`, `watch_signals(Events)`. `after_each()` resets `Log.sink`, `GameState.energy = 0`, `Feedback.reset()`, `PauseArbiter.clear()`, `_player = null`. `_make_player(pos: Vector2, warp: Callable = Callable()) -> Player` (invalid warp means `_ignore_warp`; sets warp, `add_child_autofree`, physics off, `global_position`). Plus `_ignore_warp`, `_capture`, `_logged`, `_wasp`, `_bastion`, `_asteroid(size)`, `_shoot(scene)` moved verbatim. -- A2.
- `game/tests/unit/test_player_hearts.gd` -- extend the base; delete the moved members and before/after_each. -- A2.
- `game/tests/unit/test_player_shield.gd` -- extend the base; `after_each` releases `ability_shield` then `super()`. -- A2.
- `game/tests/unit/test_player_death.gd` -- extend the base; `before_each` clears its arrays, `_begin()`, connects, adds the camera, then `_player = _make_player(PLAYER_POS, _record_warp)`; `after_each` disconnects, `super()`, then `set_gameplay_mouse_mode` and `_camera = null`; L208-211 uses `_asteroid(&"large")`. -- A2.
- `game/tests/unit/test_player_barrage.gd` -- extend the base; `before_each` builds world and spawner, `super()`, then sets `global_position = SHIP` and `set_spawner`; `after_each` releases `ability_barrage`, nulls its own refs, `super()`. -- A2.
- `game/tests/unit/test_player_pickup.gd` -- extend the base; `before_each` = `_begin()` + `_make_player(Vector2(400, 900))`. -- A2.
- `game/tests/unit/test_energy_orb.gd` -- extend the base; `before_each` = `_begin()` only; `after_each` = `Config.load_data()` then `super()`; uses the base `_make_player`. -- A2.

**Acceptance Criteria:**
- Given the six refactored scripts, when `grep -c "^func test_"` runs on each, then the counts are 28, 19, 12, 13, 5 and 15, and `git diff` shows no edited line inside any `test_*` function except death's inline asteroid.
- Given the six scripts, when searched, then none of them defines `_ignore_warp`, `_capture`, `_logged`, `_wasp`, `_bastion`, `_asteroid` or `_shoot`, and each extends `res://tests/fixtures/player_test_base.gd`.
- Given the full GUT suite, when run headless after `--import`, then it passes with the same script and test totals as baseline plus none lost (baseline 62 scripts / 915 tests), and the fixture is not collected as a test script.
- Given `git diff --stat`, when read, then only `game/tests/` files (and this spec) changed.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 14 findings — high 0, medium 0, low 3, false 11, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind: barrage's `super()` call moved log capture and the energy reset after the world and Spawner were built, so Spawner._ready's setup lines (`core/spawner.gd`, e.g. the missing-Pickups DEBUG line) were no longer captured — barrage's `before_each` now calls `_begin()` first, builds the world and Spawner, then `_player = _make_player(SHIP)` and `set_spawner`. This restores the original order; 915/915.
  - `[false]` `[reject]` Blind: hearts and death now also reset energy, pickup resets `Log.sink`, and death's teardown order changed — none of these tests reads energy or the sink after setup, `set_gameplay_mouse_mode` doesn't depend on `_player`/energy, and the suite is green. No bad outcome.
  - `[low]` `[reject]` Blind: `PLAYER_POS` is hard-coded, so pickup re-implements two lines — a design preference; an overridable `_player_pos()` hook adds surface for a two-line override.
  - `[false]` `[reject]` Blind: `_shoot` targets a null `_player` in energy_orb — energy_orb never calls `_shoot`; there is no such call path.
  - `[false]` `[reject]` Blind: `_logged` passes vacuously if a subclass skips `_begin()` — all six subclasses call `_begin()` (directly or via `super()`); no subclass reaches that state.
  - `[low]` `[reject]` Blind: the remaining duplication (lethal_feedback, laser, missile, movement, weapons, barrage's `fresh`/`lone`) isn't recorded — the intent names exactly six files, so it excludes the others.
  - `[false]` `[reject]` Blind: no recorded proof that verification ran — it ran: import exit 0, 62 scripts, 915/915, per-file counts 28/19/12/13/5/15 (see Auto Run Result).
  - `[false]` `[reject]` Blind: the Code Map line numbers will go stale — the fix would edit this build's spec (rejected by rule), and the anchors are correct for the baseline revision they cite.
  - `[false]` `[reject]` Blind: the fixture's doc omits that `global_position` is set after `add_child` — every original copy set the position after `add_child` too; behaviour is unchanged, and no `Player._ready` logic reads the position.
  - `[low]` `[patch]` Edge: Spawner._ready logs before `_begin()` installs the sink in barrage — same root cause as the first Blind row; the same patch fixes it.
  - `[false]` `[reject]` Intent: `test_player_lethal_feedback.gd:26` keeps its own `_ignore_warp` — the intent explicitly lists the six files, so it excludes this one.
  - `[false]` `[reject]` Intent: setup state is now uniform (energy reset, log capture, teardown order) — no assertion depends on it; the sink only adds output (`autoloads/log.gd` `emit_line`); the suite is green.
  - `[false]` `[reject]` Intent: barrage's player entered at (200,900) and then moved, and Events was watched earlier — after the patch it is created directly at `SHIP` (position set after `add_child`, as before); watching earlier is harmless because nothing emits during setup.
  - `[false]` `[reject]` Intent: "no test lost" and "suite green" are only stated, not shown — measured by this run (see Auto Run Result).

### 2026-10-08 — Review pass (follow-up)
- verdicts: 15 findings — high 0, medium 0, low 1, false 14, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: the fixture's header says to override `before_each` and call `super()`, which builds a default player so a subclass can't inject a warp — the same header names the alternative, "call `_begin()` and `_make_player(pos, warp)` yourself when the order matters (warp_mouse must be set before the player enters the tree)" (`player_test_base.gd:8-10`), and `super()` is correct for subclasses that only add setup afterwards. Following the header leads to neither failure.
  - `[false]` `[reject]` Blind: `_shoot` passes a null `_player` in a subclass with no default player — carried: energy_orb never calls `_shoot`; there is no such call path.
  - `[low]` `[reject]` Blind: barrage's `fresh`/`lone` players are still built by hand instead of with `_make_player` — carried: the remaining duplication is outside the six-file intent, and the Code Map keeps these inline on purpose because tuning is patched around `add_child`.
  - `[false]` `[reject]` Blind: setup changes (log capture in pickup/energy_orb, energy reset in hearts/death) aren't called out — carried: no assertion depends on them, and the sink only adds output; suite 915/915 again on this pass.
  - `[false]` `[reject]` Blind: `_wasp`/`_bastion`/`_asteroid`/`_shoot` repeat instantiate-setup-add-freeze and should become one generic helper — the intent says to move them, and they were moved verbatim; no caller is named that diverges or breaks. No harm is named.
  - `[false]` `[reject]` Blind: the remaining duplication in lethal_feedback, laser, missile, movement, weapons and shield_bubble has no follow-up — carried: the intent names exactly six files and explicitly excludes the others.
  - `[false]` `[reject]` Blind: pickup's player at `(400, 900)` is unexplained and should be a named const — the value is unchanged from baseline (`a0e67e9` pickup `before_each`); this change introduced no new bad outcome.
  - `[false]` `[reject]` Edge: `_shoot` with a null `_player` — same claim as the second Blind row; carried, false.
  - `[false]` `[reject]` Edge: the spec's task line says barrage calls `super()`, but the code calls `_begin()` first (the patch from the previous pass) — the code is right, and the only fix is to edit this build's spec, which is rejected by rule; the previous triage row records the order actually used.
  - `[false]` `[reject]` Intent: one test body changed (death's inline large asteroid now calls `_asteroid(&"large")`) — the intent's approach says "delete their copies", and the inline block was a copy; the asteroid built is identical (same scene, `size`, `HAZARD_POS`, physics off), and the death tests pass.
  - `[false]` `[reject]` Intent: hearts/death gained energy resets and pickup/energy_orb gained log capture — carried (as the Blind row above).
  - `[false]` `[reject]` Intent: `watch_signals(Events)` now runs earlier in barrage and death — carried: Player `_ready` defers its first emit, and Spawner `_ready` emits no `Events` signal, so the counts are unchanged.
  - `[false]` `[reject]` Intent: in death, `_player = null` now runs before `set_gameplay_mouse_mode(VISIBLE)` — carried: `set_gameplay_mouse_mode` doesn't read `_player`.
  - `[false]` `[reject]` Intent: pickup's teardown is now fully inherited — the base does the same four steps plus `Log.sink = Callable()`, which only undoes the capture it set up; no outcome changes.
  - `[false]` `[reject]` Intent: the base's interface (`_begin`, `_make_player`'s `warp`, `PLAYER_POS`) is wider than the extraction list — the intent's "overrides that call the base" plus the preserved-order rules need exactly these hooks; nothing uses them wrongly.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: 62 scripts, 915 tests, 0 failures
- `grep -c "^func test_" game/tests/unit/test_player_{hearts,shield,death,barrage,pickup}.gd game/tests/unit/test_energy_orb.gd` -- expected: 28, 19, 12, 13, 5, 15

## Auto Run Result

Status: done

**Summary:** Follow-up review pass on DW-56 (Epic 3 retro A2): the shared player test fixture `game/tests/fixtures/player_test_base.gd` and the six test scripts moved onto it (implemented in `18e06d1`). This pass found nothing to patch, so the code is unchanged.

**Files changed (reviewed diff since `a0e67e96e8717cacb5b36382430c34981c282282`):**
- `game/tests/fixtures/player_test_base.gd` (+ `.uid`): new shared base (no `class_name`). It holds the consts, `_player`/`_lines`, default `before_each`/`after_each`, `_begin`, `_make_player`, and the moved helpers.
- `game/tests/unit/test_player_hearts.gd`, `test_player_shield.gd`, `test_player_death.gd`, `test_player_barrage.gd`, `test_player_pickup.gd`, `test_energy_orb.gd`: each extends the base. Their copies are removed, and their file-specific setup and teardown are kept.
- This spec: the follow-up triage log and this result.

**Review:** 15 findings (high 0, medium 0, low 1, false 14). Verification-gap layer: no gaps.
- Patched: none.
- Deferred: none.
- Rejected:
  - 1 low (carried): barrage's hand-built `fresh`/`lone` players, kept inline on purpose.
  - 14 false: the `super()` header advice; `_shoot` with a null player (x2, carried); the extra resets and log capture (x2, carried); a generic hazard helper; duplication in other files (carried); pickup's position; the spec's task line for barrage (fixing it means editing this spec); death's asteroid body; watching `Events` earlier (carried); death's teardown order (carried); pickup's inherited teardown; the wider base interface.
  - Reasons are in the triage log.

**Follow-up review recommended:** false. This was a follow-up pass and it patched nothing (patched by verdict: high 0, medium 0, low 0).

**Verification (this pass):**
- `--import`: exit 0.
- Full GUT suite: 62 scripts, 915/915 passing, 7993 asserts, exit 0.
- `grep -c "^func test_"`: 28, 19, 12, 13, 5, 15, unchanged.

**Residual risks:**
- The spec's barrage task line still says `super()`; the code (and the previous triage row) use `_begin()` first. This is a doc mismatch only.
- Other player test files keep their own setup (out of scope).
- The known order-dependent barrage test (DW-55) is untouched.
- The orchestrator's uncommitted `deferred-work.md` edit and `.bmad-loop/archive/` were present before this run and were left as they were.
