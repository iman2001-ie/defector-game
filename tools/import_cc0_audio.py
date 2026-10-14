"""Import DEFECTOR's CC0 sounds and music (Story 8.1).

Reads files from unzipped CC0 packs, writes the combat SFX into
game/assets/audio/sfx/ and copies the four music tracks into
game/assets/audio/music/. Stdlib only, plus `ffmpeg` on the PATH.

SFX: each source is decoded, downmixed to mono at 44.1 kHz, optionally trimmed
to its first `trim_s` seconds (then a 5 ms fade-in and a `fade_out_s` fade-out
at its end), and peak-normalised to -1 dBFS in two passes (pass 1 measures the
peak with `astats`, pass 2 applies the gain), written as 16-bit PCM
`sfx_<id>.wav`. Music: copied byte-for-byte to `music_<id>.ogg` after a SHA-256
check. Set `loop=true` in each looping music `.import` sidecar after Godot
imports it (`game_over` is a one-shot sting and stays `loop=false`).

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
- Joth "Chunky Explosion", https://opengameart.org/content/chunky-explosion
  Chunky Explosion.mp3 (the big explosions; playtest pt7-g)
  sha256 4de53bffac187e59d3f5b43096df2f8fcb4160076b65b71a67074947950e025f
- Kistol "Game Over", https://opengameart.org/content/game-over
  Game Over_1.ogg (the game-over sting; playtest pt7-g)
  sha256 eb16aeb17fed5b13575702e082b54db00b296f6f4f2e9ee89c63aca895bc085e

Layered SFX (playtest pt7-g): `explosion_boss_death` mixes several sources
(LAYERED_SOURCES: each layer at its volume, summed without normalising), then
an echo, a trim and a fade-out, and is peak-normalised like any other SFX.

Download the files, unzip each archive into its own empty folder under one
packs folder, put the loose OGGs and the MP3 in that packs folder too, then run from the repo
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
class Layer:
    """One input of a layered SFX: its pack, its file name and its volume (linear)."""

    pack: str
    file: str
    volume: float


@dataclass(frozen=True)
class LayeredSfxSource:
    """A layered SFX: the layers summed (no normalising), then `aecho` with
    `echo` (its in_gain:out_gain:delays:decays arguments), trimmed to
    `length_s` with a `fade_out_s` fade-out at its end."""

    layers: tuple[Layer, ...]
    echo: str
    length_s: float
    fade_out_s: float


@dataclass(frozen=True)
class MusicSource:
    """One music track: its file name and the SHA-256 of the downloaded file."""

    file: str
    sha256: str


SCI_FI = "Kenney Sci-Fi Sounds"
INTERFACE = "Kenney Interface Sounds"
JOTH = 'Joth "Chunky Explosion"'

# Registry id -> source. The game writes `sfx_<id>.wav`.
SFX_SOURCES: dict[str, SfxSource] = {
    "laser_zap": SfxSource(SCI_FI, "laserSmall_001.ogg"),
    "missile_launch": SfxSource(SCI_FI, "thrusterFire_003.ogg", trim_s=0.55, fade_out_s=0.3),
    "barrage_whoosh": SfxSource(SCI_FI, "thrusterFire_001.ogg", trim_s=0.30, fade_out_s=0.2),
    "explosion_small": SfxSource(SCI_FI, "explosionCrunch_000.ogg"),
    "explosion_medium": SfxSource(SCI_FI, "explosionCrunch_001.ogg"),
    "explosion_large": SfxSource(SCI_FI, "explosionCrunch_004.ogg"),
    "explosion_boss_part": SfxSource(SCI_FI, "lowFrequency_explosion_001.ogg"),
    "explosion_big": SfxSource(JOTH, "Chunky Explosion.mp3", trim_s=3.0, fade_out_s=1.0),
    "player_hit": SfxSource(SCI_FI, "impactMetal_002.ogg"),
    "player_death": SfxSource(SCI_FI, "explosionCrunch_003.ogg"),
    "shield_on": SfxSource(SCI_FI, "forceField_000.ogg"),
    "energy_pickup": SfxSource(INTERFACE, "glass_001.ogg"),
    "needle_fire": SfxSource(SCI_FI, "laserLarge_000.ogg", trim_s=0.45, fade_out_s=0.2),
    "ability_denied": SfxSource(INTERFACE, "error_007.ogg"),
}

# Registry id -> layered source (playtest pt7-g). Also written as `sfx_<id>.wav`.
LAYERED_SOURCES: dict[str, LayeredSfxSource] = {
    "explosion_boss_death": LayeredSfxSource(
        layers=(
            Layer(JOTH, "Chunky Explosion.mp3", 1.0),
            Layer(SCI_FI, "explosionCrunch_004.ogg", 0.7),
            Layer(SCI_FI, "lowFrequency_explosion_000.ogg", 0.8),
        ),
        echo="0.8:0.6:120|260:0.35|0.22",
        length_s=4.5,
        fade_out_s=1.3,
    ),
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
    "game_over": MusicSource(
        "Game Over_1.ogg",
        "eb16aeb17fed5b13575702e082b54db00b296f6f4f2e9ee89c63aca895bc085e",
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


def layered_graph(source: LayeredSfxSource) -> str:
    """The filter graph of a layered SFX up to (not including) the final label:
    each input formatted like filter_chain and scaled by its volume, summed by
    amix (normalize=0), then the echo, the trim and the fade-out."""
    parts = []
    labels = ""
    for i, layer in enumerate(source.layers):
        parts.append(
            f"[{i}:a]aformat=sample_fmts=flt:sample_rates={RATE}:channel_layouts=mono,volume={layer.volume:g}[l{i}]"
        )
        labels += f"[l{i}]"
    start = source.length_s - source.fade_out_s
    parts.append(
        f"{labels}amix=inputs={len(source.layers)}:duration=longest:normalize=0,"
        f"aecho={source.echo},atrim=end={source.length_s:g},"
        f"afade=t=out:st={start:g}:d={source.fade_out_s:g}"
    )
    return ";".join(parts)


def _layered_inputs(srcs: list[Path]) -> list[str]:
    args: list[str] = []
    for src in srcs:
        args += ["-i", str(src)]
    return args


def layered_measure_args(srcs: list[Path], source: LayeredSfxSource) -> list[str]:
    """Pass 1 for a layered SFX: the graph plus astats, printing the overall peak."""
    graph = layered_graph(source) + ",astats=measure_perchannel=none:measure_overall=Peak_level[out]"
    return ["ffmpeg", "-hide_banner", "-nostats", *_layered_inputs(srcs), "-filter_complex", graph,
            "-map", "[out]", "-f", "null", "-"]


def layered_render_args(srcs: list[Path], out: Path, source: LayeredSfxSource, gain: float) -> list[str]:
    """Pass 2 for a layered SFX: the graph plus the gain, as bit-exact 16-bit mono PCM."""
    graph = layered_graph(source) + f",volume={gain:.6f}dB[out]"
    return [
        "ffmpeg", "-hide_banner", "-nostats", "-y", *_layered_inputs(srcs), "-filter_complex", graph,
        "-map", "[out]", "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
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
    for sfx_id, layered in LAYERED_SOURCES.items():
        srcs = [find_file(packs, layer.file) for layer in layered.layers]
        peak = parse_peak_db(_run(layered_measure_args(srcs, layered)))
        gain = gain_db(peak)
        out = out_dir / sfx_name(sfx_id)
        _run(layered_render_args(srcs, out, layered, gain))
        print(f"wrote {out.name} from {len(srcs)} layers (peak {peak:.2f} dB, gain {gain:+.2f} dB)")


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
    print(f"{len(SFX_SOURCES) + len(LAYERED_SOURCES)} SFX and {len(MUSIC_SOURCES)} music tracks imported")
    return 0


if __name__ == "__main__":
    sys.exit(main())
