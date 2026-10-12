extends Node
## Sound effects: two pools of non-positional AudioStreamPlayers on the SFX bus
## and an id -> stream registry. The comms_* ids (COMMS_SFX) play on a small
## reserved comms pool, every other id on the combat pool (DW-80). When every
## player of a pool is busy, that pool's oldest player is stolen; a pool never
## takes a player from the other, so a combat flood can't cut a comms_static.
##
## Music (Story 5.3): one `Music` AudioStreamPlayer on the Music bus and the
## `music_streams` id -> stream registry (empty until Story 8.1 adds tracks).
## apply_music_action() is the WaveDirector `music` action: `stop` fades out
## over audio.music_fade_out_s, any other id plays (or switches to) that track.
## A missing stream warns once per id, stops the current music at once and
## stays silent.

const DEFAULT_PITCH_JITTER: float = 0.05
const POOL_SIZE: int = 12
## The reserved comms pool (DW-80): comms cues are sequential by design, so the
## second player only covers a short cue overlapping a long one.
const COMMS_POOL_SIZE: int = 2
const SFX_BUS: StringName = &"SFX"
const MUSIC_BUS: StringName = &"Music"
const MUSIC_STOP: StringName = &"stop"
## The volume a fade-out tweens the music player down to before stopping it.
const MUSIC_SILENT_DB: float = -80.0
const SFX: Dictionary[StringName, AudioStream] = {
	&"laser_zap": preload("res://assets/audio/sfx/sfx_laser_zap.wav"),
	&"missile_launch": preload("res://assets/audio/sfx/sfx_missile_launch.wav"),
	&"explosion_small": preload("res://assets/audio/sfx/sfx_explosion_small.wav"),
	&"explosion_medium": preload("res://assets/audio/sfx/sfx_explosion_medium.wav"),
	&"explosion_large": preload("res://assets/audio/sfx/sfx_explosion_large.wav"),
	# Placeholder (Story 7.3): the boss_part tier plays the large explosion until
	# Epic 8 adds its own sound.
	&"explosion_boss_part": preload("res://assets/audio/sfx/sfx_explosion_large.wav"),
	# Placeholder (Story 7.5): the boss_death tier (the Flagship's death chain)
	# plays the large explosion until Epic 8 adds its own sound.
	&"explosion_boss_death": preload("res://assets/audio/sfx/sfx_explosion_large.wav"),
	&"player_hit": preload("res://assets/audio/sfx/sfx_player_hit.wav"),
	&"player_death": preload("res://assets/audio/sfx/sfx_player_death.wav"),
	&"energy_pickup": preload("res://assets/audio/sfx/sfx_energy_pickup.wav"),
	&"ability_denied": preload("res://assets/audio/sfx/sfx_ability_denied.wav"),
	&"barrage_whoosh": preload("res://assets/audio/sfx/sfx_barrage_whoosh.wav"),
	&"comms_open": preload("res://assets/audio/sfx/sfx_comms_open.wav"),
	&"comms_open_nobeep": preload("res://assets/audio/sfx/sfx_comms_open_nobeep.wav"),
	&"comms_static": preload("res://assets/audio/sfx/sfx_comms_static.wav"),
	&"comms_click": preload("res://assets/audio/sfx/sfx_comms_click.wav"),
	&"comms_handover": preload("res://assets/audio/sfx/sfx_comms_handover.wav"),
	&"maul_alarm": preload("res://assets/audio/sfx/sfx_maul_alarm.wav"),
}
## The ids that play on the comms pool; every other id plays on the combat pool.
const COMMS_SFX: Dictionary[StringName, bool] = {
	&"comms_open": true,
	&"comms_open_nobeep": true,
	&"comms_static": true,
	&"comms_click": true,
	&"comms_handover": true,
}

## The combat pool.
var _players: Array[AudioStreamPlayer] = []
var _in_use: Array[bool] = []
## Start order of each player; the lowest is the oldest.
var _serials: Array[int] = []
## The reserved comms pool (same layout as the combat pool).
var _comms_players: Array[AudioStreamPlayer] = []
var _comms_in_use: Array[bool] = []
var _comms_serials: Array[int] = []
## Shared by both pools: every play bumps it by exactly 1.
var _next_serial: int = 0
var _newest: AudioStreamPlayer = null
var _warned_ids: Dictionary[StringName, bool] = {}

## Music id -> stream. Empty until Story 8.1 adds tracks; tests insert streams.
var music_streams: Dictionary[StringName, AudioStream] = {}
var _music: AudioStreamPlayer
## The id playing now; &"" when silent or fading out.
var _music_id: StringName = &""
var _music_base_db: float = 0.0
var _music_tween: Tween
var _warned_music: Dictionary[StringName, bool] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i: int in POOL_SIZE:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Sfx%d" % i
		player.bus = SFX_BUS
		player.finished.connect(_on_player_finished.bind(i))
		add_child(player)
		_players.append(player)
		_in_use.append(false)
		_serials.append(-1)
	for i: int in COMMS_POOL_SIZE:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Comms%d" % i
		player.bus = SFX_BUS
		player.finished.connect(_on_comms_player_finished.bind(i))
		add_child(player)
		_comms_players.append(player)
		_comms_in_use.append(false)
		_comms_serials.append(-1)
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.bus = MUSIC_BUS
	add_child(_music)
	_music_base_db = _music.volume_db


## Plays a registered SFX. pitch_scale = pitch * (1 + random in +-pitch_jitter).
## comms_* ids (COMMS_SFX) play on the comms pool, every other id on the combat
## pool. Returns the player used, or null for an unknown id (warned once per id).
func play_sfx(id: StringName, pitch_jitter: float = DEFAULT_PITCH_JITTER, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	var stream: AudioStream = SFX.get(id) as AudioStream
	if stream == null:
		if not _warned_ids.has(id):
			_warned_ids[id] = true
			Log.warn("audio", "unknown sfx id '%s'" % id)
		return null
	var comms: bool = COMMS_SFX.has(id)
	var players: Array[AudioStreamPlayer] = _comms_players if comms else _players
	var in_use: Array[bool] = _comms_in_use if comms else _in_use
	var serials: Array[int] = _comms_serials if comms else _serials
	if players.is_empty():
		return null
	var index: int = _pick_player(players, in_use, serials)
	var player: AudioStreamPlayer = players[index]
	if player.playing:
		player.stop()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	in_use[index] = true
	serials[index] = _next_serial
	_next_serial += 1
	_newest = player
	player.play()
	return player


## The most recently started player of either pool (tests), or null before the
## first play.
func newest_player() -> AudioStreamPlayer:
	return _newest


## The reserved comms pool's players (tests).
func comms_players() -> Array[AudioStreamPlayer]:
	return _comms_players.duplicate()


## The pool's first free player, else its one with the oldest start serial.
func _pick_player(players: Array[AudioStreamPlayer], in_use: Array[bool], serials: Array[int]) -> int:
	var oldest: int = 0
	for i: int in players.size():
		if not in_use[i]:
			return i
		if serials[i] < serials[oldest]:
			oldest = i
	return oldest


func _on_player_finished(index: int) -> void:
	_in_use[index] = false


func _on_comms_player_finished(index: int) -> void:
	_comms_in_use[index] = false


# --- Music ----------------------------------------------------------------------

## The WaveDirector `music` action: &"stop" fades the music out, any other value
## plays that track.
func apply_music_action(action: StringName) -> void:
	if action == MUSIC_STOP:
		stop_music()
	else:
		play_music(action)


## Plays music `id` (switching from any current track at once). Does nothing when
## `id` already plays. A missing stream warns once per id, stops the current
## music at once and leaves it silent.
func play_music(id: StringName) -> void:
	if id == _music_id and not _is_fading():
		return
	var stream: AudioStream = music_streams.get(id) as AudioStream
	if stream == null:
		if not _warned_music.has(id):
			_warned_music[id] = true
			Log.warn("audio", "no music stream for '%s'; music stays silent" % id)
		_kill_music_fade()
		_music.stop()
		_music.volume_db = _music_base_db
		_music_id = &""
		return
	_kill_music_fade()
	_music.volume_db = _music_base_db
	_music.stream = stream
	_music.play()
	_music_id = id
	Log.info("audio", "Music '%s' playing" % id)


## Fades the music out over `fade_s` seconds (a negative value uses
## audio.music_fade_out_s), then stops it and restores the base volume. A fade
## of 0 stops at once; with nothing playing it only clears the current id.
## current_music() is &"" from this call on.
func stop_music(fade_s: float = -1.0) -> void:
	var fade: float = fade_s if fade_s >= 0.0 else Config.num("audio.music_fade_out_s")
	var was: StringName = _music_id
	_music_id = &""
	if was.is_empty():
		if fade <= 0.0 and _is_fading():
			_kill_music_fade()
			_end_music_fade()
		return
	_kill_music_fade()
	Log.info("audio", "Music '%s' stopping (%.2f s fade)" % [was, maxf(fade, 0.0)])
	if fade <= 0.0:
		_end_music_fade()
		return
	_music_tween = create_tween()
	_music_tween.set_ignore_time_scale(true)  # A hit-stop never freezes the fade.
	_music_tween.tween_property(_music, "volume_db", MUSIC_SILENT_DB, fade)
	_music_tween.tween_callback(_end_music_fade)


## The music id playing now (&"" when silent or fading out).
func current_music() -> StringName:
	return _music_id


## The music player (tests).
func music_player() -> AudioStreamPlayer:
	return _music


func _is_fading() -> bool:
	return _music_tween != null and _music_tween.is_valid() and _music_tween.is_running()


func _kill_music_fade() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = null


func _end_music_fade() -> void:
	_music_tween = null
	_music.stop()
	_music.volume_db = _music_base_db
