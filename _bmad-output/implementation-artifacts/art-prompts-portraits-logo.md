# DEFECTOR: image-generation prompts for portraits and logo

Paste the **shared style block** first, then one character block. Generate each character in the same session or tool, so the four images match.

## What to bring back, and where to put it

| Asset | File name | Size | Notes |
|---|---|---|---|
| Isolde portrait | `game/assets/portraits/portrait_isolde.png` | 1024 x 1024 PNG | square, head and shoulders, no text, no frame |
| Tarek portrait | `game/assets/portraits/portrait_tarek.png` | 1024 x 1024 PNG | same |
| Ryn portrait | `game/assets/portraits/portrait_ryn.png` | 1024 x 1024 PNG | same |
| Vale portrait (optional) | `game/assets/portraits/portrait_vale.png` | 1024 x 1024 PNG | Vale has no portrait today; say if you want one shown |
| Logo | `docs/defector_logo.png` | about 2048 x 640, transparent PNG | wordmark or emblem, see below (not used in game) |

- **Keep the old SVGs.** I'll switch the game over to the PNGs and remove the SVGs in the same change.
- **Don't add a frame or border.** The game draws its own frame in each speaker's colour.
- **The portraits show small in game:** 200 px in the story panel and 88 px in the combat comms box. Keep faces large and simple, with strong silhouettes. Fine detail will be lost.
- **Still images only:** the portraits drop straight in, with no animation (operator's choice, 2026-10-14).
- **Licence:** the images become project art and get a row in `CREDITS.md` naming the tool you used. Check that your tool's terms let you publish the images in a free game on a public GitHub repo.

---

## Shared style block (paste first, every time)

> Character portrait for a 2D neon sci-fi space shooter called DEFECTOR. Style: clean stylised digital illustration, semi-realistic graphic-novel faces, bold readable shapes, crisp lines, cinematic rim lighting. "Cold neon" mood: icy, crisp, high-voltage. Everything important glows; everything else falls into deep shadow. Depth comes from glow, not from soft shadows. Background: near-black navy (#0A1222) fading to black (#05070F) at the edges, with a faint holographic comms-screen feel (very subtle horizontal scanlines and a soft vignette). Framing: head and shoulders, centred, facing the viewer or three-quarter view, eyes at about 40% from the top, square 1:1 composition, the face filling most of the frame so it reads at 88 pixels. Lighting: one strong neon rim light in the character's signature colour (given below), plus a cool low-intensity key light; skin and clothing stay mostly dark and desaturated, so the signature colour pops. No text, no logos, no UI, no frame, no border, no watermark.

**The story, for context (paste it as well if your tool accepts long prompts):**

> Setting: a galactic civil war. The Sovereignty, an elegant, authoritarian empire ruled from a throne world, fights the Free Worlds Coalition, a scrappy alliance of independent planets. Its general, Arden Vale, has just defected to the Coalition. Every enemy fleet Vale now faces belongs to the ruler Vale used to serve. The Coalition's colours are icy cyan and teal; the Sovereignty's are hot magenta and crimson.

---

## Sovereign Isolde Varn (antagonist): signature colour magenta-pink #FF6AE3

> Sovereign Isolde Varn, absolute ruler of the Sovereignty and the player's former sovereign. A woman in her forties with a regal, severe beauty: high cheekbones, sharp jawline, a cold half-smile, and eyes that look down at the viewer with amused contempt. She is condescending and manipulative, a ruler who offers mercy with one hand and an execution order with the other. Dark hair swept back tightly under a slim, angular, futuristic crown of dark metal edged with glowing magenta-pink light. A tall, rigid high collar of black lacquered armour-silk with thin magenta circuitry lines rises behind her neck like a throne back. Small details: a single crimson gem at the collar clasp; a faint reflection of a fleet in her eyes. Rim light in magenta-pink (#FF6AE3), with accents of deep crimson. Expression: calm, superior, faintly amused, as if saying "Come home, General."

## Admiral Tarek Holt (mentor): signature colour cyan #3DF2FF

> Admiral Tarek Holt of the Free Worlds Coalition, the player's mentor. A weathered veteran in his late fifties, originally from another world, with a dignified, slightly unusual alien-human look: a strong brow, warm but tired deep-set eyes, and short greying hair. A full, neatly trimmed grey-and-white beard. Kind, steady, fatherly authority; a commander who has seen too many wars and still believes in this one. He wears a worn Coalition pilot's flight jacket with a raised padded collar, admiral's insignia in small glowing cyan bars, scuffed shoulder plating and a comms headset over one ear. Rim light in cyan (#3DF2FF), with teal accents. Expression: a reassuring half-smile, the look of a mentor briefing a trusted friend before a dangerous mission.

## Commander Ryn Holt (Tarek's daughter, finale ally): signature colour mint green #7CFFB2

> Commander Ryn Holt of the Free Worlds Coalition, Admiral Tarek Holt's daughter. A woman in her late twenties with a sharp, determined face, a resemblance to her father in the brow and eyes, and short, practical cropped hair, slightly tousled. She has just taken command after her father was gravely wounded protecting the general: grief held behind a steely, focused expression, jaw set, eyes intense. She wears a fitted Coalition flight suit with a high, zipped collar, a pilot's harness strap across one shoulder, a small mint-green squadron patch, and a slim helmet-mounted comms mic. Rim light in mint green (#7CFFB2), with cool cyan fill. Expression: resolute and focused, ready to lead the final assault on the throne world.

## General Arden Vale (the player, optional): signature colour pale ice #E8F4FF

> General Arden Vale, a decorated general who defected from the Sovereignty to the Free Worlds Coalition. Gender-neutral and androgynous: no clearly male or female features. Short dark hair, a lean face with a thin scar across one eyebrow, and calm, guarded eyes. A former Sovereignty general's uniform with the magenta insignia torn off, leaving dark outlines where the badges were, now worn under a Coalition cyan pilot's collar. Rim light in pale icy white (#E8F4FF), with a faint cyan edge. Expression: quiet resolve, haunted but certain.

---

## Logo (README, GitHub release page, optionally the app icon)

The in-game title stays the glowing DEFECTOR text (operator's choice, 2026-10-14). The logo is for the README and the release page, and the emblem can replace the app icon if you like it. Image tools often misspell text: **Option A** asks for an emblem only, and the README pairs it with the word; **Option B** asks for the full wordmark, so check the spelling letter by letter.

**Option A: emblem only (recommended)**

> Game logo emblem for DEFECTOR, a neon 2D space shooter about a general who defects from an authoritarian empire. Symbol: a sleek arrow-shaped delta starfighter in glowing cyan (#22E6FF) breaking away from, and turning against, a tight V-formation of angular magenta (#FF2BD6) enemy ships, which it leaves behind. A clean vector style with bold flat shapes and crisp neon outlines that glow softly. It must stay readable at 64 pixels. Transparent background, no text, no letters, centred, wide 3:1 composition.

**Option B: full wordmark**

> Game logo wordmark reading exactly "DEFECTOR" (D-E-F-E-C-T-O-R) in a wide, geometric, futuristic sans-serif typeface, all capitals, letters glowing neon cyan (#22E6FF) with a thin white-hot core and a soft outer glow. The letter "O" is replaced by a small cyan delta starfighter, or a slash cuts through the word, hinting at defection; one thin magenta (#FF2BD6) accent line runs under the word. A clean vector style with flat shapes, no 3D bevel, no chrome, no grunge. Transparent background, wide 3:1 composition.

---

## Optional: the throne world as a painted image

The game now draws the throne-world planet in code. If you'd rather have a painted one, here is a prompt:

> The lower half of a huge, dark, regal planet seen from below, filling the top of a wide 16:9 frame: the Sovereignty's throne world. Deep violet and indigo surface with swirling cloud bands, thin glowing city lights on the night side forming geometric patterns, and a thin violet atmosphere glow along the edge. Dark, moody and not too bright: it sits behind gameplay. Black space below it with faint stars. Clean digital illustration, no text. 3840 x 1080, PNG.

Put it at `game/assets/backgrounds/throne_world_planet.png` and tell me, and I'll use it instead.
