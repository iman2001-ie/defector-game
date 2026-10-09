---
title: 'Story 5.5: Open the Campaign with the Comms Sequence'
type: 'feature'
created: '2026-10-08'
status: 'done'
baseline_revision: '70800b1002824457a5587a88013f329fcca8eed7'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-5-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/EXPERIENCE.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The campaign starts in the middle of the action. There is no `story.tscn`, no `SceneRouter.goto_story`, and no `opening_main` dialogue, so the player never learns who Vale, Tarek and Isolde are (FR41, R15). Tier: MUST.

**Approach:** Add a comms-only story scene and `SceneRouter.goto_story(id, next_level)`. A fresh start of Level 1 (PLAY or Level Select) goes through the story scene with `opening_main`. When the sequence finishes, the router loads Level 1. A retry or restart never plays it. Ship `data/dialogue/opening.json` with placeholder-quality but in-voice lines.

## Boundaries & Constraints

**Always:**
- **`SceneRouter`** (`autoloads/scene_router.gd`):
  - `const STORY_SCENE_PATH: String = "res://scenes/story/story.tscn"`, `const OPENING_SEQUENCE: StringName = &"opening_main"`, `const OPENING_LEVEL_ID: String = "1"`.
  - `goto_story(id: StringName, next_level: int)` stores the pending id and next level, clears `GameState.is_retry`, and changes to the story scene through `_change_to` (INFO line `Story '<id>' before level <n>`). It refuses (Log.error, no change) while `Config.load_error` is set, like `start_level`.
  - Accessors `story_sequence() -> StringName` and `story_next_level() -> int`.
  - `finish_story()`: starts the pending level as a fresh attempt, keeping the energy, **without** the opening check, then clears the pending story. With no pending story (`next_level < 1`) it logs a warning and calls `goto_title()`.
  - `start_level(id)`: after the existing load-error guard, when `id == OPENING_LEVEL_ID` it calls `goto_story(OPENING_SEQUENCE, int(id))` instead of loading the level. Every other id behaves as today. Move the shared "set id, clear is_retry, change to level.tscn" body into a private helper used by both paths.
  - `restart_level()` and `complete_level()` are unchanged (`complete_level` never starts level 1).
  - Update the header doc comment.
- **`CommsPanel`**: `@export var dim: bool = true`. `open()` shows the `Dim` child only when `dim` is true. The level scene keeps today's look.
- **Story scene** (`scenes/story/story.tscn` + `story.gd`, `class_name StoryScene extends Control`, full rect, shared theme):
  - Children: a `Comms` CanvasLayer (layer 20) with `CommsChannel` (`panel`, `box` wired), `CommsBox` and `CommsPanel` (with `dim = false`), the same shape as `level.tscn`.
  - No HUD, no WaveDirector, no PauseMenu, no DebugTools, so Esc does nothing.
  - The backdrop is the project clear colour (`#05070F`), as on the title. Art backdrops come in Epic 8.
  - `_ready`: `PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)`, connect `Events.comms_sequence_finished` (disconnect in `_exit_tree`), then emit `Events.comms_sequence_requested(SceneRouter.story_sequence())`.
  - On `finished` with that id, call `SceneRouter.finish_story()` exactly once. Ignore other ids.
  - With an empty pending id (scene run directly), log a warning and call `SceneRouter.finish_story()` (which goes to the title).
- **Dialogue data** `data/dialogue/opening.json`: `opening_main`, story mode, 6-10 lines. Speakers only `vale`, `tarek`, `isolde`. No `system` and no narrator. Isolde has exactly one line: cold, aimed at the traitor, introducing herself. Tarek introduces himself, welcomes "the General" to the Coalition and briefs the convoy escort. Vale states the defection. Vale is gender-neutral and has a few lines at most. The tone is personal, not comedic. Every line is at most 200 characters (the validator enforces it).
- **Tests** are written first: router, story scene, panel dim, data. Statically typed GDScript, `Log` only (`scene`, `comms`), no new `Events` signal or autoload, and only `PauseArbiter` pauses (the channel does it).

**Never:** Don't add the level briefing (`intro_sequence`) to `level_1.json`; that is Epic 7. Don't add the ending story or `goto_end` (Epic 7). Don't make the opening skippable (no Esc and no skip button). Don't add art or music. Don't change `CommsChannel` behaviour.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Fresh L1 | `start_level("1")` | scene → story path, pending `opening_main`/1, `is_retry` false | none |
| Other level | `start_level("2")` | scene → level path, as today | none |
| Story done | `finish_story()` with pending 1 | `current_level_id` "1", `is_retry` false, energy kept, scene → level path, no second story | none |
| No pending | `finish_story()` with nothing pending | goes to the title | `Log.warn` |
| Retry L1 | `restart_level()` with level "1" | scene → level path, never story | none |
| Config failed | `goto_story` or `start_level("1")` with `load_error` | no scene change | `Log.error` |
| Scene plays | story.tscn instanced, pending `opening_main` | tree paused (`story`), panel showing line 0, dim hidden, mouse visible | none |
| Click-through | click past the last line | pause lifted, `finish_story` called once → level path recorded | none |
| Unknown id | pending id not in data | deferred `finished` → level path still recorded (no soft-lock) | channel logs error |
| Esc | `pause` action pressed while the story shows | nothing changes (no `menu` reason, line unchanged) | none |

</intent-contract>

## Code Map

- `game/autoloads/scene_router.gd`
  - `start_level` (l.118): the load-error guard, then the GameState writes and `_change_to`.
  - `restart_level` (l.108) and `complete_level` (l.164, calls `start_level(str(n + 1))`).
  - `_change_to` (l.176): `Feedback.reset`, log, `change_scene`, `PauseArbiter.clear()` after the swap (DW-61), so the story scene's `_ready` push survives.
- `game/scenes/title/title.gd:108` (PLAY → `start_level(str(highest))`) and `level_select.gd:82` (card → `start_level(str(n))`): no change needed. Routing lives in the router, so both get the opening.
- `game/scenes/level/level.tscn` (l.132-143): the `Comms` layer to copy (CommsChannel `process_mode = 3`, `panel`/`box` NodePaths, CommsBox before CommsPanel).
- `game/systems/comms/comms_panel.gd`: `open()` (l.~103) and the `_dim` onready. `comms_panel.tscn` has the `Dim` ColorRect.
- `game/systems/comms/comms_channel.gd`: connects in `_ready` (child `_ready` runs before the scene root's), pushes `story` and pops it **before** emitting `finished`. Input: `_unhandled_input` press-arm/release-advance on `comms_advance`, ignored while `menu` is active.
- `game/autoloads/config.gd`: loads every `data/dialogue/*.json` and validates it (`DialogueValidator`); `sequence(id)` and `dialogue_is_story(id)`.
- `game/autoloads/game_state.gd`: `is_retry`, `current_level_id`, `energy`.
- `game/data/dialogue/dev.json`: the shape to follow. `tuning.json` `comms.speakers` (l.227).
- Tests:
  - `game/tests/unit/test_scene_router.gd`: the `_record` change_scene recorder, `Log.sink` capture and the `after_each` resets. **Existing asserts that `start_level("1")` (or a title PLAY/Level Select card 1 with `highest_unlocked_level = 1`) lands on `LEVEL_SCENE_PATH` must change to `STORY_SCENE_PATH`**. Check `test_title.gd`, `test_level_select.gd` and `test_scene_router.gd`, and use level 2 where a test means "a level loads".
  - `game/tests/unit/test_comms_channel.gd`: `_push`/`_click` (l.~120-137) and `_click_to_end_of` (l.338) for driving input.
  - `game/tests/data/test_data_files.gd`: `_all_sequences()` (l.538), `_dialogue_files()` (l.475) and `test_dev_comms_check_is_a_story_with_both_panel_variants` (l.504) as the pattern.
- `_bmad-output/game-architecture.md`:
  - The Scene flow row (l.668): mark `goto_story` built.
  - The Scene Structure note (l.~256).
  - Add an "As-built 2026-10-08 (Story 5.5)" section after the Story 5.4 one (l.1709).

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_scene_router.gd`: one test per router row of the matrix. Fix the existing level-1 expectations.
- `game/tests/unit/test_story_scene.gd` (new): instance `story.tscn` with the recorder injected and `goto_story` state set (call `goto_story` with the recorder, then add the scene). Cover the "Scene plays", "Click-through", "Unknown id" and "Esc" rows, and the empty-id fallback. Restore `PauseArbiter`, `SceneRouter.change_scene` and GameState in `after_each`.
- `game/tests/unit/test_comms_panel.gd`: `dim = false` keeps `Dim` hidden on `open()`. The default still shows it.
- `game/tests/data/test_data_files.gd`: `opening_main` exists in `opening.json`, is story mode, has 6-10 lines, speakers in {vale, tarek, isolde}, exactly one isolde line, at least one tarek and one vale line, and Tarek's lines mention the convoy.
- `game/autoloads/scene_router.gd`, `game/systems/comms/comms_panel.gd`, `game/scenes/story/story.gd` + `story.tscn`, `game/data/dialogue/opening.json`: as specified.
- Fix `test_title.gd`/`test_level_select.gd` expectations if they assert the level path for level 1.
- `_bmad-output/game-architecture.md`: as in the Code Map.

**Acceptance Criteria:**
- Given the title with `highest_unlocked_level = 1` (and, separately, a Level Select card 1) and a recording `change_scene`, when PLAY (the card) is pressed, then the story scene path is recorded with pending `opening_main`/1. Then, with `story.tscn` instanced, clicking through every line records the level scene path with `current_level_id == "1"` and `is_retry == false`.
- Given the full GUT suite run headless, when it runs, then every test passes with no new orphan or engine-error output.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 16 findings — high 0, medium 0, low 13, false 3, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) no "static space background" in story.tscn, and the as-built text calls the docs "silent" on it — the clear colour is the DESIGN `background` token ("Space backdrop base", #05070F), which is how the title already shows its "space backdrop" (Story 4.1 scoped out backdrop art). So the AC holds at placeholder level. The as-built wording was wrong and now cites the token; backdrop art stays with Epic 8.
  - `[low]` `[reject]` (blind) `goto_story(id, next_level: int)` can't express Epic 7's `next = end` — this story's AC fixes the signature as `next_level = 1`. Nothing calls it with "end" yet. Widening it now would add public surface for Epic 7's ending story, which will have to extend it.
  - `[low]` `[patch]` (blind) the architecture's directory inventory still says "As of Story 5.2" — updated to 5.5, with `scenes/story/` and `opening.json` added.
  - `[low]` `[patch]` (blind) production doc comments describe the old flow — `title.gd` and `level_select.gd` are still accurate (both call `start_level`). The `level.gd` header was stale and now names the opening → `finish_story()` hop.
  - `[false]` `[reject]` (blind) no test that the story scene disconnects on exit, so a stale scene could start a level — Godot drops a freed object's signal connections automatically, so even without `_exit_tree` a freed StoryScene's handler never runs.
  - `[low]` `[patch]` (blind) the data test doesn't pin "Tarek welcomes the General" — added an assert that a Tarek line contains "general" and "welcome". A Vale upper bound was not added because "a few lines" gives no number.
  - `[false]` `[reject]` (blind) `test_esc_does_nothing` can't fail — the pushed `pause` action is exactly what PauseMenu listens for (`is_action_pressed(&"pause")`), so adding a PauseMenu or any `pause` handler to the scene makes it fail. Esc maps to that action. The only global input handler (SceneRouter) handles `toggle_fullscreen` only.
  - `[low]` `[reject]` (blind) `test_title` dropped its `current_level_id == "1"` assert — the story-scene acceptance tests assert `current_level_id == "1"` after the click-through. An id set early by `goto_story` would be harmless, and nothing reads it before the level loads.
  - `[low]` `[patch]` (blind) a long reflowed header line in `test_title.gd` and a double blank line in the architecture — both fixed.
  - `[low]` `[reject]` (edge) `goto_story` with `next_level < 1` plays the story and then lands on the title — unreachable: the only caller passes `int("1")`. A guard would add a branch for no caller.
  - `[low]` `[reject]` (edge) `goto_story(&"", n)` loads the level instead of the documented title fallback — unreachable: the only caller passes the `opening_main` constant.
  - `[false]` `[reject]` (edge) `finish_story` could load a level while `Config.load_error` is set — `goto_story` refuses under a load error, and nothing sets `load_error` between entering the story scene and finishing it (a failed reload keeps the old data, and there are no DebugTools in the scene).
  - `[low]` `[patch]` (intent) backdrop divergence — same root cause and fix as the first blind row.
  - `[low]` `[reject]` (intent) the tests use a recorder instead of a real scene change — calling `change_scene_to_file` in GUT would replace the test runner, the established pattern since Story 3.2. The scene's behaviour is proven by instancing the real `story.tscn`.
  - `[low]` `[patch]` (intent) the narrative ACs are checked through proxies — grouped with the Tarek-welcome data-test row; same fix. The rest of the meaning lives in the JSON text, which Story 5.7 owns.
  - `[low]` `[reject]` (intent) no test that PLAY with Level 2 unlocked skips the opening — `test_start_other_levels_skip_the_opening` covers it at the router, and PLAY only calls `start_level(str(highest))`.

## Design Notes

**Why the router decides:** `start_level("1")` is the single entry point for both PLAY and Level Select, so routing there covers both AC paths and keeps the menus unchanged. `finish_story()` uses the private level-load helper, so the story → level hop can't loop back into the opening. `restart_level()` never goes through `start_level`, so R15 holds by construction.

**Record-only decisions** (the docs are silent):
- The opening id and level are router constants. They are scene-flow wiring, like the scene paths, not tuning.
- The backdrop is the clear colour.
- `goto_story` keeps the energy (fresh-attempt semantics).

**Draft lines** (the implementer may polish them; they must stay in voice and within the limits):
```
tarek:  Unknown Sovereignty fighter, this is Admiral Tarek Holt of the Free Worlds Coalition. Power down your weapons and state your intent.
vale:   This is General Arden Vale. I've left the Sovereignty. I'm not going back.
tarek:  Vale. Ten years your name has topped our threat reports. Welcome to the Coalition, General. I mean that.
tarek:  No time to settle in. A supply convoy runs the outer lanes tonight, and Sovereignty raiders are already hunting it.
tarek:  You fly escort with me. Keep those cargo ships alive, whatever comes at them.
isolde: Arden. This is Isolde Varn, your Sovereign. You knelt to me once. Run to them if you like; I will bring you home in chains.
vale:   Let her come. Convoy's moving, Admiral. I'm on your wing.
```

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import`: expected to complete. Run it, because this story adds a `class_name` (`StoryScene`) and a scene.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`: expected all tests to pass.

## Auto Run Result

Status: done

**Summary:** Starting Level 1 fresh, from PLAY or from Level Select, now plays the opening comms scene first. When the opening finishes, Level 1 loads. Retrying or restarting never plays it.
- `SceneRouter.start_level("1")` sends the player to `goto_story(&"opening_main", 1)`.
- The new `story.tscn` plays the sequence: the story panel with no dim, a visible cursor, no HUD, and Esc does nothing.
- It then calls `SceneRouter.finish_story()`, which loads the level through a private helper, so the opening can't loop.
- `restart_level()` never goes through `start_level`.

**Files changed:**
- `game/autoloads/scene_router.gd`: `STORY_SCENE_PATH`, `OPENING_SEQUENCE`, `OPENING_LEVEL_ID`, `goto_story`, `story_sequence`, `story_next_level`, `finish_story`, private `_load_level`; `start_level("1")` routes through the opening.
- `game/scenes/story/story.gd` and `story.tscn` (new, `StoryScene`): the comms-only story scene.
- `game/systems/comms/comms_panel.gd`: `@export var dim`; `open()` shows the Dim only when it is on.
- `game/data/dialogue/opening.json` (new): `opening_main`, 7 placeholder-quality lines in each character's own voice (Tarek ×4, Vale ×2, Isolde ×1).
- `game/scenes/level/level.gd`: header comment updated.
- Tests:
  - `test_story_scene.gd` (new, 10 tests): covers the scene rows and both acceptance criteria end to end.
  - `test_scene_router.gd`: 12 new tests.
  - `test_comms_panel.gd`: dim on and off.
  - `test_data_files.gd`: the opening data checks.
  - `test_title.gd` and `test_level_select.gd`: the level-1 expectations now point to the story scene.
- `_bmad-output/game-architecture.md`: the story scene, `goto_story` and `finish_story` are marked built, the directory inventory is updated, and there is a new As-built (Story 5.5) section.

**Review:** 16 findings: 0 high, 0 medium, 13 low, 3 false.
- **Patched (low):**
  - Corrected the backdrop wording in the architecture doc.
  - Updated the stale directory inventory.
  - Fixed the stale `level.gd` comment.
  - Added a data-test assert that Tarek welcomes the General.
  - Fixed two formatting nits.
- **Rejected:**
  - Widening `goto_story` for Epic 7's "end" target.
  - Guards on unreachable `goto_story` arguments.
  - A real scene change in tests.
  - A dropped `test_title` assert (covered elsewhere).
  - A test for PLAY with level 2 unlocked (covered at the router).
  - The three false findings: the disconnect test, the Esc test, and the load-error claim.

  Every reason is in the Review Triage Log.
- **Deferred:** nothing.

**Follow-up review recommended: false.** Only low entries were patched (5 low, 0 medium, 0 high).

**Verification:**
- `--import`: exit 0.
- Full GUT suite headless: 1271/1271 passing, with no script or engine errors (the `ERROR:` lines are expected `Log.error` captures).
- `test_story_scene.gd` run alone: 10/10.
- The matrix audit passed: every I/O row has a passing covering test.

**Residual risks:**
- The game was not launched by hand. The real `change_scene_to_file` hop from title to story to level is only covered by the recorder, so a human should click through the opening once.
- The backdrop is the flat `background` colour until Epic 8 art.
- `goto_story` takes an `int` next level, so Epic 7's ending story (`next = end`) will need to extend it.
- The opening lines are placeholder until Story 5.7.
- None of this needs a human action outside the repo, so the status is `done`, not `awaiting-operator`.
