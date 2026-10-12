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

var turn_rate_deg_s: float = 0.0
var lifetime_s: float = 0.0

var _age: float = 0.0
## Untyped on purpose: a typed Node2D variable rejects a freed instance.
var _target: Variant = null
var _had_target: bool = false
var _gave_up: bool = false


func _ready() -> void:
	turn_rate_deg_s = Config.num("abilities.barrage.turn_rate_deg_s")
	lifetime_s = Config.num("abilities.barrage.lifetime_s")
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
	velocity = MicroMissile.steer(velocity, desired, deg_to_rad(turn_rate_deg_s) * delta)
	_orient()
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
		rotation = velocity.angle() + PI / 2.0


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
