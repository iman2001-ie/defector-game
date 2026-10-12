class_name AllyShip
extends Area2D
## An invincible wingman (Story 6.4, FR34): Tarek or Ryn. Spawned only by
## Spawner.spawn_ally into World/Allies when the level JSON has
## "ally": "tarek"|"ryn"; setup({"ally": id}) sets ally_id and the Spawner sets
## `spawner` before add_child.
##
## Layer `allies`, mask 0, monitoring and monitorable off, no collision shape and
## no apply_damage: nothing detects it, so it takes no damage and blocks nothing.
##
## Path (the "scripted horizontal path" reading, like the convoy's GDD #45): it
## starts at x ship_px / 2 at the centre of allies.patrol_band_y, heading right,
## and ping-pongs across the playfield at allies.speed_px_s; patrol_step clamps x
## to [ship_px / 2, width - ship_px / 2] and flips the direction at each edge.
## y never changes.
##
## Fire: a clock advances every step; each time it reaches allies.fire_interval_s
## it keeps the remainder and the ship fires once: one Groups.ENEMIES scan picks
## the nearest live enemy inside Playfield.RECT (nearest_target), and the
## Spawner creates an &"ally_bolt" toward it (allies.shot_speed_px_s,
## allies.damage, from_ally true; straight up on a zero aim vector). No target,
## no shot: the clock keeps running. Once the level outcome is decided
## (Events.level_cleared / level_failed) it never fires again but keeps patrolling.
##
## Tarek's fall (Story 6.5, FR35): on Events.story_event_requested(&"tarek_fall")
## a Tarek ally in PATROL stops firing and runs APPROACH (allies.fall.approach_s:
## a smoothstep glide from where it is to Vale + (0, -shield_offset_px), re-read
## every step) -> SHIELD (shield_s: holds that point, tracking Vale, while a
## coalition ring of shield_radius_px flashes around Vale at shield_flash_hz)
## -> FALLING (damaged hull, FireTrail on, exit_speed_px_s toward the nearer side
## edge with an exit_drop downward drift) -> GONE (the first step outside
## Playfield.RECT grown by ship_px: trail off, queue_free; it never returns this
## attempt). Vale is looked up once (Groups.PLAYER) on the event; without one,
## or once it is freed, the ship skips straight to FALLING from where it is.
## Ryn, other events and a repeat event are ignored. The shield is visual only.
##
## Behaviour is enum State + match with _enter_state(); movement and firing run
## in step(delta), called from _physics_process. Firing runs only in PATROL.
## The hull is drawn in code (no image asset until Epic 8): a fighter
## silhouette ship_px tall, nose up, a dim coalition body with a bright outline;
## the damaged variant has the right wing tip broken off, a dark body and a
## danger outline.

enum State { PATROL, APPROACH, SHIELD, FALLING, GONE }

## `coalition` (#22E6FF): the allies' in-world colour (UX DESIGN).
const OUTLINE_COLOR: Color = Color("#22E6FF")
## The body is the coalition colour, dimmed.
const BODY_COLOR: Color = Color(0.133333, 0.901961, 1.0, 0.3)
const OUTLINE_PX: float = 2.0
## The projectile type id its shots use.
const BOLT_TYPE: StringName = &"ally_bolt"
## The story event that starts Tarek's fall, and the only ally it applies to.
const FALL_EVENT: StringName = &"tarek_fall"
const FALL_ALLY_ID: String = "tarek"
## The damaged hull: `surfaceSolid` (#0A1222) at alpha 0.8 with a `danger` outline.
const DAMAGED_BODY_COLOR: Color = Color(0.039216, 0.070588, 0.133333, 0.8)
const DAMAGED_OUTLINE_COLOR: Color = Color("#FF1F4B")
## The shield ring's stroke (a coalition ring, 3 px).
const SHIELD_STROKE_PX: float = 3.0
const SHIELD_SEGMENTS: int = 48
## The ring's dimmest alpha in its flash.
const SHIELD_MIN_ALPHA: float = 0.2
## The FireTrail sits at the tail: y = ship_px * this (24 px at ship_px 64).
const TRAIL_Y_RATIO: float = 0.375

## "tarek" or "ryn" (from setup's `ally` key).
var ally_id: String = ""
## Set by Spawner.spawn_ally before add_child; shots are requested through it.
var spawner: Spawner = null

var ship_px: float = 0.0
var speed_px_s: float = 0.0
var damage: int = 0
var fire_interval_s: float = 0.0
var shot_speed_px_s: float = 0.0
var band_y: float = 0.0
## allies.fall (Story 6.5).
var approach_s: float = 0.0
var shield_s: float = 0.0
var shield_offset_px: float = 0.0
var shield_radius_px: float = 0.0
var shield_flash_hz: float = 0.0
var exit_speed_px_s: float = 0.0
var exit_drop: float = 0.0

var _state: State = State.PATROL
var _dir: int = 1
var _fire_clock: float = 0.0
## Set by level_cleared or any level_failed: the outcome is decided, no more shots.
var _ended: bool = false
var _warned_no_spawner: bool = false
var _outline: PackedVector2Array = PackedVector2Array()
var _damaged_outline: PackedVector2Array = PackedVector2Array()
## Vale, looked up once on the fall event.
var _player: Node2D = null
## Seconds in the current fall phase (APPROACH / SHIELD).
var _phase_t: float = 0.0
var _approach_from: Vector2 = Vector2.ZERO
var _fall_velocity: Vector2 = Vector2.ZERO
var _trail: GPUParticles2D = null


## Stores params before add_child. Keys: ally ("tarek" | "ryn").
func setup(params: Dictionary) -> void:
	if params.has("ally"):
		ally_id = str(params["ally"])


func _ready() -> void:
	collision_layer = CollisionLayers.ALLIES
	collision_mask = 0
	monitoring = false
	monitorable = false
	ship_px = maxf(Config.num("allies.ship_px"), 0.0)
	speed_px_s = maxf(Config.num("allies.speed_px_s"), 0.0)
	damage = maxi(Config.int_("allies.damage"), 0)
	fire_interval_s = Config.num("allies.fire_interval_s")
	shot_speed_px_s = maxf(Config.num("allies.shot_speed_px_s"), 0.0)
	band_y = (Config.num("allies.patrol_band_y.min") + Config.num("allies.patrol_band_y.max")) / 2.0
	approach_s = maxf(Config.num("allies.fall.approach_s"), 0.0)
	shield_s = maxf(Config.num("allies.fall.shield_s"), 0.0)
	shield_offset_px = Config.num("allies.fall.shield_offset_px")
	shield_radius_px = maxf(Config.num("allies.fall.shield_radius_px"), 0.0)
	shield_flash_hz = maxf(Config.num("allies.fall.shield_flash_hz"), 0.0)
	exit_speed_px_s = maxf(Config.num("allies.fall.exit_speed_px_s"), 0.0)
	exit_drop = Config.num("allies.fall.exit_drop")
	_trail = get_node_or_null("FireTrail") as GPUParticles2D
	if _trail != null:
		_trail.emitting = false
		_trail.position = Vector2(0.0, ship_px * TRAIL_Y_RATIO)
	if fire_interval_s <= 0.0:
		Log.warn("data", "allies.fire_interval_s is %s; the ally never fires" % fire_interval_s)
	add_to_group(Groups.ALLIES)
	Events.level_cleared.connect(_on_events_level_cleared)
	Events.level_failed.connect(_on_events_level_failed)
	Events.story_event_requested.connect(_on_events_story_event_requested)
	global_position = Vector2(ship_px / 2.0, band_y)
	_dir = 1
	_fire_clock = 0.0
	_build_outline()
	_build_damaged_outline()
	_enter_state(State.PATROL)


func _physics_process(delta: float) -> void:
	step(delta)


## One behaviour tick: in PATROL move along the path, then advance the fire
## clock; in the fall states run that phase (no firing).
func step(delta: float) -> void:
	match _state:
		State.PATROL:
			_patrol(delta)
			_tick_fire(delta)
		State.APPROACH:
			_approach(delta)
		State.SHIELD:
			_shield(delta)
		State.FALLING:
			_fall(delta)
		State.GONE:
			pass


func _enter_state(next: State) -> void:
	_state = next
	_phase_t = 0.0
	match _state:
		State.PATROL:
			queue_redraw()
		State.APPROACH:
			_approach_from = global_position
		State.SHIELD:
			queue_redraw()
		State.FALLING:
			var side: float = -1.0 if global_position.x < Playfield.SIZE.x / 2.0 else 1.0
			_fall_velocity = Vector2(side, exit_drop).normalized() * exit_speed_px_s
			if _trail != null:
				_trail.emitting = true
			Log.info("scene", "Tarek's fall: damaged, leaving the fight")
			queue_redraw()
		State.GONE:
			if _trail != null:
				_trail.emitting = false
			Log.info("scene", "Tarek's fall: Tarek has left the level")
			queue_free()


# --- Read accessors ---------------------------------------------------------------

func state() -> State:
	return _state


## +1 heading right, -1 heading left.
func direction() -> int:
	return _dir


## Seconds accumulated toward the next shot.
func fire_clock() -> float:
	return _fire_clock


## True once the level outcome is decided (the ally has stopped firing).
func has_ended() -> bool:
	return _ended


## The drawn hull outline (local points, nose up).
func outline() -> PackedVector2Array:
	return _outline


## The damaged hull outline (right wing tip broken off), drawn from FALLING on.
func damaged_outline() -> PackedVector2Array:
	return _damaged_outline


## True while the shield ring around Vale shows (SHIELD).
func shield_visible() -> bool:
	return _state == State.SHIELD


## True from FALLING on (the damaged hull and the fire trail).
func is_damaged() -> bool:
	return _state == State.FALLING or _state == State.GONE


## The FireTrail particles (null if the scene lacks them).
func fire_trail() -> GPUParticles2D:
	return _trail


# --- Tarek's fall -----------------------------------------------------------------

## Starts the fall for a patrolling Tarek; anything else is ignored. Vale is
## looked up here once and cached.
func _on_events_story_event_requested(event_name: StringName) -> void:
	if event_name != FALL_EVENT or ally_id != FALL_ALLY_ID or _state != State.PATROL:
		return
	if not is_inside_tree():
		return
	_player = get_tree().get_first_node_in_group(Groups.PLAYER) as Node2D
	Log.info("scene", "Tarek's fall: shielding Vale")
	if _has_player():
		_enter_state(State.APPROACH)
	else:
		_enter_state(State.FALLING)


func _has_player() -> bool:
	return is_instance_valid(_player) and not _player.is_queued_for_deletion()


## The point the ship shields Vale from: Vale + (0, -shield_offset_px).
func _shield_point() -> Vector2:
	return _player.global_position + Vector2(0.0, -shield_offset_px)


func _approach(delta: float) -> void:
	if not _has_player():
		_enter_state(State.FALLING)
		return
	_phase_t += maxf(delta, 0.0)
	var target: Vector2 = _shield_point()
	if approach_s <= 0.0 or _phase_t >= approach_s:
		global_position = target
		_enter_state(State.SHIELD)
		return
	global_position = _approach_from.lerp(target, smoothstep(0.0, 1.0, _phase_t / approach_s))


func _shield(delta: float) -> void:
	if not _has_player():
		_enter_state(State.FALLING)
		return
	global_position = _shield_point()
	_phase_t += maxf(delta, 0.0)
	if _phase_t >= shield_s:
		_enter_state(State.FALLING)
		return
	queue_redraw()


func _fall(delta: float) -> void:
	global_position += _fall_velocity * maxf(delta, 0.0)
	if not Playfield.RECT.grow(ship_px).has_point(global_position):
		_enter_state(State.GONE)


## The shield ring's alpha `t` seconds into SHIELD: a cosine flash at `hz`
## between 1 and SHIELD_MIN_ALPHA, starting bright (steady 1 when hz <= 0).
static func shield_alpha(t: float, hz: float) -> float:
	if hz <= 0.0:
		return 1.0
	var k: float = 0.5 + 0.5 * cos(TAU * hz * t)
	return lerpf(SHIELD_MIN_ALPHA, 1.0, k)


# --- Patrol -----------------------------------------------------------------------

func _patrol(delta: float) -> void:
	var half: float = ship_px / 2.0
	var next: Vector2 = patrol_step(global_position.x, _dir, speed_px_s * delta, half, Playfield.SIZE.x - half)
	global_position = Vector2(next.x, band_y)
	_dir = int(next.y)


## Advances `x` by `distance` in `dir` and clamps it to [lo, hi]; reaching an
## edge while moving into it flips the direction (ping-pong).
## Returns Vector2(new x, new dir).
static func patrol_step(x: float, dir: int, distance: float, lo: float, hi: float) -> Vector2:
	var top: float = maxf(hi, lo)
	var d: int = -1 if dir < 0 else 1
	var next: float = x + float(d) * maxf(distance, 0.0)
	if d > 0 and next >= top:
		return Vector2(top, -1.0)
	if d < 0 and next <= lo:
		return Vector2(lo, 1.0)
	return Vector2(clampf(next, lo, top), float(d))


# --- Fire -------------------------------------------------------------------------

## Advances the fire clock; when it reaches fire_interval_s it keeps the
## remainder and fires once (at most one shot per step).
func _tick_fire(delta: float) -> void:
	if _ended or fire_interval_s <= 0.0:
		return
	_fire_clock += maxf(delta, 0.0)
	if _fire_clock < fire_interval_s:
		return
	_fire_clock = fmod(_fire_clock - fire_interval_s, fire_interval_s)
	_fire()


## One shot at the nearest live on-screen enemy (none: no shot). Returns the
## spawned bolt, or null.
func _fire() -> Projectile:
	var target: Enemy = nearest_target(global_position, get_tree().get_nodes_in_group(Groups.ENEMIES))
	if target == null:
		return null
	if spawner == null or not is_instance_valid(spawner):
		if not _warned_no_spawner:
			_warned_no_spawner = true
			Log.debug("spawn", "ally '%s' has no spawner; shot skipped" % ally_id)
		return null
	var dir: Vector2 = aim(global_position, target.global_position)
	return spawner.spawn_projectile(BOLT_TYPE, {
		"position": global_position,
		"velocity": dir * shot_speed_px_s,
		"damage": damage,
		"from_ally": true,
	})


## Unit direction from `from` to `to`; straight up on a zero vector.
static func aim(from: Vector2, to: Vector2) -> Vector2:
	var v: Vector2 = to - from
	if v.length_squared() <= 0.0:
		return Vector2.UP
	return v.normalized()


## The live Enemy in `nodes` nearest `from` (distance_squared_to) whose
## position is inside Playfield.RECT; dead, queued-for-deletion, off-screen,
## non-targetable (the Flagship hull, an invulnerable core; Story 7.3) and
## non-Enemy nodes are skipped. Null when none qualifies.
static func nearest_target(from: Vector2, nodes: Array[Node]) -> Enemy:
	var best: Enemy = null
	var best_d: float = INF
	for node: Node in nodes:
		if not is_instance_valid(node):
			continue
		var enemy: Enemy = node as Enemy
		if enemy == null or enemy.is_dead() or enemy.is_queued_for_deletion() or not enemy.is_targetable():
			continue
		if not Playfield.RECT.has_point(enemy.global_position):
			continue
		var d: float = from.distance_squared_to(enemy.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best


func _on_events_level_cleared(_level_id: int) -> void:
	_ended = true


func _on_events_level_failed(_reason: StringName) -> void:
	_ended = true


# --- Drawing ----------------------------------------------------------------------

func _draw() -> void:
	if is_damaged():
		_draw_hull(_damaged_outline, DAMAGED_BODY_COLOR, DAMAGED_OUTLINE_COLOR)
	else:
		_draw_hull(_outline, BODY_COLOR, OUTLINE_COLOR)
	if _state == State.SHIELD and shield_radius_px > 0.0:
		var ring: Color = OUTLINE_COLOR
		ring.a = shield_alpha(_phase_t, shield_flash_hz)
		draw_arc(Vector2(0.0, shield_offset_px), shield_radius_px, 0.0, TAU, SHIELD_SEGMENTS, ring, SHIELD_STROKE_PX, true)


## A filled hull with a closed outline (no per-draw array allocation).
func _draw_hull(points: PackedVector2Array, body: Color, edge: Color) -> void:
	if points.size() < 3:
		return
	draw_colored_polygon(points, body)
	draw_polyline(points, edge, OUTLINE_PX, true)
	draw_line(points[points.size() - 1], points[0], edge, OUTLINE_PX, true)


## A small fighter, ship_px tall and wide, nose up: a pointed nose, swept wings
## and a notched tail.
func _build_outline() -> void:
	var h: float = ship_px / 2.0
	if h <= 0.0:
		_outline = PackedVector2Array()
		return
	_outline = PackedVector2Array([
		Vector2(0.0, -h),
		Vector2(h * 0.2, -h * 0.3),
		Vector2(h, h * 0.45),
		Vector2(h * 0.95, h * 0.7),
		Vector2(h * 0.3, h * 0.5),
		Vector2(h * 0.35, h),
		Vector2(0.0, h * 0.75),
		Vector2(-h * 0.35, h),
		Vector2(-h * 0.3, h * 0.5),
		Vector2(-h * 0.95, h * 0.7),
		Vector2(-h, h * 0.45),
		Vector2(-h * 0.2, -h * 0.3),
	])


## The fighter of _build_outline with the right wing tip broken off: the wing
## ends in a jagged break at about 0.6 of the half-width.
func _build_damaged_outline() -> void:
	var h: float = ship_px / 2.0
	if h <= 0.0:
		_damaged_outline = PackedVector2Array()
		return
	_damaged_outline = PackedVector2Array([
		Vector2(0.0, -h),
		Vector2(h * 0.2, -h * 0.3),
		Vector2(h * 0.6, h * 0.075),
		Vector2(h * 0.68, h * 0.25),
		Vector2(h * 0.56, h * 0.36),
		Vector2(h * 0.64, h * 0.5),
		Vector2(h * 0.6, h * 0.59),
		Vector2(h * 0.3, h * 0.5),
		Vector2(h * 0.35, h),
		Vector2(0.0, h * 0.75),
		Vector2(-h * 0.35, h),
		Vector2(-h * 0.3, h * 0.5),
		Vector2(-h * 0.95, h * 0.7),
		Vector2(-h, h * 0.45),
		Vector2(-h * 0.2, -h * 0.3),
	])
