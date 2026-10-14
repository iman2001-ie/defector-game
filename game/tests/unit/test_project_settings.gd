extends GutTest
## Pins project.godot (settings, input map, layer names, autoload order) and the Events catalogue.

const KEY_ACTIONS: Dictionary = {
	"ability_shield": KEY_E,
	"ability_barrage": KEY_Q,
	"pause": KEY_ESCAPE,
	"toggle_fullscreen": KEY_F11,
	"debug_overlay": KEY_F1,
	"debug_invincible": KEY_F2,
	"debug_resolve_wave": KEY_F3,
	"debug_add_energy": KEY_F4,
	"debug_reload_data": KEY_F5,
	"debug_skip_to_boss": KEY_F6,
	"debug_unlock_all": KEY_F7,
}
const MOUSE_ACTIONS: Dictionary = {
	"fire_laser": MOUSE_BUTTON_LEFT,
	"fire_missile": MOUSE_BUTTON_RIGHT,
	"comms_advance": MOUSE_BUTTON_LEFT,
}
const LAYERS: Array[String] = [
	"player", "player_shots", "enemies", "enemy_shots",
	"asteroids", "pickups", "convoy", "allies",
]
const AUTOLOADS: Array[String] = [
	"Log", "Events", "Config", "GameState", "SaveManager", "PauseArbiter", "Audio", "Feedback", "EntityRegistry", "SceneRouter",
]

## Signal name -> argument types, per the architecture's Events catalogue.
const EVENTS: Dictionary = {
	"hearts_changed": [TYPE_INT, TYPE_INT],
	"player_hit": [TYPE_VECTOR2],
	"player_died": [],
	"energy_changed": [TYPE_INT, TYPE_INT],
	"ability_denied": [TYPE_STRING_NAME],
	"missile_cooldown_changed": [TYPE_FLOAT],
	"player_moved": [TYPE_FLOAT],
	"player_action": [TYPE_STRING_NAME],
	"enemy_killed": [TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_BOOL],
	"asteroid_destroyed": [TYPE_STRING_NAME, TYPE_VECTOR2],
	"level_started": [TYPE_INT],
	"level_intro_started": [TYPE_INT, TYPE_STRING, TYPE_FLOAT],
	"wave_started": [TYPE_INT, TYPE_INT],
	"wave_progress_changed": [TYPE_INT, TYPE_FLOAT],
	"wave_cleared": [TYPE_INT],
	"level_cleared": [TYPE_INT],
	"level_failed": [TYPE_STRING_NAME],
	"convoy_hp_changed": [TYPE_INT, TYPE_INT],
	"boss_started": [],
	"boss_hp_changed": [TYPE_INT, TYPE_INT, TYPE_INT],
	"boss_phase_changed": [TYPE_INT],
	"boss_defeated": [],
	"comms_sequence_requested": [TYPE_STRING_NAME],
	"comms_sequence_finished": [TYPE_STRING_NAME],
	"comms_line_shown": [TYPE_STRING_NAME, TYPE_STRING, TYPE_STRING_NAME],
	"final_choice_made": [TYPE_STRING_NAME],
	"story_event_requested": [TYPE_STRING_NAME],
	"hint_requested": [TYPE_STRING_NAME],
}
## Project setting -> expected value (Story 1.1 project.godot task, the clear colour, the Story 4.1 boot main scene, and the Story 4.5 windowed size override).
const SETTINGS: Dictionary = {
	"application/config/name": "DEFECTOR",
	"application/config/use_custom_user_dir": true,
	"application/config/custom_user_dir_name": "DEFECTOR",
	"rendering/renderer/rendering_method": "forward_plus",
	"rendering/viewport/hdr_2d": true,
	"display/window/size/viewport_width": 1920,
	"display/window/size/viewport_height": 1080,
	"display/window/size/window_width_override": 1280,
	"display/window/size/window_height_override": 720,
	"display/window/size/mode": 3,
	"display/window/stretch/mode": "canvas_items",
	"display/window/stretch/aspect": "keep",
	"debug/file_logging/enable_file_logging": true,
	"debug/file_logging/enable_file_logging.pc": true,
	"debug/gdscript/warnings/untyped_declaration": 1,
	"application/run/main_scene": "res://scenes/boot/boot.tscn",
	"rendering/environment/defaults/default_clear_color": Color(0.0196, 0.0275, 0.0588, 1),
}


func test_action_count() -> void:
	assert_eq(KEY_ACTIONS.size() + MOUSE_ACTIONS.size(), 14)


func test_key_actions_bound_by_physical_keycode() -> void:
	for action: String in KEY_ACTIONS:
		assert_true(InputMap.has_action(action), "action %s exists" % action)
		if not InputMap.has_action(action):
			continue
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		assert_eq(events.size(), 1, "%s has one binding" % action)
		var key: InputEventKey = events[0] as InputEventKey
		assert_not_null(key, "%s is a key binding" % action)
		if key != null:
			assert_eq(key.physical_keycode, KEY_ACTIONS[action], "%s physical keycode" % action)


func test_mouse_actions_bound_to_buttons() -> void:
	for action: String in MOUSE_ACTIONS:
		assert_true(InputMap.has_action(action), "action %s exists" % action)
		if not InputMap.has_action(action):
			continue
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		assert_eq(events.size(), 1, "%s has one binding" % action)
		var button: InputEventMouseButton = events[0] as InputEventMouseButton
		assert_not_null(button, "%s is a mouse binding" % action)
		if button != null:
			assert_eq(button.button_index, MOUSE_ACTIONS[action], "%s button index" % action)


func test_layer_names() -> void:
	for i: int in LAYERS.size():
		var setting: String = "layer_names/2d_physics/layer_%d" % (i + 1)
		assert_eq(ProjectSettings.get_setting(setting, ""), LAYERS[i], setting)


func test_autoloads_in_order() -> void:
	var names: Array[String] = []
	for prop: Dictionary in ProjectSettings.get_property_list():
		var prop_name: String = prop.name
		if prop_name.begins_with("autoload/"):
			names.append(prop_name.trim_prefix("autoload/"))
	assert_eq(names, AUTOLOADS)


func test_display_rendering_and_debug_settings() -> void:
	for setting: String in SETTINGS:
		assert_eq(ProjectSettings.get_setting(setting), SETTINGS[setting], setting)


func test_gut_plugin_enabled() -> void:
	var enabled: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	assert_true(enabled.has("res://addons/gut/plugin.cfg"), "GUT enabled in [editor_plugins]")


func test_events_catalogue_signals_and_arg_types() -> void:
	var declared: Dictionary = {}
	for sig: Dictionary in (Events.get_script() as Script).get_script_signal_list():
		var types: Array = []
		for arg: Dictionary in sig.args:
			types.append(arg.type)
		declared[sig.name] = types
	assert_eq(declared.size(), EVENTS.size(), "signal count")
	for sig_name: String in EVENTS:
		assert_true(declared.has(sig_name), "Events.%s exists" % sig_name)
		assert_eq(declared.get(sig_name, []), EVENTS[sig_name], "Events.%s arg types" % sig_name)


func test_events_declares_no_functions() -> void:
	assert_eq((Events.get_script() as Script).get_script_method_list().size(), 0)
