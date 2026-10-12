---
title: "Story 7.3: Face the Flagship's Turrets (Phase 1)"
type: 'feature'
created: '2026-10-12'
status: 'awaiting-operator'
operator_actions:
  - 'Run "<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game res://scenes/level/level.tscn -- --level=dev_boss in a debug build, press F6, and confirm the level jumps to the boss wave: the Flagship flies in from the top and stops at its station, and the boss bar cross-fades in over the wave bar.'
  - 'In that run, judge whether the four turret glows (0.5 s) read clearly before each staggered 3-bullet spread, and whether the spreads are fair to dodge; any retune goes in game/data/tuning.json (boss.turrets) with a GDD decision-log entry.'
  - 'Judge whether the 2 medium cover asteroids give usable cover during Phase 1, given they spawn when the boss wave starts and drift through during the arrival.'
  - 'Destroy all four turrets and confirm each plays a clear Boss-part explosion (bigger than a Lancer, with a short shake and hit-stop), drops an energy orb, and drains the boss bar to the 66.7 % marker; the Flagship then holds in Phase 1 until Story 7.4 (press F3 to move on).'
  - 'Confirm or overrule the provisional readings in GDD decision-log row 54 (unaimed ±15° turret spread, 0.75 s stagger, the hull as armour that blocks shots, cover asteroids at boss-wave start, station y 170 / 3.0 s arrival, parts hanging below the hull), and update the row status accordingly.'
baseline_revision: 'a638003b45313ac066ab580846f8a6ad2c6e099b'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-7-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A `{ "boss": "flagship" }` wave currently logs "does not exist yet (Epic 7)" and is subtracted. The final fight has no Flagship, no turrets, no boss bar and no hull contact (FR49, FR52, FR53, FR30 boss part).

**Approach:** Add the Flagship entity (`entities/boss/`). It is an armoured hull with 4 turrets and an invulnerable core, and it runs the `Phase` state machine through `ARRIVING` → `TURRETS`. The WaveDirector spawns it through the `Spawner`, counts it as 1 and resolves it only on `Events.boss_defeated`. Add the HUD `BossBar`, which cross-fades in over the wave bar. Add a dev level with a boss wave for F6 and manual play. All numbers come from `tuning.boss` / `tuning.hud`.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript. Write the failing GUT test first. Read every number through `Config`. Log through `Log`. Only `Spawner` instantiates, only `Feedback` touches time scale, and the HUD reads `Events` only (Config for layout and data is fine, as WaveBar does).
- The Phase enum, in this exact order: `enum Phase { ARRIVING, TURRETS, CORE, FINAL_CHOICE, DESPERATE, DYING }`. `Events.boss_phase_changed(int(phase))` fires on every phase entry, including `ARRIVING` (0) and `TURRETS` (1). Story 7.4 relies on `CORE` being 2.
- Cadence is start-to-start (decisions #38, #50, #52). Each turret fires every `boss.turrets.fire_interval_s`. Its Glow shows for the last `telegraph_s` of each period, and then it fires. Turret `i` (scene order) starts its first period `i * boss.turrets.stagger_s` after `TURRETS` begins, so its first shot is at `i*stagger_s + fire_interval_s`.
- A spread is `spread_bullets` `enemy_bullet`s, evenly spaced from `-spread_deg` to `+spread_deg` around straight down, at `bullet_speed_px_s`, with `damage.bullet_hearts`. It is never aimed (like the Bastion; the GDD calls only the desperate spread "aimed").
- Combined HP = Σ max(part hp, 0) over the 4 turrets and the core (300 with shipped data). `Events.boss_hp_changed(current, max, int(phase))` fires on spawn, on each phase entry and on every part HP change.
- Collision follows the architecture's damage rule. The hull, turrets and core are all `Enemy` areas on the `enemies` layer (bit 4) with mask 0. Projectiles hit whatever they overlap first. The hull is armour: shots on it are spent, and `apply_damage` is ignored. Shots on the core are also spent and ignored while it is invulnerable (all of Story 7.3). No turret or core hitbox overlaps the hull hitbox, so a shot from below always reaches a part before the hull.
- Hull or part contact costs `damage.contact_large_hearts` (2) through the existing Player contact path (tier not small/medium). Contact never destroys the Flagship or its parts.
- The hull and an invulnerable core are not targets: micro-missiles and the ally ship skip them. Turrets are targets.
- The boss wave's 2 phase-1 cover asteroids (`boss.phase1_medium_asteroids`, medium) are spawned by the WaveDirector when the boss wave starts. They spawn in addition to any `asteroids` the wave lists.

**Never:**
- No `CORE` phase, core attacks, Wasp launches, Final Choice, desperate phase, boss death or `boss_defeated` emission (Stories 7.4–7.7). When all 4 turrets die, the Flagship logs one INFO line and stays in `TURRETS`; F3 moves the wave on.
- No Level 3 data change (Story 7.6). No wiring of `boss_phase` / `boss_hp_le` triggers in the WaveDirector. No `boss_death` sfx and no `white_flash` (7.5).
- Don't add `flagship` to `EntityRegistry.ENEMIES`, because that would make it a valid `spawns` type. Bosses get their own registry.
- Never claim feel, readability, difficulty or cover usefulness as verified. Those are owed to the operator.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Boss wave starts | wave `{boss: "flagship"}` | `total_count()` 1; `wave_started`; one Flagship under `World/Enemies` (in `Groups.BOSS`, not `counted`); `boss_started`, `boss_phase_changed(0)`, `boss_hp_changed(300,300,0)`; 2 medium asteroids | — |
| Arrival | step until at station | moves from `(960, hull.arrive_from_y)` to `(960, hull.station_y)` in `hull.arrival_s`; then `boss_phase_changed(1)`, turrets start | — |
| Turret cadence | in `TURRETS` | turret i shots at `i*0.75 + 3.0 + k*3.0` s; Glow visible only in the 0.5 s before each shot; 3 bullets at -15/0/+15° from down, 350 px/s | no spawner: cycle runs, no shot |
| Hit part | `apply_damage(10)` on a full turret | turret hp 15; `boss_hp_changed(290,300,1)` | — |
| Hit hull / core | `apply_damage` on hull or invulnerable core | hp unchanged; no event | — |
| Turret dies | turret hp → 0 | BOSS_PART impact (1.5×, 6 px / 0.2 s, 30 ms); `enemy_killed(&"flagship_turret",…)`; 1 orb always; combined HP drops by the overkill-free remainder | — |
| All turrets dead | 4th turret dies | INFO `Flagship: all turrets destroyed`; phase stays `TURRETS`; combined 200 | — |
| Resolve | `Events.boss_defeated` during the boss wave | wave resolves (1/1) and clears; a second `boss_defeated` changes nothing | after `level_failed`: not resolved (DW-54) |
| No resolve | Flagship alive, no `boss_defeated` | wave never clears, no stall-net subtraction | — |
| Unknown / failed boss | `{boss: "bogus"}` or no spawner | `Log.error` names it; subtracted; wave clears | — |
| F3 on boss wave | live Flagship | Flagship freed (no `boss_defeated`); wave resolves and clears | — |
| F6 | any wave, boss wave exists | counted enemies and any live Flagship freed; boss wave starts with a fresh Flagship | — |
| Player contact | player overlaps hull | hearts −2; hull survives | i-frames as usual |
| Boss bar | `boss_started` | BossBar fades 0→1 and WaveBar 1→0 over `hud.boss_bar.fade_s`; fill = current/max from the left; markers at core_hp/max (66.7 %) and final_choice_hp/max (16.7 %) | `max <= 0`: empty fill, no markers |

</intent-contract>

## Code Map

- `game/core/enemy.gd` -- base. `_ready` reads hp `enemies.<id>.hp`, the tier from `Config.section("enemies.%s" % type_id)` and builds a circle Hitbox. `_tuning_key` is at l.~168. Add virtuals: `_tuning_section()` (default `"enemies.%s" % type_id`; `_tuning_key` and the tier read use it), `_max_hp()`, `_hitbox_shape()` and public `is_targetable()` (default true). Existing enemies must behave identically.
- `game/entities/enemies/bastion/bastion.gd` + `.tscn` -- golden pattern for turret Glow (additive GradientTexture2D sprite, `self_modulate` energy), `_build_spread`, `_fire` and the `step(delta)` state machine.
- `game/core/spawner.gd` -- add `spawn_boss(type_id, params) -> Flagship` (Enemies container, sets `spawner`, unknown id → `Log.error` + null).
- `game/autoloads/entity_registry.gd` -- add `BOSSES: Dictionary[StringName, PackedScene] = { &"flagship": preload(...) }`.
- `game/core/groups.gd` -- add `BOSS`.
- `game/systems/waves/wave_director.gd` -- `start_wave` l.221/232 (boss total and the "does not exist yet" error), `_check_stall` (needs the boss as a live counted unit), `debug_resolve_wave` l.247, `debug_skip_to_boss` l.277, `_spawn_asteroids` l.371 (reuse for the cover asteroids). Update the class doc.
- `game/entities/player/player.gd` l.395 `on_contact` / `_enemy_contact_cost` -- already charges `contact_large_hearts` for any non-small/medium Enemy. Read-only.
- `game/entities/projectiles/micro_missile.gd` l.75 `nearest_enemy`, `game/entities/allies/ally_ship.gd` l.371 `nearest_target` -- skip `not is_targetable()`.
- `game/entities/projectiles/missile.gd` `apply_splash` -- calls `apply_damage` on group members (the hull and core ignore it). Read-only.
- `game/autoloads/audio.gd` `SFX` -- register `&"explosion_boss_part"` as a placeholder alias of `sfx_explosion_large.wav` (closes the known boss_part gap; Epic 8 replaces it).
- `game/ui/hud/convoy_bar.gd`, `wave_bar.gd` -- golden patterns for the BossBar (Events-only, theme type, label build, PAUSABLE). WaveBar gains the boss fade-out.
- `game/ui/theme/defector_theme.tres` -- add the `BossBar` type: `styles/track` = the existing wave track, `styles/fill` = a new StyleBoxFlat in `enemy` #FF2BD6 (2 px corners), `colors/marker` = `text` #E8F4FF, `colors/label` = `muted` #93A7C2.
- `game/scenes/level/level.tscn` -- add `HUD/BossBar` (Control, process_mode 1, hidden, theme, script) after WaveBar.
- `game/data/tuning.json` -- `boss` and `hud` sections (see Design Notes).
- `game/tests/unit/test_wave_director.gd` l.776–880, 940, 1114 -- boss tests that `assert_push_error("boss 'flagship'")` and expect the boss wave subtracted. Rewrite them: emit `Events.boss_defeated` to clear.
- `game/tests/unit/test_bastion.gd`, `tests/fixtures/player_test_base.gd`, `tests/unit/test_impact_tiers.gd`, `tests/unit/test_convoy_bar.gd`, `tests/unit/test_level_2.gd` (`_make_level` fixture), `tests/unit/test_debug_tools.gd` (F6 dispatch) -- fixture patterns to copy.
- `game/tests/data/test_data_files.gd` -- the telegraph walk (l.333) and the `*_speed_px_s` walk over `tuning.boss` (l.364). New keys must pass both: no `*_speed_px_s` key that isn't a bullet speed.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_flagship.gd` -- NEW. Spawn through a Spawner fixture world (Enemies, Projectiles, Effects, Pickups) and drive `step(delta)` with physics off. Cover the matrix rows for arrival, cadence (shot times, glow window, spread angles and speed), hit part, hull and core, turret death (impact tier observed as `test_impact_tiers.gd` does, `enemy_killed` type, orb), all turrets dead, combined HP events, the parts' hitboxes not overlapping the hull, the scene's turret count matching tuning, and targeting (`MicroMissile.nearest_enemy` and `AllyShip.nearest_target` pick a turret, never the hull or core).
- `game/tests/unit/test_player_hearts.gd` -- add hull contact costs 2 and the hull survives (like `test_bastion_contact_costs_two_and_survives`).
- `game/tests/unit/test_wave_director.gd` -- rewrite the boss and F6 tests per the matrix (resolve, no resolve, second defeat ignored, after `level_failed`, unknown id, cover asteroids, F3, F6 frees the old boss).
- `game/tests/unit/test_boss_bar.gd` -- NEW. Hidden until `boss_started`; cross-fade of both bars; fill width; marker x positions; FLAGSHIP label (muted, 20 px, centred, top y 68); `level_started` hides it and restores the wave bar.
- `game/tests/unit/test_flagship_level.gd` -- NEW. Real `level.tscn` on `dev_boss` (fixture like `test_level_2.gd`): F6 through DebugTools jumps to the boss wave, the Flagship spawns, BossBar is visible, WaveBar faded, no `[ERROR]` line.
- `game/tests/data/test_data_files.gd` and `tests/unit/test_audio.gd` -- the new tuning keys and ranges, the `dev_boss` level shape (level_dev key set) and the registered `explosion_boss_part`.
- `game/core/enemy.gd`, `entity_registry.gd`, `spawner.gd`, `groups.gd`, `micro_missile.gd`, `ally_ship.gd`, `audio.gd` -- the hooks above.
- `game/entities/boss/flagship.gd/.tscn`, `flagship_part.gd`, `flagship_turret.gd/.tscn`, `flagship_core.gd/.tscn` -- NEW, per Design Notes.
- `game/systems/waves/wave_director.gd` -- boss spawn, live count, `Events.boss_defeated` resolve, cover asteroids, F3/F6 boss freeing.
- `game/ui/hud/boss_bar.gd`, `wave_bar.gd`, `defector_theme.tres`, `level.tscn` -- the HUD.
- `game/data/tuning.json`, `game/data/levels/level_dev_boss.json` -- the data.
- `_bmad-output/game-architecture.md` -- append `## As-built 2026-10-12 (Story 7.3)` in the style of the 7.2 entry. `decision-log.md` -- add row 54 (Spec, Story 7.3, Applied (provisional)) recording the readings: an unaimed ±15° spread, a 0.75 s stagger, the hull as armour, cover spawned at boss-wave start, the station and arrival values, and parts hanging below the hull.

**Acceptance Criteria:**
- Given a level whose wave is `{ "boss": "flagship", "triggers": [...] }`, when the WaveDirector reaches it, then the total is 1, `boss_started` fires, the Flagship spawns through the Spawner and enters `ARRIVING` then `TURRETS`, and the wave clears only after `Events.boss_defeated`.
- Given Phase 1, when it runs, then 4 turrets with 25 HP each fire the staggered start-to-start spreads described above, the core takes no damage, and 2 medium asteroids were spawned.
- Given a turret is destroyed, then the Boss-part tier plays and an energy orb always drops.
- Given the player touches the hull, then the player loses 2 hearts.
- Given the boss fight starts, then the boss bar replaces the wave bar with the combined HP and both F8 markers.
- Given a debug build on `level.tscn` with `dev_boss`, when F6 is pressed, then the level jumps to the boss wave and the Flagship is present.
- Given the full GUT suite runs headless, then every test passes.

## Spec Change Log

## Review Triage Log

### 2026-10-12 — Review pass
- verdicts: 23 findings — high 0, medium 1, low 16, false 5, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) A level's `boss` id is never checked against `EntityRegistry.BOSSES`, so a typo in Level 3 would subtract the boss and clear the level. — Added data test `test_every_boss_wave_names_a_known_boss`. The runtime path already logs an ERROR.
  - `[low]` `[reject]` (blind) The HUD isn't restored when the boss leaves without a `level_started` (F3 on a boss wave). — Only reachable with debug F3 or a level with waves after the boss. Both shipped boss waves (dev_boss, planned L3) are last, and the fix needs new handlers.
  - `[low]` `[reject]` (blind) Turrets can be targeted and damaged during ARRIVING while slightly off-screen. — This matches every entering enemy (Wasps and Bastions are hittable entering from above), and projectiles free past the 64 px margin. The spec sets no arrival invulnerability. A guard would add branches for a negligible effect.
  - `[low]` `[reject]` (blind) The hull size lives in tuning and in the scene polygon / `sprite_px`. — Same pattern as the Bastion (scene art and markers, tuning hitbox). A retune fails `test_no_part_hitbox_overlaps_the_hull` loudly. Removing the keys would re-plan the spec.
  - `[low]` `[patch]` (blind) Part contact cost is never tested. — Added `test_flagship_turret_contact_costs_two_and_survives`.
  - `[low]` `[reject]` (blind) The level-scene test never reaches TURRETS in the real scene. — Turret firing and HP are unit-tested through the same `step()`. The only untested link (physics driving `step`) is patched under the verification-gap finding below.
  - `[low]` `[patch]` (blind) `epic-7-context.md` is stale: boss_part sfx gap, `_enter_state()` name, `flagship_part` missing from the file list. — Corrected all three.
  - `[low]` `[patch]` (blind) The zone limits are written as "y 378 or above it", which is ambiguous in screen coordinates. — Rewritten as y ≤ 378 / y ≤ 432.
  - `[low]` `[patch]` (blind) There is no handoff note that Story 7.6 must update `test_boss_waves_only_in_dev_levels`. — Added to the epic context.
  - `[low]` `[patch]` (blind) Decision-log row 54 isn't user-signed. — The format matches precedent #26 ("Spec (Story 1.6) | Applied (provisional)"), but the status now reads "Applied (provisional; operator to confirm)" and confirming it is an operator action.
  - `[low]` `[reject]` (blind) The geometry test hard-codes 432 rather than `ENEMY_ZONE_BOTTOM_Y`, and the "above y 340" note is untested. — Cosmetic. 432 is the GDD enemy-zone bottom, the binding constraint, and the 340 figure is descriptive (actual bottom 332.4).
  - `[low]` `[reject]` (edge) A boss removed without `level_started` leaves a stale BossBar and an invisible WaveBar. — Same root cause as the blind HUD finding; same reason.
  - `[low]` `[reject]` (edge) Turrets are damageable and targetable during ARRIVING. — Same as the blind ARRIVING finding; same reason.
  - `[false]` `[reject]` (edge) `step(delta)` with delta ≥ `fire_interval_s` drops shots. — The physics delta is the fixed tick (1/60 s × time_scale ≤ 1), which never reaches 3.0 s. The Bastion uses the same single-shot pattern.
  - `[low]` `[reject]` (edge) After F6 the queued-for-free old Flagship can step once more in the same frame. — Debug-only one-tick glitch, shared with the counted enemies F6 already frees the same way. A guard adds complexity for no player impact.
  - `[medium]` `[patch]` (verification-gap) No test asserts that the Flagship moves when physics drives it, so a dropped `_physics_process` would ship a boss that never arrives. — `test_flagship_level.gd` now asserts y > `boss.hull.arrive_from_y` after the wait.
  - `[low]` `[patch]` (verification-gap) The `Spawner.spawn_boss` failure paths are untested. — Added `test_unknown_boss_returns_null` and a no-Enemies-container check in `test_missing_container_logs_and_returns_null`.
  - `[low]` `[reject]` (intent) The diff leaves the owed playtest in prose rather than `status: awaiting-operator` + `operator_actions` (Story 7.1/7.2 precedent). — The fix edits this build's spec, so it is not a triage patch. Finalization applies the invocation's awaiting-operator rule anyway (see Auto Run Result).
  - `[false]` `[reject]` (intent) The wave-clears-on-`boss_defeated` criterion is tested by emitting the event by hand. — By design: nothing emits `boss_defeated` until Story 7.5 (spec Never). The test exercises the director's real handler.
  - `[low]` `[reject]` (intent) F6 is tested headless through `DebugTools._unhandled_input`, not a real key press in a debug build. — That is the same code path. The real key press is listed in operator_actions.
  - `[false]` `[reject]` (intent) Cover usefulness is only described in prose. — Not automatable: tests pin that 2 medium asteroids spawn, and usefulness is an operator playtest (operator_actions).
  - `[false]` `[reject]` (intent) The readability of the staggered spreads, glow and bar swap is unverified. — Tests pin the timing and values. Readability is a human judgement owed in operator_actions, never claimed.
  - `[false]` `[reject]` (intent) `epic-7-context.md` was rewritten beyond the story's scope. — The recompile is mandated by the workflow (the decision log was newer than the cached context). Its stale sfx line is fixed under the blind epic-context finding above.

## Design Notes

**Tuning additions** (provisional, per decision #11; the existing `boss` keys are unchanged):

```
boss.hull:     { tier "boss_death", width_px 720, height_px 160, station_y 170, arrive_from_y -220, arrival_s 3.0 }
boss.turrets: + { tier "boss_part", sprite_px 56, hitbox_ratio 0.8, spread_deg 15, stagger_s 0.75, glow_energy 2.5 }
boss.core:    + { tier "boss_death", sprite_px 96, hitbox_ratio 0.8 }
hud.boss_bar:  { x 680, y 40, width 560, height 20, fade_s 0.3, label_y 68, label_px 20, marker_w_px 2 }
```

Read `sprite_px` from tuning in each part's `_ready`, before `super()` builds the Hitbox. Arrival is a duration, not a speed: a `*_speed_px_s` key under `boss` would be checked as a bullet speed.

**Scene geometry** (local to the Flagship origin; geometry stays in `.tscn`, as the Bastion's turret markers do): the hull hitbox is a 720×160 `RectangleShape2D` centred on the origin (y −80..80). Turrets sit at (−270, 104), (−110, 104), (110, 104), (270, 104), radius 22.4, so their tops are at 81.6. The core sits at (0, 124), radius 38.4, so its top is at 85.6. At `station_y` 170, every part ends above y 340, inside the enemy zone. Placeholder art uses `enemy`-coloured Polygon2D shapes, like the Bastion (Epic 8 replaces it).

**Classes:** `FlagshipPart extends Enemy` adds `signal hp_changed(hp: int)`, `invulnerable`, and an `apply_damage` that is ignored while invulnerable and otherwise calls `super` and then emits. `is_targetable()` returns `not invulnerable`. `FlagshipTurret` (`type_id &"flagship_turret"`, section `boss.turrets`) owns its Glow and fire cycle (`start_firing(delay_s)`). `FlagshipCore` (`&"flagship_core"`, `boss.core`) starts invulnerable. `Flagship extends Enemy` (`&"flagship"`, section `boss.hull`): `_max_hp()` is the sum of its parts (children are ready first), `_hitbox_shape()` is the rect, `apply_damage` is a no-op, `is_targetable()` is false, and it hands `spawner` to its parts. The WaveDirector treats the boss as one live counted unit (`_live_counted`), so the stall net never subtracts a living boss.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: completes; needed after adding new `class_name` scripts.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failures.

**Manual checks (if no CLI):**
- Operator: `"<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game res://scenes/level/level.tscn -- --level=dev_boss`, then press F6. The Flagship arrives, the turrets glow and fire staggered spreads, the asteroids give cover, and the boss bar drains as turrets die.

## Auto Run Result

Status: awaiting-operator

**Summary:** The Flagship boss Phase 1 is built.
- An armoured hull (shots spent, no damage, not a target, contact costs 2 hearts) with 4 turrets and an invulnerable core, running `Phase { ARRIVING, TURRETS, CORE, FINAL_CHOICE, DESPERATE, DYING }` through ARRIVING → TURRETS.
- The turrets fire unaimed 3-bullet ±15° spreads at 350 px/s every 3.0 s, start to start. The 0.5 s glow runs inside each period, and the turrets are staggered 0.75 s apart.
- A turret death plays the Boss-part tier and always drops an orb.
- The WaveDirector spawns the boss through `Spawner.spawn_boss` (separate `EntityRegistry.BOSSES`), counts it as 1 live unit, and resolves it only on `Events.boss_defeated`. It also spawns the 2 medium cover asteroids. F3 and F6 free the boss.
- A new HUD BossBar cross-fades over the WaveBar with the combined HP (300) and the F8 markers at 66.7 % and 16.7 %.
- A new dev level `dev_boss` covers F6 and manual play.

**Files changed:**
- `game/entities/boss/flagship.gd/.tscn`, `flagship_part.gd`, `flagship_turret.gd/.tscn`, `flagship_core.gd/.tscn` -- new boss entity and parts.
- `game/core/enemy.gd` -- virtual hooks `_tuning_section`, `_max_hp`, `_hitbox_shape`, `is_targetable` (existing enemies unchanged).
- `game/core/spawner.gd`, `game/autoloads/entity_registry.gd`, `game/core/groups.gd` -- `spawn_boss`, `BOSSES`, `Groups.BOSS`.
- `game/systems/waves/wave_director.gd` -- boss spawn, live count, `boss_defeated` resolve, cover asteroids, F3/F6.
- `game/entities/projectiles/micro_missile.gd`, `game/entities/allies/ally_ship.gd` -- skip non-targetable enemies.
- `game/autoloads/audio.gd` -- `explosion_boss_part` placeholder alias of the large explosion.
- `game/ui/hud/boss_bar.gd` (new), `wave_bar.gd`, `game/ui/theme/defector_theme.tres`, `game/scenes/level/level.tscn` -- boss bar and the cross-fade.
- `game/data/tuning.json` (`boss.hull`, turret and core keys, `hud.boss_bar`), `game/data/levels/level_dev_boss.json` (new).
- Tests: new `test_flagship.gd`, `test_boss_bar.gd`, `test_flagship_level.gd`; updated `test_wave_director.gd`, `test_player_hearts.gd`, `test_spawner.gd`, `test_audio.gd`, `test_groups.gd`, `tests/data/test_data_files.gd`.
- Docs: `game-architecture.md` (As-built Story 7.3), `decision-log.md` row 54 (provisional; operator to confirm), `epic-7-context.md` (recompiled, then corrected).

**Review findings:** 23 findings (high 0, medium 1, low 16, false 5).
- **Patched (8):** 1 medium (physics-driven arrival untested) and 7 low (boss id data test, part contact test, spawn_boss failure tests, epic-context staleness, zone wording, the 7.6 handoff note, decision #54 status).
- **Deferred:** none.
- **Rejected (15),** each with its reason in the Review Triage Log:
  - HUD not restored after a boss leaves mid-level (x2): debug-only, boss waves are last.
  - Turrets hittable during ARRIVING (x2): consistent with every entering enemy.
  - Hull size in tuning and scene: Bastion pattern, a retune fails loudly.
  - Level test doesn't reach TURRETS: covered by unit tests plus the physics patch.
  - 432 literal and 340 wording: cosmetic.
  - Large-delta shot drop: false, the physics tick is fixed.
  - F6 one-tick step of the freed boss: debug-only, pre-existing pattern.
  - awaiting-operator bookkeeping: applied at finalization.
  - Hand-emitted `boss_defeated`: by design until 7.5.
  - Headless F6: same code path, real key press owed to the operator.
  - Cover usefulness and spread readability: operator playtest.
  - Epic-context rewrite: mandated by the workflow.

**Follow-up review recommended:** false. Patched: high 0, medium 1, low 7. Only one medium was patched (a test assertion), and no high.

**Verification:**
- `--headless --path game --import`: OK.
- Full GUT suite headless: 90 scripts, 1701/1701 tests passing (18285 asserts) after the patches; 1698/1698 before them.
- Matrix test audit: every I/O row has a passing covering test.
- The staged diff was scanned for secrets, personal paths and work identities: none.

**Residual risks:**
- Feel, readability, difficulty and cover usefulness are not verified: they are owed to the operator.
- The provisional readings in decision #54 await operator confirmation.
- Until Story 7.4 the Flagship stays in TURRETS after the last turret dies (F3 moves the wave on).
- Story 7.6 must update `test_boss_waves_only_in_dev_levels` when Level 3 gets its boss wave.
