shader_type canvas_item;
// The throne world (playtest 2026-10-14): the lower cap of a sphere whose
// centre sits above the playfield, drawn on LevelBackground's `Planet` rect.
// Limb-shaded and lit from the left, so a soft terminator splits a dim day side
// from a night side; slowly drifting violet bands; sparse dim city lights on the
// night side; a thin violet atmosphere just outside the disc. The surface stays
// below render.glow.hdr_threshold; only the outermost rim and the brightest city
// lights reach it, faintly. LevelBackground sets every uniform from its art
// constants.

// The rect's top-left in playfield px and its size, to map UV to playfield px.
uniform vec2 rect_origin = vec2(0.0);
uniform vec2 rect_size = vec2(1.0);
uniform vec2 centre = vec2(960.0, -920.0);
uniform float radius = 1100.0;
uniform vec4 base_color : source_color = vec4(0.102, 0.078, 0.149, 1.0);
uniform vec4 band_color : source_color = vec4(0.180, 0.141, 0.271, 1.0);
uniform vec4 rim_color : source_color = vec4(0.259, 0.212, 0.361, 1.0);
uniform vec4 atmosphere_color : source_color = vec4(0.416, 0.333, 0.659, 1.0);
uniform vec4 city_color : source_color = vec4(0.659, 0.545, 1.0, 1.0);
// Where the light comes from (normalised in the shader): the left, a little
// below and in front, so the left of the visible cap is lit.
uniform vec3 light_dir = vec3(-1.0, 0.25, 0.25);
// How far the atmosphere reaches outside the disc, in px.
uniform float atmosphere_px = 30.0;
// Surface drift in radians of longitude per second (barely moving).
uniform float drift_speed = 0.003;
// Seconds of game time, fed by LevelBackground (freezes on pause like the stars;
// unlike TIME it never rolls over, so the surface never pops).
uniform float time_s = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += amp * value_noise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		amp *= 0.5;
	}
	return sum;
}

void fragment() {
	vec2 p = rect_origin + UV * rect_size;
	vec2 d = (p - centre) / radius;
	float r = length(d);
	float px = 1.0 / radius;
	float halo_end = 1.0 + atmosphere_px * px;
	if (r > halo_end) {
		COLOR = vec4(0.0);
	} else {
		vec3 L = normalize(light_dir);
		// The disc, antialiased over about 1.5 px.
		float inside = 1.0 - smoothstep(1.0 - 1.5 * px, 1.0, r);

		// --- the sphere ---
		float z = sqrt(max(1.0 - r * r, 0.0));
		vec3 n = vec3(d, z);
		float ndl = dot(n, L);
		float day = smoothstep(-0.12, 0.4, ndl);
		float lon = atan(n.x, max(n.z, 0.0001)) + time_s * drift_speed;
		float lat = asin(clamp(n.y, -1.0, 1.0));
		// Broad latitude bands broken up by continents.
		float bands = fbm(vec2(lon * 2.2, lat * 10.0));
		float land = fbm(vec2(lon * 5.0 + 3.0, lat * 7.0 - 1.0));
		float surf_t = clamp(0.6 * smoothstep(0.3, 0.7, bands) + 0.5 * smoothstep(0.45, 0.65, land), 0.0, 1.0);
		vec3 surf = mix(base_color.rgb, band_color.rgb, surf_t);
		// Day side up to about 1.4x, night side down to 0.25x the surface colour.
		vec3 planet = surf * mix(0.25, 1.4, day);
		// A soft scattering rim toward the limb, stronger on the day side.
		float limb = pow(1.0 - z, 3.0);
		planet += atmosphere_color.rgb * limb * mix(0.08, 0.6, day);
		// The thin rim line right at the edge.
		float edge = smoothstep(1.0 - 4.0 * px, 1.0 - 1.0 * px, r);
		planet = mix(planet, max(planet, rim_color.rgb), edge * 0.8);

		// City lights: sparse, small, on land, on the night side only.
		vec2 cell_uv = vec2(lon * 70.0, lat * 140.0);
		vec2 cell = floor(cell_uv);
		float h = hash(cell);
		float lit = step(0.93, h) * step(0.5, land);
		vec2 in_cell = fract(cell_uv) - 0.5;
		float dot_shape = 1.0 - smoothstep(0.08, 0.3, length(in_cell));
		float twinkle = 0.75 + 0.25 * sin(time_s * (0.6 + h * 1.4) + h * 40.0);
		float night = 1.0 - smoothstep(-0.05, 0.25, ndl);
		// Fade out at the extreme limb, where the cells are too foreshortened to read.
		float visible_face = smoothstep(0.08, 0.3, z);
		planet += city_color.rgb * 0.55 * lit * dot_shape * twinkle * night * visible_face;

		// --- the atmosphere halo outside the disc ---
		float out_t = clamp((r - 1.0) / (atmosphere_px * px), 0.0, 1.0);
		float edge_day = smoothstep(-0.3, 0.5, dot(vec3(d / max(r, 0.0001), 0.0), L));
		// Full strength from the edge inward, so the antialiased edge has no seam.
		float halo_a = exp(-out_t * 2.5) * (1.0 - out_t) * mix(0.15, 0.6, edge_day);

		float a = inside + halo_a * (1.0 - inside);
		vec3 rgb = (planet * inside + atmosphere_color.rgb * halo_a * (1.0 - inside)) / max(a, 0.0001);
		COLOR = vec4(rgb, a);
	}
}
