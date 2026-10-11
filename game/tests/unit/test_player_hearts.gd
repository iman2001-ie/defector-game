extends "res://tests/fixtures/player_test_base.gd"
## Player hearts (Story 3.1): apply_damage, i-frames and their 10 Hz sprite
## flicker, contact costs by enemy tier and asteroid size, the persistent-overlap
## re-check, debug_invincible, the 0-heart floor (now death, Story 3.2; see
## test_player_death.gd) and the deferred first hearts_changed. Driven through
## step_iframes / on_contact with physics processing off.

const LANCER_SCENE: PackedScene = preload("res://entities/enemies/lancer/lancer.tscn")
const ENEMY_BULLET_SCENE: PackedScene = preload("res://entities/projectiles/enemy_bullet.tscn")
const NEEDLE_BOLT_SCENE: PackedScene = preload("res://entities/projectiles/needle_bolt.tscn")


func _sprite() -> Sprite2D:
	return _player.get_node("Sprite") as Sprite2D


## Steps the i-frames `seconds` forward in DT ticks.
func _step(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds - 0.00001:
		_player.step_iframes(DT)
		t += DT


func _iframes_s() -> float:
	return Config.num("player.iframes_s")


# --- Start state ------------------------------------------------------------------

func test_starts_with_tuned_hearts() -> void:
	assert_eq(_player.max_hearts, Config.int_("player.hearts"))
	assert_eq(_player.hearts, 5)
	assert_false(_player.is_invulnerable())
	assert_false(_player.debug_invincible)


func test_initial_hearts_changed_is_deferred() -> void:
	# Emitted deferred from _ready (before_each added the player this frame).
	assert_signal_not_emitted(Events, "hearts_changed", "not during _ready")
	await wait_process_frames(1)
	assert_signal_emit_count(Events, "hearts_changed", 1)
	assert_signal_emitted_with_parameters(Events, "hearts_changed", [5, 5])


# --- apply_damage -----------------------------------------------------------------

func test_bullet_hit_costs_one_heart() -> void:
	_player.apply_damage(1, null)
	assert_eq(_player.hearts, 4)
	assert_signal_emitted_with_parameters(Events, "hearts_changed", [4, 5])
	assert_signal_emit_count(Events, "player_hit", 1)
	assert_signal_emitted_with_parameters(Events, "player_hit", [_player.global_position])
	assert_true(_player.is_invulnerable(), "i-frames start")
	assert_true(Feedback.is_hit_stopped(), "PLAYER_HIT feedback ran (hit-stop)")


func test_player_hit_sfx_is_registered() -> void:
	_player.apply_damage(1, null)
	assert_eq(_logged("[WARN][audio]"), [] as Array[String], "no unknown sfx warning")
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"player_hit"])


func test_enemy_bullet_and_needle_bolt_cost_one_heart_each() -> void:
	_shoot(ENEMY_BULLET_SCENE)
	assert_eq(_player.hearts, 4, "EnemyBullet: -1")
	assert_signal_emit_count(Events, "player_hit", 1)
	_step(_iframes_s() + DT)
	_shoot(NEEDLE_BOLT_SCENE)
	assert_eq(_player.hearts, 3, "NeedleBolt: -1")
	assert_signal_emit_count(Events, "player_hit", 2)


func test_hit_during_iframes_is_ignored() -> void:
	_player.apply_damage(1, null)
	_step(0.5)
	_player.apply_damage(1, null)
	assert_eq(_player.hearts, 4)
	assert_signal_emit_count(Events, "player_hit", 1, "no second hit")
	assert_signal_emit_count(Events, "hearts_changed", 1, "no second hearts_changed")


func test_iframes_expire_after_tuned_time() -> void:
	_player.apply_damage(1, null)
	_step(_iframes_s() - 2.0 * DT)
	assert_true(_player.is_invulnerable(), "still in i-frames just before the end")
	_step(3.0 * DT)
	assert_false(_player.is_invulnerable(), "over after iframes_s")
	assert_true(_sprite().visible, "sprite restored")
	_player.apply_damage(1, null)
	assert_eq(_player.hearts, 3, "hittable again")


func test_physics_process_runs_the_iframes() -> void:
	_player.apply_damage(1, null)
	var t: float = 0.0
	while t < _iframes_s() + DT:
		_player._physics_process(DT)
		t += DT
	assert_false(_player.is_invulnerable(), "the physics tick ends the i-frames")
	assert_true(_sprite().visible, "sprite restored")


func test_zero_or_negative_amount_is_ignored() -> void:
	_player.apply_damage(0, null)
	_player.apply_damage(-2, null)
	assert_eq(_player.hearts, 5)
	assert_false(_player.is_invulnerable(), "no i-frames")
	assert_signal_not_emitted(Events, "player_hit")


func test_flicker_toggles_sprite_at_tuned_hz() -> void:
	var hz: float = Config.num("player.iframe_flicker_hz")
	assert_eq(hz, 10.0)
	_player.apply_damage(1, null)
	assert_true(_sprite().visible, "visible at the hit")
	_player.step_iframes(0.03)
	assert_true(_sprite().visible, "first half of the 0.1 s cycle: on")
	_player.step_iframes(0.04)
	assert_false(_sprite().visible, "second half of the cycle: off")
	_player.step_iframes(0.05)
	assert_true(_sprite().visible, "next cycle: on")
	_player.step_iframes(0.04)
	assert_false(_sprite().visible, "off again")


func test_flicker_changes_only_the_sprite() -> void:
	_player.apply_damage(1, null)
	_player.step_iframes(0.07)
	assert_false(_sprite().visible)
	assert_true(_player.visible, "the Player node itself stays visible")


func test_step_iframes_without_a_hit_does_nothing() -> void:
	_step(0.5)
	assert_true(_sprite().visible)
	assert_false(_player.is_invulnerable())


func test_overkill_floors_at_zero_and_kills_once() -> void:
	_player.hearts = 1
	_player.apply_damage(2, null)
	assert_eq(_player.hearts, 0, "not negative")
	assert_signal_emitted_with_parameters(Events, "hearts_changed", [0, 5])
	assert_true(_player.is_dead(), "0 hearts is death")
	assert_false(_player.is_invulnerable(), "no i-frames after death")
	_step(_iframes_s() + DT)
	_player.apply_damage(1, null)
	assert_eq(_player.hearts, 0)
	assert_signal_emit_count(Events, "player_hit", 1, "later damage ignored")
	assert_signal_emit_count(Events, "player_died", 1)
	assert_signal_emit_count(Events, "level_failed", 1)
	assert_eq(_logged("[INFO][combat]").size(), 1, "one INFO line")


# --- debug_invincible -------------------------------------------------------------

func test_debug_invincible_ignores_damage_without_flicker() -> void:
	_player.debug_invincible = true
	assert_true(_player.is_invulnerable())
	_player.apply_damage(1, null)
	assert_eq(_player.hearts, 5)
	assert_signal_not_emitted(Events, "player_hit")
	assert_signal_not_emitted(Events, "hearts_changed")
	_player.step_iframes(0.07)
	assert_true(_sprite().visible, "no flicker from debug_invincible alone")


func test_debug_invincible_still_destroys_small_enemies() -> void:
	_player.debug_invincible = true
	var wasp: Wasp = _wasp()
	_player.on_contact(wasp)
	assert_eq(_player.hearts, 5)
	assert_true(wasp.is_dead())


func test_debug_invincible_off_reapplies_overlapping_hazard() -> void:
	_player.debug_invincible = true
	var rock: Asteroid = _asteroid(&"large")
	_player.on_contact(rock)
	assert_eq(_player.hearts, 5)
	_player.debug_invincible = false
	assert_eq(_player.hearts, 3, "still inside the large asteroid: -2")


# --- Contact ----------------------------------------------------------------------

func test_small_enemy_contact_costs_one_and_destroys() -> void:
	var wasp: Wasp = _wasp()
	_player.on_contact(wasp)
	assert_eq(_player.hearts, 4)
	assert_true(wasp.is_dead(), "Wasp destroyed by contact")
	assert_true(_player.is_invulnerable())


func test_contact_during_iframes_still_destroys() -> void:
	_player.apply_damage(1, null)
	var wasp: Wasp = _wasp()
	_player.on_contact(wasp)
	assert_eq(_player.hearts, 4, "no heart cost")
	assert_true(wasp.is_dead(), "Wasp still destroyed")


func test_dead_enemy_is_skipped() -> void:
	var wasp: Wasp = _wasp()
	wasp.apply_damage(100, null)
	assert_true(wasp.is_dead())
	_player.on_contact(wasp)
	assert_eq(_player.hearts, 5)


func test_medium_enemy_contact_costs_medium_and_destroys() -> void:
	var lancer: Lancer = LANCER_SCENE.instantiate() as Lancer
	lancer.setup({"position": HAZARD_POS})
	add_child_autofree(lancer)
	lancer.set_physics_process(false)
	assert_eq(lancer.tier, ImpactTier.MEDIUM)
	_player.on_contact(lancer)
	assert_eq(_player.hearts, 5 - Config.int_("damage.contact_medium_hearts"))
	assert_true(lancer.is_dead(), "Lancer destroyed by contact")


func test_bastion_contact_costs_two_and_survives() -> void:
	var bastion: Bastion = _bastion()
	_player.on_contact(bastion)
	assert_eq(_player.hearts, 5 - Config.int_("damage.contact_large_hearts"))
	assert_eq(_player.hearts, 3)
	assert_false(bastion.is_dead(), "Bastion alive")


# --- Maul body-block (Story 6.2) ---------------------------------------------------

const MAUL_SCENE: PackedScene = preload("res://entities/enemies/maul/maul.tscn")
const CONVOY_SCENE: PackedScene = preload("res://entities/allies/convoy.tscn")


func _maul() -> Maul:
	var maul: Maul = MAUL_SCENE.instantiate() as Maul
	maul.setup({"position": HAZARD_POS})
	add_child_autofree(maul)
	maul.set_physics_process(false)
	return maul


func _still_convoy() -> Convoy:
	var convoy: Convoy = CONVOY_SCENE.instantiate() as Convoy
	add_child_autofree(convoy)
	convoy.set_physics_process(false)
	return convoy


## The Maul's contact cost is its own key (damage.maul_contact_hearts), not the
## medium tier's; it is destroyed as a kill and the convoy takes nothing.
func test_maul_body_block_costs_maul_contact_hearts_and_kills_it() -> void:
	(Config.tuning["damage"] as Dictionary)["maul_contact_hearts"] = 3
	var player: Player = _make_player(Vector2(1200, 900))
	var convoy: Convoy = _still_convoy()
	var maul: Maul = _maul()
	assert_eq(maul.tier, ImpactTier.MEDIUM)
	player.on_contact(maul)
	assert_eq(player.hearts, 2, "5 - damage.maul_contact_hearts (3)")
	assert_true(maul.is_dead(), "Maul destroyed by contact")
	assert_signal_emitted_with_parameters(Events, "enemy_killed", [&"maul", HAZARD_POS, false])
	assert_eq(convoy.hp(), convoy.max_hp(), "the convoy is unchanged")
	Config.load_data()


func test_maul_contact_uses_the_shipped_key() -> void:
	var maul: Maul = _maul()
	_player.on_contact(maul)
	assert_eq(_player.hearts, 5 - Config.int_("damage.maul_contact_hearts"))
	assert_true(maul.is_dead())


func test_maul_contact_during_iframes_or_shield_costs_nothing_but_destroys() -> void:
	_player.apply_damage(1, null)
	var first: Maul = _maul()
	_player.on_contact(first)
	assert_eq(_player.hearts, 4, "no heart during i-frames")
	assert_true(first.is_dead(), "still destroyed")
	_step(Config.num("player.iframes_s") + DT)
	GameState.energy = 100
	assert_true(_player.try_shield(), "shield raised")
	var second: Maul = _maul()
	_player.on_contact(second)
	assert_eq(_player.hearts, 4, "no heart under the shield")
	assert_true(second.is_dead(), "still destroyed")
	assert_signal_emit_count(Events, "enemy_killed", 2)


func test_other_medium_enemies_keep_the_medium_cost() -> void:
	(Config.tuning["damage"] as Dictionary)["maul_contact_hearts"] = 3
	var player: Player = _make_player(Vector2(1200, 900))
	var lancer: Lancer = LANCER_SCENE.instantiate() as Lancer
	lancer.setup({"position": HAZARD_POS})
	add_child_autofree(lancer)
	lancer.set_physics_process(false)
	player.on_contact(lancer)
	assert_eq(player.hearts, 5 - Config.int_("damage.contact_medium_hearts"), "Lancer unchanged")
	Config.load_data()


func test_asteroid_costs_by_size_and_is_never_destroyed() -> void:
	var expected: Dictionary = {&"small": 1, &"medium": 1, &"large": 2}
	for size: StringName in expected:
		var rock: Asteroid = _asteroid(size)
		var before: int = _player.hearts
		_player.on_contact(rock)
		assert_eq(before - _player.hearts, expected[size] as int, "%s asteroid cost" % size)
		assert_false(rock.is_queued_for_deletion(), "%s asteroid survives" % size)
		# Leave the overlap and clear the i-frames for the next size.
		_player._on_area_exited(rock)
		_step(_iframes_s() + DT)
	assert_eq(_player.hearts, 1)


func test_large_asteroid_hits_again_when_iframes_end() -> void:
	var rock: Asteroid = _asteroid(&"large")
	_player.on_contact(rock)
	assert_eq(_player.hearts, 3)
	_step(_iframes_s() - 2.0 * DT)
	assert_eq(_player.hearts, 3, "nothing during i-frames")
	_step(3.0 * DT)
	assert_eq(_player.hearts, 1, "second -2 when the i-frames end")
	assert_true(_player.is_invulnerable(), "the re-hit restarts the i-frames")
	assert_signal_emit_count(Events, "player_hit", 2)


func test_exited_hazard_does_not_hit_again() -> void:
	var rock: Asteroid = _asteroid(&"large")
	_player.on_contact(rock)
	_player._on_area_exited(rock)
	_step(_iframes_s() + DT)
	assert_eq(_player.hearts, 3, "left the asteroid: no re-hit")


func test_same_hazard_is_tracked_once() -> void:
	var rock: Asteroid = _asteroid(&"large")
	_player.on_contact(rock)
	_player.on_contact(rock)
	_player._on_area_exited(rock)
	_step(_iframes_s() + DT)
	assert_eq(_player.hearts, 3, "one exit clears it")


func test_freed_hazard_is_pruned_without_errors() -> void:
	var rock: Asteroid = _asteroid(&"large")
	var bastion: Bastion = _bastion()
	_player.on_contact(rock)
	_player.on_contact(bastion)
	rock.free()
	bastion.free()
	_step(_iframes_s() + DT)
	assert_eq(_player.hearts, 3, "freed hazards do not hit")
	assert_false(_player.is_invulnerable())


func test_pickup_layer_area_is_ignored() -> void:
	var pickup: Area2D = Area2D.new()
	pickup.collision_layer = 1 << 5
	pickup.global_position = HAZARD_POS
	add_child_autofree(pickup)
	_player.on_contact(pickup)
	assert_eq(_player.hearts, 5)
	assert_signal_not_emitted(Events, "player_hit")
	assert_false(_player.is_invulnerable())


func test_contact_signals_are_connected() -> void:
	assert_true(_player.area_entered.is_connected(_player._on_area_entered))
	assert_true(_player.area_exited.is_connected(_player._on_area_exited))
