---
title: DESIGN.md - DEFECTOR
status: final
created: 2026-10-06
updated: 2026-10-07
sources:
  - ../../gdds/gdd-game-project-2026-10-06/gdd.md
  - ../../../game-architecture.md
  - ../../epics.md
  - ../../implementation-readiness-report-2026-10-06.md
colors:
  background: '#05070F'
  surfaceAlt: 'rgba(10,18,34,0.85)'
  surfaceSolid: '#0A1222'
  border: '#2A3B5C'
  text: '#E8F4FF'
  muted: '#93A7C2'
  coalition: '#22E6FF'
  enemy: '#FF2BD6'
  energy: '#FFD23F'
  hazard: '#7A6E62'
  hazardRim: '#C9D8E8'
  heart: '#FF4766'
  heartEmpty: '#2B3348'
  danger: '#FF1F4B'
  isolde: '#FF6AE3'
  tarek: '#3DF2FF'
  ryn: '#7CFFB2'
  vale: '#E8F4FF'
  system: '#93A7C2'
  dim: 'rgba(0,0,0,0.6)'
typography:
  font: 'Kenney Future (CC0, from the Kenney packs); Kenney Future Narrow for long comms text if needed'
  scale: 'at 1080p: hud-label 20px, body 28px, comms 28px (story panel) / 22px (interruption box), name 30px (story panel) / 24px (interruption box), heading 48px, title 120px'
  weights: 'single weight (the font has one); hierarchy via size, colour and glow'
  case: 'UPPERCASE for labels, buttons and names; sentence case for dialogue'
rounded: '4px panels, 2px bars; buttons 4px'
spacing: '8px grid; 32px screen-edge safe margin at 1920x1080'
components:
  interruptBox: 'surfaceAlt fill, 1px border, speaker-accent left edge 4px, 72px portrait, 24px name + up to 2 lines of 22px text, 25px line height, autowrap + clip'
  storyPanel: 'surfaceAlt fill, 1px border, 200px portrait, name in speaker accent, typewriter text, "click to continue" cue in muted'
  waveBar: 'segmented, segment fill coalition, empty segments heartEmpty with border, 4px gaps'
  bossBar: 'single bar, enemy fill, 2 vertical markers in text colour (turret/core boundary, 50 core HP)'
  hearts: '5 heart icons; filled = heart, empty = muted outline'
  energyBar: 'energy fill on heartEmpty track, tick marks at 50% and 100% in text colour'
  convoyBar: 'coalition fill, "CONVOY" label in muted, thinner than energy bar'
  hint: 'pill, surfaceAlt fill, text colour, key glyph in energy colour'
  missileRing: 'cooldown arc drawn over the ship, radius ≤ ship half-size (first pass 36px), 5px stroke in text with a 2px background outline, sweeps clockwise from 12 o''clock, hidden when ready'
  button: 'surfaceAlt fill, 1px border; hover/focus: coalition border + glow; danger variant not used'
  vignette: 'danger edge gradient, max alpha 0.5'
---

# DESIGN.md - DEFECTOR (2D neon space shooter, Windows PC)

## Brand & Style

The look is clean neon and vector graphics on deep space, in the spirit of Chicken Invaders Universe but serious in tone. Everything that matters glows, and everything else stays dark. The UI is a set of thin, translucent tactical panels that never compete with the playfield. The register is "Cold Neon": icy, crisp and high-voltage. Built on Godot `Control` nodes with one shared `Theme` (`ui/theme/defector_theme.tres`). These tokens define that Theme.

## Colors

| Role | Token | Hex | Use |
|---|---|---|---|
| Background | `background` | `#05070F` | Space backdrop base, menu backdrops |
| Panel | `surfaceAlt` | `rgba(10,18,34,0.85)` | Every HUD panel, comms box, menus |
| Border | `border` | `#2A3B5C` | 1px panel and button borders |
| Text | `text` | `#E8F4FF` | All body text and dialogue (17:1 on panel) |
| Muted | `muted` | `#93A7C2` | Labels, cues, empty-heart outline (7.7:1) |
| Coalition | `coalition` | `#22E6FF` | Player, allies, convoy, wave-bar fill, focus |
| Enemy | `enemy` | `#FF2BD6` | Sovereignty ships, **all** enemy projectiles, boss bar |
| Energy | `energy` | `#FFD23F` | Orbs, energy bar, key glyphs in hints |
| Hazard | `hazard` / `hazardRim` | `#7A6E62` / `#C9D8E8` | Asteroids and their rim light |
| Heart | `heart` / `heartEmpty` | `#FF4766` / `#2B3348` | Hearts; empty hearts are a `muted` outline |
| Danger | `danger` | `#FF1F4B` | Hit vignette, "denied" flash, loss-reason headline |
| Speakers | `isolde` / `tarek` / `ryn` / `vale` / `system` | `#FF6AE3` / `#3DF2FF` / `#7CFFB2` / `#E8F4FF` / `#93A7C2` | Speaker name and portrait-frame accent. Vale and system have no portrait (no-portrait panel variant) |
| Dim | `dim` | `rgba(0,0,0,0.6)` | Over the playfield whenever the game is paused |

Contrast was checked against the panel colour composited on the background (`#09101F`). All text roles score 5:1 or better. `heartEmpty` (1.5:1) is never used alone; empty hearts are outlined in `muted`.

## Typography

- **Font:** Kenney Future (CC0, ships with the Kenney packs). Credit it in `CREDITS.md`.
- **Sizes at 1080p:** HUD labels 20px · body/hints 28px · comms text 28px (interruption box 22px) · speaker name 30px (interruption box 24px) · menu headings 48px · title logo 120px. Nothing below 20px. [ASSUMPTION: sizes; tune once the font is in-engine]
- Labels, buttons and speaker names are UPPERCASE. Dialogue uses sentence case.

## Layout & Spacing

The fixed 1920×1080 canvas is letterboxed to 16:9. There's a 32px safe margin on every edge and spacing follows an 8px grid.

| Zone | Rect (x, y, w, h) | Contents |
|---|---|---|
| **Top HUD band** | 0, 0, 1920, 120 | All persistent HUD. Nothing taller than this band |
| Interruption box | 32, 24, 560, 96 | Top-left; mid-fight one-liners only. Name 24px, text 22px; text auto-wraps to at most 2 lines and clips beyond the box, **≤ 50 characters per line of dialogue** (enforced by the data test). Ends at x 592, leaving an 88px gap before the wave bar |
| Wave / boss bar | centred, y 40, w 560 (x 680–1240; boss also 560, h 20) | Top-centre. Both bars keep ≥ 88px clear of the interruption box |
| Player meters | right-aligned at x 1888, y 24 → 112 | Hearts (5 × 40px, 8px gap), energy bar 320×16 at y 76, convoy bar 320×12 at y 104 (Level 1 only) |
| Enemy zone | y 120 → 432 | Nothing persistent drawn here |
| Hint line | centred at y 560 | Control hints, between the enemy and player zones |
| Player zone | y 432 → 1080 | **No persistent HUD.** The only exceptions are the temporary hint pill and the paused overlays (story panel, Final Choice, retry, menus), which appear over a dim. Allies y 620–760, convoy y 760–920 |
| Story panel (paused) | 410, 300, 1100, 300 | Over `dim`. 32px padding, portrait on the left, text block 812px wide, cue 20px bottom-right |
| Final Choice buttons | centred pair, 480 × 120 each, 48px gap, top at y 680 | 80px below the story panel |
| Retry prompt | headline top at y 440 (48px, `danger`); buttons 320 × 80, 48px gap, top at y 560 | No panel, just dim + text + buttons |
| Hint pill | centred at y 560, 52px tall, 24px horizontal padding, fully rounded | One pill at a time |
| Story panel text | max 4 lines at 28px in the 812px block, **≤ 200 characters per line of dialogue** (data test); autowrap, clip | No-portrait variant (Vale, system): the text block spans the full 1036px |
| Shield bubble | 120px circle centred on the ship | `coalition` ring at 40% alpha; blinks at 4 Hz for the last 0.75 s |
| Title screen | logo centred at y 300 (120px, `coalition` glow); buttons 400 × 72 stacked, 24px gap, first top at y 560 | PLAY · LEVEL SELECT · QUIT on `background` + space backdrop; config-error label in `danger` replaces the buttons if `tuning.json` failed |
| Level Select | three cards 480 × 280, 48px gap, centred row, top at y 360; BACK button 240 × 64 at (32, 984) | Card: level number, name, small background thumbnail; locked = 40% opacity + `LOCKED` label, not clickable |
| Pause menu | centred panel 520 wide, `PAUSED` heading 48px, buttons 400 × 72, 24px gap | Over `dim`; only one dim layer ever shows, never stacked |
| End screen | `DEFECTOR` 120px at y 320, closing line 30px at y 480, `Thanks for playing` 28px `muted` at y 560, BACK TO TITLE 400 × 72 at y 700 | On `background` + throne-world backdrop |

[ASSUMPTION: every pixel value in this table is a first-pass layout, tunable like gameplay values]

## Asset Direction

- **Sources (CC0):** Kenney **Space Shooter Redux** and **Space Shooter Extension** for ships, lasers, missiles and meteors; Kenney Sci-fi Sounds for SFX; Kenney Future font. Every asset is listed in `game/assets/CREDITS.md`.
- **Ships must read as spaceships:** the player and allies are fighter hulls recoloured `coalition`; enemies are Sovereignty hulls recoloured `enemy`. Wasp, Lancer, Needle, Bastion and Maul must have distinct silhouettes.
- **Convoy:** three medium cargo hulls (~160×80 px, from the extension pack's larger ship parts or a freighter sprite) in a tight triangle, recoloured `coalition` with a dimmer body so they read as civilian cargo, not fighters.
- **Asteroids:** jagged, cratered meteor sprites (Kenney meteors, brown/grey variants) tinted toward `hazard` with a `hazardRim` rim light. **Never smooth or round.**
- **Projectiles:** laser-bolt sprites (elongated, bright core) with an additive glow; enemy bullets are round or diamond with a bright core in `enemy`.
- The HTML mock uses CSS shapes as stand-ins. Real sprites replace them in-engine.

## Elevation & Depth

There are three CanvasLayers, as in the architecture: HUD (10) < Comms (20) < Overlay (30). Depth comes from glow, not shadows. Live elements (bars filling, active hint) get a soft outer glow in their colour; panels have none. `dim` sits between the playfield and any paused UI.

## Shapes

Panels have 4px corners, bars 2px, buttons 4px. Hearts are icons, not shapes. The missile cooldown ring is a circular arc over the ship that sweeps clockwise from 12 o'clock.

## Components

- **Interruption box:** panel with a 4px left edge in the speaker's accent, a 72px portrait, the uppercase 24px name, and at most 2 lines of 22px text at 25px line height, starting 6px below the name's baseline (one short line of dialogue, ≤ 50 characters). Godot `Label` with autowrap on and clip on, so text can never overflow into the wave bar.
- **Story panel:** large panel with a 200px portrait on the left, the name in the speaker accent, typewriter text, and a `click to continue ▸` cue bottom-right in `muted`. It has no buttons, so it can't be mistaken for a menu.
- **Wave bar:** N segments with 4px gaps. Full segments are `coalition`, the current one fills partially, and empty ones are a `heartEmpty` track with a `border` outline.
- **Boss bar:** same slot, `enemy` fill showing combined remaining HP (300 = 4 turrets × 25 + core 200), draining right to left. Two `text`-coloured markers measured from the left: at 66.7% (turrets gone) and at 16.7% (core at 50 = Final Choice). Labelled `FLAGSHIP` in `muted`, centred below the bar at y 68.
- **Hearts / energy / convoy:** see Layout. The energy bar has tick marks at 50 (Shield) and 100 (Barrage). The convoy bar is labelled `CONVOY` in `muted` 20px, right-aligned immediately to the left of the bar.
- **Hint pill:** panel pill with the key in `energy` and the action in `text`, e.g. `[RMB] MISSILE`.
- **Missile cooldown ring:** drawn on top of the ship (the ship is the cursor; there is no reticle, decision #29/#31). No bigger than the ship, in high-contrast `text` with a dark `background` outline, so it reads over the cyan hull and over explosions. Visible only while the missile reloads.
- **Buttons:** panel fill with a 1px border; hover shows a `coalition` border and glow.
- **Ships:** allies and convoy use `coalition` in-world. Speaker accents (`tarek`, `ryn`, `isolde`) are used only in comms UI.
- **Shield bubble:** `coalition` ring around the ship at 40% alpha.
- **Hit vignette:** screen-edge gradient in `danger`.

Key-screen mock: [HUD at a glance](mockups/key-hud.html). Its convoy geometry predates decision #19; the spine wins.

## Do's and Don'ts

- **Do** keep the player zone (below y 432) free of HUD.
- **Do** use `enemy` for every hostile projectile, with no exceptions.
- **Do** dim the playfield whenever the game is paused, for any reason.
- **Don't** put buttons on the story panel.
- **Don't** use colour alone to carry meaning: hearts are counted icons, and the convoy bar has a label.
- **Don't** set per-node style overrides. Everything goes through the Theme, except the comms portrait frame (architecture rule).
