class_name RenderGlow
extends RefCounted
## Applies tuning.json -> render.glow (intensity, bloom, HDR threshold) to a
## WorldEnvironment's Environment. Every scene root with a WorldEnvironment calls
## apply() in _ready(); F5 restarts the scene, so reloaded data is applied too.
## glow_enabled and background_mode stay in the .tscn; only these three are data.


static func apply(env: Environment) -> void:
	if env == null:
		Log.error("scene", "RenderGlow.apply: no Environment to apply render.glow to")
		return
	env.glow_intensity = Config.num("render.glow.intensity")
	env.glow_bloom = Config.num("render.glow.bloom")
	env.glow_hdr_threshold = Config.num("render.glow.hdr_threshold")
