extends RichTextLabel
## ПОКАЗАНИЯ ПРОБЫ ПРО ДВИЖЕНИЕ.
##
## Проба про ощущение, а ощущению верится легче, когда под ним видно число. Главное здесь —
## ПРЫЖОК: связанные страйф-джампы гонят его в плюс, прыжок по прямой — в минус.

## Через сколько секунд прибавка от прыжка перестаёт показываться.
const GAIN_LIFE := 3.0

## Кого читать. Путь, а не прямая ссылка, чтобы связь была видна в `walk.tscn` простым
## читаемым текстом.
@export var player_path: NodePath = ^"../../Player"

var _last_gain := 0.0
var _gain_age := 99.0

@onready var player: WalkPlayer = get_node(player_path)


func _ready() -> void:
	# Сигнал, а не опрос. Показания не лезут в игрока спросить, приземлился ли он в этом
	# кадре, — игрок сообщает сам, и будятся только те, кому это нужно.
	player.landed.connect(_on_player_landed)


func _process(delta: float) -> void:
	_gain_age += delta
	text = "\n".join(PackedStringArray([
		"скорость [b]%.1f[/b] м/с   пик %.1f   прыжок %s   %s" % [
			player.speed(), player.peak_speed, _gain_text(),
			"на земле" if player.is_on_floor()
				else "[color=#66ccff]в воздухе[/color]"],
		"",
		"WASD бег   ПРОБЕЛ прыжок   R заново   ESC отпустить мышь",
		"по рампе, дальше два острова справа: второй разрыв берётся только на скорости,"
			+ " сохранённой через первую посадку",
		"",
		"[color=#66ccff]страйф-джамп никто не проектировал — он выпал из скалярного"
			+ " произведения[/color]",
	]))


## Прибавка живёт три секунды: она про последний прыжок, а не про состояние.
func _gain_text() -> String:
	if _gain_age > GAIN_LIFE:
		return "—"
	var tint := "#7fe08a" if _last_gain >= 0.0 else "#ff8a6a"
	return "[color=%s][b]%+.2f[/b] м/с[/color]" % [tint, _last_gain]


func _on_player_landed(speed_delta: float) -> void:
	_last_gain = speed_delta
	_gain_age = 0.0
