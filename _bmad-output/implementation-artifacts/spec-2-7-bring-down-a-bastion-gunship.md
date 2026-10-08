---
title: 'Story 2.7: Bring Down a Bastion Gunship'
type: 'feature'
created: '2026-10-07'
baseline_revision: '5defea66827e6fcdeb68fb6ec67e76f27298178b'
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

**Problem:** There is no Bastion. The GDD Bastion (FR22, FR25, FR30; gdd.md L269) is a large, 40 HP tank that drifts at 60 px/s within y 80–400, has 2 turrets that each glow 0.5 s and then fire a 3-bullet ±15° spread at 350 px/s, plays the Large feedback tier on death, and is never destroyed by contact.

**Approach:** Add `Bastion` (`class_name`, extends `Enemy`, `enum State { ENTER, DRIFT, TELEGRAPH }`, Lancer pattern) with two `Turret` markers that each fire a spread of the shared `enemy_bullet`. Make the base `Enemy.destroy_by_contact()` ignore large enemies. Register it, add a Bastion wave to `level_dev.json`, and extend the data tests.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript. `_state` is assigned only inside `_enter_state()`. `_physics_process(delta)` only calls a public `step(delta)` holding the `match`. No per-frame allocation, group lookup or logging.
- Numbers from `Config`, read once in `_ready`: `enemies.bastion.drift_speed_px_s` (60), `band_y.min`/`max` (80/400), `turrets` (2), `spread_bullets` (3), `spread_deg` (15), `fire_interval_s` (2.5), `bullet_speed_px_s` (350), `telegraph_s` (0.5); bullet damage `damage.bullet_hearts`. One new key: `turret_glow_energy` 2.5 (HDR glow, Lancer `muzzle_glow_energy` precedent).
- Drift box: x in `[half, width − half]`, y in `[band_y.min + half, band_y.max − half]` (`half = sprite_px / 2`), so the whole hull stays inside y 80–400. If the band is shorter than the hull, y min = max = band centre.
- `sprite_px` 160. Slot (from `setup`) is clamped into the drift box (one `Log.warn("spawn", …)` if it moved). Entry `"top"` starts at `(slot.x, −half)`, `"sides"` at `(−half, slot.y)` or `(width + half, slot.y)` from the nearer side (x ≤ width/2 → left), other values → WARN and top. ENTER moves to the slot at `drift_speed_px_s`, then DRIFT. Without a `slot` it starts in DRIFT at its spawn position (no clamp, no WARN).
- DRIFT and TELEGRAPH both move toward a drift target at `drift_speed_px_s`; on reaching it, a new target is picked uniformly in the drift box with `var rng: RandomNumberGenerator` (tests seed it). The first target is picked on entering DRIFT from ENTER (or `_ready` when slotless).
- Cadence (Lancer precedent): after `fire_interval_s` in DRIFT → TELEGRAPH (every turret's `Glow` visible); after `telegraph_s` every turret fires, then DRIFT (glows hidden). The fire timer does not run in ENTER.
- Each turret fires `spread_bullets` `enemy_bullet`s from its own `global_position` via `spawner.spawn_projectile`, velocity `Vector2.DOWN.rotated(deg_to_rad(a)) × bullet_speed_px_s` with `a` evenly spaced from `−spread_deg` to `+spread_deg` (one bullet → 0°). Turrets are the children of `Turrets`; if their count differs from tuning `turrets`, one WARN and use the scene's turrets. No valid spawner → no shot, one `Log.debug("spawn", …)` per Bastion.
- `Enemy.destroy_by_contact()` does nothing unless `tier` is `SMALL` or `MEDIUM` (architecture: small and medium only).

**Never:**
- No aiming at the player or convoy (the spread is centred straight down), no stagger between turrets, no contact damage to the player (Epic 3), no drops (Epic 4), no turret HP. No changes to `WaveDirector`, `Formation`, `Events`, `Projectile`, `EnemyBullet`, `Feedback`, the sandbox, the bench or `sprint-status.yaml`. No new art files: polygons and gradient textures inside the `.tscn`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Top entry | slot (960,160), entry top | starts (960,−80), ENTER at 60 px/s to (960,160), then DRIFT | — |
| Side entry | slot (400,200) / (1500,200), entry sides | starts (−80,200) / (2000,200) | — |
| Clamp | slot (960,400); slot x 10 | slot (960,320); x 80 | WARN each |
| Unknown entry | entry "spiral" | top entry | WARN |
| Drift | DRIFT, seeded rng, 60 s of steps | always inside the drift box; speed ≤ 60 px/s per step; reaches several targets | — |
| Telegraph + fire | 2.5 s in DRIFT, then 0.5 s | both glows visible during TELEGRAPH; then 6 `enemy_bullet`s (3 per turret) at 350 px/s, angles −15°, 0°, +15° from down, each from its turret; glows hidden | — |
| No spawner | created without Spawner | cycle runs, no bullet, no crash | DEBUG once |
| Death | 40 damage | one `resolved`, one `enemy_killed`, Large tier (hit-stop running) | — |
| Contact | `destroy_by_contact()` on Bastion; on Wasp | Bastion alive, HP 40, no `resolved`; Wasp dies | — |
| Pause | tree paused | Bastion frozen | — |

</intent-contract>

## Code Map

- `game/entities/enemies/lancer/lancer.gd` + `.tscn` -- the pattern to mirror: `setup` (slot/entry), `_ready` (super first, then tuning, `self_modulate` glow energy), `step`, `_enter_state` toggling glows, entry WARN text, `_fire` via `spawner` with `_warned_no_spawner`, accessors. Scene: `Area2D` layer 4 mask 0 `monitoring = false`, `Hitbox`, `Hull` Polygon2D in `enemy` #FF2BD6, additive `GradientTexture2D` glow sprite (copy its sub-resources for each turret `Glow`).
- `game/entities/enemies/needle/needle.gd` -- `var rng: RandomNumberGenerator` usage for seeded random picks.
- `game/core/enemy.gd` -- `destroy_by_contact()` L59: add the tier guard. `_die` already calls `Feedback.impact(tier, …)`; tier comes from `enemies.bastion.tier` = `large`. `ImpactTier` enum in `game/core/impact_tier.gd`.
- `game/autoloads/entity_registry.gd` -- add `&"bastion"` to `ENEMIES`; `enemy_bullet` already registered.
- `game/autoloads/feedback.gd` -- `is_hit_stopped()` is true after a LARGE impact (hit_stop 40 ms; MEDIUM is 0). Read-only.
- `game/systems/waves/wave_director.gd` `_spawn_entry` L225 -- passes `position`, `slot`, `formation`, `entry`. Read-only. Slots start at `waves.formation.top_y` 160, rows 120 apart.
- `game/data/tuning.json` `enemies.bastion` L103 -- all keys exist except `turret_glow_energy`.
- `game/data/levels/level_dev.json` -- append wave 5: `spawns` `[{bastion, 1, grid_1x1, top}, {wasp, 6, grid_3x2, top}]` (Bastion first so its slot is row 0, y 160 = drift box top, no clamp WARN; Wasps rows 1–2 inside their zone), `asteroids` `[]`, `triggers` `[{ "when": "wave_clear", "actions": [ { "wait": 0.5 } ] }]`.
- `game/tests/unit/test_lancer.gd`, `test_needle.gd` -- test style: `_make`, manual `step`, `_make_world` with a real `Spawner`, `Log.sink` capture, `Config.load_data()`/`Feedback.reset()`/`PauseArbiter.clear()` in `after_each`, source check for `_state =`.
- `game/tests/unit/test_enemy.gd` L100 -- `test_destroy_by_contact` (Wasp) stays green.
- `game/tests/unit/test_level.gd` -- `wave_count() == 4` L139 and `for wave: int in 4` L215 become 5; `test_dev_wave_4_has_needles_and_cover` L262 is the template for wave 5.
- `game/tests/unit/test_config.gd` `test_level_dev_loads` L437 -- 4 waves → 5.
- `game/tests/unit/test_spawner.gd` L54 -- template for a registry test.
- `game/tests/data/test_data_files.gd` -- telegraph and bullet-speed walks already cover `enemies.bastion`; `ENEMY_ZONE_BOTTOM_Y` 432 and the `test_needle_tuning_ranges` probe pattern are reused.
- New `class_name` `Bastion` needs `--import`; commit the new `.gd.uid`.

## Tasks & Acceptance

**Execution (write each test first, red, then the code):**
- `game/data/tuning.json` -- add `turret_glow_energy` 2.5 to `enemies.bastion`.
- `game/core/enemy.gd` -- `destroy_by_contact()` returns early for tiers other than SMALL/MEDIUM; update its doc comment.
- `game/entities/enemies/bastion/bastion.gd` + `.tscn` -- `class_name Bastion extends Enemy` per the Always rules; a wide, distinct, armoured `Hull` (≈160×110) in `enemy` colour; `Turrets` Node2D with `Turret0` (−44, 40) and `Turret1` (44, 40) Marker2Ds, each with a hidden additive `Glow` Sprite2D. Accessors `state()`, `formation_slot()`, `drift_target()`, `drift_box() -> Rect2`, `turret_count()`, `is_glowing()` (true when every turret glow is visible).
- `game/autoloads/entity_registry.gd` -- register `bastion`.
- `game/data/levels/level_dev.json` -- wave 5.
- `game/tests/unit/test_bastion.gd` -- every matrix row; tuning reads (change a value in `Config.tuning`, restore with `Config.load_data()`); `_state =` occurs exactly once in the source; HP 40, LARGE tier, hitbox radius `160/2 × hitbox_ratio`; scene turret count equals tuning `turrets`; shots through a real `Spawner` are `EnemyBullet`s with the right speed, angles and origins.
- `game/tests/unit/test_enemy.gd` -- a medium enemy (Lancer) is still destroyed by contact.
- `game/tests/unit/test_spawner.gd` -- registry has `bastion`.
- `game/tests/unit/test_level.gd`, `test_config.gd` -- the 4 → 5 updates; wave 5 has one counted Bastion in `World/Enemies` with the level Spawner injected.
- `game/tests/data/test_data_files.gd` -- `test_bastion_tuning_ranges`: speeds > 0, `fire_interval_s` > 0, `turrets` ≥ 1, `spread_bullets` ≥ 1, 0 ≤ `spread_deg` < 90, `turret_glow_energy` > 1, `band_y.min` < `band_y.max`, the hull (probe `sprite_px`) fits: `band_y.min` ≥ 0, `band_y.max` ≤ `ENEMY_ZONE_BOTTOM_Y`, `band_y.max − band_y.min` ≥ `sprite_px`.
- `_bmad-output/game-architecture.md` -- a short "As-built 2026-10-07 (Story 2.7)" note: Bastion states and cadence, drift box, unaimed spread, the contact guard in `Enemy`, the new key.
- Run `--import`, then the full GUT suite.

**Acceptance Criteria:**
- Given a level wave with a Bastion entry, when it spawns, then the Bastion (40 HP, large tier) enters and drifts at 60 px/s with its whole hull inside y 80–400, above the player zone.
- Given an active Bastion, when each turret's 2.5 s timer is reached, then the turret glows for 0.5 s and then fires a 3-bullet ±15° spread of `enemy_bullet` at 350 px/s.
- Given a Bastion at 0 HP, when it dies, then it plays the Large feedback tier and resolves once.
- Given a Bastion, when `destroy_by_contact()` is called, then it is not destroyed.
- Given the headless GUT suite, when it runs, then the new tests pass and no previously passing test fails.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 26 findings — high 0, medium 0, low 17, false 9, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: the spec is missing from the diff — excluded on purpose (it goes to the edge-case layer only) and is committed with the story.
  - `[low]` `[reject]` Blind: the circular hitbox (r 64) misses the outer 16 px of the 160 px wings and pokes past the 107 px hull vertically — the `sprite_px/2 × hitbox_ratio` circle is the base `Enemy` convention for every enemy (GDD ≈ 80% hitbox); changing the shape means a base-class change, not a direct fix.
  - `[low]` `[patch]` Blind: the drift box uses the 160 px `sprite_px`, ~25 px tighter than the drawn 107 px hull, and the as-built note says "160 px hull" — the box is the spec's conservative rule (kept); the as-built note was corrected to say the 160 px sprite box stays inside y 80–400 with the ~160×107 hull inside it.
  - `[low]` `[reject]` Blind: a turret without a `Glow` child fires untelegraphed with no WARN — only a malformed scene reaches this; the shipped scene has both glows and `test_hp_tier_and_scene` pins them; a guard adds a branch.
  - `[low]` `[reject]` Blind: in wave 5 the Bastion's drift box (centre y ≤ 320) overlaps the Wasp rows at y 280/400 — enemies don't collide and enemy shots don't mask enemies, so the overlap is cosmetic dev data (Story 2.6 overlap precedent); real layouts are Epic 7.
  - `[low]` `[reject]` Blind: no data test checks that every level's Bastion slot falls inside the drift box — a misplaced slot is clamped with a WARN at runtime; a new level walk is new complexity for Epic 7 authoring.
  - `[low]` `[reject]` Blind: `test_bastion_tuning_ranges` checks `band_y.min >= 0`, not the wave bar's bottom, and doesn't check `telegraph_s` — the telegraph part is false (`test_every_telegraph_meets_the_minimum` already asserts `enemies.bastion.telegraph_s >= 0.3`); the shipped 80 is below the wave bar and the bound is the spec's.
  - `[low]` `[patch]` Blind: `test_cycle_repeats_every_interval_plus_telegraph` only counts 18 bullets in 9.5 s, so a 2.5 s period would pass — grouped with the verification-gap row; the test now asserts the second DRIFT→TELEGRAPH takes `fire_interval_s` (2.5 s), pinning the 3.0 s volley spacing.
  - `[low]` `[reject]` Blind: a slotless Bastion spawned in the player zone fires from there — slotless Bastions exist only in tests and the sandbox (which spawns none); Lancer/Needle precedent.
  - `[low]` `[reject]` Blind: side-entry coverage is thin (right-side arrival, x = width/2 tie-break, sides + clamped slot) — every branch shares the left-side `move_toward` path that is tested; the start positions are asserted; unlikely to hide a defect.
  - `[false]` `[reject]` Edge: `drift_speed_px_s` ≤ 0 freezes the Bastion in ENTER — `test_bastion_tuning_ranges` asserts it is > 0.
  - `[false]` `[reject]` Edge: `fire_interval_s` or `telegraph_s` ≤ 0 floods bullets — the data tests assert `fire_interval_s > 0` and `telegraph_s >= 0.3`.
  - `[false]` `[reject]` Edge: the data test misses a bad `telegraph_s` — `test_every_telegraph_meets_the_minimum` covers `enemies.bastion.telegraph_s`.
  - `[low]` `[reject]` Edge: a Bastion killed earlier in the same physics frame can still fire a volley — needs the kill on the exact tick the telegraph ends; same unguarded `step` as the Lancer and Needle (accepted precedent).
  - `[low]` `[reject]` Edge: a turret without a `Glow` fires with no telegraph — same root cause as the Blind turret-glow row; rejected with it.
  - `[false]` `[reject]` Edge: `spread_bullets` ≤ 0 makes turrets glow but never fire — `test_bastion_tuning_ranges` asserts `spread_bullets >= 1`.
  - `[low]` `[reject]` Edge: a slotless Bastion outside the box fires from the player zone — same claim as the Blind slotless row; rejected with it.
  - `[low]` `[reject]` Edge: the 160 px hull overlaps Wasps in wave 5 — same claim as the Blind wave-5 row; rejected with it.
  - `[low]` `[reject]` Edge: `is_glowing()` skips a turret without a `Glow`, so it can report true — same root cause as the Blind turret-glow row; rejected with it.
  - `[low]` `[patch]` Verification gap: the 3.0 s repeat cadence is not pinned (a 2.5 s period still gives 18 bullets in 9.5 s) — patched as in the Blind cadence row.
  - `[false]` `[reject]` Verification gap (other): `destroy_by_contact()` has no runtime caller yet — no bad outcome; player contact arrives in Epic 3 (the spec's Never), and the guard is proven by direct calls on Bastion, Wasp and Lancer.
  - `[false]` `[reject]` Intent: one shared timer instead of one per turret — with no stagger, two timers started together are observably identical; the GDD gives a stagger only to the Flagship.
  - `[low]` `[reject]` Intent: the period is 3.0 s (2.5 s timer + 0.5 s glow), while the GDD says "every 2.5 s" — this follows the AC's sequence and the accepted Lancer precedent; changing it means editing this build's spec; listed as a designer call.
  - `[false]` `[reject]` Intent: the Large tier is only checked through the hit-stop — the Bastion's tier is asserted LARGE, `_die` passes it to `Feedback.impact`, and `test_feedback` pins the LARGE row (2×, 8 px / 0.25 s, 40 ms, debris and shockwave).
  - `[false]` `[reject]` Intent: no player-collision path exercises the contact guard — same as the verification-gap "other" row; Epic 3 owns contact.
  - `[low]` `[reject]` Intent: the drift band is proven through `step()`, not a running level — `_physics_process` only calls `step`, and pause is tested on the real tree (Lancer/Needle precedent).

### 2026-10-07 — Review pass
Follow-up review pass on the `done` spec.
- verdicts: 26 findings — high 0, medium 0, low 15, false 11, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: the volley period is 3.0 s, not the GDD's "every 2.5 s", and the Needle counts its telegraph inside `fire_interval_s` — carried: same claim as the earlier Intent cadence row. This is the spec's Lancer-precedent decision (Design Notes, and the as-built note states the 3.0 s period). Changing it means editing this build's spec; it stays a designer call.
  - `[low]` `[reject]` Blind: a slotless Bastion keeps its spawn position and can fire from the player zone — carried: same as the earlier slotless row (only tests and the sandbox spawn slotless Bastions; the sandbox spawns none).
  - `[low]` `[reject]` Blind: ENTER uses `drift_speed_px_s`, so a side entry to a centre slot takes about 17 s with no fire — real, but the intent's Always rule says ENTER moves at `drift_speed_px_s`, so the fix (a new `entry_speed_px_s` key) edits this build's spec. The only shipped Bastion entry is top (240 px, 4 s).
  - `[low]` `[reject]` Blind: the circular 64 px hitbox doesn't match the 160×107 hull, and the drift box uses `sprite_px` — carried: same as the earlier hitbox and drift-box rows (base `Enemy` convention; the box is the spec's rule).
  - `[false]` `[reject]` Blind: large-tier contact now does nothing, and a future contact handler could hit the player every frame — carried: same as the earlier "no runtime caller" row; Epic 3 owns player contact damage (the spec's Never), and no handler exists that could repeat the hit.
  - `[low]` `[patch]` Blind: the turrets have no shape of their own, so they can't be seen between telegraphs (the markers sit inside the hull leg, and only the hidden `Glow` marks them) — fixed: added a `Barrel` Polygon2D (plating colour #731361, 18×22 px, barrel pointing down) under each `Turrets/TurretN` marker, ahead of `Glow` so the additive glow draws on top. `turret_count()` and the glow lookup are unaffected; the suite passes.
  - `[false]` `[reject]` Blind: the data test misses `telegraph_s` — carried: `test_every_telegraph_meets_the_minimum` asserts `enemies.bastion.telegraph_s >= 0.3`.
  - `[low]` `[reject]` Blind: in wave 5 the Bastion's drift box overlaps the Wasp rows — carried: same as the earlier wave-5 overlap row.
  - `[low]` `[reject]` Blind: `test_dev_wave_5_has_a_bastion` waits in real time and the pause test uses `wait_physics_frames(10)`, so they are slow and could be flaky — real (slower than needed), but it's the same `wait_seconds(0.1)` loop as the wave 1–4 tests and the Lancer/Needle pause tests, and the suite passed (34 s). The fix is a test-harness refactor, not a direct correction.
  - `[false]` `[reject]` Blind: the unaimed-spread test doesn't prove "never aimed" (no convoy, no player directly below) — `_spread_velocities` are built once in `_ready` from `Vector2.DOWN` with no target input (bastion.gd L179–185), and the tests assert the exact −15°/0°/+15° angles, so any aiming would fail them.
  - `[false]` `[reject]` Edge: `drift_speed_px_s` ≤ 0 traps the Bastion off-screen — carried: `test_bastion_tuning_ranges` asserts the speed is > 0.
  - `[false]` `[reject]` Edge: `fire_interval_s`/`telegraph_s` ≤ 0 floods bullets — carried: the data tests assert `fire_interval_s > 0` and `telegraph_s >= 0.3`.
  - `[false]` `[reject]` Edge: `telegraph_s` is not range-checked — carried: `test_every_telegraph_meets_the_minimum` covers it.
  - `[low]` `[reject]` Edge: the wave-5 drift box contains the Wasp row-1 slots — carried: same as the earlier wave-5 overlap row.
  - `[low]` `[reject]` Edge: a slotless spawn position is not clamped — carried: same as the earlier slotless row.
  - `[low]` `[reject]` Edge: `step()` can fire a volley on the tick the Bastion dies — carried: same as the earlier same-tick row (Lancer/Needle precedent).
  - `[low]` `[reject]` Edge: the timer reset gives a 3.0 s period, not 2.5 s — carried: same as the earlier cadence row.
  - `[false]` `[reject]` Verification gap (other): no game code calls `destroy_by_contact()` — carried: no bad outcome; Epic 3 adds the caller, and the guard is tested on all three tiers.
  - `[false]` `[reject]` Intent: only the method-level contact guard is tested, not a real collision — carried: same as the earlier player-collision row.
  - `[low]` `[reject]` Intent: the cadence follows the Lancer reading (3.0 s), not the plain GDD reading — carried: same as the earlier cadence row.
  - `[low]` `[reject]` Intent: no test checks the drawn hull polygon (or entry/slotless positions) against the band — the polygon's bounds (x ±80, y −55..52) sit inside the 160 px `sprite_px` box by inspection, and the matrix allows entry and slotless positions outside the band. A polygon-bounds test adds new machinery for a static scene value.
  - `[false]` `[reject]` Intent: the full Large effect (shake, debris, shockwave, sound) isn't tested for a Bastion death — carried: same as the earlier Large-tier row (`tier` asserted LARGE; `test_feedback` pins the LARGE row).
  - `[low]` `[reject]` Intent: the HDR turret glow is only tested as `self_modulate`, not as visible bloom — bloom can't be observed headless; this is the Lancer `muzzle_glow_energy` precedent, and the look is left to a human playtest.
  - `[false]` `[reject]` Intent: "no per-frame allocation" isn't enforced by a test — `step`, `_drift` and `_enter_state` allocate nothing (bastion.gd L113–128, L164–176, L217–220). The only allocation is the params dictionary per bullet in `_fire`, once per volley.
  - `[low]` `[reject]` Intent: nothing checks where the Bastion sits relative to the six Wasp slots — carried: same as the earlier wave-5 overlap row.
  - `[false]` `[reject]` Intent: the diff touches files outside the Approach list (architecture note, `test_config.gd`, `test_level.gd`) — the spec's Tasks list each of these, and none is on the Never list.

## Design Notes

**Band.** "Within y 80–400" is applied to the whole hull, not just its centre. This meets the GDD wording under either reading, keeps the hull below the y 40 wave bar and above the player zone (y 432), and settles DW-34 without changing a number.

**Spread direction.** The GDD calls only the Flagship's desperate spread "aimed", so the Bastion spread is centred straight down. Bastions "never aim at the convoy" (gdd.md L212) by construction.

**Cadence.** As with the Lancer, the AC reads "timer reaches 2.5 s → glow 0.5 s → fire", so the shot period is 3.0 s. Both turrets share the timer; the GDD gives a stagger only to the Flagship.

**Contact.** The guard lives in `Enemy` so the Flagship parts and any later large enemy inherit it; Epic 3 adds the player's contact damage.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0; class cache has `Bastion`.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all new tests pass; only the pre-existing deferred `test_wave_director.test_f3_resolves_the_wave_and_fires_pending_triggers_in_order` failure (DW-35/36) may remain.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --quit-after 600` -- expected: no ERROR or WARN lines.


## Auto Run Result

Status: done

**Summary:** This was a follow-up review pass on Story 2.7, the Bastion gunship. The shipped behaviour is as before:
- A Bastion has 40 HP and the large tier. It enters at 60 px/s, then drifts at 60 px/s inside a drift box that keeps its whole 160 px sprite inside y 80–400.
- After every 2.5 s of drifting, both turret glows show for 0.5 s. Then each turret fires a 3-bullet `enemy_bullet` spread at 350 px/s, at −15°, 0° and +15° from straight down.
- Death plays the Large feedback tier.
- `Enemy.destroy_by_contact()` ignores every tier except small and medium.
- `level_dev.json` has wave 5.

This pass fixed one problem: each turret now has a visible barrel, so players can see where the spreads come from between telegraphs.

**Files changed (since `5defea66827e6fcdeb68fb6ec67e76f27298178b`):**
- `game/entities/enemies/bastion/bastion.gd` + `.tscn` (+ `.uid`): the `Bastion` state machine, the drift box, the turrets with their glows, and the hull. This pass added a `Barrel` polygon under each turret.
- `game/core/enemy.gd`: the contact guard (small and medium only).
- `game/autoloads/entity_registry.gd`: registers `bastion`.
- `game/data/tuning.json`: adds `enemies.bastion.turret_glow_energy` (2.5).
- `game/data/levels/level_dev.json`: wave 5 (1 Bastion, 6 Wasps).
- `game/tests/unit/test_bastion.gd` (+ `.uid`): every matrix row, the tuning reads and the cadence.
- `game/tests/unit/test_enemy.gd`, `test_spawner.gd`, `test_level.gd`, `test_config.gd`, `game/tests/data/test_data_files.gd`: a medium enemy still dies by contact, the registry, the 5-wave dev level, and `test_bastion_tuning_ranges`.
- `_bmad-output/game-architecture.md`: the "As-built 2026-10-07 (Story 2.7)" note.

**Review findings (this pass):** 26 in total: high 0, medium 0, low 15, false 11, maybe-false 0. 19 rows repeat earlier rows and keep their verdicts.
- **Patched:** 1 low entry. The turrets had no shape of their own, so a `Barrel` polygon was added under each turret.
- **Deferred:** none.
- **Rejected lows:**
  - Side entries are slow because ENTER uses the drift speed. The spec's Always rule sets this, and the only shipped Bastion entry is from the top.
  - The wave-5 test and the pause test wait in real time. They follow the existing test pattern and the suite passed.
  - No test checks the hull polygon against the band. By inspection the polygon sits inside the `sprite_px` box.
  - The HDR glow is only checked through `self_modulate`. Bloom can't be seen headless (Lancer precedent).
  - Repeated from the first pass: the 3.0 s period, slotless spawns, the hitbox shape, the wave-5 overlap with the Wasps, and a volley on the tick of death.
- **Rejected as false:**
  - The unaimed-spread test is too weak. The exact spread angles are asserted, and no target is ever read.
  - Per-frame allocation is not enforced by a test. None happens.
  - Files outside the Approach list. The Tasks list every one of them.
  - Repeated from the first pass: zero or negative tuning values, `telegraph_s` coverage, the contact caller, and the Large-tier coverage.
- **Follow-up review recommended: false.** This is a follow-up pass and it patched no high entry: 0 high, 0 medium, 1 low.

**Verification:**
- `--import` exited 0.
- Full GUT suite after the patch: 43 scripts, 587/587 tests passed (5655 asserts).
- `--headless --quit-after 600` printed no ERROR or WARN lines. That run only covers wave 1.

**Residual risks:**
- Nobody has played wave 5. The Bastion's look, including the new barrels, the turret-glow readability and the Large-tier feel all need a human playtest. No feel or fun claim is made.
- Designer calls carried over:
  - the 3.0 s volley period (the GDD says "every 2.5 s");
  - no stagger between turrets;
  - `turret_glow_energy` is not in the decision log;
  - ENTER uses `drift_speed_px_s`, so side entries to centre slots are slow (about 17 s).
- `sprint-status.yaml` belongs to the orchestrator. It was left untouched and uncommitted.
