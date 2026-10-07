---
title: 'Game Architecture'
project: 'defector-game'
game: 'DEFECTOR'
date: '2026-10-06'
author: 'iman2001-ie'
version: '1.0'
stepsCompleted: [1, 2, 3, 4, 5, 6, 7, 8, 9]
status: 'complete'
mode: 'autonomous - facilitator decisions reviewed and accepted by user 2026-10-06 (see Decision Review Log)'
engine: 'Godot 4.7.2-stable (GDScript)'
platform: 'Windows 10/11 64-bit'

# Source Documents
gdd: '_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
epics: '_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/epics.md'
brief: '_bmad-output/planning-artifacts/briefs/brief-game-project-2026-10-06/brief.md'
---

# DEFECTOR - Game Architecture

## Executive Summary

**DEFECTOR** is a 2D, fixed-screen, single-player shooter. It is built in **Godot 4.7.2-stable with statically typed GDScript** for Windows. The architecture is small on purpose, because the whole project has about 20 hours. Built-in nodes do the heavy lifting: `Area2D` collision, tweens, particles and `Camera2D` shake. A handful of autoloads hold the global services.

Data files drive all content. Plain JSON in `res://data/` holds tuning, waves, triggers and dialogue. One generic `level.tscn` runs every level.

Three custom patterns carry the game's identity:

- the **Wave Director + Beat Triggers**, which handles scripted waves and story beats fired by "% of wave destroyed"
- the **Comms Channel**, which handles story and combat lines, cut-offs and the Final Choice
- the **Impact Feedback tiers**, which scale explosion size, shake and hit-stop with object size

A **Pause Arbiter** stops the menu pause, story pause and hit-stop from fighting each other.

**Ready for:** epic and story creation (`gds-create-epics-and-stories`).

> **Autonomous run.** The user asked for this workflow to run unattended. Every decision the facilitator made on the user's behalf is marked in the [Decision Review Log](#decision-review-log). Review those before implementation starts. Each one is cheap to change now.

---

## Project Context

### Game Overview

**DEFECTOR:** "Chicken Invaders meets a CoD campaign". It's a neon 2D space shooter with 3 short levels, told entirely through an in-game comms panel. The player is General Arden Vale, who defected and now has to bring down Sovereign Isolde Varn.

### Technical Scope

| Item | Value |
|---|---|
| Platform | Windows 10/11 64-bit; zipped executable on GitHub Releases |
| Genre | 2D fixed-screen arcade shooter + light narrative |
| Project level | Small (solo, ~20 h including planning, developer new to Godot 2D) |
| Multiplayer | None |
| Playfield | 1920×1080 logical, fixed, no scrolling, letterboxed 16:9 |

### Core Systems

| System | Complexity | GDD Reference |
|---|---|---|
| Player ship (cursor-locked movement, laser, missile, hearts, i-frames) | Medium | Primary Mechanics |
| Projectiles + asteroid blocking (both directions) | Medium | Weapons, Asteroids |
| Enemies ×5 (+1 COULD) with telegraphed attacks | Medium | Enemy Design and AI |
| Wave Director (scripted, data-driven, % triggers, reinforcements) | **High** | Level Design Framework |
| Comms / story system (pause vs auto lines, cut-off, Final Choice) | **High** | Pillar 3, E5 |
| Size-scaled impact feedback (explosion, shake, hit-stop) | Medium | Pillar 2 feedback table |
| Energy economy: drops, Shield, Barrage (homing) | Medium | Energy, Shield, and Barrage |
| Convoy escort + ally ships + Tarek's scripted fall | Medium | Allies and escort |
| Flagship boss (3 phases, Final Choice) | **High** | Flagship |
| Game flow: title, level select, pause, retry, end | Low | Platform-Specific Details |
| Save (unlocks + energy) | Low | Save |
| HUD: hearts, energy, cooldown ring (in-world on the ship), wave bar, boss bar, convoy bar | Low | Asset Requirements (UI) |
| Audio (size-scaled SFX, music drop-out) | Low | Art and Audio Direction |

### Technical Requirements

- **60 FPS** at 1920×1080 on an integrated-graphics laptop, with headroom for 40 enemies, 200 projectiles and their particles.
- Cold launch to the title screen in **under 5 s**. Build under **200 MB**.
- Borderless fullscreen by default, with a windowed option. The cursor is hidden during gameplay and confined to the player zone (y 432–1080): the Player warps it back onto the zone edge (Godot can only confine to the window). See [Pause and Time Model](#pause-and-time-model) for the as-built cursor lock.
- **Data-driven:** dialogue, waves and tuning live in data files. The surrender beats sit behind on/off flags.
- Mouse and keyboard only.

### Complexity Drivers

- **Story beats are interleaved with live combat.** Some lines pause the game and others don't. Some fire at a % of the wave destroyed, and one cuts off mid-sentence. These cross-system choreographies are where AI agents are most likely to diverge.
- **Several pause and time sources:** the Esc menu, story lines, the Final Choice, hit-stop, and the death pause. Godot has only one `SceneTree.paused` flag and one `Engine.time_scale`.
- **Fast projectiles:** the Needle bolt (1600 px/s) and the laser (1800 px/s) move ~27–30 px per physics tick against a 24 px player hitbox, so they can tunnel through targets.
- **Asymmetric collision rules:** asteroids block everything, friendly fire is off, the convoy can be hit only by convoy-targeted Lancer shots and Mauls, and the allies are untouchable.

### Technical Risks

| Risk | Mitigation in this architecture |
|---|---|
| Newcomer to Godot 2D | Use built-in nodes only, no plugins in the runtime. Simple `match`-based state machines. One generic level scene. |
| Story beat soft-locks (the 3-playthrough success metric) | Wave Director owns the clear logic. Debug keys can skip waves. All data is validated at load. |
| Performance on integrated graphics | No object pooling unless measured. Particles are pre-warmed by `Feedback.prewarm()` at scene start. The E1 profiling gate can switch to the Compatibility renderer. |
| GDScript JSON quirks | Number-type rule (all JSON numbers are `float`). The `Config` accessor fails loudly. |

---

## Engine & Framework

### Selected Engine

**Godot 4.7.2-stable** (official build, released 2026-08-18; verified 2026-10-06), using **GDScript with static typing**. No C#/.NET.

**Rationale:** the brief and GDD already settled this. GDScript matches the developer's Python background, Godot is light on the dev laptop, and Unity was rejected in the GDD. The developer already has 4.7.2 installed locally; its folder is referred to as `<GODOT_DIR>` (the real path lives in the gitignored `LOCAL.md` at the repo root). During this workflow, the console build (`Godot_v4.7.2-stable_win64_console.exe`) was confirmed to run scripts headless.

### Project Initialization

There is **no starter template**. Templates such as Maaack's Game Template bring menus, a settings framework and patterns sized for bigger games, and learning them would eat into the 20-hour budget. A plain project plus the structure below is faster to understand.

The Godot project lives in the **`game/` subfolder** of the repo, so the editor doesn't scan `_bmad/`, `.claude/` or the planning docs.

```bash
# from repo root
mkdir game
# Open Godot 4.7.2 → Project Manager → Create → Path: <repo>/game, Name: DEFECTOR, Renderer: Forward+
# Version control metadata: Git → creates game/.gitignore (ignores .godot/)
```

### Engine-Provided Architecture

| Component | Solution | Notes |
|---|---|---|
| Rendering | Forward+ renderer, 2D canvas | `rendering/viewport/hdr_2d = true` + `WorldEnvironment` glow for neon (see ADR-003). Glow parameters are data (`tuning.json` → `render.glow`: `intensity`, `bloom`, `hdr_threshold`), applied by `RenderGlow.apply(env)` (`core/render_glow.gd`) from the scene root's `_ready` |
| Physics / collision | Godot Physics 2D, `Area2D` only | No `RigidBody2D` / `CharacterBody2D`. Every entity moves itself and detects overlaps |
| Physics tick | 60 Hz (default) | Collision-relevant movement goes in `_physics_process` |
| Audio | `AudioServer` buses + `AudioStreamPlayer` | Buses: `Master` → `Music`, `SFX`, `UI` |
| Input | InputMap actions | Defined in `project.godot` (see Input Actions) |
| Scene management | `SceneTree.change_scene_to_file` behind the `SceneRouter` autoload (planned) | Today only the debug F5 reload restarts the scene (`DebugTools`, see Reload) |
| Tweening / animation | `Tween` (code) for UI, flicker, shake decay | `AnimationPlayer` is optional, for sprite anims only |
| Particles | `GPUParticles2D` one-shot | Pre-warmed by `Feedback.prewarm()` when the scene starts (see Asset Management) |
| Display scaling | Stretch mode `canvas_items`, aspect `keep`, base 1920×1080 | This gives the letterboxing |
| Build | Godot export templates 4.7.2 → Windows Desktop preset | `.exe` + embedded `.pck` |
| Logging | `print` / `push_warning` / `push_error` + built-in file logging | Wrapped by the `Log` autoload |

### Remaining Architectural Decisions

The sections below resolve: state management, data format and access, save, the pause/time model, scene structure, collision layers, entity creation, enemy AI pattern, the event system, the comms and wave systems, audio, UI, testing, and the debug tools.

---

## Architectural Decisions

### Decision Summary

| # | Category | Decision | Version | Affects Epics | Rationale |
|---|---|---|---|---|---|
| D1 | Engine / language | Godot, statically typed GDScript | 4.7.2-stable | All | Settled by the GDD. Python-like, light |
| D2 | Project location | Godot project in `game/` subfolder | n/a | All | Keeps BMAD files out of the editor's import scan |
| D3 | Renderer | Forward+, `hdr_2d` on, `WorldEnvironment` glow | 4.7.2 | E1, E8 | Best 2D neon glow. Fallback to Compatibility if E1 perf fails (ADR-003) |
| D4 | Collision model | `Area2D` for every entity. 8 named layers. "Projectiles apply damage" rule | built-in | E1–E3, E6, E7 | Simplest model with no physics response. Avoids double-hits |
| D5 | Fast projectile handling | Collision shape length ≥ speed × 1/60 s | built-in | E1, E2 | Prevents tunnelling without raycast code |
| D6 | Game state | Autoload `GameState` (run state), with level-local state on nodes | n/a | E3, E4 | One global source for energy and unlocks. Everything else dies with the level scene |
| D7 | Pause / time | `PauseArbiter` autoload (reason set → `tree.paused`). `HitStop` via `Engine.time_scale` | n/a | E1, E4, E5, E7 | Several pause sources must not clobber each other |
| D8 | Data format | JSON files in `res://data/`, loaded and validated by the `Config` autoload | n/a | All | Easy for humans and AI agents to write and diff. Hot-reloadable |
| D9 | Save system | `ConfigFile` at `user://save.cfg`. Custom user dir → `%APPDATA%\DEFECTOR\` | built-in | E4 | Tiny save (unlocks + energy). Built-in format with no parsing code |
| D10 | Scene structure | One generic `level.tscn` parameterised by level id. Story scene, title, level select, end screen | n/a | E4, E5, E7 | One code path for all 3 levels. Content is data |
| D11 | Retry model | Retry = reload the level scene (`SceneRouter.restart_level()`) | n/a | E3, E4 | Guarantees clean state with no reset code |
| D12 | Event system | `Events` autoload with typed signals for cross-system events. Direct calls parent→child | n/a | All | Idiomatic Godot. Decouples HUD, audio and comms |
| D13 | Entity creation | `Spawner` + `EntityRegistry` (type id → `PackedScene`), `setup()` before `add_child()`. No pooling by default | n/a | E1, E2, E3, E7 | Single creation path. Pooling can be added inside it later |
| D14 | Entity behaviour | Per-entity `enum State` + `match` in the script | n/a | E2, E6, E7 | Lighter than node-based FSMs. Readable for a newcomer |
| D15 | Wave and story scripting | **Wave Director + Beat Triggers** (novel pattern) | n/a | E2, E5, E6, E7 | Data-driven waves, % triggers and reinforcements |
| D16 | Dialogue | Custom **Comms Channel** (novel pattern), no Dialogic | n/a | E5, E7 | Requirements are narrow (typewriter, cut-off, choice). A plugin adds learning cost |
| D17 | Game feel | **Impact Feedback** service with tiers from tuning data (novel pattern) | n/a | E1, E3, E7, E8 | Pillar 2 in one call: `Feedback.impact(tier, pos)` |
| D18 | Audio | `Audio` autoload: SFX pool (12 players), music player with fade, id → stream registry | built-in | E5, E8 | Size-scaled SFX and the music drop-out for Tarek's silence |
| D19 | UI | `Control` nodes under `CanvasLayer`s. One shared `Theme` resource | built-in | E3, E4, E5, E7 | |
| D20 | Testing | GUT on the `godot_4_7` branch for logic and data tests, run headless from the CLI | GUT 9.7.1 | All | Only pure logic and data validation. Feel is tested by playtest |
| D21 | Plugins in the shipped game | None | n/a | All | Fewer moving parts. GUT is dev-only (excluded from export) |
| D22 | Distribution | Windows Desktop export, single `.exe` with embedded PCK, zipped, GitHub Release | 4.7.2 templates | E8 | GDD requirement |
| D23 | AI tooling (MCP) | **No engine MCP.** GoPeak rejected. AI agents use the headless CLI loop. Context7 optional | n/a | Dev only | Unpinned `npx` supply-chain risk, local command ports, corporate laptop. The CLI covers the needs |

### State Management

**Approach:** most state lives with its owner node, plus **one** small global run-state autoload.

| State | Owner | Lifetime |
|---|---|---|
| `energy` (0–100), `current_level_id`, `highest_unlocked_level`, `is_retry` | `GameState` autoload | Whole session. Unlocks and energy are persisted by `SaveManager` |
| Hearts, i-frames, shield, missile cooldown | `Player` node | One level attempt |
| Wave index, alive and resolved counts, triggers fired | `WaveDirector` node | One level attempt |
| Convoy HP | `Convoy` node | One level attempt |
| Boss phase and HP | `Flagship` node | One level attempt |
| Comms queue, silence flag | `CommsChannel` node (in level / story scene) | One scene |

**Energy rules** (GDD):

- On the first attempt of a level, `energy` keeps its carried value.
- On death, retry or restart: `GameState.energy = 0`, then reload the level.
- On level clear: `SaveManager.save()` writes the current energy and the new unlock.
- From the title screen, "Play" and "Level Select" load the saved energy.

### Data Persistence

**Save system:** `ConfigFile` at `user://save.cfg`.

Project setting `application/config/use_custom_user_dir = true` with `custom_user_dir_name = "DEFECTOR"`, so `user://` resolves to `%APPDATA%\DEFECTOR\`.

```ini
[progress]
save_version=1
highest_unlocked_level=2
energy=40
```

- Saving happens **only** on level clear (and nowhere else).
- A missing file means defaults (`highest_unlocked_level=1`, `energy=0`).
- A corrupt file or unknown `save_version` gives `Log.warn` and defaults. The game never crashes on a bad save.
- Writes go through `SaveManager.save()` only. No other script touches `user://save.cfg`.

### Asset Management

**Loading strategy:** scene-based. Every scene and asset is `preload()`ed by the script or scene that uses it. The game is small (target under 200 MB, realistically under 50 MB), so there is no streaming and no threaded loading. Level scenes load in well under a second.

- `EntityRegistry` `preload`s every entity `PackedScene`, so spawning never hitches on disk I/O.
- `Audio` `preload`s every SFX stream in its registry.
- **Particle and shader pre-warm:** the scene root calls `Feedback.prewarm()` at the end of its `_ready` (today `scenes/sandbox/sandbox.gd`; `level.gd` when it lands). It spawns one explosion per tier at `Feedback.PREWARM_POSITION` (-1000, 540), off-screen, with no shake, hit-stop or sfx, and lets each finish. This avoids the first-use shader compile hitch.

### Pause and Time Model

The game has two independent mechanisms. **No other code** may set `get_tree().paused` or `Engine.time_scale` directly.

1. **`PauseArbiter` (autoload):** holds a set of reasons (`&"menu"`, `&"story"`, `&"final_choice"`, `&"death"`).
   - `get_tree().paused = not _reasons.is_empty()`.
   - The Esc menu during a story line adds `&"menu"`. Closing the menu removes only `&"menu"`, so the game stays paused for the story line.
2. **`Feedback.hit_stop(ms)`:** sets `Engine.time_scale = 0.0` and restores it with `get_tree().create_timer(ms / 1000.0, true, false, true)` (with `process_always` and `ignore_time_scale` set).
   - Overlapping hit-stops keep the **longest remaining** duration. They don't stack.

**Process modes:**

| Node | `process_mode` |
|---|---|
| Gameplay world (`World` node in the scene root: `sandbox.tscn` today, `level.tscn` planned) | `PROCESS_MODE_PAUSABLE` (inherit) |
| `CommsPanel`, `PauseMenu`, `FinalChoice`, retry prompt | `PROCESS_MODE_ALWAYS` |
| Autoloads `PauseArbiter`, `Audio`, `Feedback` (and `SceneRouter`, planned) | `PROCESS_MODE_ALWAYS` |
| `ShakeCamera`, `DebugTools` (as built; each sets it in `_ready`) | `PROCESS_MODE_ALWAYS` |
| HUD | `PROCESS_MODE_PAUSABLE` (it freezes along with gameplay) |

**Cursor:** while any pause reason is active, `Input.mouse_mode = MOUSE_MODE_VISIBLE`. During gameplay it is the mode the scene declared with `PauseArbiter.set_gameplay_mouse_mode(mode)` (`MOUSE_MODE_CONFINED_HIDDEN` for gameplay scenes). `PauseArbiter` applies this, so the mode is set in one place. `clear()` drops the pause reasons but keeps the declared mode, so every scene root must declare its own (a menu scene that doesn't would inherit `CONFINED_HIDDEN`); `PauseArbiter.current_mouse_mode()` returns the mode it writes. PauseArbiter owns `mouse_mode`. The Player owns every gameplay `warp_mouse` call (zone confinement, resume, and the planned Epic 6 convoy push) (GDD decisions #29, #31). The one debug-only exception is the `--bench` mode, where `DebugTools` warps the cursor once to `BENCH_AIM`.

**Cursor lock (as built, Story 1.8):**

- Every physics tick `Player._physics_process` calls `step_lock(get_viewport().get_mouse_position())`. It reads the **viewport** mouse on purpose, not the camera-transformed global mouse, so the ShakeCamera offset can't feed back into the ship.
- `static func confine(mouse, bounds_min, bounds_max)` is a pure clamp. The bounds are x 0..`Playfield.SIZE.x` and y `player.bounds_y.min`..`max` (432..1080).
- If the mouse is more than `WARP_EPS_PX` (1.0) from the confined point **and** `PauseArbiter.current_mouse_mode() == MOUSE_MODE_CONFINED_HIDDEN`, the Player calls its injectable `warp_mouse: Callable` (defaults to the viewport's `warp_mouse`; tests inject a recorder) with the confined point.
- Then `global_position = confined`. The ship sits exactly on the cursor with no delay and never rotates.
- **Resume:** `PauseArbiter` emits `signal resumed` on every paused → unpaused transition, after it writes `mouse_mode`. `Player._on_resumed` warps the cursor to `global_position` (again only while the mode is `CONFINED_HIDDEN`), so the ship never jumps after a pause.

### Scene Structure

```
Title ──Play/Level Select──► Story (opening, only when starting Level 1 fresh)
                               │
                               ▼
                         Level (id=1..3) ──clear──► next Story/Level ──L3 clear──► End
                           ▲      │
                           └retry─┘ (reload same level)
```

`level.tscn` node tree (fixed: all three levels use this tree). **Planned:** `level.tscn` arrives in Epic 2+. Today the main scene is the Epic 1 debug sandbox `scenes/sandbox/sandbox.tscn`, which uses the same `World/<Group>` containers, `Spawner`, `ShakeCamera`, `WorldEnvironment` and `Overlay/DebugTools`.

```
Level (Node2D, level.gd)                 # reads data/levels/level_<id>.json
├── Background (Node2D)                  # parallax-free sprites, chosen by level data
├── World (Node2D)                       # everything pausable
│   ├── Asteroids (Node2D)
│   ├── Enemies (Node2D)
│   ├── Allies (Node2D)                  # Tarek/Ryn, Convoy
│   ├── Pickups (Node2D)
│   ├── Projectiles (Node2D)
│   ├── Effects (Node2D)
│   └── Player (Area2D, player.tscn)
├── WaveDirector (Node, wave_director.gd)
├── ShakeCamera (Camera2D, shake_camera.gd)   # anchor centre 960,540
├── WorldEnvironment                      # glow
├── HUD (CanvasLayer layer=10)
├── Comms (CanvasLayer layer=20)          # CommsPanel + FinalChoice
└── Overlay (CanvasLayer layer=30)        # PauseMenu, RetryPrompt, DebugOverlay
```

Spawned nodes are always parented to the matching `World/<Group>` container, which `Spawner` exposes.

### Collision Layers

Configure these in `project.godot` → `layer_names/2d_physics`. Use these names and numbers exactly.

As built, `core/collision_layers.gd` (`CollisionLayers`) holds the bit values (`PLAYER` = 1 … `ALLIES` = 128) and the shot masks `MASK_PLAYER_SHOTS` / `MASK_ENEMY_SHOTS`. Code and tests use these constants; `.tscn` files store the numbers, and tests check them against the constants.

| # | Name | Who is on it | Mask (what it detects) |
|---|---|---|---|
| 1 | `player` | Player hurtbox | `enemies`, `asteroids`, `pickups`, `convoy` |
| 2 | `player_shots` | Laser, missile, micro-missile, **ally shots** | `enemies`, `asteroids`, `convoy` |
| 3 | `enemies` | All enemies, Flagship turrets and core | `convoy` (Maul only, others none) |
| 4 | `enemy_shots` | All enemy bullets, Needle bolt | `player`, `asteroids`, `convoy` |
| 5 | `asteroids` | Asteroids | none |
| 6 | `pickups` | Energy orbs | none |
| 7 | `convoy` | Convoy ships | none |
| 8 | `allies` | Ally ships (visual only) | none |

**Damage rule (one side applies damage, never both):**

- **Projectiles apply damage** to what they overlap, then free themselves. A projectile that touches an asteroid damages it if it's a player shot, then is destroyed.
- An **enemy shot touching the convoy** always stops and damages it: `damage.convoy_aimed` (5) if `targets_convoy == true` (a Lancer aiming at the convoy), otherwise `damage.convoy_stray` (2). (GDD decision #23)
- A **player or ally shot touching the convoy** frees itself without applying damage. The convoy blocks it, but there's no friendly fire.
- **Contact damage:** the **Player** detects overlaps with enemies and asteroids. It calls `apply_damage` on itself (1 or 2 hearts, from the data) and `destroy_by_contact()` on small and medium enemies.
- **Player vs convoy:** the Player has a separate ~64 px `HullArea` circle (masking only `convoy`) next to its 24 px hurtbox. It detects convoy overlaps through it and, after moving in `_physics_process`, pushes itself out along the shortest separation vector (an Area2D push-out, no physics body). There's no damage. The convoy only moves horizontally, so the player can never be pinned. (GDD decision #25) The move from the previous position to the cursor target is swept (shape cast against `convoy`) before the push-out, because the ship moves instantly. After any block or push, the cursor is warped to the ship (GDD decision #29).
- The **Maul** detects the convoy and calls `convoy.apply_damage(10)`, then destroys itself.
- **Friendly fire is impossible.** `player_shots` doesn't detect `allies`. It does detect `convoy`, but only to be blocked, and the projectile never calls `apply_damage` on the convoy.

### Fast Projectiles (anti-tunnelling)

Every projectile's collision shape is a `CapsuleShape2D` aligned with its direction of travel. Its **height must be ≥ `speed / 60` px**. Examples: laser 1800 px/s → ≥ 30 px, Needle bolt 1600 px/s → ≥ 27 px.

The visual sprite may be shorter. No ray/shape casts are needed.

### Audio Architecture

- Buses: `Master` → `Music`, `SFX`, `UI`. Volumes are fixed in v1 (there's no settings menu).
- As built (`autoloads/audio.gd`):

  ```gdscript
  const DEFAULT_PITCH_JITTER: float = 0.05
  func play_sfx(id: StringName, pitch_jitter: float = DEFAULT_PITCH_JITTER, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer
  ```

  - `pitch_scale = pitch * (1 + randf_range(-pitch_jitter, pitch_jitter))`, and `volume_db` is set on the player.
  - The stream comes from the `Audio.SFX` registry (id → preloaded stream). An unknown id logs `Log.warn` once per id and returns `null`.
  - The pool has 12 (`POOL_SIZE`) `AudioStreamPlayer` nodes on the `SFX` bus. It uses the first free player. When all are busy it stops and reuses the one started longest ago.
- **Planned (Epic 5/8):** `Audio.play_music(id)`, `Audio.stop_music(fade := 0.5)`, `Audio.duck_music(on: bool)`. Music isn't built yet.
- SFX are in-world but on a fixed screen, so there's no positional audio (`AudioStreamPlayer`, not `2D`).
- Explosion tier → SFX: each `tuning.json → feedback.tiers` row carries `sfx`, `sfx_pitch` and `sfx_volume_db` (GDD decision #26). `Feedback.impact` calls `Audio.play_sfx(row.sfx, Audio.DEFAULT_PITCH_JITTER, row.sfx_volume_db, row.sfx_pitch)`.

### UI Framework

- Built-in `Control` nodes. One `Theme` at `res://ui/theme/defector_theme.tres` (fonts, panel styles, button styles). Don't set per-node style overrides except in the comms panel portrait frame.
- The HUD reads state **only via `Events` signals** (`hearts_changed`, `energy_changed`, `wave_progress_changed`, `boss_hp_changed`, `convoy_hp_changed`, `missile_cooldown_changed`). The HUD never polls gameplay nodes.
- There is no reticle: the ship is the cursor (GDD decision #29). The missile cooldown ring is a Player child, drawn above the ship sprite with `draw_arc` and driven only by `Events.missile_cooldown_changed`.
  - As built: `entities/player/missile_ring.gd` (`class_name MissileRing`), the `MissileRing` child of the Player with `z_index = 1`.
  - Data: `player.missile_ring.radius_px` / `stroke_px`. The radius is clamped to `player.sprite_px / 2` (with a `Log.warn`), so the ring is never bigger than the ship.
  - Colours: a `text` (#E8F4FF) stroke over a `background` (#05070F) outline. It sweeps clockwise from 12 o'clock and draws nothing when the ratio is 0 (ready).

### Architecture Decision Records

**ADR-001: JSON over Godot Resources (`.tres`) for content.**
Waves, dialogue and tuning are nested, list-heavy data that will be authored by hand and by AI agents.

- Hand-written `.tres` files need correct `ext_resource` and `uid` bookkeeping, and agents get that wrong.
- JSON diffs cleanly, can be hot-reloaded with F5, and has no schema-class boilerplate.
- *Cost:* no Inspector editing and no static typing of the data. This is mitigated by load-time validation in `Config` and by the GUT data tests.
- *Revisit if:* a designer wants to edit waves in the Inspector.

**ADR-002: No object pooling by default.**
The peak load (≈ 40 enemies + 200 projectiles) is well within Godot's 2D budget. Pooling adds lifecycle bugs (stale state, double-free), which is a high risk for a newcomer.

- All creation goes through `Spawner`, so pooling can be added there later without touching callers.
- *Trigger:* E8 profiling shows frame time > 16.6 ms caused by instancing or freeing.

**ADR-003: Forward+ renderer with a Compatibility fallback.**
Forward+ is Godot's default. It supports `hdr_2d` and `WorldEnvironment` glow, which give the neon look cheaply.

- The neon look must **also** work without glow: glow sprites use `CanvasItemMaterial` additive blend. That way, switching to the Compatibility renderer (faster start, lighter on weak iGPUs) is a one-setting change.
- *Trigger:* E1 sandbox below 60 FPS on the dev laptop, or cold start over 5 s.

**ADR-004: Retry by scene reload.**
`SceneRouter.restart_level()` reloads `level.tscn` with the same level id. No reset methods exist on entities. This removes a whole class of "forgot to reset X" bugs.

- Energy is reset in `GameState` *before* the reload.

**ADR-005: Custom comms, not Dialogic 2.**
The required features are narrow (typewriter, portrait, pause vs. auto, cut-off, 2-option choice, triggered by wave events). A custom ~150-line system tied into the Wave Director is less to learn than Dialogic's timeline system, and it keeps the runtime plugin-free.

**ADR-006: Single generic level scene.**
All per-level differences go in `level_<id>.json`: background, ally, convoy on/off, waves, triggers and music. A fourth level (stretch scope) is just a new JSON file.

---

## Cross-cutting Concerns

These patterns apply to ALL systems. Every implementation must follow them.

### Error Handling

**Strategy:** fail loudly in debug builds and degrade gracefully in release. GDScript has no exceptions, so:

| Level | When | How | Player-visible? |
|---|---|---|---|
| **Programmer error** | Impossible state, a broken invariant | `assert(cond, "msg")` (stripped in release) + `Log.error` | No |
| **Data error** | Missing or invalid JSON key, unknown enemy id or sequence id | `Log.error` with file and key path. Skip the offending item and keep running | No |
| **Recoverable runtime** | Corrupt save, missing audio stream | `Log.warn` + fall back to the default or silence | No |
| **Fatal** | `tuning.json` fails to parse at boot | `Log.error` + show a plain error label on the title screen. Don't start levels | Yes (simple text) |

Rules:

- **Never** let an error soft-lock a wave. If a spawn entry is invalid, the Wave Director logs it and **does not count it** toward the wave total.
- Null-check every `get_node_or_null` and every registry lookup. Don't use bare `$Path` for optional nodes.
- Errors never pause the game.

```gdscript
func spawn_enemy(type_id: StringName, params: Dictionary) -> Enemy:
	var scene: PackedScene = EntityRegistry.ENEMIES.get(type_id)
	if scene == null:
		Log.error("spawn", "Unknown enemy type '%s' in %s" % [type_id, params.get("_src", "?")])
		return null   # caller (WaveDirector) must treat null as "not counted"
	var enemy := scene.instantiate() as Enemy
	enemy.setup(params)
	_containers.enemies.add_child(enemy)
	return enemy
```

### Logging

**Format:** `[LEVEL][category] message`, plain text. **Destination:** the Godot console plus the built-in file log (`debug/file_logging/enable_file_logging = true`, also for release, so `%APPDATA%\DEFECTOR\logs\godot.log` exists when a playtester reports a bug).

| Level | Use | Release build |
|---|---|---|
| `ERROR` | Something broke (also `push_error`, so it shows in the debugger) | Logged |
| `WARN` | Unexpected but handled (also `push_warning`) | Logged |
| `INFO` | Milestones: scene change, level start and clear, wave start and clear, beat fired, save written | Logged |
| `DEBUG` | Detailed diagnostics (spawn details, trigger evaluation) | **Dropped** (`OS.is_debug_build()` false) |

- Categories (fixed list): `boot`, `scene`, `wave`, `beat`, `comms`, `spawn`, `combat`, `save`, `audio`, `data`, `debug`.
- **No logging in per-frame paths** (`_process`, `_physics_process`, per-projectile hits). Log events, not frames.
- Don't use bare `print()` anywhere except inside `Log`.

```gdscript
Log.info("wave", "Level %d wave %d cleared (%d resolved)" % [level_id, wave_index + 1, resolved])
Log.warn("save", "Unknown save_version %d, using defaults" % v)
Log.debug("beat", "Trigger %s at %.2f progress" % [trigger_id, progress])
```

### Configuration

**Approach:** JSON files in `res://data/`, loaded once at boot by the `Config` autoload and accessed through typed getters. **F5 (debug builds)** reloads the data and restarts the current scene so every `_ready` cache re-reads it (see the reload rules below).

| Type | Location | Example |
|---|---|---|
| Game constants (never tuned) | `const` in the owning script or a shared constants class | `Playfield.SIZE` / `Playfield.RECT` (`core/playfield.gd`, `class_name Playfield`: `const SIZE := Vector2(1920, 1080)`, `const RECT := Rect2(Vector2.ZERO, SIZE)`) |
| Balancing values | `data/tuning.json` | player zone, weapon stats, enemy stats, drop table, feedback tiers |
| Feature flags | `data/flags.json` | `{"surrender_prompts": true, "isolde_interruptions": true, "tarek_fall": true, "hunter_wasp": false}` |
| Level content | `data/levels/level_<n>.json` | waves, triggers, ally, background, music |
| Dialogue | `data/dialogue/<scene>.json` | `opening.json`, `level_1.json` … |
| Player settings | none in v1 | window mode toggled with F11, not persisted |

**Access rules:**

- The getters are exactly: `Config.num("weapons.missile.speed_px_s")` → `float`, `Config.int_("enemies.wasp.hp")` → `int`, `Config.flag("surrender_prompts")` → `bool`, and `Config.section("feedback.tiers")` → `Dictionary` (a deep copy). Level and dialogue getters are planned (see Data Patterns).
- A missing key gives `Log.error` + `assert` and returns `0` / `false` / `{}`. The `assert` fires only while `Config.assert_on_missing` is `true` (the default); tests set it to `false` to check the fallback. **Never** index `Config.tuning[...]` directly from gameplay code.
- **JSON numbers are always `float` in Godot (verified on 4.7.2).** Anything used as a count, HP, index or loop bound **must** come through `Config.int_()` or be wrapped in `int()`.
- Read tuning in `setup()` / `_ready()` and cache it in member variables. Never call `Config` per frame.

```gdscript
# entities/player/player_weapons.gd (excerpt)
var _missile_speed: float
var _missile_damage: int

func _ready() -> void:
	_missile_speed = Config.num("weapons.missile.speed_px_s")
	_missile_damage = Config.int_("weapons.missile.damage")
```

**Reload (`Config.reload() -> bool`, as built):**

- It re-reads the files last passed to `load_data()` into temporaries and validates their shape against the data loaded now. Every current key path must still exist with the same kind (int and float both count as a number). Extra keys are allowed. Array elements aren't checked. If the boot load failed, so the current data is empty, there is nothing to compare against and any shape is accepted.
- On any failure it logs `Log.error("data", "Reload rejected (...); previous data kept")`, returns `false`, and leaves `tuning`, `flags` and `load_error` untouched.
- On success it commits both files, clears `load_error`, logs the load summary and returns `true`.
- F5 runs `DebugTools.reload_data()`: `Config.reload()`. If that returns `false`, it logs and stops (the scene isn't restarted). If `true`, it runs `Feedback.reset()`, `Feedback.load_tiers()`, `PauseArbiter.clear()`, then restarts the current scene (`get_tree().reload_current_scene`) so every `_ready` cache re-reads the data and the scene root re-applies `render.glow`.

### Event System

**Pattern:** Godot signals. There are two scopes:

1. **Local signals** on a node, for parent ↔ child or a scene-local wiring (`health_component.died`, `enemy.resolved`).
2. **`Events` autoload** (global bus with typed signals) for cross-system notifications that the HUD, audio, comms or WaveDirector consume.

**Naming:** `snake_case`, **past tense** for facts (`enemy_killed`, `wave_cleared`), and `*_requested` for commands to a single owner (`comms_sequence_requested`). The signals are synchronous. There's no event history.

**Rule:** if exactly one known node must act, call its method directly. Use `Events` only when the emitter must not know its listeners.

Complete `Events` catalogue (agents must add new signals **here first**):

```gdscript
# res://autoloads/events.gd
extends Node

# Player
signal hearts_changed(current: int, max_hearts: int)
signal player_hit(position: Vector2)
signal player_died
signal energy_changed(current: int, max_energy: int)
signal ability_denied(ability: StringName)          # &"shield" | &"barrage"
signal missile_cooldown_changed(ratio: float)        # 0 = ready, 1 = just fired

# Combat
signal enemy_killed(enemy_type: StringName, position: Vector2, by_ally: bool)
signal asteroid_destroyed(size: StringName, position: Vector2)

# Waves / level
signal level_started(level_id: int)
signal wave_started(wave_index: int, wave_count: int)
signal wave_progress_changed(wave_index: int, ratio: float)
signal wave_cleared(wave_index: int)
signal level_cleared(level_id: int)
signal level_failed(reason: StringName)              # &"hearts" | &"convoy"

# Escort / boss
signal convoy_hp_changed(current: int, max_hp: int)
signal boss_started
signal boss_hp_changed(current: int, max_hp: int, phase: int)
signal boss_phase_changed(phase: int)
signal boss_defeated

# Comms
signal comms_sequence_requested(sequence_id: StringName)
signal comms_sequence_finished(sequence_id: StringName)
signal final_choice_made(choice: StringName)         # &"surrender" | &"destroy"
signal story_event_requested(event_name: StringName) # e.g. &"tarek_fall"
```

### Debug Tools

Debug tools are available **only when `OS.is_debug_build()`** (editor runs and debug exports). In release builds they do nothing (`DebugTools.debug_enabled` is false: early return, processing off). A single `DebugTools` node in `Overlay` (`ui/debug/debug_tools.tscn` + `debug_tools.gd`) handles the keys.

**Implemented today: F1 and F5.** The other keys are planned for the epics that need them.

| Key | Tool | Status |
|---|---|---|
| F1 | Toggle debug overlay. Built: FPS, frame ms (avg / max over a 0.25 s window, real time), node count, enemies alive. Planned additions: wave `n/N`, resolved/total, pause reasons, current comms sequence | Built (partial) |
| F2 | Toggle player invincibility | Planned |
| F3 | Resolve the current wave (kill every counted enemy and fire its pending triggers in order) | Planned |
| F4 | Energy +100 (capped) | Planned |
| F5 | Reload `tuning.json` and `flags.json` through `Config.reload()`, then restart the scene (see [Configuration](#configuration)) | Built |
| F6 | Jump to the boss wave in the current level (if any) | Planned |
| F7 | Unlock all levels (in memory, not saved) | Planned |
| F8 | *(Add only if needed)* Save a screenshot of the viewport to `user://screenshots/shot_<timestamp>.png` so AI agents can inspect the running game. This replaces the screenshot feature of an engine MCP | Planned |
| F11 | Toggle borderless fullscreen / windowed (**available in release too**) | Planned |

**Command-line modes (debug builds only, Story 1.7):** `DebugArgs.parse(OS.get_cmdline_user_args())` (`ui/debug/debug_args.gd`) returns `{stress: bool, bench_s: float}`. The scene root and `DebugTools` both read it.

- `-- --stress`: the sandbox spawns a 10×4 grid of 40 Wasps and refills each slot when its Wasp dies. The overlay starts on, and vsync is turned off so frame ms measures work, not the display wait.
- `-- --bench=N` implies `--stress`. It warps the cursor to `DebugTools.BENCH_AIM` (1040, 900), holds `fire_laser`, skips 2 s of warm-up, samples N s of frame times into `FrameStats` (`ui/debug/frame_stats.gd`), then logs one line and quits:
  `[INFO][debug] Stress bench: frames=… avg=… ms p99=… ms max=… ms enemies=… renderer=… window=… vsync=… result=PASS|FAIL`.
  The exit code is 0 if the average is under 16.6 ms, otherwise 2. A malformed or non-positive N logs a warning and is ignored.

---

## Project Structure

### Organization Pattern

**Pattern:** a **hybrid by feature**. Each entity or feature keeps its `.tscn` and `.gd` together in one folder. Cross-cutting services live in `autoloads/`, and data lives in `data/`.

**Rationale:** for a newcomer and for AI agents, "the Wasp lives in `entities/enemies/wasp/`" is easier to follow than splitting scenes and scripts into parallel trees.

### Directory Structure

This is the target tree. As of Epic 1 the built parts are: `project.godot`, `export_presets.cfg` and `default_bus_layout.tres`; the autoloads `Log`, `Events`, `Config`, `PauseArbiter`, `Audio`, `Feedback`, `EntityRegistry`; `core/` except `health_component.gd`; `entities/player/` (without the shield); `entities/projectiles/` laser and missile; `entities/enemies/wasp/`; `entities/asteroids/`; `entities/effects/`; `systems/camera/`; `scenes/sandbox/`; `ui/debug/`; `data/tuning.json` and `data/flags.json`; `assets/audio/sfx/` and `assets/CREDITS.md`; `addons/gut/`; and `tests/unit/` (plus `tests/fixtures/`). Everything else is planned.

```
<repo root>/
├── _bmad/, _bmad-output/, .claude/ …        # planning (not part of the Godot project)
├── README.md                                # controls + premise (E8)
└── game/                                    # ← Godot project root (res://)
    ├── project.godot
    ├── export_presets.cfg                   # Windows Desktop preset (commit it)
    ├── default_bus_layout.tres              # audio buses: Master → Music, SFX, UI
    ├── .gitignore                           # .godot/, export/, *.tmp
    ├── autoloads/
    │   ├── events.gd                        # Events
    │   ├── log.gd                           # Log
    │   ├── config.gd                        # Config
    │   ├── game_state.gd                    # GameState
    │   ├── save_manager.gd                  # SaveManager
    │   ├── pause_arbiter.gd                 # PauseArbiter
    │   ├── scene_router.gd                  # SceneRouter
    │   ├── audio.gd                         # Audio
    │   ├── feedback.gd                      # Feedback (impact tiers, shake, hit-stop)
    │   └── entity_registry.gd               # EntityRegistry (id → PackedScene consts)
    ├── core/                                # shared non-autoload classes
    │   ├── spawner.gd                       # Spawner (class_name), lives in sandbox.tscn today (level.tscn planned)
    │   ├── health_component.gd              # HealthComponent
    │   ├── projectile.gd                    # Projectile base (class_name)
    │   ├── enemy.gd                         # Enemy base (class_name)
    │   ├── impact_tier.gd                   # ImpactTier enum holder + tier names
    │   ├── playfield.gd                     # Playfield: SIZE, RECT (1920×1080)
    │   ├── render_glow.gd                   # RenderGlow.apply(env): render.glow → Environment
    │   └── collision_layers.gd              # CollisionLayers: layer bits + shot masks
    ├── entities/
    │   ├── player/            player.tscn, player.gd, player_weapons.gd, missile_ring.gd, shield_bubble.tscn (planned)
    │   ├── projectiles/       laser_bolt.tscn, missile.tscn, micro_missile.tscn,
    │   │                      enemy_bullet.tscn, needle_bolt.tscn (+ .gd each)
    │   ├── enemies/
    │   │   ├── wasp/          wasp.tscn, wasp.gd
    │   │   ├── lancer/        lancer.tscn, lancer.gd
    │   │   ├── needle/        needle.tscn, needle.gd
    │   │   ├── bastion/       bastion.tscn, bastion.gd
    │   │   ├── maul/          maul.tscn, maul.gd
    │   │   └── hunter_wasp/   hunter_wasp.tscn, hunter_wasp.gd   (COULD)
    │   ├── boss/              flagship.tscn, flagship.gd, flagship_turret.tscn, flagship_turret.gd,
    │   │                      flagship_core.tscn, flagship_core.gd
    │   ├── asteroids/         asteroid.tscn, asteroid.gd           # one scene, size from setup()
    │   ├── pickups/           energy_orb.tscn, energy_orb.gd
    │   ├── allies/            ally_ship.tscn, ally_ship.gd, convoy.tscn, convoy.gd, convoy_ship.tscn
    │   └── effects/           explosion.tscn, explosion.gd (one scene for every tier),
    │                          shockwave_ring.gd (ShockwaveRing, drawn in code, no .tscn)
    ├── systems/
    │   ├── waves/             wave_director.gd, beat_trigger.gd, wave_progress.gd
    │   ├── comms/             comms_channel.gd, comms_panel.tscn, comms_panel.gd,
    │   │                      final_choice.tscn, final_choice.gd
    │   └── camera/            shake_camera.gd
    ├── scenes/
    │   ├── boot/              boot.tscn, boot.gd                  # main scene: loads Config, Save → Title
    │   ├── title/             title.tscn, title.gd, level_select.tscn, level_select.gd
    │   ├── story/             story.tscn, story.gd                # comms-only paused scene
    │   ├── level/             level.tscn, level.gd
    │   ├── end/               end_screen.tscn, end_screen.gd
    │   └── sandbox/           sandbox.tscn, sandbox.gd            # Epic 1 debug sandbox (current main scene)
    ├── ui/
    │   ├── hud/               hud.tscn, hud.gd, hearts_display.gd, energy_bar.gd,
    │   │                      wave_bar.gd, boss_bar.gd, convoy_bar.gd
    │   ├── menus/             pause_menu.tscn, pause_menu.gd, retry_prompt.tscn, retry_prompt.gd
    │   ├── debug/             debug_tools.tscn, debug_tools.gd, debug_args.gd, frame_stats.gd
    │   └── theme/             defector_theme.tres, fonts/
    ├── data/
    │   ├── tuning.json
    │   ├── flags.json
    │   ├── levels/            level_1.json, level_2.json, level_3.json
    │   └── dialogue/          opening.json, level_1.json, level_2.json, level_3.json, ending.json
    ├── assets/
    │   ├── sprites/           player/, enemies/, boss/, allies/, asteroids/, projectiles/, fx/, ui/
    │   ├── portraits/         isolde.png, tarek.png, ryn.png, vale.png (optional)
    │   ├── backgrounds/       space_1.png, space_2.png, throne_world_arc.png
    │   ├── audio/
    │   │   ├── sfx/
    │   │   └── music/
    │   ├── shaders/           (only if needed)
    │   └── CREDITS.md         # every third-party asset: source + licence
    ├── addons/
    │   └── gut/               # dev-only; excluded from export
    └── tests/
        ├── unit/              test_config.gd, test_save_manager.gd, test_wave_progress.gd,
        │                      test_beat_trigger.gd, test_pause_arbiter.gd
        └── data/              test_data_files.gd   # validates every JSON in data/
```

### System Location Mapping

| System | Location | Responsibility |
|---|---|---|
| Global events | `autoloads/events.gd` | Signal catalogue only, no logic |
| Logging | `autoloads/log.gd` | Levelled, categorised logging |
| Tuning, flags, level and dialogue data | `autoloads/config.gd` + `data/` | Load, validate, typed getters, hot reload |
| Run state (energy, unlocks, current level) | `autoloads/game_state.gd` | Single source of truth for cross-scene state |
| Save / load | `autoloads/save_manager.gd` | Only writer and reader of `user://save.cfg` |
| Pause | `autoloads/pause_arbiter.gd` | Pause reasons → `tree.paused` + mouse mode |
| Scene flow | `autoloads/scene_router.gd` | `goto_title()`, `start_level(id)`, `restart_level()`, `goto_story(id, next)`, `goto_end()` |
| Audio | `autoloads/audio.gd` | SFX pool, music, registry |
| Impact feedback | `autoloads/feedback.gd` + `systems/camera/shake_camera.gd` | Tier → explosion, shake, hit-stop, SFX |
| Entity scenes registry | `autoloads/entity_registry.gd` | `const` dicts of `preload`ed scenes |
| Spawning | `core/spawner.gd` (node in the scene root: today `sandbox.tscn`; `level.tscn` planned) | The only place that instantiates gameplay entities |
| Player ship, weapons, abilities | `entities/player/` | `player.gd` (`Player`): cursor lock, bounds, hurtbox and sizing; delegates firing to its `Weapons` child. `player_weapons.gd` (`class_name PlayerWeapons extends Node`, the `Weapons` child): laser and missile timing, spawning, sfx and `missile_cooldown_changed`; API `set_spawner(spawner)`, `step_fire(held, delta)`, `step_missile(pressed, delta)`, which `Player` keeps as one-line delegators. `missile_ring.gd` (`MissileRing`): cooldown ring. Planned: hearts, shield, barrage |
| Enemies | `entities/enemies/<type>/` | Behaviour per type, extends `Enemy` |
| Flagship | `entities/boss/` | Phases, turrets, core, final-choice hook |
| Asteroids | `entities/asteroids/` | Drift, rotate, block, damage, drop |
| Energy orbs | `entities/pickups/` | Drift, magnet, despawn, collect |
| Convoy, allies | `entities/allies/` | Paths, shared HP, ally targeting, Tarek's fall |
| Explosions and FX | `entities/effects/` | Visual only |
| Waves and beat triggers | `systems/waves/` | Novel pattern: see Implementation Patterns |
| Comms and Final Choice | `systems/comms/` | Novel pattern: see Implementation Patterns |
| HUD | `ui/hud/` | Signal-driven display |
| Menus | `scenes/title/`, `ui/menus/` | Title, level select, pause, retry |
| Debug tools | `ui/debug/` | Debug-build keys and overlay |
| Tests | `tests/` | GUT unit and data tests |

### Naming Conventions

#### Files

- All files and folders: `snake_case` (`wave_director.gd`, `level_select.tscn`).
- A scene and its root script share a base name and folder (`wasp.tscn` + `wasp.gd`).
- Data files: `snake_case.json`. Level files are `level_<n>.json`, with `n` = 1, 2, 3.
- Tests: `test_<subject>.gd`.
- Assets: `<subject>_<variant>[_<state>].<ext>`, for example `wasp_base.png`, `asteroid_large_02.png`, `sfx_explosion_large.wav`, `portrait_tarek.png`.

#### Code Elements

| Element | Convention | Example |
|---|---|---|
| Class (`class_name`) | PascalCase, only for types other scripts reference | `class_name Enemy`, `WaveDirector` |
| Autoload name | PascalCase | `Events`, `Config`, `GameState` |
| Function / variable | snake_case | `apply_damage()`, `fire_interval` |
| Private member | `_` prefix | `_cooldown_left`, `_on_area_entered()` |
| Constant | UPPER_SNAKE | `const MAX_ENERGY := 100` |
| Enum type / values | PascalCase / UPPER_SNAKE | `enum State { ENTERING, HOLDING, DIVING }` |
| Signal | snake_case, past tense | `wave_cleared`, `hearts_changed` |
| Signal handler | `_on_<emitter>_<signal>` | `_on_health_died()`, `_on_events_wave_cleared()` |
| Node names in scenes | PascalCase | `Hurtbox`, `MuzzleLeft`, `TelegraphLine` |
| Unique scene nodes | `%PascalCase` | `%TypewriterLabel` |
| StringName ids (types, sfx, sequences, events) | `&"snake_case"` | `&"wasp"`, `&"explosion_large"`, `&"l2_tarek_cutoff"` |
| Groups | snake_case plural | `enemies`, `asteroids`, `counted` |

#### Game Data Ids

- Enemy type ids: `wasp`, `lancer`, `needle`, `bastion`, `maul`, `hunter_wasp`, `flagship`.
- Asteroid sizes: `small`, `medium`, `large`.
- Dialogue sequence ids: `<scene>_<beat>`. For example: `opening_main`, `l1_w1_tutorial_move`, `l1_w3_isolde_interrupt`, `l1_w5_surrender`, `l2_w5_tarek_cutoff`, `l2_ryn_report`, `l3_final_choice`, `l3_isolde_refuse_surrender`, `l3_isolde_refuse_destroy`, `l3_isolde_final`.
- Speaker ids: `vale`, `isolde`, `tarek`, `ryn`, `system`.

### Architectural Boundaries

1. **Autoloads never reference scene nodes by path.** Scene nodes register themselves and unregister on `_exit_tree()`. As built: `ShakeCamera` calls `Feedback.register_camera(self)` in `_enter_tree()` and `Feedback.unregister_camera(self)` in `_exit_tree()`; `Spawner` calls `Feedback.register_spawner(self)` in `_ready()` (see [Impact Feedback Tiers](#3-impact-feedback-tiers)).
2. **Entities never touch the HUD, menus or other entities' internals.** They emit `Events` or local signals. Damage is the one direct call allowed: a projectile calls `apply_damage()` on whatever it hits.
3. **Only the `Spawner` instantiates gameplay entities.** Only the `WaveDirector` decides *what* spawns and *when* (except boss-launched Wasps, which the Flagship requests through the `Spawner`).
4. **Only `SceneRouter` changes scenes. Only `PauseArbiter` pauses. Only `Feedback` touches `Engine.time_scale` and the camera offset. Only `SaveManager` touches `user://`.** The one exception today is debug-only: F5 in `DebugTools` calls `get_tree().reload_current_scene` (see Reload).
5. **Only `CommsChannel` shows dialogue.** Story logic never sets label text directly.
6. **`data/` is read-only at runtime.** Code never writes to `res://`.
7. **Never use absolute node paths** (`/root/...`) or `get_parent().get_parent()` chains. Use exported `NodePath`s, `%UniqueNames`, groups or signals.

---

## Implementation Patterns

These patterns keep the implementation consistent across all AI agents.

### Novel Patterns

#### 1. Wave Director + Beat Triggers

**Purpose:** run scripted waves from data, track "% of wave destroyed", fire story beats (comms, reinforcements, story events, music) at precise moments, and guarantee that every wave can be cleared.

**Components:**

| Component | Responsibility |
|---|---|
| `WaveDirector` (node in `level.tscn`) | Loads the level JSON. Runs waves in order. Asks the `Spawner` to spawn. Counts resolved enemies. Evaluates triggers. Emits wave signals |
| `WaveProgress` (pure `RefCounted`, unit-tested) | `total_counted`, `resolved`, `ratio()`, `is_complete()` |
| `BeatTrigger` (pure `RefCounted`, unit-tested) | One trigger's condition (`when`, `at`, `flag`) + `has_fired`. `should_fire(event, ratio, flags) -> bool` |
| Actions (handled inside `WaveDirector._run_actions`) | `comms`, `spawn_group`, `story_event`, `music`, `wait` |

**Level data shape (`data/levels/level_1.json`, abridged):**

```json
{
  "id": 1,
  "name": "Cargo Ambush",
  "background": "space_1",
  "music": "combat",
  "convoy": true,
  "ally": "tarek",
  "intro_sequence": null,
  "outro_sequence": "l1_tarek_closing",
  "waves": [
    {
      "spawns": [
        { "type": "wasp", "count": 8, "formation": "grid_4x2", "entry": "top" }
      ],
      "asteroids": [],
      "triggers": [
        { "when": "wave_start", "actions": [ { "comms": "l1_w1_tutorial_move" } ] }
      ]
    },
    {
      "spawns": [
        { "type": "wasp", "count": 16, "formation": "grid_8x2", "entry": "top" },
        { "type": "lancer", "count": 3, "entry": "sides" }
      ],
      "groups": {
        "reinforcements": [ { "type": "maul", "count": 4, "entry": "sides" } ]
      },
      "triggers": [
        { "when": "progress", "at": 0.30, "flag": "surrender_prompts",
          "actions": [ { "comms": "l1_w5_surrender" }, { "spawn_group": "reinforcements" } ] },
        { "when": "progress", "at": 0.30, "flag": "!surrender_prompts",
          "actions": [ { "spawn_group": "reinforcements" } ] }
      ]
    }
  ]
}
```

**Rules (unambiguous):**

- `when` ∈ `wave_start` | `progress` (with `at` ∈ 0–1) | `wave_clear` | `boss_phase` (with `phase`) | `boss_hp_le` (with `hp`).
- `flag` is optional. A `"!"` prefix negates it. A trigger whose flag fails never fires.
- **Totals are known up front.** `total_counted` = every entry in `spawns` **plus** every entry in all `groups` of that wave. The progress bar is monotonic, and reinforcements can't cause an early "clear".
- **Resolved** means killed (by the player or an ally), *or* a Maul that ended its dive without hitting anything (it emits `resolved` without a kill). Wasps that leave the screen re-enter, so they don't resolve.
- Each trigger fires **at most once** per level attempt. Triggers are checked in array order after every resolve.
- Actions run **sequentially**: `comms` with a story-mode sequence `await`s `Events.comms_sequence_finished`, and combat-mode sequences don't block. A trigger whose actions are still running doesn't block other triggers.
- **Wave clear** = `resolved == total_counted` **and** all of the wave's action chains have finished. Then `wave_clear` triggers fire, then a 2.0 s gap (`tuning.waves.gap_s`), then the next wave.
- **Boss wave:** `{ "boss": "flagship", "triggers": [...] }`. The total is 1 (the Flagship). It resolves on `boss_defeated`. Boss-launched Wasps are **not** counted.
- After the last wave: `outro_sequence` (if any) → `Events.level_cleared` → `GameState` and `SaveManager` update → `SceneRouter` goes to the next story or level.
- A spawn entry that fails (unknown type) is logged and **subtracted** from `total_counted`, so the wave can never soft-lock.

**Data flow:**

```
WaveDirector.start_wave(i)
  → progress.reset(total)  → Events.wave_started
  → fire triggers(when=wave_start)
  → Spawner.spawn_enemy(...) per entry ── each enemy.resolved ─┐
                                                             ▼
                        _on_enemy_resolved(): progress.resolved += 1
                        → Events.wave_progress_changed(i, ratio)
                        → for t in triggers: if t.should_fire(&"progress", ratio, flags): _run_actions(t)
                        → if progress.is_complete() and no running chains: _clear_wave()
```

```gdscript
# systems/waves/wave_director.gd (excerpt)
func _on_enemy_resolved() -> void:
	_progress.resolved += 1
	Events.wave_progress_changed.emit(_wave_index, _progress.ratio())
	for trigger: BeatTrigger in _triggers:
		if trigger.should_fire(&"progress", _progress.ratio(), Config.flags):
			_run_actions(trigger)          # not awaited here: it runs as its own chain
	_try_clear_wave()

func _run_actions(trigger: BeatTrigger) -> void:
	trigger.has_fired = true
	_running_chains += 1
	for action: Dictionary in trigger.actions:
		if action.has("comms"):
			var seq := StringName(action.comms)
			Events.comms_sequence_requested.emit(seq)
			if Config.dialogue_is_story(seq):
				await _wait_for_sequence(seq)
		elif action.has("spawn_group"):
			_spawn_group(StringName(action.spawn_group))
		elif action.has("story_event"):
			Events.story_event_requested.emit(StringName(action.story_event))
		elif action.has("music"):
			Audio.apply_music_action(StringName(action.music))   # &"stop" | &"combat" | &"boss"
		elif action.has("wait"):
			await get_tree().create_timer(float(action.wait), false).timeout
	_running_chains -= 1
	_try_clear_wave()
```

**Edge cases:**

- Tarek's fall fires at 50% while comms is silenced. The `story_event` action `tarek_fall` handles the ally, and the `comms` action uses a cut-off line that sets silence.
- The F3 debug resolve fires the remaining progress triggers in order, so beats can be tested.
- Death mid-chain: the scene reloads, so every chain is discarded with the scene.

#### 2. Comms Channel

**Purpose:** the single delivery path for all story (Pillar 3).

**Line types:**

- **Story lines** pause the game and advance on click.
- **Combat lines** auto-advance without pausing.
- **Cut-off lines** stop mid-sentence and are followed by static, shake and silence.
- **Choice lines** show two buttons.

**Dialogue data (`data/dialogue/level_2.json`):**

```json
{
  "sequences": {
    "l2_w5_tarek_cutoff": {
      "mode": "combat",
      "lines": [
        { "speaker": "tarek", "text": "General, get behind me, I've got you cov—",
          "cut_off_at": 39, "after": { "silence": "until_wave_clear", "shake": "large",
                                        "sfx": "comms_static", "music": "stop" } }
      ]
    },
    "l2_ryn_report": {
      "mode": "story",
      "lines": [
        { "speaker": "ryn", "text": "He's alive. Barely. I'm taking his ship, General." }
      ]
    }
  }
}
```

```json
"l3_final_choice": {
  "mode": "story",
  "lines": [ { "speaker": "isolde", "text": "..." } ],
  "choice": {
    "options": [
      { "id": "surrender", "label": "Offer Surrender", "next": "l3_isolde_refuse_surrender" },
      { "id": "destroy",   "label": "Destroy Her",     "next": "l3_isolde_refuse_destroy" }
    ]
  }
}
```

**Components:**

| Component | Responsibility |
|---|---|
| `CommsChannel` (`Node`, child of `Comms` CanvasLayer, `PROCESS_MODE_ALWAYS`) | Queue, mode logic, pause reasons, silence flag, emits `comms_sequence_finished` |
| `CommsPanel` (`Control`) | Portrait, name, typewriter label (`visible_characters` tween), click to advance |
| `FinalChoice` (`Control`) | Two buttons. Emits `Events.final_choice_made`, then the channel plays `next` |

**Rules:**

- **Story** sequence: `PauseArbiter.push(&"story")`, then show each line with the typewriter (`tuning.comms.chars_per_s`, default 45). On click: if the line is still typing, complete it; if it's complete, go to the next line. After the last line: `PauseArbiter.pop(&"story")` and emit `finished`.
- **Combat** sequence: no pause, and input is ignored. Each line stays for `max(2.0, chars / chars_per_s + 1.2)` seconds, then advances.
- **Priority:**
  - A story sequence **preempts** any playing combat line. The combat line is dropped, and its sequence still emits `finished`.
  - A combat sequence requested while another combat sequence plays is **queued** (FIFO, max 3, oldest dropped).
  - A story sequence requested while a story sequence plays is queued (never dropped).
- **Silence:** while `silenced`, combat sequences are dropped (logged at DEBUG). Story sequences are still delivered. `until_wave_clear` silence clears on `Events.wave_cleared`.
- **Cut-off:** the typewriter stops at `cut_off_at` characters. Then the `after` effects run: `Audio.play_sfx(&"comms_static")`, `Feedback.shake_tier(...)`, `Audio.stop_music()`, silence. The panel then hides after 0.6 s.
- **Choice:** `PauseArbiter.push(&"final_choice")` while the buttons are shown. There's no timer. The choice is saved to `GameState.final_choice` for a possible epilogue.
- Unknown sequence id: `Log.error` and immediately emit `finished`, so the waiting chains never hang.

```gdscript
# Typical caller: anything that wants dialogue
Events.comms_sequence_requested.emit(&"l1_w3_isolde_interrupt")
```

#### 3. Impact Feedback Tiers

**Purpose:** Pillar 2. Every destruction or hit calls **one** function. The tier table comes from data, not from per-entity code.

```gdscript
# core/impact_tier.gd
class_name ImpactTier
enum { SMALL, MEDIUM, LARGE, BOSS_PART, BOSS_DEATH, PLAYER_HIT, PLAYER_DEATH }
```

```json
// tuning.json → "feedback": { "tiers": { ... } }
"large": { "explosion_scale": 2.0, "shake_px": 8, "shake_s": 0.25, "hit_stop_ms": 40,
           "extras": ["debris", "shockwave"], "sfx": "explosion_large", "sfx_pitch": 0.8,
           "sfx_volume_db": 0 }
```

The real rows are in `data/tuning.json` → `feedback.tiers`, one per `ImpactTier.NAMES` entry. `sfx_volume_db` is small -6, medium -3, large 0, and 0 for the boss and player tiers (GDD decision #26).

**`Feedback` as built (`autoloads/feedback.gd`):**

- `Feedback.load_tiers()` reads every tier row through `Config` and caches it. It runs in `_ready` and again on F5.
- `impact(tier, pos)` runs in this order:
  1. range check (an unknown tier logs `Log.error` and returns),
  2. `_spawner.spawn_explosion({position, scale: explosion_scale, extras})`,
  3. `ShakeCamera.shake(shake_px, shake_s)` if both are above 0 and a camera is registered,
  4. `hit_stop(hit_stop_ms)` if `hit_stop_ms` is above 0,
  5. `Audio.play_sfx(row.sfx, Audio.DEFAULT_PITCH_JITTER, row.sfx_volume_db, row.sfx_pitch)`.
- `prewarm()` spawns one explosion per tier at `PREWARM_POSITION` (-1000, 540) with no shake, hit-stop or sfx. The scene root calls it at the end of `_ready` (today `sandbox.gd`). It does nothing if no Spawner is registered, so it relies on Godot running the child `Spawner`'s `_ready` (which registers it) before the scene root's `_ready`.
- `reset()` ends any hit-stop at once (`Engine.time_scale = 1.0`).

**Single explosion scene:** `EntityRegistry.EXPLOSION` = `entities/effects/explosion.tscn` + `explosion.gd` (`class_name Explosion`), used by every tier. Sparks, debris and the shockwave are children of this scene, not separate scenes.

- `setup(params)` takes `position`, `scale` and `extras`; `_ready` applies them.
- Children: `Burst` (always plays), then `Sparks`, `Debris` and `Shockwave`, toggled by the extras `sparks` / `debris` / `shockwave`. `Shockwave` is a `ShockwaveRing` node drawn by `shockwave_ring.gd` (no `.tscn`).
- It frees itself after `LIFETIME_S` (1.0 s). `Spawner.spawn_explosion(params)` parents it to `World/Effects`.

**Registration (accepted design, Epic 1 retro C1):**

- `ShakeCamera` calls `Feedback.register_camera(self)` in `_enter_tree` and `Feedback.unregister_camera(self)` in `_exit_tree`.
- `Spawner` calls `Feedback.register_spawner(self)` in `_ready`, only if its `world` has an `Effects` container, and `Feedback.unregister_spawner(self)` in `_exit_tree`.
- `unregister_*` clears the slot only if the argument is the registered node, so a freed old scene can't clear a newer one. The last registration wins.
- With no spawner registered, `impact` skips the explosion. With no camera, it skips the shake.

**Known gaps (registered when their epic lands):** the `boss_part`, `boss_death`, `player_hit` and `player_death` rows name sfx ids that `Audio.SFX` doesn't register yet (they warn once and play nothing). The extras `white_flash` and `red_vignette` aren't handled by `Explosion` yet (ignored).

```gdscript
# Every entity death looks like this — nothing else:
func _die() -> void:
	Feedback.impact(_tier, global_position)    # explosion + shake + hit-stop + sfx
	Events.enemy_killed.emit(type_id, global_position, _last_hit_by_ally)
	_drop_loot()
	resolved.emit()
	queue_free()
```

- Shake: `ShakeCamera` keeps the **strongest** active shake. It decays its amplitude linearly over the duration and applies a random offset every frame. It uses `process_mode = ALWAYS` so the shake survives hit-stop but not the pause menu (it reads `PauseArbiter.is_paused()`).
- **Planned:** the `BOSS_DEATH` chain explosions (4× over 2 s) are sequenced by `Feedback.boss_death(pos)`, not by the Flagship.
- **Planned:** `PLAYER_HIT` adds the red edge vignette (a `ColorRect` shader in the HUD, triggered by `Events.player_hit`).

#### 4. Pause Arbiter

The model is described in [Pause and Time Model](#pause-and-time-model) above. Here's the full API:

```gdscript
# autoloads/pause_arbiter.gd (as built)
extends Node

signal resumed                         # once per paused -> unpaused transition, after mouse_mode is written

var _reasons: Dictionary = {}          # StringName -> true
var _gameplay_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _was_paused: bool = false

func push(reason: StringName) -> void:
	_reasons[reason] = true
	_apply()

func pop(reason: StringName) -> void:
	_reasons.erase(reason)
	_apply()

func is_paused() -> bool:
	return not _reasons.is_empty()

func clear() -> void:                  # SceneRouter (planned) calls this on every scene change; F5 calls it today. Keeps _gameplay_mode
	_reasons.clear()
	_apply()

func set_gameplay_mouse_mode(mode: Input.MouseMode) -> void:   # each scene root declares its mode
	_gameplay_mode = mode
	_apply()

func current_mouse_mode() -> Input.MouseMode:                  # VISIBLE while paused
	return Input.MOUSE_MODE_VISIBLE if is_paused() else _gameplay_mode

func _apply() -> void:
	var paused: bool = is_paused()
	get_tree().paused = paused
	Input.mouse_mode = current_mouse_mode()
	var resuming: bool = _was_paused and not paused
	_was_paused = paused
	if resuming:
		resumed.emit()
```

- Esc opens the pause menu **only** when the reasons don't already contain `&"final_choice"` or `&"death"`. During `&"story"` it is allowed.
- Menu scenes (title, level select, end, story) set gameplay mouse mode = `VISIBLE`. `level.tscn` sets it to `CONFINED_HIDDEN` (today the sandbox does, in `_ready`). Both go through `set_gameplay_mouse_mode`.
- `Player._on_resumed` answers `resumed` by warping the cursor to the ship (see [Pause and Time Model](#pause-and-time-model)).

### Communication Patterns

**Pattern:** "call down, signal up, broadcast across".

- **Parent → child:** direct method calls through `@onready` refs (`_health.take_damage(n)`).
- **Child → parent:** local signals (`resolved`, `died`).
- **Across systems** (HUD, audio, comms, director): the `Events` bus.
- **Damage:** the projectile calls `area.apply_damage(amount, source)` on the overlapped `Area2D` if it `has_method("apply_damage")`.

```gdscript
# core/projectile.gd
class_name Projectile
extends Area2D

var damage: int = 1
var velocity: Vector2 = Vector2.ZERO
var from_ally: bool = false

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	position += velocity * delta
	if not Rect2(-64, -64, 2048, 1208).has_point(global_position):
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if area.has_method("apply_damage"):
		area.apply_damage(damage, self)
	_on_impact(area)                   # missile overrides: splash
	queue_free()

func _on_impact(_area: Area2D) -> void:
	Feedback.impact(ImpactTier.SMALL, global_position)
```

### Entity Patterns

**Creation:** always `Spawner.spawn_*()`, which:

1. gets the scene from `EntityRegistry`,
2. instantiates it,
3. calls `setup(params: Dictionary)` (reads tuning and sets position and path), and
4. `add_child`s it to the right `World/<Container>`.

Entities must not depend on `_ready()` having run before `setup()`. `setup()` stores values, and `_ready()` applies them.

```gdscript
# autoloads/entity_registry.gd
extends Node
const ENEMIES: Dictionary[StringName, PackedScene] = {
	&"wasp": preload("res://entities/enemies/wasp/wasp.tscn"),
	&"lancer": preload("res://entities/enemies/lancer/lancer.tscn"),
	&"needle": preload("res://entities/enemies/needle/needle.tscn"),
	&"bastion": preload("res://entities/enemies/bastion/bastion.tscn"),
	&"maul": preload("res://entities/enemies/maul/maul.tscn"),
}
const PROJECTILES: Dictionary[StringName, PackedScene] = { ... }

# Usage (WaveDirector)
var wasp := _spawner.spawn_enemy(&"wasp", {"slot": Vector2(640, 160), "entry": &"top"})
if wasp:
	wasp.resolved.connect(_on_enemy_resolved)
	wasp.add_to_group(&"counted")
```

**The `Enemy` base class contract** (`core/enemy.gd`, `class_name Enemy extends Area2D`):

- `signal resolved`, which is emitted exactly once (on a kill or on a Maul miss).
- `var type_id: StringName`, `var tier: int` (ImpactTier).
- `func setup(params: Dictionary) -> void`.
- `func apply_damage(amount: int, source: Node) -> void` (it records `source.from_ally`).
- `func destroy_by_contact() -> void` (small and medium enemies only).
- HP comes from `Config.int_("enemies.<type_id>.hp")`. Drops come from `tuning.drops.<type_id>`.

### State Patterns

**Pattern:** an `enum State` plus a `match` in `_physics_process`, inside each entity script. Transitions happen **only** through `_enter_state(new_state)`, which handles one-time entry effects such as starting a telegraph glow.

There are no node-based FSMs and no behaviour trees.

```gdscript
# entities/enemies/needle/needle.gd
extends Enemy
enum State { ANCHORING, TRACKING, LOCKED, COOLDOWN }
var _state: State = State.ANCHORING
var _t: float = 0.0

func _physics_process(delta: float) -> void:
	_t += delta
	match _state:
		State.ANCHORING:
			if _move_to_anchor(delta): _enter_state(State.TRACKING)
		State.TRACKING:
			_aim_line_at(_target_pos())
			if _t >= _track_s: _enter_state(State.LOCKED)
		State.LOCKED:
			if _t >= _lock_s:
				_fire()
				_enter_state(State.COOLDOWN)
		State.COOLDOWN:
			if _t >= _cooldown_s: _enter_state(State.TRACKING)

func _enter_state(s: State) -> void:
	_state = s
	_t = 0.0
	%TelegraphLine.visible = s in [State.TRACKING, State.LOCKED]
	%TelegraphLine.default_color = Color.RED if s == State.LOCKED else Color(1, 0.3, 0.6, 0.5)
```

- **Telegraph rule:** any attack state is preceded by a `TELEGRAPH` / `LOCKED` / `CHARGING` state whose duration comes from tuning and is **≥ 0.3 s**. The GUT data test enforces this.
- **Flagship:** `enum Phase { ARRIVING, TURRETS, CORE, FINAL_CHOICE, DESPERATE, DYING }`. It emits `Events.boss_phase_changed` on each change. `FINAL_CHOICE` is entered when the core HP drops to ≤ `final_choice_hp` (50). Entering it requests `l3_final_choice` and waits for `comms_sequence_finished` of the response sequence before `DESPERATE`.

### Data Patterns

**Access:** only through the `Config` autoload's typed getters (see Configuration). The built getters are `num`, `int_`, `flag` and `section`. **Planned (Epics 2 and 5):** level and dialogue data will come through `Config.level(id) -> Dictionary` and `Config.sequence(id) -> Dictionary`, both validated at load.

```gdscript
# autoloads/config.gd (excerpt)
func num(path: String) -> float:
	var v: Variant = _lookup(tuning, path)
	if not (v is float or v is int):
		_report_missing("tuning." + path, "a number")   # Log.error + assert (when assert_on_missing)
		return 0.0
	return float(v)

func int_(path: String) -> int:
	return int(num(path))
```

**`tuning.json` top-level sections (fixed):** `player`, `weapons`, `abilities`, `energy`, `drops`, `enemies`, `boss`, `asteroids`, `convoy`, `allies`, `waves`, `comms`, `feedback`, `damage`, `render`.

- `render.glow` holds `intensity`, `bloom` and `hdr_threshold`. The scene root's `_ready` passes its `WorldEnvironment`'s environment to `RenderGlow.apply(env)` (`core/render_glow.gd`), so the F5 scene restart re-applies it. `glow_enabled` and the background mode stay in the `.tscn`.
- `weapons.laser.glow_energy` / `halo_energy` set the HDR `self_modulate` on the additive bolt core and halo sprites (the ADR-003 fallback: the bolt still reads as a glowing bullet with WorldEnvironment glow off).

### Input Actions

These are defined in `project.godot`. Code uses action names only, never raw keys or buttons.

| Action | Binding |
|---|---|
| `fire_laser` | Mouse Left (held) |
| `fire_missile` | Mouse Right |
| `ability_shield` | E |
| `ability_barrage` | Q |
| `comms_advance` | Mouse Left |
| `pause` | Escape |
| `toggle_fullscreen` | F11 |
| `debug_overlay` … `debug_unlock_all` | F1 … F7 |

The comms panel consumes `comms_advance` with `get_viewport().set_input_as_handled()` in `_unhandled_input`, so a click that advances a story line never also fires the laser. The laser checks `Input.is_action_pressed("fire_laser")` only while the tree is unpaused.

### Consistency Rules

| Pattern | Convention | Enforcement |
|---|---|---|
| Static typing | Every var, param and return is typed. Warnings `untyped_declaration` = Warn | Project setting + code review |
| Indentation | Tabs (Godot default) | Editor default |
| Tuning values | Never hard-code a GDD number. Read it from `Config` in `setup` / `_ready` | Review; `grep` for magic numbers |
| JSON numbers | Wrap counts and HP in `int()` / `Config.int_()` | Review |
| Movement | `_physics_process` for anything with a collision shape. `_process` for visuals only | Review |
| Positions | Gameplay world positions are playfield coordinates (1920×1080 logical, `Playfield.SIZE`). The cursor lock and every `warp_mouse` use **viewport** coordinates on purpose (`get_viewport().get_mouse_position()`), so the ShakeCamera offset can't feed back into the ship; with the camera centred and unzoomed they equal playfield coordinates (Story 1.8) | Review |
| Scene changes / pause / time scale / save | Only through `SceneRouter` / `PauseArbiter` / `Feedback` / `SaveManager` (debug F5 reload excepted) | `grep` for `change_scene`, `reload_current_scene`, `.paused =`, `time_scale`, `user://` |
| Spawning | Only through `Spawner` | `grep` for `.instantiate()` outside `core/spawner.gd`, `ui/`, `scenes/` |
| Dialogue | Only through `Events.comms_sequence_requested` | Review |
| New global signal | Add it to `events.gd` with typed params first | Review |
| Free nodes | `queue_free()` only, never `free()` | `grep` |
| Timers | `get_tree().create_timer(t, false)` for gameplay (pausable). Use the `true` process-always variant only in UI and autoloads | Review |
| Groups | `enemies`, `counted`, `asteroids`, `allies`, `pickups`, `projectiles` | Review |
| Assets | Every third-party asset is listed in `assets/CREDITS.md` | Release checklist |

---

## Performance Considerations

| Concern | Strategy |
|---|---|
| Budget | 16.6 ms per frame at the peak (40 enemies, 200 projectiles, particles) on the dev laptop's iGPU |
| Instancing | No pooling (ADR-002). Every entity scene `preload`ed in `EntityRegistry` |
| Off-screen projectiles | Freed by a bounds check in `Projectile._physics_process` (no `VisibleOnScreenNotifier2D` needed) |
| Collision | Circles and capsules only. Strict layers and masks (above). `monitorable = false` on projectiles that no one needs to detect (`player_shots`) |
| Particles | `GPUParticles2D` with `one_shot`, ≤ 32 particles per small explosion. Pre-warmed by `Feedback.prewarm()` at scene start |
| Shader compile hitch | Pre-warm (above). Renderer fallback per ADR-003 |
| Logging | None per frame |
| Barrage homing | Nearest enemy picked **once** on spawn and re-picked only when the target is freed (`is_instance_valid`). No per-frame group scans |
| Ally targeting | Re-acquire the nearest enemy every 0.5 s (on fire), not every frame |
| Verification | E1 sandbox stress test: `-- --stress` (40 Wasps refilled on death, F1 overlay on, vsync off) for a manual look, and `-- --bench=N` for a self-timing run (fire held at `BENCH_AIM`, 2 s warm-up, N s sampled, logs avg/p99/max, exit 0 if avg < 16.6 ms else 2). Re-run `--bench=20` after any visual change. Last results: GDD decision log #27 and #32 |

## Security Architecture

The game is a single-player offline game with no network, no accounts and no personal data. The only thing written to disk is `save.cfg` plus the logs in `%APPDATA%\DEFECTOR\`.

- Save tampering is harmless and accepted.
- The public repo must not contain secrets, machine paths or personal machine information (export presets use relative paths only).

## Deployment Architecture

1. Install the **export templates for 4.7.2** (Editor → Manage Export Templates → Download).
2. Use the **Windows Desktop** preset with `binary_format/embed_pck = true`, 64-bit, application icon and product name "DEFECTOR". Code signing: none.
   - **Resources filter:** export all resources, and **add the non-resource filter `data/*.json`**. Without it, the JSON files are missing from the build.
   - **Exclude filter:** `addons/gut/*, tests/*`.
3. Export to `game/export/windows/DEFECTOR.exe`. This folder is gitignored.
4. Zip it as `DEFECTOR-v1.0-windows.zip` along with `README.txt` (controls) and the credits.
5. Publish with `gh release create v1.0 DEFECTOR-v1.0-windows.zip --title "DEFECTOR v1.0" --notes-file RELEASE_NOTES.md`.
6. **Smoke test** the zipped build on a clean folder: launch time under 5 s, the save is created in `%APPDATA%\DEFECTOR\`, and it plays through Level 1.

CLI export (optional, for repeatability). Run the import step first; on a fresh clone with no `game/.godot/` the export fails without it:

```bash
# 1. Import (builds the class_name cache and imports the WAVs Audio preloads)
"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import

# 2. Export
"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --export-release "Windows Desktop" export/windows/DEFECTOR.exe
```

---

## Architecture Validation

### Validation Summary

| Check | Result | Notes |
|---|---|---|
| Decision Compatibility | PASS | All decisions are built-in Godot 4.7.2 features. JSON + `Config` is consistent with the "data-driven" GDD requirement. Pause, hit-stop and comms process modes were cross-checked |
| GDD Coverage | PASS | Every core system and technical requirement is mapped (table below) |
| Pattern Completeness | PASS | Creation, communication, state, error, data and events are all defined with code |
| Epic Mapping | PASS | E1–E8 are all mapped (table below) |
| Document Completeness | PASS | No placeholders. Versions verified 2026-10-06. Open items are listed explicitly as user-review items, not gaps |

### GDD Coverage

| GDD Requirement | How Addressed |
|---|---|
| Cursor-locked movement, cursor confined to bottom 60%, hidden cursor, resume-warp | `player.gd` (`step_lock` on the viewport mouse, `confine`, `warp_mouse`) + `PauseArbiter` mouse modes and `resumed` |
| Laser / missile / splash / cooldown ring | `entities/projectiles/`, `Projectile` base, `PlayerWeapons`, `MissileRing` on the ship (`draw_arc`), `missile_cooldown_changed` |
| Asteroids block both sides | Masks: `player_shots` and `enemy_shots` both detect `asteroids` |
| Friendly fire off; convoy solid (blocks every shot, damaged by enemy shots only) | Masks + `targets_convoy` flag (aimed 5 / stray 2) + Maul convoy mask + no-damage block for player shots |
| Hearts, i-frames, shield, contact damage tiers | `player.gd` + `tuning.damage` |
| Energy carry-over, wipe on death, save on clear | `GameState` + `SaveManager` rules |
| Drop table, orb magnet and despawn | `tuning.drops`, `energy_orb.gd` |
| Telegraph ≥ 0.3 s | State pattern rule + GUT data test |
| Off-screen rule (Wasps re-enter, Maul miss resolves) | Wave Director "resolved" definition |
| Scripted data waves, 2.0 s gap, % triggers | Wave Director + Beat Triggers |
| Story vs combat lines, cut-off, silence, music drop | Comms Channel |
| Surrender beats behind flags | `flags.json` + trigger `flag` |
| Flagship 3 phases, boss bar, Final Choice | Flagship `Phase` enum + `boss_*` events + `FinalChoice` |
| Size-scaled feedback table | Impact Feedback tiers from `tuning.feedback` |
| Title, level select, pause, retry, unlocks | `scenes/title`, `ui/menus`, `SceneRouter`, `SaveManager` |
| Borderless fullscreen + windowed + letterbox | Window mode fullscreen + F11 + stretch `canvas_items`/`keep` |
| 60 FPS / <5 s launch / <200 MB | Performance section + ADR-002/003 + E8 checks |
| Save to the per-user app data folder | `use_custom_user_dir` → `%APPDATA%\DEFECTOR\` |

### Epic Mapping

| Epic | Primary Locations | Patterns |
|---|---|---|
| E1 Core Feel | `entities/player/`, `entities/projectiles/`, `entities/asteroids/`, `entities/enemies/wasp/`, `autoloads/feedback.gd`, `systems/camera/`, `autoloads/config.gd`, `data/tuning.json` | Projectile damage rule, Impact Feedback, Config access, Spawner |
| E2 Enemies + Waves | `entities/enemies/*`, `systems/waves/`, `ui/hud/wave_bar.gd`, `data/levels/` | Enemy contract, State pattern, Wave Director |
| E3 Survival + Energy | `entities/player/`, `entities/pickups/`, `ui/hud/`, `ui/menus/retry_prompt.*` | Pause Arbiter (`death`), retry by reload |
| E4 Flow + Save | `scenes/boot`, `scenes/title`, `ui/menus/pause_menu.*`, `autoloads/scene_router.gd`, `save_manager.gd`, `game_state.gd` | Router, Pause Arbiter, Save rules |
| E5 Comms + Story | `systems/comms/`, `scenes/story/`, `data/dialogue/`, `data/flags.json` | Comms Channel, Beat Triggers |
| E6 Allies + Escort | `entities/allies/`, `ui/hud/convoy_bar.gd` | Collision masks, `story_event` (`tarek_fall`) |
| E7 Levels + Boss | `data/levels/level_*.json`, `entities/boss/`, `ui/hud/boss_bar.gd`, `systems/comms/final_choice.*`, `scenes/end/` | Boss wave, Phase enum, Final Choice |
| E8 Polish + Release | `autoloads/audio.gd`, `assets/`, `export_presets.cfg`, README | Audio registry, Deployment |

### Coverage Report

- **Systems covered:** 13 of 13
- **Patterns defined:** 4 novel + 5 standard (communication, entity, state, data, input) + 13 consistency rules
- **Decisions made:** 23 (D1–D23) + 6 ADRs

### Issues Resolved During Validation

1. **The click that advances a story line could also fire the laser.** Resolved by consuming input in the comms panel + an unpaused-only fire check.
2. **Reinforcements could let a wave "clear" early,** before the group spawned. Resolved by counting `groups` in `total_counted` up front.
3. **JSON numbers are floats** (verified on 4.7.2). Resolved with the `Config.int_()` rule.
4. **The Esc menu while a story line is paused** would previously have unpaused the story. Resolved with the Pause Arbiter reason set.
5. **JSON files would be missing from the export.** Resolved with the export non-resource filter `data/*.json`.
6. **Tunnelling** of 1600–1800 px/s projectiles. Resolved with the capsule-length rule.

### Validation Date

2026-10-06

---

## Development Environment

### Prerequisites

- **Godot 4.7.2-stable**, standard (non-.NET) build. Already installed locally; its folder is referred to as `<GODOT_DIR>` (the real path lives in the gitignored `LOCAL.md` at the repo root). Use `Godot_v4.7.2-stable_win64_console.exe` for CLI and headless runs.
- **Godot 4.7.2 export templates** (installed from the editor before E8).
- **GUT 9.7.1**, from the `godot_4_7` branch of `bitwes/Gut`, copied into `game/addons/gut/`. Enable it in Project Settings → Plugins.
- **Git** + **GitHub CLI** (`gh`) for the release.
- Free assets: Kenney Space Shooter Redux / Sci-fi Sounds (CC0). Record them in `assets/CREDITS.md`.

### AI Tooling (MCP Servers)

**Decision: no engine MCP server.** GoPeak was considered and **rejected by the user**. Its recommended setup, `npx -y`, downloads the latest npm version unpinned on every launch, which is a supply-chain risk. It also opens local command ports (6505/6005/6006/7777), and this is a corporate laptop.

AI agents use the **headless CLI loop** instead, which covers editing, error checking, tests, running and logs:

```bash
# One-time, on a fresh clone: import the project (builds the class_name cache and imports the WAVs Audio preloads)
"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import

# Run all GUT tests headless
"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit

# Run the game from CLI
"<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game

# Read the runtime log after a run
cat "$APPDATA/DEFECTOR/logs/godot.log"
```

- **Visual inspection, only if needed:** add the F8 debug screenshot key (see Debug Tools). It writes PNGs to `%APPDATA%\DEFECTOR\screenshots\` for an agent to open.
- **Context7 (optional, docs only):** it has no project access. If adopted, pin a version rather than using an unpinned `npx -y`.

### Setup Commands

```bash
# 1. Create project (or use the editor's Project Manager → Create in <repo>/game, Forward+)
"<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game --editor

# 2. Add GUT (dev-only)
git clone --depth 1 --branch godot_4_7 https://github.com/bitwes/Gut.git /tmp/gut
cp -r /tmp/gut/addons/gut game/addons/gut
```

### First Steps

1. Create the `game/` Godot project and apply these project settings:
   - Window 1920×1080, fullscreen mode, stretch `canvas_items` / `keep`.
   - `hdr_2d`.
   - Custom user dir `DEFECTOR`.
   - File logging on.
   - The collision layer names.
   - The input actions.
   - Autoloads in this order: `Log`, `Events`, `Config`, `GameState`, `SaveManager`, `PauseArbiter`, `Audio`, `Feedback`, `EntityRegistry`, `SceneRouter`.
2. Create `data/tuning.json` with every GDD value (this is E1 story 6) and `flags.json`.
3. Build the E1 sandbox. Run the perf stress test and confirm the renderer choice (ADR-003).
4. Confirm the headless test and run commands in the AI Tooling section work (no MCP setup needed).
5. Run `gds-create-epics-and-stories` with the GDD + this architecture.

---

## Decision Review Log

The user authorised this workflow to run without check-ins ("it's fine if you make some decisions without me"). Everything below was decided by the facilitator. **Status: ACCEPTED by the user on 2026-10-06.** Items marked ⚑ were the ones flagged for a second look.

| # | Decision | Alternative considered | Why chosen |
|---|---|---|---|
| ⚑ R1 | Godot project in a `game/` subfolder | `project.godot` at the repo root + `.gdignore` in the BMAD folders | Cleaner separation. Paths in this doc assume `game/` |
| ⚑ R2 | JSON for all content data (ADR-001) | Custom `Resource` classes (`.tres`) | AI- and hand-authorable, diffable, hot-reloadable |
| ⚑ R3 | Forward+ renderer (ADR-003) | Compatibility (lighter and faster start on iGPU) | Better glow. Fallback planned and cheap |
| R4 | No starter template | Maaack's Game Template | Less to learn in a 20 h budget |
| R5 | No object pooling (ADR-002) | Pool projectiles from day 1 | Simpler. Can be added later inside the Spawner |
| R6 | Custom comms instead of Dialogic 2 (ADR-005) | Dialogic 2 | Narrow needs. No plugin learning curve |
| R7 | Retry = scene reload (ADR-004) | Per-entity reset methods | Fewer bugs |
| R8 | `enum` + `match` state machines | Node-based StateMachine / LimboAI | Lighter for a newcomer |
| ⚑ R9 | Comms priority rules (story preempts combat; combat queue max 3) | Strict FIFO | Isolde "interrupts" by design |
| R10 | Reinforcement groups counted in the wave total up front | Count only spawned enemies | Monotonic bar, no early clear |
| R11 | `ConfigFile` save at `%APPDATA%\DEFECTOR\` | JSON save, default Godot app_userdata path | Built-in. Friendly path |
| R12 | GUT for logic and data tests only | GdUnit4; or no tests | GUT is the established choice and has a 4.7 branch |
| ⚑ R13 | **No engine MCP (GoPeak rejected by the user).** CLI loop instead, plus an optional F8 debug screenshot key if needed | Install GoPeak | Supply-chain risk + corporate laptop. The CLI covers edit, test, run and logs |
| R14 | Debug keys F1–F7, F11 fullscreen toggle | None | Fast testing of story beats (soft-lock metric) |
| R15 | Opening story plays only when starting Level 1 fresh (not on Level 1 retry) | Every Level 1 start | Retries must be instant (Pillar 1) |

---

## As-built reconciliation 2026-10-07

Story 1.10 brought this document in line with the Epic 1 code (after Stories 1.1-1.9). This story made no new design decision. The one rule that reverses (Positions, under Consistency Rules) follows the decision already made in Story 1.8 (spec-1-8 Design Notes, implementing GDD #29). Planned systems stay in the document and are marked as planned where an edit touched them. Sections changed:

- **Technical Risks:** the Performance row says particles are pre-warmed by `Feedback.prewarm()` at scene start. Source: Story 1.6.
- **Technical Requirements:** the cursor line says the Player warps the cursor back and points to the as-built lock. Source: Story 1.8, GDD #29.
- **Engine-Provided Architecture:** the Rendering row names the `render.glow` keys and `RenderGlow.apply(env)`; the Particles row says pre-warm is `Feedback.prewarm()`; the Scene management row marks `SceneRouter` planned and names the debug F5 reload. Source: Stories 1.6, 1.7, 1.9, GDD #31.
- **Asset Management:** pre-warm is `Feedback.prewarm()` at `PREWARM_POSITION` (-1000, 540), called at the end of the scene root's `_ready` (today `sandbox.gd`). Source: Story 1.6.
- **Pause and Time Model:** the Process modes table marks `SceneRouter` planned, places `World` in today's sandbox scene, and adds `ShakeCamera` and `DebugTools` (`PROCESS_MODE_ALWAYS`); the Cursor paragraph uses `set_gameplay_mouse_mode` / `current_mouse_mode` and says `clear()` keeps the declared mode; it names the debug-only `DebugTools` bench warp to `BENCH_AIM` as the one exception to Player-owned warps; a new "Cursor lock (as built)" block describes `step_lock` on the viewport mouse, `confine`, `WARP_EPS_PX`, the injectable `warp_mouse` and the `resumed` warp. Source: Story 1.8, GDD #29/#31.
- **Collision Layers:** a new sentence names `CollisionLayers` (`core/collision_layers.gd`) as the code-side source of the bits and shot masks. Source: Story 1.10 review.
- **Scene Structure:** `level.tscn` is marked planned; the sandbox is today's main scene. Source: Story 1.10.
- **Audio Architecture:** the real `play_sfx(id, pitch_jitter = DEFAULT_PITCH_JITTER, volume_db = 0.0, pitch = 1.0) -> AudioStreamPlayer` signature, the pitch formula, unknown-id warn-once, the 12-player oldest-steal pool; music marked planned; tier rows carry `sfx_volume_db`. Source: Story 1.6, GDD #26.
- **UI Framework:** the cooldown ring is `MissileRing` (`missile_ring.gd`, `z_index = 1`), with `player.missile_ring.radius_px` / `stroke_px`, the radius clamp and its colours. Source: Story 1.8, GDD #31.
- **Configuration:** the constants example is `Playfield.SIZE` / `RECT`; the Balancing example says "player zone"; the code example is `player_weapons.gd`; the getters are listed exactly; the missing-key `assert` depends on `Config.assert_on_missing`; F5 wording fixed; a new "Reload" block describes the validating `Config.reload() -> bool` (including that an empty current data set accepts any shape) and the F5 sequence. Source: Stories 1.7, 1.8, DW-8, DW-13.
- **Debug Tools:** only F1 and F5 are built (the other keys are marked planned); new "Command-line modes" block for `DebugArgs`, `-- --stress` and `-- --bench=N`. Source: Story 1.7.
- **Directory Structure:** says which parts exist (including `project.godot`, `export_presets.cfg`, `default_bus_layout.tres`, `assets/audio/sfx/`, `assets/CREDITS.md` and `addons/gut/`), and adds `default_bus_layout.tres` to the tree; the `spawner.gd` comment says it lives in `sandbox.tscn` today (`level.tscn` planned); `core/` lists `playfield.gd`, `render_glow.gd`, `collision_layers.gd`; the player folder has `missile_ring.gd`; `effects/` has the single explosion scene plus `shockwave_ring.gd`; adds `scenes/sandbox/` and `debug_args.gd`, `frame_stats.gd`. Source: Stories 1.6-1.9, DW-13.
- **System Location Mapping:** the Spawning row says the Spawner lives in `sandbox.tscn` today (`level.tscn` planned); the player row splits `Player`, `PlayerWeapons` (with its API) and `MissileRing`. Source: DW-13, Story 1.8.
- **Naming Conventions:** the variable example is now `fire_interval`. Source: Story 1.10.
- **Architectural Boundaries:** rule 1 says ShakeCamera registers in `_enter_tree` and Spawner in `_ready`; rule 4 names the debug-only F5 `reload_current_scene` exception. Source: Epic 1 retro C1, Story 1.7.
- **Impact Feedback Tiers:** the tier JSON includes `sfx_volume_db`; new blocks for `Feedback` as built (`load_tiers`, the `impact` call order, `prewarm` and its Spawner-first ordering dependency, `reset`), the single `Explosion` scene, the registration rules (accepted design) and the known sfx/extras gaps; boss-death chain and player-hit vignette marked planned. Source: Story 1.6, GDD #26, retro C1/A8.
- **Pause Arbiter:** the API excerpt adds `signal resumed`, `set_gameplay_mouse_mode` and `current_mouse_mode`, and notes that `clear()` keeps `_gameplay_mode`. Source: Story 1.8.
- **Data Patterns:** `Config.level()` / `Config.sequence()` marked planned; the `num` excerpt matches the code; the `tuning.json` sections add `render`, with the `render.glow` and laser `glow_energy` / `halo_energy` notes. Source: Story 1.9, GDD #31/#32.
- **Consistency Rules:** the Positions rule now says the cursor lock and warps use viewport coordinates on purpose. This follows the decision made in Story 1.8 (spec-1-8 Design Notes, implementing GDD #29). The scene-changes row excepts the debug F5 reload and adds `reload_current_scene` to its grep. Source: Story 1.7.
- **Performance Considerations:** the Particles row names `Feedback.prewarm()`; the Verification row describes `--stress` and `--bench=N`. Source: Story 1.7, GDD #27/#32.
- **Deployment Architecture:** the CLI export runs `--import` before `--export-release`. Source: DW-17.
- **GDD Coverage:** the movement row names `step_lock` on the viewport mouse and `resumed`; the weapons row names `PlayerWeapons` and `MissileRing`. Source: Story 1.8.

Superseded terms removed: the chase movement and its speed cap (`max_speed`), the reticle, and the cursor-aimed missile ("toward the cursor") no longer appear as current design. GDD decisions #29 and #31 replaced them with the exact cursor lock, the straight-up missile and the ring on the ship. The getter `get_global_mouse_position()`, the `cooldown_ring.gd` file, the `spark_burst.tscn` scene, the `ShakeCamera._ready()` registration and the `const PLAYFIELD` example were also replaced by their as-built equivalents.

---

_Generated by the GDS Game Architecture Workflow v1.0 (autonomous run)_
_Date: 2026-10-06_
_For: iman2001-ie_
