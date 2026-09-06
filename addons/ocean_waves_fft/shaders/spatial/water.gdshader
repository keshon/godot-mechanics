shader_type spatial;
// ПРАВКА WORLDBOX: добавлены blend_mix и depth_draw_always — без прозрачного прохода
// нельзя прочитать сцену ЗА водой, а значит нет ни прозрачности, ни подводного вида.
// depth_draw_always обязателен: вода по-прежнему должна писать глубину, иначе брызги и
// прочая полупрозрачная мелочь теряют сортировку относительно поверхности.
// cull_disabled — чтобы поверхность была видна СНИЗУ: без неё из-под воды небо и волны
// просто исчезают, и подводного режима не существует.
render_mode world_vertex_coords, shadows_disabled, blend_mix, depth_draw_always, cull_disabled;
/**
 * Water lighting model roughly follows the 2019 GDC talk: "Wakes, Explosions and Lighting: Interactive Water Simulation in Atlas".
 * Source: https://gpuopen.com/gdc-presentations/2019/gdc-2019-agtd6-interactive-water-simulation-in-atlas.pdf
 */

#define MAX_CASCADES 8    // I am unsure how to generalize this.
#define REFLECTANCE  0.02 // Reflectance from air to water (eta=1.33).

global uniform vec4 water_color : source_color;
global uniform vec4 foam_color : source_color;

uniform float roughness : hint_range(0.0, 1.0) = 0.4;
// ПРАВКА WORLDBOX (см. addons/ocean_waves_fft/README.md). Полоса горизонта: тон неба по
// азимуту, свёрнутый из HDR-панорамы в текстуру 64×1 (печёт OceanEnvironment). Штатное
// отражение здесь целиком отдано радиансу Godot, а он на скользящих углах размывается
// шероховатостью по огромному телесному углу — азимутальная разница усредняется в один
// тон, и вода у горизонта не совпадает с небом за ней. sky_strip_on = 0 -> ведём себя
// ровно как оригинал.
uniform sampler2D sky_strip : source_color, filter_linear, repeat_enable;
uniform float sky_strip_on = 0.0;
uniform float sky_strip_gain = 1.0;  // яркость полосы = яркость панорамы (Home/End)
// ПРАВКА WORLDBOX: ПРОЗРАЧНОСТЬ ПО ТОЛЩИНЕ СЛОЯ.
// Вода была плёнкой без толщины — отсюда ни прозрачности, ни возможности разглядеть
// подводную часть корпуса. Меряем расстояние от поверхности до того, что за ней (глубина
// сцены минус глубина фрагмента) и гасим по Беру-Ламберту: тонкий слой прозрачен, толстый
// непрозрачен сам собой. В открытом море дна нет, сцена уходит в бесконечность, толщина
// огромна — вода честно остаётся глухой, и лишней работы это не создаёт. Смысл виден там,
// где ему и место: у бортов, где корпус уходит под воду.
// water_absorb — обратная длина затухания (1/м) по каналам: красный гаснет первым, синий
// живёт дольше всех, отсюда и цвет глубины.
uniform vec3 water_absorb = vec3(0.55, 0.22, 0.14);
uniform float transparency_on = 0.0;   // 0 -> ведём себя ровно как оригинал
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// Сила преломления. Смещение растёт с толщиной слоя: у самой кромки искажать нечего,
// на глубине — есть что. Ограничено, иначе на краях экрана тянутся артефакты.
uniform float refraction = 0.30;
uniform float haze_dist = 1100.0;    // воздушная перспектива: размывает линию горизонта
uniform float haze_max = 0.9;
uniform float normal_strength : hint_range(0.0, 1.0) = 1.0; // Global normal strength
// ПРАВКА WORLDBOX: РУЧКА НА ПОДПОВЕРХНОСТНОЕ РАССЕЯНИЕ.
// Слагаемое в light() у автора есть (sss_height), но константа 1.0 вшита в код, а без
// возможности выключить его нельзя ни увидеть, ни сравнить: глазом не отличить «эффекта
// нет» от «эффект есть, но условия не те». sss_gain = 1.0 -> ведём себя ровно как
// оригинал, 0.0 -> просвет выключен начисто.
uniform float sss_gain : hint_range(0.0, 6.0) = 1.0;
// ПРАВКА WORLDBOX: ЦВЕТ ВОДЫ В ПРЯМОМ СВЕТЕ.
// При своей light() Godot НЕ умножает DIFFUSE_LIGHT на ALBEDO — это обязан сделать сам
// шейдер. Автор подмешал цвет только для пены, а слагаемое lambertian осталось чисто
// белым. Оно растёт как sin высоты солнца, поэтому при высоком солнце вся поверхность
// белеет: замер показал серость 0.97 (почти идеальный серый) при густо-синем альбедо.
// Умножать на само water_color нельзя — оно тёмное (0.010, 0.020, 0.027), вода стала бы
// чёрной. Берём его ТОН: цвет, нормированный по максимальному каналу, — яркость прежняя,
// оттенок водяной. 0.0 -> ведём себя ровно как оригинал.
uniform float diffuse_tint : hint_range(0.0, 1.0) = 0.0;
// ПРАВКА WORLDBOX: ЦВЕТ ПО ГЛУБИНЕ И ПРИБОЙ У КРОМКИ.
// Затухание по Беру-Ламберту гасит свет, но не КРАСИТ воду: water_color один на всё,
// поэтому мель отличалась от глубины только яркостью. В природе наоборот — мель светлая
// бирюзовая: путь света короткий, он успевает рассеяться и выйти обратно, не растеряв
// зелёную часть спектра. Ramp глубины и есть половина того, за что хвалят чужую воду.
// Прибой: там, где слой тоньше shore_foam метров, всегда бьёт белое. 0 -> как оригинал.
uniform float depth_color_on = 0.0;
uniform vec4 shallow_color : source_color = vec4(0.055, 0.34, 0.31, 1.0);
uniform float shallow_depth : hint_range(0.5, 40.0) = 8.0;
uniform float shore_foam : hint_range(0.0, 6.0) = 1.8;
// ПРАВКА WORLDBOX: ДАЛЬНОСТЬ МЕЛКОЙ РЯБИ.
// Автор гасит нормали с расстоянием против мерцания — правильная мысль, жёсткая
// константа: на 100 м остаётся 17% рельефа, на 200 м — 3%, и всё дальше ближней зоны
// становится зеркалом. А солнечные пятна родятся ровно на мелкой ряби: без неё блик
// один и широкий вместо россыпи. 0.0175 -> ведём себя ровно как оригинал.
uniform float normal_fade = 0.0175;

group_uniforms cascade_data;
uniform vec4 map_scales[MAX_CASCADES];               // Scales for displacement/normal maps. Packed: [uv scale, displacement scale, normal scale]
global uniform uint num_cascades;
global uniform sampler2DArray displacements;         // Each layer represents one wave cascade.
global uniform sampler2DArray normals : hint_normal; // Each layer represents one wave cascade.

varying float wave_height;
varying float foam_factor;
varying float fresnel;

// КИЛЬВАТЕР (правка против оригинала). Третий близнец формулы из Ocean.wake_height() и
// нашего sea_water.gdshader. Корпуса библиотека не знает вовсе, но физика на этой карте
// уже качает суда на кильватере (общий слой в Ocean), и без картинки вышло бы расхождение:
// корабль всходит на волну, которой не видно.
uniform int ship_n = 0;
uniform vec4 ship_pos[8];   // x, z, перёд.x, перёд.z
uniform vec4 ship_dim[8];   // полудлина, полуширина, ход (м/с), 0

float wake_h(vec2 p) {
	float h = 0.0;
	for (int i = 0; i < ship_n; i++) {
		float sp = ship_dim[i].z;
		if (sp < 0.6) { continue; }
		vec2 rel = p - ship_pos[i].xy;
		vec2 fw = ship_pos[i].zw;
		float lx = dot(rel, fw);
		float ly = dot(rel, vec2(-fw.y, fw.x));
		float hl = ship_dim[i].x;
		float hb = ship_dim[i].y;
		if (abs(lx) < hl && abs(ly) < hb) { continue; }
		float amp = clamp(sp * sp / 19.62, 0.0, 1.1) * 0.45;
		float lam = max(6.2831853 * sp * sp / 9.81, 3.0);
		float bow = lx - hl;
		float aft = -lx - hl;
		if (bow > 0.0) {
			h += amp * exp(-bow / (hl * 0.35)) * exp(-pow(ly / (hb * 2.0), 2.0));
		} else if (aft > 0.0) {
			float spread = hb + aft * 0.36;
			h += amp * 0.55 * exp(-pow(ly / spread, 2.0)) * exp(-aft / (hl * 8.0))
				* cos(6.2831853 * aft / lam);
		}
	}
	return h;
}

void vertex() {
	// ВНИМАНИЕ: у шейдера включён render_mode world_vertex_coords (см. шапку), то есть
	// VERTEX УЖЕ В МИРОВЫХ координатах. Здесь однажды стояла «правка» с умножением на
	// MODEL_MATRIX — она применяла сдвиг второй раз, и волновое поле уезжало вместе с
	// сеткой, а сетка едет за камерой. Игрок описал это точно: «море вращается вместе с
	// камерой вокруг смещённого пивота, со своей угловой скоростью». Поймано зондом
	// «seapin»: центр сетки прибивали к точке мира, и картина волн менялась — чего у
	// поля, зависящего только от мировых координат, быть не может.
	vec3 world_vertex = VERTEX;
	UV = world_vertex.xz;
	// Затухание смещения с дистанцией. У автора оно начиналось со 150 м и было резким
	// (0.007): его сетка кончалась на 256 м, гасить было нечего жалеть.
	//
	// Нам такое затухание вредит вдвойне. Во-первых, высота волны переставала быть
	// свойством МОРЯ и становилась свойством ВЗГЛЯДА: зона высоких волн ездила вместе с
	// камерой, и при облёте вокруг корабля море вздымалось вокруг центра, смещённого
	// относительно того, что игрок облетает, — ровно то, что он описал как «у моря свой
	// пивот и своя угловая скорость». Во-вторых, горизонт от этого стеклянный.
	// Поэтому в ближней и средней зоне волны имеют ПОЛНУЮ высоту, а гасим только совсем
	// далёкие, где сетка всё равно не может их показать (там начинается алиасинг).
	float cam_dist = length(world_vertex.xz - CAMERA_POSITION_WORLD.xz);
	float distance_factor = min(exp(-(cam_dist - 900.0)*0.0016), 1.0);

	// Read displacements from displacement maps.
	vec3 displacement = vec3(0);
	for (uint i = 0U; i < num_cascades; ++i) {
		vec4 scales = map_scales[i];
		displacement += texture(displacements, vec3(UV*scales.xy, float(i))).xyz * scales.z;
	}
	VERTEX += displacement * distance_factor;
	VERTEX.y += wake_h(world_vertex.xz);      // слой кильватера — общий с физикой
	wave_height = displacement.y;
}

/** Filter weights for a cubic B-spline. */
vec4 cubic_weights(float a) {
	float a2 = a*a;
	float a3 = a2*a;
	
	float w0 =-a3     + a2*3.0 - a*3.0 + 1.0;
	float w1 = a3*3.0 - a2*6.0         + 4.0;
	float w2 =-a3*3.0 + a2*3.0 + a*3.0 + 1.0;
	float w3 = a3;
	return vec4(w0, w1, w2, w3) / 6.0;
}

/** Performs bicubic B-spline filtering on the provided sampler. */
// Source: https://developer.nvidia.com/gpugems/gpugems2/part-iii-high-quality-rendering/chapter-20-fast-third-order-texture-filtering
vec4 texture_bicubic(in sampler2DArray sampler, in vec3 uvw) {
	vec2 dims = vec2(textureSize(sampler, 0).xy);
	vec2 dims_inv = 1.0 / dims;
	uvw.xy = uvw.xy*dims + 0.5;
	
	vec2 fuv = fract(uvw.xy);
	vec4 wx = cubic_weights(fuv.x);
	vec4 wy = cubic_weights(fuv.y);

	vec4 g = vec4(wx.xz + wx.yw, wy.xz + wy.yw);
	vec4 h = (vec4(wx.yw, wy.yw) / g + vec2(-1.5, 0.5).xyxy + floor(uvw.xy).xxyy)*dims_inv.xxyy;
	vec2 w = g.xz / (g.xz + g.yw);
    return mix(
		mix(texture(sampler, vec3(h.yw, uvw.z)), texture(sampler, vec3(h.xw, uvw.z)), w.x),
		mix(texture(sampler, vec3(h.yz, uvw.z)), texture(sampler, vec3(h.xz, uvw.z)), w.x), w.y); 
}

void fragment() {
	float map_size = float(textureSize(normals, 0).x);
	float dist = length(VERTEX.xz);
	// Read foam and normal information from normal maps.
	vec3 gradient = vec3(0);
	for (uint i = 0U; i < num_cascades; ++i) {
		vec4 scales = map_scales[i];
		vec3 coords = vec3(UV*scales.xy, float(i));
		float ppm = map_size * min(scales.x, scales.y); // Pixels per meter
		// Mix between bicubic and bilinear filtering depending on the world space pixels per meter.
		// This is dependent on the tile size as well as displacement/normal map resolution.
		gradient += mix(texture_bicubic(normals, coords), texture(normals, coords), min(1.0, ppm*0.1)).xyw * vec3(scales.ww, 1.0);
	}
		
	foam_factor = smoothstep(0.0, 1.0, gradient.z*0.75) * exp(-dist*0.0075);
	ALBEDO = mix(water_color.rgb, foam_color.rgb, foam_factor);

	gradient *= mix(0.015, normal_strength, exp(-dist*normal_fade)); // Blend normal with terrain normal as distance increases.
	NORMAL = (VIEW_MATRIX * vec4(normalize(vec3(-gradient.x, 1.0, -gradient.y)), 0.0)).xyz;

	fresnel = mix(pow(1.0 - dot(VIEW, NORMAL), 5.0*exp(-2.69*roughness)) / (1.0 + 22.7*pow(roughness, 1.5)), 1.0, REFLECTANCE);
	ROUGHNESS = (1.0 - fresnel) * foam_factor + 0.4; // Roughness is proportional to foam/fog amount and fresnel.

	// ПРАВКА WORLDBOX: подкраска по полосе горизонта. Азимут — тем же соглашением, что и
	// положение солнца в SkySpec: atan(x, -z).
	if (sky_strip_on > 0.5) {
		vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 vdir = normalize(wpos - CAMERA_POSITION_WORLD);
		float az_u = fract(atan(vdir.x, -vdir.z) / 6.2831853 + 1.0);
		vec3 sky_h = texture(sky_strip, vec2(az_u, 0.5)).rgb * sky_strip_gain;
		ALBEDO = mix(ALBEDO, sky_h, fresnel * 0.25);
		// Воздушная перспектива — ЧЕРЕЗ ЭМИССИЮ, а не через альбедо. Небо здесь фон: его
		// радианс идёт прямо в тонемап. Альбедо же проходит через освещение, поэтому
		// подмешка тона неба в него даёт другое число, чем фон, и на тёмном небе вода у
		// горизонта светится ярче него. Эмиссия складывается до тонемапа, как и фон.
		float hz = (1.0 - exp(-dist / haze_dist)) * haze_max;
		ALBEDO *= (1.0 - hz);
		EMISSION = sky_h * hz;
		// И ОБЯЗАТЕЛЬНО ГАСИМ ОТРАЖЕНИЕ. Одного альбедо мало: у горизонта Френель ≈ 1, и
		// вода отражает размытую по шероховатости ПОЛУСФЕРУ неба целиком — вместе с луной
		// или солнцем, где бы те ни были. Отсюда светлая полоса у горизонта даже когда
		// смотришь в тёмную сторону: отражается не то небо, что за водой. В дымке отражать
		// уже нечего, поэтому F0 уводим в ноль, а шероховатость — в единицу.
		SPECULAR = 0.5 * (1.0 - hz);
		METALLIC = 0.0;
		ROUGHNESS = mix(ROUGHNESS, 1.0, hz);
	}

	// ПРАВКА WORLDBOX: ВЗГЛЯД СНИЗУ. Изнанка поверхности — почти зеркало: луч изнутри воды
	// на пологих углах не выходит наружу (полное внутреннее отражение), поэтому вместо неба
	// снизу видно отражённое дно и корпуса. Нормаль разворачиваем, иначе освещение считает
	// изнанку затенённой и вода снизу выглядит чёрной дырой.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
		ROUGHNESS = mix(ROUGHNESS, 0.05, 0.8);
	}

	// ПРАВКА WORLDBOX: прозрачность по толщине слоя (см. шапку файла).
	if (transparency_on > 0.5 && FRONT_FACING) {
		float d = texture(depth_tex, SCREEN_UV).r;
		vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
		float scene_dist = -(upos.z / upos.w);      // до геометрии за водой, в метрах
		float thick = max(scene_dist + VERTEX.z, 0.0);  // VERTEX.z отрицателен во view-space

		// ПРАВКА WORLDBOX: цвет по глубине и прибой (см. шапку файла).
		if (depth_color_on > 0.5) {
			float shal = exp(-thick / max(shallow_depth, 0.01));
			// Прибой мягче кромки: степень 1.6 убирает резкий белый контур по геометрии,
			// а потолок 0.85 не даёт ему стать сплошной наклейкой.
			float surf = shore_foam > 0.01
				? pow(1.0 - smoothstep(0.0, shore_foam, thick), 1.6) * 0.85
				: 0.0;
			foam_factor = clamp(foam_factor + surf, 0.0, 1.0);
			ALBEDO = mix(mix(water_color.rgb, shallow_color.rgb, shal), foam_color.rgb, foam_factor);
			ROUGHNESS = mix(ROUGHNESS, 0.9, surf);
		}
		// ПРАВКА WORLDBOX: ПРОПУСКАНИЕ ПОКАНАЛЬНО.
		// Здесь стояла одна скалярная непрозрачность, свёрнутая по МАКСИМАЛЬНОМУ каналу,
		// и картинка за водой шла сквозь неё бесцветной: песок на трёхметровой глубине
		// оставался песочным. А вся бирюза мелководья именно отсюда — красный гаснет с
		// коэффициентом 0.55 1/м, синий с 0.14, и на трёх метрах остаётся 19% красного
		// против 66% синего. Поканально — и дно само уходит в бирюзу с глубиной.
		// Пена непрозрачна: это воздух в воде, сквозь неё не видно ничего.
		vec3 T = exp(-water_absorb * thick) * (1.0 - clamp(foam_factor, 0.0, 1.0));

		// ПРЕЛОМЛЕНИЕ. Смещаем выборку экрана по наклону поверхности; NORMAL здесь во
		// view-space, поэтому её xy совпадают с экранными осями. Смещение растёт с толщиной:
		// у самой кромки воды искажать нечего.
		// Смещение считаем от ОТКЛОНЕНИЯ нормали от вертикали, а не от самой нормали.
		// Нормаль спокойной воды смотрит вверх, и при взгляде вдоль горизонта её экранная
		// проекция — крупная почти постоянная величина: она сдвигала бы весь кадр целиком,
		// что глазом не читается как преломление вовсе. Волна — это именно отклонение.
		vec3 up_v = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		vec2 dev = (NORMAL - up_v).xy;
		vec2 off = dev * refraction * min(thick, 6.0) * 0.12;
		vec2 ruv = clamp(SCREEN_UV + off, vec2(0.002), vec2(0.998));
		// ЗАЩИТА ОТ ПРОТЕЧКИ: в смещённой точке может оказаться то, что стоит ПЕРЕД водой
		// (борт над водой, снасти) — тогда оно размазалось бы внутрь воды. Проверяем глубину
		// и в таком случае берём несмещённую выборку.
		float rd = texture(depth_tex, ruv).r;
		vec4 rup = INV_PROJECTION_MATRIX * vec4(ruv * 2.0 - 1.0, rd, 1.0);
		if (-(rup.z / rup.w) < -VERTEX.z) {
			ruv = SCREEN_UV;
		}
		// Свет, прошедший сквозь воду, УЖЕ затенён — поэтому в эмиссию, а не в альбедо:
		// иначе он второй раз попал бы под освещение поверхности.
		vec3 behind = texture(screen_tex, ruv).rgb;
		ALBEDO *= (vec3(1.0) - T);
		EMISSION += behind * T;
		ALPHA = 1.0;                      // композицию делаем сами, blend тут больше не нужен
	} else {
		ALPHA = 1.0;
	}
}

float smith_masking_shadowing(in float cos_theta, in float alpha) {
	float a = cos_theta / (alpha * sqrt(1.0 - cos_theta*cos_theta)); // Approximate: 1.0 / (alpha * tan(acos(cos_theta)))
	float a_sq = a*a;
	return a < 1.6 ? (1.0 - 1.259*a + 0.396*a_sq) / (3.535*a + 2.181*a_sq) : 0.0;
}

// Source: https://github.com/godotengine/godot/blob/7b56111c297f24304eb911fe75082d8cdc3d4141/drivers/gles3/shaders/scene.glsl#L995
float ggx_distribution(in float cos_theta, in float alpha) {
	float a_sq = alpha*alpha;
	float d = 1.0 + (a_sq - 1.0) * cos_theta * cos_theta;
	return a_sq / (PI * d*d);
}

void light() {
	vec3 halfway = normalize(LIGHT + VIEW);
	float dot_nl = max(dot(NORMAL, LIGHT), 2e-5);
	float dot_nv = max(dot(NORMAL, VIEW), 2e-5);

	// --- SPECULAR ---
	float light_mask = smith_masking_shadowing(roughness, dot_nv);
	float view_mask = smith_masking_shadowing(roughness, dot_nl);
	float microfacet_distribution = ggx_distribution(dot(NORMAL, halfway), roughness);
	float geometric_attenuation = 1.0 / (1.0 + light_mask + view_mask);
	SPECULAR_LIGHT += fresnel * microfacet_distribution * geometric_attenuation / (4.0 * dot_nv + 0.1) * ATTENUATION;

	// --- DIFFUSE ---
	const vec3 sss_modifier = vec3(0.9,1.15,0.85); // Subsurface scattering produces a 'greener' color.
	float sss_height = sss_gain*max(0.0, wave_height + 2.5) * pow(max(dot(LIGHT, -VIEW), 0.0), 4.0) * pow(0.5 - 0.5 * dot(LIGHT, NORMAL), 3.0);
	float sss_near = 0.5*pow(dot_nv, 2.0);
	float lambertian = 0.5*dot_nl;
	// ПРАВКА WORLDBOX: тон воды в прямом свете (см. diffuse_tint в шапке).
	vec3 hue = water_color.rgb / max(max(water_color.r, water_color.g), max(water_color.b, 1e-4));
	vec3 tint = mix(vec3(1.0), hue, diffuse_tint);
	DIFFUSE_LIGHT += mix(((sss_height + sss_near) * sss_modifier / (1.0 + light_mask) + lambertian) * tint, foam_color.rgb, foam_factor) * (1.0 - fresnel) * ATTENUATION * LIGHT_COLOR;
}
