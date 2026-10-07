# res://autoloads/events.gd
extends Node

# Player
signal hearts_changed(current: int, max_hearts: int)
signal player_hit(position: Vector2)
signal player_died
signal energy_changed(current: int, max_energy: int)
signal ability_denied(ability: StringName)          # &"shield" | &"barrage"
signal missile_cooldown_changed(ratio: float)        # 0 = ready, 1 = just fired

# Combat
signal enemy_killed(enemy_type: StringName, position: Vector2, by_ally: bool)
signal asteroid_destroyed(size: StringName, position: Vector2)

# Waves / level
signal level_started(level_id: int)
signal wave_started(wave_index: int, wave_count: int)
signal wave_progress_changed(wave_index: int, ratio: float)
signal wave_cleared(wave_index: int)
signal level_cleared(level_id: int)
signal level_failed(reason: StringName)              # &"hearts" | &"convoy"

# Escort / boss
signal convoy_hp_changed(current: int, max_hp: int)
signal boss_started
signal boss_hp_changed(current: int, max_hp: int, phase: int)
signal boss_phase_changed(phase: int)
signal boss_defeated

# Comms
signal comms_sequence_requested(sequence_id: StringName)
signal comms_sequence_finished(sequence_id: StringName)
signal final_choice_made(choice: StringName)         # &"surrender" | &"destroy"
signal story_event_requested(event_name: StringName) # e.g. &"tarek_fall"
