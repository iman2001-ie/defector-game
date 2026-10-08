class_name Missile
extends Projectile
## Player missile: aimed, unguided. The hit target takes `damage` (Projectile base);
## every other enemy and asteroid within splash_radius of the impact point takes
## splash_damage once. Splash distance is centre to centre, found through the
## `enemies`/`asteroids` groups (no physics query: the space is locked in area_entered).

const SPLASH_GROUPS: Array[StringName] = [Groups.ENEMIES, Groups.ASTEROIDS]

var splash_damage: int = 0
var splash_radius: float = 0.0


func _init() -> void:
	impact_tier = ImpactTier.MEDIUM


func _ready() -> void:
	splash_damage = Config.int_("weapons.missile.splash_damage")
	splash_radius = Config.num("weapons.missile.splash_radius_px")
	super._ready()
	if velocity != Vector2.ZERO:
		# Local -Y (the capsule axis and the nose) points along travel.
		rotation = velocity.angle() + PI / 2.0


func _on_impact(area: Area2D) -> void:
	apply_splash(area)
	super._on_impact(area)


## Deals splash_damage once to every enemy and asteroid (other than `hit`) whose
## centre is within splash_radius (inclusive) of the missile's position.
func apply_splash(hit: Node) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var centre: Vector2 = global_position
	var done: Dictionary[Node, bool] = {}
	for group: StringName in SPLASH_GROUPS:
		for node: Node in tree.get_nodes_in_group(group):
			if node == hit or done.has(node) or node.is_queued_for_deletion():
				continue
			var body: Node2D = node as Node2D
			if body == null or not body.has_method(&"apply_damage"):
				continue
			if body.global_position.distance_to(centre) > splash_radius:
				continue
			done[node] = true
			body.call(&"apply_damage", splash_damage, self)
