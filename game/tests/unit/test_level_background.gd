extends GutTest
## Story 7.6: LevelBackground on level.tscn's Background node. apply(id) with
## the throne world, a space id, "" (dev levels) and an unknown id; only the
## unknown id warns, and only the throne world shows the code-drawn planet arc.
## Story 8.2: space_1 / space_2 tile their recoloured Kenney texture over the
## playfield plus EDGE_MARGIN_PX (texture_repeat on), the throne world tiles
## space_2 under its arc, "" and an unknown id tile nothing, and every
## background pixel stays <= 127 so it never blooms. The arc colours stay dark
## (below render.glow.hdr_threshold, so they don't bloom) and violet, never the
## enemy magenta or danger red. On the real level.tscn, levels 1 and 2 never
## show the throne world and level 3 does, with the Background drawn before
## World. level.gd's static background_id(data) reads the data's key like
## ally_id. How the reveal reads is an operator playtest and is not claimed here.

const SpriteProbe: GDScript = preload("res://tests/fixtures/sprite_probe.gd")
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


# --- the tiled space art (Story 8.2) -----------------------------------------------

const SPACE_TEXTURES: Dictionary = {
	"space_1": "res://assets/backgrounds/space_1.png",
	"space_2": "res://assets/backgrounds/space_2.png",
	"throne_world": "res://assets/backgrounds/space_2.png",
}


func test_space_ids_tile_their_texture_over_the_playfield_and_margin() -> void:
	var bg: LevelBackground = _background()
	assert_eq(bg.texture_repeat, CanvasItem.TEXTURE_REPEAT_ENABLED, "repeat on, so the tiles wrap")
	assert_eq(LevelBackground.tile_rect(), Rect2(-LevelBackground.EDGE_MARGIN_PX, -LevelBackground.EDGE_MARGIN_PX,
		Playfield.SIZE.x + 2.0 * LevelBackground.EDGE_MARGIN_PX, Playfield.SIZE.y + 2.0 * LevelBackground.EDGE_MARGIN_PX),
		"the playfield plus the edge margin on every side")
	for id: String in SPACE_TEXTURES:
		bg.apply(id)
		assert_not_null(bg.tile_texture(), "%s tiles a texture" % id)
		if bg.tile_texture() != null:
			assert_eq(bg.tile_texture().resource_path, SPACE_TEXTURES[id], "%s texture" % id)
	assert_eq(_lines_containing("[WARN]"), [] as Array[String], "no warning")


func test_throne_world_tiles_space_2_under_the_arc() -> void:
	var bg: LevelBackground = _background()
	bg.apply("throne_world")
	assert_true(bg.shows_throne_world(), "the arc shows")
	assert_eq(bg.tile_texture(), LevelBackground.TEXTURES["space_2"], "over the space_2 tiles")


func test_empty_and_unknown_ids_tile_nothing() -> void:
	var bg: LevelBackground = _background()
	assert_null(bg.tile_texture(), "nothing before apply")
	bg.apply("space_1")
	bg.apply("")
	assert_null(bg.tile_texture(), "\"\" tiles nothing")
	bg.apply("nope")
	assert_null(bg.tile_texture(), "an unknown id tiles nothing")
	assert_eq(_lines_containing("[WARN][scene]").size(), 1, "the unknown id still warns once")


func test_every_background_pixel_stays_below_the_glow_threshold() -> void:
	var threshold: float = Config.num("render.glow.hdr_threshold")
	for id: String in ["space_1", "space_2"]:
		var tex: Texture2D = LevelBackground.TEXTURES[id]
		var top: float = SpriteProbe.max_channel(tex)
		assert_lte(top, 127.0 / 255.0 + 0.0001, "%s: every channel <= 127" % id)
		assert_lt(top, threshold, "%s: below render.glow.hdr_threshold, never blooms" % id)
		assert_gt(top, 0.0, "%s is not black" % id)
	assert_ne(LevelBackground.TEXTURES["space_1"], LevelBackground.TEXTURES["space_2"], "two distinct backgrounds")


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


## Playtest 2026-10-13: the throne world hangs from the top edge, behind the
## HUD band and the enemy rows, never reaching the player zone.
func test_planet_arc_hangs_from_the_top_edge() -> void:
	var centre: Vector2 = LevelBackground.planet_centre()
	var radius: float = LevelBackground.PLANET_RADIUS_PX
	assert_eq(centre.x, Playfield.SIZE.x / 2.0, "centred horizontally")
	assert_lt(centre.y, 0.0, "the centre sits above the playfield")
	assert_almost_eq(centre.y + radius, LevelBackground.ARC_HEIGHT_PX, 0.001, "the bottom of the disc")
	assert_between(LevelBackground.ARC_HEIGHT_PX, 100.0, 300.0, "a shallow arc")
	assert_lt(LevelBackground.ARC_HEIGHT_PX, Config.num("player.bounds_y.min"), "clear of the player zone")
	var points: PackedVector2Array = LevelBackground.arc_points()
	assert_gt(points.size(), 64, "a smooth arc")
	var bottom: float = -INF
	for p: Vector2 in points:
		bottom = maxf(bottom, p.y)
		assert_almost_eq(p.distance_to(centre), radius, 0.01, "on the planet's edge")
	assert_almost_eq(bottom, LevelBackground.ARC_HEIGHT_PX, 0.5, "the arc hangs ARC_HEIGHT_PX below the top edge")
	assert_lt(points[0].y, 0.0, "starts above the top edge")
	assert_lt(points[points.size() - 1].y, 0.0, "ends above the top edge")
	assert_almost_eq(points[0].y, -LevelBackground.EDGE_MARGIN_PX, 0.5, "the ends sit EDGE_MARGIN_PX off screen")
	assert_lt(points[0].x, points[points.size() - 1].x, "left to right")


## The cap's closing chord and the rim's cut ends sit EDGE_MARGIN_PX above the
## top edge; ShakeCamera offsets the view by up to a shake's px, so the
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
