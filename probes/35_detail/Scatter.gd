extends RefCounted
class_name DetailScatter

## РАЗБРОСАННАЯ МЕЛОЧЬ. Камни и трава — единственный слой детализации, который добавляет
## НАСТОЯЩУЮ геометрию, и потому единственный, который приходится честно отсекать по
## расстоянию. Остальные слои живут в шейдере и гаснут сами.
##
## КЛЕТКАМИ, А НЕ ОДНИМ СПИСКОМ. Первая версия держала два `MultiMesh` на всю карту и
## рисовала все двадцать тысяч кустов всегда, куда бы игрок ни ушёл. Отсечь часть списка
## нельзя: `visible_instance_count` обрезает ХВОСТ, а хвост не имеет отношения к тому, что
## далеко. Значит нужна пространственная нарезка — та же мысль, что у чанков рельефа в
## тридцать четвёртой пробе, только вместо земли трава.
##
## У ТРАВЫ И КАМНЕЙ РАЗНАЯ ДАЛЬНОСТЬ. Трава мелкая: за полсотни метров она занимает меньше
## пикселя и превращается в мерцающий мусор — тот самый, который в замере алиасинга оказался
## главным источником шума. Камни крупнее и живут дальше. Одна дальность на всё — это либо
## лысая земля вблизи, либо кипящая каша вдали.

const CELL := 32.0
const GRID := 8

var placed := 0
var visible_now := 0
var grass_range := 46.0
var rocks_range := 110.0

var _cells: Array = []      # [{"pos": Vector3, "rocks": MMI, "grass": MMI}]
var _rng := RandomNumberGenerator.new()
var _on := true


func setup(g, root: Node3D) -> void:
	_rng.seed = 31337
	var half: float = g.SIZE * 0.5
	var buckets := {}
	for i in 40000:
		var x := _rng.randf_range(-half + 4.0, half - 4.0)
		var z := _rng.randf_range(-half + 4.0, half - 4.0)
		var n: Vector3 = g.normal_at(x, z)
		var kind := -1
		if n.y < 0.86 and _rng.randf() < 0.35:
			kind = 0
		elif n.y > 0.9 and _rng.randf() < 0.55:
			kind = 1
		if kind < 0:
			continue
		var k := Vector2i(int(floor((x + half) / CELL)), int(floor((z + half) / CELL)))
		if not buckets.has(k):
			buckets[k] = [[], []]
		buckets[k][kind].append(Vector3(x, g.height(x, z), z))
		placed += 1

	var rock_mesh := _rock_mesh()
	var blade_mesh := _blade_mesh()
	var rock_mat := _mat(Color(0.34, 0.32, 0.30), 0.55, false)
	var grass_mat := _mat(Color(0.30, 0.40, 0.18), 0.9, true)
	for k in buckets:
		var centre := Vector3((k.x + 0.5) * CELL - half, 0.0, (k.y + 0.5) * CELL - half)
		_cells.append({
			"pos": centre,
			"rocks": _make(root, rock_mesh, rock_mat, buckets[k][0], 0.6, 1.7),
			"grass": _make(root, blade_mesh, grass_mat, buckets[k][1], 0.75, 1.35),
		})


func _mat(c: Color, rough: float, two_sided: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if two_sided:
		# Листья травы двусторонние, иначе половина исчезает при взгляде с изнанки.
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _make(root: Node3D, mesh: Mesh, mat: Material, pos: Array,
		lo: float, hi: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = pos.size()
	for i in pos.size():
		var s := _rng.randf_range(lo, hi)
		var b := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, Transform3D(b, pos[i]))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	root.add_child(mi)
	return mi


func _rock_mesh() -> ArrayMesh:
	var s := SphereMesh.new()
	s.radius = 0.28
	s.height = 0.42
	s.radial_segments = 6
	s.rings = 3
	var a := ArrayMesh.new()
	a.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s.get_mesh_arrays())
	return a


## ПУЧОК, А НЕ КАРТОНКА. Один плоский квадрат читался как зелёная карточка в земле. Три
## узких сужающихся листа веером дают силуэт с любой стороны и стоят столько же.
func _blade_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for b in 3:
		var a := TAU * float(b) / 3.0 + 0.4
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-dir.z, 0.0, dir.x) * 0.022
		var base := verts.size()
		verts.append(-side)
		verts.append(side)
		verts.append(Vector3(0.0, 0.34, 0.0) + dir * 0.10)
		var n := dir.cross(Vector3.UP).normalized()
		norms.append(n); norms.append(n); norms.append(n)
		idx.append_array([base, base + 1, base + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Клетка целиком видима или целиком нет. Радиус меряется до ЦЕНТРА клетки с запасом в её
## половину диагонали — иначе трава пропадала бы прямо под ногами на границе.
func update(eye: Vector3) -> void:
	visible_now = 0
	var margin := CELL * 0.71
	for c in _cells:
		var d: float = Vector2(c["pos"].x - eye.x, c["pos"].z - eye.z).length() - margin
		var r: bool = _on and d < rocks_range
		var g: bool = _on and d < grass_range
		c["rocks"].visible = r
		c["grass"].visible = g
		if r:
			visible_now += c["rocks"].multimesh.instance_count
		if g:
			visible_now += c["grass"].multimesh.instance_count


func set_on(on: bool) -> void:
	_on = on


func cells() -> int:
	return _cells.size()
