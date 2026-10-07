---
title: 'Story 1.1: Set Up the Godot Project and Data-Driven Foundation'
type: 'feature'
created: '2026-10-07'
status: 'done'
baseline_revision: '65beb43fbc0aa08f013c9d02ae7be72866f5bd70'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
warnings: [oversized]
deferred:
  - summary: >-
      No automated check that the boot [INFO][data] summary line is emitted at INFO level.
    evidence: |-
      Verification-gap layer: removing _log_summary() from Config._ready() leaves all tests green; the line is only seen by reading GUT output. Capturing Log output needs a sink or last-line hook, which this story does not add.
    location: >-
      game/autoloads/config.gd:22
    severity: low
---

<intent-contract>

## Intent

**Problem:** The repo has no Godot project. Every later story needs the same project settings, collision layers, input actions, logging, event bus and a validated, data-driven tuning file before any gameplay can be built.

**Approach:** Create the Godot 4.7.2 (Forward+) project in `game/` with the architecture's settings, folder skeleton, layers and input map. Add the `Log`, `Events` and `Config` autoloads (in that order), `data/tuning.json` + `data/flags.json` holding every GDD number, and GUT 9.7.1 with a passing `test_config.gd`.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript (every var, param, return), tabs, snake_case files, no `class_name` on autoload scripts.
- `Log` is the only place that calls `print()`. Format `[LEVEL][category] message`; ERROR also `push_error`, WARN also `push_warning`; DEBUG dropped when `OS.is_debug_build()` is false. Categories are the fixed list `boot, scene, wave, beat, comms, spawn, combat, save, audio, data, debug` (unknown category → still log, plus a `push_warning`).
- `events.gd` = the architecture's Events catalogue verbatim (signals + typed params + comments), no logic.
- `Config` getters: `num(path) -> float`, `int_(path) -> int`, `flag(name) -> bool`, `section(path) -> Dictionary`. Dot paths walk nested dicts in `tuning`. `flag()` reads `flags`. Public vars `tuning: Dictionary`, `flags: Dictionary`, `load_error: String` (empty = OK). Public `load_data(tuning_path, flags_path)` (defaults to the `res://data/` files) and `reload()`; `_ready()` calls `load_data()` and logs one `Log.info("data", ...)` line.
- Missing key or wrong type: `Log.error("data", ...)` naming the full key path, then `assert`, then return `0.0`/`0`/`false`/`{}`. The assert is guarded by a public `assert_on_missing: bool = true` that tests set to `false` (a failed assert would abort the test function before the fallback is returned).
- JSON numbers are floats: counts/HP are stored as plain JSON numbers and read via `int_()`.
- Machine paths never appear in tracked files; use `<GODOT_DIR>`.

**Never:**
- No main scene, sandbox, PauseArbiter, EntityRegistry, Feedback, Audio, GameState, SaveManager, SceneRouter or DebugTools (later stories). Don't add autoloads beyond `Log, Events, Config`.
- No export preset (Story 1.7). No F5 key handling yet (only `Config.reload()` exists).
- Don't modify `sprint-status.yaml` or planning docs. Don't hard-code GDD numbers in scripts.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Typed float | `num("player.max_speed")` | `1400.0` (float) | none |
| Int from float JSON | `int_("player.hearts")` where JSON holds `5` (parsed as `5.0`) | `5`, `typeof == TYPE_INT` | none |
| Flag | `flag("tarek_fall")` / `flag("hunter_wasp")` | `true` / `false` | none |
| Section | `section("feedback.tiers")` | non-empty Dictionary | none |
| Missing key | `num("player.nope")`, `int_(...)`, `flag("nope")`, `section("nope")` | `0.0` / `0` / `false` / `{}` | `Log.error` with full path; assert only when `assert_on_missing` |
| Wrong type | `num("feedback.tiers")` (a dict), `section("player.max_speed")` (a number) | fallback value | same as missing |
| Bad tuning JSON | `load_data("res://tests/fixtures/bad_tuning.json", ...)` | `load_error` non-empty, `tuning == {}`, no crash | `Log.error("data", ...)` |
| Bad/missing flags JSON | invalid flags file | `flags == {}`, `load_error` unchanged by flags | `Log.error`; keep running (data error, not fatal) |
| Reload | `reload()` after good load | same values, `load_error == ""` | none |

</intent-contract>

## Code Map

Greenfield: nothing under `game/` exists yet. Reference material:

- `_bmad-output/game-architecture.md` -- Logging (~L389), Configuration (~L410), Events catalogue (L451–489, copy verbatim), Collision Layers (L276), Input Actions (L1067), Directory Structure (L517), Data Patterns `Config.num` excerpt (L1051), GUT setup (L1245–1254).
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md` + `decision-log.md` -- source of every tuning number; the decision log overrides the GDD body where they differ.
- `_bmad-output/implementation-artifacts/epic-1-context.md` -- distilled numbers and rules for Epic 1.
- `.gitignore` (root) -- already ignores `game/.godot/`, `game/export/`, `*.tmp`, `*.zip`; leave it alone.
- `LOCAL.md` (gitignored) -- holds the real `<GODOT_DIR>`; read it to run Godot, never copy it.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_config.gd` -- write first (red): cover every row of the I/O matrix, plus a check that `tuning` has exactly the 14 fixed sections and `flags` has the 4 flags with the stated defaults; set `Config.assert_on_missing = false` in `before_each` and restore (and re-`load_data()` the real files) in `after_each` -- TDD and isolation.
- `game/tests/unit/test_log.gd` -- `Log` formats `[INFO][boot] msg` (expose a pure `format(level, category, msg) -> String` helper to test) and drops DEBUG when not a debug build (make the debug check injectable, e.g. `var debug_enabled: bool = OS.is_debug_build()`) -- tests the log contract.
- `game/tests/fixtures/bad_tuning.json`, `game/tests/fixtures/bad_flags.json` -- deliberately invalid JSON -- parse-failure tests.
- `game/project.godot` -- create via headless Godot or by hand: name `DEFECTOR`, Forward+ (`rendering/renderer/rendering_method="forward_plus"`), viewport 1920×1080, window mode fullscreen (`3`), stretch `canvas_items`/`keep`, `rendering/viewport/hdr_2d=true`, `use_custom_user_dir=true` + `custom_user_dir_name="DEFECTOR"`, `debug/file_logging/enable_file_logging=true` and `.pc=true`, `debug/gdscript/warnings/untyped_declaration=1`, `layer_names/2d_physics/layer_1..8`, input actions (see Design Notes), autoloads `Log`, `Events`, `Config` in that order, GUT enabled in `[editor_plugins]` -- AC 1–3.
- `game/.gitignore` -- `.godot/`, `export/`, `*.tmp` -- AC 1.
- `game/{autoloads,core,entities,systems,scenes,ui,data,assets,tests}/` -- create; add `.gitkeep` to any otherwise empty folder so git keeps it -- AC 1.
- `game/autoloads/log.gd`, `game/autoloads/events.gd`, `game/autoloads/config.gd` -- per Boundaries -- AC 3–4.
- `game/data/tuning.json` -- 14 sections `player, weapons, abilities, energy, drops, enemies, boss, asteroids, convoy, allies, waves, comms, feedback, damage`, filled with every numeric GDD value (see Design Notes for mandatory key paths) -- AC 4.
- `game/data/flags.json` -- `{"surrender_prompts": true, "isolde_interruptions": true, "tarek_fall": true, "hunter_wasp": false}` -- AC 4.
- `game/addons/gut/` -- copy `addons/gut` from a shallow clone of `https://github.com/bitwes/Gut.git` branch `godot_4_7` (clone into the scratchpad, not the repo); confirm the version in `plugin.cfg` is 9.7.1 -- AC 5.
- Commit the `.uid` files Godot generates next to scripts.

**Acceptance Criteria:**
- Given the repo, when I open `game/project.godot`, then it holds every setting listed in the project.godot task, the 8 layer names `player, player_shots, enemies, enemy_shots, asteroids, pickups, convoy, allies` (1–8), all 14 input actions with their bindings, and autoloads `Log, Events, Config` in that order.
- Given the project, when it boots headless via a `-s` script run (the GUT command loads all autoloads; there is no main scene until Story 1.2), then the `[INFO][data]` load line prints, there are no script errors and `Config.load_error` is empty.
- Given `events.gd`, when compared to the architecture catalogue, then every signal and typed parameter matches and the file has no functions.
- Given GUT 9.7.1 in `game/addons/gut/`, when the headless GUT command runs, then `test_config.gd` and `test_log.gd` pass with 0 failures and no script errors.

## Design Notes

**Input map** (code uses only these names):
`fire_laser` LMB, `fire_missile` RMB, `ability_shield` E, `ability_barrage` Q, `comms_advance` LMB, `pause` Esc, `toggle_fullscreen` F11, and debug F1–F7 named after the architecture's Debug Tools table: `debug_overlay` F1, `debug_invincible` F2, `debug_resolve_wave` F3, `debug_add_energy` F4, `debug_reload_data` F5, `debug_skip_to_boss` F6, `debug_unlock_all` F7. Bind keys by physical keycode.

**Mandatory tuning key paths** (later stories and the architecture already reference them): `player.max_speed`, `player.hearts`, `enemies.<type_id>.hp` for `wasp, lancer, needle, bastion, maul, hunter_wasp`, `asteroids.<small|medium|large>.*`, `drops.<type_id>`, `feedback.tiers.<small|medium|large|boss_part|boss_death|player_hit|player_death>` each with `explosion_scale, shake_px, shake_s, hit_stop_ms, extras, sfx, sfx_pitch` (copy the architecture's `large` example shape), `waves.gap_s` (2.0), `comms.chars_per_s` (45), `damage.convoy_aimed` (5), `damage.convoy_stray` (2), `boss.final_choice_hp` (50). Use snake_case keys with unit suffixes (`_s`, `_ms`, `_px`, `_deg_s`) and `{"min": .., "max": ..}` objects for ranges. No keys outside the 14 sections (no top-level `_notes`). Where the GDD gives no number for a field the shape needs (e.g. a boss/player tier's `sfx_pitch`), use a neutral value (`1.0`, `0`, `[]`) rather than inventing a design number, and list each such placeholder in the final report.

**Lookup sketch:**
```gdscript
func _lookup(root: Dictionary, path: String) -> Variant:
	var node: Variant = root
	for part: String in path.split("."):
		if not (node is Dictionary and (node as Dictionary).has(part)):
			return null
		node = (node as Dictionary)[part]
	return node
```

**Headless gotcha:** before the first GUT run, import the project once (`--headless --path game --import`) so the global class cache knows `GutTest`.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0.
- (boot check is covered by the GUT command below: its output shows the `[INFO][data] Loaded ...` line, and `test_real_data_loads_without_error` asserts `load_error` is empty)
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, exit code 0.
- `git status --porcelain` -- expected: no `game/.godot/` files listed; `git grep -nI -i -e "users[/\\]" -e "c:[/\\]godot"` -- expected: no output (no machine paths tracked).

## Spec Change Log

- 2026-10-07 (step-03 verify): `--headless --path game --quit` cannot boot a project with no main scene (Godot stops with "no main scene defined" before autoloads load), and the spec forbids a main scene in this story. Amended the boot AC and Verification line to use a `-s` run (the GUT command). Avoids adding a premature boot scene. KEEP: no main scene until Story 1.2.

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 32 findings — high 0, medium 1, low 16, false 15, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) Missing-key assert fires after a tuning/flags load failure in debug builds — happens only in debug runs, which is the architecture's "fail loudly in debug" rule; release keeps running. Avoiding it adds load-state branches.
  - `[false]` `[reject]` (blind) Failed reload wipes last good data — the intent-contract matrix requires `tuning == {}` on a bad file; changing that means editing this spec. F5 handling belongs to Story 1.7.
  - `[low]` `[reject]` (blind) `int_()` silently truncates fractional values — only reachable by calling `int_` on a non-integer key (programmer misuse); a guard adds a branch.
  - `[low]` `[reject]` (blind) Load summary says "0 flags" after a flags failure and logs the error branch at INFO — the failure is already logged at ERROR by `_read_json_dict`; cosmetic.
  - `[low]` `[patch]` (blind) Untested Config branches (missing tuning file, non-object root, non-bool flag, reload with custom paths) — added 4 tests + fixtures `array_root.json`, `non_bool_flags.json`.
  - `[low]` `[patch]` (blind) Events catalogue has no automated check — added signal-name, arg-count and no-functions tests in `test_project_settings.gd`.
  - `[low]` `[reject]` (blind) Feedback tier test checks keys, not value types — type validation belongs to the data test (`test_data_files.gd`) and Feedback (1.6); not needed for this story.
  - `[false]` `[reject]` (blind) Placeholder list missing from the final report — it is in Auto Run Result below (not yet written at review time).
  - `[false]` `[reject]` (blind) Deferred work (F5 key, GUT export exclusion, `data/*.json` export filter) not recorded — already planned for Story 1.7 in epics.md.
  - `[false]` `[reject]` (blind) No `game/assets/CREDITS.md` despite vendored GUT — AGENTS.md requires credits for assets; GUT is a dev-only tool and ships its own `addons/gut/LICENSE.md`.
  - `[low]` `[reject]` (blind) `test_log.gd` checks return values, not printed output — proving output needs an injectable sink (new surface); format and push side effects are already tested.
  - `[false]` `[reject]` (blind) ERROR/WARN lines appear twice (print + push_*) — the story AC requires printing the line and also calling `push_error`/`push_warning`.
  - `[low]` `[reject]` (blind) Unknown-category warning can flood the log — only on a mistyped category; dedup adds state.
  - `[false]` `[reject]` (edge) reload wipes last-good data — same as the blind finding; the spec matrix requires it.
  - `[low]` `[reject]` (edge) `int_` truncates 0.15 to 0 — misuse only (chances are read with `num`).
  - `[low]` `[reject]` (edge) `flag()` asserts in debug after a flags-file failure — fail-loudly in debug by design; release keeps running.
  - `[low]` `[reject]` (edge) `num()` asserts in debug after a tuning failure before `load_error` is shown — no code reads tuning after a fatal load (the boot scene shows the error and stops); fail-loudly by design.
  - `[low]` `[reject]` (edge) Summary hides flags failure — duplicate of the blind finding; cosmetic.
  - `[low]` `[reject]` (edge) `emit_line` accepts unknown levels — callers use the four wrappers; a guard adds a branch.
  - `[false]` `[reject]` (edge) LMB bound to both `fire_laser` and `comms_advance` — required by the architecture's Input Actions table; the comms panel will consume the click (later story).
  - `[low]` `[reject]` (edge, claim) Spec says a flags failure "keeps running", but debug asserts — true for debug only; release behaviour matches; same root as the assert findings.
  - `[medium]` `[patch]` (verification-gap) project.godot input map, layers and autoload order not pinned by tests — added `game/tests/unit/test_project_settings.gd` (14 actions with bindings, 8 layer names, autoload order).
  - `[low]` `[patch]` (verification-gap) `Log.debug()` wrapper's release-build drop untested — wrappers now return `emit_line`'s bool; added a wrapper test.
  - `[low]` `[patch]` (verification-gap) `reload()` reuse of custom paths not observed — covered by the reload-after-BAD_TUNING test (filed as defer; cheap enough to patch).
  - `[low]` `[defer]` (verification-gap) Boot `[INFO][data]` line not asserted — recorded in frontmatter `deferred`.
  - `[false]` `[reject]` (intent) "Game boots" checked via a `-s` script run — there is no main scene until Story 1.2 by plan; autoloads load the same way; recorded in Spec Change Log.
  - `[false]` `[reject]` (intent) DEBUG drop tested via an injectable flag — the flag defaults to `OS.is_debug_build()`; that is the contract.
  - `[low]` `[reject]` (intent) Assert branch never runs under test — a failing assert would abort the test; can't be tested in GUT.
  - `[false]` `[reject]` (intent) Tuning completeness against the GDD is not tested — reviewer spot-checks matched the GDD; placeholders listed below.
  - `[false]` `[reject]` (intent) No scene displays `load_error` yet — display belongs to the Epic 4 boot/title scene by plan.
  - `[false]` `[reject]` (intent) Input Map verified only by reading the file — now pinned by `test_project_settings.gd` (see patch above).
  - `[false]` `[reject]` (intent) Spec widens scope beyond the epic (`test_log.gd`, stricter bar) — adds coverage, no defect.


### 2026-10-07 — Review pass
- verdicts: 29 findings — high 0, medium 0, low 18, false 11, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) AC 1 display, rendering, user-dir, file-logging, warning and GUT plugin settings are not tested — added `test_display_rendering_and_debug_settings` (13-entry setting table) and `test_gut_plugin_enabled` to `test_project_settings.gd`.
  - `[false]` `[reject]` (blind) Autoload test checks names only, so a wrong path or dropped `*` would pass — every test file references the `Log`/`Config`/`Events` globals; a wrong path or missing `*` stops those scripts compiling and the suite fails.
  - `[false]` `[reject]` (blind) Config has no schema check, so a missing section is a silent `0.0` in release — not silent: every failed lookup calls `Log.error` with the full key path (`config.gd:86-90`), which is the contract's missing-key behaviour.
  - `[false]` `[reject]` (blind) A broken flags file silently disables story flags — not silent: the load failure and every failed `flag()` read are logged at ERROR; `flags == {}` with a `false` fallback is the contract's matrix row.
  - `[false]` `[reject]` (blind) `reload()` is not atomic and emits no "reloaded" signal — carried: the matrix requires `tuning == {}` on a bad file; F5 and any reload consumers arrive in Story 1.7, and no system caches tuning yet.
  - `[low]` `[reject]` (blind) Tests pin shipped tuning values (1400, 45, 5, 2, 50, flag defaults), so a tuning pass turns the suite red — the I/O matrix and Design Notes fix these values as the acceptance check; changing that edits this spec.
  - `[low]` `[defer]` (blind) Boot `[INFO][data]` line not asserted; failure summary logs at INFO and reports "0 flags" — carried: already in frontmatter `deferred` (not re-added); the summary-content part is the logged cosmetic reject.
  - `[false]` `[reject]` (blind) Release builds ship F1–F7 debug bindings, tests and GUT — carried: export filters and DebugTools gating are planned for Story 1.7; no export preset exists, and no handler reads the debug actions yet.
  - `[low]` `[reject]` (blind) `int_()` silently truncates fractional values — carried: only reachable by misuse (fractions are read with `num`); a guard adds a branch.
  - `[low]` `[reject]` (edge) `int_()` truncates e.g. `drops.wasp.chance` — carried, same as above.
  - `[low]` `[reject]` (edge) Debug assert fires on first lookup after a failed tuning load — carried: fail loudly in debug by design; release keeps running.
  - `[low]` `[reject]` (edge) Summary reports success with 0 flags after a flags failure — carried: cosmetic, and the failure is already logged at ERROR.
  - `[low]` `[reject]` (edge) Non-bool flag values are not checked at load, only at first read — the read logs an ERROR with the key path; a load-time scan adds a loop for a hand-edit typo.
  - `[false]` `[reject]` (edge) No typed `str_`/`arr` getters for string/array leaves — the contract defines exactly four getters; no caller needs string or array leaves in this story, and `section()` returns a copied Dictionary.
  - `[low]` `[reject]` (edge) `emit_line` accepts unknown levels — carried: callers use the four wrappers; a guard adds a branch.
  - `[false]` `[reject]` (edge) LMB bound to both `fire_laser` and `comms_advance` — carried: required by the architecture's Input Actions table; the comms panel consumes the click (later story).
  - `[low]` `[patch]` (edge, claim) Events test checks argument counts, not types — `EVENTS` now maps each signal to its `Variant.Type` list, and `test_events_catalogue_signals_and_arg_types` asserts the declared types.
  - `[low]` `[reject]` (edge) A locked/unreadable data file reports "parse error at line 0" — `res://` data files ship inside the pack and can't be locked; distinguishing read errors adds a branch.
  - `[low]` `[patch]` (verification-gap) project.godot settings from AC 1 not checked by any test — same root as the first blind row; fixed by the same settings-table test.
  - `[low]` `[patch]` (verification-gap) Events test does not check typed parameters (AC 3) — same root as the edge claim row; fixed by the same arg-type test.
  - `[low]` `[reject]` (intent) Assert path never runs under test — carried: a failing assert aborts the GUT test function; it can't be tested in GUT.
  - `[low]` `[reject]` (intent) DEBUG drop tested via the injectable flag, and a DEBUG line with an unknown category in release gives no `push_warning` — the flag part is carried `false` (it defaults to `OS.is_debug_build()`); in debug builds the warning still fires, and in release the whole line is dropped by contract, so no developer misses it.
  - `[low]` `[reject]` (intent) Log tests check the formatter and pushed text, not the printed line — carried: capturing output needs a new sink surface.
  - `[false]` `[reject]` (intent) `tuning.json` accuracy against the GDD is not tested — carried: reviewer spot-checks (here and last pass) matched the GDD tables; placeholders are listed in the result.
  - `[low]` `[patch]` (intent) Events "verbatim" checked only for names and counts — same root as the edge claim row; arg types now pinned.
  - `[false]` `[reject]` (intent) Lookup errors name the key path but not the file — the `tuning.`/`flags.` prefix names the file (one file each), and the contract asks only for the full key path.
  - `[false]` `[reject]` (intent) `reload()` re-reads the last paths and a bad reload empties tuning — carried: production paths are the defaults; the matrix requires `{}`; F5 belongs to Story 1.7.
  - `[low]` `[reject]` (intent) `int_()` silently truncates `player.iframes_s` — carried, same as the `int_` rows above.
  - `[false]` `[reject]` (intent) "Log is the only print()", "no class_name on autoloads" and full typing have no automated check — all three hold in the diff; `untyped_declaration=1` warns on untyped code, and no defect exists to catch.

## Auto Run Result

Status: done

**Summary:** Follow-up review pass on Story 1.1. The Godot 4.7.2 (Forward+) project in `game/` was already built: settings, folder skeleton, 8 collision layers, 14 input actions, the `Log`, `Events` and `Config` autoloads, GDD-sourced `tuning.json` / `flags.json`, and GUT 9.7.1 with passing tests. This pass found two test-only gaps and closed them. No production code changed.

**Files changed (this pass):**
- `game/tests/unit/test_project_settings.gd` -- now pins the AC 1 settings (name, user dir, renderer, HDR 2D, viewport, window mode, stretch, file logging, untyped-declaration warning), checks that the GUT plugin is enabled, and checks every Events argument type, not just the count.

**Files from the original run (unchanged here):** `game/project.godot`, `game/.gitignore`, `game/*/.gitkeep`, `game/autoloads/{log,events,config}.gd`, `game/data/{tuning,flags}.json`, `game/tests/unit/{test_config,test_log}.gd`, `game/tests/fixtures/*.json`, `game/addons/gut/` (vendored GUT 9.7.1, MIT), `*.uid`.

**Review findings:** 29 findings (low 18, false 11).
- 5 rows patched, covering 2 root causes, all low: AC 1 settings untested; Events arg types untested.
- 1 row carried as an existing deferral (boot line not asserted); not re-added.
- 23 rejected; each reason is in the Review Triage Log above.

The vendored `game/addons/gut/` tree was left out of the reviewed diff (unmodified third-party code; `plugin.cfg` reads `version="9.7.1"`).

**Follow-up review recommendation:** false. This is a follow-up pass and patched no `high` (patched by verdict: high 0, medium 0, low 2 entries).

**Verification:**
- `--headless --path game --import`: exit 0.
- GUT headless command: 41/41 tests and 263 asserts passed, exit 0. The `[INFO][data] Loaded res://data/tuning.json (14 sections) and res://data/flags.json (4 flags)` line prints. No script errors.
- `git grep` machine-path scan of `game/`: no matches. `git status`: no `game/.godot/` files.

**Neutral placeholders in `tuning.json` (no GDD number exists):** `sfx_pitch` is 1.0 on every feedback tier except `large` (0.8, from the architecture). Tier `sfx` ids are named after the tier (`explosion_boss_part`, `explosion_boss_death`, `player_hit`, `player_death`). `extras` is `[]` for `boss_part` and `player_death`. `small` uses 0 shake and hit-stop (the GDD's "none").

**Residual risks:**
- No main scene until Story 1.2, so a normal launch (not through a `-s` script) reports "no main scene".
- The F2–F6 debug action names come from the architecture's Debug Tools table; the docs name only F1 and F7.
- In debug builds, reading a key after a failed data load triggers an assert (fail loudly, by design).
- A failed `reload()` empties tuning; this matters once Story 1.7 wires F5.
