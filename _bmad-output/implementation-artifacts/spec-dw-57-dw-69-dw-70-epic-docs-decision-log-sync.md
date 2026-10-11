---
title: 'DW-57, DW-69, DW-70: sync the decision log, GDD, DESIGN.md, epics and architecture with the as-built Epic 2-3 behaviour'
type: 'chore'
created: '2026-10-10'
status: 'done'
baseline_revision: '4266fa88588b478d2b1e21c9d989e1db52bd88d4'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md'
  - '{project-root}/_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md'
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: >-
      Epic 7 boss ACs and the GDD/FR49-FR51 boss cadence lines still use the "every N s after a G s glow" wording that DW-70 rewrote for Stories 2.5 and 2.7.
    evidence: |-
      epics.md Story 7.x ACs (about lines 1654, 1688, 1724), FR49-FR51 (epics.md:133-135) and gdd.md:283-285 are unchanged. Decision #50, the architecture Flagship cadence bullet and the data test now state start-to-start, but an Epic 7 implementer reading only the ACs could build interval + glow. Rewording those ACs is a planning-doc change the DW-69 decision did not ask for, so it needs the operator's OK.
    location: >-
      _bmad-output/planning-artifacts/epics.md (Epic 7 story ACs)
    severity: low
  - summary: >-
      test_level.gd test_dev_convoy_maul_wave_hits_the_convoy is intermittent ("at its slot's y": 179.3 vs 160 +/- 13.3).
    evidence: |-
      Failed in 2 of 3 full headless runs and 1 of 3 isolated runs of test_level.gd during this bundle; passed in the others. The bundle touches no runtime code, only docs and one data test. Likely frame-timing sensitive, like DW-79 (test_shake_camera, which also flaked once in this run).
    location: >-
      game/tests/unit/test_level.gd (test_dev_convoy_maul_wave_hits_the_convoy)
    severity: medium
---

<intent-contract>

## Intent

**Problem:** The operator decided on 2026-10-10 how three documentation gaps close: Epic 3 deviations (asteroids survive contact, retry-headline anchor, new tuning values and the `ui` section) are not in the decision log (DW-57); decision #38's start-to-start cadence rule covers only Lancer and Bastion, leaving the Wasp and the unbuilt boss timers unstated (DW-69); the Story 2.5 / 2.7 ACs still read as the pre-#38 "timer reaches N s, then glow" order (DW-70).

**Approach:** Docs-as-built edits in the decision log, GDD, DESIGN.md, `epics.md` and the architecture, plus one GUT data test pinning telegraph/glow ≤ period for the Wasp and every boss timer pair.

## Boundaries & Constraints

**Always:** Record the decisions exactly as the ledger `decision:` lines state them. New decision-log rows continue the table numbering (#48 onwards), same 5-column format, Source naming the DW id. Statically typed GDScript in the test; read values only through `Config`.

**Never:** No gameplay code change, no tuning value change, no edit of `deferred-work.md` or `sprint-status.yaml`. Don't rewrite FR49/FR50/FR51 numbers. Don't edit cached `epic-*-context.md` files.

</intent-contract>

## Code Map

- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- table ends at #47 (line 51); #38 at line 42 (Lancer/Bastion start-to-start).
- `.../gdd.md:189` -- damage table row "Contact with small or medium enemy or asteroid | 1 heart (the enemy is destroyed)"; line 190 large asteroid 2 hearts.
- `game/entities/player/player.gd:375-410` -- as built: asteroid contact costs `contact_<size>_hearts`, the asteroid is never destroyed and is remembered (it hits again when the i-frames end if still overlapping). Read-only evidence.
- `_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md:100` -- "headline centred at y 440"; `game/ui/menus/retry_prompt.gd:165` puts the label's top at `ui.retry_prompt.headline_y` (440).
- `game/data/tuning.json` -- S3 keys: `energy.orb_magnet_speed_px_s` 600, `energy.orb_diameter_px` 24, `energy.orb_spread_px` 32, `abilities.barrage.speed_px_s` 800, `.turn_rate_deg_s` 540, `.lifetime_s` 3.0, `debug.energy_add` 100 (F4). Top-level `ui` section (retry_prompt, title, level_select, pause_menu, comms_panel, comms_box, hint_pill). Boss: `boss.turrets` fire_interval_s 3.0 / telegraph_s 0.5; `boss.core` radial_interval_s 3.0 / charge_s 0.6; `boss.desperate` radial_interval_s 1.5 / radial_charge_s 0.4, aimed_interval_s 2.0 / aimed_telegraph_s 0.3; `enemies.wasp` dive_interval_s {3.0, 5.0} / telegraph_s 0.4.
- `game/entities/enemies/wasp/wasp_dive_clock.gd` -- the dive clock orders a dive (telegraph first) at each deadline, so the Wasp interval is already start-to-start including the telegraph. No code change needed.
- `epics.md:133` FR49 (turrets every 3.0 s after 0.5 s glow) matches `boss.turrets`; FR51 (`epics.md:135`, GDD `gdd.md:285`) "every 1.5 s after a 0.4 s glow" is the **desperate radial**, matching `boss.desperate`. DW-69's reason misattributes FR51 to the turrets: no tuning difference exists.
- `_bmad-output/planning-artifacts/epics.md:785-787` -- Story 2.5 Lancer AC; `:831-833` Story 2.7 Bastion AC, same "timer reaches → glows → fires" wording.
- `_bmad-output/game-architecture.md:1190` -- Flagship bullet (boss section); `:1188` telegraph rule.
- `game/tests/data/test_data_files.gd:277-362` -- tuning range tests; Lancer/Bastion `telegraph_s <= fire_interval_s` asserts at 297/335 are the pattern to follow. Header comment lines 1-12 list what the file checks.

## Tasks & Acceptance

**Execution:**
- `game/tests/data/test_data_files.gd` -- add `test_wasp_and_boss_telegraphs_fit_their_periods()`: each interval > 0 and `enemies.wasp.telegraph_s <= dive_interval_s.min`, `boss.turrets.telegraph_s <= fire_interval_s`, `boss.core.charge_s <= radial_interval_s`, `boss.desperate.radial_charge_s <= radial_interval_s`, `boss.desperate.aimed_telegraph_s <= aimed_interval_s`, with a `# Decision #50 (DW-69)` comment; mention it in the header comment -- DW-69 data test.
- `decision-log.md` -- append #48 (S1 asteroids survive contact + GDD table amended; S2 DESIGN.md:100 reworded), #49 (S3 tuning values and top-level `ui` section, mirroring #33), #50 (#38 extended to Wasp, `boss.turrets`, `boss.core`, `boss.desperate`; data test; architecture note; boss.turrets matches FR49 and FR51's 1.5/0.4 is the desperate radial, so no tuning difference). Amend #38's text to note the Story 2.5 / 2.7 AC rewording (DW-70) and its extension by #50 -- DW-57/69/70.
- `gdd.md:189` -- row reads "1 heart (the enemy is destroyed; an asteroid is not, decision #48)"; also note large asteroids survive in row 190 -- DW-57 S1.
- `DESIGN.md:100` -- "headline top at y 440" -- DW-57 S2.
- `epics.md:785-787` and `:831-833` -- reword to "fires every 2.0 s start-to-start (decision #38): its muzzle glows for 0.3 s inside that period, then it fires ..." and the Bastion equivalent (2.5 s, 0.5 s glow) -- DW-70.
- `game-architecture.md:1190` area -- add a Flagship cadence bullet: every boss interval is start-to-start and includes its glow/charge (decision #50), enforced by the data test -- DW-69.

**Acceptance Criteria:**
- Given the decision log, when read, then rows #48-#50 exist with the values above and #38 names the AC amendment and #50.
- Given the GUT suite run headless, when it finishes, then all tests pass including the new data test.
- Given a tuning edit setting `boss.desperate.radial_charge_s` above `radial_interval_s`, when the data test runs, then it fails.
- Given `git diff`, when inspected, then no `.gd` outside `tests/`, no `tuning.json` and no ledger file changed.

## Spec Change Log

## Review Triage Log

### 2026-10-10 — Review pass
- verdicts: 19 findings — high 0, medium 0, low 8, false 11, maybe-false 0
- findings:
  - `[low]` `[defer]` (blind) Flagship story ACs (epics.md 1654/1688/1724) keep the pre-#38 "after a glow" wording — pre-existing wording; the operator's DW-69 decision chose the decision log, architecture note and data test as the surfaces; rewording Epic 7 ACs needs operator approval. Deferred.
  - `[false]` `[reject]` (blind) #50 cites the "every 3.0 s after a 0.5 s glow" FR49 phrasing as proof of a match — under #38/#50 that phrasing reads start-to-start, exactly as #38 says the Lancer/Bastion GDD lines "hold as written"; 3.0/0.5 matches FR49.
  - `[false]` `[reject]` (blind) FR9 and the Epic 3 contact AC imply the asteroid is destroyed — both say "the enemy is destroyed" (epics.md:66, :891), which matches as built; nothing says the asteroid is.
  - `[low]` `[reject]` (blind) GDD table omits the re-hit after i-frames — implementation detail recorded in #48 and the architecture, and it already applies to the Bastion; not worth more GDD text.
  - `[false]` `[reject]` (blind) Story 2.4 Wasp AC keeps a sequential shape #50 replaces — the AC (deadline, then telegraph, then dive) is exactly the as-built start-to-start behaviour of WaspDiveClock.
  - `[low]` `[patch]` (blind) Wasp rule placed in the Flagship bullet; `<=` instead of `≤` — moved the sentence to the Wasp "Dive cadence" bullet citing #50 and used `≤`.
  - `[false]` `[reject]` (blind) Wasp pair in the test checks a relation the runtime never relies on; duplicates `min > 0` — the DW-69 decision explicitly requires the Wasp in the data test; the extra > 0 assert is harmless.
  - `[false]` `[reject]` (blind) Nothing shows the "test fails" AC was checked — the implementer set `boss.desperate.radial_charge_s` to 2.0, saw the test fail ("2.0 <= 1.5"), then restored tuning.json (unchanged in git).
  - `[false]` `[reject]` (blind) #49 claims an architecture change that didn't happen; `ui` subsections appear nowhere — `ui` is in the fixed list (game-architecture.md:1210) and every subsection is documented in the as-built blocks (:350, :1589, :1652, :1677, :1688, :1710, :1720); #49 records that history.
  - `[low]` `[patch]` (blind) #48 S1 sentence mixes enemies into the asteroid clause — reworded: an asteroid of any size costs contact_<size>_hearts and survives contact, unlike a small or medium enemy.
  - `[false]` `[reject]` (blind) Spec Code Map relies on line numbers — the fix would edit this build's spec.
  - `[low]` `[defer]` (edge) epics.md:1724 boss AC wording — same root cause as the first row; deferred with it.
  - `[low]` `[defer]` (edge) gdd.md:285 boss cadence wording — same root cause as the first row; deferred with it.
  - `[low]` `[patch]` (edge) test header says "every boss timer's telegraph" but only telegraph pairs are checked — reworded to "every boss telegraph, glow or charge".
  - `[low]` `[patch]` (edge) #50 says "every enemy and boss timer" without naming the Needle or untelegraphed timers — added that the Needle already works this way (own test) and timers without a telegraph (e.g. wasp_launch_interval_s) are unaffected.
  - `[low]` `[defer]` (intent) boss cadence wording on the FR/GDD/AC surfaces not propagated (reading R3) — same root cause as the first row; deferred with it.
  - `[false]` `[reject]` (intent) Wasp test enforces a relation the runtime doesn't rely on — mandated by the DW-69 decision (same as the blind row).
  - `[false]` `[reject]` (intent) negative AC not shown as exercised — exercised by the implementer (see the blind row).
  - `[false]` `[reject]` (intent) GDD row 190 doesn't say the Bastion survives contact — outside the intent (asteroids only) and pre-existing; the small/medium row already implies large enemies aren't destroyed.

## Design Notes

`boss.core` is included though the intent names only turrets/desperate/Wasp: the DW-69 decision title is "Extend #38 to all enemy and boss timers", and the core's 3.0/0.6 pair is a boss timer.

## Verification

**Commands:**
- `"<GODOT_DIR>/Godot_v4.7.2-stable_win64_console.exe" --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` -- expected: all tests pass.

## Auto Run Result

Status: done

**Summary:** Docs-as-built sync for DW-57, DW-69 and DW-70, plus one GUT data test. No gameplay code or tuning changed; the deferred-work ledger and sprint board were not touched.

**Files changed:**
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/decision-log.md` -- #38 notes the DW-70 AC amendment and #50; new rows #48 (asteroids survive contact; retry headline top at y 440), #49 (Epic 3 tuning values and the `ui` section), #50 (#38 extended to the Wasp, boss.turrets, boss.core, boss.desperate; no FR49/FR51 tuning difference).
- `_bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md` -- damage table contact rows: asteroids survive (#48).
- `_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/DESIGN.md` -- retry prompt "headline top at y 440".
- `_bmad-output/planning-artifacts/epics.md` -- Story 2.5 and 2.7 ACs say start-to-start with the glow inside the period (#38).
- `_bmad-output/game-architecture.md` -- new "Flagship cadence" bullet; the Wasp "Dive cadence" bullet cites #50.
- `game/tests/data/test_data_files.gd` -- new `test_wasp_and_boss_telegraphs_fit_their_periods` (5 telegraph/interval pairs) and header comment.

**Review:** 19 findings: 4 low patched (architecture Wasp sentence and `≤`; #48 wording; #50 Needle/untelegraphed clause; test header wording); 1 low entry deferred (Epic 7 boss AC / GDD boss cadence wording, 4 rows); 1 low rejected (GDD re-hit detail); 11 rejected as false (reasons in the triage log). Patched by verdict: high 0, medium 0, low 4. A pre-existing intermittent test was also deferred (see residual risks).

**Follow-up review recommended:** false (no high or medium patched).

**Verification:** `--import`, then three full headless GUT runs on the changed tree: 1585/1586 (DW-79 `test_shake_camera` flake), 1584/1586 (`test_level` Maul y flake, 1 pending), and 1585/1586 with 0 failures (1 pending). `test_data_files.gd` 53/53 after the patches. The new test fails when `boss.desperate.radial_charge_s` is raised above `radial_interval_s` (checked by the implementer, tuning restored).

**Residual risks:** `test_level.gd::test_dev_convoy_maul_wave_hits_the_convoy` is intermittent (deferred). Epic 7 boss ACs still use the older "after a glow" phrasing (deferred, needs operator approval).
