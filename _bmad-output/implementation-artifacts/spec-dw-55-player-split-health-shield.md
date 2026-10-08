---
title: 'DW-55: split player.gd into HealthComponent, PlayerShield and one spend gate'
type: 'refactor'
created: '2026-10-08'
status: 'done'
baseline_revision: '4cb60cd9c86f2b0dd112d8321ed40f284d9e50f5'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
warnings: ['oversized']
deferred:
  - summary: >-
      PlayerShield's missing-bubble degradation path (Log.error plus null-safe raise/step/drop) has no test.
    evidence: |-
      grep for "missing its bubble" hits only player_shield.gd; every test wires a real ShieldBubble. Only consumer player.tscn wires it correctly today.
    location: >-
      game/entities/player/player_shield.gd:29
    severity: low
  - summary: >-
      Pre-existing: player.hearts tuning is used unclamped, so a negative value makes the ship unhittable with no warning.
    evidence: |-
      HealthComponent.setup copies p_max_value as given, exactly as the old Player._ready did (max_hearts = Config.int_("player.hearts")). Not caused by DW-55; clamping would change behaviour.
    location: >-
      game/core/health_component.gd:36
    severity: low
  - summary: >-
      Pre-existing order-dependent test: test_player_barrage.gd::test_physics_process_steps_before_reading_q fails when run in one session with the other player test scripts.
    evidence: |-
      Reported by the implementation subagent: the six existing player scripts run together fail it at line 201 (0 launches, expected 1) on baseline 4cb60cd too; it passes alone and in the full-suite run (913/913). Suspected leaked simulated Q press; unconfirmed.
    location: >-
      game/tests/unit/test_player_barrage.gd:201
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** `game/entities/player/player.gd` is 442 lines and owns cursor lock, hearts and i-frames, death, shield state and timer, the barrage gate, contact routing and weapon delegators (Epic 3 retro A1). `try_shield` and `try_barrage` repeat the same spend gate (A3). The architecture plans `core/health_component.gd` (`HealthComponent`), but it was never built.

**Approach:** Move hearts and i-frames into a `HealthComponent` child node (`core/health_component.gd`, node `Health`). Move shield state and its countdown into a `PlayerShield` child node (`entities/player/player_shield.gd`, node `Shield`, like `PlayerWeapons`). Fold the two `try_*` bodies into one private `_spend` gate on `Player`. `Player` keeps its whole public API as delegators. Update `game-architecture.md` to match. Pure refactor.

## Boundaries & Constraints

**Always:** No behaviour, tuning, data, log-text, event or event-order change. A hit still emits `Events.hearts_changed(hearts, max_hearts)`, then `Events.player_hit(pos)`, then either PLAYER_HIT feedback plus i-frames or (at 0) `_die()`. `_die()` still plays PLAYER_DEATH and emits `player_died`, then `level_failed(&"hearts")`. The deferred first `hearts_changed` stays. `Player` keeps these names working with unchanged semantics: `hearts` and `max_hearts` (read and write), `debug_invincible`, `apply_damage`, `is_invulnerable`, `is_dead`, `_die`, `step_iframes`, `is_shielded`, `shield_remaining`, `try_shield`, `step_shield`, `is_barraging`, `try_barrage`, `step_barrage`, `on_contact`, `_contacts`, `_on_area_entered`/`_exited`, `_physics_process` tick order, and the `Sprite`/`ShieldBubble` child paths. Components hold no `Events`, `GameState` or `Audio` calls. Contact routing, death and the cursor lock stay on `Player`. Statically typed GDScript. Config is read only in `_ready`/setup; there are no per-tick lookups and no per-tick allocations.

**Never:** Do not edit existing tests. Do not change `game/data/*.json`, the HUD, `PlayerWeapons` or `ShieldBubble`. Do not touch `deferred-work.md` or `sprint-status.yaml`. Do not do the shared test fixture (A2), the blink helper (A4) or the `Groups` class (A5). Do not give enemies a `HealthComponent`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Non-lethal hit | 5 hearts, `take(1)` | current 4, i-frames start, `damaged` signal before i-frames start | none |
| Lethal hit | 1 heart, `take(3)` | current 0 (floored), `damaged` then `died`, no i-frames | none |
| Ignored hit | amount <= 0 or current 0 | no change, no signal; `can_take` false | none |
| I-frames end | elapsed >= iframes_s | flicker target visible, `iframes_ended` once | none |
| Zero i-frames | iframes_s 0 | hit leaves no i-frames | none |
| Shield raise / expire | `raise()`, step past duration | active, bubble shown; on expiry inactive, bubble hidden, `ended` once | duration 0: not active, as today |
| Spend gate | dead / busy / short / enough | false silently / false silently / deny + false / spend, log, true | none |

</intent-contract>

## Code Map

- `game/entities/player/player.gd` -- source. Hearts and i-frame fields L74-99; `_ready` Config reads L130-139; `_physics_process` tick order L148-160; `apply_damage` L178-188; `_die` L193-208; `step_iframes`/`_start_iframes` L213-228; shield L237-277; barrage gate L290-299; `_deny` L308; `_recheck_contacts` L369 (called on i-frame end, shield end and `debug_invincible` off).
- `game/entities/player/player.tscn` -- add `Health` (script `core/health_component.gd`) and `Shield` (script `player_shield.gd`, `bubble = NodePath("../ShieldBubble")`) nodes, and bump `load_steps`.
- `game/entities/player/player_weapons.gd` -- pattern to copy: a `Node` child with an exported `NodePath`, resolved in `_ready`, plus a `Log.error` when the path is missing.
- `game/entities/player/shield_bubble.gd` -- read-only: `show_remaining(s)`, `hide_bubble()`.
- Tests that read Player internals (read-only regression net): `test_player_{hearts,death,shield,barrage,pickup}.gd` set `hearts` directly and call `_die()`, `_contacts`, `_on_area_entered/_exited`, `_physics_process` and `get_node("Sprite"|"ShieldBubble")`. `test_energy_orb.gd`, `test_level.gd`.
- `_bmad-output/game-architecture.md` -- L182 state table; L478 signal example; L563 built list ("`core/` except `health_component.gd`"); L585-596 tree; L668 player row; L1276 traceability; L1520, L1534, L1559, L1569 as-built notes.

## Tasks & Acceptance

**Execution:**
- `game/tests/unit/test_health_component.gd` -- new, written first: covers the HealthComponent rows of the I/O matrix on a bare `HealthComponent` with a `Sprite2D` flicker target, including the flicker phase and that the signals fire in order. -- red/green.
- `game/tests/unit/test_player_shield_component.gd` -- new: covers the `PlayerShield` rows on a bare node with a `ShieldBubble`, plus `drop()` (inactive, bubble hidden, no `ended`). -- red/green.
- `game/core/health_component.gd` -- `class_name HealthComponent extends Node`: signals `damaged(current, max_value)`, `died`, `iframes_ended`; `setup(max_value, iframes_s, flicker_hz, flicker_target)`; `current`, `max_value`, `can_take(amount)`, `take(amount)`, `step(delta)`, `is_iframing()`, `stop_iframes()`. -- A1, the planned architecture node.
- `game/entities/player/player_shield.gd` -- `class_name PlayerShield extends Node`: `@export var bubble: NodePath`; reads `abilities.shield.cost`/`duration_s` in `_ready`; `cost`, `duration_s`, `is_active()`, `remaining()`, `raise()`, `step(delta)`, `drop()`, signal `ended`. -- A1.
- `game/entities/player/player.tscn` -- add the two nodes. -- wiring.
- `game/entities/player/player.gd` -- delegate to the components. `hearts`/`max_hearts` become properties that forward to `Health` (null-safe before `_ready`). Connect `damaged` (emits the two Events, plus PLAYER_HIT feedback when current > 0), `died` → `_die`, `iframes_ended` and `ended` → `_recheck_contacts`. Add `_spend(ability, busy, cost, log_line) -> bool` used by both `try_*`. Trim the header doc to match. -- A1, A3.
- `_bmad-output/game-architecture.md` -- update the lines in the Code Map to the as-built split. -- spec reconciliation.

**Acceptance Criteria:**
- Given the full GUT suite, when run headless after `--import`, then every pre-existing test passes unchanged, and so do the new tests.
- Given the refactor, when `player.gd` is measured, then it is under 442 lines, and neither component calls `Events`, `GameState` or `Audio`.
- Given `game-architecture.md`, when read, then it lists `health_component.gd` and `player_shield.gd` as built and no longer describes the hearts, i-frame or shield state as inline `Player` fields.

## Spec Change Log

## Review Triage Log

### 2026-10-08 — Review pass
- verdicts: 24 findings — high 0, medium 0, low 11, false 13, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: the as-built note says "no behaviour changed" yet the log now precedes raise/start — raise() and start_barrage() log nothing on valid data (Spawner logs only on misconfiguration), so the log output is unchanged.
  - `[false]` `[reject]` Blind: the Story 3.4/3.5 as-built bullets describe old internals — they describe the Player-level contract, which is unchanged; the parenthetical names the owner and the DW-55 section records the internals.
  - `[low]` `[patch]` Blind: the Player row sentence makes `shield_bubble.tscn` read as part of the spend gate — clause closed with a full stop.
  - `[low]` `[patch]` Blind: the Directory Structure heading still says "As of Story 3.5" — now "As of DW-55".
  - `[false]` `[reject]` Blind: ShieldBubble's doc says "Driven by the Player only" — the driver is still the Player entity (its Shield child); no other system calls it, and the spec keeps ShieldBubble unchanged.
  - `[false]` `[reject]` Blind: the hearts setter drops pre-_ready writes — before, a pre-_ready write was overwritten by _ready (hearts = max_hearts), so it never took effect then either.
  - `[low]` `[patch]` Blind: apply_damage duplicates can_take's checks — guard reduced to `_dead or is_invulnerable()`.
  - `[low]` `[patch]` Blind: _die's redundant `_sprite.visible = true` and its stale "apply_damage guards it" doc — line removed, doc updated.
  - `[low]` `[patch]` Blind: PlayerShield tests depend on live shield duration — before_each pins duration_s to 4.0; test_reads_tuning checks the Config value.
  - `[low]` `[defer]` Blind: new paths untested (missing bubble) — same root cause as the verification-gap finding; deferred.
  - `[false]` `[reject]` Blind: untested _spend log order / hearts forwarding / re-entrancy — the log order is not observable (see the first row); forwarding is run by every `_player.hearts = 1` setup; re-entry is covered by the asteroid and bastion re-hit tests.
  - `[low]` `[defer]` Blind: setup doesn't clamp hearts — pre-existing (the old _ready behaved the same); deferred.
  - `[low]` `[reject]` Blind: the log string is built before the gate — keypress-only, not a hot path; avoiding it needs a Callable restructure, more than a direct correction.
  - `[false]` `[reject]` Blind: test_player_shield_component.gd naming — test_player_shield.gd already holds the Player-level tests; no harm named.
  - `[false]` `[reject]` Blind: the changeset lacks the spec/ledger/decision log — the spec is tracked and committed with the change; the ledger is orchestrator-owned by instruction; adopting the planned HealthComponent changes no design decision.
  - `[false]` `[reject]` Edge: _die runs twice via a direct take() after death — take() at 0 hearts is a no-op via can_take; only Player calls take().
  - `[false]` `[reject]` Edge: public take() bypasses shield/debug checks — no caller besides Player.apply_damage.
  - `[low]` `[defer]` Edge: negative max hearts — grouped with the Blind clamp finding (pre-existing).
  - `[false]` `[reject]` Edge: the hearts setter is unclamped — identical to the old plain field.
  - `[low]` `[patch]` Edge: shield component test assumes duration > 1 s — grouped with the Blind live-tuning finding; patched.
  - `[low]` `[patch]` Edge: bubble-visible assertion depends on duration vs blink_last_s — same patch.
  - `[low]` `[defer]` Verification gap: PlayerShield missing-bubble path untested — filed disposition defer; deferred.
  - `[false]` `[reject]` Intent alignment: the log reorder conflicts with "without changing behaviour" — not observable (see the first row).
  - `[false]` `[reject]` Intent alignment: nothing in the diff exercises Player/Events — the untouched existing player suites ran green (913/913).
  - `[false]` `[reject]` Intent alignment: the hearts/max_hearts setters couple to component fields — required to keep the existing tests' direct writes working, as the spec's Always demands; no harm named.
- also deferred (found while patching): `test_player_barrage.gd::test_physics_process_steps_before_reading_q` is order-dependent and fails on baseline 4cb60cd too (unverified medium).

### 2026-10-08 — Review pass
- verdicts: 22 findings — high 0, medium 0, low 7, false 15, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: writes to `hearts`/`max_hearts` before `_ready` are lost — carried: before, a pre-_ready write was overwritten by _ready (hearts = max_hearts), so it never took effect then either.
  - `[false]` `[reject]` Blind: the forwarding setters bypass clamping (`hearts = 0` leaves a live ship) — carried: identical to the old plain field, which was just as unclamped.
  - `[false]` `[reject]` Blind: `damaged` fires before the i-frames start, so a listener could re-hit — the old Player emitted hearts_changed/player_hit before starting i-frames too; no listener of either event deals damage (only Player calls take()).
  - `[false]` `[reject]` Blind: `_flicker_target` is null-checked, not `is_instance_valid` — the only target is Player's own `Sprite` child, freed together with its sibling `Health`; no path frees it first.
  - `[low]` `[reject]` Blind: HealthComponent contracts untested (negative iframes/flicker, null target, exact `>=` boundary, non-positive max) — no caller passes these (Player always passes the Sprite and Config values); adding tests for unused inputs is extra surface, not a defect correction.
  - `[low]` `[defer]` Blind: PlayerShield missing-bubble path untested and only in the spec — carried: already in this spec's `deferred` list, so not added again.
  - `[false]` `[reject]` Blind: the components read tuning in two ways (`_ready` vs `setup()`), and `_barrage_cost` stays on Player — the spec prescribes exactly this split; both read Config only at setup, and no caller diverges. No harm named.
  - `[false]` `[reject]` Blind: the arch doc says "no behaviour changed" but records the log reorder; the Story 3.4 bullet keeps the old order — carried: raise() and start_barrage() log nothing on valid data (Spawner, Audio and Feedback log only on misconfiguration, re-checked this pass), so the captured log is unchanged; the 3.x bullets describe the Player-level contract.
  - `[low]` `[reject]` Blind: the `entities/player/` table row is very long — readability only; trimming it is a doc restructure, not a direct correction.
  - `[false]` `[reject]` Blind: the Story 3.1 bullet still describes apply_damage internals — carried: the 3.x bullets describe the unchanged Player-level contract; the DW-55 section records the internals.
  - `[low]` `[reject]` Blind: `try_shield` builds its log string before the gate — carried: keypress-only, not a hot path; avoiding it needs a Callable restructure.
  - `[false]` `[reject]` Blind: `test_player_shield_component.gd` name next to `test_player_shield.gd` — carried: no harm named.
  - `[false]` `[reject]` Edge: Player API (`is_invulnerable`, `try_shield`, ...) called before `_ready` hits a null component — the only callers are Player itself (apply_damage, _recheck_contacts, _physics_process) and tests, all after `_ready`; no external caller reaches them earlier.
  - `[low]` `[defer]` Edge: negative `player.hearts` makes `current` negative — carried: pre-existing; already in this spec's `deferred` list.
  - `[false]` `[reject]` Edge: the hearts/max_hearts setters accept out-of-range values — carried: identical to the old plain field.
  - `[low]` `[patch]` Verification gap: no test checks that a lethal hit skips PLAYER_HIT (the guard moved into `_on_damaged`'s `current > 0`; strongest-shake, longest-hit-stop and newest-SFX checks all hide a stray tier) — added `game/tests/unit/test_player_lethal_feedback.gd`. It counts Audio starts across one hit: lethal = 1 (player_death), non-lethal = 1 (player_hit). Mutating the guard to `>= 0` fails it (2 ≠ 1); restored.
  - `[false]` `[reject]` Intent alignment: the log line now precedes raise / start_barrage (whose first launch spawns, whooshes and flashes) — re-checked: `_step_launch`/`_launch_micro`, `Spawner.spawn_projectile`, `Audio.play_sfx` and `Feedback.impact` log only on errors, so no captured line moves.
  - `[false]` `[reject]` Intent alignment: PlayerShield adds a new `Log.error` for a missing bubble — fires only on a mis-wired scene (the shipped `player.tscn` wires it); no existing line changes.
  - `[false]` `[reject]` Intent alignment: the Story 3.4 as-built bullet keeps the old order — carried (see the Blind row above).
  - `[low]` `[reject]` Intent alignment: `try_shield` builds its string on silent and denied presses — carried (keypress-only).
  - `[false]` `[reject]` Intent alignment: pre-`_ready` writes are now dropped — carried: the old `_ready` overwrote them.
  - `[false]` `[reject]` Intent alignment: no Player-level tests, and no evidence the existing suites ran — carried: the unedited player suites ran green; this pass: 62 scripts, 915/915.

## Design Notes

Signal order makes the hit path match the old code exactly. `take(amount)` floors `current`, emits `damaged`, then either emits `died` (current 0) or starts the i-frames. Player's `damaged` handler emits `hearts_changed` and `player_hit`, then plays PLAYER_HIT only if current > 0. That gives the old order: events, then feedback, then i-frames, or events then `_die()`. `_dead` stays on `Player` because tests call `_die()` directly and death is Player behaviour. `_die()` calls `_health.stop_iframes()` and `_shield.drop()`.

```gdscript
func _spend(ability: StringName, busy: bool, cost: int, log_line: String) -> bool:
	if _dead or busy:
		return false
	if GameState.energy < cost:
		_deny(ability)
		return false
	GameState.add_energy(-cost)
	Log.info("combat", log_line)
	return true
```

The log line now comes before the shield goes up and before the volley starts. Neither of those logs anything, so the captured log sequence is unchanged.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import` -- expected: exit 0 (new `class_name`s cached)
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass, 0 failures


## Auto Run Result

Status: done

**Summary:** DW-55 follow-up review pass. The split itself is unchanged: hearts and i-frames are in `HealthComponent` (`game/core/health_component.gd`, the `Health` child), shield state is in `PlayerShield` (`game/entities/player/player_shield.gd`, the `Shield` child), and `try_shield`/`try_barrage` share `Player._spend`. Every Player name and the Events order are unchanged. This pass added one regression test, for the lethal-hit feedback guard that the refactor moved into `_on_damaged`.

**Files changed (whole change since baseline 4cb60cd):**
- `game/core/health_component.gd` (+ `.uid`): HealthComponent (hearts, i-frames, flicker; signals `damaged`/`died`/`iframes_ended`).
- `game/entities/player/player_shield.gd` (+ `.uid`): PlayerShield (cost/duration, raise/step/drop, signal `ended`).
- `game/entities/player/player.gd`: delegates to the components; forwarding `hearts`/`max_hearts`; `_on_damaged`; the `_spend` gate.
- `game/entities/player/player.tscn`: adds the `Health` and `Shield` nodes.
- `game/tests/unit/test_health_component.gd`, `test_player_shield_component.gd` (+ `.uid`): component tests.
- `game/tests/unit/test_player_lethal_feedback.gd` (+ `.uid`): new this pass. A lethal hit plays only PLAYER_DEATH's SFX, and a non-lethal hit only PLAYER_HIT's.
- `_bmad-output/game-architecture.md`: reconciled to the as-built split.

**Review (this pass):** 22 findings (high 0, medium 0, low 7, false 15).
- Patched (1, low): the verification gap on the lethal-hit PLAYER_HIT guard. Covered by the new test, which fails when the guard is mutated.
- Deferred: nothing new. The missing-bubble path and the negative `player.hearts` were carried, and both are already in `deferred`.
- Rejected:
  - 15 false: pre-_ready writes, setter clamping (x2), re-entrancy on `damaged`, `is_instance_valid` on the flicker target, the tuning-read pattern, the log-reorder and doc claims (x4), the 3.1 bullet, the test naming, a null component before `_ready`, the new missing-bubble `Log.error`, and "no Player-level evidence".
  - 4 low: untested unused HealthComponent inputs, the long architecture table row, and the log string built before the gate (x2).
- Reasons are in the triage log.

**Follow-up review recommended:** false. This was a follow-up pass, and it patched no `high` (patched by verdict: high 0, medium 0, low 1).

**Verification:**
- `--import`: exit 0.
- New test alone: 2/2. It fails 1/2 when `if current > 0:` is mutated to `>= 0`; the mutation was reverted, and `player.gd` shows no diff.
- Full GUT suite: 62 scripts, 915/915 passing, exit 0.

**Residual risks:**
- Feel is unverified (no playtest).
- The new test reads `Audio._next_serial`, a private counter. If Audio's internals change, the test must change too.
- `test_player_barrage.gd::test_physics_process_steps_before_reading_q` is order-dependent (pre-existing, already deferred).
- `deferred-work.md` had uncommitted changes from the orchestrator before this run. It was left untouched and uncommitted, as instructed.
