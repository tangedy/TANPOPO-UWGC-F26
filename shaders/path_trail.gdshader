shader_type canvas_item;

// Three (or so) soft streaks traveling along a Line2D. UV.x runs the length
// of the path, so the motion happens here instead of rebuilding geometry.
uniform float trail_count = 3.0;
uniform float portion = 0.15;
uniform float flow = 0.04;
uniform float trail_alpha = 0.55;
// Dissolve wipe: 0 shows the whole streak, 1 has fully faded from the end back to the start.
uniform float wipe = 0.0;
// When 0 or more, drive the streak head ourselves instead of looping on TIME.
uniform float head_override = -1.0;
// How much of the streak's rear fades in. Small is a hard cut, larger is a soft start.
uniform float tail_soft = 0.04;

void fragment() {
	float along = UV.x;
	float across = abs(UV.y * 2.0 - 1.0);
	bool manual = head_override >= 0.0;
	float head0 = manual ? head_override : fract(TIME * flow);
	float spacing = 1.0 / max(trail_count, 1.0);
	float profile = 0.0;

	for (int i = 0; i < 6; i++) {
		if (float(i) >= trail_count) {
			break;
		}
		float head = manual ? head0 : fract(head0 + spacing * float(i));
		float back = manual ? (head - along) : fract(head - along);
		float t = 1.0 - back / max(portion, 0.0001);
		float band = manual ? step(0.0, back) * step(back, portion) : step(back, portion);
		float shaped = smoothstep(0.0, tail_soft, t) * (1.0 - smoothstep(0.96, 1.0, t));
		profile = max(profile, shaped * band);
	}

	float edge = 1.0 - smoothstep(0.15, 1.0, across);
	// Fade runs from the end (along = 1) back to the start as wipe climbs.
	float threshold = 1.0 - wipe;
	float keep = 1.0 - smoothstep(threshold - 0.12, threshold, along);
	COLOR = vec4(1.0, 1.0, 1.0, profile * edge * trail_alpha * keep) * COLOR;
}
