class_name FlagshipCore
extends FlagshipPart
## The Flagship's core (Story 7.3): `boss.core` tuning (hp 200, the boss_death
## tier, sprite_px, hitbox_ratio). It starts invulnerable and stays so for all
## of Phase 1, so shots on it are spent and ignored and it is no target.
## Story 7.4 exposes it and gives it its attacks.

const SECTION: String = "boss.core"


func _init() -> void:
	type_id = &"flagship_core"
	invulnerable = true


func _tuning_section() -> String:
	return SECTION
