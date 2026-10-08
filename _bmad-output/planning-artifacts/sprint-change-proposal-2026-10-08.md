---
title: Sprint Change Proposal - Pull the player ship sprite forward from Story 8.2
date: 2026-10-08
trigger: User request (correct-course 2026-10-08)
mode: batch
scope: minor
status: applied 2026-10-08 - awaiting user review (placement and mode defaulted to the recommendation when the user did not answer)
---

# Sprint Change Proposal: 2026-10-08

## 1. Issue Summary

The player ship is still the Story 1.2 placeholder: a 96 px radial `GradientTexture2D` circle (`game/entities/player/player.tscn`, resized by `player.gd` `_ready` from `player.sprite_px`). Epics 1–3 are done, and every playtest from here on is judged with a glowing dot as the hero ship. The real ship art is scheduled in Story 8.2 (SHOULD, art pass), which is the last epic.

The user asked to **pull the player ship art forward from Story 8.2**:
- replace the placeholder circle with a Kenney CC0 ship sprite
- about 96 px, recoloured cyan/teal, facing up
- credited in `game/assets/CREDITS.md`
- inserted before Epic 4

The rest of Story 8.2 stays in Epic 8.

**Evidence:**
- `player.tscn` `Sprite` uses `GradientTexture2D_hull` (96×96 radial fill).
- `game/assets/CREDITS.md`: "Third-party assets: None yet"; "Placeholder sprites … are drawn in code".
- The target is already specified, so this needs no design change:
  - GDD movement table: "24 px circle centred on a ~96 px sprite"
  - DESIGN.md Asset Direction: Kenney Space Shooter Redux, player hull recoloured `coalition` #22E6FF
  - Architecture tree: `assets/sprites/player/`

## 2. Impact Analysis

### Checklist results

| Item | Status | Finding |
|---|---|---|
| 1.1 Trigger | [x] | User request. No story failed. Placeholder art is getting in the way of playtest judgement |
| 1.2 Problem type | [x] | Strategic resequencing (scope moved earlier), not a new requirement |
| 1.3 Evidence | [x] | See above |
| 2.1 Current epic | [x] | Epics 1–3 are done. Epic 4 has not started |
| 2.2 Epic changes | [!] | Add Story 3.6 to Epic 3. Epic 3 goes back to `in-progress` until 3.6 is done |
| 2.3 Future epics | [!] | Story 8.2: the player ship is removed from its art-pass AC; allies, convoy, enemies, backgrounds, portraits, Flagship and HUD stay. Epics 4–7 are unaffected |
| 2.4 Obsolete / new epics | [N/A] | None |
| 2.5 Resequencing | [x] | Story 3.6 runs before Story 4.1 |
| 3.1 GDD | [!] | No design change. Decision log row #37 records the move. The GDD `epics.md` E3 list gets the story |
| 3.2 Architecture | [x] | No change now. The tree already plans `assets/sprites/player/`. Story 3.6 records the as-built |
| 3.3 UX | [x] | No change. DESIGN.md Asset Direction already describes the target |
| 3.4 Other | [!] | First image asset, so the `--import` step and the `.import` sidecar apply. The placeholder resize in `player.gd` and its test change. `CREDITS.md` gets its first third-party row |
| 4.1 Direct adjustment | Viable | Effort Low, risk Low |
| 4.2 Rollback | N/A | Nothing to revert |
| 4.3 MVP review | N/A | MVP and the cut order are unchanged |
| 4.4 Path | [x] | Option 1, Direct Adjustment |

### Epic impact

- **Epic 3:** one new story, 3.6. Its status changes from `backlog` to `in-progress`, because the sprint-status `backlog` value was already stale (Epic 3 retro item 29).
- **Epic 8:** the Story 8.2 AC no longer covers the player ship.
- **Epics 4–7:** no change.

### Technical impact

- **`player.tscn`:** the `Sprite` texture becomes the PNG, and the gradient sub-resources are dropped.
- **`player.gd`:**
  - In `_ready`, the placeholder resize (`GradientTexture2D.width/height`) becomes a uniform scale, so the texture's longer side equals `player.sprite_px`.
  - The hurtbox (`player.hurtbox_diameter_px`, 24 px) is unchanged.
- **`Muzzle` marker (now y -40):** it may need to move to match the hull's nose. A ~96×73 Kenney hull puts the nose at about y -36.
- **Unchanged parts to watch:**
  - the i-frame flicker and the hidden-on-death ship both toggle `_sprite.visible`, so they keep working
  - `MissileRing` (radius ≤ ship half-size) and `ShieldBubble` sit at `z_index = 1` above the sprite
- **New files:**
  - `game/assets/sprites/player/` with the PNG and its `.import` sidecar (tracked)
  - `game/.godot/imported/` stays gitignored
  - run the headless `--import` before the tests (AGENTS.md section 3)
- **Glow:** the hull must stay readable under `render.glow` (hdr_threshold 0.55). An HDR-bright tint would bloom. Use a tint at or below 1.0, as the placeholder did.

## 3. Recommended Approach

**Direct Adjustment.** Add Story 3.6 to Epic 3, following the precedent of Stories 1.8–1.10 (added to Epic 1 after it was done). Then trim Story 8.2.

| Story | What | Tier | Effort | Risk |
|---|---|---|---|---|
| 3.6 Fly a Real Ship | Kenney Space Shooter Redux fighter hull, recoloured `coalition`, facing up, scaled to `player.sprite_px`, credited | SHOULD (inherits 8.2's tier) | Low (~0.5 h) | Low |

Placement alternative considered: a Story 4.0 at the head of Epic 4. Rejected because the numbering is awkward and Epic 4 is about game flow.

Timeline: about 0.5 h before Epic 4. Epic 8 gets the same amount shorter. The cut order is unchanged: if Story 3.6 is cut, the placeholder circle stays until Story 8.2.

## 4. Detailed Change Proposals

### 4.1 Stories: `planning-artifacts/epics.md`

**Epic 3 intro.** Add an amendment note under the epic description:

```
> **Amended 2026-10-08 (decision #37):** Story 3.6 (player ship sprite) was pulled forward from Story 8.2 and runs before Epic 4.
```

**New Story 3.6.** Insert it after Story 3.5:

```
### Story 3.6: Fly a Real Ship

As a player,
I want my ship to look like a fighter instead of a glowing circle,
So that I can read where my ship is and where its nose points at a glance.

**Tier / Covers:** SHOULD · FR64 (partial: player ship), NFR10 · GDD decision #37 (pulled forward from Story 8.2)

**Acceptance Criteria:**

**Given** the Kenney Space Shooter Redux pack (CC0)
**When** the Player scene loads
**Then** `Player/Sprite` shows a Kenney fighter hull (e.g. `playerShip1_blue.png`) stored under `game/assets/sprites/player/`, facing up (nose toward −y), instead of the radial `GradientTexture2D` circle
**And** the hull is recoloured to `coalition` cyan/teal (#22E6FF), either baked into the committed PNG or by a tint at or below 1.0, so it no longer reads as Kenney's default blue and doesn't bloom into a blob under `render.glow`
**And** the PNG's `.import` sidecar is committed, and the headless `--import` step runs before the tests (AGENTS.md section 3)

**Given** `player.sprite_px` (96) in `tuning.json`
**When** the Player runs `_ready`
**Then** the sprite is scaled uniformly so its longer side equals `player.sprite_px`, keeping its aspect ratio, with no hard-coded size
**And** the hurtbox stays the circle from `player.hurtbox_diameter_px` (24 px), centred on the hull
**And** lasers, the missile and the barrage still leave from the hull's nose (the `Muzzle` marker moved to the nose if needed), with the muzzle flash on it

**Given** the existing ship feedback
**When** I take a hit, die, raise the Shield or wait for the missile to reload
**Then** the i-frame flicker, the ship hidden on death, the shield bubble and the missile cooldown ring all still work over the new sprite, and the ring stays readable on top of it

**Given** the new art asset
**When** I check `game/assets/CREDITS.md`
**Then** it is listed under "Third-party assets" with its file, source (Kenney Space Shooter Redux, kenney.nl), licence (CC0 1.0) and a note that it was recoloured
**And** the "placeholder sprites are drawn in code" note no longer covers the player ship

**Given** the GUT suite runs headless
**When** the player tests run
**Then** a test asserts that the sprite has a non-null texture that is not a `GradientTexture2D`, and that its scaled longer side equals `player.sprite_px` within 1 px
**And** the existing player, shield-bubble and missile-ring tests still pass

**Given** the story is done
**When** I read `game-architecture.md`
**Then** it records the as-built: `assets/sprites/player/` exists, and `Player` scales the hull from `player.sprite_px`

**Given** I play the dev level (human check)
**When** I fly and fight
**Then** the ship reads at a glance as a cyan/teal fighter pointing up, distinct from enemies and pickups, with glow on
```

Rationale: this is user-requested scope moved forward. The ACs reuse the existing contract (GDD hitbox and sprite size, DESIGN.md Asset Direction, AGENTS.md asset and credit rules, data-driven sizing).

**Story 8.2: Make the Game Look Neon.** First AC.

OLD:
```
**Then** Coalition ships (player, allies, convoy) are cyan/teal, Sovereignty enemies …
```
NEW:
```
**Then** Coalition ships (allies and convoy; the player ship is already done in Story 3.6, decision #37) are cyan/teal, Sovereignty enemies …
**And** the player ship from Story 3.6 is kept, and is only re-tinted if the final palette pass changes `coalition`
```

Rationale: the rest of 8.2 stays in Epic 8, as the user asked.

**FR coverage map and Epic List.**
- `FR64: Epic 8 - Art pass` → `FR64: Epic 3 - Player ship sprite (Story 3.6); Epic 8 - Art pass`
- The Epic 3 "FRs covered" line gets `FR64 (player ship)`.

### 4.2 GDD

**`decision-log.md`.** New row:

```
| 37 | 2026-10-08 | Player ship art pulled forward from Story 8.2 into a new Story 3.6 (before Epic 4): a Kenney Space Shooter Redux (CC0) fighter hull, ~96 px (`player.sprite_px`), recoloured `coalition` cyan/teal, facing up, credited in `game/assets/CREDITS.md`. The rest of Story 8.2 (allies, convoy, enemies, backgrounds, portraits, Flagship, HUD) stays in Epic 8. Tier stays SHOULD | User (correct-course 2026-10-08) | Applied 2026-10-08 via sprint-change-proposal-2026-10-08 (Story 3.6, Story 8.2 AC) |
```

**`gdds/.../epics.md` E3 story list.** Add:

```
6. *(SHOULD)* **Player ship sprite:** a Kenney fighter hull recoloured cyan/teal, pulled forward from the E8 art pass (decision #37).
```

**`gdd.md`.** No change. Its movement table already specifies the ~96 px sprite and the 24 px hitbox.

### 4.3 Architecture, UX, Narrative

No changes now. Story 3.6 records the architecture as-built.

### 4.4 Sprint status: `implementation-artifacts/sprint-status.yaml`

- `epic-3: backlog` → `epic-3: in-progress`
- Add `3-6-fly-a-real-ship: backlog` after `3-5-unleash-the-barrage`.

## 5. Implementation Handoff

- **Scope:** Minor. The Developer agent implements it directly.
- **Next step:** create the story file with `gds-create-story` (`3-6-fly-a-real-ship`), then build it with `gds-dev-story` or `bmad-loop` before starting Story 4.1.
- **Asset sourcing:** the developer downloads the Kenney Space Shooter Redux pack from kenney.nl. Extract it into a scratch directory, then copy only the chosen hull PNG into `game/assets/sprites/player/`. Don't commit the pack zip (AGENTS.md section 5).
- **Success criteria:**
  - every Story 3.6 AC passes
  - the GUT suite is green after `--import`
  - `CREDITS.md` lists the asset
  - Story 3.6 is `done` before Story 4.1 starts
