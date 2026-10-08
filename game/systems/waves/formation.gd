class_name Formation
extends RefCounted
## Formation slot math for wave spawn entries. Pure logic, no nodes.
##
## `grid_<C>x<R>` fills rows of C slots, row-major, each row centred on
## width / 2. A count above C x R keeps adding rows of C. An empty or
## unparseable formation uses rows of mini(count, floori(width / spacing.x)).
## Rows are numbered from `first_row`, so the WaveDirector can stack entries.

const GRID_PREFIX: String = "grid_"


## True for `grid_<C>x<R>` with C and R positive integers.
static func is_valid(formation: String) -> bool:
	return _grid(formation) != Vector2i.ZERO


## Slot positions for `count` enemies, starting on row `first_row`.
static func slots(formation: String, count: int, first_row: int, spacing: Vector2, top_y: float, width: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if count <= 0:
		return out
	var columns: int = _columns(formation, count, spacing, width)
	var centre_x: float = width / 2.0
	for i: int in count:
		var row: int = floori(float(i) / float(columns))
		var col: int = i % columns
		var in_row: int = mini(columns, count - row * columns)
		var x: float = centre_x + (col - (in_row - 1) / 2.0) * spacing.x
		out.append(Vector2(x, top_y + (first_row + row) * spacing.y))
	return out


## How many rows `count` enemies take in this formation (0 for no enemies).
static func rows_used(formation: String, count: int, spacing: Vector2, width: float) -> int:
	if count <= 0:
		return 0
	return ceili(float(count) / float(_columns(formation, count, spacing, width)))


static func _columns(formation: String, count: int, spacing: Vector2, width: float) -> int:
	var grid: Vector2i = _grid(formation)
	if grid != Vector2i.ZERO:
		return grid.x
	var fit: int = floori(width / spacing.x) if spacing.x > 0.0 else count
	return maxi(mini(count, fit), 1)


## (columns, rows) of a valid grid formation, else Vector2i.ZERO.
static func _grid(formation: String) -> Vector2i:
	if not formation.begins_with(GRID_PREFIX):
		return Vector2i.ZERO
	var parts: PackedStringArray = formation.substr(GRID_PREFIX.length()).split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	var columns: int = parts[0].to_int()
	var rows: int = parts[1].to_int()
	if columns <= 0 or rows <= 0 or parts[0].begins_with("+") or parts[1].begins_with("+"):
		return Vector2i.ZERO
	return Vector2i(columns, rows)
