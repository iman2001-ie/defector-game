class_name Explosion
extends Node2D
## One-shot explosion effect, scaled per impact tier. Burst always plays; Sparks,
## Debris and Shockwave play only when listed in the tier's extras. Frees itself
## after LIFETIME_S. Visual only: no collision, no gameplay effect.
##
## Created only by Spawner: setup(params) stores values before add_child, and
## _ready() applies them.

const EXTRA_SPARKS: StringName = &"sparks"
const EXTRA_DEBRIS: StringName = &"debris"
const EXTRA_SHOCKWAVE: StringName = &"shockwave"
## Seconds the shockwave ring takes to expand and fade.
const SHOCKWAVE_S: float = 0.45
## Seconds until the node frees itself; at least every child's lifetime.
const LIFETIME_S: float = 1.0

var explosion_scale: float = 1.0
var extras: Array[StringName] = []

var _spawn_position: Vector2 = Vector2.ZERO
var _has_spawn_position: bool = false
var _elapsed: float = 0.0
var _freed: bool = false

@onready var _burst: GPUParticles2D = $Burst
@onready var _sparks: GPUParticles2D = $Sparks
@onready var _debris: GPUParticles2D = $Debris
@onready var _shockwave: ShockwaveRing = $Shockwave


## Stores params; nothing is applied until _ready(). Keys: position (global),
## scale (uniform), extras (Array of StringName; unknown extras are ignored).
func setup(params: Dictionary) -> void:
	if params.has("position"):
		_spawn_position = params["position"] as Vector2
		_has_spawn_position = true
	explosion_scale = float(params.get("scale", explosion_scale))
	extras.clear()
	var raw: Variant = params.get("extras", [])
	if raw is Array:
		for extra: Variant in raw as Array:
			extras.append(StringName(str(extra)))


func _ready() -> void:
	if _has_spawn_position:
		global_position = _spawn_position
	scale = Vector2(explosion_scale, explosion_scale)
	_burst.emitting = true
	_sparks.emitting = extras.has(EXTRA_SPARKS)
	_debris.emitting = extras.has(EXTRA_DEBRIS)
	_shockwave.visible = extras.has(EXTRA_SHOCKWAVE)
	if _shockwave.visible:
		_shockwave.set_progress(0.0)


func _process(delta: float) -> void:
	if _freed:
		return
	_elapsed += delta
	if _shockwave.visible:
		_shockwave.set_progress(_elapsed / SHOCKWAVE_S)
	if _elapsed >= LIFETIME_S:
		_freed = true
		queue_free()
