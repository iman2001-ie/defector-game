---
title: 'Story 1.8: Lock the Ship to the Cursor and Fire Missiles Straight Up'
type: 'feature'
created: '2026-10-07'
status: 'awaiting-operator'
baseline_revision: 'd0f1fe715ed7970aebaa46baf5c6ab3bd3186906'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
warnings: ['oversized']
deferred:
  - summary: >-
      After a resume warp the next physics tick may still read the pre-warp mouse position, giving a one-tick ship jump.
    evidence: |-
      Unverified (maybe-false). Depends on whether Viewport.get_mouse_position() queries the OS cursor (immediate after SetCursorPos) or the last motion event. Settle with a live pause/resume test once Story 4.4 adds the pause menu; tests only use a recorder Callable.
    location: >-
      game/entities/player/player.gd _on_resumed / step_lock
    severity: medium (unverified)
operator_actions:
  - 'Run the sandbox (`<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe --path game`), fire lasers and missiles over explosions, and confirm the missile cooldown ring reads clearly over the cyan hull; tune `player.missile_ring.radius_px` / `stroke_px` in data/tuning.json if needed.'
  - 'In the same sandbox run, confirm the ship sits exactly on the cursor with no lag, that pushing the mouse above the player zone holds the ship on the edge, and that the first downward movement moves the ship at once (no dead travel).'
  - 'If your display is not 1920x1080, repeat the zone-edge check there and confirm the ship does not jitter on the edge (WARP_EPS_PX tolerance).'
---

<intent-contract>

## Intent

**Problem:** The Story 1.7 playtest (GDD decisions #29, #31) replaced the speed-capped cursor chase with a zero-delay lock, made the missile fire straight up, removed the reticle and moved the missile cooldown ring onto the ship. The code still has the chase solver, the aimed missile, the reticle and their tuning keys.

**Approach:** Each physics tick, clamp the viewport mouse position into the player zone, warp the OS cursor back if it left the zone, and place the ship exactly on the clamped point. PauseArbiter emits a resume signal, and the Player answers it by warping the cursor onto the ship. The missile always flies `Vector2.UP` from the muzzle. A new `MissileRing` child of the Player draws the cooldown arc from `Events.missile_cooldown_changed`.

## Boundaries & Constraints

**Always:**
- Use statically typed GDScript with tabs. Log only through `Log`. Read tuning only through `Config` getters, cached in `_ready()`. Never hard-code a GDD number.
- Viewport coordinates are world coordinates here (1920×1080, the camera is centred and has no zoom). The lock reads `get_viewport().get_mouse_position()`, never `get_global_mouse_position()`, so ShakeCamera's offset can't feed back into the ship. Warps use the same space.
- **Ownership:** PauseArbiter alone sets `mouse_mode` and `tree.paused`. The Player makes every gameplay `warp_mouse` call, through an injectable `warp_mouse: Callable`. It defaults to `get_viewport().warp_mouse` (the same pattern as `DebugTools.restart_scene`). Only warp while `PauseArbiter.current_mouse_mode() == Input.MOUSE_MODE_CONFINED_HIDDEN`, so a VISIBLE-mode scene or test never moves the OS cursor.
- No allocations, lookups or logging in `_physics_process`.
- The ship never rotates. The hurtbox, muzzle and weapon timing are unchanged.
- Ring colours are constants citing the UX token `missileRing`: stroke in `text` `#E8F4FF`, a 2 px outline in `background` `#05070F`. The radius and stroke are data.

**Never:**
- Don't change the convoy push or sweep (that belongs to Story 6.1).
- Don't do any glow or `render.glow` work (Story 1.9) or architecture-doc edits (Story 1.10).
- Don't add new input actions or change the debug-tools bench warp (`DebugTools.BENCH_AIM`).
- Don't buffer missile presses or make other cooldown changes.
- Don't edit `sprint-status.yaml`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Inside zone | mouse (700, 600), gameplay | ship at (700, 600) same tick; no warp | — |
| Above zone | mouse (700, 100) | ship at (700, 432); warp to (700, 432) | — |
| Outside x / below | mouse (-50, 1200) or (2000, 1200) | ship at (0, 1080) / (1920, 1080); warp to that point | — |
| On the edge | mouse (700, 432) | ship at (700, 432); no warp (no repeated warps on the edge) | — |
| VISIBLE gameplay mode | mouse (700, 100), mode VISIBLE | ship clamped to (700, 432); no warp | — |
| Resume | ship (800, 900), cursor left at (100, 100), pause popped, mode CONFINED_HIDDEN | one warp to (800, 900); next tick ship stays at (800, 900) | — |
| Push without resume | push(&"menu") or pop while still paused by another reason | no resume emit, no warp | — |
| Missile | RMB at any cursor position | velocity `(0, -900)`, spawned at Muzzle | cooldown/spawn-failure rules unchanged |
| Ring ratio | emits 0.5 / 1.7 / -0.2 / 0 | ratio 0.5 / 1.0 / 0.0 / 0.0; nothing drawn at 0 | — |
| Ring radius > ship | `player.missile_ring.radius_px` > `player.sprite_px` / 2 | clamped to sprite_px / 2 | `Log.warn("data", …)` once in `_ready` |

</intent-contract>

## Code Map

- `game/entities/player/player.gd` -- the chase model (`chase_step`, `solve_chase_gain`, `is_ref_time_feasible`, `_cover_time`, `GAIN_*`, `ARRIVE_EPS_PX`, `_max_speed`, `_gain`, `step_toward`) gets deleted. `missile_direction` and the `target` param of `step_missile` go too. Keep `clamp_to_bounds`, `_bounds_min/_max`, the hurtbox and sprite sizing, `set_spawner` and `step_fire`.
- `game/entities/player/player_weapons.gd` -- `step_missile(pressed, origin, target, delta)` (L118) becomes `step_missile(pressed, delta)` with velocity `Vector2.UP * _missile_speed`. Delete `missile_direction` (L143) and `_missile_straight_up_px` (L39, L68). Update the header doc.
- `game/entities/player/player.tscn` -- add a `MissileRing` Node2D child after `Weapons` with `z_index = 1` (the Sprite is at 0), and bump `load_steps`.
- `game/entities/player/reticle.gd`, `reticle.tscn`, `game/tests/unit/test_reticle.gd` -- delete, along with their `.uid` files if present.
- `game/scenes/sandbox/sandbox.tscn` -- remove the `3_reticle` ext_resource, the `World/Reticle` node and its `load_steps` entry.
- `game/autoloads/pause_arbiter.gd` -- `_apply()` (L44) is the single place where the paused state changes. Add the resume signal there.
- `game/autoloads/events.gd` L9 -- `missile_cooldown_changed(ratio)` (1 = just fired, 0 = ready). It stays unchanged and is the ring's only input.
- `game/data/tuning.json` -- `player` (L2-L13) and `weapons.missile` (L21-L28).
- `game/tests/unit/test_player_movement.gd` -- the chase tests (L9-L153) get rewritten. Keep the scene-shape tests (L156+).
- `game/tests/unit/test_player_missile.gd`, `test_player_weapons.gd` -- these call `step_missile(pressed, target, delta)` / `(pressed, origin, target, delta)` and `missile_direction`.
- `game/tests/unit/test_sandbox.gd` L2, L32-33, L47-51 -- reticle assertions.
- `game/tests/unit/test_config.gd` L134-136, L187-188, L254, L261-264, L329-334, L355 -- these use `player.max_speed` (1400) as their sample number key. `game/tests/fixtures/bad_tuning.json` L3 also contains it (the file is deliberately malformed).
- `game/ui/debug/debug_tools.gd` `BENCH_AIM` -- a debug-only warp. Read-only. With the lock, the ship now sits on that point.
- `game/core/playfield.gd` -- `Playfield.SIZE` gives the x bounds.

## Tasks & Acceptance

**Execution:**
- `game/data/tuning.json` -- remove `player.max_speed`, `player.chase_ref_distance_px`, `player.chase_ref_time_s` and `weapons.missile.straight_up_within_px`. Add `player.missile_ring: { "radius_px": 36, "stroke_px": 5 }`. -- Decisions #29/#31 and the UX `missileRing` first pass.
- `game/autoloads/pause_arbiter.gd` -- add `signal resumed`. Emit it from `_apply()` only on a paused→unpaused transition (track the previous state), after `mouse_mode` is written. `clear()` while paused counts as a resume. -- The resume hook the architecture names.
- `game/entities/player/player.gd` -- replace the chase. Add `static func confine(mouse: Vector2, bounds_min: Vector2, bounds_max: Vector2) -> Vector2` (a pure clamp) and `func step_lock(mouse: Vector2) -> void`. `step_lock` confines the point. If the confined point differs from `mouse` and the mode is CONFINED_HIDDEN, it calls `warp_mouse.call(confined)`. Then it sets `global_position = confined`. Add `var warp_mouse: Callable`, which defaults in `_ready` when invalid. `_ready` connects `PauseArbiter.resumed` to `_on_resumed`, which warps to `global_position` when the mode is CONFINED_HIDDEN. `_physics_process` calls `step_lock(get_viewport().get_mouse_position())`, then `step_fire`, then `step_missile(pressed, delta)`. Remove every chase symbol and `missile_direction`. Rewrite the header doc. -- Zero-delay lock, zone confinement, no jump on resume.
- `game/entities/player/player_weapons.gd` -- straight-up missile as in the Code Map. -- FR5.
- `game/entities/player/missile_ring.gd` (new, `class_name MissileRing extends Node2D`) -- `_ready` caches `radius_px` and `stroke_px`, clamping the radius to `player.sprite_px / 2` with a warning, and connects `Events.missile_cooldown_changed`. Store the ratio clamped to 0..1 in a public `cooldown_ratio`, then `queue_redraw()`. `_draw` returns when the ratio is ≤ 0. Otherwise it draws an arc from `-PI/2` sweeping `TAU * ratio` clockwise: first the outline (`background`, width stroke + 2 × `OUTLINE_PX`), then the stroke (`text`). -- FR62 ring on the ship.
- `game/entities/player/player.tscn` -- add the `MissileRing` node as in the Code Map.
- `game/scenes/sandbox/sandbox.tscn` -- remove the Reticle. Delete the reticle files and test.
- `game/tests/unit/test_player_movement.gd` -- write the lock tests first (red), then implement. Cover: every I/O-matrix movement row (with a recorder Callable as `warp_mouse` and the gameplay mode set per row), lock in one tick with no residual offset, `confine` pure cases, never rotates, resume emits one warp to the ship and the following `step_lock` at that point does not move it, and no warp in VISIBLE mode. Restore PauseArbiter in `after_each`.
- `game/tests/unit/test_pause_arbiter.gd` -- `resumed` is emitted once on the last pop, not on push, not on a pop while another reason remains, once on `clear()` while paused, and not on `clear()` while unpaused.
- `game/tests/unit/test_player_missile.gd`, `test_player_weapons.gd` -- drop the target/origin args. Replace the aim and close-cursor tests with a straight-up test: the velocity is `(0, -900)` for any ship position and the missile spawns at Muzzle. Delete the `missile_direction` tests.
- `game/tests/unit/test_missile_ring.gd` (new) -- the I/O ring rows, a fresh ring at 0, radius and stroke from Config, oversized-radius warning and clamp, the colour constants, and that the Player scene has a `MissileRing` child with a z_index above Sprite.
- `game/tests/unit/test_sandbox.gd` -- drop the reticle assertions and add "no `World/Reticle`".
- `game/tests/unit/test_config.gd`, `game/tests/fixtures/bad_tuning.json` -- swap the sample key `player.max_speed` for `weapons.laser.speed_px_s` (1800). The fixture just uses `sprite_px` and stays malformed.

**Acceptance Criteria:**
- Given gameplay with no pause reasons, when the mouse moves, then in the same physics tick the ship's position equals the clamped cursor, and `tuning.json` has none of the four removed keys.
- Given any pause is popped back to gameplay, when the mode returns to CONFINED_HIDDEN, then the cursor is warped to the ship and the ship does not jump.
- Given RMB is pressed with the missile ready, then the missile spawns at the nose with velocity `Vector2.UP * 900`, wherever the cursor is.
- Given the repo after the story, then `reticle.tscn`/`reticle.gd` don't exist and `grep -rn "missile_direction\|straight_up_within\|chase_ref\|max_speed\"\|Reticle" game --include=*.gd --include=*.tscn --include=*.json` finds nothing outside `addons/` (`max_speed_px_s` is a different key and stays).
- Given a missile was just fired, then the ring on the ship sweeps clockwise from 12 o'clock over the remaining fraction, stays hidden when ready, and gets its data only from `Events.missile_cooldown_changed`.
- Given the GUT suite runs headless, then all tests pass.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 24 findings — high 0, medium 4, low 12, false 6, maybe-false 2
- findings:
  - `[medium]` `[patch]` (blind) The edge-warp check uses exact float equality, so at a fractional fullscreen stretch the OS pixel rounding causes a warp on every tick. — Fixed: `WARP_EPS_PX` = 1.0, and the warp happens only when the mouse is more than that distance from the confined point. Tests added for 431.6 (no warp) and 430 (one warp).
  - `[maybe-false]` `[defer]` (blind) The next tick after a warp may read the stale mouse position, so the ship jumps on resume. — It depends on whether `Viewport.get_mouse_position` queries the OS cursor. Settle it with a live pause/resume check in Story 4.4. Deferred (medium, unverified).
  - `[false]` `[reject]` (blind) The ship snaps from its spawn point to the cursor on scene start. — The intent (#29) says the ship equals the cursor on every gameplay tick. The spawn point is only the position before the first tick, and the old chase also moved toward the cursor from the first tick.
  - `[low]` `[reject]` (blind) The ring clamp ignores stroke and outline, and there's no guard for radius or stroke ≤ 0. — The clamp follows the token literally ("radius ≤ ship half-size"). The defaults (36 + 2.5 + 2 = 40.5 < 48) fit. Only bad data reaches these cases, and the fix adds guards.
  - `[low]` `[reject]` (blind) Nothing guards the assumption that viewport coordinates equal world coordinates. — The spec Design Notes document it, and a regression test now pins the viewport source (the VG patch). Runtime checks would add complexity for a fixed camera.
  - `[low]` `[patch]` (blind) The physics-process missile test doesn't catch lock/fire reordering. — Fixed: it now asserts the missile spawns at the Muzzle's global position after the lock tick.
  - `[low]` `[reject]` (blind) The new missile test hard-codes 89, 900 and 8. — Tests deliberately pin GDD values, the same as the existing `test_cooldown_drops_presses_then_fires`. Not a defect in the game code.
  - `[false]` `[reject]` (blind) There's no seam for the convoy push to move the ship. — The intent puts the convoy push in Story 6.1 (sprint-change-proposal), and the architecture already names the Player as the warp owner for it.
  - `[low]` `[reject]` (blind) Sandbox tests can warp the real OS cursor in a windowed GUT run. — Headless is the documented runner, and the sandbox already set CONFINED_HIDDEN before this story. The resume-path trigger is fixed by the after_each patch (E6).
  - `[low]` `[patch]` (blind) The `player.missile_ring` keys aren't among the mandatory paths, and the oversized-radius test mutates shared tuning. — Fixed: mandatory-path asserts for radius_px and stroke_px > 0. The mutate/restore pattern matches the existing tests and is kept.
  - `[medium]` `[patch]` (edge) Warp storm at the zone edge at a non-1080p scale. — Same root cause as the first finding. Fixed by `WARP_EPS_PX`.
  - `[false]` `[reject]` (edge) The ship teleports from its spawn point to the cursor on the first tick. — Same as the blind spawn finding: this is the intended lock behaviour.
  - `[low]` `[reject]` (edge) No warning for radius or stroke ≤ 0. — Only reachable with bad data, and the fix adds guards.
  - `[low]` `[reject]` (edge) The ring's outer edge can exceed the ship after the clamp. — The token bounds the radius, not the outer edge. The default fits.
  - `[low]` `[reject]` (edge) `_on_resumed` on a Player queued for free warps to a stale position. — SceneRouter doesn't exist yet, and the new scene's ship just locks to wherever the cursor is, so the warp is harmless.
  - `[low]` `[patch]` (edge) test_sandbox after_each calls clear() before resetting the mode, so `resumed` fires in HIDDEN mode and calls the real warp. — Fixed: the mode is reset to VISIBLE before clear() in test_sandbox and test_player_missile.
  - `[medium]` `[patch]` (edge, claim) The "no repeated warps on the edge" claim holds only at 1:1 scale. — Same root cause as the first finding. Fixed by `WARP_EPS_PX`, with a sub-pixel test.
  - `[low]` `[reject]` (edge, claim) A sub-pixel ship shift after resume at non-native scale. — At most ≤0.7 px, which is invisible. There's no simple correction.
  - `[medium]` `[patch]` (verification-gap) The viewport-vs-global mouse source is untested because the test has no camera. — Fixed: `test_lock_reads_viewport_not_global_mouse` uses a Camera2D with offset (40, 0) and proves the two differ.
  - `[false]` `[reject]` (intent) The finalization surface (status / operator_actions) is missing from the diff. — Finalization writes the spec, not game code. It is done below as awaiting-operator.
  - `[low]` `[reject]` (intent) Ring readability is only checked through proxies. — Human-only judgement, recorded as an operator action and not as code work.
  - `[maybe-false]` `[defer]` (intent) Warp behaviour against the real OS cursor is only exercised through a recorder. — Same root cause as the stale-mouse deferral. Settle it in a live run (operator action) and in Story 4.4.
  - `[false]` `[reject]` (intent) Cursor independence of the missile isn't varied in tests. — `step_missile(pressed, delta)` takes no cursor input, so it is independent by construction.
  - `[false]` `[reject]` (intent) No test asserts the tuning keys were removed. — The Verification grep ran clean after the patches.

## Design Notes

- **Why viewport space:** `get_global_mouse_position()` includes the ShakeCamera offset, so a shake would move the lock target and break the resume no-jump guarantee. Using viewport coordinates for both the lock and the warps keeps `warp(ship.global_position)` → next tick `ship.global_position` an exact identity. During a shake the ship shakes with the world, which is the intended effect.
- **Why the warp guard:** warp only when the declared gameplay mode is CONFINED_HIDDEN. Tests and menus (VISIBLE) must never grab the OS cursor.
- **Human-only checks** (operator actions, not agent claims): whether the ring reads clearly over the hull and explosions while firing lasers, and how the lock and edge feel in a live sandbox run.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0 (refreshes the class cache after files are added or removed).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failures, no new orphans.
- `grep` from the AC above -- expected: no matches.

## Auto Run Result

Status: awaiting-operator

**Summary:** The ship now sits exactly on the clamped viewport mouse position every physics tick. The chase solver and its keys are gone. When the cursor leaves the player zone it is warped back to the edge (with a 1 px tolerance). When PauseArbiter emits the new `resumed` signal, the Player warps the cursor onto the ship. The missile always flies `Vector2.UP` from the muzzle. The reticle is removed, and a new `MissileRing` (z above the hull) draws the cooldown arc from `Events.missile_cooldown_changed` using the `missileRing` token colours, with its radius and stroke read from data.

**Files changed:**
- `game/autoloads/pause_arbiter.gd`: `resumed` signal emitted on every paused→unpaused transition.
- `game/entities/player/player.gd`: lock (`confine`, `step_lock`, `WARP_EPS_PX`), injectable `warp_mouse`, resume warp. Chase code and `missile_direction` removed.
- `game/entities/player/player_weapons.gd`: straight-up missile; `missile_direction` / `straight_up_within_px` removed.
- `game/entities/player/missile_ring.gd` (+ `.uid`): new cooldown ring.
- `game/entities/player/player.tscn`: `MissileRing` child with z_index 1.
- `game/entities/player/reticle.gd`, `reticle.tscn` (+ `.uid`): deleted.
- `game/scenes/sandbox/sandbox.tscn`: Reticle node removed.
- `game/data/tuning.json`: four keys removed; `player.missile_ring` added.
- Tests: `test_player_movement.gd` (rewritten), `test_missile_ring.gd` (new), `test_pause_arbiter.gd`, `test_player_missile.gd`, `test_player_weapons.gd`, `test_sandbox.gd`, `test_config.gd`, `fixtures/bad_tuning.json` updated; `test_reticle.gd` deleted.
- `_bmad-output/implementation-artifacts/epic-1-context.md`: recompiled (it was stale after the 2026-10-07 correct-course).

**Review:**
- 24 findings in total. Patched: 4 entries (2 medium: the edge-warp tolerance and the viewport-source regression test; 2 low: the missile spawn-order assertion and the after_each ordering plus mandatory ring keys).
- Deferred: 1 (stale mouse read after a warp; medium, unverified).
- Rejected: 6 false and 10 low, with reasons in the triage log.

**Follow-up review recommended:** true. Two medium entries were patched, and the cursor-warp behaviour (edge tolerance and resume) has only been checked against a recorder, never against the real OS cursor at a non-native scale.

**Verification:**
- `--import` exits 0.
- Full GUT suite: 315 tests, 314 passing, 0 failing, 1 pending. The pending one is the existing timing-sensitive hit-stop test in the feedback suite.
- The AC grep found no matches.

**Residual risks:**
- The resume and edge warps are not exercised against a real cursor (deferred item, and an operator action).
- Ring readability and the feel of the lock need a human (see `operator_actions`).
