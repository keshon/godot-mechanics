shader_type spatial;
render_mode cull_disabled;

// The surface, from the same 48 components the physics reads a handful of. Ported from
// worldbox-0/shaders/ocean_waves.gdshaderinc (the wave) and sea_water.gdshader (the
// look: two palettes blended by weather, foam from the jacobian, aerial haze).
//
// Note `wave_time`, not TIME. His shader does the same, with the comment that time has
// to obey pause and time scale, which TIME does not. Here it is also the only way the
// CPU and the GPU can agree at all — they must read the same clock, not two clocks that
// happen to start together.

#define NW 48

uniform int wn = 48;
uniform float steepness = 0.4;
uniform float wave_time = 0.0;
uniform vec2 wdirs[NW];
uniform float wks[NW];
uniform float wamps[NW];
uniform float wphs[NW];
uniform float womg[NW];
uniform float wmr[NW];
uniform float wmp[NW];

// Two palettes with the weather leading between them: turquoise calm and the dull
// grey-green of a blow, where the sky is shut and there is nothing left to light it.
uniform vec3 deep : source_color = vec3(0.008, 0.10, 0.15);
uniform vec3 shallow : source_color = vec3(0.05, 0.38, 0.42);
uniform vec3 crest_col : source_color = vec3(0.28, 0.80, 0.70);
uniform vec3 deep_storm : source_color = vec3(0.03, 0.07, 0.07);
uniform vec3 shallow_storm : source_color = vec3(0.13, 0.22, 0.20);
uniform vec3 crest_storm : source_color = vec3(0.30, 0.40, 0.36);
uniform vec3 foam_col : source_color = vec3(0.95, 0.98, 0.99);
uniform vec3 sky_tint : source_color = vec3(0.60, 0.78, 0.88);

uniform float storm : hint_range(0.0, 1.0) = 0.0;
/// Foam where the horizontal jacobian drops below this: neighbouring particles of water
/// are converging, the crest is folding, and that is where white comes from.
///
/// It has to be CALIBRATED, not guessed. With 48 components and q = steep/(k*a*N) the
/// jacobian never gets near zero — measured minimum in a gale is 0.84, nowhere close to
/// folding — so a fixed threshold either paints nothing or paints everything. The script
/// measures the worst compression on the grid and sets this just above it.
uniform float fold : hint_range(0.2, 1.2) = 0.86;
uniform float fresnel_power = 5.0;
/// AERIAL PERSPECTIVE. Far water goes to the tone of the sky. Without it the horizon
/// line is razor sharp, and a sharp horizon is most of why an ocean reads as a pond.
uniform float haze_dist = 430.0;
uniform float haze_max : hint_range(0.0, 1.0) = 0.72;

varying float jac;
varying float lift;


vec3 wave_disp(vec2 p, float t, out float jacobian) {
	vec3 d3 = vec3(0.0);
	vec4 jac4 = vec4(0.0);
	for (int i = 0; i < wn; i++) {
		vec2 d = wdirs[i];
		float a = wamps[i] * (0.72 + 0.28 * sin(wmr[i] * t + wmp[i]));
		if (a <= 0.0) { continue; }
		float q = steepness / (wks[i] * a * float(wn));
		float ph = wks[i] * dot(d, p) - womg[i] * t + wphs[i];
		float c = cos(ph);
		float s = sin(ph);
		d3.xz += q * a * d * c;
		d3.y += a * s;
		float qka = q * a * wks[i] * s;
		jac4 += vec4(-qka * d.x * d.x, -qka * d.x * d.y, -qka * d.y * d.x, -qka * d.y * d.y);
	}
	jacobian = (1.0 + jac4.x) * (1.0 + jac4.w) - jac4.y * jac4.z;
	return d3;
}


void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float j;
	vec3 o = wave_disp(wp.xz, wave_time, j);
	float e = 0.6;
	float ja;
	vec3 ox = wave_disp(wp.xz + vec2(e, 0.0), wave_time, ja);
	vec3 oz = wave_disp(wp.xz + vec2(0.0, e), wave_time, ja);
	vec3 tx = normalize(vec3(e, 0.0, 0.0) + ox - o);
	vec3 tz = normalize(vec3(0.0, 0.0, e) + oz - o);
	VERTEX += (inverse(MODEL_MATRIX) * vec4(o, 0.0)).xyz;
	NORMAL = normalize(cross(tz, tx));
	jac = j;
	lift = o.y;
}


void fragment() {
	vec3 c_deep = mix(deep, deep_storm, storm);
	vec3 c_shal = mix(shallow, shallow_storm, storm);
	vec3 c_crest = mix(crest_col, crest_storm, storm);

	// height decides the body colour: troughs deep, faces mid, tops lit through
	float up = clamp(lift * 0.30 + 0.5, 0.0, 1.0);
	vec3 col = mix(c_deep, c_shal, smoothstep(0.0, 0.72, up));
	col = mix(col, c_crest, smoothstep(0.68, 1.0, up));

	// foam from the jacobian, not from a guess about height: white appears exactly
	// where the water is folding over itself
	float f = 1.0 - smoothstep(fold, fold + 0.035, jac);
	col = mix(col, foam_col, clamp(f, 0.0, 1.0));

	// grazing angles stop being water and start being sky
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	col = mix(col, sky_tint, fres * (1.0 - f) * 0.85);

	// and far water is sky as well, only for a different reason
	float dist = length(VERTEX);
	col = mix(col, sky_tint, clamp(dist / haze_dist, 0.0, 1.0) * haze_max);

	ALBEDO = col;
	ROUGHNESS = mix(mix(0.02, 0.22, storm), 0.85, clamp(f, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = 0.5 + 0.4 * fres;
}
