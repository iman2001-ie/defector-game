### DW-1: No automated check that the boot [INFO][data] summary line is emitted at INFO level.
origin: spec-deferred e60b6cd07bb5
location: game/autoloads/config.gd:22
source_spec: `spec-1-1-set-up-the-godot-project-and-data-driven-foundation.md`
severity: low
reason: Verification-gap layer: removing _log_summary() from Config._ready() leaves all tests green; the line is only seen by reading GUT output. Capturing Log output needs a sink or last-line hook, which this story does not add.
status: done 2026-10-07
resolution: resolved by sweep bundle dw-boot-summary-log-test
resolution-undo: 146c36bcf218d42d45614b2f28ec7b45ec8721196398ead825300f883083e974 2026-10-07 7374617475733a206f70656e

### DW-2: The laser bolt scene masks enemies and asteroids (20) but not convoy, while CollisionLayers.MASK_PLAYER_SHOTS and the architecture layer table include convoy (84).
origin: spec-deferred 23f5fc59453c
location: game/entities/projectiles/laser_bolt.tscn:4
source_spec: `spec-1-4-shoot-wasps-and-asteroids-in-the-sandbox.md`
severity: low
reason: game/entities/projectiles/laser_bolt.tscn has collision_mask = 20 (set in Story 1.3; Story 1.4 may not change the laser). game-architecture.md layer table: player_shots mask = enemies, asteroids, convoy; FR33 says convoy ships block every projectile. No convoy exists until Epic 6, so nothing breaks today, but player bolts would pass through convoy ships. test_laser_bolt_masks_enemies_and_asteroids checks single bits only, so the gap is not flagged.
status: done 2026-10-07
resolution: resolved by sweep bundle dw-laser-mask-player-shots
resolution-undo: b6d7862c5bcf8093a8495f725b9b7caf2f0c3c82331a9d27f8bc220e75772a51 2026-10-07 7374617475733a206f70656e
decision: 2026-10-07 Set mask 84 and test equality — Set the laser bolt collision mask to CollisionLayers.MASK_PLAYER_SHOTS (84), add a test asserting exact mask equality with the constant, and correct the epics.md Story 1.3 AC.

### DW-3: A player's straight shot into the grid_4x2 formation hits a bottom-row Wasp and splashes nothing, so the missile does not "burst a formation" from the ship's firing position.
origin: spec-deferred 4b2e391514c6
location: game/data/tuning.json weapons.missile.splash_radius_px; game/entities/projectiles/missile.gd apply_splash
source_spec: `spec-1-5-fire-aimed-missiles-with-splash-damage.md`
severity: medium
reason: The missile centre at contact with the Wasp at (880, 280) from below sits at about y 305-318 (Wasp hitbox radius ~25.6 px plus the 12 px capsule half-height). From there the top-row Wasp at (880, 160) is about 145-158 px away and the bottom-row neighbours about 164 px away, all beyond splash_radius_px 120. Only a top-row hit (the spec's staged Formation row, fired from inside the grid) splashes a neighbour. The numbers are the GDD's tuning (splash_radius_px 120, grid_4x2 spacing 160 x 120), so fixing it means a tuning or design decision for the Story 1.7 core-feel playtest, not a code change in this story.
status: done 2026-10-07
resolution: already resolved: Settled by human decision in 52a3621: gdd decision-log.md:32 row #28 (Story 1.7 playtest) says 'No tuning change to missile splash vs grid_4x2 (DW-3)'; tuning.json:24 splash_radius_px stays 120 by design.

### DW-4: The off-screen pre-warm at x = -1000 may be culled by the renderer, so particle and additive-material shaders might not actually compile before the first real explosion.
origin: spec-deferred 3daa68d1eac9
location: game/autoloads/feedback.gd prewarm(); game/entities/effects/explosion.tscn visibility_rect
source_spec: `spec-1-6-feel-every-impact-scale-with-size.md`
reason: Feedback.prewarm() spawns explosions at (-1000, 540); every GPUParticles2D has visibility_rect Rect2(-200,-200,400,400), scaled at most 4x, so each explosion lies wholly outside the viewport. If culled canvas items are never drawn, no pipeline compiles and the first real impact can still hitch. Headless tests only count nodes and positions, so they cannot settle it. Would settle: a Story 1.7 frame-time check of the first large explosion on the dev laptop (with and without pre-warm). The x = -1000 position is mandated by the architecture and the story's acceptance criteria.
status: open

### DW-5: Nothing caps live explosions; each one builds three GPUParticles2D nodes plus a ring, and double feedback and missile splash multiply them.
origin: spec-deferred ffc60527d303
location: game/autoloads/feedback.gd impact(); game/entities/effects/explosion.tscn
source_spec: `spec-1-6-feel-every-impact-scale-with-size.md`
reason: Every Feedback.impact spawns a full Explosion (Burst, Sparks, Debris, Shockwave) that lives until LIFETIME_S, with no pooling (ruled out by the spec) and no budget. A kill makes two impacts (projectile + death), and splash chains add more. Headless tests cannot measure GPU cost. Would settle: the Story 1.7 stress test, frame time with many simultaneous kills on the dev laptop.
status: open

### DW-6: A fresh clone cannot run the GUT suite until the project has been imported once with --import.
origin: spec-deferred e212d1529e2f
location: AGENTS.md section 3 (test command); game/autoloads/audio.gd preloads
source_spec: `spec-1-6-feel-every-impact-scale-with-size.md`
severity: medium
reason: Verified in a clean git-archive copy with no game/.godot: Audio's preload of the five WAVs fails, then every class_name type is missing, and the suite errors out. The baseline 01325de copy also fails (no class_name cache before --import), so the root cause predates this story. After --headless --path game --import, all 240 tests pass. The fix is to add the --import step before the test command in AGENTS.md (an agent-context file).
status: done 2026-10-07
resolution: resolved by sweep bundle dw-gut-import-step-docs
resolution-undo: f90452eaa0ef30bfda6085e7faf18c1689d0bb87c647454b5728702b505f82cd 2026-10-07 7374617475733a206f70656e

### DW-7: Complete story 1-7 operator actions (fun-gate playtest incl. DW-3 splash tuning, F1 overlay under --stress, glow on export), then bmad-loop confirm and re-run the Epic 1 retro
origin: retro action item epic-1-retro-item-1-complete-story-1-7-operator-actions-fun
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-1-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 1; owner Developer (operator); sprint-status status open)
status: done 2026-10-07
resolution: already resolved: a2386df confirmed Story 1-7 operator actions (spec-1-7 Operator Confirmation; decision-log #27, #28, #30 in 52a3621); sprint-status.yaml action item epic-1-retro-item-1 is status: done

### DW-8: Add a validating Config.reload() API that restores its own state on failure; DebugTools stops writing Config fields; run the follow-up review story 1-7 recommended
origin: retro action item epic-1-retro-item-2-add-a-validating-config-reload-api-that
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-1-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 1; owner Dev loop; sprint-status status open)
status: done 2026-10-07
resolution: resolved by sweep bundle dw-config-validating-reload
resolution-undo: 5b21ee29b0532637dae15f9788efd5f8de66642e1143626926536d054cf4295d 2026-10-07 7374617475733a206f70656e

### DW-9: Bring the stress bench up to the NFR peak (about 200 projectiles), judge on p99/max as well as the average, and measure the first large explosion with and without pre-warm (DW-4, DW-5)
origin: retro action item epic-1-retro-item-3-bring-the-stress-bench-up-to-the-nfr-pea
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-1-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 1; owner Dev loop; sprint-status status open)
status: done 2026-10-07
resolution: resolved by sweep bundle dw-stress-bench-nfr-peak
resolution-undo: 74db697bf92a309658c29e0bec9198c418e34c4c99e27252cf3d5a488bc87ba7 2026-10-07 7374617475733a206f70656e
decision: 2026-10-07 Build the bench now — Extend the --stress/--bench sandbox mode to sustain about 200 live projectiles or moving enemies, report p99 and max frame time alongside the average with PASS judged on all three, and add a first-large-explosion measurement with and without Feedback.prewarm(). Leave the on-hardware run itself to the operator.

### DW-10: Decide the laser collision mask (recommend MASK_PLAYER_SHOTS=84), derive masks from CollisionLayers or test equality, and correct the epics.md Story 1.3 AC (DW-2)
origin: retro action item epic-1-retro-item-4-decide-the-laser-collision-mask-recommen
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-1-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 1; owner Developer (decision) then Dev loop; sprint-status status open)
status: done 2026-10-07
resolution: resolved by sweep bundle dw-laser-mask-player-shots
resolution-undo: b6d7862c5bcf8093a8495f725b9b7caf2f0c3c82331a9d27f8bc220e75772a51 2026-10-07 7374617475733a206f70656e
decision: 2026-10-07 Follow the architecture: mask 84 — Set the laser bolt mask to CollisionLayers.MASK_PLAYER_SHOTS (84), preferably assigned from CollisionLayers in code or guarded by a test that asserts exact mask equality for laser and missile. Correct the Story 1.3 AC in epics.md to include convoy and record the decision in the decision log. This also closes DW-2.

### DW-11: Reconcile game-architecture.md with the as-built: play_sfx pitch param, tier sfx_volume_db, single explosion scene, Spawner/ShakeCamera to Feedback registration, CLI stress/bench modes
origin: retro action item epic-1-retro-item-5-reconcile-game-architecture-md-with-the
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-1-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 1; owner Developer / Architect; sprint-status status open)
status: done 2026-10-07
resolution: already resolved: Story 1.10 (1a40a12) reconciled game-architecture.md: play_sfx pitch param :325-333, tier sfx_volume_db :933-936, single explosion scene :950, Spawner/ShakeCamera Feedback registration :712 and :958-959, --stress/--bench CLI modes :541-542 and :1215
decision: 2026-10-07 Reconcile the doc to as-built — Edit _bmad-output/game-architecture.md to document the play_sfx pitch parameter, per-tier sfx_volume_db, the single explosion scene, Spawner and ShakeCamera registration with Feedback, and the --stress/--bench CLI modes, matching the current code, and add a decision-log note for each change.

### DW-12: Add the --import step before the GUT command in AGENTS.md section 3 and in the architecture test command (DW-6)
origin: retro action item epic-1-retro-item-6-add-the-import-step-before-the-gut-comma
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-1-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 1; owner Developer; sprint-status status open)
status: done 2026-10-07
resolution: resolved by sweep bundle dw-gut-import-step-docs
resolution-undo: f90452eaa0ef30bfda6085e7faf18c1689d0bb87c647454b5728702b505f82cd 2026-10-07 7374617475733a206f70656e

### DW-13: Add a shared playfield-rect constant before Epic 2; split the weapon logic out of player.gd before Epic 3
origin: retro action item epic-1-retro-item-7-add-a-shared-playfield-rect-constant-bef
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-1-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 1; owner Dev loop; sprint-status status open)
status: done 2026-10-07
resolution: resolved by sweep bundle dw-playfield-rect-and-weapon-split
resolution-undo: 32bbe04986e2fcf0d466a2988e0a98302fea1d33e860b519de92d9d73e492671 2026-10-07 7374617475733a206f70656e

### DW-14: Split oversized stories (5+ new systems, like 1-6) or raise the per-story token cap deliberately; 1-4 and 1-6 overran 2M weighted tokens
origin: retro action item epic-1-retro-item-8-split-oversized-stories-5-new-systems-li
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-1-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 1; owner Planning (SM); sprint-status status open)
status: done 2026-10-07
resolution: closed by human decision: Per-story token cap raised deliberately in bmad-loop config by the operator.
decision: 2026-10-07 Raise the token cap — Per-story token cap raised deliberately in bmad-loop config by the operator.

### DW-15: Fix the epic-1 status in sprint-status, and align the bmad-loop commit subject format with AGENTS.md section 5 (or amend section 5)
origin: retro action item epic-1-retro-item-9-fix-the-epic-1-status-in-sprint-status-a
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-1-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 1; owner Developer; sprint-status status open)
status: done 2026-10-07
resolution: resolved by sweep bundle dw-agents-md-import-and-commit-format
resolution-undo: 7ab49461c95cd205854bbcce2fdc0821b7f3fd449b8b0be9cd403df12563bc9f 2026-10-07 7374617475733a206f70656e
decision: 2026-10-07 Amend AGENTS.md section 5 — Amend AGENTS.md section 5 to accept the bmad-loop commit subject format ('story <key>: ...') alongside the manual 'Story X.Y: summary' form. The operator separately corrects the epic-1 status in sprint-status.yaml.

### DW-16: The new docs call the --import step "one-time", but an existing checkout also needs it re-run after adding class_name scripts or new imported assets (or when game/.godot/ is stale).
origin: spec-deferred 3ba10d44cd3e
location: AGENTS.md:29-30; _bmad-output/game-architecture.md:1232
source_spec: `spec-dw-6-dw-12-gut-import-step-docs.md`
severity: medium
reason: Stories 1.2-1.5 each re-ran --import to refresh the class cache for new class_name types (Player, Projectile, Enemy, Missile). Headless -s runs do not rescan the class cache. The fix rewords AGENTS.md (agent-context file), so it is deferred.
status: done 2026-10-07
resolution: resolved by sweep bundle dw-agents-md-import-and-commit-format
resolution-undo: 7ab49461c95cd205854bbcce2fdc0821b7f3fd449b8b0be9cd403df12563bc9f 2026-10-07 7374617475733a206f70656e

### DW-17: The architecture's CLI export command has the same fresh-clone gap: it runs --export-release without a prior --import.
origin: spec-deferred 3ac631213abb
location: _bmad-output/game-architecture.md:1141
source_spec: `spec-dw-6-dw-12-gut-import-step-docs.md`
severity: low
reason: Story 1.7 had to run --import before --export-release. Pre-existing; the bundle intent covers only the test command.
status: done 2026-10-07
resolution: already resolved: Story 1.10 (1a40a12): _bmad-output/game-architecture.md:1236-1242 CLI export now runs --headless --path game --import before --export-release (change log :1425 cites DW-17)

### DW-18: The godot-testing.md knowledge files show GUT commands with no --path and no import step, so agents reading them still get the failing fresh-clone procedure.
origin: spec-deferred c0aa3f8fe839
location: .claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md
source_spec: `spec-dw-6-dw-12-gut-import-step-docs.md`
severity: low
reason: .claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md (and its .agents/skills copy) are untouched by this change; pre-existing agent-context files outside the intent's two named locations.
status: done 2026-10-07
resolution: closed by human decision: Vendored generic GDS knowledge; AGENTS.md section 3 holds the correct project-specific GUT procedure and takes precedence.
decision: 2026-10-07 Close: AGENTS.md is authoritative — Vendored generic GDS knowledge; AGENTS.md section 3 holds the correct project-specific GUT procedure and takes precedence.

### DW-19: The real F5 path (input event, then get_tree().reload_current_scene and consumers re-reading Config) is still untested; tests inject restart_scene and call reload_data() directly.
origin: spec-deferred 8ed8e1eb8e32
location: game/ui/debug/debug_tools.gd:28,51-52
source_spec: `spec-dw-8-config-validating-reload.md`
severity: low
reason: Pre-existing gap (epic 1 retro finding B4, deferred there). This change keeps the injected-restart test seam; the B1 failure it fixes is pinned at the Config and reload_data() level only.
status: done 2026-10-07
resolution: resolved by sweep bundle dw-debug-tools-injectable-user-args
resolution-undo: 1207a1a248ff3ecc027e6a4856aa12c52d59767f76548beeae5ac53e5182b0f2 2026-10-07 7374617475733a206f70656e

### DW-20: After a resume warp the next physics tick may still read the pre-warp mouse position, giving a one-tick ship jump.
origin: spec-deferred c9296c5c0ffe
location: game/entities/player/player.gd _on_resumed / step_lock
source_spec: `spec-1-8-lock-the-ship-to-the-cursor-and-fire-missiles-straight-up.md`
reason: Unverified (maybe-false). Depends on whether Viewport.get_mouse_position() queries the OS cursor (immediate after SetCursorPos) or the last motion event. Settle with a live pause/resume test once Story 4.4 adds the pause menu; tests only use a recorder Callable.
status: done 2026-10-11
resolution: resolved by sweep bundle dw-player-guard-hardening
resolution-undo: 49e34bcf451130f577254cace2c37b5df00effc4e7846f3dc864a7f489b79373 2026-10-11 7374617475733a206f70656e
decision: 2026-10-10 Add a defensive one-tick guard — On the first physics tick after Player._on_resumed warps the cursor, ignore the viewport mouse position and use the warp target (the ship's position) instead, so a stale pre-warp position can never move the ship; add a unit test using the injected warp recorder. Not observed in play; this is a harmless guard (operator decision 2026-10-10 replaces the earlier close).

### DW-21: The bench's final `Stress bench:` log line is often missing from stdout and godot.log although the run completes and exits 0.
origin: spec-deferred 15ca91c1d4c8
location: game/ui/debug/debug_tools.gd _finish_bench
source_spec: `spec-1-9-make-laser-bolts-and-the-neon-glow-brighter.md`
severity: low
reason: Observed by the Story 1.9 implementer across several `-- --bench=20` runs (most runs without --verbose, one of three with it). Looks like an output-flush race between Log and get_tree().quit() in DebugTools._finish_bench. Pre-existing (Story 1.7 code); settle by flushing the log before quit and re-running the bench several times.
status: done 2026-10-07
resolution: resolved by sweep bundle dw-stress-bench-nfr-peak
resolution-undo: 74db697bf92a309658c29e0bec9198c418e34c4c99e27252cf3d5a488bc87ba7 2026-10-07 7374617475733a206f70656e

### DW-22: Record the fun-gate colleague waiver as decision-log #32 and amend epics.md lines 326 and 536 to match
origin: retro action item epic-1-retro-item-10-record-the-fun-gate-colleague-waiver-as
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-1-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 1; owner Developer; sprint-status status open)
status: done 2026-10-07
resolution: resolved by sweep bundle dw-fun-gate-waiver-record
resolution-undo: 4ac44219425cdb9e012adc6681c518f58918ec02d01db03dabc6577fbbf06cb3 2026-10-07 7374617475733a206f70656e

### DW-23: Schedule the decided DW-10 (laser mask 84, equality test, Story 1.3 AC fix) and DW-9 (bench to NFR peak) into stories (1.8/1.10, a pre-Epic-2 story, or 8.3)
origin: retro action item epic-1-retro-item-11-schedule-the-decided-dw-10-laser-mask-84
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-1-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 1; owner Planning (SM); sprint-status status open)
status: done 2026-10-07
resolution: already resolved: Both decided items landed as sweeps instead of stories: 834d98e (DW-2/DW-10 laser mask 84, equality test, Story 1.3 AC fix) and 2034298 (DW-9 bench at NFR peak); epic-2 retro follow-through table proposes item 11 done.

### DW-24: Add a human AC to Story 1.8: developer re-checks the core feel under the cursor lock and straight-up missile before Epic 2 tuning
origin: retro action item epic-1-retro-item-12-add-a-human-ac-to-story-1-8-developer-re
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-1-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 1; owner Planning (SM); sprint-status status open)
status: done 2026-10-07
resolution: closed by human decision: Story 1.8 operator confirmation (2026-10-07) included a live sandbox run firing lasers and missiles under the new lock; no separate AC needed.
decision: 2026-10-07 Close: 1.8 operator run covered it — Story 1.8 operator confirmation (2026-10-07) included a live sandbox run firing lasers and missiles under the new lock; no separate AC needed.

### DW-25: Mark DW-7 done in deferred-work.md (resolved by a2386df)
origin: retro action item epic-1-retro-item-13-mark-dw-7-done-in-deferred-work-md-resol
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-1-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 1; owner Developer; sprint-status status open)
status: done 2026-10-07
resolution: already resolved: deferred-work.md DW-7 already carries 'status: done 2026-10-07' with resolution citing a2386df; epic-2 retro follow-through table confirms item 13 landed.

### DW-26: Re-run the Epic 1 retrospective once Stories 1.8-1.10 are done
origin: retro action item epic-1-retro-item-14-re-run-the-epic-1-retrospective-once-sto
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-1-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 1; owner Developer; sprint-status status open)
status: done 2026-10-08
resolution: closed by human decision: Stories 1.8-1.10 were covered by the Epic 2 and Epic 3 retros; a separate Epic 1 re-run is not needed
decision: 2026-10-08 Close: Epic 2/3 retros superseded it — Stories 1.8-1.10 were covered by the Epic 2 and Epic 3 retros; a separate Epic 1 re-run is not needed
decision: 2026-10-07 Keep open: operator re-runs the retro

### DW-27: The --no-prewarm wiring through Sandbox._ready and DebugTools._ready is not covered by any test, so a regression could mislabel the prewarm on/off comparison.
origin: spec-deferred def51ca50f5c
location: game/ui/debug/debug_tools.gd _ready; game/scenes/sandbox/sandbox.gd _ready
source_spec: `spec-dw-9-dw-21-stress-bench-nfr-peak.md`
severity: medium
reason: Both _ready methods read OS.get_cmdline_user_args() directly, so tests cannot inject --no-prewarm. Tests cover only DebugArgs.parse, the static Sandbox.should_prewarm, and DebugTools with _prewarm set by hand. Deleting `_prewarm = args.prewarm` in debug_tools.gd would leave the suite green. Fix: an injectable user-args source for both _ready paths (the --stress wiring has the same gap).
status: done 2026-10-07
resolution: resolved by sweep bundle dw-debug-tools-injectable-user-args
resolution-undo: 1207a1a248ff3ecc027e6a4856aa12c52d59767f76548beeae5ac53e5182b0f2 2026-10-07 7374617475733a206f70656e

### DW-28: AGENTS.md section 5 still requires a story id or key, so bmad-loop's other commit subjects (`sweep <bundle>: DW-n via bmad-loop`, `chore(sweep|operator|decisions|retro): ...`) and manual non-story
origin: spec-deferred ca109689f523
location: AGENTS.md:60
source_spec: `spec-dw-15-dw-16-agents-md-import-and-commit-format.md`
severity: medium
reason: git log shows `sweep dw-stress-bench-nfr-peak: DW-9, DW-21 via bmad-loop`, `chore(operator): confirm ...`, `chore(decisions): pre-answer DW-15`, `Epic 1 retro: revision 2`. The DW-15 decision only covers the `story <key>: ...` form, and the fix edits AGENTS.md (agent-context file), so it is deferred.
status: done 2026-10-08
resolution: resolved by sweep bundle dw-agents-md-commit-subject-forms
resolution-undo: 937eccf24e8833b1900438b3a979b4f722ad9fa80d73da7714624d8dcad1d6ff 2026-10-08 7374617475733a206f70656e
decision: 2026-10-07 Amend section 5 to list the loop forms — Amend AGENTS.md section 5 to also accept 'sweep <bundle>: DW-n ...', 'chore(<scope>): ...' for orchestration/bookkeeping commits, and a clear summary for non-story manual work (retros, correct-course), keeping story references required for story work.

### DW-29: The --import re-run triggers name only adding class_name scripts or imported assets; renaming, moving or deleting class_name scripts, changing imported assets, and pulling or switching branches that
origin: spec-deferred e5e258f88c18
location: AGENTS.md:30; _bmad-output/game-architecture.md:1335-1337
source_spec: `spec-dw-15-dw-16-agents-md-import-and-commit-format.md`
severity: low
reason: Headless -s runs never rescan the class cache, whatever the cause of the change. A typical symptom is a parse error naming a class_name that exists. The fix edits AGENTS.md (agent-context file), so it is deferred.
status: done 2026-10-07
resolution: resolved by sweep bundle dw-agents-md-import-rerun-wording
resolution-undo: 102fee74f99c252aea09f90531630a3add6b0084a13b41d6c00f9ab98c8c91f3 2026-10-07 7374617475733a206f70656e

### DW-30: The DW-15 decision (amend AGENTS.md section 5) is recorded only in the deferred-work ledger, not in a decision log as AGENTS.md section 4 asks.
origin: spec-deferred 5bfb1d58f231
location: _bmad-output/implementation-artifacts/deferred-work.md (DW-15)
source_spec: `spec-dw-15-dw-16-agents-md-import-and-commit-format.md`
severity: low
reason: Commit `chore(decisions): pre-answer DW-15` recorded it in the ledger before this run. No process decision log exists, and the GDD decision log covers game design. This is pre-existing and not caused by this change.
status: done 2026-10-07
resolution: closed by human decision: Process decisions are recorded on the ledger entry's decision: line and in the AGENTS.md change itself.
decision: 2026-10-07 Close: ledger plus AGENTS.md is the record — Process decisions are recorded on the ledger entry's decision: line and in the AGENTS.md change itself.

### DW-31: The --import re-run reason ("headless -s runs don't rescan the class cache") explains only the class_name trigger; it does not say why new imported assets also need a re-run (headless -s runs don't
origin: spec-deferred a79436289cb2
location: AGENTS.md:30; _bmad-output/game-architecture.md:1335-1337
source_spec: `spec-dw-15-dw-16-agents-md-import-and-commit-format.md`
severity: low
reason: AGENTS.md:30 and game-architecture.md:1335-1337 list "new imported assets" as a trigger, but the stated cause is only the class cache. A new WAV that Audio preloads has no .import artefact until --import runs. The instruction itself is still correct, so following it gives the right result. The fix edits AGENTS.md (agent-context file), so it is deferred.
status: done 2026-10-07
resolution: resolved by sweep bundle dw-agents-md-import-rerun-wording
resolution-undo: 102fee74f99c252aea09f90531630a3add6b0084a13b41d6c00f9ab98c8c91f3 2026-10-07 7374617475733a206f70656e

### DW-32: Projectile._on_area_entered calls apply_damage on any overlapped area, so once a convoy with apply_damage exists, player bolts (now masking CONVOY) would damage it instead of being blocked with no
origin: spec-deferred f39d733a65b1
location: game/core/projectile.gd:49
source_spec: `spec-dw-2-dw-10-laser-mask-player-shots.md`
severity: medium
reason: game/core/projectile.gd:49-54 has no convoy check. FR7, GDD #23 and game-architecture.md:310 require player shots to be blocked by the convoy without damage. No convoy exists until Epic 6, so nothing breaks today. The Epic 6 convoy story must add the no-damage path, plus a test that a convoy-layer area stops a bolt without apply_damage.
status: resolved
resolution: resolved by Story 6.1: Projectile._can_damage refuses convoy-layer areas (Projectile.is_convoy), so player and ally shots are blocked with no damage and a SMALL effect; tests in test_projectile.gd.

### DW-33: Missile._on_impact always runs apply_splash, so a missile stopped by a convoy ship (missile mask already includes CONVOY) would still splash enemies and asteroids near the convoy; whether a blocked
origin: spec-deferred 27d4e4bd97cb
location: game/entities/projectiles/missile.gd:27
source_spec: `spec-dw-2-dw-10-laser-mask-player-shots.md`
reason: game/entities/projectiles/missile.gd:27-29 calls apply_splash before super._on_impact for every hit. missile.tscn has masked CONVOY (84) since Story 1.5, so this predates DW-2/DW-10. epics.md:1409-1411 (Epic 6 convoy story) says missiles reaching a convoy ship are "stopped and free itself, the convoy takes no damage", but says nothing about splash on nearby enemies. Settle by a design ruling in the Epic 6 convoy story (detonate with splash vs. fizzle) and a test for it.
status: resolved
resolution: resolved by Story 6.1: Missile._on_impact skips apply_splash on a convoy area (fizzle, GDD #46) and the base plays SMALL, not MEDIUM; tests in test_missile.gd and test_micro_missile.gd.
decision: 2026-10-10 Fizzle — A player missile (or Barrage micro-missile) stopped by a convoy ship fizzles: no explosion, no splash, no convoy damage, same blocked-shot effect as a laser bolt (GDD decision #46). Story 6.1 implements it and adds a test.

### DW-34: The Bastion's y 80–400 drift range may let a large sprite overlap the 0–120 px HUD band and the wave bar.
origin: spec-deferred c6c13658c554
location: _bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md:269
source_spec: `spec-2-1-count-wave-progress-and-evaluate-beat-triggers.md`
reason: Pre-existing in the plan, not caused by Story 2.1: GDD gdd.md L269 and epics.md FR22/L829 set "y 80–400", while the UX layout puts the HUD band at 0–120 and the wave bar at y 40. Whether a sprite actually overlaps depends on the Bastion's sprite size and how its y is clamped. To settle it, check the Bastion story (Epic 2) against DESIGN.md's layout bands before building the Bastion.
status: done 2026-10-07
resolution: closed by human decision: Story 2.7 clamps the whole hull to y 80-400; any remaining visual overlap is checked in the DW-42 playtest.
decision: 2026-10-07 Close: covered by 2.7 and the DW-42 playtest — Story 2.7 clamps the whole hull to y 80-400; any remaining visual overlap is checked in the DW-42 playtest.

### DW-35: test_f3_resolves_the_wave_and_fires_pending_triggers_in_order fails deterministically in this environment ("the skipped group never spawns", expected 0 got 1).
origin: spec-deferred 25bf8310c4a6
location: game/tests/unit/test_wave_director.gd:347
source_spec: `spec-2-3-watch-the-wave-progress-bar-fill.md`
severity: medium
reason: Pre-existing (Story 2.2 test, untouched by 2.3): it fails 5/5 in isolation on HEAD and 2/2 at baseline 07bcc62 in a clean worktree. The test sets waves.gap_s = 0.05, then awaits 2 process frames and asserts no counted enemies; the log shows wave 2/2 (1 wasp) already started before the assert, so the 0.05 s gap elapses within those 2 headless frames. The earlier 2.3 pass saw it green, so it depends on frame timing.
status: done 2026-10-07
resolution: resolved by sweep bundle dw-wave-test-reliability
resolution-undo: eb9cda2ef210f1add7d9e92328d25734709b8f4028591fe755790a11a15e164c 2026-10-07 7374617475733a206f70656e

### DW-36: test_wave_director.test_f3_resolves_the_wave_and_fires_pending_triggers_in_order fails deterministically on this machine ("the skipped group never spawns": expected 0, got 1).
origin: spec-deferred af06330c8b77
location: game/tests/unit/test_wave_director.gd:387
source_spec: `spec-2-5-face-lancers-aimed-shots.md`
severity: medium
reason: Fails 5/5 runs and also fails at HEAD dfa8063 and at baseline 6cad11a922c2edd30ccb48ff631445a4b329a74e, so it predates Story 2.5. The test waits wait_process_frames(2) after F3 with gap_s 0.05; if those two frames take longer than 0.05 s the next wave's single Wasp has already spawned and is counted. Likely fix: count only enemies from the skipped group, or assert before the gap can elapse.
status: done 2026-10-07
resolution: resolved by sweep bundle dw-wave-test-reliability
resolution-undo: eb9cda2ef210f1add7d9e92328d25734709b8f4028591fe755790a11a15e164c 2026-10-07 7374617475733a206f70656e

### DW-37: Harden wave-data validation and counting: group counting vs trigger reachability, progress at reachability, type-check trigger/entry fields, Bastion in zoned types, grid width bound, _next_row for slotless types (R1-R7, R9)
origin: retro action item epic-2-retro-item-15-harden-wave-data-validation-and-counting
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-2-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 2; owner Dev loop; sprint-status status open)
status: done 2026-10-08
resolution: resolved by sweep bundle dw-wave-data-validation-hardening
resolution-undo: a92b52114ad60ef039959c621c1aa394b64e3c6a212a663bca8461c3b546f5f0 2026-10-08 7374617475733a206f70656e
decision: 2026-10-07 Build: unreachable group is a validation error — LevelValidator rejects any group whose naming trigger can never fire (wave_clear, off or unknown flag, unevaluated boss_* triggers) and any progress `at` that cannot be reached before the group spawns; also type-check at/phase/hp/flag (against flags.json)/wait/entry and unknown action keys, add Bastion to ZONED_TYPES in test_data_files.gd, bound grid columns to the playfield width in validator and Formation, and stop _next_row advancing for Needle and Hunter Wasp. Tests for each rule.

### DW-38: Add an integration test that plays level_dev.json to LEVEL CLEAR with real kills (no F3) and asserts no stall ERROR (R3)
origin: retro action item epic-2-retro-item-16-add-an-integration-test-that-plays-level
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-2-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 2; owner Dev loop; sprint-status status open)
status: done 2026-10-07
resolution: resolved by sweep bundle dw-wave-test-reliability
resolution-undo: eb9cda2ef210f1add7d9e92328d25734709b8f4028591fe755790a11a15e164c 2026-10-07 7374617475733a206f70656e

### DW-39: Fix the isolation-only failing F3 test in test_wave_director.gd (DW-35) and close DW-36 as its duplicate
origin: retro action item epic-2-retro-item-17-fix-the-isolation-only-failing-f3-test-i
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-2-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 2; owner Dev loop; sprint-status status open)
status: done 2026-10-07
resolution: resolved by sweep bundle dw-wave-test-reliability
resolution-undo: eb9cda2ef210f1add7d9e92328d25734709b8f4028591fe755790a11a15e164c 2026-10-07 7374617475733a206f70656e

### DW-40: Decide enemy fire cadence semantics (GDD 2.0/2.5 s vs as-built 2.3/3.0 s period; Needle start-to-start), align Lancer/Bastion/Needle, record in decision log
origin: retro action item epic-2-retro-item-18-decide-enemy-fire-cadence-semantics-gdd
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-2-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 2; owner Developer (decision) then Dev loop; sprint-status status open)
status: done 2026-10-08
resolution: resolved by sweep bundle dw-enemy-fire-cadence-full-period
resolution-undo: 92a4a16a62129ebfbf76e49c515b96c482778fa3bd128f3421032b1e4eca1b7a 2026-10-08 7374617475733a206f70656e
decision: 2026-10-07 Full period: interval includes the telegraph — Change Lancer and Bastion so the shot period equals fire_interval_s (timer runs interval minus telegraph), matching the Needle's start-to-start semantics; update tests, the as-built notes in game-architecture.md and add a decision-log row.

### DW-41: Extract shared enemy behaviour (setup/entry, aim, fire guard, tuning prefix) into core/enemy.gd or a ShooterEnemy base before Epic 6
origin: retro action item epic-2-retro-item-19-extract-shared-enemy-behaviour-setup-ent
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-2-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 2; owner Dev loop; sprint-status status open)
status: done 2026-10-07
resolution: resolved by sweep bundle dw-enemy-shared-behaviour-extract
resolution-undo: 181c7063bf721a5d73635320d792fadc10b49d1116d9ab7e28f08749346df334 2026-10-07 7374617475733a206f70656e

### DW-42: Playtest Epic 2 human ACs: telegraph readability, wave bar on screen, Bastion vs HUD band (DW-34), Hunter Wasp with flag on
origin: retro action item epic-2-retro-item-20-playtest-epic-2-human-acs-telegraph-read
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-2-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 2; owner Developer (operator); sprint-status status open)
status: done 2026-10-08
resolution: closed by human decision: operator playtested Epic 2 human ACs
decision: 2026-10-08 Close: playtest done — operator playtested Epic 2 human ACs
decision: 2026-10-07 Keep open for the operator playtest

### DW-43: Set epic-1 and epic-2 to done in sprint-status once their retros are settled
origin: retro action item epic-2-retro-item-21-set-epic-1-and-epic-2-to-done-in-sprint
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-2-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 2; owner Developer; sprint-status status open)
status: done 2026-10-07
resolution: closed by human decision: Operator edits sprint-status.yaml directly; all stories and retros for epics 1 and 2 are done.
decision: 2026-10-07 Operator sets both to done now — Operator edits sprint-status.yaml directly; all stories and retros for epics 1 and 2 are done.

### DW-44: Make the verify gate catch isolation-only failures (run changed test scripts alone or randomise order), ban unscheduled known allowed failures in specs, dedupe harvested deferrals by test name
origin: retro action item epic-2-retro-item-22-make-the-verify-gate-catch-isolation-onl
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-2-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 2; owner Planning (SM) / loop config; sprint-status status open)
status: done 2026-10-07
resolution: closed by human decision: Operator adds a per-changed-script or randomised-order GUT run to the local [verify] commands and bans unscheduled known failures in spec templates.
decision: 2026-10-07 Operator updates loop config and spec rules — Operator adds a per-changed-script or randomised-order GUT run to the local [verify] commands and bans unscheduled known failures in spec templates.

### DW-45: Size stories by systems built: split stories building 5+ systems (2-2 and 2-5 overran the 2M token cap)
origin: retro action item epic-2-retro-item-23-size-stories-by-systems-built-split-stor
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-2-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 2; owner Planning (SM); sprint-status status open)
status: done 2026-10-07
resolution: closed by human decision: Operator raises max_tokens_per_story in the local loop policy.
decision: 2026-10-07 Raise the per-story cap again — Operator raises max_tokens_per_story in the local loop policy.

### DW-46: Level._ready still parses OS.get_cmdline_user_args() directly, so its --stress/--bench redirect to the sandbox and its --no-prewarm skip are untested (the DW-27 gap, in a third script).
origin: spec-deferred 0c82a3ce3da1
location: game/scenes/level/level.gd:22
source_spec: `spec-dw-27-dw-19-debug-tools-injectable-user-args.md`
severity: medium
reason: game/scenes/level/level.gd:22 calls DebugArgs.parse(OS.get_cmdline_user_args()); test_level.gd only exercises the static helpers should_redirect_to_stress and should_prewarm with hand-built dictionaries, so breaking the args wiring in _ready leaves the suite green. Pre-existing and outside the bundle intent (which names DebugTools and Sandbox); the redirect also needs an injectable change_scene seam.
status: done 2026-10-08
resolution: resolved by sweep bundle dw-level-injectable-user-args
resolution-undo: 63c64131cd7f41d972692919f517ce578316d44cec367634bd036a1fff34c86a 2026-10-08 7374617475733a206f70656e

### DW-47: The asset cause says new or changed assets have "no up-to-date `.import` artefact", but the `.import` sidecars are tracked in git; after a pull or branch switch, what is actually missing is the
origin: spec-deferred a10711430ba6
location: AGENTS.md:30; _bmad-output/game-architecture.md:1339-1340
source_spec: `spec-dw-29-dw-31-agents-md-import-rerun-wording.md`
severity: low
reason: `git ls-files '*.import'` lists 31 tracked sidecars, including every `game/assets/audio/sfx/*.wav.import`, and `game/.gitignore` ignores `.godot/`. The instruction (re-run `--import`) is still correct; only the stated cause is imprecise. The wording came from the bundle intent. The fix edits AGENTS.md (agent-context file), so it is deferred.
status: done 2026-10-08
resolution: resolved by sweep bundle dw-agents-md-import-guidance-wording
resolution-undo: d252de656dcd28d4fe026348cec3c954a441edeee9886f537449b640b706bb66 2026-10-08 7374617475733a206f70656e

### DW-48: Only the class_name symptom is named; a stale or missing asset import shows up as a preload or resource-load failure for an asset that exists, and nothing links that to the `--import` re-run.
origin: spec-deferred 46ab44a663bf
location: AGENTS.md:30; _bmad-output/game-architecture.md:1341
source_spec: `spec-dw-29-dw-31-agents-md-import-rerun-wording.md`
severity: low
reason: Both places list asset triggers and the asset cause, but the only symptom given is "a parse error naming a `class_name` that exists". `Audio` preloads WAVs, so a missing import fails at load, not parse. Raised by the blind and edge-case layers. The fix edits AGENTS.md (agent-context file), so it is deferred.
status: done 2026-10-08
resolution: resolved by sweep bundle dw-agents-md-import-guidance-wording
resolution-undo: d252de656dcd28d4fe026348cec3c954a441edeee9886f537449b640b706bb66 2026-10-08 7374617475733a206f70656e

### DW-49: The trigger list names adding or changing imported assets but not renaming, moving or deleting them, although a moved asset's new path has no imported copy until `--import` runs.
origin: spec-deferred 6f2b67a0d5d1
location: AGENTS.md:30; _bmad-output/game-architecture.md:1338-1339
source_spec: `spec-dw-29-dw-31-agents-md-import-rerun-wording.md`
severity: low
reason: Imported copies in `game/.godot/imported/` are keyed by source path, so a moved WAV with its tracked sidecar has no imported copy at the new path. Only the generic "stale game/.godot/" clause covers it. The fix edits AGENTS.md (agent-context file), so it is deferred.
status: done 2026-10-08
resolution: resolved by sweep bundle dw-agents-md-import-guidance-wording
resolution-undo: d252de656dcd28d4fe026348cec3c954a441edeee9886f537449b640b706bb66 2026-10-08 7374617475733a206f70656e

### DW-50: The class_name triggers name adding, renaming, moving or deleting class_name *scripts*, but not adding, changing or removing a `class_name` declaration inside an existing script.
origin: spec-deferred 89cb535ace78
location: AGENTS.md:30; _bmad-output/game-architecture.md:1338
source_spec: `spec-dw-29-dw-31-agents-md-import-rerun-wording.md`
severity: low
reason: Editing the `class_name` line in place changes the global class cache just like adding a new script, and headless `-s` runs don't rescan it. "Renaming class_name scripts" reads as a file rename. Raised by the intent-alignment layer. The fix edits AGENTS.md (agent-context file), so it is deferred.
status: done 2026-10-08
resolution: resolved by sweep bundle dw-agents-md-import-guidance-wording
resolution-undo: d252de656dcd28d4fe026348cec3c954a441edeee9886f537449b640b706bb66 2026-10-08 7374617475733a206f70656e

### DW-51: The `--import` guidance is kept by hand in two places (AGENTS.md section 3 and the architecture's headless CLI block) with no cross-reference, so the copies can drift.
origin: spec-deferred 5bb76b34b077
location: AGENTS.md:30; _bmad-output/game-architecture.md:1337-1341
source_spec: `spec-dw-29-dw-31-agents-md-import-rerun-wording.md`
severity: low
reason: DW-6/DW-12, DW-15/DW-16 and now DW-29/DW-31 each had to edit both copies in step. Neither marks the other as the source. This is pre-existing, not caused by this change.
status: done 2026-10-08
resolution: resolved by sweep bundle dw-agents-md-import-guidance-wording
resolution-undo: d252de656dcd28d4fe026348cec3c954a441edeee9886f537449b640b706bb66 2026-10-08 7374617475733a206f70656e

### DW-52: The opening clause says `--import` "imports the WAVs that `Audio` preloads", but the new triggers cover imported assets in general, and most tracked imports are not WAVs.
origin: spec-deferred c7bd2bd3c86f
location: AGENTS.md:30; _bmad-output/game-architecture.md:1337
source_spec: `spec-dw-29-dw-31-agents-md-import-rerun-wording.md`
severity: low
reason: `git ls-files '*.import'` lists 31 sidecars: 5 wav, 12 ttf, 9 png, 4 svg, 1 fnt. The clause predates this change (the diff kept it), and following the note still gives the right result. The fix edits AGENTS.md (agent-context file), so it is deferred.
status: done 2026-10-08
resolution: resolved by sweep bundle dw-agents-md-import-guidance-wording
resolution-undo: d252de656dcd28d4fe026348cec3c954a441edeee9886f537449b640b706bb66 2026-10-08 7374617475733a206f70656e

### DW-53: The trigger "after pulling or switching to a branch that does either" asks the agent to inspect the incoming changes for class_name or asset edits before deciding whether to re-import.
origin: spec-deferred 995801a338e8
location: AGENTS.md:30; _bmad-output/game-architecture.md:1339
source_spec: `spec-dw-29-dw-31-agents-md-import-rerun-wording.md`
severity: low
reason: This clause was added by this change. Agents rarely inspect a pull's contents, so they may skip a needed re-import. "After any pull or branch switch" would be simpler, and re-importing costs little. The "stale game/.godot/" catch-all only partly covers it. The fix edits AGENTS.md (agent-context file), so it is deferred.
status: done 2026-10-08
resolution: resolved by sweep bundle dw-agents-md-import-guidance-wording
resolution-undo: d252de656dcd28d4fe026348cec3c954a441edeee9886f537449b640b706bb66 2026-10-08 7374617475733a206f70656e

### DW-54: Make a level end exactly once (cleared or failed): stop level_cleared and kill progress after level_failed, decide death-after-clear, add a death+clear test (F1) before Story 4.2
origin: retro action item epic-3-retro-item-24-make-a-level-end-exactly-once-cleared-or
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-3-retro-2026-10-08.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 3; owner Dev loop; sprint-status status open)
status: done 2026-10-08
resolution: resolved by sweep bundle dw-decision-dw-54
resolution-undo: b4f656eb37ef690a0cd62a68a47718957c2f047a25ada1d9142ee8a54aa78557 2026-10-08 7374617475733a206f70656e
decision: 2026-10-08 First outcome wins; clear makes the ship safe — Make the level end exactly once. After level_failed, WaveDirector stops counting kill progress and never emits level_cleared, so in-flight missiles no longer score. After level_cleared, the player can no longer die (hazards are ignored and level_failed is never emitted). Add a decision-log row and tests that combine a death with a clear in both orders.

### DW-55: Split player.gd: extract hearts/i-frames (HealthComponent or a recorded replacement) and the shield into components, and fold try_shield/try_barrage into one spend gate (A1, A3)
origin: retro action item epic-3-retro-item-25-split-player-gd-extract-hearts-i-frames
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-3-retro-2026-10-08.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 3; owner Dev loop + Architect; sprint-status status open)
status: done 2026-10-08
resolution: resolved by sweep bundle dw-player-split-health-shield
resolution-undo: 9aaf762b29edad327fec3362789223598c7bae0889457eb16817047a02529c2e 2026-10-08 7374617475733a206f70656e

### DW-56: Add a shared player test fixture (tests/fixtures/player_test_base.gd + hazard factory) and move the player test files onto it (A2)
origin: retro action item epic-3-retro-item-26-add-a-shared-player-test-fixture-tests-f
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-3-retro-2026-10-08.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 3; owner Dev loop; sprint-status status open)
status: done 2026-10-08
resolution: resolved by sweep bundle dw-player-test-fixture
resolution-undo: 1ade8387c17ecb6aa80a7b0ab6934c6008e8d89cb59725eb9bc1e1dba52b33b9 2026-10-08 7374617475733a206f70656e

### DW-57: Record Epic 3 deviations in the decision log: asteroids survive contact (S1), new tuning values and the ui section (S3); clarify the retry-headline anchor in DESIGN.md:100 (S2)
origin: retro action item epic-3-retro-item-27-record-epic-3-deviations-in-the-decision
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-3-retro-2026-10-08.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 3; owner Developer; sprint-status status open)
status: done 2026-10-10
resolution: resolved by sweep bundle dw-epic-docs-decision-log-sync
resolution-undo: fd1443620827978c4576ed6f315e29497c18561fe0d09ed56a465c6c23665774 2026-10-10 7374617475733a206f70656e
decision: 2026-10-10 Record all three as built — Record the Epic 3 deviations in the GDD decision log as built: (S1) asteroids survive player contact (the enemy is destroyed, the asteroid is not); amend the GDD contact table to match. (S2) Reword DESIGN.md:100 to "headline top at y 440" to match retry_prompt.gd. (S3) Record the new tuning values (orb magnet 600, orb size 24, orb spread 32, micro-missile speed 800, turn rate 540 deg/s, lifetime 3.0, F4 +100) and the top-level `ui` tuning section as decision-log rows. Docs only; no code or tuning change.

### DW-58: Playtest the Epic 3 manual checks listed in specs 3-1 to 3-5
origin: retro action item epic-3-retro-item-28-playtest-the-epic-3-manual-checks-listed
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-3-retro-2026-10-08.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 3; owner Developer (operator); sprint-status status open)
status: done 2026-10-08
resolution: closed by human decision: operator playtested Epic 3 manual checks
decision: 2026-10-08 Close: playtest done — operator playtested Epic 3 manual checks

### DW-59: Apply the decision-closed items that did not take effect: epic-1/2/3 to done in sprint-status (DW-43), raise max_tokens_per_story (DW-45), add a per-script or randomised verify command (DW-44); confirm in the next run journal
origin: retro action item epic-3-retro-item-29-apply-the-decision-closed-items-that-did
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-3-retro-2026-10-08.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 3; owner Developer (operator) / loop config; sprint-status status open)
status: done 2026-10-08
resolution: closed by human decision: operator updated sprint-status epic statuses and policy.toml limits/verify
decision: 2026-10-08 Close: operator has applied them — operator updated sprint-status epic statuses and policy.toml limits/verify

### DW-60: Before closing a sweep item by human decision, record the commit or config change that applies it, or leave it in-progress
origin: retro action item epic-3-retro-item-30-before-closing-a-sweep-item-by-human-dec
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-3-retro-2026-10-08.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 3; owner Planning (SM); sprint-status status open)
status: done 2026-10-08
resolution: closed by human decision: adopted as operator practice for decision-closes
decision: 2026-10-08 Adopt as operator practice; close — adopted as operator practice for decision-closes

### DW-61: Tidy debug and retry edges: SceneRouter clears pauses at the swap (F2), F5 resets GameState energy and retry (F3), add a Groups const class (A5)
origin: retro action item epic-3-retro-item-31-tidy-debug-and-retry-edges-scenerouter-c
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-3-retro-2026-10-08.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 3; owner Dev loop; sprint-status status open)
status: done 2026-10-08
resolution: resolved by sweep bundle dw-debug-retry-edge-tidy
resolution-undo: b3057c011ca05ebd846e5de38253b6962d6c520b4c5e62f19df148dc5a8f57d7 2026-10-08 7374617475733a206f70656e

### DW-62: Retro commits now fit two forms, `chore(retro): ...` and a clear summary such as `Epic 1 retro: revision 2`. AGENTS.md section 5 doesn't say which to use when, for example only bmad-loop or
origin: spec-deferred f957477ee131
location: AGENTS.md:62-63
source_spec: `spec-dw-28-agents-md-commit-subject-forms.md`
severity: low
reason: AGENTS.md:62 gives `chore(retro): epic 3 retrospective` as a bookkeeping example, and AGENTS.md:63 lists retros as manual non-story work with `Epic 1 retro: revision 2`. Both are real subjects in git log. An agent writing a retro commit can't tell from the text which form applies. The fix is a short clarifying clause in AGENTS.md (agent-context file), so it is deferred.
status: done 2026-10-10
resolution: resolved by sweep bundle dw-agents-md-import-and-commit-wording
resolution-undo: b4e5f680f41e66d945025ad9c4b5bbf00ec64bb7c8eb6a016376532904901b2e 2026-10-10 7374617475733a206f70656e

### DW-63: A third copy of the import description, in the CLI export block at `_bmad-output/game-architecture.md:1247`, still says "imports the WAVs Audio preloads", and AGENTS.md's "source for the copy" pointer
origin: spec-deferred fbeeb3bb7b5e
location: _bmad-output/game-architecture.md:1247; AGENTS.md:30
source_spec: `spec-dw-47-dw-53-agents-md-import-guidance-wording.md`
severity: low
reason: Line 1247 reads `# 1. Import (builds the class_name cache and imports the WAVs Audio preloads)`. The bundle intent names only two copies, so this one predates the change and was left untouched. It can drift from AGENTS.md just like DW-51 described. A fix rewords line 1247 and widens the AGENTS.md pointer, which edits an agent-context file.
status: done 2026-10-10
resolution: resolved by sweep bundle dw-agents-md-import-and-commit-wording
resolution-undo: b4e5f680f41e66d945025ad9c4b5bbf00ec64bb7c8eb6a016376532904901b2e 2026-10-10 7374617475733a206f70656e

### DW-64: The class_name trigger covers adding, changing or removing the `class_name` declaration, but not changing the `extends` line or `@icon` of a script that keeps its `class_name`, though the global class
origin: spec-deferred 441e58b30799
location: AGENTS.md:30; _bmad-output/game-architecture.md:1344-1345
source_spec: `spec-dw-47-dw-53-agents-md-import-guidance-wording.md`
severity: low
reason: Godot's `global_script_class_cache.cfg` records each class's base and icon alongside its name, so such an edit leaves the cache stale for headless `-s` runs. The "any pull" and "stale game/.godot/" clauses cover incoming changes but not a local edit read literally. The fix edits AGENTS.md (agent-context file).
status: done 2026-10-10
resolution: resolved by sweep bundle dw-agents-md-import-and-commit-wording
resolution-undo: b4e5f680f41e66d945025ad9c4b5bbf00ec64bb7c8eb6a016376532904901b2e 2026-10-10 7374617475733a206f70656e

### DW-65: "(only the `.import` sidecars are tracked)" does not say what it contrasts with, so it can read as if the source assets were untracked.
origin: spec-deferred 832df692c8ad
location: AGENTS.md:30; _bmad-output/game-architecture.md:1348
source_spec: `spec-dw-47-dw-53-agents-md-import-guidance-wording.md`
severity: low
reason: The intended contrast is tracked assets plus sidecars versus the ignored imported copies; wording such as "the assets and their `.import` sidecars are tracked; the imported copies are not" removes the ambiguity. The fix edits AGENTS.md (agent-context file).
status: done 2026-10-10
resolution: resolved by sweep bundle dw-agents-md-import-and-commit-wording
resolution-undo: b4e5f680f41e66d945025ad9c4b5bbf00ec64bb7c8eb6a016376532904901b2e 2026-10-10 7374617475733a206f70656e

### DW-66: The asset cause says an asset "has no imported copy" until `--import` runs, but for a changed (not new or moved) asset the imported copy exists and is out of date.
origin: spec-deferred 78e12e7f3b31
location: AGENTS.md:30; _bmad-output/game-architecture.md:1347
source_spec: `spec-dw-47-dw-53-agents-md-import-guidance-wording.md`
severity: low
reason: Imported copies in `game/.godot/imported/` are keyed by source path, so a changed asset keeps its old copy. Wording such as "no up-to-date imported copy" covers both cases. The simplification comes from the bundle intent. The fix edits AGENTS.md (agent-context file).
status: done 2026-10-10
resolution: resolved by sweep bundle dw-agents-md-import-and-commit-wording
resolution-undo: b4e5f680f41e66d945025ad9c4b5bbf00ec64bb7c8eb6a016376532904901b2e 2026-10-10 7374617475733a206f70656e

### DW-67: LevelValidator doesn't detect a group named by more than one spawn_group action that can fire in the same wave.
origin: spec-deferred ec3ee6a059ef
location: game/systems/waves/level_validator.gd
source_spec: `spec-dw-37-wave-data-validation-hardening.md`
severity: low
reason: WaveDirector._request_group logs a WARN and ignores a second request for an already-spawned group (wave_director.gd:319); the validator's reachability pass accepts duplicate naming. Pre-existing, not introduced by DW-37.
status: done 2026-10-10
resolution: resolved by sweep bundle dw-level-validator-group-rules
resolution-undo: 86024e89630b53b2535ed1f810dad8b7933a23a66463e828496e223f80e46db9 2026-10-10 7374617475733a206f70656e

### DW-68: A Needle entry authored after another entry anchors on row 0 over the earlier entry's Wasps, while the row WaveDirector reserves for it stays empty.
origin: spec-deferred 9ab5c792c2ca
location: game/systems/waves/wave_director.gd:264
source_spec: `spec-dw-37-wave-data-validation-hardening.md`
severity: low
reason: needle.gd anchors at enemies.needle.anchor_y_px (160 = waves.formation.top_y) whatever its slot y, but WaveDirector._spawn_entry gives it the next free row. Only a first-in-wave Needle (as in level_dev.json wave 4) lines up. Pre-existing: before DW-37 every type advanced the row. Neither LevelValidator nor test_zoned_formations_fit_their_top_zone detects it, and no shipped wave hits it.
status: done 2026-10-10
resolution: resolved by sweep bundle dw-level-validator-group-rules
resolution-undo: 86024e89630b53b2535ed1f810dad8b7933a23a66463e828496e223f80e46db9 2026-10-10 7374617475733a206f70656e
decision: 2026-10-10 Validator: Needle must be first row-taker — Make LevelValidator reject a needle entry that follows another row-taking entry in the same wave, with a test, and document the rule in the wave-data notes.

### DW-69: Decision #38 covers only Lancer and Bastion; the boss timers (boss.turrets fire_interval_s/telegraph_s, desperate aimed/radial interval plus glow) still have unstated cadence semantics, and the Wasp
origin: spec-deferred c9bb03f74898
location: game/data/tuning.json (boss.turrets, boss.desperate)
source_spec: `spec-dw-40-enemy-fire-cadence-full-period.md`
severity: low
reason: tuning.json boss.turrets pairs fire_interval_s 3.0 with telegraph_s 0.5, and GDD FR51 says "every 1.5 s after a 0.4 s glow". The boss isn't built yet (Epic 7), so the DW-40 question will come back unless #38 is extended or the boss story states its semantics. Pre-existing ambiguity; the intent scopes DW-40 to Lancer and Bastion.
status: done 2026-10-10
resolution: resolved by sweep bundle dw-epic-docs-decision-log-sync
resolution-undo: fd1443620827978c4576ed6f315e29497c18561fe0d09ed56a465c6c23665774 2026-10-10 7374617475733a206f70656e
decision: 2026-10-10 Extend #38 to all enemy and boss timers — Add a decision-log row extending #38 (fire_interval_s is the start-to-start period including the telegraph) to boss.turrets and boss.desperate and the Wasp, add a data test requiring telegraph/glow <= interval for those keys, and note the rule in the architecture's boss section; reconcile the boss.turrets tuning with FR51 or record the difference.

### DW-70: The Story 2.5 AC in epics.md ("Given a Lancer's fire timer reaches 2.0 s ... glows for 0.3 s, then it fires") now describes the old timer literally; as built the timer is 1.7 s and the shot lands at
origin: spec-deferred 09902fcc9688
location: _bmad-output/planning-artifacts/epics.md:785
source_spec: `spec-dw-40-enemy-fire-cadence-full-period.md`
severity: low
reason: epics.md:785-787. FR20 ("every 2.0 s") and decision #38 match the new behaviour, and the architecture note explains it. The DW-40 decision lists only tests, the architecture notes and a decision-log row as the docs to update, and AGENTS.md says to ask the user before changing planning docs, so amending a done story's AC (as #34/#35 did) is left for the user to decide.
status: done 2026-10-10
resolution: resolved by sweep bundle dw-epic-docs-decision-log-sync
resolution-undo: fd1443620827978c4576ed6f315e29497c18561fe0d09ed56a465c6c23665774 2026-10-10 7374617475733a206f70656e
decision: 2026-10-10 Amend the AC wording — Reword the Story 2.5 AC in epics.md to say the Lancer fires every 2.0 s start-to-start, with the 0.3 s glow inside that period (per decision #38), and note the amendment in the #38 decision-log row; check the Bastion AC (Story 2.7) for the same wording.

### DW-71: PlayerShield's missing-bubble degradation path (Log.error plus null-safe raise/step/drop) has no test.
origin: spec-deferred 64f10899a665
location: game/entities/player/player_shield.gd:29
source_spec: `spec-dw-55-player-split-health-shield.md`
severity: low
reason: grep for "missing its bubble" hits only player_shield.gd; every test wires a real ShieldBubble. Only consumer player.tscn wires it correctly today.
status: done 2026-10-11
resolution: resolved by sweep bundle dw-player-guard-hardening
resolution-undo: 49e34bcf451130f577254cace2c37b5df00effc4e7846f3dc864a7f489b79373 2026-10-11 7374617475733a206f70656e

### DW-72: Pre-existing: player.hearts tuning is used unclamped, so a negative value makes the ship unhittable with no warning.
origin: spec-deferred dab8b901182c
location: game/core/health_component.gd:36
source_spec: `spec-dw-55-player-split-health-shield.md`
severity: low
reason: HealthComponent.setup copies p_max_value as given, exactly as the old Player._ready did (max_hearts = Config.int_("player.hearts")). Not caused by DW-55; clamping would change behaviour.
status: done 2026-10-11
resolution: resolved by sweep bundle dw-player-guard-hardening
resolution-undo: 49e34bcf451130f577254cace2c37b5df00effc4e7846f3dc864a7f489b79373 2026-10-11 7374617475733a206f70656e

### DW-73: Pre-existing order-dependent test: test_player_barrage.gd::test_physics_process_steps_before_reading_q fails when run in one session with the other player test scripts.
origin: spec-deferred aa9a4085355f
location: game/tests/unit/test_player_barrage.gd:201
source_spec: `spec-dw-55-player-split-health-shield.md`
reason: Reported by the implementation subagent: the six existing player scripts run together fail it at line 201 (0 launches, expected 1) on baseline 4cb60cd too; it passes alone and in the full-suite run (913/913). Suspected leaked simulated Q press; unconfirmed.
status: done 2026-10-10
resolution: already resolved: Player tests moved onto the shared fixture in d1f3fdc (sweep dw-player-test-fixture: DW-56, right after the DW-55 split a0e67e9); a 2026-10-10 headless GUT run of all 14 test_player*.gd scripts together passed 191/191 including test_player_barrage.gd::test_physics_process_steps_before_reading_q (now at line 163, after_each releases ability_barrage at line 40).

### DW-74: test_feedback.test_hit_stop_overlap_keeps_longest is wall-clock sensitive and failed once in a full run ("resumed promptly": 356 ms, expected < 250 ms), then passed on re-run.
origin: spec-deferred 6bef7359b27c
location: game/tests/unit/test_feedback.gd:262
source_spec: `spec-4-2-unlock-the-next-level-and-save-progress.md`
severity: low
reason: Pre-existing flake, not caused by Story 4.2 (feedback.gd and test_feedback.gd are untouched). Seen in the first full GUT run of this story's verification; the immediate re-run and the post-patch run were 973/973 and 977/977. The same test also flips to Pending ("second hit_stop came too late").
status: done 2026-10-11
resolution: resolved by sweep bundle dw-timing-test-flake-hardening
resolution-undo: 324a3f451d2eae5eb6c77955191b77f0dd5da2251e0e4af797eab07487d0a99d 2026-10-11 7374617475733a206f70656e

### DW-75: "First outcome wins" is enforced at the only current emitter (Player); RetryPrompt still reacts to any level_failed, so a future emitter (convoy, Epic 6) must not fail a cleared level.
origin: spec-deferred f1a1e137a1cd
location: game/ui/menus/retry_prompt.gd:125
source_spec: `spec-dw-54-level-ends-exactly-once.md`
severity: low
reason: ui/menus/retry_prompt.gd opens on the first Events.level_failed with no level_cleared check; events.gd documents a &"convoy" reason with no emitter yet. Today Player is the only emitter and is gated by _safe, so nothing is reachable now.
status: resolved
resolution: resolved by Story 6.1: RetryPrompt ignores level_failed after Events.level_cleared, and the Convoy ignores damage once any outcome is decided; tests in test_retry_prompt.gd and test_convoy.gd.

### DW-76: No Config test covers a missing comms.combat_line_max_chars (or comms.story_line_max_chars) tuning key: the single Log.error and the -1 fallback are untested.
origin: spec-deferred 38eece5e1f8f
location: game/autoloads/config.gd:253
source_spec: `spec-5-2-hear-combat-chatter-without-stopping-the-fight.md`
severity: low
reason: The verification-gap reviewer searched game/ for the "line length not checked" message and the _line_max_chars helper; only config.gd uses them, and every test loads the real tuning where both keys exist. Shipped tuning always has the keys. One test through _load_dialogue with a temp tuning lacking both keys would cover both kinds.
status: done 2026-10-11
resolution: resolved by sweep bundle dw-config-line-max-missing-key-test
resolution-undo: 7419951b1ea4858cced7e6c748234f7153bebdf6df6ebfea3e80707c6293e2b9 2026-10-11 7374617475733a206f70656e

### DW-77: The WaveDirector's wave-clear gap still awaits a SceneTreeTimer, which outlives the director, so a death reload during the gap before the next wave or the outro resumes a coroutine on a freed
origin: spec-deferred a59e24ebeb8d
location: game/systems/waves/wave_director.gd _try_clear
source_spec: `spec-5-3-trigger-dialogue-and-music-from-wave-events.md`
severity: low
reason: wave_director.gd _try_clear: `await get_tree().create_timer(_gap_s, false).timeout`, unchanged since Story 2.2 and kept on purpose by the Story 5.3 spec ("Leave the _try_clear gap timer as it is"). A level reload frees the director while the timer lives on the SceneTree; on timeout Godot may log "Resumed function after await, but class instance is gone". Not reproduced: a test that frees the director during the gap and checks the error output would settle it. The fix is the same child-Timer pattern used for `wait`.
status: done 2026-10-10
resolution: resolved by sweep bundle dw-wave-director-chain-lifetime
resolution-undo: 9f49191dc8277a424cc1f47d7f6bf5a505f0aa44e48eb95aa75be5b1195d0298 2026-10-10 7374617475733a206f70656e

### DW-78: Chains that keep running after a death (decision #39, DW-54) now also fire comms, story_event and music, so a chain resuming from a wait during the death beat can open a story pause over the death
origin: spec-deferred 7ecef071415f
location: game/systems/waves/wave_director.gd _run_chain
source_spec: `spec-5-3-trigger-dialogue-and-music-from-wave-events.md`
severity: medium
reason: wave_director.gd _run_chain never checks _failed (by design: decision #39 says "running chains and group spawns still run" after level_failed, and the Story 5.3 intent says not to change the DW-54 failure rules). A level chain such as [wait 2, comms story_x] whose wait ends after the death but before the reload emits comms_sequence_requested; a story sequence then pauses the tree via PauseArbiter on top of the death beat. Not reachable with shipped data (no real level has beats until Epic 7). Settling it needs a human decision extending decision #39: should comms, story_event and music be dropped once _failed is set? The fix would be a `_failed` skip on those three actions plus a test.
status: done 2026-10-10
resolution: resolved by sweep bundle dw-wave-director-chain-lifetime
resolution-undo: 9f49191dc8277a424cc1f47d7f6bf5a505f0aa44e48eb95aa75be5b1195d0298 2026-10-10 7374617475733a206f70656e
decision: 2026-10-10 Stop the whole chain after a fail — Abort running chains when level_failed fires (all actions, including spawn_group), with tests, and amend decision #39 accordingly.

### DW-79: test_shake_camera.test_process_drives_shake is frame-timing sensitive and failed once in a full run ("_process moves the offset": offset still Vector2.ZERO after 3 process frames), then passed on re-run.
origin: quick-dev
location: game/tests/unit/test_shake_camera.gd:90
source_spec: `spec-5-1-comms-open-radio-sfx.md`
severity: low
reason: Pre-existing flake, not caused by the comms-open SFX change (shake_camera.gd and its test are untouched). Seen in the first full GUT run (1340/1341); the immediate full re-run passed. Likely a near-zero headless frame delta or a sampled offset of zero within 3 frames.
status: done 2026-10-11
resolution: resolved by sweep bundle dw-timing-test-flake-hardening
resolution-undo: 324a3f451d2eae5eb6c77955191b77f0dd5da2251e0e4af797eab07487d0a99d 2026-10-11 7374617475733a206f70656e

### DW-80: A long SFX (the 6.0 s comms_static) is the first player Audio steals once all pool players are busy, so heavy combat during the cut-off hold can stop the static early.
origin: quick-dev
location: game/autoloads/audio.gd _pick_player
source_spec: `spec-5-4-cut-off-readability-and-impact.md`
severity: low
reason: _pick_player steals the oldest busy player when the pool is full, and a 6 s clip is almost always the oldest. Not observed; needs about 12 overlapping SFX during the hold. A fix would let a caller mark a player as not stealable (or reserve one comms player) and needs a decision on the Audio API.
status: done 2026-10-11
resolution: resolved by sweep bundle dw-audio-reserved-comms-player
resolution-undo: fff6e2aacda1cc7a18526fac647cedcbde1668e84e27df64c510acd48f7f0f73 2026-10-11 7374617475733a206f70656e
decision: 2026-10-10 Reserve a dedicated comms player — Give Audio a separate player (or small pool) for comms cues that combat SFX never steal, route comms_static/comms_open through it, and add tests.

### DW-81: A story request during the cut-off line's typing window (now about 2.4 s instead of 0.87 s) drops the cut-off with none of its effects, and a wave clear in that window skips the silence while the static, shake and music stop still fire.
origin: quick-dev
location: game/systems/comms/comms_channel.gd _preempt_combat / _on_wave_cleared
source_spec: `spec-5-4-cut-off-readability-and-impact.md`
severity: low
reason: Pre-existing 5.4 rules (preempt drops effects, void rule), made about 3x more likely by the slower typing. No shipped data requests a story near Tarek's cut-off. Story 6.5 / Epic 7 data should keep the Level 2 Wave 5 cut-off clear of story requests and of the wave end; otherwise decide whether a cut-off should be preempt-proof.
status: done 2026-10-13
resolution: already resolved: the Tarek's fall rework (decision #63, TarekFallScene) locks the player, holds enemy fire and leaves no story request near the cut-off; the only nearby line (the Level 2 outro) plays after the wave-clear gap. Remaining edge (a pre-lock Barrage clearing the last wave mid-typing drops the cut-off) judged too unlikely to keep open (operator 2026-10-13).

### DW-82: The 2.5 s cut-off hold (6.0 s when logged) occupies the interruption box, so when the wave clears during the hold the next wave's opening combat lines queue behind it (up to about 2.5 s late) or are dropped past comms.combat_queue_max.
origin: quick-dev
location: game/systems/comms/comms_channel.gd step_combat
source_spec: `spec-5-4-cut-off-readability-and-impact.md`
severity: low
reason: A consequence of the user's 2.5 s hold (GDD #43, revised from 6.0 s and then 4.5 s). Level 2 Wave 6 data (Epic 7) should not open with combat chatter, or the hold should end early on wave_cleared; that needs a design call.
status: done 2026-10-13
resolution: already resolved: the cut-off plays in Level 2's last wave (5 of 5), so no next wave's combat lines can queue behind the hold; the outro story line replaces the cut-off instead of waiting (sweep triage 2026-10-13, closed by operator).

### DW-83: The Player's 64 px hull circle fits through the 72 px hitbox pocket between the flankers' front edges and the lead's rear edge, so the ship can slip vertically through the triangle.
origin: spec-deferred b923c06c4a79
location: game/entities/player/player.gd resolve_hull / game/entities/allies/convoy.gd ship_centre
source_spec: `spec-6-1-protect-the-convoy.md`
reason: Hitbox centres are 200 px apart in x (160 + 40 gap) and the hitboxes are 128 px wide, leaving 72 px; resolve_hull uses the hitbox rects (as the spec and the AC's HullArea-vs-convoy-layer mechanism prescribe). Whether slipping between formation ships is unwanted is not settled by GDD #25 (which forbids passing through hulls, not between them). Settle by an operator playtest of dev_convoy; if unwanted, close the pocket (resolve against drawn extents or add a gap rect).
status: done 2026-10-11
resolution: resolved by sweep bundle dw-convoy-solid-triangle-formation
resolution-undo: 4148b8ad8f610b4b2744f9b91979eed53fd79a44f1c339b47d52bbdbbd137634 2026-10-11 7374617475733a206f70656e
decision: 2026-10-10 Nose-up mock formation with one solid triangle — Confirmed in operator playtest: the ship slips through. Change the convoy formation to the UX mock layout: three cargo ships nose-up (not facing the travel direction), side by side, the middle (lead) ship raised so the group forms a shallow symmetric triangle, all inside the y 760-920 band; the whole group slides left/right as one, ping-pong per #45 (no mirroring needed, the formation is symmetric), starting on-screen at the left clear of the player spawn. Replace the per-ship player push-out with ONE solid triangular collision shape covering the whole formation, including the gaps between ships, so the player can never pass between them (slides along it, no damage, per #25). Enemy shots and Mauls still hit and damage individual ships; player/ally shots are still blocked per ship (#23, #46). Add player-convoy tests (cannot pass between ships from any side; slides along the triangle) and update existing convoy layout tests. Amend the GDD convoy rules (formation wording, 'lead about 40 px ahead'), epics.md FR32/Story 6.1 AC, game-architecture.md convoy notes, and add a decision-log row (clarifies #25, revises #24/#45 geometry). Ship art stays as is (DW-86, Story 8.2).

### DW-84: One unidentified intermittent failure in test_level.gd (57/58), seen once while the implementer re-ran it after the review patches.
origin: spec-deferred 978bd41bfe2f
location: game/tests/unit/test_level.gd
source_spec: `spec-6-3-defend-the-convoy-from-lancer-fire.md`
reason: The failing run's log wasn't captured. The next 12 implementer runs, 6 further runs and two full suites all passed (58/58, 1515/1515). It may be one of the two new real-time Lancer tests (test_dev_convoy_lancer_shots_hit_the_convoy_for_five, test_dev_lancer_shots_aim_at_the_player_without_a_convoy) or an older timing-sensitive test. Capturing the failing test's name from a failing run would settle it.
status: done 2026-10-11
resolution: resolved by sweep bundle dw-timing-test-flake-hardening
resolution-undo: 324a3f451d2eae5eb6c77955191b77f0dd5da2251e0e4af797eab07487d0a99d 2026-10-11 7374617475733a206f70656e

### DW-85: Wasps fly straight through asteroids, so asteroids can't be used as cover against diving Wasps; a Wasp that hits an asteroid should be destroyed.
origin: operator playtest 2026-10-10 (raised while deciding DW-57)
location: game/entities/enemies/wasp/wasp.gd / game/entities/hazards (asteroid) / CollisionLayers enemy masks
source_spec: n/a (operator request)
severity: medium
reason: The user wants asteroids to shield the player from Wasps as well as from projectiles (GDD pillar "cover gives the player an answer to every attack"; gdd.md:141 and :300 cover projectiles only and say nothing about enemy ships, so this is a design change and needs a decision-log entry). Open points for the decision: which enemies it covers (Wasp only, or also Hunter Wasp and Maul); whether the asteroid takes damage or breaks; whether a Wasp destroyed by an asteroid counts toward the wave clear, drops energy and counts as a player kill; the impact feedback tier.
status: open

### DW-86: Convoy ships are plain code-drawn pentagons; the UX mock shows detailed nose-up freighters (central hull, side cargo pods, engine glow).
origin: operator playtest 2026-10-10 (raised while deciding DW-83)
location: game/entities/allies/convoy.gd (_draw)
source_spec: `_bmad-output/planning-artifacts/ux-designs/ux-defector-game-2026-10-06/mockups` (convoy in the HUD mock)
severity: low
reason: Art only, for the Story 8.2 art pass: match the mock's freighter look (DESIGN.md: ~160x80 cargo hulls recoloured `coalition` with a dimmer body). The formation and collision shape are settled separately by DW-83 (nose-up, middle ship raised, one solid triangle); this entry is only the ship drawing.
status: open

### DW-87: The class_name trigger list covers `extends` and `@icon` edits but not adding or removing `@abstract` or `@tool` on a script that keeps its `class_name`, though the global class cache records those
origin: spec-deferred caa1a8ec97eb
location: AGENTS.md:30; _bmad-output/game-architecture.md:1393-1395
source_spec: `spec-dw-62-dw-66-agents-md-import-and-commit-wording.md`
severity: low
reason: `game/.godot/global_script_class_cache.cfg` entries carry `base`, `class`, `icon`, `is_abstract`, `is_tool`, `language` and `path`, so toggling `@abstract`/`@tool` leaves the cache stale for headless `-s` runs. No game script uses either today, so it is rare. The fix edits AGENTS.md:30 (agent-context file) and its architecture copy.
status: open

### DW-88: The CLI export block's import comment is called a "copy" of the AGENTS.md note (and AGENTS.md says to change all copies together), but it repeats only the first clause and points elsewhere for re-run
origin: spec-deferred 7d969e5a29e8
location: AGENTS.md:30; _bmad-output/game-architecture.md:1293-1295, 1391-1392
source_spec: `spec-dw-62-dw-66-agents-md-import-and-commit-wording.md`
severity: low
reason: game-architecture.md:1293-1295 says "Copy of the note in AGENTS.md ... see it or the headless CLI block ... for when to re-run"; game-architecture.md:1391-1392 calls it "another copy"; AGENTS.md:30 names it among "the copies". Calling it a short form/pointer in all three places removes the ambiguity. The fix edits AGENTS.md (agent-context file).
status: open

### DW-89: AGENTS.md section 5 now gives a form for bmad-loop/orchestration retro commits and for hand-written retro revisions, but not for a first retrospective a person writes by hand (previously covered by
origin: spec-deferred e327f358a1f5
location: AGENTS.md:62-63
source_spec: `spec-dw-62-dw-66-agents-md-import-and-commit-wording.md`
severity: low
reason: AGENTS.md:62 covers "retro commits made by bmad-loop or orchestration"; AGENTS.md:63 now says "hand-written retro revisions" where it used to say "retros". Wording such as "hand-written retros (first pass or revision)" closes the gap. The fix edits AGENTS.md (agent-context file).
status: open

### DW-90: Epic 7 boss ACs and the GDD/FR49-FR51 boss cadence lines still use the "every N s after a G s glow" wording that DW-70 rewrote for Stories 2.5 and 2.7.
origin: spec-deferred 739a3e585011
location: _bmad-output/planning-artifacts/epics.md (Epic 7 story ACs)
source_spec: `spec-dw-57-dw-69-dw-70-epic-docs-decision-log-sync.md`
severity: low
reason: epics.md Story 7.x ACs (about lines 1654, 1688, 1724), FR49-FR51 (epics.md:133-135) and gdd.md:283-285 are unchanged. Decision #50, the architecture Flagship cadence bullet and the data test now state start-to-start, but an Epic 7 implementer reading only the ACs could build interval + glow. Rewording those ACs is a planning-doc change the DW-69 decision did not ask for, so it needs the operator's OK.
status: done 2026-10-11
resolution: resolved by sweep bundle dw-decision-dw-90
resolution-undo: a8c4aa599f0a3b24de3c7d67cc7f582083717f6e79fc392d0eadaedab123c87f 2026-10-11 7374617475733a206f70656e
decision: 2026-10-11 Reword FR49-FR51, the Epic 7 ACs and the GDD Flagship table to start-to-start — Reword FR49-FR51 (epics.md:133-135), the Epic 7 story ACs (epics.md around lines 1654, 1688 and 1724) and the GDD Flagship phase table (gdd.md:283-285) to the start-to-start wording used for Stories 2.5/2.7 (e.g. 'fires every 3.0 s start-to-start; the 0.5 s glow runs inside that period, then it fires'). Keep every number. Record the change in the GDD decision log with a reference to decision #50 and DW-70. Docs only, no code or data changes.
decision: 2026-10-11 Reword FR49-FR51, the Epic 7 ACs and the GDD Flagship table to start-to-start — Reword FR49-FR51 (epics.md:133-135), the Epic 7 story ACs (epics.md around lines 1654, 1688 and 1724) and the GDD Flagship phase table (gdd.md:283-285) to the start-to-start wording used for Stories 2.5/2.7 (e.g. 'fires every 3.0 s start-to-start; the 0.5 s glow runs inside that period, then it fires'). Keep every number. Record the change in the GDD decision log with a reference to decision #50 and DW-70. Docs only, no code or data changes.

### DW-91: test_level.gd test_dev_convoy_maul_wave_hits_the_convoy is intermittent ("at its slot's y": 179.3 vs 160 +/- 13.3).
origin: spec-deferred 70466bae9005
location: game/tests/unit/test_level.gd (test_dev_convoy_maul_wave_hits_the_convoy)
source_spec: `spec-dw-57-dw-69-dw-70-epic-docs-decision-log-sync.md`
severity: medium
reason: Failed in 2 of 3 full headless runs and 1 of 3 isolated runs of test_level.gd during this bundle; passed in the others. The bundle touches no runtime code, only docs and one data test. Likely frame-timing sensitive, like DW-79 (test_shake_camera, which also flaked once in this run).
status: done 2026-10-11
resolution: already resolved: f304e95 (after the b395276 bundle that filed DW-91) replaced the fixed 2-tick tolerance (2*speed/60 = 13.3 px, the failing bound) with a physics-tick-scaled one: spawn_tick captured on Events.wave_started and flown_ticks = detect_tick - spawn_tick + 1 at game/tests/unit/test_level.gd:1408-1411,1446-1450; the isolated test passed 5 of 5 headless runs on 2026-10-11 (it failed 1 of 3 before).

### DW-92: A single needle entry that spans more than one formation row (count above max_columns, or a grid_CxR with R > 1) reserves rows 1..n that stay empty, and Needles in the same column overlap on row 0.
origin: spec-deferred 719efcc1047a
location: game/systems/waves/level_validator.gd:_check_anchored_list
source_spec: `spec-dw-67-dw-68-level-validator-group-rules.md`
severity: low
reason: Formation.slots wraps or stacks the entry over several rows and WaveDirector advances _next_row by Formation.rows_used, but needle.gd anchors every Needle at enemies.needle.anchor_y_px whatever its slot y. DW-68's rule only checks the entries before a Needle, not how many rows the Needle entry itself takes. No shipped wave does this (both Needle entries are grid_2x1).
status: open

### DW-93: Nothing enforces enemies.needle.anchor_y_px == waves.formation.top_y, which the "Needle is the first row-taker" rule (DW-68) takes for granted.
origin: spec-deferred 6d893b736db5
location: game/tests/data/test_data_files.gd:test_needle_tuning_ranges
source_spec: `spec-dw-67-dw-68-level-validator-group-rules.md`
severity: low
reason: test_needle_tuning_ranges only checks that anchor_y_px is inside the enemy zone. If either tuning value changes, even a first-in-wave Needle stops lining up with row 0. Pre-existing tuning coupling; not introduced by this change.
status: open

### DW-94: The Player's 64 px hull circle can visibly overlap drawn cargo hulls (up to 16 px at the sides, about 8 px at the lead's top, more at the nose tips) because solidity uses the 80% hitboxes, not the
origin: spec-deferred 433360990799
location: game/entities/allies/convoy.gd _place_ships
source_spec: `spec-dw-83-convoy-solid-triangle-formation.md`
severity: low
reason: hull_polygon() is built from ConvoyShip.hull_rect() (128x64 hitboxes) while hulls are drawn 160x80; Story 6.1 already resolved against the hitbox rects, so this predates DW-83. Settle by operator playtest of dev_convoy: if the overlap reads badly, build the polygon from the drawn extents (hull_size) instead.
status: open

### DW-95: The Flagship turrets are "staggered" (FR49, Story 7.3, GDD phase 1) but no stagger offset is defined in the docs or in `tuning.json` `boss.turrets`.
origin: spec-deferred 838210c950e1
location: _bmad-output/planning-artifacts/epics.md (FR49, Story 7.3); game/data/tuning.json (boss.turrets)
source_spec: `spec-dw-90-boss-cadence-start-to-start-wording.md`
severity: low
reason: `boss.turrets` has count, hp, spread_bullets, bullet_speed_px_s, fire_interval_s 3.0 and telegraph_s 0.5, with no stagger key; the architecture doesn't define it either. Under start-to-start the stagger is the only thing that separates the four turrets' clocks, so an Epic 7 implementer must invent a value (and must put it in data, per AGENTS.md). Pre-existing; this rewording didn't cause it.
status: open

### DW-96: Whether the Level 1 convoy (100 HP) survives real play against 7 Mauls and Lancer fire is unverified; the integration test raises its HP to 100000.
origin: spec-deferred b0f61076fa31
location: game/data/levels/level_1.json
source_spec: `spec-7-1-play-level-1-cargo-ambush.md`
reason: Maybe-false: 3 + 4 Mauls at 10 damage each is 70, and Lancers aim at the convoy 50 % of the time for 5 per hit, so a slow player could lose the convoy. Settled by the operator playtest in operator_actions (watch convoy HP per GDD decision #23); a retune belongs in tuning.json.
status: open

### DW-97: The level-root "music" key is still unread, so Level 1 states "combat" twice (the root key and a W1 music action) and nothing owns wiring the root key.
origin: spec-deferred dcdfdd460b89
location: game/systems/waves/wave_director.gd
source_spec: `spec-7-1-play-level-1-cargo-ambush.md`
severity: low
reason: Pre-existing since Story 5.3 (architecture As-built 5.3: "Story 8.1 or Epic 7 can wire it"). Stories 7.2 and 7.6 will copy the duplicated pattern, and a later edit to one copy can silently disagree with the other. Wiring it is a WaveDirector change, which is outside this data-only story.
status: open

### DW-98: Level 2 wave 5 puts the 160 px Bastions (row y 250) in the same columns as the Needles (y 160), so each Needle can start shielded from below; Bastions in waves 2 and 4 also overlap the next Wasp row
origin: spec-deferred f397e13c8a49
location: game/data/levels/level_2.json
source_spec: `spec-7-2-play-level-2-the-blockade.md`
reason: Maybe-false: both entries are grid_2x1 from the top, so they share x slots, and the Bastion hull spans y 170-330 against the Needle's 120-200. Whether this hurts play depends on the Bastion drift and the Needle reposition (every 8 s), so it is settled by the operator playtest in operator_actions; a fix would be a layout change in level_2.json.
status: open

### DW-99: No automated test proves the throne-world placeholder arc is actually rendered on screen; the tests check LevelBackground state, colours, geometry and node order only.
origin: spec-deferred db8006c82555
location: game/scenes/level/level_background.gd
source_spec: `spec-7-6-play-level-3-siege-of-the-throne-world.md`
reason: Maybe-false (intent-alignment layer): headless GUT runs on the dummy renderer, so pixels can't be checked there. The draw path is a single draw_colored_polygon plus draw_polyline over a convex circular segment, called after apply(). Settled by the operator playtest in operator_actions (the arc must be visible in Level 3 and absent in Levels 1 and 2).
status: open

### DW-100: Whatever music is playing when Level 3 clears (the boss track from the boss wave's music action) keeps playing on the end screen, because no scene change or end-screen code stops music.
origin: spec-deferred bb58da098d13
location: game/autoloads/scene_router.gd (goto_end) / game/scenes/end/end_screen.gd (_ready)
source_spec: `spec-7-7-end-the-war-isoldes-final-line-and-the-end-screen.md`
severity: medium
reason: Audio is an autoload and music is stopped only by a `music: stop` action (Audio.apply_music_action); SceneRouter._change_to and EndScreen._ready never touch music. This is the same carry-over every scene change already has (e.g. a level to the title). No music track ships until Story 8.1, so nothing is audible today; Epic 8's audio pass should decide the end screen's music (stop, fade, or an ending theme). The Story 7.7 as-built entry now states the carry-over.
status: open

### DW-101: After the Flagship's core is destroyed the player can still die during the 2 s death chain, to leftover boss Wasps and bullets already in flight, which fails the level after the boss is beaten.
origin: operator playtest 2026-10-13 (Story 7.5 operator action 5)
location: game/entities/boss (Flagship DYING) / game/entities/player/player.gd is_safe / game/systems/waves/wave_director.gd
source_spec: `spec-7-5-make-the-final-choice-phase-3.md`
severity: medium
reason: By design today (decisions #39 and F16: the player is safe only from level_cleared, and launched Wasps stay alive), flagged by the Story 7.5 review and passed to the operator, who decided the boss's death must end the danger at once.
status: open
decision: 2026-10-13 Boss death ends the fight — The moment the Flagship's core is destroyed (the start of the 2 s death chain / DYING), the fight is over: (1) the Player becomes safe at once, exactly as after level_cleared (decision #39's is_safe(): no damage, no hazard contact, cannot die or emit level_failed); (2) every remaining enemy (launched Wasps and anything else alive) explodes during the death chain through the normal Spawner/Feedback paths, staggered with or alongside the chain explosions, with no energy drops and no kill/progress side effects that could re-trigger beats; (3) every enemy bullet in flight fizzles (removed with the small blocked-shot effect); no new enemy shots or launches start. The wave and level then clear as today. Amend decision #39 (safe from the boss's death, not only from level_cleared) and F16, add a GDD decision-log row, update the Story 7.5 notes/ACs in epics.md and the architecture boss section, and add tests: a hit during DYING costs nothing; leftover Wasps and bullets are gone by the end of the chain; level_cleared still fires once.
