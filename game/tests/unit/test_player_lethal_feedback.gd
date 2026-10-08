extends GutTest
## DW-55 regression net for Player._on_damaged: a lethal hit plays only the
## PLAYER_DEATH tier (one SFX, player_death), never PLAYER_HIT as well; a
## non-lethal hit plays only PLAYER_HIT. Counts Audio starts through its
## start serial, since shake and hit-stop keep the strongest and hide a stray tier.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")

var _player: Player


func before_each() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_player.warp_mouse = _ignore_warp
	add_child_autofree(_player)
	_player.set_physics_process(false)


func after_each() -> void:
	Feedback.reset()
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_player = null


func _ignore_warp(_p: Vector2) -> void:
	pass


func test_lethal_hit_plays_only_the_death_sfx() -> void:
	_player.hearts = 1
	var before: int = Audio._next_serial
	_player.apply_damage(1, null)
	assert_true(_player.is_dead())
	assert_eq(Audio._next_serial - before, 1, "one SFX: PLAYER_DEATH only, no PLAYER_HIT")
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"player_death"])


func test_non_lethal_hit_plays_only_the_hit_sfx() -> void:
	var before: int = Audio._next_serial
	_player.apply_damage(1, null)
	assert_false(_player.is_dead())
	assert_eq(Audio._next_serial - before, 1, "one SFX: PLAYER_HIT")
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"player_hit"])
