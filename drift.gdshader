shader_type canvas_item;

uniform float wave_speed = 3.0;
uniform float wave_freq = 10.0;
uniform float wave_width = 1;
void fragment(){
	vec2 scale_UV = UV;
	vec2 wave_uv_offset = vec2(0.0);
	wave_uv_offset.x = cos((TIME*wave_speed)+UV.x+UV.y*wave_freq*2.0)*wave_width*0.01;
	wave_uv_offset.y = cos((TIME*wave_speed)+UV.x+UV.x*wave_freq*2.0)*wave_width*0.01;
	COLOR = texture(TEXTURE,scale_UV+wave_uv_offset);
}