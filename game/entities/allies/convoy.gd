class_name Convoy
extends Node2D
## The escort convoy (Story 6.1, FR32, FR33, GDD #24, #45): three ConvoyShip
## hulls (Lead, FlankTop, FlankBottom) in a tight triangle that move as one group
## and share one HP pool for the level attempt. Spawned only by
## Spawner.spawn_convoy into World/Allies when the level JSON has "convoy": true.
##
## Layout (all numbers from tuning `convoy`): the flankers are centred at y
## band_y.min + h/2 and band_y.max - h/2, the lead at the band centre. The
## lead's rear edge is lead_offset_px ahead of the flankers' front edges, so the
## group spans 2 * ship_width_px + lead_offset_px. The group tracks its left
## edge (left_x) and direction (dir). Heading right, the flankers are at
## left_x + w/2 and the lead at left_x + w + gap + w/2; heading left the
## triangle is mirrored (lead at left_x + w/2), so the lead always leads.
##
## Path (GDD #45): it starts fully on-screen at left_x 0 heading right and moves
## at speed_px_s. step_span clamps left_x to [0, Playfield width - span] and
## flips dir at each edge (ping-pong); it never wraps off-screen.
##
## HP: hp() starts at convoy.hp and is broadcast through
## Events.convoy_hp_changed (in _ready, then on every hit). It is never reset by
## a wave change; only a scene reload refills it. apply_damage(n) with n > 0
## lowers it (floored at 0); at 0 it logs the loss and emits
## Events.level_failed(&"convoy") once. The first outcome wins: after
## level_cleared or any level_failed every hit is ignored (no HP change, no events).
##
## hull_rects() returns the cached global hitbox rects (refreshed every physics
## tick, no allocation), which the Player's hull resolution reads.

const SHIP_NAMES: Array[StringName] = [&"Lead", &"FlankTop", &"FlankBottom"]
## Index of each ship in SHIP_NAMES, ship_centres() and hull_rects().
const LEAD: int = 0
const FLANK_TOP: int = 1
const FLANK_BOTTOM: int = 2
## The ship count the triangle layout supports.
const LAYOUT_SHIPS: int = 3

var ship_width: float = 0.0
var ship_height: float = 0.0
var lead_gap: float = 0.0
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
var _rects: Array[Rect2] = []


## Stores params before add_child; no keys yet (the layout and HP are tuning).
func setup(_params: Dictionary) -> void:
	pass


func _ready() -> void:
	ship_width = maxf(Config.num("convoy.ship_width_px"), 0.0)
	ship_height = maxf(Config.num("convoy.ship_height_px"), 0.0)
	lead_gap = maxf(Config.num("convoy.lead_offset_px"), 0.0)
	speed_px_s = maxf(Config.num("convoy.speed_px_s"), 0.0)
	band_min = Config.num("convoy.band_y.min")
	band_max = Config.num("convoy.band_y.max")
	var ships: int = Config.int_("convoy.ships")
	if ships != LAYOUT_SHIPS:
		Log.warn("data", "convoy.ships is %d but the triangle layout has %d ships; using %d" % [ships, LAYOUT_SHIPS, LAYOUT_SHIPS])
	add_to_group(Groups.CONVOY)
	for ship_name: StringName in SHIP_NAMES:
		var ship: ConvoyShip = get_node(NodePath(ship_name)) as ConvoyShip
		ship.convoy = self
		_ships.append(ship)
		_rects.append(Rect2())
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


## One movement tick: advance the span by speed_px_s * delta and re-place the ships.
func step(delta: float) -> void:
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


## +1 heading right, -1 heading left.
func direction() -> int:
	return _dir


## The group width: 2 * ship_width + lead_gap.
func span() -> float:
	return group_span(ship_width, lead_gap)


## The ships in SHIP_NAMES order (Lead, FlankTop, FlankBottom).
func ships() -> Array[ConvoyShip]:
	return _ships


## The cached global hitbox rects, in SHIP_NAMES order (refreshed each tick).
func hull_rects() -> Array[Rect2]:
	return _rects


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


func _on_events_level_cleared(_level_id: int) -> void:
	_ended = true


func _on_events_level_failed(_reason: StringName) -> void:
	_ended = true


# --- Layout -----------------------------------------------------------------------

## Positions every ship for the current left_x / dir, sets its facing and
## refreshes the cached hull rects (no allocation).
func _place_ships() -> void:
	for i: int in _ships.size():
		var ship: ConvoyShip = _ships[i]
		ship.global_position = ship_centre(i, _left_x, _dir, ship_width, ship_height, lead_gap, band_min, band_max)
		ship.facing = _dir
		_rects[i] = ship.hull_rect()


## The group width for hulls `w` wide with a `gap` between lead and flankers.
static func group_span(w: float, gap: float) -> float:
	return 2.0 * w + gap


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


## The centre of ship `index` (LEAD, FLANK_TOP, FLANK_BOTTOM) for a group whose
## left edge is `left` heading `dir` (see the class doc for the layout).
static func ship_centre(index: int, left: float, dir: int, w: float, h: float, gap: float, band_lo: float, band_hi: float) -> Vector2:
	var front_x: float = left + w + gap + w / 2.0
	var rear_x: float = left + w / 2.0
	var lead_x: float = front_x if dir >= 0 else rear_x
	var flank_x: float = rear_x if dir >= 0 else front_x
	if index == LEAD:
		return Vector2(lead_x, (band_lo + band_hi) / 2.0)
	if index == FLANK_TOP:
		return Vector2(flank_x, band_lo + h / 2.0)
	return Vector2(flank_x, band_hi - h / 2.0)


## Every ship centre, in SHIP_NAMES order (allocates; the tick uses ship_centre).
static func ship_centres(left: float, dir: int, w: float, h: float, gap: float, band_lo: float, band_hi: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i: int in LAYOUT_SHIPS:
		out.append(ship_centre(i, left, dir, w, h, gap, band_lo, band_hi))
	return out
