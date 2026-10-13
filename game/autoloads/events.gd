# res://autoloads/events.gd
extends Node

# Player
signal hearts_changed(current: int, max_hearts: int)
signal player_hit(position: Vector2)
signal player_died
signal energy_changed(current: int, max_energy: int)
signal ability_denied(ability: StringName)          # &"shield" | &"barrage"
signal missile_cooldown_changed(ratio: float)        # 0 = ready, 1 = just fired
## Story 5.8: the ship moved `distance_px` this physics tick (only when it moved).
signal player_moved(distance_px: float)
## Story 5.8: the player performed an action: a laser bolt, a missile launch, the
## shield raised or a barrage started. Denied abilities and micro-missiles never emit.
signal player_action(action: StringName)            # &"laser" | &"missile" | &"shield" | &"barrage"

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
## Epic 7 playtest C: CommsChannel showed a line, in `mode` &"story" (the panel)
## or &"combat" (the box). A cut-off line carries the text as shown (cut to
## cut_off_at plus comms.cutoff_suffix). The PauseMenu keeps the combat ones.
signal comms_line_shown(speaker: StringName, text: String, mode: StringName)
signal final_choice_made(choice: StringName)         # &"surrender" | &"destroy"
signal story_event_requested(event_name: StringName) # e.g. &"tarek_fall"
## Story 5.8: a WaveDirector `hint` action asks the HUD HintPill for control hints.
signal hint_requested(hint_id: StringName)           # &"move_fire" | &"missile"
