---
title: 'DW-101: the boss''s death ends the fight (safe ship, leftover enemies explode, enemy shots fizzle)'
type: 'bugfix'
created: '2026-10-13'
status: 'done'
baseline_revision: '4296406c4d8cfd4f536206b3eb40c0836f85ab1a'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
  - '{project-root}/_bmad-output/planning-artifacts/epics.md'
warnings: ['oversized']
deferred:
  - summary: >-
      The boss-death sweep spawns one Explosion (with sparks) per swept enemy and per fizzled enemy shot in a single frame, uncapped, which may cause a one-frame spike when a full DESPERATE barrage is in flight.
    evidence: |-
      Flagship._end_the_fight calls Feedback.impact for every enemy and EnemyBullet at DYING entry; in DESPERATE dozens of bullets can be in flight. Not measured: settle it by profiling dev_boss (F6, kill the core mid-barrage) and checking the frame time of the DYING frame against the 16.67 ms budget; if it spikes, cap the effects per sweep (fizzle the rest silently).
    location: >-
      game/entities/boss/flagship.gd (_end_the_fight)
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** DW-101 (operator playtest 2026-10-13). When the Flagship's core dies, the 2 s death chain (DYING) still lets leftover boss Wasps and enemy bullets already in flight kill the player, failing a level whose boss is beaten. Today (decision #39, F16) the ship is safe only from `level_cleared` and launched Wasps stay alive.

**Approach:** Operator decision 2026-10-13 "Boss death ends the fight". On entering DYING: (1) the Player turns safe exactly as after `level_cleared` (it reacts to `Events.boss_phase_changed(Flagship.Phase.DYING)`); (2) the Flagship sweeps every other live enemy out through the existing no-kill exit with its tier's impact (no `enemy_killed`, no drops) and fizzles every enemy bullet in flight with the SMALL blocked-shot effect, alongside the chain's first explosion, and sets `spawner.hold_enemy_fire` so no new enemy shot can spawn; it sweeps once more at the chain's end, just before `boss_defeated`. The wave and level then clear as today. Amend decision #39, F16, the Story 7.4/7.5 ACs and the architecture; add decision-log row #64; add tests.

## Boundaries & Constraints

**Always:** Explosions and fizzles go through `Feedback.impact` (which spawns via the Spawner). Swept enemies use `Enemy._resolve_without_kill(true)` semantics (counted ones still emit `resolved`, so the wave's count completes; boss Wasps have no listener). The Flagship and its `FlagshipPart`s are never swept (the chain is their feedback). Only `EnemyBullet` instances (incl. `NeedleBolt`) fizzle; player and ally shots, asteroids, orbs and the Ram are untouched. `is_safe()` keeps its meaning (not `is_invulnerable()`); a dead ship stays dead. Static typing, `Log` only, tuning from `Config`, no per-frame allocation (the sweep runs twice per boss death, not per frame).

**Never:** Do not change WaveDirector code, `boss_defeated` timing, the chain, the Final Choice flow, `tuning.json` or the deferred-work ledger. No new `Events` signal. Do not emit `enemy_killed` or roll loot for swept enemies.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Hit in DYING | core killed; enemy bullet / Wasp contact / `apply_damage(99)` on the Player | no heart lost, no `player_hit` / `player_died` / `level_failed`; `is_safe()` true | none |
| Leftovers | 5 launched Wasps + a counted enemy + 3 enemy bullets + 1 laser bolt alive | at DYING entry every enemy and enemy bullet is gone (queued free), one SMALL-or-tier explosion each, no `enemy_killed` for them, no orbs; the laser bolt stays; counted enemy emits `resolved` | none |
| New shots | after DYING, a shooter requests `enemy_bullet` | spawner refuses (null) | none |
| Late spawn | an enemy added during the chain | swept at the chain's end before `boss_defeated` | none |
| Other phases | `boss_phase_changed(CORE/FINAL_CHOICE/DESPERATE)` | Player not safe | none |
| Dead first | Player already dead, then DYING | stays dead, not safe | none |
| No spawner | Flagship without spawner reaches DYING | sweep still frees enemies/bullets; no hold set; no error | none |

</intent-contract>

## Code Map

- `game/entities/boss/flagship.gd` -- `_enter_phase` (L272-303): second `match` plays `Feedback.boss_death` on DYING; add the sweep there. `step` DYING branch (L171-176) emits `boss_defeated`: sweep again right before. Header doc L33-36 and L49-54 say "launched Wasps stay" -> update. `_launched`, `spawner` available.
- `game/core/enemy.gd` -- `_resolve_without_kill(play_feedback)` (L131): the no-kill exit (tier impact, `resolved`, `queue_free`, once). Add a public wrapper (e.g. `explode_without_kill()`) so the Flagship doesn't call a private method.
- `game/core/projectile.gd` -- `_spent` guard, `_on_impact` SMALL on convoy = "blocked-shot effect". Add `fizzle()`: once (respects `_spent`), `Feedback.impact(ImpactTier.SMALL, global_position)`, `queue_free()`, no damage.
- `game/entities/projectiles/enemy_bullet.gd` -- class to filter on (`NeedleBolt` extends it).
- `game/core/spawner.gd` -- `hold_enemy_fire` (refuses `enemy_bullet`, `needle_bolt`). Also written by `systems/story/tarek_fall_scene.gd` (Level 2 only).
- `game/core/groups.gd` -- `Groups.ENEMIES`, `Groups.PROJECTILES` to iterate.
- `game/entities/player/player.gd` -- `_safe`, `is_safe()` (L292), `_on_level_cleared` (L298), connections in `_ready` (L215), header "Level clear" doc (L55-62). Add a `boss_phase_changed` handler sharing a `_make_safe()` with `_on_level_cleared`.
- `game/systems/waves/wave_director.gd` -- read-only: boss wave resolves only on `boss_defeated` (L535); counted `resolved` -> progress (L523).
- `game/tests/unit/test_flagship.gd` -- fixture world + Spawner; `test_core_death_enters_dying_then_boss_defeated_after_the_chain` (L1193) asserts "one explosion at once" and "launched Wasps stay": must change. `_launched()`, `_bullets()`, `_live_explosions()` helpers.
- `game/tests/unit/test_player_level_clear.gd` -- Player safety tests to mirror (base `tests/fixtures/player_test_base.gd`).
- `game/tests/unit/test_flagship_level.gd` -- real `level.tscn` `dev_boss` run to the boss death and `level_cleared [0]`; Player is `debug_invincible` there.
- Docs: `_bmad-output/game-architecture.md` L817, L1198, L1593, L1671, L1929, L1943 (+ append `## As-built 2026-10-13 (DW-101)` at the end); `_bmad-output/planning-artifacts/epics.md` F16 row L44, Story 7.4 AC L1694, Story 7.5 last AC L1725-1729; `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` row 39 and new row 64.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_player_level_clear.gd` -- add a "Boss death (DW-101)" section first (red): DYING makes the ship safe; lethal hit ignored with no events; Wasp contact costs nothing; CORE/FINAL_CHOICE/DESPERATE don't; dead ship stays dead.
- `game/tests/unit/test_flagship.gd` -- update the death test (Wasps gone, SMALL explosions added, no extra `enemy_killed`, no orbs) and add tests: enemy bullets fizzle with SMALL effect while a laser bolt survives; a counted enemy is swept via no-kill exit (`resolved` once, no `enemy_killed`); `hold_enemy_fire` true after DYING; an enemy added during the chain is swept before `boss_defeated`; no-spawner DYING sweeps without error. Update the file header.
- `game/tests/unit/test_flagship_level.gd` -- in the real run, before killing the core spawn one enemy bullet and one boss Wasp via the level Spawner; after the core dies turn `debug_invincible` off: `is_safe()`, a 99 hit costs nothing, no `level_failed`; at chain end no live enemy or enemy bullet remains; `level_cleared` exactly `[0]`.
- `game/core/enemy.gd`, `game/core/projectile.gd`, `game/entities/boss/flagship.gd`, `game/entities/player/player.gd` -- implement (green), with doc comments in the files' style.
- Docs as in the Code Map: amend #39 (safe from the boss's death too) and F16 (live Wasps stay until the boss's death), Story 7.4/7.5 ACs, architecture notes + new As-built section, decision-log row 64 (Source: operator, DW-101; Status: Applied 2026-10-13).

**Acceptance Criteria:**
- Given the real `dev_boss` level in DESPERATE with a live boss Wasp and an enemy bullet, when the core dies, then the Player is safe at once, a hit during DYING costs nothing, the Wasp and bullet are gone by the end of the chain, and `level_cleared` fires exactly once.
- Given the full GUT suite, when run headless, then every test passes with no new `[ERROR]` lines.

## Design Notes

"Alongside the chain" (all at DYING entry) is chosen over a stagger: it is deterministic and leaves nothing alive to fire or collide. The tier impacts are cheap (SMALL: no shake, no hit-stop; longer hit-stops never stack in `Feedback.hit_stop`). Counted enemies (none in shipped boss waves) still resolve so a boss wave with spawns can't soft-lock; progress triggers are `has_fired`-guarded so nothing re-fires.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0 (rebuilds the class cache)
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass

## Spec Change Log

## Review Triage Log

### 2026-10-13 — Review pass
- verdicts: 20 findings — high 0, medium 2, low 7, false 9, maybe-false 2
- findings:
  - `[medium]` `[patch]` (blind-hunter 1) Sweep sfx after the boss-death impact steal the oldest of Audio's 12 combat voices and cut off `explosion_boss_death` — confirmed in `audio.gd` (POOL_SIZE 12, oldest stolen); fixed: `_end_the_fight()` now runs before `Feedback.boss_death` so the boss sound is the newest voice; docs reworded.
  - `[maybe-false]` `[defer]` (blind-hunter 2) Uncapped one-frame burst of explosions at the sweep — not measured; deferred (medium, unverified) with a profiling check in frontmatter `deferred`.
  - `[low]` `[patch]` (blind-hunter 3) The As-built "Known edge" omits that the Player also stays safe after F6 — fixed: note now says both the fire hold and `_safe` persist after F6.
  - `[false]` `[reject]` (blind-hunter 4) F3 doc line stale — F3 frees the Flagship without entering DYING, so launched Wasps still stay after F3; the line remains accurate.
  - `[false]` `[reject]` (blind-hunter 5) GDD body not updated — `gdd.md` L203/L286 and the GDD-folder `epics.md` L141 only say the death plays the Boss-death tier, which is still true; the intent asked for a decision-log row, which is #64.
  - `[low]` `[patch]` (blind-hunter 6) Decision-log row 39 note glued without a full stop; Source/Status not updated — fixed: full stop added, Source and Status record the 2026-10-13 DW-101 amendment.
  - `[low]` `[patch]` (blind-hunter 7) Death test's `shots` could be empty and included any Projectile — fixed: filtered to `EnemyBullet` and `assert_gt(shots.size(), 0)`.
  - `[false]` `[reject]` (blind-hunter 8) Level test can't fail on the AC — with `debug_invincible` off, `apply_damage(99)` would kill an unsafe ship, so the hearts assertion fails without the fix; the collision path is covered by `_shoot` in `test_player_level_clear.gd`.
  - `[low]` `[reject]` (blind-hunter 9) No tests that ally shots, missiles, asteroids and orbs are untouched — the filter is a type cast to `EnemyBullet` (laser bolt tested); adding tests for each type is more than a direct correction for an unlikely regression.
  - `[false]` `[reject]` (blind-hunter 10) Swept counted enemy could overshoot `total_counted` or clear early — each counted enemy resolves once through the normal `_on_enemy_resolved` path; the wave can't clear before the boss resolves on `boss_defeated`; triggers are `has_fired`-guarded.
  - `[low]` `[patch]` (blind-hunter 11, grouped with verification-gap 1) The new INFO log line is never checked — fixed: the death test asserts exactly one line with the swept and fizzled counts (the end sweep logs nothing). The "which sweep" wording sub-point is cosmetic and rejected.
  - `[false]` `[reject]` (blind-hunter 12) Spec staleness (line numbers, status, Ram wording) — the fix would edit this build's spec; rejected per triage rules.
  - `[medium]` `[patch]` (edge-case 1) Sweep sfx cut off the boss-death sound — same root cause as blind-hunter 1; fixed by the same reorder.
  - `[maybe-false]` `[defer]` (edge-case 2) Many particle explosions on one frame — same root cause as blind-hunter 2; deferred.
  - `[low]` `[reject]` (edge-case 3) F6 after a boss death leaves enemy fire held — debug-only, documented in the As-built Known edge; a fix adds a reset branch touching the Spawner's hold from a new owner for a case players never meet.
  - `[false]` `[reject]` (edge-case 4) `get_tree()` outside the tree logs an engine error — `_end_the_fight` runs only from `_enter_phase` (driven by a part's hp change while in the tree) and `step` (physics process); no reachable out-of-tree call.
  - `[low]` `[patch]` (verification-gap 1) The INFO log line is untested — grouped with blind-hunter 11; fixed by the same assertion.
  - `[false]` `[reject]` (intent-alignment 1) Reading B2 (a counted enemy's resolve moves progress) diverges from "no progress side effects" — the intent's qualifier is "that could re-trigger beats"; triggers are `has_fired`-guarded, and shipped boss waves have no counted enemies.
  - `[false]` `[reject]` (intent-alignment 2) No end-to-end leftover-collides-with-ship test — leftovers are removed at DYING entry and new enemy shots are refused, so that collision can't happen; safety is proven on the real level by a lethal `apply_damage` with invincibility off and by `_shoot` in the Player tests.
  - `[false]` `[reject]` (intent-alignment 3) Reading C1 leaves new enemies unrefused — "no new enemy shots or launches start" holds: shots are refused by the hold, launches only run in CORE, and anything added during the chain is swept before `boss_defeated`.

## Auto Run Result

Status: done

**Summary:** The Flagship's death now ends the fight (DW-101, GDD decision #64). When the core dies and the Flagship enters DYING, the Player becomes safe exactly as after a level clear. Every other live enemy explodes through the existing no-kill exit (tier impact, no `enemy_killed`, no drops; a counted one still resolves). Every enemy bullet in flight fizzles with the SMALL blocked-shot effect, and the Spawner holds enemy fire. A second sweep runs just before `boss_defeated`. The wave and level clear as before.

**Files changed:**
- `game/entities/boss/flagship.gd` — `_end_the_fight()` sweep on DYING entry (before `Feedback.boss_death`, so the boss sound keeps its voice) and before `boss_defeated`; header docs.
- `game/entities/player/player.gd` — `boss_phase_changed(DYING)` makes the ship safe via a shared `_make_safe()`.
- `game/core/enemy.gd` — public `explode_without_kill()` wrapper for the no-kill exit.
- `game/core/projectile.gd` — `fizzle()`: SMALL blocked-shot effect, free, no damage, once.
- `game/tests/unit/test_player_level_clear.gd` — boss-death safety tests.
- `game/tests/unit/test_flagship.gd` — updated death test (sweep, fizzle, log line) plus 5 new DW-101 tests.
- `game/tests/unit/test_flagship_level.gd` — real `dev_boss` run: leftovers gone, ship safe with invincibility off, `level_cleared` once.
- `_bmad-output/game-architecture.md` — notes amended plus a new "As-built 2026-10-13 (DW-101)" section.
- `_bmad-output/planning-artifacts/epics.md` — F16, Story 7.4 AC, Story 7.5 AC.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` — row 39 amended, row 64 added.

**Review findings:** 20 findings. Patched: 5 entries (1 medium: the sweep sounds cutting off the boss-death sound; 4 low: the F6 known-edge note, decision-log row 39 formatting and columns, the death test's shots guard, and the new log-line assertion). Deferred: 1 (uncapped one-frame explosion burst, medium unverified). Rejected: 9 false and 2 low (blind-hunter 9, edge-case 3), each with its reason in the triage log above.

**Follow-up review recommended:** false. Patched by verdict: high 0, medium 1, low 4.

**Verification:** `--headless --path game --import` exited 0. The full GUT suite passed 1980/1980 both before and after the review patches. Every I/O-matrix row has a covering test that ran and passed.

**Residual risks:** the look and feel of the sweep and the safe window need the operator's playtest. The explosion burst cost when a full barrage is swept is unmeasured (deferred). Debug only: after a boss death, F6 restarts the fight with enemy fire still held and the ship still safe until the scene reloads.
