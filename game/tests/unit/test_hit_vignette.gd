extends GutTest
## HitVignette: the danger edge flash on Events.player_hit (hud.hit_vignette).

const THEME_PATH: String = "res://ui/theme/defector_theme.tres"


func after_each() -> void:
	get_tree().paused = false
	Config.load_data()
	PauseArbiter.clear()


func _make(duration_s: float = -1.0) -> HitVignette:
	if duration_s >= 0.0:
		((Config.tuning["hud"] as Dictionary)["hit_vignette"] as Dictionary)["duration_s"] = duration_s
	var vignette: HitVignette = HitVignette.new()
	vignette.theme = load(THEME_PATH) as Theme
	add_child_autofree(vignette)
	return vignette


func test_init_modes_and_shader() -> void:
	var vignette: HitVignette = _make()
	assert_eq(vignette.process_mode, Node.PROCESS_MODE_PAUSABLE)
	assert_eq(vignette.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_true(vignette.material is ShaderMaterial, "edge-gradient shader")


func test_hidden_at_start() -> void:
	var vignette: HitVignette = _make()
	assert_eq(vignette.current_alpha(), 0.0)
	assert_false(vignette.visible)


func test_tuning() -> void:
	assert_eq(Config.num("hud.hit_vignette.max_alpha"), 0.5)
	assert_eq(Config.num("hud.hit_vignette.duration_s"), 0.3)
	assert_lte(Config.num("hud.hit_vignette.duration_s"), 0.3, "UI motion never exceeds 0.3 s")


func test_player_hit_flashes_then_fades() -> void:
	var vignette: HitVignette = _make(1.0)
	Events.player_hit.emit(Vector2(960, 900))
	assert_almost_eq(vignette.current_alpha(), 0.5, 0.0001, "jumps to max_alpha")
	assert_true(vignette.visible)
	var danger: Color = Color("#FF1F4B")
	assert_almost_eq(vignette.color.r, danger.r, 0.001, "danger colour")
	assert_almost_eq(vignette.color.g, danger.g, 0.001)
	assert_almost_eq(vignette.color.b, danger.b, 0.001)
	await wait_seconds(0.4)
	var mid: float = vignette.current_alpha()
	assert_gt(mid, 0.0, "fading")
	assert_lt(mid, 0.5, "fading")
	await wait_seconds(0.8)
	assert_eq(vignette.current_alpha(), 0.0, "gone after duration_s")
	assert_false(vignette.visible, "hidden at 0")


func test_second_hit_restarts_the_flash() -> void:
	var vignette: HitVignette = _make(0.2)
	Events.player_hit.emit(Vector2.ZERO)
	await wait_seconds(0.1)
	Events.player_hit.emit(Vector2.ZERO)
	assert_almost_eq(vignette.current_alpha(), 0.5, 0.0001)


func test_fade_freezes_while_paused() -> void:
	var vignette: HitVignette = _make(0.1)
	Events.player_hit.emit(Vector2.ZERO)
	get_tree().paused = true
	# A SceneTreeTimer runs while paused by default.
	await get_tree().create_timer(0.2).timeout
	assert_almost_eq(vignette.current_alpha(), 0.5, 0.0001, "tween bound to the pausable node")
	get_tree().paused = false
