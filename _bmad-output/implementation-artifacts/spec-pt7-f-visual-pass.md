---
title: 'Epic 7 playtest F: a real throne-world planet, the planet behind the epilogue, no shield on Tarek, glowing convoy'
type: 'feature'
created: '2026-10-14'
status: 'done'
baseline_commit: 'e803edc'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:**
- The throne world is a flat dark band that doesn't read as a planet.
- The epilogue cuts to a near-black starfield, although Level 3 and the end screen both show the throne world.
- Tarek gets a blue shield ring while he covers Vale, which makes no sense for a fighter taking a hit.
- The convoy ships are dimmed to half brightness, so they get no glow.

**Approach:**
- **Planet:** draw the throne world as a shaded sphere hanging from the top edge, using a code shader. It has a smaller radius and a deeper cap, so both of its edges curve into view. It gets limb shading, slowly drifting violet surface bands, sparse dim city lights on the night side, and a thin atmosphere rim.
- **Epilogue:** the epilogue's story scene shows the throne world.
- **Tarek:** he still flies to the intercept point and holds there until the hit, but with no ring.
- **Convoy:** re-import the convoy hull at value 0.9, so it blooms like the other coalition ships.

## Boundaries & Constraints

**Always:**
- The planet stays at the top, behind every entity, and never reaches the player zone (y ≤ 432, spec pt7-b).
- The surface stays dark (below `render.glow.hdr_threshold`). Only the rim and the city lights may bloom, and only faintly.
- The planet uses violet tones and never the enemy magenta or the danger red as large areas.
- The planet's colours and geometry stay art constants in code.

**Ask First:** none. The operator asked for these on 2026-10-14.

**Never:**
- Move the formation rows or the Flagship.
- Show the throne world in Levels 1–2 or the opening story.
- Change Tarek's timeline or his damage.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior |
|---|---|---|
| Level 3 or end screen | `throne_world` | the sphere cap with both edges visible |
| Epilogue | story sequence `ending_council` | throne world |
| Opening story | any other sequence | `space_1`, as now |
| Tarek intercept | APPROACH → HOLD → hit | holds at the point, no ring drawn |
| Screen shake | the largest tuned shake | no gap shows at the cap's top edge |

</frozen-after-approval>

## Code Map

- `game/scenes/level/level_background.gd`: the arc constants and `_draw`; add a shader-driven planet child
- `game/scenes/level/throne_world.gdshader` (new): the sphere shading
- `game/scenes/story/story.gd`: picks the background per sequence
- `game/entities/allies/ally_ship.gd`: the SHIELD state, `_draw` ring, `shield_alpha` and `shield_visible`
- `game/data/tuning.json`: `allies.fall.shield_radius_px` and `shield_flash_hz` (remove)
- `tools/import_cc0_art.py:160`: the convoy recolor value
- tests: `test_level_background`, `test_ally_ship`, `test_tarek_fall_scene`, `test_level`, `test_data_files`, `test_story_scene`, `test_import_cc0_art.py`

## Tasks & Acceptance

**Execution:**
- [x] `level_background.gd` and the shader: the planet geometry (radius and cap height) and a ColorRect with the shader over the cap's bounding rect; keep `arc_points()` for the tests and the edge maths
- [x] `story.gd`: show `THRONE_WORLD` for `ending_council`
- [x] `ally_ship.gd` and its tests: rename SHIELD to HOLD and drop the ring drawing and its keys
- [x] convoy: change the import row's value to 0.9, re-run the import, update `CREDITS.md`
- [x] tests: update for the above
- [x] docs: a GDD decision-log row (amends pt7-d's "shield breaks")

**Acceptance Criteria:**
- Given the full suite, when GUT runs headless, then every test passes.
- Given Level 3, when it is played, then the operator sees a curved planet with depth and the enemies drawn in front of it.

## Verification

**Commands:**
- `--headless --path game --import`, then GUT: expected all pass
- `uv run python -m unittest tools/test_import_cc0_art.py`: pass

**Manual checks:**
- The operator looks at Level 3, the epilogue, Tarek's fall and the Level 1 convoy.

## Spec Change Log

- 2026-10-14, operator request mid-implementation: add a scrolling three-layer starfield (Chicken Invaders style) to every background. Pale blue-white and sparse; the far and mid layers stay below the glow threshold, and the near layer (brightness 0.6) may bloom very faintly, as the operator brief allowed. Numbers live in `render.starfield`.
- 2026-10-14, review: patches applied.
  - The end screen waits `epilogue_music_delay_s` before starting the track, so the boss fade-out is never cut.
  - `music_gain_db` is optional and type-safe.
  - A chain row with a pitch of 0 or less, or an empty sfx, falls back to the tier sound.
  - The orb pitch has a floor, and the chain anim speed has a floor of `Explosion.MIN_SPEED`.
  - The planet runs on a game-time clock instead of `TIME` (it freezes on pause and never rolls over).
  - The Level Select thumbnails hold the stars and the planet still.
  - The chain tests check each row's pitch.
  - Stale docs are fixed (CREDITS shield ring, spawner params, background comments, architecture as-built F).

## Suggested Review Order

**Backdrop**

- The children are built in `_init`; `apply()` toggles the planet and the stars.
  [`level_background.gd:127`](../../game/scenes/level/level_background.gd#L127)
- Game-time clocks, so both freeze on pause; the thumbnails hold still.
  [`level_background.gd:209`](../../game/scenes/level/level_background.gd#L209)
- Sphere shading, bands, city lights and the atmosphere rim.
  [`throne_world.gdshader:60`](../../game/scenes/level/throne_world.gdshader#L60)
- Hash-based three-layer starfield with a seamless wrap.
  [`starfield.gdshader:65`](../../game/scenes/level/starfield.gdshader#L65)
- The epilogue shows the throne world.
  [`story.gd:61`](../../game/scenes/story/story.gd#L61)

**Tarek and the convoy**

- HOLD replaces SHIELD: same timeline, no ring.
  [`ally_ship.gd:152`](../../game/entities/allies/ally_ship.gd#L152)
- The convoy hull is re-imported at value 0.9 so it blooms.
  [`import_cc0_art.py:160`](../../tools/import_cc0_art.py#L160)

**Portraits (operator art, same session)**

- PNG portraits replace the SVGs.
  [`comms_portraits.gd:13`](../../game/systems/comms/comms_portraits.gd#L13)
- They are sampled through mipmaps at 200 and 88 px.
  [`comms_panel.gd:116`](../../game/systems/comms/comms_panel.gd#L116)
