# Epic 4 Context: Game Flow, Progression and Save

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Turn the playable level prototype into a game you can launch and come back to. The player boots into a title screen, continues at the highest unlocked level, picks any unlocked level from Level Select, pauses at any time with Esc (resume, restart or quit), and keeps their unlocks and energy between sessions. The game runs in borderless fullscreen or windowed mode with a letterboxed 16:9 playfield. The epic opens by replacing the placeholder glowing-circle player with a real recoloured fighter sprite. Tier: MUST, except the player ship sprite (Story 4.0), which is SHOULD.

## Stories

- Story 4.0: Fly a Real Ship
- Story 4.1: Launch into the Title Screen
- Story 4.2: Unlock the Next Level and Save Progress
- Story 4.3: Choose a Level from Level Select
- Story 4.4: Pause the Game with Esc
- Story 4.5: Play Fullscreen or Windowed

## Requirements & Constraints

- **Title:** PLAY (continue at the highest unlocked level), LEVEL SELECT (locked levels greyed out and not clickable), QUIT. If `tuning.json` failed to parse, a plain error label replaces the buttons and no level can start.
- **Progression:** clearing level N unlocks N+1 (`highest_unlocked_level = max(current, N+1)`) and starts N+1 carrying the current energy. Clearing Level 3 returns to the title until Epic 7 adds the end screen.
- **Energy rules:** energy carries into the next level and is saved on level clear. It resets to 0 on death, retry or restart (reset *before* the reload). PLAY and Level Select start with the saved energy. Returning to the title restores `energy` and `highest_unlocked_level` from the save, so in-memory mid-level energy never leaks across menus. "Die, Quit to Title, Play" therefore gets back the last saved energy, while Retry gives 0. This quirk is accepted.
- **Save only on level clear**, nowhere else. Quit to Title saves nothing. Debug F7 unlocks all levels in memory only and never writes the save.
- **Pause menu (Esc):** RESUME · RESTART LEVEL · QUIT TO TITLE. Esc again equals Resume. Esc does nothing while the `death` or `final_choice` reason is active. It is allowed during a `story` pause, and closing the menu returns to the story pause.
- **Display:** borderless fullscreen by default. F11 toggles windowed/fullscreen in any scene, in debug and release, and the choice is not persisted. Non-16:9 windows letterbox uniformly, the ship stays exactly on the cursor, and the cursor stays confined to the player zone.
- **Performance:** cold launch to the title screen in under 5 s.
- **Player ship (4.0):** a Kenney Space Shooter Redux (CC0) fighter hull, facing up and recoloured `coalition` #22E6FF (baked into the PNG, or tinted at 1.0 or below so it doesn't bloom under glow). It is scaled uniformly from `player.sprite_px` (96), with the longer side equal to the setting. The 24 px hurtbox, the nose muzzle, i-frame flicker, the hidden-on-death behaviour, the shield bubble and the missile ring must all still work. Credit it in `game/assets/CREDITS.md`. Commit the `.import` sidecar and run headless `--import` before the tests.
- **Data-driven:** level names come from the level JSON files, and no GDD number is hard-coded.

## Technical Decisions

- **Autoload order:** `Log`, `Events`, `Config`, `GameState`, `SaveManager`, `PauseArbiter`, `Audio`, `Feedback`, `EntityRegistry`, `SceneRouter`. Epic 4 creates `SaveManager`.
- **SceneRouter** is the only code that changes scenes: `goto_title()`, `start_level(id)`, `restart_level()` (later epics add `goto_story`/`goto_end`). It calls `PauseArbiter.clear()` before every change. `start_level` sets `GameState.current_level_id` and clears `is_retry`. Retry and restart reload the generic `level.tscn` with the same level id, with no reset code on entities. The router already uses an injectable `change_scene` callable for tests. The `PROCESS_MODE` is ALWAYS.
- **Scenes:** `scenes/boot/boot.tscn` becomes the main scene. It confirms `Config` loaded, then calls `goto_title()`. The title and level select live in `scenes/title/`, and the pause menu in `ui/menus/pause_menu.*`. One `level.tscn` serves all levels, parameterised by level id.
- **Placeholder levels:** Story 4.1 creates `data/levels/level_1.json`, `level_2.json` and `level_3.json`, each with a `name` ("Cargo Ambush", "The Blockade", "Siege of the Throne World") and 1–2 short Wasp waves. They must pass `test_data_files.gd`. Epic 7 replaces their content.
- **SaveManager** is the only code that touches `user://`. It uses a `ConfigFile` at `user://save.cfg` (`%APPDATA%\DEFECTOR\` via the custom user dir) with section `[progress]`: `save_version=1`, `highest_unlocked_level`, `energy`. A missing file gives defaults (1, 0). A corrupt file or unknown version gives a `Log.warn` and defaults, never a crash. Tests use an injectable test path, never the real save.
- **GameState** holds `energy`, `current_level_id`, `highest_unlocked_level` and `is_retry`. `highest_unlocked_level` is new in Epic 4.
- **PauseArbiter** is the only code that pauses or sets `mouse_mode`. It uses the reason set `menu`/`story`/`final_choice`/`death`. `pop(&"menu")` removes only that reason. It emits `resumed` after writing the mouse mode, and `Player._on_resumed` warps the cursor back to the ship. `clear()` keeps the declared gameplay mouse mode, so **every scene root must call `set_gameplay_mouse_mode`**: `VISIBLE` for menu scenes, `CONFINED_HIDDEN` for the level.
- **Process modes:** the PauseMenu is `PROCESS_MODE_ALWAYS`. The HUD and World are pausable (they freeze). The ShakeCamera reads `PauseArbiter.is_paused()`, so the shake freezes under the menu.
- **Input:** use action names only: `pause` (Esc), `toggle_fullscreen` (F11), `debug_unlock_all` (F7). Never read raw keys.
- **Display settings:** 1920×1080 base, stretch `canvas_items` / aspect `keep`. Cursor warps use viewport coordinates.
- **Error handling:** fail loudly in debug and degrade in release. A fatal config parse error results in `Log.error` plus the title error label. Logging goes through `Log`, with the `scene`, `save` and `boot` categories. No `print()`.
- **Tests (GUT, headless):** `test_save_manager` (round-trip, missing, corrupt, unknown version), `test_pause_arbiter`, `test_data_files`, and the player sprite test (the texture is non-null and not a `GradientTexture2D`, and the scaled longer side equals `sprite_px` within 1 px). Re-run `--import` after adding a `class_name` or an asset.
- Update `game-architecture.md` with the as-built state (for example `assets/sprites/player/`, plus SaveManager and router status).

## UX & Interaction Patterns

- **Theme:** every menu uses the single `ui/theme/defector_theme.tres` with no per-node overrides. Buttons have a `surfaceAlt` fill, a 1px border and 4px corners. Hover shows a `coalition` border and glow. Buttons, labels and headings are UPPERCASE. Text is never below 20px.
- **Mouse only:** hover to highlight, click to activate. There is no keyboard menu navigation. Esc closes the pause menu.
- **Title:** the `DEFECTOR` logo is 120px with a coalition glow, centred at y 300. The buttons are 400×72, stacked with a 24px gap, the first with its top at y 560. The error label in `danger` replaces the buttons.
- **Level Select:** three 480×280 cards in a centred row with a 48px gap, top at y 360. Each card shows the level number, name and a thumbnail. Locked cards show at 40% opacity with a `LOCKED` label and can't be clicked. The BACK button is 240×64 at (32, 984).
- **Pause menu:** a centred 520-wide panel with a 48px `PAUSED` heading and 400×72 buttons with a 24px gap, over the 60% `dim`. Only one dim layer ever shows, never stacked. The HUD stays visible but frozen, and the cursor is a visible arrow.
- Nothing is more than two clicks from the title.

## Cross-Story Dependencies

- 4.1 creates `boot.tscn`, the router's `start_level`/`goto_title` and the placeholder level files, which 4.2–4.4 build on. 4.2 creates `SaveManager` and the save-based restore in `goto_title()`, which 4.3 needs for unlock state and saved energy.
- 4.4 relies on the Story 1.8 resume-warp, the existing `death` reason from the Epic 3 retry prompt, and `restart_level()` from Story 3.2.
- 4.2 hooks into `Events.level_cleared` from the Epic 2 WaveDirector, which until now only shows a placeholder banner.
- Later epics extend this flow: Epic 5 adds the opening story scene (only on a fresh Level 1 start, skipped on retry), and Epic 7 adds the end screen after Level 3 and replaces the placeholder level data.
- 4.0 must keep the existing player, shield-bubble and missile-ring tests green. The missile-ring radius is clamped to `player.sprite_px / 2`.
