extends GutTest
## EnergyOrb (Story 3.3): scene layers and group, sizes from tuning, drift,
## magnet pull (inclusive radius, no overshoot, ignores a dead ship), despawn,
## bottom exit and the one-shot collect. Driven through step() with physics off.

const ORB_SCENE: PackedScene = preload("res://entities/pickups/energy_orb.tscn")
const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")


func before_each() -> void:
	GameState.energy = 0
	watch_signals(Events)


func after_each() -> void:
	Config.load_data()
	GameState.energy = 0
	Feedback.reset()
	PauseArbiter.clear()


func _ignore_warp(_p: Vector2) -> void:
	pass


func _make_player(pos: Vector2) -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.warp_mouse = _ignore_warp
	add_child_autofree(player)
	player.set_physics_process(false)
	player.global_position = pos
	return player


func _make_orb(pos: Vector2 = Vector2(100, 100)) -> EnergyOrb:
	var orb: EnergyOrb = ORB_SCENE.instantiate() as EnergyOrb
	orb.setup({"position": pos})
	add_child_autofree(orb)
	orb.set_physics_process(false)
	return orb


func test_scene_layers_group_and_size() -> void:
	var orb: EnergyOrb = _make_orb()
	assert_eq(orb.collision_layer, CollisionLayers.PICKUPS)
	assert_eq(orb.collision_mask, 0)
	assert_true(orb.monitorable, "the player's hurtbox detects it")
	assert_true(orb.is_in_group(&"pickups"))
	var hitbox: CollisionShape2D = orb.get_node("Hitbox") as CollisionShape2D
	assert_true(hitbox.shape is CircleShape2D)
	if hitbox.shape is CircleShape2D:
		assert_eq((hitbox.shape as CircleShape2D).radius, Config.num("energy.orb_diameter_px") / 2.0)
	var sprite: Sprite2D = orb.get_node("Sprite") as Sprite2D
	assert_eq(sprite.texture.get_width(), Config.int_("energy.orb_diameter_px"))
	assert_eq(sprite.texture.get_height(), Config.int_("energy.orb_diameter_px"))
	var material: CanvasItemMaterial = sprite.material as CanvasItemMaterial
	assert_not_null(material, "additive material")
	if material != null:
		assert_eq(material.blend_mode, CanvasItemMaterial.BLEND_MODE_ADD)
	var gradient: Gradient = (sprite.texture as GradientTexture2D).gradient
	assert_true(gradient.get_color(1).is_equal_approx(Color("#FFD23F")), "gold body")


func test_setup_stores_and_ready_applies() -> void:
	var orb: EnergyOrb = ORB_SCENE.instantiate() as EnergyOrb
	orb.setup({"position": Vector2(300, 200)})
	assert_eq(orb.position, Vector2.ZERO, "setup does not apply the position")
	add_child_autofree(orb)
	orb.set_physics_process(false)
	assert_eq(orb.global_position, Vector2(300, 200))
	assert_eq(orb.value, 10)
	assert_eq(orb.drift_speed, 120.0)
	assert_eq(orb.magnet_radius, 160.0)
	assert_eq(orb.magnet_speed, 600.0)
	assert_eq(orb.despawn_s, 6.0)


func test_drift_without_a_player() -> void:
	var orb: EnergyOrb = _make_orb(Vector2(100, 100))
	orb.step(0.5)
	assert_eq(orb.global_position, Vector2(100, 160))


func test_magnet_at_the_radius_pulls_toward_the_ship() -> void:
	_make_player(Vector2(100, 260))
	var orb: EnergyOrb = _make_orb(Vector2(100, 100))
	assert_true(orb.is_magnet_target_in_range(), "160 px is inside (inclusive)")
	orb.step(0.1)
	assert_almost_eq(orb.global_position.y, 160.0, 0.001, "600 px/s toward the ship")
	assert_almost_eq(orb.global_position.x, 100.0, 0.001)


func test_magnet_never_overshoots() -> void:
	var player: Player = _make_player(Vector2(200, 300))
	var orb: EnergyOrb = _make_orb(Vector2(200 + 60, 300 + 80))
	orb.step(1.0)
	assert_eq(orb.global_position, player.global_position, "stops on the ship")


func test_outside_the_radius_drifts() -> void:
	_make_player(Vector2(100, 261))
	var orb: EnergyOrb = _make_orb(Vector2(100, 100))
	assert_false(orb.is_magnet_target_in_range(), "161 px is outside")
	orb.step(0.5)
	assert_eq(orb.global_position, Vector2(100, 160), "drifts down")


func test_a_dead_ship_does_not_pull() -> void:
	var player: Player = _make_player(Vector2(100, 200))
	player.apply_damage(player.hearts, null)
	Feedback.reset()
	assert_true(player.is_dead())
	var orb: EnergyOrb = _make_orb(Vector2(100, 100))
	orb.step(0.5)
	assert_eq(orb.global_position, Vector2(100, 160), "drifts down")


func test_a_freed_ship_does_not_pull() -> void:
	var player: Player = _make_player(Vector2(100, 200))
	var orb: EnergyOrb = _make_orb(Vector2(100, 100))
	player.free()
	orb.step(0.5)
	assert_eq(orb.global_position, Vector2(100, 160), "drifts down")


func test_despawns_after_six_seconds_without_energy() -> void:
	var orb: EnergyOrb = _make_orb(Vector2(100, 100))
	orb.step(5.9)
	assert_false(orb.is_queued_for_deletion(), "alive at 5.9 s")
	orb.step(0.1)
	assert_true(orb.is_queued_for_deletion(), "freed at 6.0 s")
	assert_eq(GameState.energy, 0, "no energy")
	assert_signal_not_emitted(Events, "energy_changed")


func test_despawn_counts_small_physics_steps() -> void:
	var orb: EnergyOrb = _make_orb(Vector2(100, -10000))
	for i: int in 359:
		orb.step(1.0 / 60.0)
	assert_false(orb.is_queued_for_deletion(), "alive before 6 s")
	orb.step(1.0 / 60.0)
	orb.step(1.0 / 60.0)
	assert_true(orb.is_queued_for_deletion(), "freed at 6 s")


func test_freed_once_fully_below_the_playfield() -> void:
	var radius: float = Config.num("energy.orb_diameter_px") / 2.0
	var orb: EnergyOrb = _make_orb(Vector2(100, Playfield.SIZE.y + radius - 1.0))
	orb.step(0.001)
	assert_false(orb.is_queued_for_deletion(), "still partly on screen")
	orb.step(0.1)
	assert_true(orb.is_queued_for_deletion(), "fully below the playfield")


func test_collect_adds_energy_once() -> void:
	var orb: EnergyOrb = _make_orb()
	assert_true(orb.collect())
	assert_eq(GameState.energy, 10)
	assert_signal_emitted_with_parameters(Events, "energy_changed", [10, 100])
	assert_true(orb.is_queued_for_deletion())
	var player: AudioStreamPlayer = Audio.newest_player()
	assert_not_null(player)
	if player != null:
		assert_eq(player.stream, Audio.SFX[&"energy_pickup"], "energy_pickup played")
	assert_false(orb.collect(), "second collect refused")
	assert_eq(GameState.energy, 10, "+10 once")
	assert_signal_emit_count(Events, "energy_changed", 1)


func test_collect_at_the_cap() -> void:
	GameState.energy = 95
	var orb: EnergyOrb = _make_orb()
	assert_true(orb.collect())
	assert_eq(GameState.energy, 100)
	assert_signal_emitted_with_parameters(Events, "energy_changed", [100, 100])


func test_step_after_collect_does_nothing() -> void:
	var orb: EnergyOrb = _make_orb(Vector2(100, 100))
	orb.collect()
	orb.step(0.5)
	assert_eq(orb.global_position, Vector2(100, 100))


func test_a_negative_magnet_radius_never_pulls() -> void:
	(Config.tuning["energy"] as Dictionary)["orb_magnet_radius_px"] = -500
	_make_player(Vector2(100, 200))
	var orb: EnergyOrb = _make_orb(Vector2(100, 100))
	assert_eq(orb.magnet_radius, 0.0, "clamped at 0")
	assert_false(orb.is_magnet_target_in_range())
	orb.step(0.5)
	assert_eq(orb.global_position, Vector2(100, 160), "drifts down")
