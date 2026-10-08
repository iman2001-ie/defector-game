---
title: 'Story 4.2: Unlock the Next Level and Save Progress'
type: 'feature'
created: '2026-10-08'
status: 'done'
baseline_revision: 'cfdd4044ac6c169bafafe4d4927607492ed649f8'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-4-context.md'
warnings: ['oversized']
deferred:
  - summary: >-
      test_feedback.test_hit_stop_overlap_keeps_longest is wall-clock sensitive and failed once in a full run ("resumed promptly": 356 ms, expected < 250 ms), then passed on re-run.
    evidence: |-
      Pre-existing flake, not caused by Story 4.2 (feedback.gd and test_feedback.gd are untouched). Seen in the first full GUT run of this story's verification; the immediate re-run and the post-patch run were 973/973 and 977/977. The same test also flips to Pending ("second hit_stop came too late").
    location: >-
      game/tests/unit/test_feedback.gd:262
    severity: low
---

<intent-contract>

## Intent

**Problem:** Clearing a level only shows a placeholder banner. Nothing unlocks, nothing is saved, PLAY always starts Level 1 and `goto_title()` zeroes the energy. This story covers FR58, FR14 (energy carry-over) and FR56 (continue), plus decision F13. Tier: MUST.

**Approach:** Add a `SaveManager` autoload (the only code that touches `user://`) that reads and writes `[progress]` in `user://save.cfg`. When a campaign level is cleared, `SceneRouter.complete_level(n)` raises the unlock, saves and starts level n+1 (or goes to the title after the last level). `goto_title()` restores from the save, PLAY continues at the highest unlocked level, and F7 unlocks every level in memory. It also fixes retro F1: a dead attempt can no longer clear the level.

## Boundaries & Constraints

**Always:**
- **SaveManager** (`autoloads/save_manager.gd`, autoload between `GameState` and `PauseArbiter`, no `class_name`): `SAVE_VERSION = 1`, `DEFAULT_SAVE_PATH = "user://save.cfg"`, `var save_path: String = DEFAULT_SAVE_PATH` (tests inject their own path). No file I/O in `_ready`.
  - `load_progress() -> Dictionary` returns `{"highest_unlocked_level": int, "energy": int}`. A missing file returns the defaults (1, 0) and logs `Log.info("save", …)`. It returns the defaults and logs `Log.warn("save", …)` when the file is corrupt (`ConfigFile.load` fails with anything other than file-not-found), when `save_version` is missing, not an int or not 1, or when either value is missing, not an int, `highest_unlocked_level < 1` or `energy < 0`. It never crashes and never calls a `Config` getter.
  - `save() -> bool` writes `[progress] save_version=1, highest_unlocked_level=GameState.highest_unlocked_level, energy=GameState.energy` to `save_path`. It logs `Log.info("save", …)` with the values, or `Log.error("save", …)` and returns false when the write fails.
- **GameState:** add `var highest_unlocked_level: int = 1` and `var all_levels_unlocked: bool = false` (debug F7, memory only, never saved, never reset by `goto_title`). Add `func is_level_unlocked(n: int) -> bool` (`all_levels_unlocked or n <= highest_unlocked_level`) for Story 4.3.
- **Tuning:** add a top-level `"progression": {"level_count": 3}` to `data/tuning.json`. This is the number of campaign levels; never hard-code 3.
- **SceneRouter:**
  - `goto_title()`: restores `energy` and `highest_unlocked_level` from `SaveManager.load_progress()` (replacing `energy = 0`). When `Config.load_error` is empty, it clamps `highest_unlocked_level` into 1..`progression.level_count` and `energy` into 0..`GameState.max_energy()`. It still clears `is_retry` and `current_level_id`.
  - New `complete_level(n: int)`: a campaign level is `1 <= n <= level_count`. Anything else (the dev level is id 0) only logs `Log.info("scene", "Level %d cleared: not a campaign level; no save, no scene change")` and returns. For a campaign level it sets `highest_unlocked_level = max(current, min(n + 1, level_count))` and calls `SaveManager.save()`. Then, if `n < level_count`, it calls `start_level(str(n + 1))` (energy carried); otherwise `goto_title()` (Epic 7 replaces this with the end screen). If the write fails, the transition still happens.
  - Saving happens nowhere else: not in `goto_title`, `start_level` or `restart_level`, and not on quit or F7.
- **Level (`scenes/level/level.gd`):** in `_ready`, after the stress redirect and before `_director.start_level`, connect `Events.level_cleared` to a handler that calls `SceneRouter.complete_level(level_id)`. The router itself does not listen to `Events`, because WaveDirector unit tests clear levels with ids 1, 3 and 5 and must not change scenes or save.
- **WaveDirector (retro F1):** connect `Events.level_failed` in `_ready` to set `_failed = true`. `start_level` and `debug_skip_to_boss` reset it. `_try_clear` and `_finish_level` return early while `_failed` is set, so a dead attempt never emits `wave_cleared`/`level_cleared`. Death after `level_cleared` needs no policy, because the router changes the scene on the same call.
- **Title:** PLAY calls `SceneRouter.start_level(str(GameState.highest_unlocked_level))`. Remove `FIRST_LEVEL_ID` and update the doc comments. F7 does not change PLAY.
- **DebugTools F7** (`debug_unlock_all`, debug builds only, as for F1–F6): `unlock_all()` sets `GameState.all_levels_unlocked = true`, logs `Log.info("debug", "F7: all levels unlocked (in memory, not saved)")` and never calls `SaveManager`.
- Tests never read or write the real save. Every test that can reach `goto_title`, `complete_level` or `SaveManager` sets `SaveManager.save_path` to a test path (`user://test_*.cfg`) in `before_each`, deletes that file and restores `DEFAULT_SAVE_PATH` in `after_each`, and resets `highest_unlocked_level`/`all_levels_unlocked`. This covers `test_scene_router`, `test_boot`, `test_retry_prompt`, `test_title` and the new tests.
- Statically typed GDScript, logging through `Log` (`save`, `scene`, `debug`), no `print()`, action names only.

**Never:** No Level Select screen or button (4.3), no pause menu (4.4), no F11 (4.5), no end screen or story scenes (Epics 5/7). Don't change level JSON content, the existing tuning values or the LEVEL CLEAR banner (it now shows for at most a frame on campaign levels; Epic 5's debrief replaces it). Don't save anywhere except `complete_level`. Don't touch `user://` outside `SaveManager` in game code.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| No save | file missing | `{highest 1, energy 0}` | INFO, no warn |
| Round trip | save() with highest 2, energy 40 | file has `save_version=1`, 2, 40; load returns 2, 40 | none |
| Corrupt | garbage text in file | defaults | `Log.warn("save")`, no crash |
| Unknown version | `save_version=2` (or missing) | defaults | `Log.warn("save")` |
| Bad values | highest 0, energy -5, or a string | defaults | `Log.warn("save")` |
| Clear L1 | highest 1, energy 35 | highest 2; save written (2, 35); `start_level("2")` with energy 35 | none |
| Clear L1 again | highest 3 | highest stays 3; save (3, energy); start "2" | none |
| Clear L3 | highest 3, energy 80 | save (3, 80); change to the title; GameState restored (3, 80) | none |
| Clear dev / id 5 | id 0 or > level_count | INFO only; no save, no scene change | none |
| Quit to title | in memory energy 70, saved 20 | energy 20, highest from save | none |
| PLAY | highest 2 | `start_level("2")`, energy unchanged | second press ignored |
| F7 | debug build | `all_levels_unlocked` true; `is_level_unlocked(3)`; save file unchanged | release: nothing |
| Dead attempt | `level_failed`, then the last kill | no `wave_cleared`, no `level_cleared` | none |

</intent-contract>

## Code Map

- `game/autoloads/scene_router.gd` -- `start_level`, `goto_title` (currently `energy = 0`), `restart_level` and `_change_to` (clear pauses, `Feedback.reset`, INFO line, `change_scene.call`). Add `complete_level` and the restore here.
- `game/autoloads/game_state.gd` -- the `energy`/`current_level_id`/`is_retry` fields and `max_energy()`. Add the two fields and `is_level_unlocked`, and update the doc ("Saving and carry-over arrive with Epic 4").
- `game/project.godot:20-30` -- the `[autoload]` block. Insert `SaveManager="*res://autoloads/save_manager.gd"` after GameState. `config/use_custom_user_dir` is already set. The `debug_unlock_all` action (F7) already exists.
- `game/tests/unit/test_project_settings.gd:27` -- the expected autoload order list. Add SaveManager.
- `game/autoloads/log.gd:12-14` -- the `save` and `debug` categories already exist.
- `game/autoloads/config.gd` -- `int_()` asserts on missing keys (don't call it while `load_error` is set). `test_data_files`/`test_config` may pin the tuning shape; check them when adding `progression`.
- `game/systems/waves/wave_director.gd:81-95,200-210,426-455` -- `_ready`, the `start_level` reset (`_level_done = false`), the `debug_skip_to_boss` reset, `_try_clear` and `_finish_level`.
- `game/tests/unit/test_wave_director.gd:20-60,497-504` -- the fixture (Events recorders, `_start(waves, id = 3)`, `_kill`, `GAP_S`) and the last-wave clear test to copy for the F1 test.
- `game/scenes/level/level.gd:34-66` -- `_ready`. Connect `level_cleared` after the redirect `return`. `test_level.gd` plays `level_dev` (id 0) to a clear, which must stay a no-op.
- `game/scenes/title/title.gd:14,31,98-102` -- `FIRST_LEVEL_ID` and `_on_play_pressed`.
- `game/ui/debug/debug_tools.gd:1-12,108-129,146-150` -- the doc header, the `_unhandled_input` chain and the `add_energy()` pattern for `unlock_all()`. Debug-disabled builds return early.
- `game/tests/unit/test_debug_tools.gd` -- the action-event helper `_action_event`, `_make_tools` and the log capture for the F7 test.
- `game/tests/unit/test_scene_router.gd:12-30,106-120` -- the fixture and the goto_title test, which currently expects energy 0 and must now expect the saved value.
- `game/tests/unit/test_boot.gd:18-30`, `test_retry_prompt.gd:20-27,250-260`, `test_title.gd` -- fixtures that reach `goto_title`/PLAY. Add the test save path. Retry-prompt QUIT expects energy 0, which still holds with a missing test save.
- `_bmad-output/game-architecture.md:159,181,192-211,539,579,661,798` -- D9, the state table, energy and save rules, the F7 row (Planned), the directory tree, the ownership row and the wave-flow line. Add "As-built 2026-10-08 (Story 4.2)" after the Story 4.1 section, before the closing `---`.

## Tasks & Acceptance

**Execution:**
- `game/autoloads/save_manager.gd` -- new SaveManager as specified -- the single save owner.
- `game/project.godot` -- register the autoload in order -- architecture autoload order.
- `game/autoloads/game_state.gd` -- `highest_unlocked_level`, `all_levels_unlocked`, `is_level_unlocked` and the docs.
- `game/data/tuning.json` -- `progression.level_count: 3`.
- `game/autoloads/scene_router.gd` -- the `goto_title` restore with clamping, plus `complete_level`, and the docs.
- `game/scenes/level/level.gd` -- the `level_cleared` → `SceneRouter.complete_level` wiring.
- `game/systems/waves/wave_director.gd` -- the `_failed` guard (retro F1).
- `game/scenes/title/title.gd` -- PLAY continues at `highest_unlocked_level`.
- `game/ui/debug/debug_tools.gd` -- F7 `unlock_all()`.
- `game/tests/unit/test_save_manager.gd` (new) -- the missing, round-trip (read back with a raw `ConfigFile` too), corrupt, unknown-version, missing-version and bad-value rows, each warn asserted through `Log.sink`, and no file I/O at construction.
- `game/tests/unit/test_scene_router.gd` -- `goto_title` restores from a test save (energy 20 in the file, 70 in memory → 20), clamps a saved highest of 9 to 3, and gives defaults with no file. `complete_level` covers the L1, L1-again, L3 and dev/5 rows (assert the file contents, GameState, the recorded path and `current_level_id`). Add `goto_title`, `start_level` and `restart_level` write no save file.
- `game/tests/unit/test_level.gd` -- a level instance with a `change_scene` recorder on SceneRouter and a test save: emitting `Events.level_cleared(1)` reaches `complete_level` (recorded level path, `current_level_id` "2"); `level_cleared(0)` changes nothing.
- `game/tests/unit/test_wave_director.gd` -- dead attempt: `Events.level_failed` and then the last kill emit no `wave_cleared`/`level_cleared` after the gap, and a new `start_level` resets the guard.
- `game/tests/unit/test_title.gd` -- PLAY with highest 3 starts "3"; the existing PLAY test still records "1" with the default.
- `game/tests/unit/test_debug_tools.gd` -- F7 sets the flag, logs and leaves the test save file absent. With debug disabled, nothing changes.
- `game/tests/unit/test_game_state.gd` -- the defaults and `is_level_unlocked` with and without the flag.
- `game/tests/unit/test_project_settings.gd`, `test_boot.gd`, `test_retry_prompt.gd` -- the autoload order and the test-save fixtures.
- `_bmad-output/game-architecture.md` -- update the referenced rows (SaveManager built, F7 built, the level-clear flow with the listener in `level.gd`, `progression.level_count`) and add the As-built section.

**Acceptance Criteria:**
- Given no save file, when the game boots (boot → `goto_title`), then `GameState.highest_unlocked_level` is 1 and `energy` is 0, and PLAY starts level "1".
- Given a corrupt or unknown-version save, when the game boots, then a `[WARN][save]` line is logged, the defaults are used and nothing crashes.
- Given I clear campaign level N < level_count, when `Events.level_cleared(N)` fires in the level scene, then the unlock becomes max(current, N+1), the save holds `save_version=1` with that unlock and the current energy, and level N+1 starts with that energy. Given N = level_count, the save is written and the title opens.
- Given a saved game, when I click PLAY, then the highest unlocked level starts with the saved energy.
- Given I quit to the title mid-level, when `goto_title()` runs, then energy and unlocks equal the saved values, not the in-memory values (F13).
- Given any path other than a campaign level clear (title, start, retry, quit, F7), when it runs, then no save file is written.
- Given a debug build, when I press F7, then every level reports unlocked in memory and the save is untouched.
- Given the player died, when the last counted enemy then dies, then the level never clears (retro F1).

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 28 findings — high 0, medium 0, low 19, false 9, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) a failed save on the last level is followed by `goto_title()`, which reloads the older file, so the in-memory unlock is lost -- needs a disk write failure (rare), and that progress wasn't persisted anyway; the fix adds a parameter or branch to the router.
  - `[false]` `[reject]` (blind) `complete_level` calls `Config.int_` without a `load_error` check -- unreachable: with a config error the title disables PLAY and `start_level` refuses, so no level runs and nothing can emit `level_cleared`.
  - `[low]` `[patch]` (blind) nothing ties `progression.level_count` to the level files -- added `test_data_files.test_every_campaign_level_has_a_file` (levels 1..level_count load with id i).
  - `[false]` `[reject]` (blind) `level.gd` trusts the JSON id instead of the file key -- `test_data_files` already pins `level_<i>.json` to `id` i, and the new campaign-file test does it for every campaign level.
  - `[false]` `[reject]` (blind) Quit to Title → Play keeps the saved energy while Retry gives 0 -- this is decision F13 (decision-log row 21, epics F13), an accepted quirk.
  - `[low]` `[reject]` (blind) no campaign-complete state, so energy can be built up by replaying -- matches the GDD rule (energy is saved on every clear); energy is capped at `energy.max`, and Epic 7 owns the end of the campaign.
  - `[low]` `[patch]` (blind) no test proves the F7 flag never reaches the save -- added `test_scene_router.test_f7_flag_never_leaks_into_the_save` (the save holds highest 2, and the flag stays on).
  - `[low]` `[reject]` (blind) `is_level_unlocked` doesn't range-check `n` -- it has no caller yet; Story 4.3 iterates the real ids 1..level_count; the guard would add a Config dependency to GameState.
  - `[low]` `[reject]` (blind) the save isn't written atomically -- needs a crash during a tiny write; the result is a WARN plus defaults, not a crash; temp-file-and-rename adds complexity.
  - `[false]` `[reject]` (blind) with a config error, out-of-range saved values reach GameState unclamped -- in that state no level can start and PLAY is disabled, so nothing reads them.
  - `[low]` `[reject]` (blind) no retry-prompt QUIT test with a real save -- QUIT → `goto_title` is tested in `test_retry_prompt`, and the restore in `goto_title` is tested in `test_scene_router`; the chain is one call.
  - `[low]` `[reject]` (blind) the save-fixture helpers are copied across test files -- per-file fixtures are the existing convention (e.g. the router `change_scene` recorder); a shared fixture is a refactor, not a correction.
  - `[low]` `[patch]` (blind) the F7 test reuses `_f4_lines`/`_capture_f4` -- renamed to `_debug_lines`/`_capture_debug`.
  - `[false]` `[reject]` (blind) `goto_title` reads `.get` defaults it can never need -- equivalent behaviour, no named harm; the defensive default costs nothing.
  - `[false]` `[reject]` (blind) the architecture wave-flow bullet and "Play and Level Select load the saved energy" now contradict the build -- the bullet summarises the flow and the appended as-built sentence names the listener; Play does start with the saved energy (restored at the title).
  - `[low]` `[reject]` (edge) a failed save on the last level loses the in-memory unlock -- same root cause as the first blind row; rejected for the same reason.
  - `[low]` `[reject]` (edge) non-atomic save write -- same as the blind atomic-save row.
  - `[low]` `[patch]` (edge) a death during the gap after a non-final wave still starts the next wave -- `_try_clear` now returns after the gap when `_failed` is set; added `test_death_during_a_gap_never_starts_the_next_wave`.
  - `[false]` `[reject]` (edge) the JSON id may differ from the file key -- same as the blind id row; pinned by `test_data_files`.
  - `[false]` `[reject]` (edge) `complete_level` with a config error -- same as the blind Config row; unreachable.
  - `[false]` `[reject]` (edge, claim) the handler passes the signal's id rather than the level's `level_id` -- the spec's `complete_level(level_id)` refers to the `Events.level_cleared(level_id: int)` argument; `complete_level` takes an int, and the level's `level_id` is the String file key.
  - `[low]` `[patch]` (verification-gap) no test proves `debug_skip_to_boss` resets the dead-attempt guard -- added `test_f6_resets_the_dead_attempt_guard`.
  - `[low]` `[reject]` (intent) no test plays `level_1.json` to a real clear -- `test_level` already plays `level_dev` to a clear with real kills, and the new `test_level` cases prove the scene wires `level_cleared` to the router; a full level-1 run would add a long test for the same wiring.
  - `[low]` `[reject]` (intent) the real `%APPDATA%\DEFECTOR\save.cfg` location isn't exercised -- `test_project_settings` pins `use_custom_user_dir`/`DEFECTOR`, and the real windowed launch logged `user://save.cfg` and created no file.
  - `[low]` `[reject]` (intent) the boot-level bad-save test uses an unknown version, not garbage text -- garbage text is covered in `test_save_manager`; boot only calls `goto_title`, which calls `load_progress`.
  - `[low]` `[reject]` (intent) no single test chains save → restore → PLAY -- each link is tested (`complete_level` writes, `goto_title` restores, PLAY reads `highest_unlocked_level`); same composition argument as the QUIT row.
  - `[false]` `[reject]` (intent) quitting the application isn't tested for no-save -- `SaveManager.save()` has exactly one game-code caller (`scene_router.gd:93`, `complete_level`), so no other path can save.
  - `[low]` `[reject]` (intent) the LEVEL CLEAR banner now shows for at most a frame on campaign levels -- the banner is a placeholder; the spec records this and the UX flow replaces it with Epic 5's debrief.

## Design Notes

F7 uses a separate flag rather than raising `highest_unlocked_level`. Otherwise the next level clear would persist the debug unlock through `max(current, N+1)`, which breaks "F7 never writes the save". The flag also survives `goto_title`'s restore, so Story 4.3's Level Select can honour it after the player leaves the level where F7 was pressed. PLAY continues the real progress.

The level scene, not the router, subscribes to `level_cleared`. WaveDirector unit tests run bare directors with ids 1/3/5. A global router listener would call the real `change_scene_to_file` (replacing the GUT runner) and write saves mid-suite.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0 (new autoload script).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all pass.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --path game --windowed --quit-after 180` -- expected: the log shows `[INFO][save]` with no save file (defaults), then `Title ready`. No save file is created by the launch.

## Auto Run Result

Status: done

**Summary:** Clearing a campaign level now goes through `SceneRouter.complete_level(n)`, which `level.gd` calls on `Events.level_cleared`. It raises `highest_unlocked_level` to max(current, n+1), saves through the new `SaveManager` autoload and starts level n+1 with the carried energy. After the last level (`progression.level_count`, 3) it goes to the title. `SaveManager` is the only code that touches `user://`. It reads and writes `[progress] save_version=1, highest_unlocked_level, energy`, and a missing, corrupt, unknown-version or bad-value save gives the defaults (1, 0), with a WARN for every case except a missing file. `goto_title()` restores energy and unlocks from the save (F13), PLAY continues at the highest unlocked level, and F7 sets an in-memory `all_levels_unlocked` flag that is never saved. Retro F1 is fixed: once `level_failed` fires, the WaveDirector never clears a wave or the level and never starts the next wave.

**Files changed:**
- `game/autoloads/save_manager.gd` (+ `.uid`) -- new SaveManager: `load_progress()`, `save()`, an injectable `save_path`.
- `game/project.godot` -- SaveManager autoload between GameState and PauseArbiter.
- `game/autoloads/game_state.gd` -- `highest_unlocked_level`, `all_levels_unlocked`, `is_level_unlocked(n)`.
- `game/autoloads/scene_router.gd` -- the `goto_title` save restore with clamping; the new `complete_level(n)`.
- `game/data/tuning.json` -- `progression.level_count: 3`.
- `game/scenes/level/level.gd` -- `level_cleared` → `SceneRouter.complete_level`.
- `game/systems/waves/wave_director.gd` -- the `_failed` dead-attempt guard (retro F1).
- `game/scenes/title/title.gd` -- PLAY starts `highest_unlocked_level`; `FIRST_LEVEL_ID` removed.
- `game/ui/debug/debug_tools.gd` -- F7 `unlock_all()`.
- `game/tests/unit/test_save_manager.gd` (+ `.uid`) -- new tests.
- `game/tests/unit/test_scene_router.gd`, `test_level.gd`, `test_wave_director.gd`, `test_title.gd`, `test_debug_tools.gd`, `test_game_state.gd`, `test_boot.gd`, `test_retry_prompt.gd`, `test_project_settings.gd`, `test_config.gd`, `game/tests/data/test_data_files.gd` -- new cases and test-save fixtures.
- `_bmad-output/game-architecture.md` -- D9, state, save rules, F7, ownership and wave-flow rows; "As-built 2026-10-08 (Story 4.2)".

**Review findings:** 28 total.
- **Patched (5, all low):** the death-in-gap guard in `wave_director.gd` plus its test, the F6 guard-reset test, the F7-never-leaks-into-the-save test, the campaign-level-files data test, and the renamed debug-tools test helpers.
- **Deferred (1):** the pre-existing `test_feedback` hit-stop timing flake. It came from verification, not from a reviewer.
- **Rejected (23):** 9 false and 14 low. They are F13 or GDD decisions, states that can't be reached, or composition that is already tested. The Review Triage Log gives the reason for each.

**Follow-up review recommended:** false. The patched counts are high 0, medium 0, low 5.

**Verification:**
- Headless `--import` -- exit 0.
- Full GUT suite -- 977/977 passing, exit 0, after the patches. Before the patches, one run had one failure in the pre-existing `test_feedback` timing flake, and the re-run was 973/973.
- Real windowed cold launch -- `[INFO][save] No save at user://save.cfg; using defaults (level 1, energy 0)`, then `Title ready 2053 ms after launch`. No `save.cfg` was created.
- The I/O matrix audit -- every row has a passing test.

**Residual risks:**
- No person has yet played Level 1 to a clear in the real game and confirmed that Level 2 starts and that the save survives a relaunch. The logic is covered by unit and scene tests.
- The LEVEL CLEAR banner is now effectively invisible on campaign levels until Epic 5's debrief.
- F7 works only inside a level (where DebugTools lives). Story 4.3 may want it on Level Select too.
- The spec's baseline was moved to `cfdd404` because the orchestrator committed the 4-1 operator confirmation during this run.
