---
title: 'Story 1.7: Validate the Core Feel in a Stress-Tested Sandbox'
type: 'feature'
created: '2026-10-07'
baseline_revision: 'c423c0e22defc4663fee41746909febcdef7e7d8'
status: done
review_loop_iteration: 0
followup_review_recommended: true
operator_actions:
  - 'Fun gate: 2-minute sandbox playtest by the developer and at least one colleague ("Was the shooting fun on its own?"); log any tuning change in the GDD decision log (DW-3 missile splash vs grid_4x2 spacing is a candidate).'
  - 'Stress overlay: run `<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe --path game -- --stress`, hold fire, watch the F1 overlay frame ms stay under 16.6; then set decision-log row 27 from "pending operator confirmation" to confirmed. Also try F5 after editing data/tuning.json.'
  - 'Glow look: launch the exported build (game/export/windows/DEFECTOR.exe, copied outside the repo) and judge the WorldEnvironment bloom; glow values in sandbox.tscn are art constants to tune.'
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
warnings: [multiple-goals, oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** The sandbox has no debug overlay, no F5 hot reload, no stress mode, no `WorldEnvironment` glow and no export preset. Without these, the E1 go/no-go gate (NFR1 frame budget, fun check, export smoke check F19) cannot be run.

**Approach:**
- Add the architecture's `DebugTools` node (`ui/debug/`) in an `Overlay` CanvasLayer. F1 toggles the overlay and F5 reloads the data and restarts the sandbox. It is a no-op in release builds.
- Add a command-line stress mode (40 Wasps, refilled as they die) and a self-timing `--bench=N` variant that holds fire, logs frame stats and quits.
- Add the glow `WorldEnvironment` and a committed Windows Desktop export preset.
- Then do everything an agent can: install the export templates, run the bench on this machine, record the renderer decision, and export the build and smoke-test it outside the repo.
- Leave the human-only checks as operator actions: the fun playtest with a colleague, watching the overlay, and looking at the glow.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript, tabs, `Log` only (category `debug`), no per-frame logging, string building, group scans or allocation in hot paths. Input via action names only (`debug_overlay` F1, `debug_reload_data` F5, `fire_laser`).
- **DebugArgs** (`ui/debug/debug_args.gd`, `class_name DebugArgs extends RefCounted`): `static func parse(args: PackedStringArray) -> Dictionary` → `{"stress": bool, "bench_s": float}`. `--stress` sets stress. `--bench=<seconds>` with a positive number sets `bench_s` and implies stress. A malformed or non-positive bench value logs `Log.warn("debug", …)` and leaves `bench_s` at 0. Unknown args are ignored. Callers pass `OS.get_cmdline_user_args()` (the args after `--`).
- **FrameStats** (`ui/debug/frame_stats.gd`, `class_name FrameStats extends RefCounted`):
  - `_init(capacity: int)` preallocates a `PackedFloat32Array`. `add(ms: float)` stores samples until full, then ignores the rest. `clear()` resets it.
  - Read-outs: `count()`, `average_ms()`, `max_ms()` and `percentile_ms(p: float)` (nearest-rank on a sorted copy, called only at report time). All are 0 when empty.
- **DebugTools** (`ui/debug/debug_tools.tscn` + `.gd`, `class_name DebugTools extends Node`, `process_mode = ALWAYS`) has a `Label` child for the overlay (top-left, small, coalition cyan text on a dark translucent panel; the art constants live in the script or scene).
  - `var debug_enabled: bool = OS.is_debug_build()` (tests override it before `add_child`). When it is false, `_ready` hides the overlay, disables process and input, and returns. No other method does anything.
  - `_unhandled_input`: `debug_overlay` pressed → `toggle_overlay()`. `debug_reload_data` pressed → `reload_data()`.
  - The overlay shows FPS (`Engine.get_frames_per_second()`), frame ms (average and max over the refresh window), node count (`Performance.OBJECT_NODE_COUNT`) and enemies alive (`get_tree().get_node_count_in_group(&"enemies")`).
  - Frame ms is real wall time between `_process` calls (`Time.get_ticks_usec()`), so it stays correct during hit-stop.
  - The label text is rebuilt only every `OVERLAY_REFRESH_S` (0.25 s) and only while visible. `refresh_overlay()` is public so tests can force it.
  - Overlay visibility is a `static var`, so it survives an F5 restart. It starts visible in stress mode.
  - `reload_data() -> bool` calls `Config.reload()`. If `Config.load_error` is non-empty, it logs `Log.error("debug", …)`, does not restart and returns false. Otherwise it calls `Feedback.reset()`, `Feedback.load_tiers()` and `PauseArbiter.clear()`, logs one info line, calls `restart_scene` and returns true. `var restart_scene: Callable` defaults to `get_tree().reload_current_scene`; tests inject their own.
  - In stress mode (`DebugArgs` stress), `_ready` sets `DisplayServer.window_set_vsync_mode(VSYNC_DISABLED)` so frame ms measures work, not the display wait.
  - In bench mode it also calls `Input.action_press(&"fire_laser")`, skips the first `BENCH_WARMUP_S` (2.0 s, real time), then collects frame ms into a `FrameStats` for `bench_s` seconds. It then logs one line: `Stress bench: frames=N avg=A ms p99=P ms max=M ms enemies=E renderer=<rendering_method> result=PASS|FAIL`, where PASS means avg < `FRAME_BUDGET_MS` (16.6). It calls `Input.action_release(&"fire_laser")` and `get_tree().quit(0 if PASS else 2)`.
- **Sandbox:** new child `Overlay` (`CanvasLayer`, layer 30) containing a `DebugTools` instance, and a `WorldEnvironment` child.
  - The environment: `background_mode = BG_CANVAS`, `glow_enabled = true`, art-constant glow values (intensity about 0.8, `glow_hdr_threshold` about 0.6 so the 1.0-bright neon colours bloom, small bloom). Visual tuning is a playtest item.
  - `var stress_mode: bool = false`. In `_ready`, it is set when `OS.is_debug_build()` and `DebugArgs.parse(OS.get_cmdline_user_args()).stress`; tests may set it before `add_child`.
  - In stress mode the sandbox spawns `STRESS_COLUMNS × STRESS_ROWS` (10 × 4 = 40, the NFR1 stress count) Wasps at spacing (160, 72) from y 150, centred on x. That grid lies inside the enemy zone y 120–432. This replaces the 8-Wasp formation.
  - Each resolved stress Wasp is replaced at its own slot (deferred), so 40 stay alive. Asteroids keep spawning as before. These grid values are debug-scene constants like the existing `FORMATION_*`.
- **Export preset** (`game/export_presets.cfg`, committed, relative paths only):
  - `[preset.0]` named `Windows Desktop`, platform `Windows Desktop`, `runnable=true`, export filter all resources.
  - `include_filter="data/*.json"`, `exclude_filter="addons/gut/*, tests/*"`, `export_path="export/windows/DEFECTOR.exe"`.
  - `[preset.0.options]` sets `binary_format/embed_pck=true`, `binary_format/architecture="x86_64"`, `application/product_name="DEFECTOR"`, `codesign/enable=false`, and no icon (Epic 8). Generate the preset with the editor's defaults if possible, so Godot accepts every option key.
- **Export templates:** download the official `Godot_v4.7.2-stable_export_templates.tpz` from the godotengine GitHub release into a new empty scratch directory. Unzip it and install its `templates/` contents into `%APPDATA%/Godot/export_templates/4.7.2.stable/`. Check that `version.txt` reads `4.7.2.stable` first. This is machine-local and never committed.
- **Renderer decision:**
  - Run the bench on this machine, fullscreen at 1920x1080: `<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe --path game -- --bench=20`.
  - If it FAILs, switch `rendering/renderer/rendering_method` to `gl_compatibility` per ADR-003 (glow sprites already use additive `CanvasItemMaterial`), update the settings test and re-run the bench.
  - Append GDD decision-log row 27 with the renderer kept or switched and the measured avg, p99 and max. Mark it pending the operator's on-overlay confirmation.
- **Export smoke check:**
  - Run `--headless --path game --import`, then `--headless --path game --export-release "Windows Desktop" export/windows/DEFECTOR.exe`.
  - Copy the exe to a scratch directory outside the repo and run it there with `--quit-after 300`.
  - `%APPDATA%/DEFECTOR/logs/godot.log` must then contain `[INFO][data] Loaded res://data/tuning.json` and no `SCRIPT ERROR`. Fix any export problem now (decision F19).
- `sprint-status.yaml` is never written. Final status is `awaiting-operator` with `operator_actions`.

**Never:**
- No new input actions or key bindings. No F2–F4, F6, F7 or F8 tools.
- No HUD and no `SceneRouter`.
- No change to gameplay tuning, entity rules or Feedback tiers.
- No pooling or explosion cap. Only measure them (DW-4, DW-5).
- No `instantiate()` outside `core/spawner.gd` plus `scenes/` and `ui/`.
- No `Engine.time_scale` writes outside `feedback.gd`. No `get_tree().paused` writes outside `PauseArbiter`.
- No machine paths in tracked files.
- Never claim fun, feel or glow look verified.
- No push, release or `gh` writes.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Args | `["--stress"]`; `["--bench=20"]`; `[]`; `["--bench=abc"]`; `["--bench=-1"]` | stress true/bench 0; stress true/bench 20; false/0; false/0; false/0 | one `Log.warn` per bad bench |
| F1 | debug tools enabled, `debug_overlay` pressed twice | overlay visible, then hidden | none |
| Overlay text | sandbox (8 Wasps), `refresh_overlay()` | label contains FPS, frame ms, node count and `enemies 8` | none |
| Release | `debug_enabled = false`, F1 and F5 events | overlay hidden; no reload; restart callable not called; process off | none |
| F5 reload | temp tuning with `feedback.tiers.large.shake_px` 8 → edited to 12, F5 | `Config` returns 12; `Feedback.tier_row(LARGE)` shake 12; restart callable called once; returns true | none |
| F5 bad JSON | temp tuning edited to invalid JSON, F5 | returns false; restart not called | `Log.error` |
| Stress grid | sandbox with `stress_mode = true` | 40 Wasps in Enemies, all x in [0, 1920], y in [120, 432] | none |
| Stress refill | kill one stress Wasp, await a frame | 40 Wasps again, the new one at the dead one's slot | none |
| Normal sandbox | `stress_mode = false` | 8-Wasp formation as before | none |
| FrameStats | capacity 4; add 10, 20, 30, 40, 50 | count 4; avg 25; max 40; p99 40; p50 20; empty → 0 | none |
| Glow | load sandbox | a `WorldEnvironment` with glow on and `BG_CANVAS` | none |
| Export preset | parse `res://export_presets.cfg` | the preset values listed in Boundaries | none |

</intent-contract>

## Code Map

- `game/scenes/sandbox/sandbox.gd` / `.tscn` -- add `stress_mode`, the stress grid with per-slot refill (mirror `formation_slots`/`spawn_formation`/`_on_wasp_resolved`, using `.bind(slot)`), and the `Overlay`/`DebugTools` and `WorldEnvironment` nodes. Spawning stays in `_spawner.spawn_enemy(&"wasp", {"position": slot})`. Refill with `call_deferred`, because `resolved` fires inside physics callbacks.
- `game/autoloads/config.gd:43` `reload()` -- already reloads both files with the last paths. `load_data(path, path)` lets tests point at temp files; restore with `Config.load_data()` afterwards.
- `game/autoloads/feedback.gd:26` `load_tiers()`, `:49` `tier_row()`, `:116` `reset()` -- what F5 must refresh (Feedback is an autoload, so a scene restart does not re-read its cache).
- `game/autoloads/pause_arbiter.gd:31` `clear()`.
- `game/core/enemy.gd:43` -- enemies join group `&"enemies"`. `:67` `_die()` emits `resolved`.
- `game/entities/player/player.gd:100` -- the laser reads `Input.is_action_pressed(&"fire_laser")`, so `Input.action_press` drives it in bench mode.
- `game/entities/enemies/wasp/wasp.tscn` -- 64 px sprite; Wasps hold their spawn position.
- `game/project.godot` -- the `debug_overlay` (F1) and `debug_reload_data` (F5) actions already exist; `renderer/rendering_method="forward_plus"`.
- `game/tests/unit/test_sandbox.gd` -- patterns for loading the sandbox (`add_child_autofree`, PauseArbiter cleanup). `test_project_settings.gd:119` asserts the renderer (update it only if the bench forces Compatibility).
- GUT fails tests on unasserted `push_error` (`Log.error`). Use `assert_push_error`/`assert_engine_error` or GUT's error helpers where an error is expected (bad JSON F5), as existing tests do.
- `_bmad-output/implementation-artifacts/deferred-work.md` DW-3/4/5 -- settled by the bench (max frame ms covers the first large explosion and explosion load) and by the playtest (DW-3 tuning).

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_debug_args.gd`, `test_frame_stats.gd`, `test_debug_tools.gd`, `test_export_preset.gd` -- new; extend `test_sandbox.gd` with stress grid/refill/normal/glow/Overlay rows -- write first (red), covering every I/O row.
- `game/ui/debug/debug_args.gd`, `frame_stats.gd`, `debug_tools.gd` + `debug_tools.tscn` -- implement per Boundaries.
- `game/scenes/sandbox/sandbox.gd`, `sandbox.tscn` -- stress mode, Overlay + DebugTools, WorldEnvironment.
- `game/export_presets.cfg` -- Windows Desktop preset.
- `%APPDATA%/Godot/export_templates/4.7.2.stable/` (machine-local) -- install templates as in Boundaries.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- row 27 (renderer decision with bench numbers); `game/project.godot` and `test_project_settings.gd` only if the bench fails.

**Acceptance Criteria:**
- Given the headless GUT command, when run, then all tests pass with no script errors, and a headless 120-frame sandbox boot exits cleanly.
- Given the bench run on this machine, when it finishes, then the log holds one `Stress bench:` line with `enemies=40`, the process exits, and decision-log row 27 records the renderer and numbers.
- Given installed templates, when the release export runs and the exe is launched from outside the repo, then it exits cleanly and its log shows tuning loaded.
- Given the codebase, when grepping, then `Engine.time_scale =` appears only in `feedback.gd`, `instantiate()` outside addons and tests only in `core/spawner.gd`, and tracked files hold no machine paths.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 33 findings — high 0, medium 7, low 21, false 5, maybe-false 0
- findings:
  - `[medium]` `[patch]` (blind) A refused F5 leaves the running sandbox with empty tuning, because `Config.load_data` sets `tuning = {}` on a parse failure. Verified at `config.gd:35`. Fixed: `reload_data()` saves `Config.tuning`/`flags` first; on failure it restores both, clears `load_error`, logs the failing file and returns false.
  - `[medium]` `[patch]` (blind) The bad-JSON F5 test never checked that the old data survives (same root cause). Fixed: the test now asserts `shake_px` is still 8 in both `Config` and `Feedback` and that `load_error` is empty.
  - `[low]` `[patch]` (blind) A malformed `flags.json` doesn't set `load_error`, so F5 restarts with `flags = {}`. Real, but Epic 1 has no `Config.flag` callers. Fixed in the same guard (`Config.flags.is_empty()` counts as a failure), plus new `test_f5_bad_flags_refuses_restart`.
  - `[low]` `[reject]` (blind) The bench verdict ignores the enemy count, a zero sample count and p99. The spec defines PASS as avg < 16.6, matching the "frame time under 16.6 ms" criterion. Enemies, p99 and max are logged for a person to read. A zero sample count would need a sub-frame `--bench` value, which nobody uses.
  - `[medium]` `[patch]` (blind) The bench load depended on where the cursor was left: a ship at x 960 sits between grid columns 880 and 1040. Fixed: `_start_bench()` warps the mouse to `BENCH_AIM` (1040, 900), under a grid column. Bench re-run, and row 27 updated (4306 frames, avg 4.65 ms).
  - `[low]` `[patch]` (blind) The bench line lacked the conditions that row 27 states. Fixed: the line now logs `window=` and `vsync=` (no adapter name).
  - `[medium]` `[patch]` (blind) The bench path is untested. Same root cause as the verification-gap row below. Fixed: added `_bench_exit_code()` and three tests (fire held, warm-up skipped then samples counted, exit 0/2 around 16.6).
  - `[low]` `[reject]` (blind) The sample buffer can fill silently above 5000 FPS. The measured rate is about 215 FPS, far below that, and a warning adds a branch for a case nobody will hit.
  - `[low]` `[reject]` (blind) `FRAME_BUDGET_MS = 16.6` is hard-coded. It is the NFR1 acceptance threshold, written exactly as the story and architecture state it, not a gameplay tuning value. `tuning.json` has fixed sections and no place for it, and the spec sets it as a constant.
  - `[low]` `[reject]` (blind) The refill test hard-codes Wasp HP 3. Existing tests already pin tuning values this way (rejected the same way in Story 1.6). A retune fails loudly.
  - `[low]` `[reject]` (blind) Both the sandbox and DebugTools parse the args, so a bad `--bench` warns twice. Only noise; sharing a parse result needs a static cache or new coupling.
  - `[low]` `[reject]` (blind) `deferred-work.md` isn't updated for DW-4/5. That ledger is triaged by the bmad-loop sweep. The evidence (bench max 9.25 ms) is recorded here and in row 27.
  - `[false]` `[reject]` (blind) No test checks the real F1/F5 key bindings. `test_project_settings.gd:78` `test_key_actions_bound_by_physical_keycode` already pins every debug action's physical keycode.
  - `[medium]` `[patch]` (edge) F5 with malformed tuning empties `Config` before `load_error` is checked. Same root cause as the first blind row; fixed there.
  - `[low]` `[reject]` (edge) `--bench=1e400` gives infinity or a huge buffer. That input is absurd for a debug flag and nobody will pass it.
  - `[low]` `[reject]` (edge) If the window loses focus during the bench, Godot releases `fire_laser`. Unlikely in a 22 s unattended run, and the `enemies=40` result plus the kill-driven refills show fire was held. Re-pressing every frame adds a branch.
  - `[low]` `[reject]` (edge) The buffer fills silently above `BENCH_MAX_FPS`. Same as the blind row above.
  - `[low]` `[reject]` (edge) `enemies=` can read 39 or 41 in the frame a refill lands. It is an informational log value and the verdict doesn't use it.
  - `[low]` `[reject]` (edge) F5 during a bench restarts the bench. Nobody presses F5 during an unattended bench, and restarting cleanly is harmless.
  - `[false]` `[reject]` (edge) A refill can return null and silently lose a slot. `spawn_enemy` returns null only for an unknown type, which it logs (the type is the constant `&"wasp"`), or when `Enemies` is missing, which can't happen because it is part of `sandbox.tscn`.
  - `[low]` `[reject]` (edge) A bad `--bench` value warns twice. Same as the blind double-parse row.
  - `[false]` `[reject]` (edge) A viewport narrower than 1440 px pushes Wasps off-screen. The viewport is fixed at 1920 in `project.godot` with `canvas_items`/`keep` stretch, so the playfield width is always 1920.
  - `[medium]` `[patch]` (edge, claim) The claim "the running scene keeps its cached values" was false. Same root cause as the first blind row; fixed there and the doc comment corrected.
  - `[low]` `[patch]` (edge, claim) The claim that F5 restarts only on success didn't cover a flags failure. Same as the blind flags row; fixed there.
  - `[low]` `[reject]` (edge, claim) The claim that the bench holds fire throughout. Same as the focus-loss row.
  - `[medium]` `[patch]` (verification-gap) The bench PASS/FAIL, sampling window and exit code had no test. Filed disposition: patch. Fixed with `_bench_exit_code()` and three tests in `test_debug_tools.gd`.
  - `[low]` `[reject]` (verification-gap) Turning stress mode on from the command line (sandbox flag, overlay shown, vsync off) is not covered by a test. Filed disposition: defer. Closing it needs a new injectable args property. A regression would show in the bench line (`enemies=8`), and this run's bench recorded `enemies=40`.
  - `[low]` `[patch]` (verification-gap, other) F5 restarts after a bad `flags.json`. Same as the blind flags row; fixed there.
  - `[false]` `[reject]` (intent) Nothing is committed and the status isn't `awaiting-operator`. The audit ran before finalization, which commits and sets the status.
  - `[low]` `[reject]` (intent) AC1/AC2 are tested through injected actions and a stubbed restart. `reload_current_scene` can't run inside the GUT runner, the key bindings are pinned elsewhere, and trying F5 in the real game is an operator action.
  - `[low]` `[reject]` (intent) Stress mode is a command-line flag and the evidence is a bench log, not the overlay. The Design Notes explain the flag (F1–F7 are taken, no new bindings). `-- --stress` still lets a person hold fire and read the overlay, which is an operator action.
  - `[false]` `[reject]` (intent) The export and launch results are not in the diff. The exe is gitignored by rule, and the run's outcome is recorded in the Auto Run Result below.
  - `[low]` `[reject]` (intent) The overlay and glow checks could have been closed by an agent. The agent did measure frame time (bench) and tuning load (export log). How the glow looks, and the on-overlay confirmation, are human checks under the project's rule never to claim feel verified.

## Design Notes

**Why command-line stress mode:** F1–F7 are already assigned, and new key bindings are out of scope. User args (`-- --stress`) need no input changes, survive the F5 restart (they are re-read in `_ready`), and let an agent run the measurement with no human at the keyboard. The bench holds the `fire_laser` action itself, which matches "while I hold fire".

**Why vsync is off in stress mode:** with vsync on, a 60 Hz display pins frame time at about 16.7 ms whatever the load, so "under 16.6 ms" could never read true. With vsync off, frame ms shows the real work per frame.

**Operator actions (human-only):** the 2-minute fun-gate playtest by the developer and at least one colleague, with any tuning changes logged (DW-3 is a candidate). Watching the F1 overlay in `-- --stress` mode with held fire. Looking at the glow in the exported build. Only after these does the epic gate pass.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all pass, exit 0.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --quit-after 120` -- expected: exit 0, no `SCRIPT ERROR`.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --path game -- --bench=20` -- expected: one `Stress bench:` line, exit 0 (PASS) or 2 (FAIL → ADR-003 switch).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --export-release "Windows Desktop" export/windows/DEFECTOR.exe` -- expected: exit 0, exe exists.
- `git grep -nI -i -e "users[/\\]" -e "c:[/\\]godot"` -- expected: no new matches.

**Manual checks:**
- Fun, feel and glow look are human operator actions. Do not claim them verified.

## Auto Run Result

Status: awaiting-operator

**Summary:** The sandbox now has the E1 validation tooling:
- **`DebugTools`** (in a layer-30 `Overlay`): F1 toggles an overlay showing FPS, frame ms (average and max, measured in real time), node count and enemies alive. F5 reloads the tuning and flags, refreshes the `Feedback` tiers and restarts the scene. If the new data is bad, it keeps the previous data and does not restart. Both keys do nothing in release builds.
- **Stress and bench modes:** `-- --stress` starts a stress mode with 40 Wasps that refill as they die, and turns vsync off. `-- --bench=N` holds fire at a fixed aim, logs a `Stress bench:` line and exits with 0 (pass) or 2 (fail).
- **Glow:** a `WorldEnvironment` with glow, as in the architecture.
- **Export preset:** a committed Windows Desktop `export_presets.cfg`.

Everything an agent can do is done:
- The 4.7.2 export templates are installed (on this machine only, not committed).
- The bench passes on Forward+, and the renderer decision is recorded as decision-log row 27.
- The release export runs from outside the repo and loads the tuning data.

The human-only checks are listed under `operator_actions`.

**Files changed:**
- `game/ui/debug/debug_tools.gd` / `.tscn` -- F1 overlay, F5 reload and restart (keeps the old data on failure), stress vsync, self-timing bench.
- `game/ui/debug/debug_args.gd` -- parses `--stress` and `--bench=<s>`.
- `game/ui/debug/frame_stats.gd` -- frame-time samples in a preallocated buffer (average, max, nearest-rank percentile).
- `game/scenes/sandbox/sandbox.gd` / `.tscn` -- stress grid with per-slot refill, `Overlay`/`DebugTools`, `WorldEnvironment` glow.
- `game/export_presets.cfg` -- Windows Desktop preset (`data/*.json` include, GUT and tests excluded, embedded PCK, relative path).
- `game/tests/unit/test_debug_args.gd`, `test_frame_stats.gd`, `test_debug_tools.gd`, `test_export_preset.gd` (new), `test_sandbox.gd` (extended) -- every I/O matrix row, plus the bench path.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- row 27: Forward+ kept, with the bench numbers, pending operator confirmation.
- `_bmad-output/implementation-artifacts/epic-1-context.md` -- regenerated (the decision log had changed since it was compiled).

**Review findings:** 33 in total: high 0, medium 7, low 21, false 5.
- **Patched (5 entries / 12 rows):**
  - F5 refused reload kept empty tuning (medium): now saves and restores the old data, with tests.
  - Bench load depended on the cursor (medium): fixed aim `BENCH_AIM`.
  - Bench path untested (medium): `_bench_exit_code()` plus 3 tests.
  - Bad `flags.json` let F5 restart (low).
  - Bench line lacked window size and vsync (low).
- **Deferred:** none.
- **Rejected (16):** each reason is in the triage log.
  - Informational or log-only nits: bench verdict ignores enemies, samples and p99; `enemies=` reads ±1 at a refill; double warning on a bad `--bench`.
  - Inputs or situations nobody will hit: a full sample buffer above 5000 FPS (two rows); `--bench=1e400`; focus loss during the bench (two rows); F5 during a bench.
  - Deliberate or existing choices: the NFR threshold as a constant; tests pinning Wasp HP; the deferred-work ledger belongs to the sweep; the command-line stress mode is untested and needs an injectable property, while the bench line shows `enemies=40`.
  - Intent-surface notes: unit-level F1/F5 tests; command-line stress mode versus an in-game mode; overlay and glow left to the operator.
  - Five `false`: key bindings already pinned; null refill unreachable; viewport fixed at 1920; not yet committed at audit time; export result not in the diff.

**Follow-up review recommendation:** true. Three medium entries were patched in this first pass (patched by verdict: medium 3, low 2). Specific unverified risk: the patched `reload_data()` restores `Config.tuning`/`flags` by assignment from outside `Config`, bypassing its API. Also, `warp_mouse(BENCH_AIM)` is assumed to keep the ship under the 1040 column for the whole bench. The higher frame count suggests it does, but nothing asserts it. Neither patch was re-reviewed.

**Verification:**
- `--headless --path game --import`: exit 0.
- GUT headless: 274/274 passing, exit 0, no `SCRIPT ERROR`.
- `--headless --path game --quit-after 120`: exit 0, no `SCRIPT ERROR`.
- Bench on this machine, fullscreen 1920x1080, vsync off, 40 Wasps:
  - Before the aim patch, with `--bench=10`: avg 4.26 ms, p99 6.16 ms, max 7.31 ms, PASS (re-checked by the parent run).
  - After the patch, with `--bench=20`: 4306 frames, avg 4.65 ms, p99 7.01 ms, max 9.25 ms, `enemies=40`, `renderer=forward_plus`, PASS, exit 0.
  - The max under 10 ms also covers DW-4 (first-explosion hitch) and DW-5 (explosion load) on this machine.
- `--export-release "Windows Desktop" export/windows/DEFECTOR.exe`: exit 0 (about 109 MB exe). The exe was copied to a scratch folder outside the repo and run with `--quit-after 300`: exit 0, and the log shows `[INFO][data] Loaded res://data/tuning.json (14 sections) and res://data/flags.json (4 flags)`.
- Grep checks:
  - `Engine.time_scale =` appears only in `autoloads/feedback.gd`.
  - `instantiate()` outside addons and tests appears only in `core/spawner.gd`.
  - The diff contains no personal, employer or machine paths.

**Residual risks:**
- Fun, feel and the look of the glow are unverified and need the human operator actions.
- The glow values (intensity 0.8, threshold 0.6, bloom 0.05) are placeholder art constants.
- The export preset was hand-written; opening the editor may rewrite it with the full default option list.
- Command-line stress activation has no automated test.
- The pre-existing fresh-clone `--import` issue (DW-6) still applies.
- Row 27 is marked pending until the operator confirms on the overlay.

## Operator Confirmation

Confirmed 2026-10-07: the external actions this story owed were carried out.

- Fun gate: 2-minute sandbox playtest by the developer and at least one colleague ("Was the shooting fun on its own?"); log any tuning change in the GDD decision log (DW-3 missile splash vs grid_4x2 spacing is a candidate).
- Stress overlay: run `<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe --path game -- --stress`, hold fire, watch the F1 overlay frame ms stay under 16.6; then set decision-log row 27 from "pending operator confirmation" to confirmed. Also try F5 after editing data/tuning.json.
- Glow look: launch the exported build (game/export/windows/DEFECTOR.exe, copied outside the repo) and judge the WorldEnvironment bloom; glow values in sandbox.tscn are art constants to tune.

_Appended by the bmad-loop orchestrator (`bmad-loop confirm`, #335): a human confirmed these external actions out of band, and the story was advanced from `awaiting-operator` to `done`._
