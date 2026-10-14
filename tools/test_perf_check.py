"""Tests for tools/perf_check.py (Story 8.3). Stdlib unittest only; no real launch.

Run from the repo root:  uv run python -m unittest tools/test_perf_check.py
"""

from __future__ import annotations

import io
import os
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import perf_check as tool  # noqa: E402

LIMITS = {"max_build_mb": 200, "max_launch_s": 5.0, "launch_timeout_s": 30.0}


class FakeClock:
    """A monotonic clock that only moves when sleep() is called."""

    def __init__(self) -> None:
        self.now = 100.0

    def clock(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.now += seconds


class FakeStdout:
    """A pipe whose lines are released by the test (release()); readline()
    blocks until a line is released or the pipe is closed (EOF)."""

    def __init__(self) -> None:
        self._lines: list[bytes] = []
        self._cond = threading.Condition()
        self._closed = False

    def release(self, line: bytes) -> None:
        with self._cond:
            self._lines.append(line)
            self._cond.notify_all()

    def close(self) -> None:
        with self._cond:
            self._closed = True
            self._cond.notify_all()

    def readline(self) -> bytes:
        with self._cond:
            while not self._lines and not self._closed:
                self._cond.wait(timeout=5.0)
            line = self._lines.pop(0) if self._lines else b""
            self._cond.notify_all()
            return line

    def wait_drained(self) -> None:
        """Blocks until the reader took every released line."""
        with self._cond:
            self._cond.wait_for(lambda: not self._lines, timeout=5.0)


class FakeProcess:
    def __init__(self, exits_after_polls: int | None = None) -> None:
        self.killed = False
        self.waited = False
        self.stdout = FakeStdout()
        self._polls = 0
        self._exits_after = exits_after_polls

    def poll(self) -> int | None:
        if self.killed:
            return -9
        self._polls += 1
        if self._exits_after is not None and self._polls > self._exits_after:
            self.stdout.close()
            return 1
        return None

    def kill(self) -> None:
        self.killed = True
        self.stdout.close()

    def wait(self, timeout: float | None = None) -> int:
        self.waited = True
        return -9


class LimitsTest(unittest.TestCase):
    def test_limits_come_from_the_shipped_tuning(self) -> None:
        self.assertEqual(tool.load_limits(), LIMITS)

    def test_a_missing_limit_is_an_error(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "tuning.json"
            path.write_text('{"debug": {"release_check": {"max_build_mb": 200}}}', encoding="utf-8")
            with self.assertRaises(ValueError):
                tool.load_limits(path)


class SizeTest(unittest.TestCase):
    def test_sums_every_file_recursively(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a.bin").write_bytes(b"x" * 1000)
            (root / "sub").mkdir()
            (root / "sub" / "b.bin").write_bytes(b"y" * 234)
            self.assertEqual(tool.dir_size_bytes(root), 1234)

    def test_under_the_limit_passes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "game.exe").write_bytes(b"x" * 1500)
            out = io.StringIO()
            self.assertEqual(tool.cmd_size(Path(tmp), {"max_build_mb": 0.002}, out), 0)
            self.assertIn("1500 bytes", out.getvalue())
            self.assertIn("PASS", out.getvalue())

    def test_at_or_over_the_limit_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "game.exe").write_bytes(b"x" * 2000)
            out = io.StringIO()
            self.assertEqual(tool.cmd_size(Path(tmp), {"max_build_mb": 0.002}, out), 1, "decimal MB: 2000 bytes is 0.002 MB")
            self.assertIn("FAIL", out.getvalue())

    def test_missing_folder_exits_2(self) -> None:
        out = io.StringIO()
        self.assertEqual(tool.cmd_size(Path("does/not/exist"), LIMITS, out), 2)
        self.assertIn("not a folder", out.getvalue())


class LogTest(unittest.TestCase):
    def test_log_path_comes_from_appdata(self) -> None:
        path = tool.log_path({"APPDATA": os.path.join("X", "Roaming")})
        self.assertEqual(path, Path("X") / "Roaming" / "DEFECTOR" / "logs" / "godot.log")

    def test_no_appdata_is_an_error(self) -> None:
        with self.assertRaises(ValueError):
            tool.log_path({})

    def test_title_ready_line_parse(self) -> None:
        text = "Godot Engine v4.7.2\n[INFO][boot] Config loaded\n[INFO][scene] Title ready 812 ms after launch\n"
        self.assertEqual(tool.title_ready_ms(text), 812)
        self.assertIsNone(tool.title_ready_ms("[INFO][boot] Config loaded\n"))
        self.assertIsNone(tool.title_ready_ms("Title ready soon"))

    def test_freshness_is_written_at_or_after_the_launch(self) -> None:
        self.assertTrue(tool.is_fresh(1000.0, 1000.0))
        self.assertTrue(tool.is_fresh(1000.5, 1000.0))
        self.assertFalse(tool.is_fresh(999.9, 1000.0), "the previous run's log")

    def test_read_fresh_log_ignores_a_stale_log(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "godot.log"
            log.write_text("[INFO][scene] Title ready 500 ms after launch\n", encoding="utf-8")
            os.utime(log, (1000.0, 1000.0))
            self.assertIsNone(tool.read_fresh_log(log, 2000.0), "written before the launch")
            self.assertIn("Title ready", tool.read_fresh_log(log, 900.0))
            self.assertIsNone(tool.read_fresh_log(Path(tmp) / "missing.log", 0.0))


class MeasureLaunchTest(unittest.TestCase):
    def _measure(self, log: Path, process: FakeProcess, on_poll=None, timeout_s: float = 30.0):
        fake = FakeClock()
        calls: list[list[str]] = []

        def popen(cmd, **kwargs):
            calls.append(cmd)
            self.assertEqual(kwargs.get("stdout"), tool.subprocess.PIPE, "stdout is piped")
            return process

        def sleep(seconds: float) -> None:
            fake.sleep(seconds)
            if on_poll is not None:
                on_poll(fake.now - 100.0)

        result = tool.measure_launch(Path("game.exe"), log, timeout_s, popen=popen, clock=fake.clock,
                                     wall=lambda: 5000.0, sleep=sleep)
        return result, calls

    def test_measures_until_a_fresh_title_line_then_kills(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "godot.log"
            # The previous run's log, with its own title line, written before the launch.
            log.write_text("[INFO][scene] Title ready 400 ms after launch\n", encoding="utf-8")
            os.utime(log, (4000.0, 4000.0))
            stages = {"truncated": False, "title": False}

            def on_poll(elapsed: float) -> None:
                if elapsed >= 0.5 and not stages["truncated"]:
                    stages["truncated"] = True
                    log.write_text("Godot Engine\n", encoding="utf-8")
                    os.utime(log, (5000.5, 5000.5))
                if elapsed >= 1.2 and not stages["title"]:
                    stages["title"] = True
                    log.write_text("Godot Engine\n[INFO][scene] Title ready 950 ms after launch\n", encoding="utf-8")
                    os.utime(log, (5001.2, 5001.2))

            process = FakeProcess()
            (seconds, engine_ms, source), calls = self._measure(log, process, on_poll)
            self.assertEqual(calls, [["game.exe"]])
            self.assertIsNotNone(seconds, "the fresh line was found")
            self.assertAlmostEqual(seconds, 1.2, delta=tool.POLL_S + 1e-6, msg="not the stale 400 ms line")
            self.assertEqual(engine_ms, 950)
            self.assertEqual(source, "godot.log")
            self.assertTrue(process.killed, "the game is killed")
            self.assertTrue(process.waited)

    def test_the_title_line_on_stdout_wins_over_a_buffered_log(self) -> None:
        # A release build buffers godot.log: the line only shows on stdout.
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "godot.log"
            process = FakeProcess()
            released = {"done": False}

            def on_poll(elapsed: float) -> None:
                if elapsed >= 0.8 and not released["done"]:
                    released["done"] = True
                    process.stdout.release(b"Godot Engine v4.7.2\r\n")
                    process.stdout.release(b"[INFO][scene] Title ready 1448 ms after launch\r\n")
                    # The reader thread took both lines; give it a moment to record the hit.
                    process.stdout.wait_drained()
                    threading.Event().wait(0.05)

            (seconds, engine_ms, source), _calls = self._measure(log, process, on_poll)
            self.assertEqual(source, "stdout")
            self.assertEqual(engine_ms, 1448)
            self.assertIsNotNone(seconds)
            self.assertGreaterEqual(seconds, 0.8)
            self.assertLess(seconds, 0.8 + 3 * tool.POLL_S)
            self.assertTrue(process.killed)

    def test_no_line_within_the_timeout_fails_and_kills(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            process = FakeProcess()
            (seconds, engine_ms, source), _calls = self._measure(Path(tmp) / "godot.log", process, timeout_s=1.0)
            self.assertIsNone(seconds)
            self.assertIsNone(engine_ms)
            self.assertIsNone(source)
            self.assertTrue(process.killed, "killed after the timeout")

    def test_a_process_that_exits_first_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            process = FakeProcess(exits_after_polls=3)
            (seconds, _engine_ms, _source), _calls = self._measure(Path(tmp) / "godot.log", process, timeout_s=30.0)
            self.assertIsNone(seconds)
            self.assertFalse(process.killed, "nothing to kill")
            self.assertTrue(process.waited)


class LaunchCommandTest(unittest.TestCase):
    def _run(self, results, runs: int = 3, env=None):
        with tempfile.TemporaryDirectory() as tmp:
            exe = Path(tmp) / "DEFECTOR.exe"
            exe.write_bytes(b"MZ")
            queue = list(results)
            seen: list[tuple] = []

            def measure(exe_path, log, timeout_s):
                seen.append((exe_path, log, timeout_s))
                return queue.pop(0)

            out = io.StringIO()
            code = tool.cmd_launch(exe, runs, LIMITS, env if env is not None else {"APPDATA": tmp}, out, measure)
            return code, out.getvalue(), seen, tmp

    def test_every_run_under_the_limit_passes(self) -> None:
        code, text, seen, tmp = self._run([(1.1, 800, "stdout"), (0.9, 700, "stdout"), (1.0, 750, "godot.log")])
        self.assertEqual(code, 0)
        self.assertEqual(len(seen), 3)
        self.assertEqual(seen[0][1], Path(tmp) / "DEFECTOR" / "logs" / "godot.log")
        self.assertEqual(seen[0][2], 30.0, "timeout from tuning")
        self.assertIn("launch run 2: 0.90 s", text)
        self.assertIn("seen on godot.log", text)
        self.assertEqual(seen[0][0], seen[0][0].resolve(), "an absolute exe path")
        self.assertIn("launch: PASS (3 runs)", text)

    def test_one_slow_run_fails(self) -> None:
        code, text, _seen, _tmp = self._run([(1.1, 800, "stdout"), (5.0, 700, "stdout"), (1.0, 750, "stdout")])
        self.assertEqual(code, 1, "5.0 s is not under 5 s")
        self.assertIn("launch: FAIL", text)

    def test_a_timed_out_run_fails(self) -> None:
        code, text, _seen, _tmp = self._run([(1.1, 800, "stdout"), (None, None, None), (1.0, 750, "stdout")])
        self.assertEqual(code, 1)
        self.assertIn("no 'Title ready' line", text)

    def test_usage_errors_exit_2(self) -> None:
        out = io.StringIO()
        self.assertEqual(tool.cmd_launch(Path("no/such.exe"), 1, LIMITS, {"APPDATA": "x"}, out), 2)
        code, text, seen, _tmp = self._run([], env={})
        self.assertEqual(code, 2, "no APPDATA")
        self.assertIn("APPDATA", text)
        self.assertEqual(seen, [])
        code, _text, _seen, _tmp = self._run([], runs=0)
        self.assertEqual(code, 2, "--runs 0")


class MainTest(unittest.TestCase):
    def test_size_subcommand(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "a.bin").write_bytes(b"x" * 10)
            with mock.patch("sys.stdout", new_callable=io.StringIO):
                self.assertEqual(tool.main(["size", tmp]), 0)
                self.assertEqual(tool.main(["size", os.path.join(tmp, "missing")]), 2)

    def test_no_hard_coded_machine_path(self) -> None:
        source = Path(tool.__file__).read_text(encoding="utf-8")
        self.assertNotIn("C:\\Users", source)
        self.assertNotIn("C:/Users", source)


if __name__ == "__main__":
    unittest.main()
