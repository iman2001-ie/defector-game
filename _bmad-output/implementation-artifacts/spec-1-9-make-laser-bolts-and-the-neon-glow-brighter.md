---
title: 'Story 1.9: Make Laser Bolts and the Neon Glow Brighter'
type: 'feature'
created: '2026-10-07'
status: done
baseline_revision: 'dc24dce1736970fd0e48796adfcbad0347aaf4b4'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
warnings: ['oversized']
deferred:
  - summary: >-
      The bench's final `Stress bench:` log line is often missing from stdout and godot.log although the run completes and exits 0.
    evidence: |-
      Observed by the Story 1.9 implementer across several `-- --bench=20` runs (most runs without --verbose, one of three with it). Looks like an output-flush race between Log and get_tree().quit() in DebugTools._finish_bench. Pre-existing (Story 1.7 code); settle by flushing the log before quit and re-running the bench several times.
    location: >-
      game/ui/debug/debug_tools.gd _finish_bench
    severity: low
operator_actions:
  - 'Export the build (`<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe --headless --path game --import`, then `--headless --path game --export-release "Windows Desktop" export/windows/DEFECTOR.exe`), copy it outside the repo, run it, fire the laser and confirm the bolts read as bullets and the neon is slightly brighter than before but not washed out.'
  - 'If the look needs tuning, edit `render.glow` (intensity / bloom / hdr_threshold) and `weapons.laser.glow_energy` / `halo_energy` in game/data/tuning.json (F5 reloads in a debug run), then re-export and re-check.'
  - 'Check the ADR-003 fallback: set `render.glow.intensity` and `render.glow.bloom` to 0 (F5) and confirm the additive halo alone still makes the bolts read as bullets; restore the values afterwards.'
  - 'Record the final values in decision-log row 32 (the #30 tuning note) and change its status from "Applied (provisional)" to applied/confirmed.'
---

<intent-contract>

## Intent

**Problem:** GDD decision #30: laser bolts barely cross the HDR glow threshold (gradient colour max 1.0), so they don't read as bullets, and the overall neon is a bit dim. The WorldEnvironment glow values (0.8 / 0.05 / 0.6) are hard-coded in `sandbox.tscn`, so F5 can't tune them.

**Approach:** Move glow intensity, bloom and HDR threshold into `tuning.json → render.glow` with slightly brighter first-pass values, applied by the scene root in `_ready()` (F5 restarts the scene, so this covers reload too). Give each laser twin an HDR core (self_modulate = `weapons.laser.glow_energy` > 1.0) plus a wider additive halo sprite whose brightness is `weapons.laser.halo_energy`.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript with tabs. Read tuning only through `Config` getters, cached in `_ready()`. Log through `Log`. No per-frame work added to `_physics_process`/`_process`.
- First-pass values (tuning per #11, judged later on export): `render.glow = { "intensity": 1.0, "bloom": 0.08, "hdr_threshold": 0.55 }` — every value at least as bright as the 0.8 / 0.05 / 0.6 baseline, none drastically so. `weapons.laser.glow_energy = 2.5`, `weapons.laser.halo_energy = 1.0`.
- The halo uses an additive `CanvasItemMaterial` (ADR-003 fallback), so the bolt reads without WorldEnvironment glow. The halo is wider than the core and draws behind it.
- The bolt keeps its hitbox, twin layout (±8 px), collision layers and damage. Bolt colours stay in the player cyan `#22E6FF` family.
- Keep `glow_enabled = true` and `background_mode = 3` in the `.tscn`; only intensity, bloom and threshold become data.

**Never:**
- No change to the bench logic, its PASS rule, `BENCH_AIM`, the renderer or `hdr_2d`.
- No architecture-doc edits (Story 1.10). Don't edit `sprint-status.yaml`.
- No glow on other entities (missile, Wasp, asteroid, explosions) in this story.
- Don't claim the look is verified: the export judgement is an operator action.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Scene start | `render.glow` = 1.0 / 0.08 / 0.55 | WorldEnvironment env has intensity 1.0, bloom 0.08, hdr_threshold 0.55 | — |
| Changed data (F5 path) | tuning `render.glow.intensity` set to 1.3, sandbox re-instantiated | env intensity 1.3 | — |
| Missing key | `render.glow` absent | Config's standard missing-key error names the path; fallback 0 | existing Config behaviour |
| Bolt spawn | `glow_energy` 2.5, `halo_energy` 1.0 | each core sprite self_modulate = (2.5, 2.5, 2.5, 1); each halo self_modulate = (1, 1, 1, 1) | — |
| Changed bolt data | `glow_energy` 3.0 | new bolts' cores at 3.0 | — |
| Glow off | env glow disabled (operator check: set `render.glow.intensity` 0 + F5) | halo still draws additively around each core | visual, operator action |

</intent-contract>

## Code Map

- `game/scenes/sandbox/sandbox.tscn` L9-14 -- `Environment_glow` sub-resource: delete the three `glow_intensity`/`glow_bloom`/`glow_hdr_threshold` lines; L44 `WorldEnvironment` node stays.
- `game/scenes/sandbox/sandbox.gd` `_ready()` -- the scene root; add the glow application before the stress/formation setup. Pattern for tuning reads: `_spawn_random_asteroid` uses `Config.num`.
- `game/core/` -- add `render_glow.gd` (`class_name RenderGlow extends RefCounted`, `static func apply(env: Environment) -> void`) so later level scenes (Epic 4) reuse the same call. Siblings like `playfield.gd`/`impact_tier.gd` are small static helpers.
- `game/ui/debug/debug_tools.gd` `reload_data()` -- read-only: F5 calls `Config.reload()` then `restart_scene`, so a scene-root `_ready()` re-applies glow. No change needed.
- `game/entities/projectiles/laser_bolt.tscn` -- twins `BoltLeft`/`BoltRight` (Sprite2D, 6×28 `GradientTexture2D_bolt`, additive material) at x ±8. Add a `Halo` Sprite2D child under each twin (wider/longer radial cyan gradient, e.g. 24×56, low alpha centre fading to 0, additive material, `show_behind_parent = true`). Rename nothing (tests may reference `BoltLeft`/`BoltRight`).
- `game/entities/projectiles/laser_bolt.gd` -- currently empty body over `Projectile`. Override `_ready()`: read `weapons.laser.glow_energy` / `halo_energy`, set each twin's `self_modulate` to `Color(e, e, e, 1)` and each halo's `self_modulate` to `Color(h, h, h, 1)`, then `super._ready()`. Cache node refs via `@onready` or `get_node` in `_ready` only. Pattern: `missile.gd` `_ready()` reads Config then calls `super._ready()`.
- `game/data/tuning.json` -- add top-level `"render": { "glow": {...} }`; add `glow_energy`, `halo_energy` under `weapons.laser` (L15-20).
- `game/tests/unit/test_config.gd` L97 `test_tuning_has_exactly_the_fixed_sections` -- add `render` to the expected section list; L118 `test_mandatory_key_paths` -- add the five new keys.
- `game/tests/unit/test_sandbox.gd` L219 `test_world_environment_glow` -- extend; uses `_sandbox` from `before_each` and `SANDBOX_SCENE`; `_stress_sandbox()` shows how to re-instantiate.
- `game/tests/unit/test_projectile.gd` / `test_player_laser.gd` -- existing bolt tests; spawn pattern via `Spawner` with a test world (see `test_player_laser.gd` `before_each`).
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- add row 32 as the #30 tuning note.
- `game/ui/debug/debug_tools.gd` bench -- read-only; run `-- --bench=20` and read p99 from the `Stress bench:` log line.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_render_glow.gd` (new) -- write first (red): `RenderGlow.apply` sets the three env fields from Config; changed tuning is applied; `render.glow` values are each ≥ baseline brightness (intensity ≥ 0.8, bloom ≥ 0.05, threshold ≤ 0.6) and at least one is strictly brighter; `sandbox.tscn` text contains no `glow_intensity`, `glow_bloom` or `glow_hdr_threshold`. Restore Config tuning in `after_each`.
- `game/tests/unit/test_laser_bolt_glow.gd` (new) -- write first (red): a spawned bolt's two twins have self_modulate r,g,b = `glow_energy` (> 1.0); each twin has a `Halo` with additive `CanvasItemMaterial`, `show_behind_parent`, self_modulate = `halo_energy`, and a drawn size wider and longer than the core; changing `glow_energy` in Config changes new bolts; hitbox unchanged.
- `game/core/render_glow.gd` -- the static helper described in the Code Map.
- `game/scenes/sandbox/sandbox.gd` + `sandbox.tscn` -- apply `RenderGlow.apply($WorldEnvironment.environment)` in `_ready()`; strip the three values from the `.tscn`.
- `game/entities/projectiles/laser_bolt.tscn` + `laser_bolt.gd` -- HDR core and halo per the Code Map; update the class doc.
- `game/data/tuning.json` -- the five new keys with the first-pass values.
- `game/tests/unit/test_sandbox.gd`, `test_config.gd` -- extend as in the Code Map.
- Bench -- after tests pass, run `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --path game -- --bench=20` (windowed, not headless); record the `Stress bench:` line (avg, p99, max) in this spec's Auto Run Result.
- `decision-log.md` -- add row 32: "#30 tuning note: render.glow intensity 1.0 / bloom 0.08 / hdr_threshold 0.55 (was 0.8 / 0.05 / 0.6 in the .tscn); laser glow_energy 2.5, halo_energy 1.0; bench p99 <value>. Provisional until the operator's export check", status "Applied (provisional)".

**Acceptance Criteria:**
- Given the sandbox starts or F5 reloads data, when the scene root readies, then the WorldEnvironment intensity, bloom and HDR threshold equal `tuning.json → render.glow`, and `sandbox.tscn` no longer hard-codes them.
- Given a laser bolt renders, then each core's self_modulate is above 1.0 (from `weapons.laser.glow_energy`) and a wider additive halo (brightness `weapons.laser.halo_energy`) sits behind it.
- Given the `--bench=20` run after the change, then the logged p99 is under 16.6 ms and is recorded in this spec and the decision-log note.
- Given the GUT suite runs headless, then all tests pass.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 25 findings — high 0, medium 0, low 19, false 6, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) The baseline-brightness test pins tuning: dimming `render.glow` below 0.8/0.05/0.6 turns the suite red. — The test encodes decision #30 ("slightly brighter" than that baseline). Going dimmer is a design change that should update the test and the log, not a silent tuning tweak.
  - `[low]` `[reject]` (blind) No test for a missing `render.glow` key; the fallback 0 is dangerous. — Covered by Config's generic missing-key tests (error naming the path, debug assert). It's only reachable with broken data, and the fix adds guards.
  - `[low]` `[reject]` (blind) No range check on glow or energy values (e.g. glow_energy 0.9, negative halo). — Only reachable with bad hand-edited data, which shows up at once on screen. Adding warnings or clamps adds branches for a debug-time typo.
  - `[low]` `[reject]` (blind) `LaserBolt._ready` skips missing twins or halos silently. — `test_laser_bolt_glow` asserts both twins and halos exist, so a rename fails the suite. Logging would add branches.
  - `[low]` `[reject]` (blind) "Every scene root calls RenderGlow.apply" is only enforced for the sandbox. — The sandbox is the only scene with a WorldEnvironment today. Level roots arrive in Epic 4, and the helper's doc names the contract.
  - `[false]` `[reject]` (blind) `$WorldEnvironment` crashes on a missing node before the null guard. — The node exists in sandbox.tscn and test_sandbox asserts it. A loud crash on a broken scene is correct behaviour, not a defect.
  - `[low]` `[reject]` (blind) `apply()` mutates the shared Environment sub-resource, and the F5 test only checks intensity. — Harmless: every `_ready()` re-applies all three values, and test_world_environment_glow checks all three.
  - `[low]` `[reject]` (blind) The glow-off fallback (ADR-003) has no test. — It's a visual judgement. The additive material is asserted, and the look is an operator action.
  - `[low]` `[patch]` (blind) Decision-log row 32 lacks the pre-change bench baseline. — Fixed: row 32 now cites "p99 7.01 ms before the change, row 27". The operator follow-up is tracked in `operator_actions`.
  - `[low]` `[patch]` (blind) `test_changed_glow_energy_applies_to_new_bolts` skips the halo check when Halo is null; other test nits. — Fixed: it now runs `assert_not_null(halo)` before the self_modulate check. The duplicate HDR assert and the `Feedback.reset()` call are harmless, so they were left as they are.
  - `[false]` `[reject]` (blind) The reviewed patch leaves out the spec file. — By design: the spec is the claims file, given only to the edge-case layer.
  - `[false]` `[reject]` (edge) `sandbox.gd:37` crashes on a missing WorldEnvironment. — Same as the blind finding: the node is guaranteed by the scene and asserted by tests, and failing loudly is correct.
  - `[low]` `[reject]` (edge) Zero, negative or missing `render.glow` values make the whole screen bloom. — Only bad data reaches this, and the fix adds clamps. It's visible immediately in a debug run.
  - `[low]` `[reject]` (edge) A `glow_energy` of ≤ 1 or missing stops bolts blooming, with no warning. — Same as the range finding: bad data only, and fixing it needs a new guard.
  - `[low]` `[reject]` (edge) A missing twin or Halo is skipped silently. — Same as the blind finding: the tests catch it.
  - `[false]` `[reject]` (edge, deletion) Removing the `.tscn` glow values makes the editor preview fall back to Godot defaults. — The AC requires the values not to be hard-coded in the `.tscn`. The editor preview is not a gameplay path.
  - `[low]` `[reject]` (edge, claim) The shared Environment couples instances. — Same as the blind finding: every root re-applies its values on `_ready()`.
  - `[low]` `[patch]` (edge, claim) The halo_energy path can pass the test without being checked. — Same root cause as the blind test finding, fixed by the same patch.
  - `[false]` `[reject]` (intent) The finalization surface (status, operator_actions) is missing from the diff. — Finalization happens after review. It is done here as awaiting-operator, with operator_actions.
  - `[low]` `[reject]` (intent) Row 32 is written by the agent before the human check that AC4 calls for. — It's marked provisional, and the operator action asks the developer to record the final values and confirm it.
  - `[low]` `[reject]` (intent) Tests check node properties, not the rendered look. — Rendered look is a human-only judgement (operator action). Tests cover the config-to-node layer.
  - `[low]` `[reject]` (intent) Setting intensity to 0 doesn't truly disable glow because `glow_enabled` stays true. — With intensity and bloom both at 0, glow adds nothing, so the operator action sets both. It needs no code change.
  - `[low]` `[reject]` (intent) The real F5 path (`reload_data` → `restart_scene`) is not run end to end. — test_debug_tools already covers reload → restart. This story only adds the scene-root `_ready()` part, which is tested.
  - `[low]` `[defer]` (intent) Bench reproducibility: the `Stress bench:` line often goes missing. — Pre-existing (Story 1.7 DebugTools). Deferred with low severity.
  - `[false]` `[reject]` (intent) Halo size and alpha live in the `.tscn`, not in data. — These are art values, not GDD numbers. The AC asks only for the brightness values to be data (`glow_energy`, `halo_energy`).

### 2026-10-07 — Review pass (verification repair)
- verdicts: 24 findings — high 0, medium 0, low 18, false 6, maybe-false 0
- findings:
  - `[false]` `[reject]` (blind) AC3: the bench line isn't in this spec's Auto Run Result. — The Auto Run Result is written at finalization, and this pass writes it with both bench lines.
  - `[false]` `[reject]` (blind) The spec status `in-review` disagrees with sprint-status `awaiting-operator`. — Mid-review status by design. Finalization sets `awaiting-operator`.
  - `[false]` `[reject]` (blind) No `.bmad-loop/operator/1-9-*.json` file was created. — The orchestrator writes those from `operator_actions`; a story never writes them.
  - `[low]` `[patch]` (blind) Story 1.8 ring tuning (`player.missile_ring` 36/5 → 16/4) is mixed into this diff, with the values unrecorded. — Operator tuning saved at 15:21, just before the 1.8 confirmation at 15:23. Patched by committing it on its own as Story 1.8 operator tuning (values in the commit message), not as part of 1.9.
  - `[low]` `[patch]` (blind) The rewritten ring-radius assertion always passes, because MissileRing clamps `radius_px`. — Fixed: the test now checks the raw `Config.num("player.missile_ring.radius_px")` against `sprite_px / 2`. Whether 16 px reads well is the operator's call, already confirmed for 1.8.
  - `[low]` `[reject]` (blind) The F5 test reads a shared Environment sub-resource. — carried: harmless, since every `_ready()` re-applies all three values.
  - `[false]` `[reject]` (blind) Halo alpha and size are hard-coded in the `.tscn`, and halo intent is undocumented. — carried: these are art values, not GDD numbers.
  - `[false]` `[reject]` (blind) DW-21 undermines AC3 evidence. — Both recorded bench lines come from `--verbose` runs, and the Auto Run Result names them. DW-21 tracks the flush race.
  - `[low]` `[reject]` (blind) LaserBolt skips missing nodes silently, and RenderGlow doesn't warn on missing keys. — carried: the tests catch renames, and Config already errors on missing keys.
  - `[low]` `[reject]` (blind) `test_glow_energy_is_hdr` duplicates the `test_config` asserts. — carried: harmless duplicate.
  - `[low]` `[reject]` (blind) `sandbox.gd` lacks a scene-root doc comment, and the Spec Change Log is empty. — No bad_spec loopback happened, so the change log stays empty. The helper's doc already states the contract, and a comment adds nothing users would meet.
  - `[low]` `[reject]` (edge) A missing or zero `glow_energy` makes the bolt invisible. — carried: only bad data reaches it, and the fix adds a guard.
  - `[low]` `[reject]` (edge) An `hdr_threshold` of 0 makes the whole screen bloom. — carried: same as above.
  - `[low]` `[reject]` (edge) The shared Environment in the F5 test. — carried.
  - `[low]` `[patch]` (edge, claim) The out-of-scope ring retune ships under Story 1.9. — Same root cause as the blind finding: committed separately as Story 1.8 operator tuning.
  - `[low]` `[patch]` (edge, deletion) The first-pass pin was removed, with the values unrecorded and the assert redundant. — Same root causes: the separate 1.8 commit records 16/4, and the raw-config assertion replaces the redundant one.
  - `[low]` `[patch]` (verification-gap, other) The out-of-scope ring retune and a redundant radius assertion. — Same as the blind findings, same patches.
  - `[low]` `[reject]` (intent) Rendered look (R2) is not exercised by tests. — carried: an operator action.
  - `[false]` `[reject]` (intent) Effective halo brightness depends on `.tscn` alpha (R3b). — carried: the I/O matrix fixes R3(a), the self_modulate multiplier.
  - `[low]` `[reject]` (intent) The F5 test doesn't run `Config.reload()` + `restart_scene` (R4b). — carried: covered by test_debug_tools.
  - `[low]` `[reject]` (intent) Intensity 0 alone doesn't fully disable glow (R5). — carried: the operator action sets intensity and bloom.
  - `[low]` `[reject]` (intent) The missing-key path is untested here. — carried: Config's generic missing-key tests cover it.
  - `[low]` `[reject]` (intent) The baseline-brightness test is stricter than the intent. — carried: dimming is a design change that should update the test.
  - `[low]` `[patch]` (intent) Story 1.8 closure changes appear in the diff. — The spec-1-8 and operator-JSON edits are the orchestrator's `ba92fa1`; the ring retune and test are patched as above.

## Design Notes

- **Why self_modulate:** the twin's gradient is white at the centre, cyan at the rim; multiplying by 2.5 makes the centre (2.5, 2.5, 2.5) and the rim about (0.33, 2.25, 2.5): far above the 0.55 threshold, so it blooms, and still cyan. `self_modulate` (not `modulate`) keeps the halo child's brightness independent.
- **Why a helper, not sandbox code:** the architecture says the scene root applies `render.glow`; every level root (Epic 4) will need the same three lines, so one static call keeps them identical.
- **Human-only checks:** whether the bolts read as bullets and the screen is "slightly brighter, not washed out" is judged on an exported build by the developer (operator action), not by tests.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0 (class cache for the new `RenderGlow`).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failures.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --path game -- --bench=20` -- expected: `Stress bench:` line with `enemies=40`, p99 < 16.6 ms.
- `grep -n "glow_intensity\|glow_bloom\|glow_hdr_threshold" game/scenes/sandbox/sandbox.tscn` -- expected: no matches.

## Auto Run Result

Status: awaiting-operator

**Summary:** The WorldEnvironment glow intensity, bloom and HDR threshold now come from `tuning.json → render.glow`. The values are 1.0 / 0.08 / 0.55, up from the hard-coded 0.8 / 0.05 / 0.6. `RenderGlow.apply()` applies them from the sandbox root's `_ready()`, so an F5 restart picks them up. Each laser twin is now an HDR core (`self_modulate` = `weapons.laser.glow_energy`, 2.5) with a wider additive `Halo` behind it (`weapons.laser.halo_energy`, 1.0). Decision-log row 32 records the provisional #30 tuning note. The story code is in commit `8a8ad7f`.

**Verification repair (this run):**
- The deterministic verify failed on one test: `test_missile_ring.gd::test_radius_and_stroke_from_config` pinned the Story 1.8 first pass (36/5), but the operator had tuned `player.missile_ring` to 16/4 during the 1.8 check.
- The operator's values are kept. The test now asserts the UX rules instead: a visible stroke, and the raw tuned radius at or below half the ship.
- Both files are committed separately as Story 1.8 operator tuning, not under Story 1.9.
- No Story 1.9 code changed.

**Files changed (story):**
- `game/core/render_glow.gd` (+ `.uid`): new static helper that applies `render.glow` to an Environment.
- `game/scenes/sandbox/sandbox.gd` / `sandbox.tscn`: the scene root applies the glow; the three hard-coded values are removed.
- `game/entities/projectiles/laser_bolt.gd` / `laser_bolt.tscn`: HDR core tint, plus additive `Halo` sprites (24×56) behind each twin.
- `game/data/tuning.json`: `render.glow` added, and `weapons.laser.glow_energy` / `halo_energy` added.
- Tests: new `test_render_glow.gd` and `test_laser_bolt_glow.gd`; `test_config.gd` and `test_sandbox.gd` extended.
- `decision-log.md`: row 32 (provisional #30 tuning note, with bench result and baseline).
- `deferred-work.md`: DW-21 (bench log line sometimes missing).

**Review:**
- First pass: 25 findings, 2 low patched, 1 deferred, the rest rejected.
- Repair pass: 24 findings. 2 low root causes patched: the separate 1.8 tuning commit, and the raw-config radius assertion. Nothing new was deferred. Every rejection is in the triage log with its reason.

**Follow-up review recommended:** false. Only low entries were patched (repair pass: 0 high, 0 medium, 2 low entries).

**Verification:**
- `--import` exits 0.
- GUT headless: 326 tests, 326 passing, 1860 asserts, 0 failures.
- The `sandbox.tscn` glow grep finds no matches.
- Bench (implementer, `--path game --verbose -- --bench=20`, windowed, dev laptop iGPU):
  - `Stress bench: frames=4489 avg=4.46 ms p99=7.10 ms max=9.55 ms enemies=40 renderer=forward_plus window=(1920, 1080) vsync=0 result=PASS`
  - A repeat run: `frames=4705 avg=4.25 ms p99=6.31 ms max=7.86 ms ... result=PASS`.
  - Baseline before the glow change (decision #27): p99 7.01 ms.
  - The bench was not re-run in the repair pass, because the Story 1.9 code did not change.

**Residual risks:**
- The look on an exported build (bolts read as bullets, slightly brighter but not washed out) and the glow-off fallback are not verified. See `operator_actions`.
- DW-21: the final `Stress bench:` line is sometimes lost before quit.

## Operator Confirmation

Confirmed 2026-10-07: the external actions this story owed were carried out.

- Export the build (`<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe --headless --path game --import`, then `--headless --path game --export-release "Windows Desktop" export/windows/DEFECTOR.exe`), copy it outside the repo, run it, fire the laser and confirm the bolts read as bullets and the neon is slightly brighter than before but not washed out.
- If the look needs tuning, edit `render.glow` (intensity / bloom / hdr_threshold) and `weapons.laser.glow_energy` / `halo_energy` in game/data/tuning.json (F5 reloads in a debug run), then re-export and re-check.
- Check the ADR-003 fallback: set `render.glow.intensity` and `render.glow.bloom` to 0 (F5) and confirm the additive halo alone still makes the bolts read as bullets; restore the values afterwards.
- Record the final values in decision-log row 32 (the #30 tuning note) and change its status from "Applied (provisional)" to applied/confirmed.

_Appended by the bmad-loop orchestrator (`bmad-loop confirm`, #335): a human confirmed these external actions out of band, and the story was advanced from `awaiting-operator` to `done`._
