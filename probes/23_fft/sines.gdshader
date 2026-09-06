shader_type spatial;
render_mode cull_disabled;

// The sum-of-sines surface, copied from probe 22 so this probe can change it without
// touching that one. 48 plane waves added up per vertex.
//
// Everything it can ever show is in that number. The FFT surface next to it carries
// map_size^2 components per cascade — 65536 at 256x256 — for the price of one inverse
// transform, and the difference between the two pictures is almost entirely that.

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

// ПОДПОВЕРХНОСТНОЕ РАССЕЯНИЕ. Гребень тонкий, и когда солнце ЗА ним, свет проходит
// СКВОЗЬ воду и выходит к глазу: гребень светится зелёно-золотым. Это не блик и не
// отражение — условие тут не «нормаль смотрит на солнце», а ровно наоборот.
//
// Солнце приходит УНИФОРМОЙ, а не из light(): у этого шейдера нет своей световой
// функции, а в fragment() направление света движок не отдаёт. Писать light() ради
// одного слагаемого значит взять на себя весь диффуз и блик целиком.
uniform vec3 sun_dir = vec3(-0.45, -0.62, -0.65);  // куда ИДЁТ свет, мировые координаты
uniform float sun_energy = 1.3;
uniform float sss_on = 1.0;
uniform vec3 sss_col : source_color = vec3(0.20, 0.72, 0.48);
uniform float sss_gain : hint_range(0.0, 4.0) = 1.6;
uniform float sss_power : hint_range(1.0, 16.0) = 5.0;
uniform float wave_h = 3.0;   // масштаб высоты: гребень это lift, отнесённый к нему

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

	// Три множителя, и убрать нельзя ни один:
	//   back  — смотрим примерно НА солнце, иначе просвечивать нечему;
	//   thin  — нормаль отвёрнута ОТ солнца, то есть свет идёт сквозь, а не отражается;
	//   crest — только поднятая вода: во впадине толща велика и не просвечивает.
	vec3 sun_v = normalize((VIEW_MATRIX * vec4(-sun_dir, 0.0)).xyz);
	float back = pow(max(dot(-VIEW, sun_v), 0.0), sss_power);
	float thin = pow(0.5 - 0.5 * clamp(dot(sun_v, NORMAL), -1.0, 1.0), 3.0);
	// crest В МЕТРАХ, а не долей высоты. Сперва тут стояло lift/wave_h, то есть 0..1, и
	// замер показал просвет в девяносто раз слабее, чем у аддона: у того на этом месте
	// wave_height + 2.5, а это метры, около 3.5. Обе константы одинаково произвольны —
	// величина просвета ни из чего не выводится, — но раз поверхности сравниваются
	// рядом, они обязаны быть в одном масштабе, иначе сравнивают не воду, а множители.
	float crest = max(0.0, lift + wave_h * 0.85);
	// пена непрозрачна — это воздух в воде, сквозь неё не проходит ничего
	vec3 glow = sss_col * (back * thin * crest * sss_gain * sun_energy * (1.0 - f) * sss_on);

	// and far water is sky as well, only for a different reason
	float dist = length(VERTEX);
	float hz = clamp(dist / haze_dist, 0.0, 1.0) * haze_max;
	col = mix(col, sky_tint, hz);

	ALBEDO = col;
	// В ЭМИССИЮ, а не в альбедо. Этот свет уже прошёл сквозь воду — освещать его второй
	// раз нечем. В альбедо он был бы погашен ровно там, где должен быть виден: на грани,
	// отвёрнутой от солнца. Дымка гасит его наравне со всем остальным.
	EMISSION = glow * (1.0 - hz);
	ROUGHNESS = mix(mix(0.02, 0.22, storm), 0.85, clamp(f, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = 0.5 + 0.4 * fres;
}
