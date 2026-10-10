---
status: blocked
---

# BMad Build Auto Result

## Auto Run Result

Status: blocked
Blocking condition: intent gap. Story 6.1 needs two design decisions that the GDD, architecture, epics and UX spec don't make. Each has more than one reasonable reading, and the readings play differently. The project rules say not to pick one silently, so planning stopped before a spec was written.

**Q1. What does the convoy do after it crosses the screen?** GDD FR32/FR42, epics FR32 and the Story 6.1 AC all say the group "crosses the screen left to right at 40 px/s within y 760–920, then loops back". That fits two behaviours:
- (a) **Wrap:** the group flies off the right edge and comes back in from the left. Each crossing takes about 57 s, and for a few seconds per loop some or all of the cargo ships are off-screen, where Mauls and Lancers could still target them.
- (b) **Turn around:** the group reverses at the edge and flies right to left, then back again, so it never leaves the screen. If so, does the triangle flip so the lead ship still leads?
- Also: does the group start off-screen left and fly in when the level starts, or start on-screen? The player spawns at (960, 900), inside the convoy band.

**Q2. DW-33: when a convoy ship stops a player missile, does the missile still splash?** `Missile._on_impact` always runs `apply_splash`, so a missile stopped by a cargo hull would deal splash damage to enemies and asteroids within 120 px. The AC says only "the shot is stopped and frees itself, the convoy takes no damage". The DW-33 ledger entry asks for a ruling in this story: (a) **detonate**, with splash on nearby enemies and a MEDIUM impact, but no convoy damage; or (b) **fizzle**, with no splash.

Evidence gathered (for the re-run):
- The scaffolding is already in place: the `CollisionLayers.CONVOY` (64) and `ALLIES` (128) layers, every player and enemy projectile scene masking the convoy, `Events.convoy_hp_changed`, `level_failed(&"convoy")`, the RetryPrompt's `CONVOY LOST` reason, `World/Allies` in `level.tscn`, and the tuning keys `tuning.convoy.*`, `player.hull_diameter_px` (64) and `damage.convoy_*`.
- Still needed: the no-damage block in `Projectile._on_area_entered`/`_can_damage` (DW-32), the ruling on DW-33 and a guard against the convoy failing a level that has already cleared (DW-75).
- I compiled the Epic 6 context to `_bmad-output/implementation-artifacts/epic-6-context.md`. It is untracked and isn't committed yet. No code, test or planning files were changed.

To resume: record the answers to Q1 and Q2 in the GDD decision log (Q2 can also go in as a `decision:` line on DW-33), then re-dispatch `6-1-protect-the-convoy`.
