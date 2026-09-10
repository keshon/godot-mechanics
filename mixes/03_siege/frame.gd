@tool
class_name SiegeFrame
extends Node3D
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

signal rewired(cells: int, links: int, spent_ms: float)

const SOLID := preload("res://probes/43_stuff/shard.tscn")

const COLUMN := Vector3(0.45, 2.4, 0.45)
const BEAM := Vector3(2.6, 0.35, 0.35)
const SLAB := Vector3(2.6, 0.28, 2.6)
const STEP := 2.6
## Насколько раздуваются объёмы при поиске соседей, метры.
const TOUCH := 0.06
## Насколько ниже меня должен кончаться сосед, чтобы считаться подпоркой, метры.
const UNDER := 0.25
## Сколько раз перебирать нагрузку, пока обвал не остановится.
const STRESS_PASSES := 12
## Во сколько раз способность одинокой ячейки превышает её собственный вес, когда наследование
## выключено. Двойка: щебень держит себя и соседа, но не здание.
const CELL_SAFETY := 2.0
## Габарит дома, чтобы видеть его В РЕДАКТОРЕ. Дом строится процедурно и до запуска не
## существует — а расставить два дома, не видя ни одного, нельзя. Показываем не сам дом, а
## место, которое он займёт: этого хватает, чтобы двигать и не пересекать.
const PREVIEW := "Габарит"

@export var stuff: StuffKind
@export var floors := 3:
	set(value):
		floors = value
		_preview()
@export var span := 2:
	set(value):
		span = value
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

## ВСЁ КЭШИРУЕТСЯ, И ЭТО НЕ ОПТИМИЗАЦИЯ, А УСЛОВИЕ РАБОТЫ. Габарит элемента, считанный через
## `get_node("Mesh").get_aabb()` прямо в цикле нагрузки, — это двенадцать проходов по полусотне
## элементов каждый физический тик, и кадр стоит 170 мс. Стоящий элемент заморожен и не
## двигается, значит габарит и список «кто подо мной» верны, пока граф не перестроят.
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


## Строится с первого тика, а не из `_ready`: урок сорок первой — тела, созданные до первого
## кадра, стоят в сотни раз дороже.
func build() -> void:
	# Габарит — подсказка редактора, в игре ему делать нечего.
	var hint := get_node_or_null(PREVIEW)
	if hint != null:
		hint.free()
	for child in get_children():
		child.queue_free()
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
	for level in floors:
		var y := level * lift
		for x in span + 1:
			for z in span + 1:
				_add(
						Vector3(
							(x - span * 0.5) * STEP,
							y + COLUMN.y * 0.5,
							(z - span * 0.5) * STEP),
						COLUMN, level == 0)
		var top := y + COLUMN.y
		for x in span:
			for z in span + 1:
				_add(
						Vector3(
							(x - span * 0.5 + 0.5) * STEP,
							top + BEAM.y * 0.5,
							(z - span * 0.5) * STEP),
						BEAM, false)
		for x in span:
			for z in span:
				_add(
						Vector3(
							(x - span * 0.5 + 0.5) * STEP,
							top + BEAM.y + SLAB.y * 0.5,
							(z - span * 0.5 + 0.5) * STEP),
						SLAB, false)

	_relink(pieces)
	recalibrate()


## ПЕРЕСЧЁТ СПОСОБНОСТИ ПО ТОМУ, ЧТО СТОИТ СЕЙЧАС. Сначала мерим, потом назначаем — урок
## сорок первой: прогон с бесконечной способностью даёт фактическую нагрузку, она и
## становится основой запаса.
##
## Отдельно от постройки это нужно затем, что запас прочности — ручка, а ручка не имеет права
## стирать то, что игрок уже разнёс. Её поворот не перезапускает уровень.
func recalibrate() -> void:
	_dirty = true
	for piece in _alive():
		_cap[piece] = INF
	_flow()
	for piece in _alive():
		_cap[piece] = _load[piece] * safety


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
	var reached := {}
	var queue: Array[StuffSolid] = []
	for piece in _alive():
		if _anchor.get(piece, false):
			reached[piece] = true
			queue.append(piece)
	while not queue.is_empty():
		var piece: StuffSolid = queue.pop_back()
		var top: float = _aabb[piece].end.y
		for neighbour in _near[piece]:
			if reached.has(neighbour) or not is_instance_valid(neighbour):
				continue
			if not _aabb.has(neighbour):
				continue
			if _aabb[neighbour].position.y < top - UNDER:
				continue
			reached[neighbour] = true
			queue.append(neighbour)
	for piece in _alive():
		if not reached.has(piece):
			lost_support += 1
			_drop(piece)
	return reached.size()


## НАГРУЗКА СВЕРХУ ВНИЗ. Вес каждого элемента стекает на тех, кто под ним; перегруженный
## отпускается. Только эта схема даёт цепную реакцию — измерено в сорок первой.
func stress() -> void:
	_flow()
	for piece in _alive():
		if _load.get(piece, 0.0) > _cap.get(piece, INF):
			overloaded += 1
			_drop(piece)


## Держит ли граф это тело — за постоянное время. `pieces.has()` это линейный поиск, и в
## обходе по всем телам он превращается в квадрат: при 2554 телах шесть миллионов сравнений
## за тик, и весь кадр уходит туда.
func holds(piece: StuffSolid) -> bool:
	return _near.has(piece)


## Забыть тело снаружи: его вот-вот удалят, и держать на него ссылку нельзя.
func forget(piece: StuffSolid) -> void:
	if _near.has(piece):
		_dirty = true
	_forget(piece)


func _preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var box_node := get_node_or_null(PREVIEW) as MeshInstance3D
	if box_node == null:
		box_node = MeshInstance3D.new()
		box_node.name = PREVIEW
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.4, 0.75, 1.0, 0.22)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		box_node.material_override = material
		add_child(box_node)
		# Без владельца — значит в сохранённую сцену не попадёт.
		box_node.owner = null
		box_node.set_meta("_edit_lock_", true)
	var wide: float = span * STEP + COLUMN.x
	var high: float = floors * (COLUMN.y + BEAM.y + SLAB.y)
	var box := BoxMesh.new()
	box.size = Vector3(wide, high, wide)
	box_node.mesh = box
	box_node.position = Vector3(0.0, high * 0.5, 0.0)


func _add(at: Vector3, size: Vector3, anchored: bool) -> void:
	var body := SOLID.instantiate() as StuffSolid
	body.stuff = stuff
	body.scatter_seed = pieces.size() * 7 + 13
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := body.get_node("Shape") as CollisionShape3D
	collider.shape = shape
	var box := BoxMesh.new()
	box.size = size
	var visual := body.get_node("Mesh") as MeshInstance3D
	visual.mesh = box
	add_child(body)
	# ЧЕРЕЗ СВОЙ ТРАНСФОРМ, а не в мировых координатах: иначе два дома в одной сцене строятся
	# один в другом. Сетка считается в своих осях, положение задаёт узел.
	body.global_position = global_transform * at
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	_join(body, AABB(global_transform * at - size * 0.5, size), anchored)


## ПОДПИСКА ЖИВЁТ ЗДЕСЬ, А НЕ В ПОСТРОЙКЕ. Слушать надо КАЖДЫЙ узел графа, а не только те,
## что построены с нуля: ячейка тоже узел и тоже может расколоться. Пока подписывается одна
## постройка, расколотая ячейка удаляет себя молча, в списке остаётся мёртвая ссылка, и
## сортировка нагрузки падает на ней в тот же тик.
func _join(body: StuffSolid, box: AABB, anchored: bool) -> void:
	if not body.shattered.is_connected(_on_solid_shattered):
		body.shattered.connect(_on_solid_shattered)
	pieces.append(body)
	_aabb[body] = box
	_anchor[body] = anchored
	_near[body] = [] as Array[StuffSolid]
	_below[body] = [] as Array[StuffSolid]


## СОСЕДСТВО ПО ПЕРЕСЕЧЕНИЮ СЛЕГКА РАЗДУТЫХ ОБЪЁМОВ. Дешевле списка связей руками и
## переживает любую перестройку здания.
func _relink(who: Array) -> void:
	var touched := {}
	for piece in who:
		if not is_instance_valid(piece):
			continue
		var grown: AABB = _aabb[piece].grow(TOUCH)
		var list: Array[StuffSolid] = []
		for other in pieces:
			if piece == other:
				continue
			if grown.intersects(_aabb[other]):
				list.append(other)
		_near[piece] = list
		touched[piece] = true
		for other in list:
			if not _near[other].has(piece):
				_near[other].append(piece)
			touched[other] = true
	for piece in touched:
		var mine: float = _aabb[piece].position.y
		var under: Array[StuffSolid] = []
		for neighbour in _near[piece]:
			if _aabb[neighbour].end.y <= mine + UNDER:
				under.append(neighbour)
		_below[piece] = under


## Живые узлы, и заодно чистка: тело могло исчезнуть и мимо графа. Обход обязан переживать
## это молча, а не падать в сортировке.
func _alive() -> Array[StuffSolid]:
	var out: Array[StuffSolid] = []
	for piece in pieces:
		if is_instance_valid(piece):
			out.append(piece)
	if out.size() != pieces.size():
		# По копии: `_forget` вычёркивает из `pieces`, а менять список под собственным
		# обходом — верный способ пропустить половину.
		for piece in pieces.duplicate():
			if not is_instance_valid(piece):
				_forget(piece)
	return out


func _flow() -> void:
	var order := _alive()
	order.sort_custom(
			func(first: StuffSolid, second: StuffSolid) -> bool:
				return _aabb[first].position.y > _aabb[second].position.y)
	for _pass in STRESS_PASSES:
		for piece in order:
			_load[piece] = piece.mass
		for piece in order:
			var under: Array = _below.get(piece, [])
			if under.is_empty():
				continue
			var share: float = _load[piece] / under.size()
			for neighbour in under:
				if is_instance_valid(neighbour):
					_load[neighbour] = _load.get(neighbour, 0.0) + share


func _drop(piece: StuffSolid) -> void:
	if not is_instance_valid(piece):
		return
	_dirty = true
	# ВОЗРАСТ ОБЛОМКА СЧИТАЕТСЯ С ЭТОГО МГНОВЕНИЯ, а не с постройки дома. Иначе уборка,
	# сортирующая по возрасту, первым делом сносит сам дом: его элементы — самое старое, что
	# есть в мире. Игрок видит это так: стреляешь в колонну, и половина небоскрёба ИСЧЕЗАЕТ,
	# а вторая падает сверху.
	piece.born_at = Time.get_ticks_msec()
	piece.freeze = false
	fallen += 1
	_forget(piece)


func _forget(piece: StuffSolid) -> void:
	pieces.erase(piece)
	for neighbour in _near.get(piece, []):
		if _near.has(neighbour):
			_near[neighbour].erase(piece)
		if _below.has(neighbour):
			_below[neighbour].erase(piece)
	_near.erase(piece)
	_below.erase(piece)
	_aabb.erase(piece)
	_anchor.erase(piece)
	_cap.erase(piece)
	_load.erase(piece)


func _links() -> int:
	var count := 0
	for piece in _near:
		count += _near[piece].size()
	return count / 2


## ВОТ РАДИ ЧЕГО ВСЁ. Элемент раскололся: один узел графа стал полусотней, и связи надо
## унаследовать ПОСРЕДИ обрушения, а не пересобирать здание заново.
##
## ЯЧЕЙКА НЕ НАСЛЕДУЕТ ОПОРНОСТЬ — никогда, даже лёжа на земле. Унаследованная, она даёт ровно
## ту картину, которую видит игрок: расстрелял колонны, а крыша висит в воздухе. Расстрелянная
## колонна превращается в щебень, часть щебня оказывается на земле и получает признак опоры, и
## дом продолжает стоять на нескольких крошках.
##
## Разница между «снести» и «расстрелять» видна сразу: снесённые девять колонн роняют дом
## целиком, расстрелянные — нет. Щебень не колонна: он лежит на земле, но здание не держит.
func _on_solid_shattered(
		gone: StuffSolid,
		born: Array,
		_kept: float,
		_spent_ms: float) -> void:
	if not _near.has(gone):
		return
	var started := Time.get_ticks_usec()
	var had: float = _cap.get(gone, 0.0)
	var whole: float = maxf(gone.volume, 1e-6)
	_forget(gone)

	var kids: Array[StuffSolid] = []
	for node in born:
		var cell := node as StuffSolid
		if cell == null:
			continue
		cell.freeze = true
		cell.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		var visual := cell.get_node("Mesh") as MeshInstance3D
		var box: AABB = cell.global_transform * visual.get_aabb()
		_join(cell, box, false)
		kids.append(cell)
	_relink(kids)
	# Замерять весь дом заново посреди обвала нельзя — это и есть цена дробления на лету.
	# Остаются два ответа, и мультипроба существует ради их сравнения.
	for cell in kids:
		if inherit and is_finite(had):
			_cap[cell] = had * (cell.volume / whole)
		else:
			_cap[cell] = maxf(cell.mass, 1.0) * safety * CELL_SAFETY
	_dirty = true
	rewires += 1
	rewire_ms = (Time.get_ticks_usec() - started) / 1000.0
	rewired.emit(kids.size(), _links(), rewire_ms)
