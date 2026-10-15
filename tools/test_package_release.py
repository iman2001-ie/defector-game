"""Tests for tools/package_release.py and the release docs (Story 8.5).
Stdlib unittest only; a fake exe and a fake app export in a temp dir, no real
export needed.

Run from the repo root:  uv run python -m unittest tools/test_package_release.py
"""

from __future__ import annotations

import contextlib
import io
import re
import shutil
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import package_release as tool  # noqa: E402

PROJECT_TEXT = '[gd_config]\n\n[application]\n\nconfig/name="DEFECTOR"\nconfig/version="1.0"\nrun/main_scene="res://x.tscn"\n'
README_TEXT = "DEFECTOR\nControls\n"
CREDITS_TEXT = "# Asset Credits\n\n| File | Source | Licence |\n"
COPYRIGHT_TEXT = "Godot Engine 4.7.2\r\n\r\nCopyright (c) 2014-present Godot Engine contributors.\r\nComment: The FreeType Project\r\n"
LICENSE_TEXT = "MIT License\n\nCopyright (c) 2026 someone\n"
MACOS_README_TEXT = "DEFECTOR for macOS\r\nOpen Anyway\r\n"
EXE_BYTES = b"MZ" + bytes(range(256)) * 64
APP_BINARY = b"\xca\xfe\xba\xbe" + bytes(range(256)) * 64
PLIST = b"<?xml version=\"1.0\"?><plist><dict></dict></plist>\n"

# Each control, the words that must share its line in the docs (case-insensitive).
CONTROLS = {
    "Mouse": ["cursor"],
    "LMB": ["laser"],
    "RMB": ["missile"],
    "E": ["shield", "50"],
    "Q": ["barrage", "100"],
    "Esc": ["pause"],
    "F11": ["fullscreen"],
}
SAVE_DIR = "%APPDATA%\\DEFECTOR"
MACOS_SAVE_DIR = "~/Library/Application Support/DEFECTOR/"
# Wording the public docs must not use: Tarek is not the player's mentor, and
# this personal project doesn't ask for bug reports.
BANNED_PHRASES = ("mentor", "report a bug", "open an issue", "issues tab", "../../issues", "found a bug")
# Pre-implementation control wording that no doc may still use.
STALE_PHRASES = ("chases the mouse", "chases the cursor", "toward the cursor")


class PackageTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())
        self.exe = self.write("export/DEFECTOR.exe", EXE_BYTES)
        self.project = self.write("project.godot", PROJECT_TEXT.encode())
        self.readme = self.write("README.txt", README_TEXT.encode())
        self.credits = self.write("CREDITS.md", CREDITS_TEXT.encode())
        self.copyright = self.write("GODOT_COPYRIGHT.txt", COPYRIGHT_TEXT.encode())
        self.licence = self.write("LICENSE", LICENSE_TEXT.encode())
        self.out = self.dir / "out" / "release.zip"

    def tearDown(self) -> None:
        shutil.rmtree(self.dir, ignore_errors=True)

    def write(self, rel: str, data: bytes) -> Path:
        path = self.dir / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def run_package(self, exe: Path | None = None, project: Path | None = None,
                    out: Path | None = None, default_out: bool = False) -> tuple[int, str]:
        stream = io.StringIO()
        code = tool.package(exe or self.exe, None if default_out else (out or self.out),
                            project=project or self.project, readme=self.readme, credits=self.credits,
                            godot_copyright=self.copyright, licence=self.licence, stream=stream)
        return code, stream.getvalue()

    def test_package_ok_writes_exactly_four_flat_entries(self) -> None:
        code, text = self.run_package()
        self.assertEqual(code, 0, text)
        with zipfile.ZipFile(self.out) as archive:
            self.assertEqual(sorted(archive.namelist()), sorted(tool.ENTRIES))
            for info in archive.infolist():
                self.assertEqual(info.compress_type, zipfile.ZIP_DEFLATED, info.filename)
                self.assertNotIn("/", info.filename)
            self.assertEqual(archive.read("DEFECTOR.exe"), EXE_BYTES)
            self.assertEqual(archive.read("README.txt"), b"DEFECTOR\r\nControls\r\n")
            self.assertEqual(archive.read("LICENSE.txt"), b"MIT License\r\n\r\nCopyright (c) 2026 someone\r\n")
            credits = archive.read("CREDITS.txt")
            self.assertNotIn(b"\n", credits.replace(b"\r\n", b""), "CRLF line endings only")
        for entry in tool.ENTRIES:
            self.assertRegex(text, rf"{re.escape(entry)}\s+[\d.]+ [KM]B")
        self.assertIn("DEFECTOR v1.0", text)
        self.assertEqual(sorted(path.name for path in self.out.parent.iterdir()), ["release.zip"],
                         "no partial file left")

    def test_credits_hold_the_asset_credits_then_the_godot_notices(self) -> None:
        self.assertEqual(self.run_package()[0], 0)
        with zipfile.ZipFile(self.out) as archive:
            credits = archive.read("CREDITS.txt").decode("utf-8").replace("\r\n", "\n")
        self.assertTrue(credits.startswith(CREDITS_TEXT.rstrip()), "the asset credits come first")
        heading = credits.index("# Godot Engine")
        notices = credits.index("Copyright (c) 2014-present Godot Engine contributors.")
        self.assertLess(credits.index("| File | Source | Licence |"), heading)
        self.assertLess(heading, notices)
        self.assertIn("The FreeType Project", credits)

    def test_existing_zip_is_replaced(self) -> None:
        self.write("out/release.zip", b"old")
        self.assertEqual(self.run_package()[0], 0)
        with zipfile.ZipFile(self.out) as archive:
            self.assertEqual(len(archive.namelist()), 4)

    def test_each_missing_input_is_a_usage_error_and_writes_nothing(self) -> None:
        for label, attr in (("exe", "exe"), ("readme", "readme"), ("credits", "credits"),
                            ("Godot copyright", "copyright"), ("licence", "licence")):
            with self.subTest(missing=label):
                original: Path = getattr(self, attr)
                missing = original.with_name("missing-" + original.name)
                setattr(self, attr, missing)
                try:
                    code, text = self.run_package()
                finally:
                    setattr(self, attr, original)
                self.assertEqual(code, 2, text)
                self.assertIn(f"package: {label} {missing} is missing", text)
                self.assertFalse(self.out.parent.exists(), "nothing written")

    def test_missing_version_is_a_usage_error_and_writes_nothing(self) -> None:
        for body in ('[application]\nconfig/name="DEFECTOR"\n',
                     '[application]\nconfig/version=""\n',
                     '[other]\nconfig/version="1.0"\n[application]\nconfig/name="x"\n'):
            with self.subTest(body=body):
                project = self.write("bad.godot", body.encode())
                code, text = self.run_package(project=project)
                self.assertEqual(code, 2)
                self.assertIn("config/version", text)
                self.assertFalse(self.out.exists())

    def test_a_failed_write_leaves_no_partial_zip(self) -> None:
        original = tool.crlf

        def broken(_text: str) -> bytes:
            raise OSError("disk full")

        tool.crlf = broken
        try:
            with self.assertRaises(OSError):
                self.run_package()
        finally:
            tool.crlf = original
        self.assertEqual(list(self.out.parent.iterdir()), [], "neither the zip nor a .partial.zip")

    def test_partial_name_is_ignored_by_the_zip_rule(self) -> None:
        partial = tool.partial_path(Path("x") / "DEFECTOR-v1.0-windows.zip")
        self.assertEqual(partial.name, "DEFECTOR-v1.0-windows.partial.zip")
        self.assertTrue(partial.name.endswith(".zip"), ".gitignore's *.zip covers a leftover")

    def test_default_out_is_the_versioned_zip_at_the_repo_root(self) -> None:
        original = tool.REPO
        tool.REPO = self.dir
        try:
            code, text = self.run_package(default_out=True)
        finally:
            tool.REPO = original
        self.assertEqual(code, 0, text)
        target = self.dir / "DEFECTOR-v1.0-windows.zip"
        self.assertTrue(target.is_file())
        self.assertIn(str(target), text)

    def test_next_steps_name_the_smoke_test_and_every_zip_in_one_gh_command(self) -> None:
        stream = io.StringIO()
        windows, macos = self.dir / "DEFECTOR-v1.0-windows.zip", self.dir / "DEFECTOR-v1.0-macos.zip"
        tool.print_next_steps("1.0", [windows, macos], stream)
        text = stream.getvalue()
        self.assertIn("perf_check.py launch", text)
        gh_lines = [line for line in text.splitlines() if "gh release create" in line]
        self.assertEqual(len(gh_lines), 1)
        self.assertRegex(gh_lines[0], r'gh release create v1\.0 \S*DEFECTOR-v1\.0-windows\.zip '
                                      r'\S*DEFECTOR-v1\.0-macos\.zip --title "DEFECTOR v1\.0" '
                                      r'--notes-file RELEASE_NOTES\.md')
        self.assertIn(str(windows.resolve()), gh_lines[0], "outside the current directory the path is absolute")

    def test_display_path_is_relative_inside_the_current_directory(self) -> None:
        self.assertEqual(tool.display_path(Path.cwd() / "DEFECTOR-v1.0-windows.zip"), "DEFECTOR-v1.0-windows.zip")
        self.assertEqual(tool.display_path(Path.cwd() / "a b.zip"), '"a b.zip"')

    def run_main(self, argv: list[str]) -> tuple[int, list[tuple[str, Path | None]]]:
        captured: list[tuple[str, Path | None]] = []
        originals = tool.package, tool.package_macos
        tool.package = lambda exe, out: captured.append(("windows", out)) or 0
        tool.package_macos = lambda app, out: captured.append(("macos", out)) or 0
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                code = tool.main(argv)
        finally:
            tool.package, tool.package_macos = originals
        return code, captured

    def test_main_builds_both_zips_by_default_under_their_versioned_names(self) -> None:
        code, captured = self.run_main(["--exe", str(self.exe)])
        self.assertEqual(code, 0)
        self.assertEqual(captured, [("windows", tool.REPO / "DEFECTOR-v1.0-windows.zip"),
                                    ("macos", tool.REPO / "DEFECTOR-v1.0-macos.zip")])

    def test_main_builds_one_platform_with_out(self) -> None:
        code, captured = self.run_main(["--platform", "macos", "--out", str(self.out)])
        self.assertEqual(code, 0)
        self.assertEqual(captured, [("macos", self.out)])

    def test_main_rejects_out_with_every_platform(self) -> None:
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as raised:
            tool.main(["--out", str(self.out)])
        self.assertEqual(raised.exception.code, 2)

    def test_read_version_and_default_name(self) -> None:
        self.assertEqual(tool.read_version(self.project), "1.0")
        self.assertIsNone(tool.read_version(self.dir / "missing.godot"))
        self.assertEqual(tool.zip_name("1.0"), "DEFECTOR-v1.0-windows.zip")
        self.assertEqual(tool.zip_name("1.0", "macos"), "DEFECTOR-v1.0-macos.zip")

    def test_the_real_project_has_version_1_0(self) -> None:
        self.assertEqual(tool.read_version(tool.PROJECT), "1.0")

    def test_the_real_godot_copyright_holds_the_engine_and_third_party_notices(self) -> None:
        raw = tool.GODOT_COPYRIGHT.read_bytes()
        self.assertNotIn(b"\n", raw.replace(b"\r\n", b""), "CRLF line endings only")
        text = raw.decode("utf-8")
        for phrase in ("Godot Engine contributors", "Permission is hereby granted", "FreeType", "mbedtls", "ENet"):
            self.assertIn(phrase.lower(), text.lower(), phrase)
        lines = text.split("\r\n")
        # A licence text block is a `License: <name>` line followed by indented text;
        # a component's `License:` line is followed by a blank line or the next field.
        blocks: dict[str, list[str]] = {}
        used: set[str] = set()
        for index, line in enumerate(lines):
            if not line.startswith("License: "):
                continue
            name = line[len("License: "):].strip()
            body: list[str] = []
            for following in lines[index + 1:]:
                if not following.startswith(" "):
                    break
                body.append(following)
            if body:
                blocks[name] = body
            else:
                used.update(part.strip(" ,") for part in re.split(r"\s+(?:and|or)\s+|,", name) if part.strip(" ,"))
        self.assertIn("FTL", blocks, "the FreeType licence text block")
        self.assertIn("The FreeType Project LICENSE", "\n".join(blocks["FTL"]))
        self.assertIn("Expat", used)
        self.assertEqual(sorted(used - set(blocks)), [], "every component licence has its text block")


def app_entry(name: str, mode: int) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, date_time=(2026, 10, 15, 9, 56, 0))
    info.create_system = 3
    info.external_attr = mode << 16
    return info


class PackageMacosTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())
        self.app = self.dir / "export" / "DEFECTOR.zip"
        self.app.parent.mkdir(parents=True)
        self.write_app({"DEFECTOR.app/Contents/MacOS/DEFECTOR": (APP_BINARY, 0o100755),
                        "DEFECTOR.app/Contents/Info.plist": (PLIST, 0o100644)})
        self.project = self.write("project.godot", PROJECT_TEXT.encode())
        self.readme = self.write("README-macos.txt", MACOS_README_TEXT.encode())
        self.credits = self.write("CREDITS.md", CREDITS_TEXT.encode())
        self.copyright = self.write("GODOT_COPYRIGHT.txt", COPYRIGHT_TEXT.encode())
        self.licence = self.write("LICENSE", LICENSE_TEXT.encode())
        self.out = self.dir / "out" / "release-macos.zip"

    def tearDown(self) -> None:
        shutil.rmtree(self.dir, ignore_errors=True)

    def write(self, rel: str, data: bytes) -> Path:
        path = self.dir / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def write_app(self, members: dict[str, tuple[bytes, int]]) -> None:
        with zipfile.ZipFile(self.app, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for name, (data, mode) in members.items():
                archive.writestr(app_entry(name, mode), data)

    def run_package(self) -> tuple[int, str]:
        stream = io.StringIO()
        code = tool.package_macos(self.app, self.out, project=self.project, readme=self.readme,
                                  credits=self.credits, godot_copyright=self.copyright, licence=self.licence,
                                  stream=stream)
        return code, stream.getvalue()

    def test_app_is_copied_byte_for_byte_with_its_unix_modes(self) -> None:
        code, text = self.run_package()
        self.assertEqual(code, 0, text)
        with zipfile.ZipFile(self.out) as archive:
            self.assertEqual(sorted(archive.namelist()),
                             sorted(["DEFECTOR.app/Contents/MacOS/DEFECTOR", "DEFECTOR.app/Contents/Info.plist",
                                     *tool.MACOS_TEXT_ENTRIES]))
            binary = archive.getinfo("DEFECTOR.app/Contents/MacOS/DEFECTOR")
            self.assertEqual(archive.read(binary), APP_BINARY)
            self.assertEqual(binary.create_system, 3)
            self.assertEqual(binary.external_attr >> 16, 0o100755, "the executable bit survives")
            self.assertEqual(binary.date_time, (2026, 10, 15, 9, 56, 0))
            self.assertEqual(archive.read("DEFECTOR.app/Contents/Info.plist"), PLIST)
            for info in archive.infolist():
                self.assertEqual(info.compress_type, zipfile.ZIP_DEFLATED, info.filename)
        self.assertIn("DEFECTOR v1.0", text)
        self.assertEqual(sorted(path.name for path in self.out.parent.iterdir()), ["release-macos.zip"],
                         "no partial file left")

    def test_text_entries_sit_beside_the_app_with_lf_endings_and_mode_0644(self) -> None:
        self.assertEqual(self.run_package()[0], 0)
        with zipfile.ZipFile(self.out) as archive:
            self.assertEqual(archive.read("README.txt"), b"DEFECTOR for macOS\nOpen Anyway\n")
            self.assertEqual(archive.read("LICENSE.txt"), LICENSE_TEXT.encode())
            credits = archive.read("CREDITS.txt").decode("utf-8")
            self.assertNotIn("\r", credits)
            self.assertTrue(credits.startswith(CREDITS_TEXT.rstrip()))
            self.assertIn("The FreeType Project", credits)
            for name in tool.MACOS_TEXT_ENTRIES:
                info = archive.getinfo(name)
                self.assertEqual(info.create_system, 3, name)
                self.assertEqual(info.external_attr >> 16, 0o100644, name)

    def test_an_export_without_the_app_executable_is_a_usage_error(self) -> None:
        self.write_app({"DEFECTOR.app/Contents/Info.plist": (PLIST, 0o100644),
                        "Other.app/Contents/MacOS/DEFECTOR": (APP_BINARY, 0o100755)})
        code, text = self.run_package()
        self.assertEqual(code, 2)
        self.assertIn("has no DEFECTOR.app/Contents/MacOS/DEFECTOR", text)
        self.assertFalse(self.out.parent.exists(), "nothing written")

    def test_a_non_zip_export_is_a_usage_error(self) -> None:
        self.app.write_bytes(b"not a zip")
        code, _text = self.run_package()
        self.assertEqual(code, 2)
        self.assertFalse(self.out.parent.exists(), "nothing written")

    def test_each_missing_input_is_a_usage_error_and_writes_nothing(self) -> None:
        for label, attr in (("app export", "app"), ("readme", "readme"), ("credits", "credits"),
                            ("Godot copyright", "copyright"), ("licence", "licence")):
            with self.subTest(missing=label):
                original: Path = getattr(self, attr)
                missing = original.with_name("missing-" + original.name)
                setattr(self, attr, missing)
                try:
                    code, text = self.run_package()
                finally:
                    setattr(self, attr, original)
                self.assertEqual(code, 2, text)
                self.assertIn(f"package: {label} {missing} is missing", text)
                self.assertFalse(self.out.parent.exists(), "nothing written")

    def test_default_out_is_the_versioned_macos_zip_at_the_repo_root(self) -> None:
        original = tool.REPO
        tool.REPO = self.dir
        try:
            code = tool.package_macos(self.app, None, project=self.project, readme=self.readme,
                                      credits=self.credits, godot_copyright=self.copyright, licence=self.licence,
                                      stream=io.StringIO())
        finally:
            tool.REPO = original
        self.assertEqual(code, 0)
        self.assertTrue((self.dir / "DEFECTOR-v1.0-macos.zip").is_file())


def lines_with(text: str, token: str) -> list[str]:
    pattern = re.compile(rf"(?<![A-Za-z0-9]){re.escape(token)}(?![A-Za-z0-9])")
    return [line for line in text.splitlines() if pattern.search(line)]


class ReleaseDocsTest(unittest.TestCase):
    def setUp(self) -> None:
        version = tool.read_version(tool.PROJECT)
        self.assertIsNotNone(version)
        self.version_tag = f"v{version}"

    def assert_controls(self, name: str, text: str, save_dir: str = SAVE_DIR) -> None:
        for key, words in CONTROLS.items():
            with self.subTest(doc=name, key=key):
                candidates = lines_with(text, key)
                self.assertTrue(any(all(word in line.lower() for word in words) for line in candidates),
                                f"{name}: no line names {key} with {words}")
        self.assertIn(save_dir, text, f"{name}: names the save folder")
        for stale in STALE_PHRASES + BANNED_PHRASES:
            self.assertNotIn(stale, text.lower(), f"{name}: {stale}")

    def test_release_readme_names_every_control_and_the_save_folder(self) -> None:
        raw = tool.README_TXT.read_bytes()
        text = raw.decode("utf-8")
        self.assert_controls("release/README.txt", text)
        self.assertIn(b"\r\n", raw)
        self.assertNotIn(b"\n", raw.replace(b"\r\n", b""), "CRLF line endings only")
        for phrase in (self.version_tag, "DEFECTOR.exe", "More info", "Run anyway", "Level Select", "Level 1",
                       "CREDITS.txt", "LICENSE.txt", "MIT", "Godot", "10-15 minutes", "resets your progress"):
            self.assertIn(phrase.lower(), text.lower(), phrase)

    def test_macos_readme_is_honest_about_the_untested_build(self) -> None:
        text = tool.README_MACOS_TXT.read_text(encoding="utf-8")
        self.assert_controls("release/README-macos.txt", text, MACOS_SAVE_DIR)
        self.assertNotIn("%APPDATA%", text)
        for phrase in (self.version_tag, "DEFECTOR.app", "untested", "Privacy & Security", "Open Anyway",
                       "right-click", "xattr -dr com.apple.quarantine DEFECTOR.app", "two buttons", "Fn+F11",
                       "Level Select", "CREDITS.txt", "LICENSE.txt", "MIT", "Godot", "10-15 minutes",
                       "resets your progress"):
            self.assertIn(phrase.lower(), text.lower(), phrase)

    def test_the_real_licence_is_mit_for_the_public_identity(self) -> None:
        text = tool.LICENSE.read_text(encoding="utf-8")
        self.assertTrue(text.startswith("MIT License"))
        self.assertIn("Copyright (c) 2026 iman2001-ie", text)
        self.assertIn("Permission is hereby granted, free of charge", text)
        for phrase in ("game/assets/CREDITS.md", "CC0", "game/addons/gut/LICENSE.md", "_bmad/", ".agents/",
                       ".claude/skills/"):
            self.assertIn(phrase, text, phrase)

    def test_repo_readme_names_every_control_and_has_its_sections(self) -> None:
        text = (tool.REPO / "README.md").read_text(encoding="utf-8")
        self.assert_controls("README.md", text)
        headings = [line[3:].strip().lower() for line in text.splitlines() if line.startswith("## ")]
        for section in ("the game", "controls", "download and run", "credits"):
            self.assertIn(section, headings)
        for phrase in (self.version_tag, "releases", "game/assets/CREDITS.md", "Kenney", "CC0", "MIT", "LICENSE",
                       "package_release.py", "repo_hygiene.py", "godot_copyright.gd", "DEFECTOR-v1.0-windows.zip",
                       "DEFECTOR-v1.0-macos.zip", '--export-release "macOS"', MACOS_SAVE_DIR, "Open Anyway"):
            self.assertIn(phrase.lower(), text.lower(), phrase)
        self.assertNotIn(".bmad-loop/archive/", text, "the purged run archives are gone")

    def test_release_notes_exist_with_the_essentials(self) -> None:
        text = (tool.REPO / "RELEASE_NOTES.md").read_text(encoding="utf-8")
        self.assert_controls("RELEASE_NOTES.md", text)
        for phrase in (f"DEFECTOR {self.version_tag}", "Windows 10", "64-bit", "SmartScreen", SAVE_DIR,
                       "CREDITS.txt", "LICENSE.txt", "Godot", "Shield", "Barrage", "F11",
                       "DEFECTOR-v1.0-windows.zip", "DEFECTOR-v1.0-macos.zip", "macOS", MACOS_SAVE_DIR,
                       "Open Anyway", "untested"):
            self.assertIn(phrase, text, phrase)


if __name__ == "__main__":
    unittest.main()
