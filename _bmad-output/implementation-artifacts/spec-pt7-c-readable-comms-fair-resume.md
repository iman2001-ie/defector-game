---
title: 'Epic 7 playtest C: readable combat comms and a fair resume'
type: 'feature'
created: '2026-10-13'
status: 'done'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Combat lines appear in a small top-left box, far from where the player is looking, and they're too small and too brief to read mid-fight. After a story pause (or the Esc menu) the game resumes at full speed, so a bullet that was about to be dodged can't be.

**Approach:** Move the box to the bottom centre and make it bigger. Its background is semi-transparent, and it turns more see-through when the ship or an enemy bullet is behind it. Lines stay up longer. The Isolde/Tarek interruptions move into the calm gap after the previous wave clears. The Esc pause menu lists the last few combat lines. Every in-level resume starts in slow motion and ramps back to normal speed over about 1 s, through `Feedback`.

## Boundaries & Constraints

**Always:** All numbers live in `tuning.json` and are read through Config. Only `Feedback` writes `Engine.time_scale`. The box stays mouse-transparent and one line at a time. A 50-character line must fit 2 lines. Nothing vanishes on resume.

**Ask First:** none (operator agreed 2026-10-13: bottom centre plus the extras).

**Never:** Pausing combat lines. Clearing or freezing bullets on resume. Slow motion on a scene change.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior |
|---|---|---|
| Combat line | any | the box shows bottom centre, rising into place, and stays `max(min_s, chars/45 + extra_s)` s |
| Ship under box | the player overlaps the box rect (grown by a margin) | box alpha drops to `see_through_alpha`, then returns once clear |
| Enemy bullet under box | the same, for an enemy projectile | the same |
| Story pause ends in a level | pop of the last reason | time_scale starts at `resume_slowmo.scale` and ramps to 1 over `ramp_s` real seconds |
| Hit-stop during the ramp | impact | time_scale 0 for the stop, then back to the current ramp value |
| Scene change (clear) | no Player in the tree | no slow motion |
| Esc menu | combat lines were shown | the menu lists the last `recent_comms` lines (speaker and text), newest first |

</frozen-after-approval>

## Code Map

- `game/systems/comms/comms_box.gd` (+ tscn) -- layout, rise-in, see-through
- `game/systems/comms/comms_channel.gd` -- emits `Events.comms_line_shown`
- `game/autoloads/events.gd` -- new signal `comms_line_shown(speaker, text, mode)`
- `game/autoloads/feedback.gd` -- `slow_motion(scale, hold_s, ramp_s)`, plus resume hook on `PauseArbiter.resumed` when a Player is in the tree
- `game/ui/menus/pause_menu.gd` (+ tscn) -- recent comms list
- `game/ui/theme/defector_theme.tres` -- CommsBox font sizes
- `game/data/tuning.json` -- `ui.comms_box`, `comms.combat_line_*`, `feedback.resume_slowmo`, `ui.pause_menu.recent_comms`
- `game/data/levels/level_1..3.json` -- interruptions moved to the previous wave's `wave_clear`

## Tasks & Acceptance

**Execution:**
- [x] comms box -- bottom-centre layout from tuning, larger fonts, rise-in instead of slide-from-left, see-through when the player or an enemy projectile overlaps
- [x] feedback -- slow-motion ramp (pause-aware, real time), hit-stop restores the ramp value, `reset()` cancels; resume hook
- [x] pause menu -- "RECENT COMMS" block under the buttons
- [x] data -- tuning values; L1 Tarek warning on wave 2 `wave_clear`, Isolde on wave 3 `wave_clear`; L2/L3 Isolde on wave 2 `wave_clear`
- [x] tests -- update the comms box, channel, level data and feedback tests; add slow-mo, see-through and recent-comms tests
- [x] docs -- UX DESIGN/EXPERIENCE rows and decision logs

**Acceptance Criteria:**
- Given a level with a combat line, when it plays, then it is readable bottom centre for at least 7.5 s.
- Given a story pause mid-fight, when Continue is clicked, then the game resumes in slow motion that eases back to normal within about 1 s.

## Verification

**Commands:**
- the headless GUT run from AGENTS.md -- expected: 0 failures
