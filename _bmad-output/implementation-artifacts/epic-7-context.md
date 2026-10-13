# Epic 7 Context: The Campaign: Three Levels and the Flagship

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic turns the placeholder levels into the real campaign. The player plays Cargo Ambush, The Blockade and the Siege of the Throne World, beats Isolde's Flagship across three phases, makes the Final Choice and sees the war end on an end screen. Earlier epics built the machinery (waves and triggers, comms, the story scene, the convoy, allies and Tarek's fall). So most of this epic is level data, plus one boss entity, the Final Choice control and the end screen. It closes the "surrender mirror" story beat: Isolde offers Vale surrender in Level 1, and in the finale Vale offers it back and she refuses. Every story is MUST except the council epilogue (7.8, COULD), which adds a short story scene between Level 3's clear and the end screen.

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

- **Game win:** the Flagship is destroyed, Isolde's final line plays, then the end screen appears. The council epilogue is optional (COULD) and plays between the final line and the end screen.
- **Council epilogue (7.8):** add a `council_epilogue` flag to `flags.json`. When it is true, clearing Level 3 plays a short story sequence `ending_council` from a new `data/dialogue/ending.json`, then shows the end screen. When it is false, the end screen shows directly, exactly as it does today. At most one line may refer to the player's Final Choice. The docs don't set the flag's shipped default or the epilogue's wording.
- **Flags gate story beats, never progress.** Every level and the ending complete with any flag off.
- **Final Choice:** both options lead to Isolde's refusal, and the choice changes only her response. `GameState.final_choice` (`&"surrender"` or `&"destroy"`, `&""` until the choice is made) is kept for the session and is never saved or reset.
- **Dialogue model:** each level opens with a paused briefing and closes with a paused story line. There are only two mid-fight pauses in the game: the Level 1 surrender and the Level 3 Final Choice. Story lines appear in the centred story panel and advance on click. Speakers are limited to `vale`, `isolde`, `tarek`, `ryn` and `system`. In the story, Isolde is dead by this point and Tarek is alive but badly injured.
- **Tuning:** never hard-code a GDD number. Any value the docs leave open goes in `tuning.json` with a decision-log row and stays provisional until the operator playtest. Feel and wording are owed to the operator, and tests don't claim them.

## Technical Decisions

- **Level 3 as built:** `throne_world` background, `ryn` as the ally, no convoy, `l3_briefing` as the intro (skipped on a retry), waves W1-W3, then the boss wave `{ "boss": "flagship" }` last. `outro_sequence` is `l3_isolde_final`: one paused Isolde story line, which also plays on a retry. A full run requests `[l3_briefing, l3_w3_isolde_taunt, l3_final_choice, l3_isolde_final]`. The chosen response plays as the choice's `next` and is never requested.
- **Flagship (7.3-7.5):** `Flagship extends Enemy`, with the phases `ARRIVING`, `TURRETS`, `CORE`, `FINAL_CHOICE`, `DESPERATE` and `DYING`. Its numbers live under `tuning.boss`. When the core's HP clamps to 50, the Flagship requests `l3_final_choice`. It enters `DESPERATE` on the single `comms_sequence_finished(&"l3_final_choice")`, which arrives after the response has played. When the core dies, `Feedback.boss_death` plays a 2 s chain, then `Events.boss_defeated` fires once.
- **Clear path (7.7):** the boss wave resolves on `boss_defeated`, then the outro plays (paused), then `Events.level_cleared(3)` fires. After that `level.gd` calls `SceneRouter.complete_level(3)`, which unlocks progress, saves (`complete_level` is the only caller of `SaveManager.save()`) and then calls `goto_end()`. `goto_end()` clears the level id and the retry flag, keeps the energy and `final_choice`, and writes no save. The end screen is `scenes/end/end_screen.tscn` (`EndScreen`). It reuses `LevelBackground` with `throne_world`, its layout is under `tuning.ui.end_screen`, its closing line is a code constant (decision #57), and BACK TO TITLE calls `goto_title()`. The end screen adds no music. The dev boss level (id 0) never saves or changes scene.
- **Story routing (7.8):** `goto_story(id, next_level: int)` stores a pending id and level, keeps the energy, and is refused while `Config.load_error` is set. The story scene (`StoryScene`) plays the pending id and calls `finish_story()` once when that id finishes, including when the id is unknown, so nothing soft-locks. `finish_story()` loads the pending level, and with nothing pending it warns and goes to the title. So it can't route to the end screen yet. Sending the epilogue to the end screen needs a router change. The natural place for the flag check is `complete_level` of the last level, which today calls `goto_end()`. The story scene has no backdrop (the clear colour) and its panel doesn't dim.
- **Dialogue loading:** `Config` loads every `data/dialogue/*.json` file in name order, so `ending.json` needs no registration. Invalid files or sequences are logged and left out without setting `load_error`. The dialogue format has no conditional lines.
- **Tests 7.8 will touch:** `test_scene_router.gd` (the `complete_level(3)` rows, which expect one change to the end screen); the all-flags-on run in `test_level_3.gd`, which turns every `flags.json` key on and expects one change to the end screen; and the flags and dialogue checks in `test_data_files.gd`.
- **Project rules:** only `SceneRouter` changes scenes (it clears `PauseArbiter` after each change). Only `PauseArbiter` pauses, only `Feedback` touches `Engine.time_scale`, and only `Spawner` creates entities. The HUD reads `Events` only, and logging goes through `Log`. After `level_cleared` the first outcome wins, and the player is safe.

## UX & Interaction Patterns

- **Ending sequence:** Vale's line, then Isolde's refusal. The panel closes, the desperate barrage starts and the Flagship dies. Then Isolde's final line, the council epilogue (if the flag is on) and the end screen.
- **Story scene:** the centred story panel over a static space backdrop. It advances on click, and Esc does nothing (there's no skip).
- **End screen:** `background` colour with the throne-world backdrop. `DEFECTOR` at 120 px on y 320, one closing line at 30 px on y 480, `Thanks for playing` at 28 px in `muted` on y 560, and a BACK TO TITLE button (400 x 72) at y 700. Button labels are uppercase.

## Cross-Story Dependencies

- **Done, awaiting the operator playtest:** stories 7.1-7.7. For 7.3-7.5 the playtest uses `dev_boss` and F6. For 7.6 and 7.7 it is a full Level 3 run to the end screen, judging the closing-line wording and how the placeholder arc reads.
- **7.8** depends on 7.7's `complete_level` → `goto_end()` routing and the end screen, on `GameState.final_choice` (7.5), and on the Epic 5 story scene and `goto_story` / `finish_story`.
- **Epic 8** supplies the final art (Flagship, backgrounds, throne world and end screen), the audio (including any end-screen music) and the tuning pass.
