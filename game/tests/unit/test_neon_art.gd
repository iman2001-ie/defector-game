extends GutTest
## Story 8.2 (Make the Game Look Neon), the cross-cutting checks: five distinct
## magenta enemy silhouettes (the Hunter Wasp is the Wasp in orange), every
## enemy hull a white-modulated Sprite2D fitted to sprite_px, SpriteFit's
## bad-size rule, the comms portraits map, and the shared Theme: Kenney Future
## as the default font, the dialogue and cue fonts kept on the engine font, and
## the LevelClearBanner type replacing level.tscn's overrides. Per-entity art
## pins live in each entity's own test file. How the art looks in play is owed
## to the operator, not claimed here.

const SpriteProbe: GDScript = preload("res://tests/fixtures/sprite_probe.gd")
const THEME_PATH: String = "res://ui/theme/defector_theme.tres"
const FONT_PATH: String = "res://assets/fonts/kenvector_future.ttf"
const LEVEL_SCENE: PackedScene = preload("res://scenes/level/level.tscn")
const COMMS_PANEL_SCENE: PackedScene = preload("res://systems/comms/comms_panel.tscn")
const COMMS_BOX_SCENE: PackedScene = preload("res://systems/comms/comms_box.tscn")
const ENEMY_COLOR: Color = Color("#FF2BD6")
const HUNTER_COLOR: Color = Color("#FF8A1F")
## type id -> [scene, hull texture].
const ENEMIES: Dictionary = {
	&"wasp": ["res://entities/enemies/wasp/wasp.tscn", "res://assets/sprites/enemies/enemy_wasp.png"],
	&"lancer": ["res://entities/enemies/lancer/lancer.tscn", "res://assets/sprites/enemies/enemy_lancer.png"],
	&"needle": ["res://entities/enemies/needle/needle.tscn", "res://assets/sprites/enemies/enemy_needle.png"],
	&"bastion": ["res://entities/enemies/bastion/bastion.tscn", "res://assets/sprites/enemies/enemy_bastion.png"],
	&"maul": ["res://entities/enemies/maul/maul.tscn", "res://assets/sprites/enemies/enemy_maul.png"],
	&"hunter_wasp": ["res://entities/enemies/hunter_wasp/hunter_wasp.tscn", "res://assets/sprites/enemies/enemy_hunter_wasp.png"],
}

var _lines: Array[String] = []


func before_each() -> void:
	_lines.clear()
	Log.sink = _capture


func after_each() -> void:
	Log.sink = Callable()


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _warnings() -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.begins_with("[WARN]"):
			out.append(line)
	return out


func _make_enemy(type_id: StringName, sprite_px: float = -1.0) -> Enemy:
	var scene: PackedScene = load(str((ENEMIES[type_id] as Array)[0])) as PackedScene
	var enemy: Enemy = scene.instantiate() as Enemy
	enemy.type_id = type_id
	if sprite_px >= 0.0:
		enemy.sprite_px = sprite_px
	enemy.setup({"position": Vector2(960, 300)})
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	return enemy


# --- Enemies ------------------------------------------------------------------------

func test_every_enemy_hull_is_a_white_sprite_fitted_to_sprite_px() -> void:
	for type_id: StringName in ENEMIES:
		var enemy: Enemy = _make_enemy(type_id)
		var hull: Sprite2D = enemy.get_node_or_null("Hull") as Sprite2D
		assert_not_null(hull, "%s Hull is a Sprite2D" % type_id)
		if hull == null:
			continue
		assert_eq(hull.texture.resource_path, str((ENEMIES[type_id] as Array)[1]), "%s texture" % type_id)
		assert_almost_eq(SpriteProbe.longest_side(hull), enemy.sprite_px, 1.0, "%s longer side = sprite_px" % type_id)
		assert_eq(hull.position, Vector2.ZERO, "%s centred" % type_id)
		assert_eq(hull.rotation, 0.0, "%s: the texture already faces +y" % type_id)
		assert_eq(hull.modulate, Color.WHITE, "%s modulate white" % type_id)
		assert_eq(hull.self_modulate, Color.WHITE, "%s self_modulate white" % type_id)
		var hue: Color = HUNTER_COLOR if type_id == &"hunter_wasp" else ENEMY_COLOR
		assert_lt(SpriteProbe.hue_distance_deg(SpriteProbe.dominant_hue(hull.texture), hue.h), 8.0, "%s hue" % type_id)
	assert_eq(_warnings(), [] as Array[String], "no warning")


func test_five_distinct_silhouettes_and_the_hunter_is_the_orange_wasp() -> void:
	var seen: Dictionary = {}
	for type_id: StringName in [&"wasp", &"lancer", &"needle", &"bastion", &"maul"]:
		var tex: Texture2D = load(str((ENEMIES[type_id] as Array)[1])) as Texture2D
		var key: String = "%s" % tex.get_size()
		assert_false(seen.has(key), "%s has its own silhouette (size %s)" % [type_id, key])
		seen[key] = type_id
	var wasp: Texture2D = load(str((ENEMIES[&"wasp"] as Array)[1])) as Texture2D
	var hunter: Texture2D = load(str((ENEMIES[&"hunter_wasp"] as Array)[1])) as Texture2D
	assert_eq(hunter.get_size(), wasp.get_size(), "the Hunter shares the Wasp's silhouette (GDD)")
	assert_gt(SpriteProbe.hue_distance_deg(SpriteProbe.dominant_hue(hunter), SpriteProbe.dominant_hue(wasp)), 60.0, "a distinct orange tint")


## The I/O matrix "Bad fit size" row: sprite_px <= 0 leaves the scale at 1 and
## warns once.
func test_bad_sprite_px_warns_once_and_keeps_scale_one() -> void:
	var wasp: Enemy = _make_enemy(&"wasp", 0.0)
	var hull: Sprite2D = wasp.get_node("Hull") as Sprite2D
	assert_eq(hull.scale, Vector2.ONE, "scale left at 1")
	assert_eq(_warnings().size(), 1, "one warning")
	assert_true(_warnings()[0].begins_with("[WARN][data]") and _warnings()[0].contains("wasp"), "a data warning naming the wasp")


# --- SpriteFit ---------------------------------------------------------------------

func _sprite(size: Vector2i) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	if size != Vector2i.ZERO:
		sprite.texture = ImageTexture.create_from_image(Image.create(size.x, size.y, false, Image.FORMAT_RGBA8))
	add_child_autofree(sprite)
	return sprite


func test_fit_longest() -> void:
	var sprite: Sprite2D = _sprite(Vector2i(100, 50))
	assert_true(SpriteFit.fit_longest(sprite, 64.0, "test"))
	assert_almost_eq(sprite.scale.x, 0.64, 0.0001)
	assert_eq(sprite.scale.x, sprite.scale.y, "uniform")
	assert_eq(SpriteFit.drawn_size(sprite), Vector2(64, 32))
	var tall: Sprite2D = _sprite(Vector2i(20, 80))
	SpriteFit.fit_longest(tall, 40.0, "test")
	assert_eq(SpriteFit.drawn_size(tall), Vector2(10, 40))
	assert_eq(_warnings(), [] as Array[String])


func test_fit_inside() -> void:
	var sprite: Sprite2D = _sprite(Vector2i(136, 84))
	assert_true(SpriteFit.fit_inside(sprite, Vector2(160, 80), "test"))
	var drawn: Vector2 = SpriteFit.drawn_size(sprite)
	assert_almost_eq(drawn.y, 80.0, 0.001, "height-limited")
	assert_lt(drawn.x, 160.0)
	var wide: Sprite2D = _sprite(Vector2i(200, 20))
	SpriteFit.fit_inside(wide, Vector2(160, 80), "test")
	assert_almost_eq(SpriteFit.drawn_size(wide).x, 160.0, 0.001, "width-limited")


func test_bad_fits_warn_and_leave_the_scale() -> void:
	var no_texture: Sprite2D = _sprite(Vector2i.ZERO)
	assert_false(SpriteFit.fit_longest(no_texture, 64.0, "no texture"))
	assert_eq(no_texture.scale, Vector2.ONE)
	var sprite: Sprite2D = _sprite(Vector2i(10, 10))
	assert_false(SpriteFit.fit_longest(sprite, 0.0, "zero px"))
	assert_false(SpriteFit.fit_longest(sprite, -3.0, "negative px"))
	assert_false(SpriteFit.fit_inside(sprite, Vector2(0, 10), "zero box"))
	assert_false(SpriteFit.fit_longest(null, 10.0, "null sprite"))
	assert_eq(sprite.scale, Vector2.ONE, "scale left at 1")
	assert_eq(_warnings().size(), 5, "one warning per bad fit")
	for line: String in _warnings():
		assert_true(line.begins_with("[WARN][data]"), line)
	assert_eq(SpriteFit.drawn_size(no_texture), Vector2.ZERO)


# --- Portraits -----------------------------------------------------------------------

func test_portraits_map_every_portrait_speaker() -> void:
	var speakers: Dictionary = Config.section("comms.speakers")
	for id: String in speakers:
		var row: Dictionary = speakers[id]
		var has: bool = row.get("portrait") is bool and bool(row.get("portrait"))
		if has:
			assert_not_null(CommsPortraits.texture_for(StringName(id)), "%s has a portrait texture" % id)
		else:
			assert_null(CommsPortraits.texture_for(StringName(id)), "%s has none" % id)
	assert_eq(CommsPortraits.TEXTURES.size(), 3, "isolde, tarek, ryn")
	for id: StringName in CommsPortraits.TEXTURES:
		var tex: Texture2D = CommsPortraits.TEXTURES[id]
		assert_eq(tex.resource_path, "res://assets/portraits/portrait_%s.svg" % id)
		assert_eq(tex.get_size(), Vector2(200, 200), "%s: 200 x 200" % id)


func test_portrait_image_rect_insets_by_the_frame_border() -> void:
	var flat: StyleBoxFlat = StyleBoxFlat.new()
	flat.set_border_width_all(2)
	assert_eq(CommsPortraits.image_rect(Vector2(88, 88), flat), Rect2(2, 2, 84, 84))
	assert_eq(CommsPortraits.image_rect(Vector2(88, 88), StyleBoxEmpty.new()), Rect2(0, 0, 88, 88))
	assert_eq(CommsPortraits.image_rect(Vector2(88, 88), null), Rect2(0, 0, 88, 88))


# --- Theme and font --------------------------------------------------------------------

func test_default_font_is_kenney_future() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	assert_true(theme.has_default_font(), "the Theme has a default font")
	assert_eq(theme.default_font.resource_path, FONT_PATH, "Kenney Future")


func test_dialogue_and_cue_fonts_keep_the_engine_font() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	for pair: Array in [[&"text", &"CommsPanel"], [&"cue", &"CommsPanel"], [&"text", &"CommsBox"]]:
		assert_true(theme.has_font(pair[0] as StringName, pair[1] as StringName), "%s/fonts/%s" % [pair[1], pair[0]])
		var font: FontVariation = theme.get_font(pair[0] as StringName, pair[1] as StringName) as FontVariation
		assert_not_null(font, "%s/fonts/%s is a FontVariation" % [pair[1], pair[0]])
		if font != null:
			assert_null(font.base_font, "%s/fonts/%s has no base: the engine font, not Kenney Future" % [pair[1], pair[0]])
			assert_ne(font, theme.default_font)


func test_comms_panel_applies_the_dialogue_fonts_and_names_use_kenney_future() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	var panel: CommsPanel = COMMS_PANEL_SCENE.instantiate() as CommsPanel
	add_child_autofree(panel)
	assert_eq((panel.get_node("Panel/Text") as Label).get_theme_font(&"font"), theme.get_font(&"text", &"CommsPanel"), "dialogue font")
	assert_eq((panel.get_node("Panel/Cue") as Label).get_theme_font(&"font"), theme.get_font(&"cue", &"CommsPanel"), "cue font")
	assert_eq((panel.get_node("Panel/Name") as Label).get_theme_font(&"font"), theme.default_font, "the name in Kenney Future")
	var box: CommsBox = COMMS_BOX_SCENE.instantiate() as CommsBox
	add_child_autofree(box)
	assert_eq((box.get_node("Box/Name") as Label).get_theme_font(&"font"), theme.default_font, "the box name in Kenney Future")
	assert_eq((box.get_node("Box/Text") as Label).get_theme_font(&"font"), theme.get_font(&"text", &"CommsBox"), "box dialogue font")


func test_level_clear_banner_type_replaces_the_overrides() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	assert_eq(theme.get_type_variation_base(&"LevelClearBanner"), &"Label", "a Label variation")
	assert_eq(theme.get_color(&"font_color", &"LevelClearBanner").to_html(false), "22e6ff", "coalition")
	assert_eq(theme.get_font_size(&"font_size", &"LevelClearBanner"), 120)
	var level: Node = LEVEL_SCENE.instantiate()
	var banner: Label = level.get_node("HUD/LevelClearBanner") as Label
	assert_eq(banner.theme_type_variation, &"LevelClearBanner")
	assert_eq(banner.theme, theme, "the shared Theme")
	assert_false(banner.has_theme_color_override(&"font_color"), "no colour override")
	assert_false(banner.has_theme_font_size_override(&"font_size"), "no size override")
	level.free()
