---
title: 'Story 1.6: Feel Every Impact Scale with Size'
type: 'feature'
created: '2026-10-07'
baseline_revision: '01325de86f1b6849136066ac9dd3f8d0dddb7aee'
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
      The off-screen pre-warm at x = -1000 may be culled by the renderer, so particle and additive-material shaders might not actually compile before the first real explosion.
    evidence: |-
      Feedback.prewarm() spawns explosions at (-1000, 540); every GPUParticles2D has visibility_rect Rect2(-200,-200,400,400), scaled at most 4x, so each explosion lies wholly outside the viewport. If culled canvas items are never drawn, no pipeline compiles and the first real impact can still hitch. Headless tests only count nodes and positions, so they cannot settle it. Would settle: a Story 1.7 frame-time check of the first large explosion on the dev laptop (with and without pre-warm). The x = -1000 position is mandated by the architecture and the story's acceptance criteria.
    location: >-
      game/autoloads/feedback.gd prewarm(); game/entities/effects/explosion.tscn visibility_rect
    severity: medium (unverified)
  - summary: >-
      Nothing caps live explosions; each one builds three GPUParticles2D nodes plus a ring, and double feedback and missile splash multiply them.
    evidence: |-
      Every Feedback.impact spawns a full Explosion (Burst, Sparks, Debris, Shockwave) that lives until LIFETIME_S, with no pooling (ruled out by the spec) and no budget. A kill makes two impacts (projectile + death), and splash chains add more. Headless tests cannot measure GPU cost. Would settle: the Story 1.7 stress test, frame time with many simultaneous kills on the dev laptop.
    location: >-
      game/autoloads/feedback.gd impact(); game/entities/effects/explosion.tscn
    severity: medium (unverified)
  - summary: >-
      A fresh clone cannot run the GUT suite until the project has been imported once with --import.
    evidence: |-
      Verified in a clean git-archive copy with no game/.godot: Audio's preload of the five WAVs fails, then every class_name type is missing, and the suite errors out. The baseline 01325de copy also fails (no class_name cache before --import), so the root cause predates this story. After --headless --path game --import, all 240 tests pass. The fix is to add the --import step before the test command in AGENTS.md (an agent-context file).
    location: >-
      AGENTS.md section 3 (test command); game/autoloads/audio.gd preloads
    severity: medium
---

<intent-contract>

## Intent

**Problem:** Kills and hits in the sandbox are silent and instant: nothing explodes, shakes, freezes or sounds, so Pillar 2 ("impact scales with size") cannot be judged at the Story 1.7 fun gate (FR30, FR31).

**Approach:** Add the `Feedback` and `Audio` autoloads, a `ShakeCamera`, and a data-driven `Explosion` effect. Every death and projectile impact calls only `Feedback.impact(tier, position)`, which spawns the tier's explosion through the Spawner, shakes the camera, applies hit-stop and plays the tier's SFX. The weapons get their zap/thump sounds, the missile gets a muzzle flash, and the sandbox pre-warms one explosion per tier.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript, tabs, snake_case, `Log` only. Tier numbers come only from `tuning.feedback.tiers.<name>` (read once, cached). Add `"sfx_volume_db"` to every tier row: small `-6`, medium `-3`, large `0`, the other four `0`; record it as GDD decision-log row 26 (provisional first-pass tuning per row 11, GDD "explosion volume and pitch scale with the size tier"). No other tuning changes.
- **Autoload order** in `project.godot`: `Log, Events, Config, PauseArbiter, Audio, Feedback, EntityRegistry`. `Audio` and `Feedback` set `process_mode = PROCESS_MODE_ALWAYS`.
- **ImpactTier** gains `const NAMES: Array[String]` in enum order (`small` … `player_death`).
- **Feedback** (`autoloads/feedback.gd`): caches one row per tier in `load_tiers()` (called from `_ready`): `explosion_scale`, `shake_px`, `shake_s`, `hit_stop_ms`, `sfx_pitch`, `sfx_volume_db` via `Config.num`, `sfx` as StringName, `extras` as `Array[StringName]`. API: `register_camera(c: ShakeCamera)`/`unregister_camera(c)`, `register_spawner(s: Spawner)`/`unregister_spawner(s)` (unregister is a no-op unless `s` is the current one), `impact(tier: int, position: Vector2)`, `hit_stop(ms: float)`, `is_hit_stopped() -> bool`, `prewarm()`, `reset()`. `impact` = explosion (if a spawner is registered) + `camera.shake(px, s)` (if a camera is registered and both > 0) + `hit_stop(ms)` (if > 0) + `Audio.play_sfx(sfx, Audio.DEFAULT_PITCH_JITTER, sfx_volume_db, sfx_pitch)`. An out-of-range tier logs `Log.error("combat", …)` and does nothing. Hit-stop follows Design Notes. `reset()` ends any hit-stop (`time_scale = 1.0`, stale timers ignored). `prewarm()` spawns one explosion per tier at `PREWARM_POSITION = Vector2(-1000, 540)` with that tier's scale and extras, and no shake, hit-stop or sound.
- **ShakeCamera** (`systems/camera/shake_camera.gd`, `class_name ShakeCamera extends Camera2D`): `process_mode = ALWAYS`; registers in `_ready`, unregisters in `_exit_tree`. `shake(amplitude_px, duration_s)`: ignored if either ≤ 0 or `amplitude_px < current_amplitude()`; otherwise replaces the active shake. `current_amplitude() = amplitude × remaining / duration` (0 when idle). `_process(delta)` calls `step(delta)`: while `PauseArbiter.is_paused()`, `offset = Vector2.ZERO` and remaining is kept; otherwise remaining -= delta (floored at 0) and `offset` = a random point in the square ±`current_amplitude()` (own `RandomNumberGenerator`, no allocation), `Vector2.ZERO` once idle. Under hit-stop `delta` is 0, so the shake keeps jittering without decaying.
- **Audio** (`autoloads/audio.gd`): `const DEFAULT_PITCH_JITTER := 0.05`, `const POOL_SIZE := 12`, `const SFX: Dictionary[StringName, AudioStream]` preloading `laser_zap`, `missile_launch`, `explosion_small`, `explosion_medium`, `explosion_large` from `assets/audio/sfx/sfx_<id>.wav`. `_ready` creates 12 `AudioStreamPlayer.new()` children on bus `&"SFX"`, each tracking in-use (set on play, cleared on its `finished`) and a start serial. `play_sfx(id: StringName, pitch_jitter := DEFAULT_PITCH_JITTER, volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer`: unknown id → `Log.warn("audio", …)` once per id, returns null; else picks the first not-in-use player, or steals the one with the oldest serial (`stop()` first), sets stream, `volume_db`, `pitch_scale = pitch × (1 + randf_range(−jitter, jitter))`, plays, returns it. `newest_player()` returns the most recently started player (tests).
- `game/default_bus_layout.tres`: buses `Master`, `Music`, `SFX`, `UI`, the last three sending to `Master`.
- **Explosion** (`entities/effects/explosion.tscn` + `explosion.gd`, `class_name Explosion extends Node2D`): `setup({position, scale: float, extras: Array[StringName]})`; `_ready` applies position and uniform scale. Children: `Burst` (`GPUParticles2D`, always), `Sparks` (`&"sparks"`), `Debris` (`&"debris"`) — all `one_shot`, explosiveness 1, ≤ 32 particles, additive `CanvasItemMaterial`, `emitting` set true in `_ready` only when enabled — and `Shockwave` (`Node2D` + `shockwave_ring.gd`, visible only for `&"shockwave"`, expanding fading ring via `draw_arc`). Other extras are ignored. `_process` advances elapsed time, drives the ring's progress, and `queue_free()`s at `LIFETIME_S` (≥ every child lifetime). Art constants live in the script; colours follow DESIGN.md (asteroid `#7A6E62`/`#C9D8E8` debris).
- **Spawner**: `spawn_explosion(params) -> Explosion` into `World/Effects`, scene `EntityRegistry.EXPLOSION`. `_ready` looks up `Effects` with `get_node_or_null` (no error log; `Log.debug` if missing) and calls `Feedback.register_spawner(self)` only when found; `_exit_tree` unregisters.
- **Retrofits:** `Enemy._die()` calls `Feedback.impact(tier, global_position)` before `Events.enemy_killed`. `Asteroid` caches `ImpactTier.from_name(String(size))` in `_ready` and calls `Feedback.impact` before `Events.asteroid_destroyed`. `Projectile` gains `var impact_tier: int = ImpactTier.SMALL`; base `_on_impact` calls `Feedback.impact(impact_tier, global_position)`. `Missile._init()` sets `MEDIUM`; its `_on_impact` runs `apply_splash(area)` then `super._on_impact(area)`.
- **Player:** after a successful bolt spawn `Audio.play_sfx(&"laser_zap", <weapons.laser.sfx_pitch_jitter cached>)`. After a successful missile spawn `Audio.play_sfx(&"missile_launch")` and the muzzle flash shows for `maxf(_flash_left, MISSILE_FLASH_S)` (`const MISSILE_FLASH_S := 0.05`, art constant).
- **Sandbox:** a `ShakeCamera` node (child of `Sandbox`, position (960, 540), enabled) and `Feedback.prewarm()` at the end of `_ready()`.
- **SFX assets:** placeholders generated by a committed stdlib-only script `tools/gen_placeholder_sfx.py` (fixed seed, 16-bit mono 44.1 kHz WAV, each < 1 s) into `game/assets/audio/sfx/`. Kenney downloads are blocked on the dev network. Create `game/assets/CREDITS.md` stating the placeholders are project-generated (no third-party assets yet). Commit the `.import` and `.uid` files Godot generates.
- Tests that trigger impacts call `Feedback.reset()` in `after_each`; only `feedback.gd` assigns `Engine.time_scale` (tests read it, never write it).

**Never:**
- No `instantiate()` outside `core/spawner.gd` (plus `scenes/`, `ui/`), so no separate spark/shockwave scenes. No pooling. No per-frame logging, group scans or allocation in `ShakeCamera`/`Feedback`/`Audio`. No positional audio, music, HUD, vignette, white flash, boss chain, player hit/death wiring, F5 reload hook (Story 1.7). No change to splash, damage, cooldown or movement rules. Don't modify `sprint-status.yaml` or planning docs other than decision-log row 26.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Tier data | load tiers | 7 rows; small 0.5/0/0/0 `[sparks]`; medium 1/4/0.15/0 `[debris]`; large 2/8/0.25/40 `[debris, shockwave]` pitch 0.8; boss_part 1.5/6/0.2/30; boss_death 4/20/1.0/150; player_hit 0.5/6/0.2/50; player_death 2/12/0.5/100 | none |
| Large impact | spawner + camera registered, `impact(LARGE, (500, 400))` | one Explosion in Effects at (500, 400), scale (2, 2), Debris emitting, Shockwave visible, Sparks not; camera amplitude 8; `time_scale` 0; newest SFX player stream `explosion_large`, pitch in [0.76, 0.84], volume 0 | none |
| Small impact | `impact(SMALL, p)` | explosion scale 0.5 with Sparks; amplitude 0; `time_scale` 1; volume −6 | none |
| No listeners | nothing registered, `impact(MEDIUM, p)` | no crash, SFX still plays | none |
| Bad tier | `impact(99, p)` | nothing happens | `Log.error` |
| Hit-stop overlap | `hit_stop(100)`, then at ~20 ms `hit_stop(40)` | `time_scale` 0 at 80 ms (real), 1.0 by ~150 ms | none |
| Hit-stop extend | `hit_stop(40)`, then at ~20 ms `hit_stop(100)` | still 0 at 60 ms, 1.0 by ~170 ms | none |
| Shake keep strongest | `shake(8, 0.25)`, step 0.05, `shake(4, 0.15)` | amplitude 6.4, then 3.2 after step 0.1 more; idle after 0.25 total, offset ZERO | none |
| Shake replace | `shake(4, 0.15)`, step 0.1, `shake(2, 0.2)` | amplitude 2.0 | none |
| Shake paused | active shake, `PauseArbiter.push(&"menu")`, step 0.1 | offset ZERO, amplitude unchanged | none |
| SFX steal | 12 plays (no `finished`), 13th, 14th | 13th returns the 1st player, 14th the 2nd | none |
| SFX reuse | player 5 emits `finished`, next play | returns player 5 | none |
| Unknown SFX | `play_sfx(&"nope")` twice | null both times | one `Log.warn` |
| Sandbox tiers | sandbox; kill Wasp, small, medium, large asteroid; land a missile | newest Explosion scale 0.5, 0.5, 1, 2, 1; camera amplitude 0, 0, 4, 8, 4; `is_hit_stopped()` only for the large one | none |
| Pre-warm | load sandbox | 7 Explosions in Effects at x −1000; amplitude 0; `time_scale` 1 | none |
| Weapon SFX | fire a bolt; fire a missile | newest player `laser_zap` with pitch in [0.95, 1.05]; then `missile_launch`, and the muzzle flash visible | none |

</intent-contract>

## Code Map

- `game/core/impact_tier.gd` -- enum + `from_name`; add `NAMES`.
- `game/core/enemy.gd:67` `_die()` -- comment marks where `Feedback.impact` goes.
- `game/entities/asteroids/asteroid.gd:68` `apply_damage` -- destroy branch marks where `Feedback.impact` goes; `size` is `&"small"|&"medium"|&"large"`, same names as tiers.
- `game/core/projectile.gd:61` `_on_impact` -- base hook (runs after direct damage, inside `area_entered`; adding non-physics nodes there is fine).
- `game/entities/projectiles/missile.gd:23` -- `_on_impact` override; `_init` does not exist yet.
- `game/core/spawner.gd` -- add `_effects`, `spawn_explosion` (mirror `spawn_asteroid`), registration. Never `push_error` on missing Effects: GUT fails tests on unasserted `push_error` (`failure_error_types` includes `push_error`); `Log.warn` (push_warning) and `Log.debug` are safe.
- `game/autoloads/entity_registry.gd` -- add `const EXPLOSION: PackedScene`.
- `game/entities/player/player.gd:121` `_fire_bolt`, `:137` `step_missile` -- SFX + missile flash; `_flash_left` already decays in `step_fire` every tick.
- `game/scenes/sandbox/sandbox.tscn` / `sandbox.gd` -- add ShakeCamera node, prewarm call. Spawner is ready before Sandbox `_ready` (children first).
- `game/autoloads/pause_arbiter.gd` -- `is_paused()`, `push/pop/clear` for the shake pause test.
- `game/data/tuning.json:258` -- `feedback.tiers` (add `sfx_volume_db`); `weapons.laser.sfx_pitch_jitter` exists (0.05).
- `game/project.godot` `[autoload]` -- insert `Audio`, `Feedback` after `PauseArbiter`.
- `game/tests/unit/test_project_settings.gd:26` -- `AUTOLOADS` list to update.
- `game/tests/unit/test_combat.gd`, `test_player_laser.gd`, `test_player_missile.gd`, `test_sandbox.gd` -- patterns (test World + Spawner, tick helpers, sandbox load); large-asteroid kills now trigger a 40 ms hit-stop, so add `Feedback.reset()` to `after_each` (and right after a kill if a test then steps physics by awaiting frames).
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- append row 26.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_feedback.gd`, `test_shake_camera.gd`, `test_audio.gd`, `test_explosion.gd`, `test_impact_tiers.gd` (sandbox rows) -- write first (red): every I/O row; also buses exist and send to Master, pool size 12 on bus SFX, jitter range over 50 plays with not all pitches equal, camera registers/unregisters with the tree, Explosion frees itself after `_process(LIFETIME_S)`, Explosion with `[]` extras enables only Burst.
- `game/tests/unit/test_player_laser.gd`, `test_player_missile.gd`, `test_project_settings.gd`, `test_combat.gd` -- extend (red): Weapon SFX row, autoload order, `Feedback.reset()` hygiene.
- `tools/gen_placeholder_sfx.py` -- generate the 5 WAVs (zap: short falling tone; launch: low thump + noise; explosions: noise bursts, longer and lower with size).
- `game/default_bus_layout.tres`, `game/autoloads/audio.gd`, `game/autoloads/feedback.gd`, `game/systems/camera/shake_camera.gd`, `game/entities/effects/explosion.gd` + `.tscn` + `shockwave_ring.gd`, `game/core/impact_tier.gd`, `game/core/spawner.gd`, `game/autoloads/entity_registry.gd`, `game/core/enemy.gd`, `game/entities/asteroids/asteroid.gd`, `game/core/projectile.gd`, `game/entities/projectiles/missile.gd`, `game/entities/player/player.gd`, `game/scenes/sandbox/*`, `game/project.godot`, `game/data/tuning.json` -- per Boundaries.
- `game/assets/CREDITS.md`, decision-log row 26 -- per Boundaries.

**Acceptance Criteria:**
- Given the codebase, when `git grep -n "Engine.time_scale *=" -- game ':!game/addons'` runs, then only `game/autoloads/feedback.gd` matches; and `git grep -n "instantiate()" -- game ':!game/addons' ':!game/tests'` matches only `game/core/spawner.gd` outside `scenes/`/`ui/`.
- Given the codebase, when grepping `game/core`, `game/entities` for `Feedback.`, then entities call only `Feedback.impact(` (ShakeCamera and Spawner only register/unregister).
- Given the headless GUT command, then all tests pass with no script errors, and a headless 120-frame boot of the sandbox exits without script errors.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 28 findings — high 0, medium 0, low 21, false 6, maybe-false 1
- findings:
  - `[low]` `[reject]` (blind) Camera shake offsets `get_global_mouse_position()`, so the chase target and missile aim jitter by up to the shake amplitude — real, but at most 8 px for 0.25 s in Epic 1 (under ~2° of aim at typical cursor distances) and the reticle stays under the cursor; compensating needs Player→camera coupling. Playtest item for Story 1.7.
  - `[low]` `[reject]` (blind) Laser and missile SFX play at 0 dB with no volume key, louder than small/medium explosions — the mix is a feel question for the Story 1.7 playtest; adding weapon volume keys is a tuning change the spec rules out (no other tuning changes).
  - `[low]` `[reject]` (blind) Explosion and missile pitch jitter use `Audio.DEFAULT_PITCH_JITTER`, not data — the architecture defines `play_sfx(id, pitch_jitter := 0.05, …)`; the only GDD jitter number (laser ±5%) is read from `weapons.laser.sfx_pitch_jitter`. New keys would be a spec change.
  - `[low]` `[reject]` (blind) No load-time check that every tier's `sfx` id is registered (4 tiers have no sound) — those tiers are unreachable until Epics 3/7, and `play_sfx` already warns once per unknown id; a load-time check adds a branch for no current caller.
  - `[low]` `[reject]` (blind) The pool steals the oldest player with no priority, so a busy fight can cut a large explosion — the story's acceptance criterion and the architecture specify exactly "the oldest player is stolen"; priority would change the spec.
  - `[maybe-false]` `[defer]` (blind) Pre-warm at x = -1000 may be culled and warm nothing — headless runs cannot show shader compilation; would settle with a Story 1.7 frame-time check of the first large explosion. If true, medium. Added to `deferred`.
  - `[low]` `[patch]` (blind) `shockwave_ring.gd` had no `class_name`, so it was reached untyped via `call()` — added `class_name ShockwaveRing`, typed `_shockwave`, direct calls in `explosion.gd` and `test_explosion.gd`.
  - `[low]` `[patch]` (blind) `Feedback.tier_row()` returned a shallow copy sharing the cached `extras` array — now `duplicate(true)`.
  - `[low]` `[reject]` (blind) A second camera/spawner registration silently replaces the first — the sandbox has exactly one of each; level transitions arrive in Epic 3 with `SceneRouter`; a warn branch adds complexity for no current case.
  - `[low]` `[patch]` (blind) The missile's failed-spawn early return was untested and `test_failed_launch_no_thump` had dead lines — removed the dead lines (test renamed `test_press_on_cooldown_no_thump`) and added `test_failed_spawn_no_thump_no_flash` (no `missile_launch`, flash hidden).
  - `[low]` `[patch]` (blind) `test_hit_stop_extend` asserted wall-clock bounds with no slow-frame guard — added a `pending` guard when the second call lands after 50 ms (stale timer ~40 ms vs extended stop ≥ 150 ms stay far apart); assertions otherwise unchanged; 4 runs clean.
  - `[low]` `[reject]` (edge) `pitch <= 0` or `pitch_jitter >= 1` gives an invalid `pitch_scale` — data misuse; a missing `sfx_pitch` already fails loudly through `Config` (error + debug assert); guard adds a branch.
  - `[low]` `[reject]` (edge) A missing `explosion_scale`/`sfx_pitch` reads as 0 — same: `Config` reports missing keys loudly; data misuse.
  - `[low]` `[reject]` (edge) An explosion scale ≤ 0 gives a degenerate transform — data misuse; tuning holds positive scales.
  - `[low]` `[reject]` (edge) A second Spawner exiting while the first is alive stops explosions — one Spawner per scene; fix needs a registry array.
  - `[low]` `[reject]` (edge) A re-parented Spawner never re-registers — nothing re-parents the Spawner; moving registration needs an extra `_effects` branch in `_enter_tree`.
  - `[low]` `[patch]` (edge) A re-added ShakeCamera never re-registers — moved `Feedback.register_camera(self)` to `_enter_tree()`; added `test_re_added_camera_registers_again`.
  - `[false]` `[reject]` (edge) Effects freed while the Spawner stays registered → `add_child` on a freed node — Effects lives in the same scene as the Spawner; freeing the scene runs the Spawner's `_exit_tree` (which unregisters) before any node is deleted, so no impact can reach a freed Effects.
  - `[low]` `[reject]` (edge) Four tiers name unregistered SFX ids — same root as the blind sfx-id row; unreachable until later epics, warned once.
  - `[low]` `[patch]` (verification-gap) The sandbox ShakeCamera framing was untested — added `test_shake_camera_frames_the_playfield` to `test_sandbox.gd` (enabled, at (960, 540), zero offset, screen centre (960, 540)).
  - `[low]` `[patch]` (verification-gap) The laser zap jitter was not pinned to `weapons.laser.sfx_pitch_jitter` — `test_bolt_plays_laser_zap_with_jitter` now fires 10 bolts and asserts all pitches within 1 ± the tuning value and more than one distinct pitch.
  - `[false]` `[reject]` (intent) "Placeholder Kenney sounds" read as a human-only download — the criterion says Kenney placeholders are *acceptable*, not required, and the GDD allows generated SFX; generated placeholders meet "the zap/thump plays". No out-of-repo action is required.
  - `[false]` `[reject]` (intent) The perceived feel is a human-only check — it is the Story 1.7 fun-gate playtest inside the project, not a vendor/console action; the spec says not to claim it verified.
  - `[low]` `[reject]` (intent) Four tiers play silently — same root as the blind sfx-id row.
  - `[false]` `[reject]` (intent) Sandbox tests assert data values, not shake durations or audiovisual output — durations are covered by the tier-row and ShakeCamera decay tests; rendered output is not observable headless.
  - `[low]` `[reject]` (intent) The generated-sounds substitution is not in the decision log — it is a temporary placeholder documented in `CREDITS.md` and the spec, which the acceptance criterion explicitly permits; the spec limits planning-doc edits to row 26.
  - `[false]` `[reject]` (intent) Pre-warm only runs in the sandbox — the sandbox is the only level-type scene until `level.tscn` arrives in Epic 2.
  - `[false]` `[reject]` (intent) Orchestrator rules — met: `sprint-status.yaml` untouched, no operator actions are owed, `blocked` unused.

### 2026-10-07 — Review pass (follow-up)
- verdicts: 26 findings — high 0, medium 2, low 17, false 4, maybe-false 3
- findings:
  - `[low]` `[reject]` (blind) Debris uses the asteroid rock gradient for every Medium/Large impact, so a missile hitting a Wasp sprays grey chunks — real, but extras are per tier in the GDD tuning and the colours follow DESIGN.md; passing a material/source colour would add a new `setup` param. Playtest item for Story 1.7.
  - `[low]` `[reject]` (blind) `shake()` replaces a long decaying shake with a shorter one of equal current amplitude — the spec mandates exactly this rule ("ignored if `amplitude_px < current_amplitude()`; otherwise replaces"); the long-tail case (boss_death) is unreachable until Epic 7.
  - `[low]` `[reject]` (blind) Shake jitter picks a new offset every rendered frame, so its speed depends on refresh rate — the spec specifies a random point per `step`; on the 60 Hz target it is as designed. Feel item for Story 1.7.
  - `[low]` `[reject]` (blind) `load_tiers()` reads `sfx` and `extras` with `.get()`, bypassing Config's missing-key report — a missing `sfx` still warns once at play time (unknown id); a missing `extras` silently drops effects. Data misuse only (tuning has every key); a guard adds branches.
  - `[maybe-false]` `[defer]` (blind) No cap on live explosions: each spawns 3 GPUParticles2D plus a ring, and double feedback and splash multiply them — headless tests cannot show the GPU cost; settle with the Story 1.7 stress test (frame time with many simultaneous kills). If true, medium. Added to `deferred`.
  - `[maybe-false]` `[reject]` (blind) Hit-stop freezes on the explosion's first frame, before particles have moved — freezing on the impact frame is the usual hit-stop look; at worst a low feel issue for the Story 1.7 playtest.
  - `[low]` `[reject]` (blind) Tests hard-code tuning values (asteroid hp 30, laser 6 ticks per bolt, flash 3 ticks, missile damage 8) — tests pin the current tuning on purpose (`test_asteroid.gd` `EXPECTED` dates from Story 1.4); the data-driven rule covers game code. A tuning change fails loudly, not silently.
  - `[false]` `[reject]` (blind) The unknown-SFX warn test depends on leftover `_warned_ids` state — the id `nope_test_audio` is used only by that test, and GUT runs each test once per process; no other path warns for it first.
  - `[low]` `[reject]` (blind) The hit-stop tests fall back to `pending` on slow frames and can hide regressions — deliberate from the first pass (flaky tests are worse than none); on normal frames they assert. An injectable clock would add public surface to `Feedback`.
  - `[low]` `[reject]` (blind) No test shows that off-screen exits stay quiet (no `Feedback.impact`) — the exit paths (`queue_free` on bottom exit or off-screen) do not call `_die`/`_on_impact`, by reading the code; tests for absent calls add little.
  - `[low]` `[patch]` (blind) The spec says ShakeCamera "registers in `_ready`" and the test message still said so, though the first-pass patch moved it to `_enter_tree` — spec edits are out of bounds for review; patched the test message in `test_shake_camera.gd` to "registered on entering the tree".
  - `[low]` `[reject]` (blind) `CREDITS.md` lists the generated SFX as "Project-owned" with no named licence — the repo has no LICENSE file yet; choosing one is the owner's decision. No third-party asset is involved.
  - `[medium]` `[defer]` (edge) A fresh clone cannot run GUT before `--import`: `Audio`'s `preload` of the WAVs fails and cascades — verified in a clean `git archive` copy. Pre-existing root cause: the baseline `01325de` copy also fails (no `class_name` cache until `--import`); after `--import` all 240 tests pass. The fix is to document `--import` in AGENTS.md (an agent-context file). Added to `deferred`.
  - `[low]` `[reject]` (edge) Hit-stop can end up to one frame early, because `SceneTreeTimer` counts whole frame deltas — already a recorded residual risk; re-arming the timer adds a branch. Tune at the Story 1.7 playtest.
  - `[low]` `[reject]` (edge) The player can launch a missile during hit-stop — verified: `_physics_process` runs with delta 0 under `time_scale` 0, so a fresh press spawns a frozen missile (a held laser cannot refire, since its cooldown is frozen too). Nothing in the GDD blocks input during hit-stop, and the window is at most 150 ms. Feel item.
  - `[low]` `[patch]` (edge) Spec and test claim "registers in `_ready`" — same root as the blind spec-drift row; test message patched.
  - `[low]` `[patch]` (edge) Tests that trigger impacts did not call `Feedback.reset()` in `after_each` as the spec requires; a future hit-stop on small/medium tiers would leak `time_scale` 0 — added `after_each` with `Feedback.reset()` to `test_enemy`, `test_asteroid`, `test_missile` and `test_projectile`, and the reset to the existing `after_each` in `test_player_laser` and `test_player_missile`.
  - `[low]` `[patch]` (verification-gap) The laser jitter test could not tell tuning from `Audio.DEFAULT_PITCH_JITTER` (both 0.05) — added `test_laser_zap_jitter_follows_tuning`: with tuning set to 0 for a fresh Player, every zap pitch is exactly 1.0.
  - `[medium]` `[patch]` (verification-gap) No test runs ShakeCamera's `_process` → `step` wiring, so shake could vanish with a green suite — added `test_process_drives_shake` (processing on, `shake(8, 0.25)`, 3 process frames: offset non-zero, amplitude below 8).
  - `[low]` `[patch]` (verification-gap) The missile thump and flash were untested with a non-positive cooldown — `test_non_positive_cooldown_warns_fires_every_press_no_emit` now asserts `missile_launch` and a visible flash on every press.
  - `[false]` `[reject]` (intent) carried — Tests check object state, not rendered or audible output — the perceptual check is the Story 1.7 playtest, as the spec says; rendered output is not observable headless.
  - `[low]` `[reject]` (intent) No end-to-end test from player input through projectile to impact feedback — both halves are covered (fire → SFX/flash; spawned projectile → Feedback); joining them needs a full physics run in the sandbox for little extra signal.
  - `[maybe-false]` `[defer]` (intent) carried — Pre-warm meets the literal reading (7 explosions at x −1000) but may not warm shaders — already in `deferred`; not added again.
  - `[low]` `[reject]` (intent) Small departures from the letter (`_enter_tree` registration, public `tier_row()`, Audio empty-pool guard, `spawn_explosion` error branch) — all compatible with the intent and harmless.
  - `[false]` `[reject]` (intent) "calls only `Feedback.impact`" could mean one call per visible hit — the intent says every death *and* every projectile impact calls it, and Design Notes state the double feedback is intended.
  - `[false]` `[reject]` (intent) `sprint-status.yaml` is modified in the working tree — that is the orchestrator's own bookkeeping, outside this diff; this run did not write it.

## Design Notes

**Hit-stop (longest remaining wins, no stacking).** A serial number makes stale timers harmless; the end time decides whether a new stop extends the freeze:

```gdscript
func hit_stop(ms: float) -> void:
	if ms <= 0.0:
		return
	var end_usec: int = Time.get_ticks_usec() + int(ms * 1000.0)
	if end_usec <= _hit_stop_end_usec:
		return
	_hit_stop_end_usec = end_usec
	_hit_stop_serial += 1
	Engine.time_scale = 0.0
	get_tree().create_timer(ms / 1000.0, true, false, true).timeout.connect(_end_hit_stop.bind(_hit_stop_serial))
```

`_end_hit_stop(serial)` returns unless `serial == _hit_stop_serial`, then sets `_hit_stop_end_usec = 0` and `time_scale = 1.0`. Tests await real time with `get_tree().create_timer(t, true, false, true)` (scaled timers freeze at `time_scale` 0) and use wide margins (≥ 30 ms) to stay non-flaky.

**Why Spawner registers with Feedback:** only Spawner may instantiate, and autoloads may not find scene nodes by path, so the level's Spawner registers itself, like the camera. Spark, debris and shockwave are child nodes of one explosion scene (not separate scenes, as the architecture's folder sketch lists) to keep the single-instantiation rule.

**Double feedback is intended:** a laser bolt that kills a Wasp produces its Small impact and the Wasp's Small death; a missile that kills a medium asteroid produces two Medium impacts. Shake keeps the strongest; hit-stops don't stack.

## Verification

**Commands:**
- `uv run python tools/gen_placeholder_sfx.py` -- expected: 5 WAVs written.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all pass, exit 0.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --quit-after 120` -- expected: exit 0, no `SCRIPT ERROR`.
- `git grep -nI -i -e "users[/\\]" -e "c:[/\\]godot"` -- expected: no new matches.

**Manual checks:**
- How explosions, shake, hit-stop and the placeholder sounds look and feel is a human playtest item (Story 1.7 fun gate). Do not claim it verified.

## Auto Run Result

Status: done

**Summary:** Story 1.6 was already implemented and reviewed once (commit `2f591ec56e1694525e12a8fe21bb01fb1a9696e2`). Every Wasp death, asteroid destruction and projectile impact calls only `Feedback.impact(tier, position)`. That one call spawns the tier's explosion through the Spawner, shakes the `ShakeCamera`, applies hit-stop (only `Feedback` writes `Engine.time_scale`) and plays the tier's SFX through the new `Audio` autoload. Weapons play a zap or thump, the missile shows a muzzle flash, and the sandbox pre-warms one explosion per tier. This follow-up review pass changed only tests: it closed three verification gaps and brought the tests in line with the spec's `Feedback.reset()` rule.

**Files changed (this pass):**
- `game/tests/unit/test_shake_camera.gd` -- new `test_process_drives_shake` (the real `_process` → `step` loop); registration message now says "on entering the tree".
- `game/tests/unit/test_player_laser.gd` -- new `test_laser_zap_jitter_follows_tuning` (tuning jitter 0 gives pitch exactly 1.0); `Feedback.reset()` in `after_each`.
- `game/tests/unit/test_player_missile.gd` -- the non-positive cooldown test also checks the thump and flash on every press; `Feedback.reset()` in `after_each`.
- `game/tests/unit/test_enemy.gd`, `test_asteroid.gd`, `test_missile.gd`, `test_projectile.gd` -- `after_each` calling `Feedback.reset()`.
- This spec -- follow-up triage log, two new `deferred` items, this result.

**Files changed (whole story, from the first pass):** `game/autoloads/feedback.gd`, `audio.gd`, `game/default_bus_layout.tres`, `game/systems/camera/shake_camera.gd`, `game/entities/effects/explosion.gd`/`.tscn`, `shockwave_ring.gd`, `game/core/impact_tier.gd`, `spawner.gd`, `enemy.gd`, `projectile.gd`, `game/autoloads/entity_registry.gd`, `game/entities/asteroids/asteroid.gd`, `game/entities/projectiles/missile.gd`, `game/entities/player/player.gd`, `game/scenes/sandbox/sandbox.gd`/`.tscn`, `game/project.godot`, `game/data/tuning.json` (+ decision-log row 26), `tools/gen_placeholder_sfx.py`, `game/assets/audio/sfx/*`, `game/assets/CREDITS.md`, and their tests.

**Review findings (follow-up pass):** 26 total -- high 0, medium 2, low 17, false 4, maybe-false 3.
- **Patched (7 rows, 5 fixes):** ShakeCamera `_process` wiring test (medium); laser jitter pinned to tuning, non-positive cooldown thump and flash, `Feedback.reset()` in every impact-triggering test file, and the stale "_ready" test message (two rows) (all low).
- **Deferred (2 new):** no cap on live explosions (medium, unverified; settle with the Story 1.7 stress test); a fresh clone needs `--import` before GUT (medium; pre-existing, fix belongs in AGENTS.md). The pre-warm culling item is carried, not added again.
- **Rejected (17):**
  - Spec-mandated or feel items for the Story 1.7 playtest: debris colour per tier, shake replace rule, frame-rate shake jitter, first-frame freeze, hit-stop up to a frame early, missile launch during hit-stop.
  - Data misuse: `sfx`/`extras` read with `.get()`.
  - Deliberate or low-value test choices: tests pinning tuning values, `pending` slow-frame guards, no tests for silent exits, no end-to-end input-to-impact test.
  - Owner decision: CREDITS licence (the repo has no LICENSE yet).
  - Harmless departures from the letter of the spec.
  - Four `false`: the warn-once test state, object-state-only tests (carried), the double-feedback reading, and the orchestrator's `sprint-status.yaml` edit.
  - Each reason is in the triage log.

**Follow-up review recommendation:** false. This was a follow-up pass and it patched no `high` (patched by verdict: medium 1, low 4 fixes / 6 rows).

**Verification:**
- GUT headless (`--headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`): 240/240 passing, 1456 asserts, exit 0, 0 `SCRIPT ERROR`.
- `--headless --path game --quit-after 120`: exit 0, 0 `SCRIPT ERROR`.
- Fresh-clone check: `git archive` copies of HEAD and of baseline `01325de` both fail GUT without `--import` (pre-existing, deferred); after `--import`, HEAD passes 240/240.
- `Engine.time_scale` assignments: only `game/autoloads/feedback.gd`. `instantiate()` outside addons and tests: only `game/core/spawner.gd`.
- Sensitive-data scan of the staged diff: no matches.

**Residual risks:**
- How the explosions, shake, hit-stop and placeholder sounds look, sound and feel is unverified. It needs a human playtest at the Story 1.7 fun gate.
- The pre-warm may not warm shaders, and there is no cap on live explosions (both deferred to Story 1.7 measurements).
- A fresh clone must run `--import` before the test command (deferred AGENTS.md fix).
- A hit-stop can end up to one frame early. Laser and missile SFX play at 0 dB. The shake jitters the aim slightly. The boss and player tiers have no sounds yet. The placeholder SFX are generated, not Kenney.
