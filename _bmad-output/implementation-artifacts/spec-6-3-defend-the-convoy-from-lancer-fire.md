---
title: 'Story 6.3: Defend the Convoy from Lancer Fire'
type: 'feature'
created: '2026-10-10'
status: 'done'
baseline_revision: '86b70bc2a8fd2eaa1273515f8253d11c04eba18f'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-6-context.md'
warnings: ['oversized']
deferred:
  - summary: >-
      One unidentified intermittent failure in test_level.gd (57/58), seen once while the implementer re-ran it after the review patches.
    evidence: |-
      The failing run's log wasn't captured. The next 12 implementer runs, 6 further runs and two full suites all passed (58/58, 1515/1515). It may be one of the two new real-time Lancer tests (test_dev_convoy_lancer_shots_hit_the_convoy_for_five, test_dev_lancer_shots_aim_at_the_player_without_a_convoy) or an older timing-sensitive test. Capturing the failing test's name from a failing run would settle it.
    location: >-
      game/tests/unit/test_level.gd
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** In a convoy level, Lancers still aim only at the player, so the player can protect the cargo just by dodging (FR20 convoy targeting, FR33, MUST). An enemy shot that reaches a convoy ship also applies its own heart `damage` (the 6.1 interim rule), not GDD decision #23's amounts: 5 if aimed at the convoy, `damage.convoy_stray` (2) otherwise.

**Approach:** Give `EnemyBullet` a `targets_convoy` flag (setup param, default false). On a convoy area it applies `damage.convoy_aimed` when the flag is set, else `damage.convoy_stray`. Everywhere else it still applies its own `damage`. In a level with a live convoy, the Lancer rolls `enemies.lancer.convoy_aim_chance` (0.5) at each shot. On a hit it aims at the centre of a random convoy ship and sets `targets_convoy = true`. Otherwise, and always without a convoy, it aims at the player as it does now.

## Boundaries & Constraints

**Always:**
- Every number comes from `tuning.json` through `Config`: `damage.convoy_aimed`, `damage.convoy_stray`, `enemies.lancer.convoy_aim_chance`. Cache them in `_ready`. Static typing everywhere. Use the `CollisionLayers`/`Groups` constants.
- Only the projectile applies damage (one side). The convoy still blocks every enemy shot, and the shot frees itself after one damage instance.
- The roll and the ship pick happen once per shot, at fire time, after the telegraph. Use the Lancer's own `rng: RandomNumberGenerator` (randomized in `_ready`, like Bastion and Needle) so tests can seed it. Look up the convoy once per shot, never per frame.
- A convoy-aimed bullet that hits the player still costs the player `damage` hearts (body-block, subject to i-frames and Shield). A bullet that hits an asteroid still does no damage.
- Write the failing GUT test first.

**Never:**
- Don't change the Lancer's telegraph, cadence, speed or the bullet's look. Don't make Bastion or Needle aim at the convoy.
- Don't change Convoy, ConvoyShip, Maul, Player or WaveDirector logic. Player-shot convoy blocking (DW-32/33) stays as it is.
- No allies (6.4). Don't change `level_1/2/3.json` (Epic 7).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Convoy roll hits | live convoy, `rng.randf() < convoy_aim_chance` | Bullet velocity = unit(ship centre − muzzle) × `bullet_speed_px_s` toward a ship picked by `rng.randi_range(0, n−1)`; `targets_convoy` true | — |
| Convoy roll misses | live convoy, roll ≥ chance | Aims at the player exactly as before; `targets_convoy` false | — |
| No convoy | no `Groups.CONVOY` node, or `is_lost()`, or it has no ships | Always aims at the player; no roll is consumed; `targets_convoy` false | — |
| Odds | seeded rng, 1000 shots, chance 0.5 | Convoy share within 0.45–0.55 | — |
| Chance bounds | chance 0 / 1 | Never / always convoy | — |
| Aimed hit | `targets_convoy` bullet overlaps a ConvoyShip (any ship) | Convoy HP −`damage.convoy_aimed` (5) once, bullet freed | — |
| Stray hit | `targets_convoy` false (player-aimed Lancer bullet, Bastion bullet, NeedleBolt) overlaps a ConvoyShip | Convoy HP −`damage.convoy_stray` (2) once, bullet freed | — |
| Player hit | either bullet overlaps the Player | Player takes `damage` hearts (unchanged) | — |
| Muzzle on ship centre | zero vector to the chosen ship | Straight down (same fallback as `_aim_from`) | — |

</intent-contract>

## Code Map

- `game/entities/projectiles/enemy_bullet.gd` -- `EnemyBullet extends Projectile`: overrides `_can_damage` (no asteroid damage) and `_on_impact` (none). It has no convoy-specific damage yet. Add `targets_convoy` here, plus a damage-amount override for convoy areas.
- `game/core/projectile.gd` -- `setup(params)` (position/velocity/damage), `_on_area_entered` applies `area.call(&"apply_damage", damage, self)` once, static `is_convoy(area)`. Add one hook, `_damage_for(area) -> int` (base returns `damage`), and use it in `_on_area_entered`. Everything else is read-only.
- `game/entities/projectiles/needle_bolt.gd` -- extends EnemyBullet, so it inherits the stray rule. No change.
- `game/entities/enemies/lancer/lancer.gd` -- `_fire()` (l.144) builds `{"position", "velocity": _aim_from(origin) * _bullet_speed, "damage"}`. `_ready` caches the tuning. The class doc (l.1–16) says "toward where the player is".
- `game/core/enemy.gd` -- `_aim_from(origin)` (l.146): the player-aim helper with the straight-down fallback. Reuse it, don't change it.
- `game/entities/allies/convoy.gd` -- `Groups.CONVOY` node, `ships() -> Array[ConvoyShip]`, `is_lost()`. Read-only.
- `game/entities/enemies/bastion/bastion.gd` (`_fire`, l.204) and `needle/needle.gd` (`_fire`, l.180) -- they never pass `targets_convoy`, so their shots are strays. No change.
- `game/data/tuning.json` -- `damage.convoy_aimed` 5, `damage.convoy_stray` 2, and `enemies.lancer.convoy_aim_chance` 0.5 already exist. No new key.
- `game/tests/unit/test_convoy.gd` l.359–368 -- `test_enemy_bullet_damages_the_convoy_by_its_damage` pins the 6.1 interim rule (HP 97 from damage 3). It must change to the stray amount.
- `game/tests/unit/test_lancer.gd` -- the `_make_world`/`_make_player`/`_spawn`/`_step_until`/`_bullets` helpers, and `Config.tuning[...]` overrides reset by `Config.load_data()` in `after_each`. `test_enemy_bullet.gd`, `test_needle_bolt.gd`, `test_bastion.gd` -- bullet test patterns.
- `game/tests/unit/test_level.gd` l.1224+ -- the real `dev_convoy` level helpers (`_make_level`, `_convoys`, `_wait_for_wave`, `debug_resolve_wave`, `_on_convoy_hp`). Wave 2 of `level_dev_convoy.json` already has 2 Lancers.
- `_bmad-output/game-architecture.md` -- the as-built sections end with `## As-built 2026-10-10 (Story 6.2)`. The damage rule at l.310 already states the 5/2 amounts.

## Tasks & Acceptance

**Execution:**
- `game/core/projectile.gd` -- add `_damage_for(area: Area2D) -> int` (returns `damage`), document it next to `_can_damage`, and call it in `_on_area_entered`. Update the class doc line that says EnemyBullet overrides both hooks. -- A per-target amount without duplicating the hit path.
- `game/entities/projectiles/enemy_bullet.gd` -- add `var targets_convoy: bool = false`. Override `setup` to read the `targets_convoy` key (call `super`). Cache `damage.convoy_aimed`/`convoy_stray` in `_ready`. Override `_damage_for`: on a convoy area, the aimed amount when `targets_convoy`, else the stray amount; otherwise `damage`. Update the class doc. -- GDD #23.
- `game/entities/enemies/lancer/lancer.gd` -- add `var rng := RandomNumberGenerator.new()` (randomized in `_ready`) and cache `convoy_aim_chance`. In `_fire`, add a `_pick_convoy_ship() -> ConvoyShip`: look up `Groups.CONVOY` once; return null when it is missing, `is_lost()` or has no ships; otherwise roll `rng.randf() < chance` and pick `rng.randi_range`. Aim at that ship's `global_position` (with the straight-down zero-vector fallback) and pass `"targets_convoy": true`; otherwise use `_aim_from` and pass `false`. Update the class doc. -- FR20 convoy targeting.
- `game/tests/unit/test_lancer.gd`, `test_enemy_bullet.gd`, `test_needle_bolt.gd`, `test_bastion.gd` (one stray check through a real Bastion bullet or a bullet spawned with its params), `test_projectile.gd` (the base `_damage_for`), and `test_convoy.gd` (replace the interim test with aimed 5 and stray 2 by real overlap) -- cover every I/O-matrix row, with tuning overrides for chance 0/1 and a seeded 1000-shot odds check. Add a real-scene test in `test_level.gd`: on `dev_convoy` wave 2 with `convoy_aim_chance` forced to 1 and the Player parked, a Lancer shot lands and convoy HP drops by exactly 5 per hit. On `dev` (no convoy) with chance 1, every Lancer bullet aims at the player with `targets_convoy` false. -- Tests.
- `_bmad-output/game-architecture.md` -- append `## As-built 2026-10-10 (Story 6.3)`: the hook, the flag, the Lancer roll and pick, the readings below, the tests and the `-- --level=dev_convoy` launch line. -- Docs match the as-built.

**Acceptance Criteria:**
- Given `dev_convoy` running on `level.tscn` at its Lancer wave, when a Lancer fires, then the bullet aims at the player or at a random convoy ship (a convoy-aimed bullet has `targets_convoy == true` and points at a ship centre), and a convoy-aimed bullet that reaches the convoy lowers its HP by exactly 5 and frees itself.
- Given a level without a convoy, when a Lancer fires, then it always aims at the player and `targets_convoy` is false, even with `convoy_aim_chance` at 1.
- Given a player-aimed Lancer bullet, a Bastion bullet or a Needle bolt overlapping a convoy ship, then it stops, frees itself and the convoy loses exactly `damage.convoy_stray` (2).
- Given the full GUT suite run headless, then every test passes, with no new orphans or errors.

## Spec Change Log

## Review Triage Log

### 2026-10-10 — Review pass
- verdicts: 25 findings — high 0, medium 0, low 16, false 9, maybe-false 0
- findings:
  - `[false]` `[reject]` (blind) The spec file isn't in the diff — on purpose: the spec is the claims file, shown only to the edge-case layer, and it is committed with the change.
  - `[low]` `[reject]` (blind) `test_convoy_without_ships_counts_as_no_convoy` empties `convoy.ships()` through the internal array — it is test-only, `ships()` is documented to return the live array, and a fixture or seam would add surface for a case no level reaches.
  - `[false]` `[reject]` (blind) EnemyBullet applies 0 convoy damage before `_ready` or when a key is missing — only the Spawner creates bullets, and it adds them to the tree before any overlap. `Config` asserts on missing keys, so it fails loudly.
  - `[low]` `[reject]` (blind) `bool(params.get("targets_convoy"))` accepts non-bool values — the only producer is `Lancer._fire`, which passes a bool. A type guard adds a branch for input no caller sends.
  - `[false]` `[reject]` (blind) Nothing checks the ship pick is uniform — `test_roll_and_pick_use_the_lancer_rng` pins the pick to `rng.randi_range(0, n - 1)` exactly with a same-seed mirror, and that is uniform by construction.
  - `[low]` `[patch]` (blind) `test_seeded_odds_over_1000_shots` relies on the shipped 0.5 chance — patched: the test sets `convoy_aim_chance` to 0.5 explicitly.
  - `[low]` `[reject]` (blind) The level-test loop waits for 2 hits but asserts 1 — the per-hit exact-5 check runs on every hit seen. Waiting longer only costs time when just one lands, and the test still proves the AC.
  - `[low]` `[patch]` (blind) The level test's `landed >= hits` check counts shots freed for any reason — patched: the vacuous check and its `hits` bookkeeping were removed. Free-on-hit is proven by the real-overlap tests in `test_convoy.gd`.
  - `[false]` `[reject]` (blind) Wave 1 bullets might still be flying in wave 2 — wave 1 of `dev_convoy` is 6 Wasps, and Wasps never fire (`wasp.gd` has no `spawn_projectile`).
  - `[low]` `[reject]` (blind) The 2 px aim tolerance is fragile — the loop awaits every physics frame, so each bullet is sampled within a frame of spawning. A bullet stays on its own ray, so only the ship's drift (≤ 0.67 px per frame) counts, and 2 px covers about 3 frames. It passed in every run.
  - `[low]` `[reject]` (blind) The player-hit rule isn't tested against a real Player — the bullet calls the existing, tested `Player.apply_damage(damage)`. The new code only chooses the amount, which `test_aimed_bullet_still_costs_the_player_its_own_damage` covers.
  - `[low]` `[patch]` (blind) The architecture's 6.1 interim-rule lines have no pointer to 6.3 — patched: the 6.3 as-built entry now says it replaces the 6.1 interim rule and its interim test.
  - `[low]` `[reject]` (blind) The `_damage_for` doc doesn't say it excludes Missile splash — the doc says the hook applies to `area` once `_can_damage` allows it (the direct hit), and `Missile` documents its own splash. No caller is misled.
  - `[low]` `[patch]` (blind) The EnemyBullet class doc leaves out the Needle — patched: it now lists the Needle via NeedleBolt.
  - `[false]` `[reject]` (blind) A freed ship in `ships()` or several convoy nodes — ConvoyShips are children of the Convoy and never freed on their own, and `Spawner.spawn_convoy` creates at most one per level.
  - `[low]` `[reject]` (edge) Lancers keep aiming at a convoy whose level outcome is decided but which isn't lost — after `level_cleared` or `level_failed` the convoy ignores hits and the level is leaving play, so nobody sees it. A fix needs new public surface (`is_ended()`).
  - `[low]` `[reject]` (edge) A `targets_convoy` param that isn't a bool — same root cause and reason as the blind bool row.
  - `[low]` `[patch]` (edge) The "any ship" test aimed at FlankBottom actually hits FlankTop first — patched: the bullet now fires upward from below FlankBottom.
  - `[low]` `[patch]` (edge) The level test's landed-and-freed check cannot fail — same root cause as the blind `landed` row, patched there.
  - `[low]` `[reject]` (edge) The exact-5 check may run on a single sample — every hit seen is checked, and one hit already proves the amount. More samples only add run time.
  - `[low]` `[patch]` (edge, claim) A reader may take free-on-hit as proven at the real-scene level — same patch as the `landed` row; the test's doc no longer claims it.
  - `[false]` `[reject]` (intent) Level 1 shows no Lancer split because `level_1.json` has `convoy: false` — the epic puts the Level 1 convoy in Epic 7 (the placeholder level files keep convoy false until then), and the ACs name "a level with a convoy".
  - `[false]` `[reject]` (intent) The 50/50 odds are measured only at unit level — the odds are a property of the roll. The seeded 1000-shot test and the mirror test prove it, and the real-level tests prove the routing.
  - `[false]` `[reject]` (intent) Bastion and Needle stray damage is tested by direct `_on_area_entered` calls — real physics overlap is covered for the same `EnemyBullet._damage_for` path in `test_convoy.gd`, and NeedleBolt adds no override.
  - `[false]` `[reject]` (intent) Body-blocking convoy-aimed shots isn't tested in play — the amount on the player is unit-tested, and the hurtbox path is unchanged. The feel of blocking is the operator check.

## Design Notes

**Readings this spec records (no GDD conflict).** "Aims at a random convoy ship" means the ship's centre at fire time, with no lead, the same as the player aim. A 40 px/s convoy can still drift so a shot misses, which is acceptable. A lost convoy counts as no convoy. Any convoy ship hit by an aimed bullet takes the aimed amount, not just the chosen one, because the AC keys on the flag alone. The flag lives on `EnemyBullet`, so the Bastion and Needle default to strays with no code change.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass (see `LOCAL.md` for `<GODOT_DIR>`)

**Manual checks (if no CLI):**
- Operator (feel, not verified by tests): run `level.tscn -- --level=dev_convoy` to wave 2. Check that the Lancers visibly split fire, and that defending the cargo (body-blocking or killing Lancers) feels fair.

## Auto Run Result

Status: done

**Summary:** Lancer convoy targeting (FR20, FR33) is built. With a live convoy, each Lancer shot rolls `enemies.lancer.convoy_aim_chance` (0.5) on its own seedable `rng`, at fire time after the telegraph. On a hit it aims at the centre of a random convoy ship and marks the bullet `targets_convoy`. Otherwise, and always without a convoy (none, lost or shipless; no roll consumed), it aims at the player as before. `EnemyBullet` reads the `targets_convoy` setup key. On a convoy ship it applies `damage.convoy_aimed` (5) when the flag is set, else `damage.convoy_stray` (2). Every other target still takes the bullet's own `damage`, so a body-blocked aimed shot costs the player the usual heart. A new `Projectile._damage_for(area)` hook carries this. Bastion shots and Needle bolts become strays with no code change. This replaces the 6.1 interim rule.

**Files changed:**
- `game/core/projectile.gd`: the `_damage_for(area)` hook, used in `_on_area_entered`.
- `game/entities/projectiles/enemy_bullet.gd`: the `targets_convoy` flag and setup key, the cached convoy amounts, the aimed/stray `_damage_for`.
- `game/entities/enemies/lancer/lancer.gd`: `rng`, the cached chance, `_pick_convoy_ship()`, static `_aim_at`, and `targets_convoy` passed with each shot.
- `game/tests/unit/test_lancer.gd`, `test_enemy_bullet.gd`, `test_projectile.gd`, `test_bastion.gd`, `test_needle_bolt.gd`, `test_convoy.gd` (the interim test replaced), `test_level.gd` (the real `dev_convoy` and `dev` scenes): coverage of every matrix row and AC.
- `_bmad-output/game-architecture.md`: `## As-built 2026-10-10 (Story 6.3)`.

**Review findings:** 25 (high 0, medium 0, low 16, false 9).
- Patched (5 entries, all low):
  - the odds test sets its chance explicitly;
  - the vacuous level-test `landed` check is removed (3 rows);
  - the FlankBottom test geometry is fixed;
  - the EnemyBullet doc names the Needle;
  - the architecture points from 6.3 to the replaced 6.1 rule.
- Deferred (1): a one-off `test_level.gd` failure seen during the implementer's re-run that couldn't be identified. It isn't a reviewer finding; it is recorded for tracking.
- Rejected, each with its reason in the Review Triage Log:
  - the shipless-convoy test seam;
  - the bool type guard (2 rows);
  - the 2-hit wait against 1 assert;
  - the 2 px tolerance;
  - no real-Player hit test;
  - the `_damage_for` splash doc;
  - an ended but not lost convoy;
  - a single exact-5 sample;
  - and 9 false findings.

**Follow-up review recommended:** false. Only low entries were patched (5), and all are test or doc changes.

**Verification:**
- `--import` exited 0.
- The full headless GUT suite passed 1515/1515, before and after the patches.
- After the patches, `test_level.gd` passed 6 more isolated runs (58/58).
- Every I/O-matrix row has a covering test that ran and passed.

**Residual risks:**
- One `test_level.gd` failure, out of about 20 isolated runs, was never reproduced (deferred above). The two new real-time Lancer level tests are the likely suspects.
- Feel, not verified by tests: play `level.tscn -- --level=dev_convoy` to wave 2. Check that the Lancers visibly split fire and that defending the cargo feels fair.
- By design, shots aim at a ship's centre with no lead, so the 40 px/s convoy can sometimes drift out of a shot's path.
