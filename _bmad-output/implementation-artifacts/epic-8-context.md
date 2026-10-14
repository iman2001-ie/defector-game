# Epic 8 Context: Polish and Release

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Turn the finished, playable campaign into a shippable v1.0: replace the generated placeholder sounds and code-drawn placeholder art with a coherent neon look and real audio, prove the build meets its performance, launch-time and size targets, prove it can be finished three times with every story beat firing, and publish a zipped Windows build on the public GitHub repo so anyone can download, unzip and play. Release and stability checks (8.3–8.5) are MUST. The audio and art passes (8.1, 8.2) are SHOULD and are cut first if time runs out.

## Stories

- Story 8.1: Make the Game Sound Right
- Story 8.2: Make the Game Look Neon
- Story 8.3: Hit the Performance Targets
- Story 8.4: Prove the Game Is Finishable
- Story 8.5: Ship DEFECTOR on GitHub

## Requirements & Constraints

- **Audio:** about 15–20 SFX cues, with explosion volume and pitch scaled by size tier. Distinct cues are needed for player hit, energy pickup, ability denied, comms open and the comms cut-off (static burst, then silence). The radio cues added by later decisions also count: `comms_open_nobeep`, `comms_handover` and `comms_click`. Music is optional: one combat track and one boss track. Music must drop out during Tarek's silence beat. When Level 3 clears, the boss track must not carry on into the end screen or the council epilogue. Either stop it or give the end screen its own track (DW-100). There is no voice acting.
- **Art:** clean neon/vector 2D on dark space. Colour language: Coalition (allies and convoy) cyan/teal, Sovereignty enemies and **all** enemy projectiles magenta/red, energy orbs gold, asteroids desaturated grey-brown with a rim light that are jagged and never round. Required assets: 2 space backgrounds, the throne-world planet arc (Level 3 and the end screen only), portraits for Isolde, Tarek and Ryn (Vale optional), Tarek's damaged ship, the Flagship hull, turrets and core, and HUD elements styled through the shared Theme. The player ship from Story 4.0 stays, and is re-tinted only if the `coalition` colour changes. Wasp, Lancer, Needle, Bastion and Maul need distinct silhouettes. The convoy uses dimmer cargo hulls so it reads as civilian.
- **Assets:** free or CC0 only, Kenney packs first (Space Shooter Redux and Extension, Sci-fi Sounds, the Kenney Future font). Every third-party asset goes in `game/assets/CREDITS.md` with its source and licence.
- **Performance:** a steady 60 FPS (under 16.6 ms per frame) at 1920×1080 on the dev laptop's integrated GPU, in the busiest wave (Level 3 Wave 3) and the Flagship's desperate phase. Cold launch to the title screen in under 5 s. Build under 200 MB.
- **Stability:** 3 full start-to-finish playthroughs on a release build with a fresh save, with no crash or soft-lock. Every beat must fire in each run: the opening, Isolde's interruptions, the surrender prompt (now a SURRENDER / REFUSE choice), Tarek's fall, Ryn's report, the Final Choice and the final line. Check them against the INFO beat lines in `%APPDATA%\DEFECTOR\logs\godot.log`.
- **Playtest (3–5 people, no verbal help):** record whether they understood the controls by Level 1 Wave 2, attempts per level, total playtime (target 10–15 min, 1–3 attempts per level) and answers to "Was the shooting fun on its own?" and "Which story moment do you remember?". Make any resulting retune in data only and log it in the decision log. The ally fire rate (1.0 s) is provisional and should be revisited here against the 10–15% ally kill share.
- **Release:** a 64-bit Windows zip with no installer. `DEFECTOR-v1.0-windows.zip` holds the exe, a `README.txt` with the controls, and the credits. The repo `README.md` covers the premise, controls, download and run steps, and credits. Smoke-test the zip in a clean folder: it launches in under 5 s, creates the save in `%APPDATA%\DEFECTOR\`, and plays through Level 1.
- **Public repo hygiene:** no secrets or machine-specific details anywhere, export presets included (relative paths only). Never commit `game/export/`, `*.zip` or `game/.godot/`. **Get explicit user confirmation before any push, `gh` write or `gh release create`.**
- **Current game rules the README must match:** Play always starts Level 1 through the opening, and Level Select jumps ahead. Energy is never saved. Controls: move with the mouse, hold LMB to fire the laser, RMB fires a missile, E raises the Shield (50 energy), Q fires the Barrage (100 energy), LMB advances comms and picks a choice, Esc pauses, F11 toggles fullscreen.

## Technical Decisions

- **Audio autoload:** `Audio.play_sfx(id, pitch_jitter, volume_db, pitch)` uses an id → preloaded-stream registry. Unknown ids warn once. There are two pools: 12 combat voices and 2 reserved comms voices. The `comms_*` ids route to the comms pool, so combat SFX can never cut off `comms_static`. Explosion SFX come from each `tuning.feedback.tiers` row (`sfx`, `sfx_pitch`, `sfx_volume_db`). Retune loudness there, not in code. Buses: `Master` → `Music`, `SFX`, `UI`. Volumes are fixed (there is no settings menu). There is no positional audio.
- **SFX (Story 8.1 done):** the combat SFX are CC0 Kenney sounds imported by `tools/import_cc0_audio.py`; each of the 20 ids has its own file (the boss tiers are no longer aliases), plus the new `shield_on` and `needle_lock` cues. `tools/gen_placeholder_sfx.py` makes only the five kept cues (`comms_open`, `comms_open_nobeep`, `comms_click`, `comms_handover`, `maul_alarm`). `comms_static` is a recorded CC0 clip, and its 2.5 s length is tied to `comms.cutoff_hide_s`.
- **Music (Story 8.1 done):** `Audio.MUSIC` preloads two CC0 looping tracks, `combat` and `boss` (the only values `LevelValidator` allows, plus `stop`); `Audio.music_streams` starts as a copy and plays at `audio.music_volume_db` (-10 dB). Levels start music through `music` actions on `wave_start`, because the level-root `music` key is never read. The cut-off's `after.music: "stop"` drops the music for Tarek's fall. A missing stream warns and stays silent. `stop_music` fades over `audio.music_fade_out_s`. `Audio.duck_music(on)` is not built, and no Epic 8 acceptance criterion requires it (Story 8.1 left it out). Clearing Level 3 fades the music out before the epilogue or the end screen (DW-100), which run no track.
- **Rendering:** Forward+ with `hdr_2d` and `WorldEnvironment` glow (`render.glow` in tuning). Glow sprites must also use an additive `CanvasItemMaterial`, so switching to the Compatibility renderer stays a one-setting fallback (ADR-003). Anything that shouldn't bloom keeps every colour channel below `render.glow.hdr_threshold` (0.55), with sprite modulate left at white.
- **Backgrounds:** `LevelBackground` on `Level/Background` takes ids `space_1`, `space_2` and `throne_world`. Only the throne world draws today: a code-drawn arc hanging from the **top** edge. Keep a margin wider than the largest screen shake (40 px for boss death) so its edges never show. The end screen reuses it. Level Select card thumbnails and the opening story scene's backdrop (currently the plain `#05070F` clear colour) are still to do.
- **Portraits and placeholders:** comms portraits are a frame with an initial letter. `comms.speakers` sets which speakers have a portrait (Vale and system don't). Allies, Tarek's damaged hull and fire, the convoy, the Flagship parts and the story-only Ram are code-drawn placeholders.
- **Theme and font:** one `defector_theme.tres`, and no per-node style overrides except the comms portrait frame. Adopting Kenney Future changes the text metrics: the interruption box's 33 px line pitch was measured on the fallback font and is pinned by a test, so re-measure it and update `ui.comms_box`.
- **Performance tooling:** `-- --stress` (F1 overlay) and `-- --bench=N` (exit 0 only if avg, p99 and max frame time are all under the `debug.bench` limits). Re-run `--bench=20` after any visual change. `Feedback.prewarm()` avoids the first-use shader hitch. If instancing causes an overrun, add pooling **inside `Spawner` only** (ADR-002). Don't log anything per frame.
- **Export:** the Windows Desktop preset (it already exists from the Epic 1 smoke check) must have the non-resource filter `data/*.json`, without which the JSON is missing from the build. For a CLI export, run the headless `--import` step first, then `--export-release "Windows Desktop"`.
- After adding or changing imported assets, re-run the headless `--import` before tests.

## UX & Interaction Patterns

- Use the palette tokens from the UX spec: `background` #05070F, `coalition` #22E6FF, `enemy` #FF2BD6, `energy` #FFD23F, `hazard` #7A6E62 with `hazardRim` #C9D8E8, `danger` #FF1F4B, `text` #E8F4FF, `muted` #93A7C2. Speaker accents (`isolde` #FF6AE3, `tarek` #3DF2FF, `ryn` #7CFFB2) appear only in the comms UI. In the world, allies are `coalition`.
- Typography: Kenney Future, one weight. Sizes at 1080p: 20 px HUD labels, 28 px body and comms, 30 px names, 48 px headings, 120 px title. Nothing goes below 20 px. Labels, buttons and names are UPPERCASE. Dialogue is sentence case.
- Depth comes from glow, not shadows. The persistent HUD stays in the top 120 px band.

## Cross-Story Dependencies

- 8.1 and 8.2 change audio and visuals, so 8.3's measurements must run after them (re-run the bench after any visual change).
- 8.4's playthroughs and 8.5's smoke test need the final release build, so they come after 8.1–8.3. Any retune from 8.4 lands before 8.5's release.
- 8.5 depends on CREDITS.md being complete from 8.1 and 8.2, and on the Godot 4.7.2 export templates being installed.
- The game is already finishable end to end from Epic 7. This epic changes assets, tuning and packaging, not game flow.
