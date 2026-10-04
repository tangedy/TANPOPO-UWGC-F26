shader_type canvas_item;

// A few pixels of softness so the disc edge fades into the glow.
uniform float disc_scale : hint_range(0.7, 1.0) = 0.98;
uniform float blur : hint_range(0.0, 0.03) = 0.004;

void fragment() {
	vec4 modulate = COLOR;
	vec2 uv = (UV - vec2(0.5)) / disc_scale + vec2(0.5);
	vec4 color = vec4(0.0);
	float weight = 0.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 sample_uv = uv + vec2(float(x), float(y)) * blur;
			float inside = step(0.0, sample_uv.x) * step(sample_uv.x, 1.0) * step(0.0, sample_uv.y) * step(sample_uv.y, 1.0);
			float w = 1.0 / (1.0 + float(x * x + y * y));
			color += texture(TEXTURE, clamp(sample_uv, vec2(0.0), vec2(1.0))) * inside * w;
			weight += w;
		}
	}
	COLOR = (color / weight) * modulate;
}
