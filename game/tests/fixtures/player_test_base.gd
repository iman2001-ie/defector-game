extends GutTest
## Shared base for the Player GUT scripts (DW-56): the hazard scene consts, the
## log capture, the default player and the hazard factories. Not a test script
## itself (GUT only collects `test_`-prefixed files) and has no class_name.
##
## Extend it by path: `extends "res://tests/fixtures/player_test_base.gd"`.
## Don't redeclare a member below (GDScript rejects shadowing). To customise
## setup, override before_each / after_each and call `super()`, or call
## `_begin()` and `_make_player(pos, warp)` yourself when the order matters
## (warp_mouse must be set before the player enters the tree).

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")
const WASP_SCENE: PackedScene = preload("res://entities/enemies/wasp/wasp.tscn")
const BASTION_SCENE: PackedScene = preload("res://entities/enemies/bastion/bastion.tscn")
const ASTEROID_SCENE: PackedScene = preload("res://entities/asteroids/asteroid.tscn")
const DT: float = 1.0 / 60.0
## Far from the player, so no real overlap fires (hazards share it; their mask is 0).
const HAZARD_POS: Vector2 = Vector2(1500, 150)
const PLAYER_POS: Vector2 = Vector2(200, 900)

var _player: Player
var _lines: Array[String] = []


func before_each() -> void:
	_begin()
	_player = _make_player(PLAYER_POS)


func after_each() -> void:
	Log.sink = Callable()
	GameState.energy = 0
	Feedback.reset()
	PauseArbiter.clear()
	_player = null


## Common per-test state: log capture on, energy 0, Events watched. No player.
func _begin() -> void:
	_lines.clear()
	Log.sink = _capture
	GameState.energy = 0
	watch_signals(Events)


## A player at `pos` with physics off. An invalid `warp` means _ignore_warp.
## The warp is set before add_child, because Player._ready replaces an invalid one.
func _make_player(pos: Vector2, warp: Callable = Callable()) -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.warp_mouse = warp if warp.is_valid() else _ignore_warp
	add_child_autofree(player)
	player.set_physics_process(false)
	player.global_position = pos
	return player


func _ignore_warp(_p: Vector2) -> void:
	pass


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _logged(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.begins_with(prefix):
			out.append(line)
	return out


func _wasp() -> Wasp:
	var wasp: Wasp = WASP_SCENE.instantiate() as Wasp
	wasp.setup({"position": HAZARD_POS})
	add_child_autofree(wasp)
	wasp.set_physics_process(false)
	return wasp


func _bastion() -> Bastion:
	var bastion: Bastion = BASTION_SCENE.instantiate() as Bastion
	bastion.setup({"position": HAZARD_POS})
	add_child_autofree(bastion)
	bastion.set_physics_process(false)
	return bastion


func _asteroid(size: StringName) -> Asteroid:
	var rock: Asteroid = ASTEROID_SCENE.instantiate() as Asteroid
	rock.setup({"size": size, "position": HAZARD_POS})
	add_child_autofree(rock)
	rock.set_physics_process(false)
	return rock


## A real enemy projectile (no spawner) hitting the player.
func _shoot(scene: PackedScene) -> void:
	var shot: Projectile = scene.instantiate() as Projectile
	shot.setup({"position": HAZARD_POS, "velocity": Vector2(0, 100), "damage": Config.int_("damage.bullet_hearts")})
	add_child_autofree(shot)
	shot.set_physics_process(false)
	shot._on_area_entered(_player)
