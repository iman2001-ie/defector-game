---
title: 'Epic 7 playtest H: Barrage missile exhaust and smoother flight, and the wordmark logo on the title and end screens'
type: 'feature'
created: '2026-10-14'
status: 'done'
baseline_commit: '9fb17f2'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:**
- Barrage micro-missiles have no exhaust (no fire or smoke).
- Their flight looks slightly mechanical: a constant-rate turn with the rotation snapped to the velocity every frame, and a straight-up launch followed by a hard bend.
- The new DEFECTOR wordmark appears only in the README, while the title and end screens show plain text.

**Approach:**
- **Exhaust:** each micro-missile gets a small jet trail. A short hot core (energy gold fading to danger red) turns into faint grey smoke, built like the Missile's `SmokeTrail` but smaller.
- **Flight:**
  - Steering eases in: the turn rate builds up over a short time, so the path curves smoothly instead of snapping.
  - The sprite's rotation follows the heading smoothly.
  - Launches fan out slightly left and right of straight up.
  - The speed and the homing idea stay as they are.
- **Logo:** the title and end screens show the wordmark PNG instead of the Label text, centred where the text was, at a tuned width.

## Boundaries & Constraints

**Always:**
- The tuning numbers (trail amount and lifetime, the turn ease, the fan angle, the logo width) live in `tuning.json`.
- The barrage damage, speed, count and duration stay unchanged.
- On a failed config, the authored `.tscn` layout still shows the logo, centred.

**Ask First:** none. The operator asked for these on 2026-10-14.

**Never:**
- Change the app icon. The wordmark is 3:1; a square icon comes later from the operator.
- Change the regular Missile.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior |
|---|---|---|
| Barrage volley | Q with full energy | 12 missiles fan out and curve smoothly onto targets, each trailing exhaust |
| No target | no enemies left | the missile eases to straight up, as now |
| Missile freed | lifetime ends or it hits | the trail goes with it (the trail is local to the missile, so no orphan particles) |
| Title or end screen | healthy config | the logo is centred on `logo_y` at `logo_width_px` |
| Failed config | load_error set | the authored logo rect shows |

</frozen-after-approval>

## Code Map

- `game/entities/projectiles/micro_missile.gd` + `.tscn` -- `steer`, `_orient`, `_physics_process`; no trail yet
- `game/entities/projectiles/missile.tscn` -- the `SmokeTrail` reference setup
- `game/entities/player/player_weapons.gd:227-240` -- `_launch_micro` (the launch velocity)
- `game/scenes/title/title.gd` + `.tscn`, `game/scenes/end/end_screen.gd` + `.tscn` -- the `Logo` Label and its layout and glow
- `game/tests/unit/test_title.gd`, `test_end_screen.gd`, `test_micro_missile.gd`, `tests/data/test_data_files.gd`
- `docs/defector_logo.png` -- the source for `game/assets/logo/defector_logo.png`

## Tasks & Acceptance

**Execution:**
- [x] micro-missile: the trail node; smooth steering and rotation; the fan launch
- [x] title and end screen: a TextureRect logo from `ui.title.logo_width_px` and `ui.end_screen.logo_width_px`; import with mipmaps
- [x] tuning, tests and the data shape
- [x] docs: a decision-log row, CREDITS (the logo row is AI-generated and project-owned), the architecture as-built

**Acceptance Criteria:**
- Given the full suite on the staged tuning, when GUT runs, then everything passes.

## Verification

**Commands:**
- import, then the full GUT run

## Spec Change Log

- 2026-10-14, review: patches applied.
  - `rotation_smoothing` 18 -> 60. At 18 the nose and hitbox lagged about 30° behind a hard turn.
  - The scenes' authored logo texture_filter is 4 (LINEAR_WITH_MIPMAPS).
  - Decision #74 records that it amends #72.
  - The logo source is the operator's 2048 x 640 export (gitignored), cropped to 1536 x 284. `docs/defector_logo.png` is the README copy.

## Suggested Review Order

**Barrage**

- The eased turn rate after launch replaces the instant max-rate turn.
  [`micro_missile.gd:13`](../../game/entities/projectiles/micro_missile.gd#L13)
- The nose follows the heading exponentially (60/s).
  [`micro_missile.gd:90`](../../game/entities/projectiles/micro_missile.gd#L90)
- The deterministic left/right launch fan.
  [`player_weapons.gd:236`](../../game/entities/player/player_weapons.gd#L236)
- The exhaust particles.
  [`micro_missile.tscn:47`](../../game/entities/projectiles/micro_missile.tscn#L47)

**Logo**

- Shared logo layout for the title and end screens.
  [`title.gd:105`](../../game/scenes/title/title.gd#L105)
