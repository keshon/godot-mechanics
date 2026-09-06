extends RefCounted
class_name ForestGround

## ЗЕМЛЯ ПОД ЛЕСОМ. Намеренно скучная: пологие холмы, один материал. Проба про лес, а не про
## поверхность — тридцать пятая уже ответила, из чего та собирается, и повторять её здесь
## значило бы размыть вопрос.
##
## Одно требование к ней всё же есть: **не быть плоской**. На идеальной плоскости стволы
## выстраиваются в одну линию по низу экрана, и это читается как декорация даже при идеальном
## лесе. Небольшой уклон ломает линию — и лес немедленно становится глубже.

const SIZE := 260.0
const CELLS := 130

var mesh: ArrayMesh
var material: StandardMaterial3D
var _n := FastNoiseLite.new()


func _init() -> void:
	_n.seed = 8080
	_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n.frequency = 0.008
	_n.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n.fractal_octaves = 4
	material = StandardMaterial3D.new()
	material.albedo_color = Color(0.125, 0.115, 0.075)
	material.roughness = 1.0
	_build()


func height(x: float, z: float) -> float:
	return _n.get_noise_2d(x, z) * 9.0


func _build() -> void:
	var cell := SIZE / float(CELLS)
	var side := CELLS + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in side:
		for i in side:
			var x := -SIZE * 0.5 + i * cell
			var z := -SIZE * 0.5 + j * cell
			verts.append(Vector3(x, height(x, z), z))
			var d := 1.0
			norms.append(Vector3(height(x - d, z) - height(x + d, z), 2.0 * d,
				height(x, z - d) - height(x, z + d)).normalized())
	for j in CELLS:
		for i in CELLS:
			var a := j * side + i
			idx.append_array([a, a + 1, a + side, a + 1, a + side + 1, a + side])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
