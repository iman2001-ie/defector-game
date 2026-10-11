---
title: DEFECTOR - Game Design Document
game_type: shooter
platforms: [Windows PC]
created: 2026-10-06
updated: 2026-10-07
status: final-draft
version: 0.4
inputs:
  - _bmad-output/planning-artifacts/briefs/brief-game-project-2026-10-06/brief.md
  - _bmad-output/planning-artifacts/briefs/brief-game-project-2026-10-06/addendum.md
---

# DEFECTOR - Game Design Document

**Author:** iman2001-ie
**Game Type:** Shooter (2D fixed-screen arcade space shooter with a light narrative campaign)
**Target Platform(s):** Windows PC (downloadable build, public GitHub repo)

---

## Executive Summary

### Core Concept

"Chicken Invaders meets a CoD campaign." DEFECTOR is a neon 2D space shooter in which every enemy fleet belongs to the woman you used to serve. It is not meant as a technical breakthrough. The player is General Arden Vale, who defected from the Sovereignty to the Free Worlds Coalition. Across three short levels, Vale escorts a convoy, loses a mentor, and brings down Sovereign Isolde Varn's Flagship.

**Core fantasy:** "You are the general who walked away from a tyrant, and now you're the one who brings her down."

**Player takeaway:** the rush of a good shooter, plus one or two story moments that stick: the mentor going silent mid-sentence, and the dictator refusing your offer of surrender.

### Target Audience

- **Primary:** hackathon colleagues, developers, and casual players playing a single session of 10–15 minutes. The game must launch easily, make sense instantly, and be finishable in one sitting.
- **Secondary:** visitors to the public GitHub repo. The game is non-commercial.

### Unique Selling Points (USPs)

1. **Story inside the shooting.** All narrative runs through an in-game comms panel and scripted events. There are no cutscenes, and the player never leaves the action.
2. **The surrender mirror.** Isolde tempts the player to surrender in Level 1. In the finale, the player offers her the same choice, and she refuses.
3. **Size-scaled impact.** Every explosion, screen shake, and threat scales with object size, so the feel communicates danger.

---

## Goals and Context

### Project Goals

1. Ship a working, finishable 3-level game: an opening comms sequence plus three levels playable start to finish, each beatable, with all story beats firing. "Working beats perfect."
2. Learn the complete BMAD workflow end to end (brief → GDD → architecture → epics → build).
3. Fit everything (planning and implementation) into 3 days × 6–7 hours (about 20 hours).

### Background and Rationale

- **Developer:** one 4th-year CS student who is new to Godot 2D.
- **Budget:** free assets only.
- **Core hypothesis to validate:** "Mouse-follow shooting with size-scaled feedback is fun on its own, and story delivered only through comms dialogue makes the player care."
- **Reference games:**
  - **Chicken Invaders Universe:** mouse-follow controls, formation waves, enemy variety, and a clean modern look. Excluded: the comedy and the upgrade economy.
  - **Call of Duty campaigns (gunship missions):** escort and air-support fantasy, radio chatter, and character loss. Excluded: cutscenes and realism.
  - **Red Rising:** a personal war against a tyrant, the defector arc, the mentor, the rival ace, and the council ending. All names are original.
  - **The Last of Us:** protecting someone, scarcity decisions, and the gut punch. Excluded: stealth, crafting, and a bleak tone.

---

## Core Gameplay

### Game Pillars

1. **Skilled, Not Hopeless.** The game is challenging but always winnable. The player should feel like a good shot.
   - Failure restarts only the current level, with unlimited retries.
   - Every threat is telegraphed or readable.
   - Cover (asteroids) and defensive energy (Shield) give the player an answer to every attack.
   - *Steers:* telegraph rules, hearts and i-frames, retry flow, and drop rates.
2. **Impact Scales with Size.** Explosions, screen shake, hit-stop, and threat level all grow with object size: small ship < missile < large asteroid < boss.
   - *Steers:* the feedback table, enemy HP tiers, and the asteroid damage tiers.
3. **Story Through One System.** All story is delivered through the comms panel and scripted in-level events, with no cutscenes.
   - Cheap tricks carry the emotional weight: interrupted text, silence, and screen shake.
   - *Steers:* the comms panel spec and level scripting, and it rules out any cinematic tooling.

### Core Gameplay Loop

1. The ship follows the mouse.
2. The player holds left-click to fire lasers and right-clicks to fire a missile.
3. The player destroys enemy waves and asteroids, using asteroids as cover.
4. Destroyed enemies and asteroids drop energy, which the player collects.
5. The player spends energy on Shield (E) or Barrage (Q) to survive spikes.
6. When the player clears a wave, the wave progress bar advances and comms dialogue pushes the story forward.
7. The next wave begins, and steps 1–6 repeat. After the last wave, the level is cleared and the next level unlocks.

**Why the loop holds:** each wave changes the mix of enemies and cover, so moment-to-moment positioning differs (Pillar 1). Kills pay out in feel (Pillar 2) and energy. Wave clears pay out in story (Pillar 3).

### Win/Loss Conditions

- **Level win:** every scripted wave in the level is destroyed. In Level 3, the player must also destroy the Flagship. There are no timers, score, or rating.
- **Level loss:** either of these restarts the current level from wave 1:
  - Player hearts reach 0.
  - The convoy bar reaches 0 (Level 1 only).
- **Retries:** unlimited. On retry, hearts refill to full and energy resets to 0.
- **Game win:** the Flagship is destroyed, Isolde's final line plays, and the end screen appears. The council epilogue is COULD scope.

---

## Game Mechanics

### Primary Mechanics

All values below are **initial tuning**, chosen to be easy to change. They are expected to change after playtesting and should be exposed as data, not hard-coded.

**Playfield**

- The game uses a fixed single screen at 1920×1080 (16:9). It does not scroll.
- Enemies enter from the top and sides. The player fires upward.
- Units: px = playfield pixels at 1080p. s = seconds.

**Player ship movement**

| Parameter | Value |
|---|---|
| Movement model | The ship sits exactly on the cursor, with zero delay (decision #29). |
| Movement bounds | Bottom 60% of the screen (y 432–1080), full width. The **cursor itself** is confined to this zone during gameplay, so the lock is exact everywhere. |
| Rotation | None. The ship always faces up. |
| Hitbox | 24 px circle centred on a ~96 px sprite (shmup convention: forgiving) |
| Cursor | Hidden during gameplay and confined to the player zone. There is no reticle: the ship is the cursor. If the convoy pushes the ship, the cursor moves with it. When the game resumes from any pause, the cursor is put back on the ship, so the ship never jumps. |

**Hearts (hull)**

- The player has **5 hearts**.
- Most hits cost 1 heart. Large-object contact costs 2 hearts (see the damage table).
- After a hit, the player is invulnerable for **1.2 s** and the ship flickers at 10 Hz.
- Hearts refill to 5 at the start of each level and on retry. There are no heart pickups.

**Weapons**

| Weapon | Input | Damage | Rate / Cooldown | Projectile speed | Direction | Notes |
|---|---|---|---|---|---|---|
| Laser | Hold LMB | 1 per bolt | 10 bolts/s | 1800 px/s | Straight up | Twin bolts (visual only). Unlimited. |
| Missile | RMB | 8 to the target it hits; 3 splash to every other target within 120 px | 1.5 s cooldown | 900 px/s | Straight up from the ship's nose | Unguided. Unlimited. A radial cooldown ring is drawn on top of the ship while it reloads. |

- **Missile direction:** the missile fires straight up from the ship's nose, like the lasers (decision #29). The player aims it by positioning the ship, for example by sliding out from behind cover.
- **Asteroids block projectiles from both sides.** Asteroids stop every laser bolt and missile, from the player and from enemies. Player projectiles damage the asteroid they hit.
- **Enemy hitboxes:** each enemy's hitbox covers about 80% of its sprite.
- **Friendly fire:** the player's projectiles (lasers, missile splash, Barrage, ally shots) never damage allies or the convoy. Convoy ships are solid: they **block** player and ally shots, like asteroids but without taking damage (decision #23).

**Energy, Shield, and Barrage**

| Parameter | Value |
|---|---|
| Max energy | 100 |
| Energy orb value | 10 |
| Orb behaviour | Drifts down at 120 px/s. Magnet pull within 160 px of the ship. Despawns after 6 s. |
| Carry-over | Energy carries into the next level and is saved on level clear |
| On death or level restart | Energy resets to 0 |
| **Shield** (E) | Costs 50. Full invulnerability, including contact damage, for 4.0 s. Shown as a visible bubble. Cannot be stacked or refreshed while active. |
| **Barrage** (Q) | Costs 100. Fires 12 homing micro-missiles over 2.0 s, one every ~0.17 s. Each deals 6 damage and seeks the nearest enemy. Asteroids block them. |

- If the player presses E or Q without enough energy, nothing happens except a short "denied" sound and the energy bar flashing.

**Drop table** (chance to drop one 10-energy orb)

| Source | Drop chance |
|---|---|
| Wasp / Hunter Wasp | 15% |
| Lancer, Maul | 25% |
| Needle | 30% |
| Bastion | 100%, 2 orbs |
| Asteroid S / M / L | 10% / 30% / 60% |
| Flagship turret | 100% |

**Asteroids** (cover and hazard, never a weapon)

| Size | Diameter | HP | Drift speed | Contact damage | Drop |
|---|---|---|---|---|---|
| Small | 64 px | 4 | 140 px/s | 1 heart | 10% |
| Medium | 128 px | 12 | 100 px/s | 1 heart | 30% |
| Large | 224 px | 30 | 60 px/s | 2 hearts | 60% |

- Asteroids drift downward, each rotating at a random 10–40°/s, and exit off the bottom of the screen.
- They do not split when destroyed.
- They do not count toward wave completion.
- They only appear in levels and waves that list them (see Level Design Framework).

**Damage to player and convoy**

| Source | Player | Convoy |
|---|---|---|
| Enemy bullet or bolt | 1 heart | 5 if aimed at the convoy, 2 if stray |
| Needle shot | 1 heart | 2 (stray; Needles never aim at the convoy) |
| Contact with small or medium enemy or asteroid | 1 heart (the enemy is destroyed) | n/a |
| Contact with large asteroid, Bastion, or Flagship hull | 2 hearts | n/a |
| Contact with a convoy ship | none (the ship is blocked and slides along the hull) | none |
| Maul impact | 1 heart on contact (it never targets the player, but the player can body-block it; the Maul is destroyed) | 10 |

**Size-scaled impact feedback** (Pillar 2)

| Tier | Examples | Explosion scale | Screen shake | Hit-stop | Extra |
|---|---|---|---|---|---|
| Small | Wasp, Hunter Wasp, small asteroid, laser impact | 0.5× | none | none | spark burst |
| Medium | Lancer, Needle, Maul, medium asteroid, missile impact | 1× | 4 px / 0.15 s | none | debris |
| Large | Bastion, large asteroid, Barrage volley end | 2× | 8 px / 0.25 s | 40 ms | debris and shockwave ring |
| Boss part | Flagship turret | 1.5× | 6 px / 0.2 s | 30 ms | |
| Boss death | Flagship destroyed | 4× chain explosions over 2 s | 20 px / 1.0 s | 150 ms | white flash |
| Player hit | | small | 6 px / 0.2 s | 50 ms | red edge vignette |
| Player death | | 2× | 12 px / 0.5 s | 100 ms | 1.5 s pause before the retry prompt |

**Allies and escort**

- **Convoy (Level 1):**
  - Three medium cargo ships (~160×80 px sprites, hitbox ~80% of the sprite) fly as a **tight triangle**: a lead ship with two flankers. The group crosses the screen left to right at 40 px/s within y 760–920 (the lead ship about 40 px ahead of the flankers), then loops back. At each edge the group turns around before any hull leaves the screen and flies back the other way (ping-pong), with the triangle mirrored so the lead ship still leads; it never wraps off-screen. It starts fully on-screen at the left side, heading right, clear of the player spawn (decision #45). They share **one 100 HP bar**.
  - Convoy HP carries across waves within the level and refills only when the level restarts.
  - Cargo ships are solid to projectiles. Every enemy shot that touches one is stopped and damages the convoy. Player and ally shots are stopped with no damage, so the player has to fire around the convoy. A player missile stopped by a cargo ship fizzles: no explosion, no splash on anything nearby, the same small blocked-shot effect as a laser bolt (decision #46). The convoy is solid to the player's ship too: the ship slides along the hulls, with no damage from the contact. That lets the player **body-block** shots aimed at the cargo, taking the hit (1 heart) instead of the convoy (decision #25).
  - Lancers aim at the convoy 50% of the time (5 damage per hit). Every other enemy shot that strays into a cargo ship deals 2. Mauls deal 10. Bastions and Needles never *aim* at the convoy, but their shots can hit it.
- **Tarek (Levels 1–2) and Ryn (Level 3):**
  - Their allied ships patrol scripted horizontal paths at y 620–760, moving at 150 px/s.
  - They fire 1 damage every 1.0 s at the nearest enemy (provisional, decision #47).
  - They cannot be destroyed or damaged, except for Tarek's scripted hit in Level 2.
  - They make roughly 10–15% of total kills, so they help without carrying the player.

### Controls and Input

| Input | Action |
|---|---|
| Mouse movement | The ship sits on the cursor (bottom 60% only) |
| LMB (hold) | Laser auto-fire |
| RMB | Missile, straight up (1.5 s cooldown) |
| E | Shield (50 energy) |
| Q | Barrage (100 energy) |
| LMB (on story line) | Advance comms dialogue / choose a Final Choice option |
| Esc | Pause menu |

- Input is mouse and keyboard only. There is no gamepad or keyboard-only fallback in v1.0.
- Inputs pressed during a paused story line are ignored, except for advancing the dialogue.

---

## Shooter Specific Design

### Weapon Systems

- **Fixed loadout with no progression.** The player has a Laser, a Missile, and two energy abilities (Shield and Barrage). There are no unlocks, upgrades, or shops. This matches the brief's out-of-scope list.
- **Roles:**
  - **Laser:** sustained damage against fodder.
  - **Missile:** burst damage and splash against formations and tanks, on a cooldown, so *when* you fire it matters.
  - **Shield:** an emergency answer to a pattern the player can't dodge.
  - **Barrage:** a panic button against a crowded screen.
- **Risk/reward:** energy is scarce and wiped on death. Spending it early means survival now; holding it gives safety later (The Last of Us-style scarcity).
- **Weapon feel:**
  - **Laser:** short, bright bolts, a light hit spark, and a soft repeating zap (pitch randomised ±5%).
  - **Missile:** a launch thump, a visible smoke trail, and a medium-tier explosion.
  - **Barrage:** a rapid whoosh cascade with a large-tier finish.
  - Muzzle flash on every shot.

### Aiming and Combat Mechanics

- **Aim model:** all player weapons fire straight up; the player aims by positioning the ship. There is no lock-on.
- **Hit detection:** every shot is a projectile; none are hitscan. There is no spread or recoil.
- **Weak points:** only the Flagship has weak points. Phase 1 turrets must die before the core is exposed.
- **Melee:** none. Ramming an enemy destroys small and medium enemies but costs hearts (see the damage table).
- **Enemy projectile readability:** every enemy bullet is magenta or red with a bright core, at least 16 px, and travels no faster than 450 px/s. The Needle is the only exception, and its shot is pre-telegraphed.
- **Telegraph rule (Pillar 1):** every enemy or boss attack shows at least 0.3 s of glow or charge before it fires. The exact durations are in the enemy and Flagship tables.

### Enemy Design and AI

| Enemy | Tier | Role | HP | Movement | Attack | Telegraph | Priority |
|---|---|---|---|---|---|---|---|
| **Wasp** | Small | Fodder, formations | 3 | Enters in formation at 350 px/s, holds a formation slot; every 3–5 s one Wasp dives at the player at 600 px/s | Contact only | Wing flash plus a 0.4 s pause before diving | MUST |
| **Lancer** | Medium | Ranged pressure | 8 | Strafes horizontally in the top 35% of the screen at 200 px/s | 1 aimed bullet every 2.0 s at 450 px/s, aimed at the player (or the convoy in Level 1, 50/50) | Muzzle glow for 0.3 s | MUST |
| **Needle** | Medium | Sniper, teaches cover | 6 | Anchors at the top edge, repositions every 8 s | Very fast bolt (1600 px/s) along its targeting line, every 4.0 s | Targeting line tracks the player for 1.2 s, locks for 0.3 s (line turns red), then fires. Asteroids block the bolt. | MUST |
| **Bastion** | Large | Tank, turret gunship | 40 | Drifts at 60 px/s within y 80–400 (above the player zone) | 2 turrets, each fires a 3-bullet spread (±15°) every 2.5 s at 350 px/s | Turret glow for 0.5 s | MUST |
| **Maul** | Medium | Convoy diver | 6 | Enters from the side and dives straight at the nearest convoy ship at 400 px/s | 10 convoy damage on impact, then self-destructs | Red engine trail and an alarm ping on spawn | MUST (Level 1 needs it) |
| **Hunter Wasp** | Small | Chaser | 3 | Chases the player at 300 px/s with a 90°/s turn limit | Contact only | Distinct orange tint | COULD |

**Spawning and difficulty:**

- All spawns are scripted per wave, as data. There is no procedural spawning.
- Difficulty comes from the enemy mix and count per wave, not from scaling HP or damage.
- **Off-screen rule:** a diving Wasp that exits the bottom re-enters from the top, so every wave enemy must be killed for the wave to clear. Mauls are the exception: a Maul that misses ends its dive and counts as cleared.

**Flagship (Level 3 boss)**

| Phase | Trigger | Exposed target | Attacks | Notes |
|---|---|---|---|---|
| **1: Turrets** | Boss arrival | 4 turrets, 25 HP each; the core is invulnerable | Each turret fires a 3-bullet spread (350 px/s) every 3.0 s, staggered, after a 0.5 s turret glow | 2 medium asteroids drift through as cover |
| **2: Core** | All 4 turrets destroyed | Core, 200 HP | A 12-bullet radial burst (300 px/s) every 3.0 s, after a 0.6 s core charge glow; launches 5 Wasps every 10 s (maximum 10 alive) | Wasps launched by the boss drop energy normally |
| **3: Final Choice** | The 200 HP core drops to 50 HP | The same core, with its remaining 50 HP | **Pause.** Isolde speaks, then the Final Choice appears: [Offer Surrender] / [Destroy Her]. Both lead to her refusal. Her response line differs by choice. Then the desperate barrage: 2 alternating radial bursts (300 px/s) every 1.5 s, each after a 0.4 s charge glow, plus an aimed 3-bullet spread (400 px/s) every 2.0 s after a 0.3 s glow | The core flashes red at a steady pulse; core death triggers the Boss-death feedback tier |

- **Flagship HP display:** a dedicated boss bar replaces the wave progress bar during the fight. It has three segment markers: turrets, core, and final.
- **Final Choice UI:** two large buttons centred on the screen, chosen by click. Combat stays paused until the player chooses. There is no timer.
- **Final Choice responses:**
  - **[Offer Surrender]:** Vale offers surrender in Isolde's own Level 1 words ("You're outnumbered"), and Isolde refuses with contempt (decision #44).
  - **[Destroy Her]:** Isolde refuses with defiance.
  - The exact lines are written during content authoring. The choice changes only this one dialogue line.

### Arena and Level Design

- **Arena:** a fixed 1920×1080 screen.
  - Enemies hold the top 40%.
  - The player owns the bottom 60%, where the convoy and allies also sit.
  - There is no verticality and no choke points. Space control comes from asteroid placement.
- **Cover:** asteroids are dynamic, destructible, drifting cover that blocks everything.
  - Needle waves always include at least 2 medium or large asteroids, so cover is available against the sniper.
  - Large asteroids are also the biggest contact hazard, which keeps cover risky.
- **Safe zones:** none are fixed. The 1.2 s i-frames after a hit and the 2.0 s gap between waves give breathing room.
- **Power-ups:** energy orbs only, from drops. No pickups are placed in the level.
- **Engagement distance:** enemies normally fire from 300–900 px away. The gap can be shorter if the player pushes to the top of their zone; that is a risk the player chooses. The Needle's long sightline is its identity.

### Multiplayer Considerations

N/A. DEFECTOR is single-player only. Multiplayer is out of scope (see Out of Scope).

---

## Progression and Balance

### Player Progression

- **Narrative progression:** the opening comms sequence leads into Level 1, Level 2, and Level 3. Clearing a level unlocks the next one.
- **No character progression:** the player has no XP, upgrades, or shop. The only resource that carries between levels is **energy** (saved on level clear, wiped on death).
- **Wave progress bar:** a top-centre bar is split into one segment per wave.
  - The current segment fills by the percentage of that wave's enemies destroyed.
  - In Level 3, the boss bar replaces it once the Flagship arrives.

### Difficulty Curve

- There is a single difficulty with no settings.
- The curve comes from content:
  - **Level 1:** teaches the controls with calm waves, then introduces the ambush and the convoy.
  - **Level 2:** introduces tanks (Bastions) and snipers (Needles), so the player has to use cover.
  - **Level 3:** combines everything and ends with the boss.
- **Target clear rate:** a first-time player clears each level in 1–3 attempts.
- **Tuning knob:** if "death wipes energy" proves too harsh, the first lever is +1 heart. The second lever is higher drop chances across the board. Level 3 already has the richest drops.

### Economy and Resources

- **Energy is the only economy.** It comes in only from drops and goes out only through Shield (50) and Barrage (100).
- **Expected income** from drops: about 130 energy in Level 1, about 200 in Level 2 (its 5 Bastions guarantee 10 orbs), and more than 190 in Level 3 once the boss turrets and boss-launched Wasps are counted. This rising income suits the rising difficulty. The 100 cap stops the player from hoarding, so energy has to be spent.
- **No score or currency.**

---

## Level Design Framework

### Level Types

- **Story sequence:** a comms-only scene with a static space background.
  - The game is paused, and the player clicks to advance the dialogue.
  - The opening sequence is 6–10 lines that establish Vale's defection, Tarek, and Isolde.
- **Escort level:** waves plus the convoy bar, with an extra loss condition (Level 1).
- **Combat level with ally:** waves plus an invincible ally ship (Levels 2 and 3).
- **Boss encounter:** the final segment of Level 3.

**Wave rules:**

- A wave clears when all of its counted enemies are destroyed. Asteroids are not counted.
- The next wave spawns 2.0 s after the previous wave clears.
- **Dialogue model** (decision #22):
  - **Briefings and debriefs carry the story.** Every level opens with a paused briefing and closes with a short paused debrief. The player clicks to advance each line. Paused dialogue appears in a centred panel over a dimmed playfield.
  - **Interruptions are rare.** At most 1–2 per level, each a single short line that auto-dismisses without pausing, shown in a small top-left box. They are only Isolde mocking Vale or an ally warning Vale.
  - **Only two mid-fight pauses in the whole game:** the Level 1 surrender offer and the Level 3 Final Choice.
  - **Tutorials are on-screen control hints, not dialogue** (for example "Hold LMB to fire").
- Story lines pause the game, so they only fire at level start, at level end, or at the two scripted mid-fight pauses.

### Level Progression

**Opening sequence (story, paused)**

- Vale's defection is established over comms. Tarek welcomes the General to the Coalition and briefs the convoy mission.
- Isolde gets one line of her own, a cold message aimed at the traitor. She introduces herself in her own voice; no one describes her secondhand.

**Level 1: Cargo Ambush** (escort, convoy 100 HP, Tarek on comms and flying escort)

| Wave | Content | Story / tutorial beat |
|---|---|---|
| 1 | 8 Wasps in a slow formation | Control hints: move, hold LMB to fire |
| 2 | 10 Wasps plus 3 small and 1 medium asteroid | Control hint: RMB missile; asteroids block shots |
| 3 | Ambush: 12 Wasps, 2 Lancers, 3 Mauls | Tarek warns of the ambush at wave start (interruption). Isolde's first condescending interruption once the ambush is underway (25% of the wave destroyed) |
| 4 | 10 Wasps, 4 Lancers | Control hints: energy, E Shield, Q Barrage (each shown when first relevant) |
| 5 | 16 Wasps and 3 Lancers, then 4 Mauls as reinforcements | Surrender Prompt in the wave: when 30% of the wave is destroyed, the game pauses and Isolde says "You're outnumbered, General. Come home." The player is not given a choice. When play resumes, the 4 Mauls arrive as reinforcements. |

- Level clear: Tarek's closing line.

**Level 2: The Blockade** (Tarek fights alongside). The level opens with Tarek briefing the mission, 2–3 story lines.

| Wave | Content | Story beat |
|---|---|---|
| 1 | 2 Needles, 6 Wasps, 2 medium and 1 large asteroid | Needle and cover lesson |
| 2 | 1 Bastion, 8 Wasps | |
| 3 | 3 Needles, 3 Lancers, 2 medium asteroids | Isolde interruption |
| 4 | 2 Bastions, 10 Wasps, 1 large asteroid | |
| 5 | 2 Bastions, 2 Needles, 4 Lancers, 2 medium asteroids | When 50% of the wave is destroyed: Tarek shields Vale, and his line is cut off mid-sentence. This is an interruption, so the game does not pause. Then a strong screen shake (the dedicated cut-off shake, 18 px for 0.9 s; was large-tier, decision #43), his ship trails fire and leaves, and the comms channel goes silent until the wave clears. |

- After the wave clears, Ryn reports that Tarek is alive but gravely injured, and that she is taking command.

**Level 3: Siege of the Throne World** (Ryn fights alongside; the throne-world planet arc is in the background). The level opens with Ryn's paused briefing, in which she takes command, then defence waves: the Sovereignty's home fleet is defending the throne world, and Vale has to break through it before the Flagship engages.

| Wave | Content | Story beat |
|---|---|---|
| 1 | 4 Lancers, 12 Wasps | (Ryn takes command in the level briefing) |
| 2 | 2 Bastions, 2 Needles, 3 medium asteroids (plus 4 Hunter Wasps if built) | |
| 3 | 20 Wasps, 3 Lancers, 1 Bastion | Isolde taunt (interruption) |
| Boss | Flagship, phases 1 to 3 | Final Choice, then her refusal, then the Flagship is destroyed |

- After the boss: Isolde's final line, then the end screen. The council epilogue is COULD scope.
- **Target length:** about 3–4 minutes per level plus dialogue, for a total playthrough of 10–15 minutes.
- **Stretch levels (out of v1.0):** "Ambush in the Void" and "The Ace" (rival Soren Kade).

---

## Characters and Setting

**Factions:** the Sovereignty, ruled by Isolde Varn, against the Free Worlds Coalition.

| Character | Role | Voice and notes |
|---|---|---|
| **General Arden Vale** | The player. Defected from the Sovereignty to the Coalition. | Gender-neutral. Others usually address Vale as "General". Vale speaks only a few lines (for example, offering surrender at the Final Choice). The portrait is optional. |
| **Sovereign Isolde Varn** | Antagonist. Vale's former ruler. | Condescending and manipulative. Alternates between trying to annihilate Vale and trying to talk Vale into surrendering. |
| **Admiral Tarek Holt** | Mentor. A veteran from another world who briefs missions. | Pax-inspired. Wounded in Level 2 but survives. |
| **Commander Ryn Holt** | Tarek's daughter. Takes over his ship for the finale. | Takes command after Tarek falls. |
| **Soren Kade** *(stretch)* | Rival ace. Vale's former star student. | Fights using Vale's own tactics. Appears only in the stretch level "The Ace". |

- **Speaking cast in v1.0:** Vale, Isolde, Tarek, and Ryn (4 speakers).
- **Opening rule:** every character introduces themselves in their own voice over comms, never through narration. This is why the text crawl was rejected.

---

## Art and Audio Direction

### Art Style

- **Look:** clean neon/vector 2D in the spirit of Chicken Invaders Universe, not retro or pixel art. Dark space backgrounds with glowing ships and projectiles.
- **Colour language:**
  - Coalition (player and allies): cyan and teal.
  - Sovereignty enemies and all enemy projectiles: magenta and red.
  - Energy orbs and pickups: gold.
  - Hazards (asteroids): desaturated grey-brown with a rim light.
- **Game feel:** glow, particles, and screen shake carry the feedback, as specified in the size-scaled impact table.
- **Throne world:** appears only in Level 3, as a planet arc in the background.
- **Assets:** free packs first (Kenney space and sci-fi packs), recoloured to the palette. No 3D tools are used.
- **UI:**
  - The comms panel shows a portrait, a name, and typewriter text. Paused dialogue uses a centred panel over a dimmed playfield (styled as a conversation, not a menu). Interruptions use a small top-left box.
  - Control hints are short on-screen key prompts, separate from comms.
  - Portraits are simple and stylised, one per speaker: Isolde, Tarek, and Ryn. Vale is portrait-optional.

### Audio and Music

- **SFX:** free sci-fi packs (Kenney audio) plus generated laser sounds.
  - Explosion volume and pitch scale with the size tier.
  - The game uses distinct cues for: player hit, energy pickup, ability denied, comms open, and comms cut-off (static burst, then silence).
- **Music:** optional, from free-licence sources, in one combat track and one boss track. The music drops out during Tarek's silence beat (Pillar 3: silence carries weight).
- **Voice acting:** none.
- **Tone:** personal and character-driven. Not comedic, and not bleak throughout.

---

## Technical Specifications

### Performance Requirements

- **60 FPS** sustained at 1920×1080 on the developer's dev laptop (integrated graphics), during the busiest wave. The largest planned wave has about 25 enemies; the target is set at 40 enemies, 200 projectiles, and particles to leave headroom. [ASSUMPTION: the dev laptop is mid-range with integrated graphics, and the exact specs are unrecorded]
- Cold launch to the title screen in under 5 s.
- Build size under 200 MB.

### Platform-Specific Details

- **Engine:** Godot 4 with GDScript.
- **Platform:** Windows 10/11, 64-bit. Distributed as a zipped executable on the public GitHub repo's releases page. No installer.
- **Display:**
  - Defaults to borderless fullscreen; windowed mode is also supported.
  - The playfield scales with letterboxing to keep 16:9.
- **Save:** unlocked levels and current energy, written to the per-user app data folder on level clear.
- **Menus:**
  - **Title screen:** Play (continue at the highest unlocked level), Level Select (locked levels are shown greyed out), Quit.
  - **Pause (Esc):** Resume, Restart Level, Quit to Title.
- **Data-driven content:** dialogue, wave compositions, and tuning values live in data files, not code. This lets the designer change content without code changes.
  - Surrender-prompt beats sit behind on/off flags, so they can be cut without editing scripts.

### Asset Requirements

| Category | Count (MVP) |
|---|---|
| Player ship | 1 |
| Ally ships | 2 (Tarek, Ryn) plus a damaged Tarek variant |
| Convoy ships | 1 sprite × 3 instances |
| Enemies | 4 MUST (Wasp, Lancer, Needle, Bastion) + Maul (MUST) + Hunter Wasp (COULD) |
| Boss | Flagship hull, 4 turrets, core |
| Asteroids | 3 sizes, 1–2 variants each |
| Projectiles and VFX | Laser bolt, missile and trail, micro-missile, enemy bullet, Needle line and bolt, explosion sprite or particles, shield bubble, energy orb |
| Backgrounds | 2 space backgrounds plus the throne-world arc |
| Portraits | 3 (Isolde, Tarek, Ryn), optionally Vale |
| UI | Hearts, energy bar, cooldown ring, wave progress bar, boss bar, convoy bar, comms panel, menus |
| SFX | About 15–20 cues |
| Music | 0–2 tracks (optional) |

---

## Development Epics

### Epic Structure

The detailed breakdown is in [`epics.md`](./epics.md). The build order front-loads core feel, per the brief's risk mitigation.

| # | Epic | Tier | Delivers |
|---|---|---|---|
| E1 | Core Feel Prototype | MUST | Ship movement, laser, missile, one Wasp, one asteroid of each size, size-scaled explosions |
| E2 | Enemies and Wave Director | MUST (Hunter COULD) | 4 enemy types, data-driven waves, wave progress bar |
| E3 | Player Survival and Energy | MUST (energy SHOULD) | Hearts, i-frames, death and retry, energy drops, Shield, Barrage |
| E4 | Game Flow and Save | MUST | Title, level select, unlocking, pause, save |
| E5 | Comms and Story System | MUST (interruptions and surrender SHOULD) | Comms panel, dialogue data, pause and auto-advance, cut-off effect, opening sequence |
| E6 | Allies and Escort | MUST convoy, SHOULD allies and Tarek's fall, COULD scrolling convoy | Convoy bar, Tarek and Ryn ally ships, Tarek's scripted fall |
| E7 | Levels and Flagship Boss | MUST | Content for Levels 1–3, Flagship phases 1 to 3, Final Choice |
| E8 | Polish and Release | MUST release, SHOULD polish | Audio pass, backgrounds including the throne world, Windows export, GitHub release |

**Sequence:** E1 → E2 → E3 → E4 → E5 → E6 → E7 → E8. E1 must be finished and judged fun before starting E5.

**Cut order:** COULD items first, then SHOULD. The mentor's fall (E6/E7) is the last SHOULD item to cut.

---

## Success Metrics

### Technical Metrics

- 60 FPS sustained during the busiest wave on the dev laptop (see Performance Requirements).
- No crash or soft-lock across 3 full start-to-finish playthroughs.
- Every scripted story beat fires in every playthrough: opening, Isolde's interruptions, the surrender prompt, Tarek's fall, Ryn's report, and the Final Choice.

### Gameplay Metrics

Measured informally with 3–5 hackathon playtesters:

- Full playthrough time is 10–15 minutes.
- Each level is cleared within 1–3 attempts by a first-time player.
- A playtester understands the controls without verbal help within Level 1 Wave 2.
- The core hypothesis is checked by asking: "Was the shooting fun on its own?" and "Which story moment do you remember?" The target is that at least half of the playtesters name Tarek's fall or Isolde's refusal.
- The project is done when the MVP is playable start to finish by the end of day 3.

---

## Out of Scope

**Cut for v1.0:**

- Multiplayer.
- Upgrades, shops, and any currency or score.
- Voice acting and cutscenes.
- Platforms other than Windows.
- Gamepad support and difficulty settings.
- Timers and level ratings.

**Deferred (COULD or post-v1.0):**

- The scrolling convoy.
- Hunter Wasp AI.
- The council epilogue.
- The stretch levels "Ambush in the Void" and "The Ace" (Soren Kade).
- The missile shatter combo (parked; if built, its fragments hurt everyone, or it is limited to solo levels).

**Rejected:**

- A playable escape prologue. It would add scope before the core game exists.
- A Star Wars-style text crawl. Characters introduce themselves in their own voices over comms instead.
- The throne world growing across levels. It appears only in Level 3, so it lands as a reveal.
- Asteroids as weapons. They serve as cover and hazard only. A missile shatter combo that hurts only enemies was also rejected as illogical.
- Unity. It is heavier on the dev laptop, and the ramp-up is steeper than Godot's for this project.

---

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Planning eats into the 20-hour budget | Keep every document lightweight. Build the core-feel prototype (E1) early. |
| Learning curve, as a newcomer to Godot 2D | Prototype the ship, the laser, and one enemy first. Lean on the engine's built-in particles, tweening, and collision features. |
| Scope creep | Cut strictly by tier: COULD first, then SHOULD. The mentor's fall is the last SHOULD item to cut. |
| Escort complexity | Use a scripted convoy path and one shared HP bar. Allies can't be destroyed. |
| Balance: "death wipes energy" may be too harsh | Treat it as a tuning knob (see Difficulty Curve). |

---

## Assumptions and Dependencies

- **Dependencies:**
  - Godot 4 stable.
  - Kenney (CC0) art and audio packs.
  - Free-licence music, if used.
  - A public GitHub repo for distribution.
- [ASSUMPTION: the dev laptop is mid-range with integrated graphics, and the exact specs are unrecorded] (see Performance Requirements).
- [NOTE FOR DESIGNER] The dialogue script still needs to be written:
  - The opening sequence.
  - The level briefings and debriefs, and Tarek's ambush warning.
  - Isolde's interruptions.
  - Tarek's cut-off line.
  - Ryn's report.
  - Isolde's two Final Choice responses and her final line.

  The GDD fixes the beats. The words are a content task in E5/E7. `gds-create-narrative` is optional if you want a fuller script.
- [NOTE FOR DESIGNER] All numeric values in this document are first-pass tuning. They will be adjusted after the E1 prototype and playtests, and changes go in `decision-log.md`.
- The addendum references `_bmad-output/brainstorming-session-2026-10-06.md`. It was not used directly; the brief and addendum were treated as its distilled form.
