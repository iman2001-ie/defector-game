extends GutTest
## CommsChannel (Story 5.1): story sequences push the `story` pause, play the
## comms-open SFX and drive the CommsPanel; LMB (`comms_advance`) presses and
## releases are consumed, a press arms and an armed release completes or
## advances; after the last line the pause pops before `finished`. Unknown ids
## finish deferred with no pause; a second story queues.
## Story 5.2: combat sequences show in the CommsBox without pausing, last
## combat_line_s of game time (driven with step_combat), freeze under a pause,
## ignore clicks, are preempted by a story (deferred `finished`), queue FIFO
## (max 3, oldest dropped with a deferred `finished`) and wait behind a story.
## Story 5.4: a cut-off line types to cut_off_at, then (at its cut-off moment)
## runs the `after` effects (comms_static, the shake tier, the music action,
## silence) and hides comms.cutoff_hide_s later; silence drops combat until
## Events.wave_cleared.
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
const BOX_SCENE: PackedScene = preload("res://systems/comms/comms_box.tscn")
const MENU_SCENE: PackedScene = preload("res://ui/menus/pause_menu.tscn")
const CHANNEL_DIR: String = "res://tests/fixtures/dialogue/channel/"
const CLICK_AT: Vector2 = Vector2(960, 900)
## Music id the cut-off tests play (restored in after_each).
const TEST_MUSIC: StringName = &"combat"
## The cut-off moment of cut_a / cut_plain: 39 characters at 45 chars/s.
const CUT_S: float = 39.0 / 45.0
const HIDE_S: float = 0.6

var _channel: CommsChannel
var _panel: CommsPanel
var _box: CommsBox
var _finished: Array[StringName] = []
## Snapshot taken inside each `finished` handler: [story active, panel visible].
var _at_finish: Array = []
var _lines: Array[String] = []
var _probe: Probe
## The viewport mouse before the test, restored after it (other suites read it).
var _mouse_before: Vector2 = Vector2.ZERO
## A registered ShakeCamera for the cut-off shake (Story 5.4), freed per test.
var _camera: ShakeCamera


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
	_box = BOX_SCENE.instantiate() as CommsBox
	add_child_autofree(_box)
	_channel = CommsChannel.new()
	_channel.panel = _panel
	_channel.box = _box
	add_child_autofree(_channel)


func after_each() -> void:
	Events.comms_sequence_finished.disconnect(_on_finished)
	Log.sink = Callable()
	_channel = null
	_panel = null
	_box = null
	_probe = null
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = _mouse_before
	motion.global_position = _mouse_before
	get_viewport().push_input(motion, true)
	Config.load_data()
	PauseArbiter.clear()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Audio.stop_music(0.0)
	Audio.music_streams.erase(TEST_MUSIC)
	Audio._warned_music.erase(TEST_MUSIC)
	_camera = null


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


# --- Combat (Story 5.2) ----------------------------------------------------------------

func _box_text() -> Label:
	return _box.get_node("Box/Text") as Label


func _box_name() -> Label:
	return _box.get_node("Box/Name") as Label


## Steps the current combat line to its end (and a little past it).
func _end_combat_line() -> void:
	_channel.step_combat(_channel._combat_left_s + 0.01)


func _assert_color(actual: Color, expected: Color, what: String) -> void:
	assert_almost_eq(actual.r, expected.r, 0.002, what + " r")
	assert_almost_eq(actual.g, expected.g, 0.002, what + " g")
	assert_almost_eq(actual.b, expected.b, 0.002, what + " b")


func test_combat_line_s() -> void:
	assert_almost_eq(CommsChannel.combat_line_s(15, 45.0, 2.0, 1.2), 2.0, 0.0001, "short line: the minimum")
	assert_almost_eq(CommsChannel.combat_line_s(50, 45.0, 2.0, 1.2), 50.0 / 45.0 + 1.2, 0.0001, "50 chars: 2.31 s")
	assert_almost_eq(CommsChannel.combat_line_s(50, 0.0, 2.0, 1.2), 2.0, 0.0001, "no typing speed: max(min, extra)")
	assert_almost_eq(CommsChannel.combat_line_s(50, -1.0, 1.0, 1.5), 1.5, 0.0001, "no typing speed: max(min, extra)")


func test_combat_plays_without_pausing() -> void:
	_request(&"combat_a")
	assert_false(get_tree().paused, "not paused")
	assert_false(PauseArbiter.has_reason(&"story"), "no story reason")
	assert_false(_panel.visible, "no story panel")
	assert_true(_box.visible, "box shown")
	assert_true(_box.is_open())
	assert_eq(_channel.current_combat(), &"combat_a")
	assert_false(_channel.is_showing(), "not a story")
	assert_eq(_box_name().text, "ISOLDE", "uppercase name")
	_assert_color(_box_name().get_theme_color(&"font_color"), Color("#FF6AE3"), "name in the accent")
	_assert_color((_box.get_node("Box/Edge") as ColorRect).color, Color("#FF6AE3"), "accent edge")
	assert_eq(_box_text().text, "Combat chatter.")
	assert_eq(_box_text().visible_characters, 0, "typing from 0")
	assert_true(_box.is_typing(), "typing")
	_box._slide_tween.custom_step(1.0)
	assert_eq((_box.get_node("Box") as Control).get_rect(), Rect2(32, 24, 560, 96), "box at the UX rect")
	assert_eq(_finished, [] as Array[StringName], "not finished yet")
	assert_eq(_count_lines("[INFO][comms] Combat sequence 'combat_a' started"), 1)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_finished, [] as Array[StringName], "still not finished a frame later")


func test_combat_line_time_short_line() -> void:
	_request(&"combat_a")
	_channel.step_combat(1.9)
	assert_eq(_finished, [] as Array[StringName], "not at 1.9 s")
	assert_eq(_channel.current_combat(), &"combat_a")
	_channel.step_combat(0.1)
	assert_eq(_finished, [&"combat_a"] as Array[StringName], "finished once at 2.0 s")
	assert_eq(_channel.current_combat(), &"")
	assert_false(_box.is_open(), "box fading")
	assert_eq(_count_lines("[INFO][comms] Combat sequence 'combat_a' finished"), 1)
	_channel.step_combat(5.0)
	assert_eq(_finished, [&"combat_a"] as Array[StringName], "only once")


func test_combat_line_time_fifty_chars() -> void:
	_request(&"combat_e")
	assert_eq(_box_text().text.length(), 50)
	_channel.step_combat(2.3)
	assert_eq(_finished, [] as Array[StringName], "not at 2.3 s")
	_channel.step_combat(0.012)
	assert_eq(_finished, [&"combat_e"] as Array[StringName], "finished at 2.31 s")


func test_combat_box_fades_and_hides() -> void:
	_request(&"combat_a")
	_end_combat_line()
	assert_true(_box.visible, "still visible while fading")
	assert_false(_box.is_open(), "not open while fading")
	_box._fade_tween.custom_step(0.1)
	assert_lt(_box.modulate.a, 1.0, "fading")
	_box._fade_tween.custom_step(0.2)
	assert_false(_box.visible, "hidden after the fade")


func test_combat_freezes_under_a_pause() -> void:
	_request(&"combat_e")
	await get_tree().process_frame
	PauseArbiter.push(&"menu")
	var left: float = _channel._combat_left_s
	var chars: int = _box_text().visible_characters
	for i: int in 10:
		await get_tree().process_frame
	assert_eq(_channel._combat_left_s, left, "line timer frozen")
	assert_eq(_box_text().visible_characters, chars, "typewriter frozen")
	assert_true(_box.is_typing(), "still mid-line")
	assert_eq(_finished, [] as Array[StringName])
	PauseArbiter.pop(&"menu")
	for i: int in 2000:
		await get_tree().process_frame
		if _channel._combat_left_s < left:
			break
	assert_lt(_channel._combat_left_s, left, "resumes after the pause")


func test_combat_line_ignores_clicks() -> void:
	_request(&"combat_a")
	var handled: Array[bool] = _click()
	assert_eq(handled, [false, false] as Array[bool], "press and release reach the probe")
	assert_eq(_channel.current_combat(), &"combat_a", "nothing changed")
	assert_true(_box.is_typing(), "still typing")
	assert_eq(_finished, [] as Array[StringName])


func test_story_preempts_a_combat_line() -> void:
	_request(&"combat_a")
	_request(&"story_a")
	assert_false(_box.visible, "box hidden at once")
	assert_eq(_channel.current_combat(), &"")
	assert_eq(_channel.current_sequence(), &"story_a", "story plays")
	assert_true(_panel.visible, "story panel")
	assert_true(PauseArbiter.has_reason(&"story"), "story pause")
	assert_true(get_tree().paused)
	assert_eq(_finished, [] as Array[StringName], "finished deferred")
	assert_eq(_count_lines("[INFO][comms] Combat sequence 'combat_a' preempted by story 'story_a'"), 1)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_finished, [&"combat_a"] as Array[StringName], "finished once")
	_click_to_end()
	assert_eq(_finished, [&"combat_a", &"story_a"] as Array[StringName])
	assert_eq(_channel.current_combat(), &"", "nothing replays")


func test_combat_queue_drops_the_oldest() -> void:
	_request(&"combat_a")
	for id: StringName in [&"combat_b", &"combat_c", &"combat_d", &"combat_e"]:
		_request(id)
	assert_eq(_channel.current_combat(), &"combat_a", "the first keeps playing")
	assert_eq(_channel.combat_queued(), [&"combat_c", &"combat_d", &"combat_e"] as Array[StringName], "max 3, oldest dropped")
	assert_eq(_count_lines("[DEBUG][comms] Combat queue full (max 3): dropped 'combat_b'"), 1)
	assert_eq(_finished, [] as Array[StringName], "drop finishes deferred")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_finished, [&"combat_b"] as Array[StringName], "dropped one finished once")
	for expected: StringName in [&"combat_c", &"combat_d", &"combat_e"]:
		_end_combat_line()
		assert_eq(_channel.current_combat(), expected, "FIFO: %s next" % expected)
		assert_true(_box.is_open(), "box re-opened for %s" % expected)
	_end_combat_line()
	assert_eq(_finished, [&"combat_b", &"combat_a", &"combat_c", &"combat_d", &"combat_e"] as Array[StringName], "each once, in order")
	assert_eq(_channel.current_combat(), &"")
	assert_eq(_channel.combat_queued(), [] as Array[StringName])


func test_vale_combat_line_has_no_portrait() -> void:
	_request(&"combat_c")
	assert_eq(_box_name().text, "VALE")
	assert_false((_box.get_node("Box/Portrait") as Control).visible, "no portrait")
	assert_eq(_box_text().get_rect(), Rect2(16, 34, 532, 56), "532 px text block")


func test_combat_behind_a_story_waits_for_it() -> void:
	_request(&"story_a")
	_request(&"combat_a")
	assert_eq(_channel.current_combat(), &"", "not while a story shows")
	assert_false(_box.visible)
	assert_eq(_channel.combat_queued(), [&"combat_a"] as Array[StringName], "queued")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_finished, [] as Array[StringName], "not dropped")
	assert_eq(_channel.current_combat(), &"", "doesn't play while paused")
	_click_to_end()
	assert_eq(_finished, [&"story_a"] as Array[StringName])
	assert_false(get_tree().paused, "story popped")
	assert_eq(_channel.current_combat(), &"combat_a", "plays after the story")
	assert_true(_box.visible)
	_end_combat_line()
	assert_eq(_finished, [&"story_a", &"combat_a"] as Array[StringName])


func test_queued_combat_survives_a_preempt() -> void:
	_request(&"combat_a")
	_request(&"combat_b")
	_request(&"story_b")
	assert_eq(_channel.current_combat(), &"", "playing one dropped")
	assert_eq(_channel.combat_queued(), [&"combat_b"] as Array[StringName], "queue kept")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_finished, [&"combat_a"] as Array[StringName])
	_click_to_end()
	assert_eq(_channel.current_combat(), &"combat_b", "queued combat plays after the story")
	_end_combat_line()
	assert_eq(_finished, [&"combat_a", &"story_b", &"combat_b"] as Array[StringName], "each once")


func test_combat_requested_in_a_finished_listener_queues_behind_older_ones() -> void:
	_request(&"story_a")
	_request(&"combat_a")
	var chain: Callable = func(id: StringName) -> void:
		if id == &"story_a":
			_request(&"combat_b")
	Events.comms_sequence_finished.connect(chain)
	_click_to_end()
	Events.comms_sequence_finished.disconnect(chain)
	assert_eq(_channel.current_combat(), &"combat_a", "the queued combat plays first")
	assert_eq(_channel.combat_queued(), [&"combat_b"] as Array[StringName], "the listener's combat waits")
	_end_combat_line()
	assert_eq(_channel.current_combat(), &"combat_b", "then the listener's combat")
	_end_combat_line()
	assert_eq(_finished, [&"story_a", &"combat_a", &"combat_b"] as Array[StringName], "FIFO, each once")


func test_story_hides_a_fading_combat_box() -> void:
	_request(&"combat_a")
	_end_combat_line()
	assert_true(_box.visible, "box fading, still visible")
	assert_false(_box.is_open())
	_request(&"story_a")
	assert_false(_box.visible, "hidden when the story starts")
	assert_true(_panel.visible, "story panel up")


func test_story_on_story_still_queues_with_combat_around() -> void:
	_request(&"story_a")
	_request(&"combat_a")
	_request(&"story_b")
	assert_eq(_channel.queued(), [&"story_b"] as Array[StringName], "story queued, never dropped")
	_click_to_end_of(&"story_a")
	assert_eq(_channel.current_sequence(), &"story_b", "next story before any combat")
	assert_eq(_channel.current_combat(), &"")
	_click_to_end()
	assert_eq(_channel.current_combat(), &"combat_a", "combat after both stories")
	assert_eq(_finished, [&"story_a", &"story_b"] as Array[StringName])


# --- Cut-off and silence (Story 5.4) ---------------------------------------------------

## A registered ShakeCamera whose frames don't decay the amplitude.
func _add_camera() -> ShakeCamera:
	_camera = ShakeCamera.new()
	add_child_autofree(_camera)
	_camera.set_process(false)
	return _camera


## Plays a silent looping track as `combat` music.
func _play_music() -> void:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var data: PackedByteArray = PackedByteArray()
	data.resize(22050 * 2)
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = 22050
	Audio.music_streams[TEST_MUSIC] = wav
	Audio.play_music(TEST_MUSIC)


func _newest_stream() -> AudioStream:
	var player: AudioStreamPlayer = Audio.newest_player()
	return player.stream if player != null else null


## Runs cut_a to just past its cut-off moment (silence on).
func _silence() -> void:
	_request(&"cut_a")
	_channel.step_combat(CUT_S + 0.01)
	assert_true(_channel.is_silenced(), "silenced by cut_a")


func test_cut_off_timeline() -> void:
	_add_camera()
	_play_music()
	Audio.play_sfx(&"laser_zap")
	var before: AudioStreamPlayer = Audio.newest_player()
	_request(&"cut_a")
	assert_true(_box.visible, "box shown")
	assert_true(_box.is_typing(), "typing")
	assert_eq(_box_text().text, "General, get behind me, I've got you cov—")
	assert_eq(_channel.cut_phase(), CommsChannel.CutPhase.TYPING)
	_channel.step_combat(CUT_S - 0.01)
	assert_eq(Audio.newest_player(), before, "no SFX before the cut-off moment")
	assert_eq(_camera.current_amplitude(), 0.0, "no shake yet")
	assert_eq(Audio.current_music(), TEST_MUSIC, "music still on")
	assert_false(_channel.is_silenced(), "not silenced yet")
	_channel.step_combat(0.02)
	assert_eq(_box_text().visible_characters, 39, "stopped at exactly cut_off_at")
	assert_false(_box.is_typing(), "typewriter stopped")
	assert_eq(_newest_stream(), Audio.SFX[&"comms_static"], "comms_static played")
	assert_almost_eq(_camera.current_amplitude(), 8.0, 0.0001, "large shake")
	assert_eq(Engine.time_scale, 1.0, "no hit-stop")
	assert_eq(Audio.current_music(), &"", "music stopped")
	assert_true(_channel.is_silenced(), "silenced")
	assert_eq(_channel.cut_phase(), CommsChannel.CutPhase.HOLD)
	assert_eq(_count_lines("[INFO][comms] Combat sequence 'cut_a' cut off at 39 characters"), 1)
	assert_eq(_count_lines("[INFO][comms] Comms silenced until the wave clears (cut-off 'cut_a')"), 1)
	_channel.step_combat(HIDE_S - 0.02)
	assert_true(_box.visible, "still visible before +0.6 s")
	assert_eq(_box_text().visible_characters, 39, "still at 39")
	assert_eq(_finished, [] as Array[StringName], "not finished yet")
	_channel.step_combat(0.02)
	assert_false(_box.visible, "hidden at once at +0.6 s")
	assert_eq(_finished, [&"cut_a"] as Array[StringName], "finished once")
	assert_eq(_channel.current_combat(), &"")
	assert_eq(_channel.cut_phase(), CommsChannel.CutPhase.NONE)
	assert_eq(_count_lines("[INFO][comms] Combat sequence 'cut_a' finished"), 1)
	_channel.step_combat(5.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_finished, [&"cut_a"] as Array[StringName], "only once")


func test_cut_off_without_after() -> void:
	_add_camera()
	Audio.play_sfx(&"laser_zap")
	var before: AudioStreamPlayer = Audio.newest_player()
	_request(&"cut_plain")
	_channel.step_combat(CUT_S + 0.01)
	assert_eq(_box_text().visible_characters, 39, "stops at cut_off_at")
	assert_eq(Audio.newest_player(), before, "no SFX")
	assert_eq(_camera.current_amplitude(), 0.0, "no shake")
	assert_false(_channel.is_silenced(), "no silence")
	assert_true(_box.visible)
	_channel.step_combat(HIDE_S)
	assert_false(_box.visible, "hidden 0.6 s later")
	assert_eq(_finished, [&"cut_plain"] as Array[StringName], "finished")


func test_silence_drops_combat_requests() -> void:
	_silence()
	_request(&"combat_a")
	assert_eq(_channel.current_combat(), &"cut_a", "not shown")
	assert_eq(_channel.combat_queued(), [] as Array[StringName], "not queued")
	assert_eq(_count_lines("[DEBUG][comms] Comms silenced: dropped combat sequence 'combat_a'"), 1)
	assert_eq(_finished, [] as Array[StringName], "finished deferred")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_finished, [&"combat_a"] as Array[StringName], "finished once")
	_channel.step_combat(HIDE_S)
	assert_eq(_channel.current_combat(), &"", "nothing plays after the cut-off")
	_request(&"combat_b")
	assert_eq(_channel.current_combat(), &"", "still silenced")


func test_silence_keeps_story() -> void:
	_silence()
	_channel.step_combat(HIDE_S)
	_request(&"story_a")
	assert_eq(_channel.current_sequence(), &"story_a", "story plays")
	assert_true(PauseArbiter.has_reason(&"story"), "story pauses")
	assert_true(_panel.visible)
	assert_true(_channel.is_silenced(), "still silenced")
	_click_to_end()
	assert_eq(_finished, [&"cut_a", &"story_a"] as Array[StringName])
	assert_false(get_tree().paused)


func test_wave_cleared_lifts_the_silence() -> void:
	_silence()
	_channel.step_combat(HIDE_S)
	Events.wave_cleared.emit(1)
	assert_false(_channel.is_silenced(), "silence lifted")
	assert_eq(_count_lines("[INFO][comms] Comms silence lifted (wave cleared)"), 1)
	_request(&"combat_a")
	assert_eq(_channel.current_combat(), &"combat_a", "the next combat plays")


func test_silence_flushes_the_combat_queue() -> void:
	_request(&"cut_a")
	_request(&"combat_a")
	_request(&"combat_b")
	assert_eq(_channel.combat_queued(), [&"combat_a", &"combat_b"] as Array[StringName], "queued behind the cut-off")
	_channel.step_combat(CUT_S + 0.01)
	assert_eq(_channel.combat_queued(), [] as Array[StringName], "dropped at the cut-off moment")
	assert_eq(_count_lines("[DEBUG][comms] Comms silenced: dropped queued combat sequence 'combat_a'"), 1)
	assert_eq(_count_lines("[DEBUG][comms] Comms silenced: dropped queued combat sequence 'combat_b'"), 1)
	assert_eq(_finished, [] as Array[StringName], "finished deferred")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_finished, [&"combat_a", &"combat_b"] as Array[StringName], "each finished once")
	_channel.step_combat(HIDE_S)
	assert_eq(_channel.current_combat(), &"", "nothing queued plays")
	assert_eq(_finished, [&"combat_a", &"combat_b", &"cut_a"] as Array[StringName])


func test_wave_clear_before_the_cut_off_voids_the_silence() -> void:
	_add_camera()
	_request(&"cut_a")
	_channel.step_combat(0.3)
	Events.wave_cleared.emit(1)
	_channel.step_combat(CUT_S)
	assert_eq(_newest_stream(), Audio.SFX[&"comms_static"], "effects still run")
	assert_almost_eq(_camera.current_amplitude(), 8.0, 0.0001, "shake still runs")
	assert_false(_channel.is_silenced(), "no silence into the next wave")
	assert_eq(_count_lines("[DEBUG][comms] Silence from 'cut_a' skipped: its wave already cleared"), 1)
	_channel.step_combat(HIDE_S)
	_request(&"combat_a")
	assert_eq(_channel.current_combat(), &"combat_a", "combat plays")


func test_story_preempting_before_the_cut_off_drops_the_effects() -> void:
	_add_camera()
	_play_music()
	_request(&"cut_a")
	_channel.step_combat(0.3)
	_request(&"story_a")
	assert_false(_box.visible, "box hidden")
	assert_eq(_channel.current_combat(), &"")
	assert_eq(_channel.cut_phase(), CommsChannel.CutPhase.NONE)
	assert_eq(_newest_stream(), Audio.SFX[&"comms_open"], "only the story's comms_open, no static")
	_channel.step_combat(5.0)
	assert_eq(_camera.current_amplitude(), 0.0, "no shake")
	assert_eq(Audio.current_music(), TEST_MUSIC, "music untouched")
	assert_false(_channel.is_silenced(), "no silence")
	assert_eq(_finished, [] as Array[StringName], "finished deferred")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_finished, [&"cut_a"] as Array[StringName], "the cut-off finished once")


func test_story_after_the_cut_off_just_hides_the_box() -> void:
	_silence()
	_request(&"story_b")
	assert_false(_box.visible, "box hidden")
	assert_true(_channel.is_silenced(), "the effects already ran")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_finished, [&"cut_a"] as Array[StringName])


func test_cut_off_freezes_under_a_pause() -> void:
	_request(&"cut_a")
	await get_tree().process_frame
	PauseArbiter.push(&"menu")
	var left: float = _channel._combat_left_s
	var chars: int = _box_text().visible_characters
	for i: int in 10:
		await get_tree().process_frame
	assert_eq(_channel._combat_left_s, left, "cut-off timer frozen")
	assert_eq(_box_text().visible_characters, chars, "typewriter frozen")
	assert_eq(_channel.cut_phase(), CommsChannel.CutPhase.TYPING, "still before the cut-off")
	assert_false(_channel.is_silenced())
	PauseArbiter.pop(&"menu")
	for i: int in 2000:
		await get_tree().process_frame
		if _channel._combat_left_s < left:
			break
	assert_lt(_channel._combat_left_s, left, "resumes after the pause")
