"""Story 8.5: build the release zip DEFECTOR-v<version>-windows.zip.

Run from the repo root (stdlib only), after the release export:

    uv run python tools/package_release.py
    uv run python tools/package_release.py --exe game/export/windows/DEFECTOR.exe --out some/where.zip

The version is read once, from game/project.godot ([application]
config/version), the same value Godot writes into the exe's file and product
version. The zip (deflate, flat, no folders) holds exactly three entries:

- DEFECTOR.exe  the release export (default game/export/windows/DEFECTOR.exe);
- README.txt    release/README.txt, the player-facing readme with the controls;
- CREDITS.txt   game/assets/CREDITS.md's text, then a "Godot Engine" heading
                and release/GODOT_COPYRIGHT.txt (the engine's MIT licence and
                the third-party notices Godot's licence-compliance docs ask a
                redistributed game to carry; regenerate it with
                tools/godot_copyright.gd), under a name Windows opens in
                Notepad.

Both text entries are written with CRLF line endings. The default output is
DEFECTOR-v<version>-windows.zip at the repo root (gitignored by `*.zip`); an
existing file there is replaced. The zip is first written as
<zip stem>.partial.zip next to it (also ignored by `*.zip`, and removed on a
failure), then renamed into place. It prints each entry with its size, then
the next steps: the smoke test and the publish command, which only the
operator runs (no agent pushes or releases).

Exit 0 when the zip is written, 2 on a usage error (a missing exe, readme,
credits file, Godot copyright file or version); nothing is written then.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import zipfile
from pathlib import Path
from typing import TextIO

REPO = Path(__file__).resolve().parent.parent
PROJECT = REPO / "game" / "project.godot"
README_TXT = REPO / "release" / "README.txt"
GODOT_COPYRIGHT = REPO / "release" / "GODOT_COPYRIGHT.txt"
CREDITS_MD = REPO / "game" / "assets" / "CREDITS.md"
DEFAULT_EXE = REPO / "game" / "export" / "windows" / "DEFECTOR.exe"
EXE_ENTRY = "DEFECTOR.exe"
README_ENTRY = "README.txt"
CREDITS_ENTRY = "CREDITS.txt"
ENTRIES = (EXE_ENTRY, README_ENTRY, CREDITS_ENTRY)
GODOT_HEADING = (
    "# Godot Engine\n\n"
    "DEFECTOR is made with the Godot Engine (https://godotengine.org). Its licence and the\n"
    "notices of the third-party code compiled into it follow.\n\n"
)

SECTION = re.compile(r"^\s*\[([^\]]+)\]\s*$")
VERSION_KEY = re.compile(r'^\s*config/version\s*=\s*"([^"]*)"\s*$')


def read_version(project: Path) -> str | None:
    """The [application] config/version string of a project.godot, or None
    when the file, the key or a non-empty value is missing."""
    try:
        text = project.read_text(encoding="utf-8")
    except OSError:
        return None
    section = ""
    for line in text.splitlines():
        header = SECTION.match(line)
        if header:
            section = header.group(1)
            continue
        if section == "application":
            match = VERSION_KEY.match(line)
            if match and match.group(1).strip():
                return match.group(1).strip()
    return None


def zip_name(version: str) -> str:
    return f"DEFECTOR-v{version}-windows.zip"


def partial_path(target: Path) -> Path:
    """<zip stem>.partial.zip next to the target, so `*.zip` ignores a leftover."""
    return target.with_name(f"{target.stem}.partial.zip")


def crlf(text: str) -> bytes:
    """UTF-8 bytes with every line ending as CRLF."""
    return text.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\r\n").encode("utf-8")


def credits_text(credits: Path, godot_copyright: Path) -> str:
    """CREDITS.md, then the Godot Engine heading, then GODOT_COPYRIGHT.txt."""
    assets = credits.read_text(encoding="utf-8").rstrip() + "\n\n\n"
    return assets + GODOT_HEADING + godot_copyright.read_text(encoding="utf-8")


def display_path(path: Path) -> str:
    """The path relative to the current directory, or absolute when it is
    elsewhere; quoted when it holds a space."""
    resolved = path.resolve()
    try:
        shown = str(resolved.relative_to(Path.cwd().resolve()))
    except ValueError:
        shown = str(resolved)
    return f'"{shown}"' if " " in shown else shown


def human(size: int) -> str:
    return f"{size / 1_000_000:.1f} MB" if size >= 1_000_000 else f"{size / 1000:.1f} KB"


def package(exe: Path, out: Path | None, project: Path = PROJECT, readme: Path = README_TXT,
            credits: Path = CREDITS_MD, godot_copyright: Path = GODOT_COPYRIGHT,
            stream: TextIO | None = None) -> int:
    stream = stream if stream is not None else sys.stdout
    version = read_version(project)
    if version is None:
        print(f"package: no [application] config/version in {project}; nothing written", file=stream)
        return 2
    inputs = (("exe", exe), ("readme", readme), ("credits", credits), ("Godot copyright", godot_copyright))
    for label, path in inputs:
        if not path.is_file():
            hint = (" (export the game first)" if label == "exe"
                    else " (run tools/godot_copyright.gd)" if label == "Godot copyright" else "")
            print(f"package: {label} {path} is missing{hint}; nothing written", file=stream)
            return 2
    target = out if out is not None else REPO / zip_name(version)
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = partial_path(target)
    try:
        with zipfile.ZipFile(partial, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            archive.write(exe, EXE_ENTRY)
            archive.writestr(README_ENTRY, crlf(readme.read_text(encoding="utf-8")))
            archive.writestr(CREDITS_ENTRY, crlf(credits_text(credits, godot_copyright)))
        os.replace(partial, target)
    finally:
        if partial.exists():
            partial.unlink()
    print(f"package: DEFECTOR v{version} -> {target}", file=stream)
    with zipfile.ZipFile(target) as archive:
        for info in archive.infolist():
            print(f"  {info.filename:<14} {human(info.file_size):>10} ({human(info.compress_size)} compressed)",
                  file=stream)
    print(f"  zip total      {human(target.stat().st_size):>10}", file=stream)
    print("", file=stream)
    print("Next steps:", file=stream)
    print("  1. Smoke test: unzip into an empty folder, then", file=stream)
    print("     uv run python tools/perf_check.py launch <folder>/DEFECTOR.exe --runs 3", file=stream)
    print("     and play through Level 1 from that folder.", file=stream)
    print("  2. Operator only, after explicit confirmation (an agent never runs it):", file=stream)
    print(f'     gh release create v{version} {display_path(target)} --title "DEFECTOR v{version}" '
          "--notes-file RELEASE_NOTES.md", file=stream)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--exe", type=Path, default=DEFAULT_EXE, help="the release export's DEFECTOR.exe")
    parser.add_argument("--out", type=Path, default=None,
                        help="the zip to write (default DEFECTOR-v<version>-windows.zip at the repo root)")
    args = parser.parse_args(argv)
    return package(args.exe, args.out)


if __name__ == "__main__":
    sys.exit(main())
