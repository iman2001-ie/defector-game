class_name Player
extends Area2D
## Player ship: locked to the cursor with zero delay. The ship never rotates.
##
## Hull (Story 4.0): the Sprite is the coalition-recoloured Kenney fighter
## (assets/sprites/player/playerShip1_coalition.png, nose toward -y, baked by
## tools/recolor_player_ship.py, modulate left at 1.0). _ready scales it
## uniformly so its longer side equals player.sprite_px, keeps it centred on the
## ship and moves the Muzzle onto the nose tip (0, -drawn height / 2). The
## hurtbox stays the player.hurtbox_diameter_px circle at the centre.
##
## Each physics tick the viewport mouse position is confined to the player zone
## (x 0..Playfield width, y player.bounds_y) and the ship is placed exactly on the
## confined point. Viewport coordinates are world coordinates here (1920x1080, the
## camera is centred with no zoom); the lock never reads get_global_mouse_position(),
## so the ShakeCamera offset can't feed back into the ship.
##
## Cursor warps: the Player makes every gameplay warp_mouse call, and only while
## PauseArbiter's mode is CONFINED_HIDDEN. When the cursor leaves the zone, or a
## convoy hull blocks or pushes the ship, it is warped onto the ship (so moving
## back responds at once), and on
## PauseArbiter.resumed it is warped onto the ship (so the ship never jumps).
## PauseArbiter alone sets mouse_mode and tree.paused.
##
## Weapons: the laser and missile live in the Weapons child (PlayerWeapons).
## Player drives it each physics tick and keeps set_spawner, step_fire and
## step_missile as one-line delegators.
##
## Hearts and i-frames (Story 3.1) live in the Health child (HealthComponent);
## `hearts` / `max_hearts` forward to it. apply_damage(amount, source) costs
## hearts unless invulnerable (i-frames, shield or debug_invincible); on Health's
## `damaged` the Player emits Events.hearts_changed and Events.player_hit and
## plays the PLAYER_HIT feedback, then Health starts player.iframes_s of
## i-frames. step_iframes ticks them from physics delta (frozen under pause and
## hit-stop); only the Sprite flickers, at player.iframe_flicker_hz.
##
## Death (Story 3.2): the hit that brings hearts to 0 still emits hearts_changed
## and player_hit, then plays the PLAYER_DEATH feedback (instead of PLAYER_HIT)
## and emits Events.player_died then Events.level_failed(&"hearts"), once. The
## dead ship is hidden (the MissileRing with it), has no i-frames, switches its
## collision off, forgets its contacts and ignores damage and contact; its
## physics tick does nothing (no lock, fire or missile). Retry reloads the scene
## (ADR-004), so nothing here is ever reset.
##
## Level clear (DW-54, decision #39): the first outcome wins. On
## Events.level_cleared the ship turns safe for the rest of the scene (is_safe()):
## apply_damage and hazard contact are ignored (no hearts, no events, a small or
## medium enemy is not destroyed, nothing is remembered) and the remembered
## contacts are dropped, so it can never die or emit level_failed. It stays
## visible and alive, still fires and still collects energy orbs. This is not
## is_invulnerable() (that destroys small/medium enemies on contact). Never
## reset: retry and the next level reload the scene (ADR-004).
##
## Contact: the Player watches its own area_entered/area_exited. A small or
## medium Enemy costs damage.contact_<tier>_hearts and is destroyed by contact,
## even while invulnerable; a large Enemy (Bastion) costs contact_large_hearts
## and survives; an Asteroid costs contact_<size>_hearts and is never destroyed.
## Hazards that survive are remembered while they overlap; when the i-frames end
## (or debug_invincible turns off) one still-overlapping hazard hits again.
## An EnergyOrb (Story 3.3) is collected on contact (EnergyOrb.collect), even
## while invulnerable, at no heart cost, and is never remembered.
##
## Shield (Story 3.4) and barrage (Story 3.5): the `ability_shield` (E) and
## `ability_barrage` (Q) actions call try_shield() / try_barrage(). Both go
## through one spend gate (_spend): dead or already running is a silent false;
## too little energy is denied (Events.ability_denied + the `ability_denied`
## SFX); else the cost is spent through GameState.add_energy. The shield state
## lives in the Shield child (PlayerShield, drawn by the ShieldBubble child), is
## never stacked or refreshed and is part of is_invulnerable() (small and medium
## enemies are still destroyed by contact); when it ends a still-overlapping
## hazard hits again, as with i-frames. The volley runs in PlayerWeapons, is
## never restarted, and death stops it (no more launches, no finish).
##
## Control-hint events (Story 5.8): step_lock emits Events.player_moved(distance)
## whenever the confined position differs from the ship's previous one (no
## allocation), except on the first lock tick, which only snaps the freshly
## spawned ship onto the cursor. A raised shield or a started barrage emits
## Events.player_action(&"shield" / &"barrage"); a denied or busy ability emits
## nothing. PlayerWeapons emits &"laser" / &"missile".
##
## Convoy hulls (Story 6.1, GDD #25, #29): the HullArea child (layer 0, mask
## convoy) holds the player.hull_diameter_px circle; the 24 px hurtbox and the
## root mask are unchanged, so convoy contact never costs a heart. With a live
## convoy injected through set_convoy, step_lock sweeps the move from the
## previous position to the confined cursor point against the convoy's cached
## hitbox rects (resolve_hull: sub-steps of at most radius / 2, pushed out of
## every rect after each, so the ship stops on the side it came from and slides
## along a hull), then confines it to the zone; a squeeze against the screen
## edge is pushed out along y. The first lock tick only snaps and pushes out.
## The cursor is then warped onto the final position whenever the mouse is more
## than WARP_EPS_PX from it (this also covers the zone-edge warp).

## A mouse within this distance of its confined point is not warped: warp_mouse
## rounds to whole OS pixels, so under stretch the read-back can land a fraction of
## a viewport px past the edge and would otherwise warp on every tick.
const WARP_EPS_PX: float = 1.0
## Overlap tolerance for the hull push-out: a circle resting exactly on a hull
## (or within float error of it) is not overlapping.
const HULL_EPS_PX: float = 0.01

## Moves the OS cursor, in viewport coordinates. Defaults to the viewport's
## warp_mouse in _ready; tests inject a recorder.
var warp_mouse: Callable

## Hearts left in this attempt (0..max_hearts); forwards to the Health child
## (0 before _ready).
var hearts: int:
	get:
		return _health.current if _health != null else 0
	set(value):
		if _health != null:
			_health.current = value
## Hearts at the start of an attempt (player.hearts); forwards to Health.
var max_hearts: int:
	get:
		return _health.max_value if _health != null else 0
	set(value):
		if _health != null:
			_health.max_value = value
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

var _contact_small: int = 0
var _contact_medium: int = 0
var _contact_large: int = 0
## Surviving hazards (large enemies, asteroids) the hurtbox overlaps right now.
var _contacts: Array[Area2D] = []
var _dead: bool = false
## Set by Events.level_cleared, never reset: no damage or hazard contact (DW-54).
var _safe: bool = false

var _barrage_cost: int = 0
## False until the first lock tick (that tick snaps the spawned ship onto the
## cursor and is not player movement).
var _locked_once: bool = false
## The level's convoy (set_convoy); null without one.
var _convoy: Convoy = null
## HullArea circle radius (player.hull_diameter_px / 2).
var _hull_radius: float = 0.0

@onready var _hurtbox: CollisionShape2D = $Hurtbox
@onready var _sprite: Sprite2D = $Sprite
@onready var _muzzle: Marker2D = $Muzzle
@onready var _weapons: PlayerWeapons = $Weapons
@onready var _health: HealthComponent = $Health
@onready var _shield: PlayerShield = $Shield
@onready var _hull_area: Area2D = $HullArea


func _ready() -> void:
	add_to_group(Groups.PLAYER)
	if not warp_mouse.is_valid():
		warp_mouse = get_viewport().warp_mouse
	_bounds_min = Vector2(0.0, Config.num("player.bounds_y.min"))
	_bounds_max = Vector2(Playfield.SIZE.x, Config.num("player.bounds_y.max"))

	var hurtbox_circle: CircleShape2D = _hurtbox.shape as CircleShape2D
	if hurtbox_circle != null:
		hurtbox_circle.radius = Config.num("player.hurtbox_diameter_px") / 2.0
	_fit_hull(Config.num("player.sprite_px"))
	_hull_radius = maxf(Config.num("player.hull_diameter_px") / 2.0, 0.0)
	var hull_shape: CollisionShape2D = _hull_area.get_node_or_null(^"HullShape") as CollisionShape2D
	if hull_shape != null and hull_shape.shape is CircleShape2D:
		(hull_shape.shape as CircleShape2D).radius = _hull_radius

	_health.setup(Config.int_("player.hearts"), Config.num("player.iframes_s"),
			Config.num("player.iframe_flicker_hz"), _sprite)
	_contact_small = Config.int_("damage.contact_small_hearts")
	_contact_medium = Config.int_("damage.contact_medium_hearts")
	_contact_large = Config.int_("damage.contact_large_hearts")
	_barrage_cost = maxi(Config.int_("abilities.barrage.cost"), 0)

	_health.damaged.connect(_on_damaged)
	_health.died.connect(_die)
	_health.iframes_ended.connect(_recheck_contacts)
	_shield.ended.connect(_recheck_contacts)
	PauseArbiter.resumed.connect(_on_resumed)
	Events.level_cleared.connect(_on_level_cleared)
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
	step_shield(delta)
	if Input.is_action_just_pressed(&"ability_shield"):
		try_shield()
	step_barrage(delta)
	if Input.is_action_just_pressed(&"ability_barrage"):
		try_barrage()


## Scales the hull uniformly so its longer side is `px`, centred on the ship, and
## puts the Muzzle on the nose tip (top centre of the drawn hull). A missing
## texture or px <= 0 warns and leaves the scale and the Muzzle as they are.
func _fit_hull(px: float) -> void:
	var tex: Texture2D = _sprite.texture
	if tex == null or px <= 0.0:
		Log.warn("data", "Player hull not sized: texture %s, player.sprite_px %s"
				% ["missing" if tex == null else "ok", px])
		return
	var longest: float = maxf(tex.get_width(), tex.get_height())
	if longest <= 0.0:
		Log.warn("data", "Player hull not sized: empty texture")
		return
	_sprite.scale = Vector2.ONE * (px / longest)
	_muzzle.position = Vector2(0.0, -(tex.get_height() * _sprite.scale.y) / 2.0)


# --- Hearts and i-frames ----------------------------------------------------------

## True during i-frames, while the shield is up or while debug_invincible is on.
func is_invulnerable() -> bool:
	return _health.is_iframing() or _shield.is_active() or debug_invincible


## True once hearts reached 0 in this attempt.
func is_dead() -> bool:
	return _dead


## True once the level cleared: damage and hazard contact are ignored (DW-54).
func is_safe() -> bool:
	return _safe


## Events.level_cleared: the ship turns safe for the rest of the scene. A ship
## that already died stays dead (the first outcome won).
func _on_level_cleared(_level_id: int) -> void:
	if _dead:
		return
	_safe = true
	_contacts.clear()


## Costs `amount` hearts (floored at 0) and starts the i-frames; the hit that
## reaches 0 kills the ship instead. Ignored when amount <= 0, while
## invulnerable, at 0 hearts, once dead or once safe (level cleared).
func apply_damage(amount: int, _source: Node) -> void:
	if _dead or _safe or is_invulnerable():
		return
	_health.take(amount)


## Health's `damaged`: the hit events, then PLAYER_HIT unless the hit was lethal.
## Health then emits `died` (-> _die) or starts the i-frames.
func _on_damaged(current: int, max_value: int) -> void:
	Events.hearts_changed.emit(current, max_value)
	Events.player_hit.emit(global_position)
	if current > 0:
		Feedback.impact(ImpactTier.PLAYER_HIT, global_position)


## The lethal hit: PLAYER_DEATH feedback, the ship goes hidden and inert, then
## player_died and level_failed(&"hearts"). Runs once, on Health's `died` (take
## ignores an owner at 0 hearts; apply_damage ignores a dead ship).
func _die() -> void:
	_dead = true
	_health.stop_iframes()
	_shield.drop()
	_weapons.stop_barrage()
	visible = false
	set_deferred(&"monitoring", false)
	set_deferred(&"monitorable", false)
	_contacts.clear()
	Feedback.impact(ImpactTier.PLAYER_DEATH, global_position)
	Log.info("combat", "Player destroyed: hearts reached 0")
	Events.player_died.emit()
	Events.level_failed.emit(&"hearts")


## One i-frame tick (see HealthComponent.step); on the tick the window ends, a
## hazard that still overlaps hits again.
func step_iframes(delta: float) -> void:
	_health.step(delta)


func _emit_hearts() -> void:
	Events.hearts_changed.emit(hearts, max_hearts)


# --- Shield -----------------------------------------------------------------------

## True while the shield is up.
func is_shielded() -> bool:
	return _shield.is_active()


## Seconds of shield left (0 when down).
func shield_remaining() -> float:
	return _shield.remaining()


## Raises the shield if the ship is alive, unshielded and can pay
## abilities.shield.cost; returns true when it went up. An active shield is left
## untouched (no spend, no denial). Too little energy is denied (see _deny).
func try_shield() -> bool:
	var line: String = "Shield up: -%d energy, %.1f s" % [_shield.cost, _shield.duration_s]
	if not _spend(&"shield", _shield.is_active(), _shield.cost, line):
		return false
	_shield.raise()
	Events.player_action.emit(&"shield")
	return true


## One shield tick (see PlayerShield.step); on the tick it runs out, a hazard
## that still overlaps hits again.
func step_shield(delta: float) -> void:
	_shield.step(delta)


# --- Barrage ----------------------------------------------------------------------

## True while a barrage volley is still launching.
func is_barraging() -> bool:
	return _weapons.is_barraging()


## Starts a barrage if the ship is alive, no volley is running and it can pay
## abilities.barrage.cost; returns true when it started. A running volley is
## left untouched (no spend, no denial). Too little energy is denied (see _deny).
func try_barrage() -> bool:
	if not _spend(&"barrage", _weapons.is_barraging(), _barrage_cost, "Barrage: -%d energy" % _barrage_cost):
		return false
	_weapons.start_barrage()
	Events.player_action.emit(&"barrage")
	return true


## One barrage tick (see PlayerWeapons.step_barrage).
func step_barrage(delta: float) -> void:
	_weapons.step_barrage(delta)


## The ability spend gate: dead or `busy` is a silent false; less than `cost`
## energy is denied (_deny); else the cost is spent, `log_line` logged, true.
func _spend(ability: StringName, busy: bool, cost: int, log_line: String) -> bool:
	if _dead or busy:
		return false
	if GameState.energy < cost:
		_deny(ability)
		return false
	GameState.add_energy(-cost)
	Log.info("combat", log_line)
	return true


## An ability pressed without enough energy: only the event and the denied SFX.
func _deny(ability: StringName) -> void:
	Events.ability_denied.emit(ability)
	Audio.play_sfx(&"ability_denied")


# --- Contact ----------------------------------------------------------------------

## Contact with `area`: an energy orb is collected (no heart cost, even while
## invulnerable); enemies and asteroids cost hearts by tier or size; small and
## medium enemies are then destroyed (even while invulnerable). Other areas and
## dead enemies are ignored. Surviving hazards are remembered. Once safe (level
## cleared) only orbs are collected; hazards cost and destroy nothing.
func on_contact(area: Area2D) -> void:
	if _dead:
		return
	var orb: EnergyOrb = area as EnergyOrb
	if orb != null:
		orb.collect()
		return
	if _safe:
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
	if _dead or _safe:
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


## Injected by the scene root when the level has a convoy (Story 6.1): its hulls
## become solid to the ship. Null (or a freed convoy) turns that off.
func set_convoy(convoy: Convoy) -> void:
	_convoy = convoy


## The HullArea circle radius (player.hull_diameter_px / 2).
func hull_radius() -> float:
	return _hull_radius


## One lock tick: the ship sits on the confined mouse point (viewport
## coordinates), or, with a live convoy, on that point resolved against the hulls
## (resolve_hull from the previous position; the first tick only snaps and
## pushes out). A mouse more than WARP_EPS_PX from the final position is warped
## onto it, but only while the gameplay mode is CONFINED_HIDDEN. When the ship
## moved (not on the first tick) it emits Events.player_moved (Story 5.8).
func step_lock(mouse: Vector2) -> void:
	var confined: Vector2 = confine(mouse, _bounds_min, _bounds_max)
	var previous: Vector2 = global_position
	var final: Vector2 = confined
	if _has_live_convoy():
		var start: Vector2 = previous if _locked_once else confined
		final = resolve_hull(start, confined, _hull_radius, _convoy.hull_rects(), _bounds_min, _bounds_max)
	var off: bool = mouse.distance_squared_to(final) > WARP_EPS_PX * WARP_EPS_PX
	if off and PauseArbiter.current_mouse_mode() == Input.MOUSE_MODE_CONFINED_HIDDEN:
		warp_mouse.call(final)
	global_position = final
	if not _locked_once:
		_locked_once = true
	elif final != previous:
		Events.player_moved.emit(previous.distance_to(final))


func _has_live_convoy() -> bool:
	if _convoy == null or not is_instance_valid(_convoy):
		return false
	return _convoy.is_inside_tree() and not _convoy.is_queued_for_deletion()


## The ship's position after moving from `from` toward `to` (both centres) past
## the axis-aligned `rects`, for a hull circle of `radius`: sub-steps of at most
## radius / 2, each pushed out of every rect (so the ship can't tunnel and slides
## along a hull), then confined to bounds_min..bounds_max. If that confinement
## leaves an overlap (a squeeze against the screen edge) the ship is pushed out
## along y only, and y is not clamped again (the band +- radius fits the zone).
## With from == to it only pushes out. No allocation.
static func resolve_hull(from: Vector2, to: Vector2, radius: float, rects: Array[Rect2],
		bounds_min: Vector2, bounds_max: Vector2) -> Vector2:
	if rects.is_empty() or radius <= 0.0:
		return confine(to, bounds_min, bounds_max)
	var step_len: float = radius / 2.0
	var steps: int = maxi(ceili(from.distance_to(to) / step_len), 1)
	var p: Vector2 = from
	for i: int in steps:
		p = p.move_toward(to, step_len)
		p = _push_out(p, radius, rects)
	p = confine(p, bounds_min, bounds_max)
	if overlaps_hull(p, radius, rects):
		p = _push_out_y(p, radius, rects)
	return p


## True when a circle of `radius` at `p` overlaps any rect (resting on one is not
## overlapping).
static func overlaps_hull(p: Vector2, radius: float, rects: Array[Rect2]) -> bool:
	for rect: Rect2 in rects:
		if _rect_overlap(p, radius, rect):
			return true
	return false


static func _rect_overlap(p: Vector2, radius: float, rect: Rect2) -> bool:
	var q: Vector2 = p.clamp(rect.position, rect.end)
	var r: float = radius - HULL_EPS_PX
	return p.distance_squared_to(q) < r * r


## Pushes `p` out of every rect it overlaps: to `radius` from the rect's closest
## point, or, with the centre inside (or on the edge of) a rect, out through the
## nearest side.
static func _push_out(p: Vector2, radius: float, rects: Array[Rect2]) -> Vector2:
	for rect: Rect2 in rects:
		var q: Vector2 = p.clamp(rect.position, rect.end)
		var d: Vector2 = p - q
		var d2: float = d.length_squared()
		if d2 >= radius * radius:
			continue
		if d2 > 0.0:
			p = q + d / sqrt(d2) * radius
			continue
		var to_left: float = p.x - rect.position.x
		var to_right: float = rect.end.x - p.x
		var to_top: float = p.y - rect.position.y
		var to_bottom: float = rect.end.y - p.y
		var nearest: float = minf(minf(to_left, to_right), minf(to_top, to_bottom))
		if nearest == to_top:
			p.y = rect.position.y - radius
		elif nearest == to_bottom:
			p.y = rect.end.y + radius
		elif nearest == to_left:
			p.x = rect.position.x - radius
		else:
			p.x = rect.end.x + radius
	return p


## Moves `p` vertically to the nearest y just above or below a rect where the
## circle overlaps no rect; unchanged if there is none.
static func _push_out_y(p: Vector2, radius: float, rects: Array[Rect2]) -> Vector2:
	var best_y: float = p.y
	var best_d: float = INF
	for rect: Rect2 in rects:
		var above: float = rect.position.y - radius
		var below: float = rect.end.y + radius
		if absf(above - p.y) < best_d and not overlaps_hull(Vector2(p.x, above), radius, rects):
			best_d = absf(above - p.y)
			best_y = above
		if absf(below - p.y) < best_d and not overlaps_hull(Vector2(p.x, below), radius, rects):
			best_d = absf(below - p.y)
			best_y = below
	return Vector2(p.x, best_y)


## Clamps the ship centre to x 0..Playfield width, y bounds_y.min..max.
func clamp_to_bounds(p: Vector2) -> Vector2:
	return confine(p, _bounds_min, _bounds_max)


## Pure clamp of a point into the rectangle bounds_min..bounds_max.
static func confine(mouse: Vector2, bounds_min: Vector2, bounds_max: Vector2) -> Vector2:
	return mouse.clamp(bounds_min, bounds_max)


## Resume from any pause: put the cursor back on the ship so the next lock tick
## reads the ship's own position and the ship does not jump. Ignored outside the
## tree: the outgoing Player of a scene change (or F5 restart) is still connected
## until it is freed at the end of the frame, and SceneRouter clears the pauses
## after the swap removed it (DW-61).
func _on_resumed() -> void:
	if not is_inside_tree():
		return
	if PauseArbiter.current_mouse_mode() == Input.MOUSE_MODE_CONFINED_HIDDEN:
		warp_mouse.call(global_position)
