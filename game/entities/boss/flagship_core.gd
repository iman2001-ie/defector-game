class_name FlagshipCore
extends FlagshipPart
## The Flagship's core (Stories 7.3 and 7.4, FR50): `boss.core` tuning (hp 200,
## the boss_death tier, sprite_px, hitbox_ratio). It starts invulnerable and
## stays so for all of Phase 1, so shots on it are spent and ignored and it is
## no target.
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
## The Flagship drives step(delta) while it is in CORE; the core has no physics
## process of its own. Bullets are requested through `spawner`; without one the
## cycle runs but never fires (one DEBUG line). A kill plays the boss_death tier
## and emits enemy_killed(&"flagship_core", ...); the core drops nothing (the
## GDD drop table has no core row, so there is no drops.flagship_core).

const SECTION: String = "boss.core"
const BULLET_ID: StringName = &"enemy_bullet"

var _attacking: bool = false
## Seconds into the current radial period.
var _t: float = 0.0
var _interval: float = 0.0
var _charge_s: float = 0.0
var _bullet_damage: int = 1
## One velocity per radial bullet, computed once in _ready.
var _radial_velocities: PackedVector2Array = PackedVector2Array()
var _glow: CanvasItem = null


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
	var glow_energy: float = Config.num(_tuning_key("glow_energy"))
	_glow = get_node_or_null(^"Glow") as CanvasItem
	if _glow != null:
		_glow.self_modulate = Color(glow_energy, glow_energy, glow_energy)
		_glow.visible = false
	else:
		Log.error("combat", "flagship core has no Glow")


func _tuning_section() -> String:
	return SECTION


## Starts the radial cycle: the first burst is one full radial_interval_s from now.
func start_attacking() -> void:
	_attacking = true
	_t = 0.0
	_set_glow(false)


## Ends the radial cycle and hides the Glow.
func stop_attacking() -> void:
	_attacking = false
	_t = 0.0
	_set_glow(false)


func is_attacking() -> bool:
	return _attacking


## True while the Glow (the burst's charge) is shown.
func is_glowing() -> bool:
	return _glow != null and _glow.visible


## Advances the radial cycle by `delta` seconds (called by the Flagship).
func step(delta: float) -> void:
	if not _attacking or _dead or _interval <= 0.0:
		return
	_t += delta
	if _t >= _interval:
		_t -= _interval
		_fire()
	_set_glow(_t >= _interval - _charge_s)


## `count` velocities evenly spaced over 360 degrees, the first straight down
## (then clockwise on screen), each `speed` px/s long.
static func radial_velocities(count: int, speed: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in count:
		out.append(Vector2.DOWN.rotated(TAU * float(i) / float(count)) * speed)
	return out


## The core has no drops row: a kill drops nothing (and rolls no table).
func _drop_loot() -> void:
	pass


func _set_glow(on: bool) -> void:
	if _glow != null and _glow.visible != on:
		_glow.visible = on


func _fire() -> void:
	if not _can_fire():
		return
	var origin: Vector2 = global_position
	for velocity: Vector2 in _radial_velocities:
		spawner.spawn_projectile(BULLET_ID, {
			"position": origin,
			"velocity": velocity,
			"damage": _bullet_damage,
		})
