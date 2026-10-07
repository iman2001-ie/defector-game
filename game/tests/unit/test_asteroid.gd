extends GutTest
## Asteroid: per-size tuning, drift and spin, bottom exit, destruction, scene layers.

const ASTEROID_SCENE: PackedScene = preload("res://entities/asteroids/asteroid.tscn")
const DT: float = 1.0 / 60.0
const EXPECTED: Dictionary = {
	&"small": {"diameter": 64.0, "hp": 4, "drift": 140.0},
	&"medium": {"diameter": 128.0, "hp": 12, "drift": 100.0},
	&"large": {"diameter": 224.0, "hp": 30, "drift": 60.0},
}


func before_each() -> void:
	watch_signals(Events)


func after_each() -> void:
	Feedback.reset()


func _make(size: StringName, pos: Vector2 = Vector2(960, 400)) -> Asteroid:
	var rock: Asteroid = ASTEROID_SCENE.instantiate() as Asteroid
	rock.setup({"size": size, "position": pos})
	add_child_autofree(rock)
	rock.set_physics_process(false)
	return rock


func _hitbox_radius(rock: Asteroid) -> float:
	var hitbox: CollisionShape2D = rock.get_node_or_null("Hitbox") as CollisionShape2D
	if hitbox == null or not (hitbox.shape is CircleShape2D):
		return -1.0
	return (hitbox.shape as CircleShape2D).radius


func test_sizes_match_tuning() -> void:
	assert_eq(Asteroid.SIZES, [&"small", &"medium", &"large"] as Array[StringName])
	for size: StringName in EXPECTED:
		var row: Dictionary = EXPECTED[size]
		var rock: Asteroid = _make(size)
		assert_eq(rock.size, size)
		assert_eq(rock.radius, (row.diameter as float) / 2.0, "%s radius" % size)
		assert_eq(_hitbox_radius(rock), (row.diameter as float) / 2.0, "%s hitbox radius" % size)
		assert_eq(rock.hp, row.hp as int, "%s hp" % size)
		assert_eq(rock.drift_speed, row.drift as float, "%s drift" % size)
		assert_between(absf(rock.spin_deg_s), 10.0, 40.0, "%s spin" % size)
		var visual: Node2D = rock.get_node("Visual") as Node2D
		assert_eq(visual.scale, Vector2.ONE * (row.diameter as float) / 2.0, "%s visual spans the diameter" % size)
		var rim: Line2D = visual.get_node("Rim") as Line2D
		assert_almost_eq(rim.width * rock.radius, Asteroid.RIM_WIDTH_PX, 0.0001, "%s rim width on screen" % size)


func test_placeholder_is_jagged() -> void:
	var rock: Asteroid = _make(&"medium")
	var body: Polygon2D = rock.get_node("Visual/Body") as Polygon2D
	var rim: Line2D = rock.get_node("Visual/Rim") as Line2D
	assert_gte(body.polygon.size(), 9, "at least 9 points")
	assert_true(rim.closed, "rim closed")
	var radii: Array[float] = []
	for p: Vector2 in body.polygon:
		radii.append(p.length())
	assert_almost_eq(radii.max() as float, 1.0, 0.001, "unit radius")
	assert_lt(radii.min() as float, 0.9, "irregular, not round")


func test_spin_has_both_signs() -> void:
	var signs: Dictionary = {}
	for i: int in 40:
		var rock: Asteroid = _make(&"small")
		signs[signf(rock.spin_deg_s)] = true
	assert_true(signs.has(1.0) and signs.has(-1.0), "spin sign is random")


func test_drift_step() -> void:
	var rock: Asteroid = _make(&"medium", Vector2(500, 300))
	var rot_before: float = rock.rotation_degrees
	rock._physics_process(DT)
	assert_almost_eq(rock.global_position.y, 300.0 + 100.0 / 60.0, 0.0001)
	assert_eq(rock.global_position.x, 500.0, "x unchanged")
	assert_almost_eq(rock.rotation_degrees - rot_before, rock.spin_deg_s * DT, 0.0001)


func test_break_emits_once_and_never_splits() -> void:
	var rock: Asteroid = _make(&"small", Vector2(700, 400))
	var parent: Node = rock.get_parent()
	var children_before: int = parent.get_child_count()
	for i: int in 3:
		rock.apply_damage(1, null)
	assert_signal_not_emitted(Events, "asteroid_destroyed")
	rock.apply_damage(1, null)
	rock.apply_damage(1, null)
	assert_signal_emit_count(Events, "asteroid_destroyed", 1)
	assert_signal_emitted_with_parameters(Events, "asteroid_destroyed", [&"small", Vector2(700, 400)])
	assert_true(rock.is_queued_for_deletion())
	assert_eq(parent.get_child_count(), children_before, "no new asteroid")
	assert_eq(get_tree().get_nodes_in_group(&"asteroids").size(), 1, "only the dying one")


func test_bottom_exit_frees_without_event() -> void:
	var rock: Asteroid = _make(&"large")
	rock.global_position = Vector2(960, 1080.0 + rock.radius + 1.0)
	rock._physics_process(DT)
	assert_true(rock.is_queued_for_deletion())
	assert_signal_not_emitted(Events, "asteroid_destroyed")


func test_partly_visible_survives() -> void:
	var rock: Asteroid = _make(&"large")
	rock.global_position = Vector2(960, 1080.0 + rock.radius - 10.0)
	rock._physics_process(DT)
	assert_false(rock.is_queued_for_deletion())


func test_scene_contract() -> void:
	var rock: Asteroid = _make(&"small")
	assert_eq(rock.collision_layer, CollisionLayers.ASTEROIDS)
	assert_eq(rock.collision_mask, 0)
	assert_false(rock.monitoring)
	assert_true(rock.monitorable)
	assert_true(rock.is_in_group(&"asteroids"))
