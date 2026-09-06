shader_type canvas_item;

// The half of water that is not the water.
//
// Metal Gear Solid 2's water was a simple shader. What sold it was everything AROUND
// it: motes hanging in the water, and drops left on the lens when you surfaced. This
// pass is that half — fog, a colour shift, a slow wobble, and drops that dry off.

uniform float submerged : hint_range(0.0, 1.0) = 0.0;
uniform float drops : hint_range(0.0, 1.0) = 0.0;
uniform float wobble : hint_range(0.0, 2.0) = 1.0;
uniform vec4 tint : source_color = vec4(0.10, 0.34, 0.42, 1.0);
uniform float murk : hint_range(0.0, 1.0) = 0.55;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}


void fragment() {
	vec2 uv = SCREEN_UV;

	// the whole picture breathes. tiny, and it is most of "I am under water".
	if (submerged > 0.0) {
		uv += vec2(
			sin(uv.y * 24.0 + TIME * 1.7),
			cos(uv.x * 19.0 + TIME * 1.3)) * 0.0022 * wobble * submerged;
	}

	// drops on the lens: a handful of round lenses that push the image and fade
	float wet = 0.0;
	if (drops > 0.0) {
		for (int i = 0; i < 14; i++) {
			vec2 seed = vec2(float(i) * 3.7, float(i) * 7.1);
			vec2 at = vec2(hash(seed), hash(seed + 11.0));
			float r = 0.012 + 0.028 * hash(seed + 3.0);
			// a drop slides down as it dries
			at.y -= (1.0 - drops) * (0.05 + 0.12 * hash(seed + 5.0));
			float d = distance(vec2(uv.x, uv.y * 0.62), vec2(at.x, at.y * 0.62));
			float m = 1.0 - smoothstep(r * 0.6, r, d);
			if (m > 0.0) {
				uv += normalize(vec2(uv.x, uv.y) - at + 0.0001) * m * r * 1.4 * drops;
				wet = max(wet, m * drops);
			}
		}
	}

	vec3 col = texture(screen_tex, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
	col = mix(col, tint.rgb, murk * submerged);
	col += wet * 0.10;
	COLOR = vec4(col, 1.0);
}
