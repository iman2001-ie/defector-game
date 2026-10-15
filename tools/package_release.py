"""Story 8.5: build the release zips DEFECTOR-v<version>-windows.zip and
DEFECTOR-v<version>-macos.zip.

Run from the repo root (stdlib only), after the release exports:

    uv run python tools/package_release.py
    uv run python tools/package_release.py --platform windows --exe game/export/windows/DEFECTOR.exe --out some/where.zip
    uv run python tools/package_release.py --platform macos --app game/export/macos/DEFECTOR.zip

The version is read once, from game/project.godot ([application]
config/version), the same value Godot writes into the exe's file and product
version and into the app's Info.plist. --platform picks windows, macos or all
(the default, which needs both exports); --out names the zip and only goes
with a single platform.

The Windows zip (deflate, flat, no folders) holds exactly four entries:

- DEFECTOR.exe  the release export (default game/export/windows/DEFECTOR.exe);
- README.txt    release/README.txt, the player-facing readme with the controls;
- CREDITS.txt   game/assets/CREDITS.md's text, then a "Godot Engine" heading
                and release/GODOT_COPYRIGHT.txt (the engine's MIT licence and
                the third-party notices Godot's licence-compliance docs ask a
                redistributed game to carry; regenerate it with
                tools/godot_copyright.gd), under a name Windows opens in
                Notepad;
- LICENSE.txt   the repo's LICENSE (MIT, and what it covers).

Its text entries are written with CRLF line endings.

The macOS zip (deflate) holds the app bundle and three text entries beside it:

- DEFECTOR.app/...  every member of Godot's macOS export (default
                    game/export/macos/DEFECTOR.zip: a zipped, universal,
                    ad-hoc signed .app), copied byte for byte with its Unix
                    mode and timestamp, so the executable bit and the code
                    signature survive;
- README.txt        release/README-macos.txt, the macOS player readme;
- CREDITS.txt       as above;
- LICENSE.txt       as above.

Its text entries are written with LF line endings and Unix mode 0644.

The default output is DEFECTOR-v<version>-<platform>.zip at the repo root
(gitignored by `*.zip`); an existing file there is replaced. Each zip is first
written as <zip stem>.partial.zip next to it (also ignored by `*.zip`, and
removed on a failure), then renamed into place. It prints each zip's file
entries with their sizes, then the next steps: the smoke test and the publish
command, which only the operator runs (no agent releases).

Exit 0 when every zip is written, 2 on a usage error (a missing exe, app
export, readme, credits file, licence, Godot copyright file or version, or an
app export without DEFECTOR.app/Contents/MacOS/DEFECTOR); that zip is not
written then. --out with --platform all is an argparse error (also exit 2).
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import time
import zipfile
from pathlib import Path
from typing import Callable, TextIO

REPO = Path(__file__).resolve().parent.parent
PROJECT = REPO / "game" / "project.godot"
README_TXT = REPO / "release" / "README.txt"
README_MACOS_TXT = REPO / "release" / "README-macos.txt"
GODOT_COPYRIGHT = REPO / "release" / "GODOT_COPYRIGHT.txt"
CREDITS_MD = REPO / "game" / "assets" / "CREDITS.md"
LICENSE = REPO / "LICENSE"
DEFAULT_EXE = REPO / "game" / "export" / "windows" / "DEFECTOR.exe"
DEFAULT_APP_ZIP = REPO / "game" / "export" / "macos" / "DEFECTOR.zip"
EXE_ENTRY = "DEFECTOR.exe"
README_ENTRY = "README.txt"
CREDITS_ENTRY = "CREDITS.txt"
LICENSE_ENTRY = "LICENSE.txt"
ENTRIES = (EXE_ENTRY, README_ENTRY, CREDITS_ENTRY, LICENSE_ENTRY)
APP_DIR = "DEFECTOR.app/"
APP_EXECUTABLE = APP_DIR + "Contents/MacOS/DEFECTOR"
MACOS_TEXT_ENTRIES = (README_ENTRY, CREDITS_ENTRY, LICENSE_ENTRY)
PLATFORMS = ("windows", "macos")
UNIX_SYSTEM = 3
TEXT_MODE = 0o100644
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


def zip_name(version: str, platform: str = "windows") -> str:
    return f"DEFECTOR-v{version}-{platform}.zip"


def partial_path(target: Path) -> Path:
    """<zip stem>.partial.zip next to the target, so `*.zip` ignores a leftover."""
    return target.with_name(f"{target.stem}.partial.zip")


def lf(text: str) -> str:
    """The text with every line ending as LF."""
    return text.replace("\r\n", "\n").replace("\r", "\n")


def crlf(text: str) -> bytes:
    """UTF-8 bytes with every line ending as CRLF."""
    return lf(text).replace("\n", "\r\n").encode("utf-8")


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


def missing_input(inputs: tuple[tuple[str, Path], ...], stream: TextIO) -> bool:
    """Print the first missing input and return True, or return False."""
    for label, path in inputs:
        if not path.is_file():
            hint = (" (export the game first)" if label in ("exe", "app export")
                    else " (run tools/godot_copyright.gd)" if label == "Godot copyright" else "")
            print(f"package: {label} {path} is missing{hint}; nothing written", file=stream)
            return True
    return False


def write_zip(target: Path, fill: Callable[[zipfile.ZipFile], None]) -> None:
    """Write the zip through <stem>.partial.zip, removing that on a failure."""
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = partial_path(target)
    try:
        with zipfile.ZipFile(partial, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            fill(archive)
        os.replace(partial, target)
    finally:
        if partial.exists():
            partial.unlink()


def print_listing(version: str, target: Path, stream: TextIO) -> None:
    """The zip's path, each file entry with its size, and the zip's total."""
    print(f"package: DEFECTOR v{version} -> {target}", file=stream)
    with zipfile.ZipFile(target) as archive:
        files = [info for info in archive.infolist() if not info.is_dir()]
    width = max([14, *(len(info.filename) for info in files)])
    for info in files:
        print(f"  {info.filename:<{width}} {human(info.file_size):>10} ({human(info.compress_size)} compressed)",
              file=stream)
    print(f"  {'zip total':<{width}} {human(target.stat().st_size):>10}", file=stream)


def package(exe: Path, out: Path | None, project: Path = PROJECT, readme: Path = README_TXT,
            credits: Path = CREDITS_MD, godot_copyright: Path = GODOT_COPYRIGHT,
            licence: Path = LICENSE, stream: TextIO | None = None) -> int:
    """Write the Windows zip: 0 when written, 2 on a usage error."""
    stream = stream if stream is not None else sys.stdout
    version = read_version(project)
    if version is None:
        print(f"package: no [application] config/version in {project}; nothing written", file=stream)
        return 2
    if missing_input((("exe", exe), ("readme", readme), ("credits", credits),
                      ("Godot copyright", godot_copyright), ("licence", licence)), stream):
        return 2
    target = out if out is not None else REPO / zip_name(version, "windows")

    def fill(archive: zipfile.ZipFile) -> None:
        archive.write(exe, EXE_ENTRY)
        archive.writestr(README_ENTRY, crlf(readme.read_text(encoding="utf-8")))
        archive.writestr(CREDITS_ENTRY, crlf(credits_text(credits, godot_copyright)))
        archive.writestr(LICENSE_ENTRY, crlf(licence.read_text(encoding="utf-8")))

    write_zip(target, fill)
    print_listing(version, target, stream)
    return 0


def text_info(name: str) -> zipfile.ZipInfo:
    """A ZipInfo for a text entry that a Mac unzips as a plain 0644 file."""
    info = zipfile.ZipInfo(name, date_time=time.localtime()[:6])
    info.create_system = UNIX_SYSTEM
    info.external_attr = TEXT_MODE << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    return info


def app_members(app_zip: Path) -> list[zipfile.ZipInfo]:
    """The DEFECTOR.app/ members of Godot's macOS export, or [] when it can't be read."""
    try:
        with zipfile.ZipFile(app_zip) as source:
            return [info for info in source.infolist() if info.filename.startswith(APP_DIR)]
    except (zipfile.BadZipFile, OSError):
        return []


def package_macos(app_zip: Path, out: Path | None, project: Path = PROJECT, readme: Path = README_MACOS_TXT,
                  credits: Path = CREDITS_MD, godot_copyright: Path = GODOT_COPYRIGHT,
                  licence: Path = LICENSE, stream: TextIO | None = None) -> int:
    """Write the macOS zip: 0 when written, 2 on a usage error."""
    stream = stream if stream is not None else sys.stdout
    version = read_version(project)
    if version is None:
        print(f"package: no [application] config/version in {project}; nothing written", file=stream)
        return 2
    if missing_input((("app export", app_zip), ("readme", readme), ("credits", credits),
                      ("Godot copyright", godot_copyright), ("licence", licence)), stream):
        return 2
    members = app_members(app_zip)
    if not any(info.filename == APP_EXECUTABLE for info in members):
        print(f"package: app export {app_zip} has no {APP_EXECUTABLE}; nothing written", file=stream)
        return 2
    target = out if out is not None else REPO / zip_name(version, "macos")

    def fill(archive: zipfile.ZipFile) -> None:
        with zipfile.ZipFile(app_zip) as source:
            for info in members:
                # A fresh ZipInfo keeps the name, time and Unix mode (the executable
                # bit) but drops the source's sizes and extra fields.
                copy = zipfile.ZipInfo(info.filename, date_time=info.date_time)
                copy.create_system = info.create_system
                copy.external_attr = info.external_attr
                copy.compress_type = zipfile.ZIP_STORED if info.is_dir() else zipfile.ZIP_DEFLATED
                archive.writestr(copy, source.read(info))
        texts = {README_ENTRY: readme.read_text(encoding="utf-8"),
                 CREDITS_ENTRY: credits_text(credits, godot_copyright),
                 LICENSE_ENTRY: licence.read_text(encoding="utf-8")}
        for name in MACOS_TEXT_ENTRIES:
            archive.writestr(text_info(name), lf(texts[name]).encode("utf-8"))

    write_zip(target, fill)
    print_listing(version, target, stream)
    return 0


def print_next_steps(version: str, targets: list[Path], stream: TextIO) -> None:
    zips = " ".join(display_path(target) for target in targets)
    print("", file=stream)
    print("Next steps:", file=stream)
    print("  1. Smoke test the Windows zip: unzip it into an empty folder, then", file=stream)
    print("     uv run python tools/perf_check.py launch <folder>/DEFECTOR.exe --runs 3", file=stream)
    print("     and play through Level 1 from that folder. The macOS zip can only be tried on a Mac.", file=stream)
    print("  2. Operator only, after explicit confirmation (an agent never runs it):", file=stream)
    print(f'     gh release create v{version} {zips} --title "DEFECTOR v{version}" '
          "--notes-file RELEASE_NOTES.md", file=stream)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--platform", choices=(*PLATFORMS, "all"), default="all",
                        help="the zip to build (default all, which needs both exports)")
    parser.add_argument("--exe", type=Path, default=DEFAULT_EXE, help="the Windows release export's DEFECTOR.exe")
    parser.add_argument("--app", type=Path, default=DEFAULT_APP_ZIP,
                        help="the macOS release export, Godot's zipped DEFECTOR.app")
    parser.add_argument("--out", type=Path, default=None,
                        help="the zip to write, with a single --platform "
                             "(default DEFECTOR-v<version>-<platform>.zip at the repo root)")
    args = parser.parse_args(argv)
    if args.out is not None and args.platform == "all":
        parser.error("--out needs --platform windows or --platform macos")
    version = read_version(PROJECT)
    if version is None:
        print(f"package: no [application] config/version in {PROJECT}; nothing written")
        return 2
    platforms = PLATFORMS if args.platform == "all" else (args.platform,)
    targets: list[Path] = []
    for platform in platforms:
        target = args.out if args.out is not None else REPO / zip_name(version, platform)
        code = package(args.exe, target) if platform == "windows" else package_macos(args.app, target)
        if code != 0:
            return code
        targets.append(target)
    print_next_steps(version, targets, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
