class_name Asteroid
extends Area2D
## Drifting, spinning, destructible cover. Blocks every projectile (projectiles
## free themselves on contact); player shots damage it. Never splits. On
## destruction it rolls tuning.drops.asteroid_<size> through Loot (Story 3.3).
##
## Created only by Spawner: setup(params) stores values before add_child, and
## _ready() applies them.
##
## Story 8.2: `Visual/Sprite` shows the size's recoloured Kenney meteor
## (TEXTURES: `hazard` grey-brown with a baked `hazardRim` rim light on its
## upper-left edge), fitted so its longer side is asteroids.<size>.diameter_px.

const SIZES: Array[StringName] = [&"small", &"medium", &"large"]
## One preloaded meteor texture per size.
const TEXTURES: Dictionary[StringName, Texture2D] = {
	&"small": preload("res://assets/sprites/asteroids/asteroid_small.png"),
	&"medium": preload("res://assets/sprites/asteroids/asteroid_medium.png"),
	&"large": preload("res://assets/sprites/asteroids/asteroid_large.png"),
}

var size: StringName = &"small"
## Set by Spawner before add_child; the death drop (energy orbs) is requested
## through it. Null for asteroids created outside a Spawner (some tests).
var spawner: Spawner = null
var hp: int = 0
var radius: float = 0.0
var drift_speed: float = 0.0
## Signed spin in degrees per second.
var spin_deg_s: float = 0.0

var _spawn_position: Vector2 = Vector2.ZERO
var _has_spawn_position: bool = false
var _destroyed: bool = false
var _impact_tier: int = ImpactTier.SMALL


## Stores params; nothing is applied until _ready(). Keys: position (global), size.
func setup(params: Dictionary) -> void:
	if params.has("position"):
		_spawn_position = params["position"] as Vector2
		_has_spawn_position = true
	if params.has("size"):
		size = StringName(str(params["size"]))


func _ready() -> void:
	if _has_spawn_position:
		global_position = _spawn_position
	var key: String = "asteroids.%s" % size
	_impact_tier = ImpactTier.from_name(String(size))
	radius = Config.num(key + ".diameter_px") / 2.0
	hp = Config.int_(key + ".hp")
	drift_speed = Config.num(key + ".drift_speed_px_s")
	var spin: float = randf_range(Config.num(key + ".spin_deg_s.min"), Config.num(key + ".spin_deg_s.max"))
	spin_deg_s = spin if randf() < 0.5 else -spin

	var hitbox: CollisionShape2D = get_node_or_null(^"Hitbox") as CollisionShape2D
	if hitbox != null:
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = radius
		hitbox.shape = circle
	var sprite: Sprite2D = get_node_or_null(^"Visual/Sprite") as Sprite2D
	if sprite != null:
		sprite.texture = TEXTURES.get(size) as Texture2D
		SpriteFit.fit_longest(sprite, radius * 2.0, "asteroid %s" % size)
	add_to_group(Groups.ASTEROIDS)


func _physics_process(delta: float) -> void:
	position.y += drift_speed * delta
	rotation_degrees += spin_deg_s * delta
	if global_position.y - radius > Playfield.SIZE.y:
		queue_free()


func apply_damage(amount: int, _source: Node) -> void:
	if _destroyed:
		return
	hp -= amount
	if hp <= 0:
		_destroyed = true
		Feedback.impact(_impact_tier, global_position)
		Events.asteroid_destroyed.emit(size, global_position)
		if spawner != null and is_instance_valid(spawner):
			Loot.drop(spawner, "asteroid_%s" % size, global_position)
		queue_free()
