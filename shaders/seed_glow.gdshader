shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 0.45, 0.55, 0.16);

void fragment() {
	float d = length((UV - vec2(0.5)) * 2.0);
	float a = smoothstep(1.0, 0.25, d);
	a = pow(a, 2.4);
	COLOR = vec4(glow_color.rgb, a * glow_color.a) * COLOR;
}
