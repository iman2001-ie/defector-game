"""Story 8.3: release checks for an export's size (NFR3) and launch-to-title time (NFR2).

Run from the repo root (stdlib only):

    uv run python tools/perf_check.py size game/export/windows
    uv run python tools/perf_check.py launch game/export/windows/DEFECTOR.exe --runs 3

The limits come from game/data/tuning.json -> debug.release_check
(max_build_mb, max_launch_s, launch_timeout_s); nothing here is tuned.

size: sums every file under the export folder and passes (exit 0) when the
total is under max_build_mb (decimal MB, 1 MB = 1,000,000 bytes, the stricter
reading). Over the limit exits 1; a missing folder exits 2.

launch: each run starts the exe and measures the wall seconds from just before
the process starts until the `Title ready N ms after launch` line (title.gd)
appears, then kills the process. The line is watched in two places, whichever
shows it first:
- the game's stdout, read through a pipe. Godot's Windows terminal logger
  writes it unbuffered, so this is the route that works on a release build;
- a fresh %APPDATA%/DEFECTOR/logs/godot.log (path from the APPDATA environment
  variable: project.godot's custom user dir "DEFECTOR" with file logging on).
  Release builds buffer the file logger (application/run/flush_stdout_on_print
  is off), so there the line only reaches the file at exit; debug builds flush
  every line. Godot keeps the same godot.log file on start: it copies the old
  one to godot<timestamp>.log and then truncates godot.log in place, so the
  file's identity and creation time don't change. A log therefore counts as
  created after the launch when it was last written at or after the launch's
  wall-clock start; the previous run's log (written before the launch) is never
  read.
Pass the game exe itself (DEFECTOR.exe), never the debug export's
DEFECTOR.console.exe wrapper: launch kills only the process it started, so the
wrapper's child (the real game) would be left running.
A run with no line within launch_timeout_s, or whose process exits first,
fails. Exit 0 when every run is under max_launch_s, 1 when any is not, 2 on a
usage error (no exe, no APPDATA).

The in-game `Title ready N ms` number is engine ticks, which miss the process
start and the embedded-PCK load; this script measures from outside the process
instead. It is not a true cold boot (the OS file cache is warm after the first
run); that stays an operator check.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Callable, Mapping

REPO = Path(__file__).resolve().parent.parent
TUNING = REPO / "game" / "data" / "tuning.json"
TITLE_READY = re.compile(r"Title ready (\d+) ms after launch")
BYTES_PER_MB = 1_000_000
POLL_S = 0.02


def load_limits(path: Path = TUNING) -> dict:
    """The debug.release_check section of tuning.json."""
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    limits = data["debug"]["release_check"]
    for key in ("max_build_mb", "max_launch_s", "launch_timeout_s"):
        if not isinstance(limits.get(key), (int, float)):
            raise ValueError(f"tuning.json debug.release_check.{key} is missing or not a number")
    return limits


def dir_size_bytes(folder: Path) -> int:
    """Total size of every file under `folder` (recursive)."""
    total = 0
    for root, _dirs, files in os.walk(folder):
        for name in files:
            total += os.path.getsize(os.path.join(root, name))
    return total


def log_path(env: Mapping[str, str] = os.environ) -> Path:
    """%APPDATA%/DEFECTOR/logs/godot.log; ValueError without APPDATA."""
    appdata = env.get("APPDATA", "")
    if not appdata:
        raise ValueError("APPDATA is not set; can't find the game's godot.log")
    return Path(appdata) / "DEFECTOR" / "logs" / "godot.log"


def title_ready_ms(text: str) -> int | None:
    """The N of the first `Title ready N ms after launch` line, or None."""
    match = TITLE_READY.search(text)
    return int(match.group(1)) if match else None


def is_fresh(mtime_s: float, launch_wall_s: float) -> bool:
    """A log last written at or after the launch belongs to this run."""
    return mtime_s >= launch_wall_s


def read_fresh_log(path: Path, launch_wall_s: float) -> str | None:
    """The log's text when it exists and is fresh for this launch, else None."""
    try:
        if not is_fresh(os.stat(path).st_mtime, launch_wall_s):
            return None
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return None


def measure_launch(
    exe: Path,
    log: Path,
    timeout_s: float,
    popen: Callable[..., subprocess.Popen] = subprocess.Popen,
    clock: Callable[[], float] = time.monotonic,
    wall: Callable[[], float] = time.time,
    sleep: Callable[[float], None] = time.sleep,
) -> tuple[float | None, int | None, str | None]:
    """One run: (wall seconds to the title line, the line's engine ms, where it
    was seen: "stdout" or the log's name), or (None, None, None) when no line
    came within timeout_s or the process exited first. The process is always
    killed."""
    launch_wall = wall()
    start = clock()
    process = popen([str(exe)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    lock = threading.Lock()
    seen: list[tuple[float, int, str]] = []

    def read_stdout() -> None:
        # Drains the pipe to the end, so the game never blocks on a full pipe.
        for raw in iter(process.stdout.readline, b""):
            engine_ms = title_ready_ms(raw.decode("utf-8", errors="replace"))
            if engine_ms is not None:
                with lock:
                    if not seen:
                        seen.append((clock() - start, engine_ms, "stdout"))

    def hit() -> tuple[float, int, str] | None:
        with lock:
            return seen[0] if seen else None

    reader = threading.Thread(target=read_stdout, daemon=True)
    reader.start()
    try:
        while clock() - start < timeout_s:
            found = hit()
            if found is not None:
                return found
            text = read_fresh_log(log, launch_wall)
            if text is not None:
                engine_ms = title_ready_ms(text)
                if engine_ms is not None:
                    return clock() - start, engine_ms, log.name
            if process.poll() is not None:
                reader.join(timeout=1.0)
                found = hit()
                return found if found is not None else (None, None, None)
            sleep(POLL_S)
        return None, None, None
    finally:
        if process.poll() is None:
            process.kill()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            pass
        reader.join(timeout=2.0)


def cmd_size(folder: Path, limits: dict, out=None) -> int:
    out = out if out is not None else sys.stdout
    if not folder.is_dir():
        print(f"size: {folder} is not a folder (export the game first)", file=out)
        return 2
    total = dir_size_bytes(folder)
    mb = total / BYTES_PER_MB
    limit = float(limits["max_build_mb"])
    ok = mb < limit
    print(f"size: {folder} {total} bytes = {mb:.1f} MB (limit {limit:g} MB) -> {'PASS' if ok else 'FAIL'}", file=out)
    return 0 if ok else 1


def cmd_launch(exe: Path, runs: int, limits: dict, env: Mapping[str, str] = os.environ, out=None,
               measure: Callable[..., tuple[float | None, int | None, str | None]] = measure_launch) -> int:
    out = out if out is not None else sys.stdout
    if not exe.is_file():
        print(f"launch: {exe} is not a file (export the game first)", file=out)
        return 2
    exe = exe.resolve()  # CreateProcess can't resolve a relative path with forward slashes
    if runs < 1:
        print("launch: --runs must be at least 1", file=out)
        return 2
    try:
        log = log_path(env)
    except ValueError as error:
        print(f"launch: {error}", file=out)
        return 2
    limit = float(limits["max_launch_s"])
    timeout_s = float(limits["launch_timeout_s"])
    all_ok = True
    for run in range(1, runs + 1):
        seconds, engine_ms, source = measure(exe, log, timeout_s)
        if seconds is None:
            all_ok = False
            print(f"launch run {run}: no 'Title ready' line on stdout or in a fresh {log.name} within {timeout_s:g} s -> FAIL", file=out)
            continue
        ok = seconds < limit
        all_ok = all_ok and ok
        print(f"launch run {run}: {seconds:.2f} s to the title (engine {engine_ms} ms, seen on {source}) (limit {limit:g} s) -> {'PASS' if ok else 'FAIL'}", file=out)
    print(f"launch: {'PASS' if all_ok else 'FAIL'} ({runs} run{'s' if runs != 1 else ''})", file=out)
    return 0 if all_ok else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    size = sub.add_parser("size", help="total size of an export folder")
    size.add_argument("folder", type=Path)
    launch = sub.add_parser("launch", help="launch-to-title time of the game exe itself "
                            "(DEFECTOR.exe, never the .console.exe wrapper)")
    launch.add_argument("exe", type=Path)
    launch.add_argument("--runs", type=int, default=1)
    args = parser.parse_args(argv)
    limits = load_limits()
    if args.command == "size":
        return cmd_size(args.folder, limits)
    return cmd_launch(args.exe, args.runs, limits)


if __name__ == "__main__":
    sys.exit(main())
