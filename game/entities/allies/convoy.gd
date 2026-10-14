class_name Convoy
extends Node2D
## The escort convoy (Story 6.1, DW-83, FR32, FR33, GDD #24, #45, #51): three
## nose-up ConvoyShip hulls (Lead, FlankLeft, FlankRight) side by side that move
## as one group and share one HP pool for the level attempt. Spawned only by
## Spawner.spawn_convoy into World/Allies when the level JSON has "convoy": true.
##
## Layout (all numbers from tuning `convoy`; gap_px and lead_raise_px clamped to
## >= 0): flank-left, lead, flank-right from left to right, gap_px apart between
## the drawn hulls, the middle (lead) ship lead_raise_px higher, so the group is
## a shallow symmetric triangle spanning 3 * ship_width_px + 2 * gap_px. For
## left edge `left`, width w, height h, gap g and raise r: flank-left x =
## left + w/2, lead x = left + 1.5w + g, flank-right x = left + 2.5w + 2g. The
## group (height h + r) is centred vertically in band_y: top = band centre -
## (h + r)/2, lead y = top + h/2, flank y = top + r + h/2. The layout never
## mirrors.
##
## Path (GDD #45): it starts fully on-screen at left_x 0 heading right and moves
## at speed_px_s. step_span clamps left_x to [0, Playfield width - span] and
## flips dir at each edge (ping-pong); it never wraps off-screen. direction() is
## still reported but does not change the layout.
##
## HP: hp() starts at convoy.hp and is broadcast through
## Events.convoy_hp_changed (in _ready, then on every hit). It is never reset by
## a wave change; only a scene reload refills it. apply_damage(n) with n > 0
## lowers it (floored at 0); at 0 it logs the loss and emits
## Events.level_failed(&"convoy") once. The first outcome wins: after
## level_cleared or any level_failed every hit is ignored (no HP change, no events).
##
## Death (playtest pt7-g): at HP 0 the convoy stops moving and, right after the
## failure, blows up ship by ship: Feedback.convoy_death over the ship centres in
## DEATH_ORDER (the lead first, then the flanks), each ConvoyShip.destroy()ed
## (hidden, no longer hittable) as its explosion plays. A lost convoy is no
## longer solid (the Player stops resolving against its hull).
##
## Solid hull (DW-83, GDD #51): hull_polygon() returns the cached formation
## polygon, the convex outline of the three global hitbox rects with the gaps
## included (6 points: flank-left bottom-left and top-left, lead top-left and
## top-right, flank-right top-right and bottom-right). It is refreshed in place
## every physics tick (no allocation), and the Player's hull resolution reads
## it. The per-ship hitboxes still serve shots and Mauls.

const SHIP_NAMES: Array[StringName] = [&"Lead", &"FlankLeft", &"FlankRight"]
## Index of each ship in SHIP_NAMES and ship_centres().
const LEAD: int = 0
const FLANK_LEFT: int = 1
const FLANK_RIGHT: int = 2
## The ship count the layout supports.
const LAYOUT_SHIPS: int = 3
## Points in hull_polygon().
const HULL_POINTS: int = 6
## The order the ships blow up in when the convoy is lost.
const DEATH_ORDER: Array[int] = [LEAD, FLANK_LEFT, FLANK_RIGHT]

var ship_width: float = 0.0
var ship_height: float = 0.0
## convoy.gap_px: the horizontal gap between neighbouring drawn hulls.
var gap: float = 0.0
## convoy.lead_raise_px: how much higher the lead sits than the flankers.
var lead_raise: float = 0.0
var speed_px_s: float = 0.0
var band_min: float = 0.0
var band_max: float = 0.0

var _hp: int = 0
var _max_hp: int = 0
var _lost: bool = false
## Set by level_cleared or any level_failed: the outcome is decided.
var _ended: bool = false
var _left_x: float = 0.0
var _dir: int = 1
var _ships: Array[ConvoyShip] = []
var _polygon: PackedVector2Array = PackedVector2Array()


## Stores params before add_child; no keys yet (the layout and HP are tuning).
func setup(_params: Dictionary) -> void:
	pass


func _ready() -> void:
	ship_width = maxf(Config.num("convoy.ship_width_px"), 0.0)
	ship_height = maxf(Config.num("convoy.ship_height_px"), 0.0)
	gap = maxf(Config.num("convoy.gap_px"), 0.0)
	lead_raise = maxf(Config.num("convoy.lead_raise_px"), 0.0)
	speed_px_s = maxf(Config.num("convoy.speed_px_s"), 0.0)
	band_min = Config.num("convoy.band_y.min")
	band_max = Config.num("convoy.band_y.max")
	var ships: int = Config.int_("convoy.ships")
	if ships != LAYOUT_SHIPS:
		Log.warn("data", "convoy.ships is %d but the convoy layout has %d ships; using %d" % [ships, LAYOUT_SHIPS, LAYOUT_SHIPS])
	add_to_group(Groups.CONVOY)
	for ship_name: StringName in SHIP_NAMES:
		var ship: ConvoyShip = get_node(NodePath(ship_name)) as ConvoyShip
		ship.convoy = self
		_ships.append(ship)
	_polygon.resize(HULL_POINTS)
	Events.level_cleared.connect(_on_events_level_cleared)
	Events.level_failed.connect(_on_events_level_failed)
	_left_x = 0.0
	_dir = 1
	_place_ships()
	_max_hp = maxi(Config.int_("convoy.hp"), 0)
	_hp = _max_hp
	Events.convoy_hp_changed.emit(_hp, _max_hp)


func _physics_process(delta: float) -> void:
	step(delta)


## One movement tick: advance the span by speed_px_s * delta and re-place the
## ships. A lost convoy stays where it died.
func step(delta: float) -> void:
	if _lost:
		return
	var next: Vector2 = step_span(_left_x, _dir, speed_px_s * delta, span(), Playfield.SIZE.x)
	_left_x = next.x
	_dir = int(next.y)
	_place_ships()


# --- Read accessors ---------------------------------------------------------------

func hp() -> int:
	return _hp


func max_hp() -> int:
	return _max_hp


## True once HP reached 0 (the convoy-loss failure was emitted).
func is_lost() -> bool:
	return _lost


## The group's left edge (sprite extents).
func left_x() -> float:
	return _left_x


## +1 heading right, -1 heading left (the layout is the same either way).
func direction() -> int:
	return _dir


## The group width: 3 * ship_width + 2 * gap.
func span() -> float:
	return group_span(ship_width, gap)


## The ships in SHIP_NAMES order (Lead, FlankLeft, FlankRight).
func ships() -> Array[ConvoyShip]:
	return _ships


## The cached solid formation polygon (6 global points, see the class doc),
## refreshed in place each tick.
func hull_polygon() -> PackedVector2Array:
	return _polygon


# --- Damage -----------------------------------------------------------------------

## Lowers the shared HP by `amount` (floored at 0) and broadcasts it; at 0 the
## convoy is lost and Events.level_failed(&"convoy") fires once. Ignored when
## amount <= 0, once lost and once the level outcome is decided.
func apply_damage(amount: int, _source: Node) -> void:
	if amount <= 0 or _lost or _ended:
		return
	_hp = maxi(_hp - amount, 0)
	Events.convoy_hp_changed.emit(_hp, _max_hp)
	if _hp == 0:
		_lost = true
		Log.info("combat", "Convoy lost: HP reached 0")
		Events.level_failed.emit(&"convoy")
		_explode()


## The ship centres in DEATH_ORDER (the explosion chain's positions).
func death_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for index: int in DEATH_ORDER:
		if index < _ships.size() and is_instance_valid(_ships[index]):
			out.append(_ships[index].global_position)
	return out


## Starts the explosion chain over the ships (playtest pt7-g).
func _explode() -> void:
	Feedback.convoy_death(death_positions(), _on_death_step)


## Explosion `k` of the chain is playing: destroy that ship.
func _on_death_step(k: int) -> void:
	if k < 0 or k >= DEATH_ORDER.size() or DEATH_ORDER[k] >= _ships.size():
		return
	# Check before typing: a typed variable rejects a freed instance.
	var ship: Variant = _ships[DEATH_ORDER[k]]
	if is_instance_valid(ship):
		(ship as ConvoyShip).destroy()


## True once every ship has blown up in the death chain (or none is left), so
## the player can fly through the wreck site (playtest pt7-g review).
func is_wrecked() -> bool:
	for ship: Variant in _ships:
		if is_instance_valid(ship) and not (ship as ConvoyShip).is_destroyed():
			return false
	return true


func _on_events_level_cleared(_level_id: int) -> void:
	_ended = true


func _on_events_level_failed(_reason: StringName) -> void:
	_ended = true


# --- Layout -----------------------------------------------------------------------

## Positions every ship for the current left_x and refreshes the cached hull
## polygon in place (no allocation).
func _place_ships() -> void:
	for i: int in _ships.size():
		_ships[i].global_position = ship_centre(i, _left_x, ship_width, ship_height, gap, lead_raise, band_min, band_max)
	var left: Rect2 = _ships[FLANK_LEFT].hull_rect()
	var lead: Rect2 = _ships[LEAD].hull_rect()
	var right: Rect2 = _ships[FLANK_RIGHT].hull_rect()
	_polygon[0] = Vector2(left.position.x, left.end.y)
	_polygon[1] = left.position
	_polygon[2] = lead.position
	_polygon[3] = Vector2(lead.end.x, lead.position.y)
	_polygon[4] = Vector2(right.end.x, right.position.y)
	_polygon[5] = right.end


## The group width for three hulls `w` wide with `g` between neighbours.
static func group_span(w: float, g: float) -> float:
	return 3.0 * w + 2.0 * g


## Advances the group's left edge by `distance` in `dir` and clamps it to
## [0, width - span]; reaching an edge while moving into it flips the direction.
## Returns Vector2(new left_x, new dir).
static func step_span(left: float, dir: int, distance: float, group_width: float, width: float) -> Vector2:
	var hi: float = maxf(width - group_width, 0.0)
	var d: int = -1 if dir < 0 else 1
	var next: float = left + float(d) * maxf(distance, 0.0)
	if d > 0 and next >= hi:
		return Vector2(hi, -1.0)
	if d < 0 and next <= 0.0:
		return Vector2(0.0, 1.0)
	return Vector2(clampf(next, 0.0, hi), float(d))


## The centre of ship `index` (LEAD, FLANK_LEFT, FLANK_RIGHT) for a group whose
## left edge is `left`: hulls w x h, `g` apart, the lead raised by `raise`, the
## group centred in band_lo..band_hi (see the class doc for the layout).
static func ship_centre(index: int, left: float, w: float, h: float, g: float, raise: float, band_lo: float, band_hi: float) -> Vector2:
	var top: float = (band_lo + band_hi) / 2.0 - (h + raise) / 2.0
	if index == LEAD:
		return Vector2(left + 1.5 * w + g, top + h / 2.0)
	if index == FLANK_LEFT:
		return Vector2(left + w / 2.0, top + raise + h / 2.0)
	return Vector2(left + 2.5 * w + 2.0 * g, top + raise + h / 2.0)


## Every ship centre, in SHIP_NAMES order (allocates; the tick uses ship_centre).
static func ship_centres(left: float, w: float, h: float, g: float, raise: float, band_lo: float, band_hi: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i: int in LAYOUT_SHIPS:
		out.append(ship_centre(i, left, w, h, g, raise, band_lo, band_hi))
	return out
