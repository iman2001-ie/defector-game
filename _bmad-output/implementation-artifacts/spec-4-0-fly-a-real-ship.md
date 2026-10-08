---
title: 'Story 4.0: Fly a Real Ship'
type: 'feature'
created: '2026-10-08'
baseline_revision: '55442a7af6b901c3a17f1806973a15cdf9a6156c'
status: done
operator_actions:
  - 'Play the dev level with glow on and confirm the ship reads at a glance as a cyan/teal fighter pointing up, distinct from enemies and pickups.'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-4-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The player ship is still the Story 1.2 placeholder, a 96 px radial `GradientTexture2D` glow circle, so you can't see where the hull is or which way the nose points. This covers FR64 (partial: the player ship) and NFR10, from GDD decision #37 (pulled forward from Story 8.2). Tier: SHOULD.

**Approach:** Bake a `coalition`-recoloured copy of Kenney Space Shooter Redux `playerShip1_blue.png` (CC0) into `game/assets/sprites/player/`, using a reproducible stdlib-only tool. Make it the `Player/Sprite` texture. In `_ready`, scale it uniformly so its longer side equals `player.sprite_px`, and put the `Muzzle` on the nose. Then update the tests, `CREDITS.md` and the architecture as-built notes.

## Boundaries & Constraints

**Always:**
- Statically typed GDScript. The size comes only from `Config.num("player.sprite_px")`. No hard-coded pixel size in the code or the scene.
- **Source art:** Kenney Space Shooter Redux, `PNG/playerShip1_blue.png`, 99×75 RGBA, nose at the top centre (the opaque pixels in row 0 are x 41–57). The dispatch provides a local extracted copy. The pack's `license.txt` says CC0 1.0.
- **Recolour (baked):** `tools/recolor_player_ship.py` uses the stdlib only (`zlib`, `struct`, `colorsys`), like `tools/gen_placeholder_sfx.py`. It has a module docstring with the run line, takes the source PNG path as its argument and writes `game/assets/sprites/player/playerShip1_coalition.png`. It accepts only 8-bit RGBA, non-interlaced PNGs and exits non-zero otherwise. Per pixel, in HSV: H is set to the hue of `coalition` #22E6FF; S becomes `min(1, S × S_c / S_b)` and V becomes `min(1, V × V_c / V_b)`, where `_c` is coalition and `_b` is the reference body colour (the most common fully opaque RGB in the source, #36BBF5). Alpha is unchanged. So the body maps exactly to #22E6FF, greys and whites stay near-neutral and outlines stay dark. Output is deterministic (same input gives the same bytes).
- `Sprite.modulate` / `self_modulate` stay at or below 1.0 (the default white), so nothing goes HDR-bright under `render.glow` (hdr_threshold 0.55).
- **`player.tscn`:** `Sprite.texture` is the new PNG (`ext_resource`). Remove the `Gradient_hull` / `GradientTexture2D_hull` sub-resources and fix `load_steps`. Leave the MuzzleFlash gradients, Hurtbox, MissileRing (`z_index = 1`) and ShieldBubble (`z_index = 1`) as they are.
- **`player.gd _ready`:** replace the placeholder width/height block with a uniform scale: `_sprite.scale = Vector2.ONE * (px / max(tex.width, tex.height))`. The Sprite stays centred at (0, 0). Then set `Muzzle.position = Vector2(0, -(tex.height × scale) / 2)`, the nose tip (−36.36 at default tuning). With a null texture or `sprite_px <= 0`, log `Log.warn("data", ...)` and leave the scale and Muzzle unchanged. Update the class doc to describe the hull.
- The hurtbox stays the `player.hurtbox_diameter_px` circle at (0, 0). The i-frame flicker and the hidden-on-death ship keep toggling `_sprite.visible` and `visible`, and need no code change.
- The PNG and its `.import` sidecar are committed. Run headless `--import` before the tests.

**Never:**
- No other ship, enemy or HUD art (Story 8.2). No new tuning keys, and no change to `hull_diameter_px` or other existing values. No rotation of the ship.
- Don't commit the original Kenney blue PNG, the zip or any local path. Don't use `print()`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Default | `sprite_px` 96, 99×75 texture | scale 0.9697 both axes; drawn 96×72.7; Muzzle (0, −36.36) | none |
| Retuned | `sprite_px` 64 before `_ready` | drawn longer side 64 (±1 px), aspect kept; Muzzle follows | none |
| Bad data | `sprite_px` 0 | scale and Muzzle unchanged | `Log.warn("data", …)` |
| Recolour | source body pixel #36BBF5 | output #22E6FF (±1 per channel), same alpha | non-RGBA8 or interlaced → exit non-zero |

</intent-contract>

## Code Map

- `game/entities/player/player.tscn` -- the `Sprite` currently uses `GradientTexture2D_hull` (96×96 radial). The `Muzzle` Marker2D is at (0, −40) with `MuzzleFlash/FlashLeft|Right` at ±8 x. MissileRing and ShieldBubble are at `z_index = 1`.
- `game/entities/player/player.gd:118-123` -- the placeholder resize block (`placeholder.width/height = px`), which this story replaces. `_sprite` is `@onready $Sprite`. `_health.setup(..., _sprite)` is the flicker target. `_die()` sets `visible = false`.
- `game/entities/player/missile_ring.gd:28-33` -- clamps the radius to `sprite_px / 2`. Unchanged.
- `game/tests/unit/test_player_movement.gd:218-245` -- `test_sprite_matches_sprite_px` and `test_hurtbox_and_sprite_sizes_follow_config` assert `texture.get_size() == (px, px)`. They must assert the scaled longer side instead.
- `game/tests/unit/test_missile_ring.gd:60-69` -- ring above sprite (keep green).
- `game/tests/unit/test_player_barrage.gd:54,93`, `test_player_laser.gd`, `test_player_missile.gd` -- these read the Muzzle `global_position` dynamically (keep green). `test_player_weapons.gd` builds its own Muzzle at −40 and isn't affected.
- `game/tests/fixtures/player_test_base.gd` -- the `_make_player(pos, warp)` fixture.
- `tools/gen_placeholder_sfx.py` -- the style to copy for the new tool (stdlib, docstring with the run line `uv run python tools/...`).
- `game/assets/CREDITS.md` -- "Third-party assets: None yet", plus the final note "Placeholder sprites and particles are drawn in code…".
- `_bmad-output/game-architecture.md:563` -- the Directory Structure "built parts" sentence. `:668` -- the `entities/player/` row. `:1575+` -- the as-built sections (add a new one after DW-55, before the closing `---`).

## Tasks & Acceptance

**Execution:**
- `tools/recolor_player_ship.py` -- create the deterministic stdlib recolour tool as specified. Run it on the provided source -- produces the committed PNG reproducibly.
- `game/assets/sprites/player/playerShip1_coalition.png` (+ `.import` after `--import`) -- the generated hull.
- `tools/test_recolor_player_ship.py` -- stdlib `unittest` for the tool: a tiny in-memory RGBA PNG with a #36BBF5 body pixel, a grey pixel and a transparent pixel maps to #22E6FF (±1), near-neutral grey and the same alpha values; two runs give identical bytes; an 8-bit RGB (colour type 2) or interlaced PNG is rejected (non-zero exit or the documented exception) -- covers the Recolour matrix row.
- `game/tests/unit/test_player_movement.gd` (asset check) -- load the committed PNG's `Image` and assert it is 99×75 and that its most common fully opaque colour is #22E6FF within 1/255 per channel -- the committed art really is the coalition recolour.
- `game/entities/player/player.tscn` -- swap the Sprite texture to the PNG and drop the hull gradient sub-resources -- the real hull.
- `game/entities/player/player.gd` -- uniform scale from `sprite_px`, Muzzle at the nose, warn on bad data, doc update -- data-driven sizing.
- `game/tests/unit/test_player_movement.gd` -- rewrite the two size tests. Add: the texture is non-null, not `GradientTexture2D`, and the path is under `res://assets/sprites/player/`; the scaled longer side equals `sprite_px` within 1 px with equal x/y scale; the retuned-64 case; the Muzzle is at (0, −scaled_h/2) within 0.01; the hurtbox is still at (0, 0) with radius `hurtbox_diameter_px / 2`; `sprite_px` 0 warns and leaves the scale at ONE -- the AC test plus edge cases.
- `game/assets/CREDITS.md` -- add a Third-party row (file `sprites/player/playerShip1_coalition.png`; source Kenney Space Shooter Redux, kenney.nl, `playerShip1_blue.png`; licence CC0 1.0; note "recoloured to coalition #22E6FF by `tools/recolor_player_ship.py`"). Reword the closing note so it no longer covers the player ship.
- `_bmad-output/game-architecture.md` -- the directory-structure sentence lists `assets/sprites/player/`. The player row notes that the hull is scaled from `player.sprite_px`. Add an "As-built 2026-10-08 (Story 4.0)" section (texture, tool, scale rule, Muzzle rule).

**Acceptance Criteria:**
- Given the Player scene loads, when `_ready` runs, then `Player/Sprite` shows the recoloured Kenney hull from `game/assets/sprites/player/`, nose toward −y, with a modulate of at most 1.0.
- Given `player.sprite_px`, when `_ready` runs, then the longer side is scaled to it uniformly, the hurtbox is still the 24 px circle centred on the hull, and lasers, missiles and barrage leave from the Muzzle on the nose, with the muzzle flash there.
- Given a hit, death, the Shield or the missile reload, when they play, then the flicker, the hidden-on-death ship, the bubble and the ring above the hull all still work, and the existing player, shield-bubble and missile-ring tests pass.
- Given `CREDITS.md` and `game-architecture.md`, when read, then they record the asset (source, CC0 1.0, recoloured) and the as-built (`assets/sprites/player/`, scale from `player.sprite_px`).
- Given a human plays the dev level with glow on, when they fly and fight, then the ship reads at a glance as a cyan/teal fighter pointing up, distinct from enemies and pickups. This is a human-only check, owed as an operator action.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 28 findings — high 0, medium 0, low 20, false 8, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) PNG filter types 1–4 and `_paeth` untested — added `test_reads_every_filter_type` (rows hand-filtered 0–4; filter 5 raises) and `test_paeth_predictor`.
  - `[low]` `[patch]` (blind) "same bytes" determinism only holds for one zlib build — docstring reworded: decoded pixels are always identical, and the PNG bytes are identical with the same zlib build.
  - `[low]` `[patch]` (blind) source not pinned — the docstring records the SHA-256 of the source `playerShip1_blue.png` and of the committed output (docs only).
  - `[low]` `[reject]` (blind) a malformed IHDR raises a `struct.error` traceback — it still exits non-zero; the tool bakes one known Kenney file, so this is unlikely, and the fix adds guards.
  - `[low]` `[patch]` (blind) optional `[<output PNG>]` argument undocumented — now documented in the docstring and run line.
  - `[low]` `[reject]` (blind) the null-texture, empty-texture and negative `sprite_px` branches are untested — the scene always has the hull texture, and `sprite_px` 0 already covers the `<= 0` warn path; more tests would guard states nothing reaches.
  - `[low]` `[reject]` (blind) the Muzzle formula assumes `centered` and no offset — the scene uses the Sprite2D defaults; supporting other settings adds branches for a state nobody authors.
  - `[false]` `[reject]` (blind) HDR check incomplete (root modulate; values not asserted white) — the spec's bound is ≤ 1.0 and that is asserted; the Player root modulate is the default white in `player.tscn`, so nothing can bloom.
  - `[low]` `[patch]` (blind) the path test and the asset test can check different files — now asserts `resource_path == HULL_PATH`.
  - `[low]` `[reject]` (blind) MissileRing clamp `sprite_px / 2` vs the 72.7 px tall hull — a pre-existing architecture rule; the ring is 16 px, well inside the hull; changing the clamp is a design change, not a defect.
  - `[false]` `[reject]` (blind) CREDITS row lacks a pack link and version — the AC asks for file, source (Kenney Space Shooter Redux, kenney.nl), licence CC0 1.0 and a recolour note; all are present.
  - `[false]` `[reject]` (blind) spec left in-review with the human check untracked — that was a mid-pipeline snapshot; finalize sets `awaiting-operator` with `operator_actions`.
  - `[low]` `[reject]` (edge) IHDR length not checked → `struct.error` — same root cause as the blind IHDR row; rejected for the same reason.
  - `[low]` `[reject]` (edge) chunk CRCs not checked — the input is a single trusted CC0 file, the GUT asset test catches gross corruption, and the fix adds guards.
  - `[low]` `[patch]` (edge) output mkdir/write outside the `try` → traceback — moved inside the existing `try`; an unwritable output now prints the clean error and exits 1.
  - `[low]` `[reject]` (edge) an achromatic body colour silently falls back to grey — the Kenney body is #36BBF5 (saturated); this guards an input the tool never sees.
  - `[low]` `[reject]` (edge) Muzzle wrong with `centered = false` or an offset — same as the blind Muzzle-formula row.
  - `[low]` `[patch]` (edge) the bad-data fallback leaves the Muzzle at the authored −40, but the unscaled nose is at −37.5 — authored `Muzzle.position` set to (0, −37.5).
  - `[false]` `[reject]` (edge) `tex.get_image()` may be null headless — the test ran and passed in the headless suite, so the image is readable there.
  - `[low]` `[reject]` (edge) a runtime error before the restores leaks `Log.sink` / `sprite_px` — same pattern as the existing size test, only reachable once a test is already failing, and the fix adds teardown plumbing.
  - `[low]` `[reject]` (edge) `_drawn()` has no null guard — a null texture still fails the test loudly, and `test_sprite_is_the_real_hull` asserts the texture first.
  - `[false]` `[reject]` (edge, claim) the "non-zero exit via a handled error" claim fails for malformed input — the claim covers non-RGBA8 and interlaced input, which is handled; malformed headers are the rejected IHDR row.
  - `[low]` `[patch]` (verification-gap) the S/V clamp is never reached in tests — added `test_white_hits_the_value_clamp_and_stays_neutral` (#FFFFFF stays 254–255, neutral, alpha 255).
  - `[low]` `[patch]` (verification-gap) filter types 1–4 never decoded — same root cause as the blind filter row; covered by the same new test.
  - `[low]` `[reject]` (verification-gap, other) `struct.error` / `ValueError` escape `main()` — the `ValueError` path needs the clamp removed, which a test now pins; `struct.error` is the rejected IHDR row.
  - `[false]` `[reject]` (intent) not committed, no `awaiting-operator` yet — finalize commits and sets `status: awaiting-operator` with `operator_actions`.
  - `[false]` `[reject]` (intent) the human readability check is covered only by static stand-ins — by design: it is a human-only check, owed as an operator action.
  - `[false]` `[reject]` (intent) the tool takes an optional output-path argument the spec doesn't name — the default behaviour matches the spec; the argument only lets tests write to a temp dir, and it is now documented.

## Design Notes

The muzzle is derived, not authored: putting it at −(drawn height)/2 keeps it on the nose for any `sprite_px`, and the source's row 0 is the centred nose tip. The colour is baked rather than tinted, because multiplying a blue texture by cyan only darkens it and can't turn it into #22E6FF. A tool, rather than a hand-edited PNG, keeps the recolour reviewable and repeatable.

## Verification

**Commands:**
- `uv run python tools/recolor_player_ship.py <source PNG>` -- expected: writes the PNG; a second run gives identical bytes.
- `uv run python -m unittest tools/test_recolor_player_ship.py` -- expected: all pass.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0 and creates `playerShip1_coalition.png.import`.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass.

## Auto Run Result

Status: awaiting-operator

**Summary:** The player ship is now a Kenney Space Shooter Redux fighter hull (CC0), recoloured to `coalition` #22E6FF by a reproducible stdlib tool. `Player._ready` scales it uniformly so its longer side equals `player.sprite_px` (96 gives 96×72.7) and puts the `Muzzle` on the nose (y −36.36). The hurtbox, i-frame flicker, hidden-on-death ship, shield bubble and missile ring are unchanged, and their tests pass.

**Files changed:**
- `tools/recolor_player_ship.py` -- new stdlib HSV recolour tool (8-bit RGBA only; records the source and output SHA-256).
- `tools/test_recolor_player_ship.py` -- new unittest covering body/grey/alpha mapping, the white clamp, filters 0–4, Paeth, determinism, and rejection of RGB and interlaced input.
- `game/assets/sprites/player/playerShip1_coalition.png` (+ `.import`) -- the recoloured 99×75 hull.
- `game/entities/player/player.tscn` -- the Sprite uses the PNG, the hull gradient is removed, and the authored Muzzle is at (0, −37.5).
- `game/entities/player/player.gd` -- `_fit_hull(px)` scales uniformly, puts the Muzzle on the nose and logs `Log.warn("data")` on bad data; the doc comment is updated.
- `game/tests/unit/test_player_movement.gd` -- rewrote the size tests; new tests cover the real hull, the coalition asset, scale and aspect, the Muzzle on the nose, retuning and bad data.
- `game/assets/CREDITS.md` -- a third-party row for the hull; the placeholder note no longer covers the player ship.
- `_bmad-output/game-architecture.md` -- updated the directory as-built list and the player row, and added an "As-built 2026-10-08 (Story 4.0)" section.

**Review findings:** 28 total. 9 were patched: the filter-type decode test (two findings, plus a bundled Paeth test), the white-clamp test, the determinism wording, the source and output hashes, documenting the optional output argument, moving the write inside the `try`, the exact hull-path assert, and the authored Muzzle at −37.5. None was deferred. 19 were rejected: 8 false, and 11 low ones that were unlikely to bite and needed extra guards, or would have been design changes. The Review Triage Log gives the reason for each.

**Follow-up review recommended:** false. All 9 patched findings were `low` (patched counts: high 0, medium 0, low 9).

**Verification:**
- `uv run python -m unittest tools/test_recolor_player_ship.py` -- OK.
- Re-baking from the source gives a byte-identical PNG.
- Headless `--import` -- exit 0.
- Full GUT suite -- 919/919 passing, exit 0 (after the patches).

**Residual risks:**
- Whether the hull reads at a glance with glow on can't be verified automatically; it is owed as an operator action.
- The Kenney pack came from Kenney's own OpenGameArt upload of Space Shooter Redux (CC0, same `license.txt`), not directly from kenney.nl.

**Operator actions owed:**
- Play the dev level with glow on and confirm the ship reads at a glance as a cyan/teal fighter pointing up, distinct from enemies and pickups.

## Operator Confirmation

Confirmed 2026-10-08: the external actions this story owed were carried out.

- Play the dev level with glow on and confirm the ship reads at a glance as a cyan/teal fighter pointing up, distinct from enemies and pickups.

_Appended by the bmad-loop orchestrator (`bmad-loop confirm`, #335): a human confirmed these external actions out of band, and the story was advanced from `awaiting-operator` to `done`._
