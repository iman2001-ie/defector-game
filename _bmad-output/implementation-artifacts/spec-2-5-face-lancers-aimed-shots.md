---
title: "Story 2.5: Face Lancers' Aimed Shots"
type: 'feature'
created: '2026-10-07'
baseline_revision: '6cad11a922c2edd30ccb48ff631445a4b329a74e'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-2-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
warnings: ['oversized']
deferred:
  - summary: >-
      test_wave_director.test_f3_resolves_the_wave_and_fires_pending_triggers_in_order fails deterministically on this machine ("the skipped group never spawns": expected 0, got 1).
    evidence: |-
      Fails 5/5 runs and also fails at HEAD dfa8063 and at baseline 6cad11a922c2edd30ccb48ff631445a4b329a74e, so it predates Story 2.5.
      The test waits wait_process_frames(2) after F3 with gap_s 0.05; if those two frames take longer than 0.05 s the next wave's single Wasp has already spawned and is counted.
      Likely fix: count only enemies from the skipped group, or assert before the gap can elapse.
    location: >-
      game/tests/unit/test_wave_director.gd:387
    severity: medium
---

<intent-contract>

## Intent

**Problem:** There is no Lancer and no enemy bullet. The GDD Lancer (FR20, FR25, NFR6) is a medium, 8 HP enemy that strafes horizontally in the top 35% at 200 px/s and, after a 0.3 s muzzle glow, fires one bullet aimed at the player at 450 px/s. The shared `enemy_bullet.tscn` that Stories 2.7 and 7.x reuse doesn't exist, and enemies have no way to reach the `Spawner` to fire.

**Approach:** Add `Lancer` (`class_name`, `enum State { ENTER, STRAFE, TELEGRAPH }`) and `EnemyBullet` (`class_name`, extends `Projectile`), register both in `EntityRegistry`, and have `Spawner.spawn_enemy` hand itself to every enemy (new `Enemy.spawner` field, set before `add_child`) so shooters request bullets through it. Put two Lancers in `level_dev.json` wave 3 and extend the data tests (bullet speeds, Lancer zone).

## Boundaries & Constraints

**Always:**
- Statically typed GDScript. `_state` is assigned only inside `_enter_state()`. `_physics_process(delta)` only calls a public `step(delta)` holding the `match`, as `Wasp` does, so tests drive it deterministically.
- Numbers from `Config`, read once in `_ready`: `enemies.lancer.strafe_speed_px_s`, `zone_height_ratio`, `fire_interval_s`, `telegraph_s`, `bullet_speed_px_s`, plus a new key `muzzle_glow_energy` 2.5; bullet damage is `damage.bullet_hearts`. No per-frame allocation, group lookup or logging. The player lookup (`get_first_node_in_group(&"player")`) happens once per shot.
- Entry (spawned with a `slot`): `"top"` starts at `(slot.x, -sprite_px/2)`; `"sides"` starts at `(-sprite_px/2, slot.y)` or `(width + sprite_px/2, slot.y)` from the nearer side; other values → `Log.warn("spawn", …)` and top. It flies to the slot at the strafe speed. A slot below `zone_height_ratio × Playfield.SIZE.y` (378) is clamped to it with one WARN. Without a `slot`, it starts in STRAFE at its position.
- STRAFE and TELEGRAPH both move horizontally at the strafe speed between `x = sprite_px/2` and `width − sprite_px/2`, flipping direction at a bound (clamped onto it). The first direction points toward the screen centre (+x when `slot.x ≤ width/2`). y never changes after ENTER.
- Fire cycle: the timer runs only in STRAFE and starts at 0 each time STRAFE is entered. When it reaches `fire_interval_s` → TELEGRAPH (`MuzzleGlow` visible with `self_modulate = Color(e, e, e)`). After `telegraph_s` the Lancer fires one bullet and goes back to STRAFE (glow hidden). The shot's direction is snapshotted at fire time: toward the player's `global_position`, or `Vector2.DOWN` with no player or a zero vector. The shot spawns at `Muzzle.global_position` via `spawner.spawn_projectile(&"enemy_bullet", {position, velocity, damage})`. With no valid spawner it doesn't fire (one `Log.debug("spawn", …)` per Lancer) and the cycle continues.
- `EnemyBullet`: layer `ENEMY_SHOTS` (8), mask `MASK_ENEMY_SHOTS` (81). A round visual in `enemy` #FF2BD6 with a white core, ≥ `weapons.enemy_bullet.min_diameter_px` (16). A `CapsuleShape2D` (radius ≥ 8, height ≥ `max_speed_px_s / 60`) rotated in `_ready` so its long axis follows `velocity`. On overlap it calls `apply_damage(damage, self)` only if the target has the method **and** is not on the `ASTEROIDS` layer (only player shots damage asteroids, per the architecture), then frees itself. No impact feedback (player-hit feedback arrives in Epic 3). Add a `_can_damage(area) -> bool` hook (default `true`) to `Projectile._on_area_entered` for this.

**Never:**
- No convoy aiming (`convoy_aim_chance`, `targets_convoy`: Epic 6), no player hearts or `apply_damage` on the Player (Epic 3), no Needle, Bastion or Maul. No changes to `WaveDirector`, `Formation`, `Events`, the sandbox, the bench or `sprint-status.yaml`. No new art files: polygons and gradient textures inside the `.tscn`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Top entry | slot (960,160), entry top | starts (960,-48) in ENTER, 200 px/s to the slot, then STRAFE | — |
| Side entry | slot (400,160), entry sides | starts (-48,160); slot x > 960 starts at (1968,160) | — |
| Unknown entry / low slot | entry "spiral"; slot y 520 | top entry; holds y 378 | WARN each |
| Strafe | STRAFE at x 1860 moving +x, 1 s | reaches 1872, flips, moves −x; y unchanged | — |
| Fire | STRAFE for 2.0 s, player (960,900) | TELEGRAPH: glow on, still strafing, 0.3 s; then one `enemy_bullet` at Muzzle, velocity 450 toward (960,900), glow off, STRAFE | no player → straight down |
| No spawner | Lancer created without Spawner | cycle runs, no bullet, no crash | DEBUG once |
| Bullet hits player stand-in | area with `apply_damage` on layer PLAYER | called once with (1, bullet); bullet freed | target without the method: freed only |
| Bullet hits asteroid | real Asteroid overlap | asteroid HP unchanged; bullet freed | — |
| Pause | tree paused | Lancer and bullets frozen | — |

</intent-contract>

## Code Map

- `game/core/enemy.gd` -- base: `setup` stores `_spawn_position`; `_ready` applies HP, tier, hitbox (`sprite_px/2 × hitbox_ratio`). Add `var spawner: Spawner` (doc: set by Spawner before `add_child`; shooters request projectiles through it).
- `game/core/spawner.gd` `spawn_enemy` L64-79 -- set `enemy.spawner = self` before `enemy.setup(params)`/`add_child`. `spawn_projectile` returns null for an unknown id.
- `game/core/projectile.gd` `_on_area_entered` -- add `_can_damage(area)` guard around the `apply_damage` call; `_on_impact` is the feedback hook (EnemyBullet overrides it with `pass`). `OFFSCREEN_MARGIN_PX` frees off-screen bullets.
- `game/entities/enemies/wasp/wasp.gd` -- the pattern to mirror: `setup` (slot/entry), `_ready` (super first, then tuning), `step`, `_enter_state`, `_aim()`, entry/clamp WARN text, `PLAYER_GROUP`.
- `game/entities/projectiles/laser_bolt.tscn` -- scene style to mirror: inline `GradientTexture2D` + additive `CanvasItemMaterial`, `Hitbox` capsule.
- `game/autoloads/entity_registry.gd` -- add `&"lancer"` to `ENEMIES` and `&"enemy_bullet"` to `PROJECTILES`; `Config` validates level types against `enemy_types()` automatically.
- `game/core/collision_layers.gd` -- `ENEMY_SHOTS`, `MASK_ENEMY_SHOTS`, `ASTEROIDS`.
- `game/data/tuning.json` `enemies.lancer` -- already has hp 8, tier medium, hitbox_ratio, strafe 200, zone 0.35, fire 2.0, bullet 450, telegraph 0.3, convoy_aim_chance (leave unused); add `muzzle_glow_energy`. `weapons.enemy_bullet` holds min diameter 16, max speed 450, min telegraph 0.3. `damage.bullet_hearts` 1.
- `game/data/levels/level_dev.json` wave 3 -- put `{ "type": "lancer", "count": 2, "formation": "grid_2x1", "entry": "sides" }` **before** the Wasp entry (Lancers take row y 160, Wasps 280/400, both inside their zones). `test_level.test_clearing_every_dev_wave_clears_the_level` uses F3, so it stays valid.
- `game/tests/data/test_data_files.gd` L78-129 `test_wasp_formations_fit_the_top_zone` -- generalise to check each Wasp and Lancer entry against its own `enemies.<type>.zone_height_ratio` and sprite half-width, with `checked > 0` per type.
- `game/tests/unit/test_wasp.gd` -- test style (`_make`, manual `step`, `_make_player`, `Log.sink` capture, `Config.load_data()` in `after_each`).
- `game/tests/unit/test_projectile.gd`, `test_spawner.gd`, `test_combat.gd` -- style for overlap, registry and layer tests; `tests/fixtures/damage_target.gd` is an `apply_damage` stand-in.
- New `class_name`s (`Lancer`, `EnemyBullet`) need `--import`; commit the new `.gd.uid` files.

## Tasks & Acceptance

**Execution (write each test first, red, then the code):**
- `game/data/tuning.json` -- add `"muzzle_glow_energy": 2.5` to `enemies.lancer`.
- `game/core/enemy.gd`, `game/core/spawner.gd`, `game/core/projectile.gd` -- the `spawner` field, its injection, and the `_can_damage` hook.
- `game/entities/projectiles/enemy_bullet.gd` + `.tscn` -- `class_name EnemyBullet extends Projectile` per the Always rules.
- `game/entities/enemies/lancer/lancer.gd` + `.tscn` -- `class_name Lancer extends Enemy`; `sprite_px` 96; a distinct `Hull` Polygon2D silhouette (wide, lance-nosed, `enemy` colour); `Muzzle` Marker2D at the nose (pointing down) with a hidden `MuzzleGlow` child. Accessors `state()`, `formation_slot()`, `strafe_dir()`, `is_glowing()`.
- `game/autoloads/entity_registry.gd` -- register both.
- `game/data/levels/level_dev.json` -- the wave 3 Lancer entry.
- `game/tests/unit/test_lancer.gd` -- every Lancer matrix row; tuning reads (change a value in `Config.tuning`, restore with `Config.load_data()`); a source scan that `_state =` occurs exactly once; HP 8 and MEDIUM tier; the shot is spawned through a real `Spawner` (test world with a `Projectiles` container) and its velocity length is 450.
- `game/tests/unit/test_enemy_bullet.gd` -- layers and mask equal the constants; visual diameter ≥ 16 and colour; capsule radius ≥ 8, height ≥ max speed / 60, axis follows velocity; the three bullet matrix rows (the asteroid one with a real `Asteroid` through physics).
- `game/tests/unit/test_spawner.gd` -- registry has `lancer` and `enemy_bullet`; a spawned enemy's `spawner` is that Spawner.
- `game/tests/unit/test_level.gd` -- level_dev wave 3 contains Lancers (counted, in `World/Enemies`) after advancing with F3.
- `game/tests/data/test_data_files.gd` -- the generalised zone test, plus: every `bullet_speed_px_s` under `tuning.enemies` and every key ending `_speed_px_s` under `tuning.boss` is ≤ `weapons.enemy_bullet.max_speed_px_s` (walk must find lancer, bastion, boss entries); Lancer tuning ranges (speeds, interval, glow energy > 1, 0 < zone ≤ 1).
- `_bmad-output/game-architecture.md` -- a short "As-built 2026-10-07 (Story 2.5)" note: Lancer states, `EnemyBullet` and its asteroid rule, `Enemy.spawner` injection, `Projectile._can_damage`, the new tuning key.
- Run `--import`, then the full GUT suite.

**Acceptance Criteria:**
- Given a level wave with a Lancer entry, when it spawns, then the Lancer (8 HP, medium tier) enters to a slot within the top 35% and strafes horizontally at 200 px/s, staying on screen.
- Given a strafing Lancer, when its fire timer reaches 2.0 s, then its muzzle glows for 0.3 s, then it fires one `enemy_bullet` aimed at the player's current position at 450 px/s.
- Given `enemy_bullet.tscn`, when fired, then it is `enemy` magenta with a bright core, ≥ 16 px, on `enemy_shots` masking `player`, `asteroids` and `convoy`, with a travel-aligned capsule ≥ speed / 60, stopped by asteroids, and on overlap it calls `apply_damage` only on targets that have it, then frees itself.
- Given the headless GUT suite, when it runs, then the new tests pass and no previously passing test fails.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 27 findings — high 0, medium 1, low 18, false 8, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: a Lancer killed on the tick its telegraph ends could still fire once — `_die()` only queues the free, so this needs two physics ticks in one frame with the kill landing on exactly that tick; very unlikely, and the fix is a new guard (the Wasp's `step` has none either).
  - `[low]` `[patch]` Blind: the bullet-speed data test silently skips `enemies.needle.bolt_speed_px_s` (1600) — added a comment that the Needle bolt is the GDD's one telegraphed exception.
  - `[low]` `[reject]` Blind: the two speed collectors in `test_data_files.gd` nearly duplicate each other — ten lines of test code, no caller diverges; merging them adds a parameter for no named harm.
  - `[low]` `[patch]` Blind: the 2.3 s shot period isn't recorded — the as-built note now states that the AC sequence (2.0 s timer, 0.3 s glow, fire) gives 2.3 s, mirroring the Wasp.
  - `[low]` `[reject]` Blind: the two dev Lancers strafe toward each other and overlap briefly — enemies don't collide, it's dev data, and the overlap is cosmetic; changing the direction rule is a design change.
  - `[low]` `[reject]` Blind: a slotless Lancer spawned outside the strafe bounds snaps onto a bound, and its y isn't clamped — only reachable from the sandbox or tests, and the sandbox spawns no Lancers.
  - `[low]` `[patch]` Blind: the wave-3 level test doesn't check that `"entry": "sides"` reaches the Lancer — it now asserts each Lancer is in ENTER and off-screen to the side.
  - `[low]` `[patch]` Blind: `Log.debug_enabled` is restored mid-test — it is now saved in `before_each` and restored in `after_each`.
  - `[low]` `[patch]` Blind: the cycle-count test window ended where the 3rd shot lands — it now steps to `3 × 2.3 + 0.5` s and counts with `_bullets()`.
  - `[low]` `[patch]` Blind: the capsule is aimed only in `_ready` — added a doc line that velocity is fixed at spawn (no caller changes it today).
  - `[false]` `[reject]` Blind: the literal `81` mask assertion is redundant — the project deliberately pins the exact numbers stored in `.tscn` files (decision #35); this is not a defect.
  - `[low]` `[reject]` Edge: `strafe_speed_px_s` ≤ 0 leaves a Lancer off-screen forever — bad data is already rejected by `test_lancer_tuning_ranges`; same precedent as the Wasp.
  - `[low]` `[reject]` Edge: a slot x outside the bounds — the zone data test asserts every Lancer slot x is inside [sprite_px/2, 1920 − sprite_px/2].
  - `[false]` `[reject]` Edge: a valid Spawner without a Projectiles container drops shots silently — `Spawner._ready` → `_container()` already logs an ERROR for the missing container.
  - `[low]` `[reject]` Edge: overshoot past `fire_interval_s`/`telegraph_s` is dropped (about one tick per cycle) — imperceptible; carrying the remainder adds code; same as the Wasp precedent.
  - `[false]` `[reject]` Edge: the Lancer aims at a dying player — the player can't die until Epic 3.
  - `[low]` `[reject]` Edge: a future non-bullet `*_speed_px_s` key under `tuning.boss` would fail the speed test — every boss speed key today is a bullet speed, and such a failure would be loud and named.
  - `[false]` `[reject]` Edge: the as-built note's "with no valid spawner … one DEBUG line" claim misleads — it describes exactly the no-spawner path; the missing-container case is logged by the Spawner itself.
  - `[medium]` `[patch]` Verification gap: no test checks the Lancer's `Hitbox`, so a renamed node would ship an unkillable Lancer — added `test_lancer_hitbox_radius_from_tuning` (circle radius `96/2 × hitbox_ratio`).
  - `[low]` `[patch]` Verification gap (other): the wave-3 slot-zone assertion could never fail (already clamped) — removed; the data test checks the raw slots; replaced with the side-entry check above.
  - `[low]` `[reject]` Intent: no test overlaps a bullet with the real `player.tscn` — the player has no `apply_damage` until Epic 3, so the only outcome is a free; the layers and mask are pinned by tests.
  - `[low]` `[reject]` Intent: the level test doesn't watch Lancers strafe or fire inside a running level — each link is tested (behaviour with a real Spawner, wiring in the level); same as the Wasp precedent.
  - `[false]` `[reject]` Intent: the ENTER phase is outside the 35% zone before strafing — waves bring enemies in from their `entry` edge, as the Wasp does; once active, the Lancer strafes inside the zone.
  - `[false]` `[reject]` Intent: the rule that enemy bullets never damage asteroids comes from the architecture, not the story — the AC's "only if" is a necessary condition, and the architecture's damage rule is part of the contract.
  - `[false]` `[reject]` Intent: the colour is fixed to #FF2BD6 rather than "magenta/red" — #FF2BD6 is the `enemy` magenta in DESIGN.md.
  - `[low]` `[patch]` Intent: the 2.3 s period is one reading of the AC — same root as the Blind period row; documented in the as-built note.
  - `[false]` `[reject]` Intent: no evidence the `--quit-after 600` run happened — it ran: exit 0, no WARN or ERROR lines.

### 2026-10-07 — Review pass
- verdicts: 21 findings — high 0, medium 0, low 14, false 7, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind: the 2.3 s shot period differs from the GDD's "every 2.0 s" without a decision-log entry — carried: same claim as the earlier period rows; the intent contract fixes the sequence (timer, then glow, then fire), and the as-built note records the 2.3 s period.
  - `[low]` `[reject]` Blind: `test_can_damage_rejects_asteroid_layer_only` asserts a convoy-layer target takes the generic bullet damage, while the architecture gives the convoy 5/2 — no convoy entity exists yet, and the intent defers `targets_convoy` and convoy aiming to Epic 6, which owns the convoy damage amounts and will revise this assertion.
  - `[false]` `[reject]` Blind: `var spawner: Spawner` creates a circular Enemy/Spawner dependency that the architecture body doesn't cover — Godot 4 resolves cyclic `class_name` references, the intent requires exactly this field, and the as-built note documents it; no caller breaks.
  - `[low]` `[reject]` Blind: slot/entry/clamp logic duplicates the Wasp — the two copies don't diverge today, and a shared helper is a refactor (new surface), not a direct correction.
  - `[low]` `[reject]` Blind: the bullet-speed data test only matches `bullet_speed_px_s`, so a differently named future key escapes — no such key exists; the fix would be a new exclusion list for a hypothetical.
  - `[low]` `[patch]` Blind: the wave-3 level test's "off-screen" check has only a 0.24 s window — replaced it with a check that the Lancer flies level with its slot's y (a top entry would still be above it), which holds for the whole multi-second side entry.
  - `[false]` `[reject]` Blind: the spec frontmatter is stale (`in-review`, empty `deferred`) — `in-review` is this pass's own state, and rejected findings aren't deferred by design; the fix would also edit this build's spec.
  - `[low]` `[reject]` Blind: no test kills a Lancer in a running level — the death path is the shared `Enemy._die`, already covered by the Wasp and combat tests; the kill during TELEGRAPH is the carried dead-Lancer last-shot row.
  - `[false]` `[reject]` Blind: the Lancer ignores a null `spawn_projectile` result silently — both null paths log in the Spawner: an unknown id logs an ERROR in `spawn_projectile`, and a missing container logs an ERROR in `_ready`.
  - `[low]` `[reject]` Blind: `Muzzle`'s down rotation is unused by the code — the spec asks for a Muzzle pointing down; harmless and pinned by a test.
  - `[false]` `[reject]` Blind: the bullet's off-screen cleanup isn't tested — `EnemyBullet` doesn't override `_physics_process`; the off-screen free is base `Projectile` code pinned by `test_projectile.test_bolt_freed_off_screen`.
  - `[low]` `[reject]` Edge: a slot y above the playfield isn't clamped at runtime — only reachable through bad formation data, which the patched data test (next row) now rejects; a runtime guard adds a branch (Wasp precedent).
  - `[low]` `[patch]` Edge: the zone data test has no lower bound on slot y — `assert_lte` became `assert_between(slot.y, h, limit, …)`.
  - `[low]` `[reject]` Edge: a Lancer killed on the tick its telegraph ends can still fire — carried: needs two physics ticks in one frame; the fix is a new guard.
  - `[low]` `[patch]` Intent: the cadence follows R1a (2.3 s), not R1b (2.0 s) — carried: documented in the as-built note.
  - `[low]` `[reject]` Intent: level-level strafe/glow/fire is exercised only on a test-world Spawner — carried.
  - `[low]` `[reject]` Intent: no bullet overlap with the real `player.tscn` — carried.
  - `[false]` `[reject]` Intent: the asteroid rule is tested as a layer bit rather than an entity type — only `asteroid.tscn` uses layer 16, so both readings agree for every entity.
  - `[false]` `[reject]` Intent: the aim origin is the Muzzle position after that tick's strafe move — this is "at fire time" as the contract says; no divergence.
  - `[false]` `[reject]` Intent: pause is tested through `PauseArbiter` — this exercises the real pause path; no divergence.
  - `[low]` `[patch]` Intent: the bullet-speed rule scopes out the Needle bolt — carried: commented as the GDD exception.

## Design Notes

**Fire cadence.** The AC's sequence is "timer reaches 2.0 s → glow 0.3 s → fire", so the shot period is 2.3 s. This mirrors the Wasp, whose 3–5 s clock is followed by its 0.4 s telegraph. The timer runs only while strafing, so a Lancer never fires while entering from off-screen.

**Why inject the spawner.** Shooting enemies need the `Spawner`, but autoloads must not reference scene nodes, and a group lookup per shot is avoidable. The Spawner already owns creation, so setting `enemy.spawner = self` before `add_child` keeps the single creation path and works in the level, the sandbox and test worlds.

**Asteroids.** The AC's "only if the target has `apply_damage`" is a necessary condition. The architecture's damage rule ("damages it if it's a player shot") adds that enemy shots never chip asteroids, which keeps them as reliable cover (Story 2.6).

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0; class cache has `Lancer`, `EnemyBullet`.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --quit-after 600` -- expected: no ERROR or WARN lines.

## Auto Run Result

Status: done

**Summary:** Follow-up review pass on Story 2.5 (Lancer + shared `EnemyBullet`). The implementation from the first pass held up. This pass fixed two low-severity test weaknesses, and no production code changed.

**Files changed (this pass):**
- `game/tests/unit/test_level.gd`: the wave-3 side-entry check now asserts each Lancer flies level with its slot's y, replacing a timing-sensitive "still off-screen" check.
- `game/tests/data/test_data_files.gd`: the formation-zone test also rejects slots above the playfield (`assert_between(slot.y, h, limit)`).

**Files changed (story, first pass):** `lancer.gd`/`.tscn`, `enemy_bullet.gd`/`.tscn`, `enemy.gd` (`spawner` field), `spawner.gd` (injection), `projectile.gd` (`_can_damage`), `entity_registry.gd`, `tuning.json` (`muzzle_glow_energy`), `level_dev.json` (wave 3 Lancers), new and extended tests, and the architecture as-built note.

**Review findings:** 21 findings: high 0, medium 0, low 14, false 7.
- **Patched (2 new fixes):**
  - the wave-3 side-entry level test;
  - the lower bound in the zone data test.
- **Carried patched rows:** 3 (cadence ×2, Needle comment).
- **Deferred:** one pre-existing, deterministic failure in `test_wave_director` that predates this story (see the frontmatter).
- **Rejected:**
  - low: convoy damage amount (Epic 6), Wasp/Lancer duplication, hypothetical future speed keys, no in-level Lancer death test, unused Muzzle rotation, runtime clamp for slots above the playfield (now caught by data), dead-Lancer last shot, in-level fire, real-player overlap;
  - false: the Enemy/Spawner cycle, spec frontmatter, silent failed spawn, untested off-screen cleanup, asteroid rule by layer, aim origin, pause path.
- **Follow-up review recommended: false.** This was a follow-up pass and no high was patched (patched this pass: high 0, medium 0, low 2).

**Verification:**
- `--import` exited 0.
- `--headless --quit-after 600` exited 0 with no WARN or ERROR lines.
- Full GUT suite: 40 scripts, 529/530 passed (3738/3739 asserts).
  - The one failure is `test_wave_director.test_f3_resolves_the_wave_and_fires_pending_triggers_in_order` ("the skipped group never spawns").
  - It fails 5/5 runs, and it fails identically at HEAD `dfa8063` and at baseline `6cad11a922c2edd30ccb48ff631445a4b329a74e`, so it isn't a regression from this story. The cause looks timing-dependent: a 0.05 s wave gap against a two-frame wait. It is deferred.
- All Lancer, EnemyBullet, Spawner, level and data tests pass, including the two patched ones.

**Residual risks:**
- The suite is red on this machine because of the deferred pre-existing `test_wave_director` failure.
- All runs were headless. Nobody has watched the Lancer's glow and shots, so readability and feel need a playtest. No feel or fun claim is made.
- The 2.3 s shot period (from the AC sequence) versus the GDD's "every 2.0 s" is still a designer call: set `fire_interval_s` to 1.7 or record a decision.
- Enemy-bullet damage on the convoy is the generic 1 until Epic 6 implements `targets_convoy` (5/2).
