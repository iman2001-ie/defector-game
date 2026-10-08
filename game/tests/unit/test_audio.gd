extends GutTest
## Audio: bus layout, SFX pool (size, bus, steal oldest, reuse finished),
## unknown ids, pitch jitter and per-call volume and pitch.


## Frees every pool player (as if each finished) so tests start from a known state.
func _free_all_players() -> void:
	for player: AudioStreamPlayer in _pool():
		player.stop()
		player.finished.emit()


func _pool() -> Array[AudioStreamPlayer]:
	var out: Array[AudioStreamPlayer] = []
	for child: Node in Audio.get_children():
		if child is AudioStreamPlayer:
			out.append(child as AudioStreamPlayer)
	return out


func after_each() -> void:
	_free_all_players()


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
	for id: StringName in [&"laser_zap", &"missile_launch", &"explosion_small", &"explosion_medium", &"explosion_large", &"player_hit", &"player_death", &"energy_pickup", &"ability_denied", &"barrage_whoosh"]:
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
