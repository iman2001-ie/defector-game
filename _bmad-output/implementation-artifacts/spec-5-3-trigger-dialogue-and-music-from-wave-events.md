---
title: 'Story 5.3: Trigger Dialogue and Music from Wave Events'
type: 'feature'
created: '2026-10-08'
status: 'done'
baseline_revision: '9b05f31455144d5c03dba75327e9fc7bf911bac1'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-5-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-5-2-hear-combat-chatter-without-stopping-the-fight.md'
warnings: ['oversized']
deferred:
  - summary: >-
      The WaveDirector's wave-clear gap still awaits a SceneTreeTimer, which outlives the director, so a death reload during the gap before the next wave or the outro resumes a coroutine on a freed director.
    evidence: |-
      wave_director.gd _try_clear: `await get_tree().create_timer(_gap_s, false).timeout`, unchanged since Story 2.2 and kept on purpose by the Story 5.3 spec ("Leave the _try_clear gap timer as it is"). A level reload frees the director while the timer lives on the SceneTree; on timeout Godot may log "Resumed function after await, but class instance is gone". Not reproduced: a test that frees the director during the gap and checks the error output would settle it. The fix is the same child-Timer pattern used for `wait`.
    location: >-
      game/systems/waves/wave_director.gd _try_clear
    severity: low
  - summary: >-
      Chains that keep running after a death (decision #39, DW-54) now also fire comms, story_event and music, so a chain resuming from a wait during the death beat can open a story pause over the death screen, emit a story event or switch music after the attempt failed.
    evidence: |-
      wave_director.gd _run_chain never checks _failed (by design: decision #39 says "running chains and group spawns still run" after level_failed, and the Story 5.3 intent says not to change the DW-54 failure rules). A level chain such as [wait 2, comms story_x] whose wait ends after the death but before the reload emits comms_sequence_requested; a story sequence then pauses the tree via PauseArbiter on top of the death beat. Not reachable with shipped data (no real level has beats until Epic 7). Settling it needs a human decision extending decision #39: should comms, story_event and music be dropped once _failed is set? The fix would be a `_failed` skip on those three actions plus a test.
    location: >-
      game/systems/waves/wave_director.gd _run_chain
    severity: medium
---

<intent-contract>

## Intent

**Problem:** The WaveDirector logs `comms`, `story_event` and `music` actions as "arrives in Epic 5" and skips them, ignores `intro_sequence` and skips `outro_sequence`, and `Audio` has no music. So no level JSON can script a story beat (FR28, FR39, FR61). Tier: MUST.

**Approach:** Run the three actions inside `WaveDirector._run_chain`: a story-mode `comms` awaits its `comms_sequence_finished`, a combat one doesn't block. Play the intro before wave 1 (skipped when `GameState.is_retry`) and the outro before `level_cleared`. Add music play, switch and fade-stop to the `Audio` autoload. Validate the new data, and make sure no chain survives a level reload.

## Boundaries & Constraints

**Always:**
- **Tuning.** `tuning.json` gains `"audio": { "music_fade_out_s": 0.5 }`. No other new number. Read through `Config`.
- **`Audio` music** (`autoloads/audio.gd`, still `PROCESS_MODE_ALWAYS`):
  - `var music_streams: Dictionary[StringName, AudioStream] = {}` is the music registry. It stays empty until Story 8.1 adds tracks; tests insert streams.
  - Add one `AudioStreamPlayer` child named `Music` on the `Music` bus.
  - `apply_music_action(action: StringName)`: `&"stop"` → `stop_music()`, any other value → `play_music(action)`.
  - `play_music(id)`:
    - Same id already current and not fading: does nothing.
    - Stream missing: `Log.warn("audio", ...)` once per id, stops any current music at once, and leaves the current id `&""` (stays silent).
    - Otherwise: kills any fade, restores the base volume, sets the stream, plays, sets the current id and logs `Log.info("audio", ...)`. This also covers switching (`combat` → `boss`).
  - `stop_music(fade_s: float = -1.0)`: a negative value uses `audio.music_fade_out_s`. It tweens `volume_db` down to -80 over `fade_s`, then stops and restores the base volume. A fade of 0 stops at once, and with nothing playing it only clears the current id. The current id is `&""` from the call on.
  - Accessors: `current_music() -> StringName`, `music_player() -> AudioStreamPlayer`.
  - Update the header doc comment ("Music arrives in a later epic" is now wrong).
- **`WaveDirector`** (`systems/waves/wave_director.gd`):
  - **`comms`:** emit `Events.comms_sequence_requested(StringName(value))` and `Log.info("beat", ...)`. When `Config.dialogue_is_story(id)`, the chain waits until `Events.comms_sequence_finished` carries that id, even if it arrives synchronously during the request emit. Combat and unknown ids don't wait. The channel finishes unknown ids, so nothing hangs.
  - **`story_event`:** emit `Events.story_event_requested(StringName(value))` and log at INFO. **`music`:** `Audio.apply_music_action(StringName(value))`.
  - After every await, a chain of an older wave (`serial != _serial`) returns as `wait` does today.
  - **Reload safety:** every await in a chain, the intro or the outro is on a signal of the director itself or of a node it owns (for example a relay signal fed by an `Events.comms_sequence_finished` connection made in `_ready`, and a one-shot pausable `Timer` child for `wait`). No `SceneTreeTimer` and no direct await on an `Events` signal, so a freed director never resumes one and no "class instance is gone" error appears. `wait` stays pausable with the same duration. Leave the `_try_clear` gap timer as it is.
  - **Intro:** `start_level` bumps `_serial`. When `intro_sequence` is a non-empty string and `GameState.is_retry` is false, it requests the intro the same way as a `comms` action (story waits, combat doesn't), then starts wave 0. After the await, if `_serial` changed (F6 or a new `start_level`), it starts nothing. On a retry it logs "intro skipped (retry)" and starts wave 0 at once. Every `start_level` caller keeps working without `await`.
  - **Outro:** `_finish_level` plays `outro_sequence` the same way (also on retries), then sets `_level_done` and emits `level_cleared`. If `_serial` changed or `_failed` is set after the await, it emits nothing. The "skipped" debug lines go.
  - Update the header doc comment.
- **`LevelValidator`:** `const MUSIC_ACTIONS: Array[String] = ["stop", "combat", "boss"]`. A `music` action outside that set is a problem (`must be one of stop, combat, boss`). Root `intro_sequence` and `outro_sequence` must be absent, `null` or a non-empty string. Update the rules doc comment.
- **Data test:** every `comms` action id and every non-null `intro_sequence`/`outro_sequence` in `data/levels/*.json` passes `Config.has_sequence`, with a self-check on an inline level dict that the collector finds all three kinds.
- Statically typed GDScript, `Log` only (`beat`, `audio`, `data`), no new `Events` signal or autoload, only `PauseArbiter` pauses (via the channel).

**Never:** Don't play the level-root `music` key. Story 5.3's ACs cover actions only; record it in Design Notes. No cut-off, silence or music drop from comms (that is Story 5.4). No hint action (5.8). No listeners for `story_event_requested` (Epic 6). No music assets (8.1). Don't place comms, music or intro/outro into the real level JSONs (Epic 7) or `level_dev.json`: an intro there would pause every level-scene test. Don't change the gap, clear, stall, F3/F6 or DW-54 failure rules, or `CommsChannel`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Story comms blocks | wave_start chain `[comms story_a, story_event e]` | request emitted; `e` not emitted until `finished(story_a)`, then emitted; `running_chains()` 1 until then | none |
| Combat comms doesn't block | `[comms combat_a, story_event e]` | both emitted in the same call | none |
| Unknown comms id | `[comms nope, story_event e]` | request emitted, `e` follows at once | the channel logs it |
| Other id's finished | story_a waiting, `finished(story_b)` | still waiting | none |
| Sync finished | a listener emits `finished(story_a)` inside the request | chain continues | none |
| Story event | `[story_event tarek_fall]` | `story_event_requested(&"tarek_fall")` once | none |
| Music | `music combat`, stream registered | `current_music()` combat, player stream set; `boss` switches; `stop` fades `volume_db` over 0.5 s then stops | none |
| Missing stream | `music boss`, no stream, combat playing | one warn (second call: no new warn), music stopped, current `&""` | `Log.warn` once |
| Clear waits for chain | all enemies killed while a story chain waits | no `wave_cleared` until `finished`, then it clears | none |
| Intro | `intro_sequence: story_a`, not retry | request emitted, no `wave_started` until `finished(story_a)` | none |
| Intro on retry | same, `GameState.is_retry` true | no request, wave 0 starts at once | INFO log |
| Outro | last wave cleared, `outro_sequence: story_b` | request after the gap; `level_cleared` only after `finished(story_b)` | none |
| Death mid-chain | chain waiting on story_a (or in a `wait`), `level_failed`, director freed | later `finished(story_a)` or the elapsed wait runs nothing (no `e`) and logs no engine error | none |
| Bad data | `music: "loud"`; `intro_sequence: ""` or a number | one validator problem each | logged |

</intent-contract>

## Code Map

- `game/systems/waves/wave_director.gd`
  - `start_level` (l.102): reads `_outro_sequence` (l.109). Add `_intro_sequence` and the intro step.
  - `_run_chain` (l.406): the `wait` await (l.416) and the Epic 5 placeholder branch (l.419-420) to replace.
  - `_finish_level` (l.476): the outro placeholder (l.480-481).
  - `_try_clear` (l.452): the gap and `chains_finished` loop. The rule is unchanged.
  - `debug_skip_to_boss` (l.217) calls `start_wave`, which bumps `_serial`.
- `game/systems/waves/beat_trigger.gd`: `flag` with `!` negation already works; no change.
- `game/autoloads/audio.gd`: the SFX pool pattern and warn-once `_warned_ids` (l.29, l.50). Add music beside it. The `Music` bus exists in `default_bus_layout.tres`.
- `game/autoloads/config.gd`: `has_sequence` (l.131) and `dialogue_is_story` (l.136).
- `game/autoloads/game_state.gd`: `is_retry`. `SceneRouter.restart_level` sets it; `start_level` and `goto_title` clear it.
- `game/systems/waves/level_validator.gd`: `ACTION_KEYS` (l.39), the action loop in `_check_trigger` (l.297-321) and root checks in `validate` (l.47).
- `game/data/tuning.json`: add a top-level `audio` section. `game/data/levels/*.json`: every level has `intro_sequence`/`outro_sequence`/`music` set to `null`. Leave them.
- `game/tests/unit/test_wave_director.gd`: fixture (l.17-56), `_wait_real`, `_events_named`, `_kill`, `_start`. Death tests (l.509-620) show the DW-54 style. Free the director with `_root.free()` or `queue_free` and await a frame to simulate the reload. Reset `GameState.is_retry` in `after_each`.
- `game/tests/unit/test_comms_channel.gd`: input helpers `_click` and `_click_to_end_of` (l.118, l.323) for driving a real story sequence. `test_level.gd:817` instances `level.tscn` with the comms layer.
- `game/tests/unit/test_audio.gd`, `test_level_validator.gd`, `tests/data/test_data_files.gd`: `_level_files()` (l.16), the interruption counter (l.546-627) and the pattern for walking level actions.
- `_bmad-output/game-architecture.md`:
  - Audio Architecture "Planned" line (l.334).
  - Wave Director Rules and excerpt (l.795-850).
  - The "Built (Story 5.2)" note (l.~923).
  - Add an "As-built 2026-10-08 (Story 5.3)" section after the last As-built section.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_wave_director.gd`, `test_audio.gd`, `test_level_validator.gd` (write first): one test per I/O matrix row. Drive story finishes by emitting `Events.comms_sequence_finished` directly (no channel in the fixture). Use `_wait_real` or frames, never wall-clock sleeps beyond the short `wait` values. Audio tests insert a generated `AudioStreamWAV` into `music_streams` and restore the registry and music state in `after_each`. Assert on `current_music()`, the player's `stream` and `volume_db`, and rely on `playing` only if it is reliable headless.
- `game/autoloads/audio.gd`, `game/data/tuning.json`: music as specified.
- `game/systems/waves/wave_director.gd`: actions, intro, outro, reload-safe awaits.
- `game/systems/waves/level_validator.gd`: music values and intro/outro shape.
- `game/tests/data/test_data_files.gd`: referenced ids exist (plus the self-check), and `audio.music_fade_out_s` is 0.5.
- `game/tests/unit/test_level.gd`: the surface test (AC 1).
- `_bmad-output/game-architecture.md`: mark the actions, intro/outro and music as built, record the Design Notes decisions, and add an As-built (Story 5.3) section.

**Acceptance Criteria:**
- Given the level scene (real `CommsChannel`) and its WaveDirector restarted with an inline level whose wave-1 `wave_start` chain is `[comms dev_comms_check, story_event dev_evt]`, when the level runs, then the tree pauses with the `story` reason and `dev_evt` hasn't fired. When the story is clicked through, `story_event_requested(&"dev_evt")` fires after the pause lifts.
- Given the full GUT suite, when it runs headless, then every test passes with no new orphan or engine-error output.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 26 findings — high 0, medium 0, low 22, false 4, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) `_play_intro` ignores `_failed`, so a death during a story intro still starts wave 1, contradicting the as-built doc — added `or _failed` to both post-await checks and `test_death_during_the_intro_starts_nothing`.
  - `[low]` `[defer]` (blind) the `_try_clear` gap still awaits a `SceneTreeTimer` that outlives the director — this predates the story (Story 2.2) and the spec kept it on purpose; deferred with the evidence that would settle the engine-error question.
  - `[low]` `[reject]` (blind) music has no teardown on a scene change — no track exists until Story 8.1, so every `play_music` stays silent today; what music does across retry or title is Story 8.1's design choice and would add branches. Listed under residual risks.
  - `[low]` `[patch]` (blind) the fade tween follows `Engine.time_scale`, so Feedback's hit-stop (time_scale 0) freezes it — added `set_ignore_time_scale(true)` to the fade tween.
  - `[low]` `[patch]` (blind) the reload tests don't assert the director was freed, and nothing covers a freed waiting intro — added the `is_instance_valid` assert to the wait test and `test_death_reload_drops_a_waiting_intro`. GUT fails on unexpected engine errors, and the run output has none, so the no-error claim is covered.
  - `[low]` `[reject]` (blind) the fade tests sample with real `wait_seconds` and could flake — they have 0.1-0.25 s of slack against a 0.5 s fade, and making them deterministic would mean a test-only clock in `Audio`.
  - `[low]` `[reject]` (blind) validator gaps: the root `music` key is unvalidated, `MUSIC_ACTIONS` is hard-coded, ids aren't checked at load — the root key is unread by design; the three values are the AC's enumerated schema, not a tuning number; the data test already checks that every referenced id exists.
  - `[low]` `[reject]` (blind) the wait-for-story loop is repeated three times — the exit conditions differ on purpose (DW-54: chains keep running after a death, while the intro and outro stop), and the real bug it caused is fixed above.
  - `[low]` `[reject]` (blind) the `_is_fading()` guard in `play_music` is dead — harmless; `play_music(&"")` is unreachable from validated data.
  - `[low]` `[reject]` (blind) F3 during a story outro logs "resolving" and then does nothing — debug-only, and the tree is paused by the story outro.
  - `[low]` `[reject]` (blind) `start_level` leaves earlier-level state during the intro, and `_finished_counts` grows — `start_level` runs once per scene instance (reloads make a new director); the dictionary holds a few ids.
  - `[low]` `[reject]` (blind) a `wait` outside the tree is skipped silently — chains only run in the tree; nothing reaches this.
  - `[false]` `[reject]` (blind) a story intro could hang if requested before the channel listens — `CommsChannel` connects in its `_ready` (comms_channel.gd:79), and child `_ready`s run before `level.gd`'s `_ready`, which calls `start_level`.
  - `[low]` `[reject]` (blind) duplicated WAV helper and test access to `Audio._warned_music` — test-only style with no named harm.
  - `[low]` `[patch]` (edge) intro ignores a death — same root cause as the first blind row; same fix.
  - `[low]` `[patch]` (edge) `stop_music(0.0)` during a running fade returns early and doesn't stop — `stop_music` now kills a running fade and stops at once when the fade is <= 0; added `test_zero_fade_stop_during_a_fade_stops_at_once`.
  - `[low]` `[reject]` (edge) a non-looping track that ends leaves `current_music()` stale — there are no tracks until Story 8.1, and music tracks are imported looping.
  - `[low]` `[patch]` (edge) the director test's `_silent_wav` is a 0.1 s non-looping clip, so the "stopped after fade" assert passes trivially — made it loop.
  - `[low]` `[reject]` (edge) F3 or a failure during a story outro — the story outro pauses the tree, so neither a death nor gameplay can happen; F3 is debug-only (same as the blind F3 row).
  - `[low]` `[patch]` (verification-gap) no test for a death during the intro — same fix as the first blind row; the test was added.
  - `[low]` `[patch]` (verification-gap, other) the intro `_failed` doc/code contradiction — same as above.
  - `[low]` `[reject]` (verification-gap, other) the `wait: 0` and not-in-tree changes are unpinned — intended by the spec ("0 continues at once"), and nothing in shipped data uses `wait: 0` in a chain.
  - `[false]` `[reject]` (intent) the level-root `music` key isn't played — no Story 5.3 AC asks for it and the key was unread before this change, so no behaviour regressed; the decision is recorded in Design Notes and the architecture.
  - `[low]` `[reject]` (intent) tests use inline dicts and a simulated reload instead of level files and `SceneRouter` — the real `level.tscn` test covers the channel and the pause; the intro and outro use the same `_request_sequence` path; no real level has beats until Epic 7.
  - `[false]` `[reject]` (intent) music isn't verified audibly — there are no tracks (Story 8.1); the AC's missing-stream behaviour is what runs today and is tested.
  - `[false]` `[reject]` (intent) the operator path — not a defect: the story has no human-only external action, so it finishes as `done`.

### 2026-10-08 — Review pass
Resumed after deterministic verification failed: `test_audio.gd` failed when run alone. Cause: just after engine start, a tween with `set_ignore_time_scale(true)` gets an unscaled step of over 1 s in one frame, so the 0.5 s fade ended before the 0.25 s sample. Repair: the fade tests first wait for the unscaled clock to settle (`tests/fixtures/unscaled_clock.gd`). Product code is unchanged.
- verdicts: 21 findings — high 0, medium 2, low 17, false 2, maybe-false 0
- findings:
  - `[medium]` `[defer]` (blind) after a death, chains still fire comms, story_event and music. A story pause, story event or music switch can land on the death screen — verified: `_run_chain` never checks `_failed`, as decision #39 ("running chains … still run") and the intent's "don't change the DW-54 failure rules" require. Changing it means amending a recorded user decision, so it is deferred for a human decision.
  - `[low]` `[reject]` (blind) a story wait can hang with no log or watchdog — the real channel finishes every request (unknown ids included) and the "comms '<id>'" INFO line names the waited id. A watchdog would add branches for a path no shipped scene reaches.
  - `[low]` `[patch]` (blind) the `test_wave_director.gd` fade test flakes when run first or alone — confirmed 0/1 when run alone. It now awaits the shared `UnscaledClock.settle` and passes alone.
  - `[low]` `[patch]` (blind) the clock-settle helper gives up silently — `settle()` now returns false when the clock never settles, and every fade test asserts on that result.
  - `[low]` `[reject]` (blind) the triage points to a residual-risks section that doesn't exist — the fix would edit this spec. The Auto Run Result below lists the music-teardown risk.
  - `[low]` `[reject]` (blind) no test for two chains released by one `finished` — a record-only design note that follows from the count snapshot. Story ids are per-beat, so no level requests one twice at once.
  - `[low]` `[reject]` (blind) no tests for a combat or unknown-id intro or outro — these share `_request_sequence`'s -1 return with the tested combat intro and the combat and unknown `comms` actions. Nothing ships with an outro until Epic 7.
  - `[low]` `[reject]` (blind) no story-intro test in the real `level.tscn` — the scene's child `_ready`s run before `level.gd` calls `start_level` (engine order, not a choice), and the scene test already covers the real channel through the same request path.
  - `[low]` `[reject]` (blind) the spec doesn't record that verification ran — the fix would edit this spec. The Auto Run Result below records it.
  - `[low]` `[reject]` (blind) the player-facing decisions aren't in the GDD decision log — AGENTS.md puts user decisions there. These are record-only agent decisions, kept in Design Notes and the architecture As-built that Epic 7 reads.
  - `[low]` `[reject]` (blind) carried: the level-root `music` key is ignored with no message — same claim as the earlier validator-gaps row: the key is unread by design and recorded in Design Notes.
  - `[medium]` `[defer]` (edge) a comms, story_event or music action fires after `_failed` — same root cause as the first row; same deferral.
  - `[low]` `[patch]` (edge) the director fade test flakes when its script runs first or alone — same root cause and fix as the blind flake row.
  - `[low]` `[reject]` (edge) a second request for a story id while the first copy is still showing is released by the first copy's `finished` — needs the same per-beat id requested twice at once, which no level does. Per-request tokens would add public surface to the channel contract.
  - `[false]` `[reject]` (edge) `start_level` could run before `_ready` connects the relay — every caller adds the director to the tree first: `level.gd` from its own `_ready`, after the child director's `_ready`, and the test fixture adds `_root` before `_start`.
  - `[low]` `[patch]` (verification-gap) F6 while a chain waits on a story comms is untested — added `test_f6_abandons_a_chain_waiting_on_a_story`. Removing the comms-loop serial guard makes it fail (`e` emitted, `running_chains` -1).
  - `[low]` `[reject]` (verification-gap) the fade's immunity to hit-stop is untested — a test would have to drive `Engine.time_scale`, which only `Feedback` may touch, around a hit-stop of a few frames. No track exists until Story 8.1, so it's listed under residual risks.
  - `[low]` `[reject]` (intent) carried: tests use inline dicts and hand-emitted signals rather than level files — same as the earlier row.
  - `[low]` `[defer]` (intent) carried: the reload promise against the `_try_clear` gap `SceneTreeTimer` — already in `deferred`; not deferred again.
  - `[low]` `[reject]` (intent) carried: `wait: 0` now continues in the same call — same as the earlier row.
  - `[false]` `[reject]` (intent) the validator message adds a `not '<x>'` suffix, and the F3 test's expected lines changed — the message still contains the required text, and the F3 lines follow from removing the placeholder logs the intent asked to drop. Neither is a defect.

## Design Notes

**Decisions where the docs are silent** (all record-only, none changes a documented rule):
- A combat-mode `intro_sequence`/`outro_sequence` doesn't block, like a combat `comms` action.
- The outro also plays on a retry. The AC skips only the briefing.
- The level-root `music` key stays unread. No story AC plays it, so levels start music with a `music` action (for example on `wave_start`). Story 8.1 or Epic 7 can wire the root key.
- A missing stream stops the current track, so "stays silent" holds after a switch.
- Two chains waiting on the same story id are both released by its single `finished`. That is acceptable because ids are per-beat.

**Why director-owned awaits:** a `SceneTreeTimer` or an `Events` signal outlives the reloaded level, so a chain awaiting one would resume on a freed director. Awaiting the director's own signal or child `Timer` drops the coroutine with the node.

```gdscript
signal _sequence_done(id: StringName)   # fed from Events.comms_sequence_finished in _ready
# chain: Events.comms_sequence_requested.emit(id); if story: while not done(id): await _sequence_done
```

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import`: expected to complete.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`: expected all tests to pass.

## Auto Run Result

Status: done

**Summary:** This resumed session repaired the deterministic verification failure: `test_audio.gd` failed when run alone. Story 5.3's product code, committed in c4f2c6b, is unchanged. Its behaviour:
- Level JSON can script the story. The WaveDirector runs `comms` (story mode waits for `finished`), `story_event` and `music` actions.
- The intro plays before wave 1 and is skipped on a retry. The outro plays before `level_cleared`.
- Every await is reload-safe.
- `Audio` can play, switch and fade-stop music. `LevelValidator` checks music values and the intro/outro shape.

**Root cause of the failure:** just after engine start, the unscaled clock behind a tween with `set_ignore_time_scale(true)` jumps more than a second in one frame. When a fade test ran first or alone, the 0.5 s music fade ended before the 0.25 s sample. In the full suite these tests run long after startup, so they passed. The fade tests now wait for that clock to settle first. The music fade code was not changed.

**Files changed (this session):**
- `game/tests/fixtures/unscaled_clock.gd`: new test helper. `settle(node)` waits until a time-scale-ignoring tween steps in line with the frame delta (once per run) and returns false if it never does.
- `game/tests/unit/test_audio.gd`: the three fade tests assert `UnscaledClock.settle(self)` first.
- `game/tests/unit/test_wave_director.gd`: the music fade test settles the clock first. New `test_f6_abandons_a_chain_waiting_on_a_story`.
- This spec: the triage log, one deferred item and this result.

**Review:** 21 findings. 3 patched (all low), 1 new deferral (medium, both layers), 1 carried deferral not re-added, 2 false, the rest rejected. Every reason is in the Review Triage Log.
- **Patched (low):**
  - The director fade test flaked when run alone.
  - The settle helper gave up silently.
  - F6 abandoning a chain that waits on a story had no test.
- **Deferred (medium, needs a human decision):** chains that run after a death (decision #39) now also fire comms, story_event and music. A story pause could land on the death screen. Changing that means amending decision #39.
- **Rejected:** a watchdog for story waits; tests for same-id waiters, combat/unknown outros and a real-scene intro; per-request tokens; decision-log placement; the root `music` key (carried); spec-edit-only items; a hit-stop fade test.

**Follow-up review recommended: false.** Only low entries were patched (3 low, 0 medium, 0 high).

**Verification:**
- `--import`: exit 0.
- Full GUT suite headless: 1217/1217 passing.
- Each of the 75 `test_*.gd` files run alone with `-gselect` (the verifier's isolation loop): all pass. `test_audio.gd` passed 5/5 repeated runs alone.
- Each fade test and the new F6 test also pass with `-gunit_test_name` alone.
- The new F6 test fails when the comms-loop serial guard is removed.

**Residual risks:**
- No music track exists until Story 8.1, so music is never audible yet. Music has no teardown: across a death reload, a retry or a return to title it keeps playing and `current_music()` stays set. Story 8.1 must decide this.
- The fade's immunity to hit-stop has no test.
- The level-root `music` key stays unread. Levels must start music with a `music` action.
- No real level uses comms, intro, outro or music until Epic 7.
- The deferred decision on beat actions after a death needs a human answer before Epic 7 scripts a wait followed by a comms.
