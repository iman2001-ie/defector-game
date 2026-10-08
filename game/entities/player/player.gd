class_name Player
extends Area2D
## Player ship: locked to the cursor with zero delay. The ship never rotates.
##
## Each physics tick the viewport mouse position is confined to the player zone
## (x 0..Playfield width, y player.bounds_y) and the ship is placed exactly on the
## confined point. Viewport coordinates are world coordinates here (1920x1080, the
## camera is centred with no zoom); the lock never reads get_global_mouse_position(),
## so the ShakeCamera offset can't feed back into the ship.
##
## Cursor warps: the Player makes every gameplay warp_mouse call, and only while
## PauseArbiter's mode is CONFINED_HIDDEN. When the cursor leaves the zone it is
## warped back onto the zone edge (so moving back responds at once), and on
## PauseArbiter.resumed it is warped onto the ship (so the ship never jumps).
## PauseArbiter alone sets mouse_mode and tree.paused.
##
## Weapons: the laser and missile live in the Weapons child (PlayerWeapons).
## Player drives it each physics tick and keeps set_spawner, step_fire and
## step_missile as one-line delegators.

## A mouse within this distance of its confined point is not warped: warp_mouse
## rounds to whole OS pixels, so under stretch the read-back can land a fraction of
## a viewport px past the edge and would otherwise warp on every tick.
const WARP_EPS_PX: float = 1.0

## Moves the OS cursor, in viewport coordinates. Defaults to the viewport's
## warp_mouse in _ready; tests inject a recorder.
var warp_mouse: Callable

var _bounds_min: Vector2
var _bounds_max: Vector2

@onready var _hurtbox: CollisionShape2D = $Hurtbox
@onready var _sprite: Sprite2D = $Sprite
@onready var _weapons: PlayerWeapons = $Weapons


func _ready() -> void:
	add_to_group(&"player")
	if not warp_mouse.is_valid():
		warp_mouse = get_viewport().warp_mouse
	_bounds_min = Vector2(0.0, Config.num("player.bounds_y.min"))
	_bounds_max = Vector2(Playfield.SIZE.x, Config.num("player.bounds_y.max"))

	var hurtbox_circle: CircleShape2D = _hurtbox.shape as CircleShape2D
	if hurtbox_circle != null:
		hurtbox_circle.radius = Config.num("player.hurtbox_diameter_px") / 2.0
	var placeholder: GradientTexture2D = _sprite.texture as GradientTexture2D
	if placeholder != null:
		var px: int = Config.int_("player.sprite_px")
		placeholder.width = px
		placeholder.height = px

	PauseArbiter.resumed.connect(_on_resumed)


func _physics_process(delta: float) -> void:
	step_lock(get_viewport().get_mouse_position())
	step_fire(Input.is_action_pressed(&"fire_laser"), delta)
	step_missile(Input.is_action_just_pressed(&"fire_missile"), delta)


## Injected by the scene root (safe before _ready). Without a spawner the ship does not fire.
func set_spawner(spawner: Spawner) -> void:
	(get_node(^"Weapons") as PlayerWeapons).set_spawner(spawner)


## One laser tick (see PlayerWeapons.step_fire).
func step_fire(held: bool, delta: float) -> void:
	_weapons.step_fire(held, delta)


## One missile tick; the missile flies straight up (see PlayerWeapons.step_missile).
func step_missile(pressed: bool, delta: float) -> void:
	_weapons.step_missile(pressed, delta)


## One lock tick: the ship sits exactly on the confined mouse point (viewport
## coordinates). A mouse more than WARP_EPS_PX outside the zone is warped back onto
## the zone edge, but only while the gameplay mode is CONFINED_HIDDEN.
func step_lock(mouse: Vector2) -> void:
	var confined: Vector2 = confine(mouse, _bounds_min, _bounds_max)
	var outside: bool = mouse.distance_squared_to(confined) > WARP_EPS_PX * WARP_EPS_PX
	if outside and PauseArbiter.current_mouse_mode() == Input.MOUSE_MODE_CONFINED_HIDDEN:
		warp_mouse.call(confined)
	global_position = confined


## Clamps the ship centre to x 0..Playfield width, y bounds_y.min..max.
func clamp_to_bounds(p: Vector2) -> Vector2:
	return confine(p, _bounds_min, _bounds_max)


## Pure clamp of a point into the rectangle bounds_min..bounds_max.
static func confine(mouse: Vector2, bounds_min: Vector2, bounds_max: Vector2) -> Vector2:
	return mouse.clamp(bounds_min, bounds_max)


## Resume from any pause: put the cursor back on the ship so the next lock tick
## reads the ship's own position and the ship does not jump.
func _on_resumed() -> void:
	if PauseArbiter.current_mouse_mode() == Input.MOUSE_MODE_CONFINED_HIDDEN:
		warp_mouse.call(global_position)
