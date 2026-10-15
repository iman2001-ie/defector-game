---
title: 'Story 8.5: Ship DEFECTOR on GitHub'
type: 'feature'
created: '2026-10-14'
status: done
baseline_revision: '7e77b60beca9fe854bb33920fdadb58c7c4f7e73'
review_loop_iteration: 1
followup_review_recommended: false
operator_actions:
  - "Done (e803edc): the four tracked .bmad-loop/archive run archives were purged from the whole history with git filter-repo, KNOWN_LEAKS was emptied, and repo_hygiene.py --untracked reports 0 findings."
  - "Done (2026-10-15): the operator signed off the provisional checks of Stories 8.1-8.4 after a full-game playtest on HEAD and a Windows release build; Story 8.3's hands-on performance checks were waived (smooth in play, personal project). GDD decision #89."
  - "Done (2026-10-15): the hygiene scan with the operator's identifiers passed at run time (0 findings), and a full-history scan (every commit's diff, message, author and committer) found no secrets, no machine paths and no work identity."
  - "Done (2026-10-15): licence chosen, MIT (Copyright (c) 2026 iman2001-ie), in LICENSE; third-party content keeps its own licence; both zips carry LICENSE.txt. GDD decision #90."
  - "Done (2026-10-15): a best-effort macOS build was added (universal, ad-hoc signed, not notarized, untested on a real Mac), with release/README-macos.txt and DEFECTOR-v1.0-macos.zip from tools/package_release.py. GDD decision #90."
  - "Done (2026-10-15): README.md, release/README.txt and RELEASE_NOTES.md were rewritten for v1.0 (story wording, How it was made, eight screenshots, both platforms, no bug-report invitations, credits matching CREDITS.md)."
  - "Done (2026-10-15): both builds re-exported; the Windows zip unzipped into an empty folder passed perf_check launch --runs 3; GUT and the Python tool tests passed."
  - "Done (2026-10-15): main pushed to origin with the operator's authorisation for that session."
  - "Pending the operator's go-ahead: gh release create v1.0 DEFECTOR-v1.0-windows.zip DEFECTOR-v1.0-macos.zip --title \"DEFECTOR v1.0\" --notes-file RELEASE_NOTES.md, after one more smoke test of the new Windows zip."
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
warnings: ['oversized']
deferred:
  - summary: >-
      The public repo has no LICENSE file, so visitors can't tell whether they may reuse the code or the project-owned art.
    evidence: |-
      No LICENSE at the repo root before or after Story 8.5; README.md says only "Non-commercial hobby project". Pre-existing, and the licence choice is the owner's decision (review pass 1, BH2).
    location: >-
      LICENSE (missing), README.md
    severity: medium
  - summary: >-
      AGENTS.md's "scan the staged diff before every commit" rule doesn't point at tools/repo_hygiene.py, and the tool has no --staged mode or pre-commit hook.
    evidence: |-
      AGENTS.md section 1 still describes a manual scan; the fix edits an agent-context file, so it is deferred (review pass 1, BH15).
    location: >-
      AGENTS.md section 1
    severity: low
  - summary: >-
      README.md now carries further copies of the --import, GUT and export commands, which AGENTS.md (the source of the --import command copies) doesn't list.
    evidence: |-
      AGENTS.md section 3 says its --import note is the source for the copies in game-architecture.md and asks to change them all together; the README copies added in Story 8.5 are not named there, so they can drift on the next engine bump. The fix edits an agent-context file (review pass 2, BH15).
    location: >-
      README.md "From source" / "Making a release", AGENTS.md section 3
    severity: low
---

<intent-contract>

## Intent

**Problem:** v1.0 can't ship yet. The Windows preset has no icon, nothing builds `DEFECTOR-v1.0-windows.zip` (exe + `README.txt` + credits), the repo `README.md` is a pre-implementation draft with outdated controls ("ship chases the mouse", "missile toward the cursor"), `RELEASE_NOTES.md` doesn't exist, and nothing checks the public repo for secrets or machine paths.

**Approach:** Add a project-owned SVG icon and a version to the project and preset, a stdlib packaging tool that builds the zip, a stdlib hygiene scanner over tracked files, the player-facing `release/README.txt`, a rewritten `README.md` and `RELEASE_NOTES.md`. Then export, package and smoke-test as far as an agent can. Pushing, `gh release create` and the hands-on Level 1 smoke test are owed to the operator.

## Boundaries & Constraints

**Always:** Stdlib-only Python tools with `unittest` tests in `tools/`, the same conventions as `tools/perf_check.py` (run from the repo root, `uv run python ...`, exit 0 pass / 1 fail / 2 usage error). Godot resources use relative `res://` paths. Docs match the current rules: the ship sits on the cursor (bottom 60% of the screen); hold LMB = laser; RMB = missile straight up (1.5 s cooldown); E = Shield (50 energy); Q = Barrage (100 energy, 12 homing micro-missiles); LMB advances comms and picks a choice; Esc pauses; F11 toggles fullscreen. Play always starts Level 1 through the opening, and Level Select jumps to unlocked levels. Only unlocks are saved (energy is not), in `%APPDATA%\DEFECTOR\`. Every new file under `game/assets/` gets a `CREDITS.md` row. Re-run the headless `--import` after adding the icon.

**Never:** No `git push`, no `gh` write and no release: those are operator actions. No changes to game flow, tuning, dialogue or levels. Never commit `game/export/`, `*.zip` or `game/.godot/`. Never write the operator's name, hostname, email or `LOCAL.md` values into a tracked file, the hygiene tool's patterns included. Don't touch `sprint-status.yaml`. Don't delete or move the operator's `%APPDATA%\DEFECTOR` save.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Package OK | exe exists, `release/README.txt`, `game/assets/CREDITS.md`, `config/version="1.0"` | `DEFECTOR-v1.0-windows.zip` at the repo root (or `--out`) with exactly `DEFECTOR.exe`, `README.txt`, `CREDITS.txt`, printed with sizes; exit 0 | — |
| Package, no exe | exe path missing | Nothing written | exit 2, names the missing path |
| Package, no version | `config/version` missing from `project.godot` | Nothing written | exit 2 |
| Hygiene clean | tracked files with placeholders only (`C:\Users\<name>`, `/home/me`, `/Users/host`, `example.com` emails, noreply addresses, the GUT font licence email) | `0 findings`, exit 0 | — |
| Hygiene hit | a tracked file with a real `X:\Users\someone\` path, `/Users/someone/`, a non-allowlisted email, a private-key header, a `ghp_`/`github_pat_`/`AKIA`/`xox?-`/`sk-ant-` token, or a tracked `.env`/`*.pem`/`*.key`/`*.pfx`/`*.p12`/`LOCAL.md`/`*.user.toml` | One `path:line: rule` line per finding (the matched text is never echoed in full), exit 1 | `--deny TEXT` (repeatable, case-insensitive) adds operator-supplied literals at run time only |

</intent-contract>

## Code Map

- `game/export_presets.cfg` -- `application/icon=""` today; `file_version`/`product_version` stay empty so Godot fills them from `application/config/version` (padded to `1.0.0.0`).
- `game/project.godot` `[application]` -- add `config/version="1.0"` and `config/icon` (window and taskbar icon).
- `game/tests/unit/test_export_preset.gd:29` -- pins `application/icon == ""` "no icon until Epic 8"; flip to the icon path.
- `game/assets/CREDITS.md` "Project-owned art" table (lines 58-64) -- add the icon row; `game/tests/data/test_data_files.gd:1181` `test_every_asset_file_is_credited` enforces it.
- `tools/perf_check.py` -- `size` / `launch` reused unchanged for the smoke test; its header docstring is the style template for the new tools.
- `tools/recolor_player_ship.py`, `tools/beat_audit.py` -- other stdlib-tool examples.
- `.gitignore` -- already ignores `game/export/`, `*.zip`, `*.tmp`, `game/.godot/`, `LOCAL.md` and `.bmad-loop/archive/`.
- `README.md` -- rewrite: premise, controls, download and run, credits, from source, BMAD artifacts kept.
- `_bmad-output/game-architecture.md` "Deployment Architecture" (~line 1305) and the directory tree (~line 597) -- update.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- last entry is #68; add #69.
- `_bmad-output/implementation-artifacts/epic-8-context.md` "Export" bullet -- says the icon is unset and `RELEASE_NOTES.md` doesn't exist; correct it to the 8.5 state.
- `_bmad-output/implementation-artifacts/spec-8-5-attempt-1.patch.tmp` (gitignored) -- the reviewed first attempt; see the Spec Change Log KEEP.
- Hygiene baseline, **text files**: no real user paths, secrets or real emails. The emails present are `example.com`/`example.test`/`test.com`/`company.com` samples in vendored skills, plus `mark@marksimonson.com` in `game/addons/gut/fonts/OFL.txt`. Placeholder paths in use: `C:\Users\<name>` (AGENTS.md), `/home/me`, `/Users/host` (vendored skills). Lowercase `/api/users/...` routes must not match.
- Hygiene baseline, **archives (known, pre-existing leak)**: four tracked run archives were committed before `.gitignore` ignored the folder, and they are already on `origin/main`: `.bmad-loop/archive/20261007-092930-9035.tar.gz`, `20261007-102223-b4f6.tar.gz`, `20261007-124327-8aef.tar.gz` and `20261007-155431-5f04.tar.gz`. Their logs and JSON hold the operator's absolute Windows user paths and Windows domain name, thousands of times, but no tokens or keys. The other `.bmad-loop/archive/*.tar.gz` files are untracked and ignored. AGENTS.md §1: never `git rm` them or hide them with a follow-up commit. The fix is a history rewrite and force-push, which is operator-only.

## Tasks & Acceptance

**Execution:**
- `game/assets/icon/defector_icon.svg` -- hand-authored 256×256 icon: a `background` #05070F rounded square and a bold coalition #22E6FF ship or chevron, still readable at 16 px, with no SVG filters -- the exe icon and window icon.
- `game/assets/CREDITS.md` -- add `| \`icon/defector_icon.svg\` | Hand-authored SVG, DEFECTOR (Story 8.5) | Project-owned |` -- the credits test.
- `game/project.godot` -- `config/version="1.0"`, `config/icon="res://assets/icon/defector_icon.svg"` -- single version source; runtime icon.
- `game/export_presets.cfg` -- `application/icon="res://assets/icon/defector_icon.svg"` -- exe icon.
- `game/tests/unit/test_export_preset.gd` -- the icon equals that path and loads as a 256×256 `Texture2D`; `ProjectSettings` `application/config/icon` is the same path; `application/config/version` is `"1.0"`; the existing absolute-path test still passes.
- `tools/godot_copyright.gd` -- a headless `extends SceneTree` script, run with the console Godot (`--headless --script`; add `--path game` only if it needs a project). It writes the engine's licence notice to the path given after `--`: `Engine.get_license_text()`, every `Engine.get_copyright_info()` component (name, files, copyright, licence) and every `Engine.get_license_info()` licence text, in the layout of Godot's own `COPYRIGHT.txt`. Godot's licence-compliance docs require the MIT notice plus the third-party notices (FreeType, mbedTLS, ENet and the rest) in a redistributed game.
- `release/GODOT_COPYRIGHT.txt` -- generated once by that script from the 4.7.2 console build and tracked. CRLF, like `release/README.txt`.
- `release/README.txt` -- player-facing plain text, CRLF line endings: what DEFECTOR is, how to run (unzip, run `DEFECTOR.exe`, the SmartScreen "More info → Run anyway" note for an unsigned exe), the controls table, the play flow (Play → opening → Level 1, Level Select), the save and log location `%APPDATA%\DEFECTOR\` (deleting it resets progress), about 10–15 minutes, and that the credits and the engine licence are in `CREDITS.txt`.
- `tools/package_release.py` -- `[--exe game/export/windows/DEFECTOR.exe] [--out DEFECTOR-v<version>-windows.zip]`. Reads the version from `game/project.godot`, then writes the zip (deflate, flat entries) per the matrix.
  - `CREDITS.txt` is `game/assets/CREDITS.md`, then a `Godot Engine` heading, then `release/GODOT_COPYRIGHT.txt`. The zip still holds exactly three entries. A missing `GODOT_COPYRIGHT.txt` exits 2 like a missing credits file.
  - The temp file is named `<zip stem>.partial.zip`, so `*.zip` ignores it if a crash leaves it behind.
  - It prints the next steps: the smoke test, then the operator-only `gh release create` line, naming the zip by its path relative to the current directory (absolute when it's elsewhere).
- `tools/test_package_release.py` -- the matrix rows with a fake exe in a temp dir. The missing-input case checks each of the exe, readme, credits and Godot copyright files in turn. Also test: the default target when `--out` is omitted (temporarily point `tool.REPO` at the temp dir and assert `DEFECTOR-v1.0-windows.zip` there and in the printed `gh` line); a failed write leaves no `.partial.zip`; `CREDITS.txt` contains the asset credits, `Godot Engine` and the copyright text. Docs: the real `release/README.txt` and `README.md` both name every control (Mouse, LMB, RMB, E, Q, Esc, F11), the 50 and 100 energy costs and `%APPDATA%\DEFECTOR`. `README.md` has the premise, controls, download/run and credits sections. `release/README.txt` and `RELEASE_NOTES.md` both contain `v<read_version()>`.
- `tools/repo_hygiene.py` -- scans `git ls-files` (and `--untracked`) by the matrix rules, with `--deny`, plus:
  - **Archives:** members of `.zip`, `.tar`, `.tar.gz`, `.tgz` and `.gz` files are scanned as text with stdlib `zipfile` / `tarfile` / `gzip`, and reported as `path!member:line: rule`. An archive that can't be opened is reported as `unreadable-archive`.
  - **Large files:** a text file or member over the 20 MB cap is reported as `unscanned-large`, never skipped silently. Other binaries (a NUL byte in the first 8 KiB) are skipped, and the summary counts them.
  - **User paths:** besides `X:\Users\<name>`, also match Git Bash / MSYS / WSL forms (`/c/Users/<name>`, `/mnt/c/Users/<name>`), with one or more backslashes or slashes as separators. Placeholders stay allowed: `<…>`, `%…%`, `$…`, `{…}`, the Windows system folders `Public`, `Default` and `All Users`, and generic stand-ins such as `someone`, `me`, `host`, `user`, `username` and `you`.
  - **Private keys:** also match the PGP `-----BEGIN PGP PRIVATE KEY BLOCK-----` header.
  - **Emails:** a noreply local part is allowed only at `users.noreply.github.com` or as an exact address in the allowlist (add `noreply@anthropic.com`), so `noreply@<any other domain>` is a hit.
  - **Sensitive files:** `.env` and `.env.*`, `LOCAL.md` (any case), `settings.local.json`, `*.user.toml`, `*.pem`, `*.key`, `*.pfx`, `*.p12`, `*.jks` and `*.keystore`.
  - **Deny:** blank or whitespace-only `--deny` values are ignored. A deny hit in a path prints that path with the denied text replaced by `***`.
  - **Line numbers:** lines split on `\r\n`, `\r` or `\n` only, so numbers match git's.
- `tools/test_repo_hygiene.py` -- every rule hits and misses on synthetic text (built from pieces, so the file holds no literal hit), including:
  - each new rule above, `noreply@` at a non-GitHub domain, and `/api/users/x` not matching;
  - placeholders allowed;
  - a temp `.tar.gz` and `.zip` with a hit in one member (`path!member:line`), plus a corrupt archive (`unreadable-archive`) and an over-cap file (`unscanned-large`, with the cap patched small);
  - `main(["--untracked"])` passing `True` to the lister, and `False` without the flag.
  - **Real-repo test:** every finding on the tracked tree is in one of the four `KNOWN_LEAKS` archive paths from the Code Map. Each `KNOWN_LEAKS` path is still tracked and still has findings, so the list must be emptied once the operator purges them. The comment says why: a pre-existing leak, purged by a history rewrite, never by `git rm`.
- `README.md` -- rewrite per the Code Map; status "v1.0", a link to Releases, a credits summary (Kenney and the OpenGameArt authors, CC0; Godot Engine under MIT, notices in the zip's `CREDITS.txt`) pointing at `game/assets/CREDITS.md`, and the release-tool commands, including how to regenerate `release/GODOT_COPYRIGHT.txt`.
- `RELEASE_NOTES.md` -- v1.0 notes: features, how to run (SmartScreen), requirements (Windows 10/11 64-bit, mouse), controls summary, save location, credits pointer (assets and the Godot licence in `CREDITS.txt`). No internal jargon, and no mention of the archive leak.
- `_bmad-output/implementation-artifacts/epic-8-context.md` -- fix the Export bullet: the icon is `res://assets/icon/defector_icon.svg`, `RELEASE_NOTES.md` exists at the repo root, and both tools exist (Story 8.5).
- `_bmad-output/game-architecture.md` -- Deployment steps 2-6: icon and version, `release/README.txt`, `release/GODOT_COPYRIGHT.txt` and its script, `package_release.py`, `repo_hygiene.py` (the rules above, and the known archive findings until the operator purges them) and the operator-only publish. Add `release/`, `RELEASE_NOTES.md` and `assets/icon/` to the tree.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- #69 record-only: the icon, version source, zip layout (`CREDITS.txt` with the Godot notices), tools, smoke-test results, the known archive leak (paths and kinds only, never the leaked values), and what's owed to the operator.

**Acceptance Criteria:**
- Given the templates are installed, when `--import` then `--export-release "Windows Desktop" export/windows/DEFECTOR.exe` runs, then it exits 0 and the exe carries the DEFECTOR icon (not Godot's), checked by extracting the exe's associated icon to a PNG and viewing it.
- Given that export, when `package_release.py` runs, then the zip holds exactly `DEFECTOR.exe`, `README.txt` (with the controls) and `CREDITS.txt` (asset credits plus the Godot licence and third-party notices), and `git status` shows no zip, `.partial.zip` or export file.
- Given the zip unpacked into an empty scratch folder, when `perf_check.py launch <folder>/DEFECTOR.exe --runs 3` runs, then every run reaches the title in under 5 s and `%APPDATA%\DEFECTOR\logs\godot.log` was freshly written.
- Given the repo, when `repo_hygiene.py --untracked` runs, then it exits 1, every finding is inside the four `KNOWN_LEAKS` archives, and a run with `--deny` for a string that appears nowhere adds no findings. The full GUT suite and every `tools/test_*.py` pass.

## Spec Change Log

### 2026-10-14 — Review loop 1 (bad_spec)
- **Triggering finding:** the hygiene scanner skipped binary files without reporting them (BH7/EC12). The tracked `.bmad-loop/archive/*.tar.gz` run archives, already on `origin/main`, hold the operator's absolute user paths and Windows domain name, yet the scan said "0 findings". The spec's Code Map baseline ("tracked files have no real user paths") and its "0 findings" AC were wrong, because planning grepped text files only. The other confirmed review findings were folded in too (Godot licence notices, Git Bash paths, PGP, noreply domains, env variants, deny redaction, line splitting, `.partial` naming, `gh` hint path, missing tests, version mentions, the stale epic context).
- **Amended:**
  - Code Map: corrected the baseline and added the known leak and the attempt-1 patch.
  - Tasks: added the archive, large-file and new-rule scanning; `tools/godot_copyright.gd`, `release/GODOT_COPYRIGHT.txt` and the `CREDITS.txt` composition; the package tool fixes and tests; the hygiene tests and the `KNOWN_LEAKS` real-repo test; the epic-context fix; the doc additions.
  - ACs: the `CREDITS.txt` content, no `.partial.zip`, and hygiene reporting only the known archives.
  - Design Notes: updated.
- **Known-bad state avoided:** a release gate that passes while tracked archives leak machine and employer details; a redistributed Godot exe without its licence notices.
- **KEEP:**
  - Start by applying `_bmad-output/implementation-artifacts/spec-8-5-attempt-1.patch.tmp` (`git apply`, falling back to `git apply --3way` or manual edits, without committing). It passed review on everything below, so keep these parts and amend only what this entry lists:
    - the icon SVG and its `.import`, the `project.godot` and preset values, and the GUT preset tests;
    - `release/README.txt` and its CRLF `.gitattributes` rule;
    - the `README.md` and `RELEASE_NOTES.md` text;
    - `package_release.py`'s structure (reading the version, the flat three-entry zip, CRLF text entries, atomic replace, exit codes, printed sizes);
    - `repo_hygiene.py`'s structure (the `Finding` dataclass, `line_rules`, `scan_text`, `scan_paths`, `git_files`, an injectable `list_files`, the `path:line: rule` output that never echoes the match, the allowlists);
    - the tests built from pieces;
    - the architecture and decision-log wording.
  - The verified results to keep in mind: GUT 2077/2077; release export 117.6 MB; zip 46.0 MB; launch 2.05 / 1.87 / 1.48 s; exe version 1.0.0.0 with the DEFECTOR icon.

## Review Triage Log

### 2026-10-14 — Review pass
- verdicts: 44 findings — high 2, medium 10, low 26, false 6, maybe-false 0
- findings:
  - `[medium]` `[bad_spec]` BH1 The zip ships a Godot exe without Godot's MIT notice or the third-party notices -- Godot's licence-compliance docs require them in the distribution. Amended: `godot_copyright.gd` and `GODOT_COPYRIGHT.txt` are appended to `CREDITS.txt`.
  - `[medium]` `[defer]` BH2 There is no repo `LICENSE` -- pre-existing, not caused by 8.5. Choosing a licence is the owner's decision.
  - `[low]` `[patch]` BH3 The `epic-8-context.md` Export bullet is stale (icon unset, no release notes) -- folded into the amended spec as an epic-context task.
  - `[medium]` `[patch]` BH4 Git Bash `/c/Users/<name>` and WSL `/mnt/c/Users/<name>` aren't matched -- confirmed: `line_rules('cd /c/Users/jdoe/proj')` is `[]`. Folded into the amended user-path rule.
  - `[low]` `[reject]` BH5 History, commit messages and author emails aren't scanned -- checked by hand: every author and committer is the noreply address or `bmad-loop@localhost`, and no commit message holds a user path or a real email. The leaking archives are still tracked, so the tree scan covers them. A history mode would be new surface.
  - `[low]` `[patch]` BH6 Sensitive names miss `.env.*`, `settings.local.json`, `*.jks` and `*.keystore` -- folded into the sensitive-file list.
  - `[high]` `[bad_spec]` BH7 Binary and large files are skipped without being named -- confirmed: four tracked `.bmad-loop/archive/*.tar.gz` (already pushed) hold the operator's user paths and Windows domain, yet the scan reported 0 findings. Amended: scan archive members, report `unreadable-archive` and `unscanned-large`, `KNOWN_LEAKS`, and an operator purge.
  - `[low]` `[reject]` BH8 `package_release` doesn't check that the exe is a fresh release build -- the documented sequence exports first. A check would need PE-resource parsing or heuristics, which is more than a direct correction.
  - `[low]` `[patch]` BH9 `1.0` is hard-coded in the docs -- folded in as a test that `release/README.txt` and `RELEASE_NOTES.md` contain `v<read_version()>`.
  - `[low]` `[reject]` BH10 No SHA-256 is published -- GitHub shows each release asset's digest on the release page, and this would add new surface.
  - `[medium]` `[patch]` BH11 Tests miss the missing-credits case, the default output and partial cleanup -- folded into the amended package tests (same as VG1/VG2).
  - `[low]` `[reject]` BH12 A locked zip or non-UTF-8 text gives a traceback, not a clean exit -- it fails loudly with exit 1, and the `finally` removes the partial file, so the behaviour is correct.
  - `[low]` `[reject]` BH13 `CREDITS.txt` is raw Markdown -- a deliberate Design Notes choice. It reads fine in Notepad, and converting it is more than a direct correction.
  - `[low]` `[reject]` BH14 No known-issues section -- the provisional items are internal operator checks, not verified player-facing defects.
  - `[low]` `[defer]` BH15 AGENTS.md doesn't mention the scanner and there is no `--staged` mode -- the fix edits an agent-context file.
  - `[low]` `[patch]` EC1 A leftover `.zip.partial` isn't ignored -- folded in: name it `.partial.zip`.
  - `[low]` `[reject]` EC2 Non-UTF-8 input, a directory target or a pre-1980 mtime gives a traceback -- a loud failure, nothing corrupt left behind.
  - `[low]` `[patch]` EC3 The `gh` hint names only `target.name` -- folded in: print the path relative to the current directory.
  - `[low]` `[reject]` EC4 A version with path separators -- the version is maintainer-controlled in `project.godot` and would fail loudly.
  - `[medium]` `[patch]` EC5 Git Bash and WSL paths aren't matched -- same root cause as BH4, folded in.
  - `[low]` `[patch]` EC6 Four-backslash escaped paths aren't matched -- folded in: one or more separators.
  - `[low]` `[patch]` EC7 The PGP private-key block header isn't matched -- folded in.
  - `[medium]` `[patch]` EC8 `noreply@` at any domain passes, which could expose an employer domain -- folded in: allowed only at the GitHub noreply domain or an exact allowlisted address.
  - `[low]` `[patch]` EC9 `.env.local` and a lower-case `local.md` aren't flagged -- same root cause as BH6, folded in.
  - `[low]` `[patch]` EC10 A whitespace-only `--deny` value matches everything -- folded in: ignore blank values.
  - `[low]` `[patch]` EC11 `splitlines` makes line numbers drift on `\f`, `\v` and similar -- folded in: split on `\r\n`, `\r` or `\n` only.
  - `[high]` `[bad_spec]` EC12 Large or UTF-16 files are skipped silently -- same root cause as BH7, amended as above.
  - `[low]` `[reject]` EC13 The index and history differ from the scanned tree -- see BH5. Checked by hand, and the tracked leak is covered by the tree scan.
  - `[low]` `[reject]` EC14 `icon@2x.png` would be a false email hit -- there is none in the repo, and a false positive fails loudly.
  - `[medium]` `[patch]` EC15 There is no missing-credits test -- folded into the amended tests.
  - `[low]` `[patch]` EC16 The epic-context Export bullet is stale -- same as BH3, folded in.
  - `[low]` `[patch]` EC17 A deny hit in a path echoes the denied text -- folded in: replace it with `***` in printed paths.
  - `[false]` `[reject]` EC18 `someone` is a placeholder but the matrix lists it as a hit -- the matrix row says "a real … path" and uses `someone` as a stand-in. Real names (`jdoe` in the tests) do hit. `Public` and `Default` are Windows system folders, not accounts.
  - `[low]` `[reject]` EC19 Read and write failures exit 1 with a traceback, against the exit-code convention -- same as BH12: a loud failure, which is correct.
  - `[medium]` `[patch]` VG1 The default zip name and location are never tested -- folded into the amended package tests.
  - `[medium]` `[patch]` VG2 The missing-credits case is named in a test but never run -- folded into the amended package tests.
  - `[medium]` `[patch]` VG3 Nothing checks that `--untracked` reaches the lister -- folded into the amended hygiene tests.
  - `[false]` `[reject]` VG4 The `someone` placeholder disagrees with the matrix -- see EC18.
  - `[false]` `[reject]` VG5 The new files aren't tracked, so they weren't scanned -- `repo_hygiene.py --untracked` gave 0 text findings, and the files are covered once committed.
  - `[false]` `[reject]` IA1 Finalization isn't done -- it runs at Finalize, after review.
  - `[false]` `[reject]` IA2 Save creation and Level 1 play were moved to the operator -- release builds have no autoplay or debug keys, so playing through Level 1 needs a human. It goes in `operator_actions`.
  - `[false]` `[reject]` IA3 The exe, zip and launch evidence is manual only -- the orchestrator re-ran the export, packaging, unzip and `perf_check launch` (2.05 / 1.87 / 1.48 s), and extracted the DEFECTOR icon and the 1.0.0.0 version from the exe.
  - `[low]` `[reject]` IA4 The doc tests only check substrings -- the orchestrator checked the energy rule against decision #60 and the pause labels against `pause_menu.tscn`. Semantic doc tests would be more than a direct correction.
  - `[low]` `[patch]` IA5 `epic-8-context` is stale -- same as BH3, folded in.

### 2026-10-14 — Review pass (loop 1 re-derivation)
- verdicts: 50 findings — high 0, medium 3, low 41, false 6, maybe-false 0
- findings:
  - `[low]` `[reject]` BH1 The scanner doesn't read `LOCAL.md` values as deny terms. `--deny` covers this at run time; parsing `LOCAL.md` would be a new feature, more than a direct correction.
  - `[low]` `[reject]` BH2 There is no rule for `DOMAIN\user`, `DOMAIN+user`, UNC paths or hostnames. A generic domain rule would flag many false positives. The operator's domain and host are checked with `--deny`, and the known leak is already caught through its user paths.
  - `[low]` `[reject]` BH3 UTF-16 text is skipped as binary. No tracked UTF-16 file exists, and the shell is PowerShell 7, which writes UTF-8. Handling it would add a new decode branch.
  - `[low]` `[reject]` BH4 Nested archives and the shipped zip are never scanned. The zip's text entries come from scanned tracked files. Nested archives would need recursion, and none exist in the repo.
  - `[low]` `[patch]` BH5 Token coverage gaps (ASIA, OpenAI, Google, GitLab, npm). Patched with new `TOKEN_RULES` rows and tests.
  - `[low]` `[reject]` BH6 An unreadable or missing working-tree file only counts as missing. This rarely happens, and reporting it would add a branch.
  - `[false]` `[reject]` BH7 The I/O matrix "Hygiene clean" row contradicts the ACs. That row describes synthetic tracked files with placeholders only, not the real repo, so there is no contradiction.
  - `[low]` `[patch]` BH8 The publish step doesn't pin the commit and the README omits the push. Patched: the README adds an operator-only `git push` step before `gh release create`.
  - `[low]` `[patch]` BH9 README step 3 fails with no explanation. Patched: the README notes the findings in the four archives until the history purge.
  - `[low]` `[patch]` BH10 There is no graphics requirement. Patched: Vulkan or Direct3D 12 graphics is listed in the README, the release notes and `README.txt`.
  - `[low]` `[patch]` BH11 Bug reports have no destination. Patched: the Issues page (a relative link in the README; the Issues tab in the release notes and `README.txt`).
  - `[medium]` `[patch]` BH12 Nothing ties the Godot notices to the engine version, and their layout is untested. Same root cause as VG1. Patched: the licence-text section and every licence block are asserted, and a GUT test checks that line 1 matches `Engine.get_version_info().string`.
  - `[low]` `[patch]` BH13 `godot_copyright.gd` doesn't check its write. Patched: `file.get_error()` is checked, and on an error it exits 1.
  - `[low]` `[patch]` BH14 The GUT results in decision log #69 disagreed with the KEEP. Patched: #69 now records the final 2077/2077. The orchestrator's final run was 2078/2078, including the new test.
  - `[low]` `[defer]` BH15 The README adds more copies of commands that AGENTS.md doesn't track. Fixing it means editing an agent-context file.
  - `[low]` `[patch]` BH16 The README's "only free CC0 assets" is wrong. Patched: it now says the third-party assets are CC0 and the project-made pieces are project-owned.
  - `[low]` `[patch]` BH17 The doc tests skip `RELEASE_NOTES.md` and some stale phrases. Patched: the controls check now covers the release notes, and the stale-phrase check covers all three docs.
  - `[low]` `[patch]` BH18 The README doesn't state the tool prerequisites. Patched: uv, or any Python 3 (stdlib only).
  - `[low]` `[reject]` EC1 File and member names aren't run through the content rules. No such names exist, and adding it means extra logic plus redaction.
  - `[low]` `[reject]` EC2 UTF-16 is skipped. See BH3.
  - `[low]` `[reject]` EC3 A tracked file missing from the working tree goes unreported. See BH6.
  - `[low]` `[reject]` EC4 Index and HEAD blobs can differ from the working copy. Carried: pass 1 EC13.
  - `[low]` `[patch]` EC5 `.tar.xz` / `.bz2` archives were skipped. Patched: the suffixes are added, with a `.tar.xz` test.
  - `[low]` `[reject]` EC6 Nested archives. See BH4.
  - `[low]` `[reject]` EC7 UNC, cygdrive and lowercase `/c/users` paths. These are rare, and matching lowercase `users` would hit web routes.
  - `[low]` `[patch]` EC8 Token gaps. Same as BH5, patched.
  - `[low]` `[patch]` EC9 `.ppk`, `.netrc`, `.npmrc` and `.pypirc` weren't treated as sensitive. Patched.
  - `[low]` `[reject]` EC10 Symlinks. None are tracked on this Windows checkout.
  - `[low]` `[reject]` EC11 Printing a non-cp1252 path to redirected output can raise `UnicodeEncodeError`. No such path exists, and the fix would be a guard.
  - `[low]` `[patch]` EC12 A `--deny` value with surrounding spaces kept them. Patched: values are stripped, with a test.
  - `[low]` `[patch]` EC13 Emails at reserved TLDs were flagged. Patched: `.test`, `.example`, `.invalid` and `.localhost` are allowed.
  - `[low]` `[reject]` EC14 `--out` pointing at a directory gives a traceback. Carried: pass 1 EC2 (fails loudly).
  - `[low]` `[reject]` EC15 Non-UTF-8 inputs give a traceback. Carried: pass 1 EC2.
  - `[low]` `[reject]` EC16 A version string with path characters. Carried: pass 1 EC4.
  - `[low]` `[reject]` EC17 A stale exe can be packaged. Carried: pass 1 BH8.
  - `[low]` `[reject]` EC18 Shell metacharacters in the printed `gh` path. Rare, and fixing it means quoting logic.
  - `[low]` `[patch]` EC19 Write errors in `godot_copyright.gd` went unchecked. Same as BH13, patched.
  - `[low]` `[patch]` EC20 The `gh`-line test broke on a temp path with a space. Patched: it accepts a quoted or unquoted path.
  - `[low]` `[patch]` EC21 The architecture smoke test dropped the save-creation check. Patched: step 5 restores it (a fresh save after the Level 1 clear).
  - `[low]` `[reject]` EC22 Splitting on a lone CR doesn't match git's line numbers. Lone-CR files are rare, and the fix would edit this build's spec text.
  - `[low]` `[patch]` EC23 The Slack rule missed `xoxc-`, `xoxd-` and `xoxe-` (the matrix says `xox?-`). Patched: `xox[a-z]-`.
  - `[false]` `[reject]` EC24 The `someone` placeholder vs the matrix. Carried: pass 1 EC18.
  - `[medium]` `[patch]` VG1 The Godot licence-text section and the version header were unverified. Patched together with BH12.
  - `[medium]` `[patch]` VG2 The preset's `file_version` / `product_version` were never asserted empty. Patched in `test_preset_options`.
  - `[false]` `[reject]` IA1 Finalization isn't done. Carried: pass 1 IA1.
  - `[false]` `[reject]` IA2 Save creation and Level 1 play go to the operator. Carried: pass 1 IA2.
  - `[false]` `[reject]` IA3 The exe and zip evidence is manual only. Carried: pass 1 IA3. The orchestrator re-ran everything after the patches: launches at 3.14 / 2.41 / 1.52 s, icon and version confirmed.
  - `[low]` `[patch]` IA4 The public docs spelled out what the leaked archives contain. Patched: the architecture doc, decision log #69 and the `KNOWN_LEAKS` comment now use neutral wording ("machine-specific run logs, history purge pending").
  - `[false]` `[reject]` IA5 `epic-8-context` was edited beyond the Export bullet. The extra condensing comes from step 1's epic-context recompile, not from the implementation.
  - `[low]` `[patch]` IA6 The GUT count was inconsistent. Same as BH14, patched.

## Design Notes

The version lives once, in `project.godot`, and the tool and the Windows file version both read it. `CREDITS.txt` is `CREDITS.md`'s text plus Godot's licence notices, under a name Windows opens with Notepad. Godot's compliance docs suggest shipping its `COPYRIGHT.txt`, and appending the notices keeps the zip at exactly three entries.

The hygiene scanner can't list the operator's own identifiers (that would publish them), hence `--deny` at run time. The four tracked archives are a pre-existing leak. Per AGENTS.md §1 they are reported to the operator and purged by a history rewrite, not hidden with `git rm`. Until then the CLI fails on them, which is the honest release gate. The unit test pins them as `KNOWN_LEAKS`, so any new leak still fails CI, and the list has to be emptied once they're purged. Tracked frontmatter already names the author display name, which was chosen and pushed before this story. That's out of scope, and it's mentioned to the operator rather than changed.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` then the GUT command from AGENTS.md -- expected: all tests pass
- `uv run python -m unittest discover -s tools -p "test_*.py"` -- expected: OK
- `uv run python tools/repo_hygiene.py --untracked` -- expected: exit 1, findings only under the four `KNOWN_LEAKS` archives
- the `--export-release` command, then `uv run python tools/perf_check.py size game/export/windows` -- expected: PASS under 200 MB
- `uv run python tools/package_release.py` -- expected: a zip with 3 entries, and `CREDITS.txt` contains `Godot Engine` and `FreeType`
- unzip into a scratch folder, then `uv run python tools/perf_check.py launch <scratch>/DEFECTOR.exe --runs 3` -- expected: all runs under 5 s

## Auto Run Result

Status: awaiting-operator

**Summary:** Story 8.5 is done as far as an agent can take it. The Windows export now has a project-owned icon and one version source (`config/version="1.0"`, giving exe version 1.0.0.0). `tools/package_release.py` builds `DEFECTOR-v1.0-windows.zip`, which holds `DEFECTOR.exe`, a player `README.txt`, and `CREDITS.txt` (the asset credits plus Godot's MIT and third-party notices). `tools/repo_hygiene.py` scans tracked files and archive members for secrets, real emails and machine paths. `README.md` is rewritten for v1.0 and `RELEASE_NOTES.md` is new. The export, packaging and clean-folder launch smoke test all passed on this machine. The push, the GitHub release, the hands-on Level 1 smoke play and a history purge of a pre-existing leak are owed to the operator (see `operator_actions`).

**Files changed:**
- `game/assets/icon/defector_icon.svg` (+ `.import`) -- new project-owned 256 px app icon.
- `game/assets/CREDITS.md` -- icon row.
- `game/project.godot` -- `config/version="1.0"`, `config/icon`.
- `game/export_presets.cfg` -- `application/icon`.
- `game/tests/unit/test_export_preset.gd` -- icon, version, empty file/product version, Godot notice header matches the engine.
- `release/README.txt` -- player readme (CRLF); `.gitattributes` -- CRLF rule for `release/*.txt`.
- `release/GODOT_COPYRIGHT.txt` and `tools/godot_copyright.gd` -- Godot licence and third-party notices, generated from the engine.
- `tools/package_release.py` and `tools/test_package_release.py` -- the zip builder and its tests, plus doc consistency tests.
- `tools/repo_hygiene.py` and `tools/test_repo_hygiene.py` -- the hygiene scanner (text files and archive members, `--deny`, `--untracked`) and its tests, including the `KNOWN_LEAKS` real-repo test.
- `README.md` -- rewritten for v1.0; `RELEASE_NOTES.md` -- new.
- `_bmad-output/game-architecture.md` -- Deployment steps and directory tree.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- entry #69.
- `_bmad-output/implementation-artifacts/epic-8-context.md` -- recompiled in step 1, Export bullet corrected.

**Review findings:**
- **Pass 1** (44 findings): one bad_spec loop. Planning had missed the tracked `.bmad-loop/archive/*.tar.gz` run archives, and the scanner skipped them as binary. The spec was amended and the code re-derived from the saved attempt. Two items were deferred (no `LICENSE`; AGENTS.md doesn't point at the scanner). Rejections and their reasons are in the triage log.
- **Pass 2** (50 findings): 24 patches applied, with patched entries at medium 2 (the Godot-notice verification, VG1 grouped with BH12; the empty preset versions, VG2) and low 22. One item was deferred (README command copies). 19 low findings and 6 false findings were rejected, with reasons in the triage log.
- **Follow-up review recommended:** false. Two medium entries were patched, but both are test additions that ran green in the full suites, so no unverified risk can be named.

**Verification (final, after the pass-2 patches):**
- Headless `--import`: exit 0.
- GUT: 2078/2078 passing.
- `tools/test_*.py`: 159 tests OK.
- `repo_hygiene.py --untracked`: exit 1 with 1246 findings, all inside the four `KNOWN_LEAKS` archives. A `--deny` for absent text adds none. A run-time deny scan of the changed files for the operator's identifiers hit only two pre-existing author lines, and no added line contains them.
- `--export-release`: exit 0. `perf_check size`: 117.6 MB, PASS.
- `package_release.py`: three entries; `CREDITS.txt` contains `Godot Engine` and `FreeType`; `README.txt` has the GPU and Issues lines.
- Unzipped into an empty scratch folder: `perf_check launch --runs 3` took 3.14 / 2.41 / 1.52 s, PASS.
- The icon extracted from the exe is the DEFECTOR delta, file version 1.0.0.0.
- `git status` shows no zip, `.partial.zip` or export file.

**Residual risks:**
- Four tracked run archives on `origin/main` expose machine-specific details until the operator rewrites history. Until then the hygiene CLI fails, and the `KNOWN_LEAKS` test must be emptied after the purge.
- The exe is unsigned, so players see a SmartScreen prompt; the docs explain it.
- Save creation and Level 1 play from the zip are not verified by an agent: release builds have no autoplay.
- The launch timings are warm-cache runs.

## Operator sign-off

2026-10-15: Story 8.5 is closed. The operator signed off Stories 8.1-8.4 (decision #89), chose the MIT licence and asked for a best-effort macOS build (decision #90). Both release zips were rebuilt and the Windows zip passed the launch smoke test. The repo passed the hygiene and full-history scans and main was pushed. Publishing the GitHub release (and any change to the repo's Issues setting) waits for the operator's explicit go-ahead.
