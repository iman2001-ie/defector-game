# Story 8.4 record sheet: playthroughs and playtest

This is the operator's sheet for Story 8.4. Nothing on it is done yet. Fill it in as you play, and leave a row blank until it has really happened.

- **Playthroughs:** 3 runs, start to finish, on a release build with a fresh save. Each run is checked with `tools/beat_audit.py`.
- **Playtest:** 3 to 5 people, no verbal help.
- **Retune:** only if the playtest gives a reason, and only in data (see the last section).

## 1. Playthroughs

### How to run them

1. Export the release build from the repo root (`<GODOT_DIR>` is in `LOCAL.md`):

   ```bash
   "<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import
   "<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --export-release "Windows Desktop" export/windows/DEFECTOR.exe
   ```

   Note the commit you exported from (`git rev-parse --short HEAD`) for the Commit column below.

2. For each run:
   1. Delete `%APPDATA%\DEFECTOR\save.cfg`, so the run starts from a fresh save. The audit checks this from the log.
   2. Launch `game/export/windows/DEFECTOR.exe`.
   3. Press PLAY and play to the end screen. At the Level 1 surrender prompt, pick **REFUSE**. SURRENDER loses the level by design ("EXECUTED AT DAWN"). At the Level 3 Final Choice, cover both branches: pick **OFFER SURRENDER** in at least one run and **DESTROY HER** in at least one other.
   4. On the end screen, press BACK TO TITLE, then QUIT. Release builds hold the log in memory until the game exits, so always quit normally. If the game crashes, the log may be empty or cut short: record that as a crash.
3. After the third run, audit all three:

   ```bash
   uv run python tools/beat_audit.py --latest 3
   ```

   Each launch writes its own log, and Godot keeps the last 5, so `--latest 3` audits exactly those three runs. Don't launch the game, the editor or the GUT tests between the runs and the audit, because they write logs to the same folder. If you do, pass the three log files by path instead.

### What the audit checks

A run passes (`result=PASS`) when all of these are true:

- the log says `[INFO][boot] Build: release`
- the first save line is `No save at ...` (a fresh save)
- every required beat fired in order (only each beat's first occurrence counts, because retries repeat beats):
  1. opening
  2. Isolde's L1 interruption
  3. the L1 surrender prompt
  4. Isolde's L2 interruption
  5. Tarek's fall
  6. Ryn's report
  7. Isolde's L3 taunt
  8. the Final Choice
  9. Isolde's final line
  10. the council epilogue
  11. the end screen
- the log has no errors

A beat whose flag is off in `game/data/flags.json` shows as `skipped (flag off)`. Every flag that gates a beat ships on.

For each run, the audit also prints the attempts per level, the time to the end screen, the choices picked and each attempt's ally kill-share line. Copy them into the tables below (the kill-share lines go in section 4).

### Results

| Run | Date | Commit | Audit result | Attempts L1 / L2 / L3 | Choices (L1 / L3) | Time to end screen | Crash or soft-lock notes |
|---|---|---|---|---|---|---|---|
| 1 | | | | | | | |
| 2 | | | | | | | |
| 3 | | | | | | | |

## 2. Playtest (3 to 5 people)

**Setup:** use the release build and delete `save.cfg` before each person. Don't explain the controls or the story, and give no verbal help while they play. Record people only as P1 to P5, with no names and no employer.

**Targets:**

- total playtime of 10 to 15 minutes
- 1 to 3 attempts per level

**Total playtime** is the time from pressing PLAY to reaching the end screen, timed by the observer. Don't use the audit's "time to end screen" for it: that counts seconds since launch, so it includes time spent on the title.

Count the attempts from what you see, or run the audit on that person's log: `uv run python tools/beat_audit.py --latest 1`.

| Tester | Understood controls by L1 W2 (Y/N) | Attempts L1 | Attempts L2 | Attempts L3 | Total playtime | Finished? (or where they stopped) | "Was the shooting fun on its own?" | "Which story moment do you remember?" |
|---|---|---|---|---|---|---|---|---|
| P1 | | | | | | | | |
| P2 | | | | | | | | |
| P3 | | | | | | | | |
| P4 | | | | | | | | |
| P5 | | | | | | | | |

## 3. Observation checklist (open questions from Epic 8)

Note what you see during the playthroughs and the playtest.

| Question | What to watch | Observed |
|---|---|---|
| Does the Level 1 convoy (100 HP) survive real play? | The convoy bar through wave 3 (Mauls) and wave 5 (the 4 Maul reinforcements). Any CONVOY LOST? | |
| Do Level 2's Bastions shield the Needles? | Waves 2, 4 and 5: can you get a clean shot at the Needles? | |
| Is the throne-world arc actually visible? | Level 3 and the end screen: does the planet arc at the top edge read as the throne world? | |
| Does the boss-death sweep cause a one-frame spike? | The Flagship's death with Wasps and bullets on screen: any visible hitch? | |
| Is the loudness right? | The non-tier SFX play at 0 dB and nothing limits summed clipping. Is anything harsh, crackling or too loud against the -10 dB music? | |
| Music carry-over into the menus | Music still plays on the title, Level Select and the retry-to-title path (only the final level clear fades it). Is it acceptable or does it need a fix? | |

## 4. Ally kill-share recheck (#47)

The ally fire interval (`allies.fire_interval_s`, 1.0 s) is provisional. Check it against the 10 to 15% ally kill-share target.

- **On the playtest level:** run `dev_ally` in a debug build with `"<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game res://scenes/level/level.tscn -- --level=dev_ally`. Read the `[INFO][combat] Kills: N total, ally M (P%); target 10-15%` line it logs when the level ends.
- **In the campaign:** every attempt of a level with an ally (Levels 1 to 3) also logs that line. The audit prints each one in the run's block as `kill share: <message>`, in log order, one per attempt, or `kill share: none`. These lines are information only and never change PASS / FAIL.

| Source | Kills line (total, ally, %) | In 10 to 15%? |
|---|---|---|
| `dev_ally` | | |
| Run 1 (L1 / L2 / L3) | | |
| Run 2 (L1 / L2 / L3) | | |
| Run 3 (L1 / L2 / L3) | | |

## 5. Tuning changes

Only retune when the playtest gives a reason. Change data only (`game/data/tuning.json`, or `flags.json` for a beat), never code. Tests read playtest-tuned values from tuning and check only ranges, so a retune needs no test edits.

Log every change as a new row in the GDD decision log (`_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md`), giving the old value, the new value and the playtest evidence. If a retune changes visuals or entity counts, re-run the benches (Story 8.3).

| Key | Was | Now | Evidence (tester or run) | Decision-log row |
|---|---|---|---|---|
| | | | | |
