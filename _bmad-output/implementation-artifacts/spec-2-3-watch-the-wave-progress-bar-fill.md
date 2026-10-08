---
title: 'Story 2.3: Watch the Wave Progress Bar Fill'
type: 'feature'
created: '2026-10-07'
baseline_revision: '07bcc62dec2e4ad87813a1c84037715a73e62f40'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-2-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/EXPERIENCE.md'
warnings: ['oversized']
deferred:
  - summary: >-
      test_f3_resolves_the_wave_and_fires_pending_triggers_in_order fails deterministically in this environment ("the skipped group never spawns", expected 0 got 1).
    evidence: |-
      Pre-existing (Story 2.2 test, untouched by 2.3): it fails 5/5 in isolation on HEAD and 2/2 at baseline 07bcc62 in a clean worktree. The test sets waves.gap_s = 0.05, then awaits 2 process frames and asserts no counted enemies; the log shows wave 2/2 (1 wasp) already started before the assert, so the 0.05 s gap elapses within those 2 headless frames. The earlier 2.3 pass saw it green, so it depends on frame timing.
    location: >-
      game/tests/unit/test_wave_director.gd:347
    severity: medium
---

<intent-contract>

## Intent

**Problem:** The level runs data-driven waves (Story 2.2), but the player can't see how far through a wave or the level they are. The HUD has only the placeholder LEVEL CLEAR banner, and the shared UI `Theme` the architecture and UX spec require (`ui/theme/defector_theme.tres`) doesn't exist yet.

**Approach:** Add `ui/hud/wave_bar.gd` (`class_name WaveBar`, a `Control`) to the level's HUD `CanvasLayer`. It draws one segment per wave at the top centre (UX-DR1/DR2: x 680, y 40, 560 × 20, 4 px gaps). It is driven only by `Events.level_started`/`wave_started`/`wave_progress_changed`/`wave_cleared`, and it fills the current segment with a 0.2 s pausable tween that never goes backwards. Between waves it highlights the next segment. Create `defector_theme.tres` holding the bar's styles (UX Cold Neon colours), and put the layout and tween numbers in `tuning.json` under `hud.wave_bar`.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript. The bar's state changes only in `Events` signal handlers. It never reads `WaveDirector`, groups, the scene tree or any gameplay node, and it has no `_process`/`_physics_process`. It redraws (`queue_redraw`) only when a value changes.
- `process_mode = PROCESS_MODE_PAUSABLE` on the bar. Tweens come from the bar's own `create_tween()` (bound to the node), so they freeze with the game.
- Colours, border width and corner radius come only from the theme (`get_theme_stylebox(&"track"|&"fill"|&"highlight", &"WaveBar")`, `get_theme_constant(&"separation", &"WaveBar")`). The bar sets no `theme_override_*`. The `.tres` uses the UX tokens: track `heartEmpty` #2B3348 with a 1 px `border` #2A3B5C outline; fill `coalition` #22E6FF; highlight = the track with a 1 px `coalition` outline; corners 2 px; separation 4.
- Geometry and timing come from `Config` (`hud.wave_bar.x/y/width/height/fill_tween_s`), read once in `_ready` like `MissileRing`.
- Displayed fills are monotonic within an attempt: a fill only ever moves up, and only `level_started` resets the bar.

**Never:**
- No boss bar or cross-fade (Epic 7). No glow on the bar, no font, and no restyle of `LevelClearBanner` (later UI stories). No changes to `WaveDirector`, `Events` signatures or `sprint-status.yaml`. No per-frame logging.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Level start | `level_started`, then `wave_started(0, 3)` | 3 segments, all empty; current = 0; no highlight | — |
| Progress | `wave_progress_changed(0, 0.5)` | segment 0's target is 0.5, and it reaches 0.5 after `fill_tween_s` | — |
| Lower ratio | `(0, 0.5)`, then `(0, 0.25)` | stays at 0.5 | ignored |
| Wave clear + gap | `wave_cleared(0)` with 3 segments | segment 0 tweens to 1.0; segment 1 highlighted | — |
| Next wave | `wave_started(1, 3)` | segment 0 snaps to 1.0 if its tween is still running; highlight off; current = 1 | — |
| Skipped waves (F6) | `wave_started(2, 3)` from wave 0 | segments 0 and 1 full | — |
| Last wave clear | `wave_cleared(2)` with 3 segments | segment 2 full; nothing highlighted | — |
| Stale / bad index | `wave_progress_changed(0, x)` while current = 1, or an index ≥ count or < 0 | ignored | no crash |
| Ratio out of range | ratio 1.7 or -0.2 | clamped to 0–1 | — |
| Count change / new attempt | `level_started` | all segments reset to empty, no highlight; the next `wave_started` sets the count | — |
| Paused | tree paused mid-tween | the fill freezes and resumes on unpause | — |

</intent-contract>

## Code Map

- `game/ui/hud/level_clear_banner.gd` -- the existing HUD script pattern: connects `Events` in `_ready` and reads nothing else.
- `game/entities/player/missile_ring.gd` -- precedent for a drawn, `Events`-driven visual: `Config.num` in `_ready`, `queue_redraw` in the handler, a `should_draw`-style testable accessor.
- `game/scenes/level/level.tscn` -- `HUD` (CanvasLayer, layer 10) currently holds only `LevelClearBanner`. Add a `WaveBar` Control child (with `theme` = the `.tres` ext_resource) **before** the banner, so the banner draws on top. Bump `load_steps`.
- `game/systems/waves/wave_director.gd` L92-126, L401-430 -- read-only. Wave indices are 0-based. `wave_started(index, count)` fires before any progress emit for that wave. `wave_cleared(index)` is followed by a `waves.gap_s` gap, then `wave_started(index+1)` or `level_cleared`. A total-0 wave emits no progress, only a clear. `debug_skip_to_boss` calls `start_wave(boss_index)` directly.
- `game/scenes/level/level.gd` -- emits `Events.level_started` before `start_level`, so the reset comes before wave 1.
- `game/autoloads/config.gd` L74 `num(path)` -- logs and returns 0.0 for a missing key.
- `game/data/tuning.json` -- top-level keys have no `hud` yet. Add `"hud": { "wave_bar": { "x": 680, "y": 40, "width": 560, "height": 20, "fill_tween_s": 0.2 } }`.
- `game/tests/unit/test_level.gd` -- test style (preload the scene, `add_child_autofree`, `after_each` restores `Config.load_data()`, `PauseArbiter.clear()`, `Log.sink`). `test_tree` checks the root children only, so adding a HUD child doesn't break it.
- `game/tests/unit/test_missile_ring.gd` -- a sibling test for `Events`-driven drawing.
- No `game/ui/theme/` folder exists yet. `*.gd.uid` files are tracked: run `--import` and commit the new ones.

## Tasks & Acceptance

**Execution (write each test first, red, then the code):**
- `game/ui/theme/defector_theme.tres` -- a new `Theme` resource with type `WaveBar`: `StyleBoxFlat` items `track`, `fill` and `highlight`, plus the constant `separation` = 4, per the Always rules -- the shared Theme that UX-DR6 names, seeded with the first HUD component.
- `game/data/tuning.json` -- add the `hud.wave_bar` block above -- the UX layout and the 0.2 s tween are tunable data.
- `game/ui/hud/wave_bar.gd` -- `class_name WaveBar extends Control`, `mouse_filter` ignore. `_ready` applies the rect from Config and connects the four `Events` signals. Public read accessors for tests: `segment_count()`, `current_index()`, `highlighted_index()` (-1 = none), `target_fill(i)`, `displayed_fill(i)`, and a static `segment_rects(count, size, gap) -> Array[Rect2]` (equal widths, `gap` between them, filling `size`). `_draw` draws each segment's track (or highlight) stylebox, then a fill stylebox of width `rect.w * displayed_fill(i)` when it is > 0. Behaviour per the I/O matrix: one tween at a time, which tweens the displayed fill of the segment it animates; a new target on another segment snaps the old one to its target first.
- `game/scenes/level/level.tscn` -- add `HUD/WaveBar` (script, theme, `process_mode = 1` pausable, mouse filter ignore) before `LevelClearBanner`.
- `game/tests/unit/test_wave_bar.gd` -- every I/O matrix row (shorten the tween via `Config.tuning` and restore with `Config.load_data()`; pausing via `get_tree().paused`, restored in `after_each`), `segment_rects` geometry (3 segments in 560 with gap 4 → width 184, x 0/188/376), theme items and colours, the rect from data, and a source scan of `wave_bar.gd` asserting none of `get_tree`, `get_node`, `get_parent`, `$`, `WaveDirector`, `_process`, `theme_override` appears.
- `game/tests/unit/test_level.gd` -- add: `HUD/WaveBar` is a `WaveBar`, pausable, uses `res://ui/theme/defector_theme.tres`, sits at (680, 40) with size 560 × 20, and shows 3 segments for `level_dev` after `_ready`. Within the HUD band: its rect bottom is ≤ 120.
- `_bmad-output/game-architecture.md` -- status only: a short "As-built 2026-10-07 (Story 2.3)" note (`wave_bar.gd` built, theme created with the `WaveBar` type items, `hud.wave_bar` tuning). Also mark it as built in the UI Framework section if that section lists build status.
- Run `--import`, then the full GUT suite.

**Acceptance Criteria:**
- Given the project run normally, when level_dev starts, then `HUD/WaveBar` shows 3 segments at x 680–1240, y 40, inside the top 120 px band, using the shared theme.
- Given enemies dying in the current wave, when `wave_progress_changed` arrives, then the current segment fills to the ratio over `fill_tween_s`, completed segments stay full, and no displayed fill ever decreases before the next `level_started`.
- Given `wave_bar.gd`, when reviewed, then it changes state only through `Events`, never polls gameplay nodes, has no per-frame process, and takes every colour from `defector_theme.tres` and every number from `Config` or the theme.
- Given the headless GUT suite, when it runs, then the new tests pass and every pre-existing test still passes.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 25 findings — high 0, medium 2, low 13, false 10, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: the bar's rect is in both the `level.tscn` offsets and `hud.wave_bar`, so the editor preview can drift from the data — `_ready` always applies the data at runtime, and zeroing the offsets would only lose the editor preview.
  - `[low]` `[reject]` Blind: `test_tuning_matches_ux_layout` and `test_wave_bar_in_the_hud` pin 680/40/560/20, so tuning the bar breaks a test — the pin is deliberate (it ties the data to the UX layout table), and a designer change updates one assertion set.
  - `[low]` `[patch]` Blind: `test_wave_bar_in_the_hud` asserted a literal 3 segments, tied to level_dev's content — fixed: it now compares against `Config.level("dev").waves.size()`.
  - `[low]` `[patch]` Blind: the source scan did not catch hard-coded colours, so the "every colour from the theme" AC was unchecked — fixed: `"Color("` and `"Color."` are banned in `test_source_reads_only_events`.
  - `[low]` `[patch]` Blind: the `fill_tween_s <= 0` instant-fill branch was untested — fixed: `test_zero_tween_fills_instantly`.
  - `[false]` `[reject]` Blind: the segment count goes stale after `level_started` until the next `wave_started` — `level.gd` emits `level_started` and then `start_level` → `start_wave(0)` → `wave_started` in the same call, and `Config.level_at` rejects a level without waves before `level_started`. The wave count is `_waves.size()`, constant within a level, so a shrink can't happen mid-attempt.
  - `[low]` `[reject]` Blind: stale or impossible indices are dropped without a log — the matrix says "ignored", the director never emits them, and a WARN branch adds code for a bug that doesn't exist.
  - `[low]` `[reject]` Blind: rapid kills restart the 0.2 s tween from the current value, so the fill trails a burst — the lag is bounded by `fill_tween_s` after the last kill, which is the specified smoothing; a retarget scheme adds complexity.
  - `[low]` `[reject]` Blind: timing tests could flake under load — the tweens and `wait_seconds` advance on the same SceneTree process delta, so load doesn't skew them; only a single frame longer than the margin (≥ 0.15 s) could fail them, and the suite passed twice.
  - `[false]` `[reject]` Blind: the fill hides the track outline and tiny fills smear — DESIGN.md gives the outline to empty segments ("full segments are `coalition`"), and `StyleBoxFlat` scales its corner radii down to fit a small rect.
  - `[false]` `[reject]` Blind: the diff omits the spec — by design; the spec is the claims file, reviewed separately.
  - `[false]` `[reject]` Edge: a NaN ratio poisons `_target` — `WaveProgress.ratio()` returns 1.0 for a zero total and otherwise divides two ints with total > 0, so the director never emits NaN.
  - `[low]` `[reject]` Edge: `segment_rects` gets negative widths when the gaps exceed the width — that needs more than 140 waves at 560 px with a 4 px gap; no level comes close, and the fix adds a guard.
  - `[false]` `[reject]` Edge: the stale count after `level_started` with no `wave_started` — same refutation as the Blind stale-count row.
  - `[false]` `[reject]` Edge (claim): `wave_started` with a smaller count truncates filled segments mid-attempt — `wave_count` is `_waves.size()`, fixed for the level, so the count only changes across `level_started`.
  - `[low]` `[reject]` Edge (claim): `level_started`/`wave_started` call `queue_redraw` unconditionally — they fire once per wave, never per frame, so the extra redraw isn't worth a branch.
  - `[medium]` `[patch]` Verification gap: `_draw()` was untested; a flipped highlight/track choice, a full-width fill or drawing `_target` instead of `_displayed` would pass — fixed: `_draw` now uses `style_for(index)` and `static fill_rect(rect, shown)`, tested by `test_style_for_highlights_only_the_next_segment` and `test_fill_rect`.
  - `[medium]` `[patch]` Intent: the drawn output is never checked, only state accessors — same root as the verification-gap row; fixed there.
  - `[low]` `[patch]` Intent: no test drives a real WaveDirector clear into the bar — fixed: `test_wave_bar_follows_the_director` in `test_level.gd` calls `debug_resolve_wave()` on the real level and asserts segment 0 full and segment 1 highlighted.
  - `[false]` `[reject]` Intent: no real retry is tested — no retry flow exists yet (Epics 3–4); `level_started` is the reset seam, and it is tested.
  - `[false]` `[reject]` Intent: AC3 is checked by a source scan — the AC is framed "when I review it", and the scan plus the Events-only handler tests cover it.
  - `[low]` `[reject]` Intent: the height is 20 from DESIGN.md while the HTML mockup uses 16 — DESIGN.md (the spine) gives the bar slot "h 20" and says the spine wins over the mockup; the height is one tunable number in `hud.wave_bar`.
  - `[low]` `[reject]` Intent: the highlight style and the new `hud` tuning section are recorded only as status — the highlight fills a detail the UX left open (review-rubric N9 itself suggests a `coalition` border) and is recorded in Design Notes; new top-level sections have precedent (`render` and `debug` were added as-built in the DW-9 sweep).
  - `[false]` `[reject]` Intent: the theme holds only the `WaveBar` items, not the full UX-DR6 palette and font — the AC asks the bar to use the shared theme, which it does; later UI stories add to it.
  - `[false]` `[reject]` Intent: a visual check might be an operator action — the operator clause covers actions outside the repo (domains, DNS, keys); every Story 2.3 AC is in the repo and tested.

### 2026-10-07 — Review pass
- verdicts: 27 findings — high 0, medium 0, low 16, false 11, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: highlight style invented and not in a decision log — carried: the highlight fills a detail the UX left open (rubric N9 suggests a `coalition` border) and is recorded in Design Notes; the theme holds it, so it restyles without code. Glow is excluded by the intent's Never list.
  - `[low]` `[reject]` Blind: `hud` added to the architecture's "(fixed)" tuning section list without a decision — carried: the intent itself asks for `hud.wave_bar` in `tuning.json`; new top-level sections have the `render`/`debug` precedent.
  - `[low]` `[reject]` Blind: bar height 20 vs the mockup's 16 — carried: DESIGN.md (the spine) gives h 20 and wins over the mockup; one tunable number.
  - `[low]` `[reject]` Blind: layout duplicated in `level.tscn` offsets and pinned in tests — carried: `_ready` always applies the data; the offsets keep the editor preview, and the test pin ties the data to the UX table on purpose.
  - `[false]` `[reject]` Blind: `level_started` keeps the old segment count until `wave_started` (comms before wave 1) — carried: `level.gd` emits `level_started` and then calls `start_level` → `start_wave(0)` synchronously, so no frame draws the stale count; comms do not exist before wave 1.
  - `[false]` `[reject]` Blind: a smaller `wave_count` mid-attempt makes the bar go backwards — carried: `wave_count` is `_waves.size()`, fixed for a level.
  - `[low]` `[reject]` Blind: `wave_started` with an index below `_current` is accepted — only the debug-only F6 `debug_skip_to_boss` can re-start an earlier-or-equal wave (`wave_director.gd:189`); keeping fills there is the intent's monotonic rule ("only `level_started` resets"), and a rewind branch would add code against that rule.
  - `[low]` `[reject]` Blind: the source scan is a blacklist and doesn't ban other autoloads — the AC is a review-time check; an identifier allowlist parser is more machinery than the risk warrants, and the handler tests show the Events-only behaviour.
  - `[low]` `[reject]` Blind: the theme is attached to `WaveBar` instead of a HUD root — `CanvasLayer` cannot hold a theme, so the fix needs a new root `Control`; the one shared `.tres` exists, and the HUD stories that add more controls can hoist it in one move.
  - `[false]` `[reject]` Blind: the fill covers the track border and tiny fills smear — carried: DESIGN.md gives the outline to empty segments, and `StyleBoxFlat` scales corner radii to fit.
  - `[low]` `[reject]` Blind: tween timing tests could flake — carried: tweens and `wait_seconds` share the SceneTree delta; the wave-bar tests passed on every run in this pass.
  - `[low]` `[reject]` Blind: hit-stop (`Engine.time_scale`) stretches the fill tween — the HUD tween following game time is the same "freezes with the game" behaviour the intent asks for; a hit-stop lasts milliseconds, so there is no visible harm.
  - `[low]` `[reject]` Blind: no tests for progress/clear before any `wave_started`, a double `wave_cleared`, or `_draw` at zero size — read the guards: `wave_index != _current` (−1) drops early events, `_raise_target` ignores a repeat 1.0, and `_draw` returns for 0 segments; the code is correct, and more tests would pin already-guarded paths.
  - `[false]` `[reject]` Blind: no boss-bar hand-off hook — the intent's Never list excludes the boss bar and cross-fade (Epic 7).
  - `[low]` `[reject]` Edge: `wave_started` rewind keeps old fills — same as the Blind rewind row: debug-only F6, consistent with the monotonic rule.
  - `[false]` `[reject]` Edge: smaller count mid-attempt — carried: count is fixed per level.
  - `[false]` `[reject]` Edge: stale count after `level_started` — carried: same refutation as the Blind stale-count row.
  - `[low]` `[reject]` Edge: negative segment widths when gaps exceed width — carried: needs more than 140 waves; the guard adds a branch for an unreachable case.
  - `[false]` `[reject]` Edge: NaN ratio — carried: `WaveProgress.ratio()` never returns NaN.
  - `[low]` `[reject]` Verification gap: `_draw` itself never runs under a test, so it could stop calling `style_for`/`fill_rect` — pre-verified, filed `defer`. The first pass already pinned `style_for` and `fill_rect`; what's left is the 10-line composition, and closing it needs a draw-capture harness the repo doesn't have (headless has no pixel readback). The defect isn't caused by a pre-existing issue, so `defer` doesn't apply; rejected as a low whose fix is new infrastructure.
  - `[low]` `[reject]` Intent: drawn output unverified — same root as the verification-gap row.
  - `[false]` `[reject]` Intent: AC3 checked by a crude source scan — carried: the AC is framed as a review check, and the handler tests cover behaviour.
  - `[low]` `[reject]` Intent: `test_wave_bar_in_the_hud` position check would pass without `Config` — true, but `test_rect_from_data` exercises the Config path on a bare `WaveBar`; duplicating it in the level test adds nothing.
  - `[false]` `[reject]` Intent: pause tested via `get_tree().paused`, not `PauseArbiter` — `PauseArbiter` is "the only owner of get_tree().paused" (`pause_arbiter.gd:2`), so the tween sees the identical state either way.
  - `[false]` `[reject]` Intent: count change without `level_started` and unconditional redraws untested — carried: the count is fixed per level, and the once-per-wave redraw was already rejected.
  - `[low]` `[reject]` Intent: the architecture "(fixed)" list amended under a status note — carried: same as the Blind `hud`-section row.
  - `[false]` `[reject]` Intent: `sprint-status.yaml` modified in the working tree — that edit is the orchestrator's bookkeeping, not in the story's commit or the reviewed diff.
- verification note: the full suite showed 1 failure outside this story (`test_wave_director.gd:347`), reproduced at baseline 07bcc62 — recorded in frontmatter `deferred`.

## Design Notes

**Highlight.** EXPERIENCE.md says only that "the next wave segment highlights" during the gap. The highlight here is the track drawn with a `coalition` outline (`highlight` stylebox), since `coalition` is the UX focus colour. It is set on `wave_cleared(i)` for `i + 1 < count` and cleared on the next `wave_started` or `level_started`. Because the style lives in the theme, a designer can restyle it without code.

**Where numbers live.** Visual style (colours, border, corners, gap) lives in the Theme, as the architecture's UI Framework section says. Layout position and tween time live in `tuning.json` (DESIGN.md marks the pixel values "tunable like gameplay values"), following the `player.missile_ring` precedent.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0; the class cache has `WaveBar`.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --quit-after 300` -- expected: no ERROR or WARN lines (no missing tuning key, no theme load error).


## Auto Run Result

Status: done (follow-up review pass)

**Summary:** The level's HUD has the segmented wave progress bar from UX-DR1/DR2: one segment per wave at x 680–1240, y 40, 560 × 20 with 4 px gaps.
- It is driven only by `Events` (`level_started`, `wave_started`, `wave_progress_changed`, `wave_cleared`).
- It fills the current segment with a pausable 0.2 s tween that never goes backwards within an attempt, and shows skipped waves as full.
- It highlights the next segment during the gap between waves.
- Styles come from the shared `ui/theme/defector_theme.tres` (type `WaveBar`). Layout and tween time come from `hud.wave_bar` in `tuning.json`.

This pass changed no code. It re-reviewed the committed implementation (9f944bf against baseline 07bcc62).

**Files changed (by the story, unchanged in this pass):**
- `game/ui/hud/wave_bar.gd` (+ `.uid`): the `WaveBar` Control.
- `game/ui/theme/defector_theme.tres`: the shared Theme with the `WaveBar` styleboxes and `separation`.
- `game/data/tuning.json`: the `hud.wave_bar` section.
- `game/scenes/level/level.tscn`: `HUD/WaveBar`.
- `game/tests/unit/test_wave_bar.gd` (+ `.uid`), `test_level.gd`, `test_config.gd`: the tests.
- `_bmad-output/game-architecture.md`: the as-built note.
- This spec: the follow-up triage log, a deferred item and this result.

**Review findings (this pass):** 27 in total: high 0, medium 0, low 16, false 11.
- **Patched:** none.
- **Deferred:** 1, found during verification rather than by a reviewer: a Story 2.2 test, `test_wave_director.gd:347`, fails on this machine. It reproduces at baseline, so this story didn't cause it.
- **Rejected:** all 27. Each reason is in the Review Triage Log. 15 rows were carried over from the first pass. The new rejects:
  - The F6 rewind keeps fills. This is the monotonic rule, and F6 is a debug-only path.
  - The source-scan blacklist isn't airtight. It is a review-time check.
  - The theme is attached to the bar rather than a HUD root. `CanvasLayer` can't hold a theme; later HUD stories can hoist it.
  - Hit-stop slows the fill. That is consistent with the bar freezing with the game.
  - Untested early or duplicate events. The guards already handle them.
  - The boss-bar hook. The intent excludes it.
  - `_draw` composition is untested. Fixing that needs a draw-capture harness.
  - The level test doesn't prove the Config path. `test_rect_from_data` does.
  - Pausing through the tree instead of `PauseArbiter`. It is the same mechanism.
  - The `sprint-status.yaml` edit belongs to the orchestrator.
- **Follow-up review recommended: false.** This is a follow-up pass and no high was patched. Patched by entry verdict: high 0, medium 0, low 0.

**Verification:**
- `--import` exited 0.
- Full GUT suite: 36 scripts, 461 tests, 460 passed and 1 failed: `test_wave_director.gd::test_f3_resolves_the_wave_and_fires_pending_triggers_in_order` ("the skipped group never spawns", expected 0, got 1).
  - It failed 5/5 run alone on HEAD and 2/2 at baseline 07bcc62 in a clean worktree, so it predates this story.
  - Every Story 2.3 test passed (`test_wave_bar.gd`, the wave-bar tests in `test_level.gd`, `test_config.gd`).
- `--quit-after 300` logged the level 0 start and wave 1/3, with no WARN or ERROR lines.

**Residual risks:**
- AC4 ("every pre-existing test still passes") isn't met on this machine. The cause is the pre-existing timing race above: `gap_s` 0.05 elapses within the test's 2-frame wait. It is deferred for the orchestrator.
- Nobody has looked at the bar on screen; all runs were headless. No feel or readability claim is made.
- No test runs `_draw` itself. Its helpers (`style_for`, `fill_rect`, `segment_rects`) are tested.
- There is no glow yet. Height 20 versus the mockup's 16 is one tunable number. The highlight style fills a UX gap and can be restyled in the theme.
