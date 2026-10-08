extends Node2D
## Debug sandbox (temporary main scene): fly the ship, fire the laser and shoot
## a respawning Wasp formation while random asteroids drift through.
## Stress mode (debug builds, `-- --stress` or `-- --bench=<s>`) replaces the
## formation with a 40-Wasp grid that refills each slot as its Wasp dies, and
## keeps about tuning.debug.stress.projectiles live projectiles topped up (the
## NFR1 peak: 40 enemies + 200 projectiles + particles). `-- --no-prewarm`
## (debug builds) skips Feedback.prewarm().

# Debug-scene parameters, not GDD numbers (see Story 1.4 design notes).
const FORMATION_COLUMNS: int = 4
const FORMATION_ROWS: int = 2
const FORMATION_SPACING: Vector2 = Vector2(160, 120)
const FORMATION_TOP_Y: float = 160.0
const ASTEROID_INTERVAL_S: float = 3.0
# Stress grid (NFR1 stress count 10 x 4 = 40), inside the enemy zone y 120-432.
const STRESS_COLUMNS: int = 10
const STRESS_ROWS: int = 4
const STRESS_SPACING: Vector2 = Vector2(160, 72)
const STRESS_TOP_Y: float = 150.0
## Stress projectiles start one grid row below the bottom Wasp row and fly down,
## standing in for enemy bullets (laser_bolt masks enemies, so they miss the grid).
const STRESS_PROJECTILE_Y: float = STRESS_TOP_Y + STRESS_ROWS * STRESS_SPACING.y
## Absorbs float drift when summing 1/60 s ticks up to the interval.
const _TIMER_EPSILON: float = 0.0001

## Asteroid size and x position source; tests seed it.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## True from _ready when a debug build gets `--stress` or `--bench=<s>` in
## user_args; tests may also set it directly before add_child.
var stress_mode: bool = false
## The user args _ready parses (`--stress`, `--bench=<s>`, `--no-prewarm`).
## Tests override this before add_child.
var user_args: PackedStringArray = OS.get_cmdline_user_args()

var _wasps_alive: int = 0
var _asteroid_elapsed: float = 0.0
var _playfield_width: float = 0.0
var _stress_projectile_target: int = 0
var _stress_projectile_per_tick: int = 0
var _stress_projectile_velocity: Vector2 = Vector2.ZERO
var _stress_projectile_damage: int = 0

@onready var _player: Player = $World/Player
@onready var _spawner: Spawner = $Spawner


func _ready() -> void:
	PauseArbiter.set_gameplay_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	_player.set_spawner(_spawner)
	RenderGlow.apply(($WorldEnvironment as WorldEnvironment).environment)
	_playfield_width = Playfield.SIZE.x
	var args: Dictionary = DebugArgs.parse(user_args)
	if OS.is_debug_build() and args.stress:
		stress_mode = true
	if stress_mode:
		_stress_projectile_target = Config.int_("debug.stress.projectiles")
		_stress_projectile_per_tick = Config.int_("debug.stress.projectile_spawn_per_tick")
		_stress_projectile_velocity = Vector2(0.0, Config.num("weapons.enemy_bullet.max_speed_px_s"))
		_stress_projectile_damage = Config.int_("weapons.laser.damage")
		spawn_stress_grid()
		Log.info("scene", "Sandbox stress mode: %d Wasps, %d projectiles" % [STRESS_COLUMNS * STRESS_ROWS, _stress_projectile_target])
	else:
		spawn_formation()
	Log.info("scene", "Sandbox ready")
	# One explosion per tier off-screen, so the first real impact doesn't hitch.
	# Debug builds can skip it (`--no-prewarm`) to measure the un-warmed cost.
	if should_prewarm(OS.is_debug_build(), args):
		Feedback.prewarm()
	else:
		Log.info("scene", "Feedback pre-warm skipped (--no-prewarm)")


## Pre-warm unless a debug build was given `--no-prewarm` (release builds always pre-warm).
static func should_prewarm(debug_build: bool, args: Dictionary) -> bool:
	return not debug_build or args.prewarm


func _physics_process(delta: float) -> void:
	step_asteroids(delta)
	if stress_mode:
		step_stress_projectiles()


## Stress mode: spawns min(target - live, per-tick cap) projectiles below the grid,
## flying down. Live projectiles (the player's bolts too) are counted by group.
func step_stress_projectiles() -> void:
	var missing: int = _stress_projectile_target - get_tree().get_node_count_in_group(&"projectiles")
	for i: int in mini(missing, _stress_projectile_per_tick):
		var x: float = rng.randf_range(0.0, _playfield_width)
		_spawner.spawn_projectile(&"laser_bolt", {
			"position": Vector2(x, STRESS_PROJECTILE_Y),
			"velocity": _stress_projectile_velocity,
			"damage": _stress_projectile_damage,
		})


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


## The stress grid slots: STRESS_COLUMNS x STRESS_ROWS centred on x, from STRESS_TOP_Y.
func stress_slots() -> Array[Vector2]:
	var slots: Array[Vector2] = []
	var centre_x: float = _playfield_width / 2.0
	for row: int in STRESS_ROWS:
		for col: int in STRESS_COLUMNS:
			var x: float = centre_x + (col - (STRESS_COLUMNS - 1) / 2.0) * STRESS_SPACING.x
			slots.append(Vector2(x, STRESS_TOP_Y + row * STRESS_SPACING.y))
	return slots


func spawn_stress_grid() -> void:
	for slot: Vector2 in stress_slots():
		_spawn_stress_wasp(slot)


func _spawn_stress_wasp(slot: Vector2) -> void:
	var wasp: Enemy = _spawner.spawn_enemy(&"wasp", {"position": slot})
	if wasp == null:
		return
	wasp.resolved.connect(_on_stress_wasp_resolved.bind(slot))


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


func _on_stress_wasp_resolved(slot: Vector2) -> void:
	# resolved can fire inside a physics callback, where adding areas is not allowed.
	_spawn_stress_wasp.call_deferred(slot)
