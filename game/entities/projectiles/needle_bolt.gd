class_name NeedleBolt
extends EnemyBullet
## The Needle's sniper bolt (GDD FR21, FR25): a long `enemy` magenta streak
## with a white core, fired along the Needle's locked targeting line at
## enemies.needle.bolt_speed_px_s (the one telegraphed exception to the
## enemy bullet speed cap).
##
## Everything else is EnemyBullet: layer enemy_shots, the travel-aligned
## anti-tunnelling capsule (height >= bolt speed / 60), damage only to
## non-asteroid targets with apply_damage, so an asteroid on the line stops the
## bolt without losing HP (the cover rule), then the bolt frees itself.


func _ready() -> void:
	var streak: Node2D = get_node_or_null(^"Streak") as Node2D
	if streak != null and not velocity.is_zero_approx():
		# The streak's long axis is local +y, like the capsule's.
		streak.rotation = velocity.angle() - PI / 2.0
	super._ready()
