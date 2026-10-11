class_name Maul
extends Enemy
## Maul: medium suicide diver (Story 6.2, FR23, GDD Allies and escort). It
## ignores the player and rushes the cargo.
##
## It spawns just off-screen on its `entry` side (Enemy._entry_start_for at its
## slot; without a slot at its spawn position), plays the `maul_alarm` ping and
## shows its red engine `Trail`, then flies in one straight line at
## enemies.maul.dive_speed_px_s toward the centre of the ConvoyShip nearest it
## at spawn. The heading is locked at spawn and never changes (no steering, no
## lead), so the player can't pull it off course. The convoy is looked up once,
## in _ready (Groups.CONVOY).
##
## Exits (each emits `resolved` exactly once):
## - touching a ConvoyShip: apply_damage(damage.convoy_maul) on it, then the
##   no-kill exit with the tier's impact feedback (no enemy_killed, no loot);
## - a miss: once it has been inside the playfield (Playfield.RECT grown by
##   sprite_px / 2) and is fully outside it again: the no-kill exit, silently;
## - no live convoy at spawn (none, or Convoy.is_lost()): the no-kill exit on
##   its first step (never in _ready, so the WaveDirector's `resolved`
##   connection made after spawn_enemy returns is live), without flying;
## - shot down or body-blocked by the player: Enemy._die() (a kill, drops.maul).
##
## Layer `enemies`, mask `convoy` (the only enemy that masks it), monitoring on.

enum State { DIVE, DONE }

var _state: State = State.DIVE
## Unit vector the Maul flies along, fixed at spawn.
var _heading: Vector2 = Vector2.DOWN
var _dive_speed: float = 0.0
var _convoy_damage: int = 0
## The ConvoyShip aimed at (null: no live convoy at spawn).
var _target: ConvoyShip = null
var _has_target: bool = false
## Set once the Maul has been inside the miss bounds.
var _entered: bool = false
## Playfield.RECT grown by sprite_px / 2; leaving it after entering is a miss.
var _bounds: Rect2 = Rect2()

@onready var _trail: CanvasItem = get_node_or_null(^"Trail") as CanvasItem


func _init() -> void:
	type_id = &"maul"


## Setup params are Enemy's (position, slot, entry); the slot only picks the
## off-screen start.
func _ready() -> void:
	super()
	collision_mask = CollisionLayers.CONVOY
	monitoring = true
	area_entered.connect(_on_area_entered)
	_dive_speed = Config.num(_tuning_key("dive_speed_px_s"))
	_convoy_damage = Config.int_("damage.convoy_maul")
	_bounds = Playfield.RECT.grow(sprite_px / 2.0)
	if _has_slot:
		global_position = _entry_start_for(_slot)
	Audio.play_sfx(&"maul_alarm")
	_aim_at_convoy()
	rotation = _heading.angle() - PI / 2.0
	_enter_state(State.DIVE)


func _physics_process(delta: float) -> void:
	step(delta)


## One dive tick: without a target the no-kill exit; otherwise move along the
## fixed heading and resolve as a miss once it left the playfield after entering.
func step(delta: float) -> void:
	if _dead:
		return
	match _state:
		State.DIVE:
			if not _has_target:
				_finish(false)
				return
			global_position += _heading * _dive_speed * delta
			var inside: bool = is_inside(global_position, _bounds)
			if inside:
				_entered = true
			elif _entered:
				_finish(false)
		State.DONE:
			pass


## The unit direction the Maul flies along (fixed at spawn).
func heading() -> Vector2:
	return _heading


## The ConvoyShip aimed at spawn, or null when there was no live convoy.
func target_ship() -> ConvoyShip:
	return _target if is_instance_valid(_target) else null


func state() -> State:
	return _state


## True when `p` is strictly inside `bounds` (a point on the edge is outside, so
## a Maul starting on the grown playfield's edge has not entered yet).
static func is_inside(p: Vector2, bounds: Rect2) -> bool:
	return p.x > bounds.position.x and p.x < bounds.end.x and p.y > bounds.position.y and p.y < bounds.end.y


func _enter_state(s: State) -> void:
	_state = s
	if _trail != null:
		_trail.visible = s == State.DIVE


## One group look-up at spawn: aim at the centre of the nearest ship of a live
## convoy. No convoy (or a lost one) leaves no target, logged once at DEBUG.
func _aim_at_convoy() -> void:
	var convoy: Convoy = get_tree().get_first_node_in_group(Groups.CONVOY) as Convoy
	if convoy == null or convoy.is_lost():
		Log.debug("combat", "%s: no live convoy at spawn; resolves without a kill" % type_id)
		return
	var best_d: float = INF
	for ship: ConvoyShip in convoy.ships():
		if not is_instance_valid(ship):
			continue
		var d: float = global_position.distance_squared_to(ship.global_position)
		if d < best_d:
			best_d = d
			_target = ship
	if _target == null:
		Log.debug("combat", "%s: no live convoy at spawn; resolves without a kill" % type_id)
		return
	_has_target = true
	var to_target: Vector2 = _target.global_position - global_position
	if not to_target.is_zero_approx():
		_heading = to_target.normalized()


## A ConvoyShip touched: the convoy takes damage.convoy_maul and the Maul
## self-destructs without a kill. Anything else, or a second overlap, is ignored.
func _on_area_entered(area: Area2D) -> void:
	if _dead:
		return
	var ship: ConvoyShip = area as ConvoyShip
	if ship == null:
		return
	ship.apply_damage(_convoy_damage, self)
	_finish(true)


func _finish(play_feedback: bool) -> void:
	_enter_state(State.DONE)
	_resolve_without_kill(play_feedback)
