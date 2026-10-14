class_name Flagship
extends Enemy
## Isolde's Flagship, the Level 3 boss (Story 7.3: Phase 1, FR49, FR52, FR53;
## Story 7.4: Phase 2, FR50; Story 7.5: Phase 3, FR51, FR54, FR30 boss death).
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
## rely on: ARRIVING, TURRETS, CORE, FINAL_CHOICE, DESPERATE, DYING:
## - ARRIVING: flies straight down from (centre, hull.arrive_from_y) to
##   (centre, hull.station_y) over hull.arrival_s, then enters TURRETS (or CORE
##   if every turret already died on the way in).
## - TURRETS: turret i (scene order) starts its fire cycle
##   i * boss.turrets.stagger_s after the phase began (FlagshipTurret). The
##   hp-change handler that sees the last turret die logs one INFO line and
##   enters CORE at once.
## - CORE (Story 7.4): entering it exposes the core (invulnerable = false) and
##   starts its radial cycle (FlagshipCore) and the Wasp launch timer. Every
##   boss.core.wasp_launch_interval_s (the first a full interval after CORE
##   began; no telegraph) the Flagship requests
##   n = min(wasp_launch_count, wasp_max_alive - live launched, free slots)
##   Wasps through spawner.spawn_enemy(&"wasp", {slot, launch_from}): they fly
##   out of the core centre to the first free boss.core.wasp_slots (row by row,
##   centred on the screen), then behave like wave Wasps (the WaspDiveClock
##   dives them). They join Groups.BOSS_WASPS, never Groups.COUNTED, and nobody
##   connects their `resolved`, so they never touch the wave's counts; a kill
##   rolls drops.wasp. This is the architecture's one exception to "only the
##   WaveDirector decides what spawns". Launches and core shots run only in
##   the CORE branch of step; entering any other phase stops the core cycle and
##   hides its Glow, and Wasps already alive stay until the boss's death
##   (decision F16, amended by DW-101).
## - FINAL_CHOICE (Story 7.5): _ready arms the core's hp floor
##   (boss.final_choice_hp). In CORE, the first hit that would take the core to
##   the floor or below clamps it there and makes it invulnerable (decision
##   F7, FlagshipCore.apply_damage); the hp-change handler then enters
##   FINAL_CHOICE once: the core attack and the launches stop (live Wasps
##   stay), boss_phase_changed(3) and boss_hp_changed(50, 300, 3) go out, then
##   Events.comms_sequence_requested(FINAL_CHOICE_SEQUENCE). The Flagship waits
##   for Events.comms_sequence_finished of that id (the channel emits it once
##   the chosen response has played) and then enters DESPERATE once; every
##   other id, and a finished outside FINAL_CHOICE, is ignored.
## - DESPERATE: the core is vulnerable again and runs start_desperate() (the
##   alternating radials, the aimed spread, the red pulse).
## - DYING: the core's death in any phase enters it (only DESPERATE allows that
##   with valid data). Part attacks stop, the hull and every live part leave
##   their collision layer (layer 0), and Feedback.boss_death(global_position)
##   plays the chain once. The boss's death ends the fight (DW-101, decision
##   #64): just before the chain's first explosion (so its sound is the newest
##   SFX voice) the Flagship sweeps the field (_end_the_fight): every other
##   live enemy (launched Wasps, any counted enemy; never the Flagship or its
##   parts) leaves through
##   Enemy.explode_without_kill() (its tier's impact, no enemy_killed, no
##   drops; a counted one still resolves), every EnemyBullet in flight
##   (NeedleBolt included) fizzles with the SMALL blocked-shot effect, and
##   spawner.hold_enemy_fire is set, so no new enemy shot spawns. The Player
##   turns safe on the same boss_phase_changed(DYING). After
##   feedback.boss_death_chain_s of game time the Flagship sweeps once more
##   (an enemy added during the chain), logs one INFO line, emits
##   Events.boss_defeated exactly once and frees itself.
## Every phase entry emits Events.boss_phase_changed(phase) and
## Events.boss_hp_changed(current, max, phase). _ready emits boss_started and
## enters ARRIVING.
##
## HP: the combined HP is the sum of max(part hp, 0) over the turrets and the
## core (300 with shipped data); `hp` holds it and _max_hp() is the full sum.
## Every part hp change re-emits boss_hp_changed. The Flagship itself never
## takes damage; the WaveDirector resolves the boss wave on boss_defeated.
##
## Created by Spawner.spawn_boss, which sets `spawner`; _ready hands it to the
## parts (children are ready before their parent). A `position` param is
## ignored: the Flagship always arrives from its tuning. Without a spawner the
## cycles still run but nothing fires or launches (one DEBUG line each for the
## core and the Flagship).

enum Phase { ARRIVING, TURRETS, CORE, FINAL_CHOICE, DESPERATE, DYING }

const SECTION: String = "boss.hull"
const WASP_ID: StringName = &"wasp"
## The story sequence FINAL_CHOICE requests (Isolde's lead-in and the choice).
const FINAL_CHOICE_SEQUENCE: StringName = &"l3_final_choice"
## Slack for DYING's float steps (120 steps of 1/60 s reach 2.0 s).
const DYING_EPSILON_S: float = 0.0001

var _phase: Phase = Phase.ARRIVING
## Seconds spent in the current phase.
var _t: float = 0.0
var _parts: Array[FlagshipPart] = []
var _turrets: Array[FlagshipTurret] = []
var _core: FlagshipCore = null
var _max_total: int = 0
var _all_turrets_logged: bool = false
## Seconds DYING lasts before boss_defeated (feedback.boss_death_chain_s).
var _death_chain_s: float = 0.0
## Set once boss_defeated has been emitted.
var _defeated: bool = false
var _arrive_from: Vector2 = Vector2.ZERO
var _station: Vector2 = Vector2.ZERO
var _arrival_s: float = 0.0
var _stagger_s: float = 0.0
## The core's local offset, cached in _ready: the Wasp launch origin (still
## valid after the core is freed).
var _core_offset: Vector2 = Vector2.ZERO
## Seconds into the current Wasp launch interval (CORE only).
var _launch_t: float = 0.0
var _launch_interval: float = 0.0
var _launch_count: int = 0
var _launch_max_alive: int = 0
## The boss Wasp slots (global), in fill order: row by row, left to right.
var _wasp_slots: Array[Vector2] = []
## Wasps this Flagship launched; freed or dead ones are pruned before a launch.
var _launched: Array[Wasp] = []


func _init() -> void:
	type_id = &"flagship"


func _ready() -> void:
	_collect_parts()
	# The Hull sprite (Story 8.2) is fitted by Enemy._ready so its longer side is
	# the hull width, the same boss.hull.width_px as the hitbox rect.
	sprite_px = Config.num(_tuning_key("width_px"))
	super()
	add_to_group(Groups.BOSS)
	_max_total = hp
	var centre_x: float = Playfield.SIZE.x / 2.0
	_station = Vector2(centre_x, Config.num(_tuning_key("station_y")))
	_arrive_from = Vector2(centre_x, Config.num(_tuning_key("arrive_from_y")))
	_arrival_s = maxf(Config.num(_tuning_key("arrival_s")), 0.0)
	_stagger_s = maxf(Config.num("boss.turrets.stagger_s"), 0.0)
	_read_launch_tuning()
	_death_chain_s = maxf(Config.num("feedback.boss_death_chain_s"), 0.0)
	if _core != null:
		_core_offset = _core.position
		_core.set_hp_floor(Config.int_("boss.final_choice_hp"))
	for part: FlagshipPart in _parts:
		part.spawner = spawner
		part.hp_changed.connect(_on_part_hp_changed)
	global_position = _arrive_from
	Events.comms_sequence_finished.connect(_on_events_comms_sequence_finished)
	Log.info("combat", "Flagship arriving (%d HP)" % _max_total)
	Events.boss_started.emit()
	_enter_phase(Phase.ARRIVING)


func _exit_tree() -> void:
	if Events.comms_sequence_finished.is_connected(_on_events_comms_sequence_finished):
		Events.comms_sequence_finished.disconnect(_on_events_comms_sequence_finished)


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
				_enter_phase(Phase.TURRETS if live_turret_count() > 0 else Phase.CORE)
		Phase.TURRETS:
			for turret: FlagshipTurret in _turrets:
				if is_instance_valid(turret) and not turret.is_dead():
					turret.step(delta)
		Phase.CORE:
			if _core_alive():
				_core.step(delta)
			if _launch_interval > 0.0:
				_launch_t += delta
				if _launch_t >= _launch_interval:
					_launch_t -= _launch_interval
					_launch_wasps()
		Phase.DESPERATE:
			if _core_alive():
				_core.step(delta)
		Phase.DYING:
			if not _defeated and _t + DYING_EPSILON_S >= _death_chain_s:
				_defeated = true
				_end_the_fight()
				Log.info("combat", "Flagship destroyed: boss defeated")
				Events.boss_defeated.emit()
				queue_free()


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
	if new_phase != Phase.CORE and _core_alive():
		_core.stop_attacking()
	match new_phase:
		Phase.TURRETS:
			for i: int in _turrets.size():
				if is_instance_valid(_turrets[i]):
					_turrets[i].start_firing(float(i) * _stagger_s)
		Phase.CORE:
			_launch_t = 0.0
			if _core_alive():
				_core.invulnerable = false
				_core.start_attacking()
		Phase.FINAL_CHOICE:
			if _core_alive():
				_core.invulnerable = true
		Phase.DESPERATE:
			if _core_alive():
				_core.invulnerable = false
				_core.start_desperate()
		Phase.DYING:
			_stop_parts()
	Log.info("combat", "Flagship phase %s" % Phase.keys()[new_phase])
	Events.boss_phase_changed.emit(int(new_phase))
	_emit_hp()
	match new_phase:
		Phase.FINAL_CHOICE:
			Events.comms_sequence_requested.emit(FINAL_CHOICE_SEQUENCE)
		Phase.DYING:
			# Sweep first, so the boss-death sound is the newest voice in the
			# combat SFX pool (the pool steals the oldest).
			_end_the_fight()
			Feedback.boss_death(global_position)


func _emit_hp() -> void:
	hp = current_hp()
	Events.boss_hp_changed.emit(hp, _max_total, int(_phase))


func _on_part_hp_changed(_part_hp: int) -> void:
	_emit_hp()
	if not _all_turrets_logged and not _turrets.is_empty() and live_turret_count() == 0:
		_all_turrets_logged = true
		Log.info("combat", "Flagship: all turrets destroyed")
		# While ARRIVING, the end of the arrival enters CORE instead, so the hull
		# still reaches its station.
		if _phase == Phase.TURRETS:
			_enter_phase(Phase.CORE)
	if _phase == Phase.DYING or _core == null or not is_instance_valid(_core):
		return
	if _core.is_dead():
		Log.info("combat", "Flagship: core destroyed")
		_enter_phase(Phase.DYING)
	elif _phase == Phase.CORE and _core.invulnerable:
		# The core's hp floor clamped it (FlagshipCore.apply_damage).
		_enter_phase(Phase.FINAL_CHOICE)


func _on_events_comms_sequence_finished(sequence_id: StringName) -> void:
	if sequence_id == FINAL_CHOICE_SEQUENCE and _phase == Phase.FINAL_CHOICE:
		_enter_phase(Phase.DESPERATE)


## DYING: no part attacks any more, and the hull and every live part leave
## their collision layer (no hits, no contact, no targeting by overlap).
func _stop_parts() -> void:
	collision_layer = 0
	for part: FlagshipPart in _parts:
		if is_instance_valid(part):
			part.collision_layer = 0
			if part is FlagshipTurret:
				(part as FlagshipTurret).stop_firing()


## The boss's death ends the fight (DW-101, decision #64). Every other live
## enemy explodes through the no-kill exit (Enemy.explode_without_kill: its
## tier's impact, `resolved`, no enemy_killed, no drops); the Flagship and its
## parts are skipped (the chain is their feedback). Every EnemyBullet in flight
## (NeedleBolt included) fizzles with the SMALL blocked-shot effect; player and
## ally shots, asteroids, orbs and story props are untouched. With a spawner,
## hold_enemy_fire is set so no new enemy shot spawns. Runs on DYING entry,
## just before Feedback.boss_death (so the boss-death sound is the newest voice
## in the combat SFX pool), and once more just before boss_defeated (two group
## scans per boss death).
func _end_the_fight() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var swept: int = 0
	for node: Node in tree.get_nodes_in_group(Groups.ENEMIES):
		var enemy: Enemy = node as Enemy
		if enemy == null or enemy is Flagship or enemy is FlagshipPart:
			continue
		if enemy.is_dead() or enemy.is_queued_for_deletion():
			continue
		enemy.explode_without_kill()
		swept += 1
	var fizzled: int = 0
	for node: Node in tree.get_nodes_in_group(Groups.PROJECTILES):
		var shot: EnemyBullet = node as EnemyBullet
		if shot == null or shot.is_queued_for_deletion():
			continue
		shot.fizzle()
		fizzled += 1
	if spawner != null and is_instance_valid(spawner):
		spawner.hold_enemy_fire = true
	if swept > 0 or fizzled > 0:
		Log.info("combat", "Flagship death ends the fight: %d enemies swept, %d enemy shots fizzled" % [swept, fizzled])


func _core_alive() -> bool:
	return _core != null and is_instance_valid(_core) and not _core.is_dead()


## Reads the boss.core launch numbers and builds the slot list: `columns`
## slots `spacing_x_px` apart, centred on the screen, on each of `rows_y`.
func _read_launch_tuning() -> void:
	_launch_interval = Config.num("boss.core.wasp_launch_interval_s")
	_launch_count = Config.int_("boss.core.wasp_launch_count")
	_launch_max_alive = Config.int_("boss.core.wasp_max_alive")
	if _launch_interval <= 0.0:
		Log.warn("data", "boss.core.wasp_launch_interval_s is %s; the Flagship never launches Wasps" % _launch_interval)
	var columns: int = Config.int_("boss.core.wasp_slots.columns")
	var spacing: float = Config.num("boss.core.wasp_slots.spacing_x_px")
	var rows: Variant = Config.section("boss.core.wasp_slots").get("rows_y")
	_wasp_slots.clear()
	if not (rows is Array):
		Log.error("data", "boss.core.wasp_slots.rows_y missing or not an array; no Wasp launches")
		return
	var centre_x: float = Playfield.SIZE.x / 2.0
	for y: Variant in rows:
		if not (y is float or y is int):
			Log.error("data", "boss.core.wasp_slots.rows_y entry %s is not a number; row skipped" % y)
			continue
		for c: int in columns:
			_wasp_slots.append(Vector2(centre_x + (float(c) - float(columns - 1) / 2.0) * spacing, float(y)))
	if _wasp_slots.size() < _launch_max_alive:
		Log.warn("data", "boss.core.wasp_slots has %d slots for wasp_max_alive %d" % [_wasp_slots.size(), _launch_max_alive])


## One launch tick: n = min(wasp_launch_count, wasp_max_alive - live launched,
## free slots) Wasps from the core centre into the first free slots. A null
## spawn is skipped. Without a spawner nothing launches (one DEBUG line).
func _launch_wasps() -> void:
	_prune_launched()
	if not _can_launch():
		return
	var n: int = mini(_launch_count, _launch_max_alive - _launched.size())
	if n <= 0:
		return
	var origin: Vector2 = to_global(_core_offset)
	var spawned: int = 0
	for slot: Vector2 in _wasp_slots:
		if n <= 0:
			break
		if _slot_taken(slot):
			continue
		n -= 1
		var wasp: Wasp = spawner.spawn_enemy(WASP_ID, {"slot": slot, "launch_from": origin}) as Wasp
		if wasp == null:
			continue
		wasp.add_to_group(Groups.BOSS_WASPS)
		_launched.append(wasp)
		spawned += 1
	Log.debug("spawn", "Flagship launched %d Wasps (%d alive)" % [spawned, _launched.size()])


## Drops freed and dead Wasps from _launched, in place.
func _prune_launched() -> void:
	for i: int in range(_launched.size() - 1, -1, -1):
		var entry: Variant = _launched[i]
		if not is_instance_valid(entry) or (entry as Wasp).is_dead():
			_launched.remove_at(i)


## True when a live launched Wasp holds `slot` (call after _prune_launched).
func _slot_taken(slot: Vector2) -> bool:
	for wasp: Wasp in _launched:
		if wasp.formation_slot() == slot:
			return true
	return false


## True when `spawner` can take a launch request. Without one, logs a DEBUG
## line once (the _can_fire pattern) and returns false.
func _can_launch() -> bool:
	if spawner != null and is_instance_valid(spawner):
		return true
	if not _warned_no_spawner:
		_warned_no_spawner = true
		Log.debug("spawn", "%s has no spawner; Wasp launch skipped" % type_id)
	return false
