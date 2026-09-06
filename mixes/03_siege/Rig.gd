extends Node3D
class_name SiegeRig
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

const RATE := 0.11
## Ниже этого низ обломка считается лежащим на земле.
const GROUND := 0.35
## Моложе этого обломок не убирают ни при каких обстоятельствах: он ещё летит, и его ещё не
## успели увидеть. Зрелище дороже кадра ровно на эти три секунды.
const YOUNG := 3000
const RANGE := 120.0
const FLASH_TIME := 0.045

## КОСТЫЛЬ, И ОН ЗАПИСАН В ЗАМЕТКУ. Тридцатая проба узнаёт породу по ИМЕНИ УЗЛА, а здесь у
## каждого предмета материал-ресурс и одинаковые имена. Соглашение «опознание группой или
## физическим материалом» появилось позже тридцатой, переписывать её мультипроба не вправе —
## значит таблица искр живёт тут.
const SURFACES := {
	"бетон": {"count": 22, "speed": 11.0, "life": 0.5, "streak": 0.022,
		"hot": Color(1.0, 0.86, 0.6), "hole": Color(0.55, 0.54, 0.52)},
	"стекло": {"count": 34, "speed": 15.0, "life": 0.45, "streak": 0.016,
		"hot": Color(0.85, 0.95, 1.0), "hole": Color(0.75, 0.85, 0.88)},
	"дерево": {"count": 9, "speed": 5.0, "life": 0.32, "streak": 0.010,
		"hot": Color(1.0, 0.62, 0.28), "hole": Color(0.34, 0.23, 0.12)},
	"": {"count": 26, "speed": 16.0, "life": 0.8, "streak": 0.030,
		"hot": Color(1.0, 0.94, 0.82), "hole": Color(0.62, 0.61, 0.58)},
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

var _clock := 0.0
var _next := 0.0
var _yaw := 0.0
var _pitch := -0.06
var _r := 0
var _flash_until := -1.0
var _shell_at := -1.0
var _say := "—"
var _frame_ms := 0.0
var _peak := 0.0
var _last_cells := 0
var _last_links := 0
var _last_ms := 0.0
var _last_at := Vector3.ZERO
var thinned := 0
var _slow := 0
var _kick := 0.0
var _kick_v := 0.0

@onready var _cam: Camera3D = $Camera
## ДОМОВ МОЖЕТ БЫТЬ НЕСКОЛЬКО. Каждый — свой узел со своим графом и своим запасом прочности;
## риг только заводит их и показывает сумму. Ради этого мультипроба и существует: если бы
## здание было зашито в риг, второе поставить было бы некуда.
var _frames: Array[SiegeFrame] = []
@onready var _fx: GunFx = $Fx
@onready var _hud: RichTextLabel = $Ui/Info
@onready var _weapon: Node3D = $Hands/Wrap/Sub/Weapon
@onready var _muzzle_vm: Node3D = $Hands/Wrap/Sub/Weapon/Muzzle
@onready var _flash: MeshInstance3D = $Hands/Wrap/Sub/Weapon/Muzzle/Flash
@onready var _lamp: OmniLight3D = $Lamp

## Тела и связи строятся с первого тика: до первого кадра это стоит в сотни раз дороже.
var _pending := true


func _ready() -> void:
	for n in find_children("*", "Node3D", true, false):
		var f := n as SiegeFrame
		if f != null:
			_frames.append(f)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_flash.visible = false
	_lamp.light_energy = 0.0


func _physics_process(_delta: float) -> void:
	if _pending:
		_pending = false
		for f in _frames:
			if not is_instance_valid(f):
				continue
			f.rewired.connect(_on_rewired)
			f.build()
		return
	# Сперва падает то, у чего опоры нет вовсе, и лишь потом смотрим, кому стало тяжело.
	for f in _frames:
		if is_instance_valid(f):
			f.settle()
	_pass_on()
	_retire()


## УДЕРЖАНИЕ БЮДЖЕТА ЖИВОЙ ФИЗИКИ. Обвал будит тысячи тел разом, и главная беда не в том, что
## они считаются, а в том, что каждый новый осколок будит спящую кучу цепочкой через контакты:
## один выстрел поднимал две тысячи тел из трёх.
##
## Замороженное тело разбудить нельзя — цепочка обрывается. Поэтому на покой отправляются
## только те, кого движок УЖЕ УСЫПИЛ САМ.
##
## Первый заход выбирал «самых медленных» и был неверен: вершина параболы — самый медленный
## момент полёта, и подброшенный взрывом кусок замерзал прямо в воздухе. Их набиралось 201 из
## 1459. Никакой порог по скорости тут не спасает — при 1.2 м/с вершина длится пятнадцать
## тиков. Спящее тело, в отличие от медленного, лежит наверняка.
## УДЕРЖАНИЕ БЮДЖЕТА ЖИВОЙ ФИЗИКИ. Обвал будит тысячи тел разом, и беда не в том, что они
## считаются, а в том, что каждый новый осколок будит спящую кучу цепочкой через контакты:
## один выстрел поднимал две тысячи тел из трёх. Замороженное тело разбудить нельзя — цепочка
## обрывается.
##
## НО ЗАМИРАТЬ МОЖЕТ НЕ ВСЁ. Обломок, лежащий на остове дома, обязан упасть, когда остов
## выбьют: расстрелял середину, верх осел на культю, спустился и расстрелял первый этаж —
## всё должно поехать вместе. Поэтому на покой уходит только то, что лежит НА ЗЕМЛЕ: у земли
## опору не выбить, и такой обломок действительно уже никогда не оживёт.
##
## Плюс к этому: замирают только те, кого решатель УЖЕ УСЫПИЛ САМ. Первый заход выбирал самых
## медленных и морозил их на вершине параболы — 201 кусок из 1459 висел в воздухе.
func _process(delta: float) -> void:
	_clock += delta
	_frame_ms = lerpf(_frame_ms, delta * 1000.0, 0.15)
	if _clock > 1.5:
		_peak = maxf(_peak, delta)

	var speed := 16.0 if Input.is_key_pressed(KEY_SHIFT) else 6.0
	var dir := _cam.global_basis * Vector3(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		0.0,
		Input.get_action_strength(&"move_back") - Input.get_action_strength(&"move_forward"))
	if Input.is_action_pressed(&"jump"):
		dir += Vector3.UP
	_cam.global_position += dir * speed * delta
	_cam.rotation = Vector3(_pitch, _yaw, 0.0)

	if Input.is_action_pressed(&"fire") and _clock >= _next:
		_next = _clock + RATE
		_shoot()

	_flash.visible = _clock < _flash_until
	_lamp.light_energy = 7.0 if _clock < _flash_until else 0.0
	if _flash.visible:
		var fm: ShaderMaterial = _flash.material_override
		fm.set_shader_parameter("age",
			clampf(1.0 - (_flash_until - _clock) / FLASH_TIME, 0.0, 1.0))
	if _shell_at > 0.0 and _clock >= _shell_at:
		_shell_at = -1.0
		var b := _cam.global_basis
		_fx.shell(_cam.global_position + b * Vector3(0.22, -0.12, -0.5), b.x, b.y)
	_hold(delta)
	_readout()


## ПОЗА ПЕРЕЕЗЖАЕТ СО СЦЕНОЙ, А ЖИЗНЬ — НЕТ. Проверено контрольным кадром: `weapon.tscn`
## несёт положение ствола в себе. А вот отдача и покачивание живут в риге тридцатой пробы и
## вместе со сценой не едут — их приходится писать заново в каждой мультипробе.
func _hold(delta: float) -> void:
	_kick_v -= _kick * 220.0 * delta
	_kick_v *= exp(-12.0 * delta)
	_kick = maxf(_kick + _kick_v * delta, 0.0)
	var bob := sin(_clock * 6.0) * 0.004
	_weapon.position = Vector3(0.24, -0.24 + bob, -0.62 + _kick * 0.07)
	_weapon.rotation = Vector3(_kick * 0.16, 0.0, 0.0)


func _shoot() -> void:
	if rounds.is_empty():
		return
	shots += 1
	var shot: StuffRound = rounds[_r]
	var from := _cam.global_position
	var dir := -_cam.global_basis.z
	var muzzle := from + _cam.global_basis * Vector3(0.16, -0.1, -0.55)
	_flash_until = _clock + FLASH_TIME
	_lamp.global_position = muzzle
	# ШЕЙДЕРУ ВСПЫШКИ НУЖЕН НЕ ТОЛЬКО ВОЗРАСТ. Он прячет факел за стволом, и для этого ему
	# нужно знать, ГДЕ НА ЭКРАНЕ ствол. Без `barrel_screen` маска резала пламя не в том месте.
	var fm: ShaderMaterial = _flash.material_override
	fm.set_shader_parameter("hider", 0.0)
	fm.set_shader_parameter("seed", randf())
	fm.set_shader_parameter("age", 0.0)
	fm.set_shader_parameter("barrel_screen",
		Vector2(_muzzle_vm.global_position.x * 0.4, 0.0))
	_shell_at = _clock + 0.04
	_kick_v = minf(_kick_v + 4.6, 9.0)
	_kick = minf(_kick, 1.3)

	var q := PhysicsRayQueryParameters3D.create(from, from + dir * RANGE)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	var to := from + dir * RANGE
	if not r.is_empty():
		to = r["position"]
	if shots % 2 == 0:
		_fx.tracer(muzzle, to)
	if r.is_empty():
		return

	var s := r["collider"] as StuffSolid
	var surf: Dictionary = SURFACES[""]
	if s != null and s.stuff != null and SURFACES.has(s.stuff.title):
		surf = SURFACES[s.stuff.title]
	_last_at = to
	_fx.hole(to, r["normal"], dir, surf["hole"])
	_fx.sparks(to, r["normal"], dir, surf)
	if s == null:
		return
	var kind: String = s.stuff.title if s.stuff != null else "?"
	var lim := s.limit()
	if shot.blast > 0.0:
		_blast(to, dir, shot)
		_say = "[b]%s[/b] — радиус %.0f м" % [shot.title, shot.blast]
		return
	s.hit(to, dir, shot)
	if is_instance_valid(s):
		# ПОЧЕМУ НЕ РАСКОЛОЛОСЬ — три разные причины, и путать их нельзя.
		if s.depth >= s.max_depth:
			_say = "[b]%s[/b]: глубина %d — глубже не дробим, только толкаем" % [kind, s.depth]
		elif s.stuff != null and s.stuff.pieces(s.soaked, s.volume, s.most) < 2:
			_say = "[b]%s[/b], %.4f м³ — мельче своей крошки (%.4f м³), дальше не дробится" % [
				kind, s.volume, s.stuff.grit * 2.0]
		else:
			_say = "[b]%s[/b] держится: %.0f из %.0f Дж" % [kind, s.soaked, lim]


func _retire() -> void:
	# НЕ КАЖДЫЙ ТИК. Уборка мусора — не физика, ей незачем идти в такт решателю. Раз в десять
	# тиков это шесть раз в секунду: глазом не отличить, а стоит вдесятеро дешевле.
	_slow += 1
	if _slow % 10 != 0:
		return
	var counted := 0
	var resting: Array[StuffSolid] = []
	var loose: Array[StuffSolid] = []
	for n in get_tree().get_nodes_in_group("solid"):
		var b := n as StuffSolid
		if b == null:
			continue
		if not _held(b):
			loose.append(b)
		if b.retired:
			continue
		counted += 1
		if b.sleeping:
			resting.append(b)
	# Ничего лишнего — уходим, не трогая ни габаритов, ни узлов.
	if counted <= live and loose.size() <= keep:
		return
	var over := counted - live
	var done := 0
	for b in resting:
		if done >= over:
			break
		if _on_ground(b):
			b.retire()
			done += 1
	_thin(loose)


## Ручка доходит до предметов группой: осколки рождаются на ходу, знать их поимённо нельзя.
func _pass_on() -> void:
	if _slow % 10 != 3:
		return
	var share := 0.5 if progressive else 0.0
	for n in get_tree().get_nodes_in_group("solid"):
		var b := n as StuffSolid
		if b != null and b.passes_on != share:
			b.passes_on = share


func _held(b: StuffSolid) -> bool:
	for f in _frames:
		if is_instance_valid(f) and f.holds(b):
			return true
	return false


## Лежит ли обломок на земле — не на другом теле, а именно на земле. Проверяется низом его
## габарита, а не центром: плита лежит плашмя, и её центр от земли дальше, чем кажется.
func _on_ground(b: StuffSolid) -> bool:
	var box: AABB = (b.get_node("Mesh") as MeshInstance3D).get_aabb()
	return b.global_position.y - box.size.y * 0.5 < GROUND


## УБЫЛЬ — ЕДИНСТВЕННОЕ, ЧТО ДЕЙСТВИТЕЛЬНО ДЕРЖИТ КАДР. Самые старые обломки исчезают.
##
## Замирание оказалось слишком осторожным: безопасно замереть может только лежащее НА ЗЕМЛЕ, а
## в глубокой куче на земле почти никто не лежит. Исчезновение безопасно всегда: то, чего нет,
## не повиснет и не подведёт.
##
## Возраст берётся с самого тела, а не из очереди рига. Очередь пропускала целый путь рождения:
## обломки, расколовшиеся ОТ УДАРА О ЗЕМЛЮ, в неё не попадали, и потолок не держался.
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
	for b in loose:
		if now - b.born_at >= YOUNG:
			ripe.append(b)
	ripe.sort_custom(func(a: StuffSolid, c: StuffSolid) -> bool:
		return a.volume < c.volume)
	for i in mini(over, ripe.size()):
		var loose_i: StuffSolid = ripe[i]
		for f in _frames:
			if is_instance_valid(f):
				f.forget(loose_i)
		loose_i.queue_free()
		thinned += 1


## ФУГАС. Достаёт всё в радиусе, слабея к краю: доля энергии падает как куб расстояния, потому
## что так падает плотность энергии в расходящейся волне. Одним ударом забирает ряд колонн —
## ровно этого не хватало, чтобы валить большие дома.
func _blast(at: Vector3, dir: Vector3, shot: StuffRound) -> void:
	var r2 := shot.blast * shot.blast
	var hurt := 0
	for n in get_tree().get_nodes_in_group("solid"):
		var b := n as StuffSolid
		if b == null:
			continue
		var away: Vector3 = b.global_position - at
		var d2 := away.length_squared()
		if d2 > r2:
			continue
		var near: float = 1.0 - sqrt(d2) / shot.blast
		var share: float = near * near * near
		b.bruise(shot.energy * share, shot.momentum * share,
			away.normalized() if d2 > 0.0001 else dir)
		hurt += 1
	_wake_near(at, shot.blast + 2.0)
	_last_at = at


## Разрушение будит соседей, отправленных на покой: из-под них могло уйти то, на чём они
## лежали. Далёкие остаются замершими — цепочка пробуждения по-прежнему не расходится.
func _wake_near(at: Vector3, reach: float) -> void:
	var r2 := reach * reach
	for n in get_tree().get_nodes_in_group("solid"):
		var b := n as StuffSolid
		if b != null and b.retired and b.global_position.distance_squared_to(at) < r2:
			b.revive()


func _on_rewired(cells: int, links: int, ms: float) -> void:
	_last_cells = cells
	_last_links = links
	_last_ms = ms
	_wake_near(_last_at, 4.0)
	_say = "узел графа стал [b]%d[/b] ячейками — перевязка %.1f мс, связей в доме %d" % [
		cells, ms, links]


func _unhandled_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= mm.relative.x * sensitivity
		_pitch = clampf(_pitch - mm.relative.y * sensitivity, -1.5, 1.5)
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_1: _r = (_r + 1) % maxi(rounds.size(), 1)
			KEY_2:
				var steps := [1.2, 1.5, 2.0, 3.0]
				var i := steps.find(snappedf(_frames[0].safety, 0.1))
				var next: float = steps[(i + 1) % steps.size()] if i >= 0 else 1.5
				for f in _frames:
					f.safety = next
					# Пересчёт на месте, а не перезапуск: ручка не стирает разрушенное.
					f.recalibrate()
				_say = "запас прочности ×%.1f — пересчитан по тому, что стоит сейчас" % next
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
			KEY_TAB: _restart()
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _restart() -> void:
	shots = 0
	_peak = 0.0
	get_tree().reload_current_scene()


func _standing() -> int:
	var n := 0
	for f in _frames:
		if is_instance_valid(f):
			n += f.pieces.size()
	return n


func _fallen() -> int:
	var n := 0
	for f in _frames:
		if is_instance_valid(f):
			n += f.fallen
	return n


func _rewires() -> int:
	var n := 0
	for f in _frames:
		if is_instance_valid(f):
			n += f.rewires
	return n


func _readout() -> void:
	var shot: StuffRound = rounds[_r] if not rounds.is_empty() else null
	_hud.text = "\n".join(PackedStringArray([
		_say,
		"домов %d   стоит %d   упало %d   тел %d   перевязок %d   последняя: %d ячеек, %.1f мс" % [
			_frames.size(), _standing(), _fallen(),
			get_tree().get_nodes_in_group("solid").size(),
			_rewires(), _last_cells, _last_ms],
		"обломков в мире %d из %d   убрано за игру %d" % [
			get_tree().get_nodes_in_group("solid").size(), keep, thinned],
		"кадр %.1f мс   худший %.1f   физика %.1f мс   выстрелов %d" % [
			_frame_ms, _peak * 1000.0,
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
		"2 запас прочности: ×%.1f" % (_frames[0].safety if not _frames.is_empty() else 0.0),
		"удар о мир: %s   считаемых тел %d из 700   (замершие не в счёт)" % [
			"дробит" if StuffSolid.alive < 700 else "[b]ждёт[/b]", StuffSolid.alive],
		"",
		"[color=#66ccff]расколотая колонна перестаёт быть одним узлом графа и становится"
			+ " полусотней. связи наследуются посреди обрушения.[/color]",
	]))
