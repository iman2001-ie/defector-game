# Epic 8 Context: Polish and Release

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Turn the finished, playable campaign into a shippable v1.0. That means real CC0 audio and a coherent neon art pass in place of the placeholders, measured proof that the build meets its frame-time, launch-time and size targets, three clean start-to-finish playthroughs with every story beat firing plus a short playtest, and a zipped 64-bit Windows build published as a GitHub release that anyone can download, unzip and play. The audio and art passes (8.1, 8.2) are SHOULD and the first to be cut. Performance, finishability and release (8.3–8.5) are MUST. Stories 8.1–8.3 are built. Their look, sound and hands-on performance checks are provisional until the operator confirms them.

## Stories

- Story 8.1: Make the Game Sound Right
- Story 8.2: Make the Game Look Neon
- Story 8.3: Hit the Performance Targets
- Story 8.4: Prove the Game Is Finishable
- Story 8.5: Ship DEFECTOR on GitHub

## Requirements & Constraints

- **Performance (measured, Story 8.3):** a steady 60 FPS (under 16.6 ms per frame) at 1920×1080 on the dev laptop's integrated GPU, in Level 3 Wave 3 and in the Flagship's DESPERATE phase. Cold launch to the title in under 5 s. Build under 200 MB. All three passed with wide margins: worst p99 about 7.7 ms, launch about 2 s, release exe about 118 MB. No pooling was needed and Forward+ is kept. The operator still owes two checks: hands-on play with the F1 overlay, and a true cold launch after a reboot.
- **Stability (8.4):** three full playthroughs on a release build with a fresh save, with no crash or soft-lock. Every beat must fire in every run: the opening, Isolde's interruptions, the surrender prompt (now a SURRENDER / REFUSE choice), Tarek's fall, Ryn's report, the Final Choice and the final line. Verify them against the INFO `beat` lines in `%APPDATA%\DEFECTOR\logs\godot.log`.
- **Playtest (8.4):** 3–5 people, no verbal help. Record whether they understood the controls by Level 1 Wave 2, attempts per level, total playtime (target 10–15 min, 1–3 attempts per level), and their answers to "Was the shooting fun on its own?" and "Which story moment do you remember?". Make any retune in data only (`tuning.json`) and log it in the decision log. Tests read playtest-tuned values from tuning and check only ranges, so a retune needs no test edits. The ally fire interval (1.0 s) is provisional. Recheck it here against the 10–15% ally kill share, using the `Kills: ... ally M (P%)` line on `dev_ally`.
- **Open questions the playthroughs and playtest should settle:**
  - Does the Level 1 convoy (100 HP) survive real play?
  - Do Level 2's Bastions shield the Needles?
  - Is the throne-world arc actually visible?
  - Does the boss-death sweep cause a one-frame spike?
  - Is the loudness right? The non-tier SFX play at 0 dB, and nothing limits summed clipping.
  - Music still carries over into the title, Level Select and the retry-to-title path. Only the final level clear fades it.
- **Release (8.5):** a 64-bit Windows zip with no installer. `DEFECTOR-v1.0-windows.zip` holds the exe, a `README.txt` with the controls, and the credits. The repo `README.md` covers the premise, the controls, how to download and run, and the credits. Smoke-test the zip in a clean folder: it launches in under 5 s, creates the save in `%APPDATA%\DEFECTOR\`, and plays through Level 1. Publish with `gh release create v1.0 ... --notes-file RELEASE_NOTES.md`, but **only after explicit user confirmation**. The same applies to any push or other `gh` write.
- **The README must match the current game rules:**
  - Play always starts Level 1 through the opening. Level Select jumps ahead.
  - Energy is never saved. Only unlocks persist.
  - Controls: the mouse moves the ship, which sits on the cursor. Hold LMB for the laser, RMB fires a missile, E raises the Shield (50 energy) and Q fires the Barrage (100 energy). LMB advances comms and picks a choice. Esc pauses and F11 toggles fullscreen.
- **Public-repo hygiene:** no secrets, emails or machine-specific paths anywhere, export presets included (relative paths only). Never commit `game/export/`, `*.zip` or `game/.godot/`. Every file under `game/assets/` must be in `game/assets/CREDITS.md` with its source and licence (`CC0 1.0` or `Project-owned`). A data test enforces this.

## Technical Decisions

- **Audio (built):**
  - `Audio.play_sfx(id, ...)` looks ids up in a registry of preloaded streams. There are 20 SFX ids, each with its own file. 14 are from Kenney CC0 packs, the five comms and alarm cues (`comms_open`, `comms_open_nobeep`, `comms_click`, `comms_handover`, `maul_alarm`) are generated, and `comms_static` is a recorded clip, all kept as they are.
  - There are two voice pools: 12 combat and 2 reserved for comms (`comms_*`), so combat sounds can never cut off `comms_static`.
  - Explosion sound per size tier comes from the `tuning.feedback.tiers` rows: pitch falls from small 1.2 to large 0.8, and volume rises with size.
  - Music: two CC0 looping tracks, `combat` and `boss`, at `audio.music_volume_db` -10 dB. They are started by wave `music` actions. The level-root `music` key is never read.
  - The cut-off's `music: stop` silences Tarek's fall. Clearing the last level fades the music before the epilogue or end screen.
  - Music is never ducked, and there is no menu or end-screen track. Retune loudness in `tuning.json`, not in code.
- **Rendering and art (built):**
  - Forward+ with `hdr_2d` and `WorldEnvironment` glow (`render.glow`). Glow sprites also use an additive `CanvasItemMaterial`, so falling back to the Compatibility renderer stays a one-setting change.
  - Anything that must not bloom keeps every colour channel at or below the 0.55 threshold. The backgrounds keep every channel at 127 or below.
  - Kenney sprites are recoloured by `tools/import_cc0_art.py` and sized through `SpriteFit` from the existing size data. The Flagship hull and the three portraits are project-owned SVGs.
  - Projectiles, orbs, explosions, the shield and the HUD stay drawn in code.
  - Re-run the headless `--import` after adding or changing assets.
- **Theme and font (built):** there is one shared `defector_theme.tres`, with Kenney Future as its default font. Dialogue text keeps the engine font through base-less FontVariations, because Kenney Future breaks the 4-line story panel. No per-node overrides are allowed beyond the comms portrait frame.
- **Performance tooling:**
  - `-- --bench=N` runs the sandbox bench. `-- --level-bench=busiest_wave|desperate` runs on a debug export through `DEFECTOR.console.exe`. Both pass only if avg, p99 and max frame time are all under the `debug.bench` limits.
  - `tools/perf_check.py size|launch` takes its limits from `debug.release_check`. Release builds buffer the file log, so `launch` reads stdout.
  - Re-run the benches after any visual change. If instancing ever causes an overrun, add pooling inside `Spawner` only. Don't log anything per frame.
- **Export:**
  - The Windows Desktop preset is committed, with an embedded PCK, product name "DEFECTOR", the non-resource filter `data/*.json` (without it the JSON is missing from the build) and the exclude filter `addons/gut/*, tests/*`.
  - The application icon is still unset and Story 8.5 must add one. `RELEASE_NOTES.md` does not exist yet.
  - For a CLI export, run the headless `--import` first, then `--export-release "Windows Desktop" export/windows/DEFECTOR.exe`. Godot 4.7.2 export templates must be installed.

## UX & Interaction Patterns

- **Palette tokens:** `background` #05070F, `coalition` #22E6FF (allies, convoy, player), `enemy` #FF2BD6 (all Sovereignty ships and **all** enemy shots), `energy` #FFD23F, `hazard` #7A6E62 with `hazardRim` #C9D8E8, `danger` #FF1F4B, `text` #E8F4FF, `muted` #93A7C2. The speaker accents (Isolde, Tarek, Ryn) appear only in the comms UI.
- **Typography:** sizes at 1080p are 20 px HUD labels, 28 px body and comms, 30 px names, 48 px headings and a 120 px title. Nothing goes below 20 px. Labels, buttons and names are UPPERCASE. Dialogue is sentence case.
- **Depth and layout:** depth comes from glow, not shadows. The persistent HUD stays in the top 120 px band. The throne-world arc hangs from the top edge, on Level 3 and the end screen only.

## Cross-Story Dependencies

- 8.4's playthroughs and 8.5's smoke test need the final release build, so they follow 8.1–8.3. Any retune from 8.4 is data-only and lands before 8.5's release. Re-run the benches if a retune or fix changes visuals or entity counts.
- 8.5 depends on a complete CREDITS.md from 8.1 and 8.2, the installed 4.7.2 export templates, and the operator's sign-off on the provisional audio, art and performance checks.
- The campaign is already finishable end to end from Epic 7. This epic changes assets, tuning and packaging, not game flow. Fixes for the open questions above (such as music carrying over into the menus) should stay small and data-driven.
