---
stepsCompleted: [1, 2, 3, 4]
inputDocuments:
  - _bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md
  - _bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/epics.md
  - _bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md
  - _bmad-output/game-architecture.md
  - _bmad-output/planning-artifacts/briefs/brief-game-project-2026-10-06/brief.md
  - _bmad-output/planning-artifacts/briefs/brief-game-project-2026-10-06/addendum.md
mode: 'autonomous - user asked the facilitator to "do as much as you can on your own"; see Facilitator Decisions'
---

# defector-game - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for defector-game (DEFECTOR), decomposing the requirements from the GDD, UX Design if it exists, and Architecture requirements into implementable stories.

UX spec: `ux-designs/ux-defector-game-2026-10-06/` (`DESIGN.md` for tokens and screen layout, `EXPERIENCE.md` for the dialogue model, HUD behaviour and states). Every story that places UI (2.3, 3.1, 3.2, 3.3, 4.1, 4.3, 4.4, 5.1, 5.2, 5.8, 6.1, 7.3, 7.5, 7.7) follows its Layout & Spacing table and State Patterns. If a story and the spec conflict, the spec wins on layout and the story wins on logic.

**Tier tags:** every story carries its MoSCoW tier from the GDD. The cut order is COULD first, then SHOULD. Story 6.5 (Tarek's fall) is the last SHOULD story to cut.

### Facilitator Decisions (all approved by the user 2026-10-06)

The user asked for this workflow to run unattended. These are the decisions the facilitator made on their behalf. Each is cheap to change before sprint planning.

| # | Decision | Why |
|---|---|---|
| F1 | Kept the GDD's 8-epic sequence (E1 → E8) as Epics 1–8 | It's already ordered by user value and risk. E1 is the go/no-go fun gate |
| F2 | **Maul and Lancer convoy-targeting moved from Epic 2 to Epic 6 (Escort)** | They only matter with a convoy. Keeping them with the convoy avoids building Maul against a convoy that doesn't exist yet |
| F3 | Story 1.1 sets up the Godot project and foundation autoloads | The architecture specifies no starter template, so project creation is Epic 1 Story 1 |
| F4 | Autoloads are created by the first story that needs them, not all up front (e.g. `PauseArbiter` in 1.2, `Feedback`/`Audio` in 1.6, `GameState`/`SceneRouter` in 3.2, `SaveManager` in 4.2) | Avoids an up-front "build every service" story with no player value |
| F5 | Until Epic 4, `level_cleared` only logs and shows a placeholder banner. Until Epic 7, clearing Level 3 returns to the title | Keeps every epic playable without depending on a later one |
| F6 | The Maul ignores the player for targeting but still collides with them like any medium enemy: contact costs the player 1 heart and destroys the Maul, so the player can body-block a Maul (costly, not advisable) | User decision 2026-10-06. GDD damage table updated to match |
| F7 | When the core first drops to ≤ 50 HP, its HP is clamped to exactly 50 and it is invulnerable until the Final Choice resolves | The GDD says phase 3 is "the same core with its remaining 50 HP". Clamping stops a missile from overshooting the beat |
| F8 | The boss bar is one bar over the combined HP (turrets 100 + core 200 = 300), with markers at the turret/core boundary and at 50 core HP | Gives the three GDD segment markers on one monotonic bar |
| F9 | The "scrolling convoy" (COULD) gets **no story**. FR36 is marked deferred | The GDD gives no design for it. It needs a design note before a story can be written |
| F10 | The GitHub release story requires explicit user confirmation before `gh release create` | Publishing is outward-facing and hard to reverse |
| F11 | GDD decision-log items 15–17 are accepted | User confirmed 2026-10-06: convoy and Maul MUST, the hour budget, and the mid-wave beat timings |
| F12 | Story 4.1 creates placeholder `level_1/2/3.json` (each with a `name` key); Epic 7 replaces their content | Readiness M1: Epic 4 must not depend on Epic 7 data |
| F13 | Returning to the title restores `GameState.energy` and `highest_unlocked_level` from the save. "Die → Quit to Title → Play" therefore gets back the last saved energy, while Retry gives 0. Accepted quirk | Readiness M2: in-memory energy must not leak across menus |
| F14 | `hunter_wasp` is always a known enemy type id. Whether it spawns depends only on the `hunter_wasp` flag, even if Story 2.8 is cut (with the flag forced false) | Readiness M3: cutting a COULD story must not break the data test |
| F15 | A small or medium enemy touching the ship during i-frames or Shield is still destroyed, at no heart cost | Readiness m4: the most generous reading of Pillar 1 |
| F16 | Boss Wasp launches stop when the Flagship enters `FINAL_CHOICE`; Wasps already alive stay | Readiness m6: GDD Phase 3 lists only bursts and spreads |
| F17 | Each Final Choice option first plays a short Vale line (surrender offer / vow), then Isolde's response | Readiness: GDD says Vale offers surrender at the Final Choice |
| F18 | A Maul killed by the player or an ally rolls the 25% drop; a Maul that hits the convoy or misses drops nothing | Readiness: GDD drop table lists Maul 25% but no story implemented it |
| F19 | A Windows export smoke check runs at the end of Epic 1, not just in Epic 8 | Readiness m7: export problems surface late otherwise |

## Requirements Inventory

### Functional Requirements

**Player ship and weapons**

FR1: The player ship sits exactly on the mouse cursor with zero delay (no chase, smoothing or speed cap). It never rotates (always faces up). The cursor is confined to the bottom 60% of the screen (y 432–1080), full width, so the ship is too (GDD decision #29).
FR2: The player hurtbox is a 24 px circle centred on a ~96 px sprite.
FR3: During gameplay the OS cursor is hidden and confined to the player zone. There is no reticle; the ship marks the cursor. On resume from any pause the cursor is warped to the ship, so the ship never jumps.
FR4: Holding LMB fires the laser: twin bolts (visual only), 10 bolts/s, 1 damage per bolt, 1800 px/s, straight up, unlimited.
FR5: RMB fires an unguided missile straight up from the ship's nose at 900 px/s. It deals 8 damage to the target it hits and 3 splash damage to every other target within 120 px. It has a 1.5 s cooldown, unlimited ammo, and a radial cooldown ring drawn on top of the ship.
FR6: Asteroids block every projectile from both sides (player lasers, missiles, micro-missiles, ally shots, enemy bullets, Needle bolts). Player projectiles damage the asteroid they hit.
FR7: The player's projectiles (lasers, missile splash, Barrage) and ally shots never damage allies or the convoy. Convoy ships block them with no damage (GDD decision #23).
FR8: Input is mouse and keyboard only: mouse to move, LMB laser, RMB missile, E Shield, Q Barrage, LMB to advance comms or pick a Final Choice option, Esc to pause. While a story line is paused, inputs are ignored except advancing the dialogue.

**Hearts, death and retry**

FR9: The player has 5 hearts. Enemy bullets, enemy bolts and Needle shots cost 1 heart. Contact with a small or medium enemy or asteroid costs 1 heart and destroys the enemy. Contact with a large asteroid, a Bastion or the Flagship hull costs 2 hearts.
FR10: After a hit, the player is invulnerable for 1.2 s and the ship flickers at 10 Hz.
FR11: Hearts refill to 5 at the start of each level and on retry. There are no heart pickups.
FR12: When hearts reach 0, the player-death feedback plays, followed by a 1.5 s pause and a retry prompt. Retry restarts the current level from wave 1 with full hearts and 0 energy. Retries are unlimited.

**Energy, Shield and Barrage**

FR13: Energy ranges 0–100. Destroyed enemies and asteroids drop 10-energy orbs per the drop table (Wasp/Hunter 15%, Lancer/Maul 25%, Needle 30%, Bastion 100% ×2 orbs, asteroid S/M/L 10%/30%/60%, Flagship turret 100%). Orbs drift down at 120 px/s, are magnet-pulled within 160 px of the ship, and despawn after 6 s.
FR14: Energy carries into the next level and is saved on level clear. It resets to 0 on death or level restart.
FR15: Shield (E) costs 50 energy and gives 4.0 s of full invulnerability, including contact damage, shown as a visible bubble. It cannot be stacked or refreshed while active.
FR16: Barrage (Q) costs 100 energy and fires 12 homing micro-missiles over 2.0 s (one every ~0.17 s). Each deals 6 damage and seeks the nearest enemy. Asteroids block them.
FR17: Pressing E or Q without enough energy does nothing except play a short "denied" sound and flash the energy bar.

**Asteroids**

FR18: Asteroids come in three sizes: Small (64 px, 4 HP, 140 px/s, 1 heart contact), Medium (128 px, 12 HP, 100 px/s, 1 heart), Large (224 px, 30 HP, 60 px/s, 2 hearts). They drift downward, rotate at a random 10–40°/s, exit off the bottom, never split, never count toward wave completion, and appear only in waves that list them.

**Enemies**

FR19: Wasp (small, 3 HP): enters in formation at 350 px/s and holds a formation slot. Every 3–5 s one Wasp dives at the player at 600 px/s after a wing flash and a 0.4 s pause. Contact only. A Wasp that exits the bottom re-enters from the top.
FR20: Lancer (medium, 8 HP): strafes horizontally in the top 35% of the screen at 200 px/s and fires 1 aimed bullet every 2.0 s at 450 px/s after a 0.3 s muzzle glow. In Level 1 it aims at the player or the convoy (50/50).
FR21: Needle (medium, 6 HP): anchors at the top edge and repositions every 8 s. Its targeting line tracks the player for 1.2 s, then locks for 0.3 s (turning red), then it fires a 1600 px/s bolt along the line. It fires every 4.0 s. Asteroids block the bolt.
FR22: Bastion (large, 40 HP): drifts at 60 px/s within y 80–400. Its 2 turrets each fire a 3-bullet spread (±15°) every 2.5 s at 350 px/s after a 0.5 s turret glow.
FR23: Maul (medium, 6 HP): enters from the side with a red engine trail and an alarm ping, then dives straight at the nearest convoy ship at 400 px/s. On impact it deals 10 convoy damage and self-destructs. It never targets the player, but colliding with the player costs 1 heart and destroys the Maul (body-blocking). A Maul that misses ends its dive and counts as cleared.
FR24 (COULD): Hunter Wasp (small, 3 HP, orange tint): chases the player at 300 px/s with a 90°/s turn limit. Contact only.
FR25: Enemy hitboxes cover about 80% of the sprite. Every enemy projectile is magenta or red with a bright core, at least 16 px, and no faster than 450 px/s (the pre-telegraphed Needle bolt is the only exception). Every enemy or boss attack shows at least 0.3 s of glow or charge before it fires.

**Waves**

FR26: All spawns are scripted per wave as data (enemy types, counts, formations or entries, asteroids, story triggers). There is no procedural spawning, and difficulty comes from the enemy mix, not from scaling HP or damage.
FR27: A wave clears when all of its counted enemies are destroyed (asteroids are not counted). The next wave spawns 2.0 s after the previous one clears. After the last wave, the level is cleared.
FR28: Story beats and reinforcements fire at scripted moments: wave start, a percentage of the wave destroyed, wave clear, and boss phase changes.
FR29: A top-centre wave progress bar has one segment per wave. The current segment fills by the percentage of that wave's enemies destroyed.

**Game feel**

FR30: Every hit and destruction plays size-scaled feedback per the GDD tier table: Small (0.5× explosion, no shake, no hit-stop, spark burst), Medium (1×, 4 px/0.15 s, debris), Large (2×, 8 px/0.25 s, 40 ms hit-stop, debris and shockwave ring), Boss part (1.5×, 6 px/0.2 s, 30 ms), Boss death (4× chain explosions over 2 s, 20 px/1.0 s, 150 ms, white flash), Player hit (small, 6 px/0.2 s, 50 ms, red edge vignette), Player death (2×, 12 px/0.5 s, 100 ms, then 1.5 s pause).
FR31: Weapon feel: muzzle flash on every shot; short bright laser bolts with a light hit spark and a soft repeating zap (pitch randomised ±5%); missile launch thump, visible smoke trail and a medium-tier explosion; Barrage whoosh cascade with a large-tier finish.

**Escort and allies**

FR32: In Level 1, three medium cargo ships (~160×80 px, hitbox ~80% of the sprite) fly as a tight triangle (a lead ship plus two flankers). The group crosses the screen left to right at 40 px/s within y 760–920, then loops back. They share one 100 HP bar that carries across waves and refills only when the level restarts. The convoy is solid to the player's ship (push-out, no damage), so the player can body-block shots aimed at it (GDD decision #25). When the convoy pushes the ship, the cursor is moved with it (decision #29).
FR33: Convoy ships are solid to every projectile. Every enemy shot that touches one is stopped and damages the convoy: 5 if a Lancer aimed it at the convoy, 2 if stray. Maul dives deal 10. Bastions and Needles never aim at the convoy, but their strays can hit it. If the convoy bar reaches 0, the level restarts from wave 1.
FR34: Ally ships (Tarek in Levels 1–2, Ryn in Level 3) patrol scripted horizontal paths at y 620–760 at 150 px/s and fire 1 damage every 0.5 s at the nearest enemy. They cannot be destroyed or damaged (except Tarek's scripted hit). They make roughly 10–15% of total kills.
FR35: Tarek's fall (Level 2 Wave 5, at 50% of the wave destroyed): Tarek shields Vale, his comms line is cut off mid-sentence (combat line, no pause), a strong screen shake fires (the dedicated cut-off shake, 18 px for 0.9 s; was large-tier, GDD decision #43), his damaged ship trails fire and leaves, the comms channel goes silent until the wave clears, and the music drops out.
FR36 (COULD, deferred): A scrolling convoy variant. *(No design yet; see F9.)*

**Comms and story**

FR37: The comms panel shows a portrait, a speaker name and typewriter text.
FR38: Story lines (briefings, debriefs, the opening, the surrender offer, the Final Choice lead-in) pause the game, show in a centred panel over a dimmed playfield, and advance on click. Interruptions (internal mode `combat`) are single short lines that auto-dismiss in a small top-left box without pausing; at most 2 per level, only Isolde mocking or an ally warning (GDD decision #22).
FR39: Dialogue lives in data files, and lines are triggered by wave director events (wave start, wave clear, % of wave destroyed, boss phase).
FR40: Cut-off effect: the text stops mid-sentence, a static burst plays, the screen shakes, the comms channel goes silent, and the music drops out.
FR41: The opening sequence is a paused, comms-only scene on a static space background with 6–10 lines. It establishes Vale's defection, Tarek welcoming the General and briefing the convoy mission, and one cold line from Isolde in her own voice. Every character introduces themselves in their own voice (no narration, no text crawl).
FR42 (SHOULD): Isolde interrupts (one-line, no pause): Level 1 Wave 3 (at 25% destroyed, once the ambush is underway), Level 2 Wave 3, and Level 3 Wave 3. Interruptions sit behind an on/off flag.
FR43 (SHOULD): Level 1 Wave 5 Surrender Prompt: at 30% of the wave destroyed, the game pauses and Isolde says "You're outnumbered, General. Come home." with no choice offered. When play resumes, 4 Mauls arrive as reinforcements. The prompt sits behind an on/off flag; the reinforcements arrive either way.
FR44: Level comms beats: Level 1 Tarek's ambush warning at W3 start (interruption) and Tarek's closing line (debrief); Level 2 opens with Tarek's 2–3 line briefing, and Ryn reports after Wave 5 that Tarek is alive but gravely injured and she is taking command; Level 3 opens with Ryn's briefing, in which she takes command.
FR45: All dialogue lines are written: opening, level briefings and debriefs, Tarek's ambush warning, Isolde's interruptions, the surrender line, Tarek's cut-off line, Ryn's report, Isolde's two Final Choice responses and her final line.

**Levels**

FR46: Level 1 "Cargo Ambush" (escort, convoy, Tarek): W1 8 Wasps slow formation; W2 10 Wasps + 3 small + 1 medium asteroid; W3 ambush 12 Wasps, 2 Lancers, 3 Mauls; W4 10 Wasps, 4 Lancers; W5 16 Wasps and 3 Lancers, then 4 Mauls as reinforcements.
FR47: Level 2 "The Blockade" (Tarek fights alongside): W1 2 Needles, 6 Wasps, 2 medium + 1 large asteroid; W2 1 Bastion, 8 Wasps; W3 3 Needles, 3 Lancers, 2 medium asteroids; W4 2 Bastions, 10 Wasps, 1 large asteroid; W5 2 Bastions, 2 Needles, 4 Lancers, 2 medium asteroids.
FR48: Level 3 "Siege of the Throne World" (Ryn fights alongside, throne-world planet arc in the background, shown only in this level): W1 4 Lancers, 12 Wasps; W2 2 Bastions, 2 Needles, 3 medium asteroids (+4 Hunter Wasps if built); W3 20 Wasps, 3 Lancers, 1 Bastion; then the Flagship.

**Flagship boss**

FR49: Flagship Phase 1 (Turrets): 4 turrets, 25 HP each, with an invulnerable core. Each turret fires a 3-bullet spread (350 px/s) every 3.0 s, staggered, after a 0.5 s glow. 2 medium asteroids drift through as cover.
FR50: Flagship Phase 2 (Core): once all 4 turrets die, the 200 HP core is exposed. It fires a 12-bullet radial burst (300 px/s) every 3.0 s after a 0.6 s charge glow and launches 5 Wasps every 10 s (maximum 10 alive). Boss-launched Wasps drop energy normally.
FR51: Flagship Phase 3 (Final Choice): when the core drops to 50 HP, the game pauses, Isolde speaks, and the Final Choice appears as two large centred buttons, [Offer Surrender] / [Destroy Her], chosen by click with no timer. Both lead to her refusal; only her response line differs. Then the desperate barrage starts: 2 alternating radial bursts (300 px/s) every 1.5 s after a 0.4 s glow, plus an aimed 3-bullet spread (400 px/s) every 2.0 s after a 0.3 s glow. The core flashes red at a steady pulse.
FR52: Flagship hull contact costs 2 hearts. Flagship turrets drop an energy orb 100% of the time.
FR53: During the boss fight, a dedicated boss bar replaces the wave progress bar, with three segment markers: turrets, core and final.
FR54: Destroying the Flagship plays the boss-death feedback tier, then Isolde's final line, then the end screen.
FR55 (COULD): A council epilogue after the final line.

**Game flow, save and HUD**

FR56: The title screen offers Play (continue at the highest unlocked level), Level Select (locked levels shown greyed out) and Quit.
FR57: The pause menu (Esc) offers Resume, Restart Level and Quit to Title.
FR58: Clearing a level unlocks the next one. Unlocked levels and current energy are saved to the per-user app data folder on level clear.
FR59: The game defaults to borderless fullscreen, supports windowed mode, and letterboxes the playfield to keep 16:9.
FR60: A level is won when every scripted wave is destroyed (and in Level 3, the Flagship). There are no timers, score or ratings. The game is won when the Flagship is destroyed and the end screen appears.
FR61: Dialogue, wave compositions and tuning values live in data files, not code. The surrender-prompt beats (and other optional beats) sit behind on/off flags.
FR62: The HUD shows hearts, an energy bar (with markers at 50 and 100), the missile cooldown ring (in-world, on the ship), the wave progress bar, the boss bar and the convoy bar.

**Presentation and release**

FR63: Audio: about 15–20 SFX cues; explosion volume and pitch scale with the size tier; distinct cues for player hit, energy pickup, ability denied, comms open, and comms cut-off (static burst, then silence). Optional music: one combat track and one boss track. No voice acting.
FR64: Art: clean neon/vector 2D on dark space backgrounds. Colour language: Coalition cyan/teal, Sovereignty enemies and all enemy projectiles magenta/red, energy orbs gold, asteroids desaturated grey-brown with a rim light. Two space backgrounds plus the throne-world arc (Level 3 only). Portraits for Isolde, Tarek and Ryn (Vale optional).
FR65: The game ships as a zipped Windows executable on the public GitHub repo's releases page, with a README covering the controls and the story premise.
FR66: Control hints: short on-screen key prompts (not dialogue) teach the controls in Level 1: move and hold LMB in W1, RMB missile in W2, and E Shield / Q Barrage when the player first reaches 50 / 100 energy. Each hint shows once per session and fades after the action is performed or 5 s.

### NonFunctional Requirements

NFR1: Performance: 60 FPS sustained at 1920×1080 on the developer's integrated-graphics laptop during the busiest wave, with headroom for 40 enemies, 200 projectiles and particles (16.6 ms frame budget).
NFR2: Cold launch to the title screen in under 5 s.
NFR3: Build size under 200 MB.
NFR4: Platform: Windows 10/11 64-bit; zipped executable with no installer.
NFR5: Reliability: no crash or soft-lock across 3 full start-to-finish playthroughs, and every scripted story beat fires in every playthrough.
NFR6: Readability and fairness (Pillar 1): every attack is telegraphed for at least 0.3 s; enemy projectiles are magenta/red, ≥ 16 px and ≤ 450 px/s (Needle excepted); the player hitbox is forgiving; retries are instant and unlimited.
NFR7: Tunability: every GDD number is first-pass tuning and must be exposed as data, never hard-coded; tuning changes are recorded in the GDD decision log.
NFR8: Learnability: a first-time playtester understands the controls without verbal help by Level 1 Wave 2.
NFR9: Session shape: full playthrough 10–15 minutes (about 3–4 minutes per level plus dialogue); a first-time player clears each level in 1–3 attempts.
NFR10: Assets: free assets only (Kenney CC0 packs first, free-licence music), every third-party asset credited.
NFR11: Security and privacy: offline single-player with no network or personal data; the public repo contains no secrets, machine paths or personal machine information.
NFR12: Tech constraint: Godot 4 with statically typed GDScript; no plugins in the shipped runtime.

### Additional Requirements

From `game-architecture.md`:

- **No starter template** (R4). Epic 1 Story 1 creates a plain Godot 4.7.2-stable project in the `game/` subfolder (Forward+, Git VCS metadata), following the directory structure in the architecture.
- **Project settings:** 1920×1080, fullscreen window mode, stretch `canvas_items` / aspect `keep`, `rendering/viewport/hdr_2d = true`, `application/config/use_custom_user_dir = true` with `custom_user_dir_name = "DEFECTOR"`, `debug/file_logging/enable_file_logging = true` (release too), `untyped_declaration` warning = Warn.
- **Autoloads in this order:** `Log`, `Events`, `Config`, `GameState`, `SaveManager`, `PauseArbiter`, `Audio`, `Feedback`, `EntityRegistry`, `SceneRouter`.
- **Collision layers** (exact names and numbers): 1 `player`, 2 `player_shots`, 3 `enemies`, 4 `enemy_shots`, 5 `asteroids`, 6 `pickups`, 7 `convoy`, 8 `allies`, with the masks in the architecture table. Friendly fire is impossible (player shots are blocked by the convoy without damaging it).
- **Damage rule:** projectiles apply damage to what they overlap and then free themselves; the Player applies its own contact damage; the Maul applies convoy damage; every enemy shot that hits the convoy damages it (aimed 5 / stray 2); player and ally shots are blocked by the convoy with no damage.
- **Anti-tunnelling:** every projectile uses a `CapsuleShape2D` aligned with travel, with height ≥ speed / 60 px.
- **Input actions** in `project.godot`: `fire_laser`, `fire_missile`, `ability_shield`, `ability_barrage`, `comms_advance`, `pause`, `toggle_fullscreen`, `debug_*` (F1–F7). Code never reads raw keys.
- **Data:** JSON in `res://data/` (`tuning.json` with fixed sections `player, weapons, abilities, energy, drops, enemies, boss, asteroids, convoy, allies, waves, comms, feedback, damage`; `flags.json`; `levels/level_<n>.json`; `dialogue/<scene>.json`). Access only via `Config` typed getters (`num`, `int_`, `flag`, `section`, `level`, `sequence`). JSON numbers are floats, so counts and HP go through `Config.int_()`. Tuning is cached in `setup()`/`_ready()`, never read per frame. F5 hot-reloads data in debug builds.
- **Pause and time:** only `PauseArbiter` sets `get_tree().paused` (reason set: `menu`, `story`, `final_choice`, `death`) and the mouse mode; only `Feedback` sets `Engine.time_scale` (hit-stop, longest-remaining wins) and the camera offset.
- **State:** `GameState` holds energy, `current_level_id`, `highest_unlocked_level`, `is_retry` and `final_choice`. Everything else lives on level-scene nodes. Retry = scene reload via `SceneRouter.restart_level()` (ADR-004), with energy reset first.
- **Save:** `ConfigFile` at `user://save.cfg` (`[progress] save_version, highest_unlocked_level, energy`), written only by `SaveManager.save()` and only on level clear. A missing, corrupt or unknown-version save gives defaults and a warning, never a crash.
- **Scenes:** `boot` (main scene) → `title` / `level_select` → `story` → generic `level.tscn` (one tree for all levels, parameterised by level id) → `end_screen`. Only `SceneRouter` changes scenes.
- **Entity creation:** only `Spawner` instantiates gameplay entities, using `EntityRegistry` preloaded scenes, calling `setup(params)` before `add_child`. No pooling by default (ADR-002).
- **Entity behaviour:** `enum State` + `match` with `_enter_state()`; telegraph states ≥ 0.3 s from tuning, enforced by a GUT data test. `Enemy` base contract: `resolved` signal emitted exactly once, `type_id`, `tier`, `setup`, `apply_damage`, `destroy_by_contact`.
- **Events:** global `Events` autoload with the typed signal catalogue from the architecture; new global signals are added there first.
- **Novel patterns:** Wave Director + Beat Triggers, Comms Channel, Impact Feedback tiers, Pause Arbiter, implemented exactly per the architecture rules.
- **Error handling:** fail loudly in debug, degrade in release; invalid spawn entries are logged and subtracted from the wave total (no soft-lock); unknown dialogue ids emit `finished` immediately; a fatal `tuning.json` parse error shows a plain error label on the title screen.
- **Logging:** `Log` autoload, format `[LEVEL][category] message`, fixed categories, no per-frame logging, no bare `print()`.
- **Debug tools** (debug builds only): F1 overlay, F2 invincibility, F3 resolve wave, F4 +100 energy, F5 reload data, F6 jump to boss, F7 unlock all; F11 fullscreen toggle (release too); F8 screenshot only if needed.
- **Testing:** GUT 9.7.1 (`godot_4_7` branch) in `addons/gut/`, dev-only, for pure logic and data validation (`test_config`, `test_save_manager`, `test_wave_progress`, `test_beat_trigger`, `test_pause_arbiter`, `test_data_files`), run headless from the CLI. Feel is tested by playtest.
- **Rendering:** neon via `hdr_2d` + `WorldEnvironment` glow, but glow sprites also use additive `CanvasItemMaterial`, so switching to the Compatibility renderer is a one-setting fallback (ADR-003, triggered by the E1 perf check).
- **Performance:** particle/shader pre-warm at level load; Barrage and ally targeting re-acquire on events, not per frame; E1 stress test (40 Wasps + hold fire) under 16.6 ms.
- **Deployment:** Windows Desktop preset, embedded PCK, non-resource filter `data/*.json`, exclude `addons/gut/*, tests/*`, export to `game/export/windows/` (gitignored), zip `DEFECTOR-v1.0-windows.zip` with README and credits, publish with `gh release create`, smoke test on a clean folder.
- **No engine MCP** (R13); AI agents use the headless Godot CLI loop for tests, runs and logs.
- **Credits:** every third-party asset is listed in `game/assets/CREDITS.md`.

### UX Design Requirements

From `ux-designs/ux-defector-game-2026-10-06/` (added 2026-10-06, closing readiness issue M4):

- UX-DR1: The persistent HUD stays inside the top 120px band. The player zone (below y 432) only ever gets the temporary hint pill and the paused overlays.
- UX-DR2: Interruption box at the top-left (32, 24, 560×96); wave/boss bar at the top-centre; hearts, energy and convoy bars right-aligned at the top-right.
- UX-DR3: Paused dialogue uses the centred 1100×300 story panel over a 60% dim, with no buttons and a `click to continue ▸` cue.
- UX-DR4: Control hints appear as a pill centred at y 560.
- UX-DR5: The retry prompt shows the loss reason (`HULL DESTROYED` / `CONVOY LOST`), then RETRY · QUIT TO TITLE.
- UX-DR6: Theme A "Cold Neon" palette and Kenney Future font, defined once in `defector_theme.tres`.
- UX-DR7: Every pause state dims the playfield; the HUD freezes but stays visible.

### FR Coverage Map

FR1: Epic 1 - Cursor-locked ship movement and bounds
FR2: Epic 1 - Forgiving 24 px hurtbox
FR3: Epic 1 - Hidden cursor confined to the player zone
FR4: Epic 1 - Laser
FR5: Epic 1 - Straight-up missile, splash, cooldown ring
FR6: Epic 1 - Asteroids block both sides (enemy-side verified again in Epic 2)
FR7: Epic 1 - Friendly fire impossible by mask (verified with the convoy and allies in Epic 6)
FR8: Epic 1 - Input actions (abilities in Epic 3, pause in Epic 4, comms advance in Epic 5)
FR9: Epic 3 - Hearts and damage table
FR10: Epic 3 - I-frames and flicker
FR11: Epic 3 - Hearts refill on level start and retry
FR12: Epic 3 - Death and instant retry
FR13: Epic 3 - Energy drops and orbs
FR14: Epic 3 (reset on death) and Epic 4 (carry-over and save)
FR15: Epic 3 - Shield
FR16: Epic 3 - Barrage
FR17: Epic 3 - Denied feedback
FR18: Epic 1 - Asteroids
FR19: Epic 2 - Wasp
FR20: Epic 2 - Lancer (convoy targeting in Epic 6)
FR21: Epic 2 - Needle
FR22: Epic 2 - Bastion
FR23: Epic 6 - Maul
FR24: Epic 2 - Hunter Wasp (COULD)
FR25: Epic 2 - Hitboxes, projectile readability, telegraph rule (hitbox convention set in Epic 1)
FR26: Epic 2 - Data-scripted waves
FR27: Epic 2 - Wave clear rules and gap
FR28: Epic 2 (trigger engine, reinforcements) and Epic 5 (comms, story event and music actions)
FR29: Epic 2 - Wave progress bar
FR30: Epic 1 - Impact feedback tiers (player tiers in Epic 3, boss tiers in Epic 7)
FR31: Epic 1 - Weapon feel (Barrage in Epic 3, final audio in Epic 8)
FR32: Epic 6 - Convoy
FR33: Epic 6 - Convoy damage and loss condition
FR34: Epic 6 - Ally ships
FR35: Epic 6 - Tarek's fall (with the Epic 5 cut-off effect)
FR36: Deferred - no story (F9)
FR37: Epic 5 - Comms panel
FR38: Epic 5 - Story vs combat lines
FR39: Epic 5 - Dialogue data and wave-triggered lines
FR40: Epic 5 - Cut-off effect
FR41: Epic 5 - Opening sequence
FR42: Epic 5 - Isolde interruptions (placed into levels in Epic 7)
FR43: Epic 5 - Surrender prompt (placed into Level 1 in Epic 7)
FR44: Epic 7 - Level comms beats
FR45: Epic 5 - Dialogue script
FR46: Epic 7 - Level 1
FR47: Epic 7 - Level 2
FR48: Epic 7 - Level 3
FR49: Epic 7 - Flagship Phase 1
FR50: Epic 7 - Flagship Phase 2
FR51: Epic 7 - Flagship Phase 3 and Final Choice
FR52: Epic 7 - Flagship contact damage and turret drops
FR53: Epic 7 - Boss bar
FR54: Epic 7 - Boss death, final line, end screen
FR55: Epic 7 - Council epilogue (COULD)
FR56: Epic 4 - Title screen and level select
FR57: Epic 4 - Pause menu
FR58: Epic 4 - Unlocks and save
FR59: Epic 4 - Display modes
FR60: Epic 2 (level clear) and Epic 7 (game win)
FR61: Epic 1 (tuning and flags), Epic 2 (waves), Epic 5 (dialogue and flag-gated beats)
FR62: Epic 1 (cooldown ring), Epic 2 (wave bar), Epic 3 (hearts, energy), Epic 6 (convoy bar), Epic 7 (boss bar)
FR63: Epic 8 - Audio pass (SFX framework from Epic 1)
FR64: Epic 4 - Player ship sprite (Story 4.0); Epic 8 - Art pass
FR65: Epic 8 - Windows release
FR66: Epic 5 - Control hints (placed into Level 1 in Epic 7)

## Epic List

### Epic 1: Core Feel Prototype
The player can fly the ship with the mouse, fire lasers and missiles, and blast Wasps and asteroids in a sandbox where every impact scales with size. This proves the core hypothesis and is the go/no-go gate before any story work. **Tier:** MUST.
**FRs covered:** FR1, FR2, FR3, FR4, FR5, FR6, FR7, FR8, FR18, FR30, FR31, FR61 (tuning, flags)

### Epic 2: Enemy Roster and Scripted Waves
The player fights through data-scripted waves of Wasps, Lancers, Needles and Bastions with readable telegraphs, watching a wave progress bar fill until the level clears. The designer can author waves and triggers in JSON. **Tier:** MUST (Hunter Wasp COULD).
**FRs covered:** FR19, FR20, FR21, FR22, FR24, FR25, FR26, FR27, FR28, FR29, FR60, FR61 (waves)

### Epic 3: Player Survival and Energy
The player can take hits, die and retry instantly, collect energy from wreckage and spend it on a Shield or a Barrage to survive spikes. **Tier:** MUST hearts and retry, SHOULD energy, Shield and Barrage.
**FRs covered:** FR9, FR10, FR11, FR12, FR13, FR14, FR15, FR16, FR17

### Epic 4: Game Flow, Progression and Save
The player launches into a title screen, continues where they left off, picks unlocked levels, pauses at any time and keeps their progress between sessions, in fullscreen or windowed mode. **Tier:** MUST (player ship sprite SHOULD).
**FRs covered:** FR14, FR56, FR57, FR58, FR59, FR64 (player ship)

### Epic 5: Comms and Story Delivery
The player hears the story without ever leaving the action: an opening comms scene, paused story lines, live combat chatter, Isolde's interruptions, the surrender prompt and the mid-sentence cut-off. **Tier:** MUST panel, data, cut-off and opening; SHOULD interruptions and surrender.
**FRs covered:** FR28, FR37, FR38, FR39, FR40, FR41, FR42, FR43, FR45, FR61 (dialogue, flags), FR66

### Epic 6: Escort and Allies
The player protects a convoy from Mauls and Lancers, flies alongside Tarek and Ryn, and lives through Tarek's fall at the Blockade. **Tier:** MUST convoy and Maul, SHOULD allies and Tarek's fall (last to cut).
**FRs covered:** FR7, FR20 (convoy targeting), FR23, FR32, FR33, FR34, FR35, FR62 (convoy bar)

### Epic 7: The Campaign: Three Levels and the Flagship
The player plays the full campaign from Cargo Ambush to the Siege of the Throne World, defeats Isolde's Flagship across three phases, makes the Final Choice and sees the war end. **Tier:** MUST (council epilogue COULD).
**FRs covered:** FR44, FR46, FR47, FR48, FR49, FR50, FR51, FR52, FR53, FR54, FR55, FR60

### Epic 8: Polish and Release
Anyone can download DEFECTOR from GitHub and play a polished, stable build with full audio, final art and smooth performance. **Tier:** MUST release and stability checks, SHOULD audio and art pass.
**FRs covered:** FR63, FR64, FR65 (plus NFR1–NFR5, NFR8–NFR11 verification)

**Validation (step 4, 2026-10-06):** 65 of 66 FRs are covered (FR66 control hints added 2026-10-06, GDD decision #22) by at least one story (FR36 deferred, F9); every NFR is tagged on a story; no starter template exists, so Story 1.1 sets up the project; autoloads and data files are created by the first story that needs them; no story depends on a later story. Expected file overlap: `wave_director.gd` grows in Stories 2.2, 5.3 and 7.3, and `comms_channel.gd` in 5.1–5.4 and 7.5. These are ordered extensions of one system, not churn.

**Dependency flow:** each epic builds only on earlier epics. Epic 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8. Epic 1 must pass its fun gate (Story 1.7) before Epic 5 starts.

---

## Epic 1: Core Feel Prototype

The player can fly the ship with the mouse, fire lasers and missiles, and blast Wasps and asteroids in a sandbox where every impact scales with size. Done when the developer answers "yes" to "Was the shooting fun on its own?"

> **Amended 2026-10-07 (decision #34):** the colleague requirement is waived for Epic 1 only; the developer playtest (#28) is enough.

### Story 1.1: Set Up the Godot Project and Data-Driven Foundation

As the developer,
I want a configured Godot 4.7.2 project with logging, a global event bus and a validated tuning file,
So that every later story follows the same conventions and reads GDD values from data instead of code.

**Tier / Covers:** MUST · FR8, FR61, NFR7, NFR12 · Architecture: project settings, autoloads, collision layers, input actions, Config, GUT

**Acceptance Criteria:**

**Given** the repo has no Godot project
**When** the project is created in `game/` with Godot 4.7.2-stable (Forward+)
**Then** `game/project.godot` sets 1920×1080, fullscreen window mode, stretch `canvas_items` / aspect `keep`, `hdr_2d = true`, custom user dir `DEFECTOR`, file logging enabled, and `untyped_declaration` = Warn
**And** `game/.gitignore` ignores `.godot/`, `export/` and `*.tmp`, and the folder skeleton from the architecture (`autoloads/`, `core/`, `entities/`, `systems/`, `scenes/`, `ui/`, `data/`, `assets/`, `tests/`) exists

**Given** the project settings
**When** I open the collision layer names and the Input Map
**Then** the 8 layers are named exactly `player, player_shots, enemies, enemy_shots, asteroids, pickups, convoy, allies` (1–8)
**And** the input actions `fire_laser` (LMB), `fire_missile` (RMB), `ability_shield` (E), `ability_barrage` (Q), `comms_advance` (LMB), `pause` (Esc), `toggle_fullscreen` (F11) and `debug_overlay` … `debug_unlock_all` (F1–F7) exist

**Given** the `Log`, `Events` and `Config` autoloads are registered in that order
**When** the game boots
**Then** `Log.info/warn/error/debug(category, msg)` prints `[LEVEL][category] message`, ERROR/WARN also call `push_error`/`push_warning`, and DEBUG is dropped when `OS.is_debug_build()` is false
**And** `events.gd` contains the full typed signal catalogue from the architecture, with no logic

**Given** `data/tuning.json` contains the fixed top-level sections (`player, weapons, abilities, energy, drops, enemies, boss, asteroids, convoy, allies, waves, comms, feedback, damage`) populated with every numeric value from the GDD, and `data/flags.json` contains `surrender_prompts`, `isolde_interruptions`, `tarek_fall` (true) and `hunter_wasp` (false)
**When** `Config` loads them
**Then** `Config.num()`, `Config.int_()`, `Config.flag()` and `Config.section()` return correctly typed values
**And** a missing key logs `Log.error` with the key path, asserts in debug, and returns `0` / `false` / `{}`
**And** a parse failure of `tuning.json` sets a fatal-error state (`Config.load_error` message) that a boot or title scene can display

**Given** GUT 9.7.1 (`godot_4_7` branch) is copied into `game/addons/gut/` and enabled
**When** I run the headless GUT command from the architecture
**Then** `tests/unit/test_config.gd` passes (typed getters, missing-key fallback, int conversion of float JSON numbers)

### Story 1.2: Fly the Ship with the Mouse

As a player,
I want my ship to chase my cursor smoothly within the bottom of the screen,
So that I can position precisely and feel in control from the first second.

**Tier / Covers:** MUST · FR1, FR2, FR3

> **Superseded in part by Story 1.8 (decision #29):** the chase AC and the reticle AC.

**Acceptance Criteria:**

**Given** a debug sandbox scene (`scenes/sandbox/sandbox.tscn`, set as the main scene for now) containing a `World` node with the container children from the level tree and the `Player`
**When** I move the mouse
**Then** the ship moves toward the cursor in `_physics_process`, never faster than `player.max_speed` (1400 px/s), covering a 150 px cursor move in about 0.12 s without snapping
**And** the ship never rotates and is clamped to the full width and y 432–1080
**And** the movement values come from `Config`, cached in `_ready()`

**Given** the Player scene
**When** I inspect its hurtbox
**Then** it is a 24 px-diameter circle `Area2D` on the `player` layer, masking `enemies`, `asteroids` and `pickups`, centred on a ~96 px placeholder sprite (cyan/teal)

**Given** the `PauseArbiter` autoload exists with `push`, `pop`, `is_paused`, `clear` and the mouse-mode handling from the architecture
**When** gameplay is running with no pause reasons
**Then** the mouse mode is `MOUSE_MODE_CONFINED_HIDDEN` and a reticle `Sprite2D` follows `get_global_mouse_position()`
**And** when any pause reason is active, the mouse mode is `MOUSE_MODE_VISIBLE`

**Given** `tests/unit/test_pause_arbiter.gd`
**When** it pushes two reasons and pops one
**Then** the tree is still paused, and popping the second unpauses it; `clear()` removes all reasons

### Story 1.3: Fire the Laser

As a player,
I want to hold the left mouse button to stream lasers straight up,
So that I always have sustained damage against fodder.

**Tier / Covers:** MUST · FR4, FR7, FR31 (laser)

**Acceptance Criteria:**

**Given** `core/projectile.gd` (`class_name Projectile extends Area2D`) implementing the architecture's projectile contract (velocity movement in `_physics_process`, off-screen free with the bounds rect, `apply_damage` on overlap, `_on_impact` hook, then `queue_free`)
**And** a `Spawner` node (`core/spawner.gd`) plus the `EntityRegistry` autoload with preloaded scenes
**When** any gameplay entity is created
**Then** it is created only through `Spawner.spawn_*()`, which calls `setup(params)` before `add_child` into the matching `World/<Container>`

**Given** the sandbox is running and unpaused
**When** I hold LMB (`fire_laser`)
**Then** twin laser bolts spawn at 10 bolts/s (one damage instance per bolt, the twin is visual only), travel straight up at 1800 px/s, and deal 1 damage each
**And** each bolt uses a `CapsuleShape2D` of height ≥ 30 px (speed / 60), is on `player_shots`, masks `enemies`, `asteroids` and `convoy` (`MASK_PLAYER_SHOTS`), and has `monitorable = false`
**And** a muzzle flash shows on every shot
**And** bolts are freed when they leave the playfield bounds

**Given** the tree is paused
**When** I hold LMB
**Then** no bolts fire

### Story 1.4: Shoot Wasps and Asteroids in the Sandbox

As a player,
I want targets to shoot (Wasps that die and asteroids that drift, block and break),
So that the weapons have something to prove themselves against.

**Tier / Covers:** MUST · FR6, FR18, FR25 (hitbox convention)

**Acceptance Criteria:**

**Given** `core/enemy.gd` (`class_name Enemy extends Area2D`) with the architecture contract: `signal resolved` (emitted exactly once), `type_id`, `tier`, `setup(params)`, `apply_damage(amount, source)` (records `source.from_ally`), `destroy_by_contact()`, HP from `Config.int_("enemies.<type_id>.hp")`
**When** a Wasp (3 HP, on the `enemies` layer, hitbox ~80% of its sprite, magenta/red placeholder) takes 3 laser hits
**Then** it dies, emits `Events.enemy_killed` and `resolved` once, and frees itself

**Given** the asteroid scene with a size set in `setup()`
**When** small, medium and large asteroids spawn
**Then** they have 64/128/224 px diameters and 4/12/30 HP, drift down at 140/100/60 px/s, rotate at a random 10–40°/s, and free themselves after exiting the bottom
**And** they never split when destroyed and emit `Events.asteroid_destroyed`

**Given** an asteroid between the ship and a Wasp
**When** I fire lasers at the Wasp
**Then** the asteroid stops every bolt and takes 1 damage per bolt, and the Wasp takes none
**And** the `asteroids` layer is in the mask of both `player_shots` and `enemy_shots` (verified by the project's layer configuration)

**Given** the sandbox
**When** all Wasps in its formation are dead
**Then** the sandbox respawns a Wasp formation, and it spawns asteroids of random sizes at intervals so the weapons can be tested continuously

### Story 1.5: Fire Aimed Missiles with Splash Damage

As a player,
I want to right-click to launch a missile toward my cursor that splashes nearby targets,
So that I have a burst, aimable shot for formations and for curving around cover.

**Tier / Covers:** MUST · FR5, FR31 (missile), FR62 (cooldown ring)

> **Superseded in part by Story 1.8 (decision #29):** the ship→cursor direction AC and the reticle ring location.

**Acceptance Criteria:**

**Given** the missile is ready
**When** I press RMB (`fire_missile`)
**Then** a missile spawns and flies along the ship→cursor vector at 900 px/s, or straight up if the cursor is within 32 px of the ship
**And** it uses a capsule of height ≥ 15 px and shows a visible smoke trail

**Given** a missile hits a Wasp inside a formation
**When** it impacts
**Then** the hit target takes 8 damage and every other enemy and asteroid within 120 px takes 3 splash damage (the hit target does not also take splash)
**And** an asteroid hit directly takes the 8 damage and stops the missile

**Given** I just fired a missile
**When** I press RMB again within 1.5 s
**Then** nothing fires
**And** the reticle shows a radial cooldown ring (drawn with `draw_arc`) driven by `Events.missile_cooldown_changed(ratio)` from 1 (just fired) to 0 (ready)

### Story 1.6: Feel Every Impact Scale with Size

As a player,
I want explosions, screen shake, hit-stop and sound to grow with the size of what I destroy,
So that the game's feel tells me how big and dangerous each thing was.

**Tier / Covers:** MUST · FR30, FR31 · Architecture: Impact Feedback, Audio, pause/time model

**Acceptance Criteria:**

**Given** `core/impact_tier.gd`, the `Feedback` autoload, `systems/camera/shake_camera.gd` (registering itself with `Feedback` on `_ready` and unregistering on `_exit_tree`) and `tuning.json → feedback.tiers` holding every row of the GDD feedback table
**When** any entity dies or a projectile impacts
**Then** it calls only `Feedback.impact(tier, position)`, which spawns the explosion at the tier's scale with its extras (spark burst, debris, shockwave ring), applies the tier's shake and hit-stop, and plays the tier's SFX with its pitch and volume offsets

**Given** the sandbox
**When** I destroy a Wasp, a small asteroid, a medium asteroid (or land a missile), and a large asteroid
**Then** they play the Small (0.5×, no shake), Medium (1×, 4 px / 0.15 s) and Large (2×, 8 px / 0.25 s, 40 ms hit-stop, shockwave) tiers respectively

**Given** two shakes overlap
**When** the second is weaker than the remaining first
**Then** `ShakeCamera` keeps the strongest active shake, decaying linearly

**Given** two hit-stops overlap
**When** the second starts
**Then** `Engine.time_scale` stays at 0 until the longest remaining duration ends, then returns to 1.0, and no script other than `Feedback` sets `Engine.time_scale`

**Given** the `Audio` autoload with Master → Music, SFX, UI buses and a pool of 12 `AudioStreamPlayer`s
**When** more than 12 SFX play at once
**Then** the oldest player is stolen
**And** the laser zap plays with ±5% pitch jitter and the missile launch thump plays on fire (placeholder Kenney sounds are acceptable)

**Given** a level-type scene starts
**When** it becomes ready
**Then** one explosion of each tier is pre-warmed off-screen (x = -1000) so the first real explosion causes no shader-compile hitch

### Story 1.7: Validate the Core Feel in a Stress-Tested Sandbox

As the developer,
I want debug tools, a stress test and a fun check in the sandbox,
So that I know the core loop is fun and fast enough before building anything on top of it.

**Tier / Covers:** MUST · NFR1, NFR7 · Architecture: Debug Tools (F1, F5), ADR-003, E1 go/no-go gate

> **Amended 2026-10-07 (decision #34):** the fun-gate AC no longer requires a colleague; for Epic 1 the developer playtest (#28) is enough.

**Acceptance Criteria:**

**Given** a debug build
**When** I press F1
**Then** a debug overlay toggles showing FPS, frame ms, node count and enemies alive
**And** in release builds the `DebugTools` node does nothing

**Given** I edited a value in `tuning.json`
**When** I press F5 in a debug build
**Then** all JSON data reloads and the sandbox restarts with the new values

**Given** a sandbox stress mode that spawns 40 Wasps while I hold fire
**When** I run it on the dev laptop
**Then** the overlay shows frame time under 16.6 ms
**And** if it doesn't, the renderer is switched to Compatibility per ADR-003 and the neon glow still reads correctly through additive `CanvasItemMaterial` sprites
**And** the renderer decision is recorded in the GDD decision log

**Given** a 2-minute sandbox session with a respawning Wasp formation and asteroids
**When** the developer plays it
**Then** they answer "yes" to "Was the shooting fun on its own?" (the go/no-go gate)
**And** any tuning changes made are recorded in `decision-log.md`

**Given** the Godot 4.7.2 export templates are installed and a minimal Windows Desktop preset exists (with the `data/*.json` non-resource filter)
**When** I export the sandbox with the headless CLI command and run the exe from a folder outside the repo
**Then** it launches, loads `tuning.json` and the neon glow renders; any export problem is fixed now rather than in Story 8.5 (decision F19)

### Story 1.8: Lock the Ship to the Cursor and Fire Missiles Straight Up

As a player,
I want my ship to sit exactly under my mouse and my missile to fire straight ahead,
So that movement feels instant and precise and every weapon aims the same way.

**Tier / Covers:** MUST · FR1, FR3, FR5, FR62 (cooldown ring) · GDD decisions #29, #31

**Acceptance Criteria:**

**Given** gameplay is running with no pause reasons
**When** I move the mouse
**Then** in the same physics tick, the ship's position equals the cursor position clamped to x 0–1920, y `player.bounds_y.min`–`max`, with no interpolation, speed cap or lag
**And** `player.max_speed`, `player.chase_ref_distance_px` and `player.chase_ref_time_s` are removed from `tuning.json`, along with the chase solver code and its tests

**Given** I move the mouse above y 432 (in viewport coordinates)
**When** the next physics tick runs
**Then** the cursor is warped back to the zone edge (`Viewport.warp_mouse`), the ship stays on the edge, and the first downward mouse movement moves the ship at once (no dead travel)

**Given** any pause reason is popped and gameplay resumes
**When** the mouse mode returns to `MOUSE_MODE_CONFINED_HIDDEN`
**Then** the cursor is warped to the ship's current position, so the ship does not jump to where the cursor was left during the pause

**Given** the missile is ready
**When** I press RMB
**Then** the missile spawns at the ship's nose and flies straight up (`Vector2.UP`) at 900 px/s, wherever the cursor was before clamping
**And** `missile_direction` and `weapons.missile.straight_up_within_px` are removed

**Given** the Reticle scene
**When** this story is done
**Then** `reticle.tscn`/`reticle.gd` no longer exist, and the sandbox has no reticle

**Given** I just fired a missile
**When** the 1.5 s cooldown runs
**Then** a cooldown ring is drawn on top of the ship sprite (a Player child with a z-index above the sprite), no larger than the ship, in a high-contrast colour (`text` #E8F4FF with a dark `background` outline, 4–5 px stroke), sweeping clockwise from 12 o'clock over the remaining fraction and hidden when ready
**And** it is driven only by `Events.missile_cooldown_changed(ratio)` and drawn with `draw_arc`
**And** its radius, stroke and colours come from the UX token `missileRing`, with the radius and stroke as tunable data
**And** it reads clearly over the ship while firing lasers over explosions (checked by the developer in the sandbox)

**Given** the GUT suite
**When** it runs headless
**Then** tests cover: the lock places the ship on a clamped target in one tick, the zone clamp and the cursor warp decision (a pure function of the mouse position and bounds), resume-warp, straight-up missile direction, and the ring ratio handling; all pass

### Story 1.9: Make Laser Bolts and the Neon Glow Brighter

As a player,
I want my laser bolts to glow like real bullets and the whole screen to pop a little more,
So that my shots read instantly and the neon look lands.

**Tier / Covers:** MUST (tuning) · FR64 (partial), NFR10 · GDD decision #30, ADR-003

**Acceptance Criteria:**

**Given** the WorldEnvironment glow values (intensity, bloom, HDR threshold)
**When** the scene starts or F5 reloads data
**Then** they are read from `tuning.json → render.glow` (not hard-coded in `.tscn`) and applied by the scene root
**And** the first-pass values are slightly brighter than today (intensity 0.8, bloom 0.05, threshold 0.6 are the baseline)

**Given** a laser bolt
**When** it renders
**Then** its core is HDR-bright (modulate/self-modulate above 1.0, so it clearly crosses the glow threshold) with a wider additive halo, and the brightness values come from `tuning.json` (for example `weapons.laser.glow_energy`)
**And** with the WorldEnvironment glow turned off, the additive halo alone still makes the bolt read as a bullet (ADR-003 fallback)

**Given** the `--bench=20` run
**When** it runs after the change
**Then** p99 frame time stays under 16.6 ms, and the result is recorded in the story

**Given** an exported Windows build
**When** the developer runs it
**Then** the developer confirms that the bolts read as bullets and the neon is slightly brighter but not washed out (operator action), and records the final values in the decision log as a tuning note under #30

### Story 1.10: Reconcile the Architecture with the As-Built

As the developer,
I want game-architecture.md to describe the code that actually exists,
So that agents building Epic 2 onwards follow the real patterns.

**Tier / Covers:** MUST (docs) · Epic 1 retro action item 5, DW-11, DW-17

**Acceptance Criteria:**

**Given** Stories 1.8 and 1.9 are done
**When** I update `_bmad-output/game-architecture.md`
**Then** it documents, matching the code:
  - the `play_sfx` pitch parameter
  - the tier `sfx_volume_db` (decision #26)
  - the single explosion scene
  - Spawner and ShakeCamera registering with Feedback (accepted as the design, retro C1)
  - the `-- --stress` / `--bench=N` command-line modes
  - the `Playfield` class and the `PlayerWeapons` split (DW-13)
  - `Config.reload()` (DW-8)
  - the cursor lock, zone confinement and the resume-warp owner
  - the cooldown ring on the ship
  - `render.glow` data
**And** the export command shows the `--import` step first (DW-17)
**And** every section changed is listed in a short "As-built reconciliation 2026-10-xx" note at the end of the document

**Given** the updated document
**When** I grep it for `reticle`, `max_speed`, `chase` and `toward the cursor`
**Then** the only matches are in historical or superseded notes

---

## Epic 2: Enemy Roster and Scripted Waves

The player fights through data-scripted waves of Wasps, Lancers, Needles and Bastions with readable telegraphs, watching a wave progress bar fill until the level clears. The designer can author waves and triggers in JSON.

### Story 2.1: Count Wave Progress and Evaluate Beat Triggers

As the designer,
I want wave progress and beat-trigger rules implemented as small, tested logic classes,
So that waves always clear correctly and story beats fire at exactly the right moment.

**Tier / Covers:** MUST · FR27, FR28 · Architecture: `WaveProgress`, `BeatTrigger`

**Acceptance Criteria:**

**Given** `systems/waves/wave_progress.gd` (pure `RefCounted`)
**When** it is reset with a total and enemies resolve
**Then** `ratio()` returns resolved / total, `is_complete()` is true only when resolved == total, and a total reduced by a failed spawn still completes correctly

**Given** `systems/waves/beat_trigger.gd` (pure `RefCounted`) built from a trigger dictionary (`when`, optional `at`, `phase`, `hp`, `flag`, `actions`)
**When** `should_fire(event, ratio, flags)` is called
**Then** it returns true only for a matching `when` (`wave_start`, `progress` with ratio ≥ `at`, `wave_clear`, `boss_phase`, `boss_hp_le`), only if its flag passes (a `"!"` prefix negates it), and never after `has_fired` is set

**Given** `tests/unit/test_wave_progress.gd` and `tests/unit/test_beat_trigger.gd`
**When** I run the headless GUT suite
**Then** all cases pass, including negated flags, a missing flag key and a trigger that must fire only once

### Story 2.2: Play a Level Driven by Wave Data

As a player,
I want to fight through a sequence of scripted waves that each clear and lead to the next,
So that a level has a shape: rising pressure, breathing room and a clear finish.

**Tier / Covers:** MUST · FR26, FR27, FR28, FR60, FR61 · Architecture: Wave Director, `level.tscn`, error handling, debug F3/F6

**Acceptance Criteria:**

**Given** `scenes/level/level.tscn` with the fixed node tree from the architecture (Background, World and its containers, WaveDirector, ShakeCamera, WorldEnvironment, HUD, Comms, Overlay) and a level id parameter
**When** a level starts
**Then** `level.gd` loads `data/levels/level_<id>.json` through `Config.level(id)`, emits `Events.level_started`, and the WaveDirector runs wave 1

**Given** a wave entry with `spawns` (type, count, formation or entry) and optional `asteroids`, `groups` and `triggers`
**When** the wave starts
**Then** every spawn goes through the `Spawner`, counted enemies join the `counted` group and connect `resolved`, `total_counted` includes all `spawns` plus every entry in `groups`, and `Events.wave_started` fires
**And** asteroids listed for the wave spawn but are never counted

**Given** triggers with `when` = `wave_start`, `progress` or `wave_clear`
**When** their condition is met
**Then** their actions run sequentially as a chain: `spawn_group` spawns the named group and `wait` waits (pausable timer); each trigger fires at most once per attempt and is checked in array order after every resolve

**Given** every counted enemy is resolved and no action chain is running
**When** the wave clears
**Then** `Events.wave_cleared` fires, `wave_clear` triggers run, and the next wave starts after `tuning.waves.gap_s` (2.0 s)
**And** after the last wave `Events.level_cleared` fires, a placeholder "LEVEL CLEAR" banner shows, and the clear is logged at INFO

**Given** a spawn entry with an unknown enemy type
**When** the wave starts
**Then** it is logged with `Log.error` (file and key path), subtracted from `total_counted`, and the wave can still clear

**Given** `tests/data/test_data_files.gd`
**When** it runs
**Then** every level JSON in `data/levels/` is validated (known enemy types, counts > 0, valid `when` values, `at` in 0–1, referenced groups exist)

**Given** a debug build
**When** I press F3
**Then** every counted enemy in the current wave resolves and pending progress triggers fire in order
**And** F6 jumps to the boss wave if the level has one (otherwise it logs that there is none)
**And** the F1 overlay additionally shows wave n/N, resolved/total and active pause reasons

**Given** no title flow exists yet
**When** I run the project
**Then** the main scene can start a development level (`level_dev.json` with Wasp-only waves) directly

### Story 2.3: Watch the Wave Progress Bar Fill

As a player,
I want a top-centre bar showing how far through each wave I am,
So that I always know how close I am to the next breather and to the end of the level.

**Tier / Covers:** MUST · FR29, FR62 · Architecture: HUD reads only `Events`

**Acceptance Criteria:**

**Given** a level with N waves
**When** it starts
**Then** the HUD (`ui/hud/wave_bar.gd`, on the HUD `CanvasLayer`, `PROCESS_MODE_PAUSABLE`) shows one segment per wave at the top centre, sized and placed per UX-DR1/DR2

**Given** `Events.wave_progress_changed(wave_index, ratio)`
**When** enemies in the current wave are destroyed
**Then** the current segment fills to the ratio, completed segments stay full, and the bar never decreases within a level attempt

**Given** the HUD script
**When** I review it
**Then** it updates only through `Events` signals and never polls gameplay nodes, using the shared `Theme` at `ui/theme/defector_theme.tres`

### Story 2.4: Dodge Wasp Formations and Telegraphed Dives

As a player,
I want Wasps to swoop into formation and take turns diving at me after a clear warning,
So that fodder enemies create readable pressure I can react to.

**Tier / Covers:** MUST · FR19, FR25, NFR6 · Architecture: state pattern

**Acceptance Criteria:**

**Given** a wave spawns Wasps with a `formation` (e.g. `grid_4x2`) and `entry`
**When** they enter
**Then** each Wasp flies in at 350 px/s to its formation slot in the top 40% of the screen and holds it (`enum State` + `match`, transitions only via `_enter_state()`)

**Given** Wasps are holding formation
**When** 3–5 s pass (random per dive, from tuning)
**Then** one holding Wasp flashes its wings and pauses for 0.4 s, then dives at the player's position at 600 px/s

**Given** a diving Wasp exits the bottom of the screen
**When** it leaves the playfield
**Then** it re-enters from the top and returns to its slot, and it does not resolve

**Given** `tests/data/test_data_files.gd`
**When** it checks tuning
**Then** every telegraph duration in `tuning.enemies` and `tuning.boss` is ≥ 0.3 s

### Story 2.5: Face Lancers' Aimed Shots

As a player,
I want strafing Lancers that fire aimed bullets after a muzzle glow,
So that I have ranged pressure to dodge and prioritise.

**Tier / Covers:** MUST · FR20 (player targeting), FR25, NFR6

**Acceptance Criteria:**

**Given** a Lancer spawns (8 HP, medium tier)
**When** it is active
**Then** it strafes horizontally within the top 35% of the screen at 200 px/s

**Given** a Lancer's fire timer reaches 2.0 s
**When** it attacks
**Then** its muzzle glows for 0.3 s, then it fires one bullet aimed at the player's current position at 450 px/s

**Given** the shared enemy bullet scene (`enemy_bullet.tscn`)
**When** it is fired
**Then** it is magenta/red with a bright core, at least 16 px, on `enemy_shots` masking `player`, `asteroids` and `convoy`, uses a capsule ≥ speed / 60, and is stopped by asteroids
**And** on overlap it calls `apply_damage` only if the target has that method (the player gains it in Epic 3), then frees itself

### Story 2.6: Take Cover from the Needle's Sniper Shot

As a player,
I want a sniper whose targeting line warns me before a very fast shot,
So that I learn to use asteroids as cover.

**Tier / Covers:** MUST · FR21, FR25, FR6

**Acceptance Criteria:**

**Given** a Needle spawns (6 HP)
**When** it is active
**Then** it anchors at the top edge and repositions to a new anchor every 8 s

**Given** the Needle is anchored
**When** it starts an attack cycle (every 4.0 s)
**Then** a targeting line tracks the player for 1.2 s, locks and turns red for 0.3 s, then a bolt fires along the locked line at 1600 px/s
**And** the bolt uses a capsule of height ≥ 27 px so it cannot tunnel through the 24 px player hurtbox

**Given** an asteroid lies on the locked line
**When** the bolt is fired
**Then** the asteroid stops the bolt and the bolt does not reach the player

### Story 2.7: Bring Down a Bastion Gunship

As a player,
I want a slow, armoured gunship with two turrets firing spreads,
So that I must commit missiles and positioning to take down a tank.

**Tier / Covers:** MUST · FR22, FR25, FR30 (large tier)

**Acceptance Criteria:**

**Given** a Bastion spawns (40 HP, large tier)
**When** it is active
**Then** it drifts at 60 px/s within y 80–400 and stays above the player zone

**Given** each of its 2 turrets reaches its 2.5 s timer
**When** it attacks
**Then** the turret glows for 0.5 s, then fires a 3-bullet spread (±15°) at 350 px/s using the shared enemy bullet

**Given** the Bastion's HP reaches 0
**When** it dies
**Then** it plays the Large feedback tier (2×, 8 px / 0.25 s shake, 40 ms hit-stop, shockwave ring) and resolves once

**Given** the Bastion
**When** `destroy_by_contact()` would apply
**Then** it is not destroyed by contact (large enemies are excluded)

### Story 2.8: Outrun the Hunter Wasp (COULD)

As a player,
I want an orange-tinted Wasp that chases me,
So that later waves force me to keep moving.

**Tier / Covers:** COULD · FR24

**Acceptance Criteria:**

**Given** the `hunter_wasp` flag is true and a wave lists `hunter_wasp` spawns
**When** a Hunter Wasp is active
**Then** it has 3 HP, an orange tint, and chases the player at 300 px/s with a 90°/s turn limit, dealing contact damage only

**Given** the `hunter_wasp` flag is false
**When** a wave lists Hunter Wasp spawns
**Then** they are skipped, not counted toward the wave total, and logged at DEBUG

**Given** this story is cut
**When** the data test and Level 3 run
**Then** `hunter_wasp` stays a known type id (decision F14), the flag stays false, and Level 3 W2 still passes `test_data_files.gd` and clears normally

---

## Epic 3: Player Survival and Energy

The player can take hits, die and retry instantly, collect energy from wreckage and spend it on a Shield or a Barrage to survive spikes.

### Story 3.1: Take Hits with Hearts and Mercy Invulnerability

As a player,
I want 5 hearts with a short invulnerability window after each hit,
So that mistakes cost me without ending my run instantly.

**Tier / Covers:** MUST · FR9, FR10, FR11, FR30 (player hit), FR62 (hearts)

**Acceptance Criteria:**

**Given** a level starts
**When** the player spawns
**Then** they have 5 hearts (`player.hearts` from tuning), and the HUD hearts display shows 5 via `Events.hearts_changed`

**Given** the player is hit by an enemy bullet or Needle bolt
**When** `apply_damage` is called
**Then** they lose 1 heart, `Events.player_hit` fires, and the Player-hit feedback tier plays (6 px / 0.2 s shake, 50 ms hit-stop, red edge vignette on the HUD)

**Given** the player's hurtbox overlaps a small or medium enemy or a small or medium asteroid
**When** contact is detected by the Player
**Then** the player loses 1 heart and the enemy is destroyed via `destroy_by_contact()`
**And** contact with a large asteroid or a Bastion costs 2 hearts (values from `tuning.damage`)

**Given** the player was just hit
**When** further damage arrives within 1.2 s
**Then** it is ignored, and the ship flickers at 10 Hz during the window
**And** a small or medium enemy touching the ship during the window is still destroyed via `destroy_by_contact()`, at no heart cost (decision F15)

**Given** a debug build
**When** I press F2
**Then** player invincibility toggles and the overlay shows it

### Story 3.2: Die and Retry Instantly

As a player,
I want death to land with weight and then get me back into the level in one click,
So that failing feels fair and I always want one more try.

**Tier / Covers:** MUST · FR12, FR11, FR14 (reset), FR30 (player death) · Architecture: `GameState`, `SceneRouter.restart_level()`, ADR-004, Pause Arbiter `death`

**Acceptance Criteria:**

**Given** the player's hearts reach 0
**When** they die
**Then** the Player-death feedback tier plays (2×, 12 px / 0.5 s, 100 ms hit-stop), `Events.player_died` and `Events.level_failed(&"hearts")` fire, and after 1.5 s `PauseArbiter.push(&"death")` shows the retry prompt (`PROCESS_MODE_ALWAYS`) with a visible cursor, the loss reason and RETRY · QUIT TO TITLE (UX-DR5)

**Given** the `GameState` autoload (energy, `current_level_id`, `is_retry`) and the `SceneRouter` autoload with `restart_level()`
**When** I click Retry
**Then** `GameState.energy` is set to 0, `is_retry` is set, `PauseArbiter.clear()` runs and `level.tscn` reloads with the same level id
**And** the level restarts from wave 1 with 5 hearts, no leftover enemies, projectiles or running beat chains

**Given** I retry repeatedly
**When** I count attempts
**Then** there is no retry limit

### Story 3.3: Collect Energy from Wreckage

As a player,
I want destroyed enemies and asteroids to drop glowing energy orbs that drift toward me,
So that aggression and positioning feed my survival tools.

**Tier / Covers:** SHOULD · FR13, FR14, FR62 (energy bar)

**Acceptance Criteria:**

**Given** an enemy or asteroid is destroyed
**When** its drop is rolled against `tuning.drops.<type>`
**Then** it drops one gold 10-energy orb at the GDD chance (Wasp/Hunter 15%, Lancer 25%, Needle 30%, asteroid S/M/L 10/30/60%), and a Bastion always drops 2 orbs

**Given** an orb exists
**When** time passes
**Then** it drifts down at 120 px/s, is pulled toward the ship when within 160 px, and despawns after 6 s

**Given** the player touches an orb
**When** it is collected
**Then** `GameState.energy` increases by 10, capped at 100, `Events.energy_changed` fires, and the energy pickup SFX plays

**Given** the HUD
**When** energy changes
**Then** the energy bar updates and shows markers at 50 (Shield) and 100 (Barrage)

**Given** a debug build
**When** I press F4
**Then** energy increases by 100, capped at 100

### Story 3.4: Raise the Shield

As a player,
I want to spend 50 energy on a short invulnerability bubble,
So that I have an answer when a pattern can't be dodged.

**Tier / Covers:** SHOULD · FR15, FR17

**Acceptance Criteria:**

**Given** I have at least 50 energy and no active shield
**When** I press E (`ability_shield`)
**Then** 50 energy is spent and a visible bubble surrounds the ship for 4.0 s, during which every damage source, including contact damage, is ignored

**Given** the shield is active
**When** I press E again
**Then** nothing happens and no energy is spent (no stacking or refresh)

**Given** I have less than 50 energy
**When** I press E
**Then** nothing activates, `Events.ability_denied(&"shield")` fires, the "denied" SFX plays and the energy bar flashes

### Story 3.5: Unleash the Barrage

As a player,
I want to spend a full 100 energy on a volley of homing micro-missiles,
So that I have a panic button against a crowded screen.

**Tier / Covers:** SHOULD · FR16, FR17, FR31 (Barrage)

**Acceptance Criteria:**

**Given** I have 100 energy
**When** I press Q (`ability_barrage`)
**Then** all 100 energy is spent and 12 micro-missiles launch over 2.0 s (about one every 0.17 s) with a rapid whoosh cascade
**And** each deals 6 damage, is on `player_shots`, and is stopped by asteroids

**Given** a micro-missile launches
**When** enemies exist
**Then** it picks the nearest enemy once at launch and re-picks only when that target is freed (`is_instance_valid`), never scanning per frame
**And** with no enemies alive it flies straight up

**Given** the volley ends
**When** the last micro-missile has fired
**Then** a Large-tier feedback finish plays

**Given** I have less than 100 energy
**When** I press Q
**Then** nothing fires, `Events.ability_denied(&"barrage")` fires, the "denied" SFX plays and the energy bar flashes

---

## Epic 4: Game Flow, Progression and Save

The player launches into a title screen, continues where they left off, picks unlocked levels, pauses at any time and keeps their progress between sessions, in fullscreen or windowed mode.

> **Amended 2026-10-08 (decision #37):** Story 4.0 (player ship sprite) was pulled forward from Story 8.2 and opens Epic 4. It is numbered 4.0 so Stories 4.1–4.5 keep their ids.

### Story 4.0: Fly a Real Ship

As a player,
I want my ship to look like a fighter instead of a glowing circle,
So that I can read where my ship is and where its nose points at a glance.

**Tier / Covers:** SHOULD · FR64 (partial: player ship), NFR10 · GDD decision #37 (pulled forward from Story 8.2)

**Acceptance Criteria:**

**Given** the Kenney Space Shooter Redux pack (CC0)
**When** the Player scene loads
**Then** `Player/Sprite` shows a Kenney fighter hull (e.g. `playerShip1_blue.png`) stored under `game/assets/sprites/player/`, facing up (nose toward −y), instead of the radial `GradientTexture2D` circle
**And** the hull is recoloured to `coalition` cyan/teal (#22E6FF), either baked into the committed PNG or by a tint at or below 1.0, so it no longer reads as Kenney's default blue and doesn't bloom into a blob under `render.glow`
**And** the PNG's `.import` sidecar is committed, and the headless `--import` step runs before the tests (AGENTS.md section 3)

**Given** `player.sprite_px` (96) in `tuning.json`
**When** the Player runs `_ready`
**Then** the sprite is scaled uniformly so its longer side equals `player.sprite_px`, keeping its aspect ratio, with no hard-coded size
**And** the hurtbox stays the circle from `player.hurtbox_diameter_px` (24 px), centred on the hull
**And** lasers, the missile and the barrage still leave from the hull's nose (the `Muzzle` marker moved to the nose if needed), with the muzzle flash on it

**Given** the existing ship feedback
**When** I take a hit, die, raise the Shield or wait for the missile to reload
**Then** the i-frame flicker, the ship hidden on death, the shield bubble and the missile cooldown ring all still work over the new sprite, and the ring stays readable on top of it

**Given** the new art asset
**When** I check `game/assets/CREDITS.md`
**Then** it is listed under "Third-party assets" with its file, source (Kenney Space Shooter Redux, kenney.nl), licence (CC0 1.0) and a note that it was recoloured
**And** the "placeholder sprites are drawn in code" note no longer covers the player ship

**Given** the GUT suite runs headless
**When** the player tests run
**Then** a test asserts that the sprite has a non-null texture that is not a `GradientTexture2D`, and that its scaled longer side equals `player.sprite_px` within 1 px
**And** the existing player, shield-bubble and missile-ring tests still pass

**Given** the story is done
**When** I read `game-architecture.md`
**Then** it records the as-built: `assets/sprites/player/` exists, and `Player` scales the hull from `player.sprite_px`

**Given** I play the dev level (human check)
**When** I fly and fight
**Then** the ship reads at a glance as a cyan/teal fighter pointing up, distinct from enemies and pickups, with glow on

### Story 4.1: Launch into the Title Screen

As a player,
I want the game to open on a clean title screen where I can start playing or quit,
So that the game launches easily and makes sense instantly.

**Tier / Covers:** MUST · FR56 (Play, Quit), NFR2 · Architecture: `boot.tscn`, `SceneRouter`, fatal error handling

**Acceptance Criteria:**

**Given** `scenes/boot/boot.tscn` is the main scene
**When** the game starts
**Then** it confirms `Config` loaded and calls `SceneRouter.goto_title()`

**Given** `tuning.json` failed to parse
**When** the title screen opens
**Then** it shows a plain error label with the `Config.load_error` message and does not allow starting a level

**Given** Epic 7 has not built the real levels yet
**When** this story is implemented
**Then** placeholder `data/levels/level_1.json`, `level_2.json` and `level_3.json` exist, each with a `name` ("Cargo Ambush", "The Blockade", "Siege of the Throne World") and 1–2 short Wasp waves, and they pass `test_data_files.gd`; Stories 7.1, 7.2 and 7.6 replace their content (decision F12)

**Given** the title screen
**When** I click Play
**Then** `SceneRouter.start_level(id)` loads `level.tscn` for Level 1, sets `GameState.current_level_id` and clears `is_retry`
**And** Quit exits the application

**Given** `SceneRouter` with `goto_title()`, `start_level(id)` and `restart_level()`
**When** any scene change happens
**Then** it calls `PauseArbiter.clear()` first, and menu scenes set the gameplay mouse mode to visible

**Given** a cold launch from the CLI run command on the dev laptop
**When** I time it
**Then** the title screen appears in under 5 s (the exported build is re-checked in Story 8.3)

### Story 4.2: Unlock the Next Level and Save Progress

As a player,
I want clearing a level to unlock the next one and save my progress and energy,
So that I can stop and come back without replaying what I've beaten.

**Tier / Covers:** MUST · FR58, FR14, FR56 (continue) · Architecture: `SaveManager`, save rules

**Acceptance Criteria:**

**Given** the `SaveManager` autoload is the only code that touches `user://save.cfg`
**When** the game boots with no save file
**Then** defaults load: `highest_unlocked_level = 1`, `energy = 0`

**Given** a corrupt save file or an unknown `save_version`
**When** the game boots
**Then** `Log.warn` is written, defaults are used, and the game does not crash

**Given** I clear Level N (N < 3)
**When** `Events.level_cleared(N)` fires
**Then** `GameState.highest_unlocked_level` becomes max(current, N + 1), `SaveManager.save()` writes `[progress] save_version=1, highest_unlocked_level, energy` to `%APPDATA%\DEFECTOR\save.cfg`, and `SceneRouter` starts Level N + 1 carrying the current energy
**And** saving happens at no other time

**Given** I clear Level 3
**When** the save is written
**Then** I return to the title screen (the end screen arrives in Epic 7)

**Given** a saved game
**When** I click Play on the title screen
**Then** the highest unlocked level starts with the saved energy

**Given** I quit to the title mid-level (after earning or spending energy, or after dying)
**When** `SceneRouter.goto_title()` runs
**Then** `GameState.energy` and `highest_unlocked_level` are restored from `SaveManager`, so the next Play or Level Select starts with the last saved energy, never an in-memory mid-level value (decision F13)

**Given** `tests/unit/test_save_manager.gd`
**When** it runs
**Then** round-trip, missing-file, corrupt-file and unknown-version cases pass (using a test path, never the real save)

**Given** a debug build
**When** I press F7
**Then** all levels unlock in memory without writing the save

### Story 4.3: Choose a Level from Level Select

As a player,
I want a level select screen showing which levels I've unlocked,
So that I can replay a level I enjoyed.

**Tier / Covers:** MUST · FR56 (Level Select)

**Acceptance Criteria:**

**Given** the title screen
**When** I click Level Select
**Then** `level_select.tscn` shows Levels 1–3 by name, with locked levels greyed out and not clickable

**Given** I pick an unlocked level
**When** it loads
**Then** it starts with the saved energy

**Given** the level select screen
**When** I click Back
**Then** I return to the title screen

### Story 4.4: Pause the Game with Esc

As a player,
I want Esc to pause the game with options to resume, restart or quit,
So that I can step away or bail out of a bad attempt.

**Tier / Covers:** MUST · FR57, FR8 (pause) · Architecture: Pause Arbiter `menu` reason

**Acceptance Criteria:**

**Given** a level is running
**When** I press Esc
**Then** `PauseArbiter.push(&"menu")` pauses the game, the pause menu shows Resume, Restart Level and Quit to Title, the cursor is visible, and the HUD and screen shake freeze

**Given** the pause menu is open
**When** I click Resume (or press Esc again)
**Then** only the `menu` reason is removed, and the game resumes unless another reason is active
**And** when gameplay resumes, the cursor is back on the ship and the ship has not moved (Story 1.8 resume-warp)

**Given** the pause menu is open
**When** I click Restart Level
**Then** energy resets to 0 and the level reloads from wave 1 via `SceneRouter.restart_level()`

**Given** the pause menu is open
**When** I click Quit to Title
**Then** `SceneRouter.goto_title()` runs and nothing is saved

**Given** the `death` or `final_choice` pause reason is active
**When** I press Esc
**Then** the pause menu does not open

### Story 4.5: Play Fullscreen or Windowed

As a player,
I want the game to start in borderless fullscreen and let me switch to a window,
So that it fits my setup without distorting the playfield.

**Tier / Covers:** MUST · FR59

**Acceptance Criteria:**

**Given** a fresh launch
**When** the game opens
**Then** it is borderless fullscreen

**Given** any scene, in debug or release builds
**When** I press F11
**Then** the window toggles between borderless fullscreen and windowed (not persisted)

**Given** a display or window that isn't 16:9
**When** the game renders
**Then** the 1920×1080 playfield scales uniformly with letterbox bars, the ship still sits exactly on the cursor, and the cursor stays confined to the player zone (warps use viewport coordinates)

---

## Epic 5: Comms and Story Delivery

The player hears the story without ever leaving the action: an opening comms scene, paused story lines, live combat chatter, Isolde's interruptions, the surrender prompt and the mid-sentence cut-off.

### Story 5.1: Read Story Lines on the Comms Panel

As a player,
I want story lines to pause the action and appear with a portrait, a name and typewriter text,
So that I can read the important beats without being shot.

**Tier / Covers:** MUST · FR37, FR38 (story), FR39, FR8 (comms advance) · Architecture: Comms Channel

**Acceptance Criteria:**

**Given** dialogue files in `data/dialogue/` with `sequences` keyed by id (`mode`: `story` or `combat`, `lines` with `speaker` and `text`)
**When** `Config` loads them
**Then** `Config.sequence(id)` and `Config.dialogue_is_story(id)` work, and `test_data_files.gd` validates every sequence (known speaker ids `vale, isolde, tarek, ryn, system`, valid mode, non-empty lines)

**Given** a story sequence is requested via `Events.comms_sequence_requested`
**When** the `CommsChannel` (`PROCESS_MODE_ALWAYS`, under the `Comms` CanvasLayer) plays it
**Then** `PauseArbiter.push(&"story")` pauses the game, the playfield dims, the comms open SFX plays, and the centred story `CommsPanel` (styled as a conversation, no buttons, with a "click to continue" cue; layout per the UX spec) shows the speaker's portrait, name and text typing at `tuning.comms.chars_per_s` (45)

**Given** a line is still typing
**When** I click (`comms_advance`)
**Then** the line completes instantly; clicking again goes to the next line, and after the last line `PauseArbiter.pop(&"story")` runs and `Events.comms_sequence_finished(id)` fires
**And** the click is consumed with `set_input_as_handled()` so it never fires the laser

**Given** a story line is showing
**When** I press Esc and then close the pause menu
**Then** the game stays paused for the story line

**Given** an unknown sequence id is requested
**When** the channel receives it
**Then** it logs `Log.error` and immediately emits `comms_sequence_finished` so nothing waits forever

**Given** this story's scope
**When** the panel is built
**Then** only `CommsChannel` sets dialogue text, and placeholder portraits are acceptable until Epic 8

### Story 5.2: Hear Combat Chatter Without Stopping the Fight

As a player,
I want rare one-line interruptions to play while I keep fighting,
So that the story keeps moving without breaking the action.

**Tier / Covers:** MUST · FR38 (combat) · Architecture: comms priority rules (R9)

**Acceptance Criteria:**

**Given** a combat sequence is requested
**When** it plays
**Then** the game is not paused, the line shows in the small top-left interruption box (layout per the UX spec), clicks are ignored by it, and each line stays for `max(combat_line_min_s, chars / chars_per_s + combat_line_extra_s)` seconds (5.0 and 3.0 since GDD decision #41; first built as 2.0 and 1.2) before advancing

**Given** a combat line is playing
**When** a story sequence is requested
**Then** the story sequence preempts it, and the dropped combat sequence still emits `comms_sequence_finished`

**Given** a combat sequence is playing
**When** more combat sequences are requested
**Then** they queue FIFO up to 3, dropping the oldest beyond that

**Given** a story sequence is playing
**When** another story sequence is requested
**Then** it queues and is never dropped

**Given** `test_data_files.gd`
**When** it checks level JSONs
**Then** each level has at most 2 interruption (`combat`) comms triggers, excluding the cut-off line, and every `combat` sequence has exactly 1 line of at most 50 characters (GDD decision #22; UX spec interruption box)

### Story 5.3: Trigger Dialogue and Music from Wave Events

As the designer,
I want level data to fire comms lines, story events and music changes at wave moments,
So that the whole story can be scripted in JSON without code changes.

**Tier / Covers:** MUST · FR28, FR39, FR61 · Architecture: Wave Director actions `comms`, `story_event`, `music`

**Acceptance Criteria:**

**Given** a trigger with a `comms` action
**When** it runs
**Then** the WaveDirector emits `Events.comms_sequence_requested`, and if the sequence is story mode, the chain awaits its `comms_sequence_finished` before the next action; combat sequences don't block

**Given** a trigger with a `story_event` action
**When** it runs
**Then** `Events.story_event_requested(event_name)` fires

**Given** a trigger with a `music` action (`stop`, `combat`, `boss`)
**When** it runs
**Then** `Audio.apply_music_action()` plays, stops (with a 0.5 s fade) or switches the music; a missing music stream logs a warning and stays silent

**Given** a level JSON with `intro_sequence` and `outro_sequence`
**When** the level starts or its last wave clears
**Then** the intro plays before wave 1, except when `GameState.is_retry` is set (retry or restart skips the briefing), and the outro plays before `Events.level_cleared`

**Given** a wave whose enemies are all resolved while a story chain is still running
**When** the clear is evaluated
**Then** the wave clears only after the chain finishes

**Given** a death in the middle of a chain
**When** the level reloads
**Then** no chain from the previous attempt continues

### Story 5.4: Cut a Line Off Mid-Sentence

As a player,
I want a comms line to stop mid-word with static, a shake and then silence,
So that a character's sudden loss hits hard without a cutscene.

**Tier / Covers:** MUST · FR40 · Architecture: cut-off rules, silence flag

**Acceptance Criteria:**

**Given** a line with `cut_off_at` and `after` effects (`silence`, `shake`, `sfx`, `music`)
**When** it types out
**Then** the typewriter stops at exactly `cut_off_at` characters, the static burst SFX plays, the named shake fires through `Feedback`, the music stops, and the panel hides after 0.6 s (amended by GDD decision #43: a cut-off line types at 16 chars/s, ends in `...`, uses the dedicated `cutoff` shake, and the box holds 2.5 s, the length of the softened static (which has a 0.2 s end fade), then hides with no fade)

**Given** silence is `until_wave_clear`
**When** further combat sequences are requested
**Then** they are dropped (logged at DEBUG), while story sequences are still delivered
**And** the silence clears on `Events.wave_cleared`

**Given** a dev level with a cut-off trigger at a progress ratio
**When** I play it, or press F3
**Then** the cut-off fires at that moment and the wave still clears normally

### Story 5.5: Open the Campaign with the Comms Sequence

As a player,
I want the campaign to begin with characters introducing themselves over comms,
So that I know who I am and who I'm fighting before the first shot.

**Tier / Covers:** MUST · FR41 · Architecture: `story.tscn`, `SceneRouter.goto_story(id, next)`, R15

**Acceptance Criteria:**

**Given** `scenes/story/story.tscn` with a static space background and the comms panel
**When** `SceneRouter.goto_story(&"opening_main", next_level = 1)` runs
**Then** the `opening_main` story sequence (6–10 lines) plays with the cursor visible and click-to-advance, and on finish the router starts Level 1

**Given** the opening sequence data
**When** I read it
**Then** it establishes Vale's defection, Tarek welcomes the General and briefs the convoy mission, and Isolde speaks one cold line in her own voice; there is no narrator and no text crawl (placeholder text allowed until Story 5.7)

**Given** I start Level 1 fresh from Play or Level Select
**When** the level would load
**Then** the opening plays first (confirmed by the user 2026-10-06: it replays every time Level 1 is started from Play or Level Select, but never on retry or restart)

**Given** I retry or restart Level 1
**When** it reloads
**Then** the opening does not play

### Story 5.6: Let Isolde Interrupt and Tempt Surrender (SHOULD)

As a player,
I want Isolde to cut into the comms with taunts and an offer to come home,
So that the antagonist feels present in every fight and the finale's mirror lands.

**Tier / Covers:** SHOULD · FR42, FR43, FR61 (flags)

**Acceptance Criteria:**

**Given** the dialogue data
**When** I review it
**Then** combat sequences `l1_w3_isolde_interrupt`, `l2_w3_isolde_interrupt` and `l3_w3_isolde_taunt` and the story sequence `l1_w5_surrender` ("You're outnumbered, General. Come home.", no choice) exist

**Given** a trigger pattern documented for level authors: Isolde interruptions gated by `"flag": "isolde_interruptions"`; the surrender prompt as a paired trigger (`"flag": "surrender_prompts"` → comms then `spawn_group`, and `"flag": "!surrender_prompts"` → `spawn_group` only)
**When** I set either flag to false in `flags.json` (and reload with F5)
**Then** that beat no longer fires, no scripts change, and reinforcements still arrive

**Given** a dev level using both patterns
**When** I play it with flags on
**Then** the interruption plays as a combat line without pausing, and the surrender line pauses the game and then the reinforcements spawn

### Story 5.7: Write the Dialogue Script

As the designer,
I want every comms line written in final form,
So that the story beats carry their emotional weight in the shipped game.

**Tier / Covers:** MUST (content) · FR45, FR41, FR44

**Acceptance Criteria:**

**Given** the dialogue files
**When** the script is complete
**Then** final text exists for: `opening_main`; `l1_w3_tarek_warning` (ambush warning, one line) and `l1_tarek_closing`; Isolde's interruptions and surrender line; the Level 2 briefing (2–3 story lines); `l2_w5_tarek_cutoff` with its `cut_off_at`; `l2_ryn_report`; the Level 3 briefing `l3_briefing` (Ryn takes command); `l3_final_choice` (Isolde's lead-in); `l3_isolde_refuse_surrender` (contempt, echoing "Come home"); `l3_isolde_refuse_destroy` (defiance); and `l3_isolde_final`

**Given** the cast rules
**When** I review the script
**Then** Vale is gender-neutral and addressed as "General", speaks only a few lines (including the surrender offer), every character introduces themselves in their own voice, and the tone is personal, not comedic

**Given** `test_data_files.gd`
**When** it runs
**Then** every sequence id referenced by any level JSON exists in the dialogue data

### Story 5.8: Learn the Controls from On-Screen Hints

As a player,
I want short key prompts to appear the first time I need each control,
So that I learn to play without reading dialogue mid-fight.

**Tier / Covers:** MUST · FR66, NFR8

**Acceptance Criteria:**

**Given** a trigger with a `hint` action (`move_fire` shows `MOVE THE MOUSE TO FLY` then `[HOLD LMB] FIRE` in sequence; `missile`) or the first `Events.energy_changed` reaching 50 / 100 (`shield`, `barrage`)
**When** it runs
**Then** a short key prompt (e.g. "Hold LMB to fire", "RMB: Missile", "E: Shield", "Q: Barrage") shows in the hint slot defined by the UX spec, without pausing and without using the comms panel

**Given** a hint is showing
**When** the player performs that action, or 5 s pass
**Then** the hint fades out, and that hint never shows again this session (including after a retry)

**Given** the energy stories (3.3–3.5) were cut
**When** energy events never fire
**Then** the E/Q hints never show

---

## Epic 6: Escort and Allies

The player protects a convoy from Mauls and Lancers, flies alongside Tarek and Ryn, and lives through Tarek's fall at the Blockade.

### Story 6.1: Protect the Convoy

As a player,
I want three cargo ships crossing the screen with a shared health bar I must keep above zero,
So that the escort mission adds a second thing to care about besides myself.

**Tier / Covers:** MUST · FR32, FR33 (loss), FR7, FR62 (convoy bar)

**Acceptance Criteria:**

**Given** a level JSON with `"convoy": true`
**When** the level starts
**Then** three medium cargo ships (~160×80 px, hitbox ~80% of the sprite) spawn in `World/Allies` in a tight triangle (lead + two flankers) and cross left to right as one group at 40 px/s within y 760–920, then loop back, on the `convoy` layer

**Given** the convoy
**When** I check its health
**Then** it has one shared 100 HP pool shown on a HUD convoy bar via `Events.convoy_hp_changed`, carrying across waves and refilled only by a level restart

**Given** player lasers, missiles, Barrage micro-missiles or ally shots reach a convoy ship
**When** they overlap it
**Then** the shot is stopped and frees itself, the convoy takes no damage (`player_shots` masks `convoy` only to be blocked), 

**Given** the player moves the ship into a convoy ship
**When** they overlap
**Then** the Player (through a separate ~64 px `HullArea` circle that masks only `convoy`; the 24 px hurtbox is unchanged) stops at the hull. Its move from the previous position to the cursor target is swept against `convoy`, so a fast flick can't jump through a cargo ship. The ship pushes out along the shortest separation, slides along the hull, and takes no damage
**And** whenever the convoy blocks or pushes the ship, the cursor is warped to the ship's position, so the ship and cursor stay locked (GDD decisions #25, #29)
**And** the ship is never pinned: if the push-out and the zone clamp disagree, the push-out wins along y (the convoy moves only horizontally)

**Given** a convoy-aimed Lancer bullet
**When** the player's ship is between it and the convoy
**Then** the bullet hits the player (1 heart, subject to i-frames and Shield) and the convoy takes nothing

**Given** convoy HP reaches 0
**When** the loss is detected
**Then** `Events.level_failed(&"convoy")` fires and the same retry flow as death runs (prompt, then restart from wave 1 with energy reset)

### Story 6.2: Stop the Mauls Before They Hit the Convoy

As a player,
I want suicide divers that ignore me and rush the convoy,
So that I have to prioritise targets to protect the cargo.

**Tier / Covers:** MUST · FR23

**Acceptance Criteria:**

**Given** a Maul spawns (6 HP, medium tier) with entry `sides`
**When** it appears
**Then** it enters from the side with a red engine trail and an alarm ping SFX, then dives straight at the nearest convoy ship at 400 px/s

**Given** the Maul overlaps a convoy ship
**When** it detects the convoy (its mask includes `convoy`)
**Then** it calls `convoy.apply_damage(10)`, plays its death feedback, resolves and self-destructs

**Given** the Maul misses (exits the playfield) or there is no convoy in the level
**When** its dive ends
**Then** it emits `resolved` without a kill and frees itself, counting as cleared

**Given** the Maul is diving
**When** the player moves
**Then** the Maul does not steer toward the player (it only targets the convoy)

**Given** a Maul is destroyed
**When** it was killed by the player or an ally (including by body-block)
**Then** it rolls `tuning.drops.maul` (25%) like any enemy; a Maul that hits the convoy or misses drops nothing (decision F18)

**Given** the Maul overlaps the player
**When** the Player detects the contact
**Then** the player loses 1 heart (medium-enemy contact, subject to i-frames and Shield), the Maul is destroyed via `destroy_by_contact()` and resolves, and the convoy takes no damage (body-blocking, decision F6)

### Story 6.3: Defend the Convoy from Lancer Fire

As a player,
I want Lancers in Level 1 to split their fire between me and the convoy,
So that I can't protect the cargo by just dodging.

**Tier / Covers:** MUST · FR20 (convoy targeting), FR33

**Acceptance Criteria:**

**Given** a level with a convoy
**When** a Lancer fires
**Then** it aims at the player or at a random convoy ship with 50/50 odds; convoy-aimed bullets set `targets_convoy = true`

**Given** a bullet with `targets_convoy == true` overlaps a convoy ship
**When** it hits
**Then** the convoy loses 5 HP and the bullet frees itself

**Given** any other enemy shot (player-aimed Lancer bullet, Bastion spread, Needle bolt) overlaps a convoy ship
**When** it overlaps
**Then** it is stopped, frees itself, and the convoy loses `damage.convoy_stray` (2) HP (GDD decision #23)

**Given** a level without a convoy
**When** a Lancer fires
**Then** it always aims at the player

### Story 6.4: Fly Alongside Tarek and Ryn (SHOULD)

As a player,
I want an invincible ally ship patrolling beside me and picking off enemies,
So that I feel part of a squadron without the ally carrying the fight.

**Tier / Covers:** SHOULD · FR34, FR7

**Acceptance Criteria:**

**Given** a level JSON with `"ally": "tarek"` or `"ally": "ryn"`
**When** the level starts
**Then** the matching cyan/teal ally ship patrols a scripted horizontal path within y 620–760 at 150 px/s on the `allies` layer

**Given** enemies are alive
**When** the ally's 0.5 s fire timer elapses
**Then** it re-acquires the nearest enemy and fires a 1-damage shot on the `player_shots` layer with `from_ally = true`; kills report `by_ally = true` in `Events.enemy_killed`

**Given** enemy shots or the player overlap the ally
**When** they touch
**Then** the ally takes no damage and blocks nothing

**Given** a full playthrough of a level
**When** I count kills in the log
**Then** allies account for roughly 10–15% of kills; if not, the fire rate is tuned in `tuning.allies` (not code) and the change is logged in the decision log

### Story 6.5: Lose Tarek at the Blockade (SHOULD, last to cut)

As a player,
I want Tarek to shield me, be cut off mid-sentence and fall out of the fight,
So that the mentor's loss becomes the moment I remember.

**Tier / Covers:** SHOULD (last to cut) · FR35

**Acceptance Criteria:**

**Given** the `tarek_fall` flag is true and Tarek is the ally
**When** `Events.story_event_requested(&"tarek_fall")` fires
**Then** Tarek's ship moves over Vale with a shield flash, swaps to the damaged variant, trails fire, stops firing and exits the screen, and it does not return for the rest of the level

**Given** a dev level wave with a progress trigger running `story_event: tarek_fall` and `comms: l2_w5_tarek_cutoff`
**When** the trigger fires
**Then** the cut-off line plays as an interruption (no pause) and is cut mid-sentence, a Large-tier shake fires, the music drops out, and the comms stay silent until the wave clears

**Given** the `tarek_fall` flag is false
**When** the wave reaches the trigger
**Then** nothing happens, Tarek keeps flying, and the wave still clears

---

## Epic 7: The Campaign: Three Levels and the Flagship

The player plays the full campaign from Cargo Ambush to the Siege of the Throne World, defeats Isolde's Flagship across three phases, makes the Final Choice and sees the war end.

### Story 7.1: Play Level 1: Cargo Ambush

As a player,
I want the first level to teach me the controls and then spring an ambush on the convoy,
So that I learn by playing and feel the stakes rise.

**Tier / Covers:** MUST · FR46, FR44 (Level 1), FR42, FR43, FR66, NFR8

**Acceptance Criteria:**

**Given** `data/levels/level_1.json` (`background: space_1`, `music: combat`, `convoy: true`, `ally: tarek`, `outro_sequence: l1_tarek_closing`)
**When** I play it
**Then** the waves match the GDD: W1 8 Wasps (slow formation); W2 10 Wasps + 3 small + 1 medium asteroid; W3 12 Wasps, 2 Lancers, 3 Mauls; W4 10 Wasps, 4 Lancers; W5 16 Wasps and 3 Lancers with a `reinforcements` group of 4 Mauls

**Given** the Level 1 beats
**When** the waves run
**Then** control hints show in W1 (move, hold LMB) and W2 (RMB missile), and the E/Q hints show when energy first reaches 50/100 (not shown if Stories 3.3–3.5 were cut); Tarek's ambush warning plays at W3 start and Isolde's interruption at 25% of W3; at 30% of W5 the surrender prompt pauses the game and then the 4 Mauls arrive (paired flag triggers); and Tarek's closing line plays on clear

**Given** both flags off
**When** I play Level 1
**Then** it is still completable and the Mauls still arrive in W5

**Given** a full run with the F1 overlay
**When** I play from wave 1 to clear
**Then** no wave soft-locks, and the level takes about 3–4 minutes plus dialogue

### Story 7.2: Play Level 2: The Blockade

As a player,
I want a level of tanks and snipers that forces me to use cover, ending with Tarek's fall,
So that the middle of the campaign tests my skills and breaks my heart.

**Tier / Covers:** MUST · FR47, FR44 (Level 2), FR35, FR42

**Acceptance Criteria:**

**Given** `data/levels/level_2.json` (`background: space_2`, `ally: tarek`, `convoy: false`, an intro briefing of 2–3 Tarek story lines)
**When** I play it
**Then** the waves match the GDD: W1 2 Needles, 6 Wasps, 2 medium + 1 large asteroid; W2 1 Bastion, 8 Wasps; W3 3 Needles, 3 Lancers, 2 medium asteroids; W4 2 Bastions, 10 Wasps, 1 large asteroid; W5 2 Bastions, 2 Needles, 4 Lancers, 2 medium asteroids
**And** every wave containing Needles includes at least 2 medium or large asteroids

**Given** the Level 2 beats
**When** the waves run
**Then** Isolde's interruption plays in W3; at 50% of W5 the `tarek_fall` story event and the `l2_w5_tarek_cutoff` line fire together; and on W5 clear `l2_ryn_report` plays as a story line before the level clears

**Given** the `tarek_fall` flag is off
**When** W5 reaches 50%
**Then** no fall happens and Ryn's report still plays

### Story 7.3: Face the Flagship's Turrets (Phase 1)

As a player,
I want the Flagship to arrive and shield its core behind four turrets,
So that the final fight opens with a clear first objective.

**Tier / Covers:** MUST · FR49, FR52, FR53, FR30 (boss part) · Architecture: boss wave, Phase enum

**Acceptance Criteria:**

**Given** a wave entry `{ "boss": "flagship", "triggers": [...] }`
**When** the WaveDirector reaches it
**Then** the wave total is 1, `Events.boss_started` fires, the Flagship spawns through the `Spawner` and enters `ARRIVING` then `TURRETS`, and the wave resolves only on `Events.boss_defeated`

**Given** Phase 1
**When** it runs
**Then** 4 turrets with 25 HP each fire 3-bullet spreads at 350 px/s every 3.0 s, staggered, each after a 0.5 s glow; the core is invulnerable; and 2 medium asteroids drift through as cover

**Given** a turret is destroyed
**When** it dies
**Then** it plays the Boss-part tier (1.5×, 6 px / 0.2 s, 30 ms) and always drops an energy orb

**Given** the player touches the Flagship hull
**When** contact is detected
**Then** the player loses 2 hearts

**Given** the boss fight starts
**When** the HUD updates
**Then** the boss bar replaces the wave bar, showing combined remaining HP (turrets 100 + core 200) via `Events.boss_hp_changed`, with markers at the turret/core boundary and at 50 core HP (decision F8)

**Given** a debug build in a level with a boss wave
**When** I press F6
**Then** the level jumps straight to the boss wave

### Story 7.4: Break the Exposed Core (Phase 2)

As a player,
I want the core to open up and fight back with radial bursts and Wasp launches,
So that the fight escalates once I've stripped its defences.

**Tier / Covers:** MUST · FR50

**Acceptance Criteria:**

**Given** all 4 turrets are destroyed
**When** the Flagship enters `CORE`
**Then** `Events.boss_phase_changed(2)` fires and the 200 HP core becomes damageable

**Given** Phase 2 is active
**When** 3.0 s pass
**Then** the core glows for 0.6 s, then fires a 12-bullet radial burst at 300 px/s

**Given** Phase 2 is active
**When** 10 s pass
**Then** the Flagship requests 5 Wasps through the `Spawner`, never exceeding 10 boss-launched Wasps alive
**And** those Wasps are not counted toward the wave and drop energy at the normal Wasp rate
**And** launches stop once the Flagship leaves `CORE` (Final Choice onward); Wasps already alive remain (decision F16)

### Story 7.5: Make the Final Choice (Phase 3)

As a player,
I want the fight to stop so I can offer Isolde surrender or vow to destroy her,
So that the finale mirrors her offer from Level 1 and ends on her refusal.

**Tier / Covers:** MUST · FR51, FR54 (boss death), FR30 (boss death) · Architecture: Final Choice, `final_choice` pause reason

**Acceptance Criteria:**

**Given** the core is in Phase 2
**When** its HP drops to ≤ 50
**Then** its HP is clamped to 50 and it becomes invulnerable (decision F7), it enters `FINAL_CHOICE`, and `l3_final_choice` is requested (Isolde speaks as a story line)

**Given** a sequence with a `choice` block (`options` with `id`, `label`, `next`)
**When** the `CommsChannel` finishes its lines
**Then** it shows the `FinalChoice` control instead of emitting `finished`, and emits `finished` only after the chosen `next` sequence completes

**Given** Isolde's lead-in line finishes
**When** the `FinalChoice` control appears
**Then** `PauseArbiter.push(&"final_choice")` keeps combat paused, two large centred buttons, [Offer Surrender] and [Destroy Her], are shown with no timer, and Esc does not open the pause menu

**Given** I click an option
**When** the choice is made
**Then** `Events.final_choice_made` fires, the choice is stored in `GameState.final_choice`, the `final_choice` reason is popped, and the matching response sequence plays (`l3_isolde_refuse_surrender` or `l3_isolde_refuse_destroy`), each opening with Vale's short line (the surrender offer or the vow) before Isolde's refusal (decision F17)

**Given** the response sequence finishes
**When** the Flagship enters `DESPERATE`
**Then** the core becomes damageable again and pulses red; it fires 2 alternating radial bursts (300 px/s) every 1.5 s after a 0.4 s glow and an aimed 3-bullet spread (400 px/s) every 2.0 s after a 0.3 s glow

**Given** the core's HP reaches 0
**When** the Flagship enters `DYING`
**Then** `Feedback.boss_death(pos)` plays 4× chain explosions over 2 s, a 20 px / 1.0 s shake, a 150 ms hit-stop and a white flash, then `Events.boss_defeated` fires

### Story 7.6: Play Level 3: Siege of the Throne World

As a player,
I want a final level that throws everything at me before the Flagship engages, with the throne world looming behind,
So that the campaign builds to a climax.

**Tier / Covers:** MUST · FR48, FR44 (Level 3), FR42, FR64 (throne-world reveal)

**Acceptance Criteria:**

**Given** `data/levels/level_3.json` (`ally: ryn`, a background with the throne-world planet arc, `music: combat` then a `music: boss` action on the boss wave)
**When** I play it
**Then** the waves match the GDD: W1 4 Lancers, 12 Wasps; W2 2 Bastions, 2 Needles, 3 medium asteroids (+4 Hunter Wasps only if the `hunter_wasp` flag is on; if Story 2.8 was cut, the flag stays false and the entry is skipped and not counted, per decision F14); W3 20 Wasps, 3 Lancers, 1 Bastion; then the Flagship boss wave

**Given** the Level 3 beats
**When** the waves run
**Then** `l3_briefing` (Ryn takes command) plays as the level intro before W1, and Isolde's taunt plays in W3

**Given** Levels 1 and 2
**When** I look at their backgrounds
**Then** the throne world does not appear (it is a Level 3 reveal; placeholder art is acceptable until Epic 8)

### Story 7.7: End the War: Isolde's Final Line and the End Screen

As a player,
I want Isolde's last words and an end screen after the Flagship falls,
So that the campaign closes with a clear ending.

**Tier / Covers:** MUST · FR54, FR60

**Acceptance Criteria:**

**Given** the boss wave resolves on `boss_defeated`
**When** Level 3's outro runs
**Then** `l3_isolde_final` plays as a story line, then `Events.level_cleared(3)` fires and the save is written

**Given** Level 3 is cleared
**When** `SceneRouter.goto_end()` runs
**Then** `scenes/end/end_screen.tscn` shows an ending screen (title, a short closing line, "Thanks for playing") with a button back to the title, replacing the temporary return-to-title from Story 4.2

**Given** a full Level 3 run with all flags on
**When** I play from wave 1 to the end screen
**Then** no phase soft-locks, and the Final Choice, the refusal and the final line each fire exactly once

### Story 7.8: Hear the Council Epilogue (COULD)

As a player,
I want a short council scene after the war,
So that the story has a moment of resolution after Isolde falls.

**Tier / Covers:** COULD · FR55

**Acceptance Criteria:**

**Given** a `council_epilogue` flag (added to `flags.json`) is true
**When** Level 3 is cleared
**Then** `SceneRouter.goto_story(&"ending_council", next = end)` plays a short story sequence from `data/dialogue/ending.json` before the end screen

**Given** `GameState.final_choice`
**When** the epilogue plays
**Then** at most one line may reference the choice the player made

**Given** the flag is false
**When** Level 3 is cleared
**Then** the end screen shows directly

---

## Epic 8: Polish and Release

Anyone can download DEFECTOR from GitHub and play a polished, stable build with full audio, final art and smooth performance.

### Story 8.1: Make the Game Sound Right

As a player,
I want punchy, size-scaled sound effects and optional music,
So that every shot and explosion feels as big as it looks.

**Tier / Covers:** SHOULD · FR63, FR31, NFR10

**Acceptance Criteria:**

**Given** free CC0 or free-licence sources (Kenney Sci-fi Sounds first)
**When** the sound pass is complete
**Then** about 15–20 cues are registered in `Audio`, including laser zap, missile launch, explosions per tier, player hit, energy pickup, ability denied, Shield on, Barrage whoosh, Needle lock, Maul alarm, comms open and comms static
**And** explosion volume and pitch scale with the tier via `tuning.feedback`

**Given** optional combat and boss tracks are included
**When** levels and the boss wave play
**Then** the right track plays, and the music drops out during Tarek's silence beat

**Given** every new audio file
**When** I check `game/assets/CREDITS.md`
**Then** its source and licence are listed

### Story 8.2: Make the Game Look Neon

As a player,
I want a coherent neon look with clear colour language,
So that I can read friend, foe, pickup and hazard at a glance.

**Tier / Covers:** SHOULD · FR64, NFR10

**Acceptance Criteria:**

**Given** the Kenney space packs recoloured to the palette
**When** the art pass is complete
**Then** Coalition ships (allies and convoy; the player ship is already done in Story 4.0, decision #37) are cyan/teal, Sovereignty enemies and all enemy projectiles are magenta/red, energy orbs are gold, and asteroids are desaturated grey-brown with a rim light
**And** the player ship from Story 4.0 is kept, and is only re-tinted if the final palette pass changes `coalition`

**Given** the asset list
**When** I check the project
**Then** it includes 2 space backgrounds, the throne-world planet arc (Level 3 only), portraits for Isolde, Tarek and Ryn (Vale optional), Tarek's damaged ship variant, the Flagship hull, turrets and core, and the HUD elements styled through the shared `Theme`

**Given** every new art asset
**When** I check `game/assets/CREDITS.md`
**Then** its source and licence are listed

### Story 8.3: Hit the Performance Targets

As a player,
I want the game to run smoothly and launch fast on an ordinary laptop,
So that nothing gets in the way of the feel.

**Tier / Covers:** MUST · NFR1, NFR2, NFR3 · Architecture: ADR-002 pooling trigger, ADR-003

**Acceptance Criteria:**

**Given** a release export on the dev laptop
**When** I play the busiest wave (Level 3 Wave 3) and the Flagship's desperate phase with the F1 overlay in a debug export
**Then** frame time stays under 16.6 ms (60 FPS)
**And** if instancing is the cause of any overrun, pooling is added inside the `Spawner` only (ADR-002)

**Given** a cold launch of the release build
**When** I time it
**Then** the title screen appears in under 5 s, and the exported build is under 200 MB

### Story 8.4: Prove the Game Is Finishable

As the developer,
I want three clean start-to-finish playthroughs and a short playtest session,
So that I know the game ships without crashes, soft-locks or missing beats.

**Tier / Covers:** MUST · NFR5, NFR8, NFR9

**Acceptance Criteria:**

**Given** a release build and a fresh save
**When** I play start to finish 3 times
**Then** there are no crashes or soft-locks, and every beat fires each time: opening, Isolde's interruptions, the surrender prompt, Tarek's fall, Ryn's report, the Final Choice and the final line (verified against INFO beat logs in `%APPDATA%\DEFECTOR\logs\godot.log`)

**Given** 3–5 hackathon playtesters
**When** they play without verbal help
**Then** I record whether they understood the controls by Level 1 Wave 2, their attempts per level, total playtime, and answers to "Was the shooting fun on its own?" and "Which story moment do you remember?"
**And** any tuning change that results (e.g. +1 heart, higher drop rates) is made in data and logged in the decision log

### Story 8.5: Ship DEFECTOR on GitHub

As a player,
I want to download a zip from GitHub, unzip it and play,
So that I can try the game without installing anything.

**Tier / Covers:** MUST · FR65, NFR3, NFR4, NFR11 · Architecture: Deployment

**Acceptance Criteria:**

**Given** the Godot 4.7.2 export templates are installed
**When** I configure the Windows Desktop preset
**Then** it is 64-bit with an embedded PCK, product name "DEFECTOR" and an icon, includes the non-resource filter `data/*.json`, excludes `addons/gut/*` and `tests/*`, uses only relative paths, and `export_presets.cfg` is committed

**Given** the export
**When** I build to `game/export/windows/DEFECTOR.exe`
**Then** `DEFECTOR-v1.0-windows.zip` contains the exe, a `README.txt` with controls and the credits

**Given** the repo
**When** I check `README.md`
**Then** it covers the premise, the controls, how to download and run, and the credits, and the repo contains no secrets or machine-specific paths

**Given** the zip is unpacked into a clean folder
**When** I smoke-test it
**Then** it launches in under 5 s, creates the save in `%APPDATA%\DEFECTOR\`, and plays through Level 1

**Given** the smoke test passed
**When** I am ready to publish
**Then** I get explicit confirmation from the user first, then `gh release create v1.0 DEFECTOR-v1.0-windows.zip --title "DEFECTOR v1.0" --notes-file RELEASE_NOTES.md` publishes the release (decision F10)
