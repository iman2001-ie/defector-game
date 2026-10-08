---
title: 'Story 2.2: Play a Level Driven by Wave Data'
type: 'feature'
created: '2026-10-07'
status: 'done'
baseline_revision: 'e44170317477bcd0895d1f3203fdb433a8690cf2'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-2-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The game still boots into the Epic 1 sandbox. There is no level scene, no level data and no Wave Director, so waves, reinforcements and beat triggers can't be authored or played, and Story 2.1's `WaveProgress`/`BeatTrigger` are unused.

**Approach:** Build the architecture's Wave Director (Novel Pattern #1, game-architecture.md L729-845) as a node in a new generic `scenes/level/level.tscn`. It reads `data/levels/level_<id>.json` through a new `Config.level(id)`, spawns every wave entry through the `Spawner`, counts resolves with `WaveProgress`, runs `BeatTrigger` action chains (`spawn_group`, `wait`), clears waves with the `waves.gap_s` gap and ends with `level_cleared` and a placeholder banner. A shared validator checks every level file in a GUT data test. F3/F6 and the F1 wave lines arrive in `DebugTools`. The main scene becomes the level, running `level_dev.json` (Wasp-only).

## Boundaries & Constraints

**Always:**
- Statically typed GDScript. Only `Spawner` instantiates; only `WaveDirector` decides what spawns and when. Logging through `Log` only (categories `wave`, `beat`, `spawn`, `data`, `debug`), INFO for level/wave start and clear and for each fired beat, nothing per frame.
- Use `WaveProgress.resolve()` and `remove_from_total()`, never write `resolved`/`total_counted` directly. After **every** change to the progress (a resolve or a subtraction) emit `Events.wave_progress_changed`, check progress triggers in array order, then try to clear.
- Every number comes from data: `waves.gap_s`, plus new `waves.formation` keys in `tuning.json`. JSON counts go through `int()`.
- Errors never pause the game and never soft-lock a wave.
- Spawning that can be reached from a physics callback (a resolve inside `area_entered`) is deferred (`call_deferred`), as the sandbox does.
- Each trigger fires at most once per wave attempt (`has_fired`, set when its chain starts). A running chain doesn't block other triggers. `wait` uses a pausable timer (`create_timer(s, false)`).

**Never:**
- No Wasp entry flight, slot holding or dives (Story 2.4), no wave bar (Story 2.3), no new enemy types, no `comms`/`story_event`/`music` actions (Epic 5: log them at DEBUG and skip), no Flagship (Epic 7), no SceneRouter/title flow or save (Epic 4), no Hunter Wasp flag gating (Story 2.8).
- Don't delete or change the sandbox's behaviour; it stays the stress-bench scene.
- Don't edit `sprint-status.yaml`. Don't change GDD design decisions.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Wave start | `spawns:[{wasp,8,grid_4x2}]`, `groups:{r:[{wasp,4}]}` | `wave_started(i, N)`; `total_counted` 12; 8 Wasps in `counted`; `wave_start` triggers run | — |
| Asteroids | `asteroids:[{size:"small",count:3}]` | 3 asteroids spawn at the top edge, never counted | unknown size: `Log.error`, skipped |
| Unknown type | `spawns:[{type:"bogus",count:2},{wasp,1}]` | `Log.error` naming file and `waves[i].spawns[0].type`; total 1; wave clears after the Wasp dies | no crash |
| Progress trigger | `{when:progress, at:0.5, actions:[{wait:1},{spawn_group:"r"}]}` | fires once when ratio ≥ 0.5; group spawns 1 s later (pausable) | — |
| Group spawned twice | two firing triggers name `r` | second request `Log.warn`, ignored | — |
| Stall | every live counted enemy resolved, no chain running, a group never spawned | `Log.error` names the group; its count is subtracted; wave clears | no soft-lock |
| Wave clear | resolved == total, no chains | `wave_cleared(i)`, `wave_clear` triggers run, after `gap_s` and their chains finish the next wave starts | — |
| Last wave | final wave clears | `level_cleared(id)`, INFO log, "LEVEL CLEAR" banner | — |
| Boss wave | `{boss:"flagship"}` | total 1; no Flagship exists yet, so `Log.error` and subtract; the wave clears | — |
| F3 | mid-wave | every live counted enemy dies through its death path, unspawned groups are skipped and their count resolved; pending progress triggers fire in order; wave clears | sandbox: logs "no wave director" |
| F6 | level with / without a boss wave | jumps to it (current counted enemies freed without resolving, chains abandoned) / `Log.info` "no boss wave" | — |
| Bad level file | missing file, parse error, no `waves` array | `Config.level` logs the reason, returns `{}`; level logs and starts nothing | no crash |

</intent-contract>

## Code Map

- `game/scenes/sandbox/sandbox.gd` + `sandbox.tscn` -- the template for `level.tscn`/`level.gd`: root `_ready` order (mouse mode, `_player.set_spawner`, `RenderGlow.apply`, `Feedback.prewarm()` last via `should_prewarm`), `Spawner` node at the root with `world = ../World`, `Overlay/DebugTools`, deferred respawn from `resolved`, random asteroid x at `y = -radius`.
- `game/core/spawner.gd` -- `spawn_enemy(type_id, params) -> Enemy` (null = not counted; it already logs unknown ids, so the Director checks `EntityRegistry.ENEMIES.has(type)` first and logs with the key path itself), `spawn_asteroid({size, position})`.
- `game/core/enemy.gd` -- `resolved` emitted once from `_die()`; `apply_damage(amount, source)` with `source == null` is safe; `is_dead()`. `setup` only reads `position` today; extra params (`slot`, `entry`, `formation`) are harmless and ready for 2.4.
- `game/autoloads/config.gd` -- add `level(id)`; reuse `_read_json_dict` (it logs file/parse errors). `Config.flags` is the dictionary passed to `BeatTrigger.should_fire`.
- `game/systems/waves/wave_progress.gd`, `beat_trigger.gd` -- Story 2.1, read-only. `should_fire(event, value, flags)`: pass the ratio for `progress`, `0.0` for `wave_start`/`wave_clear`.
- `game/autoloads/events.gd` -- all needed signals exist (`level_started(int)`, `wave_started`, `wave_progress_changed`, `wave_cleared`, `level_cleared(int)`). No new signal needed.
- `game/autoloads/pause_arbiter.gd` -- `_reasons` is private; add a public `reasons() -> Array[StringName]` for the overlay.
- `game/ui/debug/debug_tools.gd` -- `_unhandled_input` handles F1/F5; add `debug_resolve_wave` (F3) and `debug_skip_to_boss` (F6) — the input actions already exist in `project.godot`. `refresh_overlay()` builds the label text (runs every 0.25 s, not per frame); `debug_tools.tscn` label `offset_bottom` 132 must grow for the new lines.
- `game/entities/asteroids/asteroid.gd` -- `Asteroid.SIZES`; frees itself below the playfield.
- `game/core/playfield.gd` -- `Playfield.SIZE` for formation centring and column limits.
- `game/project.godot` L14 `run/main_scene`; `game/tests/unit/test_project_settings.gd` L69 asserts it (update to the level scene).
- `game/export_presets.cfg` L10 `include_filter="data/*.json"` -- Godot's `*` matches across `/`, so `data/levels/*.json` is already exported; leave it unless `test_export_preset.gd` proves otherwise.
- `game/tests/unit/test_sandbox.gd`, `test_debug_tools.gd` -- test style: preload the scene, `add_child_autofree`, restore `Config.load_data()`, `PauseArbiter.clear()`, `Log.sink = Callable()` in `after_each`; `Log.sink` captures log lines.
- No `game/tests/data/` folder exists yet; GUT runs with `-ginclude_subdirs`, so a new folder is picked up. `*.gd.uid` files are tracked: commit the new ones after `--import`.

## Tasks & Acceptance

**Execution (write each test file first, red, then the code):**
- `game/systems/waves/formation.gd` -- `class_name Formation`, pure `RefCounted`, static `slots(formation: String, count: int, first_row: int, spacing: Vector2, top_y: float, width: float) -> Array[Vector2]`. `grid_<C>x<R>` fills rows of C, row-major, centred on `width / 2`, starting at row `first_row`; if count > C×R it keeps adding rows of C. An empty or unparseable string uses rows of `mini(count, floori(width / spacing.x))`. Static `rows_used(...)` (or return the row count alongside) so the Director can stack entries. Static `is_valid(formation: String) -> bool`.
- `game/systems/waves/level_validator.gd` -- `class_name LevelValidator`, pure `RefCounted`, static `validate(data: Dictionary, source: String, known_types: Array[StringName]) -> Array[String]`; each problem names `source` and the key path (e.g. `res://data/levels/level_dev.json waves[1].spawns[0].type`). Checks: numeric `id`; non-empty `waves` array of dictionaries; each wave has `spawns` (array) or `boss`; every spawn and group entry has a known `type` and an integer `count` > 0; optional `formation` is valid; asteroid entries have a size in `Asteroid.SIZES` and count > 0; trigger `when` ∈ the five values; `progress` needs `at` in 0–1; `actions` entries are dictionaries; every `spawn_group` names a group in that wave; every group is named by some `spawn_group` in that wave.
- `game/autoloads/config.gd` -- `level(id: String) -> Dictionary`: reads `res://data/levels/level_%s.json` (path const), returns `{}` on a read failure or when `waves` is missing/not an array (logged with the path), otherwise logs every `LevelValidator` problem with `Log.error("data", ...)` and returns the data (bad items are skipped later at runtime). Known types = `EntityRegistry.ENEMIES.keys()`.
- `game/autoloads/pause_arbiter.gd` -- `reasons() -> Array[StringName]` (a copy).
- `game/data/tuning.json` -- `waves.formation`: `{ "spacing_px": { "x": 160, "y": 120 }, "top_y": 160 }` (the sandbox's grid_4x2 numbers, DW-3).
- `game/data/levels/level_dev.json` -- `id` 0, name "Development", Wasp-only: W1 8 Wasps `grid_4x2` with a `wave_start` trigger `[wait 0.5]`; W2 6 Wasps `grid_3x2`, 2 small asteroids, group `reinforcements` of 4 Wasps `grid_4x1` spawned by a `progress` 0.5 trigger `[wait 1.0, spawn_group]`; W3 10 Wasps `grid_5x2` with a `wave_clear` trigger `[wait 0.5]`. Must pass the validator.
- `game/systems/waves/wave_director.gd` -- `class_name WaveDirector extends Node`, joins group `wave_director`, `@export var spawner: Spawner`, public `rng: RandomNumberGenerator`. API: `start_level(data: Dictionary, source: String)`, `start_wave(index: int)`, `debug_resolve_wave()`, `debug_skip_to_boss()`, read-only accessors for wave number/count, resolved/total and level id. Per wave: build `BeatTrigger`s, compute total (spawns + all group entries, boss = 1), `reset`, emit `wave_started`, INFO log, run `wave_start` triggers, spawn entries (stacking formation rows per wave, params `position`/`slot`/`formation`/`entry`), subtract failures (unknown type, null spawn, boss), spawn asteroids. Counted enemies `add_to_group(&"counted")` and connect `resolved` bound to a wave serial (stale resolves are ignored). Follow the Design Notes for chains, the stall net, clear, gap, F3 and F6.
- `game/scenes/level/level.gd` + `level.tscn` -- root `Level` (Node2D) with the architecture tree: `Background`, `World` (`Asteroids`, `Enemies`, `Allies`, `Pickups`, `Projectiles`, `Effects`, `Player` at 960,900), `Spawner` (world = `../World`), `WaveDirector` (spawner wired), `ShakeCamera` (960,540), `WorldEnvironment` (same glow env as the sandbox), `HUD` (CanvasLayer 10) holding `LevelClearBanner`, `Comms` (CanvasLayer 20, empty), `Overlay` (CanvasLayer 30) with `DebugTools`. `@export var level_id: String = "dev"`. `_ready`: in a debug build with `--stress` or `--bench`, `Log.info` and `change_scene_to_file` the sandbox (deferred) and return; otherwise mirror the sandbox setup, `Config.level(level_id)` (on `{}` log and stop), `Events.level_started.emit(int(data.id))`, INFO log, `start_level`, `Feedback.prewarm()` last.
- `game/ui/hud/level_clear_banner.gd` -- a hidden centred `Label` "LEVEL CLEAR" (coalition #22E6FF, large font, placeholder) shown on `Events.level_cleared`; reads only `Events`.
- `game/ui/debug/debug_tools.gd` (+ `.tscn` label size) -- F3 calls `debug_resolve_wave()` and F6 `debug_skip_to_boss()` on the first `wave_director` group node, or log "no wave director in this scene". The overlay adds `wave n/N`, `resolved r/t` (or `wave -` without a director) and `pause <reasons or none>`.
- `game/project.godot` -- `run/main_scene="res://scenes/level/level.tscn"`.
- Tests: `game/tests/unit/test_formation.gd`, `test_level_validator.gd`, `test_wave_director.gd` (every I/O-matrix row, with a minimal World + Spawner fixture and inline level dicts; shorten `waves.gap_s` via `Config.tuning` and restore with `Config.load_data()`), `test_level.gd` (tree, process modes, `level_started` with the JSON id, mouse mode, banner on `level_cleared`), `game/tests/data/test_data_files.gd` (every `level_*.json` in `res://data/levels/` passes `LevelValidator`), additions to `test_config.gd` (`level("dev")`, missing id → `{}`), `test_pause_arbiter.gd` (`reasons()`), `test_debug_tools.gd` (F3/F6 dispatch, overlay lines), `test_project_settings.gd` (main scene).
- `_bmad-output/game-architecture.md` -- status only: mark `level.tscn`, `Config.level()`, F3, F6 and the F1 wave/pause lines as built; note the `Spawner` node in the level tree, the asteroid entry shape `{size, count}`, `waves.formation` tuning and the `--stress`/`--bench` sandbox redirect in a short "As-built 2026-10-07 (Story 2.2)" note.
- Run `--import`, then the full GUT suite.

**Acceptance Criteria:**
- Given the project, when it is run normally, then `level.tscn` loads `level_dev.json` through `Config.level`, `Events.level_started` fires with id 0, wave 1 starts, and clearing all three waves logs the level clear at INFO and shows "LEVEL CLEAR".
- Given `-- --stress` or `-- --bench=<s>` in a debug build, when the project runs, then the sandbox stress scene runs as before.
- Given the headless GUT suite, when it runs, then the new tests cover every I/O-matrix row, `test_data_files.gd` validates every level file, and every pre-existing test still passes.
- Given the new scripts, when inspected, then every variable, parameter and return is typed, nothing but `Spawner` instantiates entities, `LevelClearBanner` reads only `Events`, and no `_process`/`_physics_process` path logs.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 28 findings — high 0, medium 1, low 15, false 12, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: a `spawn_group` in a `wave_clear` trigger (or a boss trigger in a non-boss wave) passes validation; the stall net then subtracts the group and the clear chain spawns uncounted enemies — needs an authoring mistake no level makes, the stall net logs an ERROR when it happens, and the fix adds a validator branch.
  - `[low]` `[reject]` Blind: `boss_phase`/`boss_hp_le` triggers are not checked for `phase`/`hp` — no level has boss triggers until Epic 7, the story's data-test AC lists only `at`, and the fix adds branches.
  - `[low]` `[reject]` Blind: `wait` values, unknown action keys, `entry` values and duplicate `spawn_group` names are not validated — the runtime logs or coerces each one, no shipped data hits them, and the fix adds validator branches.
  - `[low]` `[reject]` Blind: an explicit grid wider than 12 columns puts slots off-screen — no data uses one, Story 2.4 owns entry and placement, and the fix adds a clamp or check.
  - `[low]` `[reject]` Blind: stacked formation rows are unbounded and could reach the player zone — level_dev uses at most 3 rows (y ≤ 400), and Story 2.4 plus the later level content own placement. Noted under residual risks.
  - `[low]` `[reject]` Blind: the LEVEL CLEAR banner never hides, and F6 after a level clear can emit `level_cleared` again — F6 is a debug-only key, no level has a boss wave yet, and the fix adds a guard.
  - `[low]` `[reject]` Blind: `--bench` starts the bench twice, because the level's DebugTools runs `_ready` before the redirect — the only harm is a duplicate start log; the result line and exit code come from the sandbox's run, and the fix needs new coupling between the scene root and DebugTools. Noted under residual risks.
  - `[low]` `[reject]` Blind: duplicated logic (`should_prewarm`, the id parse, the banner text), and a non-integer `id` such as 1.5 is accepted — the duplication is cosmetic, and ids are authored as integers.
  - `[low]` `[patch]` Blind: the F3 test never checks firing order — fixed: the test now asserts that the `first` comms action line is logged before the `third`.
  - `[low]` `[patch]` Blind: the architecture tree and the built-parts paragraph leave out the new files — fixed: added `formation.gd`, `level_validator.gd`, `level_clear_banner.gd` and the new folders.
  - `[low]` `[patch]` Blind: the `+` sign rejection in `Formation._grid` is untested — fixed: added `grid_+4x2` and `grid_4x+2` to the bad cases.
  - `[low]` `[patch]` Blind: the dev-level end-to-end test leaves its wait loop silently on a timeout — fixed: it now asserts that the wave advanced or the level cleared after each loop.
  - `[false]` `[reject]` Edge: a gap or wait timer resumes on a freed WaveDirector and errors — a Godot 4.7.2 probe (await a pausable timer, then free the owner) shows the coroutine is dropped with no resume and no error, and the GUT log has no such error either.
  - `[false]` `[reject]` Edge: a counted enemy that leaves the tree without `resolved` soft-locks the wave — no such path exists: an Enemy only frees through `_die()`, which resolves; F6 bumps the serial and restarts the wave; and a scene reload frees the director too.
  - `[low]` `[reject]` Edge: stacked rows and wide grids go off-screen — same root as the Blind rows above.
  - `[false]` `[reject]` Edge: calling `start_level` again with no waves leaves stale state — the only caller is `level.gd._ready`, once per scene.
  - `[low]` `[reject]` Edge: action contents are not validated — same as the Blind action-field row.
  - `[low]` `[reject]` Edge: boss trigger parameters are not validated — same as the Blind boss-parameter row.
  - `[low]` `[reject]` Edge: a progress `at` that can't be reached before its group spawns — the stall net subtracts the group with an ERROR log, and a reachability check would be complex.
  - `[low]` `[reject]` Edge: a non-integer numeric `id` is accepted — same as the Blind duplication/id row.
  - `[low]` `[reject]` Edge (claim): with `--bench`, the bench start runs and logs twice — same as the Blind bench row.
  - `[medium]` `[patch]` Verification gap: the `--stress`/`--bench` redirect in `level.gd` had no test, so the bench could silently measure the wrong scene — fixed: extracted `static should_redirect_to_stress(debug_build, args)` and tested it with `--stress`, `--bench=5` and no args, in debug and release builds.
  - `[low]` `[patch]` Verification gap: `level.gd`'s copy of `should_prewarm` was untested — fixed: added a truth-table test to `test_level.gd`.
  - `[low]` `[reject]` Verification gap (other): the bench starts twice — same as the Blind bench row.
  - `[false]` `[reject]` Intent: an awaiting-operator reading, with playtest steps as operator actions — the intent's operator clause covers actions outside the repo (domains, DNS, keys), and every Story 2.2 AC is in the repo and checked by tests or a headless run.
  - `[false]` `[reject]` Intent: the tests clear waves through F3 rather than player kills — the WaveDirector tests kill enemies through `apply_damage`, the same death path a laser hit uses; the level test uses F3 only to step through level_dev.
  - `[false]` `[reject]` Intent: the root `Spawner` node and the debug-only scene redirect go beyond the fixed tree — both follow the architecture (the Spawner is a "node in the scene root") and the spec, and both are recorded in the as-built note, so there is no bad outcome.
  - `[false]` `[reject]` Intent: `level_id` is a String while `level_started` emits the JSON's int `id` — the spec designed it this way (Design Notes, "Level id"), and the signal types are unchanged.

### 2026-10-07 — Review pass
- verdicts: 30 findings — high 0, medium 2, low 16, false 12, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind: after the stall net gives up on a group, the subtraction pushes the ratio to 1.0, a progress trigger naming that group fires, and `_request_group` logs a false "already spawned" WARN — fixed: `_check_stall` also marks given-up groups in `_skipped_groups` (a later request logs at DEBUG only), and `test_stall_subtracts_never_spawned_groups` asserts there is no `[WARN][beat]` line.
  - `[low]` `[patch]` Blind: `waves: []` gets past `Config.level_at`, so the level emits `level_started` and never clears — fixed: `level_at` treats an empty `waves` array like a missing one (logs and returns `{}`); new fixture `level_empty_waves.json` and test `test_level_with_an_empty_waves_array_returns_empty`.
  - `[medium]` `[patch]` Blind: nothing proves the export include filter ships `data/levels/*.json`, which the new main scene needs — fixed: `test_level_files_match_the_include_filter` in `test_export_preset.gd` checks every level file against the preset's filter with `matchn` (it passes, so `data/*.json` covers the subfolder).
  - `[low]` `[patch]` Blind: no test checks that a subtraction emits `wave_progress_changed` — fixed: the unknown-type test now asserts one emission with ratio 0 after the subtraction.
  - `[low]` `[reject]` Blind: some log-only branches are untested (unknown-action WARN, non-numeric `wait`, asteroids with no spawner, the `EntityRegistry`-missing fallback) — each only logs or no-ops, and the fallback would fail `test_level_dev_loads` through `push_error`. No named harm is worth extra tests.
  - `[false]` `[reject]` Blind: the validator doesn't flag a count that doesn't fit C×R — the spec designs this: `Formation` "keeps adding rows of C" when count > C×R, so there is no bad outcome.
  - `[low]` `[reject]` Blind: the data test doesn't check `id` uniqueness across files and parses with `JSON.parse_string` — only one level file exists, and the fix adds a cross-file branch. Later level stories can add it.
  - `[low]` `[reject]` Blind: a `progress` trigger with `at: 0.0` waits for the first change — no data uses it, `wave_start` covers that need, and the fix adds a validator rule or an extra step.
  - `[low]` `[reject]` Blind: F3 pressed during the clear gap logs "resolving" but changes nothing — the only effect is one debug-key log line, with no state harm.
  - `[false]` `[reject]` Blind: F3 assumes `apply_damage(hp)` kills — `Enemy.apply_damage` subtracts `amount` from `hp` and calls `_die()` at `hp <= 0`, so `maxi(hp, 1)` always kills today. Invulnerability is a hypothetical future state.
  - `[low]` `[reject]` Blind: the as-built note leaves out the `wave_director` group, `chains_finished` and `enemy_types()` — the only consumer of the group is `DebugTools`, the HUD reads only `Events`, and no other caller needs them.
  - `[false]` `[reject]` Blind: `level.gd` logs under `scene`, which isn't in the spec's list — `scene` is in the architecture's fixed category list (game-architecture.md L424), and the sandbox uses it for the same scene-start line.
  - `[false]` `[reject]` Blind: the committed spec's frontmatter says `in-review` — the committed spec at 15bdef9 has `status: 'done'`. Separately, a fix that edits this build's spec is out of scope for review.
  - `[false]` `[reject]` Edge: a wave with only progress-gated groups stalls at wave start — with no counted enemy spawned, progress can never change, so the group could never spawn. The stall net's ERROR and subtraction is the specified no-soft-lock behaviour.
  - `[low]` `[reject]` Edge: a wave whose total is 0 never emits `wave_progress_changed` — no progress change happens, so the rule ("after every change") isn't broken, no level has such a wave, and the fix adds a branch.
  - `[low]` `[patch]` Edge: `waves: []` emits `level_started` and never clears — same root as the Blind empty-waves row; fixed there.
  - `[low]` `[reject]` Edge: a huge authored `count` (1e6) would hang the game — this needs an absurd authoring error that the reviewed data files don't contain, and the fix adds a tuning cap and guards.
  - `[low]` `[patch]` Edge: a false "already spawned" WARN after the stall net — same root as the Blind stall-net row; fixed there.
  - `[medium]` `[patch]` Verification gap: no test checks that the level files match the export include filter — same root as the Blind export row; fixed there.
  - `[low]` `[reject]` Verification gap: only the predicate is tested for the `--stress`/`--bench` redirect in `_ready`; the wiring itself is not — the predicate (the logic) is pinned, a test of the wiring needs a new args seam, and a manual `--quit-after 120 -- --stress` run this pass logged the switch and "Sandbox stress mode: 40 Wasps".
  - `[false]` `[reject]` Intent: the level clear is tested only through F3, not player kills — carried: the WaveDirector tests kill enemies through `apply_damage`, the same death path a laser hit uses; the level test uses F3 only to step through level_dev.
  - `[low]` `[reject]` Intent: the deferred group spawn is never tested from inside a physics callback — `_request_group` always uses `call_deferred`, and the tests see the deferral (the group appears only after process frames). A physics-callback fixture would add a lot of test scaffolding for a path the code already handles.
  - `[false]` `[reject]` Intent: the matrix rows use inline dictionaries rather than `Config.level` — `Config.level_at` returns the parsed dictionary unchanged, so the director sees the same input either way.
  - `[false]` `[reject]` Intent: F3's "no wave director" case is tested on a bare `DebugTools`, not the sandbox — `DebugTools` finds the director only through the `wave_director` group, which the sandbox doesn't have, so the result is the same.
  - `[false]` `[reject]` Intent: the parse-error and no-waves cases only reach `Config.level_at`, not the level scene — `level.gd` handles every `{}` result in one branch, and that branch is tested with the missing-file case.
  - `[false]` `[reject]` Intent: `level_cleared` comes after the gap and chains — this follows the Wave clear row ("after `gap_s` and their chains finish the next wave starts"). The last-wave row states no order, so there is no bad outcome.
  - `[false]` `[reject]` Intent: the `scene` log category — same as the Blind `scene` row.
  - `[false]` `[reject]` Intent: the debug-only `change_scene_to_file` redirect goes beyond the fixed tree and the SceneRouter rule — carried: it follows the spec's task list, keeps the sandbox as the stress-bench scene as the intent requires, and is recorded as a debug-only exception next to F5 in the as-built note.
  - `[low]` `[reject]` Intent: F6 after a level clear can emit `level_cleared` again — carried: F6 is a debug-only key, no level has a boss wave yet, and the fix adds a guard.
  - `[low]` `[reject]` Intent: `Config.level` and the director both log a bad type (ERROR under `data` and under `wave`) — the spec designs load-time validation plus runtime skipping, and the duplicate only appears with bad data.

## Design Notes

**Level id.** Files are keyed by a string (`level_dev.json`, later `level_1.json`), but `Events.level_started/level_cleared` take an `int`, so the int comes from the JSON `id` field (`level_dev` uses 0).

**Chains and clear.** `_run_chain(trigger)` sets `has_fired`, increments `_running_chains`, runs actions in order (`spawn_group` → deferred group spawn, marked spawned immediately; `wait` → `await create_timer(float(wait), false).timeout`; `comms`/`story_event`/`music` → `Log.debug` "arrives in Epic 5"), then decrements and calls `_try_clear()`. After every `await`, a chain whose wave serial no longer matches (F6) returns without touching counters.

`_try_clear()`: only if `is_complete()` and `_running_chains == 0` and not already clearing. Then emit `wave_cleared(i)`, INFO log, run `wave_clear` triggers, wait `gap_s` (pausable), then wait until `_running_chains == 0`, then start the next wave or finish the level (`Log.debug` skips `outro_sequence` until Epic 5, then `level_cleared`).

**Stall net.** Keep a live counted-enemy count. When it is 0, no chain is running, no deferred spawn is pending and the wave isn't complete, the missing count can only be unspawned groups: `Log.error` with their names, `remove_from_total(n)`, then run the usual progress/trigger/clear step.

**F3.** Mark every unspawned group as spawned (skipped), kill each live counted enemy via `apply_damage(maxi(hp, 1), null)` (the normal resolve path fires progress triggers in order), then `resolve()` the remaining count one at a time, running the normal step after each.

**Formation stacking.** Each spawn entry and each spawned group in a wave starts on the next free formation row, so reinforcements don't land on living Wasps. Story 2.4 replaces how a Wasp reaches its slot, not the slot math.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0; class cache has `WaveDirector`, `Formation`, `LevelValidator`.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, including `tests/data/test_data_files.gd`.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --quit-after 600` -- expected: log shows the level 0 start and wave 1 start, no ERROR lines.

## Auto Run Result

Status: done

**Summary:** This was a follow-up review pass on the finished Story 2.2. The game boots into the generic `level.tscn`, and its `WaveDirector` runs `data/levels/level_dev.json`.
- **Counting:** spawns go through the `Spawner`, and progress is counted with `WaveProgress`.
- **Triggers:** `spawn_group` and `wait` chains run, and a stall net stops any wave from soft-locking.
- **Level flow:** waves clear with the `waves.gap_s` gap, and the level ends with `level_cleared` and the "LEVEL CLEAR" banner.
- **Data and debug:** `Config.level(id)` and a level validator with a GUT data test are in place, plus F3, F6 and the F1 wave/pause overlay lines.

This pass patched four small issues.

**Files changed in this pass:**
- `game/systems/waves/wave_director.gd`: the stall net now records given-up groups as skipped, so a later `spawn_group` for one logs at DEBUG and no longer gives a false WARN.
- `game/autoloads/config.gd`: `level_at` rejects an empty `waves` array, so the level starts nothing and never emits `level_started`.
- `game/tests/unit/test_wave_director.gd`:
  - the stall test asserts there is no false WARN
  - the unknown-type test asserts the subtraction emits `wave_progress_changed`
- `game/tests/unit/test_config.gd` and the new `game/tests/fixtures/level_empty_waves.json`: the empty-waves test.
- `game/tests/unit/test_export_preset.gd`: every `data/levels/*.json` file must match the export include filter.

The full list of story files is in commit 15bdef9: the director, formation, validator, level scene, banner, data, Config, EntityRegistry and PauseArbiter additions, DebugTools, project settings, tests and the architecture note.

**Review findings:** 30 in total: high 0, medium 2, low 16, false 12.
- **Patched (4 entries):**
  - Medium: the export filter test.
  - Low: the false WARN from the stall net, the empty `waves` array, and the progress signal after a subtraction.
- **Deferred:** none.
- **Rejected:** 12 low and 12 false. Each reason is in the Review Triage Log, and three rows were carried from the first pass.
- **Follow-up review recommended: false.** This is a follow-up pass and no high finding was patched. Patched by entry verdict: high 0, medium 1, low 3.

**Verification:**
- `--import` exited 0.
- The full GUT suite passed: 35 scripts, 436/436 tests, 2410 asserts.
- `--quit-after 600` logged the level 0 start, wave 1/3 and the wave_start beat, with no WARN or ERROR lines.
- `--quit-after 120 -- --stress` logged the switch to the sandbox and "Sandbox stress mode: 40 Wasps, 200 projectiles".

**Residual risks:**
- Formation rows stack with no limit. Later level content could reach the player zone; Story 2.4 and Epics 6–7 own placement.
- With `--bench`, the bench start is logged twice before the switch to the sandbox.
- Only the predicate is tested for the stress/bench redirect. The `_ready` wiring is checked by hand, not by an automated test.
- No feel or pacing claim is made. Wasps hold their slots until Story 2.4, so level_dev's shape has not been playtested.
