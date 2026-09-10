class_name ForestGround
extends RefCounted
## ЗЕМЛЯ ПОД ЛЕСОМ. Намеренно скучная: пологие холмы, один материал. Проба про лес, а не про
## поверхность — 35-я уже ответила, из чего та собирается, и повторять её здесь значило бы
## размыть вопрос.
##
## Одно требование к ней всё же есть: **не быть плоской**. На идеальной плоскости стволы
## выстраиваются в одну линию по низу экрана, и это читается как декорация даже при
## идеальном лесе. Небольшой уклон ломает линию — и лес немедленно становится глубже.

const SIZE := 260.0
const CELLS := 130

var mesh: ArrayMesh
var material: StandardMaterial3D

var _noise := FastNoiseLite.new()


func _init() -> void:
	_noise.seed = 8080
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.008
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	material = StandardMaterial3D.new()
	material.albedo_color = Color(0.125, 0.115, 0.075)
	material.roughness = 1.0
	_build()


func height(x: float, z: float) -> float:
	return _noise.get_noise_2d(x, z) * 9.0


func _build() -> void:
	var cell := SIZE / float(CELLS)
	var side := CELLS + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var index := PackedInt32Array()
	var step := 1.0
	for row in side:
		for column in side:
			var x := -SIZE * 0.5 + column * cell
			var z := -SIZE * 0.5 + row * cell
			verts.append(Vector3(x, height(x, z), z))
			norms.append(Vector3(
					height(x - step, z) - height(x + step, z),
					2.0 * step,
					height(x, z - step) - height(x, z + step)).normalized())
	for row in CELLS:
		for column in CELLS:
			var corner := row * side + column
			index.append_array([
				corner, corner + 1, corner + side,
				corner + 1, corner + side + 1, corner + side,
			])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = index
	mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
