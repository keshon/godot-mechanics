extends Node3D
class_name TyrePad
## ПЛОЩАДКА. Асфальт, его форма столкновения и отметки каждые десять метров лежат в сцене —
## их по одной штуке, у каждой есть положение, и трогать их надо мышью. Раньше всё это
## строилось в `_ready()` рига, и открытая проба показывала пустой узел.
##
## Здесь остаётся ровно то, что сценой не выражается: сетка на асфальте. Текстура — данные,
## а не размещение, и рисуется кодом.


func _ready() -> void:
	var mi := $Asphalt as MeshInstance3D
	var mat := StandardMaterial3D.new()
	# СЕТКА НУЖНА НЕ ДЛЯ КРАСОТЫ. На ровном сером асфальте скорость не читается вообще:
	# глазу не за что зацепиться, и сорок километров в час неотличимы от ста двадцати.
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.26, 0.26, 0.27))
	for i in 64:
		img.set_pixel(i, 0, Color(0.34, 0.34, 0.35))
		img.set_pixel(0, i, Color(0.34, 0.34, 0.35))
	mat.albedo_texture = ImageTexture.create_from_image(img)
	var side: float = (mi.mesh as PlaneMesh).size.x
	mat.uv1_scale = Vector3(side * 0.2, side * 0.2, 1.0)
	mat.roughness = 0.95
	mi.material_override = mat
