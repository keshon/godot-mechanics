shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Два эффекта в одном файле, потому что оба — светящаяся геометрия без освещения, и
// различает их одна ветка.
//
//   0 ВСПЫШКА  горящий пороховой газ, вылетающий из ствола. Не картинка «звёздочка», а
//              форма: плотное ядро у среза и лепестки газа вокруг.
//   1 РОСЧЕРК  искра или трассер. Цвет приходит из частицы (COLOR), геометрию уже
//              вытянул процессный шейдер — здесь остаётся только светить.
//
// ПЛАМЕГАСИТЕЛЬ не гасит пламя. Он рассекает струю газа на несколько расходящихся
// потоков, и та же энергия распределяется по большему объёму: вспышка становится шире,
// тусклее и короче, а главное — гораздо менее заметной СО СТОРОНЫ СТРЕЛКА. Поэтому
// hider = 1 не убавляет яркость целиком, а меняет форму.

uniform int mode : hint_range(0, 1) = 0;
uniform float age : hint_range(0.0, 1.0) = 0.0;
uniform float hider : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;
uniform float gain : hint_range(0.5, 12.0) = 4.5;
/// Направление ствола В ЭКРАННОЙ ПЛОСКОСТИ. Билборд всегда смотрит на камеру, поэтому
/// «вперёд» у него само по себе не определено — а пламя вылетает именно вперёд. Отсюда
/// вектор передаётся снаружи: смотришь вдоль ствола — его длина ноль и вспышка выходит
/// симметричной звездой; смотришь сбоку — она вытягивается в язык. Обе картинки на рефах
/// есть, и это одна и та же вспышка с двух точек зрения.
uniform vec2 barrel_screen = vec2(1.0, 0.0);
uniform float cone_len : hint_range(0.0, 3.0) = 2.1;
uniform float fat : hint_range(0.5, 1.6) = 0.88;
uniform vec3 core_colour : source_color = vec3(1.0, 0.93, 0.66);
uniform vec3 gas_colour : source_color = vec3(1.0, 0.48, 0.13);

varying vec3 vcol;


void vertex() {
	vcol = COLOR.rgb * COLOR.a;
	if (mode == 0) {
		// billboard, keeping the node's own scale: the flash has to face the eye whichever
		// way the barrel points, but its size is set by the gun, not by the camera
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		float sx = length(MODEL_MATRIX[0].xyz);
		float sy = length(MODEL_MATRIX[1].xyz);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(sx, 0.0, 0.0, 0.0), vec4(0.0, sy, 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
}


// NOT `return` inside fragment(): Godot's shader language forbids it in a processor
// function outright — "Using 'return' in the 'fragment' processor function is incorrect".
// The two modes have to be an if/else, not an early exit.
void fragment() {
	vec3 col;
	if (mode == 1) {
		col = vcol * gain;
	} else {
		vec2 p = UV * 2.0 - 1.0;
		// Система координат ствола на экране: q.x вдоль него, q.y поперёк. Растягиваем
		// ТОЛЬКО вперёд (step по q.x) — назад из дула ничего не летит.
		float along = length(barrel_screen);
		vec2 ax = along > 0.02 ? barrel_screen / along : vec2(1.0, 0.0);
		vec2 q = vec2(dot(p, ax), dot(p, vec2(-ax.y, ax.x)));
		float sx = 1.0 + along * cone_len * step(0.0, q.x);
		vec2 e = vec2(q.x / sx, q.y);
		float r = length(e);
		float a = atan(e.y, e.x);

		// Жизнь вспышки — две-три сотых секунды, и за это время она успевает раздуться и
		// погаснуть. Раздувается быстро, гаснет медленнее: газ вылетает разом, а светит,
		// пока не остынет.
		float grow = 0.35 + 0.65 * smoothstep(0.0, 0.25, age);
		float fade = 1.0 - smoothstep(0.35, 1.0, age);

		// ЛЕПЕСТКИ. Без пламегасителя — три-четыре широких языка и длинный вынос вперёд.
		// С ним — шесть-восемь коротких, расходящихся: та же энергия, больший телесный угол.
		float petals = mix(3.0, 7.0, hider);
		// Лепестки толще: базовый радиус больше, а модуляция мягче — на рефах языки газа
		// широкие и мясистые, а не тонкие лучи.
		// Модуляция сильнее толщины: языки должны читаться по отдельности, иначе вспышка
		// сливается в круглый ком. На рефах видно ровно это — жирные, но РАЗДЕЛЬНЫЕ лепестки.
		float ragged = (0.78 + 0.34 * sin(a * petals + seed * 6.2831853)
			+ 0.14 * sin(a * (petals * 2.0 + 1.0) - seed * 11.0)) * fat;
		float reach = mix(1.0, 0.62, hider) * grow;
		// Мягкий край вместо резкого: газ не имеет границы, он редеет.
		float gas = (1.0 - smoothstep(ragged * reach * 0.25, ragged * reach, r))
			* mix(1.0, 0.6, hider);

		// ЯДРО — плотный горящий газ у самого среза. Оно и даёт ту «дырку в экране», по
		// которой вспышка узнаётся; без него остаётся мягкое пятно, и выстрел ватный.
		float core = 1.0 - smoothstep(0.0, mix(0.34, 0.48, hider) * grow, r);

		col = (gas_colour * gas + core_colour * core * mix(3.2, 1.4, hider)) * gain * fade;
	}
	// ALPHA — это ЯРКОСТЬ, а не единица. blend_add в Godot складывает не только цвет, но и
	// альфу: ALPHA = 1.0 записывает единицу в альфа-канал, и на прозрачном SubViewport
	// (где фон 0,0,0,0) весь квад становится НЕПРОЗРАЧНЫМ ЧЁРНЫМ прямоугольником — там,
	// где пламени нет. В обычном мире это незаметно: альфу кадра никто не читает.
	// Деление возвращает вклад ровно к col, так что картинка не темнеет.
	float bright = clamp(max(col.r, max(col.g, col.b)), 0.0, 1.0);
	ALBEDO = col / max(bright, 0.001);
	ALPHA = bright;
}
