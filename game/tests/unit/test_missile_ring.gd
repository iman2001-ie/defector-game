extends GutTest
## MissileRing: the cooldown arc on the ship, driven only by Events.missile_cooldown_changed.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")


func _make_ring() -> MissileRing:
	var ring: MissileRing = MissileRing.new()
	add_child_autofree(ring)
	return ring


func test_fresh_ring_is_ready_and_hidden() -> void:
	var ring: MissileRing = _make_ring()
	assert_eq(ring.cooldown_ratio, 0.0)
	assert_false(ring.should_draw(), "nothing drawn when ready")


func test_ratio_follows_signal_clamped() -> void:
	var ring: MissileRing = _make_ring()
	var rows: Array[Array] = [[0.5, 0.5, true], [1.7, 1.0, true], [-0.2, 0.0, false], [0.0, 0.0, false]]
	for row: Array in rows:
		Events.missile_cooldown_changed.emit(row[0])
		assert_eq(ring.cooldown_ratio, row[1], "emit %s" % row[0])
		assert_eq(ring.should_draw(), row[2], "drawn for %s" % row[0])


func test_radius_and_stroke_from_config() -> void:
	var ring: MissileRing = _make_ring()
	assert_eq(ring.radius_px, Config.num("player.missile_ring.radius_px"))
	assert_eq(ring.stroke_px, Config.num("player.missile_ring.stroke_px"))
	# Operator-tuned data (first pass was 36 / 5); only the UX rules are fixed.
	assert_gt(ring.stroke_px, 0.0, "visible stroke")
	assert_true(Config.num("player.missile_ring.radius_px") <= Config.num("player.sprite_px") / 2.0,
		"tuned radius within the ship's half-size (no clamp needed)")


func test_oversized_radius_warns_and_clamps() -> void:
	var ring_tuning: Dictionary = Config.tuning["player"]["missile_ring"]
	var original: Variant = ring_tuning["radius_px"]
	ring_tuning["radius_px"] = 80
	var ring: MissileRing = _make_ring()
	ring_tuning["radius_px"] = original
	assert_push_warning("radius_px")
	assert_eq(ring.radius_px, Config.num("player.sprite_px") / 2.0, "clamped to half the ship")


func test_colour_constants_match_ux_tokens() -> void:
	assert_eq(MissileRing.STROKE_COLOR, Color("#E8F4FF"), "text")
	assert_eq(MissileRing.OUTLINE_COLOR, Color("#05070F"), "background")
	assert_eq(MissileRing.OUTLINE_PX, 2.0)


func test_sweep_is_clockwise_from_twelve() -> void:
	assert_eq(MissileRing.START_ANGLE, -PI / 2.0, "12 o'clock")
	assert_almost_eq(MissileRing.end_angle(0.25), 0.0, 0.0001, "a quarter sweeps to 3 o'clock")
	assert_almost_eq(MissileRing.end_angle(1.0), -PI / 2.0 + TAU, 0.0001, "full circle")


func test_player_scene_has_ring_above_sprite() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	var ring: Node = player.get_node_or_null(^"MissileRing")
	assert_true(ring is MissileRing, "Player/MissileRing is a MissileRing")
	if not ring is MissileRing:
		return
	var sprite: Sprite2D = player.get_node("Sprite") as Sprite2D
	assert_gt((ring as MissileRing).z_index, sprite.z_index, "drawn above the hull")
