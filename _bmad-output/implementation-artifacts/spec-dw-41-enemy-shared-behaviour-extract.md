---
title: 'DW-41: extract shared enemy behaviour into the Enemy base'
type: 'refactor'
created: '2026-10-07'
status: 'done'
baseline_revision: 'e15831e6868bab843785998896d1bef7f0fc570c'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** The five enemy scripts (`wasp`, `lancer`, `needle`, `bastion`, `hunter_wasp`) each repeat the same code: the `ENTRY_*`/`PLAYER_GROUP` constants, `setup()` slot/entry parsing, the off-screen entry-start computation with its unknown-entry WARN, aim-at-player with the `Vector2.DOWN` fallback, the `_fire` missing-spawner guard with its `_warned_no_spawner` flag, and tuning keys hard-coded as `"enemies.<type>."` (epic-2 retro A2, DW-41). `enemy_bullet.gd` and `needle_bolt.gd` repeat the rotate-onto-velocity step. Epic 6 adds more enemies, and each would copy the same code again.

**Approach:** Move the shared pieces into `core/enemy.gd` (`Enemy`) as constants, fields and protected helpers. Wasp and Hunter Wasp also enter and aim without shooting, so the code goes in `Enemy` rather than a `ShooterEnemy` subclass. Move the velocity alignment into an `EnemyBullet` helper. Then rewrite each subclass to call the helpers. Pure refactor.

## Boundaries & Constraints

**Always:** No behaviour, tuning, data, log-text or public-API change. Every subclass keeps its `formation_slot()`, `state()` and other public methods. WARN/DEBUG texts stay byte-identical: `"<type_id> entry '<entry>' is unknown; using top"` (spawn) and `"<type_id> has no spawner; shot skipped"` (spawn, debug, once per enemy). `type_id` values equal the old hard-coded prefixes. Each subclass keeps its log order (slot-clamp WARN before entry WARN). Statically typed GDScript. Tuning reads stay in `_ready` (no per-frame string building). The full GUT suite stays green.

**Never:** No `ShooterEnemy` class, new `class_name` or scene change. No edits to tests except new ones covering the base helpers. Do not touch `Spawner`, `WaveDirector`, `game/data/*.json`, `deferred-work.md` or `sprint-status.yaml`. Do not change the Wasp's re-entry after a dive (`_top_entry_start`, which logs no WARN).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Top entry | `entry` absent or `&"top"`, target (x, y) | start (x, -sprite_px/2) | none |
| Side entry, left half | `&"sides"`, target.x <= 960 | start (-sprite_px/2, target.y) | none |
| Side entry, right half | `&"sides"`, target.x > 960 | start (1920 + sprite_px/2, target.y) | none |
| Unknown entry | `&"spiral"` | top start | one WARN `"<type_id> entry 'spiral' is unknown; using top"` |
| Aim, no player | no node in group `player` | `Vector2.DOWN` | none |
| Aim, player on origin | player at origin | `Vector2.DOWN` | none |
| Aim, player present | player elsewhere | unit vector to player | none |
| Fire guard, no spawner | `spawner` null or freed | `_can_fire()` false | one DEBUG per enemy, then silent |
| Tuning key | `type_id` `&"lancer"`, field `"telegraph_s"` | `"enemies.lancer.telegraph_s"` | none |

</intent-contract>

## Code Map

- `game/core/enemy.gd` -- `Enemy` base. `setup()` L27 parses `position` only. `_ready()` L33 builds `"enemies.%s" % type_id`. The new helpers go here.
- `game/entities/enemies/wasp/wasp.gd` -- consts L17-19; setup L49-55; side/top entry L77-84 (top via `_top_entry_start()`, kept for the post-dive re-entry); `_aim()` L154-161 aims from `global_position`; tuning L60-65.
- `game/entities/enemies/lancer/lancer.gd` -- consts L20-22; setup L56-62; entry L91-97; `_fire` guard L169-173; `_aim(origin)` L184-191; tuning L67-72.
- `game/entities/enemies/needle/needle.gd` -- consts L21-23; setup L75-81; entry from `_anchor` L110-116 (sets `global_position` directly); inline aim in `_aim_line()` L197-202; `_fire` guard L210-214; tuning L86-94.
- `game/entities/enemies/bastion/bastion.gd` -- consts L22-23; setup L60-66; entry L98-104 (after slot clamp WARN L94-97); `_fire` guard L224-228; tuning L71-81. Aims straight down (no player aim).
- `game/entities/enemies/hunter_wasp/hunter_wasp.gd` -- consts L14-16; setup L40-46; entry L54-66 also sets `_heading` RIGHT/LEFT for sides; tuning L51-52. It keeps its own cached `_player` + relookup (not the per-call aim).
- `game/entities/projectiles/enemy_bullet.gd` L14-19 and `needle_bolt.gd` L14-19 -- the same `velocity.angle() - PI / 2.0` rotate on a child node.
- `game/tests/unit/test_{wasp,lancer,needle,bastion,hunter_wasp,enemy,enemy_bullet}.gd` -- read-only regression net. `test_hunter_wasp.gd:192` asserts the exact unknown-entry WARN text.
- `_bmad-output/game-architecture.md` L1098-1105 -- the `Enemy` base class contract list.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_enemy.gd` -- first (red), add tests for the base helpers from the I/O matrix: entry start (top/left/right/unknown + WARN text), `_aim_from` (no player, on origin, present), `_can_fire` (null spawner false, one DEBUG only), `_tuning_key`, and `setup` storing `slot`/`entry`. Use the wasp scene as the concrete Enemy; capture `Log.sink` the way `test_hunter_wasp.gd` does and restore it.
- `game/core/enemy.gd` -- add `ENTRY_TOP`, `ENTRY_SIDES`, `PLAYER_GROUP`; fields `_slot`, `_has_slot`, `_entry`, `_warned_no_spawner`; `setup()` also stores `slot` and `entry`; add `_entry_start_for(target: Vector2) -> Vector2` (with the WARN), `_aim_from(origin: Vector2) -> Vector2`, `_can_fire() -> bool` and `_tuning_key(field: String) -> String`; the base `_ready` uses `_tuning_key`. Document the helpers.
- `game/entities/enemies/{wasp,lancer,needle,bastion,hunter_wasp}/*.gd` -- delete the duplicated consts, fields and setup overrides; call the base helpers; build tuning keys with `_tuning_key`. Keep comments and documented behaviour.
- `game/entities/projectiles/enemy_bullet.gd`, `needle_bolt.gd` -- add `EnemyBullet._align_to_velocity(node: Node2D)`, which skips a null node or a zero velocity, and use it in both `_ready`s.
- `_bmad-output/game-architecture.md` -- add one bullet to the Enemy contract naming the shared helpers.

**Acceptance Criteria:**
- Given the refactored scripts, when each enemy script is searched, then none of them declares `ENTRY_TOP`, `ENTRY_SIDES`, `PLAYER_GROUP` or `_warned_no_spawner`, overrides `setup()`, or contains the literal `"enemies.<type>.`.
- Given the full GUT suite, when it runs headless after `--import`, then every pre-existing test passes unchanged and the new helper tests pass.

## Spec Change Log

## Review Triage Log

### 2026-10-07 — Review pass
- verdicts: 15 findings — high 0, medium 0, low 6, false 9, maybe-false 0
- findings:
  - `low` `patch` `enemy.gd` class doc says the helpers are "not used by the base itself", but base `_ready` calls `_tuning_key` — removed the parenthetical.
  - `low` `reject` The tier lookup still builds `"enemies.%s" % type_id` by hand beside `_tuning_key` — it is built from `type_id` (not a hard-coded prefix), it sits in the base only, and a fix needs a new section helper; not worth the added surface.
  - `low` `reject` `wasp._top_entry_start()` repeats the top formula of `_entry_start_for` — kept on purpose for the WARN-free post-dive re-entry (spec Never); a shared WARN-free helper would add surface for a one-line formula.
  - `low` `patch` Hunter Wasp re-tests `_slot.x <= centre` for its side heading instead of following the start `_entry_start_for` returned — heading now derives from `global_position.x <= Playfield.SIZE.x / 2.0`; same behaviour for any `sprite_px >= 0`.
  - `false` `reject` `_entry_start_for` logs per call, which is undocumented — its doc says any unknown entry logs a WARN; the only repeat caller (Wasp re-entry) deliberately uses `_top_entry_start`.
  - `false` `reject` Byte-identical log texts are untested per subclass — `type_id` is unchanged, the text comes from one helper tested in `test_enemy.gd`, `test_hunter_wasp.gd:192` checks the exact WARN, and a wrong `type_id` would break every tuning read the existing suites exercise.
  - `false` `reject` `_align_to_velocity` has no direct test — `test_enemy_bullet.gd:121` (axis follows velocity), `:125` (zero velocity keeps rotation 0) and `test_needle_bolt.gd:116` cover its contract through both callers.
  - `low` `reject` The new tests hard-code -32/1952/960 — this matches the literal-value style of `test_wasp.gd`/`test_lancer.gd`, and changing the playfield would break those suites too; negligible harm.
  - `false` `reject` The log capture resets `Log.sink` to `Callable()` instead of the prior sink — that is the project convention (`test_bastion.gd:27`, `test_config.gd:39`, `test_debug_tools.gd:348`); no harness sink exists.
  - `false` `reject` `setup()` edge cases are untested — no bad outcome named; the parsing moved verbatim from the five identical subclass overrides.
  - `false` `reject` The architecture bullet omits `_warned_no_spawner` — it is private state of `_can_fire`, whose "one DEBUG per enemy" contract is documented.
  - `false` `reject` The diff omits the spec and shows no verification evidence — the spec goes only to the edge-case layer by design; the suite ran 635/635 (recorded below).
  - `false` `reject` (intent audit) Hunter Wasp's cached player chase was not merged into `_aim_from` — it falls back to the playfield centre and caches the player; merging would change behaviour, which the intent forbids.
  - `low` `patch` (intent audit) The side check is repeated in `hunter_wasp.gd` — same root cause as the Hunter heading row above; fixed by the same patch.
  - `false` `reject` (intent audit) `wasp_dive_clock.gd` keeps `"enemies.wasp.dive_interval_s.*"` — it is not an `Enemy`, has no `type_id`, and is not one of the five enemy scripts the intent names.

### 2026-10-07 — Review pass (follow-up)
- verdicts: 17 findings — high 0, medium 0, low 7, false 10, maybe-false 0
- findings:
  - `false` `reject` (blind) Hunter Wasp's heading check `global_position.x <= Playfield.SIZE.x / 2.0` repeats the helper's side rule — the start x is always -sprite_px/2 or 1920+sprite_px/2, far from the 960 tie line, so a tie-break change in `_entry_start_for` cannot flip the heading against the start side.
  - `low` `reject` (blind) carried: `wasp._top_entry_start()` repeats the top formula — kept on purpose for the WARN-free post-dive re-entry (spec Never).
  - `low` `reject` (blind) carried: the tier lookup still builds `"enemies.%s" % type_id` by hand — base-only, built from `type_id`; a section helper adds surface for no named harm.
  - `low` `reject` (blind) `player.gd` and the tests use a literal `&"player"` rather than `Enemy.PLAYER_GROUP` — the literal predates this change (each enemy had its own copy); the fix makes the player depend on `Enemy` or adds a shared groups constant, for a name nobody is changing.
  - `false` `reject` (blind) carried: `_entry_start_for` warns per call and `setup()` accepts any entry value — the doc states the per-call WARN, the only repeat caller uses `_top_entry_start`, and the parsing moved verbatim from the five identical overrides.
  - `low` `reject` (blind) carried: the new tests hard-code -32/1952/960 — matches the literal-value style of the existing enemy suites.
  - `false` `reject` (blind) carried: `_align_to_velocity` has no direct test — `test_enemy_bullet.gd` and `test_needle_bolt.gd` cover axis-follows-velocity and zero-velocity cases through both callers.
  - `low` `reject` (blind) `_warned_no_spawner` guards a DEBUG, not a WARN — the name is the one all five scripts used before and the spec's AC greps for; a rename is cosmetic churn.
  - `low` `reject` (blind) `test_enemy.gd` `before_each` now routes every test's log output to `_lines` — a diagnostic concern only when an older test fails, and GUT still reports the failed assertion; scoping the sink would restructure the fixtures.
  - `false` `reject` (blind) the architecture bullet lists private members without subclass rules — it documents which helpers exist, as the spec task asked; no caller is misled into a wrong use.
  - `low` `patch` (blind) the `enemy.gd` class doc breaks the helper list mid-item (`` `_slot`/`_has_slot`/ `` then `` `_entry` ``) — re-wrapped into three lines.
  - `false` `reject` (edge) carried: `wasp_dive_clock.gd` keeps `"enemies.wasp.dive_interval_s.*"` — it is not an `Enemy` and not one of the five scripts the AC names.
  - `false` `reject` (intent) carried: unknown-entry WARN and no-spawner DEBUG texts are not pinned per subclass — the texts come from one tested helper with unchanged `type_id`s; `test_hunter_wasp.gd` pins the exact WARN, and a wrong `type_id` breaks every tuning read.
  - `false` `reject` (intent) Lancer/Needle/Bastion log order (clamp WARN before entry WARN) is equivalent by inspection only — the auditor itself confirmed each clamp still precedes the `_entry_start_for` call; no divergence exists.
  - `false` `reject` (intent) `test_enemy.gd` fixture changes cross the "no test edits" line — the intent allows new tests covering the base helpers, and the sink/debug fixtures exist only to serve them; no pre-existing assertion changed.
  - `false` `reject` (intent) the architecture-doc bullet is outside the stated scope — the intent forbids no doc edit, and the bullet records the base contract the refactor created.
  - `false` `reject` (intent) the full suite run was not confirmed by the auditor — re-run in this pass: 635/635 passing.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exits 0
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failures
- `grep -nE "ENTRY_(TOP|SIDES): |PLAYER_GROUP: |_warned_no_spawner|\"enemies\.(wasp|lancer|needle|bastion|hunter_wasp)\." game/entities/enemies/{wasp/wasp,lancer/lancer,needle/needle,bastion/bastion,hunter_wasp/hunter_wasp}.gd` -- expected: no matches (`wasp_dive_clock.gd` is not an Enemy and keeps its key)

## Auto Run Result

Status: done

**Summary:** Pure refactor (DW-41, epic-2 retro A2). The `Enemy` base (`game/core/enemy.gd`) now owns the `ENTRY_TOP`/`ENTRY_SIDES`/`PLAYER_GROUP` constants, `slot`/`entry` parsing in `setup()`, `_entry_start_for()`, `_aim_from()`, `_can_fire()` and `_tuning_key()`. The five enemy scripts dropped their copies and call the helpers. `EnemyBullet._align_to_velocity()` is shared by the bullet and the Needle bolt. Log texts, log order, tuning and public API are unchanged. This follow-up review pass re-wrapped one doc comment.

**Files changed:**
- `game/core/enemy.gd` -- shared constants, fields, setup parsing and four helpers (follow-up: class doc re-wrapped).
- `game/entities/enemies/{wasp,lancer,needle,bastion,hunter_wasp}/*.gd` -- duplicates removed; helpers and `_tuning_key` used.
- `game/entities/projectiles/enemy_bullet.gd`, `needle_bolt.gd` -- `_align_to_velocity` helper.
- `game/tests/unit/test_enemy.gd` -- helper tests covering every I/O matrix row.
- `_bmad-output/game-architecture.md` -- Enemy contract bullet for the shared helpers.

**Review findings (follow-up pass):** 17 in total (verification-gap layer: none). Patches applied: 1 low (the `enemy.gd` doc wrap). Deferred: none. Rejected: 6 low (Wasp top-entry helper, tier section prefix, player-group literal, hard-coded test values, `_warned_no_spawner` name, file-wide log capture in `test_enemy.gd`) and 10 false, each with its reason in the Review Triage Log.

**Follow-up review recommendation:** false (follow-up pass patched no `high`; patched by verdict: high 0, medium 0, low 1).

**Verification:** `--import` exited 0. The full GUT suite passed 635/635 (6592 asserts) after the follow-up patch. The AC grep over the five enemy scripts found no matches.

**Residual risks:** Wasp and Hunter Wasp inherit `_can_fire`/`_warned_no_spawner`, which they don't use (accepted to avoid a `ShooterEnemy` class). Automated tests confirm the gameplay rules are unchanged; feel was not re-checked by a human.
