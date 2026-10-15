DEFECTOR v1.0 for macOS
=======================

A neon 2D space shooter with a short story told over comms.

You are General Arden Vale, who defected from Sovereign Isolde Varn to the
Free Worlds Coalition. Over three short levels you escort a convoy, break a
blockade at a heavy cost and bring down Isolde's Flagship. A full
playthrough takes about 10-15 minutes.


PLEASE NOTE: UNTESTED ON A REAL MAC
-----------------------------------

DEFECTOR was made and tested on Windows. This macOS build is exported from
the same project, but it has not been tried on a real Mac. It may work
perfectly, or it may not start at all.


REQUIREMENTS
------------

- macOS 11 Big Sur or later on an Intel Mac, or macOS 13 Ventura or later
  on an Apple Silicon Mac (one universal app runs on both)
- A mouse with two buttons is recommended (the right button fires missiles)
- A keyboard
- Nothing to install


HOW TO RUN
----------

1. Unzip DEFECTOR-v1.0-macos.zip (double-click it in Finder).
2. Move DEFECTOR.app wherever you like, for example into Applications.
3. Open DEFECTOR.app. The game starts in fullscreen.

The app isn't notarized by Apple, so the first launch needs an override:

- Open the app once. macOS says it can't check it and won't open it.
  Close that message, then open System Settings > Privacy & Security,
  scroll down to the message about DEFECTOR and click "Open Anyway".
  Confirm, and the game starts. You only need to do this once.
- On older macOS versions you can instead right-click (or Control-click)
  DEFECTOR.app, choose Open, then click Open.
- If macOS says the app "is damaged and can't be opened", open Terminal in
  the folder that holds the app and run:

    xattr -dr com.apple.quarantine DEFECTOR.app

  then open the app again.


CONTROLS
--------

  Mouse          Fly. Your ship sits on the cursor (bottom 60% of the screen)
  Hold LMB       Laser (left mouse button)
  RMB            Missile, fired straight up (1.5 s cooldown; right button)
  E              Shield (costs 50 energy)
  Q              Barrage: 12 homing micro-missiles (costs 100 energy)
  LMB            Advance comms dialogue and pick a choice
  Esc            Pause menu (Resume, Restart Level, Quit to Title)
  F11            Toggle fullscreen / windowed (on many Macs: Fn+F11)

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

  ~/Library/Application Support/DEFECTOR/

In Finder, choose Go > Go to Folder and paste that path to open it. The log
is ~/Library/Application Support/DEFECTOR/logs/godot.log.
Deleting the DEFECTOR folder resets your progress.


CREDITS AND LICENCE
-------------------

DEFECTOR uses free CC0 art, sounds, music and a font by Kenney and by
OpenGameArt authors. Every asset, its source and its licence are listed in
CREDITS.txt next to this file.

Made with the Godot Engine 4.7.2 (godotengine.org), under the MIT licence.
The engine's licence and the notices of the third-party code built into it
are at the end of CREDITS.txt.

DEFECTOR is a personal project by iman2001-ie. You may play, share and
change it for free, but not sell it or use it commercially: its code is
under the PolyForm Noncommercial License 1.0.0 and its own art and sounds
under CC BY-NC 4.0. See LICENSE.txt.
