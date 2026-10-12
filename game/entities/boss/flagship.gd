class_name Flagship
extends Enemy
## Isolde's Flagship, the Level 3 boss (Story 7.3: Phase 1, FR49, FR52, FR53).
##
## An armoured hull (`boss.hull`) with 4 FlagshipTurret children (`Turrets/*`)
## and an invulnerable FlagshipCore (`Core`), all Enemy areas on the `enemies`
## layer with mask 0. The hull is armour: apply_damage on it is ignored (the
## shot is spent), it is no target (is_targetable) and contact never destroys
## it (its tier is boss_death; the Player charges damage.contact_large_hearts).
## The scene keeps every part's hitbox below the hull's rect, so a shot from
## below reaches a part before the hull.
##
## Phase state machine (`match` + _enter_phase), in the order Stories 7.4-7.7
## rely on: ARRIVING, TURRETS, CORE, FINAL_CHOICE, DESPERATE, DYING. Story 7.3
## builds the first two:
## - ARRIVING: flies straight down from (centre, hull.arrive_from_y) to
##   (centre, hull.station_y) over hull.arrival_s, then enters TURRETS.
## - TURRETS: turret i (scene order) starts its fire cycle
##   i * boss.turrets.stagger_s after the phase began (FlagshipTurret). When the
##   last turret dies the Flagship logs one INFO line and stays in TURRETS
##   (CORE is Story 7.4).
## Every phase entry emits Events.boss_phase_changed(phase) and
## Events.boss_hp_changed(current, max, phase). _ready emits boss_started and
## enters ARRIVING.
##
## HP: the combined HP is the sum of max(part hp, 0) over the turrets and the
## core (300 with shipped data); `hp` holds it and _max_hp() is the full sum.
## Every part hp change re-emits boss_hp_changed. The Flagship never dies and
## never resolves in Story 7.3 (no boss_defeated); the WaveDirector frees it.
##
## Created by Spawner.spawn_boss, which sets `spawner`; _ready hands it to the
## parts (children are ready before their parent). A `position` param is
## ignored: the Flagship always arrives from its tuning.

enum Phase { ARRIVING, TURRETS, CORE, FINAL_CHOICE, DESPERATE, DYING }

const SECTION: String = "boss.hull"

var _phase: Phase = Phase.ARRIVING
## Seconds spent in the current phase.
var _t: float = 0.0
var _parts: Array[FlagshipPart] = []
var _turrets: Array[FlagshipTurret] = []
var _core: FlagshipCore = null
var _max_total: int = 0
var _all_turrets_logged: bool = false
var _arrive_from: Vector2 = Vector2.ZERO
var _station: Vector2 = Vector2.ZERO
var _arrival_s: float = 0.0
var _stagger_s: float = 0.0


func _init() -> void:
	type_id = &"flagship"


func _ready() -> void:
	_collect_parts()
	super()
	add_to_group(Groups.BOSS)
	_max_total = hp
	var centre_x: float = Playfield.SIZE.x / 2.0
	_station = Vector2(centre_x, Config.num(_tuning_key("station_y")))
	_arrive_from = Vector2(centre_x, Config.num(_tuning_key("arrive_from_y")))
	_arrival_s = maxf(Config.num(_tuning_key("arrival_s")), 0.0)
	_stagger_s = maxf(Config.num("boss.turrets.stagger_s"), 0.0)
	for part: FlagshipPart in _parts:
		part.spawner = spawner
		part.hp_changed.connect(_on_part_hp_changed)
	global_position = _arrive_from
	Log.info("combat", "Flagship arriving (%d HP)" % _max_total)
	Events.boss_started.emit()
	_enter_phase(Phase.ARRIVING)


func _physics_process(delta: float) -> void:
	step(delta)


## Advances the phase state machine by `delta` seconds.
func step(delta: float) -> void:
	_t += delta
	match _phase:
		Phase.ARRIVING:
			var k: float = 1.0 if _arrival_s <= 0.0 else clampf(_t / _arrival_s, 0.0, 1.0)
			global_position = _arrive_from.lerp(_station, k)
			if k >= 1.0:
				_enter_phase(Phase.TURRETS)
		Phase.TURRETS:
			for turret: FlagshipTurret in _turrets:
				if is_instance_valid(turret) and not turret.is_dead():
					turret.step(delta)


# --- Damage and targeting --------------------------------------------------------

## The hull is armour: every hit on it is ignored (the projectile is still spent).
func apply_damage(_amount: int, _source: Node) -> void:
	pass


## The hull is never a target for micro-missiles or the ally.
func is_targetable() -> bool:
	return false


# --- Read accessors (tests, HUD-free) -------------------------------------------

func phase() -> Phase:
	return _phase


## Combined HP: the sum of max(part hp, 0) over the live parts.
func current_hp() -> int:
	var total: int = 0
	for part: FlagshipPart in _parts:
		if is_instance_valid(part):
			total += maxi(part.hp, 0)
	return total


func max_hp() -> int:
	return _max_total


## The turrets in scene order (freed ones included until checked).
func turrets() -> Array[FlagshipTurret]:
	return _turrets


func core() -> FlagshipCore:
	return _core


## Turrets still alive.
func live_turret_count() -> int:
	var count: int = 0
	for turret: FlagshipTurret in _turrets:
		if is_instance_valid(turret) and not turret.is_dead():
			count += 1
	return count


# --- Enemy hooks -----------------------------------------------------------------

func _tuning_section() -> String:
	return SECTION


## The full combined HP: every part's hp (the parts are ready before the hull).
func _max_hp() -> int:
	var total: int = 0
	for part: FlagshipPart in _parts:
		total += maxi(part.hp, 0)
	return total


## The hull hitbox: a hull.width_px x hull.height_px rect centred on the origin.
func _hitbox_shape() -> Shape2D:
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(Config.num(_tuning_key("width_px")), Config.num(_tuning_key("height_px")))
	return rect


# --- Internals -------------------------------------------------------------------

func _collect_parts() -> void:
	_parts.clear()
	_turrets.clear()
	_core = null
	var root: Node = get_node_or_null(^"Turrets")
	if root != null:
		for child: Node in root.get_children():
			var turret: FlagshipTurret = child as FlagshipTurret
			if turret != null:
				_turrets.append(turret)
				_parts.append(turret)
	_core = get_node_or_null(^"Core") as FlagshipCore
	if _core != null:
		_parts.append(_core)
	else:
		Log.error("combat", "flagship has no Core")
	var expected: int = Config.int_("boss.turrets.count")
	if _turrets.size() != expected:
		Log.warn("spawn", "flagship scene has %d turrets but tuning says %d; using the scene's" % [_turrets.size(), expected])


func _enter_phase(new_phase: Phase) -> void:
	_phase = new_phase
	_t = 0.0
	match new_phase:
		Phase.TURRETS:
			for i: int in _turrets.size():
				if is_instance_valid(_turrets[i]):
					_turrets[i].start_firing(float(i) * _stagger_s)
	Log.info("combat", "Flagship phase %s" % Phase.keys()[new_phase])
	Events.boss_phase_changed.emit(int(new_phase))
	_emit_hp()


func _emit_hp() -> void:
	hp = current_hp()
	Events.boss_hp_changed.emit(hp, _max_total, int(_phase))


func _on_part_hp_changed(_part_hp: int) -> void:
	_emit_hp()
	if not _all_turrets_logged and not _turrets.is_empty() and live_turret_count() == 0:
		_all_turrets_logged = true
		Log.info("combat", "Flagship: all turrets destroyed")
