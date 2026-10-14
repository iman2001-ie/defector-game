"""Generate DEFECTOR's project-made SFX (Story 1.6; trimmed in Story 8.1).

Stdlib only, fixed seeds, so the output is reproducible. Writes 16-bit mono
44.1 kHz WAVs, each 1 s or shorter, into game/assets/audio/sfx/. Only the five
cues tuned in operator checks are made here (GDD decisions #40-#43, and the
Maul alarm, which Kenney has no match for): comms_open, comms_open_nobeep,
comms_click, comms_handover and maul_alarm. Re-running leaves them
byte-identical.

The combat SFX are CC0 Kenney sounds imported by tools/import_cc0_audio.py, and
sfx_comms_static.wav is a CC0 recording (see game/assets/CREDITS.md), so a
regeneration never overwrites them.

Run from the repo root:  uv run python tools/gen_placeholder_sfx.py
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
# Each sound uses its own RNG, so every WAV stays byte-identical when another changes.
COMMS_OPEN_SEED = 5101
COMMS_CLICK_SEED = 5102
COMMS_HANDOVER_SEED = 5103
MAUL_ALARM_SEED = 6201
# Normalisation peak per sound when it differs from the default 0.9: the line cues sit under comms_open.
PEAKS = {"comms_click": 0.45, "comms_handover": 0.7, "maul_alarm": 0.6}
OUT_DIR = Path(__file__).resolve().parent.parent / "game" / "assets" / "audio" / "sfx"


def _envelope(i: int, n: int, attack_s: float, decay_power: float) -> float:
    """Short linear attack, then a power-curve decay to 0 at the last sample."""
    attack = max(1, int(attack_s * RATE))
    if i < attack:
        return i / attack
    t = (i - attack) / max(1, n - attack)
    return (1.0 - t) ** decay_power


def maul_alarm(rng: random.Random) -> list[float]:
    """Short 0.36 s two-tone alarm ping (Story 6.2): a 1320 Hz beep, a short gap, then a 990 Hz beep,
    each a soft-clipped sine with a quick attack and decay plus a trace of grit."""
    beep = int(0.15 * RATE)
    gap = int(0.06 * RATE)
    out: list[float] = []
    for freq in (1320.0, 990.0):
        phase = 0.0
        for i in range(beep):
            phase += 2.0 * math.pi * freq / RATE
            tone = math.tanh(2.0 * math.sin(phase)) + 0.25 * math.sin(2.0 * phase)
            grit = rng.uniform(-1.0, 1.0) * 0.03
            out.append((tone + grit) * _envelope(i, beep, 0.004, 1.3))
        if freq == 1320.0:
            out.extend([0.0] * gap)
    return out


def _one_pole(cutoff_hz: float) -> float:
    """Smoothing coefficient for a one-pole low-pass at cutoff_hz."""
    return 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / RATE)


def _fade(k: int, n: int, edge: int) -> float:
    """Raised-cosine fade in over the first `edge` samples and out over the last, so tones never click.
    `edge` is clamped to [1, n // 2], so short tones still reach 0 at both ends."""
    edge = max(1, min(edge, n // 2))
    if k < edge:
        return 0.5 - 0.5 * math.cos(math.pi * k / edge)
    if k >= n - edge:
        return 0.5 - 0.5 * math.cos(math.pi * (n - 1 - k) / edge)
    return 1.0


def comms_open(rng: random.Random, beep_on: bool = True) -> list[float]:
    """0.30 s radio channel opening: a short soft squelch click that settles into a steady carrier
    hiss, then a 1 kHz talk-permit beep as the main event, all through a 300 Hz - 3 kHz voice band
    with light saturation. Steady pitch and a smooth, ungated carrier keep it apart from
    the cut-off's recorded dead-channel static and from glitchy sci-fi chirps.
    """
    n = int(0.30 * RATE)
    attack_n = int(0.002 * RATE)
    click_n = int(0.03 * RATE)
    settle_n = int(0.012 * RATE)
    beep_start = int(0.045 * RATE)
    beep_n = int(0.10 * RATE)
    tail_n = int(0.08 * RATE)
    click_level = 0.5
    carrier_level = 0.2
    # The beep starts once the click has settled and ends before the carrier fades out.
    assert click_n + settle_n <= beep_start
    assert beep_start + beep_n <= n - tail_n
    raw: list[float] = []
    phase = 0.0
    for i in range(n):
        noise = rng.uniform(-1.0, 1.0)
        # Squelch click: 2 ms attack, held for 30 ms, then a 12 ms crossfade down to the carrier.
        if i < attack_n:
            hiss = click_level * (0.5 - 0.5 * math.cos(math.pi * i / attack_n))
        elif i < click_n:
            hiss = click_level
        elif i < click_n + settle_n:
            u = (i - click_n) / settle_n
            hiss = carrier_level + (click_level - carrier_level) * (0.5 + 0.5 * math.cos(math.pi * u))
        else:
            hiss = carrier_level
        # The carrier fades out over the last 80 ms.
        hiss *= min(1.0, (n - 1 - i) / tail_n)
        beep = 0.0
        k = i - beep_start
        if beep_on and 0 <= k < beep_n:
            phase += 2.0 * math.pi * 1000.0 / RATE
            beep = (math.sin(phase) + 0.15 * math.sin(3.0 * phase)) * _fade(k, beep_n, int(0.005 * RATE))
        raw.append(noise * hiss + 0.3 * beep)
    return _voice_band(raw)


def _mic_click(rng: random.Random) -> list[float]:
    """Raw 40 ms push-to-talk click: a noise tick with a 1 ms attack and a ~6 ms decay, plus a
    damped 1.6 kHz ring for the switch body. Unfiltered; callers pass it through _voice_band."""
    n = int(0.04 * RATE)
    attack_n = int(0.001 * RATE)
    decay_n = 0.006 * RATE
    ring_decay_n = 0.004 * RATE
    out: list[float] = []
    for i in range(n):
        attack = 0.5 - 0.5 * math.cos(math.pi * i / attack_n) if i < attack_n else 1.0
        tick = rng.uniform(-1.0, 1.0) * math.exp(-i / decay_n)
        ring = math.sin(2.0 * math.pi * 1600.0 * i / RATE) * math.exp(-i / ring_decay_n)
        out.append(attack * (0.6 * tick + 0.4 * ring))
    return out


def comms_click(rng: random.Random) -> list[float]:
    """Quiet 40 ms mic-click for the same speaker keying in again (next story line)."""
    return _voice_band(_mic_click(rng))


def comms_handover(rng: random.Random) -> list[float]:
    """~0.22 s speaker change: a 150 ms squelch tail ("kssh", the last speaker releasing the mic),
    a 25 ms gap, then the new speaker's quieter mic-click. No beep: that stays comms_open's."""
    tail_n = int(0.15 * RATE)
    hold_n = int(0.09 * RATE)
    attack_n = int(0.003 * RATE)
    gap_n = int(0.025 * RATE)
    raw: list[float] = []
    for i in range(tail_n):
        attack = 0.5 - 0.5 * math.cos(math.pi * i / attack_n) if i < attack_n else 1.0
        # Holds at full level, then a raised-cosine fade that reaches exactly 0 at the last sample.
        if i < hold_n:
            level = 1.0
        else:
            level = 0.5 + 0.5 * math.cos(math.pi * (i - hold_n) / (tail_n - 1 - hold_n))
        raw.append(rng.uniform(-1.0, 1.0) * attack * level)
    raw.extend([0.0] * gap_n)
    raw.extend(0.5 * s for s in _mic_click(rng))
    return _voice_band(raw)


def _voice_band(samples: list[float]) -> list[float]:
    """Radio voice band: one-pole high-pass at 300 Hz, two-pole low-pass at 3 kHz, light saturation."""
    hp_a = _one_pole(300.0)
    lp_a = _one_pole(3000.0)
    out: list[float] = []
    hp_lp = 0.0
    lp1 = 0.0
    lp2 = 0.0
    for x in samples:
        hp_lp += hp_a * (x - hp_lp)
        x -= hp_lp
        lp1 += lp_a * (x - lp1)
        lp2 += lp_a * (lp1 - lp2)
        out.append(math.tanh(1.8 * lp2))
    return out


def _normalise(samples: list[float], peak: float = 0.9) -> list[float]:
    top = max(abs(s) for s in samples) or 1.0
    return [s * peak / top for s in samples]


def _write(name: str, samples: list[float]) -> Path:
    path = OUT_DIR / f"sfx_{name}.wav"
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767))
        for s in _normalise(samples, PEAKS.get(name, 0.9))
    )
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(frames)
    return path


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sounds: dict[str, list[float]] = {}
    sounds["comms_open"] = comms_open(random.Random(COMMS_OPEN_SEED))
    # The combat box's channel-open: comms_open with the talk-permit beep left out (GDD #42),
    # scaled by comms_open's own normalisation gain, so its click and carrier stay at the same level.
    sounds["comms_open_nobeep"] = comms_open(random.Random(COMMS_OPEN_SEED), beep_on=False)
    PEAKS["comms_open_nobeep"] = 0.9 * max(abs(s) for s in sounds["comms_open_nobeep"]) / max(abs(s) for s in sounds["comms_open"])
    sounds["comms_click"] = comms_click(random.Random(COMMS_CLICK_SEED))
    sounds["comms_handover"] = comms_handover(random.Random(COMMS_HANDOVER_SEED))
    sounds["maul_alarm"] = maul_alarm(random.Random(MAUL_ALARM_SEED))
    for name, samples in sounds.items():
        path = _write(name, samples)
        print(f"wrote {path.name} ({len(samples) / RATE:.2f} s)")
    print(f"{len(sounds)} WAVs written")


if __name__ == "__main__":
    main()
