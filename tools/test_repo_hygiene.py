"""Tests for tools/repo_hygiene.py (Story 8.5). Stdlib unittest only.

Run from the repo root:  uv run python -m unittest tools/test_repo_hygiene.py

Every synthetic secret, email and path below is assembled from pieces, so this
file never holds a literal the scanner would report (the real-repo test scans
this file too).
"""

from __future__ import annotations

import gzip
import io
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import repo_hygiene as tool  # noqa: E402

BS = "\\"
AT = "@"
USER = "q" + "lindqvist"  # a made-up "real" account name (not a placeholder)
WIN_PATH = "C:" + BS + "Users" + BS + USER + BS + "game"
WIN_PATH_JSON = "D:" + BS * 2 + "Users" + BS * 2 + USER + BS * 2 + "x"
WIN_PATH_ESCAPED = "E:" + BS * 4 + "Users" + BS * 4 + USER + BS * 4 + "x"
WIN_PATH_FWD = "c:/" + "Users/" + USER + "/proj"
GIT_BASH_PATH = "/c/" + "Users/" + USER + "/proj"
WSL_PATH = "/mnt/c/" + "Users/" + USER + "/proj"
MAC_PATH = "/" + "Users/" + USER + "/proj"
LINUX_PATH = "/" + "home/" + USER + "/proj"
REAL_EMAIL = USER + AT + "realcorp.io"
OTHER_NOREPLY = "noreply" + AT + "realcorp.io"
PRIVATE_KEY = "-----BEGIN " + "RSA PRIVATE KEY" + "-----"
PRIVATE_KEY_PLAIN = "-----BEGIN " + "PRIVATE KEY" + "-----"
PGP_KEY = "-----BEGIN " + "PGP PRIVATE KEY BLOCK" + "-----"
GITHUB_TOKEN = "gh" + "p_" + "A1b2C3d4" * 5
GITHUB_PAT = "github" + "_pat_" + "11ABCDEFG0" + "abcdefghijklmnopqrstuvwxyz"
AWS_KEY = "AK" + "IA" + "ABCDEFGHIJKLMNOP"
SLACK_TOKEN = "xo" + "xb-" + "1234567890-abcdef"
ANTHROPIC_KEY = "sk" + "-ant-" + "api03-" + "abcdefghij" * 3
AWS_TEMP_KEY = "AS" + "IA" + "ABCDEFGHIJKLMNOP"
SLACK_OTHER = "xo" + "xe-" + "1234567890-abcdef"
OPENAI_KEY = "sk" + "-proj-" + "abcdefghij" * 3
GOOGLE_KEY = "AI" + "za" + "Sy" + "A1b2C3d4E5" * 3 + "abc"
GITLAB_TOKEN = "gl" + "pat-" + "abcdefghij" * 2
NPM_TOKEN = "np" + "m_" + "A1b2C3d4E5" * 3 + "abcdef"

# Tracked files allowed to have findings: pre-existing leaks awaiting a history
# rewrite and force-push (AGENTS.md section 1), never `git rm` or a follow-up
# commit. Story 8.5's four bmad-loop run archives were purged from history, so
# it is empty. The test below fails on a stale entry, so one can't hide a new leak.
KNOWN_LEAKS: set[str] = set()


def rules(line: str, deny: list[str] | None = None) -> list[str]:
    return tool.line_rules(line, deny or [])


class RuleTest(unittest.TestCase):
    def test_each_rule_hits(self) -> None:
        cases = {
            "windows-user-path": [f"see {WIN_PATH} for it", f'"path": "{WIN_PATH_JSON}"', f"at {WIN_PATH_FWD}",
                                  f"escaped {WIN_PATH_ESCAPED}", f"cd {GIT_BASH_PATH}", f"cd {WSL_PATH}",
                                  f"({GIT_BASH_PATH})"],
            "unix-user-path": [f"cd {MAC_PATH}", f"cd {LINUX_PATH}"],
            "email": [f"mail {REAL_EMAIL} today", f"<{REAL_EMAIL}>", f"from {OTHER_NOREPLY}"],
            "private-key": [PRIVATE_KEY, PRIVATE_KEY_PLAIN, PGP_KEY, f"`{PGP_KEY}", f"{PGP_KEY}`"],
            "github-token": [f"token={GITHUB_TOKEN}", f"token: {GITHUB_PAT}"],
            "aws-access-key": [f"key {AWS_KEY} end", f"key {AWS_TEMP_KEY} end"],
            "slack-token": [f"slack {SLACK_TOKEN}", f"slack {SLACK_OTHER}"],
            "anthropic-key": [f"ANTHROPIC_API_KEY={ANTHROPIC_KEY}"],
            "openai-key": [f"OPENAI_API_KEY={OPENAI_KEY}"],
            "google-api-key": [f"key={GOOGLE_KEY}"],
            "gitlab-token": [f"token {GITLAB_TOKEN}"],
            "npm-token": [f"//registry/:_authToken={NPM_TOKEN}"],
        }
        for rule, lines in cases.items():
            for line in lines:
                with self.subTest(rule=rule, line=line):
                    self.assertEqual(rules(line), [rule])

    def test_each_rule_misses_ordinary_text(self) -> None:
        for line in [
            "Hold LMB to fire; RMB fires a missile.",
            "GET /api/users/42 returns the user",
            "GET /api/users/x",
            "the route /v/users/list is lowercase",
            "the route /users/" + USER + " is lowercase",
            "https://example.org/c/Users/" + USER,
            "a sentence about Users/ and home/ folders",
            "sk-ant- prefix alone, ghp_ alone, AKIA alone, xoxb- alone",
            "-----BEGIN PUBLIC KEY-----",
            "-----BEGIN CERTIFICATE-----",
            f"the PGP header `{PGP_KEY}` is matched too",
            "@scope/package and user@ and @mention",
            "icon" + AT + "2x.png and logo" + AT + "3X.webp",
            "AKIA" + "abc lowercase tail",
            "AS" + "IA" + "short1",
            "xo" + "x1-" + "1234567890-abcdef",
            "sk" + "-proj-" + "short",
            "AI" + "za" + "short_key",
            "gl" + "pat-" + "short",
            "np" + "m_" + "short and npm_install",
        ]:
            with self.subTest(line=line):
                self.assertEqual(rules(line), [])

    def test_placeholders_are_allowed(self) -> None:
        for line in [
            "C:" + BS + "Users" + BS + "<name>" + BS + "proj",
            "C:" + BS + "Users" + BS + "%USERNAME%" + BS + "x",
            "C:" + BS + "Users" + BS + "$USER" + BS + "x",
            "C:" + BS + "Users" + BS + "{user}" + BS + "x",
            "C:" + BS + "Users" + BS + "someone" + BS,
            "X:" + BS + "Users" + BS + "someone, and more",
            "C:" + BS + "Users" + BS + "Public" + BS + "Documents",
            "C:" + BS + "Users" + BS + "Default" + BS + "AppData",
            "C:" + BS + "Users" + BS + "All Users" + BS + "x",
            "/c/" + "Users/<name>/proj",
            "/mnt/c/" + "Users/<name>/proj",
            "/c/" + "Users/me/proj",
            "/" + "home/me/project",
            "/" + "Users/host/x",
            "/" + "Users/someone/",
            "/" + "Users/" + "`",
            "test" + AT + "example.com",
            "a" + AT + "example.test",
            "u" + AT + "mail.example.org",
            "user2" + AT + "test.com",
            "admin" + AT + "company.com",
            "123+octocat" + AT + "users.noreply.github.com",
            "noreply" + AT + "anthropic.com",
            "git" + AT + "github.com:owner/repo.git",
            "mark" + AT + "marksimonson.com",
            "freetype" + AT + "nongnu.org",
            "dev" + AT + "host.test",
            "a" + AT + "mail.example",
            "b" + AT + "nowhere.invalid",
            "c" + AT + "box.localhost",
        ]:
            with self.subTest(line=line):
                self.assertEqual(rules(line), [])

    def test_one_finding_per_rule_per_line(self) -> None:
        line = f"{REAL_EMAIL} and {'x' + REAL_EMAIL} and {WIN_PATH} and {GIT_BASH_PATH}"
        self.assertEqual(rules(line), ["windows-user-path", "email"])

    def test_deny_is_case_insensitive_and_runtime_only(self) -> None:
        self.assertEqual(rules("built on HOSTNAME-42 today", ["hostname-42"]), ["deny"])
        self.assertEqual(rules("nothing here", ["hostname-42"]), [])
        for blank in ["", " ", "\t", "  \n"]:
            with self.subTest(blank=repr(blank)):
                self.assertEqual(rules("anything at all", [blank]), [], "a blank deny matches nothing")

    def test_deny_values_are_stripped(self) -> None:
        self.assertEqual(tool.clean_deny(["  box-7  ", "\tbox-8\n", " "]), ["box-7", "box-8"])
        self.assertEqual(rules("box-7 at the start", ["  box-7  "]), ["deny"])
        self.assertEqual(rules("at the end box-7", [" box-7 "]), ["deny"])

    def test_sensitive_names(self) -> None:
        for path in [".env", "config/.env", ".env.local", "app/.env.production", "keys/server.pem", "id.key",
                     "cert.PFX", "c.p12", "release.jks", "app.keystore", "LOCAL.md", "docs/local.md",
                     ".claude/settings.local.json", "_bmad/custom/x.user.toml", "putty/server.ppk", ".netrc",
                     "home/.npmrc", ".pypirc"]:
            with self.subTest(path=path):
                self.assertTrue(tool.sensitive_name(path))
        for path in ["env.md", "keyboard.gd", "LOCAL.md.txt", "local_notes.md", "settings.json", "x.toml",
                     "monkey.png", "my.environment", "netrc.md", "npmrc-notes.txt"]:
            with self.subTest(path=path):
                self.assertFalse(tool.sensitive_name(path))

    def test_lines_split_on_crlf_cr_and_lf_only(self) -> None:
        text = f"one\ftwo\vthree\u2028four\r\n{REAL_EMAIL}\rx\n{REAL_EMAIL}\n"
        self.assertEqual([(f.line, f.rule) for f in tool.scan_text("a.txt", text)], [(2, "email"), (4, "email")])

    def test_scan_text_orders_by_line_then_rule(self) -> None:
        text = f"{GITHUB_TOKEN} {REAL_EMAIL}\nclean\n{WIN_PATH}\n"
        self.assertEqual([str(f) for f in tool.scan_text("n.md", text)],
                         ["n.md:1: email", "n.md:1: github-token", "n.md:3: windows-user-path"])


class ScanTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())

    def tearDown(self) -> None:
        shutil.rmtree(self.root, ignore_errors=True)

    def write(self, rel: str, data: bytes) -> str:
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return rel

    def run_main(self, paths: list[str], argv: list[str] | None = None) -> tuple[int, str]:
        out = io.StringIO()
        code = tool.main(argv or [], root=self.root, out=out, list_files=lambda _root, _untracked: paths)
        return code, out.getvalue()

    def test_clean_files_report_zero_findings(self) -> None:
        paths = [self.write("README.md", b"Controls: hold LMB.\nC:\\Users\\<name>\\x\n"),
                 self.write("a.json", b'{"email": "test@example.com"}\n')]
        code, text = self.run_main(paths)
        self.assertEqual(code, 0)
        self.assertIn("0 findings", text)

    def test_hits_print_path_line_rule_without_the_text(self) -> None:
        paths = [self.write("docs/notes.md", f"line one\nwrite to {REAL_EMAIL}\n{GITHUB_TOKEN}\n".encode()),
                 self.write("server.pem", b"not really\n")]
        code, text = self.run_main(paths)
        self.assertEqual(code, 1)
        lines = text.splitlines()
        self.assertIn("docs/notes.md:2: email", lines)
        self.assertIn("docs/notes.md:3: github-token", lines)
        self.assertIn("server.pem:0: sensitive-file", lines)
        self.assertTrue(lines[-1].startswith("3 findings"), lines[-1])
        self.assertNotIn(REAL_EMAIL, text)
        self.assertNotIn(GITHUB_TOKEN, text)

    def test_deny_flag_hits_content_and_paths_and_redacts_paths(self) -> None:
        paths = [self.write("a.md", b"made on Box-Alpha\n"), self.write("beta-notes/b.md", b"clean\n"),
                 self.write("Box-Alpha-log.txt", f"{REAL_EMAIL}\n".encode())]
        code, text = self.run_main(paths, ["--deny", "box-alpha", "--deny", "BETA", "--deny", "  "])
        self.assertEqual(code, 1)
        lines = text.splitlines()
        self.assertIn("a.md:1: deny", lines)
        self.assertIn("***-notes/b.md:0: deny", lines)
        self.assertIn("***-log.txt:0: deny", lines)
        self.assertIn("***-log.txt:1: email", lines)
        self.assertNotIn("box-alpha", text.lower())
        self.assertNotIn("beta", text.lower())
        self.assertTrue(lines[-1].startswith("4 findings"), lines[-1])

    def test_a_deny_that_appears_nowhere_adds_no_findings(self) -> None:
        paths = [self.write("a.md", f"{REAL_EMAIL}\n".encode())]
        self.assertEqual(self.run_main(paths)[1].splitlines()[:-1],
                         self.run_main(paths, ["--deny", "zz-appears-nowhere-zz"])[1].splitlines()[:-1])

    def test_binary_and_missing_files_are_skipped_and_counted(self) -> None:
        paths = [self.write("img.png", b"\x89PNG\x00\x00" + REAL_EMAIL.encode()), "gone.txt"]
        code, text = self.run_main(paths)
        self.assertEqual(code, 0)
        self.assertIn("0 findings", text)
        self.assertIn("1 binary skipped", text)
        self.assertIn("1 missing", text)

    def test_over_cap_text_is_reported_not_skipped(self) -> None:
        original = tool.MAX_BYTES
        tool.MAX_BYTES = 64
        try:
            paths = [self.write("big.txt", b"x" * 65), self.write("small.txt", b"x" * 64)]
            code, text = self.run_main(paths)
        finally:
            tool.MAX_BYTES = original
        self.assertEqual(code, 1)
        self.assertIn("big.txt:0: unscanned-large", text.splitlines())
        self.assertNotIn("small.txt", text)

    def test_undecodable_bytes_are_replaced_not_fatal(self) -> None:
        paths = [self.write("latin.txt", b"caf\xe9 " + REAL_EMAIL.encode() + b"\n")]
        code, text = self.run_main(paths)
        self.assertEqual(code, 1)
        self.assertIn("latin.txt:1: email", text)

    def tar_gz(self, rel: str, members: dict[str, bytes]) -> str:
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
            for name, data in members.items():
                info = tarfile.TarInfo(name)
                info.size = len(data)
                archive.addfile(info, io.BytesIO(data))
        return self.write(rel, buffer.getvalue())

    def zip_file(self, rel: str, members: dict[str, bytes]) -> str:
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            for name, data in members.items():
                archive.writestr(name, data)
        return self.write(rel, buffer.getvalue())

    def test_archive_members_are_scanned(self) -> None:
        paths = [
            self.tar_gz("runs/r1.tar.gz", {"logs/clean.log": b"ok\n", "logs/run.log": f"a\nb\n{WIN_PATH}\n".encode()}),
            self.zip_file("pack.zip", {"x/readme.md": b"fine\n", "x/notes.txt": f"{REAL_EMAIL}\n".encode(),
                                       "x/.env": b"A=1\n", "x/img.bin": b"\x00\x01" + REAL_EMAIL.encode()}),
            self.write("one.log.gz", gzip.compress(f"z\n{GITHUB_TOKEN}\n".encode())),
        ]
        code, text = self.run_main(paths)
        self.assertEqual(code, 1)
        lines = text.splitlines()
        self.assertIn("runs/r1.tar.gz!logs/run.log:3: windows-user-path", lines)
        self.assertIn("pack.zip!x/notes.txt:1: email", lines)
        self.assertIn("pack.zip!x/.env:0: sensitive-file", lines)
        self.assertIn("one.log.gz!one.log:2: github-token", lines)
        self.assertTrue(lines[-1].startswith("4 findings"), lines[-1])
        self.assertIn("members of 3 archives", lines[-1])
        self.assertIn("1 binary skipped", lines[-1])
        self.assertNotIn(USER, text)

    def test_tar_xz_members_are_scanned(self) -> None:
        buffer = io.BytesIO()
        data = f"x\n{REAL_EMAIL}\n".encode()
        with tarfile.open(fileobj=buffer, mode="w:xz") as archive:
            info = tarfile.TarInfo("logs/run.log")
            info.size = len(data)
            archive.addfile(info, io.BytesIO(data))
        paths = [self.write("runs/r2.tar.xz", buffer.getvalue())]
        code, text = self.run_main(paths)
        self.assertEqual(code, 1)
        self.assertIn("runs/r2.tar.xz!logs/run.log:2: email", text.splitlines())

    def test_unreadable_archive_is_reported(self) -> None:
        paths = [self.write("broken.tar.gz", b"not a gzip stream at all"),
                 self.write("broken.zip", b"PK\x03\x04 truncated"),
                 self.write("broken.tgz", gzip.compress(b"not a tar header" * 3))]
        code, text = self.run_main(paths)
        self.assertEqual(code, 1)
        for path in paths:
            self.assertIn(f"{path}:0: unreadable-archive", text.splitlines())

    def test_over_cap_archive_member_is_reported(self) -> None:
        original = tool.MAX_BYTES
        tool.MAX_BYTES = 64
        try:
            paths = [self.tar_gz("big.tar.gz", {"huge.log": b"y" * 200, "ok.log": b"y" * 10})]
            code, text = self.run_main(paths)
        finally:
            tool.MAX_BYTES = original
        self.assertEqual(code, 1)
        self.assertIn("big.tar.gz!huge.log:0: unscanned-large", text.splitlines())
        self.assertNotIn("ok.log", text)

    def test_untracked_flag_reaches_the_lister(self) -> None:
        seen: list[bool] = []

        def lister(_root: Path, untracked: bool) -> list[str]:
            seen.append(untracked)
            return []

        out = io.StringIO()
        tool.main(["--untracked"], root=self.root, out=out, list_files=lister)
        tool.main([], root=self.root, out=out, list_files=lister)
        self.assertEqual(seen, [True, False])

    def test_git_failure_is_a_usage_error(self) -> None:
        def broken(_root: Path, _untracked: bool) -> list[str]:
            raise OSError("no git")
        out = io.StringIO()
        self.assertEqual(tool.main([], root=self.root, out=out, list_files=broken), 2)
        self.assertIn("can't list files", out.getvalue())

    def test_git_files_lists_tracked_and_optionally_untracked(self) -> None:
        if shutil.which("git") is None:
            self.skipTest("git is not available")
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.write("tracked.md", b"x\n")
        self.write("new.md", b"y\n")
        self.write("ignored.log", b"z\n")
        self.write(".gitignore", b"*.log\n")
        subprocess.run(["git", "-C", str(self.root), "add", "tracked.md", ".gitignore"], check=True)
        self.assertEqual(tool.git_files(self.root), [".gitignore", "tracked.md"])
        self.assertEqual(tool.git_files(self.root, untracked=True), [".gitignore", "new.md", "tracked.md"])


class RealRepoTest(unittest.TestCase):
    def test_only_the_known_leak_archives_have_findings(self) -> None:
        if shutil.which("git") is None:
            self.skipTest("git is not available")
        try:
            paths = tool.git_files(tool.REPO)
        except (OSError, subprocess.CalledProcessError):
            self.skipTest("not a git checkout")
        findings, stats = tool.scan_paths(tool.REPO, paths)
        self.assertGreater(stats.text_files, 0)
        outside = [str(finding) for finding in findings if finding.path.split("!", 1)[0] not in KNOWN_LEAKS]
        self.assertEqual(outside, [], "a finding outside the known leak archives")
        with_findings = {finding.path.split("!", 1)[0] for finding in findings}
        for leak in sorted(KNOWN_LEAKS):
            with self.subTest(leak=leak):
                self.assertIn(leak, paths, "purged: remove it from KNOWN_LEAKS")
                self.assertIn(leak, with_findings, "no findings any more: remove it from KNOWN_LEAKS")


if __name__ == "__main__":
    unittest.main()
