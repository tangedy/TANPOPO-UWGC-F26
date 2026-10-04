shader_type canvas_item;
render_mode blend_add;

uniform vec4 glow_color : source_color = vec4(1.0, 0.97, 0.82, 0.55);

void fragment() {
	vec4 modulate = COLOR;
	float d = length((UV - vec2(0.5)) * 2.0);
	float a = smoothstep(1.0, 0.0, d);
	a = pow(a, 1.7);
	COLOR = vec4(glow_color.rgb * a, a * glow_color.a) * modulate;
}
