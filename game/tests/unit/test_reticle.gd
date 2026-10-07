extends GutTest
## Reticle cooldown arc state, driven only by Events.missile_cooldown_changed.

const RETICLE_SCENE: PackedScene = preload("res://entities/player/reticle.tscn")


func _make_reticle() -> Sprite2D:
	var reticle: Sprite2D = RETICLE_SCENE.instantiate() as Sprite2D
	add_child_autofree(reticle)
	return reticle


func test_fresh_reticle_is_ready() -> void:
	var reticle: Sprite2D = _make_reticle()
	assert_eq(reticle.get(&"cooldown_ratio"), 0.0)


func test_ratio_follows_signal_clamped() -> void:
	var reticle: Sprite2D = _make_reticle()
	Events.missile_cooldown_changed.emit(0.5)
	assert_eq(reticle.get(&"cooldown_ratio"), 0.5)
	Events.missile_cooldown_changed.emit(1.7)
	assert_eq(reticle.get(&"cooldown_ratio"), 1.0)
	Events.missile_cooldown_changed.emit(0.0)
	assert_eq(reticle.get(&"cooldown_ratio"), 0.0)


func test_arc_constants_match_ux_spec() -> void:
	var reticle: Sprite2D = _make_reticle()
	assert_eq(reticle.get(&"COOLDOWN_RADIUS_PX"), 22.0)
	assert_eq(reticle.get(&"COOLDOWN_WIDTH_PX"), 4.0)
	assert_eq(reticle.get(&"COOLDOWN_COLOR"), Color("#93A7C2"))
