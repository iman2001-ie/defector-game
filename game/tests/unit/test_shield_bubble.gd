extends GutTest
## ShieldBubble (Story 3.4): the in-world coalition ring around the ship, sized
## and timed from player.shield_bubble, driven by the Player through
## show_remaining / hide_bubble, blinking in the last blink_last_s.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")


func _make() -> ShieldBubble:
	var bubble: ShieldBubble = ShieldBubble.new()
	add_child_autofree(bubble)
	return bubble


func test_hidden_by_default() -> void:
	assert_false(_make().visible)


func test_size_and_colour_from_config_and_ux() -> void:
	var bubble: ShieldBubble = _make()
	assert_eq(bubble.radius_px(), Config.num("player.shield_bubble.diameter_px") / 2.0)
	assert_eq(bubble.radius_px(), 60.0, "120 px ring")
	assert_eq(bubble.stroke_px, Config.num("player.shield_bubble.stroke_px"))
	assert_eq(ShieldBubble.RING_COLOR, Color("#22E6FF"), "coalition")
	var c: Color = bubble.ring_color()
	assert_true(Color(c.r, c.g, c.b, 1.0).is_equal_approx(Color("#22E6FF")))
	assert_almost_eq(c.a, 0.4, 0.0001, "40% alpha")


func test_show_remaining_and_hide() -> void:
	var bubble: ShieldBubble = _make()
	bubble.show_remaining(4.0)
	assert_true(bubble.visible)
	bubble.show_remaining(0.0)
	assert_false(bubble.visible, "<= 0 hides")
	bubble.show_remaining(2.0)
	bubble.hide_bubble()
	assert_false(bubble.visible)
	bubble.show_remaining(-1.0)
	assert_false(bubble.visible)


func test_is_lit_blink_rows() -> void:
	# remaining 0.76 / 0.75 / 0.70 / 0.60 at 4 Hz over the last 0.75 s.
	assert_true(ShieldBubble.is_lit(0.76, 0.75, 4.0), "before the window")
	assert_true(ShieldBubble.is_lit(0.75, 0.75, 4.0), "window start: lit")
	assert_true(ShieldBubble.is_lit(0.70, 0.75, 4.0), "t 0.05: lit")
	assert_false(ShieldBubble.is_lit(0.60, 0.75, 4.0), "t 0.15 (phase 0.6): off")
	assert_true(ShieldBubble.is_lit(0.50, 0.75, 4.0), "t 0.25: next cycle lit")
	assert_true(ShieldBubble.is_lit(3.0, 0.75, 4.0), "well before the end")


func test_blink_follows_tuning_in_show_remaining() -> void:
	var bubble: ShieldBubble = _make()
	assert_eq(bubble.blink_hz, 4.0)
	assert_eq(bubble.blink_last_s, 0.75)
	bubble.show_remaining(0.60)
	assert_false(bubble.visible, "off phase")
	bubble.show_remaining(0.70)
	assert_true(bubble.visible, "on phase")


func test_draws_without_errors() -> void:
	var bubble: ShieldBubble = _make()
	watch_signals(bubble)
	bubble.show_remaining(4.0)
	await wait_process_frames(1)
	assert_signal_emitted(bubble, "draw", "the ring was drawn")


func test_player_scene_has_the_bubble() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.warp_mouse = func(_p: Vector2) -> void: pass
	add_child_autofree(player)
	player.set_physics_process(false)
	var bubble: Node = player.get_node_or_null(^"ShieldBubble")
	assert_true(bubble is ShieldBubble, "Player/ShieldBubble is a ShieldBubble")
	if bubble is ShieldBubble:
		assert_false((bubble as ShieldBubble).visible, "hidden until the shield is raised")
