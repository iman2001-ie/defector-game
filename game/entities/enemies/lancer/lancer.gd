class_name Lancer
extends Enemy
## Lancer: medium ranged enemy (GDD FR20, FR25, NFR6).
##
## Wave Lancers (spawned with a `slot`) fly in from their `entry` side at
## enemies.lancer.strafe_speed_px_s to a slot in the top zone_height_ratio of
## the playfield, then strafe horizontally at that speed between the screen
## edges, never changing y. Every fire_interval_s of strafing the muzzle glows
## for telegraph_s (still strafing), then one enemy_bullet is fired at
## bullet_speed_px_s toward where the player is at that moment (straight down
## with no player), and the cycle restarts.
##
## Bullets are requested through `spawner` (injected by Spawner). Without one
## the Lancer runs its cycle but never fires.
##
## Without a `slot` (the sandbox) the Lancer strafes from its spawn position.

enum State { ENTER, STRAFE, TELEGRAPH }

const ENTRY_TOP: StringName = &"top"
const ENTRY_SIDES: StringName = &"sides"
const PLAYER_GROUP: StringName = &"player"
const BULLET_ID: StringName = &"enemy_bullet"

var _state: State = State.STRAFE
## Seconds spent in the current state (the fire timer while strafing).
var _t: float = 0.0
var _slot: Vector2 = Vector2.ZERO
var _has_slot: bool = false
var _entry: StringName = ENTRY_TOP
var _entry_start: Vector2 = Vector2.ZERO
## +1 or -1: the current horizontal strafe direction.
var _dir: float = 1.0
var _min_x: float = 0.0
var _max_x: float = 0.0
var _warned_no_spawner: bool = false

var _strafe_speed: float = 0.0
var _zone_height_ratio: float = 0.0
var _fire_interval_s: float = 0.0
var _telegraph_s: float = 0.0
var _bullet_speed: float = 0.0
var _glow_energy: float = 1.0
var _bullet_damage: int = 1

var _muzzle: Node2D = null
var _glow: CanvasItem = null


func _init() -> void:
	type_id = &"lancer"


## Stores params; nothing is applied until _ready(). Keys: position (global),
## slot (formation slot, global), entry (&"top" | &"sides").
func setup(params: Dictionary) -> void:
	super(params)
	if params.has("slot"):
		_slot = params["slot"] as Vector2
		_has_slot = true
	if params.has("entry"):
		_entry = StringName(str(params["entry"]))


func _ready() -> void:
	super()
	_strafe_speed = Config.num("enemies.lancer.strafe_speed_px_s")
	_zone_height_ratio = Config.num("enemies.lancer.zone_height_ratio")
	_fire_interval_s = Config.num("enemies.lancer.fire_interval_s")
	_telegraph_s = Config.num("enemies.lancer.telegraph_s")
	_bullet_speed = Config.num("enemies.lancer.bullet_speed_px_s")
	_glow_energy = Config.num("enemies.lancer.muzzle_glow_energy")
	_bullet_damage = Config.int_("damage.bullet_hearts")
	_muzzle = get_node_or_null(^"Muzzle") as Node2D
	_glow = get_node_or_null(^"Muzzle/MuzzleGlow") as CanvasItem
	if _glow != null:
		_glow.self_modulate = Color(_glow_energy, _glow_energy, _glow_energy)
	var half: float = sprite_px / 2.0
	_min_x = half
	_max_x = Playfield.SIZE.x - half
	if not _has_slot:
		_slot = global_position
		_dir = _initial_dir()
		_enter_state(State.STRAFE)
		return
	var zone_y: float = _zone_height_ratio * Playfield.SIZE.y
	if _slot.y > zone_y:
		Log.warn("spawn", "lancer slot y %.0f is below the strafe zone (y <= %.0f); clamped" % [_slot.y, zone_y])
		_slot.y = zone_y
	_dir = _initial_dir()
	if _entry == ENTRY_SIDES:
		var x: float = -half if _slot.x <= Playfield.SIZE.x / 2.0 else Playfield.SIZE.x + half
		_entry_start = Vector2(x, _slot.y)
	else:
		if _entry != ENTRY_TOP:
			Log.warn("spawn", "lancer entry '%s' is unknown; using top" % _entry)
		_entry_start = Vector2(_slot.x, -half)
	_enter_state(State.ENTER)


func _physics_process(delta: float) -> void:
	step(delta)


## Advances the state machine by `delta` seconds.
func step(delta: float) -> void:
	_t += delta
	match _state:
		State.ENTER:
			global_position = global_position.move_toward(_slot, _strafe_speed * delta)
			if global_position == _slot:
				_enter_state(State.STRAFE)
		State.STRAFE:
			_strafe(delta)
			if _t >= _fire_interval_s:
				_enter_state(State.TELEGRAPH)
		State.TELEGRAPH:
			_strafe(delta)
			if _t >= _telegraph_s:
				_fire()
				_enter_state(State.STRAFE)


func state() -> State:
	return _state


func formation_slot() -> Vector2:
	return _slot


## +1 when strafing right, -1 when strafing left.
func strafe_dir() -> float:
	return _dir


## True while the muzzle glow (the shot telegraph) is shown.
func is_glowing() -> bool:
	return _glow != null and _glow.visible


func _enter_state(new_state: State) -> void:
	_state = new_state
	_t = 0.0
	if _glow != null:
		_glow.visible = new_state == State.TELEGRAPH
	match new_state:
		State.ENTER:
			global_position = _entry_start


## First strafe direction: toward the screen centre.
func _initial_dir() -> float:
	return 1.0 if _slot.x <= Playfield.SIZE.x / 2.0 else -1.0


func _strafe(delta: float) -> void:
	var x: float = global_position.x + _dir * _strafe_speed * delta
	if x >= _max_x:
		x = _max_x
		_dir = -1.0
	elif x <= _min_x:
		x = _min_x
		_dir = 1.0
	global_position.x = x


func _fire() -> void:
	if spawner == null or not is_instance_valid(spawner):
		if not _warned_no_spawner:
			_warned_no_spawner = true
			Log.debug("spawn", "lancer has no spawner; shot skipped")
		return
	var origin: Vector2 = _muzzle.global_position if _muzzle != null else global_position
	spawner.spawn_projectile(BULLET_ID, {
		"position": origin,
		"velocity": _aim(origin) * _bullet_speed,
		"damage": _bullet_damage,
	})


## Direction from `origin` toward the player's current position; straight down
## with no player or a zero vector.
func _aim(origin: Vector2) -> Vector2:
	var player: Node2D = get_tree().get_first_node_in_group(PLAYER_GROUP) as Node2D
	if player == null:
		return Vector2.DOWN
	var to_player: Vector2 = player.global_position - origin
	if to_player.is_zero_approx():
		return Vector2.DOWN
	return to_player.normalized()
