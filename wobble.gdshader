shader_type canvas_item;

uniform sampler2D flowMap;
uniform float strength;
uniform float speed;
uniform int frames : hint_range(1, 60);

float clock(float time){
	float fframes = float(frames);
	return floor(mod(time * speed, fframes)) / fframes;
}

void fragment(){
	float c = clock(TIME);
	vec4 offset = texture(flowMap, vec2(UV.x + c, UV.y + c)) * strength;
	COLOR = texture(TEXTURE, vec2(UV.x,UV.y) + offset.xy - vec2(0.5,0.5)*strength);
}
