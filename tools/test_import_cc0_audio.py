"""Tests for tools/import_cc0_audio.py (Story 8.1). Stdlib unittest only; no ffmpeg needed.

Run from the repo root:  uv run python -m unittest tools/test_import_cc0_audio.py
"""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import import_cc0_audio as tool  # noqa: E402

# The kept generated cues and the recorded static: never written by the importer.
KEPT = {"comms_open", "comms_open_nobeep", "comms_click", "comms_handover", "comms_static", "maul_alarm"}


class MappingTest(unittest.TestCase):
    def test_sfx_mapping_matches_the_spec(self) -> None:
        expected = {
            "laser_zap": (tool.SCI_FI, "laserSmall_001.ogg", None, None),
            "missile_launch": (tool.SCI_FI, "thrusterFire_003.ogg", 0.55, 0.3),
            "barrage_whoosh": (tool.SCI_FI, "thrusterFire_001.ogg", 0.30, 0.2),
            "explosion_small": (tool.SCI_FI, "explosionCrunch_000.ogg", None, None),
            "explosion_medium": (tool.SCI_FI, "explosionCrunch_001.ogg", None, None),
            "explosion_large": (tool.SCI_FI, "explosionCrunch_004.ogg", None, None),
            "explosion_mid": (tool.JOTH, "Chunky Explosion.mp3", None, None),
            "explosion_boss_death": (tool.JOTH, "Chunky Explosion.mp3", None, None),
            "player_hit": (tool.SCI_FI, "impactMetal_002.ogg", None, None),
            "player_death": (tool.SCI_FI, "explosionCrunch_003.ogg", None, None),
            "shield_on": (tool.SCI_FI, "forceField_000.ogg", None, None),
            "energy_pickup": (tool.INTERFACE, "glass_001.ogg", None, None),
            "needle_fire": (tool.SCI_FI, "laserLarge_000.ogg", 0.45, 0.2),
            "ability_denied": (tool.INTERFACE, "error_007.ogg", None, None),
        }
        actual = {k: (s.pack, s.file, s.trim_s, s.fade_out_s) for k, s in tool.SFX_SOURCES.items()}
        self.assertEqual(actual, expected)

    def test_every_source_file_is_distinct(self) -> None:
        # Playtest pt7-k: one file may feed two ids only through different processing.
        keys = [(s.file, s.trim_s, s.fade_out_s, s.af) for s in tool.SFX_SOURCES.values()]
        self.assertEqual(len(keys), len(set(keys)), "no two ids share a source and its processing (no aliases)")

    def test_explosion_mid_is_a_scaled_joth(self) -> None:
        mid = tool.SFX_SOURCES["explosion_mid"]
        self.assertEqual(mid.file, tool.SFX_SOURCES["explosion_boss_death"].file, "the same recording")
        self.assertEqual(mid.af, "asetrate=44100*1.32,aresample=44100,highpass=f=130,atrim=end=1.35,afade=t=out:st=0.75:d=0.6")
        self.assertEqual(tool.SFX_SOURCES["explosion_boss_death"].af, "", "the final blast is the raw file")

    def test_kept_cues_are_never_written(self) -> None:
        self.assertFalse(KEPT & set(tool.SFX_SOURCES), "the comms cues, maul_alarm and the static stay")

    def test_fade_out_only_with_a_trim_and_shorter_than_it(self) -> None:
        for sfx_id, source in tool.SFX_SOURCES.items():
            if source.fade_out_s is not None:
                self.assertIsNotNone(source.trim_s, sfx_id)
                self.assertGreater(source.trim_s, source.fade_out_s, sfx_id)

    def test_music_mapping_matches_the_spec(self) -> None:
        self.assertEqual(
            {k: (s.file, s.sha256, s.transcode) for k, s in tool.MUSIC_SOURCES.items()},
            {
                "level_1": ("02 HoliznaCC0 - Retro Soundtrack.ogg", "2c336e7d0fa1993749a8d0fc656b07fab7e14284b2ac5234408eceb5f9eeae6b", True),
                "level_2": ("synth_5.mp3", "5c36241db12e49600052588321851625a7678affebce3bd0763b0739ae789cf1", True),
                "level_3": ("Anti Matter Magic.ogg", "7b19b04738264ef5e1c9df4d82af4a34192c6657ede915b4610d693b3388efe7", True),
                "boss": ("space_boss_battle_bpm175_0.ogg", "4fc0898456099db3d9e63bd97450fedc3f9ff0a05cd65a8d363b3f2904415e60", False),
                "epilogue": ("space_echo.ogg", "331fa9ceb811a33a31819652c9c22296879c199e1ebe407822ee7b1399b959be", False),
                "menu": ("synthwavehouse_0.ogg", "ac6a7af314f55de46e28c8068249ebb26c471e67d1a4745ee04eb0c0c9bacf0b", False),
                "game_over": ("Game Over_1.ogg", "eb16aeb17fed5b13575702e082b54db00b296f6f4f2e9ee89c63aca895bc085e", False),
            },
        )

    def test_output_names(self) -> None:
        self.assertEqual(tool.sfx_name("shield_on"), "sfx_shield_on.wav")
        self.assertEqual(tool.music_name("boss"), "music_boss.ogg")

    def test_docstring_records_every_source_hash(self) -> None:
        doc = tool.__doc__ or ""
        for digest in (
            "119340f351a5098ad814f78719438c0da355a9ce8a4c8a3af6a8d48aa3d49e04",
            "f2193d072726d6758a5f7871b2dcc54dcce0d5c35c6f0a62f92549b327c81232",
            "4fc0898456099db3d9e63bd97450fedc3f9ff0a05cd65a8d363b3f2904415e60",
            "331fa9ceb811a33a31819652c9c22296879c199e1ebe407822ee7b1399b959be",
            "ac6a7af314f55de46e28c8068249ebb26c471e67d1a4745ee04eb0c0c9bacf0b",
            "4de53bffac187e59d3f5b43096df2f8fcb4160076b65b71a67074947950e025f",
            "eb16aeb17fed5b13575702e082b54db00b296f6f4f2e9ee89c63aca895bc085e",
            "2c336e7d0fa1993749a8d0fc656b07fab7e14284b2ac5234408eceb5f9eeae6b",
            "5c36241db12e49600052588321851625a7678affebce3bd0763b0739ae789cf1",
            "7b19b04738264ef5e1c9df4d82af4a34192c6657ede915b4610d693b3388efe7",
            "f922929805bc6afdf0a35727fa3998033db544c1b6f62ed3aeab94341ed6ddeb",
            "f79f07a733eb27822fb4567318e38b150a482d340bdabad7a30c099815109588",
        ):
            self.assertIn(digest, doc)

    def test_only_tarek_burn_is_layered(self) -> None:
        # Playtest pt7-i: the final Flagship blast is Joth's file alone; pt7-j layers the burn.
        self.assertEqual(set(tool.LAYERED_SOURCES), {"tarek_burn"})

    def test_layered_tarek_burn_mapping(self) -> None:
        source = tool.LAYERED_SOURCES["tarek_burn"]
        self.assertEqual(
            [(layer.pack, layer.file, layer.volume, layer.rate, layer.delay_s) for layer in source.layers],
            [
                (tool.SCI_FI, "thrusterFire_000.ogg", 0.8, 0.7, 0.0),
                (tool.ANTUM_FIRE, "fire-1_0.ogg", 1.0, 1.0, 0.0),
                (tool.SPRING_SFX, "dull_explosion.wav", 0.6, 1.0, 2.2),
            ],
        )
        self.assertEqual(source.echo, "", "no echo")
        self.assertEqual((source.length_s, source.fade_out_s), (4.6, 1.2))

    def test_no_id_is_both_plain_and_layered(self) -> None:
        self.assertFalse(set(tool.SFX_SOURCES) & set(tool.LAYERED_SOURCES))
        self.assertFalse(KEPT & set(tool.LAYERED_SOURCES))


class FfmpegArgsTest(unittest.TestCase):
    def test_untrimmed_chain_is_only_the_format(self) -> None:
        chain = tool.filter_chain(tool.SfxSource("p", "a.ogg"))
        self.assertEqual(chain, "aformat=sample_fmts=flt:sample_rates=44100:channel_layouts=mono")

    def test_own_filter_chain_runs_first(self) -> None:
        chain = tool.filter_chain(tool.SfxSource("p", "a.ogg", af="highpass=f=130"))
        self.assertEqual(chain, "highpass=f=130,aformat=sample_fmts=flt:sample_rates=44100:channel_layouts=mono")

    def test_trimmed_chain_trims_then_fades_in_and_out(self) -> None:
        chain = tool.filter_chain(tool.SFX_SOURCES["missile_launch"])
        self.assertEqual(
            chain,
            "aformat=sample_fmts=flt:sample_rates=44100:channel_layouts=mono,"
            "atrim=end=0.55,afade=t=in:d=0.005,afade=t=out:st=0.25:d=0.3",
        )
        chain = tool.filter_chain(tool.SFX_SOURCES["barrage_whoosh"])
        self.assertTrue(chain.endswith("atrim=end=0.3,afade=t=in:d=0.005,afade=t=out:st=0.1:d=0.2"), chain)

    def test_measure_args(self) -> None:
        source = tool.SFX_SOURCES["laser_zap"]
        args = tool.measure_args(Path("in.ogg"), source)
        self.assertEqual(args[0], "ffmpeg")
        self.assertEqual(args[args.index("-i") + 1], "in.ogg")
        chain = args[args.index("-af") + 1]
        self.assertTrue(chain.startswith(tool.filter_chain(source) + ","))
        self.assertIn("astats=", chain)
        self.assertIn("measure_overall=Peak_level", chain)
        self.assertEqual(args[-3:], ["-f", "null", "-"])

    def test_render_args(self) -> None:
        source = tool.SFX_SOURCES["missile_launch"]
        args = tool.render_args(Path("in.ogg"), Path("out.wav"), source, 2.5)
        self.assertEqual(args[0], "ffmpeg")
        self.assertIn("-y", args)
        self.assertEqual(args[args.index("-af") + 1], tool.filter_chain(source) + ",volume=2.500000dB")
        self.assertEqual(args[args.index("-ac") + 1], "1")
        self.assertEqual(args[args.index("-ar") + 1], "44100")
        self.assertEqual(args[args.index("-c:a") + 1], "pcm_s16le")
        self.assertEqual(args[args.index("-map_metadata") + 1], "-1")
        self.assertIn("+bitexact", args)
        self.assertEqual(args[-1], "out.wav")

    def test_transcode_args(self) -> None:
        args = tool.transcode_args(Path("in.mp3"), Path("out.ogg"))
        self.assertEqual(args[0], "ffmpeg")
        self.assertIn("-y", args)
        self.assertEqual(args[args.index("-i") + 1], "in.mp3")
        self.assertEqual(args[args.index("-c:a") + 1], "libvorbis")
        self.assertEqual(args[args.index("-q:a") + 1], str(tool.MUSIC_QUALITY))
        self.assertEqual(args[args.index("-ac") + 1], "2")
        self.assertEqual(args[args.index("-ar") + 1], "44100")
        self.assertEqual(args[args.index("-map_metadata") + 1], "-1")
        self.assertIn("+bitexact", args)
        self.assertEqual(args[-1], "out.ogg")

    def test_layered_graph_pitches_and_delays_layers_and_skips_an_empty_echo(self) -> None:
        source = tool.LAYERED_SOURCES["tarek_burn"]
        graph = tool.layered_graph(source)
        fmt = "aformat=sample_fmts=flt:sample_rates=44100:channel_layouts=mono"
        self.assertEqual(
            graph,
            f"[0:a]{fmt},asetrate=30870,aresample=44100,volume=0.8[l0];"
            f"[1:a]{fmt},volume=1[l1];"
            f"[2:a]{fmt},adelay=2200:all=1,volume=0.6[l2];"
            "[l0][l1][l2]amix=inputs=3:duration=longest:normalize=0,"
            "atrim=end=4.6,afade=t=out:st=3.4:d=1.2",
        )

    def test_layered_measure_and_render_args(self) -> None:
        source = tool.LAYERED_SOURCES["tarek_burn"]
        srcs = [Path("a.mp3"), Path("b.ogg"), Path("c.ogg")]
        measure = tool.layered_measure_args(srcs, source)
        self.assertEqual([measure[i + 1] for i, a in enumerate(measure) if a == "-i"], ["a.mp3", "b.ogg", "c.ogg"])
        graph = measure[measure.index("-filter_complex") + 1]
        self.assertTrue(graph.startswith(tool.layered_graph(source) + ",astats="), graph)
        self.assertTrue(graph.endswith("[out]"))
        self.assertEqual(measure[measure.index("-map") + 1], "[out]")
        self.assertEqual(measure[-3:], ["-f", "null", "-"])
        render = tool.layered_render_args(srcs, Path("out.wav"), source, -1.5)
        self.assertEqual(render[render.index("-filter_complex") + 1], tool.layered_graph(source) + ",volume=-1.500000dB[out]")
        self.assertIn("-y", render)
        self.assertEqual(render[render.index("-c:a") + 1], "pcm_s16le")
        self.assertEqual(render[render.index("-ac") + 1], "1")
        self.assertIn("+bitexact", render)
        self.assertEqual(render[-1], "out.wav")

    def test_render_args_negative_gain(self) -> None:
        args = tool.render_args(Path("in.ogg"), Path("out.wav"), tool.SFX_SOURCES["laser_zap"], -1.470460)
        self.assertTrue(args[args.index("-af") + 1].endswith(",volume=-1.470460dB"))

    def test_parse_peak_takes_the_last_value(self) -> None:
        stderr = (
            "[Parsed_astats_1 @ 0x1] Channel: 1\n[Parsed_astats_1 @ 0x1] Peak level dB: -9.000000\n"
            "[Parsed_astats_1 @ 0x1] Overall\n[Parsed_astats_1 @ 0x1] Peak level dB: 0.470460\n"
        )
        self.assertAlmostEqual(tool.parse_peak_db(stderr), 0.470460)

    def test_parse_peak_errors(self) -> None:
        with self.assertRaises(ValueError):
            tool.parse_peak_db("nothing here")
        with self.assertRaises(ValueError):
            tool.parse_peak_db("Peak level dB: -inf")

    def test_gain_reaches_minus_one_dbfs(self) -> None:
        self.assertAlmostEqual(tool.gain_db(0.47), -1.47)
        self.assertAlmostEqual(tool.gain_db(-6.0), 5.0)
        self.assertAlmostEqual(tool.gain_db(-1.0), 0.0)


class FindFileTest(unittest.TestCase):
    def test_finds_one_file_by_name_in_any_subfolder(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a" / "Audio").mkdir(parents=True)
            target = root / "a" / "Audio" / "forceField_000.ogg"
            target.write_bytes(b"x")
            self.assertEqual(tool.find_file(root, "forceField_000.ogg"), target)

    def test_missing_or_ambiguous_names_fail(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaises(FileNotFoundError):
                tool.find_file(root, "nope.ogg")
            for sub in ("a", "b"):
                (root / sub).mkdir()
                (root / sub / "twice.ogg").write_bytes(b"x")
            with self.assertRaises(FileNotFoundError):
                tool.find_file(root, "twice.ogg")

    def test_sha256_of(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "f.bin"
            path.write_bytes(b"abc")
            self.assertEqual(tool.sha256_of(path), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")



class ImportMusicTest(unittest.TestCase):
    def _packs(self, root: Path, data: bytes) -> tuple[Path, Path]:
        packs = root / "packs"
        (packs / "music").mkdir(parents=True)
        (packs / "music" / "track.ogg").write_bytes(data)
        return packs, root / "out"

    def test_wrong_hash_raises_and_writes_nothing(self) -> None:
        sources = {"level_1": tool.MusicSource("track.ogg", tool.sha256_of(Path(__file__)))}
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict(tool.MUSIC_SOURCES, sources, clear=True):
            packs, out = self._packs(Path(tmp), b"not the track")
            with self.assertRaises(ValueError):
                tool.import_music(packs, out)
            self.assertFalse(out.exists() and any(out.iterdir()), "nothing written")

    def test_right_hash_copies_byte_identically(self) -> None:
        data = b"OggS fake track bytes"
        with tempfile.TemporaryDirectory() as tmp:
            packs, out = self._packs(Path(tmp), data)
            sources = {"boss": tool.MusicSource("track.ogg", tool.sha256_of(packs / "music" / "track.ogg"))}
            with mock.patch.dict(tool.MUSIC_SOURCES, sources, clear=True), contextlib.redirect_stdout(io.StringIO()):
                tool.import_music(packs, out)
            self.assertEqual(sorted(p.name for p in out.iterdir()), ["music_boss.ogg"])
            self.assertEqual((out / "music_boss.ogg").read_bytes(), data)

    def test_transcoded_track_runs_ffmpeg_after_the_hash_check(self) -> None:
        data = b"fake mp3 bytes"
        with tempfile.TemporaryDirectory() as tmp:
            packs, out = self._packs(Path(tmp), data)
            sha = tool.sha256_of(packs / "music" / "track.ogg")
            sources = {"level_2": tool.MusicSource("track.ogg", sha, transcode=True)}
            with mock.patch.dict(tool.MUSIC_SOURCES, sources, clear=True), \
                    mock.patch.object(tool, "_run", return_value="") as run, \
                    contextlib.redirect_stdout(io.StringIO()):
                tool.import_music(packs, out)
            run.assert_called_once_with(tool.transcode_args(packs / "music" / "track.ogg", out / "music_level_2.ogg"))


class MainTest(unittest.TestCase):
    def test_packs_that_is_not_a_folder_returns_2(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(tool.main(["--packs", str(Path(tmp) / "missing")]), 2)
            file = Path(tmp) / "file.txt"
            file.write_bytes(b"x")
            self.assertEqual(tool.main(["--packs", str(file)]), 2)


if __name__ == "__main__":
    unittest.main()
