class_name FxPool
extends Node
## The thing probe 08 was missing: a way to have effects without having code.
##
## Eight probes in, that one had every layer written into GDScript dictionaries.
## Adding an explosion meant editing a script, which meant it could not be done
## by whoever was actually looking at the screen. That is backwards, and it is
## the usual reason a game ends up with three effects instead of thirty.
##
## Here an effect is a SCENE and nothing else. No script on it. Its timeline is
## an AnimationPlayer, its particles are inspector properties, and this node
## finds it by reading the folder. Drop a .tscn in `effects/`, run, and it is
## in the list. Copy an existing one, change the colours, and you have a second.
##
## In a real project this would be an autoload, so anything could call
## `FxPool.play("spark", position)` from anywhere. It is a plain node here only
## so it does not attach itself to the other eight probes.

const FOLDER := "res://probes/09_fx/effects/"
## The animation every effect scene is expected to have. This is the whole
## contract between an effect and this node: one AnimationPlayer called `Anim`,
## one animation called `play`. A convention costs nothing and replaces an
## interface, a base class and a script per effect.
const ANIM := "play"

@export var world_path: NodePath = ^"../Effects"

## How many effect nodes were ever actually created.
var built := 0
## How many times one came back out of the pool instead.
var reused := 0
## How many are on screen right now.
var live := 0

var _scenes := {}
var _pool := {}

@onready var _world: Node3D = get_node(world_path)


## An orthonormal basis whose +Y points along `up`. The other two axes only
## have to be perpendicular and consistent; nothing here cares where they face,
## so any perpendicular will do — except one parallel to `up`, hence the check.
static func _upright(up: Vector3) -> Basis:
	var y := up.normalized()
	if y.is_zero_approx():
		return Basis.IDENTITY
	var x := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.99 else Vector3.FORWARD
	var z := x.cross(y).normalized()
	return Basis(y.cross(z).normalized(), y, z)


func _ready() -> void:
	rescan()


func _exit_tree() -> void:
	# Pooled nodes are out of the tree, so nothing else will ever free them.
	for bucket in _pool.values():
		for node in bucket:
			node.free()


## Read the folder and register whatever is in it, keyed by file name. Public
## because the range calls it at runtime: that is the promise of the folder
## made good, and a private method reached in from outside is no promise at all.
##
## Note both extensions. In the editor a scene is a .tscn; once the project is
## exported it has been packed and turned into a .scn, and a scan that only
## looked for .tscn would find an empty folder in the shipped game and nowhere
## else. That is a nasty one to meet late.
func rescan() -> void:
	for file in DirAccess.get_files_at(FOLDER):
		if not (file.ends_with(".tscn") or file.ends_with(".scn")):
			continue
		_scenes[file.get_basename().to_lower()] = load(FOLDER + file)


func names() -> Array:
	var found := _scenes.keys()
	found.sort()
	return found


func pooled(effect: String) -> int:
	return (_pool[effect] as Array).size() if _pool.has(effect) else 0


## Put one on screen, standing on the surface it was told about.
##
## The normal is the part that was missing at first, and it showed: sparks flew
## straight up whatever they had just bounced off. An impact effect is not at a
## POINT, it is on a SURFACE, and the surface decides which way is out.
##
## Every effect here is built spraying along its own +Y, so aligning that axis
## with the normal is the whole of it. Nothing in the effect scenes changed.
func play(effect: String, at: Vector3, normal := Vector3.UP) -> Node3D:
	if not _scenes.has(effect):
		push_warning("no effect called '%s'" % effect)
		return null

	var node: Node3D
	var bucket: Array = _pool.get(effect, [])
	if bucket.is_empty():
		node = (_scenes[effect] as PackedScene).instantiate()
		node.set_meta(&"fx", effect)
		# Connected once, at birth. Connecting on every play would stack up
		# handlers and the same effect would be returned to the pool five times.
		var animation: AnimationPlayer = node.get_node(^"Anim")
		animation.animation_finished.connect(_on_animation_finished.bind(node))
		built += 1
	else:
		node = bucket.pop_back()
		reused += 1

	_world.add_child(node)
	node.global_transform = Transform3D(_upright(normal), at)
	live += 1
	(node.get_node(^"Anim") as AnimationPlayer).play(ANIM)
	return node


## An effect is never destroyed, only put away.
##
## Instantiating a scene costs real time — unpacking, building nodes, making
## materials — and a firefight wants hundreds a minute. Taking it out of the
## tree stops it processing and stops it drawing, which is all "gone" has to
## mean.
func _on_animation_finished(_which: StringName, node: Node3D) -> void:
	_world.remove_child(node)
	live -= 1
	var effect: String = node.get_meta(&"fx")
	if not _pool.has(effect):
		_pool[effect] = []
	_pool[effect].append(node)
