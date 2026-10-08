---
title: 'Story 4.5: Play Fullscreen or Windowed'
type: 'feature'
created: '2026-10-08'
status: done
operator_actions:
  - 'Launch the game normally (no --windowed) and confirm it opens in borderless fullscreen with no title bar.'
  - 'Press F11 on the title screen, on Level Select, in a running level and with the Esc pause menu open, and confirm each press switches between borderless fullscreen and a centred window.'
  - 'In windowed mode, drag the window to a clearly non-16:9 shape (tall or wide) and confirm the playfield keeps its shape with black bars, the ship stays exactly under the cursor, and the cursor cannot leave the player zone while flying.'
  - 'Switch to windowed with F11, quit, relaunch, and confirm the game opens in fullscreen again (the choice is not saved).'
  - 'Optionally, export a release build and confirm F11 also works there.'
baseline_revision: '7d0a7e2423457daf6ed2358f581b331c5eca36dd'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-4-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/EXPERIENCE.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The game already launches in borderless fullscreen (`display/window/size/mode=3`) and letterboxes (`canvas_items`/`keep`), and the `toggle_fullscreen` action is bound to F11. But nothing handles F11, so a player can't switch to a window. This story covers FR59. Tier: MUST.

**Approach:** The `SceneRouter` autoload (`PROCESS_MODE_ALWAYS`, present under every scene) handles `toggle_fullscreen` in `_unhandled_input` and flips the window between `WINDOW_MODE_FULLSCREEN` (borderless) and `WINDOW_MODE_WINDOWED` through injectable callables. Nothing is persisted. A 1280×720 windowed size override keeps the window usable on a 1080p screen. The letterbox and the cursor confinement already exist, so they get pinning tests.

## Boundaries & Constraints

**Always:**
- **SceneRouter** gains:
  - `var get_window_mode: Callable` (returns `DisplayServer.WindowMode`) and `var set_window_mode: Callable` (takes one), defaulted in `_ready` only when invalid (like `change_scene`) to `DisplayServer.window_get_mode` / `DisplayServer.window_set_mode`. Add `default_get_window_mode()` / `default_set_window_mode()` helpers that tests use to restore them.
  - `static func toggled_window_mode(mode: DisplayServer.WindowMode) -> DisplayServer.WindowMode`: `FULLSCREEN` or `EXCLUSIVE_FULLSCREEN` → `WINDOWED`; every other mode (`WINDOWED`, `MAXIMIZED`, `MINIMIZED`) → `FULLSCREEN`.
  - `toggle_window_mode()`: reads the current mode, sets the toggled one and logs `Log.info("scene", "Window mode: fullscreen")` or `"Window mode: windowed"`.
  - `_unhandled_input(event)`: only on `event.is_action_pressed(&"toggle_fullscreen")` (an action, never a raw key; echoes ignored). It calls `toggle_window_mode()` and marks the event handled. It isn't gated on `OS.is_debug_build()` and works while the tree is paused (the router is already ALWAYS).
  - Update the header doc comment: the router also owns the F11 window toggle.
- **Not persisted:** no `user://` write, no `SaveManager` call and no `ProjectSettings.save`. A fresh launch is always fullscreen.
- **project.godot:** add `display/window/size/window_width_override=1280` and `window_height_override=720` (the windowed size). Leave `mode=3`, the viewport 1920×1080 and the stretch `canvas_items`/`keep` unchanged.
- Statically typed GDScript. Logging goes through `Log` (`scene` category) with no `print()`. Only `PauseArbiter` touches `mouse_mode`, and only the Player warps the cursor.
- Tests inject recorders and never change the real window. `after_each` restores the router's callables to the defaults.

**Never:** No settings menu, no persisted display choice, no new autoload, no new input action and no new Log category. Don't change `Player` cursor code, `PauseArbiter`, `DebugTools` or any menu scene. No exclusive fullscreen.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| To windowed | mode FULLSCREEN, F11 | `set_window_mode` called once with WINDOWED, one `[INFO][scene] Window mode: windowed` line, event handled | none |
| To fullscreen | mode WINDOWED, F11 | set once with FULLSCREEN, `Window mode: fullscreen` | none |
| Exclusive | mode EXCLUSIVE_FULLSCREEN | toggles to WINDOWED | none |
| Maximized / minimized | mode MAXIMIZED or MINIMIZED | toggles to FULLSCREEN | none |
| Paused | `PauseArbiter` has `menu`, F11 | still toggles once | none |
| Echo | F11 held (echo `InputEventKey`) | no call, not handled | none |
| Other key | Esc or F1 through the router | no call | none |
| Not persisted | any toggle, with a test save path | no save file written | none |
| Letterbox bar | Player in CONFINED_HIDDEN, viewport mouse (-150, 1200) (pillarbox left, below the field) | ship at (0, 1080), one warp to (0, 1080) in viewport coordinates | none |

</intent-contract>

## Code Map

- `game/autoloads/scene_router.gd` -- `change_scene` Callable seam + `default_change_scene()` (lines 34-46) is the pattern for the two new window-mode callables. `_ready` already sets `PROCESS_MODE_ALWAYS`. Add the toggle here.
- `game/project.godot:38-44` -- `[display]`: `mode=3` (borderless fullscreen), 1920×1080, `canvas_items`/`keep`. Add the two `window_*_override` keys. Line ~92: `toggle_fullscreen` is already bound to physical F11.
- `game/tests/unit/test_project_settings.gd:51-67` -- the `SETTINGS` table already pins mode 3, the viewport size and the stretch. Add the two override keys.
- `game/entities/player/player.gd:64-71,119-120,412-420` -- `WARP_EPS_PX`, the injectable `warp_mouse` (defaults to `get_viewport().warp_mouse`, which takes viewport coordinates and applies the stretch transform), `step_lock(get_viewport().get_mouse_position())` with `confine`. Read-only: a mouse in a letterbox bar arrives as a viewport coordinate outside 0..1920 / 432..1080 and is clamped and warped back.
- `game/tests/unit/test_player_movement.gd:40-115` -- the fixture and the confine/warp tests to extend with the letterbox-bar case.
- `game/tests/unit/test_pause_menu.gd` / `test_level.gd::test_real_esc_key_toggles_the_menu` -- how to drive an action (`InputEventAction`) and a real key through `get_viewport().push_input` and check `is_input_handled()`. Also the `Log.sink` capture pattern.
- `game/tests/unit/test_scene_router.gd` -- the existing router fixture: change-scene recorder, test save path, `after_each` resets.
- `game/autoloads/log.gd:12-15` -- categories; use `scene`.
- `_bmad-output/game-architecture.md:543` -- the F11 row (Planned → Built, Story 4.5, owned by `SceneRouter`). Line 565: the "As of Story 4.4" built-parts summary → 4.5. Add "As-built 2026-10-08 (Story 4.5)" after the Story 4.4 section (line ~1644, before the footer).

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_window_mode.gd` (new, write it first) -- every I/O matrix row except the letterbox one: `toggled_window_mode` for all five modes; `toggle_window_mode()` with recorders (the call, the log line via `Log.sink`); a real F11 `InputEventKey` (`physical_keycode = KEY_F11`, pressed) through `get_viewport().push_input` toggles once and `is_input_handled()` is true; the same while `PauseArbiter.push(&"menu")` is active; echo and Esc don't toggle; no save file at the test save path; `SceneRouter.process_mode` is ALWAYS; the defaults are valid Callables after restore.
- `game/autoloads/scene_router.gd` -- the toggle as specified -- FR59, F11 in every scene.
- `game/project.godot` -- the windowed size override -- a usable window on a 1080p display.
- `game/tests/unit/test_project_settings.gd` -- pin the two overrides.
- `game/tests/unit/test_player_movement.gd` -- the letterbox-bar row: a mouse at (-150, 1200) with CONFINED_HIDDEN puts the ship at (0, 1080) and warps once there; also (2100, 300) → (1920, 432).
- `game/tests/unit/test_window_mode.gd` -- a letterbox test: set `get_tree().root.size` to a non-16:9 size (2560×1600) and assert `get_tree().root.get_visible_rect().size` stays 1920×1080 and the final transform scales x and y equally. Restore the size afterwards. If headless can't resize the root window, leave the test out and say so in the result; the settings pin still covers the stretch.
- `_bmad-output/game-architecture.md` -- the F11 row, the built-parts summary and the As-built section.

**Acceptance Criteria:**
- Given a fresh launch, when the game opens, then the window mode setting is borderless fullscreen (`mode` 3, not exclusive) with no saved override.
- Given any scene (boot, title, level select, level, sandbox), debug or release, when F11 is pressed, then the window toggles between borderless fullscreen and windowed and nothing is persisted.
- Given a window that isn't 16:9, when the game renders, then the 1920×1080 playfield scales uniformly with letterbox bars, the ship sits on the cursor, and the cursor is confined to the player zone through viewport-coordinate warps.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 14 findings — high 0, medium 0, low 6, false 8, maybe-false 0
- findings:
  - `[false]` `[reject]` (blind) the 1280×720 override may not apply on the first switch from a fullscreen launch (a screen-sized rect at (0,0)) -- a real probe on the 1080p display (a scratch `-s` script outside the repo, a real F11 through `Input.parse_input_event`) went from mode 3 to a centred 1264×681 window at screen offset (328, 187), then back to mode 3 on the second F11.
  - `[low]` `[reject]` (blind) fullscreen then F11 loses a maximized state -- the spec's matrix sends MAXIMIZED to FULLSCREEN by design. Restoring it needs remembered state and a new branch, and a player rarely maximizes and then uses F11.
  - `[false]` `[reject]` (blind) "no design decision changed" is wrong because of the 1280×720 size -- the GDD and UX give no windowed size. The as-built note and Design Notes call it a layout default, as Story 4.4 did for its padding.
  - `[false]` `[reject]` (blind) the architecture contradicts itself by listing F11 among the debug tools -- the F11 row was already in that table, and the edited line and row both say it is owned by `SceneRouter` and works in release.
  - `[low]` `[reject]` (blind) no test sends F11 inside the real scenes -- no scene node handles `toggle_fullscreen`. The menu buttons are `FOCUS_NONE`, and a focused Button only takes `ui_accept`/focus actions, so F11 reaches the router. The guard is against a hypothetical future handler.
  - `[false]` `[reject]` (blind) the design note gets input order backwards -- it says autoloads come first in the tree, so a scene node gets F11 first. That is Godot's reverse-order `_unhandled_input`, and the note is correct.
  - `[low]` `[reject]` (blind) the not-persisted test doesn't look for `override.cfg` or `ProjectSettings.save` -- the diff has no write call of any kind. A file-system scan adds test complexity for a path that doesn't exist.
  - `[low]` `[patch]` (blind) the letterbox test checks the scale but not the bar offset -- `xform.origin` is now asserted equal to (0, 80). Restoring the size inline already happens before the asserts, which don't abort.
  - `[low]` `[reject]` (blind) the player letterbox test uses the same path as the existing outside-zone test -- intended: a mouse in a bar *is* an outside viewport coordinate. The stretch mapping is covered by the root-transform test and the real probe (1000×1000 window: 219 px bars, uniform scale within rounding).
  - `[false]` `[reject]` (blind) a mode change can release the cursor clip or snap the ship -- the ship is meant to sit on the cursor. While `CONFINED_HIDDEN`, `Player.step_lock` warps any out-of-zone cursor back every physics tick, so the cursor stays in the zone either way.
  - `[false]` `[reject]` (blind) `toggle_window_mode` assumes valid callables and logs the requested mode -- `_ready` always defaults both callables, and every test restores them. `window_set_mode` returns nothing to check, and the real probe showed the requested mode applied.
  - `[false]` `[reject]` (blind) the spec is in-review with empty logs and stale line anchors -- that is a mid-pipeline snapshot. Finalize fills it in, and the Code Map anchors are pre-change investigation pointers.
  - `[false]` `[reject]` (edge) a missing invalid-callable guard in `toggle_window_mode` -- same as the blind callable row: the state is unreachable because `_ready` sets the defaults and tests restore them.
  - `[low]` `[reject]` (intent) the acceptance criteria live at the real window, while the tests use recorders and a headless root -- addressed at finalize: a real-display probe drove F11 both ways and letterboxed a square window, and the in-scene play-checks are listed as `operator_actions` with `status: awaiting-operator`.

## Design Notes

F11 needs a handler in every scene, including while paused. `SceneRouter` is the existing `PROCESS_MODE_ALWAYS` autoload that is present under every scene, so it owns the toggle instead of a new autoload (the autoload order is fixed by the architecture). Autoloads come first in the tree, so a scene node that handles an F11 event would get it first. None does.

The 1280×720 windowed size isn't in the GDD or UX spec. It is a layout default (like the pause menu padding): a 1920×1080 window wouldn't fit a 1080p screen with its title bar. Fullscreen ignores it.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --path game --windowed --resolution 1280x1024 --quit-after 180` -- expected: `Title ready` in the log, no errors (a non-16:9 window).

**Manual checks:**
- A person presses F11 on the title, in a level and in the pause menu, resizes the window to a non-16:9 shape, and confirms the bars, the ship on the cursor and the cursor confined to the window.

## Auto Run Result

Status: awaiting-operator

**Summary:** F11 now switches between borderless fullscreen and windowed in every scene, paused or not, in debug and release. `SceneRouter` (the `PROCESS_MODE_ALWAYS` autoload present under every scene) handles the `toggle_fullscreen` action in `_unhandled_input` and flips any fullscreen mode to windowed and any other mode to borderless fullscreen. It goes through injectable `get_window_mode`/`set_window_mode` callables and logs `[INFO][scene] Window mode: …`. Nothing is saved, so a fresh launch is always borderless fullscreen (`mode=3`, unchanged). A 1280×720 windowed size override keeps the window usable on a 1080p screen. Letterboxing and cursor confinement were already in place and are now pinned by tests.

**Files changed:**
- `game/autoloads/scene_router.gd` -- the F11 handler, `toggled_window_mode`, `toggle_window_mode`, the injectable callables and their defaults.
- `game/project.godot` -- `window_width_override=1280`, `window_height_override=720`.
- `game/tests/unit/test_window_mode.gd` (+ `.uid`) -- new: 16 tests (toggle table, recorders, real F11 key, paused, echo, other keys, not persisted, defaults, headless 2560×1600 letterbox with scale and the 80 px bar).
- `game/tests/unit/test_project_settings.gd` -- pins the two overrides.
- `game/tests/unit/test_player_movement.gd` -- a mouse in a letterbox bar is clamped and warped back in viewport coordinates.
- `_bmad-output/game-architecture.md` -- the F11 row marked Built, the built-parts summary and "As-built 2026-10-08 (Story 4.5)".

**Review findings:** 14 total (high 0, medium 0, low 6, false 8).
- **Patched (1, low):** the letterbox test now asserts the bar offset (0, 80).
- **Deferred:** none.
- **Rejected:** 8 false and 5 low, each with its reason in the Review Triage Log. The false ones are the first-switch window rect (disproved by a real probe), the design-decision wording, the architecture debug-table wording, the input-order note, the cursor clip, the invalid callables (two rows) and the mid-pipeline spec state. The low ones are the lost maximized state, F11 not tested inside real scenes, the persistence scan, the player test using the generic path, and the stand-in test surfaces (handed to the operator).

**Follow-up review recommended:** false. One low entry was patched (high 0, medium 0, low 1).

**Verification:**
- Headless `--import` -- exit 0.
- Full GUT suite -- 1040/1040 passing, before and after the patch.
- Windowed non-16:9 cold launch (`--windowed --resolution 1280x1024 --quit-after 180`) -- `Title ready 1677 ms after launch`, no errors.
- Real-display probe (a scratch `-s` script outside the repo; real F11 events through `Input.parse_input_event`):
  - launch: mode 3 at 1920×1080
  - first F11: windowed, 1264×681 and centred, with a 27 px pillarbox
  - square window, resized in code to 1000×1000: 219 px bars at the top and bottom, with a uniform scale (within integer rounding)
  - second F11: mode 3 again
- I/O matrix audit -- every row has a test that ran and passed.

**Operator actions owed:** see `operator_actions` in the frontmatter. A person confirms F11 inside each real scene (title, Level Select, level, pause menu), checks that the ship stays on the cursor and the cursor stays confined in a non-16:9 window during play, and confirms that a relaunch is fullscreen again.

**Residual risks:**
- No person has watched the toggle inside the title, Level Select or a running level, or felt the cursor confinement after a window-mode change. The probe ran with `-s` (autoloads only, no main scene).
- On this display the windowed size came out as 1264×681, not exactly 1280×720 (Windows adjusts it for borders and DPI). It is centred and letterboxes correctly.
- The release export was not exercised. The handler has no debug gate.

## Operator Confirmation

Confirmed 2026-10-08: the external actions this story owed were carried out.

- Launch the game normally (no --windowed) and confirm it opens in borderless fullscreen with no title bar.
- Press F11 on the title screen, on Level Select, in a running level and with the Esc pause menu open, and confirm each press switches between borderless fullscreen and a centred window.
- In windowed mode, drag the window to a clearly non-16:9 shape (tall or wide) and confirm the playfield keeps its shape with black bars, the ship stays exactly under the cursor, and the cursor cannot leave the player zone while flying.
- Switch to windowed with F11, quit, relaunch, and confirm the game opens in fullscreen again (the choice is not saved).
- Optionally, export a release build and confirm F11 also works there.

_Appended by the bmad-loop orchestrator (`bmad-loop confirm`, #335): a human confirmed these external actions out of band, and the story was advanced from `awaiting-operator` to `done`._
