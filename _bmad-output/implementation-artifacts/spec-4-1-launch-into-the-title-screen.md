---
title: 'Story 4.1: Launch into the Title Screen'
type: 'feature'
created: '2026-10-08'
baseline_revision: 'c5dfc83738283b9cf2c210390918da98396c5507'
status: done
operator_actions:
  - 'Launch the game from the CLI (or the editor) and confirm the title screen looks right: the DEFECTOR logo centred near the top with a cyan glow, and PLAY above QUIT, centred, with a cyan border on hover.'
  - 'Click PLAY and confirm Level 1 ("Cargo Ambush") starts with Wasp waves; then return to the title through the death screen QUIT TO TITLE and click QUIT to confirm the game closes.'
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

**Problem:** The game still boots straight into `level.tscn` running `level_dev.json`. There is no title screen, `SceneRouter.goto_title()` is a placeholder that reloads the main scene, and there is no `start_level(id)` and no real level data. This story covers FR56 (Play, Quit), NFR2 and the fatal-config handling. Tier: MUST.

**Approach:** Add `scenes/boot/boot.tscn` as the main scene. It checks `Config`, logs the result and calls `SceneRouter.goto_title()`. Add `scenes/title/title.tscn` with the DEFECTOR logo and PLAY · QUIT, or an error label when `Config.load_error` is set. Give `SceneRouter` a real `goto_title()` and a new `start_level(id)`. Add placeholder `level_1/2/3.json`.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript. Logging goes through `Log` (`boot`, `scene`). Only `SceneRouter` changes scenes. The one exception is boot's debug-only `--stress`/`--bench` redirect to the sandbox, which mirrors `level.gd` (`DebugArgs.parse(user_args)`, `OS.is_debug_build()`, a deferred injectable `change_scene`, with `user_args` defaulting to `OS.get_cmdline_user_args()`). The bench CLI must keep working now that boot is the main scene.
- **SceneRouter:**
  - `TITLE_SCENE_PATH = "res://scenes/title/title.tscn"`.
  - `goto_title()`: `energy = 0`, `is_retry = false`, `current_level_id = ""`, then `_change_to(TITLE_SCENE_PATH, …)`. Story 4.2 swaps the energy reset for the save restore.
  - `start_level(id: String)`: sets `GameState.current_level_id = id` and `is_retry = false`, leaves energy untouched, then `_change_to(LEVEL_SCENE_PATH, …)`. When `Config.load_error` is non-empty it logs `Log.error("scene", …)` and changes nothing.
  - Remove `MAIN_SCENE_SETTING` and update the doc comments. `_change_to` keeps calling `PauseArbiter.clear()` first.
- **Boot (`scenes/boot/boot.gd` + `.tscn`, a plain `Node`):** `_ready` sets the gameplay mouse mode to `VISIBLE`. Then it either does the stress redirect, or logs `Log.info("boot", "Config loaded …")` (or `Log.error("boot", "Config failed to load: <load_error>")`) and calls `SceneRouter.goto_title()` either way. `project.godot` `run/main_scene` becomes `res://scenes/boot/boot.tscn`.
- **Title (`scenes/title/title.gd` + `.tscn`, a full-rect `Control` with the shared theme):**
  - `_ready` calls `PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)`, then logs `Log.info("scene", "Title ready %d ms after launch" % Time.get_ticks_msec())`. This is the NFR2 evidence.
  - Nodes: `Logo` Label ("DEFECTOR"), `Buttons` VBoxContainer holding `Play` ("PLAY") and `Quit` ("QUIT"), and an `Error` Label (hidden by default).
  - Healthy config: the layout comes from the new `ui.title` keys (`logo_y` 300 is the logo's centre, `logo_px` 120, `button_w` 400, `button_h` 72, `button_gap_px` 24, `buttons_top_y` 560). The button stack is centred horizontally.
  - `Config.load_error` non-empty: the `Buttons` are hidden and both buttons disabled. `Error` is shown in the place of the buttons with the text `"CONFIG ERROR\n" + Config.load_error`. In this branch the title **never calls `Config` getters** (the data is empty, and a getter would assert), so it uses the positions authored in the `.tscn`, which match the UX numbers above.
  - PLAY → `SceneRouter.start_level(FIRST_LEVEL_ID)` with `FIRST_LEVEL_ID = "1"`. Story 4.2 switches this to the highest unlocked level. QUIT → `quit_game.call()`, an injectable `Callable` that defaults to `get_tree().quit` and is logged under `scene`. A `_leaving` flag ignores a second press.
- **Theme:** add `Title/…` items to `defector_theme.tres`: `colors/logo` coalition `#22E6FF`, `colors/logo_glow` coalition at about 0.5 alpha (the font shadow, with a `constants/logo_glow_px` shadow outline), `colors/error` danger `#FF1F4B`, `colors/text` `#E8F4FF`, `font_sizes/button` 28, `font_sizes/error` 28, and `styles/button_normal|hover|focus` that reuse the existing `StyleBoxFlat_retry_button*` sub-resources. The title copies them onto its children in code, like `RetryPrompt._apply_theme`. The UI is mouse-only, so no button grabs focus. No text under 20 px, and all text is UPPERCASE except the error detail.
- **Levels:** `data/levels/level_1.json`, `level_2.json` and `level_3.json` copy the `level_dev.json` key set (`id` 1/2/3, `name` "Cargo Ambush" / "The Blockade" / "Siege of the Throne World", nulls, `convoy` false). Each has 1–2 short waves of `wasp` only, with grid formations that fit the zone tests (for example `grid_3x2` / `grid_4x2`) and `wave_start` or `wave_clear` wait triggers. They are replaced in Epic 7 (decision F12).
- `level.gd` keeps its exported `"dev"` fallback and its own stress redirect, so running `level.tscn` directly still works.

**Never:**
- No LEVEL SELECT button or screen (Story 4.3), no SaveManager and no `highest_unlocked_level` (Story 4.2), no pause menu (4.4), no F11/F7 (4.5/4.3), no backdrop art. Don't change existing tuning values or level_dev.json. Don't use `print()`. Don't read raw keys.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Boot OK | `load_error` "" | INFO boot line; one change to the title path; mouse mode VISIBLE | none |
| Boot bad config | `load_error` "x parse error…" | ERROR boot line naming it; still goes to the title | logged |
| Boot stress | debug build, `--stress` or `--bench=5` | deferred change to the sandbox; no goto_title | none |
| Title OK | healthy config | Logo and PLAY/QUIT at the `ui.title` layout; Error hidden | none |
| Title bad config | `load_error` set, `tuning` {} | Error shows the message; buttons hidden and disabled; no `[ERROR][data]` line | none |
| PLAY | click | `current_level_id` "1", `is_retry` false, energy unchanged, change to level.tscn | second press ignored |
| start_level with bad config | `load_error` set | no scene change, GameState untouched | `Log.error("scene")` |

</intent-contract>

## Code Map

- `game/autoloads/scene_router.gd` -- `restart_level()`, the placeholder `goto_title()` (`MAIN_SCENE_SETTING`) and `_change_to(path, msg)`, which does `PauseArbiter.clear()`, `Feedback.reset()`, `Log.info("scene")` and `change_scene.call`. Add `start_level` here and rewrite `goto_title`.
- `game/project.godot:15` -- `run/main_scene` is set to the level today.
- `game/scenes/level/level.gd:21-44,72-74` -- the pattern to mirror: the `user_args` / `change_scene` seams, `DebugArgs.parse`, the static `should_redirect_to_stress`, and `change_scene.call_deferred(SANDBOX_SCENE_PATH)`.
- `game/ui/menus/retry_prompt.gd/.tscn` -- the menu pattern to copy: the THEME_TYPE consts, layout from `Config` `ui.*`, `_apply_theme()` overrides and the `_leaving` guard.
- `game/ui/theme/defector_theme.tres` -- `RetryPrompt/*` items and the `StyleBoxFlat_retry_button*` sub-resources to reuse.
- `game/autoloads/config.gd` -- `load_error` (empty means OK), `assert_on_missing`, and `_report_missing`, which asserts when data is missing.
- `game/autoloads/pause_arbiter.gd` -- `set_gameplay_mouse_mode`, `current_mouse_mode()`.
- `game/data/tuning.json:271-273` -- the `ui` section. Add `title` next to `retry_prompt`.
- `game/data/levels/level_dev.json` -- the key set and wave shape to copy (wasp-only).
- `game/systems/waves/level_validator.gd` -- the rules the new level files must pass.
- `game/tests/data/test_data_files.gd:21-22` -- `test_level_files_exist`. Extend it for levels 1–3 and their names. The zone test already walks every level file.
- `game/tests/unit/test_scene_router.gd:100-113` -- the goto_title test asserts the main scene. It must assert `TITLE_SCENE_PATH` instead.
- `game/tests/unit/test_retry_prompt.gd:259` -- QUIT asserts the `main_scene` path. Change it to `SceneRouter.TITLE_SCENE_PATH`.
- `game/tests/unit/test_project_settings.gd:71` -- the expected `main_scene` becomes `res://scenes/boot/boot.tscn`.
- `game/tests/unit/test_level.gd:660-680` -- a level-with-args fixture to copy for the boot tests.
- `_bmad-output/game-architecture.md:132,262,663,1454` -- placeholder or "main scene is the level" notes. Add an as-built section at the end, before the closing `---`.

## Tasks & Acceptance

**Execution:**
- `game/autoloads/scene_router.gd` -- add `TITLE_SCENE_PATH` and `start_level`, rewrite `goto_title`, update the docs -- the real router API.
- `game/scenes/boot/boot.gd`, `boot.tscn` -- the boot node as specified -- main scene.
- `game/project.godot` -- `run/main_scene` becomes the boot scene.
- `game/scenes/title/title.gd`, `title.tscn` -- the title as specified -- FR56 Play/Quit and fatal error UI.
- `game/ui/theme/defector_theme.tres` -- `Title/*` items.
- `game/data/tuning.json` -- `ui.title` layout keys.
- `game/data/levels/level_1.json`, `level_2.json`, `level_3.json` -- placeholder levels.
- `game/tests/unit/test_scene_router.gd` -- goto_title goes to `TITLE_SCENE_PATH`, with GameState reset and pauses cleared. Add: start_level sets the id, clears is_retry, keeps the energy, clears the pause reasons and changes to the level path; start_level with `load_error` set changes nothing and logs an ERROR; `TITLE_SCENE_PATH` exists.
- `game/tests/unit/test_boot.gd` (new) -- the Boot OK, bad-config and stress rows (inject `user_args` and a `change_scene` recorder; the stress test only asserts in debug builds), plus the main-scene setting.
- `game/tests/unit/test_title.gd` (new) -- the healthy layout (logo centre y, button rects 400×72 with a 24 gap from 560, centred), button texts, Error hidden and mouse mode VISIBLE; the bad-config row (save and restore `Config.load_error` / `tuning`, set `assert_on_missing` false, capture `Log.sink`); PLAY records the level path with the GameState values; a second PLAY is ignored; QUIT calls the injected `quit_game` once; the "Title ready" INFO line is present.
- `game/tests/data/test_data_files.gd` -- assert that level_1..3 exist with the GDD names and ids 1..3.
- `game/tests/unit/test_retry_prompt.gd`, `test_project_settings.gd` -- update the expectations.
- `_bmad-output/game-architecture.md` -- update rows 132 and 663, the Scene Structure "Built" note and the stress-redirect note, and add "As-built 2026-10-08 (Story 4.1)".

**Acceptance Criteria:**
- Given `boot.tscn` is the main scene, when the game starts, then it confirms `Config` loaded (it logs either way) and calls `SceneRouter.goto_title()`, and the title appears with PLAY and QUIT.
- Given `tuning.json` failed to parse, when the title opens, then a plain error label shows the `Config.load_error` message and no button or router call can start a level.
- Given the placeholder level files, when `test_data_files.gd` runs, then levels 1–3 exist with their names and 1–2 Wasp waves and pass validation.
- Given the title, when I click PLAY, then `start_level("1")` loads `level.tscn` with `current_level_id` "1" and `is_retry` false. When I click QUIT, then the application quits.
- Given any router scene change, when it happens, then `PauseArbiter.clear()` runs first, and the boot and title scenes set the gameplay mouse mode to VISIBLE.
- Given a cold launch from the CLI on this machine, when the title logs its ready time, then it is under 5000 ms. A human also confirms that the title looks right on screen; this is owed as an operator action.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 22 findings — high 0, medium 0, low 17, false 5, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) a failed `change_scene` leaves the title stuck, because `_leaving` is set and the `Error` is ignored -- this only happens if `level.tscn` or `title.tscn` is missing, and tests assert both exist; the fix would add return-value plumbing to the router.
  - `[low]` `[reject]` (blind) `start_level` doesn't check that the level file exists -- the only caller passes "1", and `test_data_files` proves `Config.level("1")` loads; `level.gd` already logs an unknown id; the guard would add a second file read and validation pass per start.
  - `[low]` `[reject]` (blind) no test runs `level.tscn` with id "1" -- the pieces are covered: `test_level.test_resolve_level_id_prefers_the_game_state_id`, the router test for id and path, and `test_data_files` loading `level_1` through `Config.level`.
  - `[low]` `[patch]` (blind) a real line break inside the `CONFIG ERROR` code span in the architecture as-built -- rewritten as `CONFIG ERROR\n<load_error>` on one line.
  - `[low]` `[patch]` (blind) the as-built records a one-machine timing ("2455 ms on the dev laptop") -- deleted; the rule and log line stay.
  - `[low]` `[reject]` (blind) `_layout` clamps only some `ui.title` values and has no data range test -- this is the same pattern as `RetryPrompt`, mistuned layout data shows up at once on screen, and the fix adds guards.
  - `[low]` `[patch]` (blind) the dead `_error.position.y = top_y` and its misleading comment in the healthy branch -- deleted; the error label keeps its authored y 560.
  - `[low]` `[reject]` (blind) the tests check the theme `.tres` values, not the node overrides from `_apply_theme` -- a dropped override is visible at once and is covered by the operator's visual check; the fix only adds assertions for cosmetics.
  - `[low]` `[reject]` (blind) `test_start_level_with_a_config_error_changes_nothing` restores `Config.load_error` inline -- a leak only happens once that test is already failing; `test_config` uses the same pattern.
  - `[low]` `[reject]` (blind) the placeholder levels don't ramp in difficulty -- they are throwaway placeholders that Epic 7 replaces (decision F12); the spec asks only for 1–2 short Wasp waves.
  - `[low]` `[reject]` (edge) the `change_scene` error leaves `_leaving` stuck -- same root cause as the first blind row; rejected for the same reason.
  - `[low]` `[reject]` (edge) unknown or empty id in `start_level` -- same as the blind `start_level` row.
  - `[low]` `[reject]` (edge) a zero or negative `button_w`/`button_h`/`logo_y`/`buttons_top_y` -- same as the blind clamp row.
  - `[false]` `[reject]` (edge) a non-Control child of `Buttons` would crash `_layout` -- `title.tscn` authors only the two Buttons, so the state is unreachable; it would fail loudly if someone added one.
  - `[false]` `[reject]` (edge) re-entering the title logs session uptime and pollutes the NFR2 evidence -- the line says "N ms after launch", which is literally true on every entry; the cold-launch reading uses the first line of a fresh run.
  - `[low]` `[patch]` (verification-gap) the title layout isn't proven to follow `ui.title`, because the authored values equal the defaults -- added `test_layout_follows_ui_title_tuning` with non-default values (logo centre 400 at 100 px; PLAY (810, 600, 300, 60); QUIT (810, 670, 300, 60)).
  - `[false]` `[reject]` (intent) no commit and no `awaiting-operator` / `operator_actions` yet -- a mid-pipeline snapshot; finalize commits and sets both.
  - `[false]` `[reject]` (intent) the NFR2 test doesn't assert < 5000 ms -- GUT can't measure a cold launch; Verification ran a real windowed cold launch (2953 ms, then 2023 ms after the patches).
  - `[false]` `[reject]` (intent) nothing chains boot into the rendered title -- a real scene change would replace the GUT runner, so the recorder is by design; the real windowed run showed boot → title, and the visual check is an operator action.
  - `[low]` `[reject]` (intent) the default `quit_game` (`get_tree().quit`) is never exercised -- calling it would end the test runner; the wiring is one line in `_ready`, and the QUIT click is an operator action.
  - `[low]` `[reject]` (intent) PLAY isn't run through to `level.tscn` loading `level_1.json` -- same as the blind level-1 row; the click-through is also an operator action.
  - `[low]` `[reject]` (intent) the config-error path is faked by setting `load_error`, not by a real malformed `tuning.json` -- `test_config` covers the real parse failure setting `load_error` with the `bad_tuning.json` fixture; boot and title only read that field.

## Design Notes

The title must work with no config data at all, so its error branch reads nothing from `Config`. That is why the `.tscn` carries the UX positions as authored defaults, and `ui.title` overrides them only when the data loaded. The boot scene takes over the `--stress` redirect because the CLI bench launches the main scene. Without the redirect, `-- --bench=20` would land on the title and never exit.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0 (new `class_name`s and scenes).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all pass.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --path game --windowed --quit-after 180` -- expected: the log shows the INFO boot line, then `Title ready N ms after launch` with N < 5000.

## Auto Run Result

Status: awaiting-operator

**Summary:** The game now boots into `scenes/boot/boot.tscn` (the new main scene). It logs whether `Config` loaded and calls `SceneRouter.goto_title()`. The new title screen (`scenes/title/`) shows the DEFECTOR logo and PLAY · QUIT, laid out from `ui.title`. If `tuning.json` failed to parse, a `danger` error label with the `Config.load_error` message replaces the buttons and nothing can start a level. `SceneRouter` gained a real `goto_title()` and `start_level(id)`; `start_level` refuses while the config error is set. PLAY starts level "1" and QUIT quits. Placeholder `level_1/2/3.json` files exist. In debug builds, boot redirects `--stress`/`--bench` to the sandbox, so the CLI bench still works.

**Files changed:**
- `game/autoloads/scene_router.gd` -- `TITLE_SCENE_PATH`, a real `goto_title()`, the new `start_level(id)` with the config-error refusal; `MAIN_SCENE_SETTING` removed.
- `game/scenes/boot/boot.gd`, `boot.tscn` -- new main scene: VISIBLE mouse mode, a Config INFO/ERROR line, a deferred `goto_title`, and the debug stress/bench redirect.
- `game/scenes/title/title.gd`, `title.tscn` -- new `TitleScreen`: logo, PLAY/QUIT, the config-error label, the injectable `quit_game`, a `_leaving` guard, and the "Title ready N ms after launch" line.
- `game/project.godot` -- `run/main_scene` is the boot scene.
- `game/ui/theme/defector_theme.tres` -- `Title/*` items (reusing the retry button styles).
- `game/data/tuning.json` -- `ui.title` layout keys.
- `game/data/levels/level_1.json`, `level_2.json`, `level_3.json` -- placeholder Wasp-only levels with the GDD names.
- `game/scenes/level/level.gd` -- doc comment only.
- `game/tests/unit/test_boot.gd`, `test_title.gd` -- new tests.
- `game/tests/unit/test_scene_router.gd`, `test_retry_prompt.gd`, `test_project_settings.gd`, `game/tests/data/test_data_files.gd` -- updated expectations and new cases.
- `_bmad-output/game-architecture.md` -- updated the status rows and notes, and added "As-built 2026-10-08 (Story 4.1)".

**Review findings:** 22 total, none deferred.
- **Patched (4, all low):** the architecture code-span line break, removing the machine-specific timing, deleting the dead error-label line in `title.gd`, and the new `test_layout_follows_ui_title_tuning`.
- **Rejected (18):** 5 false and 13 low. The lows were states that can't be reached today, or fixes that would add guards for cosmetic gains. The Review Triage Log gives the reason for each.

**Follow-up review recommended:** false. The patched counts are high 0, medium 0, low 4.

**Verification:**
- Headless `--import` -- exit 0.
- Full GUT suite -- 940/940 passing, exit 0, after the patches.
- Real windowed cold launch (`--windowed --quit-after 180`) -- `[INFO][boot] Config loaded …`, then `Going to the title screen`, then `Title ready 2023 ms after launch` (2953 ms before the patches). Both are under 5000 ms.
- `-- --bench=1` (implementation run) -- boot redirected to the sandbox and the bench printed PASS.

**Residual risks:**
- The look of the title (logo glow, button hover) and the real PLAY → Level 1 and QUIT click-through haven't been checked by a person; both are owed as operator actions.
- The title has no LEVEL SELECT yet (Story 4.3), and PLAY always starts Level 1 until Story 4.2 adds the save.

**Operator actions owed:**
- Launch the game and confirm the title screen looks right (logo, glow, button layout and hover).
- Click PLAY → Level 1 starts; return through QUIT TO TITLE on the death screen; click QUIT → the game closes.

## Operator Confirmation

Confirmed 2026-10-08: the external actions this story owed were carried out.

- Launch the game from the CLI (or the editor) and confirm the title screen looks right: the DEFECTOR logo centred near the top with a cyan glow, and PLAY above QUIT, centred, with a cyan border on hover.
- Click PLAY and confirm Level 1 ("Cargo Ambush") starts with Wasp waves; then return to the title through the death screen QUIT TO TITLE and click QUIT to confirm the game closes.

_Appended by the bmad-loop orchestrator (`bmad-loop confirm`, #335): a human confirmed these external actions out of band, and the story was advanced from `awaiting-operator` to `done`._
