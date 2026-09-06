extends Node3D
class_name RuinFrame
## ЗДАНИЕ И ТРИ СПОСОБА ЗАСТАВИТЬ ЕГО РУШИТЬСЯ.
##
## Проба сравнивает то, что обычно выбирают вслепую.
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

## Здание строится кодом, но вокруг узла-метки: элементов много и они одинаковые, а вот
## ГДЕ стоит здание — свойство сцены.
@export var floors := 3
@export var span := 3
## Порог разрыва сустава в метрах: насколько соседей растащило, прежде чем связь лопнет.
@export_range(0.02, 0.6, 0.01) var snap := 0.12
## ЗАПАС ПРОЧНОСТИ: во сколько раз элемент держит больше, чем несёт в целом здании.
##
## Несущую способность НЕЛЬЗЯ выдумывать. Я выдумал — колонне 3000, балке 900, плите 300 —
## и промахнулся в разы: замер показал, что балка в целом здании несёт 3069 кг, а плита
## 1763. То есть здание стояло перегруженным втрое и вшестеро с первого тика, и любое
## касание валило его целиком. Выглядело это как «схема слишком хрупкая».
##
## Поэтому способность считается ОТ ФАКТА: строим, считаем нагрузку, умножаем на запас.
## Двойка означает ровно то, что означает у инженера: элемент держит вдвое больше своего.
## Полтора — намеренно на грани: при ×2.0 здание переживает снос половины опор, при ×1.2
## складывается целиком. Вся разница между «крепость» и «карточный домик» — в этом числе.
@export_range(1.0, 6.0, 0.1) var safety := 1.5

const COLUMN := Vector3(0.4, 2.6, 0.4)
const BEAM := Vector3(3.0, 0.35, 0.4)
const SLAB := Vector3(3.0, 0.25, 3.0)
const STEP := 3.0

var pieces: Array[RuinPiece] = []
var joints: Array[Dictionary] = []
var use_joints := false
var use_stress := false
var fallen := 0

var _rng := RandomNumberGenerator.new()


## Схема: 0 — граф опоры, 1 — суставы, 2 — граф с нагрузкой.
func build(scheme: int) -> void:
	use_joints = scheme == 1
	use_stress = scheme == 2
	for c in get_children():
		c.queue_free()
	pieces.clear()
	joints.clear()
	fallen = 0
	_rng.seed = 41

	var mats := {
		"column": _mat(Color(0.52, 0.5, 0.47)),
		"beam": _mat(Color(0.46, 0.44, 0.42)),
		"slab": _mat(Color(0.58, 0.57, 0.55)),
	}
	for f in floors:
		var y := f * STEP
		for x in span + 1:
			for z in span + 1:
				var at := Vector3((x - span * 0.5) * STEP, y + COLUMN.y * 0.5,
					(z - span * 0.5) * STEP)
				_piece(at, COLUMN, mats["column"], 260.0, f == 0)
		var top := y + COLUMN.y
		for x in span:
			for z in span + 1:
				_piece(Vector3((x - span * 0.5 + 0.5) * STEP, top + BEAM.y * 0.5,
					(z - span * 0.5) * STEP), BEAM, mats["beam"], 160.0, false)
		for x in span:
			for z in span:
				_piece(Vector3((x - span * 0.5 + 0.5) * STEP,
					top + BEAM.y + SLAB.y * 0.5,
					(z - span * 0.5 + 0.5) * STEP), SLAB, mats["slab"], 420.0, false)

	_link()
	# СНАЧАЛА МЕРИМ, ПОТОМ НАЗНАЧАЕМ. Прогон с бесконечной способностью даёт фактическую
	# нагрузку на каждый элемент в целом здании; она и становится основой для запаса.
	for p in pieces:
		p.capacity = INF
	var was := use_stress
	use_stress = true
	stress()
	use_stress = was
	for p in pieces:
		p.capacity = p.load_kg * safety
	if use_joints:
		_pin()
		for p in pieces:
			p.freeze = p.anchored
	support()


func _mat(tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = 0.95
	return m


func _piece(at: Vector3, size: Vector3, mat: StandardMaterial3D, mass: float,
		anchored: bool) -> void:
	var p := RuinPiece.new()
	p.set_script(load("res://probes/41_ruin/Piece.gd"))
	p.mass = mass
	p.anchored = anchored
	p.health = 30.0 if size == COLUMN else 45.0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	p.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.name = "Mesh"
	# Свой экземпляр материала на элемент: цвет меняется по износу и по подсветке графа.
	mi.material_override = mat.duplicate()
	p.add_child(mi)
	add_child(p)
	p.global_position = at
	pieces.append(p)


## СОСЕДСТВО ПО ПЕРЕСЕЧЕНИЮ ОБЪЁМОВ, слегка раздутых. Дешевле и надёжнее, чем список связей
## руками: здание можно перестроить другим, и связи посчитаются заново.
func _link() -> void:
	var boxes: Array[AABB] = []
	for p in pieces:
		var s: Vector3 = ((p.get_child(0) as CollisionShape3D).shape as BoxShape3D).size
		boxes.append(AABB(p.global_position - s * 0.5 - Vector3.ONE * 0.06,
			s + Vector3.ONE * 0.12))
	for i in pieces.size():
		for j in range(i + 1, pieces.size()):
			if boxes[i].intersects(boxes[j]):
				pieces[i].neighbours.append(pieces[j])
				pieces[j].neighbours.append(pieces[i])


func _pin() -> void:
	for i in pieces.size():
		for n in pieces[i].neighbours:
			if pieces[i].get_instance_id() > n.get_instance_id():
				continue
			# ПОРЯДОК РЕШАЕТ ВСЁ. Каждая правка параметра пересобирает сустав в физическом
			# сервере — но только если тела уже назначены. Сначала я назначал `node_a`/`node_b`,
			# потом крутил три десятка свойств, и получал по пересборке на каждое: двадцать один
			# сустав строился ШЕСТЬ СЕКУНД, по 290 мс на штуку. Сотня суставов не строилась
			# вовсе.
			#
			# Настроить, потом соединить — и те же двадцать один сустав строятся мгновенно.
			var j := Generic6DOFJoint3D.new()
			add_child(j)
			j.global_position = (pieces[i].global_position + n.global_position) * 0.5
			# Все шесть осей запираются руками: по умолчанию сустав не ограничивает НИЧЕГО.
			for f in [Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT,
					Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT]:
				j.set_flag_x(f, true)
				j.set_flag_y(f, true)
				j.set_flag_z(f, true)
			for p in [Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,
					Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,
					Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,
					Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT]:
				j.set_param_x(p, 0.0)
				j.set_param_y(p, 0.0)
				j.set_param_z(p, 0.0)
			j.node_a = pieces[i].get_path()
			j.node_b = n.get_path()
			joints.append({"j": j, "a": pieces[i], "b": n,
				"rest": pieces[i].global_position.distance_to(n.global_position)})


## РАЗРЫВ СУСТАВОВ. Godot не сообщает силу в суставе, поэтому судим по последствию: если
## соседей растащило дальше порога, связь считается лопнувшей. Грубо, зато работает на любом
## типе сустава и не требует лезть в физический сервер.
func snap_joints() -> void:
	if not use_joints:
		return
	for k in range(joints.size() - 1, -1, -1):
		var d: Dictionary = joints[k]
		var a: RuinPiece = d["a"]
		var b: RuinPiece = d["b"]
		if not is_instance_valid(a) or not is_instance_valid(b):
			joints.remove_at(k)
			continue
		if absf(a.global_position.distance_to(b.global_position) - d["rest"]) > snap:
			(d["j"] as Node).queue_free()
			joints.remove_at(k)


## ОБХОД ГРАФА ОТ ЗЕМЛИ. Всё, до чего путь не дошёл, отпускается и падает. Это и есть
## обрушение: не сумма сил, а потеря связности.
func support() -> Array[RuinPiece]:
	var reached := {}
	var queue: Array[RuinPiece] = []
	for p in pieces:
		if p.standing and p.anchored:
			reached[p] = true
			queue.append(p)
	while not queue.is_empty():
		var p: RuinPiece = queue.pop_back()
		for n in p.neighbours:
			if not is_instance_valid(n) or not n.standing or reached.has(n):
				continue
			# ОПОРА ТЕЧЁТ ТОЛЬКО СНИЗУ ВВЕРХ. Обход по ненаправленным связям объявлял
			# опёртой колонну, висящую ПОД плитой: путь до земли у неё формально есть —
			# через плиту и соседние колонны, — но держится она за то, что над ней.
			# В кадре это выглядело сталактитом и сразу читалось как ошибка.
			#
			# Связность не знает, где верх; направление приходится задавать руками. Вбок
			# опора идти может — соседние балки раскрепляют друг друга, — а вниз нет.
			if n.global_position.y < p.global_position.y - 0.05:
				continue
			reached[n] = true
			queue.append(n)

	var loose: Array[RuinPiece] = []
	for p in pieces:
		if p.standing and not reached.has(p):
			loose.append(p)
	if not use_joints:
		for p in loose:
			p.release()
			fallen += 1
	return loose


## ГРАФ С НАГРУЗКОЙ — третья схема и, кажется, единственная честная.
##
## Связность отвечает «есть ли путь до земли» и потому держит здание на одной колонне.
## Суставы отвечают «растянулось ли» и потому не замечают перегруза в жёсткой раме. Ни то ни
## другое не роняет дом, у которого выбили половину опор, — а он обязан упасть.
##
## Здесь считается ТРЕТИЙ вопрос: **сколько килограммов приходится на каждый элемент.** Вес
## течёт сверху вниз по соседям, элемент с перегрузом выбывает, его ноша переезжает на
## оставшихся — и это цепная реакция, то самое обрушение.
func stress() -> void:
	if not use_stress:
		return
	# Повторяем, пока обвал не остановится: каждое выбывание меняет расклад для соседей.
	for _pass in 12:
		var live: Array[RuinPiece] = []
		for p in pieces:
			if is_instance_valid(p) and p.standing:
				p.load_kg = p.mass
				live.append(p)
		# Сверху вниз: каждый отдаёт свою ношу тем соседям, что ниже его.
		live.sort_custom(func(a, b): return a.global_position.y > b.global_position.y)
		for p in live:
			var below: Array[RuinPiece] = []
			for n in p.neighbours:
				if is_instance_valid(n) and n.standing 						and n.global_position.y < p.global_position.y - 0.05:
					below.append(n)
			if below.is_empty():
				continue
			var share: float = p.load_kg / float(below.size())
			for n in below:
				n.load_kg += share
		var broke := false
		for p in live:
			# ОПОРНЫЕ КОЛОННЫ ТОЖЕ ЛОМАЮТСЯ. Сначала я их освободил — «они же держат землю», —
			# и получил здание, которое не падало ни при каком запасе прочности: нагрузка
			# стекает ровно в них, а им нельзя сломаться. `anchored` значит «связан с землёй»
			# для обхода графа, а не «неуязвим».
			if p.load_kg > p.capacity:
				p.release()
				fallen += 1
				broke = true
		if not broke:
			return


func mark_all(show: bool) -> void:
	var reached := {}
	for p in support():
		reached[p] = true
	for p in pieces:
		if p.standing:
			p.mark(not reached.has(p), show)


func standing_count() -> int:
	var n := 0
	for p in pieces:
		if is_instance_valid(p) and p.standing:
			n += 1
	return n
