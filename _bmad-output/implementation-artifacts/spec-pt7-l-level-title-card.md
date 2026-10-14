---
title: 'Epic 7 playtest L: a "LEVEL N" title card at the start of each level'
type: 'feature'
created: '2026-10-14'
status: 'done'
baseline_commit: '5ead4fa'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** a new level starts without saying which level it is. The player goes straight into the briefing or the waves.

**Approach:**
- Each campaign level opens with a big centred title card: "LEVEL 1" with the level's name under it (for example "CARGO AMBUSH"), in the HUD's theme.
- The card fades in, holds, then fades out, like the other hints.
- The level's briefing and waves start only after the card has gone.
- On a retry, the card is shorter: it uses `retry_hold_s` (set to 0 to skip it).

## Boundaries & Constraints

**Always:**
- The timings and sizes live in `tuning.json` (`ui.level_intro`).
- Text and colours come from the shared Theme.
- The HUD reads Events only. The card is driven by the level start, through an Event or the level's own start sequence, whichever matches the architecture.
- Pausing still goes only through PauseArbiter.

**Ask First:** none.

**Never:**
- Show the card on dev levels (id 0).
- Delay the music trigger relative to wave 1.
- Block input forever when the config has failed.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior |
|---|---|---|
| Campaign level start | Level 1, 2 or 3 | the card, then the briefing (or wave 1) |
| Retry | `GameState.is_retry` | the card for `retry_hold_s`, or none when 0 |
| Dev level | id 0 | no card; behaviour unchanged |
| Pause during the card | Esc | the card freezes with the game (or skips; follow the hint behaviour) |
| Failed config | `load_error` | no card |

</frozen-after-approval>

## Code Map

- `game/scenes/level/level.gd` + `.tscn`: the level start sequence (where the briefing and WaveDirector begin)
- `game/ui/hud*` or the existing hint pill and LevelClearBanner: reuse their style and fade pattern
- `game/data/levels/level_*.json`: the level `name`
- `game/data/tuning.json`: `ui.level_intro`

## Tasks & Acceptance

**Execution:**
- [x] the card node and theme type; the level-start gating
- [x] tuning and data-shape tests; unit tests for the matrix
- [x] docs: decision log, UX EXPERIENCE note, architecture as-built

**Acceptance Criteria:**
- Given the full suite on the staged data, when GUT runs, then everything passes.

## Spec Change Log

- 2026-10-14, implementation:
  - The card is the HUD's `LevelIntroCard`, driven by the new `Events.level_intro_started`.
  - level.gd waits the card's whole time on a pausable game-time timer before starting the WaveDirector.
  - The level bench and the test seam `intro_card = false` skip the card.
  - The Feedback pre-warm now runs before the card.
