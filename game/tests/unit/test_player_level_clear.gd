extends "res://tests/fixtures/player_test_base.gd"
## Player after the level clears (DW-54, decision #39): the first outcome wins.
## Once Events.level_cleared fires the ship is safe: damage and hazard contact
## cost nothing and emit nothing (a small enemy is not destroyed, nothing is
## remembered), so it can never die or emit level_failed. Orbs are still
## collected and the ship stays visible and alive. Driven with physics off.

const ORB_SCENE: PackedScene = preload("res://entities/pickups/energy_orb.tscn")


func _clear() -> void:
	Events.level_cleared.emit(1)


func _orb() -> EnergyOrb:
	var orb: EnergyOrb = ORB_SCENE.instantiate() as EnergyOrb
	orb.setup({"position": HAZARD_POS})
	add_child_autofree(orb)
	orb.set_physics_process(false)
	return orb


func _step(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		_player.step_iframes(DT)
		t += DT


func test_not_safe_before_the_clear() -> void:
	assert_false(_player.is_safe())
	_player.apply_damage(1, null)
	assert_eq(_player.hearts, _player.max_hearts - 1, "damage counts before the clear")


func test_safe_after_the_clear() -> void:
	_clear()
	assert_true(_player.is_safe())
	assert_false(_player.is_dead())
	assert_true(_player.visible, "ship stays visible")
	assert_false(_player.is_invulnerable(), "not routed through is_invulnerable()")


func test_lethal_damage_is_ignored_after_the_clear() -> void:
	_player.hearts = 1
	_clear()
	_player.apply_damage(5, null)
	assert_eq(_player.hearts, 1, "hearts unchanged")
	assert_false(_player.is_dead())
	assert_signal_not_emitted(Events, "player_hit")
	assert_signal_not_emitted(Events, "player_died")
	assert_signal_not_emitted(Events, "level_failed")


func test_wasp_contact_costs_nothing_and_wasp_survives() -> void:
	_clear()
	var wasp: Wasp = _wasp()
	_player.on_contact(wasp)
	assert_eq(_player.hearts, _player.max_hearts, "no heart cost")
	assert_false(wasp.is_dead(), "wasp not destroyed")
	assert_false(wasp.is_queued_for_deletion())
	assert_false(_player._contacts.has(wasp), "not remembered")
	assert_signal_not_emitted(Events, "player_hit")


func test_asteroid_contact_costs_nothing_and_is_not_remembered() -> void:
	_clear()
	var rock: Asteroid = _asteroid(&"large")
	_player.on_contact(rock)
	assert_eq(_player.hearts, _player.max_hearts, "no heart cost")
	assert_eq(_player._contacts.size(), 0, "nothing remembered")
	assert_signal_not_emitted(Events, "player_hit")


func test_remembered_hazard_is_dropped_at_the_clear() -> void:
	var bastion: Bastion = _bastion()
	_player.on_contact(bastion)
	var after_hit: int = _player.hearts
	assert_true(_player._contacts.has(bastion), "remembered before the clear")
	_clear()
	assert_eq(_player._contacts.size(), 0, "contacts dropped")
	_step(Config.num("player.iframes_s") + 2.0 * DT)
	assert_eq(_player.hearts, after_hit, "no re-hit when the i-frames end")
	_player.debug_invincible = true
	_player.debug_invincible = false
	assert_eq(_player.hearts, after_hit, "no re-hit when debug_invincible turns off")


func test_orb_still_collected_after_the_clear() -> void:
	_clear()
	var orb: EnergyOrb = _orb()
	_player.on_contact(orb)
	assert_eq(GameState.energy, 10, "orb collected")
	assert_true(orb.is_queued_for_deletion(), "orb freed")


func test_dead_ship_stays_dead_after_a_clear() -> void:
	_player.apply_damage(_player.hearts, null)
	Feedback.reset()
	_clear()
	assert_true(_player.is_dead())
	assert_false(_player.is_safe(), "the death came first")
