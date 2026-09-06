extends RefCounted
class_name ScaleSource


## ОТКУДА БЕРЁТСЯ ВЫСОТА. Три источника, отвечающие на один вопрос `height(x, z)`.
##
##   ФУНКЦИЯ    Шум прямо в точке. Данных ноль, мир бесконечен по-настоящему: сколько ни
##              иди, всегда есть чем ответить. Платишь вычислением на каждую вершину.
##   16 БИТ     Та же карта, запечённая в изображение с полным диапазоном. Выборка вместо
##              счёта — быстрее, но мир конечен и за краем повторяется.
##   8 БИТ      Она же в 256 уровней. Ровно то, что получишь, скачав карту высот PNG из
##              интернета, — и ровно та ловушка, о которой никто не предупреждает.
##
## ПРО 8 БИТ. На диапазоне высот в 90 метров 256 уровней дают ступеньку в 35 сантиметров.
## Само по себе терпимо. Беда в том, что НОРМАЛЬ считается разностью соседних высот: на
## пологом склоне соседи попадают в одну ступеньку, разность равна нулю, и гладкий холм
## превращается в лестницу из плоских площадок с резкими гранями. Освещение ломается
## раньше, чем силуэт.
##
## СВОЯ КАРТА. Положи рядом `height.png` — он будет подхвачен как четвёртый источник.
## Годятся SRTM, Copernicus DEM, USGS, OpenTopography или экспорт из Gaea и World Machine.
## Учти: у картинки нет ни масштаба, ни диапазона высот — их задаёшь ты, `map_metres` и
## `amplitude`. Отсюда классическая беда «почему у меня горы в сорок километров».

const FUNC := 0
const BITS16 := 1
const BITS8 := 2
const DISK := 3

const NAMES := ["функция (шум в точке)", "текстура 16 бит", "текстура 8 бит", "своя height.png"]
const DISK_PATH := "res://probes/34_scale/height.png"

## Сторона запечённой карты в текселях.
var res := 512
## Сколько метров мира покрывает карта до повтора.
var map_metres := 1024.0
var amplitude := 90.0
var mode := FUNC

var _noise := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _img16: Image
var _img8: Image
var _disk: Image
var _tex: ImageTexture


func _init() -> void:
	_noise.seed = 20260902
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0016
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 6
	_noise.fractal_lacunarity = 2.05
	_noise.fractal_gain = 0.47
	_warp.seed = 771
	_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_warp.frequency = 0.0009
	_bake()
	if ResourceLoader.exists(DISK_PATH):
		var t: Texture2D = load(DISK_PATH)
		if t != null:
			_disk = t.get_image()
			_disk.convert(Image.FORMAT_RF)


func has_disk() -> bool:
	return _disk != null


## Нормализованная высота 0…1 от чистой функции. Единственное место, где считается шум.
func _raw(x: float, z: float) -> float:
	var px := x + _warp.get_noise_2d(x, z) * 90.0
	var pz := z + _warp.get_noise_2d(x + 411.0, z - 187.0) * 90.0
	return _noise.get_noise_2d(px, pz) * 0.5 + 0.5


## ЗАПЕКАНИЕ. Одна и та же функция кладётся в два изображения разной разрядности — чтобы
## сравнение «8 против 16» показывало РАЗРЯДНОСТЬ, а не разные карты.
func _bake() -> void:
	_img16 = Image.create_empty(res, res, false, Image.FORMAT_RF)
	_img8 = Image.create_empty(res, res, false, Image.FORMAT_R8)
	var step := map_metres / float(res)
	for j in res:
		for i in res:
			var h := _raw(i * step, j * step)
			_img16.set_pixel(i, j, Color(h, 0.0, 0.0))
			_img8.set_pixel(i, j, Color(h, 0.0, 0.0))
	_tex = ImageTexture.create_from_image(_img16)


func texture() -> ImageTexture:
	return _tex


func _img() -> Image:
	match mode:
		BITS16: return _img16
		BITS8: return _img8
		DISK: return _disk
		_: return null


## БИЛИНЕЙНАЯ ВЫБОРКА С ЗАВОРОТОМ. Заворот и есть то, чем «бесконечность» из конечной
## карты отличается от бесконечности из функции: мир не кончается, но начинает повторяться,
## и повтор видно с воздуха раньше, чем ты успеешь до него дойти.
func _sample(img: Image, x: float, z: float) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var u := x / map_metres * w
	var v := z / map_metres * h
	var i0 := int(floor(u))
	var j0 := int(floor(v))
	var fu := u - i0
	var fv := v - j0
	var i1 := posmod(i0 + 1, w)
	var j1 := posmod(j0 + 1, h)
	i0 = posmod(i0, w)
	j0 = posmod(j0, h)
	var a := lerpf(img.get_pixel(i0, j0).r, img.get_pixel(i1, j0).r, fu)
	var b := lerpf(img.get_pixel(i0, j1).r, img.get_pixel(i1, j1).r, fu)
	return lerpf(a, b, fv)


func height(x: float, z: float) -> float:
	var img := _img()
	var h := _raw(x, z) if img == null else _sample(img, x, z)
	return (h - 0.5) * amplitude


## Нормаль — аналитически из той же высоты. Шаг разности намеренно крупный: на мелком шаге
## восьмибитная карта даёт ровные нули, и ступеньки становятся не видны там, где они как раз
## и есть.
func normal(x: float, z: float) -> Vector3:
	var d := 1.0
	var hx := height(x + d, z) - height(x - d, z)
	var hz := height(x, z + d) - height(x, z - d)
	return Vector3(-hx, 2.0 * d, -hz).normalized()


func label() -> String:
	return NAMES[mode]


## Сколько разных уровней высоты вообще может выдать источник — то самое число, из-за
## которого пологие склоны становятся лестницей.
func levels() -> String:
	match mode:
		BITS8: return "256 уровней, ступенька %.2f м" % (amplitude / 256.0)
		BITS16: return "float, ступеньки нет"
		DISK: return "как в файле"
		_: return "непрерывно"
