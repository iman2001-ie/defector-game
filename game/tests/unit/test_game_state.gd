extends GutTest
## GameState (Story 3.2): the run-state autoload holds energy, current_level_id
## and is_retry, with no logic.

const GAME_STATE_SCRIPT: GDScript = preload("res://autoloads/game_state.gd")


func after_each() -> void:
	GameState.energy = 0
	GameState.current_level_id = ""
	GameState.is_retry = false


func test_defaults() -> void:
	var state: Node = GAME_STATE_SCRIPT.new()
	assert_eq(state.get("energy"), 0)
	assert_eq(state.get("current_level_id"), "")
	assert_eq(state.get("is_retry"), false)
	state.free()


func test_field_types() -> void:
	assert_typeof(GameState.energy, TYPE_INT)
	assert_typeof(GameState.current_level_id, TYPE_STRING)
	assert_typeof(GameState.is_retry, TYPE_BOOL)


func test_fields_are_writable() -> void:
	GameState.energy = 40
	GameState.current_level_id = "dev"
	GameState.is_retry = true
	assert_eq(GameState.energy, 40)
	assert_eq(GameState.current_level_id, "dev")
	assert_true(GameState.is_retry)


func test_autoload_is_a_node_under_root() -> void:
	assert_eq(GameState.get_parent(), get_tree().root)
	assert_eq(String(GameState.name), "GameState")
