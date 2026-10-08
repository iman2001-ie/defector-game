class_name WaveDirector
extends Node
## Runs a level's scripted waves from data (architecture Novel Pattern #1).
##
## The only node that decides what spawns and when; the Spawner does the
## instantiating. Per wave: build the BeatTriggers, count the total up front
## (spawns + every group entry, a boss = 1), emit wave_started, run the
## wave_start triggers, spawn the entries in stacked formation rows, subtract
## what failed to spawn, then spawn the (never counted) asteroids.
##
## After every progress change (a resolve or a subtraction): emit
## wave_progress_changed, fire progress triggers in array order, then try to
## clear. A wave clears when every counted enemy resolved and no action chain
## or group spawn is pending; then wave_clear triggers, a waves.gap_s gap, the
## running chains finish, and the next wave starts (or the level clears).
## A stall net subtracts groups that can never spawn, so no wave soft-locks.
## Once Events.level_failed fires (the player died) the attempt is dead: no
## wave or level clears until start_level / debug_skip_to_boss (retro F1).
##
## Formation rows: each entry starts on the next free row, except the
## EntityRegistry.ROWLESS_TYPES (the Hunter Wasp), which don't advance the row:
## it never holds its slot (a sides entry only starts at the slot's y, so it may
## share a row with the next entry). The Needle takes a row: it anchors on and
## roams it.
##
## Feature-flag gate: a type listed in EntityRegistry.ENEMY_FLAGS whose flag is
## false at wave start is disabled for that wave. Its spawn and group entries
## count 0 toward the total, take no formation rows and spawn nothing. One DEBUG
## line is logged when such an entry would spawn (a group entry only if its group
## is requested; a never-requested group logs nothing). They are a designer
## choice, not an error, so never subtracted.

## Emitted when the last running action chain finishes.
signal chains_finished

const WHEN_WAVE_START: StringName = &"wave_start"
const WHEN_PROGRESS: StringName = &"progress"
const WHEN_WAVE_CLEAR: StringName = &"wave_clear"
const DEFAULT_ENTRY: String = "top"

@export var spawner: Spawner

## Asteroid x positions; tests seed it.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _source: String = ""
var _level_id: int = 0
var _waves: Array = []
var _outro_sequence: String = ""
var _wave_index: int = -1
## Bumped by every start_wave: resolves, chains and spawns of an older wave are ignored.
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
var _running_chains: int = 0
var _clearing: bool = false
var _level_done: bool = false
## Set by Events.level_failed: a dead attempt never clears a wave or the level.
var _failed: bool = false
## True while a step runs triggers: chain ends then leave stall/clear checks to the step.
var _in_step: bool = false
var _debug_resolving: bool = false

var _gap_s: float = 0.0
var _spacing: Vector2 = Vector2.ZERO
var _top_y: float = 0.0
var _width: float = 0.0


func _ready() -> void:
	add_to_group(Groups.WAVE_DIRECTOR)
	Events.level_failed.connect(_on_events_level_failed)


func _on_events_level_failed(_reason: StringName) -> void:
	_failed = true


## Starts the level at wave 1. `source` (the file path) prefixes every data error.
func start_level(data: Dictionary, source: String) -> void:
	_source = source
	_gap_s = Config.num("waves.gap_s")
	_spacing = Vector2(Config.num("waves.formation.spacing_px.x"), Config.num("waves.formation.spacing_px.y"))
	_top_y = Config.num("waves.formation.top_y")
	_width = Playfield.SIZE.x
	_level_id = int(data.get("id", 0)) if (data.get("id") is float or data.get("id") is int) else 0
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
		Log.error("wave", "%s %s.boss: boss '%s' does not exist yet (Epic 7); not counted" % [_source, path, str(wave["boss"])])
		failures += 1
	_spawn_asteroids(wave.get("asteroids", []), path + ".asteroids")
	_in_step = false
	if failures > 0:
		_subtract(failures)
	else:
		_check_stall()
		_try_clear()


## F3: skips every unspawned group, kills each live counted enemy through its
## death path (progress triggers fire in order), then resolves what is left.
func debug_resolve_wave() -> void:
	if _wave_index < 0 or _level_done:
		Log.info("debug", "F3: no wave running")
		return
	Log.info("debug", "F3: resolving level %d wave %d" % [_level_id, _wave_index + 1])
	var serial: int = _serial
	for key: Variant in _groups:
		var group_name: String = str(key)
		if not _spawned_groups.has(group_name) or _pending_groups.has(group_name):
			_spawned_groups[group_name] = true
			_skipped_groups[group_name] = true
	_pending_groups.clear()
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


## F6: jumps to the first boss wave. Current counted enemies are freed without
## resolving and running chains are abandoned.
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
	for node: Node in get_tree().get_nodes_in_group(Groups.COUNTED):
		node.remove_from_group(Groups.COUNTED)
		node.queue_free()
	_level_done = false
	_failed = false
	start_wave(boss_index)


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
	_progress.resolve()
	_on_progress_changed()


func _subtract(count: int) -> void:
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
## after its next await without touching the counters.
func _run_chain(trigger: BeatTrigger) -> void:
	var serial: int = _serial
	trigger.has_fired = true
	_running_chains += 1
	Log.info("beat", "Level %d wave %d: %s trigger fired (%d actions)" % [_level_id, _wave_index + 1, trigger.when, trigger.actions.size()])
	for action: Dictionary in trigger.actions:
		if action.has("spawn_group"):
			_request_group(str(action["spawn_group"]))
		elif action.has("wait"):
			var wait_s: float = float(action["wait"]) if (action["wait"] is float or action["wait"] is int) else 0.0
			await get_tree().create_timer(wait_s, false).timeout
			if serial != _serial:
				return
		elif action.has("comms") or action.has("story_event") or action.has("music"):
			Log.debug("beat", "Action %s skipped: arrives in Epic 5" % [action])
		else:
			Log.warn("beat", "%s waves[%d]: unknown action %s; skipped" % [_source, _wave_index, action])
	_running_chains -= 1
	if _running_chains == 0:
		chains_finished.emit()
	if not _in_step:
		_check_stall()
		_try_clear()


## Stall net: no live counted enemy, no chain, no pending spawn, yet the wave
## isn't complete. The missing count can only be groups that never spawned.
func _check_stall() -> void:
	if _debug_resolving or _clearing or _level_done or _wave_index < 0:
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
	await get_tree().create_timer(_gap_s, false).timeout
	if serial != _serial or _failed:
		return
	while _running_chains > 0:
		await chains_finished
		if serial != _serial:
			return
	if index + 1 < _waves.size():
		start_wave(index + 1)
	else:
		_finish_level()


func _finish_level() -> void:
	if _failed:
		return
	_level_done = true
	if not _outro_sequence.is_empty():
		Log.debug("beat", "outro_sequence '%s' skipped: arrives in Epic 5" % _outro_sequence)
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
