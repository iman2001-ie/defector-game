class_name TarekFallScene
extends Node2D
## Tarek's fall as a readable scene (Story 6.5, reworked after the Epic 7
## playtests, 2026-10-13 and 2026-10-14). A node of level.tscn; it starts on
## Events.story_event_requested(&"tarek_fall") (Level 2 wave 5) and runs one
## timeline on its own clock in game time, so it slows with Feedback's slow
## motion and freezes under a pause or a hit-stop. Every number comes from
## tuning `story.tarek_fall`. Its two story beats are paused, press-to-continue
## story sequences (playtest J, GDD decision log): the director requests each
## one and waits for Events.comms_sequence_finished before going on.
##
##   LOCK       0: the alarm (maul_alarm); a red lock-on line runs from the
##              top edge to Vale; Vale's controls lock (Player.set_scripted_lock:
##              held in place, invulnerable); enemies hold their fire
##              (Spawner.hold_enemy_fire). At warn_after_s the warning beat
##              (WARNING_SEQUENCE, Tarek: "Watch out, General! ...") is requested.
##   WARNING    the story pause holds the tree; on its `finished` Tarek dashes to
##              intercept_offset_px above Vale (AllyShip.intercept) and the
##              clock restarts:
##   RUNNING    impact_s - ram_travel_s: the lock-on line goes; the Ram dives from
##              above Vale straight at Tarek (Spawner.spawn_ram), too fast to
##              dodge. impact_s - slowmo.lead_s: Feedback.slow_motion(scale,
##              hold_s, ramp_s). impact_s (the Ram arrives, or the clock without
##              a Ram): a LARGE impact on Tarek, AllyShip.take_hit (he spins away
##              burning, gravely injured; Ryn's report says he lives), the music
##              fades out and the burning-fall sound (BURN_SFX) plays.
##   AFTERMATH  aftermath_after_s after the impact the down beat (DOWN_SEQUENCE:
##              Vale calls out, then the nameless static line "...") is
##              requested; its `silence_after` silences comms until the wave
##              clears.
##   CALLOUT    the story pause holds the tree; on its `finished` the clock
##              restarts:
##   SETTLE     release_after_s later controls and enemy fire come back (DONE).
##
## Without Vale the scene skips to the hit at once (Tarek falls where he is, the
## music fades, the burn plays) and requests both beats back to back; without a
## patrolling Tarek it does nothing. A level outcome (level_cleared /
## level_failed) mid-scene releases the lock and the fire at once and requests
## nothing more. It runs once per attempt (a retry reloads the scene).

## The story event that starts the scene, and the ally it applies to.
const EVENT: StringName = AllyShip.FALL_EVENT
const ALLY_ID: String = AllyShip.FALL_ALLY_ID
## The two story beats (data/dialogue/level_2.json): dialogue wiring, like
## SceneRouter's sequence constants, not tuning.
const WARNING_SEQUENCE: StringName = &"l2_w5_tarek_warning"
const DOWN_SEQUENCE: StringName = &"l2_w5_tarek_down"
const ALARM_SFX: StringName = &"maul_alarm"
## The burning-fall sound at the impact (playtest J).
const BURN_SFX: StringName = &"tarek_burn"
## `danger` (#FF1F4B), the lock-on line's colour.
const LINE_COLOR: Color = Color("#FF1F4B")
const LINE_WIDTH_PX: float = 4.0
const RETICLE_RADIUS_PX: float = 56.0

enum Phase { IDLE, LOCK, WARNING, RUNNING, AFTERMATH, CALLOUT, SETTLE, DONE }

## The level's Spawner (the Ram and the held fire).
@export var spawner: Spawner

var warn_after_s: float = 0.0
var impact_s: float = 0.0
var ram_travel_s: float = 0.0
var ram_scale: float = 1.0
var ram_start_y: float = 0.0
var intercept_offset_px: float = 0.0
var aftermath_after_s: float = 0.0
var release_after_s: float = 0.0
var line_pulse_hz: float = 0.0
var burn_volume_db: float = 0.0
var slowmo_lead_s: float = 0.0
var slowmo_scale: float = 1.0
var slowmo_hold_s: float = 0.0
var slowmo_ramp_s: float = 0.0

var _phase: Phase = Phase.IDLE
## Game time since the current phase's clock (re)started: LOCK from the event,
## RUNNING from the warning's end, AFTERMATH from the impact, SETTLE from the
## down beat's end.
var _t: float = 0.0
## Game time the line has pulsed for (drawing only).
var _pulse_t: float = 0.0
var _player: Player = null
var _tarek: AllyShip = null
var _vale_at: Vector2 = Vector2.ZERO
var _point: Vector2 = Vector2.ZERO
var _launched: bool = false
var _slowed: bool = false
var _impacted: bool = false
var _line_visible: bool = false
var _ram: Ram = null


func _ready() -> void:
	warn_after_s = maxf(Config.num("story.tarek_fall.warn_after_s"), 0.0)
	impact_s = maxf(Config.num("story.tarek_fall.impact_s"), 0.0)
	ram_travel_s = clampf(Config.num("story.tarek_fall.ram_travel_s"), 0.0, impact_s)
	ram_scale = maxf(Config.num("story.tarek_fall.ram_scale"), 0.01)
	ram_start_y = Config.num("story.tarek_fall.ram_start_y")
	intercept_offset_px = Config.num("story.tarek_fall.intercept_offset_px")
	aftermath_after_s = maxf(Config.num("story.tarek_fall.aftermath_after_s"), 0.0)
	release_after_s = maxf(Config.num("story.tarek_fall.release_after_s"), 0.0)
	line_pulse_hz = maxf(Config.num("story.tarek_fall.line_pulse_hz"), 0.0)
	burn_volume_db = Config.num("story.tarek_fall.burn_volume_db")
	slowmo_lead_s = maxf(Config.num("story.tarek_fall.slowmo.lead_s"), 0.0)
	slowmo_scale = Config.num("story.tarek_fall.slowmo.scale")
	slowmo_hold_s = maxf(Config.num("story.tarek_fall.slowmo.hold_s"), 0.0)
	slowmo_ramp_s = maxf(Config.num("story.tarek_fall.slowmo.ramp_s"), 0.0)
	Events.story_event_requested.connect(_on_events_story_event_requested)
	Events.comms_sequence_finished.connect(_on_events_comms_sequence_finished)
	Events.level_cleared.connect(_on_events_level_cleared)
	Events.level_failed.connect(_on_events_level_failed)


func _physics_process(delta: float) -> void:
	step(delta)


# --- Read accessors (tests) ------------------------------------------------------

func phase() -> Phase:
	return _phase


## Game time on the current phase's clock (see _t).
func elapsed() -> float:
	return _t


func line_visible() -> bool:
	return _line_visible


## The point Tarek holds between Vale and the Ram.
func intercept_point() -> Vector2:
	return _point


## The live Ram (null before the launch and after the impact).
func ram() -> Ram:
	return _ram if is_instance_valid(_ram) else null


# --- The scene -------------------------------------------------------------------

## Starts the scene: see the timeline above. Ignored unless IDLE.
func start() -> void:
	if _phase != Phase.IDLE or not is_inside_tree():
		return
	_tarek = _find_tarek()
	if _tarek == null:
		Log.info("scene", "Tarek's fall: no patrolling Tarek; scene skipped")
		_phase = Phase.DONE
		return
	_player = get_tree().get_first_node_in_group(Groups.PLAYER) as Player
	_t = 0.0
	if not _has_player():
		Log.info("scene", "Tarek's fall: no Vale; Tarek falls at once")
		_phase = Phase.DONE
		_tarek.take_hit()
		_fall_effects()
		Events.comms_sequence_requested.emit(WARNING_SEQUENCE)
		Events.comms_sequence_requested.emit(DOWN_SEQUENCE)
		return
	_phase = Phase.LOCK
	_vale_at = _player.global_position
	_point = _vale_at + Vector2(0.0, -intercept_offset_px)
	_player.set_scripted_lock(true)
	if spawner != null:
		spawner.hold_enemy_fire = true
	# Tarek stops shooting at the lock-on; his dash comes after the warning.
	_tarek.hold_fire = true
	Audio.play_sfx(ALARM_SFX)
	_line_visible = true
	Log.info("scene", "Tarek's fall: lock-on, warning in %.2f s" % warn_after_s)
	step(0.0)


## One tick of the timeline (game time).
func step(delta: float) -> void:
	if _phase == Phase.IDLE or _phase == Phase.DONE:
		return
	var dt: float = maxf(delta, 0.0)
	_t += dt
	_pulse_t += dt
	match _phase:
		Phase.LOCK:
			if _t >= warn_after_s:
				_phase = Phase.WARNING
				Log.info("scene", "Tarek's fall: the warning beat")
				Events.comms_sequence_requested.emit(WARNING_SEQUENCE)
		Phase.RUNNING:
			if not _launched and _t >= impact_s - ram_travel_s:
				_launch()
			if not _slowed and _t >= impact_s - slowmo_lead_s:
				_slowed = true
				Feedback.slow_motion(slowmo_scale, slowmo_hold_s, slowmo_ramp_s)
			# Without a Ram (no Spawner or no Enemies container) the clock decides.
			if not _impacted and ram() == null and _t >= impact_s:
				_impact()
		Phase.AFTERMATH:
			if _t >= aftermath_after_s:
				_phase = Phase.CALLOUT
				Log.info("scene", "Tarek's fall: the down beat")
				Events.comms_sequence_requested.emit(DOWN_SEQUENCE)
		Phase.SETTLE:
			if _t >= release_after_s:
				_release("released")
	if _line_visible:
		queue_redraw()


## The warning beat ended: Tarek dashes in and the impact clock starts.
func _dash() -> void:
	_phase = Phase.RUNNING
	_t = 0.0
	if is_instance_valid(_tarek):
		_tarek.intercept(_point)
	Log.info("scene", "Tarek's fall: Tarek dashes in, impact in %.2f s" % impact_s)
	step(0.0)


func _launch() -> void:
	_launched = true
	_line_visible = false
	queue_redraw()
	if spawner == null:
		return
	_ram = spawner.spawn_ram({
		"from": Vector2(_vale_at.x, ram_start_y),
		"to": _point,
		"travel_s": ram_travel_s,
		"scale": ram_scale,
	})
	if _ram != null:
		_ram.arrived.connect(_impact)
		Log.info("scene", "Tarek's fall: the Ram dives")


func _impact() -> void:
	if _impacted or _phase != Phase.RUNNING:
		return
	_impacted = true
	_ram = null
	_line_visible = false
	queue_redraw()
	Feedback.impact(ImpactTier.LARGE, _point)
	if is_instance_valid(_tarek):
		_tarek.take_hit()
	_fall_effects()
	_phase = Phase.AFTERMATH
	_t = 0.0
	Log.info("scene", "Tarek's fall: the Ram struck Tarek")


## The music drops out and the burning-fall sound plays (the impact, or the
## no-Vale fall).
func _fall_effects() -> void:
	Audio.stop_music()
	Audio.play_sfx(BURN_SFX, 0.0, burn_volume_db)


## Hands control back: the lock, the held fire and the lock-on line.
func _release(reason: String) -> void:
	if _phase == Phase.IDLE or _phase == Phase.DONE:
		return
	_phase = Phase.DONE
	_line_visible = false
	queue_redraw()
	if _has_player():
		_player.set_scripted_lock(false)
	if spawner != null:
		spawner.hold_enemy_fire = false
	if _tarek != null and is_instance_valid(_tarek):
		_tarek.hold_fire = false
	Log.info("scene", "Tarek's fall: controls %s" % reason)


func _find_tarek() -> AllyShip:
	for node: Node in get_tree().get_nodes_in_group(Groups.ALLIES):
		var ally: AllyShip = node as AllyShip
		if ally != null and ally.ally_id == ALLY_ID and ally.state() == AllyShip.State.PATROL:
			return ally
	return null


func _has_player() -> bool:
	return is_instance_valid(_player) and not _player.is_queued_for_deletion() and not _player.is_dead()


func _on_events_story_event_requested(event_name: StringName) -> void:
	if event_name == EVENT:
		start()


func _on_events_comms_sequence_finished(sequence_id: StringName) -> void:
	if _phase == Phase.WARNING and sequence_id == WARNING_SEQUENCE:
		_dash()
	elif _phase == Phase.CALLOUT and sequence_id == DOWN_SEQUENCE:
		_phase = Phase.SETTLE
		_t = 0.0
		step(0.0)


func _on_events_level_cleared(_level_id: int) -> void:
	_release("released (level cleared)")


func _on_events_level_failed(_reason: StringName) -> void:
	_release("released (level failed)")


# --- Drawing ---------------------------------------------------------------------

## The lock-on line from the top edge to Vale and a reticle on Vale, pulsing.
func _draw() -> void:
	if not _line_visible:
		return
	var color: Color = LINE_COLOR
	if line_pulse_hz > 0.0:
		color.a = lerpf(0.35, 1.0, 0.5 + 0.5 * cos(TAU * line_pulse_hz * _pulse_t))
	var top: Vector2 = Vector2(_vale_at.x, 0.0)
	draw_line(top, _vale_at, color, LINE_WIDTH_PX, true)
	draw_arc(_vale_at, RETICLE_RADIUS_PX, 0.0, TAU, 48, color, LINE_WIDTH_PX, true)
