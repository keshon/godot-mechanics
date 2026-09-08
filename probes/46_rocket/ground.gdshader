shader_type spatial;

// A PLANET IN SQUARES.
//
// The same trick as in the forty-fourth and forty-fifth probes, but on a sphere. The grid is
// taken from the ball's LOCAL coordinates projected onto XZ: the pad stands at the pole, and
// there that projection IS the tangent plane, metre for metre. Towards the equator it
// stretches, but one ascent does not get that far.
//
// The grid is not decoration. Without it neither the climb nor the drift downrange can be
// seen at all, and the probe collapses into reading numbers.

uniform vec3 pale : source_color = vec3(0.30, 0.34, 0.28);
uniform vec3 dark : source_color = vec3(0.21, 0.24, 0.20);
uniform vec3 rule : source_color = vec3(0.62, 0.68, 0.56);
uniform float cell = 500.0;
uniform float major = 5000.0;

varying vec3 local;

void vertex() {
	local = VERTEX;
}

float checker(vec2 p, float size) {
	vec2 q = p / size;
	vec2 w = fwidth(q);
	float fade = clamp(1.0 - max(w.x, w.y) * 2.0, 0.0, 1.0);
	vec2 s = sin(q * 3.14159265);
	return mix(0.5, sign(s.x * s.y) * 0.5 + 0.5, fade);
}

float ruler(vec2 p, float size) {
	vec2 q = abs(fract(p / size - 0.5) - 0.5) * size;
	vec2 w = fwidth(p) * 1.5 + 0.001;
	vec2 l = smoothstep(w, vec2(0.0), q);
	return max(l.x, l.y);
}

void fragment() {
	vec2 p = local.xz;
	vec3 col = mix(dark, pale, checker(p, cell));
	col = mix(col, rule, ruler(p, major) * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
