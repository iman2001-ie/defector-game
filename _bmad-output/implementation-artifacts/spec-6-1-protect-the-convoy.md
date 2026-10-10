---
title: 'Story 6.1: Protect the Convoy'
type: 'feature'
created: '2026-10-10'
status: 'done'
baseline_revision: '450828cc3c060360890d95acfd95f6af39349955'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-6-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/EXPERIENCE.md'
warnings: ['oversized']
deferred:
  - summary: >-
      The Player's 64 px hull circle fits through the 72 px hitbox pocket between the flankers' front edges and the lead's rear edge, so the ship can slip vertically through the triangle.
    evidence: |-
      Hitbox centres are 200 px apart in x (160 + 40 gap) and the hitboxes are 128 px wide, leaving 72 px; resolve_hull uses the hitbox rects (as the spec and the AC's HullArea-vs-convoy-layer mechanism prescribe). Whether slipping between formation ships is unwanted is not settled by GDD #25 (which forbids passing through hulls, not between them). Settle by an operator playtest of dev_convoy; if unwanted, close the pocket (resolve against drawn extents or add a gap rect).
    location: >-
      game/entities/player/player.gd resolve_hull / game/entities/allies/convoy.gd ship_centre
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** Level 1 is an escort mission (FR32, FR33 loss, FR7, FR62 convoy bar), but no convoy exists. The scaffolding is in place (the `CONVOY`/`ALLIES` layers, `Events.convoy_hp_changed`, `level_failed(&"convoy")`, the retry prompt's `CONVOY LOST`, `World/Allies`, `tuning.convoy.*`, `player.hull_diameter_px`). Three open deferred items block it. DW-32: player shots would damage a convoy. DW-33: a missile stopped by the convoy still splashes (ruled: fizzle, GDD #46). DW-75: a convoy loss could fail a level that has already cleared.

**Approach:** A level JSON with `"convoy": true` makes the Level spawn a `Convoy` through the Spawner into `World/Allies`. The Convoy is three `ConvoyShip` areas in a triangle that ping-pong across the band (GDD #45), plus one shared HP pool that it broadcasts and that fails the level at 0. Player shots are blocked with no damage; missiles fizzle. The Player's ship is swept against and pushed out of the hulls, with the cursor following it. A HUD convoy bar reads only `Events`.

## Boundaries & Constraints

**Always:**
- Every number comes from `tuning.json` through `Config`. Use the existing `convoy.*`, `player.hull_diameter_px` and `damage.*` keys; new HUD numbers go under `hud.convoy_bar`.
- Static typing everywhere. Only `Spawner` instantiates the Convoy (an `EntityRegistry` preload, then `setup(params)`, then `add_child`). The HUD reads only `Events`. The Player makes every gameplay `warp_mouse` call, and only while the mode is `CONFINED_HIDDEN`. Use `CollisionLayers`/`Groups` constants, never literals, in code.
- The first outcome wins: the convoy never emits `level_failed` after `level_cleared` or after another `level_failed`, and it emits its own `level_failed(&"convoy")` exactly once.
- No per-frame allocation in the convoy step or in the Player's hull resolution (cache the hull rects; no group lookups per tick).
- Write the failing GUT test first.

**Never:**
- No Maul (6.2), no Lancer convoy targeting and no aimed/stray damage amounts (6.3), no allies (6.4). Do not change `EnemyBullet`: until 6.3, an enemy shot reaching a convoy ship calls `apply_damage` with its own `damage`.
- Don't put `convoy` in the Player hurtbox's mask (it stays 52), don't change the 24 px hurtbox, and don't turn on the convoy in `level_1/2/3.json` (Epic 7 does that).
- No new image assets: the cargo hulls are drawn in code.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Convoy level start | level JSON `"convoy": true` | One Convoy in `World/Allies`. The group's left edge is at x 0, heading right; `convoy_hp_changed(100, 100)` emitted | — |
| No convoy | `"convoy": false` or key missing | Nothing spawned; convoy bar stays hidden | — |
| Right edge | Group right edge reaches 1920 (sprite extents) | Clamped to the edge, direction flips, triangle mirrored (lead now on the left side, leading) | — |
| Left edge | Heading left, left edge reaches 0 | Same, mirrored back | — |
| Damage | `apply_damage(n, src)` with n > 0, HP > 0 | HP = max(HP − n, 0); `convoy_hp_changed` emitted | n ≤ 0 ignored |
| Loss | HP reaches 0 | `level_failed(&"convoy")` once, then further damage ignored (no events) | — |
| After clear | `level_cleared` then damage | Ignored: no HP change, no events, no failure | — |
| After death | `level_failed(&"hearts")` then convoy hits 0 | Convoy does not emit `level_failed` | — |
| Laser / micro-missile hits hull | player_shots area overlaps ConvoyShip | Shot freed, convoy HP unchanged, `Feedback.impact(SMALL)` at the shot | — |
| Missile hits hull | Enemy within splash radius | No splash on anything, convoy unchanged, SMALL impact (not MEDIUM) | — |
| Enemy shot hits hull | EnemyBullet overlaps ConvoyShip | Convoy loses the bullet's `damage` (interim, see Never) | — |
| Ship flick through hull | prev above the convoy, cursor target below it | Ship stops at the hull side it came from (no tunnelling); cursor warped to the ship | — |
| Ship pushed at screen edge | convoy at x 0, ship squeezed against the left wall | Ship pushed out along y (never left inside a hull) | — |

</intent-contract>

## Code Map

- `game/core/projectile.gd` -- `_on_area_entered` (l.49) calls `apply_damage` when `_can_damage(area)`; base `_can_damage` (l.61) returns true; base `_on_impact` (l.67) plays `impact_tier`. DW-32 and the blocked-shot effect go here.
- `game/entities/projectiles/missile.gd` -- `_on_impact` (l.27) always calls `apply_splash`. DW-33 fizzle goes here.
- `game/entities/projectiles/enemy_bullet.gd` -- overrides `_can_damage` (not asteroids) and `_on_impact` (no-op). Read-only; its override must keep damaging the convoy.
- `game/entities/projectiles/micro_missile.gd`, `laser_bolt.gd` -- use the base hit path; read-only.
- `game/core/spawner.gd` -- add `spawn_convoy(params) -> Convoy` with an optional `Allies` container (same pattern as `_pickups`, l.30).
- `game/autoloads/entity_registry.gd` -- add a `CONVOY` preload.
- `game/core/groups.gd` -- add `CONVOY` (`&"convoy"`), joined by the Convoy node.
- `game/scenes/level/level.gd` -- `_ready` (l.74-84): after `Config.level`, if `data.get("convoy") == true`, spawn the convoy and inject it into the Player (`set_convoy`, like `set_spawner` l.72) before `_director.start_level`.
- `game/scenes/level/level.tscn` -- `World/Allies` exists (l.38); add a `ConvoyBar` Control under `HUD` after `EnergyBar`.
- `game/entities/player/player.gd` -- `step_lock` (l.456) sets the confined point and warps the cursor only when the mouse is outside the zone. Hull resolution and the unified warp go here. `confine` is at l.475.
- `game/entities/player/player.tscn` -- add the `HullArea` child.
- `game/ui/menus/retry_prompt.gd` -- `_on_events_level_failed` (l.125). Add the DW-75 guard.
- `game/systems/waves/wave_director.gd` -- already freezes on any `level_failed` unless the level is done (l.116). Read-only.
- `game/ui/hud/energy_bar.gd` -- the template for the convoy bar (Config layout, Theme type, `_draw`, pausable flash via `_process`).
- `game/ui/theme/defector_theme.tres` -- `EnergyBar/*` entries (l.130-133) are the pattern for the new `ConvoyBar/*` entries. `muted` = `Color(0.576471, 0.654902, 0.760784, 1)`, `danger` = `Color(1, 0.121569, 0.294118, 1)`, `coalition` = `#22E6FF`.
- `game/data/tuning.json` -- `convoy` {hp 100, ships 3, ship_width_px 160, ship_height_px 80, hitbox_ratio 0.8, speed_px_s 40, band_y 760–920, lead_offset_px 40}, `player.hull_diameter_px` 64, `hud.energy_bar` (right_x 1888, y 76, 320×16).
- `game/data/levels/level_dev.json` -- the template for a new `level_dev_convoy.json`. `game/tests/data/test_data_files.gd` validates every level file and forces `convoy:false` only on `level_1..3`.
- `game/tests/unit/test_isolde_beats.gd` -- the pattern for real-`level.tscn` tests with `GameState`/`Config`/`PauseArbiter` reset. `game/tests/fixtures/player_test_base.gd` is the Player fixture; `test_enemy_bullet.gd` l.179 already fakes a convoy-layer target.
- `_bmad-output/game-architecture.md` -- l.89 is stale (the convoy "can be hit only by convoy-targeted Lancer shots and Mauls"; decision #23 says every enemy shot). The as-built sections end at `## As-built 2026-10-08 (Story 5.8)` (l.1791). The built-parts list is at l.574.

## Tasks & Acceptance

**Execution:**
- `game/core/projectile.gd` -- add `static func is_convoy(area: Area2D) -> bool` (layer bit test). Base `_can_damage` returns `not is_convoy(area)` (DW-32). Base `_on_impact` plays `ImpactTier.SMALL` when `is_convoy(area)`, else `impact_tier`. Update the doc comments. -- Player and ally shots never damage the convoy; every blocked shot shows the laser's effect.
- `game/entities/projectiles/missile.gd` -- in `_on_impact`, skip `apply_splash` when `is_convoy(area)` (DW-33, GDD #46). -- Fizzle.
- `game/entities/allies/convoy_ship.gd` + `convoy_ship.tscn` -- `class_name ConvoyShip extends Area2D`: layer CONVOY, mask 0, monitoring off. Its `Hitbox` RectangleShape2D is sized `ship_*_px × hitbox_ratio` in `_ready`. `facing` (+1/−1) is set by the Convoy and redraws a code-drawn hull: a dim `coalition` body with a bright `coalition` outline and the nose toward `facing`, `ship_width_px × ship_height_px`. `apply_damage(amount, source)` forwards to its Convoy. `hull_rect() -> Rect2` is the global hitbox rect. -- One cargo hull.
- `game/entities/allies/convoy.gd` + `convoy.tscn` -- `class_name Convoy extends Node2D`, with children `Lead`, `FlankTop`, `FlankBottom` (ConvoyShip instances). `setup(params)` takes no keys yet. `_ready` reads Config, warns through `Log` if `convoy.ships` ≠ 3, joins `Groups.CONVOY`, sets HP to max and emits `convoy_hp_changed`, and connects `level_cleared`/`level_failed` to an "ended" flag. `_physics_process` advances the span and repositions the ships (layout in Design Notes), refreshing a cached `Array[Rect2]` returned by `hull_rects()`. Pure statics, `step_span(...)` and `ship_centres(...)`, carry the maths. `apply_damage`, `hp()`, `max_hp()` and `is_lost()` per the I/O matrix; log the loss through `Log`. -- The group, its path and its HP.
- `game/autoloads/entity_registry.gd`, `game/core/spawner.gd`, `game/core/groups.gd` -- the `CONVOY` preload, `spawn_convoy` (an optional `Allies` container; `Log.debug` when missing, return null), and `Groups.CONVOY`. -- Spawner ownership.
- `game/scenes/level/level.gd` -- spawn and inject the convoy when `data.get("convoy") == true`; log the spawn. -- Level wiring.
- `game/entities/player/player.gd` + `player.tscn` -- add a `HullArea` Area2D child (layer 0, mask CONVOY, a CircleShape2D of radius `hull_diameter_px / 2` set in `_ready`). Add `set_convoy(convoy: Convoy)`. Add a pure `static func resolve_hull(from, to, radius, rects, bounds_min, bounds_max) -> Vector2` (Design Notes). In `step_lock`, the final position is `resolve_hull(previous, confined, ...)` when a live convoy is set (skip it on the first lock tick: snap, then push out only). Warp the cursor to the final position whenever it is more than `WARP_EPS_PX` from the mouse and the mode is `CONFINED_HIDDEN` (this also covers today's outside-zone warp). A dead ship does nothing, as now. -- Solid hulls, cursor lock (GDD #25, #29).
- `game/ui/menus/retry_prompt.gd` -- connect `Events.level_cleared`; a `level_failed` after it is ignored (DW-75). -- Belt and braces at the consumer.
- `game/ui/hud/convoy_bar.gd` + `level.tscn` + `defector_theme.tres` + `tuning.json` -- `class_name ConvoyBar extends Control`, pausable, mouse-ignore, hidden until the first `convoy_hp_changed`. Right-aligned to `hud.convoy_bar.right_x` 1888 at `y` 104, `width` 320 × `height` 12. A `coalition` fill on the track. A `CONVOY` label in `muted` at `label_px` 20, right-aligned `label_gap_px` 8 left of the bar. On an HP drop it flashes a `danger` overlay once for `flash_s` 0.3. While HP/max < `low_ratio` 0.3 the label alpha pulses at `pulse_hz` 2. Add `ConvoyBar/colors/{label,danger}` and `ConvoyBar/styles/{track,fill}` to the theme. -- FR62 convoy bar (UX DESIGN/EXPERIENCE).
- `game/data/levels/level_dev_convoy.json` -- `id` 0, name `Development: convoy`, the `level_dev` key set, `"convoy": true`, two short Wasp waves (Lancers optional). -- A playable proof; Epic 7 does Level 1.
- `game/tests/unit/test_convoy.gd`, `test_convoy_bar.gd`, plus additions to `test_projectile.gd`, `test_missile.gd`, `test_micro_missile.gd`, `test_player_movement.gd` (or a new `test_player_convoy.gd`), `test_retry_prompt.gd`, `test_spawner.gd`, `test_level.gd` and `tests/data/test_data_files.gd` -- cover every I/O-matrix row and every AC below. Collision layers and masks are checked against the constants. Run `--import` after adding the `class_name` scripts.
- `_bmad-output/game-architecture.md` -- fix l.89 to decision #23's rule, add the new files to the built-parts list (l.574), and append `## As-built 2026-10-10 (Story 6.1)` (files, data, tests, the dev-level launch line `-- --level=dev_convoy`, the layout and push-out notes). `_bmad-output/implementation-artifacts/deferred-work.md` -- set DW-32, DW-33 and DW-75 to `status: resolved` with a one-line resolution naming Story 6.1. -- Docs match the as-built.

**Acceptance Criteria:**
- Given `level.tscn` running `dev_convoy`, when the level starts, then `World/Allies` holds one Convoy with three ConvoyShips on layer `convoy` (mask 0) in a triangle within y 760–920, moving right at 40 px/s as one group, with every hull fully on-screen and none overlapping the player spawn (960, 900).
- Given the convoy runs for long enough to cross twice (or `step_span` is driven past both edges), when it reaches each edge, then no hull's sprite extent ever leaves x 0–1920, the direction reverses and the lead ship is on the new leading side.
- Given a convoy level, when the HUD starts, then the convoy bar is visible, full, with the `CONVOY` label; given `convoy_hp_changed(60, 100)` after 100, then the fill is 60% and a danger flash runs once; below 30% the label pulses; in a non-convoy level the bar stays hidden.
- Given a convoy level, when a convoy ship takes damage across a wave change, then HP persists (it isn't reset by `wave_started`); only a scene reload refills it.
- Given convoy HP reaches 0 on `level.tscn`, when the loss is detected, then `Events.level_failed(&"convoy")` fires once, the WaveDirector stops counting, and the retry prompt shows `CONVOY LOST` after the death beat. RETRY goes through `SceneRouter.restart_level()` (wave 1, energy reset).
- Given an EnemyBullet whose path crosses the Player before a ConvoyShip, when it reaches the Player first, then the Player loses 1 heart (subject to i-frames/Shield), the bullet is spent and the convoy takes nothing.
- Given the Player at a point above a ConvoyShip and the cursor moved straight through to a point below it in one tick, when `step_lock` runs, then the ship ends on the near side of the hull, outside it, and `warp_mouse` was called with the ship's position. Given the cursor held still while a hull moves into the ship, the ship is pushed out and the cursor warped. No hearts are lost through convoy contact.
- Given the full GUT suite, when it runs headless, then every test passes, with no new orphans or errors.

## Spec Change Log

## Review Triage Log

### 2026-10-10 — Review pass
- verdicts: 20 findings — high 0, medium 1, low 10, false 8, maybe-false 1
- findings:
  - `[false]` `[reject]` (blind) Missile fizzle plays Feedback.impact(SMALL), which spawns a small Explosion, contradicting GDD #46 "no explosion" — #46 also says "the same blocked-shot effect as a laser bolt", and a laser bolt stopped by any area has always played Feedback.impact(SMALL); "no explosion" is the missile's MEDIUM detonation and splash, both removed. Listed for the operator feel check.
  - `[low]` `[reject]` (blind) Instant mirror at an edge can teleport a hull onto the Player and pop it through; the Player resolves against stale rects — the tree-order claim is wrong (World/Allies precedes World/Player, so the convoy steps first); a centre inside a 64 px-tall hitbox leaves by the nearest side (≤ 32 px, covered by test_centre_inside_a_hull_leaves_by_the_nearest_side); it happens once per 39 s crossing and only if the ship is beside the leading edge; a fix would add branches.
  - `[maybe-false]` `[defer]` (blind + edge, grouped) The ship fits through the 72 px hitbox pocket inside the triangle — geometry verified; whether it is a bad outcome is an undocumented design question; deferred as medium (unverified), settle by operator playtest.
  - `[false]` `[reject]` (blind) Resting ship visibly overlaps the drawn hull (8/16 px) — the AC defines contact as the 64 px HullArea against the convoy-layer shapes (the ~80 % hitbox), and the 96 px player sprite overlaps at any contact anyway; this is the specified behaviour.
  - `[low]` `[reject]` (blind) _push_out is single-pass, so pushing out of one rect can push into another — the final overlaps_hull check plus _push_out_y guarantees a free position; a double overlap needs the rare flip teleport; a multi-pass loop adds complexity for no common case.
  - `[false]` `[reject]` (blind) HullArea is monitoring dead physics weight — one Area2D against three shapes has no measurable frame cost; no named harm.
  - `[false]` `[reject]` (blind) CONVOY label crosses the 120 px HUD band edge — only the empty Label box does; the uppercase glyphs (no descenders) of a 20 px font centred at y 110 end around y 117.
  - `[low]` `[reject]` (blind) ConvoyBar shares the wave/energy styleboxes, square danger overlay, font-size override — follows existing patterns (EnergyBar's denied overlay is a plain draw_rect; RetryPrompt sets its font size from Config); the shared styleboxes are the same design tokens (coalition fill, heartEmpty track).
  - `[low]` `[patch]` (blind) test_tuning omits pulse_min_alpha and the pulse test hard-codes 0.35 — patched: the key is added to test_tuning and the assertion reads bar.pulse_min_alpha.
  - `[low]` `[reject]` (blind) The edge-squeeze matrix row is tested only through the pure resolve_hull — step_lock delegates to resolve_hull, and that wiring is covered by the other step_lock convoy tests; a near-duplicate test catches no reachable defect.
  - `[false]` `[reject]` (blind) Spawner.spawn_convoy has no single-instance guard — its only caller is Level._ready, once per scene load; a second convoy is unreachable.
  - `[low]` `[reject]` (blind) test_level reads the Player's private `_convoy` — a test-only reach-in, common in this suite; no runtime harm.
  - `[low]` `[reject]` (blind) Energy orbs under a hull can't be collected, and asteroid–convoy overlap is undefined — no GDD rule covers either; a convoy at 40 px/s uncovers a spot within about 4 s; any fix needs a design decision, not a correction.
  - `[low]` `[reject]` (edge) A hull pushing a still ship emits player_moved, which can dismiss the move hint — the ship really moves (Story 5.8 defines the signal as ship movement); the move hint shows at wave start, when players move anyway; a fix adds a branch for a rare, mild case.
  - `[false]` `[reject]` (edge) A missing SHIP_NAMES child crashes Convoy._ready — the children are fixed in convoy.tscn and checked by test_scene_shape; unreachable.
  - `[low]` `[reject]` (edge) convoy.hp <= 0 starts at 0 HP without being lost — needs broken tuning data (shipped 100, checked by test_tuning); a guard adds complexity for a case no build reaches.
  - `[medium]` `[patch]` (verification-gap, pre-verified) player_moved distance under a hull block is untested — patched: test_player_moved_uses_the_blocked_position checks one emit of about 36 and no emit while pushing into the hull.
  - `[false]` `[reject]` (intent) R2 (feel checks as operator actions) not implemented — the ACs contain no action outside the repo; R1 applies, so no awaiting-operator status.
  - `[false]` `[reject]` (intent) HullArea is the radius source and the blocking is analytic — the observable AC outcome (stops, slides, no tunnelling, cursor warp) is met and tested; the mechanism is the spec's documented design choice.
  - `[low]` `[reject]` (intent) The "convoy-aimed Lancer bullet" AC is tested with a plain EnemyBullet, and the path mostly through step() — Lancers fire EnemyBullet and convoy aiming is Story 6.3; step() is the per-frame path itself and is also exercised in the real scene.

## Design Notes

**Triangle layout (GDD #24, #45).** The band y 760–920 is exactly two 80 px hulls tall. The flankers are centred at y `band.min + h/2` (800) and `band.max − h/2` (880), and the lead at the band centre (840). "Lead ~40 px ahead" is read as a 40 px gap: the lead's rear edge is `lead_offset_px` ahead of the flankers' front edges. Any centre offset under 160 px would overlap the hulls. So the group span is `2·w + gap` = 360 px wide. Track `left_x` and `dir`. Heading right, the flankers' centre x is `left_x + w/2` and the lead's is `left_x + w + gap + w/2`. Heading left, mirror it: the lead is at `left_x + w/2` and the flankers at `left_x + w + gap + w/2`. `step_span` clamps to [0, 1920 − span] and flips `dir` on reaching an edge. The mirror is instant (the decision says "mirrored"); whether it reads well is for the operator to judge, not the tests.

**Hull resolution: analytic, not a physics query.** The ship teleports to the cursor, and a physics shape query in the same tick can see a stale broadphase, which makes for flaky tests. So `resolve_hull` uses the convoy's cached hitbox rects, which are the same rects the physics uses. `HullArea` holds the hull circle (the radius source) and the convoy-only mask, per the AC. The algorithm: sub-step from `from` toward `to` in steps ≤ radius/2, and after each step push out of every rect (closest point on the rect; if that is closer than the radius, move to radius along `p − q`; if the centre is inside the rect, push out along the shortest axis). Moving on toward `to` from the pushed point gives the slide. Then confine to the zone. If that leaves an overlap (a squeeze against the screen edge), push out along y only and don't re-clamp y (the band ± radius fits inside the zone).

```gdscript
var p := from
for i in steps:
    p = p.move_toward(to, step_len)
    p = _push_out(p, radius, rects)
p = confine(p, bounds_min, bounds_max)
if _overlaps(p, radius, rects): p = _push_out_y(p, radius, rects)
```

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0 (needed for the new `class_name`s)
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass (see `LOCAL.md` for `<GODOT_DIR>`)

**Manual checks (if no CLI):**
- Operator (feel, not verified by tests): launch `level.tscn` with `-- --level=dev_convoy` and check that the cargo hulls read as dim civilian ships, that the edge turn-around looks acceptable, that sliding along a hull feels solid with the cursor staying locked, and that the convoy bar is readable.

## Auto Run Result

Status: done

**Summary:** A level with `"convoy": true` now spawns (through the Spawner) a three-ship code-drawn convoy into `World/Allies`. It ping-pongs across y 760–920 at 40 px/s with a mirrored triangle (GDD #45) and shares one 100 HP pool, broadcast on `Events.convoy_hp_changed`; at 0 it fails the level once with `&"convoy"`, and the existing retry flow shows CONVOY LOST. Player and ally shots are blocked with no damage (DW-32), missiles fizzle with no splash (DW-33, GDD #46), and the retry prompt ignores failures after a clear (DW-75). The Player's ship is swept against and pushed out of the hulls, and the cursor is warped onto it. A HUD convoy bar shows the HP. `level_dev_convoy.json` proves it all; Levels 1–3 stay convoy-free until Epic 7.

**Files changed:**
- `game/entities/allies/convoy.gd` / `convoy.tscn` -- new: group layout, ping-pong path, shared HP, loss.
- `game/entities/allies/convoy_ship.gd` / `convoy_ship.tscn` -- new: one hull (convoy layer, 80 % hitbox, code-drawn).
- `game/ui/hud/convoy_bar.gd` -- new: the HUD convoy bar (Events only, flash, low pulse).
- `game/core/projectile.gd` -- `is_convoy`, no damage to the convoy, SMALL blocked-shot effect.
- `game/entities/projectiles/missile.gd` -- fizzle: no splash on a convoy hit.
- `game/entities/projectiles/micro_missile.gd` -- doc comment matches the new block rule.
- `game/entities/player/player.gd` / `player.tscn` -- HullArea, `set_convoy`, `resolve_hull`, unified cursor warp.
- `game/core/spawner.gd`, `game/autoloads/entity_registry.gd`, `game/core/groups.gd` -- `spawn_convoy`, the `CONVOY` preload, `Groups.CONVOY`.
- `game/scenes/level/level.gd` / `level.tscn` -- convoy spawn and injection; the HUD `ConvoyBar`.
- `game/ui/menus/retry_prompt.gd` -- ignores `level_failed` after `level_cleared`.
- `game/ui/theme/defector_theme.tres`, `game/data/tuning.json` -- `ConvoyBar` theme items; `hud.convoy_bar`.
- `game/data/levels/level_dev_convoy.json` -- new dev level.
- `game/tests/...` -- new `test_convoy.gd`, `test_convoy_bar.gd`, `test_player_convoy.gd`, plus additions to 9 suites.
- `_bmad-output/game-architecture.md` -- stale collision line fixed, built-parts list, As-built Story 6.1.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- DW-32, DW-33, DW-75 resolved.

**Review findings:** 20 findings. 2 patches applied (1 medium, 1 low, both test gaps). 1 deferred (the 72 px triangle pocket, medium unverified). 17 rejected, each with its reason in the Review Triage Log above.

**Follow-up review recommended:** false. 1 medium and 0 high patched, both test-only.

**Verification:** `--import` exit 0. Full headless GUT suite: 1453 tests, 1452 passing, 1 pending. The pending one is the existing timing-guarded hit-stop test in `test_feedback.gd`, which skips itself when frame timing is too coarse; it is unrelated to this story. No failures, no orphans.

**Residual risks (feel, not verified by tests):** the operator should play `level.tscn -- --level=dev_convoy` and check four things:
- whether the code-drawn hulls read as dim civilian cargo;
- whether the instant turn-around at each edge looks acceptable;
- whether sliding along a hull feels solid with the cursor locked;
- the CONVOY bar, the small blocked-shot spark on a fizzled missile (GDD #46 reading), and the 72 px pocket inside the triangle (deferred).

Until Story 6.3, enemy shots damage the convoy by their own `damage` (1), not 5/2.
