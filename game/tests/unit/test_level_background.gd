extends GutTest
## Story 7.6: LevelBackground on level.tscn's Background node. apply(id) with
## the throne world, a space id, "" (dev levels) and an unknown id; only the
## unknown id warns, and only the throne world is shown (a code-drawn
## placeholder planet arc until Epic 8). The placeholder colours stay dark
## (below render.glow.hdr_threshold, so they don't bloom) and violet, never the
## enemy magenta or danger red. On the real level.tscn, levels 1 and 2 never
## show the throne world and level 3 does, with the Background drawn before
## World. level.gd's static background_id(data) reads the data's key like
## ally_id. How the reveal reads is an operator playtest and is not claimed here.

const LEVEL_SCENE: PackedScene = preload("res://scenes/level/level.tscn")
const TEST_SAVE: String = "user://test_level_background_save.cfg"
## The UX `enemy` magenta and `danger` red the placeholder must not read as.
const ENEMY_COLOR: Color = Color("#FF2BD6")
const DANGER_COLOR: Color = Color("#FF1F4B")

var _lines: Array[String] = []
var _scene_calls: Array[String] = []


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _record_scene(path: String) -> Error:
	_scene_calls.append(path)
	return OK


func before_each() -> void:
	_lines.clear()
	_scene_calls.clear()
	SaveManager.save_path = TEST_SAVE
	_delete_save()
	_reset_game_state()
	SceneRouter.change_scene = _record_scene
	Log.sink = _capture


func after_each() -> void:
	Log.sink = Callable()
	SceneRouter.change_scene = SceneRouter.default_change_scene()
	_delete_save()
	SaveManager.save_path = SaveManager.DEFAULT_SAVE_PATH
	_reset_game_state()
	Audio.stop_music(0.0)
	Config.load_data()
	Feedback.reset()
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	PauseArbiter.clear()


func _reset_game_state() -> void:
	GameState.energy = 0
	GameState.current_level_id = ""
	GameState.is_retry = false
	GameState.highest_unlocked_level = 1
	GameState.all_levels_unlocked = false
	GameState.shown_hints.clear()


func _delete_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)


func _lines_containing(fragment: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.contains(fragment):
			out.append(line)
	return out


func _background() -> LevelBackground:
	var bg: LevelBackground = LevelBackground.new()
	add_child_autofree(bg)
	return bg


# --- apply -----------------------------------------------------------------------

func test_ids() -> void:
	assert_eq(LevelBackground.IDS, ["space_1", "space_2", "throne_world"] as Array[String])
	assert_eq(LevelBackground.THRONE_WORLD, "throne_world")


func test_starts_showing_nothing() -> void:
	var bg: LevelBackground = _background()
	assert_false(bg.shows_throne_world())
	assert_eq(bg.background_id(), "")


func test_throne_world_is_shown() -> void:
	var bg: LevelBackground = _background()
	bg.apply("throne_world")
	assert_true(bg.shows_throne_world(), "the throne world shows")
	assert_eq(bg.background_id(), "throne_world")
	assert_eq(_lines_containing("[WARN]"), [] as Array[String], "no warning")


func test_space_ids_show_no_throne_world() -> void:
	var bg: LevelBackground = _background()
	for id: String in ["space_1", "space_2"]:
		bg.apply(id)
		assert_false(bg.shows_throne_world(), "%s: no throne world" % id)
		assert_eq(bg.background_id(), id)
	assert_eq(_lines_containing("[WARN]"), [] as Array[String], "no warning")


func test_empty_id_draws_nothing_and_does_not_warn() -> void:
	var bg: LevelBackground = _background()
	bg.apply("throne_world")
	bg.apply("")
	assert_false(bg.shows_throne_world(), "no throne world after \"\"")
	assert_eq(bg.background_id(), "")
	assert_eq(_lines_containing("[WARN]"), [] as Array[String], "no warning for \"\"")


func test_unknown_id_warns_once_and_is_treated_as_none() -> void:
	var bg: LevelBackground = _background()
	bg.apply("throne_world")
	bg.apply("nope")
	assert_false(bg.shows_throne_world(), "the unknown id shows nothing")
	assert_eq(bg.background_id(), "", "treated as none")
	assert_eq(_lines_containing("[WARN]").size(), 1, "one warning")
	assert_eq(_lines_containing("[WARN][scene]").size(), 1, "a scene warning")
	assert_eq(_lines_containing("'nope'").size(), 1, "naming the id")


# --- the placeholder art ------------------------------------------------------------

func test_placeholder_colours_are_dark_violet_and_never_enemy_colours() -> void:
	var threshold: float = Config.num("render.glow.hdr_threshold")
	assert_gt(threshold, 0.0, "render.glow.hdr_threshold")
	for color: Color in [LevelBackground.PLANET_COLOR, LevelBackground.RIM_COLOR]:
		assert_lt(maxf(color.r, maxf(color.g, color.b)), threshold, "%s below the glow threshold (no bloom)" % color)
		assert_eq(color.a, 1.0, "%s opaque" % color)
		assert_between(color.h * 360.0, 240.0, 285.0, "%s is violet" % color)
		assert_lte(color.s, 0.5, "%s is desaturated" % color)
		for enemy: Color in [ENEMY_COLOR, DANGER_COLOR]:
			var dh: float = absf(color.h - enemy.h)
			dh = minf(dh, 1.0 - dh) * 360.0
			assert_gt(dh, 25.0, "%s hue is clear of %s" % [color, enemy])
	assert_gt(LevelBackground.RIM_COLOR.v, LevelBackground.PLANET_COLOR.v, "the rim is a little lighter than the disc")


func test_planet_arc_rises_from_the_bottom_edge() -> void:
	var centre: Vector2 = LevelBackground.planet_centre()
	var radius: float = LevelBackground.PLANET_RADIUS_PX
	assert_eq(centre.x, Playfield.SIZE.x / 2.0, "centred horizontally")
	assert_gt(centre.y, Playfield.SIZE.y, "the centre sits below the playfield")
	assert_almost_eq(centre.y - radius, Playfield.SIZE.y - LevelBackground.ARC_HEIGHT_PX, 0.001, "the top of the disc")
	assert_between(LevelBackground.ARC_HEIGHT_PX, 100.0, 300.0, "a shallow arc")
	var points: PackedVector2Array = LevelBackground.arc_points()
	assert_gt(points.size(), 64, "a smooth arc")
	var top: float = INF
	for p: Vector2 in points:
		top = minf(top, p.y)
		assert_almost_eq(p.distance_to(centre), radius, 0.01, "on the planet's edge")
	assert_almost_eq(top, Playfield.SIZE.y - LevelBackground.ARC_HEIGHT_PX, 0.5, "the arc peaks ARC_HEIGHT_PX above the bottom edge")
	assert_gt(points[0].y, Playfield.SIZE.y, "starts below the bottom edge")
	assert_gt(points[points.size() - 1].y, Playfield.SIZE.y, "ends below the bottom edge")
	assert_lt(points[0].x, points[points.size() - 1].x, "left to right")


## The cap's closing chord and the rim's cut ends sit EDGE_MARGIN_PX below the
## bottom edge; ShakeCamera offsets the view by up to a shake's px, so the
## margin must exceed every tuned shake (a later retune can't expose the chord).
func test_edge_margin_exceeds_every_tuned_shake() -> void:
	var largest: float = Config.num("comms.cutoff_shake_px")
	var tiers: Dictionary = Config.section("feedback.tiers")
	assert_gt(tiers.size(), 0, "feedback.tiers")
	for tier: Variant in tiers:
		largest = maxf(largest, float((tiers[tier] as Dictionary).get("shake_px", 0.0)))
	assert_gt(LevelBackground.EDGE_MARGIN_PX, largest, "the edge margin exceeds the largest shake (%s px)" % largest)


# --- level.gd background_id --------------------------------------------------------------

func test_background_id_reads_the_data_key() -> void:
	var level_script: GDScript = load("res://scenes/level/level.gd") as GDScript
	assert_eq(level_script.call("background_id", {"background": "throne_world"}), "throne_world")
	assert_eq(level_script.call("background_id", {"background": "space_1"}), "space_1")
	assert_eq(level_script.call("background_id", {"background": null}), "", "null")
	assert_eq(level_script.call("background_id", {}), "", "absent")
	assert_eq(_lines_containing("[WARN]").size(), 0, "no warning for absent or null")
	assert_eq(level_script.call("background_id", {"background": 3.0}), "", "a number")
	assert_eq(level_script.call("background_id", {"background": ["throne_world"]}), "", "an array")
	assert_eq(_lines_containing("[WARN][scene] Level background").size(), 2, "a WARN per non-String value")


# --- the real level.tscn -----------------------------------------------------------------

func _make_level(level_id: String) -> Node2D:
	var level: Node2D = LEVEL_SCENE.instantiate() as Node2D
	level.set("level_id", level_id)
	level.user_args = PackedStringArray()
	var player: Player = level.get_node("World/Player") as Player
	player.debug_invincible = true
	player.warp_mouse = func(_at: Vector2) -> void: pass
	add_child_autofree(level)
	return level


func test_background_node_is_a_level_background_drawn_before_world() -> void:
	var level: Node2D = _make_level("3")
	var bg: LevelBackground = level.get_node_or_null("Background") as LevelBackground
	assert_not_null(bg, "Background is a LevelBackground")
	if bg == null:
		return
	var world: Node2D = level.get_node("World") as Node2D
	assert_eq(bg.get_index(), 0, "the first child")
	assert_lt(bg.get_index(), world.get_index(), "before World")
	assert_lte(bg.z_index, world.z_index, "not raised above World")
	assert_true(bg.z_as_relative, "z relative to the level")


func test_level_3_shows_the_throne_world() -> void:
	var level: Node2D = _make_level("3")
	var bg: LevelBackground = level.get_node("Background") as LevelBackground
	assert_true(bg.shows_throne_world(), "level 3 shows the throne world")
	assert_eq(_lines_containing("[INFO][scene] Background 'throne_world'").size(), 1, "one INFO line")
	assert_eq(_lines_containing("[WARN][scene]"), [] as Array[String], "no scene warning")


func _assert_no_throne_world(id: String, expected: String) -> void:
	var level: Node2D = _make_level(id)
	var bg: LevelBackground = level.get_node("Background") as LevelBackground
	assert_false(bg.shows_throne_world(), "level %s: no throne world" % id)
	assert_eq(bg.background_id(), expected, "level %s background" % id)
	assert_eq(_lines_containing("[INFO][scene] Background '%s'" % expected).size(), 1, "level %s: one INFO line" % id)
	assert_eq(_lines_containing("[WARN][scene]"), [] as Array[String], "level %s: no scene warning" % id)


func test_level_1_never_shows_the_throne_world() -> void:
	_assert_no_throne_world("1", "space_1")


func test_level_2_never_shows_the_throne_world() -> void:
	_assert_no_throne_world("2", "space_2")


func test_dev_level_has_no_background_and_no_line() -> void:
	var level: Node2D = _make_level("dev")
	var bg: LevelBackground = level.get_node("Background") as LevelBackground
	assert_false(bg.shows_throne_world())
	assert_eq(bg.background_id(), "")
	assert_eq(_lines_containing("Background '"), [] as Array[String], "no background line for a null background")
	assert_eq(_lines_containing("[WARN][scene]"), [] as Array[String], "no scene warning")
