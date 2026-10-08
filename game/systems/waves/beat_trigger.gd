class_name BeatTrigger
extends RefCounted
## One data-authored beat trigger from a level wave's `triggers` array. Pure
## logic, no nodes: it stores the condition and the actions, and answers
## should_fire(). The WaveDirector runs the actions and sets has_fired.
##
## `when` is one of wave_start | progress (`at`, 0-1) | wave_clear |
## boss_phase (`phase`) | boss_hp_le (`hp`, absolute hit points, not a 0-1
## fraction). An unknown `when` never fires.
## `flag` is optional; a leading "!" negates it, and a missing or non-bool flag
## counts as false.

const NEGATE_PREFIX: String = "!"

var when: StringName = &""
var at: float = 0.0
var phase: int = 0
var hp: float = 0.0
var flag: String = ""
var actions: Array[Dictionary] = []
var has_fired: bool = false


## Builds the trigger from a JSON-shaped dictionary. JSON numbers arrive as
## floats, so `phase` goes through int(). Non-Dictionary actions are dropped;
## the rest keep their order. Missing optional keys keep their defaults.
func _init(data: Dictionary) -> void:
	when = StringName(str(data.get("when", "")))
	at = float(data.get("at", 0.0))
	phase = int(data.get("phase", 0))
	hp = float(data.get("hp", 0.0))
	flag = str(data.get("flag", ""))
	var raw_actions: Variant = data.get("actions", [])
	if raw_actions is Array:
		for action: Variant in raw_actions:
			if action is Dictionary:
				actions.append(action)


## Pure query: true when this trigger should fire for `event`. It never sets
## has_fired (the Director does that when it runs the actions).
##
## `value` is the event's number: the wave ratio for `progress`, the new phase
## for `boss_phase`, the boss's current absolute hit points (not a fraction)
## for `boss_hp_le`. The Director passes 0.0 for
## `wave_start` and `wave_clear`. `flags` is the raw flags dictionary
## (Config.flags).
func should_fire(event: StringName, value: float, flags: Dictionary) -> bool:
	if has_fired or event != when or not _flag_passes(flags):
		return false
	match when:
		&"wave_start", &"wave_clear":
			return true
		&"progress":
			return value >= at
		&"boss_phase":
			return int(value) == phase
		&"boss_hp_le":
			return value <= hp
	return false


func _flag_passes(flags: Dictionary) -> bool:
	if flag.is_empty():
		return true
	var negated: bool = flag.begins_with(NEGATE_PREFIX)
	var flag_name: String = flag.substr(NEGATE_PREFIX.length()) if negated else flag
	var raw: Variant = flags.get(flag_name, false)
	var is_set: bool = raw is bool and raw
	return not is_set if negated else is_set
