---
title: 'Story 6.4: Fly Alongside Tarek and Ryn'
type: 'feature'
created: '2026-10-10'
status: done
operator_actions:
  - 'Launch the level scene directly in a debug build with `-- --level=dev_ally` ("<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game res://scenes/level/level.tscn -- --level=dev_ally), play it through to the clear, and read the `[INFO][combat] Kills: N total, ally M (P%); target 10-15%` line in the log.'
  - 'If the ally share is outside roughly 10-15 %, retune `allies.fire_interval_s` (or `allies.damage`) in `game/data/tuning.json`, never code, replay to confirm, and record the change in the GDD decision log (`_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md`).'
  - 'While playing, confirm Tarek reads as a cyan squadmate patrolling at y 690 above the player, that his shots visibly pick off enemies without carrying the fight, and that his ship never blocks or hurts you.'
baseline_revision: '6e05c1425aaabf380736c194ea62bb48d7af6fe8'
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

**Problem:** A level JSON's `"ally"` key is ignored: no ally ship exists, nothing fires ally shots, and no log shows the ally's share of kills (FR34, FR7, SHOULD). The `from_ally` / `by_ally` plumbing in `Projectile`, `Enemy` and `Events.enemy_killed` exists but has no producer.

**Approach:** Add an invincible `AllyShip` (`entities/allies/ally_ship.tscn/.gd`) on the `allies` layer that ping-pongs horizontally across the playfield at the centre of `allies.patrol_band_y` at `allies.speed_px_s`, and every `allies.fire_interval_s` re-acquires the nearest on-screen live enemy and fires a new `ally_bolt` projectile (`player_shots`, `from_ally = true`, `allies.damage`). `Spawner.spawn_ally` creates it in `World/Allies` when the level says `"ally": "tarek"|"ryn"`. The level tallies `Events.enemy_killed` and logs one kill-share summary line when the level outcome is decided, so a human can check the 10–15 % target. Add a dev level with Tarek for that playtest.

## Boundaries & Constraints

**Always:**
- Every number from `tuning.json` through `Config`, cached in `_ready`: existing `allies.patrol_band_y`, `speed_px_s`, `damage`, `fire_interval_s`, `kill_share`; new `allies.ship_px` (64) and `allies.shot_speed_px_s` (1200). Static typing, `CollisionLayers`/`Groups` constants, `Log` only.
- Only `Spawner` instantiates the ally and its shots (`ally.spawner` is set by `spawn_ally`, like `Enemy.spawner`). The ally's shots go through `spawner.spawn_projectile(&"ally_bolt", {...})`.
- AllyShip: `collision_layer = CollisionLayers.ALLIES`, `collision_mask = 0`, `monitoring = false`, `monitorable = false`, no `apply_damage` method. Nothing collides with it, so it takes no damage and blocks nothing.
- Target pick runs once per shot, never per frame: a single `get_nodes_in_group(Groups.ENEMIES)` scan; skip dead enemies (`is_dead()`) and enemies outside `Playfield.RECT`; nearest by `distance_squared_to`. No target → no shot; the clock keeps running (it fires again on the next elapsed interval, not instantly when a target appears).
- `AllyBolt` (`extends Projectile`): layer `player_shots`, mask `MASK_PLAYER_SHOTS`, `monitorable = false`, rotated to its velocity, a capsule whose height ≥ `shot_speed_px_s / 60`, coalition-coloured like the laser. `Projectile.setup` gains an optional `from_ally` key. The base `_can_damage` already blocks it on the convoy with no damage.
- The ally stops firing once the level outcome is decided (`Events.level_cleared` / `level_failed`), and keeps patrolling.
- Behaviour uses `enum State { PATROL }` + `match` with `_enter_state()` so Story 6.5 can add its states; movement and firing go through a public `step(delta)` called from `_physics_process` (like `Convoy.step`).
- Write the failing GUT test first.

**Never:**
- No Tarek fall, damaged variant, or `story_event` reaction (6.5). No change to `level_1/2/3.json` (Epic 7). No image asset (draw in code like `ConvoyShip`; art is Epic 8).
- No change to Enemy, Player, Convoy, WaveDirector or HUD logic. No new HUD element.
- Don't retune `allies.*` existing values; the kill-share tuning decision belongs to the operator's playtest.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Ally spawns | level `"ally": "tarek"` or `"ryn"` | One AllyShip in `World/Allies`, `ally_id` set, in group `Groups.ALLIES`, at x = `ship_px/2`, y = band centre (690), heading right; log `Ally '<id>' spawned` | — |
| No ally | `"ally"` absent or null | Nothing spawned, no log warning | — |
| Bad ally | `"ally": "bogus"` or a non-string | `LevelValidator` reports `ally: must be null, "tarek" or "ryn"`; the level spawns nothing and logs a WARN | data test fails on any shipped file |
| Patrol | `step(delta)` | x moves `speed_px_s × delta`, clamped to [`ship_px/2`, `1920 − ship_px/2`], flips direction at each edge (ping-pong); y never changes | — |
| Fire | enemies on-screen, clock reaches `fire_interval_s` | One `ally_bolt` from the ally's position aimed at the nearest live on-screen enemy, `from_ally` true, damage `allies.damage`, speed `shot_speed_px_s`; clock keeps the remainder | — |
| No target | no enemies, or all dead / off-screen | No shot | — |
| Zero aim vector | enemy exactly on the ally | Straight up | — |
| Ally kill | ally bolt deals the killing hit | `Events.enemy_killed(type, pos, true)` | — |
| Hits on the ally | enemy bullet / player overlaps the ally | No signal, no damage, the bullet keeps flying | — |
| Bolt on convoy | ally bolt overlaps a ConvoyShip | Bolt freed, convoy HP unchanged | — |
| Outcome decided | after `level_cleared` / `level_failed` | No further shots; still patrols | — |
| Kill summary | outcome decided after N kills, M by ally | One INFO line `Kills: N total, ally M (P%); target 10-15%` (P = 0 when N = 0), logged once per attempt | — |

</intent-contract>

## Code Map

- `game/entities/allies/convoy.gd`, `convoy_ship.gd/.tscn` -- the pattern to copy: tuning cached in `_ready`, `step(delta)` from `_physics_process`, static pure helpers (`step_span`), code-drawn coalition hull (`OUTLINE_COLOR` `#22E6FF`, `_draw`), outcome flags via `Events.level_cleared/level_failed`. Read-only.
- `game/core/spawner.gd` -- `_allies` container already resolved (optional); `spawn_convoy` is the template for `spawn_ally(params) -> AllyShip` (sets `ally.spawner = self`, `setup(params)` before `add_child`).
- `game/autoloads/entity_registry.gd` -- add `ALLY_SHIP` preload and `&"ally_bolt"` to `PROJECTILES`.
- `game/core/projectile.gd` -- `setup()` (l.37): add the optional `from_ally` key; `from_ally` doc (l.22) says "later epics". `_can_damage` already blocks convoy damage.
- `game/entities/projectiles/laser_bolt.gd/.tscn` -- visual and layer template (layer 2, mask 84, `monitorable = false`, gradient bolt + additive halo). AllyBolt uses one bolt, not twins.
- `game/core/enemy.gd` -- `apply_damage` records `source.from_ally`; `_die` emits `by_ally`; `is_dead()`. Read-only.
- `game/core/collision_layers.gd`, `game/core/groups.gd` -- `ALLIES` layer exists; add `Groups.ALLIES = &"allies"`.
- `game/core/playfield.gd` -- `Playfield.RECT`, `Playfield.SIZE`.
- `game/scenes/level/level.gd` -- `_ready` spawns the convoy via `has_convoy(data)`/`_spawn_convoy()` before `_director.start_level`; add `ally_id(data) -> String` (static; "" for absent/null/invalid, WARN for invalid) and `_spawn_ally(id)` beside it, plus the kill tally (connect `Events.enemy_killed`, `level_cleared`, `level_failed`; log once) and a static `kill_share_line(total, ally, lo, hi) -> String`. Update the class doc.
- `game/systems/waves/level_validator.gd` -- add `const ALLY_IDS: Array[String] = ["tarek", "ryn"]` and the `ally` rule (absent, null, or one of them); document it in the Rules list.
- `game/data/tuning.json` `allies` -- add `ship_px` 64 and `shot_speed_px_s` 1200.
- `game/data/levels/` -- add `level_dev_ally.json` (`"ally": "tarek"`, `"convoy": false`, 3–4 waves mixing Wasps, Lancers, a Needle wave with asteroids) for the kill-share playtest. `level_dev.json` keeps `"ally": null`.
- Tests: `test_convoy.gd` (Convoy fixtures and `_capture` Log hook pattern), `test_spawner.gd`, `test_projectile.gd`, `test_level_validator.gd`, `test_data_files.gd` (every level file is validated), `test_level.gd` l.86 `_make_level(level_id)`, l.1214 `_convoys()`, l.1372 `_wait_for_wave`.
- `_bmad-output/game-architecture.md` -- ends with `## As-built 2026-10-10 (Story 6.3)`; layer table l.305 already lists `allies` (visual only) and ally shots on `player_shots`.

## Tasks & Acceptance

**Execution:**
- `game/data/tuning.json` -- add `allies.ship_px` and `allies.shot_speed_px_s`. -- Data-driven.
- `game/core/groups.gd`, `game/core/projectile.gd`, `game/autoloads/entity_registry.gd` -- `Groups.ALLIES`; the `from_ally` setup key (doc updated); `ALLY_SHIP` and `&"ally_bolt"` registrations. -- Plumbing.
- `game/entities/projectiles/ally_bolt.gd/.tscn` -- `class_name AllyBolt extends Projectile`; rotate to velocity in `_ready`; capsule sized for the anti-tunnelling rule. -- Ally shot.
- `game/entities/allies/ally_ship.gd/.tscn` -- `class_name AllyShip extends Area2D` per the Always rules: `setup({"ally": id})`, `ally_id`, `spawner`, `State`, `step(delta)`, static `patrol_step(x, dir, distance, lo, hi) -> Vector2` (ping-pong), static `nearest_target(from, enemies) -> Enemy`, `_fire()`, `_draw()` (a fighter silhouette `ship_px` tall, nose up, coalition outline). -- FR34.
- `game/core/spawner.gd` -- `spawn_ally(params) -> AllyShip` (null + DEBUG log without an Allies container). -- Only Spawner creates.
- `game/systems/waves/level_validator.gd` -- the `ally` rule. -- Bad data fails loudly.
- `game/scenes/level/level.gd` -- ally spawn and kill-share summary. -- FR7 measurement.
- `game/data/levels/level_dev_ally.json` -- the playtest level. -- Kill-share check.
- `game/tests/unit/test_ally_ship.gd` (new), `test_ally_bolt.gd` (new), plus additions to `test_spawner.gd`, `test_projectile.gd`, `test_level_validator.gd`, `test_level.gd` -- cover every I/O-matrix row: scene layers/mask/monitoring and no `apply_damage`; patrol geometry and ping-pong through two crossings; fire cadence over simulated steps (exactly one shot per interval, none without targets, none after an outcome); nearest-target selection skipping dead and off-screen enemies; a real enemy killed by an ally bolt emits `by_ally == true`; a real `EnemyBullet` and the Player overlapping the ally do nothing; an ally bolt on a ConvoyShip leaves HP unchanged; the validator rule; and real-scene `level.tscn` runs of `dev_ally` (one Tarek ally under `World/Allies` that fires and scores a kill) and `dev` (no ally), plus the summary line on clear and on fail. -- Tests.
- `_bmad-output/game-architecture.md` -- append `## As-built 2026-10-10 (Story 6.4)`: AllyShip, AllyBolt, `spawn_ally`, the validator rule, the kill-share line, the new tuning keys, the readings in Design Notes, and the launch line `-- --level=dev_ally`. -- Docs match the as-built.

**Acceptance Criteria:**
- Given `level.tscn` running a level whose JSON has `"ally": "tarek"` (or `"ryn"`), when the level starts, then exactly one coalition AllyShip with that `ally_id` is under `World/Allies` on the `allies` layer, patrolling horizontally at y 690 (inside 620–760) at 150 px/s.
- Given live on-screen enemies, when each 0.5 s fire interval elapses, then the ally fires one 1-damage `player_shots` bolt with `from_ally = true` at the nearest one, and a kill it lands reports `by_ally = true` in `Events.enemy_killed`.
- Given enemy shots or the player overlapping the ally, then the ally takes no damage and blocks nothing.
- Given a level attempt ends (cleared or failed), then the log has one `Kills: N total, ally M (P%); target 10-15%` line for it.
- Given the full GUT suite run headless, then every test passes with no new orphans or errors.

## Spec Change Log

## Review Triage Log

### 2026-10-10 — Review pass
- verdicts: 18 findings — high 0, medium 0, low 10, false 8, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) The `Kills:` line was logged on every level, so no-ally levels showed a misleading "target 10-15%" — patched: logged only when the level spawned an ally (`_has_ally`), with a new `dev` test that clears and logs no `Kills:` line; docs updated.
  - `[false]` `[reject]` (blind) "The matching cyan/teal ally ship" means Tarek and Ryn must look different — DESIGN.md says allies use `coalition` in-world and speaker accents are comms-only; distinct ally art is Epic 8. "Matching" is the ship for the named id (`ally_id`).
  - `[false]` `[reject]` (blind) The kill-share playtest is untracked — finalization records it as `operator_actions` with status `awaiting-operator`.
  - `[false]` `[reject]` (blind) Ally bolts can chip asteroids and drop orbs undocumented — by design: the architecture's layer table puts ally shots on `player_shots`, which masks `asteroids`, and a kill by an ally rolls loot the same way a player kill does (decision #21).
  - `[low]` `[patch]` (blind) The final position assertion in `test_player_overlapping_the_ally_does_nothing` was vacuous — patched: deleted. The layer, mask and `monitorable` checks still prove the ally blocks nothing.
  - `[false]` `[reject]` (blind) `test_enemy_bullet_passes_through_the_ally` adds nothing — it runs the real physics overlap the AC names, rather than relying on the layer constants alone.
  - `[low]` `[patch]` (blind) The real-level ally test capped its wait on the wall clock — patched: capped at 15 s worth of physics frames.
  - `[low]` `[reject]` (blind) `"tarek"`/`"ryn"` appear as literals in two messages beside `ALLY_IDS` — two ids, and building the text from the list adds code for a rename no story plans.
  - `[low]` `[reject]` (blind) `spawn_ally` accepts any id or a second ally — its only caller (`Level`) passes a validated id once per level; a guard adds a branch for input no caller sends.
  - `[false]` `[reject]` (blind) `test_ally_off_in_dev_and_campaign_levels` passes if the key is deleted — `test_placeholder_levels_have_their_names_and_wasp_waves` already pins the campaign levels to the `level_dev` key set.
  - `[low]` `[patch]` (edge) A 0 `allies.shot_speed_px_s` would leave bolts stuck at the ally — patched with data: new `test_allies_tuning_ranges` makes the suite fail on non-positive ally tuning. No code guard added.
  - `[low]` `[reject]` (edge) `fmod` drops intervals when one step spans several — only on a frame longer than 0.5 s or an interval under one physics tick. Skipping catch-up bursts after a hitch is intended.
  - `[low]` `[reject]` (edge) An abandoned attempt (quit to title) logs no `Kills:` line — the operator plays to the clear; a hook on exit adds a path for data nobody reads.
  - `[low]` `[patch]` (verification-gap) The `fire_interval_s <= 0` guard and its WARN were untested — patched: `test_zero_fire_interval_warns_and_never_fires`.
  - `[false]` `[reject]` (intent) The diff lacks the awaiting-operator handoff — applied at finalization: status `awaiting-operator` with `operator_actions` (the precedent of Stories 1.7 and 5.8 for human playtests).
  - `[false]` `[reject]` (intent) Tarek and Ryn don't differ — same as the blind "matching" row: DESIGN.md settles the in-world colour, and the art is Epic 8.
  - `[false]` `[reject]` (intent) "Scripted horizontal path" may mean a band-wandering or per-level authored path — the architecture's level schema carries only the ally id (no path data), and a fixed ping-pong at y 690 is a scripted horizontal path inside 620-760.
  - `[low]` `[patch]` (intent) The kill share was labelled FR7 (which is no friendly fire) — patched: relabelled FR34 in `level.gd`, `ally_ship.gd` and the architecture.

## Design Notes

**Readings this spec records (no GDD conflict).** "Scripted horizontal path" = a ping-pong across the full playfield width at the band centre (y 690), starting at the left edge heading right, the same path shape as the convoy (GDD #45). Tarek and Ryn share the one ship and path in this story; both are `coalition` in-world (UX DESIGN: speaker accents are comms-only). "Nearest enemy" = nearest live enemy inside the playfield, so shots aren't wasted on enemies still entering from off-screen. The ally is a code-drawn placeholder until Epic 8 art.

**Kill-share AC is a human playtest.** The 10–15 % share depends on how the player plays, so automated tests prove only the tally and the log line. The agent leaves the playtest and any `tuning.allies` retune plus decision-log entry to the operator.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0 (new `class_name`s)
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass (see `LOCAL.md` for `<GODOT_DIR>`)

**Manual checks (if no CLI):**
- Operator: run `level.tscn -- --level=dev_ally` through to the clear, read the `Kills:` line in the log, and if the ally share is outside 10–15 %, tune `allies.fire_interval_s` (or `damage`) in `tuning.json` and log the change in the GDD decision log. Also judge that Tarek reads as a squadmate and doesn't carry the fight.

## Auto Run Result

Status: awaiting-operator

**Summary:** Story 6.4 (FR34, SHOULD) is built. When a level JSON has `"ally": "tarek"` or `"ryn"`, `Spawner.spawn_ally` puts one invincible `AllyShip` into `World/Allies`. The ship is on the `allies` layer, detects nothing and nothing detects it, and it has no `apply_damage`. It ping-pongs across the playfield at y 690 (the centre of `allies.patrol_band_y`) at 150 px/s. Every 0.5 s it re-acquires the nearest live on-screen enemy and fires a 1-damage `AllyBolt`: a `player_shots` projectile with `from_ally = true`, rotated to its velocity. A kill from that bolt reports `by_ally = true`. The ally stops firing once the level outcome is decided and keeps patrolling. `LevelValidator` rejects any `ally` value other than absent, null, `tarek` or `ryn`. On a level with an ally, the Level logs one `[INFO][combat] Kills: N total, ally M (P%); target 10-15%` line per attempt. The new `level_dev_ally.json` (Tarek, 4 waves) is for the kill-share playtest. The 10-15 % kill-share check needs a human playthrough, so it is owed as `operator_actions` above.

**Files changed:**
- `game/entities/allies/ally_ship.gd/.tscn` (new): the ally: layers, patrol, fire clock, nearest-target pick and the code-drawn fighter.
- `game/entities/projectiles/ally_bolt.gd/.tscn` (new): the ally's shot.
- `game/core/projectile.gd`: the optional `from_ally` setup key.
- `game/core/spawner.gd`: `spawn_ally`.
- `game/autoloads/entity_registry.gd`: `ALLY_SHIP` and `&"ally_bolt"`.
- `game/core/groups.gd`: `Groups.ALLIES`.
- `game/systems/waves/level_validator.gd`: `ALLY_IDS`, `is_valid_ally` and the `ally` rule.
- `game/scenes/level/level.gd`: `ally_id`, `_spawn_ally`, the kill tally and `kill_share_line`.
- `game/data/tuning.json`: `allies.ship_px` (64) and `allies.shot_speed_px_s` (1200).
- `game/data/levels/level_dev_ally.json` (new): the playtest level.
- Tests: `test_ally_ship.gd` and `test_ally_bolt.gd` (new), plus additions to `test_spawner.gd`, `test_projectile.gd`, `test_level_validator.gd`, `test_groups.gd`, `test_level.gd` and `test_data_files.gd`.
- `_bmad-output/game-architecture.md`: `## As-built 2026-10-10 (Story 6.4)`.

**Review findings:** 18 (high 0, medium 0, low 10, false 8).
- Patched (6 entries, all low):
  - the `Kills:` line is now logged on ally levels only;
  - the vacuous test assertion is removed;
  - the real-level test waits a physics-frame count, not wall-clock time;
  - the zero fire interval is tested;
  - the allies tuning has a data range test;
  - the kill share is relabelled FR34.
- Deferred: none.
- Rejected, each with its reason in the Review Triage Log:
  - the ally-id literals in messages;
  - the `spawn_ally` id guard;
  - the `fmod` multi-interval catch-up;
  - no `Kills:` line on an abandoned attempt;
  - 8 false findings (Tarek/Ryn look alike (2 rows), the untracked playtest and missing handoff (2 rows), ally bolts and asteroids, the bullet pass-through test, the key-set check, the path reading).

**Follow-up review recommended:** false. Only low entries were patched (6), and none was high or medium.

**Verification:**
- `--import` exited 0.
- The full headless GUT suite passed 1557/1557 before the patches and 1560/1560 after, with no failures.
- Every I/O-matrix row has a covering test that ran and passed.

**Residual risks:**
- Not checked by tests: the kill share itself, the feel, and whether Tarek reads as a squadmate (see `operator_actions`).
- Tarek and Ryn are the same placeholder ship until Epic 8 art.
- `level_1/2/3.json` keep `"ally": null` until Epic 7.

## Operator Confirmation

Confirmed 2026-10-10: the external actions this story owed were carried out.

- Launch the level scene directly in a debug build with `-- --level=dev_ally` ("<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game res://scenes/level/level.tscn -- --level=dev_ally), play it through to the clear, and read the `[INFO][combat] Kills: N total, ally M (P%); target 10-15%` line in the log.
- If the ally share is outside roughly 10-15 %, retune `allies.fire_interval_s` (or `allies.damage`) in `game/data/tuning.json`, never code, replay to confirm, and record the change in the GDD decision log (`_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md`).
- While playing, confirm Tarek reads as a cyan squadmate patrolling at y 690 above the player, that his shots visibly pick off enemies without carrying the fight, and that his ship never blocks or hurts you.

_Appended by the bmad-loop orchestrator (`bmad-loop confirm`, #335): a human confirmed these external actions out of band, and the story was advanced from `awaiting-operator` to `done`._
