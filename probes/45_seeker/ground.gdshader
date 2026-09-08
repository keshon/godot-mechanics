shader_type spatial;

// GROUND IN SQUARES.
//
// A plane with no texture gives neither speed nor scale: you fly over it and cannot tell
// whether you are moving. The grid comes from WORLD coordinates rather than from UV, so it
// does not depend on the size of the mesh, does not tile, and stays the same however far the
// plane is stretched.
//
// The fwidth fade is not optional. Without it the grid turns into moire at range, shimmers
// with every movement of the camera and reads as something broken.

uniform vec3 pale : source_color = vec3(0.36, 0.38, 0.34);
uniform vec3 dark : source_color = vec3(0.28, 0.30, 0.27);
uniform vec3 rule : source_color = vec3(0.52, 0.55, 0.50);
uniform float cell = 50.0;
uniform float major = 500.0;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Checkerboard out of sines: the sign of the product gives a square without a branch, and the
// width of the derivative says how many squares landed in one pixel. Past one, go grey.
float checker(vec2 p, float size) {
	vec2 q = p / size;
	vec2 w = fwidth(q);
	float fade = clamp(1.0 - max(w.x, w.y) * 2.0, 0.0, 1.0);
	vec2 s = sin(q * 3.14159265);
	return mix(0.5, sign(s.x * s.y) * 0.5 + 0.5, fade);
}

// Coarse rules on top: they are what makes distance readable in hundreds of metres.
float ruler(vec2 p, float size) {
	vec2 q = abs(fract(p / size - 0.5) - 0.5) * size;
	vec2 w = fwidth(p) * 1.5 + 0.001;
	vec2 l = smoothstep(w, vec2(0.0), q);
	return max(l.x, l.y);
}

void fragment() {
	vec2 p = world.xz;
	vec3 col = mix(dark, pale, checker(p, cell));
	ALBEDO = mix(col, rule, ruler(p, major) * 0.55);
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
