"""Story 8.4: audit playthrough logs (godot.log) for the campaign's story beats.

Run from the repo root (stdlib only):

    uv run python tools/beat_audit.py --latest 3
    uv run python tools/beat_audit.py path/to/godot.log [more logs ...]
    uv run python tools/beat_audit.py --latest 1 --allow-debug

With no paths it audits the N newest godot*.log files (by modification time,
`--latest N`, default 1) in %APPDATA%/DEFECTOR/logs (path from the APPDATA
environment variable: project.godot's custom user dir "DEFECTOR" with file
logging on). Godot copies the previous godot.log to godot<timestamp>.log on
every launch and keeps 5, so one launch is one run and `--latest 3` audits the
last three launches. Release builds buffer the file log until the game exits,
so quit the game before auditing.

A run (one log file) passes when all of these hold:
- it is a release build: the `[INFO][boot] Build: release` line (boot.gd).
  `Build: debug` or no build line fails, unless --allow-debug turns that into
  a note;
- it started from a fresh save: the first `[...][save]` line is
  `No save at ...` (SaveManager, logged when the title first loads progress);
- every required beat in MANIFEST fired and their first occurrences are in
  manifest order (retries repeat beats, so only the first occurrence counts).
  A beat gated by a game/data/flags.json flag that is off is reported as
  `skipped (flag off)`, not missing;
- it reached the end screen (the last required beat);
- the log has no errors: lines starting `[ERROR]`, `ERROR:`, `SCRIPT ERROR:`
  or `SHADER ERROR:`, any line containing `Program crashed` (Godot's crash
  handler), and the INFO line saying Tarek's fall was skipped. WARN lines are
  only counted.

Each run's block lists every required beat (ok / MISSING / OUT OF ORDER /
skipped (flag off)), the attempts per level (`Level N '...' started` lines,
retries included), the time to the end screen, the choices picked, each
attempt's `Kills: ...` ally kill-share line (`kill share: <message>`, in log
order, or `kill share: none`; information only, never a failure), the
warning and error counts (the first 10 errors listed) and `result=PASS` or
`result=FAIL: <reasons>`. With `--latest N` and fewer than N logs found, each
missing log counts as a FAIL. Exit 0 when every run passes, 1 when any fails
(or a log is missing), 2 on a usage error (no logs, no APPDATA, a missing
file).

The beat lines are a contract with the game's GDScript (wave_director.gd,
story.gd, comms_channel.gd, end_screen.gd, boot.gd); tools/test_beat_audit.py
checks the format strings and that every sequence id here exists in game/data.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Mapping, TextIO

REPO = Path(__file__).resolve().parent.parent
FLAGS = REPO / "game" / "data" / "flags.json"
LOG_GLOB = "godot*.log"
MAX_LISTED_ERRORS = 10

OK = "ok"
MISSING = "MISSING"
OUT_OF_ORDER = "OUT OF ORDER"
SKIPPED = "skipped (flag off)"

LOG_LINE = re.compile(r"^\[(DEBUG|INFO|WARN|ERROR)\]\[(\w+)\] (.*)$")
BUILD = re.compile(r"Build: (release|debug)")
LEVEL_STARTED = re.compile(r"Level (\d+) '.*' started \(")
END_SCREEN = re.compile(r"End screen: campaign finished (\d+) s after launch \(final choice '([^']*)'\)")
CHOICE = re.compile(r"Choice '([^']*)' picked in '([^']*)'")
TAREK_SKIPPED = "Tarek's fall: no patrolling Tarek; scene skipped"
# Godot's crash handler ("... Program crashed with signal ...").
CRASHED = "Program crashed"
KILL_SHARE = re.compile(r"Kills: \d+ total, ally \d+ \(\d+%\); target .*")
CAMPAIGN_LEVELS = (1, 2, 3)


@dataclass(frozen=True)
class Beat:
    """One required beat: `pattern` must fullmatch the message of an
    `[INFO][beat]` line. `flag` is the flags.json key that gates it (None:
    always required). `sequence` / `event` and `level` tie it to game/data for
    the drift test (the level file that references it; None for scene-flow
    beats)."""

    label: str
    pattern: re.Pattern
    flag: str | None = None
    sequence: str | None = None
    event: str | None = None
    level: int | None = None


def _comms(level: int, sequence: str) -> re.Pattern:
    # WaveDirector: "Level %d wave %d: comms '%s'" (the wave number matched loosely).
    return re.compile(rf"Level {level} wave \d+: comms '{re.escape(sequence)}'")


MANIFEST: tuple[Beat, ...] = (
    Beat("Opening: Story 'opening_main'", re.compile(r"Story 'opening_main'"), sequence="opening_main"),
    Beat("L1 Isolde's interruption: comms 'l1_w3_isolde_interrupt'", _comms(1, "l1_w3_isolde_interrupt"),
         flag="isolde_interruptions", sequence="l1_w3_isolde_interrupt", level=1),
    Beat("L1 surrender prompt: comms 'l1_w5_surrender'", _comms(1, "l1_w5_surrender"),
         flag="surrender_prompts", sequence="l1_w5_surrender", level=1),
    Beat("L2 Isolde's interruption: comms 'l2_w3_isolde_interrupt'", _comms(2, "l2_w3_isolde_interrupt"),
         flag="isolde_interruptions", sequence="l2_w3_isolde_interrupt", level=2),
    Beat("L2 Tarek's fall: story event 'tarek_fall'", re.compile(r"Level 2 wave \d+: story event 'tarek_fall'"),
         flag="tarek_fall", event="tarek_fall", level=2),
    Beat("L2 Ryn's report: outro 'l2_ryn_report'", re.compile(r"Level 2 outro 'l2_ryn_report'"),
         sequence="l2_ryn_report", level=2),
    Beat("L3 Isolde's taunt: comms 'l3_w3_isolde_taunt'", _comms(3, "l3_w3_isolde_taunt"),
         flag="isolde_interruptions", sequence="l3_w3_isolde_taunt", level=3),
    Beat("L3 Final Choice: Choice picked in 'l3_final_choice'", re.compile(r"Choice '[^']+' picked in 'l3_final_choice'"),
         sequence="l3_final_choice", level=3),
    Beat("L3 Isolde's final line: outro 'l3_isolde_final'", re.compile(r"Level 3 outro 'l3_isolde_final'"),
         sequence="l3_isolde_final", level=3),
    Beat("Epilogue: Story 'ending_council'", re.compile(r"Story 'ending_council'"),
         flag="council_epilogue", sequence="ending_council"),
    Beat("End screen: campaign finished", re.compile(END_SCREEN.pattern)),
)
END_BEAT = MANIFEST[-1]


@dataclass
class Report:
    """One audited log."""

    build: str | None = None
    fresh: bool = False
    save_line: str | None = None
    beats: list[tuple[str, str]] = field(default_factory=list)
    attempts: dict[int, int] = field(default_factory=dict)
    end_s: int | None = None
    choices: list[tuple[str, str]] = field(default_factory=list)
    kill_shares: list[str] = field(default_factory=list)
    warnings: int = 0
    errors: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)
    reasons: list[str] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return not self.reasons


def load_flags(path: Path = FLAGS) -> dict:
    """game/data/flags.json as a dict."""
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def log_dir(env: Mapping[str, str] = os.environ) -> Path:
    """%APPDATA%/DEFECTOR/logs; ValueError without APPDATA."""
    appdata = env.get("APPDATA", "")
    if not appdata:
        raise ValueError("APPDATA is not set; can't find the game's logs")
    return Path(appdata) / "DEFECTOR" / "logs"


def latest_logs(folder: Path, count: int) -> list[Path]:
    """The `count` newest godot*.log files in `folder` by mtime, oldest first."""
    if not folder.is_dir():
        return []
    logs = [path for path in folder.glob(LOG_GLOB) if path.is_file()]
    logs.sort(key=lambda path: path.stat().st_mtime, reverse=True)
    return sorted(logs[:count], key=lambda path: path.stat().st_mtime)


def _is_error(line: str) -> bool:
    if line.startswith(("[ERROR]", "SCRIPT ERROR:", "SHADER ERROR:")) or CRASHED in line:
        return True
    if line.startswith("ERROR:"):
        # Log.error also calls push_error, which repeats its `[ERROR]...` line
        # as `ERROR: [ERROR]...`: that one is already listed.
        return not line[len("ERROR:"):].lstrip().startswith("[ERROR]")
    return False


def _is_warning(line: str) -> bool:
    if line.startswith("[WARN]"):
        return True
    if line.startswith("WARNING:"):
        return not line[len("WARNING:"):].lstrip().startswith("[WARN]")
    return False


def audit(text: str, flags: Mapping[str, object], allow_debug: bool = False) -> Report:
    """Audits one log's text against MANIFEST with the given flags."""
    report = Report()
    report.attempts = {level: 0 for level in CAMPAIGN_LEVELS}
    beat_lines: list[tuple[int, str]] = []
    for number, raw in enumerate(text.splitlines()):
        line = raw.rstrip()
        if _is_error(line):
            report.errors.append(line)
        elif _is_warning(line):
            report.warnings += 1
        match = LOG_LINE.match(line)
        if match is None:
            continue
        level, category, message = match.groups()
        if category == "boot" and report.build is None:
            build = BUILD.fullmatch(message)
            if build is not None:
                report.build = build.group(1)
        elif category == "save" and report.save_line is None:
            report.save_line = message
        elif category == "scene" and level == "INFO":
            started = LEVEL_STARTED.match(message)
            if started is not None and int(started.group(1)) in report.attempts:
                report.attempts[int(started.group(1))] += 1
            if message == TAREK_SKIPPED:
                report.errors.append(line)
        elif category == "combat" and level == "INFO" and KILL_SHARE.fullmatch(message):
            report.kill_shares.append(message)
        elif category == "beat" and level == "INFO":
            beat_lines.append((number, message))
            choice = CHOICE.fullmatch(message)
            if choice is not None:
                report.choices.append((choice.group(1), choice.group(2)))
            end = END_SCREEN.fullmatch(message)
            if end is not None and report.end_s is None:
                report.end_s = int(end.group(1))

    first: dict[int, int] = {}
    for index, beat in enumerate(MANIFEST):
        for number, message in beat_lines:
            if beat.pattern.fullmatch(message):
                first[index] = number
                break
    latest = -1
    missing = 0
    out_of_order = 0
    for index, beat in enumerate(MANIFEST):
        if beat.flag is not None and not bool(flags.get(beat.flag, True)):
            report.beats.append((beat.label, SKIPPED))
            continue
        position = first.get(index)
        if position is None:
            report.beats.append((beat.label, MISSING))
            missing += 1
            continue
        if position < latest:
            report.beats.append((beat.label, OUT_OF_ORDER))
            out_of_order += 1
        else:
            report.beats.append((beat.label, OK))
        latest = max(latest, position)

    report.fresh = report.save_line is not None and report.save_line.startswith("No save at")
    if report.build != "release":
        if allow_debug:
            report.notes.append("not a release build (allowed by --allow-debug)")
        else:
            report.reasons.append("not a release build")
    if report.save_line is None:
        report.reasons.append("no save line (fresh save not proven)")
    elif not report.fresh:
        report.reasons.append("not a fresh save")
    if missing:
        report.reasons.append(f"{missing} beat{'s' if missing != 1 else ''} missing")
    if out_of_order:
        report.reasons.append(f"{out_of_order} beat{'s' if out_of_order != 1 else ''} out of order")
    if (END_BEAT.label, MISSING) in report.beats:
        report.reasons.append("never reached the end screen")
    if report.errors:
        report.reasons.append(f"{len(report.errors)} error{'s' if len(report.errors) != 1 else ''} in the log")
    return report


def format_report(name: str, report: Report) -> str:
    """The text block for one audited log."""
    out = [f"== {name} =="]
    out.append(f"build: {report.build if report.build is not None else 'unknown (no Build line)'}")
    if report.save_line is None:
        out.append("fresh save: NO (no save line)")
    else:
        out.append(f"fresh save: {'yes' if report.fresh else 'NO'} (first save line: {report.save_line})")
    out.append("beats:")
    width = max(len(status) for status in (OK, MISSING, OUT_OF_ORDER, SKIPPED))
    for label, status in report.beats:
        out.append(f"  {status:<{width}}  {label}")
    out.append("attempts " + " ".join(f"L{level}={count}" for level, count in sorted(report.attempts.items())))
    out.append(f"time to end screen {report.end_s} s" if report.end_s is not None else "time to end screen n/a")
    if report.choices:
        out.append("choices picked: " + ", ".join(f"'{choice}' in {sequence}" for choice, sequence in report.choices))
    else:
        out.append("choices picked: none")
    if report.kill_shares:
        out.extend(f"kill share: {message}" for message in report.kill_shares)
    else:
        out.append("kill share: none")
    out.append(f"warnings: {report.warnings}")
    if report.errors:
        listed = min(len(report.errors), MAX_LISTED_ERRORS)
        out.append(f"errors: {len(report.errors)} (first {listed} listed)")
        out.extend(f"  {line}" for line in report.errors[:MAX_LISTED_ERRORS])
    else:
        out.append("errors: 0")
    for note in report.notes:
        out.append(f"note: {note}")
    out.append("result=PASS" if report.passed else "result=FAIL: " + "; ".join(report.reasons))
    return "\n".join(out)


def main(argv: list[str] | None = None, env: Mapping[str, str] = os.environ, out: TextIO | None = None,
         flags: Mapping[str, object] | None = None) -> int:
    out = out if out is not None else sys.stdout
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("logs", nargs="*", type=Path, help="log files to audit (default: the newest in APPDATA)")
    parser.add_argument("--latest", type=int, default=None, metavar="N",
                        help="audit the N newest godot*.log in %%APPDATA%%/DEFECTOR/logs (default 1)")
    parser.add_argument("--allow-debug", action="store_true", help="a debug build is a note, not a failure")
    args = parser.parse_args(argv)
    if args.logs and args.latest is not None:
        print("beat_audit: give log paths or --latest, not both", file=out)
        return 2
    shortfall = 0
    if args.logs:
        logs = list(args.logs)
        missing = [path for path in logs if not path.is_file()]
        if missing:
            print("beat_audit: no such log: " + ", ".join(str(path) for path in missing), file=out)
            return 2
    else:
        count = args.latest if args.latest is not None else 1
        if count < 1:
            print("beat_audit: --latest must be at least 1", file=out)
            return 2
        try:
            folder = log_dir(env)
        except ValueError as error:
            print(f"beat_audit: {error}", file=out)
            return 2
        logs = latest_logs(folder, count)
        if not logs:
            print(f"beat_audit: no {LOG_GLOB} in {folder} (play the game first)", file=out)
            return 2
        if len(logs) < count:
            shortfall = count - len(logs)
            print(f"beat_audit: only {len(logs)} log{'s' if len(logs) != 1 else ''} in {folder}, {count} asked; "
                  f"each missing log counts as a FAIL", file=out)
    flags = flags if flags is not None else load_flags()
    passed = 0
    for path in logs:
        with open(path, encoding="utf-8", errors="replace") as handle:
            report = audit(handle.read(), flags, args.allow_debug)
        print(format_report(str(path), report), file=out)
        print("", file=out)
        passed += 1 if report.passed else 0
    failed = len(logs) - passed + shortfall
    missing_note = f" ({shortfall} missing log{'s' if shortfall != 1 else ''} counted as FAIL)" if shortfall else ""
    print(f"beat_audit: {len(logs)} log{'s' if len(logs) != 1 else ''} audited, {passed} PASS, {failed} FAIL{missing_note}",
          file=out)
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
