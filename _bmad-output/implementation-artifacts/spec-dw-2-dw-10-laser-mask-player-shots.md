---
title: 'DW-2/DW-10: laser bolt masks MASK_PLAYER_SHOTS (enemies, asteroids, convoy)'
type: 'bugfix'
created: '2026-10-07'
status: 'done'
baseline_revision: '5c3d2dd35bb20f8cedd315c7cfb7ea0c041a54d1'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
warnings: []
deferred:
  - summary: >-
      Projectile._on_area_entered calls apply_damage on any overlapped area, so once a convoy with apply_damage exists, player bolts (now masking CONVOY) would damage it instead of being blocked with no damage.
    evidence: |-
      game/core/projectile.gd:49-54 has no convoy check. FR7, GDD #23 and game-architecture.md:310 require player shots to be blocked by the convoy without damage. No convoy exists until Epic 6, so nothing breaks today. The Epic 6 convoy story must add the no-damage path, plus a test that a convoy-layer area stops a bolt without apply_damage.
    location: >-
      game/core/projectile.gd:49
    severity: medium
  - summary: >-
      Missile._on_impact always runs apply_splash, so a missile stopped by a convoy ship (missile mask already includes CONVOY) would still splash enemies and asteroids near the convoy; whether a blocked missile should detonate is not specified.
    evidence: |-
      game/entities/projectiles/missile.gd:27-29 calls apply_splash before super._on_impact for every hit. missile.tscn has masked CONVOY (84) since Story 1.5, so this predates DW-2/DW-10. epics.md:1409-1411 (Epic 6 convoy story) says missiles reaching a convoy ship are "stopped and free itself, the convoy takes no damage", but says nothing about splash on nearby enemies. Settle by a design ruling in the Epic 6 convoy story (detonate with splash vs. fizzle) and a test for it.
    location: >-
      game/entities/projectiles/missile.gd:27
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** `laser_bolt.tscn` has `collision_mask = 20` (enemies | asteroids), but the architecture layer table and `CollisionLayers.MASK_PLAYER_SHOTS` say player shots mask enemies, asteroids and convoy (84). Laser bolts would pass through convoy ships (FR33, decisions #23/#25), and the tests only check single bits or hard-code 20, so the gap is invisible. The Story 1.3 AC in `epics.md` repeats the wrong mask.

**Approach:** Per the user's decision on DW-2/DW-10, set the bolt's `.tscn` mask to 84 (the architecture convention: `.tscn` stores numbers, tests check them against `CollisionLayers`), make every laser and missile mask test assert exact equality with `CollisionLayers.MASK_PLAYER_SHOTS`, correct the Story 1.3 AC, and record the decision as row #35 in the GDD decision log.

## Boundaries & Constraints

**Always:** Keep the numeric value in the `.tscn` (architecture §layer table, `collision_layers.gd` header). Tests compare `collision_mask` with `CollisionLayers.MASK_PLAYER_SHOTS` by exact equality, never by single-bit `&` checks or literal numbers. Statically typed GDScript.

**Never:** Do not edit the deferred-work ledger or `sprint-status.yaml`. Do not implement convoy blocking (no-damage stop) in `projectile.gd`; that is Epic 6. Do not change `collision_layer`, `monitorable`, the missile scene, or `CollisionLayers` values. Do not renumber existing decision-log rows.

</intent-contract>

## Code Map

- `game/entities/projectiles/laser_bolt.tscn:38` -- root `LaserBolt` Area2D, `collision_mask = 20` → 84.
- `game/core/collision_layers.gd:16` -- `MASK_PLAYER_SHOTS = ENEMIES | ASTEROIDS | CONVOY` (84). Read-only.
- `game/entities/projectiles/missile.tscn:40` -- already `collision_mask = 84`. Read-only.
- `game/tests/unit/test_combat.gd:137-146` -- `test_laser_bolt_masks_enemies_and_asteroids` (Spawner-spawned bolt) uses single-bit checks; replace with exact equality and rename to reflect convoy.
- `game/tests/unit/test_laser_bolt_glow.gd:121` -- hard-codes `(1 << 2) | (1 << 4)`; switch to the constant.
- `game/tests/unit/test_projectile.gd:8,128` -- `MASK_ENEMIES_ASTEROIDS` const hard-codes 20 in `test_scene_root_layers`; it would fail after the change, so switch to the constant and drop the stale const.
- `game/tests/unit/test_missile.gd:44` -- already asserts exact `MASK_PLAYER_SHOTS` equality for the missile (covers the missile half of the intent). Read-only.
- `_bmad-output/planning-artifacts/epics.md:414` -- Story 1.3 AC "masks `enemies` and `asteroids`".
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- last row is #34; append #35.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_combat.gd` -- rename the test to `test_laser_bolt_masks_player_shots` and assert `bolt.collision_mask == CollisionLayers.MASK_PLAYER_SHOTS`; also add a sibling test spawning `&"missile"` through the Spawner asserting layer `PLAYER_SHOTS` and exact mask equality (fail first for the laser) -- red test first.
- `game/tests/unit/test_laser_bolt_glow.gd` -- line 121: `assert_eq(bolt.collision_mask, CollisionLayers.MASK_PLAYER_SHOTS, "enemies + asteroids + convoy")`.
- `game/tests/unit/test_projectile.gd` -- remove `MASK_ENEMIES_ASTEROIDS`; assert exact equality with `CollisionLayers.MASK_PLAYER_SHOTS`.
- `game/entities/projectiles/laser_bolt.tscn` -- `collision_mask = 84` -- the fix.
- `_bmad-output/planning-artifacts/epics.md` -- Story 1.3 AC: "masks `enemies`, `asteroids` and `convoy` (`MASK_PLAYER_SHOTS`)".
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- append row #35 (2026-10-07): laser mask = `MASK_PLAYER_SHOTS` (84) following the architecture; tests assert exact equality for laser and missile; Story 1.3 AC corrected; source "User (Epic 1 retro action item 4, DW-2/DW-10)"; status "Applied 2026-10-07 (DW-2, DW-10)".

**Acceptance Criteria:**
- Given a laser bolt spawned through `Spawner.spawn_projectile(&"laser_bolt", …)`, when its mask is read, then it equals `CollisionLayers.MASK_PLAYER_SHOTS` exactly (84, including `CONVOY`).
- Given a missile spawned through the Spawner, when its mask is read, then it equals `CollisionLayers.MASK_PLAYER_SHOTS` exactly.
- Given the full GUT suite runs headless, when it finishes, then all tests pass and no test asserts the laser mask with a literal number or single-bit check.
- Given `epics.md` Story 1.3, when read, then the bolt mask AC lists enemies, asteroids and convoy; and the decision log has row #35 for this decision.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 15 findings — high 0, medium 2, low 8, false 5, maybe-false 0
- findings:
  - `[medium]` `[defer]` (blind) Convoy friendly fire: projectile.gd applies damage to any area, and the mask now includes CONVOY — the damage path is pre-existing and owned by the Epic 6 convoy story (FR7, architecture :310). No convoy exists today. Recorded in `deferred`.
  - `[low]` `[patch]` (blind) Decision-log row #35 claimed "bolts are blocked by convoy ships", but only the mask changed — reworded: bolts detect convoy ships, and the no-damage block lands with the convoy in Epic 6.
  - `[low]` `[reject]` (blind) No behavioural test with a convoy-layer area — exact mask equality already guarantees engine detection. The meaningful assertion (no apply_damage) needs Epic 6 code, so this would add test machinery for a case nobody meets today. Covered by the deferred item.
  - `[low]` `[reject]` (blind) Layer assertions still use `1 << 1` (test_laser_bolt_glow.gd:120, test_projectile.gd:7) — pre-existing, the layer value is correct and asserted, and the intent only names the mask. Cosmetic.
  - `[low]` `[reject]` (blind) Older done-story specs (1-3, 1-4, dw-9) still say mask 20 — those are historical records of finished runs. epics.md and row #35 are the live contract.
  - `[false]` `[reject]` (blind) New missile test duplicates test_missile.gd:44 and uses literal damage 8 — the intent asks for an equality test for the missile, and this one covers the Spawner path, which is a different surface. Damage 8 matches the existing test_combat.gd:77/94 pattern and isn't asserted.
  - `[low]` `[reject]` (blind) Spec verification grep misses layer literals, and no runs are recorded — the fix is to edit this build's spec. Runs are recorded under Auto Run Result.
  - `[low]` `[reject]` (blind) DW-23 (schedule DW-10) left open — the ledger is orchestrator-owned and the intent forbids editing it. Noted under residual risks.
  - `[medium]` `[defer]` (edge) Bolt overlapping a convoy Area2D with apply_damage would damage it — same root cause as the first row. Deferred.
  - `[false]` `[reject]` (edge) Convoy as PhysicsBody2D would bypass area_entered — the architecture (:308) uses Area2D push-out with "no physics body", and the convoy takes apply_damage from the Maul as an area.
  - `[low]` `[patch]` (edge) Row #35 "blocked" claim — same root cause as the row #35 wording finding. Patched by the same rewording.
  - `[false]` `[reject]` (intent) Preferred option B (assign the mask in code) not chosen — the intent explicitly allows "kept in the .tscn but guarded", and game-architecture.md:289 makes `.tscn` numbers checked by tests the convention.
  - `[low]` `[patch]` (intent) Behavioural claim in row #35 not exercised by tests — same root cause as the row #35 wording finding. Patched by the same rewording.
  - `[false]` `[reject]` (intent) Duplicate missile coverage — same refutation as the blind duplicate-missile-test row.
  - `[false]` `[reject]` (intent) Glow test layer check is half-updated — the auditor itself notes this is within the intent's scope, and the layer value is correct and asserted. No defect.

### 2026-10-07 — Review pass
Follow-up pass on the `done` spec.
- verdicts: 18 findings — high 0, medium 2, low 9, false 6, maybe-false 1
- findings:
  - `[low]` `[reject]` (blind) DW-32 heading in `deferred-work.md` is cut off ("...with no") — real, but the ledger is orchestrator-owned and the intent forbids editing it. The full text is in this spec's `deferred` summary.
  - `[low]` `[reject]` (blind) DW-32 / `deferred` item doesn't cite the Epic 6 AC at `epics.md:1411` — the fix edits the ledger or this build's spec. The Epic 6 AC already states the no-damage block, so the Epic 6 implementer will read it.
  - `[maybe-false]` `[defer]` (blind) A missile blocked by a convoy would still splash nearby enemies (`missile.gd:27-29` always calls `apply_splash`) — pre-existing: `missile.tscn` has masked CONVOY (84) since Story 1.5, and this change doesn't touch the missile. Whether a blocked missile should detonate isn't specified by `epics.md:1409-1411`. Settled by an Epic 6 design ruling. Added to `deferred` (medium, unverified).
  - `[false]` `[reject]` (blind) Run records unfinished (status `in-review`, no Auto Run Result, empty Spec Change Log) — status is `in-review` only while this pass runs. Auto Run Result is written at finalize. The Spec Change Log only records bad_spec loopbacks, and there were none. Patches are logged in the triage log by design.
  - `[low]` `[reject]` carried (blind) DW-23 and the `sprint-status.yaml` retro item left open — both files are orchestrator-owned and the intent forbids editing them. Noted under residual risks.
  - `[false]` `[reject]` (blind) The spec's "do not edit the ledger" rule contradicts the diff's `deferred-work.md` hunks — those hunks were written by the orchestrator after the build commit (`df62995` doesn't contain them). The implementer didn't edit the ledger.
  - `[low]` `[reject]` (blind) `resolution-undo` token format undocumented and field order changed — orchestrator bookkeeping in an orchestrator-owned file that the intent forbids editing.
  - `[low]` `[reject]` carried (blind) Layer assertions still use `1 << 1` (`test_laser_bolt_glow.gd:120`, `test_projectile.gd:7`). Also `test_player_movement.gd:8` hard-codes a literal — that's the player's mask, outside the laser/missile scope of the intent.
  - `[low]` `[reject]` carried (blind) Verification grep can't catch literals in separate consts — the fix is to edit this build's spec. Manual check this pass: no laser/missile mask const remains in `game/tests`.
  - `[false]` `[reject]` carried (blind) New missile test overlaps `test_missile.gd:44`, uses damage 8, and no red run is recorded — Spawner path is a different surface. Damage 8 matches the existing pattern and isn't asserted. The red run was recorded in the first pass's Auto Run Result ("[20] expected to equal [84]").
  - `[false]` `[reject]` (blind) `epics.md:406` projectile contract says `apply_damage` on overlap with no convoy exception — this is the Story 1.3 contract, written before any convoy exists. The Epic 6 convoy story (`epics.md:1409-1411`) and FR7 (`epics.md:61`) already state the no-damage exception, so no implementer reads it as unconditional.
  - `[false]` `[reject]` (blind) Row #35 has thin references (no DW-32 link, test files not listed) — row #35 already says the no-damage block lands in Epic 6. Neighbouring rows (e.g. #33) don't list test files either, so there is no file-list convention it breaks.
  - `[medium]` `[defer]` carried (edge) Bolt overlapping a convoy Area2D with `apply_damage` would damage it — `projectile.gd:49-56` is unchanged. Already in `deferred` (DW-32), not deferred again.
  - `[low]` `[reject]` carried (intent) No behavioural test with a convoy-layer area — exact mask equality plus the existing layer-bit tests pin detection. The meaningful assertion needs Epic 6 code.
  - `[medium]` `[defer]` carried (intent) Motivating outcome moves from "passes through" to "damages the convoy" once a convoy exists — same root cause as the edge row. Already deferred (DW-32).
  - `[low]` `[reject]` carried (intent) Historical done-story specs (1-3, 1-4) still say mask 20 — records of finished runs. `epics.md` and row #35 are the live contract.
  - `[low]` `[reject]` carried (intent) Layer assertions still use literals (narrow R4 reading) — same as the blind layer-literal row.
  - `[false]` `[reject]` (intent) Ledger hunks would breach the Never clause if the implementer wrote them — they were written by the orchestrator (see the blind ledger row), so the boundary holds.
  - `[false]` `[reject]` carried (intent) Spawner-path missile test is wider coverage than needed — the auditor itself calls it not a contradiction.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass.
- `grep -rn "collision_mask" game/tests` -- expected: no laser-mask assertion uses a literal or `&` bit check.


## Auto Run Result

Status: done (follow-up review pass)

**Summary:** The laser bolt's collision mask is `CollisionLayers.MASK_PLAYER_SHOTS` (84: enemies, asteroids, convoy), following the architecture layer table and the user's DW-2/DW-10 decision. The number stays in the `.tscn`, and every laser and missile mask test asserts exact equality with the constant. The Story 1.3 AC is corrected, and the decision is GDD decision-log row #35. This follow-up pass re-reviewed the whole change since `5c3d2dd35bb20f8cedd315c7cfb7ea0c041a54d1` and changed no code.

**Files changed (whole story):**
- `game/entities/projectiles/laser_bolt.tscn` -- `collision_mask` 20 → 84.
- `game/tests/unit/test_combat.gd` -- laser test renamed `test_laser_bolt_masks_player_shots` (exact equality); new `test_missile_masks_player_shots` (Spawner path).
- `game/tests/unit/test_laser_bolt_glow.gd` -- mask assertion uses `CollisionLayers.MASK_PLAYER_SHOTS`.
- `game/tests/unit/test_projectile.gd` -- dropped the hard-coded `MASK_ENEMIES_ASTEROIDS`; asserts the constant.
- `_bmad-output/planning-artifacts/epics.md` -- Story 1.3 AC: masks enemies, asteroids and convoy.
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- row #35.
- `_bmad-output/implementation-artifacts/spec-dw-2-dw-10-laser-mask-player-shots.md` -- this spec (follow-up triage log, one new `deferred` item, this result).

**Review findings (this pass):** 18 findings, 0 patched. 2 deferred entries:
- Convoy no-damage path in `projectile.gd`: medium, carried, already deferred (DW-32), not deferred again.
- Blocked-missile splash: new, medium (unverified), pre-existing since Story 1.5. Added to `deferred`.

Rejected findings, with the reason recorded for each in the triage log:
- 9 low:
  - DW-32 heading truncation
  - DW-32 missing an epics citation
  - DW-23 / sprint-status left open
  - `resolution-undo` format
  - layer literals (×2)
  - verification grep
  - no behavioural convoy test
  - historical specs
- 6 false:
  - "run records unfinished"
  - ledger rule contradiction (×2)
  - missile test overlap (×2)
  - `epics.md:406` contract
  - row #35 references

All ledger and sprint-status findings were rejected because those files are orchestrator-owned.

**Follow-up review recommendation:** false. This was a follow-up pass and it patched nothing (high 0, medium 0, low 0), so the work has converged.

**Verification:**
- `--import`: exit 0.
- GUT full suite: 344/344 passing, 2015 asserts, exit 0.
- `grep -rn collision_mask game/tests`: every laser and missile mask assertion (`test_combat.gd:145,155`, `test_laser_bolt_glow.gd:121`, `test_missile.gd:44`, `test_projectile.gd:127`) uses exact equality with `CollisionLayers.MASK_PLAYER_SHOTS`. No literal or bit check remains for them.

**Residual risks:**
- Convoy no-damage blocking for bolts is not built (DW-32, Epic 6). No convoy exists today, so behaviour is unchanged.
- Whether a missile blocked by a convoy should still splash is undecided (new `deferred` item). It needs a design ruling in the Epic 6 convoy story.
- DW-23 and the Epic 1 retro action item 4 in `sprint-status.yaml` are satisfied by this work. Both are orchestrator-owned, so they were left untouched.
