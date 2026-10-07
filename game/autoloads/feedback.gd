extends Node
## Impact feedback (Pillar 2): one call per hit or death scales the explosion,
## camera shake, hit-stop and SFX with the impact tier. Tier rows come from
## tuning.feedback.tiers (read once in load_tiers()).
##
## The only owner of Engine.time_scale (hit-stop). Scene nodes register
## themselves: the level's ShakeCamera and Spawner.

## Where prewarm() spawns its explosions: off-screen left, vertically centred.
const PREWARM_POSITION: Vector2 = Vector2(-1000, 540)

## One cached row per tier, indexed by ImpactTier.
var _tiers: Array[Dictionary] = []
var _camera: ShakeCamera = null
var _spawner: Spawner = null
var _hit_stop_end_usec: int = 0
var _hit_stop_serial: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_tiers()


## Reads every tier row from tuning (missing keys log through Config).
func load_tiers() -> void:
	_tiers.clear()
	for tier_name: String in ImpactTier.NAMES:
		var key: String = "feedback.tiers.%s" % tier_name
		var raw: Dictionary = Config.section(key)
		var extras: Array[StringName] = []
		var raw_extras: Variant = raw.get("extras", [])
		if raw_extras is Array:
			for extra: Variant in raw_extras as Array:
				extras.append(StringName(str(extra)))
		_tiers.append({
			"explosion_scale": Config.num(key + ".explosion_scale"),
			"shake_px": Config.num(key + ".shake_px"),
			"shake_s": Config.num(key + ".shake_s"),
			"hit_stop_ms": Config.num(key + ".hit_stop_ms"),
			"sfx_pitch": Config.num(key + ".sfx_pitch"),
			"sfx_volume_db": Config.num(key + ".sfx_volume_db"),
			"sfx": StringName(str(raw.get("sfx", ""))),
			"extras": extras,
		})


## The cached row for a tier (a copy), or {} when out of range.
func tier_row(tier: int) -> Dictionary:
	if tier < 0 or tier >= _tiers.size():
		return {}
	return _tiers[tier].duplicate(true)


func register_camera(c: ShakeCamera) -> void:
	_camera = c


func unregister_camera(c: ShakeCamera) -> void:
	if _camera == c:
		_camera = null


func register_spawner(s: Spawner) -> void:
	_spawner = s


func unregister_spawner(s: Spawner) -> void:
	if _spawner == s:
		_spawner = null


## Explosion + shake + hit-stop + SFX for one impact of the given tier.
func impact(tier: int, position: Vector2) -> void:
	if tier < 0 or tier >= _tiers.size():
		Log.error("combat", "Feedback.impact: unknown tier %d" % tier)
		return
	var row: Dictionary = _tiers[tier]
	_spawn_explosion(row, position)
	var shake_px: float = row["shake_px"]
	var shake_s: float = row["shake_s"]
	if _camera != null and is_instance_valid(_camera) and shake_px > 0.0 and shake_s > 0.0:
		_camera.shake(shake_px, shake_s)
	var stop_ms: float = row["hit_stop_ms"]
	if stop_ms > 0.0:
		hit_stop(stop_ms)
	Audio.play_sfx(row["sfx"] as StringName, Audio.DEFAULT_PITCH_JITTER, row["sfx_volume_db"] as float, row["sfx_pitch"] as float)


## Freezes time for ms milliseconds. Overlapping stops keep the longest remaining
## one; they never stack. Stale timers are ignored through the serial.
func hit_stop(ms: float) -> void:
	if ms <= 0.0:
		return
	var end_usec: int = Time.get_ticks_usec() + int(ms * 1000.0)
	if end_usec <= _hit_stop_end_usec:
		return
	_hit_stop_end_usec = end_usec
	_hit_stop_serial += 1
	Engine.time_scale = 0.0
	get_tree().create_timer(ms / 1000.0, true, false, true).timeout.connect(_end_hit_stop.bind(_hit_stop_serial))


func is_hit_stopped() -> bool:
	return _hit_stop_end_usec != 0


## Spawns one explosion per tier off-screen (shader and particle warm-up) with
## no shake, hit-stop or sound.
func prewarm() -> void:
	for row: Dictionary in _tiers:
		_spawn_explosion(row, PREWARM_POSITION)


## Ends any hit-stop at once; pending timers become stale.
func reset() -> void:
	_hit_stop_serial += 1
	_hit_stop_end_usec = 0
	Engine.time_scale = 1.0


func _spawn_explosion(row: Dictionary, position: Vector2) -> void:
	if _spawner == null or not is_instance_valid(_spawner):
		return
	_spawner.spawn_explosion({
		"position": position,
		"scale": row["explosion_scale"],
		"extras": row["extras"],
	})


func _end_hit_stop(serial: int) -> void:
	if serial != _hit_stop_serial:
		return
	_hit_stop_end_usec = 0
	Engine.time_scale = 1.0
