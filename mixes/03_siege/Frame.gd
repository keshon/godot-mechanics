@tool
extends Node3D
class_name SiegeFrame
## ЗДАНИЕ ИЗ ПРЕДМЕТОВ СОРОК ТРЕТЬЕЙ, СВЯЗАННОЕ ГРАФОМ СОРОК ПЕРВОЙ.
##
## Граф живёт СНАРУЖИ тел, в словарях. У `StuffSolid` нет и не должно быть полей «сосед»,
## «несущая способность», «стоит ли»: это понятия сорок первой пробы, а тело принадлежит
## сорок третьей. Ткань соединяет их, не влезая ни в ту, ни в другую — и именно поэтому она
## живёт здесь, а не в пробах.
##
## Вопрос мультипробы: **что делает граф опоры, когда один его узел превращается в полсотни
## посреди обрушения?** Ни одна проба его не задавала. В сорок первой элемент падал целиком,
## в сорок третьей осколки не держали никого.

const SOLID := preload("res://probes/43_stuff/shard.tscn")

const COLUMN := Vector3(0.45, 2.4, 0.45)
const BEAM := Vector3(2.6, 0.35, 0.35)
const SLAB := Vector3(2.6, 0.28, 2.6)
const STEP := 2.6
## Насколько раздуваются объёмы при поиске соседей.
const TOUCH := 0.06
## Насколько ниже меня должен кончаться сосед, чтобы считаться подпоркой.
const UNDER := 0.25

signal rewired(cells: int, links: int, ms: float)

## Габарит дома, чтобы видеть его В РЕДАКТОРЕ. Дом строится процедурно и до запуска не
## существует — а расставить два дома, не видя ни одного, нельзя. Показываем не сам дом, а
## место, которое он займёт: этого хватает, чтобы двигать и не пересекать.
const PREVIEW := "Габарит"

@export var stuff: StuffKind
@export var floors := 3:
	set(v):
		floors = v
		_preview()
@export var span := 2:
	set(v):
		span = v
		_preview()
## Во сколько раз элемент держит больше, чем несёт. Ниже — карточный домик.
@export var safety := 1.5
## ЧТО ДЕЛАТЬ СО СПОСОБНОСТЬЮ РАСКОЛОТОГО ЭЛЕМЕНТА — главный вопрос мультипробы.
## Включено: ячейки делят способность родителя по своему объёму, и остаток колонны
## продолжает держать. Выключено: способность считается от собственного веса ячейки, и
## щебень не держит ничего — тогда расколоть элемент равно снести его целиком.
@export var inherit := true

var pieces: Array[StuffSolid] = []
var fallen := 0
var rewires := 0
var rewire_ms := 0.0
## Чем именно кончился элемент: опоры не стало или нагрузка задавила.
var lost_support := 0
var overloaded := 0

## ГРАФ СЧИТАЕТСЯ, ТОЛЬКО КОГДА ЧТО-ТО ИЗМЕНИЛОСЬ. Стоящий нетронутый дом не меняется, и
## пересчитывать его каждый тик — чистая трата: башня на 2554 элемента стоила 50 мс физики,
## НЕ ПАДАЯ И БЕЗ ЕДИНОГО ВЫСТРЕЛА. Она же в обвале стоила 15 мс — потому что упавшие элементы
## из графа уходят, и считать становилось нечего.
##
## Признак был на виду и читался наоборот: «когда падает — кадр лучше». Обвал не дорог; дорог
## был покой.
var _dirty := true

## ВСЁ КЭШИРУЕТСЯ, И ЭТО НЕ ОПТИМИЗАЦИЯ, А УСЛОВИЕ РАБОТЫ. Первый заход считал габарит
## элемента через `get_node("Mesh").get_aabb()` прямо в цикле нагрузки — двенадцать проходов
## по полусотне элементов каждый физический тик, и кадр стоил 170 мс. Стоящий элемент
## заморожен и не двигается, значит габарит и список «кто подо мной» верны, пока граф не
## перестроят.
var _near := {}
var _below := {}
var _aabb := {}
var _anchor := {}
var _cap := {}
var _load := {}


func _ready() -> void:
	if Engine.is_editor_hint():
		# Отложенно: во время `_ready` дерево редактора ещё собирается, и добавленный узел
		# может не дойти до вида.
		_preview.call_deferred()


func _preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var mi := get_node_or_null(PREVIEW) as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = PREVIEW
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.75, 1.0, 0.22)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = mat
		add_child(mi)
		# Без владельца — значит в сохранённую сцену не попадёт.
		mi.owner = null
		mi.set_meta("_edit_lock_", true)
	var wide: float = span * STEP + COLUMN.x
	var high: float = floors * (COLUMN.y + BEAM.y + SLAB.y)
	var box := BoxMesh.new()
	box.size = Vector3(wide, high, wide)
	mi.mesh = box
	mi.position = Vector3(0.0, high * 0.5, 0.0)


## Строится с первого тика, а не из `_ready`: урок сорок первой — тела, созданные до первого
## кадра, стоят в сотни раз дороже.
func build() -> void:
	# Габарит — подсказка редактора, в игре ему делать нечего.
	var hint := get_node_or_null(PREVIEW)
	if hint != null:
		hint.free()
	for c in get_children():
		c.queue_free()
	pieces.clear()
	_near.clear()
	_below.clear()
	_aabb.clear()
	_anchor.clear()
	_cap.clear()
	_load.clear()
	fallen = 0
	lost_support = 0
	overloaded = 0
	rewires = 0
	rewire_ms = 0.0

	var lift := COLUMN.y + BEAM.y + SLAB.y
	for f in floors:
		var y := f * lift
		for x in span + 1:
			for z in span + 1:
				_add(Vector3((x - span * 0.5) * STEP, y + COLUMN.y * 0.5,
					(z - span * 0.5) * STEP), COLUMN, f == 0)
		var top := y + COLUMN.y
		for x in span:
			for z in span + 1:
				_add(Vector3((x - span * 0.5 + 0.5) * STEP, top + BEAM.y * 0.5,
					(z - span * 0.5) * STEP), BEAM, false)
		for x in span:
			for z in span:
				_add(Vector3((x - span * 0.5 + 0.5) * STEP, top + BEAM.y + SLAB.y * 0.5,
					(z - span * 0.5 + 0.5) * STEP), SLAB, false)

	_relink(pieces)
	recalibrate()


## ПЕРЕСЧЁТ СПОСОБНОСТИ ПО ТОМУ, ЧТО СТОИТ СЕЙЧАС. Сначала мерим, потом назначаем — урок
## сорок первой: прогон с бесконечной способностью даёт фактическую нагрузку, она и
## становится основой запаса.
##
## Отдельно от постройки это нужно затем, что запас прочности — ручка, а ручка не имеет права
## стирать то, что игрок уже разнёс. Раньше её поворот перезапускал уровень.
func recalibrate() -> void:
	_dirty = true
	for p in _alive():
		_cap[p] = INF
	_flow()
	for p in _alive():
		_cap[p] = _load[p] * safety


func _add(at: Vector3, size: Vector3, anchored: bool) -> void:
	var body := SOLID.instantiate() as StuffSolid
	body.stuff = stuff
	body.scatter_seed = pieces.size() * 7 + 13
	var bs := BoxShape3D.new()
	bs.size = size
	(body.get_node("Shape") as CollisionShape3D).shape = bs
	var bm := BoxMesh.new()
	bm.size = size
	(body.get_node("Mesh") as MeshInstance3D).mesh = bm
	add_child(body)
	# ЧЕРЕЗ СВОЙ ТРАНСФОРМ, а не в мировых координатах: иначе два дома в одной сцене строятся
	# один в другом. Сетка считается в своих осях, положение задаёт узел.
	body.global_position = global_transform * at
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	_join(body, AABB(global_transform * at - size * 0.5, size), anchored)


## ПОДПИСКА ЖИВЁТ ЗДЕСЬ, А НЕ В ПОСТРОЙКЕ. Слушать надо КАЖДЫЙ узел графа, а не только те,
## что построены с нуля: ячейка тоже узел и тоже может расколоться. Пока подписывалась одна
## постройка, расколотая ячейка удаляла себя молча, и в списке оставалась мёртвая ссылка —
## сортировка нагрузки падала на ней в тот же тик.
func _join(body: StuffSolid, box: AABB, anchored: bool) -> void:
	if not body.shattered.is_connected(_on_shattered):
		body.shattered.connect(_on_shattered)
	pieces.append(body)
	_aabb[body] = box
	_anchor[body] = anchored
	_near[body] = [] as Array[StuffSolid]
	_below[body] = [] as Array[StuffSolid]


## СОСЕДСТВО ПО ПЕРЕСЕЧЕНИЮ СЛЕГКА РАЗДУТЫХ ОБЪЁМОВ. Дешевле списка связей руками и
## переживает любую перестройку здания.
func _relink(who: Array) -> void:
	var touched := {}
	for a in who:
		if not is_instance_valid(a):
			continue
		var grown: AABB = _aabb[a].grow(TOUCH)
		var list: Array[StuffSolid] = []
		for b in pieces:
			if a == b:
				continue
			if grown.intersects(_aabb[b]):
				list.append(b)
		_near[a] = list
		touched[a] = true
		for b in list:
			if not _near[b].has(a):
				_near[b].append(a)
			touched[b] = true
	for p in touched:
		var mine: float = _aabb[p].position.y
		var under: Array[StuffSolid] = []
		for n in _near[p]:
			if _aabb[n].end.y <= mine + UNDER:
				under.append(n)
		_below[p] = under


## Один шаг успокоения: опора, потом нагрузка. Пока за шаг кто-то падает — граф считается
## снова; как только шаг прошёл вхолостую, дом объявляется устоявшимся и не считается вовсе.
func settle() -> void:
	if not _dirty:
		return
	var before := fallen
	standing()
	stress()
	if fallen == before:
		_dirty = false


## ОПОРА ТЕЧЁТ СНИЗУ ВВЕРХ И ВБОК, но не вниз: иначе колонны повисают под плитами
## сталактитами. Урок сорок первой, и он держится и на ячейках.
func standing() -> int:
	var ok := {}
	var queue: Array[StuffSolid] = []
	for p in _alive():
		if _anchor.get(p, false):
			ok[p] = true
			queue.append(p)
	while not queue.is_empty():
		var p: StuffSolid = queue.pop_back()
		var top: float = _aabb[p].end.y
		for n in _near[p]:
			if ok.has(n) or not is_instance_valid(n) or not _aabb.has(n):
				continue
			if _aabb[n].position.y < top - UNDER:
				continue
			ok[n] = true
			queue.append(n)
	for p in _alive():
		if not ok.has(p):
			lost_support += 1
			_drop(p)
	return ok.size()


## НАГРУЗКА СВЕРХУ ВНИЗ. Вес каждого элемента стекает на тех, кто под ним; перегруженный
## отпускается. Только эта схема даёт цепную реакцию — измерено в сорок первой.
func stress() -> void:
	_flow()
	for p in _alive():
		if _load.get(p, 0.0) > _cap.get(p, INF):
			overloaded += 1
			_drop(p)


## Живые узлы, и заодно чистка: тело могло исчезнуть и мимо графа. Обход обязан переживать
## это молча, а не падать в сортировке.
func _alive() -> Array[StuffSolid]:
	var out: Array[StuffSolid] = []
	for p in pieces:
		if is_instance_valid(p):
			out.append(p)
	if out.size() != pieces.size():
		# По копии: `_forget` вычёркивает из `pieces`, а менять список под собственным
		# обходом — верный способ пропустить половину.
		for p in pieces.duplicate():
			if not is_instance_valid(p):
				_forget(p)
	return out


func _flow() -> void:
	var order := _alive()
	order.sort_custom(func(a: StuffSolid, b: StuffSolid) -> bool:
		return _aabb[a].position.y > _aabb[b].position.y)
	for _pass in 12:
		for p in order:
			_load[p] = p.mass
		for p in order:
			var under: Array = _below.get(p, [])
			if under.is_empty():
				continue
			var each: float = _load[p] / under.size()
			for n in under:
				if is_instance_valid(n):
					_load[n] = _load.get(n, 0.0) + each


func _drop(p: StuffSolid) -> void:
	if not is_instance_valid(p):
		return
	_dirty = true
	# ВОЗРАСТ ОБЛОМКА СЧИТАЕТСЯ С ЭТОГО МГНОВЕНИЯ, а не с постройки дома. Иначе уборка,
	# сортирующая по возрасту, первым делом сносит сам дом: его элементы — самое старое, что
	# есть в мире. Игрок видел это так: стреляешь в колонну, и половина небоскрёба ИСЧЕЗАЕТ,
	# а вторая падает сверху.
	p.born_at = Time.get_ticks_msec()
	p.freeze = false
	fallen += 1
	_forget(p)


## Держит ли граф это тело — за постоянное время. `pieces.has()` это линейный поиск, и в
## обходе по всем телам он превращается в квадрат: при 2554 телах шесть миллионов сравнений
## за тик, и весь кадр уходил туда.
func holds(p: StuffSolid) -> bool:
	return _near.has(p)


## Забыть тело снаружи: его вот-вот удалят, и держать на него ссылку нельзя.
func forget(p: StuffSolid) -> void:
	if _near.has(p):
		_dirty = true
	_forget(p)


func _forget(p: StuffSolid) -> void:
	pieces.erase(p)
	for n in _near.get(p, []):
		if _near.has(n):
			_near[n].erase(p)
		if _below.has(n):
			_below[n].erase(p)
	_near.erase(p)
	_below.erase(p)
	_aabb.erase(p)
	_anchor.erase(p)
	_cap.erase(p)
	_load.erase(p)


## ВОТ РАДИ ЧЕГО ВСЁ. Элемент раскололся: один узел графа стал полусотней, и связи надо
## унаследовать ПОСРЕДИ обрушения, а не пересобирать здание заново.
##
## ЯЧЕЙКА НЕ НАСЛЕДУЕТ ОПОРНОСТЬ — никогда, даже лёжа на земле. Сначала наследовала, и это
## давало ровно ту картину, которую видит игрок: расстрелял колонны, а крыша висит в воздухе.
## Расстрелянная колонна превращалась в щебень, часть щебня оказывалась на земле и получала
## признак опоры, и дом продолжал стоять на нескольких крошках.
##
## Разница между «снести» и «расстрелять» была видна сразу: снесённые девять колонн роняли дом
## целиком, расстрелянные — нет. Щебень не колонна: он лежит на земле, но здание не держит.
func _on_shattered(gone: StuffSolid, born: Array, _kept: float, _ms: float) -> void:
	if not _near.has(gone):
		return
	var t0 := Time.get_ticks_usec()
	var had: float = _cap.get(gone, 0.0)
	var whole: float = maxf(gone.volume, 1e-6)
	_forget(gone)

	var kids: Array[StuffSolid] = []
	for b in born:
		var s := b as StuffSolid
		if s == null:
			continue
		s.freeze = true
		s.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		var mi := s.get_node("Mesh") as MeshInstance3D
		var box: AABB = s.global_transform * mi.get_aabb()
		_join(s, box, false)
		kids.append(s)
	_relink(kids)
	# Замерять весь дом заново посреди обвала нельзя — это и есть цена дробления на лету.
	# Остаются два ответа, и мультипроба существует ради их сравнения.
	for s in kids:
		if inherit and is_finite(had):
			_cap[s] = had * (s.volume / whole)
		else:
			_cap[s] = maxf(s.mass, 1.0) * safety * 2.0
	_dirty = true
	rewires += 1
	rewire_ms = (Time.get_ticks_usec() - t0) / 1000.0
	rewired.emit(kids.size(), _links(), rewire_ms)


func _links() -> int:
	var n := 0
	for p in _near:
		n += _near[p].size()
	return n / 2
