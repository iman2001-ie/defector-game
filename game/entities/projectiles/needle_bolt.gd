class_name NeedleBolt
extends EnemyBullet
## The Needle's sniper bolt (GDD FR21, FR25): a long `enemy` magenta streak
## with a white core, fired along the Needle's locked targeting line at
## enemies.needle.bolt_speed_px_s (the one telegraphed exception to the
## enemy bullet speed cap).
##
## Everything else is EnemyBullet: layer enemy_shots, the travel-aligned
## anti-tunnelling capsule, damage only to non-asteroid targets with
## apply_damage, so an asteroid on the line stops the bolt without losing HP
## (the cover rule), then the bolt frees itself.
##
## Anti-tunnelling: the bolt moves bolt speed / physics ticks per tick, so its
## capsule is stretched in _ready to at least that length (the faster of its
## own velocity and the tuned bolt speed), never shorter than the scene's
## capsule. A retune of bolt_speed_px_s stays safe without editing the scene.


func _ready() -> void:
	_fit_capsule_to_speed()
	# The streak's long axis is local +y, like the capsule's.
	_align_to_velocity(get_node_or_null(^"Streak") as Node2D)
	super._ready()


## Lengthens the Hitbox capsule to one physics tick of travel when the scene's
## capsule is shorter. The shape is duplicated first, since the scene's shape
## resource is shared by every bolt.
func _fit_capsule_to_speed() -> void:
	var hitbox: CollisionShape2D = get_node_or_null(^"Hitbox") as CollisionShape2D
	if hitbox == null or not (hitbox.shape is CapsuleShape2D):
		return
	var capsule: CapsuleShape2D = hitbox.shape as CapsuleShape2D
	var speed: float = maxf(velocity.length(), Config.num("enemies.needle.bolt_speed_px_s"))
	var per_tick: float = speed / float(Engine.physics_ticks_per_second)
	if capsule.height >= per_tick:
		return
	var fitted: CapsuleShape2D = capsule.duplicate() as CapsuleShape2D
	fitted.height = ceilf(per_tick)
	hitbox.shape = fitted
