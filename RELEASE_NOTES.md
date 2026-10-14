# DEFECTOR v1.0

The first release of DEFECTOR: a neon 2D space shooter with a short story told over comms. You are General Arden Vale, who defected from Sovereign Isolde Varn to the Free Worlds Coalition. Escort a convoy, lose a mentor and bring down Isolde's Flagship. A full playthrough takes about 10–15 minutes.

## What's in it

- **Three levels:** Cargo Ambush (protect a convoy), The Blockade (tanks, snipers and asteroid cover) and Siege of the Throne World, which ends with a three-phase Flagship boss fight.
- **The whole story:** the opening comms, briefings and debriefs, Isolde's taunts, a surrender offer you can accept or refuse, your mentor's fall, a Final Choice against Isolde and a short epilogue.
- **Arcade shooting:** your ship sits on the cursor; a laser, a missile and two energy abilities, Shield and Barrage.
- **Impact that scales with size:** bigger explosions, screen shake and hit-stop for bigger targets.
- **Neon art, sound effects and two music tracks**, from free CC0 packs plus a few pieces drawn for the game.
- Unlimited retries, Level Select for any unlocked level, and a pause menu.

## How to run

1. Download `DEFECTOR-v1.0-windows.zip` below.
2. Unzip it anywhere and run `DEFECTOR.exe`. There is no installer.
3. The exe isn't code-signed, so Windows SmartScreen may show "Windows protected your PC". Click **More info**, then **Run anyway**.

The game starts in borderless fullscreen; press F11 to switch to a window.

## Requirements

- Windows 10 or 11, 64-bit
- Graphics with Vulkan or Direct3D 12 support
- A mouse and a keyboard

## Controls

| Input | Action |
|---|---|
| Mouse | Fly: your ship sits on the cursor (bottom 60% of the screen) |
| Hold LMB | Laser |
| RMB | Missile, straight up (1.5 s cooldown) |
| E | Shield (costs 50 energy) |
| Q | Barrage: 12 homing micro-missiles (costs 100 energy) |
| LMB on dialogue | Advance the comms and pick a choice |
| Esc | Pause menu |
| F11 | Fullscreen / windowed |

**Play** always starts the story from the beginning. **Level Select** jumps to any level you've unlocked.

## Save and logs

Only your unlocked levels are saved (energy is not), in `%APPDATA%\DEFECTOR\`. To report a bug, open an issue on the Issues tab of the GitHub repository you downloaded the game from, and please attach `%APPDATA%\DEFECTOR\logs\godot.log`. Delete the `DEFECTOR` folder there to start over.

## Credits

Art, sounds and the font are by Kenney; the music is by MintoDog and the comms static by bretbernhoft (OpenGameArt), all CC0. The portraits, the Flagship hull, the icon and a few comms sounds were made for the game. The full list is in `CREDITS.txt` inside the zip and in `game/assets/CREDITS.md` in the repo.

DEFECTOR is made with the Godot Engine (MIT licence). `CREDITS.txt` also carries Godot's licence and the notices of the third-party code built into the engine.
