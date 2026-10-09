---
title: 'Story 5.7: Write the Dialogue Script'
type: 'feature'
created: '2026-10-08'
status: 'awaiting-operator'
operator_actions:
  - 'Read game/data/dialogue/opening.json, level_1.json, level_2.json and level_3.json top to bottom and confirm the tone is personal, not comedic, and that each line sounds like its speaker (Isolde condescending, Tarek warm, Ryn steady).'
  - 'Confirm no line refers to Vale with a gendered pronoun or term, and that others address Vale as "General" (or "Arden").'
  - 'Confirm the Final Choice mirror lands: Vale offers Isolde surrender in her own Level 1 words, and her refusal throws "Come home" back with contempt.'
baseline_revision: 'e7320cee9436afbb6cd129ecab2dbab46b7e7a30'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-5-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/EXPERIENCE.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Only the opening and Isolde's four beats exist, and they are placeholders. The Tarek warning, Tarek's closing line, the Level 2 briefing, Tarek's cut-off, Ryn's report, the Level 3 briefing, the Final Choice lead-in, Isolde's two refusals and her final line do not exist. Epics 6 and 7 need these ids (FR45, FR41, FR44).

**Approach:** This is content only. Write every campaign sequence in final form in `data/dialogue/opening.json`, `level_1.json`, `level_2.json` and `level_3.json`. Pin the ids, modes, speakers and cast rules with data tests. Record it in the architecture. No code, level file or validator changes.

## Boundaries & Constraints

**Always:**
- **Sequence layout** (file → id: mode, speakers):
  - `opening.json` → `opening_main`: story, 6-10 lines, vale / tarek / isolde only, exactly 1 Isolde line, Tarek welcomes the General and mentions the convoy (the existing Story 5.5 test must still pass).
  - `level_1.json`:
    - `l1_w3_tarek_warning`: combat, 1 tarek line (the ambush warning).
    - `l1_w3_isolde_interrupt`: combat, 1 isolde line.
    - `l1_w5_surrender`: story, exactly `You're outnumbered, General. Come home.`, unchanged, with no `choice`.
    - `l1_tarek_closing`: story, 1-2 tarek lines (the debrief).
  - `level_2.json`:
    - `l2_briefing`: story, 2-3 tarek lines.
    - `l2_w3_isolde_interrupt`: combat, 1 isolde line.
    - `l2_w5_tarek_cutoff`: combat, 1 tarek line with `cut_off_at` and `after` `{ "silence": "until_wave_clear", "shake": "large", "sfx": "comms_static", "music": "stop" }`. The cut lands mid-word.
    - `l2_ryn_report`: story, ryn only. Tarek is alive but gravely injured, and Ryn takes command.
  - `level_3.json`:
    - `l3_briefing`: story, ryn only. Ryn has taken command and briefs the siege.
    - `l3_w3_isolde_taunt`: combat, 1 isolde line.
    - `l3_final_choice`: story, isolde only (the lead-in). No `choice` key, because Story 7.5 adds it.
    - `l3_isolde_refuse_surrender`: story. Line 1 is vale (the surrender offer), then isolde. Isolde's contempt echoes "come home" (case-insensitive).
    - `l3_isolde_refuse_destroy`: story. Line 1 is vale (the vow), then isolde (defiance).
    - `l3_isolde_final`: story, isolde only.
- **Cast rules:**
  - Vale is gender-neutral. No line uses a gendered term for Vale ("sir", "ma'am", "madam", "mister", "mr", "lady", "son"). Others address Vale as "General" (or "Arden").
  - Vale speaks at most 5 lines in the campaign files: the opening plus line 1 of each refusal.
  - Each character introduces themselves in their own voice at their first appearance: Tarek, Vale and Isolde name themselves in the opening, and Ryn names herself in the first line of `l2_ryn_report`.
  - The tone is personal, not comedic. There is no narrator and no `system` speaker in campaign files.
- Use the Design Notes script as the text. The implementer may polish wording, but must keep every rule above and the validator limits (story ≤ 200 characters, combat ≤ 50).
- Tests come first, statically typed. Use the existing `test_data_files.gd` helpers.

**Never:**
- Don't touch `data/levels/*.json`. Placing the beats is Epic 7, and the "every referenced sequence exists" test (AC 3) already covers whatever the levels reference.
- Don't edit `dev.json`. Its `dev_tarek_cutoff` drives the 5.4 tests.
- Don't change `DialogueValidator`, `CommsChannel`, `Config` or `tuning.json`, and don't add a `choice` block.
- Don't add a Level 1 briefing. The opening is Level 1's story intro, and the AC doesn't list one.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Script load | the shipped dialogue files | `Config.has_sequence` true for all 15 campaign ids, `Config.dialogue_is_story` matches the layout, no load error | none |
| Cut-off | `l2_w5_tarek_cutoff` | the first `cut_off_at` chars end mid-word (the next char is a letter, the previous char is a letter) | the validator range check |
| Level refs | any `data/levels/*.json` | every referenced id exists (existing test) | none |

</intent-contract>

## Code Map

- `game/data/dialogue/opening.json`, `level_1.json`, `level_2.json`, `level_3.json`: the files to write. Shape `{ "sequences": { id: { "mode", "lines": [ { "speaker", "text", "cut_off_at"?, "after"? } ] } } }`. Use tab indentation and one line object per line, as now.
- `game/data/dialogue/dev.json`: `dev_tarek_cutoff` shows the cut-off line shape. Read-only.
- `game/systems/comms/dialogue_validator.gd`: the rules (speakers, modes, combat = 1 line ≤ 50, story ≤ 200, `cut_off_at` 1..len-1, `after` keys). Ignores unknown sequence keys. Read-only.
- `game/autoloads/config.gd`: `has_sequence`, `sequence`, `dialogue_is_story` (loads every `data/dialogue/*.json`).
- `game/tests/data/test_data_files.gd`:
  - `DIALOGUE_DIR`, `_dialogue_files()` (l.475) and `_all_sequences()` (l.573).
  - `test_opening_main_is_the_story_opening` (l.521) must keep passing.
  - `test_isolde_beats_live_in_their_level_files` (l.783) is the per-file assert pattern to copy.
  - `_interruptions()` (l.584) and the self-check (l.644) are the counting pattern.
  - `test_every_referenced_sequence_exists` (l.696) is AC 3, already present.
  - The header comment (l.1-13) lists what the file covers; extend it.
- `game/tests/unit/test_isolde_beats.gd`, `test_story_scene.gd`, `test_scene_router.gd`: these use `opening_main` / Isolde ids but no text. The full suite confirms nothing depends on line counts.
- `_bmad-output/game-architecture.md`:
  - The ids naming rule (l.~721).
  - The Comms Channel dialogue example (l.~886-920). Its `l2_w5_tarek_cutoff` text/`cut_off_at` should match the shipped line.
  - The As-built 2026-10-08 (Story 5.6) section near the end. Add a "Story 5.7" section after it, and update 5.5's "Story 5.7 can polish" remarks only if they become false.

## Tasks & Acceptance

**Execution:**
- `game/tests/data/test_data_files.gd`: add tests first (red), then write the data.
  - `test_campaign_script_layout`: a table of the 15 ids → file, mode and allowed speakers. Assert each id lives in its file, has its mode and its line-count rule, and uses only allowed speakers. Assert no `system` speaker in the campaign files and no `choice` key on `l1_w5_surrender` or `l3_final_choice`.
  - `test_refusals_open_with_vale`: both refusals have line 1 by vale and later lines by isolde. The surrender refusal's Isolde text contains "come home" (case-insensitive).
  - `test_tarek_cutoff_is_final`: mode, the `after` dictionary exactly as above, and a mid-word cut (the chars at `cut_off_at - 1` and `cut_off_at` are letters).
  - `test_cast_rules`:
    - Vale has ≤ 5 lines across the campaign files (`opening.json`, `level_1/2/3.json`).
    - No line matches the gendered-address word list (whole-word regex, case-insensitive).
    - The opening names Tarek, "Arden Vale" and Isolde in each speaker's own line.
    - `l2_ryn_report` line 1 is by ryn and contains "Ryn".
    - At least one non-Vale line in each campaign file contains "General".
  - Update the header comment.
- `game/data/dialogue/opening.json`, `level_1.json`, `level_2.json`, `level_3.json`: write the script.
- `_bmad-output/game-architecture.md`: sync the cut-off example and add the Story 5.7 As-built section (the ids, the file layout, the record-only decisions below and the tests).

**Acceptance Criteria:**
- Given the dialogue files, when the script is complete, then every id in the layout exists in its file, in its mode, in final text, and loads through `Config` without errors.
- Given the cast rules, when the new data tests run, then they pass. The tone is checked by a human reading the script, not by a test.
- Given `test_data_files.gd`, when it runs, then every sequence id referenced by any level JSON exists, and the full headless GUT suite passes with no new errors.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 22 findings — high 0, medium 1, low 8, false 13, maybe-false 0
- findings:
  - `[medium]` `[patch]` (blind) Isolde's surrender refusal "Come home? To you?" quotes words Vale never says — confirmed in `level_3.json`; the GDD mirror (USP 2) is Vale offering her own L1 choice back. Patched Vale's line to `You're outnumbered, Isolde. Surrender, and come home to your people.`
  - `[low]` `[patch]` (blind) the refusal rows allow 2-10 lines, but the GDD says the choice changes one Isolde line after one Vale line — patched both `CAMPAIGN_SCRIPT` rows to exactly 2 lines.
  - `[low]` `[patch]` (blind) no test pins the campaign files to the 15 listed ids (the size check counts only the table) — patched `test_campaign_script_layout` to compare each file's sorted keys with the table's ids for that file.
  - `[false]` `[reject]` (blind) the Vale cap (5) and the docs (4 lines) disagree — the spec sets the cap at ≤ 5 and the As-built reports the actual 4; they don't contradict each other, and no caller diverges.
  - `[low]` `[patch]` (blind) the gendered check misses terms and pronouns — patched: added `mrs`, `ms` and `lord` with self-check cases (not `miss`, which is also a verb). Pronouns can't be banned because Isolde and Ryn are "her", so they stay in the human script read (`operator_actions`).
  - `[low]` `[reject]` (blind) the regex terms aren't escaped and the regex recompiles per call — every term is a plain word today and the cost is test-only; escaping adds code for a case nobody meets.
  - `[low]` `[patch]` (blind) Ryn's "I've got his ship" is ambiguous — patched `l2_ryn_report` lines 1 and 3 ("His ship is mine now." / "And so is his fight. I'm taking command.") and synced the architecture example.
  - `[false]` `[reject]` (blind) Ryn takes command twice — the GDD puts it in both places: the L2 report ("she is taking command") and the L3 briefing ("in which she takes command").
  - `[false]` `[reject]` (blind) "wing" repeats in the opening — Tarek's "on my wing" and Vale's "I'm on your wing" are a deliberate call and answer, so no reader is misled.
  - `[low]` `[patch]` (blind) the 5.5 and 5.6 As-built data bullets still call the text placeholder — patched: appended "(final text: see As-built Story 5.7)" to each, and the dated entries are otherwise unchanged. Line 1693 is about `dev.json` and is still true.
  - `[low]` `[reject]` (blind) nothing stops a stray `cut_off_at` / `after` on other campaign combat lines — `DialogueValidator` already rejects them on story lines and rejects `after` without `cut_off_at`; a deliberate cut-off on another combat line is unlikely, and guarding it adds a new check.
  - `[false]` `[reject]` (blind) the long briefing lines hurt readability — every line is within the documented 200-character story limit, and a click completes the typing (UX).
  - `[low]` `[patch]` (edge) a stray or misnamed sequence escapes the checks — same root cause as the blind "15 listed ids" finding; patched there.
  - `[low]` `[reject]` (edge) `_campaign_lines` can hit a null `.get` on a malformed file — `test_every_dialogue_file_is_valid` catches malformed data first, and a script error still fails the test.
  - `[low]` `[patch]` (edge) `GENDERED_ADDRESS` misses Mrs / Ms / Miss / Lord — same root cause as the blind gendered-check finding; patched there (no `miss`).
  - `[false]` `[reject]` (edge) the L1 cap of 2 including the Tarek warning isn't enforced — `test_every_level_has_at_most_two_interruptions` counts level references, so it enforces the cap as soon as Epic 7 places the beats; today no level references them.
  - `[false]` `[reject]` (intent) AC 3 tests nothing new because no campaign level references the ids — the epics give placement to Epic 7 (Story 7.1 sets `outro_sequence: l1_tarek_closing`), and AC 3's test passes unchanged.
  - `[false]` `[reject]` (intent) tone and "own voice" are only checked mechanically — handled at finalize: the human script read is listed under `operator_actions` (precedent: Stories 5.1, 5.2 and 5.4), and the status is `awaiting-operator`.
  - `[false]` `[reject]` (intent) the content descriptions (contempt, defiance, lead-in) are checked only by speaker and line count — the same human read; see `operator_actions`.
  - `[false]` `[reject]` (intent) the runtime cut-off rendering isn't tested here — Story 5.4's tests cover the box stopping at `cut_off_at`; this story changes only the data.
  - `[false]` `[reject]` (intent) the architecture example edits lack a user decision — they sync the example to the shipped content, and the record-only ids follow the documented `<scene>_<beat>` rule; no GDD, architecture or UX decision changed.
  - `[false]` `[reject]` (intent) the operator clause isn't used — handled at finalize (`awaiting-operator` with `operator_actions`).

## Design Notes

**Record-only decisions** (the docs are silent):
- The Level 2 briefing id is `l2_briefing`, mirroring `l3_briefing`.
- `l1_w3_tarek_warning` is a combat line. GDD decision #22 calls it an interruption, and it counts toward Level 1's cap of 2 together with the Isolde interrupt.
- The `choice` block for `l3_final_choice` is left to Story 7.5, which builds and validates `FinalChoice`.

**Script** (the character counts were checked for the combat lines):
```
opening_main:
 tarek  Unknown Sovereignty fighter, this is Admiral Tarek Holt of the Free Worlds Coalition. Power down your weapons and state your intent.
 vale   This is General Arden Vale. I've left the Sovereignty, and I'm not going back.
 tarek  Vale. For ten years your name topped our threat reports. Welcome to the Coalition, General. I mean that.
 tarek  No time to settle in. A supply convoy runs the outer lanes tonight, and Sovereignty raiders are already hunting it.
 tarek  You fly escort on my wing. Those freighters carry medicine for three worlds. Keep them alive, whatever comes.
 isolde Arden. This is Isolde Varn, your Sovereign. You knelt to me once. Run to them if you like; I will bring you home in chains.
 vale   Let her come. Convoy's moving, Admiral. I'm on your wing.
l1_w3_tarek_warning     tarek  Contacts closing fast. It's an ambush, General!      (47)
l1_w3_isolde_interrupt  isolde Guarding freighters now, Arden? How far you fell.   (49)
l1_w5_surrender         isolde You're outnumbered, General. Come home.
l1_tarek_closing:
 tarek  Convoy's through, every ship of it. You flew like you meant it, General.
 tarek  Get some rest. Tomorrow we break her blockade, and I want you on my wing when we do.
l2_briefing:
 tarek  General, the Sovereignty has sealed the trade corridor. Nothing gets in or out, and four colonies are starving behind that line.
 tarek  Bastions anchor the blockade. Needles snipe from range, so keep a rock between you and them.
 tarek  Stay close and watch my back. I'll watch yours. That's how the Coalition flies.
l2_w3_isolde_interrupt  isolde Every ship you lead here dies, Arden. Every one.   (48)
l2_w5_tarek_cutoff      tarek  General, get behind me, I've got you covered!      (45, cut_off_at 40 → "...got you cov")
l2_ryn_report:
 ryn    General, this is Commander Ryn Holt, Tarek's daughter. I've got his ship.
 ryn    He's alive. Barely. The medics have him, and he won't fly again for a long time.
 ryn    His fight is mine now. I'm taking command.
l3_briefing:
 ryn    Commander Holt to all ships. I have the fleet now, General, and we end this today.
 ryn    Isolde's home fleet is dug in around the throne world. We break through it, then we bring down her Flagship.
 ryn    My father believed in you. Show me he was right.
l3_w3_isolde_taunt      isolde No admiral to save you this time, Arden.          (40)
l3_final_choice:
 isolde Enough. You have burned my fleet and reached my throne, Arden. I taught you well.
 isolde So, General. What will you do with me now?
l3_isolde_refuse_surrender:
 vale   It's over, Isolde. Stand down, and you walk away alive.
 isolde Come home? To you? I am home, traitor. I will burn with my throne before I kneel to what I made.
l3_isolde_refuse_destroy:
 vale   No more offers. This ends with your Flagship.
 isolde Then come and take it, General. I am the Sovereignty, and I do not break.
l3_isolde_final:
 isolde My finest general... Remember, Arden. I made you.
```

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import`: expected to complete.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`: expected all tests to pass.

**Manual checks:**
- Read the four campaign files top to bottom. Each beat should sound like its speaker, Vale should stay gender-neutral, and nothing should read as a joke.

## Auto Run Result

Status: awaiting-operator

**Summary:** The full DEFECTOR dialogue script is written in final form: 15 campaign sequences across `opening.json` and `level_1/2/3.json`. They cover the opening, Tarek's warning and closing line, the Level 2 briefing, Tarek's cut-off, Ryn's report, the Level 3 briefing, the Final Choice lead-in, Isolde's two refusals and her final line. Data tests pin the ids, modes, speakers and cast rules. There is no code, validator, level-file or `dev.json` change. Placing the beats into the real levels is Epic 7.

**Files changed:**
- `game/data/dialogue/opening.json`: `opening_main` polished (7 lines; each speaker names themselves).
- `game/data/dialogue/level_1.json`: adds `l1_w3_tarek_warning` (combat) and `l1_tarek_closing` (story); `l1_w3_isolde_interrupt` final text; the surrender line is unchanged.
- `game/data/dialogue/level_2.json`: adds `l2_briefing`, `l2_w5_tarek_cutoff` (`cut_off_at` 40, cut at "...got you cov") and `l2_ryn_report`; `l2_w3_isolde_interrupt` final text.
- `game/data/dialogue/level_3.json`: adds `l3_briefing`, `l3_final_choice` (no `choice`; Story 7.5 adds it), `l3_isolde_refuse_surrender`, `l3_isolde_refuse_destroy` and `l3_isolde_final`; `l3_w3_isolde_taunt` final text.
- `game/tests/data/test_data_files.gd`: adds `test_campaign_script_layout`, `test_refusals_open_with_vale`, `test_tarek_cutoff_is_final` and `test_cast_rules`, plus two helper self-checks.
- `_bmad-output/game-architecture.md`: the Comms Channel example is synced to the shipped cut-off and Ryn lines; adds the As-built 2026-10-08 (Story 5.7) section and pointers from the 5.5 and 5.6 data bullets.

**Review findings:** 22 in total (high 0, medium 1, low 8, false 13).
- **Patched (6 entries: 1 medium, 5 low):**
  - Vale's surrender offer now mirrors Isolde's L1 line.
  - The refusals are pinned to exactly 2 lines.
  - Each campaign file must hold exactly its listed ids.
  - `mrs`, `ms` and `lord` are added to the gendered-term check.
  - Ryn's report says plainly that she has his ship.
  - The 5.5 and 5.6 As-built bullets point to the final script.
- **Deferred:** none.
- **Rejected (low):**
  - Regex escaping: the terms are plain words.
  - A stray cut-off guard: the validator covers most cases, and a stray cut-off is unlikely.
  - A malformed-file null guard: the validity test already catches malformed files.
- **Rejected (false):** the 13 false findings, each refuted in the Review Triage Log.

**Follow-up review recommendation:** false. The patches were 1 medium and 5 low, with no high.

**Verification:**
- `--import` completed with exit 0.
- Full headless GUT suite before the patches: 1293 passed and 1 pending. The pending test is `test_feedback.gd` `test_hit_stop_overlap_keeps_longest`, a timing guard unrelated to this story.
- After the patches: 1294 of 1294 passed, 0 failures.
- Matrix audit passed: script load is covered by `test_campaign_script_layout`, the cut-off by `test_tarek_cutoff_is_final`, and level refs by `test_every_referenced_sequence_exists`.

**Residual risks:**
- Only a human can judge the tone, the voice, and gender neutrality through pronouns (see `operator_actions`).
- None of the new beats is reachable in a campaign level until Epic 7 places them. Once it does, `l1_w3_tarek_warning` and the Isolde interrupt fill Level 1's cap of 2 interruptions.
