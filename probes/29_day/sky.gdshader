shader_type sky;

// 29 — a sky that is computed, not painted.
//
// ProceduralSkyMaterial is three colours and a blur. It cannot make a sunset, because a
// sunset is not a colour: it is what is LEFT of white light after it has crossed a long
// stretch of air. Blue scatters out of the beam first, so the beam that survives goes
// orange, and the sky opposite the sun goes deep. One rule, both effects.
//
// This is the cheap single-scattering approximation: two scattering coefficients, two
// phase functions, and a flat-earth guess at how much air a ray crosses. Not physically
// exact — it ignores multiple scattering, ozone and curvature — but every colour it makes
// comes from the geometry rather than from a gradient somebody chose.

// Rayleigh scatters short wavelengths hard: blue about six times more than red. This
// single vector is the reason the sky is blue AND the reason the sun is orange at dusk.
uniform vec3 beta_rayleigh = vec3(5.8, 13.5, 33.1);
uniform vec3 beta_mie = vec3(21.0, 21.0, 21.0);
uniform float thickness : hint_range(0.1, 8.0) = 2.2;
/// Mie asymmetry: how strongly haze throws light FORWARD. This is the halo around the sun.
uniform float mie_g : hint_range(0.0, 0.95) = 0.76;
uniform float sun_size : hint_range(0.001, 0.06) = 0.008;
uniform float exposure : hint_range(0.1, 6.0) = 1.0;
/// Absolute brightness has no natural scale here: the coefficients are in the right RATIO
/// to each other, which is what makes the colours, but the overall level is ours to pick.
/// First guess was twelve and blew the whole scene to white — the sky is the ambient light,
/// so its level is not a matter of taste, it is the scene's exposure.
uniform float scatter_gain : hint_range(0.1, 12.0) = 0.85;
uniform float sun_gain : hint_range(1.0, 120.0) = 25.0;
/// How far below the horizon the sun still lights the sky. A flat-earth optical depth goes
/// to infinity the moment the sun sets, and twilight dies instantly — which is wrong, and
/// wrong in the one hour worth having. The floor is the stand-in for curvature.
uniform float twilight : hint_range(0.02, 0.4) = 0.15;

uniform vec3 night_colour : source_color = vec3(0.012, 0.020, 0.045);
uniform float star_amount : hint_range(0.0, 2.0) = 1.0;
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float moon_size : hint_range(0.0, 0.1) = 0.022;
uniform vec3 ground_colour : source_color = vec3(0.06, 0.06, 0.07);

// THREE MODELS OF THE SAME SKY. Not variations on a look — three different answers to
// "where does the colour come from", and they disagree in instructive ways.
//   0 РАССЕЯНИЕ  single scattering, computed. Colour follows from geometry.
//   1 ПРИШЕМ     the 1999 analytic fit: a formula whose coefficients were regressed
//                against measured skies. No physics inside, but it carries MULTIPLE
//                scattering, because the real skies it was fitted to had it.
//   2 ГРАДИЕНТ   two colours per key hour, interpolated. What most shipped games use.
uniform int model : hint_range(0, 2) = 0;
/// Preetham's one dial: how much haze. 2 is an alpine day, 6 a city, 10 a dust storm.
uniform float turbidity : hint_range(1.8, 10.0) = 2.8;
uniform float preetham_gain : hint_range(0.001, 0.2) = 0.028;
uniform vec3 ramp_zenith_day : source_color = vec3(0.09, 0.20, 0.46);
uniform vec3 ramp_horizon_day : source_color = vec3(0.55, 0.68, 0.85);
uniform vec3 ramp_zenith_dusk : source_color = vec3(0.10, 0.10, 0.22);
uniform vec3 ramp_horizon_dusk : source_color = vec3(0.85, 0.40, 0.18);
uniform vec3 ramp_glow : source_color = vec3(1.0, 0.55, 0.20);


vec3 xyY_to_rgb(float x, float y, float Y) {
	float iy = 1.0 / max(y, 1e-4);
	vec3 XYZ = vec3(x * Y * iy, Y, (1.0 - x - y) * Y * iy);
	return mat3(vec3(3.2406, -0.9689, 0.0557),
		vec3(-1.5372, 1.8758, -0.2040),
		vec3(-0.4986, 0.0415, 1.0570)) * XYZ;
}


/// The Perez function: five coefficients, one for darkening towards the zenith and one for
/// brightening towards the sun. Every analytic sky since 1999 is this shape.
float perez(vec3 abc, vec2 de, float ct, float cg, float g) {
	return (1.0 + abc.x * exp(abc.y / max(ct, 0.02)))
		* (1.0 + abc.z * exp(de.x * g) + de.y * cg * cg);
}


vec3 preetham(vec3 dir, vec3 sun, float T) {
	float ct = max(dir.y, 0.02);
	float cts = max(sun.y, 0.02);
	float ts = acos(clamp(cts, 0.0, 1.0));
	float cg = dot(dir, sun);
	float g = acos(clamp(cg, -1.0, 1.0));

	vec3 aY = vec3(0.1787 * T - 1.4630, -0.3554 * T + 0.4275, -0.0227 * T + 5.3251);
	vec2 dY = vec2(0.1206 * T - 2.5771, -0.0670 * T + 0.3703);
	vec3 ax = vec3(-0.0193 * T - 0.2592, -0.0665 * T + 0.0008, -0.0004 * T + 0.2125);
	vec2 dx = vec2(-0.0641 * T - 0.8989, -0.0033 * T + 0.0452);
	vec3 ay = vec3(-0.0167 * T - 0.2608, -0.0950 * T + 0.0092, -0.0079 * T + 0.2102);
	vec2 dy = vec2(-0.0441 * T - 1.6537, -0.0109 * T + 0.0529);

	float t2 = ts * ts;
	float t3 = t2 * ts;
	float T2 = T * T;
	float xz = (0.00166 * t3 - 0.00375 * t2 + 0.00209 * ts) * T2
		+ (-0.02903 * t3 + 0.06377 * t2 - 0.03202 * ts + 0.00394) * T
		+ (0.11693 * t3 - 0.21196 * t2 + 0.06052 * ts + 0.25886);
	float yz = (0.00275 * t3 - 0.00610 * t2 + 0.00317 * ts) * T2
		+ (-0.04214 * t3 + 0.08970 * t2 - 0.04153 * ts + 0.00516) * T
		+ (0.15346 * t3 - 0.26756 * t2 + 0.06670 * ts + 0.26688);
	float chi = (4.0 / 9.0 - T / 120.0) * (PI - 2.0 * ts);
	float Yz = (4.0453 * T - 4.9710) * tan(chi) - 0.2155 * T + 2.4192;

	float Y = Yz * perez(aY, dY, ct, cg, g) / perez(aY, dY, 1.0, cts, ts);
	float x = xz * perez(ax, dx, ct, cg, g) / perez(ax, dx, 1.0, cts, ts);
	float y = yz * perez(ay, dy, ct, cg, g) / perez(ay, dy, 1.0, cts, ts);
	return max(xyY_to_rgb(x, y, max(Y, 0.0)), vec3(0.0));
}


/// What most games ship: two colours per key hour and a blend. No model, no coefficients —
/// and complete control, which is the point. A stylised game wants its sky under art
/// direction, not under physics.
vec3 ramp(vec3 dir, vec3 sun, float cg) {
	float t = clamp(sun.y * 2.4 + 0.30, 0.0, 1.0);
	vec3 zen = mix(ramp_zenith_dusk, ramp_zenith_day, smoothstep(0.20, 0.80, t));
	vec3 hor = mix(ramp_horizon_dusk, ramp_horizon_day, smoothstep(0.20, 0.80, t));
	vec3 c = mix(hor, zen, pow(clamp(dir.y, 0.0, 1.0), 0.42));
	return c + ramp_glow * pow(max(cg, 0.0), 9.0) * (1.0 - t) * 0.9;
}


float rayleigh_phase(float mu) {
	return 3.0 / (16.0 * PI) * (1.0 + mu * mu);
}

/// Henyey-Greenstein: the forward lobe that makes the glow around the sun.
float mie_phase(float mu, float g) {
	float g2 = g * g;
	return 3.0 / (8.0 * PI) * ((1.0 - g2) * (1.0 + mu * mu))
		/ ((2.0 + g2) * pow(1.0 + g2 - 2.0 * g * mu, 1.5));
}

float stars(vec3 d) {
	// a hash on the direction, thresholded hard: most of the sky is empty
	vec3 p = floor(d * 260.0);
	float h = fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	return smoothstep(0.9975, 1.0, h);
}


void sky() {
	vec3 dir = EYEDIR;
	vec3 sun = LIGHT0_DIRECTION;
	float mu = dot(dir, sun);

	// HOW MUCH AIR. A ray going straight up crosses one atmosphere; one going along the
	// horizon crosses many. The flat-earth 1/cos is wrong below the horizon and right
	// enough above it, which is where we look.
	float air_view = thickness / max(dir.y + 0.06, 0.06);
	float air_sun = thickness / max(sun.y + twilight, twilight);

	vec3 br = beta_rayleigh * 1e-1;
	vec3 bm = beta_mie * 1e-2;
	// What survives the trip: this is where the sunset comes from. When the sun is low,
	// air_sun is huge, blue is gone from the beam entirely, and only red is left to scatter.
	vec3 through = exp(-(br + bm) * (air_view + air_sun) * 0.1);

	vec3 col;
	if (model == 1) {
		col = preetham(dir, sun, turbidity) * preetham_gain;
	} else if (model == 2) {
		col = ramp(dir, sun, mu);
	} else {
		col = (br * rayleigh_phase(mu) + bm * mie_phase(mu, mie_g))
			* air_view * (1.0 - through) * scatter_gain;
	}
	// The disk is shared and is NOT multiplied by LIGHT0_COLOR: the light's colour is now
	// derived from the same transmittance the sky uses, so applying both would redden the
	// sunset twice over.
	float disc = smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.4, mu);
	col += through * disc * sun_gain;

	// NIGHT is not day turned down. Air still scatters, but there is nothing left to
	// scatter, so what remains is a floor colour plus point sources.
	float night = smoothstep(0.06, -0.12, sun.y);
	float mm = dot(dir, -normalize(moon_dir));
	float moon = smoothstep(1.0 - moon_size, 1.0 - moon_size * 0.5, mm);
	col += night * (night_colour
		+ vec3(stars(dir) * star_amount) * smoothstep(0.0, 0.25, dir.y)
		+ vec3(0.85, 0.87, 0.95) * moon * 3.0);

	// below the horizon there is ground, not sky, and leaving it black gives away that the
	// world is a box with a lid
	col = mix(col, ground_colour * (0.25 + 0.75 * (1.0 - night)),
		smoothstep(0.02, -0.06, dir.y));

	COLOR = col * exposure;
}
