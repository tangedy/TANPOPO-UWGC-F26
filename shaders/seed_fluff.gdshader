shader_type canvas_item;

// Texture is a black silhouette with alpha; draw it as soft light fluff.
uniform vec4 fluff_color : source_color = vec4(0.92, 0.9, 0.84, 1.0);

void fragment() {
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(fluff_color.rgb, a * fluff_color.a) * COLOR;
}
