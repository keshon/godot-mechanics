class_name DetailScatter
extends RefCounted
## РАЗБРОСАННАЯ МЕЛОЧЬ. Камни и трава — единственный слой детализации, который добавляет
## НАСТОЯЩУЮ геометрию, и потому единственный, который приходится честно отсекать по
## расстоянию. Остальные слои живут в шейдере и гаснут сами.
##
## КЛЕТКАМИ, А НЕ ОДНИМ СПИСКОМ. Два `MultiMesh` на всю карту рисуют все двадцать тысяч
## кустов всегда, куда бы игрок ни ушёл, и отсечь часть списка нельзя:
## `visible_instance_count` обрезает ХВОСТ, а хвост не имеет отношения к тому, что далеко.
## Значит нужна пространственная нарезка — та же мысль, что у чанков рельефа в 34-й, только
## вместо земли трава.
##
## У ТРАВЫ И КАМНЕЙ РАЗНАЯ ДАЛЬНОСТЬ. Трава мелкая: за полсотни метров она занимает меньше
## пикселя и превращается в мерцающий мусор — тот самый, который в замере алиасинга
## оказался главным источником шума. Камни крупнее и живут дальше. Одна дальность на всё —
## это либо лысая земля вблизи, либо кипящая каша вдали.

const CELL := 32.0

var placed := 0
var visible_now := 0
var grass_range := 46.0
var rocks_range := 110.0
var showing := true

## Каждая: {at, rocks, grass}.
var _cells: Array[Dictionary] = []
var _random := RandomNumberGenerator.new()


func setup(ground: DetailGround, root: Node3D) -> void:
	_random.seed = 31337
	var half := DetailGround.SIZE * 0.5
	var buckets := {}
	for i in 40000:
		var x := _random.randf_range(-half + 4.0, half - 4.0)
		var z := _random.randf_range(-half + 4.0, half - 4.0)
		var normal := ground.normal_at(x, z)
		var kind := -1
		if normal.y < 0.86 and _random.randf() < 0.35:
			kind = 0
		elif normal.y > 0.9 and _random.randf() < 0.55:
			kind = 1
		if kind < 0:
			continue
		var key := Vector2i(
				int(floor((x + half) / CELL)), int(floor((z + half) / CELL)))
		if not buckets.has(key):
			buckets[key] = [[], []]
		buckets[key][kind].append(Vector3(x, ground.height(x, z), z))
		placed += 1

	var rock_mesh := _rock_mesh()
	var blade_mesh := _blade_mesh()
	var rock_material := _make_material(Color(0.34, 0.32, 0.30), 0.55, false)
	var grass_material := _make_material(Color(0.30, 0.40, 0.18), 0.9, true)
	for key in buckets:
		_cells.append({
			"at": Vector3((key.x + 0.5) * CELL - half, 0.0, (key.y + 0.5) * CELL - half),
			"rocks": _make_field(
					root, rock_mesh, rock_material, buckets[key][0], 0.6, 1.7),
			"grass": _make_field(
					root, blade_mesh, grass_material, buckets[key][1], 0.75, 1.35),
		})


## Клетка целиком видима или целиком нет. Радиус меряется до ЦЕНТРА клетки с запасом в её
## половину диагонали — иначе трава пропадала бы прямо под ногами на границе.
func update(eye: Vector3) -> void:
	visible_now = 0
	var margin := CELL * 0.71
	for cell in _cells:
		var at: Vector3 = cell["at"]
		var away := Vector2(at.x - eye.x, at.z - eye.z).length() - margin
		var rocks: MultiMeshInstance3D = cell["rocks"]
		var grass: MultiMeshInstance3D = cell["grass"]
		rocks.visible = showing and away < rocks_range
		grass.visible = showing and away < grass_range
		if rocks.visible:
			visible_now += rocks.multimesh.instance_count
		if grass.visible:
			visible_now += grass.multimesh.instance_count


func cells() -> int:
	return _cells.size()


func _make_material(tint: Color, rough: float, two_sided: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = rough
	if two_sided:
		# Листья травы двусторонние, иначе половина исчезает при взгляде с изнанки.
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _make_field(
		root: Node3D,
		mesh: Mesh,
		material: Material,
		spots: Array,
		low: float,
		high: float) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = spots.size()
	for i in spots.size():
		var scale := _random.randf_range(low, high)
		var basis := Basis(Vector3.UP, _random.randf_range(0.0, TAU)).scaled(
				Vector3(scale, scale, scale))
		multi.set_instance_transform(i, Transform3D(basis, spots[i]))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.material_override = material
	root.add_child(instance)
	return instance


func _rock_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.28
	sphere.height = 0.42
	sphere.radial_segments = 6
	sphere.rings = 3
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sphere.get_mesh_arrays())
	return mesh


## ПУЧОК, А НЕ КАРТОНКА. Один плоский квадрат читался как зелёная карточка в земле. Три
## узких сужающихся листа веером дают силуэт с любой стороны и стоят столько же.
func _blade_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var index := PackedInt32Array()
	for blade in 3:
		var angle := TAU * float(blade) / 3.0 + 0.4
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-out.z, 0.0, out.x) * 0.022
		var first := verts.size()
		verts.append(-side)
		verts.append(side)
		verts.append(Vector3(0.0, 0.34, 0.0) + out * 0.10)
		var normal := out.cross(Vector3.UP).normalized()
		norms.append(normal)
		norms.append(normal)
		norms.append(normal)
		index.append_array([first, first + 1, first + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
