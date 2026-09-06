shader_type spatial;

// ПОВЕРХНОСТЬ. Всё, что происходит МЕЖДУ вершинами.
//
// Правило, из которого растёт весь этот файл: **геометрия обязана совпадать с физикой, а
// затенение — нет.** Поэтому мелкий рельеф здесь не двигает ни одной вершины. Он живёт в
// нормали, и физика о нём не знает — и не должна.
//
// Слои включаются по одному, каждый со своей ценой:
//   1 детальная нормаль   неровность в пределах текселя
//   2 затухание с далью   без него дальние пиксели кипят
//   3 триплanar           текстура не растягивается на обрывах
//   4 слои материала      трава / камень / песок по уклону и высоте
//   5 макро-вариация      ломает видимый повтор тайла
//   6 параллакс           глубина без вершин

/// RGB — нормаль, A — ВЫСОТА. Без `hint_normal`: распаковываю руками, а альфу движок под
/// этим хинтом трогать не обязан.
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray layers_tex : filter_linear_mipmap, repeat_enable;

uniform float detail_on : hint_range(0.0, 1.0) = 1.0;
uniform float fade_on : hint_range(0.0, 1.0) = 1.0;
uniform float triplanar_on : hint_range(0.0, 1.0) = 1.0;
uniform float splat_on : hint_range(0.0, 1.0) = 1.0;
uniform float macro_on : hint_range(0.0, 1.0) = 1.0;
/// ВИД ПАРАЛЛАКСА. Их действительно несколько, и они образуют лестницу «точнее — дороже».
///   0 нет
///   1 классический       одна выборка, смещение пропорционально высоте.
///                        Дёшево и «плывёт» на острых углах: деление на косинус взгляда
///                        уходит в бесконечность, и текстура уезжает.
///   2 с ограничением     то же без деления. Плавания нет, глубина занижена — размен,
///                        который двадцать лет держался в играх как основной.
///   3 крутой марш        шагаем вдоль луча до первого пересечения с рельефом. Честно,
///                        но результат квантован по шагам — видны ступеньки.
///   4 POM                тот же марш плюс линейная интерполяция между последними двумя
///                        шагами. Ступеньки исчезают почти даром.
///   5 рельефное          марш плюс двоичный поиск. Точнее POM на резких перепадах,
///                        стоит лишних выборок.
uniform int pom_mode : hint_range(0, 5) = 0;
/// 1 — выбирать ВСЕ четыре слоя, 0 — только два с наибольшим весом. Приём из настоящих
/// шейдеров рельефа: в любой точке заметны от силы два слоя, остальные умножаются на ноль,
/// но выборка за них уже сделана и оплачена.
uniform float all_layers : hint_range(0.0, 1.0) = 1.0;
/// МОКРАЯ ЗЕМЛЯ. Не украшение, а условие опыта. Мерцание карт нормалей — это прежде всего
/// мерцание БЛИКОВ: усреднённая мипом нормаль плоская, но блик от средней нормали не равен
/// среднему от бликов. На матовой поверхности бликов почти нет, и померить нечего.
uniform float wet : hint_range(0.0, 1.0) = 0.0;

/// Тайлов на метр. Метровый тайл — типичный размер «камешков»; он же даёт видимую решётку,
/// если не разбить её макро-вариацией.
uniform float detail_scale = 1.0;
uniform float detail_strength : hint_range(0.0, 2.0) = 1.0;
/// Где деталь начинает гаснуть и где гаснет совсем. Метры.
uniform float fade_start = 18.0;
uniform float fade_end = 70.0;
uniform float pom_depth : hint_range(0.0, 0.5) = 0.22;
uniform int pom_steps : hint_range(4, 32) = 12;

uniform vec3 c_grass : source_color = vec3(0.25, 0.33, 0.16);
uniform vec3 c_dry : source_color = vec3(0.45, 0.42, 0.25);
uniform vec3 c_rock : source_color = vec3(0.32, 0.30, 0.29);
uniform vec3 c_sand : source_color = vec3(0.62, 0.57, 0.40);
uniform vec3 c_plain : source_color = vec3(0.42, 0.44, 0.42);

varying vec3 v_world;
varying vec3 v_wnorm;


void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


vec3 unpack_n(vec2 uv) {
	vec3 t = texture(detail_tex, uv).xyz * 2.0 - 1.0;
	return normalize(vec3(t.x, t.z, t.y));   // в шейдере ось «вверх» — Y
}


// ДВА МАСШТАБА ПРОТИВ РЕШЁТКИ. Макро-вариация цвета ломает повтор в альбедо — и ничего не
// делает с нормалью. На мокрой земле это видно сразу: блики выстраиваются в правильную
// сетку с периодом тайла, потому что нормаль повторяется буквально.
//
// Лечение — та же карта, взятая второй раз в НЕКРАТНОМ масштабе и под поворотом. Периоды
// не совпадают, и произведение двух решёток решёткой уже не выглядит. Цена — одна лишняя
// выборка; это единственный слой, где повтор ломается по-настоящему.
vec3 detail_n(vec2 uv, float mix_on) {
	vec3 a = unpack_n(uv);
	if (mix_on < 0.5) { return a; }
	vec2 r = vec2(uv.x * 0.771 - uv.y * 0.637, uv.x * 0.637 + uv.y * 0.771) * 0.413;
	vec3 b = unpack_n(r);
	return normalize(vec3(a.x + b.x, a.y * 1.4, a.z + b.z));
}


void fragment() {
	vec3 wn = normalize(v_wnorm);
	float dist = length(v_world - CAMERA_POSITION_WORLD);

	// ЗАТУХАНИЕ — не украшение, а необходимость. Дальний пиксель покрывает много текселей;
	// мип усредняет их до плоской нормали, но БЛИК от усреднённой нормали не равен среднему
	// от бликов, и картинка кипит при движении камеры. Гасим силу детали с расстоянием.
	float fade = mix(1.0, 1.0 - smoothstep(fade_start, fade_end, dist), fade_on);
	float amt = detail_on * detail_strength * fade;

	// ПАРАЛЛАКС СЧИТАЕТ СМЕЩЕНИЕ, а не готовые координаты. Первая версия правила локальную
	// `uv` — и триплanar её просто не читал: он берёт три проекции прямо от мировой позиции.
	// Триплanar включён по умолчанию, поэтому параллакс не делал НИЧЕГО, честно оплачивая
	// себя по времени. Замер: разница картинки между «нет» и «рельефное» — ровно 0.00 при
	// включённом триплanar и 299 при выключенном.
	//
	// Смещение применяется ко ВСЕМУ, что выбирается по этим координатам: к нормали, к
	// верхней проекции триплanar и к слоям материала. Иначе смещается рельеф, но не цвет,
	// и глубина не читается.
	vec2 base_uv = v_world.xz * detail_scale;
	vec2 poff = vec2(0.0);
	if (pom_mode > 0 && amt > 0.01) {
		vec3 vdir = normalize(CAMERA_POSITION_WORLD - v_world);
		float depth = pom_depth * detail_scale;
		if (pom_mode == 1) {
			// КЛАССИЧЕСКИЙ. Деление на вертикальную составляющую взгляда — источник
			// «плавания»: у горизонта она к нулю, смещение к бесконечности.
			float h = texture(detail_tex, base_uv).a;
			poff = -vdir.xz / max(abs(vdir.y), 0.05) * (h - 0.5) * depth;
		} else if (pom_mode == 2) {
			// С ОГРАНИЧЕНИЕМ СМЕЩЕНИЯ. Та же строка без деления: глубина занижена на
			// пологих взглядах, зато ничего не разъезжается.
			float h = texture(detail_tex, base_uv).a;
			poff = -vdir.xz * (h - 0.5) * depth;
		} else {
			// МАРШ, общий для трёх оставшихся видов.
			vec2 dir = vdir.xz / max(abs(vdir.y), 0.20) * depth;
			float step_h = 1.0 / float(pom_steps);
			vec2 duv = -dir * step_h;
			float h = 1.0;
			vec2 cur = base_uv;
			float sampled = texture(detail_tex, cur).a;
			for (int i = 0; i < pom_steps; i++) {
				if (sampled >= h) { break; }
				h -= step_h;
				cur += duv;
				sampled = texture(detail_tex, cur).a;
			}
			if (pom_mode == 3) {
				poff = cur - base_uv;           // крутой марш: как есть, со ступеньками
			} else if (pom_mode == 4) {
				// POM: где именно между двумя последними шагами пересеклись линии
				float prev = texture(detail_tex, cur - duv).a;
				float d1 = sampled - h;
				float d0 = prev - (h + step_h);
				poff = mix(cur, cur - duv, clamp(d1 / max(d1 - d0, 0.0001), 0.0, 1.0)) - base_uv;
			} else {
				// РЕЛЬЕФНОЕ: двоичный поиск внутри последнего шага, пять делений.
				vec2 lo = cur;
				vec2 hi = cur - duv;
				float hl = h;
				float hh = h + step_h;
				for (int i = 0; i < 5; i++) {
					vec2 mid = (lo + hi) * 0.5;
					float hm = (hl + hh) * 0.5;
					if (texture(detail_tex, mid).a >= hm) { hi = mid; hh = hm; }
					else { lo = mid; hl = hm; }
				}
				poff = (lo + hi) * 0.5 - base_uv;
			}
		}
	}
	vec2 uv = base_uv + poff;

	// ТРИПЛАНАР. На обрыве плоская выборка по XZ растягивает текстуру в полосы: шаг по
	// поверхности большой, а по UV — почти нулевой. Три проекции и смешение по нормали
	// решают это ценой трёх выборок вместо одной. Платить стоит только там, где круто.
	vec3 dn;
	if (triplanar_on > 0.5) {
		vec3 w = abs(wn);
		w = w / (w.x + w.y + w.z);
		vec3 nx = detail_n(v_world.zy * detail_scale, macro_on);
		vec3 ny = detail_n(uv, macro_on);   // верхняя проекция — со смещением
		vec3 nz = detail_n(v_world.xy * detail_scale, macro_on);
		dn = normalize(nx * w.x + ny * w.y + nz * w.z);
	} else {
		dn = detail_n(uv, macro_on);
	}

	// Перенос детали в мировые оси через базис от геометрической нормали. Тангенсы у меша
	// не заданы намеренно: для земли с UV по мировым X и Z базис строится тремя строками.
	vec3 T = normalize(vec3(1.0, 0.0, 0.0) - wn * wn.x);
	vec3 B = cross(wn, T);
	vec3 n = normalize(mix(wn, normalize(T * dn.x + B * dn.z + wn * dn.y), amt));

	// СЛОИ МАТЕРИАЛА. Веса от уклона и высоты, а цвет — из массива текстур: каждый слой это
	// своя выборка, и в этом вся его цена. Первая версия смешивала четыре КОНСТАНТЫ, замер
	// показал ноль миллисекунд, и это было честное измерение того, чего я не построил.
	vec3 col;
	if (splat_on > 0.5) {
		float flat_amt = clamp(wn.y, 0.0, 1.0);
		float hn = clamp(v_world.y / 22.0 * 0.5 + 0.5, 0.0, 1.0);
		float w_rock = 1.0 - smoothstep(0.62, 0.82, flat_amt);
		float w_sand = (1.0 - smoothstep(0.30, 0.52, hn)) * (1.0 - w_rock);
		float w_dry = smoothstep(0.62, 0.86, hn) * (1.0 - w_rock);
		float w_grass = max(1.0 - w_rock - w_sand - w_dry, 0.0);
		vec4 w = vec4(w_grass, w_dry, w_rock, w_sand);
		// Слои сдвигаются вместе с нормалью: смещать рельеф, но не цвет — значит показать
		// глубину освещением и тут же опровергнуть её узором.
		vec2 luv = v_world.xz * 0.35 + poff * (0.35 / max(detail_scale, 0.001));
		col = vec3(0.0);
		if (all_layers > 0.5) {
			// НАИВНЫЙ ПУТЬ: четыре выборки всегда, три из них обычно множатся на ноль.
			for (int i = 0; i < 4; i++) {
				col += texture(layers_tex, vec3(luv, float(i))).rgb * w[i];
			}
		} else {
			// ДВА ГЛАВНЫХ. В любой точке заметны от силы два слоя; ищем их индексы и
			// платим только за них. Вес нормируется, иначе поверхность темнеет.
			int i0 = 0;
			for (int i = 1; i < 4; i++) { if (w[i] > w[i0]) { i0 = i; } }
			int i1 = i0 == 0 ? 1 : 0;
			for (int i = 0; i < 4; i++) { if (i != i0 && w[i] > w[i1]) { i1 = i; } }
			float s2 = max(w[i0] + w[i1], 0.0001);
			col = texture(layers_tex, vec3(luv, float(i0))).rgb * (w[i0] / s2)
				+ texture(layers_tex, vec3(luv, float(i1))).rgb * (w[i1] / s2);
		}
	} else {
		col = c_plain;
	}

	// МАКРО-ВАРИАЦИЯ ЦВЕТА. Плавное пятно с периодом в десятки метров поверх метрового
	// тайла. Дешевле некуда — но ломает повтор только в альбедо; за нормаль отвечает
	// второй масштаб в `detail_n`, и включаются они одной и той же клавишей не случайно:
	// поодиночке каждый оставляет решётку видимой в своей половине.
	if (macro_on > 0.5) {
		float m = texture(macro_tex, v_world.xz * 0.006).r;
		col *= mix(0.78, 1.22, m);
	}

	ALBEDO = col;
	// NORMAL в Godot ожидается в осях вида — переводим из мировых.
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float dry_r = mix(0.95, 0.72, clamp(1.0 - wn.y, 0.0, 1.0));
	ROUGHNESS = mix(dry_r, 0.13, wet);
	SPECULAR = mix(0.35, 0.85, wet);
	ALBEDO *= mix(1.0, 0.55, wet);   // мокрое темнее сухого
}
