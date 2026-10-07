extends GutTest
## Explosion: setup/ready, children per extras, particle limits, shockwave ring,
## self-free after LIFETIME_S.

const EXPLOSION_SCENE: PackedScene = preload("res://entities/effects/explosion.tscn")
const PARTICLES: Array[String] = ["Burst", "Sparks", "Debris"]


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
	var e: Explosion = _make([&"white_flash", &"red_vignette"])
	assert_true(_emitting(e, "Burst"))
	assert_false(_emitting(e, "Sparks"))
	assert_false(_emitting(e, "Debris"))
	assert_false((e.get_node("Shockwave") as Node2D).visible)


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
