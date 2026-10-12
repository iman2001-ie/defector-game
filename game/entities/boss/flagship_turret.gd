class_name FlagshipTurret
extends FlagshipPart
## One of the Flagship's Phase 1 turrets (Story 7.3, FR49): `boss.turrets`
## tuning (hp 25, the boss_part tier, sprite_px, hitbox_ratio).
##
## Idle until the Flagship calls start_firing(delay_s) on entering TURRETS.
## After `delay_s` its fire cycle runs start to start (decisions #38, #50,
## #52): every `fire_interval_s` it fires, and its Glow shows for the last
## `telegraph_s` of each period, then the shot. A shot is `spread_bullets`
## enemy_bullets, evenly spaced from -`spread_deg` to +`spread_deg` around
## straight down, at `bullet_speed_px_s`, each dealing damage.bullet_hearts.
## The spread is never aimed (like the Bastion's).
##
## The Flagship drives step(delta) while it is in TURRETS; the turret has no
## physics process of its own. Bullets are requested through `spawner`; without
## one the cycle runs but never fires. A kill plays the boss_part tier and
## always drops an orb (tuning.drops.flagship_turret).

const SECTION: String = "boss.turrets"
const BULLET_ID: StringName = &"enemy_bullet"

var _firing: bool = false
## Seconds into the current fire period; negative while the start delay runs.
var _t: float = 0.0
var _interval: float = 0.0
var _telegraph_s: float = 0.0
var _bullet_damage: int = 1
## One velocity per spread bullet, computed once in _ready.
var _spread_velocities: PackedVector2Array = PackedVector2Array()
var _glow: CanvasItem = null


func _init() -> void:
	type_id = &"flagship_turret"


func _ready() -> void:
	super()
	_interval = Config.num(_tuning_key("fire_interval_s"))
	_telegraph_s = Config.num(_tuning_key("telegraph_s"))
	_bullet_damage = Config.int_("damage.bullet_hearts")
	_spread_velocities = spread_velocities(
		Config.int_(_tuning_key("spread_bullets")),
		Config.num(_tuning_key("spread_deg")),
		Config.num(_tuning_key("bullet_speed_px_s")))
	if _interval <= 0.0:
		Log.warn("data", "boss.turrets.fire_interval_s is %s; the turrets never fire" % _interval)
	var glow_energy: float = Config.num(_tuning_key("glow_energy"))
	_glow = get_node_or_null(^"Glow") as CanvasItem
	if _glow != null:
		_glow.self_modulate = Color(glow_energy, glow_energy, glow_energy)
		_glow.visible = false
	else:
		Log.error("combat", "flagship turret has no Glow")


func _tuning_section() -> String:
	return SECTION


## Starts the fire cycle: the first period begins `delay_s` from now, so the
## first shot is at delay_s + fire_interval_s.
func start_firing(delay_s: float) -> void:
	_firing = true
	_t = -maxf(delay_s, 0.0)
	_set_glow(false)


func is_firing() -> bool:
	return _firing


## True while the Glow (the shot telegraph) is shown.
func is_glowing() -> bool:
	return _glow != null and _glow.visible


## Advances the fire cycle by `delta` seconds (called by the Flagship).
func step(delta: float) -> void:
	if not _firing or _dead or _interval <= 0.0:
		return
	_t += delta
	if _t >= _interval:
		_t -= _interval
		_fire()
	_set_glow(_t >= 0.0 and _t >= _interval - _telegraph_s)


## `count` velocities evenly spaced from -spread_deg to +spread_deg around
## straight down (one bullet flies straight down), each `speed` px/s long.
static func spread_velocities(count: int, spread_deg: float, speed: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in count:
		var a: float = 0.0
		if count > 1:
			a = -spread_deg + 2.0 * spread_deg * float(i) / float(count - 1)
		out.append(Vector2.DOWN.rotated(deg_to_rad(a)) * speed)
	return out


func _set_glow(on: bool) -> void:
	if _glow != null and _glow.visible != on:
		_glow.visible = on


func _fire() -> void:
	if not _can_fire():
		return
	var origin: Vector2 = global_position
	for velocity: Vector2 in _spread_velocities:
		spawner.spawn_projectile(BULLET_ID, {
			"position": origin,
			"velocity": velocity,
			"damage": _bullet_damage,
		})
