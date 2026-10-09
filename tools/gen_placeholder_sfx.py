"""Generate DEFECTOR's placeholder SFX (Story 1.6).

Stdlib only, fixed seed, so the output is reproducible. Writes 16-bit mono
44.1 kHz WAVs, each 1 s or shorter, into game/assets/audio/sfx/. These stand in for
Kenney sounds until real assets can be downloaded.

Run from the repo root:  uv run python tools/gen_placeholder_sfx.py
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
SEED = 1606
# Sounds added after Story 1.6 use their own RNG, so the original WAVs stay byte-identical.
PLAYER_HIT_SEED = 3101
PLAYER_DEATH_SEED = 3201
ENERGY_PICKUP_SEED = 3301
ABILITY_DENIED_SEED = 3401
BARRAGE_WHOOSH_SEED = 3501
COMMS_OPEN_SEED = 5101
COMMS_STATIC_SEED = 5401
COMMS_CLICK_SEED = 5102
COMMS_HANDOVER_SEED = 5103
# Normalisation peak per sound when it differs from the default 0.9: the line cues sit under comms_open.
PEAKS = {"comms_click": 0.45, "comms_handover": 0.7}
OUT_DIR = Path(__file__).resolve().parent.parent / "game" / "assets" / "audio" / "sfx"


def _envelope(i: int, n: int, attack_s: float, decay_power: float) -> float:
    """Short linear attack, then a power-curve decay to 0 at the last sample."""
    attack = max(1, int(attack_s * RATE))
    if i < attack:
        return i / attack
    t = (i - attack) / max(1, n - attack)
    return (1.0 - t) ** decay_power


def laser_zap(rng: random.Random) -> list[float]:
    """Short falling tone: square-ish sweep 1800 -> 500 Hz over 0.12 s."""
    n = int(0.12 * RATE)
    out: list[float] = []
    phase = 0.0
    for i in range(n):
        t = i / n
        freq = 1800.0 * (500.0 / 1800.0) ** t
        phase += 2.0 * math.pi * freq / RATE
        tone = math.tanh(3.0 * math.sin(phase))
        out.append(0.45 * tone * _envelope(i, n, 0.002, 1.5))
    return out


def missile_launch(rng: random.Random) -> list[float]:
    """Low thump (sine drop 140 -> 45 Hz) plus a band of low-passed noise."""
    n = int(0.35 * RATE)
    out: list[float] = []
    phase = 0.0
    lp = 0.0
    for i in range(n):
        t = i / n
        freq = 140.0 * (45.0 / 140.0) ** t
        phase += 2.0 * math.pi * freq / RATE
        thump = math.sin(phase) * _envelope(i, n, 0.004, 2.5)
        lp += 0.08 * (rng.uniform(-1.0, 1.0) - lp)
        hiss = lp * _envelope(i, n, 0.01, 1.2)
        out.append(0.7 * thump + 0.9 * hiss)
    return out


def explosion(rng: random.Random, length_s: float, cutoff: float, rumble_hz: float) -> list[float]:
    """Noise burst through a one-pole low-pass; longer and darker for bigger tiers."""
    n = int(length_s * RATE)
    out: list[float] = []
    lp = 0.0
    lp2 = 0.0
    phase = 0.0
    for i in range(n):
        t = i / n
        # The filter closes over time, so the tail gets darker.
        a = cutoff * (1.0 - 0.7 * t)
        lp += a * (rng.uniform(-1.0, 1.0) - lp)
        lp2 += a * (lp - lp2)
        phase += 2.0 * math.pi * rumble_hz * (1.0 - 0.5 * t) / RATE
        rumble = 0.35 * math.sin(phase)
        out.append((2.2 * lp2 + rumble) * _envelope(i, n, 0.003, 2.0))
    return out


def player_hit(rng: random.Random) -> list[float]:
    """Harsh 0.3 s hull hit: clipped buzz (two detuned squares 220 -> 90 Hz) plus a noise crack."""
    n = int(0.30 * RATE)
    out: list[float] = []
    phase_a = 0.0
    phase_b = 0.0
    for i in range(n):
        t = i / n
        freq = 220.0 * (90.0 / 220.0) ** t
        phase_a += 2.0 * math.pi * freq / RATE
        phase_b += 2.0 * math.pi * freq * 1.07 / RATE
        buzz = math.tanh(4.0 * (math.sin(phase_a) + math.sin(phase_b)))
        crack = rng.uniform(-1.0, 1.0) * max(0.0, 1.0 - t * 6.0)
        out.append((0.6 * buzz + 0.8 * crack) * _envelope(i, n, 0.002, 1.8))
    return out


def player_death(rng: random.Random) -> list[float]:
    """Heavy 1.0 s ship loss: a dark explosion with a sub rumble plus a falling clipped buzz (180 -> 40 Hz)."""
    n = int(1.0 * RATE)
    boom = explosion(rng, 1.0, 0.08, 45.0)
    out: list[float] = []
    phase_a = 0.0
    phase_b = 0.0
    for i in range(n):
        t = i / n
        freq = 180.0 * (40.0 / 180.0) ** t
        phase_a += 2.0 * math.pi * freq / RATE
        phase_b += 2.0 * math.pi * freq * 1.11 / RATE
        buzz = math.tanh(3.0 * (math.sin(phase_a) + math.sin(phase_b))) * _envelope(i, n, 0.002, 2.5)
        out.append(1.0 * boom[i] + 0.35 * buzz)
    return out


def energy_pickup(rng: random.Random) -> list[float]:
    """Bright 0.15 s chime: two rising sine partials (880 -> 1760 Hz, plus a fifth) with a tiny sparkle."""
    n = int(0.15 * RATE)
    out: list[float] = []
    phase_a = 0.0
    phase_b = 0.0
    for i in range(n):
        t = i / n
        freq = 880.0 * 2.0 ** t
        phase_a += 2.0 * math.pi * freq / RATE
        phase_b += 2.0 * math.pi * freq * 1.5 / RATE
        sparkle = rng.uniform(-1.0, 1.0) * max(0.0, 1.0 - t * 8.0)
        tone = 0.7 * math.sin(phase_a) + 0.35 * math.sin(phase_b) + 0.08 * sparkle
        out.append(tone * _envelope(i, n, 0.004, 1.6))
    return out


def ability_denied(rng: random.Random) -> list[float]:
    """Short 0.15 s refusal: a low double buzz (two clipped 110 Hz pulses with a little grit)."""
    n = int(0.15 * RATE)
    pulse = n // 2
    gap = int(0.015 * RATE)
    out: list[float] = []
    phase_a = 0.0
    phase_b = 0.0
    for i in range(n):
        phase_a += 2.0 * math.pi * 110.0 / RATE
        phase_b += 2.0 * math.pi * 110.0 * 1.06 / RATE
        k = i % pulse
        if i >= 2 * pulse or k >= pulse - gap:
            out.append(0.0)
            continue
        buzz = math.tanh(4.0 * (math.sin(phase_a) + math.sin(phase_b)))
        grit = rng.uniform(-1.0, 1.0) * 0.15
        out.append((0.8 * buzz + grit) * _envelope(k, pulse - gap, 0.003, 1.2))
    return out


def barrage_whoosh(rng: random.Random) -> list[float]:
    """Short 0.18 s rising whoosh: noise through a band-pass whose centre sweeps 600 -> 3000 Hz."""
    n = int(0.18 * RATE)
    out: list[float] = []
    lp = 0.0
    bp = 0.0
    for i in range(n):
        t = i / n
        centre = 600.0 * 5.0 ** t
        a = min(0.95, 2.0 * math.pi * centre / RATE)
        lp += a * (rng.uniform(-1.0, 1.0) - lp)
        bp += a * (lp - bp)
        # Swells up to a peak at 70%, then a quick linear fade to 0.
        swell = (t / 0.7) ** 1.5 if t < 0.7 else (1.0 - t) / 0.3
        out.append((lp - bp) * swell)
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


def comms_open(rng: random.Random) -> list[float]:
    """0.30 s radio channel opening: a short soft squelch click that settles into a steady carrier
    hiss, then a 1 kHz talk-permit beep as the main event, all through a 300 Hz - 3 kHz voice band
    with light saturation. Steady pitch and a smooth, ungated carrier keep it apart from
    comms_static's stuttering dead channel and from glitchy sci-fi chirps.
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
        if 0 <= k < beep_n:
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


def comms_static(rng: random.Random) -> list[float]:
    """Harsh 0.4 s dead-channel burst: crackly broadband noise with random dropouts and a 50 Hz hum."""
    n = int(0.40 * RATE)
    out: list[float] = []
    hp_prev = 0.0
    hp = 0.0
    gate = 1.0
    phase = 0.0
    for i in range(n):
        t = i / n
        # Every ~10 ms the crackle gate jumps, so the noise stutters like a dying signal.
        if i % int(0.01 * RATE) == 0:
            gate = 1.0 if rng.random() > 0.3 else rng.uniform(0.05, 0.3)
        noise = rng.uniform(-1.0, 1.0)
        # One-pole high-pass keeps it hissy rather than rumbly.
        hp = 0.85 * (hp + noise - hp_prev)
        hp_prev = noise
        phase += 2.0 * math.pi * 50.0 / RATE
        hum = 0.25 * math.tanh(3.0 * math.sin(phase))
        out.append((0.9 * hp * gate + hum) * _envelope(i, n, 0.002, 1.3) * (1.0 - 0.3 * t))
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
    rng = random.Random(SEED)
    sounds = {
        "laser_zap": laser_zap(rng),
        "missile_launch": missile_launch(rng),
        "explosion_small": explosion(rng, 0.30, 0.35, 90.0),
        "explosion_medium": explosion(rng, 0.55, 0.20, 70.0),
        "explosion_large": explosion(rng, 0.90, 0.10, 50.0),
    }
    sounds["player_hit"] = player_hit(random.Random(PLAYER_HIT_SEED))
    sounds["player_death"] = player_death(random.Random(PLAYER_DEATH_SEED))
    sounds["energy_pickup"] = energy_pickup(random.Random(ENERGY_PICKUP_SEED))
    sounds["ability_denied"] = ability_denied(random.Random(ABILITY_DENIED_SEED))
    sounds["barrage_whoosh"] = barrage_whoosh(random.Random(BARRAGE_WHOOSH_SEED))
    sounds["comms_open"] = comms_open(random.Random(COMMS_OPEN_SEED))
    sounds["comms_static"] = comms_static(random.Random(COMMS_STATIC_SEED))
    sounds["comms_click"] = comms_click(random.Random(COMMS_CLICK_SEED))
    sounds["comms_handover"] = comms_handover(random.Random(COMMS_HANDOVER_SEED))
    for name, samples in sounds.items():
        path = _write(name, samples)
        print(f"wrote {path.name} ({len(samples) / RATE:.2f} s)")
    print(f"{len(sounds)} WAVs written")


if __name__ == "__main__":
    main()
