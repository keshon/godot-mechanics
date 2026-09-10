class_name SoundBank
extends RefCounted
## Выстрел, собранный из чисел. Никаких ассетов: проба обязана быть самодостаточной, а
## звук — такой же вычислимый объект, как пулевое отверстие в тридцатой пробе.
##
## Один выстрел — это НЕ один звук. Это три события с разными временами жизни, и ухо
## разбирает их по отдельности, даже когда сознание слышит «бах»:
##
##   ЩЕЛЧОК  ~12 мс   ударная волна. Почти весь верх спектра. Это он говорит «близко».
##   ТЕЛО    ~90 мс   расширяющийся газ. Середина плюс низкий удар. Говорит «крупное».
##   ХВОСТ   ~450 мс  всё остальное, уже глухое. Это он говорит «в помещении».
##
## Смешать их заранее в один сэмпл — значит потерять возможность их развести: на
## дистанции щелчок съедается воздухом первым, а хвост живёт дольше всех. Отсюда три
## отдельных потока.

const RATE := 44100


## Три слоя одного выстрела, каждый отдельным потоком.
## Номер варианта задаёт зерно: четыре выстрела подряд НЕ должны быть одним файлом.
static func shot(variant: int) -> Array[AudioStreamWAV]:
	var random := RandomNumberGenerator.new()
	random.seed = 8123 + variant * 977
	return [_to_wav(_crack(random)), _to_wav(_body(random)), _to_wav(_tail(random))]


## Всё в одном сэмпле — то, с чего начинают, и то, с чем сравнивают. Ровно та же сумма,
## но склеенная заранее: слоями уже не подвигать.
static func flat(variant: int) -> AudioStreamWAV:
	var random := RandomNumberGenerator.new()
	random.seed = 8123 + variant * 977
	var crack := _crack(random)
	var body := _body(random)
	var tail := _tail(random)
	var mixed := PackedFloat32Array()
	mixed.resize(tail.size())
	for i in mixed.size():
		var value := tail[i]
		if i < body.size():
			value += body[i]
		if i < crack.size():
			value += crack[i]
		mixed[i] = value
	# Тот же пик, что у суммы трёх слоёв, — иначе сравнение по клавише 8 сведётся к
	# «склеенный громче», и разницу в слоях не услышать.
	return _to_wav(_normalise(mixed, 0.95))


## Дальний выстрел ради одного эффекта: на 250 метрах звук приходит через три четверти
## секунды после вспышки. Ближний бой этого не показывает — расстояния слишком малы.
static func boom() -> AudioStreamWAV:
	var random := RandomNumberGenerator.new()
	random.seed = 4242
	var count := int(RATE * 1.1)
	var samples := _noise(count, random)
	_low_pass(samples, 240.0)
	for i in count:
		var at := float(i) / float(RATE)
		# Медленная атака: далёкий звук приходит размазанным, а не ударом.
		samples[i] *= (1.0 - exp(-at * 60.0)) * exp(-at * 4.0)
	return _to_wav(_normalise(samples, 0.95))


## ЩЕЛЧОК. Экспонента с постоянной ~2 мс: к пятнадцатой миллисекунде от него ничего не
## остаётся. Именно эта скорость спада читается как «выстрел», а не как «хлопок двери».
static func _crack(random: RandomNumberGenerator) -> PackedFloat32Array:
	var count := int(RATE * 0.014)
	var samples := _noise(count, random)
	_high_pass(samples)
	for i in count:
		samples[i] *= exp(-float(i) / float(RATE) * 430.0)
	return _normalise(samples, 0.9)


## ТЕЛО. Шум, срезанный на 2 кГц, плюс низкий удар синусом: расширяющийся газ даёт
## широкую середину, а отдача ствола — короткий низ. Без низа выстрел звучит игрушечно.
static func _body(random: RandomNumberGenerator) -> PackedFloat32Array:
	var count := int(RATE * 0.1)
	var samples := _noise(count, random)
	_low_pass(samples, 2000.0)
	var thump_hz := random.randf_range(78.0, 96.0)
	for i in count:
		var at := float(i) / float(RATE)
		samples[i] = (
				samples[i] * 2.2 * exp(-at * 42.0)
				+ sin(TAU * thump_hz * at) * 0.55 * exp(-at * 26.0)
		)
	return _normalise(samples, 0.7)


## ХВОСТ. Глухой, длинный, тихий. Сам по себе неразличим; выключи его — и выстрел станет
## сухим щелчком без помещения вокруг.
static func _tail(random: RandomNumberGenerator) -> PackedFloat32Array:
	var count := int(RATE * 0.45)
	var samples := _noise(count, random)
	_low_pass(samples, 620.0)
	for i in count:
		samples[i] *= 0.9 * exp(-float(i) / float(RATE) * 8.5)
	return _normalise(samples, 0.3)


static func _noise(count: int, random: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		samples[i] = random.randf_range(-1.0, 1.0)
	return samples


## Одинарный полюс — простейший НЧ-фильтр, какой вообще бывает: выход подтягивается к
## входу с постоянным коэффициентом. Всё, что нужно, чтобы «глухо» отличалось от «резко».
static func _low_pass(samples: PackedFloat32Array, hz: float) -> void:
	var rate := 1.0 - exp(-TAU * hz / float(RATE))
	var held := 0.0
	for i in samples.size():
		held += (samples[i] - held) * rate
		samples[i] = held


## Разность соседних отсчётов — такой же простейший ВЧ-фильтр. Щелчку нужен именно он:
## белый шум без него звучит как «ш-ш», а не как удар.
static func _high_pass(samples: PackedFloat32Array) -> void:
	var previous := 0.0
	for i in samples.size():
		var current := samples[i]
		samples[i] = current - previous
		previous = current


## Приведение к заданному пику. Без него слои клиппуют поодиночке, а вместе — тем более:
## три потока звучат ОДНОВРЕМЕННО и складываются уже в микшере. Замер показал пик ровно
## 1.00 у щелчка и у тела — то есть срез, который слышно как треск, а не как выстрел.
static func _normalise(
		samples: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var loudest := 0.0
	for value in samples:
		loudest = maxf(loudest, absf(value))
	if loudest < 1e-6:
		return samples
	var gain := peak / loudest
	for i in samples.size():
		samples[i] *= gain
	return samples


static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	wav.data = bytes
	return wav
