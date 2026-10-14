DEFECTOR v1.0
=============

A neon 2D space shooter with a short story told over comms.

You are General Arden Vale, who defected from Sovereign Isolde Varn to the
Free Worlds Coalition. Over three short levels you escort a convoy, lose a
mentor and bring down Isolde's Flagship. A full playthrough takes about
10-15 minutes.


REQUIREMENTS
------------

- Windows 10 or 11, 64-bit
- Graphics with Vulkan or Direct3D 12 support
- A mouse and keyboard
- Nothing to install


HOW TO RUN
----------

1. Unzip DEFECTOR-v1.0-windows.zip into any folder.
2. Double-click DEFECTOR.exe. The game starts in borderless fullscreen.

The exe isn't code-signed, so Windows SmartScreen may say "Windows protected
your PC". Click "More info", then "Run anyway".


CONTROLS
--------

  Mouse          Fly. Your ship sits on the cursor (bottom 60% of the screen)
  Hold LMB       Laser
  RMB            Missile, fired straight up (1.5 s cooldown)
  E              Shield (costs 50 energy)
  Q              Barrage: 12 homing micro-missiles (costs 100 energy)
  LMB            Advance comms dialogue and pick a choice
  Esc            Pause menu (Resume, Restart Level, Quit to Title)
  F11            Toggle fullscreen / windowed

Destroyed enemies and asteroids drop gold energy orbs. Fly near them to
collect them. Asteroids block shots from both sides, so use them as cover.


HOW TO PLAY
-----------

- PLAY always starts the story from the beginning: the opening comms, then
  Level 1.
- LEVEL SELECT jumps straight to any level you have unlocked.
- Clearing a level unlocks the next one. If you die, retry the level as many
  times as you like.
- Energy carries into the next level when you clear one, but it is never
  saved: every new start from the title begins with 0 energy.


SAVE AND LOGS
-------------

Your progress (only the unlocked levels) and the game's log files are kept in:

  %APPDATA%\DEFECTOR\

Paste that into the File Explorer address bar to open it. The log is
%APPDATA%\DEFECTOR\logs\godot.log.
Deleting the DEFECTOR folder resets your progress.

To report a bug, open an issue on the Issues tab of the GitHub repository
you downloaded the game from, and please attach godot.log.


CREDITS
-------

DEFECTOR uses free CC0 art, sounds, music and a font by Kenney and by
OpenGameArt authors. Every asset, its source and its licence are listed in
CREDITS.txt next to this file.

Made with the Godot Engine 4.7.2 (godotengine.org), under the MIT licence.
The engine's licence and the notices of the third-party code built into it
are at the end of CREDITS.txt.

Non-commercial hobby project.
