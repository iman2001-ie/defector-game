class_name SpriteFit
extends RefCounted
## Uniform sprite sizing from data (Story 8.2), the rule Player._fit_hull uses
## for the player hull: the sprite is scaled uniformly so its texture's longer
## side equals a size from tuning (an enemy's or the Ram's `sprite_px`, a
## `boss.*.sprite_px`, `allies.ship_px`, an asteroid's `diameter_px`), or so the
## whole texture fits inside a box (the convoy hull in
## convoy.ship_width_px x ship_height_px). The sprite stays centred and is never
## rotated here.
##
## A missing sprite or texture, or a size <= 0, logs one `[WARN][data]` line
## per call naming `what` and leaves the scale as authored (1), so a bad size
## never hides the ship.


## Scales `sprite` uniformly so the longer side of its texture is `px`.
## Returns true when it was sized.
static func fit_longest(sprite: Sprite2D, px: float, what: String) -> bool:
	var tex: Texture2D = sprite.texture if sprite != null else null
	if tex == null or px <= 0.0:
		Log.warn("data", "%s sprite not sized: texture %s, size %s px"
				% [what, "missing" if tex == null else "ok", px])
		return false
	var longest: float = maxf(tex.get_width(), tex.get_height())
	if longest <= 0.0:
		Log.warn("data", "%s sprite not sized: empty texture" % what)
		return false
	sprite.scale = Vector2.ONE * (px / longest)
	return true


## Scales `sprite` uniformly so its whole texture fits inside `box` (the larger
## scale at which neither side exceeds the box). Returns true when it was sized.
static func fit_inside(sprite: Sprite2D, box: Vector2, what: String) -> bool:
	var tex: Texture2D = sprite.texture if sprite != null else null
	if tex == null or box.x <= 0.0 or box.y <= 0.0:
		Log.warn("data", "%s sprite not sized: texture %s, box %s px"
				% [what, "missing" if tex == null else "ok", box])
		return false
	if tex.get_width() <= 0 or tex.get_height() <= 0:
		Log.warn("data", "%s sprite not sized: empty texture" % what)
		return false
	sprite.scale = Vector2.ONE * minf(box.x / tex.get_width(), box.y / tex.get_height())
	return true


## The drawn size of `sprite` (texture size times scale; zero without a texture).
static func drawn_size(sprite: Sprite2D) -> Vector2:
	if sprite == null or sprite.texture == null:
		return Vector2.ZERO
	return sprite.texture.get_size() * sprite.scale.abs()
