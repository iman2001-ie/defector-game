class_name Explosion
extends Node2D
## One-shot explosion effect, scaled per impact tier. Burst always plays; Sparks,
## Debris and Shockwave play only when listed in the tier's extras. Frees itself
## after LIFETIME_S. Visual only: no collision, no gameplay effect.
##
## The `white_flash` extra (Story 7.5, the Boss-death tier) shows the `Flash`
## child: a full-screen white ColorRect on its own CanvasLayer (layer 15, above
## the HUD at 10 and below Comms at 20). It starts at feedback.white_flash.alpha
## and fades linearly to 0 over feedback.white_flash.duration_s (capped at
## LIFETIME_S), then hides. It runs on the explosion's own _process, so it
## freezes with the game. Other unknown extras (`red_vignette`) are ignored.
##
## Playtest pt7-e: an optional `speed` (default 1.0, the Flagship's death chain
## uses feedback.boss_death_chain_anim_speed) plays the whole effect slower or
## faster: every particle system's speed_scale, the shockwave's expansion and
## the self-free time all scale by it (lifetime() = LIFETIME_S / speed). The
## white flash keeps its own tuned fade.
##
## Created only by Spawner: setup(params) stores values before add_child, and
## _ready() applies them.

const EXTRA_SPARKS: StringName = &"sparks"
const EXTRA_DEBRIS: StringName = &"debris"
const EXTRA_SHOCKWAVE: StringName = &"shockwave"
const EXTRA_WHITE_FLASH: StringName = &"white_flash"
## Seconds the shockwave ring takes to expand and fade.
const SHOCKWAVE_S: float = 0.45
## Seconds until the node frees itself at speed 1; at least every child's lifetime.
const LIFETIME_S: float = 1.0
## The slowest playback a `speed` param may ask for (keeps lifetime() finite).
const MIN_SPEED: float = 0.05

var explosion_scale: float = 1.0
## Playback speed (1.0 = as authored; below 1 is slower).
var speed: float = 1.0
var extras: Array[StringName] = []

var _spawn_position: Vector2 = Vector2.ZERO
var _has_spawn_position: bool = false
var _elapsed: float = 0.0
var _freed: bool = false
## The white flash's starting alpha and fade time (white_flash extra only).
var _flash_alpha: float = 0.0
var _flash_s: float = 0.0

@onready var _burst: GPUParticles2D = $Burst
@onready var _sparks: GPUParticles2D = $Sparks
@onready var _debris: GPUParticles2D = $Debris
@onready var _shockwave: ShockwaveRing = $Shockwave
@onready var _flash: CanvasLayer = $Flash
@onready var _flash_rect: ColorRect = $Flash/Rect


## Stores params; nothing is applied until _ready(). Keys: position (global),
## scale (uniform), extras (Array of StringName; unknown extras are ignored).
func setup(params: Dictionary) -> void:
	if params.has("position"):
		_spawn_position = params["position"] as Vector2
		_has_spawn_position = true
	explosion_scale = float(params.get("scale", explosion_scale))
	speed = maxf(float(params.get("speed", speed)), MIN_SPEED)
	extras.clear()
	var raw: Variant = params.get("extras", [])
	if raw is Array:
		for extra: Variant in raw as Array:
			extras.append(StringName(str(extra)))


func _ready() -> void:
	if _has_spawn_position:
		global_position = _spawn_position
	scale = Vector2(explosion_scale, explosion_scale)
	for particles: GPUParticles2D in [_burst, _sparks, _debris]:
		particles.speed_scale = speed
	_burst.emitting = true
	_sparks.emitting = extras.has(EXTRA_SPARKS)
	_debris.emitting = extras.has(EXTRA_DEBRIS)
	_shockwave.visible = extras.has(EXTRA_SHOCKWAVE)
	if _shockwave.visible:
		_shockwave.set_progress(0.0)
	_flash.visible = false
	if extras.has(EXTRA_WHITE_FLASH):
		_flash_alpha = clampf(Config.num("feedback.white_flash.alpha"), 0.0, 1.0)
		_flash_s = minf(Config.num("feedback.white_flash.duration_s"), lifetime())
		if _flash_alpha > 0.0 and _flash_s > 0.0:
			_flash.visible = true
			_set_flash_alpha(_flash_alpha)


func _process(delta: float) -> void:
	if _freed:
		return
	_elapsed += delta
	if _shockwave.visible:
		_shockwave.set_progress(_elapsed * speed / SHOCKWAVE_S)
	if _flash.visible:
		_step_flash()
	if _elapsed >= lifetime():
		_freed = true
		queue_free()


## Seconds until the node frees itself: LIFETIME_S at this playback speed.
func lifetime() -> float:
	return LIFETIME_S / speed


## True while the white flash shows.
func is_flashing() -> bool:
	return _flash != null and _flash.visible


## The white flash's current alpha (0 when it isn't showing).
func flash_alpha() -> float:
	return _flash_rect.color.a if is_flashing() else 0.0


## Linear fade from _flash_alpha to 0 over _flash_s, then hidden.
func _step_flash() -> void:
	if _elapsed >= _flash_s:
		_set_flash_alpha(0.0)
		_flash.visible = false
		return
	_set_flash_alpha(_flash_alpha * (1.0 - _elapsed / _flash_s))


func _set_flash_alpha(alpha: float) -> void:
	_flash_rect.color = Color(1.0, 1.0, 1.0, alpha)
