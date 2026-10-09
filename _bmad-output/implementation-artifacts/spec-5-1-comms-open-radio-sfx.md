---
title: 'Story 5.1 follow-up: make the comms-open SFX sound like a radio channel opening'
type: 'bugfix'
created: '2026-10-09'
status: 'done'
route: 'one-shot'
---

# Story 5.1 follow-up: make the comms-open SFX sound like a radio channel opening

## Intent

**Problem:** During the Story 5.1 operator check, the comms-open cue played on time but sounded like a glitch, not a radio channel opening. It was two fast rising sine chirps over fading static, which read as a sci-fi blip.

**Approach:** Regenerate `sfx_comms_open.wav` from `tools/gen_placeholder_sfx.py` as a 0.30 s radio cue. A short, soft squelch click crossfades into a steady carrier hiss, then a steady-pitch 1 kHz talk-permit beep plays as the main event. Everything passes through a 300 Hz - 3 kHz voice band with light saturation. There is no gating and no hum, so the cue stays distinct from `comms_static`. Every other WAV regenerates byte-identical (per-sound seeds).

## Suggested Review Order

**The new cue**

- Entry point: the docstring states the sound design and how the cue is kept distinct from `comms_static`.
  [gen_placeholder_sfx.py:196](../../tools/gen_placeholder_sfx.py#L196)

- Layout invariants: the beep starts after the click settles and ends before the carrier fade.
  [gen_placeholder_sfx.py:212](../../tools/gen_placeholder_sfx.py#L212)

- Squelch click: a 2 ms attack, then a 12 ms raised-cosine crossfade to the carrier. There is no hard cut, so no near-silent gap.
  [gen_placeholder_sfx.py:223](../../tools/gen_placeholder_sfx.py#L223)

- Talk-permit beep mix level, then the voice-band filter and saturation.
  [gen_placeholder_sfx.py:240](../../tools/gen_placeholder_sfx.py#L240)

**Supporting**

- `_fade` now clamps `edge`, so short tones still reach 0 at both ends.
  [gen_placeholder_sfx.py:185](../../tools/gen_placeholder_sfx.py#L185)

- Regenerated asset (binary; check it by ear in the level with `-- --comms=dev_comms_check`).
  [sfx_comms_open.wav](../../game/assets/audio/sfx/sfx_comms_open.wav)
