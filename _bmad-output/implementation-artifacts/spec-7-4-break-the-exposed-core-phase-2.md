---
title: "Story 7.4: Break the Exposed Core (Phase 2)"
type: 'feature'
created: '2026-10-12'
status: done
operator_actions:
  - 'Run "<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game res://scenes/level/level.tscn -- --level=dev_boss in a debug build, press F6, destroy all four turrets, and confirm the Flagship enters Phase 2: the core opens up, the boss bar drains from the 66.7 % marker as you hit the core, and no error appears in the log.'
  - 'In that run, judge whether the 0.6 s core glow reads clearly before each 12-bullet radial burst and whether the bursts are fair to dodge; any retune goes in game/data/tuning.json (boss.core) with a GDD decision-log entry.'
  - 'Judge the Wasp launches: every 10 s up to 5 Wasps fly out of the core to their slots below the Flagship (never more than 10 alive) and then dive like wave Wasps. Note whether one missile killing two stacked boss Wasps (rows 60 px apart) is acceptable.'
  - 'Destroy all four turrets while the Flagship is still flying in and confirm it still reaches its station and then opens the core (Phase 2).'
  - 'Confirm or overrule the provisional readings in GDD decision-log row 55 (radial layout, first burst and first launch one full period after Phase 2 starts, launch origin and the 10 fixed slots, the launch count rule, core death before Story 7.5, F6 freeing launched Wasps), and update the row status accordingly.'
baseline_revision: '98d737b124d34254dd467083dbef91524c0f0617'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-7-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** When the last turret dies, the Flagship logs a line and stays in `TURRETS` (Story 7.3). The core stays invulnerable and has no attacks, so there is no Phase 2 (FR50).

**Approach:** When the 4th turret dies, the Flagship enters `CORE`. The core becomes damageable and runs its own start-to-start charge-and-fire cycle, a 12-bullet radial burst. The Flagship launches Wasps through the `Spawner` every `wasp_launch_interval_s`, up to `wasp_max_alive`. The launched Wasps fly out of the core to fixed boss slots, then behave like wave Wasps, but they are never counted. All numbers come from `tuning.boss`.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript. Write the failing GUT test first. Read every number through `Config`, and log through `Log`. Only `Spawner` instantiates anything; the boss-launched Wasps are the architecture's one named exception to "only the WaveDirector decides".
- Enter `CORE` straight from the hp-change handler that sees the live turret count reach 0. It replaces 7.3's "stay in TURRETS", but the INFO line `Flagship: all turrets destroyed` is still logged once. Entering `CORE` sets `core.invulnerable = false`, emits `boss_phase_changed(2)` and `boss_hp_changed(200, 300, 2)`, and starts the core cycle and the launch timer.
- Core cadence is start-to-start (decisions #38, #50, #52). The core fires every `boss.core.radial_interval_s` (3.0). Its Glow shows for the last `charge_s` (0.6) of each period, and its first shot comes one full period after `CORE` begins. A burst is `radial_bullets` (12) `enemy_bullet`s from the core centre, evenly spaced over 360° with one going straight down, each at `radial_speed_px_s` (300) and dealing `damage.bullet_hearts`.
- Launches have no telegraph. The first launch is `wasp_launch_interval_s` (10) after `CORE` begins, then one every interval. Each launch spawns `n = min(wasp_launch_count, wasp_max_alive − alive launched, free slots)` Wasps through `spawner.spawn_enemy(&"wasp", { "slot": s, "launch_from": core centre })`. A null return is skipped.
- Launched Wasps join `Groups.BOSS_WASPS`, never `Groups.COUNTED`. The WaveDirector never connects their `resolved`, so they never change the wave total, resolved count, progress or stall net. Their type is `wasp`, so kills use `drops.wasp` and the WaspDiveClock dives them like any holding Wasp.
- Launches and core shots run only in the `CORE` branch of `step`. Entering any other phase hides the core Glow. Wasps already alive stay (decision F16).
- Without a spawner, the cycles still run, but nothing fires or launches. Each of the core and the Flagship logs one DEBUG line (`_can_fire` pattern).

**Never:**
- Don't build the 50 HP clamp, `FINAL_CHOICE` entry, desperate attacks, boss death or `boss_defeated` (Story 7.5). Don't wire `boss_phase` / `boss_hp_le` triggers or change Level 3 data (Story 7.6).
- Don't touch the wave Wasps' entry. The new `launch_from` param changes only where the first ENTER starts. A re-entry after a dive still comes from the top.
- Never claim feel, fairness, readability or difficulty is verified. The operator owes that.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Enter CORE | 4th turret dies | phase `CORE`; `boss_phase_changed(2)`; `boss_hp_changed(200,300,2)`; core vulnerable and targetable; INFO line once | — |
| Hit core | `apply_damage(10)` in CORE | core 190; `boss_hp_changed(190,300,2)` | — |
| Core cadence | step in CORE | shots at 3.0 + k·3.0 s; Glow only in the 0.6 s before each; 12 bullets at 0°, 30°, … from down, 300 px/s, from the core centre | no spawner: no bullets, one DEBUG line |
| Launch | 10 s in CORE, 0 alive | 5 Wasps fly from the core centre to slots 0–4; in `BOSS_WASPS`, not `counted`; WaveDirector total and resolved unchanged | no spawner: none, one DEBUG line |
| Cap | 20 s (10 alive), then 3 killed by 30 s | launch at 20 s → 5 (10 alive); 30 s → 3 into the freed slots; never > 10 | — |
| Launched Wasp killed | `apply_damage` kills one | `enemy_killed(&"wasp", …)`, `drops.wasp` table, wave counts unchanged | — |
| Leave CORE | `_enter_phase(FINAL_CHOICE)` (7.5 calls it; tests call it directly) | no more launches or core shots; Glow off; live launched Wasps stay | — |
| Core killed (pre-7.5) | core hp → 0 | boss_death impact, `enemy_killed(&"flagship_core", …)`, combined 0, INFO `Flagship: core destroyed` once; stays `CORE`, so F3 moves the wave on | — |
| F6 | live Flagship + launched Wasps | old Flagship and every `BOSS_WASPS` node freed; fresh Flagship | — |

</intent-contract>

## Code Map

- `game/entities/boss/flagship.gd` -- `step` match (add the `CORE` branch: core step and launch timer), `_enter_phase` (add the `CORE` entry), and `_on_part_hp_changed`, which holds the "all turrets destroyed" log and is where the switch to `CORE` happens. Cache the core's local offset in `_ready` (the launch origin, valid after the core is freed). Update the class doc.
- `game/entities/boss/flagship_turret.gd` -- golden pattern to copy into the core: `start_firing`, `step`, `_set_glow`, `_fire`, the static `spread_velocities`, and the Glow setup in `_ready`.
- `game/entities/boss/flagship_core.gd` / `.tscn` -- add `start_attacking()`, `stop_attacking()`, `step(delta)`, `is_glowing()`, static `radial_velocities(count, speed) -> PackedVector2Array`, and a `Glow` Sprite2D copied from `flagship_turret.tscn` (scaled for the 96 px core).
- `game/entities/enemies/wasp/wasp.gd` -- `_ready` takes `_entry_start` from `_entry_start_for(_slot)`. Override `setup` to read an optional `launch_from` (Vector2). With a slot and `launch_from`, the first ENTER starts there. WaveDirector passes `position` = slot (`wave_director.gd:379`), so don't key off `position`.
- `game/core/groups.gd` -- add `BOSS_WASPS` (`&"boss_wasps"`).
- `game/systems/waves/wave_director.gd:299` `debug_skip_to_boss` -- also free `Groups.BOSS_WASPS` nodes.
- `game/core/loot.gd` -- read-only. With no `drops.flagship_core` table, the core drops nothing.
- `game/data/tuning.json` `boss.core` -- add keys (see Design Notes). Keep the existing keys.
- `game/tests/unit/test_flagship.gd` -- fixture world, `_logged`, and the 7.3 tests. `test_all_turrets_dead_logs_once_and_stays_in_turrets` (l.394) must become the CORE-entry test. Grep the test suite for other assertions that expect `TURRETS` after every turret dies.
- `game/tests/unit/test_wave_director.gd` (F6 boss tests), `game/tests/unit/test_groups.gd`, `game/tests/unit/test_wasp.gd`, and `game/tests/data/test_data_files.gd` (boss tuning ranges; the telegraph walk and the `*_speed_px_s` walk over `tuning.boss`).

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_flagship.gd` -- add tests for every matrix row except F6, plus targeting (a micro-missile and the ally can pick the core in CORE) and the 0°/30° radial helper. Drive the Flagship with `step(delta)` at 1/60 s and physics off.
- `game/tests/unit/test_wasp.gd` -- add: with `slot` + `launch_from`, the Wasp starts its ENTER at `launch_from` and reaches the slot. Without `launch_from`, the start is unchanged. A dive re-entry still starts from the top.
- `game/tests/unit/test_wave_director.gd` -- add: F6 frees the `BOSS_WASPS` nodes. A launched Wasp's kill leaves the boss wave's total and resolved count unchanged.
- `game/tests/unit/test_groups.gd`, `game/tests/data/test_data_files.gd` -- `BOSS_WASPS`; the Phase 2 GDD numbers next to the Phase 1 ones (`test_data_files.gd` l.~1539: 12 bullets, 300 px/s, 3.0 s, 0.6 s, 5 Wasps, 10 s, max 10); and the new key ranges: `glow_energy` > 0, `radial_bullets` ≥ 1, `wasp_launch_count` ≥ 1, `wasp_max_alive` ≥ `wasp_launch_count`, columns × rows ≥ `wasp_max_alive`, every slot x inside the playfield, every row y ≤ the Wasp zone (`enemies.wasp.zone_height_ratio` × 1080), and every row y minus half the Wasp sprite below the core hitbox bottom at the station.
- `game/entities/boss/flagship.gd`, `flagship_core.gd`, `flagship_core.tscn`, `game/entities/enemies/wasp/wasp.gd`, `game/core/groups.gd`, `game/systems/waves/wave_director.gd`, `game/data/tuning.json` -- implement per the Boundaries and the Design Notes.
- `_bmad-output/game-architecture.md` -- append `## As-built 2026-10-12 (Story 7.4)` in the style of the 7.3 entry. Change the 7.3 "stays in TURRETS" sentences in that entry's Flagship bullet to point at it.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- add row 55 (Spec, Story 7.4, "Applied (provisional; operator to confirm)"). Record the readings: the radial layout, the first shot and first launch one period after CORE begins, the launch origin and the 10 fixed slots, n = min(count, cap − alive, free slots), core death before 7.5, and F6 freeing launched Wasps.
- `_bmad-output/implementation-artifacts/epic-7-context.md` -- change the "stays in `TURRETS`; Story 7.4 adds the move" line to say what was built.

**Acceptance Criteria:**
- Given all 4 turrets are destroyed, when the Flagship enters `CORE`, then `Events.boss_phase_changed(2)` fires and the 200 HP core takes damage.
- Given Phase 2, when the core attacks, then it glows for 0.6 s inside each 3.0 s start-to-start period and then fires a 12-bullet radial burst at 300 px/s.
- Given Phase 2, when 10 s pass, then the Flagship requests up to 5 Wasps through the `Spawner`, never more than 10 boss-launched Wasps alive. Those Wasps aren't counted toward the wave, they drop energy at the normal Wasp rate, and launches stop once the Flagship leaves `CORE` while the live Wasps stay.
- Given the full GUT suite runs headless, then every test passes.

## Spec Change Log

## Review Triage Log

### 2026-10-12 — Review pass
- verdicts: 27 findings — high 0, medium 2, low 22, false 3, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) Two Story 7.3 bullets in `game-architecture.md` (Tests, Owed to the operator) still say the Flagship stays in TURRETS. — Added a "Story 7.4 changes this" pointer to both.
  - `[medium]` `[patch]` (blind) No test kills the turrets during ARRIVING. — Grouped with the verification-gap arrival finding; added `test_turrets_killed_while_arriving_enter_core_at_the_station`.
  - `[low]` `[patch]` (blind) Launches after the core dies (from the cached origin) are not checked. — Grouped with the verification-gap core-death finding; the core-death test now asserts 5 launches starting at the core's old centre. (#55 item 3 already states the cached origin.)
  - `[low]` `[patch]` (blind) The boss Wasp rows are 60 px apart, inside the 120 px splash, and #55 doesn't record the double-kill side effect. — Added the side effect to row 55 for the operator to judge.
  - `[low]` `[reject]` (blind) A Wasp on row 370 overlaps the core sprite by 4 px. — Placeholder art (Epic 8); the docs state the clearance against the core hitbox (y 332.4), which holds.
  - `[low]` `[reject]` (blind) `_slot_taken` compares against a possibly clamped slot. — Only reachable if a retune puts a row below the Wasp zone, which `test_flagship_phase_2_tuning_ranges` fails; the fix adds per-Wasp slot bookkeeping.
  - `[low]` `[reject]` (blind) A null spawn uses up one of the tick's Wasps and is untested. — A null spawn needs a missing Enemies container or an unknown id; neither is reachable with the constant `&"wasp"`. The slot refills on the next launch.
  - `[low]` `[patch]` (blind) `wasp_launch_interval_s <= 0` disables launches with no warning. — Added one `[WARN][data]` line in `_read_launch_tuning`, matching the core's.
  - `[low]` `[patch]` (blind) No test shows the dive clock diving a launched Wasp. — Added `test_dive_clock_picks_a_launched_wasp_holding_its_slot`.
  - `[low]` `[reject]` (blind) No real-level test of Phase 2. — The logic is unit-tested through the same `step()`; the 7.3 level test pins the spawn and physics wiring. A real-level run needs 3 s arrival + 10 s launch in real time, and the playtest is owed to the operator.
  - `[low]` `[reject]` (blind) Nothing says what happens to leftover launched Wasps at boss death or level clear. — Boss death is Story 7.5; after `level_cleared` the player is safe (decision #39), so leftover Wasps can't fail the level.
  - `[low]` `[patch]` (blind) The epic-7 context recompile dropped the ownership and `destroy_by_contact` rules. — Restated both in the Flagship structure bullets.
  - `[low]` `[patch]` (blind) `_expected_slots()` repeats the code's formula. — It now lists the documented literal positions.
  - `[low]` `[reject]` (blind) `launch_from` isn't type-checked. — Same `as Vector2` pattern as `Enemy.setup`'s `position` / `slot`; the only caller is the Flagship.
  - `[low]` `[reject]` (edge) A splash from the missile that kills an inner turret can hit the newly exposed core in the same loop. — 3 HP at most, and it's a hit after the turrets are gone; deferring the exposure would contradict the spec's "enter CORE straight from the hp-change handler".
  - `[low]` `[reject]` (edge) A clamped slot never reads as taken. — Same as the blind clamped-slot finding; same reason.
  - `[low]` `[patch]` (edge) No warning for a non-positive launch interval. — Same fix as the blind finding.
  - `[false]` `[reject]` (edge) `spawn_enemy` could return a non-Wasp Enemy that nobody tracks. — `WASP_ID` is the constant `&"wasp"`, and `EntityRegistry.ENEMIES[&"wasp"]` is `wasp.tscn`, whose root is a `Wasp`.
  - `[low]` `[patch]` (edge) The epic-context rewrite dropped the contact and ownership rules. — Same fix as the blind finding.
  - `[medium]` `[patch]` (verification-gap) The ARRIVING→CORE branch has no test; reverting it would soft-lock the fight. — Added the arrival test above; reverting either path now fails it.
  - `[low]` `[patch]` (verification-gap) The launches after the core dies run in a test but are never asserted. — Assertions added (see above).
  - `[low]` `[reject]` (intent) The owed playtest sits in prose instead of `status: awaiting-operator` + `operator_actions`. — The fix edits this build's spec; finalization applies the awaiting-operator rule (see the frontmatter and Auto Run Result).
  - `[low]` `[reject]` (intent) The tests drive the Flagship at unit level, not in the real level. — Same as the blind real-level finding; same reason.
  - `[false]` `[reject]` (intent) "Launches stop once the Flagship leaves CORE" is tested by calling `_enter_phase(FINAL_CHOICE)` directly. — By design: FINAL_CHOICE entry is Story 7.5, and the spec matrix names this test seam.
  - `[false]` `[reject]` (intent) The test checks the Wasp drop table, not the drop rate. — The "normal Wasp rate" is `drops.wasp` by definition; the test shows a launched Wasp's kill rolls that table.
  - `[low]` `[patch]` (intent) The dive-clock behaviour of launched Wasps is untested. — Same fix as the blind finding.
  - `[low]` `[reject]` (intent) The diff includes behaviour beyond the ACs (core death before 7.5, the arrival edge, F6 freeing, fixed slots, context tidying). — Each is recorded as provisional in decision #55 per the epic-context rule for values the docs leave open; the operator confirms them.

## Design Notes

**Tuning additions** to `boss.core` (provisional, per #11 and #54): `glow_energy` 2.5, and `wasp_slots` `{ "columns": 5, "spacing_x_px": 160, "rows_y": [370, 430] }`. The 10 slots are centred on x 960: x 640, 800, 960, 1120, 1280 on row y 370, then the same on row y 430, filled in that order. Don't use a `*_speed_px_s` suffix for any new key. The 64 px Wasp then clears the core's bottom (y 332.4) and stays inside the y ≤ 432 Wasp zone.

**Radial helper** (mirrors `spread_velocities`):

```gdscript
static func radial_velocities(count: int, speed: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in count:
		out.append(Vector2.DOWN.rotated(TAU * float(i) / float(count)) * speed)
	return out
```

**Live count:** the Flagship keeps `_launched: Array[Wasp]` and prunes entries that are freed or `is_dead()` before each launch. A slot is free when no live launched Wasp holds it (`formation_slot()`). Build the `_launched` and occupied-slot scans without per-frame allocations: they run only on a launch tick.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: completes.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failures.

**Manual checks (if no CLI):**
- Operator: `"<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game res://scenes/level/level.tscn -- --level=dev_boss`, then F6. Destroy the turrets. The core opens, glows and fires radial bursts, and every 10 s Wasps fly out of the core to their slots and dive.

## Auto Run Result

Status: awaiting-operator

**Summary:** The Flagship's Phase 2 is built.
- When the 4th turret dies, the Flagship enters `CORE`: `boss_phase_changed(2)`, `boss_hp_changed(200, 300, 2)`, and the 200 HP core becomes damageable and targetable. If every turret dies during the arrival, it enters `CORE` when it reaches its station.
- The core fires a 12-bullet radial burst (30° apart, one straight down) at 300 px/s every 3.0 s start-to-start, with its 0.6 s Glow inside each period.
- Every 10 s the Flagship requests up to 5 Wasps through `Spawner.spawn_enemy`, never more than 10 alive. They fly out of the core to 10 fixed slots, then behave like wave Wasps. They are in `Groups.BOSS_WASPS`, never counted, and drop on `drops.wasp`. Launches and core shots stop when the Flagship leaves `CORE`; live Wasps stay. F6 frees them.

**Files changed:**
- `game/entities/boss/flagship.gd` -- CORE entry, the CORE branch of `step`, Wasp launches, slots, the arrival edge, the pre-7.5 core-death log.
- `game/entities/boss/flagship_core.gd` / `.tscn` -- the radial cycle, `radial_velocities`, the Glow, no drop roll.
- `game/entities/enemies/wasp/wasp.gd` -- optional `launch_from` setup param (first entry only).
- `game/core/groups.gd` -- `BOSS_WASPS`. `game/systems/waves/wave_director.gd` -- F6 frees launched Wasps.
- `game/data/tuning.json` -- `boss.core.glow_energy`, `boss.core.wasp_slots`.
- Tests: `test_flagship.gd`, `test_wasp.gd`, `test_wave_director.gd`, `test_groups.gd`, `tests/data/test_data_files.gd`.
- Docs: `game-architecture.md` (As-built Story 7.4, 7.3 pointers), `decision-log.md` row 55 (provisional; operator to confirm), `epic-7-context.md` (recompiled because the decision log was newer, then updated).

**Review findings:** 27 findings (high 0, medium 2, low 22, false 3).
- **Patched (8 entries):** 1 medium (the ARRIVING→CORE test, found by two layers) and 7 low (core-death launch assertions, the launch-interval warning, the dive-clock test, literal slot positions, the stale 7.3 architecture bullets, the #55 splash side effect, the epic-context contact and ownership rules).
- **Deferred:** none.
- **Rejected,** each with its reason in the Review Triage Log: the 4 px sprite overlap (placeholder art), the clamped-slot match (x2, guarded by the data test), null-spawn budget (unreachable), no real-level Phase 2 test (x2, covered by unit tests and the playtest), leftover Wasps after boss death (Story 7.5; player safe after clear), the untyped `launch_from` (existing pattern), the splash on the newly exposed core (3 HP; the spec's entry rule), a non-Wasp spawn (false), awaiting-operator bookkeeping (applied here), the private `_enter_phase` seam (false, by design), drop table vs rate (false), and scope beyond the ACs (recorded in #55).

**Follow-up review recommended:** false. Patched: high 0, medium 1, low 7.

**Verification:**
- `--headless --path game --import`: OK.
- Full GUT suite headless: 90 scripts, 1721/1721 tests passing (19177 asserts) after the patches; 1719/1719 before them.
- Matrix test audit: every I/O row has a covering test that ran and passed.
- The diff was scanned for secrets, personal paths and work identities before committing.

**Residual risks:**
- Feel, readability, fairness and difficulty are not verified; they are owed to the operator (see `operator_actions`).
- The provisional readings in decision #55 await operator confirmation.
- Until Story 7.5, the core can be killed in `CORE`; the Flagship then stays in `CORE` and F3 moves the wave on. Killing the core logs one known WARN (`explosion_boss_death` is not registered yet; Story 7.5).
- F3 frees the Flagship but leaves launched Wasps alive (uncounted, debug only).
- The Story 7.2 as-built entry names the splash key `missiles.splash_radius_px`; the real key is `weapons.missile.splash_radius_px` (pre-existing doc slip, not changed).

## Operator Confirmation

Confirmed 2026-10-13: the external actions this story owed were carried out.

- Run "<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game res://scenes/level/level.tscn -- --level=dev_boss in a debug build, press F6, destroy all four turrets, and confirm the Flagship enters Phase 2: the core opens up, the boss bar drains from the 66.7 % marker as you hit the core, and no error appears in the log.
- In that run, judge whether the 0.6 s core glow reads clearly before each 12-bullet radial burst and whether the bursts are fair to dodge; any retune goes in game/data/tuning.json (boss.core) with a GDD decision-log entry.
- Judge the Wasp launches: every 10 s up to 5 Wasps fly out of the core to their slots below the Flagship (never more than 10 alive) and then dive like wave Wasps. Note whether one missile killing two stacked boss Wasps (rows 60 px apart) is acceptable.
- Destroy all four turrets while the Flagship is still flying in and confirm it still reaches its station and then opens the core (Phase 2).
- Confirm or overrule the provisional readings in GDD decision-log row 55 (radial layout, first burst and first launch one full period after Phase 2 starts, launch origin and the 10 fixed slots, the launch count rule, core death before Story 7.5, F6 freeing launched Wasps), and update the row status accordingly.

_Appended by the bmad-loop orchestrator (`bmad-loop confirm`, #335): a human confirmed these external actions out of band, and the story was advanced from `awaiting-operator` to `done`._
