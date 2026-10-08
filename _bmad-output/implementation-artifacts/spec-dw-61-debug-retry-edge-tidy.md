---
title: 'DW-61: tidy debug and retry edges (pause clear at the swap, F5 resets GameState, Groups const class)'
type: 'refactor'
created: '2026-10-08'
status: 'done'
baseline_revision: '73651446b642a3f87d327b6c8375bb9a99fbb327'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
warnings: ['multiple-goals']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Epic 3 retro F2/F3/A5. (F2) `SceneRouter._change_to` calls `PauseArbiter.clear()` before the scene swap, so `resumed` fires while the dead level is still in the tree and its Player warps the cursor; F5 (`DebugTools.reload_data`) has the same order. (F3) F5 resets neither `GameState.energy` nor `GameState.is_retry`, so a playtest restart after a retry or F4 keeps stale state. (A5) Group names are spelled as scattered literals and per-file consts (`Enemy.PLAYER_GROUP`, `EnergyOrb.PLAYER_GROUP`, `WaspDiveClock.ENEMIES_GROUP`, `WaveDirector.COUNTED_GROUP`, bare `&"player"`, `&"enemies"`, ...).

**Approach:** Clear pauses right after the swap call (Godot 4.7 removes the outgoing scene from the tree synchronously inside `change_scene_to_file`, verified with a headless probe; the incoming scene is added at end of frame, so its `_ready` pushes are not wiped), and make `Player._on_resumed` ignore the signal when the Player is outside the tree. Extract goto_title's save-restore into a public `SceneRouter.restore_saved_progress()` that F5 also calls. Add `core/groups.gd` (`class_name Groups`) and use it in all production code.

## Boundaries & Constraints

**Always:** Statically typed GDScript. `Feedback.reset()` and the INFO scene log stay before the swap call in `_change_to`. `restore_saved_progress()` does exactly what goto_title does today for highest_unlocked_level, energy (both clamped while `Config.load_error` is empty) and `is_retry = false`; goto_title keeps setting `current_level_id = ""` itself. F5 calls it only after `Config.reload()` succeeded (new clamps apply), before `restart_scene.call()`; on a failed reload nothing changes. `Groups` constants are `StringName` values `player`, `enemies`, `asteroids`, `projectiles`, `pickups`, `counted`, `wave_director` (only groups in use). Run `--import` after adding the `class_name`. Update `game-architecture.md` where it states the old clear order (Reload rules ~L474, PauseArbiter `clear()` comment ~L1013) and the `PLAYER_GROUP` mention (~L1112), and name `Groups` next to `CollisionLayers` (~L292, dir tree ~L595).

**Never:** No change to save writing, to `restart_level`'s energy wipe, to `GameState` fields, or to `.tscn` files. Don't rewrite test-file group literals (tests stay independent checks). Don't touch `deferred-work.md` or `sprint-status.yaml`. No new pause/scene owners.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Retry from death | `death` pushed, `restart_level()` | at the `change_scene` call the tree is still paused; afterwards unpaused, `resumed` emitted once, after the call | none |
| Old Player gets resumed | Player removed from tree, gameplay mode CONFINED_HIDDEN, pause push then clear | no `warp_mouse` call | none |
| In-tree resume | Player in tree (existing tests) | still warps once onto the ship | none |
| F5 after retry | save energy 40 / highest 2, GameState energy 0, is_retry true, `death` pushed | energy 40, highest 2, is_retry false; paused at `restart_scene` call, unpaused after | none |
| F5 with no save | no file | energy 0, highest 1, is_retry false | SaveManager INFO default |
| F5 reload fails | `Config.reload()` false | GameState and pauses unchanged, no restart | existing ERROR log |

</intent-contract>

## Code Map

- `game/autoloads/scene_router.gd:163-167` -- `_change_to`: move `PauseArbiter.clear()` after `change_scene.call(path)`; update header doc (L6-7). `goto_title()` L125-136 holds the restore logic to extract.
- `game/autoloads/pause_arbiter.gd:52-55` -- `clear()` emits `resumed` when it unpauses; doc says SceneRouter calls it (update to "at the swap").
- `game/entities/player/player.gd:434-436` -- `_on_resumed`: add an `is_inside_tree()` guard (connected at L140, never disconnected; the outgoing Player lives until end of frame).
- `game/ui/debug/debug_tools.gd:224-239` -- `reload_data()`: call `SceneRouter.restore_saved_progress()`, then `restart_scene.call()`, then `PauseArbiter.clear()`; update docs (L8-9).
- `game/core/collision_layers.gd` -- precedent for a `class_name` const holder.
- Group literals to replace: `core/enemy.gd:16,68,131` (drop `PLAYER_GROUP`), `core/projectile.gd:39`, `entities/asteroids/asteroid.gd:62`, `entities/enemies/hunter_wasp/hunter_wasp.gd:81` (uses inherited `PLAYER_GROUP`), `entities/enemies/wasp/wasp_dive_clock.gd:10,54` (drop `ENEMIES_GROUP`), `entities/pickups/energy_orb.gd:15,61,62` (drop `PLAYER_GROUP`), `entities/player/player.gd:118`, `entities/projectiles/micro_missile.gd:61`, `entities/projectiles/missile.gd:8`, `scenes/sandbox/sandbox.gd:88`, `systems/waves/wave_director.gd:39,86,192,216,217,290` (drop `COUNTED_GROUP`), `ui/debug/debug_tools.gd:167,193,216,368,369`. No test references the dropped consts.
- `game/tests/unit/test_scene_router.gd` -- recorder `_record` (L69) and fixtures `_write_save`, TEST_SAVE; `test_restart_level_resets_and_reloads` L113.
- `game/tests/unit/test_debug_tools.gd` -- `_make_tools` injects `restart_scene = _count_restart`; TEST_SAVE already set; after_each resets energy but not `is_retry`.
- `game/tests/unit/test_player_movement.gd:178-206` -- resume-warp tests; `_record_warp` recorder.

## Tasks & Acceptance

**Execution:**
- `game/core/groups.gd` -- new `class_name Groups` with the seven constants and a doc comment (code uses these, `.tscn` stores none, tests may use literals) -- A5.
- production files listed in the Code Map -- replace every group literal/const with `Groups.*` -- A5.
- `game/autoloads/scene_router.gd` -- add `restore_saved_progress()`; goto_title uses it; `_change_to` clears after the swap -- F2/F3.
- `game/entities/player/player.gd` -- guard `_on_resumed` -- F2.
- `game/ui/debug/debug_tools.gd` -- F5 restores progress and clears after restart -- F2/F3.
- `game/autoloads/pause_arbiter.gd` -- doc only -- F2.
- `game/tests/unit/test_groups.gd` -- new: constant values; scan production `.gd` files (res:// excluding `addons/`, `tests/`) for `group(&"`, `in_group(&"` and `_GROUP` const definitions: none found -- A5.
- `game/tests/unit/test_scene_router.gd` -- add: paused at the swap call / unpaused after, `resumed` emitted after the call (for restart_level, goto_title); `restore_saved_progress()` restores and clamps -- F2/F3.
- `game/tests/unit/test_player_movement.gd` -- add: out-of-tree Player does not warp on resume -- F2.
- `game/tests/unit/test_debug_tools.gd` -- add: F5 restores save energy/highest, clears is_retry, pauses still held at restart call and cleared after; failed reload leaves GameState alone; reset `is_retry` in after_each -- F2/F3.
- `_bmad-output/game-architecture.md` -- the as-built updates named in Boundaries.

**Acceptance Criteria:**
- Given the full GUT suite, when run headless after `--import`, then every test passes, with the new tests counted.
- Given production `.gd` files, when grepped for `group(&"` or `in_group(&"`, then nothing matches.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 22 findings — high 0, medium 0, low 18, false 4, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) `change_scene.call` result ignored; a failed swap would unpause an in-tree scene — pre-existing (the old order also cleared with the scene still in the tree on failure); paths are constants with existence tests, so unreachable in practice; fix adds an error branch.
  - `[low]` `[reject]` (blind) group-literal scan misses plain `"..."` strings and literals in const arrays — guard-strength only; no such literal exists today (grep clean); broadening needs a value-token scan that collides with tuning keys like `"enemies.<id>"`.
  - `[low]` `[reject]` (blind) `.tscn` groups rule not enforced — no `.tscn` declares groups today; adding a new scanner is extra complexity for an unlikely regression.
  - `[low]` `[reject]` (blind) no regression test for engine synchronous scene removal — verified this run with a headless 4.7.2 probe (`in_tree=false` right after `change_scene_to_file`); a real scene change inside GUT would replace the runner scene, and `Player._on_resumed`'s guard covers the case anyway.
  - `[low]` `[reject]` (blind) guard instead of disconnecting in `_exit_tree` — design preference; Player is the only `resumed` listener (searched), no named harm.
  - `[low]` `[patch]` (blind) architecture WaveDirector usage sample still shows `wasp.add_to_group(&"counted")` against the new rule — fixed: sample now `wasp.add_to_group(Groups.COUNTED)`; prose naming groups by name is fine.
  - `[low]` `[reject]` (blind) `test_restore_saved_progress_clamps` hard-codes 3 and 100 — mirrors the existing `test_goto_title_clamps_the_saved_values` exactly; changing one alone would split the convention.
  - `[low]` `[reject]` (blind) no test for a failed swap or for the incoming scene's `_ready` push surviving — failed swap is pre-existing/unreachable; incoming-scene timing cannot be exercised with the recorder seam (see probe evidence above).
  - `[false]` `[reject]` (blind) F5 keeps `all_levels_unlocked`/`current_level_id` undocumented — F5 restarts the current level so the id must stay; GameState documents F7's flag as never reset by goto_title; `restore_saved_progress()` doc says it touches no other field.
  - `[false]` `[reject]` (blind) F5 tests could pass on leaked pause state — the asserted property (paused at the restart call, resumed once after) holds regardless of a pre-existing reason; every suite's after_each clears.
  - `[false]` `[reject]` (blind) transient CONFINED_HIDDEN mouse mode between swap and new scene — identical before the change (clear() applied the same gameplay mode in the same frame); the new scene sets its mode in `_ready`.
  - `[low]` `[reject]` (blind) F5 architecture bullet is dense — style only, no named harm.
  - `[low]` `[reject]` (edge) `_change_to` swap error unguarded — same root as the first row; rejected there.
  - `[low]` `[reject]` (edge) F5 `restart_scene` failure returns true after GameState restore — DebugTools lives inside a scene so a current scene always exists; old order cleared regardless too.
  - `[low]` `[reject]` (edge) scan misses plain-string group calls — same as blind row 2.
  - `[low]` `[reject]` (edge) scan misses literals in const arrays (old SPLASH_GROUPS form) — same as blind row 2.
  - `[low]` `[reject]` (edge) `.tscn` `groups=[` not scanned — same as blind row 3.
  - `[low]` `[reject]` (verification-gap, other) scan misses plain-string group names — same as blind row 2; reviewer found no verification gaps.
  - `[low]` `[reject]` (intent) F2 tests use a fake swap, engine premise unverified in-suite — same as blind row 4.
  - `[low]` `[reject]` (intent) F5 also restores `highest_unlocked_level` (wider than energy + retry) — matches the intent's "like goto_title does"; in-memory and saved unlock only differ after a failed save write, so no everyday difference.
  - `[low]` `[reject]` (intent) A5 guard is text-only and skips `.tscn` — same as blind rows 2-3.
  - `[false]` `[reject]` (intent) F5 clear reorder, Player guard and doc edits exceed the intent's wording — they implement the intent's stated outcome (no dead-scene resume) on the second scene-change path; no bad outcome.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0, no parse errors.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass.

## Auto Run Result

Status: done

**Summary:** DW-61 (Epic 3 retro F2/F3/A5). `SceneRouter._change_to` and F5 `reload_data` now drop pauses right after the scene swap call (Godot 4.7.2 removes the outgoing scene synchronously, confirmed with a headless probe), and `Player._on_resumed` ignores the signal outside the tree. goto_title's save restore became `SceneRouter.restore_saved_progress()`, which F5 calls after a successful reload (energy, unlock, `is_retry = false`). New `Groups` const class; every production group literal and per-file `*_GROUP` const replaced.

**Files changed:**
- `game/core/groups.gd` (+ `.uid`) -- new `Groups` class, seven `StringName` group names.
- `game/autoloads/scene_router.gd` -- clear after swap; `restore_saved_progress()` extracted.
- `game/ui/debug/debug_tools.gd` -- F5 restores progress, clears after restart; `Groups.*`.
- `game/entities/player/player.gd` -- `_on_resumed` in-tree guard; `Groups.PLAYER`.
- `game/autoloads/pause_arbiter.gd` -- doc only.
- `game/core/enemy.gd`, `core/projectile.gd`, `entities/asteroids/asteroid.gd`, `entities/enemies/hunter_wasp/hunter_wasp.gd`, `entities/enemies/wasp/wasp_dive_clock.gd`, `entities/pickups/energy_orb.gd`, `entities/projectiles/micro_missile.gd`, `entities/projectiles/missile.gd`, `scenes/sandbox/sandbox.gd`, `systems/waves/wave_director.gd` -- `Groups.*` instead of literals/consts.
- `game/tests/unit/test_groups.gd` (+ `.uid`) -- constant values and production-source scan.
- `game/tests/unit/test_scene_router.gd`, `test_debug_tools.gd`, `test_player_movement.gd` -- ordering, restore and out-of-tree tests.
- `_bmad-output/game-architecture.md` -- as-built: Groups, F5 order, clear() comment, Enemy helpers, WaveDirector sample.

**Review:** 22 findings (0 high, 0 medium, 18 low, 4 false). 1 patch applied (low: architecture sample literal). 0 deferred. 21 rejected, reasons in the Review Triage Log.

**Follow-up review recommended:** false (patched: high 0, medium 0, low 1).

**Verification:** `--import` exit 0; full GUT suite exit 0: 69 scripts, 1052 tests, 1051 passing, 1 pending (`test_feedback.gd` hit-stop overlap self-pends when the machine is too slow to time it; unrelated). All 11 new tests ran and passed. Re-run after the patch gave the same totals. Production grep for `group(&"` / `in_group(&"` finds nothing.

**Residual risks:** the F2 ordering relies on Godot's synchronous removal in `change_scene_to_file` / `reload_current_scene` (probed on 4.7.2, not covered in-suite); an engine upgrade should re-check it. The group-literal scan catches only `&"` call forms and `*_GROUP` consts.
