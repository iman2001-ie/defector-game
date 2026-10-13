class_name LevelBackground
extends Node2D
## The level's backdrop, chosen by the level data's `background` id (Story 7.6,
## architecture Scene Structure: "Background (Node2D), chosen by level data").
## It is level.tscn's first child, so it draws behind World. level.gd calls
## apply(level.background_id(data)) once in _ready, before the WaveDirector
## starts.
##
## Only the throne world draws anything for now: a code-drawn placeholder
## planet arc (a large dark violet disc whose bottom hangs a shallow
## ARC_HEIGHT_PX down from the top edge of the playfield, plus a thin, slightly
## lighter rim): the siege is fought below the throne world, so it protrudes
## from the top, behind the HUD band, the Flagship and the enemy rows (playtest
## 2026-10-13; it rose from the bottom edge before). The GDD keeps the throne
## world to Level 3 alone, so it lands as a reveal.
## space_1 and space_2 are known ids that draw nothing until Epic 8, which also
## replaces this placeholder with art. An empty id (dev levels) draws nothing
## and logs nothing; any other id logs one `[WARN][scene]` line and is treated
## as none.
##
## The colours stay dark (every channel below render.glow.hdr_threshold, so the
## arc adds no HDR glow; only the scene-wide bloom applies, as to every pixel)
## and violet, never the enemy magenta or danger red. They and the geometry are
## placeholder-art constants, not GDD tuning numbers (like the ally's
## placeholder hull). Godot draws the node once when it enters the tree (it
## draws nothing then, before apply()), and again only when apply() queues a
## redraw; the canvas caches the result, so nothing is allocated per frame.

## Every background id a level may name (the data test
## test_throne_world_background_only_in_level_3 checks every level file).
const IDS: Array[String] = ["space_1", "space_2", "throne_world"]
const THRONE_WORLD: String = "throne_world"

## The planet's radius; its centre sits above the playfield so only a shallow
## arc of the disc shows along the top edge.
const PLANET_RADIUS_PX: float = 1600.0
## How far the bottom of the arc hangs below the playfield's top edge.
const ARC_HEIGHT_PX: float = 180.0
## The arc's ends sit this far above the top edge, so the closing chord of
## the filled cap and the rim's cut ends stay off-screen. It must exceed the
## largest tuned screen shake (the feedback tiers' shake_px and
## comms.cutoff_shake_px; ShakeCamera offsets the view by up to that much),
## which test_edge_margin_exceeds_every_tuned_shake checks.
const EDGE_MARGIN_PX: float = 64.0
const ARC_SEGMENTS: int = 160
## A dark, desaturated violet disc (#1A1426) and a slightly lighter rim (#42365C).
const PLANET_COLOR: Color = Color(0.101961, 0.078431, 0.149020, 1.0)
const RIM_COLOR: Color = Color(0.258824, 0.211765, 0.360784, 1.0)
const RIM_PX: float = 3.0

var _id: String = ""


## Shows the background `id` (one of IDS) and queues one redraw. "" shows
## nothing; an unknown id logs one WARN and shows nothing.
func apply(id: String) -> void:
	if not id.is_empty() and not IDS.has(id):
		Log.warn("scene", "Unknown level background '%s' (known: %s); drawing none" % [id, ", ".join(PackedStringArray(IDS))])
		id = ""
	_id = id
	queue_redraw()


## The id being shown ("" for none).
func background_id() -> String:
	return _id


func shows_throne_world() -> bool:
	return _id == THRONE_WORLD


## The planet's centre: horizontally centred, ARC_HEIGHT_PX of the disc below
## the playfield's top edge.
static func planet_centre() -> Vector2:
	return Vector2(Playfield.SIZE.x / 2.0, ARC_HEIGHT_PX - PLANET_RADIUS_PX)


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
	if not shows_throne_world():
		return
	var points: PackedVector2Array = arc_points()
	# The cap: the arc closed by its off-screen chord.
	draw_colored_polygon(points, PLANET_COLOR)
	draw_polyline(points, RIM_COLOR, RIM_PX, true)
