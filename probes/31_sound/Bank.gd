class_name SoundBank
extends RefCounted

## Выстрел, собранный из чисел. Никаких ассетов: проба обязана быть самодостаточной, а
## звук — такой же вычислимый объект, как пулевое отверстие в тридцатой пробе.
##
## Один выстрел — это НЕ один звук. Это три события с разными временами жизни, и ухо
## разбирает их по отдельности, даже когда сознание слышит «бах»:
##
##   ЩЕЛЧОК  ~12 мс   ударная волна. Почти весь верх спектра. Это он говорит «близко».
##   ТЕЛО    ~90 мс   расширяющийся газ. Середина плюс низкий удар. Это он говорит «крупное».
##   ХВОСТ   ~450 мс  всё остальное, уже глухое. Это он говорит «в помещении».
##
## Смешать их заранее в один сэмпл — значит потерять возможность их развести: на дистанции
## щелчок съедается воздухом первым, а хвост живёт дольше всех. Отсюда три отдельных потока.

const RATE := 44100


## Одинарный полюс — простейший НЧ-фильтр, какой вообще бывает: выход подтягивается к
## входу с постоянным коэффициентом. Всё, что нужно, чтобы «глухо» отличалось от «резко».
static func _lp(buf: PackedFloat32Array, hz: float) -> void:
	var a := 1.0 - exp(-TAU * hz / float(RATE))
	var y := 0.0
	for i in buf.size():
		y += (buf[i] - y) * a
		buf[i] = y


## Разность соседних отсчётов — такой же простейший ВЧ-фильтр. Щелчку нужен именно он:
## белый шум без него звучит как «ш-ш», а не как удар.
static func _hp(buf: PackedFloat32Array) -> void:
	var prev := 0.0
	for i in buf.size():
		var x := buf[i]
		buf[i] = x - prev
		prev = x


## Приведение к заданному пику. Без него слои клиппуют поодиночке, а вместе — тем более:
## три потока звучат ОДНОВРЕМЕННО и складываются уже в микшере. Замер показал пик ровно
## 1.00 у щелчка и у тела — то есть срез, который слышно как треск, а не как выстрел.
static func _norm(buf: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0
	for v in buf:
		m = maxf(m, absf(v))
	if m < 1e-6:
		return buf
	var k := peak / m
	for i in buf.size():
		buf[i] *= k
	return buf


static func _noise(n: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		b[i] = rng.randf_range(-1.0, 1.0)
	return b


## ЩЕЛЧОК. Экспонента с постоянной ~2 мс: к пятнадцатой миллисекунде от него ничего не
## остаётся. Именно эта скорость спада читается как «выстрел», а не как «хлопок двери».
static func _crack(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 0.014)
	var b := _noise(n, rng)
	_hp(b)
	for i in n:
		var t := float(i) / float(RATE)
		b[i] *= exp(-t * 430.0)
	return _norm(b, 0.9)


## ТЕЛО. Шум, срезанный на 2 кГц, плюс низкий удар синусом: расширяющийся газ даёт
## широкую середину, а отдача ствола — короткий низ. Без низа выстрел звучит игрушечно.
static func _body(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 0.1)
	var b := _noise(n, rng)
	_lp(b, 2000.0)
	var thump_hz := rng.randf_range(78.0, 96.0)
	for i in n:
		var t := float(i) / float(RATE)
		b[i] = b[i] * 2.2 * exp(-t * 42.0) + sin(TAU * thump_hz * t) * 0.55 * exp(-t * 26.0)
	return _norm(b, 0.7)


## ХВОСТ. Глухой, длинный, тихий. Сам по себе неразличим; выключи его — и выстрел станет
## сухим щелчком без помещения вокруг.
static func _tail(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 0.45)
	var b := _noise(n, rng)
	_lp(b, 620.0)
	for i in n:
		var t := float(i) / float(RATE)
		b[i] *= 0.9 * exp(-t * 8.5)
	return _norm(b, 0.3)


static func _to_wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	w.data = bytes
	return w


## Три слоя одного выстрела, каждый отдельным потоком.
## Номер варианта задаёт зерно: четыре выстрела подряд НЕ должны быть одним файлом.
static func shot(variant: int) -> Array[AudioStreamWAV]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8123 + variant * 977
	return [_to_wav(_crack(rng)), _to_wav(_body(rng)), _to_wav(_tail(rng))]


## Всё в одном сэмпле — то, с чего начинают, и то, с чем сравнивают. Ровно та же сумма,
## но склеенная заранее: слоями уже не подвигать.
static func flat(variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8123 + variant * 977
	var c := _crack(rng)
	var b := _body(rng)
	var t := _tail(rng)
	var out := PackedFloat32Array()
	out.resize(t.size())
	for i in out.size():
		var v := t[i]
		if i < b.size():
			v += b[i]
		if i < c.size():
			v += c[i]
		out[i] = v
	# Тот же пик, что у суммы трёх слоёв, — иначе сравнение по клавише 8 сведётся к
	# «склеенный громче», и разницу в слоях не услышать.
	return _to_wav(_norm(out, 0.95))


## Дальний выстрел ради одного эффекта: на 250 метрах звук приходит через три четверти
## секунды после вспышки. Ближний бой этого не показывает — расстояния слишком малы.
static func boom() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var n := int(RATE * 1.1)
	var b := _noise(n, rng)
	_lp(b, 240.0)
	for i in n:
		var t := float(i) / float(RATE)
		# медленная атака: далёкий звук приходит размазанным, а не ударом
		b[i] *= (1.0 - exp(-t * 60.0)) * exp(-t * 4.0)
	return _to_wav(_norm(b, 0.95))
