extends RichTextLabel
## ТРИ ЧИСЛА, РАДИ КОТОРЫХ ПРОБА СУЩЕСТВУЕТ.
##
## СЧЁТ — сколько заняла сама математика стаи, замеренная до того, как что-либо нарисовано.
## Зависит от `count` и `neighbour_samples`, и больше ни от чего.
##
## ВЫЗОВОВ ОТРИСОВКИ — сколько раз за кадр GPU попросили что-нибудь нарисовать, и он здесь
## потому, что он неожиданность. Со стаей он НЕ РАСТЁТ: десять тысяч отдельных
## `MeshInstance3D` стоят те же полтора десятка вызовов, потому что Godot 4 сам объединяет
## одинаковые меши. Цена узла живёт совсем в другом месте — нажми F, заморозь стаю и смотри,
## как кадр обваливается, пока все узлы остаются ровно там же.

## Сколько кадров после перестройки не считать: раздача нескольких тысяч узлов даёт один
## очень медленный кадр, который ничего не говорит об установившемся состоянии.
const SETTLE_FRAMES := 60

@export var flock_path: NodePath = ^"../../Flock"

## Худший кадр с последней перестройки стаи, мс.
var _worst_ms := 0.0
var _settle_frames := 0
var _smoothed_delta := 0.016

@onready var flock: CrowdFlock = get_node(flock_path)


func _ready() -> void:
	flock.rebuilt.connect(_on_flock_rebuilt)


func _process(delta: float) -> void:
	_smoothed_delta = lerpf(_smoothed_delta, delta, 0.05)
	var frame_ms := _smoothed_delta * 1000.0
	_settle_frames += 1
	if _settle_frames > SETTLE_FRAMES:
		_worst_ms = maxf(_worst_ms, frame_ms)

	var calls := RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var by_multimesh := flock.draw_mode == CrowdFlock.DrawMode.MULTIMESH
	var vsync := DisplayServer.window_get_vsync_mode(get_window().get_window_id())
	var capped := vsync != DisplayServer.VSYNC_DISABLED
	text = "\n".join(PackedStringArray([
		"особей [b]%d[/b]   рисуем %s   узлов в дереве %d%s" % [
			flock.count,
			"[color=#7fe08a]мультимешем[/color]" if by_multimesh
				else "[color=#ffd479]узлами[/color]",
			get_tree().get_node_count(),
			"   [color=#ffd479][b]ЗАМОРОЖЕНА[/b][/color]" if flock.frozen else ""],
		"кадр [b]%.2f[/b] мс   худший с перестройки %.1f   %.0f кадров/с%s" % [
			frame_ms, _worst_ms, 1.0 / maxf(_smoothed_delta, 0.0001),
			"   [color=#ff8a6a](вертикальная синхронизация держит потолок — V)[/color]"
				if capped else ""],
		"счёт [b]%.2f[/b] мс при %d выборках   выкладка [b]%.2f[/b] мс   вызовов %d" % [
			flock.simulation_usec / 1000.0, flock.neighbour_samples,
			flock.present_usec / 1000.0, calls],
		"",
		"WASD лететь   ПРОБЕЛ вверх   SHIFT быстрее   КОЛЕСО скорость   ESC мышь",
		"F заморозить стаю: %s   (узлы остаются на месте, записи в них прекращаются)" % (
			"[b]заморожена[/b]" if flock.frozen else "летит"),
		"V вертикальная синхронизация: %s   (при ней любой замер кадра врёт)" % (
			"[color=#ff8a6a]вкл[/color]" if capped else "выкл"),
		"",
		"[color=#66ccff]стен две, на разных числах и с разными лекарствами: дорого не"
			+ " количество узлов, а количество записей в них[/color]",
	]))


## Перестройка выбрасывает все замеры. «Худший с перестройки» без сброса врёт: после смены
## числа особей строка показывает всплеск от прежней раскладки.
func _on_flock_rebuilt() -> void:
	_worst_ms = 0.0
	_settle_frames = 0
