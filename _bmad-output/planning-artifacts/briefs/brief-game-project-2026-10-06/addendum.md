---
title: 'Addendum: DEFECTOR Game Brief'
created: '2026-10-06'
updated: '2026-10-06'
---

# Addendum: DEFECTOR Game Brief

Detail decided during brainstorming that belongs in the GDD rather than the brief. Full source: `_bmad-output/brainstorming-session-2026-10-06.md`.

## Cast

| Role | Name | Notes |
|---|---|---|
| Player | General Arden Vale | Former general of the Sovereignty, defected; gender-neutral, usually addressed as "General" |
| Dictator | Sovereign Isolde Varn | Condescending and manipulative; alternates between trying to annihilate you and trying to talk you into surrendering |
| Mentor | Admiral Tarek Holt | Veteran general from another world (Pax-inspired role); briefs missions, gravely wounded at the Blockade, survives |
| Successor | Commander Ryn Holt | Tarek's daughter; takes command of his ship for the finale |
| Rival (stretch) | Soren Kade | Former star student turned Sovereignty ace; uses your tactics |

## Controls

- Left click (hold): laser auto-fire
- Right click: unguided missile (unlimited, short cooldown shown as a radial ring)
- Q: Barrage (costs 100 energy)
- E: Shield (costs 50 energy)

## Enemy Roster

| Enemy | Size | Behaviour | Tier |
|---|---|---|---|
| Wasp | Small | Fast, fragile, formations, dives at player | MUST |
| Lancer | Medium | Strafes, fires aimed shots | MUST |
| Needle | Medium | Sniper; telegraphs with a targeting line, which teaches asteroid cover | MUST |
| Bastion | Large | Slow, tanky turret gunship | MUST |
| Maul | Medium | Ignores player, dives at the convoy | SHOULD |
| Hunter Wasp | Small | Chases the player | COULD |

## Level Scripts (V1)

1. **Cargo Ambush:** Tarek teaches the controls in calm waves → ambush waves with Wasps, Lancers and Mauls → Isolde's first interruption (condescending) → Surrender Prompt in the final wave ("You're outnumbered, General. Come home.") → clear.
2. **The Blockade:** Bastions and Needles, with Tarek fighting alongside → final wave: Tarek shields the player, is cut off mid-sentence, screen shake, his ship trails fire, the channel goes silent → last enemies fall → Ryn reports he's alive but gravely injured and she's taking command.
3. **Siege of the Throne World:** Planet arc in the background → defence waves with Ryn → Flagship in three phases: (1) turrets, (2) exposed core plus Wasp launches, (3) at low health the game pauses, Isolde speaks, and the Final Choice appears [Offer Surrender] / [Destroy Her] → she refuses → desperate barrage → destruction → council epilogue (COULD).

## Systems Notes

- **Allies:** Convoy cargo ships follow a scripted path and share one health bar; if it hits zero, the level restarts. Tarek's and Ryn's ships follow scripted paths, fire at the nearest enemy, and can't be destroyed except for Tarek's scripted hit.
- **Energy:** Max 100, filled by random drops from enemies and asteroids. It carries over between levels and resets to 0 on death.
- **Player health:** A hull bar that takes several hits, with brief invulnerability and a flicker after each hit.
- **Comms panel:** Portrait, name and typewriter text. Story lines pause and advance on click; combat lines auto-advance. Dialogue is stored as data. The surrender prompts are behind toggle flags.
- **Save:** Unlocked levels and current energy, stored in Godot's `user://` folder.

## Parked and Rejected (with rationale)

- **Missile shatter combo** (parked): a missile shatters a big asteroid and the fragments damage ships. If it's built, fragments should hurt everyone, or the combo should be limited to solo levels. "Enemies only" was rejected as illogical.
- **Playable escape prologue** (rejected): cut for scope and replaced by the opening comms-dialogue sequence.
- **Literal Star Wars-style text crawl** (rejected): back-to-back dialogue reuses the comms system and introduces characters in their own voices.
- **Throne world growing across every level** (rejected): the planet appears in the final level only.
- **Asteroids as weapons** (rejected): asteroids are cover and hazards only.
- **Unity** (rejected): heavier on the dev laptop and a steeper ramp-up; Godot's GDScript matches the developer's Python background.
