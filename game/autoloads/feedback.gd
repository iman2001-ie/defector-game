extends Node
## Impact feedback (Pillar 2): one call per hit or death scales the explosion,
## camera shake, hit-stop and SFX with the impact tier. Tier rows come from
## tuning.feedback.tiers (read once in load_tiers()).
##
## The only owner of Engine.time_scale (hit-stop). Scene nodes register
## themselves: the level's ShakeCamera and Spawner.
##
## Boss death (Story 7.5): boss_death(pos) plays the Flagship's chain, one
## Boss-death explosion per feedback.boss_death_chain_offsets_px entry at
## pos + offset, spread evenly over feedback.boss_death_chain_s (explosion k at
## k * chain_s / (N - 1); a single entry plays at once). Explosion 0 is a full
## impact (its extras, shake, hit-stop and sfx) inside the call; each later one
## is only its explosion (no extras) plus the tier sfx. The pending ones advance
## in step_chain(delta), which _process calls with game-time delta only while
## the tree isn't paused; reset() drops them. No per-frame allocation.

## Where prewarm() spawns its explosions: off-screen left, vertically centred.
const PREWARM_POSITION: Vector2 = Vector2(-1000, 540)
## The screen-space extra prewarm() leaves out (it has nothing to warm up and
## would flash the whole screen).
const PREWARM_SKIPPED_EXTRA: StringName = &"white_flash"
## Slack for the chain's float steps (120 steps of 1/60 s reach 2.0 s).
const CHAIN_EPSILON_S: float = 0.0001

## One cached row per tier, indexed by ImpactTier.
var _tiers: Array[Dictionary] = []
var _camera: ShakeCamera = null
var _spawner: Spawner = null
var _hit_stop_end_usec: int = 0
var _hit_stop_serial: int = 0
## feedback.boss_death_chain_s and feedback.boss_death_chain_offsets_px, cached
## in load_tiers().
var _chain_s: float = 0.0
var _chain_offsets: PackedVector2Array = PackedVector2Array()
## The pending chain: one position and start time per explosion; _chain_next
## is the next one to play (== size when none is pending).
var _chain_positions: PackedVector2Array = PackedVector2Array()
var _chain_times: PackedFloat32Array = PackedFloat32Array()
var _chain_next: int = 0
var _chain_t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_tiers()


func _process(delta: float) -> void:
	if _chain_next < _chain_positions.size() and not get_tree().paused:
		step_chain(delta)


## Reads every tier row from tuning (missing keys log through Config), and the
## boss-death chain's duration and offsets.
func load_tiers() -> void:
	_load_chain()
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
	_shake(row)
	var stop_ms: float = row["hit_stop_ms"]
	if stop_ms > 0.0:
		hit_stop(stop_ms)
	_play_sfx(row)


## Shakes the registered camera with the tier's shake_px / shake_s only: no
## explosion, hit-stop or SFX (Story 5.4, a comms cut-off). An unknown tier logs
## an error and does nothing; with no camera it does nothing.
func shake_tier(tier: int) -> void:
	if tier < 0 or tier >= _tiers.size():
		Log.error("combat", "Feedback.shake_tier: unknown tier %d" % tier)
		return
	_shake(_tiers[tier])


## Shakes the registered camera by `px` pixels for `s` seconds only: no
## explosion, hit-stop or SFX (the comms cut-off's own shake, GDD decision #43).
## A no-op when either value isn't above 0 or no camera is registered.
func shake(px: float, s: float) -> void:
	if _camera != null and is_instance_valid(_camera) and px > 0.0 and s > 0.0:
		_camera.shake(px, s)


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
## no shake, hit-stop or sound, and without the screen-space white flash.
func prewarm() -> void:
	for row: Dictionary in _tiers:
		var extras: Array[StringName] = (row["extras"] as Array[StringName]).duplicate()
		extras.erase(PREWARM_SKIPPED_EXTRA)
		_spawn_explosion_with(row, PREWARM_POSITION, extras)


## The Flagship's death (Story 7.5): explosion 0 of the chain plays now as a full
## Boss-death impact at pos + offsets[0]; the rest are queued for step_chain at
## k * chain_s / (N - 1). A new call replaces a chain still pending. Without
## offsets it logs an error and plays the single impact at pos.
func boss_death(pos: Vector2) -> void:
	var count: int = _chain_offsets.size()
	if count == 0:
		Log.error("combat", "feedback.boss_death_chain_offsets_px is empty; one boss_death impact instead")
		impact(ImpactTier.BOSS_DEATH, pos)
		return
	_chain_positions.resize(count)
	_chain_times.resize(count)
	for k: int in count:
		_chain_positions[k] = pos + _chain_offsets[k]
		_chain_times[k] = 0.0 if count == 1 else float(k) * _chain_s / float(count - 1)
	_chain_t = 0.0
	_chain_next = 1
	impact(ImpactTier.BOSS_DEATH, _chain_positions[0])


## Advances the pending boss-death chain by `delta` seconds of game time: each
## explosion whose time has come plays (the Boss-death scale, no extras) with
## the tier sfx. Does nothing when no chain is pending.
func step_chain(delta: float) -> void:
	if _chain_next >= _chain_positions.size():
		return
	_chain_t += delta
	var row: Dictionary = _tiers[ImpactTier.BOSS_DEATH]
	while _chain_next < _chain_positions.size() and _chain_t + CHAIN_EPSILON_S >= _chain_times[_chain_next]:
		_spawn_explosion_with(row, _chain_positions[_chain_next], [])
		_play_sfx(row)
		_chain_next += 1


## Explosions of the boss-death chain still to play (tests, F1).
func chain_pending() -> int:
	return maxi(_chain_positions.size() - _chain_next, 0)


## Ends any hit-stop at once; pending timers become stale. Drops a pending
## boss-death chain.
func reset() -> void:
	_hit_stop_serial += 1
	_hit_stop_end_usec = 0
	Engine.time_scale = 1.0
	_chain_next = _chain_positions.size()


## Shakes the registered camera with the row's shake_px / shake_s (see shake).
func _shake(row: Dictionary) -> void:
	shake(row["shake_px"] as float, row["shake_s"] as float)


func _play_sfx(row: Dictionary) -> void:
	Audio.play_sfx(row["sfx"] as StringName, Audio.DEFAULT_PITCH_JITTER, row["sfx_volume_db"] as float, row["sfx_pitch"] as float)


func _spawn_explosion(row: Dictionary, position: Vector2) -> void:
	_spawn_explosion_with(row, position, row["extras"] as Array)


## Spawns one explosion at the row's scale with the given extras; nothing
## without a registered spawner.
func _spawn_explosion_with(row: Dictionary, position: Vector2, extras: Array) -> void:
	if _spawner == null or not is_instance_valid(_spawner):
		return
	_spawner.spawn_explosion({
		"position": position,
		"scale": row["explosion_scale"],
		"extras": extras,
	})


## Caches feedback.boss_death_chain_s and the chain offsets (each a [x, y]
## pair; a malformed entry logs an error and is skipped) and drops a pending
## chain.
func _load_chain() -> void:
	_chain_s = maxf(Config.num("feedback.boss_death_chain_s"), 0.0)
	_chain_offsets.clear()
	var raw: Variant = Config.section("feedback").get("boss_death_chain_offsets_px")
	if not (raw is Array):
		Log.error("data", "feedback.boss_death_chain_offsets_px missing or not an array")
	else:
		for entry: Variant in raw as Array:
			var pair: Array = entry as Array if entry is Array else []
			if pair.size() != 2 or not ((pair[0] is float or pair[0] is int) and (pair[1] is float or pair[1] is int)):
				Log.error("data", "feedback.boss_death_chain_offsets_px entry %s is not an [x, y] pair; skipped" % str(entry))
				continue
			_chain_offsets.append(Vector2(float(pair[0]), float(pair[1])))
	_chain_positions.clear()
	_chain_times.clear()
	_chain_next = 0


func _end_hit_stop(serial: int) -> void:
	if serial != _hit_stop_serial:
		return
	_hit_stop_end_usec = 0
	Engine.time_scale = 1.0
