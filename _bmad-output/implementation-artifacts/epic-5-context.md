# Epic 5 Context: Comms and Story Delivery

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Deliver DEFECTOR's story without ever leaving the action. This epic builds the single comms delivery path: an opening comms-only scene, paused story lines (briefings, debriefs, the surrender offer) in a centred panel, rare non-pausing combat interruptions in a top-left box, Isolde's flag-gated taunts and surrender prompt, the mid-sentence cut-off (static, shake, silence, music drop), data-driven firing of dialogue, story events and music from wave moments, the final dialogue script, and on-screen control hints for Level 1. It realises the "story through comms" pillar and gives Epics 6 and 7 (Tarek's fall, level beats, Final Choice) the machinery they need. Tier: MUST for panel, data, cut-off, opening, script and hints; SHOULD for interruptions and the surrender prompt.

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

- **Dialogue model:** story lines pause the game, dim the playfield and advance on click; they wait indefinitely (no timed reading). Combat lines are single short lines that auto-dismiss without pausing; at most 2 per level (the Tarek cut-off line doesn't count), only Isolde mocking or an ally warning. Only two mid-fight story pauses exist in the game: the L1 surrender offer and the L3 Final Choice lead-in. Missing an interruption never blocks progress.
- **Data limits (data tests):** every combat sequence has exactly 1 line of at most 50 characters; story lines at most 200 characters; known speakers only (`vale, isolde, tarek, ryn, system`); valid mode; non-empty lines; every sequence id referenced by a level JSON must exist.
- **Combat line timing:** each line stays `max(5.0, chars/45 + 3.0)` s (raised from 2.0 / 1.2 after the operator check), then the box fades out over 0.6 s with an ease-out.
- **Radio cues:** a story sequence opens with `comms_open` (with the talk-permit beep); advancing to a different speaker plays `comms_handover`, same speaker `comms_click`; completing a typing line or closing plays nothing. Combat lines key in quieter (-4 dB): `comms_open_nobeep` when the box opens fresh, `comms_handover` / `comms_click` when following another combat line. The beep means only "the game paused for a story". No cue on fade; the cut-off's `comms_static` is separate.
- **Opening:** 6–10 lines, comms-only on a static space background, cursor visible. Establishes Vale's defection, Tarek welcomes the General and briefs the convoy mission, Isolde speaks one cold line. No narrator or text crawl. Plays every time Level 1 starts from Play or Level Select, never on retry or restart. It is Level 1's briefing (no separate L1 briefing).
- **Briefings** (`intro_sequence`) are skipped on retry/restart; the outro plays before the level clears, also on retry.
- **Surrender prompt:** "You're outnumbered, General. Come home.", no choice, pauses the game; reinforcements arrive whether or not the prompt is on. Interruptions and the surrender prompt are gated by the `isolde_interruptions` / `surrender_prompts` flags in `flags.json`.
- **Cast rules:** Vale is gender-neutral, addressed as "General", speaks only a few lines; every character introduces themselves in their own voice; tone personal, not comedic. No voice acting.
- **Control hints:** `MOVE THE MOUSE TO FLY` then `[HOLD LMB] FIRE`, `[RMB] MISSILE`, `[E] SHIELD` / `[Q] BARRAGE` on first reaching the ability cost in energy (50 / 100). Never pause, never use comms. Fade on action or after 5 s; each shows once per session (retries don't repeat). If energy never fires, E/Q never show. Target: a first-time player understands the controls by L1 W2.
- No soft-locks: every scripted beat must fire and nothing may wait forever. Placeholder portraits are fine until Epic 8.

## Technical Decisions

- **Custom comms, no plugin.** `CommsChannel` (`PROCESS_MODE_ALWAYS`, under the `Comms` CanvasLayer 20) owns the queue, modes, pause reasons and silence, and is the only thing that sets dialogue text. `CommsPanel` (story) and `CommsBox` (combat) are views. Dialogue is requested only via `Events.comms_sequence_requested`; completion is `comms_sequence_finished(id)`; `story_event_requested(name)` carries story events.
- **Story path:** `PauseArbiter.push(&"story")`, typewriter at `tuning.comms.chars_per_s` (45); a click completes, the next advances; after the last line pop `story` then emit finished. The click is consumed (`set_input_as_handled()`) so it never fires the laser. Esc adds `menu`; closing it leaves the story pause.
- **Priority:** story preempts a playing combat line (the dropped one still emits finished); combat-on-combat queues FIFO max 3, oldest dropped; story-on-story queues, never dropped. Unknown id: `Log.error` plus a deferred finished. Combat timers run on game time and freeze under any pause.
- **Cut-off:** combat-only line fields `cut_off_at` and `after` (`silence`, `shake`, `sfx`, `music`). A cut-off line types slower (`comms.cutoff_chars_per_s` 16, so the cut lands at `cut_off_at / 16` s, about 2.4-2.5 s) and stops at exactly `cut_off_at` chars plus `comms.cutoff_suffix` (`...`), then static SFX (a 4.5 s softened CC0 recording with a 0.2 s end fade, stopped with the line and paused with the tree), a shake through `Feedback` (shake only: `"cutoff"` is the dedicated 18 px / 0.9 s `comms.cutoff_shake_px` / `cutoff_shake_s`, or an `ImpactTier` name), music stop, silence; the box holds the cut text for `comms.cutoff_hide_s` (4.5 s of real time, the clip's length), then hides at once with no fade, about 7 s in all (GDD decision #43). While silenced (`until_wave_clear`), combat requests are dropped at DEBUG, story still plays; `Events.wave_cleared` lifts it. A story preempting before the cut-off moment drops the effects, so don't request a story in the same moment as a cut-off.
- **Dialogue data:** `data/dialogue/<scene>.json`, `{ "sequences": { id: { "mode", "lines": [{ "speaker", "text", ... }], "choice"? } } }`, ids `<scene>_<beat>`. Access only via `Config.sequence`, `has_sequence`, `dialogue_is_story`; validated at load by `DialogueValidator`.
- **WaveDirector actions:** `comms` (story awaits finished; combat doesn't block), `story_event`, `music` (`stop` | `combat` | `boss` via `Audio.apply_music_action`; stop fades 0.5 s; a missing stream warns once and stays silent), `hint` (`move_fire` | `missile`, emits `Events.hint_requested`, never waits), plus `spawn_group` and `wait`. Triggers take an optional `flag` with `!` negation. A wave clears only when its enemies resolve and its chains finish; a reload discards all chains.
- **Hints:** the HUD `HintPill` reads only `Events` (`hint_requested`, `energy_changed`, `player_moved`, `player_action`); shown hints live in `GameState.shown_hints` (session-only, never saved). Hint copy is UI text, not dialogue.
- **Scene flow:** `scenes/story/story.tscn` via `SceneRouter.goto_story(id, next)`; only `SceneRouter` changes scenes. The story scene must declare a visible cursor.
- **Global rules:** only `PauseArbiter` pauses; only `Feedback` touches time scale and shake; new global signals go into `Events`; log through `Log` (`comms`, `beat`, `hint`); all timings, sizes and limits come from `tuning.json` via `Config`. New SFX are generated placeholders and must be credited in `assets/CREDITS.md`.

## UX & Interaction Patterns

- One rule: a centred panel over a dim means read and click; a small corner box means glance if you like.
- **Story panel:** (410, 300, 1100×300) over a 60% dim; 200 px portrait left, uppercase name in speaker accent (30 px), 28 px sentence-case text (max 4 lines in an 812 px block), `click to continue ▸` cue (muted) bottom-right; no buttons; click anywhere. No-portrait variant (Vale, system) spans 1036 px. HUD visible but frozen.
- **Interruption box:** top-left (32, 24, 560×96); 4 px accent edge, 72 px portrait, 24 px name, 22 px text, max 2 wrapped lines, clipped; types at 45 chars/s; slides in over 0.15 s; ignores the mouse.
- **Opening scene:** no HUD, no dim, static backdrop, visible cursor, Esc does nothing; ends by loading Level 1.
- **Hint pill:** centred at y 560, 52 px tall, fully rounded, key glyph in energy gold, action in text colour; fades in 0.2 s; one pill at a time, newer hints wait. Move dismisses after 150 px; fire on first shot.
- Speaker accents: isolde #FF6AE3, tarek #3DF2FF, ryn #7CFFB2, vale #E8F4FF, system #93A7C2. Styling through the single Theme; the comms portrait frame is the only allowed per-node override. UI motion stays at or under 0.3 s except the box's 0.6 s fade.

## Cross-Story Dependencies

- 5.1 builds the channel, panel and dialogue loading that 5.2, 5.4, 5.5 and 5.6 extend; Story 7.5 extends the channel again for the Final Choice (`final_choice` pause reason, the `choice` block on `l3_final_choice`).
- 5.3 extends the Epic 2 WaveDirector; 5.4, 5.6 and 5.8 rely on its actions and flag-gated triggers. 5.5 depends on Epic 4's `SceneRouter`, title, level select and `GameState.is_retry`. 5.8's E/Q hints depend on Epic 3's `energy_changed` and ability costs.
- Epic 5 proves beats in dev levels (`level_dev_isolde`, `level_dev_hints`); placing interruptions, the surrender prompt and hints into the real campaign levels is Epic 7. 5.7's script covers ids used by Epics 6–7 (Tarek cut-off, Ryn report, L3 briefing, Final Choice lines); Tarek's fall (Epic 6) uses the 5.4 cut-off plus a `tarek_fall` story event.
- Music tracks arrive in Story 8.1; until then music actions are silent by design.
