shader_type spatial;
render_mode cull_back;

// Та же раскраска по высоте и уклону, что в тридцать третьей. Здесь у неё вторая работа:
// на восьмибитной карте ступеньки видны прежде всего ОСВЕЩЕНИЕМ, потому что нормаль —
// это разность соседних высот. Ровная заливка их бы спрятала.

uniform float paint : hint_range(0.0, 1.0) = 1.0;
uniform float amplitude = 90.0;
uniform float origin_y = 0.0;
uniform vec3 low : source_color = vec3(0.26, 0.33, 0.19);
uniform vec3 high : source_color = vec3(0.44, 0.42, 0.26);
uniform vec3 rock : source_color = vec3(0.31, 0.30, 0.29);
uniform vec3 snow : source_color = vec3(0.88, 0.91, 0.95);
uniform vec3 plain : source_color = vec3(0.40, 0.42, 0.44);

varying float v_h;
varying float v_flat;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_h = wp.y - origin_y;
	v_flat = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}

void fragment() {
	if (paint < 0.5) {
		ALBEDO = plain;
		ROUGHNESS = 0.9;
	} else {
		float hn = clamp(v_h / max(amplitude, 0.001) * 0.5 + 0.5, 0.0, 1.0);
		float flat_amt = clamp(v_flat, 0.0, 1.0);
		vec3 ground = mix(low, high, smoothstep(0.2, 0.62, hn));
		ground = mix(ground, snow, smoothstep(0.74, 0.93, hn) * smoothstep(0.5, 0.82, flat_amt));
		float rock_amt = 1.0 - smoothstep(0.60, 0.80, flat_amt);
		ALBEDO = mix(ground, rock, rock_amt);
		ROUGHNESS = mix(0.95, 0.6, rock_amt);
	}
}
