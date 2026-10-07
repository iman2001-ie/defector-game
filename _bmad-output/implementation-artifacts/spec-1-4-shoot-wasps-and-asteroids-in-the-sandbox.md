---
title: 'Story 1.4: Shoot Wasps and Asteroids in the Sandbox'
type: 'feature'
created: '2026-10-07'
baseline_revision: '7ac109da6ebf3e9c7797d94c1b55ecfc7bfc7995'
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
      The laser bolt scene masks enemies and asteroids (20) but not convoy, while CollisionLayers.MASK_PLAYER_SHOTS and the architecture layer table include convoy (84).
    evidence: |-
      game/entities/projectiles/laser_bolt.tscn has collision_mask = 20 (set in Story 1.3; Story 1.4 may not change the laser). game-architecture.md layer table: player_shots mask = enemies, asteroids, convoy; FR33 says convoy ships block every projectile. No convoy exists until Epic 6, so nothing breaks today, but player bolts would pass through convoy ships. test_laser_bolt_masks_enemies_and_asteroids checks single bits only, so the gap is not flagged.
    location: >-
      game/entities/projectiles/laser_bolt.tscn:4
    severity: low
---

<intent-contract>

## Intent

**Problem:** The laser has nothing to hit. The core-feel test needs Wasps that die and asteroids that drift, block bolts and break. Every later enemy also needs the `Enemy` base contract, and every later level needs the asteroid scene. This story adds both.

**Approach:** Add `core/enemy.gd` (architecture contract), a stationary `wasp` enemy, one `asteroid` scene sized in `setup()`, `Spawner.spawn_enemy` / `spawn_asteroid`, and registry entries. The sandbox then spawns a `grid_4x2` Wasp formation, respawns it when every Wasp is dead, and spawns a random-size asteroid at a fixed interval.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript, tabs, snake_case files. `class_name Enemy`, `Asteroid`, `ImpactTier`, `CollisionLayers` are fine; the Wasp script needs no `class_name`.
- `core/impact_tier.gd`: `class_name ImpactTier` with the architecture enum `{ SMALL, MEDIUM, LARGE, BOSS_PART, BOSS_DEATH, PLAYER_HIT, PLAYER_DEATH }` and `static func from_name(tier_name: String) -> int` (`"small"` → `SMALL`, … snake_case names; an unknown name logs `Log.error("data", ...)` and returns `SMALL`).
- `core/collision_layers.gd`: `class_name CollisionLayers`, bit constants `PLAYER 1, PLAYER_SHOTS 2, ENEMIES 4, ENEMY_SHOTS 8, ASTEROIDS 16, PICKUPS 32, CONVOY 64, ALLIES 128`, plus `MASK_PLAYER_SHOTS = ENEMIES | ASTEROIDS | CONVOY` and `MASK_ENEMY_SHOTS = PLAYER | ASTEROIDS | CONVOY` (the architecture's layer table). Scenes keep their numeric values in `.tscn`; tests check them against these constants.
- **Enemy** (`core/enemy.gd`, `class_name Enemy extends Area2D`): `signal resolved`; `var type_id: StringName`; `var tier: int`; `var hp: int`. `setup(params)` only stores (`position` key, global). `_ready()` applies the position, reads `hp = Config.int_("enemies.<type_id>.hp")` and `tier = ImpactTier.from_name(Config.section("enemies.<type_id>").get("tier", ""))`, sets the `Hitbox` child's shape to a new `CircleShape2D` with radius `sprite_px / 2 * Config.num("enemies.<type_id>.hitbox_ratio")`, and adds itself to group `&"enemies"`. `@export var sprite_px: float` is set per enemy scene.
- `apply_damage(amount: int, source: Node)`: ignored once dead. Records `_last_hit_by_ally = source != null and source.get(&"from_ally") == true`, subtracts `amount`, and calls `_die()` at `hp <= 0`. `destroy_by_contact()` sets `_last_hit_by_ally = false` and calls `_die()` (contact destroys the enemy; GDD contact table). `_die()` runs once: `Events.enemy_killed.emit(type_id, global_position, _last_hit_by_ally)`, then `resolved.emit()`, then `queue_free()`. Feedback is a comment placeholder for Story 1.6.
- **Wasp** (`entities/enemies/wasp/wasp.gd` `extends Enemy`, sets `type_id = &"wasp"` in `_init()`; `wasp.tscn`): `collision_layer = 4` (enemies), `collision_mask = 0`, `monitoring = false`, `monitorable = true`; `sprite_px = 64`; a `Hitbox` `CollisionShape2D`; a magenta `#FF2BD6` placeholder hull (`Polygon2D`, pointing down, ~64 px across, ship-like silhouette, not a circle). It holds its spawn position: no movement, no dive (Story 2.4).
- **Asteroid** (`entities/asteroids/asteroid.gd` `class_name Asteroid extends Area2D`; `asteroid.tscn`): `const SIZES: Array[StringName] = [&"small", &"medium", &"large"]`. `setup(params)` stores `position` and `size`. `_ready()` applies the position and reads `asteroids.<size>.diameter_px`, `hp`, `drift_speed_px_s`, `spin_deg_s.min/max`. The `Hitbox` gets a new `CircleShape2D` of radius `diameter / 2`. The `Visual` node is scaled so the jagged placeholder (unit-radius `Polygon2D` fill `#7A6E62` plus a closed `Line2D` rim `#C9D8E8`, ≥ 9 irregular points, never round) spans the diameter. Spin = `randf_range(min, max)` with a random sign. Group `&"asteroids"`. `collision_layer = 16`, `collision_mask = 0`, `monitoring = false`, `monitorable = true`.
- Asteroid `_physics_process`: `position.y += drift * delta`, `rotation_degrees += spin * delta`. Free (no event) once `global_position.y - radius > viewport height` (from `ProjectSettings`, cached in `_ready`). `apply_damage(amount, source)`: ignored once destroyed; subtracts; at `hp <= 0`, `Events.asteroid_destroyed.emit(size, global_position)` once and `queue_free()`. It never spawns anything (no split).
- **EntityRegistry** gains `const ENEMIES: Dictionary[StringName, PackedScene] = { &"wasp": preload(...wasp.tscn) }` and `const ASTEROID: PackedScene = preload(...asteroid.tscn)`.
- **Spawner** resolves `Projectiles`, `Enemies` and `Asteroids` under `world` in `_ready()`, each with `get_node_or_null`, and logs one `Log.error("spawn", ...)` per missing container. `spawn_enemy(type_id, params) -> Enemy` mirrors `spawn_projectile`: registry lookup first (unknown id → error naming it, `null`), null container → `null`, `setup(params)` before `add_child` into `Enemies`. `spawn_asteroid(params) -> Asteroid`: `params.size` must be in `Asteroid.SIZES` (otherwise `Log.error` naming the size, `null`); `setup` then `add_child` into `Asteroids`.
- **Sandbox** (`sandbox.gd`): debug-scene constants (not GDD numbers): `FORMATION_COLUMNS = 4`, `FORMATION_ROWS = 2`, `FORMATION_SPACING = Vector2(160, 120)`, `FORMATION_TOP_Y = 160.0` (rows centred on x 960, slots inside the top 40%), `ASTEROID_INTERVAL_S = 3.0`. `_ready()` spawns the formation. `spawn_formation()` spawns 8 Wasps through the Spawner, connects each `resolved` to a handler and counts them alive. When the count reaches 0, the next formation is spawned with `call_deferred` (resolve can fire inside a physics callback). `step_asteroids(delta)` runs from `_physics_process`: an accumulator spawns one asteroid every interval, with a size picked uniformly from `Asteroid.SIZES`, x uniform in `[radius, 1920 - radius]`, and y = `-radius`. Randomness comes from a member `rng: RandomNumberGenerator` (tests seed it). The first asteroid spawns one interval after start.
- The sandbox is pausable: World entities and the sandbox's own `_physics_process` stop while `PauseArbiter` holds a reason.
- Tests: every test World given to a Spawner must hold all three containers so no unexpected `push_error` fires (GUT tracks errors).

**Never:**
- No Feedback, ImpactTier use beyond `Enemy.tier`, Audio, ShakeCamera, drops or energy, Wasp entry/dive/states, player contact damage or hearts, enemy bullets, WaveDirector, level JSON, `counted` group, HUD, missile (later stories). No new `tuning.json` keys or sections. No per-frame logging. No pooling. No `.instantiate()` of gameplay entities outside `core/spawner.gd`.
- Don't change the laser, Projectile base or player behaviour. Don't modify `sprint-status.yaml` or planning docs.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Wasp kill | spawned Wasp, `apply_damage(1, bolt)` ×3 | hp 3→0; `enemy_killed(&"wasp", pos, false)` once, `resolved` once, queued for deletion | none |
| Overkill | dead Wasp gets a 4th hit in the same frame | no second `enemy_killed` / `resolved` | none |
| Ally source | source with `from_ally = true` lands the kill | `enemy_killed(..., true)` | none |
| Null / plain source | `apply_damage(3, null)` or a source with no `from_ally` | dies, `by_ally` false | none |
| Contact | `destroy_by_contact()` on a full-HP Wasp | dies once, `by_ally` false | none |
| Wasp hitbox | spawned Wasp | `Hitbox` circle radius = 64 / 2 × 0.8 = 25.6 | none |
| Asteroid sizes | spawn small / medium / large | diameter 64/128/224 (hitbox radius 32/64/112), hp 4/12/30, drift 140/100/60 px/s, abs(spin) in [10, 40] | none |
| Drift step | medium asteroid, one 1/60 s step | y +100/60; x unchanged | none |
| Asteroid break | small asteroid, 4 × `apply_damage(1, bolt)` | `asteroid_destroyed(&"small", pos)` once, freed, no new asteroid | none |
| Bottom exit | asteroid at y = 1080 + radius + 1, stepped | freed, no `asteroid_destroyed` | none |
| Unknown enemy | `spawn_enemy(&"nope", {})` | `null`, nothing added | `Log.error("spawn")` naming the id |
| Unknown size | `spawn_asteroid({"size": &"huge"})` | `null`, nothing added | `Log.error("spawn")` naming the size |
| Respawn | all 8 sandbox Wasps killed | after one frame, 8 new Wasps at the same slots | none |
| Asteroid timer | `step_asteroids` for 3.0 s of 1/60 ticks, then 3.0 s more | 1 asteroid, then 2 (none before the first interval) | none |

</intent-contract>

## Code Map

- `game/core/projectile.gd` -- read-only. Calls `area.apply_damage(damage, self)` then frees; `from_ally` field the Enemy reads.
- `game/core/spawner.gd` -- extend: three containers, `spawn_enemy`, `spawn_asteroid`. Keep `spawn_projectile` order (registry before container).
- `game/autoloads/entity_registry.gd` -- add `ENEMIES`, `ASTEROID`.
- `game/autoloads/events.gd` -- read-only; `enemy_killed(enemy_type: StringName, position: Vector2, by_ally: bool)`, `asteroid_destroyed(size: StringName, position: Vector2)` already exist.
- `game/autoloads/config.gd` -- `num`, `int_`, `section` (deep copy; fine in `_ready`). Missing key → `Log.error` + assert unless `assert_on_missing = false`.
- `game/data/tuning.json` -- read-only: `enemies.wasp` (`tier "small"`, `hp 3`, `hitbox_ratio 0.8`), `asteroids.{small,medium,large}` (`diameter_px`, `hp`, `drift_speed_px_s`, `spin_deg_s.min/max`).
- `game/scenes/sandbox/sandbox.gd` / `sandbox.tscn` -- add formation, respawn and asteroid timer to `sandbox.gd`. The `.tscn` already has `World/Enemies` and `World/Asteroids`, and a `Spawner` with `world = ../World`.
- `game/entities/projectiles/laser_bolt.tscn` -- read-only; layer 2, mask 20 (enemies + asteroids), capsule radius 10 / height 40.
- `game/entities/player/player.tscn` -- read-only; layer 1, mask 52. The Player has no `area_entered` handler, so overlaps with Wasps or asteroids do nothing yet.
- `game/tests/unit/test_spawner.gd:8`, `game/tests/unit/test_player_laser.gd:13` -- test Worlds hold only `Projectiles`; add `Enemies` and `Asteroids`. `test_missing_container_logs_and_returns_null` now sees three errors; assert each.
- `game/tests/unit/test_projectile.gd:95` -- pattern for a real-physics overlap test (`await wait_physics_frames`); `test_project_settings.gd:104` -- layer-name test.
- `game/tests/fixtures/damage_target.gd` -- recording double; pattern for test-local Areas.
- `_bmad-output/game-architecture.md` ~L276–296 (layers, damage rule, contact), ~L376–386 (`spawn_enemy`), ~L880–896 (`_die` order), ~L978–1007 (registry, Enemy contract).

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_enemy.gd` -- write first (red): Wasp kill, Overkill, Ally source, Null/plain source, Contact, Wasp hitbox rows (use `watch_signals(Events)` and the Wasp's `resolved`); a scene check that `wasp.tscn`'s root is an `Enemy` with layer `CollisionLayers.ENEMIES`, mask 0, tier `ImpactTier.SMALL`, in group `enemies`; `ImpactTier.from_name` for each name, plus an unknown name with `assert_push_error`.
- `game/tests/unit/test_asteroid.gd` -- write first (red): Asteroid sizes, Drift step, Asteroid break, Bottom exit rows; layer `CollisionLayers.ASTEROIDS`, mask 0, group `asteroids`.
- `game/tests/unit/test_combat.gd` -- write first (red), real physics through a test World + Spawner: (a) a Wasp at (960, 300) and bolts spawned at (960, 700) moving up → after 3 bolts the Wasp is dead and `enemy_killed` fired once; (b) a large asteroid at (960, 500) between bolts from (960, 900) and a Wasp at (960, 200) → after 3 bolts have hit, the asteroid hp is 27 and the Wasp hp is 3 (asteroid drift can be disabled with `set_physics_process(false)` on the asteroid). Layer config: `CollisionLayers.MASK_PLAYER_SHOTS` and `MASK_ENEMY_SHOTS` both contain `ASTEROIDS`; `laser_bolt.tscn` mask has the `ASTEROIDS` and `ENEMIES` bits; project layer 5 is named `asteroids` and its bit equals `CollisionLayers.ASTEROIDS`.
- `game/tests/unit/test_spawner.gd` -- extend (red): `spawn_enemy` / `spawn_asteroid` parent into `Enemies` / `Asteroids` with position applied; Unknown enemy and Unknown size rows; registry has `wasp` and `ASTEROID`.
- `game/tests/unit/test_sandbox.gd` -- extend (red): 8 Wasps in `World/Enemies` at the `grid_4x2` slots after `_ready`; the Respawn row (kill each via `apply_damage(3, null)`, `await wait_process_frames(2)`, 8 alive, none queued for deletion); the Asteroid timer row with a seeded `rng`, every spawned asteroid fully inside x [0, 1920] and at y = -radius; paused (`PauseArbiter.push(&"menu")`, await physics frames) → no new asteroid.
- `game/core/impact_tier.gd`, `game/core/collision_layers.gd`, `game/core/enemy.gd` -- per Boundaries.
- `game/entities/enemies/wasp/wasp.gd` + `wasp.tscn`, `game/entities/asteroids/asteroid.gd` + `asteroid.tscn` -- per Boundaries.
- `game/autoloads/entity_registry.gd`, `game/core/spawner.gd`, `game/scenes/sandbox/sandbox.gd` -- per Boundaries; update the test Worlds in `test_player_laser.gd`.
- Commit the `.uid` files Godot generates.

**Acceptance Criteria:**
- Given a Wasp spawned in the sandbox, when it takes 3 laser hits, then it dies, emits `Events.enemy_killed` and `resolved` exactly once, and frees itself.
- Given the Spawner, when small, medium and large asteroids are spawned and stepped, then they have 64/128/224 px diameters and 4/12/30 HP, drift down at 140/100/60 px/s, rotate at a random 10–40°/s, free themselves after exiting the bottom, never split, and emit `Events.asteroid_destroyed` when destroyed.
- Given an asteroid between the ship's bolts and a Wasp, when bolts are fired at the Wasp, then the asteroid stops every bolt and takes 1 damage per bolt, and the Wasp takes none; and the layer constants show `asteroids` in the masks of both `player_shots` and `enemy_shots`.
- Given the sandbox, when all Wasps of its formation are dead, then a new formation spawns, and asteroids of random sizes keep spawning every interval.
- Given the codebase, when `git grep -n "instantiate()" -- game` is run excluding `game/addons/` and `game/tests/`, then the only match outside `scenes/`/`ui/` is `game/core/spawner.gd`.
- Given the headless GUT command, then all tests (old and new) pass with no script errors, and a headless boot of the main scene for 120 frames exits without script errors.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 34 findings — high 0, medium 0, low 20, false 14, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) `spawn_asteroid` orphans the instanced node when the cast fails — it now keeps `node` and calls `node.queue_free()` in the failure branch, mirroring `spawn_enemy`.
  - `[low]` `[reject]` (blind) Dead enemies and destroyed asteroids still absorb bolts until the frame ends — laser bolts are 180 px apart (1800 / 10), so two cannot reach one target in the same flush, and `queue_free` removes the area before the next tick; the fix adds deferred state changes for a case play does not reach.
  - `[low]` `[reject]` (blind) Asteroid spin ignores the sandbox's seeded RNG — spin is never asserted beyond its range and sign, and the spec has spin use `randf_range`; threading an RNG through `setup` adds a parameter.
  - `[low]` `[reject]` (blind) `Enemy._ready()` has no guard for an empty `type_id` — `Config` already logs the full key path (`enemies..hp`) and asserts, so the failure is loud; a guard adds a branch.
  - `[low]` `[reject]` (blind) Asteroid without a `Hitbox` fails silently — `asteroid.tscn` has a `Hitbox` and is the only asteroid scene; logging adds a branch for a case that cannot happen.
  - `[low]` `[reject]` (blind) The sandbox repeats the asteroid radius lookup — one read of `diameter_px / 2`; a static helper adds public surface for two lines.
  - `[false]` `[reject]` (blind) `resolved` is never emitted if a Wasp is freed some other way, which stalls respawn — nothing frees a sandbox Wasp except `_die()`; scene teardown frees the sandbox and its counter together, and Story 1.7's F5 restart reloads the scene.
  - `[low]` `[patch]` (blind) No test covers contact after an ally hit — added `test_contact_after_ally_hit_is_not_ally`.
  - `[false]` `[reject]` (blind) The pause test can leak a pause reason — `test_sandbox.gd` `after_each` already calls `PauseArbiter.clear()`.
  - `[low]` `[reject]` (blind) World-container setup is copied into three test files — three short local helpers; a shared fixture is extra machinery and adding a container already means editing the Spawner.
  - `[low]` `[patch]` (blind) `ImpactTier._BY_NAME` is an untyped `Dictionary` — now `Dictionary[String, int]`, cast removed.
  - `[false]` `[reject]` (blind) The `instantiate()` acceptance check has no automated test — the spec states it as a grep, the architecture enforces it at review (~L1095), and it was run this pass: only `game/core/spawner.gd` matches.
  - `[low]` `[patch]` (edge) `spawn_asteroid` leaks on a failed cast — same root as the blind leak row; same fix.
  - `[low]` `[reject]` (edge) A second bolt in the same frame is used up on a dead enemy — same as the blind corpse row.
  - `[low]` `[reject]` (edge) A destroyed asteroid absorbs extra bolts that frame — same as the blind corpse row.
  - `[low]` `[reject]` (edge) Empty `type_id` reaches Config — same as the blind `type_id` row; the failure is loud.
  - `[low]` `[reject]` (edge) Zero or negative damage heals the enemy — every caller passes tuning damage ≥ 1; data misuse, and a guard adds a branch.
  - `[false]` `[reject]` (edge) A freed source makes `source.get` error — the only caller (`Projectile._on_area_entered`) passes `self` while it is alive, and tests pass null or live objects.
  - `[low]` `[reject]` (edge) Asteroids with drift ≤ 0, or leaving through the top or sides, never free — tuning drift is 60–140 px/s, the motion is straight down, and sandbox x keeps every rock on screen; data misuse only.
  - `[false]` `[reject]` (edge) A diameter wider than the playfield inverts the x range — the largest diameter is 224 px against 1920 px.
  - `[false]` `[reject]` (edge) A formation that spawns zero Wasps fails silently — the Spawner already logs an error for a missing container or an unknown id.
  - `[false]` `[reject]` (edge) A Wasp leaving the tree without `_die` stalls the counter — same as the blind `resolved` row.
  - `[false]` `[reject]` (edge) An asteroid instanced directly with a bad size — the Spawner validates sizes, and a direct instance makes `Config` log and assert loudly.
  - `[false]` `[reject]` (edge) A large delta spawns an asteroid burst — the physics delta is fixed at 1/60 s, so `step_asteroids` never sees a hitch-sized delta from `_physics_process`.
  - `[low]` `[reject]` (edge, claim) A bolt can hit a Wasp that overlaps a drifting asteroid before the rock — only when the Wasp's hitbox already sits inside the asteroid, which is not "behind cover"; picking the nearest overlap adds sorting to the Projectile base.
  - `[low]` `[patch]` (verification-gap) The respawn deferral is never exercised from inside a physics callback — added `test_respawn_after_kill_inside_physics_callback` (7 direct kills, 3 real bolts at the last Wasp, 8 fresh Wasps at the slots, no engine error).
  - `[low]` `[patch]` (verification-gap) The tier read from tuning is only checked where it equals the default — added `test_tier_read_from_tuning` (bare `Enemy`, `type_id = &"lancer"` → `ImpactTier.MEDIUM`).
  - `[low]` `[patch]` (verification-gap) The asteroid x bounds were checked on only 2 seeded asteroids — the 30-asteroid loop in `test_asteroid_sizes_vary` now asserts x bounds and y = -radius.
  - `[false]` `[reject]` (intent) The `enemy_shots` mask is checked only against a constant the diff defines — no enemy-shot node exists yet, so no wrong mask can occur; `project.godot` holds layer names only, and `test_project_layer_bits_match_constants` ties `CollisionLayers` to them. Enemy bullet scenes (Epic 2) will be tested against `MASK_ENEMY_SHOTS`.
  - `[false]` `[reject]` (intent) The asteroid-blocking test fires from the Spawner, not the ship — the Player fires through the same `spawn_projectile(&"laser_bolt", ...)` call; `test_spawner_wired_to_world_and_player` pins that path.
  - `[low]` `[patch]` (intent) The sandbox respawn is tested only by direct kills — same root as the verification-gap respawn row; same new test.
  - `[false]` `[reject]` (intent) The player-visible surface (art, drift and break) is never exercised — rendered pixels cannot be observed headless; this is the spec's human playtest item, part of the Epic 1 fun gate (Story 1.7), not an operator action outside the repo.
  - `[false]` `[reject]` (intent) The sandbox formation and interval are hard-coded — descriptive; they are debug-scene parameters the GDD does not define, as the spec's Design Notes record.
  - `[false]` `[reject]` (intent) The asteroid hitbox is the full diameter, not 80% (FR25) — the 80% convention covers enemies; the GDD defines asteroids by diameter.

### 2026-10-07 — Review pass
- verdicts: 31 findings — high 0, medium 0, low 4, false 27, maybe-false 0
- findings:
  - `[false]` `[reject]` (blind) Bolts can damage an asteroid before it is on screen — an asteroid spawns at y = -radius, so its lowest edge sits at y = 0 and drifts down; an upward bolt meets that lowest edge first, which is on screen. A bolt already in the 64 px band above the screen when a rock spawns on top of it is there for about 2 frames at 1800 px/s.
  - `[low]` `[reject]` (blind) The asteroid hitbox circle reaches into the notches of the jagged art — the intent fixes the hitbox at `diameter / 2` and the GDD defines asteroids by diameter; changing it edits the spec, and the art is a placeholder.
  - `[low]` `[defer]` (blind) `MASK_PLAYER_SHOTS` (84) does not match `laser_bolt.tscn`'s mask (20, no convoy) — real: the constant matches the architecture table, the bolt mask is from Story 1.3 and this story may not change the laser; harmless until the convoy arrives in Epic 6. Added to `deferred`.
  - `[false]` `[reject]` (blind) Asteroids have no impact tier — the intent's Never list excludes ImpactTier use beyond `Enemy.tier`; no Feedback consumer exists until Story 1.6.
  - `[false]` `[reject]` (blind) Asteroids have no `resolved` signal and no contact hook — the intent excludes the WaveDirector and player contact damage; nothing counts asteroids yet.
  - `[low]` `[reject]` (blind) carried — Asteroid spin ignores the seeded RNG; same claim as the earlier row, and `asteroid.gd:42-43` still uses the global `randf_range`/`randf`.
  - `[false]` `[reject]` (blind) Missing or zero tuning values fail silently — `Config.int_`/`num` log an error and assert on a missing key; zero values are data misuse. The missing-Hitbox and empty-`type_id` parts are carried from the earlier rows.
  - `[low]` `[reject]` (blind) carried — The sandbox repeats the asteroid radius lookup; `sandbox.gd:67` is unchanged.
  - `[low]` `[reject]` (blind) Spawner error paths (scene root of the wrong type, missing `size`, String size) have no tests — the wrong-type branch is unreachable with the current registry; a missing `size` becomes `""` and hits the tested unknown-size path (`spawner.gd:65-67`); a fixture scene for an unreachable branch adds machinery.
  - `[false]` `[reject]` (blind) The combat tests miss hits on separate frames and bolts reaching a dead Wasp — `test_enemy.gd` covers sequential hits through `apply_damage`; the corpse case is carried from the earlier "dead enemies absorb bolts" row.
  - `[false]` `[reject]` (blind) The sandbox tests depend on child order and leave the asteroid timer running — spawn order is deterministic (`formation_slots()` order, then `add_child`), and respawn tests wait at most 30 physics frames, well under the 180-frame interval.
  - `[false]` `[reject]` (edge) Enemy shots will break asteroids, which contradicts the doc comment — no enemy shot exists until Epic 2, so it cannot happen here. The enemy-bullet story must apply the architecture rule that only player shots damage asteroids (see Residual risks).
  - `[low]` `[reject]` (edge) carried — Drift ≤ 0 never frees the asteroid; `asteroid.gd:61-65` is unchanged.
  - `[low]` `[reject]` (edge) carried — Asteroid without a `Hitbox` fails silently; `asteroid.gd:46-50` is unchanged.
  - `[false]` `[reject]` (edge) carried — Directly instanced asteroid with a bad size; the Spawner validates, and Config asserts loudly.
  - `[low]` `[reject]` (edge) carried — Empty `type_id` reaches Config; the failure is loud.
  - `[false]` `[reject]` (edge) carried — An enemy freed without `_die()` stalls the respawn counter; nothing frees a sandbox Wasp except `_die()`.
  - `[false]` `[reject]` (edge) carried — The asteroid x range inverts for huge diameters; the largest is 224 px against 1920 px.
  - `[false]` `[reject]` (edge) carried — A formation that spawns zero Wasps fails silently; the Spawner logs every failure.
  - `[low]` `[patch]` (verification-gap) The asteroid rim width (`RIM_WIDTH_PX / radius`) is never asserted — added a rim-width check to `test_sizes_match_tuning` in `test_asteroid.gd`: `rim.width * radius ≈ RIM_WIDTH_PX` for each size.
  - `[low]` `[defer]` (verification-gap, other) `MASK_PLAYER_SHOTS` vs `laser_bolt.tscn` mask — same root as the blind mask row; same deferral.
  - `[false]` `[reject]` (intent) Asteroid blocking relies on the existing Projectile and is tested on a synthetic World — carried from the earlier "fires from the Spawner, not the ship" row; the Player fires through the same `spawn_projectile` call.
  - `[false]` `[reject]` (intent) Nothing proves that existing Wasps, asteroids and bolts freeze on pause — `sandbox.tscn` sets no `process_mode` (only `PauseArbiter` uses `PROCESS_MODE_ALWAYS`), so every World entity inherits the tree pause.
  - `[false]` `[reject]` (intent) Respawn "after one frame" is tested by waiting 2 frames — `call_deferred` runs at the end of the kill's frame; the second frame lets `queue_free` flush so the test can assert none queued for deletion.
  - `[false]` `[reject]` (intent) Most Enemy contract rows are tested by direct calls — descriptive; the I/O rows name `apply_damage`/`destroy_by_contact` as the surface, and `test_combat.gd` adds a real-physics kill.
  - `[false]` `[reject]` (intent) Ally attribution is tested with a stand-in Projectile — no ally shooter exists yet, and the stand-in is a real `Projectile` with `from_ally` set, the field the Enemy reads.
  - `[false]` `[reject]` (intent) The timer epsilon was added so the timer row passes — it absorbs float drift when summing 180 ticks of 1/60 s, so the spawn lands on the 3.0 s boundary that the row specifies.
  - `[low]` `[reject]` (intent) carried — The sandbox `rng` does not cover spin; same as the blind spin row.
  - `[false]` `[reject]` (intent) `monitorable = true` is not written in the `.tscn` files — it is the engine default and tests assert it at runtime.
  - `[false]` `[reject]` (intent) Foundation reuse is shown only through the `lancer` tier case — descriptive; no other enemy exists in this story.
  - `[false]` `[reject]` (intent) Tests instantiate scenes directly — the acceptance criterion's grep excludes `game/tests/`, and the rule covers gameplay code.

## Design Notes

**Why the sandbox has its own constants:** the formation size, spacing and asteroid interval are debug-scene parameters. The GDD and the architecture define none of them, and the rule "every GDD number lives in data" does not cover them. `tuning.json` has a fixed list of top-level sections, so a `sandbox` section would change the architecture. `grid_4x2` with 8 Wasps mirrors Level 1 wave 1. Story 1.7 (F5 restart, 40-Wasp stress mode) can revisit this.

**Why Wasps stand still:** entry at 350 px/s, holding a slot and diving are Story 2.4 (`enum State`). Here the Wasp is the Epic 1 "sandbox target".

**Respawn deferral:** a kill's `resolved` fires inside `area_entered` (physics flush). Adding Area2Ds there raises "Can't change this state while flushing queries", so the respawn is deferred:

```gdscript
func _on_wasp_resolved() -> void:
	_wasps_alive -= 1
	if _wasps_alive == 0:
		spawn_formation.call_deferred()
```

**`_die()` order** follows the architecture (L889–895) minus Feedback (1.6) and drops (Epic 4): `enemy_killed` → `resolved` → `queue_free()`.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0 (class cache for `Enemy`, `Asteroid`, `ImpactTier`, `CollisionLayers`).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, exit 0.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --quit-after 120` -- expected: exit 0, no `SCRIPT ERROR` lines.
- `git grep -nI -i -e "users[/\\]" -e "c:[/\\]godot"` -- expected: no output.

**Manual checks:**
- How the targets feel to shoot and how readable the placeholder Wasp and asteroid art is are human playtest items. Do not claim them verified.

## Auto Run Result

Status: done

**Summary:** Follow-up review pass on Story 1.4, which was already implemented. The sandbox has a `grid_4x2` formation of 8 magenta Wasps (3 HP, hitbox 80% of a 64 px hull) that die to 3 laser hits, emit `Events.enemy_killed` and `resolved` once, and respawn on the next frame once all are dead. Every 3 s a random-size asteroid (64/128/224 px, 4/12/30 HP, 140/100/60 px/s, random 10–40°/s spin) drifts down, blocks bolts, takes 1 damage per bolt, emits `Events.asteroid_destroyed` once, never splits, and frees itself after leaving the bottom. The story adds the `Enemy` base contract, `ImpactTier`, `CollisionLayers`, and `Spawner.spawn_enemy` / `spawn_asteroid`. This pass added one test assertion; it changed no gameplay code.

**Files changed (this pass):**
- `game/tests/unit/test_asteroid.gd` -- `test_sizes_match_tuning` now checks that the rim stays `RIM_WIDTH_PX` wide on screen at every size.

**Files changed (story total):** `game/core/enemy.gd`, `impact_tier.gd`, `collision_layers.gd`, `spawner.gd`; `game/autoloads/entity_registry.gd`; `game/entities/enemies/wasp/wasp.gd` / `.tscn`; `game/entities/asteroids/asteroid.gd` / `.tscn`; `game/scenes/sandbox/sandbox.gd`; tests `test_enemy.gd`, `test_asteroid.gd`, `test_combat.gd` (new), plus `test_spawner.gd`, `test_sandbox.gd` and `test_player_laser.gd`.

**Review findings (this pass):** 31 total (low 4, false 27).
- **Patched:** 1 low, the rim-width assertion.
- **Deferred:** 1 entry made of 2 low findings. `laser_bolt.tscn` masks 20 rather than `MASK_PLAYER_SHOTS` (84), so convoy is missing. This dates from Story 1.3 and is harmless until Epic 6.
- **Rejected:** 28. Each reason is in the 2026-10-07 Review pass entry of the Review Triage Log above. 15 of them carry earlier rows or restate them.

**Follow-up review recommendation:** false. This was a follow-up pass and it patched no high findings (patched: high 0, medium 0, low 1).

**Verification:**
- `--headless --path game --import`: exit 0.
- GUT headless: 145/145 tests, 782 asserts, exit 0, 0 `SCRIPT ERROR` lines.
- `--headless --path game --quit-after 120`: exit 0, 0 `SCRIPT ERROR` lines.
- Machine-path scan of `game/` and `_bmad-output/implementation-artifacts/`: the only match is Story 1.2's own text describing the scan. A repo-wide scan matches only generic `/api/users/` examples in vendored skill docs.
- `instantiate()` scan outside `addons/` and `tests/`: only `game/core/spawner.gd`.

**Residual risks:**
- How the targets feel to shoot and how readable the placeholder art is are unverified and need a human playtest (the Epic 1 fun gate, Story 1.7).
- `Asteroid.apply_damage` does not check its source. When enemy bullets arrive in Epic 2, that story must make sure only player shots damage asteroids, as the architecture's damage rule says.
- The laser bolt's mask is missing convoy (see `deferred`).
- The sandbox formation and asteroid interval are debug-scene constants in `sandbox.gd`, not tuning data.
