---
title: 'Story 5.4 follow-up: make the cut-off readable and hit hard'
type: 'feature'
created: '2026-10-09'
status: 'done'
baseline_commit: 'c1ee4fea997cee8f0dd5e3cded7c6b797ffb867f'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-5-4-cut-a-line-off-mid-sentence.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-5-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** In the Story 5.4 operator check, the cut-off went by too fast to follow. The line types its 39 characters in 0.87 s and the box hides 0.6 s later, so it's on screen for about 1.5 s against 5 s for other combat lines. Nothing marks the cut. The `large` shake (8 px, 0.25 s) is barely felt, and the 0.4 s generated static is far too short and doesn't sound like a dead radio channel.

**Approach:** Make it a timeline of about 7 s:
- The cut-off line types slower, so the cut lands at about 2.4 s.
- At the cut, a `...` suffix appears, a dedicated strong shake fires and 4.5 s of softened CC0 static plays, with a 0.2 s fade-out at its very end.
- The box holds the cut text for the same 4.5 s, then vanishes instantly as the static ends (no fade, as before).

Every number lives in `tuning.json`.

## Boundaries & Constraints

**Always:**
- **New tuning keys under `comms`:**
  - `cutoff_chars_per_s`: 16
  - `cutoff_suffix`: `"..."`
  - `cutoff_shake_px`: 18
  - `cutoff_shake_s`: 0.9
- **Changed tuning key:** `cutoff_hide_s` goes from 0.6 to 4.5, equal to the clip's length.
- **Typing speed:** a cut-off line's typing timer in `CommsChannel` and its tween in `CommsBox` both use `cutoff_chars_per_s`. A value of 0 or less means instant, as with the normal speed.
- **`CommsBox.cut_off(chars, suffix := "")`:**
  - It kills the type tween.
  - It sets the text to the first `chars` characters plus `suffix`, all visible.
  - With an empty suffix it behaves as today.
- **Shake:**
  - `after.shake` accepts every `ImpactTier` name plus the new keyword `"cutoff"`.
  - `"cutoff"` shakes through a new `Feedback.shake(px, s)` using `comms.cutoff_shake_px`/`cutoff_shake_s`.
  - Only `Feedback` touches the camera.
  - `DialogueValidator` accepts `"cutoff"`.
  - `dev.json`'s `dev_tarek_cutoff` changes to `"shake": "cutoff"`.
- **SFX:**
  - `sfx_comms_static.wav` is replaced with the clip the user picked: CC0 "Frequency Static" `static2.wav` by bretbernhoft (OpenGameArt), from 20.0 s for 4.5 s, mono 44.1 kHz 16-bit, limiter at 0.9 without auto-level, a gentle 1-pole 6 kHz lowpass and -0.6 dB (slightly softer: mean about -12.0 dB, peak about -1.6 dB).
  - **No decay.** It's full static to the end, with a 5 ms fade-in and a 0.2 s fade-out at its very end. The audition file is `static_4.5s_slightly_soft.wav`.
  - `comms_static` is removed from `tools/gen_placeholder_sfx.py` (the function, seed and `sounds` entry) so a regeneration can't overwrite it. The other WAVs must stay byte-identical.
  - The `CREDITS.md` row names the source URL, the author, CC0 and the ffmpeg recipe used.
  - Run `--import` afterwards.
- **Decision logs:** the user changed these documented rules (FR35/GDD "large-tier shake", UX EXPERIENCE.md:67 "hides after 0.6 s"). Record them as GDD decision #43 and UX decision #25. Update EXPERIENCE.md:67 and the 5.4 As-built section of `game-architecture.md`.
- Existing 5.4 behaviour is unchanged: the order of the after effects, silence, the void rule, preempt and pause freeze.

**Ask First:** any change to the static's level, filtering or length beyond the user-picked `static_4.5s_slightly_soft.wav`.

**Never:**
- No fade on the cut-off box.
- No changes to the impact tiers, other combat lines or story panel timing.
- No Tarek ship or fall visuals (Story 6.5).
- No sprint-status change: 5.4 stays `awaiting-operator` for bmad-loop.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Timeline | `dev_tarek_cutoff`, tuning defaults | no effects before 39/16 s; at the cut: text `General, get behind me, I've got you co...`, static plays, camera shakes 18 px, silenced; box visible until +4.5 s, then hidden (no fade) and `finished` once | none |
| Tier shake still works | `after.shake: "large"` | `Feedback.shake_tier(LARGE)` as before | none |
| Validator | `shake: "cutoff"` / `shake: "huge"` | valid / one problem | logged |
| Empty suffix | `cutoff_suffix: ""` | text stops at 39 characters, no suffix | none |
| Bad shake values | `Feedback.shake(0, 1)` or no camera | no-op | none |

</frozen-after-approval>

## Code Map

- `game/data/tuning.json` (about l.217, `comms`): the new and changed keys.
- `game/systems/comms/comms_channel.gd`:
  - `_ready` caches tuning (l.~123).
  - `_show_combat_line` sets the cut timer (l.~387).
  - `_cut_off` (l.408) calls `box.cut_off` and runs the shake.
- `game/systems/comms/comms_box.gd`: `show_line` and `_type` (l.112, l.224) for the cut speed, and `cut_off` (l.153) for the suffix.
- `game/autoloads/feedback.gd`: `shake_tier` and `_shake` (l.90, l.131). Add `shake(px, s)`.
- `game/systems/comms/dialogue_validator.gd`: the `after.shake` check and a `SHAKE_CUTOFF` const.
- `game/data/dialogue/dev.json` (l.35): `shake` changes to `cutoff`.
- `tools/gen_placeholder_sfx.py`: remove `comms_static` (l.27, l.302, l.364).
- `game/assets/audio/sfx/sfx_comms_static.wav` and `game/assets/CREDITS.md` (l.29).
- Tests:
  - `test_comms_channel.gd`: the cut-off timeline tests around l.700–860, which use hide/typing durations from tuning.
  - `test_comms_box.gd` (l.218).
  - `test_dialogue_validator.gd` (l.186).
  - `test_feedback.gd`.
  - `tests/data/test_data_files.gd` (l.1029).
  - `test_level.gd` (l.1100–1190).
  - `tests/fixtures/dialogue/channel/channel.json`.

## Tasks & Acceptance

**Execution:**
- [x] Tests first: update and extend `test_comms_channel.gd`, `test_comms_box.gd`, `test_feedback.gd`, `test_dialogue_validator.gd`, `test_data_files.gd` and `test_level.gd` so every matrix row has a test. Durations come from `Config`, not literals.
- [x] `game/data/tuning.json`: add and change the keys listed above.
- [x] `game/autoloads/feedback.gd`: `shake(px, s)`. `_shake` reuses it.
- [x] `dialogue_validator.gd`, `comms_box.gd`, `comms_channel.gd`: the cut speed, the suffix and the `cutoff` shake. Update the doc comments.
- [x] `game/data/dialogue/dev.json`: `"shake": "cutoff"`.
- [x] Static: cut the chosen clip with ffmpeg into `sfx_comms_static.wav`, then update the generator, `CREDITS.md` and run `--import`.
- [x] Docs: GDD decision-log #43, UX `.decision-log.md` #25, EXPERIENCE.md:67, and the 5.4 As-built section in `game-architecture.md`.

**Acceptance Criteria:**
- Given level_dev wave 2 with real kills past 0.25, when the cut-off fires, then the box shows the line ending in `co...` at about 2.4 s, `comms_static` (the new clip) plays, the ShakeCamera amplitude is 18 px, and the box hides 4.5 s later without fading.
- Given F3 on the same wave, then the cut-off still fires and wave 3 starts.
- Given the full GUT suite after `--import`, then everything passes, and the existing generated WAVs are byte-identical in `git status`.

## Spec Change Log

- 2026-10-09: user retuned after hearing it: 4.5 s hold and clip, softer clip, 0.2 s end fade.

## Design Notes

The cut lands mid-typing because the slower typing speed sells it as an interruption rather than a pause. The 4.5 s hold equals the static clip's length, so the box and the static end on the same frame. The quick end into silence (the music has stopped too) is the "radio silence": the static has no decay, only a 0.2 s fade-out at its very end so it doesn't click off. The user rejected decaying static in the audition, then shortened and softened the first 6.0 s full-level cut after hearing it.

## Verification

**Commands:**
- `uv run python tools/gen_placeholder_sfx.py`: expected the other WAVs unchanged and `sfx_comms_static.wav` left untouched.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import`: expected exit 0.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`: expected all tests passing.

## Suggested Review Order

**Cut-off moment and hold**

- Entry point: the cut runs the suffix, the dedicated shake and the static, and keeps the static's player.
  [`comms_channel.gd:434`](../../game/systems/comms/comms_channel.gd#L434)

- HOLD counts real time, so hit-stop can't stretch the box past the 4.5 s static.
  [`comms_channel.gd:483`](../../game/systems/comms/comms_channel.gd#L483)

- The static stops with the line: hide, preempt, clear, exit tree.
  [`comms_channel.gd:513`](../../game/systems/comms/comms_channel.gd#L513)

- Pause mirrors into the static's `stream_paused` (the channel runs ALWAYS).
  [`comms_channel.gd:333`](../../game/systems/comms/comms_channel.gd#L333)

- A checked suffix read; a bad type logs and falls back to "".
  [`comms_channel.gd:488`](../../game/systems/comms/comms_channel.gd#L488)

**Box, shake and validation**

- The box shows the cut text plus the suffix, fully visible.
  [`comms_box.gd:159`](../../game/systems/comms/comms_box.gd#L159)

- A cut-off line types at `cutoff_chars_per_s`.
  [`comms_box.gd:236`](../../game/systems/comms/comms_box.gd#L236)

- A public shake with explicit px/s; tier shakes reuse it.
  [`feedback.gd:100`](../../game/autoloads/feedback.gd#L100)

- `after.shake` accepts the "cutoff" keyword besides tier names.
  [`dialogue_validator.gd:164`](../../game/systems/comms/dialogue_validator.gd#L164)

**Data, asset and docs**

- New and retuned cut-off keys; the hold equals the clip length.
  [`tuning.json:222`](../../game/data/tuning.json#L222)

- The real Level 2 cut-off also uses the dedicated shake (GDD #43).
  [`level_2.json:21`](../../game/data/dialogue/level_2.json#L21)

- The CC0 static credit with its exact ffmpeg recipe.
  [`CREDITS.md:10`](../../game/assets/CREDITS.md#L10)

- The architecture follow-up recording the as-built timing and rules.
  [`game-architecture.md:1745`](../../_bmad-output/game-architecture.md#L1745)

**Tests**

- The full timeline: suffix, 18 px shake, 4.5 s hold, finished once.
  [`test_comms_channel.gd:747`](../../game/tests/unit/test_comms_channel.gd#L747)

- Static lifetime: hide, preempt, tree exit, pause.
  [`test_comms_channel.gd:839`](../../game/tests/unit/test_comms_channel.gd#L839)

## Auto Run Result

Review: three reviewers. Patched: the static is tied to the line's lifetime (hide, preempt, exit tree, pause), the HOLD counts real time, the WAV is re-cut so the limiter's lookahead no longer drops the end ramp, the suffix read is checked, and doc and test fixes. Deferred: DW-80 (Audio pool can steal the long static), DW-81 (wider typing window makes preempt and void more likely), DW-82 (the 6 s hold delays the next wave's chatter). Deviation accepted: `level_2.json` `l2_w5_tarek_cutoff` also uses `"shake": "cutoff"`, per GDD #43. Sprint-status untouched: 5.4 stays `awaiting-operator` for bmad-loop. GUT: 1374/1374 passing.
