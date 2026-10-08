---
title: 'Story 3.4: Raise the Shield'
type: 'feature'
created: '2026-10-08'
baseline_revision: 'faf25062023cbec06d7eabf160191f4711a3d69c'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-3-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/EXPERIENCE.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Energy can be collected (3.3) but not spent. There is no Shield on E, no `ability_denied` emitter, no "denied" SFX and no energy-bar denied flash, so the player has no answer to a pattern they can't dodge. Covers FR15 and FR17 (shield half). SHOULD tier.

**Approach:** The Player reads `ability_shield` in its physics tick. With enough energy and no active shield it spends `abilities.shield.cost` through `GameState.add_energy(-cost)` and becomes invulnerable for `abilities.shield.duration_s`, shown by a new in-world `ShieldBubble` child. Without enough energy it emits `Events.ability_denied(&"shield")` and plays the new `ability_denied` SFX, and the `EnergyBar` flashes `danger` on that event.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript. Every number comes from `Config`. Existing keys: `abilities.shield.cost` (50) and `abilities.shield.duration_s` (4.0). New keys: `player.shield_bubble` {`diameter_px` 120, `stroke_px` 4, `alpha` 0.4, `blink_hz` 4, `blink_last_s` 0.75} and `hud.energy_bar` gets `denied_flash_s` 0.3 and `denied_flashes` 2.
- **Player shield state** (state stays on `Player`, per the architecture): `is_shielded() -> bool`, `shield_remaining() -> float`, `try_shield() -> bool` and `step_shield(delta)`.
  - `try_shield()`: dead → false, nothing else. Already shielded → false, no energy spent, no event, no SFX (no stacking or refresh). `GameState.energy < cost` → `Events.ability_denied.emit(&"shield")`, `Audio.play_sfx(&"ability_denied")`, return false. Otherwise `GameState.add_energy(-cost)`, shield on with `duration_s` remaining, bubble shown, one `Log.info("combat", ...)`, return true. Put the denial in a small `_deny(ability: StringName)` helper so Story 3.5 can reuse it.
  - `step_shield(delta)` counts down physics delta (so it freezes under pause and hit-stop, like i-frames). On the tick it reaches 0, the shield turns off, the bubble hides, and `_recheck_contacts()` runs (a still-overlapping Bastion or asteroid hits then, as when i-frames end).
  - `is_invulnerable()` becomes i-frames OR shield OR `debug_invincible`. So every damage source (bullets, bolts, Needle shots, contact) is ignored while shielded, and small/medium enemies touching the ship are still destroyed by contact at no heart cost (existing `on_contact` path). Orbs are still collected.
  - `_physics_process` (alive only): after `step_iframes`, call `step_shield(delta)`, then `try_shield()` when `Input.is_action_just_pressed(&"ability_shield")`. Read the action only, never a raw key.
  - `_die()` also clears the shield and hides the bubble.
- **ShieldBubble** (`entities/player/shield_bubble.tscn` + `shield_bubble.gd`, `class_name ShieldBubble extends Node2D`): a `Player` child named `ShieldBubble` instanced in `player.tscn`, hidden by default. It draws a ring of `diameter_px` / `stroke_px` in UX `coalition` `#22E6FF` (a const with a UX-token comment, like `MissileRing`) at `alpha`. The Player drives it with `show_remaining(remaining_s: float)` (≤ 0 hides it) and `hide_bubble()`. Visibility per tick is `remaining > 0 and ShieldBubble.is_lit(remaining, blink_last_s, blink_hz)`. Static `is_lit` returns true above `blink_last_s`; inside the window, with `t = blink_last_s - remaining`, it returns `fmod(t * blink_hz, 1.0) < 0.5`. Accessors `radius_px()` and `ring_color()`.
- **EnergyBar denied flash:** connects `Events.ability_denied` (any ability). It starts or restarts a flash of `denied_flash_s` with `denied_flashes` on-phases. During an on-phase it draws a full-rect overlay in the new theme colour `EnergyBar/colors/denied` (`#FF1F4B`) above the fill and ticks. `_process` runs only while flashing (`set_process(false)` otherwise), so the node stays `PAUSABLE` and freezes under pause. Static `flash_lit(elapsed, duration, flashes) -> bool`: false outside `[0, duration)` or when `duration <= 0` or `flashes <= 0`; else `fmod(elapsed / duration * flashes, 1.0) < 0.5`. Accessors `is_flashing()` and `flash_on()`. It never reads GameState.
- **SFX:** append `ability_denied` (a short ~0.15 s low double buzz with its own `ABILITY_DENIED_SEED = 3401`) to `tools/gen_placeholder_sfx.py` so the existing WAVs stay byte-identical. Then register it in `Audio.SFX` and add a CREDITS row.

**Never:**
- No Barrage, micro-missiles or Q handling (Story 3.5). No E/Q control hints (Epic 5). No shield activation SFX or HUD shield timer (not in the GDD or UX).
- No `instantiate` outside Spawner. The bubble is a scene child of the Player, like `MissileRing`, not a spawned entity. No per-frame allocations or group lookups in the shield or flash ticks. No HUD polling. No bare `print()`. No per-tick logging.
- Denial never spends energy or changes shield state. An active shield is never extended.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Activate | energy 60, no shield, E | energy 10, `energy_changed(10,100)`, shielded, remaining 4.0, bubble visible | n/a |
| Exact cost | energy 50, E | energy 0, shielded | n/a |
| Denied | energy 49, E | energy 49, `ability_denied(&"shield")` once, `ability_denied` SFX played, not shielded | n/a |
| No stacking | shielded, 1.0 s left, energy 100, E | returns false, energy 100, remaining 1.0, no `ability_denied` | n/a |
| Bullet hit | shielded, `apply_damage(1, bullet)` | hearts unchanged, no `player_hit` | n/a |
| Contact small | shielded, Wasp contact | Wasp destroyed, hearts unchanged | n/a |
| Contact large | shielded, Bastion overlapping when the shield ends | 2 hearts lost on the expiry tick, i-frames start | n/a |
| Expiry | 4.0 s of physics delta | not shielded, bubble hidden, damage lands again | n/a |
| Blink | remaining 0.76 / 0.75 / 0.70 / 0.60, 4 Hz | lit / lit / lit / off (t = 0.15 → phase 0.6) | n/a |
| Dead | dead ship, E | nothing (no spend, no event) | n/a |
| Flash | `ability_denied` emitted | on in [0,0.075), off [0.075,0.15), on [0.15,0.225), off from 0.225; stops at 0.3 with `_process` off | n/a |
| Re-flash | second denial mid-flash | flash restarts from 0 | n/a |

</intent-contract>

## Code Map

- `game/entities/player/player.gd` -- `is_invulnerable()` at line 130 (add the shield). `_physics_process` at line 118 (add `step_shield` and the action read). `_die()` at line 157 (clear the shield). `step_iframes`/`_recheck_contacts` at lines 173/251 are the model for expiry and re-checking. `debug_invincible` setter (line 60) is the re-check pattern. `on_contact` (line 201) needs no change. Update the class doc with a "Shield (Story 3.4)" paragraph.
- `game/entities/player/player.tscn` -- add the `ShieldBubble` instance (ext_resource, bump `load_steps`). `MissileRing` (z_index 1) is the sibling pattern.
- `game/entities/player/missile_ring.gd` -- pattern for an in-world `_draw` ring: UX-token colour consts, Config reads in `_ready`, `draw_arc`.
- `game/autoloads/game_state.gd` -- `add_energy(-cost)` spends and clamps. No change.
- `game/autoloads/events.gd:9` -- `ability_denied(ability)` already exists. No change.
- `game/autoloads/audio.gd:9-18` -- `SFX` registry. Add `&"ability_denied"`.
- `tools/gen_placeholder_sfx.py` -- seed consts at lines 20-23 and `main()` at line 155. Add a function and a seed, and keep the existing outputs identical.
- `game/assets/CREDITS.md:22` -- add the WAV row after `sfx_energy_pickup.wav`.
- `game/ui/hud/energy_bar.gd` -- add the flash (`_ready` connect, `_draw` overlay, `_process` gate). `hit_vignette.gd` is the Events-driven flash precedent.
- `game/ui/theme/defector_theme.tres:87` -- add `EnergyBar/colors/denied = Color(1, 0.121569, 0.294118, 1)`. A colour entry needs no `load_steps` change.
- `game/data/tuning.json` -- `player` (line 2, next to `missile_ring`) and `hud.energy_bar` (line 265).
- `game/project.godot:61` -- `ability_shield` = E already exists. No change.
- `game/tests/unit/test_player_hearts.gd` -- player test harness pattern: instantiate the scene, inject `warp_mouse`, physics off, hazards at `HAZARD_POS`, `Feedback.reset()`/`PauseArbiter.clear()` in `after_each`.
- `game/tests/unit/test_energy_bar.gd`, `test_audio.gd`, `tests/data/test_data_files.gd` -- extend.
- `_bmad-output/game-architecture.md` -- built-parts line 563 (shield built; `shield_bubble`), tree line 596 (drop "(planned)"), the Player row at line 668 (Built Story 3.4 API; barrage still planned) and the EnergyBar bullet at line 345 (denied flash).

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_player_shield.gd` (new), `test_shield_bubble.gd` (new), `test_energy_bar.gd`, `test_audio.gd`, `tests/data/test_data_files.gd` -- write these FIRST and cover every I/O row. Set `GameState.energy` directly in setup and reset it to 0 in `after_each`. Include one test that drives the real input path: physics on, `Input.action_press(&"ability_shield")`, await a physics frame, `Input.action_release`, then assert that energy was spent and the shield is up. The data test checks that the shield cost and duration match the GDD (50, 4.0) and that the new keys exist.
- `game/data/tuning.json` -- the new keys.
- `game/entities/player/shield_bubble.gd`, `shield_bubble.tscn` -- NEW.
- `game/entities/player/player.gd`, `player.tscn` -- the shield.
- `game/ui/hud/energy_bar.gd`, `game/ui/theme/defector_theme.tres` -- the denied flash.
- `tools/gen_placeholder_sfx.py`, `game/assets/audio/sfx/sfx_ability_denied.wav`, `game/autoloads/audio.gd`, `game/assets/CREDITS.md` -- the SFX. Regenerate with `uv run python tools/gen_placeholder_sfx.py`, confirm that only the new WAV is added, then run `--import` (new class_name and WAV).
- `_bmad-output/game-architecture.md` -- the as-built notes per the Code Map.

**Acceptance Criteria:**
- Given a level is running with ≥ 50 energy and no shield, when E is pressed, then `HUD/EnergyBar` drops by 50, a coalition ring of 120 px surrounds the ship, and for 4.0 s no bullet, bolt or contact costs a heart (small/medium enemies that touch it still die). The ring blinks at 4 Hz in the last 0.75 s and disappears at the end.
- Given the shield is active, when E is pressed again, then nothing changes.
- Given < 50 energy, when E is pressed, then no shield appears, `Events.ability_denied(&"shield")` fires, the `ability_denied` SFX plays with no "unknown sfx" warning, and the energy bar flashes `danger` twice over 0.3 s.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 20 findings — high 0, medium 1, low 15, false 4, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: when `abilities.shield.duration_s` is 0 or less, `try_shield` spends energy, logs "Shield up" and returns true, but no shield goes up. Only a mistuned data file can reach this (the GDD value is 4.0, pinned by `test_data_files`), and the fix would add a guard branch.
  - `[low]` `[reject]` Blind: the denied overlay is a square `draw_rect` over the track's rounded corners. The track radius is 2 px (`defector_theme.tres:36-39`, not 4), so the corner shows for 75 ms per flash. The fix would add a new theme stylebox item.
  - `[false]` `[reject]` Blind: the opaque flash hides the bar it is about. UX says "the bar flashes `danger` twice over 0.3 s" (EXPERIENCE.md:72, DESIGN.md:73). The bar is fully visible during the off-phases and after the flash, so the opaque on-phase is that flash, not a defect.
  - `[low]` `[patch]` Blind: `test_shield_freezes_without_physics_ticks` can't fail (physics is already off), and nothing tests the pause freeze. Renamed to `test_only_step_shield_counts_down`. Added `test_shield_freezes_under_pause` (physics on, `PROCESS_MODE_PAUSABLE` as under `World`, `PauseArbiter.push`, 10 physics frames, remaining time unchanged).
  - `[low]` `[patch]` Blind: the Design Note on tick order (`step_shield` before the E read) has no test. Added `test_expiring_shield_can_be_reraised_on_the_same_tick`: one DT before expiry, E pressed, a single `_physics_process(DT)`, then the shield is back at the full 4.0 s and energy is down by 50.
  - `[low]` `[reject]` Blind: denial isn't tested through real input. The E read in `_physics_process` is the same line for success and denial, and the input test covers that line. Denial itself is tested on `try_shield`.
  - `[low]` `[patch]` Blind: `test_draws_without_errors` never shows that `_draw` ran. It now watches the bubble and asserts the `draw` signal was emitted.
  - `[low]` `[patch]` Blind: the flash pause test never checks that the flash resumes, and `PauseArbiter.clear()` sat in the test body. This shares a root cause with the Verification-gap pause row and is fixed by the same patch.
  - `[low]` `[reject]` Blind: mashing E with low energy plays `ability_denied` with no cooldown, and that can steal pooled SFX players. The pool already steals oldest-first under the 10/s laser, and each press is a single 0.15 s sound. A cooldown would add a guard and state the spec doesn't ask for.
  - `[false]` `[reject]` Blind: the bubble's appear/expire behaviour is left unspecified while the as-built note says "no design decision changed". The UX spec (DESIGN.md:103, EXPERIENCE.md) defines no pop-in or fade, and a rubric suggestion isn't a decision. The build follows the documented behaviour, so no decision changed.
  - `[low]` `[patch]` Blind: redundant code. Removed the unreachable `if not _flashing` guard in `EnergyBar._process` (`_update_flash` already gates `set_process`) and the duplicate `assert_lte(denied_flash_s, 0.3)` in `test_data_files.gd`.
  - `[low]` `[reject]` Edge: duration ≤ 0 spends energy with no shield. Same as the first Blind row: mistuned data only, and the fix is a guard.
  - `[low]` `[reject]` Edge: `abilities.shield.cost` above `energy.max` denies every press with no diagnostic. Only a mistuned data file can reach this, `test_data_files` pins the cost at 50, and the fix is a new guard and warning.
  - `[medium]` `[patch]` Verification gap: `test_flash_freezes_under_pause` passed even when the flash ignored pause (5 headless frames ≈ 0.034 s, still inside the first on-phase). It now waits 24 physics frames under pause (past the whole flash) and asserts the flash is still on. It then clears the pause and asserts the flash runs out with `_process` off, and `after_each` clears PauseArbiter. `wait_seconds` hangs under pause, so it couldn't be used. Mutation check: letting the bar process under pause makes the test fail.
  - `[low]` `[reject]` Verification gap: nothing checks that the denied overlay is actually drawn (colour and rect). Pinning it needs a new test-facing draw accessor, which is new public surface. The `draw` signal, the `flash_on()` state and the theme colour are asserted, and the look is left for the human playtest.
  - `[false]` `[reject]` Intent: the R3b reading, under which the playtest counts as owed operator actions (`awaiting-operator`). The intent's examples are infrastructure actions outside the repo. A feel and look playtest is this project's standard leftover manual check (as in the 3.3 triage), not an `awaiting-operator` action.
  - `[low]` `[reject]` Intent: no end-to-end E → HUD test inside `level.tscn`. Each link is tested where it connects: the real E action raises or denies on the Player, `GameState` → `energy_changed` → the bar is covered by 3.3's level test, and `ability_denied` → the bar flash is covered here.
  - `[low]` `[reject]` Intent: the SFX is checked as the queued stream, not as heard audio. Playback is engine behaviour. The test confirms the pool played the `ability_denied` stream with no unknown-sfx warning.
  - `[low]` `[reject]` Intent: the bubble's rendered pixels are never checked. Automation can't judge visuals. The size, colour, alpha, blink timing, visibility and `draw` emission are asserted, and the look is left for the playtest.
  - `[false]` `[reject]` Intent: the tests pin numbers the epic doesn't state (120 px, 4 Hz / 0.75 s, 2 flashes / 0.3 s). These come from the UX spec (DESIGN.md:103, EXPERIENCE.md:72), which is part of the planning contract.

### 2026-10-08 — Review pass (follow-up)
- verdicts: 23 findings — high 0, medium 0, low 15, false 7, maybe-false 1
- findings:
  - `[low]` `[reject]` Blind: duration ≤ 0 spends energy and returns true with no shield. carried: same as the first Blind row of the previous pass, and `try_shield` still reads `_shield_active = _shield_duration_s > 0.0` after the spend.
  - `[false]` `[reject]` Blind: the opaque flash hides the fill and the ticks. carried: the UX says the bar flashes `danger` twice; the bar shows normally in the off-phases and after the flash.
  - `[false]` `[reject]` Blind: a successful shield sends no SFX or Events signal. The intent's Never list rules out a shield activation SFX and a HUD shield timer, and nothing in the GDD or UX listens for a shield-up event today. No defect.
  - `[false]` `[reject]` Blind: only the shield-up path is logged. The intent asks for exactly one `Log.info` on activation and forbids per-tick logging. Nothing goes wrong at runtime.
  - `[low]` `[reject]` Blind: no test sends a real E press with < 50 energy through to the bar flash. carried: the same claim as the previous pass's "denial isn't tested through real input" and "no end-to-end E → HUD test" rows.
  - `[low]` `[reject]` Blind: mashing E stacks the denied buzz and can steal pooled players. carried: the previous pass's "no denial SFX cooldown" row; `_deny` is unchanged.
  - `[maybe-false]` `[reject]` Blind: an E tap that starts and ends inside hit-stop may be lost. To settle it, check Godot 4.7's `pressed_physics_frame` bookkeeping when no physics tick runs under `time_scale = 0`. If true it is only low: hit-stop lasts at most 150 ms, the hit's i-frames already cover the ship, and the already-shipped `fire_missile` read (`player.gd:142`) uses the same pattern.
  - `[low]` `[patch]` Blind: `test_shield_freezes_under_pause` never clears the pause, so a shield stuck after a pause would still pass. The test now runs `PauseArbiter.clear()`, waits 10 physics frames, and asserts that the remaining time drops below the full duration and the shield is still up.
  - `[false]` `[reject]` Blind: wall-clock waits in the flash tests are flaky. Each wait runs longer than the 0.3 s flash, so a slow machine only ends the flash sooner. The under-pause wait counts physics frames, and the flash can't advance while paused.
  - `[false]` `[reject]` Blind: `assert_eq` on floats in the tuning test. JSON values parse to the same double however they are written (`0.750 == 0.75`), so the exact comparison can't fail spuriously.
  - `[low]` `[reject]` Blind: the bubble doesn't redraw if Config changes and doesn't clamp to the ship size. Config doesn't change at runtime, and a clamp plus warning would be a new guard. The tuned 120 px is far larger than the ship sprite.
  - `[low]` `[reject]` Edge: duration ≤ 0 spends energy with no shield. carried: same as the previous pass's Edge row.
  - `[low]` `[reject]` Edge: pressing E on the exact tick the shield expires while a Bastion overlaps costs hearts before the new shield goes up. This is real, but the intent sets the order (`step_shield` with its expiry `_recheck_contacts`, then `try_shield`) and the "Contact large" matrix row. The window is one physics tick, and changing the order would break the intent contract.
  - `[false]` `[reject]` Edge: the ring's outer edge is 124 px, not 120. DESIGN.md:103 asks for a "120px circle centred on the ship". The ring's centreline is 120 px across, the same centreline convention `MissileRing.draw_arc` uses, and the UX doesn't say where the stroke sits.
  - `[low]` `[reject]` Verification gap: nothing checks that the denied overlay, or the bubble's ring, is actually painted. carried: the previous pass's "denied overlay is drawn" and "bubble pixels unchecked" rows. `_draw` in both files is unchanged.
  - `[low]` `[reject]` Verification gap (other): duration 0 spends energy. carried: same as the duration ≤ 0 rows above.
  - `[low]` `[reject]` Intent: the tests inject contacts and projectile hits instead of real Area2D overlaps. The overlap-signal → `on_contact` / `_on_area_entered` wiring predates this diff, and the shield only changes the `is_invulnerable()` gate those handlers already check. A physics-overlap test would test engine collision, not this story.
  - `[low]` `[reject]` Intent: real input is exercised once, on the success path. carried: the previous pass's denial-through-input row.
  - `[low]` `[reject]` Intent: Player and EnergyBar never meet in a test. carried: the previous pass's end-to-end E → HUD row.
  - `[low]` `[reject]` Intent: nothing tests the shield freezing under hit-stop. `step_shield` takes the same physics delta as `step_iframes`, and no physics tick runs under `time_scale = 0`. A test would pin engine behaviour, and the code is correct by construction.
  - `[low]` `[reject]` Intent: the bubble is checked as flags, not pixels, and it shares `z_index` 1 with `MissileRing`. The pixels part is carried from the previous pass's "bubble pixels unchecked" row. On layering: `MissileRing` draws nothing while the missile is ready and has a much smaller radius, so the two rarely overlap. The look is left to the playtest.
  - `[low]` `[reject]` Intent: the SFX is checked as a queued stream, not as heard audio. carried: same as the previous pass's Intent row.
  - `[false]` `[reject]` Intent: nothing checks that the existing WAVs stay byte-identical. This pass re-ran `uv run python tools/gen_placeholder_sfx.py`, and `git status --short game/assets/audio/sfx` showed no change.

## Design Notes

- **New tuning keys:** the UX spec gives the bubble size, alpha, blink rate and window, and the flash colour, count and duration. These are UX numbers, so they live in data (`player.shield_bubble` mirrors `player.missile_ring`). The ring stroke (4 px) isn't specified, so it gets a data default.
- **The shield reuses `is_invulnerable()`:** this one gate already covers `apply_damage`, contact costs, the contact-destroy path and the overlap re-check. Adding the shield there meets "every damage source, including contact" without touching projectiles or enemies.
- **Blink phase** starts at the window's start, so the ring is lit at exactly `blink_last_s` and toggles every 0.125 s at 4 Hz.
- **Order in the tick:** `step_shield` runs before the E read, so a shield that expires this tick can be re-raised on the same tick, and a fresh shield isn't shortened by the tick it was raised on.

## Verification

**Commands:**
- `uv run python tools/gen_placeholder_sfx.py` then `git status --short game/assets/audio/sfx` -- expected: only `sfx_ability_denied.wav` is new, and no existing WAV is modified.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0, with `ShieldBubble` cached and the WAV imported (`<GODOT_DIR>` from `LOCAL.md`).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failures, no new SCRIPT ERRORs.

**Manual checks (if no CLI):**
- The bubble's look, the blink and the denied flash and buzz need a human playtest.


## Auto Run Result

Status: done

**Summary:** This was a follow-up review pass on Story 3.4 (FR15 and the shield half of FR17).
- The implementation in commit `eb6b7c5e820b5d2499fb233738c0a1acc5e1cc18` is unchanged. E spends 50 energy for 4.0 s of invulnerability, folded into `Player.is_invulnerable()`, and a coalition `ShieldBubble` ring blinks in the last 0.75 s.
- With less than 50 energy, E emits `Events.ability_denied(&"shield")` and plays the `ability_denied` SFX, and the `EnergyBar` flashes `danger` twice over 0.3 s.
- This pass added one test hardening patch.

**Files changed (this pass):**
- `game/tests/unit/test_player_shield.gd`: `test_shield_freezes_under_pause` now clears the pause and asserts that the countdown starts again with the shield still up.
- `_bmad-output/implementation-artifacts/spec-3-4-raise-the-shield.md`: the follow-up triage log entry and this result.

**Review findings:** 23 findings (high 0, medium 0, low 15, false 7, maybe-false 1).
- **Patched (1, low):** the pause test never checked that the shield resumes.
- **Deferred:** none.
- **Rejected (22):** each reason is in the follow-up triage log.
  - Carried from the previous pass:
    - duration ≤ 0 spends energy (×3)
    - opaque flash
    - no denial-through-input or end-to-end E → HUD test (×3)
    - SFX mashing
    - overlay and bubble pixels unchecked (×2)
    - SFX checked as a stream, not heard
  - New lows:
    - no Config redraw or clamp on the bubble
    - the expiry-tick re-raise still takes the Bastion hit (set by the intent)
    - injected contacts, not physics overlaps
    - hit-stop freeze untested
  - New falses:
    - no activation SFX or event (excluded by the intent)
    - only shield-up is logged (as specified)
    - flaky wall-clock waits
    - exact float compares
    - 124 px outer edge (the centreline is 120 px, as with `MissileRing`)
    - WAV byte-identity (re-checked, unchanged)
  - Maybe-false: a hit-stop tap may be lost (if true, only low).

**Follow-up review recommended:** false. This is a follow-up pass, and it patched no high (patched by verdict: high 0, medium 0, low 1).

**Verification:**
- `uv run python tools/gen_placeholder_sfx.py` exits 0, and `git status --short game/assets/audio/sfx` is clean, so no WAV changed.
- `--headless --path game --import` exits 0.
- The full GUT suite exits 0: 838 tests, 837 passing, 1 pending, 7554 asserts, 0 SCRIPT ERRORs.
  - The pending test is the existing `test_hit_stop_overlap_keeps_longest`. It skips itself when wall-clock timing can't tell two hit-stops apart (34.5 ms on this run). It is not a failure, and this story doesn't touch it.

**Residual risks:**
- The bubble's look, the blink, the red flash and the denied buzz still need a human playtest.
- An E tap made entirely inside a hit-stop may be lost (an unverified maybe-false).
- The working tree still has the orchestrator's uncommitted `sprint-status.yaml` change. This run doesn't own that file, so it left the file untouched and didn't commit it.
