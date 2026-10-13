---
title: 'Story 7.8: Hear the Council Epilogue'
type: 'feature'
created: '2026-10-12'
status: done
operator_actions:
  - 'Play Level 3 from Level Select in a debug build ("<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game) with the shipped flags, through the Flagship and the Final Choice, and confirm that after Isolde''s final line the council epilogue (ending_council) plays once in the story panel, that clicking it through opens the end screen once, and that nothing soft-locks on the way.'
  - 'Judge the six epilogue lines in game/data/dialogue/ending.json (wording, pacing, and the one choice-neutral line about the Final Choice), reword them there if needed, and record any change against decision #58 in the decision log.'
  - 'Confirm that council_epilogue should ship true in game/data/flags.json; if you set it false instead, also update FLAG_DEFAULTS in game/tests/unit/test_config.gd and the ships-on assert in test_council_epilogue_flag_and_sequence (game/tests/data/test_data_files.gd), and record the decision in the decision log.'
baseline_revision: 'c5df06966d42d838c7a5d09b2dfb055d4174f4a2'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-7-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/EXPERIENCE.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Clearing Level 3 goes straight from Isolde's final line to the end screen. The council epilogue (FR55, COULD) doesn't exist: there is no `council_epilogue` flag, no `ending_council` sequence, and the router can't send a story scene to the end screen, because `finish_story()` only loads a level (or the title).

**Approach:** Add a `council_epilogue` flag and a new `data/dialogue/ending.json` holding the story sequence `ending_council`. Let `goto_story` take an "end screen" target, so `finish_story()` can call `goto_end()`. When the flag is on, `complete_level` for the last level saves and then calls `goto_story(&"ending_council", STORY_NEXT_END)`. When the flag is off, it calls `goto_end()` as it does today.

## Boundaries & Constraints

**Always:**
- **SceneRouter** (`game/autoloads/scene_router.gd`):
  - New constants next to `OPENING_SEQUENCE`: `ENDING_SEQUENCE: StringName = &"ending_council"` and `STORY_NEXT_END: int = -1`. These are scene-flow wiring, not tuning.
  - `goto_story(id, STORY_NEXT_END)` stores the pending story like any other target. Its INFO line is `Story '<id>' before the end screen`; level targets keep `Story '<id>' before level N`. It is still refused while `Config.load_error` is set.
  - `finish_story()` with a pending `STORY_NEXT_END` clears the pending story, then calls `goto_end()`. The other targets are unchanged: `>= 1` loads that level, and nothing pending warns and goes to the title.
  - `complete_level(level_count)` does the same unlock and save first (a failed save still moves on). Then:
    - if `Config.load_error` is empty and `Config.flag("council_epilogue")` is true: `goto_story(ENDING_SEQUENCE, STORY_NEXT_END)`
    - otherwise: `goto_end()`
  - Update the header doc comments for `goto_story`, `finish_story`, `complete_level` and `goto_end`.
- **Flag:** add `"council_epilogue": true` to `game/data/flags.json` as the last key. It ships on, so the player hears the story's scene, like every other story-beat flag. Flipping it to false cuts the epilogue with no code change.
- **Dialogue:** new `game/data/dialogue/ending.json` with one sequence, `ending_council`, in `mode: "story"`. It has no `choice` and these 6 lines, in this order:
  1. `ryn`: "All ships, stand down. Her home fleet has laid down its arms, General. It's over."
  2. `tarek`: "They won't let me fly yet, but they let me sit at the table. I wouldn't miss this, General."
  3. `ryn`: "Every free world sent a delegate. No sovereign and no throne this time. A council, where every world has a voice."
  4. `tarek`: "Whatever you told Isolde at the end, she was never going to kneel. That choice was always hers."
  5. `tarek`: "There's a seat on the council for you, General. Not as anyone's weapon. As one voice among many."
  6. `vale`: "Then I'll take it. No more thrones."
- **The choice line:** line 4 is the only line that refers to the Final Choice, and it fits either option. The epilogue plays the same lines whatever `GameState.final_choice` holds (`&"surrender"`, `&"destroy"` or `&""`). Nothing reads or changes `final_choice`.
- **Story scene:** `story.gd` needs no logic change. It already calls `finish_story()` once, also for an unknown id. Update only its header comment ("loads the pending level or the end screen").
- **Docs:**
  - Decision-log row #58 (`Spec (Story 7.8)`, provisional, operator to confirm) records these readings:
    - the flag ships true
    - `STORY_NEXT_END` / `ENDING_SEQUENCE` are the "next = end" target
    - line 4 is the one choice-neutral line, because the dialogue format has no conditional lines and both options end in Isolde's refusal
    - the wording is provisional
    - with a config load error, the last level goes to the end screen directly
  - Architecture:
    - add the flag to the Feature flags row (~L450)
    - add `ending.json` to the Dialogue row (~L452)
    - add a `## As-built 2026-10-12 (Story 7.8)` entry after Story 7.7's
    - add a one-sentence pointer to it in the SceneRouter `complete_level` paragraph (~L1663)

**Never:**
- No change to the end screen, the WaveDirector, the Flagship, CommsChannel, FinalChoice, `level_3.json` or any existing dialogue line.
- No new dialogue-format feature (no conditional or templated lines) and no second epilogue sequence.
- No new save field and no save outside `complete_level`. Nothing saves after the epilogue.
- No backdrop, music or audio change on the story scene (Epic 8).
- No hard-coded wording in code: the lines live only in `ending.json`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Flag on, last level | `complete_level(3)`, flag true, energy 80, choice `destroy` | save [1, 3, 80] first; one change to `STORY_SCENE_PATH`; pending `ending_council` / `STORY_NEXT_END`; energy and choice kept; INFO `Story 'ending_council' before the end screen` | — |
| Flag off, last level | `complete_level(3)`, flag false | save; one change to `END_SCENE_PATH`, no story pending (today's behaviour) | — |
| Flag on, save fails | unwritable save path | still one change to `STORY_SCENE_PATH` | existing `[ERROR][save]` |
| Flag on, config error | `Config.load_error` set, `complete_level(3)` | one change to `END_SCENE_PATH`, never a refused story | — |
| Epilogue finishes | story scene plays `ending_council` to the end | `finish_story()` once → `goto_end()`: `[STORY, END]`, level id "", pending cleared, energy and choice kept; a late click or repeat finish changes nothing more | — |
| Either choice | `final_choice` `surrender`, `destroy` or `""` | the same 6 lines play, then the end screen | — |
| Level 1 path | `start_level("1")` → `finish_story()` | unchanged: the opening, then level 1 | — |

</intent-contract>

## Code Map

- `game/autoloads/scene_router.gd` -- header doc L13-45; constants L53-61 (add the two new ones after `OPENING_LEVEL_ID`); `goto_story` L159 (the log message); `finish_story` L183 (add the END branch before the `< 1` check); `complete_level` L229 (the last-level branch, L236-239); `goto_end` L245, reused as-is.
- `game/scenes/story/story.gd` -- header comment only (L12-14). `_finish()` already calls the router once.
- `game/data/flags.json` -- 4 keys today. Add `council_epilogue`.
- `game/data/dialogue/opening.json` -- the format to copy for `ending.json`. `Config` loads every `data/dialogue/*.json` by name, so the new file needs no registration. Story lines are at most 200 chars (`comms.story_line_max_chars`).
- `game/autoloads/config.gd` -- `flag()` L106 returns false and logs a `data` error when the key is missing or not a bool. Read-only.
- `game/tests/unit/test_config.gd` -- `FLAG_DEFAULTS` L17 and `test_flags_have_the_four_defaults` L106: add the key and rename the test to five.
- `game/tests/unit/test_scene_router.gd` -- `after_each` L38 resets router and GameState. The last-level rows (L372, L388) now depend on the flag, so set `Config.flags["council_epilogue"]` explicitly and restore it in `after_each`. Story rows are at L497-614.
- `game/tests/unit/test_story_scene.gd` -- `_make_with(id, next_level)`, `_click_through()` and the `_calls` recorder are the pattern for the epilogue-to-end tests.
- `game/tests/unit/test_level_3.gd`:
  - `_drive_flagship_to_the_end_screen` (L452) asserts `[END_SCENE_PATH]` after the outro click-through (L516). With the shipped flag on, the router now records `STORY_SCENE_PATH`.
  - The shipped-flags run is at L536 and the all-flags run at L556. `_load_flags(overrides)` is at L192, and `after_each` reloads the shipped config.
- `game/tests/data/test_data_files.gd`:
  - `CAMPAIGN_DIALOGUE_FILES` and `CAMPAIGN_SCRIPT` (L1210-1229)
  - `test_campaign_script_layout` asserts 15 sequences
  - `MAX_VALE_LINES` (5) and its comment (L1235)
  - the gendered and "someone addresses the General" checks (~L1400-1415) apply to every campaign file
- `game/tests/unit/test_level.gd` -- `test_level_cleared_reaches_the_router` (L218): `level.gd` passes `level_cleared(n)` straight to `complete_level(n)`.
- `_bmad-output/game-architecture.md` -- the Feature flags and Dialogue rows (L450-452), the SceneRouter paragraph L1663, and the Story 7.7 as-built entry (L1962, the last one).
- `decision-log.md` -- the last row is #57.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_scene_router.gd` -- write these first (red):
  - the flag-on last-level row: save first, then the story is pending with `STORY_NEXT_END`
  - the flag-off row: the existing end-screen rows, with the flag set false
  - a flag-on failed save
  - flag on with a config error goes to the end screen
  - `finish_story()` with the END pending calls `goto_end()` once, and a second finish goes to the title as today
  - `goto_story(id, STORY_NEXT_END)` stores the pending story and logs the end-screen line
  - the constants
- `game/tests/unit/test_story_scene.gd` -- `ending_council` pending to the end: it plays in the panel, and the click-through gives `[STORY, END]` once. Repeat for each `final_choice` value (`surrender`, `destroy`, `""`): the same line count and speakers, then the end screen.
- `game/autoloads/scene_router.gd` -- the constants, `goto_story` / `finish_story` / `complete_level` per Always, and the docs.
- `game/data/flags.json`, `game/data/dialogue/ending.json` -- the flag and the sequence, per Always.
- `game/scenes/story/story.gd` -- the header comment.
- `game/tests/unit/test_config.gd` -- five defaults.
- `game/tests/data/test_data_files.gd`:
  - add `ending.json` and the row `["ending.json", "ending_council", "story", ["ryn", "tarek", "vale"], 3, 8]`, which brings the count to 16
  - update the `MAX_VALE_LINES` comment (the cap stays 5)
  - add a test: `flags.council_epilogue` is a bool and ships true; `ending_council` has no `choice`; at most one of its lines contains a choice word (`surrender`, `destroy`, `choice`, `chose`, `offer`, `mercy`, `spare`, case-insensitive); every line fits `comms.story_line_max_chars`
- `game/tests/unit/test_level_3.gd`:
  - Make `_drive_flagship_to_the_end_screen` end on the shipped route: after the outro click-through, the save, then `_scene_calls == [STORY_SCENE_PATH]` with `ending_council` / `STORY_NEXT_END` pending.
  - Add a helper that frees the level, as the real scene change does (so its CommsChannel can't also play the request), then instances `story.tscn`, clicks it through and asserts `_scene_calls == [STORY_SCENE_PATH, END_SCENE_PATH]`, with `ending_council` requested once.
  - Both full runs (shipped and all flags on) use it, and their request order gains `ending_council`.
  - Add a cheap test: `_load_flags({"council_epilogue": false})`, the real level.tscn on level 3, then emit `Events.level_cleared(3)`. Expect `_scene_calls == [END_SCENE_PATH]` and no story pending.
- `_bmad-output/game-architecture.md`, `decision-log.md` -- per Always.
- Run `--import`, then the full GUT suite.

**Acceptance Criteria:**
- Given the shipped flags (`council_epilogue` true), when Level 3 is cleared on the real `level.tscn` after Isolde's final line, then the save is written, the router opens the story scene with `ending_council` from `data/dialogue/ending.json`, and clicking it through opens the end screen exactly once.
- Given any `GameState.final_choice`, when the epilogue plays, then the same lines play and at most one of them refers to the choice.
- Given `council_epilogue` is false, when Level 3 is cleared, then the end screen shows directly with no story scene.
- Given the full GUT suite runs headless, then it passes with no new failures.

## Spec Change Log

## Review Triage Log

### 2026-10-12 — Review pass
- verdicts: 28 findings — high 0, medium 1, low 22, false 5, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) EXPERIENCE.md Flow 3 and its story-scene row show only the opening, and the build now adds the epilogue without saying so. — Decision #58 gains (6): the UX flow leaves out the COULD epilogue, which (with the flag on) plays between the final line and the end screen in the same story scene.
  - `[low]` `[patch]` (blind) The architecture's Story-box paragraph (L264) and Scene flow row (L675) have no Story 7.8 entry. — Added a Story 7.8 sentence to each.
  - `[low]` `[reject]` (blind) The "As of Story 6.1" directory sentence is out of date and leaves out `scenes/end/`. — It was already stale before this story (it missed the Story 7.7 end screen). This diff only added `ending.json`, and nothing reads that sentence as a contract.
  - `[false]` `[reject]` (blind) `epic-7-context.md` describes the state before the change. — It is the planning cache compiled for this story at step 1. This story edits `decision-log.md`, so the cache becomes invalid and is recompiled at the next story's step 1.
  - `[low]` `[reject]` (blind) `epic-7-context.md` contradicts itself on the story scene's backdrop. — Cosmetic, in a cache that is invalid and gets recompiled next time; no code reads it.
  - `[low]` `[reject]` (blind) The `epic-7-context.md` rewrite dropped some requirement bullets. — Same cache. The GDD and earlier specs still hold those requirements, and the next recompile reads them again.
  - `[low]` `[reject]` (blind) No guard for a missing or invalid `ending_council`. — The story scene's existing unknown-id path finishes at once and still reaches the end screen (no soft-lock). The shipped data is pinned by `test_council_epilogue_flag_and_sequence`. A guard would add a branch for a case players can't reach.
  - `[low]` `[reject]` (blind) `goto_story` accepts targets like 0 or -2. — The same behaviour existed before this story. Every caller passes a level id or `STORY_NEXT_END`.
  - `[false]` `[reject]` (blind) The epilogue replays on every Level 3 clear. — The AC says "When Level 3 is cleared", which covers every clear. Isolde's outro already replays the same way.
  - `[low]` `[patch]` (blind) The music under the epilogue is not mentioned. — Added the carry-over to the Story 7.8 as-built entry and to decision #58 (7). It is the same carry-over Story 7.7 deferred to Epic 8.
  - `[low]` `[patch]` (blind) The flag-off Level 3 test skips `_assert_clean_log()` and the level-id check. — Added both, plus an assert message.
  - `[low]` `[patch]` (blind) The every-choice test compares only speakers. — The recorder now captures each line's text from the panel and compares speakers and text against the data for `surrender`, `destroy` and `""`.
  - `[low]` `[patch]` (blind) `CHOICE_WORDS` misses "choose" and similar words. — Added `choose`, `decide` and `decision`, plus a self-check case.
  - `[low]` `[reject]` (blind) The data test repeats the ships-true pin and the length check. — The spec's task asks for both. The cost is one extra place to edit if the operator flips the flag, and that place is named in operator action 3.
  - `[low]` `[patch]` (blind) The config-error router test doesn't check the save or the INFO line. — It now sets energy 80 and highest 3, asserts the save [1, 3, 80] and the "Going to the end screen" line.
  - `[low]` `[reject]` (blind) Wording notes: the throne image repeats, "General" appears 3 times, and line 1 sounds like a surrender. — These are provisional wording calls owed to the operator (decision #58 (4), operator action 2). Line 1 is about the fleet, not Isolde's Final Choice.
  - `[low]` `[reject]` (edge) A guard for an invalid `ending_council` (`dialogue_is_story`). — Same reason as the blind row: the unknown-id path recovers, and the shipped data is tested.
  - `[low]` `[reject]` (edge) `goto_story` with a target of 0 or below -1. — Same reason as the blind row: unchanged from before, and no such caller exists.
  - `[low]` `[patch]` (edge) A failed full run in `test_level_3.gd` can leave the epilogue pending in SceneRouter for later suites. — `after_each` now resets `_story_id` and `_story_next_level`.
  - `[low]` `[patch]` (edge) `CHOICE_WORDS` misses "choose", "decide" and "decision". — Grouped with the blind row; same patch.
  - `[low]` `[patch]` (edge) The every-choice test should compare text, not only speakers. — Grouped with the blind row; same patch.
  - `[false]` `[reject]` (intent) AC2 could mean a choice-aware line (reading B2), but the diff is choice-neutral. — "At most one line may reference" is a cap, and one choice-neutral line meets it. A choice-dependent line would need a dialogue-format change, which the spec rules out.
  - `[low]` `[reject]` (intent) The choice-reference check matches words, not meaning. — No automated check can judge meaning. The operator reads the wording (action 2).
  - `[false]` `[reject]` (intent) The real scene-change chain level → story → end is only checked at the call level. — GUT can't call the real `change_scene_to_file` without replacing the test runner. The Level 3 test frees the level and instances the real `story.tscn`, and `test_end_scene_path` pins the end scene.
  - `[low]` `[reject]` (intent) The flag-off test emits `level_cleared(3)` instead of playing the level through. — `level.gd` passes `level_cleared` straight to `complete_level`. Another 3-minute full run per flag adds no new path (the same call Story 7.7 made).
  - `[low]` `[reject]` (intent) With `tarek_fall` off, line 2 assumes Tarek was injured. — The existing script already assumes the fall under any flag: `l2_ryn_report` ("He's alive. Barely.") and `l3_briefing` ("my father's fleet"). The epilogue matches it, and flags gate beats, not text.
  - `[medium]` `[patch]` (intent) The owed playtest and the provisional readings are not in `operator_actions` / `awaiting-operator`. — Finalized with `status: awaiting-operator` and three `operator_actions`, following the Epic 7 convention.
  - `[false]` `[reject]` (intent) The config-error route is behaviour no AC asks for. — It is not a defect. It stops a broken config from leaving the player stuck on a cleared level, because `goto_story` refuses on a config error.

## Design Notes

- **Why a sentinel and not a second method:** the AC says `goto_story(&"ending_council", next = end)`, and the architecture's Scene flow row already lists `goto_story(id, next)`. A `STORY_NEXT_END` value keeps one pending-story path. `story_next_level()` returns it, and the story scene doesn't care where it goes.
- **Why `complete_level` checks `load_error`:** `goto_story` refuses while the config is broken. Without the check, the last level would change no scene and the player would be stuck on the cleared level.
- **Why choice-neutral:** both options end in Isolde's refusal, and the dialogue format has no conditional lines. So one line that fits either choice meets "at most one line" without a format change.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: completes.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failures. `<GODOT_DIR>` comes from `LOCAL.md`.

**Manual checks (if no CLI):**
- Owed to the operator: play Level 3 to the end with the flag on, and judge the epilogue's wording and pacing and whether shipping it on is right.

## Auto Run Result

Status: awaiting-operator

**Summary:** Clearing Level 3 now plays a short council epilogue before the end screen. The new `council_epilogue` flag in `flags.json` ships on. With it on, `SceneRouter.complete_level` for the last level saves first, then calls `goto_story(ENDING_SEQUENCE, STORY_NEXT_END)`. The story scene plays `ending_council` from the new `data/dialogue/ending.json`: six lines from Ryn, Tarek and Vale, and only one of them refers to the Final Choice, in words that fit either option. When it finishes, `finish_story()` goes to the end screen through `goto_end()`. With the flag off, or while the config failed to load, the end screen opens directly, as in Story 7.7.

**Files changed:**
- `game/autoloads/scene_router.gd`:
  - new constants `ENDING_SEQUENCE` and `STORY_NEXT_END`
  - `goto_story` accepts the end-screen target and logs which target it uses
  - `finish_story()` with that target goes to the end screen
  - the last level's `complete_level` checks the flag and the config error
  - doc comments updated
- `game/data/flags.json`: `council_epilogue: true`.
- `game/data/dialogue/ending.json` (new): the `ending_council` story sequence.
- `game/scenes/story/story.gd`: header comment only.
- `game/tests/unit/test_scene_router.gd`:
  - the Story 7.7 last-level rows now pin the flag off
  - new rows: flag on, the save before the change, a failed save, a config error, levels below the last, the end target, and finishing to the end screen
  - `after_each` restores the flag
- `game/tests/unit/test_story_scene.gd`: the epilogue to the end screen once, with the same speakers and text for every Final Choice value.
- `game/tests/unit/test_level_3.gd`:
  - both full runs now go through the epilogue in the real `story.tscn` to the end screen
  - new flag-off test
  - `after_each` resets the pending story
- `game/tests/unit/test_config.gd`: five flag defaults.
- `game/tests/data/test_data_files.gd`:
  - `ending.json` added to the campaign script (16 sequences)
  - new test of the flag and the sequence, with a choice-word check and its self-check
- `_bmad-output/game-architecture.md`:
  - the flags and dialogue rows
  - the Story-box paragraph and the Scene flow row
  - the SceneRouter paragraph and the directory list
  - a new Story 7.8 as-built entry
- `decision-log.md`: row #58, with provisional readings (1)-(7).
- `_bmad-output/implementation-artifacts/epic-7-context.md`: recompiled at step 1 because it was stale.

**Review findings:** 28 in total (high 0, medium 1, low 22, false 5).
- **Patches applied, 9 entries:**
  - one medium entry: finalized as awaiting-operator with `operator_actions`
  - eight low entries:
    - the UX note in decision #58
    - the architecture rows
    - the music carry-over note
    - the flag-off test's clean-log and level-id checks
    - the every-choice test now compares the line text
    - `CHOICE_WORDS` extended
    - the config-error test checks the save and the INFO line
    - `test_level_3` resets the pending story
- **Deferred:** none. The music carry-over is the existing Story 7.7 deferral to Epic 8, now noted in the docs.
- **Rejected:** every other finding, each with its reason in the Review Triage Log.

**Follow-up review recommendation:** false. Patched entries by verdict: high 0, medium 1, low 8.

**Verification:**
- `--import`: exit 0, both before and after the review patches.
- Full GUT suite (headless): 1838 tests, 1837 passed and 1 pending. The pending one is `test_feedback.gd` `test_hit_stop_overlap_keeps_longest`, skipped by its own timing guard; it is unrelated to this story. 0 failures, both before and after the patches.
- Every row of the I/O matrix has a covering test, and each of those tests ran and passed:
  - router: flag on, flag off, failed save, config error, finish to the end screen, Level 1 path
  - story scene: the epilogue and every choice
  - Level 3: shipped and all-flags runs, and flag off

**Residual risks:**
- The epilogue's wording and pacing, and whether to ship it on, are provisional (decision #58). They are owed to the operator.
- The scene changes level → story → end are simulated in tests: the router is a recorder, and the test instances the story scene by hand. A real run is operator action 1.
- The boss music carries over under the epilogue once tracks ship (Epic 8).

## Operator Confirmation

Confirmed 2026-10-13: the external actions this story owed were carried out.

- Play Level 3 from Level Select in a debug build ("<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game) with the shipped flags, through the Flagship and the Final Choice, and confirm that after Isolde's final line the council epilogue (ending_council) plays once in the story panel, that clicking it through opens the end screen once, and that nothing soft-locks on the way.
- Judge the six epilogue lines in game/data/dialogue/ending.json (wording, pacing, and the one choice-neutral line about the Final Choice), reword them there if needed, and record any change against decision #58 in the decision log.
- Confirm that council_epilogue should ship true in game/data/flags.json; if you set it false instead, also update FLAG_DEFAULTS in game/tests/unit/test_config.gd and the ships-on assert in test_council_epilogue_flag_and_sequence (game/tests/data/test_data_files.gd), and record the decision in the decision log.

_Appended by the bmad-loop orchestrator (`bmad-loop confirm`, #335): a human confirmed these external actions out of band, and the story was advanced from `awaiting-operator` to `done`._
