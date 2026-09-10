class_name ScaleSource
extends RefCounted
## ОТКУДА БЕРЁТСЯ ВЫСОТА. Четыре источника, отвечающие на один вопрос `height(x, z)`.
##
##   NOISE   Шум прямо в точке. Данных ноль, мир бесконечен по-настоящему: сколько ни
##           иди, всегда есть чем ответить. Платишь вычислением на каждую вершину.
##   BITS16  Та же карта, запечённая в изображение с полным диапазоном. Выборка вместо
##           счёта — быстрее, но мир конечен и за краем повторяется.
##   BITS8   Она же в 256 уровней. Ровно то, что получишь, скачав карту высот PNG из
##           интернета, — и ровно та ловушка, о которой никто не предупреждает.
##   DISK    Свой `height.png`, если он лежит рядом.
##
## ПРО 8 БИТ. На диапазоне высот в 90 метров 256 уровней дают ступеньку в 35 сантиметров.
## Само по себе терпимо. Беда в том, что НОРМАЛЬ считается разностью соседних высот: на
## пологом склоне соседи попадают в одну ступеньку, разность равна нулю, и гладкий холм
## превращается в лестницу из плоских площадок с резкими гранями. Освещение ломается
## раньше, чем силуэт.
##
## СВОЯ КАРТА. Годятся SRTM, Copernicus DEM, USGS, OpenTopography или экспорт из Gaea и
## World Machine. Учти: у картинки нет ни масштаба, ни диапазона высот — их задаёшь ты,
## `map_metres` и `amplitude`. Отсюда классическая беда «почему у меня горы в сорок
## километров».

enum Mode {
	NOISE,
	BITS16,
	BITS8,
	DISK,
}

const NAMES := [
	"функция (шум в точке)",
	"текстура 16 бит",
	"текстура 8 бит",
	"своя height.png",
]
const DISK_PATH := "res://probes/34_scale/height.png"

## Сторона запечённой карты в текселях.
var resolution := 512
## Сколько метров мира покрывает карта до повтора.
var map_metres := 1024.0
var amplitude := 90.0
var mode := Mode.NOISE

var _noise := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _map16: Image
var _map8: Image
var _disk: Image
var _texture: ImageTexture


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
	if not ResourceLoader.exists(DISK_PATH):
		return
	var loaded: Texture2D = load(DISK_PATH)
	if loaded == null:
		return
	_disk = loaded.get_image()
	_disk.convert(Image.FORMAT_RF)


func has_disk() -> bool:
	return _disk != null


func texture() -> ImageTexture:
	return _texture


func height(x: float, z: float) -> float:
	var map := _map()
	var value := _noise_at(x, z) if map == null else _sample(map, x, z)
	return (value - 0.5) * amplitude


## Нормаль — аналитически из той же высоты. Шаг разности намеренно крупный: на мелком
## шаге восьмибитная карта даёт ровные нули, и ступеньки становятся не видны там, где они
## как раз и есть.
func normal(x: float, z: float) -> Vector3:
	var step := 1.0
	var slope_x := height(x + step, z) - height(x - step, z)
	var slope_z := height(x, z + step) - height(x, z - step)
	return Vector3(-slope_x, 2.0 * step, -slope_z).normalized()


func label() -> String:
	return NAMES[mode]


## Сколько разных уровней высоты вообще может выдать источник — то самое число, из-за
## которого пологие склоны становятся лестницей.
func levels() -> String:
	match mode:
		Mode.BITS8:
			return "256 уровней, ступенька %.2f м" % (amplitude / 256.0)
		Mode.BITS16:
			return "float, ступеньки нет"
		Mode.DISK:
			return "как в файле"
	return "непрерывно"


## Нормализованная высота 0…1 от чистой функции. Единственное место, где считается шум.
func _noise_at(x: float, z: float) -> float:
	var sample_x := x + _warp.get_noise_2d(x, z) * 90.0
	var sample_z := z + _warp.get_noise_2d(x + 411.0, z - 187.0) * 90.0
	return _noise.get_noise_2d(sample_x, sample_z) * 0.5 + 0.5


## ЗАПЕКАНИЕ. Одна и та же функция кладётся в два изображения разной разрядности — чтобы
## сравнение «8 против 16» показывало РАЗРЯДНОСТЬ, а не разные карты.
func _bake() -> void:
	_map16 = Image.create_empty(resolution, resolution, false, Image.FORMAT_RF)
	_map8 = Image.create_empty(resolution, resolution, false, Image.FORMAT_R8)
	var step := map_metres / float(resolution)
	for row in resolution:
		for column in resolution:
			var value := _noise_at(column * step, row * step)
			_map16.set_pixel(column, row, Color(value, 0.0, 0.0))
			_map8.set_pixel(column, row, Color(value, 0.0, 0.0))
	_texture = ImageTexture.create_from_image(_map16)


func _map() -> Image:
	match mode:
		Mode.BITS16:
			return _map16
		Mode.BITS8:
			return _map8
		Mode.DISK:
			return _disk
	return null


## БИЛИНЕЙНАЯ ВЫБОРКА С ЗАВОРОТОМ. Заворот и есть то, чем «бесконечность» из конечной
## карты отличается от бесконечности из функции: мир не кончается, но начинает
## повторяться, и повтор видно с воздуха раньше, чем ты успеешь до него дойти.
func _sample(map: Image, x: float, z: float) -> float:
	var width := map.get_width()
	var height_px := map.get_height()
	var u := x / map_metres * width
	var v := z / map_metres * height_px
	var left := int(floor(u))
	var top := int(floor(v))
	var fraction_u := u - left
	var fraction_v := v - top
	var right := posmod(left + 1, width)
	var bottom := posmod(top + 1, height_px)
	left = posmod(left, width)
	top = posmod(top, height_px)
	var upper := lerpf(
			map.get_pixel(left, top).r, map.get_pixel(right, top).r, fraction_u)
	var lower := lerpf(
			map.get_pixel(left, bottom).r, map.get_pixel(right, bottom).r, fraction_u)
	return lerpf(upper, lower, fraction_v)
