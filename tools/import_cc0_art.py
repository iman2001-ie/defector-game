"""Import DEFECTOR's CC0 Kenney art (Story 8.2).

Reads sprites, backgrounds and the Kenney Future font from the unzipped Kenney
Space Shooter Redux and Space Shooter Extension packs, recolours them to the
DESIGN.md palette and writes them under game/assets/ (see ROWS). Stdlib only
(zlib, struct, colorsys) and deterministic: re-running on the same packs gives
byte-identical files with the same zlib build. The PNG decoder, encoder and the
HSV recolour are reused from tools/recolor_player_ship.py (the player hull,
playerShip1_coalition.png, is never regenerated here).

Sources (both CC0 1.0 on their OpenGameArt page; Kenney, https://kenney.nl):

- Kenney "Space Shooter Redux", https://opengameart.org/content/space-shooter-redux
  https://opengameart.org/sites/default/files/SpaceShooterRedux.zip
  sha256 d44a371a8fa1eb5d61a4fed3677954590aa015a78d2afb5f97924cfe02e3f700
- Kenney "Space Shooter Extension (250+ sprites)",
  https://opengameart.org/content/space-shooter-extension-250
  https://opengameart.org/sites/default/files/kenney_spaceShooterExtension.zip
  sha256 77efd54b343bbd123af8cc7f534446706731b9cf5a34f38d8fcc54e7245f9c91

Ops (applied in order to the row's first source; colours are 8-bit RGB):

- recolor(target, value=1.0): the recolor_player_ship HSV map (H becomes the
  target's hue, S and V scale by target / reference, clamped to 1), where the
  reference is the most common fully opaque RGB with HSV saturation >= 0.25
  (ties: the smallest RGB); with no such pixel it falls back to tint(target).
  Then every RGB channel is multiplied by `value` (HSV V x value).
- tint(target): RGB = target x the pixel's luminance (Rec. 709, 0..1).
- rot180: the image turned half a turn.
- overlay(n): source n alpha-composited over the image ("over"), its top-left
  on the image's top-left and clipped to the image (Kenney's
  playerShip2_damage3.png is one row taller than playerShip2_blue.png).
- rim(rgb, px=2): every pixel with alpha > 0 that has transparency (alpha 0, or
  outside the image) within `px` pixels up, left or up-left lerps 70% toward
  `rgb`, a rim light from the upper left.
- background(target): RGB = target x (pixel luminance / mean luminance of the
  image), every channel clamped to <= 127 so it stays under the glow
  threshold (render.glow.hdr_threshold 0.55); alpha 255.
- copy: the source copied byte-for-byte (no decode).

8-bit RGBA and RGB non-interlaced PNGs are decoded; every PNG is written as
8-bit RGBA.

Download both zips, unzip each into its own empty folder, then run from the
repo root:

    uv run python tools/import_cc0_art.py --redux <redux folder> --extension <extension folder>

A missing source file exits 2 naming it, before anything is written. Then run
Godot's headless --import.
"""

from __future__ import annotations

import argparse
import colorsys
import struct
import sys
import zlib
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import recolor_player_ship as png  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS_DIR = REPO_ROOT / "game" / "assets"

REDUX = "redux"
EXTENSION = "extension"
PACK_NAMES = {REDUX: "Kenney Space Shooter Redux", EXTENSION: "Kenney Space Shooter Extension"}

COLOR_TYPE_RGB = 2
REFERENCE_MIN_S = 0.25
RIM_LERP = 0.7
BACKGROUND_MAX = 127
LUMA = (0.2126, 0.7152, 0.0722)

ENEMY = (0xFF, 0x2B, 0xD6)
HUNTER = (0xFF, 0x8A, 0x1F)
COALITION = (0x22, 0xE6, 0xFF)
HAZARD = (0x7A, 0x6E, 0x62)
HAZARD_RIM = (0xC9, 0xD8, 0xE8)
SPACE_1 = (0x0B, 0x12, 0x26)
SPACE_2 = (0x14, 0x0E, 0x26)


@dataclass(frozen=True)
class Source:
    """One file in an unzipped pack: the pack key and its path inside the pack."""

    pack: str
    path: str


@dataclass(frozen=True)
class Op:
    """One processing step. `rgb` is the target colour, `index` the overlay source."""

    name: str
    rgb: tuple[int, int, int] | None = None
    value: float = 1.0
    px: int = 2
    index: int = 1


@dataclass(frozen=True)
class Row:
    """One output file under game/assets/, its sources and its ops."""

    out: str
    sources: tuple[Source, ...]
    ops: tuple[Op, ...]


def _redux(path: str) -> Source:
    return Source(REDUX, path)


def _ext(path: str) -> Source:
    return Source(EXTENSION, path)


def recolor_op(rgb: tuple[int, int, int], value: float = 1.0) -> Op:
    return Op("recolor", rgb=rgb, value=value)


def tint_op(rgb: tuple[int, int, int]) -> Op:
    return Op("tint", rgb=rgb)


def rim_op(rgb: tuple[int, int, int], px: int = 2) -> Op:
    return Op("rim", rgb=rgb, px=px)


def background_op(rgb: tuple[int, int, int]) -> Op:
    return Op("background", rgb=rgb)


ROT180 = Op("rot180")
OVERLAY = Op("overlay", index=1)
COPY = Op("copy")

ROWS: tuple[Row, ...] = (
    Row("sprites/enemies/enemy_wasp.png", (_redux("PNG/Enemies/enemyRed1.png"),), (recolor_op(ENEMY),)),
    Row("sprites/enemies/enemy_hunter_wasp.png", (_redux("PNG/Enemies/enemyRed1.png"),), (recolor_op(HUNTER),)),
    Row("sprites/enemies/enemy_lancer.png", (_redux("PNG/Enemies/enemyRed2.png"),), (recolor_op(ENEMY),)),
    Row("sprites/enemies/enemy_needle.png", (_ext("PNG/Sprites/Ships/spaceShips_006.png"),), (recolor_op(ENEMY),)),
    Row("sprites/enemies/enemy_bastion.png", (_ext("PNG/Sprites/Ships/spaceShips_007.png"),), (recolor_op(ENEMY),)),
    Row("sprites/enemies/enemy_maul.png", (_ext("PNG/Sprites/Ships/spaceShips_004.png"),), (recolor_op(ENEMY),)),
    Row("sprites/allies/ally_coalition.png", (_redux("PNG/playerShip2_blue.png"),), (recolor_op(COALITION),)),
    Row(
        "sprites/allies/ally_damaged.png",
        (_redux("PNG/playerShip2_blue.png"), _redux("PNG/Damage/playerShip2_damage3.png")),
        (OVERLAY, recolor_op(COALITION, 0.45)),
    ),
    Row(
        "sprites/allies/convoy_cargo.png",
        (_ext("PNG/Sprites/Ships/spaceShips_005.png"),),
        (ROT180, recolor_op(COALITION, 0.9)),
    ),
    Row("sprites/boss/flagship_turret.png", (_redux("PNG/Parts/turretBase_big.png"),), (tint_op(ENEMY),)),
    Row("sprites/boss/flagship_core.png", (_redux("PNG/ufoRed.png"),), (recolor_op(ENEMY),)),
    Row(
        "sprites/asteroids/asteroid_large.png",
        (_redux("PNG/Meteors/meteorBrown_big1.png"),),
        (recolor_op(HAZARD), rim_op(HAZARD_RIM)),
    ),
    Row(
        "sprites/asteroids/asteroid_medium.png",
        (_redux("PNG/Meteors/meteorBrown_med1.png"),),
        (recolor_op(HAZARD), rim_op(HAZARD_RIM)),
    ),
    Row(
        "sprites/asteroids/asteroid_small.png",
        (_redux("PNG/Meteors/meteorBrown_small1.png"),),
        (recolor_op(HAZARD), rim_op(HAZARD_RIM)),
    ),
    Row("backgrounds/space_1.png", (_redux("Backgrounds/blue.png"),), (background_op(SPACE_1),)),
    Row("backgrounds/space_2.png", (_redux("Backgrounds/darkPurple.png"),), (background_op(SPACE_2),)),
    Row("fonts/kenvector_future.ttf", (_redux("Bonus/kenvector_future.ttf"),), (COPY,)),
)


class Image:
    """A decoded RGBA image: width, height and row-major RGBA bytes."""

    __slots__ = ("width", "height", "pixels")

    def __init__(self, width: int, height: int, pixels: bytearray) -> None:
        if len(pixels) != width * height * 4:
            raise png.PngFormatError("pixel buffer does not match %dx%d" % (width, height))
        self.width = width
        self.height = height
        self.pixels = pixels

    def copy(self) -> Image:
        return Image(self.width, self.height, bytearray(self.pixels))


# --- PNG decode (RGBA via recolor_player_ship.read_rgba, RGB here) ---------------


def _header(data: bytes) -> tuple[int, ...]:
    if not data.startswith(png.PNG_SIGNATURE):
        raise png.PngFormatError("not a PNG file")
    pos = len(png.PNG_SIGNATURE)
    length, kind = struct.unpack(">I4s", data[pos:pos + 8])
    if kind != b"IHDR" or length != 13:
        raise png.PngFormatError("missing IHDR")
    return struct.unpack(">IIBBBBB", data[pos + 8:pos + 21])


def _read_rgb(data: bytes) -> Image:
    """Decode an 8-bit RGB non-interlaced PNG into RGBA (alpha 255)."""
    width, height, depth, color_type, _c, _f, interlace = _header(data)
    if depth != 8 or color_type != COLOR_TYPE_RGB or interlace != 0:
        raise png.PngFormatError("need 8-bit RGB non-interlaced")
    pos = len(png.PNG_SIGNATURE)
    idat = bytearray()
    while pos + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        if kind == b"IDAT":
            idat += data[pos + 8:pos + 8 + length]
        elif kind == b"IEND":
            break
        pos += 12 + length
    raw = zlib.decompress(bytes(idat))
    stride = width * 3
    if len(raw) != height * (stride + 1):
        raise png.PngFormatError("pixel data size does not match the header")
    out = bytearray(width * height * 4)
    prev = bytearray(stride)
    for y in range(height):
        ftype = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            left = line[i - 3] if i >= 3 else 0
            up = prev[i]
            up_left = prev[i - 3] if i >= 3 else 0
            if ftype == 0:
                pass
            elif ftype == 1:
                line[i] = (line[i] + left) & 0xFF
            elif ftype == 2:
                line[i] = (line[i] + up) & 0xFF
            elif ftype == 3:
                line[i] = (line[i] + ((left + up) >> 1)) & 0xFF
            elif ftype == 4:
                line[i] = (line[i] + png._paeth(left, up, up_left)) & 0xFF
            else:
                raise png.PngFormatError("unknown filter type %d" % ftype)
        for x in range(width):
            o = (y * width + x) * 4
            out[o:o + 3] = line[x * 3:x * 3 + 3]
            out[o + 3] = 255
        prev = line
    return Image(width, height, out)


def read_png(data: bytes) -> Image:
    """Decode an 8-bit RGBA or RGB non-interlaced PNG into an RGBA Image."""
    color_type = _header(data)[3]
    if color_type == COLOR_TYPE_RGB:
        return _read_rgb(data)
    width, height, pixels = png.read_rgba(data)
    return Image(width, height, pixels)


def write_png(image: Image) -> bytes:
    return png.write_rgba(image.width, image.height, bytes(image.pixels))


# --- ops ------------------------------------------------------------------------


def luminance(r: int, g: int, b: int) -> float:
    """Rec. 709 relative luminance of an 8-bit RGB, 0..1."""
    return (LUMA[0] * r + LUMA[1] * g + LUMA[2] * b) / 255.0


def reference_colour(image: Image, min_s: float = REFERENCE_MIN_S) -> tuple[int, int, int] | None:
    """The most common fully opaque RGB with saturation >= min_s (ties: the smallest RGB)."""
    counts: Counter[tuple[int, int, int]] = Counter()
    px = image.pixels
    for i in range(0, len(px), 4):
        if px[i + 3] == 255:
            counts[(px[i], px[i + 1], px[i + 2])] += 1
    saturated = [
        (rgb, n) for rgb, n in counts.items()
        if colorsys.rgb_to_hsv(rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0)[1] >= min_s
    ]
    if not saturated:
        return None
    return min(saturated, key=lambda kv: (-kv[1], kv[0]))[0]


def tint(image: Image, target: tuple[int, int, int]) -> Image:
    out = image.copy()
    px = out.pixels
    for i in range(0, len(px), 4):
        lum = luminance(px[i], px[i + 1], px[i + 2])
        px[i] = round(target[0] * lum)
        px[i + 1] = round(target[1] * lum)
        px[i + 2] = round(target[2] * lum)
    return out


def recolor(image: Image, target: tuple[int, int, int], value: float = 1.0) -> Image:
    ref = reference_colour(image)
    if ref is None:
        out = tint(image, target)
    else:
        out = Image(image.width, image.height, png.recolor(image.pixels, ref, target))
    if value != 1.0:
        px = out.pixels
        for i in range(0, len(px), 4):
            px[i] = min(255, round(px[i] * value))
            px[i + 1] = min(255, round(px[i + 1] * value))
            px[i + 2] = min(255, round(px[i + 2] * value))
    return out


def rot180(image: Image) -> Image:
    px = image.pixels
    out = bytearray(len(px))
    count = image.width * image.height
    for p in range(count):
        q = (count - 1 - p) * 4
        out[p * 4:p * 4 + 4] = px[q:q + 4]
    return Image(image.width, image.height, out)


def overlay(base: Image, top: Image) -> Image:
    """`top` alpha-composited over `base` (Porter-Duff over), top-left aligned, clipped to `base`."""
    out = base.copy()
    bp = out.pixels
    tp = top.pixels
    for y in range(min(base.height, top.height)):
        for x in range(min(base.width, top.width)):
            t = (y * top.width + x) * 4
            b = (y * base.width + x) * 4
            ta = tp[t + 3] / 255.0
            if ta == 0.0:
                continue
            ba = bp[b + 3] / 255.0
            oa = ta + ba * (1.0 - ta)
            for c in range(3):
                bp[b + c] = round((tp[t + c] * ta + bp[b + c] * ba * (1.0 - ta)) / oa)
            bp[b + 3] = round(oa * 255.0)
    return out


def rim(image: Image, rgb: tuple[int, int, int], px: int = 2) -> Image:
    """Lerp 70% toward `rgb` every visible pixel within `px` of transparency up, left or up-left."""
    w, h = image.width, image.height
    src = image.pixels
    out = image.copy()
    op = out.pixels

    def clear(x: int, y: int) -> bool:
        return x < 0 or y < 0 or src[(y * w + x) * 4 + 3] == 0

    for y in range(h):
        for x in range(w):
            i = (y * w + x) * 4
            if src[i + 3] == 0:
                continue
            if any(clear(x - k, y) or clear(x, y - k) or clear(x - k, y - k) for k in range(1, px + 1)):
                for c in range(3):
                    op[i + c] = round(src[i + c] + RIM_LERP * (rgb[c] - src[i + c]))
    return out


def background(image: Image, target: tuple[int, int, int]) -> Image:
    px = image.pixels
    count = image.width * image.height
    lums = [luminance(px[p * 4], px[p * 4 + 1], px[p * 4 + 2]) for p in range(count)]
    mean = sum(lums) / count if count else 0.0
    out = bytearray(len(px))
    for p in range(count):
        factor = lums[p] / mean if mean > 0.0 else 1.0
        for c in range(3):
            out[p * 4 + c] = min(BACKGROUND_MAX, round(target[c] * factor))
        out[p * 4 + 3] = 255
    return Image(image.width, image.height, out)


def apply_op(image: Image, op: Op, extra: list[Image]) -> Image:
    if op.name == "recolor":
        assert op.rgb is not None
        return recolor(image, op.rgb, op.value)
    if op.name == "tint":
        assert op.rgb is not None
        return tint(image, op.rgb)
    if op.name == "rot180":
        return rot180(image)
    if op.name == "overlay":
        return overlay(image, extra[op.index])
    if op.name == "rim":
        assert op.rgb is not None
        return rim(image, op.rgb, op.px)
    if op.name == "background":
        assert op.rgb is not None
        return background(image, op.rgb)
    raise ValueError("unknown op '%s'" % op.name)


def render_row(row: Row, source_bytes: list[bytes]) -> bytes:
    """The output file's bytes for `row`, given the bytes of each of its sources."""
    if row.ops == (COPY,):
        return source_bytes[0]
    images = [read_png(data) for data in source_bytes]
    image = images[0]
    for op in row.ops:
        image = apply_op(image, op, images)
    return write_png(image)


def source_path(source: Source, packs: dict[str, Path]) -> Path:
    return packs[source.pack] / source.path


def missing_sources(packs: dict[str, Path], rows: tuple[Row, ...] = ROWS) -> list[str]:
    """`<pack> <path> (for <out>)` for every source file that is not there."""
    missing: list[str] = []
    for row in rows:
        for source in row.sources:
            if not source_path(source, packs).is_file():
                missing.append("%s %s (for %s)" % (PACK_NAMES[source.pack], source.path, row.out))
    return missing


def import_art(packs: dict[str, Path], out_dir: Path, rows: tuple[Row, ...] = ROWS) -> list[Path]:
    """Render every row in memory, then write them all. Returns the written paths."""
    rendered: list[tuple[Path, bytes]] = []
    for row in rows:
        data = [source_path(s, packs).read_bytes() for s in row.sources]
        rendered.append((out_dir / row.out, render_row(row, data)))
    for path, data in rendered:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return [path for path, _ in rendered]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    parser.add_argument("--redux", type=Path, required=True, help="the unzipped Space Shooter Redux folder")
    parser.add_argument("--extension", type=Path, required=True, help="the unzipped Space Shooter Extension folder")
    parser.add_argument("--out", type=Path, default=ASSETS_DIR, help="output root (default game/assets)")
    args = parser.parse_args(argv)
    packs = {REDUX: args.redux, EXTENSION: args.extension}
    for key, folder in packs.items():
        if not folder.is_dir():
            print("--%s %s is not a folder" % (key, folder), file=sys.stderr)
            return 2
    missing = missing_sources(packs)
    if missing:
        for line in missing:
            print("missing source file: %s" % line, file=sys.stderr)
        return 2
    try:
        written = import_art(packs, args.out)
    except (OSError, png.PngFormatError, zlib.error, ValueError, struct.error) as error:
        print(error, file=sys.stderr)
        return 1
    for path in written:
        print("wrote %s" % path.relative_to(args.out).as_posix())
    print("%d art files imported" % len(written))
    return 0


if __name__ == "__main__":
    sys.exit(main())
