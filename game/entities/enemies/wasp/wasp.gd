class_name Wasp
extends Enemy
## Wasp: small fodder enemy (GDD FR19, FR25, NFR6).
##
## Wave Wasps (spawned with a `slot`) fly in from their `entry` side at
## enemies.wasp.entry_speed_px_s to a slot in the top zone_height_ratio of the
## playfield, then hold it. The formation-wide WaspDiveClock calls start_dive()
## on one holding Wasp: it flashes its wings for telegraph_s without moving,
## then dives at dive_speed_px_s toward where the player was when the dive
## started. A diving Wasp that leaves the screen re-enters from the top, flies
## back to its slot and never resolves for leaving.
##
## Without a `slot` (the sandbox) the Wasp holds its spawn position forever.

enum State { ENTER, HOLD, TELEGRAPH, DIVE }

const ENTRY_TOP: StringName = &"top"
const ENTRY_SIDES: StringName = &"sides"
const PLAYER_GROUP: StringName = &"player"

var _state: State = State.HOLD
## Seconds spent in the current state.
var _t: float = 0.0
var _slot: Vector2 = Vector2.ZERO
var _has_slot: bool = false
var _entry: StringName = ENTRY_TOP
## Where the next ENTER starts.
var _entry_start: Vector2 = Vector2.ZERO
var _dive_dir: Vector2 = Vector2.DOWN
var _flash_on: bool = false
var _exit_rect: Rect2 = Rect2()

var _entry_speed: float = 0.0
var _dive_speed: float = 0.0
var _telegraph_s: float = 0.0
var _zone_height_ratio: float = 0.0
var _wing_flash_hz: float = 0.0
var _wing_flash_energy: float = 1.0

var _hull: CanvasItem = null


func _init() -> void:
	type_id = &"wasp"


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
	_entry_speed = Config.num("enemies.wasp.entry_speed_px_s")
	_dive_speed = Config.num("enemies.wasp.dive_speed_px_s")
	_telegraph_s = Config.num("enemies.wasp.telegraph_s")
	_zone_height_ratio = Config.num("enemies.wasp.zone_height_ratio")
	_wing_flash_hz = Config.num("enemies.wasp.wing_flash_hz")
	_wing_flash_energy = Config.num("enemies.wasp.wing_flash_energy")
	_hull = get_node_or_null(^"Hull") as CanvasItem
	_exit_rect = Playfield.RECT.grow(sprite_px / 2.0)
	if not _has_slot:
		_slot = global_position
		_entry_start = _top_entry_start()
		_enter_state(State.HOLD)
		return
	var zone_y: float = _zone_height_ratio * Playfield.SIZE.y
	if _slot.y > zone_y:
		Log.warn("spawn", "wasp slot y %.0f is below the formation zone (y <= %.0f); clamped" % [_slot.y, zone_y])
		_slot.y = zone_y
	if _entry == ENTRY_SIDES:
		var half: float = sprite_px / 2.0
		var x: float = -half if _slot.x <= Playfield.SIZE.x / 2.0 else Playfield.SIZE.x + half
		_entry_start = Vector2(x, _slot.y)
	else:
		if _entry != ENTRY_TOP:
			Log.warn("spawn", "wasp entry '%s' is unknown; using top" % _entry)
		_entry_start = _top_entry_start()
	_enter_state(State.ENTER)


func _physics_process(delta: float) -> void:
	step(delta)


## Advances the state machine by `delta` seconds.
func step(delta: float) -> void:
	_t += delta
	match _state:
		State.ENTER:
			global_position = global_position.move_toward(_slot, _entry_speed * delta)
			if global_position == _slot:
				_enter_state(State.HOLD)
		State.HOLD:
			pass
		State.TELEGRAPH:
			if _t >= _telegraph_s:
				_enter_state(State.DIVE)
			else:
				_set_flash(int(_t * _wing_flash_hz * 2.0) % 2 == 0)
		State.DIVE:
			global_position += _dive_dir * _dive_speed * delta
			if not _exit_rect.has_point(global_position):
				_entry_start = _top_entry_start()
				_enter_state(State.ENTER)


## Starts the telegraph, then the dive. Ignored unless holding and alive.
func start_dive() -> void:
	if _state != State.HOLD or _dead:
		return
	_enter_state(State.TELEGRAPH)


func state() -> State:
	return _state


func formation_slot() -> Vector2:
	return _slot


func is_holding() -> bool:
	return _state == State.HOLD


## True while the hull shows the bright wing-flash colour.
func is_flashing() -> bool:
	return _flash_on


func _enter_state(new_state: State) -> void:
	_state = new_state
	_t = 0.0
	_set_flash(new_state == State.TELEGRAPH)
	match new_state:
		State.ENTER:
			global_position = _entry_start
		State.DIVE:
			_dive_dir = _aim()


func _top_entry_start() -> Vector2:
	return Vector2(_slot.x, -sprite_px / 2.0)


## Direction toward the player's current position; straight down with no player.
func _aim() -> Vector2:
	var player: Node2D = get_tree().get_first_node_in_group(PLAYER_GROUP) as Node2D
	if player == null:
		return Vector2.DOWN
	var to_player: Vector2 = player.global_position - global_position
	if to_player.is_zero_approx():
		return Vector2.DOWN
	return to_player.normalized()


func _set_flash(on: bool) -> void:
	if on == _flash_on:
		return
	_flash_on = on
	if _hull != null:
		_hull.self_modulate = Color(_wing_flash_energy, _wing_flash_energy, _wing_flash_energy) if on else Color.WHITE
