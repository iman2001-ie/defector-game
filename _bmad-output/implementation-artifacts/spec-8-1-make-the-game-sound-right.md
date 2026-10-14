---
title: 'Story 8.1: Make the Game Sound Right'
type: 'feature'
created: '2026-10-13'
status: done
operator_actions:
  - 'Play Level 1 in a debug build ("<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game) and listen to every new combat sound: laser, missile launch, Barrage, the small, medium and large explosions, player hit and death, energy pickup, ability denied (E or Q with too little energy) and the new Shield-on cue (E). Say whether each one fits and whether the explosions sound bigger as they get bigger (pitch 1.2 / 1.0 / 0.8).'
  - 'Listen to the combat track (MintoDog "Space Adventure") in Level 1 at the -10 dB music volume: judge its balance against the sound effects and the comms lines, and whether its loop point is seamless after about 2 minutes 10 seconds.'
  - 'Play Level 3 from Level Select through the Needles (judge the new Needle lock cue against the red lock line) and the Flagship: confirm the boss track (MintoDog "Space Boss Battle") replaces the combat track when the boss wave starts, loops cleanly, and that the boss-part and boss-death explosions sound right with no harsh clipping in the death chain.'
  - 'After the Flagship dies and Isolde''s final line is clicked through, confirm the music fades out and the council epilogue and the end screen play in silence (DW-100).'
  - 'Play Level 2 to Tarek''s fall and confirm the combat music drops out at the cut-off and stays silent through his silence beat.'
  - 'Approve or replace any pick, and the -10 dB music volume and the small-explosion pitch 1.2 (GDD decision #65, provisional); record any change in the decision log, with retunes in tuning.json.'
baseline_revision: '5a8a710c4f8044f24d9e2fb4f110897cd519127c'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
warnings: ['oversized']
deferred:
  - summary: >-
      Music still carries over when the player quits to the title, opens Level Select or goes from the retry prompt to the title, so the combat or boss track now plays on the menus.
    evidence: |-
      No scene change stops music (SceneRouter._change_to never touches Audio; only a `music: stop` action, the cut-off and, since Story 8.1, the last level clear do). Before Story 8.1 no track shipped, so this was silent; now Audio.MUSIC plays real tracks. DW-100 named this carry-over as the general case ("e.g. a level to the title"); Story 8.1's AC fixed only the Level 3 to end-screen route. Whether the title and menus should be silent is a design call (the GDD ships 0-2 tracks: combat and boss).
    location: >-
      game/autoloads/scene_router.gd (goto_title, goto_level_select)
    severity: medium
  - summary: >-
      The non-tier sound effects (laser_zap, missile_launch, barrage_whoosh, energy_pickup, shield_on, needle_lock, ability_denied, maul_alarm) play at a code-default 0 dB, so their loudness can only be retuned by code or by re-rendering the WAV, not in tuning.json.
    evidence: |-
      Only feedback.tiers rows carry sfx_volume_db and sfx_pitch; every other call is Audio.play_sfx(id) with the default volume (player_weapons.gd, player.gd, energy_orb.gd, maul.gd, needle.gd). The pattern predates Story 8.1, which follows it for the two new cues; the operator listening pass may want per-cue levels.
    location: >-
      game/entities/player/player_weapons.gd / game/entities/player/player.gd / game/entities/pickups/energy_orb.gd / game/entities/enemies/needle/needle.gd
    severity: medium
  - summary: >-
      Nothing limits the summed SFX level, so many peak-normalised (-1 dBFS) sounds at once, such as the boss-death sweep, may clip.
    evidence: |-
      Unverified. Every new WAV peaks at -1 dBFS and the large, boss and player tiers play at 0 dB; default_bus_layout.tres has no effects on Master, SFX or Music. Settle it by listening to the Flagship's death chain with many Wasps on screen, or by capturing the Master bus peak in play.
    location: >-
      game/default_bus_layout.tres
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** Most combat SFX are generated placeholders (boss tiers alias the large explosion), Shield-on and Needle-lock have no cue, no music ships (`Audio.music_streams` is empty), and once tracks exist the boss track would carry on into the council epilogue and end screen (DW-100).

**Approach:** Replace the combat placeholders with CC0 Kenney sounds (OpenGameArt mirrors; kenney.nl is unreachable here) through a reproducible import tool, add `shield_on` and `needle_lock`, ship two CC0 looping tracks (`combat`, `boss`) in a preloaded `Audio.MUSIC` registry, and fade the music out when the last campaign level clears, before the epilogue or end screen. Credit every file.

## Boundaries & Constraints

**Always:**
- Sources are CC0 only; every audio file under `game/assets/audio/` has a `game/assets/CREDITS.md` row (source, licence, processing).
- SFX are `sfx_<id>.wav`, 16-bit mono 44.1 kHz, peak-normalised to -1 dBFS; music is `music_<id>.ogg`, copied byte-for-byte, imported with `loop=true`.
- Volume/pitch tuning lives in `tuning.json` (`feedback.tiers`, `audio`), read through `Config`. Registry ids stay `StringName` constants in `audio.gd`.
- Keep the comms cues (`comms_open`, `comms_open_nobeep`, `comms_click`, `comms_handover`, `comms_static`) and `maul_alarm` byte-identical: they were tuned in operator checks (decisions #40–#43) and Kenney has no alarm.
- Statically typed GDScript; failing GUT test first; logging via `Log`.

**Never:**
- No title/menu/end-screen track, no `duck_music`, no settings menu, no positional audio, no change to the quit-to-title carry-over.
- Don't read the level-root `music` key (DW-97 stays open). Don't change `LevelValidator.MUSIC_ACTIONS`.
- Don't commit downloaded zips, unused pack files or any machine path.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Level 3 clears | `combat` or `boss` playing; `SceneRouter.complete_level(level_count)` | `Audio.current_music()` is `&""` at once and the track fades over `audio.music_fade_out_s`, whether the epilogue flag is on, off, or `Config.load_error` is set | No error expected |
| Earlier level clears | `complete_level(1)` with `combat` playing | Music untouched (`current_music()` stays `combat`) | No error expected |
| Last level clears in silence | nothing playing | No error, `current_music()` stays `&""` | No error expected |
| Shield raised | enough energy, shield down | `shield_on` plays once | Denied raise plays only `ability_denied`; a raise while active plays nothing |
| Needle locks | TRACKING → LOCKED | `needle_lock` plays once per lock | No error expected |
| Music actions | `music: combat` / `boss` from wave data | The registered looping stream plays on the Music bus at `audio.music_volume_db` | Unregistered id keeps the existing warn-once silence |

</intent-contract>

## Code Map

- `game/autoloads/audio.gd` -- `SFX` registry (:24-48; boss tiers alias large at :31-36), `music_streams` var (:76, empty), `_ready` (:82, `_music_base_db = _music.volume_db` at :106), `play_music`/`stop_music` (:184-226). Config loads before Audio (project.godot autoloads).
- `game/autoloads/scene_router.gd:269-281` -- `complete_level`; last-level branches go to `goto_story(ENDING_SEQUENCE, ...)` or `goto_end()`.
- `game/entities/player/player.gd:393-399` -- `try_shield`; cue goes after `_shield.raise()` (Shield component must not touch Audio, architecture :1638).
- `game/entities/enemies/needle/needle.gd:158-173` -- `_enter_state`; LOCKED entry is the lock moment.
- `game/data/tuning.json:287-316` (`feedback.tiers`), `:352-354` (`audio`).
- `tools/gen_placeholder_sfx.py:342-368` -- `sounds` dict; still writes every placeholder, so it would overwrite the new WAVs.
- Tests: `game/tests/unit/test_audio.gd` (registry :98-101, alias asserts :105-117, `music_streams.size()==0` :254-262, `after_each` clears `music_streams` :39-41), `test_wave_director.gd:63-65` (also clears it), `test_feedback.gd:122-130` (pins large pitch 0.8 and volumes), `test_data_files.gd:1105-1132,1414-1426`, `test_player_shield.gd`, `test_needle.gd`, `test_scene_router.gd`; level tests (`test_level_1/2/3.gd`, `test_level.gd:1758+`) swap streams under `combat`/`boss` and restore them.
- Docs: `game-architecture.md:340` (music registry "empty until 8.1"), decision log (next row #65), `deferred-work.md` DW-100 (:959).

## Tasks & Acceptance

**Execution:**
- `tools/import_cc0_audio.py` (new, stdlib + `ffmpeg`/`ffprobe` subprocess) -- `--packs DIR` (unzipped packs, files found by name with `rglob`) writes the SFX below into `game/assets/audio/sfx/` (trim, 5 ms fade-in where trimmed, fade-out, mono 44.1 kHz s16, two-pass peak normalise to -1 dBFS) and copies the two music OGGs to `game/assets/audio/music/`; docstring lists page URLs and source SHA-256 -- reproducible provenance. Plus `tools/test_import_cc0_audio.py` (unittest) for the mapping table and ffmpeg arg building (no ffmpeg needed).
- Run it: curl the zips/OGGs below into a fresh system-temp folder, unzip each into its own empty folder, run the tool, then the headless `--import`; set `loop=true` in both music `.import` sidecars and re-import.
- `tools/gen_placeholder_sfx.py` -- generate only `comms_open`, `comms_open_nobeep`, `comms_click`, `comms_handover`, `maul_alarm`; re-running must leave those five byte-identical (verify with `git diff --stat`).
- `game/autoloads/audio.gd` -- register `shield_on`, `needle_lock`, own files for both boss tiers; add `const MUSIC` (`combat`, `boss` preloads); `music_streams` starts as a copy of `MUSIC`; base music volume = `audio.music_volume_db`; update header comments.
- `game/data/tuning.json` -- `audio.music_volume_db: -10.0`; `feedback.tiers.small.sfx_pitch` 1.0 → 1.2 so pitch falls small 1.2 > medium 1.0 > large 0.8 (volumes unchanged).
- `player.gd` / `needle.gd` -- play `shield_on` / `needle_lock` (defaults) per the matrix.
- `scene_router.gd` -- `complete_level` of the last campaign level calls `Audio.stop_music()` before either branch; doc comment.
- Tests -- update the pins above (restore `Audio.MUSIC` instead of clearing; boss tiers distinct from large; music registered, `AudioStreamOggVorbis.loop` true, played on Music bus at `audio.music_volume_db`; small pitch); add matrix-row tests; add a data test that every `.wav`/`.ogg` under `res://assets/audio/` is named in `res://assets/CREDITS.md` and every `feedback.tiers` sfx and every non-`stop` `MUSIC_ACTIONS` id is registered.
- `game/assets/CREDITS.md` -- third-party rows for each new file; generated table keeps only the five kept cues; drop the "until the Kenney packs" wording.
- Docs -- decision log row #65 (mapping, tracks, -10 dB, small pitch, stop on last clear, kept cues; feel provisional for operator); `game-architecture.md:340` registry text; `epic-8-context.md` placeholder/music bullets; DW-100 `status: done 2026-10-13` + resolution (Story 8.1).

| id | source (pack → file) | processing |
|---|---|---|
| laser_zap | Sci-Fi → laserSmall_001.ogg | none |
| missile_launch | Sci-Fi → thrusterFire_003.ogg | first 0.55 s, 0.3 s fade-out |
| barrage_whoosh | Sci-Fi → thrusterFire_001.ogg | first 0.30 s, 0.2 s fade-out |
| explosion_small / medium / large | Sci-Fi → explosionCrunch_000 / 001 / 004.ogg | none |
| explosion_boss_part / boss_death | Sci-Fi → lowFrequency_explosion_001 / 000.ogg | none |
| player_hit / player_death | Sci-Fi → impactMetal_002 / explosionCrunch_003.ogg | none |
| shield_on | Sci-Fi → forceField_000.ogg | none |
| energy_pickup / needle_lock | Digital SFX → powerUp5.mp3 / highUp.mp3 | none |
| ability_denied | Interface → error_007.ogg | none |
| music combat | MintoDog "Space Adventure" `space_adventure_bpm140_0.ogg` | copy |
| music boss | MintoDog "Space Boss Battle" `space_boss_battle_bpm175_0.ogg` | copy |

Sources (all CC0 on their OpenGameArt page, `https://opengameart.org` + page; files at `https://opengameart.org/sites/default/files/<file>`), SHA-256 to record in the tool docstring:
- `sci-fi_sounds.zip` (Kenney, /content/sci-fi-sounds) `119340f351a5098ad814f78719438c0da355a9ce8a4c8a3af6a8d48aa3d49e04`
- `Digital_SFX_Set.zip` (Kenney, /content/63-digital-sound-effects-lasers-phasers-space-etc) `022f0f4b73da55989567fe2b373c8af89d74f5d015257e293cab497ca606d063`
- `kenney_interfaceSounds.zip` (Kenney, /content/interface-sounds) `f2193d072726d6758a5f7871b2dcc54dcce0d5c35c6f0a62f92549b327c81232`
- `space_adventure_bpm140_0.ogg` (MintoDog, /content/space-adventure) `30e31ee6da7a24bea35bf22d6c125f8100f803fca20a3f59637e52a4fd764ce3`
- `space_boss_battle_bpm175_0.ogg` (MintoDog, /content/space-boss-battle) `4fc0898456099db3d9e63bd97450fedc3f9ff0a05cd65a8d363b3f2904415e60`

**Acceptance Criteria:**
- Given the sound pass, when `Audio.SFX` is read, then it holds 20 ids, each with its own file (no aliases), every one a third-party CC0 file except the five kept generated cues, and `explosion_boss_part`/`explosion_boss_death` no longer share the large stream.
- Given an explosion of each tier, when `Feedback` plays it, then the tier row's `sfx`, `sfx_pitch` and `sfx_volume_db` come from `tuning.feedback` (data only).
- Given Level 2 Wave 5's cut-off and Level 3's boss wave, when they run, then music stops for Tarek's silence beat and `boss` replaces `combat`, with the shipped streams (existing level tests stay green).
- Given every file under `game/assets/audio/`, when CREDITS.md is checked, then its row exists (enforced by the data test).

## Spec Change Log

## Review Triage Log

### 2026-10-13 — Review pass
- verdicts: 37 findings — high 4, medium 2, low 24, false 5, maybe-false 2
- findings:
  - `[high]` `[patch]` (blind) `tools/__pycache__/*.pyc` untracked and not ignored, would be committed — added `__pycache__/` to `.gitignore`, deleted the folder; `git status --ignored` shows none left.
  - `[medium]` `[defer]` (blind) Music still carries over on quit-to-title, Level Select and retry-to-title, now audible with real tracks — the carry-over (no scene change stops music) predates this story and DW-100 recorded it as the general case; the story's AC covers only the Level 3 → end-screen route. Deferred.
  - `[medium]` `[defer]` (blind) Non-tier cues (laser, missile, barrage, pickup, shield_on, needle_lock, denied, maul_alarm) play at a code-default 0 dB, so a retune needs code — pre-existing `play_sfx(id)` pattern from Stories 1.3–6.2; the new cues follow it. Deferred.
  - `[maybe-false]` `[defer]` (blind) No bus limiter; many -1 dBFS SFX at once (boss-death sweep) may clip — needs a listening or summed-level check in play; buses had no effects before either. Deferred as medium (unverified).
  - `[maybe-false]` `[reject]` (blind) Boss tiers at pitch 1.0 "break" the pitch ladder — the ladder (decision #65, GDD) covers the three size tiers; the boss tiers use their own low-frequency recordings, so whether they sound higher than `large` needs a listen; if true only low.
  - `[low]` `[reject]` (blind) Needles locking on the same frame stack `needle_lock` — at most 2 Needles per wave, so 2 of 12 voices and a louder cue for two simultaneous threats; a dedupe adds new logic.
  - `[low]` `[reject]` (blind) Level tests swap silent WAVs instead of the shipped tracks — the id → shipped stream path is covered by `test_music_actions_play_the_shipped_tracks` and the data test that every music action is registered; decoding full tracks in level suites adds cost for no new coverage.
  - `[low]` `[reject]` (blind) Import tool ignores `SfxSource.pack` and does not hash-check the SFX zips — a one-shot tool whose name lookup already fails loudly on a missing or ambiguous file; zip hashing adds parameters.
  - `[low]` `[patch]` (blind) Docstring says `ffprobe` is required but it is never used — docstring now names only `ffmpeg`.
  - `[low]` `[patch]` (blind) `import_sfx` / `import_music` / `main` untested — grouped with the verification-gap finding below; tests added.
  - `[low]` `[reject]` (blind) MP3 lead-in silence on `energy_pickup` / `needle_lock` — measured: `needle_lock` starts at once, `energy_pickup` has about 45 ms below -50 dB, under a noticeable lag for a pickup chime; a trim option means a re-import.
  - `[low]` `[patch]` (blind) Needle cue test: passes not isolated, null Needle returns silently — the no-spawner pass now runs first and a null Needle fails the test.
  - `[low]` `[patch]` (blind) Credits test checks only the path, not the licence (the file-count coupling to the registry is intended: every audio file must be registered) — rows must now also name `CC0 1.0` or `Project-owned`.
  - `[low]` `[patch]` (blind) `duck_music` still "Planned (Epic 8)" though no Epic 8 story builds it — architecture and epic context now say it is not built and no Epic 8 AC requires it.
  - `[low]` `[reject]` (blind) `epic-8-context.md` hand-edited though generated — its sources (architecture, decision #65) carry the same facts, and the newer decision log makes the cache stale, so the next regeneration reproduces them.
  - `[high]` `[patch]` (edge) `tools/__pycache__` would publish a local path — same root cause as the first row; same fix.
  - `[low]` `[reject]` (edge) `needle_lock` plays when the Needle can't fire (held fire, no spawner) — the red lock line also shows in those states, so the cue matches the visual telegraph; a guard adds a branch for a harmless case.
  - `[low]` `[reject]` (edge) Same-frame Needle locks stack — same as the blind row above.
  - `[false]` `[reject]` (edge) Audio becomes the first autoload to read tuning at boot — with a broken `tuning.json`, `Feedback._ready` → `load_tiers()` already reads `Config.num` unguarded at boot, so nothing new can fail.
  - `[low]` `[patch]` (edge) Music volume cached in `_ready`, so an F5 reload is ignored — `play_music` re-reads `audio.music_volume_db`; new test `test_retuned_music_volume_applies_on_the_next_play`.
  - `[false]` `[reject]` (edge) `shield_on` plays when `duration_s <= 0` leaves the shield down — shipped tuning has a positive duration, and the energy spend in that case predates this story.
  - `[low]` `[reject]` (edge) `filter_chain` accepts a trim with no fade, or a fade longer than the trim — the fixed mapping table is pinned by `test_fade_out_only_with_a_trim_and_shorter_than_it`; validation adds code to a one-shot tool.
  - `[low]` `[reject]` (edge) SFX zip hashes never checked — same as the blind row above.
  - `[low]` `[reject]` (edge) A mid-run failure leaves a mixed asset set — one-shot tool; `git` restores the committed files, and staging adds complexity.
  - `[low]` `[reject]` (edge) `python -OO` makes `__doc__` None — nobody runs this tool optimised; not a direct correction worth adding.
  - `[low]` `[patch]` (edge) Credits test only collects .wav/.ogg — it now collects every file under `res://assets/audio/` except `.import`/`.uid` sidecars.
  - `[false]` `[reject]` (edge) Level-running suites leak the real tracks across suites — the GUT log shows every "Music … playing" line comes from suites that stop music in `after_each` (test_audio, comms_channel, level, level_1/2/3, scene_router, wave_director); the flagged suites run dev levels with no music action or stub the scene change.
  - `[low]` `[patch]` (edge) Needle test `return` skips silently — same as the blind row; same fix.
  - `[false]` `[reject]` (edge) The config-error fade claim fails on a real broken tuning — a real tuning load error already asserts at boot in Feedback (row above); the matrix row is about `Config.load_error` being set with tuning available, which is what the test does.
  - `[low]` `[patch]` (verification-gap) `gen_placeholder_sfx.py` output set only checked by hand — new `tools/test_gen_placeholder_sfx.py` runs `main()` into a temp folder and checks exactly the five names, byte-identical to the committed files.
  - `[low]` `[patch]` (verification-gap) Importer file writes and SHA check never run — added tests: a wrong hash raises and writes nothing, the right bytes give a byte-identical copy, `main` returns 2 for a bad `--packs`.
  - `[high]` `[patch]` (verification-gap) `tools/__pycache__` with the local user name — same root cause as the first row; same fix.
  - `[low]` `[reject]` (intent) The listening pass is owed but not enumerated as `operator_actions` — the fix is this spec's frontmatter; the finalization records it as `operator_actions` with status `awaiting-operator`, as Stories 7.2–7.8 did.
  - `[low]` `[reject]` (intent) Level runs never use the shipped streams — same as the blind row above.
  - `[low]` `[reject]` (intent) The 0.5 s fade tail can overlap the start of the next screen — with the shipped `council_epilogue` flag on, the end screen opens long after the fade ends; only the designer flag-off route shows a 0.5 s fading tail, which DW-100 names as an allowed "fade".
  - `[false]` `[reject]` (intent) Keeping the generated comms cues and `maul_alarm` conflicts with the AC's sourcing — the AC allows "free CC0 or free-licence sources"; these are project-owned and were approved by the operator (#40–#43), so nothing in the design changed.
  - `[high]` `[patch]` (intent) `tools/__pycache__` in the change — same root cause as the first row; same fix.

## Design Notes

Stopping on the last clear (not adding an end track) follows the GDD's "0–2 tracks" and covers both routes out of Level 3, so the boss track never reaches the epilogue or end screen; it still plays under Isolde's final line (the outro runs before `level_cleared`). -10 dB because the tracks' mean (≈ -13 dB) sits above the SFX mean (≈ -15 dB). Nobody has listened to any pick: loudness, loop seams and fit are owed to the operator.

## Verification

**Commands:**
- `uv run python -m unittest tools/test_import_cc0_audio.py tools/test_recolor_player_ship.py` -- expected: OK
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0, no import errors
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, no new orphans
- `git status --porcelain` -- expected: no zips, no pack folders, no unused audio, no `game/.godot/`

## Auto Run Result

Status: awaiting-operator

**Summary.** The sound pass is in. The combat placeholder SFX are replaced with CC0 Kenney sounds (Sci-Fi Sounds, 63 Digital sound effects and Interface Sounds, taken from the OpenGameArt mirrors because kenney.nl is blocked on this network). A reproducible importer, `tools/import_cc0_audio.py`, builds them. Two new cues are wired in: `shield_on`, when the Shield goes up, and `needle_lock`, when a Needle's line locks. The boss tiers now have their own explosions. Two CC0 looping MintoDog tracks (`combat`, `boss`) ship in a preloaded `Audio.MUSIC` registry at `audio.music_volume_db` (-10 dB). The small explosion's pitch goes to 1.2, so pitch falls with size. Clearing the last campaign level now fades the music out before the council epilogue or the end screen (DW-100, closed). The operator-tuned comms cues, `maul_alarm` and `comms_static` are unchanged byte for byte. Every audio file is credited, and a data test enforces it.

**Files changed**
- `game/assets/audio/sfx/*.wav` (+ `.import`): 10 replaced and 4 new CC0 SFX, mono 44.1 kHz, peak -1 dBFS.
- `game/assets/audio/music/music_combat.ogg`, `music_boss.ogg` (+ `.import`, `loop=true`): the two CC0 tracks.
- `game/autoloads/audio.gd`: 20 SFX ids, each with its own file. Adds the `MUSIC` registry; `music_streams` starts as a copy of it. The music volume comes from tuning and is re-read on every play.
- `game/autoloads/scene_router.gd`: `complete_level` of the last level calls `Audio.stop_music()` before the epilogue or the end screen.
- `game/entities/player/player.gd`, `game/entities/enemies/needle/needle.gd`: the `shield_on` and `needle_lock` cues.
- `game/data/tuning.json`: `audio.music_volume_db` -10.0; `feedback.tiers.small.sfx_pitch` 1.2.
- `game/assets/CREDITS.md`: a CC0 row for every new file; the generated-sounds table keeps only the five kept cues.
- `tools/import_cc0_audio.py` (new) and its tests; `tools/gen_placeholder_sfx.py` now writes only the five kept cues; new `tools/test_gen_placeholder_sfx.py`.
- Tests: `test_audio`, `test_feedback`, `test_scene_router`, `test_player_shield`, `test_needle`, `test_wave_director`, `test_comms_channel`, `test_level_1/2/3` (comments) and `test_data_files` (credits and registry checks).
- `.gitignore`: ignores `__pycache__/`.
- Docs: decision log #65, the architecture's Audio section plus "As-built 2026-10-13 (Story 8.1)", `epic-8-context.md`, and DW-100 marked done.

**Review findings.** 37 findings: high 4, medium 2, low 24, false 5, maybe-false 2.
- **Patched (9 entries; by entry verdict, 1 high and 8 low):**
  - Python bytecode with a local path was about to be committed. Fixed by the `.gitignore` rule and deleting the folder.
  - The importer's docstring no longer mentions `ffprobe`.
  - The Needle cue test now isolates its two passes and fails on a null Needle.
  - The credits test now requires a licence in each row.
  - The credits test now collects every audio file, not only `.wav` and `.ogg`.
  - The music volume is re-read on every play, so an F5 reload applies.
  - The `duck_music` docs now say it is not built.
  - New test that the generator writes exactly the five kept cues, byte-identical.
  - New tests for the importer's SHA check, its file writes and its exit codes.
- **Deferred (3):**
  - Music carries over to the title and Level Select (medium).
  - Non-tier SFX volumes are not in tuning (medium).
  - Possible clipping with no bus limiter (medium, unverified).
- **Rejected** (each with its reason in the Review Triage Log):
  - boss tiers versus the pitch ladder (maybe-false, low if true)
  - stacked `needle_lock` cues
  - level tests use silent tracks instead of the shipped streams (×2)
  - SFX zip hashes unchecked and the `pack` field unused (×2)
  - MP3 lead-in (about 45 ms on `energy_pickup`)
  - hand-edited epic context
  - lock cue while fire is held
  - Audio reads Config at boot (false)
  - shield duration of 0 or less (false)
  - `filter_chain` validation
  - partial import on failure
  - `python -OO`
  - test music leaks across suites (false)
  - config-error fade claim (false)
  - listening pass not in `operator_actions` (recorded by this finalization)
  - fade tail on the flag-off route
  - kept cues versus the sourcing AC (false)

**Follow-up review recommendation: false.** The one high (the bytecode) is fixed and checked with `git status --ignored`. No unverified risk remains from the patched entries.

**Verification**
- `uv run python -m unittest tools/test_import_cc0_audio.py tools/test_recolor_player_ship.py tools/test_gen_placeholder_sfx.py`: 31 tests, OK.
- Headless `--import`: exit 0.
- Full GUT run: 97 scripts, 2000/2000 passing, no orphans.
- Every row of the I/O matrix is covered by a test that ran and passed.
- Re-running `tools/gen_placeholder_sfx.py` left the five kept cues byte-identical.
- `git status`: no zips, no pack folders, no `__pycache__`.

**Residual risks.** Nobody has listened to any pick. Loudness, mix balance, loop seams, possible clipping in dense moments and whether each cue fits are owed to the operator (see `operator_actions`). The music tracks add about 7.5 MB to the repo and the build.

## Operator Confirmation

Confirmed 2026-10-14: the external actions this story owed were carried out.

- Play Level 1 in a debug build ("<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game) and listen to every new combat sound: laser, missile launch, Barrage, the small, medium and large explosions, player hit and death, energy pickup, ability denied (E or Q with too little energy) and the new Shield-on cue (E). Say whether each one fits and whether the explosions sound bigger as they get bigger (pitch 1.2 / 1.0 / 0.8).
- Listen to the combat track (MintoDog "Space Adventure") in Level 1 at the -10 dB music volume: judge its balance against the sound effects and the comms lines, and whether its loop point is seamless after about 2 minutes 10 seconds.
- Play Level 3 from Level Select through the Needles (judge the new Needle lock cue against the red lock line) and the Flagship: confirm the boss track (MintoDog "Space Boss Battle") replaces the combat track when the boss wave starts, loops cleanly, and that the boss-part and boss-death explosions sound right with no harsh clipping in the death chain.
- After the Flagship dies and Isolde's final line is clicked through, confirm the music fades out and the council epilogue and the end screen play in silence (DW-100).
- Play Level 2 to Tarek's fall and confirm the combat music drops out at the cut-off and stays silent through his silence beat.
- Approve or replace any pick, and the -10 dB music volume and the small-explosion pitch 1.2 (GDD decision #65, provisional); record any change in the decision log, with retunes in tuning.json.

_Appended by the bmad-loop orchestrator (`bmad-loop confirm`, #335): a human confirmed these external actions out of band, and the story was advanced from `awaiting-operator` to `done`._
