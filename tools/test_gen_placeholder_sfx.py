"""Tests for tools/gen_placeholder_sfx.py (Story 8.1). Stdlib unittest only.

Run from the repo root:  uv run python -m unittest tools/test_gen_placeholder_sfx.py
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

import gen_placeholder_sfx as tool  # noqa: E402

COMMITTED_DIR = Path(__file__).resolve().parent.parent / "game" / "assets" / "audio" / "sfx"
KEPT = ["comms_click", "comms_handover", "comms_open", "comms_open_nobeep", "maul_alarm"]


class RegenerateTest(unittest.TestCase):
    def test_writes_exactly_the_five_kept_cues_byte_identically(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            with mock.patch.object(tool, "OUT_DIR", out), mock.patch.dict(tool.PEAKS), \
                    contextlib.redirect_stdout(io.StringIO()):
                tool.main()
            written = sorted(p.name for p in out.iterdir())
            self.assertEqual(written, [f"sfx_{name}.wav" for name in KEPT])
            for name in KEPT:
                file = f"sfx_{name}.wav"
                self.assertEqual((out / file).read_bytes(), (COMMITTED_DIR / file).read_bytes(), file)


if __name__ == "__main__":
    unittest.main()
