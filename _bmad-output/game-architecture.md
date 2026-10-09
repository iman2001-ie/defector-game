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
| Scene management | `SceneTree.change_scene_to_file` behind the `SceneRouter` autoload | Built (Story 3.2, Story 4.1, Story 4.2, Story 4.3): `restart_level()`, `goto_title()` (the title scene, restoring energy and unlocks from the save), `goto_level_select()`, `start_level(id)` and `complete_level(n)`, through an injectable `change_scene` callable. The debug F5 reload (`DebugTools`, see Reload) and the `--stress` redirect (in `boot.gd` and `level.gd`) are the debug-only exceptions |
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
| D9 | Save system | `ConfigFile` at `user://save.cfg`. Custom user dir → `%APPDATA%\DEFECTOR\`. Built (Story 4.2): the `SaveManager` autoload | built-in | E4 | Tiny save (unlocks + energy). Built-in format with no parsing code |
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
| `energy` (0–100), `current_level_id`, `highest_unlocked_level`, `is_retry` | `GameState` autoload | Whole session. Unlocks and energy are persisted by `SaveManager`. Built (Story 3.2): `energy`, `current_level_id` (the level file key, e.g. `"dev"`) and `is_retry`; Story 3.3 adds the energy API (`max_energy()`, `add_energy(amount)`, `emit_energy()`); Story 4.2 adds `highest_unlocked_level` (1..`progression.level_count`), the debug-only `all_levels_unlocked` (F7, memory only, never saved) and `is_level_unlocked(n)` |
| Hearts, i-frames, shield, missile cooldown | `Player` node, held by its children: `Health` (`HealthComponent`: hearts, i-frames), `Shield` (`PlayerShield`) and `Weapons` (`PlayerWeapons`: missile cooldown) | One level attempt |
| Wave index, alive and resolved counts, triggers fired | `WaveDirector` node | One level attempt |
| Convoy HP | `Convoy` node | One level attempt |
| Boss phase and HP | `Flagship` node | One level attempt |
| Comms queue, silence flag | `CommsChannel` node (in level / story scene) | One scene |

**Energy rules** (GDD):

- On the first attempt of a level, `energy` keeps its carried value.
- On death, retry or restart: `GameState.energy = 0`, then reload the level.
- On level clear: `SaveManager.save()` writes the current energy and the new unlock.
- From the title screen, "Play" and "Level Select" load the saved energy.
- Built (Story 4.2): `SceneRouter.goto_title()` restores `energy` and `highest_unlocked_level` from the save (F13), so in-memory mid-level energy never leaks across menus. `SceneRouter.complete_level(n)` does the clear: unlock, save, then the next level with the carried energy.

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
- Built (Story 4.2): `autoloads/save_manager.gd` (autoload `SaveManager`, no `class_name`). `load_progress() -> Dictionary` (`highest_unlocked_level`, `energy`; never calls a `Config` getter), `save() -> bool`, `save_path` (default `DEFAULT_SAVE_PATH`; tests inject `user://test_*.cfg`). No file I/O in `_ready`. The only caller of `save()` is `SceneRouter.complete_level`; the only caller of `load_progress()` is `SceneRouter.goto_title`.

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
| Gameplay world (`World` node in the scene root: `level.tscn`, and the `sandbox.tscn` stress bench) | `PROCESS_MODE_PAUSABLE` (inherit) |
| `CommsPanel`, `FinalChoice`, retry prompt (`Overlay/RetryPrompt`, built), pause menu (`Overlay/PauseMenu`, built in Story 4.4) | `PROCESS_MODE_ALWAYS` |
| Autoloads `PauseArbiter`, `Audio`, `Feedback`, `SceneRouter` | `PROCESS_MODE_ALWAYS` |
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

**Built (Story 5.5):** the Story box is `scenes/story/story.tscn`. `SceneRouter.start_level("1")` (PLAY and Level Select both call it) goes to it with `opening_main` through `goto_story`; `finish_story()` then loads Level 1 directly, and `restart_level()` never passes through `start_level`, so a retry never replays the opening (R15). The "next Story" after a clear and the End screen are Epic 7.

`level.tscn` node tree (fixed: all three levels use this tree). **Built (Story 2.2):** `scenes/level/level.tscn`. Since Story 4.1 the main scene is `scenes/boot/boot.tscn` (→ `scenes/title/title.tscn`), and the title's PLAY runs `level_1.json` through `SceneRouter.start_level`; run directly, `level.tscn` still falls back to its exported `level_dev.json`. As built it also has a `Spawner` node (`world = ../World`) next to `WaveDirector`, and `HUD/LevelClearBanner`. The Epic 1 sandbox `scenes/sandbox/sandbox.tscn` stays as the stress-bench scene.

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
├── Spawner (Node, spawner.gd)            # as built: world = ../World
├── WaveDirector (Node, wave_director.gd)
├── ShakeCamera (Camera2D, shake_camera.gd)   # anchor centre 960,540
├── WorldEnvironment                      # glow
├── HUD (CanvasLayer layer=10)
├── Comms (CanvasLayer layer=20)          # CommsPanel + FinalChoice
└── Overlay (CanvasLayer layer=30)        # RetryPrompt, PauseMenu (built, Story 4.4), DebugOverlay
```

Spawned nodes are always parented to the matching `World/<Group>` container, which `Spawner` exposes.

### Collision Layers

Configure these in `project.godot` → `layer_names/2d_physics`. Use these names and numbers exactly.

As built, `core/collision_layers.gd` (`CollisionLayers`) holds the bit values (`PLAYER` = 1 … `ALLIES` = 128) and the shot masks `MASK_PLAYER_SHOTS` / `MASK_ENEMY_SHOTS`. Code and tests use these constants; `.tscn` files store the numbers, and tests check them against the constants. Likewise `core/groups.gd` (`Groups`, DW-61) holds the scene-tree group names as `StringName` constants (`PLAYER`, `ENEMIES`, `ASTEROIDS`, `PROJECTILES`, `PICKUPS`, `COUNTED`, `WAVE_DIRECTOR`). Production code joins and queries groups only through them (no `&"..."` group literal, no per-file `*_GROUP` const); `.tscn` files store no groups, and tests may spell the literals as independent checks.

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
- **Music (built, Story 5.3):** one `Music` `AudioStreamPlayer` child on the `Music` bus and the `Audio.music_streams` registry (id → stream, empty until Story 8.1 adds tracks). `Audio.apply_music_action(action)` (the WaveDirector `music` action: `&"stop"` → `stop_music()`, anything else → `play_music(action)`), `play_music(id)` (plays or switches at once; the same id is a no-op; a missing stream warns once per id, stops the current track at once and stays silent), `stop_music(fade_s := -1.0)` (a negative fade uses `audio.music_fade_out_s`, 0.5 s), `current_music()`, `music_player()`. **Planned (Epic 8):** `Audio.duck_music(on: bool)`.
- SFX are in-world but on a fixed screen, so there's no positional audio (`AudioStreamPlayer`, not `2D`).
- Explosion tier → SFX: each `tuning.json → feedback.tiers` row carries `sfx`, `sfx_pitch` and `sfx_volume_db` (GDD decision #26). `Feedback.impact` calls `Audio.play_sfx(row.sfx, Audio.DEFAULT_PITCH_JITTER, row.sfx_volume_db, row.sfx_pitch)`.

### UI Framework

- Built-in `Control` nodes. One `Theme` at `res://ui/theme/defector_theme.tres` (fonts, panel styles, button styles). Don't set per-node style overrides except in the comms panel portrait frame.
- The HUD reads state **only via `Events` signals** (`hearts_changed`, `energy_changed`, `wave_progress_changed`, `boss_hp_changed`, `convoy_hp_changed`, `missile_cooldown_changed`; the hint pill also reads `hint_requested`, `player_moved` and `player_action`, Story 5.8). The HUD never polls gameplay nodes.
- There is no reticle: the ship is the cursor (GDD decision #29). The missile cooldown ring is a Player child, drawn above the ship sprite with `draw_arc` and driven only by `Events.missile_cooldown_changed`.
  - As built: `entities/player/missile_ring.gd` (`class_name MissileRing`), the `MissileRing` child of the Player with `z_index = 1`.
  - Data: `player.missile_ring.radius_px` / `stroke_px`. The radius is clamped to `player.sprite_px / 2` (with a `Log.warn`), so the ring is never bigger than the ship.
  - Colours: a `text` (#E8F4FF) stroke over a `background` (#05070F) outline. It sweeps clockwise from 12 o'clock and draws nothing when the ratio is 0 (ready).
- The hearts display and hit vignette are built (Story 3.1): `ui/hud/hearts_display.gd` (`class_name HeartsDisplay`, `HUD/HeartsDisplay`) draws the heart icons in code, right-aligned to `hud.hearts.right_x`, and pops a lost heart; `ui/hud/hit_vignette.gd` (`class_name HitVignette`, `HUD/HitVignette`, the first HUD child so it draws under the meters) is a full-rect `ColorRect` with the `hit_vignette.gdshader` edge gradient, driven by `Events.player_hit`. Both are `PROCESS_MODE_PAUSABLE` and `MOUSE_FILTER_IGNORE`; colours are the theme's `HeartsDisplay` (`heart`, `empty`, `outline`) and `HitVignette` (`color`) items; layout and timing are `hud.hearts` / `hud.hit_vignette`.
- The energy bar is built (Story 3.3): `ui/hud/energy_bar.gd` (`class_name EnergyBar`, `HUD/EnergyBar` right after `HeartsDisplay`, `PROCESS_MODE_PAUSABLE`, `MOUSE_FILTER_IGNORE`), driven only by `Events.energy_changed`. Rect from `hud.energy_bar` (`right_x − width`, `y`, `width × height`: 1568, 76, 320×16); theme type `EnergyBar` (`track` and `fill` styleboxes, `tick` colour); tick marks at `abilities.shield.cost` and `abilities.barrage.cost` of max, clamped inside the bar. Denied flash (Story 3.4): `Events.ability_denied` (any ability) starts or restarts a `hud.energy_bar.denied_flash_s` flash with `denied_flashes` on-phases (static `flash_lit(elapsed, duration, flashes)`), drawn as a full-rect theme `EnergyBar/colors/denied` (`danger`) overlay above the fill and ticks; `_process` runs only while flashing, so the flash freezes under pause.
- The control-hint pill is built (Story 5.8): `ui/hud/hint_pill.gd` (`class_name HintPill`, `HUD/HintPill` right after `EnergyBar`, `PROCESS_MODE_PAUSABLE`, `MOUSE_FILTER_IGNORE`), driven only by `Events.hint_requested`, `energy_changed`, `player_moved` and `player_action`; it also reads and writes `GameState.shown_hints`. Theme type `HintPill`; layout and timing `ui.hint_pill`. See As-built 2026-10-08 (Story 5.8).
- The wave bar is built: `ui/hud/wave_bar.gd` (`class_name WaveBar`), the `HUD/WaveBar` child of `level.tscn` (before `LevelClearBanner`, `PROCESS_MODE_PAUSABLE`). `defector_theme.tres` exists and holds the `WaveBar` type items (`track`, `fill`, `highlight` styleboxes, `separation` constant); rect and tween time are `tuning.json` → `hud.wave_bar`.

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

- Categories (fixed list): `boot`, `scene`, `wave`, `beat`, `comms`, `spawn`, `combat`, `save`, `audio`, `data`, `debug`, `hint` (Story 5.8).
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

- The getters are exactly: `Config.num("weapons.missile.speed_px_s")` → `float`, `Config.int_("enemies.wasp.hp")` → `int`, `Config.flag("surrender_prompts")` → `bool`, and `Config.section("feedback.tiers")` → `Dictionary` (a deep copy). Level data comes through `Config.level(id)`; dialogue through `Config.sequence(id)` (a deep copy, `{}` for an unknown id), `Config.has_sequence(id)` and `Config.dialogue_is_story(id)` (built, Story 5.1; see Data Patterns).
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
- It re-reads the dialogue dir too (Story 5.1): a dialogue file that fails to parse (or a missing dir) is a reload problem; `DialogueValidator` problems are only logged and the bad sequences left out.
- On any failure it logs `Log.error("data", "Reload rejected (...); previous data kept")`, returns `false`, and leaves `tuning`, `flags`, the dialogue and `load_error` untouched.
- On success it commits tuning, flags and dialogue, clears `load_error`, logs the load summary and returns `true`.
- F5 runs `DebugTools.reload_data()`: `Config.reload()`. If that returns `false`, it logs and stops (the scene isn't restarted). If `true`, it runs `Feedback.reset()`, `Feedback.load_tiers()` and `SceneRouter.restore_saved_progress()` (energy and `highest_unlocked_level` from the save, clamped with the new data, and `is_retry = false`, exactly as `goto_title()` does; DW-61), then restarts the current scene (`get_tree().reload_current_scene`) so every `_ready` cache re-reads the data and the scene root re-applies `render.glow`, and only then calls `PauseArbiter.clear()`. The restart removes the outgoing scene from the tree synchronously, so `resumed` never reaches its Player while it is still in the tree (`Player._on_resumed` also ignores the signal outside the tree). On a failed reload GameState and the pauses are untouched.

### Event System

**Pattern:** Godot signals. There are two scopes:

1. **Local signals** on a node, for parent ↔ child or a scene-local wiring (`HealthComponent.died` → `Player._die`, `enemy.resolved`).
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
signal player_moved(distance_px: float)              # Story 5.8: the ship moved this tick
signal player_action(action: StringName)            # Story 5.8: &"laser" | &"missile" | &"shield" | &"barrage"

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
signal hint_requested(hint_id: StringName)           # Story 5.8: &"move_fire" | &"missile"
```

### Debug Tools

Debug tools are available **only when `OS.is_debug_build()`** (editor runs and debug exports). In release builds they do nothing (`DebugTools.debug_enabled` is false: early return, processing off). A single `DebugTools` node in `Overlay` (`ui/debug/debug_tools.tscn` + `debug_tools.gd`) handles the keys.

**Implemented today: F1, F2, F3, F4, F5, F6, F7 and F11 (F11 is owned by `SceneRouter`, not `DebugTools`).** The other keys are planned for the epics that need them.

| Key | Tool | Status |
|---|---|---|
| F1 | Toggle debug overlay. Built: FPS, frame ms (avg / max over a 0.25 s window, real time), node count, enemies alive, wave `n/N` and resolved/total (`wave -` without a WaveDirector), pause reasons (`PauseArbiter.reasons()`), `invincible on|off` (`-` without a Player). Planned addition: current comms sequence | Built (comms line planned) |
| F2 | Toggle player invincibility (`Player.debug_invincible` on the `player` group node; damage is ignored, small and medium enemies still die on contact, no flicker) | Built |
| F3 | Resolve the current wave (kill every counted enemy and fire its pending triggers in order) | Built |
| F4 | Energy +`debug.energy_add` (100), capped: `DebugTools.add_energy()` → `GameState.add_energy(...)` and one `F4: energy n/max` INFO line | Built |
| F5 | Reload `tuning.json` and `flags.json` through `Config.reload()`, then restart the scene (see [Configuration](#configuration)) | Built |
| F6 | Jump to the boss wave in the current level (if any) | Built |
| F7 | Unlock all levels (in memory, not saved): `DebugTools.unlock_all()` sets `GameState.all_levels_unlocked` and logs `F7: all levels unlocked (in memory, not saved)`; it never calls `SaveManager`, survives `goto_title`, and doesn't change PLAY | Built |
| F8 | *(Add only if needed)* Save a screenshot of the viewport to `user://screenshots/shot_<timestamp>.png` so AI agents can inspect the running game. This replaces the screenshot feature of an engine MCP | Planned |
| F11 | Toggle borderless fullscreen / windowed (**available in release too**, not a debug tool): owned by `SceneRouter` (Story 4.5), works in every scene and while paused, not persisted | Built |

**Command-line modes (debug builds only, Story 1.7, DW-9/DW-21):** `DebugArgs.parse(OS.get_cmdline_user_args())` (`ui/debug/debug_args.gd`) returns `{stress: bool, bench_s: float, prewarm: bool, comms: StringName, level: String}`. The scene root and `DebugTools` both read it. The bench and stress numbers come from `tuning.json` → `debug.bench` / `debug.stress` (see [Data Patterns](#data-patterns)).

- `-- --stress`: the sandbox spawns a 10×4 grid of 40 Wasps and refills each slot when its Wasp dies. It also keeps `debug.stress.projectiles` (200) projectiles live, the NFR1 peak: each physics tick it spawns `min(target - live, debug.stress.projectile_spawn_per_tick)` laser bolts through `Spawner`, one grid row below the Wasps, flying down at `weapons.enemy_bullet.max_speed_px_s` (they stand in for enemy bullets; live count = the `projectiles` group, the player's bolts included). The overlay starts on, and vsync is turned off so frame ms measures work, not the display wait.
- `-- --comms=<id>` (Story 5.1): `DebugArgs.parse` returns it as `comms: StringName` (`&""` when absent). After `start_level`, `level.gd` requests that sequence through `Events.comms_sequence_requested` (deferred) so the panel can be checked before Story 5.3's triggers exist (static `debug_comms_id(debug_build, args)`).
- `-- --level=<id>` (Story 5.6): `DebugArgs.parse` returns it as `level: String` (`""` when absent; an empty value warns and is ignored). `level.gd` replaces its exported `level_id` with it **before** `resolve_level_id`, so a non-empty GameState id (a retry, or any SceneRouter entry) still wins (static `debug_level_id(debug_build, args)`). It takes effect only when `level.tscn` is the launched scene: the main scene is `boot.tscn`, and every route from boot or the title into `level.tscn` goes through `SceneRouter`, which sets `GameState.current_level_id`, so the arg on a normal launch never changes the level. For a human to play a level the title doesn't reach: `"<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game res://scenes/level/level.tscn -- --level=dev_isolde`.
- `-- --no-prewarm`: the sandbox logs that it skipped `Feedback.prewarm()` and does not call it, so the operator can compare the first-explosion cost with and without pre-warm. Release builds ignore it and still pre-warm.
- `-- --bench=N` implies `--stress`. It warps the cursor to `DebugTools.BENCH_AIM` (1040, 900) and holds `fire_laser`. During the `debug.bench.warmup_s` warm-up (2 s) it fires one deliberate `Feedback.impact(ImpactTier.LARGE, …)` at `first_large_at_s` and, after the next `first_large_frames` frames, logs `[INFO][debug] Stress bench: first LARGE impact max=… ms avg=… ms over … frames prewarm=on|off`. It then samples N s of frame times into `FrameStats` (`ui/debug/frame_stats.gd`), releases fire and logs one line:
  `[INFO][debug] Stress bench: frames=… avg=… ms p99=… ms max=… ms enemies=… projectiles=… renderer=… window=… vsync=… result=PASS|FAIL`.
  PASS (exit 0) needs avg, p99 and max all under `debug.bench.avg_ms_max` / `p99_ms_max` / `max_ms_max` (16.6 ms each); otherwise, or with no samples, FAIL (exit 2). The quit runs through the injectable `DebugTools.quit_game` callable (default `get_tree().quit`) after a real-time `debug.bench.quit_delay_s` timer, never in the frame that logs, so the final line reaches stdout and the log file. A malformed or non-positive N logs a warning and is ignored.

---

## Project Structure

### Organization Pattern

**Pattern:** a **hybrid by feature**. Each entity or feature keeps its `.tscn` and `.gd` together in one folder. Cross-cutting services live in `autoloads/`, and data lives in `data/`.

**Rationale:** for a newcomer and for AI agents, "the Wasp lives in `entities/enemies/wasp/`" is easier to follow than splitting scenes and scripts into parallel trees.

### Directory Structure

This is the target tree. As of Story 5.8 the built parts are: `project.godot`, `export_presets.cfg` and `default_bus_layout.tres`; the autoloads `Log`, `Events`, `Config`, `GameState`, `SaveManager`, `PauseArbiter`, `Audio`, `Feedback`, `EntityRegistry`, `SceneRouter`; `core/` (with `loot.gd` and `health_component.gd`); `entities/player/` (with the shield, `player_shield`, `shield_bubble` and the barrage); `entities/projectiles/` laser, missile and `micro_missile`; `entities/enemies/wasp/`; `entities/asteroids/`; `entities/pickups/`; `entities/effects/`; `systems/camera/`; `systems/waves/`; `systems/comms/` (`comms_channel.gd`, `comms_panel.tscn` + `.gd`, `comms_box.tscn` + `.gd`, `dialogue_validator.gd`); `scenes/sandbox/`; `scenes/level/`; `scenes/boot/`; `scenes/title/title.tscn` + `.gd` and `level_select.tscn` + `.gd`; `scenes/story/` (`story.tscn` + `.gd`); `ui/debug/`; `ui/hud/level_clear_banner.gd`, `wave_bar.gd`, `hearts_display.gd`, `energy_bar.gd`, `hint_pill.gd` (Story 5.8) and `hit_vignette.gd` (+ `.gdshader`); `ui/menus/retry_prompt.tscn` + `.gd` and `pause_menu.tscn` + `.gd`; `data/tuning.json`, `data/flags.json`, `data/levels/` (plus the dev levels `level_dev.json`, `level_dev_isolde.json` and `level_dev_hints.json`) and `data/dialogue/` (`dev.json`, `opening.json`, `level_1.json`, `level_2.json`, `level_3.json`); `assets/audio/sfx/`, `assets/sprites/player/` and `assets/CREDITS.md`; `addons/gut/`; `tests/unit/` (plus `tests/fixtures/`); and `tests/data/`. Everything else is planned.

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
    │   ├── spawner.gd                       # Spawner (class_name), a node in level.tscn and sandbox.tscn
    │   ├── health_component.gd              # HealthComponent: hearts + i-frames (the Player's Health child)
    │   ├── projectile.gd                    # Projectile base (class_name)
    │   ├── enemy.gd                         # Enemy base (class_name)
    │   ├── impact_tier.gd                   # ImpactTier enum holder + tier names
    │   ├── playfield.gd                     # Playfield: SIZE, RECT (1920×1080)
    │   ├── render_glow.gd                   # RenderGlow.apply(env): render.glow → Environment
    │   ├── collision_layers.gd              # CollisionLayers: layer bits + shot masks
    │   ├── groups.gd                        # Groups: scene-tree group names (StringName consts)
    │   └── loot.gd                          # Loot: drop rolls → Spawner.spawn_orb (deferred)
    ├── entities/
    │   ├── player/            player.tscn, player.gd, player_weapons.gd, player_shield.gd, missile_ring.gd, shield_bubble.tscn + .gd
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
    │   ├── waves/             wave_director.gd, beat_trigger.gd, wave_progress.gd, formation.gd, level_validator.gd
    │   ├── comms/             comms_channel.gd, comms_panel.tscn, comms_panel.gd,
    │   │                      final_choice.tscn, final_choice.gd
    │   └── camera/            shake_camera.gd
    ├── scenes/
    │   ├── boot/              boot.tscn, boot.gd                  # main scene: loads Config, Save → Title
    │   ├── title/             title.tscn, title.gd, level_select.tscn, level_select.gd
    │   ├── story/             story.tscn, story.gd                # comms-only paused scene
    │   ├── level/             level.tscn, level.gd
    │   ├── end/               end_screen.tscn, end_screen.gd
    │   └── sandbox/           sandbox.tscn, sandbox.gd            # Epic 1 debug sandbox (stress bench)
    ├── ui/
    │   ├── hud/               hud.tscn, hud.gd, hearts_display.gd, energy_bar.gd, level_clear_banner.gd,
    │   │                      wave_bar.gd, boss_bar.gd, convoy_bar.gd
    │   ├── menus/             pause_menu.tscn, pause_menu.gd (built, Story 4.4), retry_prompt.tscn, retry_prompt.gd
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
| Run state (energy, unlocks, current level) | `autoloads/game_state.gd` | Single source of truth for cross-scene state. Built (Story 3.2): `energy`, `current_level_id`, `is_retry`. Built (Story 3.3): `max_energy()`, `add_energy(amount)` (clamp + `energy_changed`), `emit_energy()`. Built (Story 4.2): `highest_unlocked_level`, `all_levels_unlocked` (F7), `is_level_unlocked(n)` |
| Save / load | `autoloads/save_manager.gd` | Only writer and reader of `user://save.cfg`. Built (Story 4.2): `load_progress()`, `save()`, injectable `save_path` |
| Pause | `autoloads/pause_arbiter.gd` | Pause reasons → `tree.paused` + mouse mode |
| Scene flow | `autoloads/scene_router.gd` | `goto_title()`, `goto_level_select()`, `start_level(id)`, `restart_level()`, `goto_story(id, next)`, `goto_end()`. Built (Story 3.2): `restart_level()`. Built (Story 4.1): `goto_title()` (the title scene) and `start_level(id)`. Built (Story 4.2): the save restore in `goto_title()` and `complete_level(n)`. Built (Story 4.3): `goto_level_select()`. Built (Story 5.5): `goto_story(id, next)` and `finish_story()` (`start_level("1")` plays the opening first); `goto_end()` is planned |
| Audio | `autoloads/audio.gd` | SFX pool, music, registry |
| Impact feedback | `autoloads/feedback.gd` + `systems/camera/shake_camera.gd` | Tier → explosion, shake, hit-stop, SFX |
| Entity scenes registry | `autoloads/entity_registry.gd` | `const` dicts of `preload`ed scenes |
| Spawning | `core/spawner.gd` (node in the scene root: today `sandbox.tscn`; `level.tscn` planned) | The only place that instantiates gameplay entities |
| Player ship, weapons, abilities | `entities/player/` | `player.gd` (`Player`): cursor lock, bounds, hurtbox and sizing (since Story 4.0 the `Sprite` is the recoloured Kenney hull from `assets/sprites/player/`, scaled uniformly so its longer side is `player.sprite_px`, with the `Muzzle` on its nose); delegates firing to its `Weapons` child. `player_weapons.gd` (`class_name PlayerWeapons extends Node`, the `Weapons` child): laser and missile timing, spawning, sfx and `missile_cooldown_changed`; API `set_spawner(spawner)`, `step_fire(held, delta)`, `step_missile(pressed, delta)`, which `Player` keeps as one-line delegators. `missile_ring.gd` (`MissileRing`): cooldown ring. Built (Story 3.1): hearts, i-frames with the sprite flicker, contact damage and `debug_invincible` (Player API `apply_damage(amount, source)`, `step_iframes(delta)`, `on_contact(area)`, `is_invulnerable()`, `hearts`, `max_hearts`). Since DW-55 the hearts and i-frames live in the `Health` child (`core/health_component.gd`, `class_name HealthComponent extends Node`: signals `damaged(current, max_value)`, `died`, `iframes_ended`; `setup(max_value, iframes_s, flicker_hz, flicker_target)`, `current`, `max_value`, `can_take(amount)`, `take(amount)`, `step(delta)`, `is_iframing()`, `stop_iframes()`; no `Events`, `GameState` or `Audio`), and `Player` keeps the API as delegators (`hearts` / `max_hearts` are forwarding properties). Built (Story 3.2): death at 0 hearts (`is_dead()`; PLAYER_DEATH feedback, `player_died` + `level_failed(&"hearts")`, the ship hidden and inert). Built (Story 3.4): the shield (Player API `try_shield()`, `step_shield(delta)`, `is_shielded()`, `shield_remaining()`; `is_invulnerable()` = i-frames OR shield OR `debug_invincible`; denial through `_deny(ability)` = `Events.ability_denied` + the `ability_denied` SFX). Since DW-55 its state lives in the `Shield` child (`player_shield.gd`, `class_name PlayerShield extends Node`, `@export var bubble: NodePath`: `cost`, `duration_s`, `is_active()`, `remaining()`, `raise()`, `step(delta)`, `drop()`, signal `ended`; no global events), and `try_shield` / `try_barrage` share one private spend gate `Player._spend(ability, busy, cost, log_line)`. Also built in Story 3.4: `shield_bubble.tscn` + `.gd` (`ShieldBubble`, the hidden-by-default `ShieldBubble` child, `z_index = 1`; `show_remaining(s)`, `hide_bubble()`, static `is_lit(remaining, last_s, hz)`; data `player.shield_bubble`). Built (Story 3.5): the barrage. `Player.try_barrage()` (the `ability_barrage` action, Q) spends `abilities.barrage.cost` or denies through `_deny(&"barrage")`, never restarts a running volley, and `_die()` calls `stop_barrage()`; `Player` keeps `step_barrage(delta)` and `is_barraging()` as delegators. `PlayerWeapons` runs the volley: `start_barrage()`, `step_barrage(delta)`, `stop_barrage()`, `is_barraging()`, `barrage_left()`; `abilities.barrage.missiles` launches of `&"micro_missile"`, one every `duration_s / missiles` from physics delta, each with the `barrage_whoosh` SFX and the muzzle flash, and one `Feedback.impact(LARGE)` at the muzzle on the last launch. `entities/projectiles/micro_missile.tscn` + `.gd` (`MicroMissile extends Projectile`; static `nearest_enemy(from, nodes)` and `steer(v, desired, max_turn_rad)`, `target()`; data `abilities.barrage.speed_px_s`, `turn_rate_deg_s`, `lifetime_s`) |
| Enemies | `entities/enemies/<type>/` | Behaviour per type, extends `Enemy` |
| Flagship | `entities/boss/` | Phases, turrets, core, final-choice hook |
| Asteroids | `entities/asteroids/` | Drift, rotate, block, damage, drop |
| Energy orbs | `entities/pickups/` | Drift, magnet, despawn, collect. Built (Story 3.3): `energy_orb.tscn` + `.gd` (`EnergyOrb`); drops rolled by `core/loot.gd` (`Loot`) |
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
- Dialogue sequence ids: `<scene>_<beat>`. For example: `opening_main`, `l1_w3_isolde_interrupt`, `l1_w5_surrender`, `l2_w5_tarek_cutoff`, `l2_ryn_report`, `l3_final_choice`, `l3_isolde_refuse_surrender`, `l3_isolde_refuse_destroy`, `l3_isolde_final`.
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
| Actions (handled inside `WaveDirector._run_actions`) | `comms`, `spawn_group`, `story_event`, `music`, `wait`, `hint` (Story 5.8) |

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
        { "when": "wave_start", "actions": [ { "hint": "move_fire" } ] }
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
- Actions run **sequentially**: `comms` with a story-mode sequence `await`s `Events.comms_sequence_finished`, and combat-mode sequences don't block. A trigger whose actions are still running doesn't block other triggers. Built (Story 5.3): `comms`, `story_event` and `music` run as described below; the chain waits on a relay signal of the director itself (fed by an `Events.comms_sequence_finished` connection made in `_ready`), and a finished emitted synchronously during the request still releases it; unknown ids don't wait (the channel finishes them). `wait` uses a one-shot pausable `Timer` child. So every chain dies with the director on a reload. A `music` value must be `stop`, `combat` or `boss` (LevelValidator).
- **`hint` (built, Story 5.8):** `{ "hint": "move_fire" | "missile" }` logs `[INFO][beat] Level <n> wave <w>: hint '<id>'`, emits `Events.hint_requested(id)` and never waits, so the next action runs in the same chain step. The HUD `HintPill` shows the hints; nothing goes through the comms channel and nothing pauses. Any other value is a LevelValidator problem (`HINT_ACTIONS`). The energy hints (`[E] SHIELD`, `[Q] BARRAGE`) are not data: the pill raises them from `Events.energy_changed`. Control tutorials are hints, never `comms` sequences (GDD).
- **Intro and outro (built, Story 5.3):** `intro_sequence` plays before wave 1 the same way as a `comms` action (a story intro holds wave 1, a combat one doesn't) and is skipped when `GameState.is_retry` (INFO `intro '<id>' skipped (retry)`); `outro_sequence` plays before `level_cleared` the same way, also on a retry. A death, F6 or a new `start_level` during either await starts or clears nothing. Both are absent, `null` or a non-empty string (LevelValidator). The level-root `music` key is not read (see As-built Story 5.3).
- **Wave clear** = `resolved == total_counted` **and** all of the wave's action chains have finished. Then `wave_clear` triggers fire, then a 2.0 s gap (`tuning.waves.gap_s`), then the next wave.
- **Boss wave:** `{ "boss": "flagship", "triggers": [...] }`. The total is 1 (the Flagship). It resolves on `boss_defeated`. Boss-launched Wasps are **not** counted.
- After the last wave: `outro_sequence` (if any) → `Events.level_cleared` → `GameState` and `SaveManager` update → `SceneRouter` goes to the next story or level. As built (Story 4.2): `level.gd` listens to `Events.level_cleared` and calls `SceneRouter.complete_level(id)` (the router itself doesn't listen, so bare WaveDirector tests never change scenes or save). Once `Events.level_failed` fires, the WaveDirector clears nothing and freezes progress (kills don't resolve, nothing is subtracted, no `wave_progress_changed`, no progress triggers, no stall net, F3 refuses; chains and group spawns still run) until the next `start_level` / `debug_skip_to_boss` (retro F1, DW-54). First outcome wins (decision #39): a `level_failed` after `level_cleared` changes nothing in the WaveDirector, and after `level_cleared` the Player is safe, so it can't fail a cleared level.
- A spawn entry that fails (unknown type) is logged and **subtracted** from `total_counted`, so the wave can never soft-lock.

**Level-author trigger patterns (Story 5.6):** both Isolde beats are plain trigger data on the machinery above; no code knows about them. `data/levels/level_dev_isolde.json` shows both; play it by launching `level.tscn` directly with the arg (`"<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game res://scenes/level/level.tscn -- --level=dev_isolde`; on a normal launch through `boot.tscn` the arg has no effect).

- **Interruption:** one `comms` action naming a **combat** sequence (one line of at most 50 characters), gated by the interruptions flag, so the fight never stops and nothing waits on it:

  ```json
  { "when": "progress", "at": 0.25, "flag": "isolde_interruptions", "actions": [ { "comms": "l1_w3_isolde_interrupt" } ] }
  ```

- **Surrender prompt (paired triggers):** two triggers at the same `at`, one per flag state. The `surrender_prompts` one plays the **story** sequence (it pauses, and the chain waits for the click-through) and then spawns the group; the `!surrender_prompts` one only spawns the group. Exactly one of them fires in any attempt. The `level_1.json` example above has this shape.
- **A flag gates only its beat.** A trigger whose flag fails runs none of its actions, so anything that must happen either way (the reinforcements) goes in **both** triggers of the pair. Never put a must-happen action only behind a flag-gated trigger: with the flag off the group would never spawn, and the wave (whose `total_counted` includes the group up front) would end only through the stall net's `Log.error` and subtraction.
- Triggers read `Config.flags` when they fire, and F5 re-reads `flags.json` and restarts the level, so flipping a flag needs no script or level change. Under F3 the paired surrender still pauses, but F3 skips every unspawned group, so the reinforcements don't spawn (the wave is resolved anyway).

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

The excerpt below is the original sketch. As built (Story 5.3) the loop is `_run_chain`, a story `comms` waits with `while count(id) == before: await _sequence_done` (the director's own relay signal, see above), `wait` awaits a child `Timer`, and after every await a chain of an older wave returns without touching the counters.

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
- Death mid-chain: the scene reloads, so every chain is discarded with the scene. Built (Story 5.3): because every chain await is on the director's own signal or child `Timer`, a freed director never resumes a chain (no "class instance is gone" error).

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
        { "speaker": "tarek", "text": "General, get behind me, I've got you covered!",
          "cut_off_at": 40, "after": { "silence": "until_wave_clear", "shake": "large",
                                        "sfx": "comms_static", "music": "stop" } }
      ]
    },
    "l2_ryn_report": {
      "mode": "story",
      "lines": [
        { "speaker": "ryn", "text": "General, this is Commander Ryn Holt, Tarek's daughter. His ship is mine now." },
        { "speaker": "ryn", "text": "He's alive. Barely. The medics have him, and he won't fly again for a long time." },
        { "speaker": "ryn", "text": "And so is his fight. I'm taking command." }
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

**Built (Story 5.1):** `systems/comms/comms_channel.gd` (`CommsChannel`), `comms_panel.tscn` + `comms_panel.gd` (`CommsPanel`) and `dialogue_validator.gd` (`DialogueValidator`), instanced as `Comms/CommsChannel` and `Comms/CommsPanel` in `level.tscn`: the story path, the story queue, unknown ids and the combat placeholder. See As-built 2026-10-08 (Story 5.1).

**Built (Story 5.2):** `systems/comms/comms_box.tscn` + `comms_box.gd` (`CommsBox`, the UX interruption box), instanced as `Comms/CommsBox` in `level.tscn` before `CommsPanel`, and the channel's combat path: combat lines and the priority rules below. Silence and cut-off were built later (Story 5.4); choice is still planned (Story 7.5). See As-built 2026-10-08 (Story 5.2).

**Built (Story 5.3):** the WaveDirector `comms`, `story_event` and `music` actions, `intro_sequence` and `outro_sequence` (see [Wave Director + Beat Triggers](#1-wave-director--beat-triggers)) and music in the `Audio` autoload. See As-built 2026-10-08 (Story 5.3).

**Built (Story 5.4):** cut-off lines and silence in `CommsChannel` and `CommsBox`, the `cut_off_at` / `after` rules in `DialogueValidator`, `Feedback.shake_tier` and the `comms_static` SFX. See As-built 2026-10-08 (Story 5.4).

**Rules:**

- **Story** sequence: `PauseArbiter.push(&"story")`, then show each line with the typewriter (`tuning.comms.chars_per_s`, default 45). On click: if the line is still typing, complete it; if it's complete, go to the next line. After the last line: `PauseArbiter.pop(&"story")` and emit `finished`.
- **Advance on release (built, Story 5.1):** the channel consumes both the `comms_advance` press and its release (`set_input_as_handled()` in `_unhandled_input`) and acts on the **release**; a press only arms it. `set_input_as_handled()` doesn't change `Input.is_action_pressed`, so acting on the press would lift the pause with LMB still held and the Player's next physics tick would fire the laser. An unarmed release (the button was held from before the panel opened) is consumed and ignored. Nothing is consumed while the `menu` reason is active.
- **Combat** sequence (built, Story 5.2): no pause, and input is ignored. Each line stays for `max(5.0, chars / chars_per_s + 3.0)` seconds of game time (`comms.combat_line_min_s`, `combat_line_extra_s`; GDD decision #41), then advances; after the last line the box fades and `finished` is emitted. Each combat line starts with a key-in cue played quieter than in a story (`comms_open_nobeep`, `comms_open` without its beep, at `comms.combat_open_db` when the box opens fresh, `comms_handover` / `comms_click` at `comms.combat_line_cue_db` straight after another combat line; GDD decision #42). The timer runs only while the tree isn't paused, so a pause menu freezes the line.
- **Priority (built, Story 5.2):**
  - A story sequence **preempts** any playing combat line. The combat line is dropped, and its sequence still emits `finished` (deferred). Queued combat sequences are kept and play after the story.
  - A combat sequence requested while another combat sequence plays **or a story shows** is **queued** (FIFO, max `comms.combat_queue_max` = 3, oldest dropped; a dropped sequence still emits `finished`, deferred). Queued combat plays once neither a story nor a combat line is showing.
  - A story sequence requested while a story sequence plays is queued (never dropped).
  - Every requested known sequence emits `finished` exactly once (played, preempted or dropped).
- **Silence (built, Story 5.4):** while `silenced`, combat sequences are dropped (logged at DEBUG, `finished` deferred), and turning silence on drops every queued combat sequence the same way. Story sequences are still delivered. `until_wave_clear` silence clears on `Events.wave_cleared`. A `wave_cleared` that arrives while the cut-off line is still typing voids its silence, so it never carries into the next wave.
- **Cut-off (built, Story 5.4):** combat sequences only (a combat sequence has one line, so the cut-off line is the whole sequence). The box typewriter stops at exactly `cut_off_at` characters after `cut_off_at / chars_per_s` s of game time. Then the `after` effects run in order: `Audio.play_sfx(sfx)` (`comms_static`), `Feedback.shake_tier(...)`, `Audio.apply_music_action(music)` (`stop` fades out), silence. The box then hides at once (no fade) after `comms.cutoff_hide_s` (0.6 s) and `finished` is emitted. A story that preempts the line before its cut-off moment drops it with no effects.
- **Choice:** `PauseArbiter.push(&"final_choice")` while the buttons are shown. There's no timer. The choice is saved to `GameState.final_choice` for a possible epilogue.
- Unknown sequence id: `Log.error` and emit `finished` in the same frame but **deferred** (`call_deferred`), so the waiting chains never hang and a caller that emits the request and then awaits `finished` still sees it.

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
- `shake_tier(tier)` (built, Story 5.4, the comms cut-off): shakes the registered camera with the tier's `shake_px` / `shake_s` only, with no explosion, hit-stop or SFX. An unknown tier logs `Log.error` and does nothing; with no camera it does nothing.
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

**Known gaps (registered when their epic lands):** the `boss_part` and `boss_death` rows name sfx ids that `Audio.SFX` doesn't register yet (they warn once and play nothing); `player_hit` (Story 3.1) and `player_death` (Story 3.2) are registered. The extras `white_flash` and `red_vignette` aren't handled by `Explosion` (ignored); the red vignette is the HUD `HitVignette` instead.

```gdscript
# Every entity death looks like this — nothing else (as built in Enemy since Story 3.3;
# the Asteroid drops after asteroid_destroyed the same way):
func _die() -> void:
	Feedback.impact(_tier, global_position)    # explosion + shake + hit-stop + sfx
	Events.enemy_killed.emit(type_id, global_position, _last_hit_by_ally)
	_drop_loot()
	resolved.emit()
	queue_free()
```

- Shake: `ShakeCamera` keeps the **strongest** active shake. It decays its amplitude linearly over the duration and applies a random offset every frame. It uses `process_mode = ALWAYS` so the shake survives hit-stop but not the pause menu (it reads `PauseArbiter.is_paused()`).
- **Planned:** the `BOSS_DEATH` chain explosions (4× over 2 s) are sequenced by `Feedback.boss_death(pos)`, not by the Flagship.
- **Built (Story 3.1):** `PLAYER_HIT` has its red edge vignette: `HUD/HitVignette`, a `ColorRect` shader in the HUD triggered by `Events.player_hit` (alpha `hud.hit_vignette.max_alpha` fading over `duration_s`).

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

func clear() -> void:                  # SceneRouter calls this at every scene swap, right after the change call (DW-61); F5 right after its restart. Keeps _gameplay_mode
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
	wasp.add_to_group(Groups.COUNTED)
```

**The `Enemy` base class contract** (`core/enemy.gd`, `class_name Enemy extends Area2D`):

- `signal resolved`, which is emitted exactly once (on a kill or on a Maul miss).
- `var type_id: StringName`, `var tier: int` (ImpactTier).
- `func setup(params: Dictionary) -> void`.
- `func apply_damage(amount: int, source: Node) -> void` (it records `source.from_ally`).
- `func destroy_by_contact() -> void` (small and medium enemies only).
- HP comes from `Config.int_("enemies.<type_id>.hp")`. Drops come from `tuning.drops.<type_id>`.
- Shared subclass helpers (DW-41): `setup()` also stores `slot`/`entry` (`_slot`, `_has_slot`, `_entry`; constants `ENTRY_TOP`, `ENTRY_SIDES`; the player is found through `Groups.PLAYER`, DW-61), `_entry_start_for(target)` (off-screen entry start, WARNs on an unknown entry and uses top), `_aim_from(origin)` (unit vector to the player, `Vector2.DOWN` without one), `_can_fire()` (missing-spawner guard, one DEBUG per enemy) and `_tuning_key(field)` (`"enemies.<type_id>.<field>"`). Enemy projectiles share `EnemyBullet._align_to_velocity(node)`.

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

**Access:** only through the `Config` autoload's typed getters (see Configuration). The built getters are `num`, `int_`, `flag`, `section`, `level(id) -> Dictionary` (Story 2.2) and, since Story 5.1, the dialogue getters `sequence(id) -> Dictionary`, `has_sequence(id) -> bool` and `dialogue_is_story(id) -> bool`; every `data/dialogue/*.json` is validated by `DialogueValidator` at load (story lines at most `comms.story_line_max_chars`; since Story 5.2 a combat sequence has exactly one line of at most `comms.combat_line_max_chars`).

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

**`tuning.json` top-level sections (fixed):** `player`, `weapons`, `abilities`, `energy`, `drops`, `enemies`, `boss`, `asteroids`, `convoy`, `allies`, `waves`, `progression`, `comms`, `feedback`, `damage`, `hud`, `ui`, `audio`, `render`, `debug`.

- `audio.music_fade_out_s` (0.5, Story 5.3) is the `music: stop` fade.

- `progression.level_count` (3, Story 4.2) is the number of campaign levels (ids 1..level_count). Nothing hard-codes 3.

- `debug.bench` (`avg_ms_max`, `p99_ms_max`, `max_ms_max`, `warmup_s`, `first_large_at_s`, `first_large_frames`, `quit_delay_s`) and `debug.stress` (`projectiles`, `projectile_spawn_per_tick`) hold the debug-build stress bench numbers (GDD decision log #33). Only `DebugTools` and the sandbox's stress mode read them; the stress-grid layout and `BENCH_MAX_FPS` / `BENCH_AIM` / `OVERLAY_REFRESH_S` stay code consts.
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

The comms channel consumes `comms_advance` (press and release) with `get_viewport().set_input_as_handled()` in `_unhandled_input` and advances on the release, so a click that advances a story line never also fires the laser. The laser checks `Input.is_action_pressed("fire_laser")` only while the tree is unpaused, and the pause lifts only once the button is up (Story 5.1).

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
| Barrage homing | Nearest enemy picked **once** on spawn and re-picked only when the target is freed (`is_instance_valid`). No per-frame group scans. Built (Story 3.5): `MicroMissile` re-picks once per lost target (freed or queued for deletion) and stops scanning when that finds nothing; with no target it steers toward straight up; it turns at most `turn_rate_deg_s`, keeps its speed and frees itself after `lifetime_s` |
| Ally targeting | Re-acquire the nearest enemy every 0.5 s (on fire), not every frame |
| Verification | E1 sandbox stress test at the NFR1 peak: `-- --stress` (40 Wasps refilled on death, ~200 live projectiles topped up through `Spawner`, F1 overlay on, vsync off) for a manual look, and `-- --bench=N` for a self-timing run (fire held at `BENCH_AIM`, one deliberate LARGE impact during the 2 s warm-up with its frame ms logged, N s sampled, logs avg/p99/max, exit 0 only if avg, p99 and max are all < 16.6 ms (`debug.bench`), else 2; quits after a short real-time delay so the final line is never lost). Add `-- --no-prewarm` to compare the first LARGE impact without `Feedback.prewarm()`. Re-run `--bench=20` after any visual change. Last results: GDD decision log #27 and #32 (taken before the 200-projectile load and the p99/max gate) |

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
| Hearts, i-frames, shield, contact damage tiers | `player.gd` (contact, death) + `core/health_component.gd` (hearts, i-frames) + `player_shield.gd` + `tuning.damage` |
| Energy carry-over, wipe on death, save on clear | `GameState` + `SaveManager` rules |
| Drop table, orb magnet and despawn | `tuning.drops`, `core/loot.gd`, `energy_orb.gd` |
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
# Import the project (builds the class_name cache and imports the project's assets).
# Copy of the note in AGENTS.md section 3 (Project facts), Tests bullet, which is the source; change both together.
# Run on a fresh clone with no game/.godot/. Re-run after adding, changing or removing a class_name declaration
# (including adding, renaming, moving or deleting a script that has one), after adding, changing, renaming, moving
# or deleting an imported asset, after any pull or branch switch, or when game/.godot/ is stale: headless -s runs
# don't rescan the class cache, and an asset has no imported copy in the gitignored game/.godot/imported/ until
# --import runs (only the .import sidecars are tracked). Typical symptoms: a parse error naming a class_name that
# exists, or a preload or resource-load failure for an asset that exists.
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

## As-built 2026-10-07 (Story 2.2)

Status update only; no design decision changed.

- **Built:** `scenes/level/level.tscn` + `level.gd` (main scene, runs `level_dev.json`), `systems/waves/wave_director.gd`, `formation.gd` (`Formation`), `level_validator.gd` (`LevelValidator`), `Config.level(id)` (plus `Config.level_at(path)`), `ui/hud/level_clear_banner.gd`, F3, F6 and the F1 wave/resolved/pause lines, `tests/data/test_data_files.gd`.
- **Level tree:** a `Spawner` node (`world = ../World`) sits at the root next to `WaveDirector`, which references it through its exported `spawner`.
- **Asteroid entries** in a wave are `{ "size": "small" | "medium" | "large", "count": n }`. They spawn at the top edge at a random x and are never counted.
- **`waves.formation`** in `tuning.json` (`spacing_px.x/y`, `top_y`) drives the `grid_<C>x<R>` slot math; each spawn entry and spawned group starts on the next free formation row, except a Hunter Wasp entry (`EntityRegistry.ROWLESS_TYPES`), which never holds its slot and so doesn't advance the row (the Needle anchors on and roams row 0, so it takes a row). Grid columns are capped at what fits the playfield width (`Formation.max_columns()`: `floori(Playfield.SIZE.x / spacing_px.x)`), wrapping extra slots onto further rows, and `LevelValidator` rejects a wider grid (DW-37).
- **`--stress` / `--bench` redirect:** in a debug build, `level.gd` switches to the sandbox stress scene (`change_scene_to_file`, deferred) when either arg is given. Like the F5 reload, this is a debug-only exception to "only `SceneRouter` changes scenes". Since Story 4.1 the main scene is `boot.tscn`, which carries the same redirect, so the CLI bench still works.
- `Config.level()` reads `EntityRegistry`'s enemy ids at runtime (`EntityRegistry.enemy_types()`): a static reference to `EntityRegistry.ENEMIES` from `Config` is a cyclic compile dependency (enemy scripts use `Config`).

## As-built 2026-10-07 (Story 2.3)

Status update only; no design decision changed.

- **Built:** `ui/hud/wave_bar.gd` (`WaveBar`) on the level's HUD layer, driven only by `level_started` / `wave_started` / `wave_progress_changed` / `wave_cleared`. It fills the current segment with a node-bound 0.2 s tween, never goes back within an attempt, and highlights the next segment during the gap.
- **Theme created:** `ui/theme/defector_theme.tres`, seeded with the `WaveBar` type items (`track`, `fill`, `highlight` `StyleBoxFlat`s in the UX Cold Neon tokens, `separation` = 4).
- **Tuning:** a new `hud` top-level section, `hud.wave_bar` (`x`, `y`, `width`, `height`, `fill_tween_s`).

## As-built 2026-10-07 (Story 2.4)

Status update only; no design decision changed.

- **Wasp states:** `entities/enemies/wasp/wasp.gd` is now `class_name Wasp` with `enum State { ENTER, HOLD, TELEGRAPH, DIVE }`. `_state` is assigned only in `_enter_state()` (entry effects: ENTER places the Wasp at its entry point, TELEGRAPH turns the wing flash on, DIVE snapshots the direction to the player, or straight down without one); `_physics_process` only calls `step(delta)`. A Wasp spawned with a `slot` enters from `entry` (`top`: above its slot; `sides`: the nearer side edge at the slot's y; anything else warns and uses top) at `entry_speed_px_s`, holds, and on `start_dive()` flashes `Hull.self_modulate` for `telegraph_s` without moving, then dives at `dive_speed_px_s`. Leaving `Playfield.RECT` grown by `sprite_px / 2` sends it back to ENTER from above its slot; it never resolves for leaving. A slot below the zone is clamped with a WARN. Without a `slot` (sandbox, stress bench) it holds its position forever.
- **Dive cadence:** `entities/enemies/wasp/wasp_dive_clock.gd` (`WaspDiveClock`, a plain `Node`) is the `WaveDirector/WaspDiveClock` child in `level.tscn` (the root tree is unchanged). Every random `dive_interval_s` (min..max, own seedable `rng`) it calls `start_dive()` on one random holding, living Wasp in group `enemies`. The sandbox has no clock.
- **Player group:** the Player joins group `player` in `_ready`; a Wasp looks it up once per dive.
- **Tuning:** `enemies.wasp` gains `zone_height_ratio` (0.4), `wing_flash_hz` (10) and `wing_flash_energy` (2.0).
- **Data tests:** `tests/data/test_data_files.gd` enforces the >= `weapons.enemy_bullet.min_telegraph_s` rule over every `telegraph_s` / `lock_s` / `charge_s` / `*_telegraph_s` / `*_charge_s` key in `tuning.enemies` and `tuning.boss`, and checks that every level wave with a Wasp keeps its stacked formation rows inside the top `zone_height_ratio` of 1080.

## As-built 2026-10-07 (Story 2.5)

Status update only; no design decision changed. Amended 2026-10-08: the Lancer cadence in the "Lancer states" bullet follows decision #38 (DW-40).

- **Lancer states:** `entities/enemies/lancer/lancer.gd` is `class_name Lancer` with `enum State { ENTER, STRAFE, TELEGRAPH }`, the same `step(delta)` / `_enter_state()` shape as the Wasp. A Lancer with a `slot` enters from `entry` (`top` / `sides`, anything else warns and uses top) at `strafe_speed_px_s`; a slot below `zone_height_ratio` × 1080 is clamped with a WARN. STRAFE and TELEGRAPH both move horizontally between `sprite_px / 2` and `1920 − sprite_px / 2` (first toward the screen centre), never changing y. After `max(fire_interval_s − telegraph_s, 0)` in STRAFE (timer reset on each entry, so never while entering) it enters TELEGRAPH (`Muzzle/MuzzleGlow` shown at `muzzle_glow_energy`), and after `telegraph_s` fires one `enemy_bullet` from `Muzzle` toward the player's position at that moment (straight down without one), then returns to STRAFE. The shot period is start-to-start `fire_interval_s`, matching the Needle (DW-40, decision #38; as first built it was `fire_interval_s + telegraph_s`, 2.3 s): with default tuning 1.7 s strafe, 0.3 s glow, shots 2.0 s apart, the first 2.0 s after STRAFE begins. Without a `slot` it strafes from its spawn position.
- **`EnemyBullet`** (`entities/projectiles/enemy_bullet.tscn`, `class_name EnemyBullet extends Projectile`): the shared enemy bullet. Layer `enemy_shots`, mask `MASK_ENEMY_SHOTS`; a round `enemy` orb with a white core (≥ `weapons.enemy_bullet.min_diameter_px`); a capsule turned in `_ready` so its long axis follows `velocity`. It never damages anything on the `asteroids` layer (only player shots chip asteroids), so asteroids stop it without losing HP. No impact feedback yet (player-hit feedback is Epic 3).
- **`Enemy.spawner`:** `Spawner.spawn_enemy` sets `enemy.spawner = self` before `setup` / `add_child`; shooting enemies request projectiles through it. With no valid spawner a Lancer skips its shot (one DEBUG line per Lancer).
- **`Projectile._can_damage(area) -> bool`:** a hook (default `true`) checked before `apply_damage` in `_on_area_entered`; the projectile still stops and frees when it returns false.
- **Tuning:** `enemies.lancer` gains `muzzle_glow_energy` (2.5); bullet damage is `damage.bullet_hearts`. `level_dev.json` wave 3 adds two side-entering Lancers (`grid_2x1`).
- **Data tests:** the formation-zone test covers Wasps and Lancers, each against its own `zone_height_ratio`; every `bullet_speed_px_s` under `tuning.enemies` and every `*_speed_px_s` under `tuning.boss` must be ≤ `weapons.enemy_bullet.max_speed_px_s`.

## As-built 2026-10-07 (Story 2.6)

Status update only; no design decision changed.

- **Needle states:** `entities/enemies/needle/needle.gd` is `class_name Needle` with `enum State { ANCHORING, TRACKING, LOCKED, COOLDOWN }`, the same `step(delta)` / `_enter_state()` shape as the Wasp and Lancer. The cycle period is start-to-start `fire_interval_s`: TRACKING `track_s` (the in-world `TelegraphLine` Line2D, `enemy` at alpha 0.5, width 2, re-aimed from `Muzzle` at the player every tick, straight down without one, `Playfield.SIZE.length()` long), LOCKED `lock_s` (line frozen, `danger` #FF1F4B, width 4), then one `needle_bolt` from `Muzzle` along the locked line at `bolt_speed_px_s`, then COOLDOWN `max(fire_interval_s − track_s − lock_s, 0)` with the line hidden. With default tuning: shots 1.5 s and 5.5 s after arriving on an anchor. Without a valid spawner the cycle runs and skips the shot (one DEBUG line per Needle).
- **Anchor and reposition:** the anchor y is always `anchor_y_px` (a slot's y is ignored, so the Needle keeps its long sightline whatever its formation row); x is the slot's x clamped into `[sprite_px / 2, 1920 − sprite_px / 2]` (WARN if clamped). Entry `top` / `sides` (anything else warns and uses top); ANCHORING flies at `reposition_speed_px_s`. Anchored time counts from arrival and is only acted on in COOLDOWN (a reposition never interrupts a track or lock): once it reaches `reposition_interval_s` the Needle flies to a new x, uniform over the parts of the range at least `reposition_min_distance_px` away (the whole range if none), from its seedable `rng`. Without a `slot` the spawn position is the anchor.
- **`NeedleBolt`** (`entities/projectiles/needle_bolt.tscn`, `class_name NeedleBolt extends EnemyBullet`): an elongated `Streak` (white core, `enemy` edge, 20 px wide) turned with the 48 px capsule onto `velocity`. Damage, asteroid cover and freeing are inherited unchanged, so an asteroid on the locked line stops the bolt without losing HP.
- **Tuning:** `enemies.needle` gains `anchor_y_px` (160), `reposition_speed_px_s` (400) and `reposition_min_distance_px` (320). `level_dev.json` wave 4 adds two top-entry Needles (`grid_2x1`), four Wasps and two medium asteroids.
- **Data tests:** Needle tuning ranges (`track_s + lock_s ≤ fire_interval_s`, `reposition_interval_s ≥ fire_interval_s`, `anchor_y_px` inside the enemy zone), and every level wave with a Needle has ≥ 2 medium or large asteroids (GDD cover rule).

## As-built 2026-10-07 (Story 2.7)

Status update only; no design decision changed. Amended 2026-10-08: the "Cadence and spread" bullet follows decision #38 (DW-40).

- **Bastion states:** `entities/enemies/bastion/bastion.gd` is `class_name Bastion` with `enum State { ENTER, DRIFT, TELEGRAPH }`, the same `step(delta)` / `_enter_state()` shape as the Lancer. A Bastion with a `slot` enters from `entry` (`top` / `sides`, anything else warns and uses top) at `drift_speed_px_s`; a slot outside the drift box is clamped with a WARN. Without a `slot` it drifts from its spawn position.
- **Drift box:** the hull centre stays in x `[sprite_px / 2, 1920 − sprite_px / 2]`, y `[band_y.min + sprite_px / 2, band_y.max − sprite_px / 2]` (the band centre if the band is shorter than the hull), so the 160 px sprite box (`sprite_px`) stays inside y 80–400 (the drawn hull, about 160×107, sits within it). DRIFT and TELEGRAPH move toward a target at `drift_speed_px_s` and pick a new uniform target from the seedable `rng` on arrival.
- **Cadence and spread:** after `max(fire_interval_s − telegraph_s, 0)` in DRIFT (timer reset on each entry, so never while entering) every `Turrets/TurretN/Glow` shows at `turret_glow_energy` for `telegraph_s`, then every turret fires `spread_bullets` `enemy_bullet`s from its own position, evenly spaced from −`spread_deg` to +`spread_deg` around straight down (one bullet: straight down), at `bullet_speed_px_s`. The spread is never aimed; both turrets share the timer. The volley period is therefore start-to-start `fire_interval_s`, matching the Needle (DW-40, decision #38; as first built it was `fire_interval_s + telegraph_s`, 3.0 s): with default tuning 2.0 s drift, 0.5 s glow, volleys 2.5 s apart, the first 2.5 s after DRIFT begins. The scene's turrets are used; a mismatch with `turrets` warns once. Without a valid spawner the cycle runs and skips the volley (one DEBUG line per Bastion).
- **Contact guard:** `Enemy.destroy_by_contact()` does nothing unless `tier` is `SMALL` or `MEDIUM`, so the Bastion (and later Flagship parts) ignore contact.
- **Tuning:** `enemies.bastion` gains `turret_glow_energy` (2.5). `level_dev.json` wave 5 adds one top-entry Bastion (`grid_1x1`, row 0 at y 160) and six Wasps.
- **Data tests:** Bastion tuning ranges (speeds and interval > 0, `turrets` and `spread_bullets` ≥ 1, `spread_deg` in [0, 90), `turret_glow_energy` > 1, `band_y` inside the enemy zone and at least `sprite_px` tall).

## As-built 2026-10-07 (Story 2.8)

Status update only; no design decision changed.

- **Hunter Wasp:** `entities/enemies/hunter_wasp/hunter_wasp.gd` is `class_name HunterWasp extends Enemy` (not a `Wasp`, so the `WaspDiveClock` never picks it). No states: every `step(delta)` turns the unit `heading` toward the target by at most `turn_rate_deg_s` × delta (exactly onto it when the angle is smaller), then moves `chase_speed_px_s` × delta along it; `rotation = heading.angle() − PI/2` (the hull nose points down). The target is the cached `player` group node, looked up again at most every 0.5 s (`PLAYER_RELOOKUP_S`) while missing or freed; without one it is `Playfield.SIZE / 2`. With a `slot` it starts off-screen: `top` above the slot heading down, `sides` at the nearer side edge at the slot's y heading inward (anything else warns and uses top); it never holds the slot and never wraps. Without a `slot` it starts at its spawn position heading down. Contact only, orange hull `#FF8A1F`, 3 HP, small tier. Contact damage to the player is Epic 3.
- **Flag gate:** `EntityRegistry.ENEMY_FLAGS` maps a type id to the `flags.json` flag that gates it (`hunter_wasp` → `hunter_wasp`); the type stays in `ENEMIES`, so levels always validate (F14). `WaveDirector.start_wave` reads each gate once per wave; an entry (spawn or group) whose type is disabled counts 0, takes no formation rows and spawns nothing. One DEBUG `spawn` line is logged when the entry would spawn (a group entry only if its group is requested; a never-requested group logs nothing). It is never subtracted.
- **Flag default:** `flags.hunter_wasp` stays `false`. `level_dev.json` wave 6 lists four Hunter Wasps (`grid_4x1`) and six Wasps; with the default flag only the Wasps spawn.
- **Data tests:** Hunter Wasp tuning ranges (`chase_speed_px_s` > 0, `turn_rate_deg_s` in (0, 360], `hp` ≥ 1) and every `ENEMY_FLAGS` entry is a registered enemy with a bool flag in `flags.json`.

## As-built 2026-10-07 (Story 3.1)

Status update only; no design decision changed.

- **Hearts and i-frames:** `Player` exposes `hearts` / `max_hearts` (`player.hearts`; held by the `Health` child since DW-55). `apply_damage(amount, source)` with amount > 0, not invulnerable and hearts > 0 floors hearts at 0, emits `Events.hearts_changed(hearts, max_hearts)` and `Events.player_hit(global_position)`, calls `Feedback.impact(ImpactTier.PLAYER_HIT, global_position)` and starts `player.iframes_s` of i-frames; anything else is ignored with no event. I-frame time accumulates in `step_iframes(delta)` from physics delta (no timers), so it freezes under pause and hit-stop. During i-frames only the `Sprite` child flickers (`fmod(elapsed × iframe_flicker_hz, 1) < 0.5` is visible) and is restored when they end. At 0 hearts one `Log.info("combat", …)` line runs and no more damage is taken (death is Story 3.2). The first `hearts_changed(max, max)` is emitted deferred from `_ready`, after the HUD's `_ready`.
- **Contact:** the Player connects its own `area_entered` / `area_exited`. `on_contact(area)`: a small or medium `Enemy` costs `damage.contact_small_hearts` / `contact_medium_hearts`, then `destroy_by_contact()` runs, even while invulnerable (F15); any other enemy tier (Bastion) costs `contact_large_hearts` and survives; an `Asteroid` costs by `size` and is never destroyed by contact; dead enemies and other areas (pickups) are ignored. Surviving hazards are kept in a typed `_contacts` array while they overlap (freed, dying or dead entries pruned); when the i-frames end, or `debug_invincible` turns off, the newest one still overlapping hits again, so sitting in a large asteroid keeps costing hearts.
- **HUD:** `HeartsDisplay` and `HitVignette` (see UI Framework). Theme items added: `HeartsDisplay/colors/heart|empty|outline`, `HitVignette/colors/color`.
- **Audio:** `player_hit` is registered in `Audio.SFX` (`sfx_player_hit.wav`, generated by `tools/gen_placeholder_sfx.py` with its own seed so the older WAVs are unchanged).
- **Debug:** F2 `DebugTools.toggle_invincible()` and the overlay `invincible` line.
- **Tuning:** `hud.hearts` (`right_x`, `y`, `icon_px`, `gap_px`, `pop_scale`, `pop_s`) and `hud.hit_vignette` (`duration_s`, `max_alpha`).

## As-built 2026-10-07 (Story 3.2)

Status update only; no design decision changed.

- **Autoloads:** `GameState` (`autoloads/game_state.gd`: `energy: int`, `current_level_id: String`, `is_retry: bool`, no logic) and `SceneRouter` (`autoloads/scene_router.gd`, `PROCESS_MODE_ALWAYS`). The order is now `Log, Events, Config, GameState, PauseArbiter, Audio, Feedback, EntityRegistry, SceneRouter`; `SaveManager` (Epic 4) takes its slot between `GameState` and `PauseArbiter`.
- **SceneRouter:** `LEVEL_SCENE_PATH` = `res://scenes/level/level.tscn`. `change_scene: Callable` defaults to `get_tree().change_scene_to_file` (`default_change_scene()`); tests inject a recorder. `restart_level()` sets `GameState.energy = 0` and `is_retry = true`, then `PauseArbiter.clear()`, `Feedback.reset()`, one `Log.info("scene", …)` and `change_scene.call(LEVEL_SCENE_PATH)`; no counter, no limit. `goto_title()` is a placeholder until Story 4.1/4.2: `energy = 0`, `is_retry = false`, `current_level_id = ""` (so the main scene runs its own exported id), the same clear/reset, then the `application/run/main_scene` (today the level, so a fresh non-retry attempt).
- **Level id:** `level.gd` runs `resolve_level_id(exported, GameState.current_level_id)` (the state id when non-empty, else the export), writes the result back to `GameState.current_level_id`, and tags its start line ` (retry)` when `GameState.is_retry`.
- **Player death:** the hit that brings hearts to 0 still emits `hearts_changed` and `player_hit`, then plays `Feedback.impact(ImpactTier.PLAYER_DEATH, …)` instead of `PLAYER_HIT`, logs once and emits `Events.player_died` then `Events.level_failed(&"hearts")`. The dead ship is hidden (`visible = false`, MissileRing included), its i-frames stop (`Health.stop_iframes()`; the shield `Shield.drop()`s), `monitoring` / `monitorable` go off (deferred), `_contacts` is cleared, `apply_damage` / `on_contact` / the contact re-check are no-ops and `_physics_process` returns at once. This replaces the Story 3.1 "hearts reached 0" line. Since DW-54 (decision #39) the Player also listens to `Events.level_cleared`: from then on it is safe (`is_safe()`, never reset): `apply_damage` and hazard contact are ignored (no hearts, no events, small/medium enemies not destroyed, nothing remembered; not routed through `is_invulnerable()`), remembered contacts are dropped, energy orbs are still collected and the ship stays visible and able to fire, so it never emits `player_died` / `level_failed` on a cleared level. A ship that already died stays dead.
- **Retry prompt:** `ui/menus/retry_prompt.tscn` + `.gd` (`class_name RetryPrompt extends Control`), full rect under `Overlay` before `DebugTools`; `PROCESS_MODE_ALWAYS`, hidden at start, `MOUSE_FILTER_STOP` only while shown. On the first `Events.level_failed` it starts a pausable `create_timer(feedback.player_death_pause_s, false)` (the death beat freezes under any pause and stretches with hit-stop); then `show_prompt(reason)` pushes `&"death"`, shows the `Dim`, the `Reason` (`HULL DESTROYED` for `hearts`, `CONVOY LOST` for `convoy`, anything else `HULL DESTROYED` plus a WARN) and RETRY · QUIT TO TITLE, and focuses RETRY with the focus ring hidden (`grab_focus(true)`; the UI is mouse-only). Later failures are ignored; a `_leaving` flag ignores repeat presses. RETRY → `SceneRouter.restart_level()`, QUIT → `SceneRouter.goto_title()`. It reads only `Events`.
- **Theme:** `RetryPrompt/colors/dim|reason|text`, `RetryPrompt/font_sizes/button` (28) and `RetryPrompt/styles/button_normal|button_hover|button_focus` (`surfaceAlt` fill, 1 px `border`; hover and focus have a `coalition` border).
- **Audio:** `player_death` is registered in `Audio.SFX` (`sfx_player_death.wav`, a 1.0 s explosion plus buzz generated by `tools/gen_placeholder_sfx.py` with its own seed, so the older WAVs are unchanged).
- **Tuning:** a new `ui` top-level section, `ui.retry_prompt` (`headline_y`, `headline_px`, `button_w`, `button_h`, `button_gap_px`, `buttons_top_y`). The beat is the existing `feedback.player_death_pause_s`.

## As-built 2026-10-07 (Story 3.3)

Status update only; no design decision changed.

- **GameState energy:** `max_energy()` (`Config.int_("energy.max")`), `add_energy(amount) -> int` (clamps `energy + amount` into 0..max, always emits `Events.energy_changed(energy, max)`, even at the cap, and returns the new value) and `emit_energy()` (announces the current value). `SceneRouter.restart_level()` / `goto_title()` still write `energy = 0` directly; `level.gd` calls `GameState.emit_energy()` right after `level_started`, so the reloaded level announces it.
- **Loot:** `core/loot.gd` (`class_name Loot`, static only). `orb_count(row, roll)` is `row.orbs` when `roll < row.chance`, else 0 (0 for a missing or non-number field). `drop(spawner, table_key, at, roll = randf())` reads `drops.<table_key>` and calls `spawner.spawn_orb.call_deferred({position})` once per orb, `energy.orb_spread_px` apart horizontally and centred on `at`; it returns the count. The spawner parameter is untyped so a freed spawner returns 0 with no script error (a `Spawner`-typed parameter rejects a freed instance). Spawning is deferred because deaths happen inside `area_entered` (physics query flush).
- **Death paths:** `Enemy._die()` calls `_drop_loot()` (`Loot.drop(spawner, type_id, global_position)`) after `enemy_killed` and before `resolved`; `Asteroid` has a `spawner` field (set by `Spawner.spawn_asteroid`) and drops `asteroid_<size>` after `asteroid_destroyed`. Contact kills, ally kills and the F3 resolve all go through these paths. Without a spawner nothing drops.
- **EnergyOrb:** `entities/pickups/energy_orb.tscn` + `.gd` (`class_name EnergyOrb extends Area2D`): layer `pickups` (32), mask 0, group `pickups`, a `Hitbox` circle and an additive gold (`#FFD23F`) gradient `Sprite`, both `energy.orb_diameter_px`. `step(delta)` (from `_physics_process`) ages it and frees it at `orb_despawn_s`; while the Player (cached once in `_ready` by group) is valid, alive and within `orb_magnet_radius_px` (inclusive) it moves toward it at `orb_magnet_speed_px_s` without overshooting, else down at `orb_drift_px_s`; it frees itself once fully below the playfield. `collect()` works once: `GameState.add_energy(orb_value)`, `Audio.play_sfx(&"energy_pickup")`, `queue_free()`.
- **Spawner / registry:** `EntityRegistry.ENERGY_ORB`; `Spawner.spawn_orb(params)` parents to `World/Pickups`, which is optional like `Effects` (a missing container gives one DEBUG line and `spawn_orb` returns null).
- **Player:** `on_contact` collects an `EnergyOrb` first (after the dead guard), even while invulnerable or `debug_invincible`, at no heart cost, and never remembers it.
- **HUD:** `EnergyBar` (see UI Framework). Theme items added: `EnergyBar/styles/track` (`#2B3348`, 2 px corners), `EnergyBar/styles/fill` (`#FFD23F`, 2 px corners), `EnergyBar/colors/tick` (`#E8F4FF`).
- **Debug:** F4 `DebugTools.add_energy()` (debug builds only).
- **Audio:** `energy_pickup` is registered in `Audio.SFX` (`sfx_energy_pickup.wav`, a 0.15 s rising chime generated by `tools/gen_placeholder_sfx.py` with its own seed, so the older WAVs are unchanged).
- **Tuning:** `energy.orb_magnet_speed_px_s` (600), `energy.orb_diameter_px` (24), `energy.orb_spread_px` (32), `hud.energy_bar` (`right_x` 1888, `y` 76, `width` 320, `height` 16, `tick_px` 2) and `debug.energy_add` (100). These are first-pass feel defaults (the GDD gives no magnet speed, orb size or spread).

## As-built 2026-10-08 (Story 3.4)

Status update only; no design decision changed.

- **Player shield:** (state in the `Shield` child, `PlayerShield`, since DW-55) `try_shield()` (dead or already shielded: false, nothing else; `GameState.energy < abilities.shield.cost`: `_deny(&"shield")`; else `GameState.add_energy(-cost)`, shield up for `abilities.shield.duration_s`, bubble shown, one `Log.info("combat", ...)`). `step_shield(delta)` counts physics delta down after `step_iframes`; on the tick it reaches 0 the shield drops, the bubble hides and `_recheck_contacts()` runs. `_physics_process` reads `Input.is_action_just_pressed(&"ability_shield")` after `step_shield`. `_die()` clears the shield. The shield is part of `is_invulnerable()`, so no projectile or enemy code changed.
- **ShieldBubble:** `entities/player/shield_bubble.tscn` + `.gd`, a `coalition` (`#22E6FF`) `draw_arc` ring at `player.shield_bubble.alpha`; blink phase starts at the window start (`fmod((blink_last_s − remaining) × blink_hz, 1) < 0.5`).
- **HUD:** the `EnergyBar` denied flash (see UI Framework). Theme item added: `EnergyBar/colors/denied` (`#FF1F4B`).
- **Audio:** `ability_denied` is registered in `Audio.SFX` (`sfx_ability_denied.wav`, a 0.15 s low double buzz generated by `tools/gen_placeholder_sfx.py` with its own seed, so the older WAVs are unchanged).
- **Tuning:** `player.shield_bubble` (`diameter_px` 120, `stroke_px` 4, `alpha` 0.4, `blink_hz` 4, `blink_last_s` 0.75) and `hud.energy_bar.denied_flash_s` (0.3) / `denied_flashes` (2). The stroke is a data default (the UX spec gives none).

## As-built 2026-10-08 (Story 3.5)

Status update only; no design decision changed.

- **Player barrage:** (shares `Player._spend` with the shield since DW-55) `try_barrage()` (dead or volley running: false, nothing else; `GameState.energy < abilities.barrage.cost`: `_deny(&"barrage")`; else `GameState.add_energy(-cost)`, `_weapons.start_barrage()`, one `Log.info("combat", ...)`). `_physics_process` calls `step_barrage(delta)` and then reads `Input.is_action_just_pressed(&"ability_barrage")`, after the shield. `_die()` calls `stop_barrage()` (no more launches, no finish).
- **Volley (`PlayerWeapons`):** `start_barrage()` launches the first `&"micro_missile"` at once; `step_barrage(delta)` launches one each time the physics-delta countdown reaches `FIRE_EPS`, every `duration_s / missiles` (60 Hz ticks 0, 10, … 110, so the last launch lands at about 1.83 s). Each launch spawns at the muzzle with `Vector2.UP * speed_px_s` and `damage`, then plays `barrage_whoosh` and the muzzle flash; the 12th launch also plays one `Feedback.impact(LARGE)` at the muzzle. `missiles <= 0` or `duration_s <= 0` warns once in `_ready` and `start_barrage` then does nothing (the energy is still spent, as with the shield's mistuned-data rows).
- **MicroMissile:** `entities/projectiles/micro_missile.tscn` + `.gd`, layer `player_shots` (2), mask 84, `monitorable = false`, a capsule 4/16 and an additive `coalition` (`#22E6FF`) body. It homes on `nearest_enemy` picked in `_ready`, re-picks once per lost target, steers toward straight up with no target, turns at most `turn_rate_deg_s` at constant speed and frees itself after `lifetime_s`. Hits go through the base `Projectile` path, so asteroids block it.
- **Audio:** `barrage_whoosh` is registered in `Audio.SFX` (`sfx_barrage_whoosh.wav`, a 0.18 s rising filtered-noise whoosh generated by `tools/gen_placeholder_sfx.py` with its own seed, so the older WAVs are unchanged).
- **Tuning:** `abilities.barrage.speed_px_s` (800), `turn_rate_deg_s` (540, about an 85 px turn radius) and `lifetime_s` (3.0). These are first-pass feel defaults (the GDD gives no micro-missile speed, turn rate or lifetime).

## As-built 2026-10-08 (DW-55)

Refactor only; no behaviour, data or design decision changed.

- **Player split:** `player.gd` keeps the cursor lock, contact routing, death and the weapon and ability delegators. Hearts and i-frames moved to the `Health` child (`core/health_component.gd`, `HealthComponent`), the shield state and countdown to the `Shield` child (`entities/player/player_shield.gd`, `PlayerShield`, `bubble = ../ShieldBubble`). Neither component touches `Events`, `GameState` or `Audio`.
- **Hit order:** `HealthComponent.take(amount)` floors `current`, emits `damaged`, then `died` (at 0) or starts the i-frames. The Player's `damaged` handler emits `hearts_changed` then `player_hit`, then plays PLAYER_HIT when `current > 0`; `died` → `_die()`. `iframes_ended` and `PlayerShield.ended` → `_recheck_contacts()`. `_die()` calls `Health.stop_iframes()` and `Shield.drop()` (neither signals).
- **Spend gate:** `Player._spend(ability, busy, cost, log_line)`: dead or busy is a silent false; too little energy runs `_deny(ability)`; else `GameState.add_energy(-cost)`, one `Log.info("combat", log_line)`, true. The log line now precedes raising the shield / starting the volley (neither logs).

## As-built 2026-10-08 (Story 4.0)

Status update only; no design decision changed (GDD decision #37 pulled the player hull forward from Story 8.2).

- **Texture:** `Player/Sprite` uses `assets/sprites/player/playerShip1_coalition.png` (99×75 RGBA, nose toward −y, `.import` sidecar committed), a recolour of Kenney Space Shooter Redux `PNG/playerShip1_blue.png` (CC0 1.0, credited in `assets/CREDITS.md`). The placeholder `GradientTexture2D_hull` is gone. `modulate` / `self_modulate` stay at the default white, so the hull never goes HDR-bright under glow.
- **Tool:** `tools/recolor_player_ship.py <source PNG>` (stdlib only, deterministic; 8-bit RGBA non-interlaced input only, anything else exits non-zero) bakes the colour: per pixel in HSV, H becomes the `coalition` (#22E6FF) hue and S and V are scaled by coalition / body, where the body is the most common fully opaque RGB of the source (#36BBF5), clamped to 1; alpha is unchanged. Tests: `tools/test_recolor_player_ship.py` (`uv run python -m unittest tools/test_recolor_player_ship.py`).
- **Scale rule:** `Player._ready` → `_fit_hull(player.sprite_px)`: `Sprite.scale = Vector2.ONE × (sprite_px / max(texture width, height))`, the Sprite centred at (0, 0) and never rotated (0.9697 at the default 96, drawn 96×72.7). A null texture or `sprite_px <= 0` gives one `Log.warn("data", …)` and leaves the scale and the Muzzle as authored.
- **Muzzle rule:** `Muzzle.position = (0, −(texture height × scale) / 2)`, the nose tip (−36.36 at default tuning); lasers, missiles, the barrage and the muzzle flash follow it. The hurtbox (the `player.hurtbox_diameter_px` circle at the centre), the i-frame flicker, the hidden-on-death ship, the ShieldBubble and the MissileRing (both `z_index = 1`, the ring still clamped to `sprite_px / 2`) are unchanged.

## As-built 2026-10-08 (Story 4.1)

Status update only; no design decision changed.

- **Boot:** `scenes/boot/boot.tscn` + `boot.gd` (a plain `Node`) is `application/run/main_scene`. `_ready` declares `PauseArbiter.set_gameplay_mouse_mode(MOUSE_MODE_VISIBLE)`; then, in a debug build given `--stress` or `--bench=N`, it switches to the sandbox (`change_scene.call_deferred(SANDBOX_SCENE_PATH)`, the same `user_args` / `change_scene` seams and static `should_redirect_to_stress` as `level.gd`); otherwise it logs `[INFO][boot] Config loaded (…)` or `[ERROR][boot] Config failed to load: <load_error>` and calls `SceneRouter.goto_title()` either way. The `goto_title` call is deferred, because the main scene's `_ready` runs while the root is still adding it.
- **SceneRouter:** `TITLE_SCENE_PATH` = `res://scenes/title/title.tscn`; `MAIN_SCENE_SETTING` is gone. `goto_title()` sets `energy = 0`, `is_retry = false`, `current_level_id = ""` and changes to the title (Story 4.2 swaps the energy reset for the save restore). `start_level(id)` sets `current_level_id = id` and `is_retry = false`, keeps the energy and changes to `level.tscn`; while `Config.load_error` is set it logs `Log.error("scene", …)` and changes nothing. Every change still runs `PauseArbiter.clear()` and `Feedback.reset()` first.
- **Title:** `scenes/title/title.tscn` + `title.gd` (`class_name TitleScreen extends Control`, full rect, the shared theme). Children: `Logo` (Label, `DEFECTOR`), `Buttons` (VBoxContainer: `Play` `PLAY`, `Quit` `QUIT`, both `FOCUS_NONE`) and `Error` (Label, hidden). `_ready` declares the VISIBLE mouse mode and ends with `[INFO][scene] Title ready N ms after launch` (`Time.get_ticks_msec()`, the NFR2 evidence). Healthy config: layout from `ui.title` (the Logo label is `2 × logo_px` tall, centred on `logo_y`; the button stack is centred horizontally, `button_w × button_h` with `button_gap_px` as the VBox separation, top at `buttons_top_y`). Config error: no `Config` getter is called; the buttons are hidden and disabled and `Error` shows `CONFIG ERROR\n<load_error>` at the authored y 560 (the `.tscn` positions match the UX numbers). PLAY → `SceneRouter.start_level(FIRST_LEVEL_ID)` (`"1"`; Story 4.2 switches it to the highest unlocked level); QUIT → the injectable `quit_game` (default `get_tree().quit`, one `scene` INFO line). A `_leaving` flag ignores a second press.
- **Theme:** `Title/colors/logo` (`#22E6FF`), `logo_glow` (`#22E6FF` at 0.5 alpha, the Logo's font shadow with zero offset), `error` (`#FF1F4B`), `text` (`#E8F4FF`); `Title/constants/logo_glow_px` (16, the shadow outline); `Title/font_sizes/button` and `error` (28); `Title/styles/button_normal|button_hover|button_focus` reuse the `StyleBoxFlat_retry_button*` sub-resources. The title copies them onto its children in code, like `RetryPrompt._apply_theme`.
- **Levels:** placeholder `data/levels/level_1.json` ("Cargo Ambush"), `level_2.json` ("The Blockade") and `level_3.json` ("Siege of the Throne World"), with the `level_dev.json` key set, `convoy` false, and two short Wasp-only waves each (`grid_3x2` / `grid_4x2` / `grid_5x2`, `wave_start` / `wave_clear` waits). Epic 7 replaces them (decision F12).
- **Tuning:** `ui.title` (`logo_y` 300, `logo_px` 120, `button_w` 400, `button_h` 72, `button_gap_px` 24, `buttons_top_y` 560).
- **Tests:** `tests/unit/test_boot.gd` and `test_title.gd` (new); `test_scene_router.gd`, `test_retry_prompt.gd`, `test_project_settings.gd` and `tests/data/test_data_files.gd` updated.

## As-built 2026-10-08 (Story 4.2)

Status update only; no design decision changed (FR58, FR14, FR56, decision F13, retro F1).

- **SaveManager:** `autoloads/save_manager.gd`, autoloaded between `GameState` and `PauseArbiter`, no `class_name`. `SAVE_VERSION = 1`, `DEFAULT_SAVE_PATH = "user://save.cfg"`, `var save_path`. `load_progress()` returns `{"highest_unlocked_level", "energy"}`: a missing file gives (1, 0) with an INFO `save` line; a corrupt file (any `ConfigFile.load` error other than file-not-found), a missing, non-int or unknown `save_version`, or a missing, non-int, `highest < 1` or `energy < 0` value gives (1, 0) with a WARN `save` line. It never calls a `Config` getter. `save()` writes `[progress] save_version, highest_unlocked_level, energy` from `GameState`, logs INFO, or logs ERROR and returns false on a failed write. No file I/O in `_ready`.
- **GameState:** `highest_unlocked_level` (1), `all_levels_unlocked` (false; F7, memory only, never saved and not reset by `goto_title`), `is_level_unlocked(n)` (`all_levels_unlocked or n <= highest_unlocked_level`, for Story 4.3).
- **SceneRouter:** `goto_title()` restores `energy` and `highest_unlocked_level` from `SaveManager.load_progress()`; while `Config.load_error` is empty it clamps them into 1..`progression.level_count` and 0..`GameState.max_energy()`. `complete_level(n)`: ids outside 1..`level_count` (the dev level is 0) only log `[INFO][scene] Level n cleared: not a campaign level; no save, no scene change`; a campaign level sets `highest_unlocked_level = max(current, min(n + 1, level_count))`, calls `SaveManager.save()`, then `start_level(str(n + 1))` (energy carried) or, after the last level, `goto_title()` (Epic 7 replaces this with the end screen). A failed write doesn't stop the transition. Nothing else saves (not `goto_title`, `start_level`, `restart_level`, quit or F7).
- **Level:** `level.gd` connects `Events.level_cleared` → `SceneRouter.complete_level(id)` in `_ready` after the stress redirect. The LEVEL CLEAR banner still shows, for at most a frame on campaign levels.
- **WaveDirector (retro F1):** `_failed`, set by `Events.level_failed` and reset by `start_level` / `debug_skip_to_boss`; `_try_clear` and `_finish_level` return early while it is set, so a dead attempt never emits `wave_cleared` / `level_cleared`. Since DW-54 (decision #39) `_on_enemy_resolved`, `_subtract` and `_check_stall` also return while it is set (no resolve, no `wave_progress_changed`, no progress triggers, no stall net) and `debug_resolve_wave` logs INFO `F3: attempt failed; nothing to resolve`; a `level_failed` after `level_cleared` doesn't set it. Debug-only exception: F6 (`debug_skip_to_boss`) reopens the attempt (resets `_failed` / `_level_done`); the Player's death or safe state is not reset.
- **Title:** PLAY → `SceneRouter.start_level(str(GameState.highest_unlocked_level))`; `FIRST_LEVEL_ID` is gone. F7 doesn't change PLAY.
- **DebugTools:** F7 (`debug_unlock_all`, debug builds only) → `unlock_all()`.
- **Tuning:** top-level `progression.level_count` (3).
- **Tests:** `tests/unit/test_save_manager.gd` (new); `test_scene_router.gd`, `test_level.gd`, `test_wave_director.gd`, `test_title.gd`, `test_debug_tools.gd`, `test_game_state.gd`, `test_boot.gd`, `test_retry_prompt.gd`, `test_project_settings.gd` and `test_config.gd` updated. Every test that can reach `goto_title`, `complete_level` or `SaveManager` points `SaveManager.save_path` at its own `user://test_*.cfg` and deletes it afterwards, so the suite never reads or writes the real save.

## As-built 2026-10-08 (Story 4.3)

Status update only; no design decision changed (FR56).

- **SceneRouter:** `LEVEL_SELECT_SCENE_PATH` = `res://scenes/title/level_select.tscn`; `goto_level_select()` goes through `_change_to` (pause clear, `Feedback.reset`, one INFO `scene` line), touches no `GameState` field and writes no save. The energy a level starts with from Level Select is therefore the value `goto_title()` restored from the save (F13); BACK uses `goto_title()`, which re-restores the same values.
- **Title:** a `LevelSelect` button (`LEVEL SELECT`) between `Play` and `Quit` (QUIT now at y 752; the `Buttons` stack is 560..824), styled and guarded like the others (shared `_leaving`, hidden and disabled on a config error). It calls `SceneRouter.goto_level_select()`.
- **Level Select:** `scenes/title/level_select.tscn` + `level_select.gd` (`class_name LevelSelectScreen extends Control`, full rect, the shared theme). `_ready` declares the VISIBLE mouse mode and logs `[INFO][scene] Level select ready (N levels, M unlocked)`. Healthy config: one `Button` `Card<n>` (`FOCUS_NONE`) per id 1..`progression.level_count`, built in code under the authored `Cards` Control, with `MOUSE_FILTER_IGNORE` children `Thumbnail` (a `thumbnail`-coloured `ColorRect` placeholder: every level's `background` is null until Epic 7), `Number` (`LEVEL <n>`), `Name` (the uppercased `name` from `Config.level(str(n))`, empty if the file fails to load) and `Locked` (`LOCKED`, visible only when locked). Unlocked = `GameState.is_level_unlocked(n)` (F7 counts); a locked card is `disabled` with `modulate.a = ui.level_select.locked_alpha`. The row is centred on `Playfield.SIZE.x` (static `cards_rect(canvas_w, card, gap, top_y, count)`), so the default cards sit at x 192, 720, 1248, top 360. An unlocked card → `SceneRouter.start_level(str(n))`; `Back` (`BACK`, 240×64 at (32, 984)) → `SceneRouter.goto_title()`; a `_leaving` flag ignores every later press. Config error: no cards, no `Config` getter, BACK at its authored position.
- **Theme:** `LevelSelect/colors/text` (`#E8F4FF`), `muted` (`#93A7C2`, the LOCKED label), `thumbnail` (`#2B3348`); `LevelSelect/font_sizes/button` and `name` (28), `number` (20); `LevelSelect/styles/button_normal|button_hover|button_focus` reuse the `StyleBoxFlat_retry_button*` sub-resources (a disabled card uses `button_normal`). Copied onto the children in code.
- **Tuning:** `ui.level_select` (`card_w` 480, `card_h` 280, `card_gap_px` 48, `cards_top_y` 360, `back_x` 32, `back_y` 984, `back_w` 240, `back_h` 64, `locked_alpha` 0.4).
- **Tests:** `tests/unit/test_level_select.gd` (new); `test_title.gd` and `test_scene_router.gd` updated.

## As-built 2026-10-08 (Story 4.4)

Status update only; no design decision changed (FR57, FR8).

- **PauseArbiter:** `has_reason(reason) -> bool` (`_reasons.has`, no allocation). Nothing else changed.
- **PauseMenu:** `ui/menus/pause_menu.tscn` + `pause_menu.gd` (`class_name PauseMenu extends Control`, full rect, the shared theme, `PROCESS_MODE_ALWAYS`, hidden at start, `MOUSE_FILTER_IGNORE` while hidden and `MOUSE_FILTER_STOP` while shown), instanced as `Overlay/PauseMenu` in `level.tscn` between `RetryPrompt` and `DebugTools` (not in the sandbox). Children: `Dim` (full-rect ColorRect), `Panel` (holding the `Heading` Label, `PAUSED`) and the buttons `Resume` (`RESUME`), `Restart` (`RESTART LEVEL`) and `Quit` (`QUIT TO TITLE`), all `FOCUS_NONE`. `_unhandled_input` reacts only to `event.is_action_pressed(&"pause")` (echoes ignored), marks it handled and toggles: `open()` (no-op while shown, while leaving, or while `death` / `final_choice` is active; a `story` pause doesn't block it) pushes `&"menu"`, shows the menu and logs `[INFO][scene] Pause menu opened`; `resume()` (RESUME or Esc while shown; no-op when hidden or leaving) pops only `&"menu"`, hides it and logs `Pause menu closed`. Over a story pause the tree therefore stays paused and `resumed` doesn't fire. RESTART → `SceneRouter.restart_level()`, QUIT → `SceneRouter.goto_title()`; the menu stays visible until the scene changes and a `_leaving` flag ignores every later press and Esc. The HUD freeze, the shake freeze, the visible cursor and `Player._on_resumed`'s warp are the existing mechanisms, unchanged.
- **Layout:** static `panel_rect(canvas, panel_w, padding, heading, heading_gap, button, gap, count)` (centred on `Playfield.SIZE`, height padding + heading + heading gap + 3 buttons + 2 gaps + padding) and `button_rects(panel, …)` (centred horizontally, first top at panel top + padding + heading + heading gap). Default: panel (700, 324, 520, 432), heading at y 364, buttons 400×72 at x 760, y 452 / 548 / 644.
- **Theme:** `PauseMenu/colors/dim` (black at 0.6), `text` (`#E8F4FF`); `PauseMenu/font_sizes/heading` (48) and `button` (28); `PauseMenu/styles/panel` and `button_normal` reuse `StyleBoxFlat_retry_button`, `button_hover|button_focus` the matching `StyleBoxFlat_retry_button*` boxes. Copied onto the children in code.
- **Tuning:** `ui.pause_menu` (`panel_w` 520, `panel_padding_px` 40, `heading_px` 48, `heading_gap_px` 40, `button_w` 400, `button_h` 72, `button_gap_px` 24). The padding and heading gap are layout defaults (the UX table gives neither).
- **Tests:** `tests/unit/test_pause_menu.gd` (new); `test_pause_arbiter.gd` and `test_level.gd` updated.

## As-built 2026-10-08 (Story 4.5)

Status update only; no design decision changed (FR59).

- **SceneRouter:** owns the F11 window toggle (the `PROCESS_MODE_ALWAYS` autoload present under every scene, so it works in boot, title, level select, level and sandbox, while paused, in debug and release). `_unhandled_input` reacts only to `event.is_action_pressed(&"toggle_fullscreen")` (echoes ignored), calls `toggle_window_mode()` and marks the event handled. `toggle_window_mode()` reads the injectable `get_window_mode` (default `DisplayServer.window_get_mode`), sets `toggled_window_mode(current)` through the injectable `set_window_mode` (default `DisplayServer.window_set_mode`) and logs `[INFO][scene] Window mode: fullscreen|windowed`. Static `toggled_window_mode(mode)`: `FULLSCREEN` / `EXCLUSIVE_FULLSCREEN` → `WINDOWED`, anything else → `FULLSCREEN` (borderless; never exclusive). `default_get_window_mode()` / `default_set_window_mode()` return the real callables for tests to restore. Nothing is persisted (no `user://` write, no `SaveManager` call, no `ProjectSettings.save`): a fresh launch is always fullscreen.
- **project.godot:** `display/window/size/window_width_override=1280`, `window_height_override=720` (the windowed size, a layout default so the window fits a 1080p screen with its title bar; fullscreen ignores it). `mode=3`, the 1920×1080 viewport and the `canvas_items` / `keep` stretch are unchanged, which is what letterboxes a non-16:9 window. The cursor confinement is the existing `Player.step_lock` warp in viewport coordinates (a mouse in a letterbox bar arrives outside the playfield and is clamped and warped back), unchanged.
- **Tests:** `tests/unit/test_window_mode.gd` (new: the toggle table, recorders, a real F11 key through the viewport, paused, echo, other keys, not persisted, the defaults, and a headless 2560×1600 root keeping the 1920×1080 canvas at a uniform scale); `test_project_settings.gd` and `test_player_movement.gd` (letterbox-bar mouse) updated.


## As-built 2026-10-08 (Story 5.1)

Status update; no GDD or UX decision changed (FR37, FR38 story mode, FR39, FR8 comms advance). Two Comms Channel rules were refined here: the unknown-id `finished` is emitted deferred (same frame), and advancing acts on the mouse release (see [Comms Channel](#2-comms-channel)).

- **Dialogue data:** `data/dialogue/<scene>.json`, shape `{ "sequences": { "<id>": { "mode": "story"|"combat", "lines": [ { "speaker", "text" } ] } } }`. `data/dialogue/dev.json` holds the placeholder story sequence `dev_comms_check` (4 lines: Tarek and Isolde with a portrait, Vale without; one 195-character line for the wrap check). Story 5.7 writes the real script.
- **DialogueValidator:** `systems/comms/dialogue_validator.gd` (static, like `LevelValidator`). `SPEAKERS` (`vale, isolde, tarek, ryn, system`), `MODES` (`story, combat`). `validate(data, path, story_max_chars)` and `validate_sequence(id, seq, path, story_max_chars)` return one message per problem, each naming the file and the sequence id: `sequences` missing or not an object, a sequence that isn't an object, an unknown `mode`, `lines` missing / not an array / empty, a line that isn't an object, an unknown `speaker`, `text` missing / not a String / empty after `strip_edges()`, story `text` longer than `story_max_chars` (a negative limit skips that check), and an empty or blank sequence id. Combat limits are Story 5.2's.
- **Config:** `DEFAULT_DIALOGUE_DIR` (`res://data/dialogue/`); `load_data(tuning_path, flags_path, dialogue_dir := DEFAULT_DIALOGUE_DIR)` loads every `*.json` in the dir (sorted by name) after tuning, with the limit from `comms.story_line_max_chars` (when that key is missing the length isn't checked; an error is logged only if tuning itself loaded). A missing, unparsable or non-object file is `Log.error`ed and skipped; every validator problem is `Log.error`ed (`data`) and a sequence with any problem is left out; a duplicate id across files is `Log.error`ed and the first wins; a missing dir logs an error and leaves dialogue empty. Dialogue never sets `load_error`. `reload()` re-reads the dir (see Configuration). Getters: `sequence(id)` (deep copy, `{}` for an unknown id with no log), `has_sequence(id)`, `dialogue_is_story(id)`. The load summary adds `[INFO][data] Loaded N dialogue sequences from <dir>`; the existing summary line is unchanged.
- **CommsChannel:** `systems/comms/comms_channel.gd` (`class_name CommsChannel extends Node`, `PROCESS_MODE_ALWAYS`, `@export var panel: CommsPanel`), `Comms/CommsChannel` in `level.tscn` wired to `Comms/CommsPanel`. It connects `Events.comms_sequence_requested`. Unknown id: `Log.error("comms", "Unknown comms sequence '<id>'")` and a deferred `finished(id)`. Combat id: `Log.warn` and a deferred `finished`, nothing shown, no pause (Story 5.2 builds it). Story id while idle: `PauseArbiter.push(&"story")`, `Audio.play_sfx(&"comms_open", 0.0)`, `panel.open()`, line 0 and `[INFO][comms] Story sequence '<id>' started (<n> lines)`; while a story plays the id is queued FIFO and never dropped. Input: see the advance-on-release rule in [Comms Channel](#2-comms-channel). Advance: complete a typing line, else the next line; after the last line it logs `Story sequence '<id>' finished` and, with a queued story, emits `finished(id)` (still showing, so a story a listener requests queues behind it) and starts the next one without unpausing (with `comms_open` again); otherwise it closes the panel and pops `story` **before** emitting `finished(id)`. Read accessors `current_sequence()` (`&""` when idle), `is_showing()`, `line_index()`, `queued()`.
- **CommsPanel:** `systems/comms/comms_panel.tscn` + `.gd` (`class_name CommsPanel extends Control`, full rect, the shared theme, `PROCESS_MODE_ALWAYS`, hidden at start, `MOUSE_FILTER_IGNORE` on it and every child), `Comms/CommsPanel` in `level.tscn`. Children: `Dim` (ColorRect), `Panel`, and inside the Panel `Portrait` (a Panel frame plus a centred `Initial` Label in the accent: the placeholder until Epic 8), `Name`, `Text` (autowrap word-smart, clip, `VC_CHARS_AFTER_SHAPING`) and `Cue` (`click to continue ▸`, `muted`, right- and bottom-aligned). A view only: `open()`, `close()` (also kills the tween), `show_line(speaker, text)` (uppercase name from `comms.speakers` in the accent, portrait only when `portrait` is true, text block re-laid out for either variant, typed from 0), `is_typing()`, `complete_line()`. The typewriter tweens `visible_characters` 0 to count over `count / chars_per_s` s on the panel with `TWEEN_PAUSE_PROCESS`. Static `layout(x, y, w, h, padding, portrait_px, portrait_gap, name_h, name_gap, cue_h, with_portrait)` returns the panel rect (canvas) and the portrait, name, text and cue rects (panel-local): default panel (410, 300, 1100, 300), portrait (32, 32, 200, 200), text (256, 76, 812 × 168) with a portrait and (32, 76, 1036 × 168) without, cue the bottom 24 px of the block.
- **Theme:** `CommsPanel/colors/dim` (black 0.6), `text` (#E8F4FF), `muted` (#93A7C2) and one per speaker (`isolde` #FF6AE3, `tarek` #3DF2FF, `ryn` #7CFFB2, `vale` #E8F4FF, `system` #93A7C2); `CommsPanel/font_sizes/text` 30, `name` 28, `cue` 20; `CommsPanel/constants/line_spacing` 0 (copied onto `Text`, so four 30 px lines fit the 168 px block); `CommsPanel/styles/panel` is a new `StyleBoxFlat_comms_panel` (surfaceAlt fill, 1 px #2A3B5C border, 4 px corners). The portrait frame (a copy of that box with the border in the speaker accent) is the only per-node style override.
- **Tuning:** `comms.story_line_max_chars` (200), `comms.speakers` (`name`, `portrait` per speaker id: Vale and system have no portrait), `ui.comms_panel` (`x` 410, `y` 300, `w` 1100, `h` 300, `padding_px` 32, `portrait_px` 200, `portrait_gap_px` 24, `name_h_px` 36, `name_gap_px` 8, `cue_h_px` 24).
- **Audio:** `comms_open` registered in `Audio.SFX`: `assets/audio/sfx/sfx_comms_open.wav` (0.25 s, two rising sine chirps plus band-limited static) from `tools/gen_placeholder_sfx.py` (`COMMS_OPEN_SEED = 5101`, so the other WAVs stay byte-identical); credited in `assets/CREDITS.md`.
- **One dim:** `PauseMenu.open()` hides its own `Dim` while `PauseArbiter.has_reason(&"story")` and shows it otherwise.
- **Debug:** `-- --comms=<id>` (debug builds) requests that sequence after the level starts (see Debug Tools).
- **Tests:** `tests/unit/test_dialogue_validator.gd`, `test_comms_panel.gd` and `test_comms_channel.gd` (new; fixtures in `tests/fixtures/dialogue/`); `test_config.gd`, `test_level.gd` (including the acceptance test that clicks through `dev_comms_check` with `Input.parse_input_event` and counts zero laser bolts), `test_pause_menu.gd`, `test_debug_args.gd`, `test_audio.gd` and `tests/data/test_data_files.gd` updated. Under GUT the root viewport reports a mouse button event as handled even when no node consumed it, so the channel tests detect consumption with a probe node rather than `is_input_handled()`.

## As-built 2026-10-08 (Story 5.2)

Status update (FR38 combat mode, R9). No GDD or UX decision changed; three rules the docs left open were decided here, all following the GDD rule that every scripted beat fires in every playthrough: a combat request while a story shows is **queued**, not dropped; a preempt drops only the **playing** combat line (queued ones survive); and a combat line dropped from the full queue still emits `finished`.

- **Data:** `comms.combat_line_max_chars` (50), `comms.box_slide_in_s` (0.15), `comms.box_fade_out_s` (0.2); the existing `combat_line_min_s` (2.0), `combat_line_extra_s` (1.2) (as first built; the 2026-10-09 follow-up below changes these and the box metrics) and `combat_queue_max` (3) are used. `ui.comms_box` (`x` 32, `y` 24, `w` 560, `h` 96, `edge_px` 4, `padding_px` 6, `portrait_px` 72, `portrait_gap_px` 12, `name_h_px` 28, `text_line_h_px` 28, `text_lines` 2). `data/dialogue/dev.json` adds `dev_combat_check` (Isolde) and `dev_combat_vale` (Vale, no-portrait variant), each one line under 50 characters, so `-- --comms=<id>` shows the box.
- **DialogueValidator:** `validate(data, path, story_max_chars, combat_max_chars)` and `validate_sequence(id, seq, path, story_max_chars, combat_max_chars)`; a combat sequence must have exactly 1 line (`combat sequence has N lines, exactly 1 allowed`) of at most `combat_max_chars` characters (`combat line has N characters, more than M`; negative skips it). `static is_interruption(seq)`: combat mode and no line has `cut_off_at` (the Tarek cut-off, Story 5.4, doesn't count against the per-level cap). `Config._load_dialogue` passes `comms.combat_line_max_chars` (missing key: one `Log.error` when tuning loaded, then -1, like the story key).
- **CommsBox:** `systems/comms/comms_box.tscn` + `.gd` (`class_name CommsBox extends Control`, full rect, the shared theme, process mode inherited so it is pausable in the level, hidden at start, `MOUSE_FILTER_IGNORE` on it and every child). Children: `Box` (Panel) with `Edge` (ColorRect in the speaker accent), `Portrait` (Panel frame + centred `Initial` Label, the placeholder until Epic 8), `Name` and `Text` (autowrap word-smart, clip, `VC_CHARS_AFTER_SHAPING`). No dim, no cue. A view only, called by `CommsChannel`: `show_line(speaker, text)` (uppercase name from `comms.speakers`, accent from `CommsPanel/colors/<speaker>`, portrait only when `portrait` is true, re-laid out, full alpha, `Box` slides from x = -w to x over `box_slide_in_s`, text typed at `chars_per_s`), `dismiss()` (fades `modulate.a` to 0 over `box_fade_out_s`, then hides), `hide_now()` (kills every tween, hides), `is_typing()`, `is_open()` (visible and not fading). Every tween is created on the box with the default pause mode, so it freezes under any pause. Static `layout(x, y, w, h, edge, padding, portrait_px, portrait_gap, name_h, line_h, lines, with_portrait)`: inset = (h - portrait_px) / 2; edge (0, 0, edge, h), portrait (edge + inset, inset, 72, 72), name (left, padding, bw, name_h), text (left, padding + name_h, bw, line_h × lines). Default: box (32, 24, 560, 96), text (100, 34, 448 × 56) with a portrait and (16, 34, 532 × 56) without.
- **Theme:** `CommsBox/font_sizes/text` 24, `name` 28, `CommsBox/fonts/text` (a `FontVariation` with no base font, so it uses the default font, and `spacing_top` / `spacing_bottom` -3, trimming the fallback font's 34 px line box at 24 px to the UX 28 px line height) with `CommsBox/constants/line_spacing` 0, so two full lines fill the 56 px text rect (a test pins the 28 px pitch), `CommsBox/styles/panel` = the existing `StyleBoxFlat_comms_panel`. The portrait frame is the only per-node style override; the `Edge` colour is set on the ColorRect. Epic 8's font changes the metrics.
- **CommsChannel:** `@export var box: CommsBox`, wired in `level.tscn` to `Comms/CommsBox` (placed before `CommsPanel`, so the panel draws on top). Combat request: when a combat plays or a story shows it is appended to the combat queue (DEBUG); past `combat_queue_max` the oldest is popped, logged at DEBUG (`Combat queue full (max N): dropped '<id>'`) and finished deferred. Otherwise `box.show_line` for line 0, the line timer set to `static combat_line_s(chars, chars_per_s, min_s, extra_s)` = `max(min_s, chars / chars_per_s + extra_s)` (`max(min_s, extra_s)` without a typing speed), `[INFO][comms] Combat sequence '<id>' started`; no pause, no SFX (as first built; since the 2026-10-09 follow-up each combat line starts with a key-in cue, see below). `step_combat(delta)` (from `_process`, only while the tree isn't paused) counts the timer down (1e-6 s slack); at the end: next line, or `box.dismiss()`, `Combat sequence '<id>' finished`, `finished(id)`, then the next queued combat if no story shows and none started. A story request while a combat plays: `box.hide_now()`, `[INFO][comms] Combat sequence '<id>' preempted by story '<story>'`, deferred `finished(combat)`, then the story exactly as in 5.1 (combat queue kept). A story start also hides a box that is still fading. After a story ends with an empty story queue, the next queued combat starts. Input is unchanged (`_unhandled_input` acts only while a story shows), so clicks during a combat line are never consumed. Accessors `current_combat()`, `is_playing_combat()`, `combat_queued()` (copy).
- **Tests:** `tests/unit/test_comms_box.gd` (new: tuning, layout, theme, mouse transparency, accent / edge / portrait, slide, typewriter, pause freeze, fade, hide_now, 50-character two-line fit in both variants and the 28 px line pitch); `test_comms_channel.gd` (the combat placeholder test replaced by every I/O row: timing, pause freeze, ignored clicks, preempt, queue drop, combat behind a story, queue surviving a preempt), `test_dialogue_validator.gd`, `test_config.gd` (+ `tests/fixtures/dialogue/bad/e_combat.json`), `test_level.gd` (box wiring and the acceptance test: fire held, combat line, no pause, bolts keep spawning, one `finished`) and `tests/data/test_data_files.gd` (every combat sequence 1 line ≤ 50 characters, at most 2 interruptions per level JSON with an inline self-check of the counter, positive tuning) updated; `tests/fixtures/dialogue/channel/channel.json` gains `combat_b`..`combat_e`.
- **Follow-up 2026-10-09 (operator check; GDD decision #41, UX decision #23):** `comms.combat_line_min_s` 5.0, `combat_line_extra_s` 3.0, `box_fade_out_s` 0.6 (the fade is now `TRANS_SINE` / `EASE_OUT`). `ui.comms_box.padding_px` 4 and `text_line_h_px` 30; `CommsBox/font_sizes/text` 26 (the -3/-3 FontVariation trim is unchanged and gives the 30 px pitch), so the text block is (100, 32, 448 × 60) with a portrait and (16, 32, 532 × 60) without. `CommsChannel._show_combat_line` plays `static combat_cue(box_visible, previous_speaker, speaker)` (0.0 pitch jitter) before `box.show_line`: `comms_chatter` while the box is hidden, else `comms_handover` for a new speaker and `comms_click` for the same one. The previous speaker is `box.current_speaker()`, kept while the box fades. `comms_chatter` (generated, seed 5201, peak 0.55) is added to `Audio.SFX`. *Revised the same day (GDD decision #42, UX decision #24):* `comms_chatter` is removed and a fresh box plays `comms_open_nobeep` (`comms_open` without the beep, same seed and level) at `comms.combat_open_db` (-4); handover / click play at `comms.combat_line_cue_db` (-4). `CommsBox/font_sizes/name` 24 and `text` 22, `CommsPanel/font_sizes/text` 28; `ui.comms_box.name_h_px` 32 and `text_line_h_px` 25, so the text block is (100, 36, 448 × 50) with a portrait and (16, 36, 532 × 50) without. The debug `--comms=` takes a comma-separated list (`DebugArgs.parse` returns `comms: Array[StringName]`, `Level.debug_comms_ids`), and each id is requested in order. `dev.json` adds a second Tarek line to `dev_comms_check` and a `dev_combat_isolde_2` line, so `--comms=dev_combat_check,dev_combat_isolde_2,dev_combat_vale` checks key-in, then click, then handover.

## As-built 2026-10-08 (Story 5.3)

Status update (FR28, FR39, FR61). No GDD or UX decision changed. Decisions where the docs are silent (record-only): a combat-mode `intro_sequence` / `outro_sequence` doesn't block, like a combat `comms` action; the outro also plays on a retry (only the briefing is skipped); the level-root `music` key stays unread (no story AC plays it, so levels start music with a `music` action, e.g. on `wave_start`; Story 8.1 or Epic 7 can wire it); a missing music stream stops the current track, so "stays silent" holds after a switch; two chains waiting on the same story id are both released by its single `finished` (ids are per beat).

- **Data:** `tuning.json` gains the `audio` section (`music_fade_out_s` 0.5). No level JSON gained comms, music or an intro/outro (Epic 7 places them; an intro in `level_dev.json` would pause every level-scene test).
- **Audio:** see [Audio Architecture](#audio-architecture). `Music` is an `AudioStreamPlayer` child on the `Music` bus; the fade is a tween of `volume_db` to -80 on the `PROCESS_MODE_ALWAYS` autoload, then stop and the base volume back. `current_music()` is `&""` from the `stop_music` call on; with nothing playing `stop_music` only clears the id. Logs: `[INFO][audio] Music '<id>' playing`, `Music '<id>' stopping (<s> s fade)`, `[WARN][audio] no music stream for '<id>'; music stays silent` (once per id).
- **WaveDirector:** `signal _sequence_done(sequence_id)` relays `Events.comms_sequence_finished` (connected in `_ready`, which also counts finishes per id). `_request_sequence(id)` takes the id's finished count, emits `Events.comms_sequence_requested(id)` and returns the count when `Config.dialogue_is_story(id)`, else -1; the caller loops `while count == before: await _sequence_done`, so a synchronous finish during the request never hangs it. `comms` logs `[INFO][beat] Level <n> wave <w>: comms '<id>'`; `story_event` emits `Events.story_event_requested` and logs `... story event '<name>'`; `music` calls `Audio.apply_music_action`. `wait` (> 0) runs a one-shot `PROCESS_MODE_PAUSABLE` `Timer` child, freed after it fires (0 continues at once). `start_level` bumps `_serial`, resets the wave index (wave 0 = "not started") and plays the intro (INFO `intro '<id>'`) or, on a retry, logs the skip and starts wave 1 at once; callers never await it. `_finish_level` plays the outro (INFO `outro '<id>'`) before `level_cleared`; a changed serial or `_failed` after the await emits nothing. The `_try_clear` gap timer is unchanged.
- **LevelValidator:** `MUSIC_ACTIONS` (`stop`, `combat`, `boss`); another `music` value is a problem (`must be one of stop, combat, boss`). Root `intro_sequence` / `outro_sequence` must be absent, `null` or a non-empty string.
- **Tests:** `test_wave_director.gd` (every Story 5.3 I/O row: story blocks, combat and unknown don't, another id's finish, a synchronous finish, story event, music play/switch/fade, missing stream, clear waits for the chain, intro, intro on retry, combat intro, restart and F6 during the intro, outro, outro on retry, death during the outro, death reload during a story wait and during a `wait`, the pausable child Timer; the F3 test now reads the comms INFO lines), `test_audio.gd` (the Music player, play/switch/same id, fade over the tuning time, play during a fade, zero fade, missing stream), `test_level_validator.gd` (music values, intro/outro shape), `test_config.gd` (the `audio` section), `test_level.gd` (the acceptance test: an inline level's wave-1 chain `[comms dev_comms_check, story_event dev_evt]` pauses with `story` through the real channel and fires `dev_evt` only after the click-through lifts the pause) and `tests/data/test_data_files.gd` (every sequence a level references exists, with a self-check of the collector; `audio.music_fade_out_s` is 0.5).

## As-built 2026-10-08 (Story 5.4)

Status update (FR40). No GDD or UX decision changed. Decisions where the docs are silent (record-only): a cut-off is **combat-only** (the architecture example, the UX "the box hides" and `is_interruption` all put it in the interruption box; a story-mode `cut_off_at` is a validator problem); `until_wave_clear` means the wave the cut-off happened in, so if that wave clears before the cut-off moment (F3, or a wave ending during the ~0.9 s of typing) no silence starts; a story that preempts the line before its cut-off moment drops the effects with the line (every combat line is treated alike, so Epic 7 data must not request a story in the same moment as a cut-off); `shake` names a tier's shake only (no hit-stop or explosion: a comms effect, not an impact); the box hides at once rather than fading (with the static burst it reads as a dead channel).

- **Data:** cut-off line keys (combat sequences only) `"cut_off_at": <int>` and optional `"after": { "silence": "until_wave_clear", "shake": "<ImpactTier name>", "sfx": "<sfx id>", "music": "stop"|"combat"|"boss" }`, every `after` key optional. The existing `comms.cutoff_hide_s` (0.6) is read; no new tuning key. `data/dialogue/dev.json` adds `dev_tarek_cutoff` (Tarek, `General, get behind me, I've got you cov—`, `cut_off_at` 39, the full `after`); `level_dev.json` wave 2 gains `{ "when": "progress", "at": 0.25, "actions": [ { "comms": "dev_tarek_cutoff" } ] }` (the reinforcements trigger is unchanged). Under F3 on that wave the clear waits for the reinforcements chain's `wait 1.0`, so the cut-off moment (0.87 s) comes first: silence turns on, then `wave_cleared` lifts it.
- **DialogueValidator:** `AFTER_KEY` and the `AFTER_*` key constants, `SILENCE_UNTIL_WAVE_CLEAR`. One problem each for: `cut_off_at` in a story sequence (`cut_off_at is only allowed in combat sequences`); `cut_off_at` not a whole number (a JSON float with no fraction is whole) or outside 1..text length - 1; `after` without `cut_off_at` or not an object; an unknown `after` key; `silence` other than `until_wave_clear`; `shake` not in `ImpactTier.NAMES`; `sfx` not a non-empty string; `music` not in `LevelValidator.MUSIC_ACTIONS`.
- **Feedback:** `shake_tier(tier)` (see [Impact Feedback Tiers](#3-impact-feedback-tiers)); `impact` shares its camera guard (`_shake(row)`).
- **CommsBox:** `show_line(speaker, text, cut_off_at := -1)`: with `cut_off_at >= 0` it types only to `cut_off_at` characters over `cut_off_at / chars_per_s` and keeps that count when the tween ends (never -1). `cut_off(chars)` kills the type tween and sets `visible_characters = chars`. Existing callers are unchanged.
- **CommsChannel:** `enum CutPhase { NONE, TYPING, HOLD }`, accessors `is_silenced()` and `cut_phase()`. A combat line with `cut_off_at` sets its timer to `cut_off_at / chars_per_s` s (0 without a typing speed). When it runs out (`step_combat`, game time) the channel calls `box.cut_off(cut_off_at)`, logs `[INFO][comms] Combat sequence '<id>' cut off at <n> characters` and runs `after` in order (`Audio.play_sfx(sfx, 0.0)`, `Feedback.shake_tier(ImpactTier.from_name(shake))`, `Audio.apply_music_action(music)`, silence), then holds `comms.cutoff_hide_s` more (overshoot carried) and calls `box.hide_now()`, logs `finished` and emits it as before. Silence on: `[INFO][comms] Comms silenced until the wave clears (cut-off '<id>')`, each queued combat dropped (`[DEBUG][comms] Comms silenced: dropped queued combat sequence '<id>'`, deferred `finished`). While silenced a combat request is dropped (`[DEBUG][comms] Comms silenced: dropped combat sequence '<id>'`, deferred `finished`); story requests play as before. `Events.wave_cleared` (connected in `_ready`, disconnected in `_exit_tree`) lifts it (`[INFO][comms] Comms silence lifted (wave cleared)`) and, while the cut-off line still types, marks its silence void (`[DEBUG][comms] Silence from '<id>' skipped: its wave already cleared`). `_clear_combat` resets the cut-off state, so a preempt before the cut-off moment runs no effects.
- **Audio:** `comms_static` registered in `Audio.SFX`: `assets/audio/sfx/sfx_comms_static.wav` (0.4 s crackly noise with stuttering dropouts and a 50 Hz hum) from `tools/gen_placeholder_sfx.py` (`COMMS_STATIC_SEED = 5401`, so the other WAVs stay byte-identical); credited in `assets/CREDITS.md`.
- **Tests:** `test_dialogue_validator.gd` (valid cut-off lines and every bad-data row), `test_feedback.gd` (`shake_tier`: shake only, no shake for `small`, bad tier, no camera), `test_comms_box.gd` (typing to `cut_off_at` and staying there, `cut_off`, the default unchanged), `test_comms_channel.gd` (every Story 5.4 I/O row: the timeline, no `after`, silence drops combat, keeps story, clears on `wave_cleared`, flushes the queue, a wave clear before the cut-off moment, an early and a late preempt, the pause freeze; fixture `cut_a` / `cut_plain` in `tests/fixtures/dialogue/channel/channel.json`) and `test_level.gd` (the two acceptance tests: real kills on level_dev wave 2 to progress 0.25, and F3 on wave 2).

## As-built 2026-10-08 (Story 5.5)

Status update (FR41, R15). No GDD or UX decision changed. Record-only decisions: the opening id (`opening_main`) and the level it opens (`"1"`) are `SceneRouter` constants, scene-flow wiring like the scene paths rather than tuning; the static space background (AC, FR41, UX "Opening story scene") is the DESIGN `background` token (`#05070F`, "Space backdrop base") shown as the project clear colour, as on the title, and backdrop art arrives with Epic 8; `goto_story` keeps the energy (fresh-attempt semantics, like `start_level`).

- **SceneRouter:** `STORY_SCENE_PATH` (`res://scenes/story/story.tscn`), `OPENING_SEQUENCE` (`&"opening_main"`), `OPENING_LEVEL_ID` (`"1"`). `goto_story(id, next_level)` stores the pending id and level, clears `is_retry`, keeps the energy and changes to the story scene through `_change_to` (`[INFO][scene] Story '<id>' before level <n>`); refused with `Log.error` while `Config.load_error` is set. Accessors `story_sequence()` (`&""` when none) and `story_next_level()` (0 when none). `finish_story()` clears the pending story and starts its level through the private `_load_level(id)` (set the id, clear `is_retry`, change to `level.tscn`), so it never reaches the opening check; with nothing pending it logs a warning and calls `goto_title()`. `start_level(id)`: after the load-error guard, id `"1"` calls `goto_story(OPENING_SEQUENCE, 1)`, every other id calls `_load_level`. `restart_level()` and `complete_level()` are unchanged (`complete_level` never starts level 1). The title and Level Select are unchanged: both get the opening through `start_level`.
- **CommsPanel:** `@export var dim: bool = true`; `open()` sets `Dim.visible = dim`. `level.tscn` keeps the default.
- **Story scene:** `scenes/story/story.tscn` + `story.gd` (`class_name StoryScene extends Control`, full rect, `MOUSE_FILTER_IGNORE` so clicks reach the channel's `_unhandled_input`, the shared theme). Children: `Comms` (CanvasLayer 20) with `CommsChannel` (`PROCESS_MODE_ALWAYS`, `panel` / `box` wired), `CommsBox` and `CommsPanel` (`dim = false`), the same shape as `level.tscn`. No HUD, WaveDirector, PauseMenu or DebugTools, so Esc does nothing and there is no skip; no backdrop node: the static space background is the DESIGN `background` token (`#05070F`) shown as the project clear colour, as on the title (backdrop art arrives with Epic 8). `_ready` declares `MOUSE_MODE_VISIBLE`, reads `SceneRouter.story_sequence()`, connects `Events.comms_sequence_finished` (disconnected in `_exit_tree`) and emits `Events.comms_sequence_requested(id)`; the channel (whose `_ready` ran first) pushes `story`. A `finished` with that id (including the channel's deferred finish of an unknown id, so nothing soft-locks) calls `SceneRouter.finish_story()` once; other ids are ignored. With an empty pending id (scene run directly) it warns and calls `finish_story()`, which goes to the title. Accessor `sequence()`.
- **Data:** `data/dialogue/opening.json` with `opening_main` (story, 7 lines): Tarek hails the fighter and introduces himself, Vale states the defection, Tarek welcomes the General and briefs the convoy escort over two lines, Isolde's one cold line, Vale closes. Placeholder-quality but in voice; Story 5.7 can polish it (final text: see As-built Story 5.7).
- **Tests:** `test_scene_router.gd` (every router row: level 1 through the story, other levels direct, `goto_story` state and pauses, `finish_story` once and with nothing pending, retry of level 1, config error for `goto_story` and `start_level("1")`), `test_story_scene.gd` (new: the scene shape, plays with the story pause, panel on line 0, no dim and a visible cursor; click-through loads level 1 once; other ids ignored; unknown id; Esc; no pending id; the two acceptance tests from the title PLAY and Level Select card 1; a retry after the opening), `test_comms_panel.gd` (`dim` default and off), `tests/data/test_data_files.gd` (`opening_main`: in `opening.json`, story, 6-10 lines, only vale / tarek / isolde, one Isolde line, Tarek mentions the convoy), and `test_title.gd` / `test_level_select.gd` (level 1 now records the story path).

## As-built 2026-10-08 (Story 5.6)

Status update (FR42, FR43, FR61; SHOULD). No GDD or UX decision changed, and no `CommsChannel`, `WaveDirector`, `BeatTrigger` or `LevelValidator` behaviour changed: both beats are data on the Story 5.3 machinery. Record-only decisions: the beats live in a separate dev level, not `level_dev.json`, so no existing test meets a story pause; `--level` exists only so a human can play it (debug-only, like `--comms`); the dev reinforcements are Wasps because the Maul is Epic 6; the trigger timings follow the GDD L1 table (interruption at 0.25 in W3, surrender at 0.30 in W5). Placing the beats in `level_1/2/3.json` is Epic 7.

- **Data:** `data/dialogue/level_1.json` (`l1_w3_isolde_interrupt`, combat; `l1_w5_surrender`, story, one Isolde line `You're outnumbered, General. Come home.`, no `choice`), `level_2.json` (`l2_w3_isolde_interrupt`, combat) and `level_3.json` (`l3_w3_isolde_taunt`, combat): one Isolde line each, combat lines at most 50 characters, placeholder text in voice for Story 5.7 to polish (final text: see As-built Story 5.7). `data/levels/level_dev_isolde.json` (`id` 0, `Development: Isolde beats`, the `level_dev` key set): wave 1 is 8 Wasps (`grid_4x2`) with the interruption at 0.25 behind `isolde_interruptions`; wave 2 is 10 Wasps (`grid_5x2`) plus the `reinforcements` group (4 Wasps, `grid_4x1`) and the paired surrender triggers at 0.30. `flags.json` is unchanged (both flags already on).
- **DebugArgs / level.gd:** `LEVEL_PREFIX` (`--level=`), the `level` key and static `level.gd` `debug_level_id(debug_build, args) -> String` (see [Debug Tools](#debug-tools)). `_ready` logs `[INFO][debug] --level: running level '<id>'`, or, when GameState already holds an id (a retry or any SceneRouter entry), `--level '<id>' ignored: GameState level '<state id>' wins`. The arg only takes effect when `level.tscn` is the launched scene (`"<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game res://scenes/level/level.tscn -- --level=dev_isolde`); a normal launch starts at `boot.tscn` and reaches the level through `SceneRouter`, which sets the GameState id.
- **Architecture:** the "Level-author trigger patterns" block under the Wave Director rules.
- **Known limit:** under F3 the surrender pauses and clears without a soft-lock, but the reinforcements don't spawn (F3 skips unspawned groups, unchanged).
- **Tests:** `tests/unit/test_isolde_beats.gd` (new, the real `level.tscn` on `dev_isolde`: interruption in the box without a pause; interruption off via a temp flags file loaded as F5 does, wave 1 still clears and wave 2's surrender and 4 reinforcements still arrive and the level clears; the shipped-flags acceptance run from wave 1 through the surrender pause, click-through, 4 reinforcements and the level clear; surrender off: no pause, no story reason, no panel, and the reinforcements still arrive; F3 with the prompt on doesn't soft-lock; the `--level` rows, including the retry), `test_debug_args.gd` (the `level` key) and `tests/data/test_data_files.gd` (the four beats in their files, modes, one Isolde line, combat length, the exact surrender text and no choice; the dev level's shape).

## As-built 2026-10-08 (Story 5.7)

Status update (FR41, FR44, FR45). Content only: no code, `DialogueValidator`, `CommsChannel`, `Config`, `tuning.json`, level file or `dev.json` changed, and no GDD or UX decision changed. Record-only decisions (the docs are silent): the Level 2 briefing id is `l2_briefing`, mirroring `l3_briefing`; `l1_w3_tarek_warning` is a combat line (GDD decision #22 calls it an interruption), so it counts toward Level 1's cap of 2 together with the Isolde interrupt; the `choice` block on `l3_final_choice` is left to Story 7.5, which builds and validates `FinalChoice`. There is no Level 1 briefing: the opening is Level 1's story intro.

- **Data (final script, 15 campaign sequences):**
  - `opening.json`: `opening_main` (story, 7 lines: vale / tarek / isolde, one Isolde line; Tarek, Vale and Isolde each name themselves in their own line, Tarek welcomes the General and briefs the convoy).
  - `level_1.json`: `l1_w3_tarek_warning` (combat, Tarek's ambush warning), `l1_w3_isolde_interrupt` (combat), `l1_w5_surrender` (story, `You're outnumbered, General. Come home.`, unchanged, no `choice`), `l1_tarek_closing` (story, 2 Tarek lines, the debrief).
  - `level_2.json`: `l2_briefing` (story, 3 Tarek lines), `l2_w3_isolde_interrupt` (combat), `l2_w5_tarek_cutoff` (combat, `General, get behind me, I've got you covered!`, `cut_off_at` 40 so the box stops at `...got you cov`, mid-word; the full `after`), `l2_ryn_report` (story, 3 Ryn lines: she names herself, Tarek is alive but gravely injured, she takes command).
  - `level_3.json`: `l3_briefing` (story, 3 Ryn lines), `l3_w3_isolde_taunt` (combat), `l3_final_choice` (story, 2 Isolde lines, the lead-in, no `choice`), `l3_isolde_refuse_surrender` and `l3_isolde_refuse_destroy` (story, Vale's offer or vow, then Isolde; the surrender refusal echoes "Come home"), `l3_isolde_final` (story, 1 Isolde line).
  - Cast rules: Vale is gender-neutral and addressed as "General" (or "Arden"), speaks 4 lines in the campaign (2 in the opening, line 1 of each refusal); no narrator and no `system` speaker in the campaign files.
- **Tests:** `tests/data/test_data_files.gd`: `test_campaign_script_layout` (the 15 ids: file, mode, line count, allowed speakers, loads through `Config`; no `system` speaker; no `choice` on `l1_w5_surrender` or `l3_final_choice`), `test_refusals_open_with_vale` (line 1 by Vale, then Isolde; the "come home" echo), `test_tarek_cutoff_is_final` (Tarek, combat, the exact `after`, the chars either side of `cut_off_at` are letters) and `test_cast_rules` (Vale at most 5 lines, no gendered term as a whole word, the opening self-introductions, Ryn names herself first, every campaign file has a non-Vale "General"), plus the `_is_letter` and `_gendered` self-checks. The every-referenced-sequence test (Story 5.3) is unchanged.

## As-built 2026-10-08 (Story 5.8)

Status update (FR66, NFR8). No GDD or UX decision changed. Record-only decisions (the docs are silent): the energy thresholds are the ability costs from tuning (`abilities.shield.cost` / `abilities.barrage.cost`, 50 / 100 today), and "reaching" means a value ≥ the cost; an action counts only while its hint is the one showing (a held LMB dismisses the fire pill on the next bolt, about 0.1 s, which still confirms the control); the fade-out mirrors the 0.2 s fade-in; the 5 s clock runs from the start of the fade-in and only while the tree is unpaused; hints aren't gated by a level (once per session, so the energy hints normally show in Level 1); the copy is UI text, a const in `hint_pill.gd`; the Player's first lock tick (the spawned ship snapping onto the cursor) is not movement, so it never counts toward the move hint.

- **Events:** `player_moved(distance_px: float)` and `player_action(action: StringName)` (Player), `hint_requested(hint_id: StringName)` (Comms). See [Event System](#event-system).
- **Player:** `step_lock` emits `player_moved` with the distance whenever the confined position differs from the previous one (no allocation), except on its first call. `try_shield` / `try_barrage` emit `player_action(&"shield" / &"barrage")` only on success (a denied or busy ability emits nothing). `PlayerWeapons` emits `&"laser"` after a spawned bolt and `&"missile"` after a spawned missile; the barrage's micro-missiles never emit.
- **WaveDirector / LevelValidator:** the `hint` action (see the Wave Director rules); `LevelValidator.ACTION_KEYS` gains `hint`, `HINT_ACTIONS` = `move_fire`, `missile`.
- **GameState:** `shown_hints: Dictionary[StringName, bool]`, the hints shown this session; never saved or reset.
- **HintPill:** `ui/hud/hint_pill.gd` (`class_name HintPill extends Control`, built in code: a `Panel` holding the `Key` and `Action` Labels, plus a one-shot `ShowTimer`; `MOUSE_FILTER_IGNORE` on it and every child; `PROCESS_MODE_PAUSABLE`), `HUD/HintPill` in `level.tscn` right after `EnergyBar`. `hint_requested(&"move_fire")` queues `move` then `fire`, `&"missile"` queues `missile`; an unknown id logs `[WARN][hint] Unknown hint request '<id>'; nothing shown`. `energy_changed` ≥ the shield / barrage cost queues `shield` / `barrage` (shield first). A hint is never queued when it is in `GameState.shown_hints`, showing or queued. One pill at a time: the next queued hint shows (recorded in `shown_hints`, `[INFO][hint] Hint '<id>' shown`), fades in over `fade_in_s`, starts the `show_s` timer; its action (`move`: cumulative `player_moved` ≥ `move_dismiss_px`; `fire`: `&"laser"`; `missile` / `shield` / `barrage`: the same-named action) or the timer fades it out over `fade_out_s`, then the next queued hint shows. Tweens are created on the pill (default pause mode) and the timer inherits the pausable mode, so a pause freezes both. Layout: width = 2 × `padding_px` + key + `gap_px` (only with a key) + action (text widths from the font at the theme size), centred on `Playfield.SIZE.x`, vertical centre `center_y`, height `h`. Copy: `move` `MOVE THE MOUSE TO FLY` (no key), `fire` `[HOLD LMB]` `FIRE`, `missile` `[RMB]` `MISSILE`, `shield` `[E]` `SHIELD`, `barrage` `[Q]` `BARRAGE`. Read accessors `showing_hint()` (also while fading), `queued()`, `is_fading()`, `key_text()`, `action_text()`, `key_color()`, `action_color()`, `font_px()`, `time_left()`.
- **Theme:** `HintPill/styles/panel` (`StyleBoxFlat_hint_pill`: surfaceAlt fill, corner radius 26, `shadow_color` energy at 0.35 alpha, `shadow_size` 6, the soft glow), `HintPill/colors/key` (#FFD23F), `HintPill/colors/text` (#E8F4FF), `HintPill/font_sizes/text` 28.
- **Data:** `tuning.json` `ui.hint_pill` (`center_y` 560, `h` 52, `padding_px` 24, `gap_px` 12, `fade_in_s` 0.2, `fade_out_s` 0.2, `show_s` 5.0, `move_dismiss_px` 150). `data/levels/level_dev_hints.json` (`id` 0, `Development: control hints`, the `level_dev` key set): two waves of 4 Wasps (`grid_4x1`), wave 1 `wave_start` → `{ "hint": "move_fire" }`, wave 2 `wave_start` → `{ "hint": "missile" }`; play it with `"<GODOT_DIR>/Godot_v4.7.2-stable_win64.exe" --path game res://scenes/level/level.tscn -- --level=dev_hints`. No campaign level, dialogue file or `flags.json` changed: Story 7.1 places the hints in Level 1.
- **Log:** the `hint` category.
- **Tests:** `tests/unit/test_hint_pill.gd` (new: modes, mouse transparency, tuning, the copy and colours, theme items, the rect, move then fire, fade-in, each action, timeout, pause freeze, the 5 s clock, the queue, actions only for the showing hint, energy thresholds and costs, no energy events, once per session across a reload, a queued-only hint, duplicates, an unknown id, no pause or comms), `tests/unit/test_control_hints.gd` (new, the real `level.tscn` on `dev_hints`: the HUD node, wave 1 shows move without a pause or comms, 150 px swaps it for fire, no energy hints, a retry and a reload with the same `shown_hints` show neither), `test_wave_director.gd` (the `hint` action emits and never blocks), `test_level_validator.gd` (hint values), `test_player_movement.gd` / `test_player_laser.gd` / `test_player_missile.gd` / `test_player_shield.gd` / `test_player_barrage.gd` (emit / no-emit), `test_project_settings.gd` (the Events catalogue) and `tests/data/test_data_files.gd` (`ui.hint_pill`, the dev level's shape).

---

_Generated by the GDS Game Architecture Workflow v1.0 (autonomous run)_
_Date: 2026-10-06_
_For: iman2001-ie_
