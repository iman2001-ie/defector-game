# DEFECTOR v1.0

The first release of DEFECTOR: a neon 2D space shooter with a short story told over comms. You are General Arden Vale, who defected from Sovereign Isolde Varn to the Free Worlds Coalition. Escort a convoy, break a blockade at a heavy cost and bring down Isolde's Flagship. A full playthrough takes about 10–15 minutes.

## What's in it

- **Three levels:** Cargo Ambush (protect a convoy), The Blockade (gunships, snipers and asteroid cover) and Siege of the Throne World, which ends with a three-phase Flagship boss fight.
- **The whole story:** the opening comms, briefings and debriefs, Isolde's taunts, a surrender offer you can accept or refuse, a costly fight at the blockade, a Final Choice against Isolde and a short epilogue.
- **Arcade shooting:** your ship sits on the cursor; a laser, a missile and two energy abilities, Shield and Barrage.
- **Impact that scales with size:** bigger explosions, screen shake and hit-stop for bigger targets.
- **Neon art, sound effects and music** (a track for each level, the boss fight, the menus, the epilogue and a game-over sting), from free CC0 packs, plus portraits, a logo, an icon, the Flagship hull and a few comms sounds made for the game.
- Unlimited retries, Level Select for any unlocked level, and a pause menu.

## Downloads

| File | For |
|---|---|
| `DEFECTOR-v1.0-windows.zip` | Windows 10 or 11, 64-bit |
| `DEFECTOR-v1.0-macos.zip` | macOS 11 or later (Intel) or 13 or later (Apple Silicon); **untested** |

Each zip also holds a `README.txt` with the controls, `CREDITS.txt` and `LICENSE.txt`.

## How to run on Windows

1. Download `DEFECTOR-v1.0-windows.zip` below.
2. Unzip it anywhere and run `DEFECTOR.exe`. There is no installer.
3. The exe isn't code-signed, so Windows SmartScreen may show "Windows protected your PC". Click **More info**, then **Run anyway**.

The game starts in borderless fullscreen; press F11 to switch to a window.

**Requirements:** Windows 10 or 11, 64-bit; graphics with Vulkan or Direct3D 12 support; a mouse and a keyboard.

## How to run on macOS (untested)

The macOS build is exported from the same project but has **not been tested on a real Mac**, so it may not work.

1. Download `DEFECTOR-v1.0-macos.zip` below, unzip it and open `DEFECTOR.app`.
2. The app isn't notarized, so macOS blocks the first launch. Open **System Settings > Privacy & Security** and click **Open Anyway**. On older macOS versions, right-click the app, choose **Open**, then click **Open**.
3. If macOS says the app is "damaged", run `xattr -dr com.apple.quarantine DEFECTOR.app` in Terminal and open it again.

**Requirements:** one universal app for Intel (macOS 11 or later) and Apple Silicon (macOS 13 or later); a mouse with two buttons is recommended, and F11 may need Fn+F11.

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

Only your unlocked levels are saved (energy is not). The save and the logs are in `%APPDATA%\DEFECTOR\` on Windows and in `~/Library/Application Support/DEFECTOR/` on macOS; the log is `logs/godot.log` inside that folder. Delete the `DEFECTOR` folder to start over.

## Credits

The ship, enemy, asteroid and background art, most sound effects and the Kenney Future font are by Kenney. The music and the other sounds are by OpenGameArt authors: Holizna, G_P and tricksntraps (the three level tracks), MintoDog (the boss fight), Fupi (the menus), Centurion_of_war (the epilogue), Kistol (the game-over sting), Joth (the Flagship's final blast and the medium explosions), AntumDeluge and Spring Spring (Tarek's burning fall) and xhunterko (the comms static). All of it is CC0. The portraits, the logo, the app icon, the Flagship hull, the comms cues and the Maul alarm were made for the game. The full list is in `CREDITS.txt` inside each zip and in `game/assets/CREDITS.md` in the repo.

DEFECTOR is made with the Godot Engine (MIT licence). `CREDITS.txt` also carries Godot's licence and the notices of the third-party code built into the engine.

## Licence

DEFECTOR is a personal project: free to play, share and change, but not to sell or use commercially. The code is under the PolyForm Noncommercial License 1.0.0 and the project-owned art and sounds under CC BY-NC 4.0 (`LICENSE.txt` in each zip, `LICENSE` in the repo). The third-party assets keep their own CC0 licence.
