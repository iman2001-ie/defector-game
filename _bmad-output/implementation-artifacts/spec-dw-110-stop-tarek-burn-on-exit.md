---
title: 'DW-110: stop Tarek''s burn sound when his scene leaves'
type: 'bugfix'
created: '2026-10-14'
status: 'done'
baseline_revision: 8e4a43da81b0ed112905a98e9e5129eb034f38a9
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

**Problem:** Tarek's burning-fall sound (`tarek_burn`, about 4.6 s, combat SFX pool, on the `Audio` autoload which is `PROCESS_MODE_ALWAYS`) keeps playing into the next scene when the player quits or retries from the pause menu during the down beat, because nothing stops a combat-pool sound on a scene change (DW-110).

**Approach:** Add `Audio.stop_sfx(id)`, which stops every combat-pool player still playing that id's stream and frees its slot, by extracting the loop `play_sfx_solo` already uses (and having `play_sfx_solo` call it). Add `TarekFallScene._exit_tree()` that calls `Audio.stop_sfx(BURN_SFX)`, so the burn ends whenever the level scene (and with it the director) leaves the tree.

## Boundaries & Constraints

**Always:** Statically typed GDScript. `stop_sfx` touches only combat-pool players whose stream is that id's registered stream; it never stops other ids, the comms pool or music. `play_sfx_solo` keeps its exact behaviour (it now calls `stop_sfx` before `play_sfx`). Update the `audio.gd` header doc and the `tarek_fall_scene.gd` header doc, and the as-built notes in `_bmad-output/game-architecture.md` (Audio API line under "As-built 2026-10-14 (Epic 7 playtest E)" and the TarekFallScene / Audio bullets of the playtest J as-built), so the docs match. Tests write the failing case first.

**Never:** Do not stop the whole combat pool (or any audio) on scene changes, and do not touch `SceneRouter`. No tuning, data, dialogue or scene (`.tscn`) changes. No new `class_name`. Don't edit `deferred-work.md`, `sprint-status.yaml` or `.bmad-loop/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Stop a playing id | `tarek_burn` and `laser_zap` playing on the combat pool; `stop_sfx(&"tarek_burn")` | every `tarek_burn` player stopped and its slot free (the next `play_sfx` may reuse it); `laser_zap` still playing | No error expected |
| Two copies | two `energy_pickup` players playing | both stopped | No error expected |
| Nothing playing | id registered but not playing | no change, no warning | No error expected |
| Unknown id | `stop_sfx(&"no_such_id")` | no change, silent (no warning, no log) | Silent no-op |
| Comms id | `comms_static` playing on the comms pool; `stop_sfx(&"comms_static")` | no change: the comms pool is never touched | Silent no-op |
| Scene leaves mid-burn | director has played the burn (impact or no-Vale fall), then is freed (retry / quit reloads the level) | the burn stops; other combat sounds keep playing | No error expected |
| Normal run | impact, then the down beat requested, scene still in the tree | the burn is still playing during the down beat, as now | No error expected |

</intent-contract>

## Code Map

- `game/autoloads/audio.gd` -- combat pool `_players` / `_in_use` / `_serials` (l.91-95); `play_sfx_solo` (l.178-189) holds the loop to extract: `for i in _players.size(): if _in_use[i] and _players[i].stream == stream: _players[i].stop(); _in_use[i] = false` (stop() never emits `finished`, so the slot is freed by hand). Guard: `stream != null and not COMMS_SFX.has(id)`. Header doc l.26-27 mentions `play_sfx_solo`; add `stop_sfx` beside it.
- `game/systems/story/tarek_fall_scene.gd` -- `BURN_SFX` (l.50); burn played in `_fall_effects()` (l.258-260) via `Audio.play_sfx(BURN_SFX, 0.0, burn_volume_db)`; no `_exit_tree` yet. Header doc l.3-39 (add one sentence: leaving the tree stops the burn, DW-110). Place `_exit_tree` right after `_ready` (project style, e.g. `game/core/spawner.gd:51`).
- `game/tests/unit/test_audio.gd` -- helpers `_free_all_players()`, `_pool()`; pattern to mirror: `test_play_sfx_solo_never_stacks_one_id` (l.602-620). `after_each` frees every player.
- `game/tests/unit/test_tarek_fall_scene.gd` -- fixture `_make()`, `_to_dash()`, `_run_to(t)`, `_start()`; `test_impact_when_the_ram_arrives` (l.330) and `test_no_vale_tarek_falls_at_once_and_both_beats_play` (l.511) already assert the burn as `Audio.newest_player()`. The scene is `add_child_autofree`d; free it explicitly in a test with `_scene.free()` (then set `_scene = null`) to trigger `_exit_tree`. `after_each` does not free SFX players: the new tests should stop any burn they leave (e.g. `Audio.stop_sfx(TarekFallScene.BURN_SFX)` in `after_each`) so a 4.6 s burn never leaks into other suites.
- `_bmad-output/game-architecture.md` -- l.2133 (Audio: `play_sfx_solo`), l.2221 (TarekFallScene as-built), l.2224 (Audio: `tarek_burn`).

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_audio.gd` -- add tests: `stop_sfx` stops every copy of the id and frees the slot, leaves another id playing; unknown id and comms id are silent no-ops (`assert_push_warning_count(0)` for the unknown id; comms player still playing) -- the I/O matrix's Audio rows.
- `game/tests/unit/test_tarek_fall_scene.gd` -- add tests: (a) after the impact a `laser_zap` also plays, then the scene is freed: the burn stops, the `laser_zap` keeps playing; (b) same for the no-Vale fall; (c) a normal run reaches the down beat (`_requested` ends with `DOWN`) with the burn still playing. Stop leftover burns in `after_each`.
- `game/autoloads/audio.gd` -- add `stop_sfx(id: StringName) -> void` with a `##` doc comment; `play_sfx_solo` calls it; header doc updated.
- `game/systems/story/tarek_fall_scene.gd` -- add `_exit_tree() -> void` calling `Audio.stop_sfx(BURN_SFX)`; header doc updated.
- `_bmad-output/game-architecture.md` -- amend the three as-built lines above to name `stop_sfx` and the director's `_exit_tree` (DW-110).

**Acceptance Criteria:**
- Given Tarek's burn is playing after the impact and another combat sound is playing, when the TarekFallScene leaves the tree (a retry or quit frees the level), then no combat-pool player is still playing the `tarek_burn` stream and the other sound is still playing.
- Given an unquit run, when the down beat is requested after the impact, then the burn is still playing, exactly as before this change.
- Given the full GUT suite, when it runs headless, then every test passes (no new failures, no orphan warnings from the new tests).

## Spec Change Log

## Review Triage Log

### 2026-10-14 — Review pass
- verdicts: 21 findings — high 0, medium 0, low 15, false 6, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) The `COMMS_SFX.has(id)` guard in `stop_sfx` is redundant, so the comms test passes without it — true (comms ids only ever play on the comms pool, which the loop never visits), but the guard is harmless, carried over from `play_sfx_solo`, and costs nothing; no user or developer harm.
  - `[low]` `[patch]` (blind) The comms-id test does not check the matrix's "no log" — fixed: the test now captures `Log.sink` and asserts no line.
  - `[low]` `[reject]` (blind) A silent no-op for an unknown id would hide a typo in a future `stop_sfx` call — the spec chose silence deliberately; `BURN_SFX`'s registration is already exercised by tests that index `Audio.SFX[TarekFallScene.BURN_SFX]`; a warn branch adds complexity for an unlikely case.
  - `[false]` `[reject]` (blind) No test frees the director before the burn has played — every existing scene test autofrees the director in LOCK/WARNING/RUNNING, so `_exit_tree` with nothing playing runs in each of them and the suite passes without errors; `test_stop_sfx_with_nothing_playing_changes_nothing` covers the call itself.
  - `[low]` `[reject]` (blind) A level outcome during the burn lets it play over the game-over screen — pre-existing and unlikely: Vale is scripted-locked and invulnerable through the aftermath, and the burn (about 4.6 s real time) has ended long before the lock releases; outside DW-110's scope.
  - `[low]` `[reject]` (blind) Tests free a standalone director instead of going through pause menu -> `SceneRouter` — the link holds: `TarekFallScene` is a node of `game/scenes/level/level.tscn` and `SceneRouter._change_to` uses `change_scene_to_file`, which removes the level and runs `_exit_tree` on every descendant; a full router integration test would be costly for a cosmetic gain.
  - `[low]` `[reject]` (blind) `_free_combat_pool` duplicates `test_audio.gd` helpers and its comment is imprecise — test-only duplication across two files with no named divergence risk; the comment's intent (keep free slots so the zap never steals the burn) is correct.
  - `[low]` `[patch]` (blind) `_requested.back()` raises an engine error on an empty array instead of a clean failure — fixed: replaced with `assert_eq(_requested, [WARNING, DOWN] as Array[StringName], ...)`.
  - `[low]` `[reject]` (blind) Inconsistent null guards in the new Audio tests — `laser_zap` and `energy_pickup` are registered, so `play_sfx` cannot return null there; adding guards is complexity for an unreachable case.
  - `[low]` `[reject]` (blind) The freed-slot assertion depends on `_pick_player`'s first-free order — that order is `_pick_player`'s documented contract ("the pool's first free player"); test-only fragility with no current harm.
  - `[low]` `[reject]` (blind) "About 4.6 s" is hard-coded in docs and a comment — cosmetic; the figure also appears in the ledger entry this run resolves.
  - `[low]` `[reject]` (blind) The spec's Code Map line numbers are stale after the change — fix would edit this build's spec.
  - `[false]` `[reject]` (edge) `stop_sfx` leaves `_newest` pointing at a stopped player — `newest_player()` is documented as "the most recently started player" (tests only), which stays true after a stop; nothing reads it as "playing".
  - `[false]` `[reject]` (edge) `_exit_tree` could cut a burn another director played (L1/L3 directors, a node removed without being freed) — only one level scene exists at a time, so no other director can be in the tree while a burn from a different one plays; nothing removes the director without freeing it.
  - `[low]` `[reject]` (edge) `zap` used unguarded in two Audio tests — same as the null-guard row above; unreachable.
  - `[low]` `[reject]` (intent) No test drives the real pause-menu -> `SceneRouter` route — same as the router row above.
  - `[false]` `[reject]` (intent) No test frees the director while the game is paused — `NOTIFICATION_EXIT_TREE` is not gated by pause or process mode, so `_exit_tree` runs the same paused or not.
  - `[low]` `[patch]` (intent) Nothing checks that `stop_sfx` leaves music alone, though the docs claim it — fixed: `test_stop_sfx_stops_the_id_and_frees_its_slot` now plays `boss` music first and asserts it is still current and playing.
  - `[low]` `[reject]` (intent) The normal down beat is checked at one moment, not for the burn's full length — headless tests cannot meaningfully observe real-time playback length; the test proves no stop happens while the scene is in the tree, which is what this change could break.
  - `[false]` `[reject]` (intent) `_exit_tree` stops the burn on every exit and phase, wider than "quit or retry during the down beat" — the intent itself mandates `_exit_tree` as the mechanism.
  - `[false]` `[reject]` (intent) The artifact-only receipt does not describe this change — not a defect; this run changes tracked code and will not assert the receipt.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0 (`<GODOT_DIR>` from `LOCAL.md`).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, including the new ones.

## Auto Run Result

Status: done

**Summary:** Tarek's burning-fall sound no longer plays on into the next scene after a retry or quit from the pause menu (DW-110). `Audio.stop_sfx(id)` stops every combat-pool player still playing one id and frees its slot (the loop moved out of `play_sfx_solo`, which now calls it). `TarekFallScene._exit_tree()` calls `Audio.stop_sfx(BURN_SFX)`, so the burn ends when the level scene leaves. The combat pool is not stopped on scene changes, and `SceneRouter` is untouched.

**Files changed:**
- `game/autoloads/audio.gd` -- new `stop_sfx(id)`; `play_sfx_solo` calls it; header doc.
- `game/systems/story/tarek_fall_scene.gd` -- new `_exit_tree()` stopping the burn; header doc.
- `game/tests/unit/test_audio.gd` -- 5 tests for `stop_sfx` (stops the id and frees its slot, leaves other ids and music; every copy; nothing playing; unknown id; comms id).
- `game/tests/unit/test_tarek_fall_scene.gd` -- 3 tests (freeing the director after the impact or the no-Vale fall stops the burn and nothing else; a normal run still plays the burn through the down beat); `after_each` stops any leftover burn.
- `_bmad-output/game-architecture.md` -- as-built notes (playtest E Audio, playtest J TarekFallScene and Audio) name `stop_sfx` and `_exit_tree`.

**Review findings:** 21 findings (0 high, 0 medium, 15 low, 6 false). Patches applied: 3 low (comms test checks no log; `stop_sfx` test checks music is untouched; down-beat test asserts the full request list instead of `back()`). Deferred: none. Rejected: 18, each with its reason in the Review Triage Log above (redundant-but-harmless comms guard, deliberate silent unknown id, pre-existing level-outcome overlap, router-level test not worth its cost, test-only duplication and fragility, cosmetic doc figures, stale spec line numbers, and six false claims).

**Follow-up review recommended:** false. Patched entries by verdict: high 0, medium 0, low 3.

**Verification:** `--import` exited 0. Full headless GUT run exited 0: 2191 tests, 2190 passing, 1 pending (`test_feedback.gd` `test_hit_stop_overlap_keeps_longest`, an existing timing guard unrelated to this change), 0 failing. All 8 new tests ran and passed; every I/O matrix row is covered by a passing test.

**Residual risks:** The scene-exit tests free a standalone director rather than going through the pause menu and `SceneRouter`; the real route relies on `change_scene_to_file` freeing `level.tscn`, which contains the director. How the cut-off sounds in play is for the operator to judge.
