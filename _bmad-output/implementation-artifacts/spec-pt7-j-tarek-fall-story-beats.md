---
title: "Epic 7 playtest J: Tarek's fall as paused story beats, a burning-crash sound, and an ally ship the player's size"
type: 'feature'
created: '2026-10-14'
status: 'done'
baseline_commit: '9956f9e'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:**
- Tarek's fall plays as a live, cut-off comms line, so its emotional beats fly by.
- His downed ship has no burning or crash sound.
- The ally fighter is visibly smaller than the player's ship.

**Approach:** the operator agreed this on 2026-10-14.
1. Lock-on: the alarm sounds, the red line runs to Vale, Vale's controls lock and enemies hold their fire (as now).
2. **Paused story beat** (press to continue). TAREK, with his portrait: "Watch out, General! Get behind me, I've got you covered!"
3. Resume. Tarek dashes in front of Vale. The Ram strikes him in slow motion, there is an explosion, and the music stops. His burning ship spins away and down with a new **burning-fall** sound, a CC0 composite of a fire crackle, a falling thruster roar and a dull distant crash.
4. **Paused story beat.**
   - VALE: "Admiral? Admiral Tarek?! ADMIRAL!"
   - Then a line with **no speaker name and no portrait**: text "...", over the comms static. It is the open channel's noise, and his fate is unknown.
5. Resume. Control returns, and comms stay silent until the wave clears. Ryn's report is unchanged.

**Also:** the ally ship (Tarek, and Ryn, who flies his ship) is drawn at the same size as the player's ship.

## Boundaries & Constraints

**Always:**
- Story pauses go through the existing comms story mode and PauseArbiter. Nothing else pauses.
- Only Feedback changes time_scale.
- Every timing and size lives in data.
- Dialogue lives in `data/dialogue/level_2.json`.
- The sound is reproducible from the import tool and credited.

**Ask First:** none. The operator answered: Tarek warns, Vale calls out, the "..." line has no name, and the GDD's "only two mid-fight pauses" rule is changed. Record that in the decision log, and update the GDD text.

**Never:**
- Tarek dies.
- The Ram damages Vale.
- A retry replays a half-finished scene.
- Change the Level 1 surrender or the Level 3 Final Choice.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior |
|---|---|---|
| The fall plays | L2 wave 5 at 0.75 | the beats above, in order; nothing hurts Vale |
| No Vale | the player is gone | Tarek falls at once; the beats still play |
| Level ends mid-scene | cleared or failed | the lock and the fire hold are released; no stray pause |
| "..." line | the speaker has no name or portrait | the name label is hidden, there is no portrait frame, and the static plays |
| tarek_fall flag off | as now | Tarek keeps flying |

</frozen-after-approval>

## Code Map

- `game/systems/story/tarek_fall_scene.gd`: the scene timeline (currently a cut-off interruption line)
- `game/systems/comms/` (comms_channel, comms_panel): the story-mode sequences, the speakers, the name and portrait handling
- `game/data/dialogue/level_2.json`: `l2_w5_tarek_cutoff`, which becomes two story sequences
- `game/data/tuning.json`: `comms.speakers` (a nameless speaker), `story.tarek_fall`, `allies.ship_px` or the ally scale, and the player's ship size
- `game/entities/allies/ally_ship.gd`: the falling state (where the burn sound plays)
- `tools/import_cc0_audio.py`: the layered `tarek_burn` sfx

## Tasks & Acceptance

**Execution:**
- [x] the scene director with the two paused beats; the dialogue data; the nameless speaker
- [x] the burn sfx (layered) plus its credits
- [x] the ally ship size matched to the player's
- [x] tests for the matrix; the GDD and decision log

**Acceptance Criteria:**
- Given the full suite on the staged data, when GUT runs, then everything passes.

## Spec Change Log

- 2026-10-14, merge and review:
  - `_release` also clears Tarek's `hold_fire`.
  - The fire layer is looked up by its download name (`fire-1_0.ogg`).
  - The UX EXPERIENCE.md rows, the GDD lines 30 and 593, and decision rows #22, #43, #63 and #73 are amended.
  - Deferred: DW-109 (silence_after with a wave already cleared), DW-110 (burn bleeding into the next scene), DW-111 (CommsBox empty name).

## Suggested Review Order

- The director timeline: LOCK → WARNING (paused) → RUNNING → AFTERMATH → CALLOUT (paused) → SETTLE.
  [`tarek_fall_scene.gd:1`](../../game/systems/story/tarek_fall_scene.gd#L1)
- Line sfx and `silence_after` in the channel.
  [`comms_channel.gd:413`](../../game/systems/comms/comms_channel.gd#L413)
- The two story sequences and the nameless static line.
  [`level_2.json:1`](../../game/data/dialogue/level_2.json#L1)
- The ally at the player's size.
  [`ally_ship.gd:1`](../../game/entities/allies/ally_ship.gd#L1)
