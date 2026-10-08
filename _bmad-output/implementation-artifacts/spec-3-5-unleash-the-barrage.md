---
title: 'Story 3.5: Unleash the Barrage'
type: 'feature'
created: '2026-10-08'
baseline_revision: 'cdb7f5285fe82cc4619b19a646f1132be7d18c04'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-3-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Energy can buy a Shield (3.4) but Q does nothing, so a full 100 energy has no panic-button answer to a crowded screen. Covers FR16, FR17 (barrage half) and FR31 (Barrage). SHOULD tier.

**Approach:** `Player.try_barrage()` (on the `ability_barrage` action) spends `abilities.barrage.cost` through `GameState`, or denies through the existing `_deny(&"barrage")`. `PlayerWeapons` then runs the volley: 12 `micro_missile` projectiles, one every `duration_s / missiles`, each with a `barrage_whoosh` SFX, and a Large-tier `Feedback.impact` at the muzzle right after the last launch. A new `MicroMissile` projectile homes on the nearest enemy, chosen once at launch.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript. Every number comes from `Config`. Existing keys: `abilities.barrage` {`cost` 100, `missiles` 12, `duration_s` 2.0, `damage` 6}. New keys in `abilities.barrage`: `speed_px_s` 800, `turn_rate_deg_s` 540, `lifetime_s` 3.0.
- **Player** (`try_barrage() -> bool`): dead → false, nothing else. Volley already running → false, no spend, no event, no SFX. `GameState.energy < cost` → `_deny(&"barrage")`, false. Otherwise `GameState.add_energy(-cost)`, `_weapons.start_barrage()`, one `Log.info("combat", ...)`, true. `_physics_process` (alive only) calls `step_barrage(delta)` (a one-line delegator) and then `try_barrage()` on `Input.is_action_just_pressed(&"ability_barrage")`. Read the action only. `_die()` calls `_weapons.stop_barrage()`, so there are no more launches and no finish. `is_barraging()` delegates.
- **PlayerWeapons volley:** `start_barrage()` sets `missiles` left and launches the first one at once. `step_barrage(delta)` counts physics delta down (frozen under pause and hit-stop) and launches each time the countdown reaches ≤ `FIRE_EPS`, adding `interval = duration_s / missiles`, so a 60 Hz run launches on ticks 0, 10, 20, … 110. The tick of the 12th launch also plays `Feedback.impact(ImpactTier.LARGE, muzzle global_position)`, once. Each launch spawns `&"micro_missile"` through the Spawner at the muzzle with `velocity = Vector2.UP * speed_px_s` and `damage`, then plays `Audio.play_sfx(&"barrage_whoosh")` (default jitter) and shows the muzzle flash. A launch with no spawner, or a null spawn, still counts but plays nothing. `missiles <= 0` or `duration_s <= 0` logs `Log.warn("data", ...)` once in `_ready`, and `start_barrage` then does nothing (the energy is still spent, as with the shield's mistuned-data rows). Accessors: `is_barraging()`, `barrage_left() -> int`, `stop_barrage()`.
- **MicroMissile** (`entities/projectiles/micro_missile.gd`/`.tscn`, `class_name MicroMissile extends Projectile`): scene layer `PLAYER_SHOTS` (2), mask `MASK_PLAYER_SHOTS` (84), `monitorable = false`. A `Hitbox` `CapsuleShape2D` along local Y with height ≥ `speed_px_s / 60` (radius 4, height 16), and an additive coalition `#22E6FF` `Polygon2D` body. `impact_tier` stays SMALL. `_ready` reads speed, turn rate and lifetime, calls `super._ready()`, then picks the target once: `MicroMissile.nearest_enemy(global_position, get_tree().get_nodes_in_group(&"enemies"))`. Static `nearest_enemy(from, nodes) -> Node2D` skips non-`Node2D` nodes, nodes queued for deletion, and `Enemy` nodes with `is_dead()`. It returns null when none is left, and the first node wins on a tie.
  - `_physics_process(delta)`: age += delta, and at `age >= lifetime_s` it frees itself (no impact). If it had a target and `not is_instance_valid(target) or target.is_queued_for_deletion()`, re-pick once. If that finds nothing, it never scans again. Then steer: `velocity = MicroMissile.steer(velocity, desired_dir, deg_to_rad(turn_rate) * delta)`, where `desired_dir` points at the target, or `Vector2.UP` with no target. Set `rotation = velocity.angle() + PI / 2`, then `super._physics_process(delta)`. Static `steer(v, desired, max_turn_rad) -> Vector2` rotates `v` toward `desired` by at most `max_turn_rad` and keeps its length. Accessor `target() -> Node2D` (null when there is none or it is invalid).
  - Hits use the base Projectile path: the first enemy, asteroid or convoy area overlapped takes `damage` (6), and the missile frees itself. So asteroids block it.
- Register `&"micro_missile"` in `EntityRegistry.PROJECTILES`.
- **SFX:** append `barrage_whoosh` (a ~0.18 s rising filtered-noise whoosh with its own `BARRAGE_WHOOSH_SEED = 3501`) to `tools/gen_placeholder_sfx.py` so the existing WAVs stay byte-identical. Register it in `Audio.SFX` and add a CREDITS row.

**Never:**
- No per-frame group scans or allocations in `MicroMissile` or the volley tick (the only scans are at launch and on target loss). No `instantiate` outside Spawner. No bare `print()`, no per-tick logging.
- No E/Q control hints (Epic 5), no barrage HUD timer, no new Events signal. No change to the Shield or to the EnergyBar flash (it already reacts to any `ability_denied`).
- Denial never spends or starts a volley. A running volley is never restarted or extended.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Activate | energy 100, Q | energy 0, `energy_changed(0,100)`, 1 micro-missile at the muzzle on the press tick, `barrage_whoosh` played | n/a |
| Cadence | 60 Hz `step_barrage(DT)` | 12 launches total on ticks 0,10,…,110; none after | n/a |
| Finish | the 12th launch | exactly one Large explosion (scale 2.0) at the muzzle, hit-stop starts | n/a |
| Denied | energy 99, Q | energy 99, `ability_denied(&"barrage")` once, `ability_denied` SFX, no missiles | n/a |
| No restart | volley running, energy 100, Q | false, energy 100, launches unchanged, no `ability_denied` | n/a |
| Dead | dead ship, Q | nothing | n/a |
| Death mid-volley | dies after 5 launches | no more launches, no finish | n/a |
| Pause | volley running, tree paused | no launches while paused; resumes after | n/a |
| Nearest | enemies at 300 px and 100 px | targets the 100 px one; dead or queued enemies are skipped | n/a |
| No re-scan | a nearer enemy is added after launch | target unchanged | n/a |
| Re-pick | target freed, another alive | targets the remaining one | n/a |
| No enemies | none alive | velocity stays `UP * speed` | n/a |
| Steer | desired 90° off, max 0.1 rad | turns 0.1 rad, same length | n/a |
| Asteroid | overlaps an asteroid | asteroid takes 6, missile freed | n/a |
| Lifetime | `lifetime_s` elapsed | freed, no impact feedback | n/a |

</intent-contract>

## Code Map

- `game/entities/player/player.gd` -- `_physics_process` at line 137 (add `step_barrage` and the Q read after the shield). `_deny` at line 266 is reused as is. `_die()` at line 179 (add `stop_barrage`). `try_shield` at line 235 is the model for `try_barrage`. Delegators sit at lines 365-372. Add a "Barrage (Story 3.5)" paragraph to the class doc.
- `game/entities/player/player_weapons.gd` -- the volley lives here next to the missile. `_can_spawn` at line 75, the `step_missile` spawn and flash at lines 123-132 and `FIRE_EPS` are the patterns. Add `MICRO_TYPE` and `WHOOSH_SFX` consts and update the class doc.
- `game/entities/projectiles/missile.gd` + `missile.tscn` -- the template for the scene (layer 2, mask 84, `monitorable=false`, capsule, additive `Polygon2D`) and for `rotation = velocity.angle() + PI/2`.
- `game/core/projectile.gd` -- the base: `setup`, `_physics_process` (move and off-screen free), `_on_area_entered`. Don't change it.
- `game/core/enemy.gd:91` `is_dead()`, and `_die()` queue_frees at line 103. Enemies join the `enemies` group at line 68.
- `game/autoloads/entity_registry.gd:17` -- `PROJECTILES`.
- `game/autoloads/feedback.gd:74` `impact(tier, pos)`. A Spawner whose world has an `Effects` node registers itself, and tests count `Explosion` children there. `Feedback.reset()` goes in `after_each`.
- `game/autoloads/audio.gd:9` -- the `SFX` registry. `tools/gen_placeholder_sfx.py` -- seeds at lines 21-24 and `main()`. `game/assets/CREDITS.md` -- add the row after `sfx_ability_denied.wav`.
- `game/data/tuning.json:40` -- `abilities.barrage`.
- `game/project.godot:66` -- `ability_barrage` = Q already exists.
- `game/tests/unit/test_player_missile.gd` -- the world, Spawner and Player harness (add an `Effects` container for the finish). `test_player_shield.gd` -- the energy, input and pause test patterns. `test_projectile.gd:123-146` -- the layer and capsule-tunnelling test pattern. `tests/data/test_data_files.gd:362` -- the shield data test pattern.
- `_bmad-output/game-architecture.md` -- built parts at line 563 (barrage, `micro_missile`), the tree at line 597, the Player row at line 668 (Built Story 3.5 API, drop "Planned: barrage"), and the homing row at line 1222.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_micro_missile.gd` (new), `test_player_barrage.gd` (new), `test_audio.gd`, `tests/data/test_data_files.gd` -- write these FIRST and cover every I/O row. In the barrage tests, set `GameState.energy` directly and reset it in `after_each`. Include one real-input test: physics on, `Input.action_press(&"ability_barrage")`, await a physics frame, release, then assert energy 0 and one micro-missile. The data test pins cost 100, missiles 12, duration 2.0 and damage 6 (GDD), and checks that the new keys are positive.
- `game/data/tuning.json` -- the new keys.
- `game/entities/projectiles/micro_missile.gd`, `micro_missile.tscn` -- NEW. `game/autoloads/entity_registry.gd` -- register it.
- `game/entities/player/player_weapons.gd`, `player.gd` -- the volley and Q.
- `tools/gen_placeholder_sfx.py`, `game/assets/audio/sfx/sfx_barrage_whoosh.wav`, `game/autoloads/audio.gd`, `game/assets/CREDITS.md` -- the SFX. Regenerate, confirm that only the new WAV is added, then run `--import` (new class_name and WAV).
- `_bmad-output/game-architecture.md` -- the as-built notes from the Code Map.

**Acceptance Criteria:**
- Given a level is running with 100 energy, when Q is pressed, then `HUD/EnergyBar` drops to 0 and 12 micro-missiles launch from the muzzle over 2.0 s with a whoosh each. Each deals 6 damage on `player_shots`, homes on the nearest enemy, and is stopped by asteroids.
- Given a barrage is running, when its 12th micro-missile launches, then one Large-tier feedback plays at the muzzle.
- Given < 100 energy, when Q is pressed, then nothing fires, `Events.ability_denied(&"barrage")` fires, the `ability_denied` SFX plays and the energy bar flashes.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 25 findings — high 0, medium 0, low 16, false 9, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: `nearest_enemy` can pick an enemy still on its off-screen entry path, and a missile that curves past bounds + 64 px is freed. Real but rare: entries move on-screen while an 800 px/s missile crosses the ~900 px climb. The fix would add a playfield filter, which changes targeting semantics the GDD ("seeks the nearest enemy") doesn't ask for.
  - `[low]` `[patch]` Blind: `MicroMissile.speed` is read but never used, because movement keeps the spawn velocity's length. Fixed by deleting the field, its Config read and its test assert. `PlayerWeapons` still applies `speed_px_s` at launch.
  - `[low]` `[reject]` Blind: nothing warns at runtime about non-positive `speed_px_s`, `turn_rate_deg_s` or `lifetime_s`. Only mistuned data reaches this, `test_data_files` pins the shipped values as positive, and the fix would add guards.
  - `[low]` `[reject]` Blind: the LARGE finish plays even when no micro-missile spawned (no spawner, or a null spawn). Every game scene injects a Spawner (`level.gd:35`, sandbox), so players never hit this. The fix would add state to track whether anything spawned.
  - `[low]` `[reject]` Blind: the mistuned-data test covers only `missiles = 0`; the log says "Barrage" with nothing firing; repeated Q presses spend again. All of this is mistuned data only, and the spec accepts spending in that case (as with the shield's duration ≤ 0 rows).
  - `[false]` `[reject]` Blind: `_target_alive` doesn't check `is_dead()`. `Enemy._die()` (`core/enemy.gd:95-103`) sets `_dead` and calls `queue_free()` in the same call, so a dead enemy is always queued and `_target_alive` already rejects it.
  - `[false]` `[reject]` Blind: the WAV is missing from the diff. The review diff deliberately excluded `*.wav`. `git status` shows `sfx_barrage_whoosh.wav` added, and regenerating changes no other WAV.
  - `[false]` `[reject]` Blind: E and Q pressed on the same tick buy the shield and deny the barrage. With 100 energy the shield leaves 50, so denying the barrage is the specified rule (cost 100). This is not a defect.
  - `[low]` `[reject]` Blind: no hit-stop freeze test, and hits are injected through `_on_area_entered`. Under `time_scale = 0` no physics tick runs, so the volley freezes by construction (as in 3.4). Real-overlap hits are covered for the shared Projectile base by `test_projectile.gd:98`.
  - `[false]` `[reject]` Blind: the reused `MISSILE_FLASH_S` breaks the data-driven rule. That rule covers GDD numbers. The flash length is a documented art constant (`player_weapons.gd:17`) that the GDD doesn't specify.
  - `[low]` `[reject]` Edge: the finish plays with no spawn. Same as the Blind row: no game path reaches it.
  - `[low]` `[reject]` Edge: no warning for `speed_px_s <= 0`. Mistuned data only; the fix is a guard.
  - `[low]` `[reject]` Edge: `lifetime_s <= 0` frees every missile on its first tick. Mistuned data only; the fix is a guard.
  - `[low]` `[patch]` Edge: speed is never applied in MicroMissile. Same root cause as the Blind unused-`speed` row, fixed by the same deletion.
  - `[low]` `[reject]` Edge: off-screen nearest enemy. Same as the Blind row.
  - `[false]` `[reject]` Edge: a non-Enemy group member that is dead but not queued. Only `Enemy` subclasses join `enemies` (`core/enemy.gd:68`), and their death queues them at once.
  - `[low]` `[patch]` Verification gap: no test pins the press-tick order (`step_barrage` before the Q read) in `_physics_process`. Added `test_physics_process_steps_before_reading_q`: Q is pressed through `_physics_process`, there is 1 launch after 9 more ticks and 2 after the 10th.
  - `[false]` `[reject]` Intent: R2 (the playtest as owed operator actions, so `awaiting-operator`). The intent's examples are actions outside the repo. A feel playtest is the project's standard manual check (same ruling as in 3.3 and 3.4).
  - `[low]` `[reject]` Intent: no `level.tscn` integration test. The level already injects the Spawner (`level.gd:35`), and each link is tested where it connects.
  - `[low]` `[reject]` Intent: the bar drop and flash are asserted at `GameState` and `Events`, not on the `HUD/EnergyBar` node. 3.3's level test covers `energy_changed` → bar, and 3.4's `test_energy_bar` covers `ability_denied` → flash.
  - `[low]` `[patch]` Intent: the whoosh was asserted only on the first launch. The cadence test now checks the newest SFX on every launch tick: `barrage_whoosh` for launches 1–11, and `explosion_large` on the 12th, because the finish plays right after that launch's whoosh.
  - `[low]` `[reject]` Intent: no test shows that volley-launched missiles home. The volley spawns the same `micro_missile` scene through the registry, and the homing tests cover it.
  - `[false]` `[reject]` Intent: re-picking on queued-for-deletion goes beyond the epics wording. A queued node is freed at the end of the frame, so this is the same "freed" condition one tick earlier, and the spec contract requires it.
  - `[false]` `[reject]` Intent: no commit made. The commit happens at finalize.
  - `[false]` `[reject]` Intent: the finish lands at ~1.83 s, not 2.0 s. The AC says "when the last micro-missile has fired", and the cadence is recorded in the Design Notes.

### 2026-10-08 — Review pass
Follow-up pass on the `done` spec.
- verdicts: 27 findings — high 0, medium 0, low 22, false 5, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: mistuned `missiles`/`duration_s` still spends 100 energy and returns true. Carried: the same claim as the earlier mistuned-data row. The spec's Always clause accepts the spend, as with the shield's mistuned-data rows.
  - `[low]` `[reject]` Blind: the LARGE finish plays after a volley with no spawner or failed spawns. Carried: the earlier finish-without-spawn row. Every game scene injects a Spawner (`level.gd:35`, sandbox).
  - `[low]` `[reject]` Blind: no runtime warning for non-positive `damage`, `speed_px_s`, `turn_rate_deg_s` or `lifetime_s`. Carried: the earlier no-runtime-guards rows. Mistuned data only, `test_data_files` pins the shipped values as positive, and the fix adds guards.
  - `[low]` `[patch]` Blind: `game-architecture.md` has no "As-built 2026-10-08 (Story 3.5)" section, though 3.3 and 3.4 each record their tuning keys, cue and behaviour there. Verified at lines 1537-1567. Fixed by adding that section, which records the barrage flow, the volley cadence, MicroMissile, the `barrage_whoosh` cue and the three new first-pass tuning defaults.
  - `[false]` `[reject]` Blind: the queued-for-deletion re-pick and the give-up rule go beyond the contract and are not recorded. Carried: the earlier queued re-pick row. The spec contract requires both, and the architecture homing row records them.
  - `[low]` `[reject]` Blind: `level_cleared` doesn't stop a running volley, so the finish can land over the clear banner. Real, but a cleared level keeps every player action live today (laser, missile, shield). Post-clear flow belongs to Epic 4, and the intent doesn't ask the barrage to react to clears. Fixing it here would add a new signal subscription and state to `Player`.
  - `[low]` `[reject]` Blind: a missile can lock onto an enemy still off-screen. Carried: the earlier off-screen entry row.
  - `[low]` `[reject]` Blind: no test runs a missile all the way to a hit on an offset or moving target, and the ~85 px turn radius could orbit. Homing feel is a manual playtest item. `steer`, targeting and the hit path are each unit-tested, and an end-to-end flight test would need moving physics with real frames (a flakiness risk) for a tuning question.
  - `[low]` `[reject]` Blind: barrage tuning is read both in `PlayerWeapons` and in `MicroMissile._ready`. The spec specifies this split (`_ready` reads speed, turn rate and lifetime). No caller diverges today: both read the same `Config` keys. Moving them would change public spawn params.
  - `[low]` `[reject]` Blind: the barrage-specific bar flash is untested. Carried: the earlier HUD-asserted-through-`Events` row. 3.4's `test_energy_bar` covers `ability_denied` → flash.
  - `[false]` `[reject]` Blind: the WAV is missing from the diff. Carried: the review diff excludes `*.wav`. The WAV is tracked in HEAD, and regenerating this pass left `git status game/assets/audio/sfx` empty.
  - `[low]` `[reject]` Edge: finish with no spawn (`player_weapons.gd:206-212`). Carried: same as the Blind finish row.
  - `[low]` `[reject]` Edge: the mistuned barrage still spends. Carried: same as the Blind mistuned row.
  - `[false]` `[reject]` Edge: a missile launched with no enemies never homes on enemies that appear later. This is the specified behaviour. The intent says the target is "chosen once at launch", the matrix's "No enemies" row says the velocity stays `UP * speed`, and the Never clause forbids per-frame scans.
  - `[low]` `[reject]` Edge: `lifetime_s <= 0` frees every missile at once. Carried: the earlier lifetime guard row.
  - `[low]` `[reject]` Edge: `speed_px_s <= 0` gives a missile no warning and no motion. Carried: the earlier speed guard row.
  - `[low]` `[reject]` Edge: with an interval shorter than one physics tick, only one launch happens per tick, so the volley runs long. Only reachable with more than 120 missiles per 2 s (shipped: 12). The laser uses the same one-shot-per-tick rule (`player_weapons.gd:119`), and a catch-up loop would need a cap and a new finish ordering.
  - `[low]` `[reject]` Edge (claim): the docstring "still counts but plays nothing" vs the LARGE finish. Carried: same root cause as the finish-without-spawn rows.
  - `[false]` `[reject]` Edge (claim): the volley ends at ~1.83 s, not 2.0 s. Carried: the earlier 1.83 s row. The cadence is recorded in the Design Notes.
  - `[low]` `[reject]` Intent: the no-spawner finish reading is untested. Carried: same root cause as the finish-without-spawn rows. No game path reaches it.
  - `[low]` `[reject]` Intent: the hit-stop freeze is never tested. Carried: the earlier hit-stop row. Under `time_scale = 0` no physics tick runs.
  - `[false]` `[reject]` Intent: a dead-but-not-queued Enemy stays the target. Carried: the earlier `is_dead` liveness row. `Enemy._die()` sets `_dead` and calls `queue_free()` in the same call.
  - `[low]` `[reject]` Intent: no test covers a second target loss after a successful re-pick. The code is one branch (`_gave_up` is set only when a re-pick returns null), so a second loss follows the same path the Re-pick test already covers. Adding a test costs more than the risk it covers.
  - `[low]` `[reject]` Intent: hits and asteroid blocking are tested through a direct `_on_area_entered`, not a physics overlap. Carried: the earlier real-overlap row. `test_projectile.gd:98` covers real overlap for the shared base.
  - `[low]` `[reject]` Intent: tests use direct method calls and never load `level.tscn`. Carried: the earlier level-integration and direct-instance rows.
  - `[low]` `[reject]` Intent: no test checks that the older WAVs stay byte-identical. Checked by this pass's verification instead: regenerating left `git status game/assets/audio/sfx` empty. A test would need to run the Python generator from GUT.
  - `[low]` `[reject]` Intent: no stress or bench run covers the crowded-screen case. The perf rule (no per-frame scans or allocations) is met by construction, and the E1 `--bench` path already exists for a manual run. Benching after a visual change is a project-wide practice, not this story's acceptance.

## Design Notes

- **Cadence:** "about one every 0.17 s" fixes the interval at `duration_s / missiles` (2.0 / 12). Each launch sits at the start of its 1/12 slot of the 2.0 s window, so the last launches at about 1.83 s and the finish plays then ("when the last micro-missile has fired").
- **Finish position:** the AC ties the finish to the last launch, not to an impact, so it plays at the muzzle, the only point that belongs to that moment.
- **New tuning:** the GDD gives no micro-missile speed, turn rate or lifetime. These are first-pass data defaults, as with 3.3's `orb_magnet_speed_px_s`: 800 px/s, with 540°/s giving about an 85 px turn radius. `lifetime_s` frees a missile that circles a target it can't reach.
- **Volley in PlayerWeapons:** the energy, denial and death rules stay on `Player` (the ability state owner). Launch timing reuses the weapon node's spawner, muzzle, flash and `FIRE_EPS`, like the missile.

## Verification

**Commands:**
- `uv run python tools/gen_placeholder_sfx.py` then `git status --short game/assets/audio/sfx` -- expected: only `sfx_barrage_whoosh.wav` is new.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0 (`<GODOT_DIR>` from `LOCAL.md`).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failures, no new SCRIPT ERRORs.

**Manual checks (if no CLI):**
- The homing feel, the whoosh cascade and the finish need a human playtest.


## Auto Run Result

Status: done

This was a follow-up review pass on the `done` spec. It was not a re-implementation.

**Summary:** Story 3.5 (FR16, FR17 barrage half, FR31 Barrage).
- With at least 100 energy, Q (`ability_barrage`) spends the cost through `GameState` and starts a volley in `PlayerWeapons`.
- The volley fires 12 homing `MicroMissile`s over 2.0 s (60 Hz ticks 0…110). Each launch plays `barrage_whoosh` and the muzzle flash, and the 12th launch also plays one LARGE `Feedback.impact` at the muzzle.
- With less than 100 energy, Q is denied through `_deny(&"barrage")`. A running volley is never restarted, and death stops it.

**Files changed in this pass:**
- `_bmad-output/game-architecture.md`: added the "As-built 2026-10-08 (Story 3.5)" section, in line with 3.3 and 3.4.
- `_bmad-output/implementation-artifacts/spec-3-5-unleash-the-barrage.md`: this pass's triage log and result.

**Files from the original implementation (commit `7de27431d57371cb1047ef7579429bb64271ae9e`):**
- `micro_missile.gd`/`.tscn`: the homing projectile.
- `player_weapons.gd`: the volley.
- `player.gd`: `try_barrage` and the Q read.
- `entity_registry.gd`, `audio.gd`: registrations.
- `tuning.json`: three new keys.
- `gen_placeholder_sfx.py`, plus the WAV, its `.import` and CREDITS: the whoosh.
- The tests: `test_micro_missile.gd`, `test_player_barrage.gd`, `test_audio.gd`, `test_data_files.gd`.

**Review findings:** 27 findings (high 0, medium 0, low 22, false 5).
- **Patched (1, low):** the missing architecture as-built section.
- **Deferred:** none.
- **Rejected:** each with the reason in the triage log above.
  - Carried from the first pass:
    - mistuned-data spend
    - the finish with no spawn (×4)
    - no runtime guards (×3)
    - queued re-pick
    - off-screen targets
    - the HUD flash asserted through `Events`
    - the WAV missing from the diff
    - the 1.83 s finish
    - hit-stop
    - `is_dead` liveness
    - real-overlap hits
    - level integration
  - New this pass:
    - the volley continues past `level_cleared` (Epic 4 owns the post-clear flow)
    - no end-to-end homing flight test (manual playtest item)
    - tuning read in two places (as specified)
    - no homing on enemies that appear later (as specified, so false)
    - a sub-tick interval (unreachable with shipped data)
    - no second-loss re-pick test
    - no WAV byte-identity test (checked by the regen)
    - no crowded-screen bench run

**Follow-up review recommended:** false. On a follow-up pass, a further review is recommended only if this pass patched a high. It patched none (high 0, medium 0, low 1).

**Verification:**
- `uv run python tools/gen_placeholder_sfx.py` wrote 10 WAVs. `git status --short game/assets/audio/sfx` is empty, so no WAV changed.
- `--headless --path game --import` exits 0.
- The full GUT suite exits 0: 871 tests, 871 passing, 7712 asserts, "All tests passed".

**Residual risks:**
- The homing feel (about an 85 px turn radius), the whoosh cascade and the finish need a human playtest.
- A volley running when the level clears keeps launching, and its finish lands over the clear banner. Epic 4's post-clear flow should decide this.
- A micro-missile chasing an enemy still on its off-screen entry path may be freed without a hit.
