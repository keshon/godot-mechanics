class_name SplitDual
extends Node3D
## ONE THING, TWO READINGS, and the two ways the engine can give them.
##
## The children are the same object as each world sees it: `Scifi` and `Fantasy`, each a mesh with
## whatever decoration hangs under it. Also the vocabulary of worlds for the whole probe: which
## layer bits a world owns, and how a subtree is put on them.
##
## LAYERS — both readings stand in the scene, each on its world's visual layer, and each camera
## draws only its own. Measured: what a camera does not see is culled before drawing, and its
## LIGHT AND SHADOW go with it. A cube on the scifi layer throws no shadow on the fantasy floor,
## neither from the sun nor from a lamp standing next to it. The shapes may differ, which is the
## reason for having two meshes at all.
##
## SHADER — one mesh on both layers, and the fragment shader reads `CAMERA_VISIBLE_LAYERS` to pick
## one of two surfaces. Half the nodes, but a shader changes only the SKIN: the shape is the scifi
## one in both worlds, and every piece of decoration is gone.

enum World {
	SCIFI,
	FANTASY,
	BOTH,
}

enum Method {
	LAYERS,
	SHADER,
}

## Visual layer bits and physics layer bits of each world — the same numbers, on purpose: a thing
## that belongs to a world is drawn on its layer and is solid on its layer. Bit 1 is shared.
const WORLD_BITS: Array[int] = [2, 4, 6]
const READING := preload("res://probes/48_split/reading.gdshader")

@export var method := Method.LAYERS:
	set(value):
		method = value
		if is_node_ready():
			_apply()

var _own_material: Material = null
var _combined := ShaderMaterial.new()

@onready var _scifi: MeshInstance3D = $Scifi
@onready var _fantasy: MeshInstance3D = $Fantasy


static func bits(of: World) -> int:
	return WORLD_BITS[of]


## Puts `root` and every visible thing under it on the given visual layers.
static func paint(root: Node, layer_bits: int) -> void:
	# `find_children` never returns the node it was called on, so the root is its own case.
	if root is VisualInstance3D:
		var own: VisualInstance3D = root
		own.layers = layer_bits
	for node in root.find_children("*", "VisualInstance3D", true, false):
		var visual: VisualInstance3D = node
		visual.layers = layer_bits


func _ready() -> void:
	add_to_group(&"split_dual")
	_own_material = _scifi.material_override
	_combined.shader = READING
	_fill("scifi", _scifi.material_override)
	_fill("fantasy", _fantasy.material_override)
	_apply()


func _apply() -> void:
	var layered := method == Method.LAYERS
	_fantasy.visible = layered
	for child in _scifi.get_children():
		var piece: Node3D = child
		piece.visible = layered
	_scifi.material_override = _own_material if layered else _combined
	paint(_scifi, bits(World.SCIFI) if layered else bits(World.BOTH))
	paint(_fantasy, bits(World.FANTASY))


## Copies a standard surface into the shader's uniforms for one world. The shader needs no
## surface of its own: what it draws is exactly what the LAYERS method would have drawn.
func _fill(prefix: String, surface: StandardMaterial3D) -> void:
	_combined.set_shader_parameter(prefix + "_albedo", surface.albedo_color)
	_combined.set_shader_parameter(prefix + "_metallic", surface.metallic)
	_combined.set_shader_parameter(prefix + "_roughness", surface.roughness)
	var glow := Color.BLACK
	if surface.emission_enabled:
		# Emission colour is authored in sRGB and scaled in linear space, which is what a plain
		# vec3 uniform receives; the albedo uniform carries `source_color` and converts itself.
		glow = surface.emission.srgb_to_linear() * surface.emission_energy_multiplier
	_combined.set_shader_parameter(prefix + "_emission", Vector3(glow.r, glow.g, glow.b))
