extends GutTest
## Enemy contract via wasp.tscn: HP, damage intake, ally attribution, one-shot death,
## hitbox from tuning, scene layers; ImpactTier name mapping.

const WASP_SCENE: PackedScene = preload("res://entities/enemies/wasp/wasp.tscn")
const DamageTarget: GDScript = preload("res://tests/fixtures/damage_target.gd")


func before_each() -> void:
	watch_signals(Events)


func _make_wasp(pos: Vector2 = Vector2(960, 300)) -> Enemy:
	var wasp: Enemy = WASP_SCENE.instantiate() as Enemy
	wasp.setup({"position": pos})
	add_child_autofree(wasp)
	watch_signals(wasp)
	return wasp


## An out-of-tree Projectile standing in for a bolt, with the given from_ally flag.
func _source(from_ally: bool) -> Projectile:
	var projectile: Projectile = Projectile.new()
	projectile.from_ally = from_ally
	autofree(projectile)
	return projectile


func test_setup_stores_and_ready_applies() -> void:
	var wasp: Enemy = WASP_SCENE.instantiate() as Enemy
	wasp.setup({"position": Vector2(300, 200)})
	assert_eq(wasp.position, Vector2.ZERO, "setup does not apply the position")
	add_child_autofree(wasp)
	assert_eq(wasp.global_position, Vector2(300, 200))
	assert_eq(wasp.hp, Config.int_("enemies.wasp.hp"))
	assert_eq(wasp.hp, 3)


func test_wasp_kill_after_three_hits() -> void:
	var wasp: Enemy = _make_wasp()
	var bolt: Projectile = _source(false)
	wasp.apply_damage(1, bolt)
	wasp.apply_damage(1, bolt)
	assert_eq(wasp.hp, 1)
	assert_signal_not_emitted(Events, "enemy_killed", "alive after 2 hits")
	assert_false(wasp.is_queued_for_deletion())
	wasp.apply_damage(1, bolt)
	assert_eq(wasp.hp, 0)
	assert_signal_emit_count(Events, "enemy_killed", 1)
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"wasp", Vector2(960, 300), false])
	assert_signal_emit_count(wasp, "resolved", 1)
	assert_true(wasp.is_queued_for_deletion())


func test_overkill_does_not_die_twice() -> void:
	var wasp: Enemy = _make_wasp()
	for i: int in 4:
		wasp.apply_damage(1, null)
	assert_signal_emit_count(Events, "enemy_killed", 1)
	assert_signal_emit_count(wasp, "resolved", 1)
	wasp.destroy_by_contact()
	assert_signal_emit_count(Events, "enemy_killed", 1, "contact after death is ignored")
	assert_signal_emit_count(wasp, "resolved", 1)


func test_ally_source_flags_kill() -> void:
	var wasp: Enemy = _make_wasp()
	wasp.apply_damage(2, _source(false))
	wasp.apply_damage(1, _source(true))
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"wasp", Vector2(960, 300), true])


func test_player_kill_after_ally_hit_is_not_ally() -> void:
	var wasp: Enemy = _make_wasp()
	wasp.apply_damage(2, _source(true))
	wasp.apply_damage(1, _source(false))
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"wasp", Vector2(960, 300), false])


func test_null_source_kill() -> void:
	var wasp: Enemy = _make_wasp()
	wasp.apply_damage(3, null)
	assert_signal_emit_count(Events, "enemy_killed", 1)
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"wasp", Vector2(960, 300), false])
	assert_signal_emit_count(wasp, "resolved", 1)


func test_plain_source_without_from_ally() -> void:
	var wasp: Enemy = _make_wasp()
	var plain: Area2D = DamageTarget.new() as Area2D
	autofree(plain)
	wasp.apply_damage(3, plain)
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"wasp", Vector2(960, 300), false])


func test_destroy_by_contact() -> void:
	var wasp: Enemy = _make_wasp()
	wasp.destroy_by_contact()
	assert_signal_emit_count(Events, "enemy_killed", 1)
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"wasp", Vector2(960, 300), false])
	assert_signal_emit_count(wasp, "resolved", 1)
	assert_true(wasp.is_queued_for_deletion())


func test_contact_after_ally_hit_is_not_ally() -> void:
	var wasp: Enemy = _make_wasp()
	wasp.apply_damage(1, _source(true))
	wasp.destroy_by_contact()
	assert_signal_emit_count(Events, "enemy_killed", 1)
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"wasp", Vector2(960, 300), false])


func test_tier_read_from_tuning() -> void:
	var lancer: Enemy = Enemy.new()
	lancer.type_id = &"lancer"
	var hitbox: CollisionShape2D = CollisionShape2D.new()
	hitbox.name = "Hitbox"
	lancer.add_child(hitbox)
	add_child_autofree(lancer)
	assert_eq(lancer.tier, ImpactTier.MEDIUM, "lancer tier 'medium' from tuning")


func test_wasp_hitbox_radius_from_tuning() -> void:
	var wasp: Enemy = _make_wasp()
	var hitbox: CollisionShape2D = wasp.get_node_or_null("Hitbox") as CollisionShape2D
	assert_not_null(hitbox)
	if hitbox == null:
		return
	var circle: CircleShape2D = hitbox.shape as CircleShape2D
	assert_not_null(circle, "CircleShape2D")
	if circle != null:
		assert_almost_eq(circle.radius, 25.6, 0.0001, "64 / 2 * 0.8")
		assert_almost_eq(circle.radius, wasp.sprite_px / 2.0 * Config.num("enemies.wasp.hitbox_ratio"), 0.0001)


func test_wasp_scene_contract() -> void:
	var wasp: Enemy = _make_wasp()
	assert_true(wasp is Enemy, "root is an Enemy")
	assert_eq(wasp.type_id, &"wasp")
	assert_eq(wasp.collision_layer, CollisionLayers.ENEMIES, "enemies layer")
	assert_eq(wasp.collision_mask, 0, "masks nothing")
	assert_false(wasp.monitoring)
	assert_true(wasp.monitorable)
	assert_eq(wasp.tier, ImpactTier.SMALL)
	assert_true(wasp.is_in_group(&"enemies"))
	assert_eq(wasp.sprite_px, 64.0)


func test_wasp_holds_position() -> void:
	var wasp: Enemy = _make_wasp(Vector2(720, 160))
	await wait_physics_frames(5)
	assert_eq(wasp.global_position, Vector2(720, 160))


# --- ImpactTier ---------------------------------------------------------------

func test_impact_tier_from_name() -> void:
	var expected: Dictionary = {
		"small": ImpactTier.SMALL,
		"medium": ImpactTier.MEDIUM,
		"large": ImpactTier.LARGE,
		"boss_part": ImpactTier.BOSS_PART,
		"boss_death": ImpactTier.BOSS_DEATH,
		"player_hit": ImpactTier.PLAYER_HIT,
		"player_death": ImpactTier.PLAYER_DEATH,
	}
	for tier_name: String in expected:
		assert_eq(ImpactTier.from_name(tier_name), expected[tier_name], tier_name)


func test_impact_tier_unknown_name_logs_and_returns_small() -> void:
	assert_eq(ImpactTier.from_name("gigantic"), ImpactTier.SMALL)
	assert_push_error("gigantic")
