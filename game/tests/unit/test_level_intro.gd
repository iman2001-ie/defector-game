extends GutTest
## Epic 7 playtest L: the "LEVEL N" title card. LevelIntroCard (the HUD node,
## driven by Events.level_intro_started) and the level's start gating: a
## campaign level shows the card and starts its WaveDirector only after the
## card's whole time; a retry uses retry_hold_s (0 skips the card); dev levels,
## a failed config and `intro_card = false` start at once; a pause freezes the
## wait.

const LEVEL_SCENE: PackedScene = preload("res://scenes/level/level.tscn")
const FADE_IN_S: float = 0.1
const HOLD_S: float = 0.2
const RETRY_HOLD_S: float = 0.1
const FADE_OUT_S: float = 0.1
const TEST_PAUSE: StringName = &"menu"

var _level: Node2D = null


func before_each() -> void:
	_reset_game_state()
	var intro: Dictionary = (Config.tuning["ui"] as Dictionary)["level_intro"] as Dictionary
	intro["fade_in_s"] = FADE_IN_S
	intro["hold_s"] = HOLD_S
	intro["retry_hold_s"] = RETRY_HOLD_S
	intro["fade_out_s"] = FADE_OUT_S
	(Config.tuning["waves"] as Dictionary)["gap_s"] = 0.05
	watch_signals(Events)


func after_each() -> void:
	_level = null
	Config.assert_on_missing = true
	Config.load_data()
	_reset_game_state()
	Feedback.reset()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	PauseArbiter.clear()


func _reset_game_state() -> void:
	GameState.energy = 0
	GameState.current_level_id = ""
	GameState.is_retry = false
	GameState.shown_hints.clear()


## The real level scene on `level_id` with an invincible player and no cursor
## warps; `intro_card` as given.
func _make_level(level_id: String, intro_card: bool = true) -> Node2D:
	_level = LEVEL_SCENE.instantiate() as Node2D
	_level.set("intro_card", intro_card)
	_level.set("level_id", level_id)
	_level.user_args = PackedStringArray()
	var player: Player = _level.get_node("World/Player") as Player
	player.debug_invincible = true
	player.warp_mouse = func(_at: Vector2) -> void: pass
	add_child_autofree(_level)
	return _level


func _card() -> LevelIntroCard:
	return _level.get_node("HUD/LevelIntroCard") as LevelIntroCard


func _total(hold: float) -> float:
	return LevelIntroCard.total_s(FADE_IN_S, hold, FADE_OUT_S)


# --- the maths -------------------------------------------------------------------------

func test_alpha_fades_in_holds_and_fades_out() -> void:
	assert_eq(LevelIntroCard.alpha_at(-0.1, 0.4, 1.6, 0.6), 0.0, "before it starts")
	assert_almost_eq(LevelIntroCard.alpha_at(0.2, 0.4, 1.6, 0.6), 0.5, 0.0001, "half way in")
	assert_eq(LevelIntroCard.alpha_at(1.0, 0.4, 1.6, 0.6), 1.0, "holding")
	assert_almost_eq(LevelIntroCard.alpha_at(2.3, 0.4, 1.6, 0.6), 0.5, 0.0001, "half way out")
	assert_eq(LevelIntroCard.alpha_at(2.6, 0.4, 1.6, 0.6), 0.0, "gone")
	assert_almost_eq(LevelIntroCard.total_s(0.4, 1.6, 0.6), 2.6, 0.0001)
	assert_almost_eq(LevelIntroCard.total_s(0.4, -1.0, 0.6), 1.0, 0.0001, "a negative hold counts as 0")


func test_hold_and_campaign_helpers() -> void:
	assert_eq(LevelIntroCard.TEXT_FORMAT % 2, "LEVEL 2")
	assert_eq(load("res://scenes/level/level.gd").intro_hold_s(false, 1.6, 0.6), 1.6, "first run: hold_s")
	assert_eq(load("res://scenes/level/level.gd").intro_hold_s(true, 1.6, 0.6), 0.6, "retry: retry_hold_s")
	assert_eq(load("res://scenes/level/level.gd").intro_hold_s(true, 1.6, -1.0), 0.0, "never negative")
	assert_true(load("res://scenes/level/level.gd").is_campaign_level(1, 3))
	assert_true(load("res://scenes/level/level.gd").is_campaign_level(3, 3))
	assert_false(load("res://scenes/level/level.gd").is_campaign_level(0, 3), "dev levels")
	assert_false(load("res://scenes/level/level.gd").is_campaign_level(4, 3))


# --- the card on its own ---------------------------------------------------------------

func test_card_shows_the_level_then_hides() -> void:
	var card: LevelIntroCard = LevelIntroCard.new()
	add_child_autofree(card)
	assert_false(card.visible, "hidden until asked")
	Events.level_intro_started.emit(2, "The Blockade", HOLD_S)
	assert_true(card.visible, "shows on the event")
	assert_true(card.is_showing())
	assert_eq(card.number_label().text, "LEVEL 2")
	assert_eq(card.name_label().text, "THE BLOCKADE", "the name upper-cased")
	assert_eq(card.modulate.a, 0.0, "fades in from nothing")
	assert_eq(card.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(card.process_mode, Node.PROCESS_MODE_PAUSABLE, "freezes with the game")
	await wait_seconds(_total(HOLD_S) + 0.15)
	assert_false(card.visible, "hidden after its whole time")
	assert_false(card.is_showing())


func test_card_layout_comes_from_tuning() -> void:
	var card: LevelIntroCard = LevelIntroCard.new()
	add_child_autofree(card)
	Events.level_intro_started.emit(1, "Cargo Ambush", HOLD_S)
	var number: Label = card.number_label()
	var center_y: float = Config.num("ui.level_intro.center_y")
	assert_almost_eq(number.position.y + number.size.y / 2.0, center_y, 0.5, "the number centred on center_y")
	assert_eq(number.get_theme_font_size(&"font_size"), int(Config.num("ui.level_intro.number_px")))
	assert_eq(card.name_label().get_theme_font_size(&"font_size"), int(Config.num("ui.level_intro.name_px")))
	assert_gt(card.name_label().position.y, number.position.y, "the name sits under the number")


func test_card_shows_nothing_on_a_failed_config() -> void:
	var card: LevelIntroCard = LevelIntroCard.new()
	add_child_autofree(card)
	Config.assert_on_missing = false
	Config.load_error = "broken"
	Events.level_intro_started.emit(1, "Cargo Ambush", HOLD_S)
	assert_false(card.visible, "no card on a failed config")


# --- the level's start gating ----------------------------------------------------------

func test_level_has_the_card_node() -> void:
	_make_level("dev", false)
	assert_not_null(_card(), "HUD/LevelIntroCard")


func test_campaign_level_waits_for_the_card() -> void:
	_make_level("1")
	assert_signal_emitted_with_parameters(Events, "level_intro_started", [1, "Cargo Ambush", HOLD_S])
	assert_true(_card().visible, "the card shows")
	assert_signal_not_emitted(Events, "wave_started", "wave 1 waits for the card")
	await wait_seconds(_total(HOLD_S) + 0.3)
	assert_signal_emitted(Events, "wave_started", "wave 1 after the card")
	assert_false(_card().visible, "the card is gone")


func test_retry_uses_the_short_hold() -> void:
	GameState.is_retry = true
	_make_level("1")
	assert_signal_emitted_with_parameters(Events, "level_intro_started", [1, "Cargo Ambush", RETRY_HOLD_S])
	assert_signal_not_emitted(Events, "wave_started")
	await wait_seconds(_total(RETRY_HOLD_S) + 0.3)
	assert_signal_emitted(Events, "wave_started")


func test_retry_hold_zero_skips_the_card() -> void:
	((Config.tuning["ui"] as Dictionary)["level_intro"] as Dictionary)["retry_hold_s"] = 0
	GameState.is_retry = true
	_make_level("1")
	assert_signal_not_emitted(Events, "level_intro_started", "no card")
	assert_false(_card().visible)
	await wait_seconds(0.2)
	assert_signal_emitted(Events, "wave_started", "wave 1 at once")


func test_dev_level_has_no_card() -> void:
	_make_level("dev")
	assert_signal_not_emitted(Events, "level_intro_started")
	assert_false(_card().visible)


func test_intro_card_false_starts_at_once() -> void:
	_make_level("1", false)
	assert_signal_not_emitted(Events, "level_intro_started")
	await wait_seconds(0.2)
	assert_signal_emitted(Events, "wave_started")


func test_a_pause_freezes_the_wait() -> void:
	_make_level("1")
	PauseArbiter.push(TEST_PAUSE)
	# GUT's wait_seconds stops under a pause: wait on a process-always timer.
	await get_tree().create_timer(_total(HOLD_S) + 0.3, true, false, true).timeout
	assert_signal_not_emitted(Events, "wave_started", "frozen while paused")
	assert_true(_card().visible, "the card stays up")
	PauseArbiter.pop(TEST_PAUSE)
	await wait_seconds(_total(HOLD_S) + 0.3)
	assert_signal_emitted(Events, "wave_started", "starts once unpaused")
