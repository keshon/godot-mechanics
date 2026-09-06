shader_type spatial;

// One quad, two effects, and they are the same effect.
//
// A shockwave is not a picture of a ring. It is a place where the air is dense
// enough to bend what is behind it — so this shader samples the finished frame
// through an offset and shows THAT. The faint bright edge on top is secondary;
// take it away and the distortion alone still reads as a blast.
//
// blend_mix puts this in the transparent pass, which is the only place where
// hint_screen_texture holds anything worth reading: the opaque world is
// already drawn, the transparent things are not yet.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

// 0 at the moment of the blast, 1 when the ring has reached the quad's edge.
// Driven by a Tween from Boom.gd — the shader knows nothing about time.
uniform float t = 0.0;
// How wide the band is, as a fraction of the radius.
uniform float thickness = 0.14;
// How far the air bends, in screen units. 0.02 is a shimmer, 0.1 is a lens.
uniform float refract = 0.025;
uniform vec4 ring_color : source_color = vec4(1.0, 0.85, 0.6, 0.5);
// Hard edges or soft. The single knob that moves this between the two styles.
uniform float softness = 1.0;


void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;

	// Distance from this pixel to the expanding circle, turned into a band.
	float band = 1.0 - smoothstep(0.0, thickness * softness + 0.001, abs(r - t));
	// And the whole thing fades out as it grows, because energy spreads.
	band *= 1.0 - t;
	if (band < 0.004) {
		discard;
	}

	// Push the sample outward from the centre, hardest in the middle of the
	// band. That is what makes the world behind it appear to swell and snap.
	vec2 offset = normalize(d + vec2(0.0001)) * band * refract;
	vec3 behind = texture(screen_tex, SCREEN_UV + offset).rgb;

	ALBEDO = behind + ring_color.rgb * band * ring_color.a;
	ALPHA = clamp(band * 1.6, 0.0, 1.0);
}
