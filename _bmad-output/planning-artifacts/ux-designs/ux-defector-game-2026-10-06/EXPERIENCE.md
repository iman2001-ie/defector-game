---
title: EXPERIENCE.md - DEFECTOR
status: final
created: 2026-10-06
updated: 2026-10-06
form_factor: Windows PC, mouse + keyboard, desk
sources:
  - ../../gdds/gdd-game-project-2026-10-06/gdd.md
  - ../../../game-architecture.md
  - ../../epics.md
  - ../../implementation-readiness-report-2026-10-06.md
---

# EXPERIENCE.md - DEFECTOR

## Foundation

DEFECTOR is a Windows PC game played at a desk with mouse and keyboard, in a single sitting of 10–15 minutes. The UI is built from Godot 4.7 `Control` nodes under three CanvasLayers (HUD 10, Comms 20, Overlay 30) with one shared Theme. Pausing is owned by `PauseArbiter`, and the HUD reads state only through `Events`. Visual identity: [DESIGN.md](DESIGN.md). This file specifies behaviour only.

## Information Architecture

- **Boot → Title:** `DEFECTOR` logo, then PLAY · LEVEL SELECT · QUIT.
  - **Play** continues at the highest unlocked level.
  - **Level Select:** three level cards by name; locked cards are greyed and can't be clicked. BACK returns to the title.
- **Story scene:** the opening sequence plays before Level 1 on a fresh start only.
- **Level:** briefing (paused) → waves → debrief (paused) → next level. **On retry or restart, the briefing is skipped** and the level starts at wave 1 straight away (same rule as the opening).
  - **Pause (Esc):** RESUME · RESTART LEVEL · QUIT TO TITLE.
  - **Retry prompt** (after death or convoy loss): loss reason, then RETRY · QUIT TO TITLE.
- **End screen** (after Level 3): title, one closing line, "Thanks for playing", BACK TO TITLE.

Nothing is more than two clicks from the title screen.

**HUD information hierarchy** (most-glanced first):
1. Hearts (top-right)
2. The missile cooldown ring (on the ship)
3. Energy (top-right)
4. Wave or boss progress (top-centre)
5. Convoy (top-right, Level 1 only)

Interruptions (top-left) and hints (centre-low) appear only when needed.

## Dialogue Model

This is the core UX rule, from GDD decision #22.

| Kind | When | Game paused? | Where | Advances |
|---|---|---|---|---|
| **Briefing / debrief** | Level start / level end; also the opening | Yes, with dim | Centred story panel | Click anywhere |
| **Big mid-fight moment** | L1 surrender offer, L3 Final Choice lead-in (only these two) | Yes, with dim | Centred story panel | Click anywhere |
| **Interruption** | At most 2 per level: Isolde mocks or an ally warns; Tarek's cut-off | No | Top-left box | Auto-dismisses |
| **Control hint** | First time each control matters (Level 1) | No | Centre-low pill | Fades on use or after 5 s |

The player learns one rule: **a centred panel with a dimmed screen means read this and click; a small box in the corner means glance at it if you like.**

## Voice and Tone

- **Microcopy is terse, military and uppercase:** `HULL DESTROYED`, `CONVOY LOST`, `PAUSED`, `RETRY`, `QUIT TO TITLE`, `click to continue ▸` (that cue stays lowercase so it reads as quiet).
- **Hints are key plus verb:** `[HOLD LMB] FIRE`, `[RMB] MISSILE`, `[E] SHIELD`, `[Q] BARRAGE`. Move is shown as `MOVE THE MOUSE TO FLY`.
- Dialogue voice belongs to the characters (GDD cast rules). The UI itself never jokes.

## Component Patterns

| Component | Behaviour |
|---|---|
| Story panel | Opens with the comms-open SFX and types at 45 chars/s. A click completes the current line; the next click advances. The click is consumed so it never fires the laser. Esc opens the pause menu on top; closing the menu returns to the story pause |
| Interruption box | Types out at 45 chars/s like the story panel (so a cut-off can stop mid-word). One short line (≤ 50 chars), auto-wrapping to at most 2 lines at 24px and clipped to the box. Slides in from the left over 0.15 s and stays for `max(2.0, chars/45 + 1.2)` s, then fades. Click-through (it ignores the mouse). Story lines preempt it. At most 3 queued |
| Cut-off | The text stops mid-word, a static burst plays, the box hides after 0.6 s, and further interruptions are silenced until the wave clears |
| Control hint | Fades in over 0.2 s. Fades out once the action is performed or after 5 s. Each hint shows once per session; retries don't repeat it | Move and fire are two hints shown in sequence: `MOVE THE MOUSE TO FLY` (dismissed after 150 px of movement), then `[HOLD LMB] FIRE` (dismissed on first shot). Only one pill shows at a time; a newer hint waits for the current one to fade
| Missile cooldown ring | Appears full when the missile fires and empties clockwise over 1.5 s; hidden when ready. Freezes with the game while paused |
| Wave bar | Fills smoothly (0.2 s tween) and never goes backwards within an attempt |
| Boss bar | Replaces the wave bar with a 0.3 s cross-fade when the Flagship arrives |
| Energy bar | Fills on pickup. If E/Q is pressed without enough energy, the bar flashes `danger` twice over 0.3 s and the "denied" SFX plays |
| Hearts | On a hit, the lost heart pops (scale 1.3 → 1, 0.15 s) and turns into an outline |
| Convoy bar | On damage, the bar flashes `danger` once. Below 30%, the label pulses |
| Final Choice | Two large buttons appear after Isolde's lead-in finishes. While they're up, the `click to continue` cue is hidden and clicking outside the buttons does nothing. No timer; Esc is disabled; hover shows a coalition glow |
| Buttons / menus | Mouse only: hover to highlight, click to activate. Esc closes the pause menu (= RESUME) |

## State Patterns

| State | HUD | Cursor | Dim | Notes |
|---|---|---|---|---|
| Playing | Visible | Hidden, locked to the ship | No | |
| Story pause | Visible, frozen | Visible arrow | Yes | Centred story panel |
| Opening story scene | None (no level loaded) | Visible arrow | No dim, static space backdrop | Centred story panel; Esc does nothing; ends by loading Level 1 |
| Final Choice | Visible, frozen | Visible arrow | Yes | Buttons below the panel |
| Paused (menu) | Visible, frozen | Visible arrow | Yes | Centred menu panel `PAUSED` |
| Death / convoy lost | Visible, frozen | Visible arrow | Yes | After the 1.5 s death beat: the loss reason in `danger`, then RETRY · QUIT TO TITLE. Esc disabled |
| Between waves (2.0 s) | Visible | Hidden, locked to the ship | No | The next wave segment highlights |
| Level clear | Wave bar full | Visible arrow | Yes | Debrief story panel, then the next level loads |

## Interaction Primitives

- **Click anywhere** advances paused dialogue.
- **Hover + click** for every button. There's no keyboard menu navigation (mouse-only scope).
- **Esc** toggles the pause menu, except during death or the Final Choice.
- **F11** toggles fullscreen/windowed anywhere.

## HUD & Diegetic UI

Everything is a non-diegetic overlay, except the shield bubble, the missile cooldown ring, the Needle's targeting line and the telegraph glows, which are drawn in-world. The HUD is confined to the top 120px band, and the player zone (below y 432) never has HUD on it. Hints sit on the boundary at y 560 and are temporary.

## Input Schemes

Mouse + keyboard only: the mouse moves, LMB fires, RMB fires a missile, E is Shield, Q is Barrage, Esc pauses, F11 toggles fullscreen. There's no remapping and no gamepad (GDD out of scope). Hint glyphs are fixed text, so no platform adaptation is needed.

## Game Feel & Juice

Feel comes from the GDD size-scaled feedback table. The UI-specific additions are:
- the hit vignette (0.3 s, max alpha 0.5)
- the heart pop
- the energy-denied flash
- the convoy-damage flash
- the wave-segment highlight between waves

UI motion never exceeds 0.3 s, and the HUD freezes with the game (`PROCESS_MODE_PAUSABLE`).

## Accessibility Floor

- No text smaller than 20px at 1080p. Paused dialogue is 30px; interruptions are 24px.
- All text meets 4.5:1 contrast on panels (verified in DESIGN.md).
- No information is carried by colour alone: hearts are counted icons, the convoy bar is labelled, and the loss reason is in words.
- Paused dialogue waits for the player indefinitely, with no timed reading. Interruptions are optional flavour or warnings, and missing one never blocks progress.
- **Photosensitivity:** the 10 Hz i-frame flicker affects only the small player sprite. The boss-death white flash happens once, so no full-screen flashing repeats. [ASSUMPTION: an acceptable floor for a hackathon build; there is no reduce-flash option]

## Key Flows

[ASSUMPTION: these protagonist journeys were drafted by the facilitator; replace them with a real playtester's session if you like]

**Flow 1: Sam's first run (a hackathon colleague, never played it before)**
1. Sam launches the zip, gets the title screen, and clicks PLAY.
2. The opening plays in centred panels. Sam clicks through and learns who Vale, Tarek and Isolde are.
3. Level 1 begins. [Example lines below are placeholders until Story 5.7 writes the script.] `MOVE THE MOUSE TO FLY` and `[HOLD LMB] FIRE` appear centre-low, Sam does both, and the hints fade.
4. In W2, `[RMB] MISSILE` appears and Sam slides out from behind an asteroid and fires one up into the formation.
5. W3: Tarek warns of the ambush (top-left), and Mauls dive at the convoy. The CONVOY bar flashes as it takes a hit.
6. Sam reaches 50 energy, and `[E] SHIELD` appears.
7. **Climax:** in W5 the screen dims and Isolde's centred panel says "You're outnumbered, General. Come home." Sam clicks, the Mauls pour in, and Sam clears the wave.
8. The debrief plays, and Level 2 loads.

**Flow 2: Sam loses the convoy**
1. In L1 W4, Sam focuses on Lancers and the convoy bar drains.
2. The game freezes and dims, and the screen shows `CONVOY LOST` with RETRY · QUIT TO TITLE.
3. **Climax:** Sam now knows the convoy is a loss condition, clicks RETRY, and is back at wave 1 within a second, with no briefing replay.

**Flow 3: The Final Choice**
1. In Level 3, the boss bar's core marker drops to 50.
2. **Climax:** the screen dims, Isolde speaks in the centred panel, and two buttons appear: OFFER SURRENDER and DESTROY HER. Sam hovers over each and picks one.
3. Vale's line plays, then Isolde's refusal. The panel closes, the desperate barrage starts, and the Flagship dies. Isolde's final line plays, then the end screen.

## Responsive & Platform

There is one target: 1920×1080 letterboxed to 16:9, borderless fullscreen by default, with windowed mode via F11. All HUD coordinates are on the 1920×1080 canvas and scale with it (stretch `canvas_items`, aspect `keep`).

Visual reference: [HUD at a glance](mockups/key-hud.html) (its convoy geometry predates decision #19). If the spines and a mock disagree, the spines win.
