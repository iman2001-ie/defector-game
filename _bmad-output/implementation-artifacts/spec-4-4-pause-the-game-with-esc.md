---
title: 'Story 4.4: Pause the Game with Esc'
type: 'feature'
created: '2026-10-08'
status: 'done'
baseline_revision: 'd0c8f2e5cdd763f5825a139e772b1c3695f7b780'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-4-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/EXPERIENCE.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A running level can't be paused, restarted or abandoned, so the player can't step away or bail out of a bad attempt. This story covers FR57 and FR8 (pause), using the `menu` pause reason. Tier: MUST.

**Approach:** Add a `PauseMenu` overlay (`ui/menus/pause_menu.tscn` + `.gd`) under `level.tscn`'s `Overlay` layer. The `pause` action (Esc) toggles it. Opening it calls `PauseArbiter.push(&"menu")`. RESUME (or Esc again) calls `PauseArbiter.pop(&"menu")`. RESTART LEVEL calls `SceneRouter.restart_level()`, and QUIT TO TITLE calls `SceneRouter.goto_title()`. The HUD freeze, the shake freeze, the visible cursor and the resume warp already exist, so they only need tests here.

## Boundaries & Constraints

**Always:**
- **PauseArbiter:** add `has_reason(reason: StringName) -> bool` (no allocation) and document it. Nothing else in the arbiter changes.
- **PauseMenu** (`class_name PauseMenu extends Control`, full rect, shared theme, `PROCESS_MODE_ALWAYS`, hidden at start, `MOUSE_FILTER_IGNORE` while hidden and `MOUSE_FILTER_STOP` while shown). The children are `Dim` (a full-rect ColorRect), `Panel` (a Panel holding `Heading`, a `PAUSED` Label) and the buttons `Resume`, `Restart` and `Quit` (texts `RESUME`, `RESTART LEVEL`, `QUIT TO TITLE`, each `FOCUS_NONE`).
  - `_unhandled_input`: on `event.is_action_pressed(&"pause")` (never a raw key, echoes ignored), if the menu is shown it resumes, otherwise it opens. Either way the event is marked handled.
  - `open()` does nothing while `_shown`, while `_leaving`, or while `PauseArbiter.has_reason(&"death")` or `has_reason(&"final_choice")` is true. A `story` reason does not block it. Otherwise it pushes `&"menu"`, shows the menu and logs `Log.info("scene", "Pause menu opened")`.
  - `resume()` (RESUME press or Esc while shown): pops only `&"menu"`, hides the menu and logs `"Pause menu closed"`. It does nothing when the menu isn't shown.
  - RESTART calls `SceneRouter.restart_level()` and QUIT calls `SceneRouter.goto_title()`. The menu stays visible until the scene changes. A `_leaving` guard ignores every later press and every later Esc.
  - Public read accessor `is_shown() -> bool` for tests.
- **Layout** comes from a new `ui.pause_menu` tuning section: `panel_w` 520, `panel_padding_px` 40, `heading_px` 48, `heading_gap_px` 40, `button_w` 400, `button_h` 72, `button_gap_px` 24. The panel is centred on `Playfield.SIZE`. Its height is padding + heading + heading gap + 3 buttons + 2 gaps + padding (432 with the shipped values, so the panel rect is (700, 324, 520, 432)). The heading is centred and full panel width at panel top + padding. The buttons are centred horizontally, with the first top at panel top + padding + heading + heading gap (452, then 548 and 644). Expose a static `panel_rect(canvas: Vector2, ...) -> Rect2` and `button_rects(...) -> Array[Rect2]` like `RetryPrompt.button_rects`.
- **Theme:** add a new `PauseMenu` type to `defector_theme.tres`: `dim` (0,0,0,0.6), `text` #E8F4FF, `panel` = the existing `StyleBoxFlat_retry_button` (surfaceAlt fill, 1px `border`, 4px corners), the button styles reuse the `StyleBoxFlat_retry_button*` boxes, `heading` font 48 and `button` font 28. Copy these onto the children in code, like `retry_prompt.gd::_apply_theme` does. There are no per-node overrides in the `.tscn`.
- **level.tscn:** instance `PauseMenu` under `Overlay`, after `RetryPrompt` and before `DebugTools`.
- Statically typed GDScript. Logging goes through `Log` with no `print()`. Nothing is saved and nothing touches `user://`. Scene changes go only through `SceneRouter`, and pausing only through `PauseArbiter`.
- Tests use a `change_scene` recorder and a test save path, and they reset `GameState` and `PauseArbiter` in `after_each`, as `test_retry_prompt.gd` does.

**Never:** Don't change the retry prompt, the HUD scripts, `ShakeCamera` or `Player._on_resumed`. Don't add the pause menu to the sandbox scene, and don't add F11 (4.5) or a story pause scene (Epic 5). No keyboard menu navigation and no persisted settings. Existing tuning values stay as they are.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Open | level running, no reasons, Esc | `reasons()` == [menu], tree paused, menu visible, mouse mode VISIBLE, one INFO line | none |
| Esc again | menu shown, Esc | `menu` popped, tree unpaused, menu hidden, `resumed` emitted once | none |
| RESUME | menu shown, press Resume | same as Esc again | none |
| Resume under story | reasons {story}, Esc opens, then RESUME | `menu` popped, `story` still active, tree still paused, menu hidden, no `resumed` | none |
| Death | `death` active, Esc | menu stays hidden, reasons unchanged | none |
| Final choice | `final_choice` active, Esc | menu stays hidden, reasons unchanged | none |
| Restart | energy 40, level "2", press RESTART | one change to level.tscn, energy 0, `is_retry` true, `current_level_id` "2", no save file | a second press or Esc is ignored |
| Quit | press QUIT TO TITLE | one change to title.tscn through `goto_title`, no save file written | a second press or Esc is ignored |
| Resume press when hidden | emit `pressed` on Resume while hidden | nothing changes | none |
| Echo | Esc held (echo event) | ignored | none |

</intent-contract>

## Code Map

- `game/autoloads/pause_arbiter.gd` -- `_reasons` dict, `push`/`pop`/`reasons`/`current_mouse_mode`. Add `has_reason`. `resumed` fires only on the paused -> unpaused transition.
- `game/ui/menus/retry_prompt.gd` + `.tscn` -- the pattern to copy: `THEME_TYPE` constants, the `_init` process mode / mouse filter, `_apply_theme` (button style and colour loop), the static rect helpers, the `_leaving` guard and the `.tscn` layout (full rect, `process_mode = 3`, theme ext_resource, authored offsets matching the UX).
- `game/scenes/title/title.gd` -- `FOCUS_NONE` buttons (mouse-only, no focus ring), which the pause menu copies instead of the retry prompt's `grab_focus(true)`.
- `game/scenes/level/level.tscn` -- `Overlay` (layer 30) holds `RetryPrompt` and `DebugTools`. Add the `PauseMenu` ext_resource and node, and bump `load_steps`.
- `game/autoloads/scene_router.gd` -- `restart_level()` (energy 0, `is_retry`, reload) and `goto_title()` (save restore). Read-only.
- `game/entities/player/player.gd:71,434` -- the `warp_mouse` Callable seam and `_on_resumed` (it warps only when the mode is CONFINED_HIDDEN). Read-only. The level test can inject a recorder into `$World/Player.warp_mouse`.
- `game/systems/camera/shake_camera.gd:58` -- shake freezes on `PauseArbiter.is_paused()`. Read-only; `test_shake_camera.gd:76` already covers it.
- `game/ui/hud/*.gd` -- the HUD nodes are `PROCESS_MODE_PAUSABLE` (frozen under the tree pause). Read-only.
- `game/ui/debug/debug_tools.gd:109` -- uses `_unhandled_input` with action names. No Esc binding, so there is no conflict.
- `game/data/tuning.json:275-277` -- `ui.retry_prompt`/`title`/`level_select`. Add `ui.pause_menu` after them.
- `game/ui/theme/defector_theme.tres:48-120` -- the `StyleBoxFlat_retry_button*` sub-resources and the `RetryPrompt/*` entries. Add `PauseMenu/*` in alphabetical position (before `RetryPrompt`).
- `game/project.godot:77` -- the `pause` action already maps to Esc (`test_project_settings.gd:7`).
- `game/tests/unit/test_retry_prompt.gd` -- the fixture to copy (`_record`, `_capture`, test save, `after_each` resets).
- `game/tests/unit/test_level.gd:9-100,166` -- `ROOT_CHILDREN`, `_make_level`, `test_process_modes` and `test_tree`. Add the PauseMenu to the Overlay tree/process-mode checks and an integration test.
- `_bmad-output/game-architecture.md:238,283,630` -- the PauseMenu rows. Mark them built (Story 4.4) and add "As-built 2026-10-08 (Story 4.4)" after the Story 4.3 section, at the end of the file (line 1622+).

## Tasks & Acceptance

**Execution:**
- `game/autoloads/pause_arbiter.gd` -- add `has_reason` -- the menu checks the blocking reasons without allocating.
- `game/data/tuning.json` -- add `ui.pause_menu` -- data-driven layout.
- `game/ui/theme/defector_theme.tres` -- add the `PauseMenu` theme type -- one shared theme.
- `game/ui/menus/pause_menu.tscn` + `pause_menu.gd` (new) -- the menu as specified -- FR57.
- `game/scenes/level/level.tscn` -- instance `Overlay/PauseMenu` -- Esc works in every level.
- `game/tests/unit/test_pause_menu.gd` (new) -- every I/O matrix row, driving Esc with an `InputEventAction` (`action = &"pause"`, `pressed = true`) passed to `_unhandled_input`, plus an echo case using an `InputEventKey` with `echo = true`. Also cover: layout (panel (700, 324, 520, 432), heading at y 364, buttons (760, 452/548/644, 400, 72)), the layout following `ui.pause_menu` tuning, uppercase texts, the theme items applied (dim colour, panel style, button styles, font sizes ≥ 20), `PROCESS_MODE_ALWAYS`, the mouse filter shown and hidden, and the INFO lines.
- `game/tests/unit/test_pause_arbiter.gd` -- `has_reason` true/false, and false after pop and clear.
- `game/tests/unit/test_level.gd` -- `Overlay/PauseMenu` exists with `PROCESS_MODE_ALWAYS`. Integration: Esc in a running level pauses the tree with the HUD nodes still PAUSABLE and the menu shown. RESUME unpauses and the Player's injected `warp_mouse` recorder gets the ship's `global_position` once, while the ship's position stays the same.
- `_bmad-output/game-architecture.md` -- the built rows and the As-built section.

**Acceptance Criteria:**
- Given a level is running, when I press Esc, then `PauseArbiter.push(&"menu")` pauses the game, the pause menu shows RESUME, RESTART LEVEL and QUIT TO TITLE over the dim, the cursor is visible, and the pausable HUD and the shake freeze.
- Given the pause menu is open, when I click RESUME or press Esc, then only `menu` is removed, the game resumes unless another reason is active, and the cursor is warped back onto the unmoved ship.
- Given the pause menu is open, when I click RESTART LEVEL, then energy is 0 and level.tscn reloads the same level id through `SceneRouter.restart_level()`.
- Given the pause menu is open, when I click QUIT TO TITLE, then `SceneRouter.goto_title()` runs and no save file is written.
- Given the `death` or `final_choice` reason is active, when I press Esc, then the pause menu does not open.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 22 findings — high 0, medium 0, low 14, false 8, maybe-false 0
- findings:
  - `[false]` `[reject]` (blind) two dims stack when the menu opens over a story pause -- no story panel or story dim exists yet (Epic 5). The only other dim is the retry prompt's, and its `death` reason blocks the menu.
  - `[low]` `[reject]` (blind) Esc during the 1.5 s death beat opens the menu, before `death` is pushed -- the architecture (line 1034) and the epic AC both key the block on the active reasons, and the spec follows them. The beat timer is pausable, so it just freezes under the menu, and RESUME or RESTART then behave normally. Blocking it would couple the menu to RetryPrompt internals, which adds a branch.
  - `[low]` `[reject]` (blind) the panel reuses the retry button's StyleBox -- DESIGN.md gives buttons and panels the same `surfaceAlt` fill and 1px `border`, so sharing one box keeps them in step. The spec asked for this reuse, and the title and Level Select already share these boxes.
  - `[low]` `[reject]` (blind) the heading size lives in both `ui.pause_menu.heading_px` and the theme `heading` font size -- both are 48. A mismatch only shifts the heading's vertical placement and is cosmetic. Unifying them needs a spec change.
  - `[low]` `[patch]` (blind) `button_size` is the only unclamped tuning read -- now `maxf(..., 1.0)` on both components.
  - `[low]` `[patch]` (blind) the architecture's built-parts summary (line 565) still says "As of Story 4.3" -- now "As of Story 4.4", listing `pause_menu.tscn` + `.gd`.
  - `[false]` `[reject]` (blind) the as-built note claims no design decision changed while adding padding and heading-gap values -- the UX table leaves those two values unset, and they are designer-editable tuning defaults. Earlier stories filled unspecified layout values the same way. No GDD, UX or architecture decision changes.
  - `[false]` `[reject]` (blind) the shake freeze from AC1 is untested -- `test_shake_camera.gd:72` `test_paused_holds_still_and_keeps_remaining` pushes `&"menu"` and asserts the offset holds still and the remaining shake is kept.
  - `[low]` `[patch]` (blind) the level test never sends Esc through the real input path -- grouped with the verification-gap row below; `test_real_esc_key_toggles_the_menu` added.
  - `[false]` `[reject]` (blind) Esc is swallowed even when the menu refuses to open -- no other code handles `pause`. RetryPrompt is mouse-only and FinalChoice doesn't exist. The spec says the event is marked handled either way.
  - `[false]` `[reject]` (blind) RESTART LEVEL sets `is_retry` like a death retry -- intended. EXPERIENCE.md says "On retry or restart, the briefing is skipped", and the epic AC routes RESTART through `restart_level()`.
  - `[false]` `[reject]` (blind) the change set lacks the spec file and the sprint-status update -- the spec is committed at finalize, and `sprint-status.yaml` belongs to the orchestrator and must never be written.
  - `[low]` `[patch]` (edge) unclamped `button_w`/`button_h` -- same root cause and fix as the blind clamp row.
  - `[low]` `[reject]` (edge) `panel_w` tuned narrower than `button_w` lets the buttons overflow the panel -- designer-only data far from the shipped 520/400. The guard would add a cross-value rule.
  - `[false]` `[reject]` (edge) Esc consumed when blocked starves the retry prompt or final choice -- neither handles Esc (the retry prompt is mouse-only; FinalChoice is Epic 6+).
  - `[low]` `[reject]` (edge) a failed scene change after `PauseArbiter.clear()` leaves an undismissable menu over running gameplay -- `change_scene_to_file` fails only for a missing scene, which the router's path tests catch. The retry prompt shares the pattern (rejected the same way in Story 4.3). The fix needs return-value plumbing through the router.
  - `[low]` `[reject]` (edge) gameplay can run for up to one frame between `clear()` and the deferred scene swap -- this is existing router behaviour shared by every scene change (retry prompt, level clear). The scene being replaced is discarded, so the player never sees it.
  - `[false]` `[reject]` (edge) something external pops `menu` while it's shown -- only the menu pushes or pops `menu`, and `clear()` runs only on a scene change, which removes the menu with its scene.
  - `[low]` `[patch]` (verification-gap) no test sends Esc through viewport dispatch or checks the handled flag -- added `test_level.gd::test_real_esc_key_toggles_the_menu`. It pushes a real Esc `InputEventKey` twice into a running level and checks the menu opens and closes, the pause and unpause, and `is_input_handled()` (the subagent confirmed an unbound key leaves the flag false).
  - `[low]` `[patch]` (verification-gap) the `death` block is pinned by a hard-coded string, not RetryPrompt's real reason -- `test_death_blocks_the_menu` now pushes and asserts `RetryPrompt.PAUSE_REASON`.
  - `[low]` `[patch]` (intent) "When I press Esc" was tested only by calling the handler directly -- same root cause and fix as the verification-gap Esc row.
  - `[low]` `[reject]` (intent) clicks, the real cursor and the real scene reload are covered by `pressed.emit()`, the arbiter's mouse mode and a scene-change recorder -- this is the project's established pattern, and a real reload in GUT would replace the test runner. A human play-through is listed as a residual risk.

## Design Notes

Opening over a `story` pause pushes `menu` on top. RESUME pops only `menu`, so the story pause remains, and the arbiter emits no `resumed` because the tree stays paused. UX's "only one dim layer" over the story panel is an Epic 5 concern: there is no story panel yet, and death/final_choice already block the menu, so the menu's dim never stacks with the retry prompt's.

The menu's own panel layout numbers below the heading (padding 40, heading gap 40) are not in the UX table. They are tuning values, so a designer can adjust them.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0 (new `class_name PauseMenu`).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --path game --windowed --quit-after 180` -- expected: `Title ready` in the log, no errors.

## Auto Run Result

Status: done

**Summary:** Esc now pauses a running level. The new `Overlay/PauseMenu` (`ui/menus/pause_menu.tscn` + `.gd`, `class_name PauseMenu`) pushes the `menu` pause reason. It shows a 60% dim and a centred 520-wide `PAUSED` panel with RESUME · RESTART LEVEL · QUIT TO TITLE. RESUME or Esc again pops only `menu`, so a story pause would remain. RESTART calls `SceneRouter.restart_level()` (energy 0, same level from wave 1) and QUIT calls `SceneRouter.goto_title()` (no save). A single-press guard ignores everything after the first press. The menu doesn't open while `death` or `final_choice` is active. While it is open, the existing systems freeze the HUD and the shake and show the cursor, and `Player._on_resumed` warps the cursor back onto the ship on resume. The layout comes from `ui.pause_menu` and the styles from a new `PauseMenu` theme type.

**Files changed:**
- `game/ui/menus/pause_menu.tscn`, `pause_menu.gd` (+ `.uid`) -- the new menu.
- `game/autoloads/pause_arbiter.gd` -- `has_reason(reason)`.
- `game/scenes/level/level.tscn` -- instances `Overlay/PauseMenu` between RetryPrompt and DebugTools.
- `game/data/tuning.json` -- `ui.pause_menu`.
- `game/ui/theme/defector_theme.tres` -- the `PauseMenu` theme type (reuses the retry StyleBoxes).
- `game/tests/unit/test_pause_menu.gd` (+ `.uid`) -- new: every I/O matrix row, layout, theme, echo and the leave guard.
- `game/tests/unit/test_pause_arbiter.gd` -- `has_reason`.
- `game/tests/unit/test_level.gd` -- tree and process mode, Esc → pause → RESUME warp integration, and the real Esc key through viewport dispatch.
- `_bmad-output/game-architecture.md` -- the built rows, the built-parts summary and "As-built 2026-10-08 (Story 4.4)".

**Review findings:** 22 total (high 0, medium 0, low 14, false 8).
- **Patched (4 entries, all low):**
  - the `button_size` clamp
  - the architecture built-parts line
  - the real Esc key test through `push_input`, with the handled-flag check (grouped across the blind, verification-gap and intent rows)
  - `RetryPrompt.PAUSE_REASON` in the death-block test
- **Deferred:** none.
- **Rejected:** 8 false and 7 low. They cover the unbuilt story dim, the reason-keyed death rule during the beat, the shared panel StyleBox, the duplicated heading size, the narrow-panel tuning, the scene-change-failure and one-frame swap patterns shared with the retry prompt, and stand-in test surfaces. The Review Triage Log gives the reason for each.

**Follow-up review recommended:** false. The patched entries were high 0, medium 0, low 4.

**Verification:**
- Headless `--import` -- exit 0.
- Full GUT suite -- before the patches, 1022/1022 passing. After them, 1022/1023 passing with 1 pending: `test_feedback.gd::test_hit_stop_overlap_keeps_longest` marked itself pending because a timing sample came in too late to use. That script re-run alone gave 19/19 passing, and it is not touched by this diff.
- Windowed cold launch (`--quit-after 180`) -- `Title ready 1643 ms after launch`, no errors.
- The I/O matrix audit -- every row has a test that ran and passed.

**Residual risks:**
- No person has pressed Esc and clicked RESUME, RESTART or QUIT in the running game, or judged how the panel looks. The click and reload paths are tested through `pressed` and a scene-change recorder. Only Esc goes through real viewport dispatch.
- During the 1.5 s death beat, before `death` is pushed, Esc can still open the menu. The architecture's reason-based rule allows it. The beat freezes under the menu and continues on resume.
- When Epic 5 adds the story panel, it must make sure only one dim shows when the menu opens over a story pause.
