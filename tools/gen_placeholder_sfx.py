"""Generate DEFECTOR's placeholder SFX (Story 1.6).

Stdlib only, fixed seed, so the output is reproducible. Writes 16-bit mono
44.1 kHz WAVs, each under 1 s, into game/assets/audio/sfx/. These stand in for
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
    for name, samples in sounds.items():
        path = _write(name, samples)
        print(f"wrote {path.name} ({len(samples) / RATE:.2f} s)")
    print(f"{len(sounds)} WAVs written")


if __name__ == "__main__":
    main()
