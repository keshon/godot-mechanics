extends RigidBody3D
class_name RuinPiece
## ОДИН ЭЛЕМЕНТ КОНСТРУКЦИИ: колонна, балка, плита, панель.
##
## Разница с мишенью из сороковой пробы принципиальная. Там предмет разваливался САМ — его
## прочность была его личным делом. Здесь элемент стоит не сам по себе, а **потому что под
## ним что-то есть**, и главное его свойство — не прочность, а СВЯЗЬ.
##
## Отсюда два состояния и ни одного промежуточного:
##
##   ДЕРЖИТСЯ — заморожен, неподвижен, проводит опору соседям;
##   ОТПУЩЕН — обычное твёрдое тело, падает и больше ничего не держит.
##
## Это и есть честная граница приёма: элемент не гнётся и не трещит. Он либо часть здания,
## либо обломок. Провисание балки — уже другая физика, и её здесь нет.

## Опора: элемент стоит на земле и держит всё остальное. Такие не падают никогда.
@export var anchored := false
@export var health := 30.0
## Сколько килограммов элемент способен держать сверх собственного веса. Ноль — не
## считается вовсе (схемы без нагрузки).
@export var capacity := 0.0

var neighbours: Array[RuinPiece] = []
var standing := true
var load_kg := 0.0
var left := 0.0

var _mat: StandardMaterial3D


func _ready() -> void:
	left = health
	add_to_group("piece")
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	var mi := get_node_or_null("Mesh") as MeshInstance3D
	if mi != null:
		_mat = mi.material_override as StandardMaterial3D


## Воздействие снаружи — как и у мишени в сороковой. Элемент не знает ни про стрелка, ни про
## заряд: ему сообщают, куда попало и насколько сильно.
func hit(at: Vector3, dir: Vector3, force: float, hurt: float) -> void:
	if not standing:
		# Уже падает — обычное твёрдое тело, толкаем и всё.
		apply_impulse(dir.normalized() * force, at - global_position)
		return
	left -= hurt
	if _mat != null:
		var wear := 1.0 - clampf(left / maxf(health, 0.001), 0.0, 1.0)
		_mat.albedo_color = _mat.albedo_color.lerp(Color(0.3, 0.16, 0.12), wear * 0.35)
	if left <= 0.0:
		release(dir.normalized() * force, at)


## ОТПУСТИТЬ. Элемент перестаёт быть частью здания и становится обломком. Опору он больше не
## проводит — и в этом вся механика: обрушение это не «предметы упали», а «путь до земли
## разорвался».
func release(imp := Vector3.ZERO, at := Vector3.INF) -> void:
	if not standing:
		return
	standing = false
	anchored = false
	remove_from_group("piece")
	add_to_group("debris")
	freeze = false
	if imp != Vector3.ZERO:
		apply_impulse(imp, (at if at != Vector3.INF else global_position) - global_position)


## Подсветка при показе графа опоры: держится — зелёный, висит без опоры — красный.
func mark(supported: bool, show: bool) -> void:
	if _mat == null or not standing:
		return
	_mat.emission_enabled = show
	if show:
		_mat.emission = Color(0.1, 0.55, 0.2) if supported else Color(0.7, 0.15, 0.1)
		_mat.emission_energy_multiplier = 0.6
