extends GutTest
## Formation: grid_<C>x<R> slot math, row stacking and the fallback for an
## empty or unparseable formation.

const SPACING: Vector2 = Vector2(160, 120)
const TOP_Y: float = 160.0
const WIDTH: float = 1920.0


func test_grid_4x2_matches_the_sandbox_slots() -> void:
	var slots: Array[Vector2] = Formation.slots("grid_4x2", 8, 0, SPACING, TOP_Y, WIDTH)
	var expected: Array[Vector2] = []
	for y: float in [160.0, 280.0]:
		for x: float in [720.0, 880.0, 1040.0, 1200.0]:
			expected.append(Vector2(x, y))
	assert_eq(slots, expected, "row-major, centred on x 960")


func test_first_row_offsets_every_slot() -> void:
	var slots: Array[Vector2] = Formation.slots("grid_4x1", 4, 2, SPACING, TOP_Y, WIDTH)
	assert_eq(slots.size(), 4)
	for slot: Vector2 in slots:
		assert_eq(slot.y, TOP_Y + 2 * SPACING.y, "starts on row 2")


func test_count_above_capacity_keeps_adding_rows() -> void:
	var slots: Array[Vector2] = Formation.slots("grid_3x1", 7, 0, SPACING, TOP_Y, WIDTH)
	assert_eq(slots.size(), 7, "every enemy gets a slot")
	assert_eq(slots[6].y, TOP_Y + 2 * SPACING.y, "third row of 3")
	assert_eq(Formation.rows_used("grid_3x1", 7, SPACING, WIDTH), 3)


func test_partial_last_row_is_centred() -> void:
	var slots: Array[Vector2] = Formation.slots("grid_4x2", 5, 0, SPACING, TOP_Y, WIDTH)
	assert_eq(slots[4], Vector2(960, TOP_Y + SPACING.y), "a lone slot sits on the centre line")


func test_rows_used() -> void:
	assert_eq(Formation.rows_used("grid_4x2", 8, SPACING, WIDTH), 2)
	assert_eq(Formation.rows_used("grid_4x2", 4, SPACING, WIDTH), 1)
	assert_eq(Formation.rows_used("grid_5x2", 10, SPACING, WIDTH), 2)
	assert_eq(Formation.rows_used("grid_4x2", 0, SPACING, WIDTH), 0, "no enemies, no rows")


func test_empty_formation_uses_one_row_up_to_the_width() -> void:
	var slots: Array[Vector2] = Formation.slots("", 5, 0, SPACING, TOP_Y, WIDTH)
	assert_eq(slots.size(), 5)
	for slot: Vector2 in slots:
		assert_eq(slot.y, TOP_Y, "one row")
	assert_eq(slots[2].x, 960.0, "centred")


func test_unparseable_formation_wraps_at_the_playfield_width() -> void:
	var per_row: int = floori(WIDTH / SPACING.x)
	var slots: Array[Vector2] = Formation.slots("v_shape", per_row + 1, 0, SPACING, TOP_Y, WIDTH)
	assert_eq(slots.size(), per_row + 1)
	assert_eq(slots[per_row].y, TOP_Y + SPACING.y, "wraps to a second row")
	assert_eq(Formation.rows_used("v_shape", per_row + 1, SPACING, WIDTH), 2)
	for slot: Vector2 in slots:
		assert_between(slot.x, 0.0, WIDTH, "on screen")


func test_zero_count_has_no_slots() -> void:
	assert_eq(Formation.slots("grid_4x2", 0, 0, SPACING, TOP_Y, WIDTH).size(), 0)


func test_is_valid() -> void:
	for good: String in ["grid_4x2", "grid_1x1", "grid_10x4"]:
		assert_true(Formation.is_valid(good), good)
	for bad: String in ["", "grid_", "grid_4", "grid_0x2", "grid_4x0", "grid_ax2", "grid_4x2x1", "line_4x2", "grid_-1x2", "grid_+4x2", "grid_4x+2"]:
		assert_false(Formation.is_valid(bad), bad)


func test_max_columns_is_what_fits_the_width() -> void:
	assert_eq(Formation.max_columns(SPACING, WIDTH), 12, "1920 / 160")
	assert_eq(Formation.max_columns(Vector2(0, 120), WIDTH), 0, "no spacing: unbounded")
	assert_eq(Formation.max_columns(Vector2(WIDTH * 2.0, 120), WIDTH), 1, "spacing wider than the width: one column")


func test_wide_grid_wraps_to_the_width() -> void:
	var cap: int = Formation.max_columns(SPACING, WIDTH)
	var slots: Array[Vector2] = Formation.slots("grid_13x1", 13, 0, SPACING, TOP_Y, WIDTH)
	assert_eq(slots.size(), 13)
	assert_eq(Formation.rows_used("grid_13x1", 13, SPACING, WIDTH), 2, "rows of %d" % cap)
	assert_eq(slots[cap - 1].y, TOP_Y, "first row holds %d" % cap)
	assert_eq(slots[cap].y, TOP_Y + SPACING.y, "the 13th wraps")
	for slot: Vector2 in slots:
		assert_between(slot.x, SPACING.x / 2.0, WIDTH - SPACING.x / 2.0, "on screen: %s" % slot)
