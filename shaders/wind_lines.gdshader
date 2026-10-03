shader_type canvas_item;

// Short streaks that travel along the zone's flow. The flow bows along a
// parabolic arc controlled by `curve`, and the push field in wind_zone.gd
// samples the same arc so the visuals match the force.
// The quad (rect_size) is padded larger than the logical wind area (zone_size)
// so the bow and the line ends fade out instead of being clipped by the edge.
uniform vec4 wind_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flow_speed = 80.0;
uniform float active : hint_range(0.0, 1.0) = 1.0;
uniform vec2 zone_size = vec2(260.0, 180.0);
uniform vec2 rect_size = vec2(380.0, 320.0);
// How much the flow bows. 0 = straight. Matches wind_zone.gd `curve`.
uniform float curve : hint_range(-1.0, 1.0) = 0.0;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - 0.5) * rect_size;
	vec2 edge_dist = rect_size * 0.5 - abs(p);
	float fade = smoothstep(0.0, 42.0, edge_dist.x) * smoothstep(0.0, 42.0, edge_dist.y);

	// Shared arc: bend peaks at the center, anchored to 0 at the inlet/outlet.
	// Clamp to the logical zone so lines straighten (not blow up) in the margin.
	float hw = max(zone_size.x * 0.5, 1.0);
	float amp = curve * zone_size.y * 0.5;
	float nx = clamp(p.x / hw, -1.0, 1.0);
	float bend = amp * (1.0 - nx * nx);
	float slope = -2.0 * amp * nx / hw;
	float inv_len = inversesqrt(1.0 + slope * slope);
	// Vertical coordinate that follows the arc, so rows curve together.
	float py = p.y - bend;

	float streaks = 0.0;

	for (int layer = 0; layer < 2; layer++) {
		float id = float(layer);
		float row_pitch = 32.0 + id * 14.0;
		float shifted = py + id * 40.0;
		float row = floor(shifted / row_pitch);
		float row_id = row + id * 100.0;
		float present = step(0.45 + id * 0.08, hash(row_id + 1.7));

		float y_center = (row + 0.5) * row_pitch - id * 40.0;
		float wave = sin(p.x * 0.03 + TIME * (1.1 + id * 0.35) + row_id) * (1.6 + id * 0.8);
		// Perpendicular distance to the curved centerline keeps the width even.
		float dy = abs(py - y_center - wave) * inv_len;

		float dash_len = mix(55.0, 110.0, hash(row_id + 2.3)) + id * 16.0;
		float gap = mix(40.0, 90.0, hash(row_id + 6.1));
		float period = dash_len + gap;
		float spd = flow_speed * mix(0.72, 1.28, hash(row_id + 3.8)) * (1.0 + id * 0.28);
		float along = mod(p.x - TIME * spd + hash(row_id + 0.4) * period, period);

		float t = clamp(along / max(dash_len, 0.001), 0.0, 1.0);
		float on_dash = step(along, dash_len);
		// Soft tail, pointed tip at the leading end so a still frame still shows direction.
		float profile = smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.7, 1.0, t));
		float thick = max(mix(0.9, 1.7, hash(row_id + 8.2)) * profile, 0.001);
		float core = (1.0 - smoothstep(thick * 0.2, thick, dy)) * on_dash * profile;
		float halo = (1.0 - smoothstep(thick, thick * 2.2, dy)) * on_dash * profile;

		float brightness = mix(0.6, 1.0, hash(row_id + 4.4));
		float layer_fade = mix(1.0, 0.7, id);
		streaks += (core + halo * 0.25) * present * brightness * layer_fade;
	}

	streaks = clamp(streaks, 0.0, 1.0);
	// active only fades the whole layer in/out; the streaks keep moving.
	float alpha = streaks * fade * active;
	COLOR = vec4(wind_color.rgb, alpha);
}
