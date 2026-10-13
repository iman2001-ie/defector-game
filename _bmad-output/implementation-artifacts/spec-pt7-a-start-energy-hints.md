---
title: 'Epic 7 playtest A: Play from level 1, energy reset rules, level 1 always teaches controls'
type: 'bugfix'
created: '2026-10-13'
status: 'done'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** In the Epic 7 playtest, Play started level 3 because it continued at the highest unlocked level. Energy came back from the save on every menu start. The control hints showed only once per launch, so a later level 1 run didn't teach the controls.

**Approach:** Play always starts level 1, through the opening. Play and Level Select start with 0 energy. A level clear carries energy into the next level. Death followed by Retry gives 0. Pause → Restart Level goes back to the energy the attempt started with. Level 1 always shows its hints. Energy is no longer saved; the save keeps only the unlock.

## Boundaries & Constraints

**Always:** SceneRouter stays the only scene changer. Saving still happens only on a level clear. Old saves that still hold an `energy` key must load without a warning.

**Ask First:** none (operator agreed 2026-10-13).

**Never:** Don't touch tuning.json values. Don't add a save version bump that drops the player's unlocks.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior |
|---|---|---|
| Play | any save, any energy | level 1 via opening, energy 0 |
| Level Select n | energy 70 in memory | level n, energy 0 |
| Clear level n<3 | energy 35 | level n+1 with 35; save holds the unlock only |
| Death → Retry | started with 40, now 80 | same level, energy 0, is_retry |
| Pause → Restart | started with 40, now 80 | same level, energy 40, is_retry |
| Restart after a death-retry | energy 0 at attempt start | energy 0 |
| Level 1 run | hints shown earlier this session | move/fire and missile hints show again |
| Old save | has `energy=50` | loads, unlock kept, energy ignored |

</frozen-after-approval>

## Code Map

- `game/autoloads/scene_router.gd` -- start_level / restart_level / restore_saved_progress
- `game/autoloads/game_state.gd` -- energy, level_start_energy, shown_hints
- `game/autoloads/save_manager.gd` -- save format
- `game/scenes/title/title.gd`, `level_select.gd` -- Play / card handlers
- `game/ui/menus/retry_prompt.gd`, `pause_menu.gd` -- Retry vs Restart
- `game/scenes/level/level.gd`, `game/data/levels/level_1.json` -- `teach_controls` key clears shown hints

## Tasks & Acceptance

**Execution:**
- [x] `scene_router.gd` -- add `start_new(id)` (energy 0, then start_level); `_load_level` records `GameState.level_start_energy`; split `retry_level()` (0) from `restart_level()` (level_start_energy); restore no longer touches energy (sets 0)
- [x] `game_state.gd` -- add `level_start_energy`
- [x] `save_manager.gd` -- save/load the unlock only; tolerate a legacy energy key
- [x] `title.gd` / `level_select.gd` -- Play → `start_new("1")`, card → `start_new(str(n))`
- [x] `retry_prompt.gd` -- Retry → `retry_level()`; pause menu keeps `restart_level()`
- [x] `level.gd` + `level_1.json` -- `"teach_controls": true` clears `GameState.shown_hints` at level start
- [x] tests -- update the router/title/level-select/save/hint tests to the new rules
- [x] docs -- GDD + UX + epics wording and decision-log entries

**Acceptance Criteria:**
- Given any save, when Play is clicked, then the opening plays and level 1 starts with 0 energy.
- Given the full test suite, when run headless, then everything passes.

## Verification

**Commands:**
- the headless GUT run from AGENTS.md -- expected: 0 failures
