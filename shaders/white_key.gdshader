shader_type canvas_item;

uniform float cutoff : hint_range(0.9, 1.0) = 0.988;

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	if (min(color.r, min(color.g, color.b)) >= cutoff) {
		color.a = 0.0;
	}
	COLOR = color;
}
