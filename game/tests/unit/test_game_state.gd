extends GutTest
## GameState (Story 3.2): the run-state autoload holds energy, current_level_id
## and is_retry. Story 3.3: the energy API (max_energy, add_energy clamp and
## energy_changed, emit_energy).

const GAME_STATE_SCRIPT: GDScript = preload("res://autoloads/game_state.gd")


func before_each() -> void:
	watch_signals(Events)


func after_each() -> void:
	Config.load_data()
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


# --- Energy (Story 3.3) ------------------------------------------------------------

func test_max_energy_from_tuning() -> void:
	assert_eq(GameState.max_energy(), Config.int_("energy.max"))
	assert_eq(GameState.max_energy(), 100)


func test_add_energy_adds_and_emits() -> void:
	assert_eq(GameState.add_energy(10), 10)
	assert_eq(GameState.energy, 10)
	assert_signal_emitted_with_parameters(Events, "energy_changed", [10, 100])


func test_add_energy_caps_at_max() -> void:
	GameState.energy = 95
	assert_eq(GameState.add_energy(10), 100)
	assert_signal_emitted_with_parameters(Events, "energy_changed", [100, 100])


func test_add_energy_at_the_cap_still_emits() -> void:
	GameState.energy = 100
	assert_eq(GameState.add_energy(10), 100)
	assert_signal_emit_count(Events, "energy_changed", 1)


func test_add_energy_floors_at_zero() -> void:
	GameState.energy = 30
	assert_eq(GameState.add_energy(-50), 0)
	assert_signal_emitted_with_parameters(Events, "energy_changed", [0, 100])


func test_add_energy_follows_the_tuning_max() -> void:
	(Config.tuning["energy"] as Dictionary)["max"] = 60
	assert_eq(GameState.add_energy(100), 60)
	assert_signal_emitted_with_parameters(Events, "energy_changed", [60, 60])


func test_emit_energy_announces_the_current_value() -> void:
	GameState.energy = 30
	GameState.emit_energy()
	assert_eq(GameState.energy, 30, "unchanged")
	assert_signal_emitted_with_parameters(Events, "energy_changed", [30, 100])
