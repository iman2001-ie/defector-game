---
title: 'Epic 7 playtest B: the throne world hangs from the top; Level 3 ships sit lower'
type: 'bugfix'
created: '2026-10-13'
status: 'done'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The Level 3 throne-world placeholder rose from the bottom edge, behind the player, which read as the wrong side.

**Approach:** Draw the arc hanging from the top edge, and move Level 3's formation rows and the Flagship a little lower so they sit in front of it. Everything stays inside the enemy zone (y ≤ 432).

## Boundaries & Constraints

**Always:** The enemy zone, the HUD band and the part-hitbox rules hold (decision #54). Other levels are unchanged.

**Never:** The planet enters the player zone.

</frozen-after-approval>

## Code Map

- `game/scenes/level/level_background.gd` -- the arc hangs from the top
- `game/data/levels/level_3.json` -- `formation` rows override
- `game/systems/waves/wave_director.gd` / `level_validator.gd` -- `formation_rows()`, `row_shift_y`, validation
- `game/entities/enemies/needle/needle.gd` -- the anchor row moves by `row_shift_y`
- `game/entities/boss/flagship.tscn`, `game/data/tuning.json` (`boss.hull`, `boss.core.wasp_slots`, `feedback.boss_death_chain_offsets_px`)

## Tasks & Acceptance

**Execution:**
- [x] background, Level 3 rows, Flagship layout, tests, decision #61

**Acceptance Criteria:**
- Given Level 3, when it plays, then the planet arc hangs from the top and every ship sits in front of it, above the player zone.

## Verification

**Commands:**
- the headless GUT run from AGENTS.md -- expected: 0 failures (1862 passed, 1 pre-existing timing-pending)
