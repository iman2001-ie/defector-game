# Epic 5 Context: Comms and Story Delivery

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Deliver DEFECTOR's story without ever leaving the action. This epic builds the single comms delivery path: an opening comms-only scene, paused story lines (briefings, debriefs, the surrender offer) in a centred panel, rare non-pausing combat interruptions in a top-left box, Isolde's flag-gated taunts and surrender prompt, the mid-sentence cut-off (static, shake, silence, music drop), data-driven triggering of dialogue, story events and music from wave moments, the final dialogue script, and on-screen control hints that teach the controls in Level 1. It realises the "story through comms" pillar and gives Epics 6 and 7 (Tarek's fall, level beats, Final Choice) the machinery they depend on. Tier: MUST for the panel, data, cut-off, opening, script and hints; SHOULD for interruptions and the surrender prompt.

## Stories

- Story 5.1: Read Story Lines on the Comms Panel
- Story 5.2: Hear Combat Chatter Without Stopping the Fight
- Story 5.3: Trigger Dialogue and Music from Wave Events
- Story 5.4: Cut a Line Off Mid-Sentence
- Story 5.5: Open the Campaign with the Comms Sequence
- Story 5.6: Let Isolde Interrupt and Tempt Surrender (SHOULD)
- Story 5.7: Write the Dialogue Script
- Story 5.8: Learn the Controls from On-Screen Hints

## Requirements & Constraints

- **Dialogue model:** story lines (opening, briefings, debriefs, surrender offer, Final Choice lead-in) pause the game, dim the playfield and advance on click. Combat lines (interruptions) are single short lines that auto-dismiss without pausing; at most 2 per level (excluding the Tarek cut-off line), only Isolde mocking or an ally warning. Only two mid-fight pauses exist in the whole game: the L1 surrender offer and the L3 Final Choice.
- **Data limits (enforced by data tests):** every `combat` sequence has exactly 1 line of at most 50 characters; story lines at most 200 characters; known speakers only (`vale, isolde, tarek, ryn, system`); valid mode; non-empty lines; every sequence id referenced by any level JSON must exist.
- **Opening:** 6-10 lines, comms-only on a static space background, cursor visible. Establishes Vale's defection, Tarek welcomes the General and briefs the convoy mission, Isolde speaks one cold line. No narrator, no text crawl. Plays every time Level 1 is started from Play or Level Select, never on retry or restart.
- **Briefings** (`intro_sequence`) are skipped on retry/restart (`GameState.is_retry`); the outro plays before `level_cleared`.
- **Surrender prompt:** "You're outnumbered, General. Come home.", no choice offered, pauses the game; reinforcements (4 Mauls) arrive whether or not the prompt flag is on. Interruptions and the surrender prompt sit behind `isolde_interruptions` / `surrender_prompts` flags in `flags.json`.
- **Cast rules for the script:** Vale is gender-neutral, addressed as "General", speaks only a few lines (including the surrender offer); every character introduces themselves in their own voice; tone is personal, not comedic. No voice acting.
- **Control hints:** `MOVE THE MOUSE TO FLY` then `[HOLD LMB] FIRE` (W1), `[RMB] MISSILE` (W2), `[E] SHIELD` / `[Q] BARRAGE` on first reaching 50 / 100 energy. Never pause, never use the comms panel. Fade on action performed or after 5 s; each shows once per session (retries don't repeat). If energy never fires, E/Q hints never show. Goal: a first-time player understands controls by L1 W2 without verbal help.
- Every scripted story beat must fire in every playthrough; nothing may wait forever (no soft-locks).
- Placeholder portraits are fine until Epic 8; placeholder text is fine until Story 5.7.

## Technical Decisions

- **Custom Comms Channel, no dialogue plugin.** `CommsChannel` (`Node`, `PROCESS_MODE_ALWAYS`, under the `Comms` CanvasLayer, layer 20) owns the queue, mode logic, pause reasons, silence flag and emits `comms_sequence_finished`. `CommsPanel` (`Control`) shows portrait, name and a typewriter label (`visible_characters` tween). Only `CommsChannel` sets dialogue text; all dialogue is requested only via `Events.comms_sequence_requested`.
- **Events:** `comms_sequence_requested(sequence_id)`, `comms_sequence_finished(sequence_id)`, `story_event_requested(event_name)`. New global signals go into `Events` first.
- **Story sequence:** `PauseArbiter.push(&"story")`, type at `tuning.comms.chars_per_s` (45). Click while typing completes the line; next click advances; after the last line `PauseArbiter.pop(&"story")` and emit finished. The advance click is consumed with `set_input_as_handled()` in `_unhandled_input`; the laser only fires while unpaused. Esc during a story line adds `&"menu"`; closing the menu leaves the story pause in place.
- **Combat sequence:** no pause, input ignored; each line stays `max(2.0, chars / chars_per_s + 1.2)` s.
- **Priority:** story preempts a playing combat line (the dropped combat sequence still emits finished); combat-on-combat queues FIFO, max 3, oldest dropped; story-on-story queues and is never dropped.
- **Cut-off:** line fields `cut_off_at` and `after` (`silence`, `shake`, `sfx`, `music`). Typewriter stops at exactly `cut_off_at` chars, then `comms_static` SFX, `Feedback` shake tier, music stop, silence; panel hides after 0.6 s. While silenced, combat sequences are dropped (logged at DEBUG); story still delivered; `until_wave_clear` clears on `Events.wave_cleared`.
- **Unknown sequence id:** `Log.error` and emit `comms_sequence_finished` in the same frame but deferred (`call_deferred`), so a caller that emits the request and then awaits `finished` cannot miss it.
- **Dialogue data:** `data/dialogue/<scene>.json` (`opening.json`, `level_1.json` ...), shape `{ "sequences": { id: { "mode", "lines": [{ "speaker", "text", ... }], "choice"? } } }`. Access only via `Config.sequence(id)` and `Config.dialogue_is_story(id)`, validated at load. Ids follow `<scene>_<beat>` (e.g. `opening_main`, `l1_w5_surrender`, `l2_w5_tarek_cutoff`).
- **WaveDirector actions** (`_run_actions`): `comms` (story mode awaits `comms_sequence_finished`; combat does not block), `story_event` (emits `story_event_requested`), `music` (`stop` | `combat` | `boss` via `Audio.apply_music_action()`; stop fades 0.5 s; a missing stream logs a warning and stays silent), plus existing `spawn_group` and `wait`. Story 5.8 adds a `hint` action. Triggers support an optional `flag` with `!` negation. A wave clears only when all counted enemies resolve **and** all its action chains finish. Death reloads the scene, discarding all chains. F3 debug resolve fires remaining progress triggers in order.
- **Audio:** music is not built yet; this epic adds music play/stop/fade to the `Audio` autoload (Music bus exists). SFX via `Audio.play_sfx(id, ...)`; unknown ids warn once.
- **Pausing and time:** only `PauseArbiter` pauses (reasons `menu`, `story`, `final_choice`, `death`) and owns mouse mode; only `Feedback` touches time scale and shake. Scene roots must declare their gameplay mouse mode (the story scene needs a visible cursor).
- **Scene flow:** `scenes/story/story.tscn` + `SceneRouter.goto_story(id, next)`; only `SceneRouter` changes scenes. Code lives in `systems/comms/`, `scenes/story/`, `data/dialogue/`, `data/flags.json`.
- Logging through `Log` with category `comms` / `beat`; no bare `print()`. All timings and limits come from `tuning.json` via `Config`, never hard-coded.

## UX & Interaction Patterns

- One rule for the player: a centred panel over a dimmed screen means read and click; a small corner box means glance if you like.
- **Story panel:** centred at (410, 300), 1100x300, over a 60% dim; 200 px portrait left, name in speaker accent (uppercase), 30 px sentence-case typewriter text, `click to continue ▸` cue (lowercase, muted) bottom-right; no buttons; click anywhere advances; opens with the comms-open SFX. No-portrait variant for Vale and system (text spans full width). HUD stays visible but frozen.
- **Interruption box:** top-left (32, 24, 560x96); 4 px speaker-accent left edge, 72 px portrait, name, 24 px text, max 2 wrapped lines, clipped; types at 45 chars/s (so a cut-off stops mid-word); slides in from the left over 0.15 s, fades out; ignores the mouse.
- **Opening scene:** no HUD, no dim, static space backdrop, visible arrow cursor, Esc does nothing; ends by loading Level 1.
- **Hint pill:** centred at y 560, 52 px tall, fully rounded, key glyph in energy gold, action in text colour; fades in 0.2 s; only one pill at a time, a newer hint waits. Move hint dismisses after 150 px of movement; fire hint on first shot.
- Speaker accents: isolde #FF6AE3, tarek #3DF2FF, ryn #7CFFB2, vale #E8F4FF, system #93A7C2. All styling through the single Theme; the comms portrait frame is the only allowed per-node override.

## Cross-Story Dependencies

- 5.1 builds the channel, panel and dialogue data loading that 5.2, 5.4, 5.5 and 5.6 extend; `comms_channel.gd` grows across 5.1-5.4 (and 7.5 for the Final Choice).
- 5.3 extends the Epic 2 WaveDirector (`wave_director.gd`, again in 7.3); 5.4 and 5.6 rely on its `comms`/`music` actions and flag-gated triggers; 5.8 adds the `hint` action.
- 5.5 depends on Epic 4's `SceneRouter`, title and level select, and `GameState.is_retry`.
- 5.7 fills the final script for ids used by Epics 6-7 (Tarek cut-off, Ryn report, L3 briefing, Final Choice lines); placement of Isolde beats, the surrender prompt and hints into real levels happens in Epic 7.
- 5.8's E/Q hints depend on Epic 3's `Events.energy_changed`.
- Epic 6 Tarek's fall uses the 5.4 cut-off plus a `tarek_fall` story event; Epic 7's Final Choice (`final_choice` pause reason, `FinalChoice` buttons) builds on this channel.
