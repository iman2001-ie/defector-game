# AGENTS.md: DEFECTOR

Rules for every AI agent (and human) working in this repository. This is a **public** GitHub repo.

## 1. Never commit sensitive information

- **No secrets:** no passwords, API keys, tokens, private keys, certificates, `.env` files or credentials of any kind, in code, data, docs, commit messages or comments.
- **No personal or employer information:** no work email addresses, usernames inside absolute paths (`C:\Users\<name>\...`), machine names, internal hostnames, or employer, client or work-device details.
- **No machine-specific paths.** Use placeholders such as `<GODOT_DIR>`. Real local values belong in `LOCAL.md` (gitignored). Read it, but never copy its values into tracked files.
- **Personal config stays local:** `.claude/settings.local.json`, `_bmad/config.user.toml`, `_bmad/custom/*.user.toml` and `LOCAL.md` are gitignored. Don't un-ignore them or move their contents into tracked files.
- **Before every commit**, scan the staged diff for the items above. If anything sensitive was committed, stop and tell the user. Don't try to hide it with a follow-up commit; it needs history rewriting and credential rotation.
- **Commit identity** for this repo is the GitHub noreply address set in the repo-local git config. Never change it to a work email.

## 2. Ask before outward-facing actions

Get explicit user confirmation, each time, before you:
- push to a remote
- create, publish or delete a GitHub release, repo, issue or PR
- change repo visibility
- run any `gh` command that writes to GitHub

Local commits are fine when the user asks for them.

## 3. Project facts

- **Game:** DEFECTOR, a 2D neon fixed-screen space shooter with a light comms-driven story. Windows only, mouse and keyboard.
- **Engine:** Godot **4.7.2-stable**, statically typed GDScript, Forward+ renderer. The project lives in `game/` (created by Story 1.1). Use the console build at `<GODOT_DIR>` (see `LOCAL.md`) for headless runs.
- **Tests:** GUT 9.7.1 (`godot_4_7` branch), headless:
  `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import`
  (builds the `class_name` cache and imports the project's assets; this note is the source: `game-architecture.md`'s headless CLI block is a full copy and its CLI export block's import step is a short form that points back here, so change them all together. Run it on a fresh clone with no `game/.godot/`, and re-run it after adding, changing or removing a `class_name` declaration (including adding, renaming, moving or deleting a script that has one, changing the `extends` line or `@icon` of a script that keeps its `class_name`, or adding or removing `@abstract` or `@tool` on a script that keeps its `class_name`), after adding, changing, renaming, moving or deleting an imported asset, after any pull or branch switch, or whenever `game/.godot/` is stale, because headless `-s` runs don't rescan the class cache, and an asset has no up-to-date imported copy in the gitignored `game/.godot/imported/` until `--import` runs (the assets and their `.import` sidecars are tracked; the imported copies are not). Typical symptoms: a parse error naming a `class_name` that exists, or a preload or resource-load failure for an asset that exists), then:
  `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
- **Assets:** free or CC0 only (Kenney packs first). Every third-party asset must be listed in `game/assets/CREDITS.md` with its source and licence.

## 4. Planning documents are the contract

All of these are in `_bmad-output/`:

| What | Where |
|---|---|
| Game Design Document + decision log | `planning-artifacts/gdds/gdd-game-project-2026-10-06/` |
| Architecture | `game-architecture.md` |
| Epics and stories | `planning-artifacts/epics.md` |
| UX spec (layout, palette, dialogue model, HUD) | `planning-artifacts/ux-designs/ux-defector-game-2026-10-06/` (`DESIGN.md`, `EXPERIENCE.md`) |
| Readiness report | `planning-artifacts/implementation-readiness-report-2026-10-06.md` |

- Implement stories in epic order and follow their acceptance criteria.
- **Don't change design decisions silently.** If a story conflicts with the GDD, architecture or UX spec, ask the user. Record any decision they make in the relevant decision log.
- **Everything is data-driven.** Tuning numbers, waves and dialogue live in `game/data/*.json` and are read through `Config`. Never hard-code a GDD number.
- Follow the architecture's rules:
  - only `PauseArbiter` pauses
  - only `Feedback` touches `Engine.time_scale`
  - only `Spawner` creates entities
  - the HUD reads `Events` only
  - logging goes through `Log` (no bare `print()`)
- **Scope cut order:** COULD stories first, then SHOULD. Story 6.5 (Tarek's fall) is the last SHOULD to cut.

## 5. Hygiene

- Don't commit build output (`game/export/`, `*.zip`), the Godot cache (`game/.godot/`) or generated logs.
- Keep commits small, with a clear message. Story work must reference the story id or key: either the manual form `Story X.Y: summary` (e.g. `Story 1.2: ship chases cursor`) or the bmad-loop form `story <key>: ...`, where the key is the story file slug (e.g. `story 1-3-fire-the-laser: ...`). Other commits use:
  - bmad-loop deferred-work bundles: `sweep <bundle>: DW-n ...` (e.g. `sweep dw-wave-test-reliability: DW-35, DW-36, DW-39, DW-38 via bmad-loop`)
  - orchestration and bookkeeping, including retro commits made by bmad-loop or orchestration: `chore(<scope>): ...` (e.g. `chore(retro): epic 3 retrospective`, `chore(decisions): pre-answer DW-24`)
  - manual non-story work such as hand-written retros (first pass or revision) and correct-course: a clear summary of the change (e.g. `Epic 1 retro: revision 2`)
