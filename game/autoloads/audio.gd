extends Node
## Sound effects: a pool of non-positional AudioStreamPlayers on the SFX bus and
## an id -> stream registry. When every player is busy the oldest one is stolen.
## Music arrives in a later epic.

const DEFAULT_PITCH_JITTER: float = 0.05
const POOL_SIZE: int = 12
const SFX_BUS: StringName = &"SFX"
const SFX: Dictionary[StringName, AudioStream] = {
	&"laser_zap": preload("res://assets/audio/sfx/sfx_laser_zap.wav"),
	&"missile_launch": preload("res://assets/audio/sfx/sfx_missile_launch.wav"),
	&"explosion_small": preload("res://assets/audio/sfx/sfx_explosion_small.wav"),
	&"explosion_medium": preload("res://assets/audio/sfx/sfx_explosion_medium.wav"),
	&"explosion_large": preload("res://assets/audio/sfx/sfx_explosion_large.wav"),
	&"player_hit": preload("res://assets/audio/sfx/sfx_player_hit.wav"),
	&"player_death": preload("res://assets/audio/sfx/sfx_player_death.wav"),
}

var _players: Array[AudioStreamPlayer] = []
var _in_use: Array[bool] = []
## Start order of each player; the lowest is the oldest.
var _serials: Array[int] = []
var _next_serial: int = 0
var _newest: AudioStreamPlayer = null
var _warned_ids: Dictionary[StringName, bool] = {}


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


## Plays a registered SFX. pitch_scale = pitch * (1 + random in +-pitch_jitter).
## Returns the player used, or null for an unknown id (warned once per id).
func play_sfx(id: StringName, pitch_jitter: float = DEFAULT_PITCH_JITTER, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	var stream: AudioStream = SFX.get(id) as AudioStream
	if stream == null:
		if not _warned_ids.has(id):
			_warned_ids[id] = true
			Log.warn("audio", "unknown sfx id '%s'" % id)
		return null
	if _players.is_empty():
		return null
	var index: int = _pick_player()
	var player: AudioStreamPlayer = _players[index]
	if player.playing:
		player.stop()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	_in_use[index] = true
	_serials[index] = _next_serial
	_next_serial += 1
	_newest = player
	player.play()
	return player


## The most recently started player (tests), or null before the first play.
func newest_player() -> AudioStreamPlayer:
	return _newest


## The first free player, else the one with the oldest start serial.
func _pick_player() -> int:
	var oldest: int = 0
	for i: int in _players.size():
		if not _in_use[i]:
			return i
		if _serials[i] < _serials[oldest]:
			oldest = i
	return oldest


func _on_player_finished(index: int) -> void:
	_in_use[index] = false
