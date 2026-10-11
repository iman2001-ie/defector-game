---
title: 'DW-80: reserve a comms SFX pool that combat SFX never steal'
type: 'bugfix'
created: '2026-10-11'
status: 'done'
baseline_revision: '18db24f1b541061cc8f6fe404a8044ddc7421713'
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

**Problem:** `Audio` plays every SFX from one 12-player pool and, when all are busy, `_pick_player` steals the player started longest ago. The 6 s `comms_static` played at a cut-off is almost always the oldest, so about 12 overlapping combat SFX during the cut-off hold stop it early (DW-80).

**Approach:** Per the operator decision of 2026-10-10, give `Audio` a separate small comms pool (`COMMS_POOL_SIZE` = 2 players on the SFX bus). `play_sfx` routes every `comms_*` id (`comms_open`, `comms_open_nobeep`, `comms_static`, `comms_click`, `comms_handover`) to the comms pool and every other id to the combat pool. Each pool picks its first free player, else steals its own oldest; a pool never takes a player from the other one.

## Boundaries & Constraints

**Always:** Keep `play_sfx(id, pitch_jitter, volume_db, pitch) -> AudioStreamPlayer` signature and return contract unchanged, so no caller changes. `newest_player()` keeps returning the most recently started player from either pool. The combat pool stays 12 players (`POOL_SIZE`). Comms players are on the `SFX` bus. Statically typed GDScript; no per-call allocation added in `play_sfx` (the comms check is a const dictionary lookup, not string building). Write the failing GUT tests first.

**Never:** No new `tuning.json` key (pool sizes are not tunable, same as `POOL_SIZE`). No change to `CommsChannel` or other callers. No "non-stealable" flag API. Don't edit the deferred-work ledger.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Combat flood during static | `comms_static` playing, then 13+ `laser_zap` | every laser player is a combat-pool player; the static player keeps its stream and keeps playing | No error expected |
| Comms id routing | `play_sfx(&"comms_click")` | returns a comms-pool player | No error expected |
| Comms pool full | 2 comms cues busy, a 3rd comms cue | steals the oldest comms player, never a combat player | No error expected |
| Combat pool full | 12 combat SFX busy, a 13th | steals the oldest combat player (unchanged behaviour) | No error expected |
| Unknown id | `play_sfx(&"nope")` | null, warned once (unchanged) | warn once |

</intent-contract>

## Code Map

- `game/autoloads/audio.gd` -- the only production change. `POOL_SIZE` (l.13), `SFX` registry (l.18-35), pool build in `_ready` (l.58-66: players named `Sfx%d`, `finished` bound to `_on_player_finished(i)`), `play_sfx` (l.76-97), `_pick_player` (l.106-113, the oldest-steal), `_on_player_finished` (l.116). Parallel arrays `_players` / `_in_use` / `_serials`; `_next_serial` is global and `test_player_lethal_feedback.gd` reads `Audio._next_serial` deltas, so every play (either pool) must still bump it by exactly 1.
- `game/systems/comms/comms_channel.gd` -- read-only. Calls `play_sfx` with `comms_open` (l.251), `comms_click`/`comms_handover` (l.298), the combat cue (l.417) and the cut-off `after.sfx` (`comms_static`, l.442); it keeps the returned player to pause/stop the static (`cut_sfx_player`, l.497-519) and checks the stream identity, which keeps working.
- `game/tests/unit/test_audio.gd` -- `_pool()` (l.19) currently returns every `AudioStreamPlayer` child except Music; it must now exclude the comms players too, or `test_pool_of_twelve_on_sfx_bus` and `test_steal_oldest_when_full` break. `_free_all_players()` must free both pools.
- `game/tests/unit/test_comms_channel.gd`, `test_level.gd` -- use `Audio.newest_player()` for comms ids; unaffected if `newest_player` spans both pools.
- `_bmad-output/game-architecture.md` -- Audio Architecture as-built bullet (l.335) and decision D18 (l.168) describe a single 12-player pool; update to mention the 2-player comms pool.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_audio.gd` -- add tests first: comms pool size/bus/names; each comms id routes to a comms player; a full combat pool (12 busy + extra plays) never steals the playing `comms_static` player (still playing, same stream); comms pool steals its own oldest; combat-pool steal unchanged. Update `_pool()` to exclude comms players (via a new `Audio.comms_players()` accessor) and `_free_all_players()` to free both pools -- the pools are now distinct.
- `game/autoloads/audio.gd` -- add `COMMS_POOL_SIZE: int = 2`, a const `COMMS_SFX: Dictionary[StringName, bool]` of the five `comms_*` ids, a second set of parallel arrays for the comms pool (players named `Comms%d`, SFX bus, own `finished` handler), make `_pick_player` take the pool's arrays (or an index range) so each pool steals only its own oldest, route in `play_sfx` by `COMMS_SFX.has(id)`, add `comms_players() -> Array[AudioStreamPlayer]` (tests). Update the header doc comment. -- the fix.
- `_bmad-output/game-architecture.md` -- update D18 and the Audio Architecture pool bullet to describe the reserved comms pool (DW-80). -- keep the architecture as-built accurate.

**Acceptance Criteria:**
- Given `comms_static` is playing from `Audio`, when 20 `laser_zap` SFX are played back to back, then the static's player is still playing `comms_static` and none of the 20 returned players is a comms player.
- Given the game runs a cut-off, when `CommsChannel` calls `play_sfx(&"comms_static")`, then the existing comms-channel and level tests pass with no caller change.
- Given the full headless GUT suite, when it runs, then it passes.

## Spec Change Log

## Review Triage Log

### 2026-10-11 — Review pass
- verdicts: 19 findings — high 0, medium 0, low 16, false 3, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) Cut-off `after.sfx` is data-driven; a non-`COMMS_SFX` id would route to the combat pool unflagged — added `test_every_after_sfx_is_a_comms_sfx` in `tests/data/test_data_files.gd`.
  - `[low]` `[patch]` (blind) No test keeps `COMMS_SFX` in step with the `comms_*` keys of `SFX` — added `test_comms_sfx_matches_the_comms_ids_in_the_registry` (both directions).
  - `[low]` `[patch]` (blind) Routing test copies the id list instead of reading `Audio.COMMS_SFX` — routing test now iterates `Audio.COMMS_SFX`; `COMMS_IDS` is checked against it.
  - `[low]` `[reject]` (blind) A comms player stopped by `_stop_cut_sfx` stays marked in use — same pre-existing semantics as the combat pool; the harmful ordering needs a cut-off static started while a story `comms_open` still plays, which the story-preempt order prevents. Unlikely, and the fix adds branching to the shared picker.
  - `[low]` `[patch]` (blind) No test covers a finished comms player being reused — added `test_finished_comms_player_is_reused`.
  - `[low]` `[patch]` (blind) Comms steal test doesn't assert combat players keep playing — added `assert_true(player.playing)` per combat player.
  - `[false]` `[reject]` (blind) Serial test lacks a known start state / non-null checks — the +2 assertion holds whatever the pool state, and a null return would skip the bump and fail the test.
  - `[low]` `[reject]` (blind) Architecture edits D18 in place without an As-built DW-80 section — only DW-55 among the DW sweeps added a section; the D18 row and the Audio bullet now state the as-built pools accurately.
  - `[false]` `[reject]` (blind) Routing all five `comms_*` ids exceeds the recorded decision — the bundle intent says "and the other comms_* cues".
  - `[low]` `[reject]` (blind) Spec Code Map cites pre-change line numbers — the fix edits this build's spec.
  - `[low]` `[patch]` (edge) Cut-off `after.sfx` not tied to `COMMS_SFX` — same root cause as row 1; covered by `test_every_after_sfx_is_a_comms_sfx`.
  - `[low]` `[patch]` (edge) New `comms_*` id added to `SFX` but not `COMMS_SFX` routes to combat — covered by the registry-sync test.
  - `[low]` `[patch]` (edge) Test `COMMS_IDS` duplicates the production list — covered by the registry-sync test and the `COMMS_SFX`-driven routing test.
  - `[low]` `[patch]` (verification-gap) Comms `finished` reuse untested; oldest-steal yields the same picks — covered by `test_finished_comms_player_is_reused`.
  - `[low]` `[patch]` (verification-gap) Data `after.sfx` not asserted in `COMMS_SFX` — covered by `test_every_after_sfx_is_a_comms_sfx`.
  - `[low]` `[patch]` (intent) Fix tested only at the `Audio` unit surface, not through a real `CommsChannel` cut-off — added `test_a_combat_flood_keeps_the_static` in `test_comms_channel.gd`.
  - `[false]` `[reject]` (intent) A second overlapping comms cue could still steal the static inside the 2-player pool — during the hold a combat request queues (`_request_combat`), and a story request runs `_preempt_combat` → `_clear_combat` → `_reset_cut` (stops the static) before `_start` plays `comms_open`; no comms cue overlaps a live static.
  - `[low]` `[patch]` (intent) Routing is by id, not by caller — same root cause as row 1; covered by `test_every_after_sfx_is_a_comms_sfx`.
  - `[low]` `[reject]` (intent) `comms_channel.gd:52` says "the 2.5 s static" while the ledger says 6.0 s — pre-existing comment untouched by this change; no behaviour impact.

## Design Notes

Two pools, one picker: keep the code shape by storing each pool as its own arrays and having `_pick_player(players, in_use, serials) -> int` work on whichever pool the id belongs to. Two comms players is enough: comms cues are sequential by design (a combat line is silenced during the hold, and a story preempt stops the static before its `comms_open`), so the second player only covers a short cue overlapping a long one.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass

## Auto Run Result

Status: done

**Summary:** `Audio` now has a reserved 2-player comms pool (`COMMS_POOL_SIZE`, players `Comms0`/`Comms1` on the SFX bus) beside the 12-player combat pool. `play_sfx` routes the five `comms_*` ids in the const `COMMS_SFX` to the comms pool and everything else to the combat pool; each pool picks its first free player, else steals only its own oldest. The `play_sfx` API, `newest_player()` and the `_next_serial` bump are unchanged, so no caller changed. A combat flood during the cut-off hold can no longer stop `comms_static` early (DW-80).

**Files changed:**
- `game/autoloads/audio.gd` -- comms pool, `COMMS_SFX` routing, per-pool `_pick_player`, `comms_players()` accessor.
- `game/tests/unit/test_audio.gd` -- pool helpers exclude/free the comms pool; tests for comms pool size/bus/names, registry sync, routing, combat flood vs static, comms self-steal, finished comms reuse, serial bump.
- `game/tests/unit/test_comms_channel.gd` -- real cut-off under a 20-SFX combat flood keeps `cut_sfx_player()` playing the static.
- `game/tests/data/test_data_files.gd` -- every dialogue `after.sfx` is in `Audio.COMMS_SFX`.
- `_bmad-output/game-architecture.md` -- D18 and the Audio Architecture pool bullet describe the reserved comms pool.

**Review findings:** 19 findings (low 16, false 3). Patched 11 rows (5 root causes, all `low`): after.sfx/COMMS_SFX data test, registry-sync test, finished-comms-reuse test, combat-players-keep-playing assertion, CommsChannel-level flood test. Deferred: none. Rejected: stopped comms player stays marked in use (low, unlikely, pre-existing semantics, fix adds picker branching); serial test start state (false); no As-built DW-80 section (low, D18 and bullet already accurate); routing all five ids (false, intent names the other comms_* cues); stale Code Map line numbers (fix edits the spec); second comms cue stealing the static (false, preempt stops the static first); 2.5 s comment (low, pre-existing, untouched).

**Follow-up review recommendation:** false — patched counts: high 0, medium 0, low 5 entries.

**Verification:** `--import` exit 0; full headless GUT suite 1631/1631 passing (85 scripts, 14050 asserts) after patches (1627/1627 before the review patches). The new `test_audio.gd` tests failed before the fix (7 failures) per the implementer.

**Residual risks:** `test_second_story_queues_and_plays_without_unpausing` compares two `comms_open` players; with a 2-player comms pool it depends on the number of comms cues in between and could flip if the dev dialogue changes. Feel of the static under heavy combat is not claimed; operator playtest.
