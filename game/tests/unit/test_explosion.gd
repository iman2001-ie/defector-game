extends GutTest
## Explosion: setup/ready, children per extras, particle limits, shockwave ring,
## self-free after LIFETIME_S. Story 7.5: the white_flash extra (a full-screen
## white flash between the HUD and Comms layers, fading linearly).

const EXPLOSION_SCENE: PackedScene = preload("res://entities/effects/explosion.tscn")
const PARTICLES: Array[String] = ["Burst", "Sparks", "Debris"]


func after_each() -> void:
	Config.load_data()


func _make(extras: Array, scale: float = 1.0, pos: Vector2 = Vector2(400, 300)) -> Explosion:
	var e: Explosion = EXPLOSION_SCENE.instantiate() as Explosion
	e.setup({"position": pos, "scale": scale, "extras": extras})
	add_child_autofree(e)
	return e


func _emitting(e: Explosion, child: String) -> bool:
	return (e.get_node(child) as GPUParticles2D).emitting


func test_registry_has_explosion() -> void:
	assert_eq(EntityRegistry.EXPLOSION, EXPLOSION_SCENE)


func test_setup_stores_ready_applies() -> void:
	var e: Explosion = EXPLOSION_SCENE.instantiate() as Explosion
	e.setup({"position": Vector2(10, 20), "scale": 2.0, "extras": [&"debris"]})
	assert_eq(e.position, Vector2.ZERO, "nothing applied before _ready")
	add_child_autofree(e)
	assert_eq(e.global_position, Vector2(10, 20))
	assert_eq(e.scale, Vector2(2, 2))


func test_no_extras_only_burst() -> void:
	var e: Explosion = _make([])
	assert_true(_emitting(e, "Burst"))
	assert_false(_emitting(e, "Sparks"))
	assert_false(_emitting(e, "Debris"))
	assert_false((e.get_node("Shockwave") as Node2D).visible)


func test_sparks() -> void:
	var e: Explosion = _make([&"sparks"], 0.5)
	assert_true(_emitting(e, "Burst"))
	assert_true(_emitting(e, "Sparks"))
	assert_false(_emitting(e, "Debris"))
	assert_false((e.get_node("Shockwave") as Node2D).visible)


func test_debris_and_shockwave() -> void:
	var e: Explosion = _make([&"debris", &"shockwave"], 2.0)
	assert_true(_emitting(e, "Burst"))
	assert_false(_emitting(e, "Sparks"))
	assert_true(_emitting(e, "Debris"))
	assert_true((e.get_node("Shockwave") as Node2D).visible)


func test_unknown_extras_ignored() -> void:
	var e: Explosion = _make([&"red_vignette", &"glitter"])
	assert_true(_emitting(e, "Burst"))
	assert_false(_emitting(e, "Sparks"))
	assert_false(_emitting(e, "Debris"))
	assert_false((e.get_node("Shockwave") as Node2D).visible)
	assert_false(e.is_flashing(), "no flash")


# --- White flash (Story 7.5) -----------------------------------------------------

func test_white_flash_layer_sits_between_the_hud_and_comms() -> void:
	var e: Explosion = EXPLOSION_SCENE.instantiate() as Explosion
	var flash: CanvasLayer = e.get_node_or_null("Flash") as CanvasLayer
	assert_not_null(flash, "a Flash CanvasLayer")
	if flash != null:
		var level: Node = (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
		var hud: int = (level.get_node("HUD") as CanvasLayer).layer
		var comms: int = (level.get_node("Comms") as CanvasLayer).layer
		level.free()
		assert_gt(flash.layer, hud, "above the HUD")
		assert_lt(flash.layer, comms, "below Comms")
		assert_false(flash.visible, "hidden in the scene")
		var rect: ColorRect = flash.get_node("Rect") as ColorRect
		assert_eq(rect.get_rect(), Rect2(Vector2.ZERO, Playfield.SIZE), "full screen")
		assert_eq(rect.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	e.free()


func test_white_flash_fades_linearly_over_its_duration() -> void:
	var alpha: float = Config.num("feedback.white_flash.alpha")
	var duration: float = Config.num("feedback.white_flash.duration_s")
	assert_eq([alpha, duration], [0.7, 0.3], "shipped flash")
	var e: Explosion = _make([&"white_flash"], 4.0)
	var rect: ColorRect = e.get_node("Flash/Rect") as ColorRect
	assert_true(e.is_flashing(), "the flash shows")
	assert_almost_eq(e.flash_alpha(), alpha, 0.0001, "0 s: full alpha")
	assert_eq(Color(rect.color.r, rect.color.g, rect.color.b), Color.WHITE, "white")
	e._process(duration / 2.0)
	assert_almost_eq(e.flash_alpha(), alpha / 2.0, 0.0001, "half way: half alpha")
	e._process(duration / 2.0)
	assert_false(e.is_flashing(), "end: hidden")
	assert_eq(e.flash_alpha(), 0.0, "end: alpha 0")
	assert_almost_eq(rect.color.a, 0.0, 0.0001)
	assert_false(e.is_queued_for_deletion(), "the explosion itself lives to LIFETIME_S")


func test_white_flash_never_outlasts_the_explosion() -> void:
	(Config.tuning["feedback"] as Dictionary)["white_flash"] = {"alpha": 0.5, "duration_s": 5.0}
	var e: Explosion = _make([&"white_flash"])
	e._process(Explosion.LIFETIME_S - 0.01)
	assert_true(e.is_flashing(), "still fading just before LIFETIME_S")
	assert_almost_eq(e.flash_alpha(), 0.5 * 0.01 / Explosion.LIFETIME_S, 0.0001, "capped at LIFETIME_S")


func test_white_flash_only_with_its_extra() -> void:
	var e: Explosion = _make([&"debris", &"shockwave"], 2.0)
	assert_false(e.is_flashing())
	assert_eq(e.flash_alpha(), 0.0)


func test_particle_settings() -> void:
	var e: Explosion = _make([])
	for child: String in PARTICLES:
		var p: GPUParticles2D = e.get_node(child) as GPUParticles2D
		assert_not_null(p, child)
		if p == null:
			continue
		assert_true(p.one_shot, child + " one_shot")
		assert_eq(p.explosiveness, 1.0, child + " explosiveness")
		assert_lte(p.amount, 32, child + " particle count")
		var mat: CanvasItemMaterial = p.material as CanvasItemMaterial
		assert_not_null(mat, child + " material")
		if mat != null:
			assert_eq(mat.blend_mode, CanvasItemMaterial.BLEND_MODE_ADD, child + " additive")
		assert_lte(p.lifetime, Explosion.LIFETIME_S, child + " lifetime within LIFETIME_S")
	assert_lte(Explosion.SHOCKWAVE_S, Explosion.LIFETIME_S)


func test_scene_children_disabled_by_default() -> void:
	var e: Explosion = EXPLOSION_SCENE.instantiate() as Explosion
	for child: String in PARTICLES:
		assert_false((e.get_node(child) as GPUParticles2D).emitting, child + " off in the scene")
	assert_false((e.get_node("Shockwave") as Node2D).visible)
	e.free()


func test_shockwave_ring_expands_and_fades() -> void:
	var e: Explosion = _make([&"shockwave"])
	var ring: ShockwaveRing = e.get_node("Shockwave") as ShockwaveRing
	assert_not_null(ring, "Shockwave is a ShockwaveRing")
	if ring == null:
		return
	var r0: float = ring.current_radius()
	e._process(Explosion.SHOCKWAVE_S / 2.0)
	assert_almost_eq(ring.progress, 0.5, 0.0001)
	assert_gt(ring.current_radius(), r0, "expands")
	e._process(Explosion.SHOCKWAVE_S)
	assert_eq(ring.progress, 1.0, "clamped at 1")


func test_frees_after_lifetime() -> void:
	var e: Explosion = _make([&"debris"])
	e._process(Explosion.LIFETIME_S - 0.01)
	assert_false(e.is_queued_for_deletion(), "alive just before")
	e._process(0.01)
	assert_true(e.is_queued_for_deletion(), "freed at LIFETIME_S")


## Playtest pt7-e: a `speed` param slows (or speeds) the whole effect: the
## particles' speed_scale, the shockwave and the self-free time.
func test_speed_scales_particles_shockwave_and_lifetime() -> void:
	var e: Explosion = EXPLOSION_SCENE.instantiate() as Explosion
	e.setup({"position": Vector2(400, 300), "scale": 1.0, "extras": [&"debris", &"shockwave"], "speed": 0.5})
	add_child_autofree(e)
	assert_almost_eq(e.speed, 0.5, 0.0001)
	for child: String in ["Burst", "Sparks", "Debris"]:
		assert_almost_eq((e.get_node(child) as GPUParticles2D).speed_scale, 0.5, 0.0001, child + " speed_scale")
	assert_almost_eq(e.lifetime(), Explosion.LIFETIME_S / 0.5, 0.0001, "lives twice as long")
	var ring: ShockwaveRing = e.get_node("Shockwave") as ShockwaveRing
	e._process(Explosion.SHOCKWAVE_S / 2.0)
	assert_almost_eq(ring.progress, 0.25, 0.0001, "the ring expands at half speed")
	e._process(Explosion.LIFETIME_S - Explosion.SHOCKWAVE_S / 2.0)
	assert_false(e.is_queued_for_deletion(), "alive past LIFETIME_S")
	e._process(Explosion.LIFETIME_S)
	assert_true(e.is_queued_for_deletion(), "freed at lifetime()")


func test_speed_defaults_to_one_and_is_floored() -> void:
	var plain: Explosion = _make([])
	assert_almost_eq(plain.speed, 1.0, 0.0001, "default")
	assert_almost_eq(plain.lifetime(), Explosion.LIFETIME_S, 0.0001)
	var e: Explosion = EXPLOSION_SCENE.instantiate() as Explosion
	e.setup({"speed": 0.0})
	add_child_autofree(e)
	assert_almost_eq(e.speed, Explosion.MIN_SPEED, 0.0001, "never 0")
