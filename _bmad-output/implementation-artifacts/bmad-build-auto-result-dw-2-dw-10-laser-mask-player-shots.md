---
status: blocked
---

# BMad Build Auto Result

## Auto Run Result

Status: blocked
Blocking condition: dirty working tree. `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` has an uncommitted change from a previous session: row #32's status went from `Applied (provisional)` to `applied/confirmed`. This bundle (DW-2, DW-10: set the laser bolt mask to `CollisionLayers.MASK_PLAYER_SHOTS` = 84) has to append a new row to the same file. The step-01 version-control check requires a clean tree. Commit or discard the pending decision-log edit, then re-dispatch the bundle. No code, test, or planning files were changed.
