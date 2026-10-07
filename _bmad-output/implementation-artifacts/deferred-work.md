### DW-1: No automated check that the boot [INFO][data] summary line is emitted at INFO level.
origin: spec-deferred e60b6cd07bb5
location: game/autoloads/config.gd:22
source_spec: `spec-1-1-set-up-the-godot-project-and-data-driven-foundation.md`
severity: low
reason: Verification-gap layer: removing _log_summary() from Config._ready() leaves all tests green; the line is only seen by reading GUT output. Capturing Log output needs a sink or last-line hook, which this story does not add.
status: open
