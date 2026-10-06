---
stepsCompleted: [1, 2, 3, 4, 5, 6]
readinessStatus: READY (after remediation; M5 handled in sprint planning)
documentsIncluded:
  gdd: _bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md
  gddDecisionLog: _bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md
  architecture: _bmad-output/game-architecture.md
  epics: _bmad-output/planning-artifacts/epics.md
  gddEpicOutline: _bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/epics.md
  ux: _bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/ (DESIGN.md, EXPERIENCE.md, added after assessment)
---

# Implementation Readiness Assessment Report

**Date:** 2026-10-06
**Project:** defector-game

## Document Inventory

| Type | File | Notes |
|---|---|---|
| GDD | `gdds/gdd-game-project-2026-10-06/gdd.md` (35.6 KB) | Primary; `decision-log.md` as supporting |
| Architecture | `_bmad-output/game-architecture.md` (73.5 KB) | Located outside planning-artifacts |
| Epics & Stories | `planning-artifacts/epics.md` (96.5 KB) | Primary breakdown |
| GDD Epic Outline | `gdds/gdd-game-project-2026-10-06/epics.md` (9.1 KB) | Cross-check only (source outline, not duplicate) |
| UX Design | — | **Not found** |

**Issues noted at discovery:**
- No UX design document exists (WARNING).
- Architecture document lives outside `planning-artifacts/` (minor).

## GDD Analysis

Source: `gdd.md` v0.2 (final-draft) plus `decision-log.md` (#1–#20). The GDD has no numbered requirements, so the FRs and NFRs below were derived from its specs and tables. Numbering here is the readiness report's own (prefix `G-`) and is independent of any numbering in `epics.md`. Tier tags (MUST, SHOULD, COULD) come from the GDD and decision log.

### Functional Requirements

**Playfield & Player Ship**
- G-FR1: Fixed single-screen 1920×1080 (16:9) playfield, no scrolling; enemies enter from top/sides; player fires upward.
- G-FR2: Ship chases the cursor (no snap), max 1400 px/s, covers a 150 px cursor move in ~0.12 s.
- G-FR3: Ship is confined to the bottom 60% of the screen (y 432–1080), full width; no rotation (always faces up).
- G-FR4: Player hitbox is a 24 px circle centred on a ~96 px sprite.
- G-FR5: OS cursor hidden and confined to the window during gameplay; a reticle marks the cursor position.

**Weapons & Combat**
- G-FR6: Laser: hold LMB → 10 bolts/s, 1 dmg, 1800 px/s, straight up, twin-bolt visual, unlimited.
- G-FR7: Missile: RMB → 8 dmg to the target hit + 3 splash to all other targets within 120 px; 1.5 s cooldown; 900 px/s; unguided; unlimited.
- G-FR8: Missile direction is the ship→cursor vector; straight up if the cursor is within 32 px of the ship.
- G-FR9: Radial missile-cooldown ring shown on the reticle.
- G-FR10: Asteroids block all projectiles from both sides (player lasers, missiles, Barrage micro-missiles, enemy bullets, Needle bolts); player projectiles damage the asteroid they hit.
- G-FR11: Enemy hitboxes cover ~80% of the sprite.
- G-FR12: No friendly fire: player projectiles (laser, splash, Barrage) never damage allies or the convoy.
- G-FR13: All shots are projectiles (no hitscan, spread, recoil, or lock-on).
- G-FR14: Ramming destroys small/medium enemies at the heart cost in the damage table.

**Hearts / Damage**
- G-FR15: Player has 5 hearts; refilled at level start and on retry; no heart pickups.
- G-FR16: Damage table: enemy bullet/bolt 1 heart (convoy 5); Needle shot 1 heart (convoy 5); small/medium enemy or asteroid contact 1 heart (enemy destroyed); large asteroid, Bastion, or Flagship hull contact 2 hearts; Maul contact 1 heart + Maul destroyed (body-block), Maul impact on convoy 10 (decision #20).
- G-FR17: After a hit: 1.2 s invulnerability with a 10 Hz flicker.

**Energy, Shield, Barrage** *(SHOULD per decision #15)*
- G-FR18: Energy max 100; orb = 10; orbs drift down at 120 px/s, magnet within 160 px, despawn after 6 s.
- G-FR19: Energy carries into the next level, is saved on level clear, and resets to 0 on death or restart.
- G-FR20: Drop table: Wasp/Hunter 15%, Lancer/Maul 25%, Needle 30%, Bastion 100% ×2 orbs, Asteroid S/M/L 10/30/60%, Flagship turret 100%; boss-launched Wasps drop normally.
- G-FR21: Shield (E): costs 50, 4.0 s full invulnerability including contact, visible bubble, cannot be stacked or refreshed while active.
- G-FR22: Barrage (Q): costs 100, 12 homing micro-missiles over 2.0 s (~0.17 s apart), 6 dmg each, seek the nearest enemy, blocked by asteroids.
- G-FR23: Insufficient energy on E/Q → "denied" SFX + energy bar flash, no other effect.

**Asteroids**
- G-FR24: Three sizes: S 64 px / 4 HP / 140 px/s / 1 heart; M 128 / 12 / 100 / 1 heart; L 224 / 30 / 60 / 2 hearts.
- G-FR25: Asteroids drift down, rotate at a random 10–40°/s, exit off the bottom, do not split, do not count toward wave clear, and appear only in waves that list them.

**Size-Scaled Feedback (Pillar 2)**
- G-FR26: Feedback tiers per the table (Small / Medium / Large / Boss part / Boss death / Player hit / Player death), each with explosion scale, screen shake, hit-stop, and extras (sparks, debris, shockwave ring, white flash, red vignette).
- G-FR27: Player death plays its feedback tier, then a 1.5 s pause before the retry prompt.

**Enemies**
- G-FR28: Wasp (3 HP, small): formation entry at 350 px/s, holds a slot; every 3–5 s one dives at the player at 600 px/s after a wing flash + 0.4 s pause; contact-only. MUST.
- G-FR29: Lancer (8 HP, medium): strafes the top 35% at 200 px/s; 1 aimed bullet every 2.0 s at 450 px/s; in Level 1 targets the player or convoy 50/50; 0.3 s muzzle-glow telegraph. MUST.
- G-FR30: Needle (6 HP, medium): anchors at the top edge, repositions every 8 s; targeting line tracks for 1.2 s, locks for 0.3 s (turns red), fires a 1600 px/s bolt every 4.0 s; blocked by asteroids. MUST.
- G-FR31: Bastion (40 HP, large): drifts at 60 px/s within y 80–400; 2 turrets each fire a 3-bullet ±15° spread every 2.5 s at 350 px/s after a 0.5 s glow. MUST.
- G-FR32: Maul (6 HP, medium): enters from the side and dives at the nearest convoy ship at 400 px/s; 10 convoy dmg then self-destructs; red engine trail + alarm ping on spawn; a missed dive counts as cleared. MUST.
- G-FR33: Hunter Wasp (3 HP): chases the player at 300 px/s with a 90°/s turn limit; orange tint. COULD.
- G-FR34: Enemy projectiles are magenta/red with a bright core, ≥16 px, ≤450 px/s (Needle the only exception).
- G-FR35: Telegraph rule: every enemy/boss attack has ≥0.3 s glow/charge.
- G-FR36: Off-screen rule: a diving Wasp that exits the bottom re-enters from the top.

**Wave Director / Progress**
- G-FR37: All spawns are scripted per wave as data; no procedural spawning; difficulty comes from the mix, not stat scaling.
- G-FR38: A wave clears when all counted enemies are dead (asteroids excluded); the next wave spawns 2.0 s later.
- G-FR39: Wave progress bar (top-centre), one segment per wave, current segment fills by % of the wave destroyed.
- G-FR40: Wave events (wave start, wave clear, % destroyed, boss phase) trigger dialogue and scripted beats.
- G-FR41: Mid-wave reinforcement spawning (Level 1 Wave 5: 4 Mauls arrive after the Surrender Prompt).

**Allies & Escort**
- G-FR42: Convoy (Level 1): 3 cargo ships cross left→right at 40 px/s along y 780–880 then loop; shared 100 HP bar; HP persists across waves and refills only on restart. MUST.
- G-FR43: The convoy has no hitbox vs the player and blocks nothing; only Lancer shots aimed at the convoy and Maul dives hit it.
- G-FR44: Convoy HP reaching 0 → level loss (restart from wave 1). MUST.
- G-FR45: Ally ships Tarek (L1–2) and Ryn (L3) patrol scripted horizontal paths at y 620–760, 150 px/s; fire 1 dmg every 0.5 s at the nearest enemy; invulnerable. SHOULD.
- G-FR46: Tarek's scripted fall (L2 W5 at 50% destroyed): shields Vale, line cut off mid-sentence (combat line, no pause), large-tier shake, damaged variant with fire trail exits, comms silent until the wave clears. SHOULD (last to cut).

**Comms & Story**
- G-FR47: Comms panel: portrait, name, typewriter text.
- G-FR48: Story lines pause the game and advance on LMB; combat lines auto-advance without pausing.
- G-FR49: Input during a paused story line is ignored except dialogue advance.
- G-FR50: Cut-off effect: text stops mid-sentence, static burst, screen shake, comms silent, music drops out.
- G-FR51: Opening sequence: paused comms-only scene of 6–10 lines on a static space background; Tarek welcomes and briefs; Isolde has her own line; every character self-introduces (no narration or crawl).
- G-FR52: Isolde interruptions as combat lines (L1 W3 at 25% destroyed; L2 W3; L3 W3). SHOULD.
- G-FR53: Level 1 Surrender Prompt (W5 at 30% destroyed): pause, Isolde: "You're outnumbered, General. Come home.", no choice; on resume the Mauls arrive. SHOULD.
- G-FR54: Surrender-prompt beats are behind on/off flags in data.
- G-FR55: Level-specific story beats: L1 tutorial combat lines (move/laser, missile, asteroids, energy/Shield/Barrage prompts) and Tarek's closing line; L2 opening briefing (2–3 lines) and Ryn's report after W5; L3 Ryn's command line (W1).
- G-FR56: Dialogue script authored (opening, tutorial, interruptions, cut-off line, Ryn's report, two Final Choice responses, final line). Content task.

**Levels & Boss**
- G-FR57: Level 1 Cargo Ambush, 5 waves per the GDD table.
- G-FR58: Level 2 The Blockade, 5 waves per the GDD table.
- G-FR59: Level 3 Siege of the Throne World, 3 waves + Flagship (Hunter Wasps in W2 only if built).
- G-FR60: Flagship Phase 1: 4 turrets × 25 HP, core invulnerable, staggered 3-bullet spreads (350 px/s) every 3.0 s after a 0.5 s glow; 2 medium cover asteroids.
- G-FR61: Flagship Phase 2: core 200 HP; 12-bullet radial burst (300 px/s) every 3.0 s after a 0.6 s glow; launches 5 Wasps every 10 s (max 10 alive).
- G-FR62: Flagship Phase 3 at core 50 HP: pause, Isolde speaks, Final Choice UI (2 large centred buttons, click, no timer, combat paused); both choices lead to refusal with choice-specific lines; then the desperate barrage (2 alternating radial bursts every 1.5 s after a 0.4 s glow, plus an aimed 3-spread at 400 px/s every 2.0 s after a 0.3 s glow); core pulses red.
- G-FR63: Boss death plays the Boss-death feedback tier (4× chain explosions over 2 s, 20 px/1.0 s shake, 150 ms hit-stop, white flash).
- G-FR64: Boss bar replaces the wave bar during the fight, with 3 segment markers (turrets, core, final).
- G-FR65: Flagship hull contact costs 2 hearts.
- G-FR66: After the boss: Isolde's final line, then the end screen. Council epilogue is COULD.

**Win / Loss / Flow**
- G-FR67: Level win = all scripted waves destroyed (+ Flagship in L3); no timers, score, or rating.
- G-FR68: Level loss (hearts 0 or convoy 0) → restart from wave 1; unlimited retries; hearts refilled, energy reset to 0.
- G-FR69: Clearing a level unlocks the next.
- G-FR70: Title screen: Play (continue at the highest unlocked level), Level Select (locked levels greyed), Quit.
- G-FR71: Pause (Esc): Resume, Restart Level, Quit to Title.
- G-FR72: Save of unlocked levels + energy to the per-user app-data folder on level clear.
- G-FR73: Display: borderless fullscreen default, windowed supported, 16:9 letterbox scaling.

**Data-Driven Content**
- G-FR74: Dialogue, wave compositions, and all tuning values live in data files, not code.

**Audio / Art**
- G-FR75: SFX: explosion volume/pitch scale by tier; distinct cues for player hit, energy pickup, ability denied, comms open, comms cut-off; laser zap pitch ±5%; missile launch thump; Barrage whoosh; muzzle flash on every shot; ~15–20 cues.
- G-FR76: Music (optional): 1 combat + 1 boss track; drops out during Tarek's silence.
- G-FR77: Art: neon/vector colour language (cyan/teal Coalition, magenta/red enemies, gold orbs, grey-brown asteroids); 2 space backgrounds + throne-world arc in L3 only; 3 portraits (Isolde, Tarek, Ryn; Vale optional); damaged Tarek variant; missile smoke trail; shield bubble.

**Release**
- G-FR78: Windows build zipped and published as a GitHub release with a README (controls, premise). MUST (decision #14).

**Total FRs: 78**

### Non-Functional Requirements

- G-NFR1 (Performance): 60 FPS sustained at 1920×1080 on the dev laptop (integrated GPU) during the busiest wave; headroom target of 40 enemies + 200 projectiles + particles.
- G-NFR2 (Performance): Cold launch to the title screen in under 5 s.
- G-NFR3 (Platform/Size): Build size under 200 MB.
- G-NFR4 (Platform): Windows 10/11 64-bit; zipped exe, no installer; Godot 4 + GDScript.
- G-NFR5 (Input/Usability): Mouse + keyboard only; no gamepad or keyboard-only fallback in v1.0.
- G-NFR6 (Reliability): No crash or soft-lock across 3 full start-to-finish playthroughs.
- G-NFR7 (Reliability): Every scripted story beat fires on every playthrough.
- G-NFR8 (Usability/Readability): Enemy projectile readability + ≥0.3 s telegraph rule (Pillar 1).
- G-NFR9 (Usability): Controls understood without verbal help by L1 W2.
- G-NFR10 (Balance): First-time player clears each level in 1–3 attempts; playthrough 10–15 min (~3–4 min/level).
- G-NFR11 (Maintainability/Tunability): All numeric values are first-pass, exposed as data, easily changed; changes logged in `decision-log.md`.
- G-NFR12 (Licensing): Free/CC0 assets only (Kenney, free-licence music); public non-commercial repo.
- G-NFR13 (Schedule): Everything (planning + build) fits in ~20 h; MUST ~13 h, SHOULD ~4 h.

**Total NFRs: 13**

### Additional Requirements & Constraints

- **Gate:** E1 must be finished and judged fun (dev + ≥1 colleague) before E5 starts.
- **Build order:** E1 → E8; cut order COULD → SHOULD, with Tarek's fall the last SHOULD item to cut.
- **Tuning knobs:** +1 heart first, then higher drop rates.
- **Out of scope:** multiplayer, upgrades/shops/score, VO/cutscenes, non-Windows, gamepad, difficulty settings, timers/ratings, asteroid weapons/shatter combo, text crawl, prologue.
- **Open items:** dialogue script unwritten; laptop specs unrecorded (performance assumption).

### GDD Completeness Assessment

The GDD is strong for a ~20-hour project. Nearly every mechanic has concrete, tunable numbers, the MoSCoW tiers are explicit, and the decision log is current up to #20. Gaps and ambiguities I noted during extraction:

1. **No UI/HUD layout spec.** HUD elements are listed (hearts, energy bar with 50/100 markers, cooldown ring, wave bar, boss bar, convoy bar, comms panel), but their placement, sizes, and screen-overlap rules are missing. The comms panel position vs the 60% player zone is undefined. This is the UX gap.
2. **End screen content** is unspecified (text? credits? return-to-title?).
3. **Retry prompt UX** is unspecified (button vs auto, wording; does it offer Quit to Title?).
4. **Level Select after completion:** behaviour of "Play" once all three levels are cleared is undefined (replay L3? L1?).
5. **Save on level clear only.** The GDD doesn't say whether quitting mid-level loses the energy earned in that level (implied yes). Also unspecified: whether L3 clear/game-complete is recorded.
6. **Level 3 Wave 3 / boss transition:** the GDD doesn't say whether the 2.0 s gap or a story beat precedes the Flagship arrival.
7. **Ally kill-share target (10–15%)** is a balance goal with no explicit verification step.
8. **Tutorial prompts** ("Energy, Shield, and Barrage prompts" in L1 W4) are delivered as comms lines. The GDD doesn't say whether the energy prompt is cut if Energy (SHOULD) is cut.

## Epic Coverage Validation

`epics.md` contains its own requirements inventory (FR1–FR65, NFR1–NFR12) and an FR Coverage Map. Every story carries a `Tier / Covers` line. I traced the 78 G-FRs from this report against story **acceptance criteria**, not just the map, so a requirement only counts as covered if a story's AC actually implements it.

### Coverage Matrix

| G-FR | Requirement (short) | Epics FR | Story coverage | Status |
|---|---|---|---|---|
| G-FR1 | Fixed 1920×1080 playfield | FR59/arch | 1.1, 4.5 | ✓ |
| G-FR2 | Cursor-chase movement | FR1 | 1.2 | ✓ |
| G-FR3 | Bottom 60% bounds, no rotation | FR1 | 1.2 | ✓ |
| G-FR4 | 24 px hurtbox | FR2 | 1.2 | ✓ |
| G-FR5 | Hidden/confined cursor + reticle | FR3 | 1.2 | ✓ |
| G-FR6 | Laser | FR4 | 1.3 | ✓ |
| G-FR7 | Missile damage/splash/cooldown | FR5 | 1.5 | ✓ |
| G-FR8 | Missile aim vector / 32 px rule | FR5 | 1.5 | ✓ |
| G-FR9 | Cooldown ring | FR5, FR62 | 1.5 | ✓ |
| G-FR10 | Asteroids block both sides | FR6 | 1.4, 2.5, 2.6, 3.5 | ✓ |
| G-FR11 | Enemy hitbox ~80% | FR25 | 1.4 | ✓ |
| G-FR12 | No friendly fire | FR7 | 1.3, 6.1, 6.4 | ✓ |
| G-FR13 | Projectiles only, no hitscan | (implicit) | 1.3 projectile contract | ✓ |
| G-FR14 | Ramming small/medium | FR9 | 3.1 | ✓ |
| G-FR15 | 5 hearts, refill rules | FR9, FR11 | 3.1, 3.2 | ✓ |
| G-FR16 | Damage table | FR9, FR23, FR33, FR52 | 3.1, 6.2, 6.3, 7.3 | ✓ |
| G-FR17 | 1.2 s i-frames, 10 Hz flicker | FR10 | 3.1 | ✓ |
| G-FR18 | Orbs: value, drift, magnet, despawn | FR13 | 3.3 | ✓ |
| G-FR19 | Energy carry/save/reset | FR14 | 3.2, 4.2, 4.4 | ✓ |
| G-FR20 | Drop table | FR13, FR52 | 3.3, 7.3, 7.4 | ⚠️ Partial: **Maul 25% drop is in no story's AC** |
| G-FR21 | Shield | FR15 | 3.4 | ✓ |
| G-FR22 | Barrage | FR16 | 3.5 | ✓ |
| G-FR23 | Denied feedback | FR17 | 3.4, 3.5 | ✓ |
| G-FR24 | Asteroid sizes/stats | FR18 | 1.4 | ✓ |
| G-FR25 | Asteroid behaviour, uncounted | FR18 | 1.4, 2.2 | ✓ |
| G-FR26 | Size-scaled feedback tiers | FR30 | 1.6, 2.7, 3.1, 3.2, 3.5, 7.3, 7.5 | ✓ |
| G-FR27 | Death feedback + 1.5 s pause | FR12 | 3.2 | ✓ |
| G-FR28 | Wasp | FR19 | 2.4 | ✓ |
| G-FR29 | Lancer | FR20 | 2.5, 6.3 | ✓ |
| G-FR30 | Needle | FR21 | 2.6 | ✓ |
| G-FR31 | Bastion | FR22 | 2.7 | ✓ |
| G-FR32 | Maul | FR23 | 6.2 | ✓ |
| G-FR33 | Hunter Wasp (COULD) | FR24 | 2.8 | ✓ |
| G-FR34 | Projectile readability | FR25 | 2.5 | ✓ |
| G-FR35 | ≥0.3 s telegraph rule | FR25 | 2.4 (GUT data test) | ✓ |
| G-FR36 | Wasp off-screen re-entry | FR19 | 2.4 | ✓ |
| G-FR37 | Data-scripted waves | FR26 | 2.2 | ✓ |
| G-FR38 | Wave clear + 2.0 s gap | FR27 | 2.1, 2.2 | ✓ |
| G-FR39 | Wave progress bar | FR29 | 2.3 | ✓ |
| G-FR40 | Event-triggered beats | FR28 | 2.1, 2.2, 5.3 | ✓ |
| G-FR41 | Mid-wave reinforcements | FR28, FR43 | 2.2 (`spawn_group`), 5.6, 7.1 | ✓ |
| G-FR42 | Convoy path + shared HP | FR32 | 6.1 | ✓ |
| G-FR43 | Convoy hit rules | FR33 | 6.1, 6.3 | ✓ |
| G-FR44 | Convoy loss | FR33 | 6.1 | ✓ |
| G-FR45 | Ally ships | FR34 | 6.4 | ✓ |
| G-FR46 | Tarek's fall | FR35 | 6.5, 7.2 | ✓ |
| G-FR47 | Comms panel | FR37 | 5.1 | ✓ |
| G-FR48 | Story vs combat lines | FR38 | 5.1, 5.2 | ✓ |
| G-FR49 | Input ignored during story | FR8 | 5.1 | ✓ |
| G-FR50 | Cut-off effect | FR40 | 5.4 | ✓ |
| G-FR51 | Opening sequence | FR41 | 5.5, 5.7 | ✓ |
| G-FR52 | Isolde interruptions | FR42 | 5.6, 7.1, 7.2, 7.6 | ✓ |
| G-FR53 | L1 Surrender Prompt | FR43 | 5.6, 7.1 | ✓ |
| G-FR54 | On/off flags | FR61 | 1.1, 5.6 | ✓ |
| G-FR55 | Level-specific beats | FR44 | 5.7, 7.1, 7.2, 7.6 | ✓ |
| G-FR56 | Dialogue script | FR45 | 5.7 | ✓ |
| G-FR57 | Level 1 content | FR46 | 7.1 | ✓ |
| G-FR58 | Level 2 content | FR47 | 7.2 | ✓ |
| G-FR59 | Level 3 content | FR48 | 7.6 | ✓ |
| G-FR60 | Flagship Phase 1 | FR49 | 7.3 | ✓ |
| G-FR61 | Flagship Phase 2 | FR50 | 7.4 | ✓ |
| G-FR62 | Flagship Phase 3 + Final Choice | FR51 | 7.5 | ✓ (see note on Vale's line) |
| G-FR63 | Boss-death tier | FR54 | 7.5 | ✓ |
| G-FR64 | Boss bar | FR53 | 7.3 | ✓ |
| G-FR65 | Hull contact 2 hearts | FR52 | 7.3 | ✓ |
| G-FR66 | Final line → end screen (+COULD epilogue) | FR54, FR55 | 7.7, 7.8 | ✓ |
| G-FR67 | Level win rules | FR60 | 2.2, 7.7 | ✓ |
| G-FR68 | Level loss / unlimited retry | FR12, FR33 | 3.2, 6.1 | ✓ |
| G-FR69 | Unlock next | FR58 | 4.2 | ✓ |
| G-FR70 | Title screen | FR56 | 4.1, 4.2, 4.3 | ✓ |
| G-FR71 | Pause menu | FR57 | 4.4 | ✓ |
| G-FR72 | Save to app data | FR58 | 4.2 | ✓ |
| G-FR73 | Display modes | FR59 | 4.5 | ✓ |
| G-FR74 | Data-driven content | FR61 | 1.1, 2.2, 5.1 | ✓ |
| G-FR75 | SFX set + scaling | FR31, FR63 | 1.6, 8.1 | ✓ |
| G-FR76 | Music + silence drop-out | FR63 | 5.3, 5.4, 8.1 | ✓ |
| G-FR77 | Art direction/assets | FR64 | 8.2 | ✓ |
| G-FR78 | GitHub release | FR65 | 8.5 | ✓ |

**NFR traceability:** G-NFR1→1.7, 8.3; G-NFR2→4.1, 8.3; G-NFR3→8.3, 8.5; G-NFR4→1.1, 8.5; G-NFR5→1.1 (input map); G-NFR6/7→8.4; G-NFR8→2.4, 2.5; G-NFR9/10→7.1, 8.4; G-NFR11→1.1, 1.7, 8.4; G-NFR12→8.1, 8.2; G-NFR13 (schedule) is a process constraint with no story (expected).

**Epics FRs not in the GDD:** none in substance. Epics NFR11 (security/privacy) and NFR12 (static typing, no runtime plugins) come from the architecture, which is a legitimate source. Epics FR36 (scrolling convoy, COULD) is explicitly deferred with no story (decision F9). That is acceptable: the GDD lists it as deferred too.

### Missing Requirements

**Critical missing FRs:** none.

**Minor gaps or ambiguities:**

1. **G-FR20: Maul energy drop (25%).** Story 3.3 lists drop chances before the Maul exists, and Story 6.2 doesn't mention drops. Also undefined: does a Maul that self-destructs on the convoy, or misses, roll a drop? (Probably only player/ally kills should.)
   - *Recommendation:* add an AC to Story 6.2: "A Maul killed by the player or an ally rolls `tuning.drops.maul` (25%); a Maul that impacts the convoy or misses drops nothing."
2. **G-FR62: Vale's surrender line at the Final Choice.** The GDD says Vale speaks a few lines, "for example, offering surrender at the Final Choice". Story 5.7 requires the surrender offer to exist in the script, but Story 7.5's flow goes from the click straight to Isolde's response. It never says whether a Vale line plays first.
   - *Recommendation:* in Story 7.5, make each option's `next` sequence start with Vale's line (surrender offer or vow), followed by Isolde's response.
3. **Tutorial energy prompt when Energy (SHOULD) is cut.** Story 7.1 plays the W4 "energy, Shield, Barrage" tutorial line unconditionally. If Stories 3.3–3.5 are cut, that line teaches a feature that doesn't exist.
   - *Recommendation:* gate the W4 line behind an `energy` flag, or add a cut-dependency note.

### Coverage Statistics

- Total GDD FRs (G-FR): 78
- Fully covered: 77
- Partially covered: 1 (G-FR20, Maul drop)
- Missing: 0
- **Coverage: 98.7% full, 100% at least partial**
- NFRs traced: 12/13 (schedule NFR is a process constraint)

## UX Alignment Assessment

### UX Document Status

**Not found.** No `*ux*` document exists in `planning-artifacts/` or elsewhere in the project. `epics.md` acknowledges this and folds the GDD's UI statements into FR3, FR29, FR37, FR51, FR53, FR56, FR57 and FR62.

**Is UX implied?** Yes, heavily. This is a player-facing game with:
- a 6-element HUD (hearts, energy bar with 50/100 markers, missile cooldown ring, wave bar, boss bar, convoy bar), plus a red-edge hit vignette and a shield bubble
- a comms panel that sometimes **overlays live combat** (combat lines don't pause)
- 5 menus or screens: title, level select, pause, retry prompt and end screen, plus a story scene
- a modal Final Choice

### What the GDD and Architecture already pin down

| Concern | Source | Status |
|---|---|---|
| UI tech (Control under CanvasLayers, one shared Theme) | Arch D19, §315 | ✓ Defined |
| Layer order: HUD (10) < Comms (20) < Overlay (30) | Arch §269–271 | ✓ Defined |
| Process modes (HUD pausable; comms/menus always) | Arch §236–238 | ✓ Defined |
| HUD reads only `Events` | Arch §316 | ✓ Defined |
| Click-through prevention (comms click ≠ laser) | Arch §1080, R1 | ✓ Defined |
| Mouse visibility per pause reason | Arch Pause Arbiter, Story 1.2 | ✓ Defined |
| Wave bar placement | GDD "top-centre" | ✓ Defined |
| Final Choice: two large centred buttons, no timer | GDD | ✓ Defined |
| Colour language | GDD Art | ✓ Defined |
| Comms text speed | Story 5.1 (45 chars/s) | ✓ Defined |

### Alignment Issues (gaps the stories will hit)

1. **The comms panel position and size are undefined.** This is the most important gap. Combat lines run *during* play, and the player, convoy (y 780–880) and allies (y 620–760) all live in the bottom 60%. If a developer docks the panel at the bottom (the usual dialogue convention), it covers the convoy and the player's dodge space during interruptions and Tarek's cut-off. If it docks at the top, it covers enemies (top 40%), Needle anchors and Bastions (y 80–400). The choice affects Pillar 1 (readability) and needs a decision before Story 5.1.
2. **HUD element placement is undefined beyond the wave bar.** Hearts, energy bar, convoy bar and boss bar have no positions, so they could collide with the wave bar, the comms panel or the play area. The boss bar "replaces" the wave bar, which implies the same top-centre slot. Fine, but unstated.
3. **The HUD shares the top band with enemies.** The wave and boss bars sit top-centre over the area where Wasps form and Needles anchor (top edge). Something needs to cap the HUD's height (for example ≤ 48 px) or reserve a safe band.
4. **The energy bar's 50/100 markers and the "denied" flash** have no visual spec. Minor; the Theme will handle it.
5. **Retry prompt content is undefined.** Stories 3.2 and 6.1 imply a single Retry button. Undecided: whether to show the loss reason ("Convoy destroyed" vs "Hull destroyed"), which helps players learn the convoy rule, and whether to offer Quit to Title.
6. **End screen content is decided only in the story** (Story 7.7: title, closing line, "Thanks for playing", back to title). Acceptable, but nothing upstream records it.
7. **Story scene vs in-level comms panel.** Story 5.5 reuses the comms panel on a static background. No conflict.
8. **The 1.5 s death pause vs the convoy-loss path.** Story 6.1 says "same retry flow". Consistent.
9. **The cursor and reticle at screen edges** under letterboxing (Story 4.5 AC covers tracking). OK.

### Warnings

- ⚠️ **WARNING: No UX/HUD specification for a UI-heavy, player-facing game.** The architecture fully supports the UI *technically* (layers, theme, signals and process modes are all defined), but the screen-layout decisions are missing. Those decisions affect gameplay readability, not just looks.
- **Severity: Medium.** It won't block Epics 1–4 (Story 1.5's cooldown ring sits on the reticle, so it needs no layout). It **will** block a clean implementation of Story 2.3 (wave bar sizing), Story 3.1/3.3 (hearts and energy placement), Story 5.1 (comms panel placement) and Story 6.1 (convoy bar).
- **Recommendation:** produce a **lightweight HUD/screen layout spec** before Epic 2 Story 2.3. A single-page `gds-ux` output (screen-zone map at 1920×1080, panel anchors and sizes, comms docking rule, retry/end screen contents) is enough. The GDD's 20-hour budget argues for a one-page spec, not a full UX document.

## Epic Quality Review

Scope: 8 epics and 50 stories (E1: 7, E2: 8, E3: 5, E4: 5, E5: 7, E6: 5, E7: 8, E8: 5), checked against the create-epics-and-stories standards. The architecture is consistent with the epics on engine version (4.7.2), GUT version (9.7.1), autoloads, layers, data paths and enemy ids.

### Epic Structure

| Epic | Player value | Independent of later epics | Notes |
|---|---|---|---|
| 1 Core Feel | ✓ playable sandbox | ✓ | Story 1.1 is a technical setup story. Acceptable for a greenfield project with no starter template (Arch R4) |
| 2 Enemies & Waves | ✓ | ⚠️ | Enemies fire, but the player has no `apply_damage` until Epic 3 (Story 2.5 degrades gracefully). Playable but stakes-free. Accepted by design |
| 3 Survival & Energy | ✓ | ✓ | |
| 4 Flow & Save | ✓ | ❌ **see M1** | Needs level data that only Epic 7 creates |
| 5 Comms & Story | ✓ | ✓ | Uses dev levels for verification |
| 6 Escort & Allies | ✓ | ⚠️ minor | Story 6.4's 10–15% kill-share check needs the real levels from Epic 7 |
| 7 Campaign & Boss | ✓ | ✓ | |
| 8 Polish & Release | ✓ | ✓ | |

No technical-milestone epics. Every epic title and goal is player-centric. The architecture's autoloads are introduced just-in-time (decision F4), which is the right pattern.

### 🔴 Critical Violations

None. No epic is purely technical, there are no circular dependencies, and no story is epic-sized to the point of being uncompletable.

### 🟠 Major Issues

**M1. Epic 4 forward-depends on Epic 7 level data.**
- Story 4.1 ("Play loads `level.tscn` for Level 1"), Story 4.2 ("starts Level N+1"), and Story 4.3 ("shows Levels 1–3 by name") all need `data/levels/level_1..3.json`. Those files are only created in Stories 7.1, 7.2 and 7.6. Until then only `level_dev.json` exists (Story 2.2), so `Config.level(1)` errors and the data test fails on missing files.
- *Remediation:* add an AC to Story 4.1 (or 2.2): "Create placeholder `level_1/2/3.json` (name, 1–2 Wasp waves, `convoy`/`ally` flags unset) so flow and save are testable. Epic 7 stories replace their content." Also define where level display names come from (a `name` key in each level JSON).

**M2. Energy state leaks across Quit to Title.**
- Story 4.4 Quit to Title says "nothing is saved", and Story 4.2/4.3 start levels "with the saved energy". `GameState.energy` is an in-memory autoload value, though. After quitting mid-level, it still holds the mid-level amount unless something reloads it from the save. The ACs never say what does.
- Related: retry sets energy to 0 in memory, but the save keeps the last cleared value. So "die → Quit to Title → Play" restores the energy, while "die → Retry" gives 0. That's harmless, but should be a conscious choice.
- *Remediation:* add an AC to Story 4.2: "`SceneRouter.goto_title()` (or starting a level from a menu) restores `GameState.energy` and `highest_unlocked_level` from `SaveManager`." Also record the die/quit/Play energy behaviour as an accepted quirk in the decision log.

**M3. Cutting the Hunter Wasp breaks the data test for Level 3.**
- Story 7.6 says that if Story 2.8 is cut, the Level 3 W2 Hunter entry "is logged as unknown and subtracted". But Story 2.2's `test_data_files.gd` fails any level JSON with an unknown enemy type.
- Story 2.8 says a flag-off entry is "skipped, not counted, logged at DEBUG". That only works if `hunter_wasp` is a registered type.
- *Remediation:* keep `hunter_wasp` in the known-type list (id reserved in Arch §656) whether or not its scene exists, and drive the skip purely by flag. Then remove the "logged as unknown" wording from Story 7.6.

**M4. The HUD and comms layout are unspecified** (from the UX step). Stories 2.3, 3.1, 3.3, 5.1, 6.1 and 7.3 each place UI elements, and no story or document says where.
- *Remediation:* produce a one-page HUD/screen layout spec before Story 2.3, and reference it from those stories.

**M5. Schedule realism: 50 stories against about 13–17 build hours.**
- Planning (brief, GDD, architecture, epics) has already used day 1 of the 3-day, ~20 h budget. That leaves about 13–14 h, roughly 16 minutes per story. Large stories (1.1, 2.2, 5.1, 7.5) alone could each take 1 h or more for a Godot newcomer.
- The cut order (COULD → SHOULD) exists, but no story-level hour estimates or checkpoints say *when* to cut.
- *Remediation:* at sprint planning, add a time checkpoint per epic, for example "end of day 2 = Epic 4 done, else cut SHOULD energy". Pre-mark the cut candidates (2.8, 7.8, 3.3–3.5, 6.4, 5.6, 8.1–8.2).

### 🟡 Minor Concerns

- **m1. Story 2.1 is a technical story** (pure logic classes, a "designer" persona). It's small and tested, so it's acceptable as an enabler, but it could be folded into Story 2.2's ACs.
- **m2. Story 2.2 is oversized.** It covers the level scene, the wave director, trigger chains, error handling, data tests, F3/F6 debug and the dev level. Consider splitting debug F3/F6 and the overlay additions into a small follow-on story.
- **m3. Story 1.1 front-loads every GDD number into `tuning.json`.** That slightly contradicts "data created when needed", but one source-of-truth tuning file is reasonable here. Accept.
- **m4. Contact during i-frames is undefined.** Story 3.1 ignores damage during the 1.2 s window but doesn't say whether a small enemy touching the ship is still destroyed or passes through. Pick one; destroyed with no damage is the most generous (Pillar 1).
- **m5. Boss telegraph values aren't covered by the telegraph data test.** Story 2.4's data test checks only `tuning.enemies`. Extend it to `tuning.boss` (Arch §1042 says *every* attack).
- **m6. Boss-launched Wasps during Phase 3 are undefined.** It isn't stated whether launches continue in DESPERATE or whether live Wasps remain (Story 7.4/7.5). Recommend: launches stop at FINAL_CHOICE, and existing Wasps stay.
- **m7. The Windows export is first attempted at the very end (Story 8.5).** Export templates, the `data/*.json` non-resource filter, and Forward+ behaviour on the integrated GPU all surface only in an exported build. Recommend a 10-minute export smoke check at the end of Epic 1 (Story 1.7) or Epic 4.
- **m8. Maul drop, Vale's Final Choice line and the energy tutorial gating** (from coverage, step 3).
- **m9. Story 5.5 replays the opening every time Level 1 is started from Level Select.** That's probably intended; confirm it.
- **m10. NFR11 says the repo contains no machine paths,** but `game-architecture.md` contains local Godot install paths (since replaced with `<GODOT_DIR>`) and will be public if `_bmad-output/` is committed. Decide whether planning artifacts ship in the public repo.

### Acceptance Criteria Quality

- **Format:** every story uses Given/When/Then consistently, with exact numbers, file paths, signal names and data keys. That is well above typical quality.
- **Testability:** high. Logic is covered by GUT tests (config, save, wave progress, beat trigger, pause arbiter, data files), and feel by explicit playtest gates (Stories 1.7, 8.4).
- **Error paths:** well covered (corrupt save, unknown sequence, unknown enemy, parse failure, death mid-chain, flag-off paths). Gaps are M2, M3 and m4.

### Dependency Analysis

- **Within-epic:** all sequential. Placeholder notes (Story 5.5 → 5.7 text, Story 4.2 → 7.7 end screen) point backward or are explicitly temporary (decision F5). ✓
- **Cross-epic:** M1 (Epic 4 → Epic 7 data) is the only real forward dependency. Story 6.4's balance check needing Epic 7 levels is a soft verification dependency.
- **Shared-file growth** (`wave_director.gd` in Stories 2.2/5.3/7.3, and `comms_channel.gd` in 5.1–5.4/7.5) is acknowledged in the epics validation. ✓

### Special Checks

- **Starter template:** none. Story 1.1 creates the project. ✓
- **Greenfield setup:** project setup ✓, dev environment (headless GUT/CLI) ✓, build pipeline late (see m7).

### Best Practices Checklist

| Check | E1 | E2 | E3 | E4 | E5 | E6 | E7 | E8 |
|---|---|---|---|---|---|---|---|---|
| Player value | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Independent | ✓ | ✓ | ✓ | ❌ M1 | ✓ | ~ | ✓ | ✓ |
| Story sizing | ~ 1.1 | ~ 2.2 | ✓ | ✓ | ✓ | ✓ | ~ 7.5 | ✓ |
| No forward deps | ✓ | ✓ | ✓ | ❌ M1 | ✓ | ~ | ✓ | ✓ |
| Data created when needed | ~ m3 | ✓ | ✓ | ❌ M1 | ✓ | ✓ | ✓ | ✓ |
| Clear ACs | ✓ | ✓ | ~ m4 | ~ M2 | ✓ | ✓ | ~ m6 | ✓ |
| FR traceability | ✓ | ✓ | ✓ | ✓ | ✓ | ~ m8 | ✓ | ✓ |

## Summary and Recommendations

### Overall Readiness Status

**NEEDS WORK (minor). Fixable in about 1 hour of planning edits, with no re-planning required.**

The planning set is unusually strong for a 20-hour project:
- The GDD is numerically complete.
- The architecture is concrete and cross-checked.
- FR coverage is 77/78 full and 78/78 at least partial.
- Every story has precise, testable Given/When/Then ACs, with GUT tests and playtest gates.

What's missing is a handful of seams between epics and one missing artefact (the HUD/comms layout). None needs a structural rework.

### Critical Issues Requiring Immediate Action

There are no critical (🔴) violations. These major (🟠) items should be fixed before sprint planning:

1. **M1:** Epic 4 forward-depends on Epic 7 level files. Add placeholder `level_1..3.json` (with a `name` key) early.
2. **M2:** `GameState.energy` isn't reloaded from the save on Quit to Title or menu starts.
3. **M3:** cutting the Hunter Wasp breaks the Level 3 data test. Keep the `hunter_wasp` type id registered; the flag controls skipping.
4. **M4:** there is no HUD/comms screen-layout spec, and six stories place UI. The comms panel's dock position directly affects Pillar 1 readability.
5. **M5:** 50 stories against about 13–14 remaining build hours, with no time checkpoints for applying the cut order.

### Recommended Next Steps

1. **Patch `epics.md`** for M1, M2, M3 and minor items m4–m8 (AC additions only, plus Facilitator Decisions entries for the design choices).
2. **Create a one-page HUD/screen layout spec** with `gds-ux` (screen-zone map, HUD anchors, comms docking rule, retry/end screen contents). Reference it from Stories 2.3, 3.1, 3.3, 5.1, 6.1 and 7.3.
3. **At sprint planning (`gds-sprint-planning`):** add per-epic time checkpoints, pre-mark the cut candidates, and add a 10-minute Windows export smoke check at the end of Epic 1 (m7).
4. **Decide whether `_bmad-output/` ships in the public repo** (m10, NFR11). If it does, scrub the machine paths from `game-architecture.md`.

### Issue Tally

| Severity | Count | Items |
|---|---|---|
| 🔴 Critical | 0 | |
| 🟠 Major | 5 | M1–M5 |
| 🟡 Minor | 10 | m1–m10 (including the coverage items: Maul drop, Vale's Final Choice line, energy tutorial gating) |
| ⚠️ Warning | 1 | No UX document (folds into M4) |

### Final Note

This assessment found **16 issues across 4 categories** (coverage, UX alignment, epic structure, schedule), and none of them is critical. Fix M1–M4 before implementation starts; M5 belongs in sprint planning. You can also proceed as-is, since none of the issues blocks Epic 1, but M1 and M4 will hurt by Epic 2 or 4.

---

**Assessed by:** Game Producer / Scrum Master (gds-check-implementation-readiness), for iman2001-ie
**Date:** 2026-10-06

## Remediation Applied (2026-10-06, same session)

The user authorized fixes. Applied to `epics.md` (Facilitator Decisions F12–F19) and logged as GDD decision #21:

| Issue | Fix | Where |
|---|---|---|
| M1 | Placeholder `level_1/2/3.json` with `name` keys | Story 4.1 AC, F12 |
| M2 | Energy and unlocks restored from the save on `goto_title()` | Story 4.2 AC, F13 |
| M3 | `hunter_wasp` always a known type; flag-only skip | Story 2.8 AC, Story 7.6 wording, F14 |
| m4 | Contact during i-frames destroys enemy, no cost | Story 3.1 AC, F15 |
| m5 | Telegraph data test covers `tuning.boss` | Story 2.4 AC |
| m6 | Boss Wasp launches stop at Final Choice | Story 7.4 AC, F16 |
| m7 | Export smoke check at end of Epic 1 | Story 1.7 AC, F19 |
| m8 | Maul drop rule; Vale's Final Choice line; W4 energy tutorial removed if energy is cut | Stories 6.2, 7.5, 7.1; F17, F18 |

**Still open:** M4 (HUD/comms layout spec, next via `gds-ux`), M5 (time checkpoints, handled in sprint planning), m1/m2 (optional story splits), m9 (confirm the opening replays from Level Select), m10 (public-repo decision on `_bmad-output/`).

## Remediation Update: UX and Design Changes (2026-10-06, same session)

**M4 closed.** The UX spec was created with `gds-ux` at `ux-designs/ux-defector-game-2026-10-06/`:
- `DESIGN.md`: Cold Neon palette (contrast verified), Kenney Future font, a 1920×1080 layout table for every HUD element and screen, and an asset direction (Kenney Space Shooter Redux and Extension).
- `EXPERIENCE.md`: the dialogue model, HUD behaviour, state patterns, accessibility floor and key flows.
- `mockups/key-hud.html`: the HUD mock.
- A rubric review found 0 blockers. All 13 should-fix items are resolved; 17 nits remain in `review-rubric.md`.
- The epics reference the spec through UX-DR1 to UX-DR7.

**Design changes made with the user during the UX session** (GDD v0.3, decisions #22–#25):
- **Dialogue model:** paused briefings and debriefs carry the story. There are at most 2 one-line interruptions per level and only two mid-fight pauses in the game. Tutorials became on-screen control hints (new FR66 and Story 5.8). Briefings are skipped on retry.
- **Convoy:** three medium cargo ships fly in a tight triangle (band y 760–920) and are solid to everything. Enemy shots damage it (aimed 5, stray 2). Player and ally shots are blocked without damage. The player's ship is blocked too, so the player can body-block shots aimed at the convoy.
- **Updated to match:** the architecture's collision masks and damage rules, and Stories 5.1, 5.2, 5.3, 5.7, 5.8, 6.1, 6.3, 7.1 and 7.6.

**Balance watch item:** stray enemy fire can now hit the convoy, so Level 1 is harder. The tuning knobs are convoy HP (100) and stray damage (2).

**Remaining open items:**
- **M5:** add per-epic time checkpoints at sprint planning.
- **m1/m2:** optional story splits.
- **m9:** whether the opening replays when Level 1 is started from Level Select.
- **m10:** whether `_bmad-output/` ships in the public repo.

**Updated status: READY for sprint planning.**

## Open Items Closed (2026-10-06)

The user approved every decision in the GDD, UX and epics decision logs.
- **M5:** closed by the user's decision. There are no per-epic time checkpoints; the team implements in epic order as far as time allows, and the existing cut order (COULD, then SHOULD) applies.
- **m9:** confirmed. The opening replays whenever Level 1 is started from Play or Level Select (Story 5.5), but never on retry or restart.
- **m10:** the user plans to publish the whole `defector-game` directory as a personal GitHub repo. Prep items are listed in the session summary: a personal git email, personal paths in `.claude/settings.json`, `.gitignore` entries, and wording about the dev laptop.
