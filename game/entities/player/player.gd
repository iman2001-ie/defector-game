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
##
## Hearts and i-frames (Story 3.1): `hearts` starts at player.hearts and only
## goes down within an attempt. apply_damage(amount, source) costs hearts, emits
## Events.hearts_changed and Events.player_hit, plays the PLAYER_HIT feedback and
## starts player.iframes_s of i-frames. Damage while invulnerable (i-frames or
## debug_invincible) is ignored entirely. I-frame time accumulates from physics
## delta in step_iframes, so it freezes under pause and hit-stop; meanwhile only
## the Sprite flickers at player.iframe_flicker_hz.
##
## Death (Story 3.2): the hit that brings hearts to 0 still emits hearts_changed
## and player_hit, then plays the PLAYER_DEATH feedback (instead of PLAYER_HIT)
## and emits Events.player_died then Events.level_failed(&"hearts"), once. The
## dead ship is hidden (the MissileRing with it), has no i-frames, switches its
## collision off, forgets its contacts and ignores damage and contact; its
## physics tick does nothing (no lock, fire or missile). Retry reloads the scene
## (ADR-004), so nothing here is ever reset.
##
## Contact: the Player watches its own area_entered/area_exited. A small or
## medium Enemy costs damage.contact_<tier>_hearts and is destroyed by contact,
## even while invulnerable; a large Enemy (Bastion) costs contact_large_hearts
## and survives; an Asteroid costs contact_<size>_hearts and is never destroyed.
## Hazards that survive are remembered while they overlap; when the i-frames end
## (or debug_invincible turns off) one still-overlapping hazard hits again.

## A mouse within this distance of its confined point is not warped: warp_mouse
## rounds to whole OS pixels, so under stretch the read-back can land a fraction of
## a viewport px past the edge and would otherwise warp on every tick.
const WARP_EPS_PX: float = 1.0

## Moves the OS cursor, in viewport coordinates. Defaults to the viewport's
## warp_mouse in _ready; tests inject a recorder.
var warp_mouse: Callable

## Hearts left in this attempt (0..max_hearts).
var hearts: int = 0
## Hearts at the start of an attempt (player.hearts).
var max_hearts: int = 0
## Debug-only invincibility (F2). Turning it off re-applies overlapping hazards.
var debug_invincible: bool = false:
	set(value):
		if debug_invincible == value:
			return
		debug_invincible = value
		if not value:
			_recheck_contacts()

var _bounds_min: Vector2
var _bounds_max: Vector2

var _iframes_s: float = 0.0
var _flicker_hz: float = 0.0
var _iframe_active: bool = false
var _iframe_elapsed: float = 0.0
var _contact_small: int = 0
var _contact_medium: int = 0
var _contact_large: int = 0
## Surviving hazards (large enemies, asteroids) the hurtbox overlaps right now.
var _contacts: Array[Area2D] = []
var _dead: bool = false

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

	max_hearts = Config.int_("player.hearts")
	hearts = max_hearts
	_iframes_s = maxf(Config.num("player.iframes_s"), 0.0)
	_flicker_hz = maxf(Config.num("player.iframe_flicker_hz"), 0.0)
	_contact_small = Config.int_("damage.contact_small_hearts")
	_contact_medium = Config.int_("damage.contact_medium_hearts")
	_contact_large = Config.int_("damage.contact_large_hearts")

	PauseArbiter.resumed.connect(_on_resumed)
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	# The HUD's _ready runs after World/Player's, so the first value goes out deferred.
	_emit_hearts.call_deferred()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	step_lock(get_viewport().get_mouse_position())
	step_fire(Input.is_action_pressed(&"fire_laser"), delta)
	step_missile(Input.is_action_just_pressed(&"fire_missile"), delta)
	step_iframes(delta)


# --- Hearts and i-frames ----------------------------------------------------------

## True during i-frames or while debug_invincible is on.
func is_invulnerable() -> bool:
	return _iframe_active or debug_invincible


## True once hearts reached 0 in this attempt.
func is_dead() -> bool:
	return _dead


## Costs `amount` hearts (floored at 0) and starts the i-frames; the hit that
## reaches 0 kills the ship instead. Ignored when amount <= 0, while
## invulnerable, at 0 hearts or once dead.
func apply_damage(amount: int, _source: Node) -> void:
	if _dead or amount <= 0 or is_invulnerable() or hearts <= 0:
		return
	hearts = maxi(hearts - amount, 0)
	Events.hearts_changed.emit(hearts, max_hearts)
	Events.player_hit.emit(global_position)
	if hearts == 0:
		_die()
		return
	Feedback.impact(ImpactTier.PLAYER_HIT, global_position)
	_start_iframes()


## The lethal hit: PLAYER_DEATH feedback, the ship goes hidden and inert, then
## player_died and level_failed(&"hearts"). Runs once (apply_damage guards it).
func _die() -> void:
	_dead = true
	_iframe_active = false
	_sprite.visible = true
	visible = false
	set_deferred(&"monitoring", false)
	set_deferred(&"monitorable", false)
	_contacts.clear()
	Feedback.impact(ImpactTier.PLAYER_DEATH, global_position)
	Log.info("combat", "Player destroyed: hearts reached 0")
	Events.player_died.emit()
	Events.level_failed.emit(&"hearts")


## One i-frame tick: advances the window by `delta`, flickers the sprite and,
## on the tick the window ends, re-applies a hazard that still overlaps.
func step_iframes(delta: float) -> void:
	if not _iframe_active:
		return
	_iframe_elapsed += delta
	if _iframe_elapsed >= _iframes_s:
		_iframe_active = false
		_sprite.visible = true
		_recheck_contacts()
		return
	_sprite.visible = fmod(_iframe_elapsed * _flicker_hz, 1.0) < 0.5


func _start_iframes() -> void:
	_iframe_active = _iframes_s > 0.0
	_iframe_elapsed = 0.0
	_sprite.visible = true


func _emit_hearts() -> void:
	Events.hearts_changed.emit(hearts, max_hearts)


# --- Contact ----------------------------------------------------------------------

## Contact with `area`: enemies and asteroids cost hearts by tier or size; small
## and medium enemies are then destroyed (even while invulnerable). Other areas
## (pickups) and dead enemies are ignored. Surviving hazards are remembered.
func on_contact(area: Area2D) -> void:
	if _dead:
		return
	var enemy: Enemy = area as Enemy
	if enemy != null:
		if enemy.is_dead():
			return
		var destroyed: bool = enemy.tier == ImpactTier.SMALL or enemy.tier == ImpactTier.MEDIUM
		apply_damage(_enemy_contact_cost(enemy.tier), enemy)
		if destroyed:
			enemy.destroy_by_contact()
		elif not _dead:
			_remember(area)
		return
	var rock: Asteroid = area as Asteroid
	if rock != null:
		if rock.is_queued_for_deletion():
			return
		apply_damage(_asteroid_contact_cost(rock.size), rock)
		if not _dead:
			_remember(area)


func _enemy_contact_cost(tier: int) -> int:
	if tier == ImpactTier.SMALL:
		return _contact_small
	if tier == ImpactTier.MEDIUM:
		return _contact_medium
	return _contact_large


func _asteroid_contact_cost(rock_size: StringName) -> int:
	if rock_size == &"large":
		return _contact_large
	if rock_size == &"medium":
		return _contact_medium
	return _contact_small


func _remember(area: Area2D) -> void:
	if not _contacts.has(area):
		_contacts.append(area)


## Drops freed, dying or dead hazards, then (when vulnerable) lets the newest
## remaining one hit again; on_contact restarts the i-frames, so one hit per expiry.
func _recheck_contacts() -> void:
	if _dead:
		_contacts.clear()
		return
	var i: int = _contacts.size() - 1
	while i >= 0:
		if not _is_live_hazard(_contacts[i]):
			_contacts.remove_at(i)
		i -= 1
	if _contacts.is_empty() or is_invulnerable() or hearts <= 0:
		return
	on_contact(_contacts[_contacts.size() - 1])


## Untyped on purpose: a typed parameter rejects a previously freed instance.
func _is_live_hazard(area: Variant) -> bool:
	if not is_instance_valid(area):
		return false
	var node: Area2D = area as Area2D
	if node == null or node.is_queued_for_deletion() or not node.is_inside_tree():
		return false
	var enemy: Enemy = node as Enemy
	return enemy == null or not enemy.is_dead()


func _on_area_entered(area: Area2D) -> void:
	on_contact(area)


func _on_area_exited(area: Area2D) -> void:
	_contacts.erase(area)


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
