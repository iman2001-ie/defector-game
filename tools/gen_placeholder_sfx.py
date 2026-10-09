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


def comms_open(rng: random.Random) -> list[float]:
    """Short 0.25 s radio-open blip: two quick rising sine chirps plus a little band-limited static."""
    n = int(0.25 * RATE)
    chirp_n = int(0.07 * RATE)
    # The chirps start at 0 s and 0.09 s; the second is a fourth higher.
    chirps = ((0, 900.0, 1500.0), (int(0.09 * RATE), 1200.0, 2000.0))
    out: list[float] = []
    phases = [0.0, 0.0]
    lp = 0.0
    bp = 0.0
    for i in range(n):
        t = i / n
        tone = 0.0
        for c, (start, f0, f1) in enumerate(chirps):
            k = i - start
            if 0 <= k < chirp_n:
                u = k / chirp_n
                phases[c] += 2.0 * math.pi * (f0 * (f1 / f0) ** u) / RATE
                tone += math.sin(phases[c]) * _envelope(k, chirp_n, 0.003, 1.4)
        # Static: noise band-passed around ~2.5 kHz, fading out over the blip.
        lp += 0.35 * (rng.uniform(-1.0, 1.0) - lp)
        bp += 0.35 * (lp - bp)
        static = (lp - bp) * (1.0 - t) ** 1.5
        out.append(0.75 * tone + 0.5 * static)
    return out


def _normalise(samples: list[float], peak: float = 0.9) -> list[float]:
    top = max(abs(s) for s in samples) or 1.0
    return [s * peak / top for s in samples]


def _write(name: str, samples: list[float]) -> Path:
    path = OUT_DIR / f"sfx_{name}.wav"
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in _normalise(samples)
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
    for name, samples in sounds.items():
        path = _write(name, samples)
        print(f"wrote {path.name} ({len(samples) / RATE:.2f} s)")
    print(f"{len(sounds)} WAVs written")


if __name__ == "__main__":
    main()
