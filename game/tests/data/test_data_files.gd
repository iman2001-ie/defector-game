extends GutTest
## Data files: every level_*.json in res://data/levels/ passes LevelValidator;
## every telegraph in tuning.enemies / tuning.boss is >= the 0.3 s minimum;
## every enemy bullet speed is <= the readable maximum; Wasp, Lancer and
## Bastion waves fit their formation rows inside each type's zone (a Bastion's
## is its drift box); Needle, Bastion and Hunter Wasp tuning is sane; every
## Needle wave brings cover; every flag-gated enemy type has its flag; the
## energy and drop tuning matches the GDD; the Shield cost and duration match
## the GDD and its UX tuning exists.

const LEVELS_DIR: String = "res://data/levels/"


func _level_files() -> Array[String]:
	var out: Array[String] = []
	for file: String in DirAccess.get_files_at(LEVELS_DIR):
		if file.begins_with("level_") and file.ends_with(".json"):
			out.append(LEVELS_DIR + file)
	return out


func test_level_files_exist() -> void:
	assert_true(_level_files().has(LEVELS_DIR + "level_dev.json"), "level_dev.json present")


func test_every_level_file_is_valid() -> void:
	var known: Array[StringName] = EntityRegistry.enemy_types()
	var spacing: Vector2 = Vector2(Config.num("waves.formation.spacing_px.x"), Config.num("waves.formation.spacing_px.y"))
	var max_columns: int = Formation.max_columns(spacing, Playfield.SIZE.x)
	for path: String in _level_files():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_true(parsed is Dictionary, "%s parses to an object" % path)
		if not (parsed is Dictionary):
			continue
		var problems: Array[String] = LevelValidator.validate(parsed as Dictionary, path, known, Config.flags, EntityRegistry.enemy_flags(), max_columns)
		assert_eq(problems, [] as Array[String], "%s has no problems" % path)


# --- Telegraph rule (Pillar 1) ------------------------------------------------

const TELEGRAPH_KEYS: Array[String] = ["telegraph_s", "lock_s", "charge_s"]
const TELEGRAPH_SUFFIXES: Array[String] = ["_telegraph_s", "_charge_s"]


static func _is_telegraph_key(key: String) -> bool:
	if TELEGRAPH_KEYS.has(key):
		return true
	for suffix: String in TELEGRAPH_SUFFIXES:
		if key.ends_with(suffix):
			return true
	return false


## Collects path -> value for every telegraph-like key under `node`.
static func _collect_telegraphs(node: Variant, path: String, out: Dictionary) -> void:
	if not (node is Dictionary):
		return
	var dict: Dictionary = node
	for key: Variant in dict:
		var child_path: String = "%s.%s" % [path, str(key)]
		if _is_telegraph_key(str(key)):
			out[child_path] = dict[key]
		_collect_telegraphs(dict[key], child_path, out)


func test_every_telegraph_meets_the_minimum() -> void:
	var minimum: float = Config.num("weapons.enemy_bullet.min_telegraph_s")
	assert_eq(minimum, 0.3, "GDD minimum telegraph")
	var found: Dictionary = {}
	for section: String in ["enemies", "boss"]:
		_collect_telegraphs(Config.tuning.get(section), section, found)
	for expected: String in [
		"enemies.wasp.telegraph_s", "enemies.lancer.telegraph_s", "enemies.needle.lock_s",
		"enemies.bastion.telegraph_s", "boss.turrets.telegraph_s", "boss.core.charge_s",
		"boss.desperate.radial_charge_s", "boss.desperate.aimed_telegraph_s",
	]:
		assert_true(found.has(expected), "walk finds %s" % expected)
	for path: String in found:
		var value: Variant = found[path]
		assert_true(value is float or value is int, "%s is a number" % path)
		if value is float or value is int:
			assert_gte(float(value), minimum, "%s >= %.1f s" % [path, minimum])


# --- Bullet speed rule (Pillar 1) ---------------------------------------------

## Collects path -> value for every `bullet_speed_px_s` under tuning.enemies.
## enemies.needle.bolt_speed_px_s (1600) is deliberately not collected: the
## Needle bolt is the GDD's one telegraphed exception to the 450 px/s rule.
static func _collect_enemy_bullet_speeds(node: Variant, path: String, out: Dictionary) -> void:
	if not (node is Dictionary):
		return
	var dict: Dictionary = node
	for key: Variant in dict:
		var child_path: String = "%s.%s" % [path, str(key)]
		if str(key) == "bullet_speed_px_s":
			out[child_path] = dict[key]
		_collect_enemy_bullet_speeds(dict[key], child_path, out)


## Collects path -> value for every key ending `_speed_px_s` under tuning.boss.
static func _collect_speeds(node: Variant, path: String, out: Dictionary) -> void:
	if not (node is Dictionary):
		return
	var dict: Dictionary = node
	for key: Variant in dict:
		var child_path: String = "%s.%s" % [path, str(key)]
		if str(key).ends_with("_speed_px_s"):
			out[child_path] = dict[key]
		_collect_speeds(dict[key], child_path, out)


func test_every_enemy_bullet_is_at_most_the_max_speed() -> void:
	var maximum: float = Config.num("weapons.enemy_bullet.max_speed_px_s")
	assert_eq(maximum, 450.0, "GDD maximum enemy bullet speed")
	var found: Dictionary = {}
	_collect_enemy_bullet_speeds(Config.tuning.get("enemies"), "enemies", found)
	_collect_speeds(Config.tuning.get("boss"), "boss", found)
	for expected: String in ["enemies.lancer.bullet_speed_px_s", "enemies.bastion.bullet_speed_px_s"]:
		assert_true(found.has(expected), "walk finds %s" % expected)
	var boss_found: int = 0
	for path: String in found:
		if path.begins_with("boss."):
			boss_found += 1
	assert_gt(boss_found, 0, "walk finds boss speeds")
	for path: String in found:
		var value: Variant = found[path]
		assert_true(value is float or value is int, "%s is a number" % path)
		if value is float or value is int:
			assert_lte(float(value), maximum, "%s <= %.0f px/s" % [path, maximum])


# --- Formation zones ----------------------------------------------------------

func _entry_count(entry: Dictionary) -> int:
	var raw: Variant = entry.get("count", 0)
	return int(raw) if (raw is float or raw is int) else 0


## Enemy types whose formation slots must sit in their own zone.
const ZONED_TYPES: Array[StringName] = [&"wasp", &"lancer", &"bastion"]


## The slot y range [min, max] a zoned type accepts without clamping: the Wasp
## and Lancer top zone (zone_height_ratio of the height, fully on screen), the
## Bastion's drift box (bastion.gd: band_y shrunk by half the sprite, the band
## centre when the band is shorter than the sprite).
func _zone_y(type_id: StringName, half: float) -> Vector2:
	if type_id == &"bastion":
		var band_min: float = Config.num("enemies.bastion.band_y.min")
		var band_max: float = Config.num("enemies.bastion.band_y.max")
		if band_min + half > band_max - half:
			var centre: float = (band_min + band_max) / 2.0
			return Vector2(centre, centre)
		return Vector2(band_min + half, band_max - half)
	return Vector2(half, Config.num("enemies.%s.zone_height_ratio" % type_id) * Playfield.SIZE.y)


## Mirrors WaveDirector._spawn_entry: spawns then groups, in order, on a running
## first row; non-objects, unknown types and empty entries take no rows, and
## nor do EntityRegistry.ROWLESS_TYPES (the Hunter Wasp; the Needle takes a row).
## Every Wasp, Lancer and Bastion slot must be inside its type's zone (see _zone_y)
## and fully on screen horizontally.
func test_zoned_formations_fit_their_top_zone() -> void:
	var spacing: Vector2 = Vector2(Config.num("waves.formation.spacing_px.x"), Config.num("waves.formation.spacing_px.y"))
	var top_y: float = Config.num("waves.formation.top_y")
	var zone_y: Dictionary = {}
	var half: Dictionary = {}
	var checked: Dictionary = {}
	for type_id: StringName in ZONED_TYPES:
		var probe: Enemy = (EntityRegistry.ENEMIES[type_id] as PackedScene).instantiate() as Enemy
		half[type_id] = probe.sprite_px / 2.0
		probe.free()
		zone_y[type_id] = _zone_y(type_id, half[type_id])
		checked[type_id] = 0
	for path: String in _level_files():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary) or not ((parsed as Dictionary).get("waves") is Array):
			continue
		var waves: Array = (parsed as Dictionary)["waves"]
		for i: int in waves.size():
			if not (waves[i] is Dictionary):
				continue
			var wave: Dictionary = waves[i]
			var entries: Array = []
			if wave.get("spawns") is Array:
				entries.append_array(wave["spawns"] as Array)
			if wave.get("groups") is Dictionary:
				for group: Variant in (wave["groups"] as Dictionary).values():
					if group is Array:
						entries.append_array(group as Array)
			var first_row: int = 0
			for raw: Variant in entries:
				if not (raw is Dictionary):
					continue
				var entry: Dictionary = raw
				var type_id: StringName = StringName(str(entry.get("type", "")))
				var count: int = _entry_count(entry)
				if not EntityRegistry.ENEMIES.has(type_id) or count <= 0:
					continue
				var formation: String = str(entry["formation"]) if entry.get("formation") is String else ""
				if ZONED_TYPES.has(type_id):
					checked[type_id] = int(checked[type_id]) + 1
					var range_y: Vector2 = zone_y[type_id]
					var h: float = half[type_id]
					for slot: Vector2 in Formation.slots(formation, count, first_row, spacing, top_y, Playfield.SIZE.x):
						var where: String = "%s waves[%d] %s slot %s" % [path, i, type_id, slot]
						assert_between(slot.y, range_y.x, range_y.y, where + " inside its zone")
						assert_between(slot.x, h, Playfield.SIZE.x - h, where + " fully on screen")
				if not EntityRegistry.ROWLESS_TYPES.has(type_id):
					first_row += Formation.rows_used(formation, count, spacing, Playfield.SIZE.x)
	for type_id: StringName in ZONED_TYPES:
		assert_gt(int(checked[type_id]), 0, "at least one %s entry checked" % type_id)


func test_wasp_tuning_ranges() -> void:
	assert_gt(Config.num("enemies.wasp.entry_speed_px_s"), 0.0, "entry_speed_px_s > 0")
	assert_gt(Config.num("enemies.wasp.dive_speed_px_s"), 0.0, "dive_speed_px_s > 0")
	var dive_min: float = Config.num("enemies.wasp.dive_interval_s.min")
	var dive_max: float = Config.num("enemies.wasp.dive_interval_s.max")
	assert_gt(dive_min, 0.0, "dive_interval_s.min > 0")
	assert_lte(dive_min, dive_max, "dive_interval_s.min <= max")
	var zone: float = Config.num("enemies.wasp.zone_height_ratio")
	assert_gt(zone, 0.0, "zone_height_ratio > 0")
	assert_lte(zone, 1.0, "zone_height_ratio <= 1")
	assert_gt(Config.num("enemies.wasp.wing_flash_hz"), 0.0, "wing_flash_hz > 0")
	assert_gt(Config.num("enemies.wasp.wing_flash_energy"), 1.0, "wing_flash_energy > 1")


func test_lancer_tuning_ranges() -> void:
	assert_gt(Config.num("enemies.lancer.strafe_speed_px_s"), 0.0, "strafe_speed_px_s > 0")
	assert_gt(Config.num("enemies.lancer.bullet_speed_px_s"), 0.0, "bullet_speed_px_s > 0")
	var fire: float = Config.num("enemies.lancer.fire_interval_s")
	assert_gt(fire, 0.0, "fire_interval_s > 0")
	# DW-40: fire_interval_s is the full shot period and includes the telegraph.
	assert_lte(Config.num("enemies.lancer.telegraph_s"), fire, "telegraph_s <= fire_interval_s")
	assert_gt(Config.num("enemies.lancer.muzzle_glow_energy"), 1.0, "muzzle_glow_energy > 1")
	var zone: float = Config.num("enemies.lancer.zone_height_ratio")
	assert_gt(zone, 0.0, "zone_height_ratio > 0")
	assert_lte(zone, 1.0, "zone_height_ratio <= 1")


## UX DESIGN.md: the enemy zone ends at y 432. Needle anchors must be fully on
## screen (y >= the needle half-height) and at or above this bottom edge.
const ENEMY_ZONE_BOTTOM_Y: float = 432.0


func test_needle_tuning_ranges() -> void:
	assert_gt(Config.num("enemies.needle.bolt_speed_px_s"), 0.0, "bolt_speed_px_s > 0")
	assert_gt(Config.num("enemies.needle.reposition_speed_px_s"), 0.0, "reposition_speed_px_s > 0")
	var fire: float = Config.num("enemies.needle.fire_interval_s")
	var track: float = Config.num("enemies.needle.track_s")
	var lock: float = Config.num("enemies.needle.lock_s")
	assert_gt(fire, 0.0, "fire_interval_s > 0")
	assert_gt(track, 0.0, "track_s > 0")
	assert_lte(track + lock, fire, "track_s + lock_s <= fire_interval_s")
	assert_gte(Config.num("enemies.needle.reposition_interval_s"), fire, "reposition_interval_s >= fire_interval_s")
	var probe: Enemy = (EntityRegistry.ENEMIES[&"needle"] as PackedScene).instantiate() as Enemy
	var half: float = probe.sprite_px / 2.0
	probe.free()
	assert_between(Config.num("enemies.needle.anchor_y_px"), half, ENEMY_ZONE_BOTTOM_Y,
		"anchor_y_px fully on screen and inside the enemy zone")
	assert_gte(Config.num("enemies.needle.reposition_min_distance_px"), 0.0, "reposition_min_distance_px >= 0")


## GDD Bastion: drifts within band_y with its whole hull (probe sprite_px)
## inside it, and the band sits inside the enemy zone.
func test_bastion_tuning_ranges() -> void:
	assert_gt(Config.num("enemies.bastion.drift_speed_px_s"), 0.0, "drift_speed_px_s > 0")
	assert_gt(Config.num("enemies.bastion.bullet_speed_px_s"), 0.0, "bullet_speed_px_s > 0")
	var fire: float = Config.num("enemies.bastion.fire_interval_s")
	assert_gt(fire, 0.0, "fire_interval_s > 0")
	# DW-40: fire_interval_s is the full volley period and includes the telegraph.
	assert_lte(Config.num("enemies.bastion.telegraph_s"), fire, "telegraph_s <= fire_interval_s")
	assert_gte(Config.int_("enemies.bastion.turrets"), 1, "turrets >= 1")
	assert_gte(Config.int_("enemies.bastion.spread_bullets"), 1, "spread_bullets >= 1")
	var spread: float = Config.num("enemies.bastion.spread_deg")
	assert_gte(spread, 0.0, "spread_deg >= 0")
	assert_lt(spread, 90.0, "spread_deg < 90")
	assert_gt(Config.num("enemies.bastion.turret_glow_energy"), 1.0, "turret_glow_energy > 1")
	var band_min: float = Config.num("enemies.bastion.band_y.min")
	var band_max: float = Config.num("enemies.bastion.band_y.max")
	assert_lt(band_min, band_max, "band_y.min < band_y.max")
	assert_gte(band_min, 0.0, "band_y.min >= 0")
	assert_lte(band_max, ENEMY_ZONE_BOTTOM_Y, "band_y.max inside the enemy zone")
	var probe: Enemy = (EntityRegistry.ENEMIES[&"bastion"] as PackedScene).instantiate() as Enemy
	var sprite: float = probe.sprite_px
	probe.free()
	assert_gte(band_max - band_min, sprite, "the hull fits inside band_y")


## GDD FR24: the Hunter Wasp chases at a positive speed with a sane turn cap.
func test_hunter_wasp_tuning_ranges() -> void:
	assert_gt(Config.num("enemies.hunter_wasp.chase_speed_px_s"), 0.0, "chase_speed_px_s > 0")
	var turn: float = Config.num("enemies.hunter_wasp.turn_rate_deg_s")
	assert_gt(turn, 0.0, "turn_rate_deg_s > 0")
	assert_lte(turn, 360.0, "turn_rate_deg_s <= 360")
	assert_gte(Config.int_("enemies.hunter_wasp.hp"), 1, "hp >= 1")


## Every flag-gated enemy type is registered and its flag is a bool in flags.json.
func test_every_gated_type_has_a_flag() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/flags.json"))
	assert_true(parsed is Dictionary, "flags.json parses to an object")
	if not (parsed is Dictionary):
		return
	var flags: Dictionary = parsed
	assert_gt(EntityRegistry.ENEMY_FLAGS.size(), 0, "at least one gated type")
	for type_id: StringName in EntityRegistry.ENEMY_FLAGS:
		var flag_name: String = EntityRegistry.ENEMY_FLAGS[type_id]
		assert_true(EntityRegistry.ENEMIES.has(type_id), "%s is a registered enemy" % type_id)
		assert_true(flags.get(flag_name) is bool, "flags.%s is a bool (gates %s)" % [flag_name, type_id])


## GDD (Arena and Level Design): every Needle wave has >= 2 medium or large asteroids.
func test_every_needle_wave_has_cover() -> void:
	var needle_waves: int = 0
	for path: String in _level_files():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary) or not ((parsed as Dictionary).get("waves") is Array):
			continue
		var waves: Array = (parsed as Dictionary)["waves"]
		for i: int in waves.size():
			if not (waves[i] is Dictionary):
				continue
			var wave: Dictionary = waves[i]
			var entries: Array = []
			if wave.get("spawns") is Array:
				entries.append_array(wave["spawns"] as Array)
			if wave.get("groups") is Dictionary:
				for group: Variant in (wave["groups"] as Dictionary).values():
					if group is Array:
						entries.append_array(group as Array)
			var has_needle: bool = false
			for raw: Variant in entries:
				if raw is Dictionary and str((raw as Dictionary).get("type", "")) == "needle" \
						and _entry_count(raw as Dictionary) > 0:
					has_needle = true
			if not has_needle:
				continue
			needle_waves += 1
			var cover: int = 0
			if wave.get("asteroids") is Array:
				for raw: Variant in wave["asteroids"] as Array:
					if raw is Dictionary and ["medium", "large"].has(str((raw as Dictionary).get("size", ""))):
						cover += _entry_count(raw as Dictionary)
			assert_gte(cover, 2, "%s waves[%d] has a Needle and >= 2 medium/large asteroids" % [path, i])
	assert_gt(needle_waves, 0, "at least one Needle wave checked")


## GDD Energy and drop table (FR13/FR14): the drop rows and the orb numbers.
func test_energy_and_drops_match_the_gdd() -> void:
	var expected: Dictionary = {
		"wasp": [0.15, 1], "hunter_wasp": [0.15, 1], "lancer": [0.25, 1], "maul": [0.25, 1],
		"needle": [0.30, 1], "bastion": [1.0, 2], "asteroid_small": [0.10, 1],
		"asteroid_medium": [0.30, 1], "asteroid_large": [0.60, 1], "flagship_turret": [1.0, 1],
	}
	for key: String in expected:
		var row: Array = expected[key]
		assert_almost_eq(Config.num("drops.%s.chance" % key), float(row[0]), 0.0001, "drops.%s.chance" % key)
		assert_eq(Config.int_("drops.%s.orbs" % key), int(row[1]), "drops.%s.orbs" % key)
	for type_id: StringName in EntityRegistry.ENEMIES:
		assert_true(expected.has(String(type_id)), "every enemy type has a drop row (%s)" % type_id)
	assert_eq(Config.int_("energy.max"), 100)
	assert_eq(Config.int_("energy.orb_value"), 10)
	assert_eq(Config.num("energy.orb_drift_px_s"), 120.0)
	assert_eq(Config.num("energy.orb_magnet_radius_px"), 160.0)
	assert_eq(Config.num("energy.orb_despawn_s"), 6.0)


## Story 3.3 feel tuning: positive orb numbers, a bar inside the HUD band, F4 > 0.
func test_energy_feel_tuning_ranges() -> void:
	assert_gt(Config.num("energy.orb_magnet_speed_px_s"), 0.0, "orb_magnet_speed_px_s > 0")
	assert_gt(Config.num("energy.orb_diameter_px"), 0.0, "orb_diameter_px > 0")
	assert_gte(Config.num("energy.orb_spread_px"), 0.0, "orb_spread_px >= 0")
	var width: float = Config.num("hud.energy_bar.width")
	assert_gt(width, 0.0, "energy_bar.width > 0")
	assert_gt(Config.num("hud.energy_bar.height"), 0.0, "energy_bar.height > 0")
	assert_lte(Config.num("hud.energy_bar.right_x"), Playfield.SIZE.x, "inside the screen")
	assert_gte(Config.num("hud.energy_bar.right_x") - width, 0.0, "inside the screen")
	assert_lte(Config.num("hud.energy_bar.y") + Config.num("hud.energy_bar.height"), 120.0, "inside the top HUD band")
	assert_gt(Config.num("hud.energy_bar.tick_px"), 0.0, "tick_px > 0")
	assert_gt(Config.int_("debug.energy_add"), 0, "debug.energy_add > 0")


## Story 3.4: GDD Shield (50 energy, 4.0 s) and the UX bubble / denied-flash keys.
func test_shield_matches_the_gdd_and_ux_keys_exist() -> void:
	assert_eq(Config.int_("abilities.shield.cost"), 50)
	assert_eq(Config.num("abilities.shield.duration_s"), 4.0)
	assert_eq(Config.num("player.shield_bubble.diameter_px"), 120.0)
	assert_gt(Config.num("player.shield_bubble.stroke_px"), 0.0, "stroke_px > 0")
	assert_almost_eq(Config.num("player.shield_bubble.alpha"), 0.4, 0.0001)
	assert_eq(Config.num("player.shield_bubble.blink_hz"), 4.0)
	assert_eq(Config.num("player.shield_bubble.blink_last_s"), 0.75)
	assert_lt(Config.num("player.shield_bubble.blink_last_s"), Config.num("abilities.shield.duration_s"),
		"the blink window fits inside the shield")
	assert_almost_eq(Config.num("hud.energy_bar.denied_flash_s"), 0.3, 0.0001)
	assert_eq(Config.int_("hud.energy_bar.denied_flashes"), 2)


## Story 3.5: GDD Barrage (100 energy, 12 missiles over 2.0 s, 6 damage) and
## positive micro-missile feel keys.
func test_barrage_matches_the_gdd_and_feel_keys_are_positive() -> void:
	assert_eq(Config.int_("abilities.barrage.cost"), 100)
	assert_eq(Config.int_("abilities.barrage.missiles"), 12)
	assert_eq(Config.num("abilities.barrage.duration_s"), 2.0)
	assert_eq(Config.int_("abilities.barrage.damage"), 6)
	assert_gt(Config.num("abilities.barrage.speed_px_s"), 0.0, "speed_px_s > 0")
	assert_gt(Config.num("abilities.barrage.turn_rate_deg_s"), 0.0, "turn_rate_deg_s > 0")
	assert_gt(Config.num("abilities.barrage.lifetime_s"), 0.0, "lifetime_s > 0")
