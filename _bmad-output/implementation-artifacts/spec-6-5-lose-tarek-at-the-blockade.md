---
title: 'Story 6.5: Lose Tarek at the Blockade'
type: 'feature'
created: '2026-10-10'
status: 'done'
baseline_revision: '23fbb4f31b412f7a2395893c16c9bc1997036443'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-6-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `Events.story_event_requested(&"tarek_fall")` has no listener, so Tarek never shields Vale, never falls and keeps flying through the Blockade beat (FR35, SHOULD, last to cut). The comms half (cut-off, static, `cutoff` shake, music stop, silence until wave clear) already exists in `CommsChannel` (Story 5.4) and `l2_w5_tarek_cutoff` exists in `level_2.json`, but no level fires both together.

**Approach:** Give `AllyShip` the fall: on `story_event_requested(&"tarek_fall")`, a Tarek ally in `PATROL` stops firing and runs `APPROACH` (glides over Vale) → `SHIELD` (holds over Vale while a coalition shield ring flashes around Vale) → `FALLING` (damaged hull, fire trail, flies off the nearer side edge) → `GONE` (freed; never returns this attempt). All timings in a new `tuning.allies.fall` section. Add a dev level whose wave 2 has a `tarek_fall`-flagged progress trigger running `story_event: tarek_fall` then `comms: l2_w5_tarek_cutoff`, and prove the whole beat on the real `level.tscn`.

## Boundaries & Constraints

**Always:**
- New tuning `allies.fall`: `approach_s` 1.0, `shield_s` 1.5, `shield_offset_px` 80, `shield_radius_px` 72, `shield_flash_hz` 8, `exit_speed_px_s` 320, `exit_drop` 0.35. Read through `Config`, cached in `_ready`. Static typing, `Groups`/`CollisionLayers` constants, `Log` only.
- `AllyShip` connects `Events.story_event_requested` in `_ready` (disconnect not needed; it's freed with the level). It reacts only when `event_name == &"tarek_fall"`, `ally_id == "tarek"` and the state is `PATROL`; any other case is ignored (Ryn, repeats, other events). The ally never reads the flag: the flag gates only the trigger.
- On the event: look up `Groups.PLAYER` **once** (`get_first_node_in_group`) and cache it; log `[INFO][scene] Tarek's fall: shielding Vale`. No `Groups.PLAYER` node (or freed later) → skip `APPROACH`/`SHIELD` and go straight to `FALLING` from where it is.
- `APPROACH` (`approach_s`): position = start lerped toward `player.global_position + Vector2(0, -shield_offset_px)` (re-read each step, so it tracks Vale) with smoothstep on `t = elapsed / approach_s`. `SHIELD` (`shield_s`): stays exactly at that point, tracking Vale; `shield_visible()` true, the ring (radius `shield_radius_px`, `coalition`, 3 px) drawn centred on Vale (local offset `(0, shield_offset_px)`), alpha pulsing at `shield_flash_hz`. A zero duration skips the phase in one step.
- `FALLING`: `is_damaged()` true; the hull swaps to the damaged outline (`_build_damaged_outline`: the fighter with the right wing tip broken off) drawn with body `#0A1222` at alpha 0.8 and a `danger` `#FF1F4B` outline; the `FireTrail` `GPUParticles2D` child (in `ally_ship.tscn`, `emitting = false`, `local_coords = false`, additive, gradient `energy` `#FFD23F` → `danger` → transparent) starts emitting. Velocity = `Vector2(side, exit_drop).normalized() * exit_speed_px_s`, `side` = −1 when x < 960 else +1 (nearer edge). Log `[INFO][scene] Tarek's fall: damaged, leaving the fight`.
- `GONE`: entered on the first step where the position is outside `Playfield.RECT.grow(ship_px)`; stops the trail, logs `[INFO][scene] Tarek's fall: Tarek has left the level`, `queue_free()`. No path re-creates the ally (only `Level._ready` spawns one; retry reloads the scene, which is intended).
- No shots from the event onward (`_tick_fire` runs only in `PATROL`). Movement stays in `step(delta)`; no per-frame group lookups or allocations (the outline arrays are built once in `_ready`).
- Write the failing GUT test first.

**Never:**
- No change to `CommsChannel`, `WaveDirector`, `Feedback`, `Audio`, the dialogue files, Player, Enemy or HUD. The shake, static, music stop and silence come only from `l2_w5_tarek_cutoff`'s `after` data.
- The shield is visual only: it blocks no shot and grants no invulnerability (allies block nothing).
- No change to `level_1/2/3.json` (Epic 7 places the beat in Level 2 Wave 5). No image asset (Epic 8 art).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Fall starts | Tarek in PATROL, event `tarek_fall` | state APPROACH, INFO line, firing stops at once | — |
| Approach | `approach_s` of steps, Vale moving | ends at Vale + (0, −80) exactly; positions in between are a smoothstep blend | — |
| Shield | `shield_s` of steps | stays at Vale + (0, −80) while Vale moves; `shield_visible()` true; then FALLING | — |
| Falling | after SHIELD, x < 960 / x ≥ 960 | `is_damaged()`, trail emitting, damaged outline, moves at 320 px/s toward the left / right edge with the down drift | — |
| Gone | position leaves `RECT.grow(ship_px)` | INFO line, trail stops, node freed; no AllyShip in `World/Allies` afterwards | — |
| No player | no `Groups.PLAYER` node at the event | straight to FALLING from the current spot | — |
| Ignored | Ryn gets `tarek_fall`; Tarek gets another event; repeat event mid-fall | no change of state | — |
| Flag off | `tarek_fall` false, wave 2 passes 50 % | no story event, no cut-off line, Tarek keeps patrolling and firing, wave 2 clears | — |
| Zero timings | `approach_s` or `shield_s` 0 | that phase ends on the first step | — |

</intent-contract>

## Code Map

- `game/entities/allies/ally_ship.gd` -- the 6.4 ally to extend: `enum State { PATROL }` (l.29) gains `APPROACH, SHIELD, FALLING, GONE`; `step()` `match` (l.96); `_enter_state()` (l.103); `_tick_fire` (l.157) already gated by `_ended`; `_draw()` / `_build_outline()` (l.222+) and `OUTLINE_COLOR`/`BODY_COLOR`. Keep `patrol_step`, `nearest_target`, `aim` unchanged. Update the class doc.
- `game/entities/allies/ally_ship.tscn` -- add the `FireTrail` `GPUParticles2D` (copy the `SmokeTrail` pattern of `game/entities/projectiles/missile.tscn`: `ParticleProcessMaterial`, `GradientTexture1D`, additive `CanvasItemMaterial`, `local_coords = false`), `emitting = false`, `position = (0, 24)`.
- `game/autoloads/events.gd` l.40 -- `story_event_requested(event_name: StringName)`; `game/systems/waves/wave_director.gd` l.482 emits it from a `story_event` action, no await; the next action (`comms`) runs the same frame.
- `game/systems/comms/comms_channel.gd` -- read-only: `current_combat()`, `cut_phase()` (`CutPhase.HOLD` after the cut), `is_silenced()`, `step_combat(delta)`; the cut lands at `cut_off_at / comms.cutoff_chars_per_s` = 40 / 16 = 2.5 s, which `approach_s + shield_s` matches.
- `game/autoloads/audio.gd` -- read-only: `music_streams`, `play_music`, `current_music()` (`&""` once stopping), `stop_music(0.0)`; test pattern `_play_music()` in `tests/unit/test_comms_channel.gd` l.721 (silent looping WAV under a test id; erase it in teardown).
- `game/core/groups.gd` -- `Groups.PLAYER`; `game/core/playfield.gd` -- `Playfield.RECT`.
- `game/data/levels/level_dev_ally.json` -- template for the new `level_dev_tarek_fall.json` (`level_dev` key set, id 0).
- `game/data/dialogue/level_2.json` l.17 -- `l2_w5_tarek_cutoff` (combat, `cut_off_at` 40, `after`: silence until wave clear, `shake: cutoff`, `comms_static`, `music: stop`). Dialogue is loaded globally, so a dev level may reference it.
- `game/data/flags.json` -- `tarek_fall: true`; triggers read `Config.flags` at fire time, so a test can set `Config.flags["tarek_fall"] = false` before `_make_level` (`after_each` calls `Config.load_data()`).
- Tests: `tests/unit/test_ally_ship.gd` (fixtures for a bare AllyShip), `tests/unit/test_level.gd` (`_make_level` l.86, `_capture` l.32, `_ally_ships()` ~l.1557, `_kill_one_counted`, `test_dev_wave_2_cut_off_by_real_kills` l.1106 as the cut-off-by-real-kills pattern, `_wait_for_wave` l.1372), `tests/data/test_data_files.gd` (`test_dev_ally_level_shape` l.1190 pattern, `test_allies_tuning_ranges`).
- `_bmad-output/game-architecture.md` -- ends with `## As-built 2026-10-10 (Story 6.4)` then a `---` footer; append the 6.5 section before the footer.

## Tasks & Acceptance

**Execution:**
- `game/data/tuning.json` -- add `allies.fall` with the seven keys above. -- Data-driven.
- `game/tests/unit/test_ally_ship.gd` -- failing tests first for every I/O-matrix row except "Flag off": a bare AllyShip with `ally_id` tarek / ryn and a stub node in `Groups.PLAYER`, driven through `step()`; state sequence, positions (approach end, shield tracking, exit direction and speed both sides), `shield_visible()`, `is_damaged()`, damaged outline differs from the patrol one, trail emitting, no bolts after the event (spy spawner or `fire_clock` check), freed in GONE, the ignored cases, no player, zero timings, tuning reads. -- Red first.
- `game/entities/allies/ally_ship.gd` / `.tscn` -- the states, the event handler, accessors `shield_visible()`, `is_damaged()`, `fire_trail()`, `damaged_outline()`, the drawing and the `FireTrail` node, per the Always rules. -- FR35.
- `game/data/levels/level_dev_tarek_fall.json` -- `"name": "Development: Tarek's fall"`, `"ally": "tarek"`, `"convoy": false`, `music` null; wave 1: 6 Wasps `grid_3x2` top (`wave_start` wait 0.5); wave 2: 2 Lancers `grid_2x1` sides + 8 Wasps `grid_4x2` top, 2 medium asteroids, triggers `{ "when": "progress", "at": 0.5, "flag": "tarek_fall", "actions": [ { "story_event": "tarek_fall" }, { "comms": "l2_w5_tarek_cutoff" } ] }` and a `wave_clear` wait 0.5; wave 3: 8 Wasps `grid_4x2` top (`wave_clear` wait 0.5). -- The dev proof level.
- `game/tests/data/test_data_files.gd` -- `test_dev_tarek_fall_level_shape` (key set, Tarek, no convoy, exactly one trigger with `story_event` `tarek_fall`, flagged `tarek_fall`, at 0.5, whose actions are the story event then `l2_w5_tarek_cutoff`) and `allies.fall` ranges (durations ≥ 0, speed, radius, offset, hz > 0). -- Data guard.
- `game/tests/unit/test_level.gd` -- real `level.tscn` runs of `dev_tarek_fall`: (a) flag on: a silent test track playing as music, kill counted wave-2 enemies one by one until progress ≥ 0.5; then the `story_event` fired (Log line `story event 'tarek_fall'`), `current_combat()` is `l2_w5_tarek_cutoff`, the box is shown, the game is not paused, Tarek is in APPROACH; step physics frames until `cut_phase()` is HOLD: text ends with the suffix after 40 chars, `comms_static` played, `ShakeCamera.current_amplitude()` = `comms.cutoff_shake_px`, `Audio.current_music()` is `&""`, `is_silenced()`; Tarek reaches FALLING (damaged, trail on), then is freed with no AllyShip left; no `AllyBolt` spawned after the event; clearing wave 2 lifts the silence and wave 3 runs with no ally. (b) flag off: past 50 % no story-event line, no cut-off line, Tarek still in PATROL and firing, wave 2 clears to wave 3. -- Story ACs on the outer surface.
- `_bmad-output/game-architecture.md` -- append `## As-built 2026-10-10 (Story 6.5)`: the states, the event reaction, `allies.fall`, the dev level and its launch line `-- --level=dev_tarek_fall`, the readings in Design Notes, tests. -- Docs match the as-built.

**Acceptance Criteria:**
- Given `tarek_fall` is true and Tarek is the ally, when `Events.story_event_requested(&"tarek_fall")` fires, then Tarek's ship moves over Vale with a flashing shield ring, swaps to the damaged hull, trails fire, stops firing, exits past the screen edge and is gone for the rest of the level attempt.
- Given `level_dev_tarek_fall` on the real `level.tscn`, when wave 2 reaches 50 % destroyed, then the `l2_w5_tarek_cutoff` line plays as an interruption (no pause) and is cut mid-sentence, the dedicated cut-off shake (18 px for 0.9 s) fires, the music drops out, and comms stay silent until wave 2 clears.
- Given `tarek_fall` is false, when wave 2 reaches 50 %, then nothing happens, Tarek keeps flying and firing, and the wave still clears.
- Given the full GUT suite run headless, then every test passes with no new orphans or errors.

## Spec Change Log

## Review Triage Log

### 2026-10-10 — Review pass
- verdicts: 22 findings — high 0, medium 0, low 16, false 6, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) Tarek keeps shielding a dead Vale (`Player._die` hides the ship, never frees it) — real, but the level fails at that moment and the retry prompt follows; finishing the beat over the wreck is harmless, and the fix adds a Player-type guard.
  - `[low]` `[reject]` (blind) The fall keeps playing if the outcome is decided mid-beat — the 6.4 rule already keeps the ally moving after an outcome; a stop/freeze path adds states for a 2.5 s window nobody defined.
  - `[low]` `[reject]` (blind) `approach_s + shield_s` matching the 2.5 s cut is unenforced — it is a recorded tuning reading, not a rule; a test forcing equality would block the operator retuning either side.
  - `[low]` `[reject]` (blind) No validator rule ties `story_event: tarek_fall` to `"ally": "tarek"` — no shipped level can hit it before Epic 7, whose Story 7.2 places the beat with Tarek; a cross-key validator rule adds a branch for data nobody writes yet.
  - `[low]` `[reject]` (blind) `_draw_hull` draws an open polyline plus a closing line, overlapping strokes at the nose — the 2 px overlap at one vertex is imperceptible; it removes a per-redraw allocation that SHIELD would otherwise pay every frame.
  - `[low]` `[patch]` (blind) FireTrail position (0, 24) is a magic number tied to `ship_px` 64 — patched: `_ready` sets it to `Vector2(0, ship_px * TRAIL_Y_RATIO)` (0.375; still (0, 24) at 64). Other visual constants (stroke, segments, min alpha) follow the existing `OUTLINE_PX` const pattern.
  - `[false]` `[reject]` (blind) The exit side uses `SIZE.x / 2` while GONE uses `RECT` — `Playfield.RECT` is `Rect2(Vector2.ZERO, SIZE)` (`core/playfield.gd:7`), so both agree.
  - `[false]` `[reject]` (blind) The readings are design decisions missing from the decision log — the cut-off shake replacing "Large-tier" is already GDD decision #43 and FR35; the rest are record-only readings where the docs are silent, logged in the as-built section as in 6.1–6.4.
  - `[low]` `[reject]` (blind) The trail's live particles vanish when the ship is freed — GONE fires 64 px past the screen edge, so at most a short tail near the edge pops; letting it fade needs a reparent path.
  - `[low]` `[reject]` (blind) No test checks what `_draw` renders for the ring and damaged hull — `_draw` is a two-branch switch on the tested `is_damaged()` / SHIELD state; asserting draw calls needs a canvas spy for little gain.
  - `[low]` `[reject]` (blind) The flag-on test discards `_kill_to_half`'s count — only diagnostics on failure; the following assertions already report whether the event fired and the progress reached.
  - `[false]` `[reject]` (blind) The flag-off test's cleanup is inconsistent (`Log.sink`, flag) — `after_each` resets `Log.sink` and calls `Config.load_data()`, so nothing leaks.
  - `[false]` `[reject]` (edge) `exit_speed_px_s` 0 leaves Tarek in FALLING forever — `test_allies_fall_tuning_ranges` fails the suite on a non-positive value (the 6.4 data-guard pattern).
  - `[low]` `[patch]` (edge) The test music id `&"combat"` would overwrite then erase a real 8.1 track — patched: renamed `&"test_fall_silent"`.
  - `[low]` `[patch]` (edge) "No AllyBolt after the event" counted only bolts alive at the end — patched: every new AllyBolt id seen on each physics frame of both post-event waits (and at the end) is recorded and asserted empty.
  - `[low]` `[patch]` (edge) Same root cause as the row above (the claim that the level test proves no shots) — fixed by the same patch.
  - `[low]` `[patch]` (verification-gap) Vale freed during SHIELD → FALLING had no test — patched: `test_player_freed_mid_shield_falls_from_where_it_is`.
  - `[low]` `[reject]` (verification-gap, other) A dead (hidden, not freed) Vale keeps the shield going — same as the first blind row.
  - `[low]` `[reject]` (intent) Visuals are tested through state flags, not rendering — same as the `_draw` row; headless tests can't judge visibility, and feel is never claimed.
  - `[low]` `[reject]` (intent) The shake's 0.9 s duration isn't checked in the level test — `test_comms_channel.gd` (Story 5.4) already covers the cut-off shake and `ShakeCamera` decay; this story changes neither.
  - `[false]` `[reject]` (intent) The beat is proved only on a dev level, not the Blockade — the AC itself names a dev level; Epic 7 Story 7.2 places it in Level 2 Wave 5.
  - `[false]` `[reject]` (intent) The "memorable moment" should be an `operator_actions` debt — none of 6.5's ACs needs a human outside the repo (unlike 6.4's kill-share AC); feel is a normal playtest, so the story finishes `done`.

## Design Notes

**Readings this spec records (no GDD conflict).** "Moves over Vale" = glides to a point 80 px above Vale (between Vale and the enemy fire coming down) and holds there, tracking Vale. The "shield flash" is a visual coalition ring around Vale; it blocks nothing, because allies block nothing (epic rule) and nothing in the GDD gives Vale invulnerability here. `approach_s + shield_s` = 2.5 s matches the cut moment of `l2_w5_tarek_cutoff` (40 chars at 16 chars/s), so the damaged swap lands with the static and the shake without the ally listening to comms (the epic says it reacts only to the story event). "Exits the screen" = flies off the nearer side edge with a slight downward drift. "Large-tier shake" in the epic AC is superseded by the dedicated cut-off shake (GDD decision #43), which the dialogue data already selects. The damaged hull and fire are code-drawn placeholders until Epic 8 art.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass (see `LOCAL.md` for `<GODOT_DIR>`)

**Manual checks (if no CLI):**
- Operator: play `level.tscn -- --level=dev_tarek_fall` and judge whether the fall reads as the memorable beat (timing against the cut, shield ring, fire trail, exit). Feel is never claimed verified by tests.

## Auto Run Result

Status: done

**Summary:** Story 6.5 (FR35, SHOULD, last to cut) is built. A Tarek `AllyShip` now reacts to `Events.story_event_requested(&"tarek_fall")`. From `PATROL` it stops firing and glides over Vale (`APPROACH`, 1.0 s smoothstep to Vale + (0, -80), tracking him), then holds there while a coalition shield ring flashes around Vale (`SHIELD`, 1.5 s, 8 Hz, visual only). Next it swaps to the damaged hull (right wing tip broken, dark body, `danger` outline), lights its `FireTrail` and flies off the nearer side edge at 320 px/s with a slight drop (`FALLING`). Once past the screen edge it is freed (`GONE`) and never returns that attempt. Ryn, other events and repeat events are ignored, and with no Vale it falls from where it is. The 2.5 s approach plus shield matches the `l2_w5_tarek_cutoff` cut moment (40 chars at 16 chars/s), so the damaged swap lands with the static and the shake. All timings are in the new `tuning.allies.fall`. The new `level_dev_tarek_fall.json` fires `story_event: tarek_fall` then `comms: l2_w5_tarek_cutoff` at 50 % of wave 2, gated by the `tarek_fall` flag. The existing Story 5.4 machinery supplies the no-pause interruption, the mid-sentence cut, the dedicated cut-off shake (18 px, 0.9 s), the music stop and the silence until the wave clears. No comms, wave, audio or feedback code changed.

**Files changed:**
- `game/entities/allies/ally_ship.gd`: the fall states, the event handler, the shield ring, the damaged hull, the trail and new accessors.
- `game/entities/allies/ally_ship.tscn`: the `FireTrail` GPUParticles2D (energy to danger to transparent, additive, world-space).
- `game/data/tuning.json`: `allies.fall` (7 keys).
- `game/data/levels/level_dev_tarek_fall.json` (new): the 3-wave proof level (`-- --level=dev_tarek_fall`).
- `game/tests/unit/test_ally_ship.gd`: 22 fall tests covering every I/O-matrix row except "Flag off".
- `game/tests/unit/test_level.gd`: real `level.tscn` runs of `dev_tarek_fall` with the flag on and off.
- `game/tests/data/test_data_files.gd`: the dev level shape and the `allies.fall` ranges.
- `_bmad-output/game-architecture.md`: `## As-built 2026-10-10 (Story 6.5)`.

**Review findings:** 22 (high 0, medium 0, low 16, false 6).
- Patched (4 entries, 5 rows, all low):
  - the trail position now derives from `ship_px`;
  - the test music id is unique;
  - the level test records every ally bolt seen after the event, frame by frame;
  - a new test covers Vale freed during SHIELD.
- Deferred: none.
- Rejected, each with its reason in the Review Triage Log:
  - a dead (hidden) Vale still shielded (2 rows);
  - the fall continuing after an outcome;
  - the unenforced 2.5 s timing match;
  - no validator rule tying the story event to Tarek;
  - the open polyline plus closing line in `_draw_hull`;
  - the trail particles popping off-screen;
  - no rendering test for `_draw` (2 rows);
  - the discarded kill count;
  - the shake duration not checked at level scope;
  - 6 false findings (the `RECT` midpoint, the decision log, test cleanup, zero exit speed, dev-level placement, operator debt).

**Follow-up review recommended:** false. Only low entries were patched (4), none high or medium.

**Verification:**
- `--import` exited 0.
- The full headless GUT suite passed 1584/1584 before the patches and 1585/1585 after, with no failures.
- Every I/O-matrix row has a covering test that ran and passed.

**Residual risks:**
- Feel is not checked by tests: whether the fall reads as the memorable beat (timing against the cut, the ring, the trail, the exit). Judge it by playing `level.tscn -- --level=dev_tarek_fall`.
- If Vale dies mid-beat, Tarek finishes it over the hidden wreck.
- The damaged hull and fire are placeholders until Epic 8 art.
- `level_2.json` gets the beat in Epic 7 (Story 7.2).
