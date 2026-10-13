---
title: 'Story 7.6: Play Level 3: Siege of the Throne World'
type: 'feature'
created: '2026-10-12'
status: done
operator_actions:
  - 'Play Level 3 from Level Select in a debug build ("<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game) with the F1 overlay on, from Ryn''s briefing through the three waves, the Flagship, the Final Choice and the clear (which returns to the title until Story 7.7), and confirm that no wave or boss phase soft-locks and that the level takes about 3-4 minutes plus dialogue.'
  - 'During that run, confirm the placeholder throne-world arc is visible along the bottom of the screen in Level 3 (including during the boss-death shake, with no flat edge showing), and judge whether it reads as the throne-world reveal without distracting from the fight; then start Levels 1 and 2 and confirm no arc appears there.'
  - 'Judge the Level 3 difficulty and pacing: wave 1 (4 Lancers, 12 Wasps), wave 2 (whether the 3 medium asteroids give usable cover from the Needles, and whether the Bastions in the same columns below the Needles hide them too much), wave 3 (20 Wasps in a 10 x 2 block plus Lancers and a Bastion) and Isolde''s taunt at 25 % of wave 3; raise any retune or layout change rather than editing code silently (tuning goes in game/data/tuning.json with a decision-log entry).'
  - 'Optionally set "hunter_wasp": true in game/data/flags.json, press F5 in Level 3, and confirm wave 2 brings the 4 Hunter Wasps and still clears; set the flag back to false afterwards.'
baseline_revision: 'd52f022c0bf85f9e630a1b5024a59ddc4c2b14d9'
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
      No automated test proves the throne-world placeholder arc is actually rendered on screen; the tests check LevelBackground state, colours, geometry and node order only.
    evidence: |-
      Maybe-false (intent-alignment layer): headless GUT runs on the dummy renderer, so pixels can't be checked there. The draw path is a single draw_colored_polygon plus draw_polyline over a convex circular segment, called after apply(). Settled by the operator playtest in operator_actions (the arc must be visible in Level 3 and absent in Levels 1 and 2).
    location: >-
      game/scenes/level/level_background.gd
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** `game/data/levels/level_3.json` is still the Story 4.1 placeholder: two Wasp-only waves, no ally, no briefing and no boss. The finale must run Ryn's briefing, the three GDD defence waves (with Isolde's taunt in W3) and then the Flagship boss wave. The throne world must appear behind Level 3 only, as a reveal (FR48, FR44 L3, FR42, FR64).

**Approach:** Replace `level_3.json` with the GDD data, and put the Flagship boss wave (built in Stories 7.3-7.5) last. Every mechanic already exists, so the level is data. The one code addition is a small `LevelBackground` script on the existing `Level/Background` node. It reads the level's `background` id and draws a code-drawn placeholder planet arc only for `throne_world`; Epic 8 replaces the placeholder with art. Tests pin the data, play Level 3 on the real `level.tscn` through the boss to the clear, and check that Levels 1 and 2 never show the throne world.

## Boundaries & Constraints

**Always:**
- The root keys are exactly the `level_dev` key set: `id` 3, `name` "Siege of the Throne World", `background` "throne_world", `music` "combat", `convoy` false, `ally` "ryn", `intro_sequence` "l3_briefing", `outro_sequence` null. Story 7.7 adds `l3_isolde_final` as the outro.
- W1's `wave_start` runs `{ "music": "combat" }`, because the root `music` key isn't read. The boss wave's `wave_start` runs `{ "music": "boss" }`.
- Entry order (decision #53, DW-68, epic context): W1 Lancers then Wasps; W2 Needles first; W3 Bastion, Lancers, then Wasps `grid_10x2`. No slot may clamp, and `test_zoned_formations_fit_their_top_zone` must pass with no exemption.
- The W2 Hunter Wasp entry is a normal `hunter_wasp` spawn entry. With `hunter_wasp` false (as shipped) the WaveDirector skips it and doesn't count it (decision F14). No new gating code.
- The W3 taunt is `progress` 0.25 gated by `isolde_interruptions`, the same pattern as the L1/L2 Isolde lines (decision #53 reading 1).
- `LevelBackground` follows the project rules: statically typed, logs only through `Log`, no per-frame allocation, and it redraws only when `apply` is called. The placeholder colours stay dark (below `render.glow.hdr_threshold`, so they don't bloom) and must not read as enemy magenta or red. It sits behind `World`.
- GUT tests are statically typed and written first (red, then green).

**Never:**
- No WaveDirector, Flagship, CommsChannel, AllyShip, HUD, Audio, SceneRouter or LevelValidator change. Don't edit any dialogue file, `level_1.json`, `level_2.json`, `flags.json` or `tuning.json`.
- No `outro_sequence`, end screen or `goto_end` (Story 7.7). No level-select thumbnail and no space_1 or space_2 art (Epic 8).
- Never claim feel, pacing, the 3-4 minute length, difficulty or how the reveal reads as verified. Those are owed to the operator.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Level start | `level_3`, fresh | 1 `AllyShip` with `ally_id` "ryn", no Convoy; `Background` shows the throne world; `l3_briefing` is paused in the story panel (RYN) and W1 hasn't started | — |
| W1 | after the click-through | 16 counted: lancer 4, wasp 12; combat music | — |
| W2, flag off (shipped) | `hunter_wasp` false | 4 counted: needle 2, bastion 2; 3 medium asteroids; no hunter_wasp spawned; one DEBUG skip line | — |
| W2, flag on | `hunter_wasp` true | 8 counted: plus hunter_wasp 4; the wave clears into W3 | — |
| W3 | 24 counted: bastion 1, lancer 3, wasp 20 | `l3_w3_isolde_taunt` requested on the resolve that crosses 0.25, no pause | `isolde_interruptions` off: never requested |
| Boss wave | W3 cleared | `boss` music; total 1; one Flagship; its 2 medium cover asteroids | — |
| Boss to clear | turrets killed, core to 50, a choice clicked, the response clicked through, core killed | `boss_defeated` once, `level_cleared` [3] once, the router called once with the title scene (`complete_level(3)` → `goto_title`) | — |
| Levels 1, 2 | `level.tscn` with `level_id` "1" / "2" | `Background` doesn't show the throne world | — |
| Unknown background id | `apply("nope")` | draws nothing, one `[WARN][scene]` line | WARN, no crash |
| Null background | `apply("")` (dev levels) | draws nothing, no warning | — |

</intent-contract>

## Code Map

- `game/data/levels/level_3.json` -- REPLACE with the Design Notes content.
- `game/data/levels/level_2.json`, `level_1.json`, `level_dev_boss.json`, `level_dev.json` (l.69-72, the hunter_wasp entry) -- golden patterns. Read-only.
- `game/data/dialogue/level_3.json` -- `l3_briefing` (story, 3 Ryn lines) and `l3_w3_isolde_taunt` (combat). Read-only.
- `game/scenes/level/level.gd` -- `_ready` loads `data` (l.~104) and spawns the convoy and ally before `_director.start_level`. Add one call that hands `data.get("background")` to the Background node, plus a doc line in the header comment. Follow the `ally_id(data)` style for a static `background_id(data) -> String` ("" for absent or null, and "" with a WARN for a non-String).
- `game/scenes/level/level.tscn` l.33 -- `Background` (Node2D, first child, so it draws behind `World`). Attach the new script (add an `ext_resource`).
- `game/entities/allies/ally_ship.gd` l.47-61 -- the placeholder-colour constant idiom (`const ... : Color`) to copy.
- `game/systems/waves/wave_director.gd` l.221, l.371 -- the hunter_wasp skip and its DEBUG line `... skipped (flag 'hunter_wasp' off); not counted`. Read-only.
- `game/systems/comms/comms_channel.gd` l.73-78 -- a choice's `next` plays without a `comms_sequence_requested`, so the request list is `[l3_briefing, l3_w3_isolde_taunt, l3_final_choice]`. Read-only.
- `game/autoloads/scene_router.gd` l.224 -- `complete_level(3)` saves and calls `goto_title()` (level 3 is the last). Read-only.
- `game/tests/unit/test_level_2.gd` -- the fixture to copy: flags, save, router recorder, Log capture, silent music, tallies, `_kill_one_counted`, `_kill_through_wave`, `_kill_to_ratio`, `_click_through`, `_info`/`_crossed`, `_assert_clean_log`. Register silent tracks under both `combat` and `boss`, and restore both afterwards.
- `game/tests/unit/test_flagship_level.gd` l.151-256 -- how to drive the real boss: `boss.step(arrival_s)`, kill the turrets, `core.apply_damage(core.hp - 50)`, `_click_at` through the lead-in, click a `FinalChoice.buttons()` entry, click through the response, kill the core, wait `feedback.boss_death_chain_s` + 0.8.
- `game/tests/data/test_data_files.gd` -- `PLACEHOLDER_LEVELS` (l.67) and the placeholder branch of `test_campaign_levels_have_their_names_and_placeholder_wasp_waves` (l.72); `test_ally_tarek_in_levels_1_2_and_off_in_dev_and_level_3` (l.1463); `test_boss_waves_only_in_dev_levels` (l.1684); `test_level_2_blockade_shape` (l.207) is the model for the new shape test; `_wave_type_totals`.
- `_bmad-output/game-architecture.md` -- append `## As-built 2026-10-12 (Story 7.6)` after the Story 7.5 entry and before the closing `---` footer.

## Tasks & Acceptance

**Execution:**
- `game/tests/data/test_data_files.gd` -- Add `test_level_3_siege_shape`. It asserts the root values (`l3_briefing` is a story sequence, the outro is null), each wave's exact `spawns` order, formations and entries, the counted totals by type with the flag off and on, the exact asteroids, no groups, and every wave's exact trigger list. The last wave is `{boss: flagship}` with exactly the boss music trigger. Remove `PLACEHOLDER_LEVELS` and its branch (no placeholders are left), keep the name, id and key-set checks for all three levels, and rename the test. Rename the ally guard to expect Tarek in levels 1-2, `ryn` in level 3 and none in `level_dev`. Make the boss guard allow `level_3.json`, and assert that its only boss wave is its last wave. Add `test_throne_world_background_only_in_level_3`: every level file's `background` is null or in `LevelBackground.IDS`, level 1 is `space_1`, level 2 is `space_2`, and only `level_3.json` uses `throne_world`. Update the header comments. -- These pin the GDD numbers and the reveal rule.
- `game/tests/unit/test_level_background.gd` -- NEW. Cover `apply` with "throne_world", "space_1", "" and an unknown id: `shows_throne_world()`, one WARN only for the unknown id, and no WARN for "". Also build the real `level.tscn` with `level_id` "1", "2" and "3" (invincible player, router recorder, test save) and check `Background` is a `LevelBackground`, shows the throne world only for "3", and is drawn before `World`. -- AC3 at the scene surface.
- `game/tests/unit/test_level_3.gd` -- NEW. The integration test on the real `level.tscn` (`level_id` "3"), using the `test_level_2.gd` fixture. (a) Shipped flags: cover every matrix row from the level start to the clear, pick OFFER SURRENDER, and record the requests `[l3_briefing, l3_w3_isolde_taunt, l3_final_choice]`. (b) `hunter_wasp` on (temp flags file): W2 counts 8 including 4 hunter_wasp, and the wave clears into W3. (c) `isolde_interruptions` off: play through W3 into the boss wave; the taunt is never requested, and the boss music starts. Every run has no `[WARN][spawn]`, `stalled` or `[ERROR]` line. Ryn's kills shift ratios, so never assert exact kill counts. -- These observe the ACs on the played level.
- `game/scenes/level/level_background.gd` -- NEW. `class_name LevelBackground extends Node2D`. `const IDS: Array[String] = ["space_1", "space_2", "throne_world"]`. `apply(id: String)` stores the id and calls `queue_redraw()`; an id that is non-empty and not in `IDS` gets one `Log.warn("scene", ...)` and is treated as none. `shows_throne_world() -> bool`. `_draw` (throne world only): one large filled planet disc whose top arc rises from the bottom edge of the playfield, plus a thin rim arc. Colours and geometry are placeholder-art constants. -- The reveal at the surface, with placeholder art (allowed until Epic 8).
- `game/scenes/level/level.tscn` + `level.gd` -- Attach the script to `Background`. In `_ready`, after `data` loads and before the director starts, call `($Background as LevelBackground).apply(background_id(data))`, then log one INFO line `Background '<id>'` when the id is non-empty. -- Background is chosen by level data (architecture Scene Structure).
- `game/data/levels/level_3.json` -- Replace it with the Design Notes content. -- This is the story's deliverable.
- `_bmad-output/game-architecture.md` -- Append the Story 7.6 as-built entry. Cover the data, `LevelBackground`, and the readings (the `throne_world` id and its code-drawn placeholder, the taunt's gate, the null outro until 7.7, Level 3 clearing to the title until 7.7). Cover the tests and the playtest owed. -- This is the project's convention.

**Acceptance Criteria:**
- Given the shipped flags, when Level 3 is played on the real `level.tscn` from the briefing through the Flagship's death, then every matrix row holds, nothing soft-locks, and the level clears exactly once to the title.
- Given `hunter_wasp` on or `isolde_interruptions` off, when the affected wave runs, then the matrix's flag rows hold and the level keeps progressing.
- Given Levels 1 and 2 loaded in `level.tscn`, when their Background is inspected, then the throne world isn't shown; only Level 3 shows it.
- Given every shipped level file, when the full GUT suite runs headless, then `LevelValidator` and the zone, cover, interruption, boss and background data tests pass, along with every other test.

## Design Notes

Target `level_3.json` waves (same layout as `level_2.json`; rows at 90 px):

```
W1 spawns: lancer 4 grid_4x1 sides (y160), wasp 12 grid_6x2 top (y250,340) | asteroids: []
   wave_start: [music combat]
W2 spawns: needle 2 grid_2x1 top (y160), bastion 2 grid_2x1 top (y250),
           hunter_wasp 4 grid_4x1 top (rowless) | asteroids: medium 3 | triggers: []
W3 spawns: bastion 1 grid_1x1 top (y160), lancer 3 grid_3x1 sides (y250),
           wasp 20 grid_10x2 top (y340,430) | asteroids: [] 
   progress 0.25 flag isolde_interruptions: [comms l3_w3_isolde_taunt]
W4 { "boss": "flagship", "triggers": [ wave_start: [music boss] ] }
```

Placeholder arc (record-only reading; final art comes in Epic 8): the disc centre sits well below the playfield (for example (960, 1080 + R - ~200) with R ~ 1600), so only a shallow arc about 200 px high shows along the bottom. Use a dark, desaturated violet fill and a slightly lighter rim, drawn once and cached by Godot's canvas. This is not a GDD tuning number, so it stays as code constants, like the ally's placeholder hull.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits cleanly (a new `class_name` was added).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failing (`<GODOT_DIR>` comes from `LOCAL.md`).

**Manual checks (operator):**
- Play Level 3 from Level Select in a debug build with F1 on: briefing, waves, taunt, boss, choice and clear. Judge pacing, the 3-4 minute length, whether the placeholder arc reads as a reveal without distracting, and the W2 Bastion/Needle column overlap.

## Spec Change Log

## Review Triage Log

### 2026-10-12 — Review pass
- verdicts: 23 findings — high 0, medium 1, low 7, false 14, maybe-false 1
- findings:
  - `[false]` `[reject]` (blind) `test_level_3.gd` clicks 4 times through 2-line sequences, so leftover clicks reach gameplay. — Each typewriter line needs a click to complete it and one to advance, so 2 lines take up to 4 clicks; `test_flagship_level.gd` uses the same count, and the test asserts the panel closed and no pause reason remains.
  - `[false]` `[reject]` (blind) Nothing checks that `draw_colored_polygon` can triangulate the cap. — The polygon is a circular segment (arc plus chord), which is convex and always triangulates.
  - `[low]` `[patch]` (blind) The header says `_draw` runs only after `apply()`, but Godot also draws on entering the tree. — Comment and as-built reworded: one draw on entering the tree (nothing, before `apply()`), then only when `apply()` queues a redraw.
  - `[low]` `[reject]` (blind) The ally kill-share line isn't checked on Level 3, where turret, core and boss-Wasp kills feed it. — The line is logged once per attempt by existing tested code (`test_level.gd`). Whether boss kills should count toward Ryn's 10-15 % is a tuning-pass question, not a defect here, and the fix would need a design decision.
  - `[false]` `[reject]` (blind) Ryn is never exercised over real frames in the boss fight. — `AllyShip.nearest_target` skips non-targetable parts (`ally_ship.gd` l.379), covered in `test_flagship.gd`, and the ally is invincible by design (GDD).
  - `[low]` `[patch]` (blind) The `highest_unlocked_level` assertion message "level 3 stays the highest" is wrong, and the save isn't checked. — The message is now "complete_level(3) records level 3 as the highest". The save write is covered by the `complete_level` tests in `test_scene_router.gd`.
  - `[false]` `[reject]` (blind) The `isolde_interruptions`-off test stops at the boss wave. — The boss path doesn't read that flag. Reaching the boss wave with the music on proves progress, and the shipped-flags run drives the same boss to the clear.
  - `[false]` `[reject]` (blind) The hunter-on "no skip line" check matches only the exact string. — The same test asserts total 8 and a tally of 4 `hunter_wasp`, which already disproves a skip.
  - `[false]` `[reject]` (blind) `level.gd` doesn't guard the `$Background as LevelBackground` cast. — The script is an `ext_resource` of the only `level.tscn`. A stale class cache breaks `level.gd`'s own parse (it names `LevelBackground`), so a guard can't help, and the null state is unreachable.
  - `[low]` `[patch]` (blind) No handoff to Story 7.7 for the end screen's throne-world backdrop. — The as-built entry now says the end screen can reuse `LevelBackground.apply("throne_world")`.
  - `[low]` `[reject]` (blind) `LevelValidator` doesn't check `background`, and that isn't deferred. — `test_throne_world_background_only_in_level_3` checks every level file (dev included), and a hand-edited file logs a WARN at runtime. The fix adds a validator branch for an unlikely case.
  - `[false]` `[reject]` (blind) The `Background 'space_1'` INFO line claims a backdrop that isn't drawn. — The line reports the applied id, which is accurate. It makes no claim about art.
  - `[false]` `[reject]` (blind) `test_level_background.gd`'s reset skips `final_choice`, and its story pauses leak. — No test in that file sets `final_choice`, and `after_each` calls `PauseArbiter.clear()`, the same pattern as the other scene tests.
  - `[low]` `[patch]` (blind) The arc's horizontal extent isn't recorded. — The as-built entry now records that the arc meets the bottom edge at about x 185 and x 1735 (a shallow dome with the corners empty) for the operator to judge.
  - `[medium]` `[patch]` (edge) `EDGE_MARGIN_PX` 8 is less than the ShakeCamera offset (boss-death 20 px, cut-off 18 px, both axes), so the cap's flat chord and the rim ends show during the Level 3 boss-death shake. — Confirmed in `shake_camera.gd` l.67. `EDGE_MARGIN_PX` is now 40, and `test_edge_margin_exceeds_every_tuned_shake` pins it above every tuned `shake_px` and `comms.cutoff_shake_px`.
  - `[false]` `[reject]` (edge) A null `Background` cast aborts `_ready` and soft-locks. — Same as the blind finding: the state is unreachable with the shipped scene.
  - `[low]` `[patch]` (edge) "Never blooms" is inaccurate, because `render.glow.bloom` 0.08 glows every pixel. — Comment and as-built reworded: the arc stays below the HDR threshold, so it adds no HDR glow, and only the scene-wide bloom applies.
  - `[false]` `[reject]` (intent) The tests drive a harness (invincible player, direct kills, stepped boss), not real play. — By design. The playtest is owed in `operator_actions` (status awaiting-operator, as in Stories 7.1-7.5).
  - `[maybe-false]` `[defer]` (intent) No test checks that `_draw` renders the arc on screen. — Headless runs can't read pixels. Settled by the operator playtest. Deferred as medium (unverified).
  - `[false]` `[reject]` (intent) Both music cues are inaudible in the shipped build. — No music track exists until Story 8.1 (pre-existing, `Audio.music_streams` is empty). The AC's music keys are data, and the data is pinned and played.
  - `[false]` `[reject]` (intent) The taunt is checked only as a request. — Showing a requested combat sequence is `CommsChannel` behaviour covered by its own tests. Level data only requests it.
  - `[false]` `[reject]` (intent) Clearing Level 3 to the title is an addition. — It is the existing `complete_level(3)` path, recorded as reading 5 until Story 7.7 adds the end screen.
  - `[false]` `[reject]` (intent) The spec isn't finalised (`in-review`, no `operator_actions`, uncommitted). — That was a mid-loop snapshot. Finalisation sets awaiting-operator with `operator_actions` and commits.

## Auto Run Result

Status: awaiting-operator

**Summary:** Story 7.6 is built and all 1806 tests pass. `game/data/levels/level_3.json` is now the GDD's Siege of the Throne World:
- **Setup:** Ryn flies and there is no convoy. Her paused `l3_briefing` holds wave 1.
- **Waves:**
  - W1: 4 Lancers and 12 Wasps, with the combat music.
  - W2: 2 Needles, 2 Bastions and 3 medium asteroids, plus 4 Hunter Wasps that are skipped and not counted while `hunter_wasp` is off, as shipped.
  - W3: 1 Bastion, 3 Lancers and 20 Wasps (`grid_10x2`), with Isolde's taunt at 25 %.
  - Last: the Flagship boss wave with the boss music.
- **Throne world:** a new `LevelBackground` on the existing `Level/Background` node draws a code-drawn placeholder planet arc, and only for the `throne_world` id that Level 3 uses. Levels 1 and 2 never show it. Epic 8 replaces it with art.
- **Not changed:** no WaveDirector, Flagship, comms, ally, HUD, audio, router, validator, dialogue, flags or tuning code or data.
- **Until Story 7.7:** the outro stays null, and clearing Level 3 returns to the title.
- **Owed to the operator** under `operator_actions`: the full playtest, whether the reveal shows and reads well, pacing and difficulty.

**Files changed:**
- `game/data/levels/level_3.json`: replaces the Story 4.1 placeholder with the GDD Level 3 and the Flagship boss wave.
- `game/scenes/level/level_background.gd` (+ `.uid`): new `LevelBackground`, the throne-world placeholder arc chosen by level data.
- `game/scenes/level/level.gd`: static `background_id(data)`, and applies the background before the waves start, with one INFO line.
- `game/scenes/level/level.tscn`: attaches `LevelBackground` to `Background`.
- `game/tests/data/test_data_files.gd`: adds `test_level_3_siege_shape` and `test_throne_world_background_only_in_level_3`, removes the placeholder-level branch, and updates the ally and boss-wave guards for Level 3.
- `game/tests/unit/test_level_3.gd` (+ `.uid`): new. Plays Level 3 on the real `level.tscn` with the shipped flags through the Flagship to the clear, plus a `hunter_wasp`-on run and an `isolde_interruptions`-off run.
- `game/tests/unit/test_level_background.gd` (+ `.uid`): new. Covers `apply`, the colours, the arc geometry, the shake margin, `background_id`, and levels 1, 2, 3 and dev on the real scene.
- `_bmad-output/game-architecture.md`: new `As-built 2026-10-12 (Story 7.6)` entry.

**Review findings:** 23 findings: 0 high, 1 medium, 7 low, 14 false, 1 maybe-false. The verification-gap layer reported none.
- **Patched (6):**
  - (medium) The planet cap's flat edge could show during the boss-death shake. The margin is now 40 px, pinned by a test.
  - (low) The comment on when the arc is drawn was corrected.
  - (low) The bloom wording was corrected.
  - (low) A wrong assertion message was fixed.
  - (low) The end-screen reuse is noted for Story 7.7.
  - (low) The arc's horizontal extent is recorded.
- **Deferred (1):** no test proves the arc renders on screen, medium (unverified), settled by the operator playtest.
- **Rejected (16):**
  - Low, not worth fixing:
    - the boss kills counting toward the ally kill share (a tuning-pass question)
    - no `LevelValidator` check for `background` (every level file is already data-tested)
  - False:
    - the click count (typewriter lines take two clicks)
    - polygon triangulation (the cap is convex)
    - Ryn's targeting (already covered)
    - the flag-off boss path (the boss doesn't read the flag)
    - the narrow skip-line check (the counts already disprove a skip)
    - the Background cast guard, twice (the null state is unreachable)
    - the INFO line wording (it reports the id accurately)
    - the test reset (nothing leaks)
    - harness versus real play (owed to the operator)
    - inaudible music (no tracks until Story 8.1)
    - the taunt checked only as a request (display is covered by the comms tests)
    - clear to title (existing path until Story 7.7)
    - the unfinalised snapshot (finalised now)

**Follow-up review recommendation:** false. One medium and five low entries were patched, and no high. The medium fix is a constant change pinned by a new test, so there is no named unverified risk.

**Verification:**
- `--headless --path game --import` exited 0, after implementation and again after the patches.
- After implementation: 93 scripts, 1805 tests, 1804 passing, 0 failing, 1 pending.
- After the review patches: 1806 tests, 1805 passing, 0 failing, 1 pending.
- The one pending test is the existing hit-stop timing guard in `test_feedback.gd`, which skips itself when the frame timing is too coarse. It is unrelated to this story.
- Every row of the I/O matrix is covered by a passing test in `test_level_3.gd` or `test_level_background.gd`.

**Residual risks:**
- The tests use an invincible player, kill enemies directly and step the boss, so pacing, difficulty, cover and the reveal are unproven until the playtest.
- The W2 Bastions sit in the same columns below the Needles, the same accepted layout as Level 2 wave 5. The operator judges it.
- With 20 Wasps on rows y 340 and 430, a missile on the lower row usually splash-kills the one above, the known side effect of the 90 px rows.
- In the shipped build both music cues are silent until Story 8.1 adds tracks.

## Operator Confirmation

Confirmed 2026-10-13: the external actions this story owed were carried out.

- Play Level 3 from Level Select in a debug build ("<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game) with the F1 overlay on, from Ryn's briefing through the three waves, the Flagship, the Final Choice and the clear (which returns to the title until Story 7.7), and confirm that no wave or boss phase soft-locks and that the level takes about 3-4 minutes plus dialogue.
- During that run, confirm the placeholder throne-world arc is visible along the bottom of the screen in Level 3 (including during the boss-death shake, with no flat edge showing), and judge whether it reads as the throne-world reveal without distracting from the fight; then start Levels 1 and 2 and confirm no arc appears there.
- Judge the Level 3 difficulty and pacing: wave 1 (4 Lancers, 12 Wasps), wave 2 (whether the 3 medium asteroids give usable cover from the Needles, and whether the Bastions in the same columns below the Needles hide them too much), wave 3 (20 Wasps in a 10 x 2 block plus Lancers and a Bastion) and Isolde's taunt at 25 % of wave 3; raise any retune or layout change rather than editing code silently (tuning goes in game/data/tuning.json with a decision-log entry).
- Optionally set "hunter_wasp": true in game/data/flags.json, press F5 in Level 3, and confirm wave 2 brings the 4 Hunter Wasps and still clears; set the flag back to false afterwards.

_Appended by the bmad-loop orchestrator (`bmad-loop confirm`, #335): a human confirmed these external actions out of band, and the story was advanced from `awaiting-operator` to `done`._
