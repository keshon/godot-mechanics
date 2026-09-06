shader_type canvas_item;

// One shader, used twice, at two different stages — because the two effects
// belong to two different pieces of hardware.
//
// Crushing the colours is something the FRAMEBUFFER did. That pass lives
// inside the low-resolution viewport, where every pixel is a pixel the console
// actually stored.
//
// Scanlines are something the DISPLAY did; the console never knew about them.
// That pass lives outside, over the blown-up picture, at window resolution.
//
// The first version had both inside, and the scanlines silently did nothing at
// low resolution: with four output rows per rendered row, a two-row pattern
// lands in the same phase every time and comes out as a flat dimming. You
// cannot draw a feature finer than your own pixel — so the fix was not a
// better formula, it was moving the pass to where the pixels are small enough.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;

// Which of the two jobs this instance is doing.
uniform bool crush = true;
uniform bool scanlines = false;

// Steps per channel. 32 is roughly the 15-bit output of the real thing; drop
// to 4 and it becomes a poster, raise to 256 and the effect vanishes.
uniform int levels = 32;
uniform bool dither = true;
uniform float dither_strength = 1.0;
uniform float scanline_strength = 0.18;
/// Сколько пикселей ОКНА приходится на одну отрисованную строку. Строка развёртки — это
/// строка кадрового буфера, растянутая на экран, а не пиксель монитора: при уменьшении
/// вчетверо период должен быть четыре, а не два. С периодом в два пикселя при 900 строках
/// узор становится тоньше человеческого различения и читается просто затемнением.
uniform float scan_period = 4.0;
/// Финальный проход телевизора: виньетка, лёгкий изгиб и расплывание цвета по строке.
uniform bool crt = false;
uniform float curve = 0.06;
uniform float bleed = 0.55;
uniform float vignette = 0.35;

// A 4x4 ordered (Bayer) matrix. Not random: a fixed pattern that spreads the
// rounding error evenly, so it stays still instead of boiling frame to frame.
const float BAYER[16] = float[16](
	 0.0,  8.0,  2.0, 10.0,
	12.0,  4.0, 14.0,  6.0,
	 3.0, 11.0,  1.0,  9.0,
	15.0,  7.0, 13.0,  5.0
);


void fragment() {
	vec2 uv = SCREEN_UV;
	if (crt) {
		// ИЗГИБ. Кинескоп был выпуклым, и картинка на нём растягивалась к краям. Величина
		// смешная — шесть сотых, — но именно она отличает «картинку в окне» от «картинки
		// на телевизоре»: прямые перестают быть прямыми, и мозг достраивает остальное.
		vec2 p = uv * 2.0 - 1.0;
		p *= 1.0 + curve * dot(p, p);
		uv = p * 0.5 + 0.5;
	}
	vec3 c = texture(screen_tex, uv).rgb;

	if (crt) {
		// РАСПЛЫВАНИЕ ЦВЕТА ПО СТРОКЕ. У композитного сигнала яркость и цвет шли в одной
		// полосе, и цвет имел вчетверо меньшее разрешение — отсюда цветные хвосты вправо от
		// контрастных границ. Смещаем красный и синий на доли пикселя в разные стороны.
		vec2 px = vec2(bleed / max(float(textureSize(screen_tex, 0).x), 1.0), 0.0);
		c.r = texture(screen_tex, uv + px).r;
		c.b = texture(screen_tex, uv - px).b;
		// ВИНЬЕТКА. Не эффект, а факт: маска кинескопа темнила углы, и без неё кадр
		// выглядит вырезанным из большего.
		vec2 v = uv * (1.0 - uv.yx);
		c *= mix(1.0, clamp(pow(v.x * v.y * 16.0, 0.35), 0.0, 1.0), vignette);
	}

	if (crush) {
		float steps = float(max(levels, 2));
		if (dither) {
			// Nudge each pixel by less than one step before rounding. Half the
			// pixels round up, half down, and the average lands where the true
			// colour was — banding traded for a fine noise the eye forgives.
			ivec2 p = ivec2(FRAGCOORD.xy) % 4;
			c += ((BAYER[p.y * 4 + p.x] / 16.0) - 0.5) * dither_strength / steps;
		}
		c = floor(c * steps + 0.5) / steps;
	}

	if (scanlines) {
		// Период — одна ОТРИСОВАННАЯ строка, растянутая на экран. Профиль косинусом, а не
		// ступенькой: у кинескопа луч имел толщину, и переход между строками был плавным.
		float phase = FRAGCOORD.y / max(scan_period, 1.0) * 6.2831853;
		c *= 1.0 - scanline_strength * (0.5 - 0.5 * cos(phase));
	}

	COLOR = vec4(c, 1.0);
}
