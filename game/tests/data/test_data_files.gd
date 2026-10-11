extends GutTest
## Data files: every level_*.json in res://data/levels/ passes LevelValidator;
## every telegraph in tuning.enemies / tuning.boss is >= the 0.3 s minimum;
## every enemy bullet speed is <= the readable maximum; Wasp, Lancer and
## Bastion waves fit their formation rows inside each type's zone (a Bastion's
## is its drift box); Needle, Bastion and Hunter Wasp tuning is sane; the
## Wasp's and every boss telegraph, glow or charge fits inside its
## start-to-start period (decision #50, DW-69); every
## Needle wave brings cover; every flag-gated enemy type has its flag; the
## energy and drop tuning matches the GDD; the Shield cost and duration match
## the GDD and its UX tuning exists. Dialogue (Stories 5.1-5.2): every file
## validates, every combat sequence is one line of at most 50 characters, and
## every level has at most 2 interruptions (the cut-off line excluded). Story
## 5.3: every sequence id a level references (comms actions, intro and outro)
## exists, and the music fade-out tuning. Story 5.7 (the dialogue script):
## every campaign sequence lives in its file with its mode, line count and
## speakers, no system speaker and no choice yet; the Final Choice refusals
## open with Vale; Tarek's cut-off is final and cuts mid-word; the cast rules
## (Vale's line cap, no gendered terms, self-introductions, "General"). Story
## 7.1: level_1.json is the GDD Cargo Ambush (root values, per-wave counts by
## type, asteroids, reinforcements, exact triggers). Story 7.2: level_2.json is
## the GDD Blockade (root values, per-wave counted totals by type, exact spawn
## order and formations, asteroids, exact triggers) and the formation rows are
## 90 px apart (decision #53); level 3 stays the Wasp-only placeholder; Mauls
## and the convoy are allowed in level_1 but not in levels 2 and 3; Tarek flies
## in levels 1 and 2 and level 3 has no ally yet.

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


## The campaign levels: GDD names, ids 1..3 and the level_dev key set. Level 3
## is still the placeholder (Story 4.1, replaced in Epic 7, decision F12): no
## convoy and 1-2 Wasp-only waves. Level 1 is the real Cargo Ambush since Story
## 7.1 (test_level_1_cargo_ambush_shape) and level 2 the real Blockade since
## Story 7.2 (test_level_2_blockade_shape).
const LEVEL_NAMES: Dictionary = {
	1: "Cargo Ambush",
	2: "The Blockade",
	3: "Siege of the Throne World",
}
## The campaign levels that are still Story 4.1 placeholders.
const PLACEHOLDER_LEVELS: Array[int] = [3]
## The campaign levels the GDD gives no Mauls and no convoy (escort is Level 1 only).
const NO_MAUL_NO_CONVOY_LEVELS: Array[int] = [2, 3]


func test_campaign_levels_have_their_names_and_placeholder_wasp_waves() -> void:
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
		assert_false(Config.level("%d" % i).is_empty(), "Config.level('%d') loads" % i)
		if not PLACEHOLDER_LEVELS.has(i):
			continue
		assert_eq(data.get("convoy"), false, "%s has no convoy" % path)
		var waves: Array = data.get("waves", []) as Array
		assert_between(waves.size(), 1, 2, "%s has 1-2 waves" % path)
		for w: int in waves.size():
			var spawns: Array = (waves[w] as Dictionary).get("spawns", []) as Array
			assert_gt(spawns.size(), 0, "%s wave %d spawns something" % [path, w])
			for entry: Variant in spawns:
				assert_eq((entry as Dictionary).get("type"), "wasp", "%s wave %d is Wasp-only" % [path, w])
			assert_false((waves[w] as Dictionary).has("groups"), "%s wave %d has no groups" % [path, w])


## Counted enemies by type in one wave: every spawn entry plus every group
## entry (the WaveDirector counts groups up front). Type String -> int.
func _wave_type_totals(wave: Dictionary) -> Dictionary:
	var entries: Array = []
	if wave.get("spawns") is Array:
		entries.append_array(wave["spawns"] as Array)
	if wave.get("groups") is Dictionary:
		for group: Variant in (wave["groups"] as Dictionary).values():
			if group is Array:
				entries.append_array(group as Array)
	var totals: Dictionary = {}
	for raw: Variant in entries:
		if raw is Dictionary:
			var type_id: String = str((raw as Dictionary).get("type", ""))
			totals[type_id] = int(totals.get(type_id, 0)) + _entry_count(raw as Dictionary)
	return totals


## Story 7.1: Level 1 is the GDD's Cargo Ambush. Root values (convoy on, Tarek
## flying, no intro because the opening story is its intro, Tarek's closing as
## the outro), the per-wave counted totals by type (spawns plus groups), wave 2's
## asteroids, Lancers as the first entry of every wave that has them (their
## strafe zone ends at y 378, so they take row 0), the exact reinforcements
## group and every wave's exact trigger list: wave 1 also starts the music
## (the level-root `music` key is not read) before its hint; the Tarek warning
## has no flag; the Isolde interruption and the surrender are flag-gated and the
## surrender is paired with a !surrender_prompts trigger so the 4 Mauls arrive
## either way.
func test_level_1_cargo_ambush_shape() -> void:
	var data: Dictionary = Config.level("1")
	assert_false(data.is_empty(), "level_1.json loads")
	var keys: Array = data.keys()
	keys.sort()
	var dev_keys: Array = Config.level("dev").keys()
	dev_keys.sort()
	assert_eq(keys, dev_keys, "the level_dev key set")
	assert_eq(data.get("id"), 1.0, "id 1")
	assert_eq(data.get("name"), "Cargo Ambush")
	assert_eq(data.get("background"), "space_1")
	assert_eq(data.get("music"), "combat")
	assert_eq(data.get("convoy"), true, "convoy on")
	assert_eq(data.get("ally"), "tarek", "Tarek flies")
	assert_true(data.has("intro_sequence"), "intro_sequence key present")
	assert_null(data.get("intro_sequence"), "no intro: the opening story is Level 1's intro")
	assert_eq(data.get("outro_sequence"), "l1_tarek_closing", "Tarek's closing is the outro")
	assert_true(Config.dialogue_is_story(&"l1_tarek_closing"), "the outro is a story sequence")
	var waves: Array = data.get("waves", []) as Array
	assert_eq(waves.size(), 5, "5 waves")
	if waves.size() != 5:
		return
	var expected_totals: Array[Dictionary] = [
		{"wasp": 8},
		{"wasp": 10},
		{"lancer": 2, "wasp": 12, "maul": 3},
		{"lancer": 4, "wasp": 10},
		{"lancer": 3, "wasp": 16, "maul": 4},
	]
	var expected_counted: Array[int] = [8, 10, 17, 14, 23]
	for w: int in 5:
		var wave: Dictionary = waves[w] as Dictionary
		var totals: Dictionary = _wave_type_totals(wave)
		assert_eq(totals, expected_totals[w], "wave %d counted by type" % (w + 1))
		var sum: int = 0
		for type_id: Variant in totals:
			sum += int(totals[type_id])
		assert_eq(sum, expected_counted[w], "wave %d counts %d" % [w + 1, expected_counted[w]])
		var spawns: Array = wave.get("spawns", []) as Array
		if totals.has("lancer") and not spawns.is_empty():
			assert_eq((spawns[0] as Dictionary).get("type"), "lancer", "wave %d: Lancers are the first entry (row 0)" % (w + 1))
		if w != 4:
			assert_false(wave.has("groups"), "wave %d has no groups" % (w + 1))
		if w != 1:
			assert_eq(wave.get("asteroids", []), [], "wave %d has no asteroids" % (w + 1))
	assert_eq((waves[1] as Dictionary).get("asteroids"), [{"size": "small", "count": 3.0}, {"size": "medium", "count": 1.0}], "wave 2: 3 small and 1 medium asteroid")
	assert_eq((waves[4] as Dictionary).get("groups"), {"reinforcements": [{"type": "maul", "count": 4.0, "formation": "grid_4x1", "entry": "sides"}]}, "wave 5: 4 Maul reinforcements")
	var expected_triggers: Array = [
		[{"when": "wave_start", "actions": [{"music": "combat"}, {"hint": "move_fire"}]}],
		[{"when": "wave_start", "actions": [{"hint": "missile"}]}],
		[
			{"when": "wave_start", "actions": [{"comms": "l1_w3_tarek_warning"}]},
			{"when": "progress", "at": 0.25, "flag": "isolde_interruptions", "actions": [{"comms": "l1_w3_isolde_interrupt"}]},
		],
		[],
		[
			{"when": "progress", "at": 0.30, "flag": "surrender_prompts", "actions": [{"comms": "l1_w5_surrender"}, {"spawn_group": "reinforcements"}]},
			{"when": "progress", "at": 0.30, "flag": "!surrender_prompts", "actions": [{"spawn_group": "reinforcements"}]},
		],
	]
	for w: int in 5:
		assert_eq((waves[w] as Dictionary).get("triggers"), expected_triggers[w], "wave %d triggers" % (w + 1))


## Story 7.2: Level 2 is the GDD's Blockade. Root values (no convoy, Tarek
## flying, the l2_briefing story as the intro, Ryn's report story as the
## outro), the per-wave counted totals by type, each wave's exact spawn order
## and formations (a Needle entry first, decision #53 / DW-68; wave 5 is
## Needles, Bastions, Lancers so the rows sit at y 160 / 250 / 340), the exact
## asteroids, no groups and every wave's exact trigger list: wave 1 also starts
## the music (the level-root `music` key is not read); the wave 3 Isolde line is
## gated by isolde_interruptions at 0.25; the wave 5 fall is one tarek_fall
## trigger at 0.5 (story event, then the cut-off line) with no !tarek_fall pair.
## The formation rows are 90 px apart (decision #53).
func test_level_2_blockade_shape() -> void:
	assert_eq(Config.num("waves.formation.spacing_px.y"), 90.0, "formation rows 90 px apart (decision #53)")
	var data: Dictionary = Config.level("2")
	assert_false(data.is_empty(), "level_2.json loads")
	var keys: Array = data.keys()
	keys.sort()
	var dev_keys: Array = Config.level("dev").keys()
	dev_keys.sort()
	assert_eq(keys, dev_keys, "the level_dev key set")
	assert_eq(data.get("id"), 2.0, "id 2")
	assert_eq(data.get("name"), "The Blockade")
	assert_eq(data.get("background"), "space_2")
	assert_eq(data.get("music"), "combat")
	assert_eq(data.get("convoy"), false, "no convoy")
	assert_eq(data.get("ally"), "tarek", "Tarek flies")
	assert_eq(data.get("intro_sequence"), "l2_briefing", "Tarek's briefing is the intro")
	assert_true(Config.dialogue_is_story(&"l2_briefing"), "the intro is a story sequence")
	assert_eq(data.get("outro_sequence"), "l2_ryn_report", "Ryn's report is the outro")
	assert_true(Config.dialogue_is_story(&"l2_ryn_report"), "the outro is a story sequence")
	var waves: Array = data.get("waves", []) as Array
	assert_eq(waves.size(), 5, "5 waves")
	if waves.size() != 5:
		return
	var expected_totals: Array[Dictionary] = [
		{"needle": 2, "wasp": 6},
		{"bastion": 1, "wasp": 8},
		{"needle": 3, "lancer": 3},
		{"bastion": 2, "wasp": 10},
		{"needle": 2, "bastion": 2, "lancer": 4},
	]
	var expected_counted: Array[int] = [8, 9, 6, 12, 8]
	var expected_spawns: Array = [
		[
			{"type": "needle", "count": 2.0, "formation": "grid_2x1", "entry": "top"},
			{"type": "wasp", "count": 6.0, "formation": "grid_3x2", "entry": "top"},
		],
		[
			{"type": "bastion", "count": 1.0, "formation": "grid_1x1", "entry": "top"},
			{"type": "wasp", "count": 8.0, "formation": "grid_4x2", "entry": "top"},
		],
		[
			{"type": "needle", "count": 3.0, "formation": "grid_3x1", "entry": "top"},
			{"type": "lancer", "count": 3.0, "formation": "grid_3x1", "entry": "sides"},
		],
		[
			{"type": "bastion", "count": 2.0, "formation": "grid_2x1", "entry": "top"},
			{"type": "wasp", "count": 10.0, "formation": "grid_5x2", "entry": "top"},
		],
		[
			{"type": "needle", "count": 2.0, "formation": "grid_2x1", "entry": "top"},
			{"type": "bastion", "count": 2.0, "formation": "grid_2x1", "entry": "top"},
			{"type": "lancer", "count": 4.0, "formation": "grid_4x1", "entry": "sides"},
		],
	]
	var expected_asteroids: Array = [
		[{"size": "medium", "count": 2.0}, {"size": "large", "count": 1.0}],
		[],
		[{"size": "medium", "count": 2.0}],
		[{"size": "large", "count": 1.0}],
		[{"size": "medium", "count": 2.0}],
	]
	var expected_triggers: Array = [
		[{"when": "wave_start", "actions": [{"music": "combat"}]}],
		[],
		[{"when": "progress", "at": 0.25, "flag": "isolde_interruptions", "actions": [{"comms": "l2_w3_isolde_interrupt"}]}],
		[],
		[{"when": "progress", "at": 0.5, "flag": "tarek_fall", "actions": [{"story_event": "tarek_fall"}, {"comms": "l2_w5_tarek_cutoff"}]}],
	]
	for w: int in 5:
		var wave: Dictionary = waves[w] as Dictionary
		var totals: Dictionary = _wave_type_totals(wave)
		assert_eq(totals, expected_totals[w], "wave %d counted by type" % (w + 1))
		var sum: int = 0
		for type_id: Variant in totals:
			sum += int(totals[type_id])
		assert_eq(sum, expected_counted[w], "wave %d counts %d" % [w + 1, expected_counted[w]])
		assert_eq(wave.get("spawns"), expected_spawns[w], "wave %d spawn order and formations" % (w + 1))
		assert_eq(wave.get("asteroids"), expected_asteroids[w], "wave %d asteroids" % (w + 1))
		assert_false(wave.has("groups"), "wave %d has no groups" % (w + 1))
		assert_eq(wave.get("triggers"), expected_triggers[w], "wave %d triggers" % (w + 1))


func test_every_level_file_is_valid() -> void:
	var known: Array[StringName] = EntityRegistry.enemy_types()
	var spacing: Vector2 = Vector2(Config.num("waves.formation.spacing_px.x"), Config.num("waves.formation.spacing_px.y"))
	var max_columns: int = Formation.max_columns(spacing, Playfield.SIZE.x)
	for path: String in _level_files():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_true(parsed is Dictionary, "%s parses to an object" % path)
		if not (parsed is Dictionary):
			continue
		var problems: Array[String] = LevelValidator.validate(parsed as Dictionary, path, known, Config.flags, EntityRegistry.enemy_flags(), EntityRegistry.rowless_types(), max_columns)
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


# Decision #50 (DW-69): decision #38 extended to the Wasp and every boss timer.
# Each interval is the start-to-start period and includes its telegraph, glow
# or charge, so the telegraph must fit inside the period.
func test_wasp_and_boss_telegraphs_fit_their_periods() -> void:
	var pairs: Array[Array] = [
		["enemies.wasp.telegraph_s", "enemies.wasp.dive_interval_s.min"],
		["boss.turrets.telegraph_s", "boss.turrets.fire_interval_s"],
		["boss.core.charge_s", "boss.core.radial_interval_s"],
		["boss.desperate.radial_charge_s", "boss.desperate.radial_interval_s"],
		["boss.desperate.aimed_telegraph_s", "boss.desperate.aimed_interval_s"],
	]
	for pair: Array in pairs:
		var telegraph_key: String = pair[0]
		var interval_key: String = pair[1]
		var interval: float = Config.num(interval_key)
		assert_gt(interval, 0.0, "%s > 0" % interval_key)
		assert_lte(Config.num(telegraph_key), interval, "%s <= %s" % [telegraph_key, interval_key])


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
	assert_between(lines.size(), 3, 5, "3-5 lines")
	var speakers: Array[String] = []
	var longest: int = 0
	for line: Variant in lines:
		speakers.append(str((line as Dictionary).get("speaker")))
		longest = maxi(longest, str((line as Dictionary).get("text")).length())
	# Both line cues (GDD #40): one same-speaker advance (click) and one speaker change (handover).
	var same: bool = false
	var change: bool = false
	for i: int in range(1, speakers.size()):
		same = same or speakers[i] == speakers[i - 1]
		change = change or speakers[i] != speakers[i - 1]
	assert_true(same, "a same-speaker advance")
	assert_true(change, "a speaker change")
	assert_true(speakers.has("vale"), "a no-portrait speaker")
	assert_true(speakers.has("tarek") or speakers.has("isolde"), "a portrait speaker")
	assert_between(longest, 180, 200, "one line near 200 characters for the wrap check")


## Story 5.5 (FR41): the opening comms sequence. Story mode, 6-10 lines, only
## Vale, Tarek and Isolde (no system, no narrator), Isolde exactly once, Tarek
## briefing the convoy and Vale speaking at least once.
func test_opening_main_is_the_story_opening() -> void:
	var path: String = DIALOGUE_DIR + "opening.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(parsed is Dictionary, "opening.json parses to an object")
	if not (parsed is Dictionary):
		return
	var sequences: Variant = (parsed as Dictionary).get("sequences")
	assert_true(sequences is Dictionary and (sequences as Dictionary).has("opening_main"), "opening_main lives in opening.json")
	assert_eq(SceneRouter.OPENING_SEQUENCE, &"opening_main", "the router's opening id")
	assert_true(Config.dialogue_is_story(&"opening_main"), "opening_main loads and is story")
	var lines: Array = Config.sequence(&"opening_main").get("lines", []) as Array
	assert_between(lines.size(), 6, 10, "6-10 lines")
	var counts: Dictionary = {"vale": 0, "tarek": 0, "isolde": 0}
	var tarek_convoy: bool = false
	var tarek_welcome: bool = false
	for line: Variant in lines:
		var speaker: String = str((line as Dictionary).get("speaker"))
		var text: String = str((line as Dictionary).get("text"))
		assert_true(counts.has(speaker), "speaker '%s' is vale, tarek or isolde" % speaker)
		counts[speaker] = int(counts.get(speaker, 0)) + 1
		assert_lte(text.length(), Config.int_("comms.story_line_max_chars"), "line within the story limit")
		if speaker == "tarek" and text.to_lower().contains("convoy"):
			tarek_convoy = true
		if speaker == "tarek" and text.to_lower().contains("general") and text.to_lower().contains("welcome"):
			tarek_welcome = true
	assert_eq(counts["isolde"], 1, "exactly one Isolde line")
	assert_gte(counts["tarek"], 1, "Tarek speaks")
	assert_gte(counts["vale"], 1, "Vale speaks")
	assert_true(tarek_convoy, "Tarek briefs the convoy")
	assert_true(tarek_welcome, "Tarek welcomes the General")


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
	for id: StringName in [&"dev_combat_check", &"dev_combat_isolde_2", &"dev_combat_vale"]:
		assert_true(Config.has_sequence(id), "%s loads" % id)
		assert_false(Config.dialogue_is_story(id), "%s is combat" % id)
	var check: Array = Config.sequence(&"dev_combat_check").get("lines", []) as Array
	var again: Array = Config.sequence(&"dev_combat_isolde_2").get("lines", []) as Array
	var vale: Array = Config.sequence(&"dev_combat_vale").get("lines", []) as Array
	assert_eq(str((check[0] as Dictionary).get("speaker")), "isolde", "a portrait speaker")
	# Queued right after dev_combat_check: the same-speaker click (GDD #41).
	assert_eq(str((again[0] as Dictionary).get("speaker")), "isolde", "the same speaker again")
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


## DW-80: a cut-off sfx plays on the reserved comms pool, so combat SFX can't steal it.
func test_every_after_sfx_is_a_comms_sfx() -> void:
	var refs: Array[Array] = _after_sfx(_all_sequences())
	assert_gt(refs.size(), 0, "dialogue has an after.sfx to check")
	for ref: Array in refs:
		assert_true(Audio.COMMS_SFX.has(StringName(str(ref[1]))), "%s: sfx '%s' is in Audio.COMMS_SFX" % [ref[0], ref[1]])


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
			"comms.combat_line_min_s", "comms.combat_line_extra_s", "comms.combat_queue_max",
			"comms.cutoff_hide_s", "comms.cutoff_chars_per_s", "comms.cutoff_shake_px", "comms.cutoff_shake_s"]:
		assert_gt(Config.num(key), 0.0, key)
	for key: String in ["x", "y"]:
		assert_gte(Config.num("ui.comms_box.%s" % key), 0.0, "ui.comms_box.%s" % key)
	for key: String in ["w", "h", "edge_px", "padding_px", "portrait_px", "portrait_gap_px", "name_h_px", "text_line_h_px", "text_lines"]:
		assert_gt(Config.num("ui.comms_box.%s" % key), 0.0, "ui.comms_box.%s" % key)


# --- Isolde beats (Story 5.6) -----------------------------------------------------

## Each Isolde beat: its file, its mode, exactly one Isolde line; combat lines
## are at most 50 characters; the surrender text is exact and has no choice.
func test_isolde_beats_live_in_their_level_files() -> void:
	var beats: Array[Array] = [
		["level_1.json", "l1_w3_isolde_interrupt", "combat"],
		["level_1.json", "l1_w5_surrender", "story"],
		["level_2.json", "l2_w3_isolde_interrupt", "combat"],
		["level_3.json", "l3_w3_isolde_taunt", "combat"],
	]
	var limit: int = Config.int_("comms.combat_line_max_chars")
	for beat: Array in beats:
		var path: String = DIALOGUE_DIR + str(beat[0])
		var id: String = str(beat[1])
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_true(parsed is Dictionary, "%s parses to an object" % path)
		if not (parsed is Dictionary):
			continue
		var sequences: Variant = (parsed as Dictionary).get("sequences")
		assert_true(sequences is Dictionary and (sequences as Dictionary).has(id), "%s lives in %s" % [id, path])
		if not (sequences is Dictionary and (sequences as Dictionary).has(id)):
			continue
		var seq: Dictionary = (sequences as Dictionary)[id] as Dictionary
		assert_eq(seq.get("mode"), beat[2], "%s mode" % id)
		assert_eq(Config.dialogue_is_story(StringName(id)), beat[2] == "story", "%s loads with its mode" % id)
		var lines: Array = seq.get("lines", []) as Array
		assert_eq(lines.size(), 1, "%s has exactly 1 line" % id)
		if lines.is_empty():
			continue
		var line: Dictionary = lines[0] as Dictionary
		assert_eq(str(line.get("speaker")), "isolde", "%s speaker" % id)
		if beat[2] == "combat":
			assert_lte(str(line.get("text", "")).length(), limit, "%s within the combat limit" % id)
	var surrender: Dictionary = Config.sequence(&"l1_w5_surrender")
	assert_eq(str(((surrender.get("lines", []) as Array)[0] as Dictionary).get("text")), "You're outnumbered, General. Come home.", "the exact surrender text")
	assert_false(surrender.has("choice"), "no choice on the sequence")
	assert_false(((surrender.get("lines", []) as Array)[0] as Dictionary).has("choice"), "no choice on the line")


## The dev level that exercises both patterns: the level_dev key set, wave 1's
## gated interruption, wave 2's reinforcements group and the paired triggers.
func test_dev_isolde_level_shape() -> void:
	var data: Dictionary = Config.level("dev_isolde")
	assert_false(data.is_empty(), "level_dev_isolde.json loads")
	var dev: Dictionary = Config.level("dev")
	assert_eq(data.keys().size(), dev.keys().size(), "same root keys as level_dev.json")
	for key: Variant in dev.keys():
		assert_true(data.has(key), "has root key %s" % key)
	assert_eq(data.get("id"), 0.0, "id 0")
	assert_eq(data.get("name"), "Development: Isolde beats")
	assert_null(data.get("intro_sequence"), "no intro")
	assert_null(data.get("outro_sequence"), "no outro")
	var waves: Array = data.get("waves", []) as Array
	assert_eq(waves.size(), 2, "2 waves")
	if waves.size() != 2:
		return
	var w1: Dictionary = waves[0] as Dictionary
	assert_eq(w1.get("spawns"), [{"type": "wasp", "count": 8.0, "formation": "grid_4x2", "entry": "top"}], "wave 1 spawns")
	assert_eq(w1.get("triggers"), [{"when": "progress", "at": 0.25, "flag": "isolde_interruptions", "actions": [{"comms": "l1_w3_isolde_interrupt"}]}], "wave 1 interruption")
	var w2: Dictionary = waves[1] as Dictionary
	assert_eq(w2.get("spawns"), [{"type": "wasp", "count": 10.0, "formation": "grid_5x2", "entry": "top"}], "wave 2 spawns")
	assert_eq(w2.get("groups"), {"reinforcements": [{"type": "wasp", "count": 4.0, "formation": "grid_4x1", "entry": "top"}]}, "wave 2 reinforcements")
	assert_eq(w2.get("triggers"), [
		{"when": "progress", "at": 0.30, "flag": "surrender_prompts", "actions": [{"comms": "l1_w5_surrender"}, {"spawn_group": "reinforcements"}]},
		{"when": "progress", "at": 0.30, "flag": "!surrender_prompts", "actions": [{"spawn_group": "reinforcements"}]},
	], "wave 2 paired surrender triggers")


# --- Control hints (Story 5.8) ---------------------------------------------------

func test_hint_pill_tuning() -> void:
	var expected: Dictionary = {"center_y": 560.0, "h": 52.0, "padding_px": 24.0, "gap_px": 12.0,
		"fade_in_s": 0.2, "fade_out_s": 0.2, "show_s": 5.0, "move_dismiss_px": 150.0}
	for key: String in expected:
		assert_almost_eq(Config.num("ui.hint_pill.%s" % key), float(expected[key]), 0.0001, "ui.hint_pill.%s" % key)


## The dev level that exercises the hints: the level_dev key set, wave 1 asks
## for move_fire and wave 2 for missile at wave start.
func test_dev_hints_level_shape() -> void:
	var data: Dictionary = Config.level("dev_hints")
	assert_false(data.is_empty(), "level_dev_hints.json loads")
	var dev: Dictionary = Config.level("dev")
	assert_eq(data.keys().size(), dev.keys().size(), "same root keys as level_dev.json")
	for key: Variant in dev.keys():
		assert_true(data.has(key), "has root key %s" % key)
	assert_null(data.get("intro_sequence"), "no intro")
	assert_null(data.get("outro_sequence"), "no outro")
	var waves: Array = data.get("waves", []) as Array
	assert_eq(waves.size(), 2, "2 waves")
	if waves.size() != 2:
		return
	assert_eq((waves[0] as Dictionary).get("triggers"), [{"when": "wave_start", "actions": [{"hint": "move_fire"}]}], "wave 1 hint")
	assert_eq((waves[1] as Dictionary).get("triggers"), [{"when": "wave_start", "actions": [{"hint": "missile"}]}], "wave 2 hint")


# --- The dialogue script (Story 5.7) ----------------------------------------------

## The campaign dialogue files (dev.json is not part of the script).
const CAMPAIGN_DIALOGUE_FILES: Array[String] = ["opening.json", "level_1.json", "level_2.json", "level_3.json"]

## Every campaign sequence: [file, id, mode, allowed speakers, min lines, max lines].
const CAMPAIGN_SCRIPT: Array[Array] = [
	["opening.json", "opening_main", "story", ["vale", "tarek", "isolde"], 6, 10],
	["level_1.json", "l1_w3_tarek_warning", "combat", ["tarek"], 1, 1],
	["level_1.json", "l1_w3_isolde_interrupt", "combat", ["isolde"], 1, 1],
	["level_1.json", "l1_w5_surrender", "story", ["isolde"], 1, 1],
	["level_1.json", "l1_tarek_closing", "story", ["tarek"], 1, 2],
	["level_2.json", "l2_briefing", "story", ["tarek"], 2, 3],
	["level_2.json", "l2_w3_isolde_interrupt", "combat", ["isolde"], 1, 1],
	["level_2.json", "l2_w5_tarek_cutoff", "combat", ["tarek"], 1, 1],
	["level_2.json", "l2_ryn_report", "story", ["ryn"], 1, 10],
	["level_3.json", "l3_briefing", "story", ["ryn"], 1, 10],
	["level_3.json", "l3_w3_isolde_taunt", "combat", ["isolde"], 1, 1],
	["level_3.json", "l3_final_choice", "story", ["isolde"], 1, 10],
	["level_3.json", "l3_isolde_refuse_surrender", "story", ["vale", "isolde"], 2, 2],
	["level_3.json", "l3_isolde_refuse_destroy", "story", ["vale", "isolde"], 2, 2],
	["level_3.json", "l3_isolde_final", "story", ["isolde"], 1, 10],
]

## Gendered terms no line may use, as whole words (Vale is gender-neutral).
const GENDERED_ADDRESS: Array[String] = ["sir", "ma'am", "madam", "mister", "mr", "mrs", "ms", "lady", "lord", "son"]

## The most lines Vale speaks across the campaign files (the opening plus line
## 1 of each Final Choice refusal).
const MAX_VALE_LINES: int = 5


## The sequences of one campaign file (id String -> Dictionary), empty when it
## doesn't parse.
func _file_sequences(file: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIALOGUE_DIR + file))
	if parsed is Dictionary and (parsed as Dictionary).get("sequences") is Dictionary:
		return (parsed as Dictionary).get("sequences") as Dictionary
	return {}


## Every line of every sequence in the campaign files, as [file, id, line] triples.
func _campaign_lines() -> Array[Array]:
	var out: Array[Array] = []
	for file: String in CAMPAIGN_DIALOGUE_FILES:
		var sequences: Dictionary = _file_sequences(file)
		for id: Variant in sequences:
			for line: Variant in (sequences[id] as Dictionary).get("lines", []) as Array:
				out.append([file, str(id), line as Dictionary])
	return out


func _lines_of(id: String) -> Array:
	return Config.sequence(StringName(id)).get("lines", []) as Array


## Every campaign id lives in its file, with its mode, its line count and only
## its allowed speakers, and loads through Config; no `system` speaker anywhere
## in the campaign; no `choice` on the surrender or on the Final Choice lead-in
## (Story 7.5 adds that one).
func test_campaign_script_layout() -> void:
	assert_eq(CAMPAIGN_SCRIPT.size(), 15, "15 campaign sequences")
	for file: String in CAMPAIGN_DIALOGUE_FILES:
		var expected: Array = []
		for row: Array in CAMPAIGN_SCRIPT:
			if str(row[0]) == file:
				expected.append(str(row[1]))
		expected.sort()
		var actual: Array = []
		for id: Variant in _file_sequences(file):
			actual.append(str(id))
		actual.sort()
		assert_eq(actual, expected, "%s holds exactly its campaign sequences" % file)
	for row: Array in CAMPAIGN_SCRIPT:
		var file: String = str(row[0])
		var id: String = str(row[1])
		var sequences: Dictionary = _file_sequences(file)
		assert_true(sequences.has(id), "%s lives in %s" % [id, file])
		if not sequences.has(id):
			continue
		var seq: Dictionary = sequences[id] as Dictionary
		assert_eq(seq.get("mode"), row[2], "%s mode" % id)
		assert_true(Config.has_sequence(StringName(id)), "%s loads through Config" % id)
		assert_eq(Config.dialogue_is_story(StringName(id)), row[2] == "story", "%s loads with its mode" % id)
		var lines: Array = seq.get("lines", []) as Array
		assert_between(lines.size(), int(row[4]), int(row[5]), "%s has %d-%d lines" % [id, row[4], row[5]])
		for line: Variant in lines:
			var speaker: String = str((line as Dictionary).get("speaker"))
			assert_true((row[3] as Array).has(speaker), "%s speaker '%s' is one of %s" % [id, speaker, row[3]])
	var all_lines: Array[Array] = _campaign_lines()
	assert_gt(all_lines.size(), 0, "campaign lines to check")
	for entry: Array in all_lines:
		assert_ne(str((entry[2] as Dictionary).get("speaker")), "system", "%s %s: no system speaker" % [entry[0], entry[1]])
	for id: StringName in [&"l1_w5_surrender", &"l3_final_choice"]:
		assert_false(Config.sequence(id).has("choice"), "%s has no choice" % id)


## Both Final Choice refusals open with Vale's line and Isolde answers; the
## Vale's surrender offer mirrors Isolde's Level 1 "You're outnumbered" (GDD
## decision #44).
func test_refusals_open_with_vale() -> void:
	for id: String in ["l3_isolde_refuse_surrender", "l3_isolde_refuse_destroy"]:
		var lines: Array = _lines_of(id)
		assert_gte(lines.size(), 2, "%s has Vale's line and Isolde's answer" % id)
		if lines.size() < 2:
			continue
		assert_eq(str((lines[0] as Dictionary).get("speaker")), "vale", "%s line 1 is Vale" % id)
		for i: int in range(1, lines.size()):
			assert_eq(str((lines[i] as Dictionary).get("speaker")), "isolde", "%s line %d is Isolde" % [id, i + 1])
	var surrender: Array = _lines_of("l3_isolde_refuse_surrender")
	if surrender.is_empty():
		return
	var offer: String = str((surrender[0] as Dictionary).get("text")).to_lower()
	assert_true(offer.contains("outnumbered"), "Vale's offer mirrors Isolde's 'You're outnumbered'")


## True for a single letter character.
static func _is_letter(c: String) -> bool:
	return c.length() == 1 and c.to_lower() != c.to_upper()


func test_is_letter_self_check() -> void:
	assert_true(_is_letter("v"), "v")
	assert_true(_is_letter("E"), "E")
	for c: String in [" ", ",", "'", "!", "-", "4", "", "ab"]:
		assert_false(_is_letter(c), "'%s' is not a letter" % c)


## Tarek's cut-off: Tarek, combat, the full `after`, and the cut lands mid-word.
func test_tarek_cutoff_is_final() -> void:
	var seq: Dictionary = Config.sequence(&"l2_w5_tarek_cutoff")
	assert_eq(seq.get("mode"), "combat", "combat mode")
	var lines: Array = seq.get("lines", []) as Array
	assert_eq(lines.size(), 1, "one line")
	if lines.size() != 1:
		return
	var line: Dictionary = lines[0] as Dictionary
	assert_eq(str(line.get("speaker")), "tarek", "Tarek speaks")
	assert_eq(line.get("after"), {"silence": "until_wave_clear", "shake": "cutoff", "sfx": "comms_static", "music": "stop"}, "the full after")
	var text: String = str(line.get("text"))
	var at: int = int(line.get("cut_off_at", 0))
	assert_between(at, 1, text.length() - 1, "cut_off_at inside the text")
	if at < 1 or at > text.length() - 1:
		return
	assert_true(_is_letter(text[at - 1]), "the last shown char '%s' is a letter" % text[at - 1])
	assert_true(_is_letter(text[at]), "the next char '%s' is a letter (mid-word)" % text[at])


## GDD decision #43: the cut-off tuning (16 chars/s, a "..." suffix, an
## 18 px / 0.9 s shake, a 2.5 s hold equal to the comms_static clip) and both
## Tarek cut-offs use the dedicated `cutoff` shake.
func test_cut_off_tuning_and_shake() -> void:
	var comms: Dictionary = Config.section("comms")
	assert_true(comms.get("cutoff_suffix") is String, "cutoff_suffix is a String")
	assert_eq(comms.get("cutoff_chars_per_s"), 16.0, "cutoff_chars_per_s")
	assert_eq(comms.get("cutoff_suffix"), "...", "cutoff_suffix")
	assert_eq(comms.get("cutoff_shake_px"), 18.0, "cutoff_shake_px")
	assert_eq(comms.get("cutoff_shake_s"), 0.9, "cutoff_shake_s")
	assert_eq(comms.get("cutoff_hide_s"), 2.5, "cutoff_hide_s")
	var clip: AudioStream = Audio.SFX[&"comms_static"]
	assert_almost_eq(clip.get_length(), Config.num("comms.cutoff_hide_s"), 0.01, "the hold equals the static clip")
	for id: StringName in [&"dev_tarek_cutoff", &"l2_w5_tarek_cutoff"]:
		var lines: Array = Config.sequence(id).get("lines", []) as Array
		assert_eq(lines.size(), 1, "%s: one line" % id)
		if lines.size() == 1:
			var after: Dictionary = (lines[0] as Dictionary).get("after", {}) as Dictionary
			assert_eq(after.get("shake"), DialogueValidator.SHAKE_CUTOFF, "%s: the cut-off shake" % id)


## Whether `text` uses a GENDERED_ADDRESS term as a whole word (case-insensitive;
## an apostrophe counts as part of a word, so "son's" is caught by neither side).
static func _gendered(text: String) -> bool:
	var regex: RegEx = RegEx.create_from_string("(?i)(?<![\\w'])(%s)(?![\\w'])" % "|".join(GENDERED_ADDRESS))
	return regex.search(text) != null


func test_gendered_check_self_check() -> void:
	for text: String in ["Yes, sir.", "Ma'am!", "MADAM", "Mister Vale", "Mr. Vale", "Lady Arden", "My son.", "Mrs. Vale", "Ms Vale", "My lord."]:
		assert_true(_gendered(text), "'%s' is gendered" % text)
	for text: String in ["Sirens wail.", "Arden Madison", "Persona", "Ladybird", "Season", "General Arden Vale"]:
		assert_false(_gendered(text), "'%s' is not gendered" % text)


## Vale speaks at most MAX_VALE_LINES lines and no line uses a gendered term;
## Tarek, Vale ("Arden Vale") and Isolde name themselves in their own opening
## lines; Ryn names herself in her report's first line; in every campaign file
## someone other than Vale addresses the General.
func test_cast_rules() -> void:
	var vale_lines: int = 0
	var general_in: Dictionary = {}
	for entry: Array in _campaign_lines():
		var line: Dictionary = entry[2] as Dictionary
		var speaker: String = str(line.get("speaker"))
		var text: String = str(line.get("text"))
		if speaker == "vale":
			vale_lines += 1
		elif text.contains("General"):
			general_in[entry[0]] = true
		assert_false(_gendered(text), "%s %s: no gendered term in '%s'" % [entry[0], entry[1], text])
	assert_lte(vale_lines, MAX_VALE_LINES, "Vale speaks at most %d lines" % MAX_VALE_LINES)
	for file: String in CAMPAIGN_DIALOGUE_FILES:
		assert_true(general_in.has(file), "%s: someone addresses the General" % file)
	var names: Dictionary = {"tarek": "Tarek", "vale": "Arden Vale", "isolde": "Isolde"}
	var named: Dictionary = {}
	for line: Variant in _lines_of("opening_main"):
		var speaker: String = str((line as Dictionary).get("speaker"))
		if names.has(speaker) and str((line as Dictionary).get("text")).contains(str(names[speaker])):
			named[speaker] = true
	for speaker: String in names:
		assert_true(named.has(speaker), "%s names themselves in the opening" % speaker)
	var report: Array = _lines_of("l2_ryn_report")
	assert_false(report.is_empty(), "l2_ryn_report has lines")
	if not report.is_empty():
		assert_eq(str((report[0] as Dictionary).get("speaker")), "ryn", "Ryn speaks first")
		assert_true(str((report[0] as Dictionary).get("text")).contains("Ryn"), "Ryn names herself")


# --- Convoy (Story 6.1) ------------------------------------------------------------

## The dev level that proves the convoy: the level_dev key set, convoy on, two
## short waves of Wasps (Lancers allowed), then (Story 6.2) a Maul wave: 4
## side-entry Mauls plus 2 top Wasps; no intro or outro.
func test_dev_convoy_level_shape() -> void:
	var data: Dictionary = Config.level("dev_convoy")
	assert_false(data.is_empty(), "level_dev_convoy.json loads")
	var dev: Dictionary = Config.level("dev")
	var keys: Array = data.keys()
	keys.sort()
	var dev_keys: Array = dev.keys()
	dev_keys.sort()
	assert_eq(keys, dev_keys, "the level_dev key set")
	assert_eq(data.get("id"), 0.0)
	assert_eq(data.get("name"), "Development: convoy")
	assert_eq(data.get("convoy"), true, "convoy on")
	assert_null(data.get("intro_sequence"), "no intro")
	assert_null(data.get("outro_sequence"), "no outro")
	var waves: Array = data.get("waves", []) as Array
	assert_eq(waves.size(), 3, "3 waves")
	for w: int in mini(waves.size(), 2):
		var types: Array[String] = []
		for entry: Variant in (waves[w] as Dictionary).get("spawns", []) as Array:
			types.append(str((entry as Dictionary).get("type")))
		assert_true(types.has("wasp"), "wave %d has Wasps" % w)
		for t: String in types:
			assert_true(t == "wasp" or t == "lancer", "wave %d is Wasps (and Lancers) only" % w)
	if waves.size() < 3:
		return
	var spawns: Array = (waves[2] as Dictionary).get("spawns", []) as Array
	assert_eq(spawns.size(), 2, "wave 3: a Maul entry and a Wasp entry")
	if spawns.size() != 2:
		return
	var mauls: Dictionary = spawns[0]
	assert_eq(mauls.get("type"), "maul")
	assert_eq(mauls.get("count"), 4.0)
	assert_eq(mauls.get("formation"), "grid_4x1")
	assert_eq(mauls.get("entry"), "sides")
	var wasps: Dictionary = spawns[1]
	assert_eq(wasps.get("type"), "wasp")
	assert_eq(wasps.get("count"), 2.0)
	assert_eq(wasps.get("entry"), "top")


## Mauls appear only in dev levels and in level_1 (Story 7.1: the W3 ambush and
## the W5 reinforcements); the GDD gives levels 2 and 3 none.
func test_mauls_only_in_dev_levels_and_level_1() -> void:
	for path: String in _level_files():
		var text: String = FileAccess.get_file_as_string(path)
		if text.contains("\"maul\""):
			var file: String = path.get_file()
			assert_true(file.begins_with("level_dev") or file == "level_1.json", "%s: Mauls only in dev levels and level_1" % path)
	assert_true(FileAccess.get_file_as_string(LEVELS_DIR + "level_1.json").contains("\"maul\""), "level_1 has Mauls")
	for i: int in NO_MAUL_NO_CONVOY_LEVELS:
		assert_false(FileAccess.get_file_as_string(LEVELS_DIR + "level_%d.json" % i).contains("\"maul\""), "level_%d has no Mauls" % i)


func test_maul_tuning_ranges() -> void:
	assert_eq(Config.int_("enemies.maul.hp"), 6)
	assert_eq(str(Config.section("enemies.maul").get("tier")), "medium")
	assert_gt(Config.num("enemies.maul.dive_speed_px_s"), 0.0, "dive_speed_px_s > 0")
	assert_gt(Config.num("enemies.maul.hitbox_ratio"), 0.0)
	assert_lte(Config.num("enemies.maul.hitbox_ratio"), 1.0)
	assert_eq(Config.int_("damage.convoy_maul"), 10)
	assert_gte(Config.int_("damage.maul_contact_hearts"), 1)
	assert_between(Config.num("drops.maul.chance"), 0.0, 1.0)


## Only dev levels and level_1 (the escort level, Story 7.1) turn the convoy
## on (decision F12); levels 2 and 3 have none.
func test_convoy_is_a_bool_and_only_on_in_dev_levels_and_level_1() -> void:
	for path: String in _level_files():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			continue
		var value: Variant = (parsed as Dictionary).get("convoy", false)
		assert_true(value is bool, "%s convoy is a bool" % path)
		if value is bool and bool(value):
			var file: String = path.get_file()
			assert_true(file.begins_with("level_dev") or file == "level_1.json", "%s: only dev levels and level_1 have a convoy" % path)
	assert_eq(Config.level("1").get("convoy"), true, "level_1 has the convoy")
	for i: int in NO_MAUL_NO_CONVOY_LEVELS:
		assert_eq(Config.level(str(i)).get("convoy"), false, "level_%d has no convoy" % i)


# --- Ally (Story 6.4) ------------------------------------------------------------------

## The dev level for the kill-share playtest: the level_dev key set, Tarek on,
## no convoy, 3-4 waves mixing Wasps and Lancers with a Needle wave that brings
## asteroids; no intro or outro.
func test_dev_ally_level_shape() -> void:
	var data: Dictionary = Config.level("dev_ally")
	assert_false(data.is_empty(), "level_dev_ally.json loads")
	var keys: Array = data.keys()
	keys.sort()
	var dev_keys: Array = Config.level("dev").keys()
	dev_keys.sort()
	assert_eq(keys, dev_keys, "the level_dev key set")
	assert_eq(data.get("id"), 0.0)
	assert_eq(data.get("name"), "Development: ally")
	assert_eq(data.get("ally"), "tarek", "Tarek flies")
	assert_eq(data.get("convoy"), false, "no convoy")
	assert_null(data.get("intro_sequence"))
	assert_null(data.get("outro_sequence"))
	var waves: Array = data.get("waves", []) as Array
	assert_between(waves.size(), 3, 4, "3-4 waves")
	var types: Dictionary = {}
	var needle_with_rocks: bool = false
	for wave: Variant in waves:
		var wave_types: Array[String] = []
		for entry: Variant in (wave as Dictionary).get("spawns", []) as Array:
			wave_types.append(str((entry as Dictionary).get("type")))
			types[str((entry as Dictionary).get("type"))] = true
		if wave_types.has("needle") and not ((wave as Dictionary).get("asteroids", []) as Array).is_empty():
			needle_with_rocks = true
	assert_true(types.has("wasp"), "Wasps")
	assert_true(types.has("lancer"), "Lancers")
	assert_true(needle_with_rocks, "a Needle wave with asteroids")


## level_dev keeps no ally; levels 1 and 2 fly Tarek (Stories 7.1 and 7.2);
## level 3 keeps "ally": null until Story 7.6.
func test_ally_tarek_in_levels_1_2_and_off_in_dev_and_level_3() -> void:
	assert_null(Config.level("dev").get("ally"), "level_dev has no ally")
	assert_eq(Config.level("1").get("ally"), "tarek", "level_1 flies Tarek")
	assert_eq(Config.level("2").get("ally"), "tarek", "level_2 flies Tarek")
	assert_null(Config.level("3").get("ally"), "level_3 has no ally yet")


func test_allies_tuning_ranges() -> void:
	assert_gt(Config.num("allies.fire_interval_s"), 0.0, "fire_interval_s > 0")
	assert_gt(Config.num("allies.shot_speed_px_s"), 0.0, "shot_speed_px_s > 0")
	assert_gt(Config.num("allies.speed_px_s"), 0.0, "speed_px_s > 0")
	assert_gt(Config.num("allies.ship_px"), 0.0, "ship_px > 0")
	assert_gt(Config.int_("allies.damage"), 0, "damage > 0")
	assert_lt(Config.num("allies.patrol_band_y.min"), Config.num("allies.patrol_band_y.max"), "patrol_band_y.min < max")
	assert_lte(Config.num("allies.kill_share.min"), Config.num("allies.kill_share.max"), "kill_share.min <= max")


# --- Tarek's fall (Story 6.5) ------------------------------------------------------------

## The dev level that proves the fall: the level_dev key set, Tarek on, no
## convoy, exactly one trigger with a story_event, flagged tarek_fall at 0.5,
## whose actions are the story event then the Level 2 cut-off line.
func test_dev_tarek_fall_level_shape() -> void:
	var data: Dictionary = Config.level("dev_tarek_fall")
	assert_false(data.is_empty(), "level_dev_tarek_fall.json loads")
	var keys: Array = data.keys()
	keys.sort()
	var dev_keys: Array = Config.level("dev").keys()
	dev_keys.sort()
	assert_eq(keys, dev_keys, "the level_dev key set")
	assert_eq(data.get("id"), 0.0)
	assert_eq(data.get("name"), "Development: Tarek's fall")
	assert_eq(data.get("ally"), "tarek", "Tarek flies")
	assert_eq(data.get("convoy"), false, "no convoy")
	assert_null(data.get("music"))
	assert_null(data.get("intro_sequence"))
	assert_null(data.get("outro_sequence"))
	var waves: Array = data.get("waves", []) as Array
	assert_eq(waves.size(), 3, "3 waves")
	var found: Array[Dictionary] = []
	var found_wave: int = -1
	for i: int in waves.size():
		for trigger: Variant in ((waves[i] as Dictionary).get("triggers", []) as Array):
			for action: Variant in ((trigger as Dictionary).get("actions", []) as Array):
				if (action as Dictionary).has("story_event"):
					found.append(trigger as Dictionary)
					found_wave = i
					break
	assert_eq(found.size(), 1, "exactly one story_event trigger")
	if found.size() != 1:
		return
	assert_eq(found_wave, 1, "in wave 2")
	var t: Dictionary = found[0]
	assert_eq(t.get("when"), "progress")
	assert_eq(t.get("at"), 0.5)
	assert_eq(t.get("flag"), "tarek_fall", "gated by tarek_fall")
	assert_eq(t.get("actions"), [{"story_event": "tarek_fall"}, {"comms": "l2_w5_tarek_cutoff"}], "the story event, then the cut-off line")
	assert_true(Config.has_sequence(&"l2_w5_tarek_cutoff"), "the line exists")


func test_allies_fall_tuning_ranges() -> void:
	assert_gte(Config.num("allies.fall.approach_s"), 0.0, "approach_s >= 0")
	assert_gte(Config.num("allies.fall.shield_s"), 0.0, "shield_s >= 0")
	assert_gt(Config.num("allies.fall.exit_speed_px_s"), 0.0, "exit_speed_px_s > 0")
	assert_gt(Config.num("allies.fall.shield_radius_px"), 0.0, "shield_radius_px > 0")
	assert_gt(Config.num("allies.fall.shield_offset_px"), 0.0, "shield_offset_px > 0")
	assert_gt(Config.num("allies.fall.shield_flash_hz"), 0.0, "shield_flash_hz > 0")
	assert_gte(Config.num("allies.fall.exit_drop"), 0.0, "exit_drop >= 0 (down or level)")
