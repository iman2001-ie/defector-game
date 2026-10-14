"""Tests for tools/import_cc0_art.py (Story 8.2). Stdlib unittest only, synthetic images, no packs.

Run from the repo root:  uv run python -m unittest tools/test_import_cc0_art.py
"""

from __future__ import annotations

import colorsys
import contextlib
import io
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import import_cc0_art as tool  # noqa: E402
import recolor_player_ship as png  # noqa: E402


def make_image(width: int, height: int, fill: tuple[int, int, int, int]) -> tool.Image:
    return tool.Image(width, height, bytearray(bytes(fill) * (width * height)))


def set_px(image: tool.Image, x: int, y: int, rgba: tuple[int, int, int, int]) -> None:
    i = (y * image.width + x) * 4
    image.pixels[i:i + 4] = bytes(rgba)


def get_px(image: tool.Image, x: int, y: int) -> tuple[int, int, int, int]:
    i = (y * image.width + x) * 4
    return tuple(image.pixels[i:i + 4])  # type: ignore[return-value]


def rgb_png(width: int, height: int, rows: list[list[tuple[int, int, int]]], ftype: int | list[int] = 0) -> bytes:
    """An 8-bit RGB PNG; `ftype` is one filter for every row or one per row (0 none,
    1 sub, 2 up, 3 average, 4 paeth), with 3-byte pixels."""
    filters = ftype if isinstance(ftype, list) else [ftype] * height
    stride = width * 3
    raw = bytearray()
    prev = bytes(stride)
    for y, row in enumerate(rows):
        line = b"".join(bytes(rgb) for rgb in row)
        f = filters[y]
        raw.append(f)
        for i in range(stride):
            left = line[i - 3] if i >= 3 else 0
            up = prev[i]
            up_left = prev[i - 3] if i >= 3 else 0
            pred = (0, left, up, (left + up) >> 1, png._paeth(left, up, up_left))[f]
            raw.append((line[i] - pred) & 0xFF)
        prev = line
    ihdr = struct.pack(">IIBBBBB", width, height, 8, tool.COLOR_TYPE_RGB, 0, 0, 0)
    return (png.PNG_SIGNATURE + png._chunk(b"IHDR", ihdr)
            + png._chunk(b"IDAT", zlib.compress(bytes(raw))) + png._chunk(b"IEND", b""))


def sprite_png() -> bytes:
    """A 4x4 RGBA sprite: a saturated red body, a grey pixel and a transparent corner."""
    image = make_image(4, 4, (200, 40, 40, 255))
    set_px(image, 1, 1, (128, 128, 128, 255))
    set_px(image, 0, 0, (0, 0, 0, 0))
    return tool.write_png(image)


def build_packs(root: Path, skip: str | None = None) -> dict[str, Path]:
    packs = {tool.REDUX: root / "redux", tool.EXTENSION: root / "ext"}
    for row in tool.ROWS:
        for source in row.sources:
            if source.path == skip:
                continue
            path = tool.source_path(source, packs)
            path.parent.mkdir(parents=True, exist_ok=True)
            if path.suffix == ".ttf":
                path.write_bytes(b"\x00\x01\x00\x00fake font bytes")
            elif source.path.startswith("Backgrounds/"):
                path.write_bytes(rgb_png(3, 2, [[(10, 20, 30), (200, 200, 220), (40, 40, 60)],
                                                [(0, 0, 0), (255, 255, 255), (30, 30, 50)]], ftype=1))
            elif "Damage" in source.path:
                damage = make_image(4, 5, (0, 0, 0, 0))
                set_px(damage, 2, 2, (20, 20, 20, 255))
                path.write_bytes(tool.write_png(damage))
            else:
                path.write_bytes(sprite_png())
    return packs


def hue_of(rgb: tuple[int, ...]) -> float:
    return colorsys.rgb_to_hsv(rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0)[0]


class MappingTest(unittest.TestCase):
    def test_mapping_table_matches_the_spec(self) -> None:
        r, e = tool.REDUX, tool.EXTENSION
        expected = {
            "sprites/enemies/enemy_wasp.png": ([(r, "PNG/Enemies/enemyRed1.png")], [("recolor", (0xFF, 0x2B, 0xD6), 1.0)]),
            "sprites/enemies/enemy_hunter_wasp.png": ([(r, "PNG/Enemies/enemyRed1.png")], [("recolor", (0xFF, 0x8A, 0x1F), 1.0)]),
            "sprites/enemies/enemy_lancer.png": ([(r, "PNG/Enemies/enemyRed2.png")], [("recolor", (0xFF, 0x2B, 0xD6), 1.0)]),
            "sprites/enemies/enemy_needle.png": ([(e, "PNG/Sprites/Ships/spaceShips_006.png")], [("recolor", (0xFF, 0x2B, 0xD6), 1.0)]),
            "sprites/enemies/enemy_bastion.png": ([(e, "PNG/Sprites/Ships/spaceShips_007.png")], [("recolor", (0xFF, 0x2B, 0xD6), 1.0)]),
            "sprites/enemies/enemy_maul.png": ([(e, "PNG/Sprites/Ships/spaceShips_004.png")], [("recolor", (0xFF, 0x2B, 0xD6), 1.0)]),
            "sprites/allies/ally_coalition.png": ([(r, "PNG/playerShip2_blue.png")], [("recolor", (0x22, 0xE6, 0xFF), 1.0)]),
            "sprites/allies/ally_damaged.png": (
                [(r, "PNG/playerShip2_blue.png"), (r, "PNG/Damage/playerShip2_damage3.png")],
                [("overlay", None, 1.0), ("recolor", (0x22, 0xE6, 0xFF), 0.45)],
            ),
            "sprites/allies/convoy_cargo.png": (
                [(e, "PNG/Sprites/Ships/spaceShips_005.png")],
                [("rot180", None, 1.0), ("recolor", (0x22, 0xE6, 0xFF), 0.9)],
            ),
            "sprites/boss/flagship_turret.png": ([(r, "PNG/Parts/turretBase_big.png")], [("tint", (0xFF, 0x2B, 0xD6), 1.0)]),
            "sprites/boss/flagship_core.png": ([(r, "PNG/ufoRed.png")], [("recolor", (0xFF, 0x2B, 0xD6), 1.0)]),
            "backgrounds/space_1.png": ([(r, "Backgrounds/blue.png")], [("background", (0x0B, 0x12, 0x26), 1.0)]),
            "backgrounds/space_2.png": ([(r, "Backgrounds/darkPurple.png")], [("background", (0x14, 0x0E, 0x26), 1.0)]),
            "fonts/kenvector_future.ttf": ([(r, "Bonus/kenvector_future.ttf")], [("copy", None, 1.0)]),
        }
        for size, meteor in (("large", "big1"), ("medium", "med1"), ("small", "small1")):
            expected["sprites/asteroids/asteroid_%s.png" % size] = (
                [(r, "PNG/Meteors/meteorBrown_%s.png" % meteor)],
                [("recolor", (0x7A, 0x6E, 0x62), 1.0), ("rim", (0xC9, 0xD8, 0xE8), 1.0)],
            )
        actual = {
            row.out: ([(s.pack, s.path) for s in row.sources], [(o.name, o.rgb, o.value) for o in row.ops])
            for row in tool.ROWS
        }
        self.assertEqual(actual, expected)
        self.assertEqual(len(tool.ROWS), len(actual), "no output is written twice")

    def test_rim_is_two_pixels(self) -> None:
        for row in tool.ROWS:
            for op in row.ops:
                if op.name == "rim":
                    self.assertEqual(op.px, 2, row.out)

    def test_never_writes_the_player_ship(self) -> None:
        self.assertFalse(any("player" in row.out for row in tool.ROWS))

    def test_docstring_records_pages_and_hashes(self) -> None:
        doc = tool.__doc__ or ""
        for text in (
            "https://opengameart.org/content/space-shooter-redux",
            "https://opengameart.org/content/space-shooter-extension-250",
            "d44a371a8fa1eb5d61a4fed3677954590aa015a78d2afb5f97924cfe02e3f700",
            "77efd54b343bbd123af8cc7f534446706731b9cf5a34f38d8fcc54e7245f9c91",
        ):
            self.assertIn(text, doc)


class DecodeTest(unittest.TestCase):
    def test_rgb_png_decodes_to_opaque_rgba(self) -> None:
        image = tool.read_png(rgb_png(2, 1, [[(1, 2, 3), (250, 100, 7)]], ftype=1))
        self.assertEqual((image.width, image.height), (2, 1))
        self.assertEqual(get_px(image, 0, 0), (1, 2, 3, 255))
        self.assertEqual(get_px(image, 1, 0), (250, 100, 7, 255))

    def test_rgb_reads_every_filter_type(self) -> None:
        rows = [
            [(10, 20, 30), (200, 100, 50)],
            [(15, 25, 35), (190, 110, 60)],
            [(250, 5, 128), (1, 2, 3)],
            [(90, 180, 45), (255, 255, 255)],
            [(33, 66, 99), (7, 77, 177)],
        ]
        data = rgb_png(2, 5, rows, ftype=[0, 1, 2, 3, 4])
        image = tool.read_png(data)
        self.assertEqual((image.width, image.height), (2, 5))
        for y, row in enumerate(rows):
            for x, rgb in enumerate(row):
                self.assertEqual(get_px(image, x, y), rgb + (255,), "row %d (filter %d), pixel %d" % (y, y, x))

    def test_rgb_unknown_filter_type_is_refused(self) -> None:
        ihdr = struct.pack(">IIBBBBB", 1, 1, 8, tool.COLOR_TYPE_RGB, 0, 0, 0)
        bad = (png.PNG_SIGNATURE + png._chunk(b"IHDR", ihdr)
               + png._chunk(b"IDAT", zlib.compress(bytes([5, 1, 2, 3]))) + png._chunk(b"IEND", b""))
        with self.assertRaises(png.PngFormatError):
            tool.read_png(bad)

    def test_rgba_png_round_trips(self) -> None:
        image = make_image(3, 2, (9, 8, 7, 128))
        decoded = tool.read_png(tool.write_png(image))
        self.assertEqual(decoded.pixels, image.pixels)

    def test_other_formats_are_refused(self) -> None:
        ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 0, 0, 0, 0)  # greyscale
        data = png.PNG_SIGNATURE + png._chunk(b"IHDR", ihdr) + png._chunk(b"IEND", b"")
        with self.assertRaises(png.PngFormatError):
            tool.read_png(data)


class OpsTest(unittest.TestCase):
    def test_reference_is_the_most_common_saturated_opaque_colour(self) -> None:
        image = make_image(4, 1, (240, 240, 240, 255))  # 4 white (S 0)
        set_px(image, 0, 0, (200, 40, 40, 255))
        set_px(image, 1, 0, (200, 40, 40, 255))
        set_px(image, 2, 0, (40, 200, 40, 128))  # not fully opaque
        self.assertEqual(tool.reference_colour(image), (200, 40, 40))

    def test_reference_ignores_low_saturation(self) -> None:
        image = make_image(3, 1, (130, 120, 110, 255))  # S ~0.15
        self.assertIsNone(tool.reference_colour(image))

    def test_reference_ties_take_the_smallest_rgb(self) -> None:
        image = make_image(2, 1, (200, 40, 40, 255))
        set_px(image, 1, 0, (40, 40, 200, 255))
        self.assertEqual(tool.reference_colour(image), (40, 40, 200))

    def test_recolor_maps_the_reference_to_the_target(self) -> None:
        image = make_image(2, 1, (200, 40, 40, 255))
        set_px(image, 1, 0, (128, 128, 128, 77))
        out = tool.recolor(image, tool.ENEMY)
        self.assertEqual(get_px(out, 0, 0), (0xFF, 0x2B, 0xD6, 255))
        grey = get_px(out, 1, 0)
        self.assertEqual(grey[3], 77, "alpha unchanged")
        self.assertLessEqual(max(grey[:3]) - min(grey[:3]), 0, "a grey stays grey")

    def test_recolor_value_scales_v(self) -> None:
        image = make_image(1, 1, (200, 40, 40, 255))
        out = tool.recolor(image, tool.COALITION, 0.5)
        self.assertEqual(get_px(out, 0, 0), (round(0x22 * 0.5), round(0xE6 * 0.5), round(0xFF * 0.5), 255))

    def test_recolor_falls_back_to_tint(self) -> None:
        image = make_image(1, 1, (200, 200, 200, 255))
        self.assertEqual(tool.recolor(image, tool.ENEMY).pixels, tool.tint(image, tool.ENEMY).pixels)

    def test_tint_is_target_times_luminance(self) -> None:
        image = make_image(2, 1, (255, 255, 255, 255))
        set_px(image, 1, 0, (0, 0, 0, 40))
        out = tool.tint(image, tool.ENEMY)
        self.assertEqual(get_px(out, 0, 0), (0xFF, 0x2B, 0xD6, 255))
        self.assertEqual(get_px(out, 1, 0), (0, 0, 0, 40))
        mid = tool.tint(make_image(1, 1, (128, 128, 128, 255)), (200, 100, 50))
        lum = tool.luminance(128, 128, 128)
        self.assertEqual(get_px(mid, 0, 0), (round(200 * lum), round(100 * lum), round(50 * lum), 255))

    def test_rot180(self) -> None:
        image = make_image(2, 2, (0, 0, 0, 255))
        set_px(image, 0, 0, (1, 2, 3, 4))
        out = tool.rot180(image)
        self.assertEqual(get_px(out, 1, 1), (1, 2, 3, 4))
        self.assertEqual(get_px(out, 0, 0), (0, 0, 0, 255))

    def test_overlay_alpha_over(self) -> None:
        base = make_image(2, 1, (100, 100, 100, 255))
        set_px(base, 1, 0, (0, 0, 0, 0))
        top = make_image(2, 2, (0, 0, 0, 0))  # one row taller: clipped
        set_px(top, 0, 0, (200, 0, 0, 128))
        set_px(top, 1, 0, (0, 200, 0, 255))
        out = tool.overlay(base, top)
        a = 128 / 255.0
        self.assertEqual(get_px(out, 0, 0), (round(200 * a + 100 * (1 - a)), round(100 * (1 - a)),
                                             round(100 * (1 - a)), 255))
        self.assertEqual(get_px(out, 1, 0), (0, 200, 0, 255))
        self.assertEqual((out.width, out.height), (2, 1))

    def test_rim_lights_the_upper_left_edge_only(self) -> None:
        image = make_image(7, 7, (0, 0, 0, 0))
        for y in range(1, 6):
            for x in range(1, 6):
                set_px(image, x, y, (100, 100, 100, 255))
        out = tool.rim(image, (200, 0, 0), 2)
        lit = (round(100 + 0.7 * 100), round(100 - 0.7 * 100), round(100 - 0.7 * 100), 255)
        self.assertEqual(get_px(out, 1, 3), lit, "left edge")
        self.assertEqual(get_px(out, 2, 3), lit, "2 px in from the left")
        self.assertEqual(get_px(out, 3, 3), (100, 100, 100, 255), "3 px in: unlit")
        self.assertEqual(get_px(out, 3, 1), lit, "top edge")
        self.assertEqual(get_px(out, 5, 3), (100, 100, 100, 255), "the right edge stays unlit")
        self.assertEqual(get_px(out, 3, 5), (100, 100, 100, 255), "the bottom edge stays unlit")
        self.assertEqual(get_px(out, 0, 0), (0, 0, 0, 0), "transparent stays transparent")

    def test_rim_counts_the_image_border_as_transparent(self) -> None:
        out = tool.rim(make_image(4, 4, (100, 100, 100, 255)), (0, 0, 0), 2)
        self.assertEqual(get_px(out, 0, 3)[0], 30)
        self.assertEqual(get_px(out, 3, 3)[0], 100)

    def test_background_scales_by_relative_luminance_and_clamps(self) -> None:
        image = make_image(4, 1, (20, 20, 20, 255))
        set_px(image, 3, 0, (255, 255, 255, 255))
        out = tool.background(image, tool.SPACE_1)
        mean = (3 * tool.luminance(20, 20, 20) + 1.0) / 4
        f = tool.luminance(20, 20, 20) / mean
        self.assertEqual(get_px(out, 0, 0), (round(0x0B * f), round(0x12 * f), round(0x26 * f), 255))
        self.assertTrue(all(c <= 127 for c in get_px(out, 3, 0)[:3]))

    def test_background_never_exceeds_127(self) -> None:
        image = make_image(8, 8, (0, 0, 0, 255))
        set_px(image, 2, 2, (255, 255, 255, 255))
        set_px(image, 5, 5, (255, 200, 255, 255))
        for target in (tool.SPACE_1, tool.SPACE_2, (255, 255, 255)):
            out = tool.background(image, target)
            for i in range(0, len(out.pixels), 4):
                self.assertLessEqual(max(out.pixels[i:i + 3]), tool.BACKGROUND_MAX)
                self.assertEqual(out.pixels[i + 3], 255)


class RunTest(unittest.TestCase):
    def run_main(self, args: list[str]) -> tuple[int, str]:
        err = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(err):
            code = tool.main(args)
        return code, err.getvalue()

    def test_writes_every_row_deterministically(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            packs = build_packs(root)
            args = ["--redux", str(packs[tool.REDUX]), "--extension", str(packs[tool.EXTENSION])]
            self.assertEqual(self.run_main(args + ["--out", str(root / "a")])[0], 0)
            self.assertEqual(self.run_main(args + ["--out", str(root / "b")])[0], 0)
            for row in tool.ROWS:
                a = (root / "a" / row.out).read_bytes()
                self.assertEqual(a, (root / "b" / row.out).read_bytes(), row.out)
            self.assertEqual((root / "a" / "fonts/kenvector_future.ttf").read_bytes(),
                             b"\x00\x01\x00\x00fake font bytes", "copy is byte-for-byte")
            wasp = tool.read_png((root / "a" / "sprites/enemies/enemy_wasp.png").read_bytes())
            self.assertEqual(get_px(wasp, 2, 2), (0xFF, 0x2B, 0xD6, 255))
            convoy = tool.read_png((root / "a" / "sprites/allies/convoy_cargo.png").read_bytes())
            self.assertEqual(get_px(convoy, 3, 3), (0, 0, 0, 0), "rot180 moved the clear corner")
            self.assertAlmostEqual(hue_of(get_px(convoy, 0, 0)), hue_of(tool.COALITION), places=2)
            for name in ("space_1", "space_2"):
                bg = tool.read_png((root / "a" / ("backgrounds/%s.png" % name)).read_bytes())
                self.assertTrue(all(bg.pixels[i] <= 127 for i in range(len(bg.pixels)) if i % 4 != 3))

    def test_missing_source_exits_2_and_writes_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            packs = build_packs(root, skip="PNG/Damage/playerShip2_damage3.png")
            out = root / "out"
            code, err = self.run_main(["--redux", str(packs[tool.REDUX]), "--extension",
                                       str(packs[tool.EXTENSION]), "--out", str(out)])
            self.assertEqual(code, 2)
            self.assertIn("playerShip2_damage3.png", err)
            self.assertIn("sprites/allies/ally_damaged.png", err)
            self.assertFalse(out.exists(), "nothing written")

    def test_truncated_png_source_exits_1(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            packs = build_packs(root)
            path = packs[tool.REDUX] / "PNG/Enemies/enemyRed1.png"
            path.write_bytes(png.PNG_SIGNATURE + bytes(2))  # cut off before the IHDR
            code, _err = self.run_main(["--redux", str(packs[tool.REDUX]), "--extension",
                                        str(packs[tool.EXTENSION]), "--out", str(root / "out")])
            self.assertEqual(code, 1)
            self.assertFalse((root / "out").exists(), "nothing written")

    def test_pack_folder_must_exist(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            code, _err = self.run_main(["--redux", str(Path(tmp) / "nope"), "--extension", tmp,
                                        "--out", str(Path(tmp) / "out")])
            self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
