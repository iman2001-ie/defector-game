---
title: 'Epic 7 playtest E: gentler orbs, real Needle lasers, a readable Flagship death and an epilogue track'
type: 'feature'
created: '2026-10-14'
status: 'done'
baseline_commit: 'e803edc'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Several energy orbs in a row stack a loud, grating jingle. The Needle's rising lock beep reads as its "shot", isn't a laser, and the shot itself is silent. The Flagship's death chain blurs into one long rumble, and the explosions play too fast. After the Sovereign falls, the music stops and the ending has no music at all.

**Approach:**
- **Orb:** use a soft CC0 chime (Kenney Interface Sounds `glass_001`), played quieter. A new pickup replaces the one still playing instead of stacking, and quick pickups climb slightly in pitch.
- **Needle:** drop the lock beep and play a CC0 Kenney laser blast (`laserLarge_000`) the moment the bolt fires. The red line stays as the warning.
- **Flagship:** give each chain explosion its own sound (punchy crunches, then the big low rumble last), space the chain out, and play the chain's explosions slower.
- **Epilogue:** add a gentle CC0 track, isaiah658 "Heavenly Loop". It fades in once the boss music has faded out, and keeps playing through the end screen. Going back to the title stops it.

## Boundaries & Constraints

**Always:**
- Every volume, pitch, timing and gain lives in `tuning.json`.
- New third-party files are credited in `CREDITS.md`.
- Only `Feedback` touches time_scale.
- The operator's uncommitted balance edits in `tuning.json` are never staged or overwritten.

**Ask First:** none. The operator asked for these on 2026-10-14. The recommended options were taken while they were away and stay open to change.

**Never:**
- Change the boss fight, the gameplay timings (apart from the death chain), or the telegraph's visual line.
- Add a music track to the title or the menus.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior |
|---|---|---|
| Orb streak | 4 orbs within `streak_window_s` | one chime at a time, each a step higher, capped at `streak_max_steps` |
| Lone orb | the gap since the last pickup is over the window | the chime plays at base pitch |
| Needle | lock, then fire | no sound at the lock; one `needle_fire` when the bolt spawns; nothing without a spawner |
| Boss chain | N offsets, N chain sfx rows | step k plays row k; a missing row falls back to the tier sfx |
| Epilogue on | last level cleared, flag on | boss track fades out, then the epilogue track fades in after `epilogue_music_delay_s` and carries on to the end screen |
| Epilogue off | flag off | the end screen starts the epilogue track |
| Back to title | from the end screen | the music fades out |

</frozen-after-approval>

## Code Map

- `game/autoloads/audio.gd`: the SFX and MUSIC registries; `play_sfx`; `play_music` (add a fade-in and a per-track gain)
- `game/entities/pickups/energy_orb.gd:98`: `collect()` plays the pickup
- `game/entities/enemies/needle/needle.gd:171,193`: the lock cue and `_fire()`
- `game/autoloads/feedback.gd:258-285`: `boss_death` and `step_chain`
- `game/entities/effects/explosion.gd`: particle lifetimes and `LIFETIME_S`
- `game/autoloads/scene_router.gd:272,233`: `complete_level` and `goto_title`
- `game/scenes/story/story.gd` and `game/scenes/end/end_screen.gd`: start the epilogue track
- `game/systems/waves/level_validator.gd:59`: `MUSIC_ACTIONS`
- `tools/import_cc0_audio.py`: the CC0 import table

## Tasks & Acceptance

**Execution:**
- [x] `tools/import_cc0_audio.py` and `game/assets`: import `needle_fire`, the new `energy_pickup` and `music_epilogue.ogg`; remove `sfx_needle_lock.wav`; update `CREDITS.md`
- [x] `game/autoloads/audio.gd`: registry changes; `play_sfx_solo` (stops the same id first); `play_music(id, fade_in_s)` with the gain from `audio.music_gain_db.<id>`
- [x] `energy_orb.gd`: the streak pitch and solo play, from `pickups.energy_orb.sfx`
- [x] `needle.gd`: the fire cue
- [x] `feedback.gd` and `explosion.gd`: chain sfx rows and an explosion `speed` parameter
- [x] router, story scene and end screen: start and stop the epilogue track; add `epilogue` to `MUSIC_ACTIONS`
- [x] `game/data/tuning.json`: the new keys and `boss_death_chain_s` 2.0 → 3.0
- [x] tests: update the Needle, orb, audio, feedback, explosion, router and validator tests for the matrix above
- [x] docs: a GDD decision-log row

**Acceptance Criteria:**
- Given the full suite, when GUT runs headless, then every test passes.
- Given Level 3, when the Flagship dies, then the operator hears the chain as distinct blasts and the explosions visibly play slower.

## Verification

**Commands:**
- `--headless --path game --import`, then GUT: expected all pass

**Manual checks:**
- The operator listens to the orbs, the Needle, the boss death and the epilogue.

## Suggested Review Order

**Epilogue music**

- Fade-in plus per-track gain is the core of the gentle ending track.
  [`audio.gd:218`](../../game/autoloads/audio.gd#L218)
- The story scene waits for the boss fade-out, then fades the epilogue in.
  [`story.gd:81`](../../game/scenes/story/story.gd#L81)
- The end screen continues the track or starts it after the same delay.
  [`end_screen.gd:89`](../../game/scenes/end/end_screen.gd#L89)
- Every return to the title fades the music out.
  [`scene_router.gd:236`](../../game/autoloads/scene_router.gd#L236)

**Flagship death chain**

- Each chain step plays its own sound row and a slower explosion.
  [`feedback.gd:275`](../../game/autoloads/feedback.gd#L275)
- Malformed rows (or a pitch of 0 or less) fall back to the tier sound.
  [`feedback.gd:384`](../../game/autoloads/feedback.gd#L384)
- The `speed` param stretches particles, shockwave and lifetime.
  [`explosion.gd:62`](../../game/entities/effects/explosion.gd#L62)

**Orb and Needle**

- Solo play: a new cue replaces the same cue instead of stacking.
  [`audio.gd:161`](../../game/autoloads/audio.gd#L161)
- A shared real-time streak raises the pitch for quick pickups.
  [`energy_orb.gd:126`](../../game/entities/pickups/energy_orb.gd#L126)
- The laser cue fires only with the bolt; the lock beep is gone.
  [`needle.gd:25`](../../game/entities/enemies/needle/needle.gd#L25)

**Data and assets**

- New keys: `energy.orb_sfx`, `fire_sfx_volume_db`, chain rows, the `audio` fade and gain.
  [`tuning.json:59`](../../game/data/tuning.json#L59)
- Reproducible CC0 imports for the chime, the laser and Heavenly Loop.
  [`import_cc0_audio.py:1`](../../tools/import_cc0_audio.py#L1)
