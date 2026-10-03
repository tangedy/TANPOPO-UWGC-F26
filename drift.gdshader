shader_type canvas_item;

uniform float wave_speed = 3.0;
uniform float wave_freq = 10.0;
uniform float wave_width = 1.0;

varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
	vec2 wave_uv_offset = vec2(0.0);
	wave_uv_offset.x = cos((TIME * wave_speed) + UV.x + UV.y * wave_freq * 2.0) * wave_width * 0.01;
	wave_uv_offset.y = cos((TIME * wave_speed) + UV.x + UV.x * wave_freq * 2.0) * wave_width * 0.01;
	vec4 tex = texture(TEXTURE, UV + wave_uv_offset);
	COLOR = tex * modulate;
}
