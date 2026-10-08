class_name HunterWasp
extends Enemy
## Hunter Wasp: small chaser (GDD FR24, COULD; gated by flags.hunter_wasp in
## the WaveDirector).
##
## Flies at a constant enemies.hunter_wasp.chase_speed_px_s and turns its
## heading toward the player by at most turn_rate_deg_s per second, so it
## overshoots and loops back. Contact only: no shots, no telegraph, and it is
## not a Wasp (the WaspDiveClock never picks it). It never holds a formation
## slot and never wraps: a wave Hunter starts just off-screen on its `entry`
## side and chases from there. Without a player it steers toward the playfield
## centre. Without a `slot` (sandbox, tests) it starts at its spawn position.

const ENTRY_TOP: StringName = &"top"
const ENTRY_SIDES: StringName = &"sides"
const PLAYER_GROUP: StringName = &"player"
## Seconds between player look-ups while no valid player is cached.
const PLAYER_RELOOKUP_S: float = 0.5

var _slot: Vector2 = Vector2.ZERO
var _has_slot: bool = false
var _entry: StringName = ENTRY_TOP
## Unit vector the hull flies along.
var _heading: Vector2 = Vector2.DOWN
var _chase_speed: float = 0.0
## Radians per second.
var _turn_rate: float = 0.0
var _player: Node2D = null
## Seconds until the next player look-up while none is cached (0 while one is,
## so a vanished player is looked up again on the next step).
var _relookup_t: float = 0.0


func _init() -> void:
	type_id = &"hunter_wasp"


## Stores params; nothing is applied until _ready(). Keys: position (global),
## slot (global; picks the off-screen start), entry (&"top" | &"sides").
func setup(params: Dictionary) -> void:
	super(params)
	if params.has("slot"):
		_slot = params["slot"] as Vector2
		_has_slot = true
	if params.has("entry"):
		_entry = StringName(str(params["entry"]))


func _ready() -> void:
	super()
	_chase_speed = Config.num("enemies.hunter_wasp.chase_speed_px_s")
	_turn_rate = deg_to_rad(Config.num("enemies.hunter_wasp.turn_rate_deg_s"))
	_heading = Vector2.DOWN
	if _has_slot:
		var half: float = sprite_px / 2.0
		if _entry == ENTRY_SIDES:
			if _slot.x <= Playfield.SIZE.x / 2.0:
				global_position = Vector2(-half, _slot.y)
				_heading = Vector2.RIGHT
			else:
				global_position = Vector2(Playfield.SIZE.x + half, _slot.y)
				_heading = Vector2.LEFT
		else:
			if _entry != ENTRY_TOP:
				Log.warn("spawn", "hunter_wasp entry '%s' is unknown; using top" % _entry)
			global_position = Vector2(_slot.x, -half)
	rotation = _heading.angle() - PI / 2.0
	_find_player()


func _physics_process(delta: float) -> void:
	step(delta)


## Turns toward the chase target (capped) and moves `delta` seconds.
func step(delta: float) -> void:
	if not is_instance_valid(_player):
		_relookup_t -= delta
		if _relookup_t <= 0.0:
			_find_player()
	var to_target: Vector2 = chase_target() - global_position
	if not to_target.is_zero_approx():
		var max_turn: float = _turn_rate * delta
		var turn: float = clampf(_heading.angle_to(to_target), -max_turn, max_turn)
		_heading = _heading.rotated(turn).normalized()
	global_position += _heading * _chase_speed * delta
	rotation = _heading.angle() - PI / 2.0


## The unit direction the Hunter flies along.
func heading() -> Vector2:
	return _heading


## The cached player's position, or the playfield centre without one.
func chase_target() -> Vector2:
	if is_instance_valid(_player):
		return _player.global_position
	return Playfield.SIZE / 2.0


## One group look-up; a miss waits PLAYER_RELOOKUP_S before the next one.
func _find_player() -> void:
	_player = get_tree().get_first_node_in_group(PLAYER_GROUP) as Node2D
	_relookup_t = 0.0 if _player != null else PLAYER_RELOOKUP_S
