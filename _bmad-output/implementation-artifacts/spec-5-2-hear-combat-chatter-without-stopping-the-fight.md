---
title: 'Story 5.2: Hear Combat Chatter Without Stopping the Fight'
type: 'feature'
created: '2026-10-08'
status: 'awaiting-operator'
operator_actions:
  - 'Run the level scene in a debug build with `-- --comms=dev_combat_check` and confirm the interruption box slides in top-left, shows the Isolde placeholder portrait, the pink accent edge, the uppercase name and two lines of typing text that fit the box and stay clear of the wave bar, and that the fight never pauses.'
  - 'Run it again with `-- --comms=dev_combat_vale` and confirm the no-portrait variant: the text spans the full box width and the accent edge stays.'
  - 'Confirm the two text lines read cleanly at the 28 px line height (descenders on the first line do not touch the second line) and the 28 px name does not overlap the text.'
  - 'Confirm the box stays up about 2-3 s, then fades out, and that clicking during the line fires the laser normally.'
baseline_revision: '937ce66af4cfda53faacb6536d21a5beefb510ad'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-5-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-5-1-read-story-lines-on-the-comms-panel.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/EXPERIENCE.md'
warnings: ['oversized']
deferred:
  - summary: >-
      No Config test covers a missing comms.combat_line_max_chars (or comms.story_line_max_chars) tuning key: the single Log.error and the -1 fallback are untested.
    evidence: |-
      The verification-gap reviewer searched game/ for the "line length not checked" message and the _line_max_chars helper; only config.gd uses them, and every test loads the real tuning where both keys exist. Shipped tuning always has the keys. One test through _load_dialogue with a temp tuning lacking both keys would cover both kinds.
    location: >-
      game/autoloads/config.gd:253
    severity: low
---

<intent-contract>

## Intent

**Problem:** `CommsChannel` (Story 5.1) delivers story sequences only; a `combat` sequence is logged as "arrives in Story 5.2" and finished with nothing shown. Mid-fight interruptions (Isolde mocking, an ally warning) can't reach the player, and there are no priority rules between story and combat lines. Covers FR38 (combat) and architecture R9. Tier: MUST.

**Approach:** Add a `CommsBox` view (the UX "Interruption box", top-left, no dim, click-through) and teach `CommsChannel` the combat path: show the line without pausing, type it at `chars_per_s`, keep it up for `max(combat_line_min_s, chars / chars_per_s + combat_line_extra_s)` s of game time, then fade it and emit `finished`. Add the priority rules (story preempts combat; combat queues FIFO max 3, oldest dropped), the combat data limits in `DialogueValidator`, and the per-level interruption cap in the data test.

## Boundaries & Constraints

**Always:**
- **Data and tuning.** `tuning.json` `comms` gains `combat_line_max_chars: 50`, `box_slide_in_s: 0.15`, `box_fade_out_s: 0.2` (the existing `combat_line_min_s` 2.0, `combat_line_extra_s` 1.2, `combat_queue_max` 3 are used, not duplicated). `ui` gains `comms_box: { "x": 32, "y": 24, "w": 560, "h": 96, "edge_px": 4, "padding_px": 6, "portrait_px": 72, "portrait_gap_px": 12, "name_h_px": 28, "text_line_h_px": 28, "text_lines": 2 }`. `dev.json` gains `dev_combat_check` (isolde, one line ≤ 50 chars) and `dev_combat_vale` (vale, one line ≤ 50 chars, no-portrait variant), so `-- --comms=<id>` shows the box.
- **`DialogueValidator`.** `validate` / `validate_sequence` take a `combat_max_chars: int` after `story_max_chars` (negative skips the check, like the story limit). A combat sequence must have exactly 1 line (`combat sequence has N lines, exactly 1 allowed`) whose `text` is at most `combat_max_chars` characters. New `static func is_interruption(seq: Dictionary) -> bool`: combat mode and no line carries a `cut_off_at` key (the Tarek cut-off, Story 5.4, doesn't count against the cap). `Config._load_dialogue` passes `comms.combat_line_max_chars` (missing key: `Log.error` once when tuning loaded, then -1, same as the story key). Update every existing caller and test.
- **`CommsBox`** (`game/systems/comms/comms_box.tscn` + `.gd`, `class_name`, full-rect `Control`, process mode inherited (pausable), `mouse_filter` IGNORE on it and every child). Children: `Box` (Panel, theme style), inside it `Edge` (ColorRect, speaker accent), `Portrait` (Panel frame + centred initial `Label`, like `CommsPanel`), `Name`, `Text` (Label: autowrap word-smart, clip text, `VC_CHARS_AFTER_SHAPING`). No dim, no cue.
  - `static func layout(x, y, w, h, edge, padding, portrait_px, portrait_gap, name_h, line_h, lines, with_portrait) -> Dictionary` returns box (canvas), edge, portrait, name and text rects (local). With `inset = (h - portrait_px) / 2`: edge `(0, 0, edge, h)`; portrait `(edge + inset, inset, portrait_px, portrait_px)`; `left = edge + inset + (portrait_px + portrait_gap if with_portrait else 0)`; block width `w - left - inset`; name `(left, padding, bw, name_h)`; text `(left, padding + name_h, bw, line_h * lines)`. With the tuning numbers: text 448 px wide with a portrait (x 100), 532 px without (x 16), text block y 34-90 inside the 96 px box.
  - API, called only by `CommsChannel`: `show_line(speaker, text)` sets the uppercase name from `comms.speakers` and the accent (from the Theme's `CommsPanel/colors/<speaker>`, shared with the panel), colours `Edge`, shows the portrait only when `portrait` is true, re-lays out, makes it visible at full alpha, slides `Box` in from `x = -w` to `x` over `box_slide_in_s` and types `visible_characters` 0 → count over `count / chars_per_s`. `dismiss()` fades `modulate.a` to 0 over `box_fade_out_s`, then hides. `hide_now()` kills every tween and hides at once. `is_typing()`, `is_open()` (visible and not fading). Tweens are created on the box with the default pause mode, so they freeze while the tree is paused. Starts hidden; tuning and Theme values cached in `_ready`.
  - Theme type `CommsBox`: `font_sizes/text` 24, `font_sizes/name` 28, `constants/line_spacing` set so two 24 px lines fit the 56 px text rect (measure it with the fallback font, as Story 5.1 did), `styles/panel` reusing the existing `StyleBoxFlat_comms_panel` sub-resource. The portrait frame is the only per-node style override; the `Edge` colour is set on the ColorRect (not a style override).
- **`CommsChannel`** gains `@export var box: CommsBox` (wired in `level.tscn` to a new `Comms/CommsBox` instance, placed before `CommsPanel` so the panel draws on top). Combat state: `_combat: StringName` (`&""` idle), its lines, index, `_combat_left_s`, and `_combat_queue: Array[StringName]`.
  - **Combat request:** if a combat sequence is playing **or** a story is showing, append to `_combat_queue`; if the queue is then longer than `comms.combat_queue_max`, pop the oldest, `Log.debug("comms", ...)` it and emit its `finished` deferred. Otherwise start it: `box.show_line(...)` for line 0, set `_combat_left_s = combat_line_s(text.length(), ...)`, `Log.info("comms", "Combat sequence '<id>' started")`. No pause, no SFX.
  - **`static func combat_line_s(chars: int, chars_per_s: float, min_s: float, extra_s: float) -> float`** = `maxf(min_s, chars / chars_per_s + extra_s)`; with `chars_per_s <= 0` it is `maxf(min_s, extra_s)`.
  - **`step_combat(delta: float)`**, called from `_process` only while `not get_tree().paused`: counts `_combat_left_s` down; at ≤ 0 shows the next line or, after the last, `box.dismiss()`, logs `Combat sequence '<id>' finished`, clears `_combat`, emits `finished(id)`, then starts the next queued combat if no story is showing and nothing started one.
  - **Story request while a combat plays (preempt):** `box.hide_now()`, `Log.info` the preemption, clear `_combat`, emit its `finished` deferred, then start the story exactly as in Story 5.1. The combat queue is kept.
  - **Story end:** after the existing pop + `finished` (queue empty), if no story is showing and no combat plays, start the next queued combat.
  - Input is untouched: `_unhandled_input` still acts only while a story shows, so clicks during a combat line are never consumed. Accessors `current_combat() -> StringName` and `combat_queued() -> Array[StringName]` (copy).
  - Every requested known sequence emits `finished` exactly once (played, preempted or dropped).
- Statically typed GDScript, `Log` only (`comms`, `data`), no tuning number in code, only `PauseArbiter` pauses. Tests follow the 5.1 fixtures (`Log.sink` capture; `after_each` reloads Config, `PauseArbiter.clear()`, resets mouse mode).

**Never:** No silence, cut-off effects, `cut_off_at` handling in the channel, `comms_static`, music or shake (Story 5.4). No WaveDirector `comms` action or level comms triggers (Story 5.3). No Isolde flags or surrender prompt (5.6). No real portraits (Epic 8). No new autoload, input action, `Events` signal or Log category. Don't change `PauseArbiter`, `Player` or `WaveDirector`. Don't change Story 5.1's story behaviour.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Combat plays | request `combat_a` (15 chars) while idle | tree not paused, no `story` reason, box visible at the UX rect, name/accent/edge of the speaker, typing; `finished` not yet emitted | none |
| Line time | 15 chars, cps 45 | `finished` once after 2.0 s of `step_combat` (not at 1.9 s); 50 chars → 2.31 s | none |
| Pause freezes it | `menu` pushed mid-line, frames pass | `_combat_left_s` and the typewriter don't advance; resume continues | none |
| Clicks ignored | LMB press/release during a combat line | not handled by the channel (probe receives both), nothing changes | none |
| Preempt | story requested while `combat_a` plays | box hidden at once, `finished(combat_a)` deferred (once), story panel + `story` pause as in 5.1 | none |
| Combat queue | 4 combat requests while one plays (queue max 3) | oldest queued dropped with deferred `finished`; the rest play FIFO after the current one | `Log.debug` the drop |
| Combat behind a story | combat requested while a story shows | queued; plays after the story pops, not while paused | none |
| Queue survives preempt | combat queued, story preempts the playing one | after the story ends, the queued combat plays | none |
| Story on story | unchanged from 5.1 | queued, never dropped | none |
| Combat data limits | fixture: combat with 2 lines; combat line 51 chars | each `Log.error`ed with path + id, sequence left out | logged, skipped |
| Interruption cap | level dict with 3 combat comms actions (one a cut-off) | counts 2 (cut-off excluded); a level with 3 non-cut-off combat actions counts 3 | data test fails on > 2 |

</intent-contract>

## Code Map

- `game/systems/comms/comms_channel.gd` -- `_on_events_comms_sequence_requested` (l.78; the combat branch at l.83-86 is the placeholder to replace), `_start` (l.95), `_finish` (l.153; hook the "start queued combat" after the final `finished`), `_unhandled_input` (l.121, unchanged). Header doc comment lists the rules: update it.
- `game/systems/comms/comms_panel.gd` / `.tscn` -- the view to mirror for `CommsBox`: `_ready` caching (l.69), `show_line` (l.115), `_type` tween (l.182; the box must NOT use `TWEEN_PAUSE_PROCESS`), `layout` static (l.164), `_apply_frame` (l.224), `_apply_theme` (l.234), `accent_color` (l.148).
- `game/systems/comms/dialogue_validator.gd` -- `validate` (l.22), `validate_sequence` (l.36), `MODE_COMBAT`; the header says combat limits are 5.2's.
- `game/autoloads/config.gd` -- `_load_dialogue` (l.195) calls the validator twice; `_story_max_chars` (l.241) + `STORY_MAX_CHARS_KEY` is the pattern for the combat key.
- `game/data/tuning.json:217` -- `comms` (combat keys already present: `combat_line_min_s`, `combat_line_extra_s`, `combat_queue_max`, `cutoff_hide_s` is 5.4's); `ui.comms_panel` at l.287 (add `comms_box` beside it).
- `game/data/dialogue/dev.json` -- add the two dev combat sequences.
- `game/ui/theme/defector_theme.tres:86-111` -- `StyleBoxFlat_comms_panel` and the `CommsPanel/...` entries; add `CommsBox/...` (no new sub_resource needed, so `load_steps` stays).
- `game/scenes/level/level.tscn:131-139` -- `Comms` layer with `CommsChannel` (`node_paths` for the export) and the `CommsPanel` instance; add the `CommsBox` instance and wire `box`.
- `game/tests/unit/test_comms_channel.gd` -- fixture in `before_each` (l.41) loads `tests/fixtures/dialogue/channel/`; `test_combat_id_finishes_deferred_without_pause` (l.291) becomes obsolete: replace it. Uses an input probe instead of `is_input_handled()` (GUT root viewport quirk, see the 5.1 triage log).
- `game/tests/fixtures/dialogue/channel/channel.json` -- add combat sequences (`combat_b`..`combat_e`, one a vale line, one 50 chars). `tests/fixtures/dialogue/bad/` -- add the two bad combat cases; tests in `test_config.gd` count `push_error`s, so update those counts.
- `game/tests/unit/test_comms_panel.gd` -- style for the new `test_comms_box.gd` (layout rects, fit test with the fallback font).
- `game/tests/data/test_data_files.gd:468-520` -- dialogue tests; `test_every_dialogue_file_is_valid` (l.479) calls `validate` (new arg). Level files are `data/levels/level_{1,2,3,dev}.json`; actions live at `waves[].triggers[].actions[]` with a `comms` key (none exist yet).
- `game/tests/unit/test_level.gd` -- has the level-scene instancing pattern and the 5.1 no-laser test (count `laser_bolt` nodes) to reuse for the combat-line laser test.
- `_bmad-output/game-architecture.md:912-925` -- the "Built (Story 5.1)" note and the Rules list; Data Patterns dialogue line (l.~1663); add an As-built (Story 5.2) section after the last As-built section.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_comms_box.gd`, `test_comms_channel.gd`, `test_dialogue_validator.gd` (write first) -- every I/O matrix row. Drive time with `step_combat(delta)` and await frames for tweens; no wall-clock sleeps. Box layout rects checked against the UX numbers (box 32,24,560,96; text 448/532 wide); a fit test that a realistic 50-char line wraps to at most 2 lines inside the text rect in both variants.
- `game/tests/fixtures/dialogue/channel/channel.json`, `tests/fixtures/dialogue/bad/*` -- the combat fixtures.
- `game/systems/comms/comms_box.gd`, `comms_box.tscn` (new) and `comms_channel.gd` -- as specified.
- `game/systems/comms/dialogue_validator.gd`, `game/autoloads/config.gd`, `game/tests/unit/test_config.gd` -- combat limits, `is_interruption`, the new tuning key.
- `game/data/tuning.json`, `game/data/dialogue/dev.json`, `game/ui/theme/defector_theme.tres` -- data and theme.
- `game/scenes/level/level.tscn`, `game/tests/unit/test_level.gd` -- wire `Comms/CommsBox`; test it exists and `CommsChannel.box` is valid.
- `game/tests/data/test_data_files.gd` -- every combat sequence in `res://data/dialogue/` has exactly 1 line of ≤ 50 characters (asserted directly, not only via the validator); every level JSON has at most 2 `comms` actions whose sequence `is_interruption`; a self-check of that counter on an inline level dict (3 combat actions, one sequence with `cut_off_at`, counts 2); the new tuning keys are positive.
- `_bmad-output/game-architecture.md` -- mark combat lines and the priority rules as built (Story 5.2), record the decisions in Design Notes below, add "As-built 2026-10-08 (Story 5.2)".

**Acceptance Criteria:**
- Given the level scene running with the fire button held, when `Events.comms_sequence_requested(&"dev_combat_check")` is emitted, then the game stays unpaused, the interruption box shows top-left with the uppercase accent name and typing text, laser bolts keep spawning, and after the line time the box fades and `comms_sequence_finished(&"dev_combat_check")` is emitted once.
- Given the full GUT suite, when it runs headless, then every test passes with no new orphan warnings.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 25 findings — high 0, medium 1, low 15, false 5, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) a combat requested inside a `finished` listener starts at once and jumps ahead of queued combat ids -- real: `step_combat`/`_finish` emit before `_start_next_combat()`, and Story 5.3 chains resume synchronously inside that emit. `_request_combat` now starts directly only when the combat queue is also empty; added `test_combat_requested_in_a_finished_listener_queues_behind_older_ones`.
  - `[low]` `[reject]` (blind) queued combat lines replace each other with no visible fade in between -- the spec orders dismiss-then-start; with at most 2 interruptions per level a queue is rare, and a hand-off delay adds a new timed state.
  - `[false]` `[reject]` (blind) "finished exactly once" breaks at level teardown -- every caller that could await `finished` (the WaveDirector chains) lives in the level scene and is freed with it; the architecture says death and exit discard all chains.
  - `[low]` `[reject]` (blind) the multi-line combat branch is unreachable -- the spec asked for the generic line loop; it is three lines and harmless.
  - `[low]` `[reject]` (blind) the level test holds fire with `Input.action_press`, not real mouse events -- click-through is pinned by the box's mouse_filter test and the channel's probe test; GUI consumption doesn't change `Input` state the laser polls.
  - `[low]` `[patch]` (blind) the level test never shows real frames drive the combat timer -- it now records `_combat_left_s` at start and asserts it decreased after the 30 physics frames.
  - `[low]` `[defer]` (blind) no test for a missing `comms.combat_line_max_chars` key -- same as the verification-gap row below; deferred.
  - `[low]` `[patch]` (blind) no test for a story starting while the box is fading -- same as the verification-gap row; added `test_story_hides_a_fading_combat_box`.
  - `[medium]` `[patch]` (blind) `line_spacing = -12` gives a ~22 px line pitch, not the UX's 28 px, so two-line interruptions look cramped -- replaced by a theme `FontVariation` (no base font, spacing top/bottom -3) for the box text with `line_spacing` 0: pitch 28 px, two full lines in the 56 px rect; the fit tests now assert the 28 px pitch in both variants.
  - `[low]` `[reject]` (blind) the line-spacing regression test depends on the fallback font -- it was replaced by the pitch test in the patch above; a test failing when Epic 8 changes the font is the intended signal to re-measure.
  - `[low]` `[patch]` (blind) the tuning test requires `ui.comms_box.x`/`y` > 0 -- now >= 0; sizes and durations stay > 0.
  - `[low]` `[reject]` (blind) `_apply_frame` duplicates the StyleBox per line -- once per interruption, never per frame; negligible (same call as Story 5.1).
  - `[low]` `[reject]` (blind) `_assert_color` duplicated across two test files -- test-only style, no harm named.
  - `[low]` `[patch]` (edge) FIFO break when a `finished` listener requests combat -- same root cause as the first blind row; same fix.
  - `[false]` `[reject]` (edge) no `_exit_tree` flush of combat `finished` -- same refutation as the blind teardown row.
  - `[false]` `[reject]` (edge) a deferred `finished` is lost if the channel is freed first -- the channel is freed only with the level scene, which frees every awaiting caller too.
  - `[low]` `[reject]` (edge) a queued combat id removed by a Config reload shows an empty box -- needs a debug F5 reload that deletes a sequence between request and play; an empty box for 2 s is harmless.
  - `[low]` `[reject]` (edge) the interruption-cap data test skips unknown comms ids -- Story 5.3 owns "every sequence id a level references exists"; no level has comms actions yet.
  - `[false]` `[reject]` (edge) the level test leaves `fire_laser` pressed on early exit -- GUT assertions don't abort the test, so the release always runs (same as the 5.1 triage).
  - `[low]` `[patch]` (verification-gap) story start hiding a fading box is untested -- added `test_story_hides_a_fading_combat_box`.
  - `[low]` `[defer]` (verification-gap) missing-tuning-key path for the combat limit untested -- deferred (filed disposition): shipped tuning has the key and the story key has the same gap; one test should cover both.
  - `[low]` `[reject]` (intent) the human look check is prose, not `operator_actions` -- handled at finalize: following the Story 5.1 precedent, the look checks are listed under `operator_actions` and the status is `awaiting-operator`.
  - `[low]` `[patch]` (intent) the rendered line pitch follows fallback-font metrics, not 28 px -- same root cause as the medium blind row; same fix.
  - `[low]` `[patch]` (intent) tests end the line through the private timer -- same root cause as the level-timer blind row; same fix.
  - `[false]` `[reject]` (intent) the level-JSON cap passes trivially on real data -- no level has comms actions until Story 5.3; the inline self-check proves the counter can fail.

## Design Notes

**Decisions where the docs are silent** (both follow the GDD rule "every scripted beat fires in every playthrough"; R9 only says what is dropped):
- A combat request while a story shows is **queued** (combat queue), not dropped, and plays after the story ends.
- Preemption drops only the **playing** combat line; queued combat lines survive and play after the story.
- A combat line dropped from the full queue emits `finished` too, so "every request finishes exactly once" holds for any future awaiting caller.

**Game time.** The channel runs `PROCESS_MODE_ALWAYS` for story input, so the combat timer is stepped only while the tree isn't paused, and the box itself is pausable. A pause menu over an interruption freezes it; it resumes where it was.

**Name size.** The 96 px box holds a 28 px name line and two 28 px text lines (UX numbers). Godot's fallback font is taller than its size, so the text `line_spacing` is negative; the fit test pins it. Epic 8's font changes the metrics; the operator check covers the look.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: completes (new `class_name CommsBox`).
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass.

**Manual checks (if no CLI):**
- Run `level.tscn` with `-- --comms=dev_combat_check` and `-- --comms=dev_combat_vale`: the box slides in top-left, the accent edge, portrait (or none), name and two-line text fit the box and stay clear of the wave bar, the fight never pauses, and the box fades after about 2-3 s.

## Auto Run Result

Status: awaiting-operator

**Summary:** Combat chatter now reaches the player without stopping the fight. A new `CommsBox` (the UX interruption box, top-left 32,24,560x96, click-through, no dim) shows the speaker's accent edge, a placeholder portrait (none for Vale/system), the uppercase name and typewriter text. `CommsChannel` plays combat sequences with no pause: each line stays `max(2.0, chars / 45 + 1.2)` s of game time (frozen while the tree is paused), then the box fades and `finished` is emitted. A story preempts a playing combat line (it still emits `finished`, deferred); combat queues FIFO up to 3 (the oldest dropped, with `finished`); a combat requested during a story waits for it; story-on-story is unchanged. `DialogueValidator` enforces one line of at most 50 characters per combat sequence, and the data test caps each level at 2 interruptions (cut-off lines excluded via `is_interruption`).

**Files changed:**
- `game/systems/comms/comms_box.gd`, `comms_box.tscn` (new): the interruption box view and its static layout
- `game/systems/comms/comms_channel.gd`: combat path, priority rules, combat queue, `step_combat`, `combat_line_s`
- `game/systems/comms/dialogue_validator.gd`, `game/autoloads/config.gd`: combat limits, `is_interruption`, `comms.combat_line_max_chars`
- `game/data/tuning.json`, `game/data/dialogue/dev.json`: combat/box tuning, `ui.comms_box`, `dev_combat_check` and `dev_combat_vale`
- `game/ui/theme/defector_theme.tres`: `CommsBox` theme type (sizes, panel style, a 28 px-pitch text font variation)
- `game/scenes/level/level.tscn`: `Comms/CommsBox` wired to the channel
- Tests: `test_comms_box.gd` (new), `test_comms_channel.gd`, `test_dialogue_validator.gd`, `test_config.gd`, `test_level.gd`, `tests/data/test_data_files.gd`, fixtures `channel.json` and `bad/e_combat.json`
- `_bmad-output/game-architecture.md`: combat lines and priority rules marked built, the open-doc decisions recorded, As-built (Story 5.2) section

**Review:** 25 findings. Patches applied: medium 1 (box text line pitch 22 px -> 28 px per UX), low 4 entries (FIFO order when a `finished` listener requests combat; tests for a story hiding a fading box and for real frames driving the timer; tuning test allows position 0). Deferred 1 (missing-tuning-key test for the line limits). Rejected: the rest, each with its reason in the Review Triage Log (teardown/free-order claims refuted because callers die with the scene; rare or harmless debug-only paths; negligible cost; test-only style).

**Follow-up review recommended: false.** Only one medium was patched and no high; the remaining risk is visual and is covered by `operator_actions`.

**Verification:**
- `--import`: exit 0.
- Full GUT suite headless: 1181/1181 passing, no orphan warnings.
- Every I/O matrix row is covered by a test that ran (channel, box, validator, config and data tests).

**Residual risks:**
- The look (slide, fade, two-line fit, 28 px name in a 28 px slot) is checked as node state with Godot's fallback font only; Epic 8's Kenney Future font will need new spacing values. See `operator_actions`.
- Three rules the docs left open were decided and recorded (combat behind a story queues; queued combat survives a preempt; dropped queue entries emit `finished`).
- Back-to-back queued combat lines replace each other without a visible fade gap.
