@tool
extends RigidBody3D
class_name HitTarget
## МИШЕНЬ — СУЩНОСТЬ, КОТОРУЮ БЬЮТ.
##
## Написана по соглашениям о готовности к сборке, и это первая проба, которая им следует с
## первой строки:
##
##   ввод не читает вовсе — воздействие приходит снаружи вызовом `hit()`;
##   камеры и интерфейса не имеет — это забота рига;
##   наружу выставлено ВОЗДЕЙСТВИЕ, а не только состояние;
##   опознаётся ГРУППОЙ, а не именем узла.
##
## Последнее стоит отдельного слова. Во всех тридцати восьми пробах `add_to_group` не
## встречается ни разу: породу поверхности определяли по имени. В первой мультипробе это и
## сломалось — 30-я искала `Wood`, а трасса называла плиты `Plate01`. Группа переживает и
## переименование, и переезд в чужую сцену.

@export_enum("дерево", "металл", "стекло", "камень") var material := "дерево":
	set(v):
		material = v
		_apply()

## Запас прочности. На нуле предмет разлетается кусками.
@export var health := 40.0
## На сколько кусков разваливается. Ноль — не разваливается вовсе (камень).
@export_range(0, 12, 1) var pieces := 6
## Во сколько раз этот материал глушит импульс. Стекло почти не сопротивляется, камень стоит.
@export_range(0.0, 1.0, 0.05) var give := 1.0

const LOOK := {
	"дерево": {"tint": Color(0.45, 0.31, 0.17), "rough": 0.9, "metal": 0.0},
	"металл": {"tint": Color(0.55, 0.57, 0.6), "rough": 0.35, "metal": 0.9},
	"стекло": {"tint": Color(0.62, 0.78, 0.82), "rough": 0.1, "metal": 0.2},
	"камень": {"tint": Color(0.42, 0.42, 0.44), "rough": 1.0, "metal": 0.0},
}

var left := 0.0

## Уже развалился. `queue_free()` действует только в КОНЦЕ кадра, а до тех пор узел
## остаётся в дереве и в группе: заряд, задевший мишень дважды за кадр, разваливал её
## дважды. Двенадцать мишеней давали 227 обломков вместо 75.
var _gone := false
var _mat: StandardMaterial3D


func _ready() -> void:
	left = health
	add_to_group("mishen")
	add_to_group(material)
	_apply()


func _apply() -> void:
	if not is_inside_tree():
		return
	var mi := get_node_or_null("Mesh") as MeshInstance3D
	if mi == null:
		return
	var look: Dictionary = LOOK.get(material, LOOK["дерево"])
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = look["tint"]
	_mat.roughness = look["rough"]
	_mat.metallic = look["metal"]
	if material == "стекло":
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.albedo_color.a = 0.45
	mi.material_override = _mat


## ВОТ ЭТО И ЕСТЬ ИНТЕРФЕЙС. Стрелок ничего не знает про мишень: он сообщает, куда попал,
## откуда летела пуля и сколько в ней осталось энергии. Что с этим делать — дело мишени.
##
## Импульс прикладывается В ТОЧКУ, а не в центр. Разница и есть половина ощущения: попал в
## угол — ящик закрутило, попал в середину — просто отодвинуло.
func hit(at: Vector3, dir: Vector3, energy: float, gain: float, hurt: float) -> void:
	if _gone or freeze:
		return
	var imp := HitImpact.impulse(dir, gain) * energy * give
	apply_impulse(imp, at - global_position)
	left -= HitImpact.damage(energy, hurt)
	if _mat != null:
		# Чем ближе к развалу, тем темнее и краснее: запас прочности виден без цифр.
		var wear := 1.0 - clampf(left / maxf(health, 0.001), 0.0, 1.0)
		var look: Dictionary = LOOK.get(material, LOOK["дерево"])
		_mat.albedo_color = (look["tint"] as Color).lerp(Color(0.28, 0.12, 0.08), wear * 0.8)
	if left <= 0.0:
		_break(imp)


## Чистый материал породы, без наложенного износа.
func _fresh() -> StandardMaterial3D:
	var look: Dictionary = LOOK.get(material, LOOK["дерево"])
	var m := StandardMaterial3D.new()
	m.albedo_color = look["tint"]
	m.roughness = look["rough"]
	m.metallic = look["metal"]
	if material == "стекло":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = 0.55
	return m


## РАЗВАЛ. Куски наследуют скорость целого плюс долю импульса — иначе они рассыпаются на
## месте, а обломки обязаны лететь туда же, куда летела пуля.
func _break(imp: Vector3) -> void:
	_gone = true
	remove_from_group("mishen")
	var box := (get_node("Shape") as CollisionShape3D).shape as BoxShape3D
	var size: Vector3 = box.size if box != null else Vector3.ONE
	var rng := RandomNumberGenerator.new()
	rng.seed = get_instance_id()
	for i in pieces:
		var p := RigidBody3D.new()
		p.mass = maxf(mass / maxf(pieces, 1), 0.05)
		var s := size * rng.randf_range(0.25, 0.45)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = s
		cs.shape = bs
		p.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = s
		mi.mesh = bm
		# СВОЙ материал, а не родительский. Родительский к моменту развала уже затемнён
		# износом, и осколки стекла выходили бурыми, как дерево. Излом показывает свежий
		# материал, а не измочаленную поверхность.
		mi.material_override = _fresh()
		p.add_child(mi)
		# СНАЧАЛА В ДЕРЕВО, ПОТОМ КООРДИНАТА. Узел вне дерева не знает трансформа родителя,
		# и запись в `global_position` даёт ошибку в терминале и позицию мимо.
		get_parent().add_child(p)
		p.global_position = global_position + Vector3(
			rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5),
			rng.randf_range(-0.5, 0.5)) * size * 0.5
		p.linear_velocity = linear_velocity + imp / maxf(mass, 0.1) * 0.6 \
			+ Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(0.0, 2.0),
				rng.randf_range(-1.5, 1.5))
		p.angular_velocity = Vector3(rng.randf_range(-8.0, 8.0),
			rng.randf_range(-8.0, 8.0), rng.randf_range(-8.0, 8.0))
	queue_free()
