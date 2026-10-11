---
title: 'Story 7.2: Play Level 2: The Blockade'
type: 'feature'
created: '2026-10-11'
status: 'awaiting-operator'
operator_actions:
  - 'Play Level 2 from the title in a debug build ("<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game) with the F1 overlay on, from the briefing to the clear, and confirm that no wave soft-locks and that the level takes about 3-4 minutes plus dialogue.'
  - 'During that run, judge whether the asteroids give usable cover against the Needles, and whether in wave 5 the Bastions (row y 250, same columns as the Needles at y 160) hide the Needles too much; if so, raise a layout or design change rather than editing code silently.'
  - 'Confirm Tarek''s fall at 50 % of wave 5 lands as the beat: the shield glide, the line cut mid-word, the static, shake and music stop, the fire trail and the exit, then Ryn''s report after the clear. Watch for the cut-off being delayed behind another combat line.'
  - 'Play Level 1 again and judge whether the tighter 90 px formation rows still read well, and whether missiles are now too strong against formations (a hit on a back-row Wasp now usually also splash-kills the Wasp in front of it); any retune goes in game/data/tuning.json with a GDD decision-log entry.'
baseline_revision: '14c37d78931468dfd9dbaa2439897746f6f64a9c'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-7-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
warnings: ['oversized']
deferred:
  - summary: >-
      Level 2 wave 5 puts the 160 px Bastions (row y 250) in the same columns as the Needles (y 160), so each Needle can start shielded from below; Bastions in waves 2 and 4 also overlap the next Wasp row by about 22 px.
    evidence: |-
      Maybe-false: both entries are grid_2x1 from the top, so they share x slots, and the Bastion hull spans y 170-330 against the Needle's 120-200. Whether this hurts play depends on the Bastion drift and the Needle reposition (every 8 s), so it is settled by the operator playtest in operator_actions; a fix would be a layout change in level_2.json.
    location: >-
      game/data/levels/level_2.json
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** `game/data/levels/level_2.json` is still the Story 4.1 placeholder (2 Wasp-only waves, no ally, no beats). The middle campaign level must teach Needles, Bastions and cover, and end with Tarek's fall and Ryn's report (FR47, FR44 L2, FR35, FR42). With the current 120 px formation rows, the GDD's W5 can't fit its enemy zones, so decision #53 tightens the rows to 90 px.

**Approach:** Set `waves.formation.spacing_px.y` to 90 in `tuning.json` (decision #53). Replace `level_2.json` with the GDD Level 2 data: Tarek flying, the `l2_briefing` intro, five waves with the exact GDD counts and asteroids, the W3 Isolde interruption, the flag-gated W5 fall plus cut-off at 50 %, and `l2_ryn_report` as the outro. Every mechanic already exists (Epics 2–6), so this is data plus tests: narrow the placeholder guards to level 3, add a level-2 shape test, and add a real-`level.tscn` integration test that plays Level 2 to the clear with `tarek_fall` on and off.

## Boundaries & Constraints

**Always:**
- Root keys are exactly the `level_dev` key set: `id` 2, `name` "The Blockade", `background` "space_2", `music` "combat", `convoy` false, `ally` "tarek", `intro_sequence` "l2_briefing", `outro_sequence` "l2_ryn_report" (decision #53 reading 3).
- W1's `wave_start` runs `{ "music": "combat" }`, because the level-root `music` key isn't read (As-built 5.3; decision #53 reading 2).
- Entry order follows decision #53 and DW-68: a Needle entry is the first row-taking entry of its wave. Rows at 90 px are y 160 / 250 / 340 / 430. W5 is Needles (y 160), Bastions (y 250), Lancers (y 340). No slot may clamp: `test_zoned_formations_fit_their_top_zone` must pass for every level file, with no exemption.
- The W3 interruption is `progress` 0.25 gated by `isolde_interruptions` (reading 1). The W5 fall is one `progress` 0.5 trigger gated by `tarek_fall` with actions `[story_event tarek_fall, comms l2_w5_tarek_cutoff]`, copied from `level_dev_tarek_fall.json`, and it has no `!tarek_fall` pair (reading 4).
- Every Needle wave has at least 2 medium or large asteroids. The level must pass `LevelValidator`. There are at most 2 interruptions, and the cut-off is excluded from that count.
- Statically typed GUT tests that follow the `test_level_1.gd` fixture. Write the failing tests first.

**Never:**
- No engine code change: no WaveDirector, Level, AllyShip, Comms, HUD or Audio edit. If the data can't express a beat, HALT. Don't add code.
- Don't edit `level_1.json`, `level_3.json`, any dialogue file or any tuning value other than `waves.formation.spacing_px.y`. No background art and no level-select thumbnail (Epic 8).
- Never claim feel, pacing, the 3–4 minute length, cover usefulness or the emotional beat as verified. Those are owed to the operator.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Level start (fresh) | `level_2` loads, not a retry | 1 Tarek `AllyShip`, no Convoy; `l2_briefing` shows paused in the story panel (TAREK) before wave 1; after the click-through, W1 starts with 8 counted and the combat music | — |
| W1–W4 | each wave cleared in turn | counted by type: W1 needle 2 + wasp 6; W2 bastion 1 + wasp 8; W3 needle 3 + lancer 3; W4 bastion 2 + wasp 10. Asteroids: W1 2 medium + 1 large, W3 2 medium, W4 1 large | — |
| W3 25 % | resolved/6 ≥ 0.25, flag on | `l2_w3_isolde_interrupt` requested, no pause | flag off: never requested |
| W5 50 %, `tarek_fall` on | resolved/8 crosses 0.5 | `story_event tarek_fall` logged and `l2_w5_tarek_cutoff` requested at the same crossing; no pause; Tarek leaves the fight; comms silenced until W5 clears | — |
| W5 50 %, `tarek_fall` off | resolved/8 passes 0.5 | no story event, no cut-off line; Tarek still `PATROL` and not damaged | — |
| Clear | W5 cleared (either flag state) | `l2_ryn_report` (story, RYN) shows paused before the clear; after the click-through `level_cleared(2)` fires once and the router loads the level scene with `current_level_id` "3" | — |
| Formation rows | every level file at `spacing_px.y` 90 | no `[WARN][spawn]` clamp in play; zone data test passes | — |

</intent-contract>

## Code Map

- `game/data/tuning.json` l.222 -- `waves.formation.spacing_px` `{x 160, y 120}`. Change only `y` to 90.
- `game/data/levels/level_2.json` -- REPLACE. The target content is in Design Notes.
- `game/data/levels/level_1.json`, `level_dev_tarek_fall.json` -- golden patterns for the W1 music action, the gated interrupt and the fall trigger. Read-only.
- `game/data/dialogue/level_2.json` -- `l2_briefing` (story, 3 Tarek lines), `l2_w3_isolde_interrupt` (combat), `l2_w5_tarek_cutoff` (combat, `cut_off_at` 40, `after` silence/shake/static/music stop) and `l2_ryn_report` (story, 3 Ryn lines). Read-only.
- `game/systems/waves/wave_director.gd` -- `start_level` plays the intro (story intro holds wave 1, skipped on retry); `_finish_level` (l.~598) plays the outro and then `level_cleared`. `wave_number()`, `resolved_count()`, `total_count()`, `is_level_cleared()`. Read-only.
- `game/systems/comms/comms_channel.gd` -- `current_sequence()`, `current_combat()`, `combat_queued()`, `cut_phase()`, `is_silenced()`, `advance()`. Silence drops only combat sequences, so the story outro still plays. Read-only.
- `game/entities/allies/ally_ship.gd` -- `state()` (`PATROL`/`APPROACH`/...), `is_damaged()`, `has_ended()`; logs `Tarek's fall: ...`. Read-only.
- `game/systems/waves/formation.gd` l.32 -- row y = `top_y + row * spacing.y`. `game/scenes/sandbox/sandbox.gd` and `tests/unit/test_formation.gd` use their own constants and are unaffected. Read-only.
- `game/tests/data/test_data_files.gd` -- edit `PLACEHOLDER_LEVELS` (l.62, now `[2, 3]`), `test_placeholder_levels_have_their_names_and_wasp_waves` (l.66), `test_mauls_only_in_dev_levels_and_level_1` (l.1287), `test_convoy_is_a_bool_and_only_on_in_dev_levels_and_level_1` (l.1311) and `test_ally_tarek_in_level_1_and_off_in_dev_and_levels_2_3` (l.1363). Also edit the file's header comment. Model the new shape test on `test_level_1_cargo_ambush_shape` (l.127) and reuse `_wave_type_totals`.
- `game/tests/unit/test_level_1.gd` -- fixture to copy: `_load_flags`, `_make_level`, `_kill_one_counted`, `_kill_through_wave`, `_click_through`, `_info`/`_crossed`, the comms recorder, the router recorder and the silent music track.
- `game/tests/unit/test_level.gd` l.1821–1960 -- how the fall is observed: the `story event 'tarek_fall'` log line, `channel.cut_phase() == HOLD`, `is_silenced()`, the ally leaving, and the flag-off `PATROL` check.
- `_bmad-output/game-architecture.md` -- append `## As-built 2026-10-11 (Story 7.2)` after the Story 7.1 entry (l.1888), in the same style.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` row 53 -- change its status cell from "Adopted; applied in Story 7.2" to "Applied 2026-10-11 (Story 7.2)".

## Tasks & Acceptance

**Execution:**
- `game/tests/data/test_data_files.gd` -- Add `test_level_2_blockade_shape`. It asserts the root values (intro and outro are story sequences), the per-wave counted totals by type, each wave's exact `spawns` order and formations, the exact asteroids, no groups, the exact trigger list of each wave, and `waves.formation.spacing_px.y` == 90 (decision #53). Set `PLACEHOLDER_LEVELS` to `[3]` and keep the name check for all 3 levels. The Maul and convoy guards must still assert that levels 2 and 3 have neither. Use an explicit list for this, not `PLACEHOLDER_LEVELS`. The ally guard asserts `tarek` for levels 1 and 2 and null for level 3. Rename the tests and update the comments to match. -- These pin the GDD numbers and keep the epic guards honest.
- `game/tests/unit/test_level_2.gd` -- NEW. An integration test on the real `level.tscn` with `level_id` "2", using the `test_level_1.gd` fixture: a short gap, an invincible player, a test save, a router recorder, a reset `GameState` and a captured Log. Cover the matrix. (a) Shipped flags: the briefing pause, W1–W4 rows, the W3 interrupt at 0.25, and the W5 fall plus cut-off at the 0.5 crossing with no pause. Wait for the cut to land (`HOLD` or silenced) before killing the rest. Then Tarek leaves, Ryn's report shows paused before the clear, `level_cleared` == [2] once, the router is called once, and `current_level_id` is "3". (b) `tarek_fall` off: no story event and no cut-off; Tarek is still patrolling at the clear; Ryn's report plays; the level clears. Both runs must have no `[WARN][spawn]`, `stalled` or `[ERROR][wave]` lines. Ally kills shift the ratios, so never assert exact kill counts. -- These observe the surface the ACs name: playing the level.
- `game/data/tuning.json` -- `waves.formation.spacing_px.y` 120 → 90. -- Decision #53.
- `game/data/levels/level_2.json` -- Replace it with the Design Notes content. -- This is the story's deliverable.
- `_bmad-output/game-architecture.md` -- Append the Story 7.2 as-built entry: the files and tests, the global 90 px row change and its new row y values, the decision #53 readings, the accepted outro/cut-off edge, and the playtest owed. -- This is the project's convention.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- Mark row 53 as applied. -- This keeps the log truthful.

**Acceptance Criteria:**
- Given the shipped flags, when Level 2 is played on the real `level.tscn` by killing counted enemies, then the briefing, waves, interruption, fall, cut-off, outro and clear happen as the matrix lists, and the level clears exactly once to level 3.
- Given `tarek_fall` false, when W5 passes 50 % and then clears, then no fall happens, Tarek keeps flying and Ryn's report still plays before the clear.
- Given every shipped level file at the 90 px row spacing, when the full GUT suite runs headless, then `LevelValidator` and the zone, cover and interruption data tests pass, along with every other test.

## Spec Change Log

## Review Triage Log

### 2026-10-11 — Review pass
- verdicts: 17 findings — high 0, medium 1, low 7, false 8, maybe-false 1
- findings:
  - `[false]` `[reject]` (blind) The spec file is missing from the reviewed diff. — Deliberate: the workflow sends the spec only to the edge-case layer as the claims file.
  - `[low]` `[patch]` (blind) The accepted outro/cut-off edge (reading 5) ignores a cut-off queued behind another combat line. — Added the queued variant to the as-built entry: unlikely in play, and listed for the playtest.
  - `[low]` `[patch]` (blind) The integration test only covers the queued cut-off, never the cut-off playing at once with the fall. — The test now waits for Isolde's line and the combat queue to clear before wave 5 and asserts `current_combat() == CUTOFF` at the 0.5 crossing.
  - `[low]` `[patch]` (blind) The flag-off test turned off both flags, so the AC case (`tarek_fall` off only) was untested. — Restored the `tarek_fall`-only test and added a separate `isolde_interruptions`-off test through wave 3 for the matrix row.
  - `[medium]` `[patch]` (blind) With 90 px rows, a missile hit on a back-row Wasp now usually splash-kills the Wasp in front of it (splash radius 120), which changes the DW-3 / decision #28 balance read, and nothing recorded it. — Recorded it in the as-built entry and added a playtest judgement to operator_actions. No tuning change (that would be a design decision).
  - `[maybe-false]` `[defer]` (blind) Wave 5 Bastions sit in the same columns as the Needles and can shield them; Bastions in waves 2 and 4 visually overlap the next Wasp row. — Whether this harms play depends on the drift and repositioning; settled by the playtest. Deferred as medium (unverified).
  - `[low]` `[patch]` (blind) `test_wave_director.gd` hard-codes row y 250. — `test_entries_stack_on_the_next_free_rows` now computes row 1 from the shipped tuning; `test_needles_take_a_row` keeps its deliberate pin.
  - `[false]` `[reject]` (blind) No Level 2 retry test. — Retry is data-independent: `test_wave_director.gd::test_intro_is_skipped_on_retry` covers skipping the intro, and the reload tests in `test_level.gd` cover ally re-creation on a fresh level scene.
  - `[low]` `[patch]` (blind) The cut-off's after-effects aren't checked on Level 2. — Added `Audio.current_music() == &""` once the cut lands (the static and shake are covered by the dev fall test).
  - `[false]` `[reject]` (blind) The shape test keeps three copies of the counts. — Each copy is compared against the data, so any drift fails loudly instead of passing silently.
  - `[false]` `[reject]` (blind) The 2 px margin of the planned L3 W3 layout is not recorded as a risk. — Level 3 data doesn't exist yet. When Story 7.6 adds it, `test_zoned_formations_fit_their_top_zone` checks it.
  - `[false]` `[reject]` (intent) The tests use a harness, not real play. — By design: the playtest is owed in operator_actions (status awaiting-operator, as in Story 7.1).
  - `[low]` `[patch]` (intent) "Plays" and "fire together" were checked only as requested or queued. — Grouped with the cut-off timing row; same fix.
  - `[low]` `[patch]` (intent) No test runs with only `tarek_fall` off. — Grouped with the flag-off row; same fix.
  - `[false]` `[reject]` (intent) Nothing checks the briefing's 2-3 Tarek lines. — `test_data_files.gd::test_campaign_script_layout` already asserts `l2_briefing` is a story with 2-3 Tarek lines.
  - `[false]` `[reject]` (intent) Level 1 is not re-checked after the spacing change. — `test_level_1.gd` and the zone data test ran in the full suite and pass at 90 px.
  - `[false]` `[reject]` (intent) The operator status is missing from the diff. — Finalization records it: `status: awaiting-operator` with a non-empty `operator_actions` list.

## Design Notes

Target `level_2.json` waves (entry order matters; format like `level_1.json`):

```
W1 spawns: needle 2 grid_2x1 top, wasp 6 grid_3x2 top | asteroids: medium 2, large 1
   wave_start: [music combat]
W2 spawns: bastion 1 grid_1x1 top, wasp 8 grid_4x2 top | asteroids: [] | triggers: []
W3 spawns: needle 3 grid_3x1 top, lancer 3 grid_3x1 sides | asteroids: medium 2
   progress 0.25 flag isolde_interruptions: [comms l2_w3_isolde_interrupt]
W4 spawns: bastion 2 grid_2x1 top, wasp 10 grid_5x2 top | asteroids: large 1 | triggers: []
W5 spawns: needle 2 grid_2x1 top, bastion 2 grid_2x1 top, lancer 4 grid_4x1 sides | asteroids: medium 2
   progress 0.5 flag tarek_fall: [story_event tarek_fall, comms l2_w5_tarek_cutoff]
```

At 90 px, rows fall at y 160 / 250 / 340. Every Wasp, Lancer and Bastion slot then fits its zone: Wasps ≤ 432, Lancers ≤ 378 and Bastions 160–320. Level 1 only moves up, so it still fits. Known edge, accepted (reading 5): if W5's last enemies die within about 0.5 s of the 50 % mark, the outro preempts the cut-off's effects.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits cleanly.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failing (`<GODOT_DIR>` from `LOCAL.md`).

**Manual checks (operator):**
- Play Level 2 from the title in a debug build with the F1 overlay on. Check that no wave soft-locks, the level takes about 3–4 minutes plus dialogue, cover works against the Needles, and the fall lands as a beat. Also play Level 1 and check that the tighter 90 px rows still read well.

## Auto Run Result

Status: awaiting-operator

**Summary:** Story 7.2 is built as data plus tests, and all 1652 tests pass. `game/data/levels/level_2.json` is now the GDD's Blockade. Tarek flies with no convoy. His paused `l2_briefing` holds wave 1, and `l2_ryn_report` is the paused outro. The five waves have the exact GDD counts and asteroids (8, 9, 6, 12 and 8 counted), with every Needle entry first. W1 starts the combat music, and Isolde's line comes at 25 % of W3 when its flag is on. When `tarek_fall` is on, Tarek's fall and his cut-off line fire together at 50 % of W5. Decision #53's global change is applied: formation rows are now 90 px apart (`waves.formation.spacing_px.y` 120 → 90), so W5 fits as Needles y 160, Bastions y 250 and Lancers y 340, with no spawn clamp in any level. No engine code, dialogue or other tuning changed. The playtest-only parts of the ACs need a human, so they are owed under `operator_actions`: the 3-4 minute length, a full F1 run with no soft-lock, whether cover works, how the fall feels as a beat, and how the tighter rows and missile splash play.

**Files changed:**
- `game/data/levels/level_2.json`: replaces the Story 4.1 placeholder with the GDD Level 2 data.
- `game/data/tuning.json`: `waves.formation.spacing_px.y` 120 → 90 (decision #53).
- `game/tests/data/test_data_files.gd`: adds `test_level_2_blockade_shape`. Level 3 is now the only placeholder. The Maul and convoy guards use an explicit `[2, 3]` list, and the ally guard expects Tarek in levels 1 and 2.
- `game/tests/unit/test_level_2.gd` (+ `.gd.uid`): new integration test on the real `level.tscn`. It plays level 2 with the shipped flags, with `tarek_fall` off, and through W3 with `isolde_interruptions` off.
- `game/tests/unit/test_wave_director.gd`: the row-1 expectations now match the 90 px rows. One is computed from tuning, one is a deliberate pin.
- `_bmad-output/game-architecture.md`: new `As-built 2026-10-11 (Story 7.2)` entry.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md`: row 53 marked "Applied 2026-10-11 (Story 7.2)".
- `_bmad-output/implementation-artifacts/epic-7-context.md`: recompiled with decision #53.

**Review findings:** 17 findings: 0 high, 1 medium, 7 low, 8 false, 1 maybe-false. The edge-case and verification-gap layers reported none.
- **Patched (8 rows, 6 fixes):**
  - The cut-off now plays at once in the test, and the music stop is asserted.
  - The `tarek_fall`-only test is restored, and an Isolde-off test is added.
  - Row 1 is computed from tuning in `test_entries_stack_on_the_next_free_rows`.
  - The as-built entry records the queued cut-off variant.
  - The as-built entry and the operator list record the missile-splash side effect (medium).
- **Deferred (1):** the W5 Bastion/Needle column overlap and the W2/W4 Bastion/Wasp visual overlap, medium (unverified), owed to the playtest.
- **Rejected (8 false):**
  - the spec missing from the diff (deliberate)
  - no Level 2 retry test (data-independent and covered)
  - the duplicated counts in the shape test (drift fails loudly)
  - the L3 W3 margin (checked when Story 7.6 lands)
  - harness versus real play (owed to the operator)
  - the briefing line count (already tested)
  - Level 1 not re-checked (its tests pass)
  - the operator status (recorded at finalization)

**Follow-up review recommendation:** false. One medium entry was patched, and it was documentation only. No high entry was patched, so there is no named unverified risk for another pass.

**Verification:**
- `--headless --path game --import` exited 0.
- Full GUT run after implementation: 87 scripts, 1651 tests, 1651 passing.
- After the review patches: 1652 tests, 1652 passing, 0 failing, 0 pending.
- Every row of the I/O matrix is covered by a passing test in `test_level_2.gd`, plus the zone data test for the formation rows.

**Residual risks:**
- The tests run with an invincible player and kill enemies directly, so pacing, difficulty and cover are unproven until the playtest.
- The 90 px rows are global. They make missile splash usually reach the next Wasp row, and they bring Bastions closer to the rows below them.
- If a combat line is still playing at the W5 50 % mark, the cut-off is delayed behind it. This is unlikely in play.
