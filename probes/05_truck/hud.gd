extends RichTextLabel
## ШЕСТЬ КОЛЁС, ШЕСТЬ ПОЛОСОК. Каждая полоска — одна подвеска, считанная прямо с положения
## узла колеса: пусто — пружина висит свободно, полно — вжата до упора хода.
##
## Проехать гребёнку в виде сбоку и посмотреть, как три оси проходят её по очереди. Эта
## волна и есть то, ради чего проба существует.

## Имя узла колеса → как звать его на экране, с выравниванием, чтобы полоски встали в столбец.
const WHEEL_NAMES := {
	"FL": "перед Л",
	"FR": "перед П",
	"ML": "сред  Л",
	"MR": "сред  П",
	"RL": "зад   Л",
	"RR": "зад   П",
}
## Ширина полоски сжатия в знаках.
const BAR_WIDTH := 16
## Выше этой доли хода пружина считается вжатой в упор.
const BAR_HOT := 0.85

@export var truck_path: NodePath = ^"../../Truck"

@onready var truck: TruckBody = get_node(truck_path)


func _process(_delta: float) -> void:
	var lines := PackedStringArray([
		"[b]%d[/b] км/ч   привод [b]%s[/b]   оси %s   крен [b]%+.2f°[/b]" % [
			roundi(truck.linear_velocity.length() * 3.6),
			truck.driving_axles(),
			"[b]6×6[/b]" if truck.middle_axle_enabled
				else "[color=#ffd479]4×4, средняя поднята[/color]",
			truck.roll_degrees()],
		"стабилизаторы %.0f / %.0f / %.0f   момент: %s" % [
			truck.bar_front, truck.bar_middle, truck.bar_rear,
			"делится по колёсам" if truck.use_split_torque
				else "[color=#ffd479]полный на каждое[/color]"],
		"",
	])
	for wheel in truck.wheels():
		lines.append("%s  %s%s%s" % [
			WHEEL_NAMES.get(wheel.name, wheel.name),
			_compression_bar(truck.compression(wheel)),
			"   [color=#ff8a6a]в воздухе[/color]" if not wheel.is_in_contact() else "",
			"   [color=#7fe08a]ведущее[/color]" if wheel.use_as_traction else ""])
	lines.append_array(PackedStringArray([
		"",
		"W/S газ и тормоз двигателем   A/D руль   ПРОБЕЛ тормоз   C вид сбоку",
		"привод, средняя ось и деление момента живут на Truck — их крутят во вкладке"
			+ " Remote на живой игре",
		"",
		"[color=#66ccff]раскладка привода не значит ничего, пока шина держит: значит"
			+ " стабилизатор поперечной устойчивости[/color]",
	]))
	text = "\n".join(lines)


## Сжатие рисуется полоской, потому что столбец чисел прячет ритм, а столбец полосок его
## показывает.
func _compression_bar(value: float) -> String:
	var filled := int(round(value * BAR_WIDTH))
	var tint := "#7fe08a" if value < BAR_HOT else "#ff8a6a"
	return "[color=%s]%s[/color][color=#4a4f58]%s[/color]" % [
		tint, "|".repeat(filled), "-".repeat(BAR_WIDTH - filled)]
