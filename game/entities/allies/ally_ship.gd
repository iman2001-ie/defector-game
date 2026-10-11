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
## Behaviour is enum State + match with _enter_state() (Story 6.5 adds its
## states); movement and firing run in step(delta), called from _physics_process.
## The hull is drawn in code (no image asset until Epic 8): a fighter
## silhouette ship_px tall, nose up, a dim coalition body with a bright outline.

enum State { PATROL }

## `coalition` (#22E6FF): the allies' in-world colour (UX DESIGN).
const OUTLINE_COLOR: Color = Color("#22E6FF")
## The body is the coalition colour, dimmed.
const BODY_COLOR: Color = Color(0.133333, 0.901961, 1.0, 0.3)
const OUTLINE_PX: float = 2.0
## The projectile type id its shots use.
const BOLT_TYPE: StringName = &"ally_bolt"

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

var _state: State = State.PATROL
var _dir: int = 1
var _fire_clock: float = 0.0
## Set by level_cleared or any level_failed: the outcome is decided, no more shots.
var _ended: bool = false
var _warned_no_spawner: bool = false
var _outline: PackedVector2Array = PackedVector2Array()


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
	if fire_interval_s <= 0.0:
		Log.warn("data", "allies.fire_interval_s is %s; the ally never fires" % fire_interval_s)
	add_to_group(Groups.ALLIES)
	Events.level_cleared.connect(_on_events_level_cleared)
	Events.level_failed.connect(_on_events_level_failed)
	global_position = Vector2(ship_px / 2.0, band_y)
	_dir = 1
	_fire_clock = 0.0
	_build_outline()
	_enter_state(State.PATROL)


func _physics_process(delta: float) -> void:
	step(delta)


## One behaviour tick: move along the path, then advance the fire clock.
func step(delta: float) -> void:
	match _state:
		State.PATROL:
			_patrol(delta)
			_tick_fire(delta)


func _enter_state(next: State) -> void:
	_state = next
	match _state:
		State.PATROL:
			queue_redraw()


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
## position is inside Playfield.RECT; dead, queued-for-deletion, off-screen and
## non-Enemy nodes are skipped. Null when none qualifies.
static func nearest_target(from: Vector2, nodes: Array[Node]) -> Enemy:
	var best: Enemy = null
	var best_d: float = INF
	for node: Node in nodes:
		if not is_instance_valid(node):
			continue
		var enemy: Enemy = node as Enemy
		if enemy == null or enemy.is_dead() or enemy.is_queued_for_deletion():
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
	if _outline.size() < 3:
		return
	draw_colored_polygon(_outline, BODY_COLOR)
	var closed: PackedVector2Array = _outline.duplicate()
	closed.append(_outline[0])
	draw_polyline(closed, OUTLINE_COLOR, OUTLINE_PX, true)


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
