---
title: 'Story 8.3: Hit the Performance Targets'
type: 'feature'
created: '2026-10-13'
status: done
operator_actions:
  - 'On the dev laptop, export a debug build ("<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --export-debug "Windows Desktop" export/windows_debug/DEFECTOR.exe), launch it, press F7 to unlock every level, start Level 3 from Level Select, press F1 for the overlay and play Wave 3 by hand; confirm the overlay''s frame ms stays under 16.6 ms throughout the wave.'
  - 'In the same debug export, play on into the Flagship fight, make the Final Choice with boss Wasps still alive, and confirm the F1 overlay''s frame ms stays under 16.6 ms through the desperate phase until the core dies.'
  - 'Reboot the dev laptop, then as the first thing after login run uv run python tools/perf_check.py launch game/export/windows/DEFECTOR.exe (or launch and time the release exe by hand) and confirm the title screen appears in under 5 s.'
  - 'If the machine the agent measured on is not the dev laptop, re-run uv run python tools/perf_check.py size game/export/windows and both level benches (game/export/windows_debug/DEFECTOR.console.exe -- --level-bench=busiest_wave, then -- --level-bench=desperate) on the dev laptop.'
  - 'Record the outcome in decision #67 of the decision log (its status currently says operator confirmation owed).'
baseline_revision: '85694aa2549df1e2f69f4a52cd1f012e8248d2f9'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** NFR1–NFR3 (60 FPS in the busiest wave and the Flagship's desperate phase, cold launch to the title in under 5 s, build under 200 MB) have never been measured on the finished game. The only bench (`-- --bench=N`) runs the sandbox stress grid, not Level 3 Wave 3 or the DESPERATE phase. Nothing measures launch time or build size of an export.

**Approach:** Add a debug-only, self-timing **level bench** (`-- --level-bench=<scenario>`, scenarios `busiest_wave` and `desperate`) that runs inside the real `level.tscn`, drives the game to the target state with no input, samples frame times and exits PASS/FAIL like the sandbox bench. Add `tools/perf_check.py` that measures an export's size and its launch-to-title time. Export release and debug builds, run everything on this machine, and record the numbers in the decision log and architecture. The hands-on play with the F1 overlay and a true cold boot are owed to the operator.

## Boundaries & Constraints

**Always:** Statically typed GDScript; failing GUT test first. Every number (target level and wave, sample and settle seconds, size and launch limits) comes from `tuning.json` → `debug.*` through `Config`; the pass limits reuse `debug.bench.avg_ms_max` / `p99_ms_max` / `max_ms_max`. Debug-only: the bench and its boot route do nothing when `OS.is_debug_build()` is false. Only `Spawner` creates entities; only `PauseArbiter` pauses (the bench clicks comms through public `CommsChannel` / `FinalChoice` APIs, it never pushes or pops pauses); only `Feedback` touches `Engine.time_scale`; logging through `Log`, nothing per frame (only start, phase-reached and the final result line). No per-frame allocation in the bench's `_process`. Frame ms is real wall time (`Time.get_ticks_usec()`), with vsync off for the run. The quit happens after the `debug.bench.quit_delay_s` real-time timer, through an injectable `quit_game` callable, never in the frame that logs. `perf_check.py` is stdlib-only, derives the log path from the `APPDATA` environment variable, and never hard-codes a machine path.

**Never:** Don't add object pooling unless a measured overrun is shown to come from instancing or freeing, and then only inside `Spawner` (ADR-002). Don't switch the renderer or retune gameplay, glow or Feedback to make a number pass: if a scenario FAILs for any cause other than instancing, HALT `blocked` with the numbers (ADR-003 renderer fallback is the user's call). Don't reuse the `--bench=` prefix (it implies stress and redirects to the sandbox). Don't commit `game/export/`, `*.zip` or logs. Don't change game flow, data other than the new `debug` keys, or `sprint-status.yaml`. Don't claim the operator's hands-on play or a true post-reboot cold launch as done.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Arg parse | `--level-bench=busiest_wave` / `desperate` | `DebugArgs.parse` returns `level_bench` = that name; `stress` stays false | last one wins |
| Bad arg | `--level-bench=` or `--level-bench=foo` | `level_bench` = `""` | one `Log.warn` naming the valid scenarios |
| Boot route | debug build + `level_bench` set | boot calls `SceneRouter.start_level(debug.level_bench.level)` instead of `goto_title` | release build: normal title |
| busiest_wave | Level 3 starting | intro comms clicked through; once wave 1 starts the bench jumps (deferred) to wave `debug.level_bench.wave` (1-based), player `debug_invincible`, cursor at `DebugTools.BENCH_AIM`, `fire_laser` held; samples begin `settle_s` after that wave starts | wave clears early: sampling stops, `ended=wave_cleared` |
| desperate | Level 3 starting | jumps to the boss wave; when the Flagship reaches TURRETS the bench kills the turrets, drops the core to its Final Choice floor, clicks through `l3_final_choice` picking the first option, clicks the response; fire **not** held; samples begin `settle_s` after DESPERATE starts | phase leaves DESPERATE early (Ryn kills the core): sampling stops, `ended=phase_left` |
| Finish | `sample_s` reached or early end | one `[INFO][debug] Level bench: scenario=… frames=… avg=… ms p99=… ms max=… ms enemies=… projectiles=… ended=time|wave_cleared|phase_left renderer=… window=… vsync=… result=PASS|FAIL`; quit(0) on PASS, quit(2) on FAIL after the delay | 0 samples → FAIL |
| No director / boss | target not found | `Log.error`, result FAIL, quit(2) | no hang |
| perf_check size | export dir | prints total MB, exit 0 when under `debug.release_check.max_build_mb` | missing dir → exit 2 with message |
| perf_check launch | exe path, `--runs N` | each run: wall seconds from process start until a `Title ready N ms after launch` line appears in a `godot.log` created after that start; kills the process; exit 0 when every run < `max_launch_s` | no line within `timeout_s` → that run fails, process killed |

</intent-contract>

## Code Map

- `game/ui/debug/debug_args.gd` -- `parse()` returns `{stress, bench_s, prewarm, comms, level}`; add `level_bench: String` (`LEVEL_BENCH_PREFIX := "--level-bench="`, valid names as a const list). Must NOT set `stress`.
- `game/scenes/boot/boot.gd` -- `_ready` + static `should_redirect_to_stress` (:44) pattern; add static `should_start_level_bench(debug_build, args)` and route to `SceneRouter.start_level(str(Config.int_("debug.level_bench.level")))` (deferred; `Config` has no string getter, so the level is an int) before the title. `start_level` (`autoloads/scene_router.gd:176`) loads level 3 directly (only "1" goes through the story scene).
- `game/scenes/level/level.gd` -- composition root. `_ready` (:89-143) parses `DebugArgs`; injectable `user_args` (:70), `change_scene` (:75); `_director` (:86), Player `$World/Player`; comms nodes `Comms/CommsChannel`, `Comms/FinalChoice`; `Overlay/DebugTools` (level.tscn:200). When debug build + `level_bench`, create the `LevelBench` node here, hand it its refs, add it under `Overlay`.
- `game/ui/debug/debug_tools.gd` -- reuse: `BENCH_AIM` (1040, 900), `BENCH_MAX_FPS`, `_bench_exit_code()` (:~395; extract a `static func bench_passed(stats: FrameStats) -> bool` both benches use), `_finish_bench` quit-timer pattern (`create_timer(delay, true, false, true)` bound to `quit_game.bind(code)`). Overlay starts on when `stress` — also start it on for `level_bench`. Note DebugTools `_ready` runs before `Level._ready` and reads the real OS args itself.
- `game/ui/debug/frame_stats.gd` -- `FrameStats.new(capacity)`, `add`, `count`, `average_ms`, `percentile_ms` (sorts a copy: report time only), `max_ms`.
- `game/systems/waves/wave_director.gd` -- `start_wave(index)` (:230, public, emits `Events.wave_started(index, count)`, does NOT free live enemies); `debug_skip_to_boss()` (:325, frees `COUNTED`/`BOSS`/`BOSS_WASPS`, clears `_failed`/`_level_done`, starts the boss wave); `Events.wave_cleared(index)` from `_try_clear` (:679). Add `debug_jump_to_wave(index)` that shares skip_to_boss's clearing; skip_to_boss calls it.
- `game/entities/boss/flagship.gd` -- `Phase` enum (:81), `phase()`, `turrets()`, `core()`, `boss_phase_changed` signal / `Events`; DESPERATE entered only on `comms_sequence_finished(&"l3_final_choice")` (:348). Core `apply_damage` clamps at `boss.final_choice_hp` (flagship_core.gd:131). No timer ends DESPERATE; Ryn (1 dmg / 1.0 s) can kill the 50 HP core in ~50 s.
- `game/systems/comms/comms_channel.gd` -- `is_showing()`, `is_choosing()`, `advance()` (:358); `game/systems/comms/final_choice.gd`: `FinalChoice.buttons()[i].pressed.emit()` picks an option. Story sequences push `story` (+ `final_choice`) pauses through PauseArbiter; the bench node must run `PROCESS_MODE_ALWAYS` to click them.
- `game/autoloads/feedback.gd` -- resume slow-mo after every unpause (~1 s): why `settle_s` exists.
- `game/data/tuning.json` (:359-375) -- `debug` section; add `level_bench` `{level: 3, wave: 3, sample_s: 20.0, settle_s: 2.0}` and `release_check` `{max_build_mb: 200, max_launch_s: 5.0, launch_timeout_s: 30.0}`.
- `game/scenes/title/title.gd:78` -- `Title ready %d ms after launch` (engine ticks) is the launch marker `perf_check.py` waits for.
- `game/project.godot:16-17,34-35` -- custom user dir `DEFECTOR`, file logging on: log at `%APPDATA%\DEFECTOR\logs\godot.log`, older runs rotated to `godot<timestamp>.log`.
- `game/export_presets.cfg` -- "Windows Desktop", `export/windows/DEFECTOR.exe`, embed_pck, console wrapper; pinned by `tests/unit/test_export_preset.gd`; do not change it.
- `tools/test_import_cc0_audio.py` -- the stdlib `unittest` + `sys.path.insert` pattern for the new `tools/test_perf_check.py`.
- Tests to extend: `tests/unit/test_debug_args.gd` (pure parse), `test_boot.gd` (static helpers + `change_scene` recorder), `test_debug_tools.gd` (`_bench_tools`, `_record_quit`, `Log.sink`; F6 tests with `_make_director` :649), `test_level.gd` (`_level_with_args` :748). Fixtures to copy for the scenario tests: `test_flagship_level.gd:69` `_make_level()` (gap_s 0.05, invincible, no-op `warp_mouse`, `SceneRouter.change_scene` recorder) and `test_level_3.gd` helpers (`_click_through`, `_drive_flagship_to_the_epilogue`).
- `_bmad-output/game-architecture.md` -- Debug Tools "Command-line modes" (:556-566; its `comms: StringName` / `debug_comms_id` wording is stale, fix while there), Performance "Verification" row (:1280), Deployment CLI export block (:1301-1310).
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- last row #66; format `| # | YYYY-MM-DD | Decision / Change | Source | Status |`; prior bench results #27, #32.

## Tasks & Acceptance

**Execution:**
- `game/data/tuning.json` -- add `debug.level_bench` and `debug.release_check` (values above) -- every bench and limit number is data.
- `game/tests/unit/test_debug_args.gd`, `test_boot.gd`, `test_debug_tools.gd` (or a new `test_wave_director_debug.gd`), new `game/tests/unit/test_level_bench.gd`, `test_level.gd` -- write first, failing: the I/O matrix rows (parse, bad arg, boot route debug/release, `debug_jump_to_wave` frees live counted enemies and starts wave i and refuses an out-of-range index with a warning, skip_to_boss still passes, busiest_wave jump + invincible + fire held + settle then sample, wave_cleared early end, desperate drive reaches DESPERATE with the choice picked and fire not held, phase_left early end, finish line format + quit after delay with 0/2, 0 samples FAIL, missing target FAIL, level.gd creates the bench only in debug builds with the arg). Scenario tests may inject smaller `sample_s`/`settle_s` and drive `_process` / a step method with fake times, like `_bench_tools()` does.
- `game/ui/debug/debug_args.gd` -- `level_bench` parsing.
- `game/systems/waves/wave_director.gd` -- `debug_jump_to_wave(index)`; `debug_skip_to_boss` reuses it.
- `game/ui/debug/level_bench.gd` (new, `class_name LevelBench extends Node`) -- the scenario driver and sampler per the matrix; refs and config injected by level.gd; `PROCESS_MODE_ALWAYS`; vsync off; preallocated `FrameStats`.
- `game/ui/debug/debug_tools.gd` -- extract the shared PASS rule; overlay on for `level_bench`.
- `game/scenes/level/level.gd`, `game/scenes/boot/boot.gd` -- wire the bench and the boot route (debug only).
- `tools/perf_check.py` + `tools/test_perf_check.py` -- subcommands `size <dir>` and `launch <exe> [--runs N]`, limits read from `game/data/tuning.json` `debug.release_check`; tests cover the size sum and limit, the `Title ready` line parse, the "log created after launch" freshness rule, timeout handling (mock `subprocess`, temp files; no real launch).
- Run the measurements (Verification) and, only if an overrun is instancing-caused, add pooling inside `game/core/spawner.gd` with tests.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- append #67 (2026-10-13, Story 8.3): the measured busiest_wave and desperate numbers (debug export), sandbox `--bench=20`, release size, launch runs, whether pooling was needed; Status `Measured on this machine; operator confirmation owed`.
- `_bmad-output/game-architecture.md` -- document `--level-bench` and its boot route, `perf_check.py` in Deployment, point Verification's "Last results" at #67, note the ADR-002 outcome.

**Acceptance Criteria:**
- Given a debug export of the current game, when it runs `-- --level-bench=busiest_wave` and `-- --level-bench=desperate` windowed at 1920×1080, then each logs a `Level bench:` line for its scenario and the recorded result is PASS (avg, p99 and max under 16.6 ms), or the run HALTs `blocked` with the numbers for a non-instancing overrun.
- Given a fresh release export, when `perf_check.py size` and `perf_check.py launch --runs 3` run against it, then the total is under 200 MB and every launch-to-title time is under 5 s, and both are recorded in decision #67.
- Given the full GUT suite and the tools unit tests, when they run, then all pass, and the sandbox `--bench=20` still reports PASS.
- Given a release build, when it is launched with `-- --level-bench=desperate`, then the title screen appears as normal (no bench).

## Spec Change Log

- 2026-10-13 (dev): `perf_check launch` also reads the game's stdout. Measured: a release build buffers the file logger (`application/run/flush_stdout_on_print` is off), so `Title ready` never reaches `godot.log` while the game runs and is lost when the process is killed (3/3 runs timed out reading only the log). Godot's Windows terminal logger writes stdout unbuffered, so the tool pipes stdout and takes whichever of stdout or a fresh `godot.log` shows the line first. Freshness is "written at or after the launch" (mtime), because Godot copies the old log to `godot<timestamp>.log` and truncates `godot.log` in place, so its identity and creation time never change. No game or project setting changed.
- 2026-10-13 (dev): a missing target (no WaveDirector, wave or Flagship) also writes the final `Level bench:` line, with `frames=0 ended=no_target result=FAIL`, after its `Log.error`. In `desperate` the player is also `debug_invincible` with the cursor at `BENCH_AIM` (fire still off), so a death can't end the run.

## Review Triage Log

### 2026-10-13 — Review pass
- verdicts: 32 findings — high 0, medium 0, low 25, false 7, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) A failed config with `--level-bench` goes to the title and never quits, so a scripted run waits — a broken versioned `tuning.json` during a bench is unlikely, the title shows the config error, and the fix adds a quit seam to boot.
  - `[low]` `[reject]` (blind) `--stress` silently wins over `--level-bench` when both are passed — nobody passes both; a warning branch is more than a direct correction.
  - `[false]` `[reject]` (blind) The documented final-line format omits `ended=no_target` — the architecture bullet and the `level_bench.gd` header both state the `frames=0, ended=no_target, FAIL` case right after the format line.
  - `[low]` `[reject]` (blind) Decision #67 records fullscreen 1920x1080 while the spec AC says "windowed" — "windowed" meant non-headless; fullscreen at 1920x1080 is the game's shipped mode and the stricter case; the only fix edits this spec.
  - `[false]` `[reject]` (blind) Paused or slowed frames can enter the sample — wave 3 has no story comms (`test_level_3.gd` "no story pause in wave 3") and DESPERATE has none until the core dies, which ends sampling; hit-stop frames still render at full cost.
  - `[low]` `[reject]` (blind) Only peak enemy and projectile counts are reported — a reporting preference with no named harm; averages add per-frame state.
  - `[false]` `[reject]` (blind) `abort()` is not gated on `debug_enabled` — level.gd creates a LevelBench only when `debug_level_bench` returns a scenario, which never happens in a release build, so abort can't run with `debug_enabled` false outside tests.
  - `[low]` `[reject]` (blind) Error and warning messages print the numeric level id ("level 0" for dev levels) — cosmetic and debug-only; WaveDirector holds only the int id, so the fix adds plumbing.
  - `[low]` `[reject]` (blind) `debug_jump_to_wave` leaves `Spawner.hold_enemy_fire` and the post-DYING safe player set when jumping out of a dying boss — identical to the pre-existing F6 behaviour it was extracted from; the bench always jumps from wave 1; rare debug use, and the fix adds resets.
  - `[low]` `[reject]` (blind) No test jumps away from a live boss wave — the boss-freeing code is the same block `test_f6_frees_the_live_flagship_and_starts_a_fresh_one` covers.
  - `[low]` `[patch]` (blind) No test covers a bench whose level fails to load — grouped with the verification-gap finding below; fixed by `test_level_that_fails_to_load_aborts_the_bench`.
  - `[low]` `[reject]` (blind) `perf_check.py` exits 1 (like a FAIL) on a broken `tuning.json` and accepts zero or negative limits — the shipped tuning is pinned by `test_limits_come_from_the_shipped_tuning`; catching it adds a branch for an unlikely case.
  - `[low]` `[patch]` (blind) `launch` pointed at `DEFECTOR.console.exe` kills only the wrapper — fixed: the docstring and the `launch` help now say to pass the game exe itself, never the `.console.exe` wrapper.
  - `[low]` `[reject]` (blind) `test_the_title_line_on_stdout_wins_over_a_buffered_log` relies on a 50 ms real wait for the reader thread — after `wait_drained` the reader only decodes and matches one line (microseconds); a flake needs an extreme stall, and the fix reworks the fake.
  - `[false]` `[reject]` (blind) Decision #67 names `DEFECTOR.exe` where the tool measured the folder — the release export folder holds only `DEFECTOR.exe` (a release export writes no console wrapper), so the two numbers are the same.
  - `[low]` `[reject]` (blind) The bench leaves vsync off after its node is freed in tests — headless runs have no vsync, and in a real run the bench quits the game.
  - `[low]` `[reject]` (blind) The spec's I/O matrix still says "a godot.log created after that start" while the change log moved to stdout plus mtime freshness — the fix edits this spec; the change log already records the deviation and why.
  - `[low]` `[reject]` (edge) `debug.level_bench.level` set to 1 routes through the story scene, where no bench runs, so the process never quits — the shipped value is 3; switching it to the opening level is unlikely, and the guard adds a branch.
  - `[low]` `[reject]` (edge) No drive timeout, so a bench stuck in WAITING or DRIVING never quits — not reachable with the shipped Level 3 (both scenarios reached their target in every run); a timeout adds a tuning key and a branch, and unattended callers wrap the run in an external timeout.
  - `[low]` `[patch]` (edge) A target wave that clears while the bench is still DRIVING is missed, so the next wave is sampled as the target — fixed: `_on_events_wave_cleared` now flags the target wave's clear in any stage except WAITING and DONE.
  - `[false]` `[reject]` (edge) A story comms pause during SAMPLING adds cheap paused frames — same refutation as the blind finding: no story comms can start in either sampled window.
  - `[low]` `[reject]` (edge) `popen` raising `OSError` gives a traceback instead of exit 2 — only for a corrupt or locked exe the user named; the fix adds a try branch.
  - `[low]` `[patch]` (edge) Launching the console wrapper orphans the real game — same root cause as the blind console-wrapper finding; fixed by the same docstring and help change.
  - `[low]` `[reject]` (edge) `os.walk` skipping an unreadable subfolder undercounts the size — the export folder was written by the same user moments before; unlikely, and the fix adds error handling.
  - `[low]` `[patch]` (verification-gap) No test checks that level.gd aborts the bench when the level fails to load — fixed: `test_level_that_fails_to_load_aborts_the_bench` (unknown level id; asserts DONE, `no_target`, exit 2, the FAIL line and quit [2] after the delay).
  - `[low]` `[patch]` (verification-gap) Boot's "failed config means title, not bench" guard is untested — fixed: `test_level_bench_with_a_bad_config_goes_to_the_title`.
  - `[low]` `[patch]` (verification-gap) The final line's peak `enemies=` value is never checked — fixed: the busiest_wave test parses `enemies=([0-9]+)` and asserts it is above 0.
  - `[false]` `[reject]` (intent) Finalization is missing (status, `operator_actions`, commit) — the review runs before finalization by design; this pass sets `awaiting-operator`, the operator actions and the commit.
  - `[low]` `[reject]` (intent) The DESPERATE window has no leftover boss Wasps, so it is lighter than organic play — recorded in decision #67 and covered by the operator's hands-on F1-overlay play; at about 4 ms per frame, 10 more Wasps leave a wide margin.
  - `[low]` `[reject]` (intent) Fullscreen versus "windowed" mismatch — same as the blind finding: fullscreen 1920x1080 is the shipped and stricter mode, and the fix edits this spec.
  - `[low]` `[reject]` (intent) The cold-launch AC is covered only by warm back-to-back runs — by design: a post-reboot cold launch is a human action, listed in `operator_actions`.
  - `[false]` `[reject]` (intent) "A release build ignores `--level-bench`" rests on static tests and a claim — the orchestrator re-ran the release export with `-- --level-bench=desperate` in this session: `Title ready 2442 ms after launch`, no bench line.


## Design Notes

The bench lives in the level, not the sandbox, because the AC names real content (Level 3 Wave 3, DESPERATE), and it boots through `boot.gd` so the same command works on the editor binary and on a debug export: `DEFECTOR.exe -- --level-bench=busiest_wave`. It clicks comms through instead of faking `GameState.is_retry`, so it plays the same path a player does. In DESPERATE fire is held off because the laser would kill the 50 HP core in about 5 s; the AC measures the phase's own load (bursts, aimed spreads, leftover Wasps, Ryn), not the player's kill. Launch time is measured from outside the process (wall clock to the title log line), since the in-game `Time.get_ticks_msec()` misses process start and the embedded-PCK load.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` then the GUT command from AGENTS.md -- expected: all pass
- `uv run python -m unittest tools/test_perf_check.py tools/test_import_cc0_art.py tools/test_import_cc0_audio.py tools/test_recolor_player_ship.py tools/test_gen_placeholder_sfx.py` -- expected: OK
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --path game -- --bench=20` (windowed) -- expected: `Stress bench:` result=PASS
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --export-release "Windows Desktop" export/windows/DEFECTOR.exe` and `--export-debug "Windows Desktop" export/windows_debug/DEFECTOR.exe` -- expected: both exes written (gitignored)
- `game/export/windows_debug/DEFECTOR.console.exe -- --level-bench=busiest_wave` and `-- --level-bench=desperate` -- expected: `Level bench:` result=PASS (exit 0)
- `uv run python tools/perf_check.py size game/export/windows` and `uv run python tools/perf_check.py launch game/export/windows/DEFECTOR.exe --runs 3` -- expected: under 200 MB; every run under 5 s

## Auto Run Result

Status: awaiting-operator

**Summary.** Story 8.3 is done as far as an agent can take it. A new debug-only level bench (`-- --level-bench=busiest_wave|desperate`) boots into Level 3 and plays it to the target state with no input: Wave 3 with fire held, or the Flagship's DESPERATE phase reached through the Final Choice. It times real frames and exits PASS (0) or FAIL (2), using the sandbox bench's pass rule (now shared through `DebugTools.bench_passed`). The new `tools/perf_check.py` measures an export's size and its launch-to-title time. Every target passed on this machine. No pooling was needed (ADR-002 not triggered), and Forward+ is kept. The results are recorded as decision #67. Hands-on play with the F1 overlay and a true post-reboot cold launch are owed to the operator (see `operator_actions`).

**Files changed**
- `game/ui/debug/level_bench.gd` (new): the LevelBench scenario driver and frame sampler.
- `game/ui/debug/debug_args.gd`: `--level-bench=<scenario>` parsing (never implies stress).
- `game/ui/debug/debug_tools.gd`: shared static `bench_passed()`; the overlay starts on for the level bench.
- `game/scenes/boot/boot.gd`: debug-only route to `SceneRouter.start_level(debug.level_bench.level)`.
- `game/scenes/level/level.gd`: creates and wires the LevelBench (debug builds only) and aborts it if the level fails to load.
- `game/systems/waves/wave_director.gd`: `debug_jump_to_wave(index)`; F6 now uses it.
- `game/data/tuning.json`: `debug.level_bench` and `debug.release_check`.
- `tools/perf_check.py` and `tools/test_perf_check.py` (new): `size` and `launch` checks and their stdlib tests.
- Tests: new `test_level_bench.gd`; additions to `test_debug_args.gd`, `test_boot.gd`, `test_debug_tools.gd`, `test_level.gd` and `test_wave_director.gd`.
- `_bmad-output/game-architecture.md`: the `--level-bench` docs, `perf_check.py` in Deployment, the Verification rows pointing at #67, and the stale `--comms` wording fixed.
- `decision-log.md`: decision #67 (the measurements; operator confirmation owed).

**Review findings.** 32 findings (high 0, medium 0, low 25, false 7).
- Patched (all low), across 5 entries:
  - a test that a level which fails to load aborts the bench;
  - a test that a bad config with `--level-bench` still goes to the title;
  - the busiest_wave test now asserts the reported peak `enemies=` is above 0;
  - a target-wave clear during DRIVING is no longer missed;
  - `perf_check.py` docs and help now say to launch the game exe, never the `.console.exe` wrapper.
- Deferred: none.
- Rejected: every remaining finding, each with its reason in the Review Triage Log above. They include the drive-timeout and config-failure hang edge cases (not reachable with shipped data, and fixing them adds branches), the fullscreen-versus-"windowed" wording (the fix would edit this spec), and the absence of boss Wasps in the DESPERATE window (recorded in #67 and covered by the operator's play).
- Follow-up review recommended: false (patched counts: high 0, medium 0, low 5 entries).

**Verification** (orchestrator re-runs after the patches; Forward+, vsync off, the game's default fullscreen window at 1920x1080):
- Headless `--import`: exit 0. Full GUT suite: 2062/2062 passed, including `test_level_bench.gd` 11/11.
- Tools tests: `uv run python -m unittest tools/test_perf_check.py tools/test_import_cc0_art.py tools/test_import_cc0_audio.py tools/test_recolor_player_ship.py tools/test_gen_placeholder_sfx.py` ran 78 tests, OK.
- Export: `--export-debug` and `--export-release` both exit 0 (to the gitignored `game/export/`).
- Debug export `-- --level-bench=busiest_wave`: frames=4966, avg 4.03 ms, p99 5.79 ms, max 7.22 ms, 24 enemies / 27 projectiles, ended=time, PASS (exit 0).
- Debug export `-- --level-bench=desperate`: frames=5334, avg 3.75 ms, p99 5.45 ms, max 9.91 ms, 2 enemies / 35 projectiles, ended=time, PASS (exit 0).
- Sandbox `--bench=20`: avg 4.13 ms, p99 8.64 ms, max 13.72 ms, 40 enemies / 201 projectiles, PASS.
- `perf_check.py size game/export/windows`: 117.6 MB (limit 200 MB), PASS.
- `perf_check.py launch ... --runs 3`: 2.77 s, 1.22 s and 1.39 s to the title (limit 5 s), PASS (warm runs).
- A release export launched with `-- --level-bench=desperate` shows the title (`Title ready 2442 ms after launch`) with no bench.

**Residual risks**
- The DESPERATE sample has no leftover boss Wasps (the bench passes through CORE at once), so organic play carries a little more load. Covered by the operator's hands-on check.
- The launch times are warm back-to-back runs, not a post-reboot cold start.
- Release builds buffer the file logger (`application/run/flush_stdout_on_print` is off), so a crash can lose the last lines of `godot.log`. That weakens the plan to use that log when a playtester reports a bug. Enabling the setting is the user's call; it was not changed.
- The level bench has no internal drive timeout. Unattended callers should wrap it in an external timeout.

## Operator Confirmation

Confirmed 2026-10-14: the external actions this story owed were carried out.

- On the dev laptop, export a debug build ("<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --export-debug "Windows Desktop" export/windows_debug/DEFECTOR.exe), launch it, press F7 to unlock every level, start Level 3 from Level Select, press F1 for the overlay and play Wave 3 by hand; confirm the overlay's frame ms stays under 16.6 ms throughout the wave.
- In the same debug export, play on into the Flagship fight, make the Final Choice with boss Wasps still alive, and confirm the F1 overlay's frame ms stays under 16.6 ms through the desperate phase until the core dies.
- Reboot the dev laptop, then as the first thing after login run uv run python tools/perf_check.py launch game/export/windows/DEFECTOR.exe (or launch and time the release exe by hand) and confirm the title screen appears in under 5 s.
- If the machine the agent measured on is not the dev laptop, re-run uv run python tools/perf_check.py size game/export/windows and both level benches (game/export/windows_debug/DEFECTOR.console.exe -- --level-bench=busiest_wave, then -- --level-bench=desperate) on the dev laptop.
- Record the outcome in decision #67 of the decision log (its status currently says operator confirmation owed).

_Appended by the bmad-loop orchestrator (`bmad-loop confirm`, #335): a human confirmed these external actions out of band, and the story was advanced from `awaiting-operator` to `done`._

## Operator sign-off

2026-10-15: the operator played the whole game end to end on the current build, then exported a Windows release build and played it, and signs off this story. **Waived:** the hands-on performance checks in `operator_actions` (the F1 overlay in the busiest wave and DESPERATE, the cold launch after a reboot, and the re-runs on the dev laptop) were not done. Why: the game runs smoothly in play on the operator's machine, and this is a personal project, not a commercial one. The bench numbers in decision #67 stand as the only measurements. Recorded in GDD decision #89.
