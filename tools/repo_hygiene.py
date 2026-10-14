"""Story 8.5: scan the public repo's tracked files for secrets, real emails and
machine-specific paths before a push or a release.

Run from the repo root (stdlib only):

    uv run python tools/repo_hygiene.py
    uv run python tools/repo_hygiene.py --deny "<your name>" --deny "<your host>"
    uv run python tools/repo_hygiene.py --untracked

It scans every file `git ls-files` lists (plus untracked, not-ignored files
with --untracked, so new files can be checked before they are added). Text is
read as UTF-8 with undecodable bytes replaced, and split into lines on CRLF,
CR or LF only, so the line numbers match git's.

- Archives (`.zip`, `.tar`, `.tar.gz`, `.tgz`, `.tar.xz`, `.txz`, `.tar.bz2`,
  `.tbz`, `.tbz2`, `.gz`) are opened with the
  stdlib and every member is scanned like a file, reported as
  `path!member:line: rule`. An archive that can't be opened is reported as
  `unreadable-archive`.
- A text file or archive member over MAX_BYTES (20 MB) is reported as
  `unscanned-large`, never skipped silently.
- Other binaries (a NUL byte in the first 8 KiB) are skipped, and the summary
  counts them.

Rules (one finding per rule per line):
- sensitive-file: a file named `.env` or `.env.*`, `LOCAL.md` (any case),
  `settings.local.json`, `.netrc`, `.npmrc`, `.pypirc` or `*.user.toml`, or
  ending in `.pem`, `.key`, `.pfx`, `.p12`, `.jks`, `.keystore` or `.ppk`
  (reported on line 0);
- windows-user-path: a user folder under a drive, `X:\\Users\\<someone>`, in its
  Windows, Git Bash / MSYS (`/c/Users/<someone>`) and WSL
  (`/mnt/c/Users/<someone>`) forms, with one or more backslashes or slashes as
  separators. Placeholders are allowed: a name that starts with `<`, `%`, `$`,
  `{` or `[`, the Windows system folders `Public`, `Default` and `All Users`,
  and the generic stand-ins in PLACEHOLDER_USERS;
- unix-user-path: `/Users/<someone>` (macOS) or `/home/<someone>` (Linux),
  case-sensitive, so a lowercase `/api/users/...` route never matches; the
  same placeholders are allowed (`/home/me`, `/Users/host`);
- email: an email address, except the reserved example domains
  (example.com/.org/.net/.test and their subdomains, test.com, company.com),
  the reserved top-level domains `.test`, `.example`, `.invalid` and
  `.localhost`, GitHub's `users.noreply.github.com` addresses and the exact public addresses
  in ALLOWED_EMAILS. A noreply address at any other domain is a hit. A retina
  asset name such as `icon@2x.png` is not an email;
- private-key: a PEM `-----BEGIN ... PRIVATE KEY-----` or PGP
  `-----BEGIN PGP PRIVATE KEY BLOCK-----` header. A header quoted as inline
  code (between backticks, as here) is documentation, not a key, and is not
  reported;
- github-token / aws-access-key / slack-token / anthropic-key / openai-key /
  google-api-key / gitlab-token / npm-token: the well-known token prefixes
  (`ghp_`/`gho_`/`ghu_`/`ghs_`/`ghr_` and `github_pat_`, `AKIA` and `ASIA`,
  `xox?-`, `sk-ant-`, `sk-proj-`, `AIza`, `glpat-`, `npm_`) followed by a
  token-shaped tail;
- deny: any `--deny TEXT` literal (repeatable, case-insensitive; surrounding
  whitespace is stripped and blank values are ignored), in a line or in a
  file path. This is how the operator checks
  their own name, hostname, email or LOCAL.md values: they can't be listed
  here, because this file is public too. A path that contains a denied text is
  printed with that text replaced by `***`.

Each finding prints as `path:line: rule`; the matched text is never echoed.
Exit 0 with `0 findings`, 1 with any finding, 2 on a usage error (git missing
or not a git repo).
"""

from __future__ import annotations

import argparse
import bisect
import gzip
import re
import subprocess
import sys
import tarfile
import zipfile
import zlib
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import BinaryIO, Callable, Iterable, Iterator, TextIO

REPO = Path(__file__).resolve().parent.parent
MAX_BYTES = 20_000_000
BINARY_PROBE_BYTES = 8192
READ_CHUNK = 1 << 20

SENSITIVE_NAMES = {".env", "local.md", "settings.local.json", ".netrc", ".npmrc", ".pypirc"}
SENSITIVE_SUFFIXES = (".pem", ".key", ".pfx", ".p12", ".jks", ".keystore", ".ppk", ".user.toml")

# Generic stand-ins used in docs, specs and vendored skills, and the Windows
# system folders; never a real account. Compared lower-case.
PLACEHOLDER_USERS = {
    "...", "all", "all users", "default", "default user", "example", "host", "jdoe", "me",
    "name", "public", "runner", "shared", "somebody", "someone", "user", "username", "you",
    "your-name", "yourname", "your_name",
}
PLACEHOLDER_START = "<%${["
NAME_TRAILING_PUNCTUATION = ".,;:)]}>'\"`"

EXAMPLE_DOMAINS = ("example.com", "example.org", "example.net", "example.test", "test.com", "company.com")
# RFC 2606 / 6761 reserved top-level domains: never a real mailbox.
RESERVED_TLDS = ("test", "example", "invalid", "localhost")
NOREPLY_DOMAINS = ("users.noreply.github.com",)
# Exact addresses that are public and expected: GitHub's ssh user, the
# Claude Code commit co-author, the licence contact in GUT's vendored OFL.txt
# (game/addons/gut/fonts/) and the FreeType contacts in Godot's licence
# notices (release/GODOT_COPYRIGHT.txt).
ALLOWED_EMAILS = {
    "git@github.com", "noreply@anthropic.com", "mark@marksimonson.com",
    "freetype@nongnu.org", "freetype-devel@nongnu.org",
}

SEP = r"[\\/]+"
NAME = r"([^\\/\s\"'`|*?:]+)"
# A drive letter (Windows paths are case-insensitive), then Users and a name.
WINDOWS_USER_PATH = re.compile(rf"(?<![A-Za-z])[A-Za-z]:{SEP}(?i:users){SEP}{NAME}")
# Git Bash / MSYS `/c/Users/<name>` and WSL `/mnt/c/Users/<name>`. Both print
# `Users` capitalised, so a lowercase `/v/users/list` route never matches.
POSIX_DRIVE_USER_PATH = re.compile(rf"(?<![A-Za-z0-9_.~:-])(?:/mnt)?/[A-Za-z]{SEP}Users{SEP}{NAME}")
# Not after a drive letter (that is a windows-user-path) or inside a word or URL path.
UNIX_USER_PATH = re.compile(r"(?<![A-Za-z0-9_.~:-])/(?:Users|home)/([A-Za-z0-9._-]+)")
EMAIL = re.compile(r"(?<![A-Za-z0-9._%+-])([A-Za-z0-9._%+-]+)@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})")
# The `@2x.` of a retina asset name such as `icon@2x.png`.
RETINA_DOMAIN = re.compile(r"^\d+x\.", re.IGNORECASE)
# A PEM or PGP private-key header, with any backtick right around it captured.
PRIVATE_KEY = re.compile(r"(`?)-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY(?: BLOCK)?-----(`?)")
# (rule, the literals a hit must contain, pattern). A pattern only runs on a
# text that holds one of its literals: a substring test is far cheaper than a
# regex that starts with a lookbehind.
TOKEN_RULES: tuple[tuple[str, tuple[str, ...], re.Pattern[str]], ...] = (
    ("github-token", ("ghp_", "gho_", "ghu_", "ghs_", "ghr_"),
     re.compile(r"(?<![A-Za-z0-9])gh[pousr]_[A-Za-z0-9]{36,}")),
    ("github-token", ("github_pat_",), re.compile(r"(?<![A-Za-z0-9])github_pat_[A-Za-z0-9_]{22,}")),
    ("aws-access-key", ("AKIA", "ASIA"), re.compile(r"(?<![A-Z0-9])A(?:KI|SI)A[0-9A-Z]{16}(?![0-9A-Z])")),
    ("slack-token", ("xox",), re.compile(r"(?<![A-Za-z0-9])xox[a-z]-[A-Za-z0-9-]{10,}")),
    ("anthropic-key", ("sk-ant-",), re.compile(r"(?<![A-Za-z0-9])sk-ant-[A-Za-z0-9_-]{20,}")),
    ("openai-key", ("sk-proj-",), re.compile(r"(?<![A-Za-z0-9])sk-proj-[A-Za-z0-9_-]{20,}")),
    ("google-api-key", ("AIza",), re.compile(r"(?<![A-Za-z0-9])AIza[0-9A-Za-z_-]{35}")),
    ("gitlab-token", ("glpat-",), re.compile(r"(?<![A-Za-z0-9])glpat-[A-Za-z0-9_-]{20,}")),
    ("npm-token", ("npm_",), re.compile(r"(?<![A-Za-z0-9])npm_[A-Za-z0-9]{36}")),
)
LINE_BREAK = re.compile(r"\r\n|\r|\n")
RULE_ORDER = ("windows-user-path", "unix-user-path", "email", "private-key", "github-token",
              "aws-access-key", "slack-token", "anthropic-key", "openai-key", "google-api-key",
              "gitlab-token", "npm-token", "deny")

TAR_SUFFIXES = (".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".tbz", ".tbz2", ".tar")
ARCHIVE_SUFFIXES = TAR_SUFFIXES + (".zip", ".gz")
ARCHIVE_ERRORS = (OSError, EOFError, tarfile.TarError, zipfile.BadZipFile, zlib.error,
                  RuntimeError, NotImplementedError, ValueError)


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    rule: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}: {self.rule}"

    def render(self, deny: Iterable[str] = ()) -> str:
        """`path:line: rule`, with every denied text in the path replaced by ***."""
        return f"{redact(self.path, deny)}:{self.line}: {self.rule}"


@dataclass
class Stats:
    text_files: int = 0
    members: int = 0
    archives: int = 0
    binary: int = 0
    missing: int = 0


def clean_deny(deny: Iterable[str]) -> list[str]:
    """The --deny values worth matching, each stripped of surrounding
    whitespace; blank or whitespace-only ones are dropped."""
    return [text.strip() for text in deny if text and text.strip()]


def redact(text: str, deny: Iterable[str]) -> str:
    for denied in clean_deny(deny):
        text = re.sub(re.escape(denied), "***", text, flags=re.IGNORECASE)
    return text


def is_placeholder_user(name: str) -> bool:
    bare = name.strip().rstrip(NAME_TRAILING_PUNCTUATION)
    return name[:1] in PLACEHOLDER_START or bare.lower() in PLACEHOLDER_USERS


def is_allowed_email(local: str, domain: str) -> bool:
    local_l, domain_l = local.lower(), domain.lower()
    if f"{local_l}@{domain_l}" in ALLOWED_EMAILS:
        return True
    if domain_l in NOREPLY_DOMAINS or RETINA_DOMAIN.match(domain_l):
        return True
    if domain_l.rsplit(".", 1)[-1] in RESERVED_TLDS:
        return True
    return any(domain_l == d or domain_l.endswith("." + d) for d in EXAMPLE_DOMAINS)


def sensitive_name(path: str) -> bool:
    name = path.replace("\\", "/").rsplit("/", 1)[-1].lower()
    return name in SENSITIVE_NAMES or name.startswith(".env.") or name.endswith(SENSITIVE_SUFFIXES)


def rule_hits(text: str, deny: Iterable[str] = ()) -> Iterator[tuple[str, int]]:
    """(rule, offset) for every hit in `text`. No pattern crosses a line break,
    so each pattern runs once over a whole file instead of once per line, and
    only when the text holds a literal every hit of it must contain."""
    if "users" in text.lower():
        for pattern in (WINDOWS_USER_PATH, POSIX_DRIVE_USER_PATH):
            for match in pattern.finditer(text):
                if not is_placeholder_user(match.group(1)):
                    yield "windows-user-path", match.start()
    if "/Users/" in text or "/home/" in text:
        for match in UNIX_USER_PATH.finditer(text):
            if not is_placeholder_user(match.group(1)):
                yield "unix-user-path", match.start()
    if "@" in text:
        for match in EMAIL.finditer(text):
            if not is_allowed_email(match.group(1), match.group(2)):
                yield "email", match.start()
    if "PRIVATE KEY" in text:
        for match in PRIVATE_KEY.finditer(text):
            if not (match.group(1) and match.group(2)):
                yield "private-key", match.start()
    for rule, literals, pattern in TOKEN_RULES:
        if any(literal in text for literal in literals):
            for match in pattern.finditer(text):
                yield rule, match.start()
    for denied in clean_deny(deny):
        for match in re.finditer(re.escape(denied), text, flags=re.IGNORECASE):
            yield "deny", match.start()


def line_rules(line: str, deny: Iterable[str] = ()) -> list[str]:
    """The rules one line of text breaks, in RULE_ORDER, each at most once."""
    found = {rule for rule, _offset in rule_hits(line, deny)}
    return [rule for rule in RULE_ORDER if rule in found]


def split_lines(text: str) -> list[str]:
    """Lines split on CRLF, CR or LF only (not on the form feeds, vertical tabs
    and Unicode breaks str.splitlines() honours), so the numbers match git's."""
    return LINE_BREAK.split(text)


def scan_text(path: str, text: str, deny: Iterable[str] = ()) -> list[Finding]:
    """One finding per rule per line, ordered by line, then RULE_ORDER."""
    hits = set(rule_hits(text, deny))
    if not hits:
        return []
    starts = [0] + [match.end() for match in LINE_BREAK.finditer(text)]
    lines = {(bisect.bisect_right(starts, offset), rule) for rule, offset in hits}
    return [Finding(path, line, rule)
            for line, rule in sorted(lines, key=lambda hit: (hit[0], RULE_ORDER.index(hit[1])))]


def read_capped(handle: BinaryIO) -> bytes:
    """A stream's bytes, in 1 MiB chunks, stopping once more than MAX_BYTES
    have been read (enough to tell a file is too large). Chunked, because
    read(MAX_BYTES + 1) allocates the whole 20 MB buffer for every small file."""
    chunks: list[bytes] = []
    total = 0
    while total <= MAX_BYTES:
        chunk = handle.read(READ_CHUNK)
        if not chunk:
            break
        chunks.append(chunk)
        total += len(chunk)
    return b"".join(chunks)


def is_binary(data: bytes) -> bool:
    return b"\x00" in data[:BINARY_PROBE_BYTES]


def is_archive(path: str) -> bool:
    return path.lower().endswith(ARCHIVE_SUFFIXES)


def path_findings(path: str, deny: Iterable[str]) -> list[Finding]:
    """The name-only findings: a sensitive file name, or a denied text in the path."""
    findings: list[Finding] = []
    if sensitive_name(path):
        findings.append(Finding(path, 0, "sensitive-file"))
    if any(text.lower() in path.lower() for text in clean_deny(deny)):
        findings.append(Finding(path, 0, "deny"))
    return findings


def scan_blob(path: str, data: bytes, deny: Iterable[str], stats: Stats, member: bool) -> list[Finding]:
    """Findings in one file's or archive member's bytes, as read by read_capped()."""
    if is_binary(data):
        stats.binary += 1
        return []
    if len(data) > MAX_BYTES:
        return [Finding(path, 0, "unscanned-large")]
    if member:
        stats.members += 1
    else:
        stats.text_files += 1
    return scan_text(path, data.decode("utf-8", errors="replace"), deny)


def archive_members(file: Path) -> Iterator[tuple[str, bytes]]:
    """(member name, bytes) for every regular file in an archive. Each member
    is read by read_capped(), enough to tell that it is too large.
    Raises one of ARCHIVE_ERRORS on an archive that can't be read."""
    name = file.name.lower()
    if name.endswith(TAR_SUFFIXES):
        with tarfile.open(file, "r:*") as archive:
            for info in archive:
                if not info.isfile():
                    continue
                handle = archive.extractfile(info)
                if handle is None:
                    continue
                with handle:
                    yield info.name, read_capped(handle)
    elif name.endswith(".zip"):
        with zipfile.ZipFile(file) as archive:
            for info in archive.infolist():
                if info.is_dir():
                    continue
                with archive.open(info) as handle:
                    yield info.filename, read_capped(handle)
    else:
        with gzip.open(file, "rb") as handle:
            yield PurePosixPath(file.name).stem, read_capped(handle)


def scan_archive(path: str, file: Path, deny: Iterable[str], stats: Stats) -> list[Finding]:
    findings: list[Finding] = []
    stats.archives += 1
    try:
        for member, data in archive_members(file):
            member_path = f"{path}!{member}"
            findings.extend(path_findings(member_path, deny))
            findings.extend(scan_blob(member_path, data, deny, stats, member=True))
    except ARCHIVE_ERRORS:
        findings.append(Finding(path, 0, "unreadable-archive"))
    return findings


def scan_paths(root: Path, paths: Iterable[str], deny: Iterable[str] = ()) -> tuple[list[Finding], Stats]:
    """(findings, stats) for repo-relative `paths` under `root`."""
    deny = clean_deny(deny)
    findings: list[Finding] = []
    stats = Stats()
    for path in paths:
        findings.extend(path_findings(path, deny))
        file = root / path
        if not file.is_file():
            stats.missing += 1
            continue
        if is_archive(path):
            findings.extend(scan_archive(path, file, deny, stats))
            continue
        try:
            with file.open("rb") as handle:
                data = read_capped(handle)
        except OSError:
            stats.missing += 1
            continue
        findings.extend(scan_blob(path, data, deny, stats, member=False))
    return findings, stats


def git_files(root: Path, untracked: bool = False,
              run: Callable[..., subprocess.CompletedProcess] = subprocess.run) -> list[str]:
    """Tracked files (and untracked, not-ignored ones with `untracked`); raises
    OSError or CalledProcessError when git is missing or this isn't a repo."""
    args = ["git", "-C", str(root), "ls-files", "-z", "--cached"]
    if untracked:
        args += ["--others", "--exclude-standard"]
    result = run(args, capture_output=True, check=True)
    names = result.stdout.decode("utf-8", errors="replace").split("\0")
    return sorted({name for name in names if name})


def main(argv: list[str] | None = None, root: Path = REPO, out: TextIO | None = None,
         list_files: Callable[[Path, bool], list[str]] = git_files) -> int:
    out = out if out is not None else sys.stdout
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--deny", action="append", default=[], metavar="TEXT",
                        help="a literal that must not appear (repeatable, case-insensitive); never stored")
    parser.add_argument("--untracked", action="store_true",
                        help="also scan untracked files that .gitignore doesn't ignore")
    args = parser.parse_args(argv)
    deny = clean_deny(args.deny)
    try:
        paths = list_files(root, args.untracked)
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"repo_hygiene: can't list files with git ({error.__class__.__name__})", file=out)
        return 2
    findings, stats = scan_paths(root, paths, deny)
    for finding in findings:
        print(finding.render(deny), file=out)
    count = len(findings)
    print(f"{count} finding{'s' if count != 1 else ''} ({len(paths)} files: {stats.text_files} text files "
          f"and {stats.members} members of {stats.archives} archives scanned, {stats.binary} binary skipped, "
          f"{stats.missing} missing)", file=out)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
