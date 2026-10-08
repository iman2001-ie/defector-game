"""Tests for tools/recolor_player_ship.py (Story 4.0). Stdlib unittest only.

Run from the repo root:  uv run python -m unittest tools/test_recolor_player_ship.py
"""

from __future__ import annotations

import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import recolor_player_ship as tool  # noqa: E402

BODY = (0x36, 0xBB, 0xF5, 255)
GREY = (0x80, 0x80, 0x80, 255)
CLEAR = (0x36, 0xBB, 0xF5, 0)
COALITION = (0x22, 0xE6, 0xFF)


def _png(width: int, height: int, pixels: list[tuple[int, ...]], color_type: int = 6,
         interlace: int = 0) -> bytes:
    """A minimal PNG with filter 0 rows (bit depth 8)."""
    channels = 4 if color_type == 6 else 3
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw += bytes(pixels[y * width + x][:channels])
    ihdr = struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, interlace)
    return (tool.PNG_SIGNATURE + tool._chunk(b"IHDR", ihdr)
            + tool._chunk(b"IDAT", zlib.compress(bytes(raw))) + tool._chunk(b"IEND", b""))


def _source() -> bytes:
    # Two body pixels so #36BBF5 is the most common fully opaque colour.
    return _png(2, 2, [BODY, BODY, GREY, CLEAR])


class RecolorTest(unittest.TestCase):
    def test_body_grey_and_alpha(self) -> None:
        width, height, px = tool.read_rgba(tool.recolor_png_bytes(_source()))
        self.assertEqual((width, height), (2, 2))
        for i, want in enumerate(COALITION):
            self.assertLessEqual(abs(px[i] - want), 1, "body channel %d" % i)
            self.assertLessEqual(abs(px[4 + i] - want), 1, "second body channel %d" % i)
        grey = px[8:11]
        self.assertLessEqual(max(grey) - min(grey), 2, "grey stays near-neutral: %s" % list(grey))
        self.assertEqual([px[3], px[7], px[11], px[15]], [255, 255, 255, 0], "alpha unchanged")

    def test_body_colour_is_most_common_opaque(self) -> None:
        _w, _h, px = tool.read_rgba(_source())
        self.assertEqual(tool.body_colour(px), BODY[:3])

    def test_deterministic(self) -> None:
        self.assertEqual(tool.recolor_png_bytes(_source()), tool.recolor_png_bytes(_source()))

    def test_main_writes_identical_bytes_twice(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "src.png"
            src.write_bytes(_source())
            out = Path(tmp) / "out.png"
            self.assertEqual(tool.main(["x", str(src), str(out)]), 0)
            first = out.read_bytes()
            self.assertEqual(tool.main(["x", str(src), str(out)]), 0)
            self.assertEqual(out.read_bytes(), first)

    def test_white_hits_the_value_clamp_and_stays_neutral(self) -> None:
        # White has V = 1, so V * V_c / V_b (about 1.04) needs the min(1, ...) clamp.
        # S = 0 stays 0, so all three channels come from the same V: exactly equal,
        # with tolerance 0 needed; 1 allows for float rounding only.
        src = _png(3, 1, [BODY, BODY, (0xFF, 0xFF, 0xFF, 255)])
        _w, _h, px = tool.read_rgba(tool.recolor_png_bytes(src))
        white = list(px[8:11])
        for c in white:
            self.assertTrue(0 <= c <= 255)
        self.assertLessEqual(max(white) - min(white), 1, "white stays neutral: %s" % white)
        self.assertGreaterEqual(min(white), 254, "white stays white: %s" % white)
        self.assertEqual(px[11], 255)

    def test_reads_every_filter_type(self) -> None:
        width, height = 2, 5
        pixels = bytes([
            10, 20, 30, 255, 200, 100, 50, 128,
            15, 25, 35, 250, 190, 110, 60, 120,
            250, 5, 128, 0, 1, 2, 3, 4,
            90, 180, 45, 200, 255, 255, 255, 255,
            33, 66, 99, 132, 7, 77, 177, 17,
        ])
        stride = width * 4
        raw = bytearray()
        prev = bytes(stride)
        for y in range(height):
            line = pixels[y * stride:(y + 1) * stride]
            ftype = y  # rows use filters 0, 1, 2, 3, 4
            raw.append(ftype)
            for i in range(stride):
                left = line[i - 4] if i >= 4 else 0
                up = prev[i]
                up_left = prev[i - 4] if i >= 4 else 0
                pred = (0, left, up, (left + up) >> 1, tool._paeth(left, up, up_left))[ftype]
                raw.append((line[i] - pred) & 0xFF)
            prev = line
        ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
        data = (tool.PNG_SIGNATURE + tool._chunk(b"IHDR", ihdr)
                + tool._chunk(b"IDAT", zlib.compress(bytes(raw))) + tool._chunk(b"IEND", b""))
        self.assertEqual(tool.read_rgba(data), (width, height, bytearray(pixels)))
        raw[0] = 5  # unknown filter type
        bad = (tool.PNG_SIGNATURE + tool._chunk(b"IHDR", ihdr)
               + tool._chunk(b"IDAT", zlib.compress(bytes(raw))) + tool._chunk(b"IEND", b""))
        with self.assertRaises(tool.PngFormatError):
            tool.read_rgba(bad)

    def test_paeth_predictor(self) -> None:
        self.assertEqual(tool._paeth(10, 20, 15), 15)  # p = 15, c is nearest
        self.assertEqual(tool._paeth(10, 20, 10), 20)  # p = 20, b is nearest
        self.assertEqual(tool._paeth(20, 10, 10), 20)  # p = 20, a is nearest
        self.assertEqual(tool._paeth(5, 5, 5), 5)      # tie goes to a

    def test_rgb_rejected(self) -> None:
        rgb = _png(1, 1, [(1, 2, 3)], color_type=2)
        with self.assertRaises(tool.PngFormatError):
            tool.recolor_png_bytes(rgb)
        self._assert_main_fails(rgb)

    def test_interlaced_rejected(self) -> None:
        interlaced = _png(1, 1, [BODY], interlace=1)
        with self.assertRaises(tool.PngFormatError):
            tool.recolor_png_bytes(interlaced)
        self._assert_main_fails(interlaced)

    def _assert_main_fails(self, data: bytes) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "bad.png"
            src.write_bytes(data)
            out = Path(tmp) / "out.png"
            stderr = sys.stderr
            sys.stderr = open(Path(tmp) / "err.txt", "w")
            try:
                code = tool.main(["x", str(src), str(out)])
            finally:
                sys.stderr.close()
                sys.stderr = stderr
            self.assertNotEqual(code, 0)
            self.assertFalse(out.exists(), "nothing written on rejection")


if __name__ == "__main__":
    unittest.main()
