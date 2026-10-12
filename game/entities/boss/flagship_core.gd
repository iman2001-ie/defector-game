class_name FlagshipCore
extends FlagshipPart
## The Flagship's core (Stories 7.3-7.5, FR50, FR51): `boss.core` tuning (hp
## 200, the boss_death tier, sprite_px, hitbox_ratio). It starts invulnerable
## and stays so for all of Phase 1, so shots on it are spent and ignored and it
## is no target.
##
## Phase 2 (Story 7.4): the Flagship sets `invulnerable = false` and calls
## start_attacking() on entering CORE. The radial cycle then runs start to start
## (decisions #38, #50, #52): every `radial_interval_s` it fires, and its Glow
## (`glow_energy`) shows for the last `charge_s` of each period, then the burst.
## The first burst comes one full period after start_attacking(). A burst is
## `radial_bullets` enemy_bullets from the core centre, evenly spaced over 360
## degrees with one flying straight down, each at `radial_speed_px_s` and
## dealing damage.bullet_hearts. stop_attacking() ends the cycle and hides the
## Glow.
##
## The 50 HP clamp (Story 7.5, decision F7): the Flagship arms an hp floor with
## set_hp_floor(boss.final_choice_hp). The first hit that would take a
## vulnerable core to the floor or below sets hp to exactly the floor (never a
## kill, whatever the damage; a bad floor above the hp never raises it), makes
## the core invulnerable, disarms the floor and emits hp_changed. Once only.
##
## Desperate (Story 7.5, FR51): start_desperate() runs two start-to-start
## cycles from `boss.desperate` (decisions #38, #50, #52):
## - the radial every `radial_interval_s`: `radial_bullets` at
##   `radial_speed_px_s`, burst j rotated by
##   (j mod radial_bursts) * (360 / radial_bullets) / radial_bursts degrees, so
##   with 2 bursts every other one sits in the gaps of the last;
## - the aimed spread every `aimed_interval_s`: `aimed_bullets` at
##   `aimed_speed_px_s` from -`aimed_spread_deg` to +`aimed_spread_deg` around
##   the core->player direction (_aim_from).
## The first radial comes one full radial period in, the first aimed spread one
## full aimed period in. The Glow shows during the last `radial_charge_s` of
## each radial period and the last `aimed_telegraph_s` of each aimed period.
## The `Eye` pulses toward `pulse_color` (red) with a steady sine at
## `pulse_hz`. Bullets come from the core centre and deal damage.bullet_hearts.
##
## The Flagship drives step(delta) while it is in CORE or DESPERATE; the core
## has no physics process of its own. Bullets are requested through `spawner`;
## without one the cycles run but never fire (one DEBUG line). A kill emits
## enemy_killed(&"flagship_core", ...) with no impact of its own
## (_death_feedback: the Flagship's death chain is the feedback) and drops
## nothing (the GDD drop table has no core row, so there is no
## drops.flagship_core).

enum Mode { IDLE, RADIAL, DESPERATE }

const SECTION: String = "boss.core"
const DESPERATE_SECTION: String = "boss.desperate"
const BULLET_ID: StringName = &"enemy_bullet"

## The colour the Eye pulses toward in the desperate phase (DESIGN `danger`).
@export var pulse_color: Color = Color(1.0, 0.121569, 0.294118, 1.0)

var _mode: Mode = Mode.IDLE
## Seconds into the current radial period (Phase 2 and desperate).
var _t: float = 0.0
var _interval: float = 0.0
var _charge_s: float = 0.0
var _bullet_damage: int = 1
## One velocity per radial bullet, computed once in _ready.
var _radial_velocities: PackedVector2Array = PackedVector2Array()
var _glow: CanvasItem = null
var _eye: Polygon2D = null
var _eye_color: Color = Color.WHITE
## The hp floor (0 = disarmed), see set_hp_floor.
var _hp_floor: int = 0

## `boss.desperate`, cached in _ready.
var _d_radial_interval: float = 0.0
var _d_radial_charge: float = 0.0
var _d_radial_bursts: int = 1
## The desperate radial burst before its rotation, and the rotation step.
var _d_radial_velocities: PackedVector2Array = PackedVector2Array()
var _d_rotation_step_rad: float = 0.0
var _d_aimed_interval: float = 0.0
var _d_aimed_telegraph: float = 0.0
## The aimed spread around straight down, rotated onto the aim when it fires.
var _d_aimed_velocities: PackedVector2Array = PackedVector2Array()
var _d_pulse_hz: float = 0.0
## Desperate state: seconds into the aimed period, radial bursts fired, pulse clock.
var _aimed_t: float = 0.0
var _radial_count: int = 0
var _pulse_t: float = 0.0


func _init() -> void:
	type_id = &"flagship_core"
	invulnerable = true


func _ready() -> void:
	super()
	_interval = Config.num(_tuning_key("radial_interval_s"))
	_charge_s = Config.num(_tuning_key("charge_s"))
	_bullet_damage = Config.int_("damage.bullet_hearts")
	_radial_velocities = radial_velocities(
		Config.int_(_tuning_key("radial_bullets")),
		Config.num(_tuning_key("radial_speed_px_s")))
	if _interval <= 0.0:
		Log.warn("data", "boss.core.radial_interval_s is %s; the core never fires" % _interval)
	_read_desperate_tuning()
	var glow_energy: float = Config.num(_tuning_key("glow_energy"))
	_glow = get_node_or_null(^"Glow") as CanvasItem
	if _glow != null:
		_glow.self_modulate = Color(glow_energy, glow_energy, glow_energy)
		_glow.visible = false
	else:
		Log.error("combat", "flagship core has no Glow")
	_eye = get_node_or_null(^"Eye") as Polygon2D
	if _eye != null:
		_eye_color = _eye.color
	else:
		Log.error("combat", "flagship core has no Eye")


func _tuning_section() -> String:
	return SECTION


## The clamp: a hit that would take a vulnerable, living core to the armed
## floor or below sets hp to exactly the floor, makes it invulnerable, disarms
## the floor and emits hp_changed (never a kill). Every other hit goes through
## FlagshipPart.apply_damage.
func apply_damage(amount: int, source: Node) -> void:
	if not invulnerable and not _dead and _hp_floor > 0 and hp - amount <= _hp_floor:
		hp = mini(hp, _hp_floor)
		_hp_floor = 0
		invulnerable = true
		hp_changed.emit(hp)
		return
	super(amount, source)


## Arms the one-shot hp floor (0 or less disarms it).
func set_hp_floor(value: int) -> void:
	_hp_floor = maxi(value, 0)


func hp_floor() -> int:
	return _hp_floor


## Starts the Phase 2 radial cycle: the first burst is one full radial_interval_s from now.
func start_attacking() -> void:
	_stop()
	_mode = Mode.RADIAL


## Starts the desperate cycles (radial and aimed, each one full period in) and
## the red pulse.
func start_desperate() -> void:
	_stop()
	_mode = Mode.DESPERATE


## Ends any cycle, hides the Glow and stops the pulse.
func stop_attacking() -> void:
	_stop()


func is_attacking() -> bool:
	return _mode != Mode.IDLE


func is_desperate() -> bool:
	return _mode == Mode.DESPERATE


## True while the Glow (a burst's charge or the aimed telegraph) is shown.
func is_glowing() -> bool:
	return _glow != null and _glow.visible


## True while the Eye pulses toward red (the desperate phase).
func is_pulsing() -> bool:
	return _mode == Mode.DESPERATE and _d_pulse_hz > 0.0


## How far the Eye is toward pulse_color: 0 (its own colour) to 1 (red).
func pulse_amount() -> float:
	if not is_pulsing():
		return 0.0
	return pulse_at(_pulse_t, _d_pulse_hz)


## The Eye's colour now.
func eye_color() -> Color:
	return _eye.color if _eye != null else Color.TRANSPARENT


## The steady sine pulse: 0 at t = 0, 1 half a period later.
static func pulse_at(t: float, hz: float) -> float:
	return 0.5 - 0.5 * cos(TAU * hz * t)


## Advances the active cycle by `delta` seconds (called by the Flagship).
func step(delta: float) -> void:
	if _dead:
		return
	match _mode:
		Mode.RADIAL:
			_step_radial(delta)
		Mode.DESPERATE:
			_step_desperate(delta)


## `count` velocities evenly spaced over 360 degrees, the first straight down
## (then clockwise on screen), each `speed` px/s long.
static func radial_velocities(count: int, speed: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in count:
		out.append(Vector2.DOWN.rotated(TAU * float(i) / float(count)) * speed)
	return out


## The rotation of desperate radial burst `index` (0-based), in degrees:
## (index mod bursts) * (360 / bullets) / bursts.
static func desperate_rotation_deg(index: int, bullets: int, bursts: int) -> float:
	if bullets <= 0 or bursts <= 0:
		return 0.0
	return float(index % bursts) * (360.0 / float(bullets)) / float(bursts)


## The core has no drops row: a kill drops nothing (and rolls no table).
func _drop_loot() -> void:
	pass


## The core's death plays no impact of its own: the Flagship's DYING phase
## plays Feedback.boss_death (Story 7.5).
func _death_feedback() -> void:
	pass


func _read_desperate_tuning() -> void:
	_d_radial_interval = Config.num(_desperate_key("radial_interval_s"))
	_d_radial_charge = Config.num(_desperate_key("radial_charge_s"))
	_d_radial_bursts = maxi(Config.int_(_desperate_key("radial_bursts")), 1)
	var radial_bullets: int = Config.int_(_desperate_key("radial_bullets"))
	_d_radial_velocities = radial_velocities(radial_bullets, Config.num(_desperate_key("radial_speed_px_s")))
	_d_rotation_step_rad = deg_to_rad(desperate_rotation_deg(1, radial_bullets, _d_radial_bursts))
	_d_aimed_interval = Config.num(_desperate_key("aimed_interval_s"))
	_d_aimed_telegraph = Config.num(_desperate_key("aimed_telegraph_s"))
	_d_aimed_velocities = FlagshipTurret.spread_velocities(
		Config.int_(_desperate_key("aimed_bullets")),
		Config.num(_desperate_key("aimed_spread_deg")),
		Config.num(_desperate_key("aimed_speed_px_s")))
	_d_pulse_hz = Config.num(_desperate_key("pulse_hz"))
	if _d_radial_interval <= 0.0 or _d_aimed_interval <= 0.0:
		Log.warn("data", "boss.desperate intervals %s / %s; a cycle that isn't positive never fires" % [_d_radial_interval, _d_aimed_interval])


## Config key for a `boss.desperate` field.
func _desperate_key(field: String) -> String:
	return "%s.%s" % [DESPERATE_SECTION, field]


func _stop() -> void:
	_mode = Mode.IDLE
	_t = 0.0
	_aimed_t = 0.0
	_radial_count = 0
	_pulse_t = 0.0
	_set_glow(false)
	if _eye != null:
		_eye.color = _eye_color


func _step_radial(delta: float) -> void:
	if _interval <= 0.0:
		return
	_t += delta
	if _t >= _interval:
		_t -= _interval
		_fire_burst(_radial_velocities, 0.0)
	_set_glow(_t >= _interval - _charge_s)


func _step_desperate(delta: float) -> void:
	var glow: bool = false
	if _d_radial_interval > 0.0:
		_t += delta
		if _t >= _d_radial_interval:
			_t -= _d_radial_interval
			_fire_burst(_d_radial_velocities, float(_radial_count % _d_radial_bursts) * _d_rotation_step_rad)
			_radial_count += 1
		glow = _t >= _d_radial_interval - _d_radial_charge
	if _d_aimed_interval > 0.0:
		_aimed_t += delta
		if _aimed_t >= _d_aimed_interval:
			_aimed_t -= _d_aimed_interval
			_fire_burst(_d_aimed_velocities, Vector2.DOWN.angle_to(_aim_from(global_position)))
		glow = glow or _aimed_t >= _d_aimed_interval - _d_aimed_telegraph
	_set_glow(glow)
	_pulse_t += delta
	if _eye != null and _d_pulse_hz > 0.0:
		_eye.color = _eye_color.lerp(pulse_color, pulse_at(_pulse_t, _d_pulse_hz))


func _set_glow(on: bool) -> void:
	if _glow != null and _glow.visible != on:
		_glow.visible = on


## Fires `velocities` rotated by `rotation_rad` from the core centre.
func _fire_burst(velocities: PackedVector2Array, rotation_rad: float) -> void:
	if not _can_fire():
		return
	var origin: Vector2 = global_position
	for velocity: Vector2 in velocities:
		spawner.spawn_projectile(BULLET_ID, {
			"position": origin,
			"velocity": velocity.rotated(rotation_rad),
			"damage": _bullet_damage,
		})
