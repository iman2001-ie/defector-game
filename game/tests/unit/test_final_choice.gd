extends GutTest
## FinalChoice (Story 7.5, UX "Final Choice"): the two-button view the
## CommsChannel shows after Isolde's lead-in. Layout from ui.final_choice (two
## 480 x 120 buttons, 48 px apart, centred on x 960, top at y 680), the labels
## as-is from the options, FOCUS_NONE, PROCESS_MODE_ALWAYS, a mouse-transparent
## root, the retry-prompt button styling (hover differs from normal), one
## `chosen` per showing, and the Comms/FinalChoice wiring in level.tscn.

const CHOICE_SCENE: PackedScene = preload("res://systems/comms/final_choice.tscn")
const THEME_PATH: String = "res://ui/theme/defector_theme.tres"
const OPTIONS: Array = [
	{"id": "surrender", "label": "OFFER SURRENDER", "next": "l3_isolde_refuse_surrender"},
	{"id": "destroy", "label": "DESTROY HER", "next": "l3_isolde_refuse_destroy"},
]

var _chosen: Array[StringName] = []


func before_each() -> void:
	_chosen.clear()


func after_each() -> void:
	Config.load_data()
	PauseArbiter.clear()


func _make() -> FinalChoice:
	var view: FinalChoice = CHOICE_SCENE.instantiate() as FinalChoice
	add_child_autofree(view)
	view.chosen.connect(func(id: StringName) -> void: _chosen.append(id))
	return view


func test_tuning() -> void:
	assert_eq(Config.num("ui.final_choice.button_w"), 480.0)
	assert_eq(Config.num("ui.final_choice.button_h"), 120.0)
	assert_eq(Config.num("ui.final_choice.button_gap_px"), 48.0)
	assert_eq(Config.num("ui.final_choice.buttons_top_y"), 680.0)
	var retry_font: int = (load(THEME_PATH) as Theme).get_font_size(&"button", &"RetryPrompt")
	assert_eq(Config.int_("ui.final_choice.font_px"), retry_font, "the retry prompt's button font size")


func test_hidden_at_start_mouse_transparent_and_always_processing() -> void:
	var view: FinalChoice = _make()
	assert_false(view.visible, "hidden at start")
	assert_false(view.is_shown())
	assert_eq(view.process_mode, Node.PROCESS_MODE_ALWAYS, "works while paused")
	assert_eq(view.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the root (and so the gap) ignores the mouse")
	assert_eq(view.get_child_count(), 2, "only the two buttons: nothing else catches a click")
	assert_not_null(view.theme, "the shared theme")
	if view.theme != null:
		assert_eq(view.theme.resource_path, THEME_PATH)
	for button: Button in view.buttons():
		assert_eq(button.focus_mode, Control.FOCUS_NONE, "%s: no focus" % button.name)
		assert_eq(button.mouse_filter, Control.MOUSE_FILTER_STOP, "%s takes the click" % button.name)


func test_layout_is_a_centred_pair_below_the_story_panel() -> void:
	var view: FinalChoice = _make()
	var rects: Array[Rect2] = FinalChoice.button_rects(1920.0, Vector2(480, 120), 48.0, 680.0)
	assert_eq(rects, [Rect2(456, 680, 480, 120), Rect2(984, 680, 480, 120)] as Array[Rect2])
	var buttons: Array[Button] = view.buttons()
	assert_eq(buttons[0].get_rect(), Rect2(456, 680, 480, 120), "left button")
	assert_eq(buttons[1].get_rect(), Rect2(984, 680, 480, 120), "right button")
	assert_almost_eq((buttons[0].get_rect().end.x + buttons[1].get_rect().position.x) / 2.0, 960.0, 0.001, "centred on x 960")
	assert_eq(buttons[1].get_rect().position.x - buttons[0].get_rect().end.x, 48.0, "48 px apart")
	var panel_bottom: float = Config.num("ui.comms_panel.y") + Config.num("ui.comms_panel.h")
	assert_eq(buttons[0].get_rect().position.y - panel_bottom, 80.0, "80 px below the story panel (UX)")


func test_show_options_uses_the_labels_as_is() -> void:
	var view: FinalChoice = _make()
	view.show_options(OPTIONS)
	assert_true(view.visible)
	assert_true(view.is_shown())
	assert_eq(view.buttons()[0].text, "OFFER SURRENDER")
	assert_eq(view.buttons()[1].text, "DESTROY HER")
	assert_eq(view.option_ids(), [&"surrender", &"destroy"] as Array[StringName])
	view.show_options([{"id": "destroy", "label": "Destroy her", "next": "x"}, {"id": "surrender", "label": "Spare", "next": "y"}])
	assert_eq(view.buttons()[0].text, "Destroy her", "no case change")
	assert_eq(view.option_ids(), [&"destroy", &"surrender"] as Array[StringName], "data order")


func test_a_click_chooses_once_per_showing() -> void:
	var view: FinalChoice = _make()
	view.buttons()[0].pressed.emit()
	assert_eq(_chosen, [] as Array[StringName], "nothing while hidden")
	view.show_options(OPTIONS)
	view.buttons()[1].pressed.emit()
	assert_eq(_chosen, [&"destroy"] as Array[StringName])
	view.buttons()[0].pressed.emit()
	assert_eq(_chosen, [&"destroy"] as Array[StringName], "once per showing")
	view.hide_options()
	assert_false(view.visible)
	view.show_options(OPTIONS)
	view.buttons()[0].pressed.emit()
	assert_eq(_chosen, [&"destroy", &"surrender"] as Array[StringName], "a new showing chooses again")


func test_buttons_use_the_retry_prompt_styles() -> void:
	var view: FinalChoice = _make()
	var theme: Theme = load(THEME_PATH) as Theme
	var normal: StyleBox = theme.get_stylebox(&"button_normal", &"FinalChoice")
	var hover: StyleBox = theme.get_stylebox(&"button_hover", &"FinalChoice")
	assert_eq(normal, theme.get_stylebox(&"button_normal", &"RetryPrompt"), "the retry prompt's normal box")
	assert_eq(hover, theme.get_stylebox(&"button_hover", &"RetryPrompt"), "the retry prompt's hover box")
	assert_ne(normal, hover, "hover differs from normal")
	var normal_flat: StyleBoxFlat = normal as StyleBoxFlat
	var hover_flat: StyleBoxFlat = hover as StyleBoxFlat
	assert_not_null(normal_flat)
	assert_not_null(hover_flat)
	if normal_flat != null and hover_flat != null:
		assert_eq(normal_flat.border_width_top, 1, "1 px border")
		assert_true(normal_flat.border_color.is_equal_approx(Color("#2A3B5C")), "border colour")
		assert_true(hover_flat.border_color.is_equal_approx(Color("#22E6FF")), "coalition border on hover")
		assert_gt(hover_flat.shadow_size, 0, "a glow on hover")
		assert_ne(normal_flat.border_color, hover_flat.border_color)
	var text: Color = theme.get_color(&"text", &"FinalChoice")
	for button: Button in view.buttons():
		assert_eq(button.get_theme_stylebox(&"normal"), normal, "%s normal" % button.name)
		assert_eq(button.get_theme_stylebox(&"hover"), hover, "%s hover" % button.name)
		assert_ne(button.get_theme_stylebox(&"hover"), button.get_theme_stylebox(&"normal"))
		assert_eq(button.get_theme_color(&"font_color"), text)
		assert_eq(button.get_theme_font_size(&"font_size"), Config.int_("ui.final_choice.font_px"))


func test_no_timer() -> void:
	var view: FinalChoice = _make()
	view.show_options(OPTIONS)
	await wait_seconds(0.5)
	assert_true(view.visible, "still up")
	assert_eq(_chosen, [] as Array[StringName], "nothing chosen on its own")
	for child: Node in view.get_children():
		assert_false(child is Timer, "no Timer child")


func test_level_wires_comms_final_choice_after_the_panel() -> void:
	var level: Node = (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
	var comms: Node = level.get_node("Comms")
	var view: FinalChoice = comms.get_node_or_null("FinalChoice") as FinalChoice
	assert_not_null(view, "Comms/FinalChoice is a FinalChoice")
	if view != null:
		assert_gt(view.get_index(), comms.get_node("CommsPanel").get_index(), "after CommsPanel, so it draws on top")
		assert_eq((comms.get_node("CommsChannel") as CommsChannel).final_choice, view, "wired to the channel")
	level.free()
