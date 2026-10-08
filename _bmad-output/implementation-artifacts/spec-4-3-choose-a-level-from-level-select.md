---
title: 'Story 4.3: Choose a Level from Level Select'
type: 'feature'
created: '2026-10-08'
status: 'done'
baseline_revision: 'b3f58984a38eecb728d97ec1009dcb7536d1deb0'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-4-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The title offers only PLAY · QUIT, so a player can't replay an earlier level. This story covers FR56 (Level Select). Tier: MUST.

**Approach:** Add a LEVEL SELECT button between PLAY and QUIT on the title, a new `scenes/title/level_select.tscn` showing one card per campaign level (1..`progression.level_count`) with its number and JSON name, locked cards greyed and not clickable, and a BACK button. Scene changes go through a new `SceneRouter.goto_level_select()`; an unlocked card calls `SceneRouter.start_level(str(n))`, which keeps the energy `goto_title()` restored from the save.

## Boundaries & Constraints

**Always:**
- **SceneRouter:** `const LEVEL_SELECT_SCENE_PATH := "res://scenes/title/level_select.tscn"` and `goto_level_select()`: goes through `_change_to` (pause clear, `Feedback.reset`, one INFO `scene` line). It does not touch `GameState` and writes no save. Update the doc header.
- **Title:** a `LevelSelect` button (text `LEVEL SELECT`) between `Play` and `Quit` in `title.tscn`, styled like the others (`_apply_theme` loop, `FOCUS_NONE`, `custom_minimum_size` from `ui.title`). It calls `SceneRouter.goto_level_select()`, shares the `_leaving` single-press guard, and is hidden/disabled with the others on a config error. QUIT moves down to y 752.
- **Level Select** (`scenes/title/level_select.gd`, `class_name LevelSelectScreen extends Control`, full rect, shared theme): `_ready` calls `PauseArbiter.set_gameplay_mouse_mode(MOUSE_MODE_VISIBLE)` and logs `Log.info("scene", "Level select ready (%d levels, %d unlocked)")`.
  - Cards are built in code under a `Cards` container node, one per id 1..`Config.int_("progression.level_count")` (never hard-code 3). Each card is a `Button` named `Card<n>`, `FOCUS_NONE`, with child labels (`Number` = `LEVEL <n>`, `Name` = the uppercased `name` from `Config.level(str(n))`, `Locked` = `LOCKED`, visible only when locked) and a `Thumbnail` placeholder rect. Children use `MOUSE_FILTER_IGNORE` so clicks reach the card.
  - Unlocked = `GameState.is_level_unlocked(n)` (honours the F7 flag). A locked card has `disabled = true` and `modulate.a = ui.level_select.locked_alpha` (0.4).
  - Layout from a new `ui.level_select` tuning section: `card_w` 480, `card_h` 280, `card_gap_px` 48, `cards_top_y` 360, `back_x` 32, `back_y` 984, `back_w` 240, `back_h` 64, `locked_alpha` 0.4. The card row is centred horizontally on `Playfield.SIZE.x`. Expose a static `cards_rect(canvas_w, card: Vector2, gap, top_y, count) -> Rect2` like `TitleScreen.buttons_rect`.
  - A card press calls `SceneRouter.start_level(str(n))` only if the level is unlocked; `Back` (text `BACK`) calls `SceneRouter.goto_title()`. A `_leaving` guard ignores every press after the first.
  - Config error (`Config.load_error` set; normally unreachable because the title hides its buttons): no cards are built and no Config getter is called; only BACK works, at its authored position.
  - Colours, font sizes and button styles come from a new `LevelSelect` theme type in `ui/theme/defector_theme.tres` (reuse the `RetryPrompt` button StyleBoxes; `text` #E8F4FF, `muted` #93A7C2 for the LOCKED label, `thumbnail` = `heartEmpty` #2B3348; button and name font 28 px, number font 20 px, all ≥ 20 px), copied onto children in code like `title.gd::_apply_theme`.
- UPPERCASE text, mouse-only, statically typed GDScript, logging through `Log`, no `print()`, no save writes, no `user://` access.
- Tests use a `change_scene` recorder, a test save path and reset `GameState` (`energy`, `highest_unlocked_level`, `all_levels_unlocked`, `current_level_id`, `is_retry`) in `after_each`, as `test_title.gd` does.

**Never:** No pause menu (4.4), no F11 (4.5), no story scene (Epic 5), no real level backgrounds or thumbnail art (all levels have `background: null` until Epic 7). Don't change level JSON content, `GameState`, `SaveManager` or existing tuning values. No keyboard menu navigation.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Fresh save | highest 1 | Card1 enabled; Card2, Card3 disabled, alpha 0.4, LOCKED shown | none |
| Mid progress | highest 2 | Cards 1–2 enabled, Card3 locked | none |
| F7 flag | highest 1, `all_levels_unlocked` | all cards enabled | none |
| Pick unlocked | highest 2, energy 40, press Card2 | one change to level.tscn, `current_level_id` "2", energy 40, `is_retry` false | second press ignored |
| Pick locked | press Card3 (or emit `pressed` on it) | no scene change | none |
| Back | press BACK | one change to title.tscn via `goto_title` (save restore) | none |
| Level file broken | `Config.level` returns {} | card still shows `LEVEL n`, empty name | the `data` error Config already logs |
| Config error | `load_error` set | no cards, BACK works, no `[ERROR][data]` lines | none |

</intent-contract>

## Code Map

- `game/autoloads/scene_router.gd` -- `_change_to`, `goto_title`, `start_level`; add `LEVEL_SELECT_SCENE_PATH` and `goto_level_select` near `goto_title`.
- `game/scenes/title/title.gd` -- the pattern to copy: `THEME_TYPE`/style constants, `_apply_theme` (loops `[_play, _quit]`; add the new button), `_layout` (loops `_buttons.get_children()`, so the new child is sized and counted automatically), `_show_config_error` (disable the new button too), `_leaving` guard. Update the doc header ("Story 4.3 adds LEVEL SELECT").
- `game/scenes/title/title.tscn` -- add `LevelSelect` Button between `Play` and `Quit`; the `Buttons` offsets grow to 3 buttons (bottom 824).
- `game/autoloads/game_state.gd:31` -- `is_level_unlocked(n)`, read-only here.
- `game/autoloads/config.gd:103` -- `Config.level(id)` returns the parsed level (logs and returns {} on failure); `int_`/`num` assert on missing keys (never call them while `load_error` is set).
- `game/data/tuning.json` -- `ui.title` section; add `ui.level_select` next to it. `test_config.gd:15` lists top-level sections only (no change needed).
- `game/ui/theme/defector_theme.tres` -- `Title/*` entries and the `StyleBoxFlat_retry_button*` sub-resources to reuse for `LevelSelect/*`.
- `game/core/playfield.gd` (`Playfield.SIZE`) -- the 1920×1080 canvas width for centring.
- `game/tests/unit/test_title.gd` -- fixture to copy (recorder, test save, `_make`, `_make_bad`, `_capture`, `_assert_color`); `test_healthy_layout` QUIT rect becomes `Rect2(760, 752, 400, 72)`, the bad-config tests must also cover the new button.
- `game/tests/unit/test_scene_router.gd:138-160` -- pattern for the new `goto_level_select` tests (`_calls`, `_scene_lines`, `_write_save`).
- `_bmad-output/game-architecture.md:132,665` -- router rows (add `goto_level_select()` as Built, Story 4.3); add "As-built 2026-10-08 (Story 4.3)" after the Story 4.2 section, before the closing `---` at line 1622.

## Tasks & Acceptance

**Execution:**
- `game/autoloads/scene_router.gd` -- add the path constant and `goto_level_select()` with docs -- the router owns every scene change.
- `game/data/tuning.json` -- add `ui.level_select` -- data-driven layout.
- `game/ui/theme/defector_theme.tres` -- add the `LevelSelect` theme type -- one shared theme.
- `game/scenes/title/level_select.tscn` + `level_select.gd` (new) -- the screen as specified (authored `Cards` HBoxContainer/Control, `Back` button at (32, 984) 240×64) -- FR56.
- `game/scenes/title/title.tscn` + `title.gd` -- the LEVEL SELECT button and wiring -- entry point.
- `game/tests/unit/test_level_select.gd` (new) -- every I/O matrix row; layout (cards 480×280, row centred → Card1 at x 192, Card2 at 720, Card3 at 1248, top 360; BACK rect (32, 984, 240, 64)); the layout follows `ui.level_select` tuning; card count follows `progression.level_count`; texts uppercase (`LEVEL 1`, `CARGO AMBUSH`, `THE BLOCKADE`, `SIEGE OF THE THRONE WORLD`); VISIBLE mouse mode and ready line; no save file written; every font size ≥ 20; theme items.
- `game/tests/unit/test_title.gd` -- LEVEL SELECT text/rect (760, 656), press → one change to `LEVEL_SELECT_SCENE_PATH` and no GameState change, second press ignored, bad config hides/disables it.
- `game/tests/unit/test_scene_router.gd` -- `goto_level_select` path constant exists as a resource, one change, one INFO line, pauses cleared, GameState (energy, highest, level id, retry) unchanged, no save written.
- `_bmad-output/game-architecture.md` -- router rows and the As-built section.

**Acceptance Criteria:**
- Given the title screen, when I click LEVEL SELECT, then `level_select.tscn` loads and shows `progression.level_count` cards (Levels 1–3) by name, with locked ones at 40% opacity, labelled LOCKED and not clickable.
- Given I pick an unlocked level, when it loads, then `start_level` runs it with `GameState.energy` equal to the value `goto_title()` restored from the save.
- Given the level select screen, when I click BACK, then I return to the title through `SceneRouter.goto_title()`.
- Given any path through the title or level select, when it runs, then no save file is written and no scene change bypasses `SceneRouter`.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 24 findings — high 0, medium 0, low 18, false 6, maybe-false 0
- findings:
  - `[false]` `[reject]` (blind) the spec file has no hunk in the diff and its logs are empty -- the spec was excluded from the review diff on purpose (it is the claims file), and this step fills the triage log.
  - `[false]` `[reject]` (blind) `sprint-status.yaml` still says backlog -- the orchestrator owns that file; this run must never write it.
  - `[low]` `[reject]` (blind) `Config.level` parses and validates the whole level just to read its name -- three small files each time the menu opens, and the current levels log nothing; a name-only Config API would add public surface.
  - `[low]` `[reject]` (blind) `_leaving` stays set if a scene change fails, so the screen locks up -- `start_level` refuses only on a config error, which this screen already guards, and a failing `change_scene_to_file` means a missing scene that the path tests catch; the title already uses the same pattern; the fix needs return-value plumbing through the router.
  - `[false]` `[reject]` (blind) cards don't refresh when F7 is pressed on Level Select -- F7 lives in DebugTools, which exists only in the level scene, so it can't fire on this screen.
  - `[false]` `[reject]` (blind) locked cards are greyed only by alpha -- DESIGN.md specifies exactly "locked = 40% opacity + `LOCKED` label".
  - `[low]` `[reject]` (blind) the tests emit `pressed` instead of sending real clicks -- `disabled` is asserted, the code guard is tested separately, and a disabled Button ignoring clicks is engine behaviour; a real-input harness is more than a direct fix.
  - `[low]` `[reject]` (blind) degenerate tuning (count 0, oversized row, tiny cards) is untested -- designer-only values far from the shipped data; already guarded by `maxi`/`maxf`.
  - `[low]` `[patch]` (blind) nothing checks that a long name fits its row -- a headless probe showed all three names fit on one line (39 px line, 84 px row); added `test_every_name_fits_its_row` as a regression guard.
  - `[false]` `[reject]` (blind) `_layout` crashes on a non-Button child of `Cards` -- `Cards` has no authored children; only `_build_cards` adds Buttons to it.
  - `[low]` `[patch]` (blind) the `title.gd` header still says "Story 4.3 adds LEVEL SELECT" -- reworded to "LEVEL SELECT (Story 4.3) opens Level Select".
  - `[low]` `[patch]` (blind) rewrapped header comments in `test_title.gd` and `test_scene_router.gd` run past the ~80-column wrap -- rewrapped.
  - `[low]` `[reject]` (blind) `level_select.tscn` authored offsets duplicate `ui.level_select` -- the same convention as `title.tscn` (authored positions match the UX for the config-error branch); the BACK rect is pinned by the bad-config test.
  - `[low]` `[reject]` (edge) `_leaving` stuck on a failed scene change -- same as the blind row; same reason.
  - `[low]` `[reject]` (edge) a large `level_count` pushes cards off-screen -- `level_count` is 3 by design (GDD); a wrap/scale layout is new behaviour.
  - `[low]` `[reject]` (edge) a null or non-string `name` shows `<null>` -- every level file has a string name and Epic 7 owns the content; a type guard for a data error the shipped files can't produce adds a branch.
  - `[low]` `[reject]` (edge) a level that fails validation shows a blank name and re-logs errors on every open -- same root as the blind `Config.level` row; the blank-name case is tested and logged loudly.
  - `[low]` `[reject]` (edge) `locked_alpha` outside 0..1 -- designer-only value; Godot clamps colour alpha when drawing.
  - `[low]` `[reject]` (edge) zero or negative `card_w`/`card_h` -- designer-only value far from the shipped 480x280.
  - `[low]` `[patch]` (verification-gap) the applied card/BACK styleboxes, and the disabled-equals-normal style on locked cards, are never checked -- added `_assert_button_styles` for Card1..3 and BACK plus `test_locked_card_disabled_style_is_the_normal_style`.
  - `[low]` `[patch]` (verification-gap, other) the title's applied button styles aren't checked -- the same helper now covers PLAY, LEVEL SELECT and QUIT in `test_title.gd`.
  - `[false]` `[reject]` (intent) the operator clause could apply because the criteria are player actions -- the clause covers actions outside the repo (domains, keys, consoles); playing the game isn't one, and every criterion is covered in-repo.
  - `[low]` `[reject]` (intent) the tests stop at signals, a recorder and node properties rather than real clicks and rendering -- the project's established pattern (injectable `change_scene`); a human click-through is recorded as a residual risk.
  - `[low]` `[reject]` (intent) the level scene loading with the saved energy is checked only in GameState -- `start_level` keeps `GameState.energy` and the level reads it; that chain is Story 4.2's and is already tested there.

## Design Notes

The card thumbnail is a flat `thumbnail`-coloured placeholder rect: every level's `background` is `null` until Epic 7 adds backgrounds, so there is nothing to show. Epic 7 can fill the `Thumbnail` node without layout changes.

Energy needs no extra code: the only route to Level Select is the title, and `goto_title()` already restored `energy` from the save (F13). `goto_level_select()` deliberately leaves `GameState` alone; BACK uses `goto_title()`, which re-restores the same saved values.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0 (new `class_name LevelSelectScreen`).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all pass.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --path game --windowed --quit-after 180` -- expected: `Title ready` in the log, no errors.

## Auto Run Result

Status: done

**Summary:** The title now offers PLAY · LEVEL SELECT · QUIT. LEVEL SELECT goes through the new `SceneRouter.goto_level_select()` to `scenes/title/level_select.tscn`. That screen shows one card per campaign level (1..`progression.level_count`), each with `LEVEL n`, the uppercased JSON name and a thumbnail placeholder. A locked card is disabled, drawn at 40% opacity and labelled LOCKED (the F7 flag unlocks all). An unlocked card calls `start_level(str(n))`, keeping the energy `goto_title()` restored from the save, and BACK calls `goto_title()`. The layout comes from `ui.level_select`, the styles from a new `LevelSelect` theme type, and nothing writes the save.

**Files changed:**
- `game/autoloads/scene_router.gd` -- `LEVEL_SELECT_SCENE_PATH`, `goto_level_select()`.
- `game/scenes/title/level_select.tscn`, `level_select.gd` (+ `.uid`) -- the new screen (`LevelSelectScreen`).
- `game/scenes/title/title.tscn`, `title.gd` -- the LEVEL SELECT button and its wiring; QUIT moves to y 752.
- `game/data/tuning.json` -- `ui.level_select`.
- `game/ui/theme/defector_theme.tres` -- the `LevelSelect` theme type.
- `game/tests/unit/test_level_select.gd` (+ `.uid`) -- new tests (every matrix row, layout, styles, name fit).
- `game/tests/unit/test_title.gd`, `test_scene_router.gd` -- the new button, applied styles and `goto_level_select` tests.
- `_bmad-output/game-architecture.md` -- router rows, the built tree and "As-built 2026-10-08 (Story 4.3)".

**Review findings:** 24 total (high 0, medium 0, low 18, false 6).
- **Patched (5, all low):** the name-fit regression test, the `title.gd` header wording, the rewrapped test headers, the applied-style tests on cards, BACK and the locked card, and the applied-style tests on the title buttons.
- **Deferred:** none.
- **Rejected (19):** 6 false and 13 low. These are unreachable states (F7 on the menu, non-Button children), the UX spec as written (opacity-only lock), designer-only degenerate tuning, and the scene-change-failure lock-up that the title already shares. The Review Triage Log gives the reason for each.

**Follow-up review recommended:** false. The patched entries were high 0, medium 0, low 5.

**Verification:**
- Headless `--import` -- exit 0.
- Full GUT suite -- 1001/1001 passing, exit 0, after the patches (999/999 before them).
- Windowed cold launch -- `Title ready 2651 ms after launch`, no errors.
- A headless probe of `level_select.tscn` -- every name fits on one 39 px line inside its 84 px row.
- The I/O matrix audit -- every row has a passing test.

**Residual risks:**
- No person has clicked through title → Level Select → a level → BACK in the running game, or judged how locked cards look. The tests drive the buttons through `pressed` and a scene-change recorder.
- The card thumbnail is a flat placeholder until Epic 7 adds level backgrounds.
- The UX font (Kenney Future) isn't in the project yet. Name fit was measured with the default font, and the new test will catch overflow once the font changes.
- If a scene change ever failed, the single-press guard would leave the menu unresponsive. The title has the same pattern.
