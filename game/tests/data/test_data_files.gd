extends GutTest
## Data files: every level_*.json in res://data/levels/ passes LevelValidator;
## every telegraph in tuning.enemies / tuning.boss is >= the 0.3 s minimum;
## every enemy bullet speed is <= the readable maximum; Wasp, Lancer and
## Bastion waves fit their formation rows inside each type's zone (a Bastion's
## is its drift box); Needle, Bastion and Hunter Wasp tuning is sane; every
## Needle wave brings cover; every flag-gated enemy type has its flag; the
## energy and drop tuning matches the GDD; the Shield cost and duration match
## the GDD and its UX tuning exists. Dialogue (Stories 5.1-5.2): every file
## validates, every combat sequence is one line of at most 50 characters, and
## every level has at most 2 interruptions (the cut-off line excluded). Story
## 5.3: every sequence id a level references (comms actions, intro and outro)
## exists, and the music fade-out tuning.

const LEVELS_DIR: String = "res://data/levels/"


func _level_files() -> Array[String]:
	var out: Array[String] = []
	for file: String in DirAccess.get_files_at(LEVELS_DIR):
		if file.begins_with("level_") and file.ends_with(".json"):
			out.append(LEVELS_DIR + file)
	return out


func test_level_files_exist() -> void:
	assert_true(_level_files().has(LEVELS_DIR + "level_dev.json"), "level_dev.json present")
	for i: int in [1, 2, 3]:
		assert_true(_level_files().has(LEVELS_DIR + "level_%d.json" % i), "level_%d.json present" % i)


## Story 4.2: every campaign level 1..progression.level_count has its file,
## with the matching id, so raising level_count without a new file fails here.
func test_every_campaign_level_has_a_file() -> void:
	var count: int = Config.int_("progression.level_count")
	assert_gt(count, 0, "progression.level_count")
	for i: int in range(1, count + 1):
		var data: Dictionary = Config.level(str(i))
		assert_false(data.is_empty(), "level_%d.json loads" % i)
		assert_eq(data.get("id"), float(i), "level_%d.json id" % i)


## The placeholder levels (Story 4.1, replaced in Epic 7, decision F12): GDD
## names, ids 1..3, the level_dev key set, and 1-2 Wasp-only waves.
const LEVEL_NAMES: Dictionary = {
	1: "Cargo Ambush",
	2: "The Blockade",
	3: "Siege of the Throne World",
}


func test_placeholder_levels_have_their_names_and_wasp_waves() -> void:
	var dev: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEVELS_DIR + "level_dev.json"))
	assert_true(dev is Dictionary, "level_dev.json parses")
	if not (dev is Dictionary):
		return
	var dev_keys: Array = (dev as Dictionary).keys()
	dev_keys.sort()
	for i: int in LEVEL_NAMES:
		var path: String = LEVELS_DIR + "level_%d.json" % i
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_true(parsed is Dictionary, "%s parses to an object" % path)
		if not (parsed is Dictionary):
			continue
		var data: Dictionary = parsed
		var keys: Array = data.keys()
		keys.sort()
		assert_eq(keys, dev_keys, "%s has the level_dev key set" % path)
		assert_eq(data.get("id"), float(i), "%s id" % path)
		assert_eq(data.get("name"), LEVEL_NAMES[i], "%s name" % path)
		assert_eq(data.get("convoy"), false, "%s has no convoy" % path)
		var waves: Array = data.get("waves", []) as Array
		assert_between(waves.size(), 1, 2, "%s has 1-2 waves" % path)
		for w: int in waves.size():
			var spawns: Array = (waves[w] as Dictionary).get("spawns", []) as Array
			assert_gt(spawns.size(), 0, "%s wave %d spawns something" % [path, w])
			for entry: Variant in spawns:
				assert_eq((entry as Dictionary).get("type"), "wasp", "%s wave %d is Wasp-only" % [path, w])
			assert_false((waves[w] as Dictionary).has("groups"), "%s wave %d has no groups" % [path, w])
		assert_false(Config.level("%d" % i).is_empty(), "Config.level('%d') loads" % i)


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


# --- Dialogue (Story 5.1) -----------------------------------------------------

const DIALOGUE_DIR: String = "res://data/dialogue/"


func _dialogue_files() -> Array[String]:
	var out: Array[String] = []
	for file: String in DirAccess.get_files_at(DIALOGUE_DIR):
		if file.ends_with(".json"):
			out.append(DIALOGUE_DIR + file)
	return out


func test_every_dialogue_file_is_valid() -> void:
	var files: Array[String] = _dialogue_files()
	assert_true(files.has(DIALOGUE_DIR + "dev.json"), "dev.json present")
	var max_chars: int = Config.int_("comms.story_line_max_chars")
	assert_eq(max_chars, 200, "comms.story_line_max_chars")
	var combat_max_chars: int = Config.int_("comms.combat_line_max_chars")
	assert_eq(combat_max_chars, 50, "comms.combat_line_max_chars")
	var seen: Dictionary = {}
	for path: String in files:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_true(parsed is Dictionary, "%s parses to an object" % path)
		if not (parsed is Dictionary):
			continue
		assert_eq(DialogueValidator.validate(parsed as Dictionary, path, max_chars, combat_max_chars), [] as Array[String], "%s has no problems" % path)
		var sequences: Variant = (parsed as Dictionary).get("sequences")
		if sequences is Dictionary:
			for id: Variant in sequences:
				assert_false(seen.has(id), "sequence id '%s' is unique (also in %s)" % [id, seen.get(id, "")])
				seen[id] = path


func test_dev_comms_check_is_a_story_with_both_panel_variants() -> void:
	assert_true(Config.dialogue_is_story(&"dev_comms_check"), "dev_comms_check loads and is story")
	var lines: Array = Config.sequence(&"dev_comms_check").get("lines", []) as Array
	assert_between(lines.size(), 3, 4, "3-4 lines")
	var speakers: Array[String] = []
	var longest: int = 0
	for line: Variant in lines:
		speakers.append(str((line as Dictionary).get("speaker")))
		longest = maxi(longest, str((line as Dictionary).get("text")).length())
	assert_true(speakers.has("vale"), "a no-portrait speaker")
	assert_true(speakers.has("tarek") or speakers.has("isolde"), "a portrait speaker")
	assert_between(longest, 180, 200, "one line near 200 characters for the wrap check")


func test_every_speaker_has_comms_tuning() -> void:
	var speakers: Dictionary = Config.section("comms.speakers")
	for speaker: StringName in DialogueValidator.SPEAKERS:
		var entry: Variant = speakers.get(String(speaker))
		assert_true(entry is Dictionary, "comms.speakers.%s" % speaker)
		if not (entry is Dictionary):
			continue
		var display_name: Variant = (entry as Dictionary).get("name")
		assert_true(display_name is String and not (display_name as String).is_empty(), "comms.speakers.%s.name" % speaker)
		assert_true((entry as Dictionary).get("portrait") is bool, "comms.speakers.%s.portrait is a bool" % speaker)
	assert_gt(Config.num("comms.chars_per_s"), 0.0, "comms.chars_per_s")


# --- Combat comms (Story 5.2) -------------------------------------------------

## The UX caps interruptions at 2 per level (the Tarek cut-off excluded).
const MAX_INTERRUPTIONS_PER_LEVEL: int = 2


## Every sequence in res://data/dialogue/ (id String -> Dictionary).
func _all_sequences() -> Dictionary:
	var out: Dictionary = {}
	for path: String in _dialogue_files():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and (parsed as Dictionary).get("sequences") is Dictionary:
			out.merge((parsed as Dictionary).get("sequences") as Dictionary)
	return out


## Counts the `comms` actions (waves[].triggers[].actions[]) of `level` whose
## sequence in `sequences` is an interruption (DialogueValidator.is_interruption).
static func _interruptions(level: Dictionary, sequences: Dictionary) -> int:
	var n: int = 0
	var waves: Variant = level.get("waves")
	if not (waves is Array):
		return 0
	for wave: Variant in waves as Array:
		var triggers: Variant = (wave as Dictionary).get("triggers") if wave is Dictionary else null
		if not (triggers is Array):
			continue
		for trigger: Variant in triggers as Array:
			var actions: Variant = (trigger as Dictionary).get("actions") if trigger is Dictionary else null
			if not (actions is Array):
				continue
			for action: Variant in actions as Array:
				if not (action is Dictionary and (action as Dictionary).has("comms")):
					continue
				var seq: Variant = sequences.get(str((action as Dictionary).get("comms")))
				if seq is Dictionary and DialogueValidator.is_interruption(seq as Dictionary):
					n += 1
	return n


func test_every_combat_sequence_is_one_short_line() -> void:
	var limit: int = Config.int_("comms.combat_line_max_chars")
	assert_eq(limit, 50)
	var sequences: Dictionary = _all_sequences()
	var combat: int = 0
	for id: Variant in sequences:
		var seq: Dictionary = sequences[id] as Dictionary
		if seq.get("mode") != "combat":
			continue
		combat += 1
		var lines: Array = seq.get("lines", []) as Array
		assert_eq(lines.size(), 1, "combat '%s' has exactly 1 line" % id)
		for line: Variant in lines:
			var text: String = str((line as Dictionary).get("text", ""))
			assert_lte(text.length(), limit, "combat '%s' line has %d characters" % [id, text.length()])
	assert_gte(combat, 2, "the dev combat sequences exist")


func test_dev_combat_sequences() -> void:
	for id: StringName in [&"dev_combat_check", &"dev_combat_vale"]:
		assert_true(Config.has_sequence(id), "%s loads" % id)
		assert_false(Config.dialogue_is_story(id), "%s is combat" % id)
	var check: Array = Config.sequence(&"dev_combat_check").get("lines", []) as Array
	var vale: Array = Config.sequence(&"dev_combat_vale").get("lines", []) as Array
	assert_eq(str((check[0] as Dictionary).get("speaker")), "isolde", "a portrait speaker")
	assert_eq(str((vale[0] as Dictionary).get("speaker")), "vale", "the no-portrait variant")


func test_every_level_has_at_most_two_interruptions() -> void:
	var sequences: Dictionary = _all_sequences()
	for path: String in _level_files():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			continue
		var n: int = _interruptions(parsed as Dictionary, sequences)
		assert_lte(n, MAX_INTERRUPTIONS_PER_LEVEL, "%s has %d interruptions" % [path, n])


func test_interruption_counter_self_check() -> void:
	var line: Dictionary = {"speaker": "isolde", "text": "Still alive?"}
	var sequences: Dictionary = {
		"c1": {"mode": "combat", "lines": [line]},
		"c2": {"mode": "combat", "lines": [line]},
		"c3": {"mode": "combat", "lines": [line]},
		"cut": {"mode": "combat", "lines": [{"speaker": "tarek", "text": "General, get behind me, I've got you cov-", "cut_off_at": 39}]},
		"story": {"mode": "story", "lines": [line]},
	}
	var with_cut: Dictionary = {"waves": [
		{"triggers": [{"when": "wave_start", "actions": [{"comms": "c1"}, {"comms": "story"}]}]},
		{"triggers": [{"when": "progress", "actions": [{"spawn_group": "x"}, {"comms": "cut"}]}, {"when": "wave_clear", "actions": [{"comms": "c2"}]}]},
	]}
	assert_eq(_interruptions(with_cut, sequences), 2, "3 combat actions, the cut-off excluded")
	var three: Dictionary = {"waves": [
		{"triggers": [{"when": "wave_start", "actions": [{"comms": "c1"}, {"comms": "c2"}]}]},
		{"triggers": [{"when": "wave_start", "actions": [{"comms": "c3"}]}]},
	]}
	assert_eq(_interruptions(three, sequences), 3, "3 non-cut-off combat actions count 3 (the data test fails on > 2)")
	assert_eq(_interruptions({}, sequences), 0, "no waves")


# --- Wave-triggered dialogue and music (Story 5.3) ------------------------------

## Every sequence id `level` references: each `comms` action value
## (waves[].triggers[].actions[]) and a non-null intro_sequence / outro_sequence,
## as [path, id] pairs.
static func _referenced_sequences(level: Dictionary) -> Array[Array]:
	var out: Array[Array] = []
	for key: String in ["intro_sequence", "outro_sequence"]:
		if level.get(key) != null:
			out.append([key, str(level.get(key))])
	var waves: Variant = level.get("waves")
	if not (waves is Array):
		return out
	for w: int in (waves as Array).size():
		var wave: Variant = (waves as Array)[w]
		var triggers: Variant = (wave as Dictionary).get("triggers") if wave is Dictionary else null
		if not (triggers is Array):
			continue
		for t: int in (triggers as Array).size():
			var trigger: Variant = (triggers as Array)[t]
			var actions: Variant = (trigger as Dictionary).get("actions") if trigger is Dictionary else null
			if not (actions is Array):
				continue
			for a: int in (actions as Array).size():
				var action: Variant = (actions as Array)[a]
				if action is Dictionary and (action as Dictionary).has("comms"):
					out.append(["waves[%d].triggers[%d].actions[%d].comms" % [w, t, a], str((action as Dictionary)["comms"])])
	return out


func test_every_referenced_sequence_exists() -> void:
	assert_gt(_level_files().size(), 0, "level files to check")
	for path: String in _level_files():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			continue
		for ref: Array in _referenced_sequences(parsed as Dictionary):
			assert_true(Config.has_sequence(StringName(str(ref[1]))), "%s %s: sequence '%s' exists" % [path, ref[0], ref[1]])


func test_referenced_sequence_collector_self_check() -> void:
	var level: Dictionary = {
		"intro_sequence": "brief",
		"outro_sequence": null,
		"waves": [
			{"triggers": [{"when": "wave_start", "actions": [{"wait": 1.0}, {"comms": "w1"}]}]},
			{"spawns": []},
			{"triggers": [{"when": "progress", "at": 0.5, "actions": [{"music": "boss"}, {"comms": "w3"}]}]},
		],
	}
	var refs: Array[Array] = _referenced_sequences(level)
	assert_eq(refs, [
		["intro_sequence", "brief"],
		["waves[0].triggers[0].actions[1].comms", "w1"],
		["waves[2].triggers[0].actions[1].comms", "w3"],
	] as Array[Array], "finds the intro and both comms actions, skips the null outro")
	level["outro_sequence"] = "debrief"
	assert_eq(_referenced_sequences(level).size(), 4, "finds the outro too")
	assert_eq(_referenced_sequences({}).size(), 0, "nothing referenced")


# --- Cut-off SFX (Story 5.4) ------------------------------------------------------

## Every `after.sfx` value in `sequences` (id -> sequence), as
## ["<id>.lines[<i>].after.sfx", value] pairs.
static func _after_sfx(sequences: Dictionary) -> Array[Array]:
	var out: Array[Array] = []
	for id: Variant in sequences:
		var seq: Variant = sequences[id]
		var lines: Variant = (seq as Dictionary).get("lines") if seq is Dictionary else null
		if not (lines is Array):
			continue
		for i: int in (lines as Array).size():
			var line: Variant = (lines as Array)[i]
			var after: Variant = (line as Dictionary).get(DialogueValidator.AFTER_KEY) if line is Dictionary else null
			if after is Dictionary and (after as Dictionary).has(DialogueValidator.AFTER_SFX):
				out.append(["%s.lines[%d].after.sfx" % [id, i], str((after as Dictionary)[DialogueValidator.AFTER_SFX])])
	return out


func test_every_after_sfx_is_registered() -> void:
	var refs: Array[Array] = _after_sfx(_all_sequences())
	assert_gt(refs.size(), 0, "dialogue has an after.sfx to check")
	for ref: Array in refs:
		assert_true(Audio.SFX.has(StringName(str(ref[1]))), "%s: sfx '%s' is in Audio.SFX" % [ref[0], ref[1]])


func test_after_sfx_collector_self_check() -> void:
	var sequences: Dictionary = {
		"plain": {"mode": "combat", "lines": [{"speaker": "isolde", "text": "Hi."}]},
		"cut": {"mode": "combat", "lines": [{"speaker": "tarek", "text": "General, cov-", "cut_off_at": 9, "after": {"shake": "large", "sfx": "comms_statc"}}]},
		"no_sfx": {"mode": "combat", "lines": [{"speaker": "tarek", "text": "General, cov-", "cut_off_at": 9, "after": {"music": "stop"}}]},
	}
	var refs: Array[Array] = _after_sfx(sequences)
	assert_eq(refs, [["cut.lines[0].after.sfx", "comms_statc"]] as Array[Array], "finds the one after.sfx")
	assert_false(Audio.SFX.has(StringName(str(refs[0][1]))), "a typo is not registered (the data test would fail)")
	assert_eq(_after_sfx({}).size(), 0, "nothing to find")


func test_music_fade_out_tuning() -> void:
	assert_almost_eq(Config.num("audio.music_fade_out_s"), 0.5, 0.0001, "audio.music_fade_out_s")


func test_combat_comms_tuning_is_positive() -> void:
	for key: String in ["comms.combat_line_max_chars", "comms.box_slide_in_s", "comms.box_fade_out_s",
			"comms.combat_line_min_s", "comms.combat_line_extra_s", "comms.combat_queue_max"]:
		assert_gt(Config.num(key), 0.0, key)
	for key: String in ["x", "y"]:
		assert_gte(Config.num("ui.comms_box.%s" % key), 0.0, "ui.comms_box.%s" % key)
	for key: String in ["w", "h", "edge_px", "padding_px", "portrait_px", "portrait_gap_px", "name_h_px", "text_line_h_px", "text_lines"]:
		assert_gt(Config.num("ui.comms_box.%s" % key), 0.0, "ui.comms_box.%s" % key)
