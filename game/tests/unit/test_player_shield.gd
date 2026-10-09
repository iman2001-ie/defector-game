extends "res://tests/fixtures/player_test_base.gd"
## Player shield (Story 3.4): try_shield spends abilities.shield.cost through
## GameState and makes the ship invulnerable for abilities.shield.duration_s
## (no stacking or refresh); too little energy is denied (ability_denied event
## + SFX, nothing spent); step_shield counts physics delta down, drives the
## ShieldBubble and re-applies an overlapping hazard on expiry; death clears it.
## Driven through try_shield / step_shield with physics off, plus one test that
## goes through the real `ability_shield` input action.

const LANCER_SCENE: PackedScene = preload("res://entities/enemies/lancer/lancer.tscn")
const ENEMY_BULLET_SCENE: PackedScene = preload("res://entities/projectiles/enemy_bullet.tscn")
const NEEDLE_BOLT_SCENE: PackedScene = preload("res://entities/projectiles/needle_bolt.tscn")
const ORB_SCENE: PackedScene = preload("res://entities/pickups/energy_orb.tscn")


func after_each() -> void:
	Input.action_release(&"ability_shield")
	super()


func _bubble() -> ShieldBubble:
	return _player.get_node("ShieldBubble") as ShieldBubble


func _duration() -> float:
	return Config.num("abilities.shield.duration_s")


## Steps the shield (and i-frames) `seconds` forward in DT ticks.
func _step(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds - 0.00001:
		_player.step_iframes(DT)
		_player.step_shield(DT)
		t += DT


func _raise(energy: int = 100) -> void:
	GameState.energy = energy
	assert_true(_player.try_shield(), "shield raised")


# --- Start state ------------------------------------------------------------------

func test_starts_unshielded_with_bubble_hidden() -> void:
	assert_false(_player.is_shielded())
	assert_eq(_player.shield_remaining(), 0.0)
	assert_true(_bubble() is ShieldBubble, "Player/ShieldBubble is a ShieldBubble")
	assert_false(_bubble().visible, "hidden by default")
	assert_false(_player.is_invulnerable())


# --- Activate / deny --------------------------------------------------------------

func test_activate_spends_cost_and_raises_shield() -> void:
	GameState.energy = 60
	assert_true(_player.try_shield())
	assert_eq(GameState.energy, 10)
	assert_signal_emitted_with_parameters(Events, "energy_changed", [10, 100])
	assert_true(_player.is_shielded())
	assert_almost_eq(_player.shield_remaining(), 4.0, 0.0001)
	assert_true(_bubble().visible, "bubble shown")
	assert_true(_player.is_invulnerable())
	assert_signal_not_emitted(Events, "ability_denied")
	assert_eq(_logged("[INFO][combat]").size(), 1, "one INFO line")


func test_exact_cost_activates() -> void:
	GameState.energy = 50
	assert_true(_player.try_shield())
	assert_eq(GameState.energy, 0)
	assert_true(_player.is_shielded())


func test_too_little_energy_is_denied() -> void:
	GameState.energy = 49
	assert_false(_player.try_shield())
	assert_eq(GameState.energy, 49, "nothing spent")
	assert_signal_emit_count(Events, "ability_denied", 1)
	assert_signal_emitted_with_parameters(Events, "ability_denied", [&"shield"])
	assert_signal_not_emitted(Events, "energy_changed")
	assert_false(_player.is_shielded())
	assert_false(_bubble().visible)
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"ability_denied"], "denied SFX played")
	assert_eq(_logged("[WARN][audio]"), [] as Array[String], "no unknown sfx warning")


func test_no_stacking_or_refresh() -> void:
	_raise()
	_step(3.0)
	GameState.energy = 100
	assert_false(_player.try_shield(), "already shielded")
	assert_eq(GameState.energy, 100, "nothing spent")
	assert_almost_eq(_player.shield_remaining(), 1.0, 0.001, "not refreshed")
	assert_signal_not_emitted(Events, "ability_denied")


func test_dead_ship_does_nothing() -> void:
	_player.hearts = 1
	_player.apply_damage(1, null)
	assert_true(_player.is_dead())
	GameState.energy = 100
	watch_signals(Events)
	assert_false(_player.try_shield())
	assert_eq(GameState.energy, 100)
	assert_signal_not_emitted(Events, "ability_denied")
	assert_signal_not_emitted(Events, "energy_changed")
	assert_false(_player.is_shielded())


func test_death_clears_the_shield() -> void:
	_raise()
	# Kill through the death path directly (damage is ignored while shielded).
	_player._die()
	assert_false(_player.is_shielded())
	assert_false(_bubble().visible)
	assert_eq(_player.shield_remaining(), 0.0)


# --- Invulnerability --------------------------------------------------------------

func test_damage_is_ignored_while_shielded() -> void:
	_raise()
	_player.apply_damage(1, null)
	_shoot(ENEMY_BULLET_SCENE)
	_shoot(NEEDLE_BOLT_SCENE)
	assert_eq(_player.hearts, _player.max_hearts, "hearts unchanged")
	assert_signal_not_emitted(Events, "player_hit")
	assert_signal_not_emitted(Events, "hearts_changed")


func test_small_and_medium_contact_destroyed_at_no_cost() -> void:
	_raise()
	var wasp: Wasp = _wasp()
	_player.on_contact(wasp)
	var lancer: Lancer = LANCER_SCENE.instantiate() as Lancer
	lancer.setup({"position": HAZARD_POS})
	add_child_autofree(lancer)
	lancer.set_physics_process(false)
	_player.on_contact(lancer)
	assert_true(wasp.is_dead(), "Wasp destroyed")
	assert_true(lancer.is_dead(), "Lancer destroyed")
	assert_eq(_player.hearts, _player.max_hearts)
	assert_signal_not_emitted(Events, "player_hit")


func test_large_contact_is_free_while_shielded() -> void:
	_raise()
	_player.on_contact(_bastion())
	_player.on_contact(_asteroid(&"large"))
	assert_eq(_player.hearts, _player.max_hearts)


func test_orbs_are_collected_while_shielded() -> void:
	_raise(50)
	var orb: EnergyOrb = ORB_SCENE.instantiate() as EnergyOrb
	orb.setup({"position": HAZARD_POS})
	add_child_autofree(orb)
	orb.set_physics_process(false)
	_player.on_contact(orb)
	assert_eq(GameState.energy, 10)


# --- Expiry -----------------------------------------------------------------------

func test_shield_expires_after_duration() -> void:
	_raise()
	_step(_duration() - 2.0 * DT)
	assert_true(_player.is_shielded(), "still up just before the end")
	_step(3.0 * DT)
	assert_false(_player.is_shielded(), "down after duration_s")
	assert_false(_bubble().visible, "bubble hidden")
	assert_false(_player.is_invulnerable())
	_player.apply_damage(1, null)
	assert_eq(_player.hearts, _player.max_hearts - 1, "damage lands again")


func test_bastion_overlapping_at_expiry_hits() -> void:
	_raise()
	var bastion: Bastion = _bastion()
	_player.on_contact(bastion)
	assert_eq(_player.hearts, 5)
	_step(_duration() - 2.0 * DT)
	assert_eq(_player.hearts, 5, "nothing while shielded")
	_step(3.0 * DT)
	assert_eq(_player.hearts, 5 - Config.int_("damage.contact_large_hearts"), "-2 on the expiry tick")
	assert_eq(_player.hearts, 3)
	assert_true(_player.is_invulnerable(), "i-frames start")
	assert_false(_player.is_shielded())


func test_bubble_blinks_in_the_last_window() -> void:
	_raise()
	var last_s: float = Config.num("player.shield_bubble.blink_last_s")
	_player.step_shield(_duration() - last_s - 0.01)
	assert_true(_bubble().visible, "0.76 s left: lit")
	_player.step_shield(0.01)
	assert_true(_bubble().visible, "0.75 s left: lit")
	_player.step_shield(0.05)
	assert_true(_bubble().visible, "0.70 s left: lit")
	_player.step_shield(0.10)
	assert_false(_bubble().visible, "0.60 s left: off")


func test_only_step_shield_counts_down() -> void:
	_raise()
	await wait_process_frames(3)
	assert_almost_eq(_player.shield_remaining(), _duration(), 0.0001, "only step_shield counts down")


func test_physics_process_runs_the_shield() -> void:
	_raise()
	var t: float = 0.0
	while t < _duration() + DT:
		_player._physics_process(DT)
		t += DT
	assert_false(_player.is_shielded(), "the physics tick ends the shield")


func test_shield_freezes_under_pause() -> void:
	_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	_player.set_physics_process(true)
	_raise()
	PauseArbiter.push(&"menu")
	await wait_physics_frames(10)
	assert_almost_eq(_player.shield_remaining(), _duration(), 0.0001, "frozen while paused")
	PauseArbiter.clear()
	await wait_physics_frames(10)
	assert_lt(_player.shield_remaining(), _duration(), "counts down again after unpause")
	assert_true(_player.is_shielded(), "still up after a short resume")


## Design Note: step_shield runs before the E read, so a shield that expires on
## this tick can be raised again on the same tick, at full duration.
func test_expiring_shield_can_be_reraised_on_the_same_tick() -> void:
	_raise()
	_player.step_shield(_duration() - DT)
	assert_true(_player.is_shielded(), "one DT left")
	GameState.energy = 100
	Input.action_press(&"ability_shield")
	_player._physics_process(DT)
	Input.action_release(&"ability_shield")
	assert_true(_player.is_shielded(), "up again")
	assert_almost_eq(_player.shield_remaining(), _duration(), 0.0001, "fresh full duration")
	assert_eq(GameState.energy, 50, "cost spent")


# --- Real input path --------------------------------------------------------------

func test_ability_shield_action_raises_the_shield() -> void:
	GameState.energy = 60
	_player.set_physics_process(true)
	Input.action_press(&"ability_shield")
	await wait_physics_frames(1)
	Input.action_release(&"ability_shield")
	assert_eq(GameState.energy, 10, "energy spent")
	assert_true(_player.is_shielded(), "shield up")


# --- Story 5.8: player_action ----------------------------------------------------

func test_shield_raised_emits_player_action_shield() -> void:
	_raise()
	assert_signal_emit_count(Events, "player_action", 1)
	assert_signal_emitted_with_parameters(Events, "player_action", [&"shield"])
	assert_false(_player.try_shield(), "already up")
	assert_signal_emit_count(Events, "player_action", 1, "an active shield emits nothing")


func test_denied_shield_emits_no_player_action() -> void:
	GameState.energy = 0
	assert_false(_player.try_shield())
	assert_signal_emit_count(Events, "ability_denied", 1)
	assert_signal_not_emitted(Events, "player_action")
