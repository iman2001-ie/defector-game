---
title: 'DW-9 + DW-21: stress bench at the NFR peak, p99/max judging, first-large-explosion timing, reliable final log line'
type: 'feature'
created: '2026-10-07'
status: done
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/performance-testing.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
warnings: []
deferred:
  - summary: >-
      The --no-prewarm wiring through Sandbox._ready and DebugTools._ready is not covered by any test, so a regression could mislabel the prewarm on/off comparison.
    evidence: |-
      Both _ready methods read OS.get_cmdline_user_args() directly, so tests cannot inject --no-prewarm. Tests cover only DebugArgs.parse, the static Sandbox.should_prewarm, and DebugTools with _prewarm set by hand. Deleting `_prewarm = args.prewarm` in debug_tools.gd would leave the suite green. Fix: an injectable user-args source for both _ready paths (the --stress wiring has the same gap).
    location: >-
      game/ui/debug/debug_tools.gd _ready; game/scenes/sandbox/sandbox.gd _ready
    severity: medium
baseline_revision: 2b7524fb6dd7ddd1d2e7da15a203e18a90905504
---

<intent-contract>

## Intent

**Problem:** The `--bench` run is lighter than the NFR peak (40 stationary Wasps plus one laser stream, against 40 enemies + 200 projectiles + particles), judges PASS on the average only, and never measures the first explosions because its 2 s warm-up skips them (DW-9, DW-4, DW-5). Its final `Stress bench:` log line is also often missing from stdout and godot.log, because `get_tree().quit()` runs in the same frame as the log call (DW-21).

**Approach:** In stress mode the sandbox keeps about 200 live projectiles topped up through `Spawner`. `DebugTools` judges PASS on avg, p99 and max, and fires one deliberate LARGE `Feedback.impact` during warm-up, logging that impact's frame time. A new `--no-prewarm` user arg makes the sandbox skip `Feedback.prewarm()`, so the operator can compare runs with and without pre-warm. The bench logs its final line, then quits after a short real-time delay through an injectable quit callable.

## Boundaries & Constraints

**Always:** Every new number, and the existing `FRAME_BUDGET_MS` / `BENCH_WARMUP_S`, is read through `Config` from a new top-level `debug` section in `tuning.json` (decided, see Design Notes). The stress-grid layout consts (`STRESS_COLUMNS` etc.) and `BENCH_MAX_FPS` / `BENCH_AIM` / `OVERLAY_REFRESH_S` stay code consts. Statically typed GDScript. Only `Spawner` creates entities. Only `Feedback` touches `Engine.time_scale` (the deliberate impact goes through `Feedback.impact`). All logging goes through `Log`. No per-frame allocation in `_process`/`_physics_process` (count live projectiles with `get_node_count_in_group(&"projectiles")`). Debug-only behaviour stays gated on `OS.is_debug_build()` / `debug_enabled`. Write the failing GUT tests first.

**Never:** Don't run the on-hardware bench as evidence of PASS (that run belongs to the operator). Don't change gameplay tuning, Feedback tiers, prewarm position (DW-4 stays the operator's call), or the normal (non-stress) sandbox. Don't add pooling (ADR-002). Don't edit `deferred-work.md` or `sprint-status.yaml`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Peak load | stress mode, fewer live projectiles than the target | each physics tick spawns `min(target - live, per_tick_cap)` stress projectiles via `Spawner` | Spawner returns null: skip, no crash |
| At target | live >= target | spawns nothing | none |
| PASS | avg, p99 and max all under their limits | `result=PASS`, exit 0 | none |
| FAIL on spike | avg under limit, max at or over its limit | `result=FAIL`, exit 2 | none |
| Empty bench | 0 samples | FAIL (exit 2), not a false PASS | logged line still written |
| First large | elapsed passes the first-large time during warm-up | one `Feedback.impact(ImpactTier.LARGE, …)`; after the measured frames, an INFO line `Stress bench: first LARGE impact … ms prewarm=on/off` | fires once only |
| `--no-prewarm` | user arg present (debug build) | sandbox logs that pre-warm was skipped and does not call `Feedback.prewarm()` | release build ignores it and still pre-warms |
| Finish | sampling window over | final `Stress bench:` line logged, fire released, quit called with the exit code only after the quit delay, never in the same frame | quit callable injectable for tests |

</intent-contract>

## Code Map

- `game/ui/debug/debug_tools.gd` -- bench runner. `FRAME_BUDGET_MS` / `BENCH_WARMUP_S` consts (:11-13) become Config reads; `_step_bench` (:161), `_finish_bench` (:171-186, races `get_tree().quit` with the log), `_bench_exit_code` (:190-191, avg only). `restart_scene` (:28) is the existing injectable-Callable pattern to copy for a `quit_game` Callable. `_process` (:70) measures real wall time, so hit-stop doesn't hide frame cost.
- `game/ui/debug/frame_stats.gd` -- reuse `average_ms`, `percentile_ms(99.0)`, `max_ms`; no change expected.
- `game/ui/debug/debug_args.gd` -- add `--no-prewarm` → `prewarm: bool` (default true) in the returned dictionary. Doc comment lists the args.
- `game/scenes/sandbox/sandbox.gd` -- stress grid (:13-17, :86-95); `_physics_process` (:51) is where the projectile top-up goes when `stress_mode`; `Feedback.prewarm()` call (:48) becomes conditional on the parsed `prewarm` (debug builds only).
- `game/core/spawner.gd` `spawn_projectile(&"laser_bolt", {position, velocity, damage})` (:35) -- the only way to create stress projectiles. Projectiles join group `projectiles` in `Projectile._ready` (`game/core/projectile.gd:39`) and free themselves outside `Playfield.RECT.grow(64)`.
- `game/entities/projectiles/laser_bolt.tscn` -- layer 2, mask 20 (enemies + asteroids). So stress projectiles must spawn **below** the Wasp grid (grid bottom y ≈ 366) and fly **down**, standing in for enemy bullets. Speed: reuse `weapons.enemy_bullet.max_speed_px_s` (450), so most stress shots never hit a Wasp and the projectile count stays the main load. Asteroids drifting through may be hit; that's acceptable.
- `game/autoloads/feedback.gd` -- `impact(tier, pos)` (:187) for the deliberate LARGE impact; `prewarm()` (:223). Large tier extras = debris + shockwave, which no other bench source plays before 3 s (small kills play burst + sparks), so the first-large measurement isolates the un-warmed debris and shockwave.
- `game/data/tuning.json` + `game/tests/unit/test_config.gd` `SECTIONS` (:12) -- the new numbers go in a new top-level `debug` section (decided, see Design Notes); add `"debug"` to `SECTIONS`.
- `game/tests/unit/test_debug_tools.gd` (bench tests :208-246), `test_debug_args.gd`, `test_sandbox.gd` (stress tests :249-291) -- extend these.
- `_bmad-output/game-architecture.md` -- Debug Tools "Command-line modes" (:539-543) and Performance "Verification" row (:1215) describe the bench and must be updated to the new behaviour; tuning sections list (:1159).

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_debug_args.gd` -- tests: `--no-prewarm` sets `prewarm=false`; default true; combines with `--bench`.
- `game/ui/debug/debug_args.gd` -- parse `--no-prewarm`.
- `game/tests/unit/test_debug_tools.gd` -- tests: exit code FAIL when avg passes but p99 or max is at or over its limit, and FAIL on 0 samples; `_finish_bench` emits the `Stress bench:` line (via `Log.sink`) with avg/p99/max and does **not** call the injected quit in the same frame, then calls it with the exit code after the delay; the first-large impact fires once at its time during warm-up and logs its frame ms with `prewarm=on|off`.
- `game/ui/debug/debug_tools.gd` -- read the bench numbers from Config; judge on all three stats; deliberate LARGE impact during warm-up plus its frame-time log line; release fire, log, then quit after the delay through `quit_game` (defaults to `get_tree().quit`); add `projectiles=<live count>` to the final line.
- `game/tests/unit/test_sandbox.gd` -- tests: stress sandbox tops up to the target live projectile count within the expected ticks without exceeding the per-tick cap; normal sandbox spawns none; stress projectiles spawn below the grid and move down.
- `game/scenes/sandbox/sandbox.gd` -- the stress projectile top-up in `_physics_process`; conditional pre-warm with a log line when skipped.
- `game/data/tuning.json` -- add the top-level `debug` section with exactly the keys listed in Design Notes.
- `game/tests/unit/test_config.gd` -- add `"debug"` to `SECTIONS`.
- `_bmad-output/game-architecture.md` -- update the bench description, the Verification row, and the fixed sections list (:1159) to include `debug`, with a one-line note on `debug.bench` / `debug.stress` like the `render.glow` bullet.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- append one row (next number, 2026-10-07): bench and stress numbers live in a new `tuning.json` `debug` section (DW-9/DW-21), user decision, extending the fixed sections list.

**Acceptance Criteria:**
- Given `-- --bench=N`, when the run ends, then the final `[INFO][debug] Stress bench:` line reports frames, avg, p99, max, enemies and projectiles, and `result=PASS` only when avg, p99 and max are all under their Config limits (exit 0, else 2).
- Given stress mode, when the sandbox has run for a few seconds, then about the Config target (200) of projectiles are live alongside the 40-Wasp grid.
- Given `-- --bench=N` with and without `--no-prewarm`, when the deliberate LARGE impact fires in warm-up, then one `Stress bench: first LARGE impact` line logs its frame ms and the pre-warm state.
- Given any bench run, when it finishes, then the final line is written before the quit happens, which is a later frame after the Config delay.
- Given the full GUT suite, when run headless, then every test passes.

## Spec Change Log

- 2026-10-07 (bmad-loop resolve): the open decision on where the bench numbers live was resolved as option A (new `debug` tuning section). Boundaries, Tasks and Design Notes were updated to match.

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 25 findings — high 0, medium 2, low 14, false 9, maybe-false 0
- findings:
  - `false` `reject` Stress bolts breaking asteroids make the deliberate impact not the first LARGE explosion — the first asteroid spawns only after `ASTEROID_INTERVAL_S` (3 s), above the screen, while the deliberate LARGE impact fires at 1.0 s, so nothing LARGE can come first.
  - `low` `reject` A laser bolt is not a faithful enemy bullet (no player collision, glow sprites) — the spec chose this stand-in on purpose, no enemy-bullet scene exists yet, and fixing it means a new entity.
  - `false` `reject` DW-21 uses a delay instead of a flush and has no multi-run evidence — the intent allows "flush or defer the quit", and 13 headless bench runs in this session all printed the final line.
  - `low` `reject` Pass/fail limits are read live while timing values are cached at start — this only matters for an F5 during a bench, which nobody does in practice; changing it adds state.
  - `medium` `defer` Untested paths: `DebugTools._ready`/sandbox `_ready` prewarm wiring, plus the misconfig warning and the partial first-large log — grouped with the verification-gap finding below (same root cause: `_ready` reads OS args directly); the misconfig paths are unreachable with shipped values.
  - `low` `reject` The sandbox test copies the grid constants (150 + 3 × 72) — test-only, harmless while the grid stays unchanged; the fix needs constant plumbing.
  - `low` `reject` The live count includes bolts queued for deletion — the count dips by a few bolts for at most one tick and is refilled the next; the intent says "about 200".
  - `low` `reject` The sandbox RNG is not seeded in bench mode — the asteroid RNG behaviour already existed; asteroids first appear after the first-large measurement ends.
  - `false` `reject` No new bench result recorded and the ledger is still open — the intent leaves the on-hardware run to the operator and the ledger to the orchestrator.
  - `false` `reject` The max gate is fragile against one hiccup — the intent asks for PASS on all three stats; the Design Notes record the 16.6 ms choice and `max_ms_max` is tunable.
  - `low` `patch` The quit timer was connected to a DebugTools method, so freeing the node during the delay would drop the quit and hang a headless bench — fixed: the timer now calls `quit_game.bind(exit_code)` directly and the `_quit` helper is gone.
  - `low` `reject` Stress bolts hitting asteroids add impacts and hit-stop to the sampled window — the spec accepts it, and explosions are part of the NFR1 peak (40 enemies + 200 projectiles + particles).
  - `low` `patch` A DebugTools freed before the quit timer fires means the bench never quits — same root cause and fix as the quit-timer patch above.
  - `false` `reject` First LARGE logs a cost even when Feedback has no spawner — the bench only runs in the sandbox, which registers the spawner, and both lines appeared in every headless run.
  - `low` `reject` `first_large_frames <= 0` logs "over 0 frames" — only reachable through a misconfigured value, and the line is honest about it.
  - `low` `reject` Queued and player bolts count toward the target — same as the queued-for-deletion finding above; the spec chose group counting.
  - `low` `reject` Release builds now parse the debug args and may warn on a malformed `--bench` — the only harm is one warning log in release; gating it adds a branch.
  - `low` `reject` The "200 projectiles" claim includes the player's bolts — the spec says so explicitly, and the intent says "about 200".
  - `medium` `defer` The `--no-prewarm` wiring through both `_ready` methods is untested, so a regression could mislabel the prewarm on/off comparison — pre-verified gap; closing it needs an injectable args source for both `_ready` paths, the same refactor the existing `--stress` wiring lacks. The headless `--no-prewarm` runs did show the skip line and `prewarm=off`.
  - `false` `reject` DW-21 is not flushed and the tests never check stdout — the intent allows deferring the quit; repeated real-process runs confirmed the line reaches stdout.
  - `low` `reject` Player bolts reduce how many stress bolts get spawned — duplicate of the counting finding above; the total stays about 200.
  - `false` `reject` Moving enemies are not used — the intent says "projectiles and/or moving enemies".
  - `false` `reject` The empty-bench FAIL was not asked for — it is required by the spec's matrix and is not a defect.
  - `low` `reject` The first-large window also contains the stress load — this is inherent to measuring in place, and the on/off comparison runs under the same load.
  - `false` `reject` User sign-off for the new `debug` section cannot be verified — the Spec Change Log records the user's bmad-loop resolve decision (option A).

### 2026-10-07 — Review pass
- verdicts: 24 findings — high 0, medium 3, low 11, false 10, maybe-false 0
- findings:
  - `low` `reject` Stress bolts can blow up asteroids inside the sampled window — carried: same as the earlier "stress bolts hitting asteroids" row; the NFR1 peak includes explosions and the spec accepts it.
  - `false` `reject` A large asteroid destroyed before 1.0 s makes the deliberate impact not the first LARGE — carried: the first asteroid spawns after `ASTEROID_INTERVAL_S` (3 s), so nothing LARGE comes before the 1.0 s impact.
  - `low` `reject` A laser bolt is not a faithful enemy-bullet stand-in (and borrows `weapons.laser.damage`) — carried: chosen on purpose, and no enemy-bullet scene exists yet; the damage value has no effect on the load.
  - `false` `reject` No bench result recorded for the new gate — carried: the intent leaves the on-hardware run to the operator.
  - `false` `reject` The 16.6 ms max gate will FAIL on noise — carried: the intent asks for PASS on all three stats, and `max_ms_max` is tunable.
  - `low` `reject` Pass limits are read at finish while timing values are cached at start — carried: only an F5 during a bench changes them.
  - `low` `reject` The first-LARGE frames can spill into the sampled stats — only with a misconfigured `first_large_at_s` close to `warmup_s`; shipped values (1.0 s + 3 frames vs 2.0 s) never overlap, and a guard would add a branch for a case nobody configures.
  - `medium` `defer` Untested paths (`_ready` wiring, misconfig warning, zero first-large frames, quit during hit-stop, default `quit_game`) — carried: same as the earlier grouped untested-paths row, already deferred as the `_ready` wiring gap; not re-deferred.
  - `low` `reject` `test_sandbox.gd` copies the grid constants — carried: test-only, and harmless while the grid stays unchanged.
  - `low` `reject` Stress bolt x positions use the unseeded sandbox RNG — carried: the asteroid RNG already behaved this way, and the first-large measurement ends before any asteroid appears.
  - `false` `reject` DebugTools' `prewarm=` label can be wrong under another main scene — `debug_tools.tscn` is instanced only in `sandbox.tscn`, the same scene that applies `--no-prewarm`, so no other scene can run the bench.
  - `low` `reject` A single hitch of 1 s or more can jump past the whole first-large window and lose the line silently — real but needs a frame of 1 s or more at exactly that moment; all 16 headless runs logged the line, and a warning adds a branch for a case nobody has seen.
  - `false` `reject` A null `spawn_projectile` floods the log with 20 errors per tick — the sandbox always has the Projectiles container and `laser_bolt` is a registered id; every bench run reported `projectiles=200–201`.
  - `low` `reject` Asteroids drifting into the stress bolts add LARGE hit-stops — carried: duplicate of the asteroid row above.
  - `low` `reject` `debug.stress.projectiles` at 0 silently disables the load — only reachable through misconfigured tuning; the final line reports `projectiles=` so the operator sees it.
  - `false` `reject` `_finish_bench` can connect an invalid `quit_game` — `_finish_bench` is reached only from `_process` after `_ready` has set `quit_game` (`debug_tools.gd:64-65`); a disabled DebugTools never processes.
  - `false` `reject` The comment claiming the deliberate impact's debris and shockwave come first is wrong — carried: no asteroid exists before 3 s, and Wasp kills are SMALL tier (burst and sparks only).
  - `medium` `defer` `DebugTools._ready` never verified to pass `--no-prewarm` into the `prewarm=` label — carried: the same pre-verified gap already deferred (DW-27); not re-deferred.
  - `false` `reject` The final line reaching stdout/godot.log is untested — carried: the intent allows deferring the quit; three more real-process runs in this pass printed the line.
  - `low` `reject` The player's held-fire bolts count toward the 200 — carried: the intent says "about 200", and the spec chose group counting.
  - `false` `reject` The first natural SMALL kills stay unmeasured — the intent's approach names one deliberate LARGE impact as the first-explosion measurement, and the diff does exactly that.
  - `medium` `defer` `--no-prewarm` `_ready` wiring is untested in both scenes — carried: same root cause as the DW-27 deferral; not re-deferred.
  - `false` `reject` `--no-prewarm` also skips pre-warm in the normal sandbox — the intent's matrix row applies to "user arg present (debug build)" with no stress condition, and without the arg the normal sandbox is unchanged.
  - `low` `reject` One parameter Dictionary per spawned stress bolt in `_physics_process` — `Spawner.spawn_projectile` takes a Dictionary by design; this happens only in debug stress mode, at most 20 a tick, and avoiding it means changing the Spawner API.

## Design Notes

**DECIDED (user, 2026-10-07, bmad-loop resolve): option A, a new top-level `debug` section in `tuning.json`.** The architecture's fixed sections list is extended to add `debug` (architecture, `test_config.gd` `SECTIONS` and a decision-log row all updated). The keys are exactly:
- `debug.bench`: `avg_ms_max` (16.6), `p99_ms_max` (16.6), `max_ms_max` (16.6), `warmup_s` (2.0, replaces `BENCH_WARMUP_S`), `first_large_at_s` (inside warm-up, e.g. 1.0), `first_large_frames` (frames measured after the impact, e.g. 3), `quit_delay_s` (e.g. 0.25).
- `debug.stress`: `projectiles` (200), `projectile_spawn_per_tick` (e.g. 20).

`FRAME_BUDGET_MS` and `BENCH_WARMUP_S` are removed in favour of these reads. Grid layout consts and `BENCH_MAX_FPS` / `BENCH_AIM` stay as code consts. They aren't new numbers, and the Story 1.4/1.7 precedent holds for them. The rejected option B was to keep every bench number as a code const.

**Thresholds:** p99 and max use the same 16.6 ms budget as the average (the architecture budget is per frame; the Story 1.9 AC already judges p99 against 16.6). A single OS hiccup can now FAIL a run; the operator can raise `max_ms_max` if that proves noisy.

**DW-21 cause:** quit in the same frame as the print. Godot flushes stdout on print in debug builds (`application/run/flush_stdout_on_print.debug`), but the console wrapper and file logger can lose the tail on an immediate quit. Deferring the quit by a short real-time timer (`create_timer(delay, true, false, true)`, ignoring time_scale) gives the output time to drain. Verify with several short headless `--bench=2` runs, checking each one for the line.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass.
- Five runs of `"<GODOT_DIR>/…_console.exe" --headless --path game -- --bench=2` (plus one with `--no-prewarm`) -- expected: every run prints the final `Stress bench:` line and the `first LARGE impact` line. Headless timings are not performance evidence.


## Auto Run Result

Status: done (follow-up review pass)

**Summary:**
- The stress sandbox keeps about 200 live projectiles topped up through `Spawner` (NFR1 peak).
- The bench judges PASS on avg, p99 and max, all read from the new `debug` tuning section. An empty bench fails.
- During warm-up the bench fires one deliberate LARGE impact and logs its frame cost, tagged with whether pre-warm ran. `--no-prewarm` skips `Feedback.prewarm()`.
- The final `Stress bench:` line is logged first. The quit runs later, after a real-time `quit_delay_s` timer, through the injectable `quit_game` (DW-21).

**Files changed (since baseline 2b7524fb6dd7ddd1d2e7da15a203e18a90905504):**
- `game/data/tuning.json`: new `debug.bench` / `debug.stress` section.
- `game/ui/debug/debug_args.gd`: parses `--no-prewarm`.
- `game/ui/debug/debug_tools.gd`: three-stat gate from Config, first-LARGE measurement, delayed quit, `projectiles=` in the final line.
- `game/scenes/sandbox/sandbox.gd`: stress projectile top-up and conditional pre-warm.
- `game/tests/unit/test_debug_args.gd`, `test_debug_tools.gd`, `test_sandbox.gd`, `test_config.gd`: new and updated tests.
- `_bmad-output/game-architecture.md`: bench description, Verification row and sections list.
- `decision-log.md`: row #33.

**Review findings (this pass):**
- 24 findings: 0 high, 3 medium, 11 low, 10 false.
- No patches applied.
- No new deferrals. All three medium findings are the already-deferred `_ready` `--no-prewarm` wiring gap (DW-27), carried forward.
- 21 rejected. Each reason is in the Review Triage Log. Most repeat earlier rows. The new ones are false or misconfig-only lows: the >1 s hitch skipping the first-large window, the first-large frames overlapping the sample, zero stress tuning, and the per-bolt Dictionary.
- Patched by verdict: 0 high, 0 medium, 0 low.

**Follow-up review recommended:** false. This was a follow-up pass and it patched no high finding, so the work has converged.

**Verification:**
- Full GUT suite headless: 343/343 passing.
- `--bench=2` headless twice, plus once with `--no-prewarm`:
  - every run printed the `first LARGE impact` line and the final `Stress bench:` line, with `enemies=40 projectiles=201 result=PASS`;
  - the `--no-prewarm` run logged the skip line and `prewarm=off`;
  - headless timings are not performance evidence.

**Residual risks:**
- The on-hardware `--bench=20` with the new load and gate is still the operator's to run.
- `max_ms_max` at 16.6 ms may FAIL on a single OS hiccup.
- Stress bolts can hit drifting asteroids after 3 s.
- The `_ready` `--no-prewarm` wiring stays untested (DW-27).
