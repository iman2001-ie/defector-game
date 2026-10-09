extends GutTest
## Audio: bus layout, SFX pool (size, bus, steal oldest, reuse finished),
## unknown ids, pitch jitter and per-call volume and pitch. Story 5.3: the
## Music player, play / switch / fade-stop and the missing-stream warning.

const UnscaledClock := preload("res://tests/fixtures/unscaled_clock.gd")

var _lines: Array[String] = []


## Frees every pool player (as if each finished) so tests start from a known state.
func _free_all_players() -> void:
	for player: AudioStreamPlayer in _pool():
		player.stop()
		player.finished.emit()


## The SFX pool (every AudioStreamPlayer child except the Music player).
func _pool() -> Array[AudioStreamPlayer]:
	var out: Array[AudioStreamPlayer] = []
	for child: Node in Audio.get_children():
		if child is AudioStreamPlayer and child != Audio.music_player():
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
	for id: StringName in [&"laser_zap", &"missile_launch", &"explosion_small", &"explosion_medium", &"explosion_large", &"player_hit", &"player_death", &"energy_pickup", &"ability_denied", &"barrage_whoosh", &"comms_open", &"comms_static", &"comms_click", &"comms_handover"]:
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
