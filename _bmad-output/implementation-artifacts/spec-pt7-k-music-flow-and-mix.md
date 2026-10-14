---
title: 'Epic 7 playtest K: smooth music transitions, louder music, menu music, the epilogue and convoy picks, softer static'
type: 'feature'
created: '2026-10-14'
status: 'done'
baseline_commit: '5ead4fa'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:**
- Music cuts abruptly everywhere.
- The Level 1 and Level 2 tracks carry into the next level's briefing.
- The in-game music is drowned out by the effects.
- The title and menus are silent.
- The convoy blasts sound bad.
- The comms static is harsh.

**Approach.** The operator's picks, 2026-10-14:
- **Transitions:**
  - Every stop fades out over about 2 s (`audio.music_fade_out_s`).
  - Every start fades in (`audio.music_fade_in_s`).
  - Switching from one track to another crossfades over `audio.music_crossfade_s`, using two music players.
- **Level changes:** clearing Level 1 or Level 2 fades the music out at the level transition, so the next briefing starts in silence. The next level's own track starts at its wave-1 trigger, as now.
- **Mix:**
  - The base music volume rises by about 3 dB.
  - The tracks that play without combat effects (`epilogue`, `game_over` and the new `menu`) get their gains lowered by the same amount, so their absolute level is unchanged.
- **Menu music:** Fupi's "Synthwave House Loop" (CC0, loops) as `menu`. It plays on the title and Level Select, keeps playing between them, and fades out when the game starts: the opening story, or a level from Level Select.
- **Epilogue:** Centurion_of_war's "Space Echo" (CC0) replaces Heavenly Loop. It still carries on into the end screen.
- **Convoy chain:** uses Spring Spring's `dull_explosion.wav` (CC0) as a new `explosion_dull`. The boss chain keeps `explosion_mid`.
- **Static:** `comms_static` is re-cut softer from the same recording, with a high-pass at 250 Hz, a low-pass at 2.8 kHz and about 5 dB less level. This is provisional; the operator may pick another option from the audition folder.

## Boundaries & Constraints

**Always:**
- Every number lives in `tuning.json`.
- Assets are reproducible and credited.
- Only Audio plays music.
- Fades ignore time_scale.
- The operator's unstaged edits are never staged.

**Ask First:** none.

**Never:**
- Change gameplay.
- Put music under the story briefing, unless a level's own trigger does so (none does).
- Let the menu track bleed into gameplay.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior |
|---|---|---|
| Level 1 or 2 cleared | `complete_level(n < count)` | the music fades out over `music_fade_out_s` across the scene change |
| Wave 1 starts | its `level_N` trigger | fade in |
| Boss trigger | `boss` while `level_3` plays | crossfade |
| Title, then Level Select, then title | `menu` already playing | it keeps playing, with no restart |
| Start a level from the menu | | `menu` fades out |
| Loss | as now (fade, then the sting) | the fade is longer, the sting fades in |
| Retry | the sting is playing | the sting fades out and the level's track fades in |

</frozen-after-approval>

## Code Map

- `game/autoloads/audio.gd`: `play_music`/`stop_music`; add the second player and the crossfade
- `game/autoloads/scene_router.gd`: `complete_level`, `goto_title`, `goto_level_select`, `start_level` and `goto_story` (music hooks)
- `game/scenes/title/title.gd`, `level_select`: start `menu`
- `game/data/tuning.json`: `audio.*` (the convoy chain keeps its rows; `explosion_mid` itself changed)
- `tools/import_cc0_audio.py`, `game/assets/CREDITS.md`, `README.md`

## Tasks & Acceptance

**Execution:**
- [x] Audio: the crossfade, default fades and gains; the router and menu hooks
- [x] assets: `menu`, the new epilogue, the medium blast (`explosion_mid`, replacing the planned `explosion_dull`; see the Change Log) and the static; the credits
- [x] tuning, tests, docs

**Acceptance Criteria:**
- Given the full suite on the staged data, when GUT runs, then everything passes.

## Spec Change Log

- 2026-10-14, the operator's picks during implementation (these supersede parts of the Intent's provisional choices):
  - **Menu music:** m05, Fupi's "Synthwave House Loop". Already the default, so no change.
  - **Medium blasts:** the operator first picked y02 (a brightened Spring Spring dull explosion), then switched to a scaled-down Joth (prototype `y08_joth_rescaled_medium_smaller.ogg`).
    - `explosion_mid` (the convoy chain rows, boss-chain rows 0-2 and the turret kills) is now Joth's "Chunky Explosion.mp3" run through `asetrate=44100*1.32,aresample=44100,highpass=f=130,atrim=end=1.35,afade=t=out:st=0.75:d=0.6`. The import tool applies this through a new optional `SfxSource.af` filter chain, run first.
    - The Intent's `explosion_dull` id is dropped. `dull_explosion.wav` stays only as a `tarek_burn` layer.
    - EZduzziteh's explosion3 is retired: its tool row, docstring hash, credit and README mention are removed.
    - The final blast stays Joth's raw file (`explosion_boss_death`). All chain pitches stay at 0.9 or above.
  - **Static:** s02, xhunterko's "Static" (CC0; https://lpc.opengameart.org/node/22007, `ScatterNoise1.mp3`, sha256 712bc6b549d189e112433f609dc0d3a6f07f2d7458f73a08a915c50a1903f124), replacing the softened bretbernhoft re-cut.
    - The steadiest 2.5 s, from 3.0 s in, used raw, mono 44.1 kHz 16-bit, +5 dB to about -20 LUFS (peak about -3.4 dBFS), with a 5 ms fade-in and a 0.2 s fade-out.
    - The exact ffmpeg command is in `CREDITS.md`. The bretbernhoft row and its README mention are removed.
  - **Mix gains:**
    - `epilogue`: +7 dB (Space Echo measures -22.2 LUFS).
    - `menu`: -1.5 dB (Fupi measures -13.0 LUFS).
    - `game_over`: +6 → +3 dB, the same absolute level.
    - With the -7 dB base, the effect-free tracks sit about 3 dB under the in-game tracks.
  - `audio.epilogue_music_delay_s` goes from 1.0 to 2.0, matching the existing data test (delay ≥ `music_fade_out_s`).
- 2026-10-14, review fixes:
  - The opening story waits for a fading menu track (`Audio.is_fading_out()`).
  - `_reload_level` (pause-menu Restart) fades the music.
  - A data test checks that the title card outlasts `music_fade_out_s`.
  - Doc fixes: the level.gd doc comment, decision #78 amending #70, and the Events catalogue.
  - Not changed: `menu` stays in `MUSIC_ACTIONS` (the registry mirror needs it; no level data uses it); a third-track request during a crossfade cuts the oldest leg (documented, unreachable today).
- 2026-10-14, operator retune: fade-out 1.0 s, fade-in and crossfade 1.5 s, epilogue delay 1.0 s. The opening briefing waits for the menu fade, but the epilogue does not.
