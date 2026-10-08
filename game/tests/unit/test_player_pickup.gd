extends GutTest
## Player orb pickup (Story 3.3): on_contact collects an EnergyOrb at no heart
## cost, even while invulnerable, and never remembers it; a dead ship collects
## nothing. One real-physics test lets the hurtbox overlap the orb.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")
const ORB_SCENE: PackedScene = preload("res://entities/pickups/energy_orb.tscn")

var _player: Player


func before_each() -> void:
	GameState.energy = 0
	watch_signals(Events)
	_player = PLAYER_SCENE.instantiate() as Player
	_player.warp_mouse = _ignore_warp
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.global_position = Vector2(400, 900)


func after_each() -> void:
	GameState.energy = 0
	Feedback.reset()
	PauseArbiter.clear()
	_player = null


func _ignore_warp(_p: Vector2) -> void:
	pass


## An orb far from the player (no real overlap) with physics off.
func _orb(pos: Vector2 = Vector2(1500, 150)) -> EnergyOrb:
	var orb: EnergyOrb = ORB_SCENE.instantiate() as EnergyOrb
	orb.setup({"position": pos})
	add_child_autofree(orb)
	orb.set_physics_process(false)
	return orb


func test_contact_collects_the_orb_at_no_heart_cost() -> void:
	var orb: EnergyOrb = _orb()
	_player.on_contact(orb)
	assert_eq(GameState.energy, 10)
	assert_signal_emitted_with_parameters(Events, "energy_changed", [10, 100])
	assert_true(orb.is_queued_for_deletion(), "orb freed")
	assert_eq(_player.hearts, _player.max_hearts, "hearts unchanged")
	assert_signal_not_emitted(Events, "player_hit")
	assert_false(_player.is_invulnerable(), "no i-frames")
	assert_false(_player._contacts.has(orb), "never remembered")


func test_collects_while_invulnerable() -> void:
	_player.apply_damage(1, null)
	Feedback.reset()
	assert_true(_player.is_invulnerable())
	_player.on_contact(_orb())
	assert_eq(GameState.energy, 10, "i-frames don't block pickups")
	var debug_orb: EnergyOrb = _orb()
	_player.debug_invincible = true
	_player.on_contact(debug_orb)
	assert_eq(GameState.energy, 20, "debug_invincible doesn't block pickups")


func test_two_orbs_add_twenty() -> void:
	_player.on_contact(_orb())
	_player.on_contact(_orb())
	assert_eq(GameState.energy, 20)


func test_dead_ship_collects_nothing() -> void:
	_player.apply_damage(_player.hearts, null)
	Feedback.reset()
	var orb: EnergyOrb = _orb()
	_player.on_contact(orb)
	assert_eq(GameState.energy, 0)
	assert_false(orb.is_queued_for_deletion())


func test_real_overlap_collects() -> void:
	var orb: EnergyOrb = _orb(_player.global_position)
	await wait_physics_frames(3)
	assert_eq(GameState.energy, 10, "the hurtbox picked the orb up")
	assert_true(not is_instance_valid(orb) or orb.is_queued_for_deletion())
	assert_eq(_player.hearts, _player.max_hearts)
