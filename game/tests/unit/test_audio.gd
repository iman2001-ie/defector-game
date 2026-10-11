extends GutTest
## Audio: bus layout, SFX pool (size, bus, steal oldest, reuse finished),
## unknown ids, pitch jitter and per-call volume and pitch. Story 5.3: the
## Music player, play / switch / fade-stop and the missing-stream warning.
## DW-80: the reserved comms pool (comms_* ids only; combat SFX never steal it).

const UnscaledClock := preload("res://tests/fixtures/unscaled_clock.gd")

var _lines: Array[String] = []


## Frees every player of both pools (as if each finished) so tests start from a
## known state.
func _free_all_players() -> void:
	var all: Array[AudioStreamPlayer] = _pool()
	all.append_array(Audio.comms_players())
	for player: AudioStreamPlayer in all:
		player.stop()
		player.finished.emit()


## The combat SFX pool (every AudioStreamPlayer child except the Music player
## and the comms players).
func _pool() -> Array[AudioStreamPlayer]:
	var comms: Array[AudioStreamPlayer] = Audio.comms_players()
	var out: Array[AudioStreamPlayer] = []
	for child: Node in Audio.get_children():
		if child is AudioStreamPlayer and child != Audio.music_player() and not comms.has(child):
			out.append(child as AudioStreamPlayer)
	return out


func before_each() -> void:
	_lines.clear()


func after_each() -> void:
	_free_all_players()
	Log.sink = Callable()
	Audio.stop_music(0.0)
	Audio.music_streams.clear()
	Audio._warned_music.clear()


func _capture(level: String, category: String, msg: String) -> void:
	_lines.append(Log.format(level, category, msg))


func _lines_containing(text: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _lines:
		if line.contains(text):
			out.append(line)
	return out


## A short silent 16-bit mono WAV, so the music tests need no asset.
func _stream() -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var data: PackedByteArray = PackedByteArray()
	data.resize(22050 * 2)
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = 22050
	return wav


func _register_music() -> Dictionary:
	var streams: Dictionary = {&"combat": _stream(), &"boss": _stream()}
	for id: StringName in streams:
		Audio.music_streams[id] = streams[id]
	return streams


func test_buses_send_to_master() -> void:
	for bus: String in ["Music", "SFX", "UI"]:
		var index: int = AudioServer.get_bus_index(bus)
		assert_gt(index, 0, "bus %s exists" % bus)
		if index > 0:
			assert_eq(AudioServer.get_bus_send(index), &"Master", "%s sends to Master" % bus)


func test_pool_of_twelve_on_sfx_bus() -> void:
	var pool: Array[AudioStreamPlayer] = _pool()
	assert_eq(Audio.POOL_SIZE, 12)
	assert_eq(pool.size(), 12)
	for player: AudioStreamPlayer in pool:
		assert_eq(player.bus, &"SFX")


func test_process_mode_always() -> void:
	assert_eq(Audio.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_registry_streams() -> void:
	for id: StringName in [&"laser_zap", &"missile_launch", &"explosion_small", &"explosion_medium", &"explosion_large", &"player_hit", &"player_death", &"energy_pickup", &"ability_denied", &"barrage_whoosh", &"comms_open", &"comms_open_nobeep", &"comms_static", &"comms_click", &"comms_handover", &"maul_alarm"]:
		assert_true(Audio.SFX.get(id) is AudioStream, "sfx %s" % id)


func test_steal_oldest_when_full() -> void:
	_free_all_players()
	var pool: Array[AudioStreamPlayer] = _pool()
	var used: Array[AudioStreamPlayer] = []
	for i: int in 12:
		used.append(Audio.play_sfx(&"laser_zap"))
	assert_eq(used, pool, "fills the pool in order")
	assert_eq(Audio.play_sfx(&"laser_zap"), pool[0], "13th steals the 1st")
	assert_eq(Audio.play_sfx(&"laser_zap"), pool[1], "14th steals the 2nd")
	assert_eq(Audio.newest_player(), pool[1])


func test_finished_player_is_reused() -> void:
	_free_all_players()
	var pool: Array[AudioStreamPlayer] = _pool()
	for i: int in 12:
		Audio.play_sfx(&"laser_zap")
	pool[5].finished.emit()
	assert_eq(Audio.play_sfx(&"explosion_small"), pool[5])
	assert_eq(pool[5].stream, Audio.SFX[&"explosion_small"])


func test_unknown_id_warns_once() -> void:
	assert_null(Audio.play_sfx(&"nope_test_audio"))
	assert_null(Audio.play_sfx(&"nope_test_audio"))
	assert_push_warning_count(1)


func test_volume_and_pitch_applied() -> void:
	var player: AudioStreamPlayer = Audio.play_sfx(&"explosion_large", 0.0, -3.0, 0.8)
	assert_not_null(player)
	if player != null:
		assert_eq(player.stream, Audio.SFX[&"explosion_large"])
		assert_almost_eq(player.volume_db, -3.0, 0.0001)
		assert_almost_eq(player.pitch_scale, 0.8, 0.0001)
		assert_eq(Audio.newest_player(), player)


func test_pitch_jitter_range() -> void:
	var pitches: Dictionary[float, bool] = {}
	for i: int in 50:
		var player: AudioStreamPlayer = Audio.play_sfx(&"laser_zap", 0.05)
		assert_between(player.pitch_scale, 0.95, 1.05)
		pitches[player.pitch_scale] = true
	assert_gt(pitches.size(), 1, "not all pitches equal")


# --- Comms pool (DW-80) ----------------------------------------------------------

const COMMS_IDS: Array[StringName] = [&"comms_open", &"comms_open_nobeep", &"comms_static", &"comms_click", &"comms_handover"]


func test_comms_pool_of_two_on_sfx_bus() -> void:
	var comms: Array[AudioStreamPlayer] = Audio.comms_players()
	assert_eq(Audio.COMMS_POOL_SIZE, 2)
	assert_eq(comms.size(), 2)
	for i: int in comms.size():
		assert_eq(comms[i].bus, &"SFX")
		assert_eq(comms[i].name, StringName("Comms%d" % i))
		assert_eq(comms[i].get_parent(), Audio)
	for player: AudioStreamPlayer in _pool():
		assert_false(comms.has(player), "the pools are distinct")


func test_comms_sfx_matches_the_comms_ids_in_the_registry() -> void:
	for id: StringName in Audio.SFX:
		if String(id).begins_with("comms_"):
			assert_true(Audio.COMMS_SFX.has(id), "registry id %s is in COMMS_SFX" % id)
	for id: StringName in Audio.COMMS_SFX:
		assert_true(String(id).begins_with("comms_"), "COMMS_SFX id %s is a comms_ id" % id)
		assert_true(Audio.SFX.has(id), "COMMS_SFX id %s is registered" % id)
	for id: StringName in COMMS_IDS:
		assert_true(Audio.COMMS_SFX.has(id), "%s is in COMMS_SFX" % id)


func test_every_comms_id_routes_to_the_comms_pool() -> void:
	var comms: Array[AudioStreamPlayer] = Audio.comms_players()
	for id: StringName in Audio.COMMS_SFX:
		_free_all_players()
		var player: AudioStreamPlayer = Audio.play_sfx(id)
		assert_true(comms.has(player), "%s plays on a comms player" % id)
		assert_eq(Audio.newest_player(), player, "newest spans the comms pool")
	_free_all_players()
	assert_false(comms.has(Audio.play_sfx(&"laser_zap")), "a combat id never uses the comms pool")


func test_combat_flood_never_steals_the_static() -> void:
	_free_all_players()
	var comms: Array[AudioStreamPlayer] = Audio.comms_players()
	var static_player: AudioStreamPlayer = Audio.play_sfx(&"comms_static", 0.0)
	assert_true(comms.has(static_player))
	for i: int in 20:
		var player: AudioStreamPlayer = Audio.play_sfx(&"laser_zap")
		assert_false(comms.has(player), "laser %d is a combat player" % i)
	assert_true(static_player.playing, "the static keeps playing")
	assert_eq(static_player.stream, Audio.SFX[&"comms_static"], "the static keeps its stream")


func test_comms_pool_steals_its_own_oldest() -> void:
	_free_all_players()
	var comms: Array[AudioStreamPlayer] = Audio.comms_players()
	var pool: Array[AudioStreamPlayer] = _pool()
	for i: int in 12:
		Audio.play_sfx(&"laser_zap")
	assert_eq(Audio.play_sfx(&"comms_static"), comms[0])
	assert_eq(Audio.play_sfx(&"comms_click"), comms[1])
	assert_eq(Audio.play_sfx(&"comms_handover"), comms[0], "3rd comms cue steals the oldest comms player")
	assert_eq(comms[0].stream, Audio.SFX[&"comms_handover"])
	assert_eq(comms[1].stream, Audio.SFX[&"comms_click"], "the newer comms cue is kept")
	for player: AudioStreamPlayer in pool:
		assert_eq(player.stream, Audio.SFX[&"laser_zap"], "no combat player taken")
		assert_true(player.playing, "the combat player keeps playing")


func test_finished_comms_player_is_reused() -> void:
	_free_all_players()
	var comms: Array[AudioStreamPlayer] = Audio.comms_players()
	assert_eq(Audio.play_sfx(&"comms_static"), comms[0])
	assert_eq(Audio.play_sfx(&"comms_click"), comms[1])
	comms[1].finished.emit()
	assert_eq(Audio.play_sfx(&"comms_handover"), comms[1], "the finished comms player is reused")
	assert_eq(comms[0].stream, Audio.SFX[&"comms_static"], "the static keeps its player")
	assert_true(comms[0].playing, "the static keeps playing")


func test_every_play_bumps_the_serial_once() -> void:
	var before: int = Audio._next_serial
	Audio.play_sfx(&"laser_zap")
	Audio.play_sfx(&"comms_click")
	assert_eq(Audio._next_serial, before + 2, "one per play, either pool")


# --- Music (Story 5.3) ------------------------------------------------------------

func test_music_player_on_the_music_bus() -> void:
	var player: AudioStreamPlayer = Audio.music_player()
	assert_not_null(player)
	if player == null:
		return
	assert_eq(player.name, &"Music")
	assert_eq(player.bus, &"Music")
	assert_eq(player.get_parent(), Audio)
	assert_eq(Audio.music_streams.size(), 0, "no tracks until Story 8.1")
	assert_eq(Audio.current_music(), &"", "silent at start")


func test_play_switch_and_same_id() -> void:
	Log.sink = _capture
	var streams: Dictionary = _register_music()
	var player: AudioStreamPlayer = Audio.music_player()
	Audio.apply_music_action(&"combat")
	assert_eq(Audio.current_music(), &"combat")
	assert_eq(player.stream, streams[&"combat"])
	assert_almost_eq(player.volume_db, 0.0, 0.0001, "base volume")
	Audio.play_music(&"combat")
	assert_eq(_lines_containing("[INFO][audio] Music 'combat' playing").size(), 1, "the same id does nothing")
	Audio.apply_music_action(&"boss")
	assert_eq(Audio.current_music(), &"boss", "switched")
	assert_eq(player.stream, streams[&"boss"])
	assert_eq(_lines_containing("[INFO][audio] Music 'boss' playing").size(), 1)


func test_stop_fades_over_the_tuning_time_then_stops() -> void:
	assert_true(await UnscaledClock.settle(self), "unscaled clock settled")
	_register_music()
	var player: AudioStreamPlayer = Audio.music_player()
	assert_eq(Config.num("audio.music_fade_out_s"), 0.5)
	Audio.apply_music_action(&"combat")
	Audio.apply_music_action(&"stop")
	assert_eq(Audio.current_music(), &"", "silent from the call on")
	await wait_seconds(0.25)
	assert_lt(player.volume_db, -1.0, "fading down")
	assert_gt(player.volume_db, -80.0, "not yet at the end of the 0.5 s fade")
	assert_eq(player.stream, Audio.music_streams[&"combat"], "still the faded track")
	await wait_seconds(0.4)
	assert_false(player.playing, "stopped after the fade")
	assert_almost_eq(player.volume_db, 0.0, 0.0001, "base volume restored")
	assert_eq(Audio.current_music(), &"")


func test_play_during_a_fade_restores_the_volume() -> void:
	assert_true(await UnscaledClock.settle(self), "unscaled clock settled")
	_register_music()
	var player: AudioStreamPlayer = Audio.music_player()
	Audio.play_music(&"combat")
	Audio.stop_music()
	await wait_seconds(0.2)
	assert_lt(player.volume_db, -1.0, "fading")
	Audio.play_music(&"combat")
	assert_eq(Audio.current_music(), &"combat", "plays again during the fade")
	assert_almost_eq(player.volume_db, 0.0, 0.0001, "fade killed, base volume")
	await wait_seconds(0.5)
	assert_almost_eq(player.volume_db, 0.0, 0.0001, "the old fade never ends it")
	assert_eq(Audio.current_music(), &"combat")


func test_zero_fade_stop_during_a_fade_stops_at_once() -> void:
	assert_true(await UnscaledClock.settle(self), "unscaled clock settled")
	_register_music()
	var player: AudioStreamPlayer = Audio.music_player()
	Audio.play_music(&"combat")
	Audio.stop_music()
	await wait_seconds(0.2)
	assert_lt(player.volume_db, -1.0, "fading")
	Audio.stop_music(0.0)
	assert_false(player.playing, "stopped at once")
	assert_almost_eq(player.volume_db, 0.0, 0.0001, "base volume")
	assert_eq(Audio.current_music(), &"")


func test_stop_with_zero_fade_or_nothing_playing() -> void:
	_register_music()
	var player: AudioStreamPlayer = Audio.music_player()
	Audio.play_music(&"combat")
	Audio.stop_music(0.0)
	assert_false(player.playing, "stopped at once")
	assert_almost_eq(player.volume_db, 0.0, 0.0001)
	assert_eq(Audio.current_music(), &"")
	Audio.stop_music()
	assert_eq(Audio.current_music(), &"", "nothing playing: only clears the id")
	assert_almost_eq(player.volume_db, 0.0, 0.0001)


func test_missing_stream_warns_once_and_stays_silent() -> void:
	Log.sink = _capture
	Audio.music_streams[&"combat"] = _stream()
	var player: AudioStreamPlayer = Audio.music_player()
	Audio.apply_music_action(&"combat")
	Audio.apply_music_action(&"boss")
	assert_eq(Audio.current_music(), &"", "stays silent")
	assert_false(player.playing, "the combat track stopped at once")
	assert_almost_eq(player.volume_db, 0.0, 0.0001)
	assert_eq(_lines_containing("[WARN][audio]").size(), 1, "one warning")
	Audio.apply_music_action(&"boss")
	assert_eq(_lines_containing("[WARN][audio]").size(), 1, "no new warning for the same id")
	assert_eq(Audio.current_music(), &"")
	assert_push_warning_count(1)
