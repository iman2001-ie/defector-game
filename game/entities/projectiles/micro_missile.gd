class_name MicroMissile
extends Projectile
## Barrage micro-missile (Story 3.5): homes on the nearest enemy, picked once at
## launch. The target is re-picked only when it is freed or queued for deletion;
## if that finds nothing the missile flies on without scanning again. With no
## target it steers toward Vector2.UP. It turns at most abilities.barrage
## .turn_rate_deg_s, keeps its speed and frees itself (no impact) after
## lifetime_s. Hits use the Projectile base: the first enemy or asteroid area
## overlapped takes `damage`, so asteroids block it; a convoy ship blocks it with
## no damage and the SMALL blocked-shot effect (Story 6.1, GDD #46).
##
## Playtest pt7-h (smoother flight): the allowed turn rate eases in after
## launch, from abilities.barrage.turn_ease_start x turn_rate_deg_s up to the
## full rate over turn_ease_s (turn_factor), so the path bends smoothly out of
## the launch instead of snapping. The nose follows the heading through an
## exponential lerp_angle at rotation_smoothing per second (it is aimed exactly
## only at launch). The `Exhaust` child (GPUParticles2D, world coordinates)
## streams a short gold-to-red flame fading into grey smoke behind it.

var turn_rate_deg_s: float = 0.0
var lifetime_s: float = 0.0
var turn_ease_s: float = 0.0
var turn_ease_start: float = 1.0
var rotation_smoothing: float = 0.0

var _age: float = 0.0
## Untyped on purpose: a typed Node2D variable rejects a freed instance.
var _target: Variant = null
var _had_target: bool = false
var _gave_up: bool = false


func _ready() -> void:
	turn_rate_deg_s = Config.num("abilities.barrage.turn_rate_deg_s")
	lifetime_s = Config.num("abilities.barrage.lifetime_s")
	turn_ease_s = Config.num("abilities.barrage.turn_ease_s")
	turn_ease_start = clampf(Config.num("abilities.barrage.turn_ease_start"), 0.0, 1.0)
	rotation_smoothing = maxf(Config.num("abilities.barrage.rotation_smoothing"), 0.0)
	super._ready()
	_pick_target()
	_orient()


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime_s:
		queue_free()
		return
	if _had_target and not _gave_up and not _target_alive():
		_pick_target()
		if _target == null:
			_gave_up = true
	var desired: Vector2 = Vector2.UP
	var node: Node2D = target()
	if node != null:
		var to_target: Vector2 = node.global_position - global_position
		if to_target != Vector2.ZERO:
			desired = to_target
	var factor: float = MicroMissile.turn_factor(_age, turn_ease_s, turn_ease_start)
	velocity = MicroMissile.steer(velocity, desired, deg_to_rad(turn_rate_deg_s) * factor * delta)
	_follow_heading(delta)
	super._physics_process(delta)


## The current target, or null when there is none or it is no longer valid.
func target() -> Node2D:
	if not _target_alive():
		return null
	return _target as Node2D


func _target_alive() -> bool:
	return _target != null and is_instance_valid(_target) and not (_target as Node).is_queued_for_deletion()


func _pick_target() -> void:
	_target = MicroMissile.nearest_enemy(global_position, get_tree().get_nodes_in_group(Groups.ENEMIES))
	if _target != null:
		_had_target = true


func _orient() -> void:
	if velocity != Vector2.ZERO:
		# Local -Y (the capsule axis and the nose) points along travel.
		rotation = heading_rotation(velocity)


## Turns the nose toward the heading by the exponential smoothing step for
## `delta` (at once when rotation_smoothing is 0).
func _follow_heading(delta: float) -> void:
	if velocity == Vector2.ZERO:
		return
	if rotation_smoothing <= 0.0:
		_orient()
		return
	rotation = lerp_angle(rotation, heading_rotation(velocity), 1.0 - exp(-rotation_smoothing * maxf(delta, 0.0)))


## The node rotation that points local -Y (the nose) along `v`.
static func heading_rotation(v: Vector2) -> float:
	return v.angle() + PI / 2.0


## The share of turn_rate_deg_s allowed `age` seconds after launch: `start`
## at launch, rising linearly to 1.0 at `ease_s` (1.0 at once for ease_s <= 0).
static func turn_factor(age: float, ease_s: float, start: float) -> float:
	if ease_s <= 0.0:
		return 1.0
	return lerpf(clampf(start, 0.0, 1.0), 1.0, clampf(age / ease_s, 0.0, 1.0))


## The Node2D in `nodes` nearest to `from`, skipping non-Node2D nodes, nodes
## queued for deletion, dead Enemies and Enemies that are not targetable (the
## Flagship hull, an invulnerable core; Story 7.3). Null when none is left; the
## first wins a tie.
static func nearest_enemy(from: Vector2, nodes: Array[Node]) -> Node2D:
	var best: Node2D = null
	var best_d2: float = INF
	for node: Node in nodes:
		var body: Node2D = node as Node2D
		if body == null or body.is_queued_for_deletion():
			continue
		var enemy: Enemy = body as Enemy
		if enemy != null and (enemy.is_dead() or not enemy.is_targetable()):
			continue
		var d2: float = from.distance_squared_to(body.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = body
	return best


## `v` rotated toward `desired` by at most `max_turn_rad`, keeping its length.
static func steer(v: Vector2, desired: Vector2, max_turn_rad: float) -> Vector2:
	if v == Vector2.ZERO or desired == Vector2.ZERO:
		return v
	var diff: float = v.angle_to(desired)
	var turn: float = clampf(diff, -absf(max_turn_rad), absf(max_turn_rad))
	return v.rotated(turn)
