shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

// Copied verbatim from probe 21 as a TARGET for the panel, not as shared code.
// 21 — water is not one thing. It is six effects stacked, and which ones you turn on
// is what makes an ocean an ocean and a pool a pool. Every one of them has a switch.
//
//   1 waves        the surface moves. Gerstner, not sine: crests sharpen, troughs flatten
//   2 ripples      two scrolling normal maps. this alone is most of "looks wet"
//   3 depth        how much water is between the surface and the floor. THE difference
//                  between a pool and an ocean is one number: how far light gets
//   4 fresnel      steep angle sees through, grazing angle mirrors. the one that makes
//                  it read as a surface rather than as coloured glass
//   5 refract      what is behind, pushed sideways by the normal
//   6 foam         where the floor comes close to the surface

uniform float use_waves : hint_range(0.0, 1.0) = 1.0;
uniform float use_ripple : hint_range(0.0, 1.0) = 1.0;
uniform float use_depth : hint_range(0.0, 1.0) = 1.0;
uniform float use_fresnel : hint_range(0.0, 1.0) = 1.0;
uniform float use_refract : hint_range(0.0, 1.0) = 1.0;
uniform float use_foam : hint_range(0.0, 1.0) = 1.0;
/// paint the water column itself: black at the surface, white at `absorb` metres.
/// the only way to find out whether the depth maths is right is to look at it.
uniform float show_depth : hint_range(0.0, 1.0) = 0.0;

uniform vec4 shallow_col : source_color = vec4(0.30, 0.62, 0.62, 1.0);
uniform vec4 deep_col : source_color = vec4(0.02, 0.10, 0.18, 1.0);
uniform vec4 foam_col : source_color = vec4(0.92, 0.96, 1.0, 1.0);

// how many metres of water it takes to reach the deep colour.
// a swimming pool is clear for tens of metres; a river is opaque in one.
uniform float absorb = 4.0;

uniform float wave_amp = 0.35;
uniform float wave_len = 9.0;
uniform float wave_speed = 1.0;
uniform float wave_steep : hint_range(0.0, 1.0) = 0.6;
uniform int wave_n : hint_range(1, 6) = 4;
uniform float wave_spread : hint_range(0.0, 3.14) = 0.9;
uniform float wave_dir = 0.0;

uniform float ripple_scale = 0.35;
uniform float ripple_strength : hint_range(0.0, 2.0) = 0.6;
uniform float ripple_speed = 0.05;
uniform vec2 flow = vec2(0.0, 0.0);

uniform float foam_depth = 0.6;
/// foam from the WAVE itself, not from the floor. an ocean gets its whitecaps where
/// the crest is steep, and without this the open sea has no white on it at all.
uniform float foam_crest = 0.0;
uniform float refract_amount = 0.35;
uniform float fresnel_power = 5.0;
uniform float water_rough : hint_range(0.0, 0.5) = 0.04;

uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture;

varying vec3 world_pos;
varying float crest;


// Gerstner: points bunch toward the crest instead of riding a plain sine, which is
// why real swell has sharp tops and wide flat troughs.
vec3 gerstner(vec2 p, float t) {
	vec3 sum = vec3(0.0);
	float amp = wave_amp;
	float len = wave_len;
	for (int i = 0; i < wave_n; i++) {
		float ang = wave_dir + (float(i) - float(wave_n) * 0.5) * wave_spread;
		vec2 d = vec2(cos(ang), sin(ang));
		float k = 6.28318 / len;
		float w = sqrt(9.8 * k) * wave_speed;
		float q = wave_steep / (k * amp * float(wave_n));
		float ph = k * dot(d, p) - w * t;
		sum.xz += q * amp * d * cos(ph);
		sum.y += amp * sin(ph);
		amp *= 0.62;
		len *= 0.63;
	}
	return sum * use_waves;
}


void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float e = 0.35;
	vec3 o = gerstner(wp.xz, t);
	vec3 ox = gerstner(wp.xz + vec2(e, 0.0), t);
	vec3 oz = gerstner(wp.xz + vec2(0.0, e), t);

	// normals from three samples of the same function. slower than the analytic
	// derivative and impossible to get wrong, which at four waves is the better trade.
	vec3 a = vec3(0.0, o.y, 0.0) + o;
	vec3 bx = vec3(e, 0.0, 0.0) + ox;
	vec3 bz = vec3(0.0, 0.0, e) + oz;
	vec3 tx = normalize(bx - a);
	vec3 tz = normalize(bz - a);

	VERTEX += (inverse(MODEL_MATRIX) * vec4(o, 0.0)).xyz;
	NORMAL = normalize(cross(tz, tx));
	TANGENT = tx;
	BINORMAL = tz;
	world_pos = wp + o;
	crest = clamp(o.y / max(wave_amp, 0.001), -1.0, 1.0);
}


void fragment() {
	// --- 2. ripples: two sheets at different sizes and speeds, drifting apart ---
	vec2 uv = world_pos.xz * ripple_scale;
	vec2 drift = flow * TIME;
	vec3 n1 = texture(ripples, uv * 1.0 + drift + vec2(0.03, 0.017) * TIME * ripple_speed * 20.0).rgb * 2.0 - 1.0;
	vec3 n2 = texture(ripples, uv * 2.7 + drift * 1.6 - vec2(0.021, 0.041) * TIME * ripple_speed * 20.0).rgb * 2.0 - 1.0;
	vec3 nrm = normalize(mix(vec3(0.0, 0.0, 1.0), normalize(n1 + n2), ripple_strength * use_ripple));
	vec3 world_n = normalize(TANGENT * nrm.x + BINORMAL * nrm.y + NORMAL * nrm.z);
	NORMAL = world_n;

	// --- 3. depth: how much water is between here and whatever is behind it ---
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float column = max(-view.z + VERTEX.z, 0.0);
	float thick = clamp(column / max(absorb, 0.01), 0.0, 1.0) * use_depth;

	// --- 5. refraction: shift what is behind by the normal, less in shallow water ---
	vec2 off = NORMAL.xy * refract_amount * 0.1 * use_refract * clamp(column, 0.0, 1.0);
	vec3 behind = texture(screen_tex, SCREEN_UV + off).rgb;

	vec3 body = mix(shallow_col.rgb, deep_col.rgb, thick);
	vec3 col = mix(behind, body, thick * 0.92 + 0.08);

	// --- 6. foam where the floor comes close ---
	float foam = (1.0 - smoothstep(0.0, max(foam_depth, 0.01), column));
	foam = max(foam, smoothstep(0.55, 0.95, crest) * foam_crest);
	foam *= use_foam;
	foam *= 0.6 + 0.4 * (n1.x + n2.y + 1.0);
	col = mix(col, foam_col.rgb, clamp(foam, 0.0, 1.0));

	// --- 4. fresnel: grazing angles stop being transparent ---
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power) * use_fresnel;

	ALBEDO = col;
	ROUGHNESS = mix(water_rough, 0.0, f);
	METALLIC = 0.0;
	SPECULAR = 0.5 + 0.5 * f;
	ALPHA = clamp(mix(0.35 + 0.65 * thick, 1.0, f), 0.0, 1.0);

	if (show_depth > 0.5) {
		// EMISSION, not ALBEDO: albedo goes through the lighting pass and what you
		// read back is the number times the sun, which is not the number.
		float g = clamp(column / max(absorb, 0.01), 0.0, 1.0);
		ALBEDO = vec3(0.0);
		EMISSION = vec3(g);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		ALPHA = 1.0;
	}
}
