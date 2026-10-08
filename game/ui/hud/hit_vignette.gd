class_name HitVignette
extends ColorRect
## Red screen-edge flash when the player is hit (UX `vignette`, GDD PLAYER_HIT
## "red edge vignette"). A full-rect ColorRect in the HUD whose colour is the
## theme's `danger` (`HitVignette/colors/color`) and whose shader fades it in
## toward the edges.
##
## Driven only by Events.player_hit: the alpha jumps to `hud.hit_vignette.max_alpha`
## and tweens to 0 over `hud.hit_vignette.duration_s`. Hidden at alpha 0. The
## tween is bound to this pausable node, so it freezes with the game.

const THEME_TYPE: StringName = &"HitVignette"
const COLOR_NAME: StringName = &"color"
const SHADER: Shader = preload("res://ui/hud/hit_vignette.gdshader")

var duration_s: float = 0.0
var max_alpha: float = 0.0

var _alpha: float = 0.0
var _tween: Tween


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	duration_s = maxf(Config.num("hud.hit_vignette.duration_s"), 0.0)
	max_alpha = clampf(Config.num("hud.hit_vignette.max_alpha"), 0.0, 1.0)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if material == null:
		var shader_material: ShaderMaterial = ShaderMaterial.new()
		shader_material.shader = SHADER
		material = shader_material
	_set_alpha(0.0)
	Events.player_hit.connect(_on_events_player_hit)


## The vignette's current alpha (0 when hidden).
func current_alpha() -> float:
	return _alpha


func _on_events_player_hit(_position: Vector2) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_set_alpha(max_alpha)
	if duration_s <= 0.0:
		_set_alpha(0.0)
		return
	_tween = create_tween()
	_tween.tween_method(_set_alpha, max_alpha, 0.0, duration_s)


func _set_alpha(value: float) -> void:
	_alpha = maxf(value, 0.0)
	var base: Color = get_theme_color(COLOR_NAME, THEME_TYPE)
	color = Color(base.r, base.g, base.b, _alpha)
	visible = _alpha > 0.0
