extends Node2D
## Debug sandbox (temporary main scene): fly the ship, fire the laser and shoot
## a respawning Wasp formation while random asteroids drift through.

# Debug-scene parameters, not GDD numbers (see Story 1.4 design notes).
const FORMATION_COLUMNS: int = 4
const FORMATION_ROWS: int = 2
const FORMATION_SPACING: Vector2 = Vector2(160, 120)
const FORMATION_TOP_Y: float = 160.0
const ASTEROID_INTERVAL_S: float = 3.0
## Absorbs float drift when summing 1/60 s ticks up to the interval.
const _TIMER_EPSILON: float = 0.0001

## Asteroid size and x position source; tests seed it.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _wasps_alive: int = 0
var _asteroid_elapsed: float = 0.0
var _playfield_width: float = 0.0

@onready var _player: Player = $World/Player
@onready var _spawner: Spawner = $Spawner


func _ready() -> void:
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	_player.set_spawner(_spawner)
	_playfield_width = float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	spawn_formation()
	Log.info("scene", "Sandbox ready")


func _physics_process(delta: float) -> void:
	step_asteroids(delta)


## The grid_4x2 slots: rows centred on the screen's x centre, starting at FORMATION_TOP_Y.
func formation_slots() -> Array[Vector2]:
	var slots: Array[Vector2] = []
	var centre_x: float = _playfield_width / 2.0
	for row: int in FORMATION_ROWS:
		for col: int in FORMATION_COLUMNS:
			var x: float = centre_x + (col - (FORMATION_COLUMNS - 1) / 2.0) * FORMATION_SPACING.x
			slots.append(Vector2(x, FORMATION_TOP_Y + row * FORMATION_SPACING.y))
	return slots


func spawn_formation() -> void:
	for slot: Vector2 in formation_slots():
		var wasp: Enemy = _spawner.spawn_enemy(&"wasp", {"position": slot})
		if wasp == null:
			continue
		wasp.resolved.connect(_on_wasp_resolved)
		_wasps_alive += 1


## Spawns one random asteroid every ASTEROID_INTERVAL_S (the first after one interval).
func step_asteroids(delta: float) -> void:
	_asteroid_elapsed += delta
	while _asteroid_elapsed >= ASTEROID_INTERVAL_S - _TIMER_EPSILON:
		_asteroid_elapsed -= ASTEROID_INTERVAL_S
		_spawn_random_asteroid()


func _spawn_random_asteroid() -> void:
	var size: StringName = Asteroid.SIZES[rng.randi_range(0, Asteroid.SIZES.size() - 1)]
	var radius: float = Config.num("asteroids.%s.diameter_px" % size) / 2.0
	var x: float = rng.randf_range(radius, _playfield_width - radius)
	_spawner.spawn_asteroid({"size": size, "position": Vector2(x, -radius)})


func _on_wasp_resolved() -> void:
	_wasps_alive -= 1
	if _wasps_alive == 0:
		# resolved can fire inside a physics callback, where adding areas is not allowed.
		spawn_formation.call_deferred()
