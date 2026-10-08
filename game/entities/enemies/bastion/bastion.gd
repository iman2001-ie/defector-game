class_name Bastion
extends Enemy
## Bastion: large turret gunship (GDD FR22, FR25, FR30).
##
## Wave Bastions (spawned with a `slot`) fly in from their `entry` side at
## enemies.bastion.drift_speed_px_s to their slot, then drift at that speed
## toward random targets inside the drift box: the whole hull stays inside
## band_y (y 80-400), fully on screen. Every fire_interval_s of drifting each
## turret's Glow shows for telegraph_s (still drifting), then every turret fires
## a spread of spread_bullets enemy_bullets, evenly spaced from -spread_deg to
## +spread_deg around straight down, at bullet_speed_px_s. The spread is never
## aimed at the player or the convoy.
##
## Bullets are requested through `spawner` (injected by Spawner). Without one
## the Bastion runs its cycle but never fires. Contact never destroys it (large
## tier, see Enemy.destroy_by_contact).
##
## Without a `slot` (the sandbox) the Bastion drifts from its spawn position.

enum State { ENTER, DRIFT, TELEGRAPH }

const ENTRY_TOP: StringName = &"top"
const ENTRY_SIDES: StringName = &"sides"
const BULLET_ID: StringName = &"enemy_bullet"

## Picks drift targets; tests seed it.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _state: State = State.DRIFT
## Seconds spent in the current state (the fire timer while drifting).
var _t: float = 0.0
var _slot: Vector2 = Vector2.ZERO
var _has_slot: bool = false
var _entry: StringName = ENTRY_TOP
var _entry_start: Vector2 = Vector2.ZERO
## Where the hull centre may drift: band_y shrunk by half the hull, x on screen.
var _box: Rect2 = Rect2()
var _target: Vector2 = Vector2.ZERO
var _has_target: bool = false
var _warned_no_spawner: bool = false

var _drift_speed: float = 0.0
var _fire_interval_s: float = 0.0
var _telegraph_s: float = 0.0
var _bullet_damage: int = 1
## One velocity per spread bullet, computed once in _ready.
var _spread_velocities: PackedVector2Array = PackedVector2Array()

var _turrets: Array[Node2D] = []
var _glows: Array[CanvasItem] = []


func _init() -> void:
	type_id = &"bastion"
	rng.randomize()


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
	_drift_speed = Config.num("enemies.bastion.drift_speed_px_s")
	_fire_interval_s = Config.num("enemies.bastion.fire_interval_s")
	_telegraph_s = Config.num("enemies.bastion.telegraph_s")
	_bullet_damage = Config.int_("damage.bullet_hearts")
	var band_min: float = Config.num("enemies.bastion.band_y.min")
	var band_max: float = Config.num("enemies.bastion.band_y.max")
	var glow_energy: float = Config.num("enemies.bastion.turret_glow_energy")
	_build_spread(
		Config.int_("enemies.bastion.spread_bullets"),
		Config.num("enemies.bastion.spread_deg"),
		Config.num("enemies.bastion.bullet_speed_px_s"))
	_collect_turrets(Config.int_("enemies.bastion.turrets"), glow_energy)
	var half: float = sprite_px / 2.0
	var y_min: float = band_min + half
	var y_max: float = band_max - half
	if y_min > y_max:
		y_min = (band_min + band_max) / 2.0
		y_max = y_min
	_box = Rect2(half, y_min, maxf(Playfield.SIZE.x - sprite_px, 0.0), y_max - y_min)
	if not _has_slot:
		_slot = global_position
		_enter_state(State.DRIFT)
		return
	var clamped: Vector2 = _clamp_to_box(_slot)
	if clamped != _slot:
		Log.warn("spawn", "bastion slot %s is outside its drift box; clamped to %s" % [_slot, clamped])
		_slot = clamped
	if _entry == ENTRY_SIDES:
		var x: float = -half if _slot.x <= Playfield.SIZE.x / 2.0 else Playfield.SIZE.x + half
		_entry_start = Vector2(x, _slot.y)
	else:
		if _entry != ENTRY_TOP:
			Log.warn("spawn", "bastion entry '%s' is unknown; using top" % _entry)
		_entry_start = Vector2(_slot.x, -half)
	_enter_state(State.ENTER)


func _physics_process(delta: float) -> void:
	step(delta)


## Advances the state machine by `delta` seconds.
func step(delta: float) -> void:
	_t += delta
	match _state:
		State.ENTER:
			global_position = global_position.move_toward(_slot, _drift_speed * delta)
			if global_position == _slot:
				_enter_state(State.DRIFT)
		State.DRIFT:
			_drift(delta)
			if _t >= _fire_interval_s:
				_enter_state(State.TELEGRAPH)
		State.TELEGRAPH:
			_drift(delta)
			if _t >= _telegraph_s:
				_fire()
				_enter_state(State.DRIFT)


func state() -> State:
	return _state


func formation_slot() -> Vector2:
	return _slot


## The point the Bastion is currently drifting toward.
func drift_target() -> Vector2:
	return _target


## Where the hull centre may be while drifting (a zero-height rect when the
## band is shorter than the hull).
func drift_box() -> Rect2:
	return _box


func turret_count() -> int:
	return _turrets.size()


## True while every turret glow (the shot telegraph) is shown.
func is_glowing() -> bool:
	if _glows.is_empty():
		return false
	for glow: CanvasItem in _glows:
		if not glow.visible:
			return false
	return true


func _enter_state(new_state: State) -> void:
	_state = new_state
	_t = 0.0
	var glowing: bool = new_state == State.TELEGRAPH
	for glow: CanvasItem in _glows:
		glow.visible = glowing
	match new_state:
		State.ENTER:
			global_position = _entry_start
		State.DRIFT:
			if not _has_target:
				_has_target = true
				_target = _pick_target()


func _build_spread(count: int, spread_deg: float, speed: float) -> void:
	_spread_velocities.clear()
	for i: int in count:
		var a: float = 0.0
		if count > 1:
			a = -spread_deg + 2.0 * spread_deg * float(i) / float(count - 1)
		_spread_velocities.append(Vector2.DOWN.rotated(deg_to_rad(a)) * speed)


func _collect_turrets(expected: int, glow_energy: float) -> void:
	_turrets.clear()
	_glows.clear()
	var root: Node = get_node_or_null(^"Turrets")
	if root != null:
		for child: Node in root.get_children():
			var turret: Node2D = child as Node2D
			if turret == null:
				continue
			_turrets.append(turret)
			var glow: CanvasItem = turret.get_node_or_null(^"Glow") as CanvasItem
			if glow != null:
				glow.self_modulate = Color(glow_energy, glow_energy, glow_energy)
				glow.visible = false
				_glows.append(glow)
	if _turrets.size() != expected:
		Log.warn("spawn", "bastion scene has %d turrets but tuning says %d; using the scene's" % [_turrets.size(), expected])


func _clamp_to_box(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, _box.position.x, _box.end.x), clampf(p.y, _box.position.y, _box.end.y))


func _pick_target() -> Vector2:
	return Vector2(
		rng.randf_range(_box.position.x, _box.end.x),
		rng.randf_range(_box.position.y, _box.end.y))


func _drift(delta: float) -> void:
	global_position = global_position.move_toward(_target, _drift_speed * delta)
	if global_position == _target:
		_target = _pick_target()


func _fire() -> void:
	if spawner == null or not is_instance_valid(spawner):
		if not _warned_no_spawner:
			_warned_no_spawner = true
			Log.debug("spawn", "bastion has no spawner; shot skipped")
		return
	for turret: Node2D in _turrets:
		var origin: Vector2 = turret.global_position
		for velocity: Vector2 in _spread_velocities:
			spawner.spawn_projectile(BULLET_ID, {
				"position": origin,
				"velocity": velocity,
				"damage": _bullet_damage,
			})
