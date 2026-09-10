class_name RuinFrame
extends Node3D
## ЗДАНИЕ И ТРИ СПОСОБА ЗАСТАВИТЬ ЕГО РУШИТЬСЯ.
##
## СУСТАВЫ. Каждый элемент — твёрдое тело, соседи связаны суставом, сустав рвётся, когда
## соседей растащило дальше порога. Честно: конструкция реагирует на любую нагрузку, гнётся
## и оседает. Дорого: сотня тел и триста суставов считаются каждый тик, и главный вопрос
## даже не в цене, а в том, СТОИТ ЛИ ЗДАНИЕ, пока его никто не трогает.
##
## ГРАФ ОПОРЫ. Элементы заморожены и неподвижны, у каждого список соседей. Разрушили один —
## обходим граф от земли и смотрим, до кого путь оборвался; до кого оборвался, тот
## отпускается и падает. Так сделано в Red Faction Guerrilla, и это не упрощение ради
## скорости, а другая модель: **обрушение здесь — не про силы, а про связность.**
##
## ГРАФ С НАГРУЗКОЙ. То же связное дерево, но по нему течёт ВЕС. Элемент, на который
## навалилось больше, чем он держит, выбывает, и его ноша переезжает на соседей — цепью.
##
## Три вопроса, и они разные:
##
##   суставы          — «растянулось ли?»
##   граф опоры       — «есть ли ещё путь до земли?»
##   граф с нагрузкой — «сколько килограммов на мне лежит?»
##
## Первые два измерены и оба НЕ РОНЯЮТ дом, у которого выбили половину опор. Третий и есть
## ответ на то, чего им не хватало.

const COLUMN := Vector3(0.4, 2.6, 0.4)
const BEAM := Vector3(3.0, 0.35, 0.4)
const SLAB := Vector3(3.0, 0.25, 3.0)
const STEP := 3.0
## Сколько раз перебирать нагрузку, пока обвал не остановится.
const STRESS_PASSES := 12

## Здание строится кодом, но вокруг узла-метки: элементов много и они одинаковые, а вот
## ГДЕ стоит здание — свойство сцены.
@export var floors := 3
@export var span := 3
## Порог разрыва сустава в метрах: насколько соседей растащило, прежде чем связь лопнет.
@export_range(0.02, 0.6, 0.01) var snap := 0.12
## ЗАПАС ПРОЧНОСТИ: во сколько раз элемент держит больше, чем несёт в целом здании.
##
## Несущую способность НЕЛЬЗЯ выдумывать. Выдуманные числа — колонне 3000, балке 900, плите
## 300 — промахиваются в разы: замер показал, что балка в целом здании несёт 3069 кг, а
## плита 1763. То есть здание стоит перегруженным втрое и вшестеро с первого тика, и любое
## касание валит его целиком. Выглядит это как «схема слишком хрупкая».
##
## Поэтому способность считается ОТ ФАКТА: строим, считаем нагрузку, умножаем на запас.
## Двойка означает ровно то, что означает у инженера: элемент держит вдвое больше своего.
## Полтора — намеренно на грани: при ×2.0 здание переживает снос половины опор, при ×1.2
## складывается целиком. Вся разница между «крепость» и «карточный домик» — в этом числе.
@export_range(1.0, 6.0, 0.1) var safety := 1.5

var pieces: Array[RuinPiece] = []
var joints: Array[Dictionary] = []
var use_joints := false
var use_stress := false
var fallen := 0


## Схема: 0 — граф опоры, 1 — суставы, 2 — граф с нагрузкой.
func build(scheme: int) -> void:
	use_joints = scheme == 1
	use_stress = scheme == 2
	for child in get_children():
		child.queue_free()
	pieces.clear()
	joints.clear()
	fallen = 0

	var column_material := _make_material(Color(0.52, 0.5, 0.47))
	var beam_material := _make_material(Color(0.46, 0.44, 0.42))
	var slab_material := _make_material(Color(0.58, 0.57, 0.55))
	for level in floors:
		var y := level * STEP
		for x in span + 1:
			for z in span + 1:
				var at := Vector3(
						(x - span * 0.5) * STEP,
						y + COLUMN.y * 0.5,
						(z - span * 0.5) * STEP)
				_add_piece(at, COLUMN, column_material, 260.0, level == 0)
		var top := y + COLUMN.y
		for x in span:
			for z in span + 1:
				_add_piece(
						Vector3(
							(x - span * 0.5 + 0.5) * STEP,
							top + BEAM.y * 0.5,
							(z - span * 0.5) * STEP),
						BEAM, beam_material, 160.0, false)
		for x in span:
			for z in span:
				_add_piece(
						Vector3(
							(x - span * 0.5 + 0.5) * STEP,
							top + BEAM.y + SLAB.y * 0.5,
							(z - span * 0.5 + 0.5) * STEP),
						SLAB, slab_material, 420.0, false)

	_link()
	# СНАЧАЛА МЕРИМ, ПОТОМ НАЗНАЧАЕМ. Прогон с бесконечной способностью даёт фактическую
	# нагрузку на каждый элемент в целом здании; она и становится основой для запаса.
	for piece in pieces:
		piece.capacity = INF
	var was := use_stress
	use_stress = true
	stress()
	use_stress = was
	for piece in pieces:
		piece.capacity = piece.load_kg * safety
	if use_joints:
		_pin_joints()
		for piece in pieces:
			piece.freeze = piece.anchored
	drop_unsupported()


## РАЗРЫВ СУСТАВОВ. Godot не сообщает силу в суставе, поэтому судим по последствию: если
## соседей растащило дальше порога, связь считается лопнувшей. Грубо, зато работает на
## любом типе сустава и не требует лезть в физический сервер.
func snap_joints() -> void:
	if not use_joints:
		return
	for index in range(joints.size() - 1, -1, -1):
		var link: Dictionary = joints[index]
		var first: RuinPiece = link["a"]
		var second: RuinPiece = link["b"]
		if not is_instance_valid(first) or not is_instance_valid(second):
			joints.remove_at(index)
			continue
		var apart := first.global_position.distance_to(second.global_position)
		if absf(apart - link["rest"]) > snap:
			(link["joint"] as Node).queue_free()
			joints.remove_at(index)


## ОБХОД ГРАФА ОТ ЗЕМЛИ, и всё, до чего путь не дошёл, отпускается и падает. Это и есть
## обрушение: не сумма сил, а потеря связности. Возвращает то, что повисло, — в схеме
## суставов ронять должна физика, поэтому там список только возвращается.
func drop_unsupported() -> Array[RuinPiece]:
	var reached := {}
	var queue: Array[RuinPiece] = []
	for piece in pieces:
		if piece.standing and piece.anchored:
			reached[piece] = true
			queue.append(piece)
	while not queue.is_empty():
		var piece: RuinPiece = queue.pop_back()
		for neighbour in piece.neighbours:
			if not is_instance_valid(neighbour) or not neighbour.standing:
				continue
			if reached.has(neighbour):
				continue
			# ОПОРА ТЕЧЁТ ТОЛЬКО СНИЗУ ВВЕРХ. Обход по ненаправленным связям объявляет
			# опёртой колонну, висящую ПОД плитой: путь до земли у неё формально есть —
			# через плиту и соседние колонны, — но держится она за то, что над ней. В
			# кадре это выглядит сталактитом и сразу читается как ошибка.
			#
			# Связность не знает, где верх; направление приходится задавать руками. Вбок
			# опора идти может — соседние балки раскрепляют друг друга, — а вниз нет.
			if neighbour.global_position.y < piece.global_position.y - 0.05:
				continue
			reached[neighbour] = true
			queue.append(neighbour)

	var loose: Array[RuinPiece] = []
	for piece in pieces:
		if piece.standing and not reached.has(piece):
			loose.append(piece)
	if not use_joints:
		for piece in loose:
			piece.release()
			fallen += 1
	return loose


## ГРАФ С НАГРУЗКОЙ — третья схема и, кажется, единственная честная.
##
## Связность отвечает «есть ли путь до земли» и потому держит здание на одной колонне.
## Суставы отвечают «растянулось ли» и потому не замечают перегруза в жёсткой раме. Ни то
## ни другое не роняет дом, у которого выбили половину опор, — а он обязан упасть.
##
## Здесь считается ТРЕТИЙ вопрос: **сколько килограммов приходится на каждый элемент.**
## Вес течёт сверху вниз по соседям, элемент с перегрузом выбывает, его ноша переезжает на
## оставшихся — и это цепная реакция, то самое обрушение.
func stress() -> void:
	if not use_stress:
		return
	# Повторяем, пока обвал не остановится: каждое выбывание меняет расклад для соседей.
	for _pass in STRESS_PASSES:
		var live: Array[RuinPiece] = []
		for piece in pieces:
			if is_instance_valid(piece) and piece.standing:
				piece.load_kg = piece.mass
				live.append(piece)
		# Сверху вниз: каждый отдаёт свою ношу тем соседям, что ниже его.
		live.sort_custom(
				func(first: RuinPiece, second: RuinPiece) -> bool:
					return first.global_position.y > second.global_position.y)
		for piece in live:
			var below: Array[RuinPiece] = []
			for neighbour in piece.neighbours:
				if not is_instance_valid(neighbour) or not neighbour.standing:
					continue
				if neighbour.global_position.y < piece.global_position.y - 0.05:
					below.append(neighbour)
			if below.is_empty():
				continue
			var share := piece.load_kg / float(below.size())
			for neighbour in below:
				neighbour.load_kg += share
		var broke := false
		for piece in live:
			# ОПОРНЫЕ КОЛОННЫ ТОЖЕ ЛОМАЮТСЯ. Освобождённые от этого — «они же держат
			# землю» — дают здание, которое не падает ни при каком запасе прочности:
			# нагрузка стекает ровно в них, а им нельзя сломаться. `anchored` значит
			# «связан с землёй» для обхода графа, а не «неуязвим».
			if piece.load_kg > piece.capacity:
				piece.release()
				fallen += 1
				broke = true
		if not broke:
			return


func mark_supported(showing: bool) -> void:
	var reached := {}
	for piece in drop_unsupported():
		reached[piece] = true
	for piece in pieces:
		if piece.standing:
			piece.mark(not reached.has(piece), showing)


func standing_count() -> int:
	var count := 0
	for piece in pieces:
		if is_instance_valid(piece) and piece.standing:
			count += 1
	return count


func _make_material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.95
	return material


func _add_piece(
		at: Vector3,
		size: Vector3,
		material: StandardMaterial3D,
		piece_mass: float,
		anchored: bool) -> void:
	var piece := RuinPiece.new()
	piece.mass = piece_mass
	piece.anchored = anchored
	piece.health = 30.0 if size == COLUMN else 45.0
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	piece.add_child(collider)
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	visual.mesh = box
	visual.name = "Mesh"
	# Свой экземпляр материала на элемент: цвет меняется по износу и по подсветке графа.
	visual.material_override = material.duplicate()
	piece.add_child(visual)
	add_child(piece)
	piece.global_position = at
	pieces.append(piece)


## СОСЕДСТВО ПО ПЕРЕСЕЧЕНИЮ ОБЪЁМОВ, слегка раздутых. Дешевле и надёжнее, чем список
## связей руками: здание можно перестроить другим, и связи посчитаются заново.
func _link() -> void:
	var boxes: Array[AABB] = []
	for piece in pieces:
		var collider := piece.get_child(0) as CollisionShape3D
		var shape := collider.shape as BoxShape3D
		boxes.append(AABB(
				piece.global_position - shape.size * 0.5 - Vector3.ONE * 0.06,
				shape.size + Vector3.ONE * 0.12))
	for i in pieces.size():
		for j in range(i + 1, pieces.size()):
			if boxes[i].intersects(boxes[j]):
				pieces[i].neighbours.append(pieces[j])
				pieces[j].neighbours.append(pieces[i])


func _pin_joints() -> void:
	for i in pieces.size():
		for neighbour in pieces[i].neighbours:
			if pieces[i].get_instance_id() > neighbour.get_instance_id():
				continue
			# ПОРЯДОК РЕШАЕТ ВСЁ. Каждая правка параметра пересобирает сустав в физическом
			# сервере — но только если тела уже назначены. Назначить `node_a`/`node_b`, а
			# потом крутить три десятка свойств, значит получить по пересборке на каждое:
			# двадцать один сустав строится ШЕСТЬ СЕКУНД, по 290 мс на штуку. Сотня
			# суставов не строится вовсе.
			#
			# Настроить, потом соединить — и те же двадцать один сустав строятся мгновенно.
			var joint := Generic6DOFJoint3D.new()
			add_child(joint)
			joint.global_position = (
					pieces[i].global_position + neighbour.global_position) * 0.5
			# Все шесть осей запираются руками: по умолчанию сустав не ограничивает НИЧЕГО.
			for flag in [
				Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT,
				Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,
			]:
				joint.set_flag_x(flag, true)
				joint.set_flag_y(flag, true)
				joint.set_flag_z(flag, true)
			for param in [
				Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,
				Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,
				Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,
				Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,
			]:
				joint.set_param_x(param, 0.0)
				joint.set_param_y(param, 0.0)
				joint.set_param_z(param, 0.0)
			joint.node_a = pieces[i].get_path()
			joint.node_b = neighbour.get_path()
			joints.append({
				"joint": joint,
				"a": pieces[i],
				"b": neighbour,
				"rest": pieces[i].global_position.distance_to(neighbour.global_position),
			})
