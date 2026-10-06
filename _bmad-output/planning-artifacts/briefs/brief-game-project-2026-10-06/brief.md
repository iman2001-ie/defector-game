---
title: 'Game Brief: DEFECTOR'
status: final
created: '2026-10-06'
updated: '2026-10-06'
---

# Game Brief: DEFECTOR

## Executive Summary

**DEFECTOR** is a short 2D space shooter campaign for Windows PC. You play a general who defected from a tyrant's fleet and now leads the rebellion against her. You fly with the mouse, cut through enemy waves with lasers and missiles, protect your allies, and see the war through to her throne world.

The game pairs the readable, satisfying arcade shooting of *Chicken Invaders* with the personal, character-driven war stories of *Call of Duty* campaigns and *Red Rising*. All of the story runs through one system, a comms panel with character portraits. That system delivers briefings, the dictator's taunts, a mentor's sacrifice, and a final choice, without cutscenes or animation.

It's being built solo during a one-week team BMAD hackathon, within a budget of about 20 hours. The goal is to learn the complete BMAD workflow from start to finish and ship a working three-level game. Working beats perfect.

## Vision

**Core fantasy:** *You are the general who walked away from a tyrant, and now you're the one who brings her down.*

**Elevator pitch:** Chicken Invaders meets a CoD campaign. A neon space shooter where every enemy fleet belongs to the woman you used to serve.

**What players walk away with:** The rush of a good shooter, plus one or two story moments that stick. The mentor going silent mid-sentence. The dictator refusing your offer of surrender.

## Target Players

- **Primary:** Iman's colleagues at the hackathon. They're developers and casual players, and will try it once out of curiosity, in a single session of about 10–15 minutes. They need it to launch easily, make sense instantly, and be finishable.
- **Secondary:** Anyone who finds the public GitHub repo. Same needs: download, play, done.
- **Market:** Not applicable. This is a learning and hackathon project, not a commercial release. No market positioning is needed.

## Core Fundamentals

**Genre:** 2D arcade space shooter with a light narrative campaign.

**Core loop:** The ship follows the mouse → hold left-click to fire lasers, right-click for a missile → destroy waves of enemies and asteroids → collect energy drops → spend energy on command powers (Shield or Barrage) → clear the waves to advance the story → next level.

**Pillars:**
1. **Skilled, Not Hopeless.** Challenging but always winnable. The player should feel like a good shot. Failure restarts only the current level, with unlimited retries.
2. **Impact Scales with Size.** Explosion size, screen shake and threat all grow with the size of the object: small ship < missile < large asteroid < boss.
3. **Story Through One System.** Every story beat goes through the comms panel and scripted events. There are no cutscenes. Cheap tricks (interrupted text, silence, screen shake) carry the emotional weight.

**Primary mechanics:**
- Mouse-follow movement; laser (left click, hold); unguided missile (right click, cooldown)
- Asteroids in several sizes act as solid cover against all lasers and damage the player on contact
- Energy bar filled by random drops: Shield (E) and Barrage (Q). Energy carries over between levels and is wiped on death.
- Escort objective: a shared convoy health bar
- Wave-based levels, a phased boss, and level unlocking

## References & Differentiation

| Reference | Taking | Deliberately not taking |
|---|---|---|
| **Chicken Invaders (Universe)** | Mouse-follow controls, formation waves, enemy variety, a clean modern look | Comedy tone, deep upgrade and economy systems |
| **Call of Duty campaigns** (gunship missions) | Air-support and escort fantasy, radio chatter, character-loss moments | Cinematic cutscenes, realism |
| **Red Rising** | A personal war against a tyrant, the defector arc, the mentor and the rival ace, the council ending | Its characters and names (all names are original) |
| **The Last of Us** | Protecting someone, scarcity decisions (saving energy), an emotional gut punch | Stealth, crafting, bleak tone throughout |

**What sets it apart (honestly):** It isn't a technical breakthrough. What makes it different is a *personal* story told entirely through gameplay-integrated dialogue in an arcade shooter, plus the surrender "mirror" (she tempts you to give up, and later you offer her the same choice).

## Scope & MVP

- **Platform:** Windows PC only. Distributed as a downloadable build in a public personal GitHub repo.
- **Engine and tools:** Godot 4 with GDScript (Python-like, matching the developer's strongest language). Free asset packs (e.g. Kenney) for art and sound. No 3D tools.
- **Team:** One developer, a 4th-year CS student who is new to Godot 2D and learning along the way.
- **Timeline:** 3 days × 6–7 hours (about 20 hours) during a one-week hackathon. This budget covers **both** the BMAD planning workflow and implementation. Possible polish afterward, not guaranteed.

**MVP = "Done" after day 3:** An opening dialogue sequence plus **three playable levels, start to finish**:
1. **Cargo Ambush:** escort the convoy, learn the controls, and meet the dictator
2. **The Blockade:** break the wall, and the mentor falls
3. **Siege of the Throne World:** defeat the flagship boss and see the ending

Each level needs to be beatable, and the story beats need to fire. Working beats polish.

**Core hypothesis the MVP validates:** Mouse-follow shooting with size-scaled feedback is fun on its own, and story delivered only through comms dialogue makes the player care.

**Scope tiers:**
- **MUST:** controls with both weapons; 4 enemy types; asteroid cover; waves and level unlocking; comms panel; size-scaled explosions; 3 levels; flagship boss
- **SHOULD:** energy, Shield and Barrage; the mentor's fall sequence; the successor's ship; dictator interruptions and surrender prompts; throne world background
- **COULD:** scrolling convoy, hunter AI, council epilogue, stretch levels (Ambush in the Void, The Ace)
- **Out of scope:** multiplayer, upgrades or shops, voice acting, platforms other than Windows

## Content & Direction

- **World:** A solar system ruled by Sovereign Isolde Varn's **Sovereignty**, opposed by General Arden Vale's **Free Worlds Coalition**.
- **Narrative:** Linear, three chapters, delivered by a comms panel with portraits and typewriter text. Story dialogue pauses the game; combat lines don't. The surrender prompts sit behind toggle flags.
- **Content size:** 3 levels, about 4–5 enemy types, 1 multi-phase boss, a cast of 4 speaking characters, and a playthrough of roughly 10–15 minutes.
- **Art:** Clean neon or vector 2D in the style of Chicken Invaders Universe, not retro. Glow, particles and screen shake for game feel. Free asset packs first.
- **Audio:** Free sci-fi sound effects (Kenney audio and generated laser sounds). Music is optional, from free-licence sources.

## Risks & Open Questions

| Risk | Mitigation |
|---|---|
| **Time:** the BMAD planning steps (GDD, architecture, epics, stories) take hours out of the 20-hour budget | Keep every document lightweight. Build the core-feel prototype early so there's always something playable. |
| **Learning curve:** first 2D Godot project | Prototype ship + laser + one enemy first. Lean on Godot's built-in nodes (particles, tweens, collision layers). |
| **Scope creep:** a big story for a small window | Cut in tier order (COULD → SHOULD). The mentor's fall is the SHOULD item to protect last. |
| **Ally and escort logic** is more complex than solo waves | Scripted paths, one shared convoy health bar, allied flagships can't be destroyed. |
| **Balance:** "death wipes energy" may be too harsh | It's a tuning knob. Use richer energy drops in the final level if playtests show it's needed. |

**Open questions for the GDD:** exact tuning values (health, cooldowns, drop rates, wave composition) and the Flagship phase details. Everything else is decided.
