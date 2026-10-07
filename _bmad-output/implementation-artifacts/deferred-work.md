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
status: open
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
status: open

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
status: open
decision: 2026-10-07 Build the bench now — Extend the --stress/--bench sandbox mode to sustain about 200 live projectiles or moving enemies, report p99 and max frame time alongside the average with PASS judged on all three, and add a first-large-explosion measurement with and without Feedback.prewarm(). Leave the on-hardware run itself to the operator.

### DW-10: Decide the laser collision mask (recommend MASK_PLAYER_SHOTS=84), derive masks from CollisionLayers or test equality, and correct the epics.md Story 1.3 AC (DW-2)
origin: retro action item epic-1-retro-item-4-decide-the-laser-collision-mask-recommen
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-1-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 1; owner Developer (decision) then Dev loop; sprint-status status open)
status: open
decision: 2026-10-07 Follow the architecture: mask 84 — Set the laser bolt mask to CollisionLayers.MASK_PLAYER_SHOTS (84), preferably assigned from CollisionLayers in code or guarded by a test that asserts exact mask equality for laser and missile. Correct the Story 1.3 AC in epics.md to include convoy and record the decision in the decision log. This also closes DW-2.

### DW-11: Reconcile game-architecture.md with the as-built: play_sfx pitch param, tier sfx_volume_db, single explosion scene, Spawner/ShakeCamera to Feedback registration, CLI stress/bench modes
origin: retro action item epic-1-retro-item-5-reconcile-game-architecture-md-with-the
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-1-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 1; owner Developer / Architect; sprint-status status open)
status: open
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
status: open

### DW-15: Fix the epic-1 status in sprint-status, and align the bmad-loop commit subject format with AGENTS.md section 5 (or amend section 5)
origin: retro action item epic-1-retro-item-9-fix-the-epic-1-status-in-sprint-status-a
location: n/a
source_spec: `_bmad-output/implementation-artifacts/epic-1-retro-2026-10-07.md`
severity: low
reason: retrospective action item from sprint-status.yaml (epic 1; owner Developer; sprint-status status open)
status: open

### DW-16: The new docs call the --import step "one-time", but an existing checkout also needs it re-run after adding class_name scripts or new imported assets (or when game/.godot/ is stale).
origin: spec-deferred 3ba10d44cd3e
location: AGENTS.md:29-30; _bmad-output/game-architecture.md:1232
source_spec: `spec-dw-6-dw-12-gut-import-step-docs.md`
severity: medium
reason: Stories 1.2-1.5 each re-ran --import to refresh the class cache for new class_name types (Player, Projectile, Enemy, Missile). Headless -s runs do not rescan the class cache. The fix rewords AGENTS.md (agent-context file), so it is deferred.
status: open

### DW-17: The architecture's CLI export command has the same fresh-clone gap: it runs --export-release without a prior --import.
origin: spec-deferred 3ac631213abb
location: _bmad-output/game-architecture.md:1141
source_spec: `spec-dw-6-dw-12-gut-import-step-docs.md`
severity: low
reason: Story 1.7 had to run --import before --export-release. Pre-existing; the bundle intent covers only the test command.
status: open

### DW-18: The godot-testing.md knowledge files show GUT commands with no --path and no import step, so agents reading them still get the failing fresh-clone procedure.
origin: spec-deferred c0aa3f8fe839
location: .claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md
source_spec: `spec-dw-6-dw-12-gut-import-step-docs.md`
severity: low
reason: .claude/skills/gds-agent-game-dev/gametest/knowledge/godot-testing.md (and its .agents/skills copy) are untouched by this change; pre-existing agent-context files outside the intent's two named locations.
status: open

### DW-19: The real F5 path (input event, then get_tree().reload_current_scene and consumers re-reading Config) is still untested; tests inject restart_scene and call reload_data() directly.
origin: spec-deferred 8ed8e1eb8e32
location: game/ui/debug/debug_tools.gd:28,51-52
source_spec: `spec-dw-8-config-validating-reload.md`
severity: low
reason: Pre-existing gap (epic 1 retro finding B4, deferred there). This change keeps the injected-restart test seam; the B1 failure it fixes is pinned at the Config and reload_data() level only.
status: open
