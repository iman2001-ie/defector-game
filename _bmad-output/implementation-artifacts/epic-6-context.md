# Epic 6 Context: Escort and Allies

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Give the player a second thing to care about besides their own ship. In Level 1 the player escorts a three-ship cargo convoy that shares one health bar. Mauls dive at the convoy and Lancers split their fire between the player and the cargo. Invincible allies fly alongside: Tarek in Levels 1–2 and Ryn in Level 3. Tarek's scripted fall at the Blockade is the story moment the game is built to be remembered for. The convoy, the Maul and Lancer convoy targeting are MUST. Allies and Tarek's fall are SHOULD, and Tarek's fall is the last SHOULD story to cut. The Maul and Lancer convoy targeting moved here from Epic 2 because they only matter once a convoy exists.

## Stories

- Story 6.1: Protect the Convoy
- Story 6.2: Stop the Mauls Before They Hit the Convoy
- Story 6.3: Defend the Convoy from Lancer Fire
- Story 6.4: Fly Alongside Tarek and Ryn (SHOULD)
- Story 6.5: Lose Tarek at the Blockade (SHOULD, last to cut)

## Requirements & Constraints

- **Convoy (level JSON `"convoy": true`):** three medium cargo ships (~160×80 px, hitbox ~80% of the sprite) in a tight triangle, with the lead about 40 px ahead of two flankers. The group moves as one at 40 px/s within y 760–920. They share one 100 HP pool, which carries across waves and refills only when the level restarts.
- **Convoy path (decision #45):** the group starts fully on-screen at the left side of the band, heading right, clear of the player spawn (960, 900). At each screen edge it turns around before any hull leaves the screen and flies back the other way (ping-pong). The triangle is mirrored so the lead ship still leads. It never wraps off-screen, so the cargo is always visible when it is hit. Wrap-around and fly-in starts were rejected.
- **Convoy loss:** when HP reaches 0, `Events.level_failed(&"convoy")` runs the same retry flow as death: prompt, then restart from wave 1 with energy reset.
- **The convoy is solid to every projectile.** Any enemy shot that touches it stops and does damage: 5 if it was aimed at the convoy (`targets_convoy`), or `damage.convoy_stray` (2) if it was a stray. Bastion shots, Needle shots and player-aimed Lancer shots count as strays. A Maul impact does 10. Player and ally shots (lasers, missiles, Barrage micro-missiles, ally fire) are blocked and free themselves with no damage, so there is no friendly fire.
- **Missile fizzle (decision #46, DW-33):** a player missile or Barrage micro-missile stopped by a convoy ship does not explode. There is no splash on nearby enemies or asteroids and no convoy damage, only the same small blocked-shot effect a laser bolt gets. The player still has to fire around the convoy. Detonate-with-splash was rejected.
- **The convoy is solid to the player's ship.** The ship is pushed out with no damage and slides along the hull. The player can body-block convoy-aimed shots and take the heart instead (subject to i-frames and Shield).
- **Maul** (6 HP, medium tier): enters from the side with a red engine trail and an alarm ping, then dives straight at the nearest convoy ship at 400 px/s. It never steers toward the player. When it hits the convoy it does 10 damage and self-destructs. If it misses (leaves the playfield), or the level has no convoy, it resolves without a kill and counts as cleared. If it touches the player, the player loses 1 heart (subject to i-frames and Shield), the Maul is destroyed by contact and the convoy takes nothing. Only a Maul killed by the player or an ally (body-block included) rolls `drops.maul` (25%).
- **Lancer convoy targeting:** in a convoy level each shot aims at the player or at a random convoy ship, 50/50. Without a convoy it always aims at the player.
- **Allies** (level JSON `"ally": "tarek"|"ryn"`): cyan/teal ships that patrol scripted horizontal paths within y 620–760 at 150 px/s. Every 0.5 s an ally fires a 1-damage shot at the nearest enemy. Allies can't be damaged and block nothing. They should get roughly 10–15% of kills. If the share is off, tune `tuning.allies` (never code) and log the change in the GDD decision log.
- **Tarek's fall** (`tarek_fall` flag, Level 2 Wave 5 at 50% destroyed): Tarek's ship moves over Vale with a shield flash, swaps to a damaged variant, trails fire, stops firing and leaves for the rest of the level. His cut-off line plays as an interruption (no pause). Then come the static, the dedicated cut-off shake (18 px for 0.9 s, which replaces the story's "Large-tier shake"), the music dropping out, and comms silence until the wave clears. With the flag off, nothing happens, Tarek keeps flying and the wave still clears.
- All numbers come from `tuning.json` (`convoy`, `allies`, `damage`, `enemies.maul`, `drops.maul`) through `Config`. Never hard-code them. Every telegraph lasts at least 0.3 s.

## Technical Decisions

- **Collision layers:** `convoy` (7) and `allies` (8) detect nothing. `player_shots` (ally shots included) masks `enemies`, `asteroids` and `convoy`. It masks `convoy` only so the shot gets blocked: the projectile never calls `apply_damage` on the convoy. `enemy_shots` masks `player`, `asteroids` and `convoy`. On the `enemies` layer, only the Maul masks `convoy`. Use the `CollisionLayers` and `Groups` constants, never literal numbers or strings.
- **Only one side applies damage:** an enemy projectile damages the convoy (the aimed or stray amount), the Maul calls `convoy.apply_damage(10)` itself, and the Player handles its own contact damage.
- **Player vs convoy:** the Player gets a separate ~64 px `HullArea` circle that masks only `convoy`. The 24 px hurtbox stays as it is. The move from the previous position to the cursor target is swept (a shape cast against `convoy`), then the ship is pushed out along the shortest separation. After any block or push, warp the cursor to the ship using viewport coordinates. If the push-out and the zone clamp disagree, the push-out wins along y.
- **Ownership:** the `Convoy` node owns convoy HP for one level attempt and broadcasts `Events.convoy_hp_changed(current, max_hp)`. The HUD convoy bar reads only that signal. The convoy and allies sit under `World/Allies`. Their files are in `entities/allies/` (`ally_ship`, `convoy`, `convoy_ship`) and `ui/hud/convoy_bar.gd`.
- **Spawning:** only `Spawner` instantiates entities, through `EntityRegistry` preloads, and it calls `setup(params)` before `add_child`. `&"maul"` is already a known type id. Behaviour uses `enum State` + `match` with `_enter_state()`.
- **Enemy contract:** `resolved` is emitted exactly once. A Maul miss counts as resolved but not as a kill. `apply_damage(amount, source)` records `source.from_ally`, and kills report `by_ally` in `Events.enemy_killed`. Every death goes through `Enemy._die()`, which drops the loot.
- **Ally shots** are `player_shots` projectiles with `from_ally = true`. An ally picks the nearest enemy again on each 0.5 s shot, not every frame.
- **Tarek's fall is data plus a `story_event`:** a WaveDirector trigger runs `story_event: tarek_fall` (which emits `Events.story_event_requested`) and `comms: l2_w5_tarek_cutoff`. `CommsChannel` already provides the cut-off, the static, the `"shake": "cutoff"` shake, the music stop and the silence until the wave clears. The ally reacts only to the story event. A flag gates only its own beat, so anything that must happen either way goes into both triggers of a flag pair.
- The first level outcome wins. After `level_failed`, the WaveDirector freezes progress.
- One summary line in the architecture still says only convoy-targeted shots and Mauls can hit the convoy. That line is out of date. The current rule is that every enemy shot hits the convoy (5 if aimed, 2 if stray).

## UX & Interaction Patterns

- **Convoy bar:** top right, 320×12 px at y 104 under the energy bar, Level 1 only. The fill is `coalition`. A `CONVOY` label in `muted` 20 px sits right-aligned just left of the bar. The bar is thinner than the energy bar. It flashes `danger` once when the convoy takes damage, and the label pulses below 30%.
- **Convoy loss** uses the existing retry prompt with the reason `CONVOY LOST`, then offers RETRY · QUIT TO TITLE. A retry doesn't replay the briefing.
- **Visuals:** allies and the convoy are `coalition` in the world. Convoy hulls are dimmer so they read as civilian cargo. Speaker accent colours appear only in the comms UI. The Maul needs its own silhouette. A missile blocked by the convoy shows only the blocked-shot effect, never an explosion.
- No persistent HUD goes in the player zone (y ≥ 432). Tarek's cut-off line shows in the top-left interruption box, which hides at once when the static ends.

## Cross-Story Dependencies

- 6.1 comes first: 6.2, 6.3 and 6.5 all need the convoy node, its `apply_damage`, its HP signal and its loss condition.
- 6.3 builds on the Lancer, `EnemyBullet` and `Projectile._can_damage` from Story 2.5. The missile fizzle in 6.1 changes the existing missile and Barrage detonation path (Epics 1 and 3). 6.2 relies on Player contact and i-frames (3.1), loot (3.3) and Shield (3.4).
- 6.5 needs the ally ship from 6.4. Its comms side (cut-off, silence, music stop, the `story_event` action) comes from Epic 5 (Stories 5.3, 5.4 and 5.7).
- Epic 7 puts all of this into the real levels: the Level 1 convoy with Mauls, Tarek's fall in Level 2 Wave 5, and Ryn in Level 3. Epic 6 proves each feature in dev levels first. Until Epic 7, the placeholder `level_1/2/3.json` files have `convoy` set to false.
