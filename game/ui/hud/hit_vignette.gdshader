shader_type canvas_item;
// Hit vignette (UX `vignette`): the ColorRect colour fades in toward the screen
// edges. Alpha comes from the node's colour, so a tween on it fades the whole effect.

uniform float inner : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec2 d = abs(UV - vec2(0.5)) * 2.0;
	float edge = max(d.x, d.y);
	COLOR = vec4(COLOR.rgb, COLOR.a * smoothstep(inner, 1.0, edge));
}
