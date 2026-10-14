extends RefCounted
## Test helper for the Story 8.2 art pins: a sprite's drawn size and its
## texture's dominant hue. Not a test script (GUT only collects `test_`-prefixed
## files) and has no class_name: preload it by path.

## Saturation below this is treated as grey (the same cut as the importer's
## recolour reference, tools/import_cc0_art.py).
const MIN_SATURATION: float = 0.25


## The longer side of `sprite` as drawn (texture size times its scale).
static func longest_side(sprite: Sprite2D) -> float:
	var drawn: Vector2 = SpriteFit.drawn_size(sprite)
	return maxf(drawn.x, drawn.y)


## The hue (0..1) of the most common fully opaque, saturated colour of `tex`
## (-1 when it has none).
static func dominant_hue(tex: Texture2D) -> float:
	if tex == null:
		return -1.0
	var image: Image = tex.get_image()
	if image == null:
		return -1.0
	if image.is_compressed():
		image.decompress()
	var counts: Dictionary[int, int] = {}
	var best: int = -1
	var best_n: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var c: Color = image.get_pixel(x, y)
			if c.a < 0.999 or c.s < MIN_SATURATION:
				continue
			var key: int = c.to_rgba32()
			var n: int = counts.get(key, 0) + 1
			counts[key] = n
			if n > best_n:
				best_n = n
				best = key
	if best < 0:
		return -1.0
	return Color.hex(best).h


## The angular distance between two hues (0..1 each), in degrees.
static func hue_distance_deg(a: float, b: float) -> float:
	var d: float = absf(a - b)
	return minf(d, 1.0 - d) * 360.0


## The largest colour channel (0..1) anywhere in `tex` (-1 without a texture or image).
static func max_channel(tex: Texture2D) -> float:
	if tex == null:
		return -1.0
	var image: Image = tex.get_image()
	if image == null:
		return -1.0
	if image.is_compressed():
		image.decompress()
	var top: float = 0.0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var c: Color = image.get_pixel(x, y)
			top = maxf(top, maxf(c.r, maxf(c.g, c.b)))
	return top
