---
title: 'Epic 7 playtest I: a music track per level, a medium explosion sound, and Joth for the final Flagship blast'
type: 'feature'
created: '2026-10-14'
status: 'done'
baseline_commit: '9956f9e'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** every level shares one dated "combat" track. The boss chain and the convoy chain lack a proper medium blast, and the operator wants Joth's full "Chunky Explosion" as the final Flagship blast.

**Approach:** the operator chose these on 2026-10-14 from the audition folder.
- **Per-level music:**
  - Level 1: Holizna "Retro Soundtrack"
  - Level 2: G_P "synthwave"
  - Level 3: tricksntraps "Anti Matter Magic"
  - The boss track is unchanged.
- **New `explosion_mid` sound** (EZduzziteh "explosion3", CC0) for:
  - the boss chain's first three blasts
  - every convoy chain blast
  - the turret (`boss_part`) kills
- **Final Flagship blast:** Joth's untrimmed "Chunky Explosion", as the new `explosion_boss_death`.

## Boundaries & Constraints

**Always:**
- Every track and sound is reproducible from `tools/import_cc0_audio.py`, with its sha256 checked, and credited.
- Music is transcoded to OGG Vorbis at a modest quality, so the repo and export don't balloon. Each track is imported looping.
- Volumes are levelled through `audio.music_gain_db` where a track is much quieter or louder than the others.
- The operator's unstaged tuning and flag edits are never staged.

**Ask First:** none (the operator's picks).

**Never:** change any gameplay timing.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior |
|---|---|---|
| Level 1, 2 or 3 starts | wave 1 trigger | that level's own track plays |
| Boss wave | the boss trigger | the unchanged boss track |
| Retry | a level reloads | its own track again |
| Boss death | the chain | three `explosion_mid` blasts, then the full Joth blast |
| Convoy lost | the chain | `explosion_mid` blasts |

</frozen-after-approval>

## Code Map

- `game/autoloads/audio.gd`: the MUSIC registry (new ids `level_1`, `level_2` and `level_3`, or similar; drop or keep `combat` as dev-level fallback)
- `game/systems/waves/level_validator.gd`: `MUSIC_ACTIONS`
- `game/data/levels/level_*.json`: the wave `music` triggers, plus the dev levels
- `game/data/tuning.json`: `feedback.boss_death_chain_sfx`, `convoy_death_chain_sfx`, `tiers.boss_part.sfx`, `audio.music_gain_db`
- `tools/import_cc0_audio.py`, `game/assets/CREDITS.md`, `README.md` credits

## Tasks & Acceptance

**Execution:**
- [x] the import tool, the assets and the credits
- [x] the registry, the validator, the level data and the tuning
- [x] tests and the decision-log row

**Acceptance Criteria:**
- Given the full suite on the staged data, when GUT runs, then everything passes.

## Spec Change Log

- 2026-10-14, merge and review:
  - The import tool keeps its layered machinery for playtest J's `tarek_burn`, now its only layered source. The registry holds 21 SFX ids.
  - The README credits restore the AntumDeluge and Spring Spring lines that the merge dropped.
  - Deferred: DW-112 (SFX hashes are never checked).

## Suggested Review Order

- The level tracks are transcoded through the tool (q4) with sha256 checks.
  [`import_cc0_audio.py:1`](../../tools/import_cc0_audio.py#L1)
- The MUSIC registry and the per-level ids.
  [`audio.gd:1`](../../game/autoloads/audio.gd#L1)
- The chain rows and the turret blasts use `explosion_mid`; the final blast is Joth's.
  [`tuning.json:1`](../../game/data/tuning.json#L1)
