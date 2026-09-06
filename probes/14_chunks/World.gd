extends Node3D

# 14 — a level made of hand-made pieces.
#
# The pieces live in the scene under Library, hidden. Each one is a normal Node3D you
# can open and edit: a Floor whose BoxMesh size IS the footprint, and Marker3D gates
# whose -Z points out. Add a node there, press R, and it starts showing up in levels.
#
# This file reads that library into plain dictionaries, hands them to Layout.gd, and
# instantiates whatever comes back. Layout.gd never sees a node.

@export_range(4, 60) var target := 22
## half the side of the plot everything must fit inside. shrink it and watch
## the solver start taking pieces back off.
@export_range(12.0, 70.0) var extent := 30.0
## how many pieces the solver may take back off before it settles for less
@export_range(0, 20000) var budget := 600
@export_range(20.0, 120.0) var view_size := 60.0
## draw the rim wall around each piece, with a gap at every gate that got used
@export var walls := true

var seed_value := 5
var ms := 0.0

var _layout := ChunkLayout.new()
var _lib: Array = []
var _focus := Vector3.ZERO
var _sig := ""


func _ready() -> void:
	$Library.visible = false
	_lib = _read_library()
	_rebuild()


func _process(delta: float) -> void:
	var pan := Vector3(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		0.0,
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
	if pan != Vector3.ZERO:
		_focus += Basis.from_euler(Vector3(0, PI * 0.25, 0)) * pan * delta * view_size * 0.8
	_camera()
	var now := "%d|%d|%.1f|%d|%s" % [seed_value, target, extent, budget, walls]
	if now != _sig:
		_sig = now
		_rebuild()
	_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				seed_value = randi() & 0xFFFF
			KEY_LEFT:
				seed_value -= 1
			KEY_RIGHT:
				seed_value += 1
			KEY_UP:
				target = mini(target + 2, 60)
			KEY_DOWN:
				target = maxi(target - 2, 4)
			KEY_Q:
				extent = maxf(extent - 2.0, 12.0)
			KEY_E:
				extent = minf(extent + 2.0, 70.0)
			KEY_G:
				walls = not walls
			KEY_R:
				_lib = _read_library()
				_sig = ""
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			view_size = maxf(view_size - 4.0, 20.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			view_size = minf(view_size + 4.0, 120.0)


# --- the library is a scene, not a table --------------------------------------

func _read_library() -> Array:
	var lib: Array = []
	for node in $Library.get_children():
		var box: BoxMesh = (node.get_node("Floor") as MeshInstance3D).mesh
		var gates: Array[Transform3D] = []
		var kinds := PackedStringArray()
		for child in node.get_children():
			if not str(child.name).begins_with("Gate"):
				continue
			gates.append((child as Node3D).transform)
			kinds.append(str(child.get_meta("kind", "std")))
		lib.append({
			"name": str(node.name),
			"size": Vector2(box.size.x, box.size.z),
			"gates": gates,
			"kinds": kinds,
			"max_uses": int(node.get_meta("max_uses", 99)),
			"node": node,
		})
	return lib


func _rebuild() -> void:
	var t0 := Time.get_ticks_usec()
	_layout.solve(_lib, seed_value, target, extent, budget)
	ms = (Time.get_ticks_usec() - t0) / 1000.0

	for child in $Board.get_children():
		child.free()
	for p in _layout.placed:
		var src: Node3D = _lib[p["chunk"]]["node"]
		var copy: Node3D = src.duplicate()
		$Board.add_child(copy)
		copy.visible = true
		copy.transform = p["xform"]
	_build_walls()

	$Limit.scale = Vector3(extent * 2.0, 1.0, extent * 2.0)
	_focus = Vector3.ZERO
	view_size = clampf(extent * 1.55, 20.0, 120.0)


func _build_walls() -> void:
	var at: Array[Transform3D] = []
	if walls:
		for p in _layout.placed:
			var r: Rect2 = p["rect"]
			for x in range(roundi(r.position.x), roundi(r.end.x)):
				_seg(Vector3(x + 0.5, 0.45, r.position.y), 0.0, at)
				_seg(Vector3(x + 0.5, 0.45, r.end.y), 0.0, at)
			for z in range(roundi(r.position.y), roundi(r.end.y)):
				_seg(Vector3(r.position.x, 0.45, z + 0.5), PI * 0.5, at)
				_seg(Vector3(r.end.x, 0.45, z + 0.5), PI * 0.5, at)
	var mm: MultiMesh = $Walls.multimesh
	mm.instance_count = at.size()
	for i in at.size():
		mm.set_instance_transform(i, at[i])


func _seg(at: Vector3, yaw: float, out: Array[Transform3D]) -> void:
	for d in _layout.doors:
		if absf(d.x - at.x) < 1.0 and absf(d.z - at.z) < 1.0:
			return  # a gate that got used is a doorway, so leave the hole
	out.append(Transform3D(Basis.from_euler(Vector3(0, yaw, 0)), at))


func _camera() -> void:
	var cam: Camera3D = $Camera
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = view_size
	cam.position = _focus + Vector3(1.0, 1.0, 1.0).normalized() * 160.0
	cam.look_at(_focus, Vector3.UP)


func _hud() -> void:
	$Ui/Hud/Big.text = "SEED %d" % seed_value
	var t := "[table=2]"
	t += "[cell]plot  [/cell][cell]%.0f x %.0f[/cell]" % [extent * 2.0, extent * 2.0]
	t += "[cell]pieces asked for  [/cell][cell]%d[/cell]" % target
	t += "[cell]pieces placed  [/cell][cell]%d[/cell]" % _layout.placed.size()
	t += "[cell]backtracks  [/cell][cell]%d of %d%s[/cell]" % [_layout.backtracks, budget,
		"   RAN OUT" if _layout.spent else ""]
	t += "[cell]gates walled up  [/cell][cell]%d[/cell]" % _layout.capped
	t += "[cell]fits tested  [/cell][cell]%d[/cell]" % _layout.tried
	t += "[cell]solved in  [/cell][cell]%.2f ms[/cell]" % ms
	t += "[/table]\n\n"
	var row := ""
	for i in _lib.size():
		row += "%s %d   " % [_lib[i]["name"], _layout.uses[i]]
	t += row
	$Ui/Hud/Detail.text = t
