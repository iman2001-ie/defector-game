extends GutTest
## Data files: every level_*.json in res://data/levels/ passes LevelValidator;
## every telegraph in tuning.enemies / tuning.boss is >= the 0.3 s minimum;
## Wasp waves fit their formation rows inside the top zone.

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
	for path: String in _level_files():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_true(parsed is Dictionary, "%s parses to an object" % path)
		if not (parsed is Dictionary):
			continue
		var problems: Array[String] = LevelValidator.validate(parsed as Dictionary, path, known)
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


# --- Wasp formation zone ------------------------------------------------------

func _entry_count(entry: Dictionary) -> int:
	var raw: Variant = entry.get("count", 0)
	return int(raw) if (raw is float or raw is int) else 0


## Mirrors WaveDirector._spawn_entry: spawns then groups, in order, on a running
## first row; non-objects, unknown types and empty entries take no rows. Every
## Wasp slot must be inside the top zone and fully on screen horizontally.
func test_wasp_formations_fit_the_top_zone() -> void:
	var spacing: Vector2 = Vector2(Config.num("waves.formation.spacing_px.x"), Config.num("waves.formation.spacing_px.y"))
	var top_y: float = Config.num("waves.formation.top_y")
	var zone_y: float = Config.num("enemies.wasp.zone_height_ratio") * Playfield.SIZE.y
	var probe: Enemy = (EntityRegistry.ENEMIES[&"wasp"] as PackedScene).instantiate() as Enemy
	var half: float = probe.sprite_px / 2.0
	probe.free()
	var checked: int = 0
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
				if type_id == &"wasp":
					checked += 1
					for slot: Vector2 in Formation.slots(formation, count, first_row, spacing, top_y, Playfield.SIZE.x):
						var where: String = "%s waves[%d] wasp slot %s" % [path, i, slot]
						assert_lte(slot.y, zone_y, where + " inside the top zone")
						assert_between(slot.x, half, Playfield.SIZE.x - half, where + " fully on screen")
				first_row += Formation.rows_used(formation, count, spacing, Playfield.SIZE.x)
	assert_gt(checked, 0, "at least one Wasp entry checked")


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
