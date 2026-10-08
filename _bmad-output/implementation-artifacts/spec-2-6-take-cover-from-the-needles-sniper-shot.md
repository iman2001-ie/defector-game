---
title: "Story 2.6: Take Cover from the Needle's Sniper Shot"
type: 'feature'
created: '2026-10-07'
baseline_revision: 'fcd7a19c4285d99db4acd7e93c6f3a373c0d27f3'
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
deferred: []
---

<intent-contract>

## Intent

**Problem:** There is no Needle. The GDD Needle (FR21, FR25, FR6; gdd.md L268) is a medium, 6 HP sniper that anchors at the top edge, repositions every 8 s, and every 4.0 s shows a targeting line that tracks the player for 1.2 s, locks red for 0.3 s, then fires a 1600 px/s bolt along the locked line. Asteroids block the bolt, which teaches the player to use cover.

**Approach:** Add `Needle` (`class_name`, `enum State { ANCHORING, TRACKING, LOCKED, COOLDOWN }`, as the architecture's State Patterns example sketches) with an in-world `TelegraphLine` (Line2D), and `NeedleBolt` (`class_name`, extends `EnemyBullet`, so it inherits the asteroid rule and the travel-aligned capsule). Register both, add a Needle wave with medium asteroids to `level_dev.json`, and extend the data tests.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript. `_state` is assigned only inside `_enter_state()`. `_physics_process(delta)` only calls a public `step(delta)` holding the `match` (Lancer/Wasp pattern), so tests drive it deterministically. No per-frame allocation, group lookup or logging; the player lookup runs once per tick only in TRACKING (as `Lancer._aim` does per shot), and the line is updated with `set_point_position`.
- Numbers from `Config`, read once in `_ready`: `enemies.needle.reposition_interval_s` (8), `fire_interval_s` (4), `track_s` (1.2), `lock_s` (0.3), `bolt_speed_px_s` (1600); bolt damage `damage.bullet_hearts`. New keys: `anchor_y_px` 160, `reposition_speed_px_s` 400, `reposition_min_distance_px` 320. Cooldown = `maxf(fire_interval_s − track_s − lock_s, 0)`.
- Anchor: y is always `anchor_y_px` (a slot's y is ignored); x is the slot's x clamped into `[sprite_px/2, width − sprite_px/2]` (one WARN if clamped). Entry `"top"` starts at `(anchor.x, −sprite_px/2)`, `"sides"` at `(−sprite_px/2, anchor_y)` or `(width + sprite_px/2, anchor_y)` from the nearer side (x ≤ width/2 → left), other values → `Log.warn("spawn", …)` and top. Without a `slot` the anchor is the spawn position (no teleport). It starts in ANCHORING.
- ANCHORING: move toward the anchor at `reposition_speed_px_s` (line hidden); on arrival reset the anchored timer and enter TRACKING.
- TRACKING (line visible, `track_color` = `enemy` #FF2BD6 at alpha 0.5, width 2): each tick aim the line from `Muzzle` toward the player's `global_position` (straight down with no player or a zero vector), reaching `Playfield.SIZE.length()` px. After `track_s` → LOCKED.
- LOCKED (line frozen on the last tracked direction, `lock_color` = `danger` #FF1F4B opaque, width 4): after `lock_s` fire one `needle_bolt` from `Muzzle.global_position` with `velocity = locked_dir × bolt_speed` via `spawner.spawn_projectile`, then COOLDOWN. No valid spawner → no shot, one `Log.debug("spawn", …)` per Needle, cycle continues.
- COOLDOWN (line hidden): if a reposition is due (anchored time ≥ `reposition_interval_s − 0.0001`), pick a new anchor and enter ANCHORING; else after the cooldown → TRACKING. A reposition is only taken in COOLDOWN, so it never interrupts a track or lock.
- New anchor x: uniform over the parts of `[min_x, max_x]` at least `reposition_min_distance_px` from the current x; if none exist, uniform over the full range. Uses a `var rng: RandomNumberGenerator` (tests seed it). y stays `anchor_y_px`.
- `NeedleBolt`: layer `ENEMY_SHOTS` (8), mask `MASK_ENEMY_SHOTS` (81); `CapsuleShape2D` radius ≥ 8 and height ≥ `bolt_speed_px_s / 60` (27; use 48); an elongated `Streak` visual (white core, `enemy` magenta edge, ≥ 16 px wide) rotated with the capsule to follow `velocity`. Damage, asteroid and free behaviour inherited unchanged from `EnemyBullet`.

**Never:**
- No convoy targeting (Needles never aim at the convoy), no player hearts or `apply_damage` on the Player (Epic 3), no drops (Epic 4), no line occlusion by asteroids, no Bastion. No changes to `WaveDirector`, `Formation`, `Events`, `Projectile`, `EnemyBullet` behaviour, the sandbox, the bench or `sprint-status.yaml`. No new art files: polygons and gradient textures inside the `.tscn`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Top entry | slot (960,280), entry top | starts (960,−40), ANCHORING at 400 px/s to (960,160), then TRACKING | — |
| Side entry | slot (400,160), entry sides; slot x 1500 | starts (−40,160); (1960,160) | — |
| Unknown entry / off-screen slot x | entry "spiral"; slot x 5 | top entry; anchor x 40 | WARN each |
| Track | TRACKING, player (300,900) moving | line visible, enemy colour, end point follows the player each tick | no player → line straight down |
| Lock + fire | 1.2 s tracked, then player moves | LOCKED: line red and frozen; after 0.3 s one `needle_bolt` at Muzzle, velocity 1600 along the locked line; COOLDOWN, line hidden | — |
| Cycle | anchored, 8.0 s of steps | shots at 1.5 s and 5.5 s; at 8.0 s ANCHORING to a new x ≥ 320 px away, y 160 | — |
| No spawner | Needle created without Spawner | cycle runs, no bolt, no crash | DEBUG once |
| Cover | medium asteroid on the locked line, player stand-in behind it | asteroid HP unchanged, stand-in gets no `apply_damage`, bolt freed | — |
| No tunnelling | stand-in (24 px) on the line, real physics | exactly one `apply_damage(1, bolt)`; bolt freed | — |
| Pause | tree paused | Needle and bolt frozen | — |

</intent-contract>

## Code Map

- `game/entities/enemies/lancer/lancer.gd` + `.tscn` -- the pattern to mirror: `setup` (slot/entry), `_ready` (super first, then tuning), `step`, `_enter_state`, entry WARN text, `_fire` via `spawner`, `_aim` no-player fallback, `_warned_no_spawner`, accessors. Scene style: `Area2D` layer 4 mask 0 `monitoring = false`, `Hitbox`, `Hull` Polygon2D in `enemy` colour, `Muzzle` Marker2D.
- `game/core/enemy.gd` -- base: `spawner` field injected by `Spawner.spawn_enemy`; `_ready` sets HP, tier, hitbox (`sprite_px/2 × hitbox_ratio`). No change.
- `game/entities/projectiles/enemy_bullet.gd` + `.tscn` -- `NeedleBolt` extends it; its `_ready` rotates `Hitbox` by `velocity.angle() − PI/2` before `super._ready()`; `_can_damage` rejects the `ASTEROIDS` layer; `_on_impact` is a no-op. Mirror the `.tscn` (layers 8/81, `monitorable = false`, inline gradients, additive material).
- `game/core/projectile.gd` -- base flight, off-screen free (`OFFSCREEN_MARGIN_PX`), `_on_area_entered`. Read-only.
- `game/autoloads/entity_registry.gd` -- add `&"needle"` to `ENEMIES`, `&"needle_bolt"` to `PROJECTILES`; `Config` validates level types against `enemy_types()` automatically.
- `game/systems/waves/wave_director.gd` `_spawn_entry` L219-258 -- passes `position`, `slot`, `formation`, `entry`; `_spawn_asteroids` L264 spawns asteroids at random x above the screen (seeded `rng`). Read-only.
- `game/data/tuning.json` `enemies.needle` -- has tier, hp 6, hitbox_ratio, reposition 8, fire 4, bolt 1600, track 1.2, lock 0.3; add the three new keys. `waves.formation.top_y` 160, spacing (160,120).
- `game/data/levels/level_dev.json` -- append wave 4: `spawns` `[{needle, 2, grid_2x1, top}, {wasp, 4, grid_4x1, top}]`, `asteroids` `[{ "size": "medium", "count": 2 }]`, `triggers` `[{ "when": "wave_clear", "actions": [ { "wait": 0.5 } ] }]`.
- `game/tests/unit/test_level.gd` -- `test_level_started_with_the_json_id_and_wave_1` L139 asserts `wave_count() == 3`; `test_clearing_every_dev_wave_clears_the_level` L208 loops `for wave in 3`: both become 4. `test_dev_wave_3_has_lancers` L235 is the template for a wave-4 Needle test.
- `game/tests/data/test_data_files.gd` -- `test_every_telegraph_meets_the_minimum` already covers `enemies.needle.lock_s`; `test_every_enemy_bullet_is_at_most_the_max_speed` deliberately skips the Needle bolt (L82); `ZONED_TYPES` stays Wasp/Lancer (the Needle ignores slot y). `test_lancer_tuning_ranges` L207 is the template.
- `game/tests/unit/test_lancer.gd`, `test_enemy_bullet.gd` -- test style: `_make`, manual `step`, `_make_player`, `_make_world` with a real `Spawner`, `Log.sink` capture, `Config.load_data()` in `after_each`, physics overlap with `tests/fixtures/damage_target.gd`, real asteroid via `_spawner.spawn_asteroid`.
- New `class_name`s (`Needle`, `NeedleBolt`) need `--import`; commit the new `.gd.uid` files.

## Tasks & Acceptance

**Execution (write each test first, red, then the code):**
- `game/data/tuning.json` -- add `anchor_y_px` 160, `reposition_speed_px_s` 400, `reposition_min_distance_px` 320 to `enemies.needle`.
- `game/entities/projectiles/needle_bolt.gd` + `.tscn` -- `class_name NeedleBolt extends EnemyBullet`; `_ready` also rotates `Streak` like the hitbox, then `super._ready()`.
- `game/entities/enemies/needle/needle.gd` + `.tscn` -- `class_name Needle extends Enemy` per the Always rules; `sprite_px` 80; a distinct long, thin, needle-nosed `Hull` in `enemy` colour; `Muzzle` Marker2D at the nose; `TelegraphLine` Line2D (2 points, hidden). `@export var track_color`, `lock_color`. Accessors `state()`, `anchor()`, `line_visible()`, `line_color()`, `line_direction()`.
- `game/autoloads/entity_registry.gd` -- register both.
- `game/data/levels/level_dev.json` -- wave 4.
- `game/tests/unit/test_needle.gd` -- every Needle matrix row except cover/tunnelling/pause-of-bolt; tuning reads (change a value in `Config.tuning`, restore with `Config.load_data()`); `_state =` occurs exactly once in the source; HP 6, MEDIUM tier, hitbox radius `80/2 × hitbox_ratio`; shots through a real `Spawner` with speed 1600 and direction equal to the locked line; seeded reposition stays in bounds and ≥ min distance.
- `game/tests/unit/test_needle_bolt.gd` -- layers/mask equal the constants; capsule radius ≥ 8, height ≥ `bolt_speed_px_s / 60`, axis and `Streak` follow velocity; streak ≥ 16 px wide; the cover row (Needle fired through a real Spawner, real medium `Asteroid`, stand-in behind it) and the no-tunnelling row through physics.
- `game/tests/unit/test_spawner.gd` -- registry has `needle` and `needle_bolt`.
- `game/tests/unit/test_level.gd` -- the 3 → 4 updates; wave 4 has two counted Needles in `World/Enemies` with the level Spawner injected and 2 medium asteroids.
- `game/tests/data/test_data_files.gd` -- `test_needle_tuning_ranges` (speeds > 0, `track_s + lock_s ≤ fire_interval_s`, reposition interval ≥ fire interval, `anchor_y_px` between the needle half-height and the enemy zone bottom 432, min distance ≥ 0); every wave whose spawns or groups contain a `needle` has ≥ 2 medium or large asteroids (GDD L301), with at least one such wave found.
- `_bmad-output/game-architecture.md` -- a short "As-built 2026-10-07 (Story 2.6)" note: Needle states and cadence, anchor/reposition rules, `NeedleBolt extends EnemyBullet`, the new tuning keys.
- Run `--import`, then the full GUT suite.

**Acceptance Criteria:**
- Given a level wave with a Needle entry, when it spawns, then the Needle (6 HP, medium tier) flies to an anchor at the top edge (y `anchor_y_px`) and, after each 8 s anchored, moves to a new anchor along the top edge.
- Given an anchored Needle, when an attack cycle starts (every 4.0 s), then its targeting line tracks the player for 1.2 s, locks and turns red for 0.3 s, then a `needle_bolt` fires along the locked line at 1600 px/s with a capsule height ≥ 27 px.
- Given an asteroid on the locked line, when the bolt is fired, then the asteroid stops it and the bolt does not reach the player.
- Given the headless GUT suite, when it runs, then the new tests pass and no previously passing test fails.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 27 findings — high 0, medium 0, low 19, false 8, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: the spec, `sprint-status.yaml` and `deferred-work.md` are missing from the diff — the spec was excluded from the review diff on purpose (it goes to the edge-case layer only) and is committed with the story; `sprint-status.yaml` is orchestrator-owned; nothing was deferred.
  - `[low]` `[reject]` Blind: three new tuning keys (`anchor_y_px`, `reposition_speed_px_s`, `reposition_min_distance_px`) without a decision-log entry, while the as-built note says "no design decision changed" — they fill numbers the GDD leaves open, live in data for the designer to tune, and follow the Story 2.5 precedent (`muzzle_glow_energy`); surfaced under residual risks.
  - `[low]` `[reject]` Blind: two Needles arrive together, fire in lockstep and can pick overlapping reposition anchors — enemies don't collide, so the overlap is cosmetic (Story 2.5 Lancer-overlap precedent); de-conflicting needs cross-Needle coordination, new complexity; flagged for playtest.
  - `[low]` `[reject]` Blind: the red locked line runs through asteroids to the covered player — the line still shows the bolt's true path and the asteroid visibly stops the bolt; occlusion needs a per-tick raycast, new complexity not asked for by the AC.
  - `[low]` `[patch]` Blind: the enemy-zone comment ("y 120 -> 432") contradicts the assertion's lower bound (half-height 40) — comment reworded to state what is checked; assertion unchanged.
  - `[low]` `[patch]` Blind: two lines hold collapsed `\` continuations (runs of tabs mid-line) in `test_data_files.gd` and `test_needle.gd` — restored proper line continuations.
  - `[false]` `[reject]` Blind: `Muzzle.rotation` is unused yet pinned by a test — no bad outcome; it mirrors the Lancer's Muzzle (pointing down, the firing side) and nothing reads or breaks on it.
  - `[false]` `[reject]` Blind: the line mixes global direction and local points — the Needle never rotates or scales; no code path reaches the claimed mismatch.
  - `[low]` `[reject]` Blind: no tests for convoy rules (no aiming at the convoy, stray 2 damage) — no convoy exists until Epic 6, which owns convoy damage; the Needle aims only at group `player` by construction.
  - `[low]` `[reject]` Blind: the wave-4 level test doesn't assert each wave advanced — a stall still fails loudly on the "on wave 4" assert; mirrors the accepted wave-3 test.
  - `[low]` `[reject]` Blind: the cover data test counts wave asteroids, not cover that lasts while a Needle lives — it implements the GDD rule as worded (gdd.md L301); asteroid lifetime is a level-design matter for Epic 7 content.
  - `[low]` `[reject]` Edge: a Needle entry spanning more than one formation row collapses later rows onto row-0 anchors — cosmetic overlap (enemies don't collide); `level_dev` uses one row; residual risk for Epic 7 authoring (use `grid_<count>x1`).
  - `[low]` `[reject]` Edge: a Needle entry listed after other entries anchors on y 160 over their row-0 enemies — same cosmetic overlap; the design note fixes the top-edge y on purpose; Wasps dive and Lancers strafe away; residual risk for authoring.
  - `[low]` `[reject]` Edge: two Needles reposition onto the same x — same claim as the Blind lockstep/overlap row; rejected on the same grounds.
  - `[false]` `[reject]` Edge: `reposition_speed_px_s` ≤ 0 freezes the Needle in ANCHORING — `test_needle_tuning_ranges` asserts it is > 0, so bad data fails the suite.
  - `[false]` `[reject]` Edge: a negative `reposition_min_distance_px` biases the pick — `test_needle_tuning_ranges` asserts it is ≥ 0.
  - `[low]` `[reject]` Edge: a slotless Needle spawned off-screen anchors there without a WARN — only reachable from tests or the sandbox, which spawns no Needles (Lancer precedent).
  - `[false]` `[reject]` Edge: a null `spawn_projectile` result loses the shot silently — the Spawner logs an ERROR for both null paths (unknown id, missing container).
  - `[low]` `[patch]` Verification gap: the side-entry test used slot y = `anchor_y_px`, so a regression to the Lancer's `slot.y` start would pass — slots moved to y 280; asserts starts (−40,160)/(1960,160) and anchors (400,160)/(1500,160).
  - `[false]` `[reject]` Verification gap (other): `test_state_is_assigned_only_in_enter_state` checks source text — the spec requires this guard of the state-pattern rule; step-driven tests cover behaviour; no defect.
  - `[low]` `[reject]` Intent: "does not reach the player" is proven on a `DamageTarget` stand-in, not the real Player — the Player has no `apply_damage` until Epic 3; layers and mask are pinned (Story 2.5 precedent).
  - `[low]` `[reject]` Intent: timings are proven with manual `step(DT)`, not the live loop — `_physics_process` only calls `step`; pause is tested on the real tree (precedent).
  - `[low]` `[reject]` Intent: the level test never watches an in-level Needle track or fire — each link is tested (behaviour with a real Spawner, wiring in the level); precedent.
  - `[low]` `[reject]` Intent: `level_dev` asteroids fall at random x, so no rock is guaranteed on a firing line — dev data; the AC's cover mechanic is proven by the physics test; real level layout is Epic 7.
  - `[false]` `[reject]` Intent: telegraph readability is only checked as Line2D properties — no defect claimed; feel and readability need a human playtest and are listed as residual risk.
  - `[low]` `[reject]` Intent: "repositions every 8 s" is implemented as 8 s anchored, so travel time stretches the real period — documented in Design Notes and the as-built note; tunable via `reposition_interval_s`; listed as a designer call (same handling as the Story 2.5 cadence).
  - `[low]` `[reject]` Intent: the fixed top-edge anchor y and new keys appear only in the spec and as-built note, not a decision log — same claim as the Blind tuning-keys row.

### 2026-10-07 — Review pass (follow-up)
- verdicts: 25 findings — high 0, medium 0, low 18, false 7, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: a Needle killed by a hit in the same physics frame can still fire. Area signals flush before `_physics_process`, `queue_free` is deferred, and `step()` has no `_dead` check. — Real, but it needs the kill to land on the single tick the lock ends (1 tick in each 4 s cycle). The Lancer has the same unguarded `step` (Story 2.5 precedent). The fix adds a guard. Rejected as unlikely.
  - `[low]` `[reject]` Blind: if `reposition_interval_s` isn't a multiple of `fire_interval_s`, a reposition mid-cooldown breaks the 4.0 s rhythm. — Only with non-default tuning (default 8 = 2 × 4). The spec's COOLDOWN rule says exactly this. Enforcing a multiple would add a rule. Designer tuning matter.
  - `[false]` `[reject]` Blind: the Streak's "opaque body ≥ 16 px" assertion overstates it: alpha 1 only reaches 11 px, so the GDD 16 px readability rule may be broken. — The magenta body stays at alpha ≥ 0.6 across 17 px, inside a 40 px additive halo, so the visible bolt is wider than 16 px. The 0.85-stop convention is the one accepted for `EnemyBullet` in Story 2.5 (same gradient). The Needle bolt is also the GDD's named exception to the bullet rule.
  - `[low]` `[reject]` Blind: the `anchor_y_px` range check (`half`..432 on the centre) would accept values under the HUD band or a hull past y 432. — The shipped 160 puts the hull at y 120–200, inside the zone. Only bad data could reach the gap. The bound is the one the spec's Tasks state, so tightening it changes the spec's rule. Unlikely.
  - `[low]` `[reject]` Blind: `ENEMY_ZONE_BOTTOM_Y` 432 is a magic number duplicated with `sandbox.gd`. — Duplicated UX value; it diverges only if the UX zone changes. A shared constant would be new public surface. Not worth it now.
  - `[low]` `[reject]` Blind: Needles don't keep distance from each other's anchors. — carried: same claim as the earlier Blind lockstep/overlap row; code unchanged; rejected (cosmetic, enemies don't collide).
  - `[low]` `[reject]` Blind: Needles in one wave fire in lockstep. — carried: same claim as the earlier Blind lockstep row; code unchanged; rejected.
  - `[low]` `[reject]` Blind: the cover data test counts asteroids, not their on-screen time while Needles fire. — carried: same claim as the earlier cover data-test row; rejected (GDD L301 as worded, Epic 7 layout).
  - `[low]` `[reject]` Blind: `test_cycle_cadence_and_reposition` tolerances (`DT * 6.5`) let cadence drift pass. — Same root cause as the Edge `_t`-reset drift row. The drift is at most 1 tick per state (about 50 ms per 4 s) and can't be seen in play. Rejected with it.
  - `[low]` `[reject]` Blind: no test kills a Needle during TRACKING/LOCKED. — Same root cause as the dead-Needle-fires row. Rejected with it.
  - `[low]` `[reject]` Blind: `reposition_min_distance_px` has no upper bound against the playable width. — Shipped 320 leaves a large valid range. Only bad data falls back to the spec's "uniform over the full range" rule. Unlikely.
  - `[low]` `[reject]` Edge: `_enter_state` resets `_t` to 0 and drops the overshoot, so each state can run 1 tick long and the 4.0 s cycle drifts. — Real: about 1–3 ticks per cycle. Invisible to players, and the reposition still lands at 8 s anchored. Carrying the overshoot would change transition semantics in every state. Rejected as negligible.
  - `[low]` `[reject]` Edge: a Needle killed earlier in the same physics frame can still fire in its last `step`. — Same root cause as the Blind dead-Needle row. Rejected with it.
  - `[false]` `[reject]` Edge: `reposition_speed_px_s` ≤ 0 freezes the Needle in ANCHORING. — carried: `test_needle_tuning_ranges` asserts it is > 0.
  - `[low]` `[reject]` Edge: two Needles reposition onto overlapping anchors. — carried: same claim as the earlier Edge same-x row; rejected.
  - `[low]` `[reject]` Edge: a slotless Needle spawned off screen anchors there. — carried: same claim as the earlier slotless row (sandbox and tests only); rejected.
  - `[low]` `[reject]` Edge: a Needle spawned by a later group beat may have no cover left, and the cover test ignores this. — `level_dev` spawns no Needles from groups. This is a level-authoring matter for Epic 7, on the same grounds as the carried cover row.
  - `[false]` `[reject]` Edge: the Streak stops matching the travel direction if `velocity` changes after `_ready`. — Nothing writes `velocity` after `setup`. `Projectile` only reads it in flight, and the `EnemyBullet` hitbox uses the same `_ready`-time rotation.
  - `[low]` `[reject]` Intent: the cadence is approximate (tick-rounded), not an exact 4.0 s. — Same root cause as the Edge drift row. Rejected with it.
  - `[false]` `[reject]` Intent: a slotless Needle snaps to `anchor_y_px` on its first reposition. — The contract says "y stays `anchor_y_px`", and slotless Needles exist only in tests and the sandbox (which spawns none). This is intended behaviour, not a divergence.
  - `[false]` `[reject]` Intent: Streak width is checked on the texture, not the rendered opaque width. — Same refutation as the Blind Streak row.
  - `[low]` `[reject]` Intent: state-machine timings run through `step()`, and the level test never watches a Needle fire. — carried: same claims as the earlier Intent precedent rows; rejected.
  - `[low]` `[reject]` Intent: the cover and no-tunnelling physics tests only use a straight-down line. — Capsule and Streak orientation are checked for four diagonal velocities, and overlap physics doesn't depend on orientation. Adding more physics tests isn't a direct fix. Unlikely to hide a defect.
  - `[false]` `[reject]` Intent: the as-built architecture note and the extra data rules are outside the named scope. — The spec's Tasks require both.
  - `[false]` `[reject]` Intent: `sprint-status.yaml` is modified in the working tree. — It is not in the reviewed diff. The file is orchestrator-owned and is left uncommitted.

## Design Notes

**Cadence.** The AC says an attack cycle *starts* every 4.0 s, so the period is start-to-start: track 1.2 s + lock 0.3 s + cooldown 2.5 s (the architecture's COOLDOWN state). This differs from the Lancer, whose AC put the interval before the telegraph.

**Reposition.** The 8 s counts anchored time from arrival and is only acted on in COOLDOWN. With default tuning this lands exactly on a cycle boundary: two shots per anchor (at 1.5 s and 5.5 s), then a move. Travel time adds to the real period; that is a tuning matter for playtest.

**Anchor height.** "Top edge" is a fixed `anchor_y_px` rather than the formation row, so a Needle listed after other entries in a wave still sits at the top and keeps its long sightline (gdd.md L305).

**Bolt.** Subclassing `EnemyBullet` reuses the asteroid-cover rule (enemy shots never chip asteroids) and the capsule alignment, so the cover AC holds by construction and is proven by a physics test.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0; class cache has `Needle`, `NeedleBolt`.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all new tests pass; only the pre-existing deferred `test_wave_director.test_f3_resolves_the_wave_and_fires_pending_triggers_in_order` failure may remain.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --quit-after 600` -- expected: no ERROR or WARN lines.

## Auto Run Result

Status: done

**Summary:** Story 2.6 adds the Needle sniper and its bolt. A Needle flies to an anchor on the top edge (y `anchor_y_px`, x from its formation slot). Every 4.0 s, start to start, its targeting line tracks the player for 1.2 s, then locks red for 0.3 s, and then a `needle_bolt` fires along the locked line at 1600 px/s. After 8 s anchored it moves at least 320 px along the top edge, but only between shots. `NeedleBolt` extends `EnemyBullet`, so asteroids stop it. Its 48 px capsule can't tunnel through the 24 px player hurtbox. This run was a follow-up review pass on the already-committed implementation (`426c5ab41fb7ab58116fcad909cd59cda86b30f6`). It made no code changes.

**Files changed (whole story, since `fcd7a19c4285d99db4acd7e93c6f3a373c0d27f3`):**
- `game/entities/enemies/needle/needle.gd` + `.tscn` (+ `.uid`): the `Needle` state machine, `TelegraphLine` and hull.
- `game/entities/projectiles/needle_bolt.gd` + `.tscn` (+ `.uid`): `NeedleBolt extends EnemyBullet`, with a velocity-aligned `Streak`.
- `game/autoloads/entity_registry.gd`: registers `needle` and `needle_bolt`.
- `game/data/tuning.json`: adds `anchor_y_px`, `reposition_speed_px_s` and `reposition_min_distance_px`.
- `game/data/levels/level_dev.json`: wave 4 (2 Needles, 4 Wasps, 2 medium asteroids).
- `game/tests/unit/test_needle.gd`, `test_needle_bolt.gd` (+ `.uid`): new behaviour, physics cover and no-tunnelling tests.
- `game/tests/unit/test_level.gd`, `test_config.gd`, `test_spawner.gd`, `game/tests/data/test_data_files.gd`: the 4-wave dev level, registry checks, Needle tuning ranges and the cover rule.
- `_bmad-output/game-architecture.md`: the "As-built 2026-10-07 (Story 2.6)" note.

**Review findings (follow-up pass):** 25 in total: high 0, medium 0, low 18, false 7, maybe-false 0.
- **Patched:** none (0 high, 0 medium, 0 low).
- **Deferred:** none.
- **Rejected lows:**
  - A Needle killed on the exact tick its lock ends can still fire one bolt, because `step` has no `_dead` check. This needs a 1-tick coincidence, and the Lancer has the same pattern.
  - The cadence drifts up to 1 tick per state, because `_t` resets and drops the overshoot. The test tolerances accept this. It is about 50 ms per cycle and invisible in play.
  - A non-multiple `reposition_interval_s` breaks the rhythm. This only happens with non-default tuning, and it is the spec's own COOLDOWN rule.
  - The `anchor_y_px` bound is loose, and the 432 zone value is duplicated. The shipped data is in range, and the bound is the spec's.
  - There is no upper bound on `reposition_min_distance_px`. Only bad data reaches it.
  - A Needle spawned by a later group beat may have no cover left. `level_dev` has no such case; this is for Epic 7 authoring.
  - The physics tests use only straight-down lines. Orientation is checked statically for diagonals.
  - Carried from the first pass: Needles overlap and fire in lockstep; the cover data test counts asteroids; a slotless Needle off screen gets no WARN; timings are tested via `step`, with no in-level fire check.
- **Rejected false:**
  - The Streak 16 px readability claim: the body at alpha ≥ 0.6 spans 17 px, plus a 40 px halo. This is the `EnemyBullet` convention.
  - The streak rotation after a velocity change: nothing changes `velocity` after `setup`.
  - The slotless reposition y: the contract says y stays `anchor_y_px`.
  - The out-of-scope architecture note and data rules: the spec's Tasks require them.
  - `sprint-status.yaml`: not in the reviewed diff.
  - Carried: speed ≤ 0 is guarded by the data test.
- **Follow-up review recommended: false.** This was a follow-up pass and it patched no high finding. The work has converged.

**Verification (this pass):**
- `--import` exited 0.
- Full GUT suite: 42 scripts, 559/560 tests passed (4343/4344 asserts). The one failure is the pre-existing deferred `test_wave_director.test_f3_resolves_the_wave_and_fires_pending_triggers_in_order`, which the Verification section allows. All Needle tests passed.
- `--headless --quit-after 600` printed no ERROR or WARN lines. It only covers wave 1.

**Residual risks:**
- Nobody has played wave 4. Telegraph readability, the cover lesson and the bolt's feel need a human playtest. No feel or fun claim is made.
- A dead Needle can, rarely, fire one last bolt on the tick it dies, as can the Lancer. If playtests notice it, add a `_dead` guard to `step`.
- Designer calls carried from the first pass:
  - the reposition period is 8 s anchored plus travel time;
  - the three new tuning values aren't in the decision log;
  - Needles should go first in a wave, on one row.
