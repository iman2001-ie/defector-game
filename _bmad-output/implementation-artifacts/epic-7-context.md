# Epic 7 Context: The Campaign: Three Levels and the Flagship

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Turn the placeholder levels into the real campaign. The player plays Cargo Ambush, The Blockade and the Siege of the Throne World, beats Isolde's Flagship across three phases, makes the Final Choice and sees the war end on an end screen. Earlier epics built the machinery (waves and triggers, comms, the convoy, allies, Tarek's fall), so this epic is mostly level data plus one boss entity, the Final Choice control and the end screen. It closes the "surrender mirror" story beat: Isolde offers Vale surrender in Level 1, and in the finale Vale offers it back and she refuses. Everything is MUST except the council epilogue (COULD).

## Stories

- Story 7.1: Play Level 1: Cargo Ambush
- Story 7.2: Play Level 2: The Blockade
- Story 7.3: Face the Flagship's Turrets (Phase 1)
- Story 7.4: Break the Exposed Core (Phase 2)
- Story 7.5: Make the Final Choice (Phase 3)
- Story 7.6: Play Level 3: Siege of the Throne World
- Story 7.7: End the War: Isolde's Final Line and the End Screen
- Story 7.8: Hear the Council Epilogue (COULD)

## Requirements & Constraints

- **Game win:** the Flagship is destroyed, Isolde's final line plays, then the end screen appears. In a full Level 3 run with all flags on, no phase soft-locks and the Final Choice, the refusal and the final line each fire exactly once. The full-run F1-overlay playtest is owed to the operator; tests don't claim it.
- **Levels:** wave content matches the GDD exactly; a level clears when every scripted wave (in Level 3, the Flagship) is destroyed. No timers, score or rating. About 3-4 min per level plus dialogue.
- **Dialogue model:** a paused briefing opens each level and a paused story line closes it. Only two mid-fight pauses in the game: the L1 surrender and the L3 Final Choice. At most 1-2 unpaused combat interruptions per level.
- **Flags gate story beats, never progress.** Every level completes with any flag off. 7.8 adds `council_epilogue` to `flags.json`; when false, the end screen shows directly.
- **Final Choice:** both options lead to Isolde's refusal; the choice only changes that response. `GameState.final_choice` holds it for the session (not saved). The epilogue may reference the choice in at most one line.
- **Tuning:** never hard-code a GDD number. Any value the docs leave open goes in `tuning.json` with a decision-log row and is provisional until the operator playtest.

## Technical Decisions

- **Level data** is all of `data/levels/level_<n>.json`. The root `music` key is not read (start music with a `music` action on W1's `wave_start`; the boss wave runs `music: boss`). Isolde interruptions are `progress` 0.25 triggers gated by `isolde_interruptions`. Formation rows are 90 px apart from `top_y` 160; zone clamps fail a test and are fixed by entry order.
- **Level 3 as built (7.6):** `background` `throne_world`, `ally` `ryn`, no convoy, `intro_sequence` `l3_briefing` (skipped on retry), W1-W3 then the boss wave `{ "boss": "flagship" }` last, **`outro_sequence` still null**. The full-run comms requests are `[l3_briefing, l3_w3_isolde_taunt, l3_final_choice]`; the chosen response plays as the choice's `next` and is never requested. With `hunter_wasp` off (shipped), W2's Hunter Wasps are skipped and not counted.
- **Throne-world backdrop:** `LevelBackground` (on `level.tscn`'s `Background` node) draws a code-drawn placeholder planet arc only for `apply("throne_world")`; Levels 1-2 draw nothing. The end screen can reuse it instead of building a second placeholder. Final art is Epic 8.
- **Flagship (7.3-7.5):** `Flagship extends Enemy`, phases `ARRIVING, TURRETS, CORE, FINAL_CHOICE, DESPERATE, DYING`; numbers under `tuning.boss`. The core clamps to exactly 50 HP, the Flagship enters `FINAL_CHOICE` and requests `l3_final_choice`; it enters `DESPERATE` on `comms_sequence_finished(&"l3_final_choice")`, which the channel emits once, only after the chosen response has played. Core death enters `DYING`: `Feedback.boss_death(pos)` runs the 2 s chain, then `Events.boss_defeated` fires exactly once and the Flagship frees itself.
- **Boss wave resolution:** resolves only on the first `boss_defeated`. Then the normal clear path runs: `outro_sequence` (if any; a story outro pauses and also plays on a retry) → `Events.level_cleared(3)` → `level.gd` calls `SceneRouter.complete_level(3)`, which unlocks, saves (`SaveManager.save()` has no other caller) and, after the last level, currently calls `goto_title()`.
- **Story 7.7 work:** set `outro_sequence` to `l3_isolde_final` (already written: one Isolde story line). Add `SceneRouter.goto_end()` loading `scenes/end/end_screen.tscn` (+ `end_screen.gd`) and make `complete_level` call it after the last level instead of `goto_title()`. Tests pinning the old behaviour must change: `test_level_3.gd` (router called once with the title scene), `test_level_3_siege_shape` in `test_data_files.gd` (null outro), and the `complete_level` rows in `test_scene_router.gd`. The dev boss level (id 0) never saves or changes scene. No doc fixes the closing line's wording.
- **Story 7.8 work:** sequence `ending_council` in a new `data/dialogue/ending.json`. Today `goto_story(id, next_level)` takes a level number and `finish_story()` always loads that level (or the title when nothing is pending), so routing the story to the end screen needs a router change. `goto_story` is refused while `Config.load_error` is set.
- **Project rules:** only `SceneRouter` changes scenes (it clears `PauseArbiter` before each change), only `PauseArbiter` pauses, only `Feedback` touches `Engine.time_scale`, only `Spawner` creates entities, the HUD reads `Events` only, logging goes through `Log`. First outcome wins: after `level_cleared` the player is safe.

## UX & Interaction Patterns

- **Ending sequence:** Vale's line, Isolde's refusal, panel closes, desperate barrage, Flagship dies, Isolde's final line, (optional council epilogue), end screen.
- **End screen:** `background` colour with the throne-world backdrop; `DEFECTOR` 120 px at y 320; one closing line 30 px at y 480; `Thanks for playing` 28 px `muted` at y 560; BACK TO TITLE button 400 x 72 at y 700. Button labels are uppercase.
- **Story lines** use the centred story panel over the dimmed screen, advanced by click.

## Cross-Story Dependencies

- **Done, awaiting operator playtest:** 7.1-7.6 (7.3-7.5 via `dev_boss` + F6; 7.6 a full Level 3 run, including whether the placeholder arc reads as the throne-world reveal).
- **7.7** needs `boss_defeated` (7.5) and Level 3 (7.6). **7.8** needs 7.7's `goto_end()` routing and `GameState.final_choice` (7.5).
- **Epic 8** supplies final art (Flagship, backgrounds, throne world, end screen), audio and the tuning pass.
