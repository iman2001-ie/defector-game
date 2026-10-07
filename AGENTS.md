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
  (one-time, on a fresh clone with no `game/.godot/`: builds the `class_name` cache and imports the WAVs that `Audio` preloads), then:
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
- Keep commits small, with a clear message that references the story id (e.g. `Story 1.2: ship chases cursor`).
