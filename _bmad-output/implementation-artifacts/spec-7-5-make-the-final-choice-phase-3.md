---
title: "Story 7.5: Make the Final Choice (Phase 3)"
type: 'feature'
created: '2026-10-12'
status: 'awaiting-operator'
operator_actions:
  - 'Run "<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game res://scenes/level/level.tscn -- --level=dev_boss in a debug build, press F6, destroy the four turrets and damage the core to 50 HP. Confirm the fight pauses, Isolde''s lead-in plays, and the OFFER SURRENDER / DESTROY HER buttons appear below the panel with a coalition hover glow, no timer, and Esc not opening the pause menu.'
  - 'Pick each option on separate runs. Confirm Vale''s line and then Isolde''s matching refusal play, the panel closes, and the desperate barrage starts with no error in the log.'
  - 'Judge the desperate phase: whether the alternating 12-bullet radials (every other one turned 15 degrees), the aimed 3-bullet spread and their glows are readable and fair to dodge, and whether the red pulse reads. Any retune goes in game/data/tuning.json (boss.desperate) with a GDD decision-log entry.'
  - 'Kill the core and judge the boss death: the 4 chain explosions over 2 s, the single white flash (comfort and photosensitivity), the shake and the hit-stop. Confirm the wave and level then clear.'
  - 'Decide whether the player should stay vulnerable to leftover boss Wasps and bullets during the 2 s death chain (today a death there fails the level, per decisions #39 and F16).'
  - 'Confirm or overrule the provisional readings in GDD decision-log row 56, and update the row status accordingly.'
baseline_revision: 'eb2fa5571990ab2b92fd01e5f66c5d599363cd3c'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-7-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/EXPERIENCE.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** After Story 7.4 the Flagship stops at Phase 2. A core taken to 0 HP just dies, and the Flagship stays in `CORE`. There is no Final Choice, no desperate barrage, no boss-death sequence, and nothing emits `Events.boss_defeated`, so the boss wave can only end through F3 (FR51, FR54, the FR30 boss-death row).

**Approach:** The first hit that takes the core to 50 HP or below clamps it to exactly 50 and makes it invulnerable. The Flagship then enters `FINAL_CHOICE` and requests `l3_final_choice`. `CommsChannel` learns the `choice` block: after Isolde's lead-in it shows a new `FinalChoice` control under the `final_choice` pause. A click stores and announces the choice, then plays that option's `next` response. When the response ends, the channel emits `finished(l3_final_choice)` and the Flagship enters `DESPERATE` (attacks from `boss.desperate`, red pulse). When the core dies, the Flagship enters `DYING`: `Feedback.boss_death(pos)` plays the chain, and once the chain ends the Flagship emits `boss_defeated` and frees itself. All numbers come from `tuning.json` through `Config`.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript. Write the failing GUT test first. Log through `Log`. Only `PauseArbiter` pauses, only `Feedback` touches `Engine.time_scale`, and only `Spawner` creates entities.
- **Clamp (decision F7):** while the Flagship is in `CORE`, a core hit whose result would be ≤ `boss.final_choice_hp` sets the core's hp to exactly that value and makes it invulnerable. It never kills the core, even a 999-damage hit. Then `hp_changed` fires. This happens once per Flagship.
- **FINAL_CHOICE entry:** the core attack and the Wasp launches stop (live launched Wasps stay). Emit `boss_phase_changed(3)` and `boss_hp_changed(50, 300, 3)`, then emit `Events.comms_sequence_requested(&"l3_final_choice")` (a const in `Flagship`). The Flagship waits for `Events.comms_sequence_finished(&"l3_final_choice")` and then enters `DESPERATE` once. It ignores every other id and any `finished` outside `FINAL_CHOICE`.
- **Channel choice flow:** a story sequence with a `choice` block plays its lines as usual. On the advance after its last line, the panel stays open on that line with the `click to continue` cue hidden. The channel then calls `PauseArbiter.push(&"final_choice")` (the `story` reason stays) and shows `FinalChoice` with the options. While the choice is up, `comms_advance` presses and releases are consumed and do nothing. When an option is chosen, the channel emits `Events.final_choice_made(StringName(id))`, sets `GameState.final_choice`, hides the control, pops `final_choice`, plays `comms_handover` and plays the option's `next` lines in the same panel. `current_sequence()` returns the `next` id while it plays. When `next` ends, the normal finish runs (queue, panel close, pop `story`) and emits `finished` **once, with the requested id**. No `finished` is emitted for `next`, because nobody requested it.
- `FinalChoice` (`systems/comms/final_choice.tscn` + `.gd`) is a view, like `CommsPanel`. Only the channel calls it. It runs with `PROCESS_MODE_ALWAYS` and is instanced as `Comms/FinalChoice` in `level.tscn`, after `CommsPanel`, and wired to the channel's new `@export var final_choice`. It has two `Button`s, 480 × 120, 48 px apart, centred on x 960, with their top at y 680. Both use `FOCUS_NONE`. Their text is the option `label`, taken as-is from the data. The style follows `RetryPrompt`'s button styling: a `surfaceAlt` fill with a 1 px border, and on hover a `coalition` border and glow. It has no timer. The root and the gap ignore the mouse. Layout numbers live in `ui.final_choice`.
- **Data:** `l3_final_choice` gains `"choice": { "options": [ { "id": "surrender", "label": "OFFER SURRENDER", "next": "l3_isolde_refuse_surrender" }, { "id": "destroy", "label": "DESTROY HER", "next": "l3_isolde_refuse_destroy" } ] }`. `DialogueValidator` checks the block. A `choice` is allowed only in story mode, `options` holds exactly 2 objects, each `id` is `surrender` or `destroy` with no duplicate, each `label` is a non-empty string, and each `next` is a non-empty string.
- **DESPERATE entry:** `core.invulnerable = false`. Start `core.start_desperate()`, which uses `boss.desperate` with start-to-start timing (decisions #38, #50, #52):
  - The radial fires every `radial_interval_s` (1.5). Burst j uses the radial pattern of `radial_bullets` (new key, 12) at `radial_speed_px_s` (300), rotated by `(j mod radial_bursts) × (360 / radial_bullets) / radial_bursts` degrees, so with 2 bursts every other one sits in the gaps of the last.
  - The aimed spread fires every `aimed_interval_s` (2.0): `aimed_bullets` (3) at `aimed_speed_px_s` (400), centred on the core→player direction (`_aim_from`), from −`aimed_spread_deg` (new key, 15) to +`aimed_spread_deg`.
  - The first radial comes 1.5 s in and the first aimed spread 2.0 s in.
  - The core's Glow shows during the last `radial_charge_s` (0.4) of each radial period and the last `aimed_telegraph_s` (0.3) of each aimed period.
  - The core's `Eye` pulses toward red with a steady sine at `boss.desperate.pulse_hz` (new key, 2.0).
  - Each bullet deals `damage.bullet_hearts` and comes from the core centre.
- **DYING:** the core's death in any phase enters `DYING`. Only DESPERATE allows it with valid data.
  - The core's death skips its own impact feedback through a new `Enemy._death_feedback()` hook. `Enemy` keeps `Feedback.impact(tier, global_position)` as the default, and `FlagshipCore` overrides it to do nothing. Everything else in `Enemy._die` still runs: `enemy_killed(&"flagship_core", …)`, no drop, `queue_free`.
  - Entering DYING stops all part attacks and sets `collision_layer = 0` on the hull and on every live part. It calls `Feedback.boss_death(global_position)` once.
  - After `feedback.boss_death_chain_s` (2.0) of game time in DYING, the Flagship logs one INFO line, emits `Events.boss_defeated` exactly once and calls `queue_free()`. Launched Wasps stay.
- **`Feedback.boss_death(pos)`:** plays one explosion per entry of `feedback.boss_death_chain_offsets_px` (new key, 4 entries), each at `pos + offset` with the `boss_death` tier's `explosion_scale` (4.0).
  - The explosions are spread evenly over `boss_death_chain_s`: explosion k plays at k × chain_s / (N − 1). With one entry, it plays at t = 0.
  - Explosion 0 plays inside the call, with the tier's extras (`white_flash`), shake, hit-stop and sfx. Each later one gets only its explosion, with no extras, plus the tier sfx.
  - The pending explosions advance in `step_chain(delta)`, which `_process` calls with game-time `delta` only while the tree isn't paused. `reset()` drops them, and nothing is ever allocated per frame.
- **White flash:** `Explosion` handles the `white_flash` extra. A child full-screen white overlay starts at alpha `feedback.white_flash.alpha` (new, 0.7) and fades linearly to 0 over `feedback.white_flash.duration_s` (new, 0.3, and never more than `LIFETIME_S`). The overlay sits on a CanvasLayer above the HUD and below `Comms`.
- **Audio:** register `explosion_boss_death` in `Audio.SFX` as a placeholder alias of `sfx_explosion_large.wav`, the same way `explosion_boss_part` is set up. Epic 8 replaces it.
- `GameState.final_choice: StringName = &""` is new and is never saved.

**Never:**
- Don't wire the `boss_phase` / `boss_hp_le` triggers. Don't change Level 3 data, `SceneRouter`, the end screen or `l3_isolde_final` (Stories 7.6 and 7.7).
- Don't add a timer to the choice, let the choice skip the response, or let Esc open the pause menu during `final_choice`. `PauseMenu` already blocks that, so don't touch it.
- Never claim feel, readability, fairness or difficulty is verified. That is owed to the operator.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Clamp | CORE, core 60, hit 999 | core 50, alive, invulnerable; `FINAL_CHOICE`; `boss_phase_changed(3)`, `boss_hp_changed(50,300,3)`; `l3_final_choice` requested once | — |
| Exact | CORE, core 55, hit 5 | the same as Clamp | — |
| Above | CORE, core 200, hit 149 | core 51, still CORE | — |
| Wait | FINAL_CHOICE, `finished(&"other")`, 600 steps | still FINAL_CHOICE; no core shots, no launches; core ignores damage | — |
| Choice shown | `l3_final_choice` advanced past line 2 | reasons `story` + `final_choice`; FinalChoice visible with 2 buttons; cue hidden; `finished` not emitted; an advance press or release changes nothing | no `final_choice` view: `Log.error`, finish as a plain story (no event) |
| Pick | press "destroy" | `final_choice_made(&"destroy")` once; `GameState.final_choice == &"destroy"`; `final_choice` popped and `story` still there; panel shows `vale` line 1 of `l3_isolde_refuse_destroy` | unknown `next` id: `Log.error`, finish at once |
| Response ends | advance through both lines | panel closed; no pause reasons; one `finished(&"l3_final_choice")`, no `finished` for `next`; Flagship DESPERATE (`boss_phase_changed(4)`), core vulnerable and targetable | — |
| Desperate cadence | step DESPERATE 6.1 s | radials at 1.5·k (12 bullets; bursts 1, 3 straight down, bursts 2, 4 rotated 15°); aimed spreads at 2.0·k (3 bullets at 400, centre bullet aimed at the player, ±15°); Glow exactly in each window; pulse active | no spawner: nothing fires, one DEBUG line |
| Core dies | DESPERATE, core 50, hit 50 | `enemy_killed(&"flagship_core")`, no core impact explosion; DYING; collision layers 0; `Feedback.boss_death` once: 1 explosion with `white_flash` at once, 20 px shake, hit-stop; at 2.0 s `boss_defeated` once, Flagship freed; 4 explosions in total | — |
| Chain | `boss_death(p)`, step 2.0 s in 1/60 s steps | explosions at 0, 0.667, 1.333, 2.0 s at p + offsets, scale 4; flash only on the first; paused tree: chain frozen; `reset()` drops the rest | no spawner: no explosions, no error |

</intent-contract>

## Code Map

- `game/entities/boss/flagship.gd`:
  - `_on_part_hp_changed`: replace the 7.4 "core destroyed" placeholder (and `_core_destroyed_logged`) with the core-death → `DYING` rule, and FINAL_CHOICE entry on the clamp.
  - `_enter_phase`: add the FINAL_CHOICE, DESPERATE and DYING entries.
  - `step`: add the DESPERATE branch (`core.step`) and the DYING timer.
  - `_ready`: arm the clamp with `core.set_hp_floor(final_choice_hp)` for CORE. Connect to `Events.comms_sequence_finished` and disconnect in `_exit_tree`.
  - Update the class doc.
- `game/entities/boss/flagship_core.gd` / `.tscn` (the existing radial cycle and Glow): add an hp floor in `apply_damage` (override it, or a hook in `FlagshipPart`), `start_desperate()`, the desperate step, the `pulse` accessors, the aimed spread (reuse `FlagshipTurret.spread_velocities` rotated onto the aim) and the `_death_feedback` override.
- `game/core/enemy.gd` `_die` (l.~117): extract `_death_feedback()`.
- `game/autoloads/feedback.gd`: `boss_death`, `step_chain`, the `_process` driver, and the chain cleared in `reset()`. Cache the new keys in `load_tiers()` (F5 re-reads them).
- `game/entities/effects/explosion.gd` / `.tscn`: the `white_flash` extra.
- `game/autoloads/audio.gd:33`: the alias line pattern.
- `game/systems/comms/comms_channel.gd`:
  - `_finish` and `advance`: the choice branch.
  - `_unhandled_input`: consume input while the choice is up.
  - New `is_choosing()` accessor, `final_choice` export, and a choice-parent id for `finished`.
- `game/systems/comms/comms_panel.gd`: add a cue on/off call.
- `game/systems/comms/final_choice.tscn` / `.gd` (new): build it from `game/ui/menus/retry_prompt.gd:170-195` (theme-driven button styles).
- `game/systems/comms/dialogue_validator.gd`: the `choice` rules.
- `game/scenes/level/level.tscn:169-180`: the `Comms` layer nodes.
- `game/autoloads/game_state.gd`: add `final_choice`.
- `game/data/dialogue/level_3.json`, `game/data/tuning.json`:
  - Add `boss.desperate.radial_bullets` 12, `aimed_spread_deg` 15, `pulse_hz` 2.0.
  - Add `feedback.boss_death_chain_offsets_px` `[[0, 124], [-270, 40], [270, 40], [0, 0]]` (the core, then the left and right hull ends, then the hull centre).
  - Add `feedback.white_flash` `{ "alpha": 0.7, "duration_s": 0.3 }`.
  - Add `ui.final_choice` `{ "button_w": 480, "button_h": 120, "button_gap_px": 48, "buttons_top_y": 680, "font_px": <the retry prompt's button font size> }`.
  - Don't use a `*_speed_px_s` suffix for any non-bullet key.
- Tests:
  - `game/tests/unit/test_flagship.gd`: `test_core_killed_before_story_7_5_stays_in_core` (l.765) becomes the clamp test. `test_leaving_core_stops_shots_and_launches_and_keeps_the_wasps` (l.747) still holds. Grep for other `core destroyed` assertions.
  - `test_flagship_level.gd`: the real `dev_boss` level.
  - `test_comms_channel.gd`, `test_comms_panel.gd`, `test_feedback.gd`, `test_explosion.gd`, `test_audio.gd`, `test_game_state.gd`, `test_pause_menu.gd`, the dialogue validator tests.
  - `game/tests/data/test_data_files.gd`: `test_campaign_script_layout` (l.~1214 asserts that `l3_final_choice` has no choice; flip that for `l3_final_choice` only), and the boss tuning tests at l.1538-1640.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_flagship.gd`: cover every Flagship matrix row: Clamp, Exact, Above, Wait, the DESPERATE entry from an emitted `finished(&"l3_final_choice")`, Desperate cadence (6.1 s at 1/60 s), the pulse, the radial rotation, the aimed direction against a player node, the no-spawner case, Core dies, and DESPERATE targeting.
- `game/tests/unit/test_comms_channel.gd` and a new `game/tests/unit/test_final_choice.gd`: cover Choice shown, Pick (both options), Response ends, consumed input, no view, an unknown `next`, a story queued behind a choice that plays after it, and the FinalChoice layout (rects, labels, `FOCUS_NONE`, `PROCESS_MODE_ALWAYS`, mouse filters, the hover style differs from normal).
- `game/tests/unit/test_feedback.gd`, `test_explosion.gd`, `test_audio.gd`, `test_game_state.gd`: cover the Chain row, the `white_flash` alpha at 0 s / half / end, `explosion_boss_death` registered, and the `final_choice` default.
- `game/tests/unit/test_flagship_level.gd`: on the real `level.tscn` with `dev_boss` and F6, kill the turrets and drop the core to 50, then check the real panel, the choice and the pause (`PauseMenu.open()` refuses). Press a button, advance through the response, and check DESPERATE. Kill the core, step 2 s, and check `boss_defeated`, `level_cleared` and that no `[ERROR]` line appeared.
- Validator tests plus `game/tests/data/test_data_files.gd`: the `choice` rules (each invalid shape has one problem). Every `next` is a known story sequence with no `choice` of its own. The shipped block matches the Data bullet. Ranges: `0 < final_choice_hp < boss.core.hp`, `radial_bullets ≥ 1`, `radial_bursts ≥ 1`, `0 ≤ aimed_spread_deg < 90`, `pulse_hz > 0`, 4 chain offsets with N ≥ 1, `0 < white_flash.alpha ≤ 1`, `0 < duration_s ≤ 1.0`. Add the Phase 3 GDD numbers next to Phase 2.
- The source files in the Code Map: implement per the Boundaries.
- `_bmad-output/game-architecture.md`: append `## As-built 2026-10-12 (Story 7.5)` in the style of the 7.4 entry. Point the planned/known-gap notes for Final Choice, `Feedback.boss_death`, `white_flash`, `explosion_boss_death` and the Flagship's 7.4 placeholder at it.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md`: add row 56 (Spec, Story 7.5, "Applied (provisional; operator to confirm)"). It records these readings:
  - the alternating radial rotation and the new `radial_bullets`
  - the aimed spread width
  - the first shots one full period in
  - the shared Glow
  - the pulse rate
  - the 4 chain explosions at scale 4 (this satisfies both readings of "4× chain"), their offsets and timing, with the flash, shake and hit-stop only on the first
  - the white-flash values
  - DYING switching collisions off
  - `finished` emitted only for the requested id
  - the uppercase labels in the data
- `_bmad-output/implementation-artifacts/epic-7-context.md`: change the "Placeholder 7.5 must replace" and open-gap lines to say what was built.

**Acceptance Criteria:**
- Given the Flagship is in Phase 2, when the core's HP drops to ≤ 50, then it is clamped to 50 and invulnerable, the Flagship enters `FINAL_CHOICE`, and `l3_final_choice` is requested.
- Given a sequence with a `choice` block, when the channel finishes its lines, then `FinalChoice` shows instead of `finished`, and `finished` comes only after the chosen `next` completes.
- Given Isolde's lead-in has finished, when the `FinalChoice` control appears, then `final_choice` keeps combat paused, OFFER SURRENDER and DESTROY HER show with no timer, and Esc does not open the pause menu.
- Given the choice is shown, when I click an option, then `final_choice_made` fires, `GameState.final_choice` is set, `final_choice` is popped and the matching response plays (Vale's line, then Isolde).
- Given the response is playing, when it finishes, then the Flagship enters `DESPERATE`: the core is damageable, pulses red, and fires the alternating 1.5 s radials and the 2.0 s aimed spread with their glows inside the periods.
- Given the Flagship is in `DESPERATE`, when the core's HP reaches 0, then the Flagship enters `DYING`, `Feedback.boss_death(pos)` plays the chain (scale 4, 20 px / 1.0 s, 150 ms, one white flash), and then `Events.boss_defeated` fires.
- Given the story is implemented, when the full GUT suite runs headless, then every test passes.

## Spec Change Log

## Review Triage Log

### 2026-10-12 — Review pass
- verdicts: 26 findings — high 0, medium 0, low 19, false 7, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) Decision row 56 calls its readings "silent" in the docs, but item (9) reconciles a stated architecture line and item (10) departs from the architecture's data example. — Reworded the row's opening ("silent on them or leave them open"); item (9) now states that it reconciles the architecture's "finished of the response sequence" with the Story 7.5 AC. The architecture line itself was already updated in the as-built note.
  - `[low]` `[reject]` (blind) `boss_defeated` (Flagship physics clock) and the last chain explosion (Feedback process clock) both land at 2.0 s with no fixed order, and an F5 retune isn't re-read by a live Flagship. — At most one frame apart, and F5 is debug-only; the fix would change the DYING mechanism (end it on the chain's completion), not just correct a line.
  - `[low]` `[reject]` (blind) The player can still die during the 2 s DYING window, from launched Wasps or bullets already in flight. — By design: the player is safe only from `level_cleared` (decision #39), and live launched Wasps stay (F16). The outro is a paused story, so only the chain window is exposed. Added to `operator_actions` for the playtest to judge; any change is a design decision.
  - `[false]` `[reject]` (blind) A click whose id matches no option leaves the game stuck under the `final_choice` pause. — Unreachable: Config leaves out any sequence that fails `DialogueValidator` (exactly 2 object options, valid unique ids), and FinalChoice takes its ids from that same options array, so every click matches.
  - `[false]` `[reject]` (blind) FINAL_CHOICE is inferred from the `invulnerable` flag, so other code could trigger it. — Nothing else sets `invulnerable` while the Flagship is in CORE. The branch also requires `_phase == CORE`, and `_enter_phase(FINAL_CHOICE)` changes the phase first.
  - `[low]` `[patch]` (blind) `set_hp_floor` / the clamp could raise hp when the floor is at or above it (bad data); `_last_hit_by_ally` isn't updated on the clamping hit. — The clamp now sets `hp = mini(hp, _hp_floor)`. The ally flag only matters on a kill, and the clamping hit never kills.
  - `[low]` `[reject]` (blind) The validator has no length cap for choice labels. — The shipped labels are 15 and 11 characters, and the UX sets no cap; a cap would need a new tuning key and rule. Unlikely to come up.
  - `[low]` `[reject]` (blind) The `epic-7-context.md` rewrite dropped facts (Boss-part tier numbers, arrival geometry, turret x positions, the per-attempt ownership note, the Events signal list). — The file was regenerated from the planning docs by the workflow's compile step (the decision log was newer). Every dropped fact is still in the architecture's as-built entries and the GDD, and the file is regenerated whenever the docs change.
  - `[low]` `[reject]` (blind) `test_flagship_phase_3_tuning_ranges` pins exactly 4 offsets and repeats the 1.0 s literal next to `Explosion.LIFETIME_S`. — Follows the spec's task ("4 chain offsets with N >= 1"); the redundancy is harmless, and a retune of the count would update the test along with decision #56.
  - `[low]` `[reject]` (blind) The white flash freezes on screen if a pause starts within its 0.3 s fade. — Brief and cosmetic: it resumes and fades on unpause, and the pause menu draws above it. The fix would need unscaled-time handling.
  - `[low]` `[reject]` (blind) `final_choice.tscn` repeats the layout numbers that `_layout()` overwrites from `ui.final_choice`. — Editor preview only; at runtime the layout comes from the data, the same pattern as the other scenes.
  - `[low]` `[patch]` (blind) `comms_handover` plays before the `next` check, so an unknown `next` plays a speaker-change cue. — Moved the cue to after the check, just before the response's first line.
  - `[false]` `[reject]` (edge) `_on_final_choice_chosen` soft-locks when the clicked id matches no option. — Same refutation as the blind finding: Config drops invalid choice sequences.
  - `[false]` `[reject]` (edge) `show_options` with fewer than 2 options shows a blank clickable button. — Unreachable for the same reason: the validator requires exactly 2 object options.
  - `[false]` `[reject]` (edge) `_start` accepts malformed `options`. — Same: a sequence with an invalid choice never loads through Config.
  - `[low]` `[reject]` (edge) An F3/F6 that frees the Flagship during DYING leaves the chain playing over the restarted wave. — Debug keys only and cosmetic (up to 3 explosions); the fix adds a branch in `_exit_tree`.
  - `[low]` `[reject]` (edge) The player can die after beating the boss, before `level_cleared`. — Same as the blind DYING-window finding; by design (#39, F16), passed to the operator.
  - `[low]` `[reject]` (edge) `boss_defeated` and the chain's end can diverge after an F5 or a reset. — Same as the blind two-clocks finding.
  - `[low]` `[reject]` (edge) The epic-context rewrite removed facts that 7.6-7.8 rely on. — Same as the blind finding.
  - `[low]` `[patch]` (verification-gap) The bad-data fallbacks of the boss-death chain (empty or malformed offsets) are untested. — Added `test_no_chain_offsets_plays_one_impact_at_pos` and `test_malformed_chain_offsets_are_skipped` to `test_feedback.gd`.
  - `[low]` `[reject]` (verification-gap, other) A pending chain survives F6. — Same as the edge F3/F6 finding: debug-only and cosmetic.
  - `[false]` `[reject]` (intent) The diff doesn't set `status: awaiting-operator` / `operator_actions`. — That is finalization, applied below (frontmatter and Auto Run Result).
  - `[false]` `[reject]` (intent) "Esc does not open the pause menu" is checked through `menu.open()`, not a keypress. — `test_pause_menu.gd` `test_final_choice_blocks_the_menu` sends a real Esc event (`_esc`) with the `final_choice` reason active; the level test adds the direct check.
  - `[low]` `[reject]` (intent) The pulse, glows, flash and chain are tested through internal state, not on screen. — By design: feel and readability are owed to the operator (see `operator_actions`).
  - `[low]` `[reject]` (intent) The level test drives combat with `step` / `apply_damage` instead of player shots. — An accepted test seam (as in Story 7.4); the comms half uses real mouse input.
  - `[low]` `[reject]` (intent) The `epic-7-context.md` change goes beyond the Code Map's two lines. — Same as the blind epic-context finding: the workflow recompiled the file before planning.

## Design Notes

**Why `finished` carries only the requested id:** the WaveDirector and the Flagship wait on the id they requested, and the channel contract is "every requested known sequence finishes exactly once". `next` is the channel's own continuation, not a request.

**Clamp placement:** `Enemy.apply_damage` kills on `hp <= 0` before any `hp_changed` listener runs, so the floor has to live in the core's damage path, not in the Flagship's listener:

```gdscript
func apply_damage(amount: int, source: Node) -> void:
	if not invulnerable and not _dead and _hp_floor > 0 and hp - amount <= _hp_floor:
		hp = _hp_floor
		_hp_floor = 0
		invulnerable = true
		hp_changed.emit(hp)
		return
	super(amount, source)
```

**Choice and the click:** each `Button` fires `pressed` on release and the GUI consumes the click, so `_unhandled_input` never sees it. Line 0 of the response therefore needs a fresh press and release, the same as every other story line.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import`: expected to complete (new `class_name FinalChoice`).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`: expected to pass with 0 failures.

**Manual checks (if no CLI):**
- Operator: `"<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game res://scenes/level/level.tscn -- --level=dev_boss`, then press F6. Destroy the turrets, take the core to 50, pick an option, survive the barrage and kill the core.

## Auto Run Result

Status: awaiting-operator

**Summary:** The Flagship's Phase 3, the Final Choice and the boss death are built.
- **Clamp and choice:** in Phase 2, the first core hit that would reach 50 HP or below clamps the core to exactly 50 and makes it invulnerable (F7). The Flagship enters `FINAL_CHOICE` (no more core shots or launches; live Wasps stay) and requests `l3_final_choice`.
- **The choice flow:** after Isolde's lead-in, `CommsChannel` keeps the panel open with the cue hidden, pushes `final_choice` and shows the new `FinalChoice` control (OFFER SURRENDER / DESTROY HER, 480 x 120, top y 680, no timer; Esc blocked by the pause menu). A click emits `final_choice_made`, sets `GameState.final_choice`, pops `final_choice` and plays the matching response (Vale, then Isolde). Then `finished(l3_final_choice)` fires once.
- **Desperate phase:** the Flagship enters `DESPERATE`. The core is damageable and pulses red. It fires a 12-bullet radial every 1.5 s, every other one turned 15 degrees, and an aimed 3-bullet spread at 400 px/s every 2.0 s, with the glows inside the periods.
- **Boss death:** the core's death enters `DYING`, switches collisions off and plays `Feedback.boss_death`: 4 explosions at scale 4 over 2 s, with the white flash, 20 px shake and 150 ms hit-stop on the first. Then `boss_defeated` fires once and the Flagship frees itself.

**Files changed:**
- `game/entities/boss/flagship.gd`: the FINAL_CHOICE, DESPERATE and DYING phases, waiting for `finished`, the death timer.
- `game/entities/boss/flagship_core.gd`: the hp floor (clamp), the desperate cycles, the red pulse, no impact of its own on death.
- `game/entities/boss/flagship_turret.gd`: `stop_firing()`.
- `game/core/enemy.gd`: the `_death_feedback()` hook.
- `game/autoloads/feedback.gd`: `boss_death`, `step_chain`, `chain_pending`; `reset()` drops the chain; prewarm skips the white flash.
- `game/autoloads/audio.gd`: the `explosion_boss_death` placeholder alias.
- `game/autoloads/game_state.gd`: `final_choice`.
- `game/entities/effects/explosion.gd` / `.tscn`: the `white_flash` extra (a full-screen overlay on layer 15).
- `game/systems/comms/comms_channel.gd`: the choice flow.
- `game/systems/comms/comms_panel.gd`: cue on/off.
- `game/systems/comms/dialogue_validator.gd`: the `choice` rules.
- `game/systems/comms/final_choice.gd` / `.tscn` (new): the two-button view.
- `game/scenes/level/level.tscn`: `Comms/FinalChoice` wired to the channel.
- `game/ui/theme/defector_theme.tres`: the `FinalChoice` theme items.
- `game/data/dialogue/level_3.json`: the `choice` block.
- `game/data/tuning.json`: `boss.desperate.radial_bullets` / `aimed_spread_deg` / `pulse_hz`, `feedback.boss_death_chain_offsets_px`, `feedback.white_flash`, `ui.final_choice`.
- Tests:
  - new: `test_final_choice.gd`
  - updated: `test_flagship.gd`, `test_flagship_level.gd`, `test_comms_channel.gd`, `test_comms_panel.gd`, `test_dialogue_validator.gd`, `test_feedback.gd`, `test_explosion.gd`, `test_audio.gd`, `test_game_state.gd`, `tests/data/test_data_files.gd`, `tests/fixtures/dialogue/channel/channel.json`
- Docs:
  - `game-architecture.md`: As-built Story 7.5, with the planned and known-gap notes pointing to it.
  - `decision-log.md`: row 56 (provisional; operator to confirm).
  - `epic-7-context.md`: recompiled because the decision log was newer, then updated.

**Review findings:** 26 findings (high 0, medium 0, low 19, false 7).
- **Patched (4, all low):** the row-56 wording, the clamp's `mini`, the handover cue order, and the two bad-data chain tests.
- **Deferred:** none.
- **Rejected:** each one with its reason in the Review Triage Log.
  - the two-clock timing (x2)
  - the DYING-window vulnerability (x2): by design, passed to the operator
  - unreachable no-match soft-locks (x4 false): Config drops invalid choices
  - the `invulnerable` inference (false)
  - no label cap
  - the epic-context condensation (x3)
  - the pinned offset count
  - the flash frozen under pause
  - the `.tscn` preview numbers
  - the chain surviving F3/F6 (x2): debug only
  - the awaiting-operator bookkeeping (false): applied here
  - Esc via the method (false): a real Esc test exists
  - internal-state checks and the step-driven level test (x2): accepted seams

**Follow-up review recommended:** false. Patched: high 0, medium 0, low 4.

**Verification:**
- `--headless --path game --import`: OK.
- Full GUT suite headless: 91 scripts, 1786/1786 tests passing (20246 asserts) after the patches. Before the patches: 1783 passing plus 1 pre-existing timing-guarded pending (`test_hit_stop_overlap_keeps_longest`).
- Matrix test audit: every I/O row has a covering test that ran and passed.
- The diff was scanned for secrets, personal paths and work identities before committing.

**Residual risks:**
- Feel, readability, fairness, difficulty and the comfort of the white flash are not verified. They are owed to the operator (see `operator_actions`).
- The provisional readings in decision #56 await operator confirmation.
- The player can die during the 2 s boss-death chain, from leftover launched Wasps or bullets (#39, F16); the operator should judge it.
- The `boss_defeated` emission and the last chain explosion run on separate clocks, so they can land up to a frame apart. F3 or F6 during DYING leaves the chain playing (debug only).
- The real-level test waits about 2.8 s of real time for the chain, so it may be slow on a loaded machine.
