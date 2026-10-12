# Epic 7 Context: The Campaign: Three Levels and the Flagship

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Turn the placeholder levels into the real campaign. The player plays Cargo Ambush, The Blockade and the Siege of the Throne World, beats Isolde's Flagship across three phases, makes the Final Choice and sees the war end on an end screen. Earlier epics built the machinery: waves and triggers, comms, the convoy, allies and Tarek's fall. This epic is mostly level data, plus one new boss entity, the Final Choice control and the end screen. It closes the "surrender mirror" story beat: Isolde offers Vale surrender in Level 1, and in the finale Vale offers it back and she refuses. Everything here is MUST except the council epilogue (COULD).

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

- **Wave content must match the GDD exactly.** The counts are in each story's acceptance criteria. A level clears when every scripted wave is destroyed, and in Level 3 that includes the Flagship. There are no timers, no score and no rating. Each level should take about 3–4 minutes plus dialogue, and the whole game about 10–15 minutes. No wave or phase may soft-lock: check with a full run and the F1 overlay. That playtest is owed to the operator; tests don't claim it.
- **Cover:** every wave with Needles needs at least 2 medium or large asteroids.
- **Dialogue model:**
  - A paused briefing opens each level and a paused debrief closes it. Level 1 has no briefing, because the opening story is its intro.
  - Each level has at most 1–2 one-line combat interruptions, with no pause. Tarek's cut-off doesn't count toward that limit.
  - The whole game has only two mid-fight pauses: the L1 surrender and the L3 Final Choice.
  - Control tutorials are hints, never comms.
- **Flags gate story beats, never progress.** Every level must still be completable with any flag off (`surrender_prompts`, `isolde_interruptions`, `tarek_fall`, `hunter_wasp`; Story 7.8 adds `council_epilogue`).
  - Anything that must happen with the flag on or off goes in both triggers of a `flag` / `!flag` pair. Example: the L1 W5 Maul reinforcements.
  - With `hunter_wasp` off, the L3 W2 Hunter Wasp entry is skipped and not counted.
- **The throne world appears only in Level 3, as a reveal.** Placeholder art is fine until Epic 8.
- **Flagship numbers:** all of these come from `tuning.boss` through `Config`, never hard-coded.
  - **Phase 1:** 4 turrets with 25 HP each, and the core is invulnerable. Each turret fires a staggered 3-bullet spread at 350 px/s. 2 medium asteroids drift through as cover.
  - **Phase 2:** the 200 HP core fires a 12-bullet radial burst at 300 px/s. Every 10 s it launches 5 Wasps, with at most 10 alive.
  - **Final Choice:** when the core first drops to 50 HP or below, its HP is clamped to exactly 50 and it is invulnerable until the choice resolves.
  - **Desperate phase:** 2 alternating radial bursts (300 px/s) plus an aimed 3-bullet spread (400 px/s). The core pulses red.
  - **Contact:** touching the hull costs 2 hearts.
  - **Turrets:** a destroyed turret plays the Boss-part tier (1.5×, 6 px / 0.2 s shake, 30 ms hit-stop) and always drops an orb.
  - **Boss death:** 4× chain explosions over 2 s, a 20 px / 1.0 s shake, a 150 ms hit-stop and one white flash.
- **Boss timing is start-to-start (decisions #50 and #52).** Each interval is the full period from one shot to the next, and the glow or charge runs inside it, never added on top. Every glow or charge lasts at least 0.3 s.

  | Attack | Interval | Glow or charge |
  |---|---|---|
  | Turrets | 3.0 s | 0.5 s glow |
  | Core | 3.0 s | 0.6 s charge |
  | Desperate radial | 1.5 s | 0.4 s charge |
  | Desperate aimed spread | 2.0 s | 0.3 s glow |

  The data test `test_wasp_and_boss_telegraphs_fit_their_periods` requires each glow or charge to be no longer than its interval. The Wasp launch timer has no glow and isn't affected.
- **Boss-launched Wasps** don't count toward the wave and drop energy at the normal Wasp rate. Launches stop once the Flagship leaves `CORE`, and Wasps already alive stay.
- **Final Choice:** both options lead to Isolde's refusal, and the choice changes only that response.
  - Each response opens with a short Vale line, then Isolde's refusal.
  - For the surrender option, Vale offers surrender in Isolde's own Level 1 words ("You're outnumbered…"), not "come home", and Isolde refuses with contempt (decision #44). For the destroy option, Vale makes a vow and Isolde refuses with defiance.
  - The Final Choice, the refusal and the final line each fire exactly once.
- **Epilogue (COULD):** at most one line may reference the player's choice.

## Technical Decisions

- **Everything about a level lives in `data/levels/level_<n>.json`:** background, ally, convoy, waves, groups, triggers, `intro_sequence` and `outro_sequence`.
  - **Music:** the `music` key at the top of the level file is **not read**. Start music with a `music` action on wave 1's `wave_start`, and switch to `boss` with an action on the boss wave.
  - **Trigger `when` values:** `wave_start`, `progress` (with `at`), `wave_clear`, `boss_phase` (with `phase`) and `boss_hp_le` (with `hp`).
  - **Actions:** `comms`, `spawn_group`, `story_event`, `music`, `wait` and `hint` (`move_fire`, `missile`). The E and Q energy hints are raised by the HintPill itself, not by level data.
  - **Validation:** `LevelValidator` rejects a second `spawn_group` for the same group, and a Needle entry that isn't the first row-taking entry of its wave.
- **Formation rows (decision #53):**
  - Each spawn entry or group takes the next formation row. Hunter Wasps and Mauls don't take a row.
  - Row spacing `waves.formation.spacing_px.y` is now **90** (was 120). With `top_y` 160, the rows sit at y 160, 250, 340 and 430.
  - Zone limits: Needles only in row 0, Lancer slots at y ≤ 378, Bastion slots between y 160 and 320, and Wasp slots at y ≤ 432.
  - A slot outside its zone gets clamped. That logs `[WARN][spawn]` and fails `test_zoned_formations_fit_their_top_zone`. Fix it by ordering the entries. Clamp exemptions, engine changes and changes to the GDD wave mix were all rejected.
  - Required order for L3 W3: Bastion (y 160), then Lancers (y 250), then Wasps as `grid_10x2` (y 340 and 430). L3 W2 must start with its Needles.
  - Known side effect: with the tighter rows, a missile hitting a lower-row Wasp now usually splash-kills the Wasp above it. The operator will judge this in playtest, and any retune goes in `tuning.json` with a decision-log entry.
- **Patterns from Levels 1 and 2 to copy:**
  - Put Lancers before Wasps in the entry order.
  - The Isolde interruption is a `progress` 0.25 trigger gated by `isolde_interruptions`.
  - Level 2's fall is a single `progress` 0.5 trigger gated by `tarek_fall`, with no `!flag` pair.
  - Full-run tests build the real `level.tscn` with an invincible player, a test save, a router recorder and a captured Log. They check every comms request and that no `[WARN][spawn]`, `stalled` or `[ERROR][wave]` line appears.
  - The data tests treat Level 3 as a placeholder (no ally, no convoy, no Maul). Story 7.6 must update those guards, because Level 3's ally is `ryn`. It must also update `test_boss_waves_only_in_dev_levels` (Story 7.3) when Level 3 gets its boss wave.
- **Boss wave:**
  - A wave of the form `{ "boss": "flagship", "triggers": [...] }` has a total of 1 and resolves only on `Events.boss_defeated`.
  - The Flagship (type id `flagship`) and the Wasps it launches both spawn through `Spawner`. Those Wasps are the one exception to "only the WaveDirector decides what spawns".
  - F6 (`debug_skip_to_boss`) already exists and reopens a failed or cleared attempt.
- **Flagship state machine:** `enum Phase { ARRIVING, TURRETS, CORE, FINAL_CHOICE, DESPERATE, DYING }`, built with `match` and `_enter_phase()`. It emits `boss_phase_changed` on every phase change.
  - **Ownership:** the Flagship owns its phase and HP for one level attempt.
  - **Files:** `entities/boss/` holds `flagship`, `flagship_part`, `flagship_turret` and `flagship_core`. Turrets and the core sit on the `enemies` collision layer.
  - **Contact:** `Enemy.destroy_by_contact()` ignores anything that isn't SMALL or MEDIUM, so boss parts survive contact with the player.
  - **Signals:** `Events` already declares `boss_started`, `boss_hp_changed(current, max_hp, phase)`, `boss_phase_changed(phase)`, `boss_defeated` and `final_choice_made(choice)`, where `choice` is `&"surrender"` or `&"destroy"`.
- **Final Choice flow:**
  1. Entering `FINAL_CHOICE` requests the `l3_final_choice` sequence.
  2. `CommsChannel` gains `choice` support (`options` with `id`, `label`, `next`). After the lead-in lines it shows `FinalChoice` instead of emitting `finished`.
  3. While the buttons are up, `PauseArbiter.push(&"final_choice")` keeps combat paused. The pause menu already refuses to open during `final_choice`.
  4. On a click: emit `final_choice_made`, store the choice in `GameState.final_choice`, pop the pause reason, then play the option's `next` sequence (`l3_isolde_refuse_surrender` or `l3_isolde_refuse_destroy`).
  5. `finished` fires only after `next` completes, and the Flagship waits for it before entering `DESPERATE`.
  6. `FinalChoice` lives in `systems/comms/final_choice.*` and runs with `PROCESS_MODE_ALWAYS` under the `Comms` CanvasLayer.
- **Boss death:** `Feedback.boss_death(pos)` runs the chain explosions, not the Flagship. Two known gaps must be closed:
  - The `boss_death` tier's sfx id isn't registered in `Audio` yet. (The `boss_part` sfx id is registered since Story 7.3, as a placeholder alias of the large explosion.)
  - `Explosion` ignores the `white_flash` extra.
- **Dialogue is already written** (15 campaign sequences, including `l3_briefing`, `l3_w3_isolde_taunt`, `l3_final_choice`, both refusals and `l3_isolde_final`). Levels only reference these ids.
  - `l3_final_choice` has no `choice` block yet, and an existing data test asserts that it has none. Story 7.5 adds the block and updates that test.
- **Cut-offs:** never request a story sequence at the same moment as a cut-off, because the story would drop the cut-off's effects.
- **Scene flow:**
  - `SceneRouter.complete_level(n)` currently returns to the title after the last level. Story 7.7 replaces that with `goto_end()` (still planned), which loads `scenes/end/end_screen.tscn`.
  - The epilogue uses the existing `goto_story(id, next)` with `data/dialogue/ending.json`.
- **Project-wide rules:** only `SceneRouter` changes scenes, only `PauseArbiter` pauses, only `Feedback` touches `Engine.time_scale`, and the HUD reads `Events` only.
- **The first outcome wins (decision #39).** After `level_failed` the WaveDirector freezes and running action chains stop. After `level_cleared` the player is safe.

## UX & Interaction Patterns

- **Boss bar:**
  - It takes the wave bar's slot (centred, y 40, 560 × 20) with a 0.3 s cross-fade when the Flagship arrives.
  - The `enemy` fill shows the combined remaining HP (turrets 100 + core 200 = 300) and drains right to left.
  - Two `text`-coloured markers sit at 66.7% (turrets gone) and 16.7% (core at 50 HP).
  - A `FLAGSHIP` label in `muted` is centred below the bar at y 68.
- **Final Choice:**
  - It appears after Isolde's lead-in, in the centred story panel over the dimmed screen.
  - Two 480 × 120 buttons, OFFER SURRENDER and DESTROY HER, sit 48 px apart with their top edge at y 680.
  - Hovering a button shows a `coalition` glow.
  - There is no timer and the `click to continue` cue is hidden. Clicks outside the buttons do nothing, and Esc is disabled.
- **End screen:**
  - On the `background` colour with the throne-world backdrop, from top to bottom:
    - `DEFECTOR` at 120 px, y 320
    - the closing line at 30 px, y 480
    - `Thanks for playing` at 28 px in `muted`, y 560
    - a BACK TO TITLE button, 400 × 72, at y 700
- **Retries:** a retry or restart skips the briefing and goes straight to wave 1.

## Cross-Story Dependencies

- **Done (awaiting operator playtest):** Stories 7.1 and 7.2.
- **Flagship build order:** Stories 7.3 → 7.4 → 7.5 build the Flagship one phase at a time.
  - 7.6 puts the boss wave into Level 3 and needs 7.3–7.5.
  - 7.7 needs `boss_defeated` from 7.5 and Level 3 from 7.6.
  - 7.8 needs the end-screen routing from 7.7.
- **Earlier epics this one relies on:** Epic 2 (enemies and asteroids), Epic 3 (energy abilities), Epic 4 (level flow and saving), Epic 5 (comms, interruptions, cut-off and hints) and Epic 6 (convoy and allies; Ryn is Level 3's ally).
- **Cut stories:**
  - If Stories 3.3–3.5 were cut, the E and Q hints don't show.
  - Level 3 W2's Hunter Wasps depend on Story 2.8 (COULD). If it was cut, `hunter_wasp` stays false.
- **Epic 8** supplies the final art (Flagship, backgrounds, throne world), the audio and the tuning pass. Placeholders are fine until then.
