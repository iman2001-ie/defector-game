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
## Story 5.4: a cut-off line types to cut_off_at at comms.cutoff_chars_per_s,
## then (at its cut-off moment) shows comms.cutoff_suffix after the cut, runs
## the `after` effects (comms_static, the `cutoff` shake or a tier's shake, the
## music action, silence) and hides comms.cutoff_hide_s later; silence drops
## combat until Events.wave_cleared.
## Decision #40: advancing a story line plays comms_click (same speaker) or
## comms_handover (speaker change); completing or closing plays none.
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
## The text of cut_a / cut_plain / cut_large and their cut point.
const CUT_TEXT: String = "General, get behind me, I've got you cov—"
const CUT_AT: int = 39

## The cut-off moment of cut_a / cut_plain (CUT_AT characters at
## comms.cutoff_chars_per_s) and the hold after it (comms.cutoff_hide_s), set
## from the tuning in before_each.
var _cut_s: float = 0.0
var _hide_s: float = 0.0

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
	_cut_s = CUT_AT / Config.num("comms.cutoff_chars_per_s")
	_hide_s = Config.num("comms.cutoff_hide_s")
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
	Engine.time_scale = 1.0


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


## Decision #40: advancing to a new line plays comms_click for the same
## speaker and comms_handover for a speaker change.
func test_line_cues_follow_the_speaker() -> void:
	_request(&"story_c")
	_panel.complete_line()
	_click()
	assert_eq(_channel.line_index(), 1)
	assert_eq(_newest_stream(), Audio.SFX[&"comms_click"], "tarek -> tarek: click")
	_panel.complete_line()
	_click()
	assert_eq(_channel.line_index(), 2)
	assert_eq(_newest_stream(), Audio.SFX[&"comms_handover"], "tarek -> vale: handover")


func test_completing_a_typing_line_plays_no_cue() -> void:
	_request(&"story_c")
	var open_player: AudioStreamPlayer = Audio.newest_player()
	assert_true(_panel.is_typing())
	_click()
	assert_false(_panel.is_typing(), "line complete")
	assert_eq(_channel.line_index(), 0)
	assert_eq(Audio.newest_player(), open_player, "no new sfx")


func test_closing_the_last_line_plays_no_cue() -> void:
	_request(&"story_c")
	_click_to_end_of_line(2)
	var handover_player: AudioStreamPlayer = Audio.newest_player()
	assert_eq(handover_player.stream, Audio.SFX[&"comms_handover"], "cue played on the last line")
	_click_to_end()
	assert_false(_channel.is_showing())
	assert_eq(Audio.newest_player(), handover_player, "no cue on close")


## Clicks (complete + advance) until the panel shows line `index`.
func _click_to_end_of_line(index: int) -> void:
	for i: int in 20:
		if _channel.line_index() >= index:
			return
		_click()


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
	_channel.step_combat(4.9)
	assert_eq(_finished, [] as Array[StringName], "not at 4.9 s")
	assert_eq(_channel.current_combat(), &"combat_a")
	_channel.step_combat(0.1)
	assert_eq(_finished, [&"combat_a"] as Array[StringName], "finished once at 5.0 s")
	assert_eq(_channel.current_combat(), &"")
	assert_false(_box.is_open(), "box fading")
	assert_eq(_count_lines("[INFO][comms] Combat sequence 'combat_a' finished"), 1)
	_channel.step_combat(5.0)
	assert_eq(_finished, [&"combat_a"] as Array[StringName], "only once")


func test_combat_line_time_fifty_chars() -> void:
	_request(&"combat_e")
	assert_eq(_box_text().text.length(), 50)
	# 50 / 45 + 3.0 = 4.11 s, under the 5.0 s minimum (GDD decision #41).
	_channel.step_combat(4.9)
	assert_eq(_finished, [] as Array[StringName], "not at 4.9 s")
	_channel.step_combat(0.1)
	assert_eq(_finished, [&"combat_e"] as Array[StringName], "finished at 5.0 s")


func test_combat_box_fades_and_hides() -> void:
	_request(&"combat_a")
	_end_combat_line()
	assert_true(_box.visible, "still visible while fading")
	assert_false(_box.is_open(), "not open while fading")
	_box._fade_tween.custom_step(0.3)
	assert_lt(_box.modulate.a, 1.0, "fading")
	assert_true(_box.visible, "still visible half way through the 0.6 s fade")
	_box._fade_tween.custom_step(0.31)
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


## A combat line queued behind one that a story preempted keys in fresh: the
## preempt hid the box at once (no fade left), so the cue is comms_open, not handover.
func test_combat_resumed_after_a_preempt_plays_open() -> void:
	_request(&"combat_a")
	_request(&"combat_b")
	_request(&"story_a")
	assert_false(_box.visible, "preempt hid the box")
	assert_eq(_box.current_speaker(), &"", "speaker cleared by the hide")
	_click_to_end()
	assert_eq(_channel.current_combat(), &"combat_b", "queued combat resumes")
	assert_eq(_newest_stream(), Audio.SFX[&"comms_open_nobeep"], "fresh key-in after the story")


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
	assert_eq(_box_text().get_rect(), Rect2(16, 36, 532, 50), "532 px text block")


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


# --- Combat cues (GDD decision #41) ---------------------------------------------------

func test_combat_line_from_idle_plays_a_quiet_open() -> void:
	_request(&"combat_a")
	assert_eq(_newest_stream(), Audio.SFX[&"comms_open_nobeep"], "the channel-open sound without the beep when the box opens fresh")
	assert_eq(Audio.newest_player().pitch_scale, 1.0, "no pitch jitter")
	assert_eq(Audio.newest_player().volume_db, Config.num("comms.combat_open_db"), "quieter than in a story")
	assert_lt(Config.num("comms.combat_open_db"), 0.0)


func test_back_to_back_new_speaker_plays_handover() -> void:
	_request(&"combat_a")
	_request(&"combat_b")
	_end_combat_line()
	assert_eq(_channel.current_combat(), &"combat_b", "queued line straight on")
	assert_eq(_newest_stream(), Audio.SFX[&"comms_handover"], "isolde -> tarek: handover")
	assert_eq(Audio.newest_player().volume_db, Config.num("comms.combat_line_cue_db"), "quieter than in a story")
	assert_lt(Config.num("comms.combat_line_cue_db"), 0.0)


func test_back_to_back_same_speaker_plays_click() -> void:
	_request(&"combat_a")
	_request(&"combat_e")
	_end_combat_line()
	assert_eq(_channel.current_combat(), &"combat_e")
	assert_eq(_newest_stream(), Audio.SFX[&"comms_click"], "isolde -> isolde: click")
	assert_eq(Audio.newest_player().volume_db, Config.num("comms.combat_line_cue_db"), "quieter than in a story")


func test_combat_after_a_story_plays_open() -> void:
	_request(&"story_a")
	_request(&"combat_a")
	_click_to_end()
	assert_eq(_channel.current_combat(), &"combat_a")
	assert_eq(_newest_stream(), Audio.SFX[&"comms_open_nobeep"], "the story hid the box: a fresh key-in")


func test_combat_after_the_fade_plays_open() -> void:
	_request(&"combat_a")
	_end_combat_line()
	_box._fade_tween.custom_step(1.0)
	assert_false(_box.visible, "faded out")
	_request(&"combat_e")
	assert_eq(_newest_stream(), Audio.SFX[&"comms_open_nobeep"], "same speaker, but the box was gone")


func test_no_cue_when_the_box_fades() -> void:
	_request(&"combat_a")
	var key_in: AudioStreamPlayer = Audio.newest_player()
	_end_combat_line()
	_box._fade_tween.custom_step(1.0)
	assert_eq(Audio.newest_player(), key_in, "no sound on the way out")


func test_combat_cue_rule() -> void:
	assert_eq(CommsChannel.combat_cue(false, &"isolde", &"isolde"), &"comms_open_nobeep")
	assert_eq(CommsChannel.combat_cue(false, &"", &"tarek"), &"comms_open_nobeep")
	assert_eq(CommsChannel.combat_cue(true, &"isolde", &"tarek"), &"comms_handover")
	assert_eq(CommsChannel.combat_cue(true, &"isolde", &"isolde"), &"comms_click")


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
	_channel.step_combat(_cut_s + 0.01)
	assert_true(_channel.is_silenced(), "silenced by cut_a")


func test_cut_off_timeline() -> void:
	_add_camera()
	_play_music()
	var cut_text: String = CUT_TEXT.left(CUT_AT) + str(Config.section("comms").get("cutoff_suffix"))
	_request(&"cut_a")
	assert_eq(_newest_stream(), Audio.SFX[&"comms_open_nobeep"], "the cut-off line keys in like any other")
	var before: AudioStreamPlayer = Audio.newest_player()
	assert_true(_box.visible, "box shown")
	assert_true(_box.is_typing(), "typing")
	assert_eq(_box_text().text, CUT_TEXT)
	assert_eq(_channel.cut_phase(), CommsChannel.CutPhase.TYPING)
	assert_almost_eq(_channel._combat_left_s, _cut_s, 0.0001, "cut at cut_off_at / cutoff_chars_per_s")
	_channel.step_combat(_cut_s - 0.01)
	assert_eq(Audio.newest_player(), before, "no SFX before the cut-off moment")
	assert_eq(_camera.current_amplitude(), 0.0, "no shake yet")
	assert_eq(Audio.current_music(), TEST_MUSIC, "music still on")
	assert_false(_channel.is_silenced(), "not silenced yet")
	assert_eq(_box_text().text, CUT_TEXT, "no suffix before the cut")
	_channel.step_combat(0.02)
	assert_eq(_box_text().text, cut_text, "the cut text and the suffix")
	assert_eq(_box_text().text, "General, get behind me, I've got you co...", "the tuned suffix is ...")
	assert_eq(_box_text().visible_characters, -1, "all of it visible")
	assert_false(_box.is_typing(), "typewriter stopped")
	assert_eq(_newest_stream(), Audio.SFX[&"comms_static"], "comms_static played")
	assert_almost_eq(_camera.current_amplitude(), Config.num("comms.cutoff_shake_px"), 0.0001, "the cut-off shake")
	assert_eq(Engine.time_scale, 1.0, "no hit-stop")
	assert_eq(Audio.current_music(), &"", "music stopped")
	assert_true(_channel.is_silenced(), "silenced")
	assert_eq(_channel.cut_phase(), CommsChannel.CutPhase.HOLD)
	assert_eq(_count_lines("[INFO][comms] Combat sequence 'cut_a' cut off at 39 characters"), 1)
	assert_eq(_count_lines("[INFO][comms] Comms silenced until the wave clears (cut-off 'cut_a')"), 1)
	_channel.step_combat(_hide_s - 0.02)
	assert_true(_box.visible, "still visible before +cutoff_hide_s")
	assert_eq(_box.modulate.a, 1.0, "no fade while holding")
	assert_eq(_box_text().text, cut_text, "still the cut text")
	assert_eq(_finished, [] as Array[StringName], "not finished yet")
	_channel.step_combat(0.02)
	assert_false(_box.visible, "hidden at once at +cutoff_hide_s")
	assert_eq(_finished, [&"cut_a"] as Array[StringName], "finished once")
	assert_eq(_channel.current_combat(), &"")
	assert_eq(_channel.cut_phase(), CommsChannel.CutPhase.NONE)
	assert_eq(_count_lines("[INFO][comms] Combat sequence 'cut_a' finished"), 1)
	_channel.step_combat(5.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_finished, [&"cut_a"] as Array[StringName], "only once")


## GDD decision #43: the shipped cut-off tuning. 39 characters at 16 chars/s put
## the cut at about 2.4 s; the 2.5 s hold equals the static clip.
func test_cut_off_tuning() -> void:
	assert_eq(Config.num("comms.cutoff_chars_per_s"), 16.0)
	assert_eq(Config.num("comms.cutoff_hide_s"), 2.5)
	assert_eq(Config.num("comms.cutoff_shake_px"), 18.0)
	assert_eq(Config.num("comms.cutoff_shake_s"), 0.9)
	assert_eq(Config.section("comms").get("cutoff_suffix"), "...")
	assert_almost_eq(_cut_s, 2.4375, 0.0001, "the cut lands at about 2.4 s")
	assert_lt(Config.num("comms.cutoff_chars_per_s"), Config.num("comms.chars_per_s"), "slower than a normal line")


## A tier name in after.shake still shakes with that tier (Feedback.shake_tier).
func test_cut_off_with_a_tier_shake() -> void:
	_add_camera()
	_request(&"cut_large")
	_channel.step_combat(_cut_s + 0.01)
	var large_px: float = Feedback.tier_row(ImpactTier.LARGE).get("shake_px", 0.0) as float
	assert_gt(large_px, 0.0, "large has a shake")
	assert_almost_eq(_camera.current_amplitude(), large_px, 0.0001, "the large tier's shake")
	assert_ne(_camera.current_amplitude(), Config.num("comms.cutoff_shake_px"), "not the cut-off shake")
	assert_eq(_channel.cut_phase(), CommsChannel.CutPhase.HOLD)
	_channel.step_combat(_hide_s + 0.01)
	assert_false(_box.visible, "hidden after the hold")
	assert_eq(_finished, [&"cut_large"] as Array[StringName], "finished once")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_finished, [&"cut_large"] as Array[StringName], "only once")


# --- The static lives with the cut-off line --------------------------------------------

## Runs cut_a to just past its cut-off moment; returns the static's player.
func _cut_static() -> AudioStreamPlayer:
	_request(&"cut_a")
	_channel.step_combat(_cut_s + 0.01)
	var player: AudioStreamPlayer = _channel.cut_sfx_player()
	assert_not_null(player, "the static's player is kept")
	if player != null:
		assert_eq(player.stream, Audio.SFX[&"comms_static"], "it plays comms_static")
		assert_true(player.playing, "playing")
	return player


func test_the_static_stops_with_the_hide() -> void:
	var player: AudioStreamPlayer = _cut_static()
	_channel.step_combat(_hide_s - 0.02)
	assert_true(player.playing, "still playing during the hold")
	_channel.step_combat(0.03)
	assert_false(_box.visible, "hidden")
	assert_false(player.playing, "stopped with the line")
	assert_null(_channel.cut_sfx_player(), "released")


func test_a_preempt_during_the_hold_stops_the_static() -> void:
	var player: AudioStreamPlayer = _cut_static()
	_request(&"story_a")
	assert_false(_box.visible, "box hidden")
	assert_false(player.playing, "the static stopped")
	assert_false(player.stream_paused, "left unpaused for the pool")
	assert_null(_channel.cut_sfx_player(), "released")


func test_leaving_the_tree_stops_the_static() -> void:
	var player: AudioStreamPlayer = _cut_static()
	remove_child(_channel)
	assert_false(player.playing, "stopped on exit (death reload, retry, scene change)")
	add_child(_channel)


func test_a_pause_pauses_the_static() -> void:
	var player: AudioStreamPlayer = _cut_static()
	PauseArbiter.push(&"menu")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(player.stream_paused, "paused with the tree")
	var left: float = _channel._combat_left_s
	for i: int in 5:
		await get_tree().process_frame
	assert_eq(_channel._combat_left_s, left, "the hold is frozen too")
	PauseArbiter.pop(&"menu")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(player.stream_paused, "resumed with the tree")
	assert_eq(player.stream, Audio.SFX[&"comms_static"], "still the static")


func test_other_sfx_are_not_paused() -> void:
	_cut_static()
	var other: AudioStreamPlayer = Audio.play_sfx(&"laser_zap")
	PauseArbiter.push(&"menu")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(other.stream_paused, "only the static pauses")
	PauseArbiter.pop(&"menu")


## The hold counts real time: at a time scale of 0.5 the game delta is half the
## real delta, so it still ends after cutoff_hide_s real seconds.
func test_the_hold_counts_real_time_under_a_slow_down() -> void:
	_request(&"cut_a")
	Engine.time_scale = 0.5
	_channel.step_combat(_cut_s + 0.01)
	assert_eq(_channel.cut_phase(), CommsChannel.CutPhase.HOLD, "typing counts game time")
	var game_delta: float = (_hide_s - 0.04) * 0.5
	_channel.step_combat(game_delta)
	assert_true(_box.visible, "still holding just before cutoff_hide_s real seconds")
	_channel.step_combat(0.04)
	assert_false(_box.visible, "hidden after cutoff_hide_s real seconds")
	assert_eq(_finished, [&"cut_a"] as Array[StringName])
	Engine.time_scale = 1.0


func test_hold_step() -> void:
	assert_almost_eq(CommsChannel.hold_step(0.1, 1.0), 0.1, 0.000001)
	assert_almost_eq(CommsChannel.hold_step(0.05, 0.5), 0.1, 0.000001, "slowed: real time")
	assert_eq(CommsChannel.hold_step(0.0, 0.0), 0.0, "a freeze adds nothing")
	assert_eq(CommsChannel.hold_step(0.1, -1.0), 0.1, "guarded")


func test_cutoff_suffix_must_be_a_string() -> void:
	assert_eq(CommsChannel.cutoff_suffix_from({"cutoff_suffix": "..."}), "...")
	assert_eq(CommsChannel.cutoff_suffix_from({"cutoff_suffix": ""}), "")
	assert_eq(CommsChannel.cutoff_suffix_from({"cutoff_suffix": 3}), "", "not a string")
	assert_push_error("tuning.comms.cutoff_suffix missing or not a string")
	assert_eq(CommsChannel.cutoff_suffix_from({}), "", "missing")
	assert_push_error("tuning.comms.cutoff_suffix missing or not a string")


## An empty comms.cutoff_suffix: the text stops at cut_off_at characters with
## no suffix (the Story 5.4 behaviour).
func test_cut_off_with_an_empty_suffix() -> void:
	_channel._cutoff_suffix = ""
	_request(&"cut_a")
	_channel.step_combat(_cut_s + 0.01)
	assert_eq(_box_text().text, CUT_TEXT, "the text is kept, no suffix")
	assert_eq(_box_text().visible_characters, CUT_AT, "only cut_off_at characters show")
	assert_false(_box.is_typing(), "typewriter stopped")


func test_cut_off_without_after() -> void:
	_add_camera()
	_request(&"cut_plain")
	var before: AudioStreamPlayer = Audio.newest_player()
	_channel.step_combat(_cut_s + 0.01)
	assert_eq(_box_text().text, "General, get behind me, I've got you co...", "stops at cut_off_at, with the suffix")
	assert_eq(Audio.newest_player(), before, "no SFX")
	assert_eq(_camera.current_amplitude(), 0.0, "no shake")
	assert_false(_channel.is_silenced(), "no silence")
	assert_true(_box.visible)
	_channel.step_combat(_hide_s)
	assert_false(_box.visible, "hidden cutoff_hide_s later")
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
	_channel.step_combat(_hide_s)
	assert_eq(_channel.current_combat(), &"", "nothing plays after the cut-off")
	_request(&"combat_b")
	assert_eq(_channel.current_combat(), &"", "still silenced")


func test_silence_keeps_story() -> void:
	_silence()
	_channel.step_combat(_hide_s)
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
	_channel.step_combat(_hide_s)
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
	_channel.step_combat(_cut_s + 0.01)
	assert_eq(_channel.combat_queued(), [] as Array[StringName], "dropped at the cut-off moment")
	assert_eq(_count_lines("[DEBUG][comms] Comms silenced: dropped queued combat sequence 'combat_a'"), 1)
	assert_eq(_count_lines("[DEBUG][comms] Comms silenced: dropped queued combat sequence 'combat_b'"), 1)
	assert_eq(_finished, [] as Array[StringName], "finished deferred")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_finished, [&"combat_a", &"combat_b"] as Array[StringName], "each finished once")
	_channel.step_combat(_hide_s)
	assert_eq(_channel.current_combat(), &"", "nothing queued plays")
	assert_eq(_finished, [&"combat_a", &"combat_b", &"cut_a"] as Array[StringName])


func test_wave_clear_before_the_cut_off_voids_the_silence() -> void:
	_add_camera()
	_request(&"cut_a")
	_channel.step_combat(0.3)
	Events.wave_cleared.emit(1)
	_channel.step_combat(_cut_s)
	assert_eq(_newest_stream(), Audio.SFX[&"comms_static"], "effects still run")
	assert_almost_eq(_camera.current_amplitude(), Config.num("comms.cutoff_shake_px"), 0.0001, "shake still runs")
	assert_false(_channel.is_silenced(), "no silence into the next wave")
	assert_eq(_count_lines("[DEBUG][comms] Silence from 'cut_a' skipped: its wave already cleared"), 1)
	_channel.step_combat(_hide_s)
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
