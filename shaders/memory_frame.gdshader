shader_type canvas_item;

// Soft, dreamy memory: a heavy blur plus an organic, inky blob border that
// eats into the edges so the picture reads like the splotchy reference frame.
// Blur radius as a fraction of the image, so it is just as heavy on any size
// of PNG (pixel-based offsets vanished on the big memory art).
uniform float blur_amount : hint_range(0.0, 0.5) = 0.22;
// 0 is gray, 1 is the picture's own color.
uniform float saturation : hint_range(0.0, 1.0) = 0.08;
// How far the inky border eats in from each edge (0..0.5).
uniform float border_width : hint_range(0.0, 0.5) = 0.13;
// Width of the soft falloff at the border.
uniform float border_softness : hint_range(0.0, 0.5) = 0.11;
// Size and bite of the noisy splotches around the rim.
uniform float noise_scale : hint_range(0.5, 12.0) = 4.5;
uniform float noise_strength : hint_range(0.0, 0.6) = 0.14;
// How fast the border noise drifts, so the rim shimmers/animates.
uniform float scroll_speed : hint_range(0.0, 2.0) = 0.18;
// Per-memory variation so each border looks a little different.
uniform float seed = 0.0;
// Pixel size of the frame, so the fade follows the picture edges rather than the cropped texture.
uniform vec2 rect_size = vec2(1280.0, 720.0);

varying vec2 local_xy;

float hash(vec2 p) {
	p += seed;
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

// Signed distance to a rounded rectangle, so corners fade the same as the sides.
float rounded_box(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - half_size + vec2(radius);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void vertex() {
	local_xy = VERTEX;
}

void fragment() {
	// COLOR arrives already tinted by the node's modulate, including fade alpha.
	// Keep it and reapply it, since writing COLOR below would otherwise drop the fade.
	vec4 tint = COLOR;
	// Drift the noise over time so the inky rim shimmers instead of sitting still.
	vec2 flow = vec2(TIME * scroll_speed, TIME * scroll_speed * 0.7);
	float n = fbm(UV * noise_scale + flow);
	n += 0.5 * fbm(UV * noise_scale * 2.1 + flow * 1.7 + 11.0);
	n /= 1.5;
	// Measure the fade in pixels from the frame, with the same softness on every side.
	// Texture UVs are cropped, so using them cuts the top and bottom off hard.
	float edge = min(rect_size.x, rect_size.y);
	float inset = edge * border_width;
	float soft = max(edge * border_softness, 1.0);
	vec2 p = local_xy - rect_size * 0.5;
	vec2 half_size = rect_size * 0.5 - vec2(inset + (n - 0.5) * edge * noise_strength);
	float dist = rounded_box(p, half_size, edge * 0.06);
	float mask = 1.0 - smoothstep(0.0, soft, dist);
	// Sampling has to happen here. Godot rejects texture() inside a helper.
	vec4 img = vec4(0.0);
	float weight = 0.0;
	float sigma = max(blur_amount * 0.5, 0.001);
	float step_px = blur_amount / 5.0;
	for (int y = -5; y <= 5; y++) {
		for (int x = -5; x <= 5; x++) {
			vec2 o = vec2(float(x), float(y)) * step_px;
			float w = exp(-dot(o, o) / (2.0 * sigma * sigma));
			img += texture(TEXTURE, UV + o * TEXTURE_PIXEL_SIZE) * w;
			weight += w;
		}
	}
	img /= max(weight, 0.0001);
	float luma = dot(img.rgb, vec3(0.299, 0.587, 0.114));
	img.rgb = mix(vec3(luma), img.rgb, saturation);
	COLOR = img * tint;
	COLOR.a *= mask;
}
