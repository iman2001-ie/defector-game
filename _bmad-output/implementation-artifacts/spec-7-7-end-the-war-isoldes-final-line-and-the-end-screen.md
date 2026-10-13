---
title: 'Story 7.7: End the War: Isolde''s Final Line and the End Screen'
type: 'feature'
created: '2026-10-12'
status: done
operator_actions:
  - 'Play Level 3 from Level Select in a debug build ("<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game) with the F1 overlay on, through the Flagship and the Final Choice, and confirm that after the death chain Isolde''s final line ("My finest general... Remember, Arden. I made you.") shows once as a paused story line, that clicking it through opens the end screen, and that no wave or boss phase soft-locks on the way.'
  - 'On the end screen, judge how DEFECTOR, the closing line, "Thanks for playing" and the BACK TO TITLE button read over the placeholder throne-world arc at the DESIGN.md layout; then click BACK TO TITLE and confirm the title opens with Level 3 still unlocked (the save was written).'
  - 'Confirm or reword the end screen''s closing line "The Sovereignty has fallen. The war is over." (decision #57, provisional; the text is EndScreen.TEXT_CLOSING in game/scenes/end/end_screen.gd), and record any change in the decision log.'
baseline_revision: '6474aabe153437b039731ba4640e0344a855847c'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-7-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/EXPERIENCE.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
warnings: ['oversized']
deferred:
  - summary: >-
      Whatever music is playing when Level 3 clears (the boss track from the boss wave's music action) keeps playing on the end screen, because no scene change or end-screen code stops music.
    evidence: |-
      Audio is an autoload and music is stopped only by a `music: stop` action (Audio.apply_music_action); SceneRouter._change_to and EndScreen._ready never touch music. This is the same carry-over every scene change already has (e.g. a level to the title). No music track ships until Story 8.1, so nothing is audible today; Epic 8's audio pass should decide the end screen's music (stop, fade, or an ending theme). The Story 7.7 as-built entry now states the carry-over.
    location: >-
      game/autoloads/scene_router.gd (goto_end) / game/scenes/end/end_screen.gd (_ready)
    severity: medium
---

<intent-contract>

## Intent

**Problem:** Beating the Flagship clears Level 3 straight to the title (the Story 4.2 stand-in): Isolde's written final line (`l3_isolde_final`) never plays and there is no end screen, so the campaign has no ending (FR54, FR60).

**Approach:** Make `l3_isolde_final` Level 3's `outro_sequence` (the existing WaveDirector outro path plays it as a paused story line before `level_cleared(3)`). Add `SceneRouter.goto_end()` and a new `scenes/end/end_screen.tscn`: DEFECTOR, one closing line, "Thanks for playing" and BACK TO TITLE over the throne-world backdrop. `complete_level(level_count)` saves, then goes to the end screen instead of the title.

## Boundaries & Constraints

**Always:**
- **Level data:** `level_3.json` `outro_sequence` becomes `"l3_isolde_final"`. Nothing else in the file changes.
- **SceneRouter:**
  - New `END_SCENE_PATH = "res://scenes/end/end_screen.tscn"` and `goto_end()`. It sets `GameState.current_level_id = ""` and `is_retry = false`, keeps energy and `final_choice` (Story 7.8's epilogue may read the choice), and goes through `_change_to` with the INFO line `Going to the end screen`.
  - `complete_level(n)` for the last level: same unlock and save as today, then `goto_end()`. The save still happens first, and a failed save still moves on.
  - Update the doc comments that say "Epic 7 replaces that".
- **End screen** (`EndScreen extends Control`, written like `TitleScreen`):
  - Nodes: a `LevelBackground` (reused, not copied) drawing `"throne_world"` behind everything, then labels `Logo` (`DEFECTOR`), `ClosingLine`, `Thanks` (`Thanks for playing`) and a `Back` button (`BACK TO TITLE`).
  - The background is the project clear colour (`background` #05070F) plus the arc.
  - Mouse mode: `PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)` in `_ready`.
  - No focus on the button (mouse-only).
  - One `[INFO][scene] End screen ready` line.
- **Back button:** BACK TO TITLE calls `SceneRouter.goto_title()` once. A second press does nothing (a `_leaving` guard).
- **Layout** (healthy config) comes from a new `tuning.json` `ui.end_screen` block: `logo_y` 320, `logo_px` 120, `line_y` 480, `line_px` 30, `thanks_y` 560, `thanks_px` 28, `button_w` 400, `button_h` 72, `button_top_y` 700.
  - Each text label spans the full 1920 width, horizontally centred, with its vertical centre on its `*_y` (as the title logo uses `logo_y`).
  - The button is horizontally centred with its top at `button_top_y` (as the title's `buttons_top_y`).
- **If the config failed to load** (`Config.load_error` set): call no Config getter and keep the positions authored in the `.tscn`, which match the UX values.
- **Theme:** new `EndScreen` type in `ui/theme/defector_theme.tres`, copied in code like the title does:
  - colours `logo` and `logo_glow` (the Title values), `text` and `muted` (#93A7C2)
  - constant `logo_glow_px` 16
  - font size `button` 28
  - the shared retry button styles (normal, hover, focus)
- **Text colours:** `Logo` in `logo` with the glow, `ClosingLine` in `text`, `Thanks` in `muted`.
- **Closing line:** written as the constant `TEXT_CLOSING = "The Sovereignty has fallen. The war is over."` Microcopy lives in code, as in `TitleScreen`. The docs are silent on the wording, so record it as a provisional reading for the operator to confirm.
- **Docs:** add decision-log row #57 (`Spec (Story 7.7)`, provisional, operator to confirm) recording these readings:
  - the closing-line wording
  - text `y` = centre and button `y` = top
  - `goto_end()` keeps energy and `final_choice`
- **Architecture as-built:** add a `## As-built 2026-10-12 (Story 7.7)` entry, and update these places that still say "planned" or "goes to the title" for the last level:
  - the Scene flow table row (`goto_end()` built)
  - the SceneRouter `complete_level` paragraph (~line 1663)
  - Story 7.6's reading (4)/(5) notes, via the new entry only (don't rewrite history)
- **Exactly-once beats:** the Final Choice, the refusal and the final line each fire exactly once per run. No new code is expected for this, because the existing machinery already does it. The tests prove it.

**Never:**
- No council epilogue, `ending.json`, `council_epilogue` flag or `goto_story` change (Story 7.8).
- No change to the WaveDirector, Flagship, CommsChannel, FinalChoice, dialogue text, other level files or `flags.json`.
- No new save field and no save write outside `complete_level`.
- No music or audio change on the end screen (Epic 8).
- No hard-coded layout number in the end screen's healthy-config path.
- No copy of the planet-arc drawing code.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Last level cleared | `complete_level(3)`, highest 3, energy 80 | save [1, 3, 80] written; one change to `END_SCENE_PATH`; `current_level_id` ""; energy 80 kept | — |
| Save fails on last level | unwritable save path, `complete_level(3)` | still one change to `END_SCENE_PATH` | existing `[ERROR][save]` |
| Non-last level | `complete_level(1)` | unchanged: level 2 starts | — |
| BACK TO TITLE | one or two presses | exactly one `goto_title()` (one change to `TITLE_SCENE_PATH`, progress restored from the save) | — |
| Config failed | `Config.load_error` set, end screen built | authored positions and texts, no Config getter called, button still works | — |
| Level 3 outro | boss wave resolves on `boss_defeated` | `l3_isolde_final` requested once, paused story panel named ISOLDE; `level_cleared(3)` only after the click-through; then the save and the end screen | — |

</intent-contract>

## Code Map

- `game/autoloads/scene_router.gd` -- `complete_level()` (last-level branch → `goto_title()` today, ~L212), path constants (L48-52), `_change_to()`; add `END_SCENE_PATH` + `goto_end()`, refresh the header doc.
- `game/scenes/title/title.gd` / `title.tscn` -- the pattern to mirror: `logo_rect()`, `_layout()`, `_apply_theme()`, config-error branch, `_leaving` guard, VISIBLE mouse mode, ready log line. `Playfield.SIZE` gives 1920×1080.
- `game/scenes/level/level_background.gd` -- `LevelBackground.apply("throne_world")`, `shows_throne_world()`; a `Node2D`, so instance it as the end screen's first child (a Node2D under a Control draws in canvas coordinates; fine at the 1920×1080 base).
- `game/ui/theme/defector_theme.tres` -- `Title/*` entries (L184-193) and `LevelSelect/colors/muted` (L160) to copy into a new `EndScreen/*` type.
- `game/data/tuning.json` -- `ui` block; add `end_screen` after `final_choice`.
- `game/data/levels/level_3.json` -- `outro_sequence: null` → `"l3_isolde_final"`.
- `game/data/dialogue/level_3.json` -- `l3_isolde_final` (story, 1 Isolde line) already exists; read-only.
- `game/systems/waves/wave_director.gd` -- `_finish_level()` (~L678) already plays the outro, waits for its `comms_sequence_finished`, then emits `level_cleared`; read-only.
- `game/scenes/level/level.gd` -- `_on_events_level_cleared` → `SceneRouter.complete_level`; read-only.
- `game/systems/comms/comms_channel.gd` -- INFO lines usable as once-only evidence: `Story sequence '%s': final choice shown` (L406), `Final choice '%s': response '%s' started` (L445), `Story sequence '%s' started` (L305).
- `game/tests/unit/test_scene_router.gd` -- `test_complete_last_level_saves_and_goes_to_the_title` (L367) must become the end-screen version; add `goto_end` tests.
- `game/tests/unit/test_level_3.gd` -- shipped-flags full run asserts `TITLE_SCENE_PATH` and requests `[BRIEFING, TAUNT, FINAL_CHOICE]`; update for the outro + end screen; `_load_flags()` helper exists for the all-flags run.
- `game/tests/data/test_data_files.gd` -- `test_level_3_siege_shape` L320-321 asserts a null outro; the sequence table at L1228 already pins `l3_isolde_final`.
- `game/tests/unit/test_title.gd` -- template for the new `test_end_screen.gd` (recorder, layout/tuning override, theme style checks, config-error case via `Config.load_error` / `assert_on_missing`).
- `_bmad-output/game-architecture.md` -- Scene flow row (~L675), SceneRouter paragraph (~L1663), As-built list ends at Story 7.6 (L1952+).
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- last row #56.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_scene_router.gd` -- first (red): replace the last-level title test with `complete_level(3)` → save written, `[END_SCENE_PATH]`, level id "", energy kept; add a failing-save last-level case; add `goto_end()` tests (state, one change, INFO line, pause reasons cleared) -- pins AC2 routing.
- `game/tests/unit/test_end_screen.gd` -- new: scene shape and texts; default layout rects from `ui.end_screen` (logo centre y 320 at 120 px, line centre 480 at 30 px, thanks centre 560 at 28 px, button Rect2(760, 700, 400, 72)); tuning override moves them; colours and button styles from the `EndScreen` theme type; background is a `LevelBackground` showing the throne world and drawn first; VISIBLE mouse mode and ready line; BACK TO TITLE → exactly one title change even on a double press; config-error case calls no getter and keeps the button working -- pins AC2 screen.
- `game/autoloads/scene_router.gd` -- add `END_SCENE_PATH`, `goto_end()`, route the last level to it; update docs -- AC2.
- `game/scenes/end/end_screen.gd` + `end_screen.tscn` -- new `EndScreen` per the Always rules -- AC2.
- `game/ui/theme/defector_theme.tres` -- add the `EndScreen` theme type -- styling.
- `game/data/tuning.json` -- add `ui.end_screen` -- data-driven layout.
- `game/data/levels/level_3.json` -- set the outro -- AC1.
- `game/tests/data/test_data_files.gd` -- `test_level_3_siege_shape` expects `outro_sequence == "l3_isolde_final"` and that it is a story sequence; add a sanity test that `ui.end_screen` fits the 1920×1080 canvas and no text is below 20 px -- AC1.
- `game/tests/unit/test_level_3.gd` -- shipped-flags run: after DYING, assert the outro `l3_isolde_final` shows paused in the panel as ISOLDE with no `level_cleared` yet, click through, then `level_cleared(3)` once, save written, `_scene_calls == [END_SCENE_PATH]`, request order `[BRIEFING, TAUNT, FINAL_CHOICE, l3_isolde_final]`. Add an all-flags-on run (every key in `flags.json` true via `_load_flags`, Hunter Wasps counted) to the end screen choosing DESTROY HER, asserting no stall/clamp/error and exactly one each of: `final_choice_made`, the "final choice shown" line, the "response ... started" line, `l3_isolde_final` requested and started, `boss_defeated`, `level_cleared(3)`, end-screen change -- AC1, AC3.
- `_bmad-output/game-architecture.md` and `decision-log.md` -- as-built entry and row #57 per the Always rules.
- Run `--import` (new `class_name EndScreen`), then the full GUT suite.

**Acceptance Criteria:**
- Given the boss wave resolves on `boss_defeated`, when Level 3's outro runs, then `l3_isolde_final` plays as a paused story line (ISOLDE in the story panel), and only after it is clicked through does `Events.level_cleared(3)` fire and the save get written.
- Given Level 3 is cleared, when `complete_level(3)` runs, then the router calls `goto_end()` and `scenes/end/end_screen.tscn` shows DEFECTOR, the closing line, "Thanks for playing" and BACK TO TITLE on the throne-world backdrop at the DESIGN.md layout, and BACK TO TITLE returns to the title once.
- Given a full Level 3 run on the real `level.tscn` with every flag on, when it is played from wave 1 to the end screen, then no wave or phase stalls or logs a spawn clamp or error, and the Final Choice, the refusal and the final line each fire exactly once.
- Given the full GUT suite runs headless, then it passes with no new failures.

## Spec Change Log

## Review Triage Log

### 2026-10-12 — Review pass
- verdicts: 22 findings — high 0, medium 5, low 8, false 9, maybe-false 0
- findings:
  - `[medium]` `[defer]` (blind) Boss music keeps playing on the end screen and the as-built entry claims "no music or audio on the end screen". — Real once tracks ship (Story 8.1), but it is the existing carry-over of every scene change. Deferred to Epic 8's audio pass (frontmatter `deferred`). The as-built wording was corrected to state the carry-over.
  - `[false]` `[reject]` (blind) `epic-7-context.md` is stale after this story lands (outro null, 7.7 described in future tense). — This story edits `decision-log.md`, so the cached context is newer-than-planning-artifacts invalid at Story 7.8's step 1 and is recompiled there.
  - `[false]` `[reject]` (blind) The spec is untracked and sprint-status still says backlog. — The spec is committed at finalization, and `sprint-status.yaml` is owned by the orchestrator, which this run must never write.
  - `[low]` `[reject]` (blind) No test plays to the end screen with a story flag off. — No flag gates the boss wave, the outro or the router. The flag-off runs already cover the gated beats, so a full run per flag adds about 3 minutes of tests for no new path.
  - `[low]` `[reject]` (blind) The Level 3 outro on a retry is untested. — The WaveDirector outro-on-retry path is generic and already tested. Level 3 adds only data.
  - `[false]` `[reject]` (blind) The closing line is duplicated in the `.tscn` and the constant, so the scene copy can drift. — `_ready` always sets every text from the constants, healthy or bad config, so the scene text never shows. This is the same pattern as `title.tscn` / `TitleScreen`.
  - `[low]` `[reject]` (blind) `EndScreen.text_rect` copies `TitleScreen.logo_rect`. — It is a 2-line static helper. Coupling the end screen to the title screen's class would cost more than the duplication. Unlikely to cause trouble.
  - `[low]` `[patch]` (blind) The `ui.end_screen` values are pinned in two tests. — Deleted `test_tuning` from `test_end_screen.gd`. `test_end_screen_ui_tuning` keeps the pin.
  - `[false]` `[reject]` (blind) The no-overlap check uses the font height, not the 2x label box. — The label boxes are transparent and the text is vertically centred, so the visible extent is about the font size. Overlapping boxes alone show nothing.
  - `[false]` `[reject]` (blind) The last-level router test starts at highest 3, so it can't prove the unlock raise. — `test_complete_level_unlock_never_passes_the_level_count` starts at 2 and asserts the raise to 3 through the same branch.
  - `[low]` `[patch]` (blind) `test_goto_end_writes_no_save` duplicates the no-save check. — Deleted it. `test_goto_end_clears_the_level_and_keeps_energy_and_choice` asserts the save is unchanged.
  - `[false]` `[reject]` (blind) The failed-save last-level test doesn't check `is_retry` / `final_choice`. — Both paths run the same `goto_end()`, whose state changes the success-path and `goto_end` tests assert. The failure only affects the save.
  - `[low]` `[patch]` (blind) Architecture line 264 still says the End screen is Epic 7. — Appended "The End screen was built in Story 7.7 (`goto_end()`)."
  - `[low]` `[reject]` (blind) `test_level_3.gd` hard-codes `save_version` 1. — This matches the existing `test_scene_router.gd` `_read_save` pattern. A version bump would touch every save test anyway.
  - `[medium]` `[defer]` (edge) `goto_end()` doesn't stop the boss music. — Same root cause as the first row. Deferred to Epic 8.
  - `[low]` `[reject]` (edge) A stale `final_choice` from an earlier run could reach Story 7.8's epilogue. — Only reachable through debug F3 (in play, the core can't die before the choice). Story 7.8 owns how the epilogue reads it.
  - `[false]` `[reject]` (edge) The overlap test measures font px, not the 2x box. — Same refutation as the blind overlap row.
  - `[medium]` `[patch]` (intent) What is owed to the operator isn't in `operator_actions` / `awaiting-operator`. — Finalized with `status: awaiting-operator` and three `operator_actions` (the playtest to the end screen, the end-screen read, the closing-line wording).
  - `[medium]` `[patch]` (intent) AC3's "when I play" is shown only by a scripted headless run. — Same entry: the human Level 3 run to the end screen is now operator action 1.
  - `[false]` `[reject]` (intent) No test runs the router into the loaded end screen. — GUT can't call the real `change_scene_to_file` without replacing the runner. The router test pins `END_SCENE_PATH`, `test_end_scene_path` checks the resource exists, and `test_end_screen.gd` instantiates that same file.
  - `[medium]` `[patch]` (intent) The closing-line wording is owed to the operator but sits in no action list. — Same entry: operator action 3.
  - `[false]` `[reject]` (intent) `epic-7-context.md` is rewritten outside the Code Map. — The workflow's step 1 recompiles it when it is stale, as in Stories 7.1-7.5. It is not story scope, and no code depends on it.

## Design Notes

- **Why the outro path:** `WaveDirector._finish_level()` already plays `outro_sequence` as a story and waits for it before `level_cleared`. Levels 1 and 2 use the same path, so AC1 is a data change plus tests.
- **Why constants:** the closing line and "Thanks for playing" are microcopy like the title's `TEXT_PLAY`. `Config` has no string getter for tuning, and the line is not dialogue (it has no speaker).
- **Why keep `final_choice`:** `goto_end()` keeps `GameState.final_choice` so 7.8 can route `goto_story(&"ending_council", end)` without touching the end screen. `goto_title()` already leaves it alone.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: completes (the class cache gains `EndScreen`).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failures. `<GODOT_DIR>` comes from `LOCAL.md`.

**Manual checks (if no CLI):**
- Owed to the operator: play Level 3 to the end screen and judge how the final line lands, how the end screen reads and whether the closing-line wording fits.

## Auto Run Result

Status: awaiting-operator

**Summary:** Beating the Flagship now ends the war. Level 3's `outro_sequence` is `l3_isolde_final`, so Isolde's final line plays as a paused story line through the existing WaveDirector outro path. Only after the click-through do `level_cleared(3)` and the save happen. `SceneRouter.complete_level` for the last level then calls the new `goto_end()`, which opens `scenes/end/end_screen.tscn`: DEFECTOR, the closing line, "Thanks for playing" and BACK TO TITLE over the reused throne-world `LevelBackground`, laid out from the new `ui.end_screen` tuning. This replaces the Story 4.2 return to the title.

**Files changed:**
- `game/data/levels/level_3.json`: the outro is `l3_isolde_final`.
- `game/autoloads/scene_router.gd`:
  - adds `END_SCENE_PATH` and `goto_end()` (clears the level id and the retry flag, keeps the energy and `final_choice`)
  - the last level now routes to `goto_end()`
- `game/scenes/end/end_screen.gd` and `end_screen.tscn` (new): the `EndScreen` Control.
- `game/ui/theme/defector_theme.tres`: new `EndScreen` theme type.
- `game/data/tuning.json`: new `ui.end_screen` block.
- `game/tests/unit/test_end_screen.gd` (new): layout, theme, backdrop, the back button and the config-error case.
- `game/tests/unit/test_scene_router.gd`: tests for the last level to the end screen (including a failed save) and for `goto_end()`.
- `game/tests/unit/test_level_3.gd`: the shipped-flags run goes through the final line to the end screen, plus a new all-flags-on run that checks each beat happens exactly once (AC3).
- `game/tests/data/test_data_files.gd`: checks the outro and the `ui.end_screen` layout.
- `_bmad-output/game-architecture.md`: the Story 7.7 as-built entry, the scene-flow row and the SceneRouter notes.
- `decision-log.md`: row #57 (provisional readings).
- `_bmad-output/implementation-artifacts/epic-7-context.md`: recompiled because it was stale.

**Review findings:** 22 findings in total (high 0, medium 5, low 8, false 9).
- **Patches applied, 4 entries:**
  - one medium entry: finalized as awaiting-operator with `operator_actions`
  - three low entries: deleted 2 duplicate tests, and fixed the stale architecture line 264 note
  - the music wording in the as-built entry was also corrected
- **Deferred, 1 entry (medium):** the boss music carries over onto the end screen. Nothing is audible until Story 8.1 ships the tracks, so Epic 8's audio pass should decide it.
- **Rejected:** every other finding, each with its reason in the Review Triage Log.

**Follow-up review recommendation:** false. Patched entries by verdict: high 0, medium 1, low 3.

**Verification:**
- `--import`: exit 0.
- Full GUT suite (headless): 1826 of 1826 tests passed before the review patches, and 1824 of 1824 after them (2 duplicate tests deleted).
- Every row of the I/O matrix has a covering test, and each of those tests ran and passed.

**Residual risks:**
- How the final line lands, how the end screen reads and whether the closing-line wording fits are not verified. They are owed to the operator through `operator_actions`.
- The AC3 run is a scripted headless run (invincible player, direct damage, synthetic clicks), not real play.

## Operator Confirmation

Confirmed 2026-10-13: the external actions this story owed were carried out.

- Play Level 3 from Level Select in a debug build ("<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game) with the F1 overlay on, through the Flagship and the Final Choice, and confirm that after the death chain Isolde's final line ("My finest general... Remember, Arden. I made you.") shows once as a paused story line, that clicking it through opens the end screen, and that no wave or boss phase soft-locks on the way.
- On the end screen, judge how DEFECTOR, the closing line, "Thanks for playing" and the BACK TO TITLE button read over the placeholder throne-world arc at the DESIGN.md layout; then click BACK TO TITLE and confirm the title opens with Level 3 still unlocked (the save was written).
- Confirm or reword the end screen's closing line "The Sovereignty has fallen. The war is over." (decision #57, provisional; the text is EndScreen.TEXT_CLOSING in game/scenes/end/end_screen.gd), and record any change in the decision log.

_Appended by the bmad-loop orchestrator (`bmad-loop confirm`, #335): a human confirmed these external actions out of band, and the story was advanced from `awaiting-operator` to `done`._
