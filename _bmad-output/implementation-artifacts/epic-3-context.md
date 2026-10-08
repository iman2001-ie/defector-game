# Epic 3 Context: Player Survival and Energy

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Give the player a survival layer on top of the Epic 1 and 2 combat. The player can take hits on 5 hearts with mercy invulnerability, die and retry instantly, collect energy orbs from wreckage, and spend that energy on a Shield or a Barrage to survive spikes. This epic delivers the "fair challenge" pillar: every attack has an answer (dodge, cover, i-frames, Shield), failure is cheap, and retries are unlimited. It also delivers the risk/reward loop of scarce energy that is wiped on death. Tiers: hearts and retry are MUST. Energy, Shield and Barrage are SHOULD, and cover plus i-frames are the fallback if they get cut.

## Stories

- Story 3.1: Take Hits with Hearts and Mercy Invulnerability
- Story 3.2: Die and Retry Instantly
- Story 3.3: Collect Energy from Wreckage
- Story 3.4: Raise the Shield
- Story 3.5: Unleash the Barrage

## Requirements & Constraints

- **Hearts:** 5 at level start and on retry. There are no heart pickups. Enemy bullets, bolts and Needle shots cost 1 heart. Contact with a small or medium enemy or asteroid costs 1 heart and destroys the enemy. Contact with a large asteroid, a Bastion or the Flagship hull costs 2 hearts. The Maul collides like a medium enemy (1 heart, Maul destroyed).
- **I-frames:** 1.2 s after a hit, with the ship flickering at 10 Hz. Damage during the window is ignored. A small or medium enemy touching the ship during i-frames or Shield is still destroyed via `destroy_by_contact()`, at no heart cost.
- **Death:** when hearts reach 0, the Player-death tier plays (2×, 12 px / 0.5 s shake, 100 ms hit-stop), then a 1.5 s beat, then the retry prompt. Retry restarts the level from wave 1 with 5 hearts and 0 energy, with no leftover entities or running beat chains. There is no retry limit.
- **Energy:** ranges 0–100. Orbs are worth 10 each. Drop chances per kill: Wasp/Hunter 15%, Lancer/Maul 25%, Needle 30%, asteroid S/M/L 10/30/60%. A Bastion always drops 2 orbs. Orbs drift down at 120 px/s, are magnet-pulled within 160 px of the ship, and despawn after 6 s. Energy resets to 0 on death or restart. Carry-over between levels and saving belong to Epic 4.
- **Shield (E):** costs 50 and gives 4.0 s of full invulnerability, contact damage included. It cannot be stacked or refreshed while active.
- **Barrage (Q):** costs 100 and fires 12 homing micro-missiles over 2.0 s (one about every 0.17 s). Each deals 6 damage. Asteroids block them. It ends with a Large-tier feedback finish.
- **Denied:** pressing E or Q without enough energy does nothing except emit `Events.ability_denied(&"shield"|&"barrage")`, play the "denied" SFX and flash the energy bar.
- **Debug keys (debug builds only):** F2 toggles player invincibility (shown on the overlay). F4 adds 100 energy, capped at 100.
- Every number above is first-pass tuning and must live in `tuning.json`: `player`, `abilities`, `energy`, `drops`, `damage` and `feedback.tiers`. Never hard-code it.

## Technical Decisions

- **State ownership:** hearts, i-frames and shield state live on the `Player` node, for one attempt only. Energy, `current_level_id` and `is_retry` live in the `GameState` autoload. Story 3.2 creates `GameState` and `SceneRouter`, in the fixed autoload order `Log, Events, Config, GameState, SaveManager, PauseArbiter, Audio, Feedback, EntityRegistry, SceneRouter`.
- **Retry = scene reload (ADR-004).** Retry sets `GameState.energy = 0` and `is_retry` first, then calls `PauseArbiter.clear()`, then `SceneRouter.restart_level()` reloads `level.tscn` with the same id. Don't write reset methods on entities. Only `SceneRouter` changes scenes.
- **Pause:** death pauses through `PauseArbiter.push(&"death")` only. The retry prompt uses `PROCESS_MODE_ALWAYS` and the HUD uses `PAUSABLE`. Esc must not open the pause menu while `death` is active. Hit-stop goes through `Feedback` only.
- **Damage rule:** projectiles call `apply_damage(amount, source)` on what they hit, then free themselves. The Player detects contact overlaps itself (the hurtbox masks `enemies`, `asteroids` and `pickups`), applies its own heart loss and calls `destroy_by_contact()` on small and medium enemies. Contact costs come from `tuning.damage`.
- **Feedback:** use `Feedback.impact(ImpactTier.PLAYER_HIT / PLAYER_DEATH / LARGE, pos)`. The player-tier sfx ids and the `red_vignette` extra are known gaps that Epic 3 must close. The vignette is a HUD `ColorRect` triggered by `Events.player_hit`.
- **Events (already in the catalogue):** `hearts_changed(current, max)`, `player_hit(pos)`, `player_died`, `energy_changed(current, max)`, `ability_denied(ability)`, `level_failed(&"hearts")`. Add any new global signal to `events.gd` first.
- **Entities:** orbs (`entities/pickups/energy_orb`, `pickups` layer 6, `pickups` group) and micro-missiles (`entities/projectiles/micro_missile`, `player_shots` layer) are created only through `Spawner` and registered in `EntityRegistry`. Drops are rolled in the enemy and asteroid death path (`_drop_loot`) against `tuning.drops.<type_id>`.
- **Barrage targeting:** pick the nearest enemy once at launch. Re-pick only when that target is freed (`is_instance_valid`), never per frame. With no enemies alive, fly straight up. The micro-missile is a `CapsuleShape2D` aligned with travel, with height ≥ speed / 60.
- **Shield bubble:** planned at `entities/player/shield_bubble.tscn`, drawn in-world.
- **Input:** read only the `ability_shield` (E) and `ability_barrage` (Q) actions, never raw keys. Abilities and weapons run only while the tree is unpaused.
- **HUD:** `ui/hud/hearts_display.gd` and `energy_bar.gd` update from `Events` only and never poll gameplay nodes. Retry prompt: `ui/menus/retry_prompt.tscn/.gd` in the `Overlay` layer.
- Read tuning in `setup()` / `_ready()`. Wrap counts and HP in `Config.int_()`. Log through `Log` with no per-frame logging. Use pausable `create_timer(t, false)` for gameplay timers. Add GUT tests for pure logic (energy clamp, drop rolls, i-frame timing, cost checks).

## UX & Interaction Patterns

- **Player meters** sit right-aligned at x 1888 in the top HUD band: 5 heart icons (40 px, 8 px gap) at y 24, and an energy bar (320×16) at y 76 with tick marks at 50 and 100. Colours: heart `#FF4766`, empty hearts `#2B3348` with a `muted` outline, energy `#FFD23F` (also used for the gold orbs), danger `#FF1F4B`. All of them come from `defector_theme.tres`.
- **Heart pop:** the lost heart scales 1.3 → 1 over 0.15 s and becomes an outline.
- **Hit vignette:** a danger-coloured edge gradient, 0.3 s, max alpha 0.5.
- **Denied flash:** the energy bar flashes `danger` twice over 0.3 s. UI motion never exceeds 0.3 s.
- **Retry prompt:** no panel. It shows a dim, then the loss reason `HULL DESTROYED` centred at y 440 (48 px, `danger`), then RETRY · QUIT TO TITLE buttons (320×80, 48 px gap, top at y 560). The cursor is visible, the HUD is frozen but visible, and Esc is disabled. Microcopy is uppercase.
- **Shield bubble:** a 120 px `coalition` ring centred on the ship at 40% alpha. It blinks at 4 Hz for the last 0.75 s.
- **Retry flow:** the briefing is skipped on retry, and the player is back at wave 1 within about a second.
- The 10 Hz i-frame flicker affects only the player sprite, which keeps it within the photosensitivity floor.

## Cross-Story Dependencies

- Builds on Epic 1 (Player, Spawner, Feedback tiers, PauseArbiter, Audio) and Epic 2 (`level.tscn`, WaveDirector, enemy roster, `Enemy` base with `destroy_by_contact`, debug overlay).
- 3.1 → 3.2: death is triggered by hearts reaching 0. 3.2 introduces `GameState` and `SceneRouter`, which 3.3–3.5 use for energy.
- 3.3 → 3.4 and 3.5: the abilities spend `GameState.energy` and rely on the energy bar for the denied flash. The Shield also reuses the i-frame and contact-destroy path from 3.1.
- **Forward links:**
  - Epic 4 adds energy carry-over and saving on level clear, the title-screen restore of saved energy, and the real QUIT TO TITLE target.
  - Epic 5 adds the E and Q control hints at 50 and 100 energy.
  - Epic 6 reuses the retry prompt for `CONVOY LOST` (`level_failed(&"convoy")`) and adds the Maul drop: a Maul killed by the player or an ally rolls 25%, and one that hits the convoy or misses drops nothing.
  - Epic 7 adds the Flagship hull contact (2 hearts) and turret drops (100%).
