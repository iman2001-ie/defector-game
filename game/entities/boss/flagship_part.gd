class_name FlagshipPart
extends Enemy
## One damageable part of the Flagship (Story 7.3): a turret or the core.
##
## Its tuning lives in a `boss.*` section (subclasses override
## _tuning_section()); _ready reads `sprite_px` from that section before
## Enemy._ready builds the circle Hitbox from it and `hitbox_ratio`.
##
## While `invulnerable` every apply_damage is ignored: the shot that hit it is
## still spent, and the part is not a target for micro-missiles or the ally
## (is_targetable). Otherwise the damage goes through Enemy.apply_damage (a
## kill plays the part's tier, emits enemy_killed and rolls its drops), and
## hp_changed then reports the new hp, also on the killing hit (hp <= 0).
## Contact never destroys a part: its tier is neither small nor medium.
##
## The Flagship hands each part its `spawner` and listens to hp_changed.

## The part's hp after a hit it took (<= 0 on the killing hit).
signal hp_changed(hp: int)

## While true, damage is ignored and the part is not a target.
var invulnerable: bool = false


func _ready() -> void:
	sprite_px = Config.num(_tuning_key("sprite_px"))
	super()


func apply_damage(amount: int, source: Node) -> void:
	if invulnerable or _dead:
		return
	super(amount, source)
	hp_changed.emit(hp)


func is_targetable() -> bool:
	return not invulnerable
