extends GutTest
## Player death (Story 3.2): the lethal hit plays the PLAYER_DEATH tier (not
## PLAYER_HIT), emits player_died then level_failed(&"hearts") once, logs once,
## and leaves the ship hidden and inert: no more damage, contact, collision,
## i-frames, lock or fire. Driven with physics processing off.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")
const WASP_SCENE: PackedScene = preload("res://entities/enemies/wasp/wasp.tscn")
const BASTION_SCENE: PackedScene = preload("res://entities/enemies/bastion/bastion.tscn")
const ASTEROID_SCENE: PackedScene = preload("res://entities/asteroids/asteroid.tscn")
const DT: float = 1.0 / 60.0
## Far from the player, so no real overlap fires.
const HAZARD_POS: Vector2 = Vector2(1500, 150)

var _player: Player
var _camera: ShakeCamera
var _lines: Array[String] = []
## Events in the order they fired.
var _order: Array[String] = []
var _failed_reasons: Array[StringName] = []
var _warps: Array[Vector2] = []


func before_each() -> void:
	_lines.clear()
	_order.clear()
	_failed_reasons.clear()
	_warps.clear()
	Log.sink = _capture
	watch_signals(Events)
	Events.player_hit.connect(_on_player_hit)
	Events.player_died.connect(_on_player_died)
	Events.level_failed.connect(_on_level_failed)
	_camera = ShakeCamera.new()
	add_child_autofree(_camera)
	_camera.set_process(false)
	_player = PLAYER_SCENE.instantiate() as Player
	_player.warp_mouse = _record_warp
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.global_position = Vector2(200, 900)


func after_each() -> void:
	Events.player_hit.disconnect(_on_player_hit)
	Events.player_died.disconnect(_on_player_died)
	Events.level_failed.disconnect(_on_level_failed)
	Log.sink = Callable()
	Feedback.reset()
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_player = null
	_camera = null


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _record_warp(p: Vector2) -> void:
	_warps.append(p)


func _on_player_hit(_pos: Vector2) -> void:
	_order.append("player_hit")


func _on_player_died() -> void:
	_order.append("player_died")


func _on_level_failed(reason: StringName) -> void:
	_order.append("level_failed")
	_failed_reasons.append(reason)


func _logged(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.begins_with(prefix):
			out.append(line)
	return out


func _wasp() -> Wasp:
	var wasp: Wasp = WASP_SCENE.instantiate() as Wasp
	wasp.setup({"position": HAZARD_POS})
	add_child_autofree(wasp)
	wasp.set_physics_process(false)
	return wasp


func _bastion() -> Bastion:
	var bastion: Bastion = BASTION_SCENE.instantiate() as Bastion
	bastion.setup({"position": HAZARD_POS})
	add_child_autofree(bastion)
	bastion.set_physics_process(false)
	return bastion


func _kill() -> void:
	_player.hearts = 1
	_player.apply_damage(1, null)


# --- Lethal hit -------------------------------------------------------------------

func test_alive_at_start() -> void:
	assert_false(_player.is_dead())
	assert_true(_player.visible)


func test_non_lethal_hit_does_not_kill() -> void:
	_player.apply_damage(1, null)
	assert_false(_player.is_dead())
	assert_signal_not_emitted(Events, "player_died")
	assert_signal_not_emitted(Events, "level_failed")


func test_lethal_hit_emits_once_in_order() -> void:
	_kill()
	assert_eq(_player.hearts, 0)
	assert_true(_player.is_dead())
	assert_signal_emit_count(Events, "hearts_changed", 1)
	assert_signal_emitted_with_parameters(Events, "hearts_changed", [0, 5])
	assert_signal_emit_count(Events, "player_hit", 1, "the vignette still fires")
	assert_signal_emit_count(Events, "player_died", 1)
	assert_signal_emit_count(Events, "level_failed", 1)
	assert_eq(_failed_reasons, [&"hearts"] as Array[StringName])
	assert_eq(_order, ["player_hit", "player_died", "level_failed"] as Array[String])


func test_lethal_hit_plays_the_player_death_tier() -> void:
	_kill()
	var death_px: float = Config.num("feedback.tiers.player_death.shake_px")
	assert_eq(death_px, 12.0)
	assert_almost_eq(_camera.current_amplitude(), death_px, 0.0001, "PLAYER_DEATH shake (12 px), not PLAYER_HIT (6 px)")
	assert_true(Feedback.is_hit_stopped(), "death hit-stop")


func test_player_death_sfx_is_registered() -> void:
	_kill()
	assert_eq(_logged("[WARN][audio]"), [] as Array[String], "no unknown sfx warning")
	assert_true(Audio.SFX.get(&"player_death") is AudioStream)
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"player_death"])


func test_lethal_hit_logs_once() -> void:
	_kill()
	_player.apply_damage(1, null)
	assert_eq(_logged("[INFO][combat]").size(), 1, "one INFO line")
	assert_false(_logged("[INFO][combat]")[0].contains("no more damage"), "not the Story 3.1 line")


func test_dead_ship_is_hidden_and_inert() -> void:
	_kill()
	assert_false(_player.visible, "ship hidden (MissileRing too)")
	assert_false(_player.is_invulnerable(), "no i-frames after death")
	await wait_physics_frames(2)
	assert_false(_player.monitoring, "monitoring off")
	assert_false(_player.monitorable, "monitorable off")


func test_dead_ship_skips_the_physics_tick() -> void:
	_kill()
	var before: Vector2 = _player.global_position
	_warps.clear()
	_player._physics_process(DT)
	assert_eq(_player.global_position, before, "no lock after death")
	assert_eq(_warps, [] as Array[Vector2], "no warp after death")


func test_overkill_contact_kills_and_bastion_survives() -> void:
	_player.hearts = 1
	var bastion: Bastion = _bastion()
	_player.on_contact(bastion)
	assert_eq(_player.hearts, 0)
	assert_true(_player.is_dead())
	assert_false(bastion.is_dead(), "Bastion alive")
	assert_signal_emit_count(Events, "player_died", 1)
	assert_signal_emit_count(Events, "level_failed", 1)
	assert_almost_eq(_camera.current_amplitude(), 12.0, 0.0001, "PLAYER_DEATH tier")


# --- After death ------------------------------------------------------------------

func test_hits_after_death_do_nothing() -> void:
	_kill()
	Feedback.reset()
	_player.apply_damage(1, null)
	assert_signal_emit_count(Events, "hearts_changed", 1, "no second hearts_changed")
	assert_signal_emit_count(Events, "player_hit", 1)
	assert_signal_emit_count(Events, "player_died", 1)
	assert_signal_emit_count(Events, "level_failed", 1)
	assert_false(Feedback.is_hit_stopped(), "no feedback")


func test_contact_after_death_does_nothing() -> void:
	_kill()
	var wasp: Wasp = _wasp()
	_player.on_contact(wasp)
	assert_false(wasp.is_dead(), "small enemy not destroyed")
	assert_signal_emit_count(Events, "player_hit", 1)
	assert_signal_emit_count(Events, "level_failed", 1)


func test_debug_invincible_off_after_death_does_nothing() -> void:
	_player.hearts = 1
	_player.debug_invincible = true
	var rock: Asteroid = ASTEROID_SCENE.instantiate() as Asteroid
	rock.setup({"size": &"large", "position": HAZARD_POS})
	add_child_autofree(rock)
	rock.set_physics_process(false)
	_player.on_contact(rock)
	assert_false(_player.is_dead(), "invincible: no damage")
	_player.debug_invincible = false
	assert_true(_player.is_dead(), "the remembered asteroid kills on invincibility off")
	_player.debug_invincible = true
	_player.debug_invincible = false
	assert_signal_emit_count(Events, "player_died", 1)
	assert_signal_emit_count(Events, "level_failed", 1)
	assert_signal_emit_count(Events, "player_hit", 1)
