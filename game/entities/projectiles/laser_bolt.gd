class_name LaserBolt
extends Projectile
## Player laser bolt: twin visual, one capsule, one damage instance.
##
## Each twin (BoltLeft / BoltRight) is an HDR core: its self_modulate is
## weapons.laser.glow_energy (> 1.0), so it crosses the render.glow HDR threshold
## and blooms. Each twin has a wider additive Halo child drawn behind it, at
## weapons.laser.halo_energy, so the bolt still reads as a glowing bullet without
## WorldEnvironment glow (ADR-003). self_modulate (not modulate) keeps the halo's
## brightness independent of the core's (decision #30).

const TWIN_NAMES: Array[StringName] = [&"BoltLeft", &"BoltRight"]


func _ready() -> void:
	var e: float = Config.num("weapons.laser.glow_energy")
	var h: float = Config.num("weapons.laser.halo_energy")
	var core_tint: Color = Color(e, e, e, 1.0)
	var halo_tint: Color = Color(h, h, h, 1.0)
	for twin_name: StringName in TWIN_NAMES:
		var twin: Sprite2D = get_node_or_null(NodePath(twin_name)) as Sprite2D
		if twin == null:
			continue
		twin.self_modulate = core_tint
		var halo: Sprite2D = twin.get_node_or_null(^"Halo") as Sprite2D
		if halo != null:
			halo.self_modulate = halo_tint
	super._ready()
