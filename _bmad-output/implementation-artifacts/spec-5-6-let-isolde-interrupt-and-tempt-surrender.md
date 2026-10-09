---
title: 'Story 5.6: Let Isolde Interrupt and Tempt Surrender'
type: 'feature'
created: '2026-10-08'
status: done
baseline_revision: '3d94e8a2f208e4e6ee266ee5f722071a2d627fa7'
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

**Problem:** Isolde never speaks during a fight. The dialogue data has no `l1_w3_isolde_interrupt`, `l2_w3_isolde_interrupt`, `l3_w3_isolde_taunt` or `l1_w5_surrender`. Level authors also have no documented flag-gated pattern for interruptions and the surrender prompt, and there is no dev level a human can play to see both (FR42, FR43, FR61). Tier: SHOULD.

**Approach:** The trigger machinery already exists (Story 5.3: BeatTrigger `flag` with `!` negation, the `comms` and `spawn_group` actions, story-waits-for-finished). This story adds:
- the four sequences, in `data/dialogue/level_1.json`, `level_2.json` and `level_3.json`;
- a new dev level, `data/levels/level_dev_isolde.json`, that uses both patterns;
- a debug-only `-- --level=<id>` arg, so a human can play that level;
- the level-author pattern docs in the architecture;
- tests that prove the flags gate the beats and that the reinforcements always arrive.

## Boundaries & Constraints

**Always:**
- **Dialogue data:** one file per level scene, each `{ "sequences": { ... } }`.
  - `level_1.json`:
    - `l1_w3_isolde_interrupt`: combat, 1 isolde line.
    - `l1_w5_surrender`: story, exactly 1 isolde line with the text `You're outnumbered, General. Come home.` and no `choice` key.
  - `level_2.json`: `l2_w3_isolde_interrupt`, combat, 1 isolde line.
  - `level_3.json`: `l3_w3_isolde_taunt`, combat, 1 isolde line.
  - Every combat line is at most 50 characters (the validator already enforces this).
  - The text is placeholder-quality but in voice: condescending and personal, aimed at "General" or "Arden", not comedic. Story 5.7 polishes it.
- **Dev level** `data/levels/level_dev_isolde.json`: `"id": 0`, name `Development: Isolde beats`, same root keys as `level_dev.json` (`intro_sequence`/`outro_sequence` null). It must pass LevelValidator.
  - **Wave 1:** 8 wasps (`grid_4x2`, top). Trigger `{ "when": "progress", "at": 0.25, "flag": "isolde_interruptions", "actions": [ { "comms": "l1_w3_isolde_interrupt" } ] }`.
  - **Wave 2:** 10 wasps (`grid_5x2`, top).
    - Group `reinforcements`: 4 wasps (`grid_4x1`, top). The Maul is not built until Epic 6.
    - The paired triggers, at `0.30`:
      - `"flag": "surrender_prompts"` → `[ { "comms": "l1_w5_surrender" }, { "spawn_group": "reinforcements" } ]`
      - `"flag": "!surrender_prompts"` → `[ { "spawn_group": "reinforcements" } ]`
- **`--level=<id>`** (debug builds only):
  - `DebugArgs.parse` returns a `level` key (`""` when the arg is absent). An empty value warns and is ignored, like `--comms`. Update the header list.
  - `level.gd` gets a static `debug_level_id(debug_build, args) -> String`, like `debug_comms_id`.
  - In `_ready`, a non-empty value replaces the exported `level_id` **before** `resolve_level_id`. So a retry (GameState id set) keeps its id.
  - Log one INFO `[debug]` line. Update the header comment.
- **Architecture:** add a "Level-author trigger patterns" block under the Wave Director rules. It covers:
  - the interruption pattern (a `comms` action on a combat sequence, gated by `"flag": "isolde_interruptions"`);
  - the paired surrender pattern;
  - the rule that a flag gates only its beat, so reinforcements live in both triggers;
  - that F5 re-reads `flags.json` and restarts the level.

  Also add an "As-built 2026-10-08 (Story 5.6)" section after Story 5.5's.
- Tests come first. Statically typed GDScript. Log only through `Log`. Only `PauseArbiter` pauses (the channel does it). No new `Events` signal, autoload or tuning key.

**Never:**
- Don't place these beats in `level_1/2/3.json`; that is Epic 7.
- Don't edit `level_dev.json`: a story pause there would stall the existing F3 and real-kill clear tests.
- Don't change `CommsChannel`, `WaveDirector`, `BeatTrigger` or `LevelValidator` behaviour.
- Don't add a Maul.
- Don't offer a choice on the surrender line.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Interrupt on | flags default, dev_isolde wave 1, kill 2 of 8 | channel `current_combat()` = `l1_w3_isolde_interrupt`, box shows ISOLDE, tree not paused | none |
| Interrupt off | `isolde_interruptions` false (flags file reloaded) | no combat line at 0.25 or later in wave 1; the wave still clears | none |
| Surrender on | wave 2, kill until ratio ≥ 0.30 | tree paused (`story`), panel shows the surrender text, no reinforcements yet; click through → pause lifted, 4 more counted wasps spawn | none |
| Surrender off | `surrender_prompts` false | no pause and no surrender sequence requested; 4 reinforcements still spawn after the 0.30 kill | none |
| F3 with prompt on | `debug_resolve_wave()` on wave 2 | surrender pauses; after click-through the pause lifts, the reinforcements do NOT spawn (F3 already marked the unspawned `reinforcements` group as skipped; existing F3 semantics, `WaveDirector` unchanged), and the wave and level clear (no soft-lock) | none |
| `--level` arg | debug + `--level=dev_isolde` / release / absent / `--level=` | `dev_isolde` / `""` / `""` / `""` + warn | `Log.warn` on empty |
| Retry with arg | GameState id `"dev"`, arg `dev_isolde` | resolved id stays `"dev"` | none |

</intent-contract>

## Code Map

- `game/data/dialogue/dev.json`: the shape to copy. `game/autoloads/config.gd` loads every `data/dialogue/*.json` (DialogueValidator). `sequence(id)` and `dialogue_is_story(id)`.
- `game/data/flags.json`: `surrender_prompts` and `isolde_interruptions` are already `true`.
- `game/systems/waves/beat_trigger.gd:48-70`: `should_fire(event, value, flags)` reads `Config.flags` at fire time (`wave_director.gd:449-454`), so a reloaded flags file takes effect.
- `game/systems/waves/wave_director.gd:457-499`: `_run_chain`. A story `comms` awaits finished, then `spawn_group`.
- `game/data/levels/level_dev.json`: the template for the new level. Wave 2 shows the `groups` and `spawn_group` shape. Leave it unchanged.
- `game/scenes/level/level.gd`:
  - `level_id` export (l.28) and `_ready` (l.47-80): `DebugArgs.parse(user_args)`, then `resolve_level_id`.
  - `debug_comms_id` (l.102) is the pattern for `debug_level_id`.
  - `user_args` is injectable before `add_child`.
- `game/ui/debug/debug_args.gd`: `parse()` and `COMMS_PREFIX`. Add `LEVEL_PREFIX = "--level="`. Check the existing DebugArgs tests (grep `DebugArgs.parse` in `game/tests`) and extend the ones that assert the whole returned dictionary.
- `game/tests/unit/test_level.gd`:
  - `_make_level(level_id)` (l.86), `_make_player_invincible` (l.82), `_kill_one_counted` (l.1070) and `_capture` (l.32).
  - The Story 5.4 acceptance tests (l.1080-1200) show how to drive real kills, F3 and the channel or box.
  - `after_each` calls `Config.load_data()` (it restores flags).
  - `test_debug_comms_id_only_in_debug_builds` (l.834) is the pattern for the arg test.
- `game/tests/unit/test_debug_tools.gd:395-410`: the TEMP_FLAGS pattern (write a flags file, then `Config.load_data(DEFAULT_TUNING_PATH, TEMP_FLAGS)`). Use it for the flag-off rows, because that is what F5 re-reads.
- `game/tests/unit/test_comms_channel.gd`: `_click_to_end_of` / `_push` / `_click` input helpers for clicking a story through (or call the channel's advance path the same way the 5.5 story-scene tests do).
- `game/tests/data/test_data_files.gd`: `_level_files()` (l.18) auto-validates the new level. `_dialogue_files()` (l.475) and `_all_sequences()` (l.573) feed the new data asserts. The "every referenced sequence exists" test covers the dev level's ids.
- `_bmad-output/game-architecture.md`:
  - Wave Director rules (l.~792-805), right after the `level_1.json` example (whose paired triggers already show the surrender shape).
  - The directory inventory (search for "As of Story 5.5").
  - Add the As-built section after l.~1730.

## Tasks & Acceptance

**Execution:**
- `game/tests/data/test_data_files.gd`: check each of the 4 ids:
  - it sits in its file;
  - its mode;
  - it has exactly 1 line, with speaker `isolde`;
  - combat lines are at most 50 characters;
  - the surrender text is exact and the sequence has no `choice`.
- `game/tests/unit/test_level.gd` (or a new `test_isolde_beats.gd` if the file is unwieldy): one test per I/O row on the real `level.tscn` with `level_id = "dev_isolde"`. Also cover the `--level` rows, including the retry row through `resolve_level_id`.
- DebugArgs tests: the `level` key.
- `game/data/dialogue/level_1.json`, `level_2.json`, `level_3.json`, `game/data/levels/level_dev_isolde.json`, `game/ui/debug/debug_args.gd` and `game/scenes/level/level.gd`: as specified.
- `_bmad-output/game-architecture.md`: the pattern block, the inventory and the As-built section.

**Acceptance Criteria:**
- Given the shipped `flags.json` (both flags on) and `level_dev_isolde` in `level.tscn`, when the player kills through wave 1 and into wave 2:
  - the interruption shows in the box while the tree stays unpaused;
  - at 0.30 the surrender line pauses the game in the centred panel;
  - after clicking through, 4 reinforcements spawn and the level clears.
- Given a flags file with either flag false, loaded as F5 does, when the same level plays:
  - that beat never fires;
  - the reinforcements still arrive;
  - no script or level file changed.
- Given the full GUT suite run headless, when it runs, then every test passes with no new orphan or engine-error output.

## Spec Change Log

- 2026-10-08 (bmad-loop-resolve, human-approved): the "F3 with prompt on" matrix row was amended. It wrongly expected the reinforcements to spawn after the click-through, but F3 (`debug_resolve_wave`) skips every unspawned group by design, and the Never clause forbids changing `WaveDirector`. The row now expects no reinforcements under F3; the no-soft-lock check is unchanged. The "4 reinforcements spawn" acceptance criteria apply to real kills, not F3.

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 23 findings — high 0, medium 3, low 19, false 1, maybe-false 0
- findings:
  - `[medium]` `[patch]` (blind) `--level` does nothing on a normal launch: boot → title → SceneRouter always sets `GameState.current_level_id`, so `level.gd` ignores the arg — confirmed via `project.godot` main_scene and `scene_router.gd:239`; patched the docs (architecture Debug Tools bullet, trigger-pattern block, As-built, `level.gd` and `debug_args.gd` headers) to give the direct-scene launch command; no boot/router change.
  - `[low]` `[patch]` (blind) the "ignored" log line calls every GameState-id case a retry — true for fresh router entries too; reworded to `ignored: GameState level '<id>' wins` (code, test, doc).
  - `[low]` `[reject]` (blind) unknown `--level` id has no safeguard — debug-only typo fails loudly through the existing `Config.level` error path; a pre-check adds a branch for a case nobody meets in normal use.
  - `[low]` `[reject]` (blind) "last one wins" and `--stress` precedence untested — the loop overwrites by construction and the stress redirect is pre-existing; a combined debug misuse nobody needs.
  - `[low]` `[reject]` (blind) click-through uses `channel.advance()` not a real mouse release — the release → advance path is covered by the existing comms channel and Story 5.5 story-scene tests on the same node.
  - `[low]` `[patch]` (blind) the two flags are never tested against each other — grouped with the edge-case AC 2 gap below; the interruptions-off test now runs through the surrender and the reinforcements.
  - `[low]` `[patch]` (blind) the surrender-off "no pause" check is narrow — added `PauseArbiter.has_reason(&"story")` false and panel-hidden asserts.
  - `[low]` `[reject]` (blind) test helpers time out silently / divide by zero — a failure still surfaces as a failing downstream assertion; extra guards add test complexity for no new coverage.
  - `[low]` `[reject]` (blind) `test_dev_isolde_level_shape` copies the level JSON literally — the spec fixes the dev level's exact shape; this is a dev fixture, not tuning.
  - `[low]` `[reject]` (blind) nothing enforces "a flag gates only its beat" in data — no level violates it today, `LevelValidator` must not change in this story, and Epic 7 places the real beats.
  - `[low]` `[reject]` (blind) the surrender-text data check can crash on a missing sequence — the preceding loop asserts presence first; a crash is still a test failure.
  - `[false]` `[reject]` (blind) the L3 taunt depends on Story 6.5 (Tarek's fall) — the GDD has Tarek wounded in Level 2, so "no admiral to hide behind" holds whether or not 6.5 ships; Story 5.7 polishes text.
  - `[low]` `[reject]` (blind) the `--level` scene tests leave the player mortal and `warp_mouse` real — those tests await no frames, so neither can act; no flakiness path.
  - `[low]` `[patch]` (blind) the `debug_args.gd` header overstates what `--level` does — same root cause as the launch-path finding; the header now says it applies only when `level.tscn` is the launched scene.
  - `[low]` `[reject]` (edge) an unknown level id goes into GameState — same as the blind unknown-id finding.
  - `[low]` `[patch]` (edge) the "ignored" log wording is wrong for non-retries — same as the blind log-wording finding; reworded.
  - `[low]` `[reject]` (edge) `_kill_to_ratio` gives NaN on a total of 0 — same as the blind helper finding.
  - `[low]` `[reject]` (edge) `_load_flags_with` gets null on an unparseable shipped flags file — the shipped file is validated by the data tests; a null would still fail the test.
  - `[low]` `[patch]` (edge) AC 2: the reinforcements are never checked with interruptions off — extended the interrupt-off test through wave 2: surrender click-through, 9 counted, level clear.
  - `[medium]` `[patch]` (verification-gap) `--level` is only tested on a bare `level.tscn`; the real launch never applies it — same root cause as the blind launch-path finding; documented the direct-scene command.
  - `[low]` `[patch]` (verification-gap, other) the retry wording is false under a normal launch — same as the log-wording finding.
  - `[medium]` `[patch]` (intent-alignment) reading B ("so a human can play that level") lives at the normal launch, but the diff wires only `level.tscn` — same root cause; the documented direct-scene launch satisfies the intent.
  - `[low]` `[reject]` (intent-alignment) the flag-off tests use `Config.load_data` rather than F5's reload-and-restart — the spec's Code Map prescribes exactly this TEMP_FLAGS pattern; F5's reload is pre-existing and tested in `test_debug_tools.gd`.

## Design Notes

**Record-only decisions** (the docs are silent):
- The beats live in a separate dev level, not `level_dev.json`, so no existing test meets a story pause.
- `--level` exists only so a human can play it from the command line. It is debug-only, like `--comms`.
- The dev reinforcements are wasps, because the Maul is not built until Epic 6.
- The trigger timings follow the GDD L1 table: interruption at 0.25 (W3) and surrender at 0.30 (W5).

**Draft lines** (the implementer may polish them; combat lines must stay at most 50 characters):
```
l1_w3_isolde_interrupt: Running with rebels now, Arden? How very sad.
l2_w3_isolde_interrupt: Your new friends die so easily, General.
l3_w3_isolde_taunt:     No admiral to hide behind now, Arden.
l1_w5_surrender:        You're outnumbered, General. Come home.
```

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import`: expected to complete. Run it in case a test file adds a `class_name`.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`: expected all tests to pass.

**Manual check (human, not required for done):** run the game with `-- --level=dev_isolde` and confirm that the interruption box appears and the surrender pause appears.

## Auto Run Result

Status: done

**Summary:** Isolde's flag-gated interruption and surrender prompt are added as plain data on the Story 5.3 trigger machinery. There are four dialogue sequences and a dev level, `level_dev_isolde`, that uses both patterns. A debug-only `--level=<id>` arg lets a human play that level, and the level-author patterns are documented in the architecture. `CommsChannel`, `WaveDirector`, `BeatTrigger` and `LevelValidator` are unchanged.

**Files changed:**
- `game/data/dialogue/level_1.json`: `l1_w3_isolde_interrupt` (combat) and `l1_w5_surrender` (story, exact text, no choice).
- `game/data/dialogue/level_2.json`: `l2_w3_isolde_interrupt` (combat).
- `game/data/dialogue/level_3.json`: `l3_w3_isolde_taunt` (combat).
- `game/data/levels/level_dev_isolde.json`: the 2-wave dev level, with the gated interruption, the `reinforcements` group and the paired surrender triggers.
- `game/ui/debug/debug_args.gd`: `LEVEL_PREFIX` and the `level` key; an empty value warns and is ignored.
- `game/scenes/level/level.gd`: static `debug_level_id`; `_ready` swaps the id in before `resolve_level_id` and logs one INFO `[debug]` line.
- `game/tests/unit/test_isolde_beats.gd` (new): every I/O matrix row on the real `level.tscn`, plus the `--level` and retry rows.
- `game/tests/unit/test_debug_args.gd`: tests for the `level` key.
- `game/tests/data/test_data_files.gd`: the four beats' files, modes, lines and text, and the dev level's shape.
- `_bmad-output/game-architecture.md`: the `--level` debug entry, the Level-author trigger patterns block, the directory inventory and the As-built (Story 5.6) section.

**Review findings:** 23 total: 3 medium, 19 low, 1 false.
- **Patched (4 entries):**
  - medium: the `--level` launch path is now documented.
  - low: the "ignored" log wording is corrected.
  - low: the interrupt-off test now checks that the reinforcements arrive.
  - low: the surrender-off test checks for a pause more thoroughly.
- **Deferred:** none.
- **Rejected:** 12 low and 1 false, each with its reason in the Review Triage Log.

**Follow-up review recommended:** false. The patches were 1 medium and 3 low, with no high, and the medium fix was documentation only.

**Verification:** `--import` exited 0. The full headless GUT suite passed 1288 of 1288 tests, before and after the review patches, with no orphans; the only engine errors come from older tests that cause them on purpose. The matrix audit passed: every row has a test that ran and passed.

**Residual risks:**
- `--level` only takes effect when `level.tscn` is the launched scene:
  `"<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game res://scenes/level/level.tscn -- --level=dev_isolde`.
  The manual check above should use this command.
- The wave-flow tests wait on real time, with 3-10 s caps, so they may be slow on a loaded machine.
- The feel of the beats has not been checked: a human still needs to play `dev_isolde`.

