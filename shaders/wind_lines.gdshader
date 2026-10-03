shader_type canvas_item;

// Short streaks that travel along local +X, matching the zone's wind direction.
uniform vec4 wind_color : source_color = vec4(0.62, 0.98, 0.78, 1.0);
uniform float flow_speed = 80.0;
uniform float active : hint_range(0.0, 1.0) = 1.0;
uniform vec2 zone_size = vec2(260.0, 180.0);

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - 0.5) * zone_size;
	vec2 edge_dist = zone_size * 0.5 - abs(p);
	float fade = smoothstep(0.0, 26.0, edge_dist.x) * smoothstep(0.0, 32.0, edge_dist.y);

	float speed_scale = mix(0.22, 1.0, active);
	float streaks = 0.0;
	float core_sum = 0.0;

	for (int layer = 0; layer < 3; layer++) {
		float id = float(layer);
		float row_pitch = 15.0 + id * 7.0;
		float shifted = p.y + id * 40.0;
		float row = floor(shifted / row_pitch);
		float row_id = row + id * 100.0;
		float present = step(0.18 + id * 0.12, hash(row_id + 1.7));

		float y_center = (row + 0.5) * row_pitch - id * 40.0;
		float wave = sin(p.x * 0.03 + TIME * (1.1 + id * 0.35) + row_id) * (1.6 + id * 0.8);
		float dy = abs(p.y - y_center - wave);

		float dash_len = mix(16.0, 34.0, hash(row_id + 2.3)) + id * 10.0;
		float gap = mix(26.0, 64.0, hash(row_id + 6.1));
		float period = dash_len + gap;
		float spd = flow_speed * speed_scale * mix(0.72, 1.28, hash(row_id + 3.8)) * (1.0 + id * 0.28);
		float along = mod(p.x - TIME * spd + hash(row_id + 0.4) * period, period);

		float t = clamp(along / max(dash_len, 0.001), 0.0, 1.0);
		float on_dash = step(along, dash_len);
		// Soft tail, pointed tip at the leading end so a still frame still shows direction.
		float profile = smoothstep(0.0, 0.16, t) * (1.0 - smoothstep(0.58, 1.0, t));
		float thick = max(mix(2.6, 4.2, hash(row_id + 8.2)) * profile, 0.001);
		float core = (1.0 - smoothstep(thick * 0.15, thick, dy)) * on_dash * profile;
		float halo = (1.0 - smoothstep(thick * 0.8, thick * 2.6, dy)) * on_dash * profile;

		float brightness = mix(0.5, 1.0, hash(row_id + 4.4));
		float layer_fade = mix(1.0, 0.62, id / 2.0);
		streaks += (core + halo * 0.45) * present * brightness * layer_fade;
		core_sum += core * present;
	}

	streaks = clamp(streaks, 0.0, 1.0);
	core_sum = clamp(core_sum, 0.0, 1.0);
	vec3 color = mix(wind_color.rgb, vec3(0.95, 1.0, 0.98), core_sum * 0.7);
	float alpha = streaks * fade * mix(0.32, 1.0, active);
	COLOR = vec4(color, alpha);
}
