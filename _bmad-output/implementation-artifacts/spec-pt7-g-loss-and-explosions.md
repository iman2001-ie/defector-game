---
title: 'Epic 7 playtest G: the convoy explodes, a game-over sting on every loss, and big explosion sounds'
type: 'feature'
created: '2026-10-14'
status: 'done'
baseline_commit: '9fb17f2'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:**
- When the convoy's HP reaches 0, nothing visible happens before the retry prompt.
- A loss has no audio identity: the combat music just keeps playing under the prompt.
- The Flagship death chain sounds muffled. Its boom sounds are mostly sub-bass rumble, and some are pitched down further.

**Approach:**
- **Convoy death:** the moment the convoy dies, its ships blow up one after another in a slow chain. The ships vanish as they explode. The retry prompt waits until the chain has finished (about 3 s in all).
- **Every loss** (convoy, hearts or surrender): the music fades out, and a short CC0 game-over sting plays when the retry prompt appears. The provisional pick is Kistol's "Game Over"; the operator picks the final one from the audition folder.
- **Explosion sounds:** new CC0-based big-explosion sounds, built from Joth's "Chunky Explosion" layered with Kenney's crunch transient and a low boom, with a long tail. They replace the muffled boss sounds, and the chain rows stop pitching below 0.9. The convoy chain uses the same big sound.

## Boundaries & Constraints

**Always:**
- Data-driven: chain timings, sound rows, per-reason prompt delays and volumes live in `tuning.json`.
- Only Spawner creates explosions, through Feedback.
- Only Feedback touches time_scale.
- Assets are reproducible from `tools/import_cc0_audio.py` and credited in `CREDITS.md`.
- The operator's unstaged balance edits are never staged.

**Ask First:** none. The operator asked for these on 2026-10-14.

**Never:**
- Change the outcome latching: `level_failed` still fires at once, so waves stop and the reason is fixed.
- Change the retry flow or its texts.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior |
|---|---|---|
| Convoy lost | convoy HP reaches 0 | `level_failed(convoy)` fires at once; each ship explodes in turn over `feedback.convoy_death_chain_s` and hides; the prompt shows after `feedback.loss_pause_s.convoy`, after the chain ends |
| Hull destroyed | player dies | as now (prompt after `loss_pause_s.hearts`), plus the music fade and the sting |
| Surrender | the SURRENDER choice | the music fades and the sting plays when the prompt shows |
| Retry | RETRY pressed | the level reloads and its own music trigger replaces the sting |
| Quit | QUIT TO TITLE | `goto_title` fades the sting out |
| Boss death | the chain | every row plays the new big sounds at pitch ≥ 0.9 |

</frozen-after-approval>

## Code Map

- `game/entities/allies/convoy.gd:158-166` -- HP reaches 0 and emits level_failed; ships(), hull_rect()
- `game/autoloads/feedback.gd:271-303` -- the boss chain machinery to generalise or reuse for the convoy (`step_chain` runs only while unpaused)
- `game/ui/menus/retry_prompt.gd:64,135-140,119-132` -- the beat timer and show_prompt
- `game/autoloads/audio.gd` -- MUSIC registry (add `game_over`, imported with loop off)
- `game/data/tuning.json` -- `feedback.player_death_pause_s` becomes or gains per-reason `loss_pause_s`; new chain keys; boss chain rows
- `tools/import_cc0_audio.py` -- composite explosion build and the sting import

## Tasks & Acceptance

**Execution:**
- [x] audio assets: `sfx_explosion_big.wav` (Joth, normalised), a new layered `sfx_explosion_boss_death.wav`, and `music_game_over.ogg` (Kistol, loop off), reproducibly; credits
- [x] Feedback: a convoy death chain over the given ship positions (its own `convoy_death_chain_s` and sfx rows), hiding each ship as it blows
- [x] convoy: start the chain at HP 0
- [x] retry prompt: per-reason delay; music fade on fail; the sting on show
- [x] tuning: the boss chain rows (big sounds, pitch ≥ 0.9), convoy chain keys, `loss_pause_s`
- [x] tests for the matrix, plus the data shape
- [x] docs: a decision-log row, CREDITS, the architecture as-built

**Acceptance Criteria:**
- Given the full suite on the staged tuning, when GUT runs, then everything passes.

## Verification

**Commands:**
- import, then the full GUT run; `tools/test_import_cc0_audio.py`

## Spec Change Log

- 2026-10-14, review: patches applied.
  - `loss_pause_s.convoy` 3.2 -> 3.8, because the last slowed blast outlived 3.2 s. The data test now includes the explosion lifetime.
  - `explosion_big` is trimmed to 3.0 s.
  - The chain rows play with no pitch jitter (pitch stays ≥ 0.9).
  - The wreck stays solid until `is_wrecked()`.
  - Safe ship lookups.
  - `convoy_death` with no Large tier clears the ships.
  - A one-shot track ending clears the music id.
  - The logo scenes' authored texture_filter is fixed to 4.

## Suggested Review Order

**Loss sequence**

- The retry prompt fades the music on any loss and plays the sting when it shows.
  [`retry_prompt.gd:156`](../../game/ui/menus/retry_prompt.gd#L156)
- The convoy chain shares the boss-chain machinery and hides each ship per step.
  [`feedback.gd:323`](../../game/autoloads/feedback.gd#L323)
- The convoy latches the loss, then explodes lead first.
  [`convoy.gd:191`](../../game/entities/allies/convoy.gd#L191)
- The wreck stays solid until its last ship blows.
  [`convoy.gd:207`](../../game/entities/allies/convoy.gd#L207)

**Explosion sounds**

- Chain rows play at their exact pitch, with no jitter.
  [`feedback.gd:419`](../../game/autoloads/feedback.gd#L419)
- The layered boss-death recipe is reproducible from the tool.
  [`import_cc0_audio.py:138`](../../tools/import_cc0_audio.py#L138)
