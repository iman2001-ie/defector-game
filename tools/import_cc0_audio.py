"""Import DEFECTOR's CC0 sounds and music (Story 8.1).

Reads files from unzipped CC0 packs, writes the combat SFX into
game/assets/audio/sfx/ and copies the three music tracks into
game/assets/audio/music/. Stdlib only, plus `ffmpeg` on the PATH.

SFX: each source is decoded, downmixed to mono at 44.1 kHz, optionally trimmed
to its first `trim_s` seconds (then a 5 ms fade-in and a `fade_out_s` fade-out
at its end), and peak-normalised to -1 dBFS in two passes (pass 1 measures the
peak with `astats`, pass 2 applies the gain), written as 16-bit PCM
`sfx_<id>.wav`. Music: copied byte-for-byte to `music_<id>.ogg` after a SHA-256
check. Set `loop=true` in each music `.import` sidecar after Godot imports it.

The five generated comms cues and `maul_alarm` (tools/gen_placeholder_sfx.py)
and the recorded `comms_static` are not touched.

Sources (all CC0 1.0 on their OpenGameArt page; files are at
https://opengameart.org/sites/default/files/<file>):

- Kenney "Sci-Fi Sounds", https://opengameart.org/content/sci-fi-sounds
  sci-fi_sounds.zip
  sha256 119340f351a5098ad814f78719438c0da355a9ce8a4c8a3af6a8d48aa3d49e04
- Kenney "Interface Sounds", https://opengameart.org/content/interface-sounds
  kenney_interfaceSounds.zip
  sha256 f2193d072726d6758a5f7871b2dcc54dcce0d5c35c6f0a62f92549b327c81232
- MintoDog "Space Adventure", https://opengameart.org/content/space-adventure
  space_adventure_bpm140_0.ogg
  sha256 30e31ee6da7a24bea35bf22d6c125f8100f803fca20a3f59637e52a4fd764ce3
- MintoDog "Space Boss Battle", https://opengameart.org/content/space-boss-battle
  space_boss_battle_bpm175_0.ogg
  sha256 4fc0898456099db3d9e63bd97450fedc3f9ff0a05cd65a8d363b3f2904415e60
- isaiah658 "Heavenly Loop", https://opengameart.org/content/heavenly-loop
  Heavenly Loop_0.ogg (the epilogue track; playtest pt7-e)
  sha256 a842e9e054019132cacc8fd352e7b31c000ebb51e0b227a2511e1bccb4eb166e

Download the files, unzip each archive into its own empty folder under one
packs folder, put the three OGGs in that packs folder too, then run from the repo
root:

    uv run python tools/import_cc0_audio.py --packs <packs folder>

Files are found by name anywhere under --packs (each name must match exactly
one file). Then run Godot's headless --import.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

RATE = 44100
TARGET_PEAK_DB = -1.0
FADE_IN_S = 0.005
REPO_ROOT = Path(__file__).resolve().parent.parent
SFX_DIR = REPO_ROOT / "game" / "assets" / "audio" / "sfx"
MUSIC_DIR = REPO_ROOT / "game" / "assets" / "audio" / "music"


@dataclass(frozen=True)
class SfxSource:
    """One SFX: the pack it comes from, its file name in the pack and the optional trim."""

    pack: str
    file: str
    trim_s: float | None = None
    fade_out_s: float | None = None


@dataclass(frozen=True)
class MusicSource:
    """One music track: its file name and the SHA-256 of the downloaded file."""

    file: str
    sha256: str


SCI_FI = "Kenney Sci-Fi Sounds"
INTERFACE = "Kenney Interface Sounds"

# Registry id -> source. The game writes `sfx_<id>.wav`.
SFX_SOURCES: dict[str, SfxSource] = {
    "laser_zap": SfxSource(SCI_FI, "laserSmall_001.ogg"),
    "missile_launch": SfxSource(SCI_FI, "thrusterFire_003.ogg", trim_s=0.55, fade_out_s=0.3),
    "barrage_whoosh": SfxSource(SCI_FI, "thrusterFire_001.ogg", trim_s=0.30, fade_out_s=0.2),
    "explosion_small": SfxSource(SCI_FI, "explosionCrunch_000.ogg"),
    "explosion_medium": SfxSource(SCI_FI, "explosionCrunch_001.ogg"),
    "explosion_large": SfxSource(SCI_FI, "explosionCrunch_004.ogg"),
    "explosion_boss_part": SfxSource(SCI_FI, "lowFrequency_explosion_001.ogg"),
    "explosion_boss_death": SfxSource(SCI_FI, "lowFrequency_explosion_000.ogg"),
    "player_hit": SfxSource(SCI_FI, "impactMetal_002.ogg"),
    "player_death": SfxSource(SCI_FI, "explosionCrunch_003.ogg"),
    "shield_on": SfxSource(SCI_FI, "forceField_000.ogg"),
    "energy_pickup": SfxSource(INTERFACE, "glass_001.ogg"),
    "needle_fire": SfxSource(SCI_FI, "laserLarge_000.ogg", trim_s=0.45, fade_out_s=0.2),
    "ability_denied": SfxSource(INTERFACE, "error_007.ogg"),
}

# Music id -> source. The game copies it to `music_<id>.ogg`.
MUSIC_SOURCES: dict[str, MusicSource] = {
    "combat": MusicSource(
        "space_adventure_bpm140_0.ogg",
        "30e31ee6da7a24bea35bf22d6c125f8100f803fca20a3f59637e52a4fd764ce3",
    ),
    "boss": MusicSource(
        "space_boss_battle_bpm175_0.ogg",
        "4fc0898456099db3d9e63bd97450fedc3f9ff0a05cd65a8d363b3f2904415e60",
    ),
    "epilogue": MusicSource(
        "Heavenly Loop_0.ogg",
        "a842e9e054019132cacc8fd352e7b31c000ebb51e0b227a2511e1bccb4eb166e",
    ),
}

_PEAK_RE = re.compile(r"Peak level dB:\s*(-?inf|-?[0-9.]+)")


def sfx_name(sfx_id: str) -> str:
    return f"sfx_{sfx_id}.wav"


def music_name(music_id: str) -> str:
    return f"music_{music_id}.ogg"


def filter_chain(source: SfxSource) -> str:
    """The shared filters: mono float at 44.1 kHz, then the optional trim and fades."""
    filters = [f"aformat=sample_fmts=flt:sample_rates={RATE}:channel_layouts=mono"]
    if source.trim_s is not None:
        filters.append(f"atrim=end={source.trim_s:g}")
        filters.append(f"afade=t=in:d={FADE_IN_S:g}")
        if source.fade_out_s is not None:
            start = source.trim_s - source.fade_out_s
            filters.append(f"afade=t=out:st={start:g}:d={source.fade_out_s:g}")
    return ",".join(filters)


def measure_args(src: Path, source: SfxSource) -> list[str]:
    """Pass 1: run the chain and print the overall peak (astats) to stderr."""
    chain = filter_chain(source) + ",astats=measure_perchannel=none:measure_overall=Peak_level"
    return ["ffmpeg", "-hide_banner", "-nostats", "-i", str(src), "-af", chain, "-f", "null", "-"]


def render_args(src: Path, out: Path, source: SfxSource, gain_db: float) -> list[str]:
    """Pass 2: the same chain plus the gain, written as bit-exact 16-bit mono PCM."""
    chain = filter_chain(source) + f",volume={gain_db:.6f}dB"
    return [
        "ffmpeg", "-hide_banner", "-nostats", "-y", "-i", str(src), "-af", chain,
        "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
        "-ac", "1", "-ar", str(RATE), "-c:a", "pcm_s16le", str(out),
    ]


def parse_peak_db(stderr: str) -> float:
    """The last `Peak level dB` astats printed (the overall one)."""
    matches = _PEAK_RE.findall(stderr)
    if not matches:
        raise ValueError("no 'Peak level dB' in ffmpeg output")
    value = matches[-1]
    if value.endswith("inf"):
        raise ValueError("the source is silent")
    return float(value)


def gain_db(peak_db: float, target_db: float = TARGET_PEAK_DB) -> float:
    return target_db - peak_db


def find_file(packs: Path, name: str) -> Path:
    """The one file called `name` anywhere under `packs`."""
    matches = sorted(p for p in packs.rglob(name) if p.is_file())
    if len(matches) != 1:
        raise FileNotFoundError(f"expected exactly one '{name}' under {packs}, found {len(matches)}")
    return matches[0]


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 16), b""):
            digest.update(block)
    return digest.hexdigest()


def _run(args: list[str]) -> str:
    result = subprocess.run(args, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(f"{args[0]} failed ({result.returncode}):\n{result.stderr}")
    return result.stderr


def import_sfx(packs: Path, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    for sfx_id, source in SFX_SOURCES.items():
        src = find_file(packs, source.file)
        peak = parse_peak_db(_run(measure_args(src, source)))
        gain = gain_db(peak)
        out = out_dir / sfx_name(sfx_id)
        _run(render_args(src, out, source, gain))
        print(f"wrote {out.name} from {source.file} (peak {peak:.2f} dB, gain {gain:+.2f} dB)")


def import_music(packs: Path, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    for music_id, source in MUSIC_SOURCES.items():
        src = find_file(packs, source.file)
        actual = sha256_of(src)
        if actual != source.sha256:
            raise ValueError(f"{source.file}: sha256 {actual}, expected {source.sha256}")
        out = out_dir / music_name(music_id)
        shutil.copyfile(src, out)
        print(f"copied {out.name} from {source.file}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--packs", type=Path, required=True, help="folder holding the unzipped packs and the OGGs")
    args = parser.parse_args(argv)
    if not args.packs.is_dir():
        print(f"--packs {args.packs} is not a folder", file=sys.stderr)
        return 2
    try:
        import_sfx(args.packs, SFX_DIR)
        import_music(args.packs, MUSIC_DIR)
    except (FileNotFoundError, RuntimeError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    print(f"{len(SFX_SOURCES)} SFX and {len(MUSIC_SOURCES)} music tracks imported")
    return 0


if __name__ == "__main__":
    sys.exit(main())
