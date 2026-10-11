# Epic 7 Context: The Campaign: Three Levels and the Flagship

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Turn the placeholder levels into the real campaign. The player plays Cargo Ambush, The Blockade and the Siege of the Throne World, beats Isolde's Flagship across three phases, makes the Final Choice and sees the war end on an end screen. Earlier epics built the machinery: waves and triggers, comms, the convoy, allies and Tarek's fall. This epic is mostly level data plus one new boss entity, the Final Choice control and the end screen. It closes the "surrender mirror" pillar: Isolde offers surrender in Level 1, and in the finale Vale offers it back and she refuses. Everything here is MUST except the council epilogue (COULD).

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

- **Wave content must match the GDD exactly** (the counts are in each story's AC). A level clears when every scripted wave is destroyed. In Level 3 that includes the Flagship. There are no timers, no score and no rating. Each level should take about 3–4 minutes plus dialogue, about 10–15 minutes for the whole game. No wave or phase may soft-lock. Check this with a full run and the F1 overlay.
- **Every Needle wave needs at least 2 medium or large asteroids as cover.**
- **Dialogue model:** a paused briefing opens each level and a paused debrief closes it. Each level has at most 1–2 one-line combat interruptions with no pause. The game has only two mid-fight pauses: the L1 surrender and the L3 Final Choice. Level 1 has no briefing because the opening story is its intro. Control tutorials are hints, never comms.
- **Flags gate beats, never progress.** Every level must still be completable with any flag off (`surrender_prompts`, `isolde_interruptions`, `tarek_fall`, `hunter_wasp`; Story 7.8 adds `council_epilogue`). Anything that must happen either way, such as the L1 W5 Maul reinforcements, goes in both triggers of a flag/`!flag` pair. With `hunter_wasp` off, the Hunter Wasp entry is skipped and not counted.
- **The throne world appears only in Level 3, as a reveal.** Placeholder art is fine until Epic 8.
- **Flagship numbers (all from `tuning.boss` through `Config`, never hard-coded):**
  - **Phase 1:** 4 turrets with 25 HP each. The core is invulnerable. Each turret fires a staggered 3-bullet spread at 350 px/s.
  - **Phase 2:** a 200 HP core fires a 12-bullet radial burst at 300 px/s. Every 10 s it launches 5 Wasps, with at most 10 alive.
  - **Final Choice:** when the core first drops to ≤ 50 HP, its HP is clamped to exactly 50 and it is invulnerable until the choice resolves.
  - **Desperate phase:** 2 alternating radial bursts (300 px/s) and an aimed 3-bullet spread (400 px/s). The core pulses red.
  - **Contact:** touching the hull costs 2 hearts.
  - **Turrets:** a destroyed turret plays the Boss-part tier and always drops an orb.
  - **Boss death:** 4× chain explosions over 2 s, a 20 px / 1.0 s shake, a 150 ms hit-stop and one white flash.
- **Boss cadence is start-to-start.** Every boss interval includes its glow or charge, and that glow or charge is at least 0.3 s. Turrets fire every 3.0 s with a 0.5 s glow. The core fires every 3.0 s with a 0.6 s charge. The desperate radial fires every 1.5 s with a 0.4 s charge, and the aimed spread every 2.0 s with a 0.3 s glow. A data test enforces telegraph ≤ period.
- **Boss-launched Wasps:** they are not counted toward the wave and drop energy at the normal Wasp rate. Launches stop once the Flagship leaves `CORE`. Wasps already alive stay.
- **Final Choice:** both options lead to her refusal. Each response opens with a short Vale line (the surrender offer in Isolde's own Level 1 words, or the vow), then Isolde's refusal. The choice changes only that response. The Final Choice, the refusal and the final line each fire exactly once.
- **Epilogue (COULD):** at most one line may reference the player's choice.

## Technical Decisions

- **Everything per level lives in `data/levels/level_<n>.json`:** background, ally, convoy, waves, groups, triggers, `intro_sequence` and `outro_sequence`.
  - **Music:** the level-root `music` key is **not read**. Start music with a `music` action (for example on `wave_start`) and switch to `boss` with an action on the boss wave.
  - **Trigger `when` values:** `wave_start`, `progress` (with `at`), `wave_clear`, `boss_phase` (with `phase`) and `boss_hp_le` (with `hp`).
  - **Actions:** `comms`, `spawn_group`, `story_event`, `music`, `wait` and `hint` (`move_fire`, `missile`). The E/Q energy hints are raised by the hint pill itself, not by data.
  - **Validation:** `LevelValidator` rejects a second `spawn_group` for the same group, and a Needle entry that isn't the first row-taking entry of its wave.
- **Boss wave:** a wave of the form `{ "boss": "flagship", "triggers": [...] }` has a total of 1 and resolves only on `Events.boss_defeated`. The Flagship is spawned through `Spawner` (type id `flagship`). Its boss-launched Wasps also go through `Spawner`. That is the one exception to "only the WaveDirector decides what spawns". F6 (`debug_skip_to_boss`) already exists and reopens a failed or cleared attempt.
- **Flagship state machine:** `enum Phase { ARRIVING, TURRETS, CORE, FINAL_CHOICE, DESPERATE, DYING }` using `match` and `_enter_state()`, with `boss_phase_changed` emitted on every change.
  - **Ownership:** the Flagship owns its phase and HP for one level attempt.
  - **Files:** `entities/boss/` holds `flagship`, `flagship_turret` and `flagship_core`. Turrets and the core sit on the `enemies` collision layer.
  - **Contact:** `Enemy.destroy_by_contact()` ignores anything that isn't SMALL or MEDIUM, so boss parts survive contact.
  - **Signals:** `boss_started`, `boss_hp_changed(current, max_hp, phase)`, `boss_phase_changed(phase)`, `boss_defeated` and `final_choice_made(choice)` (`&"surrender"` or `&"destroy"`) are all declared in `Events`.
- **Final Choice flow:**
  1. Entering `FINAL_CHOICE` requests `l3_final_choice`.
  2. `CommsChannel` gains `choice` support: after the lead-in lines it shows `FinalChoice` instead of emitting `finished`.
  3. While the buttons are up, `PauseArbiter.push(&"final_choice")` is active. The pause menu already refuses to open during `final_choice`.
  4. On a click: emit `final_choice_made`, store `GameState.final_choice`, pop the reason, then play the option's `next` sequence (`l3_isolde_refuse_surrender` or `l3_isolde_refuse_destroy`).
  5. `finished` fires only after `next` completes. The Flagship waits for that before it enters `DESPERATE`.
  6. `FinalChoice` runs with `PROCESS_MODE_ALWAYS` under the `Comms` CanvasLayer (`systems/comms/final_choice.*`).
- **Boss death:** `Feedback.boss_death(pos)` sequences the chain explosions, not the Flagship. Known gaps to close:
  - The sfx ids for the `boss_part` and `boss_death` tiers aren't registered in `Audio` yet.
  - `Explosion` ignores the `white_flash` extra.
- **Dialogue is already written** (15 campaign sequences, including `l1_w3_tarek_warning`, `l1_w3_isolde_interrupt`, `l1_w5_surrender`, `l1_tarek_closing`, `l2_briefing`, `l2_w3_isolde_interrupt`, `l2_w5_tarek_cutoff`, `l2_ryn_report`, `l3_briefing`, `l3_w3_isolde_taunt`, `l3_final_choice`, both refusals and `l3_isolde_final`). Levels only reference them. `l3_final_choice` has no `choice` block yet, and the existing data test asserts that it has none, so Story 7.5 must add the block and update that test.
- **Tarek's fall** is data: at 50% of L2 W5, one trigger runs `story_event: tarek_fall` and `comms: l2_w5_tarek_cutoff`. Never request a story sequence at the same moment as a cut-off, because the story would drop the cut-off's effects.
- **Scene flow:** `SceneRouter.complete_level(n)` currently goes to the title after the last level. Epic 7 replaces that with `goto_end()` (still planned), which loads `scenes/end/end_screen.tscn`. The epilogue uses the existing `goto_story(id, next)` with `data/dialogue/ending.json`. Only `SceneRouter` changes scenes, only `PauseArbiter` pauses, only `Feedback` touches time scale, and the HUD reads `Events` only.
- **First outcome wins.** After `level_failed` the WaveDirector freezes. After `level_cleared` the player is safe.

## UX & Interaction Patterns

- **Boss bar:**
  - It takes the wave bar's slot (centred, y 40, 560 × 20) with a 0.3 s cross-fade when the Flagship arrives.
  - The `enemy` fill shows the combined remaining HP (turrets 100 + core 200 = 300) and drains right to left.
  - Two `text`-coloured markers sit at 66.7% (the turrets are gone) and 16.7% (core at 50).
  - A `FLAGSHIP` label in `muted` is centred below the bar at y 68.
- **Final Choice:**
  - It appears after Isolde's lead-in in the centred story panel over the dim.
  - It shows two 480 × 120 buttons, OFFER SURRENDER and DESTROY HER, with a 48 px gap and their top at y 680.
  - Hover shows a `coalition` glow. There is no timer, the `click to continue` cue is hidden, clicks outside the buttons do nothing and Esc is disabled.
- **End screen:**
  - `DEFECTOR` at 120 px, y 320.
  - The closing line at 30 px, y 480.
  - `Thanks for playing` at 28 px in `muted`, y 560.
  - BACK TO TITLE at 400 × 72, y 700.
  - It sits on `background` with the throne-world backdrop.
- **Control hints (Level 1):**
  - W1 shows `MOVE THE MOUSE TO FLY` and then `[HOLD LMB] FIRE`. W2 shows `[RMB] MISSILE`.
  - Each hint shows once per session, and retries don't repeat it.
  - A first-time player should understand the controls by L1 W2 with no verbal help.
- A retry or restart skips the briefing and goes straight to wave 1.

## Cross-Story Dependencies

- 7.3 → 7.4 → 7.5 build the Flagship one phase at a time. 7.6 places the boss wave in Level 3 and needs 7.3–7.5. 7.7 needs `boss_defeated` from 7.5 and Level 3 from 7.6. 7.8 needs the end-screen routing from 7.7.
- 7.1 and 7.2 use what earlier epics built:
  - the convoy, Mauls and Lancer convoy targeting (6.1–6.3)
  - allies and Tarek's fall (6.4, 6.5)
  - comms, interruptions, the surrender prompt, cut-off and hints (Epic 5)
  - enemies and asteroids (Epic 2)
  - energy abilities (Epic 3)
  - level flow and saving (Epic 4)
- The E/Q hints depend on Stories 3.3–3.5. If those were cut, the hints don't show.
- 7.6's W2 Hunter Wasps depend on Story 2.8 (COULD). If it was cut, the flag stays false.
- Epic 8 supplies the final art (Flagship, backgrounds, throne world), the audio and the tuning pass. Placeholders are fine here.
