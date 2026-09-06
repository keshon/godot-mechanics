shader_type spatial;

// Gouraud, not per-pixel: the hardware being imitated lit whole vertices and
// let the rasteriser smear the result across the triangle. Specular did not
// exist. Two words in a render_mode line and half the look is already there.
render_mode vertex_lighting, specular_disabled, diffuse_lambert;

// Where the vertices are allowed to land, in steps of normalised device space.
//
// This is written from the ACTUAL viewport size by Look.gd, not typed in: a
// grid of size/2 puts exactly one step on one rendered pixel, which is what
// the hardware did. The first version of this probe had it fixed at 160x120
// while the viewport was 250x140, so every vertex was being rounded to
// something coarser than a pixel and the wobble came out roughly three times
// too strong. It looked wrong because it was wrong.
uniform vec2 snap_grid = vec2(160.0, 120.0);
uniform bool snap_vertices = true;

// The other half of the look, and the one worth understanding rather than
// copying. See the fragment stage.
uniform bool affine_uv = true;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
// The same image again, sampled smoothly. A sampler's filter is fixed at
// compile time, so switching between sharp and smooth means two of them.
//
// This is what a PS2 did when running a PS1 disc: it left the geometry alone
// and turned bilinear filtering on for the textures. Cleaner, and immediately
// wrong for the era — which is itself worth seeing.
uniform sampler2D albedo_smooth : source_color, filter_linear, repeat_enable;
uniform bool smooth_textures = false;
// How many times the texture repeats across a face. A mesh hands over UVs from
// 0 to 1 whatever its size, so a seventy-metre floor and a two-metre pillar
// both get exactly one tile unless somebody says otherwise. Nothing to do with
// the era being imitated — just the difference between a checkerboard and four
// enormous squares.
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying vec2 uv_over_w;
varying float one_w;


void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);

	if (snap_vertices) {
		// Round the position in normalised device space onto a coarse grid.
		// The console had no sub-pixel precision in its vertex pipeline, so
		// corners could only sit on whole screen positions — and a corner that
		// keeps jumping between two of them is what makes the picture crawl.
		clip.xy = round(clip.xy / clip.w * snap_grid) / snap_grid * clip.w;
	}
	POSITION = clip;

	// Perspective correction, and how to defeat it.
	//
	// The rasteriser does not interpolate a varying linearly across a triangle.
	// It interpolates value/w and 1/w and divides, which is what keeps a
	// checkerboard floor looking flat instead of folded. The console could not
	// afford that division per pixel, so its textures swam.
	//
	// To reproduce the swim: hand the rasteriser UV*w instead of UV. Its own
	// division by w then cancels out, and what arrives at the fragment stage is
	// a plain linear blend in screen space — exactly the wrong answer, exactly
	// the right look.
	uv_over_w = UV * uv_scale * clip.w;
	one_w = clip.w;
}


void fragment() {
	vec2 uv = affine_uv ? uv_over_w / one_w : UV * uv_scale;
	vec4 c = (smooth_textures ? texture(albedo_smooth, uv) : texture(albedo_tex, uv)) * tint;
	ALBEDO = c.rgb;
}
