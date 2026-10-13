---
title: 'Epic 7 playtest D: Tarek takes the hit for Vale, and Isolde offers a real surrender'
type: 'feature'
created: '2026-10-13'
status: 'done'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Tarek's fall happens too fast and nothing visibly hits him, so his damage comes "out of nowhere". Isolde's Level 1 surrender offer has no choice, so the finale's surrender mirror doesn't land.

**Approach:**
- **Tarek:** turn the fall into a readable beat of about 8–10 s, near the end of Level 2 wave 5 (progress 0.75):
  1. An alarm sounds and a red lock-on line runs from the top edge to Vale.
  2. Vale's controls lock, Vale can't be hurt, and enemies hold their fire.
  3. Tarek dashes between Vale and the threat as his line types: "Watch out! Get behind me, I've got you covered!", cut off.
  4. A Ram (a bigger, spikier Maul, too fast to dodge) dives from the top straight at Vale. The game slows down just before it hits Tarek.
  5. Impact: an explosion, the shield breaks, the line is cut to static, the music stops.
  6. Tarek's damaged ship spins away slowly, trailing fire, and leaves the screen. He is gravely injured, not dead; Ryn's report confirms it.
  7. Controls come back after the slow motion ends.
- **Surrender:** Isolde's Level 1 offer becomes a two-button choice, using the Final Choice view.
  - **SURRENDER:** Vale powers down, and Isolde reveals the trick and orders the execution. The level is lost with the reason "surrender" ("EXECUTED AT DAWN"), and Retry follows as for any loss.
  - **REFUSE:** Vale answers defiantly, and the reinforcements arrive as now.

## Boundaries & Constraints

**Always:**
- Only the Spawner creates the Ram.
- Only Feedback changes time_scale.
- Every timing and size lives in `tuning.json` (`story.tarek_fall`).
- The comms cut lands exactly at impact: the scene requests the cut-off line `cut_off_at / cutoff_chars_per_s` before its impact time.
- The `tarek_fall` flag off keeps Tarek flying, as now.
- The Final Choice in Level 3 is unchanged.

**Ask First:** none (operator agreed 2026-10-13: no shootable Ram; mouse locked; Tarek survives; a real choice with a lose ending in which Isolde orders the execution).

**Never:** Tarek dies. The Ram counts toward wave progress, can be shot, or damages Vale. A retry replays a scene that the level reload has already reset.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior |
|---|---|---|
| Fall plays | wave 5 at 0.75, flag on | the timeline above; Vale takes no damage during the lock |
| No Vale | the player is gone | Tarek falls at once, as before |
| Level ends mid-scene | cleared or failed | the lock and fire-hold are released |
| L1 surrender | SURRENDER clicked | the accept lines play, then level_failed(&"surrender") and the retry prompt "EXECUTED AT DAWN" |
| L1 refuse | REFUSE clicked | the refuse lines play, then the Mauls arrive |
| surrender_prompts off | flag off | no prompt, Mauls only (unchanged) |

</frozen-after-approval>

## Code Map

- `game/systems/story/tarek_fall_scene.gd` (new, a node in level.tscn) -- the scene director (own clock in game time)
- `game/entities/allies/ally_ship.gd` -- `intercept(point)`, shield hold until `take_hit()`, slower spinning fall
- `game/entities/story/ram.gd` + `.tscn` (new) -- visual-only diving Ram, A→B over `travel_s`
- `game/core/spawner.gd` / `entity_registry.gd` -- `spawn_ram`, `hold_enemy_fire`
- `game/entities/player/player.gd` -- `set_scripted_lock(bool)`: holds position, invulnerable, cursor warp on release
- `game/autoloads/feedback.gd` -- `slow_motion` (from batch C)
- `game/systems/comms/comms_channel.gd`, `dialogue_validator.gd` -- option ids `surrender|destroy|refuse`, option `fail` reason
- `game/ui/menus/retry_prompt.gd` -- `surrender` reason text
- `game/data/levels/level_2.json`, `game/data/dialogue/level_1.json`, `level_2.json`

## Tasks & Acceptance

**Execution:**
- [x] the scene director, Ram, ally, player lock, spawner fire-hold
- [x] data: wave 5 trigger at 0.75 with only `story_event`; new Tarek line; L1 choice sequences
- [x] comms: choice option `fail` → `Events.level_failed` after the response; retry prompt text
- [x] tests: the director timeline, ally intercept, Ram, lock, fire-hold, the L1 choice both ways, data shape
- [x] docs: GDD decision log, narrative notes

**Acceptance Criteria:**
- Given Level 2 with shipped flags, when wave 5 reaches 0.75, then the player sees the Ram strike Tarek, hears static at that moment, and keeps control afterwards.
- Given Level 1 wave 5, when SURRENDER is clicked, then Isolde orders the execution and the retry prompt shows.

## Verification

**Commands:**
- the headless GUT run from AGENTS.md -- expected: 0 failures
