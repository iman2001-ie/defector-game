# Epic 2 Context: Enemy Roster and Scripted Waves

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Turn the Epic 1 sandbox into a real level: the player fights through data-scripted waves of Wasps, Lancers, Needles and Bastions, each with a readable telegraph, while a top-centre wave bar fills until the level clears. The designer authors waves, reinforcement groups and beat triggers in JSON, so later epics (comms, escort, campaign, boss) can plug story beats and content into one Wave Director without new code paths. Tier: MUST (Hunter Wasp is COULD).

## Stories

- Story 2.1: Count Wave Progress and Evaluate Beat Triggers
- Story 2.2: Play a Level Driven by Wave Data
- Story 2.3: Watch the Wave Progress Bar Fill
- Story 2.4: Dodge Wasp Formations and Telegraphed Dives
- Story 2.5: Face Lancers' Aimed Shots
- Story 2.6: Take Cover from the Needle's Sniper Shot
- Story 2.7: Bring Down a Bastion Gunship
- Story 2.8: Outrun the Hunter Wasp (COULD)

## Requirements & Constraints

- **Waves are pure data.** No procedural spawning. Difficulty comes from enemy mix and count, never from scaling HP or damage. All numbers (HP, speeds, timers, gap) live in `tuning.json` and are read through `Config`; never hard-code a GDD number.
- **Wave clear:** every counted enemy resolved (asteroids never count) and no action chain still running. Then `wave_clear` triggers, a `waves.gap_s` (2.0 s) gap, the next wave. After the last wave: `level_cleared`, a placeholder "LEVEL CLEAR" banner and an INFO log (real progression arrives in Epic 4).
- **No soft-locks:** an invalid spawn entry (unknown type) is logged with file and key path and subtracted from the wave total. Errors never pause the game.
- **Enemy behaviour (first-pass tuning):**
  - Wasp: small, 3 HP, enters at 350 px/s to a formation slot in the top 40%; every 3–5 s one holding Wasp flashes its wings, pauses 0.4 s, dives at the player at 600 px/s. Contact only. A Wasp that exits the bottom re-enters from the top and does **not** resolve.
  - Lancer: medium, 8 HP, strafes in the top 35% at 200 px/s; 0.3 s muzzle glow, then 1 bullet aimed at the player every 2.0 s at 450 px/s. Convoy targeting is Epic 6, not here.
  - Needle: medium, 6 HP, anchors at the top edge, repositions every 8 s; every 4.0 s the line tracks the player 1.2 s, locks red 0.3 s, then fires a 1600 px/s bolt. Asteroids block it.
  - Bastion: large, 40 HP, drifts at 60 px/s within y 80–400; 2 turrets, each 0.5 s glow then a 3-bullet ±15° spread at 350 px/s every 2.5 s. Large feedback tier on death; never destroyed by contact.
  - Hunter Wasp (COULD): small, 3 HP, orange tint, chases at 300 px/s with a 90°/s turn limit. `hunter_wasp` is always a known type id; spawning is gated only by the `hunter_wasp` flag (default false). When false, its spawns are skipped, not counted, and logged at DEBUG.
- **Fairness (Pillar 1):** enemy hitboxes ≈ 80% of the sprite; every enemy projectile is `enemy` magenta/red with a bright core, ≥ 16 px and ≤ 450 px/s (only the telegraphed Needle bolt is faster); every attack has ≥ 0.3 s telegraph, enforced by a data test over `tuning.enemies` and `tuning.boss`.
- **Performance:** 60 FPS at 1920×1080 with ~40 enemies and ~200 projectiles. Re-run `-- --bench=20` after visual changes.
- **Known playtest risk:** the instant cursor-locked ship makes dodging easier. Tune enemy bullet density and speed, not movement. Missile splash vs `grid_4x2` spacing (DW-3) is only to be revisited if formations feel weak.

## Technical Decisions

- **Wave Director + Beat Triggers (novel pattern):**
  - `WaveProgress` and `BeatTrigger` are pure `RefCounted` classes in `systems/waves/`, unit-tested headless.
  - `BeatTrigger.should_fire(event, ratio, flags)`: `when` ∈ `wave_start` | `progress` (`at` 0–1, fires when ratio ≥ `at`) | `wave_clear` | `boss_phase` (`phase`) | `boss_hp_le` (`hp`). An optional `flag` with a `"!"` prefix negates it; a missing flag key is handled. Fires at most once per attempt (`has_fired`).
  - `total_counted` = all `spawns` **plus** every entry in all `groups` of the wave, known up front, so the bar is monotonic and reinforcements can't cause an early clear.
  - Triggers are checked in array order after every resolve. Actions run sequentially as their own chain; a running chain doesn't block other triggers. Epic 2 implements `spawn_group` and `wait` (pausable timer); `comms`, `story_event` and `music` arrive in Epic 5.
  - Boss wave shape `{ "boss": "flagship", ... }` has total 1; F6 jumps to it if present, otherwise logs that there is none.
- **Level data:** `data/levels/level_<n>.json` (`id`, `name`, `background`, `music`, `convoy`, `ally`, `intro_sequence`, `outro_sequence`, `waves[]` with `spawns` {type, count, formation, entry}, `asteroids`, `groups`, `triggers`). Loaded through `Config.level(id)` (new getter, validated at load). A `level_dev.json` with Wasp-only waves lets the main scene start a level directly until the title flow exists. JSON numbers are floats: counts and HP go through `Config.int_()`/`int()`.
- **Level scene:** one generic `scenes/level/level.tscn` with the fixed tree: Background, World (Asteroids, Enemies, Allies, Pickups, Projectiles, Effects, Player), WaveDirector, ShakeCamera, WorldEnvironment, HUD (layer 10), Comms (20), Overlay (30). The scene root declares `CONFINED_HIDDEN` via `PauseArbiter.set_gameplay_mouse_mode`, applies `RenderGlow`, and calls `Feedback.prewarm()` at the end of `_ready`, mirroring the sandbox.
- **Entities:** only `Spawner` instantiates (scenes preloaded in `EntityRegistry`, `setup(params)` before `add_child`, `setup` stores and `_ready` applies). Only the WaveDirector decides what spawns and when. Counted enemies join group `counted` and connect `resolved`.
- **`Enemy` base contract** (`core/enemy.gd`): `signal resolved` emitted exactly once, `type_id`, `tier`, `setup`, `apply_damage(amount, source)` (records `source.from_ally`), `destroy_by_contact()` (small and medium only). HP from `enemies.<type_id>.hp`. Death = `Feedback.impact(tier, pos)` → `Events.enemy_killed` → drops → `resolved.emit()` → `queue_free()`.
- **State pattern:** `enum State` + `match` in `_physics_process`; transitions only via `_enter_state()`, which handles entry effects such as telegraph glows. Every attack state is preceded by a telegraph state whose duration comes from tuning.
- **Projectiles:** a shared `enemy_bullet.tscn` and a `needle_bolt.tscn` extend `Projectile`. Layer `enemy_shots`, masking `player`, `asteroids`, `convoy`. A `CapsuleShape2D` aligned with travel, height ≥ speed / 60 (Needle bolt ≥ 27 px). On overlap, call `apply_damage` only if the target has it (the player gains it in Epic 3), then free. Asteroids stop enemy shots. Use the `CollisionLayers` constants.
- **Events:** use `level_started`, `wave_started(wave_index, wave_count)`, `wave_progress_changed(wave_index, ratio)`, `wave_cleared`, `level_cleared`, `enemy_killed`. Add any new global signal to `events.gd` first.
- **Logging/debug:** `Log` only (categories `wave`, `beat`, `spawn`, `data`, `debug`), INFO for wave/level start and clear, nothing per frame. Debug F3 resolves every counted enemy in the wave and fires pending progress triggers in order. The F1 overlay adds wave n/N, resolved/total and active pause reasons.
- **Tests:** `tests/unit/test_wave_progress.gd`, `test_beat_trigger.gd`; `tests/data/test_data_files.gd` validates every level JSON (known enemy types, counts > 0, valid `when`, `at` in 0–1, referenced groups exist) and the ≥ 0.3 s telegraph rule. Re-run `--import` after adding `class_name` scripts.

## UX & Interaction Patterns

- **Wave bar** (`ui/hud/wave_bar.gd`, on the HUD CanvasLayer, `PROCESS_MODE_PAUSABLE`): centred at y 40, width 560 (x 680–1240), inside the top 120 px HUD band. N segments with 4 px gaps. Full segments are `coalition` #22E6FF, the current one fills partially, and empty ones are a `heartEmpty` #2B3348 track with a `border` #2A3B5C outline.
- It fills smoothly (0.2 s tween), completed segments stay full, and it never decreases within an attempt. During the 2.0 s gap between waves the next segment highlights.
- The HUD updates only from `Events` signals, never by polling gameplay nodes, and styles come from the shared `ui/theme/defector_theme.tres`.
- Nothing persistent is drawn in the enemy zone (y 120–432). Enemies use the `enemy` colour and need distinct silhouettes (Wasp, Lancer, Needle, Bastion). Telegraph glows and the Needle targeting line are in-world, not HUD.

## Cross-Story Dependencies

- 2.1 (pure logic) → 2.2 (Wave Director, `level.tscn`, `Config.level`, data test) → 2.3 (wave bar consumes 2.2's signals). Stories 2.4–2.8 plug enemy types into the 2.2 spawn path and extend `test_data_files.gd`.
- 2.5 creates the shared `enemy_bullet.tscn`, which 2.7 reuses (and the Flagship reuses in Epic 7). The Wasp from Epic 1 gains formation and dive behaviour in 2.4.
- Builds on Epic 1: `Spawner`, `EntityRegistry`, `Feedback` tiers, `ShakeCamera`, `Config`, `PauseArbiter`, `DebugTools`, the asteroids and the cursor-locked player.
- Later epics extend these systems: player hearts and `apply_damage` (Epic 3), the title flow and real level-clear progression (Epic 4), `comms`/`story_event`/`music` actions on triggers (Epic 5), the Maul, Lancer convoy targeting and the convoy (Epic 6), real level content, the boss wave and the boss bar (Epic 7). Keep `wave_director.gd` open to those extensions.
