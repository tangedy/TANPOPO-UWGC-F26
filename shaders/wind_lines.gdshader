shader_type canvas_item;

// Short streaks that travel along the zone's flow. The flow bows along a
// parabolic arc controlled by `curve`, and the push field in wind_zone.gd
// samples the same arc so the visuals match the force.
// The quad (rect_size) is padded larger than the logical wind area (zone_size)
// so the bow and the line ends fade out instead of being clipped by the edge.
uniform vec4 wind_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flow_speed = 80.0;
uniform float active : hint_range(0.0, 1.0) = 1.0;
// 1.0 while turning on/steady (fill), 0.0 while turning off (empty). Both
// sweep along the flow axis from the end back to the start.
uniform float fill_mode : hint_range(0.0, 1.0) = 1.0;
uniform vec2 zone_size = vec2(260.0, 180.0);
uniform vec2 rect_size = vec2(380.0, 320.0);
// How much the flow bows. 0 = straight. Matches wind_zone.gd `curve`.
uniform float curve : hint_range(-1.0, 1.0) = 0.0;
// When on, streaks rise (local up) instead of traveling along local right.
uniform float upward = 0.0;
// Multiplier on how far apart the streaks sit. 1 keeps the wind-zone spacing.
uniform float line_gap = 1.0;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - 0.5) * rect_size;
	vec2 edge_dist = rect_size * 0.5 - abs(p);
	float fade = smoothstep(0.0, 42.0, edge_dist.x) * smoothstep(0.0, 42.0, edge_dist.y);

	// Updraft reuses the same streaks, with shader +X mapped onto local up.
	vec2 flow = p;
	vec2 flow_zone = zone_size;
	if (upward > 0.5) {
		flow = vec2(-p.y, p.x);
		flow_zone = vec2(zone_size.y, zone_size.x);
	}

	// Shared arc: bend peaks at the center, anchored to 0 at the inlet/outlet.
	// Clamp to the logical zone so lines straighten (not blow up) in the margin.
	float hw = max(flow_zone.x * 0.5, 1.0);
	float amp = curve * flow_zone.y * 0.5;
	float nx = clamp(flow.x / hw, -1.0, 1.0);
	float bend = amp * (1.0 - nx * nx);
	float slope = -2.0 * amp * nx / hw;
	float inv_len = inversesqrt(1.0 + slope * slope);
	// Vertical coordinate that follows the arc, so rows curve together.
	float py = flow.y - bend;

	float streaks = 0.0;

	for (int layer = 0; layer < 1; layer++) {
		float id = float(layer);
		float row_pitch = 88.0 * max(line_gap, 0.25);
		float shifted = py;
		float row = floor(shifted / row_pitch);
		float row_id = row;
		float present = 1.0;

		float y_center = (row + 0.5) * row_pitch;
		float wave = sin(flow.x * 0.03 + TIME * (1.1 + id * 0.35) + row_id) * (1.6 + id * 0.8);
		// Perpendicular distance to the curved centerline keeps the width even.
		float dy = abs(py - y_center - wave) * inv_len;

		float dash_len = mix(120.0, 220.0, hash(row_id + 2.3)) + id * 28.0;
		float gap = mix(48.0, 96.0, hash(row_id + 6.1));
		float period = dash_len + gap;
		float spd = flow_speed * mix(0.72, 1.28, hash(row_id + 3.8)) * (1.0 + id * 0.28);
		float along = mod(flow.x - TIME * spd + hash(row_id + 0.4) * period, period);

		float t = clamp(along / max(dash_len, 0.001), 0.0, 1.0);
		float on_dash = step(along, dash_len);
		// Soft tail, pointed tip, same shape as the path streaks.
		float profile = smoothstep(0.0, 0.16, t) * (1.0 - smoothstep(0.78, 1.0, t));
		float thick = max(mix(2.6, 3.8, hash(row_id + 8.2)) * profile, 0.001);
		float core = (1.0 - smoothstep(thick * 0.28, thick, dy)) * on_dash * profile;
		float halo = (1.0 - smoothstep(thick, thick * 2.3, dy)) * on_dash * profile;

		float brightness = mix(0.75, 0.9, hash(row_id + 4.4));
		float layer_fade = mix(1.0, 0.85, id);
		streaks += (core + halo * 0.38) * present * brightness * layer_fade;
	}

	streaks = clamp(streaks, 0.0, 1.0);

	// Directional reveal along the flow axis: ax = 0 at the start, 1 at the end.
	// A wide edge makes the front a broad gradient, so lines fade smoothly
	// in/out as it sweeps instead of popping on/off.
	float ax = clamp(-flow.x / max(flow_zone.x, 1.0) + 0.5, 0.0, 1.0);
	float e = 0.55;
	// Turning on: fill the visible band from the end (ax=1) back to the start.
	float front = mix(1.0 + e, -e, active);
	float m_fill = smoothstep(front - e, front + e, ax);
	// Turning off: empty the band from the end back to the start too.
	float ef = mix(-e, 1.0 + e, active);
	float m_empty = smoothstep(ef + e, ef - e, ax);
	float reveal = mix(m_empty, m_fill, fill_mode);

	float alpha = streaks * fade * reveal * wind_color.a;
	// COLOR starts as this node's modulate, including parents. Keep it so the
	// inspector tint and alpha actually affect the streaks.
	COLOR = vec4(wind_color.rgb, alpha) * COLOR;
}
