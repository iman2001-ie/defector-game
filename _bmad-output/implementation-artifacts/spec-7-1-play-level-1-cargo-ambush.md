---
title: 'Story 7.1: Play Level 1: Cargo Ambush'
type: 'feature'
created: '2026-10-11'
status: 'awaiting-operator'
operator_actions:
  - 'Play Level 1 from the title in a debug build ("<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game) with the F1 overlay on, from wave 1 to the clear, and confirm that no wave soft-locks and that the level takes about 3-4 minutes plus dialogue.'
  - 'During that run, confirm the control hints read clearly (W1 move then hold LMB, W2 RMB missile, E/Q when energy first reaches 50/100) and that a first-time player would understand the controls by wave 2 without verbal help.'
  - 'Judge whether wave 1 reads as the calm "slow formation" the GDD asks for; if it does not, raise a design change (a per-wave Wasp speed does not exist yet) rather than editing code silently.'
  - 'Judge whether the convoy (100 HP) survives real play against the 3 + 4 Mauls and the Lancer fire; if it is too fragile or too safe, retune in game/data/tuning.json (never code) and record the change in the GDD decision log.'
  - 'Confirm the ambush (Tarek warning at W3 start, Isolde at 25 % of W3), the W5 surrender pause and the Maul reinforcements, and Tarek''s closing line on clear land as beats.'
baseline_revision: 'e2128e832164cdfe6eff234a3c90a8f038a8ab46'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-7-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
warnings: ['oversized']
deferred:
  - summary: >-
      Whether the Level 1 convoy (100 HP) survives real play against 7 Mauls and Lancer fire is unverified; the integration test raises its HP to 100000.
    evidence: |-
      Maybe-false: 3 + 4 Mauls at 10 damage each is 70, and Lancers aim at the convoy 50 % of the time for 5 per hit, so a slow player could lose the convoy. Settled by the operator playtest in operator_actions (watch convoy HP per GDD decision #23); a retune belongs in tuning.json.
    location: >-
      game/data/levels/level_1.json
    severity: medium (unverified)
  - summary: >-
      The level-root "music" key is still unread, so Level 1 states "combat" twice (the root key and a W1 music action) and nothing owns wiring the root key.
    evidence: |-
      Pre-existing since Story 5.3 (architecture As-built 5.3: "Story 8.1 or Epic 7 can wire it"). Stories 7.2 and 7.6 will copy the duplicated pattern, and a later edit to one copy can silently disagree with the other. Wiring it is a WaveDirector change, which is outside this data-only story.
    location: >-
      game/systems/waves/wave_director.gd
    severity: low
---

<intent-contract>

## Intent

**Problem:** `game/data/levels/level_1.json` is still the Story 4.1 placeholder (2 Wasp-only waves, no convoy, no ally, no beats). The first campaign level must teach the controls, then spring the convoy ambush with its comms beats (FR46, FR44 L1, FR42, FR43, FR66, NFR8).

**Approach:** Replace `level_1.json` with the GDD Level 1 data: convoy on, Tarek flying, five waves with the exact GDD counts, the hint, music and comms triggers, the flag-paired surrender + Maul reinforcements, and `l1_tarek_closing` as the outro. Every mechanic already exists (Epics 2–6). This is a data change plus tests: rewrite the data-test guards that pinned the placeholder, add a level-1 shape test, and add a real-`level.tscn` integration test that plays Level 1 to the clear with the flags on and off.

## Boundaries & Constraints

**Always:**
- Root keys stay exactly the `level_dev` key set: `id` 1, `name` "Cargo Ambush", `background` "space_1", `music` "combat", `convoy` true, `ally` "tarek", `intro_sequence` null (the opening story is L1's intro), `outro_sequence` "l1_tarek_closing".
- The level-root `music` key is not read (architecture, As-built 5.3), so W1's `wave_start` trigger also runs `{ "music": "combat" }` before its hint.
- Lancers are each wave's first entry (row 0, y 160), because their strafe zone ends at y 378 (`enemies.lancer.zone_height_ratio` 0.35) and a lower slot is clamped with a WARN. Wasps take the next rows (no lower than y 400, inside their 0.4 zone). Mauls are rowless.
- The `l1_w3_tarek_warning` line is an ally warning and has no flag. The Isolde interruption is gated by `isolde_interruptions`. The surrender prompt is gated by `surrender_prompts` and paired with a `!surrender_prompts` trigger, so the 4 Mauls arrive either way.
- The level must pass `LevelValidator` (the existing `test_every_level_file_is_valid`).
- Statically typed GUT tests that follow the `test_isolde_beats.gd` fixture pattern. Write the failing tests first.

**Never:**
- No engine code change: no WaveDirector, Level, HUD, Audio or Comms edit. If the data can't express a beat, HALT. Don't add code.
- Don't edit `level_2.json`, `level_3.json` or any dialogue (Stories 7.2 and 7.6 own them). No background rendering and no level-select thumbnail (Epic 8 art). No tuning change.
- Never claim feel, pacing, the 3–4 minute length or control comprehension as verified. Those are owed to the operator.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Level start | `level_1` loads | 1 Convoy and 1 Tarek `AllyShip` in `World/Allies`; W1 has 8 counted; `hint_requested(&"move_fire")` | — |
| W2 start | W1 cleared | `hint_requested(&"missile")`; 10 counted; 3 small + 1 medium asteroid spawned | — |
| W3 start | W2 cleared | 17 counted; `l1_w3_tarek_warning` requested before any W3 kill; no pause | — |
| W3 25 % | resolved/17 ≥ 0.25, flag on | `l1_w3_isolde_interrupt` requested; no pause | flag off: never requested |
| W4 | W3 cleared | 14 counted (10 Wasps, 4 Lancers) | — |
| W5 30 % | resolved/23 ≥ 0.30, `surrender_prompts` on | `l1_w5_surrender` shows, tree paused, no Maul yet; after the click-through: unpaused, 4 Mauls | flag off: no surrender and no pause; 4 Mauls arrive at 0.30 |
| Clear | W5 cleared | `l1_tarek_closing` (story) shows, then `level_cleared(1)` once → router loads level 2 | — |
| Energy hints | energy reaches 50 / 100 on L1 | the HintPill shows or queues `shield` / `barrage` | — |

</intent-contract>

## Code Map

- `game/data/levels/level_1.json` -- REPLACE. Target content is in Design Notes.
- `game/data/levels/level_dev_isolde.json` -- golden pattern for the W3 interrupt and the W5 surrender pair (`groups.reinforcements` plus the two `progress` 0.30 triggers). Read-only.
- `game/data/levels/level_dev_convoy.json`, `level_dev_hints.json` -- the Maul/Lancer entry shapes (`entry: sides`, Lancers listed first) and the `hint` actions. Read-only.
- `game/data/dialogue/level_1.json` -- the 4 L1 sequences: `l1_w3_tarek_warning` (combat), `l1_w3_isolde_interrupt` (combat), `l1_w5_surrender` (story), `l1_tarek_closing` (story, 2 lines). Read-only.
- `game/systems/waves/level_validator.gd` -- the rules the data must meet (MUSIC_ACTIONS, HINT_ACTIONS, one request per group, the flag/!flag pair is allowed, reachability). Read-only.
- `game/scenes/level/level.gd` -- spawns the convoy (`has_convoy`) and the ally (`ally_id`) before `WaveDirector.start_level`; `level_cleared` → `SceneRouter.complete_level`. Read-only.
- `game/ui/hud/hint_pill.gd` -- raises `shield` / `barrage` from `Events.energy_changed`; `showing_hint()`, `queued()`; once per session through `GameState.shown_hints`. Read-only.
- `game/tests/data/test_data_files.gd` -- guards that pin the placeholder and must change: `test_placeholder_levels_have_their_names_and_wasp_waves` (l.53; asserts convoy false, 1–2 Wasp-only waves, no groups for all 3 levels), `test_mauls_only_in_dev_levels` (l.1184), `test_convoy_is_a_bool_and_only_on_in_dev_levels` (l.1203), `test_ally_off_in_dev_and_campaign_levels` (l.1250).
- `game/tests/unit/test_isolde_beats.gd` -- fixture to copy: `_load_flags_with(flag, value)` (temp flags file + `Config.load_data`), `_make_level()` (gap_s 0.05, `user_args` empty, `debug_invincible`, no-op `warp_mouse`), `_kill_one_counted`, `_kill_through_wave`, `_kill_to_ratio`, `_click_through` (`channel.advance()`), and the comms-request recorder.
- `game/tests/unit/test_level.gd` l.218 -- `SceneRouter.change_scene = _record_scene`, the test `SaveManager.save_path`, restore in `after_each`. `test_control_hints.gd` resets `GameState.shown_hints`.
- `_bmad-output/game-architecture.md` -- append `## As-built 2026-10-11 (Story 7.1)` after the DW-83 entry, in the style of the 6.4 and 6.5 entries.

## Tasks & Acceptance

**Execution:**
- `game/tests/data/test_data_files.gd` -- Add `test_level_1_cargo_ambush_shape`. It asserts the root values and, per wave, the counted totals by type (spawns plus groups), W2's asteroids, the exact `reinforcements` group, and the exact trigger list of each wave (the W5 pair: both triggers at 0.30, one flagged `surrender_prompts` with `[comms, spawn_group]`, one `!surrender_prompts` with `[spawn_group]`). Narrow the placeholder test to levels 2 and 3 (keep the name check for all 3). Allow `level_1` in the Maul and convoy guards (assert levels 2 and 3 still have neither). Assert the ally is `tarek` for level 1 and null for 2 and 3. Update the doc comments. -- These pin the GDD numbers and keep the epic guards honest.
- `game/tests/unit/test_level_1.gd` -- NEW. Integration on the real `level.tscn` with `level_id` "1". In setup, raise `Config.tuning.convoy.hp` (for example to 100000) before the level spawns so stray hits can't fail the run, use a test save and a router recorder, reset `GameState` including `shown_hints`, and capture the Log. Cover the matrix: (a) shipped flags, kill through all 5 waves and assert every row, the comms request order `[tarek_warning, isolde_interrupt, surrender, tarek_closing]`, `level_cleared` == [1], the router called once with the level scene and `current_level_id` "2", and no `[WARN][spawn]`, `stalled` or `[ERROR][wave]` lines; (b) both flags off, the requests are `[tarek_warning, tarek_closing]`, the 4 Mauls spawn at 0.30 of W5 with no pause, and the level clears; (c) energy hints on L1. Ally kills shift ratios, so never assert exact kill counts. -- These observe the outermost surface the ACs name (playing the level).
- `game/data/levels/level_1.json` -- Replace with the Design Notes content. -- The story's deliverable.
- `_bmad-output/game-architecture.md` -- Append the Story 7.1 as-built entry. Record-only readings: "slow formation" is the plain `grid_4x2` of the architecture's own Level 1 example (no per-entry speed exists); W1 also starts the music; Lancers come first. List the files and tests, and the playtest owed. -- This is the project's convention.

**Acceptance Criteria:**
- Given the shipped flags, when Level 1 is played on the real `level.tscn` by killing counted enemies, then the hints, comms lines, surrender pause, Mauls, outro and clear happen in the order the matrix lists, and the level clears exactly once to level 2.
- Given `surrender_prompts` and `isolde_interruptions` both false, when Level 1 is played, then neither Isolde line is requested, the 4 Mauls still arrive in W5 with no pause, and the level clears.
- Given every shipped level file, when the GUT suite runs, then `LevelValidator` reports no problems and the full suite passes headless.

## Spec Change Log

## Review Triage Log

### 2026-10-11 — Review pass
- verdicts: 17 findings — high 0, medium 0, low 12, false 2, maybe-false 3
- findings:
  - `[low]` `[patch]` (blind) The as-built entry filed "slow formation" under "the docs are silent", though the architecture's own Level 1 example settles it. — Reworded the as-built entry to cite the architecture example (plain `grid_4x2`, no per-entry speed exists) and moved the "calm" judgement to the operator playtest (operator_actions).
  - `[low]` `[patch]` (blind) The W1 fire hint and the W2 missile hint were only shown as requested, never as reaching the HintPill. — Added asserts that `fire` is queued at level start and `missile` is queued or showing at W2 start.
  - `[low]` `[patch]` (blind) Isolde's interruption was only shown as requested, never as reaching the channel. — Added an assert after wave 3 that it is playing or queued in CommsChannel.
  - `[low]` `[patch]` (blind) The energy-hint test reached 100 only through the cap, and its order check was conditional. — The second step now lands exactly on the barrage cost, and both hints plus their order are asserted unconditionally.
  - `[maybe-false]` `[defer]` (blind) Convoy survival at 100 HP is untested; the test raises HP to 100000. — Settled by the operator playtest; deferred as medium (unverified).
  - `[false]` `[reject]` (blind) No retry path is tested on Level 1. — Retry is data-independent and already covered by `test_level.gd` (`test_death_and_retry_reload_a_clean_level`, `test_convoy_loss_runs_the_retry_flow`) and `test_control_hints.gd` (`test_a_retry_reload_shows_neither_hint_again`). Level 1's data changes none of it.
  - `[low]` `[reject]` (blind) The guards hard-code `level_1.json` and `"1"`, so 7.2 and 7.6 must edit several lines. — The cost is a few one-line edits that those stories must make anyway; the suggested fix is a structural refactor.
  - `[low]` `[patch]` (blind) `_kill_through_wave` and `_kill_until_outro` timed out silently, hiding a soft-lock's real cause. — Each now asserts its exit condition with the wave and resolved/total counts.
  - `[low]` `[defer]` (blind) Level music is defined twice (root key plus the W1 action) and nobody owns wiring the root key. — Pre-existing since Story 5.3; the fix is WaveDirector code, outside this story. Deferred.
  - `[low]` `[reject]` (edge) An F5 flag reload after W5 passes 0.30 lets the other trigger of the surrender pair fire (a late surrender or a WARN'd second spawn). — Debug-only (F5) and pre-existing for every flag/!flag pair the architecture prescribes. A guard would need engine changes.
  - `[low]` `[patch]` (edge) The test's comms listener records `paused` before CommsChannel acts, so the "requested without a pause" asserts can never fail. — Dropped the field and both vacuous asserts; after wave 3 the test now checks that the tree is unpaused and no story reason is held.
  - `[low]` `[patch]` (verification-gap, other) Same defect as above: the `paused` field is always false. — Grouped with the previous row; same fix.
  - `[false]` `[reject]` (intent) The AC4 playtest is owed only in architecture prose, not in `operator_actions`. — Finalization records it: the spec ends `awaiting-operator` with a non-empty `operator_actions` list (the Story 6.4 precedent).
  - `[maybe-false]` `[defer]` (intent) "Completable" is shown only in a harness where losing is impossible (invincible player, 100000 HP convoy). — Same root cause as the convoy-survival row; deferred there and owed to the operator playtest.
  - `[low]` `[patch]` (intent) The W1 fire hint is not checked. — Grouped with the hints row; same fix.
  - `[low]` `[patch]` (intent) The E/Q hints were checked only as "queued or showing" via direct energy adds. — Grouped with the energy-hint row; same fix.
  - `[maybe-false]` `[patch]` (intent) "Slow formation" is not implemented, only recorded as a reading. — The architecture's Level 1 example defines W1 as plain `grid_4x2`, so there is one contract reading. Grouped with the as-built wording row; whether it feels calm is an operator action.

## Design Notes

Target `level_1.json` waves (flags and order matter; formatting follows the other level files):

```
W1 spawns: wasp 8 grid_4x2 top | wave_start: [music combat, hint move_fire]
W2 spawns: wasp 10 grid_5x2 top | asteroids: small 3, medium 1 | wave_start: [hint missile]
W3 spawns: lancer 2 grid_2x1 sides, wasp 12 grid_6x2 top, maul 3 grid_3x1 sides
   wave_start: [comms l1_w3_tarek_warning] ; progress 0.25 flag isolde_interruptions: [comms l1_w3_isolde_interrupt]
W4 spawns: lancer 4 grid_4x1 sides, wasp 10 grid_5x2 top | triggers: []
W5 spawns: lancer 3 grid_3x1 sides, wasp 16 grid_8x2 top
   groups.reinforcements: maul 4 grid_4x1 sides
   progress 0.30 flag surrender_prompts: [comms l1_w5_surrender, spawn_group reinforcements]
   progress 0.30 flag !surrender_prompts: [spawn_group reinforcements]
```

W4 needs no data for the E/Q hints because the HintPill raises them from energy. If Stories 3.3–3.5 are cut, those hints don't show.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits cleanly (run it first; the new test file has no `class_name`, but re-run it if the cache is stale).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failing (`<GODOT_DIR>` from `LOCAL.md`).

**Manual checks (operator):**
- Play Level 1 from the title in a debug build with the F1 overlay: no wave soft-locks, the level takes about 3–4 minutes plus dialogue, the hints read clearly, and the ambush, the surrender pause and the Maul reinforcements land as beats.

## Auto Run Result

Status: awaiting-operator

**Summary:** Story 7.1 is built as data plus tests. `game/data/levels/level_1.json` is now the GDD's Cargo Ambush: convoy on, Tarek flying, no intro (the opening story is Level 1's intro) and `l1_tarek_closing` as the outro. The five waves have the exact GDD counts (8, 10, 17, 14 and 23 counted, the 4 reinforcement Mauls included). W1 starts the combat music and the move/fire hint, W2 shows the missile hint and brings 3 small + 1 medium asteroids, W3 plays Tarek's ambush warning at the start and Isolde's flag-gated line at 25 %, and W5 has the flag-paired surrender at 30 %, so the 4 Mauls arrive with either flag state. The E/Q hints come from the existing HintPill. No engine code, dialogue, tuning or `level_2/3.json` changed. The playtest-only parts of the ACs (the 3-4 minute length, a full F1 run with no soft-lock, readability, convoy balance, how the beats feel) need a human, so they are owed under `operator_actions`.

**Files changed:**
- `game/data/levels/level_1.json`: replaced the Story 4.1 placeholder with the GDD Level 1 data.
- `game/tests/data/test_data_files.gd`: new `test_level_1_cargo_ambush_shape`. The placeholder, Maul, convoy and ally guards are narrowed to levels 2 and 3 and allow level 1.
- `game/tests/unit/test_level_1.gd` (+ `.gd.uid`): new integration test that plays the real `level.tscn` on level 1 to the clear, with the shipped flags and with both Isolde flags off, plus the energy hints.
- `_bmad-output/game-architecture.md`: new `As-built 2026-10-11 (Story 7.1)` entry.
- `_bmad-output/implementation-artifacts/epic-7-context.md`: compiled Epic 7 planning context (new).

**Review findings:** 17 findings: 0 high, 0 medium, 12 low, 2 false, 3 maybe-false.
- **Patched (9 rows, 6 fixes, all low or maybe-false):** dropped the vacuous pause asserts and added post-wave pause checks; asserted Isolde's line reaches the channel; asserted the fire and missile hints reach the HintPill; made the energy-hint test exact and unconditional; made the kill helpers assert their exit condition; reworded the "slow formation" reading in the as-built entry.
- **Deferred (3 rows, 2 items):** convoy survival at 100 HP (medium, unverified; owed to the playtest); the unread level-root `music` key (low, pre-existing since Story 5.3).
- **Rejected:** no Level 1 retry test (false: retry is data-independent and covered in `test_level.gd` and `test_control_hints.gd`); hard-coded level names in the guards (low; the fix is a refactor and later stories edit those lines anyway); the F5 reload re-firing the other trigger of the paired surrender (low, debug-only, pre-existing for every flag pair); the AC4 obligation living only in prose (false: recorded in `operator_actions` at finalization).

**Follow-up review recommendation:** false. 0 high, 0 medium and 6 low/maybe-false fixes were patched, so there is no named unverified risk that another pass would settle.

**Verification:**
- `--headless --path game --import` exited 0.
- Full GUT run before review: 86 scripts, 1648 tests, 1648 passing.
- Full GUT run after the patches: 1648 tests, 1647 passing, 0 failing, 1 pending. The pending test is `test_feedback.gd::test_hit_stop_overlap_keeps_longest`, which skips itself when a timer fires too late under load. Rerun alone, `test_feedback.gd` passed 27/27. The three `test_level_1.gd` tests and the new data tests ran and passed. All 8 rows of the scenario table are covered by passing tests.

**Residual risks:** the tests run with an invincible player and a 100000 HP convoy, so whether Level 1 can actually be won at 100 convoy HP is unproven until the playtest. W1's "slow formation" is the plain `grid_4x2` that the architecture prescribes; if it doesn't feel calm, that needs a design change. With real timing, Isolde's 25 % line queues behind Tarek's 5 s warning; whether that reads well is part of the playtest.
