extends GutTest
## PlayerWeapons on its own: laser rate, bolt params, straight-up missile and cooldown,
## no-spawner gating, and its place in the Player scene.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")
const DT: float = 1.0 / 60.0
const SHIP: Vector2 = Vector2(960, 900)
const MUZZLE_OFFSET: Vector2 = Vector2(0, -40)

var _spawner: Spawner
var _projectiles: Node2D
var _muzzle: Marker2D
var _flash: Node2D
var _weapons: PlayerWeapons


func before_each() -> void:
	var world: Node2D = Node2D.new()
	_projectiles = Node2D.new()
	_projectiles.name = "Projectiles"
	world.add_child(_projectiles)
	for container: String in ["Enemies", "Asteroids"]:
		var node: Node2D = Node2D.new()
		node.name = container
		world.add_child(node)
	add_child_autofree(world)
	_spawner = Spawner.new()
	_spawner.world = world
	add_child_autofree(_spawner)
	_weapons = _make_weapons()
	_weapons.set_spawner(_spawner)
	watch_signals(Events)


func after_each() -> void:
	Feedback.reset()
	_spawner = null
	_projectiles = null
	_muzzle = null
	_flash = null
	_weapons = null


## A bare ship (Node2D) with a Muzzle, a MuzzleFlash and a Weapons component.
func _make_weapons() -> PlayerWeapons:
	var ship: Node2D = Node2D.new()
	ship.position = SHIP
	_muzzle = Marker2D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = MUZZLE_OFFSET
	ship.add_child(_muzzle)
	_flash = Node2D.new()
	_flash.name = "MuzzleFlash"
	_flash.visible = true
	_muzzle.add_child(_flash)
	var weapons: PlayerWeapons = PlayerWeapons.new()
	weapons.name = "Weapons"
	weapons.muzzle = ^"../Muzzle"
	weapons.muzzle_flash = ^"../Muzzle/MuzzleFlash"
	ship.add_child(weapons)
	add_child_autofree(ship)
	return weapons


func _missiles() -> Array[Missile]:
	var out: Array[Missile] = []
	for child: Node in _projectiles.get_children():
		if child is Missile:
			out.append(child as Missile)
	return out


func test_flash_hidden_on_ready() -> void:
	assert_false(_flash.visible)


func test_laser_rate_ten_per_second() -> void:
	for i: int in 60:
		_weapons.step_fire(true, DT)
	assert_eq(_projectiles.get_child_count(), 10, "60 ticks -> 10 bolts")


func test_bolt_at_muzzle_with_tuning_params_and_flash() -> void:
	_weapons.step_fire(true, DT)
	assert_eq(_projectiles.get_child_count(), 1)
	if _projectiles.get_child_count() != 1:
		return
	var bolt: Projectile = _projectiles.get_child(0) as Projectile
	assert_true(bolt is LaserBolt)
	assert_eq(bolt.global_position, SHIP + MUZZLE_OFFSET, "spawned at the muzzle")
	assert_eq(bolt.velocity, Vector2(0, -Config.num("weapons.laser.speed_px_s")))
	assert_eq(bolt.damage, Config.int_("weapons.laser.damage"))
	assert_true(_flash.visible, "flash shown on the shot")


func test_missile_straight_up_then_cooldown_drops_press() -> void:
	_weapons.step_missile(true, DT)
	var missiles: Array[Missile] = _missiles()
	assert_eq(missiles.size(), 1, "one missile")
	if missiles.size() != 1:
		return
	var missile: Missile = missiles[0]
	assert_eq(missile.global_position, SHIP + MUZZLE_OFFSET, "spawned at the muzzle")
	assert_eq(missile.velocity, Vector2.UP * Config.num("weapons.missile.speed_px_s"))
	assert_eq(missile.damage, Config.int_("weapons.missile.damage"))
	assert_signal_emit_count(Events, "missile_cooldown_changed", 1)
	assert_eq(float(get_signal_parameters(Events, "missile_cooldown_changed", 0)[0]), 1.0,
		"cooldown starts full")
	_weapons.step_missile(true, DT)
	assert_eq(_missiles().size(), 1, "press on cooldown is dropped")


func test_no_spawner_fires_nothing() -> void:
	var lone: PlayerWeapons = _make_weapons()
	for i: int in 60:
		lone.step_fire(true, DT)
	lone.step_missile(true, DT)
	assert_eq(_projectiles.get_child_count(), 0)
	assert_signal_not_emitted(Events, "missile_cooldown_changed")
	assert_false(_flash.visible, "flash stays hidden")


func test_missing_muzzle_logs_and_fires_nothing() -> void:
	var ship: Node2D = Node2D.new()
	var flash: Node2D = Node2D.new()
	flash.name = "MuzzleFlash"
	ship.add_child(flash)
	var broken: PlayerWeapons = PlayerWeapons.new()
	broken.muzzle = ^"../NoSuchMuzzle"
	broken.muzzle_flash = ^"../MuzzleFlash"
	ship.add_child(broken)
	add_child_autofree(ship)
	assert_push_error("missing its muzzle")
	broken.set_spawner(_spawner)
	for i: int in 60:
		broken.step_fire(true, DT)
	broken.step_missile(true, DT)
	assert_eq(_projectiles.get_child_count(), 0)
	assert_signal_not_emitted(Events, "missile_cooldown_changed")


func test_player_scene_owns_weapons() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	var weapons: Node = player.get_node_or_null(^"Weapons")
	assert_not_null(weapons)
	assert_true(weapons is PlayerWeapons, "Weapons is a PlayerWeapons")
	if not weapons is PlayerWeapons:
		return
	var typed: PlayerWeapons = weapons as PlayerWeapons
	assert_eq(typed.muzzle, ^"../Muzzle")
	assert_eq(typed.muzzle_flash, ^"../Muzzle/MuzzleFlash")
