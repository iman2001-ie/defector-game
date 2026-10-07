---
title: 'Story 1.2: Fly the Ship with the Mouse'
type: 'feature'
created: '2026-10-07'
status: 'done'
baseline_revision: '029de563383c176fda0f9d13eb5e620e213ba856'
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

**Problem:** The project has no main scene and nothing to control. The core feel test needs a ship that chases the mouse smoothly in the bottom 60% of the screen, plus the single owner of pause and mouse mode that every later screen relies on.

**Approach:** Add the `PauseArbiter` autoload (architecture API), a `Player` scene (Area2D hurtbox + placeholder sprite) whose `_physics_process` chases the clamped cursor with a speed-capped exponential approach, a `Reticle` Sprite2D at the cursor, and a debug sandbox scene (`scenes/sandbox/sandbox.tscn`) set as the main scene with the level tree's `World` containers.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript, tabs, snake_case files; no `class_name` on autoload scripts. `class_name Player` on `player.gd` is fine.
- Every tuning number comes from `Config`, read once in `_ready()` and cached (`player.max_speed`, `player.chase_ref_distance_px`, `player.chase_ref_time_s`, `player.bounds_y.min/max`, `player.sprite_px`, `player.hurtbox_diameter_px`). The x bounds are `0 .. ProjectSettings display/window/size/viewport_width` (design resolution; stretch `keep` makes world coords always 1920×1080). No per-frame `Config` calls.
- Bounds clamp the ship **centre** (y 432–1080 already reaches the screen bottom, so x uses the same centre rule: 0–1920). Clamp both the chase target and the resulting position.
- The ship never sets `rotation`.
- Only `PauseArbiter` sets `get_tree().paused` and `Input.mouse_mode`. Autoload order becomes `Log, Events, Config, PauseArbiter` with `process_mode = PROCESS_MODE_ALWAYS` set on it.
- PauseArbiter API exactly: `push(reason: StringName)`, `pop(reason: StringName)`, `is_paused() -> bool`, `clear()`, plus `set_gameplay_mouse_mode(mode: Input.MouseMode)` (scenes declare their gameplay mode; architecture: "level.tscn sets CONFINED_HIDDEN, menus set VISIBLE") and `current_mouse_mode() -> Input.MouseMode` (the value `_apply()` writes: `VISIBLE` if paused, else the gameplay mode). Default gameplay mode is `MOUSE_MODE_VISIBLE`.
- The sandbox calls `PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)` in `_ready()`.
- Placeholder art is built from Godot resources (`GradientTexture2D`) inside the `.tscn` files, coalition cyan `#22E6FF`: no external image files, so nothing to credit.

**Never:**
- No firing, Projectile, Spawner, EntityRegistry, Feedback, Audio, ShakeCamera, WorldEnvironment, HUD, DebugTools, HullArea/convoy push-out, hearts or i-frames (later stories). No missile cooldown arc on the reticle yet (Story 1.5).
- Don't mask `convoy` on the hurtbox yet (arrives with the convoy). Don't add new tuning keys or Events signals. Don't enable physics interpolation or change physics tick rate.
- Don't modify `sprint-status.yaml` or planning docs.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Reference move | ship at (960,800), target (1110,800), 60 Hz steps | within 1 px of target after 0.10–0.14 s; never overshoots | none |
| Speed cap | target 1000 px away, one 1/60 s step | moves exactly `max_speed/60` (≈23.33 px), not more | none |
| No snap | any target > 1 px away, first step | distance shrinks but stays > 0 | none |
| Small offset | target 5 px away | moves less than the cap (smoothed, not full-speed) | none |
| Clamp low | cursor at (960, 100) | ship settles at y 432 | none |
| Clamp edges | cursor at (-50, 1200) / (2000, 1200) | ship settles at (0,1080) / (1920,1080) | none |
| Rotation | after any sequence of steps | `rotation == 0.0` | none |
| Pause stack | push A, push B, pop A | paused; pop B → unpaused | none |
| Duplicate / unknown | push A twice then pop A once; pop C never pushed | unpaused after single pop; popping C is a no-op | none |
| Clear | push A, B; `clear()` | unpaused, `is_paused() == false` | none |
| Mouse mode | gameplay mode CONFINED_HIDDEN, no reasons / any reason | `current_mouse_mode()` CONFINED_HIDDEN / VISIBLE | none |
| Infeasible ref time | `chase_ref_time_s` ≤ ref distance / max speed | gain falls back to the solver's upper bound (pure capped chase) | `Log.warn("data", ...)` once in `_ready()` |

</intent-contract>

## Code Map

- `game/project.godot` -- add `PauseArbiter="*res://autoloads/pause_arbiter.gd"` after `Config`; add `[application] run/main_scene="res://scenes/sandbox/sandbox.tscn"`; add `rendering/environment/defaults/default_clear_color=Color(0.0196, 0.0275, 0.0588, 1)` (#05070F background).
- `game/autoloads/config.gd` -- `Config.num/int_` getters (read-only reuse). `player` section already in `game/data/tuning.json`: `max_speed 1400`, `chase_ref_distance_px 150`, `chase_ref_time_s 0.12`, `bounds_y {min 432, max 1080}`, `sprite_px 96`, `hurtbox_diameter_px 24`.
- `game/autoloads/log.gd` -- `Log.warn(category, msg)`; categories fixed (`data`, `scene`, ...).
- `game/tests/unit/test_project_settings.gd:26` -- `AUTOLOADS` must become `["Log", "Events", "Config", "PauseArbiter"]`; `SETTINGS` dict (~L55) gets `application/run/main_scene` and the clear colour.
- `game/tests/unit/test_config.gd` -- pattern for `before_each`/`after_each` isolation (`Config.assert_on_missing`).
- `_bmad-output/game-architecture.md` ~L225–240 (pause model, process modes), ~L253–274 (level tree: `World` → `Asteroids, Enemies, Allies, Pickups, Projectiles, Effects, Player`), ~L276–297 (layers: player=1, enemies=3, asteroids=5, pickups=6), ~L905–932 (PauseArbiter sketch with `_gameplay_mouse_mode()`), ~L545 (`entities/player/` file names).
- `game/scenes/.gitkeep`, `game/entities/.gitkeep` -- delete once the folders hold real files.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_pause_arbiter.gd` -- write first (red): Pause stack, Duplicate/unknown, Clear and Mouse-mode matrix rows, asserting both `is_paused()` and `get_tree().paused`; `after_each` calls `PauseArbiter.clear()` and restores gameplay mode to VISIBLE -- AC 4, TDD.
- `game/tests/unit/test_player_movement.gd` -- write first (red): every movement matrix row via the pure static helpers and via an instanced `player.tscn` driven by `step_toward(target, delta)` (no real mouse); the infeasible-ref-time row via `solve_chase_gain`; scene checks: root is `Area2D`, `collision_layer == 1` (bit 1 only), `collision_mask` == bits 3+5+6 (`52`), `monitorable` true, one `CircleShape2D` radius = `hurtbox_diameter_px / 2` at local (0,0), a `Sprite2D` whose texture size equals `sprite_px` -- AC 1–2.
- `game/tests/unit/test_sandbox.gd` -- instance `sandbox.tscn`: `World` has children `Asteroids, Enemies, Allies, Pickups, Projectiles, Effects` (Node2D), a `Player` (Player) and a `Reticle` (Sprite2D); after `_ready`, `PauseArbiter.current_mouse_mode() == MOUSE_MODE_CONFINED_HIDDEN`; reticle `global_position` equals `get_global_mouse_position()` after one `_process` call; free and reset PauseArbiter in `after_each` -- AC 3.
- `game/autoloads/pause_arbiter.gd` -- per Boundaries and the architecture sketch -- AC 3–4.
- `game/entities/player/player.gd` + `player.tscn` -- `class_name Player extends Area2D`; static `solve_chase_gain(max_speed, ref_distance, ref_time) -> float`, static `chase_step(from, target, delta, max_speed, gain) -> Vector2`, `clamp_to_bounds(p) -> Vector2`, `step_toward(target, delta)`; `_physics_process` calls `step_toward(get_global_mouse_position(), delta)` -- AC 1–2.
- `game/entities/player/reticle.gd` + `reticle.tscn` -- Sprite2D (32 px coalition ring via radial `GradientTexture2D`), `_process` sets `global_position = get_global_mouse_position()` -- AC 3.
- `game/scenes/sandbox/sandbox.gd` + `sandbox.tscn` -- `Sandbox` (Node2D) → `World` (Node2D, pausable) → six containers, `Player` instance at (960, 900), `Reticle` instance last (draws on top) -- AC 1, 3.
- `game/project.godot`, `game/tests/unit/test_project_settings.gd` -- per Code Map.
- Commit the `.uid` files Godot generates.

**Acceptance Criteria:**
- Given the project, when it runs (main scene `sandbox.tscn`) and the mouse moves, then the ship chases the cursor in `_physics_process`, never faster than `player.max_speed`, covers a 150 px move in about 0.12 s, never rotates and stays within x 0–1920, y 432–1080, all values cached from `Config` in `_ready()`.
- Given `player.tscn`, when inspected, then its root `Area2D` is on layer `player` only, masks `enemies`, `asteroids`, `pickups`, has a 24 px-diameter circle centred on a ~96 px cyan placeholder sprite.
- Given the sandbox running with no pause reasons, then the mouse mode is `CONFINED_HIDDEN` and the reticle follows `get_global_mouse_position()`; with any reason pushed, the mode is `VISIBLE`.
- Given `test_pause_arbiter.gd`, when two reasons are pushed and one popped, then the tree stays paused; popping the second unpauses; `clear()` removes all.
- Given the headless GUT command, then all tests (old and new) pass with no script errors, and a headless boot of the main scene for a few frames exits without script errors.

## Design Notes

**Chase model** (frame-rate independent, no overshoot, smooth arrival): per tick `step = min(dist * (1 - exp(-gain * delta)), max_speed * delta)` along the offset. Far moves run at the cap; the last pixels ease in. `gain` is derived once in `_ready()` so designers tune only `chase_ref_*`: find `gain` such that the continuous model covers `ref_distance` to within `ARRIVE_EPS_PX = 1.0` in `ref_time`:

```gdscript
# capped phase until dist == max_speed/gain, then exponential to 1 px
static func _cover_time(v: float, d: float, g: float) -> float:
	var d_cap: float = v / g
	if d_cap >= d:
		return log(d / ARRIVE_EPS_PX) / g
	return (d - d_cap) / v + log(d_cap / ARRIVE_EPS_PX) / g
```

`_cover_time` decreases as `gain` grows, so bisect `gain` in `[1, 10000]` (~40 iterations, `_ready()` only). For 1400/150/0.12 the answer is ≈116 /s. If `ref_time <= ref_distance / max_speed`, no gain fits: warn and return the upper bound.

**Sandbox mouse mode in tests:** headless `Input.mouse_mode` may not reflect writes, so assert on `current_mouse_mode()`. Pausing the tree inside a synchronous GUT test is safe as long as `after_each` clears it.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0 (refreshes the class cache for `Player`).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, exit 0.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --quit-after 120` -- expected: boots the sandbox, exit 0, no `SCRIPT ERROR` lines.
- `git grep -nI -i -e "users[/\\]" -e "c:[/\\]godot"` -- expected: no output.

**Manual checks:**
- Feel (smoothness, cursor confinement in a real window) is a human playtest item; do not claim it verified.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 30 findings — high 0, medium 0, low 24, false 6, maybe-false 0
- findings:
  - `[false]` `[reject]` (blind) Gain solver can land on a rising branch of `_cover_time` when gain > max_speed/eps — the rising branch stays below `ref_distance / max_speed`, and the solver only runs when `ref_time` is above that value, so bisection can only cross on the decreasing branch.
  - `[low]` `[reject]` (blind) Feasibility bound ignores the 1 px epsilon — affects a 0.7 ms window of `ref_time` that no designer would hit; a correct bound also needs solver changes near `GAIN_MAX`.
  - `[low]` `[reject]` (blind) No guards for zero, negative or tiny tuning values — data misuse only; missing keys already log ERROR and assert via `Config`; guards add branches.
  - `[low]` `[reject]` (blind) `_ready()` writes shared sub-resources (hurtbox circle, gradient texture) — every Player writes the same Config values, so no instance diverges; F5 restarts the sandbox (Story 1.7). No current harm.
  - `[low]` `[reject]` (blind) Tests pin tuning numbers (432, 1080, 1920, gain ~116, 8 ticks) — the spec's I/O matrix fixes these as the acceptance check, the same choice Story 1.1 made.
  - `[low]` `[patch]` (blind) Infeasible ref-time warning untested — grouped with the verification-gap row; added `test_infeasible_ref_time_warns_and_uses_capped_chase`.
  - `[low]` `[patch]` (blind) `set_gameplay_mouse_mode` while a reason is pushed untested — code is correct (`current_mouse_mode` checks `is_paused` first); added `test_gameplay_mode_set_while_paused_stays_visible`.
  - `[low]` `[reject]` (blind) PauseArbiter accepts any reason name — matches the architecture API; a typo needs a mismatched push/pop in two places; validation adds a constant and a branch.
  - `[low]` `[reject]` (blind) Reticle freezes while paused and the OS cursor reappears — nothing pushes a pause reason in this story; the Reticle sits in `World` per the architecture; the pause-menu story owns what shows while paused.
  - `[low]` `[reject]` (blind) Sandbox does not restore mouse mode on exit — the architecture has each scene declare its own mode and SceneRouter call `clear()`; only one scene exists today.
  - `[low]` `[reject]` (blind) Spawn point (960, 900) is a literal — the GDD has no number for it (checked); it is sandbox scene placement, and `level.tscn` will place its own Player.
  - `[false]` `[reject]` (blind) `test_reticle_follows_mouse` cannot fail — the test first moves the reticle to (-500, -500), so an empty `_process` fails it; World placement (no CanvasLayer) is asserted in `test_world_containers`.
  - `[low]` `[reject]` (edge) `clear()` keeps the previous gameplay mouse mode — by the architecture, menus set VISIBLE themselves; no second scene exists yet.
  - `[low]` `[reject]` (edge) `push()` accepts typos — same as the blind row above.
  - `[low]` `[reject]` (edge) Zero or negative `max_speed` freezes the ship or gives NaN — data misuse; zero already logs the infeasible warning; guards add branches.
  - `[low]` `[reject]` (edge) A very long `ref_time` (e.g. 10 s) settles near `GAIN_MIN` silently — absurd tuning only; a check adds a branch.
  - `[low]` `[reject]` (edge) `ref_distance <= 1 px` breaks `log()` — data misuse; a guard adds a branch.
  - `[low]` `[reject]` (edge) `bounds_y.min > max` makes the clamp inconsistent — data misuse; a guard adds a branch.
  - `[low]` `[reject]` (edge) Zero or negative `sprite_px` or hurtbox diameter — data misuse; the engine errors loudly.
  - `[low]` `[reject]` (edge) Shared sub-resources mutated in `_ready` — same as the blind row above.
  - `[false]` `[reject]` (edge, claim) With the `GAIN_MAX` fallback the ship snaps to near targets, breaking no-snap — the matrix's "Infeasible ref time" row defines the fallback as a pure capped chase (with a warning); the no-snap row applies to the solved gain, which the tests cover.
  - `[low]` `[patch]` (verification-gap) `_physics_process` → `step_toward(get_global_mouse_position())` is never run by a test — added `test_physics_process_chases_global_mouse`.
  - `[low]` `[patch]` (verification-gap) Infeasible ref-time `Log.warn` in `_ready` untested — added `test_infeasible_ref_time_warns_and_uses_capped_chase` (`assert_push_warning`, capped step, tuning restored).
  - `[low]` `[reject]` (verification-gap) `Input.mouse_mode` write not verified — checked: headless Godot 4.7.2 reads back `MOUSE_MODE_VISIBLE` after writing CONFINED_HIDDEN, so no headless test can observe it; listed as a human check under residual risks.
  - `[false]` `[reject]` (intent) The playtest makes the story `awaiting-operator` — the operator clause covers actions outside the repo (domains, DNS, keys, consoles); a local playtest is the Epic 1 fun gate (Story 1.7), not an owed external action.
  - `[low]` `[patch]` (intent) Mouse-driven movement only tested through helpers — same root as the `_physics_process` gap; fixed by the same test.
  - `[low]` `[reject]` (intent) Real mouse mode only checked through `current_mouse_mode()` — same as the verification-gap row; not observable headless.
  - `[false]` `[reject]` (intent) Reticle test runs without a real cursor so proves nothing — the test still fails if `_process` stops assigning the position; same refutation as the blind row.
  - `[low]` `[reject]` (intent) A ship starting out of bounds jumps in faster than the cap — unreachable today: the only spawn (960, 900) is in bounds and nothing else moves the ship.
  - `[false]` `[reject]` (intent) No evidence the headless boot ran — it ran in step 3 and after the patches: exit 0, 0 `SCRIPT ERROR` lines, `[INFO][scene] Sandbox ready` printed.

### 2026-10-07 — Review pass (follow-up)
- verdicts: 33 findings — high 0, medium 0, low 26, false 7, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) Ship moves at 60 Hz in `_physics_process`, the reticle at refresh rate, and physics interpolation is off, so the ship may judder on high-refresh monitors — the intent says "Don't enable physics interpolation"; already listed as a residual risk for the playtest.
  - `[false]` `[reject]` (blind) Nothing re-applies `CONFINED_HIDDEN` after alt-tab — `Input.mouse_mode` is stored engine state, and Godot's Windows display server re-applies the stored mode's cursor clip when the window is activated again; pausing on focus loss is a design choice no planning doc makes for this story.
  - `[low]` `[reject]` (blind) `test_physics_process_chases_global_mouse` can't tell the headless mouse at (0,0) from any target that clamps to (0,432) — true, but the fix needs a reliable way to inject a mouse position headless (`warp_mouse`/`push_input`), which is extra machinery for one line of wiring; the reticle test already covers `get_global_mouse_position()` use.
  - `[low]` `[reject]` (blind) `test_infeasible_ref_time_warns_and_uses_capped_chase` restores tuning inline, not in `after_each`, and does not check the warning's category or count — the leak only happens when instancing already failed and turned the suite red; `Log.warn` adds the category itself.
  - `[low]` `[reject]` (blind) Collision bits are literals in `player.tscn` and the test, not looked up from `[layer_names]` — AC 2 and the architecture fix the layer numbers; renumbering layers is not planned.
  - `[false]` `[reject]` (blind) One `pop` clears a reason shared by two owners — the I/O matrix's "Duplicate / unknown" row requires exactly this (set semantics: push A twice, pop once, unpaused).
  - `[low]` `[reject]` (blind) Pause changes are not logged or broadcast — the intent forbids new Events signals; a debug log line has no consumer yet and no current harm.
  - `[false]` `[reject]` (blind) `PauseArbiter._ready()` never calls `_apply()`, so an undeclared scene gets no mouse mode — the engine starts unpaused with `MOUSE_MODE_VISIBLE`, which is exactly the arbiter's default state, so nothing differs.
  - `[low]` `[reject]` (blind) Reticle size and cyan are literals in `reticle.tscn`, and the cyan is repeated in `player.tscn` — DESIGN.md fixes the 32 px coalition ring, and the intent puts placeholder art (`GradientTexture2D`, `#22E6FF`) in the `.tscn` files; real art replaces both.
  - `[low]` `[reject]` (blind) The sandbox as main scene isn't flagged for replacement before export — the intent makes it the main scene; `sandbox.gd` marks it temporary, and later stories own the real main scene.
  - `[low]` `[reject]` (edge) Zero or negative `max_speed` freezes or reverses the ship — carried: the same as the earlier "Zero or negative `max_speed`" row; data misuse.
  - `[low]` `[reject]` (edge) `max_speed == 0` divides by zero in the feasibility check — carried: the same as the earlier `max_speed` row; zero already logs the infeasible warning.
  - `[low]` `[reject]` (edge) `chase_ref_distance_px <= ARRIVE_EPS_PX` breaks `log()` — carried: the same as the earlier "`ref_distance <= 1 px`" row.
  - `[false]` `[reject]` (edge) A gain above `max_speed / eps` gives a negative log term and an inaccurate gain — carried: the same as the earlier "rising branch" row; bisection only crosses on the decreasing branch.
  - `[low]` `[reject]` (edge) The feasibility bound ignores the 1 px epsilon — carried: the same as the earlier epsilon row.
  - `[low]` `[reject]` (edge) Inverted or missing `bounds_y` pins the ship — carried: the same as the earlier "`bounds_y.min > max`" row.
  - `[low]` `[reject]` (edge) A non-circle hurtbox or non-gradient texture silently skips the Config sizing — unreachable today (the scene holds exactly these types, and the tests assert them); a warning branch adds complexity for future art that will revisit this code anyway.
  - `[low]` `[reject]` (edge) `sprite_px <= 0` — carried: the same as the earlier sprite or hurtbox size row.
  - `[low]` `[reject]` (edge) `_ready()` mutates shared sub-resources — carried: the same as the earlier shared sub-resources row.
  - `[low]` `[reject]` (edge) `clear()` keeps the previous gameplay mouse mode — carried: the same as the earlier `clear()` row.
  - `[low]` `[reject]` (edge) The sandbox does not restore the mouse mode on exit — carried: the same as the earlier sandbox exit row.
  - `[low]` `[reject]` (edge) `push()` accepts typos — carried: the same as the earlier typo rows.
  - `[low]` `[reject]` (edge) The infeasible-ref-time test restores tuning without `after_each` — the same root as the blind restore row above; it leaks only after a failure that already fails the suite.
  - `[low]` `[reject]` (edge, claim) A ship starting out of bounds jumps in faster than the cap — carried: the same as the earlier out-of-bounds row; the only spawn point is in bounds.
  - `[low]` `[patch]` (verification-gap) No test proves the hurtbox radius and sprite size come from Config, because `player.tscn` hard-codes the same 12.0 and 96 — added `test_hurtbox_and_sprite_sizes_follow_config` (tuning set to 40/64, instance a fresh `player.tscn`, restore, assert radius 20 and texture 64×64).
  - `[low]` `[patch]` (intent) Cursor chasing is only tested by calling `_physics_process` by hand — carried: the same as the earlier "Mouse-driven movement only tested through helpers" row, already fixed by `test_physics_process_chases_global_mouse`; no new action.
  - `[low]` `[reject]` (intent) Mouse mode is checked only through `current_mouse_mode()` — carried: the same as the earlier verification-gap row; not observable headless.
  - `[false]` `[reject]` (intent) Reticle and sandbox mouse behaviour is covered only structurally — carried: the same as the earlier reticle refutation; the test fails if `_process` stops assigning the position.
  - `[low]` `[reject]` (intent) The infeasible warning's count and category are not asserted — the same root as the blind restore row above.
  - `[low]` `[reject]` (intent) Solver edge cases (near `d/v`, a very long `ref_time` hitting `GAIN_MIN`, the negative log) are untested — carried: the same as the earlier epsilon, long-`ref_time` and rising-branch rows.
  - `[low]` `[patch]` (intent) The tests can't tell Config-driven sprite and hurtbox sizes apart from the `.tscn` literals — the same root as the verification-gap row; fixed by the same new test.
  - `[false]` `[reject]` (intent) The clear colour and the hurtbox mask are additions outside the contract — the spec's Code Map lists the clear colour, and AC 2 requires the enemies/asteroids/pickups mask.
  - `[false]` `[reject]` (intent) `sprint-status.yaml` is modified in the working tree — that is the orchestrator's own bookkeeping, not part of this change, and it is not in the reviewed diff.

## Auto Run Result

Status: done

**Summary:** Follow-up review pass on Story 1.2: `PauseArbiter` autoload, a `Player` that chases the clamped cursor with a speed-capped exponential approach, the cursor `Reticle`, and the debug sandbox as the main scene. Four review layers ran on the full diff since `029de56`. One test-only gap was patched.

**Files changed (this pass):**
- `game/tests/unit/test_player_movement.gd` -- added `test_hurtbox_and_sprite_sizes_follow_config`, so the Config-driven hurtbox radius and sprite size can no longer be hidden by the matching literals in `player.tscn`.

**Files in the story (unchanged this pass):** `game/autoloads/pause_arbiter.gd`, `game/entities/player/player.gd`/`.tscn`, `reticle.gd`/`.tscn`, `game/scenes/sandbox/sandbox.gd`/`.tscn`, `game/project.godot`, `game/tests/unit/test_pause_arbiter.gd`, `test_sandbox.gd`, `test_project_settings.gd`, `.uid` files.

**Review findings:** 33 (low 26, false 7). Patched: 1 root cause, low (2 rows from new findings plus 1 carried row that needed no new action). Deferred: none. Rejected: 30. Each reason is in the follow-up Review Triage Log entry above. 17 rows were carried over from the first pass.

**Follow-up review recommendation:** false. This was a follow-up pass and patched high 0, medium 0, low 1 entry, so the work has converged.

**Verification:**
- `--headless --path game --import`: exit 0.
- GUT headless: 74/74 tests, 387 asserts, exit 0, 0 `SCRIPT ERROR` lines.
- `--headless --path game --quit-after 120`: exit 0, 0 `SCRIPT ERROR` lines, `[INFO][scene] Sandbox ready`.
- `git grep` machine-path scan of `game/` and `_bmad-output/`: no matches. A repo-wide scan only matches generic example paths such as `/api/users/` in vendored `.agents/` skill docs.

**Residual risks:**
- Feel (smoothness, the ~0.13 s settle) and real cursor hiding and confinement are unverified and need a human playtest; headless Godot does not reflect `Input.mouse_mode` writes.
- 60 Hz physics without interpolation (the intent forbids enabling it) may judder against the refresh-rate reticle on high-refresh monitors.
- The `_physics_process` wiring test cannot tell the headless mouse at (0,0) from other targets that clamp to (0,432).
- No Esc handling yet: in fullscreen with a confined, hidden cursor, leave the sandbox with Alt+F4. The Reticle freezes while paused (nothing pauses yet).

