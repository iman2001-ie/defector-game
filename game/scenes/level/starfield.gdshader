shader_type canvas_item;
// The starfield (playtest 2026-10-14): three parallax layers of small
// procedural stars drifting straight down over the tiled space texture, drawn
// on LevelBackground's `Stars` rect. Each layer is a jittered grid with one star
// per cell (cell size from the layer's density); the star hash repeats every
// `period` cell rows, so LevelBackground can wrap each layer's scroll at
// cell_px * period with no visible jump. Scroll and twinkle time come from
// GDScript (game time), never TIME, so the field freezes on pause and slows in
// slow motion. Pale blue-white only; LevelBackground sets every uniform.

// The rect's top-left in playfield px and its size, to map UV to playfield px.
uniform vec2 rect_origin = vec2(0.0);
uniform vec2 rect_size = vec2(1.0);
// Per layer (x far, y mid, z near): grid cell size in px, scroll in px (down),
// star diameter in px and peak brightness (alpha of the star colour).
uniform vec3 cell_px = vec3(50.0, 100.0, 180.0);
uniform vec3 scroll_px = vec3(0.0);
uniform vec3 size_px = vec3(1.0, 1.5, 2.0);
uniform vec3 brightness = vec3(0.22, 0.38, 0.6);
// How many cell rows before the star pattern repeats.
uniform float period = 256.0;
// Twinkle: the share of stars that twinkle, how deep (0..1) and the base rate.
uniform float twinkle_fraction = 0.35;
uniform float twinkle_amount = 0.5;
uniform float twinkle_hz = 0.25;
// Seconds of game time, wrapped by LevelBackground at 1 / twinkle_hz.
uniform float twinkle_time = 0.0;
uniform vec4 color_a : source_color = vec4(0.788, 0.847, 0.910, 1.0);
uniform vec4 color_b : source_color = vec4(0.910, 0.957, 1.0, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

// One layer at playfield point `p`: vec2(alpha, colour mix t), where alpha is
// the star's antialiased coverage times its brightness (0 off any star).
vec2 layer(vec2 p, float cell, float scroll, float diameter, float peak, float seed) {
	if (cell <= 0.0 || peak <= 0.0) {
		return vec2(0.0);
	}
	vec2 q = vec2(p.x, p.y - scroll);
	vec2 c = floor(q / cell);
	c.y = mod(c.y, period);
	vec2 id = c + vec2(seed * 17.0, seed * 31.0);
	// The star sits in the middle 80% of its cell, so it never crosses into the next.
	vec2 star = (vec2(hash(id), hash(id + 7.13)) * 0.8 + 0.1) * cell;
	vec2 local = q - floor(q / cell) * cell;
	float d = length(local - star);
	float cover = clamp(diameter * 0.5 + 0.5 - d, 0.0, 1.0);
	if (cover <= 0.0) {
		return vec2(0.0);
	}
	float h = hash(id + 3.71);
	float b = peak * (0.6 + 0.4 * h);
	if (hash(id + 9.29) < twinkle_fraction) {
		float k = 1.0 + floor(h * 3.0);
		float wave = 0.5 + 0.5 * sin(TAU * twinkle_hz * k * twinkle_time + h * 40.0);
		b *= 1.0 - twinkle_amount * wave;
	}
	return vec2(cover * b, hash(id + 5.17));
}

void fragment() {
	vec2 p = rect_origin + UV * rect_size;
	vec2 far = layer(p, cell_px.x, scroll_px.x, size_px.x, brightness.x, 1.0);
	vec2 mid = layer(p, cell_px.y, scroll_px.y, size_px.y, brightness.y, 2.0);
	vec2 near = layer(p, cell_px.z, scroll_px.z, size_px.z, brightness.z, 3.0);
	// The strongest layer at this pixel wins (stars almost never overlap).
	vec2 s = far;
	if (mid.x > s.x) { s = mid; }
	if (near.x > s.x) { s = near; }
	COLOR = vec4(mix(color_a.rgb, color_b.rgb, s.y), clamp(s.x, 0.0, 1.0));
}
