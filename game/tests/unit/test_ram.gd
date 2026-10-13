extends GutTest
## Ram (Tarek's fall, Epic 7 playtest D): a visual-only story prop. setup()
## reads from / to / travel_s / scale (bad values fall back), it starts at
## `from` scaled, its nose (local +y) points along the dive, it moves in a
## straight line at a constant speed, reaches `to` exactly at travel_s,
## emits `arrived` once and frees itself; travel_s 0 arrives on the first
## step. Driven through step() with physics off.

const RAM_SCENE: PackedScene = preload("res://entities/story/ram.tscn")
const FROM: Vector2 = Vector2(900, -150)
const TO: Vector2 = Vector2(900, 750)
## An exact binary fraction: four steps make the 0.5 s flight exactly.
const STEP: float = 0.125

var _arrivals: int = 0


func before_each() -> void:
	_arrivals = 0


func _on_arrived() -> void:
	_arrivals += 1


## A Ram set up with `params`, in the tree with physics off and `arrived` counted.
func _make(params: Dictionary) -> Ram:
	var ram: Ram = RAM_SCENE.instantiate() as Ram
	ram.setup(params)
	ram.arrived.connect(_on_arrived)
	add_child_autofree(ram)
	ram.set_physics_process(false)
	return ram


func test_setup_reads_the_params() -> void:
	var ram: Ram = RAM_SCENE.instantiate() as Ram
	ram.setup({"from": FROM, "to": TO, "travel_s": 0.45, "scale": 1.5})
	assert_eq(ram.from, FROM)
	assert_eq(ram.to, TO)
	assert_eq(ram.travel_s, 0.45)
	assert_eq(ram.size_scale, 1.5)
	ram.free()


func test_setup_falls_back_on_bad_values() -> void:
	var ram: Ram = RAM_SCENE.instantiate() as Ram
	ram.setup({"from": "top", "to": 3, "travel_s": "fast", "scale": null})
	assert_eq(ram.from, Vector2.ZERO, "a non-Vector2 from is ignored")
	assert_eq(ram.to, Vector2.ZERO, "a non-Vector2 to is ignored")
	assert_eq(ram.travel_s, 0.0, "a non-number travel_s is 0")
	assert_eq(ram.size_scale, 1.0, "a non-number scale is 1")
	ram.setup({"travel_s": -2, "scale": 0})
	assert_eq(ram.travel_s, 0.0, "a negative travel_s clamps to 0")
	assert_eq(ram.size_scale, 0.01, "the scale has a floor")
	ram.free()


func test_scene_is_visual_only() -> void:
	var ram: Ram = RAM_SCENE.instantiate() as Ram
	assert_false((ram as Node) is CollisionObject2D, "no collision body")
	assert_eq(ram.find_children("*", "CollisionObject2D", true, false).size(), 0, "no collision child")
	assert_eq(ram.find_children("*", "CollisionShape2D", true, false).size(), 0, "no collision shape")
	assert_true(ram.get_node_or_null("Hull") is Polygon2D, "a hull polygon")
	ram.free()


func test_starts_at_from_scaled() -> void:
	var ram: Ram = _make({"from": FROM, "to": TO, "travel_s": 0.5, "scale": 1.5})
	assert_eq(ram.global_position, FROM)
	assert_eq(ram.scale, Vector2(1.5, 1.5))
	assert_false(ram.has_arrived())
	assert_false(ram.is_in_group(Groups.ENEMIES), "never an enemy")


func test_nose_points_along_the_dive() -> void:
	for target: Vector2 in [TO, Vector2(400, 600), Vector2(1500, 300)]:
		var ram: Ram = _make({"from": FROM, "to": target, "travel_s": 0.5})
		var nose: Vector2 = (ram.to_global(Vector2(0, 1)) - ram.global_position).normalized()
		assert_almost_eq(nose, (target - FROM).normalized(), Vector2(0.0001, 0.0001), "nose toward %s" % target)


func test_straight_line_at_constant_speed_and_arrives_exactly_at_travel_s() -> void:
	var ram: Ram = _make({"from": FROM, "to": Vector2(1300, 650), "travel_s": 0.5})
	var target: Vector2 = Vector2(1300, 650)
	for k: int in range(1, 4):
		ram.step(STEP)
		assert_almost_eq(ram.global_position, FROM.lerp(target, float(k) / 4.0), Vector2(0.001, 0.001), "a quarter more at step %d" % k)
		assert_false(ram.has_arrived(), "not there at step %d" % k)
		assert_eq(_arrivals, 0)
	ram.step(STEP)
	assert_eq(ram.global_position, target, "exactly at `to` after travel_s")
	assert_true(ram.has_arrived())
	assert_eq(_arrivals, 1, "arrived once")
	assert_true(ram.is_queued_for_deletion(), "frees itself")


func test_arrived_only_once() -> void:
	var ram: Ram = _make({"from": FROM, "to": TO, "travel_s": 0.25})
	ram.step(1.0)
	assert_eq(_arrivals, 1, "an overshooting step arrives once")
	assert_eq(ram.global_position, TO, "clamped at `to`")
	ram.step(STEP)
	ram.step(1.0)
	assert_eq(_arrivals, 1, "later steps emit nothing")
	assert_eq(ram.global_position, TO, "and don't move it")
	await get_tree().process_frame
	assert_false(is_instance_valid(ram), "freed")


func test_zero_travel_arrives_on_the_first_step() -> void:
	var ram: Ram = _make({"from": FROM, "to": TO, "travel_s": 0.0})
	assert_eq(ram.global_position, FROM, "still at from before the step")
	ram.step(0.0)
	assert_eq(ram.global_position, TO)
	assert_eq(_arrivals, 1)
	assert_true(ram.has_arrived())


func test_negative_delta_does_not_move_it_back() -> void:
	var ram: Ram = _make({"from": FROM, "to": TO, "travel_s": 0.5})
	ram.step(STEP)
	var at: Vector2 = ram.global_position
	ram.step(-1.0)
	assert_eq(ram.global_position, at)
	assert_eq(_arrivals, 0)


func test_physics_process_steps() -> void:
	var ram: Ram = _make({"from": FROM, "to": TO, "travel_s": 10.0})
	ram.set_physics_process(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_gt(ram.global_position.y, FROM.y, "moved by the physics tick")
