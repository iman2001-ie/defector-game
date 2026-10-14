class_name LevelBackground
extends Node2D
## The level's backdrop, chosen by the level data's `background` id (Story 7.6,
## architecture Scene Structure: "Background (Node2D), chosen by level data").
## It is level.tscn's first child, so it draws behind World. level.gd calls
## apply(level.background_id(data)) once in _ready, before the WaveDirector
## starts. The end screen, the title, the story scene and the Level Select
## thumbnails reuse it (Story 8.2).
##
## Story 8.2: `space_1` and `space_2` tile a recoloured Kenney space texture
## (TEXTURES; every channel <= 127/255, below render.glow.hdr_threshold, so it
## never blooms) over the playfield plus EDGE_MARGIN_PX on every side
## (tile_rect), with texture_repeat on, so a screen shake never shows an edge.
## The throne world tiles `space_2`, then shows the planet on top: the lower
## cap of a sphere whose bottom hangs ARC_HEIGHT_PX down from the top edge of
## the playfield: the siege is fought below the throne world, so it protrudes
## from the top, behind the HUD band, the Flagship and the enemy rows (playtest
## 2026-10-13). Playtest 2026-10-14: it reads as a planet, not a flat band. The
## radius is small enough that both curved edges of the cap come into view, and
## the `Planet` child (a ColorRect over planet_rect(), mouse ignored) runs
## throne_world.gdshader: limb shading lit from the left with a soft terminator,
## slowly drifting violet bands, sparse dim city lights on the night side and a
## thin atmosphere just outside the disc. It is visible only for the throne
## world.
##
## Playtest 2026-10-14 (operator: "small stars, Chicken Invaders style"): every
## non-empty id also shows the `Stars` child, a ColorRect over tile_rect() (above
## the tiles, under the planet, mouse ignored) running starfield.gdshader: three
## parallax layers (render.starfield far / mid / near) of small pale blue-white
## procedural stars drifting straight down, a few of them twinkling. Each
## layer's `density` is stars per 100,000 px^2 (one star per jittered grid cell
## of sqrt(100000 / density) px), `speed_px_s` its downward drift, `size_px`
## its star diameter and `brightness` its peak alpha. step_stars(delta), called
## from _process, advances each layer's scroll in game time (it freezes on pause
## and slows in slow motion) and wraps it at cell_px * STAR_PERIOD_ROWS, where
## the shader's star pattern repeats, so the float never grows and the wrap is
## invisible; the twinkle clock wraps at 1 / twinkle.hz the same way. Read once
## at construction, so an F5 reload applies on the next scene. With a failed
## config (Config.load_error set) no Config getter is called and the field
## stays off, as the title and end screen require.
## The GDD keeps the throne world to Level 3 (plus the epilogue and the end
## screen), so it lands as a reveal. An empty id (dev levels) draws nothing and logs nothing; any
## other id logs one `[WARN][scene]` line and is treated as none.
##
## The surface colours stay dark (every channel below
## render.glow.hdr_threshold, so the surface adds no HDR glow) and violet, never
## the enemy magenta or danger red; only the outermost atmosphere and the
## brightest city lights reach the threshold, faintly. They and the geometry
## are art constants, not GDD tuning numbers. Godot draws the tiles once when
## the node enters the tree (nothing then, before apply()), and again only when
## apply() queues a redraw; the planet is the shader's, so nothing is allocated
## per frame.

## Every background id a level may name (the data test
## test_throne_world_background_only_in_level_3 checks every level file).
const IDS: Array[String] = ["space_1", "space_2", "throne_world"]
const THRONE_WORLD: String = "throne_world"
## The backdrop of the title and the story scene (Story 8.2).
const MENU_BACKGROUND: String = "space_1"
## The tiled space texture per id (the throne world tiles space_2 under its arc).
const TEXTURES: Dictionary[String, Texture2D] = {
	"space_1": preload("res://assets/backgrounds/space_1.png"),
	"space_2": preload("res://assets/backgrounds/space_2.png"),
	"throne_world": preload("res://assets/backgrounds/space_2.png"),
}

## The planet's radius; its centre sits above the playfield so only the cap of
## the disc shows along the top edge, narrow enough that both of its curved
## edges meet the top edge inside the playfield (playtest 2026-10-14).
const PLANET_RADIUS_PX: float = 1100.0
## How far the bottom of the arc hangs below the playfield's top edge. Level
## 3's first formation row (top_y 200) is drawn in front of the cap's lower
## edge and its atmosphere, as the Flagship is.
const ARC_HEIGHT_PX: float = 180.0
## The planet's shader rect starts this far above the top edge, so the cap's
## cut top never shows. It must exceed the
## largest tuned screen shake (the feedback tiers' shake_px and
## comms.cutoff_shake_px; ShakeCamera offsets the view by up to that much),
## which test_edge_margin_exceeds_every_tuned_shake checks.
const EDGE_MARGIN_PX: float = 64.0
const ARC_SEGMENTS: int = 160
## A dark, desaturated violet surface (#1A1426), its lighter bands (#2E2445)
## and a slightly lighter rim line (#42365C).
const PLANET_COLOR: Color = Color(0.101961, 0.078431, 0.149020, 1.0)
const BAND_COLOR: Color = Color(0.180392, 0.141176, 0.270588, 1.0)
const RIM_COLOR: Color = Color(0.258824, 0.211765, 0.360784, 1.0)
## The atmosphere's violet (#6A55A8) and the night side's city lights (#A88BFF,
## drawn at about half strength in tiny dots).
const ATMOSPHERE_COLOR: Color = Color(0.415686, 0.333333, 0.658824, 1.0)
const CITY_COLOR: Color = Color(0.658824, 0.545098, 1.0, 1.0)
## How far the atmosphere reaches outside the disc.
const ATMOSPHERE_PX: float = 30.0
## The direction the light comes from (the left, a little below, in front).
const LIGHT_DIR: Vector3 = Vector3(-1.0, 0.25, 0.25)
## The surface's drift, in radians of longitude per second (barely moving).
const DRIFT_RAD_S: float = 0.003
const PLANET_SHADER: Shader = preload("res://scenes/level/throne_world.gdshader")
const STAR_SHADER: Shader = preload("res://scenes/level/starfield.gdshader")
## The starfield layers, back to front (render.starfield.<layer>).
const STAR_LAYERS: Array[String] = ["far", "mid", "near"]
## Cell rows before the shader's star pattern repeats (its `period` uniform).
const STAR_PERIOD_ROWS: float = 256.0
## The pale blue-white range the stars are drawn in (UX hazardRim #C9D8E8 to text #E8F4FF).
const STAR_COLOR_A: Color = Color("#C9D8E8")
const STAR_COLOR_B: Color = Color("#E8F4FF")

var _id: String = ""
var _planet: ColorRect = null
var _stars: ColorRect = null
var _star_mat: ShaderMaterial = null
## Per layer (x far, y mid, z near): grid cell px, drift px/s and the scroll wrap.
var _star_cell: Vector3 = Vector3.ZERO
var _star_speed: Vector3 = Vector3.ZERO
var _star_wrap: Vector3 = Vector3.ZERO
var _star_scroll: Vector3 = Vector3.ZERO
var _twinkle_period_s: float = 0.0
var _twinkle_t: float = 0.0
## False when the config failed to load: the starfield never shows.
var _stars_enabled: bool = false
## Seconds of game time the planet has been shown (its drift and city twinkle).
var _planet_t: float = 0.0
## False keeps the stars and the planet still (the Level Select thumbnails: at
## their tiny scale moving 1-2 px stars would flicker).
var animate: bool = true


func _init() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_build_stars()
	_planet = ColorRect.new()
	_planet.name = "Planet"
	_planet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_planet.color = Color.WHITE
	var rect: Rect2 = planet_rect()
	_planet.position = rect.position
	_planet.size = rect.size
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = PLANET_SHADER
	mat.set_shader_parameter(&"rect_origin", rect.position)
	mat.set_shader_parameter(&"rect_size", rect.size)
	mat.set_shader_parameter(&"centre", planet_centre())
	mat.set_shader_parameter(&"radius", PLANET_RADIUS_PX)
	mat.set_shader_parameter(&"base_color", PLANET_COLOR)
	mat.set_shader_parameter(&"band_color", BAND_COLOR)
	mat.set_shader_parameter(&"rim_color", RIM_COLOR)
	mat.set_shader_parameter(&"atmosphere_color", ATMOSPHERE_COLOR)
	mat.set_shader_parameter(&"city_color", CITY_COLOR)
	mat.set_shader_parameter(&"light_dir", LIGHT_DIR)
	mat.set_shader_parameter(&"atmosphere_px", ATMOSPHERE_PX)
	mat.set_shader_parameter(&"drift_speed", DRIFT_RAD_S)
	_planet.material = mat
	_planet.visible = false
	add_child(_planet)


## Shows the background `id` (one of IDS) and queues one redraw. "" shows
## nothing; an unknown id logs one WARN and shows nothing.
func apply(id: String) -> void:
	if not id.is_empty() and not IDS.has(id):
		Log.warn("scene", "Unknown level background '%s' (known: %s); drawing none" % [id, ", ".join(PackedStringArray(IDS))])
		id = ""
	_id = id
	_planet.visible = shows_throne_world()
	_stars.visible = _stars_enabled and not _id.is_empty()
	queue_redraw()


## The id being shown ("" for none).
func background_id() -> String:
	return _id


func shows_throne_world() -> bool:
	return _id == THRONE_WORLD


## The texture tiled for the shown id (null for none).
func tile_texture() -> Texture2D:
	return TEXTURES.get(_id) as Texture2D


## The starfield's ColorRect (shown for every non-empty id).
func stars() -> ColorRect:
	return _stars


## Each layer's scroll in px (x far, y mid, z near), always in [0, wrap).
func star_scroll() -> Vector3:
	return _star_scroll


## Each layer's scroll wrap in px: its cell size times STAR_PERIOD_ROWS.
func star_wrap() -> Vector3:
	return _star_wrap


## Each layer's grid cell in px: sqrt(100000 / density), 0 for a layer with no stars.
func star_cell() -> Vector3:
	return _star_cell


## The twinkle clock in seconds, always in [0, 1 / twinkle.hz).
func twinkle_time() -> float:
	return _twinkle_t


## Advances the starfield by `delta` seconds of game time (wrapping each
## layer's scroll and the twinkle clock) and hands the values to the shader.
func step_stars(delta: float) -> void:
	var dt: float = maxf(delta, 0.0)
	for i: int in 3:
		if _star_wrap[i] > 0.0:
			_star_scroll[i] = fposmod(_star_scroll[i] + _star_speed[i] * dt, _star_wrap[i])
	if _twinkle_period_s > 0.0:
		_twinkle_t = fposmod(_twinkle_t + dt, _twinkle_period_s)
	_star_mat.set_shader_parameter(&"scroll_px", _star_scroll)
	_star_mat.set_shader_parameter(&"twinkle_time", _twinkle_t)


func _process(delta: float) -> void:
	if not animate:
		return
	if _stars.visible:
		step_stars(delta)
	if _planet.visible:
		step_planet(delta)


## Advances the planet's game-time clock by `delta` and hands it to the shader.
func step_planet(delta: float) -> void:
	_planet_t += maxf(delta, 0.0)
	(_planet.material as ShaderMaterial).set_shader_parameter(&"time_s", _planet_t)


## The planet's game-time clock in seconds.
func planet_time() -> float:
	return _planet_t


## The planet's ColorRect (shown only for the throne world).
func planet() -> ColorRect:
	return _planet


## Builds the `Stars` child from render.starfield (before the Planet, so it
## draws under it).
func _build_stars() -> void:
	var size: Vector3 = Vector3.ZERO
	var peak: Vector3 = Vector3.ZERO
	var hz: float = 0.0
	var fraction: float = 0.0
	var amount: float = 0.0
	_stars_enabled = Config.load_error.is_empty()
	if _stars_enabled:
		for i: int in STAR_LAYERS.size():
			var key: String = "render.starfield.%s" % STAR_LAYERS[i]
			var density: float = maxf(Config.num(key + ".density"), 0.0)
			_star_cell[i] = sqrt(100000.0 / density) if density > 0.0 else 0.0
			_star_speed[i] = Config.num(key + ".speed_px_s")
			size[i] = maxf(Config.num(key + ".size_px"), 0.0)
			peak[i] = clampf(Config.num(key + ".brightness"), 0.0, 1.0)
			_star_wrap[i] = _star_cell[i] * STAR_PERIOD_ROWS
		hz = maxf(Config.num("render.starfield.twinkle.hz"), 0.0)
		fraction = clampf(Config.num("render.starfield.twinkle.fraction"), 0.0, 1.0)
		amount = clampf(Config.num("render.starfield.twinkle.amount"), 0.0, 1.0)
	_twinkle_period_s = 1.0 / hz if hz > 0.0 else 0.0
	_stars = ColorRect.new()
	_stars.name = "Stars"
	_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stars.color = Color.WHITE
	var rect: Rect2 = tile_rect()
	_stars.position = rect.position
	_stars.size = rect.size
	_star_mat = ShaderMaterial.new()
	_star_mat.shader = STAR_SHADER
	_star_mat.set_shader_parameter(&"rect_origin", rect.position)
	_star_mat.set_shader_parameter(&"rect_size", rect.size)
	_star_mat.set_shader_parameter(&"cell_px", _star_cell)
	_star_mat.set_shader_parameter(&"size_px", size)
	_star_mat.set_shader_parameter(&"brightness", peak)
	_star_mat.set_shader_parameter(&"period", STAR_PERIOD_ROWS)
	_star_mat.set_shader_parameter(&"twinkle_fraction", fraction)
	_star_mat.set_shader_parameter(&"twinkle_amount", amount)
	_star_mat.set_shader_parameter(&"twinkle_hz", hz)
	_star_mat.set_shader_parameter(&"color_a", STAR_COLOR_A)
	_star_mat.set_shader_parameter(&"color_b", STAR_COLOR_B)
	_star_mat.set_shader_parameter(&"scroll_px", _star_scroll)
	_star_mat.set_shader_parameter(&"twinkle_time", _twinkle_t)
	_stars.material = _star_mat
	_stars.visible = false
	add_child(_stars)


## The tiled area: the playfield grown by EDGE_MARGIN_PX on every side.
static func tile_rect() -> Rect2:
	return Playfield.RECT.grow(EDGE_MARGIN_PX)


## The planet's centre: horizontally centred, ARC_HEIGHT_PX of the disc below
## the playfield's top edge.
static func planet_centre() -> Vector2:
	return Vector2(Playfield.SIZE.x / 2.0, ARC_HEIGHT_PX - PLANET_RADIUS_PX)


## The planet's drawn rect: the playfield's width plus EDGE_MARGIN_PX each
## side, from EDGE_MARGIN_PX above the top edge down to the bottom of the
## atmosphere (ARC_HEIGHT_PX + ATMOSPHERE_PX), plus 2 px of slack.
static func planet_rect() -> Rect2:
	var top: float = -EDGE_MARGIN_PX
	var bottom: float = ARC_HEIGHT_PX + ATMOSPHERE_PX + 2.0
	return Rect2(-EDGE_MARGIN_PX, top, Playfield.SIZE.x + 2.0 * EDGE_MARGIN_PX, bottom - top)


## Where the planet's edge crosses the playfield's top edge (y 0): the left and
## right x of that chord.
static func top_edge_crossings() -> Vector2:
	var dy: float = 0.0 - planet_centre().y
	var half: float = sqrt(maxf(PLANET_RADIUS_PX * PLANET_RADIUS_PX - dy * dy, 0.0))
	return Vector2(Playfield.SIZE.x / 2.0 - half, Playfield.SIZE.x / 2.0 + half)


## The visible arc of the planet's edge, left to right, ARC_SEGMENTS + 1 points;
## both ends sit EDGE_MARGIN_PX above the playfield's top edge.
static func arc_points() -> PackedVector2Array:
	var centre: Vector2 = planet_centre()
	# The edge is at y = -margin where cos(half) = (r - h - margin) / r.
	var half: float = acos(clampf((PLANET_RADIUS_PX - ARC_HEIGHT_PX - EDGE_MARGIN_PX) / PLANET_RADIUS_PX, -1.0, 1.0))
	var points: PackedVector2Array = PackedVector2Array()
	points.resize(ARC_SEGMENTS + 1)
	for i: int in ARC_SEGMENTS + 1:
		# From the left end (angle PI / 2 + half) through the bottom (PI / 2) to the right.
		var angle: float = PI / 2.0 + half - 2.0 * half * float(i) / float(ARC_SEGMENTS)
		points[i] = centre + Vector2(cos(angle), sin(angle)) * PLANET_RADIUS_PX
	return points


func _draw() -> void:
	var tiles: Texture2D = tile_texture()
	if tiles != null:
		draw_texture_rect(tiles, tile_rect(), true)
