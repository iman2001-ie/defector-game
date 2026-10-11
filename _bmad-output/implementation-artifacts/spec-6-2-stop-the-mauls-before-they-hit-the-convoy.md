---
title: 'Story 6.2: Stop the Mauls Before They Hit the Convoy'
type: 'feature'
created: '2026-10-10'
status: 'done'
baseline_revision: 'f637ac45f0625a1e5ffdf856a169ff305241f382'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-6-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Level 1's convoy needs its main threat, the Maul (FR23, MUST). It is a suicide diver that ignores the player and rushes the cargo. The tuning (`enemies.maul`, `drops.maul`, `damage.convoy_maul`, `damage.maul_contact_hearts`) and the convoy from Story 6.1 exist, but no `maul` scene exists and `&"maul"` is not in `EntityRegistry.ENEMIES`, so a level can't spawn one.

**Approach:** Add `Maul extends Enemy` (6 HP, medium tier). It spawns just off-screen on its `entry` side, plays an alarm ping and shows a red engine trail, then flies in a straight line at 400 px/s toward the convoy ship nearest to it at spawn. On touching a ConvoyShip it deals `damage.convoy_maul` and self-destructs without a kill. If it leaves the playfield, or there is no live convoy, it resolves without a kill. Contact with the player and kills by the player use the existing Enemy and Player paths. Register it, make it rowless, add a Maul wave to the dev convoy level, and generate a placeholder alarm SFX.

## Boundaries & Constraints

**Always:**
- Every number comes from `tuning.json` through `Config` (`enemies.maul.*`, `damage.convoy_maul`, `damage.maul_contact_hearts`, `drops.maul`). Static typing everywhere. Only the Spawner instantiates the Maul. Use `CollisionLayers`/`Groups` constants in code, never literals.
- `resolved` is emitted exactly once, on every path (kill, convoy hit, miss, no convoy). A convoy hit or a miss emits no `Events.enemy_killed` and drops no loot (decision F18). A kill by the player or an ally, contact included, goes through `Enemy._die()` (kill event plus a `drops.maul` roll).
- The heading is fixed at spawn and never changes, so the Maul never steers toward the player (or anything else).
- No per-frame allocation or group lookup in the Maul's step: look up the convoy once, at spawn.
- Write the failing GUT test first.

**Never:**
- No Lancer convoy targeting and no aimed/stray amounts (6.3). No allies (6.4). Don't put Mauls in `level_1/2/3.json` (Epic 7).
- Don't change the Convoy, ConvoyShip, Projectile or WaveDirector logic. Data-driven additions such as `ROWLESS_TYPES` are fine.
- No image asset: the hull and trail are drawn as polygons. The only new audio is a project-generated placeholder.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Spawn with convoy | `slot` (x ≤ 960), `entry: sides`, live convoy | Starts at `(−sprite/2, slot.y)`; `maul_alarm` SFX plays once; heading = unit vector toward the nearest ConvoyShip's centre at spawn; trail visible | — |
| Right-side spawn | slot x > 960 | Starts at `(1920 + sprite/2, slot.y)`, same targeting | — |
| Top entry / no slot | `entry: top`, or no `slot` | Top: above the slot (`_entry_start_for`). No slot: at `position`. Targeting is the same | Unknown entry warns and uses top (existing) |
| Dive | each step | Moves `dive_speed_px_s × delta` along the fixed heading; the player's position has no effect | — |
| Convoy hit | Maul area enters a ConvoyShip | `ship.apply_damage(damage.convoy_maul, maul)` once; `Feedback.impact(tier)`; `resolved`; freed; no `enemy_killed`, no loot | Already dead: ignored |
| Miss | Entered the playfield, then fully outside it (beyond the sprite half) | `resolved` without a kill, freed, no feedback, no loot | — |
| No convoy | No live `Groups.CONVOY` node, or the convoy `is_lost()`, at spawn | `resolved` without a kill on its first step (never inside `_ready`, so the WaveDirector's connection is live), freed | Logged once at DEBUG |
| Shot down | Player/ally damage takes HP to 0 | `_die()`: kill event (`by_ally` as recorded), `drops.maul` roll, resolved | — |
| Body-block | Maul overlaps the Player | Player loses `damage.maul_contact_hearts` (i-frames and Shield as existing); Maul `destroy_by_contact()` → `_die()` (kill and loot roll); convoy unchanged | — |

</intent-contract>

## Code Map

- `game/core/enemy.gd` -- the base: `setup` (position/slot/entry), `_ready` (hp, tier, circle hitbox from `sprite_px × hitbox_ratio`, joins `Groups.ENEMIES`), `_die()` (feedback, `enemy_killed`, loot, `resolved`, free), `destroy_by_contact()` (small/medium), `_entry_start_for(target)` (side: nearer edge at `target.y`; x ≤ 960 counts as left). The no-kill resolution helper goes here.
- `game/entities/enemies/hunter_wasp/hunter_wasp.gd` + `.tscn` -- the closest template: `_init` sets `type_id`, `_ready` calls `super()` then starts from `_entry_start_for(_slot)`, `step(delta)` is public and driven by `_physics_process`, `rotation = heading.angle() − PI/2` (nose down), Polygon2D `Hull`, layer 4, mask 0, monitoring off.
- `game/entities/enemies/lancer/lancer.tscn` -- the medium-tier `sprite_px` 96 and the additive-glow pattern (GradientTexture2D + CanvasItemMaterial blend add).
- `game/entities/allies/convoy.gd` -- `Groups.CONVOY` node; `ships() -> Array[ConvoyShip]`, `is_lost()`. `convoy_ship.gd` `apply_damage(amount, source)` forwards to the Convoy (which ignores damage after a loss or a clear).
- `game/entities/player/player.gd` -- `on_contact` (l.377): a medium enemy costs `_enemy_contact_cost(tier)` and is destroyed by contact; `_enemy_contact_cost` (l.406). The Maul's cost moves to `damage.maul_contact_hearts`.
- `game/autoloads/entity_registry.gd` -- `ENEMIES` (no `maul` yet) and `ROWLESS_TYPES` (`[&"hunter_wasp"]`).
- `game/systems/waves/wave_director.gd` -- `_spawn_entry` (l.320) passes `position`, `slot`, `formation` and `entry`, then connects `resolved` after `spawn_enemy` returns. Read-only.
- `game/autoloads/audio.gd` -- the `SFX` dictionary (l.19) and `play_sfx(id)`.
- `tools/gen_placeholder_sfx.py` -- deterministic generator; each sound after 1.6 has its own seed constant; `main()` writes every sound (the existing WAVs must come out byte-identical).
- `game/assets/CREDITS.md` -- the project-generated placeholders table.
- `game/data/levels/level_dev_convoy.json` -- 2 waves; `tests/data/test_data_files.gd` `test_dev_convoy_level_shape` (l.1113) asserts 2 waves of Wasps and Lancers only.
- `game/tests/unit/test_hunter_wasp.gd` -- the test pattern (instantiate the scene, `setup`, `add_child_autofree`, drive `step`, capture `Log.sink`, reset `Config`/`PauseArbiter`/`Feedback`). `test_spawner.gd` l.52–68 checks the known type ids. `test_level.gd` l.1224+ runs `dev_convoy` on the real `level.tscn`.
- `_bmad-output/game-architecture.md` -- the source tree lists `maul/` (l.616); the registry sample (l.1133); the as-built sections end at `## As-built 2026-10-10 (Story 6.1)` (l.1805), whose "Not built here" names the Maul.

## Tasks & Acceptance

**Execution:**
- `game/core/enemy.gd` -- add `_resolve_without_kill(play_feedback: bool)`: when not dead, set dead, optionally `Feedback.impact(tier, global_position)`, emit `resolved`, `queue_free()`. No `enemy_killed`, no loot. Document it next to `_die()`. -- Shared no-kill exit (F18).
- `game/entities/enemies/maul/maul.gd` + `maul.tscn` -- `class_name Maul extends Enemy`, `type_id &"maul"`, `sprite_px` 96. The scene has layer 4, a `Hitbox`, a distinct Polygon2D `Hull` in `enemy` `#FF2BD6` (a heavy wedge or ram shape, unlike the Wasp, Lancer, Needle, Bastion and Hunter), and a `Trail` behind the nose: a tapered polygon in `danger` `#FF1F4B` with an additive glow. `_ready`: `super()`; set `collision_mask = CollisionLayers.CONVOY` and `monitoring = true`; connect `area_entered`; position from `_entry_start_for(_slot)` when it has a slot; play `&"maul_alarm"`; find the convoy once (`Groups.CONVOY`) and aim at the ship whose centre is nearest; set `rotation` from the heading. `enum State { DIVE, DONE }` with `_enter_state()`. `step(delta)`: no target means `_resolve_without_kill(false)`; otherwise move along the heading, track `entered` (inside the playfield rect), and resolve as a miss once entered and fully outside. `_on_area_entered`: a ConvoyShip → `apply_damage(Config.int_("damage.convoy_maul"), self)`, then `_resolve_without_kill(true)`. Public `heading()` and `target_ship()` for tests. -- FR23.
- `game/autoloads/entity_registry.gd` -- add `&"maul"` to `ENEMIES` and to `ROWLESS_TYPES` (it never holds its slot; update the comment). -- Levels can spawn it.
- `game/entities/player/player.gd` -- in the enemy contact cost, a Maul (`enemy is Maul`) costs `damage.maul_contact_hearts`, cached in `_ready`; other enemies are unchanged. Update the contact doc comment. -- Decision #20 data key.
- `tools/gen_placeholder_sfx.py` -- add `maul_alarm` with its own seed: a short two-tone alarm ping, ≤ 0.5 s. Re-run it with `uv run python tools/gen_placeholder_sfx.py` and confirm `git status` shows only the new WAV changed. Then `game/autoloads/audio.gd` (`&"maul_alarm"` entry), `game/assets/CREDITS.md` (placeholder row), and run `--import` so the `.wav.import` sidecar exists. -- The alarm SFX.
- `game/data/levels/level_dev_convoy.json` -- add a third wave: `{ "type": "maul", "count": 4, "formation": "grid_4x1", "entry": "sides" }` plus 2 Wasps (top). Update `test_dev_convoy_level_shape` so waves 1–2 stay as they are and wave 3 holds Mauls. -- A playable proof.
- `game/tests/unit/test_maul.gd` (new) plus additions to `test_enemy.gd`, `test_player*.gd` (contact cost), `test_spawner.gd` (known type, spawns a Maul), `test_audio.gd` if it pins the SFX ids, `test_data_files.gd`, and a real-scene test in `test_level.gd` (`dev_convoy` Maul wave: a Maul on its dive hits the convoy and convoy HP drops by 10) -- cover every I/O-matrix row and each AC. Check the layer and mask against the constants. Run `--import` after adding `class_name Maul`.
- `_bmad-output/game-architecture.md` -- append `## As-built 2026-10-10 (Story 6.2)`: files, heading locked at spawn, the no-convoy rule, `_resolve_without_kill`, the rowless Maul, the SFX, tests, and the `-- --level=dev_convoy` launch line. -- Docs match the as-built.

**Acceptance Criteria:**
- Given `dev_convoy` running on `level.tscn` at its Maul wave, when the Mauls spawn, then each starts off-screen on its side, the alarm ping plays and the trail shows. Each dives in a straight line at 400 px/s toward the convoy ship nearest it at spawn. The time from spawn to reaching the convoy band is at least the 0.3 s telegraph minimum.
- Given a Maul touching a ConvoyShip, then convoy HP drops by exactly 10 (`convoy_hp_changed` emitted), MEDIUM death feedback plays, `resolved` fires once, no `enemy_killed` fires, no orb spawns, and the Maul is freed.
- Given a Maul whose straight line misses, or no convoy in the level, when its dive ends, then it resolves without a kill and frees itself, and the WaveDirector counts it, so a wave of only Mauls clears.
- Given a diving Maul, when the player moves anywhere, then its heading is unchanged.
- Given a Maul killed by player shots, or destroyed by body-block contact, then `enemy_killed(&"maul", …)` fires and `drops.maul` is rolled (with chance forced to 1 in the test, an orb spawns). Given body-block, the player loses `damage.maul_contact_hearts` (none during i-frames or Shield, but the Maul is still destroyed), and the convoy is unchanged.
- Given the full GUT suite, when it runs headless, then every test passes, with no new orphans or errors.

## Spec Change Log

## Review Triage Log

### 2026-10-10 — Review pass
- verdicts: 22 findings — high 0, medium 3, low 10, false 9, maybe-false 0
- findings:
  - `[false]` `[reject]` (blind) Wasp shots in wave 3 could hit the convoy and break the level test's 10-per-hit checks — `wasp.gd` never calls `spawn_projectile` (Wasps only dive), and Wasps don't mask `convoy`, so only Mauls can change convoy HP in that wave.
  - `[low]` `[reject]` (blind) Four alarm pings stack in one frame for a 4-Maul batch — real but mild: the 12-player pool is far from exhausted. Fixing it needs per-frame dedupe state in Audio, a new guard for a feel question. Listed for the operator feel check.
  - `[low]` `[reject]` (blind) With no convoy the alarm and trail still play before the Maul silently resolves — Mauls only appear in convoy levels (dev_convoy now, Level 1 in Epic 7), so players won't meet this. The fix adds a branch.
  - `[false]` `[reject]` (blind) A Maul that never enters the bounds never resolves — wave Mauls always have a slot and start exactly on the grown-bounds edge (`_entry_start_for` uses sprite/2, the bounds are grown by sprite/2), aimed at an on-screen ship centre, so the first step is strictly inside. A slotless spawn happens only in sandbox/tests.
  - `[low]` `[reject]` (blind) Player hard-codes `enemy is Maul` instead of a data-driven per-enemy cost — the spec prescribed it to use the existing `damage.maul_contact_hearts` key. The only harm is a branch per future special-cost enemy, and none is planned.
  - `[false]` `[reject]` (blind) The telegraph check doesn't measure a real Maul path — `test_dev_convoy_maul_wave_hits_the_convoy` computes the time to the band from each real Maul's start and heading, and checks ≥ 300 ms elapsed before the first hit.
  - `[medium]` `[patch]` (blind) Heading lock weakly tested; the per-Maul await in the level test shifts timing — the timing part shares its root cause with the edge rows below, patched there. The heading itself is assigned only in `_aim_at_convoy`, so it is structurally locked.
  - `[low]` `[patch]` (blind) No test for hitting a non-target ship or for a freed target; `target_ship()` can return a freed instance — patched `target_ship()` to return null for a freed ship. Hitting any ConvoyShip is handled generically in `_on_area_entered`, and the convoy is never freed mid-level, so no extra tests.
  - `[low]` `[reject]` (blind) `_has_target` duplicates `_target != null` — both are set once at spawn and only gate the no-convoy exit. They can't drift in play.
  - `[low]` `[reject]` (blind) `test_mauls_only_in_dev_levels` substring-matches `"maul"` — level files hold dialogue ids, not text, so a bare `"maul"` string appears only as a type. A false positive would fail loudly, and parsing would add code for no reachable case.
  - `[low]` `[patch]` (blind) The edited ROWLESS_TYPES comment's "it" is ambiguous — reworded to "so such an entry may share a row with the next one".
  - `[false]` `[reject]` (blind) The readings aren't in the decision log, and the spec isn't in the diff — AGENTS.md logs decisions the user makes. These are record-only readings, documented in the architecture's as-built section, and no design decision changed. The spec is committed with the change.
  - `[low]` `[reject]` (edge) `dive_speed_px_s` ≤ 0 would make a Maul never enter — that needs broken tuning (shipped 400), and `test_maul_tuning_ranges` asserts > 0. A runtime guard adds a branch for data no build ships.
  - `[medium]` `[patch]` (edge) The level test's per-Maul `await` lets later Mauls drift past the 2-frame y tolerance (flaky) — patched: every Maul's position and heading are snapshotted before any await, the assertions run on the snapshot, then one frame passes and the heading lock is checked.
  - `[medium]` `[patch]` (edge) Same root cause: the second steep Maul has about 0.3 px of margin — fixed by the same snapshot patch.
  - `[low]` `[patch]` (edge) `target_ship()` returns a freed instance after the convoy is freed — same patch as the blind row (an `is_instance_valid` check).
  - `[false]` `[reject]` (intent) Not finalized as awaiting-operator — the ACs have no action a human must do outside the repo. The play-feel check is an in-repo operator note, so the R1 close-out applies.
  - `[false]` `[reject]` (intent) One straight flight (B1) rather than fly-in-then-dive or homing — "dives straight" plus `enemies.maul` holding only `dive_speed_px_s` select B1. Homing would make the GDD's "misses" impossible. Recorded as a reading in the as-built section.
  - `[false]` `[reject]` (intent) The convoy damage goes through `ConvoyShip.apply_damage` rather than `convoy.apply_damage` — `ConvoyShip.apply_damage` forwards to `Convoy.apply_damage`, and the tests assert the Convoy's HP drops by 10 with `convoy_hp_changed`.
  - `[false]` `[reject]` (intent) A separate contact key instead of the medium cost — `damage.maul_contact_hearts` is the GDD damage table's Maul row (1 heart, the same as medium contact). Using it is the data-driven reading.
  - `[low]` `[reject]` (intent) Body-block is exercised only through `on_contact`, not on the real level — the hurtbox → `on_contact` wiring is existing, tested Player code. The level test parks the Player so the convoy hit is deterministic. A second real-scene test would mostly duplicate coverage.
  - `[false]` `[reject]` (intent) The 0.3 s telegraph assertion adds an unstated constraint — the epic context requires "every telegraph lasts at least 0.3 s".

## Design Notes

**Readings this spec records (no GDD conflict).** "Enters from the side, then dives straight at the nearest convoy ship" is built as one straight flight. The Maul spawns just off-screen at its slot's y, already aimed. The alarm ping, the trail and the off-screen start are the telegraph. `enemies.maul` has only `dive_speed_px_s`, with no entry speed or hover time, so a separate fly-in or hold phase would need invented numbers. The aim is the target ship's centre at spawn, with no lead and no re-aim, because the GDD says "straight". A miss is possible only because the convoy moves 40 px/s, and the GDD expects misses. With no convoy there is nothing to dive at, so the Maul resolves on its first step without flying. Doing it in `_ready` would fire before the WaveDirector connects `resolved`. The Maul is rowless like the Hunter Wasp, because it never holds its slot.

**Miss test.** Using `Playfield.SIZE` grown by `sprite_px / 2` on every side: the Maul starts outside that rect (on its edge), so it only counts as a miss after it has been inside once.

## Verification

**Commands:**
- `uv run python tools/gen_placeholder_sfx.py` then `git status --short game/assets/audio` -- expected: only `sfx_maul_alarm.wav` is new; no existing WAV is modified
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0 (new `class_name`, new WAV)
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass (see `LOCAL.md` for `<GODOT_DIR>`)

**Manual checks (if no CLI):**
- Operator (feel, not verified by tests): run `level.tscn -- --level=dev_convoy` to wave 3. Check that the Maul silhouette and red trail read clearly, that the alarm ping is audible but not grating, and that shooting or body-blocking Mauls feels fair.

## Auto Run Result

Status: done

**Summary:** The Maul (FR23) is built. `Maul extends Enemy` (6 HP, medium tier) spawns just off-screen on its entry side at its slot's y. It plays a new `maul_alarm` ping, shows a red additive engine trail, and flies in one straight line at `enemies.maul.dive_speed_px_s` (400) toward the convoy ship nearest it at spawn. The heading is locked, so the player never steers it. A hit on a ConvoyShip deals `damage.convoy_maul` (10), then the Maul self-destructs with MEDIUM feedback through the new `Enemy._resolve_without_kill`: no kill event and no loot (F18). A miss (it leaves the playfield after entering) or no live convoy resolves without a kill, so the wave still clears. A Maul shot down or body-blocked goes through `_die()` and rolls `drops.maul`. A body-block costs `damage.maul_contact_hearts`. `maul` is registered and rowless. `dev_convoy` gains a Maul wave (wave 3). Levels 1–3 stay Maul-free until Epic 7.

**Files changed:**
- `game/entities/enemies/maul/maul.gd` / `maul.tscn` — new: the Maul (straight dive, convoy hit, miss, no-convoy exit, code-drawn hull and trail).
- `game/core/enemy.gd` — `_resolve_without_kill(play_feedback)`, the shared no-kill exit.
- `game/autoloads/entity_registry.gd` — `&"maul"` in `ENEMIES` and `ROWLESS_TYPES`.
- `game/entities/player/player.gd` — the Maul's contact cost reads `damage.maul_contact_hearts`.
- `game/autoloads/audio.gd`, `tools/gen_placeholder_sfx.py`, `game/assets/audio/sfx/sfx_maul_alarm.wav(.import)`, `game/assets/CREDITS.md` — the generated alarm ping. The other WAVs come out byte-identical.
- `game/data/levels/level_dev_convoy.json` — wave 3: 4 Mauls (sides) + 2 Wasps.
- `game/tests/unit/test_maul.gd` (new) plus `test_enemy`, `test_player_hearts`, `test_spawner`, `test_wave_director`, `test_audio`, `test_level` and `tests/data/test_data_files` — coverage of every matrix row and AC.
- `_bmad-output/game-architecture.md` — `## As-built 2026-10-10 (Story 6.2)`.

**Review findings:** 22 findings (high 0, medium 3, low 10, false 9).
- 4 entries patched:
  - the flaky per-Maul await in the level test (medium; 3 rows grouped);
  - `target_ship()` returning a freed ship (low; 2 rows);
  - the ROWLESS_TYPES comment wording (low).
- 0 deferred.
- Rejected, each with its reason in the Review Triage Log:
  - stacked alarm pings;
  - the alarm with no convoy;
  - the `is Maul` branch;
  - `_has_target` duplicating `_target`;
  - the substring level check;
  - `dive_speed <= 0`;
  - body-block only tested through `on_contact`;
  - and 9 false findings.

**Follow-up review recommended:** false. One medium entry was patched, and it was test-only. 0 high.

**Verification:** `uv run python tools/gen_placeholder_sfx.py` changed only the new WAV. `--import` exited 0. The full headless GUT suite ran 1491/1491 passing, before and after the patches, with no orphans. The only ERROR lines are existing fixture-driven negative tests.

**Residual risks (feel, not verified by tests):** play `level.tscn -- --level=dev_convoy` to wave 3 and check:
- that the Maul silhouette and red trail read clearly;
- that four simultaneous alarm pings aren't grating;
- that shooting or body-blocking Mauls feels fair.

A Maul can miss a moving convoy ship by design, because it aims once with no lead.
