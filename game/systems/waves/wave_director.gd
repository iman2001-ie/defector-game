class_name WaveDirector
extends Node
## Runs a level's scripted waves from data (architecture Novel Pattern #1).
##
## The only node that decides what spawns and when; the Spawner does the
## instantiating. Per wave: build the BeatTriggers, count the total up front
## (spawns + every group entry, a boss = 1), emit wave_started, run the
## wave_start triggers, spawn the entries in stacked formation rows and the
## boss (if any), subtract what failed to spawn, then spawn the (never counted)
## asteroids.
##
## After every progress change (a resolve or a subtraction): emit
## wave_progress_changed, fire progress triggers in array order, then try to
## clear. A wave clears when every counted enemy resolved and no action chain
## or group spawn is pending; then wave_clear triggers, a waves.gap_s gap (on a
## pausable one-shot Timer child, like a `wait` action), the running chains
## finish, and the next wave starts (or the level clears).
## A stall net subtracts groups that can never spawn, so no wave soft-locks.
##
## Boss wave (Story 7.3): `{ "boss": "<id>", "triggers": [...] }` counts 1. The
## boss spawns through Spawner.spawn_boss (EntityRegistry.BOSSES), after the
## wave_start triggers, and is one live counted unit (in Groups.BOSS, never in
## Groups.COUNTED), so the stall net never subtracts a living boss. It resolves
## only on Events.boss_defeated (once; a second one, or one after level_failed,
## changes nothing). An unknown id or a failed spawn logs an error naming it
## and is subtracted, so the wave still clears. When the boss spawned, the
## WaveDirector also spawns its boss.phase1_medium_asteroids medium cover
## asteroids, in addition to the wave's `asteroids`. F3 frees a live boss
## (without boss_defeated) and resolves the wave; F6 frees it with the counted
## enemies and starts the boss wave with a fresh one (debug_jump_to_wave, which
## the Story 8.3 level bench also uses to jump to any wave).
## Once Events.level_failed fires (the player died) the attempt is dead until
## start_level / debug_skip_to_boss (retro F1, DW-54): no wave or level clears
## and progress is frozen (kills don't resolve, nothing is subtracted, no
## wave_progress_changed, no progress triggers, no stall net, F3 refuses).
## A running chain runs no further action of any kind (decision #39, amended
## by DW-78): it stops at its next action or after its current await, logs one
## INFO beat line and leaves the chain count. A group spawn requested before
## the failure still spawns, uncounted.
## First outcome wins: a level_failed after level_cleared changes nothing here.
##
## Formation rows: each entry starts on the next free row, except the
## EntityRegistry.ROWLESS_TYPES (the Hunter Wasp), which don't advance the row:
## it never holds its slot (a sides entry only starts at the slot's y, so it may
## share a row with the next entry). The Needle takes a row: it anchors on and
## roams it.
## A level may move its rows (playtest 2026-10-13, Level 3 under the throne
## world): an optional `formation` object with `top_y` and/or `spacing_y`
## replaces waves.formation.top_y / spacing_px.y for that level
## (formation_rows()), and every spawn gets `row_shift_y`, the level's top_y
## minus the tuned one, so the Needle's anchor row moves with the rows.
##
## Actions (Story 5.3) run in order inside each trigger's chain: spawn_group,
## wait (a pausable one-shot Timer child), comms (requests the sequence; a story
## sequence holds the chain until its comms_sequence_finished arrives, even
## synchronously during the request; combat and unknown ids don't wait),
## story_event (Events.story_event_requested), music (Audio.apply_music_action)
## and hint (Story 5.8: Events.hint_requested for the HUD HintPill; never waits).
## The level's intro_sequence plays before wave 1 (skipped on a retry) and its
## outro_sequence before level_cleared (also on a retry), each the same way as
## a comms action. Every await in a chain, the wave-clear gap, the intro or the
## outro is on this node's own signal or a child Timer, so a freed director
## (death reload) never resumes one. After every await a chain of an older wave
## (F6, a new start_level) returns without touching the counters; then a chain
## of a failed attempt stops (above).
##
## Feature-flag gate: a type listed in EntityRegistry.ENEMY_FLAGS whose flag is
## false at wave start is disabled for that wave. Its spawn and group entries
## count 0 toward the total, take no formation rows and spawn nothing. One DEBUG
## line is logged when such an entry would spawn (a group entry only if its group
## is requested; a never-requested group logs nothing). They are a designer
## choice, not an error, so never subtracted.

## Emitted when the last running action chain finishes.
signal chains_finished
## Relay of Events.comms_sequence_finished (connected in _ready): chains, the
## intro and the outro await this, never the Events signal itself.
signal _sequence_done(sequence_id: StringName)

const WHEN_WAVE_START: StringName = &"wave_start"
const WHEN_PROGRESS: StringName = &"progress"
const WHEN_WAVE_CLEAR: StringName = &"wave_clear"
const DEFAULT_ENTRY: String = "top"
## Shortest child Timer: a Timer can't run 0 s, so a gap of 0 (or less) fires on
## the next frame like the old zero-length timer. Technical, not a design number.
const MIN_TIMER_S: float = 0.001

@export var spawner: Spawner

## Asteroid x positions; tests seed it.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _source: String = ""
var _level_id: int = 0
var _waves: Array = []
var _intro_sequence: String = ""
var _outro_sequence: String = ""
## Sequence id -> how many comms_sequence_finished it has had (a story wait
## compares against the count taken before its request).
var _finished_counts: Dictionary[StringName, int] = {}
var _wave_index: int = -1
## Bumped by every start_level and start_wave: resolves, chains and spawns of an older wave are ignored.
var _serial: int = 0
var _progress: WaveProgress = WaveProgress.new()
var _triggers: Array[BeatTrigger] = []
## Group name (String) -> Array of entries.
var _groups: Dictionary = {}
## Group name -> true once requested, spawned, skipped (F3) or given up (stall net).
var _spawned_groups: Dictionary = {}
## Group name -> true for groups F3 skipped or the stall net gave up on (a later
## spawn_group logs at DEBUG only).
var _skipped_groups: Dictionary = {}
## Group name -> true while its deferred spawn is pending.
var _pending_groups: Dictionary = {}
var _next_row: int = 0
## Enemy type id (StringName) -> gating flag name, for types whose flag was off
## at wave start.
var _disabled_types: Dictionary = {}
var _live_counted: int = 0
## The current boss wave's boss (null when none spawned); freed by F3 and F6.
var _boss: Enemy = null
## True while the current wave's boss is a live counted unit (spawned and not
## yet resolved by Events.boss_defeated, F3 or F6).
var _boss_pending: bool = false
var _running_chains: int = 0
var _clearing: bool = false
var _level_done: bool = false
## Set by Events.level_failed: a dead attempt never counts progress or clears a
## wave or the level (DW-54).
var _failed: bool = false
## True while a step runs triggers: chain ends then leave stall/clear checks to the step.
var _in_step: bool = false
var _debug_resolving: bool = false

var _gap_s: float = 0.0
var _spacing: Vector2 = Vector2.ZERO
var _top_y: float = 0.0
## The level's top_y minus waves.formation.top_y (0 without an override).
var _row_shift_y: float = 0.0
var _width: float = 0.0


func _ready() -> void:
	add_to_group(Groups.WAVE_DIRECTOR)
	Events.level_failed.connect(_on_events_level_failed)
	Events.comms_sequence_finished.connect(_on_events_comms_sequence_finished)
	Events.boss_defeated.connect(_on_events_boss_defeated)


## First outcome wins (DW-54): a failure after the level cleared is ignored.
func _on_events_level_failed(_reason: StringName) -> void:
	if _level_done:
		return
	_failed = true


func _on_events_comms_sequence_finished(sequence_id: StringName) -> void:
	_finished_counts[sequence_id] = _finished_count(sequence_id) + 1
	_sequence_done.emit(sequence_id)


## The level's formation rows as (top_y, spacing_y): the tuned
## waves.formation.top_y / spacing_px.y, each replaced by the level data's
## `formation.top_y` / `formation.spacing_y` when that is a number (the
## LevelValidator reports anything else).
static func formation_rows(data: Dictionary) -> Vector2:
	var rows: Vector2 = Vector2(Config.num("waves.formation.top_y"), Config.num("waves.formation.spacing_px.y"))
	var override: Variant = data.get("formation")
	if override is Dictionary:
		var top: Variant = (override as Dictionary).get("top_y")
		var spacing: Variant = (override as Dictionary).get("spacing_y")
		if top is float or top is int:
			rows.x = float(top)
		if spacing is float or spacing is int:
			rows.y = float(spacing)
	return rows


## Starts the level: its intro (if any, and not on a retry), then wave 1.
## `source` (the file path) prefixes every data error. Callers don't await it.
func start_level(data: Dictionary, source: String) -> void:
	_serial += 1
	_wave_index = -1
	_source = source
	_gap_s = Config.num("waves.gap_s")
	var rows: Vector2 = formation_rows(data)
	_spacing = Vector2(Config.num("waves.formation.spacing_px.x"), rows.y)
	_top_y = rows.x
	_row_shift_y = _top_y - Config.num("waves.formation.top_y")
	_width = Playfield.SIZE.x
	_level_id = int(data.get("id", 0)) if (data.get("id") is float or data.get("id") is int) else 0
	_intro_sequence = str(data.get("intro_sequence", "")) if data.get("intro_sequence") is String else ""
	_outro_sequence = str(data.get("outro_sequence", "")) if data.get("outro_sequence") is String else ""
	_level_done = false
	_failed = false
	var waves: Variant = data.get("waves")
	if not (waves is Array) or (waves as Array).is_empty():
		Log.error("wave", "%s has no waves; nothing to run" % source)
		_waves = []
		return
	_waves = waves
	if spawner == null:
		Log.error("wave", "WaveDirector has no spawner; every spawn fails")
	if _intro_sequence.is_empty():
		start_wave(0)
	elif GameState.is_retry:
		Log.info("beat", "Level %d intro '%s' skipped (retry)" % [_level_id, _intro_sequence])
		start_wave(0)
	else:
		_play_intro()  # Not awaited: wave 1 starts once the intro allows it.


## Plays the intro like a comms action (a story intro holds wave 1 until it
## finishes), then starts wave 1 unless F6 or a new start_level moved on.
func _play_intro() -> void:
	var serial: int = _serial
	var id: StringName = StringName(_intro_sequence)
	Log.info("beat", "Level %d intro '%s'" % [_level_id, id])
	var before: int = _request_sequence(id)
	while before >= 0 and _finished_count(id) == before:
		await _sequence_done
		if serial != _serial or _failed:
			return
	if serial != _serial or _failed:
		return
	start_wave(0)


## Starts wave `index` (0-based), abandoning anything still running from the
## current wave.
func start_wave(index: int) -> void:
	if index < 0 or index >= _waves.size():
		Log.error("wave", "%s: no wave %d (level has %d)" % [_source, index + 1, _waves.size()])
		return
	_serial += 1
	_wave_index = index
	_clearing = false
	_running_chains = 0
	_live_counted = 0
	_boss = null
	_boss_pending = false
	_next_row = 0
	_spawned_groups.clear()
	_skipped_groups.clear()
	_pending_groups.clear()
	_disabled_types.clear()
	for type_id: StringName in EntityRegistry.ENEMY_FLAGS:
		var flag_name: String = EntityRegistry.ENEMY_FLAGS[type_id]
		if not Config.flag(flag_name):
			_disabled_types[type_id] = flag_name
	var path: String = "waves[%d]" % index
	var wave: Dictionary = _waves[index] if _waves[index] is Dictionary else {}

	_triggers.clear()
	var raw_triggers: Variant = wave.get("triggers", [])
	if raw_triggers is Array:
		for raw: Variant in raw_triggers:
			if raw is Dictionary:
				_triggers.append(BeatTrigger.new(raw as Dictionary))
	_groups = wave.get("groups", {}) if wave.get("groups") is Dictionary else {}
	var spawns: Array = wave.get("spawns", []) if wave.get("spawns") is Array else []

	var total: int = 0
	for entry: Variant in spawns:
		total += _counted_count(entry)
	for key: Variant in _groups:
		for entry: Variant in _group_entries(str(key)):
			total += _counted_count(entry)
	if wave.has("boss"):
		total += 1
	_progress.reset(total)
	Events.wave_started.emit(index, _waves.size())
	Log.info("wave", "Level %d wave %d/%d started (%d counted)" % [_level_id, index + 1, _waves.size(), total])

	_in_step = true
	_fire_triggers(WHEN_WAVE_START, 0.0)
	var failures: int = 0
	for i: int in spawns.size():
		failures += _spawn_entry(spawns[i], "%s.spawns[%d]" % [path, i], _serial)
	if wave.has("boss"):
		failures += _spawn_boss(wave["boss"], path + ".boss")
	_spawn_asteroids(wave.get("asteroids", []), path + ".asteroids")
	_in_step = false
	if failures > 0:
		_subtract(failures)
	else:
		_check_stall()
		_try_clear()


## F3: skips every unspawned group, kills each live counted enemy through its
## death path (progress triggers fire in order), then resolves what is left.
## Refused once the attempt failed (DW-54).
func debug_resolve_wave() -> void:
	if _wave_index < 0 or _level_done:
		Log.info("debug", "F3: no wave running")
		return
	if _failed:
		Log.info("debug", "F3: attempt failed; nothing to resolve")
		return
	Log.info("debug", "F3: resolving level %d wave %d" % [_level_id, _wave_index + 1])
	var serial: int = _serial
	for key: Variant in _groups:
		var group_name: String = str(key)
		if not _spawned_groups.has(group_name) or _pending_groups.has(group_name):
			_spawned_groups[group_name] = true
			_skipped_groups[group_name] = true
	_pending_groups.clear()
	_free_boss()
	_debug_resolving = true
	for node: Node in get_tree().get_nodes_in_group(Groups.COUNTED):
		var enemy: Enemy = node as Enemy
		if enemy != null and not enemy.is_dead() and not enemy.is_queued_for_deletion():
			enemy.apply_damage(maxi(enemy.hp, 1), null)
	while serial == _serial and not _progress.is_complete():
		_progress.resolve()
		_on_progress_changed()
	_debug_resolving = false
	if serial == _serial:
		_try_clear()


## F6: jumps to the first boss wave through debug_jump_to_wave (current counted
## enemies, any live boss and its launched Wasps are freed without resolving,
## running chains are abandoned, and the boss wave starts with a fresh boss).
func debug_skip_to_boss() -> void:
	var boss_index: int = -1
	for i: int in _waves.size():
		if _waves[i] is Dictionary and (_waves[i] as Dictionary).has("boss"):
			boss_index = i
			break
	if boss_index < 0:
		Log.info("debug", "F6: no boss wave in level %d" % _level_id)
		return
	Log.info("debug", "F6: jumping to boss wave %d" % (boss_index + 1))
	debug_jump_to_wave(boss_index)


## Debug jump (F6 and the Story 8.3 level bench): starts wave `index` (0-based)
## at once. Current counted enemies, any live boss and its launched Wasps
## (Groups.BOSS_WASPS, Story 7.4) are freed without resolving, running chains
## are abandoned, and a failed or cleared attempt is live again. An index
## outside the level's waves logs a warning, frees nothing and returns false.
func debug_jump_to_wave(index: int) -> bool:
	if index < 0 or index >= _waves.size():
		Log.warn("debug", "Wave jump: level %d has no wave %d (it has %d)" % [_level_id, index + 1, _waves.size()])
		return false
	for node: Node in get_tree().get_nodes_in_group(Groups.COUNTED):
		node.remove_from_group(Groups.COUNTED)
		node.queue_free()
	for node: Node in get_tree().get_nodes_in_group(Groups.BOSS):
		node.remove_from_group(Groups.BOSS)
		node.queue_free()
	for node: Node in get_tree().get_nodes_in_group(Groups.BOSS_WASPS):
		node.remove_from_group(Groups.BOSS_WASPS)
		node.queue_free()
	_boss = null
	_boss_pending = false
	_level_done = false
	_failed = false
	start_wave(index)
	return true


## 1-based number of the current wave (0 before the level starts).
func wave_number() -> int:
	return _wave_index + 1


func wave_count() -> int:
	return _waves.size()


func resolved_count() -> int:
	return _progress.resolved


func total_count() -> int:
	return _progress.total_counted


func level_id() -> int:
	return _level_id


func running_chains() -> int:
	return _running_chains


func is_level_cleared() -> bool:
	return _level_done


# --- Spawning -----------------------------------------------------------------

## Spawns one spawn/group entry on the next free formation rows. Returns how
## many of its counted enemies failed to spawn (the caller subtracts them).
func _spawn_entry(entry: Variant, path: String, serial: int) -> int:
	if not (entry is Dictionary):
		Log.error("wave", "%s %s: not an object; skipped" % [_source, path])
		return 0
	var dict: Dictionary = entry
	var count: int = _entry_count(dict)
	var type_id: StringName = StringName(str(dict.get("type", "")))
	if not EntityRegistry.ENEMIES.has(type_id):
		Log.error("wave", "%s %s.type: unknown enemy type '%s'; %d not counted" % [_source, path, type_id, count])
		return count
	if count <= 0:
		return 0
	if _disabled_types.has(type_id):
		Log.debug("spawn", "%s %s: %d x %s skipped (flag '%s' off); not counted" % [_source, path, count, type_id, _disabled_types[type_id]])
		return 0
	var formation: String = str(dict.get("formation", "")) if dict.get("formation") is String else ""
	var entry_kind: StringName = StringName(str(dict.get("entry", DEFAULT_ENTRY)))
	var slots: Array[Vector2] = Formation.slots(formation, count, _next_row, _spacing, _top_y, _width)
	if not EntityRegistry.ROWLESS_TYPES.has(type_id):
		_next_row += Formation.rows_used(formation, count, _spacing, _width)
	var failures: int = 0
	for slot: Vector2 in slots:
		var enemy: Enemy = null
		if spawner != null:
			enemy = spawner.spawn_enemy(type_id, {
				"position": slot,
				"slot": slot,
				"formation": formation,
				"entry": entry_kind,
				"row_shift_y": _row_shift_y,
			})
		if enemy == null:
			failures += 1
			continue
		enemy.add_to_group(Groups.COUNTED)
		enemy.resolved.connect(_on_enemy_resolved.bind(serial))
		_live_counted += 1
	Log.debug("spawn", "%s %s: %d x %s (%s)" % [_source, path, count - failures, type_id, formation])
	if failures > 0:
		Log.error("wave", "%s %s: %d %s failed to spawn; not counted" % [_source, path, failures, type_id])
	return failures


## Spawns the wave's boss `raw` (a type id in EntityRegistry.BOSSES) through
## the Spawner as one live counted unit, then its medium cover asteroids.
## Returns 1 when it failed (an unknown id or no spawner; logged, the caller
## subtracts it), else 0.
func _spawn_boss(raw: Variant, path: String) -> int:
	var type_id: StringName = StringName(str(raw))
	if spawner == null:
		Log.error("wave", "%s %s: boss '%s' has no spawner; not counted" % [_source, path, type_id])
		return 1
	if not EntityRegistry.BOSSES.has(type_id):
		Log.error("wave", "%s %s: unknown boss '%s'; not counted" % [_source, path, type_id])
		return 1
	var boss: Flagship = spawner.spawn_boss(type_id, {})
	if boss == null:
		Log.error("wave", "%s %s: boss '%s' failed to spawn; not counted" % [_source, path, type_id])
		return 1
	_boss = boss
	_boss_pending = true
	_live_counted += 1
	Log.info("wave", "Level %d wave %d: boss '%s' spawned" % [_level_id, _wave_index + 1, type_id])
	var cover: int = Config.int_("boss.phase1_medium_asteroids")
	if cover > 0:
		_spawn_asteroids([{"size": "medium", "count": float(cover)}], path + ".cover")
	return 0


## Frees the current boss without resolving it (F3) and drops it from the live
## count. Its wave progress is then resolved by F3 itself.
func _free_boss() -> void:
	if _boss != null and is_instance_valid(_boss):
		_boss.remove_from_group(Groups.BOSS)
		_boss.queue_free()
	_boss = null
	if _boss_pending:
		_boss_pending = false
		_live_counted = maxi(_live_counted - 1, 0)


## Asteroids spawn at the top edge at a random x and are never counted.
func _spawn_asteroids(raw: Variant, path: String) -> void:
	if not (raw is Array):
		return
	var entries: Array = raw
	for i: int in entries.size():
		var entry_path: String = "%s[%d]" % [path, i]
		if not (entries[i] is Dictionary):
			Log.error("wave", "%s %s: not an object; skipped" % [_source, entry_path])
			continue
		var dict: Dictionary = entries[i]
		var size: StringName = StringName(str(dict.get("size", "")))
		if not Asteroid.SIZES.has(size):
			Log.error("wave", "%s %s.size: unknown asteroid size '%s'; skipped" % [_source, entry_path, size])
			continue
		if spawner == null:
			continue
		var radius: float = Config.num("asteroids.%s.diameter_px" % size) / 2.0
		for n: int in _entry_count(dict):
			var x: float = rng.randf_range(radius, _width - radius)
			spawner.spawn_asteroid({"size": size, "position": Vector2(x, -radius)})


## Marks the group spawned at once and spawns it deferred: a resolve inside a
## physics callback may have triggered this, where adding areas is not allowed.
func _request_group(group_name: String) -> void:
	if not _groups.has(group_name):
		Log.error("beat", "%s waves[%d]: spawn_group names no group '%s'; ignored" % [_source, _wave_index, group_name])
		return
	if _skipped_groups.has(group_name):
		Log.debug("beat", "Group '%s' was skipped (F3 or stall net); not spawned" % group_name)
		return
	if _spawned_groups.has(group_name):
		Log.warn("beat", "%s waves[%d]: group '%s' already spawned; second request ignored" % [_source, _wave_index, group_name])
		return
	_spawned_groups[group_name] = true
	_pending_groups[group_name] = true
	_spawn_group.call_deferred(group_name, _serial)


func _spawn_group(group_name: String, serial: int) -> void:
	if serial != _serial or not _pending_groups.has(group_name):
		return  # Abandoned (F6) or cancelled (F3).
	_pending_groups.erase(group_name)
	var entries: Array = _group_entries(group_name)
	var failures: int = 0
	for i: int in entries.size():
		failures += _spawn_entry(entries[i], "waves[%d].groups.%s[%d]" % [_wave_index, group_name, i], serial)
	Log.info("wave", "Level %d wave %d: group '%s' spawned" % [_level_id, _wave_index + 1, group_name])
	if failures > 0:
		_subtract(failures)
	else:
		_check_stall()
		_try_clear()


# --- Progress, triggers and clear ---------------------------------------------

func _on_enemy_resolved(serial: int) -> void:
	if serial != _serial:
		return
	_live_counted = maxi(_live_counted - 1, 0)
	if _failed:
		return  # DW-54: a dead attempt's kills don't count.
	_progress.resolve()
	_on_progress_changed()


## The boss wave resolves only here (Story 7.3). Once: a second boss_defeated,
## one with no live boss, or one of a dead attempt (DW-54) changes nothing.
func _on_events_boss_defeated() -> void:
	if not _boss_pending:
		return
	_boss_pending = false
	_live_counted = maxi(_live_counted - 1, 0)
	if _failed:
		return  # DW-54: a dead attempt's progress is frozen.
	_progress.resolve()
	_on_progress_changed()


func _subtract(count: int) -> void:
	if _failed:
		return  # DW-54: a dead attempt's progress is frozen.
	_progress.remove_from_total(count)
	_on_progress_changed()


## The one step after every progress change: signal, progress triggers in
## array order, stall net, clear.
func _on_progress_changed() -> void:
	Events.wave_progress_changed.emit(_wave_index, _progress.ratio())
	var was_in_step: bool = _in_step
	_in_step = true
	_fire_triggers(WHEN_PROGRESS, _progress.ratio())
	_in_step = was_in_step
	if not _in_step:
		_check_stall()
		_try_clear()


func _fire_triggers(event: StringName, value: float) -> void:
	for trigger: BeatTrigger in _triggers:
		if trigger.should_fire(event, value, Config.flags):
			_run_chain(trigger)  # Not awaited: each chain runs on its own.


## Runs one trigger's actions in order. A chain of an older wave (F6) stops
## after its next await without touching the counters. Once the attempt failed
## (DW-78) the chain runs no further action: it stops before its next action or
## right after its current await, and still leaves the chain count.
func _run_chain(trigger: BeatTrigger) -> void:
	var serial: int = _serial
	trigger.has_fired = true
	_running_chains += 1
	Log.info("beat", "Level %d wave %d: %s trigger fired (%d actions)" % [_level_id, _wave_index + 1, trigger.when, trigger.actions.size()])
	var skipped: int = 0
	for i: int in trigger.actions.size():
		if _failed:
			skipped = trigger.actions.size() - i
			break
		var action: Dictionary = trigger.actions[i]
		if action.has("spawn_group"):
			_request_group(str(action["spawn_group"]))
		elif action.has("wait"):
			var wait_s: float = float(action["wait"]) if (action["wait"] is float or action["wait"] is int) else 0.0
			if wait_s > 0.0 and is_inside_tree():
				var timer: Timer = _start_wait_timer(wait_s)
				await timer.timeout
				timer.queue_free()
				if serial != _serial:
					return
		elif action.has("comms"):
			var id: StringName = StringName(str(action["comms"]))
			Log.info("beat", "Level %d wave %d: comms '%s'" % [_level_id, _wave_index + 1, id])
			var before: int = _request_sequence(id)
			while before >= 0 and _finished_count(id) == before:
				await _sequence_done
				if serial != _serial:
					return
				if _failed:
					break  # The loop top stops the chain.
		elif action.has("story_event"):
			var event_name: StringName = StringName(str(action["story_event"]))
			Log.info("beat", "Level %d wave %d: story event '%s'" % [_level_id, _wave_index + 1, event_name])
			Events.story_event_requested.emit(event_name)
		elif action.has("music"):
			Audio.apply_music_action(StringName(str(action["music"])))
		elif action.has("hint"):
			var hint_id: StringName = StringName(str(action["hint"]))
			Log.info("beat", "Level %d wave %d: hint '%s'" % [_level_id, _wave_index + 1, hint_id])
			Events.hint_requested.emit(hint_id)
		else:
			Log.warn("beat", "%s waves[%d]: unknown action %s; skipped" % [_source, _wave_index, action])
	if _failed:
		Log.info("beat", "Level %d wave %d: %s trigger chain stopped (attempt failed; %d actions skipped)" % [_level_id, _wave_index + 1, trigger.when, skipped])
	_running_chains -= 1
	if _running_chains == 0:
		chains_finished.emit()
	if not _in_step:
		_check_stall()
		_try_clear()


## Emits the request for comms sequence `id`. Returns the finished count taken
## before the request when the caller must wait (a story sequence), else -1
## (combat and unknown ids don't block; the channel finishes unknown ids).
## The count is taken first, so a finished emitted synchronously during the
## request still releases the caller.
func _request_sequence(id: StringName) -> int:
	var before: int = _finished_count(id)
	var story: bool = Config.dialogue_is_story(id)
	Events.comms_sequence_requested.emit(id)
	return before if story else -1


func _finished_count(id: StringName) -> int:
	return int(_finished_counts.get(id, 0))


## A one-shot pausable Timer child for a `wait` action or the wave-clear gap:
## freed with the director, so an abandoned chain or gap never resumes. The
## caller frees it after its timeout. `wait_s` must be > 0.
func _start_wait_timer(wait_s: float) -> Timer:
	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	timer.wait_time = wait_s
	add_child(timer)
	timer.start()
	return timer


## Stall net: no live counted enemy, no chain, no pending spawn, yet the wave
## isn't complete. The missing count can only be groups that never spawned.
func _check_stall() -> void:
	if _failed or _debug_resolving or _clearing or _level_done or _wave_index < 0:
		return
	if _live_counted > 0 or _running_chains > 0 or not _pending_groups.is_empty() or _progress.is_complete():
		return
	var missing: int = _progress.total_counted - _progress.resolved
	var names: Array[String] = []
	for key: Variant in _groups:
		var group_name: String = str(key)
		if not _spawned_groups.has(group_name):
			names.append(group_name)
			_spawned_groups[group_name] = true
			_skipped_groups[group_name] = true
	Log.error("wave", "%s waves[%d]: stalled with %d unresolved; group(s) never spawned: %s; subtracting them" % [
		_source, _wave_index, missing, ", ".join(names) if not names.is_empty() else "none",
	])
	_subtract(missing)


func _try_clear() -> void:
	if _failed or _clearing or _level_done or _wave_index < 0:
		return
	if not _progress.is_complete() or _running_chains > 0 or not _pending_groups.is_empty():
		return
	_clearing = true
	var serial: int = _serial
	var index: int = _wave_index
	Events.wave_cleared.emit(index)
	Log.info("wave", "Level %d wave %d cleared (%d resolved)" % [_level_id, index + 1, _progress.resolved])
	_fire_triggers(WHEN_WAVE_CLEAR, 0.0)
	var gap: Timer = _start_wait_timer(maxf(_gap_s, MIN_TIMER_S))
	await gap.timeout
	gap.queue_free()
	if serial != _serial or _failed:
		return
	while _running_chains > 0:
		await chains_finished
		if serial != _serial or _failed:
			return
	if index + 1 < _waves.size():
		start_wave(index + 1)
	else:
		_finish_level()


## Plays the outro like a comms action (also on a retry), then clears the
## level, unless the attempt failed or F6 / a new start_level moved on meanwhile.
func _finish_level() -> void:
	if _failed:
		return
	var serial: int = _serial
	if not _outro_sequence.is_empty():
		var id: StringName = StringName(_outro_sequence)
		Log.info("beat", "Level %d outro '%s'" % [_level_id, id])
		var before: int = _request_sequence(id)
		while before >= 0 and _finished_count(id) == before:
			await _sequence_done
			if serial != _serial or _failed:
				return
		if serial != _serial or _failed:
			return
	_level_done = true
	Events.level_cleared.emit(_level_id)
	Log.info("wave", "Level %d cleared" % _level_id)


# --- Data helpers -------------------------------------------------------------

## An entry's count as an int (JSON numbers are floats); 0 when missing or bad.
func _entry_count(entry: Variant) -> int:
	if not (entry is Dictionary):
		return 0
	var raw: Variant = (entry as Dictionary).get("count")
	if not (raw is float or raw is int):
		return 0
	return maxi(int(raw), 0)


## What an entry adds to the wave total: its count, or 0 when its type is
## disabled by a feature flag this wave.
func _counted_count(entry: Variant) -> int:
	if entry is Dictionary and _disabled_types.has(StringName(str((entry as Dictionary).get("type", "")))):
		return 0
	return _entry_count(entry)


func _group_entries(group_name: String) -> Array:
	var entries: Variant = _groups.get(group_name)
	return entries if entries is Array else []
