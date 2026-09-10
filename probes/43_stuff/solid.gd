class_name StuffSolid
extends RigidBody3D
## ПРЕДМЕТ ИЗ ЧЕГО-ТО.
##
## Тело не знает ни про стрелка, ни про камеру: ему сообщают энергию удара вызовом `hit()`.
## Всё остальное решает материал.
##
## Осколок — ТАКОЙ ЖЕ предмет, тот же класс и тот же скрипт. Отсюда повторный скол: разница
## между целым и обломком только в том, что у обломка форма не коробка. Пока рез умел резать
## одни коробки, второй класс был неизбежен; теперь он не нужен.

const SHARD := preload("res://probes/43_stuff/shard.tscn")
## На сколько частей предмет разваливается даже при полностью занятом бюджете.
const LEAST := 2
## Объём шара единичного радиуса, 4π/3.
const SPHERE := 4.18879
## Ниже этой потери энергии за тик, в джоулях, удар о мир считается дрожанием на месте.
const MIN_IMPACT := 1.0

## Сообщает не только СКОЛЬКО кусков, но и КАКИЕ. Без списка тот, кто снаружи держит связи
## между предметами, не может унаследовать их осколкам: он знает, что предмет исчез, и не
## знает, чем он стал. Найдено сборкой — в одиночку пробе список был не нужен.
signal shattered(what: StuffSolid, born: Array[RigidBody3D], kept: float, spent_ms: float)

## СЧИТАЕМЫХ предметов в сцене — не всех, а тех, что ещё нагружают решатель. Обломок,
## отправленный на покой снаружи (`retire`), из счёта выходит: он заморожен и стоит ноль,
## значит не должен мешать дому крошиться дальше. Уснувший и замороженный выходят по той же
## причине — решателю они не стоят ничего.
##
## Бюджет обязан ограничивать НАГРУЗКУ, а не количество вещей на свете: пока здесь считались
## все тела, настрелянные три сотни обломков лишали обвал дома права на крошку.
static var alive := 0

## Один общий «снаряд» на все удары о мир: у него нет калибра в обычном смысле, воронка — во
## всю грань, которой предмет пришёлся о землю.
static var _blow := StuffRound.new()

@export var stuff: StuffKind
@export var scatter_seed := 1
## Потолок числа кусков. Закон куба очень резкий, и без потолка сильный удар мгновенно
## выносит бюджет тел.
@export var most := 48
## УДАР О МИР — ВТОРОЙ ИСТОЧНИК ЭНЕРГИИ, и без него модель противоречит сама себе. Падающая
## колонна несёт на два порядка больше джоулей, чем ракета: 63 000 против 309 с девяти метров
## и 7 000 уже с одного, при пороге в 30. Пока предмет слышал только снаряд, он падал с любой
## высоты и оставался цел.
##
## Энергия считается по ПОТЕРЕ СКОРОСТИ за тик, а не по контактному импульсу: так работает на
## любом решателе и не требует `contact_monitor` на сотнях обломков.
@export var brittle_on_impact := true
## СКОЛЬКО ТЕЛ ПРОБА СОГЛАСНА РАЗВЕСТИ. Закон говорит «дроби», кадр говорит «нет»: падение
## даёт энергию в десятки раз выше порога, и КАЖДОЕ приземление крошит по максимуму. Одна
## колонна с метра высоты дала 667 тел и 111 мс физики, и высота на это почти не влияла.
##
## Это не физика, а бюджет, и он честнее любой подкрутки коэффициентов: модель остаётся
## верной, просто ей отказано в праве разорить кадр. Ограничение действует ТОЛЬКО на удары о
## мир — выстрелы игрок делает по одному и сам себе бюджет.
##
## На семистах обвал дома доламывает всё, что вообще может сломаться: целыми остаются ровно
## девять колонн первого этажа, которым падать некуда.
@export var budget := 700
## НА СКОЛЬКО КУСКОВ БЬЁТ УДАР О МИР. Много меньше, чем снаряд, и это не поблажка бюджету, а
## разница в том, КАК приложена энергия. Снаряд отдаёт её в воронку размером с калибр — оттуда
## крошка. Плита, упавшая плашмя, отдаёт ту же энергию всей своей гранью сразу, и трескается
## на несколько крупных кусков; щебня от падения плашмя не бывает.
##
## Без этого обвал большого дома съедает бюджет за две секунды: две с половиной тысячи
## элементов дают семнадцать тысяч осколков.
@export var most_on_impact := 6
## СКОЛЬКО РАЗ ПАДЕНИЕ ВООБЩЕ МОЖЕТ РАСКОЛОТЬ. Один: плита трескается, ударившись о землю, а
## её куски дальше просто лежат. Иначе дробление повторяется на каждом отскоке — шесть кусков
## в кубе это двести шестнадцать с одного элемента, и обвал дома даёт семнадцать тысяч тел.
##
## Снаряду это ограничение не писано: пуля бьёт куда целятся, и её глубину держит `max_depth`.
@export var impact_depth := 1
## КАКАЯ ДОЛЯ УДАРА ДОСТАЁТСЯ ТОМУ, ВО ЧТО ПРИЛЕТЕЛО. У удара две стороны, а до сих пор его
## чувствовал только падающий: стоящий элемент заморожен, он не тормозит — значит и не узнаёт,
## что на него рухнула крыша. Верхняя половина дома падала на нижний остов, и остов оставался
## цел, накопив ровно ноль джоулей.
##
## С этой долей появляется обрушение прогрессирующее: верх, падая, ломает низ, тот теряет
## опору и едет дальше. Именно так рушатся настоящие дома, и именно этого не хватало.
@export_range(0.0, 1.0) var passes_on := 0.5
## С КАКОГО РАЗМЕРА ОСКОЛОК БРОСАЕТ ТЕНЬ, м³. Замер при постоянном числе бодрствующих тел:
## 166 кадров в секунду с тенями от всего щебня и 284 без них — сорок два процента кадра.
## Но совсем без теней куча «плавает», не касаясь земли. Порог оставляет тень крупным кускам,
## которые держат форму кучи, и снимает с крошки, которой в тени всё равно не видно.
@export var shadow_from := 0.03

## Ручки рига, а не материала. Сущность выставляет наружу не только состояние, но и
## ВОЗДЕЙСТВИЕ: чем на неё можно повлиять снаружи, не трогая её потрохов.
var toughness_scale := 1.0
## Принудительно щебень вместо узора материала — чтобы увидеть, что узор задаёт именно он.
var grain_flat := false
## До какой глубины осколок ещё колется. Ноль — разрушение разовое, как в сорок второй.
var max_depth := 3
## Своя форма списком полупространств. У целого предмета выводится из коробки, у осколка —
## приходит от резавшей его ячейки.
var walls: Array[Plane] = []
var volume := 0.0
var depth := 0
var soaked := 0.0
## Отправлен на покой снаружи: заморожен насовсем и выведен из бюджета.
var retired := false
## Когда родился, мс. Возраст — самый простой честный признак «этот обломок уже не нужен».
var born_at := 0

var _last_velocity := Vector3.ZERO
var _counted := false
var _material: StandardMaterial3D
var _gone := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	alive += 1
	_counted = true
	born_at = Time.get_ticks_msec()
	# Уснувшее тело не опрашивается вообще — гигиена, а не спасение. Замер A-B-A на ОДНОЙ куче
	# показал, что опрос шестисот обломков не стоит ничего: 48.2 мс со скриптами и 48.2 без.
	# Дешевеет куча только от того, что засыпает: через 600 тиков спят 531 из 599 и физика
	# падает до 1.2 мс. Стена — число одновременно бодрствующих тел, а не код вокруг них.
	sleeping_state_changed.connect(_on_sleeping_state_changed)
	_rng.seed = scatter_seed
	if walls.is_empty():
		var collider := get_node("Shape") as CollisionShape3D
		var box := collider.shape as BoxShape3D
		walls = StuffShatter.box(box.size)
		volume = box.size.x * box.size.y * box.size.z
	if stuff == null:
		return
	mass = maxf(volume * stuff.density, 0.05)
	physics_material_override = stuff.rubble
	var visual := get_node("Mesh") as MeshInstance3D
	visual.material_override = stuff.shard_look if depth > 0 else stuff.body_look
	var tag := get_node_or_null("Tag") as Label3D
	if tag != null:
		tag.text = stuff.title


func _physics_process(_delta: float) -> void:
	# ЗАМОРОЗКА НЕ ВЫКЛЮЧАЕТ ОПРОС НАСОВСЕМ. Выключала — и это стоило целой механики: элемент
	# здания стоит замороженным, сам себя отключает, а когда граф его отпускает, включить
	# обратно уже некому. Падающая плита физически не могла заметить удар о землю, и обвал
	# дома не давал ни одного осколка. Осколки от выстрела крошились исправно — их никто
	# не морозил, потому и не было видно.
	#
	# Насовсем выключаемся только по своей воле: ушедшие и отправленные на покой.
	if _gone or retired or stuff == null or not brittle_on_impact:
		set_physics_process(false)
		return
	if freeze:
		# ЗАМОРОЖЕННОЕ НЕ СЧИТАЕТСЯ. Стоящий дом — это тысячи замороженных тел, и решателю они
		# не стоят ничего. Пока они попадали в бюджет дробления, тот был насыщен ещё до
		# первого выстрела: небоскрёб давал 2780 «считаемых» при бюджете 700, и обвал не
		# крошил НИЧЕГО — ни колонн, ни плит, с любой высоты.
		_uncount()
		_last_velocity = Vector3.ZERO
		return
	if not _counted:
		alive += 1
		_counted = true
	var now := linear_velocity
	var lost := 0.5 * mass * (_last_velocity.length_squared() - now.length_squared())
	var slowed := _last_velocity.length() - now.length()
	var falling := (_last_velocity.normalized()
			if _last_velocity.length_squared() > 1e-6 else Vector3.DOWN)
	_last_velocity = now
	if lost > MIN_IMPACT and slowed > 0.0:
		# СНАЧАЛА ДЕЛИМСЯ, ПОТОМ ЛОМАЕМСЯ. Передача удара не зависит от того, может ли этот
		# кусок расколоться сам: осколок на пределе глубины всё равно бьёт то, на что упал.
		# Передача внутри `_bruise`, после проверки глубины, не доходит до остова вовсе —
		# падает на него как раз мелочь.
		_share(lost, mass * slowed, falling)
		_bruise(lost, mass * slowed, falling)


func _exit_tree() -> void:
	_uncount()


## Порог этого предмета: сколько энергии он терпит, пока цел.
func limit() -> float:
	return stuff.threshold(volume) if stuff != null else INF


## ВЕРНУТЬ К ЖИЗНИ. Покой не приговор: если из-под улёгшегося обломка выбили опору, он обязан
## снова падать. Без этого замершая крошка висит в воздухе там, где раньше была стена.
func revive() -> void:
	if not retired:
		return
	retired = false
	freeze = false
	if not _counted:
		alive += 1
		_counted = true
	set_physics_process(true)


## ОТПРАВИТЬ НА ПОКОЙ. Обломок замирает и перестаёт быть физической задачей — а значит и
## занимать место в бюджете. Вызывается снаружи тем, кто держит бюджет сцены.
func retire() -> void:
	if retired:
		return
	retired = true
	_uncount()
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	set_physics_process(false)


## Принять чужой удар. Публично: бьёт не только мир, но и то, что в тебя прилетело.
func bruise(energy: float, push: float, falling: Vector3) -> void:
	_bruise(energy, push, falling)


## Воздействие снаружи. Энергия НАКАПЛИВАЕТСЯ: слабые удары копят повреждение, и когда сумма
## перевалит порог, она же определяет, на сколько кусков предмет разлетится.
func hit(at: Vector3, direction: Vector3, shot: StuffRound) -> void:
	if _gone or stuff == null or shot == null:
		return
	if depth >= max_depth:
		apply_impulse(direction.normalized() * shot.momentum * 0.02, at - global_position)
		return
	soaked += stuff.soak(shot.energy, volume, shot.bite())
	var threshold := limit()
	if soaked >= threshold and stuff.pieces(soaked, volume, most) >= LEAST:
		shatter(at, direction, shot)
		return
	_wear(soaked / threshold)


func shatter(at: Vector3, direction: Vector3, shot: StuffRound, cap := -1) -> void:
	if _gone:
		return
	_gone = true
	remove_from_group("solid")

	var started := Time.get_ticks_usec()
	if soaked <= 0.0:
		soaked = stuff.soak(shot.energy, volume, shot.bite())
	var count := stuff.pieces(
			soaked / maxf(toughness_scale, 0.01), volume, cap if cap > 0 else most)
	# ОЧАГ СКОЛА СИДИТ ПОД ТОЧКОЙ КАСАНИЯ, а не в ней — примерно на два калибра, там где
	# снаряд остановился. Во-первых, так честнее. Во-вторых, точка от луча лежит РОВНО на
	# поверхности, а это формально снаружи: без поправки каждый пятый выстрел молча переносит
	# очаг в ЦЕНТР предмета, и скол идёт не из дырки.
	var into: Vector3 = (global_transform.basis.inverse() * direction).normalized()
	var focus := StuffShatter.tuck(
			walls, global_transform.affine_inverse() * at + into * shot.calibre * 2.0)
	var grain := Vector3.ONE if grain_flat else stuff.grain
	# ВОРОНКА НЕ БЫВАЕТ МЕЛЬЧЕ СОБСТВЕННОЙ КРОШКИ МАТЕРИАЛА. Винтовочная воронка в три
	# сантиметра меньше бетонной щебёнки в двенадцать: зёрна в ней отбраковываются как тесные,
	# и вместо одиннадцати кусков выходит три — молча, без единого признака. Ребро крошки
	# задаёт и минимальный шаг между зёрнами.
	var least: float = pow(stuff.grit, 1.0 / 3.0)
	var seeds := StuffShatter.spread(
			walls, count, focus, maxf(shot.crater(), least), _rng, least)
	var kept := 0.0
	var born: Array[RigidBody3D] = []
	for index in seeds.size():
		var piece := StuffShatter.cell(walls, seeds, index, grain)
		# Отбрасываем только вырожденное. Порог «слишком мелкой ячейки» — это ЗЕРНИСТОСТЬ
		# материала, и она уже задана шагом между зёрнами выше. Отдельная глобальная отсечка
		# была вторым источником правды: у тонкой панели она резала законные пластины, и объём
		# переставал сходиться.
		if piece.is_empty() or float(piece["volume"]) <= 0.0:
			continue
		kept += float(piece["volume"])
		born.append(_spawn(piece))
	_push(born, at, direction, shot)
	shattered.emit(
			self,
			born,
			kept / maxf(volume, 1e-6),
			(Time.get_ticks_usec() - started) / 1000.0)
	queue_free()


func _uncount() -> void:
	if _counted:
		alive -= 1
		_counted = false


## Отдать долю удара тому, во что прилетело. Один луч по направлению падения — дешевле любого
## слежения за контактами и работает на любом решателе.
func _share(energy: float, push: float, falling: Vector3) -> void:
	if passes_on <= 0.0 or stuff == null:
		return
	var reach: float = pow(maxf(volume, 1e-6), 1.0 / 3.0) * 0.5
	var query := PhysicsRayQueryParameters3D.create(
			global_position, global_position + falling * (reach * 2.0 + 0.4))
	query.exclude = [get_rid()]
	var found := get_world_3d().direct_space_state.intersect_ray(query)
	if found.is_empty():
		return
	var other := found["collider"] as StuffSolid
	if other != null and other != self:
		other.bruise(energy * passes_on, push * passes_on, falling)


## Удар о мир проходит по тому же пути, что и попадание: энергия копится, порог решает,
## вязкость назначает число кусков. Никакого второго закона — только второй источник.
func _bruise(energy: float, push: float, falling: Vector3) -> void:
	if depth >= mini(max_depth, impact_depth):
		return
	# БЮДЖЕТ УРЕЗАЕТ ЧИСЛО КУСКОВ, А НЕ ПРАВО НА СКОЛ. Ворота «есть место — дроблю, нет — не
	# дроблю» отдают весь обвал тому, кто упал первым: плиты крошатся (12 из 12), а колонны
	# приземляются в закрытые ворота и остаются целыми (25 из 27) — при том что порог у
	# колонны НИЖЕ, то есть ломаться ей легче. На большом доме ворота захлопываются в первый
	# же миг, и здание падает с двадцатого этажа целыми блоками.
	#
	# Остаток бюджета режет число кусков — ступенька превращается в наклон. Пол в две части:
	# даже под самой тяжёлой нагрузкой предмет обязан треснуть хотя бы надвое, дешевле
	# разрушения не бывает, а «совсем не сломалось» — это уже не бюджет, а обман.
	var room: int = maxi(budget - alive, LEAST)
	# Удар о мир задевает предмет целым боком, а не точкой: воронка во всю его половину.
	var half: float = pow(maxf(volume, 1e-6), 1.0 / 3.0) * 0.5
	soaked += stuff.soak(energy, volume, SPHERE * half * half * half)
	var threshold := limit()
	# Остаток бюджета режет число кусков ТОЛЬКО в этом сколе: записанный в `most`, он навсегда
	# отнял бы у слегка стукнувшегося предмета право дробиться мелко — даже от ракеты потом.
	var cap: int = clampi(room, LEAST, most_on_impact)
	if soaked < threshold or stuff.pieces(soaked, volume, cap) < LEAST:
		_wear(soaked / maxf(threshold, 0.001))
		return
	var reach: float = pow(maxf(volume, 1e-6), 1.0 / 3.0)
	_blow.title = "удар"
	_blow.calibre = reach * 0.5
	_blow.crater_width = 1.0
	_blow.energy = energy
	_blow.momentum = push
	shatter(global_position + falling * reach * 0.5, falling, _blow, cap)


## Повреждение обязано быть ВИДНО, иначе прочность неотличима от сломанной ручки. Материал
## общий на все предметы своего рода, поэтому темнеет личная копия, а не общий ресурс.
func _wear(part: float) -> void:
	var visual := get_node("Mesh") as MeshInstance3D
	if _material == null:
		_material = (visual.material_override as StandardMaterial3D).duplicate()
		visual.material_override = _material
	_material.albedo_color = _material.albedo_color.lerp(Color(0.2, 0.17, 0.15), part * 0.08)


## РАЗДАЁМ ИМПУЛЬС СНАРЯДА, а не выдумываем силу на каждый кусок. Доля куска падает как
## 1/(1+(d/воронка)²): крошка из воронки улетает, дальние блоки едва трогаются. Сумма
## розданного равна импульсу снаряда — это приёмка, такая же проверяемая, как объём.
func _push(
		born: Array[RigidBody3D],
		at: Vector3,
		direction: Vector3,
		shot: StuffRound) -> void:
	var crater: float = maxf(shot.crater(), 0.01)
	var share := PackedFloat32Array()
	var total := 0.0
	for body in born:
		var apart: float = body.global_position.distance_to(at) / crater
		var weight := 1.0 / (1.0 + apart * apart)
		share.append(weight)
		total += weight
	if total <= 0.0:
		return
	var ahead := direction.normalized()
	for index in born.size():
		var body := born[index]
		var away := body.global_position - at
		var out := ahead * 0.45
		if away.length_squared() > 1e-8:
			out += away.normalized() * 0.55
		body.apply_central_impulse(out.normalized() * shot.momentum * share[index] / total)


func _spawn(piece: Dictionary) -> RigidBody3D:
	var body := SHARD.instantiate() as StuffSolid
	body.stuff = stuff
	body.walls = piece["walls"]
	body.volume = piece["volume"]
	body.depth = depth + 1
	body.most = most
	body.most_on_impact = most_on_impact
	body.impact_depth = impact_depth
	body.shadow_from = shadow_from
	body.max_depth = max_depth
	body.grain_flat = grain_flat
	body.toughness_scale = toughness_scale
	body.scatter_seed = _rng.randi()
	var shape := ConvexPolygonShape3D.new()
	shape.points = piece["points"]
	var collider := body.get_node("Shape") as CollisionShape3D
	collider.shape = shape
	var visual := body.get_node("Mesh") as MeshInstance3D
	visual.mesh = piece["mesh"]
	if float(piece["volume"]) < shadow_from:
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_sibling(body)
	body.global_transform = global_transform.translated_local(piece["centre"])
	return body


func _on_sleeping_state_changed() -> void:
	set_physics_process(not sleeping and not retired)
	if sleeping:
		_uncount()
	elif not retired and not _counted:
		alive += 1
		_counted = true
