class_name TarekFallScene
extends Node2D
## Tarek's fall as a readable scene (Story 6.5, reworked after the Epic 7
## playtest, 2026-10-13). A node of level.tscn; it starts on
## Events.story_event_requested(&"tarek_fall") (Level 2 wave 5) and runs one
## timeline on its own clock in game time, so it slows with Feedback's slow
## motion and freezes under a pause or a hit-stop. Every number comes from
## tuning `story.tarek_fall`.
##
##   0            alarm (maul_alarm); a red lock-on line runs from the top edge
##                to Vale; Vale's controls lock (Player.set_scripted_lock: held
##                in place, invulnerable); enemies hold their fire
##                (Spawner.hold_enemy_fire); Tarek dashes to intercept_offset_px
##                above Vale (AllyShip.intercept) and raises his shield.
##   impact_s - cut-off typing time: Tarek's cut-off line is requested
##                (CUT_OFF_SEQUENCE, "Watch out! Get behind me, ..."), so its
##                cut, the static, the shake and the music stop land on the
##                impact (typing time = the line's cut_off_at /
##                comms.cutoff_chars_per_s).
##   impact_s - ram_travel_s: the lock-on line goes; the Ram dives from above
##                Vale straight at Tarek (Spawner.spawn_ram), too fast to dodge.
##   impact_s - slowmo.lead_s: Feedback.slow_motion(scale, hold_s, ramp_s).
##   impact_s     the Ram strikes: a LARGE impact on Tarek, AllyShip.take_hit
##                (he spins away burning, gravely injured; Ryn's report says he
##                lives).
##   impact + release_after_s: controls and enemy fire come back.
##
## Without Vale the scene skips to the hit at once (Tarek falls where he is and
## the line plays); without a patrolling Tarek it does nothing. A level outcome
## (level_cleared / level_failed) mid-scene releases the lock and the fire at
## once. It runs once per attempt (a retry reloads the scene).

## The story event that starts the scene, and the ally it applies to.
const EVENT: StringName = AllyShip.FALL_EVENT
const ALLY_ID: String = AllyShip.FALL_ALLY_ID
## Tarek's cut-off line (data/dialogue/level_2.json): dialogue wiring, like
## SceneRouter's sequence constants, not tuning.
const CUT_OFF_SEQUENCE: StringName = &"l2_w5_tarek_cutoff"
const ALARM_SFX: StringName = &"maul_alarm"
## `danger` (#FF1F4B), the lock-on line's colour.
const LINE_COLOR: Color = Color("#FF1F4B")
const LINE_WIDTH_PX: float = 4.0
const RETICLE_RADIUS_PX: float = 56.0

enum Phase { IDLE, RUNNING, AFTERMATH, DONE }

## The level's Spawner (the Ram and the held fire).
@export var spawner: Spawner

var impact_s: float = 0.0
var ram_travel_s: float = 0.0
var ram_scale: float = 1.0
var ram_start_y: float = 0.0
var intercept_offset_px: float = 0.0
var release_after_s: float = 0.0
var line_pulse_hz: float = 0.0
var slowmo_lead_s: float = 0.0
var slowmo_scale: float = 1.0
var slowmo_hold_s: float = 0.0
var slowmo_ramp_s: float = 0.0

var _phase: Phase = Phase.IDLE
var _t: float = 0.0
var _player: Player = null
var _tarek: AllyShip = null
var _vale_at: Vector2 = Vector2.ZERO
var _point: Vector2 = Vector2.ZERO
var _line_at: float = 0.0
var _line_requested: bool = false
var _launched: bool = false
var _slowed: bool = false
var _impacted: bool = false
var _release_at: float = 0.0
var _line_visible: bool = false
var _ram: Ram = null


func _ready() -> void:
	impact_s = maxf(Config.num("story.tarek_fall.impact_s"), 0.0)
	ram_travel_s = clampf(Config.num("story.tarek_fall.ram_travel_s"), 0.0, impact_s)
	ram_scale = maxf(Config.num("story.tarek_fall.ram_scale"), 0.01)
	ram_start_y = Config.num("story.tarek_fall.ram_start_y")
	intercept_offset_px = Config.num("story.tarek_fall.intercept_offset_px")
	release_after_s = maxf(Config.num("story.tarek_fall.release_after_s"), 0.0)
	line_pulse_hz = maxf(Config.num("story.tarek_fall.line_pulse_hz"), 0.0)
	slowmo_lead_s = maxf(Config.num("story.tarek_fall.slowmo.lead_s"), 0.0)
	slowmo_scale = Config.num("story.tarek_fall.slowmo.scale")
	slowmo_hold_s = maxf(Config.num("story.tarek_fall.slowmo.hold_s"), 0.0)
	slowmo_ramp_s = maxf(Config.num("story.tarek_fall.slowmo.ramp_s"), 0.0)
	Events.story_event_requested.connect(_on_events_story_event_requested)
	Events.level_cleared.connect(_on_events_level_cleared)
	Events.level_failed.connect(_on_events_level_failed)


func _physics_process(delta: float) -> void:
	step(delta)


# --- Read accessors (tests) ------------------------------------------------------

func phase() -> Phase:
	return _phase


func elapsed() -> float:
	return _t


func line_visible() -> bool:
	return _line_visible


## When the cut-off line is requested (impact_s minus its typing time, never
## before 0).
func line_request_time() -> float:
	return _line_at


## The point Tarek holds between Vale and the Ram.
func intercept_point() -> Vector2:
	return _point


## The live Ram (null before the launch and after the impact).
func ram() -> Ram:
	return _ram if is_instance_valid(_ram) else null


## The cut-off line's typing time: its cut_off_at characters at
## comms.cutoff_chars_per_s (0 when either is missing).
static func cut_off_typing_s(sequence: Dictionary, chars_per_s: float) -> float:
	var lines: Variant = sequence.get("lines")
	if not (lines is Array) or (lines as Array).is_empty() or not ((lines as Array)[0] is Dictionary):
		return 0.0
	var cut: Variant = ((lines as Array)[0] as Dictionary).get("cut_off_at")
	if not (cut is float or cut is int) or chars_per_s <= 0.0:
		return 0.0
	return maxf(float(cut), 0.0) / chars_per_s


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
	_line_at = maxf(impact_s - cut_off_typing_s(Config.sequence(CUT_OFF_SEQUENCE), Config.num("comms.cutoff_chars_per_s")), 0.0)
	_phase = Phase.RUNNING
	if not _has_player():
		Log.info("scene", "Tarek's fall: no Vale; Tarek falls at once")
		_request_line()
		_tarek.take_hit()
		_phase = Phase.DONE
		return
	_vale_at = _player.global_position
	_point = _vale_at + Vector2(0.0, -intercept_offset_px)
	_player.set_scripted_lock(true)
	if spawner != null:
		spawner.hold_enemy_fire = true
	Audio.play_sfx(ALARM_SFX)
	_tarek.intercept(_point)
	_line_visible = true
	Log.info("scene", "Tarek's fall: lock-on, impact in %.2f s" % impact_s)
	step(0.0)


## One tick of the timeline (game time).
func step(delta: float) -> void:
	if _phase == Phase.IDLE or _phase == Phase.DONE:
		return
	_t += maxf(delta, 0.0)
	if _phase == Phase.RUNNING:
		if not _line_requested and _t >= _line_at:
			_request_line()
		if not _launched and _t >= impact_s - ram_travel_s:
			_launch()
		if not _slowed and _t >= impact_s - slowmo_lead_s:
			_slowed = true
			Feedback.slow_motion(slowmo_scale, slowmo_hold_s, slowmo_ramp_s)
		# Without a Ram (no Spawner or no Enemies container) the clock decides.
		if not _impacted and ram() == null and _t >= impact_s:
			_impact()
	elif _phase == Phase.AFTERMATH and _t >= _release_at:
		_release("released")
	if _line_visible:
		queue_redraw()


func _request_line() -> void:
	_line_requested = true
	Events.comms_sequence_requested.emit(CUT_OFF_SEQUENCE)


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
	Feedback.impact(ImpactTier.LARGE, _point)
	if is_instance_valid(_tarek):
		_tarek.take_hit()
	_release_at = _t + release_after_s
	_phase = Phase.AFTERMATH
	Log.info("scene", "Tarek's fall: the Ram struck Tarek")


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
		color.a = lerpf(0.35, 1.0, 0.5 + 0.5 * cos(TAU * line_pulse_hz * _t))
	var top: Vector2 = Vector2(_vale_at.x, 0.0)
	draw_line(top, _vale_at, color, LINE_WIDTH_PX, true)
	draw_arc(_vale_at, RETICLE_RADIUS_PX, 0.0, TAU, 48, color, LINE_WIDTH_PX, true)
