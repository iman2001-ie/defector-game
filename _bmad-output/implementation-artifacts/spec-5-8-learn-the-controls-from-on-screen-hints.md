---
title: 'Story 5.8: Learn the Controls from On-Screen Hints'
type: 'feature'
created: '2026-10-08'
status: 'awaiting-operator'
operator_actions:
  - 'Launch the level scene directly in a debug build with `-- --level=dev_hints` and confirm `MOVE THE MOUSE TO FLY` appears as a rounded pill centred at y 560, readable, with no clipping, then fades once you fly the ship a short way.'
  - 'Confirm `[HOLD LMB] FIRE` follows with the key part in energy gold and the action in the text colour, and fades on your first shot; in wave 2 confirm `[RMB] MISSILE` appears and fades when you fire a missile.'
  - 'Collect energy orbs until the bar passes 50, then 100, and confirm `[E] SHIELD` then `[Q] BARRAGE` appear one at a time and fade on use or after about 5 s; die, retry, and confirm no hint you already saw shows again.'
baseline_revision: 'ad28af6f1afd58e89ca73ba532205747a2cff1c6'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-5-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/EXPERIENCE.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Nothing teaches the controls (FR66, NFR8). The GDD replaced tutorial dialogue with short on-screen key prompts. There is no `hint` wave action, no hint pill and no "once per session" memory. The architecture's Level 1 example still shows the dropped `{ "comms": "l1_w1_tutorial_move" }`.

**Approach:**
- Add a non-blocking `hint` wave action (`move_fire` | `missile`). It emits a new `Events.hint_requested`.
- Add a `HintPill` HUD control. It shows one pill at a time and queues newer hints. It shows the E/Q hints when `Events.energy_changed` first reaches the shield / barrage cost. It dismisses a hint when the player performs the action (two new player Events) or after 5 s.
- Remember the hints shown in `GameState`, so retries don't repeat them.
- Add a dev level that exercises the hints. Story 7.1 places them in the real Level 1.

## Boundaries & Constraints

**Always:**
- Hints (UX, exact copy, key part in `energy`, action part in `text`):
  - `move`: `MOVE THE MOUSE TO FLY` (no key part).
  - `fire`: `[HOLD LMB]` `FIRE`.
  - `missile`: `[RMB]` `MISSILE`.
  - `shield`: `[E]` `SHIELD`.
  - `barrage`: `[Q]` `BARRAGE`.
- `move_fire` queues `move` then `fire`. `missile` queues `missile`.
- Each hint is dismissed by its action, counted only while it is the showing hint:
  - `move`: cumulative ship movement ≥ `ui.hint_pill.move_dismiss_px` (150).
  - `fire`: the first laser bolt.
  - `missile`: a missile launch.
  - `shield`: the shield raised.
  - `barrage`: a barrage started.
  - Denied abilities and barrage micro-missiles never count.
- `shield` / `barrage` are queued when an `Events.energy_changed` value is ≥ `abilities.shield.cost` / `abilities.barrage.cost`. If both qualify, shield goes first. No energy events means no E/Q hints.
- Once per session:
  - A hint is added to `GameState.shown_hints` when it starts showing.
  - A shown, showing or queued hint is never queued again.
  - It is never saved or reset, so retries, restarts and the title don't repeat it.
  - A queued hint that never showed (the scene reloaded first) can show later.
- One pill at a time:
  - Show: fade in over `fade_in_s` (0.2).
  - Dismiss on its action or `show_s` (5.0) after it started showing: fade out over `fade_out_s` (0.2), then the next queued hint shows.
- Layout: centred horizontally, vertical centre at `ui.hint_pill.center_y` (560), `h` 52, `padding_px` 24 per side, `gap_px` between the key and the action. Fully rounded `surfaceAlt` pill. 28 px text. A soft energy glow. All styling comes from the Theme type `HintPill`.
- The pill never pauses, never touches `PauseArbiter`, `CommsChannel` or the comms panel, and ignores the mouse. Its process mode is pausable, so its tweens and the 5 s clock freeze under any pause.
- Architecture rules apply:
  - The pill reads gameplay only through `Events`. It may read and write `GameState.shown_hints` and read `Config`.
  - New signals go into `events.gd` first.
  - Every number comes from `tuning.json`.
  - Logging goes through `Log` (category `hint`), with no per-frame allocation in hot paths.
- Tests first (red, then green), statically typed.

**Never:**
- Don't edit `level_1.json` / `level_2.json` / `level_3.json` (placement is Story 7.1), dialogue files, or `flags.json`.
- Don't add a feature flag.
- Don't show hints through the comms channel.
- Don't poll `Input` or `Player` from the pill.
- Don't change `level_dev.json` or `level_dev_isolde.json`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Move then fire | `hint: move_fire` runs | `move` pill shows. After 150 px of cumulative movement it fades, then `fire` shows; the first bolt fades it. The tree is never paused. | none |
| Timeout | a hint showing, no action | it fades out at 5 s of unpaused time; a pause stops the clock | none |
| Queue | `missile` requested while `move` shows | `missile` waits and shows only after `move` has faded out | none |
| Energy | energy_changed 40, then 50, then 100 | 40: nothing. 50: `shield` queued. 100: `barrage` queued. Repeats are ignored. | none |
| Once per session | the hint shown, then a retry reload and the same trigger | it doesn't show again | none |
| Unknown id | `Events.hint_requested(&"bogus")` | nothing shows | `Log.warn` (`hint`) |
| Bad data | a level action `{ "hint": "shield" }` or a non-string | `LevelValidator` problem naming the path | the data test fails |
| Chain | `[{hint}, {story_event}]` | both run in the same chain step (hint never blocks) | none |

</intent-contract>

## Code Map

- `game/autoloads/events.gd`: add, with comments:
  - Player: `player_moved(distance_px: float)` and `player_action(action: StringName)` (`&"laser"` | `&"missile"` | `&"shield"` | `&"barrage"`).
  - Comms: `hint_requested(hint_id: StringName)` (`&"move_fire"` | `&"missile"`).
- `game/entities/player/player.gd`:
  - `step_lock` (l.443): emit `player_moved` with the distance when the confined position differs from the old one. Use no allocation.
  - `try_shield` / `try_barrage` (l.278, l.302): emit `player_action` only on success.
  - Update the header comment.
- `game/entities/player/player_weapons.gd`:
  - `_fire_bolt` (l.127): emit `&"laser"` after a spawned bolt.
  - `step_missile` (l.145): emit `&"missile"` after a spawned missile.
  - Never emit from the barrage volley.
- `game/systems/waves/wave_director.gd`:
  - `_run_chain` (l.457-499): add an `elif action.has("hint")` branch that logs at INFO (`beat`) and emits `Events.hint_requested`, without awaiting.
  - Extend the Actions header comment (l.30-41).
- `game/systems/waves/level_validator.gd`: add `"hint"` to `ACTION_KEYS` (l.42) and `HINT_ACTIONS = ["move_fire", "missile"]`. Check it like `music` (l.322). Update the Rules comment (l.24-27).
- `game/autoloads/game_state.gd`: `var shown_hints: Dictionary[StringName, bool] = {}`. Doc: "Story 5.8: control hints shown this session; never saved or reset".
- `game/ui/hud/hint_pill.gd` (new, `class_name HintPill`, `Control`):
  - Builds the pill in code: a `Panel` holding two `Label`s.
  - Caches its tuning in `_ready`.
  - Connects the 4 Events.
  - Uses node-bound tweens and a pausable one-shot `Timer` (or a tween interval) for `show_s`.
  - Pattern: `ui/hud/energy_bar.gd` and `systems/comms/comms_box.gd` (tuning caching, theme lookups, `MOUSE_FILTER_IGNORE` on every child, pausable tweens).
  - Expose small read accessors for tests (`showing_hint() -> StringName`, `queued() -> Array[StringName]`), as `CommsBox.is_open` does.
- `game/scenes/level/level.tscn`: add `HUD/HintPill` (`process_mode = 1`, `mouse_filter = 2`, theme `9_theme`) after `EnergyBar`. HUD children `_ready` before `Level._ready`, so the start-of-level `GameState.emit_energy()` (`level.gd` l.80) reaches it.
- `game/ui/theme/defector_theme.tres`: type `HintPill`:
  - `styles/panel`: StyleBoxFlat, `bg_color` (10,18,34,0.85), corner radius 26, `shadow_color` energy at alpha 0.35, `shadow_size` 6.
  - `colors/key` `#FFD23F` and `colors/text` `#E8F4FF`.
  - `font_sizes/text` 28.
- `game/data/tuning.json`: `ui.hint_pill`: `center_y` 560, `h` 52, `padding_px` 24, `gap_px` 12, `fade_in_s` 0.2, `fade_out_s` 0.2, `show_s` 5.0, `move_dismiss_px` 150. Check whether `test_config.gd` / `Config` key checks need updating.
- `game/data/levels/level_dev_hints.json` (new): copy the `level_dev_isolde.json` shape.
  - 2 waves of a few wasps.
  - W1: `wave_start` → `[{ "hint": "move_fire" }]`.
  - W2: `wave_start` → `[{ "hint": "missile" }]`.
  - Validated automatically by `test_data_files.gd` `_level_files()`. Played by a human with `--level=dev_hints` on a direct `level.tscn` launch (see the 5.6 As-built).
- Tests:
  - `tests/unit/test_hint_pill.gd` (new): unit tests on a bare `HintPill` (pattern: `test_energy_bar.gd` `_make()` l.14). Reset `GameState.shown_hints` in `before_each` / `after_each`.
  - `tests/unit/test_wave_director.gd`: the `_events` capture (l.18-28) and `_start_chain` (l.771) patterns, for the hint action.
  - `tests/unit/test_level_validator.gd`: the bad-value table (l.267) and the ok actions (l.276).
  - `tests/unit/test_player_movement.gd`, `test_player_laser.gd`, `test_player_missile.gd`, `test_player_shield.gd`, `test_player_barrage.gd`: one emit / no-emit test each. Use the `player_test_base.gd` fixture.
  - `tests/unit/test_level.gd` (or a new `test_control_hints.gd` modelled on `test_isolde_beats.gd`, l.7-111): the real `level.tscn` with `dev_hints`.
  - Grep `tests` for any test that lists the HUD children or the Events signals exactly, and extend it.
- `_bmad-output/game-architecture.md`:
  - The HUD rule (l.343): list the new signals the hint pill reads.
  - The Level 1 example (l.774): replace `{ "comms": "l1_w1_tutorial_move" }` with `{ "hint": "move_fire" }`.
  - The ids example (l.721): drop `l1_w1_tutorial_move`.
  - The Wave Director rules: the `hint` action.
  - Add an As-built 2026-10-08 (Story 5.8) section after the Story 5.7 one.

## Tasks & Acceptance

**Execution:**
- Tests first (each failing before its code):
  - `test_hint_pill.gd`: every I/O row except Bad data and Chain. Also:
    - the exact copy and colours per hint;
    - the rect (centred, vertical centre 560, height 52);
    - `MOUSE_FILTER_IGNORE`;
    - `get_tree().paused` stays false and `PauseArbiter` gains no reason;
    - a fresh pill with a populated `shown_hints` shows nothing;
    - energy 100 queues shield then barrage.
  - WaveDirector: `hint` emits `hint_requested` and doesn't block.
  - LevelValidator: `move_fire` and `missile` are accepted; `shield`, `""` and `3` are rejected.
  - Player:
    - `player_moved` fires on movement and not when still;
    - `player_action` fires for a bolt, a missile, a shield and a barrage;
    - nothing fires for a denied shield or barrage, or for the barrage's micro-missiles.
- Then implement: `events.gd`, `game_state.gd`, `player.gd`, `player_weapons.gd`, `wave_director.gd`, `level_validator.gd`, `hint_pill.gd`, `level.tscn`, `defector_theme.tres`, `tuning.json`, `level_dev_hints.json`.
- Level acceptance test on `level.tscn` with `level_id = "dev_hints"`:
  - wave 1 start shows `move`;
  - simulated `player_moved` totalling 150 swaps it for `fire`;
  - a reload with the same `GameState.shown_hints` shows neither.
- `_bmad-output/game-architecture.md`: the edits listed in the Code Map.

**Acceptance Criteria:**
- Given `level.tscn` running `dev_hints`, when wave 1 starts, then `MOVE THE MOUSE TO FLY` shows in the centre-low pill. The tree stays unpaused, and the comms panel and box stay hidden.
- Given a showing hint, when its action is performed or 5 s of unpaused time pass, then it fades out and never shows again this session, including after a retry.
- Given energy never changes, when the level plays, then the E/Q hints never show.
- Given the full headless GUT suite, when it runs, then every test passes with no new errors.

## Spec Change Log

- 2026-10-08 (implementation, record-only): `Player.step_lock` does not emit `player_moved` on its first call. That tick only snaps the freshly spawned ship from its scene position onto the cursor (often more than 150 px), which would otherwise dismiss the move hint before the player had moved. Every later tick emits as specified. Recorded in the architecture As-built (Story 5.8) and covered by `test_player_movement.gd`.
- 2026-10-08 (implementation): `Log.CATEGORIES` gains `hint` (the spec's log category; the architecture's fixed category list is updated to match). `test_project_settings.gd` (the exact Events catalogue) is extended with the three new signals.

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 30 findings — high 0, medium 0, low 16, false 14, maybe-false 0
- findings:
  - `[false]` `[reject]` (blind) the resume snap after a pause counts as movement — `Player._on_resumed` warps the cursor onto the ship before the next lock tick, so the confined point equals the ship position and nothing is emitted.
  - `[low]` `[reject]` (blind) `player_moved` / `player_action` fire for the whole session — one signal emit per tick with a float argument allocates nothing and has one listener; disconnecting adds state for no measurable gain.
  - `[false]` `[reject]` (blind) the HUD writing `GameState.shown_hints` is a silent design change — the spec allows it, and the architecture records it (the hint-pill HUD bullet, l.350, and the As-built Story 5.8 GameState bullet).
  - `[low]` `[patch]` (blind) the directory paragraph says "As of Story 5.6" while listing 5.8 parts — changed to "As of Story 5.8".
  - `[low]` `[patch]` (blind) `test_player_movement.gd` hard-codes 168.0 from tuning — now `600.0 - Config.num("player.bounds_y.min")`.
  - `[low]` `[patch]` (blind) `test_energy_never_changing_means_no_energy_hints` checks only the queue — it now also asserts `showing_hint() == &"move"`.
  - `[low]` `[reject]` (blind) carried energy at the level start shows shield before move/fire, and costs ≤ 0 are unguarded — the order follows the spec's one-at-a-time queue rule; a cost ≤ 0 is a data misconfiguration nobody ships, and a guard adds a branch. The order is now pinned by a test (see the verification-gap row).
  - `[low]` `[reject]` (blind) the level test stops at wave 1 (missile from data, real energy path untested) — the `hint` action's data path is covered by the WaveDirector and LevelValidator tests and the auto-validated dev level; the energy path is covered by the pill and carried-energy tests.
  - `[false]` `[reject]` (blind) timing tests are flaky — `wait_seconds` / the tick loops wait at least the requested time, and the asserts accept both valid end states, so load only delays them.
  - `[low]` `[reject]` (blind) a dismissal during the fade-in fades from partial alpha over the full fade_out_s — cosmetic (≤ 0.2 s) and not a wrong outcome.
  - `[false]` `[reject]` (blind) no `NOTIFICATION_THEME_CHANGED` handling — nothing in the game changes a theme at runtime; `level.tscn` sets the theme before `_ready`.
  - `[low]` `[reject]` (blind) the pill sits under the comms panel during a story pause — intended: the pill is pausable and frozen under the dim, and resumes after; nothing breaks.
  - `[false]` `[reject]` (blind) `shown_hints` leaks between test suites — only `test_hint_pill.gd` and `test_control_hints.gd` read it, and both reset it in before_each / after_each; other suites never assert on it.
  - `[low]` `[reject]` (blind) the missile tests lack a no-spawner case and a micro-missile check — the barrage test asserts exactly one `player_action` for the whole volley (so no micro-missile emits), and the no-spawner path returns before the emit as for the laser.
  - `[false]` `[reject]` (blind) the Config key-check outcome isn't recorded — the suite passes with the new `ui.hint_pill` keys; the fix would only edit this spec.
  - `[low]` `[reject]` (edge) `show_s` ≤ 0 never times out — a data misconfiguration; a guard adds a branch for a case nobody meets.
  - `[low]` `[reject]` (edge) costs ≤ 0 raise E/Q at level start — same as the blind carried-energy row.
  - `[false]` `[reject]` (edge) the resume snap dismisses the move hint — same refutation as the blind row (`_on_resumed` warps the cursor onto the ship).
  - `[low]` `[reject]` (edge) the `_wait_faded` helpers time out silently — the following asserts still fail; only the message is less precise.
  - `[false]` `[reject]` (edge) a queued, never-shown E/Q hint shows at the next level start without an energy change — the spec says a hint that never showed can show later; with the energy stories cut, no event ever reaches a cost.
  - `[low]` `[patch]` (verification-gap) the pause freezing the fade tweens is unverified — added `test_a_pause_freezes_the_fades` (fade-in and fade-out held under `&"menu"`).
  - `[low]` `[patch]` (verification-gap) carried energy at the level start reaching the pill is untested — added `test_carried_energy_at_level_start_queues_shield_then_barrage` (shield shows, then barrage, move, fire).
  - `[false]` `[reject]` (intent) FR66 "in Level 1" and NFR8 aren't delivered — the epics assign placement to Epic 7 ("FR66: Epic 5 - Control hints (placed into Level 1 in Epic 7)", Story 7.1); NFR8 is a playtest outcome.
  - `[low]` `[reject]` (intent) the UX hint slot is verified only through the rect and theme — handled at finalize: a human visual check is listed under `operator_actions` (precedent: Stories 5.1, 5.2 and 5.4).
  - `[low]` `[patch]` (intent) "performs that action" is tested only at the Events surface — added `test_the_real_player_dismisses_move_then_fire`, which drives the level's real Player (`step_lock`, `step_fire`) into the pill.
  - `[false]` `[reject]` (intent) the retry is simulated with `is_retry` and a rebuild — a retry is a scene reload (ADR-004), and nothing resets `shown_hints`, so the rebuild is the retry mechanism.
  - `[false]` `[reject]` (intent) 50 / 100 is tied to tuning — a record-only decision; the values are equal today.
  - `[false]` `[reject]` (intent) the copy differs from the AC examples — the AC says "e.g."; the UX spec gives the exact copy.
  - `[false]` `[reject]` (intent) the HUD writes GameState — same as the blind row; documented.
  - `[false]` `[reject]` (intent) the O1 / O2 status reading — handled at finalize (`awaiting-operator` with `operator_actions` for the visual check).

## Design Notes

**Record-only decisions** (the docs are silent):
- The energy thresholds are the ability costs from tuning (50 / 100 today), so they follow any retune. "Reaching" means a value ≥ the cost.
- An action counts only while its hint is the one showing. A player already holding LMB dismisses the fire pill on the next bolt (about 0.1 s). That is acceptable, because the pill already confirmed the control.
- The fade-out time is 0.2 s, mirroring the fade-in. The UX gives only the fade-in.
- The 5 s timer runs from the start of the fade-in, and only while the tree is unpaused.
- The hints aren't gated by a level. Energy hints can show in any level, but once per session, so they normally show in Level 1.
- The copy is UI text, kept as a const in `hint_pill.gd`, like `CommsPanel.TEXT_CUE`.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import`: expected to complete. A new `class_name` (`HintPill`) needs it.
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`: expected all tests to pass.

**Manual checks (human):**
- Launch `level.tscn` directly with `-- --level=dev_hints`. Confirm that the move pill, then the fire pill, then the missile pill (wave 2) appear centre-low, read clearly and fade on use.

## Auto Run Result

Status: awaiting-operator

**Summary:** Control hints are built. A non-blocking `hint` wave action (`move_fire` | `missile`) emits the new `Events.hint_requested`. The new `HintPill` (`HUD/HintPill`) shows one centre-low pill at a time, with UX copy. It queues `shield` / `barrage` when `energy_changed` reaches the ability costs. It dismisses on the action (the new `Events.player_moved` / `player_action`, emitted by Player and PlayerWeapons) or after 5 s, and freezes under any pause. `GameState.shown_hints` keeps each hint to once per session, retries included. A dev level (`dev_hints`) exercises the hints; Story 7.1 places them in the real Level 1.

**Files changed:**
- `game/autoloads/events.gd`: `player_moved`, `player_action`, `hint_requested`.
- `game/autoloads/game_state.gd`: `shown_hints` (session-only).
- `game/autoloads/log.gd`: the `hint` category.
- `game/entities/player/player.gd`: `player_moved` from `step_lock` (not on the first snap tick); `player_action` on a raised shield or a started barrage.
- `game/entities/player/player_weapons.gd`: `player_action` for each laser bolt and missile (never for micro-missiles).
- `game/systems/waves/wave_director.gd`: the `hint` action.
- `game/systems/waves/level_validator.gd`: `hint` in `ACTION_KEYS`, plus `HINT_ACTIONS`.
- `game/ui/hud/hint_pill.gd` (new): the pill.
- `game/scenes/level/level.tscn`: `HUD/HintPill`.
- `game/ui/theme/defector_theme.tres`: the `HintPill` theme type.
- `game/data/tuning.json`: `ui.hint_pill`.
- `game/data/levels/level_dev_hints.json` (new): the dev level.
- Tests:
  - `test_hint_pill.gd` and `test_control_hints.gd` (new).
  - Additions to `test_wave_director.gd`, `test_level_validator.gd`, `test_player_movement` / `laser` / `missile` / `shield` / `barrage`, `test_project_settings.gd` and `test_data_files.gd`.
- `_bmad-output/game-architecture.md`:
  - the HUD rule and the Level 1 example (`{ "hint": "move_fire" }`);
  - the ids example, the Wave Director rules, the log categories and the directory list;
  - the As-built Story 5.8 section.

**Review findings:** 30 in total (high 0, medium 0, low 16, false 14).
- **Patched (6 low):**
  - The stale "As of Story 5.6" directory header.
  - The hard-coded 168.0 in the movement test.
  - The energy-at-start test now checks the pill.
  - New test: the pause freezes the fade tweens.
  - New test: carried energy at the level start queues shield then barrage.
  - New test: the real Player dismisses move then fire end to end.
- **Deferred:** none.
- **Rejected (low):**
  - Session-long event emits (no allocation).
  - Carried-energy ordering and costs ≤ 0 (spec-conforming, misconfiguration only).
  - Wave 2 / energy integration coverage (covered at unit level).
  - A partial-alpha fade-out (cosmetic).
  - The pill under the story panel (intended pause freeze).
  - Missile no-spawner / micro-missile cases (covered by the barrage count).
  - `show_s` ≤ 0 (misconfiguration).
  - Silent helper timeouts (only the messages).
  - The visual slot check (moved to `operator_actions`).
- **Rejected (false):** 14, each refuted in the Review Triage Log.

**Follow-up review recommendation:** false. Only 6 low patches, with no medium or high.

**Verification:**
- `--import`: exit 0.
- Full headless GUT suite after implementation: 1338 of 1338 passed.
- After the review patches: 1341 of 1341 passed, 0 failures. The `ERROR` lines in the log come from existing tests that check error paths on purpose.
- Matrix audit passed: every I/O row is covered by a test that ran and passed (`test_hint_pill.gd`, `test_control_hints.gd`, the WaveDirector hint tests, the LevelValidator hint test).

**Residual risks:**
- The pill's width is measured with the default fallback font, so it will shift when the Epic 8 font lands. Its look on screen is unchecked (see `operator_actions`).
- Hints aren't reachable in the campaign until Story 7.1 adds the `hint` actions to `level_1.json`. NFR8 (learnability) needs a human playtest then.
- If a player starts a level already holding ≥ 50 energy without having seen the E/Q hints, those show before move/fire (queue order). This is spec-conforming but worth a playtest look.
