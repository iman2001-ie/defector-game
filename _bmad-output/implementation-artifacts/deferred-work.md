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
status: open

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
status: open

### DW-20: After a resume warp the next physics tick may still read the pre-warp mouse position, giving a one-tick ship jump.
origin: spec-deferred c9296c5c0ffe
location: game/entities/player/player.gd _on_resumed / step_lock
source_spec: `spec-1-8-lock-the-ship-to-the-cursor-and-fire-missiles-straight-up.md`
reason: Unverified (maybe-false). Depends on whether Viewport.get_mouse_position() queries the OS cursor (immediate after SetCursorPos) or the last motion event. Settle with a live pause/resume test once Story 4.4 adds the pause menu; tests only use a recorder Callable.
status: open

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
status: open

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
status: open

### DW-26: Re-run the Epic 1 retrospective once Stories 1.8-1.10 are done
origin: retro action item epic-1-retro-item-14-re-run-the-epic-1-retrospective-once-sto
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-1-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 1; owner Developer; sprint-status status open)
status: open

### DW-27: The --no-prewarm wiring through Sandbox._ready and DebugTools._ready is not covered by any test, so a regression could mislabel the prewarm on/off comparison.
origin: spec-deferred def51ca50f5c
location: game/ui/debug/debug_tools.gd _ready; game/scenes/sandbox/sandbox.gd _ready
source_spec: `spec-dw-9-dw-21-stress-bench-nfr-peak.md`
severity: medium
reason: Both _ready methods read OS.get_cmdline_user_args() directly, so tests cannot inject --no-prewarm. Tests cover only DebugArgs.parse, the static Sandbox.should_prewarm, and DebugTools with _prewarm set by hand. Deleting `_prewarm = args.prewarm` in debug_tools.gd would leave the suite green. Fix: an injectable user-args source for both _ready paths (the --stress wiring has the same gap).
status: open

### DW-28: AGENTS.md section 5 still requires a story id or key, so bmad-loop's other commit subjects (`sweep <bundle>: DW-n via bmad-loop`, `chore(sweep|operator|decisions|retro): ...`) and manual non-story
origin: spec-deferred ca109689f523
location: AGENTS.md:60
source_spec: `spec-dw-15-dw-16-agents-md-import-and-commit-format.md`
severity: medium
reason: git log shows `sweep dw-stress-bench-nfr-peak: DW-9, DW-21 via bmad-loop`, `chore(operator): confirm ...`, `chore(decisions): pre-answer DW-15`, `Epic 1 retro: revision 2`. The DW-15 decision only covers the `story <key>: ...` form, and the fix edits AGENTS.md (agent-context file), so it is deferred.
status: open

### DW-29: The --import re-run triggers name only adding class_name scripts or imported assets; renaming, moving or deleting class_name scripts, changing imported assets, and pulling or switching branches that
origin: spec-deferred e5e258f88c18
location: AGENTS.md:30; _bmad-output/game-architecture.md:1335-1337
source_spec: `spec-dw-15-dw-16-agents-md-import-and-commit-format.md`
severity: low
reason: Headless -s runs never rescan the class cache, whatever the cause of the change. A typical symptom is a parse error naming a class_name that exists. The fix edits AGENTS.md (agent-context file), so it is deferred.
status: open

### DW-30: The DW-15 decision (amend AGENTS.md section 5) is recorded only in the deferred-work ledger, not in a decision log as AGENTS.md section 4 asks.
origin: spec-deferred 5bfb1d58f231
location: _bmad-output/implementation-artifacts/deferred-work.md (DW-15)
source_spec: `spec-dw-15-dw-16-agents-md-import-and-commit-format.md`
severity: low
reason: Commit `chore(decisions): pre-answer DW-15` recorded it in the ledger before this run. No process decision log exists, and the GDD decision log covers game design. This is pre-existing and not caused by this change.
status: open

### DW-31: The --import re-run reason ("headless -s runs don't rescan the class cache") explains only the class_name trigger; it does not say why new imported assets also need a re-run (headless -s runs don't
origin: spec-deferred a79436289cb2
location: AGENTS.md:30; _bmad-output/game-architecture.md:1335-1337
source_spec: `spec-dw-15-dw-16-agents-md-import-and-commit-format.md`
severity: low
reason: AGENTS.md:30 and game-architecture.md:1335-1337 list "new imported assets" as a trigger, but the stated cause is only the class cache. A new WAV that Audio preloads has no .import artefact until --import runs. The instruction itself is still correct, so following it gives the right result. The fix edits AGENTS.md (agent-context file), so it is deferred.
status: open

### DW-32: Projectile._on_area_entered calls apply_damage on any overlapped area, so once a convoy with apply_damage exists, player bolts (now masking CONVOY) would damage it instead of being blocked with no
origin: spec-deferred f39d733a65b1
location: game/core/projectile.gd:49
source_spec: `spec-dw-2-dw-10-laser-mask-player-shots.md`
severity: medium
reason: game/core/projectile.gd:49-54 has no convoy check. FR7, GDD #23 and game-architecture.md:310 require player shots to be blocked by the convoy without damage. No convoy exists until Epic 6, so nothing breaks today. The Epic 6 convoy story must add the no-damage path, plus a test that a convoy-layer area stops a bolt without apply_damage.
status: open

### DW-33: Missile._on_impact always runs apply_splash, so a missile stopped by a convoy ship (missile mask already includes CONVOY) would still splash enemies and asteroids near the convoy; whether a blocked
origin: spec-deferred 27d4e4bd97cb
location: game/entities/projectiles/missile.gd:27
source_spec: `spec-dw-2-dw-10-laser-mask-player-shots.md`
reason: game/entities/projectiles/missile.gd:27-29 calls apply_splash before super._on_impact for every hit. missile.tscn has masked CONVOY (84) since Story 1.5, so this predates DW-2/DW-10. epics.md:1409-1411 (Epic 6 convoy story) says missiles reaching a convoy ship are "stopped and free itself, the convoy takes no damage", but says nothing about splash on nearby enemies. Settle by a design ruling in the Epic 6 convoy story (detonate with splash vs. fizzle) and a test for it.
status: open

### DW-34: The Bastion's y 80–400 drift range may let a large sprite overlap the 0–120 px HUD band and the wave bar.
origin: spec-deferred c6c13658c554
location: _bmad-output/planning-artifacts/gdds/gdd-game-project-2026-10-06/gdd.md:269
source_spec: `spec-2-1-count-wave-progress-and-evaluate-beat-triggers.md`
reason: Pre-existing in the plan, not caused by Story 2.1: GDD gdd.md L269 and epics.md FR22/L829 set "y 80–400", while the UX layout puts the HUD band at 0–120 and the wave bar at y 40. Whether a sprite actually overlaps depends on the Bastion's sprite size and how its y is clamped. To settle it, check the Bastion story (Epic 2) against DESIGN.md's layout bands before building the Bastion.
status: open

### DW-35: test_f3_resolves_the_wave_and_fires_pending_triggers_in_order fails deterministically in this environment ("the skipped group never spawns", expected 0 got 1).
origin: spec-deferred 25bf8310c4a6
location: game/tests/unit/test_wave_director.gd:347
source_spec: `spec-2-3-watch-the-wave-progress-bar-fill.md`
severity: medium
reason: Pre-existing (Story 2.2 test, untouched by 2.3): it fails 5/5 in isolation on HEAD and 2/2 at baseline 07bcc62 in a clean worktree. The test sets waves.gap_s = 0.05, then awaits 2 process frames and asserts no counted enemies; the log shows wave 2/2 (1 wasp) already started before the assert, so the 0.05 s gap elapses within those 2 headless frames. The earlier 2.3 pass saw it green, so it depends on frame timing.
status: open
