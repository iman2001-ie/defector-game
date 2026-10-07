---
title: Sprint Change Proposal - Movement lock, straight-up missile, brighter glow, architecture as-built
date: 2026-10-07
trigger: GDD decision log #29 and #30 (Story 1.7 playtest and export check); Epic 1 retro action item 5 (DW-11)
mode: batch
scope: moderate
status: approved by user 2026-10-07 - applied
---

# Sprint Change Proposal: 2026-10-07

## 1. Issue Summary

The Story 1.7 developer playtest passed the E1 fun gate (decision #28). It also surfaced two changes that the user has already decided:

- **#29 Movement and missile redesign.** This supersedes #5 (movement) and #6 (missile direction).
  - The ship sits **exactly on the cursor with zero delay**: no chase, smoothing or max speed.
  - The cursor itself is **confined to the player zone** (bottom 60%, y 432–1080), so the lock stays exact everywhere.
  - The convoy stays solid to the ship (#25). On contact the game pushes the cursor along with the ship.
  - The missile fires **straight up from the ship's nose**, like the lasers. It no longer aims at the cursor.
- **#30 Glow.** Laser bolts need a stronger glow so they read as bullets, and the overall neon/bloom should be slightly brighter (judged on the exported build). This is tuning only.

Two knock-on effects need a design answer:
- With the ship on the cursor, the **reticle** would sit on top of the ship.
- The **missile cooldown ring**, which was drawn on the reticle, needs a new home.

The user decided on 2026-10-07 (proposed decision-log #31):
- Remove the reticle.
- Draw the cooldown ring on top of the ship. It is no bigger than the ship and must be easy to see.

Also folded in: **Epic 1 retro action item 5 / DW-11**, reconcile `game-architecture.md` with the as-built.

**Evidence:**
- Decision log rows #28–#30, both marked *Pending - apply via /gds-correct-course*.
- `game/entities/player/player.gd` (exponential capped chase solver).
- `player_weapons.gd` `missile_direction`.
- `reticle.gd` (cooldown arc at the cursor).
- `sandbox.tscn` WorldEnvironment (glow 0.8 / bloom 0.05 / threshold 0.6, hard-coded in the scene).
- `laser_bolt.tscn` (6×28 px gradient, colour max 1.0, so it barely crosses the HDR glow threshold).

## 2. Impact Analysis

### Checklist results

| Item | Status | Finding |
|---|---|---|
| 1.1 Trigger | [x] | Story 1.7 playtest (fun gate) and export glow check |
| 1.2 Problem type | [x] | New requirement from the playtest. The design was changed on purpose after the prototype, as #11 planned |
| 1.3 Evidence | [x] | Decision log #28–#30. Code locations above |
| 2.1 Current epic | [!] | Epic 1 is functionally done, but its movement, missile and reticle no longer match the design. It needs follow-up stories |
| 2.2 Epic changes | [!] | Add Stories 1.8, 1.9 and 1.10 to Epic 1. Mark Stories 1.2 and 1.5 as partly superseded (history kept) |
| 2.3 Future epics | [!] | Story 4.4 (resume must not make the ship jump), 4.5 (confinement under letterbox) and 6.1 (convoy push now warps the cursor; sweep so a flick can't jump through a hull). No other epic depends on chase or aiming |
| 2.4 Obsolete / new epics | [N/A] | None |
| 2.5 Resequencing | [x] | The new stories run before Epic 2, so Epic 2's enemies are built and tuned against the final movement |
| 3.1 GDD | [!] | Movement table, Cursor row, Weapons table + missile note, Controls table, Weapon Systems roles ("only aimable shot"), Aim model, GDD epics E1 |
| 3.2 Architecture | [!] | Core systems row, cursor/PauseArbiter, player vs convoy, UI Framework reticle line, Config example (`max_speed`), project tree (`reticle.*`), GDD coverage rows, glow values in data. Plus the DW-11 as-built drift |
| 3.3 UX | [!] | DESIGN.md `reticle` token, Shapes, Components (Reticle); EXPERIENCE.md HUD hierarchy, State Patterns (Playing, Between waves), Flow 1 step 4 ("fires one around an asteroid"), HUD & Diegetic UI |
| 3.4 Other | [!] | `tuning.json` keys removed and added; tests for chase, missile aim and reticle rewritten; `debug_tools.gd` bench warp still valid (the ship now sits on the warp point) |
| 4.1 Direct adjustment | Viable | Effort Medium, risk Low |
| 4.2 Rollback | Not viable | Nothing to revert. Movement and missile are rewritten in place |
| 4.3 MVP review | Not viable / not needed | MVP unaffected |
| 4.4 Path | [x] | Option 1, Direct Adjustment |

### Epic impact

- **Epic 1:** 3 new stories (1.8, 1.9, 1.10). Its status goes from `backlog` back to `in-progress`.
- **Epics 4 and 6:** small AC additions to Stories 4.4, 4.5 and 6.1. No new work items.
- **Epics 2, 3, 5, 7 and 8:** no change.
  - Epic 8's Story 8.2 (art pass) keeps the final look; Story 1.9 is only a tuning step.
  - Story 5.8's `[RMB] MISSILE` hint text still works.

### Technical impact

- **`player.gd`:**
  - The chase solver (`chase_step`, `solve_chase_gain`, `is_ref_time_feasible`, gain constants) is deleted.
  - Movement becomes: clamp the cursor into the zone, then place the ship on it.
- **Cursor confinement:**
  - Godot can only confine the cursor to the window, not to a sub-rect.
  - So whenever the mouse's viewport y is below `player.bounds_y.min`, the game calls `Viewport.warp_mouse` to put it back at the zone edge.
  - That way, moving back down responds on the very first frame, with no dead travel.
  - This is the only place besides convoy contact and resume that warps the mouse.
- **Missile:**
  - Direction is the constant `Vector2.UP` from the nose.
  - `missile_direction` and `weapons.missile.straight_up_within_px` go away.
- **Reticle:**
  - `reticle.tscn` and `reticle.gd` are deleted.
  - A cooldown-ring node is a child of the Player, drawn above the ship sprite.
  - It is still driven only by `Events.missile_cooldown_changed` and still uses `draw_arc`.
- **`tuning.json`:**
  - Removed: `player.max_speed`, `player.chase_ref_distance_px`, `player.chase_ref_time_s`, `weapons.missile.straight_up_within_px`.
  - Added: `render.glow.*` (Story 1.9) and the laser bolt glow values.
- **Risks to watch in Epic 2 playtests** (no action now):
  - An instant ship lets the player "teleport" through bullet gaps and makes dodging easier.
    - The difficulty knobs are enemy bullet density and speed, not movement.
    - Mouse-locked ships are the norm in the genre this game is modelled on.
  - A teleporting ship does not register contact with an enemy it jumps *over* in one frame.
    - That's acceptable (forgiving), and it matches the 24 px hitbox philosophy.
  - With the missile fixed straight up, DW-3 (splash vs `grid_4x2` spacing) can no longer be dodged by angling.
    - #28 kept the current splash. Revisit only if Epic 2 formations feel weak.

## 3. Recommended Approach

**Direct Adjustment.** Add three stories to Epic 1 and update the planning documents now, so the stories are built against the right contract.

| Story | What | Effort | Risk |
|---|---|---|---|
| 1.8 Lock the ship to the cursor and fire missiles straight up | #29 + #31: zero-delay lock, cursor confined to the zone, no jump on resume, straight-up missile, reticle removed, cooldown ring on the ship | Medium | Low |
| 1.9 Make laser bolts and the neon glow brighter | #30: brighter bolts, slightly stronger WorldEnvironment glow; glow values moved into `tuning.json` so F5 can tune them live | Low | Low |
| 1.10 Reconcile the architecture with the as-built | DW-11 / retro item 5, plus the as-built of 1.8/1.9 and DW-13 (Playfield, PlayerWeapons split) and DW-8 (`Config.reload`). Runs last so it reflects the final code. Also closes DW-17 (the export command lacks `--import`), a one-line fix in the same doc | Low | Low |

The **convoy part of #29** (the push moves the cursor) has nothing to build against until the convoy exists. It goes into **Story 6.1's ACs**, not Story 1.8. Story 1.8 only puts the rule in place: the ship's position is the source of truth, and the cursor is warped to follow it.

Timeline: adds roughly 1.5–2 h before Epic 2. MVP and the cut order are unchanged.

## 4. Detailed Change Proposals

### 4.1 GDD: `gdds/gdd-game-project-2026-10-06/gdd.md` (v0.3 → v0.4, `updated: 2026-10-07`)

**Player ship movement table**

| Row | OLD | NEW |
|---|---|---|
| Movement model | Ship chases the cursor. It does not snap. | The ship sits exactly on the cursor, with zero delay (decision #29). |
| Max speed | 1400 px/s | *(row removed)* |
| Smoothing | Ship covers a 150 px cursor move in about 0.12 s | *(row removed)* |
| Movement bounds | Bottom 60% of the screen (y 432–1080), full width | Bottom 60% of the screen (y 432–1080), full width. The **cursor itself** is confined to this zone during gameplay, so the lock is exact everywhere. |
| Cursor | Hidden during gameplay and confined to the window. A small reticle marks the cursor position. | Hidden during gameplay and confined to the player zone. There is no reticle: the ship is the cursor. If the convoy pushes the ship, the cursor moves with it. When the game resumes from any pause, the cursor is put back on the ship, so the ship never jumps. |

**Weapons table, Missile row**
- Direction: `Toward the cursor (see note)` → `Straight up from the ship's nose`
- Notes: `Unguided. Unlimited. A radial cooldown ring is shown on the reticle.` → `Unguided. Unlimited. A radial cooldown ring is drawn on top of the ship while it reloads.`

**Missile direction note** (the four bullets under the table)

OLD:
```
- **Missile direction:** the missile flies along the ship-to-cursor vector.
  - If the cursor is within 32 px of the ship, the missile flies straight up.
  - The ship chases the cursor, so in practice the missile usually flies close to straight up, like the lasers.
  - It angles off when the cursor leads the ship (for example during fast movement), which lets the player aim a missile around cover.
```
NEW:
```
- **Missile direction:** the missile fires straight up from the ship's nose, like the lasers (decision #29). The player aims it by positioning the ship, for example by sliding out from behind cover.
```

**Controls table**
- `Mouse movement | Ship chases the cursor` → `Mouse movement | The ship sits on the cursor (bottom 60% only)`
- `RMB | Missile toward the cursor (1.5 s cooldown)` → `RMB | Missile, straight up (1.5 s cooldown)`

**Weapon Systems → Roles**
- `**Missile:** burst damage and splash against formations and tanks, and the only aimable shot.` → `**Missile:** burst damage and splash against formations and tanks, on a cooldown, so *when* you fire it matters.`

**Aiming and Combat Mechanics**
- `**Aim model:** fixed upward fire for lasers. The missile is aimed by the cursor offset from the ship (see Primary Mechanics). There is no lock-on.` → `**Aim model:** all player weapons fire straight up; the player aims by positioning the ship. There is no lock-on.`

**Decision log (`decision-log.md`)**
- #29 status → `Applied 2026-10-07 via sprint-change-proposal-2026-10-07 (Stories 1.8, 6.1 AC)`
- #30 status → `Applied 2026-10-07 via sprint-change-proposal-2026-10-07 (Story 1.9)`
- New row **#31**:

  | # | Date | Decision / Change | Source | Status |
  |---|---|---|---|---|
  | 31 | 2026-10-07 | Follow-ons of #29: (1) The reticle is removed, because the ship is the cursor. (2) The missile cooldown ring is drawn on top of the ship, no bigger than the ship and high-contrast so it's easy to see. (3) On resume from any pause, the cursor is warped back to the ship, so the ship never jumps. (4) The convoy push sweeps the ship's move, so a fast flick can't jump through a hull, and then warps the cursor to the ship. (5) Glow values move into `tuning.json` (`render.glow`). (6) New Stories 1.8–1.10 run before Epic 2 | User (correct-course 2026-10-07) | Applied |

**GDD epics summary (`gdds/.../epics.md`, E1)**
- Item 1: `the ship chases the cursor (1400 px/s cap, smoothing) and stays inside the bottom 60% of the screen. The cursor is hidden and replaced by a reticle.` → `the ship sits exactly on the cursor, which is confined to the bottom 60% of the screen and hidden (decision #29).`
- Item 3: `RMB fires a missile toward the cursor (straight up within 32 px). … and shows a radial cooldown ring.` → `RMB fires a missile straight up from the ship's nose. … and shows a radial cooldown ring on the ship.`
- Goal line: `"mouse-follow shooting …"` is kept. It still describes the game.

### 4.2 Epics: `planning-artifacts/epics.md`

**Requirements**
- **FR1** → `The player ship sits exactly on the mouse cursor with zero delay (no chase, smoothing or speed cap). It never rotates (always faces up). The cursor is confined to the bottom 60% of the screen (y 432–1080), full width, so the ship is too (GDD decision #29).`
- **FR3** → `During gameplay the OS cursor is hidden and confined to the player zone. There is no reticle; the ship marks the cursor. On resume from any pause the cursor is warped to the ship, so the ship never jumps.`
- **FR5** → `RMB fires an unguided missile straight up from the ship's nose at 900 px/s. It deals 8 damage to the target it hits and 3 splash damage to every other target within 120 px. It has a 1.5 s cooldown, unlimited ammo, and a radial cooldown ring drawn on top of the ship.`
- **FR32**, append: `When the convoy pushes the ship, the cursor is moved with it (decision #29).`
- **FR62**: `the missile cooldown ring` → `the missile cooldown ring (in-world, on the ship)`
- **Coverage map:**
  - `FR1: Epic 1 - Cursor-chase ship movement and bounds` → `FR1: Epic 1 - Cursor-locked ship movement and bounds`
  - `FR5: Epic 1 - Aimed missile, splash, cooldown ring` → `FR5: Epic 1 - Straight-up missile, splash, cooldown ring`

**Epic 1 description** (Epic List and the Epic 1 header): `fire lasers and aimed missiles` → `fire lasers and missiles`

**Story 1.2 and Story 1.5**: their ACs are kept as history. Add one line under each Tier / Covers line:
- 1.2: `> **Superseded in part by Story 1.8 (decision #29):** the chase AC and the reticle AC.`
- 1.5: `> **Superseded in part by Story 1.8 (decision #29):** the ship→cursor direction AC and the reticle ring location.`

**New Story 1.8** (inserted after Story 1.7)

```
### Story 1.8: Lock the Ship to the Cursor and Fire Missiles Straight Up

As a player,
I want my ship to sit exactly under my mouse and my missile to fire straight ahead,
So that movement feels instant and precise and every weapon aims the same way.

**Tier / Covers:** MUST · FR1, FR3, FR5, FR62 (cooldown ring) · GDD decisions #29, #31

**Acceptance Criteria:**

**Given** gameplay is running with no pause reasons
**When** I move the mouse
**Then** in the same physics tick, the ship's position equals the cursor position clamped to x 0–1920, y `player.bounds_y.min`–`max`, with no interpolation, speed cap or lag
**And** `player.max_speed`, `player.chase_ref_distance_px` and `player.chase_ref_time_s` are removed from `tuning.json`, along with the chase solver code and its tests

**Given** I move the mouse above y 432 (in viewport coordinates)
**When** the next physics tick runs
**Then** the cursor is warped back to the zone edge (`Viewport.warp_mouse`), the ship stays on the edge, and the first downward mouse movement moves the ship at once (no dead travel)

**Given** any pause reason is popped and gameplay resumes
**When** the mouse mode returns to `MOUSE_MODE_CONFINED_HIDDEN`
**Then** the cursor is warped to the ship's current position, so the ship does not jump to where the cursor was left during the pause

**Given** the missile is ready
**When** I press RMB
**Then** the missile spawns at the ship's nose and flies straight up (`Vector2.UP`) at 900 px/s, wherever the cursor was before clamping
**And** `missile_direction` and `weapons.missile.straight_up_within_px` are removed

**Given** the Reticle scene
**When** this story is done
**Then** `reticle.tscn`/`reticle.gd` no longer exist, and the sandbox has no reticle

**Given** I just fired a missile
**When** the 1.5 s cooldown runs
**Then** a cooldown ring is drawn on top of the ship sprite (a Player child with a z-index above the sprite), no larger than the ship, in a high-contrast colour (`text` #E8F4FF with a dark `background` outline, 4–5 px stroke), sweeping clockwise from 12 o'clock over the remaining fraction and hidden when ready
**And** it is driven only by `Events.missile_cooldown_changed(ratio)` and drawn with `draw_arc`
**And** its radius, stroke and colours come from the UX token `missileRing`, with the radius and stroke as tunable data
**And** it reads clearly over the ship while firing lasers over explosions (checked by the developer in the sandbox)

**Given** the GUT suite
**When** it runs headless
**Then** tests cover: the lock places the ship on a clamped target in one tick, the zone clamp and the cursor warp decision (a pure function of the mouse position and bounds), resume-warp, straight-up missile direction, and the ring ratio handling; all pass
```

**New Story 1.9**

```
### Story 1.9: Make Laser Bolts and the Neon Glow Brighter

As a player,
I want my laser bolts to glow like real bullets and the whole screen to pop a little more,
So that my shots read instantly and the neon look lands.

**Tier / Covers:** MUST (tuning) · FR64 (partial), NFR10 · GDD decision #30, ADR-003

**Acceptance Criteria:**

**Given** the WorldEnvironment glow values (intensity, bloom, HDR threshold)
**When** the scene starts or F5 reloads data
**Then** they are read from `tuning.json → render.glow` (not hard-coded in `.tscn`) and applied by the scene root
**And** the first-pass values are slightly brighter than today (intensity 0.8, bloom 0.05, threshold 0.6 are the baseline)

**Given** a laser bolt
**When** it renders
**Then** its core is HDR-bright (modulate/self-modulate above 1.0, so it clearly crosses the glow threshold) with a wider additive halo, and the brightness values come from `tuning.json` (for example `weapons.laser.glow_energy`)
**And** with the WorldEnvironment glow turned off, the additive halo alone still makes the bolt read as a bullet (ADR-003 fallback)

**Given** the `--bench=20` run
**When** it runs after the change
**Then** p99 frame time stays under 16.6 ms, and the result is recorded in the story

**Given** an exported Windows build
**When** the developer runs it
**Then** the developer confirms that the bolts read as bullets and the neon is slightly brighter but not washed out (operator action), and records the final values in the decision log as a tuning note under #30
```

**New Story 1.10**

```
### Story 1.10: Reconcile the Architecture with the As-Built

As the developer,
I want game-architecture.md to describe the code that actually exists,
So that agents building Epic 2 onwards follow the real patterns.

**Tier / Covers:** MUST (docs) · Epic 1 retro action item 5, DW-11, DW-17

**Acceptance Criteria:**

**Given** Stories 1.8 and 1.9 are done
**When** I update `_bmad-output/game-architecture.md`
**Then** it documents, matching the code:
  - the `play_sfx` pitch parameter
  - the tier `sfx_volume_db` (decision #26)
  - the single explosion scene
  - Spawner and ShakeCamera registering with Feedback (accepted as the design, retro C1)
  - the `-- --stress` / `--bench=N` command-line modes
  - the `Playfield` class and the `PlayerWeapons` split (DW-13)
  - `Config.reload()` (DW-8)
  - the cursor lock, zone confinement and the resume-warp owner
  - the cooldown ring on the ship
  - `render.glow` data
**And** the export command shows the `--import` step first (DW-17)
**And** every section changed is listed in a short "As-built reconciliation 2026-10-xx" note at the end of the document

**Given** the updated document
**When** I grep it for `reticle`, `max_speed`, `chase` and `toward the cursor`
**Then** the only matches are in historical or superseded notes
```

**Story 4.4**, append to the Resume AC:
`**And** when gameplay resumes, the cursor is back on the ship and the ship has not moved (Story 1.8 resume-warp)`

**Story 4.5**, replace the last Then:
`**Then** the 1920×1080 playfield scales uniformly with letterbox bars, the ship still sits exactly on the cursor, and the cursor stays confined to the player zone (warps use viewport coordinates)`

**Story 6.1**, replace the player-vs-convoy AC:

OLD:
```
**Then** the Player (through a separate ~64 px `HullArea` circle that masks only `convoy`; the 24 px hurtbox is unchanged) pushes itself out along the shortest separation and slides along the hull, takes no damage, and is never pinned (the convoy moves only horizontally) (GDD decision #25)
```
NEW:
```
**Then** the Player (through a separate ~64 px `HullArea` circle that masks only `convoy`; the 24 px hurtbox is unchanged) stops at the hull. Its move from the previous position to the cursor target is swept against `convoy`, so a fast flick can't jump through a cargo ship. The ship pushes out along the shortest separation, slides along the hull, and takes no damage
**And** whenever the convoy blocks or pushes the ship, the cursor is warped to the ship's position, so the ship and cursor stay locked (GDD decisions #25, #29)
**And** the ship is never pinned: if the push-out and the zone clamp disagree, the push-out wins along y (the convoy moves only horizontally)
```

### 4.3 UX: `ux-designs/ux-defector-game-2026-10-06/`

**DESIGN.md** (`updated: 2026-10-07`)
- Frontmatter `components.reticle: 'coalition ring 32px; missile cooldown arc 4px stroke radius 22px, muted'` → replaced by `missileRing: 'cooldown arc drawn over the ship, radius ≤ ship half-size (first pass 36px), 5px stroke in text with a 2px background outline, sweeps clockwise from 12 o'clock, hidden when ready'`
- **Shapes**: `The reticle is a circle, and the cooldown arc sweeps clockwise from 12 o'clock.` → `The missile cooldown ring is a circular arc over the ship that sweeps clockwise from 12 o'clock.`
- **Components**: the `Reticle` bullet is replaced with:
  `- **Missile cooldown ring:** drawn on top of the ship (the ship is the cursor; there is no reticle, decision #29/#31). No bigger than the ship, in high-contrast text with a dark outline, so it reads over the cyan hull and over explosions. Visible only while the missile reloads.`

**EXPERIENCE.md**
- **HUD hierarchy**, item 2: `The reticle with its missile cooldown arc (at the cursor)` → `The missile cooldown ring (on the ship)`
- **State Patterns**:
  - Playing, Cursor: `Hidden, reticle shown` → `Hidden, locked to the ship`
  - Between waves, Cursor: `Reticle` → `Hidden, locked to the ship`
- **Component Patterns**, new row (also closes review-rubric N8):
  `| Missile cooldown ring | Appears full when the missile fires and empties clockwise over 1.5 s; hidden when ready. Freezes with the game while paused |`
- **Flow 1, step 4**: `Sam fires one around an asteroid.` → `Sam slides out from behind an asteroid and fires one up into the formation.`
- **HUD & Diegetic UI**: `except the shield bubble, the Needle's targeting line and the telegraph glows` → `except the shield bubble, the missile cooldown ring, the Needle's targeting line and the telegraph glows`

### 4.4 Architecture: `_bmad-output/game-architecture.md` (design changes now; full as-built in Story 1.10)

- **Core Systems**: `Player ship (cursor-chase movement, …)` → `Player ship (cursor-locked movement, …)`. In the HUD row, `cooldown ring` → `cooldown ring (in-world on the ship)`.
- **Technical Requirements**: `The cursor is hidden and confined during gameplay.` → `The cursor is hidden during gameplay and confined to the player zone (y 432–1080) by warping it back (Godot can only confine to the window).`
- **Cursor paragraph** (Pause Arbiter section), append:
  `On returning to gameplay mode, the cursor is warped to the Player's position, so the ship never jumps after a pause. PauseArbiter still owns `mouse_mode`. The Player owns all `warp_mouse` calls (zone confinement, convoy push, resume), reacting to a PauseArbiter resume signal.`
- **Player vs convoy** bullet, append:
  `The move from the previous position to the cursor target is swept (shape cast against `convoy`) before the push-out, because the ship moves instantly. After any block or push, the cursor is warped to the ship (GDD decision #29).`
- **UI Framework**: `The reticle is a Sprite2D in World that follows get_global_mouse_position(). The missile cooldown ring is drawn on it with draw_arc.` → `There is no reticle: the ship is the cursor (decision #29). The missile cooldown ring is a Player child, drawn above the ship sprite with draw_arc and driven only by Events.missile_cooldown_changed.`
- **Config example**: `Config.num("player.max_speed")` and the `_max_speed` sample → `Config.num("weapons.missile.speed_px_s")`, with the sample changed to `_missile_speed` / `_max_hearts`.
- **Project tree**: `player.tscn, player.gd, reticle.tscn, reticle.gd, shield_bubble.tscn` → `player.tscn, player.gd, player_weapons.gd, cooldown_ring.gd, shield_bubble.tscn`
- **Rendering row / ADR-003**, append: `Glow parameters are data (tuning.json → render.glow), applied by the scene root.`
- **GDD Coverage**:
  - `Cursor-chase movement, bottom 60%, hidden or confined cursor` → `Cursor-locked movement, cursor confined to bottom 60%, hidden cursor, resume-warp`
  - `reticle draw_arc` → `ring on the ship (draw_arc)`

### 4.5 Sprint status: `implementation-artifacts/sprint-status.yaml`

```yaml
  epic-1: in-progress            # was backlog (also fixes the DW-15 drift)
  ...
  1-7-validate-the-core-feel-in-a-stress-tested-sandbox: done
  1-8-lock-the-ship-to-the-cursor-and-fire-missiles-straight-up: backlog
  1-9-make-laser-bolts-and-the-neon-glow-brighter: backlog
  1-10-reconcile-the-architecture-with-the-as-built: backlog
  epic-1-retrospective: done     # unchanged; re-run after 1.10 per the retro's "path to acceptance"
  epic-2: backlog
```
The `last_updated` field is set to 2026-10-07.

## 5. Implementation Handoff

**Scope: Moderate.** Backlog reorganisation and document edits, then direct implementation by the dev loop. No PM or Architect replan is needed.

| Who | Responsibility |
|---|---|
| This workflow (on approval) | Apply sections 4.1–4.5 to the GDD, decision log, both epics files, UX DESIGN/EXPERIENCE, the architecture and sprint status |
| Dev loop / Developer agent | Implement Stories 1.8 → 1.9 → 1.10 in that order (`/gds-create-story`, then `/gds-dev-story`) |
| Developer (operator) | 1.8: check the ring visibility and the lock feel in the sandbox. 1.9: judge the glow on the exported build. Then re-run the Epic 1 retrospective |
| Dev loop (ledger) | When 1.10 is done, close DW-11 and DW-17 as resolved by story 1-10, so a sweep does not redo them |

**Success criteria**
- The ship lands on the cursor in the same tick everywhere in the zone, with no dead travel at the zone edge and no jump on resume.
- The missile always flies straight up from the nose.
- There is no reticle. The cooldown ring is visible on the ship during play.
- Bolts read as bullets on the exported build, and p99 stays under 16.6 ms.
- `game-architecture.md` has no stale chase, reticle or aim text, and documents the DW-11 list.
- Sprint status lists 1-8, 1-9 and 1-10 before Epic 2. The GUT suite is green.
