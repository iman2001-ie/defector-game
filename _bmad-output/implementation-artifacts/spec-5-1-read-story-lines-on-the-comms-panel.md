---
title: 'Story 5.1: Read Story Lines on the Comms Panel'
type: 'feature'
created: '2026-10-08'
status: 'awaiting-operator'
operator_actions:
  - 'Run the level scene in a debug build with `-- --comms=dev_comms_check` and confirm the playfield dims, the HUD stays visible but frozen, and the centred panel matches the UX layout (portrait left, accent-coloured uppercase name, typing text, a readable `click to continue ▸` cue bottom-right, no buttons).'
  - "Confirm the comms-open sound plays when the panel opens and sounds like a radio channel opening, not a glitch."
  - "Confirm the long Isolde line shows all of its text (nothing clipped at the bottom) and the Vale line uses the full-width, no-portrait layout."
  - 'Click while a line types to complete it, click again to advance, and confirm the final click closes the panel without firing a laser shot.'
  - 'With a line showing, press Esc, then Esc again, and confirm the game stays paused on the story line with only one dim layer visible.'
baseline_revision: 'd3f677cb8ad5db151e7fd6158702278b67ab5a82'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-5-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/EXPERIENCE.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The game has the `Comms` CanvasLayer (layer 20) in `level.tscn`, the `Events.comms_sequence_requested` / `comms_sequence_finished` signals, the `comms_advance` action and `tuning.comms.chars_per_s`, but nothing loads dialogue or shows it. Story beats can't be delivered. This story covers FR37, FR38 (story mode), FR39 and FR8 (comms advance). Tier: MUST.

**Approach:** `Config` loads every `data/dialogue/*.json` file, validates each sequence with a new `DialogueValidator`, and serves `sequence(id)` / `dialogue_is_story(id)`. A `CommsChannel` node (under `Comms`) listens for requests. For a story sequence it pushes the `story` pause, plays a new `comms_open` SFX and drives a `CommsPanel` view: a centred conversation panel over a dim, with a placeholder portrait, an accent-coloured name, typewriter text and a `click to continue ▸` cue. A click completes the line, the next click advances, and after the last line the channel pops the pause and emits `finished`.

## Boundaries & Constraints

**Always:**
- **Data** `game/data/dialogue/<scene>.json`, shape `{ "sequences": { "<id>": { "mode": "story"|"combat", "lines": [ { "speaker": "...", "text": "..." } ] } } }`. Add `game/data/dialogue/dev.json` with one story sequence `dev_comms_check`: 3-4 placeholder lines covering a portrait speaker (`tarek`, `isolde`) and a no-portrait speaker (`vale`), one line near 200 characters so a human can check the wrap. Placeholder text is fine (Story 5.7 writes the script).
- **`DialogueValidator`** (`game/systems/comms/dialogue_validator.gd`, `class_name`, static, modelled on `LevelValidator`). It has `const SPEAKERS: Array[StringName] = [&"vale", &"isolde", &"tarek", &"ryn", &"system"]` and `const MODES = [&"story", &"combat"]`. `validate(data: Dictionary, path: String, story_max_chars: int) -> Array[String]` returns one message per problem, each naming the path and sequence id: `sequences` missing or not an object; a sequence that isn't an object; an unknown `mode`; `lines` missing, not an array or empty; a line that isn't an object; an unknown `speaker`; `text` missing, not a String or empty after `strip_edges()`; story-mode `text` longer than `story_max_chars`. It also offers `validate_sequence(id, seq, path, story_max_chars) -> Array[String]`, which `validate` uses. Combat-specific limits are Story 5.2's.
- **`Config`**:
  - `const DEFAULT_DIALOGUE_DIR := "res://data/dialogue/"`.
  - `load_data(tuning_path, flags_path, dialogue_dir := DEFAULT_DIALOGUE_DIR)` loads dialogue after tuning, so the max comes from `tuning.comms.story_line_max_chars`. Files are every `*.json` in the dir, sorted by name. A file that is missing, fails to parse or isn't an object is `Log.error`ed and skipped. Every validator problem is `Log.error`ed (`data`), and a sequence with any problem is left out. A duplicate id across files is `Log.error`ed and the first one wins. A missing dir logs an error and leaves dialogue empty.
  - `reload()` re-reads the dialogue dir too. A dialogue file that fails to parse is a reload problem (the reload is rejected and the previous data kept); validator problems are only logged. On success it commits the dialogue with tuning and flags.
  - `sequence(id: StringName) -> Dictionary` returns a deep copy, or `{}` for an unknown id with no log or assert (the channel reports it). `has_sequence(id) -> bool`. `dialogue_is_story(id) -> bool` is true only for a known story-mode sequence.
  - After loading, log one extra `Log.info("data", "Loaded %d dialogue sequences from %s")` line. Don't change the existing summary line's format (`test_boot` and the boot summary pin it).
- **`tuning.json`**:
  - `comms.story_line_max_chars: 200`.
  - `comms.speakers`: `{ "vale": { "name": "VALE", "portrait": false }, "isolde": { "name": "ISOLDE", "portrait": true }, "tarek": { "name": "TAREK", "portrait": true }, "ryn": { "name": "RYN", "portrait": true }, "system": { "name": "SYSTEM", "portrait": false } }`.
  - `ui.comms_panel`: `{ "x": 410, "y": 300, "w": 1100, "h": 300, "padding_px": 32, "portrait_px": 200, "portrait_gap_px": 24, "name_h_px": 36, "name_gap_px": 8, "cue_h_px": 24 }`. The text block is 812 px wide with a portrait and 1036 px without one.
- **Theme** (`defector_theme.tres`), type `CommsPanel`:
  - colors: `dim` (0,0,0,0.6), `text` #E8F4FF, `muted` #93A7C2, and one per speaker id (`isolde` #FF6AE3, `tarek` #3DF2FF, `ryn` #7CFFB2, `vale` #E8F4FF, `system` #93A7C2)
  - font_sizes: `text` 30, `name` 28, `cue` 20
  - styles: `panel`, a new StyleBoxFlat with `surfaceAlt` fill rgba(10,18,34,0.85), a 1px #2A3B5C border and 4px corners
  - The portrait frame is the only per-node style override (a StyleBoxFlat border in the speaker accent).
- **`CommsPanel`** (`game/systems/comms/comms_panel.tscn` + `.gd`, `class_name`, `Control` full-rect, `PROCESS_MODE_ALWAYS`, `mouse_filter` IGNORE on it and every child). Children: `Dim` (ColorRect), `Panel`, and inside the Panel `Portrait` (a Panel frame plus a centred initial-letter Label in the accent, as the placeholder), `Name`, `Text` and `Cue`.
  - `Text` is a Label with autowrap (word-smart), clip text and `visible_characters_behavior` set to chars-after-shaping. `Cue` is the lowercase `click to continue ▸` in `muted`, right-aligned at the bottom.
  - It is a view only. It never reads dialogue data, and only `CommsChannel` calls it:
    - `open()` shows the Dim and the panel.
    - `close()` hides everything and kills the tween.
    - `show_line(speaker: StringName, text: String)` sets the uppercase name from `comms.speakers` in the accent colour, shows the portrait only when `portrait` is true, re-lays out the text block for the portrait or no-portrait variant, sets the text and types it.
    - `is_typing() -> bool`, `complete_line()`.
  - The typewriter tweens `visible_characters` from 0 to the character count over `count / chars_per_s` s. The tween is created on the panel and keeps running while paused (`TWEEN_PAUSE_PROCESS`).
  - `static func layout(...)` returns the panel, portrait, name, text and cue rects from the `ui.comms_panel` numbers, like `PauseMenu.panel_rect`. The panel starts hidden. Tuning and Theme values are cached in `_ready`.
- **`CommsChannel`** (`game/systems/comms/comms_channel.gd`, `class_name`, `Node`, `PROCESS_MODE_ALWAYS`) with `@export var panel: CommsPanel`. In `level.tscn`, add `Comms/CommsChannel` and `Comms/CommsPanel` (instance) and wire the export.
  - It connects `Events.comms_sequence_requested`.
  - **Unknown id:** `Log.error("comms", "Unknown comms sequence '%s'" % id)`, then emit `comms_sequence_finished(id)` with `call_deferred`.
  - **Combat mode** (Story 5.2 builds it): `Log.warn("comms", ...)` and a deferred `finished`, with no pause and nothing shown.
  - **Story mode while idle:** `PauseArbiter.push(&"story")`, `Audio.play_sfx(&"comms_open", 0.0)`, `panel.open()`, show line 0, and `Log.info("comms", "Story sequence '<id>' started (<n> lines)")`.
  - **Story mode while a story plays:** append the id to a FIFO and never drop it.
  - **Input:** `_unhandled_input` acts only while a story is showing and the `menu` reason is not active. A `comms_advance` press or release (echoes ignored) is always consumed with `get_viewport().set_input_as_handled()`. A press arms the channel. A release that is armed disarms it and advances. A release that isn't armed (the button was held down from before the panel opened) is consumed and ignored.
  - **Advance:** while typing, `panel.complete_line()`. Otherwise show the next line. After the last line, emit `finished(id)` and log `Story sequence '<id>' finished`. If the queue isn't empty, start the next sequence without popping the pause, playing `comms_open` again because it is a new conversation. Otherwise `panel.close()` and `PauseArbiter.pop(&"story")` **before** emitting `finished`.
  - `current_sequence() -> StringName` (`&""` when idle) and `is_showing() -> bool` are read accessors.
- **`comms_open` SFX**: add a `comms_open()` generator to `tools/gen_placeholder_sfx.py` with its own seed (`COMMS_OPEN_SEED = 5101`, so the existing WAVs stay byte-identical). It is a short (about 0.25 s) radio-open blip: two quick rising sine chirps plus a little band-limited static. Generate `game/assets/audio/sfx/sfx_comms_open.wav`, register `&"comms_open"` in `Audio.SFX`, add the CREDITS row, and run `--import` so the `.import` sidecar exists and is committed.
- **One dim:** `PauseMenu.open()` hides its own `Dim` while `PauseArbiter.has_reason(&"story")` and shows it otherwise, because the UX rule says one dim layer, never stacked. Nothing else in the pause menu changes.
- **Debug seam:** `DebugArgs.parse` gains `--comms=<id>`, returned as `"comms": StringName` (`&""` when absent). In debug builds only, after `start_level`, `Level._ready` emits `Events.comms_sequence_requested` with `call_deferred` for that id, so a human can see the panel before Story 5.3's triggers exist (`... -- --comms=dev_comms_check`). The level keeps a static `debug_comms_id(debug_build, args) -> StringName` helper like `should_prewarm`.
- Statically typed GDScript. Logging through `Log` (`comms`, `data`), no `print()`. Only `PauseArbiter` pauses or touches `mouse_mode`. No tuning number in code. Tests follow the existing fixtures: `Log.sink` capture, and `after_each` runs `Config.load_data()`, `PauseArbiter.clear()` and resets the gameplay mouse mode.

**Never:** No interruption box, no combat timing, no priority or preemption, no cut-off, no silence, no music, no Final Choice, no story scene, no `intro_sequence`/`outro_sequence`, no WaveDirector `comms` action, no control hints (Stories 5.2-5.8, 7.x). No dialogue plugin, no new autoload, no new input action, no new `Events` signal, no new Log category. No real portrait art (Epic 8). Don't change `Player`, `PauseArbiter` or `WaveDirector`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Story starts | request `dev_comms_check` | `story` reason active, tree paused, `comms_open` played, Dim + panel visible, name/accent of line 0, `visible_characters` 0 then rising | none |
| Typing speed | 45-char line, chars_per_s 45 | fully typed after ~1.0 s of process time (not before ~0.9 s) | none |
| Complete line | press + release while typing | line fully visible, same line index, still paused, both events handled | none |
| Advance | press + release on a complete line | next line shown and typing | none |
| Finish | release on the last complete line | panel hidden, `story` popped (tree unpaused), then `finished(id)` once | none |
| Unarmed release | release with no press since open | consumed, nothing advances | none |
| Menu over story | `menu` reason active, click | not handled by the channel, nothing advances | none |
| Esc + close menu | Esc opens menu, Esc again | `story` still active, tree paused, pause menu's Dim hidden while story active | none |
| No-portrait | `vale` line | portrait hidden, text block 1036 px wide | none |
| Unknown id | request `nope` | no pause, nothing shown, `finished(&"nope")` on the next idle frame, not during the emit | `Log.error` `[comms]` naming the id |
| Combat id | request a combat sequence | no pause, nothing shown, deferred `finished` | `Log.warn` (Story 5.2 pending) |
| Queued story | second story requested while one plays | first finishes, second starts without the tree unpausing; `finished` once each in order | none |
| Bad data | fixture dir: unknown speaker, bad mode, empty lines, empty text, 201-char story text, non-object line, duplicate id, bad JSON file | each problem `Log.error`ed with path + id; bad sequences absent; the good one present | logged, skipped |

</intent-contract>

## Code Map

- `game/autoloads/config.gd` -- `load_data` (l.29), `reload` (l.47) with `_check_shape`, `_read_json_dict` (l.217), `level_at` + `LevelValidator` call (l.115) as the validate-and-log pattern. Add the dialogue store, loader and getters here.
- `game/systems/waves/level_validator.gd` -- the static-validator style to mirror (message format, path prefix).
- `game/autoloads/events.gd:31-35` -- comms signals already exist; read-only.
- `game/autoloads/pause_arbiter.gd` -- `push`/`pop`/`has_reason`/`clear`; read-only. Popping the last reason emits `resumed`, and the Player warps the cursor back onto the ship.
- `game/autoloads/audio.gd:9-20` -- the `SFX` registry; add `comms_open`. `game/tests/unit/test_audio.gd:48` `test_registry_streams` lists the ids; add it.
- `tools/gen_placeholder_sfx.py` -- per-sound seeds (l.21-26), the `sounds` dict in `main()`. `game/assets/CREDITS.md` has the placeholder table.
- `game/scenes/level/level.tscn` -- the `Comms` CanvasLayer (layer 20) between HUD (10) and Overlay (30); add the two nodes. `game/scenes/level/level.gd` -- `_ready` order and the `should_prewarm` static-helper pattern for the debug comms request.
- `game/ui/debug/debug_args.gd` -- `parse` returns a Dictionary; add `comms`. `game/tests/unit/test_debug_args.gd` has its tests.
- `game/ui/menus/pause_menu.gd` -- `open()` (l.~125) and `_dim`; `game/ui/menus/pause_menu.tscn` for the Panel/Label layout and Theme idiom (`get_theme_color(..., THEME_TYPE)` then child overrides).
- `game/ui/theme/defector_theme.tres:86-125` -- `[resource]` type entries (`PauseMenu/...`); `load_steps` must grow with the new sub_resource.
- `game/entities/player/player.gd:159-163` -- the laser polls `Input.is_action_pressed(&"fire_laser")` (same LMB as `comms_advance`) only while unpaused, and `set_input_as_handled` doesn't change `Input` state. That is why the pause must lift on release.
- `game/data/tuning.json:217` -- the `comms` section; `ui` at l.274.
- `game/tests/data/test_data_files.gd` -- add the dialogue checks. `game/tests/unit/test_config.gd`, `test_pause_menu.gd` (fixture, `Log.sink`), `test_level.gd` (level scene instancing with injected `user_args`/`change_scene`), and `test_boot.gd` (pins the summary line).
- `_bmad-output/game-architecture.md` -- Comms Channel section (l.~855-925), Data Patterns "Planned (Epic 5)" (l.1155), and the getters note (l.454). Mark them as built.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_dialogue_validator.gd`, `test_comms_channel.gd`, `test_comms_panel.gd` (new, write first) -- every I/O row. Drive input with `InputEventMouseButton` (LMB, pressed/released) through `get_viewport().push_input` and check `is_input_handled()`. Advance the typewriter with `await` frames or call the tween step via `complete_line`, never wall-clock sleeps. The panel layout rects are checked against the UX numbers (panel 410,300,1100,300; text block 812/1036).
- `game/tests/fixtures/dialogue/` (new) -- the bad-data and duplicate-id fixture files, plus a combat sequence and a two-story fixture used by the channel tests.
- `game/systems/comms/dialogue_validator.gd`, `comms_channel.gd`, `comms_panel.gd`, `comms_panel.tscn` -- as specified.
- `game/autoloads/config.gd` -- dialogue loading, reload and getters. `game/tests/unit/test_config.gd` -- getters, reload rejects a bad dialogue file, missing dir.
- `game/data/dialogue/dev.json`, `game/data/tuning.json`, `game/ui/theme/defector_theme.tres` -- data and theme as specified.
- `game/tests/data/test_data_files.gd` -- every file in `res://data/dialogue/` validates with no problems, `dev_comms_check` loads and is story, every `DialogueValidator.SPEAKERS` id has a `comms.speakers` entry with a non-empty name and a bool `portrait`, and `chars_per_s` > 0.
- `tools/gen_placeholder_sfx.py`, `game/assets/audio/sfx/sfx_comms_open.wav` (+ `.import`), `game/autoloads/audio.gd`, `game/assets/CREDITS.md`, `game/tests/unit/test_audio.gd` -- the new SFX.
- `game/scenes/level/level.tscn`, `level.gd`, `game/ui/debug/debug_args.gd`, `game/tests/unit/test_debug_args.gd`, `game/tests/unit/test_level.gd` -- wiring and the debug seam. The level test checks that the level has a `Comms/CommsChannel` with a valid `panel`, and that `--comms=<id>` in a debug build requests it.
- `game/ui/menus/pause_menu.gd`, `game/tests/unit/test_pause_menu.gd` -- the single-dim rule.
- `_bmad-output/game-architecture.md` -- mark the Comms Channel story path, `Config.sequence`/`dialogue_is_story`/`has_sequence` and `DialogueValidator` as built (Story 5.1), add the advance-on-release note, and add an "As-built 2026-10-08 (Story 5.1)" section after the last As-built section.

**Acceptance Criteria:**
- Given the level scene running, when `Events.comms_sequence_requested(&"dev_comms_check")` is emitted, then the game pauses with the playfield dimmed and the HUD frozen, the comms-open SFX plays, and the centred panel shows the portrait (or the no-portrait variant), the uppercase accent name and the typing text with the `click to continue ▸` cue, and no buttons.
- Given a story line is showing, when the player clicks through it to the end, then no laser bolt is fired by any of those clicks (a level-scene test: hold no fire before, run press/release pairs through the real input path to the end, step physics frames and count `laser_bolt` nodes = 0 with the Player's fire state idle).
- Given the full GUT suite, when it runs headless, then every test passes with no new orphan warnings.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 26 findings — high 1, medium 1, low 13, false 11, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) the deferred unknown-id `finished` and advance-on-release are recorded as "no design decision changed", and epic-5-context still says "immediately" -- the epic-5-context line now says deferred within the same frame, and the architecture's As-built line names both rule refinements.
  - `[medium]` `[patch]` (blind) an empty sequence id (`""` key) passes validation and soft-locks the game (`_current = &""` reads as idle while `story` is pushed) -- `DialogueValidator.validate_sequence` now rejects an empty or blank id, so Config leaves it out; validator and Config fixture tests were added.
  - `[low]` `[reject]` (blind) with no panel, a story becomes an invisible pause -- `level.tscn` always wires the panel (`test_comms_channel_and_panel_in_the_comms_layer` pins it) and a null panel logs an error; guarding it adds a branch for a misconfiguration the shipped scenes can't reach.
  - `[high]` `[patch]` (blind) a 200-character story line may not fit the text block -- confirmed by a headless measurement: 30 px text is 42 px per line plus a 3 px Label `line_spacing`, so the 168 px block showed 3 of 4 lines and dev.json's 195-character line lost its last line. Added `CommsPanel/constants/line_spacing = 0`, applied to the Text label, and a regression test (both panel variants, the dev line and a 200-character sentence; it fails with spacing 3).
  - `[low]` `[reject]` (blind) a missing dialogue dir is fatal on reload but not at boot -- the dir is tracked in the repo; only a deleted folder triggers it, and the reload is then rejected with a clear log line.
  - `[low]` `[reject]` (blind) a rejected reload still logs dialogue validator problems -- the logged problems are true facts about the files on disk; reworking the log order adds complexity for a debug-only F5 path.
  - `[low]` `[reject]` (blind) `--comms=<id>` replays on every retry -- a debug-only check seam; replaying it on a reload is harmless (one click-through) and arguably expected.
  - `[false]` `[reject]` (blind) the acceptance test can leave LMB held if an assertion fails mid-loop -- GUT assertions don't abort the test, so the release and mouse restore at the end always run.
  - `[low]` `[reject]` (blind) no test for a listener that requests a story inside the `finished` handler -- with the queue empty the pause pops and is pushed again in the same frame, and `resumed` only warps the cursor onto the ship; Story 5.3 tests its own chains.
  - `[false]` `[reject]` (blind) the typewriter-under-pause test proves little -- `chars_per_s` is 45 from tuning, so a tween is always created, and the test reaches -1 only through `_on_typed` after the tween finished while `story` was pushed; that is the required behaviour.
  - `[low]` `[reject]` (blind) a dialogue file with zero sequences passes -- unlikely in practice and adds a new rule; a missing id would surface as "Unknown comms sequence" at play time and fail level-reference checks from Story 5.3.
  - `[low]` `[reject]` (blind) the portrait frame StyleBox is duplicated per line -- once per line shown, never per frame; negligible.
  - `[medium]` `[patch]` (edge) an empty-string sequence id soft-locks the game -- same defect as the blind empty-id row; same fix.
  - `[false]` `[reject]` (edge) a stale armed flag across the pause menu advances on a click that started before the menu -- after the menu closes, the next click's press re-arms anyway, so the advance happens on the same release either way; the only other case is a deliberate press, Esc, Esc, release, which is a real click.
  - `[false]` `[reject]` (edge) re-adding the channel to the tree loses its Events connection -- nothing reparents the channel; it lives and dies with the level scene.
  - `[false]` `[reject]` (edge) leaving the tree mid-story leaves `story` pushed -- every scene exit goes through `SceneRouter` or the F5 restart, and both call `PauseArbiter.clear()`.
  - `[false]` `[reject]` (edge) a story request while the menu is open stacks two dims -- requests come from the deferred `--comms` call (same frame as the level start, before any Esc) and, from Story 5.3, the pausable WaveDirector, which can't run while the menu pauses the tree.
  - `[false]` `[reject]` (edge) a story request during `death` / `final_choice` -- the tree is paused, so no pausable requester runs; `final_choice` doesn't exist yet (Story 7.5).
  - `[low]` `[reject]` (edge) the tests use a probe instead of `is_input_handled()` and drive the private tween -- documented deviation: under GUT the root viewport reports mouse events as handled even when nothing consumed them, so the probe is the stronger check.
  - `[low]` `[patch]` (verification-gap) no Config-level test for a dialogue file without a `sequences` object -- added `tests/fixtures/dialogue/bad/d_no_sequences.json`, expected its error, and raised the push_error count.
  - `[low]` `[reject]` (verification-gap) the missing `comms.story_line_max_chars` fallback and its log are untested -- the shipped key is pinned at 200 by the data tests; only the diagnostic for a removed key is unverified, and testing it needs a temp tuning file.
  - `[low]` `[patch]` (verification-gap) the level test's `comms_open` assertion can't fail on its own (`Audio._newest` persists) -- the test now plays `laser_zap` first, so the assertion passes only if the channel played `comms_open`.
  - `[low]` `[patch]` (intent) the epic says "immediately" and the diff defers the unknown-id `finished` -- same root cause as the first blind row; same doc fix (deferred within the same frame).
  - `[false]` `[reject]` (intent) Esc and closing the menu aren't tested through real level input routing -- the pause menu handles only `pause` and the channel only `comms_advance`, so routing order can't change the outcome; both suites cover the behaviour.
  - `[low]` `[reject]` (intent) "only CommsChannel sets dialogue text" is enforced by convention only -- the panel is a view with no data access and the channel is its only caller; a source-scan test adds little.
  - `[false]` `[reject]` (intent) scope beyond the epic ACs (story queue, combat placeholder, `--comms`, theme, SFX, one-dim) -- all of it is in the spec's contract, and it serves the ACs (comms-open SFX, dim, nothing waiting forever).

## Design Notes

**Advance on release.** `set_input_as_handled()` stops the event from reaching other nodes, but it doesn't change `Input.is_action_pressed`. If the last click popped the pause on press, the Player's next physics tick would see LMB held and fire. The channel therefore consumes both press and release and acts on the release, so the pause lifts with the button already up. The "armed" flag stops a fire button that was held down from before the panel opened from advancing on its release.

**Deferred `finished` for unknown and combat ids.** Callers (the WaveDirector in 5.3) emit the request and then `await` the finished signal. If the channel emitted `finished` inside the request it would fire before that await and the chain would hang. Deferring it keeps "immediately" (the same frame) without the race.

**Speaker names** are first-name placeholders in tuning so Story 5.7 can change them without code. Accents live in the Theme (styling), and the portrait on/off flag lives in data because Epic 8 may give Vale a portrait.

**The `▸` glyph** isn't in Godot's built-in fallback font (checked: `has_char(0x25B8)` is false). The font's system fallback is expected to draw it on Windows, and the Kenney Future font replaces the font in Epic 8. The human check below covers it.

## Verification

**Commands:**
- `uv run python tools/gen_placeholder_sfx.py` then `git status` -- expected: only `sfx_comms_open.wav` is new; the existing WAVs are unchanged.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: completes; `sfx_comms_open.wav.import` exists.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass.

**Manual checks (if no CLI):**
- Run `level.tscn` with `-- --comms=dev_comms_check`. The dim, panel layout, accent names, placeholder portrait, typing speed, the `▸` cue glyph and the comms-open sound look and sound right. Click-to-complete, click-to-advance, Esc then Esc keeps the panel paused with one dim, and no laser shot on the final click.

## Auto Run Result

Status: awaiting-operator

**Summary:** Story lines now reach the player. `Config` loads and validates every `data/dialogue/*.json` (`DialogueValidator`) and serves `sequence` / `has_sequence` / `dialogue_is_story`. `CommsChannel` (under the level's `Comms` layer) pauses the game with the `story` reason, plays the new `comms_open` SFX and drives `CommsPanel`: a centred conversation panel over a dim, with a placeholder portrait, the accent-coloured uppercase name, typewriter text at 45 chars/s and the `click to continue ▸` cue. A click completes a line, the next click advances, and the pause lifts on the mouse **release**, so the last click never fires the laser. Unknown ids (and combat ids until Story 5.2) finish deferred with no pause. A second story queues. The pause menu hides its own dim over a story. A debug `-- --comms=<id>` argument opens a sequence in the level so a human can check it.

**Files changed:**
- `game/systems/comms/comms_channel.gd`, `comms_panel.gd`, `comms_panel.tscn`, `dialogue_validator.gd` (new): the channel, the panel view, data validation (including empty ids)
- `game/autoloads/config.gd`: dialogue load, reload and getters
- `game/autoloads/audio.gd`, `game/assets/audio/sfx/sfx_comms_open.wav` (+ `.import`), `tools/gen_placeholder_sfx.py`, `game/assets/CREDITS.md`: the `comms_open` placeholder SFX
- `game/data/dialogue/dev.json` (new), `game/data/tuning.json`: the placeholder sequence `dev_comms_check`; `comms.story_line_max_chars`, `comms.speakers`, `ui.comms_panel`
- `game/ui/theme/defector_theme.tres`: the `CommsPanel` theme type (colours, font sizes, panel style, `line_spacing` 0)
- `game/scenes/level/level.tscn`, `level.gd`, `game/ui/debug/debug_args.gd`: wiring and the `--comms` debug argument
- `game/ui/menus/pause_menu.gd`: one dim over a story pause
- Tests: `test_dialogue_validator.gd`, `test_comms_panel.gd`, `test_comms_channel.gd` (new) plus fixtures in `tests/fixtures/dialogue/`; `test_config.gd`, `test_level.gd`, `test_pause_menu.gd`, `test_debug_args.gd`, `test_audio.gd`, `tests/data/test_data_files.gd` extended
- `_bmad-output/game-architecture.md`: comms parts marked as built, the advance-on-release and deferred-finished notes, and an As-built (Story 5.1) section; `_bmad-output/implementation-artifacts/epic-5-context.md` (new, compiled)

**Review:** 26 findings, 5 patches applied:
- high: story text clipped to 3 of 4 lines, fixed with Theme `line_spacing` 0 and a fit test
- medium: an empty sequence id soft-locked the game, now rejected by the validator
- low: a missing-`sequences` fixture test; a level SFX assertion that couldn't fail; the epic-context and architecture wording on the deferred `finished`

Nothing was deferred. The other 21 were rejected; each reason is in the Review Triage Log (unreachable states, debug-only paths or negligible cost).

**Follow-up review recommended: true.** A high finding (the clipped text) was patched. The fit test uses Godot's built-in fallback font; the risk still unverified is the real rendered text in the running game, and Epic 8's Kenney Future font, which changes the metrics. Patched by verdict: high 1, medium 1, low 3.

**Verification:**
- `uv run python tools/gen_placeholder_sfx.py`: only `sfx_comms_open.wav` is new; the existing WAVs are byte-identical.
- `--import`: exit 0.
- Full GUT suite headless: 1139/1139 passing, 9778 asserts.
- Every I/O matrix row is covered by a test that ran.
- The no-laser acceptance test fails when the channel advances on press instead of release (checked by the implementer).

**Residual risks:**
- The `▸` glyph isn't in Godot's fallback font, so it relies on the Windows system font fallback.
- The layout, dim, accent colours, typing feel and the placeholder `comms_open` sound are checked only as node state, not by eye or ear (see `operator_actions`).
- Speaker names are first-name placeholders until Story 5.7.
