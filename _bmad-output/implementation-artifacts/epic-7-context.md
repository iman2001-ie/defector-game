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

- **Wave content matches the GDD exactly** (counts are in each story's ACs). A level clears when every scripted wave is destroyed; in Level 3 that includes the Flagship. No timers, score or rating. About 3–4 min per level plus dialogue, 10–15 min for the game. No wave or phase may soft-lock; the full-run F1-overlay playtest is owed to the operator, tests don't claim it.
- **Cover:** every wave with Needles has at least 2 medium or large asteroids.
- **Dialogue model:** a paused briefing opens each level and a paused debrief closes it (Level 1 has no briefing; the opening story is its intro). At most 1–2 one-line combat interruptions per level, unpaused (Tarek's cut-off doesn't count). Only two mid-fight pauses in the game: the L1 surrender and the L3 Final Choice. Control tutorials are hints, never comms.
- **Flags gate story beats, never progress.** Every level is completable with any flag off (`surrender_prompts`, `isolde_interruptions`, `tarek_fall`, `hunter_wasp`; 7.8 adds `council_epilogue`). Anything that must happen either way goes in both triggers of a `flag` / `!flag` pair (e.g. the L1 W5 Maul reinforcements). With `hunter_wasp` off, the L3 W2 Hunter Wasp entry is skipped and not counted.
- **The throne world appears only in Level 3**, as a reveal. Placeholder art is fine until Epic 8.
- **Flagship numbers** all come from `tuning.boss` via `Config`:
  - Phase 1: 4 turrets × 25 HP, core invulnerable, staggered 3-bullet spreads at 350 px/s, 2 medium cover asteroids.
  - Phase 2: 200 HP core, 12-bullet radial burst at 300 px/s; 5 Wasps every 10 s, at most 10 alive.
  - Final Choice: when the core first drops to ≤ 50 HP, clamp it to exactly 50 and keep it invulnerable until the choice resolves.
  - Desperate: 2 alternating radial bursts (300 px/s) plus an aimed 3-bullet spread (400 px/s); the core pulses red.
  - Hull contact costs 2 hearts and never destroys anything. A destroyed turret plays the Boss-part tier and always drops an orb. Boss death: 4× chain explosions over 2 s, 20 px / 1.0 s shake, 150 ms hit-stop, one white flash.
- **Boss timing is start-to-start:** each interval is the full shot-to-shot period with its glow or charge inside it, never added on top; every telegraph ≥ 0.3 s and ≤ its interval (enforced by `test_wasp_and_boss_telegraphs_fit_their_periods`). Turrets 3.0 s / 0.5 s glow; core 3.0 s / 0.6 s; desperate radial 1.5 s / 0.4 s; desperate aimed 2.0 s / 0.3 s. The Wasp launch timer has no telegraph.
- **Boss-launched Wasps** don't count toward the wave, drop on `drops.wasp`, stop launching once the Flagship leaves `CORE`; live ones stay.
- **Final Choice:** both options lead to Isolde's refusal; the choice changes only that response. Each response opens with a short Vale line, then Isolde. Surrender option: Vale offers surrender in Isolde's own Level 1 words ("You're outnumbered…", never "come home") and she refuses with contempt. Destroy option: Vale vows, she refuses with defiance. The choice, the refusal and the final line each fire exactly once.
- **Epilogue (COULD):** at most one line may reference the player's choice.

## Technical Decisions

- **A level is entirely `data/levels/level_<n>.json`:** background, ally, convoy, waves, groups, triggers, `intro_sequence`, `outro_sequence`.
  - The root `music` key is **not read**: start music with a `music` action on W1's `wave_start`; switch to `boss` with an action on the boss wave.
  - Trigger `when`: `wave_start`, `progress` (`at`), `wave_clear`, `boss_phase` (`phase`), `boss_hp_le` (`hp`). The WaveDirector does **not yet run** `boss_phase` / `boss_hp_le`; the first story that needs them wires them.
  - Actions: `comms`, `spawn_group`, `story_event`, `music`, `wait`, `hint` (`move_fire`, `missile`). E/Q energy hints are raised by the HintPill, not level data.
  - `LevelValidator` rejects a second `spawn_group` of the same group and a Needle entry that isn't the first row-taking entry of its wave.
- **Formation rows:** each spawn entry or group takes the next row (Hunter Wasps and Mauls don't). Row spacing is 90 with `top_y` 160 (rows at y 160/250/340/430). Zones: Needles row 0 only, Lancers y ≤ 378, Bastions y 160–320, Wasps y ≤ 432. A clamp logs `[WARN][spawn]` and fails `test_zoned_formations_fit_their_top_zone`; fix it by entry order (clamp exemptions, engine changes and GDD mix changes were rejected). L3 W3 order: Bastion, Lancers, Wasps as `grid_10x2`. L3 W2 starts with its Needles. Known side effect: a missile on a lower-row Wasp usually splash-kills the one above (same for the two boss-Wasp rows 60 px apart); operator judges, retunes go in `tuning.json` with a decision-log row.
- **Patterns to copy from Levels 1–2:** Lancers before Wasps; the Isolde interruption is a `progress` 0.25 trigger gated by `isolde_interruptions`; full-run tests build the real `level.tscn` with an invincible player, a test save, a router recorder and a captured Log, check every comms request, and assert no `[WARN][spawn]`, `stalled` or `[ERROR][wave]` line. Data tests still treat Level 3 as a placeholder (no ally/convoy/Maul) and `test_boss_waves_only_in_dev_levels` allows boss waves only in dev levels; 7.6 must update both (Level 3's ally is `ryn`).
- **Boss wave (built):** `{ "boss": "flagship", "triggers": [...] }` has total 1 and resolves only on the first `Events.boss_defeated` (ignored outside a boss wave and after `level_failed`). The WaveDirector spawns the boss via `Spawner.spawn_boss` after the `wave_start` triggers, plus `boss.phase1_medium_asteroids` cover on top of the wave's own asteroids. Bosses live in `EntityRegistry.BOSSES` (never a valid `spawns` type); the Flagship is in `Groups.BOSS`, never `COUNTED`. Debug: F3 frees the boss and resolves the wave; F6 restarts the boss wave with a fresh Flagship and frees every `Groups.BOSS_WASPS` node. Dev level: `level_dev_boss.json`.
- **Flagship structure (built through Phase 3, Stories 7.3-7.5):**
  - `Flagship extends Enemy` (section `boss.hull`); `FlagshipPart extends Enemy` is the base of `FlagshipTurret` (`boss.turrets`) and `FlagshipCore` (`boss.core`). A part's `invulnerable` flag ignores `apply_damage` and makes it untargetable (micro-missiles and the ally skip it). Contact never destroys boss parts.
  - The hull is armour: it spends shots, ignores all damage including splash, is never targeted, costs 2 hearts. The invulnerable core behaves the same.
  - `enum Phase { ARRIVING, TURRETS, CORE, FINAL_CHOICE, DESPERATE, DYING }`, entered via `_enter_phase()`, stepped by `step(delta)`. Every entry emits `boss_phase_changed(phase)` and `boss_hp_changed`; part HP changes re-emit `boss_hp_changed(current, 300, phase)` with current = summed remaining part HP.
  - Turret spreads are not aimed (±15° around straight down); only the desperate spread is aimed.
  - Phase 2: the 4th turret death enters `CORE` (after the arrival, if the turrets died on the way in). The core's radial cycle and the Wasp launch timer each start one full period in. Launches request n = min(5, 10 − live launched, free slots) Wasps through `Spawner.spawn_enemy(&"wasp", {slot, launch_from})` from the cached core position to 10 fixed `boss.core.wasp_slots`. Entering any other phase calls `core.stop_attacking()` and stops launches.
  - **Phase 3 (built, Story 7.5, decision #56):** in `CORE` the first hit that would take the core to <= `boss.final_choice_hp` clamps it to exactly 50 and makes it invulnerable (`FlagshipCore.set_hp_floor` / `apply_damage`, never a kill), then the Flagship enters `FINAL_CHOICE` (core attack and launches stop, live Wasps stay) and requests `l3_final_choice` (`Flagship.FINAL_CHOICE_SEQUENCE`). It enters `DESPERATE` once on `comms_sequence_finished(&"l3_final_choice")` (other ids ignored): the core is damageable again and runs `start_desperate()` (12-bullet radials every 1.5 s, every other one turned 15 degrees; an aimed 3-bullet +-15 degree spread at 400 px/s every 2.0 s; first shots one full period in; one shared Glow; the Eye pulses red at 2 Hz). The core's death in any phase enters `DYING`: no core impact of its own (`Enemy._death_feedback()` override), `enemy_killed(&"flagship_core")`, no drop, hull and part collision layers 0, `Feedback.boss_death(global_position)` once, then after `feedback.boss_death_chain_s` (2.0) one INFO line, `Events.boss_defeated` exactly once and the Flagship frees itself (launched Wasps stay). The 7.4 placeholder (`core destroyed`, staying in CORE) is gone.
  - Every `*_speed_px_s` key under `tuning.boss` is checked as a bullet speed, so don't use that suffix for non-bullet speeds.
- **Final Choice flow:** entering `FINAL_CHOICE` requests `l3_final_choice`. `CommsChannel` gains `choice` support (`options` with `id`, `label`, `next`): after the lead-in lines it shows `FinalChoice` (in `systems/comms/final_choice.*`, `PROCESS_MODE_ALWAYS`, under the `Comms` CanvasLayer) instead of emitting `finished`. While shown, `PauseArbiter.push(&"final_choice")` (the pause menu already refuses to open then). On click: emit `Events.final_choice_made(&"surrender" | &"destroy")`, store `GameState.final_choice`, pop the reason, play `next` (`l3_isolde_refuse_surrender` / `l3_isolde_refuse_destroy`). `finished` fires only after `next` completes; the Flagship waits for it before `DESPERATE`. **Built (Story 7.5):** `finished` is emitted once, with the requested id (`l3_final_choice`), never for `next`; while the choice is up the `click to continue` cue is hidden and `comms_advance` clicks are consumed and ignored; the response plays in the same panel after a `comms_handover`. No `final_choice` view: `Log.error` and a plain finish; an unknown `next`: `Log.error` and an immediate finish. `FinalChoice` is `Comms/FinalChoice` in `level.tscn` (after `CommsPanel`), wired to the channel's `final_choice` export; layout `ui.final_choice`, theme type `FinalChoice` (the retry prompt's button boxes).
- **Boss death (built, Story 7.5):** `Feedback.boss_death(pos)` sequences the chain explosions, not the Flagship: 4 Boss-death explosions (scale 4) at `pos + feedback.boss_death_chain_offsets_px` at 0, 0.667, 1.333 and 2.0 s; the first carries the white flash, the 20 px / 1.0 s shake and the 150 ms hit-stop, every one the tier sfx; `step_chain(delta)` advances them in game time only while unpaused and `reset()` drops them. `explosion_boss_death` is registered in `Audio` (placeholder alias of the large explosion until Epic 8), and `Explosion` handles `white_flash` (a full-screen white overlay on layer 15, between the HUD and Comms, alpha 0.7 fading linearly over 0.3 s, `feedback.white_flash`).
- **Dialogue is written:** all 15 campaign sequences exist (including `l3_briefing`, `l3_w3_isolde_taunt`, `l3_final_choice`, both refusals, `l3_isolde_final`). `l3_final_choice` carries the `choice` block since Story 7.5 (OFFER SURRENDER -> `l3_isolde_refuse_surrender`, DESTROY HER -> `l3_isolde_refuse_destroy`; labels uppercase in the data), validated by `DialogueValidator` and pinned by the data tests. Never request a story sequence at the same moment as a cut-off (the story drops the cut-off's effects).
- **Scene flow:** `complete_level(n)` returns to the title after the last level; 7.7 adds `SceneRouter.goto_end()` (planned) loading `scenes/end/end_screen.tscn`. The epilogue uses the existing `goto_story(id, next)` with `data/dialogue/ending.json`.
- **Project rules:** only `SceneRouter` changes scenes, only `PauseArbiter` pauses, only `Feedback` touches `Engine.time_scale`, only `Spawner` creates entities (boss-launched Wasps are the one case where something other than the WaveDirector decides what spawns), the HUD reads `Events` only. The first outcome wins: after `level_failed` the WaveDirector freezes and action chains stop; after `level_cleared` the player is safe.
- **New tuning numbers are provisional:** any value the docs leave open goes in `tuning.json` with a decision-log row (as #54 and #55 did for Phases 1 and 2); the operator confirms feel in playtest.

## UX & Interaction Patterns

- **Boss bar (built):** takes the wave bar's slot (centred, y 40, 560 × 20) with a 0.3 s cross-fade; `enemy` fill of combined HP (300) draining right to left; `text` markers at 66.7% (turrets gone) and 16.7% (core at 50); `FLAGSHIP` label in `muted` below at y 68.
- **Final Choice:** appears after Isolde's lead-in in the centred story panel over the dimmed screen. Two 480 × 120 buttons, OFFER SURRENDER and DESTROY HER, 48 px apart, top at y 680, `coalition` glow on hover. No timer, `click to continue` cue hidden, clicks outside the buttons do nothing, Esc disabled.
- **Ending sequence:** Vale's line, Isolde's refusal, panel closes, desperate barrage, Flagship dies, Isolde's final line, end screen.
- **End screen:** `background` colour with the throne-world backdrop; `DEFECTOR` 120 px at y 320; closing line 30 px at y 480; `Thanks for playing` 28 px `muted` at y 560; BACK TO TITLE button 400 × 72 at y 700.
- **Retries** skip the briefing and go straight to wave 1.

## Cross-Story Dependencies

- **Done, awaiting operator playtest:** 7.1, 7.2, 7.3, 7.4, 7.5. For 7.3-7.5 the operator owes a `dev_boss` + F6 check (arrival, turret and core readability, burst dodgeability, Wasp-launch fairness, cover usefulness, boss bar; for 7.5 the clamp and choice beat, the buttons, the desperate barrage's readability and fairness, the red pulse and the death chain, shake, hit-stop and single white flash).
- **Order:** 7.3 → 7.4 → 7.5 build the Flagship phase by phase. 7.6 puts the boss wave into Level 3 and needs 7.3–7.5. 7.7 needs `boss_defeated` (7.5) and Level 3 (7.6). 7.8 needs the end-screen routing from 7.7.
- **Earlier epics relied on:** Epic 2 (enemies, asteroids), 3 (energy abilities), 4 (level flow, saving), 5 (comms, interruptions, cut-off, hints), 6 (convoy, allies; Ryn is Level 3's ally).
- **Cut stories:** if 3.3–3.5 were cut, the E/Q hints don't show. L3 W2's Hunter Wasps depend on Story 2.8 (COULD); if cut, `hunter_wasp` stays false.
- **Epic 8** supplies final art (Flagship, backgrounds, throne world), audio and the tuning pass.
