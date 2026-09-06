shader_type particles;

// Искры — это НЕ «жёлтые точки». Это раскалённые осколки пули и преграды, и всё их
// поведение следует из двух вещей: куда они полетели и как быстро остывают.
//
// КУДА. При прямом попадании осколки летят обратно широким конусом. При косом — пуля
// рикошетит, и брызги вытягиваются в узкий веер вдоль отражённого направления. Один и тот
// же выстрел в стену под 90° и под 20° даёт совершенно разные картинки, и это половина
// того, что читается как «настоящее».
//
// КАК ОСТЫВАЮТ. Осколок светится потому, что горячий, и гаснет, потому что остывает:
// бело-жёлтый, оранжевый, тёмно-красный, ничего. Длина росчерка при этом падает вместе со
// скоростью — быстрый осколок за кадр проходит больше и размазывается сильнее.

uniform vec3 emit_dir = vec3(0.0, 1.0, 0.0);
/// Полураствор конуса. Узкий у косого попадания, широкий у прямого.
uniform float cone : hint_range(0.05, 1.6) = 0.8;
uniform float speed_min = 2.5;
uniform float speed_max = 11.0;
/// Метров росчерка на метр в секунду. Это и есть «длина искры зависит от скорости».
uniform float streak : hint_range(0.0, 0.08) = 0.026;
uniform float thickness : hint_range(0.002, 0.03) = 0.009;
uniform float drag = 2.6;
/// Оттенок раскалённого осколка: у стали он бело-жёлтый, у дерева — тусклый уголёк.
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);


float h11(float p) {
	return fract(sin(p * 78.233 + 12.9898) * 43758.5453);
}


void start() {
	TRANSFORM = EMISSION_TRANSFORM;
	float i = float(INDEX) + float(NUMBER) * 0.013;
	// равномерно по конусу вокруг emit_dir: угол по кругу и косинус раствора
	float a = h11(i * 1.7 + 0.3) * 6.2831853;
	float c = mix(cos(cone), 1.0, h11(i * 3.1 + 1.7));
	float s = sqrt(max(1.0 - c * c, 0.0));
	vec3 f = normalize(emit_dir);
	vec3 up = abs(f.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 t = normalize(cross(up, f));
	vec3 b = cross(f, t);
	vec3 dir = normalize(f * c + (t * cos(a) + b * sin(a)) * s);
	// степень 1.6 сдвигает распределение к медленным: несколько ярких длинных росчерков
	// и много коротких, как в жизни, а не ровный веер одинаковых
	VELOCITY = dir * mix(speed_min, speed_max, pow(h11(i * 5.3 + 2.9), 1.6));
	CUSTOM = vec4(0.0);
}


void process() {
	VELOCITY.y -= 9.8 * DELTA;
	VELOCITY *= max(1.0 - drag * DELTA, 0.0);
	CUSTOM.w += DELTA / LIFETIME;
	float age = clamp(CUSTOM.w, 0.0, 1.0);

	// ТЕМПЕРАТУРА, а не просто «цвет со временем». Раскалённый осколок идёт по той же
	// дороге, что любое остывающее тело: бело-жёлтый, оранжевый, тёмно-красный, погас.
	vec3 hot = vec3(1.0, 0.94, 0.72);
	vec3 warm = vec3(1.0, 0.42, 0.09);
	vec3 dying = vec3(0.5, 0.05, 0.01);
	vec3 col = age < 0.35 ? mix(hot, warm, age / 0.35) : mix(warm, dying, (age - 0.35) / 0.65);
	COLOR = vec4(col * tint, 1.0 - age * age);

	// ОРИЕНТАЦИЯ И ДЛИНА пишутся прямо в TRANSFORM: росчерк вытянут вдоль скорости, а его
	// длина пропорциональна ей. Штатный материал частиц так не умеет — он либо billboard,
	// либо ничего, — а весь смысл искры в том, что она вытянута ТУДА, КУДА ЛЕТИТ.
	float sp = length(VELOCITY);
	vec3 f = sp > 0.001 ? VELOCITY / sp : vec3(0.0, 0.0, 1.0);
	vec3 up = abs(f.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 r = normalize(cross(up, f));
	vec3 u = cross(f, r);
	float len = clamp(sp * streak, 0.012, 1.2) * (1.0 - age * 0.55);
	TRANSFORM[0].xyz = r * thickness;
	TRANSFORM[1].xyz = u * thickness;
	TRANSFORM[2].xyz = f * len;
}
