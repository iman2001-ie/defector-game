# DEFECTOR

> "Chicken Invaders meets a CoD campaign."

A neon 2D space shooter where every enemy fleet belongs to the woman you used to serve. You play **General Arden Vale**, who defected from Sovereign Isolde Varn's Sovereignty to the Free Worlds Coalition. Over three short levels you escort a convoy, lose a mentor, and bring down Isolde's Flagship. All of it is told through in-game comms, with no cutscenes.

**Status:** 🛠️ Planning complete, implementation starting. A playable Windows build will be published on the [Releases](../../releases) page when it's ready.

## The game (planned v1.0)

- **Fixed-screen arcade shooting:** your ship chases the mouse; you hold LMB for lasers and press RMB for an aimed missile.
- **Energy abilities:** collect energy from wreckage and spend it on a Shield (E) or a homing Barrage (Q).
- **Size-scaled impact:** explosions, screen shake and hit-stop grow with what you destroy.
- **Story through comms:** paused briefings, rare mid-fight interruptions, and a Final Choice at the end.
- **3 levels:** Cargo Ambush (convoy escort), The Blockade, and Siege of the Throne World (Flagship boss).
- **One sitting:** about 10–15 minutes, Windows 10/11, mouse and keyboard.

### Controls

| Input | Action |
|---|---|
| Mouse | Fly (the ship chases the cursor) |
| Hold LMB | Laser |
| RMB | Missile toward the cursor |
| E / Q | Shield (50 energy) / Barrage (100 energy) |
| LMB on dialogue | Continue |
| Esc | Pause |
| F11 | Fullscreen / windowed |

## Tech

- **Engine:** Godot 4.7.2 with statically typed GDScript
- **Tests:** GUT for logic and data tests
- **Content:** all tuning, waves and dialogue are data-driven JSON
- **Assets:** free and CC0, mainly [Kenney](https://kenney.nl). Credits will be in `game/assets/CREDITS.md`

## How it was planned

This project is also a run-through of the **BMAD Method** (with its game-dev module), done with AI agents. Every planning artifact is in the repo:

| Artifact | Path |
|---|---|
| Brainstorming and game brief | `_bmad-output/brainstorming-session-2026-10-06.md`, `_bmad-output/planning-artifacts/briefs/` |
| Game Design Document | `_bmad-output/planning-artifacts/gdds/` |
| Architecture | `_bmad-output/game-architecture.md` |
| UX spec and HUD mockup | `_bmad-output/planning-artifacts/ux-designs/` |
| Epics and stories | `_bmad-output/planning-artifacts/epics.md` |
| Implementation readiness report | `_bmad-output/planning-artifacts/implementation-readiness-report-2026-10-06.md` |

`_bmad/`, `.agents/` and `.claude/` hold the BMAD tooling and agent skills. `AGENTS.md` holds the rules for AI agents working in this repo.

## Repository layout

```
_bmad-output/    planning documents (GDD, architecture, UX, epics)
game/            Godot project (created in Epic 1)
_bmad/ .agents/ .claude/   BMAD method tooling and agent skills
AGENTS.md        rules for AI agents
```

## Running it (once the game exists)

1. Download `DEFECTOR-v1.0-windows.zip` from Releases, unzip it, and run `DEFECTOR.exe`. Nothing needs installing.
2. Or, from source: open `game/` in Godot 4.7.2 and press F5.

Non-commercial hobby project.
