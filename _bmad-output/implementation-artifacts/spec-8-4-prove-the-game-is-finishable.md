---
title: 'Story 8.4: Prove the Game Is Finishable'
type: 'feature'
created: '2026-10-13'
status: 'awaiting-operator'
operator_actions:
  - 'Export the release build ("<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import, then --headless --path game --export-release "Windows Desktop" export/windows/DEFECTOR.exe) and note the commit (git rev-parse --short HEAD) in the record sheet.'
  - 'Play the campaign start to finish three times on game/export/windows/DEFECTOR.exe, deleting %APPDATA%\DEFECTOR\save.cfg before each run, picking REFUSE at the Level 1 surrender prompt, OFFER SURRENDER at the Final Choice in at least one run and DESTROY HER in at least one other, and quitting normally from the title after the end screen each time.'
  - 'Without launching the game, the editor or the GUT tests in between, run uv run python tools/beat_audit.py --latest 3 and confirm all three runs report result=PASS (no crash, no soft-lock, every beat fired in order, fresh save, release build); fix and replay any run that fails.'
  - 'Fill in the Playthroughs results table in _bmad-output/implementation-artifacts/playtest-8-4-record.md (date, commit, audit result, attempts, choices, time, crash or soft-lock notes).'
  - 'Run a playtest with 3 to 5 people on the release build, deleting save.cfg before each person and giving no verbal help, and record for each (P1 to P5 only, no names) whether they understood the controls by Level 1 Wave 2, attempts per level, total playtime from PLAY to the end screen, whether they finished, and their answers to "Was the shooting fun on its own?" and "Which story moment do you remember?".'
  - 'Fill in the record sheet''s observation checklist (Level 1 convoy survival, Bastions shielding Needles, throne-world arc visibility, boss-death frame spike, loudness and clipping, music carrying over into the menus) and the ally kill-share recheck against the 10 to 15% target (dev_ally plus the kill share lines the audit prints), per decision #47.'
  - 'If the playtest shows a need, retune in data only (game/data/tuning.json or flags.json), add a decision-log row per change with the old value, the new value and the evidence, re-run the benches if visuals or entity counts changed, then update decision #68''s status to record that the playthroughs and playtest are done.'
baseline_revision: '96a4015c22b408383a611f66fd2504c2e13f3349'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The story's ACs are human work: three start-to-finish playthroughs on a release build with a fresh save, and a 3–5 person playtest. The playthrough AC says beats are "verified against INFO beat logs in godot.log", but today only some beats log an `[INFO][beat]` line: the opening, the Final Choice, the epilogue and reaching the end screen don't. Nothing checks a log either, and there is nowhere to record the results.

**Approach:** Do the agent-side work so the operator's runs are quick to check:
- (1) Make every AC beat log an `[INFO][beat]` line, and log the build type at boot.
- (2) Add a stdlib `tools/beat_audit.py` that checks one or more `godot.log` files. A run passes when it is a release build with a fresh save, every required beat fired in order, it reached the end screen, and the log has no errors. The tool also reports attempts per level and the time to the end screen.
- (3) Add a record sheet for the three playthroughs and the playtest.

The playing, the playtest and any retune it leads to are owed to the operator.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript. Write the failing GUT test first.
- Log through `Log` only, using the `beat` category for the new beat lines and `boot` for the build line. Use the exact message formats in the matrix below, because they are the contract with `beat_audit.py`.
- `beat_audit.py` uses only the standard library and follows the `perf_check.py` conventions: a docstring with usage, `REPO`-relative paths, and the log folder taken from the `APPDATA` environment variable (`DEFECTOR\logs`). No machine paths.
- The tool reads `game/data/flags.json`. A beat whose flag is off is reported as `skipped (flag off)`, not as missing.
- Python tests use `unittest` with temporary files, matching `tools/test_perf_check.py`. There are no real launches.
- The record sheet identifies playtesters only as P1–P5: no names and no employer.

**Never:**
- Don't change game flow, tuning, dialogue, levels or flags.
- Don't retune anything without playtest evidence. Any retune is the operator's call after the playtest, in data only, and logged in the decision log.
- Don't add an autoplay mode.
- Don't enable `flush_stdout_on_print`. That is still the user's call (Story 8.3 residual).
- Don't claim any playthrough or playtest as done.
- Don't write `sprint-status.yaml`. Don't commit logs, exports or zips.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Boot line | Any boot, before the stress or bench redirect | `[INFO][boot] Build: release` or `Build: debug`, from `OS.is_debug_build()` | none |
| Story beat | StoryScene `_ready` with a pending sequence | `[INFO][beat] Story '<id>'`, e.g. `opening_main` or `ending_council` | no pending sequence: keep the existing WARN, no beat line |
| Choice beat | `CommsChannel._on_final_choice_chosen(id)` accepted | `[INFO][beat] Choice '<id>' picked in '<sequence>'`, for both the L1 surrender and the L3 Final Choice | a rejected unknown option logs no beat line |
| End beat | EndScreen `_ready` | `[INFO][beat] End screen: campaign finished <s> s after launch (final choice '<id>')`. `<s>` is the integer `Time.get_ticks_msec() / 1000`. The choice is `GameState.final_choice`, `none` when empty | fatal config: still logged |
| Audit pass | A complete release run | One block per log file listing each required beat as `ok` / `MISSING` / `OUT OF ORDER` / `skipped (flag off)`, `attempts L1=a L2=b L3=c`, `time to end screen <s> s`, choices picked, then `result=PASS`. Exit 0 | none |
| Required beats (in first-occurrence order) | `Story 'opening_main'`; L1 `comms 'l1_w3_isolde_interrupt'` (isolde_interruptions); L1 `comms 'l1_w5_surrender'` (surrender_prompts); L2 `comms 'l2_w3_isolde_interrupt'` (isolde_interruptions); L2 `story event 'tarek_fall'` (tarek_fall); `Level 2 outro 'l2_ryn_report'`; L3 `comms 'l3_w3_isolde_taunt'` (isolde_interruptions); `Choice '<any>' picked in 'l3_final_choice'`; `Level 3 outro 'l3_isolde_final'`; `Story 'ending_council'` (council_epilogue); `End screen: campaign finished` | the wave number in a `Level N wave W:` line is matched loosely | a missing beat, or a beat whose first occurrence comes before an earlier required beat, makes the run FAIL |
| Not fresh | The first `[...][save]` line is not `No save at` | `fresh save: NO`, FAIL | no save line at all: FAIL |
| Debug build | `Build: debug`, or no build line | FAIL `not a release build` | `--allow-debug` turns this into a note, not a failure |
| Errors | Any line starting `[ERROR]`, `ERROR:` or `SCRIPT ERROR:`; the INFO line `Tarek's fall: no patrolling Tarek; scene skipped` | listed (first 10), FAIL | WARN lines are only counted |
| Inputs | `beat_audit.py [LOG ...]`, or `--latest N` (default 1 with no paths): the N newest `godot*.log` in the APPDATA log folder | every run audited. Exit 0 if all PASS, 1 if any FAIL | no logs or no APPDATA: message and exit 2 |

</intent-contract>

## Code Map

- `game/scenes/boot/boot.gd:31` -- `_ready`: add the build line first, before the stress redirect. `tests/unit/test_boot.gd` already captures through `Log.sink`.
- `game/scenes/story/story.gd:23-38` -- `_ready`: log the story beat after `_sequence` resolves, when it is non-empty. Tests: `tests/unit/test_story_scene.gd`.
- `game/systems/comms/comms_channel.gd:446-479` -- `_on_final_choice_chosen`: log the choice beat once the option is found, just before `Events.final_choice_made`. `_requested` holds the choice sequence id. Tests: `test_comms_channel.gd` / `test_final_choice.gd`.
- `game/scenes/end/end_screen.gd:52-66` -- `_ready`: add the end beat next to `End screen ready`. Tests: `tests/unit/test_end_screen.gd`.
- `game/systems/waves/wave_director.gd:218,613,623,727` -- existing beat formats: `Level %d intro '%s'`, `Level %d wave %d: comms '%s'`, `... story event '%s'`, `Level %d outro '%s'`. These are read-only, and the audit patterns must match them.
- `game/scenes/level/level.gd:138` -- `Level %d '%s' started (%s)%s`, logged once per attempt (retries included) under `[INFO][scene]`. Attempts are counted from this line.
- `game/autoloads/save_manager.gd:46,62` -- `No save at ...` / `Save loaded from ...` under `[INFO][save]`. Logged when the title first loads progress. This is the fresh-save signal.
- `game/autoloads/log.gd:42` -- line format `[LEVEL][category] message`.
- `game/systems/story/tarek_fall_scene.gd:149` -- the skipped-scene INFO line counts as a problem.
- `game/data/flags.json` -- the flags that gate beats (all on in the shipped data).
- `game/data/dialogue/*.json`, `game/data/levels/level_[123].json` -- the source of every sequence id in the manifest. Choice ids: L1 `surrender` / `refuse`, L3 `surrender` / `destroy`.
- `tools/perf_check.py` + `tools/test_perf_check.py` -- the pattern to copy for the module docstring, `REPO`, the `APPDATA` log dir, argparse and the exit codes.
- `game/project.godot:16-17,34-35` -- custom user dir `DEFECTOR`, file logging on. On each launch Godot copies the old log to `godot<timestamp>.log` and truncates `godot.log`. Release builds buffer the file log until exit.
- `_bmad-output/game-architecture.md:433-443` -- the Logging section: document the new beat lines and the build line. Deployment / Verification (~1280-1310): add `beat_audit.py`.
- `decision-log.md` -- the last row is #67. Format: `| # | YYYY-MM-DD | Decision / Change | Source | Status |`.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_boot.gd`, `test_story_scene.gd`, `test_comms_channel.gd` (or `test_final_choice.gd`), `test_end_screen.gd` -- write these failing tests first, one per GDScript row of the matrix: the exact message text, through `Log.sink`. The story test covers the opening and the epilogue. The choice test covers both the L1 refuse and the L3 destroy, plus no line for an unknown option. The end test checks the `final choice 'none'` default.
- `boot.gd`, `story.gd`, `comms_channel.gd`, `end_screen.gd` -- add the four log lines.
- `tools/beat_audit.py` (new) and `tools/test_beat_audit.py` (new) -- the manifest, the parser, the per-run report and the CLI from the matrix. The tests cover:
  - a full passing log;
  - each failure kind: a missing beat, out of order, not fresh, debug, `--allow-debug`, an error line, the Tarek skip line, a run that never reaches the end;
  - a flag off giving `skipped`;
  - attempts counted with retries;
  - `--latest N` picking the newest files by mtime;
  - no logs giving exit 2;
  - every manifest sequence id existing in `game/data` (so the manifest can't drift from the data).
- `_bmad-output/implementation-artifacts/playtest-8-4-record.md` (new) -- the operator's record sheet:
  - **Playthroughs:** how to run them. Export the release build, delete `%APPDATA%\DEFECTOR\save.cfg`, launch, play to the end screen and quit. Then run `uv run python tools/beat_audit.py --latest 3`. Pick REFUSE at the L1 surrender prompt, or the level is lost by design.
  - **Results table:** run, date, audit result, crash or soft-lock notes.
  - **Playtest table** for P1–P5: understood controls by L1 W2 (Y/N), attempts L1/L2/L3, total playtime, "Was the shooting fun on its own?", "Which story moment do you remember?". State the 10–15 min and 1–3 attempts targets.
  - **Observation checklist** from the epic's open questions: the Level 1 convoy surviving, Bastions shielding Needles, whether the throne-world arc is visible, a frame spike at the boss's death, loudness and clipping, and music carrying over into the menus.
  - **Ally kill-share recheck:** check the 1.0 s fire interval against 10–15% using the `Kills:` line on `dev_ally` (#47).
  - **Tuning changes:** the rule is data only, plus a decision-log row.
- `_bmad-output/game-architecture.md` -- Logging: list the beat lines and the boot build line. Verification and Deployment: `beat_audit.py`.
- `decision-log.md` -- append #68 (2026-10-13, Story 8.4). This is record-only: the new beat lines and build line, the audit tool and its pass rule, and the record sheet. Status: `Tooling applied; playthroughs and playtest owed to the operator`.

**Acceptance Criteria:**
- Given the full GUT suite and every tools unit test, when they run, then all pass.
- Given a release export of the current game, when it is launched with `--headless --quit-after 600` (a clean exit, so the release build's buffered file log is flushed), then its log contains `[INFO][boot] Build: release`, and `beat_audit.py` on that log reports `result=FAIL` with every campaign beat `MISSING`. This proves the tool reads a real release log.
- Given a synthetic log built from the exact GDScript message formats for a full run, when `beat_audit.py` audits it, then the result is PASS with attempts and time reported.

## Spec Change Log

## Review Triage Log

### 2026-10-14 — Review pass
- verdicts: 30 findings — high 0, medium 1, low 20, false 9, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) Docs call `Build:` "the first line of every boot", but the Config autoload's `[data]` load lines come first — reworded in boot.gd, the architecture Logging bullet and #68 to "the first line the boot scene logs (after the autoloads' load lines)".
  - `[low]` `[patch]` (blind) `SHADER ERROR:` lines are not counted as errors — `_is_error` now also matches `SHADER ERROR:` and any `Program crashed` line, with a test each.
  - `[low]` `[reject]` (blind) The audit never checks for a clean exit (the title's quit line) — release builds buffer the file log until a clean exit, so a crash loses the tail, including the end beat, and the run already FAILs; a required quit line adds a rule the AC does not ask for.
  - `[low]` `[reject]` (blind) OUT OF ORDER blames the later beats when one beat is misplaced late — the result is still a correct FAIL. The beat order is fixed by game flow, so this is not met in real play, and the fix needs a longest-increasing-subsequence.
  - `[low]` `[patch]` (blind) The record sheet says "All flags ship on" but `hunter_wasp` ships off — now says every flag that gates a beat ships on.
  - `[low]` `[patch]` (blind) The results table has no column for the choices the text says to copy — added "Choices (L1 / L3)".
  - `[low]` `[patch]` (blind) Nothing makes the runs cover both Final Choice branches — the run steps now ask for OFFER SURRENDER in one run and DESTROY HER in another.
  - `[low]` `[patch]` (blind) No build identity is recorded per run — added a "Commit" column and a note to record `git rev-parse --short HEAD`.
  - `[low]` `[patch]` (blind) "Total playtime" is undefined and the audit's time includes the title — defined as PLAY to the end screen, timed by the observer, with a note on the audit's number and a "Finished? (or where they stopped)" column.
  - `[low]` `[patch]` (blind) The audit does not print the `Kills:` lines the sheet asks the operator to copy — each run's block now lists them (`kill share: ...`, information only), with a test and a format-contract entry.
  - `[low]` `[patch]` (blind) The regenerated `epic-8-context.md` misstates the SFX sources — the Audio bullet now says 14 are Kenney, 5 are generated and `comms_static` is recorded. The other dropped details (accent hexes and the like) were dropped by design: the step-01 compile scopes aggressively and the full docs keep them.
  - `[false]` `[reject]` (blind) Two ACs have no recorded evidence — the orchestrator ran both after implementation and again after the patches (see Verification under Auto Run Result); evidence is recorded at finalization by design.
  - `[low]` `[reject]` (blind) The drift test picks its check from label substrings and a loose `flagship.gd` match — developer-only; a reworded label makes the test fail loudly rather than pass. Adding a `kind` field is more than a direct correction.
  - `[low]` `[reject]` (blind) The end beat's final choice is never cross-checked against the L3 pick — the regression is speculative (the L3 choice overwrites `GameState.final_choice`), and the check adds a branch.
  - `[low]` `[patch]` (blind) The new GUT tests skip the L1 `surrender` and L3 `surrender` options, and `_lines_at_choice` is declared mid-file — the coverage part is rejected because the beat line comes before any option-specific branch, so the code path is identical. The declaration was moved up with the other members.
  - `[low]` `[patch]` (edge) Crash-handler and `SHADER ERROR:` lines are not errors — same root cause as the blind error-prefix finding; same fix.
  - `[low]` `[reject]` (edge) The running-max order check mislabels beats — same as the blind finding; rejected for the same reason.
  - `[low]` `[patch]` (edge) `--latest N` with fewer logs found still exits 0 — each missing log now counts as a FAIL (shown in the summary, exit 1), and the old test was updated.
  - `[low]` `[reject]` (edge) A comms beat could log its request but be preempted or dropped by the channel — the AC defines the check as the INFO beat lines. The combat queue never drops a queued line (Story 5.2 record), and no story sequence runs in those beats' windows; requiring channel lines adds branches.
  - `[low]` `[reject]` (edge) A missing or malformed `flags.json` gives a traceback with exit 1 — the shipped file is pinned by `test_flags_come_from_the_shipped_data`. Unlikely, and the guard adds a branch.
  - `[medium]` `[patch]` (edge) `test_boot_logs_the_build_line_first` does not await, so the deferred `goto_title` runs after `after_each` restores the real `change_scene` and save path — added `await wait_process_frames(1)`, like the other boot tests.
  - `[low]` `[reject]` (edge) The epic context dropped the `comms_static` / `cutoff_hide_s` coupling note — the compile rules scope the context aggressively, and the coupling is recorded in the full planning docs (#40-#43).
  - `[low]` `[patch]` (edge) The epic context says all 20 SFX ids are Kenney — same root cause as the blind epic-context finding; same fix.
  - `[low]` `[patch]` (verification-gap) The build line is not the first line of every boot — same root cause as the first blind finding; same fix.
  - `[false]` `[reject]` (intent) Finalization is missing (status, `operator_actions`, commit, Auto Run Result) — review runs before finalization by design; this pass sets `awaiting-operator`, the operator actions and the commit.
  - `[false]` `[reject]` (intent) There is no evidence that the real release-log AC ran — the orchestrator exported the release build and ran `--headless --quit-after 600` twice: `Build: release`, 11 beats MISSING, `result=FAIL`.
  - `[false]` `[reject]` (intent) There is no operator JSON like Story 8-3's — that file lives in `.bmad-loop/operator/` and the orchestrator writes it when parking the story (it carries `run_id` and `parked_at`). build-auto supplies `operator_actions` in the spec.
  - `[false]` `[reject]` (intent) The audit cannot tell a crash from a quit before the end — both FAIL, and the record sheet's notes column captures which one it was; the auditor itself calls this a reasonable stand-in.
  - `[false]` `[reject]` (intent) No agent run exercises the beats in a real campaign — the auditor itself says leaving the play to the operator matches the intent (the AC says "I play"), and each level's beat chain is covered by the existing level tests.
  - `[false]` `[reject]` (intent) The playtest AC is covered only by documentation — the playtest is human work, which the intent routes to `operator_actions`.

## Design Notes

The required-beat manifest lives in the tool, not in game data, because it is a QA contract and not tuning. A test ties every id in it to `game/data`. First-occurrence order is checked rather than exact sequence, because retries legitimately repeat beats. "Fresh save" is read from the log, so the audit proves it instead of trusting the operator. One launch is one run: the operator relaunches for each of the three runs, and Godot rotates the logs (it keeps 5 by default), so `--latest 3` audits exactly those runs.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import`, then the GUT command from AGENTS.md -- expected: all pass.
- `uv run python -m unittest tools/test_beat_audit.py tools/test_perf_check.py tools/test_import_cc0_art.py tools/test_import_cc0_audio.py tools/test_recolor_player_ship.py tools/test_gen_placeholder_sfx.py` -- expected: OK.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --export-release "Windows Desktop" export/windows/DEFECTOR.exe`, then `game/export/windows/DEFECTOR.exe --headless --quit-after 600`, then `uv run python tools/beat_audit.py --latest 1` -- expected: `Build: release` is in the log, and the audit reports FAIL with the beats missing (no play happened).

## Auto Run Result

Status: awaiting-operator

**Summary.** Story 8.4 is done as far as an agent can take it. Every AC beat now leaves an `[INFO][beat]` line in `godot.log`:
- the WaveDirector's existing lines;
- three new lines: `Story '<id>'` (the opening and the epilogue), `Choice '<id>' picked in '<sequence>'` (the L1 surrender and the L3 Final Choice) and `End screen: campaign finished <s> s after launch (final choice '<id>')`.

The boot scene also logs `Build: release|debug`.

The new `tools/beat_audit.py` audits one or more playthrough logs. A run passes when:
- it is a release build;
- it started from a fresh save (read from the log);
- every required beat fired, in order by first occurrence (a beat whose flag is off is skipped);
- it reached the end screen;
- the log has no error, shader-error, crash or skipped-Tarek's-fall lines.

The audit also reports attempts per level, the time to the end screen, the choices picked and the ally kill-share lines.

The record sheet `playtest-8-4-record.md` covers the three playthroughs, the P1–P5 playtest, the Epic 8 observation checklist, the ally kill-share recheck and the data-only retune rule. Game flow, tuning, dialogue, levels and flags are unchanged. The three human playthroughs, the playtest and any resulting retune are owed to the operator (see `operator_actions`).

**Files changed**
- `game/scenes/boot/boot.gd`: the `Build:` line, plus a static `build_type()`.
- `game/scenes/story/story.gd`: the `Story '<id>'` beat line.
- `game/systems/comms/comms_channel.gd`: the `Choice ... picked in ...` beat line.
- `game/scenes/end/end_screen.gd`: the end-of-run beat line.
- `tools/beat_audit.py` (new): the beat manifest, the log audit and the CLI (`--latest N`, `--allow-debug`).
- `tools/test_beat_audit.py` (new): 41 stdlib tests, including drift checks against `game/data` and the GDScript format strings.
- GUT tests in `test_boot.gd`, `test_story_scene.gd`, `test_comms_channel.gd` and `test_end_screen.gd`.
- `_bmad-output/implementation-artifacts/playtest-8-4-record.md` (new): the operator's record sheet.
- `_bmad-output/game-architecture.md`: the beat lines in Logging, a finishability row under Verification, and the audit in Deployment.
- `decision-log.md`: #68 (record only; playthroughs and playtest owed).
- `_bmad-output/implementation-artifacts/epic-8-context.md`: regenerated in step 1 because the decision log was newer; the SFX-source sentence was corrected in review.

**Review findings.** 30 findings: high 0, medium 1, low 20, false 9.
- **Patched**, 11 entries:
  - the boot-test await (the one medium);
  - `SHADER ERROR:` and crash lines now count as errors;
  - a `--latest` shortfall now counts as FAIL;
  - the kill-share lines are reported;
  - the build-line wording;
  - the epic-context SFX sources;
  - the misplaced test member;
  - record-sheet fixes: the flags wording, the choices and commit columns, covering both Final Choice branches, the playtime definition and a "finished" column.
- **Deferred:** none.
- **Rejected:** everything else, each with its reason in the Review Triage Log above:
  - a clean-exit rule (a crash already loses the buffered end beat);
  - the order-check labelling (the result is still a correct FAIL);
  - requiring channel lines for comms beats;
  - flags.json error handling;
  - drift-test refactors;
  - the end-choice cross-check;
  - the false intent findings, which concern finalization and are settled here.
- **Follow-up review recommended:** false. No high was patched and only one medium (patched counts: high 0, medium 1, low 10 entries).

**Verification** (orchestrator, after the patches):
- **Headless `--import`:** exit 0.
- **Full GUT suite:** 2075 tests, 2074 passing, 1 pending. The pending test is `test_feedback.gd` `test_hit_stop_overlap_keeps_longest`, in an unchanged file. Its timing guard marks it pending when the machine stalls (here, 32.8 ms). It passed in the first full run (2075/2075).
- **Tools tests:** `uv run python -m unittest tools/test_beat_audit.py tools/test_perf_check.py tools/test_import_cc0_art.py tools/test_import_cc0_audio.py tools/test_recolor_player_ship.py tools/test_gen_placeholder_sfx.py` ran 119 tests, OK.
- **Release export and audit:** `--export-release "Windows Desktop"` exit 0, then `DEFECTOR.exe --headless --quit-after 600` exit 0. `beat_audit.py --latest 1` on that log reports `build: release`, all 11 beats MISSING, `kill share: none` and `result=FAIL: not a fresh save; 11 beats missing; never reached the end screen`, as expected with no play. The save on this machine is not fresh, which is why it says so; the audit only reads it.

**Residual risks**
- Nobody has played the campaign end to end on a release build in this story. Finishability rests on the operator's three runs.
- Release builds buffer the file log (`flush_stdout_on_print` is off, Story 8.3). A crash loses the log's tail, so the audit sees a FAIL without the cause, and the operator must note crashes by hand.
- `--latest 3` takes the most recent launches. Launching the editor, the GUT tests or the game between the runs and the audit shifts that window (the record sheet warns about this).
- The audit reads `game/data/flags.json` from the repo, not the flags packed into the export, so the two must match.
