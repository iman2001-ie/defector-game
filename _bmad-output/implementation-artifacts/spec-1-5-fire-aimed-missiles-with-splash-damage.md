---
title: 'Story 1.5: Fire Aimed Missiles with Splash Damage'
type: 'feature'
created: '2026-10-07'
baseline_revision: '6c70a8d49ea9b397f5c46c9542e3ae224f997dc9'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
warnings: [oversized]
deferred:
  - summary: >-
      A player's straight shot into the grid_4x2 formation hits a bottom-row Wasp and splashes nothing, so the missile does not "burst a formation" from the ship's firing position.
    evidence: |-
      The missile centre at contact with the Wasp at (880, 280) from below sits at about y 305-318 (Wasp hitbox radius ~25.6 px plus the 12 px capsule half-height). From there the top-row Wasp at (880, 160) is about 145-158 px away and the bottom-row neighbours about 164 px away, all beyond splash_radius_px 120. Only a top-row hit (the spec's staged Formation row, fired from inside the grid) splashes a neighbour. The numbers are the GDD's tuning (splash_radius_px 120, grid_4x2 spacing 160 x 120), so fixing it means a tuning or design decision for the Story 1.7 core-feel playtest, not a code change in this story.
    location: >-
      game/data/tuning.json weapons.missile.splash_radius_px; game/entities/projectiles/missile.gd apply_splash
    severity: medium
---

<intent-contract>

## Intent

**Problem:** The ship has only the laser. The core-feel test needs the second weapon: an aimable, cooldown-gated missile that bursts a formation with splash damage, with the cooldown visible on the reticle (FR5, FR31 missile, FR62).

**Approach:** Add a `Missile` projectile (extends `Projectile`, overrides `_on_impact` for splash), register it, let the Player fire it on RMB press along the ship→cursor vector with a 1.5 s cooldown that it broadcasts through `Events.missile_cooldown_changed`, and have the reticle draw the cooldown arc from that signal.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript, tabs, snake_case. Tuning comes only from `weapons.missile.*` in `tuning.json` (`damage 8`, `splash_damage 3`, `splash_radius_px 120`, `cooldown_s 1.5`, `speed_px_s 900`, `straight_up_within_px 32`), read once in `_ready()` and cached. No new tuning keys.
- **Missile** (`entities/projectiles/missile.gd` `class_name Missile extends Projectile`; `missile.tscn`): `collision_layer = 2`, `collision_mask = 84` (`CollisionLayers.MASK_PLAYER_SHOTS`, the architecture table), `monitorable = false`. One `Hitbox` `CapsuleShape2D` radius 6, height 24 (≥ 900 / 60 = 15). A coalition-cyan `#22E6FF` placeholder body (`Polygon2D`, nose toward local −Y, ~8×22 px, additive `CanvasItemMaterial`) and a `SmokeTrail` `GPUParticles2D` (`emitting = true`, `local_coords = false`, grey particles fading out, ~0.4 s lifetime, ≤ 32 particles, placed at the tail). `_ready()` caches `splash_damage` (`Config.int_`) and `splash_radius` (`Config.num`), then calls `super._ready()`, then sets `rotation = velocity.angle() + PI / 2` when velocity is non-zero (local −Y, the capsule axis, points along travel).
- `_on_impact(area)` calls `apply_splash(area)`. `apply_splash(hit: Node)`: for every node in groups `&"enemies"` and `&"asteroids"` that is a `Node2D`, is not `hit`, is not queued for deletion, has `apply_damage`, and whose `global_position` is within `splash_radius` (≤, centre distance) of the missile's `global_position`: `apply_damage(splash_damage, self)`. Each node at most once. Runs on every impact, including an asteroid hit.
- **Player** (`player.gd`): caches `_missile_damage`, `_missile_speed`, `_missile_cooldown_s`, `_missile_straight_up_px`. `_physics_process` adds `step_missile(Input.is_action_just_pressed(&"fire_missile"), get_global_mouse_position(), delta)` after `step_fire`. `static func missile_direction(from: Vector2, target: Vector2, straight_up_within: float) -> Vector2`: `Vector2.UP` if `from.distance_to(target) <= straight_up_within`, else the normalised offset.
- `step_missile(pressed: bool, target: Vector2, delta: float)`: (1) if `_missile_cooldown > 0`: subtract `delta`; at `<= FIRE_EPS` set it to 0; emit `Events.missile_cooldown_changed(_missile_cooldown / _missile_cooldown_s)` (so the last emit is exactly `0.0`). (2) if `pressed`, the cooldown is 0 and the spawner is valid: spawn `&"missile"` at the Muzzle with `velocity = missile_direction(global_position, target, …) * speed` and `damage`; only if the spawn returned non-null, set the cooldown to `_missile_cooldown_s` and emit `1.0`. With `cooldown_s <= 0` (data misuse) `_ready()` logs `Log.warn("data", …)` once, the missile fires on every press and nothing is emitted. Presses during the cooldown are dropped, not buffered.
- **Reticle** (`reticle.gd`, still `extends Sprite2D`): constants `COOLDOWN_RADIUS_PX = 22.0`, `COOLDOWN_WIDTH_PX = 4.0`, `COOLDOWN_COLOR = Color("#93A7C2")` (UX spec `muted`). `var cooldown_ratio: float = 0.0`. `_ready()` connects `Events.missile_cooldown_changed`; the handler stores `clampf(ratio, 0, 1)` and calls `queue_redraw()`. `_draw()` draws nothing at 0; otherwise `draw_arc(Vector2.ZERO, 22, -PI / 2, -PI / 2 + TAU * cooldown_ratio, …, COOLDOWN_COLOR, 4, true)` (clockwise from 12 o'clock on screen).
- `EntityRegistry.PROJECTILES` gains `&"missile"`. Only `Spawner` instantiates the missile.

**Never:**
- No Feedback, Audio, launch thump, explosion, missile muzzle flash or hit-stop (Story 1.6). No Barrage/micro-missiles, HUD, energy, convoy handling. No physics space queries for splash (the space is locked inside `area_entered`). No per-frame logging or allocation in the cooldown path. No pooling.
- Don't change the laser, `laser_bolt.tscn`, the `Projectile` base, `Enemy`, `Asteroid` or `Spawner`. Don't modify `sprint-status.yaml` or planning docs.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Aimed shot | ship (960, 900), cursor (1260, 500), press | one missile in `Projectiles` at the Muzzle, velocity = (0.6, −0.8) × 900, damage 8, rotation = velocity.angle() + PI/2 | none |
| Close cursor | cursor exactly 32 px from the ship (any side), press | velocity (0, −900) | none |
| Just outside | cursor 33 px right of the ship | velocity (900, 0) | none |
| Cooldown | press on tick 0, press on ticks 1–89 (1/60 s) | 1 missile; tick 90 press → 2nd missile | none |
| Ring signal | fire, then 90 idle ticks | emits 1.0, then strictly decreasing ratios, last emit exactly 0.0, then no more emits | none |
| Not pressed | 120 idle ticks from ready | no missile, no emit | none |
| No spawner | no `set_spawner`, press | no missile, no emit, cooldown stays 0 | none |
| Splash | missile hits target A; B at 100 px, C at 120 px, D at 121 px (enemies group); E at 60 px (asteroids group); F at 50 px in no group | A takes exactly [8]; B, C, E take exactly [3]; D, F nothing | none |
| Asteroid hit | missile from (960, 900) up at a large asteroid at (960, 500); Wasp at (960, 200) | asteroid hp 30 → 22, missile freed, Wasp hp 3 | none |
| Formation | 8 Wasps at the `grid_4x2` slots (x 720/880/1040/1200, y 160/280), missile hits the Wasp at (880, 160) | that Wasp (8) and the Wasp below at (880, 280) (3) die; the other 6 (≥ 160 px from the impact) keep hp 3 | none |
| Reticle | emit `missile_cooldown_changed(0.5)`, then `(1.7)`, then `(0.0)` | `cooldown_ratio` 0.5, 1.0, 0.0 | none |

</intent-contract>

## Code Map

- `game/core/projectile.gd` -- read-only. `setup()` takes `position`/`velocity`/`damage`; `_ready()` sets position, bounds, group `projectiles`, connects `area_entered`; `_on_area_entered` applies direct damage, then `_on_impact(area)`, then `queue_free()`, guarded by `_spent`.
- `game/entities/projectiles/laser_bolt.gd` / `.tscn` -- pattern for the missile scene (additive material, capsule `Hitbox`); read-only.
- `game/entities/player/player.gd` -- add missile fields, `step_missile`, `missile_direction`; mirror `step_fire`/`_fire_bolt`/`FIRE_EPS`; `_muzzle` is the spawn point. `player.tscn` unchanged.
- `game/entities/player/reticle.gd` -- add the cooldown arc. `reticle.tscn` (32 px ring texture) unchanged.
- `game/autoloads/events.gd:10` -- `missile_cooldown_changed(ratio: float)` already exists; read-only.
- `game/autoloads/entity_registry.gd` -- add `&"missile"` to `PROJECTILES`.
- `game/core/collision_layers.gd` -- `MASK_PLAYER_SHOTS` (84) for the scene test.
- `game/core/enemy.gd`, `game/entities/asteroids/asteroid.gd` -- read-only; groups `enemies` / `asteroids`; `apply_damage` ignores calls once dead.
- `game/data/tuning.json:21` -- `weapons.missile` (read-only).
- `game/project.godot` -- `fire_missile` (RMB) already mapped.
- `game/tests/unit/test_player_laser.gd` -- pattern: test World + Spawner, `set_physics_process(false)`, `DT`, tick helper; `after_each` releases input and clears `PauseArbiter`.
- `game/tests/unit/test_projectile.gd:95` -- real-physics overlap with a `DamageTarget` double; `game/tests/unit/test_combat.gd` -- World with all three containers.
- `game/tests/fixtures/damage_target.gd` -- recording double (`calls`); add it to a group in the test for splash rows.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_missile.gd` -- write first (red): scene checks (root `Missile`, layer 2, mask `CollisionLayers.MASK_PLAYER_SHOTS`, `monitorable` false, one capsule with height ≥ 15 and ≥ speed / 60, `SmokeTrail` is a `GPUParticles2D` emitting with `local_coords` false); rotation row (capsule axis `global_transform.y` parallel to velocity); Splash row with `DamageTarget` doubles (direct call to `_on_area_entered(A)` and one real-physics hit); a target already queued for deletion is skipped; registry has `missile`.
- `game/tests/unit/test_player_missile.gd` -- write first (red): Aimed shot, Close cursor, Just outside, Cooldown, Ring signal (`watch_signals(Events)` + `get_signal_parameters` per emit), Not pressed, No spawner rows; laser and missile fire independently in the same tick.
- `game/tests/unit/test_combat.gd` -- extend (red): Asteroid hit and Formation rows through real physics (spawn the missile through the Spawner, moving up; Formation setup per Design Notes; disable asteroid drift with `set_physics_process(false)`).
- `game/tests/unit/test_reticle.gd` -- new (red): Reticle row; a fresh reticle has `cooldown_ratio` 0.
- `game/entities/projectiles/missile.gd` + `missile.tscn`, `game/autoloads/entity_registry.gd`, `game/entities/player/player.gd`, `game/entities/player/reticle.gd` -- per Boundaries.
- Commit the `.uid` files Godot generates.

**Acceptance Criteria:**
- Given the sandbox with the missile ready, when the player presses RMB, then a missile spawns at the Muzzle and flies along the ship→cursor vector at 900 px/s (straight up within 32 px), with a ≥ 15 px capsule and a smoke trail.
- Given a missile hitting a Wasp in a formation, then the hit target takes 8 and every other enemy and asteroid within 120 px takes 3 exactly once; an asteroid hit directly takes 8 and stops the missile.
- Given a missile just fired, when RMB is pressed within 1.5 s, then nothing fires, and the reticle's arc, driven only by `Events.missile_cooldown_changed`, goes from 1 to 0.
- Given the codebase, when `git grep -n "instantiate()" -- game ':!game/addons' ':!game/tests'` is run, then outside `scenes/`/`ui/` only `game/core/spawner.gd` matches.
- Given the headless GUT command, then all tests pass with no script errors, and a headless boot of the main scene for 120 frames exits without script errors.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 21 findings — high 0, medium 0, low 11, false 10, maybe-false 0
- findings:
  - `[false]` `[reject]` (blind) The reticle arc stays drawn if the Player is freed mid-cooldown — the Reticle and Player live in the same scene (`sandbox.tscn`), so nothing frees the Player alone; a scene reload frees both.
  - `[low]` `[reject]` (blind) The missile flies parallel to the ship→cursor line from the Muzzle, offset by 40 px — the GDD and the spec define the vector from the ship; the ship chases the cursor, so the offset rarely shows; changing it edits the spec.
  - `[low]` `[reject]` (blind) `speed_px_s`, `straight_up_within_px`, damage and splash values are not validated — data misuse; tuning holds valid values, and guards add branches.
  - `[low]` `[patch]` (blind) No test proves that a held RMB does not keep firing — same root as the verification-gap RMB wiring row; same new test.
  - `[low]` `[patch]` (blind) Splash after a direct asteroid hit is never tested — added `test_missile_asteroid_hit_splashes_nearby_wasp` to `test_combat.gd` (large asteroid 30 → 22, a Wasp about 100 px from the impact is killed by splash).
  - `[low]` `[reject]` (blind) `_draw()` / the arc angles are never tested — headless drawing cannot be observed, and pulling the maths into a helper adds public surface; the spec gives the exact `draw_arc` call and review read it.
  - `[low]` `[reject]` (blind) The smoke trail vanishes with the missile on impact — cosmetic; detaching the emitter adds lifecycle code, and the impact explosion arrives in Story 1.6.
  - `[low]` `[reject]` (blind) The zero-cooldown test restores `Config.tuning` inline, not in `after_each` — the restore runs right after the one `instantiate()` call, so only a crash in `Player._ready` could skip it; unlikely in everyday use.
  - `[false]` `[reject]` (blind) Tests hard-code tuning numbers — the I/O matrix pins the GDD values on purpose, as in Stories 1.3 and 1.4.
  - `[low]` `[reject]` (blind) Centre-distance splash short-changes large asteroids — the spec's Design Notes choose centre distance; changing it edits the spec.
  - `[false]` `[reject]` (blind) A failed missile spawn is silent — the Spawner logs a missing container in `_ready()` (`spawner.gd` `_container`) and an unknown or wrong-type scene on every call.
  - `[low]` `[reject]` (edge) A negative `straight_up_within_px` with the cursor on the ship centre gives a zero velocity — data misuse (negative radius); the guard adds a branch.
  - `[low]` `[reject]` (edge) A non-positive `speed_px_s` is not reported — same as the blind validation row.
  - `[false]` `[reject]` (edge) The Player is freed mid-cooldown and the arc sticks — same as the blind reticle row.
  - `[false]` `[reject]` (edge) An `apply_damage` handler `free()`s another group node during splash — the architecture allows only `queue_free()`, and every `apply_damage` in the codebase uses it; the loop already skips nodes queued for deletion.
  - `[low]` `[patch]` (verification-gap) The RMB input path through `_physics_process` is untested — added `test_held_rmb_fires_once_through_physics_process` (sandbox, RMB held 120 physics frames → exactly 1 missile) and `test_rmb_while_paused_fires_nothing`; the implementer confirmed that swapping to `is_action_pressed` makes the held test fail.
  - `[low]` `[patch]` (intent) RMB is tested through `step_missile`, not real input — same root as the verification-gap row; same new tests.
  - `[false]` `[reject]` (intent) The smoke trail and ring are checked only as node properties — rendered pixels cannot be observed headless; this is the spec's human playtest item (Story 1.7), not a defect.
  - `[false]` `[reject]` (intent) The `instantiate()` grep and the 120-frame boot are not automated tests — the spec states them as verification commands, and both were run this pass: only `game/core/spawner.gd` matches, and the boot exits 0 with no `SCRIPT ERROR`.
  - `[false]` `[reject]` (intent) The spec narrows the epic (splash on asteroid hits, centre distance, tick-quantised cooldown) — descriptive; each choice is consistent with the epic's criteria and recorded in the spec.
  - `[false]` `[reject]` (intent) The operator clause is not triggered — correct: no criterion needs a human action outside the repo; look and feel is a playtest item.

### 2026-10-07 — Review pass
- verdicts: 20 findings — high 0, medium 1, low 12, false 7, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) A missile launch shows no muzzle flash (FR31) — out of scope by intent: the intent's Never list excludes "missile muzzle flash" and assigns it to Story 1.6.
  - `[low]` `[reject]` (blind) The missile aims from the ship centre but spawns at the Muzzle, so it flies parallel to the ship→cursor line — carried: same claim as the first pass's muzzle-offset row; the code still reads that way; changing it edits the spec.
  - `[low]` `[reject]` (blind) Centre-distance splash short-changes large asteroids — carried: same claim as the first pass's row; Design Notes choose centre distance.
  - `[low]` `[reject]` (blind) The smoke trail vanishes with the missile on impact — carried: same claim as the first pass's row; Story 1.6's explosion covers it.
  - `[false]` `[reject]` (blind) The reticle arc sticks if the Player is freed mid-cooldown, or a new Reticle starts out of sync — carried: same claim as the first pass's row; Player and Reticle live and die together in `sandbox.tscn`.
  - `[low]` `[reject]` (blind) `speed_px_s`, `splash_radius_px`, `damage`, `splash_damage` are not validated — carried: same claim as the first pass's validation row; data misuse, guards add branches.
  - `[false]` `[reject]` (blind) Splash reaches Wasps behind an asteroid and off-screen enemies, against FR6 — the intent defines splash exactly as group members within 120 px with no cover rule and no physics queries; FR6 is about projectiles being blocked, and splash is not a projectile, so the code does what the intent specifies.
  - `[low]` `[reject]` (blind) `test_reticle.gd` never tests `_draw` / the arc angles — carried: same claim as the first pass's row; headless drawing is not observable.
  - `[false]` `[reject]` (blind) `missile_direction` is tested only on axis-aligned offsets — the Aimed-shot row is diagonal ((300, −400) offset), and the code uses `Vector2.distance_to` (Euclidean) and `normalized()`, so a (25, 25) or below-ship cursor already gives the correct result; no bad outcome exists at the cited code.
  - `[low]` `[reject]` (blind) The zero-cooldown test restores `Config.tuning` inline, not in `after_each` — carried: same claim as the first pass's row.
  - `[false]` `[reject]` (edge) Player freed mid-cooldown leaves the arc drawn — carried: same claim as the first pass's edge row.
  - `[low]` `[reject]` (edge) `speed_px_s <= 0` gives a missile that never despawns — carried: same claim as the first pass's non-positive speed row.
  - `[low]` `[reject]` (edge) Negative `straight_up_within_px` with the cursor on the ship centre gives a zero velocity — carried: same claim as the first pass's row.
  - `[low]` `[reject]` (edge) Negative or missing `splash_radius_px` / `splash_damage` silently disables splash or heals — carried: same claim as the first pass's validation row (damage and splash values not validated).
  - `[low]` `[patch]` (verification-gap) No test makes `spawn_projectile` return null while a spawner is set, so the "only arm the cooldown on a non-null spawn" rule is unguarded — added `test_failed_spawn_does_not_start_cooldown` to `test_player_missile.gd` (a Spawner whose World lacks `Projectiles`: press → no `missile_cooldown_changed` emit; swap in the working spawner → the next press fires at once). Removing `missile == null or` from the guard makes it fail (12/13 passing); the restored code passes 13/13.
  - `[medium]` `[defer]` (intent) A player's straight shot into `grid_4x2` hits a bottom-row Wasp and splashes nothing; the formation burst is only shown from a missile placed inside the grid — real: the missile centre at contact is ~145-164 px from every neighbour, beyond 120 px. Pre-existing GDD tuning (splash radius 120 vs grid spacing 160 × 120), not caused by this code; needs a tuning or design decision at the Story 1.7 playtest. Added to `deferred`.
  - `[false]` `[reject]` (intent) Splash is measured from the missile centre at overlap, not the hit target's centre — the intent states "within `splash_radius` … of the missile's `global_position`", and the Formation row's numbers hold under that reading (Design Notes); the code matches the intent.
  - `[low]` `[reject]` (intent) The reticle's rendering and the Player → Reticle chain in the sandbox are not tested — carried: same claim as the first pass's `_draw` row and its smoke-trail and ring row; human playtest item.
  - `[false]` `[reject]` (intent) Aim, cooldown and ring are driven through `step_missile`, not real mouse input — `_physics_process` calls exactly `step_missile(Input.is_action_just_pressed(...), get_global_mouse_position(), delta)`, and the first pass's held-RMB and paused integration tests cover the RMB path; descriptive, no defect.
  - `[false]` `[reject]` (intent) The Splash row is tested by a direct `_on_area_entered` call with shapeless doubles — descriptive; the spec's task asks for exactly that plus one real-physics hit, and the asteroid and formation combat tests drive real Wasps and Asteroids through physics.

## Design Notes

**Splash distance is centre-to-centre** from the missile's position at impact. The GDD gives one radius and no hitbox-edge rule; centre distance needs no physics query (the space is locked inside `area_entered`), and groups `enemies`/`asteroids` already exist. The inclusive `≤` is pinned by the Splash row (C at exactly 120 px, direct call, so the impact point is the missile position the test sets).

**Formation setup:** spawn the missile at (880, 220) moving up. It starts between the rows touching nothing and meets the top Wasp (hitbox bottom y ≈ 185.6) first, so the impact point is ≈ (880, 175–190): about 90–105 px from the Wasp at (880, 280) and ≥ 160 px from every other Wasp.

**Mask 84 vs the laser's 20:** the missile follows the architecture's `player_shots` mask. The laser's missing convoy bit is deferred work (DW-2) and is not touched here.

**Cooldown order** (decrement, then fire) makes the 90th tick after a launch the first that can fire again, so every press in the first 1.5 s is dropped:

```gdscript
if _missile_cooldown > 0.0:
	_missile_cooldown -= delta
	if _missile_cooldown <= FIRE_EPS:
		_missile_cooldown = 0.0
	Events.missile_cooldown_changed.emit(_missile_cooldown / _missile_cooldown_s)
```

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0 (class cache for `Missile`).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, exit 0.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --quit-after 120` -- expected: exit 0, no `SCRIPT ERROR` lines.
- `git grep -nI -i -e "users[/\\]" -e "c:[/\\]godot"` -- expected: no output.

**Manual checks:**
- How the missile, its smoke trail and the cooldown arc look and feel are human playtest items (Epic 1 fun gate, Story 1.7). Do not claim them verified.

## Auto Run Result

Status: done

**Summary:** Follow-up review pass on Story 1.5 (the missile). Right-click launches a missile from the Muzzle along the ship→cursor vector at 900 px/s (straight up within 32 px), with a 24 px capsule and a grey smoke trail. On impact the hit target takes 8 and every other enemy and asteroid whose centre is within 120 px takes 3, once each. A 1.5 s cooldown drops presses and is broadcast through `Events.missile_cooldown_changed`, which drives the reticle's arc. This pass added one test only; production code is unchanged.

**Files changed (whole story, since the baseline):**
- `game/entities/projectiles/missile.gd` / `missile.tscn` -- `Missile` projectile: layers, capsule, smoke trail, body, group-based splash.
- `game/autoloads/entity_registry.gd` -- registers `&"missile"`.
- `game/entities/player/player.gd` -- `step_missile`, `missile_direction`, cooldown and ratio broadcast, RMB wiring.
- `game/entities/player/reticle.gd` -- cooldown arc driven by `Events.missile_cooldown_changed`.
- `game/tests/unit/test_missile.gd`, `test_player_missile.gd`, `test_reticle.gd`, `test_combat.gd` -- missile, player, reticle and combat coverage. This pass: `test_player_missile.gd` gains `test_failed_spawn_does_not_start_cooldown`.

**Review findings (this pass):** 20 total -- medium 1, low 12, false 7.
- **Patched:** 1 low (verification-gap): a failed spawn must not arm the cooldown. New test, mutation-checked.
- **Deferred:** 1 medium: a straight player shot into `grid_4x2` splashes no neighbour, because of the GDD tuning (radius 120 vs grid spacing). Needs a tuning decision at the Story 1.7 playtest.
- **Rejected:** 18, 13 of them carried from the first pass. Every reason is in the second 2026-10-07 Review pass entry of the Review Triage Log.

**Follow-up review recommendation:** false. This is a follow-up pass and it patched no high finding (high 0, medium 0, low 1), so the work has converged.

**Verification:**
- `--headless --path game --import`: exit 0.
- GUT headless: 176/176 tests, 992 asserts, exit 0, 0 `SCRIPT ERROR` lines.
- `--headless --path game --quit-after 120`: exit 0, 0 `SCRIPT ERROR` lines.
- Machine-path scan of `game/` and `_bmad-output/implementation-artifacts/`: the only matches are Stories 1.2 and 1.4 describing the scan itself. A repo-wide scan matches only generic `/users/...` examples in vendored skill docs.
- `instantiate()` outside `addons/` and `tests/`: only `game/core/spawner.gd`.
- Mutation check: removing the `missile == null` guard makes the new test fail.

**Residual risks:**
- How the missile, smoke trail and cooldown arc look and feel is unverified and needs a human playtest (Epic 1 fun gate, Story 1.7).
- Formation burst from a real shot: see the deferred item. A straight shot into the bottom row kills one Wasp only.
- The smoke trail disappears with the missile on impact; Story 1.6's explosion should cover it.
- Splash uses centre distance, so a large asteroid whose edge is inside 120 px but whose centre is not takes no splash.
- The missile mask (84) includes convoy, while the laser's (20) does not (DW-2). When the convoy arrives in Epic 6, the Projectile base must not damage it.

