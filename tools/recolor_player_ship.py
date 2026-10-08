"""Bake the coalition-recoloured player hull (Story 4.0).

Stdlib only (zlib, struct, colorsys), deterministic: the same input PNG always
gives identical decoded pixels, and identical PNG bytes with the same zlib build.
Reads Kenney Space Shooter Redux `PNG/playerShip1_blue.png` (CC0) and writes
game/assets/sprites/player/playerShip1_coalition.png (or the optional output
path given as the second argument).

Expected source SHA-256 (Kenney Space Shooter Redux PNG/playerShip1_blue.png):
  648ec1635979fb867d08bfd0c56f011d6559dd953a13c73109c6186a3069f7ee
Committed output SHA-256 (as produced on the Story 4.0 toolchain):
  bf3a0b4c6bc8904feef380959c53f4405c11f527a24e43cb6887ee8e535fc634

Per pixel, in HSV: H becomes the hue of `coalition` #22E6FF; S becomes
min(1, S * S_c / S_b) and V becomes min(1, V * V_c / V_b), where _c is coalition
and _b is the reference body colour (the most common fully opaque RGB in the
source, #36BBF5 for playerShip1_blue). Alpha is unchanged, so the body maps to
#22E6FF, greys and whites stay near-neutral and outlines stay dark.

Only 8-bit RGBA, non-interlaced PNGs are accepted; anything else exits non-zero.

Run from the repo root:  uv run python tools/recolor_player_ship.py <source PNG> [<output PNG>]
"""

from __future__ import annotations

import colorsys
import struct
import sys
import zlib
from collections import Counter
from pathlib import Path

COALITION_RGB: tuple[int, int, int] = (0x22, 0xE6, 0xFF)
OUT_PATH = (
    Path(__file__).resolve().parent.parent
    / "game" / "assets" / "sprites" / "player" / "playerShip1_coalition.png"
)
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
COLOR_TYPE_RGBA = 6


class PngFormatError(ValueError):
    """The PNG is malformed or not 8-bit RGBA non-interlaced."""


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def read_rgba(data: bytes) -> tuple[int, int, bytearray]:
    """Decode an 8-bit RGBA non-interlaced PNG into (width, height, RGBA bytes)."""
    if not data.startswith(PNG_SIGNATURE):
        raise PngFormatError("not a PNG file")
    pos = len(PNG_SIGNATURE)
    header: tuple[int, ...] | None = None
    idat = bytearray()
    while pos + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if len(body) != length:
            raise PngFormatError("truncated chunk")
        pos += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
    if header is None:
        raise PngFormatError("missing IHDR")
    width, height, depth, color_type, _compression, _filter, interlace = header
    if depth != 8 or color_type != COLOR_TYPE_RGBA:
        raise PngFormatError(
            "need 8-bit RGBA (got bit depth %d, colour type %d)" % (depth, color_type))
    if interlace != 0:
        raise PngFormatError("interlaced PNGs are not supported")
    raw = zlib.decompress(bytes(idat))
    stride = width * 4
    if len(raw) != height * (stride + 1):
        raise PngFormatError("pixel data size does not match the header")
    out = bytearray(height * stride)
    prev = bytearray(stride)
    for y in range(height):
        ftype = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            left = line[i - 4] if i >= 4 else 0
            up = prev[i]
            up_left = prev[i - 4] if i >= 4 else 0
            if ftype == 0:
                pass
            elif ftype == 1:
                line[i] = (line[i] + left) & 0xFF
            elif ftype == 2:
                line[i] = (line[i] + up) & 0xFF
            elif ftype == 3:
                line[i] = (line[i] + ((left + up) >> 1)) & 0xFF
            elif ftype == 4:
                line[i] = (line[i] + _paeth(left, up, up_left)) & 0xFF
            else:
                raise PngFormatError("unknown filter type %d" % ftype)
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, out


def _chunk(kind: bytes, body: bytes) -> bytes:
    crc = zlib.crc32(kind + body) & 0xFFFFFFFF
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", crc)


def write_rgba(width: int, height: int, pixels: bytes) -> bytes:
    """Encode RGBA bytes as an 8-bit RGBA PNG (filter 0, fixed zlib level)."""
    stride = width * 4
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw += pixels[y * stride:(y + 1) * stride]
    ihdr = struct.pack(">IIBBBBB", width, height, 8, COLOR_TYPE_RGBA, 0, 0, 0)
    return (PNG_SIGNATURE + _chunk(b"IHDR", ihdr)
            + _chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + _chunk(b"IEND", b""))


def body_colour(pixels: bytes) -> tuple[int, int, int]:
    """The most common fully opaque RGB (ties: the smallest RGB value)."""
    counts: Counter[tuple[int, int, int]] = Counter()
    for i in range(0, len(pixels), 4):
        if pixels[i + 3] == 255:
            counts[(pixels[i], pixels[i + 1], pixels[i + 2])] += 1
    if not counts:
        raise PngFormatError("no fully opaque pixel to use as the body colour")
    return min(counts.items(), key=lambda kv: (-kv[1], kv[0]))[0]


def _hsv(rgb: tuple[int, int, int]) -> tuple[float, float, float]:
    return colorsys.rgb_to_hsv(rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0)


def recolor(pixels: bytes, body: tuple[int, int, int],
            target: tuple[int, int, int] = COALITION_RGB) -> bytearray:
    """Map every pixel's hue to `target`'s and scale S and V by target/body."""
    h_c, s_c, v_c = _hsv(target)
    _h_b, s_b, v_b = _hsv(body)
    s_ratio = s_c / s_b if s_b > 0.0 else 1.0
    v_ratio = v_c / v_b if v_b > 0.0 else 1.0
    out = bytearray(pixels)
    cache: dict[tuple[int, int, int], tuple[int, int, int]] = {}
    for i in range(0, len(pixels), 4):
        key = (pixels[i], pixels[i + 1], pixels[i + 2])
        mapped = cache.get(key)
        if mapped is None:
            _h, s, v = _hsv(key)
            r, g, b = colorsys.hsv_to_rgb(h_c, min(1.0, s * s_ratio), min(1.0, v * v_ratio))
            mapped = (round(r * 255.0), round(g * 255.0), round(b * 255.0))
            cache[key] = mapped
        out[i:i + 3] = bytes(mapped)
    return out


def recolor_png_bytes(data: bytes) -> bytes:
    """Source PNG bytes -> recoloured PNG bytes. Raises PngFormatError."""
    width, height, pixels = read_rgba(data)
    return write_rgba(width, height, recolor(pixels, body_colour(pixels)))


def main(argv: list[str]) -> int:
    if len(argv) not in (2, 3):
        sys.stderr.write("usage: recolor_player_ship.py <source PNG> [<output PNG>]\n")
        return 2
    out_path = Path(argv[2]) if len(argv) == 3 else OUT_PATH
    try:
        result = recolor_png_bytes(Path(argv[1]).read_bytes())
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_bytes(result)
    except (OSError, PngFormatError, zlib.error) as err:
        sys.stderr.write("recolor_player_ship: %s\n" % err)
        return 1
    sys.stdout.write("wrote %s (%d bytes)\n" % (out_path.name, len(result)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
