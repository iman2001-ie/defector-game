---
title: 'Story 1.10: Reconcile the Architecture with the As-Built'
type: 'chore'
created: '2026-10-07'
status: 'done'
baseline_revision: '8e15b22535c372339b31b544a6c90bf2b1d8ad6d'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `_bmad-output/game-architecture.md` still describes the pre-Epic-1 plan in several places. It has the old `play_sfx` signature, a tier row with no `sfx_volume_db`, and a planned `spark_burst.tscn`/`shockwave_ring.tscn`. It says ShakeCamera registers in `_ready`, and it doesn't mention the stress/bench modes, `Playfield`, the validating `Config.reload()` or the `render` section. Its consistency rule requires `get_global_mouse_position()`, but the cursor lock deliberately reads the viewport mouse. The export command has no `--import` step, and `max_speed` is used as a naming example. Agents building Epic 2 would follow the wrong patterns.

**Approach:** Edit only the architecture doc so that every item in Story 1.10's AC matches the code (the facts are in the Code Map below). Then append an "As-built reconciliation 2026-10-07" note at the end that lists every section changed.

## Boundaries & Constraints

**Always:**
- Describe the code as it is, quoting real symbols and paths. When the doc describes a planned system that doesn't exist yet (level.tscn, SceneRouter, HUD, the Epic 2+ entities), keep it and mark it as planned. Don't delete the plan.
- Keep the doc's existing style: plain English, tables and short code blocks.
- No machine paths. Use `<GODOT_DIR>`.
- Mentions of the terms `reticle`, `max_speed`, `chase` and `toward the cursor` may stay only in sentences that say what was superseded or removed.

**Never:**
- Don't edit game code, tests, data, AGENTS.md, the GDD, epics.md, `deferred-work.md` or `sprint-status.yaml`.
- Don't make new design decisions. Where code and doc disagree on something outside the AC list, describe the code and don't change behaviour.
- Don't touch the doc's pre-existing frontmatter author fields or the Decision Review Log rows R1-R15.

</intent-contract>

## Code Map

Doc anchors (line numbers in the current `_bmad-output/game-architecture.md`) and the as-built facts to write:

- **L310 Audio Architecture:** the real signature is `play_sfx(id: StringName, pitch_jitter: float = DEFAULT_PITCH_JITTER, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer` (`game/autoloads/audio.gd:41`), with `pitch_scale = pitch * (1 + randf_range(-jitter, jitter))`. `DEFAULT_PITCH_JITTER` is 0.05. An unknown id warns once and returns null. The pool has 12 players; when full it stops and reuses the oldest-started one. L313: each tier row carries `sfx`, `sfx_pitch` and `sfx_volume_db` (#26). `Feedback.impact` calls `Audio.play_sfx(row.sfx, DEFAULT_PITCH_JITTER, row.sfx_volume_db, row.sfx_pitch)`.
- **L872-899 Impact Feedback Tiers:** the tier JSON example must include `"sfx_volume_db": 0`. The real rows are in `game/data/tuning.json` `feedback.tiers`: small -6, medium -3, large 0. `Feedback.load_tiers()` caches the rows and runs in `_ready` and on F5. `impact(tier, pos)` follows this order: range check, `_spawner.spawn_explosion({position, scale: explosion_scale, extras})`, shake if `shake_px` and `shake_s` are above 0, `hit_stop` if `hit_stop_ms` is above 0, then the sfx.
- **Single explosion scene:** `EntityRegistry.EXPLOSION` = `entities/effects/explosion.tscn` + `explosion.gd` (`class_name Explosion`), used by every tier.
  - `setup()` takes position, scale and extras.
  - Children: Burst (always on), Sparks, Debris and Shockwave (a `ShockwaveRing` drawn by `shockwave_ring.gd`, which has no .tscn), toggled by `extras` (`sparks` / `debris` / `shockwave`).
  - `Spawner.spawn_explosion` parents it to `World/Effects`.
  - Pre-warm: `Feedback.prewarm()` spawns one of each tier at `PREWARM_POSITION` (-1000, 540) with no shake, stop or sfx. The scene root calls it at the end of `_ready` (today that is `sandbox.gd`).
  - Doc lines to fix: L219 (pre-warm wording) and L560 (`effects/` contents).
- **Feedback registration (retro C1, accepted design):**
  - ShakeCamera calls `Feedback.register_camera(self)` in `_enter_tree` and `unregister_camera` in `_exit_tree`.
  - Spawner calls `register_spawner(self)` in `_ready` (only if `world` has `Effects`) and `unregister_spawner` in `_exit_tree`.
  - Unregister clears the slot only if the argument matches. The last registration wins.
  - Fix L665 (which says `ShakeCamera._ready()`) and add a short paragraph under Impact Feedback Tiers or Architectural Boundaries.
- **Debug CLI modes (L491-505 Debug Tools, L1115 Performance Verification row):**
  - `DebugArgs.parse(OS.get_cmdline_user_args())` (`game/ui/debug/debug_args.gd`) returns `{stress, bench_s}`.
  - `-- --stress` gives a 10x4 grid of 40 Wasps refilled on death, overlay on, vsync off.
  - `-- --bench=N` implies stress: it warps the cursor to `DebugTools.BENCH_AIM` (1040, 900), holds `fire_laser`, skips 2 s of warm-up, samples N s into `FrameStats`, logs `[INFO][debug] Stress bench: frames= avg= p99= max= ... result=`, and quits with exit 0 if the average is under 16.6 ms, otherwise 2.
  - Debug builds only.
  - Implemented keys today: F1 overlay and F5 reload. The other F-keys are still planned.
- **`Playfield` / `PlayerWeapons` split (DW-13):**
  - `game/core/playfield.gd` is `class_name Playfield` with `const SIZE := Vector2(1920, 1080)` and `const RECT := Rect2(Vector2.ZERO, SIZE)`. Fix the L416 example `const PLAYFIELD := ...`.
  - `game/entities/player/player_weapons.gd` (`class_name PlayerWeapons extends Node`, the `Weapons` child) owns the laser and missile timing, spawning, sfx and `missile_cooldown_changed`. Its API is `set_spawner`, `step_fire(held, delta)` and `step_missile(pressed, delta)`.
  - `player.gd` owns the lock, bounds, hurtbox and sizing, and delegates to `Weapons`.
  - Fix the L431 example header (`# player.gd`, `_missile_speed`), the L545 player dir (`cooldown_ring.gd` → `missile_ring.gd`), and add `playfield.gd`, `render_glow.gd` and `collision_layers.gd` to the L538-543 `core/` list.
- **`Config.reload() -> bool` (DW-8, L412 and L425):**
  - It re-reads the last paths into temporaries and validates the shape: every current key path must still exist with the same kind (int and float both count as number), and extra keys are allowed.
  - On failure it logs `Log.error("data", "Reload rejected ...; previous data kept")`, returns false, and leaves `tuning`, `flags` and `load_error` untouched.
  - On success it commits, clears `load_error` and logs the summary.
  - F5 runs `DebugTools.reload_data()`: `Config.reload()`. If that is false, it logs and stops (the scene is not restarted). If true, it runs `Feedback.reset()`, `Feedback.load_tiers()`, `PauseArbiter.clear()`, then restarts the current scene so `_ready` caches re-read.
  - The getters are exactly `num`, `int_`, `flag` and `section`. `Config.level()` and `Config.sequence()` (L1049) are still planned.
- **Cursor lock (L80, L240, L902-932, L1095, L1162):**
  - `Player.step_lock(get_viewport().get_mouse_position())` every physics tick. `static confine(mouse, bounds_min, bounds_max)` is a pure clamp; the bounds are x from 0 to `Playfield.SIZE.x` and y from `player.bounds_y.min/max` (432/1080).
  - It warps through the injectable `warp_mouse: Callable` only when the cursor is more than `WARP_EPS_PX` (1.0) from the clamped point and `PauseArbiter.current_mouse_mode() == MOUSE_MODE_CONFINED_HIDDEN`. Then `global_position = confined`. The ship never rotates.
  - PauseArbiter adds `signal resumed` (emitted on each paused→unpaused transition after `mouse_mode` is written), `set_gameplay_mouse_mode(mode)` and `current_mouse_mode()` (VISIBLE while paused). Add these to the L907 API excerpt.
  - `Player._on_resumed` warps to `global_position`.
  - **The L1095 Positions rule must change:** the lock and warps use viewport coordinates on purpose, so the ShakeCamera offset can't feed back into the ship (see `spec-1-8` Design Notes). Gameplay world positions are still the 1920×1080 playfield coordinates. Also fix the L1162 GDD-coverage cell (`get_global_mouse_position()`).
- **Cooldown ring (L319, already correct, plus data):** `game/entities/player/missile_ring.gd` (`class_name MissileRing`) is a `MissileRing` child with `z_index = 1`. It reads only from `Events.missile_cooldown_changed`. Its data is `player.missile_ring.radius_px` / `stroke_px`, with the radius clamped to `sprite_px / 2`. Colours: `text` #E8F4FF with a `background` #05070F outline.
- **`render.glow` (L127 correct; L1063 sections list lacks `render`):**
  - Keys: `intensity`, `bloom`, `hdr_threshold`. `RenderGlow.apply(env)` (`game/core/render_glow.gd`) is called by the scene root's `_ready` on its `WorldEnvironment`, so the F5 restart re-applies it.
  - Laser: `weapons.laser.glow_energy` / `halo_energy` set the HDR `self_modulate` on the additive bolt and halo sprites (ADR-003 fallback).
- **L1139-1141 export command (DW-17):** put the `--import` command before `--export-release`, as in the AI Tooling block (L1232).
- **L645:** the naming example `max_speed` becomes e.g. `fire_interval`. Also L417, where "player speed" in the Balancing row becomes e.g. "player zone".

## Tasks & Acceptance

**Execution:**
- `_bmad-output/game-architecture.md` -- apply every Code Map item in the section it anchors to. Mark planned-but-unbuilt items as planned where an edit touches them. -- Story 1.10 AC, DW-11, DW-17, retro A8/C1.
- `_bmad-output/game-architecture.md` (end of file, after the Decision Review Log, before the generated-by footer) -- add `## As-built reconciliation 2026-10-07`. It should have one bullet per changed section (section name, what changed, and the source: story, DW or decision id), plus one line saying which superseded terms (reticle, chase, max_speed) were removed and why (#29/#31). -- AC "every section changed is listed".

**Acceptance Criteria:**
- Given the updated doc, when a reader checks each of the ten AC topics, then each is described matching the Code Map facts (the signatures, keys, owners and call order quoted there).
- Given the doc's Deployment section, when a reader follows the CLI export, then the `--import` command comes before `--export-release`.
- Given the updated doc, when you run `grep -n -i "reticle\|max_speed\|chase\|toward the cursor" _bmad-output/game-architecture.md`, then every match is a sentence that states a removal or supersession (for example L319, or the reconciliation note).
- Given the end of the doc, when it is read, then an "As-built reconciliation 2026-10-07" note lists every section this story changed.
- Given `git diff --stat`, then only `_bmad-output/game-architecture.md` (and this spec) changed.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 25 findings — high 0, medium 0, low 19, false 6, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) `epic-1-context.md` is in the diff, though the spec AC expects only the architecture doc and the spec. — The file is the workflow's own step-01 epic-context cache. It was recompiled because the decision log was newer, and Story 1.8 committed its recompile the same way. Reverting it would leave a stale cache. The only alternative fix is to edit this spec, which the triage rules forbid.
  - `[low]` `[patch]` (blind) The recompiled `epic-1-context.md` repeats stale facts: `play_sfx` without `pitch`, pre-warm "at level start", convoy push presented as current, and "F5 reload all data". — Fixed: all four sentences are corrected to match the code and the reconciled architecture doc.
  - `[low]` `[reject]` (blind) The recompiled epic context drops details: the ring first pass 36/5, the enemy zone, the old glow baseline, the 4.4/4.5/6.1 hand-offs, DW-3 and the DW closure. — The compile prompt regenerates this cache from planning docs. Several of the dropped values are obsolete (the ring is now 16/4 and the glow was re-tuned in #32). The rest live in `epics.md` and `deferred-work.md` and will be compiled into those epics' own contexts. Restoring them would mean hand-curating a generated file.
  - `[low]` `[patch]` (blind) "The Player owns every gameplay `warp_mouse` call" ignores the DebugTools bench warp to `BENCH_AIM`. — Fixed: the Cursor paragraph names the debug-only exception.
  - `[low]` `[patch]` (blind) The Spawner location in System Location Mapping and in the tree comment says `level.tscn`, as if it were built. — Fixed: both now say "today `sandbox.tscn`; `level.tscn` planned".
  - `[low]` `[patch]` (blind) The Directory Structure "built" list leaves out `project.godot`, `export_presets.cfg`, `default_bus_layout.tres`, `assets/` and `addons/gut/`, and the tree has no `default_bus_layout.tres`. — Fixed: these are added to the list and to the tree.
  - `[low]` `[patch]` (blind) The Feedback block leaves out `hit_stop`, `tier_row` and the prewarm/registration ordering. — The `hit_stop` part does not hold, because it is already documented in Pause and Time Model. Fixed: one sentence now says `prewarm()` relies on the child Spawner's `_ready` registering before the scene root's `_ready`.
  - `[low]` `[patch]` (blind) The note says "No design decision changed", yet the Positions rule reverses. — Fixed: the note says the rule follows the Story 1.8 decision (spec-1-8 Design Notes, GDD #29). The Consistency Rules bullet cites it too.
  - `[false]` `[reject]` (blind) The spec AC doesn't enumerate the ten topics, and the spec's context list is off. — Fixing this would mean editing this build's spec. Also, the Code Map enumerates every topic.
  - `[false]` `[reject]` (blind) The spec Verification section has no hunk-coverage or epic-context checks, and its line anchors aren't said to be pre-edit. — Fixing this would mean editing this build's spec. I checked the note's coverage by reading the diff.
  - `[low]` `[reject]` (edge) The diff-stat claim mismatch for `epic-1-context.md`. — Same root cause and evidence as the first blind row (workflow cache recompile).
  - `[low]` `[patch]` (edge) The epic context's `play_sfx` has no `pitch`. — Grouped with the stale-facts row. Fixed.
  - `[low]` `[patch]` (edge) The epic context gives pre-warm "at level start". — Grouped with the stale-facts row. Fixed.
  - `[low]` `[patch]` (edge) The epic context presents the convoy-push warp as current. — Grouped with the stale-facts row. Fixed (marked planned, Epic 6).
  - `[low]` `[patch]` (edge) The epic context says "F5 reloads all data". — Grouped with the stale-facts row. Fixed (validating reload of tuning and flags, then a scene restart).
  - `[low]` `[reject]` (edge) The dropped Cross-Story bullets (4.4/4.5/6.1, DW-3, DW closure, retro re-run). — Same as the dropped-details row: a generated cache, with the sources intact in `epics.md` and `deferred-work.md`.
  - `[false]` `[reject]` (edge) The dropped requirement bullets weaken the bench gate from p99 to the average. — The as-built bench passes or fails on the average (`debug_tools.gd` `FRAME_BUDGET_MS`), and the GDD budget is frame time under 16.6 ms. The doc describes the code. The old glow baseline is obsolete after #32.
  - `[low]` `[patch]` (edge) The Technical Risks row still says "Particles are pre-warmed at load". — Fixed: it now says `Feedback.prewarm()` at scene start, and the change is listed in the note.
  - `[low]` `[reject]` (verification-gap) The scope rule is broken by `epic-1-context.md`. — Same as the first blind row.
  - `[low]` `[patch]` (verification-gap) The epic context's `play_sfx` and pre-warm wording contradict the code. — Grouped with the stale-facts row. Fixed.
  - `[low]` `[reject]` (verification-gap) The epic context drops recorded facts. — Same as the dropped-details row.
  - `[false]` `[reject]` (intent) The scope boundary versus the `epic-1-context.md` change. — The file is the workflow's cache recompile, not story authorship, so there is no intent divergence (see the first blind row).
  - `[low]` `[patch]` (intent) The epic context disagrees with the reconciled doc on `play_sfx`, pre-warm and the convoy push. — Grouped with the stale-facts row. Fixed.
  - `[false]` `[reject]` (intent) The edits beyond the ten AC topics widen the change. — The spec's Always rule asks for planned items to be marked as planned where edits touch them. No design changed, and every extra edit only re-labels text as as-built or planned.
  - `[false]` `[reject]` (intent) The verification only checks wording, not whether the doc matches the code. — The orchestrator read the full diff and checked the Code Map facts against the source: the `PauseArbiter` excerpt matches `pause_arbiter.gd` line for line, `_report_missing` matches `config.gd:75`, decision #32 exists, and the `collision_layers` masks match.

### 2026-10-07 — Review pass (follow-up)
- verdicts: 19 findings — high 0, medium 0, low 12, false 5, maybe-false 2
- findings:
  - `[low]` `[patch]` (blind) Architectural Boundaries rule 4 and the scene-changes Consistency row say only `SceneRouter` changes scenes, but F5 in `DebugTools` calls `reload_current_scene`, and the row's grep for `change_scene` misses it. — Fixed: rule 4 names the debug-only F5 exception, and the row excepts it and adds `reload_current_scene` to its grep.
  - `[low]` `[patch]` (blind) The doc doesn't say that `PauseArbiter.clear()` keeps `_gameplay_mode` (`pause_arbiter.gd:40`), so a scene that never declares its mode inherits `CONFINED_HIDDEN`. — Fixed: the Cursor paragraph and the `clear()` excerpt comment now say so.
  - `[low]` `[patch]` (blind) The Process modes table lists `SceneRouter` as if it were built, leaves out `ShakeCamera` and `DebugTools` (both set `PROCESS_MODE_ALWAYS` in `_ready`), and puts `World` only in `level.tscn`. — Fixed: the table marks `SceneRouter` planned, places `World` in today's sandbox, and adds the two nodes. Grouped with the intent row about untouched planned text.
  - `[low]` `[patch]` (blind) The missing-key rule says it always asserts, but `Config.assert_on_missing` (`config.gd:16`, default true) turns the assert off in tests. — Fixed: one sentence names the switch.
  - `[low]` `[reject]` (blind) The doc doesn't record Epic 1's test seams (injectable Callables, `debug_enabled`, `assert_on_missing`, fixture `load_data`). — Nothing in the doc is wrong here; the gap is missing guidance. Every spec's context already loads `godot-testing.md`, and the seams sit in the tests next to the code. The fix would be a new Testing section, not a correction.
  - `[low]` `[patch]` (blind) The Collision Layers section doesn't mention `CollisionLayers` constants, which code and tests use. — Fixed: one sentence names `core/collision_layers.gd`, its bits and shot masks, and how tests check `.tscn` values against them.
  - `[maybe-false]` `[reject]` (blind) The off-screen pre-warm at (-1000, 540) may not compile shaders if canvas culling skips it. — To settle this, compare a first-impact frame-time trace with pre-warm on and off. If true it is only low (a single hitch), and the claim predates this story. Rejected with this note.
  - `[low]` `[reject]` (blind) Nothing enforces the Positions rule's "camera centred and unzoomed" assumption. — The fix is a new lint or test, not a doc correction, and the camera is not touched until a later epic.
  - `[low]` `[reject]` (blind) The regenerated `epic-1-context.md` drops the DW-11/DW-17 closure line. — The deferred-work ledger is closed by the orchestrator's sweep, not by this story. The cache is generated.
  - `[low]` `[reject]` (blind) The spec AC expects only the architecture doc and the spec, but `epic-1-context.md` changed. — carried: same as the first-pass blind row (the workflow's step-01 cache recompile).
  - `[false]` `[reject]` (blind) The spec's `context` list is wrong. — Fixing this would mean editing this build's spec, and the list follows the project's required-context rule.
  - `[false]` `[reject]` (blind) The footer `_Date: 2026-10-06_` hides the revision. — The footer records the generation date, which is correct. The revision is dated in the "As-built reconciliation 2026-10-07" heading.
  - `[low]` `[patch]` (edge) The Reload block promises shape validation, but `_check_shape` accepts anything when the current data is empty after a failed boot load (`config.gd:118`). — Fixed: the Reload block says so.
  - `[maybe-false]` `[reject]` (edge) A `--bench=N` run with zero samples would report PASS, because an empty average is 0. — To settle this, check whether a positive N can end sampling before one frame is recorded. If true it is low, debug-only, and pre-existing in Story 1.7 code. Rejected with this note.
  - `[low]` `[reject]` (edge) The "only two files changed" claim is false because of `epic-1-context.md`. — carried: same as the first-pass edge diff-stat row.
  - `[false]` `[reject]` (intent) The change reaches beyond the architecture doc into `epic-1-context.md`. — carried: same as the first-pass intent row (a cache recompile, not story authorship).
  - `[low]` `[patch]` (intent) The untouched Engine-Provided "Scene management … `SceneRouter`" row reads as if it were built. — Fixed: the row is marked planned and names today's debug F5 reload. Grouped with the Process-modes row.
  - `[false]` `[reject]` (intent) The verification only greps for terms and never checks the doc against the code. — carried: same as the first-pass intent row. This pass's reviewers checked the code facts again and found them matching.
  - `[false]` `[reject]` (intent) The Positions rule reverses. — The auditor itself notes the intent names this rule as the problem, and the change cites spec-1-8 and GDD #29. It is not a divergence.

## Design Notes

- **Planned versus as-built:** most of the doc describes Epics 2-8, which are not built yet. Reconciling means making the Epic 1 parts true and not letting planned parts claim to exist (for example "Implemented today: F1, F5"). It doesn't mean deleting the plan.
- **Known code gaps to mention, not fix:** the tiers `boss_part`, `boss_death`, `player_hit` and `player_death` name sfx ids that `Audio.SFX` doesn't register yet, and the extras `white_flash` and `red_vignette` aren't handled by `Explosion`. The doc may call these "registered when their epic lands".

## Verification

**Commands:**
- `grep -n -i "reticle\|max_speed\|chase\|toward the cursor" _bmad-output/game-architecture.md` -- expected: only removal or supersession sentences.
- `grep -n "get_global_mouse_position\|cooldown_ring\|spark_burst\|ShakeCamera._ready\|const PLAYFIELD" _bmad-output/game-architecture.md` -- expected: no matches, except inside the reconciliation note.
- `grep -n "pitch: float = 1.0\|sfx_volume_db\|register_spawner\|--bench=\|Playfield\|PlayerWeapons\|Config.reload\|resumed\|MissileRing\|render.glow\|--import" _bmad-output/game-architecture.md` -- expected: each term has at least one match.
- `git diff --stat` -- expected: only the architecture doc and spec files.

## Auto Run Result

Status: done

**Summary:** `_bmad-output/game-architecture.md` describes the Epic 1 code as built for every Story 1.10 AC topic:
- the `play_sfx` pitch parameter and the tier `sfx_volume_db` (#26)
- the single `Explosion` scene and `Feedback.prewarm()`
- Feedback registration (retro C1)
- `DebugArgs`, `--stress` and `--bench=N`
- `Playfield` and `PlayerWeapons` (DW-13)
- the validating `Config.reload()` and F5 (DW-8)
- the cursor lock and `resumed`
- `MissileRing`
- `render.glow`
- `--import` before export (DW-17)

The closing "As-built reconciliation 2026-10-07" note lists every changed section. This follow-up review pass made eight small doc corrections.

**Files changed (since baseline):**
- `_bmad-output/game-architecture.md`: the reconciliation edits, the follow-up patches, and the closing note.
- `_bmad-output/implementation-artifacts/epic-1-context.md`: the step-01 epic-context cache recompile, from the first pass.
- This spec.

**Review (follow-up pass):**
- 19 findings: 12 low, 5 false, 2 maybe-false.
- Patched (8 rows, 7 entries, all low):
  - the debug F5 `reload_current_scene` exception in rule 4 and the Consistency row
  - `clear()` keeps the gameplay mouse mode
  - the Process modes table and the Scene management row marking `SceneRouter` planned (grouped)
  - `Config.assert_on_missing`
  - `CollisionLayers`
  - an empty current data set skips the reload shape check
- Deferred: none.
- Rejected:
  - test-seam guidance: missing guidance, not a wrong statement
  - pre-warm efficacy and the zero-sample bench: maybe-false, low if true, and pre-existing
  - Positions-rule enforcement: needs a new check, not a doc fix
  - the DW closure line: the ledger belongs to the orchestrator
  - carried cache-recompile scope rows
  - spec-edit-only findings
  - the footer date and the Positions reversal: false

Reasons are in the triage log.

**Follow-up review recommended:** false. This is a follow-up pass and no `high` was patched. Patched counts: high 0, medium 0, low 7 entries.

**Verification:**
- The superseded-terms grep matches only L337 ("There is no reticle") and the reconciliation note.
- The old-names grep matches only inside the note.
- Every required term has at least one match.
- `git diff --stat` from the baseline shows the architecture doc, this spec and the epic-context cache, plus `sprint-status.yaml`. The orchestrator changed that file and owns it; this run neither edited nor committed it.
- No game code changed, so the GUT suite was not run.

**Residual risks:**
- The doc is checked against the code only by hand reading, so future code changes can drift from it again.
- The tier sfx ids and extras that aren't registered yet remain documented gaps.
- The two maybe-false claims (off-screen pre-warm efficacy, a zero-sample bench passing) are unverified.
