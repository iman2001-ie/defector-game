---
title: 'Story 1.3: Fire the Laser'
type: 'feature'
created: '2026-10-07'
baseline_revision: '133aba2e578a7615e972e1a1173f0881de5918ee'
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
deferred: []
---

<intent-contract>

## Intent

**Problem:** The ship flies but cannot shoot. The core-feel test needs a held-LMB laser, and every later entity (Wasps, asteroids, missiles) needs the single creation path (`Spawner` + `EntityRegistry`) and the shared `Projectile` contract that this story introduces.

**Approach:** Add `core/projectile.gd` (architecture contract), `core/spawner.gd` (node in the sandbox), the `EntityRegistry` autoload with the preloaded `laser_bolt.tscn`, and laser firing in `Player._physics_process`: while `fire_laser` is held, spawn one twin-visual bolt per `1 / weapons.laser.rate_per_s` through the Spawner, with a muzzle flash on every shot.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript, tabs, snake_case files. `class_name Projectile`, `class_name Spawner`, `class_name LaserBolt` are fine; no `class_name` on the `EntityRegistry` autoload.
- Autoload order becomes `Log, Events, Config, PauseArbiter, EntityRegistry`. `EntityRegistry` holds only `const PROJECTILES: Dictionary[StringName, PackedScene] = { &"laser_bolt": preload("res://entities/projectiles/laser_bolt.tscn") }`.
- `Spawner.spawn_projectile(type_id: StringName, params: Dictionary) -> Projectile`: registry lookup → `instantiate()` → `setup(params)` → `add_child` into `World/Projectiles`. Unknown id: `Log.error("spawn", ...)` naming the id, return `null`. Spawner gets the World via `@export var world: Node2D` (set in `sandbox.tscn`), resolves the `Projectiles` container with `get_node_or_null` in `_ready()`; a missing container logs an error and spawns return `null`.
- `Projectile.setup(params)` only stores (`position`, `velocity`, `damage`); `_ready()` applies the position. `_physics_process`: `position += velocity * delta`, then `queue_free()` if outside the playfield rect (viewport size from `ProjectSettings` grown by `OFFSCREEN_MARGIN_PX = 64`, computed once in `_ready`). `_on_area_entered(area)`: if already spent return; mark spent; `area.apply_damage(damage, self)` if it `has_method`; `_on_impact(area)`; `queue_free()`. Base `_on_impact` is an empty hook (Feedback arrives in 1.6). Adds itself to group `&"projectiles"`.
- `laser_bolt.tscn`: root `Area2D` with `laser_bolt.gd` (`extends Projectile`), `collision_layer = 2` (player_shots), `collision_mask = 20` (enemies + asteroids), `monitorable = false`, `monitoring = true`; one vertical `CapsuleShape2D` radius 10, height 40 (≥ 30 = speed/60); two cyan `#22E6FF` elongated `GradientTexture2D` sprites `BoltLeft`/`BoltRight` at x ±8 (twin is visual only).
- Player caches `weapons.laser.damage` (`Config.int_`), `speed_px_s`, `rate_per_s` in `_ready()`. Bolt velocity is `Vector2(0, -speed)`; spawn position is the `Muzzle` Marker2D's global position.
- Fire timing in `step_fire(held: bool, delta: float)`: cooldown counts down every tick; when held and cooldown ≤ a tiny epsilon, fire one bolt and add the interval (accumulator, no drift). When not held, cooldown is floored at 0 so the next press fires at once. At most one bolt per tick.
- Muzzle flash: a `MuzzleFlash` Node2D on the player (two additive cyan sprites at x ±8 near the nose), shown on every shot and hidden after half the fire interval via a countdown in `_physics_process` (no timers or allocation per shot).
- Paused: the Player lives in the pausable `World`, so `_physics_process` (and firing) stops; `Input.is_action_pressed(&"fire_laser")` is read only there. Only `PauseArbiter` pauses.
- The sandbox root wires the Spawner into the Player: `sandbox.gd` `_ready()` calls `player.set_spawner(spawner)` via `@onready` refs (call down; no absolute paths, no `get_parent()` chains). A player with no spawner does not fire and does not error per tick.

**Never:**
- No Feedback, Audio/zap SFX, ShakeCamera, Enemy base, Wasp, asteroids, missile, convoy masks, Events signals, HUD (later stories). No per-shot or per-frame logging. No pooling. No new tuning keys. No `.instantiate()` of gameplay entities outside `core/spawner.gd`.
- Don't modify `sprint-status.yaml` or planning docs.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Rate | held for 60 ticks of 1/60 s | exactly 10 bolts (first on tick 1); 600 ticks → exactly 100 | none |
| Release/re-press | held 1 tick, released 2 ticks, held 1 tick | 1 bolt (cap holds for taps); after ≥ 6 released ticks a press fires at once | none |
| Not held | 60 ticks not held | 0 bolts, flash hidden | none |
| Bolt motion | one 1/60 s step | moves exactly (0, -30); never moves sideways | none |
| Off-screen | bolt at y -40 stepped once | queued for deletion; bolt at (960, 500) is not | none |
| Hit | bolt overlaps an area with `apply_damage` | `apply_damage(1, bolt)` once, then bolt queued for deletion | none |
| Double overlap | two `_on_area_entered` calls same frame | only the first area is damaged | none |
| No damage method | area without `apply_damage` | no call, bolt still freed | none |
| Unknown id | `spawn_projectile(&"nope", {})` | returns `null`, nothing added | `Log.error("spawn", ...)` naming the id |
| Paused | `PauseArbiter.push(&"menu")`, `fire_laser` held | no bolts spawn | none |
| No spawner | `step_fire(true, 1/60)` with no spawner set | no bolt, no error | none |

</intent-contract>

## Code Map

- `game/entities/player/player.gd` -- add laser caching in `_ready()` (after movement setup), `set_spawner()`, `step_fire()`, flash countdown; `_physics_process` becomes `step_toward(...)` then `step_fire(Input.is_action_pressed(&"fire_laser"), delta)`. Keep existing movement code untouched.
- `game/entities/player/player.tscn` -- add `Muzzle` (Marker2D, (0, -40)) and `MuzzleFlash` (Node2D, `visible = false`) with `FlashLeft`/`FlashRight` sprites (radial `GradientTexture2D`, additive `CanvasItemMaterial`, ADR-003). Root layer/mask stay 1/52.
- `game/scenes/sandbox/sandbox.tscn` / `sandbox.gd` -- add `Spawner` node (Node, `core/spawner.gd`) as a child of `Sandbox` after `World`, with `world = NodePath("../World")`; wire `set_spawner` in `_ready()`.
- `game/project.godot` -- `[autoload]` add `EntityRegistry="*res://autoloads/entity_registry.gd"` after `PauseArbiter`.
- `game/tests/unit/test_project_settings.gd:26` -- `AUTOLOADS` gains `"EntityRegistry"`.
- `game/tests/unit/test_sandbox.gd` -- existing World/Player/Reticle tests must stay green; extend with spawner wiring.
- `game/data/tuning.json` `weapons.laser` -- `damage 1`, `rate_per_s 10`, `speed_px_s 1800` already present (read-only).
- `game/tests/unit/test_player_movement.gd` -- pattern for instancing `player.tscn`, tuning swaps and `assert_push_warning`; `test_config.gd` shows `Config.assert_on_missing` isolation and `assert_push_error`.
- `_bmad-output/game-architecture.md` ~L276–303 (layers, damage rule, capsule rule), ~L936–1000 (Projectile sketch, Spawner creation steps, EntityRegistry sketch), ~L1082 (fire only while unpaused), ~L1095 (`.instantiate()` grep rule), ~L1111 (bounds-check off-screen free).
- `game/core/.gitkeep` -- delete once `core/` holds real files.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_projectile.gd` -- write first (red): Bolt motion, Off-screen, Hit, Double overlap, No damage method rows (synchronous `_physics_process`/`_on_area_entered` calls on a bolt added via a test-local Spawner or directly with `add_child_autofree`); scene checks on `laser_bolt.tscn`: root is `Projectile`, layer 2, mask 20, `monitorable` false, a `CapsuleShape2D` with height ≥ `Config.num("weapons.laser.speed_px_s") / 60` and rotation 0, two sprites. Use `tests/fixtures/damage_target.gd` (Area2D recording `apply_damage` calls) -- AC 1–2.
- `game/tests/unit/test_spawner.gd` -- write first (red): spawn into a test World with a `Projectiles` container → returned bolt is parented there, `global_position`, `velocity`, `damage` equal the params, in group `projectiles`; Unknown id row with `assert_push_error`; `EntityRegistry.PROJECTILES` has `laser_bolt` -- AC 1.
- `game/tests/unit/test_player_laser.gd` -- write first (red): Rate, Release/re-press, Not held, No spawner rows via `step_fire` on an instanced `player.tscn` with a test Spawner + World; bolts spawn at the `Muzzle` global position with velocity (0, -1800) and damage 1; flash visible right after a shot and hidden after half the interval; Paused row: instance `sandbox.tscn`, `PauseArbiter.push(&"menu")`, `Input.action_press(&"fire_laser")`, `await wait_physics_frames(10)` → `World/Projectiles` empty, then pop, await again → ≥ 1 bolt; `after_each` releases the action and clears PauseArbiter. If GUT cannot await frames while the tree is paused, assert `player.can_process() == false` instead and record that in the spec -- AC 2–3.
- `game/core/projectile.gd`, `game/core/spawner.gd`, `game/autoloads/entity_registry.gd` -- per Boundaries -- AC 1.
- `game/entities/projectiles/laser_bolt.gd` + `laser_bolt.tscn` -- per Boundaries -- AC 2.
- `game/entities/player/player.gd` + `player.tscn`, `game/scenes/sandbox/sandbox.gd` + `sandbox.tscn`, `game/project.godot`, `game/tests/unit/test_project_settings.gd` -- per Code Map -- AC 1–3.
- Commit the `.uid` files Godot generates.

**Acceptance Criteria:**
- Given the codebase, when `git grep -n "instantiate()" -- game` excluding `game/addons/` and `game/tests/` is run, then the only match outside `scenes/`/`ui/` is `game/core/spawner.gd`, and every spawn calls `setup(params)` before `add_child` into `World/Projectiles`.
- Given the sandbox running unpaused, when LMB is held, then twin-visual bolts spawn at 10/s from the muzzle, fly straight up at 1800 px/s, deal 1 damage per bolt (one damage instance), show a muzzle flash on every shot, and are freed after leaving the playfield bounds.
- Given the tree is paused, when LMB is held, then no bolts fire.
- Given the headless GUT command, then all tests (old and new) pass with no script errors, and a headless boot of the main scene for a few frames exits without script errors.

## Spec Change Log

- 2026-10-07 (dev): The Design Notes sketch decrements the cooldown *before* the fire check. Taken literally that fires on ticks 1, 6, 11, … (12 bolts per 60 ticks), because tick 1's `-1/60` debt carries into the first interval. That contradicts the I/O matrix (10 per 60 ticks, ticks 1, 7, 13, …). `Player.step_fire` keeps the same accumulator semantics but checks the cooldown first and decrements it after. Released (or with no spawner), the cooldown floors at 0. The matrix rows pass as written. The paused test awaits physics frames successfully under GUT, so the `can_process()` fallback was not needed.

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 26 findings — high 0, medium 0, low 19, false 7, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) A projectile spawned without `velocity` never leaves the bounds and leaks — the only caller (Player) always passes velocity; the `{}` spawns in `test_spawner.gd` return null before instancing; a guard or lifetime cap adds a branch for caller misuse.
  - `[false]` `[reject]` (blind) Motion is local but the bounds check is global, so they diverge under a container offset — `World/Projectiles` sits at the identity transform, and a later ShakeCamera moves the Camera2D, which never changes node `global_position`; the bad outcome cannot occur.
  - `[false]` `[reject]` (blind) Only `area_entered` is connected, so physics-body targets are missed — architecture D4 makes every entity an `Area2D`; no body targets exist or are planned.
  - `[low]` `[reject]` (blind) `from_ally` is dead state — it is part of the architecture's Projectile sketch, and the Enemy contract (Story 1.4) reads `source.from_ally`; removing it now means re-adding it next story.
  - `[low]` `[reject]` (blind) The Spawner's "scene is not a Projectile" branch is untested — unreachable with the current registry (one LaserBolt entry); a test needs a stub registry, which is extra machinery.
  - `[low]` `[patch]` (blind) The `rate_per_s <= 0` path is untested — added `test_non_positive_rate_warns_and_disables_laser` (tuning swap, `assert_push_warning`, 60 held ticks → 0 bolts).
  - `[low]` `[reject]` (blind) `test_no_spawner_no_bolt_no_error` does not assert zero errors — `step_fire` has no logging on that path, and GUT reports unexpected engine errors on its own; an extra assertion adds nothing today.
  - `[low]` `[reject]` (blind) The test pins the literal `Vector2(0, -1800)` — the spec's I/O matrix fixes these numbers as the acceptance check, the same choice Stories 1.1 and 1.2 made.
  - `[low]` `[patch]` (blind) The muzzle offset is written twice (`Muzzle` and `MuzzleFlash`) — `MuzzleFlash` is now a child of `Muzzle` at the origin; `player.gd` and the tests use `Muzzle/MuzzleFlash`; added `test_flash_sits_on_muzzle`.
  - `[low]` `[reject]` (blind) No automated test enforces "only the Spawner instantiates" — the architecture enforces that rule by a grep at review (~L1095); it was run this pass and only `core/spawner.gd` matches.
  - `[low]` `[reject]` (blind) An unknown id logs on every call (10/s while held) — the laser uses a const id that the registry test pins; unreachable, and a dedupe set adds state.
  - `[low]` `[patch]` (blind) The capsule radius 10 misses the outer edge of the sprites at x ±8 (to ±11) — capsule radius set to 11; height stays 40 (≥ 30).
  - `[low]` `[reject]` (edge) Zero or missing `weapons.laser.speed_px_s` gives stationary bolts — data misuse; a missing key already logs an error and asserts via `Config`; a guard adds a branch.
  - `[low]` `[reject]` (edge) Zero-velocity projectiles leak — same as the blind velocity row; caller misuse only.
  - `[low]` `[reject]` (edge) Damage ≤ 0 is silent — data misuse; a guard adds a branch.
  - `[false]` `[reject]` (edge) `add_child` on a freed container when World is freed before the Spawner — World and Spawner belong to the same scene and are freed together at frame end; nothing frees World alone.
  - `[low]` `[reject]` (edge) `world` assigned after `Spawner._ready` is never resolved — the sandbox sets it in the `.tscn`, and the tests set it before `add_child`; no late assignment exists; a setter adds surface.
  - `[low]` `[reject]` (edge) A failed spawn still uses up the cooldown — it only happens when the container is missing, which already logs an error at ready; no bolt can ever fire then, so the timing is moot.
  - `[low]` `[patch]` (verification-gap) The `area_entered` wiring is never exercised; hit tests call the handler directly — added `test_real_overlap_through_physics_damages_once` (target on the enemies layer, awaits physics frames, asserts one `apply_damage(1, bolt)` and the free). The implementer confirmed it fails with the connect line deleted.
  - `[low]` `[patch]` (verification-gap) The non-positive rate guard is untested — same root as the blind rate row; fixed by the same test.
  - `[low]` `[reject]` (verification-gap, other) A failed spawn costs a cycle and is untested — same as the edge cooldown row.
  - `[false]` `[reject]` (intent) The human playtest makes the story `awaiting-operator` — the operator clause covers actions outside the repo (domains, DNS, keys, consoles); the feel playtest is the Epic 1 fun gate (Story 1.7), as decided in Story 1.2's triage.
  - `[low]` `[reject]` (intent) Tests drive `step_fire` directly; the real input path only asserts "> 0 bolts" — the rate is pinned by the deterministic `step_fire` tests; `_physics_process` is one line that the paused/unpaused test runs with `Input.action_press`.
  - `[low]` `[patch]` (intent) No test shows a real physics collision — same root as the verification-gap wiring row; fixed by the same test.
  - `[false]` `[reject]` (intent) The AC1 grep property is untested — the spec states it as a grep check, not a unit test; it was run this pass and only `game/core/spawner.gd` matches.
  - `[false]` `[reject]` (intent) The flash is only checked through `visible` — rendered pixels cannot be observed headless, and `visible` is exactly what drives rendering; the readability is listed as a human playtest item.

### 2026-10-07 — Review pass (follow-up)
- verdicts: 24 findings — high 0, medium 0, low 17, false 7, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) The Design Notes `step_fire` sketch still decrements before the check, unlike `player.gd` — the fix is a spec edit; the Spec Change Log already records the order and why.
  - `[low]` `[reject]` (blind) The Boundaries line says capsule radius 10 while the scene had 11 — the fix that remains is a spec edit; the scene was brought back to the contract (see the intent radius row).
  - `[false]` `[reject]` (blind) The frontmatter is stale and `sprint-status.yaml` is modified — `in-review` is this pass's own state and `review_loop_iteration: 0` is correct; `sprint-status.yaml` is the orchestrator's file, outside the reviewed diff.
  - `[low]` `[reject]` (blind) `Muzzle` sits at a fixed (0, -40) while the hull size comes from `player.sprite_px` — the Code Map fixes (0, -40); a coupling to `sprite_px` adds code and the hull size is not expected to change; no new tuning keys are allowed.
  - `[low]` `[patch]` (blind) The off-screen test passes even with a 0 px margin — same root as the verification-gap margin row; fixed by `test_bolt_within_margin_survives`.
  - `[low]` `[reject]` (blind) `test_no_spawner_no_bolt_no_error` counts another spawner's container and does not assert zero errors — carried for the error part (the first pass rejected it); the count is vacuous by construction, but the test's real job is to prove the null-spawner path does not crash, which GUT reports as an engine error.
  - `[low]` `[patch]` (blind) No test shows the flash cycling during a continuous hold — the code hides on tick 4 and shows again on tick 7 (countdown runs before the fire check); added `test_flash_cycles_while_held`.
  - `[low]` `[reject]` (blind) The flash stays visible while paused — the whole `World` freezes, bolts included; a frozen flash matches the frozen frame, and hiding it needs a pause hook.
  - `[false]` `[reject]` (blind) The Spawner's cached container can go stale — carried: World and Spawner are freed together; nothing frees World alone.
  - `[low]` `[patch]` (blind) The tunnelling test divides by a literal 60 instead of the physics tick rate — now divides by `Engine.physics_ticks_per_second`. The related "rate above tick rate is silently capped" part is rejected with the edge rate row.
  - `[low]` `[reject]` (blind) Subclasses must call `super._ready()` — standard GDScript inheritance; no subclass overrides `_ready()` today.
  - `[low]` `[reject]` (edge) A `rate_per_s` above the physics tick rate is capped at one bolt per tick and the cooldown debt grows while held — data misuse (tuning is 10/s); the debt floors at 0 on release; a warning adds a branch.
  - `[low]` `[patch]` (edge) With a missing container, an unknown id returns null without the id error — `spawn_projectile` now looks up the registry before checking the container, so an unknown id always logs.
  - `[low]` `[patch]` (verification-gap) No test catches a removed cooldown floor on release (a long release would bank a 60/s burst) — added `test_long_release_does_not_bank_shots` (60 released ticks, 6 held → exactly 1 bolt).
  - `[low]` `[patch]` (verification-gap) The 64 px off-screen margin is untested — added `test_bolt_within_margin_survives` (bolt at (960, -20), stepped once, not freed).
  - `[low]` `[reject]` (intent) The AC 2 rate and flash are tested through `step_fire`, not the real input path — carried: the rate is pinned by the deterministic tests, and `_physics_process` is one line run by the pause test.
  - `[false]` `[reject]` (intent) No test checks that `fire_laser` is bound to LMB — `test_project_settings.gd:18` asserts `fire_laser` → `MOUSE_BUTTON_LEFT`.
  - `[low]` `[reject]` (intent) The off-screen free is not observed under real physics — the engine calls the same `_physics_process` the tests call; the real-overlap test already runs bolts under physics.
  - `[false]` `[reject]` (intent) The AC 1 grep is not a test — carried: the spec states it as a grep; run this pass, only `game/core/spawner.gd` matches.
  - `[false]` `[reject]` (intent) AC 4 is not shown by the diff — run this pass: GUT 105/105, headless boot exit 0, no `SCRIPT ERROR`.
  - `[low]` `[patch]` (intent) The capsule radius 11 departs from the contract's literal radius 10 — set back to 10 in `laser_bolt.tscn`; the sprites' radial gradient reaches zero alpha at their ±11 edge, so the visible bolt stays inside the hitbox width.
  - `[false]` `[reject]` (intent) `MuzzleFlash` under `Muzzle` departs from "on the player" — it is still on the player, at the nose; the contract does not require a direct child.
  - `[low]` `[patch]` (intent) The Spawner checks the container before the registry — same root as the edge unknown-id row; same fix.
  - `[false]` `[reject]` (intent) `sprint-status.yaml` is modified in the working tree — not part of this diff; it is the orchestrator's file and was neither written nor committed by this pass.

## Design Notes

**Fire accumulator** (physics delta is fixed at 1/60, so `if`, not `while`):

```gdscript
func step_fire(held: bool, delta: float) -> void:
	_fire_cooldown -= delta
	if not held:
		_fire_cooldown = maxf(_fire_cooldown, 0.0)
	elif _fire_cooldown <= FIRE_EPS and _spawner != null:
		_fire_cooldown += _fire_interval
		_fire_bolt()
	# flash countdown here
```

`FIRE_EPS = 1e-6` absorbs float drift so 6 ticks of 1/60 always equal one 0.1 s interval. Ticks 1, 7, 13, … 55 fire → 10 bolts in 60 ticks.

**Why the Player calls the Spawner directly:** exactly one known node must act, so a direct call (architecture: "Use direct calls when exactly one known node must act") beats a new Events signal; the scene root injects the reference.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0 (refreshes the class cache for `Projectile`, `Spawner`, `LaserBolt`).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, exit 0.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --quit-after 120` -- expected: exit 0, no `SCRIPT ERROR` lines.
- `git grep -nI -i -e "users[/\\]" -e "c:[/\\]godot"` -- expected: no output.

**Manual checks:**
- Feel (fire rhythm, flash readability) is a human playtest item; do not claim it verified.


## Auto Run Result

Status: done

**Summary:** Story 1.3, follow-up review pass. Holding LMB streams twin-visual laser bolts straight up at 10/s and 1800 px/s, 1 damage each, with a muzzle flash on every shot. Bolts free themselves off-screen, and nothing fires while paused. The story also adds the `Projectile` base, the `Spawner` node and the `EntityRegistry` autoload. This pass ran four review layers and patched six low entries: four test gaps, the Spawner's check order, and the capsule radius, which is back to the contract's 10.

**Files changed (this pass):**
- `game/core/spawner.gd` -- looks up the registry before the container check, so an unknown id always logs its error.
- `game/entities/projectiles/laser_bolt.tscn` -- capsule radius 11 → 10, matching the intent contract.
- `game/tests/unit/test_player_laser.gd` -- added `test_long_release_does_not_bank_shots` and `test_flash_cycles_while_held`.
- `game/tests/unit/test_projectile.gd` -- added `test_bolt_within_margin_survives`; the tunnelling test reads `Engine.physics_ticks_per_second`.

**Files in the story overall:** `core/projectile.gd`, `core/spawner.gd`, `autoloads/entity_registry.gd`, `project.godot`, `entities/projectiles/laser_bolt.gd`/`.tscn`, `entities/player/player.gd`/`.tscn`, `scenes/sandbox/sandbox.gd`/`.tscn`, the new tests and the `damage_target.gd` fixture (see commit `ee8e124e93a8e45b6c54f9495b8c3897c169e484`).

**Review findings:** 24 (low 17, false 7). Patched 6 low entries:
- off-screen margin test
- long-release test
- flash cycling while held
- tunnelling test tick rate
- Spawner registry-before-container order
- capsule radius 10

Deferred: none. Rejected: 18; each reason is in the Review Triage Log above.

**Follow-up review recommendation:** false. This is a follow-up pass and it patched no high entries (high 0, medium 0, low 6). The work has converged.

**Verification:**
- `--headless --path game --import`: exit 0.
- GUT headless: 105/105 tests, 467 asserts, exit 0, 0 `SCRIPT ERROR` lines.
- `--headless --path game --quit-after 120`: exit 0, 0 `SCRIPT ERROR` lines.
- Machine-path scan of `game/`: no matches.
- `instantiate()` scan outside `addons/` and `tests/`: only `game/core/spawner.gd`.

**Residual risks:**
- Fire rhythm and muzzle-flash readability are unverified and need a human playtest.
- The rate is pinned by the deterministic `step_fire` tests; the real input path only checks "> 0 bolts".
- Bolts hit nothing yet: there are no targets until Story 1.4.
- `sprint-status.yaml` is left modified and uncommitted in the working tree. It belongs to the orchestrator and this run did not touch it.
