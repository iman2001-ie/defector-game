extends GutTest
## Asteroid: per-size tuning, drift and spin, bottom exit, destruction, scene
## layers; death drops through Loot (Story 3.3).

const SpriteProbe: GDScript = preload("res://tests/fixtures/sprite_probe.gd")
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
	Config.load_data()
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
		var sprite: Sprite2D = rock.get_node("Visual/Sprite") as Sprite2D
		assert_eq(sprite.texture.resource_path, "res://assets/sprites/asteroids/asteroid_%s.png" % size, "%s meteor" % size)
		assert_almost_eq(SpriteProbe.longest_side(sprite), row.diameter as float, 1.0, "%s sprite spans the diameter" % size)
		assert_eq((rock.get_node("Visual") as Node2D).scale, Vector2.ONE, "%s visual unscaled" % size)


## Story 8.2: the meteors are recoloured to `hazard` grey-brown with a
## `hazardRim` rim light baked on the upper-left edge (jagged Kenney meteors,
## never round), and the placeholder polygons are gone.
func test_meteor_art_is_hazard_with_a_rim_light() -> void:
	var rock: Asteroid = _make(&"medium")
	assert_null(rock.get_node_or_null("Visual/Body"), "no placeholder body")
	assert_null(rock.get_node_or_null("Visual/Rim"), "no placeholder rim")
	for size: StringName in Asteroid.SIZES:
		var tex: Texture2D = Asteroid.TEXTURES[size]
		assert_not_null(tex, "%s texture" % size)
		var image: Image = tex.get_image()
		var hazard: Color = Color("#7A6E62")
		var rim: Color = Color("#C9D8E8")
		var hazard_like: int = 0
		var rim_like: int = 0
		var opaque: int = 0
		for y: int in image.get_height():
			for x: int in image.get_width():
				var c: Color = image.get_pixel(x, y)
				if c.a < 0.999:
					continue
				opaque += 1
				if absf(c.h - hazard.h) < 0.06 and c.s < 0.4:
					hazard_like += 1
				if c.b > c.r and c.v > hazard.v:
					rim_like += 1
		assert_gt(float(hazard_like), float(opaque) / 3.0, "%s body is hazard grey-brown" % size)
		assert_gt(rim_like, 0, "%s has a cool rim light (%s)" % [size, rim])
		assert_lt(opaque, image.get_width() * image.get_height(), "%s is not a filled square" % size)


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


# --- Death drops (Story 3.3) -------------------------------------------------------


## A World with the entity containers and Pickups, plus its Spawner.
func _drop_world() -> Spawner:
	var world: Node2D = Node2D.new()
	for container: String in ["Projectiles", "Enemies", "Asteroids", "Pickups"]:
		var node: Node2D = Node2D.new()
		node.name = container
		world.add_child(node)
	add_child_autofree(world)
	var spawner: Spawner = Spawner.new()
	spawner.world = world
	add_child_autofree(spawner)
	return spawner


## The orb started at `at`: x exact; y at most a frame's physics drift below it.
func _assert_dropped_at(orb: EnergyOrb, at: Vector2) -> void:
	assert_eq(orb.global_position.x, at.x)
	assert_between(orb.global_position.y, at.y, at.y + 40.0, "spawned at the point, then drifted down")


func _orbs(spawner: Spawner) -> Array[EnergyOrb]:
	var out: Array[EnergyOrb] = []
	for child: Node in spawner.world.get_node("Pickups").get_children():
		if child is EnergyOrb:
			(child as EnergyOrb).set_physics_process(false)
			out.append(child as EnergyOrb)
	return out


func _set_chance(size: StringName, chance: float) -> void:
	((Config.tuning["drops"] as Dictionary)["asteroid_%s" % size] as Dictionary)["chance"] = chance


## `size`'s row always drops and every other size's row never does, so a rock
## that reads the wrong row drops nothing.
func _only_size_drops(size: StringName) -> void:
	for other: StringName in Asteroid.SIZES:
		_set_chance(other, 1.0 if other == size else 0.0)


func test_destroyed_asteroid_drops_by_size() -> void:
	for size: StringName in Asteroid.SIZES:
		var spawner: Spawner = _drop_world()
		_only_size_drops(size)
		var rock: Asteroid = spawner.spawn_asteroid({"size": size, "position": Vector2(700, 300)})
		rock.set_physics_process(false)
		rock.apply_damage(999, null)
		Feedback.reset()
		await wait_process_frames(1)
		var orbs: Array[EnergyOrb] = _orbs(spawner)
		assert_eq(orbs.size(), 1, "%s drops one orb" % size)
		if orbs.size() == 1:
			_assert_dropped_at(orbs[0], Vector2(700, 300))


func test_missed_roll_drops_nothing() -> void:
	var spawner: Spawner = _drop_world()
	for size: StringName in Asteroid.SIZES:
		_set_chance(size, 0.0)
	var rock: Asteroid = spawner.spawn_asteroid({"size": &"large", "position": Vector2(700, 300)})
	rock.set_physics_process(false)
	rock.apply_damage(999, null)
	Feedback.reset()
	await wait_process_frames(1)
	assert_eq(_orbs(spawner).size(), 0)


func test_asteroid_without_spawner_drops_nothing() -> void:
	_set_chance(&"small", 1.0)
	var rock: Asteroid = _make(&"small")
	assert_null(rock.spawner)
	rock.apply_damage(999, null)
	await wait_process_frames(1)
	assert_eq(get_tree().get_nodes_in_group(&"pickups").size(), 0)
