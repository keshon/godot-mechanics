class_name SiegeRig
extends Node3D
## МУЛЬТИПРОБА: ОСАДА.
##
## Вопрос, которого не задавала ни одна проба: **что делает граф опоры, когда один его узел
## превращается в полсотни посреди обрушения?** В сорок первой элемент падал целиком и связи
## были неизменны. В сорок третьей осколки не держали никого, и графа не было вовсе.
##
## Собрано из сцен и ресурсов трёх закрытых проб:
##
##   `43_stuff/shard.tscn`  предмет: материал, порог, скол по Вороному, повторный скол
##   `43_stuff/*.tres`      материалы и снаряды
##   `30_gun/weapon.tscn`   оружие в своём подвьюпорте со своим светом
##   `30_gun/fx.tscn`       искры, гильзы, трассеры, дырки
##
## Своего — риг и связывающий граф. Ни то ни другое не имеет смысла внутри одной пробы.

## Пауза между выстрелами в секундах.
const RATE := 0.11
## Дальность луча в метрах.
const RANGE := 120.0
## Сколько живёт вспышка у дула, секунды.
const FLASH_TIME := 0.045
## Через сколько после выстрела вылетает гильза, секунды.
const SHELL_DELAY := 0.04
## Каждый второй выстрел рисует трассер.
const TRACER_EVERY := 2
## Ниже этого низ обломка считается лежащим на земле, метры.
const GROUND := 0.35
## Моложе этого, в миллисекундах, обломок не убирают ни при каких обстоятельствах: он ещё
## летит, и его ещё не успели увидеть. Зрелище дороже кадра ровно на эти три секунды.
const YOUNG := 3000
## Уборка мусора — не физика, ей незачем идти в такт решателю. Раз в десять тиков это шесть
## раз в секунду: глазом не отличить, а стоит вдесятеро дешевле.
const SLOW_EVERY := 10
## Ступени запаса прочности, между которыми ходит ручка.
const SAFETY_STEPS := [1.2, 1.5, 2.0, 3.0]
## Насколько дальше края взрыва будить замерших, метры.
const WAKE_MARGIN := 2.0
## Радиус пробуждения вокруг только что расколотого элемента, метры.
const WAKE_REWIRE := 4.0

## КОСТЫЛЬ, И ОН ЗАПИСАН В ЗАМЕТКУ. Тридцатая проба узнаёт породу по ИМЕНИ УЗЛА, а здесь у
## каждого предмета материал-ресурс и одинаковые имена. Соглашение «опознание группой или
## физическим материалом» появилось позже тридцатой, переписывать её мультипроба не вправе —
## значит таблица искр живёт тут.
const SURFACES := {
	"бетон": {
		"count": 22, "speed": 11.0, "life": 0.5, "streak": 0.022,
		"hot": Color(1.0, 0.86, 0.6), "hole": Color(0.55, 0.54, 0.52),
	},
	"стекло": {
		"count": 34, "speed": 15.0, "life": 0.45, "streak": 0.016,
		"hot": Color(0.85, 0.95, 1.0), "hole": Color(0.75, 0.85, 0.88),
	},
	"дерево": {
		"count": 9, "speed": 5.0, "life": 0.32, "streak": 0.010,
		"hot": Color(1.0, 0.62, 0.28), "hole": Color(0.34, 0.23, 0.12),
	},
	"": {
		"count": 26, "speed": 16.0, "life": 0.8, "streak": 0.030,
		"hot": Color(1.0, 0.94, 0.82), "hole": Color(0.62, 0.61, 0.58),
	},
}

@export var rounds: Array[StuffRound] = []
@export var sensitivity := 0.0028
## СКОЛЬКО ОБЛОМКОВ РЕШАТЕЛЬ СЧИТАЕТ ОДНОВРЕМЕННО. Всё сверх этого замирает — не исчезает, а
## перестаёт быть физической задачей. Замирают самые медленные: они и так почти улеглись,
## и в кадре разницы не видно, а решателю становится легче ровно на них.
@export var live := 350
## СКОЛЬКО ОБЛОМКОВ ВООБЩЕ ЖИВЁТ В МИРЕ. Всё сверх этого исчезает, начиная с самых старых
## замерших. Это единственная ручка, которая на самом деле держит кадр: цена картинки растёт
## с числом обломков линейно, и никакая хитрость её не отменяет.
##
## ЗАПЕКАНИЕ ПРОБОВАЛОСЬ И ПРОИГРАЛО: слить замершие меши в один — 89 кадров/с против 101 без
## слияния. Слитый меш охватывает всю кучу и перестаёт отсекаться по видимости, так что четыре
## тысячи мелких ОТСЕКАЕМЫХ вызовов меняются на десятки огромных всегда-рисуемых. Красивая
## идея, отрицательный результат.
@export var keep := 1200
## ПЕРЕДАЁТ ЛИ ПАДАЮЩЕЕ УДАР ТОМУ, НА ЧТО УПАЛО. Включено — верх, обрушившись, добивает низ,
## и обрушение идёт дальше само. Выключено — остов держится, что бы на него ни свалилось.
## Разница видна с одного взгляда, поэтому это ручка, а не решение в коде.
@export var progressive := true

var shots := 0
var thinned := 0

## ДОМОВ МОЖЕТ БЫТЬ НЕСКОЛЬКО. Каждый — свой узел со своим графом и своим запасом прочности;
## риг только заводит их и показывает сумму. Ради этого мультипроба и существует: если бы
## здание было зашито в риг, второе поставить было бы некуда.
var _frames: Array[SiegeFrame] = []
## Тела и связи строятся с первого тика: до первого кадра это стоит в сотни раз дороже.
var _pending := true
var _clock := 0.0
var _next_shot := 0.0
var _yaw := 0.0
var _pitch := -0.06
var _round := 0
var _flash_until := -1.0
var _shell_at := -1.0
var _say := "—"
var _frame_ms := 0.0
var _peak_frame := 0.0
var _last_cells := 0
var _last_links := 0
var _last_ms := 0.0
var _last_at := Vector3.ZERO
var _ticks := 0
var _kick := 0.0
var _kick_speed := 0.0

@onready var _camera: Camera3D = $Camera
@onready var _fx: GunFx = $Fx
@onready var _hud: RichTextLabel = $Ui/Info
@onready var _weapon: Node3D = $Hands/Wrap/Sub/Weapon
@onready var _muzzle: Node3D = $Hands/Wrap/Sub/Weapon/Muzzle
@onready var _flash: MeshInstance3D = $Hands/Wrap/Sub/Weapon/Muzzle/Flash
@onready var _lamp: OmniLight3D = $Lamp


func _ready() -> void:
	for node in find_children("*", "Node3D", true, false):
		var frame := node as SiegeFrame
		if frame != null:
			_frames.append(frame)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_flash.visible = false
	_lamp.light_energy = 0.0


func _process(delta: float) -> void:
	_clock += delta
	_frame_ms = lerpf(_frame_ms, delta * 1000.0, 0.15)
	if _clock > 1.5:
		_peak_frame = maxf(_peak_frame, delta)

	var speed := 16.0 if Input.is_key_pressed(KEY_SHIFT) else 6.0
	var direction := _camera.global_basis * Vector3(
			Input.get_action_strength(&"move_right")
				- Input.get_action_strength(&"move_left"),
			0.0,
			Input.get_action_strength(&"move_back")
				- Input.get_action_strength(&"move_forward"))
	if Input.is_action_pressed(&"jump"):
		direction += Vector3.UP
	_camera.global_position += direction * speed * delta
	_camera.rotation = Vector3(_pitch, _yaw, 0.0)

	if Input.is_action_pressed(&"fire") and _clock >= _next_shot:
		_next_shot = _clock + RATE
		_shoot()

	_burn_flash()
	_eject_shell()
	_hold(delta)
	_readout()


func _physics_process(_delta: float) -> void:
	if _pending:
		_pending = false
		for frame in _frames:
			if not is_instance_valid(frame):
				continue
			frame.rewired.connect(_on_frame_rewired)
			frame.build()
		return
	# Сперва падает то, у чего опоры нет вовсе, и лишь потом смотрим, кому стало тяжело.
	for frame in _frames:
		if is_instance_valid(frame):
			frame.settle()
	_ticks += 1
	_pass_on()
	_retire()


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= motion.relative.x * sensitivity
		_pitch = clampf(_pitch - motion.relative.y * sensitivity, -1.5, 1.5)
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		_apply_key(key.keycode)
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _apply_key(keycode: Key) -> void:
	match keycode:
		KEY_1:
			_round = (_round + 1) % maxi(rounds.size(), 1)
		KEY_2:
			_step_safety()
		KEY_EQUAL, KEY_KP_ADD:
			keep = mini(keep + 200, 20000)
			_say = "потолок обломков: [b]%d[/b]" % keep
		KEY_MINUS, KEY_KP_SUBTRACT:
			keep = maxi(keep - 200, 200)
			_say = "потолок обломков: [b]%d[/b]" % keep
		KEY_0:
			progressive = not progressive
			_say = "передача удара вниз: [b]%s[/b]" % (
				"есть — верх добивает низ" if progressive else "нет")
		KEY_TAB:
			_restart()


func _step_safety() -> void:
	if _frames.is_empty():
		return
	var step := SAFETY_STEPS.find(snappedf(_frames[0].safety, 0.1))
	var next: float = (SAFETY_STEPS[(step + 1) % SAFETY_STEPS.size()]
			if step >= 0 else 1.5)
	for frame in _frames:
		frame.safety = next
		# Пересчёт на месте, а не перезапуск: ручка не стирает разрушенное.
		frame.recalibrate()
	_say = "запас прочности ×%.1f — пересчитан по тому, что стоит сейчас" % next


func _burn_flash() -> void:
	_flash.visible = _clock < _flash_until
	_lamp.light_energy = 7.0 if _clock < _flash_until else 0.0
	if not _flash.visible:
		return
	var material: ShaderMaterial = _flash.material_override
	material.set_shader_parameter(
			"age", clampf(1.0 - (_flash_until - _clock) / FLASH_TIME, 0.0, 1.0))


func _eject_shell() -> void:
	if _shell_at <= 0.0 or _clock < _shell_at:
		return
	_shell_at = -1.0
	var eye := _camera.global_basis
	_fx.add_shell(
			_camera.global_position + eye * Vector3(0.22, -0.12, -0.5), eye.x, eye.y)


## ПОЗА ПЕРЕЕЗЖАЕТ СО СЦЕНОЙ, А ЖИЗНЬ — НЕТ. Проверено контрольным кадром: `weapon.tscn`
## несёт положение ствола в себе. А вот отдача и покачивание живут в риге тридцатой пробы и
## вместе со сценой не едут — их приходится писать заново в каждой мультипробе.
func _hold(delta: float) -> void:
	_kick_speed -= _kick * 220.0 * delta
	_kick_speed *= exp(-12.0 * delta)
	_kick = maxf(_kick + _kick_speed * delta, 0.0)
	var bob := sin(_clock * 6.0) * 0.004
	_weapon.position = Vector3(0.24, -0.24 + bob, -0.62 + _kick * 0.07)
	_weapon.rotation = Vector3(_kick * 0.16, 0.0, 0.0)


func _shoot() -> void:
	if rounds.is_empty():
		return
	shots += 1
	var shot: StuffRound = rounds[_round]
	var from := _camera.global_position
	var direction := -_camera.global_basis.z
	var muzzle := from + _camera.global_basis * Vector3(0.16, -0.1, -0.55)
	_flash_until = _clock + FLASH_TIME
	_lamp.global_position = muzzle
	# ШЕЙДЕРУ ВСПЫШКИ НУЖЕН НЕ ТОЛЬКО ВОЗРАСТ. Он прячет факел за стволом, и для этого ему
	# нужно знать, ГДЕ НА ЭКРАНЕ ствол. Без `barrel_screen` маска режет пламя не в том месте.
	var material: ShaderMaterial = _flash.material_override
	material.set_shader_parameter("hider", 0.0)
	material.set_shader_parameter("seed", randf())
	material.set_shader_parameter("age", 0.0)
	material.set_shader_parameter(
			"barrel_screen", Vector2(_muzzle.global_position.x * 0.4, 0.0))
	_shell_at = _clock + SHELL_DELAY
	_kick_speed = minf(_kick_speed + 4.6, 9.0)
	_kick = minf(_kick, 1.3)

	var query := PhysicsRayQueryParameters3D.create(from, from + direction * RANGE)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var to := from + direction * RANGE
	if not hit.is_empty():
		to = hit["position"]
	if shots % TRACER_EVERY == 0:
		_fx.add_tracer(muzzle, to)
	if hit.is_empty():
		return

	var solid := hit["collider"] as StuffSolid
	var surface: Dictionary = SURFACES[""]
	if solid != null and solid.stuff != null and SURFACES.has(solid.stuff.title):
		surface = SURFACES[solid.stuff.title]
	_last_at = to
	_fx.add_hole(to, hit["normal"], direction, surface["hole"])
	_fx.add_sparks(to, hit["normal"], direction, surface)
	if solid == null:
		return
	if shot.blast > 0.0:
		_blast(to, direction, shot)
		_say = "[b]%s[/b] — радиус %.0f м" % [shot.title, shot.blast]
		return
	var threshold := solid.limit()
	solid.hit(to, direction, shot)
	if is_instance_valid(solid):
		_say = _why_whole(solid, threshold)


## ПОЧЕМУ НЕ РАСКОЛОЛОСЬ — три разные причины, и путать их нельзя.
func _why_whole(solid: StuffSolid, threshold: float) -> String:
	var kind: String = solid.stuff.title if solid.stuff != null else "?"
	if solid.depth >= solid.max_depth:
		return "[b]%s[/b]: глубина %d — глубже не дробим, только толкаем" % [
			kind, solid.depth]
	if solid.stuff != null and solid.stuff.pieces(solid.soaked, solid.volume,
			solid.most) < 2:
		return "[b]%s[/b], %.4f м³ — мельче своей крошки (%.4f м³), дальше не дробится" % [
			kind, solid.volume, solid.stuff.grit * 2.0]
	return "[b]%s[/b] держится: %.0f из %.0f Дж" % [kind, solid.soaked, threshold]


## УДЕРЖАНИЕ БЮДЖЕТА ЖИВОЙ ФИЗИКИ. Обвал будит тысячи тел разом, и беда не в том, что они
## считаются, а в том, что каждый новый осколок будит спящую кучу цепочкой через контакты:
## один выстрел поднимает две тысячи тел из трёх. Замороженное тело разбудить нельзя — цепочка
## обрывается.
##
## НО ЗАМИРАТЬ МОЖЕТ НЕ ВСЁ. Обломок, лежащий на остове дома, обязан упасть, когда остов
## выбьют: расстрелял середину, верх осел на культю, спустился и расстрелял первый этаж —
## всё должно поехать вместе. Поэтому на покой уходит только то, что лежит НА ЗЕМЛЕ: у земли
## опору не выбить, и такой обломок действительно уже никогда не оживёт.
##
## Плюс к этому: замирают только те, кого решатель УЖЕ УСЫПИЛ САМ. Выбор «самых медленных»
## морозит куски на вершине параболы — 201 из 1459 висел в воздухе, — и никакой порог по
## скорости не спасает: при 1.2 м/с вершина длится пятнадцать тиков.
func _retire() -> void:
	if _ticks % SLOW_EVERY != 0:
		return
	var counted := 0
	var resting: Array[StuffSolid] = []
	var loose: Array[StuffSolid] = []
	for node in get_tree().get_nodes_in_group("solid"):
		var body := node as StuffSolid
		if body == null:
			continue
		if not _held(body):
			loose.append(body)
		if body.retired:
			continue
		counted += 1
		if body.sleeping:
			resting.append(body)
	# Ничего лишнего — уходим, не трогая ни габаритов, ни узлов.
	if counted <= live and loose.size() <= keep:
		return
	var over := counted - live
	var done := 0
	for body in resting:
		if done >= over:
			break
		if _on_ground(body):
			body.retire()
			done += 1
	_thin(loose)


## Ручка доходит до предметов группой: осколки рождаются на ходу, знать их поимённо нельзя.
func _pass_on() -> void:
	if _ticks % SLOW_EVERY != 3:
		return
	var share := 0.5 if progressive else 0.0
	for node in get_tree().get_nodes_in_group("solid"):
		var body := node as StuffSolid
		if body != null and body.passes_on != share:
			body.passes_on = share


func _held(body: StuffSolid) -> bool:
	for frame in _frames:
		if is_instance_valid(frame) and frame.holds(body):
			return true
	return false


## Лежит ли обломок на земле — не на другом теле, а именно на земле. Проверяется низом его
## габарита, а не центром: плита лежит плашмя, и её центр от земли дальше, чем кажется.
func _on_ground(body: StuffSolid) -> bool:
	var visual := body.get_node("Mesh") as MeshInstance3D
	var box := visual.get_aabb()
	return body.global_position.y - box.size.y * 0.5 < GROUND


## УБЫЛЬ — ЕДИНСТВЕННОЕ, ЧТО ДЕЙСТВИТЕЛЬНО ДЕРЖИТ КАДР. Самые старые обломки исчезают.
##
## Замирание оказалось слишком осторожным: безопасно замереть может только лежащее НА ЗЕМЛЕ, а
## в глубокой куче на земле почти никто не лежит. Исчезновение безопасно всегда: то, чего нет,
## не повиснет и не подведёт.
##
## Возраст берётся с самого тела, а не из очереди рига: очередь пропускает целый путь
## рождения — обломки, расколовшиеся ОТ УДАРА О ЗЕМЛЮ, в неё не попадают, и потолок не держится.
func _thin(loose: Array[StuffSolid]) -> void:
	var over := loose.size() - keep
	if over <= 0:
		return
	# ПЕРВЫМИ УХОДЯТ МЕЛКИЕ. Возраст решает, КОГО ВООБЩЕ МОЖНО трогать (свежее трёх секунд
	# не трогаем — оно ещё летит и его не видели), а среди тех, кого можно, — размер: крошку
	# никто не разглядывает, а крупный обломок держит вид кучи. В настоящей игре мелочь бы
	# заменили спрайтом или статическим мешем при приземлении; здесь она просто уходит.
	var now := Time.get_ticks_msec()
	var ripe: Array[StuffSolid] = []
	for body in loose:
		if now - body.born_at >= YOUNG:
			ripe.append(body)
	ripe.sort_custom(
			func(first: StuffSolid, second: StuffSolid) -> bool:
				return first.volume < second.volume)
	for index in mini(over, ripe.size()):
		var body: StuffSolid = ripe[index]
		for frame in _frames:
			if is_instance_valid(frame):
				frame.forget(body)
		body.queue_free()
		thinned += 1


## ФУГАС. Достаёт всё в радиусе, слабея к краю: доля энергии падает как куб расстояния, потому
## что так падает плотность энергии в расходящейся волне. Одним ударом забирает ряд колонн —
## ровно этого не хватало, чтобы валить большие дома.
func _blast(at: Vector3, direction: Vector3, shot: StuffRound) -> void:
	var reach_squared := shot.blast * shot.blast
	for node in get_tree().get_nodes_in_group("solid"):
		var body := node as StuffSolid
		if body == null:
			continue
		var away: Vector3 = body.global_position - at
		var apart_squared := away.length_squared()
		if apart_squared > reach_squared:
			continue
		var near: float = 1.0 - sqrt(apart_squared) / shot.blast
		var share: float = near * near * near
		body.bruise(
				shot.energy * share,
				shot.momentum * share,
				away.normalized() if apart_squared > 0.0001 else direction)
	_wake_near(at, shot.blast + WAKE_MARGIN)
	_last_at = at


## Разрушение будит соседей, отправленных на покой: из-под них могло уйти то, на чём они
## лежали. Далёкие остаются замершими — цепочка пробуждения по-прежнему не расходится.
func _wake_near(at: Vector3, reach: float) -> void:
	var reach_squared := reach * reach
	for node in get_tree().get_nodes_in_group("solid"):
		var body := node as StuffSolid
		if body == null or not body.retired:
			continue
		if body.global_position.distance_squared_to(at) < reach_squared:
			body.revive()


func _restart() -> void:
	shots = 0
	_peak_frame = 0.0
	get_tree().reload_current_scene()


func _standing() -> int:
	var count := 0
	for frame in _frames:
		if is_instance_valid(frame):
			count += frame.pieces.size()
	return count


func _fallen() -> int:
	var count := 0
	for frame in _frames:
		if is_instance_valid(frame):
			count += frame.fallen
	return count


func _rewires() -> int:
	var count := 0
	for frame in _frames:
		if is_instance_valid(frame):
			count += frame.rewires
	return count


func _readout() -> void:
	var shot: StuffRound = rounds[_round] if not rounds.is_empty() else null
	var bodies := get_tree().get_nodes_in_group("solid").size()
	_hud.text = "\n".join(PackedStringArray([
		_say,
		"домов %d   стоит %d   упало %d   тел %d   перевязок %d   последняя: %d ячеек, %.1f мс"
			% [_frames.size(), _standing(), _fallen(), bodies, _rewires(),
				_last_cells, _last_ms],
		"обломков в мире %d из %d   убрано за игру %d" % [bodies, keep, thinned],
		"кадр %.1f мс   худший %.1f   физика %.1f мс   выстрелов %d" % [
			_frame_ms, _peak_frame * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, shots],
		"",
		"WASD лететь   SHIFT быстрее   ПРОБЕЛ вверх   ЛКМ огонь   TAB заново",
		"1 снаряд: [b]%s[/b]   калибр %.0f мм   импульс %.0f кг·м/с" % [
			shot.title if shot != null else "—",
			(shot.calibre if shot != null else 0.0) * 1000.0,
			shot.momentum if shot != null else 0.0],
		"0 обрушение прогрессирующее: %s   (падающее бьёт то, на что упало)" % (
			"[b]вкл[/b]" if progressive else "выкл"),
		"+ / −  потолок обломков: [b]%d[/b]   (первыми уходят самые мелкие)" % keep,
		"2 запас прочности: ×%.1f" % (
			_frames[0].safety if not _frames.is_empty() else 0.0),
		"удар о мир: %s   считаемых тел %d из 700   (замершие не в счёт)" % [
			"дробит" if StuffSolid.alive < 700 else "[b]ждёт[/b]", StuffSolid.alive],
		"",
		"[color=#66ccff]расколотая колонна перестаёт быть одним узлом графа и становится"
			+ " полусотней. связи наследуются посреди обрушения.[/color]",
	]))


func _on_frame_rewired(cells: int, links: int, spent_ms: float) -> void:
	_last_cells = cells
	_last_links = links
	_last_ms = spent_ms
	_wake_near(_last_at, WAKE_REWIRE)
	_say = "узел графа стал [b]%d[/b] ячейками — перевязка %.1f мс, связей в доме %d" % [
		cells, spent_ms, links]
