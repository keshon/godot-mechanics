shader_type spatial;
render_mode cull_back;

// Раскраска рельефа берётся из ДВУХ величин, и обе уже есть в геометрии: высота вершины и
// наклон нормали. Ни текстур, ни карт материалов — трава внизу и на пологом, камень на
// крутом, снег наверху. Так делают все, у кого нет художника, и это на удивление честно
// выглядит: скала — это не «серый цвет», это участок, куда не держится грунт.

uniform float paint : hint_range(0.0, 1.0) = 1.0;
uniform float amplitude = 45.0;
uniform vec3 grass : source_color = vec3(0.24, 0.34, 0.17);
uniform vec3 dry : source_color = vec3(0.42, 0.40, 0.24);
uniform vec3 rock : source_color = vec3(0.30, 0.29, 0.28);
uniform vec3 snow : source_color = vec3(0.86, 0.89, 0.94);
uniform vec3 plain : source_color = vec3(0.38, 0.40, 0.42);
/// Косинус угла, с которого грунт перестаёт держаться. 0.72 — это примерно 44°.
uniform float rock_slope : hint_range(0.3, 0.98) = 0.72;

varying float v_h;
varying float v_flat;
varying vec3 v_wpos;


void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wpos = wp;
	v_h = wp.y;
	// НОРМАЛЬ В МИРОВЫХ ОСЯХ. В фрагменте NORMAL уже во view space, и «вверх» там зависит
	// от того, куда смотрит камера: уклон бы менялся при повороте головы.
	v_flat = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}


// Дешёвая крапинка, чтобы плоскости не выглядели пластиком. Не текстура — просто функция
// от мировых координат, поэтому она не тянется и не повторяется видимой плиткой.
float speck(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}


void fragment() {
	if (paint < 0.5) {
		ALBEDO = plain;
		ROUGHNESS = 0.9;
	} else {
		float hn = clamp(v_h / max(amplitude, 0.001) * 0.5 + 0.5, 0.0, 1.0);
		// склон: 1 — плоско, 0 — отвесно
		float flat_amt = clamp(v_flat, 0.0, 1.0);
		vec3 ground = mix(dry, grass, smoothstep(0.15, 0.55, hn));
		// снег ложится только туда, где высоко И достаточно полого
		float snow_amt = smoothstep(0.72, 0.92, hn) * smoothstep(0.55, 0.85, flat_amt);
		ground = mix(ground, snow, snow_amt);
		float rock_amt = 1.0 - smoothstep(rock_slope - 0.14, rock_slope + 0.06, flat_amt);
		vec3 col = mix(ground, rock, rock_amt);
		col *= 0.92 + 0.16 * speck(floor(v_wpos.xz * 3.0));
		ALBEDO = col;
		ROUGHNESS = mix(0.95, 0.62, rock_amt);
	}
}
