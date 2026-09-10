extends RichTextLabel
## ПОКАЗАНИЯ ПРОБЫ ПРО ТРЕТЬЕ ЛИЦО.
##
## Главное здесь — ДОВОРОТ: угол между тем, куда смотрит тело, и тем, куда смотрит камера.
## В свободном режиме он ходит по всему кругу; зажми прицел — схлопывается в ноль и там
## остаётся. Это два режима любой игры от третьего лица, одним числом.

## Насколько камера должна отстать, метры, чтобы про это стоило писать.
const LAG_SHOWN := 0.15
## На сколько камера должна вжаться, метры, чтобы про это стоило писать.
const SQUEEZE_SHOWN := 0.05
## Доворот меньше этого, градусы, считается сведённым.
const ON_TARGET := 5.0

@export var player_path: NodePath = ^"../../Player"

@onready var player: OrbitPlayer = get_node(player_path)
@onready var rig: OrbitRig = player.get_node(^"CameraRig")


func _process(_delta: float) -> void:
	var want := rig.wanted_length()
	var got := rig.actual_length()
	var lag := rig.lag()
	text = "\n".join(PackedStringArray([
		"режим: %s   скорость [b]%.1f[/b] м/с   доворот %s" % [
			"[color=#ffd479][b]ПРИЦЕЛ[/b][/color]" if player.is_aiming()
				else "свободный",
			player.speed(), _facing_text()],
		"камера %.2f м%s   отставание %.2f м%s" % [
			got,
			"   [color=#ffd479](вжата с %.2f)[/color]" % want
				if got < want - SQUEEZE_SHOWN else "",
			lag,
			"   [color=#66ccff](тянется следом)[/color]" if lag > LAG_SHOWN else ""],
		"",
		"WASD бег   ПРОБЕЛ прыжок   ПКМ прицел   R заново   ESC отпустить мышь",
		"колонны и узкий коридор поджимают камеру, а зажатый прицел сводит доворот в ноль",
		"",
		"[color=#66ccff]расцепление тела и камеры — это и есть третье лицо: тело"
			+ " поворачивается к своему движению и опаздывает, камера ходит сама[/color]",
	]))


func _facing_text() -> String:
	var error := player.facing_error()
	var tint := "#7fe08a" if absf(error) < ON_TARGET else "#ffffff"
	return "[color=%s][b]%+.0f°[/b][/color]" % [tint, error]
