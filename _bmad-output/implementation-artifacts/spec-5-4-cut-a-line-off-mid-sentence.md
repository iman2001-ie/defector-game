---
title: 'Story 5.4: Cut a Line Off Mid-Sentence'
type: 'feature'
created: '2026-10-08'
baseline_revision: '82bdd753fc4d036467cef5c0f6bc3e434b99cd82'
status: 'awaiting-operator'
operator_actions:
  - 'Run the level scene in a debug build, kill enemies on level_dev wave 2 until the wave bar passes a quarter, and confirm the TAREK line in the top-left box stops mid-word ("...you co"), a static burst plays, the screen shakes and the box vanishes about 0.6 s later.'
  - 'Listen to the placeholder `comms_static` sound and confirm it reads as a dead radio channel, not a glitch or an explosion.'
  - 'Replay the same moment and press F3 instead; confirm the cut-off still fires and wave 3 starts normally.'
  - 'Judge whether the cut-off hits hard as a sudden loss; automated tests cannot verify feel.'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-5-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/EXPERIENCE.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-5-3-trigger-dialogue-and-music-from-wave-events.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A dialogue line can't be cut off. `CommsChannel` ignores `cut_off_at` and `after`, there is no comms silence, no `comms_static` sound and no way to fire only a shake tier through `Feedback`. Tarek's fall (Epic 6) needs all of this (FR40). Tier: MUST.

**Approach:** A cut-off is a **combat-mode** line in the interruption box (architecture example `l2_w5_tarek_cutoff`, UX EXPERIENCE.md "Cut-off: ... the box hides after 0.6 s"). The channel types it to exactly `cut_off_at` characters, runs the `after` effects (static SFX, shake tier, music, silence), hides the box 0.6 s later and finishes. Silence drops further combat sequences until `Events.wave_cleared`. The validator checks the new keys, and `level_dev.json` gets a cut-off at a progress ratio.

## Boundaries & Constraints

**Always:**
- **Data shape** (line keys, combat sequences only): `"cut_off_at": <int>`, optional `"after": { "silence": "until_wave_clear", "shake": "<ImpactTier name>", "sfx": "<sfx id>", "music": "stop"|"combat"|"boss" }`, every `after` key optional.
- **`DialogueValidator.validate_sequence`**, one problem each:
  - `cut_off_at` in a story sequence (`cut_off_at is only allowed in combat sequences`).
  - `cut_off_at` not a whole number from 1 to text length - 1 (JSON floats with no fraction are whole).
  - `after` without `cut_off_at`, or not an object.
  - An unknown `after` key.
  - `silence` other than `until_wave_clear`.
  - `shake` not in `ImpactTier.NAMES`.
  - `sfx` not a non-empty string.
  - `music` not in `LevelValidator.MUSIC_ACTIONS`.
  - Update the doc comment.
- **`Feedback.shake_tier(tier: int)`**: shakes the registered camera with that tier's `shake_px`/`shake_s` only (no explosion, hit-stop or SFX). An out-of-range tier gets `Log.error` and does nothing. No camera: no-op.
- **`CommsBox`**:
  - `show_line(speaker, text, cut_off_at: int = -1)`: with `cut_off_at >= 0` it types only to `cut_off_at` characters over `cut_off_at / chars_per_s` and stays there (never `-1`).
  - `cut_off(chars: int)`: kills the type tween and sets `visible_characters = chars`.
  - Existing callers are unchanged.
- **`CommsChannel`** (one combat line per sequence, so a cut-off line is the whole sequence):
  - **Typing:** a cut-off line's timer is `cut_off_at / chars_per_s` s of game time (0 when `chars_per_s <= 0`), not `combat_line_s`.
  - **Cut-off moment:** when the timer runs out, the channel calls `box.cut_off(cut_off_at)`, logs `Log.info("comms", ...)` and runs `after` in this order:
    - `Audio.play_sfx(sfx, 0.0)`
    - `Feedback.shake_tier(ImpactTier.from_name(shake))`
    - `Audio.apply_music_action(music)`
    - silence
  - **Hide:** after `comms.cutoff_hide_s` (0.6, already in tuning) more seconds it calls `box.hide_now()` (no fade), then logs, emits `finished` and starts the next queued combat as today.
  - Both phases count game time in `step_combat`, so a pause freezes them.
  - **Silence on:** sets `is_silenced()` true, logs at INFO and drops every queued combat sequence (`Log.debug`, deferred `finished`).
  - **Void silence:** if `Events.wave_cleared` arrived between the cut-off line's start and its cut-off moment, the silence is skipped (`Log.debug`), so it never carries into the next wave.
  - **While silenced:** a combat request is dropped (`Log.debug("comms", ...)` naming the id, deferred `finished`). Story requests play as before.
  - **Silence off:** `Events.wave_cleared` clears it (INFO log). Connect in `_ready` and disconnect in `_exit_tree`, like the request signal.
  - **Preempted:** a story that preempts a cut-off line before its cut-off moment drops it like any combat line, and no `after` effects run. After the moment, the effects have already run and the box just hides.
  - Update the header doc comment.
- **SFX:** add `comms_static` (a short static burst under 1 s with its own seed constant) to `tools/gen_placeholder_sfx.py`. Generate `game/assets/audio/sfx/sfx_comms_static.wav`, run `--import` so its `.import` sidecar exists, register `&"comms_static"` in `Audio.SFX` and add a `CREDITS.md` row.
- **Dev data:**
  - `data/dialogue/dev.json` gets combat sequence `dev_tarek_cutoff`, speaker `tarek`, text `General, get behind me, I've got you cov—`, `cut_off_at` 39, `after` `{ silence: until_wave_clear, shake: large, sfx: comms_static, music: stop }`.
  - `data/levels/level_dev.json` wave 2 gets a new trigger `{ "when": "progress", "at": 0.25, "actions": [ { "comms": "dev_tarek_cutoff" } ] }`. The reinforcements trigger stays unchanged.
- Statically typed GDScript, `Log` only, no new `Events` signal, autoload or tuning key. Only `Feedback` shakes.

**Never:** Don't support cut-off in story sequences or on the story panel. No `tarek_fall` handling or ally changes (Epic 6). No real level data or final script (Epic 7, Story 5.7). Don't change the combat queue, preempt or story rules beyond what is listed. Don't change WaveDirector or `Audio` music behaviour.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Cut-off timeline | `dev_tarek_cutoff` requested, idle | box typing; just before 39/45 s: no effects; at it: `visible_characters` 39, `comms_static` played, camera shaking, music stopped, silenced; box visible until +0.6 s, then hidden and `finished` once | none |
| No `after` | cut-off line without `after` | stops at `cut_off_at`, hides after 0.6 s, finishes; no SFX, shake or silence | none |
| Silence drops combat | silenced, `dev_combat_check` requested | not shown; `finished` deferred; DEBUG log | DEBUG |
| Silence keeps story | silenced, `dev_comms_check` requested | story plays and pauses as usual | none |
| Silence clears | silenced, `wave_cleared` | `is_silenced()` false; next combat plays | INFO |
| Queue flushed | combat queued behind the cut-off line | at the cut-off moment the queued one is dropped with deferred `finished` | DEBUG |
| Wave clears first | `wave_cleared` while the cut-off line types | effects still run, but no silence | DEBUG |
| Preempted early | story requested while the cut-off line types | box hides, combat `finished` deferred, no SFX, shake, music or silence | none |
| Paused | menu pause during typing | timers and tween freeze; resume where they were | none |
| Bad data | story-mode `cut_off_at`; `cut_off_at` 0, 1.5 or >= length; `after` alone; `after.bogus`; `silence: "forever"`; `shake: "huge"`; `sfx: ""`; `music: "loud"` | one validator problem each | logged |
| Bad tier | `Feedback.shake_tier(99)` | nothing shakes | `Log.error` |

</intent-contract>

## Code Map

- `game/systems/comms/comms_channel.gd`
  - `_on_events_comms_sequence_requested` (l.133): the combat branch at l.138 is where the silence drop goes.
  - `step_combat` (l.245): the line countdown. Add the cut-off phase there.
  - `_show_combat_line` (l.289): sets `_combat_left_s` via `combat_line_s`.
  - `_request_combat` (l.267): the queue and drop pattern with `_emit_finished.call_deferred`.
  - `_preempt_combat` (l.308) and `_clear_combat` (l.317): reset the new cut-off state here.
  - `_ready` and `_exit_tree` (l.70-85): signal wiring and tuning cache.
- `game/systems/comms/comms_box.gd`: `show_line` (l.109), `_type` and `_on_typed` (l.210-223; `_on_typed` sets -1, which a cut-off must avoid), `hide_now` (l.148).
- `game/systems/comms/dialogue_validator.gd`: `validate_sequence` (l.40), per-line loop (l.63-83), `CUT_OFF_KEY` (l.22). `is_interruption` already excludes cut-off lines.
- `game/autoloads/feedback.gd`: `impact` (l.74) shows the camera shake guard to reuse in `shake_tier`, and `_tiers` holds the rows.
- `game/core/impact_tier.gd`: `NAMES` and `from_name`.
- `game/systems/waves/level_validator.gd`: `MUSIC_ACTIONS`.
- `game/autoloads/audio.gd`: the `SFX` const registry (l.19), `newest_player()` (l.96), `apply_music_action` and `current_music`.
- `game/data/tuning.json`: `comms.cutoff_hide_s` 0.6 already exists (l.~222). Read it via `Config.num`.
- `game/systems/waves/wave_director.gd`: `_try_clear` (l.546) emits `wave_cleared` before the gap, and `debug_resolve_wave` (l.238) fires progress triggers synchronously. So under F3 the wave clears while the cut-off still types, which is the "Wave clears first" row.
- `tools/gen_placeholder_sfx.py`: follow `comms_open` and `COMMS_OPEN_SEED` (l.26, l.179, l.239). Run it with `uv run python tools/gen_placeholder_sfx.py` from the repo root. It must leave the existing WAVs byte-identical (check `git status`).
- `game/assets/CREDITS.md`: the "Project-generated placeholders" table.
- Tests:
  - `game/tests/unit/test_comms_channel.gd`: fixture (l.47-83), `_request`, `_box_text`, `_end_combat_line` (l.341), the preempt and queue tests (l.445-526).
  - `test_comms_box.gd`: `_make` (l.26), the typewriter test (l.178).
  - `test_feedback.gd`: camera listener setup (l.22).
  - `test_dialogue_validator.gd`: `_seq`, `_line` and `_only_problem` helpers.
  - `test_level.gd`: `_make_level`, `_make_player_invincible`, the F3 all-waves test (l.364) and the real-kills test (l.392).
  - `tests/data/test_data_files.gd`: the interruption-cap counter, which must keep excluding the cut-off.

## Tasks & Acceptance

**Execution:**
- Tests first: `test_dialogue_validator.gd`, `test_feedback.gd`, `test_comms_box.gd` and `test_comms_channel.gd` get one test per I/O matrix row. Drive the channel timeline with `step_combat(delta)` and register a test `ShakeCamera` with `Feedback` for the shake assert. Restore `Audio` music state and the camera in `after_each`.
- `tools/gen_placeholder_sfx.py`, the new WAV and its `.import`, `game/autoloads/audio.gd`, `game/assets/CREDITS.md`: the `comms_static` SFX.
- `game/autoloads/feedback.gd`: `shake_tier`.
- `game/systems/comms/dialogue_validator.gd`: the cut-off rules.
- `game/systems/comms/comms_box.gd`, `game/systems/comms/comms_channel.gd`: cut-off and silence.
- `game/data/dialogue/dev.json`, `game/data/levels/level_dev.json`: the dev cut-off.
- `game/tests/unit/test_level.gd`: the surface tests (ACs 1 and 2).
- `_bmad-output/game-architecture.md`:
  - Mark cut-off and silence as built in the Comms Channel section, and fix the Story 5.2 note "Silence, cut-off ... still planned".
  - Document `Feedback.shake_tier` beside `Feedback` as built.
  - Add an "As-built 2026-10-08 (Story 5.4)" section after the Story 5.3 one, with the Design Notes decisions.

**Acceptance Criteria:**
- Given the level scene with `level_dev.json` on wave 2, when counted enemies are killed one by one until progress reaches 0.25, then `dev_tarek_cutoff` shows in the real `Comms/CommsBox`. At the cut-off moment its text shows exactly 39 characters, `Audio.newest_player()` plays the `comms_static` stream, the level `ShakeCamera` is shaking and the channel is silenced. A `dev_combat_check` request is dropped. The box hides 0.6 s later. Once the remaining enemies die, `wave_cleared` lifts the silence and wave 3 starts.
- Given the same level on wave 2, when F3 is pressed (`debug_resolve_wave`), then the cut-off fires (box shown, then stopped at 39 characters with the static SFX), the wave clears and wave 3 starts as usual, and the channel isn't silenced during wave 3.
- Given the full GUT suite, when it runs headless after `--import`, then every test passes with no new orphan or engine-error output, and the existing level_dev F3 and real-kill tests still pass.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 23 findings — high 0, medium 0, low 19, false 4, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) `after.sfx` isn't checked against the registered sounds, so a typo passes validation and only warns at runtime — added `test_every_after_sfx_is_registered` and a self-check to `tests/data/test_data_files.gd`. The validator stays pure.
  - `[low]` `[reject]` (blind) a cut-off line has no queue priority. It can be dropped past 3 queued lines or by an earlier cut-off's silence, and if it is queued past a wave clear its silence lands in the next wave — each case needs a stack of combat lines around the single Tarek cut-off, which no data does. A fix needs per-request wave tracking or a priority lane, which is more than a direct correction.
  - `[low]` `[reject]` (blind) the spec Code Map says F3 clears wave 2 while the cut-off types, and the as-built disagrees — the as-built is right: the reinforcements `wait 1.0` holds the clear past the 0.87 s cut-off. The fix would edit this spec. The AC holds either way, and the Auto Run Result records the correction.
  - `[low]` `[patch]` (blind) the F3 acceptance test could pass on the log line alone, skipping the 39-character, box and SFX asserts — the test now waits for the HOLD phase (5 s timeout) and asserts it with no log fallback.
  - `[low]` `[reject]` (blind) acceptance test 1 jumps the clock through `_combat_left_s` and never measures 0.6 s — `test_cut_off_timeline` pins the cut-off moment and the 0.6 s hide with exact steps. The level test proves the real box, SFX, camera and silence take part.
  - `[low]` `[patch]` (blind) `_cut_off` used literal key strings and started silence whenever the key was present — it now uses the `DialogueValidator.AFTER_*` constants, and silence starts only for `SILENCE_UNTIL_WAVE_CLEAR`.
  - `[low]` `[reject]` (blind) the music stop and the shake aren't voided when the wave clears first — this is as specified ("effects still run, but no silence"). It only happens when a wave clears within about 0.9 s of the cut-off.
  - `[false]` `[reject]` (blind) the text and the cut point don't match (`cov—` never shows) — that is the point of a cut-off: the architecture's own example pairs this text with `cut_off_at` 39, so the line stops mid-word.
  - `[low]` `[reject]` (blind) the `chars_per_s <= 0` path is untested — tuning is 45 and the panel already warns on a non-positive speed. The guard only prevents a division by zero.
  - `[low]` `[reject]` (blind) `step_combat` moves one phase per call, so a huge delta delays the hide by one frame — nobody would notice a one-frame delay, and the fix adds a fall-through branch.
  - `[low]` `[reject]` (blind) the new level tests undo `Log.sink` and the signal connection only at the end — this matters only after an earlier failure, and it matches the existing test style.
  - `[low]` `[reject]` (blind) the pause-freeze test may wait many frames and reads a private field — test-only style, and no flake was seen.
  - `[low]` `[reject]` (edge) one large delta crosses both phases, and a 0 s hide waits one step — same as the blind step-phase row.
  - `[low]` `[reject]` (edge) a cut-off queued in wave N, or started by a `wave_clear` trigger, silences wave N+1 — same as the blind priority row.
  - `[low]` `[patch]` (edge) an unregistered `after.sfx` passes validation — same root cause and fix as the first blind row.
  - `[low]` `[reject]` (edge) a second cut-off is dropped while an earlier one's silence holds — the game has one cut-off (Tarek, L2).
  - `[false]` `[reject]` (edge) `cut_off_at` under an invalid mode isn't flagged as a cut-off problem — the unknown-mode problem is already reported, so Config leaves the sequence out either way.
  - `[false]` `[reject]` (intent) the AC says "panel" but the code uses the box — UX EXPERIENCE.md:67 says "the box hides after 0.6 s", and the architecture example is combat mode.
  - `[false]` `[reject]` (intent) a story-mode cut-off is rejected — no doc puts a cut-off on the story panel (see the row above).
  - `[low]` `[reject]` (intent) acceptance test 1 is partly synthetic — same as the blind AC 1 timing row.
  - `[low]` `[patch]` (intent) the F3 test fallback — same as the blind F3 row, same fix.
  - `[low]` `[reject]` (intent) "when I play it" and the feel are unverified — handled at finalize: as in Stories 5.1 and 5.2, the play, listen and feel checks are listed under `operator_actions`, and the status is `awaiting-operator`.
  - `[low]` `[reject]` (intent) the extra edge decisions weren't put to the user — they are record-only choices where the docs are silent, and none conflicts with the GDD, architecture or UX. They are recorded in Design Notes and the architecture As-built, as in Stories 5.2 and 5.3.

## Design Notes

**Decisions where the docs are silent** (record-only, none changes a documented rule):
- Cut-off is combat-only. The architecture example, UX EXPERIENCE.md ("the box hides") and `is_interruption` all place it in the interruption box. A story-mode cut-off is a validator problem.
- `until_wave_clear` means the wave the cut-off happened in. If that wave clears before the cut-off moment (F3, or a wave ending within the ~0.9 s of typing), no silence starts. Otherwise it would silence the next wave.
- An early preempt drops the effects with the line. Every combat line is treated alike, and Epic 7 data must not request a story in the same moment as a cut-off.
- `shake` names a tier's shake only. No hit-stop or explosion: the line is a comms effect, not an impact.
- The box hides at once rather than fading. "Hides" plus the static burst reads as a dead channel.

```gdscript
# step_combat, cut-off line: phase TYPING -> (timer 0) _cut_off() -> phase HOLD (cutoff_hide_s) -> hide_now + finish
```

## Verification

**Commands:**
- `uv run python tools/gen_placeholder_sfx.py` (repo root): expected `sfx_comms_static.wav` is written and the other WAVs stay unchanged in `git status`.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import`: expected to complete and create the new `.import` sidecar.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`: expected all tests to pass.

## Auto Run Result

Status: awaiting-operator

**Summary:** A combat comms line can now be cut off mid-sentence.
- It types to exactly `cut_off_at` characters.
- Its `after` effects then run in order: the `comms_static` burst, a shake tier through `Feedback.shake_tier`, a music action and silence.
- The interruption box hides 0.6 s later.
- Silence drops combat sequences (DEBUG log, deferred `finished`) until `Events.wave_cleared`. Story lines still play.
- The validator checks the new keys, and `level_dev.json` wave 2 fires `dev_tarek_cutoff` at progress 0.25.

**Files changed:**
- `game/systems/comms/comms_channel.gd`: the cut-off phases (typing, then a 0.6 s hold), silence, the wave-clear lift and the void rule.
- `game/systems/comms/comms_box.gd`: `show_line(..., cut_off_at)` and `cut_off(chars)`.
- `game/systems/comms/dialogue_validator.gd`: the `cut_off_at` and `after` rules and the `AFTER_*` constants.
- `game/autoloads/feedback.gd`: `shake_tier(tier)` (shake only), sharing `_shake` with `impact`.
- `game/autoloads/audio.gd`, `tools/gen_placeholder_sfx.py`, `game/assets/audio/sfx/sfx_comms_static.wav` (+ `.import`), `game/assets/CREDITS.md`: the `comms_static` placeholder SFX.
- `game/data/dialogue/dev.json`, `game/data/levels/level_dev.json`: the dev cut-off and its progress trigger.
- Tests:
  - `test_comms_channel.gd` and its fixture `channel.json`.
  - `test_comms_box.gd`, `test_dialogue_validator.gd` and `test_feedback.gd`.
  - `test_level.gd`: both acceptance tests.
  - `tests/data/test_data_files.gd`: the `after.sfx` registry check.
- `_bmad-output/game-architecture.md`: cut-off and silence marked built, `Feedback.shake_tier` documented, "As-built 2026-10-08 (Story 5.4)" added.

**Review:** 23 findings: 0 high, 0 medium, 19 low and 4 false. 3 low entries were patched and nothing was deferred. Every row and reason is in the Review Triage Log.
- **Patched (low):**
  - The `after.sfx` registry check in the data test.
  - The channel now uses the validator's `after` constants and starts silence only on the exact value.
  - The F3 acceptance test now asserts the cut-off moment directly.
- **Rejected:**
  - Queue priority and stacked cut-offs.
  - The spec's F3 timing wording (fixing it would mean editing this spec).
  - The jumped clock in the level test.
  - Music and shake not being wave-scoped.
  - The `chars_per_s <= 0` path.
  - The one-frame phase step.
  - Test cleanup and style.
  - Panel vs box and the story-mode ban (false: the UX doc says box).
  - The record-only decisions.

**Follow-up review recommended: false.** Patched by verdict: high 0, medium 0, low 3.

**Verification:**
- `uv run python tools/gen_placeholder_sfx.py`: wrote `sfx_comms_static.wav`, and every existing WAV is byte-identical.
- `--import`: exit 0.
- Full GUT suite headless: 1246/1246 passing after the review patches (1244/1244 before them), with no orphan warnings.
- Every I/O matrix row has a passing test.

**Spec correction:** under F3, level_dev wave 2 doesn't clear while the cut-off types, as the Code Map claims. The reinforcements `wait 1.0` holds the clear until after the cut-off at 0.87 s, so silence starts and `wave_cleared` lifts it. AC 2 holds either way. `test_wave_clear_before_the_cut_off_voids_the_silence` covers the void rule.

**Residual risks:**
- No human has checked the cut-off's look, sound or feel (see `operator_actions`). `comms_static` is a generated placeholder until Epic 8.
- A cut-off that is queued behind combat lines, or requested after its wave clears, can silence the next wave. Epic 7 data should request the Tarek cut-off alone.
- A story requested within about 0.9 s of a cut-off drops the cut-off's effects, including the silence and the music stop.
- One isolated `test_feedback.gd` run printed an ObjectDB leak warning. It didn't recur in later runs.
