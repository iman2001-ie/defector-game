---
title: 'Story 8.2: Make the Game Look Neon'
type: 'feature'
created: '2026-10-13'
status: done
operator_actions:
  - 'Play Level 1, Level 2 and Level 3 in a debug build ("<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game) and judge every new sprite in motion: the five enemy silhouettes (Wasp, Lancer, Needle, Bastion, Maul) and the orange Hunter Wasp, with each one pointing its nose toward the player (check the Needle, Bastion and Maul, which come from the Extension pack, in particular); the cyan ally fighter; the dimmed convoy hulls reading as civilian cargo; and the Ram in Tarek''s fall.'
  - 'Judge the asteroids: grey-brown, jagged, with the rim light baked on the upper-left edge (the light turns as the rock spins). Say whether that reads well or needs a non-rotating rim.'
  - 'Play Level 2 to Tarek''s fall and confirm his hull swaps to the darkened, battle-damaged sprite with the fire trail when he is hit.'
  - 'Fight the Flagship in Level 3 and judge the project-owned SVG hull against the Kenney turrets and core (mounts lined up, the Eye pulse readable, no bloom blob), and check that the throne-world arc still reads as a reveal over the space_2 tiles.'
  - 'Look at the two space backgrounds (space_1 in Level 1, the title and the story scene; space_2 in Level 2): no visible tile seams, dark enough, no bloom. Also check the Level Select thumbnails, including the throne-world arc shown on the Level 3 card.'
  - 'Read the comms in the opening and in a fight: judge the three SVG portraits (Isolde, Tarek, Ryn) in the 200 px story panel and the 88 px interruption box.'
  - 'Judge the Kenney Future font on the title, menus, HUD labels, names and buttons. Approve or reject decision #66''s reading that dialogue text (story panel, interruption box, pause-menu recent comms) and the story-panel cue keep the engine font, because Kenney Future Narrow could not be downloaded (kenney.nl returns 403). If you can supply Kenney Future Narrow, add it and switch the dialogue fonts to it.'
  - 'Approve or replace any pick in tools/import_cc0_art.py ROWS or the SVGs, then record the outcome in decision #66 of the decision log (it is marked provisional).'
baseline_revision: '6a7683d433073023b1a9fbc1efcf00bff7708293'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
warnings: ['oversized']
deferred:
  - summary: >-
      The architecture's Story 7.6 LevelBackground bullet still describes the old arc: it rises 200 px from the bottom edge with a 40 px margin. The code now hangs it 180 px down from the top edge with a 64 px margin.
    evidence: |-
      game/scenes/level/level_background.gd:48,54 (ARC_HEIGHT_PX 180, EDGE_MARGIN_PX 64, arc hanging from the top since the 2026-10-13 playtest) versus game-architecture.md:1964, which still says (960, 1080 + 1600 - 200), the bottom edge, and EDGE_MARGIN_PX 40. The staleness predates Story 8.2, which only appended a tiling note to that bullet.
    location: >-
      _bmad-output/game-architecture.md:1964
    severity: low
  - summary: >-
      test_level.gd test_dev_ally_level_spawns_tarek_who_fires_and_scores, a real-time test of ally kills, failed once and then passed in the full run and on its own.
    evidence: |-
      Seen once by the Story 8.2 implementer, in an early run. Two later full runs passed (2032/2032). The test (Story 6.4) depends on real-time ally kills, so it may be flaky. To settle it, run the test in a loop (for example 20 runs) and look for a timing assumption in its kill wait.
    location: >-
      game/tests/unit/test_level.gd (test_dev_ally_level_spawns_tarek_who_fires_and_scores)
    severity: low
  - summary: >-
      No test observes LevelBackground._draw tiling the space texture. The tests check only tile_texture(), tile_rect() and texture_repeat, so a broken draw call would pass.
    evidence: |-
      Headless GUT runs on the dummy renderer and can't sample pixels. _draw calls draw_texture_rect(tiles, tile_rect(), true) before the throne-world early return, and nothing records that call. Closing the gap needs a seam that records draw calls, or a screenshot check. Until then the operator's look-check covers it.
    location: >-
      game/scenes/level/level_background.gd (_draw)
    severity: low
---

<intent-contract>

## Intent

**Problem:** Apart from the player ship (Story 4.0), every ship, the convoy, the asteroids, the Flagship and the Ram are code-drawn polygons. `space_1` and `space_2` draw nothing. Portraits are an initial letter in a frame. No font ships, so the UI uses Godot's fallback font, not the Kenney Future font that DESIGN.md calls for. The title and story scenes have no backdrop, and the Level Select thumbnails are flat grey boxes.

**Approach:** Add a reproducible, stdlib-only importer that recolours Kenney Space Shooter Redux and Extension sprites (CC0) to the palette. Use it for the enemies, allies, convoy, asteroids, Flagship turret and core, and the two space backgrounds. Hand-author project-owned SVGs for the three portraits and the Flagship hull, which Kenney has no art for. Swap the placeholder visual nodes for `Sprite2D`s, fitted from the existing size data. Give the shared Theme Kenney Future, except for dialogue text. Credit every file, and enforce the credits with a data test.

## Boundaries & Constraints

**Always:**
- Sources are CC0 Kenney packs or project-owned SVGs. Every file under `game/assets/` gets a `game/assets/CREDITS.md` row: source, licence (`CC0 1.0` / `Project-owned`) and processing.
- Gameplay stays the same: hitboxes, hurtboxes, collision outlines (`outline()` / `damaged_outline()`), muzzles, turret and core positions, sizes, colours of telegraph and glow nodes, and animated nodes (Wasp flash on `Hull`, Lancer `MuzzleGlow`, Bastion `Turrets/*`, turret `Barrel`/glow, core `Eye` pulse, Needle `TelegraphLine`, Maul/Ram `Trail`, ally `FireTrail` and shield ring) keep their names, positions and behaviour. Only the placeholder body nodes change.
- Each sprite is fitted from existing data with uniform scale: the longer side equals `sprite_px` (enemy and Ram `@export`, `boss.*.sprite_px`), `allies.ship_px`, or the asteroid `diameter_px`. The convoy hull fits inside `convoy.ship_width_px` × `ship_height_px`. Nothing is hard-coded.
- Rotation 0 means nose toward +y for enemies and the Ram (Kenney enemies already face down; `rotation = heading.angle() - PI/2`). Allies and the convoy face up (−y).
- Sprite modulate stays white. Background pixels keep every channel ≤ 127/255, below `render.glow.hdr_threshold` (0.55), so they never bloom.
- Statically typed GDScript. Write the failing GUT test first. Log through `Log`. No per-frame allocations.

**Never:**
- Don't change projectiles, the energy orb, explosions or shockwaves, the shield bubble, the missile ring, the player ship or the throne-world arc geometry and colours: they already follow the palette.
- Don't add a parallax or scrolling background, settings or new gameplay tuning.
- Don't regenerate `playerShip1_coalition.png`. Don't commit downloaded zips, unused pack files, `__pycache__` or any machine path.
- Don't set per-node style overrides. `LevelClearBanner`'s overrides move into the Theme.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Level background | `set_background(&"space_1")` / `&"space_2"` | The texture is tiled over the playfield plus `EDGE_MARGIN_PX` on every side | `""` draws nothing; an unknown id keeps its warn-once |
| Throne world | `&"throne_world"` | The `space_2` tiles, then the existing arc on top | No error expected |
| Portrait speaker | `show_line(&"tarek", …)` in the panel or box | `Portrait/Image` shows `portrait_tarek.svg`; `Initial` is hidden | A speaker with `portrait: true` but no texture shows `Initial` (as now) |
| No-portrait speaker | vale / system | Unchanged no-portrait variant | No error expected |
| Tarek falls | ally FALLING/GONE | The `Sprite` texture swaps to `ally_damaged.png`; `FireTrail` runs as now | No error expected |
| Bad fit size | `sprite_px` ≤ 0 or no texture | Scale is left at 1 and the problem warns once (the player's `_fit_hull` rule) | Warn, no crash |
| Importer | `--redux DIR --extension DIR` with an unzipped pack missing a mapped file | Exit 2 naming the file. Nothing partial is written for that row | Non-zero exit |

</intent-contract>

## Code Map

- `tools/recolor_player_ship.py` -- stdlib PNG `read_rgba` (RGBA only), `write_rgba`, `body_colour`, `recolor`. Reuse these by import; never re-run the tool on the player file. `tools/import_cc0_audio.py` is the pattern for the mapping table, `--packs`-style args and docstring provenance.
- `game/core/enemy.gd:29,215-218` -- `sprite_px` export, hitbox. A shared fit belongs here (or in a new `core/sprite_fit.gd`, `class_name SpriteFit`); `player.gd:252-263` `_fit_hull` is the rule to mirror.
- Enemy scenes (`Hull` Polygon2D): `wasp.tscn:14` (flash `wasp.gd:63,150`), `hunter_wasp.tscn:15` (orange #FF8A1F, GDD "distinct orange tint"), `lancer.tscn` (`MuzzleGlow`), `needle.tscn` (+`TelegraphLine`), `bastion.tscn:29-63` (`Hull`/`Plating`/`Bridge` + `Turrets/Turret0..1` at (±44,40)), `maul.tscn` (+additive `Trail`), `entities/story/ram.tscn:16` (Hull spans about 120 px; root scale `story.tarek_fall.ram_scale`).
- Boss: `flagship.tscn:16-26` (`Hull`/`Plating`/`Bridge`, outline ±360 × ±70; turrets at y 94, core at y 114), `flagship_turret.tscn:28-44` (`Body`/`Plating` placeholders; `Barrel` + glow stay), `flagship_core.tscn:28-40` (`Shell` placeholder; `Eye` stays, pulse `flagship_core.gd:54,111-113,299`), `flagship_part.gd:26` (sprite_px from `boss.*`).
- Allies: `ally_ship.gd:49-60,391-408` (`_draw` body/outline; damaged `:392-393`; shield arc `:396-399`; `FireTrail` `:176-182`), `convoy_ship.gd:17,58-79` (`_draw` polygon, `outline()` used for solids).
- `asteroid.tscn:13-24` / `asteroid.gd:12,44,55-58` -- `Visual/Body` + `Visual/Rim` placeholders. `Visual.scale = radius` comes from `asteroids.<size>.diameter_px`.
- `scenes/level/level_background.gd:31-61,94-100` -- ids, the arc, `EDGE_MARGIN_PX` 64. Used by `level.tscn:35` and `end_screen.tscn:17`. `title.tscn` and `story.tscn` (root Control) have no background node.
- `scenes/title/level_select.gd:98-113,163-173` -- `Thumbnail` ColorRect (theme `LevelSelect/colors/thumbnail`) inside the card's thumbnail rect. The levels' background ids are at `data/levels/level_[123].json:4`.
- Comms: `comms_panel.gd:141-145,241-246` / `.tscn` `Panel/Portrait` (200 px) + `Initial`; `comms_box.gd:99-100,179-183,422-427,439` `Box/Portrait` (88 px). Speakers: `tuning.json:278-283` `comms.speakers.<id>.portrait`.
- `ui/theme/defector_theme.tres` -- no default font. `CommsBox/fonts/text` is a base-less `FontVariation`, which resolves to the engine fallback font, not this Theme's default. `level.tscn:163-171` `HUD/LevelClearBanner` uses overrides.
- Text tests stay valid only if the dialogue keeps its font: `test_comms_box.gd:407,432,456`, `test_comms_panel.gd:289`. Measured Kenney Future vs fallback at 28 px for a 50-character line: 961 vs 675 px. The 195-character dev line takes 5 lines in the 812 px panel, over the 4-line limit. Every UI label measured still fits (Level Select name 510 px wraps within its 84 px two-line row). Kenney Future has no `▸` glyph (story-panel cue).
- Tests that pin today's placeholders and need updating: `test_hunter_wasp.gd:61`, `test_lancer.gd:114`, `test_needle.gd:140`, `test_bastion.gd:151`, `test_maul.gd:126`, `test_flagship.gd:311,633`, `test_ram.gd:59`, `test_ally_ship.gd:391,647`, `test_convoy.gd:391,417`, `test_asteroid.gd:38,55`, `test_level_background.gd` (the "space draws nothing" cases), `test_level_select.gd:163,229`, `test_comms_box.gd:187,209`, `test_comms_panel.gd:199,220`.
- `tests/data/test_data_files.gd:1143-1181` -- `test_every_audio_file_is_credited` (`_credited`). Generalise it to all of `res://assets/`.
- Docs: `game-architecture.md:271-276,344-346,646-659,706,1642-1649,1872,1882,1963,1994-2000` (target tree: `portraits/*.png`, `ui/theme/fonts/`, `backgrounds/throne_world_arc.png`). The decision log's next row is #66. `epic-8-context.md` has the Backgrounds, Portraits and Theme bullets.

## Tasks & Acceptance

**Execution:**
1. `tools/import_cc0_art.py` (new, stdlib) plus `tools/test_import_cc0_art.py` (unittest, synthetic images, no packs).
   - Takes `--redux DIR --extension DIR` and writes the table below.
   - Decodes 8-bit RGBA and RGB PNGs (the backgrounds are RGB).
   - Ops:
     - `recolor(target, value=1.0)`: the existing HSV map, with the reference = the most common opaque RGB with S ≥ 0.25 (falling back to `tint` if there is none), then V × `value`.
     - `tint(target)`: target × pixel luminance.
     - `rot180`.
     - `overlay(src2)`: alpha-over, same size.
     - `rim(rgb, px=2)`: opaque pixels within `px` of transparency on the upper-left side lerp 70% toward `rgb`.
     - `background(target)`: target × (luminance / mean luminance), every channel clamped to ≤ 127.
     - `copy`: byte-for-byte.
   - The docstring records page URLs and zip SHA-256 values. Re-running gives byte-identical output.
   - Tests cover: the mapping table, each op, the reference choice, the background clamp, deterministic bytes, and exit 2 on a missing file.
2. Run the importer.
   - Download `https://opengameart.org/sites/default/files/SpaceShooterRedux.zip` (SHA-256 `d44a371a8fa1eb5d61a4fed3677954590aa015a78d2afb5f97924cfe02e3f700`) and `…/kenney_spaceShooterExtension.zip` (`77efd54b343bbd123af8cc7f534446706731b9cf5a34f38d8fcc54e7245f9c91`) into a fresh system-temp folder, and unzip each into its own empty folder.
   - Run the tool, then view each output PNG to confirm its colour and orientation.
3. Author the project-owned SVGs.
   - `assets/portraits/portrait_{isolde,tarek,ryn}.svg`: 200×200 viewBox, simple stylised head-and-shoulders busts on dark `#0A1222`, line art and fills in the speaker accent (`isolde` #FF6AE3 with a crown and high collar, `tarek` #3DF2FF older and bearded with a pilot collar, `ryn` #7CFFB2 with short hair and a flight-suit collar).
   - `assets/sprites/boss/flagship_hull.svg`: 720×140 within the current hull outline, dark plating (every channel ≤ 0.5) with `enemy` neon trim, and mounts above the four turret x positions and the core.
   - Then run the headless `--import`.
4. Code.
   - Replace the placeholder nodes with a `Sprite2D` (keep the node name `Hull` for enemies, the Ram and the Flagship; `Body` for the turret; `Shell` for the core; `Visual/Sprite` for the asteroid, removing `Body`/`Rim`; `Sprite` for the ally and the convoy ship, whose `_draw` stops filling the body polygon but keeps the shield ring). Remove Bastion/Flagship `Plating`/`Bridge` and turret `Plating`.
   - Add `@export var sprite_px: float = 120.0` to the Ram. Ally textures swap on `is_damaged()`.
   - `LevelBackground`: preloaded textures, a tiled draw (`texture_repeat` enabled), and `throne_world` = the `space_2` tiles plus the arc.
   - Add a `Background` (`space_1`) as the first child of `title.tscn` and `story.tscn`.
   - Level Select `Thumbnail` becomes a clipped `Control` holding a `LevelBackground` set to the level's `background` id, scaled to the thumbnail rect. A null id keeps the theme colour.
   - New `systems/comms/comms_portraits.gd` (`class_name CommsPortraits`, a preloaded `StringName → Texture2D` map) feeds a `Portrait/Image` TextureRect in both comms UIs.
5. `ui/theme/defector_theme.tres`.
   - `default_font` = `assets/fonts/kenvector_future.ttf`.
   - `CommsPanel/fonts/text` and `CommsPanel/fonts/cue` = base-less `FontVariation`s, so the dialogue and the `▸` cue keep the engine font (`CommsBox/fonts/text` already does).
   - New `LevelClearBanner` type with its colour and size, replacing the `level.tscn` overrides.
   - If any fit test fails under Kenney Future, lower only that type's size (never below 20 px) and record it in #66.
6. Tests. Update the pins above to assert the texture `resource_path`s and the fitted size within 1 px. Add tests for:
   - every matrix row;
   - every background pixel ≤ 127;
   - the default font is Kenney Future and the dialogue fonts are not;
   - in `test_data_files.gd`, every file under `res://assets/` (except `.import`, `.uid`, `.gitkeep` and `CREDITS.md`) has a `CREDITS.md` row with `CC0 1.0` or `Project-owned` (replacing the audio-only test).
7. `game/assets/CREDITS.md`.
   - Add a row per new file: pack, source file, `CC0 1.0` and the op.
   - Add a "Project-owned art" table for the four SVGs.
   - Replace the closing "placeholder sprites" note with the list of what stays code-drawn by design.
8. Docs.
   - Decision log #66: the mapping, SVG portraits and hull, convoy and damaged dimming, dialogue keeping the engine font because Kenney Future Narrow isn't obtainable (kenney.nl returns 403 here; the OGA font pack has only Future and Thin), and any size retunes. Mark it provisional pending the operator.
   - Architecture: an "As-built 2026-10-13 (Story 8.2)" section, and correct the target-tree and Scene Structure lines.
   - `epic-8-context.md`: update its art bullets.

| output under `game/assets/` | source (pack → file) | op |
|---|---|---|
| `sprites/enemies/enemy_wasp.png` | Redux `PNG/Enemies/enemyRed1.png` | recolor #FF2BD6 |
| `sprites/enemies/enemy_hunter_wasp.png` | Redux `PNG/Enemies/enemyRed1.png` | recolor #FF8A1F |
| `sprites/enemies/enemy_lancer.png` | Redux `PNG/Enemies/enemyRed2.png` | recolor #FF2BD6 |
| `sprites/enemies/enemy_needle.png` | Ext `PNG/Sprites/Ships/spaceShips_006.png` | recolor #FF2BD6 |
| `sprites/enemies/enemy_bastion.png` | Ext `PNG/Sprites/Ships/spaceShips_007.png` | recolor #FF2BD6 |
| `sprites/enemies/enemy_maul.png` (also the Ram) | Ext `PNG/Sprites/Ships/spaceShips_004.png` | recolor #FF2BD6 |
| `sprites/allies/ally_coalition.png` | Redux `PNG/playerShip2_blue.png` | recolor #22E6FF |
| `sprites/allies/ally_damaged.png` | Redux `PNG/playerShip2_blue.png` + `PNG/Damage/playerShip2_damage3.png` | overlay, recolor #22E6FF value 0.45 |
| `sprites/allies/convoy_cargo.png` | Ext `PNG/Sprites/Ships/spaceShips_005.png` | rot180, recolor #22E6FF value 0.5 |
| `sprites/boss/flagship_turret.png` | Redux `PNG/Parts/turretBase_big.png` | tint #FF2BD6 |
| `sprites/boss/flagship_core.png` | Redux `PNG/ufoRed.png` | recolor #FF2BD6 |
| `sprites/asteroids/asteroid_{large,medium,small}.png` | Redux `PNG/Meteors/meteorBrown_{big1,med1,small1}.png` | recolor #7A6E62, rim #C9D8E8 |
| `backgrounds/space_1.png` / `space_2.png` | Redux `Backgrounds/blue.png` / `darkPurple.png` | background #0B1226 / #140E26 |
| `fonts/kenvector_future.ttf` | Redux `Bonus/kenvector_future.ttf` | copy |

**Acceptance Criteria:**
- Given any level, when it runs, then allies and the convoy are coalition-cyan Kenney hulls (the convoy dimmer), all enemies and the Ram are magenta Kenney hulls with five distinct silhouettes (the Hunter Wasp is the Wasp in orange, per the GDD), the asteroids are grey-brown with a rim light, and the player ship, enemy projectiles and orbs are unchanged.
- Given the project, when the assets are listed, then it holds `space_1` and `space_2` backgrounds (drawn in Levels 1–2, the title, the story scene and Level Select), the throne-world arc (Level 3 and the end screen only), three portraits, Tarek's damaged hull, the Flagship hull, turret and core, and Kenney Future in the shared Theme.
- Given every file under `game/assets/`, when the data test runs, then each has a `CREDITS.md` row with its source and licence.
- Given the change, when the full GUT suite and the importer unit tests run, then all pass, and `--bench=20` still reports p99 < 16.6 ms.

## Spec Change Log

## Review Triage Log

### 2026-10-13 — Review pass
- verdicts: 24 findings — high 0, medium 0, low 21, false 3, maybe-false 0
- findings:
  - `[low]` `[defer]` (blind) The architecture's Story 7.6 LevelBackground bullet still describes the old arc geometry: bottom edge, 200 px, 40 px margin. — Pre-existing: the arc moved to the top edge (180 px, 64 px margin) in the 2026-10-13 playtest, before this story. Deferred.
  - `[low]` `[patch]` (blind) The pause menu's RECENT COMMS rows show dialogue in Kenney Future, contrary to "dialogue keeps the engine font". — Added a base-less `PauseMenu/fonts/comms` FontVariation, applied to the rows in `_apply_theme`. The heading stays Kenney Future. Added a test in `test_pause_menu.gd` and updated the #66, architecture and epic-context wording. The rows fit either way (a 50-character line is about 920 px in a 1200 px panel).
  - `[low]` `[patch]` (blind) DESIGN.md's Typography section doesn't reflect the dialogue-font reading. — Added one Typography bullet pointing to decision #66 (provisional). Approval is in `operator_actions`.
  - `[low]` `[reject]` (blind) The convoy art is narrower than its hitbox and solid shape. — Partly false: the hitbox is 160 × `hitbox_ratio` 0.8 = 128 px, inside the drawn 129.5 px, so shots and Maul contact land on the visible hull. Only the player-solid formation polygon (built from the 160 px `hull_rect`) reaches about 15 px past the outer flanks. That matches the GDD's "one solid shape including the gaps". A fix would need a new fit rule.
  - `[low]` `[reject]` (blind) The large asteroid's 224 px hitbox circle extends about 19 px past the 224×186 drawn rock. — The old unit polygon was just as irregular (radii 0.77–1.0, gaps up to about 26 px at r 112). The jagged meteor is the GDD's look, and a fix would mean redesigning the hitbox against the art.
  - `[low]` `[reject]` (blind) The ally draws 64×43, not 64×64, and FireTrail starts 2.6 px below the hull. — This follows the spec's fit rule (the longer side equals `allies.ship_px`, like every sprite). The 2.6 px trail offset can't be seen once the particles drift.
  - `[low]` `[reject]` (blind) `outline()` / `damaged_outline()` are dead shape code, and a test pins an unseen broken wing. — The spec's Always list keeps them as the hull's shape data. They're harmless and documented as shape data in the class doc.
  - `[low]` `[reject]` (blind) The portrait image's square corners cover the frame's 4 px rounded corners. — Cosmetic, inside a 1 px border on a 200/88 px portrait. Unlikely to be noticed, and the fix needs a new inset or clip rule.
  - `[false]` `[reject]` (blind) The Ram's 120 px `sprite_px` is hard-coded and makes it 1.875× the Maul, against #63's "1.5x". — The old Ram hull polygon also spanned about 120 px, under the same `ram_scale` 1.5. The drawn size is unchanged, and the export follows the enemy `sprite_px` pattern.
  - `[low]` `[defer]` (blind) Spec bookkeeping (status, change log, wording drift such as `set_background` vs `apply`) and a flaky ally test that wasn't deferred. — The spec-edit parts are rejected (a fix that edits this build's spec). The once-failed real-time test is pre-existing (Story 6.4) and deferred.
  - `[false]` `[reject]` (blind) Kenney Future's system glyph fallback makes text metrics depend on the machine. — Checked in-engine: Kenney Future has every glyph of A–Z, a–z, 0–9 and `[]:.,'!?-%/()`, which covers every string it now draws. Dialogue (including the recent-comms rows after the patch above) and the `▸` cue use the engine font.
  - `[low]` `[reject]` (blind) The baked upper-left rim light turns with the spinning asteroid. — The spec chose a baked rim. Light drift on a slowly spinning rock is subtle, and a non-rotating rim layer adds nodes. Listed in `operator_actions` for a look.
  - `[low]` `[patch]` (blind) The silhouette test uses texture size as identity, and `SpriteProbe.max_channel` has no null guard. — `max_channel` now returns -1.0 for a null texture or image. The size proxy is kept: the five textures do differ, and the shapes are owed to the operator.
  - `[false]` `[reject]` (blind) The Flagship's `sprite_px` has two sources of truth. — `boss.hull.width_px` is 720, the scene's value, so nothing changes. The only other `sprite_px` reader, `Enemy._entry_start_for`, is never used by the boss, and a width retune now moves the hull art with the hitbox, as intended.
  - `[low]` `[reject]` (blind) The importer doesn't verify zip hashes, and its writes aren't atomic. — It's a one-shot tool that renders every row in memory before writing. The zip hashes are recorded and were checked by hand. The same reasoning applied to Story 8.1's importer.
  - `[low]` `[patch]` (edge) A truncated PNG makes `_header` raise `struct.error`, which escapes `main` with a traceback. — Added `struct.error` to `main`'s except tuple, plus `test_truncated_png_source_exits_1`.
  - `[low]` `[reject]` (edge) `_read_rgb` doesn't detect a truncated chunk body. — It still fails loudly: the zlib or size check raises, and `main` exits 1. Only the message is vaguer.
  - `[low]` `[reject]` (edge) The baked rim rotates with the asteroid. — Same as the blind row above.
  - `[low]` `[patch]` (edge) `SpriteProbe.max_channel` null dereference. — Same fix as the blind probe row.
  - `[low]` `[reject]` (edge) The Level 3 card's thumbnail shows the throne-world arc, beyond "Level 3 and the end screen only". — DESIGN.md's Level Select calls for each card to show its level's background, so the card is a preview of Level 3. Whether it spoils the reveal is in `operator_actions`.
  - `[low]` `[reject]` (edge) `rim` acts on every pixel with alpha > 0, not only opaque pixels. — The soft edge pixels are the rim. The effect is cosmetic, and the tests cover it.
  - `[low]` `[patch]` (verification-gap) The RGB decoder's filter types 2, 3 and 4 are never tested. — `rgb_png` now encodes filters 0–4. Added `test_rgb_reads_every_filter_type` (exact pixels) and `test_rgb_unknown_filter_type_is_refused`.
  - `[low]` `[defer]` (verification-gap) No test observes `LevelBackground._draw` drawing the tiles. — Headless runs use the dummy renderer. Closing it needs a draw-call recording seam, and the operator's look covers it meanwhile. Deferred.
  - `[low]` `[reject]` (intent) The status isn't `awaiting-operator` with `operator_actions`, and perceptual ACs are only in prose. — This finalization records them: `status: awaiting-operator` plus the `operator_actions` list, as Story 8.1 did.

## Design Notes

Kenney Future at 28 px is about 42% wider than the fallback font, which breaks the 200-character, 4-line story-panel contract. DESIGN.md anticipated this ("Kenney Future Narrow for long comms text if needed"), but Narrow can't be obtained from any reachable source. So dialogue text alone keeps the engine font, and all labels, names, buttons, headings and the HUD use Kenney Future. That is a one-line Theme revert if the operator supplies Narrow. Kenney has no portraits and no hull at 720×140, hence the project-owned SVGs: Godot imports SVG as a texture. No one has looked at any pick yet; fit and look are owed to the operator.

## Verification

**Commands:**
- `uv run python -m unittest tools/test_import_cc0_art.py tools/test_import_cc0_audio.py tools/test_recolor_player_ship.py tools/test_gen_placeholder_sfx.py` -- expected: OK
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0, no import errors
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all pass, no new orphans
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --path game -- --bench=20` (windowed) -- expected: `Stress bench:` p99 < 16.6 ms, recorded in the Auto Run Result
- `git status --porcelain --ignored` -- expected: no zips, pack folders, `__pycache__` or unused pack files

## Auto Run Result

Status: awaiting-operator

**Summary.** The art pass is in. A new stdlib importer, `tools/import_cc0_art.py`, recolours CC0 Kenney Space Shooter Redux and Extension sprites to the palette:
- five distinct magenta enemy hulls, plus the Wasp in orange for the Hunter;
- the cyan ally fighter, Tarek's darkened damaged hull and the dimmed convoy cargo hulls;
- the Flagship turret and core;
- three hazard-grey asteroids with a baked rim light;
- two space backgrounds that never bloom;
- the Kenney Future font.

The three comms portraits and the Flagship hull are project-owned SVGs. `SpriteFit` fits every sprite from the existing size data, so gameplay is unchanged. The space tiles now show in levels, the title, the story scene and the Level Select thumbnails. Kenney Future is the Theme's default font, but dialogue (story panel, interruption box, pause-menu recent comms) keeps the engine font, because it is too wide and Kenney Future Narrow is not obtainable (decision #66, provisional). Every file under `game/assets/` is credited, and a data test enforces it. Only a person playing the game can judge the look, so the story is `awaiting-operator` (see `operator_actions`).

**Files changed**
- `tools/import_cc0_art.py` and `tools/test_import_cc0_art.py` (new): the importer and its tests.
- `game/assets/sprites/{enemies,allies,boss,asteroids}/*`, `backgrounds/space_{1,2}.png`, `fonts/kenvector_future.ttf`, `portraits/portrait_{isolde,tarek,ryn}.svg`, `sprites/boss/flagship_hull.svg` (each with its `.import` file): the new art.
- `game/core/sprite_fit.gd` (new) and `core/enemy.gd`: the uniform fit; `Enemy` fits its body sprite to `sprite_px`.
- Enemy, Ram, Flagship, turret and core scenes and scripts: placeholder polygons replaced by `Sprite2D`s.
- `game/entities/allies/ally_ship.*` and `convoy_ship.*`: the hull sprites, and the swap to the damaged hull.
- `game/entities/asteroids/asteroid.*`: the meteor sprite for each size.
- `game/scenes/level/level_background.gd`: tiled textures, with the throne world over `space_2`.
- `title.*` and `story.*`: a `space_1` backdrop.
- `level_select.gd`: backdrop thumbnails.
- `level.tscn`: the banner uses the Theme type.
- `game/systems/comms/comms_portraits.gd` (new), plus `comms_panel.*`, `comms_box.*` and `game/ui/menus/pause_menu.gd`: portraits and the dialogue fonts.
- `game/ui/theme/defector_theme.tres`: the default font, the base-less dialogue fonts and the `LevelClearBanner` type.
- Tests:
  - `test_neon_art.gd` and `tests/fixtures/sprite_probe.gd` (new);
  - the updated pins in the enemy, Flagship, Ram, ally, convoy, asteroid, LevelBackground, Level Select, title, story, comms and pause-menu tests;
  - the asset credits check in `test_data_files.gd`.
- `game/assets/CREDITS.md`: a row for every new file.
- Docs: decision log #66, the architecture's as-built Story 8.2 section and its tree, `epic-8-context.md`, and a typography note in DESIGN.md.

**Review findings.** 24 findings: low 21, false 3, no high, medium or maybe-false.
- **Patched (6 entries, all low):**
  - The pause-menu recent comms now use the engine font.
  - DESIGN.md has a typography note.
  - The `SpriteProbe.max_channel` null guard.
  - The importer catches `struct.error`, with a new test.
  - Tests for the RGB decoder's filters 2–4 and an unknown filter.
- **Deferred (3, low):** the stale arc geometry in the Story 7.6 architecture bullet (pre-existing), a flaky real-time ally test (pre-existing), and no test of the `_draw` tiling (headless).
- **Rejected:**
  - convoy solid margin (partly false)
  - large asteroid hitbox (no worse than the old polygon)
  - ally fitted size
  - kept shape data
  - portrait corners
  - Ram size (false)
  - glyph fallback (false)
  - rotating rim (×2)
  - Flagship `sprite_px` (false)
  - importer hashes and atomic writes
  - truncated RGB chunk message
  - Level 3 thumbnail arc
  - rim on soft edge pixels
  - the spec bookkeeping and status (handled by this finalization)

  Each has its reason in the Review Triage Log.

**Follow-up review recommendation: false.** No high or medium entry was patched; the 6 patched entries were all low.

**Verification**
- After the patches:
  - Tool unit tests: 57 tests, OK.
  - Headless `--import`: exit 0.
  - Full GUT run: 98 scripts, 2032/2032 passing.
  - `git status`: no zips, no pack folders, no `__pycache__`.
- Before the patches, `--bench=20` (windowed): `frames=4832 avg=4.14 ms p99=8.94 ms max=14.54 ms enemies=40 projectiles=201 window=(1920, 1080) result=PASS`. The patches changed no rendering path, only the pause-menu font and tests.
- Every row of the I/O matrix is covered by a test that ran and passed.

**Residual risks.** Nobody has looked at any pick in the running game: silhouettes, orientation, convoy dimness, portraits, the Flagship hull, the rim light, the tile seams and the font are all owed to the operator. Kenney's flat style plus bloom on white hull parts may read differently from "clean neon" in play.

Implementer notes (first pass):
- Importer: both zips matched their SHA-256; `tools/import_cc0_art.py` wrote all 17 rows, and a second run into a separate folder was byte-identical. Every output PNG was viewed for colour and orientation.
- `uv run python -m unittest tools/test_import_cc0_art.py tools/test_import_cc0_audio.py tools/test_recolor_player_ship.py tools/test_gen_placeholder_sfx.py`: OK.
- Headless `--import`: exit 0, no import errors.
- GUT: 98 scripts, 2032 tests, 2031 passing, 1 pre-existing timing-dependent pending (`test_feedback.gd` hit-stop), 0 failing, no orphans. `test_level.gd` `test_dev_ally_level_spawns_tarek_who_fires_and_scores` (a real-time ally-kill test) failed once in an early run and passed in the full run and alone afterwards.
- `--bench=20` (windowed): `frames=4415 avg=4.53 ms p99=9.75 ms max=14.32 ms enemies=40 projectiles=201 renderer=forward_plus window=(1920, 1080) vsync=0 result=PASS`.
- No font size retune was needed; decision #66 recorded (provisional).

## Operator Confirmation

Confirmed 2026-10-14: the external actions this story owed were carried out.

- Play Level 1, Level 2 and Level 3 in a debug build ("<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game) and judge every new sprite in motion: the five enemy silhouettes (Wasp, Lancer, Needle, Bastion, Maul) and the orange Hunter Wasp, with each one pointing its nose toward the player (check the Needle, Bastion and Maul, which come from the Extension pack, in particular); the cyan ally fighter; the dimmed convoy hulls reading as civilian cargo; and the Ram in Tarek's fall.
- Judge the asteroids: grey-brown, jagged, with the rim light baked on the upper-left edge (the light turns as the rock spins). Say whether that reads well or needs a non-rotating rim.
- Play Level 2 to Tarek's fall and confirm his hull swaps to the darkened, battle-damaged sprite with the fire trail when he is hit.
- Fight the Flagship in Level 3 and judge the project-owned SVG hull against the Kenney turrets and core (mounts lined up, the Eye pulse readable, no bloom blob), and check that the throne-world arc still reads as a reveal over the space_2 tiles.
- Look at the two space backgrounds (space_1 in Level 1, the title and the story scene; space_2 in Level 2): no visible tile seams, dark enough, no bloom. Also check the Level Select thumbnails, including the throne-world arc shown on the Level 3 card.
- Read the comms in the opening and in a fight: judge the three SVG portraits (Isolde, Tarek, Ryn) in the 200 px story panel and the 88 px interruption box.
- Judge the Kenney Future font on the title, menus, HUD labels, names and buttons. Approve or reject decision #66's reading that dialogue text (story panel, interruption box, pause-menu recent comms) and the story-panel cue keep the engine font, because Kenney Future Narrow could not be downloaded (kenney.nl returns 403). If you can supply Kenney Future Narrow, add it and switch the dialogue fonts to it.
- Approve or replace any pick in tools/import_cc0_art.py ROWS or the SVGs, then record the outcome in decision #66 of the decision log (it is marked provisional).

_Appended by the bmad-loop orchestrator (`bmad-loop confirm`, #335): a human confirmed these external actions out of band, and the story was advanced from `awaiting-operator` to `done`._
