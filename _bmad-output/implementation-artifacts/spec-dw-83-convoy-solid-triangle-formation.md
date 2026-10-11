---
title: 'DW-83: nose-up convoy formation with one solid triangular hull for the player'
type: 'feature'
created: '2026-10-11'
status: 'done'
baseline_revision: 'fb8b6edb091964d92fe70728e4db5c8b9dfa1404'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
  - '{project-root}/_bmad-output/planning-artifacts/epics.md'
warnings: ['oversized']
deferred:
  - summary: >-
      The Player's 64 px hull circle can visibly overlap drawn cargo hulls (up to 16 px at the sides, about 8 px at the lead's top, more at the nose tips) because solidity uses the 80% hitboxes, not the drawn extents.
    evidence: |-
      hull_polygon() is built from ConvoyShip.hull_rect() (128x64 hitboxes) while hulls are drawn 160x80; Story 6.1 already resolved against the hitbox rects, so this predates DW-83. Settle by operator playtest of dev_convoy: if the overlap reads badly, build the polygon from the drawn extents (hull_size) instead.
    location: >-
      game/entities/allies/convoy.gd _place_ships
    severity: low
---

<intent-contract>

## Intent

**Problem:** The convoy is a sideways triangle (lead 40 px ahead, flankers stacked above and below) and the Player is pushed out of each ship's hitbox rect separately. The 64 px hull circle fits through the 72 px pocket between hitboxes, so the ship slips between cargo ships (DW-83, confirmed in operator playtest).

**Approach:** Apply the operator decision of 2026-10-10. Lay the three ships out like the UX mock: nose-up, side by side, the middle (lead) ship raised, so the group is a shallow symmetric triangle inside y 760-920. The group slides left/right as one, ping-pong (#45), no mirroring. Replace the per-rect push-out with ONE solid convex polygon covering the formation, gaps included (the convex outline of the three hitboxes). The Player collides with that polygon and slides along it with no damage. Per-ship Area2D hitboxes stay as they are for enemy shots, Mauls and player/ally shot blocking.

## Boundaries & Constraints

**Always:**
- Layout numbers come from `tuning.json` `convoy`: replace `lead_offset_px` with `gap_px: 8` (horizontal gap between drawn hulls) and `lead_raise_px: 20` (how much higher the lead sits). These are the mock's values (`key-hud.html`: cargo at x 712/880/1048, tops 800/780/800, 160x80 each). Clamp both to >= 0 when read.
- Ship order stays `[Lead, FlankLeft, FlankRight]`. Rename the nodes and the `FLANK_TOP`/`FLANK_BOTTOM` constants to `FlankLeft`/`FlankRight` and `FLANK_LEFT`/`FLANK_RIGHT` everywhere, tests included.
- Geometry for left edge `left`, width w, height h, gap g, raise r: span = 3w + 2g. Flank-left x = left + w/2, lead x = left + 1.5w + g, flank-right x = left + 2.5w + 2g. The group (height h + r) is centred vertically in the band: top = (band_lo + band_hi)/2 - (h + r)/2, lead y = top + h/2, flank y = top + r + h/2. Defaults: span 496; at left 0 the centres are (80, 850), (248, 830), (416, 850).
- Path: starts at left_x 0 heading right. `step_span` (unchanged) ping-pongs in [0, 1920 - span]. `direction()` is still reported but does not change the layout.
- Solid hull: `Convoy.hull_polygon() -> PackedVector2Array`, 6 global points, cached and refreshed in place each `_place_ships` (no allocation per tick): flank-left hitbox bottom-left and top-left, lead hitbox top-left and top-right, flank-right hitbox top-right and bottom-right. Defaults at left 0: (16,882), (16,818), (184,798), (312,798), (480,818), (480,882). Remove `hull_rects()`.
- Player: `resolve_hull(from, to, radius, polygon: PackedVector2Array, bounds_min, bounds_max)` and `overlaps_hull(p, radius, polygon)` work against one convex polygon. Keep the existing behaviour contract: sub-steps of at most radius/2; push-out after each step (outside: to `radius` from the closest boundary point; centre inside: out through the nearest edge along its outward normal); then `confine`; a remaining overlap (screen-edge squeeze) moves along y only, to the nearest free y above or below; `HULL_EPS_PX` tolerance; first lock tick only pushes out; cursor warp, `player_moved` and no-heart rules unchanged. Fewer than 3 points or radius <= 0 means plain confine. The result must not depend on the polygon's winding.
- ConvoyShip: drop `facing`. The code-drawn pentagon (art otherwise unchanged, DW-86) points nose-up: still ship_width_px x ship_height_px, flat bottom, the top tapered to a point at (0, -h/2) over the top quarter of the height (taper h/4).
- Write the failing GUT tests first. Statically typed GDScript. Logging only through `Log`.

**Never:** No change to ConvoyShip layers/masks or hitbox size, projectile/Maul/Lancer code, damage numbers, HP rules, the HullArea node, or the hurtbox. No physics-body or new collision layer for the polygon (it stays analytic, like the old rects). No new ship art. Don't edit the deferred-work ledger. Don't touch DESIGN.md/EXPERIENCE.md or the mock.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Slow descent through a gap | convoy at left 0; cursor moves down 4 px/tick at x 164 (flank-left/lead gap) or x 332 from y 700 to 1000 | ship rests on the polygon (never overlaps it) and stays above it | No error expected |
| Rise through a gap from below | cursor moves up at x 164 / 248 / 332 from y 1000 to 700 | ship stops below the polygon (y 914 at those x) | No error expected |
| Side approach into the pocket under the lead | convoy stepped 5 s (left_x 200, polygon x 216-680); cursor moves right along y 870 from x 100 to x 900, 4 px/tick and as one flick; also leftward from x 900 to 100 | stops at (184, 870) (or (712, 870) from the right); never inside or past the polygon | No error expected |
| Flick across | one tick from (248, 700) to (248, 1000) | stops above the lead at y 766 | No error expected |
| Slide along the shoulder | diagonal move toward a point inside the sloped edge (16,818)-(184,798) | ends at distance 32 (within 0.01) from that edge, x moved toward the target | No error expected |
| Squeeze at the screen edge | convoy at left 0, ship resolved at (0, 840) | x stays 0, ship moves up along y to the nearest clear y (about 790.29, 32 px from the vertex (16, 818)), not overlapping | No error expected |
| Moving hull | ship at right of the polygon, convoy steps 1 s right | ship pushed to 32 px right of the polygon; cursor warped once | No error expected |
| Degenerate polygon | `PackedVector2Array()` | plain confine | No error expected |

</intent-contract>

## Code Map

- `game/entities/allies/convoy.gd` -- layout (`ship_centre`, `ship_centres`, `group_span`, `_place_ships`, `span`), `hull_rects` cache to replace with `_polygon`; class doc describes layout and must be rewritten. `ship_centre` drops the `dir` param and takes `(index, left, w, h, gap, raise, band_lo, band_hi)`; `group_span(w, gap)` = 3w + 2g.
- `game/entities/allies/convoy.tscn` -- node names `FlankTop`/`FlankBottom` -> `FlankLeft`/`FlankRight`.
- `game/entities/allies/convoy_ship.gd` -- `facing` setter, `_build_outline` (nose toward facing) -> nose-up, drop `facing`; class doc. `hull_rect()` stays (used to build the polygon).
- `game/entities/player/player.gd:85-99` (class doc), `:494-628` -- `set_convoy`, `step_lock` (passes `_convoy.hull_rects()` at :524), `resolve_hull`, `overlaps_hull`, `_rect_overlap`, `_push_out`, `_push_out_y` to rework for a polygon.
- `game/data/tuning.json:190-199` -- `convoy` section.
- `game/tests/unit/test_convoy.gd` -- tuning, layout, mirroring, facing, hull_rects and outline tests to rewrite (remove mirroring/facing assertions; add raised-lead, gap, symmetry, centred-in-band, polygon cache tests).
- `game/tests/unit/test_player_convoy.gd` -- pure resolve_hull tests built on rects; rewrite on polygons and add the DW-83 tests from the matrix.
- `game/tests/unit/test_ally_bolt.gd:98`, `test_level.gd:1244,1329`, `test_maul.gd:202-209`, `test_missile.gd:230`, `test_needle_bolt.gd:205`, `test_projectile.gd:221` -- use `FLANK_TOP`/`FLANK_BOTTOM`; `test_level.gd:1244` asserts "lead ahead" (replace with lead raised / between flankers); `test_maul.gd` nearest-ship expectations move with the new centres (from (1500, 840) the nearest is now FlankRight; from (100, 900) FlankLeft). Also run `test_lancer.gd`, `test_data_files.gd`, `test_config.gd` (may pin convoy keys).
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md:191,209` -- convoy contact row and formation rule.
- `_bmad-output/planning-artifacts/epics.md:107` (FR32), `:1449-1450,1461-1465` (Story 6.1 AC).
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- append row 51 after row 50.
- `_bmad-output/game-architecture.md` -- the "As-built 2026-10-10 (Story 6.1)" Convoy/ConvoyShip/Player bullets; append a new `## As-built 2026-10-11 (DW-83)` section at the end of the file superseding them.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_convoy.gd`, `game/tests/unit/test_player_convoy.gd` -- write the new/updated failing tests first (matrix rows, layout, polygon, nose-up outline, tuning keys).
- `game/data/tuning.json` -- replace `lead_offset_px` with `gap_px: 8`, `lead_raise_px: 20`.
- `game/entities/allies/convoy.tscn`, `convoy.gd` -- rename flank nodes/constants, new layout, `hull_polygon()` cache, class doc.
- `game/entities/allies/convoy_ship.gd` -- nose-up outline, drop `facing`, class doc.
- `game/entities/player/player.gd` -- polygon `resolve_hull`/`overlaps_hull`/push-outs; `step_lock` reads `_convoy.hull_polygon()`; class docs.
- the other tests in the Code Map -- rename constants and update position-dependent expectations.
- `gdd.md` -- formation rule: three cargo ships nose-up, side by side, the middle (lead) ship raised so the group forms a shallow symmetric triangle, within y 760-920; slides left/right as one group, ping-pong, no mirroring; drop "lead about 40 px ahead". Contact: the formation is one solid shape including the gaps, so the ship can't pass between cargo ships; it slides along the formation's outline (decisions #25, #51).
- `epics.md` -- FR32 and Story 6.1 AC to match (remove "triangle mirrored so the lead still leads"; Player AC sweeps against the formation's one solid outline, not each ship).
- `decision-log.md` -- row 51, dated 2026-10-10, source "User (operator playtest, DW-83)", status "Applied 2026-10-11 (DW-83)": the decision, the record-only choices (the solid shape is the convex outline of the three hitboxes, a flat-topped shallow triangle, because a true triangle covering two side-by-side hulls would reach far past them; gap 8 px and raise 20 px from the mock; group centred in the band), clarifies #25, revises #24/#45 geometry, lists what was amended.
- `game-architecture.md` -- new As-built DW-83 section.

**Acceptance Criteria:**
- Given a level with `"convoy": true`, when it starts, then the three ships are nose-up, side by side with 8 px gaps, the lead in the middle 20 px higher, all inside y 760-920, fully on-screen at the left, clear of (960, 900), heading right.
- Given the convoy reaches either screen edge, when it turns, then the layout stays the same (no mirroring) and every hull stays on-screen.
- Given the player moves at any speed toward any gap between cargo ships from above, below or the side, when the move resolves, then the ship never overlaps the formation polygon and never ends on the far side of it, takes no damage, and slides along the outline.
- Given an enemy shot, Maul or player/ally shot meets a single cargo ship, when it overlaps, then the per-ship behaviour is unchanged (existing tests stay green).

## Spec Change Log

## Review Triage Log

### 2026-10-11 — Review pass
- verdicts: 25 findings — high 0, medium 2, low 19, false 4, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) No data validation that gap_px/lead_raise_px keep the group inside the band and screen — only mis-tuned data reaches it (current 8/20 fit); a fix adds guards and validation branches.
  - `[low]` `[reject]` (blind) The polygon's in-place refresh is no longer identity-tested; COW copy if a caller holds it — the Player only passes it into resolve_hull for the call's duration, so no copy happens in play; allocation is not testable in GDScript without new tooling.
  - `[medium]` `[patch]` (blind) Squeeze only tested at the left edge / up branch — grouped with the verification-gap finding; added the downward (0, 890) → y ≈ 909.71 test and a right-edge squeeze test.
  - `[low]` `[patch]` (blind) No test of a ship resting on a sloped shoulder while the convoy moves — added a real-convoy test that rests on the left shoulder and steps the convoy 60 ticks with no overlap.
  - `[false]` `[reject]` (blind) Raise 0 makes collinear vertices that break collision — `_inside` ignores zero cross products and collinear edges share one outward normal in `_exit_nearest_edge`, so the result is unchanged.
  - `[low]` `[patch]` (blind) Decision #51 doesn't say DESIGN.md's mock note is now partly stale — grouped with the mock-y finding; row 51 now says the arrangement is adopted while the mock's band label stays stale.
  - `[low]` `[patch]` (blind) Superseded Story 6.1 architecture bullets have no forward marker — added a sentence to the Story 6.1 status paragraph pointing at As-built DW-83.
  - `[low]` `[patch]` (blind) Group sits 10 px lower than the mock and the decision doesn't say so — row 51 now notes it (the mock's 780-880 band predates #24).
  - `[low]` `[patch]` (blind) Unrelated test_level timing change bundled and loosens slot-y — not unrelated: the new layout shifted the suite's frame alignment so a catch-up burst let the Mauls fly 3 ticks before the poll (baseline: 2); the tolerance is now the physical bound since the recorded spawn tick, so a slot-y error beyond the flown distance still fails. Documented in the As-built DW-83 Tests bullet.
  - `[low]` `[reject]` (blind) No on-screen debug overlay of the polygon — new feature surface not asked for by the intent.
  - `[low]` `[patch]` (blind) test_tuning pins the exact convoy key set — replaced with an assertion that `lead_offset_px` is absent.
  - `[low]` `[reject]` (blind) Spec bookkeeping unfinished / matrix row lists x 248 — fixing means editing this build's spec; bookkeeping is finalised by this step.
  - `[low]` `[patch]` (blind) Badly wrapped step_lock doc comment — rewrapped (comment only).
  - `[low]` `[reject]` (edge) lead_raise_px larger than band - height spills out of the band — same as the validation finding; data-only, guard adds complexity.
  - `[low]` `[reject]` (edge) Zero-area polygon from zero ship size leaves the ship overlapping — needs ship_width_px or ship_height_px 0, which no data uses; guard adds a branch.
  - `[low]` `[reject]` (edge) Centre exactly on a zero-area polygon isn't pushed — same degenerate-tuning precondition; the y-squeeze still resolves it.
  - `[low]` `[reject]` (edge) Removed assert_same on the cached hull — same as the blind in-place finding.
  - `[false]` `[reject]` (edge) Holding hull_polygon() across a tick forces a hidden per-tick copy — no gameplay caller holds it: step_lock passes it to a static function and drops it before the convoy's next tick.
  - `[medium]` `[patch]` (verification-gap) Downward branch of the screen-edge squeeze has no test — added `resolve_hull((0, 890))` → x 0, no overlap, y ≈ 909.71, plus the right-edge mirror.
  - `[false]` `[reject]` (intent) The solid shape is a hexagon, not a literal triangle — a 3-vertex triangle enclosing two side-by-side hulls must reach roughly 240 px past them on each side, contradicting "covering the whole formation" and sliding along it; the convex outline of the formation is the only shape meeting both, and decision #51 records it for the operator.
  - `[low]` `[defer]` (intent) Polygon covers the 80% hitboxes, so the player circle can overlap drawn hulls — pre-existing since Story 6.1 (it resolved against the same hitbox rects); deferred for the operator playtest.
  - `[low]` `[patch]` (intent) Mock absolute y not followed — same root as the blind mock-y finding; row 51 amended.
  - `[low]` `[patch]` (intent) Gap descent only proven in the pure function, not via step_lock with a real convoy — added a real-convoy step_lock descent at x 164.
  - `[low]` `[patch]` (intent) Out-of-scope test_level change — same as the blind finding; documented.
  - `[false]` `[reject]` (intent) Artifact-only receipt does not apply — correct and informational; no receipt is asserted.

## Design Notes

Circle vs convex polygon, no allocation: iterate edges with indices `i`, `(i + 1) % n`. Inside test: all edge cross products share a sign (winding-independent). Outside push: closest point over all edges (`Geometry2D.get_closest_point_to_segment` returns a Vector2, no heap allocation). Inside push: for each edge, outward normal (flip by the sign of the polygon's area or by testing against the centroid) and signed distance; leave by the smallest. Squeeze y-push: the overlap set on a vertical line is one interval (the disc-inflated convex polygon is convex), so bisect between the current y and `min_y - radius` / `max_y + radius` (~24 iterations each) and take the nearer free y.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` then `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` (`<GODOT_DIR>` from `LOCAL.md`) -- expected: all tests pass, no new failures.
- `git grep -n "FLANK_TOP\|FLANK_BOTTOM\|FlankTop\|FlankBottom\|lead_offset\|hull_rects\|\.facing" -- game` -- expected: no hits in convoy code or tests.

## Auto Run Result

Status: done

**Summary:** DW-83 resolved per the operator decision of 2026-10-10. The convoy is now three nose-up cargo ships side by side (8 px gaps), the middle (lead) ship raised 20 px, centred in y 760-920, sliding as one group ping-pong with no mirroring. The Player collides with one solid convex polygon (the outline of the three hitboxes, gaps included), so it can no longer slip between ships; per-ship hitboxes still handle enemy shots, Mauls and player/ally shot blocking.

**Files changed:**
- `game/data/tuning.json` — `convoy.lead_offset_px` replaced by `gap_px` 8 and `lead_raise_px` 20.
- `game/entities/allies/convoy.gd`, `convoy.tscn` — new layout, `FlankLeft`/`FlankRight`, `hull_polygon()` replaces `hull_rects()`.
- `game/entities/allies/convoy_ship.gd` — `facing` removed, nose-up pentagon.
- `game/entities/player/player.gd` — circle vs convex polygon `resolve_hull`/`overlaps_hull`, bisection y-squeeze.
- `game/tests/unit/test_convoy.gd`, `test_player_convoy.gd` — rewritten for the new layout and polygon, every matrix row covered.
- `game/tests/unit/test_ally_bolt.gd`, `test_level.gd`, `test_maul.gd`, `test_missile.gd`, `test_needle_bolt.gd`, `test_projectile.gd` — flank renames and position-dependent expectations; `test_level.gd` Maul-wave slot-y tolerance now counts ticks since the spawn tick.
- `gdd.md`, `epics.md` (FR32, Story 6.1 AC), `decision-log.md` (row 51), `game-architecture.md` (As-built DW-83) — docs amended.

**Review:** 25 findings. Patched: 2 medium (grouped: the screen-edge squeeze tests) and 9 low (shoulder-while-moving and real-convoy gap tests, narrower tuning key test, doc comment rewrap, decision-row notes on the mock, supersede marker in the architecture, test_level change documented). Deferred: 1 low (hull circle vs drawn extents, pre-existing). Rejected: 4 false and 9 low, with reasons in the triage log. Follow-up review recommended: false (one medium entry patched, no high).

**Verification:** `--import`, then the full headless GUT suite: 1644/1644 passing (baseline 1631/1631). `git grep` for the old names, `lead_offset`, `hull_rects` and `.facing` under `game/` finds only the intended absence check at `game/tests/unit/test_convoy.gd:72`. A baseline-worktree run confirmed the Maul-wave test's earlier failure came from frame alignment, not convoy logic.

**Residual risks:** Feel is not verified: whether the formation reads well and sliding along the sloped shoulders feels right needs an operator playtest of `dev_convoy`. The polygon is the formation's convex outline rather than a literal 3-vertex triangle (recorded in decision #51). The Player can still overlap drawn hull edges by up to 16 px (deferred).
