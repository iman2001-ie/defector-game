extends GutTest
## CommsChannel (Story 5.1): story sequences push the `story` pause, play the
## comms-open SFX and drive the CommsPanel; LMB (`comms_advance`) presses and
## releases are consumed, a press arms and an armed release completes or
## advances; after the last line the pause pops before `finished`. Unknown and
## combat ids finish deferred with no pause; a second story queues.
## Input goes through get_viewport().push_input like a real click. Under GUT
## the root viewport reports a mouse button as handled even when no node
## consumed it, so is_input_handled() can't tell who did: a Probe node added
## before the channel (so its _unhandled_input runs after the channel's)
## records the events that got past the channel.


class Probe:
	extends Node
	var seen: int = 0

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			seen += 1

const PANEL_SCENE: PackedScene = preload("res://systems/comms/comms_panel.tscn")
const MENU_SCENE: PackedScene = preload("res://ui/menus/pause_menu.tscn")
const CHANNEL_DIR: String = "res://tests/fixtures/dialogue/channel/"
const CLICK_AT: Vector2 = Vector2(960, 900)

var _channel: CommsChannel
var _panel: CommsPanel
var _finished: Array[StringName] = []
## Snapshot taken inside each `finished` handler: [story active, panel visible].
var _at_finish: Array = []
var _lines: Array[String] = []
var _probe: Probe
## The viewport mouse before the test, restored after it (other suites read it).
var _mouse_before: Vector2 = Vector2.ZERO


func before_each() -> void:
	_mouse_before = get_viewport().get_mouse_position()
	_finished.clear()
	_at_finish.clear()
	_lines.clear()
	Config.load_data(Config.DEFAULT_TUNING_PATH, Config.DEFAULT_FLAGS_PATH, CHANNEL_DIR)
	Events.comms_sequence_finished.connect(_on_finished)
	Log.sink = _capture
	_probe = Probe.new()
	add_child_autofree(_probe)
	_panel = PANEL_SCENE.instantiate() as CommsPanel
	add_child_autofree(_panel)
	_channel = CommsChannel.new()
	_channel.panel = _panel
	add_child_autofree(_channel)


func after_each() -> void:
	Events.comms_sequence_finished.disconnect(_on_finished)
	Log.sink = Callable()
	_channel = null
	_panel = null
	_probe = null
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = _mouse_before
	motion.global_position = _mouse_before
	get_viewport().push_input(motion, true)
	Config.load_data()
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_finished(id: StringName) -> void:
	_finished.append(id)
	_at_finish.append([PauseArbiter.has_reason(&"story"), _panel.visible if _panel != null else false])


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _count_lines(text: String) -> int:
	var n: int = 0
	for line: String in _lines:
		if line == text:
			n += 1
	return n


func _mouse(pressed: bool) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = CLICK_AT
	event.global_position = CLICK_AT
	return event


## Pushes one LMB press or release through the viewport; returns whether the
## channel consumed it (set_input_as_handled stops it before the Probe).
func _push(pressed: bool) -> bool:
	var before: int = _probe.seen
	get_viewport().push_input(_mouse(pressed), true)
	return _probe.seen == before


## Press then release; returns [press handled, release handled].
func _click() -> Array[bool]:
	var out: Array[bool] = []
	out.append(_push(true))
	out.append(_push(false))
	return out


func _request(id: StringName) -> void:
	Events.comms_sequence_requested.emit(id)


func _text() -> Label:
	return _panel.get_node("Panel/Text") as Label


func _name() -> String:
	return (_panel.get_node("Panel/Name") as Label).text


## Clicks through the rest of the current sequence (complete + advance per line).
func _click_to_end() -> void:
	for i: int in 20:
		if not _channel.is_showing():
			return
		_click()


# --- Starting --------------------------------------------------------------------------

func test_story_starts() -> void:
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	_request(&"story_a")
	assert_true(PauseArbiter.has_reason(&"story"), "story reason active")
	assert_true(get_tree().paused, "tree paused")
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "cursor visible")
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"comms_open"], "comms_open played")
	assert_true(_panel.visible, "panel open")
	assert_true((_panel.get_node("Dim") as Control).is_visible_in_tree(), "dim shown")
	assert_eq(_name(), "TAREK", "line 0 speaker")
	assert_eq(_text().text, "Forty-five characters exactly, General. Okay.")
	assert_eq(_text().visible_characters, 0, "typing from 0")
	assert_true(_panel.is_typing())
	assert_eq(_channel.current_sequence(), &"story_a")
	assert_true(_channel.is_showing())
	assert_eq(_channel.line_index(), 0)
	assert_eq(_count_lines("[INFO][comms] Story sequence 'story_a' started (3 lines)"), 1)
	assert_eq(_finished, [] as Array[StringName])


func test_idle_accessors() -> void:
	assert_eq(_channel.current_sequence(), &"")
	assert_false(_channel.is_showing())
	assert_eq(_channel.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_typing_reaches_the_end_in_about_a_second() -> void:
	_request(&"story_a")
	_panel._tween.custom_step(0.89)
	assert_true(_panel.is_typing(), "not done before ~0.9 s")
	_panel._tween.custom_step(0.12)
	assert_false(_panel.is_typing(), "45 chars at 45/s done by ~1.0 s")
	assert_eq(_text().visible_characters, -1)


# --- Clicking --------------------------------------------------------------------------

func test_click_while_typing_completes_the_line() -> void:
	_request(&"story_a")
	var handled: Array[bool] = _click()
	assert_eq(handled, [true, true] as Array[bool], "press and release consumed")
	assert_false(_panel.is_typing(), "line complete")
	assert_eq(_text().visible_characters, -1)
	assert_eq(_channel.line_index(), 0, "same line")
	assert_true(get_tree().paused, "still paused")


func test_click_on_a_complete_line_advances() -> void:
	_request(&"story_a")
	_click()
	var handled: Array[bool] = _click()
	assert_eq(handled, [true, true] as Array[bool])
	assert_eq(_channel.line_index(), 1, "next line")
	assert_eq(_name(), "VALE")
	assert_true(_panel.is_typing(), "next line typing")
	assert_false((_panel.get_node("Panel/Portrait") as Control).visible, "no-portrait variant")
	assert_eq(_text().get_rect().size.x, 1036.0, "full-width text block")


func test_press_alone_does_not_advance() -> void:
	_request(&"story_a")
	_panel.complete_line()
	assert_true(_push(true), "press consumed")
	assert_eq(_channel.line_index(), 0, "press only arms")
	assert_true(_push(false), "release consumed")
	assert_eq(_channel.line_index(), 1, "release advances")


func test_last_release_finishes() -> void:
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	_request(&"story_a")
	watch_signals(PauseArbiter)
	for i: int in 2:
		_click()
		_click()
	assert_eq(_channel.line_index(), 2, "on the last line")
	_click()
	assert_true(_panel.is_typing() == false)
	assert_true(_push(true), "last press consumed")
	assert_true(get_tree().paused, "press doesn't lift the pause")
	assert_eq(_finished, [] as Array[StringName])
	assert_true(_push(false), "last release consumed")
	assert_false(_panel.visible, "panel hidden")
	assert_false(PauseArbiter.has_reason(&"story"), "story popped")
	assert_false(get_tree().paused, "tree unpaused")
	assert_eq(PauseArbiter.current_mouse_mode(), Input.MOUSE_MODE_CONFINED_HIDDEN, "gameplay cursor back")
	assert_signal_emit_count(PauseArbiter, "resumed", 1)
	assert_eq(_finished, [&"story_a"] as Array[StringName], "finished once")
	assert_eq(_at_finish, [[false, false]], "pause popped and panel closed before finished")
	assert_eq(_channel.current_sequence(), &"")
	assert_eq(_count_lines("[INFO][comms] Story sequence 'story_a' finished"), 1)
	assert_false(_push(true), "idle: clicks are not consumed")
	_push(false)


func test_unarmed_release_is_consumed_and_ignored() -> void:
	_request(&"story_a")
	assert_true(_push(false), "release consumed")
	assert_true(_panel.is_typing(), "nothing completed")
	assert_eq(_channel.line_index(), 0, "nothing advanced")
	_panel.complete_line()
	assert_true(_push(false), "second unarmed release consumed")
	assert_eq(_channel.line_index(), 0, "still nothing advanced")


func test_menu_over_story_ignores_clicks() -> void:
	_request(&"story_a")
	PauseArbiter.push(&"menu")
	var handled: Array[bool] = _click()
	assert_eq(handled, [false, false] as Array[bool], "not handled by the channel")
	assert_true(_panel.is_typing(), "nothing completed")
	assert_eq(_channel.line_index(), 0)
	PauseArbiter.pop(&"menu")
	# A press made under the menu doesn't arm the channel either.
	PauseArbiter.push(&"menu")
	_push(true)
	PauseArbiter.pop(&"menu")
	assert_true(_push(false), "release consumed")
	assert_true(_panel.is_typing(), "unarmed release ignored")


func test_esc_and_close_menu_keeps_the_story_with_one_dim() -> void:
	var menu: PauseMenu = MENU_SCENE.instantiate() as PauseMenu
	add_child_autofree(menu)
	_request(&"story_a")
	var esc: InputEventAction = InputEventAction.new()
	esc.action = &"pause"
	esc.pressed = true
	menu._unhandled_input(esc)
	assert_true(menu.is_shown(), "menu over the story")
	assert_false((menu.get_node("Dim") as Control).visible, "menu dim hidden: one dim")
	assert_true((_panel.get_node("Dim") as Control).is_visible_in_tree(), "the comms dim stays")
	menu._unhandled_input(esc)
	assert_false(menu.is_shown())
	assert_true(PauseArbiter.has_reason(&"story"), "story still active")
	assert_true(get_tree().paused, "still paused")
	assert_true(_panel.visible, "panel still up")
	assert_eq(_click(), [true, true] as Array[bool], "clicks reach the story again")


# --- Unknown, combat and queued ids ----------------------------------------------------

func test_unknown_id_finishes_deferred() -> void:
	_request(&"nope")
	assert_false(PauseArbiter.is_paused(), "no pause")
	assert_false(_panel.visible, "nothing shown")
	assert_false(_channel.is_showing())
	assert_eq(_finished, [] as Array[StringName], "not during the emit")
	assert_push_error("[ERROR][comms] Unknown comms sequence 'nope'")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_finished, [&"nope"] as Array[StringName], "finished on the next idle frame")


func test_combat_id_finishes_deferred_without_pause() -> void:
	_request(&"combat_a")
	assert_false(PauseArbiter.is_paused(), "no pause")
	assert_false(_panel.visible, "nothing shown")
	assert_false(_channel.is_showing())
	assert_eq(_finished, [] as Array[StringName])
	assert_push_warning("combat_a")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_finished, [&"combat_a"] as Array[StringName])


func test_second_story_queues_and_plays_without_unpausing() -> void:
	_request(&"story_a")
	watch_signals(PauseArbiter)
	_request(&"story_b")
	assert_eq(_channel.current_sequence(), &"story_a", "first keeps playing")
	assert_eq(_channel.queued(), [&"story_b"] as Array[StringName])
	var first_player: AudioStreamPlayer = Audio.newest_player()
	_click_to_end_of(&"story_a")
	assert_eq(_finished, [&"story_a"] as Array[StringName])
	assert_eq(_channel.current_sequence(), &"story_b", "second started")
	assert_true(get_tree().paused, "never unpaused")
	assert_signal_not_emitted(PauseArbiter, "resumed")
	assert_true(_panel.visible)
	assert_eq(_name(), "RYN")
	assert_ne(Audio.newest_player(), first_player, "comms_open played again")
	assert_eq(Audio.newest_player().stream, Audio.SFX[&"comms_open"])
	_click_to_end()
	assert_eq(_finished, [&"story_a", &"story_b"] as Array[StringName], "finished once each, in order")
	assert_false(get_tree().paused)
	assert_signal_emit_count(PauseArbiter, "resumed", 1)


func _click_to_end_of(id: StringName) -> void:
	for i: int in 20:
		if _channel.current_sequence() != id:
			return
		_click()
