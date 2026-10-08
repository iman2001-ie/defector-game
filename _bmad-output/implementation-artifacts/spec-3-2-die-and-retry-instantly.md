---
title: 'Story 3.2: Die and Retry Instantly'
type: 'feature'
created: '2026-10-07'
baseline_revision: 'c2c1e657791a53f6957a0e8b057d94e64b4754be'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-3-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/EXPERIENCE.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** At 0 hearts the player just stops taking damage. There is no death feedback, no `player_died`/`level_failed`, no retry prompt and no way to restart. `GameState` and `SceneRouter` don't exist yet. Covers FR12, FR11, FR14 (reset) and FR30 (player death). MUST tier.

**Approach:** The lethal hit kills the Player: it plays the PLAYER_DEATH tier, emits `Events.player_died` then `Events.level_failed(&"hearts")`, and the ship is hidden and inert. A `RetryPrompt` in `Overlay` waits `feedback.player_death_pause_s` (1.5 s, pausable), then calls `PauseArbiter.push(&"death")` and shows a dim, `HULL DESTROYED` and RETRY · QUIT TO TITLE. A new `GameState` autoload (energy, `current_level_id`, `is_retry`) and a new `SceneRouter` autoload (`restart_level()`, a placeholder `goto_title()`) reload `level.tscn` with the same level id (ADR-004).

## Boundaries & Constraints

**Always:**
- Statically typed GDScript. Numbers come from `Config`, read once in `_ready`. Existing keys: `feedback.player_death_pause_s` (1.5) and `feedback.tiers.player_death`. New key `ui.retry_prompt` {`headline_y` 440, `headline_px` 48, `button_w` 320, `button_h` 80, `button_gap_px` 48, `buttons_top_y` 560}.
- Autoload order in `project.godot`: `Log, Events, Config, GameState, PauseArbiter, Audio, Feedback, EntityRegistry, SceneRouter`. `SaveManager` is Epic 4 and keeps its slot between GameState and PauseArbiter. `SceneRouter` is `PROCESS_MODE_ALWAYS`.
- `GameState` (`autoloads/game_state.gd`, extends Node, no logic beyond fields): `energy: int = 0`, `current_level_id: String = ""` (the level file key, e.g. `"dev"`), `is_retry: bool = false`.
- `SceneRouter` (`autoloads/scene_router.gd`): `const LEVEL_SCENE_PATH := "res://scenes/level/level.tscn"`. `var change_scene: Callable` defaults to `get_tree().change_scene_to_file` in `_ready`, and tests inject a recorder (the same pattern as `Player.warp_mouse`). `restart_level()` sets `GameState.energy = 0` and `GameState.is_retry = true`, then calls `PauseArbiter.clear()`, `Feedback.reset()` and `change_scene.call(LEVEL_SCENE_PATH)`, and logs one `Log.info("scene", …)`. There is no counter and no limit.
- `goto_title()` is a placeholder until Epic 4 builds the title: it sets `energy = 0` and `is_retry = false`, then does the same clear/reset and calls `change_scene` with `ProjectSettings` `application/run/main_scene` (today `level.tscn`, so it starts a fresh, non-retry attempt). Its doc comment says Story 4.1/4.2 replace it.
- `level.gd` resolves its id with a static `resolve_level_id(exported: String, state_id: String) -> String` (state id if non-empty, else the export), writes the result back to `GameState.current_level_id`, and adds ` (retry)` to its start log line when `GameState.is_retry` is set.
- Player death (`player.gd`): on the hit that brings hearts to 0, `apply_damage` still emits `hearts_changed` and `player_hit`. It then plays `Feedback.impact(ImpactTier.PLAYER_DEATH, …)` instead of PLAYER_HIT, emits `Events.player_died` then `Events.level_failed(&"hearts")` exactly once, and logs once. After death: `is_dead()` is true; the node is hidden (`visible = false`, which also hides the MissileRing); i-frames stop; `monitoring` and `monitorable` are switched off with `set_deferred`; `_contacts` is cleared; `on_contact` and `apply_damage` are no-ops; and `_physics_process` returns at once (no lock, no fire, no missile). This replaces the Story 3.1 "hearts reached 0" log.
- `RetryPrompt` (`ui/menus/retry_prompt.tscn` + `.gd`, `class_name RetryPrompt extends Control`, full rect, under `Overlay`): `PROCESS_MODE_ALWAYS`, hidden at start, `MOUSE_FILTER_STOP` only while shown. It has a `Dim` ColorRect (theme `dim` rgba(0,0,0,0.6)), a `Reason` Label (48 px, `danger` #FF1F4B, centred horizontally, top at `headline_y`), and `Retry` / `Quit` Buttons (`RETRY`, `QUIT TO TITLE`, 320×80, centred pair with a 48 px gap, top at y 560). Button style: `surfaceAlt` rgba(10,18,34,0.85) fill and 1 px `border` #2A3B5C; hover/focus has a `coalition` #22E6FF border. Theme items go in `defector_theme.tres` under the `RetryPrompt` type.
- On the first `Events.level_failed(reason)` it starts `get_tree().create_timer(beat_s, false)` (pausable). When that fires, `show_prompt(reason)` calls `PauseArbiter.push(&"death")`, sets the reason text (`&"hearts"` → `HULL DESTROYED`, `&"convoy"` → `CONVOY LOST`, anything else → `HULL DESTROYED` plus a `Log.warn`), shows the prompt and gives `Retry` focus. Later `level_failed` emissions are ignored. Retry → `SceneRouter.restart_level()`; Quit → `SceneRouter.goto_title()`. A button press during a repeat press does nothing more (guard with a `_leaving` flag). Accessors: `is_shown()`, `reason_text()`, `is_pending()`.
- Tests never call the real scene change: every test that reaches `SceneRouter` injects a recorder and restores the default in `after_each`. Tests that touch `GameState` reset its three fields in `after_each`. Tests that push pause reasons call `PauseArbiter.clear()`.

**Never:**
- No reset methods on entities (ADR-004). No `change_scene*` outside `SceneRouter` (the existing debug F5 and the `--stress` redirect stay as they are). No `tree.paused`/`Engine.time_scale`/`mouse_mode` writes outside their owners. No bare `print()`.
- No energy logic (clamp, `energy_changed`, orbs: Story 3.3), no `SaveManager`, title, level select, pause menu or briefing (Epics 4 and 5), and no convoy loss (Epic 6). The Esc pause menu doesn't exist yet, so there is nothing to block during death.
- The HUD is not changed. The retry prompt doesn't read gameplay nodes (Events in, SceneRouter out).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Lethal hit | 1 heart, `apply_damage(1, b)` | hearts 0; `hearts_changed(0,5)`, `player_hit`, `player_died`, `level_failed(&"hearts")` once each; PLAYER_DEATH tier; ship hidden | n/a |
| Overkill contact | 1 heart, Bastion contact (−2) | same as lethal hit; the Bastion survives | n/a |
| Hit after death | dead, `apply_damage` / `on_contact` / `debug_invincible` off | no events, no feedback, small enemy not destroyed | n/a |
| Death beat | `level_failed` fired, < beat_s elapsed | prompt hidden, `is_pending()`, not paused | n/a |
| Beat ends | ≥ beat_s of unpaused time | `death` in `PauseArbiter.reasons()`, mouse VISIBLE, prompt shown with `HULL DESTROYED` | n/a |
| Beat under pause | another reason pushed during the beat | timer frozen; prompt not shown until unpaused time reaches beat_s | n/a |
| Second failure | `level_failed` again while pending/shown | ignored (one timer, one push) | n/a |
| Retry | prompt shown, RETRY pressed | `energy` 0, `is_retry` true, not paused, `time_scale` 1, `change_scene(level.tscn)` once | n/a |
| Many retries | `restart_level()` ×N | N identical scene changes, no limit | n/a |
| Quit | QUIT TO TITLE pressed | `is_retry` false, energy 0, not paused, `change_scene(main_scene)` | n/a |
| Reloaded level | fresh `level.tscn` with `current_level_id` "dev", `is_retry` true | same id; 5 hearts; wave 1; no enemies/projectiles beyond wave 1's spawns; retry prompt hidden | n/a |

</intent-contract>

## Code Map

- `game/entities/player/player.gd` -- `apply_damage` (the lethal branch replaces the `_zero_logged` log), `on_contact`, `_recheck_contacts`, `_physics_process`. Add `_dead`, `is_dead()` and `_die()`. Its class doc says "death is Story 3.2"; update it.
- `game/autoloads/feedback.gd` -- `impact(tier, pos)` and `reset()`. Read-only. The `player_death` row's sfx `player_death` isn't in `Audio.SFX` yet (architecture "known gaps" line 967).
- `game/autoloads/audio.gd` (`SFX` dict, line ~9), `tools/gen_placeholder_sfx.py` (`main()`; `player_hit` uses its own `PLAYER_HIT_SEED`), `game/assets/CREDITS.md` (row pattern at line 20) -- add a `player_death` WAV (a heavier, ~1 s explosion-plus-buzz, own seed, appended so existing WAVs stay byte-identical) and register it.
- `game/autoloads/pause_arbiter.gd` -- `push(&"death")`, `clear()`, `reasons()`, `current_mouse_mode()`. Read-only.
- `game/autoloads/events.gd` -- `player_died` and `level_failed(reason)` already exist. No change.
- `game/scenes/level/level.gd` -- `@export level_id`, `_ready` start log. Add the id resolution and the retry tag.
- `game/scenes/level/level.tscn` -- add `Overlay/RetryPrompt` (instance of the new scene) before `DebugTools`, so the debug overlay draws on top.
- `game/ui/hud/level_clear_banner.gd`, `wave_bar.gd` -- patterns for Events-driven UI, Config reads in `_ready` and theme lookup by type.
- `game/ui/theme/defector_theme.tres` -- add the `RetryPrompt` colours (`dim`, `reason`) and the button StyleBoxes.
- `game/ui/debug/debug_tools.gd` -- F5 (`reload_data`) is the existing debug-only reload. Leave it unchanged.
- `game/project.godot` `[autoload]` and `game/tests/unit/test_project_settings.gd` `AUTOLOADS` -- the new order.
- `game/data/tuning.json` -- add `ui.retry_prompt`. Check `game/tests/data/test_data_files.gd` for any section whitelist.
- `game/tests/unit/test_level.gd` -- the long-running wave tests (`test_clearing_every_dev_wave…`, `test_dev_level_clears_with_real_kills…`, `test_dev_wave_3..6`) could now kill the player and pause the tree. Make the player `debug_invincible` in those tests. `after_each` already clears PauseArbiter; also reset `GameState`.
- `game/tests/unit/test_player_hearts.gd` -- the overkill/0-heart rows expect the old 3.1 log and behaviour. Update them to the death behaviour.
- `_bmad-output/game-architecture.md` -- the directory "built parts" line (~562), the state table, the Scene management row (line 132), the process-modes row (SceneRouter planned → built), the known-gaps line 967 (`player_death` sfx now registered), and the Player row in System Location Mapping.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_player_death.gd`, `test_game_state.gd`, `test_scene_router.gd`, `test_retry_prompt.gd` -- NEW, written first. Cover every I/O-matrix row. Observe the PLAYER_DEATH tier through a registered test `ShakeCamera`'s shake amplitude (12 px, not 6) or an equivalent observable. Check the retry prompt layout rects (reason top 440; buttons 320×80 at x 616 and 984, y 560). Set `feedback.player_death_pause_s` small in `Config.tuning` before instantiating, and call `Config.load_data()` in `after_each`.
- `game/autoloads/game_state.gd`, `game/autoloads/scene_router.gd`, `game/project.godot` -- NEW autoloads in the stated order. Then run `--import`.
- `game/entities/player/player.gd` -- the death behaviour per Boundaries.
- `game/scenes/level/level.gd` -- `resolve_level_id`, the write-back and the retry log tag.
- `game/ui/menus/retry_prompt.gd`, `retry_prompt.tscn`, `game/ui/theme/defector_theme.tres`, `game/scenes/level/level.tscn`, `game/data/tuning.json` -- the prompt per Boundaries.
- `tools/gen_placeholder_sfx.py`, `game/assets/audio/sfx/sfx_player_death.wav`, `game/autoloads/audio.gd`, `game/assets/CREDITS.md`, `game/tests/unit/test_audio.gd` -- add the `player_death` SFX. Regenerate, confirm that only the new WAV changed, then run `--import`.
- `game/tests/unit/test_level.gd`, `test_player_hearts.gd`, `test_project_settings.gd` -- update per the Code Map. Add a level test: kill the player in a real level, wait out the beat, assert the prompt and `death` pause, press Retry with a recorder, then free the level and instantiate the recorded path fresh. Assert 5 hearts, wave 1, the same id, not paused and `is_retry` true.
- `_bmad-output/game-architecture.md` -- mark GameState, SceneRouter (`restart_level`, placeholder `goto_title`), the retry prompt, player death and the `player_death` sfx as built.

**Acceptance Criteria:**
- Given the level is running, when the player's hearts reach 0, then the PLAYER_DEATH tier plays with the `player_death` SFX and no "unknown sfx" warning, `Events.player_died` and `Events.level_failed(&"hearts")` fire once, and after 1.5 s of unpaused time `PauseArbiter` holds `death`, the cursor is visible and `Overlay/RetryPrompt` shows `HULL DESTROYED` with RETRY and QUIT TO TITLE.
- Given the retry prompt is shown, when RETRY is clicked, then `GameState.energy` is 0, `is_retry` is true, the pause reasons are empty and `level.tscn` is loaded again. The reloaded level keeps the same `current_level_id` and starts at wave 1 with 5 hearts and no leftover entities.
- Given the game boots, when the autoloads load, then their order is `Log, Events, Config, GameState, PauseArbiter, Audio, Feedback, EntityRegistry, SceneRouter`.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 30 findings — high 0, medium 2, low 20, false 8, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: the level can clear after the player dies (a lethal contact with the last small enemy still destroys it, or an in-flight missile kills the last enemy during the beat), so LEVEL CLEAR and HULL DESTROYED both show. This is real, but it needs the final enemy to fall in the same instant as the death, and level-clear progression (Epic 4) doesn't exist yet. A guard means new cross-system state (clear vs fail exclusion). Recorded as a residual risk for Epic 4.
  - `[low]` `[reject]` Blind: `SceneRouter._change_to` ignores the `change_scene` Error, so a failed change leaves the prompt stuck. It is unreachable with a valid build: `LEVEL_SCENE_PATH` is a const that a test asserts exists, and `main_scene` is configured. Godot already logs the error, and a fix adds error-recovery branches.
  - `[low]` `[reject]` Blind: `PauseArbiter.clear()` runs before the deferred scene swap, so the old level gets one unpaused frame. The architecture and Story 4.1 AC mandate clear-first ("calls PauseArbiter.clear() first"). The dead ship is inert, so the frame is invisible in practice.
  - `[low]` `[reject]` Blind: nothing outside SceneRouter clears `is_retry`/`energy`, so a debug F5 restart after a retry is tagged retry. This is debug-only, and Story 4.1's `start_level` is specified to clear `is_retry`.
  - `[low]` `[patch]` Blind: `grab_focus()` draws the coalition focus ring on RETRY permanently, so it looks hovered while the mouse is over QUIT (UX is mouse-only). Fixed with `_retry.grab_focus(true)` (hide_focus, confirmed in 4.7.2): focus kept, ring hidden.
  - `[low]` `[patch]` Blind: the `GameState.energy` doc says "wiped to 0 on death", but death doesn't touch it. Comment reworded: only `restart_level()`/`goto_title()` reset it.
  - `[low]` `[patch]` Blind: `goto_title()` keeps the stale `current_level_id`, so "fresh attempt of the main scene" reuses the last id. `goto_title()` now sets it to `""`; the test asserts it and the architecture as-built line was updated.
  - `[medium]` `[patch]` Blind: the button theme items (focus style, text colour, font size 28, the applied overrides) are untested. Same root cause as the verification-gap row; patched there.
  - `[low]` `[reject]` Blind: the layout values are duplicated in the tscn offsets, and the button font size lives in the theme rather than tuning. The tscn values are editor-preview values that `_ready` overwrites (the carried 3.1 reasoning). 28 px is the UX `body` typography token, and the theme owns typography.
  - `[low]` `[reject]` Blind: DESIGN.md says the headline is "centred at y 440", while the code puts the top at 440. The spec settled "top at headline_y". The difference is a few px of placeholder layout, and the fix would edit the spec.
  - `[false]` `[reject]` Blind: the beat tests can flake with fixed sleeps. Both the pausable beat timer and the test's real-time timer are SceneTreeTimers advanced by the same process-frame delta, so a stall advances both equally. The only difference is the deliberate hit-stop, which the 0.6 s wait covers.
  - `[false]` `[reject]` Blind: setting `hearts = 0` directly leaves an undying ship. No game code writes `hearts` outside `apply_damage`; only tests do (as in the 3.1 triage).
  - `[low]` `[reject]` Blind: no direct test that `_contacts` is empty or that `_recheck_contacts` is a no-op after death. Both are guarded by `_dead` twice, and the debug-invincible-after-death test exercises the re-check path with no events.
  - `[false]` `[reject]` Blind: "only the new WAV changed" can't be checked from the diff. It was checked: `git status --short game/assets/audio/sfx` shows only `sfx_player_death.wav` (+ `.import`) added and no modified WAVs.
  - `[low]` `[reject]` Edge: scene-change error unchecked. Same as the Blind row (unreachable; Godot logs it).
  - `[low]` `[reject]` Edge: one unpaused frame before the swap. Same as the Blind row (clear-first is mandated).
  - `[low]` `[reject]` Edge: `level_cleared` during the death beat shows both banner and prompt. Same root cause as the Blind clear-vs-fail row; residual risk for Epic 4.
  - `[low]` `[reject]` Edge: the player dies after `level_cleared` (a leftover bullet), so the prompt shows on a cleared level. Same clear-vs-fail root cause; rare, and progression is Epic 4.
  - `[low]` `[reject]` Edge: an invalid level id is written back to GameState before the data loads. Only `"dev"` exists today, and a broken level spawns nothing, so the player can't die to reach retry. With the goto_title patch, quit clears the id anyway.
  - `[low]` `[patch]` Edge: `goto_title()` keeps the stale `current_level_id`. Same as the Blind row; patched.
  - `[medium]` `[patch]` Verification gap: RetryPrompt button styling is never checked on the buttons. `test_layout` now asserts, on both buttons, the normal/hover/focus border colours, font size 28 and `font_color` = the theme `text`; `test_uses_the_shared_theme` asserts `button_focus` with the coalition border.
  - `[false]` `[reject]` Intent: the operator-playtest reading (awaiting-operator). The intent's examples are outside-repo infrastructure actions; a feel playtest is this project's standard residual manual check (Stories 3.1 and 1.x).
  - `[low]` `[reject]` Intent: "click Retry" is tested with `pressed.emit()`, not real input. Mouse routing is engine behaviour; `PROCESS_MODE_ALWAYS`, `MOUSE_FILTER_STOP` while shown and the layer order are asserted.
  - `[low]` `[reject]` Intent: the real `change_scene_to_file` is never exercised. Running it in GUT replaces the runner; the callable's identity is asserted, and the reload is simulated by instantiating the recorded path.
  - `[false]` `[reject]` Intent: the cursor is checked via `current_mouse_mode()`, not `Input.mouse_mode`. `PauseArbiter._apply` writes `Input.mouse_mode = current_mouse_mode()`, so they are the same value.
  - `[low]` `[reject]` Intent: the PLAYER_DEATH explosion scale, shake decay and exact 100 ms are not asserted. They are tuning rows covered by the impact-tier tests, and this story changes none of them (carried 3.1 reasoning).
  - `[false]` `[reject]` Intent: hit-stop stretches the beat past 1.5 s of wall time. That is deliberate (Design Notes): the beat is game time, like the rest of the pausable world.
  - `[low]` `[reject]` Intent: the prompt → reload → prompt cycle is never repeated end to end. Each reload is a fresh scene with no counter; 25 router restarts plus the fresh-level test cover "no limit".
  - `[false]` `[reject]` Intent: "running beat chains" are not tested. Beat chains (comms, Epic 5) don't exist yet, and a reload frees the whole scene, which the fresh-level test asserts (no enemies or projectiles beyond wave 1, prompt not pending).
  - `[false]` `[reject]` Intent: QUIT TO TITLE doesn't reach a title. The epic context assigns "the real QUIT TO TITLE target" to Epic 4; the placeholder is disclosed in the spec and the architecture.

### 2026-10-07 — Review pass
- verdicts: 32 findings — high 0, medium 1, low 20, false 11, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: level clear and level fail are not mutually exclusive (in-flight missile or debug resolve-wave clears after death; leftover hazard kills after clear). carried — same clear-vs-fail root cause as the logged rows; residual risk for Epic 4's level-clear progression.
  - `[low]` `[reject]` Blind: `SceneRouter._change_to` drops the `change_scene` Error, so a failed change soft-locks the prompt. carried — unreachable with a valid build (const path asserted to exist, `main_scene` configured); Godot logs the error.
  - `[low]` `[reject]` Blind: the headline's top sits at y 440 while DESIGN.md centres it there. carried — the spec settled "top at headline_y"; a few px of placeholder layout.
  - `[false]` `[reject]` Blind: the hit-stop-stretched beat contradicts "after 1.5 s" and belongs in the decision log. carried — the stretch is deliberate (Design Notes) and the GDD asks for "about 1.5 s"; game-time beats are the existing design, not a new decision.
  - `[false]` `[reject]` Blind: Esc is not disabled while the prompt shows. No non-test code handles the `pause` action or `ui_cancel` today (grep), so Esc does nothing during death; the pause menu and its guard are Epic 4, as the spec's Never list says.
  - `[low]` `[reject]` Blind: a bad level id is written to GameState before `Config.level()` validates it. carried — only `"dev"` exists; a broken level spawns nothing, so no death reaches retry; quit clears the id.
  - `[low]` `[reject]` Blind: the physics-skip test checks no lock/warp but not that firing or missiles stop after death. `_physics_process` returns before all four steps on one `_dead` guard, which the lock assertion already proves; a fire test only adds value if the code is reordered.
  - `[low]` `[reject]` Blind: `PauseArbiter.clear()` gives the old scene one unpaused frame before the swap. carried — clear-first is mandated by the architecture and Story 4.1; the dead ship is inert.
  - `[false]` `[reject]` Blind: `test_debug_invincible_off_after_death_does_nothing` is misnamed. Its final assertions are exactly the after-death toggle doing nothing (one `player_died`/`level_failed`/`player_hit` each); the earlier lines are the setup that produces the death.
  - `[low]` `[reject]` Blind: tests hard-code tuning values (`ui.retry_prompt`, `player_death_pause_s`, 12 px shake, button rects). This is the project's spec-conformance pattern since Epic 1 (`test_config`, layout tests); restructuring every test to derive from Config is a cross-suite change, not a direct correction.
  - `[false]` `[reject]` Blind: the beat and retry tests are wall-clock flaky. carried — both timers are SceneTreeTimers advanced by the same frame delta; the 0.6 s wait covers the deliberate hit-stop.
  - `[low]` `[reject]` Blind: RETRY and QUIT stay clickable after the first press. `_leaving` makes every extra press a no-op, and the hover state lasts only until the deferred scene swap at the end of the frame; disabling adds state for no visible gain.
  - `[low]` `[reject]` Blind: `is_retry` is only cleared by `goto_title()`, so debug F5 after a retry is tagged retry. carried — debug-only; Story 4.1's `start_level` clears it.
  - `[low]` `[reject]` Blind: the prompt logs nothing when it shows, and warns about unknown reasons only after the beat. Not a defect: the spec requires the router's scene log and the unknown-reason warn, both present; extra trace lines are optional.
  - `[low]` `[reject]` Edge: `change_scene` Error unchecked in `_change_to`. carried — same as the Blind row.
  - `[low]` `[reject]` Edge: an empty `application/run/main_scene` makes QUIT call `change_scene_to_file("")`. `project.godot` sets `main_scene`; an empty value is a broken project config that also fails to launch the game, so the guard protects an unreachable state.
  - `[low]` `[reject]` Edge: one unpaused frame before the deferred swap. carried — same as the Blind row.
  - `[false]` `[reject]` Edge: `_on_resumed` after death warps the cursor onto the hidden ship. The warp only moves the cursor to the death spot in the frame before the scene swap; the new level's ship then sits on the cursor by design (`step_lock`), so nothing jumps and no input is lost. During the beat nothing can push and pop a pause outside tests.
  - `[false]` `[reject]` Edge: `hearts` at 0 without `_dead` (tuning 0 or an external write) means the ship can never die. carried — no game code writes `hearts` outside `apply_damage`; `player.hearts` 0 is a broken tuning file, not a reachable state.
  - `[low]` `[reject]` Edge: `level_failed` after `level_cleared`, or `level_cleared` during the beat, stacks the prompt on the banner. carried — clear-vs-fail root cause; residual risk for Epic 4.
  - `[low]` `[reject]` Edge: an invalid resolved id persists in GameState. carried — same as the Blind row.
  - `[low]` `[reject]` Edge: debug F5 after a retry keeps `is_retry`. carried — same as the Blind row.
  - `[medium]` `[patch]` Verification gap: no test proves `SceneRouter._ready` wires the real `change_scene` when nothing is injected (every `after_each` repairs the autoload field, and the factory test calls `default_change_scene()` directly), so breaking the wiring keeps every test green while RETRY and QUIT stop working in a real game. Added `test_ready_wires_the_real_change_scene` to `test_scene_router.gd`: a fresh `scene_router.gd` instance, nothing injected, asserts a valid `change_scene_to_file` callable on `get_tree()`.
  - `[low]` `[patch]` Verification gap (other): the `PauseArbiter.clear()` doc comment still says SceneRouter calls it "(later epics)". Removed the stale "(later epics)" in `game/autoloads/pause_arbiter.gd`.
  - `[low]` `[reject]` Intent: the reloaded-level row is exercised by simulation, not the real `change_scene_to_file`. carried — the contract forbids the real call in tests; the callable is identity-checked (now also on a fresh router).
  - `[false]` `[reject]` Intent: `grab_focus(true)` hides the focus ring, which diverges from "hover/focus has a coalition border". Retry still gets focus as the contract says, and the theme's coalition focus style draws as soon as keyboard navigation shows focus; hiding the ring on show was the last pass's patch so RETRY doesn't look hovered under a mouse-only UX.
  - `[false]` `[reject]` Intent: `goto_title()` also clears `current_level_id`, beyond the contract's list. That is the last pass's patch for the contract's own "starts a fresh, non-retry attempt"; the main scene then runs its exported id, and nothing differs today.
  - `[false]` `[reject]` Intent: the hit-stop stretch of the beat is untested. carried — deliberate per Design Notes; the beat is game time like the rest of the pausable world.
  - `[false]` `[reject]` Intent: the death SFX asset/generator and architecture edits go beyond the contract's lists. "Plays the PLAYER_DEATH tier" needs a registered sound to play at all (the architecture listed it as a gap); the SFX is CC0-generated and credited, and the as-built doc edits are required bookkeeping.
  - `[low]` `[reject]` Intent: extra theme items (text colour, 28 px button font, pressed styles, radii) live in the theme, not Config. carried — the theme owns typography and styles; 28 px is the UX `body` token.
  - `[low]` `[reject]` Intent: `debug_invincible = true` on six long wave tests changes what they prove. Those tests cover wave sequencing, not player vulnerability; vulnerability and death are covered by `test_player_death.gd` and the death → retry level test.
  - `[false]` `[reject]` Intent: `_change_to` logs before calling `change_scene`. The contract only says it "logs one `Log.info`", with no ordering, and the tests assert exactly one line.

## Design Notes

- **Death tier replaces the hit tier:** playing PLAYER_HIT and PLAYER_DEATH together would double the explosion and SFX. Hit-stop and shake keep the longest anyway, so the lethal hit plays PLAYER_DEATH only. `player_hit` is still emitted, so the vignette fires.
- **Where the beat lives:** the 1.5 s beat is a pausable SceneTree timer in RetryPrompt. It freezes under any pause and stretches by the 100 ms death hit-stop (time scale 0). This is the "about 1.5 s" the GDD asks for. During the beat the world keeps running (enemies fly on), and the dead ship is hidden and has no collision.
- **QUIT TO TITLE placeholder:** no title exists until Story 4.1, and the epic context says Epic 4 adds "the real QUIT TO TITLE target". Until then `goto_title()` loads the configured main scene (today the level) as a fresh, non-retry attempt with energy 0, which matches F13's "restore saved energy" because there's no save yet (default 0). Story 4.1 replaces the body; its callers stay.
- **Testable router:** `change_scene` is an injectable Callable, because calling `change_scene_to_file` inside GUT would replace the test runner's scene.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0, the new autoloads, class_names and WAV imported (`<GODOT_DIR>` from `LOCAL.md`).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failures, no new SCRIPT ERRORs.
- `git status --short game/assets/audio/sfx` after regenerating -- expected: only `sfx_player_death.wav` (+ `.import`) is new; no existing WAV is modified.

**Manual checks (if no CLI):**
- Death feel (explosion size, shake, the 1.5 s beat) and the prompt's look need a human playtest; automation can't verify them.

## Auto Run Result

Status: done

**Summary:** Follow-up review pass on Story 3.2 (die and retry instantly). The implementation from the first pass stands. The lethal hit plays PLAYER_DEATH, emits `player_died` then `level_failed(&"hearts")` once, and leaves the ship hidden and inert. `Overlay/RetryPrompt` waits the pausable 1.5 s beat, pushes the `death` pause and shows HULL DESTROYED with RETRY and QUIT TO TITLE. `GameState` and `SceneRouter` handle retry as a scene reload (ADR-004), and QUIT TO TITLE is a placeholder until Epic 4. This pass added one regression test and fixed one stale comment.

**Files changed (this pass):**
- `game/tests/unit/test_scene_router.gd`: new `test_ready_wires_the_real_change_scene`. It checks that a fresh router, with nothing injected, wires `get_tree().change_scene_to_file`.
- `game/autoloads/pause_arbiter.gd`: `clear()` doc comment no longer says "(later epics)".

**Files changed (story, first pass):** GameState and SceneRouter autoloads plus `project.godot` order; `player.gd` death; `level.gd` id resolution and retry tag; `level.tscn` RetryPrompt; `ui/menus/retry_prompt.gd`/`.tscn`; theme `RetryPrompt` items; `tuning.json` `ui.retry_prompt`; the `player_death` SFX (generator, WAV, `.import`, `Audio`, CREDITS); tests; architecture as-built notes.

**Review findings:** 32 findings (high 0, medium 1, low 20, false 11, maybe-false 0).
- **Patched (2):**
  - 1 medium: SceneRouter's `_ready` wiring of the real scene change was untested. A test now covers it.
  - 1 low: stale `PauseArbiter.clear()` comment.
- **Deferred:** none.
- **Rejected (30):** each row's reason is in the Review Triage Log. In short:
  - Carried from the first pass (16): clear vs fail (5 rows), the unchecked scene-change error (2), the unpaused frame before the swap (3), F5 and `is_retry` (2), the invalid id persisting (2), headline top vs centre, wall-clock flakiness, a direct `hearts` write, the beat stretch (3), the simulated reload, and theme items living in the theme. The groups total more than 16 because the beat-stretch group includes two new rows.
  - New lows: no fire-after-death test (one guard covers it), hard-coded tuning in tests (the project's conformance pattern), buttons stay clickable after a press (`_leaving` makes it a no-op), no prompt-shown log line (optional), an empty `main_scene` (broken config), and `debug_invincible` on the wave tests (death is covered elsewhere).
  - New falses: Esc during death (nothing handles it yet), a misnamed test, the cursor warp on resume after death (harmless before the swap), the hidden focus ring (deliberate; the style still draws on keyboard focus), `goto_title` clearing the id (serves "fresh attempt"), the SFX scope, and the log order.

**Follow-up review recommended:** false. This was a follow-up pass. It patched 1 medium and 1 low, and no high (high 0, medium 1, low 1), so the work has converged.

**Verification:**
- `--headless --path game --import` exits 0.
- The full GUT suite passes 728/728 (7136 asserts) with 0 SCRIPT ERRORs after the patches.
- `git status` after the run shows only the two patched files, the spec, and the orchestrator's `sprint-status.yaml`. No asset changed.

**Residual risks:**
- How death feels (explosion, shake, the 1.5 s beat) and how the prompt looks still need a human playtest.
- Level clear and level failure aren't mutually exclusive. Epic 4's level-clear progression should decide this.
- The real `change_scene_to_file` reload runs only in the game. GUT checks the wiring (now also on a fresh router) and simulates the reload.
- QUIT TO TITLE stays a placeholder until Story 4.1/4.2. Esc handling during death belongs with the Epic 4 pause menu.
