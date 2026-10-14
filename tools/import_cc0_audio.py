"""Import DEFECTOR's CC0 sounds and music (Story 8.1).

Reads files from unzipped CC0 packs, writes the combat SFX into
game/assets/audio/sfx/ and the music tracks into game/assets/audio/music/.
Stdlib only, plus `ffmpeg` on the PATH.

SFX: each source is decoded, downmixed to mono at 44.1 kHz, optionally trimmed
to its first `trim_s` seconds (then a 5 ms fade-in and a `fade_out_s` fade-out
at its end), and peak-normalised to -1 dBFS in two passes (pass 1 measures the
peak with `astats`, pass 2 applies the gain), written as 16-bit PCM
`sfx_<id>.wav`. Music: SHA-256 checked, then either copied byte-for-byte to
`music_<id>.ogg` or, for the per-level tracks (playtest pt7-i), transcoded to
OGG Vorbis at quality MUSIC_QUALITY (44.1 kHz, stereo, bit-exact flags) so the
long tracks stay small. Set `loop=true` in each looping music `.import` sidecar
after Godot imports it (`game_over` is a one-shot sting and stays
`loop=false`).

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
- MintoDog "Space Boss Battle", https://opengameart.org/content/space-boss-battle
  space_boss_battle_bpm175_0.ogg
  sha256 4fc0898456099db3d9e63bd97450fedc3f9ff0a05cd65a8d363b3f2904415e60
- isaiah658 "Heavenly Loop", https://opengameart.org/content/heavenly-loop
  Heavenly Loop_0.ogg (the epilogue track; playtest pt7-e)
  sha256 a842e9e054019132cacc8fd352e7b31c000ebb51e0b227a2511e1bccb4eb166e
- Joth "Chunky Explosion", https://opengameart.org/content/chunky-explosion
  Chunky Explosion.mp3 (the final Flagship blast, full length; playtest pt7-i)
  sha256 4de53bffac187e59d3f5b43096df2f8fcb4160076b65b71a67074947950e025f
- Kistol "Game Over", https://opengameart.org/content/game-over
  Game Over_1.ogg (the game-over sting; playtest pt7-g)
  sha256 eb16aeb17fed5b13575702e082b54db00b296f6f4f2e9ee89c63aca895bc085e
- EZduzziteh "Explosions", https://opengameart.org/content/explosions-4
  explosion3.ogg (the medium blasts; playtest pt7-i)
  sha256 ffacf6f1f6cc8deb364cec27b1b0abcb5191d8c6b4f5dfa5b58b27aef9f75b23
- Holizna "Retro Wave" collection, https://opengameart.org/content/retro-wave-collection
  retro_wave_1.zip, file "02 HoliznaCC0 - Retro Soundtrack.ogg" (Level 1)
  sha256 of that file 2c336e7d0fa1993749a8d0fc656b07fab7e14284b2ac5234408eceb5f9eeae6b
- G_P "synthwave", https://opengameart.org/content/synthwave-1
  synth_5.mp3 (Level 2)
  sha256 5c36241db12e49600052588321851625a7678affebce3bd0763b0739ae789cf1
- tricksntraps "T & T Free Cyberpunk Pack",
  https://opengameart.org/content/t-t-free-cyberpunk-pack
  Anti Matter Magic.ogg (Level 3)
  sha256 7b19b04738264ef5e1c9df4d82af4a34192c6657ede915b4610d693b3388efe7
- AntumDeluge "Fire Crackling", https://opengameart.org/content/fire-crackling
  fire-1_0.ogg (the download name of fire-1.ogg; a layer of `tarek_burn`, playtest pt7-j)
  sha256 f922929805bc6afdf0a35727fa3998033db544c1b6f62ed3aeab94341ed6ddeb
- Spring Spring "Various Sound Effects", https://opengameart.org/content/various-sound-effects-0
  dull_explosion.wav (a layer of `tarek_burn`, playtest pt7-j)
  sha256 f79f07a733eb27822fb4567318e38b150a482d340bdabad7a30c099815109588

Layered SFX (playtest pt7-j): `tarek_burn` (Tarek's burning fall) mixes several
sources (LAYERED_SOURCES: each layer at its volume, summed without normalising;
a layer may be pitched with `rate`, asetrate then resampled back to 44.1 kHz,
and delayed with `delay_s`, adelay), then an optional echo (empty for none), a
trim and a fade-out, and is peak-normalised like any other SFX. Since playtest
pt7-i, `explosion_boss_death` is Joth's file alone, not layered.

Download the files, unzip each archive into its own empty folder under one
packs folder, put the loose OGGs and MP3s (and the Retro Soundtrack OGG from
retro_wave_1.zip) in that packs folder too, then run from the repo
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
# libvorbis VBR quality for transcoded music (about 128 kbps stereo).
MUSIC_QUALITY = 4
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
    """One input of a layered SFX: its pack, its file name, its volume (linear),
    its playback rate (pitch and speed; 1.0 leaves it as is) and its delay."""

    pack: str
    file: str
    volume: float
    rate: float = 1.0
    delay_s: float = 0.0


@dataclass(frozen=True)
class LayeredSfxSource:
    """A layered SFX: the layers summed (no normalising), then `aecho` with
    `echo` (its in_gain:out_gain:delays:decays arguments; empty for none),
    trimmed to `length_s` with a `fade_out_s` fade-out at its end."""

    layers: tuple[Layer, ...]
    echo: str
    length_s: float
    fade_out_s: float


@dataclass(frozen=True)
class MusicSource:
    """One music track: its file name, the SHA-256 of the downloaded file and
    whether it is transcoded (True) or copied byte-for-byte (False)."""

    file: str
    sha256: str
    transcode: bool = False


SCI_FI = "Kenney Sci-Fi Sounds"
INTERFACE = "Kenney Interface Sounds"
JOTH = 'Joth "Chunky Explosion"'
EZDUZZITEH = 'EZduzziteh "Explosions"'
ANTUM_FIRE = 'AntumDeluge "Fire Crackling"'
SPRING_SFX = 'Spring Spring "Various Sound Effects"'

# Registry id -> source. The game writes `sfx_<id>.wav`.
SFX_SOURCES: dict[str, SfxSource] = {
    "laser_zap": SfxSource(SCI_FI, "laserSmall_001.ogg"),
    "missile_launch": SfxSource(SCI_FI, "thrusterFire_003.ogg", trim_s=0.55, fade_out_s=0.3),
    "barrage_whoosh": SfxSource(SCI_FI, "thrusterFire_001.ogg", trim_s=0.30, fade_out_s=0.2),
    "explosion_small": SfxSource(SCI_FI, "explosionCrunch_000.ogg"),
    "explosion_medium": SfxSource(SCI_FI, "explosionCrunch_001.ogg"),
    "explosion_large": SfxSource(SCI_FI, "explosionCrunch_004.ogg"),
    "explosion_mid": SfxSource(EZDUZZITEH, "explosion3.ogg"),
    "explosion_boss_death": SfxSource(JOTH, "Chunky Explosion.mp3"),
    "player_hit": SfxSource(SCI_FI, "impactMetal_002.ogg"),
    "player_death": SfxSource(SCI_FI, "explosionCrunch_003.ogg"),
    "shield_on": SfxSource(SCI_FI, "forceField_000.ogg"),
    "energy_pickup": SfxSource(INTERFACE, "glass_001.ogg"),
    "needle_fire": SfxSource(SCI_FI, "laserLarge_000.ogg", trim_s=0.45, fade_out_s=0.2),
    "ability_denied": SfxSource(INTERFACE, "error_007.ogg"),
}

# Registry id -> layered source (playtest pt7-j). Also written as `sfx_<id>.wav`.
LAYERED_SOURCES: dict[str, LayeredSfxSource] = {
    # Tarek's burning fall (playtest pt7-j): a falling thruster roar pitched
    # down, the fire crackle, and a dull distant crash 2.2 s in.
    "tarek_burn": LayeredSfxSource(
        layers=(
            Layer(SCI_FI, "thrusterFire_000.ogg", 0.8, rate=0.7),
            Layer(ANTUM_FIRE, "fire-1_0.ogg", 1.0),
            Layer(SPRING_SFX, "dull_explosion.wav", 0.6, delay_s=2.2),
        ),
        echo="",
        length_s=4.6,
        fade_out_s=1.2,
    ),
}

# Music id -> source. The game writes it to `music_<id>.ogg`.
MUSIC_SOURCES: dict[str, MusicSource] = {
    "level_1": MusicSource(
        "02 HoliznaCC0 - Retro Soundtrack.ogg",
        "2c336e7d0fa1993749a8d0fc656b07fab7e14284b2ac5234408eceb5f9eeae6b",
        transcode=True,
    ),
    "level_2": MusicSource(
        "synth_5.mp3",
        "5c36241db12e49600052588321851625a7678affebce3bd0763b0739ae789cf1",
        transcode=True,
    ),
    "level_3": MusicSource(
        "Anti Matter Magic.ogg",
        "7b19b04738264ef5e1c9df4d82af4a34192c6657ede915b4610d693b3388efe7",
        transcode=True,
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
        chain = f"[{i}:a]aformat=sample_fmts=flt:sample_rates={RATE}:channel_layouts=mono"
        if layer.rate != 1.0:
            chain += f",asetrate={RATE * layer.rate:g},aresample={RATE}"
        if layer.delay_s > 0.0:
            chain += f",adelay={round(layer.delay_s * 1000)}:all=1"
        parts.append(f"{chain},volume={layer.volume:g}[l{i}]")
        labels += f"[l{i}]"
    start = source.length_s - source.fade_out_s
    echo = f"aecho={source.echo}," if source.echo else ""
    parts.append(
        f"{labels}amix=inputs={len(source.layers)}:duration=longest:normalize=0,"
        f"{echo}atrim=end={source.length_s:g},"
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


def transcode_args(src: Path, out: Path) -> list[str]:
    """A per-level track: decoded and re-encoded as stereo 44.1 kHz OGG Vorbis at
    MUSIC_QUALITY, with no metadata and bit-exact flags."""
    return [
        "ffmpeg", "-hide_banner", "-nostats", "-y", "-i", str(src), "-vn",
        "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
        "-ac", "2", "-ar", str(RATE), "-c:a", "libvorbis", "-q:a", str(MUSIC_QUALITY), str(out),
    ]


def import_music(packs: Path, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    for music_id, source in MUSIC_SOURCES.items():
        src = find_file(packs, source.file)
        actual = sha256_of(src)
        if actual != source.sha256:
            raise ValueError(f"{source.file}: sha256 {actual}, expected {source.sha256}")
        out = out_dir / music_name(music_id)
        if source.transcode:
            _run(transcode_args(src, out))
            print(f"transcoded {out.name} from {source.file} (q{MUSIC_QUALITY})")
        else:
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
