---
title: DEFECTOR - Development Epics
source: gdd.md
created: 2026-10-06
updated: 2026-10-08
---

# DEFECTOR - Development Epics

## About this breakdown

- **Purpose:** this is a high-level breakdown for `gds-create-epics-and-stories`. That workflow refines it into implementable stories.
- **Tiers:** each item is tagged with its MoSCoW tier from the brief.
- **Budget:** about 20 hours in total, including planning. Hour figures are rough guides.

**Cut order:** COULD items go first, then SHOULD. The mentor's fall is the last SHOULD item to cut.

## Hour budget

Planning is part of the 20 h total. The must-haves are budgeted to about 13 h; the should-haves fill the remaining time in cut order; the could-haves are unbudgeted. Any overrun goes into the optional polish week after day 3.

| Tier | Contents | Estimate |
|---|---|---|
| MUST | E1 core feel (3 h); E2 four enemies, Maul, wave director, progress bar (2.5 h); E3 hearts and retry (1 h); E4 flow and save (1.5 h); E5 comms panel, dialogue data, cut-off effect, opening (1.5 h); E6 convoy (1 h); E7 three levels, Flagship, Final Choice (2 h); E8 Windows release (0.5 h) | ~13 h |
| SHOULD | Energy, Shield, and Barrage (1.5 h); Isolde interruptions and surrender flags (0.5 h); ally ships and Tarek's fall (1 h); throne world and backgrounds, audio pass (1 h) | ~4 h |
| COULD | Hunter Wasp, scrolling convoy, council epilogue, stretch levels | Unbudgeted |

---

## E1: Core Feel Prototype (MUST, ~3 h)

**Goal:** prove the core hypothesis: "mouse-follow shooting with size-scaled feedback is fun on its own." This epic is the go/no-go gate before story work starts.

**Pillars served:** Impact Scales with Size, Skilled Not Hopeless.

**Stories:**

1. **Ship movement:** the ship sits exactly on the cursor, which is confined to the bottom 60% of the screen and hidden (decision #29).
2. **Laser:** hold LMB to fire 10 bolts/s, 1 damage each, straight up.
3. **Missile:** RMB fires a missile straight up from the ship's nose. It deals 8 damage plus 3 splash in a 120 px radius, has a 1.5 s cooldown, and shows a radial cooldown ring on the ship.
4. **Test targets:** one Wasp (3 HP), plus one asteroid of each size that drifts, blocks projectiles, and takes damage.
5. **Size-scaled feedback:** explosion scale, screen shake, and hit-stop follow the GDD feedback table.
6. **Data-driven tuning:** all values above are loaded from one tuning data file.

**Done when:** a 2-minute sandbox with a respawning Wasp formation and asteroids passes the core-hypothesis question: the developer answers "yes" to "Was the shooting fun on its own?" (Amended 2026-10-07, decision #34: the colleague requirement is waived for Epic 1 only.)

---

## E2: Enemies and Wave Director (MUST, ~3 h)

**Pillars served:** Skilled Not Hopeless (telegraphs), Impact Scales with Size (enemy size tiers).

**Goal:** scripted, data-driven waves with every enemy type the levels need.

**Stories:**

1. **Wasp:** formation entry and slot-holding, plus a telegraphed dive (0.4 s pause). A Wasp that exits the bottom of the screen re-enters from the top.
2. **Lancer:** horizontal strafe and an aimed bullet every 2.0 s. In Level 1 it targets the player or the convoy.
3. **Needle:** a targeting line that tracks for 1.2 s, locks for 0.3 s, then fires a 1600 px/s bolt. Asteroids block the bolt.
4. **Bastion:** 40 HP, slow drift, 2 turrets firing a 3-bullet spread.
5. **Wave director:** reads per-level wave data (enemy counts, entry patterns, asteroids, story triggers). Wave clear means all counted enemies are dead. The next wave starts after 2.0 s.
6. **Wave progress bar:** one segment per wave, filled by the percentage of the wave destroyed.
7. *(MUST, Level 1 depends on it)* **Maul:** a convoy diver that does 10 convoy damage and self-destructs.
8. *(COULD)* **Hunter Wasp:** chases the player (300 px/s, 90°/s turn limit).

---

## E3: Player Survival and Energy (MUST hearts, SHOULD energy, ~2.5 h)

**Pillars served:** Skilled Not Hopeless.

**Stories:**

1. **Hearts:** 5 hearts, damage per the GDD table, 1.2 s i-frames with a 10 Hz flicker, and a hearts HUD.
2. **Death and retry:** death feedback, then a 1.5 s pause and a retry prompt. Retry restarts the level from wave 1 with full hearts and 0 energy.
3. *(SHOULD)* **Energy drops:** energy orbs per the drop table, with drift, a 160 px magnet, and a 6 s despawn. The energy bar shows markers at 50 and 100.
4. *(SHOULD)* **Shield (E):** costs 50 and gives 4 s of invulnerability inside a bubble. Pressing E without enough energy plays the "denied" feedback.
5. *(SHOULD)* **Barrage (Q):** costs 100 and fires 12 homing micro-missiles over 2 s, each dealing 6 damage.
6. *(SHOULD)* **Player ship sprite:** a Kenney fighter hull recoloured cyan/teal, pulled forward from the E8 art pass (decision #37).

---

## E4: Game Flow and Save (MUST, ~1.5 h)

**Pillars served:** Skilled Not Hopeless (instant, unlimited retries). Also delivers the goal of a finishable game.

**Stories:**

1. **Title screen:** Play (continue), Level Select (locked levels greyed out), and Quit.
2. **Pause menu (Esc):** Resume, Restart Level, and Quit to Title.
3. **Unlock and save:** clearing a level unlocks the next one. Unlocked levels and energy are saved to the per-user app data folder on level clear.
4. **Display:** borderless fullscreen by default with a windowed option, and 16:9 letterbox scaling.

---

## E5: Comms and Story System (MUST panel, SHOULD interruptions and surrender, ~2.5 h)

**Pillar served:** Story Through One System.

**Stories:**

1. **Comms panel:** portrait, name, and typewriter text.
   - Story lines pause the game and advance on click.
   - Combat lines advance automatically and do not pause the game.
2. **Dialogue data:** dialogue lives in data files, and lines are triggered by wave director events (wave start, wave clear, % of wave destroyed, boss phase).
3. **Cut-off effect:** text stops mid-sentence, a static burst plays, a screen shake fires, the comms channel goes silent, and the music drops out.
4. **Opening sequence:** a paused, comms-only scene of 6–10 lines.
5. *(SHOULD)* **Isolde interruptions and the Level 1 Surrender Prompt:** controlled by on/off flags.
6. **Content task:** write all dialogue lines (see the GDD's Notes for Designer).

---

## E6: Allies and Escort (MUST convoy, SHOULD allies, ~2 h)

**Pillars served:** Story Through One System (Tarek's fall, Ryn's succession), Skilled Not Hopeless (allies help without carrying the player).

**Stories:**

1. *(MUST)* **Convoy (Level 1):** 3 cargo ships on a scripted slow path with a shared 100 HP bar. If the bar reaches 0, the level restarts.
2. *(SHOULD, "the successor's ship" in the brief)* **Ally ships:** Tarek (Levels 1–2) and Ryn (Level 3) follow scripted paths, fire 1 damage every 0.5 s at the nearest enemy, and cannot be destroyed.
3. *(SHOULD, last to cut)* **Tarek's scripted fall in Level 2 Wave 5:** triggered at 50% of the wave destroyed. His shield flashes over Vale, then the damaged variant appears with a fire trail and exits. This works together with the cut-off effect from E5.
4. *(COULD)* **Scrolling convoy variant.**

---

## E7: Levels and Flagship Boss (MUST, ~3 h)

**Pillars served:** all three pillars. This epic assembles them into content.

**Stories:**

1. **Level 1 data:** Cargo Ambush, 5 waves, tutorial combat lines, escort.
2. **Level 2 data:** The Blockade, 5 waves, with the Tarek's-fall beat and Ryn's report.
3. **Level 3 data:** Siege of the Throne World, 3 waves plus the boss, with Ryn as the ally and the throne-world background.
4. **Flagship Phase 1:** 4 turrets (25 HP each) with staggered spreads and 2 cover asteroids. The core is invulnerable.
5. **Flagship Phase 2:** core with 200 HP, a 12-bullet radial burst every 3 s, and 5 Wasps launched every 10 s (maximum 10 alive).
6. **Flagship Phase 3:** at 50 HP remaining, the game pauses and Isolde speaks.
   - The Final Choice appears with [Offer Surrender] and [Destroy Her].
   - She refuses, with a response line that depends on the choice.
   - The desperate barrage starts.
   - The Flagship's destruction plays the Boss-death feedback tier.
7. **Boss bar:** replaces the wave progress bar during the fight, with segment markers for each phase.
8. **End screen:** shown after Isolde's final line.
9. *(COULD)* **Council epilogue.**

---

## E8: Polish and Release (MUST release, SHOULD polish, ~1.5 h)

**Pillars served:** Impact Scales with Size (audio scaling). Also delivers the goal of shipping a downloadable build.

**Stories:**

1. **Audio pass:** about 15–20 SFX cues with size-scaled explosion audio. Optional combat and boss music.
2. **Backgrounds:** 2 space backgrounds plus the throne-world planet arc for Level 3.
3. **Performance check:** 60 FPS during the busiest wave on the dev laptop.
4. *(MUST)* **Windows release:** export a Windows build, zip it, and publish it as a GitHub release with a README covering controls and the story premise.
5. **Playthrough check:** 3 full start-to-finish playthroughs to confirm that every story beat fires and nothing soft-locks.
