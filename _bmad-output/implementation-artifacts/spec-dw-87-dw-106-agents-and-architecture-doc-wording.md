---
title: 'DW-87, DW-88, DW-89, DW-106: AGENTS.md and architecture doc wording'
type: 'chore'
created: '2026-10-14'
status: 'done'
baseline_revision: '1c80e1b8e7be4bdefb5bf7f611f145eb217eeb33'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/game-architecture.md'
  - '{project-root}/.claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md'
warnings: []
deferred:
  - summary: >-
      The Story 8.2 as-built LevelBackground and Level Select bullets still describe the planet arc as drawn by `_draw` after the tiles, with no pointer to the playtest-F section.
    evidence: |-
      game-architecture.md (As-built 2026-10-13 (Story 8.2)) says "`_draw` tiles the texture, then draws the throne world's arc"; the arc is now the `Planet` ColorRect running throne_world.gdshader (level_background.gd planet_rect, PLANET_SHADER). Pre-existing; the playtest-F section's "supersedes the earlier as-built notes on the planet arc" covers it only implicitly.
    location: >-
      _bmad-output/game-architecture.md:2119-2120
    severity: low
  - summary: >-
      The architecture's current-design trees still describe the old arc: the scene tree's Background comment and the asset tree's "the throne-world arc is drawn in code over space_2", and neither lists starfield.gdshader or throne_world.gdshader.
    evidence: |-
      game-architecture.md:274 "tiled space texture (+ throne-world arc)"; :678 "(the throne-world arc is drawn in code over space_2)". The playtest-F visual pass added `Stars` (starfield.gdshader) and `Planet` (throne_world.gdshader) ColorRect children. Pre-existing, not caused by this bundle.
    location: >-
      _bmad-output/game-architecture.md:274, 678
    severity: low
  - summary: >-
      AGENTS.md section 5 now covers first-pass hand-written retros, but its only example is a revision (`Epic 1 retro: revision 2`), so the first-pass message shape must be guessed.
    evidence: |-
      AGENTS.md:63 "hand-written retros (first pass or revision) ... (e.g. `Epic 1 retro: revision 2`)". Adding a first-pass example such as `Epic 4 retro` would settle it. The fix edits AGENTS.md (agent-context file).
    location: >-
      AGENTS.md:63
    severity: low
  - summary: >-
      AGENTS.md section 5 does not say which commit form applies to a retro an agent writes interactively at a person's request (neither bmad-loop/orchestration nor strictly hand-written).
    evidence: |-
      AGENTS.md:62 covers "retro commits made by bmad-loop or orchestration" (`chore(retro): ...`); AGENTS.md:63 covers "hand-written retros (first pass or revision)" (plain summary). An interactive bmad-retrospective / gds-retrospective run fits neither label cleanly. The fix edits AGENTS.md (agent-context file).
    location: >-
      AGENTS.md:62-63
    severity: low
  - summary: >-
      "change them all together" still groups the short-form export comment with the full copy, so it is not explicit that a trigger-list edit only needs the full copy changed.
    evidence: |-
      AGENTS.md:30 and the headless CLI block now call the export block's import comment a short form that points back, but both keep "change them all together"; the short form holds no trigger list. Wording such as "change the full copy with every edit, and the short form when its first clause or the source location changes" would make it explicit. The fix edits AGENTS.md (agent-context file).
    location: >-
      AGENTS.md:30; _bmad-output/game-architecture.md:1469-1471
    severity: low
  - summary: >-
      The `EDGE_MARGIN_PX` doc comment in level_background.gd says only that the planet's shader rect starts this far above the top edge, though `planet_rect()` also extends it past both sides and `tile_rect()` grows the playfield by it on every side.
    evidence: |-
      game/scenes/level/level_background.gd:75-80 ("The planet's shader rect starts this far above the top edge, so the cap's cut top never shows") versus planet_rect() (:308) and tile_rect() (:295); the architecture's playtest-F bullet now says "past the top and side edges". Pre-existing code comment; this bundle is docs-only and may not change code.
    location: >-
      game/scenes/level/level_background.gd:75-76
    severity: low
  - summary: >-
      The `--import` trigger clause now says "a script that keeps its `class_name`" twice in a row, which a merged clause would avoid.
    evidence: |-
      AGENTS.md:30 and the headless CLI block in game-architecture.md read "changing the `extends` line or `@icon` of a script that keeps its `class_name`, or adding or removing `@abstract` or `@tool` on a script that keeps its `class_name`". A merged form such as "changing the `extends` line, `@icon`, `@abstract` or `@tool` of a script that keeps its `class_name`" reads shorter; both copies must change together. The fix edits AGENTS.md (agent-context file).
    location: >-
      AGENTS.md:30; _bmad-output/game-architecture.md:1472-1474
    severity: low
---

<intent-contract>

## Intent

**Problem:** Four small doc gaps, each with an operator decision dated 2026-10-14: the `--import` re-run triggers miss `@abstract`/`@tool` toggles (DW-87); the CLI export block's import comment is called a "copy" of the AGENTS.md note though it only repeats the first clause and points elsewhere (DW-88); AGENTS.md section 5 has no commit form for a first hand-written retro (DW-89); the architecture's Story 7.6 LevelBackground and Tests bullets still describe the old bottom-edge arc with no pointer to the current as-built, and the later visual-pass section doesn't state the 64 px margin (DW-106).

**Approach:** Docs-only wording edits in `AGENTS.md` and `_bmad-output/game-architecture.md`, applying each decision exactly, keeping the full-copy trigger lists in step and leaving historical as-built text untouched apart from appended pointers.

## Boundaries & Constraints

**Always:** Keep the AGENTS.md section 3 note and the headless CLI block copy saying the same triggers. Call the CLI export block's import comment a short form/pointer of the AGENTS.md note in all three places (the comment itself, the headless block's line about it, AGENTS.md's "copies" sentence). Match the existing italic `*(Story 8.2: ...)*` pointer style. Use placeholders only (`<GODOT_DIR>`); no machine-specific values.

**Never:** No code, data or test change. Don't rewrite the Story 7.6 history text (only append pointers). Don't edit the deferred-work ledger, `.bmad-loop/decisions.json` or the sprint board. Don't add triggers beyond `@abstract`/`@tool`.

</intent-contract>

## Code Map

- `AGENTS.md:30` -- the `--import` note (source). Holds "this note is the source for the copies in `game-architecture.md`'s headless CLI block and its CLI export block's import step, so change them all together" (DW-88) and the trigger parenthetical "or changing the `extends` line or `@icon` of a script that keeps its `class_name`" (DW-87).
- `AGENTS.md:63` -- "manual non-story work such as hand-written retro revisions and correct-course" (DW-89). Example `Epic 1 retro: revision 2` stays valid.
- `_bmad-output/game-architecture.md:1337-1339` -- CLI export block import comment: "Copy of the note in AGENTS.md section 3 (Project facts), Tests bullet, which is the source; see it or the headless CLI block ... for when to re-run." (DW-88)
- `_bmad-output/game-architecture.md:1469-1474` -- headless CLI block: "the CLI export block's import step (Deployment Architecture) is another copy; change them all together." (DW-88) and "changing the extends line or @icon of a script that keeps its class_name" (DW-87). Lines are `#` comments wrapped near 115 chars.
- `_bmad-output/game-architecture.md:2032` -- Story 7.6 LevelBackground bullet; ends with `*(Story 8.2: ... see As-built 2026-10-13 (Story 8.2).)*` (style to match; append the DW-106 pointer after it).
- `_bmad-output/game-architecture.md:2034` -- Story 7.6 Tests bullet; mentions "peaking 200 px above the bottom edge"; ends "only `level_3.json` uses `throne_world`)." (append pointer).
- `_bmad-output/game-architecture.md:2141-2149` -- section `## As-built 2026-10-14 (Epic 7 playtest F)` (decision log #71, "It supersedes the earlier as-built notes on the planet arc"); its LevelBackground sub-bullet "The planet is a shaded sphere cap (`PLANET_RADIUS_PX` 1100, `ARC_HEIGHT_PX` 180)..." lacks the margin.
- `game/scenes/level/level_background.gd:75-80` -- read-only evidence: `EDGE_MARGIN_PX` 64.0, "The planet's shader rect starts this far above the top edge, so the cap's cut top never shows. It must exceed the largest tuned screen shake ... which test_edge_margin_exceeds_every_tuned_shake checks." Also used by `tile_rect()` (line 296, playfield grown by the margin).

## Tasks & Acceptance

**Execution:**
- `AGENTS.md` -- (a) line 30: name the headless CLI block as the copy and the CLI export block's import step as a short form that points back here, keeping "change them all together"; add "or adding or removing `@abstract` or `@tool` on a script that keeps its `class_name`" beside the `extends`/`@icon` trigger. (b) line 63: replace "hand-written retro revisions" with "hand-written retros (first pass or revision)". -- DW-87, DW-88, DW-89.
- `_bmad-output/game-architecture.md` -- (a) CLI export import comment: call it a short form of (pointer to) the AGENTS.md note instead of a copy. (b) headless block: say the export block's import step is a short form that points here (not "another copy"), and add the same `@abstract`/`@tool` trigger, rewrapping the comment lines. (c) append an italic pointer to the 7.6 LevelBackground and Tests bullets: the arc now hangs 180 px down from the top edge (`EDGE_MARGIN_PX` 64); see As-built 2026-10-14 (Epic 7 playtest F). (d) add `EDGE_MARGIN_PX` 64 with its purpose to the playtest-F LevelBackground bullet. -- DW-87, DW-88, DW-106.

**Acceptance Criteria:**
- Given AGENTS.md section 3 and the headless CLI block, when an agent reads either trigger list, then both list adding or removing `@abstract` or `@tool` on a script that keeps its `class_name`, in the same words apart from markdown backticks.
- Given the CLI export block's import comment, the headless block's line about it and AGENTS.md's sync sentence, when read, then none calls the export comment a "copy"; all call it a short form/pointer of the AGENTS.md note, and the headless block is still the full copy to change together with the source.
- Given AGENTS.md section 5, when a person commits a first hand-written retrospective, then the "manual non-story work" bullet covers it ("hand-written retros (first pass or revision)").
- Given the Story 7.6 LevelBackground and Tests bullets, when read, then each ends with an italic pointer saying the arc now hangs from the top edge and naming As-built 2026-10-14 (Epic 7 playtest F), and their original text is unchanged.
- Given the playtest-F LevelBackground bullet, when read, then it states `EDGE_MARGIN_PX` 64, matching `level_background.gd:80`.
- Given the diff, when scanned, then only `AGENTS.md`, `_bmad-output/game-architecture.md` and this spec change, with no secrets or machine-specific values.

## Spec Change Log

## Review Triage Log

### 2026-10-14 — Review pass
- verdicts: 19 findings — high 0, medium 0, low 16, false 3, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) The 7.6 pointers only mention the arc's position, though its radius, centre and drawing method were also replaced — patched: both pointers now say the arc "is now a shader-drawn sphere cap hanging 180 px down from the top edge".
  - `[low]` `[patch]` (blind) Pointer's "starting `EDGE_MARGIN_PX` 64 above it" has an ambiguous "it" and an undefined "shader rect" — patched: reworded to "with an `EDGE_MARGIN_PX` of 64", no dangling pronoun.
  - `[low]` `[reject]` (blind) The Tests-bullet pointer should name the replacement tests — the decision asks for a short pointer to the playtest-F section; listing four test names exceeds it, and readers reach the current state through the pointer.
  - `[low]` `[defer]` (blind) Story 8.2 as-built bullets still describe `_draw` drawing the arc, with no pointer — pre-existing, not caused by this bundle; deferred.
  - `[low]` `[defer]` (blind) Scene tree (:274) and asset tree (:678) still describe the code-drawn arc and omit the shaders — pre-existing; deferred.
  - `[low]` `[patch]` (blind) New margin sentence says the rect only starts above the top edge; `planet_rect()` also extends past both sides — patched together with the edge-case tile_rect finding: names `planet_rect()`, "past the top and side edges".
  - `[false]` `[reject]` (blind) "Full copy" overclaims because the two texts differ slightly in phrasing — "full" means the complete note content (all clauses and every trigger), which the side-by-side check confirmed; the phrasing differences ("Run it on" / "Run on") pre-date this change and change no meaning.
  - `[low]` `[defer]` (blind) Section 5 adds first-pass retros but its only example is a revision — grouped with edge-case and intent findings; fix edits AGENTS.md (agent-context), so deferred.
  - `[low]` `[reject]` (blind) The AGENTS.md `--import` note is a long nested parenthetical — pre-existing structure; restructuring both copies into sub-bullets is a rewrite beyond the decisions, and the added clause does not change readability materially.
  - `[low]` `[reject]` (blind) The spec's `git grep` verification command has no path filter — fix edits this build's spec; the expected result is already scoped to the two files and the run used the filtered form.
  - `[low]` `[reject]` (blind) The spec's verification does not check DW-106 or the "short form" wording by command — fix edits this build's spec; the manual check and the diff read covered them.
  - `[low]` `[reject]` (blind) The spec cites `level_background.gd:80` and lists godot-testing.md as context — fix edits this build's spec; godot-testing.md is a required context entry by project rule.
  - `[low]` `[defer]` (edge) No commit form named for a retro an agent writes interactively at a person's request — fix edits AGENTS.md (agent-context); deferred.
  - `[low]` `[defer]` (edge) First-pass retro example missing — grouped with the blind-hunter finding; deferred.
  - `[low]` `[defer]` (edge) "change them all together" stays ambiguous for the short form on trigger-only edits — the decision kept the short form in the group; any sharper rule edits AGENTS.md (agent-context); deferred.
  - `[low]` `[patch]` (edge) Planet bullet says `tile_rect()` grows the playfield by the margin, but `tile_rect()` is the stars' rect and the planet uses `planet_rect()` — patched: "Its drawn rect, `planet_rect()`, extends ... The stars' `tile_rect()` grows the playfield by the same margin." (level_background.gd:295, 308-311).
  - `[false]` `[reject]` (intent) DW-106 pointers are longer than a "short" pointer — after the patch each is one sentence carrying only the position, the margin the decision asked to surface, and the section name.
  - `[false]` `[reject]` (intent) DW-88 implements R88a (short form stays in the "change them all together" group) rather than R88b — the decision says to describe it as a short form/pointer in the three named places, which the diff does; nothing in it asks to drop the sync rule.
  - `[low]` `[defer]` (intent) DW-89 example still shows only a revision — grouped with the first-pass example finding; deferred.

### 2026-10-14 — Review pass
Resumed run after the orchestrator's verify command (`--import` then the full GUT suite) failed with rc=1 on the committed tree. This session's two full GUT runs on the same tree both passed (2183/2183, rc=0), and the commit changes no file under `game/`, so the earlier failure was transient and not caused by this bundle. No repair was needed for it.
- verdicts: 18 findings — high 0, medium 0, low 12, false 4, maybe-false 0 (verification-gap: no gaps found)
- findings:
  - `[low]` `[patch]` (blind) In the playtest-F planet bullet, "Its colours and geometry are art constants." now follows the `tile_rect()` sentence, so "Its" reads as the stars — patched: "The planet's colours and geometry are art constants."
  - `[low]` `[patch]` (blind) "The stars' `tile_rect()`" names the wrong owner; `_draw` also tiles the space texture over it (level_background.gd:340) — patched: "`tile_rect()`, used by the tiled texture and the `Stars` child, grows the playfield by the same margin."
  - `[low]` `[reject]` (blind) The 7.6 LevelBackground pointer doesn't say the draw-once / no-per-frame-allocation claims are stale — the pointer's job is to send the reader to the superseding section, which states the per-frame game-time clocks; the decision asked for a short pointer, and listing every superseded claim would rewrite the note.
  - `[low]` `[patch]` (blind) The 7.6 pointer gives `EDGE_MARGIN_PX` 64 without saying where it applies, in a bullet where it is a 40 px chord below the bottom edge — grouped with the edge-case finding below; patched: both 7.6 pointers say "of 64 past the top and side edges".
  - `[low]` `[patch]` (blind) The Tests-bullet pointer talks about the arc, not the tests, though the listed arc-geometry assertions no longer exist — grouped with the edge-case finding below; patched: "and its arc-geometry tests changed with it" (no test names, per the earlier rejected row).
  - `[low]` `[defer]` (blind) The `EDGE_MARGIN_PX` code comment (level_background.gd:75-76) says only "above the top edge" while the doc now says top and side edges — pre-existing code comment; this bundle may not change code; deferred.
  - `[low]` `[defer]` carried (blind) "change them all together" still groups the short form with the full copy — matches the earlier deferred row (AGENTS.md:30 and the headless block still read as it describes). The finding's second claim, that "points back here" leaves out the headless block, is false: the export comment calls itself a pointer to the AGENTS.md note, which is the source; it mentions the headless block only as a second place to read.
  - `[low]` `[defer]` carried (blind) First-pass retro has no example — matches the earlier deferred row; AGENTS.md:63 still shows only `Epic 1 retro: revision 2`.
  - `[low]` `[defer]` (blind) The new trigger clause repeats "a script that keeps its `class_name`" — real but cosmetic; the fix edits AGENTS.md (agent-context file) and both copies; deferred.
  - `[low]` `[reject]` (blind) Spec frontmatter `status: in-review` / `review_loop_iteration: 0` disagrees with the logged review pass — fix edits this build's spec; the status is the workflow's live state, and the counter counts bad_spec loopbacks only (there were none).
  - `[false]` `[reject]` (blind) The five deferred items have no DW ids and are not in the ledger — the orchestrator has already filed them as DW-113 to DW-117 in `deferred-work.md`.
  - `[low]` `[patch]` (edge) Story 7.6 LevelBackground pointer: 64 next to the old 40 px below-screen chord reads as the same bottom margin — grouped with the blind finding above; patched.
  - `[low]` `[patch]` (edge) Story 7.6 Tests pointer: readers look for the "peaking 200 px above the bottom edge" tests that no longer exist — grouped with the blind finding above; patched.
  - `[false]` `[reject]` carried (intent) DW-88 implements reading 88a (short form stays in the "change them all together" group) rather than 88b — matches the earlier rejected row; the decision asks to describe the comment as a short form/pointer in the three named places, which the diff does.
  - `[low]` `[defer]` carried (intent) DW-89 example still shows only a revision — matches the earlier deferred row.
  - `[low]` `[reject]` (intent) The 7.6 pointers restate the 180 px / 64 px facts, so they could go stale apart from the playtest-F bullet — the pointers are dated historical notes ("Epic 7 playtest F: ...") and the decision asked to surface the margin; a later change would add its own dated note, as the Story 8.2 pointer did.
  - `[false]` `[reject]` (intent) The uncommitted `deferred-work.md` change (DW-113 to DW-117) may break the "don't edit the ledger" rule — it is the orchestrator's harvest of this spec's deferred list (origin `spec-deferred`), already present before this session started; this session did not touch the ledger.
  - `[false]` `[reject]` (intent) The working-tree spec differs from the committed one — that is the orchestrator resetting the status and removing the old result section for this resumed run, not a defect in the change.

## Verification

**Commands:**
- `git diff --stat` -- expected: only `AGENTS.md`, `_bmad-output/game-architecture.md` and this spec.
- `git grep -n -e "another copy" -e "Copy of the note" -e "retro revisions"` -- expected: no hits in `AGENTS.md` or `_bmad-output/game-architecture.md`.
- `git grep -n "@abstract" AGENTS.md _bmad-output/game-architecture.md` -- expected: one hit in each.

**Manual checks (if no CLI):**
- Read both edited trigger lists side by side; they must match. No GUT run is needed (no game file changes).

## Auto Run Result

Status: done

**Summary:** Resumed run after the orchestrator's verify command failed (rc=1) on the committed docs-only change. The bundle's work (commit `49c3d28e8bed24e721c8a3ca54adbd4bdf869463`) changes no file under `game/`, and this session's two full runs of the same verify command's GUT suite both passed (2183/2183 tests, rc=0, after a clean `--import`), so the failure was transient and needed no repair. The four operator decisions stay applied as before: the `--import` triggers include adding or removing `@abstract` or `@tool` (both full copies); the CLI export block's import comment is a short form of, and pointer to, the AGENTS.md note in all three places; AGENTS.md section 5 covers hand-written retros, first pass or revision; the Story 7.6 arc bullets point to the playtest-F as-built, which states `EDGE_MARGIN_PX` 64. A fresh review pass sharpened the DW-106 wording (four small patches).

**Files changed:**
- `AGENTS.md` -- section 3 import note (full copy / short form wording, `@abstract`/`@tool` trigger); section 5 retro commit wording (from the earlier commit; unchanged this session).
- `_bmad-output/game-architecture.md` -- CLI export import comment, headless CLI block comment, Story 7.6 pointers, playtest-F margin sentence; this session: both 7.6 pointers say "64 past the top and side edges", the Tests pointer says its arc-geometry tests changed, and the playtest-F bullet names `tile_rect()`'s two users and says "The planet's colours".
- `_bmad-output/implementation-artifacts/spec-dw-87-dw-106-agents-and-architecture-doc-wording.md` -- this spec (triage log, deferred items, result).

**Review findings:** 18 findings (low 14, false 4; verification-gap layer: no gaps). Patches applied: 6 low findings in 4 fixes (pronoun "Its" -> "The planet's"; `tile_rect()` owner; where the 64 px margin applies, in both 7.6 pointers; the Tests pointer notes the arc-geometry tests changed). Deferred: 5 (2 new: the `EDGE_MARGIN_PX` code comment at level_background.gd:75-76, code changes being out of scope; the repeated "a script that keeps its `class_name`" in the trigger clause, an AGENTS.md edit. 3 carried: short-form sync scope, first-pass retro example (blind and intent)). Rejected: draw-once claims not named in the 7.6 pointer (the pointer sends the reader to the superseding section; the decision asked for a short pointer); spec status/counter mismatch (fix edits this spec; the counter counts bad_spec loopbacks only); pointers restating 180/64 px could go stale (dated historical notes; the decision asked to surface the margin); false: deferred items not in the ledger (already DW-113 to DW-117); false (carried): DW-88 reading 88a vs 88b; false: uncommitted ledger change breaks the "don't edit the ledger" rule (orchestrator's harvest, there before this session); false: working-tree spec differs from committed (orchestrator's reset for this resumed run).

**Follow-up review recommendation:** false -- patched entries: high 0, medium 0, low 4 (6 findings).

**Verification:** `--import` then the full GUT suite (the orchestrator's verify command): `--import` rc=0; GUT run 1 rc=0 and run 2 rc=0, both "All tests passed" with 2183/2183 tests and 23716 asserts. Spec commands after the patches: `git diff --stat` since the baseline shows only `AGENTS.md`, `_bmad-output/game-architecture.md` and this spec, besides the orchestrator's ledger commit `51b3cf4` and its uncommitted DW-113 to DW-117 entries in `deferred-work.md`, which this session did not touch; `git grep` for "another copy", "Copy of the note" and "retro revisions" in the two files finds nothing; `@abstract` appears once in each. Both 7.6 bullets keep their original text; only the appended pointers changed. Margin facts checked against `game/scenes/level/level_background.gd` (`EDGE_MARGIN_PX` 64.0 at :80; `tile_rect()` used at :271 and :340; `planet_rect()` at :308).

**Residual risks:** the deferred items above. The earlier verify failure did not come back in two runs, so whatever caused it (likely a timing-sensitive test, since this change touches no game file) may come back in later runs. `_bmad-output/implementation-artifacts/deferred-work.md` stays modified in the working copy: it is the orchestrator-owned ledger (DW-113 to DW-117), which this session was told not to edit, so it is left for the orchestrator to commit.
